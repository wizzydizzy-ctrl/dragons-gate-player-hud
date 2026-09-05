local Colorizer={}; Colorizer.__index=Colorizer

local defaultColors={room={224,184,79},label={139,45,45},direction={191,91,33},gold={224,184,79},silver={192,192,192},portal={55,190,200},attack={205,62,62},damage={255,70,70},danger={205,135,45},recovery={90,165,105},upkeep={185,105,45},spell={145,95,190},discovery={225,185,70},illumination={220,200,85},darkness={105,120,140}}
local directions={north=true,northeast=true,east=true,southeast=true,south=true,southwest=true,west=true,northwest=true,up=true,down=true,['in']=true,out=true,n=true,ne=true,e=true,se=true,s=true,sw=true,w=true,nw=true,u=true,d=true}
local travelNouns={door=true,doors=true,gate=true,gates=true,arch=true,arches=true,portal=true,portals=true,staircase=true,staircases=true,stairs=true,ladder=true,ladders=true,trapdoor=true,trapdoors=true,bridge=true,bridges=true,tunnel=true,tunnels=true,passage=true,passages=true,entrance=true,entrances=true,exit=true,exits=true}
local attackVerbs={attacks=true,swings=true,slashes=true,stabs=true,bites=true,claws=true,kicks=true,strikes=true,shoots=true,breathes=true,charges=true,pounces=true,throws=true}

local function segment(first,last,kind,colors)
  return {start=first,length=last-first+1,kind=kind,color=colors[kind]}
end

local function whole(line,kind,colors)
  local first=line:find("%S"); local last=line:match(".*()%S")
  return first and last and {segment(first,last,kind,colors)} or nil
end

local function portalSegment(line,lower,colors)
  if not lower:match("%f[%a]is here%.[%s]*$") and not lower:match("%f[%a]are here%.[%s]*$") then return nil end
  local contentLast=lower:match(".*()%S")
  if not contentLast then return nil end
  local clauseStart=1
  for index=1,contentLast-1 do if line:sub(index,index):match("[%.!?]") then clauseStart=index+1 end end
  while clauseStart<=#line and line:sub(clauseStart,clauseStart):match("%s") do clauseStart=clauseStart+1 end
  local clause=lower:sub(clauseStart,contentLast)
  if not clause:match("^an?%s") and not clause:match("^the%s") then return nil end
  for _,word in ipairs({"blocking","guarding","beside","near"}) do if clause:match("%f[%a]"..word.."%f[%A]") then return nil end end
  local subject=clause:match("^(.-)%s+is here%.$") or clause:match("^(.-)%s+are here%.$") or ""
  local hasTravelNoun=false
  for word in subject:gmatch("%a+") do if travelNouns[word] then hasTravelNoun=true; break end end
  if not hasTravelNoun then return nil end
  return {segment(clauseStart,contentLast,"portal",colors)}
end

local function specialSegments(line,lower,colors)
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
  return portalSegment(line,lower,colors)
end

function Colorizer.parse(line,colors)
  colors=colors or defaultColors
  if type(line)~="string" or line=="" then return nil end
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
    return special
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
  return #result>0 and result or nil
end

function Colorizer.new(adapter,enabled,settings)
  settings=type(settings)=="table" and settings or {}
  local colors={room=settings.room_color or defaultColors.room,label=settings.label_color or defaultColors.label,direction=settings.direction_color or defaultColors.direction,gold=settings.gold_color or defaultColors.gold,silver=settings.silver_color or defaultColors.silver,portal=settings.portal_color or defaultColors.portal,attack=settings.attack_color or defaultColors.attack,damage=settings.damage_color or defaultColors.damage,danger=settings.danger_color or defaultColors.danger,recovery=settings.recovery_color or defaultColors.recovery,upkeep=settings.upkeep_color or defaultColors.upkeep,spell=settings.spell_color or defaultColors.spell,discovery=settings.discovery_color or defaultColors.discovery,illumination=settings.illumination_color or defaultColors.illumination,darkness=settings.darkness_color or defaultColors.darkness}
  local legacyHighlights=settings.highlights_enabled~=false
  local features={room=settings.room_enabled~=false,exits=settings.exits_enabled~=false,currency=settings.currency_enabled~=false}
  for _,kind in ipairs({"portal","attack","damage","danger","recovery","upkeep","spell","discovery","illumination"}) do
    local configured=settings[kind.."_enabled"]
    if configured==nil then features[kind]=legacyHighlights else features[kind]=configured~=false end
  end
  return setmetatable({adapter=adapter,enabled=enabled==true,colors=colors,features=features,trigger=nil,started=false},Colorizer)
end
function Colorizer:start()
  if self.started then return true end
  local ok,id=pcall(self.adapter.addColorizerTrigger,self.adapter,function(line) return self:onLine(line) end)
  if not ok then return nil,tostring(id) end
  if not id then return nil,"colorizer trigger registration failed" end
  self.trigger=id; self.started=true; return true
end
function Colorizer:onLine(line)
  if not self.started or not self.enabled then return false end
  local segments=Colorizer.parse(line,self.colors)
  if not segments then return false end
  local filtered={}
  for _,item in ipairs(segments) do
    local feature=item.kind
    if item.kind=="darkness" then feature="illumination"
    elseif item.kind=="label" or item.kind=="direction" then feature="exits"
    elseif item.kind=="gold" or item.kind=="silver" then feature="currency" end
    if self.features[feature] then filtered[#filtered+1]=item end
  end
  if #filtered==0 then return false end
  local ok,applied,err=pcall(self.adapter.applyLineColors,self.adapter,filtered)
  if not ok then return nil,tostring(applied) end
  if not applied then return nil,err or "line coloring failed" end
  return true
end
function Colorizer:setEnabled(enabled) self.enabled=enabled==true; return self.enabled end
function Colorizer:setFeature(name,enabled)
  if name=="highlights" then
    for _,kind in ipairs({"portal","attack","damage","danger","recovery","upkeep","spell","discovery","illumination"}) do self.features[kind]=enabled==true end
    return enabled==true
  end
  if self.features[name]==nil then return nil,"unknown color feature" end
  self.features[name]=enabled==true; return self.features[name]
end
function Colorizer:toggle() return self:setEnabled(not self.enabled) end
function Colorizer:status()
  local result={enabled=self.enabled,started=self.started,trigger=self.trigger}
  for key,value in pairs(self.features) do result[key]=value end
  result.highlights=result.portal and result.attack and result.damage and result.danger and result.recovery and result.upkeep and result.spell and result.discovery and result.illumination
  return result
end
function Colorizer:shutdown()
  local id=self.trigger; self.trigger=nil; self.started=false
  if id then local ok,err=pcall(self.adapter.killTrigger,self.adapter,id); if not ok then return nil,tostring(err) end end
  return true
end

return Colorizer
