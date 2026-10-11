-- Pure QuickActions controller. The parent owns aliases, settings, Collector
-- capture, connection events and rune variables; this module owns no globals.
local QuickActions={}; QuickActions.__index=QuickActions
local SkillSort=require("skill_sort")
local REQUESTS={shoprenew="info mag",shoprenewall="info mag",trainall="skill"}
local MAX_ITEMS,MAX_RUNE_NAME,MAX_SKILL_NAME=256,80,2048
local MAX_INTEGER=9007199254740991
local BUSY="A shortcut is already running. Use shoprenewstop or trainallstop to stop it."
local function listName(name) return name=="trainall" and "skill list" or "rune list" end
local function stopAlias(name) return name=="trainall" and "trainallstop" or "shoprenewstop" end
local function stoppedMessage(name,reason)
  local value=tostring(reason or ""):lower()
  if value:find("disconnect",1,true) then return name.." stopped because you disconnected." end
  if value:find("character",1,true) then return name.." stopped because the character changed." end
  if value:find("updat",1,true) then return name.." stopped while the HUD updates." end
  if value=="shutdown" then return name.." stopped because the HUD closed." end
  if value:find("interrupt",1,true) or value:find("outgoing",1,true) then
    return name.." stopped because you sent another command."
  end
  return name.." stopped."
end
local function failureMessage(name,reason,stage)
  local value=tostring(reason or ""):lower()
  if stage=="setting" then return reason end
  if value:find("disconnect",1,true) or value:find("interrupt",1,true)
      or value:find("character",1,true) or value=="cancelled" or value=="canceled" then
    return stoppedMessage(name,reason)
  end
  if stage=="timer" then
    return name.." stopped because the next action could not be scheduled. Try the shortcut again."
  end
  if stage=="send" or value:find("send",1,true) then
    return name.." stopped because a command could not be sent. Check your connection, then try again."
  end
  if stage=="request" and value:find("busy",1,true) then
    return "The HUD is already refreshing your character. Wait for it to finish, then try "..name.." again."
  end
  return name.." stopped because a fresh, complete "..listName(name)
    .." could not be confirmed. Refresh it and try again."
end

local function integer(value)
  return type(value)=="number" and value==value and value>=0
    and value<=MAX_INTEGER and value%1==0
end
local function plain(value) return type(value)=="table" and getmetatable(value)==nil end
local function runeName(value)
  -- Never repair unsafe text into a command: validate the entire ASCII name.
  if type(value)~="string" or #value==0 or #value>MAX_RUNE_NAME
      or not value:match("^[A-Za-z ]+$") or value:find("  ",1,true)
      or value:sub(1,1)==" " or value:sub(-1)==" " then return nil end
  return value:lower()
end
local function queueFor(name,result)
  -- Completeness/freshness are guaranteed by Collector:request's successful
  -- callback, not by retained snapshots. Explicit negative markers fail closed.
  if not plain(result) or result.complete==false or result.confirmed==false
      or result.cached==true or result.incomplete==true or not plain(result.items) then
    return nil,"unconfirmed or incomplete response"
  end
  local count,highest=0,0
  for key in next,result.items do
    count=count+1
    if count>MAX_ITEMS or not integer(key) or key<1 or key>MAX_ITEMS then
      return nil,"invalid or oversized item list"
    end
    if key>highest then highest=key end
  end
  if count~=highest then return nil,"incomplete item list" end
  local entries,selected={},{}
  for index=1,count do
    local item=result.items[index]
    if not plain(item) then return nil,"invalid response item" end
    if name=="trainall" then
      if type(item.name)~="string" or #item.name==0 or #item.name>MAX_SKILL_NAME
          or not integer(item.remain) or not integer(item.level) then
        return nil,"invalid skill row"
      end
      local id=SkillSort.skillId(item.name)
      -- Unknown names never fall back to the position in the displayed table.
      if id~=nil then
        if not integer(id) or id<1 then return nil,"invalid skill identifier" end
        local previous=entries[id]
        if previous and (previous.remain~=item.remain or previous.level~=item.level) then
          return nil,"conflicting skill rows"
        end
        if not previous then
          entries[id]={remain=item.remain,level=item.level}
          if item.remain==0 then selected[#selected+1]=id end
        end
      end
    else
      local rune=runeName(item.name)
      if not rune or not integer(item.remaining) then return nil,"invalid rune row" end
      if entries[rune]~=nil and entries[rune]~=item.remaining then
        return nil,"conflicting rune counts"
      end
      if entries[rune]==nil then
        entries[rune]=item.remaining
        if name=="shoprenewall" or item.remaining<20 then selected[#selected+1]=rune end
      end
    end
  end
  table.sort(selected) -- Rune names alphabetically; authoritative skill IDs numerically.
  local queue={}
  for index,value in ipairs(selected) do
    queue[index]=name=="trainall" and ("train raise "..string.format("%.0f",value))
      or ("shop renew "..value)
  end
  return queue
end

-- adapter:schedule(seconds,callback) -> timer or nil,error
-- adapter:cancelTimer(timer); adapter:sendCommand(command) -> true or nil,error
-- Void send/cancel returns are accepted; false, errors and exceptions stop work.
-- collector:request(command,done) -> true or nil,error; done(parsed,error).
-- options.enabled(alias) must return true to opt in; options.notify(text) is optional.
function QuickActions.new(adapter,collector,options)
  assert(type(adapter)=="table" and type(adapter.schedule)=="function"
    and type(adapter.cancelTimer)=="function" and type(adapter.sendCommand)=="function",
    "QuickActions requires schedule, cancelTimer and sendCommand")
  assert(type(collector)=="table" and type(collector.request)=="function",
    "QuickActions requires Collector:request")
  options=options or {}
  assert(type(options)=="table" and type(options.enabled)=="function",
    "QuickActions requires options.enabled")
  return setmetatable({adapter=adapter,collector=collector,options=options,
    generation=0,sending=false,closed=false},QuickActions)
end
function QuickActions:busy() return self.current~=nil end
function QuickActions:_live(operation)
  return not self.closed and self.current==operation and operation.generation==self.generation
end
function QuickActions:_notify(message)
  if type(self.options.notify)=="function" then pcall(self.options.notify,message) end
end
function QuickActions:_enabled(operation)
  local ok,enabled=pcall(self.options.enabled,operation.name)
  if not ok then
    return nil,"I couldn't check whether "..operation.name.." is enabled. Save OPTIONS → Skills & Runes and try again."
  end
  if enabled~=true then
    return nil,operation.name.." is OFF. Enable it in OPTIONS → Skills & Runes, then Save."
  end
  return true
end
function QuickActions:_stop(message)
  local operation=self.current
  self.generation=self.generation+1
  self.current=nil -- Invalidate callbacks before calling any external code.
  if not operation then return true end
  operation.error=message
  local timer=operation.timer
  operation.timer=nil
  local ok,cancelled,err=true
  if timer and timer.id~=nil then
    ok,cancelled,err=pcall(self.adapter.cancelTimer,self.adapter,timer.id)
  end
  self:_notify(operation.error)
  if not ok or cancelled==false or err~=nil then
    return nil,operation.name.." stopped; a pending delay could not be cleared. No further actions will run."
  end
  return true
end
function QuickActions:cancel(reason)
  return self:_stop(self.current and stoppedMessage(self.current.name,reason) or "Shortcut stopped.")
end
function QuickActions:_fail(operation,reason,stage)
  local message=failureMessage(operation.name,reason,stage)
  if self:_live(operation) then self:_stop(message) end
  return nil,operation.error or message
end
function QuickActions:shutdown()
  self.closed=true
  return self:cancel("shutdown")
end
function QuickActions:settingsChanged()
  local operation=self.current
  if operation then
    local ok,err=self:_enabled(operation)
    if not ok then return self:_stop(err) end
  end
  return true
end

-- Public sending remains true throughout the synchronous request/send call,
-- including reentrant outgoing events, and is reset even when that call throws.
function QuickActions:_markedCall(command,fn,owner,...)
  self.sending=true; self.own_command=command
  local ok,result,err=pcall(fn,owner,...)
  self.sending=false; self.own_command=nil
  return ok,result,err
end
function QuickActions:onOutgoing(command)
  local operation=self.current
  if not operation then return true end
  if command=="" then return true end -- Collector's delayed empty prompt nudge.
  if self.sending and (command==self.own_command
      or self.own_command=="info mag" and command=="info magic") then return true end
  return self:cancel("interrupted by outgoing command")
end

function QuickActions:_schedule(operation)
  if not self:_live(operation) then return nil,operation.error or "Shortcut stopped." end
  local enabled,err=self:_enabled(operation)
  if not enabled then return self:_fail(operation,err,"setting") end
  if not self:_live(operation) then return nil,operation.error or "Shortcut stopped." end
  if operation.index>#operation.queue then
    self.current=nil
    self:_notify(operation.name.." finished.")
    return true
  end
  local timer={}; operation.timer=timer
  local registering=true
  local ok,id,scheduleErr=pcall(self.adapter.schedule,self.adapter,1,function()
    if not self:_live(operation) or operation.timer~=timer then return end
    -- A scheduler must defer the callback; do not spend before the delay.
    if registering then self:_fail(operation,"timer fired before delay","timer"); return end
    operation.timer=nil
    local allowed,settingErr=self:_enabled(operation)
    if not allowed then self:_fail(operation,settingErr,"setting"); return end
    if not self:_live(operation) then return end
    local command=operation.queue[operation.index]
    local called,sent,sendErr=self:_markedCall(command,self.adapter.sendCommand,self.adapter,command)
    if not self:_live(operation) then return end
    if not called or sent==false or sendErr~=nil then
      self:_fail(operation,(not called and sent) or sendErr or "command send failed","send")
      return
    end
    operation.index=operation.index+1
    self:_schedule(operation)
  end)
  registering=false
  if not ok then scheduleErr=id; id=nil end
  timer.id=id
  if not self:_live(operation) then
    if id~=nil and id~=false then pcall(self.adapter.cancelTimer,self.adapter,id) end
    return nil,operation.error or "Shortcut stopped."
  end
  if id==nil or id==false or scheduleErr~=nil then
    return self:_fail(operation,scheduleErr or "timer could not be created","timer")
  end
  return true
end
function QuickActions:_accept(operation)
  if not self:_live(operation) then return nil,operation.error or "Shortcut stopped." end
  if operation.response_error~=nil then return self:_fail(operation,operation.response_error,"response") end
  local enabled,err=self:_enabled(operation)
  if not enabled then return self:_fail(operation,err,"setting") end
  if not self:_live(operation) then return nil,operation.error or "Shortcut stopped." end
  operation.queue=operation.response_queue; operation.index=1
  local count=#operation.queue
  if count==0 then
    self.current=nil
    self:_notify(operation.name..(operation.name=="trainall"
      and ": No known skills are ready to train."
      or operation.name=="shoprenew" and ": No runes have fewer than 20 weaves remaining."
      or ": No runes are available to renew."))
    return true
  end
  local unit=operation.name=="trainall" and "skill" or "rune"
  local action=operation.name=="trainall" and "training" or "renewal"
  self:_notify(operation.name..": "..count.." "..unit..(count==1 and "" or "s")
    .." queued for "..action..", one per second. Use "..stopAlias(operation.name).." to stop.")
  return self:_schedule(operation)
end
function QuickActions:start(name)
  if self.closed then return nil,"Shortcuts are unavailable because the HUD has closed." end
  if type(name)~="string" or not REQUESTS[name] then
    return nil,"Unknown shortcut. Use shoprenew, shoprenewall or trainall."
  end
  if self:busy() or self.sending then return nil,BUSY end
  self.generation=self.generation+1
  local operation={name=name,generation=self.generation}
  self.current=operation
  local enabled,settingErr=self:_enabled(operation)
  if not enabled then return self:_fail(operation,settingErr,"setting") end
  if not self:_live(operation) then return nil,operation.error or "Shortcut stopped." end
  self:_notify("Refreshing your "..(name=="trainall" and "skills" or "runes").." for "..name
    .."... Use "..stopAlias(name).." to stop.")
  if not self:_live(operation) then return nil,operation.error or "Shortcut stopped." end
  local function done(result,err)
    if not self:_live(operation) or operation.response_seen then return end
    operation.response_seen=true
    if err~=nil then operation.response_error=tostring(err)
    else
      -- Snapshot only validated commands at callback time. Later mutations of a
      -- parsed table cannot change the queued actions.
      local ok,queue,validationErr=pcall(queueFor,name,result)
      if not ok then operation.response_error="invalid response"
      else operation.response_queue=queue; operation.response_error=validationErr end
    end
    if operation.request_accepted then self:_accept(operation) end
  end
  local called,accepted,requestErr=self:_markedCall(REQUESTS[name],
    self.collector.request,self.collector,REQUESTS[name],done)
  if not self:_live(operation) then return nil,operation.error or "Shortcut stopped." end
  if not called or accepted~=true or requestErr~=nil then
    return self:_fail(operation,(not called and accepted) or requestErr or "request not confirmed","request")
  end
  operation.request_accepted=true
  if operation.response_seen then return self:_accept(operation) end
  return true
end

return QuickActions
