local Parser=require("command_parser")
local Display={}; Display.__index=Display
Display.MAX_ROWS=128; Display.MAX_LINES=256; Display.MAX_LINE_BYTES=2048; Display.RESPONSE_TIMEOUT=5
Display.BOUNDARY_DELAY=0

-- Authoritative game catalog supplied by the user. Entries are identifiers,
-- never a list of possessed skills and never display-order ordinals.
local catalog={
  "Brawling","Sharp Weapons","Blunt Weapons","Pole Weapons","Throw Weapons","Missile Weapons",
  "Shield Parry","Quickdraw","Dodging","Focus Force","Berserk Attack","Parry Blows","Bargaining",
  "Identify Gems/Minerals","Climbing","Detect Traps","Remove Traps","Skinning","Disguise","Pick Locks",
  "Riding","Hiding","Swimming","Alchemy","Backstab","Martial Arts","Picking Pockets","Shoplifting",
  "Stealth","Poisoning","Identify Magick","Identify Weapon Quality","Play Instruments","Armor Smithing",
  "Weapon Smithing","Singing","Fletching","Tracking","Disarming","Psionics","Channeling","First Aid",
  "Body Building","Turn Undead","Draining","Biting","Clawing","Webbing","Breath Weapon",
  "Identify Armor Quality","Linguistics","Herbalism","Healing","Spellcasting","Conjuration","Delving","Stinging",
}
local function plain(value)
  return value:gsub("\27%[[0-?]*[ -/]*[@-~]",""):gsub("\r","")
end
local function name(value)
  return value:match("^%s*(.-)%s*$"):gsub("^[%*%s]+",""):gsub("%s+"," ")
end
local ids={}; for id,value in ipairs(catalog) do ids[name(value):lower()]=id end
local combatIds={
  [1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true,[11]=true,[12]=true,
  [25]=true,[26]=true,[30]=true,[39]=true,[40]=true,[41]=true,[42]=true,[43]=true,[44]=true,[45]=true,[46]=true,
  [47]=true,[48]=true,[49]=true,[53]=true,[54]=true,[55]=true,[57]=true,
}
function Display.skillId(value)
  if type(value)~="string" or #value>Display.MAX_LINE_BYTES then return nil end
  return ids[name(plain(value)):lower()]
end
function Display.displayName(value)
  local cleaned=name(plain(tostring(value or ""))):gsub("%c"," ")
  local short={["sharp weapons"]="Sharps",["blunt weapons"]="Blunts",["pole weapons"]="Poles",
    ["throw weapons"]="Throws",["missile weapons"]="Missiles"}
  return short[cleaned:lower()] or cleaned
end
function Display.category(skill)
  if skill.remain==0 then return "ready" end
  return combatIds[Display.skillId(skill.name)] and "combat" or "utility"
end
local function width(value)
  local _,points=tostring(value):gsub("[^\128-\191]","")
  return points
end
local function columnWidths(items)
  local widths={6,5,3,4}
  for _,skill in ipairs(items) do
    local values={tostring(Display.skillId(skill.name) or "?"),Display.displayName(skill.name),tostring(skill.level),tostring(skill.remain)}
    for index,value in ipairs(values) do widths[index]=math.max(widths[index],width(value)) end
  end
  return widths
end
local function columns(values,widths)
  local cells={}
  for index,value in ipairs(values) do
    local padding=string.rep(" ",math.max(0,widths[index]-width(value)))
    cells[index]=index==2 and value..padding or padding..value
  end
  return table.concat(cells,"  ")
end
function Display.format(skill,widths)
  return columns({tostring(Display.skillId(skill.name) or "?"),Display.displayName(skill.name),tostring(skill.level),tostring(skill.remain)},
    widths or columnWidths({skill}))
end
function Display.new(adapter,enabled,packageName)
  return setmetatable({adapter=adapter,enabled=enabled~=false,package_name=packageName or "DragonsGateHUD",
    started=false,generation=0,events={}},Display)
end
function Display:disarmTimer()
  self.generation=self.generation+1
  local timer=self.timer; self.timer=nil
  if timer then pcall(self.adapter.cancelTimer,self.adapter,timer) end
end
function Display:cancel()
  self:disarmTimer(); self.response=nil; self.pending=nil
end
function Display:setEnabled(enabled)
  if type(enabled)~="boolean" then return nil,"main skills display must be a boolean" end
  self:cancel(); self.enabled=enabled; return enabled
end
function Display:armTimer(delay,fn)
  self:disarmTimer()
  local generation=self.generation
  local ok,id=pcall(self.adapter.schedule,self.adapter,delay,function()
    if self.generation~=generation then return end
    self.timer=nil; fn()
  end)
  if not ok or not id then self:cancel(); return nil end
  self.timer=id; return true
end
function Display:finish()
  local response=self.response
  self:cancel()
  if not response or #response.rows==0 or not self.enabled then return end
  local items={}; for _,row in ipairs(response.rows) do items[#items+1]=row.skill end
  table.sort(items,function(a,b)
    if a.level~=b.level then return a.level>b.level end
    if a.remain~=b.remain then return a.remain<b.remain end
    return a.name:lower()<b.name:lower()
  end)
  local widths=columnWidths(items)
  local rows={{line_number=response.header.line_number,source_line=response.header.source_line,
    display_text=columns({"Number","Skill","LVL","USES"},widths),category="neutral"}}
  for index,row in ipairs(response.rows) do
    local category=Display.category(items[index])
    rows[#rows+1]={line_number=row.line_number,source_line=row.source_line,display_text=Display.format(items[index],widths),
      category=category,style_id="skill_"..category}
  end
  self.pending=rows
  -- Defer until the complete raw response has reached every Mudlet trigger.
  -- Never delete lines: the original slots, combat, blank lines and prompt stay.
  self:armTimer(0,function()
    local pending=self.pending; self.pending=nil
    if self.started and self.enabled and pending then pcall(self.adapter.replaceSkillOutput,self.adapter,pending) end
  end)
end
function Display:onLine(value,number)
  if not self.started or not self.enabled or type(value)~="string" then return false end
  if #value>Display.MAX_LINE_BYTES then self:cancel(); return false end
  local source=plain(value); local text=source:match("^%s*(.-)%s*$")
  if text=="Dragon's Gate Menu" or text:find("Dragon's Gate Character Creator",1,true)
      or text:match("^Welcome to Dragon's Gate,") then self:cancel(); return false end
  if text:match("^Skill%s+Remain%s+Level$") then
    self:cancel()
    if type(number)~="number" or number<0 or number%1~=0 then return false end
    self.response={rows={},numbers={[number]=true},lines=0,header={line_number=number,source_line=source}}
    return self:armTimer(Display.RESPONSE_TIMEOUT,function() self:cancel() end)==true
  end
  local response=self.response; if not response then return false end
  response.lines=response.lines+1
  if response.lines>Display.MAX_LINES then self:cancel(); return false end
  if Parser.isPrompt(source) then self:finish(); return true end
  if text=="" then
    -- The game can end a complete table with blanks and omit the prompt.
    -- Wait for this burst to finish; a later row before the tick keeps collecting.
    if #response.rows>0 and not response.ending then
      response.ending=true
      self:armTimer(Display.BOUNDARY_DELAY,function() self:finish() end)
    end
    return false
  end
  -- Fixed-width table cells require separation; prose/combat is not consumed.
  local skillName,remain,level=source:match("^%s*(.-)%s%s+(%d+)%s+(%d+)%s*$")
  if not skillName then return false end
  skillName=name(skillName); remain=tonumber(remain); level=tonumber(level)
  if skillName=="" or skillName:find("[%c<>:]") or #skillName>256
      or not remain or remain>1000000000000 or not level or level>9999 then return false end
  if type(number)~="number" or number<0 or number%1~=0 or response.numbers[number]
      or #response.rows>=Display.MAX_ROWS then self:cancel(); return false end
  response.numbers[number]=true
  response.rows[#response.rows+1]={line_number=number,source_line=source,
    skill={name=skillName,remain=remain,level=level}}
  if response.ending then
    response.ending=nil
    return self:armTimer(Display.RESPONSE_TIMEOUT,function() self:cancel() end)==true
  end
  return true
end
function Display:start()
  if self.started then return true end
  for _,key in ipairs({"addSkillDisplayTrigger","replaceSkillOutput","addEvent","killEvent","killTrigger","schedule","cancelTimer"}) do
    if type(self.adapter[key])~="function" then return nil,"main skills display is unavailable in this adapter" end
  end
  local ok,id=pcall(self.adapter.addSkillDisplayTrigger,self.adapter,function(value,number)
    local handled=pcall(self.onLine,self,value,number); if not handled then self:cancel() end
  end)
  if not ok or not id then return nil,"skill display trigger registration failed" end
  self.trigger=id; self.started=true
  local function watch(event,fn)
    local called,handler=pcall(self.adapter.addEvent,self.adapter,event,fn)
    if not called or not handler then self:shutdown(); return nil end
    self.events[#self.events+1]=handler; return true
  end
  if not watch("sysDisconnectionEvent",function() self:cancel() end)
      or not watch("sysUninstallPackage",function(_,packageName) if packageName==self.package_name then self:cancel() end end)
      or not watch("sysInstallPackage",function(_,packageName) if packageName==self.package_name then self:cancel() end end) then
    return nil,"skill display event registration failed"
  end
  return true
end
function Display:shutdown()
  self.started=false; self:cancel()
  if self.trigger then pcall(self.adapter.killTrigger,self.adapter,self.trigger); self.trigger=nil end
  for _,id in ipairs(self.events) do pcall(self.adapter.killEvent,self.adapter,id) end
  self.events={}; return true
end
return Display
