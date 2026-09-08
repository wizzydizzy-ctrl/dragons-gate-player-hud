package.loaded["output_colorizer"]=nil
local State=require("state"); local Events=require("events"); local Layout=require("layout"); local Parser=require("command_parser"); local Collector=require("command_collector"); local Clock=require("game_clock"); local ChatParser=require("chat_parser"); local ChatHistory=require("chat_history"); local ChatController=require("chat_controller"); local OutputColorizer=require("output_colorizer"); local PostureTracker=require("posture_tracker"); local NeedsTracker=require("needs_tracker"); local Autoroller=require("autoroller"); local MapperModel=require("mapper_model"); local MapAdapter=require("map_adapter"); local MapTransfer=require("map_transfer"); local MapCatalog=require("map_catalog"); local MapCollections=require("map_collections"); local Automapper=require("automapper"); local SpecialTransition=require("special_transition"); local MapWalker=require("map_walker"); local Cleanup=require("map_cleanup"); local MapDiagnostics=require("map_diagnostics"); local FailureReport=require("failure_report")
local Main={}; Main.__index=Main
local colorFeatures={"room","exits","currency","races","classes","portal","attack","damage","danger","recovery","upkeep","spell","discovery","illumination"}
local function colorOptions(status)
  local result={enabled=status.enabled}
  for _,name in ipairs(colorFeatures) do result[name]=status[name] end
  return result
end
function Main.new(adapter,settings)
  adapter.settings=settings
  local colorSettings=settings and settings.colorization
  local self=setmetatable({adapter=adapter,settings=settings,runtime={events={},aliases={},triggers={}},started=false,roundtime_display=nil,managed_rooms={},colorizer_enabled=not (type(colorSettings)=="table" and colorSettings.enabled==false)},Main)
  self.clock=Clock.new(settings and settings.time,function() return adapter:epoch() end)
  self.map_diagnostics=MapDiagnostics.new(settings and settings.version,settings and settings.edition,function() return adapter.cleanupClock and adapter:cleanupClock() or os.time() end)
  self.failure_reports=FailureReport.new({version=settings and settings.version,edition=settings and settings.edition,clock=function() return adapter.cleanupClock and adapter:cleanupClock() or os.time() end,save=function(report) if adapter.saveFailureReport then return adapter:saveFailureReport(report) end end,submit=function(report,done) if not adapter.submitFailureReport then return nil,"anonymous failure reporting is unavailable" end; return adapter:submitFailureReport(report,done) end})
  return self
end
function Main:captureFailure(category,message,context)
  if not self.failure_reports then return nil,"failure reporting is unavailable" end
  local report=self.failure_reports:record(category,message,context); self.last_failure_report=report; return report
end
function Main:saveMapCollectionIndex()
  if not self.map_collections or not self.adapter.saveMapCollectionIndex then return nil,"map collections are unavailable" end
  return self.adapter:saveMapCollectionIndex(self.map_collections:exportState())
end
function Main:saveActiveMapCollection()
  local active=self.map_collections and self.map_collections:active(); if not active then return nil,"active map collection is unavailable" end
  local metadata,err=self.adapter:saveMapCollection(active.id); if not metadata then self:captureFailure("map_collection",err,{operation="save",collection=active.id}); return nil,err end
  local updated,updateErr=self.map_collections:updateSnapshot(active.id,metadata); if not updated then return nil,updateErr end
  local saved,indexErr=self:saveMapCollectionIndex(); if not saved then return nil,indexErr end; return updated
end
function Main:initializeMapCollections()
  if not self.adapter.loadMapCollectionIndex or not self.adapter.saveMapCollection then return true end
  self.map_collection_counter=0
  local function idFactory() self.map_collection_counter=self.map_collection_counter+1; return "map-"..tostring(os.time()).."-"..tostring(self.map_collection_counter) end
  self.map_collection_options={clock=function() return os.time() end,id_factory=idFactory}
  local state,indexErr=self.adapter:loadMapCollectionIndex(); if not state and indexErr~="map collection index was not found" then return nil,indexErr end
  local manager,err=MapCollections.new(state,self.map_collection_options); if not manager then return nil,err end
  self.map_collections=manager
  if #manager:list()==0 then
    local initial,createErr=manager:create("My Maps",{kind="local_map"},true); if not initial then return nil,createErr end; assert(manager:setActive(initial.id))
    local metadata,saveErr=self.adapter:saveMapCollection(initial.id); if not metadata then return nil,saveErr end; assert(manager:updateSnapshot(initial.id,metadata)); return self:saveMapCollectionIndex()
  end
  if not manager:active() then manager:setActive(manager:list()[1].id); return self:saveMapCollectionIndex() end
  return true
end
function Main:restoreMapCollectionState(state) self.map_collections=assert(MapCollections.new(state,self.map_collection_options)); return true end
function Main:listMapCollections() return self.map_collections and self.map_collections:list() or {} end
function Main:presentMapCollections(status)
  if not self.view or not self.view.setMapCollections then return true end
  local active=self.map_collections and self.map_collections:active(); local rows={}
  for _,item in ipairs(self:listMapCollections()) do rows[#rows+1]={id=item.id,name=item.name,creator=item.source and item.source.publisher or "You",room_count=item.snapshot and item.snapshot.room_count or 0,active=active and active.id==item.id,editable=item.editable,version=item.source and item.source.artifact_id} end
  return self.view:setMapCollections(rows,status)
end
function Main:switchMapCollection(id)
  local target=self.map_collections and self.map_collections:get(id); if not target then return nil,"map collection does not exist" end
  local current=self.map_collections:active(); if current and current.id==target.id then return target end
  local saved,saveErr=self:saveActiveMapCollection(); if not saved then return nil,"current map could not be saved: "..tostring(saveErr) end
  local function restore(message)
    local restored,restoreErr=current and self.adapter:loadMapCollection(current.id); self.map_collections:setActive(current and current.id or nil)
    if current and not restored then self.map_collection_unsafe=true; message=tostring(message).."; CRITICAL: previous map restore failed: "..tostring(restoreErr) end
    return nil,message
  end
  local loaded,loadErr=self.adapter:loadMapCollection(target.id); if not loaded then self:captureFailure("map_collection",loadErr,{operation="switch",collection=target.id}); return restore(loadErr) end
  self.map_collections:setActive(target.id); local indexed,indexErr=self:saveMapCollectionIndex(); if not indexed then return restore(indexErr) end
  if self.automapper then self.automapper:onDisconnect(); local data=self.adapter:getGMCP(); local info=data and data.Room and data.Room.Info; if info then self.automapper:onRoom(info) end end
  self:refresh(); return self.map_collections:active()
end
function Main:createMapCollection(name,source)
  local saved,err=self:saveActiveMapCollection(); if not saved then return nil,err end
  local before=self.map_collections:exportState()
  local item,createErr=self.map_collections:create(name,source or {kind="local_map"},true); if not item then return nil,createErr end
  local metadata,copyErr=self.adapter:saveMapCollection(item.id); if not metadata then self.map_collections:remove(item.id); return nil,copyErr end
  self.map_collections:updateSnapshot(item.id,metadata); local indexed,indexErr=self:saveMapCollectionIndex(); if not indexed then self.adapter:deleteMapCollection(item.id); self:restoreMapCollectionState(before); return nil,indexErr end; return item
end
function Main:forkMapCollection(id,name)
  local source=self.map_collections and self.map_collections:get(id); if not source then return nil,"source collection does not exist" end
  local active=self.map_collections:active(); if not active or active.id~=id then local switched,err=self:switchMapCollection(id); if not switched then return nil,err end end
  local before=self.map_collections:exportState(); local fork,err=self.map_collections:fork(id,name); if not fork then return nil,err end
  local metadata,saveErr=self.adapter:saveMapCollection(fork.id); if not metadata then self.map_collections:remove(fork.id); return nil,saveErr end
  self.map_collections:updateSnapshot(fork.id,metadata); self.map_collections:setActive(fork.id); local indexed,indexErr=self:saveMapCollectionIndex(); if not indexed then self.adapter:deleteMapCollection(fork.id); self:restoreMapCollectionState(before); return nil,indexErr end; return fork
end
function Main:renameMapCollection(id,name)
  name=tostring(name or ""):match("^%s*(.-)%s*$"); if name=="" then return nil,"enter the new map name in the NAME box first" end
  local before=self.map_collections:exportState(); local item,err=self.map_collections:rename(id,name); if not item then return nil,err end; local ok,saveErr=self:saveMapCollectionIndex(); if not ok then self:restoreMapCollectionState(before); return nil,saveErr end; self:presentMapCollections("Renamed map to "..name.."."); return item
end
function Main:backupMapCollection(id)
  local item=self.map_collections:get(id); if not item then return nil,"map collection does not exist" end
  local active=self.map_collections:active(); if not active or active.id~=id then local switched,err=self:switchMapCollection(id); if not switched then return nil,err end end
  local backupName=item.name.." Backup "..os.date("%Y-%m-%d %H:%M"); local backup,err=self:createMapCollection(backupName,{kind="local_map"}); if not backup then return nil,err end
  self:presentMapCollections("Backup created: "..backupName); return backup
end
function Main:deleteMapCollection(id)
  local active=self.map_collections:active(); if active and active.id==id then return nil,"switch to another map before deleting the active map" end
  local before=self.map_collections:exportState(); local token,stageErr=self.adapter:stageDeleteMapCollection(id); if not token then return nil,stageErr end
  local removed,err=self.map_collections:remove(id); if not removed then self.adapter:rollbackDeleteMapCollection(token); return nil,err end
  local indexed,indexErr=self:saveMapCollectionIndex(); if not indexed then self:restoreMapCollectionState(before); self.adapter:rollbackDeleteMapCollection(token); return nil,indexErr end
  local committed,commitErr=self.adapter:commitDeleteMapCollection(token); if not committed then return nil,"collection index was saved but snapshot cleanup failed: "..tostring(commitErr) end; self:presentMapCollections("Deleted "..removed.name.."."); return removed
end
function Main:installDownloadedCollection(entry,model,name)
  local current=self.map_collections:active(); local saved,saveErr=self:saveActiveMapCollection(); if not saved then return nil,saveErr end
  local before=self.map_collections:exportState()
  local function rollback(message)
    self:restoreMapCollectionState(before); local restored,restoreErr=current and self.adapter:loadMapCollection(current.id)
    if current and not restored then message=tostring(message).."; CRITICAL: previous map restore failed: "..tostring(restoreErr) end
    return nil,message
  end
  local source={kind="library",artifact_id=model.provenance.artifact_id,publisher=model.provenance.publisher,slug=model.provenance.slug}
  local item,createErr=self.map_collections:create(name or entry.name,source,true); if not item then return nil,createErr end
  local cleared,clearErr=self.adapter:clearCurrentMap(); if not cleared then self.map_collections:remove(item.id); return nil,clearErr end
  local policies={default="use_imported",rooms={}}; local plan,previewErr=self.map_transfer:preview(model,policies); local result,applyErr=plan and self.map_transfer:apply(plan,self:mapTransferCreator())
  if not result then return rollback(previewErr or applyErr) end
  local metadata,snapshotErr=self.adapter:saveMapCollection(item.id); if not metadata then return rollback(snapshotErr) end
  self.map_collections:updateSnapshot(item.id,metadata); self.map_collections:setActive(item.id); local indexed,indexErr=self:saveMapCollectionIndex(); if not indexed then self.adapter:deleteMapCollection(item.id); return rollback(indexErr) end; self:presentMapCollections("Downloaded as a separate editable map: "..item.name); return item
end
function Main:downloadLibraryCollection(entry,replaceCurrent)
  if type(entry)~="table" then return nil,"select a shared map first" end
  local replaced=self.map_collections and self.map_collections:active(); local backup
  if replaceCurrent and replaced then local made,backupErr=self:backupMapCollection(replaced.id); if not made then return nil,"automatic backup failed: "..tostring(backupErr) end; backup=made end
  self.view.map_library_status="Downloading and verifying "..tostring(entry.name).."…"; if self.view.layout then self.view:layoutMapLibrary(self.view.layout) end
  local function failed(message) self:captureFailure("map_library",message,{operation=replaceCurrent and "replace_collection" or "download_collection",stage="download_or_validation"}); self.view.map_library_status="Map failed: "..tostring(message).." A sanitized report is ready."; if self.view.layout then self.view:layoutMapLibrary(self.view.layout) end end
  local started,err=self.adapter:downloadCatalogMap(entry,function(raw,downloadErr)
    if downloadErr then return failed(downloadErr) end; local model,validationErr=self.map_transfer:validate(raw); if not model then return failed(validationErr) end
    if model.provenance.publisher~=entry.publisher or model.provenance.slug~=entry.slug then return failed("map provenance does not match the catalog") end
    local item,installErr=self:installDownloadedCollection(entry,model,entry.name); if not item then return failed(installErr) end
    if replaceCurrent and replaced then local removed,removeErr=self:deleteMapCollection(replaced.id); if not removed then return failed(removeErr) end end
    self.view:setMapLibraryMode("collections"); self:presentMapCollections(replaceCurrent and ("Replaced the active map. Backup kept as "..tostring(backup and backup.name)..".") or ("Installed "..item.name.." as a separate editable map."))
  end)
  if not started then failed(err) end; return started,err
end
function Main:mergeLibraryIntoCurrent(entry)
  if type(entry)~="table" then return nil,"select a shared map first" end
  local active=self.map_collections and self.map_collections:active(); if not active then return nil,"active map collection is unavailable" end
  self.view.map_library_status="Downloading and checking "..tostring(entry.name).." before combining…"; if self.view.layout then self.view:layoutMapLibrary(self.view.layout) end
  local function failed(message) self.last_mapper_error=tostring(message); self.last_map_library_error=tostring(message); self:captureFailure("map_library",message,{operation="combine_collection",stage="download_or_validation"}); self.view.map_library_status="Combine failed: "..tostring(message).." A sanitized report is ready."; if self.view.layout then self.view:layoutMapLibrary(self.view.layout) end end
  local started,err=self.adapter:downloadCatalogMap(entry,function(raw,downloadErr)
    if downloadErr then return failed(downloadErr) end; local model,validationErr=self.map_transfer:validate(raw); if not model then return failed(validationErr) end
    if model.provenance.publisher~=entry.publisher or model.provenance.slug~=entry.slug then return failed("map provenance does not match the catalog") end
    local policies={default="keep_mine",rooms={}}; local plan,previewErr=self.map_transfer:preview(model,policies); if not plan then return failed(previewErr) end
    self.pending_map_import={name=entry.name,data=model,policies=policies,plan=plan,combine={base_id=active.id,base_name=active.name,incoming_name=entry.name,priority="primary"}}
    return self:reportMapImportPlan(plan,entry.name)
  end)
  if not started then failed(err) end; return started,err
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
  Main.installFailureApi(namespace)
  return chat
end
function Main.installFailureApi(namespace)
  local api=type(namespace.failures)=="table" and namespace.failures or {}; namespace.failures=api
  local function active() local root=rawget(_G,"DGHUD"); local controller=root and root.controller; return controller,controller and controller.failure_reports end
  api.last=function() local _,reports=active(); if not reports then return nil,"failure reporting is unavailable" end; return reports:lastReport() end
  api.report=function(category,message,context) local controller=active(); if not controller then return nil,"HUD is not running" end; return controller:captureFailure(category,message,context) end
  api.submitLast=function(done) local _,reports=active(); if not reports then return nil,"failure reporting is unavailable" end; return reports:submitReport(nil,done) end
  return api
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
  if self.needs then normalized.needs=self.needs:status() end
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
  if not (self.settings.update and self.settings.update.auto_apply==true) then refreshCommands(); return true end
  if not self.updater or not self.updater.update then refreshCommands(); return true end
  local ok,err=self.updater:update(function() refreshCommands() end)
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
function Main:setMapperEnabled(enabled)
  enabled=enabled==true
  local wasEnabled=self:mapperEnabled()
  if wasEnabled==enabled then return enabled end
  local candidate={}; for key,value in pairs(self.settings.mapper or {}) do candidate[key]=value end; candidate.enabled=enabled
  if self.adapter.saveMapperSettings then local saved,err=self.adapter:saveMapperSettings(candidate); if not saved then return nil,"Could not save mapper setting: "..tostring(err) end end
  self.settings.mapper=type(self.settings.mapper)=="table" and self.settings.mapper or {}; self.settings.mapper.enabled=enabled
  local root=rawget(_G,"DGHUD")
  if root then root.user_settings=type(root.user_settings)=="table" and root.user_settings or {}; root.user_settings.mapper=type(root.user_settings.mapper)=="table" and root.user_settings.mapper or {}; root.user_settings.mapper.enabled=enabled end
  if not enabled then
    self:callSpecialTransition("cancel","disabled")
    if self.automapper then self.automapper:onWrongDirection() end
    if self.walker and self.walker:active() then self.walker:stop("mapper disabled") end
    self:removeMapClickHook()
  else
    self:installMapClickHook()
    local data=self.adapter:getGMCP(); local info=data and data.Room and data.Room.Info
    if self.automapper and info then local ok=self:callAutomapper("onRoom",info); if ok and tonumber(info.num) then self.managed_rooms[tonumber(info.num)]=true end end
  end
  if self.view and self.view.setColorOptions then local options=colorOptions(self.colorizer and self.colorizer:status() or {}); options.mapper=enabled; self.view:setColorOptions(options) end
  self:applyResponsiveLayout(); self:refresh(); return enabled
end
function Main:configureMapper(values)
  values=type(values)=="table" and values or {}; local wasEnabled=self:mapperEnabled(); local candidate={}; for k,v in pairs(self.settings.mapper or {}) do candidate[k]=v end
  local rules={minimum_height={90,300},height_percent={.20,.70},maximum_height={140,700},zoom_step={.5,10},zoom_min={3,30},zoom_max={10,100},walk_timeout={3,60},special_timeout={3,60}}
  for key,range in pairs(rules) do local n=tonumber(values[key]); if not n or n<range[1] or n>range[2] then return nil,key.." must be between "..range[1].." and "..range[2] end; candidate[key]=n end
  if candidate.zoom_min>=candidate.zoom_max then return nil,"maximum zoom must be greater than minimum zoom" end
  if candidate.maximum_height<candidate.minimum_height then return nil,"maximum map height must be at least the minimum height" end
  candidate.enabled=values.enabled~=false; candidate.transition_submaps={}; for _,key in ipairs({"gate","portal","door","arch","path","other"}) do candidate.transition_submaps[key]=not (values.transition_submaps and values.transition_submaps[key]==false) end
  if self.adapter.saveMapperSettings then local ok,err=self.adapter:saveMapperSettings(candidate); if not ok then return nil,"Could not save mapper settings: "..tostring(err) end end
  self.settings.mapper=candidate; local root=rawget(_G,"DGHUD"); if root then root.user_settings=root.user_settings or {}; root.user_settings.mapper=candidate end
  if self.automapper then self.automapper.transition_submaps=candidate.transition_submaps end; if self.special_transition then self.special_transition.timeout_seconds=candidate.special_timeout end; if self.walker then self.walker.timeout_seconds=candidate.walk_timeout end
  if wasEnabled and not candidate.enabled then self:callSpecialTransition("cancel","disabled"); if self.automapper then self.automapper:onWrongDirection() end; if self.walker and self.walker:active() then self.walker:stop("mapper disabled") end; self:removeMapClickHook()
  elseif not wasEnabled and candidate.enabled then self:installMapClickHook(); local data=self.adapter:getGMCP(); local info=data and data.Room and data.Room.Info; if self.automapper and info then self:callAutomapper("onRoom",info) end end
  self:applyResponsiveLayout(); self:refresh(); return true,nil,candidate
end
function Main:mapperStatus(kind,message,isError)
  self.last_mapper_status=tostring(message or kind or "none")
  if kind=="invalid_room" or kind=="ownership_conflict" or kind=="error" or isError==true then self.last_mapper_error=tostring(message or "unknown mapper error") end
  if self.map_diagnostics then self.map_diagnostics:record(kind,message) end
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
function Main:mapDiagnosticContext()
  local status=self:mapStatus(); local ownedRooms,ownedAreas=0,0
  if self.map and type(self.map.listRooms)=="function" then local ok,rooms=pcall(self.map.listRooms,self.map); if ok and type(rooms)=="table" then ownedRooms=#rooms end end
  if self.map and self.map.api and type(self.map.api.getAreaTable)=="function" and type(self.map.areaRecord)=="function" then
    local ok,areas=pcall(self.map.api.getAreaTable); if ok and type(areas)=="table" then for _,id in pairs(areas) do local rok,record=pcall(self.map.areaRecord,self.map,id); if rok and record and record.owned then ownedAreas=ownedAreas+1 end end end
  end
  local pending=self.cleanup and self.cleanup:pending(); local safety=self:safetySnapshot(); local mudlet=self.adapter.mudletVersion and self.adapter:mudletVersion()
  return {settings=self.settings.mapper,enabled=status.enabled,current_room=status.current_room,owned_room_count=ownedRooms,owned_area_count=ownedAreas,pending_cleanup=pending and pending.operation or "none",walking=safety and safety.walking or false,pending_automap=safety and safety.pending_automap or false,pending_special=safety and safety.pending_special or false,last_status=status.last_status,last_error=status.last_error,mudlet_version=mudlet}
end
function Main:exportMapDiagnostic(openFolder)
  if not self.map_diagnostics or not self.adapter.saveMapDiagnostic then local err="mapper diagnostics are unavailable"; self:reportCleanup(err,true); return nil,err end
  local payload=self.map_diagnostics:render(self:mapDiagnosticContext()); local path,err=self.adapter:saveMapDiagnostic(payload)
  if not path then self:reportCleanup("Could not save mapper diagnostic: "..tostring(err),true); return nil,err end
  if openFolder and self.adapter.openMapDiagnosticsFolder then self.adapter:openMapDiagnosticsFolder() end
  self:reportCleanup("Mapper diagnostic saved privately: "..path..". It contains no credentials, chat, room prose, character name, IP address, or command history.",false); return path
end
function Main:submitMapDiagnostic()
  if not self.map_diagnostics or not self.adapter.submitFeedback then local err="anonymous mapper diagnostics are unavailable"; self:reportCleanup(err,true); return nil,err end
  local payload=self.map_diagnostics:render(self:mapDiagnosticContext()); self:reportCleanup("Sending privacy-safe mapper diagnostic…",false)
  return self.adapter:submitFeedback({kind="feedback",summary="Automatic mapper diagnostic",details=payload},function(result,err)
    self:reportCleanup(err and ("Could not send mapper diagnostic: "..tostring(err)) or ("Mapper diagnostic sent anonymously. Reference: "..tostring(result.report_id or result.number or "received")),err~=nil)
  end)
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
  if not current and self.automapper and type(self.automapper.currentRoom)=="function" then local currentOK,fallback=pcall(self.automapper.currentRoom,self.automapper); if currentOK then current=positiveRoom(fallback) end end
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
  elseif self.generated_command~=nil then
    -- A generated command can survive a completed/aborted walk when Mudlet does
    -- not deliver the matching outgoing-command event.  With no active walker,
    -- automapper move, or special transition it is stale and must not wedge map
    -- cleanup forever.
    local specialOK,special=pcall(self.special_transition.pending,self.special_transition)
    if not specialOK then return nil,"cleanup safety state is unavailable" end
    if self.automapper.pending~=nil and type(self.automapper.pending)~="table" then self.automapper.pending=nil end
    if self.automapper.pending~=nil or special~=nil then
      return {current_room=current,walking=false,route_rooms=route,pending_automap=self.automapper.pending~=nil,pending_special=special~=nil}
    end
    self.generated_command=nil
  end
  local globalPath=rawget(_G,"speedWalkPath")
  local globalDirections=rawget(_G,"speedWalkDir")
  local function emptyNativeRoutePart(value)
    return value==nil or type(value)=="table" and next(value)==nil
  end
  local nativeActive=not (emptyNativeRoutePart(globalPath) and emptyNativeRoutePart(globalDirections))
  if nativeActive then
    local pathCount=denseArray(globalPath,validRoomID,false)
    local directionCount=denseArray(globalDirections,validCommand,false)
    if not pathCount or not directionCount or pathCount~=directionCount then
      -- Mudlet and other mapper packages can leave partial speedwalk globals
      -- behind after a route finishes.  They are not evidence of live movement
      -- when DGHUD's own walker is idle, so ignore them for cleanup safety.
      if walkerActive then return nil,"cleanup safety state is unavailable" end
      nativeActive=false
    else
      local destination=globalPath[pathCount]
      if walkerActive and destination~=self.walker.destination then return nil,"cleanup safety state is unavailable" end
      appendRooms(route,globalPath,1,pathCount)
    end
  end
  local specialOK,special=pcall(self.special_transition.pending,self.special_transition); if not specialOK then return nil,"cleanup safety state is unavailable" end
  if self.automapper.pending~=nil and type(self.automapper.pending)~="table" then
    if walkerActive then return nil,"cleanup safety state is unavailable" end
    self.automapper.pending=nil
  end
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
  if self.map_diagnostics then self.map_diagnostics:record(isError and "cleanup_error" or "cleanup",message) end
  if type(self.adapter.reportMapCleanup)=="function" then pcall(self.adapter.reportMapCleanup,self.adapter,message,isError==true) end
  if isError and self.adapter and self.adapter.saveMapDiagnostic and not self.writing_map_diagnostic then self.writing_map_diagnostic=true; pcall(function() self.adapter:saveMapDiagnostic(self.map_diagnostics:render(self:mapDiagnosticContext())) end); self.writing_map_diagnostic=false end
  if isError then self:captureFailure("mapper",message,{operation="map_cleanup",stage="cleanup"}) end
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
  if preview.operation=="clear_all" then message=message.."\n[DGHUD Map] Or click the red CLICK AGAIN button to permanently clear every DGHUD map and submap." end
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
    if self.clear_all_armed_at and now-self.clear_all_armed_at<1 then
      local err="CLEAR ALL is armed. Wait one second, then click the red button again."
      self:reportCleanup(err,false); return nil,err
    end
    return self:confirmCleanup(pending.token)
  end
  local preview,err=self:previewCleanup("previewAll")
  self.clear_all_armed_at=preview and (self.adapter.cleanupClock and self.adapter:cleanupClock() or os.time()) or nil
  if self.view and self.view.setMapClearPending then self.view:setMapClearPending(preview~=nil) end
  return preview,err
end
function Main:mapTransferCreator()
  local data=self.adapter:getGMCP(); local status=data and data.Char and data.Char.Status or {}; local name=tostring(status.name or "Unknown"); local surname=tostring(status.surname or "")
  return (name..(surname~="" and (" "..surname) or "")):match("^%s*(.-)%s*$")
end
function Main:reportMapTransfer(message,isError) if isError then self:captureFailure("map_transfer",message,{operation="map_transfer",stage="operation"}) end; if self.adapter.reportMapTransfer then return self.adapter:reportMapTransfer(message,isError) end; return true end
function Main:currentMapSelection(scope)
  if scope=="all" then return {scope="all"} end
  local current=self.automapper and self.automapper:currentRoom(); if not current then return nil,"current room is unavailable" end
  local record,err=self.map:currentTransferScope(current); if not record then return nil,err end
  if scope=="area" then return {scope="area",area=record.area,area_name=record.area_name~="" and record.area_name or nil} end
  return {scope="subarea",partition=record.partition,area=record.area,area_name=record.area_name~="" and record.area_name or nil,subarea_name=record.subarea_name~="" and record.subarea_name or nil}
end
function Main:exportMapTransfer(name,publisher,selection)
  if not tostring(publisher or ""):match("^[%w][%w%-]*$") then local err="publisher name must contain only letters, numbers, and dashes"; self:reportMapTransfer(err,true); return nil,err end
  local stamp=self.adapter.timestamp and self.adapter:timestamp() or tostring(os.time()); local data,err=self.map_transfer:exportData({artifact_id="local:"..stamp..":"..tostring(name),author=self:mapTransferCreator(),publisher=publisher,slug=name},selection)
  if not data then self:reportMapTransfer(err,true); return nil,err end
  local path,saveErr=self.adapter:saveMapTransfer(name,data); if not path then self:reportMapTransfer(saveErr,true); return nil,saveErr end
  self:reportMapTransfer("Saved a private backup of "..#data.rooms.." canonical rooms to "..path..". Use Map Settings > Map Library > SHARE to submit a map anonymously for review.",false); return path
end
local function transferChoice(value) return ({keep="keep_mine",replace="use_imported",skip="skip_area"})[tostring(value or ""):lower()] end
function Main:reportMapImportPlan(plan,name)
  local combine=self.pending_map_import and self.pending_map_import.combine
  if self.view and self.view.setMapLibraryImportPending then self.view:setMapLibraryImportPending(true,combine~=nil) end
  local lines={"Ready to install '"..tostring(name).."': "..plan.creates.." new rooms and "..plan.conflicts.." overlaps."}
  if combine then
    lines[#lines+1]="Current Map: "..tostring(combine.base_name)..". Downloaded Map: "..tostring(combine.incoming_name).."."
    if plan.conflicts>0 then lines[#lines+1]="Choose CURRENT MAP WINS or DOWNLOADED MAP WINS for room-number collisions, or SKIP COLLISIONS, then choose CREATE COMBINED MAP." end
  elseif plan.conflicts>0 then lines[#lines+1]="Choose KEEP MY MAP, USE SHARED MAP, or SKIP THIS AREA, then choose FINISH INSTALLING."
  else lines[#lines+1]="No overlaps found. Choose FINISH INSTALLING to add this map." end
  if plan.blocked then lines[#lines+1]="Some rooms belong to another personal map and cannot be replaced." end
  if self.view then self.view.map_library_status=table.concat(lines," "); if self.view.layout then self.view:layoutMapLibrary(self.view.layout) end end
  self:reportMapTransfer(table.concat(lines,"\n"),plan.blocked); return plan
end
function Main:setDefaultMapImportPolicy(choice)
  local pending=self.pending_map_import; if not pending then return nil,"download and review a map first" end
  local policy=transferChoice(choice); if not policy then return nil,"choice must be keep, replace, or skip" end
  pending.policies={default=policy,rooms={}}
  if pending.combine then pending.combine.priority=policy=="use_imported" and "secondary" or (policy=="keep_mine" and "primary" or "skip") end
  local plan,err=self.map_transfer:preview(pending.data,pending.policies); if not plan then return nil,err end
  pending.plan=plan; return self:reportMapImportPlan(plan,pending.name)
end
function Main:previewMapTransfer(name)
  local data,err=self.adapter:loadMapTransfer(name); if not data then self:reportMapTransfer(err,true); return nil,err end
  local policies={default="keep_mine",rooms={}}; local plan,previewErr=self.map_transfer:preview(data,policies); if not plan then self:reportMapTransfer(previewErr,true); return nil,previewErr end
  self.pending_map_import={name=name,data=data,policies=policies,plan=plan}; return self:reportMapImportPlan(plan,name)
end
function Main:setMapImportPolicy(kind,target,choice)
  local pending=self.pending_map_import; if not pending then return nil,"no map import preview is pending" end; local policy=transferChoice(choice); if not policy then return nil,"choice must be keep, replace, or skip" end
  if kind=="room" then pending.policies.rooms[tonumber(target)]=policy else pending.policies[tostring(target)]=policy end
  local plan,err=self.map_transfer:preview(pending.data,pending.policies); if not plan then self:reportMapTransfer(err,true); return nil,err end; pending.plan=plan; return self:reportMapImportPlan(plan,pending.name)
end
function Main:confirmMapTransfer()
  local pending=self.pending_map_import; if not pending then return nil,"no map import preview is pending" end
  local combined
  if pending.combine then
    local active=self.map_collections and self.map_collections:active(); if not active or active.id~=pending.combine.base_id then return nil,"active map changed; start the combine again" end
    local combinedName=(tostring(pending.combine.base_name).." + "..tostring(pending.combine.incoming_name)):sub(1,100)
    local created,createErr=self:createMapCollection(combinedName,{kind="local_map"}); if not created then self:reportMapTransfer(createErr,true); return nil,createErr end
    local switched,switchErr=self:switchMapCollection(created.id); if not switched then self:reportMapTransfer(switchErr,true); return nil,switchErr end; combined=created
  end
  local result,err=self.map_transfer:apply(pending.plan,self:mapTransferCreator()); if not result then self:reportMapTransfer(err,true); return nil,err end
  if combined then local saved,saveErr=self:saveActiveMapCollection(); if not saved then self:reportMapTransfer("Combined map was applied but could not be saved: "..tostring(saveErr),true); return nil,saveErr end end
  self.pending_map_import=nil; if self.view and self.view.setMapLibraryImportPending then self.view:setMapLibraryImportPending(false) end
  local message=(combined and ("Combined map saved as '"..combined.name.."': ") or "Map installed: ")..result.applied.." rooms added or updated, "..result.kept.." of your rooms kept, "..result.skipped.." skipped."
  self:reportMapTransfer(message,false); if combined and self.view then self.view:setMapLibraryMode("collections"); self:presentMapCollections(message) end; return result
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
  if self.speed_walk_hook and rawget(_G,"doSpeedWalk")==self.speed_walk_hook then return true end
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
  self.map_transfer=MapTransfer.new(self.map)
  local collectionsOK,collectionsErr=self:initializeMapCollections()
  if not collectionsOK then self:captureFailure("map_collection",collectionsErr,{operation="initialize"}); self:shutdown(); return nil,collectionsErr end
  self.map_collection_unsafe=false
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
  local mapperSettings=self.settings.mapper or {}
  local factory=self.createAutomapper or function(_,model,adapter,status,policies) return Automapper.new(model,adapter,status,policies) end
  local automapperOk,automapper,automapperErr=pcall(factory,self,MapperModel,self.map,function(kind,message) self:mapperStatus(kind,message) end,mapperSettings.transition_submaps)
  if not automapperOk then self:shutdown(); return nil,automapper end
  if not automapper then self:shutdown(); return nil,automapperErr or "automapper construction failed" end
  self.automapper=automapper
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
  local tokenFactory=function()
    local token=self.adapter.cleanupToken and self.adapter:cleanupToken()
    if token then return token end
    self.cleanup_token_counter=(self.cleanup_token_counter or 0)+1
    return ("local"..tostring(os.time())..tostring(self.cleanup_token_counter)..tostring(self):gsub("[^%w]","")):sub(-32)
  end
  self.cleanup=Cleanup.new(self.map,cleanupRuntime,clock,tokenFactory,30)
  self:installMapClickHook()
  local startupOk,startupErr=pcall(function()
  self.view=self.adapter:createView(self.settings)
  if self.view.setMapCollectionActionCallback then self.view:setMapCollectionActionCallback(function(action,item,name)
    local result,err
    if action=="use_collection" then result,err=self:switchMapCollection(item.id)
    elseif action=="share_collection" then
      local active=self.map_collections:active()
      if not active or active.id~=item.id then result,err=self:switchMapCollection(item.id); if not result then self:captureFailure("map_collection",err,{operation=action,collection=item.id}); self:presentMapCollections("Could not share map: "..tostring(err)); return nil,err end end
      return self.view.map_library_action_callback("publish_all",item)
    elseif action=="rename_collection" then result,err=self:renameMapCollection(item.id,name)
    elseif action=="duplicate_edit" then result,err=self:forkMapCollection(item.id,(name and name~="" and name) or ("Copy of "..item.name))
    elseif action=="backup_collection" then result,err=self:backupMapCollection(item.id)
    elseif action=="delete_collection" then result,err=self:deleteMapCollection(item.id)
    elseif action=="replace_collection" then return nil,"replace a map from the Shared Library tab" else return nil,"unknown map collection action" end
    if not result then self:captureFailure("map_collection",err,{operation=action,collection=item.id}); self:presentMapCollections("Could not complete action: "..tostring(err)); return nil,err end
    self:presentMapCollections(); return result
  end) end
  self:presentMapCollections()
  self.posture=PostureTracker.new(self.adapter,function() if self.started then self:refresh() end end)
  self.needs=NeedsTracker.new(self.adapter,function() if self.started then self:refresh() end end)
  self.roller=Autoroller.new(self.adapter,self.settings.roller,function(config)
    if self.adapter.saveRollerSettings then local saved,err=self.adapter:saveRollerSettings(config); if not saved then return nil,"Could not save settings: "..tostring(err) end end
    self.settings.roller=config; local root=rawget(_G,"DGHUD"); if root then root.user_settings=type(root.user_settings)=="table" and root.user_settings or {}; root.user_settings.roller=config end; return true
  end)
  if self.view.setColorToggleCallback then self.view:setColorToggleCallback(function(wanted) local enabled=self:setColorizerEnabled(type(wanted)=="boolean" and wanted or not self.colorizer_enabled); if self.adapter.reportColorizerStatus then self.adapter:reportColorizerStatus(self.colorizer:status()) end; return enabled end) end
  if self.view.setColorOptionsCallback then self.view:setColorOptionsCallback(function(name,wanted)
    if name=="mapper" then return self:setMapperEnabled(wanted) end
    local feature=name=="room_titles" and "room" or name; local enabled,err=self:setColorFeature(feature,wanted); if enabled==nil then return nil,err end; if self.adapter.reportColorizerStatus then self.adapter:reportColorizerStatus(self.colorizer:status()) end; return enabled
  end) end
  local colorSettings=type(self.settings.colorization)=="table" and self.settings.colorization or {}
  if self.view.setColorOptions then
    local initial={mapper=self:mapperEnabled(),enabled=self.colorizer_enabled,room=colorSettings.room_enabled~=false,exits=colorSettings.exits_enabled~=false,currency=colorSettings.currency_enabled~=false,races=colorSettings.races_enabled~=false,classes=colorSettings.classes_enabled~=false}
    local legacy=colorSettings.highlights_enabled~=false
    for _,name in ipairs({"portal","attack","damage","danger","recovery","upkeep","spell","discovery","illumination"}) do local value=colorSettings[name.."_enabled"]; if value==nil then initial[name]=legacy else initial[name]=value~=false end end
    self.view:setColorOptions(initial)
  elseif self.view.setColorEnabled then self.view:setColorEnabled(self.colorizer_enabled) end
  if self.view.setHelpCloseCallback then self.view:setHelpCloseCallback(function() return true end) end
  if self.view.setFeedbackCallback then self.view:setFeedbackCallback(function(payload,done) return self.adapter:submitFeedback(payload,done) end) end
  if self.view.setOptionsActionCallback then self.view:setOptionsActionCallback(function(action)
    if action=="send_debug" then return self.failure_reports:submitReport(nil,function(result,sendErr) local message=sendErr and ("Could not send report: "..tostring(sendErr)) or ("Report sent anonymously. Reference: "..tostring(result.report_id or result.number or "received")); if self.view.setSupportStatus then self.view:setSupportStatus(message) end; self:reportMapTransfer(message,sendErr~=nil) end) end
    if action=="map_settings" then local config={}; for key,value in pairs(self.settings.mapper or {}) do config[key]=value end; local current=self.automapper and self.automapper:currentRoom(); local scope=current and self.map:currentTransferScope(current); if scope then config.current_area_name=scope.area_name; config.current_subarea_name=scope.subarea_name end; return config end
    if action=="roller_settings" then local status=self.roller and {config=self.roller.cfg}; return status and status.config end
    if action=="auto_update" then
      local enabled=not (self.settings.update and self.settings.update.auto_apply==true); self.settings.update=self.settings.update or {}; self.settings.update.auto_apply=enabled
      local root=rawget(_G,"DGHUD"); if root then root.user_settings=type(root.user_settings)=="table" and root.user_settings or {}; root.user_settings.update=type(root.user_settings.update)=="table" and root.user_settings.update or {}; root.user_settings.update.auto_apply=enabled end
      if self.adapter.saveUpdateSettings then local saved,saveErr=self.adapter:saveUpdateSettings({auto_apply=enabled}); if not saved then self.settings.update.auto_apply=not enabled; if root and root.user_settings and root.user_settings.update then root.user_settings.update.auto_apply=not enabled end; return nil,"Could not save automatic update setting: "..tostring(saveErr) end end
      if self.view.setAutoUpdateEnabled then self.view:setAutoUpdateEnabled(enabled) end; return enabled
    end
    local command=({roller_start="start",roller_stop="stop",roller_stats="stats",roller_last="last",roller_reset="reset",roller_help="help"})[action]
    if not command then return nil,"unknown autoroller action" end; return self.roller:command(command)
  end) end
  if self.view.setAutoUpdateEnabled then self.view:setAutoUpdateEnabled(self.settings.update and self.settings.update.auto_apply==true) end
  if self.view.setMapLibraryActionCallback then self.view:setMapLibraryActionCallback(function(action,suppliedEntry)
    if action=="merge_current" then return self:mergeLibraryIntoCurrent(suppliedEntry or self.view:selectedMapLibraryEntry()) end
    if action=="download_new" then return self:downloadLibraryCollection(suppliedEntry or self.view:selectedMapLibraryEntry(),false) end
    if action=="update_collection" then
      local entry=suppliedEntry or self.view:selectedMapLibraryEntry(); local matching
      for _,item in ipairs(self:listMapCollections()) do if item.source and entry and item.source.kind=="library" and item.source.publisher==entry.publisher and item.source.slug==entry.slug then matching=item; break end end
      if not matching then return nil,"download this map before updating it" end; local active=self.map_collections:active(); if not active or active.id~=matching.id then local switched,switchErr=self:switchMapCollection(matching.id); if not switched then return nil,switchErr end end
      return self:downloadLibraryCollection(entry,true)
    end
    if action=="replace_current" then return self:downloadLibraryCollection(suppliedEntry or self.view:selectedMapLibraryEntry(),true) end
    if action=="upload_my_version" then local entry=suppliedEntry or self.view:selectedMapLibraryEntry(); local active=self.map_collections and self.map_collections:active(); if not active or not active.source or not entry or active.source.publisher~=entry.publisher or active.source.slug~=entry.slug then return nil,"use your editable copy of this map before uploading your version" end; action="publish_all" end
    if action=="browse" then
      if self.view.setMapLibraryImportPending then self.view:setMapLibraryImportPending(false) end
      self.view:setMapLibraryCatalog({},"Loading community map catalog…")
      local started,err=self.adapter:fetchMapCatalog(function(raw,downloadErr) if downloadErr then self:captureFailure("map_library",downloadErr,{operation="browse",stage="download"}); return self.view:setMapLibraryCatalog({},"Could not load library: "..tostring(downloadErr)) end; local catalog,validationErr=MapCatalog.validate(raw); if not catalog then self:captureFailure("map_library",validationErr,{operation="browse",stage="validation"}); return self.view:setMapLibraryCatalog({},validationErr) end; self.map_catalog=catalog; self.view:setMapLibraryCatalog(catalog.maps) end); if not started then self:captureFailure("map_library",err,{operation="browse",stage="start"}); self.view:setMapLibraryCatalog({},"Could not load library: "..tostring(err)) end; return started,err
    elseif action:match("^export_") then
      local scope=action:gsub("^export_",""); local selection,selectionErr=self:currentMapSelection(scope); if not selection then self.view.map_library_status="Backup failed: "..tostring(selectionErr); return nil,selectionErr end
      local stamp=(self.adapter.timestamp and self.adapter:timestamp() or tostring(os.time())):gsub("[^%w]+","-"):gsub("^%-+",""):gsub("%-+$","")
      local path,err=self:exportMapTransfer("dghud-"..scope.."-"..stamp,"local-export",selection)
      if path then self.adapter:openMapTransferFolder() end
      return path,err
    elseif action=="install" then
      local entry=self.view:selectedMapLibraryEntry(); if not entry then self.view:setMapLibraryCatalog(self.map_catalog and self.map_catalog.maps or {},"Select a map first."); return nil,"select a map first" end
      self.view.map_library_status="Downloading and verifying "..entry.name.."…"; if self.view.layout then self.view:layoutMapLibrary(self.view.layout) end
      local function failed(message) self.last_mapper_error=tostring(message); self.last_map_library_error=tostring(message); self:captureFailure("map_library",message,{operation="install",stage="download_or_validation",map_scope=entry.scope,catalog_schema=self.map_catalog and self.map_catalog.schema}); self.view.map_library_status="Map failed: "..tostring(message).." A sanitized report is ready. Choose REPORT A PROBLEM to send it anonymously; no GitHub account is needed."; if self.view.layout then self.view:layoutMapLibrary(self.view.layout) end end
      local started,err=self.adapter:downloadCatalogMap(entry,function(raw,downloadErr) if downloadErr then return failed(downloadErr) end; local model,validationErr=self.map_transfer:validate(raw); if not model then return failed(validationErr) end; if model.provenance.publisher~=entry.publisher or model.provenance.slug~=entry.slug then return failed("map provenance does not match the catalog") end; local path,saveErr=self.adapter:saveMapTransfer(entry.slug,raw); if not path then return failed(saveErr) end; local plan,previewErr=self:previewMapTransfer(entry.slug); if not plan then return failed(previewErr) end end); if not started then failed(err) end; return started,err
    elseif action=="keep" then return self:setDefaultMapImportPolicy("keep")
    elseif action=="replace" then return self:setDefaultMapImportPolicy("replace")
    elseif action=="skip" then return self:setDefaultMapImportPolicy("skip")
    elseif action=="confirm" then return self:confirmMapTransfer()
    elseif action=="cancel" then self.pending_map_import=nil; if self.view.setMapLibraryImportPending then self.view:setMapLibraryImportPending(false) end; self.view.map_library_status="Stopped. Your map was not changed."; if self.view.layout then self.view:layoutMapLibrary(self.view.layout) end; return true
    elseif action=="report" then
      if not self.failure_reports:lastReport() then self:captureFailure("map_library",self.last_map_library_error or "manual problem report",{operation="map_library",stage="manual"}) end
      self.view.map_library_status="Sending privacy-safe diagnostic…"
      return self.failure_reports:submitReport(nil,function(result,sendErr) self.view.map_library_status=sendErr and ("Could not send report: "..tostring(sendErr)) or ("Report sent. Reference: "..tostring(result.report_id or result.number or "received")); if self.view.layout then self.view:layoutMapLibrary(self.view.layout) end end)
    elseif action:match("^publish_") then
      local scope=action:gsub("^publish_",""); local selection,selectionErr=self:currentMapSelection(scope); if not selection then self.view.map_library_status="Share failed: "..tostring(selectionErr); return nil,selectionErr end
      local stamp=os.date("%Y%m%d-%H%M%S"); local author=self:mapTransferCreator(); local publisher=author:lower():gsub("[^%w]+","-"):gsub("^%-+",""):gsub("%-+$",""):sub(1,39); if publisher=="" then publisher="anonymous" end
      local friendly=selection.subarea_name or selection.area_name or scope; local slug=(friendly.."-"..stamp):lower():gsub("[^%w]+","-"):gsub("^%-+",""):gsub("%-+$",""):sub(1,64); local data,buildErr=self.map_transfer:exportData({artifact_id="submission:"..stamp..":"..slug,author=author,publisher=publisher,slug=slug},selection)
      if not data then self:captureFailure("map_library",buildErr,{operation="publish",stage="build",map_scope=scope}); self.view.map_library_status="Publish failed: "..tostring(buildErr); self:reportMapTransfer(buildErr,true); return nil,buildErr end
      self.view.map_library_status="Uploading and validating "..#data.rooms.." rooms…"; if self.view.layout then self.view:layoutMapLibrary(self.view.layout) end
      local function completed(result,publishErr)
        if publishErr then self.last_map_library_error=tostring(publishErr); self:captureFailure("map_library",publishErr,{operation="publish",stage="upload",map_scope=scope,room_count=#data.rooms}); self.view.map_library_status="Publish failed: "..tostring(publishErr); self:reportMapTransfer(publishErr,true)
        else self.view.map_library_status="Submitted for owner review. Submission "..tostring(result.submission_id or "received").."."; self:reportMapTransfer("Map submitted for owner review. It will appear in the library after validation and approval.",false) end
        if self.view.layout then self.view:layoutMapLibrary(self.view.layout) end
      end
      local started,publishErr=self.adapter:publishMap({publisher=publisher,slug=slug,map=data},completed); if not started then completed(nil,publishErr) end; return started,publishErr
    end
    return nil,"unknown map library action"
  end) end
  if self.view.setRollerSettingsCallback then self.view:setRollerSettingsCallback(function(values) local ok,err=self.roller:configure(values); if not ok then return nil,err end; return true,nil,self.roller.cfg end) end
  if self.view.setMapZoomCallback then self.view:setMapZoomCallback(function(action) return self:mapToolbarAction(action) end) end
  if self.view.setMapClearAllCallback then self.view:setMapClearAllCallback(function() if self.view.showMapSettings then return self.view:showMapSettings(self.settings.mapper) end; return self:clearAllMapsAction() end) end
  if self.view.setMapSettingsCallback then self.view:setMapSettingsCallback(function(values) return self:configureMapper(values) end) end
  if self.view.setMapSettingsActionCallback then self.view:setMapSettingsActionCallback(function(action,value)
    if action=="map_library" then self:presentMapCollections(); return self.view:showMapLibrary() end
    if action=="clear_all" then return self:clearAllMapsAction() end
    if action=="clear_current" then local current=self.automapper and self.automapper:currentRoom(); return self:previewCleanup("previewCurrent",current) end
    if action=="rename_area" or action=="rename_subarea" then
      local kind=action=="rename_area" and "area" or "subarea"
      local current=self.automapper and self.automapper:currentRoom(); if not current then return nil,"current room is unavailable" end
      local scope,scopeErr=self.map:currentTransferScope(current); if not scope then return nil,scopeErr end
      local key=kind=="area" and scope.area or scope.partition
      local previous=self.map:mapLabel(kind,key) or ""
      local saved,saveErr=self.map:setMapLabel(kind,key,value); if not saved then return nil,saveErr end
      local native,nativeErr=self.map:renameNativePartition(scope.partition)
      if not native then
        local restored,restoreErr=self.map:restoreMapLabel(kind,key,previous)
        if not restored then return nil,tostring(nativeErr).."; label rollback failed: "..tostring(restoreErr) end
        return nil,nativeErr
      end
      self.view.map_settings_error=nil; self.view.map_settings_status_text="Saved map name: "..native; return saved,native
    end
  end) end
  if self.view.setCopyTextCallback then self.view:setCopyTextCallback(function(text) return self.adapter:copyText(text) end) end
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
  self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias("^dghud map debug$",function() return self:submitMapDiagnostic() end)
  self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias("^dghud map debug folder$",function() return self:exportMapDiagnostic(true) end)
  self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias("^dghud map(?:per)?(?: (on|off|toggle|status))?$",function(value)
    local action=tostring(aliasArgument(value) or "toggle"):lower()
    if action=="status" then return self:mapperEnabled() end
    if action=="on" then return self:setMapperEnabled(true) end
    if action=="off" then return self:setMapperEnabled(false) end
    if action=="toggle" then return self:setMapperEnabled(not self:mapperEnabled()) end
    return nil,"usage: dghud map [on|off|toggle|status]"
  end)
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
  local transferAliases={
    {"^dghud map library$",function() self.view:showMapLibrary(); self.view:setMapLibraryMode("library"); return self.view.map_library_actions.browse.click() end},
    {"^dghud map folder$",function() local path=self.adapter:openMapTransferFolder(); self:reportMapTransfer("Map folder: "..tostring(path),false); return path end},
    {"^dghud map export ([\\w_-]+) ([\\w-]+)$",function(value) local first,second;if type(value)=="table" then first,second=value[2],value[3] elseif type(_G.matches)=="table" then first,second=_G.matches[2],_G.matches[3] end; return self:exportMapTransfer(first,second) end},
    {"^dghud map import ([\\w_-]+)$",function(value) return self:previewMapTransfer(aliasArgument(value)) end},
    {"^dghud map import area (.+) (keep|replace|skip)$",function(value) local area,choice;if type(value)=="table" then area,choice=value[2],value[3] elseif type(_G.matches)=="table" then area,choice=_G.matches[2],_G.matches[3] end; return self:setMapImportPolicy("area",area,choice) end},
    {"^dghud map import room (\\d+) (keep|replace|skip)$",function(value) local room,choice;if type(value)=="table" then room,choice=value[2],value[3] elseif type(_G.matches)=="table" then room,choice=_G.matches[2],_G.matches[3] end; return self:setMapImportPolicy("room",room,choice) end},
    {"^dghud map import confirm$",function() return self:confirmMapTransfer() end},
    {"^dghud map import cancel$",function() self.pending_map_import=nil; self:reportMapTransfer("Import preview cancelled.",false); return true end},
  }
  for _,entry in ipairs(transferAliases) do self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias(entry[1],entry[2]) end
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
    else return nil,"usage: dghud colors [on|off|toggle|status|room|exits|currency|races|classes|highlights|portal|attack|damage|danger|recovery|upkeep|spell|discovery|illumination]" end
    if enabled==nil then return nil,err end
    if self.adapter.reportColorizerStatus then self.adapter:reportColorizerStatus(self.colorizer:status()) end; return enabled
  end)
  self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias("^dghud help$",function()
    if not self.view or not self.view.showHelp then return nil,"help panel is unavailable" end
    return self.view:showHelp()
  end)
  self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias("^rr(?:\\s+(.*))?$",function(value) return self.roller:command(aliasArgument(value) or "help") end)
  self.runtime_registration_complete=true; self.started=true; local data=self.adapter:getGMCP(); if self:mapperEnabled() and data and data.Room and data.Room.Info then local mapped=self.automapper:onRoom(data.Room.Info); if mapped and tonumber(data.Room.Info.num) then self.managed_rooms[tonumber(data.Room.Info.num)]=true end end; self:refresh(); self:scheduleRoundtimeTick(); self:scheduleClockTick()
  local chatStarted,chatErr=self:startChat(); if not chatStarted then error(chatErr,0) end
  self.runtime.triggers[#self.runtime.triggers+1]=self.adapter:addLineTrigger(function(line) self:callSpecialTransition("onLine",line) end)
  self.runtime.triggers[#self.runtime.triggers+1]=self.adapter:addLineTrigger(function(line) self.posture:onLine(line); self.needs:onLine(line,"output"); self.roller:onLine(line) end)
  end)
  if not startupOk then pcall(function() self:shutdown() end); return nil,startupErr end
  return true
end
function Main:shutdown()
  if self.started and self.map_collections and not self.map_collection_unsafe then local ok,err=self:saveActiveMapCollection(); if not ok then self:captureFailure("map_collection",err,{operation="shutdown_save"}) end end
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
  if self.automapper then self.automapper:shutdown(); self.automapper=nil end; self.map=nil; self.map_collections=nil
  for _,id in ipairs(self.runtime.events) do self.adapter:killEvent(id) end; for _,id in ipairs(self.runtime.aliases) do self.adapter:killAlias(id) end; for _,id in ipairs(self.runtime.triggers or {}) do self.adapter:killTrigger(id) end
  self.runtime={events={},aliases={},triggers={}}; if self.view then self.view:delete(); self.view=nil end
  if self.original_borders then self.adapter:setBorders(self.original_borders[1],self.original_borders[2],self.original_borders[3],self.original_borders[4]); self.original_borders=nil end
  self.character_entry_started=false; self.character_entry_name=nil; self.runtime_registration_complete=false; self.started=false; return true
end
function Main:reload() self:shutdown(); return self:start() end
function Main:healthCheck()
  local chatEnabled=not (self.settings.chat and self.settings.chat.enabled==false)
  local function validRegistrations(items) if type(items)~="table" or #items<1 then return false end; for _,id in ipairs(items) do if id==nil or id==false then return false end end; return true end
  if not self.started or not self.runtime_registration_complete or not self.view or not self.collector or not self.collector.started or not self.colorizer or not self.colorizer.started or not self.colorizer.trigger or not self.roller or not self.automapper or not self.special_transition or not self.map_transfer or (chatEnabled and (not self.chat or not self.chat.started or not self.chat.trigger)) or not validRegistrations(self.runtime.events) or not validRegistrations(self.runtime.aliases) or not validRegistrations(self.runtime.triggers) then return nil,"HUD is not healthy" end
  local ok=pcall(function() self:refresh() end); if not ok then return nil,"state refresh failed" end; return true
end
return Main
