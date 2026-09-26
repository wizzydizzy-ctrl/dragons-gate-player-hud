local Colorizer={}; Colorizer.__index=Colorizer
local Styles=require("color_styles")
local Travel=require("travel_highlights")
local Preferences=require("color_preferences")
local MAX_CUSTOM_MATCHES=256

local defaultColors={room={224,184,79},label={139,45,45},direction={191,91,33},gold={224,184,79},silver={192,192,192},portal={55,190,200},presence={136,190,153},presence_phrase={255,220,90},attack={205,62,62},damage={255,70,70},danger={205,135,45},recovery={90,165,105},upkeep={185,105,45},spell={145,95,190},discovery={225,185,70},illumination={220,200,85},darkness={105,120,140},notice={255,215,80}}
local directions={north=true,northeast=true,east=true,southeast=true,south=true,southwest=true,west=true,northwest=true,up=true,down=true,['in']=true,out=true,n=true,ne=true,e=true,se=true,s=true,sw=true,w=true,nw=true,u=true,d=true}
local attackVerbs={attacks=true,swings=true,slashes=true,stabs=true,bites=true,claws=true,kicks=true,strikes=true,shoots=true,breathes=true,charges=true,pounces=true,throws=true}
local raceColors={
  ["go-blin-al"]={153,204,255},["muatana-al"]={102,153,204},["drag-al"]={0,204,204},["fir elf"]={102,204,153},["san elf"]={153,153,255},["usil elf"]={102,102,255},["oog-ra"]={0,153,153},
  anthian={102,204,255},arachnian={204,153,255},dragon={51,153,255},draco={51,153,255},drake={51,153,255},imperial={51,153,255},firian={102,204,153},sanene={153,153,255},usilin={102,102,255},frontacian={0,153,204},flerian={102,255,204},hithual={51,204,153},human={102,255,255},leuian={0,204,255},monitanian={102,204,102},oogra={0,153,153},penthanian={0,204,153},psycian={153,204,204},secian={204,255,255},thugian={0,102,204},goblin={153,255,204},
}
local classColors={
  ["non-elemental mages"]={204,102,153},["non-elemental mage"]={204,102,153},["elemental mages"]={255,179,71},["elemental mage"]={255,179,71},["hand cleric"]={255,204,153},["heart cleric"]={255,153,153},["sword cleric"]={204,102,51},["rune mage"]={255,102,0},["air mage"]={255,204,102},["earth mage"]={204,119,34},["fire mage"]={255,51,0},["water mage"]={255,102,102},runemages={255,102,0},runemage={255,102,0},barbarian={255,102,102},bard={255,153,204},cleric={255,204,102},fighter={255,153,51},forester={255,204,51},psion={255,102,204},thief={255,102,153},
}
local function orderedKeys(values)
  local result={}; for key in pairs(values) do result[#result+1]=key end
  table.sort(result,function(a,b) if #a==#b then return a<b end return #a>#b end); return result
end
local raceNames,classNames=orderedKeys(raceColors),orderedKeys(classColors)

local function segment(first,last,kind,colors,override)
  return {start=first,length=last-first+1,kind=kind,color=override or colors[kind]}
end

local function appendNamedSegments(result,line,lower,colors)
  result=result or {}; local claimed={}
  local function scan(names,palette,kind)
    for _,name in ipairs(names) do
      local cursor=1
      while true do
        local first,last=lower:find(name,cursor,true); if not first then break end
        local before=first>1 and lower:sub(first-1,first-1) or ""; local after=last<#lower and lower:sub(last+1,last+1) or ""
        local free=not before:match("[%a%-]") and not after:match("[%a%-]")
        if free then for index=first,last do if claimed[index] then free=false; break end end end
        if free then local item=segment(first,last,kind,colors,palette[name]); item.style_id=(kind=="races" and "race:" or "class:")..name; result[#result+1]=item; for index=first,last do claimed[index]=true end end
        cursor=last+1
      end
    end
  end
  scan(raceNames,raceColors,"races"); scan(classNames,classColors,"classes")
  table.sort(result,function(a,b) return a.start<b.start end); return result
end

local function whole(line,kind,colors)
  local first=line:find("%S"); local last=line:match(".*()%S")
  return first and last and {segment(first,last,kind,colors)} or nil
end

local function specialSegments(line,lower,colors)
  local notice=lower:gsub("\r",""):match("^%s*(.-)%s*$")
  if notice:sub(1,1)=="(" and notice:sub(-1)==")" then notice=notice:sub(2,-2):match("^%s*(.-)%s*$") end
  notice=notice:gsub("%s+"," "):gsub("%.$","")
  local playerNotice=notice=="there are new version notes"
  local staffNotice=notice=="there are new version notes and gm version notes"
  if playerNotice or staffNotice then
    local parts=whole(line,"notice",colors)
    if parts then parts[1].bold=true; parts[1].underline=true; parts[1].background={80,25,20}; parts[1].display_text=staffNotice and "*** IMPORTANT - PLEASE READ: NEW VERSION NOTES AND GM VERSION NOTES ARE AVAILABLE. ***" or "*** IMPORTANT - PLEASE READ: NEW VERSION NOTES ARE AVAILABLE. ***" end
    return parts
  end
  if lower:match("^%s*this area is illuminated%.%s*$") or lower:match("^%s*this room is illuminated%.%s*$") then return whole(line,"illumination",colors) end
  if lower:match("^%s*this area is not illuminated%.%s*$") or lower:match("^%s*this room is not illuminated%.%s*$") then return whole(line,"darkness",colors) end
  if lower:match("^%s*your .+ takes %d+ points? of .+ damage!%s*$") then return whole(line,"damage",colors) end
  if lower:match("^%s*the .+ you!%s*$") then
    local narrative=lower:match("%f[%a]depicts%f[%A]") or lower:match("%f[%a]shows%f[%A]") or lower:match("%f[%a]reads%f[%A]")
    for verb in pairs(attackVerbs) do
      if not narrative and (lower:match("%s"..verb.."%s+at you!%s*$") or lower:match("%s"..verb.."%s+towards you!%s*$") or lower:match("%s"..verb.."%s+you!%s*$")) then return whole(line,"attack",colors) end
    end
  end
  if lower:match("^%s*the .+ blocks you from leaving!%s*$") or lower:match("^%s*you cannot move in that direction%.?%s*$") or lower:match("^%s*you cannot move more than %d+ uds per turn!%s*$") then return whole(line,"danger",colors) end
  if lower:match("^%s*%*%*%s*you are fully rested%.%s*$") or lower:match("^%s*%*%*%s*you are fully healed%.%s*$") then return whole(line,"recovery",colors) end
  if lower:match("^%s*you expend %d+ fatigue keeping up .+%.%s*$") then return whole(line,"upkeep",colors) end
  if lower:match("^%s*the .+ casts his gaze across the room%.%s*$") or lower:match("^%s*the .+ casts her gaze across the room%.%s*$") or lower:match("^%s*the .+ casts their gaze across the room%.%s*$") or lower:match("^%s*the .+ casts .+ at you!%s*$") or lower:match("^%s*the .+ casts .+ towards you!%s*$") then return whole(line,"spell",colors) end
  if lower:match("^%s*you have discovered .+[%!%.]%s*$") then return whole(line,"discovery",colors) end
  local travel=Travel.parsePresence(line)
  if travel then for _,item in ipairs(travel) do item.color=colors[item.kind] end end
  return travel
end

function Colorizer.parse(line,colors)
  colors=colors or defaultColors
  if type(line)~="string" or line=="" then return nil end
  line=line:gsub("\27%[[0-?]*[ -/]*[@-~]",""):gsub("\r","")
  local first,last=line:find("%[[^%[%]\r\n]+%]")
  if first and line:sub(1,first-1):match("^%s*$") and line:sub(last+1):match("^%s*$") then
    return {segment(first,last,"room",colors)}
  end
  local lower=line:lower()
  local special=specialSegments(line,lower,colors)
  if special then
    for wordFirst,word in line:gmatch("()(%a+)") do
      local normalized=word:lower()
      if normalized=="gold" or normalized=="gp" then special[#special+1]=segment(wordFirst,wordFirst+#word-1,"gold",colors)
      elseif normalized=="silver" or normalized=="sp" then special[#special+1]=segment(wordFirst,wordFirst+#word-1,"silver",colors) end
    end
    return appendNamedSegments(special,line,lower,colors)
  end
  local labelFirst,labelLast=lower:find("obvious%s+exits%s*:")
  if not labelFirst then labelFirst,labelLast=lower:find("obvious%s+paths%s*:") end
  local result={}
  local cursor=1
  local validLabel=labelFirst and line:sub(1,labelFirst-1):match("^%s*$")
  if validLabel then
    result[#result+1]=segment(labelFirst,labelLast,"label",colors)
    cursor=labelLast+1
  end
  while true do
    local wordFirst,wordLast=line:find("%a+",cursor)
    if not wordFirst then break end
    local word=line:sub(wordFirst,wordLast):lower()
    if validLabel and directions[word] then result[#result+1]=segment(wordFirst,wordLast,"direction",colors)
    elseif word=="gold" or word=="gp" then result[#result+1]=segment(wordFirst,wordLast,"gold",colors)
    elseif word=="silver" or word=="sp" then result[#result+1]=segment(wordFirst,wordLast,"silver",colors) end
    cursor=wordLast+1
  end
  result=appendNamedSegments(result,line,lower,colors)
  return #result>0 and result or nil
end

local function wordByte(byte)
  return byte and (byte>=128 or (byte>=48 and byte<=57) or (byte>=65 and byte<=90) or (byte>=97 and byte<=122) or byte==95)
end

local function customSegments(line,rules,bridge)
  local result, claimed, candidates = {}, {}, {}
  local lower=Preferences.foldCase(line)
  for index,rule in ipairs(rules) do
    if rule.enabled then candidates[#candidates+1]={rule=rule,index=index,needle=Preferences.foldCase(rule.phrase)} end
  end
  -- Longest phrase wins a custom/custom overlap; otherwise saved order wins.
  table.sort(candidates,function(a,b)
    if #a.needle==#b.needle then return a.index<b.index end
    return #a.needle>#b.needle
  end)
  for _,candidate in ipairs(candidates) do
    local needle,rule=candidate.needle,candidate.rule
    local firstWord,lastWord=wordByte(needle:byte(1)),wordByte(needle:byte(-1))
    local cursor=1
    while #result<MAX_CUSTOM_MATCHES do
      -- Plain find's fourth argument forbids Lua pattern interpretation.
      local first,last=lower:find(needle,cursor,true)
      if not first then break end
      local boundaries=(not bridge or (first<=bridge and last>bridge+1)) and
        (not firstWord or not wordByte(line:byte(first-1))) and
        (not lastWord or not wordByte(line:byte(last+1)))
      local free=boundaries
      if free then for position=first,last do if claimed[position] then free=false; break end end end
      if free then
        for position=first,last do claimed[position]=true end
        result[#result+1]={
          start=first,length=last-first+1,kind="custom",color=Styles.toRGB(rule.foreground),
          background=rule.background and Styles.toRGB(rule.background) or nil,
          bold=rule.bold,underline=rule.underline,
          rank_length=#needle,rule_index=candidate.index,
        }
      end
      cursor=first+1
    end
    if #result>=MAX_CUSTOM_MATCHES then break end
  end
  table.sort(result,function(a,b) return a.start<b.start end)
  return result
end

local function outranks(first,second)
  if first.rank_length~=second.rank_length then return first.rank_length>second.rank_length end
  return first.rule_index<second.rule_index
end

local function copySegment(item,start,length)
  local copy={}
  for key,value in pairs(item) do copy[key]=value end
  copy.start,copy.length=start,length
  return copy
end

local function verifiedLine(number,source)
  local get=rawget(_G,"getLines")
  if type(number)~="number" or number<0 or number%1~=0 or type(source)~="string" or type(get)~="function" then return false end
  local ok,lines=pcall(get,number,number+1)
  return ok and type(lines)=="table" and lines[1]==source
end

local function wrappedCustomSegments(previous,current,rules,adapter)
  if not previous or type(previous.text)~="string" or type(previous.number)~="number"
    or type(current.number)~="number" or current.number~=previous.number+1 then return {} end
  local hasPhrase=false
  for _,rule in ipairs(rules) do if rule.enabled and rule.phrase:find(" ",1,true) then hasPhrase=true; break end end
  if not hasPhrase then return {} end
  local old,now=previous.text,current.text
  local oldEnd=old:match(".*()%S")
  local nowStart=now:find("%S")
  -- Require the preceding line to approach the configured wrap column. This
  -- avoids joining ordinary consecutive messages that happen to share words.
  local threshold=80
  if adapter and type(adapter.getMainConsoleWrap)=="function" then
    local ok,columns=pcall(adapter.getMainConsoleWrap,adapter)
    if ok and type(columns)=="number" and columns>=1 then threshold=math.max(20,math.min(80,columns-10)) end
  end
  if not oldEnd or oldEnd<threshold or not nowStart or not wordByte(old:byte(oldEnd)) or not wordByte(now:byte(nowStart))
    or old:match("^%s*[%[>]" ) or now:match("^%s*[%[>]" ) then return {} end
  local joined=old:sub(1,oldEnd).." "..now:sub(nowStart)
  local matches=customSegments(joined,rules,oldEnd)
  if #matches==0 then return {} end
  -- Both absolute console rows must still contain the exact game text. The
  -- adapter verifies again when selecting; missing/stale rows color neither half.
  if not verifiedLine(previous.number,old) or not verifiedLine(current.number,now) then return {} end
  local result={}
  for _,match in ipairs(matches) do
    local group={}
    local left=copySegment(match,match.start,oldEnd-match.start+1)
    local right=copySegment(match,nowStart,match.start+match.length-oldEnd-2)
    left.source_line,left.line_number,left.wrap_group=old,previous.number,group
    right.source_line,right.line_number,right.wrap_group=now,current.number,group
    result[#result+1]=left; result[#result+1]=right
  end
  return result
end

local function selectCustomSegments(current,wrapped,parts)
  local groups={}
  for _,item in ipairs(current) do groups[#groups+1]={item} end
  local seen={}
  for _,item in ipairs(wrapped) do
    local group=item.wrap_group
    if not seen[group] then seen[group]=true; groups[#groups+1]=group end
    group[#group+1]=item
  end
  table.sort(groups,function(a,b) return outranks(a[1],b[1]) end)
  local chosen,claimed={},{}
  for _,group in ipairs(groups) do
    local blocked=#group==0 or #chosen+#group>MAX_CUSTOM_MATCHES
    for _,item in ipairs(group) do
      if not blocked then
        local row=item.line_number or -1
        local occupied=claimed[row] or {}
        for pos=item.start,item.start+item.length-1 do if occupied[pos] then blocked=true; break end end
        for _,span in ipairs(parts) do
          if span.display_text and span.source_line==item.source_line and span.line_number==item.line_number and
            span.start<item.start+item.length and item.start<span.start+span.length then blocked=true; break end
        end
      end
    end
    if not blocked then
      for _,item in ipairs(group) do
        local row=item.line_number or -1
        local occupied=claimed[row] or {}; claimed[row]=occupied
        for pos=item.start,item.start+item.length-1 do occupied[pos]=true end
        chosen[#chosen+1]=item
      end
    end
  end
  table.sort(chosen,function(a,b)
    if a.line_number==b.line_number then return a.start<b.start end
    return (a.line_number or -1)<(b.line_number or -1)
  end)
  return chosen
end

local function withoutCustomOverlap(parts,custom)
  if #custom==0 then return parts end
  local result={}
  for _,item in ipairs(parts) do
    local spans={item}
    for _,highlight in ipairs(custom) do
      if item.source_line==highlight.source_line and item.line_number==highlight.line_number then
        local remaining={}
        local customEnd=highlight.start+highlight.length
        for _,span in ipairs(spans) do
          local spanEnd=span.start+span.length
          if span.start<customEnd and highlight.start<spanEnd then
            -- Replacement notices are protected before this pass; retaining
            -- this guard prevents any future caller from deleting their text.
            if not span.display_text then
              if span.start<highlight.start then
                remaining[#remaining+1]=copySegment(span,span.start,highlight.start-span.start)
              end
              if customEnd<spanEnd then
                remaining[#remaining+1]=copySegment(span,customEnd,spanEnd-customEnd)
              end
            end
          else
            remaining[#remaining+1]=span
          end
        end
        spans=remaining
        if #spans==0 then break end
      end
    end
    for _,span in ipairs(spans) do result[#result+1]=span end
  end
  return result
end

function Colorizer.new(adapter,enabled,settings)
  settings=type(settings)=="table" and getmetatable(settings)==nil and settings or {}
  local colors={room=settings.room_color or defaultColors.room,label=settings.label_color or defaultColors.label,direction=settings.direction_color or defaultColors.direction,gold=settings.gold_color or defaultColors.gold,silver=settings.silver_color or defaultColors.silver,portal=settings.portal_color or defaultColors.portal,presence=settings.presence_color or defaultColors.presence,presence_phrase=settings.presence_phrase_color or defaultColors.presence_phrase,attack=settings.attack_color or defaultColors.attack,damage=settings.damage_color or defaultColors.damage,danger=settings.danger_color or defaultColors.danger,recovery=settings.recovery_color or defaultColors.recovery,upkeep=settings.upkeep_color or defaultColors.upkeep,spell=settings.spell_color or defaultColors.spell,discovery=settings.discovery_color or defaultColors.discovery,illumination=settings.illumination_color or defaultColors.illumination,darkness=settings.darkness_color or defaultColors.darkness,notice=settings.notice_color or defaultColors.notice}
  local legacyHighlights=settings.highlights_enabled~=false
  local features={room=settings.room_enabled~=false,exits=settings.exits_enabled~=false,currency=settings.currency_enabled~=false,races=settings.races_enabled~=false,classes=settings.classes_enabled~=false}
  for _,kind in ipairs({"portal","presence","attack","damage","danger","recovery","upkeep","spell","discovery","illumination","notice"}) do
    local configured=settings[kind.."_enabled"]
    if configured==nil then features[kind]=legacyHighlights else features[kind]=configured~=false end
  end
  local self=setmetatable({adapter=adapter,enabled=enabled==true,colors=colors,features=features,trigger=nil,started=false,travel=Travel.new(true),line_history={},custom_rules={}},Colorizer)
  local styled=self:setStyles(settings)
  if not styled then self:setStyles({}) end
  return self
end
function Colorizer:setStyles(settings)
  settings=type(settings)=="table" and getmetatable(settings)==nil and settings or {}
  local ok,err=self:setCustomRules(settings.custom_rules)
  if not ok then return nil,err end
  self.styles={}
  for _,entry in ipairs(Styles.entries()) do self.styles[entry.id]=Styles.resolve(settings,entry.id) end
  return true
end
function Colorizer:setCustomRules(rules)
  local normalized,err=Preferences.normalizeCustomRules(rules)
  if not normalized then return nil,err end
  self.custom_rules=normalized
  self._custom_rules_source=normalized
  self._custom_rules_validated=Preferences.normalizeCustomRules(normalized)
  return true
end
function Colorizer:start()
  if self.started then return true end
  local ok,id=pcall(self.adapter.addColorizerTrigger,self.adapter,function(line,number) return self:onLine(line,number) end)
  if not ok then return nil,tostring(id) end
  if not id then return nil,"colorizer trigger registration failed" end
  self.trigger=id; self.started=true; return true
end
function Colorizer:onLine(line,number)
  if not self.started or not self.enabled then self.travel=Travel.new(true); self.line_history={}; return false end
  if type(line)~="string" then return false end
  line=line:gsub("\27%[[0-?]*[ -/]*[@-~]",""):gsub("\r","")
  if #line>8192 then self.travel=Travel.new(true); self.line_history={}; return false end
  self.line_history[#self.line_history+1]={text=line,number=number}
  if #self.line_history>4 then table.remove(self.line_history,1) end
  local segments,overlays={},{}
  for _,item in ipairs(Colorizer.parse(line,self.colors) or {}) do
    if item.kind~="portal" and item.kind~="presence" and item.kind~="presence_phrase" then overlays[#overlays+1]=item end
  end
  local oldOverlays={}
  local travelParts=self.travel:onLine(line) or {}
  -- A wrapped subject without trustworthy historical row numbers is not
  -- partially painted: even its current-row "is here" suffix would mislead.
  for _,item in ipairs(travelParts) do
    if (item.line_offset or 0)<0 then
      local source=self.line_history[#self.line_history+item.line_offset]
      if not source or type(source.number)~="number" then travelParts={}; break end
    end
  end
  for _,item in ipairs(travelParts) do
    local source=self.line_history[#self.line_history+(item.line_offset or 0)]
    -- Never guess an older screen row from a relative offset: other triggers
    -- may have inserted text since the previous game line arrived.
    if source and ((item.line_offset or 0)==0 or type(source.number)=="number") then
      item.source_line=source.text; item.line_number=source.number; item.color=self.colors[item.kind]
      segments[#segments+1]=item
      if (item.line_offset or 0)<0 then
        for _,overlay in ipairs(Colorizer.parse(source.text,self.colors) or {}) do
          local narrow=overlay.kind=="gold" or overlay.kind=="silver" or overlay.kind=="races" or overlay.kind=="classes"
          local overlaps=overlay.start<item.start+item.length and item.start<overlay.start+overlay.length
          local key=tostring(source.number)..":"..overlay.start..":"..overlay.kind
          if narrow and overlaps and not oldOverlays[key] then
            oldOverlays[key]=true; overlay.source_line=source.text; overlay.line_number=source.number
            overlays[#overlays+1]=overlay
          end
        end
      end
    end
  end
  -- Broad travel phrases go first. Currency and named styles must remain
  -- visible inside them, including previously colored wrapped server lines.
  for _,item in ipairs(overlays) do segments[#segments+1]=item end
  -- Main's save path replaces custom_rules directly with a fresh validated
  -- array. Revalidate that new table once, not for every incoming game line.
  if self._custom_rules_source~=self.custom_rules then
    self._custom_rules_validated=Preferences.normalizeCustomRules(self.custom_rules) or {}
    self._custom_rules_source=self.custom_rules
  end
  local rules=self._custom_rules_validated or {}
  local custom=customSegments(line,rules)
  for _,item in ipairs(custom) do item.source_line=line; item.line_number=number end
  local previous=self.line_history[#self.line_history-1]
  local wrapped=#rules>0 and wrappedCustomSegments(previous,{text=line,number=number},rules,self.adapter) or {}
  local filtered={}
  for _,item in ipairs(segments) do
    local feature=item.kind
    if item.kind=="darkness" then feature="illumination"
    elseif item.kind=="presence_phrase" then feature="presence"
    elseif item.kind=="label" or item.kind=="direction" then feature="exits"
    elseif item.kind=="gold" or item.kind=="silver" then feature="currency" end
    local style=self.styles[item.style_id or item.kind]
    if self.features[feature] and style and style.enabled then
      item.color=Styles.toRGB(style.foreground)
      item.background=style.background and Styles.toRGB(style.background) or nil
      item.bold=style.bold; item.underline=style.underline
      item.source_line=item.source_line or line
      item.line_number=item.line_number or number
      filtered[#filtered+1]=item
    end
  end
  custom=selectCustomSegments(custom,wrapped,filtered)
  filtered=withoutCustomOverlap(filtered,custom)
  for _,item in ipairs(custom) do filtered[#filtered+1]=item end
  if #filtered==0 then return false end
  local ok,applied,err=pcall(self.adapter.applyLineColors,self.adapter,filtered)
  if not ok then return nil,tostring(applied) end
  if not applied then return nil,err or "line coloring failed" end
  return true
end
function Colorizer:setEnabled(enabled) self.enabled=enabled==true; self.travel=Travel.new(true); self.line_history={}; return self.enabled end
function Colorizer:setFeature(name,enabled)
  if name=="highlights" then
    for _,kind in ipairs({"portal","presence","attack","damage","danger","recovery","upkeep","spell","discovery","illumination","notice"}) do self.features[kind]=enabled==true end
    return enabled==true
  end
  if self.features[name]==nil then return nil,"unknown color feature" end
  self.features[name]=enabled==true; return self.features[name]
end
function Colorizer:toggle() return self:setEnabled(not self.enabled) end
function Colorizer:status()
  local result={enabled=self.enabled,started=self.started,trigger=self.trigger}
  for key,value in pairs(self.features) do result[key]=value end
  result.highlights=result.portal and result.presence and result.attack and result.damage and result.danger and result.recovery and result.upkeep and result.spell and result.discovery and result.illumination and result.notice
  return result
end
function Colorizer:shutdown()
  local id=self.trigger; self.trigger=nil; self.started=false
  if id then local ok,err=pcall(self.adapter.killTrigger,self.adapter,id); if not ok then return nil,tostring(err) end end
  return true
end

return Colorizer
