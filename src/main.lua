package.loaded["output_colorizer"]=nil
local State=require("state"); local Events=require("events"); local Layout=require("layout"); local Parser=require("command_parser"); local Collector=require("command_collector"); local Clock=require("game_clock"); local ChatParser=require("chat_parser"); local ChatHistory=require("chat_history"); local ChatController=require("chat_controller"); local OutputColorizer=require("output_colorizer"); local PostureTracker=require("posture_tracker"); local Autoroller=require("autoroller"); local MapperModel=require("mapper_model"); local MapAdapter=require("map_adapter"); local Automapper=require("automapper"); local SpecialTransition=require("special_transition"); local MapWalker=require("map_walker"); local Cleanup=require("map_cleanup")
local Main={}; Main.__index=Main
local colorFeatures={"room","exits","currency","portal","attack","damage","danger","recovery","upkeep","spell","discovery","illumination"}
local function colorOptions(status)
  local result={enabled=status.enabled}
  for _,name in ipairs(colorFeatures) do result[name]=status[name] end
  return result
end
function Main.new(adapter,settings)
  local colorSettings=settings and settings.colorization
  local self=setmetatable({adapter=adapter,settings=settings,runtime={events={},aliases={},triggers={}},started=false,roundtime_display=nil,managed_rooms={},colorizer_enabled=not (type(colorSettings)=="table" and colorSettings.enabled==false)},Main)
  self.clock=Clock.new(settings and settings.time,function() return adapter:epoch() end)
  return self
end
function Main.installChatApi(namespace)
  local chat=type(namespace.chat)=="table" and namespace.chat or {}
  namespace.chat=chat
  chat.capture=function(category,text,metadata)
      local active=rawget(_G,"DGHUD"); local controller=active and active.controller; local chat=controller and controller.chat
      if not chat then return nil,"chatbox is not running" end
      return chat:capture(category,text,metadata)
    end
  chat.setFilter=function(filter)
      local active=rawget(_G,"DGHUD"); local controller=active and active.controller; local chat=controller and controller.chat
      if not chat then return nil,"chatbox is not running" end
      return chat:setFilter(filter)
    end
  chat.status=function()
      local active=rawget(_G,"DGHUD"); local controller=active and active.controller
      if not controller then return nil,"HUD is not running" end
      return controller:chatStatus()
    end
  Main.installColorizerApi(namespace)
  Main.installRunesApi(namespace)
  Main.installRollerApi(namespace)
  return chat
end
function Main.installRollerApi(namespace)
  local api=type(namespace.roller)=="table" and namespace.roller or {}; namespace.roller=api
  local function active() local root=rawget(_G,"DGHUD"); local controller=root and root.controller; return controller and controller.roller end
  api.command=function(action) local roller=active(); if not roller then return nil,"autoroller is not running" end; return roller:command(action) end
  api.configure=function(values) local roller=active(); if not roller then return nil,"autoroller is not running" end; return roller:configure(values) end
  api.status=function() local roller=active(); if not roller then return nil,"autoroller is not running" end; local function copy(value) if type(value)~="table" then return value end; local out={}; for key,item in pairs(value) do out[key]=copy(item) end; return out end; return {active=roller.state.active,rolls=roller.state.rolls,last=copy(roller.state.last),best=copy(roller.state.best),config=copy(roller.cfg)} end
  return api
end
local function runeCopy(item) return item and {name=item.name,remaining=item.remaining} or nil end
function Main.installRunesApi(namespace)
  local api=type(namespace.runes)=="table" and namespace.runes or {}; namespace.runes=api; api.items=api.items or {}; api.by_name=api.by_name or {}; api.remaining=api.remaining or {}
  api.get=function(name) local item=api.by_name[tostring(name or ""):lower()]; return runeCopy(item) end
  api.getRemaining=function(name) return api.remaining[tostring(name or ""):lower()] end
  api.all=function() local result={}; for i,item in ipairs(api.items) do result[i]=runeCopy(item) end; return result end
  return api
end
function Main.syncRunesApi(state)
  local root=rawget(_G,"DGHUD"); if not root then return end
  local api=Main.installRunesApi(root); api.items={}; api.by_name={}; api.remaining={}
  for i,item in ipairs(state and state.runes and state.runes.items or {}) do local copy=runeCopy(item); api.items[i]=copy; api.by_name[copy.name:lower()]=copy; api.remaining[copy.name:lower()]=copy.remaining end
end
function Main.installColorizerApi(namespace)
  local api=type(namespace.colors)=="table" and namespace.colors or {}; namespace.colors=api
  local function active() local root=rawget(_G,"DGHUD"); local controller=root and root.controller; return controller,controller and controller.colorizer end
  api.setEnabled=function(value) local controller,colorizer=active(); if not colorizer then return nil,"colorizer is not running" end; return controller:setColorizerEnabled(value==true) end
  api.toggle=function() local controller,colorizer=active(); if not colorizer then return nil,"colorizer is not running" end; return controller:setColorizerEnabled(not colorizer.enabled) end
  api.setFeature=function(name,value) local controller,colorizer=active(); if not colorizer then return nil,"colorizer is not running" end; return controller:setColorFeature(tostring(name or ""):lower(),value==true) end
  api.status=function() local _,colorizer=active(); if not colorizer then return nil,"colorizer is not running" end; return colorizer:status() end
  return api
end
function Main:setColorizerEnabled(enabled)
  enabled=enabled==true; self.colorizer_enabled=enabled
  if self.colorizer then self.colorizer:setEnabled(enabled) end
  self.settings.colorization=type(self.settings.colorization)=="table" and self.settings.colorization or {}; self.settings.colorization.enabled=enabled
  local root=rawget(_G,"DGHUD")
  if root then root.user_settings=type(root.user_settings)=="table" and root.user_settings or {}; root.user_settings.colorization=type(root.user_settings.colorization)=="table" and root.user_settings.colorization or {}; root.user_settings.colorization.enabled=enabled end
  if self.view and self.view.setColorEnabled then self.view:setColorEnabled(enabled) end
  return enabled
end
function Main:setColorFeature(name,enabled)
  if not self.colorizer then return nil,"colorizer is not running" end
  local result,err=self.colorizer:setFeature(name,enabled); if result==nil then return nil,err end
  local key=name.."_enabled"; self.settings.colorization=type(self.settings.colorization)=="table" and self.settings.colorization or {}; self.settings.colorization[key]=result
    if name=="highlights" then for _,feature in ipairs({"portal","attack","damage","danger","recovery","upkeep","spell","discovery","illumination"}) do self.settings.colorization[feature.."_enabled"]=result end end
  local root=rawget(_G,"DGHUD")
  if root then
    root.user_settings=type(root.user_settings)=="table" and root.user_settings or {}; root.user_settings.colorization=type(root.user_settings.colorization)=="table" and root.user_settings.colorization or {}; root.user_settings.colorization[key]=result
    if name=="highlights" then for _,feature in ipairs({"portal","attack","damage","danger","recovery","upkeep","spell","discovery","illumination"}) do root.user_settings.colorization[feature.."_enabled"]=result end end
  end
  if self.view and self.view.setColorOptions then self.view:setColorOptions(colorOptions(self.colorizer:status())) end
  return result
end
function Main:clockDisplay()
  local real
  if type(self.adapter.localTime)=="function" then local ok,value=pcall(self.adapter.localTime,self.adapter); if ok then real=value end end
  if not real then real=os.date("%I:%M:%S %p"):gsub("^0","") end
  local game=self.clock and self.clock:current(self.adapter:epoch())
  return {real_time=real,game_time=Clock.format(game),period=game and game.period or "—"}
end
function Main:refreshClock()
  local clock=self:clockDisplay()
  if self.last_state then self.last_state.clock=clock end
  if self.view and type(self.view.updateClock)=="function" then self.view:updateClock(clock) end
  return clock
end
function Main:refresh()
  local normalized=State.normalize(self.adapter:getGMCP(),self.collector and self.collector.snapshot or {})
  local posture=self.posture and self.posture:status() or nil
  if not posture and self.adapter.getPostureVariables then local ok,value=pcall(self.adapter.getPostureVariables,self.adapter); if ok and type(value)=="table" then posture=value end end
  if type(posture)=="table" then normalized.vitals.standing=posture.standing; normalized.vitals.sitting=posture.sitting; normalized.vitals.unconscious=posture.unconscious end
  if self.roundtime_display~=nil then normalized.vitals.roundtime=self.roundtime_display end; normalized.clock=self:clockDisplay()
  local signature=(normalized.vitals.psi.visible and "1" or "0")..(normalized.vitals.web.visible and "1" or "0")
  self.last_state=normalized
  if signature~=self.layout_vitals_signature then self:applyResponsiveLayout(normalized) end
  self.view:update(normalized); Main.syncRunesApi(normalized); if self.chat then self.chat:syncCharacter() end; return true
end
function Main:onClockSync(value) local ok,err=self.clock:sync(value,self.adapter:epoch()); if not ok then return nil,err end; self:refreshClock(); return true end
function Main:scheduleClockTick()
  if self.clock_timer then return true end
  local starter=self.adapter.startClockTimer
  if type(starter)~="function" then return nil,"clock timer is unavailable" end
  local id,err=starter(self.adapter,function() if self.started then self:refreshClock() end end)
  if not id then return nil,err or "clock timer could not be created" end
  self.clock_timer=id; return true
end
function Main:characterName()
  if self.character_entry_name and self.character_entry_name~="" then return self.character_entry_name end
  return self.last_state and self.last_state.character and self.last_state.character.full_name or nil
end
function Main:onCharacterEntry(name)
  name=tostring(name or ""):match("^%s*(.-)%s*$")
  if self.character_entry_started and (name=="" or name==self.character_entry_name) then return false end
  self.character_entry_started=true; self.character_entry_name=name~="" and name or self.character_entry_name
  if self.chat then self.chat:syncCharacter() end
  local function refreshCommands()
    local collector=self.collector
    if collector then collector:refresh() end
  end
  if self.adapter.consumeUpdateReinstall and self.adapter:consumeUpdateReinstall() then refreshCommands(); return true end
  if not self.updater or not self.updater.checkAtCharacterEntry then refreshCommands(); return true end
  local ok,err=self.updater:checkAtCharacterEntry(function() refreshCommands() end)
  if not ok then refreshCommands() end
  return ok,err
end
function Main:startChat()
  local settings=self.settings.chat or {}
  if settings.enabled==false then return true end
  local visibleLimit=ChatHistory.visibleLimit(settings.visible_limit)
  local storage=self.adapter:createChatStorage(visibleLimit)
  self.chat=ChatController.new(self.adapter,ChatParser,ChatHistory.new(visibleLimit,settings.dedupe_seconds or 3),storage,function(entries,categories,filter)
    if self.view and self.view.renderChat then self.view:renderChat(entries,categories,filter) end
  end,function() return self:characterName() end)
  if self.view and self.view.setChatFilterCallback then
    self.view:setChatFilterCallback(function(category)
      local chat=self.chat
      if not chat then return nil,"chatbox is not running" end
      return chat:setFilter(category)
    end)
  end
  return self.chat:start()
end
function Main:chatStatus()
  if not self.chat then return {active_filter="OFF",visible_count=0,storage_key=nil,last_storage_error=nil} end
  return self.chat:status()
end
function Main:reportChatStatus()
  local status=self:chatStatus()
  local reporter=self.adapter and self.adapter.reportChatStatus
  if type(reporter)=="function" then
    local ok,result=pcall(reporter,self.adapter,status)
    if ok then return result end
  end
  return status
end
function Main:scheduleRoundtimeTick()
  if self.roundtime_timer or self.roundtime_display<=0 then return end
  self.roundtime_timer=self.adapter:schedule(1,function() self.roundtime_timer=nil; self.roundtime_display=math.max(0,self.roundtime_display-1); self:refresh(); self:scheduleRoundtimeTick() end)
end
function Main:onRoundtime(value)
  value=math.max(0,math.floor(tonumber(value) or 0)); if self.roundtime_timer then self.adapter:cancelTimer(self.roundtime_timer); self.roundtime_timer=nil end
  self.roundtime_display=value; if self.walker then self.walker:onRoundtime(value) end; self:refresh(); self:scheduleRoundtimeTick(); return true
end
function Main:applyResponsiveLayout(state)
  local vitals=(state or self.last_state or {}).vitals
  local width,height=self.adapter:getWindowSize(); local layout=Layout.compute(width,height,self.settings.chat,self.settings.mapper,vitals); self.current_layout=layout
  self.layout_vitals_signature=((vitals and vitals.psi and vitals.psi.visible) and "1" or "0")..((vitals and vitals.web and vitals.web.visible) and "1" or "0")
  self.adapter:setBorders(layout.console_left or layout.left,layout.top,layout.console_right or layout.right,layout.bottom)
  if self.view and self.view.applyLayout then self.view:applyLayout(layout) end; return layout
end
function Main:mapperEnabled() return not (self.settings.mapper and self.settings.mapper.enabled==false) end
function Main:mapperStatus(kind,message,isError)
  self.last_mapper_status=tostring(message or kind or "none")
  if kind=="invalid_room" or kind=="ownership_conflict" or kind=="error" or isError==true then self.last_mapper_error=tostring(message or "unknown mapper error") end
  if self.adapter.reportMapperStatus then self.adapter:reportMapperStatus(kind,message) end
end
function Main:mapToolbarAction(action)
  local current=self.automapper and self.automapper:currentRoom()
  if not current then local err="current room is unavailable"; self:mapperStatus("error",err,true); return nil,err end
  local callOk,result,err=pcall(function()
    if action=="center" then return self.map:center(current) end
    if action=="larger" or action=="smaller" then
      local settings=self.settings.mapper or {}
      return self.map:zoom(current,action,settings.zoom_step,settings.zoom_min,settings.zoom_max)
    end
    return nil,"unknown map toolbar action "..tostring(action)
  end)
  if not callOk then err=result; result=nil end
  if result==nil or result==false then err=err or "map toolbar action failed"; self:mapperStatus("error",err,true); return nil,err end
  if action=="center" then self:mapperStatus("centered","Map centered on room "..tostring(current))
  else self:mapperStatus("zoom","Map zoom "..tostring(result)) end
  return result
end
function Main:callSpecialTransition(method,...)
  local tracker=self.special_transition
  if not tracker then return nil end
  local callOk,result,err=pcall(tracker[method],tracker,...)
  if not callOk then err=result; result=nil end
  if err then self:mapperStatus("error",err,true) end
  return result,err
end
function Main:callAutomapper(method,...)
  local callOk,result,err=pcall(self.automapper[method],self.automapper,...)
  if not callOk then
    err=result; result=nil
    pcall(self.automapper.onWrongDirection,self.automapper)
    self:mapperStatus("error",err,true)
  end
  return result,err
end
function Main:mapStatus()
  local managed=0; for _ in pairs(self.managed_rooms or {}) do managed=managed+1 end
  return {
    enabled=self:mapperEnabled(),
    current_room=self.automapper and self.automapper:currentRoom() or nil,
    managed_count=managed,
    active_destination=self.walker and self.walker.destination or "none",
    last_error=self.last_mapper_error or "none",
    last_status=self.last_mapper_status or "none",
  }
end
function Main:reportMapStatus()
  local status=self:mapStatus()
  if self.adapter and type(self.adapter.reportMapStatus)=="function" then return self.adapter:reportMapStatus(status) end
  local line="enabled="..tostring(status.enabled).." current room="..tostring(status.current_room or "none").." managed="..tostring(status.managed_count).." destination="..tostring(status.active_destination or "none").." last status="..tostring(status.last_status).." last error="..tostring(status.last_error)
  if type(_G.cecho)=="function" then pcall(_G.cecho,"\n<gold>[DGHUD Map]<reset> "..line.."\n") end
  return status
end
local function positiveRoom(value)
  local room=tonumber(value)
  return room and room==room and room~=math.huge and room~=-math.huge and room>0 and room%1==0 and room or nil
end
local function denseArray(value,validate,allowEmpty)
  if type(value)~="table" then return nil end
  local count,maximum=0,0
  for key,item in pairs(value) do
    if type(key)~="number" or key<1 or key%1~=0 or not validate(item) then return nil end
    count=count+1; if key>maximum then maximum=key end
  end
  if count~=maximum or not allowEmpty and count==0 then return nil end
  return count
end
local function validRoomID(value) return type(value)=="number" and positiveRoom(value)~=nil end
local function validCommand(value) return type(value)=="string" and value:match("%S")~=nil end
local function appendRooms(target,source,first,last)
  for index=first,last do target[#target+1]=source[index] end
end
function Main:safetySnapshot()
  local ok,data=pcall(self.adapter.getGMCP,self.adapter)
  local info=ok and type(data)=="table" and type(data.Room)=="table" and type(data.Room.Info)=="table" and data.Room.Info or nil
  local current=info and positiveRoom(info.num) or nil
  if not current or not self.walker or type(self.walker.active)~="function" or not self.automapper or not self.special_transition then return nil,"cleanup safety state is unavailable" end
  local activeOK,walkerActive=pcall(self.walker.active,self.walker); if not activeOK or type(walkerActive)~="boolean" then return nil,"cleanup safety state is unavailable" end
  local route={}
  if walkerActive then
    local ownedRoute=self.walker.route
    local roomCount=type(ownedRoute)=="table" and denseArray(ownedRoute.rooms,validRoomID,false) or nil
    local commandCount=type(ownedRoute)=="table" and denseArray(ownedRoute.commands,validCommand,false) or nil
    local index=positiveRoom(self.walker.index); local destination=positiveRoom(self.walker.destination)
    if not roomCount or not commandCount or roomCount~=commandCount+1 or not index or index>commandCount or not destination or ownedRoute.rooms[roomCount]~=destination then return nil,"cleanup safety state is unavailable" end
    appendRooms(route,ownedRoute.rooms,index,roomCount)
  elseif self.generated_command~=nil then return nil,"cleanup safety state is unavailable" end
  local globalPath=rawget(_G,"speedWalkPath")
  local globalDirections=rawget(_G,"speedWalkDir")
  local function emptyNativeRoutePart(value)
    return value==nil or type(value)=="table" and next(value)==nil
  end
  local nativeActive=not (emptyNativeRoutePart(globalPath) and emptyNativeRoutePart(globalDirections))
  if nativeActive then
    local pathCount=denseArray(globalPath,validRoomID,false)
    local directionCount=denseArray(globalDirections,validCommand,false)
    if not pathCount or not directionCount or pathCount~=directionCount then return nil,"cleanup safety state is unavailable" end
    local destination=globalPath[pathCount]
    if walkerActive and destination~=self.walker.destination then return nil,"cleanup safety state is unavailable" end
    appendRooms(route,globalPath,1,pathCount)
  end
  local specialOK,special=pcall(self.special_transition.pending,self.special_transition); if not specialOK then return nil,"cleanup safety state is unavailable" end
  if self.automapper.pending~=nil and type(self.automapper.pending)~="table" then return nil,"cleanup safety state is unavailable" end
  return {current_room=current,walking=walkerActive or nativeActive,route_rooms=route,pending_automap=self.automapper.pending~=nil,pending_special=special~=nil}
end
function Main:beforeCleanupDelete()
  local walkOK,walkErr=self.walker:stop("map cleanup")
  if not walkOK then return nil,walkErr end
  self.generated_command=nil
  local automapCallOK,automapOK,automapErr=pcall(self.automapper.onWrongDirection,self.automapper)
  if not automapCallOK then return nil,tostring(automapOK) end
  if automapOK~=true then return nil,automapErr or "automapper cancellation failed" end
  local specialOK,specialErr=self:callSpecialTransition("cancel","map_cleanup")
  if specialOK~=true then return nil,specialErr or "special transition cancellation failed" end
  return true
end
function Main:afterCleanupDelete(result)
  local deleted={}
  for _,roomID in ipairs(result.deleted or {}) do deleted[roomID]=true; self.managed_rooms[roomID]=nil end
  local refreshed,refreshErr=true,nil
  if type(self.adapter.refreshMap)=="function" then refreshed,refreshErr=self.adapter:refreshMap() end
  if not refreshed then return nil,refreshErr or "map refresh failed" end
  local gmcpOK,data=pcall(self.adapter.getGMCP,self.adapter)
  local info=gmcpOK and type(data)=="table" and type(data.Room)=="table" and type(data.Room.Info)=="table" and data.Room.Info or nil
  local current=info and positiveRoom(info.num) or nil
  if not current then return nil,"cleanup current room state is unavailable" end
  if self:mapperEnabled() then
    local mapped,mapErr=self:callAutomapper("onRoom",info); if not mapped then return nil,mapErr or "current room remap failed" end
    self.managed_rooms[current]=true
  end
  return true
end
function Main:reportCleanup(message,isError)
  message=tostring(message or "cleanup failed"); if #message>1000 then message=message:sub(1,997).."..." end
  if type(self.adapter.reportMapCleanup)=="function" then pcall(self.adapter.reportMapCleanup,self.adapter,message,isError==true) end
  return isError and nil or true,message
end
function Main:previewCleanup(method,target)
  local callOK,preview,err=pcall(self.cleanup[method],self.cleanup,target)
  if not callOK then err=preview; preview=nil end
  if not preview then self:reportCleanup(err,true); return nil,err end
  local ids={}; for index,roomID in ipairs(preview.room_ids) do ids[index]=tostring(roomID) end
  local areas={}; for index,areaID in ipairs(preview.area_ids or {}) do areas[index]=tostring(areaID) end
  local message="Operation: "..preview.operation.."\nArea: "..tostring(preview.area_id or "none")
  if preview.operation=="clear_all" then
    local shown={}; for index=1,math.min(#areas,20) do shown[index]=areas[index] end
    message=message.."\nAreas: "..tostring(#areas).." total"
    if #shown>0 then message=message.." ("..table.concat(shown,",")..(#areas>#shown and ",..." or "")..")" end
    if preview.incremental then message=message.."\nRooms: counted after confirmation in safe batches"
    else message=message.."\nRooms: "..tostring(#preview.room_ids).." total" end
  else
    if #areas>0 then message=message.."\nAreas: "..table.concat(areas,",") end
    message=message.."\nCount: "..tostring(#preview.room_ids).."\nRoom IDs: "..table.concat(ids,",")
  end
  message=message.."\n[DGHUD Map] Preview "..preview.token.." expires in 30 seconds.\n[DGHUD Map] Confirm with: dghud map confirm "..preview.token
  self:reportCleanup(message,false); return preview
end
function Main:confirmCleanup(token)
  self.clear_all_armed_at=nil
  local result,err=self.cleanup:confirm(token)
  if self.view and self.view.setMapClearPending then self.view:setMapClearPending(false) end
  if not result then self:reportCleanup(err,true); return nil,err end
  if result.pending then self:reportCleanup("Cleanup started; large map data will be removed in safe batches.",false); return result end
  self:reportCleanup(self:cleanupResultMessage(result),result.error~=nil); return result
end
function Main:cleanupResultMessage(result)
  local function ids(values) local out={}; for i,value in ipairs(values or {}) do out[i]=tostring(value) end; return #out>0 and table.concat(out,",") or "none" end
  local message="Deleted IDs: "..ids(result.deleted).."\nFailed ID: "..tostring(result.failed or "none").."\nUntouched IDs: "..ids(result.untouched).."\nArea deleted: "..tostring(result.area_deleted==true)
  if #(result.deleted_areas or {})>0 then message=message.."\nDeleted areas: "..ids(result.deleted_areas) end
  if result.error then message=message.."\nError: "..tostring(result.error) end
  return message
end
function Main:clearAllMapsAction()
  local pending=self.cleanup and self.cleanup:pending()
  if pending and pending.operation=="clear_all" then
    local now=self.adapter.cleanupClock and self.adapter:cleanupClock() or os.time()
    if self.clear_all_armed_at and now-self.clear_all_armed_at<1 then return nil,"wait one second before confirming clear all" end
    return self:confirmCleanup(pending.token)
  end
  local preview,err=self:previewCleanup("previewAll")
  self.clear_all_armed_at=preview and (self.adapter.cleanupClock and self.adapter:cleanupClock() or os.time()) or nil
  if self.view and self.view.setMapClearPending then self.view:setMapClearPending(preview~=nil) end
  return preview,err
end
function Main:routeShape(fromID,toID,route)
  if type(route)~="table" then return nil,"invalid map route" end
  local commands=type(route.commands)=="table" and route.commands or route
  local path=type(route.rooms)=="table" and route.rooms or (type(_G.speedWalkPath)=="table" and _G.speedWalkPath or nil)
  if not path then return nil,"map route did not provide room numbers" end
  local rooms={}; for index,value in ipairs(path) do rooms[index]=tonumber(value) end
  local copiedCommands={}; for index,value in ipairs(commands) do copiedCommands[index]=value end
  if #rooms==#copiedCommands then table.insert(rooms,1,tonumber(fromID)) end
  if #rooms~=#copiedCommands+1 then return nil,"map route rooms and commands do not match" end
  if tonumber(rooms[1])~=tonumber(fromID) or tonumber(rooms[#rooms])~=tonumber(toID) then return nil,"map route endpoints do not match" end
  return {rooms=rooms,commands=copiedCommands}
end
function Main:walkTo(destination,providedRoute)
  if not self:mapperEnabled() then return nil,"mapper is disabled" end
  destination=tonumber(destination)
  if not destination or destination<=0 or destination%1~=0 then return nil,"destination room must be a positive integer" end
  local current=self.automapper and self.automapper:currentRoom()
  if not current then return nil,"current room is unavailable" end
  local route,routeErr=providedRoute,nil; if not route then route,routeErr=self.map:route(current,destination) end
  if not route then return nil,routeErr or "route unavailable" end
  local shaped,shapeErr=self:routeShape(current,destination,route); if not shaped then return nil,shapeErr end
  local ok,err=self.walker:start(shaped,destination); if not ok then return nil,err end
  return true
end
function Main:installMapClickHook()
  if not self:mapperEnabled() then return true end
  self.previous_speed_walk=rawget(_G,"doSpeedWalk")
  local controller=self
  self.speed_walk_hook=function()
    local sourcePath=type(_G.speedWalkPath)=="table" and _G.speedWalkPath or nil
    local sourceCommands=type(_G.speedWalkDir)=="table" and _G.speedWalkDir or nil
    local path,commands
    if sourcePath and sourceCommands then
      path={}; commands={}
      for index,roomID in ipairs(sourcePath) do path[index]=roomID end
      for index,command in ipairs(sourceCommands) do commands[index]=command end
    end
    local destination=path and path[#path] or nil
    local owned=destination~=nil and controller.map and type(controller.map.isOwned)=="function"
    if owned then for _,roomID in ipairs(path) do if not controller.map:isOwned(tonumber(roomID)) then owned=false; break end end end
    if not owned then
      if type(controller.previous_speed_walk)=="function" then return controller.previous_speed_walk() end
      return nil,"clicked route is not owned by DragonsGateHUD"
    end
    return controller:walkTo(destination,{rooms=path,commands=commands})
  end
  _G.doSpeedWalk=self.speed_walk_hook
end
function Main:removeMapClickHook()
  if self.speed_walk_hook and rawget(_G,"doSpeedWalk")==self.speed_walk_hook then _G.doSpeedWalk=self.previous_speed_walk end
  self.speed_walk_hook=nil; self.previous_speed_walk=nil
end
function Main:start()
  if self.started then return true end
  self.original_borders={0,0,0,0}
  local mapOk,map,mapErr=pcall(function() if self.adapter.createMapAdapter then return self.adapter:createMapAdapter() end; return MapAdapter.new(MapAdapter.mudletApi(_G)) end)
  if not mapOk then self:shutdown(); return nil,map end
  if not map then self:shutdown(); return nil,mapErr or "map adapter construction failed" end
  self.map=map
  if self.adapter.suppressDefaultMapInfo then
    local infoOk,infoResult,infoErr=pcall(self.adapter.suppressDefaultMapInfo,self.adapter)
    if not infoOk then self:mapperStatus("warning","Map information cleanup failed: "..tostring(infoResult),true)
    elseif infoResult==nil then self:mapperStatus("warning","Map information cleanup failed: "..tostring(infoErr),true) end
  end
  if type(self.map.migrateLegacyRoomNames)=="function" then
    local cleanupOk,cleanupResult,cleanupErr=pcall(self.map.migrateLegacyRoomNames,self.map)
    if not cleanupOk then self:mapperStatus("warning","Map label cleanup failed: "..tostring(cleanupResult),true)
    elseif cleanupResult==nil then self:mapperStatus("warning","Map label cleanup failed: "..tostring(cleanupErr),true) end
  end
  local factory=self.createAutomapper or function(_,model,adapter,status) return Automapper.new(model,adapter,status) end
  local automapperOk,automapper,automapperErr=pcall(factory,self,MapperModel,self.map,function(kind,message) self:mapperStatus(kind,message) end)
  if not automapperOk then self:shutdown(); return nil,automapper end
  if not automapper then self:shutdown(); return nil,automapperErr or "automapper construction failed" end
  self.automapper=automapper
  local mapperSettings=self.settings.mapper or {}
  self.special_transition=SpecialTransition.new(MapperModel,self.adapter,mapperSettings.special_timeout or 12,nil,mapperSettings.special_patterns)
  local walkerAdapter={owner=self}
  function walkerAdapter:sendCommand(command)
    self.owner.generated_command=command
    local ok,err=self.owner.adapter:sendCommand(command)
    if ok==false or err~=nil then self.owner.generated_command=nil; return nil,err or "movement command failed" end
    return true
  end
  function walkerAdapter:validateStep(fromID,toID,command) return self.owner.map:validateRouteStep(fromID,toID,command) end
  function walkerAdapter:schedule(delay,callback) return self.owner.adapter:schedule(delay,callback) end
  function walkerAdapter:cancelTimer(id) return self.owner.adapter:cancelTimer(id) end
  function walkerAdapter:clearGenerated() self.owner.generated_command=nil end
  self.walker=MapWalker.new(walkerAdapter,function(kind,message,isError) self:mapperStatus(kind,message,isError) end,(self.settings.mapper and self.settings.mapper.walk_timeout) or 12)
  local initialVitals=self.adapter:getGMCP(); initialVitals=initialVitals and initialVitals.Char and initialVitals.Char.Vitals
  self.roundtime_display=math.max(0,math.floor(tonumber(initialVitals and initialVitals.roundtime) or 0)); self.walker:onRoundtime(self.roundtime_display)
  local cleanupRuntime={owner=self}
  function cleanupRuntime:safetySnapshot(roomIDs) return self.owner:safetySnapshot(roomIDs) end
  function cleanupRuntime:beforeDelete(plan) return self.owner:beforeCleanupDelete(plan) end
  function cleanupRuntime:afterDelete(result)
    local ok,err=self.owner:afterCleanupDelete(result)
    if result.background then self.owner:reportCleanup(self.owner:cleanupResultMessage(result),result.error~=nil or not ok) end
    return ok,err
  end
  local clock=function() return self.adapter:cleanupClock() end
  local tokenFactory=function() local token,err=self.adapter:cleanupToken(); if not token then error(err or "secure random source is unavailable",0) end; return token end
  self.cleanup=Cleanup.new(self.map,cleanupRuntime,clock,tokenFactory,30)
  self:installMapClickHook()
  local startupOk,startupErr=pcall(function()
  self.view=self.adapter:createView(self.settings)
  self.posture=PostureTracker.new(self.adapter,function() if self.started then self:refresh() end end)
  self.roller=Autoroller.new(self.adapter,self.settings.roller,function(config)
    if self.adapter.saveRollerSettings then local saved,err=self.adapter:saveRollerSettings(config); if not saved then return nil,"Could not save settings: "..tostring(err) end end
    self.settings.roller=config; local root=rawget(_G,"DGHUD"); if root then root.user_settings=type(root.user_settings)=="table" and root.user_settings or {}; root.user_settings.roller=config end; return true
  end)
  if self.view.setColorToggleCallback then self.view:setColorToggleCallback(function(wanted) local enabled=self:setColorizerEnabled(type(wanted)=="boolean" and wanted or not self.colorizer_enabled); if self.adapter.reportColorizerStatus then self.adapter:reportColorizerStatus(self.colorizer:status()) end; return enabled end) end
  if self.view.setColorOptionsCallback then self.view:setColorOptionsCallback(function(name,wanted) local feature=name=="room_titles" and "room" or name; local enabled,err=self:setColorFeature(feature,wanted); if enabled==nil then return nil,err end; if self.adapter.reportColorizerStatus then self.adapter:reportColorizerStatus(self.colorizer:status()) end; return enabled end) end
  local colorSettings=type(self.settings.colorization)=="table" and self.settings.colorization or {}
  if self.view.setColorOptions then
    local initial={enabled=self.colorizer_enabled,room=colorSettings.room_enabled~=false,exits=colorSettings.exits_enabled~=false,currency=colorSettings.currency_enabled~=false}
    local legacy=colorSettings.highlights_enabled~=false
    for _,name in ipairs({"portal","attack","damage","danger","recovery","upkeep","spell","discovery","illumination"}) do local value=colorSettings[name.."_enabled"]; if value==nil then initial[name]=legacy else initial[name]=value~=false end end
    self.view:setColorOptions(initial)
  elseif self.view.setColorEnabled then self.view:setColorEnabled(self.colorizer_enabled) end
  if self.view.setHelpCloseCallback then self.view:setHelpCloseCallback(function() return true end) end
  if self.view.setOptionsActionCallback then self.view:setOptionsActionCallback(function(action)
    if action=="roller_settings" then local status=self.roller and {config=self.roller.cfg}; return status and status.config end
    local command=({roller_start="start",roller_stop="stop",roller_stats="stats",roller_last="last",roller_reset="reset",roller_help="help"})[action]
    if not command then return nil,"unknown autoroller action" end; return self.roller:command(command)
  end) end
  if self.view.setRollerSettingsCallback then self.view:setRollerSettingsCallback(function(values) local ok,err=self.roller:configure(values); if not ok then return nil,err end; return true,nil,self.roller.cfg end) end
  if self.view.setMapZoomCallback then self.view:setMapZoomCallback(function(action) return self:mapToolbarAction(action) end) end
  if self.view.setMapClearAllCallback then self.view:setMapClearAllCallback(function() return self:clearAllMapsAction() end) end
  self:applyResponsiveLayout()
  self.collector=Collector.new(self.adapter,Parser,function(snapshot,key) if key=="time" then self:onClockSync(snapshot.time) else self:refresh() end end,function(value) self:onRoundtime(value) end,function(name) self:onCharacterEntry(name) end); local collectorOk,collectorErr=self.collector:start(); if not collectorOk then error(collectorErr,0) end
  self.colorizer=OutputColorizer.new(self.adapter,self.colorizer_enabled==true,self.settings.colorization); local colorizerOk,colorizerErr=self.colorizer:start(); if not colorizerOk then error(colorizerErr,0) end
  if self.adapter.isCharacterActive and self.adapter:isCharacterActive() then self:onCharacterEntry() end
  for _,name in ipairs(Events.gmcp) do local eventName=name; self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(eventName,function()
    if eventName=="gmcp.Char.Vitals" then local data=self.adapter:getGMCP(); local vitals=data and data.Char and data.Char.Vitals; self:onRoundtime(vitals and vitals.roundtime or 0); return end
    self:refresh()
  end) end
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(Events.mapper.room,function()
    local data=self.adapter:getGMCP(); local info=data and data.Room and data.Room.Info; local ok,err
    if self:mapperEnabled() then
      local transition=self:callSpecialTransition("onRoom",info and info.num)
      if transition then self:callAutomapper("onSpecialTransition",transition) end
      ok,err=self:callAutomapper("onRoom",info); if ok and info and tonumber(info.num) then self.managed_rooms[tonumber(info.num)]=true end
    else self:callSpecialTransition("cancel","disabled"); ok=true end
    if self.walker and self.walker:active() then
      local vitals=data and data.Char and data.Char.Vitals; self.walker:onRoundtime(vitals and vitals.roundtime or 0)
      if not ok then self.walker:stop(err or "room mapping failed",true) else self.walker:onRoom(info and info.num) end
    end; self:refresh()
  end)
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(Events.mapper.wrong,function(_,direction) self:callSpecialTransition("cancel","wrong_direction"); self.automapper:onWrongDirection(direction); self.walker:onWrongDirection(); self:refresh() end)
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(Events.mapper.outgoing,function(_,command)
    local canonical=MapperModel.direction(command); local generated=command==self.generated_command
    if generated then self.generated_command=nil end
    self.walker:onManualMovement(command,generated)
    if self:mapperEnabled() then
      self.automapper:onOutgoing(command)
      if canonical then self:callSpecialTransition("cancel","direction") else self:callSpecialTransition("onOutgoing",command,self.automapper:currentRoom()) end
    else self:callSpecialTransition("cancel","disabled") end
  end)
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(Events.mapper.disconnect,function() self.character_entry_started=false; self.character_entry_name=nil; self:callSpecialTransition("cancel","disconnect"); self.automapper:onDisconnect(); self.walker:stop("disconnected") end)
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent("sysWindowResizeEvent",function() self:applyResponsiveLayout() end)
  local function aliasArgument(value) if type(value)=="table" then return value[2] end; return value or (type(_G.matches)=="table" and _G.matches[2]) end
  local commands={function() if self.updater then self.updater:check() end end,function() if self.updater then self.updater:update() end end,function() self:reload() end,function() if self.adapter.openSettings then self.adapter:openSettings() end end,function() if self.adapter.requestPurge then self.adapter:requestPurge() end end,function() return self:reportChatStatus() end,function(value) return self:walkTo(aliasArgument(value)) end,function() return self.walker:stop("requested") end,function() local room=self.automapper:currentRoom(); if not room then return nil,"current room is unavailable" end; return self.map:center(room) end}
  for i,pattern in ipairs(Events.aliases) do self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias(pattern,commands[i]) end
  self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias("^dghud mapstatus$",function() return self:reportMapStatus() end)
  local cleanupAliases={
    {"^dghud map delete room (\\d+)$",function(value) return self:previewCleanup("previewRoom",aliasArgument(value)) end},
    {"^dghud map clear submap (\\d+)$",function(value) return self:previewCleanup("previewSubmap",aliasArgument(value)) end},
    {"^dghud map clear area (.+)$",function(value) return self:previewCleanup("previewArea",aliasArgument(value)) end},
    {"^dghud map clear current$",function()
      local data=self.adapter:getGMCP(); local info=data and data.Room and data.Room.Info
      local room=info and tonumber(info.num) or self.automapper:currentRoom()
      if not room then local err="current room is unavailable"; self:reportCleanup(err,true); return nil,err end
      return self:previewCleanup("previewCurrent",room)
    end},
    {"^dghud map clear all$",function() return self:clearAllMapsAction() end},
    {"^dghud map confirm (\\S+)$",function(value) return self:confirmCleanup(aliasArgument(value)) end},
    {"^dghud map cancel$",function() local ok,err=self.cleanup:cancel(); self.clear_all_armed_at=nil; if self.view and self.view.setMapClearPending then self.view:setMapClearPending(false) end; if not ok then self:reportCleanup(err,true); return nil,err end; self:reportCleanup("Cleanup preview cancelled.",false); return true end},
  }
  for _,entry in ipairs(cleanupAliases) do self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias(entry[1],entry[2]) end
  self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias("^dghud colors(?: (.*))?$",function(value)
    local action=tostring(aliasArgument(value) or "toggle"):lower():match("^%s*(.-)%s*$"); local enabled,err
    local feature,featureAction=action:match("^(%a+)%s+(%a+)$")
    local validFeature=feature=="highlights"; for _,name in ipairs(colorFeatures) do if feature==name then validFeature=true; break end end
    local validFeatureAction=featureAction=="on" or featureAction=="off" or featureAction=="toggle" or featureAction=="status"
    if validFeature and validFeatureAction then
      local current=self.colorizer:status()[feature]
      if featureAction=="status" then enabled=current else enabled,err=self:setColorFeature(feature,featureAction=="on" or (featureAction=="toggle" and not current)) end
    elseif action=="on" then enabled=self:setColorizerEnabled(true)
    elseif action=="off" then enabled=self:setColorizerEnabled(false)
    elseif action=="toggle" or action=="" then enabled=self:setColorizerEnabled(not self.colorizer_enabled)
    elseif action=="status" then enabled=self.colorizer:status().enabled
    else return nil,"usage: dghud colors [on|off|toggle|status|room|exits|currency|highlights|portal|attack|damage|danger|recovery|upkeep|spell|discovery|illumination]" end
    if enabled==nil then return nil,err end
    if self.adapter.reportColorizerStatus then self.adapter:reportColorizerStatus(self.colorizer:status()) end; return enabled
  end)
  self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias("^dghud help$",function()
    if not self.view or not self.view.showHelp then return nil,"help panel is unavailable" end
    return self.view:showHelp()
  end)
  self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias("^rr(?:\\s+(.*))?$",function(value) return self.roller:command(aliasArgument(value) or "help") end)
  self.started=true; local data=self.adapter:getGMCP(); if self:mapperEnabled() and data and data.Room and data.Room.Info then local mapped=self.automapper:onRoom(data.Room.Info); if mapped and tonumber(data.Room.Info.num) then self.managed_rooms[tonumber(data.Room.Info.num)]=true end end; self:refresh(); self:scheduleRoundtimeTick(); self:scheduleClockTick()
  local chatStarted,chatErr=self:startChat(); if not chatStarted then error(chatErr,0) end
  self.runtime.triggers[#self.runtime.triggers+1]=self.adapter:addLineTrigger(function(line) self:callSpecialTransition("onLine",line) end)
  self.runtime.triggers[#self.runtime.triggers+1]=self.adapter:addLineTrigger(function(line) self.posture:onLine(line); self.roller:onLine(line) end)
  end)
  if not startupOk then pcall(function() self:shutdown() end); return nil,startupErr end
  return true
end
function Main:shutdown()
  if self.clock_timer then
    if type(self.adapter.stopClockTimer)=="function" then self.adapter:stopClockTimer(self.clock_timer) else self.adapter:cancelTimer(self.clock_timer) end
    self.clock_timer=nil
  end
  if self.roundtime_timer then self.adapter:cancelTimer(self.roundtime_timer); self.roundtime_timer=nil end
  local chat=self.chat; self.chat=nil; if chat then chat:shutdown() end
  local colorizer=self.colorizer; self.colorizer=nil; if colorizer then colorizer:shutdown() end
  local roller=self.roller; self.roller=nil; if roller then roller:shutdown() end
  if self.collector then self.collector:shutdown(); self.collector=nil end
  if self.walker then self.walker:shutdown(); self.walker=nil end; self.generated_command=nil; self:removeMapClickHook()
  if self.special_transition then self:callSpecialTransition("shutdown"); self.special_transition=nil end
  self.cleanup=nil
  if self.automapper then self.automapper:shutdown(); self.automapper=nil end; self.map=nil
  for _,id in ipairs(self.runtime.events) do self.adapter:killEvent(id) end; for _,id in ipairs(self.runtime.aliases) do self.adapter:killAlias(id) end; for _,id in ipairs(self.runtime.triggers or {}) do self.adapter:killTrigger(id) end
  self.runtime={events={},aliases={},triggers={}}; if self.view then self.view:delete(); self.view=nil end
  if self.original_borders then self.adapter:setBorders(self.original_borders[1],self.original_borders[2],self.original_borders[3],self.original_borders[4]); self.original_borders=nil end
  self.character_entry_started=false; self.character_entry_name=nil; self.started=false; return true
end
function Main:reload() self:shutdown(); return self:start() end
function Main:healthCheck()
  local chatEnabled=not (self.settings.chat and self.settings.chat.enabled==false)
  if not self.started or not self.view or not self.collector or not self.collector.started or not self.colorizer or not self.colorizer.started or not self.colorizer.trigger or not self.roller or not self.automapper or not self.special_transition or (chatEnabled and (not self.chat or not self.chat.started or not self.chat.trigger)) or #self.runtime.events~=(#Events.gmcp+5) or #self.runtime.aliases~=(#Events.aliases+11) or #self.runtime.triggers~=2 then return nil,"HUD is not healthy" end
  local ok=pcall(function() self:refresh() end); if not ok then return nil,"state refresh failed" end; return true
end
return Main
