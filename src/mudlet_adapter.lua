local View=require("view"); local Storage=require("chat_storage"); local MapAdapter=require("map_adapter"); local SHA256=require("sha256")
local Adapter={}; Adapter.__index=Adapter
function Adapter.updateBase(home) return home.."/DGHUDUpdater" end
function Adapter.updateArchivePath(home) return Adapter.updateBase(home).."/staging/DragonsGateHUD.mpackage" end
function Adapter.verifyArchive(payload,digest) return type(payload)=="string" and type(digest)=="string" and SHA256.hex(payload)==digest end
function Adapter.manifestUrl(github,nonce)
  return "https://github.com/"..github.owner.."/"..github.repository.."/releases/latest/download/manifest.json?dghud="..tostring(nonce)
end
function Adapter.versionManifestUrl(github,version,nonce)
  return "https://github.com/"..github.owner.."/"..github.repository.."/releases/download/v"..tostring(version).."/manifest.json?dghud="..tostring(nonce)
end
local updateNonce=0
function Adapter.new() return setmetatable({},Adapter) end
function Adapter:getBorders() return getBorderLeft(),getBorderTop(),getBorderRight(),getBorderBottom() end
function Adapter:getWindowSize() return getMainWindowSize() end
function Adapter:setBorders(l,t,r,b) setBorderLeft(l);setBorderTop(t);setBorderRight(r);setBorderBottom(b) end
function Adapter:suppressDefaultMapInfo(api)
  api=api or _G
  if type(api.disableMapInfo)~="function" then return true end
  local ok,err=pcall(function()
    api.disableMapInfo("Short")
    api.disableMapInfo("Full")
    if type(api.updateMap)=="function" then api.updateMap() end
  end)
  if not ok then return nil,tostring(err) end
  return true
end
function Adapter:centerMap(roomID)
  local ok,err=pcall(function() centerview(roomID); updateMap() end)
  if not ok then return nil,tostring(err) end
  return true
end
function Adapter:createView(settings)
  local view=View.new(settings)
  if view.setMapCenterCallback then view:setMapCenterCallback(function(roomID) return self:centerMap(roomID) end) end
  return view
end
function Adapter:createMapAdapter(api)
  local map=MapAdapter.new(api or MapAdapter.mudletApi(_G))
  function map:setCurrent(roomID)
    if not self:isOwned(roomID) then return nil,"room "..tostring(roomID).." is not owned by DragonsGateHUD" end
    return self:center(roomID)
  end
  return map
end
function Adapter:createChatStorage(visibleLimit) return Storage.new(Storage.mudletApi(),getMudletHomeDir().."/DragonsGateHUD/chat",visibleLimit) end
function Adapter:addEvent(name,fn) return registerAnonymousEventHandler(name,fn) end
function Adapter:killEvent(id) return killAnonymousEventHandler(id) end
function Adapter:addAlias(pattern,fn) return tempAlias(pattern,fn) end
function Adapter:killAlias(id) return killAlias(id) end
function Adapter:addLineTrigger(fn) return tempRegexTrigger("^.*$",function() fn(line or "") end) end
function Adapter:addColorizerTrigger(fn)
  -- Keep recognition in output_colorizer.lua. A broad owned trigger prevents
  -- new independently configurable categories from being silently excluded
  -- by an older registration prefilter.
  return tempRegexTrigger("^.*$",function()
    fn(line or (type(getCurrentLine)=="function" and getCurrentLine() or ""))
  end)
end
function Adapter:applyLineColors(segments,api)
  api=api or _G
  if type(segments)~="table" or type(api.selectSection)~="function" or type(api.setFgColor)~="function" then return nil,"Mudlet line-color API is unavailable" end
  local ok,err=pcall(function()
    for _,item in ipairs(segments) do
      local color=item.color
      assert(type(item.start)=="number" and type(item.length)=="number" and type(color)=="table","invalid color segment")
      api.selectSection(item.start-1,item.length)
      api.setFgColor(color[1],color[2],color[3])
    end
    if type(api.deselect)=="function" then api.deselect() end
  end)
  if not ok then if type(api.deselect)=="function" then pcall(api.deselect) end; return nil,tostring(err) end
  return true
end
function Adapter:killTrigger(id) return killTrigger(id) end
function Adapter:epoch() return os.time() end
function Adapter:localTime() return os.date("%I:%M:%S %p"):gsub("^0","") end
function Adapter:startClockTimer(fn) return tempTimer(1,fn,true) end
function Adapter:stopClockTimer(id) return killTimer(id) end
function Adapter:cleanupClock() return os.time() end
function Adapter:cleanupToken(source)
  source=source or io
  if type(source)~="table" or type(source.open)~="function" then return nil,"secure random source is unavailable" end
  local openOK,file=pcall(source.open,"/dev/urandom","rb")
  if not openOK or not file then return nil,"secure random source is unavailable" end
  local readOK,bytes=pcall(file.read,file,16)
  if type(file.close)=="function" then pcall(file.close,file) end
  if not readOK then return nil,"secure random source read failed" end
  if type(bytes)~="string" or #bytes~=16 then return nil,"secure random source returned incomplete data" end
  return SHA256.hex(bytes):sub(1,16)
end
function Adapter:refreshMap(api)
  api=api or _G
  if type(api.updateMap)~="function" then return nil,"Mudlet mapper API updateMap is unavailable" end
  local ok,err=pcall(api.updateMap)
  if not ok then return nil,tostring(err) end
  return true
end
function Adapter:reportMapCleanup(message,isError)
  local color=isError and "red" or "gold"
  local ok,err=pcall(cecho,"\n<"..color..">[DGHUD Map]<reset> "..tostring(message).."\n")
  if not ok then return nil,tostring(err) end
  return true
end
local function mapToken(value,kind)
  value=tostring(value or ""):lower():gsub("%s+","-")
  if not value:match("^[a-z0-9][a-z0-9_%-]*$") or #value>64 then return nil,(kind or "map name").." must use 1-64 letters, numbers, dashes, or underscores" end
  return value
end
function Adapter:mapTransferDirectory()
  local base=getMudletHomeDir().."/DragonsGateHUD"; lfs.mkdir(base); local directory=base.."/maps"; lfs.mkdir(directory); return directory
end
function Adapter:saveMapTransfer(name,data)
  local slug,err=mapToken(name,"map name"); if not slug then return nil,err end
  local ok,payload=pcall(yajl.to_string,data); if not ok or type(payload)~="string" then return nil,"could not encode map JSON" end
  local destination=self:mapTransferDirectory().."/"..slug..".json"; local temporary=destination..".tmp"
  local file,openErr=io.open(temporary,"wb"); if not file then return nil,openErr end
  local wrote,writeErr=file:write(payload.."\n"); if not wrote then file:close(); os.remove(temporary); return nil,writeErr end
  local closed,closeErr=file:close(); if closed==nil then os.remove(temporary); return nil,closeErr end
  local moved,moveErr=os.rename(temporary,destination); if not moved then os.remove(temporary); return nil,moveErr end
  return destination,slug
end
function Adapter:loadMapTransfer(name)
  local slug,err=mapToken(name,"map name"); if not slug then return nil,err end
  local path=self:mapTransferDirectory().."/"..slug..".json"; local file,openErr=io.open(path,"rb"); if not file then return nil,openErr or "map file was not found" end
  local payload=file:read("*a"); file:close(); if type(payload)~="string" or #payload>20000000 then return nil,"map file exceeds the 20 MB safety limit" end
  local ok,data=pcall(yajl.to_value,payload); if not ok then return nil,"map JSON is invalid" end; return data,path,slug
end
function Adapter:openMapTransferFolder() local directory=self:mapTransferDirectory(); if type(openUrl)=="function" then openUrl("file://"..directory) end; return directory end
function Adapter:openMapLibrary(page)
  local base="https://github.com/wizzydizzy-ctrl/dragons-gate-map-library"; local url=page=="publish" and (base.."/compare") or base
  if type(openUrl)~="function" then return nil,"Mudlet browser integration is unavailable" end; openUrl(url); return url
end
function Adapter:reportMapTransfer(message,isError)
  local color=isError and "red" or "gold"; cecho("\n<"..color..">[DGHUD Maps]<reset> "..tostring(message).."\n"); return true
end
function Adapter:timestamp() return os.date("%Y-%m-%dT%H:%M:%S%z") end
function Adapter:reportChatErrorOnce(message) cecho("\n<red>[DGHUD Chat]<reset> "..tostring(message).."\n") end
function Adapter:reportChatStatus(status)
  status=type(status)=="table" and status or {}
  local storage=status.storage_key or "unknown"; local error=status.last_storage_error or "none"
  cecho("\n<gold>[DGHUD Chat]<reset> filter="..tostring(status.active_filter or "OFF").." visible="..tostring(status.visible_count or 0).." storage="..tostring(storage).." last storage error="..tostring(error).."\n")
  return status
end
function Adapter:reportColorizerStatus(status)
  if type(status)~="table" then status={enabled=status==true} end
  local function word(value) return value and "ON" or "OFF" end
  cecho("\n<gold>[DGHUD Options]<reset> All "..word(status.enabled).."  Room "..word(status.room).."  Exits "..word(status.exits).."  Currency "..word(status.currency).."  Races "..word(status.races).."  Classes "..word(status.classes).."  Travel "..word(status.portal).."  Attacks "..word(status.attack).."  Damage "..word(status.damage).."  Danger "..word(status.danger).."  Recovery "..word(status.recovery).."  Costs "..word(status.upkeep).."  Spells "..word(status.spell).."  Discovery "..word(status.discovery).."  Illumination "..word(status.illumination).."\n")
  return true
end
function Adapter:reportRoller(message) cecho("\n<gold>[DGHUD Roller]<reset> "..tostring(message or "").."\n"); return true end
function Adapter:standaloneRollerPresent() return type(rawget(_G,"OGDGROLLER"))=="table" end
function Adapter:startRollerLog(config)
  local function component(value,fallback) value=tostring(value or ""):gsub("[^%w%._%-]","_"); if value=="" or value=="." or value==".." then return fallback end; return value end
  local base=getMudletHomeDir().."/DragonsGateHUD"; lfs.mkdir(base)
  local folder=base.."/"..component(config.log_folder,"og_dg_roller"); lfs.mkdir(folder)
  local stamp=os.date("%Y-%m-%d_%H-%M-%S")
  local log={session=folder.."/session_"..stamp..".txt",master=folder.."/"..component(config.master_file,"og_dg_rolls_master.txt")}
  log.session_handle=io.open(log.session,"ab"); log.master_handle=io.open(log.master,"ab")
  if not log.session_handle or not log.master_handle then if log.session_handle then log.session_handle:close() end; if log.master_handle then log.master_handle:close() end; return nil,"could not open roller logs" end
  return log
end
function Adapter:appendRollerLog(log,message)
  local line=os.date("%Y-%m-%d %H:%M:%S ")..tostring(message or "").."\n"
  local a,ae=log.session_handle:write(line); if not a then return nil,ae end; local b,be=log.session_handle:flush(); if not b then return nil,be end
  local c,ce=log.master_handle:write(line); if not c then return nil,ce end; local d,de=log.master_handle:flush(); if not d then return nil,de end
  return true
end
function Adapter:closeRollerLog(log) if log.session_handle then log.session_handle:close(); log.session_handle=nil end; if log.master_handle then log.master_handle:close(); log.master_handle=nil end; return true end
local function rollerSettingsPath() return getMudletHomeDir().."/DragonsGateHUD/roller-settings.lua" end
function Adapter:saveRollerSettings(config)
  local base=getMudletHomeDir().."/DragonsGateHUD"; lfs.mkdir(base); local temp=rollerSettingsPath()..".tmp"
  local fields={"target_total","hard_stop","max_rolls","reroll_delay","reroll_command","auto_start_on_name","use_min_stats","require_min_stats_to_stop","show_every_roll","logging_enabled","log_folder","master_file"}
  local function literal(value) if type(value)=="string" then return string.format("%q",value) elseif value==nil then return "nil" else return tostring(value) end end
  local lines={"return {"}; for _,key in ipairs(fields) do lines[#lines+1]="  "..key.."="..literal(config[key]).."," end; lines[#lines+1]="  min_stats={"
  for _,key in ipairs({"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"}) do lines[#lines+1]="    "..key.."="..literal((config.min_stats or {})[key]).."," end; lines[#lines+1]="  },"; lines[#lines+1]="}"
  local file,err=io.open(temp,"wb"); if not file then return nil,err end; local wrote,writeErr=file:write(table.concat(lines,"\n")); if not wrote then file:close(); os.remove(temp); return nil,writeErr end; local closed,closeErr=file:close(); if closed==nil then os.remove(temp); return nil,closeErr end
  local destination=rollerSettingsPath(); local backup=destination..".bak"; os.remove(backup)
  local existing=io.open(destination,"rb"); if existing then existing:close(); local moved,moveErr=os.rename(destination,backup); if not moved then os.remove(temp); return nil,moveErr end end
  local ok,renameErr=os.rename(temp,destination); if not ok then os.rename(backup,destination); return nil,renameErr end; os.remove(backup); return true
end
function Adapter.loadRollerSettings()
  local loader=loadfile(rollerSettingsPath()); if not loader then return nil end; local ok,value=pcall(loader); if ok and type(value)=="table" then return value end; return nil
end
local function mapperSettingsPath() return getMudletHomeDir().."/DragonsGateHUD/mapper-settings.lua" end
function Adapter:saveMapperSettings(config)
  local base=getMudletHomeDir().."/DragonsGateHUD"; lfs.mkdir(base); local destination=mapperSettingsPath(); local temp=destination..".tmp"
  local file,err=io.open(temp,"wb"); if not file then return nil,err end
  local wrote,writeErr=file:write("return { enabled="..tostring(not (config and config.enabled==false)).." }\n"); if not wrote then file:close(); os.remove(temp); return nil,writeErr end
  local closed,closeErr=file:close(); if closed==nil then os.remove(temp); return nil,closeErr end
  local ok,renameErr=os.rename(temp,destination); if not ok then os.remove(temp); return nil,renameErr end; return true
end
function Adapter.loadMapperSettings()
  local loader=loadfile(mapperSettingsPath()); if not loader then return nil end; local ok,value=pcall(loader); if ok and type(value)=="table" and type(value.enabled)=="boolean" then return {enabled=value.enabled} end; return nil
end
function Adapter:schedule(seconds,fn) return tempTimer(seconds,fn) end
function Adapter:cancelTimer(id) return killTimer(id) end
function Adapter:sendCommand(command) return send(command) end
function Adapter:getGMCP() return gmcp or {} end
function Adapter:getPostureVariables()
  return {standing=rawget(_G,"standing"),sitting=rawget(_G,"sitting"),unconscious=rawget(_G,"unconscious")}
end
function Adapter:setPostureVariables(state)
  state=type(state)=="table" and state or {}; rawset(_G,"standing",state.standing); rawset(_G,"sitting",state.sitting); rawset(_G,"unconscious",state.unconscious); return true
end
function Adapter.characterPrompt(value)
  local line=tostring(value or ""):gsub("\27%[[%d;]*m",""):gsub("%s+$","")
  return line:match("^>")~=nil or line:match("^%[%d+%]%s+%d+/%d+%s+hp,%s+%d+/%d+%s+ftg%s*>")~=nil
end
function Adapter:isCharacterActive()
  if Adapter.characterPrompt(getCurrentLine and getCurrentLine() or "") then return true end
  local status=gmcp and gmcp.Char and gmcp.Char.Status
  if type(status)=="table" and type(status.name)=="string" and status.name~="" then return true end
  local controller=DGHUD and DGHUD.controller
  return controller and controller.character_entry_started==true or false
end
function Adapter:mudletVersion()
  if type(getMudletVersion)~="function" then return nil end
  local ok,major,minor,revision=pcall(getMudletVersion,"table"); if not ok then return nil end
  if type(major)=="table" then return major end
  if tonumber(major) and tonumber(minor) and tonumber(revision) then return {major,minor,revision} end
  return nil
end
function Adapter:refreshCharacterData()
  local controller=DGHUD and DGHUD.controller
  if not controller then return nil,"HUD controller is unavailable" end
  if controller.character_entry_started then
    local collector=controller.collector
    if collector and type(collector.restartRefresh)=="function" then return collector:restartRefresh() end
    if collector and type(collector.forceRefresh)=="function" then return collector:forceRefresh() end
    return nil,"HUD command collector is unavailable"
  end
  if type(controller.onCharacterEntry)=="function" then return controller:onCharacterEntry() end
  return nil,"HUD startup refresh is unavailable"
end
function Adapter:consumeUpdateReinstall()
  if not DGHUD or DGHUD._update_reinstall_pending~=true then return false end
  DGHUD._update_reinstall_pending=nil
  return true
end
function Adapter:reportUpdateCheckFailure(message) cecho("\n<yellow>[DGHUD Update]<reset> Version check failed: "..tostring(message).."; refreshing character data.\n") end
function Adapter:updateClock()
  if type(getEpoch)=="function" then return tonumber(getEpoch()) or os.time() end
  return os.time()
end
function Adapter:reportUpdateStage(stage,elapsed)
  cecho(string.format("\n<gold>[DGHUD Update]<reset> %s (%.1fs)\n",tostring(stage),tonumber(elapsed) or 0))
end
function Adapter:openSettings() cecho("\n<gold>[DGHUD]<reset> Settings: "..getMudletHomeDir().."/DragonsGateHUD/settings.lua\n") end
local function readFile(path) local f=io.open(path,"rb"); if not f then return nil end; local data=f:read("*a"); f:close(); return data end
local function writeFile(path,data) local f=assert(io.open(path,"wb")); f:write(data); f:close() end
local function hasPackage(name) for _,value in ipairs(getPackages() or {}) do if value==name then return true end end return false end
function Adapter:checkLatestAsync(updater,done)
  local settings=updater.settings; local github=settings.github or {}; local policy=settings.update or {}
  if github.owner=="GITHUB_OWNER" or not tostring(github.owner):match("^[%w_.-]+$") or not tostring(github.repository):match("^[%w_.-]+$") then return nil,"configure the GitHub owner and repository first" end
  local base=Adapter.updateBase(getMudletHomeDir()); local staging=base.."/staging"; lfs.mkdir(base); lfs.mkdir(staging)
  local manifestPath=staging.."/startup-manifest.json"; local ids={}; local timeoutId; local finished=false
  local function cleanup() for _,id in ipairs(ids) do killAnonymousEventHandler(id) end; ids={}; if timeoutId then killTimer(timeoutId); timeoutId=nil end end
  local function finish(manifest,message) if finished then return end; finished=true; cleanup(); done(manifest,message) end
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadError",function(_,message,url) if url and url:find(github.repository,1,true) then finish(nil,message) end end)
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadDone",function(_,path)
    if path~=manifestPath then return end
    local raw=readFile(path); if not raw or #raw>(policy.manifest_limit or 65536) then finish(nil,"manifest is missing or too large"); return end
    local ok,manifest=pcall(yajl.to_value,raw); if not ok then finish(nil,"manifest JSON is invalid"); return end
    local valid,why=updater:validateManifest(manifest); if not valid then finish(nil,why); return end
    finish(manifest,nil,raw)
  end)
  updateNonce=updateNonce+1
  downloadFile(manifestPath,Adapter.manifestUrl(github,tostring(os.time()).."-"..tostring(updateNonce)))
  timeoutId=tempTimer(policy.timeout_seconds or 30,function() timeoutId=nil; finish(nil,"download timed out") end)
  return true
end
function Adapter:startUpdate(updater,done,validatedManifest,validatedManifestRaw)
  local settings=updater.settings; local github=settings.github or {}; local policy=settings.update or {}
  if github.owner=="GITHUB_OWNER" or not tostring(github.owner):match("^[%w_.-]+$") or not tostring(github.repository):match("^[%w_.-]+$") then return nil,"configure the GitHub owner and repository first" end
  local base=Adapter.updateBase(getMudletHomeDir()); local staging=base.."/staging"; lfs.mkdir(base); lfs.mkdir(staging)
  local manifestPath=staging.."/manifest.json"; local packagePath=Adapter.updateArchivePath(getMudletHomeDir())
  local rollbackManifestPath=staging.."/rollback-manifest.json"; local rollbackPackagePath=staging.."/rollback.mpackage"
  local currentPath=base.."/current.mpackage"; local currentManifestPath=base.."/current-manifest.json"; local previousPath=base.."/previous.mpackage"; local rollbackInstallPath=base.."/DragonsGateHUD.mpackage"
  local ids={}; local timers={}; local timeoutId; local expectedPath; local expectedUrl; local targetManifest; local targetManifestRaw; local rollbackManifest; local previousDigest; local finished=false
  local function schedule(delay,fn) local id; id=tempTimer(delay,function() for i,value in ipairs(timers) do if value==id then table.remove(timers,i); break end end; fn() end); timers[#timers+1]=id; return id end
  local function disarmTimeout() if timeoutId then killTimer(timeoutId); timeoutId=nil end end
  local function cleanup() for _,id in ipairs(ids) do killAnonymousEventHandler(id) end; ids={}; for _,id in ipairs(timers) do killTimer(id) end; timers={}; disarmTimeout(); updater:release() end
  local function fail(message) if finished then return end; finished=true; cleanup(); cecho("\n<red>[DGHUD Update]<reset> "..tostring(message).."\n"); if done then done(nil,message) end end
  local function armTimeout() disarmTimeout(); timeoutId=tempTimer(policy.timeout_seconds or 30,function() timeoutId=nil; if updater.lock then fail("download timed out") end end) end
  local function request(path,url) expectedPath=path; expectedUrl=url; updater.expected_path=path; armTimeout(); downloadFile(path,url) end
  local function parseManifest(path)
    local raw=readFile(path); if not raw or #raw>(policy.manifest_limit or 65536) then return nil,nil,"manifest is missing or too large" end
    local ok,manifest=pcall(yajl.to_value,raw); if not ok then return nil,nil,"manifest JSON is invalid" end
    local valid,why=updater:validateManifest(manifest); if not valid then return nil,nil,why end
    return manifest,raw
  end
  local function exactInstalled(manifest) return manifest and tostring(manifest.version)==tostring(settings.version) end
  local beginReplacement
  local function stageRollback(payload,preverified)
    if preverified~=true and not Adapter.verifyArchive(payload,rollbackManifest.sha256) then return fail("rollback package checksum mismatch") end
    writeFile(previousPath,payload); previousDigest=tostring(rollbackManifest.sha256):lower(); beginReplacement()
  end
  local function bootstrapRollback()
    updater:stage("Preparing rollback")
    local cached=readFile(currentPath); local cachedManifestRaw=readFile(currentManifestPath)
    if cached and cachedManifestRaw then
      local ok,cachedManifest=pcall(yajl.to_value,cachedManifestRaw)
      if ok then
        local valid=updater:validateManifest(cachedManifest)
        -- This archive was checksum-verified before it became current.mpackage.
        -- Defer re-verification until rollback is actually needed, where
        -- rollbackAsync verifies it before installation.
        if valid and exactInstalled(cachedManifest) and #cached<=(policy.package_limit or 10485760) then rollbackManifest=cachedManifest; return stageRollback(cached,true) end
      end
    end
    updateNonce=updateNonce+1
    request(rollbackManifestPath,Adapter.versionManifestUrl(github,settings.version,tostring(os.time()).."-"..tostring(updateNonce)))
  end
  beginReplacement=function()
    updater:stage("Installing")
    disarmTimeout(); expectedPath=nil; expectedUrl=nil
    self.replacePackageAsync=function(_,data,name,replaceDone)
      if name~="DragonsGateHUD" then replaceDone(nil,"package identity mismatch"); return end
      writeFile(packagePath,data)
      if DGHUD then DGHUD._update_reinstall_pending=true end
      if DGHUD and DGHUD.shutdown then pcall(DGHUD.shutdown) end
      if hasPackage(name) then local removed=uninstallPackage(name); if removed==nil then replaceDone(nil,"could not remove existing HUD package"); return end end
      schedule(0.25,function()
        local installed=installPackage(packagePath)
        if installed==nil then replaceDone(nil,"could not install HUD package"); return end
        -- Mudlet can finish loading a larger package after installPackage returns.
        -- Give package scripts time to register before the updater health check.
        schedule(1.00,function() replaceDone(true) end)
      end)
    end
    self.healthCheck=function() return DGHUD and DGHUD.healthCheck and DGHUD.healthCheck() end
    self.rollbackAsync=function(_,name,rollbackDone)
      local rollbackPayload=readFile(previousPath)
      if name~="DragonsGateHUD" or not rollbackPayload then rollbackDone(nil,"no rollback package available"); return end
      if not Adapter.verifyArchive(rollbackPayload,previousDigest) then rollbackDone(nil,"rollback package checksum mismatch"); return end
      if DGHUD then DGHUD._update_reinstall_pending=true end
      if DGHUD and DGHUD.shutdown then pcall(DGHUD.shutdown) end
      if hasPackage(name) then uninstallPackage(name) end
      schedule(0.25,function()
        -- Mudlet derives the installed package identity from the archive filename.
        -- Installing previous.mpackage registers a package named "previous" and
        -- leaves DragonsGateHUD missing, so stage the verified bytes under the
        -- canonical package filename before restoring.
        writeFile(rollbackInstallPath,rollbackPayload)
        local restored=installPackage(rollbackInstallPath)
        schedule(1.00,function() rollbackDone(restored~=nil,restored==nil and "could not restore rollback package" or nil) end)
      end)
    end
    local completed=false
    local started,why=updater:installVerifiedAsync(readFile(packagePath),targetManifest.sha256,function(installed,message)
      completed=true
      if not installed then fail(message); return end
      writeFile(currentPath,readFile(packagePath)); writeFile(currentManifestPath,targetManifestRaw)
      if finished then return end; updater:stage("Completed"); local elapsed=updater.update_started_at and math.max(0,updater.adapter:updateClock()-updater.update_started_at) or 0; finished=true; cleanup(); cecho(string.format("\n<green>[DGHUD Update]<reset> Installed version %s (%.1fs)\n",tostring(targetManifest.version),elapsed)); if done then done(true) end
    end,true)
    if not started and not completed then fail(why) end
  end
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadError",function(_,message,url) if expectedUrl and url==expectedUrl then fail(message) end end)
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadDone",function(_,path)
    if finished or path~=expectedPath then return end
    disarmTimeout(); expectedPath=nil; expectedUrl=nil
    if path==manifestPath then
      local manifest,raw,why=parseManifest(path); if not manifest then return fail(why) end
      targetManifest=manifest; targetManifestRaw=raw; updater:stage("Downloading package"); request(packagePath,manifest.archive_url)
    elseif path==packagePath then
      local payload=readFile(path)
      if not payload or #payload>(policy.package_limit or 10485760) then return fail("package is missing or too large") end
      if not Adapter.verifyArchive(payload,targetManifest.sha256) then return fail("package checksum mismatch") end
      bootstrapRollback()
    elseif path==rollbackManifestPath then
      local manifest,_,why=parseManifest(path); if not manifest then return fail("rollback bootstrap failed: "..tostring(why)) end
      if not exactInstalled(manifest) then return fail("rollback bootstrap returned the wrong installed version") end
      rollbackManifest=manifest
      local cached=readFile(currentPath)
      if cached and #cached<=(policy.package_limit or 10485760) then stageRollback(cached,true)
      else request(rollbackPackagePath,manifest.archive_url) end
    elseif path==rollbackPackagePath then
      local payload=readFile(path)
      if not payload or #payload>(policy.package_limit or 10485760) then return fail("rollback package is missing or too large") end
      stageRollback(payload,false)
    end
  end)
  if validatedManifest then
    local valid,why=updater:validateManifest(validatedManifest); if not valid then cleanup(); return nil,why end
    targetManifest=validatedManifest
    targetManifestRaw=validatedManifestRaw
    if type(targetManifestRaw)~="string" and yajl and type(yajl.to_string)=="function" then targetManifestRaw=yajl.to_string(validatedManifest) end
    if type(targetManifestRaw)~="string" then cleanup(); return nil,"validated manifest source is unavailable" end
    updater:stage("Downloading package"); request(packagePath,targetManifest.archive_url)
  else
    updater:stage("Checking")
    updateNonce=updateNonce+1
    local latest=Adapter.manifestUrl(github,tostring(os.time()).."-"..tostring(updateNonce))
    request(manifestPath,latest)
  end
  return true
end
return Adapter
