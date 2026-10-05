local Parser=require("command_parser")
local SkillSort=require("skill_sort")
local Display={}; Display.__index=Display
Display.MAX_ROWS=128; Display.MAX_LINES=256; Display.MAX_LINE_BYTES=2048; Display.RESPONSE_TIMEOUT=5
Display.BOUNDARY_DELAY=0
Display.MAX_FILTER_BYTES=128

local function plain(value)
  return value:gsub("\27%[[0-?]*[ -/]*[@-~]",""):gsub("\r","")
end
local function name(value)
  return value:match("^%s*(.-)%s*$"):gsub("^[%*%s]+",""):gsub("%s+"," ")
end
Display.skillId=SkillSort.skillId
Display.combatCategory=SkillSort.combatCategory
local shortNames={["sharp weapons"]="Sharps",["blunt weapons"]="Blunts",["pole weapons"]="Poles",
  ["throw weapons"]="Throws",["missile weapons"]="Missiles"}
local filterAliases={
  ["identify gems/minerals"]={"id gems/minerals","id gems"},
  ["identify magick"]={"id magick"},
  ["identify weapon quality"]={"id weapon quality","id weapon"},
  ["identify armor quality"]={"id armor quality","id armor"},
}
local canonicalNames={}
for full,short in pairs(shortNames) do canonicalNames[short:lower()]=full end
for full,aliases in pairs(filterAliases) do
  for _,alias in ipairs(aliases) do canonicalNames[alias]=full end
end
function Display.displayName(value)
  local cleaned=name(plain(tostring(value or ""))):gsub("%c"," ")
  return shortNames[cleaned:lower()] or cleaned
end
function Display.normalizeFilter(query)
  if type(query)~="string" then return nil,"skill filter must be a string" end
  if #query>Display.MAX_FILTER_BYTES then return nil,"skill filter exceeds 128 bytes" end
  for index=1,#query do
    local byte=query:byte(index)
    if byte<32 or byte==127 then return nil,"skill filter must not contain control characters" end
  end
  local normalized=query:lower():gsub(" +"," "):match("^ *(.-) *$")
  return normalized=="all" and "" or normalized
end
function Display.matchesFilter(skillName,query)
  local prefix=Display.normalizeFilter(query)
  if prefix==nil or type(skillName)~="string" or #skillName>Display.MAX_LINE_BYTES then return false end
  if prefix=="" then return true end
  local cleaned=name(plain(skillName)):lower()
  local canonical=canonicalNames[cleaned] or cleaned
  -- The query is data: literal leading bytes only, never a Lua pattern or code.
  local function starts(value) return value:sub(1,#prefix)==prefix end
  if starts(canonical) or starts(Display.displayName(canonical):lower()) then return true end
  if canonical:sub(1,9)=="identify " and starts("id "..canonical:sub(10)) then return true end
  for _,alias in ipairs(filterAliases[canonical] or {}) do if starts(alias) then return true end end
  return prefix=="bite" and canonical=="biting"
end
function Display.category(skill)
  if skill.remain==0 then return "ready" end
  return Display.combatCategory(skill)
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
function Display.new(adapter,enabled,packageName,sort)
  return setmetatable({adapter=adapter,enabled=enabled~=false,package_name=packageName or "DragonsGateHUD",
    sort=SkillSort.normalize(sort),started=false,generation=0,events={}},Display)
end
function Display:disarmTimer()
  self.generation=self.generation+1
  local timer=self.timer; self.timer=nil
  if timer then pcall(self.adapter.cancelTimer,self.adapter,timer) end
end
function Display:cancel()
  self:disarmTimer(); self.response=nil; self.pending=nil; self.filter_query=nil; self.pending_filter=nil
end
function Display:filterPending()
  return self.filter_query~=nil or (self.response~=nil and self.response.filter_query~=nil) or self.pending_filter==true
end
function Display:requestFilter(query)
  local normalized,err=Display.normalizeFilter(query)
  if normalized==nil then return nil,err end
  if self:filterPending() then return nil,"a skill filter request is already pending" end
  if not self.started then return nil,"main skills display is not started" end
  self:cancel()
  self.filter_query=normalized
  if not self:armTimer(Display.RESPONSE_TIMEOUT,function() self:cancel() end) then
    return nil,"skill filter timeout registration failed"
  end
  return true
end
function Display:setEnabled(enabled)
  if type(enabled)~="boolean" then return nil,"main skills display must be a boolean" end
  self:cancel(); self.enabled=enabled; return enabled
end
function Display:setSort(config)
  local normalized,err=SkillSort.validate(config)
  if not normalized then return nil,err end
  self.sort=normalized; return normalized
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
  if not response then return end
  local query=response.filter_query
  if (not self.enabled and query==nil) or (#response.rows==0 and (query==nil or query=="")) then return end
  local items,sources={},{}
  for _,row in ipairs(response.rows) do
    sources[row.skill]=row.source_line
    if query==nil or Display.matchesFilter(row.skill.name,query) then items[#items+1]=row.skill end
  end
  if self.enabled then items=SkillSort.sorted(items,self.sort) end
  local widths=self.enabled and columnWidths(items) or nil
  local heading=response.header.source_line
  if #items==0 then heading="No skills match: "..query
  elseif self.enabled then heading=columns({"Number","Skill","LVL","USES"},widths) end
  local rows={{line_number=response.header.line_number,source_line=response.header.source_line,
    display_text=heading,category="neutral"}}
  for index,row in ipairs(response.rows) do
    local output={line_number=row.line_number,source_line=row.source_line}
    local skill=items[index]
    if not skill then output.remove=true
    elseif self.enabled then
      output.display_text=Display.format(skill,widths)
      output.category=Display.category(skill); output.style_id="skill_"..output.category
    else output.display_text=sources[skill]; output.category="neutral" end
    rows[#rows+1]=output
  end
  self.pending=rows; self.pending_filter=query~=nil
  -- Defer until the complete raw response has reached every Mudlet trigger.
  -- The adapter owns guarded rewrites/removals of the original skill slots.
  self:armTimer(0,function()
    local pending,filtered=self.pending,self.pending_filter
    self.pending=nil; self.pending_filter=nil
    if self.started and (self.enabled or filtered) and pending then pcall(self.adapter.replaceSkillOutput,self.adapter,pending) end
  end)
end
function Display:onLine(value,number)
  if not self.started or (not self.enabled and not self:filterPending()) or type(value)~="string" then return false end
  if #value>Display.MAX_LINE_BYTES then self:cancel(); return false end
  local source=plain(value); local text=source:match("^%s*(.-)%s*$")
  if text=="Dragon's Gate Menu" or text:find("Dragon's Gate Character Creator",1,true)
      or text:match("^Welcome to Dragon's Gate,") then self:cancel(); return false end
  if text:match("^Skill%s+Remain%s+Level$") then
    local query=self.filter_query
    self:cancel()
    if not self.enabled and query==nil then return false end
    if type(number)~="number" or number<0 or number%1~=0 then return false end
    self.response={rows={},numbers={[number]=true},lines=0,filter_query=query,
      header={line_number=number,source_line=source}}
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
