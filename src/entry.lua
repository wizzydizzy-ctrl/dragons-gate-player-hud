local previous=rawget(_G,"DGHUD")
local userSettings=previous and previous.user_settings
local updateReinstallPending=previous and previous._update_reinstall_pending
if previous and previous.shutdown then pcall(previous.shutdown) end
local chat=previous and type(previous.chat)=="table" and previous.chat or {}
chat.capture=function() return nil,"chatbox is not running" end
chat.setFilter=function() return nil,"chatbox is not running" end
chat.status=function() return nil,"HUD is not running" end
DGHUD = {user_settings=userSettings,chat=chat,_update_reinstall_pending=updateReinstallPending}
local installGraceStarted=(type(getEpoch)=="function" and tonumber(getEpoch())) or os.time()
local moduleNames={"defaults","command_parser","command_collector","chat_parser","chat_history","chat_storage","chat_controller","output_colorizer","posture_tracker","needs_tracker","autoroller","game_clock","navigation","mapper_model","map_adapter","map_transfer","map_catalog","map_collections","map_cleanup","map_diagnostics","failure_report","automapper","special_transition","map_walker","state","settings","sha256","release","events","layout","view","mudlet_adapter","main","updater"}
for _,name in ipairs(moduleNames) do package.loaded[name]=nil end
local defaults=require("defaults")
local Settings=require("settings")
local Adapter=require("mudlet_adapter")
local Main=require("main")
local Updater=require("updater")
local Storage=require("chat_storage")
if type(userSettings)~="table" then userSettings={} end
if userSettings.update==nil then local persisted=Adapter.loadUpdateSettings and Adapter.loadUpdateSettings(); if type(persisted)=="table" then userSettings.update=persisted end end
if userSettings.roller==nil then local persisted=Adapter.loadRollerSettings and Adapter.loadRollerSettings(); if type(persisted)=="table" then userSettings.roller=persisted end end
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
DGHUD.chatStorageApi=Storage.mudletApi()
DGHUD.controller=Main.new(Adapter.new(),DGHUD.settings)
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
  -- Older HUD updaters probe only 0.5 seconds after installPackage(), while
  -- Mudlet may still be registering this package. Let that verified migration
  -- cross the short registration window; all later checks remain strict.
  local now=(type(getEpoch)=="function" and tonumber(getEpoch())) or os.time()
  if DGHUD._update_reinstall_pending==true and now-installGraceStarted<3 then return true end
  return DGHUD.controller:healthCheck()
end
DGHUD.start()
if DGHUD.controller and DGHUD.controller.adapter and DGHUD.controller.adapter.ensureRecoveryPackage then pcall(DGHUD.controller.adapter.ensureRecoveryPackage,DGHUD.controller.adapter) end
