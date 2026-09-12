local previous=rawget(_G,"DGHUD")
local userSettings=previous and previous.user_settings
local updateReinstallPending=previous and previous._update_reinstall_pending
local viewHandoff=previous and previous._view_handoff
local function copyChatEntries(entries)
  local source=type(entries)=="table" and entries or {}; local result={}; local first=math.max(1,#source-999)
  for index=first,#source do
    local entry=source[index]
    if type(entry)=="table" then
      local copy={}
      for key,value in pairs(entry) do local kind=type(value); if type(key)=="string" and (kind=="string" or kind=="number" or kind=="boolean") then copy[key]=value end end
      result[#result+1]=copy
    end
  end
  return result
end
local function captureChatHandoff(hud)
  if type(hud)~="table" then return nil end
  local controller=type(hud.controller)=="table" and hud.controller or nil
  local active=controller and type(controller.chat)=="table" and controller.chat or nil
  local handoff
  if active and type(active.handoff)=="function" then local ok,value=pcall(active.handoff,active); if ok and type(value)=="table" then handoff=value end end
  if not handoff and active and type(active.history)=="table" and type(active.history.entries)=="function" then
    local ok,entries=pcall(active.history.entries,active.history,"ALL")
    if ok then handoff={schema=1,character_key=active.currentCharacterKey,filter=active.filter,entries=entries,last_key=active.history.lastKey,last_epoch=active.history.lastEpoch} end
  end
  if not handoff and type(hud._chat_handoff)=="table" then handoff=hud._chat_handoff end
  if not handoff and controller and controller.view and type(controller.view.chat_entries)=="table" then handoff={schema=1,character_key="unknown",filter=controller.view.chat_active_filter,entries=controller.view.chat_entries} end
  if type(handoff)~="table" then return nil end
  return {schema=1,character_key=handoff.character_key,filter=handoff.filter,entries=copyChatEntries(handoff.entries),last_key=handoff.last_key,last_epoch=handoff.last_epoch}
end
local chatHandoff=captureChatHandoff(previous)
if updateReinstallPending and previous and type(previous.controller)=="table" then
  -- The replacement package owns this handoff. Detaching the retiring
  -- collection manager also gives pre-0.3.8 HUDs the fast path: their shutdown
  -- cannot serialize the map, while Mudlet's native map remains untouched.
  previous.controller.update_handoff=true
  previous.controller.map_collections=nil
end
if previous and previous.shutdown then pcall(previous.shutdown) end
local chat=previous and type(previous.chat)=="table" and previous.chat or {}
chat.capture=function() return nil,"chatbox is not running" end
chat.setFilter=function() return nil,"chatbox is not running" end
chat.status=function() return nil,"HUD is not running" end
DGHUD = {user_settings=userSettings,chat=chat,_update_reinstall_pending=updateReinstallPending,_view_handoff=viewHandoff,_chat_handoff=chatHandoff}
local moduleNames={"defaults","command_parser","command_collector","chat_parser","chat_history","chat_storage","chat_controller","output_colorizer","posture_tracker","needs_tracker","autoroller","game_clock","navigation","mapper_model","map_adapter","map_transfer","map_catalog","map_collections","map_cleanup","map_diagnostics","failure_report","automapper","special_transition","map_walker","state","settings","sha256","release","events","layout","view","mudlet_adapter","main","updater"}
for _,name in ipairs(moduleNames) do package.loaded[name]=nil end
local defaults=require("defaults")
local Settings=require("settings")
local Adapter=require("mudlet_adapter")
local Main=require("main")
local Updater=require("updater")
local Storage=require("chat_storage")
if Adapter.prepareDataDirectory then
  local called,prepared,prepareMessage=pcall(Adapter.prepareDataDirectory)
  if not called or not prepared or prepareMessage then pcall(cecho,"\n<yellow>[DGHUD]<reset> Persistent data preparation warning: "..tostring((not called and prepared) or prepareMessage or "filesystem is unavailable").."\n") end
end
if type(userSettings)~="table" then userSettings={} end
if userSettings.update==nil then local persisted=Adapter.loadUpdateSettings and Adapter.loadUpdateSettings(); if type(persisted)=="table" then userSettings.update=persisted end end
do local persisted=Adapter.loadRollerSettings and Adapter.loadRollerSettings(); if type(persisted)=="table" then userSettings.roller=persisted end end
local persistedMapper=Adapter.loadMapperSettings and Adapter.loadMapperSettings()
if type(persistedMapper)=="table" then userSettings.mapper=type(userSettings.mapper)=="table" and userSettings.mapper or {}; for key,value in pairs(persistedMapper) do if userSettings.mapper[key]==nil then userSettings.mapper[key]=value end end end
DGHUD.user_settings=userSettings
local function applyUserSettings()
  local ok,resolvedSettings,migratedSettings=pcall(Settings.resolve,defaults,DGHUD.user_settings or {})
  if not ok then return nil,resolvedSettings end
  DGHUD.user_settings=migratedSettings
  DGHUD.settings=resolvedSettings
  if DGHUD.controller then DGHUD.controller.settings=resolvedSettings end
  if DGHUD.updater then DGHUD.updater.settings=resolvedSettings end
  return true
end
local applied,applyErr=applyUserSettings()
if not applied then error(applyErr) end
DGHUD.chatStorageApi=Storage.mudletApi(getMudletHomeDir(),"DGHUDData")
DGHUD.controller=Main.new(Adapter.new(),DGHUD.settings,viewHandoff,chatHandoff)
DGHUD.updater=Updater.new(DGHUD.controller.adapter,DGHUD.settings)
DGHUD.controller.updater=DGHUD.updater
Main.installChatApi(DGHUD)
function DGHUD.start() return DGHUD.controller:start() end
function DGHUD.shutdown() return DGHUD.controller:shutdown() end
function DGHUD.reload()
  local applied,err=applyUserSettings()
  if not applied then return nil,err end
  return DGHUD.controller:reload()
end
function DGHUD.healthCheck()
  return DGHUD.controller:healthCheck()
end
local started,startErr=DGHUD.start()
if not started then error("DGHUD startup failed: "..tostring(startErr or "unknown error"),0) end
DGHUD._view_handoff=nil
DGHUD._chat_handoff=nil
local installedController=DGHUD.controller
local function maintainRecoveryCompanion()
  local hud=rawget(_G,"DGHUD")
  if type(hud)~="table" or hud.controller~=installedController then return end
  local adapter=hud.controller and hud.controller.adapter
  if adapter and adapter.ensureRecoveryPackage then pcall(adapter.ensureRecoveryPackage,adapter) end
end
-- Recovery maintenance is independent of HUD readiness. Let package import and
-- Mudlet's mandatory profile save finish before doing any companion I/O.
if type(rawget(_G,"tempTimer"))=="function" then tempTimer(0,maintainRecoveryCompanion) else maintainRecoveryCompanion() end
