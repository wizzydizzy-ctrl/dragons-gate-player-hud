local Controller={}
Controller.__index=Controller
local History=require("chat_history")
local Channels=require("chat_channels")
local Outgoing=require("chat_outgoing")

local HANDOFF_SCHEMA=1
local STAFF_MESSAGE_FLUSH_DELAY=.4
local STAFF_MESSAGE_MAX_LINES=20
local STAFF_MESSAGE_MAX_CHARS=4000
local LINK_FILTER=Channels.linkFilter
local CUSTOM_LINK_VIEW="LINK VIEW"
local linkConstituents=Channels.linkMembers

local function boundedCategory(value)
  if type(value)~="string" or #value>32 then return nil end
  value=Channels.category(value)
  if value==LINK_FILTER or value==CUSTOM_LINK_VIEW then return value end
  return value:match("^[A-Z][A-Z0-9_%-]*$") and value or nil
end

local function copyEntries(entries)
  local source=History.retained(entries,History.MAX_ENTRIES)
  local result={}
  for _,entry in ipairs(source) do
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

function Controller.new(adapter,parser,history,storage,onChange,characterProvider,allSources,onAccepted,captureOutgoing)
  return setmetatable({adapter=adapter,parser=parser,history=history,storage=storage,onChange=onChange or function() end,characterProvider=characterProvider or function() end,allSources=type(allSources)=="table" and allSources or nil,onAccepted=type(onAccepted)=="function" and onAccepted or nil,filter="ALL",started=false,historiesByCharacter={},captureOutgoing=captureOutgoing~=false,outgoing=Outgoing.new(),linkCombined=false},Controller)
end

function Controller:character()
  local ok,value=pcall(self.characterProvider)
  return ok and value or nil
end

function Controller:notify()
  pcall(self.onChange,self:entries(),self.history:categories(),self.filter)
end

function Controller:entries()
  local retained=self.history:entries(self.filter,self.allSources,self.linkCombined)
  local visible={}
  -- Limit the rendered view only after filtering. Hidden combat cannot push
  -- ordinary conversations out of ALL, and dedicated histories remain intact.
  local first=math.max(1,#retained-self.history.limit+1)
  for index=first,#retained do visible[#visible+1]=retained[index] end
  return visible
end

function Controller:setAllSources(sources)
  if type(sources)~="table" then return nil,"ALL tab sources must be a table" end
  self.allSources=sources
  if self.started then self:notify() end
  return true
end

function Controller:setLinkCombined(enabled)
  if type(enabled)~="boolean" then return nil,"combined link mode must be a boolean" end
  if enabled and not self.currentCharacterKey then self:syncCharacter() end
  self.linkCombined=enabled
  -- A v0.3.103 handoff used the personal name for its virtual filter. Defer
  -- its interpretation until the current mode is applied, after hydration.
  if self.legacyLinkFilterPending then
    if self.filter==CUSTOM_LINK_VIEW and not self.history.knownCategories[CUSTOM_LINK_VIEW] then self.filter=LINK_FILTER end
    self.legacyLinkFilterPending=nil
  end
  if enabled and linkConstituents[self.filter] then
    self.linkPriorFilter=self.filter
    self.filter=LINK_FILTER
  elseif not enabled then
    if self.filter==LINK_FILTER then
      local prior=boundedCategory(self.linkPriorFilter)
      self.filter=linkConstituents[prior] and prior or "MENTAL"
    end
    self.linkPriorFilter=nil
  end
  if self.started then self:notify() end
  return true
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

function Controller:accept(entry,suppressAlert,force)
  local added=self.history:append(entry,call(self.adapter,"epoch"),force==true and entry.source=="outgoing")
  if not added then return false end
  local ok,err=call(self.storage,"append",entry)
  if not ok then self:reportStorageError(err or "could not append chat log") end
  self:notify()
  if self.started and suppressAlert~=true and self.onAccepted then pcall(self.onAccepted,entry) end
  return true
end

local function cleanLine(value)
  value=tostring(value or ""):gsub("\27%[[0-?]*[ -/]*[@-~]",""):match("^%s*(.-)%s*$")
  return value
end

local function bufferedStaffEntry(entry)
  if type(entry)~="table" or entry.category~="STAFF" then return false end
  local message=tostring(entry.message or "")
  return entry.staff_referral~=nil or message:match("^submits an idea:")~=nil or message:match("^reports a bug in room %d+:")~=nil or message:match("^resolved report #%d+:")~=nil
end

local function completeStaffReferral(entry)
  if entry.staff_referral=="detail" then return entry.message:match("'%s*>$")~=nil end
  if entry.staff_referral=="list" then
    local message=entry.message:gsub("%s+"," ")
    return message:match("'%s+%[[^%[%]%c]+ago%.%]$")~=nil
  end
  return false
end

local function referralTerminatorContinuation(entry,line)
  if not entry.message:match("'$") then return false end
  line=cleanLine(line)
  if entry.staff_referral=="detail" then return line==">" end
  if entry.staff_referral~="list" then return false end
  -- An age may start on its own wrapped line. Do not mistake a numeric
  -- game prompt (which contains a closing bracket) for that continuation.
  return line:match("^%[%d[%d%s%a,%.]*$")~=nil or line:match("^%[%d[%d%s%a,%.]*ago%.%]$")~=nil
end

local function staffMessageBoundary(line,parsed)
  if parsed then return true end
  line=cleanLine(line)
  return line=="" or line:match("^>")~=nil or line:match("^%[[^%]]+%]")~=nil
end

function Controller:cancelStaffMessageTimer()
  self.staffMessageGeneration=(self.staffMessageGeneration or 0)+1
  local timer=self.staffMessageTimer; self.staffMessageTimer=nil
  if timer then call(self.adapter,"cancelTimer",timer) end
end

function Controller:flushStaffMessage(suppressAlert)
  self:cancelStaffMessageTimer()
  local entry=self.pendingStaffMessage; self.pendingStaffMessage=nil; self.pendingStaffMessageLines=nil
  if not entry then return false end
  entry.staff_referral=nil
  return self:accept(entry,suppressAlert)
end

function Controller:scheduleStaffMessageFlush()
  self:cancelStaffMessageTimer()
  local generation=self.staffMessageGeneration
  local timer=call(self.adapter,"schedule",STAFF_MESSAGE_FLUSH_DELAY,function()
    if self.staffMessageGeneration~=generation then return end
    self.staffMessageTimer=nil
    if self.started then self:flushStaffMessage() end
  end)
  if not timer then return self:flushStaffMessage() end
  self.staffMessageTimer=timer
  return true
end

function Controller:beginStaffMessage(entry)
  entry.message=entry.message:sub(1,STAFF_MESSAGE_MAX_CHARS)
  entry.line=entry.line:sub(1,STAFF_MESSAGE_MAX_CHARS)
  self.pendingStaffMessage=entry; self.pendingStaffMessageLines=1
  if completeStaffReferral(entry) or #entry.message>=STAFF_MESSAGE_MAX_CHARS then return self:flushStaffMessage() end
  return self:scheduleStaffMessageFlush()
end

function Controller:appendStaffMessage(line)
  local text=cleanLine(line)
  if text=="" then return self:flushStaffMessage() end
  local entry=self.pendingStaffMessage
  entry.message=(entry.message.." "..text):sub(1,STAFF_MESSAGE_MAX_CHARS)
  entry.line=(entry.line.." "..text):sub(1,STAFF_MESSAGE_MAX_CHARS)
  self.pendingStaffMessageLines=(self.pendingStaffMessageLines or 1)+1
  if completeStaffReferral(entry) or self.pendingStaffMessageLines>=STAFF_MESSAGE_MAX_LINES or #entry.message>=STAFF_MESSAGE_MAX_CHARS then return self:flushStaffMessage() end
  return self:scheduleStaffMessageFlush()
end

function Controller:acceptParsed(entry)
  if bufferedStaffEntry(entry) then return self:beginStaffMessage(entry) end
  return self:accept(entry)
end

function Controller:handoff()
  self.outgoing:clear()
  self:flushStaffMessage(true)
  return {
    schema=HANDOFF_SCHEMA,
    character_key=validStorageKey(self.currentCharacterKey),
    filter=self.filter,
    previous_link_filter=boundedCategory(self.linkPriorFilter),
    entries=copyEntries(self.history.items),
    last_key=self.history.lastKey,
    last_epoch=self.history.lastEpoch,
    last_mental_kind=self.history.lastMentalKind,
  }
end

function Controller:restoreHandoff(handoff)
  if type(handoff)~="table" or tonumber(handoff.schema)~=HANDOFF_SCHEMA then return nil,"unsupported chat handoff" end
  self.outgoing:clear()
  local filter=boundedCategory(handoff.filter) or "ALL"
  local prior=boundedCategory(handoff.previous_link_filter)
  self.linkPriorFilter=linkConstituents[prior] and prior or nil
  local key="profile"
  self.history:hydrate(copyEntries(handoff.entries))
  if handoff.partial==true then
    -- A view-only snapshot omits sources hidden from ALL. Restore their saved
    -- records too; a full handoff must still preserve an explicitly cleared view.
    local recent,loadErr=call(self.storage,"loadRecent")
    if loadErr then self:reportStorageError(loadErr) end
    -- Prefer the raw disk record when a partial snapshot contains its projection.
    self.history:hydrate(type(recent)=="table" and recent or {},true)
  end
  self.history:restoreDedupe(handoff.last_key,handoff.last_epoch,handoff.last_mental_kind)
  self.filter=filter
  self.legacyLinkFilterPending=filter==CUSTOM_LINK_VIEW and not self.history.knownCategories[CUSTOM_LINK_VIEW] or nil
  self.currentCharacterKey=key
  self.historiesByCharacter[key]=self.history
  self.restoredFromHandoff=true
  if self.linkCombined then self:setLinkCombined(true) end
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

function Controller:stopOutgoingObserver()
  self.outgoingGeneration=(self.outgoingGeneration or 0)+1
  local event=self.outgoingEvent; self.outgoingEvent=nil
  if event then call(self.adapter,"killEvent",event) end
  self.outgoing:clear()
end

function Controller:startOutgoingObserver()
  if self.outgoingEvent or not self.captureOutgoing or type(self.adapter.addEvent)~="function" then return true end
  self.outgoingGeneration=(self.outgoingGeneration or 0)+1
  local generation=self.outgoingGeneration
  local event,err=call(self.adapter,"addEvent","sysDataSendRequest",function(_,command)
    if self.outgoingGeneration==generation then self:onOutgoing(command) end
  end)
  if type(event)~="number" or event<1 or event~=math.floor(event) then return nil,err or "could not register outgoing chat observer" end
  self.outgoingEvent=event
  return true
end

function Controller:setCaptureOutgoing(enabled)
  if type(enabled)~="boolean" then return nil,"outgoing capture must be a boolean" end
  self.captureOutgoing=enabled
  if not enabled then self:stopOutgoingObserver(); return true end
  if self.started then return self:startOutgoingObserver() end
  return true
end

function Controller:outgoingCharacter()
  if type(self.sessionActive)=="function" then
    local ok,active=pcall(self.sessionActive)
    if not ok or active~=true then self.outgoing:clear(); return nil end
  end
  if call(self.adapter,"isCharacterActive")~=true then self.outgoing:clear(); return nil end
  local character=Outgoing.character(self:character())
  if not character then self.outgoing:clear() end
  return character
end

function Controller:nextOutgoingId(epoch)
  epoch=tonumber(epoch)
  if not epoch or epoch~=epoch or epoch==math.huge or epoch==-math.huge then epoch=os.time() end
  local epochKey=tostring(epoch)
  local sequence=self.outgoingSequence or 0
  if self.outgoingEpoch~=epochKey then
    -- A replacement controller can start in the same second as saved sends.
    -- Seed from retained IDs, keeping cold reloads and handoffs distinct.
    for _,entry in ipairs(self.history.items or {}) do
      if entry.source=="outgoing" and type(entry.outgoing_id)=="string" and #entry.outgoing_id<=64 then
        local savedEpoch,savedSequence=entry.outgoing_id:match("^([^:]+):(%d+)$")
        savedSequence=tonumber(savedSequence)
        if savedEpoch==epochKey and savedSequence and savedSequence<9007199254740991 then sequence=math.max(sequence,savedSequence) end
      end
    end
  end
  self.outgoingEpoch=epochKey; self.outgoingSequence=sequence+1
  return epochKey..":"..string.format("%.0f",self.outgoingSequence)
end

function Controller:onOutgoing(command)
  if not self.started then return nil,"chatbox is not running" end
  if not self.captureOutgoing then return false end
  local character=self:outgoingCharacter()
  if not character then return false end
  local entry=Outgoing.parse(command,character,call(self.adapter,"timestamp"))
  if not entry then return false end
  local epoch=call(self.adapter,"epoch")
  local serverName=Outgoing.serverName(character,call(self.adapter,"getGMCP"))
  entry.outgoing_id=self:nextOutgoingId(epoch)
  self:flushStaffMessage()
  local accepted=self:accept(entry,true,true)
  if accepted then self.outgoing:record(entry,epoch,serverName) end
  return accepted
end

function Controller:start(preserveDisplay)
  if self.started then return true end
  self:syncCharacter()
  if self.linkCombined then self:setLinkCombined(true) end
  local trigger,triggerErr=call(self.adapter,"addLineTrigger",function(line) self:onLine(line) end)
  if not trigger then return nil,triggerErr or "could not register chat trigger" end
  self.trigger=trigger
  self.started=true
  local observed,observerErr=self:startOutgoingObserver()
  if not observed then
    self.started=false; self.trigger=nil
    self:stopOutgoingObserver()
    call(self.adapter,"killTrigger",trigger)
    return nil,observerErr
  end
  if preserveDisplay~=true then self:notify() end
  return true
end

function Controller:onLine(line)
  if not self.started then return nil,"chatbox is not running" end
  local entry=self.parser.parse(line,self:character(),call(self.adapter,"timestamp"))
  if entry and self.captureOutgoing then
    local character=self:outgoingCharacter()
    local serverName=Outgoing.serverName(character,call(self.adapter,"getGMCP"))
    if self.outgoing:reconcile(entry,character,call(self.adapter,"epoch"),serverName) then
      if self.pendingStaffMessage then self:flushStaffMessage() end
      return false
    end
  end
  if self.pendingStaffMessage then
    if staffMessageBoundary(line,entry) and not referralTerminatorContinuation(self.pendingStaffMessage,line) then
      self:flushStaffMessage()
      if entry then return self:acceptParsed(entry) end
      return false
    end
    return self:appendStaffMessage(line)
  end
  if entry then return self:acceptParsed(entry) end
  return false
end

function Controller:capture(category,text,metadata)
  if not self.started then return nil,"chatbox is not running" end
  if Channels.category(category)==LINK_FILTER then return nil,"reserved chat filter cannot be captured" end
  local customLinkView=Channels.category(category)==CUSTOM_LINK_VIEW
  local entry,err=self.parser.custom(customLinkView and "LINK_VIEW" or category,text,metadata,self:character(),call(self.adapter,"timestamp"))
  if not entry then return nil,err end
  if customLinkView then entry.category=CUSTOM_LINK_VIEW end
  local accepted=self:accept(entry)
  return accepted==false and true or accepted
end

function Controller:setFilter(filter)
  if not self.started then return nil,"chatbox is not running" end
  filter=boundedCategory(filter)
  if not filter then return nil,"invalid chat category" end
  self.legacyLinkFilterPending=nil
  if self.linkCombined and linkConstituents[filter] then self.linkPriorFilter=filter; filter=LINK_FILTER end
  self.filter=filter
  self:notify()
  return true
end

function Controller:clearVisibleHistory()
  self.outgoing:clear()
  local removed=self.history:clearVisible()
  self:notify()
  return true,removed
end

function Controller:clearSavedHistory(confirmed)
  if confirmed~=true then return nil,"explicit confirmation is required to permanently clear saved chat history" end
  local cleared,removedOrError=call(self.storage,"clearProfileHistory",true)
  if not cleared then
    local message=removedOrError or "saved chat history clearing is unavailable"
    self:reportStorageError(message)
    return nil,message
  end
  -- A pending wrapped message predates the deletion. Neither it nor a stale
  -- timer may put that private text back into the freshly cleared history.
  self:cancelStaffMessageTimer()
  self.pendingStaffMessage=nil; self.pendingStaffMessageLines=nil
  self.outgoing:clear()
  self.history:clearVisible()
  self.currentCharacterKey="profile"
  self.historiesByCharacter={profile=self.history}
  self:notify()
  return true,tonumber(removedOrError) or 0
end

function Controller:shutdown()
  self:stopOutgoingObserver()
  self:flushStaffMessage(true)
  self.started=false
  local trigger=self.trigger; self.trigger=nil; local storage=self.storage
  if trigger then call(self.adapter,"killTrigger",trigger) end
  if storage then call(storage,"close") end
  return true
end

return Controller
