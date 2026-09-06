local Parser={}
local ATTRS={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"}
local RANKS={awful="Awful",poor="Poor",low="Low",aver="Aver",fair="Fair",good="Good",great="Great"}
local function clean(value)
  return tostring(value or ""):gsub("\27%[[%d;]*m",""):gsub("\27%[[%d;]*[A-Za-z]",""):gsub("%s+$","")
end
local function isPrompt(value)
  local line=clean(value)
  return line:match("^>%s*$")~=nil or line:match("^%[%d+%]%s+%d+/%d+%s+hp,%s+%d+/%d+%s+ftg%s*>%s*$")~=nil
end
local function hasPrompt(lines) for _,raw in ipairs(lines or {}) do if isPrompt(raw) then return true end end return false end
Parser.isPrompt=isPrompt

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

function Parser.parseStat(lines)
  if not hasPrompt(lines) then return nil,"incomplete stat response" end
  local result={equipment={}}; local reading=false
  for _,raw in ipairs(lines or {}) do
    local line=clean(raw)
    result.body_armor=result.body_armor or tonumber(line:match("^Body Armor:%s*(%d+)%%%."))
    local orv,dr,move,max,damage,stance=line:match("^OR:%s*(%d+)%s+DR:%s*(%d+)%s+Move Rate:%s*(%d+)/(%d+)%s+UDs%s+Dam Bonus:%s*(%S+)%s+Stance:%s*(%S+)")
    if orv then result.or_rating=tonumber(orv); result.dr=tonumber(dr); result.move={current=tonumber(move),maximum=tonumber(max)}; result.damage_bonus=damage; result.stance=stance end
    local position=line:match("^You are in the (.-) of the area!$"); if position then result.area_position=position end
    if line:find("novice protection",1,true) then result.novice_protected=true end
    if line:find("Equipment Readied",1,true) then reading=true
    elseif reading and line:match("^%s+%S") then local item=line:match("^%s+(.+)%.$"); if item then result.equipment[#result.equipment+1]=item end end
  end
  if not result.body_armor and not result.or_rating then return nil,"unrecognized stat response" end
  return result
end

function Parser.parseInfo(lines)
  local result={physical={},attributes={}}
  for i,raw in ipairs(lines or {}) do
    local line=clean(raw)
    local full,description,age,alignment,sex,stageAndRace,height,weight=line:match("^You are (.-), (.-) (%d+) year old (%S+) (%S+) (.-)%.%s+You are (.-) and weigh (%d+) lbs%.")
    if full then
      local stage,race=stageAndRace:match("^(.-)%s+(%S+)$")
      if stage and race then result.character={full_name=full,alignment=alignment,race=race}; result.physical={description=description,age=tonumber(age),sex=sex,life_stage=stage,height=height,weight=tonumber(weight)} end
    end
    if line:match("^%s*Str%s+Int%s+Wis%s+Dex%s+Agi%s+Con%s+Cha%s+Wil%s+Voi%s+Per%s+App%s+MP%s*$") or line:match("^%s*Str%s+Int%s+Wis%s+Dex%s+Agi%s+Con%s+Cha%s+Wil%s+Voi%s+Per%s+App%s*$") then
      for offset=1,8 do
        local values={}; local valid=true
        for value in clean(lines[i+offset] or ""):gmatch("[%a]+") do local rank=RANKS[value:lower()]; if not rank then valid=false; break end; values[#values+1]=rank end
        if valid and #values>=11 then for n,key in ipairs(ATTRS) do result.attributes[key]=values[n] end; break end
      end
    end
  end
  if not result.physical.age and not result.attributes.STR then return nil,"unrecognized info response" end
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
    local hour,minute,meridiem,day,month,year=clean(raw):match("^It is now (%d+):(%d+) ([ap]m) on the (%d+)%a* day of the (%d+)%a* month in the year (%d+)%.$")
    if hour then
      hour=tonumber(hour); if meridiem=="am" and hour==12 then hour=0 elseif meridiem=="pm" and hour<12 then hour=hour+12 end
      return {hour=hour,minute=tonumber(minute),day=tonumber(day),month=tonumber(month),year=tonumber(year)}
    end
  end
  return nil,"unrecognized time response"
end

function Parser.isComplete(command,lines)
  local fn={inventory=Parser.parseInventory,stat=Parser.parseStat,info=Parser.parseInfo,["info religion"]=Parser.parseReligion,["info mag"]=Parser.parseRunes,skill=Parser.parseSkills,time=Parser.parseTime}
  return fn[command] and hasPrompt(lines) and fn[command](lines)~=nil or false
end
return Parser
