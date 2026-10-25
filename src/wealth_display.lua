local Parser=require("command_parser")
local Display={}; Display.__index=Display
Display.MAX_ROWS=512; Display.MAX_LINES=1024; Display.MAX_LINE_BYTES=512
Display.MAX_NAME_BYTES=80; Display.MAX_AMOUNT_DIGITS=32; Display.RESPONSE_TIMEOUT=5

local function clean(value)
  if type(value)~="string" or #value>Display.MAX_LINE_BYTES then return nil end
  local text=value:gsub("\27%[[0-?]*[ -/]*[@-~]",""):gsub("\7","")
  if text:sub(-1)=="\n" then text=text:gsub("\r?\n$","") else text=text:gsub("\r$","") end
  if text:find("[\r\n%z]") or text:find("[\1-\8\11\12\14-\31\127]") then return nil end
  return text
end
local function validName(value)
  return type(value)=="string" and #value<=Display.MAX_NAME_BYTES
    and value:match("^[A-Za-z][A-Za-z0-9_%-' ]*$")~=nil
end
local function canonicalAmount(value)
  if type(value)~="string" or #value>Display.MAX_AMOUNT_DIGITS or not value:match("^%d+$") then return nil end
  local digits=value:gsub("^0+","")
  return digits~="" and digits or "0"
end
local function coordinate(value)
  return type(value)=="number" and value==value and value>=0 and value<math.huge and value%1==0
end
function Display.isCommand(value)
  if type(value)~="string" or #value>64 or value:find("[\r\n%z]") or value:find("[\1-\8\11-\31\127]") then return false end
  local verb,subject=value:lower():match("^%s*(%a+)%s+(%a+)%s*$")
  return (verb=="breakd" or verb=="breakdown") and subject=="wealth" or false
end
function Display.parseRow(value)
  local source=clean(value); if not source then return nil end
  local name,amount=source:match("^%s*([A-Za-z][A-Za-z0-9_%-' ]-)%s+has%s+(%d+)%s+silver%s*$")
  if not name then return nil end
  name=name:match("^%s*(.-)%s*$"):gsub(" +"," ")
  local silver=canonicalAmount(amount)
  if not validName(name) or not silver then return nil end
  return {name=name,silver=silver}
end
local function grouped(amount)
  local reversed=amount:reverse():gsub("(%d%d%d)","%1,")
  return reversed:reverse():gsub("^,","")
end
function Display.formatRows(items)
  if type(items)~="table" or #items>Display.MAX_ROWS then return nil,"Invalid wealth report." end
  local sorted={}; local nameWidth,silverWidth=4,6
  for index,item in ipairs(items) do
    if type(item)~="table" or not validName(item.name) then return nil,"Invalid wealth row." end
    local silver=canonicalAmount(item.silver)
    if not silver then return nil,"Invalid silver amount." end
    local amount=grouped(silver)
    sorted[index]={name=item.name,silver=silver,amount=amount,index=index}
    nameWidth=math.max(nameWidth,#item.name); silverWidth=math.max(silverWidth,#amount)
  end
  table.sort(sorted,function(a,b)
    if #a.silver~=#b.silver then return #a.silver>#b.silver end
    if a.silver~=b.silver then return a.silver>b.silver end
    return a.index<b.index
  end)
  local function columns(name,amount)
    return name..string.rep(" ",nameWidth-#name+2)..string.rep(" ",silverWidth-#amount)..amount
  end
  local lines={columns("Name","Silver")}
  for _,item in ipairs(sorted) do lines[#lines+1]=columns(item.name,item.amount) end
  return lines
end
function Display.new(adapter,packageName)
  return setmetatable({adapter=adapter,package_name=packageName or "DragonsGateHUD",
    started=false,generation=0,events={}},Display)
end
function Display:cancel()
  self.generation=self.generation+1
  local timer=self.timer; self.timer=nil; self.response=nil; self.pending=nil
  if timer then pcall(self.adapter.cancelTimer,self.adapter,timer) end
  return true
end
function Display:armTimer(delay,fn)
  self.generation=self.generation+1
  local previous=self.timer; self.timer=nil
  if previous then pcall(self.adapter.cancelTimer,self.adapter,previous) end
  local generation=self.generation
  local registering,early=true,false
  local ok,id=pcall(self.adapter.schedule,self.adapter,delay,function()
    if registering then early=true; return end
    if not self.started or self.generation~=generation then return end
    self.timer=nil; fn()
  end)
  registering=false
  if not ok or not id or early then
    if ok and id then pcall(self.adapter.cancelTimer,self.adapter,id) end
    self:cancel(); return nil
  end
  self.timer=id; return true
end
function Display:onOutgoing(command)
  if not self.started then return false end
  -- Empty prompt nudges are not new requests. Never send or rewrite commands.
  if type(command)=="string" and command:match("^[ \t]*$") then return false end
  self:cancel()
  if not Display.isCommand(command) then return false end
  self.response={rows={},numbers={},lines=0}
  return self:armTimer(Display.RESPONSE_TIMEOUT,function() self:cancel() end)==true
end
function Display:finish(source,number)
  local response=self.response
  if not response or #response.rows==0 or not coordinate(number)
      or number<=response.rows[#response.rows].line_number or response.numbers[number] then self:cancel(); return false end
  local items={}
  for index,row in ipairs(response.rows) do items[index]=row.item end
  local formatted=Display.formatRows(items)
  if not formatted then self:cancel(); return false end
  local pending={}
  for index,row in ipairs(response.rows) do
    pending[index]={line_number=row.line_number,source_line=row.source_line,display_text=formatted[index]}
  end
  -- Reuse the terminating Done. slot for the final item, making room for the
  -- header without deleting rows, adding blank gaps, or changing other output.
  pending[#pending+1]={line_number=number,source_line=source,display_text=formatted[#formatted]}
  self:cancel(); self.pending=pending
  return self:armTimer(0,function()
    local rows=self.pending; self.pending=nil
    if self.started and rows then pcall(self.adapter.replaceWealthOutput,self.adapter,rows) end
  end)==true
end
function Display:onLine(value,number)
  if not self.started or (not self.response and not self.pending) then return false end
  local source=clean(value); if not source then self:cancel(); return false end
  local text=source:match("^%s*(.-)%s*$")
  if text=="Dragon's Gate Menu" or text:find("Dragon's Gate Character Creator",1,true)
      or text:match("^Welcome to Dragon's Gate,") then self:cancel(); return false end
  if not self.response then return false end
  local response=self.response; response.lines=response.lines+1
  if response.lines>Display.MAX_LINES then self:cancel(); return false end
  if text=="Done." then return self:finish(source,number) end
  if Parser.isPrompt(source) then self:cancel(); return false end
  local item=Display.parseRow(source)
  if not item then
    -- A damaged wealth row must not silently become a partial sorted report.
    -- Quoted chat/other ordinary output does not match this anchored prefix.
    if source:match("^%s*[^\"<>:]+%s+has%s+")
        or source:match("^%s*.+%s+has%s+.-%s+silver%s*$") then self:cancel() end
    return false
  end
  local previous=response.rows[#response.rows]
  if not coordinate(number) or response.numbers[number] or (previous and number<=previous.line_number)
      or #response.rows>=Display.MAX_ROWS then self:cancel(); return false end
  response.numbers[number]=true
  response.rows[#response.rows+1]={line_number=number,source_line=source,item=item}
  return true
end
function Display:start()
  if self.started then return true end
  for _,key in ipairs({"addWealthDisplayTrigger","replaceWealthOutput","addEvent","killEvent","killTrigger","schedule","cancelTimer"}) do
    if type(self.adapter[key])~="function" then return nil,"Wealth display is unavailable in this adapter." end
  end
  local ok,id=pcall(self.adapter.addWealthDisplayTrigger,self.adapter,function(value,number)
    if not pcall(self.onLine,self,value,number) then self:cancel() end
  end)
  if not ok or not id then return nil,"Wealth display trigger registration failed." end
  self.trigger=id; self.started=true
  local function watch(event,fn)
    local called,handler=pcall(self.adapter.addEvent,self.adapter,event,fn)
    if not called or not handler then self:shutdown(); return nil end
    self.events[#self.events+1]=handler; return true
  end
  if not watch("sysDataSendRequest",function(_,command) self:onOutgoing(command) end)
      or not watch("sysDisconnectionEvent",function() self:cancel() end)
      or not watch("sysInstallPackage",function(_,name) if name==self.package_name then self:cancel() end end)
      or not watch("sysUninstallPackage",function(_,name) if name==self.package_name then self:cancel() end end) then
    return nil,"Wealth display event registration failed."
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
