local Controller={}
Controller.__index=Controller

local HANDOFF_SCHEMA=1
local MAX_HANDOFF_ENTRIES=1000

local function copyEntries(entries)
  local source=type(entries)=="table" and entries or {}
  local result={}
  local first=math.max(1,#source-MAX_HANDOFF_ENTRIES+1)
  for index=first,#source do
    local entry=source[index]
    if type(entry)=="table" then
      local copy={}
      for key,value in pairs(entry) do
        local kind=type(value)
        if type(key)=="string" and (kind=="string" or kind=="number" or kind=="boolean") then copy[key]=value end
      end
      result[#result+1]=copy
    end
  end
  return result
end

local function validStorageKey(value)
  value=tostring(value or "")
  if #value>128 or not value:match("^[a-z0-9_-]+$") then return "unknown" end
  return value
end

local function call(object,name,...)
  if type(object)~="table" or type(object[name])~="function" then return nil end
  local ok,first,second=pcall(object[name],object,...)
  if not ok then return nil,tostring(first) end
  return first,second
end

function Controller.new(adapter,parser,history,storage,onChange,characterProvider)
  return setmetatable({adapter=adapter,parser=parser,history=history,storage=storage,onChange=onChange or function() end,characterProvider=characterProvider or function() end,filter="ALL",started=false,historiesByCharacter={}},Controller)
end

function Controller:character()
  local ok,value=pcall(self.characterProvider)
  return ok and value or nil
end

function Controller:notify()
  pcall(self.onChange,self:entries(),self.history:categories(),self.filter)
end

function Controller:entries()
  return self.history:entries(self.filter)
end

function Controller:reportStorageError(message)
  self.lastStorageError=tostring(message or "could not access chat log")
  if self.reportedStorageError then return end
  self.reportedStorageError=true
  call(self.adapter,"reportChatErrorOnce",self.lastStorageError)
end

function Controller:status()
  local storageKey=self.currentCharacterKey or "profile"
  local storageError=call(self.storage,"lastError")
  return {active_filter=self.filter,visible_count=#self:entries(),storage_key=storageKey,last_storage_error=storageError or self.lastStorageError}
end

function Controller:accept(entry)
  local added=self.history:append(entry,call(self.adapter,"epoch"))
  if not added then return false end
  local ok,err=call(self.storage,"append",entry)
  if not ok then self:reportStorageError(err or "could not append chat log") end
  self:notify()
  return true
end

function Controller:handoff()
  return {
    schema=HANDOFF_SCHEMA,
    character_key=validStorageKey(self.currentCharacterKey),
    filter=self.filter,
    entries=copyEntries(self.history:entries("ALL")),
    last_key=self.history.lastKey,
    last_epoch=self.history.lastEpoch,
  }
end

function Controller:restoreHandoff(handoff)
  if type(handoff)~="table" or tonumber(handoff.schema)~=HANDOFF_SCHEMA then return nil,"unsupported chat handoff" end
  local filter=self.parser.category(handoff.filter) or "ALL"
  local key="profile"
  self.history:hydrate(copyEntries(handoff.entries))
  self.history.lastKey=type(handoff.last_key)=="string" and handoff.last_key or nil
  self.history.lastEpoch=tonumber(handoff.last_epoch)
  self.filter=filter
  self.currentCharacterKey=key
  self.historiesByCharacter[key]=self.history
  self.restoredFromHandoff=true
  return true
end

function Controller:syncCharacter()
  local storageKey="profile"
  if self.currentCharacterKey==storageKey then return true end
  self.currentCharacterKey=storageKey
  local existing=self.historiesByCharacter[storageKey]
  if existing then self.history=existing; if self.started then self:notify() end; return true end
  if next(self.historiesByCharacter)~=nil then self.history=self.history:newSibling() end
  self.historiesByCharacter[storageKey]=self.history
  local recent,loadErr=call(self.storage,"loadRecent")
  if loadErr then self:reportStorageError(loadErr) end
  self.history:hydrate(type(recent)=="table" and recent or {})
  if self.started then self:notify() end
  return true
end

function Controller:start(preserveDisplay)
  if self.started then return true end
  self:syncCharacter()
  local trigger,triggerErr=call(self.adapter,"addLineTrigger",function(line) self:onLine(line) end)
  if not trigger then return nil,triggerErr or "could not register chat trigger" end
  self.trigger=trigger
  self.started=true
  if preserveDisplay~=true then self:notify() end
  return true
end

function Controller:onLine(line)
  if not self.started then return nil,"chatbox is not running" end
  local entry=self.parser.parse(line,self:character(),call(self.adapter,"timestamp"))
  if entry then return self:accept(entry) end
  return false
end

function Controller:capture(category,text,metadata)
  if not self.started then return nil,"chatbox is not running" end
  local entry,err=self.parser.custom(category,text,metadata,self:character(),call(self.adapter,"timestamp"))
  if not entry then return nil,err end
  local accepted=self:accept(entry)
  return accepted==false and true or accepted
end

function Controller:setFilter(filter)
  if not self.started then return nil,"chatbox is not running" end
  filter=self.parser.category(filter)
  if not filter then return nil,"invalid chat category" end
  self.filter=filter
  self:notify()
  return true
end

function Controller:shutdown()
  self.started=false
  local trigger=self.trigger; self.trigger=nil; local storage=self.storage
  if trigger then call(self.adapter,"killTrigger",trigger) end
  if storage then call(storage,"close") end
  return true
end

return Controller
