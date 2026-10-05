local Parser={}
local ATTR_ORDERS={
  {"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","PRE","PER","LUK"},
  {"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"},
}
local RANKS={awful="Awful",poor="Poor",low="Low",aver="Aver",fair="Fair",good="Good",great="Great",excel="Excel",super="Super",superb="Superb",godly="Godly"}
local GAME_MONTHS={tanei=1,odeth=2,daleth=3,majus=4,mateth=5,rina=6}
local function clean(value)
  return tostring(value or ""):gsub("\27%[[0-?]*[ -/]*[@-~]",""):gsub("%s+$","")
end
local function trim(value) return clean(value):match("^%s*(.-)%s*$") end
local function infoLine(value)
  return trim(value):gsub("^%[%d+%]%s+%d+/%d+%s+hp,%s+%d+/%d+%s+ftg%s*>%s*",""):gsub("^>%s*","")
end
local function isPrompt(value)
  local line=clean(value)
  return line:match("^>%s*$")~=nil or line:match("^%[%d+%]%s+%d+/%d+%s+hp,%s+%d+/%d+%s+ftg%s*>%s*$")~=nil
end
local function hasPrompt(lines) for _,raw in ipairs(lines or {}) do if isPrompt(raw) then return true end end return false end
Parser.isPrompt=isPrompt
local function infoBoundary(line)
  line=trim(line)
  local lower=line:lower()
  return line=="" or isPrompt(line) or lower:match("^hp:%s*") or lower:match("^str%s*$") or lower:match("^str%s+int%s+wis") or lower:match("^use:%s+info")
end
local function infoBlock(lines,startPattern,limit)
  for start=1,#lines do
    local first=infoLine(lines[start])
    if first:match(startPattern) then
      local parts={first}
      for index=start+1,math.min(#lines,start+(limit or 6)) do
        local line=infoLine(lines[index]); if infoBoundary(line) then break end; parts[#parts+1]=line
      end
      return table.concat(parts," ")
    end
  end
  return ""
end

function Parser.parseInventory(lines)
  local result={items={}}
  for _,raw in ipairs(lines or {}) do
    local line=clean(raw)
    local name,weight=line:match('^%s*%[%s*%d+%]%s+"(.-)".-%[([%d%.]+)%s+lbs?%]%s*$')
    if not name then name,weight=line:match("^%s+(.+)%s+%[([%d%.]+)%s+lbs?%]%.$") end
    if name then result.items[#result.items+1]={name=name,weight=tonumber(weight)} end
    local total=line:match("^Your inventory totals ([%d%.]+) lbs?%.$")
    if total then result.total_weight=tonumber(total); return result end
  end
  return nil,"incomplete inventory response"
end

local COMBAT_FIELDS={
  {label="Body Armor",key="body_armor",pattern="^(%d+)%%%.$"},
  {label="OR",key="or_rating",pattern="^(%d+)$"},
  {label="DR",key="dr",pattern="^(%d+)$"},
  {label="Move Rate",key="move",pattern="^(%d+)%s*/%s*(%d+)%s+UDs$"},
  {label="Dam Bonus",key="damage_bonus",pattern="^(%S+)$"},
  {label="Stance",key="stance",pattern="^([A-Za-z]+)$"},
}
local function combatStart(line)
  for _,field in ipairs(COMBAT_FIELDS) do
    if line:sub(1,#field.label+1)==field.label..":" then return true end
  end
  return false
end
local function combatRow(row,result)
  local fields={}
  for _,field in ipairs(COMBAT_FIELDS) do
    local cursor=1
    while true do
      local first,last=row:find(field.label..":",cursor,true); if not first then break end
      if first==1 or row:sub(first-1,first-1):match("%s") then fields[#fields+1]={first=first,last=last,field=field} end
      cursor=last+1
    end
  end
  table.sort(fields,function(a,b) return a.first<b.first end)
  for index,entry in ipairs(fields) do
    local value=trim(row:sub(entry.last+1,fields[index+1] and fields[index+1].first-1 or #row))
    if entry.field.key=="damage_bonus" then value=value:gsub("%s*/%s*","/") end
    local first,second=value:match(entry.field.pattern)
    if first then
      local key=entry.field.key
      if key=="move" then result.move={current=tonumber(first),maximum=tonumber(second)}
      elseif key=="damage_bonus" or key=="stance" then result[key]=first
      else result[key]=tonumber(first) end
    end
  end
end
function Parser.parseStance(value)
  local stance,tail=infoLine(value):match("^Attack strategy set to:%s*([A-Za-z]+)(.*)$")
  -- Validate the entire stance token; explanatory prose is only allowed after --.
  if stance and (tail=="" or tail:match("^%s+%-%-%s+")) then return stance end
  return nil
end
function Parser.parseStatCombat(lines)
  local result={}; local row=""; local parts=0
  for _,raw in ipairs(lines or {}) do
    local line=infoLine(raw); local stance=Parser.parseStance(raw)
    local pending=row:match(":%s*$") or row:match("/%s*$") or row:match("Move Rate:%s*%d+%s*/%s*%d+%s*$")
    local token,rest=line:match("^([A-Za-z%d/%%%.%+%-]+)%s*(.*)$")
    local continuation=pending and token and (rest=="" or combatStart(rest) or rest:match("^UDs%f[%A]") or (token=="UDs" and rest=="Dam"))
    continuation=continuation or (row:match("%f[%a]Move%s*$") and line:match("^Rate:")) or (row:match("%f[%a]Dam%s*$") and line:match("^Bonus:"))
    if stance then result.stance=stance; row=""; parts=0
    elseif combatStart(line) or (row~="" and continuation) then
      -- Bound reconstruction and only join labeled rows or unfinished field values.
      -- NPC prose never starts a combat row or an equipment/posture update.
      if parts>=16 then row=""; parts=0 end
      row=row~="" and row.." "..line or line; parts=parts+1; combatRow(row,result)
    else row=""; parts=0 end
    local position=line:match("^You are in the (.-) of the area!$"); if position then result.area_position=position end
    if line:match("^You are .-novice protection%.$") then result.novice_protected=true end
  end
  if next(result)==nil then return nil,"unrecognized stat combat response" end
  return result
end
function Parser.parseStat(lines)
  if not hasPrompt(lines) then return nil,"incomplete stat response" end
  local result=Parser.parseStatCombat(lines); if not result then return nil,"unrecognized stat response" end
  local reading=false
  for _,raw in ipairs(lines or {}) do
    local line=clean(raw)
    if infoLine(raw)=="::: Equipment Readied :::" then result.equipment={}; reading=true
    elseif reading then
      local item=line:match("^%s+(.+)%.$")
      if item then result.equipment[#result.equipment+1]=item elseif trim(line)~="" then reading=false end
    end
  end
  return result
end

function Parser.parseInfo(lines)
  lines=lines or {}
  local result={physical={},attributes={}}
  local biography=infoBlock(lines,"^You are .-,",64)
  local _,last,full,description,age,alignment,sex,stageAndRace,height,weight=biography:find('^You are ([^,"]+), ([^"]-) (%d+) year old (%S+) (%S+) (.-)%.%s+You are (.-) and weigh (%d+%.?%d*) lbs%.')
  if full then
    stageAndRace=trim(stageAndRace); local race=stageAndRace:match("(%S+)$"); local stage=trim(stageAndRace:sub(1,#stageAndRace-#tostring(race or "")))
    if race then
      result.character={full_name=full,alignment=alignment,race=race}
      result.physical={description=description,age=tonumber(age),sex=sex,life_stage=stage~="" and stage or nil,height=height,weight=tonumber(weight)}
      local tail=trim(biography:sub(last+1)):gsub("%s+"," "); local lower=tail:lower(); local stop
      for _,needle in ipairs({" hp:"," str int wis"," use: info"}) do local at=lower:find(needle,1,true); if at and (not stop or at<stop) then stop=at end end
      if stop then tail=trim(tail:sub(1,stop-1)) end; result.condition_text=tail
    end
  end
  local vitals=infoBlock(lines,"^HP:%s*",3)
  local hp,hpMax=vitals:match("HP:%s*(%d+%.?%d*)%s+of%s+(%d+%.?%d*)")
  local fatigue,fatigueMax=vitals:match("Ftg:%s*(%d+%.?%d*)%s+of%s+(%d+%.?%d*)")
  local carry,carryMax=vitals:match("Carry:%s*(%d+%.?%d*)%s+of%s+(%d+%.?%d*)%s+lbs?%.")
  if hp or fatigue or carry then result.vitals={hp=tonumber(hp),hp_max=tonumber(hpMax),fatigue=tonumber(fatigue),fatigue_max=tonumber(fatigueMax),carry=tonumber(carry),carry_max=tonumber(carryMax)} end

  local headerEnd,headerAttrs
  for _,attrs in ipairs(ATTR_ORDERS) do
    for start=1,#lines do
      local expected=1
      for index=start,math.min(#lines,start+#attrs+1) do
        local words={}; for word in trim(lines[index]):gmatch("[%a]+") do words[#words+1]=word:lower() end
        if index==start and words[1]~="str" then break end
        for _,word in ipairs(words) do
          if expected<=#attrs then
            if word~=attrs[expected]:lower() then expected=0; break end
            expected=expected+1
          end
        end
        if expected==#attrs+1 then headerEnd=index; headerAttrs=attrs; break end
        if expected==0 then break end
      end
      if headerEnd then break end
    end
    if headerEnd then break end
  end
  if headerEnd then
    for start=headerEnd+1,math.min(#lines,headerEnd+#headerAttrs+2) do
      local values={}; local index=start; local valid=true
      while #values<#headerAttrs and index<=math.min(#lines,headerEnd+#headerAttrs+2) do
        local found=0
        for word in trim(lines[index]):gmatch("[%a]+") do
          local rank=RANKS[word:lower()]; if not rank then valid=false; break end
          values[#values+1]=rank; found=found+1
        end
        if not valid or found==0 then break end
        index=index+1
      end
      if valid and #values>=#headerAttrs then for n,key in ipairs(headerAttrs) do result.attributes[key]=values[n] end; break end
    end
  end
  if not result.physical.age and not result.attributes.STR and not result.vitals then return nil,"unrecognized info response" end
  return result
end

function Parser.parseReligion(lines)
  if not hasPrompt(lines) then return nil,"incomplete religion response" end
  local result={}
  for _,raw in ipairs(lines or {}) do
    local line=clean(raw)
    local rank,deity=line:match("^You are an? (.-) follower of (.-)%.$")
    if rank then result.rank=rank; result.deity=deity end
    if line:match("^You have not yet dedicated to a deity%.$") then result.rank="None"; result.deity="None" end
    local favors=line:match("^You have earned (%d+) favors?%.$")
    if favors then result.favors=tonumber(favors) end
    local balance,alignment=line:match("^You are (.-) within your (.-) alignment%.$")
    if balance then result.balance=balance; result.alignment=alignment end
  end
  if not result.rank or not result.deity then return nil,"unrecognized religion response" end
  return result
end

function Parser.parseRunes(lines)
  local result={items={}}; local header=false; local complete=false
  for _,raw in ipairs(lines or {}) do
    local line=clean(raw)
    if line:match("^You have the following elemental runes available to you%.%.%.$") then header=true
    elseif header and isPrompt(line) then complete=true
    elseif header then
      local cursor=1
      while true do
        local first,last,name,remaining=line:find("([%a][%a%s]-)%s*%-%s*(%d+)%s+weaves?%s+remain",cursor)
        if not first then break end
        name=name:match("^%s*(.-)%s*$")
        if name~="" then result.items[#result.items+1]={name=name:gsub("^%l",string.upper),remaining=tonumber(remaining)} end
        cursor=last+1
      end
    end
  end
  if not complete then return nil,"incomplete rune response" end
  if not header then return nil,"unrecognized rune response" end
  table.sort(result.items,function(a,b) if a.remaining~=b.remaining then return a.remaining<b.remaining end; return a.name:lower()<b.name:lower() end)
  return result
end

function Parser.parseSkills(lines)
  local result={items={}}; local header=false; local complete=false
  for _,raw in ipairs(lines or {}) do
    local line=clean(raw)
    if line:match("^%s*Skill%s+Remain%s+Level%s*$") then header=true
    elseif header and isPrompt(line) then complete=true
    elseif header then
      local name,remain,level=line:match("^%s*(.-)%s+(%d+)%s+(%d+)%s*$")
      if name and name~="" then result.items[#result.items+1]={name=name:gsub("^%*",""),remain=tonumber(remain),level=tonumber(level)} end
    end
  end
  if not complete then return nil,"incomplete skill response" end
  if not header or #result.items==0 then return nil,"unrecognized skill response" end
  table.sort(result.items,function(a,b)
    if a.level~=b.level then return a.level>b.level end
    if a.remain~=b.remain then return a.remain<b.remain end
    return a.name:lower()<b.name:lower()
  end)
  return result
end

function Parser.parseTime(lines)
  if not hasPrompt(lines) then return nil,"incomplete time response" end
  for _,raw in ipairs(lines or {}) do
    local line=clean(raw)
    local day,monthName,year,hour,minute=line:match("^Today is the (%d+)%a* day of ([%a]+) in the year (%d+)%. The time is (%d+):(%d+)%.%s*$")
    if hour then
      local month=GAME_MONTHS[monthName:lower()]
      if month then return {hour=tonumber(hour),minute=tonumber(minute),day=tonumber(day),month=month,month_name=monthName,year=tonumber(year),days_per_month=60,months_per_year=6} end
    end
    local meridiem,oldDay,oldMonth,oldYear
    hour,minute,meridiem,oldDay,oldMonth,oldYear=line:match("^It is now (%d+):(%d+) ([ap]m) on the (%d+)%a* day of the (%d+)%a* month in the year (%d+)%.$")
    if hour then
      hour=tonumber(hour); if meridiem=="am" and hour==12 then hour=0 elseif meridiem=="pm" and hour<12 then hour=hour+12 end
      return {hour=hour,minute=tonumber(minute),day=tonumber(oldDay),month=tonumber(oldMonth),year=tonumber(oldYear)}
    end
  end
  return nil,"unrecognized time response"
end

function Parser.isComplete(command,lines)
  local fn={inventory=Parser.parseInventory,stat=Parser.parseStat,info=Parser.parseInfo,["info religion"]=Parser.parseReligion,["info mag"]=Parser.parseRunes,["info magic"]=Parser.parseRunes,skill=Parser.parseSkills,time=Parser.parseTime}
  if not fn[command] or type(lines)~="table" or #lines==0 or not isPrompt(lines[#lines]) then return false end
  return fn[command](lines)~=nil
end
return Parser
