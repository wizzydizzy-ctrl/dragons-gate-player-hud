local View=require("view"); local Storage=require("chat_storage"); local MapAdapter=require("map_adapter")
local SHA256
local function sha256Hex(payload)
  if not SHA256 then SHA256=require("sha256") end
  return SHA256.hex(payload)
end
local Adapter={recovery_version="1.6.0"}; Adapter.__index=Adapter
function Adapter.dataBase(home) return tostring(home or getMudletHomeDir()):gsub("[/\\]+$","").."/DGHUDData" end
function Adapter.prepareDataDirectory(home)
  home=tostring(home or getMudletHomeDir()):gsub("[/\\]+$","")
  local target=Adapter.dataBase(home)
  local inspect=lfs and lfs.symlinkattributes
  if type(inspect)~="function" or type(lfs.mkdir)~="function" then return nil,"filesystem is unavailable" end
  local function mode(path)
    local ok,value,message,code=pcall(inspect,path,"mode")
    if not ok then return nil,tostring(value) end
    if value==nil and message then
      local lower=tostring(message):lower()
      if tonumber(code)~=2 and not lower:find("no such file",1,true) and not lower:find("cannot find the file",1,true) then return nil,tostring(message) end
    end
    return value
  end
  local function ensure(path)
    local current,currentErr=mode(path); if currentErr then return nil,currentErr end
    if current=="directory" then return true end
    if current~=nil then return nil,"path is not a directory" end
    local called,made,makeErr=pcall(lfs.mkdir,path); if called and made then return true end
    local retry,retryErr=mode(path); if retry=="directory" then return true end
    return nil,tostring((not called and made) or makeErr or retryErr or "could not create directory")
  end
  local made,makeErr=ensure(target); if not made then return nil,"could not create persistent HUD data directory: "..tostring(makeErr) end
  local legacy=home.."/DragonsGateHUD"
  local legacyMode,legacyErr=mode(legacy); if legacyErr then return nil,"could not inspect legacy HUD data: "..legacyErr end
  if legacyMode==nil then return true end
  if legacyMode~="directory" then return nil,"legacy HUD data path is not a directory" end
  local packageFiles={['DragonsGateHUD.xml']=true,['DGHUDRuntime.lua']=true,['config.lua']=true}
  local function readChunk(file)
    local ok,chunk,readErr=pcall(file.read,file,65536)
    if not ok then return nil,tostring(chunk),false end
    if chunk==nil and readErr then return nil,tostring(readErr),false end
    return chunk,nil,true
  end
  local function filesEqual(first,second)
    local left,leftErr=io.open(first,"rb"); if not left then return nil,tostring(leftErr) end
    local right,rightErr=io.open(second,"rb"); if not right then left:close(); return nil,tostring(rightErr) end
    while true do
      local a,aErr,aOK=readChunk(left); local b,bErr,bOK=readChunk(right)
      if not aOK or not bOK then left:close(); right:close(); return nil,aErr or bErr end
      if a~=b then left:close(); right:close(); return false end
      if a==nil then left:close(); right:close(); return true end
    end
  end
  local temporaryCounter=0
  local function temporaryPath(destination)
    for _=1,1000 do
      temporaryCounter=temporaryCounter+1
      local candidate=destination..".dghud-tmp-"..temporaryCounter
      local candidateMode,candidateErr=mode(candidate); if candidateErr then return nil,candidateErr end
      if candidateMode==nil then return candidate end
    end
    return nil,"could not reserve a unique migration staging path"
  end
  local function copyFile(source,destination)
    local destinationMode,destinationErr=mode(destination); if destinationErr then return nil,destinationErr end
    if destinationMode=="file" then
      local same,sameErr=filesEqual(source,destination); if same==nil then return nil,sameErr end
      if same then return true end
      return nil,"persistent destination differs; run the DGHUD safe-upgrade bridge"
    end
    if destinationMode~=nil then return nil,"persistent destination has the wrong type" end
    local input,inputErr=io.open(source,"rb"); if not input then return nil,tostring(inputErr) end
    local temporary,tempErr=temporaryPath(destination); if not temporary then input:close(); return nil,tempErr end
    local output,outputErr=io.open(temporary,"wb"); if not output then input:close(); return nil,tostring(outputErr) end
    while true do
      local chunk,readErr,readOK=readChunk(input)
      if not readOK then input:close(); output:close(); os.remove(temporary); return nil,readErr end
      if chunk==nil then break end
      local writeOK,wrote,writeErr=pcall(output.write,output,chunk)
      if not writeOK or not wrote then input:close(); output:close(); os.remove(temporary); return nil,tostring((not writeOK and wrote) or writeErr or "could not write copied data") end
    end
    input:close(); local closeOK,closed,closeErr=pcall(output.close,output)
    if not closeOK or closed==nil then os.remove(temporary); return nil,tostring((not closeOK and closed) or closeErr or "could not close copied data") end
    local same,verifyErr=filesEqual(source,temporary); if not same then os.remove(temporary); return nil,verifyErr or "copied data verification failed" end
    local renameOK,installed,installErr=pcall(os.rename,temporary,destination)
    if not renameOK or not installed then os.remove(temporary); return nil,tostring((not renameOK and installed) or installErr) end
    return true
  end
  local function copyTree(source,destination,depth)
    if depth>12 then return nil,"legacy data nesting exceeds the migration limit" end
    local sourceMode,sourceErr=mode(source); if sourceErr then return nil,sourceErr end
    if sourceMode==nil then return true end
    if sourceMode=="file" then return copyFile(source,destination) end
    if sourceMode~="directory" then return nil,"legacy data contains an unsupported filesystem entry" end
    local ok,err=ensure(destination); if not ok then return nil,err end
    local opened,iterator,state=pcall(lfs.dir,source); if not opened or type(iterator)~="function" then return nil,"could not inspect legacy HUD data" end
    for name in iterator,state do
      if name~="." and name~=".." then
        if type(name)~="string" or name:find("[/\\]") then return nil,"legacy data contains an unsafe name" end
        local copied,copyErr=copyTree(source.."/"..name,destination.."/"..name,depth+1); if not copied then return nil,copyErr end
      end
    end
    return true
  end
  local warnings={}
  local opened,iterator,state=pcall(lfs.dir,legacy); if not opened or type(iterator)~="function" then return true,"could not inspect legacy HUD data" end
  for name in iterator,state do
    if name~="." and name~=".." and not packageFiles[name] then
      local copied,copyErr=copyTree(legacy.."/"..name,target.."/"..name,1)
      if not copied then warnings[#warnings+1]=tostring(name)..": "..tostring(copyErr) end
    end
  end
  return true,#warnings>0 and table.concat(warnings,"; ") or nil
end
function Adapter.markUpdateHandoff(hud,destinationSchema)
  if type(hud)~="table" then return nil end
  hud._update_reinstall_pending=true
  local destination=tonumber(destinationSchema); local controller=type(hud.controller)=="table" and hud.controller or nil
  local existing=hud._view_handoff
  local existingValid=type(existing)=="table" and tonumber(existing.schema)==destination and type(existing.view)=="table" and existing.view.root~=nil
  if controller then
    controller.update_handoff=true
    if type(controller.chat)=="table" and type(controller.chat.handoff)=="function" then
      local captured,snapshot=pcall(controller.chat.handoff,controller.chat)
      if captured and type(snapshot)=="table" then hud._chat_handoff=snapshot end
    end
    local sourceSchema=hud.settings and tonumber(hud.settings.view_schema)
    if sourceSchema and sourceSchema==destination and controller.view and controller.view.root then
      hud._view_handoff={schema=sourceSchema,view=controller.view}; controller.update_preserve_view=true
    elseif not existingValid then
      hud._view_handoff=nil; controller.update_preserve_view=nil
    end
  end
  return hud._view_handoff
end
function Adapter.updateBase(home) return home.."/DGHUDUpdater" end
function Adapter.updateArchivePath(home) return Adapter.updateBase(home).."/staging/DragonsGateHUD.mpackage" end
function Adapter.isCanonicalArchivePath(path)
  local normalized=tostring(path or ""):gsub("\\","/")
  return normalized:match("([^/]+)$")=="DragonsGateHUD.mpackage"
end
function Adapter.verifyArchive(payload,digest) return type(payload)=="string" and type(digest)=="string" and sha256Hex(payload)==digest end
function Adapter.nativeHashSpec(osName,path)
  osName=tostring(osName or ""):lower()
  if osName=="mac" or osName=="macos" or osName=="osx" then return "/usr/bin/shasum",{"-a","256",path} end
  if osName=="linux" or osName=="freebsd" or osName=="openbsd" or osName=="netbsd" then return "/usr/bin/sha256sum",{path} end
  if osName=="windows" then
    local root=os.getenv("SystemRoot") or os.getenv("WINDIR") or "C:\\Windows"
    return root.."\\System32\\certutil.exe",{"-hashfile",path,"SHA256"}
  end
end
function Adapter.parseNativeHash(output)
  output=tostring(output or "")
  for line in (output.."\n"):gmatch("([^\r\n]*)[\r\n]+") do
    local compact=line:gsub("%s",""):lower()
    if #compact==64 and compact:match("^[0-9a-f]+$") then return compact end
  end
  for token in output:gmatch("%x+") do if #token==64 then return token:lower() end end
end
function Adapter.manifestUrl(github,nonce)
  return "https://github.com/"..github.owner.."/"..github.repository.."/releases/latest/download/manifest.json"
end
function Adapter.latestReleaseUrl(github)
  return "https://api.github.com/repos/"..github.owner.."/"..github.repository.."/releases/latest"
end
function Adapter.versionManifestUrl(github,version,nonce)
  return "https://github.com/"..github.owner.."/"..github.repository.."/releases/download/v"..tostring(version).."/manifest.json"
end
local updateNonce=0
function Adapter.new() return setmetatable({},Adapter) end
function Adapter:getBorders() return getBorderLeft(),getBorderTop(),getBorderRight(),getBorderBottom() end
function Adapter:getWindowSize() return getMainWindowSize() end
function Adapter:setBorders(l,t,r,b) setBorderLeft(l);setBorderTop(t);setBorderRight(r);setBorderBottom(b) end
function Adapter:getMainConsoleWrap(api)
  api=api or _G
  if type(api.getWindowWrap)~="function" then return nil end
  local ok,value=pcall(api.getWindowWrap,"main")
  value=ok and tonumber(value) or nil
  return value and value>=1 and math.floor(value) or nil
end
function Adapter:mainConsoleWrapColumns(pixelWidth,allowance,api)
  api=api or _G
  pixelWidth=math.max(1,tonumber(pixelWidth) or 1)
  allowance=math.max(0,tonumber(allowance) or 0)
  -- When Mudlet has already committed the new border geometry, its native
  -- column count accounts for platform DPI, frame styling, and scrollbars
  -- more accurately than any fixed pixel estimate. Reject stale geometry
  -- after a large resize and fall back to the known responsive width below.
  if type(api.getMainConsoleWidth)=="function" and type(api.getColumnCount)=="function" then
    local widthOK,liveWidth=pcall(api.getMainConsoleWidth)
    local columnsOK,liveColumns=pcall(api.getColumnCount,"main")
    liveWidth=widthOK and tonumber(liveWidth) or nil; liveColumns=columnsOK and tonumber(liveColumns) or nil
    local tolerance=math.max(32,pixelWidth*.04)
    if liveWidth and liveWidth>0 and liveColumns and liveColumns>0 and math.abs(liveWidth-pixelWidth)<=tolerance then
      return math.max(1,math.min(1000,math.floor(liveColumns)-1))
    end
  end
  local cellWidth
  if type(api.calcFontSize)=="function" then
    local ok,value=pcall(api.calcFontSize,"main")
    if ok and tonumber(value) and tonumber(value)>0 then cellWidth=tonumber(value) end
  end
  -- calcFontSize(window) is available in Mudlet 5.x. Keep a conservative
  -- fallback so a missing font metric never prevents the HUD from loading.
  cellWidth=cellWidth or 8
  return math.max(1,math.min(1000,math.floor(math.max(1,pixelWidth-allowance)/cellWidth)))
end
function Adapter:setMainConsoleWrap(columns,api)
  api=api or _G; columns=math.max(1,math.floor(tonumber(columns) or 1))
  if type(api.setWindowWrap)~="function" then return nil,"main-console wrapping is unavailable" end
  if self:getMainConsoleWrap(api)==columns then return columns end
  local ok,result=pcall(api.setWindowWrap,"main",columns)
  if not ok or result==false then return nil,ok and "main-console wrap was rejected" or tostring(result) end
  return columns
end
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
function Adapter:adoptView(view,settings)
  if type(view)~="table" or not view.root then return nil,"preserved HUD view is unavailable" end
  setmetatable(view,View)
  local ok,result,message=pcall(view.prepareForReuse,view,settings)
  if not ok then return nil,result end
  if not result then return nil,message or "preserved HUD view could not be prepared" end
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
function Adapter:createChatStorage(visibleLimit) local home=getMudletHomeDir(); return Storage.new(Storage.mudletApi(home,"DGHUDData"),Adapter.dataBase(home).."/chat",visibleLimit) end
function Adapter:saveMapDiagnostic(payload)
  local base=Adapter.dataBase(); lfs.mkdir(base); local directory=base.."/diagnostics"; lfs.mkdir(directory)
  local path=directory.."/mapper-"..os.date("%Y%m%d-%H%M%S")..".txt"; local file,err=io.open(path,"wb"); if not file then return nil,err end
  local ok,writeErr=file:write(tostring(payload or "")); if not ok then file:close(); return nil,writeErr end; file:close(); return path
end
function Adapter:saveFailureReport(report)
  local ok,payload=pcall(yajl.to_string,report); if not ok or type(payload)~="string" then return nil,"could not encode failure report" end; if #payload>16000 then return nil,"failure report exceeds the safety limit" end
  local base=Adapter.dataBase(); lfs.mkdir(base); local directory=base.."/diagnostics"; lfs.mkdir(directory); local path=directory.."/failure-"..os.date("%Y%m%d-%H%M%S")..".json"; local file,err=io.open(path,"wb"); if not file then return nil,err end
  local wrote,writeErr=file:write(payload.."\n"); if not wrote then file:close(); return nil,writeErr end; file:close(); return path
end
function Adapter:submitFailureReport(report,done)
  if type(done)~="function" then return nil,"failure report callback is required" end; if type(postHTTP)~="function" then return nil,"Mudlet HTTP upload support is unavailable" end
  local detailsOK,details=pcall(yajl.to_string,{generated_epoch=report.generated_epoch,category=report.category,context=report.context,events=report.events}); if not detailsOK then return nil,"could not encode failure report" end
  local request={component=report.category or "unknown",edition=report.edition or "unknown",version=report.hud_version or "unknown",mudlet_version=tostring((self.mudletVersion and self:mudletVersion()) or "unknown"),message=report.message or "unknown failure",details=details}
  local ok,payload=pcall(yajl.to_string,request); if not ok or type(payload)~="string" then return nil,"could not encode failure report" end; if #payload>16000 then return nil,"failure report exceeds the safety limit" end
  local url="https://dghud-maps.wallfamilyarchive.com/v1/diagnostics"; local ids={}; local timer; local finished=false
  local function cleanup() for _,id in ipairs(ids) do killAnonymousEventHandler(id) end; if timer then killTimer(timer) end end
  local function finish(value,err) if finished then return end; finished=true; cleanup(); done(value,err) end
  ids[#ids+1]=registerAnonymousEventHandler("sysPostHttpDone",function(_,actual,body) if actual~=url then return end; local parsed,value=pcall(yajl.to_value,body or ""); if not parsed or type(value)~="table" or value.ok~=true then return finish(nil,type(value)=="table" and value.error or "report service returned an invalid response") end; finish(value) end)
  ids[#ids+1]=registerAnonymousEventHandler("sysPostHttpError",function(_,message,actual) if actual==url then finish(nil,message or "failure report upload failed") end end)
  timer=tempTimer(30,function() timer=nil; finish(nil,"failure report upload timed out") end); local queued,err=postHTTP(payload,url,{["Content-Type"]="application/json",["Accept"]="application/json"}); if queued==false then cleanup(); return nil,err or "Mudlet could not start the report upload" end; return true
end
function Adapter:openMapDiagnosticsFolder()
  local base=Adapter.dataBase(); lfs.mkdir(base); local directory=base.."/diagnostics"; lfs.mkdir(directory)
  if type(openUrl)=="function" then pcall(openUrl,"file://"..directory) end; return directory
end
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
  return sha256Hex(bytes):sub(1,16)
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
  local base=Adapter.dataBase(); local directory=base.."/maps"
  for _,path in ipairs({base,directory}) do if lfs.attributes(path,"mode")~="directory" then local ok,err=lfs.mkdir(path); if not ok and lfs.attributes(path,"mode")~="directory" then return nil,"could not create map export directory "..path..": "..tostring(err) end end end
  return directory
end
function Adapter:mapCollectionDirectory()
  local base=Adapter.dataBase(); local directory=base.."/map-collections"
  for _,path in ipairs({base,directory}) do if lfs.attributes(path,"mode")~="directory" then local ok,err=lfs.mkdir(path); if not ok and lfs.attributes(path,"mode")~="directory" then return nil,"could not create map collection directory "..path..": "..tostring(err) end end end
  return directory
end
function Adapter:mapCollectionPath(id)
  local slug,err=mapToken(id,"collection id"); if not slug then return nil,err end
  local directory,dirErr=self:mapCollectionDirectory(); if not directory then return nil,dirErr end
  return directory.."/"..slug..".dat",slug
end
function Adapter:saveMapCollection(id)
  if type(saveMap)~="function" then return nil,"Mudlet saveMap support is unavailable" end
  local path,err=self:mapCollectionPath(id); if not path then return nil,err end
  local temporary=path..".tmp"; os.remove(temporary)
  local called,saved,saveErr=pcall(saveMap,temporary); if not called then os.remove(temporary); return nil,tostring(saved) end
  if saved~=true then os.remove(temporary); return nil,tostring(saveErr or "Mudlet could not save the map") end
  local backup=path..".bak"; os.remove(backup)
  if lfs.attributes(path,"mode")=="file" then local ok,moveErr=os.rename(path,backup); if not ok then os.remove(temporary); return nil,"could not preserve previous collection: "..tostring(moveErr) end end
  local installed,installErr=os.rename(temporary,path); if not installed then if lfs.attributes(backup,"mode")=="file" then os.rename(backup,path) end; os.remove(temporary); return nil,"could not install collection snapshot: "..tostring(installErr) end
  os.remove(backup)
  local file,openErr=io.open(path,"rb"); if not file then return nil,tostring(openErr) end; local payload=file:read("*a"); file:close()
  local rooms=type(getRooms)=="function" and getRooms() or {}; local roomCount=0; for _ in pairs(type(rooms)=="table" and rooms or {}) do roomCount=roomCount+1 end
  return {path=path,sha256=sha256Hex(payload),room_count=roomCount,bytes=#payload}
end
function Adapter:loadMapCollection(id)
  if type(loadMap)~="function" then return nil,"Mudlet loadMap support is unavailable" end
  local path,err=self:mapCollectionPath(id); if not path then return nil,err end
  if lfs.attributes(path,"mode")~="file" then return nil,"map collection file was not found" end
  local called,loaded,loadErr=pcall(loadMap,path); if not called then return nil,tostring(loaded) end
  if loaded~=true then return nil,tostring(loadErr or "Mudlet could not load the map collection") end
  if type(updateMap)=="function" then pcall(updateMap) end; return path
end
function Adapter:clearCurrentMap()
  if type(deleteMap)~="function" then return nil,"Mudlet deleteMap support is unavailable" end
  local called,ok,err=pcall(deleteMap); if not called then return nil,tostring(ok) end; if ok~=true then return nil,tostring(err or "Mudlet could not clear the current map") end; return true
end
function Adapter:deleteMapCollection(id)
  local path,err=self:mapCollectionPath(id); if not path then return nil,err end
  if lfs.attributes(path,"mode")~="file" then return true end
  local removed,removeErr=os.remove(path); if not removed then return nil,"could not delete collection snapshot: "..tostring(removeErr) end; return true
end
function Adapter:stageDeleteMapCollection(id)
  local path,err=self:mapCollectionPath(id); if not path then return nil,err end; if lfs.attributes(path,"mode")~="file" then return {path=path,staged=nil} end
  local staged=path..".delete-pending"; os.remove(staged); local ok,moveErr=os.rename(path,staged); if not ok then return nil,tostring(moveErr) end; return {path=path,staged=staged}
end
function Adapter:rollbackDeleteMapCollection(token) if not token or not token.staged then return true end; local ok,err=os.rename(token.staged,token.path); if not ok then return nil,tostring(err) end; return true end
function Adapter:commitDeleteMapCollection(token) if not token or not token.staged then return true end; local ok,err=os.remove(token.staged); if not ok then return nil,tostring(err) end; return true end
function Adapter:saveMapCollectionIndex(index)
  local directory,err=self:mapCollectionDirectory(); if not directory then return nil,err end
  local ok,payload=pcall(yajl.to_string,index); if not ok or type(payload)~="string" then return nil,"could not encode map collection index" end
  local path=directory.."/collections.json"; local temporary=path..".tmp"; local file,openErr=io.open(temporary,"wb"); if not file then return nil,tostring(openErr) end
  local wrote,writeErr=file:write(payload.."\n"); if not wrote then file:close(); os.remove(temporary); return nil,tostring(writeErr) end; file:close()
  local function valid(candidate) local input=io.open(candidate,"rb"); if not input then return false end; local raw=input:read("*a"); input:close(); local parsed,value=pcall(yajl.to_value,raw); return parsed and type(value)=="table" end
  local backup=path..".bak"; local previous=path..".previous"; os.remove(previous); local hadPrimary=lfs.attributes(path,"mode")=="file"; local primaryValid=hadPrimary and valid(path)
  if hadPrimary then local moved,moveErr=os.rename(path,previous); if not moved then os.remove(temporary); return nil,tostring(moveErr) end end
  local installed,installErr=os.rename(temporary,path); if not installed then if hadPrimary then os.rename(previous,path) end; return nil,tostring(installErr) end
  if primaryValid then os.remove(backup); local preserved,preserveErr=os.rename(previous,backup); if not preserved then return nil,"new index installed but previous index backup failed: "..tostring(preserveErr) end else os.remove(previous) end
  return true
end
function Adapter:loadMapCollectionIndex()
  local directory,err=self:mapCollectionDirectory(); if not directory then return nil,err end
  local function read(path) local file=io.open(path,"rb"); if not file then return nil end; local payload=file:read("*a"); file:close(); local ok,value=pcall(yajl.to_value,payload); if ok and type(value)=="table" then return value end end
  local path=directory.."/collections.json"; local value=read(path); if value then return value end; local backup=read(path..".bak"); if backup then return backup,"recovered map collection index from backup" end
  if lfs.attributes(path,"mode")=="file" or lfs.attributes(path..".bak","mode")=="file" then return nil,"map collection index is invalid and its backup could not be recovered" end
  return nil,"map collection index was not found"
end
function Adapter:saveMapTransfer(name,data)
  local slug,err=mapToken(name,"map name"); if not slug then return nil,err end
  local ok,payload=pcall(yajl.to_string,data); if not ok or type(payload)~="string" then return nil,"could not encode map JSON" end
  local directory,directoryErr=self:mapTransferDirectory(); if not directory then return nil,directoryErr end
  local destination=directory.."/"..slug..".json"; local nonce=tostring(os.time())..tostring({}):gsub("[^%w]",""); local temporary=destination..".tmp-"..nonce; local backup=destination..".bak"
  local file,openErr=io.open(temporary,"wb"); if not file then return nil,"could not open temporary map export "..temporary..": "..tostring(openErr) end
  local wrote,writeErr=file:write(payload.."\n"); if not wrote then file:close(); os.remove(temporary); return nil,"could not write temporary map export "..temporary..": "..tostring(writeErr) end
  local closed,closeErr=file:close(); if closed==nil then os.remove(temporary); return nil,"could not close temporary map export "..temporary..": "..tostring(closeErr) end
  os.remove(backup); local existing=io.open(destination,"rb"); if existing then existing:close(); local preserved,preserveErr=os.rename(destination,backup); if not preserved then os.remove(temporary); return nil,"could not preserve existing map export "..destination..": "..tostring(preserveErr) end end
  local moved,moveErr=os.rename(temporary,destination); if not moved then local restored,restoreErr=os.rename(backup,destination); os.remove(temporary); return nil,"could not install map export "..destination..": "..tostring(moveErr)..(restored and "" or "; rollback failed: "..tostring(restoreErr)) end
  os.remove(backup)
  return destination,slug
end
function Adapter:loadMapTransfer(name)
  local slug,err=mapToken(name,"map name"); if not slug then return nil,err end
  local directory,directoryErr=self:mapTransferDirectory(); if not directory then return nil,directoryErr end; local path=directory.."/"..slug..".json"; local file,openErr=io.open(path,"rb"); if not file then return nil,openErr or "map file was not found" end
  local payload=file:read("*a"); file:close(); if type(payload)~="string" or #payload>20000000 then return nil,"map file exceeds the 20 MB safety limit" end
  local ok,data=pcall(yajl.to_value,payload); if not ok then return nil,"map JSON is invalid" end; return data,path,slug
end
function Adapter:openMapTransferFolder() local directory,err=self:mapTransferDirectory(); if not directory then return nil,err end; if type(openUrl)=="function" then openUrl("file://"..directory:gsub(" ","%%20")) end; return directory end
function Adapter:copyText(value)
  local text=tostring(value or "")
  if type(setClipboardText)=="function" then local ok,err=pcall(setClipboardText,text); if ok then return true end; return nil,tostring(err) end
  if type(setClipboard)=="function" then local ok,err=pcall(setClipboard,text); if ok then return true end; return nil,tostring(err) end
  return nil,"clipboard integration is unavailable"
end
local function libraryRead(path,limit)
  local file,err=io.open(path,"rb"); if not file then return nil,err end; local value=file:read("*a"); file:close(); if #value>(limit or 20000000) then return nil,"download exceeds safety limit" end; return value
end
function Adapter:fetchMapCatalog(done)
  if type(done)~="function" then return nil,"catalog callback is required" end; if type(downloadFile)~="function" then return nil,"Mudlet download integration is unavailable" end
  local directory,dirErr=self:mapTransferDirectory(); if not directory then return nil,dirErr end; local path=directory.."/.catalog-download.json"; local url="https://raw.githubusercontent.com/wizzydizzy-ctrl/dragons-gate-map-library/main/catalog-v2.json?dghud="..tostring(os.time()); local ids={}; local timer; local finished=false
  local function cleanup() for _,id in ipairs(ids) do killAnonymousEventHandler(id) end; if timer then killTimer(timer) end; os.remove(path) end
  local function finish(value,err) if finished then return end; finished=true; cleanup(); done(value,err) end
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadDone",function(_,actual) if actual~=path then return end; local raw,readErr=libraryRead(path,1048576); if not raw then return finish(nil,readErr) end; local ok,value=pcall(yajl.to_value,raw); if not ok then return finish(nil,"catalog JSON is invalid") end; finish(value) end)
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadError",function(_,message,actualUrl) if actualUrl==url then finish(nil,message or "catalog download failed") end end)
  timer=tempTimer(30,function() timer=nil; finish(nil,"catalog download timed out") end); downloadFile(path,url); return true
end
function Adapter:downloadCatalogMap(entry,done)
  if type(entry)~="table" or type(done)~="function" then return nil,"selected catalog map is required" end; if type(downloadFile)~="function" then return nil,"Mudlet download integration is unavailable" end
  local directory,dirErr=self:mapTransferDirectory(); if not directory then return nil,dirErr end; local path=directory.."/.map-download-"..entry.slug..".json"; local url=entry.download_url; local ids={}; local timer; local finished=false
  local function cleanup() for _,id in ipairs(ids) do killAnonymousEventHandler(id) end; if timer then killTimer(timer) end; os.remove(path) end
  local function finish(value,err) if finished then return end; finished=true; cleanup(); done(value,err) end
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadDone",function(_,actual) if actual~=path then return end; local raw,readErr=libraryRead(path,20000000); if not raw then return finish(nil,readErr) end; if #raw~=entry.bytes then return finish(nil,"downloaded map size does not match the catalog") end; if sha256Hex(raw)~=entry.sha256 then return finish(nil,"downloaded map checksum does not match the catalog") end; local ok,value=pcall(yajl.to_value,raw); if not ok then return finish(nil,"downloaded map JSON is invalid") end; finish(value) end)
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadError",function(_,message,actualUrl) if actualUrl==url then finish(nil,message or "map download failed") end end)
  timer=tempTimer(30,function() timer=nil; finish(nil,"map download timed out") end); downloadFile(path,url); return true
end
function Adapter:publishMap(data,done)
  if type(done)~="function" then return nil,"publish callback is required" end
  if type(postHTTP)~="function" then return nil,"Mudlet HTTP upload support is unavailable" end
  local ok,payload=pcall(yajl.to_string,data); if not ok or type(payload)~="string" then return nil,"could not encode map submission" end
  if #payload>20000000 then return nil,"map submission exceeds the 20 MB limit" end
  local url="https://dghud-maps.wallfamilyarchive.com/v1/maps"; local ids={}; local timer; local finished=false
  local function cleanup() for _,id in ipairs(ids) do killAnonymousEventHandler(id) end; if timer then killTimer(timer) end end
  local function finish(value,err) if finished then return end; finished=true; cleanup(); done(value,err) end
  ids[#ids+1]=registerAnonymousEventHandler("sysPostHttpDone",function(_,actual,body) if actual~=url then return end; local parsed,value=pcall(yajl.to_value,body or ""); if not parsed or type(value)~="table" then return finish(nil,"publisher returned an invalid response") end; if value.ok~=true then return finish(nil,value.error or "map submission was rejected") end; finish(value) end)
  ids[#ids+1]=registerAnonymousEventHandler("sysPostHttpError",function(_,message,actual) if actual==url then finish(nil,message or "map upload failed") end end)
  timer=tempTimer(60,function() timer=nil; finish(nil,"map upload timed out") end)
  local queued,err=postHTTP(payload,url,{["Content-Type"]="application/json",["Accept"]="application/json"}); if queued==false then cleanup(); return nil,err or "Mudlet could not start the upload" end
  return true
end
local function urlEncode(value) return tostring(value or ""):gsub("\n","%%0A"):gsub("([^%w%-_%.~%%])",function(char) return string.format("%%%02X",string.byte(char)) end) end
function Adapter:submitFeedback(entry,done)
  if type(entry)~="table" then return nil,"feedback is required" end; if type(done)~="function" then return nil,"feedback callback is required" end
  local kind=entry.kind=="request" and "request" or entry.kind=="feedback" and "feedback" or nil; if not kind then return nil,"feedback type is invalid" end
  local summary=tostring(entry.summary or ""):match("^%s*(.-)%s*$"); local details=tostring(entry.details or ""):match("^%s*(.-)%s*$")
  if #summary<3 or #summary>200 then return nil,"summary must be 3-200 characters" end; if #details<10 or #details>10000 then return nil,"description must be 10-10000 characters" end
  if summary:find("[%z\1-\8\11\12\14-\31]") or details:find("[%z\1-\8\11\12\14-\31]") then return nil,"feedback contains unsupported characters" end
  if type(postHTTP)~="function" then return nil,"Mudlet HTTP upload support is unavailable" end
  local request={component=kind=="request" and "feature_request" or "user_feedback",edition=tostring((DGHUD and DGHUD.settings and DGHUD.settings.edition) or "unknown"),version=tostring(self.settings and self.settings.version or (DGHUD and DGHUD.settings and DGHUD.settings.version) or "unknown"),mudlet_version=tostring((self.mudletVersion and self:mudletVersion()) or "unknown"),message=summary,details="Type: "..kind.."\nDescription:\n"..details}
  local ok,payload=pcall(yajl.to_string,request); if not ok or type(payload)~="string" then return nil,"could not encode feedback" end; if #payload>16000 then return nil,"feedback exceeds the safety limit" end
  local url="https://dghud-maps.wallfamilyarchive.com/v1/diagnostics"; local ids={}; local timer; local finished=false
  local function cleanup() for _,id in ipairs(ids) do killAnonymousEventHandler(id) end; if timer then killTimer(timer) end end
  local function finish(value,err) if finished then return end; finished=true; cleanup(); done(value,err) end
  ids[#ids+1]=registerAnonymousEventHandler("sysPostHttpDone",function(_,actual,body) if actual~=url then return end; local parsed,value=pcall(yajl.to_value,body or ""); if not parsed or type(value)~="table" or value.ok~=true then return finish(nil,type(value)=="table" and value.error or "feedback service returned an invalid response") end; finish(value) end)
  ids[#ids+1]=registerAnonymousEventHandler("sysPostHttpError",function(_,message,actual) if actual==url then finish(nil,message or "feedback upload failed") end end)
  timer=tempTimer(30,function() timer=nil; finish(nil,"feedback upload timed out") end); local queued,err=postHTTP(payload,url,{["Content-Type"]="application/json",["Accept"]="application/json"}); if queued==false then cleanup(); return nil,err or "Mudlet could not start the feedback upload" end; return true
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
function Adapter:reportCharacterRefresh() cecho("\n<gold>[DGHUD]<reset> Refreshing inventory, combat, character, religion, runes, skills, and time…\n"); return true end
function Adapter:reportDisplayTextScale(name) cecho("\n<gold>[DGHUD]<reset> HUD text size: <white>"..tostring(name or "Normal").."<reset>.\n"); return true end
function Adapter:reportCommandError(message) cecho("\n<red>[DGHUD]<reset> "..tostring(message or "Command failed.").."\n"); return true end
function Adapter:standaloneRollerPresent() return type(rawget(_G,"OGDGROLLER"))=="table" end
function Adapter:startRollerLog(config)
  local function component(value,fallback) value=tostring(value or ""):gsub("[^%w%._%-]","_"); if value=="" or value=="." or value==".." then return fallback end; return value end
  local base=Adapter.dataBase(); lfs.mkdir(base)
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
local function rollerSettingsPath() return Adapter.dataBase().."/roller-settings.lua" end
function Adapter.rollerSettingsSnapshot(config)
  config=type(config)=="table" and config or {}; local optional={target_total=true,hard_stop=true,max_rolls=true,minimum_greats=true,minimum_good_plus=true}
  local fields={"target_total","hard_stop","max_rolls","reroll_delay","reroll_command","arrange_mode","minimum_greats","minimum_good_plus","auto_start_on_name","use_min_stats","require_min_stats_to_stop","show_every_roll","logging_enabled","log_folder","master_file"}
  local result={schema=3,min_stats={}}
  for _,key in ipairs(fields) do local value=config[key]; if optional[key] and value==nil then value=false end; result[key]=value end
  if result.arrange_mode==nil then result.arrange_mode="manual" end
  for _,key in ipairs({"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP","MP"}) do local value=(config.min_stats or {})[key]; if value==nil then value=false end; result.min_stats[key]=value end
  return result
end
function Adapter.rollerSettingsSource(config)
  local snapshot=Adapter.rollerSettingsSnapshot(config)
  local fields={"target_total","hard_stop","max_rolls","reroll_delay","reroll_command","arrange_mode","minimum_greats","minimum_good_plus","auto_start_on_name","use_min_stats","require_min_stats_to_stop","show_every_roll","logging_enabled","log_folder","master_file"}
  local function literal(value) if type(value)=="string" then return string.format("%q",value) elseif value==nil then return "nil" else return tostring(value) end end
  local lines={"return {","  schema="..snapshot.schema..","}
  for _,key in ipairs(fields) do lines[#lines+1]="  "..key.."="..literal(snapshot[key]).."," end
  lines[#lines+1]="  min_stats={"
  for _,key in ipairs({"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP","MP"}) do lines[#lines+1]="    "..key.."="..literal(snapshot.min_stats[key]).."," end
  lines[#lines+1]="  },"; lines[#lines+1]="}"; return table.concat(lines,"\n")
end
function Adapter:saveRollerSettings(config)
  local base=Adapter.dataBase(); lfs.mkdir(base); local temp=rollerSettingsPath()..".tmp"
  local file,err=io.open(temp,"wb"); if not file then return nil,err end; local wrote,writeErr=file:write(Adapter.rollerSettingsSource(config)); if not wrote then file:close(); os.remove(temp); return nil,writeErr end; local closed,closeErr=file:close(); if closed==nil then os.remove(temp); return nil,closeErr end
  local destination=rollerSettingsPath(); local backup=destination..".bak"; os.remove(backup)
  local existing=io.open(destination,"rb"); if existing then existing:close(); local moved,moveErr=os.rename(destination,backup); if not moved then os.remove(temp); return nil,moveErr end end
  local ok,renameErr=os.rename(temp,destination); if not ok then os.rename(backup,destination); return nil,renameErr end; os.remove(backup); return true
end
function Adapter.loadRollerSettings()
  local path=rollerSettingsPath(); local source=""; local file=io.open(path,"rb"); if file then source=file:read("*a") or ""; file:close() end
  local loader=loadfile(path); if not loader then return nil end; local ok,value=pcall(loader); if not ok or type(value)~="table" then return nil end
  if tostring(value.reroll_command or ""):lower()=="n" then value.reroll_command="reroll" end
  local schema=tonumber(value.schema) or 0
  if schema<2 then
    value.min_stats=type(value.min_stats)=="table" and value.min_stats or {}
    if value.min_stats.MP==nil then value.min_stats.MP=false end
    for _,key in ipairs({"target_total","hard_stop","max_rolls"}) do if value[key]==nil and source:match("%f[%w_]"..key.."%f[^%w_]%s*=%s*nil%f[^%w_]") then value[key]=false end end
    for _,key in ipairs({"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"}) do if value.min_stats[key]==nil and source:match("%f[%w_]"..key.."%f[^%w_]%s*=%s*nil%f[^%w_]") then value.min_stats[key]=false end end
  end
  if schema<3 then
    if value.arrange_mode==nil then value.arrange_mode="manual" end
    if value.minimum_greats==nil then value.minimum_greats=false end
    if value.minimum_good_plus==nil then value.minimum_good_plus=false end
  end
  value.schema=3; return value
end
local function mapperSettingsPath() return Adapter.dataBase().."/mapper-settings.lua" end
function Adapter:saveMapperSettings(config)
  local base=Adapter.dataBase(); lfs.mkdir(base); local destination=mapperSettingsPath(); local temp=destination..".tmp"
  local file,err=io.open(temp,"wb"); if not file then return nil,err end
  local function n(key,default) return tonumber(config and config[key]) or default end; local transitions=config and config.transition_submaps or {}
  local body=string.format("return { enabled=%s, minimum_height=%g, height_percent=%g, maximum_height=%g, zoom_step=%g, zoom_min=%g, zoom_max=%g, walk_timeout=%g, special_timeout=%g, transition_submaps={gate=%s,portal=%s,door=%s,arch=%s,path=%s,other=%s} }\n",tostring(not (config and config.enabled==false)),n("minimum_height",90),n("height_percent",.4),n("maximum_height",380),n("zoom_step",2.5),n("zoom_min",3),n("zoom_max",60),n("walk_timeout",12),n("special_timeout",12),tostring(transitions.gate~=false),tostring(transitions.portal~=false),tostring(transitions.door~=false),tostring(transitions.arch~=false),tostring(transitions.path~=false),tostring(transitions.other~=false))
  local wrote,writeErr=file:write(body); if not wrote then file:close(); os.remove(temp); return nil,writeErr end
  local closed,closeErr=file:close(); if closed==nil then os.remove(temp); return nil,closeErr end
  local backup=destination..".bak"; os.remove(backup)
  local existing=io.open(destination,"rb"); if existing then existing:close(); local moved,moveErr=os.rename(destination,backup); if not moved then os.remove(temp); return nil,moveErr end end
  local ok,renameErr=os.rename(temp,destination); if not ok then os.rename(backup,destination); return nil,renameErr end; os.remove(backup); return true
end
function Adapter.loadMapperSettings()
  local loader=loadfile(mapperSettingsPath()); if not loader then return nil end; local ok,value=pcall(loader); if ok and type(value)=="table" and type(value.enabled)=="boolean" then return value end; return nil
end
local function updateSettingsPath() return Adapter.dataBase().."/update-settings.lua" end
function Adapter:saveUpdateSettings(config)
  local base=Adapter.dataBase(); lfs.mkdir(base); local destination=updateSettingsPath(); local temp=destination..".tmp"
  local file,err=io.open(temp,"wb"); if not file then return nil,err end
  local wrote,writeErr=file:write("return { auto_apply="..tostring(type(config)=="table" and config.auto_apply==true).." }\n")
  if not wrote then file:close(); os.remove(temp); return nil,writeErr end; local closed,closeErr=file:close(); if closed==nil then os.remove(temp); return nil,closeErr end
  local backup=destination..".bak"; os.remove(backup); local existing=io.open(destination,"rb"); if existing then existing:close(); local moved,moveErr=os.rename(destination,backup); if not moved then os.remove(temp); return nil,moveErr end end
  local ok,renameErr=os.rename(temp,destination); if not ok then os.rename(backup,destination); return nil,renameErr end; os.remove(backup); return true
end
function Adapter.loadUpdateSettings()
  local loader=loadfile(updateSettingsPath()); if not loader then return nil end; local ok,value=pcall(loader); if ok and type(value)=="table" and type(value.auto_apply)=="boolean" then return value end; return nil
end
local function displaySettingsPath() return Adapter.dataBase().."/display-settings.lua" end
function Adapter.displaySettingsSnapshot(config)
  local scale=tonumber(type(config)=="table" and config.side_text_scale)
  if not scale or scale<.8 or scale>1.2 then return nil,"HUD text scale must be between 0.8 and 1.2" end
  return {side_text_scale=scale}
end
function Adapter:saveDisplaySettings(config)
  local snapshot,snapshotErr=Adapter.displaySettingsSnapshot(config); if not snapshot then return nil,snapshotErr end
  local base=Adapter.dataBase(); lfs.mkdir(base); local destination=displaySettingsPath(); local temp=destination..".tmp"
  local file,err=io.open(temp,"wb"); if not file then return nil,err end
  local wrote,writeErr=file:write(string.format("return { side_text_scale=%.3f }\n",snapshot.side_text_scale)); if not wrote then file:close(); os.remove(temp); return nil,writeErr end
  local closed,closeErr=file:close(); if closed==nil then os.remove(temp); return nil,closeErr end
  local backup=destination..".bak"; os.remove(backup); local existing=io.open(destination,"rb"); if existing then existing:close(); local moved,moveErr=os.rename(destination,backup); if not moved then os.remove(temp); return nil,moveErr end end
  local ok,renameErr=os.rename(temp,destination); if not ok then os.rename(backup,destination); return nil,renameErr end; os.remove(backup); return true
end
function Adapter.loadDisplaySettings()
  local loader=loadfile(displaySettingsPath()); if not loader then return nil end
  local ok,value=pcall(loader); if not ok then return nil end
  local snapshot=Adapter.displaySettingsSnapshot(value); return snapshot
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
  local line=tostring(getCurrentLine and getCurrentLine() or ""):gsub("\27%[[0-?]*[ -/]*[@-~]",""):match("^%s*(.-)%s*$")
  if line=="Dragon's Gate Menu" or line:find("Dragon's Gate Character Creator",1,true) or line:match("^Your selection,.-%?%s*$") or line:match("^Do you wish to %(C, D, V, Q%) %?%s*$") or line:match("^How would you like to begin") then return false end
  if Adapter.characterPrompt(line) then return true end
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
  -- The freshly installed package owns the pending refresh.  Do not let the
  -- retiring updater consume or duplicate that startup sequence.
  if DGHUD and DGHUD._update_reinstall_pending==true then return true end
  local controller=DGHUD and DGHUD.controller
  if not controller then return nil,"HUD controller is unavailable" end
  if controller.character_entry_started then
    local collector=controller.collector
    -- A freshly installed controller starts its own character refresh. Joining
    -- that sequence avoids cancelling it and sending every startup command twice.
    if collector and (collector.active or collector.refreshed) then return true end
    if collector and type(collector.refresh)=="function" then return collector:refresh() end
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
function Adapter:activateInstalledHUD()
  -- Mudlet activates newly installed package scripts after this callback
  -- unwinds. A forced profile reset races that registration and can remove the
  -- package just installed. Native activation is the safe handoff.
  return true
end
function Adapter:reportUpdateCheckFailure(message) cecho("\n<yellow>[DGHUD Update]<reset> Version check failed: "..tostring(message).."; refreshing character data. A privacy-safe report is ready under Map Library > REPORT A PROBLEM.\n"); local controller=DGHUD and DGHUD.controller; if controller and controller.captureFailure then controller:captureFailure("updater",message,{operation="update_check",stage="check"}) end end
function Adapter:reportUpdateFailure(message) cecho("\n<red>[DGHUD Update]<reset> Update failed: "..tostring(message)..". A privacy-safe report is ready under Map Library > REPORT A PROBLEM.\n"); local controller=DGHUD and DGHUD.controller; if controller and controller.captureFailure then controller:captureFailure("updater",message,{operation="update_install",stage="install"}) end end
function Adapter:updateClock()
  if type(getEpoch)=="function" then return tonumber(getEpoch()) or os.time() end
  return os.time()
end
function Adapter:reportUpdateStage(stage,elapsed)
  cecho(string.format("\n<gold>[DGHUD Update]<reset> %s (%.1fs)\n",tostring(stage),tonumber(elapsed) or 0))
end
function Adapter:reportVersionStatus(installed,latest,current)
  if current then cecho(string.format("\n<green>[DGHUD]<reset> Version %s is already up to date.\n",tostring(installed)))
  else cecho(string.format("\n<gold>[DGHUD]<reset> Update available: %s (installed: %s). Run <white>dghud update<reset> when ready.\n",tostring(latest),tostring(installed))) end
end
function Adapter:openSettings() cecho("\n<gold>[DGHUD]<reset> Persistent data: "..Adapter.dataBase().."\n") end
local function readFile(path) local f=io.open(path,"rb"); if not f then return nil end; local data=f:read("*a"); f:close(); return data end
local function fileSize(path) local f=io.open(path,"rb"); if not f then return nil end; local ok,size=pcall(function() return f:seek("end") end); if not ok then local data=f:read("*a"); size=type(data)=="string" and #data or nil end; f:close(); return tonumber(size) end
local function writeFile(path,data)
  if type(data)~="string" then return nil,"file payload is unavailable" end
  local temporary=path..".writing"; os.remove(temporary)
  local file,openErr=io.open(temporary,"wb"); if not file then return nil,tostring(openErr) end
  local writeOK,wrote,writeErr=pcall(file.write,file,data); local closeOK,closed,closeErr=pcall(file.close,file)
  if not writeOK or not wrote or not closeOK or closed==nil then os.remove(temporary); return nil,tostring((not writeOK and wrote) or writeErr or (not closeOK and closed) or closeErr or "file write failed") end
  if readFile(temporary)~=data then os.remove(temporary); return nil,"written file verification failed" end
  os.remove(path)
  local renameOK,installed,renameErr=pcall(os.rename,temporary,path)
  if not renameOK or not installed then os.remove(temporary); return nil,tostring((not renameOK and installed) or renameErr or "could not finalize file") end
  return true
end
local function hasPackage(name) for _,value in ipairs(getPackages() or {}) do if value==name then return true end end return false end
function Adapter.versionAtLeast(actual,required)
  local function tuple(value) local a,b,c=tostring(value or ""):match("^(%d+)%.(%d+)%.(%d+)$"); if not a then return nil end; return tonumber(a),tonumber(b),tonumber(c) end
  local aa,ab,ac=tuple(actual); local ra,rb,rc=tuple(required); if not aa or not ra then return false end
  if aa~=ra then return aa>ra end; if ab~=rb then return ab>rb end; return ac>=rc
end
function Adapter:recoveryPackageCurrent()
  if not hasPackage("DGHUDRecovery") then return false end
  local runtime=rawget(_G,"DGHUDRecovery")
  local github=self.settings and self.settings.github or {}
  return type(runtime)=="table" and Adapter.versionAtLeast(runtime.version,Adapter.recovery_version) and runtime.owner==github.owner and runtime.repository==github.repository and type(runtime.alias)=="number" and runtime.alias>0 and type(runtime.run)=="function"
end
function Adapter:verifyFileAsync(path,digest,done)
  done=done or function() end
  local expected=type(digest)=="string" and digest:lower() or nil
  local finished=false
  local function finish(ok,message) if finished then return end; finished=true; done(ok,message) end
  local function fallback()
    local payload=readFile(path)
    if not payload then finish(nil,"package is missing"); return end
    local valid=Adapter.verifyArchive(payload,expected)
    if valid then finish(true) else finish(false,"package checksum mismatch") end
  end
  if type(expected)~="string" or #expected~=64 or type(rawget(_G,"spawn"))~="function" or type(rawget(_G,"getOS"))~="function" then fallback(); return true end
  local osOK,osName=pcall(getOS); if not osOK then fallback(); return true end
  local program,args=Adapter.nativeHashSpec(osName,path); if not program then fallback(); return true end
  local chunks={}; local process
  local function receive(value) if value~=nil then chunks[#chunks+1]=tostring(value) end end
  local unpackValues=table.unpack or unpack
  local spawned,result=pcall(function() return spawn(receive,program,unpackValues(args)) end)
  if not spawned or type(result)~="table" or type(result.isRunning)~="function" then fallback(); return true end
  process=result
  local attempts=0
  local function closeProcess() if process and type(process.close)=="function" then pcall(process.close) end end
  local function poll()
    if finished then closeProcess(); return end
    attempts=attempts+1
    local runningOK,running=pcall(process.isRunning)
    if runningOK and running and attempts<80 then tempTimer(0.025,poll); return end
    closeProcess()
    local actual=Adapter.parseNativeHash(table.concat(chunks))
    if actual then
      local valid=actual==expected
      if valid then finish(true) else finish(false,"package checksum mismatch") end
    else fallback() end
  end
  tempTimer(0,poll)
  return true
end
function Adapter:ensureRecoveryPackage()
  if self:recoveryPackageCurrent() or self.recovery_installing then return true end
  self.recovery_installing=true
  local retiredRuntime=rawget(_G,"DGHUDRecovery")
  local github=self.settings and self.settings.github or {}; local owner=github.owner or "wizzydizzy-ctrl"; local repository=github.repository or "dragons-gate-player-hud"
  local url="https://github.com/"..owner.."/"..repository.."/releases/latest/download/DGHUDRecovery.mpackage"; local path=getMudletHomeDir().."/DGHUDRecovery.mpackage"; local doneId,errorId,timeoutId; local timers={}; local finished=false
  local function disarmDownload() if doneId then killAnonymousEventHandler(doneId); doneId=nil end; if errorId then killAnonymousEventHandler(errorId); errorId=nil end; if timeoutId then killTimer(timeoutId); timeoutId=nil end end
  local function finish(message) if finished then return end; finished=true; disarmDownload(); for _,id in ipairs(timers) do killTimer(id) end; timers={}; self.recovery_installing=false; if message then cecho("\n<yellow>[DGHUD Recovery]<reset> "..message.." Manual updates remain available.\n") end end
  local function scheduleRecovery(delay,fn) timers[#timers+1]=tempTimer(delay,fn) end
  local function awaitCurrent(remaining)
    local runtime=rawget(_G,"DGHUDRecovery")
    if runtime~=retiredRuntime and self:recoveryPackageCurrent() then finish(); return end
    if remaining<=0 then finish("Companion install was accepted, but version "..Adapter.recovery_version.." did not activate."); return end
    scheduleRecovery(0.25,function() awaitCurrent(remaining-1) end)
  end
  local function installRecovery()
    local installed=installPackage(path); if installed==nil then finish("Companion install failed."); return end
    awaitCurrent(120)
  end
  local function replaceRecovery(remaining)
    if not hasPackage("DGHUDRecovery") then installRecovery(); return end
    if uninstallPackage("DGHUDRecovery") then installRecovery(); return end
    if remaining<=0 then finish("Could not replace the outdated recovery companion after waiting for Mudlet to finish saving."); return end
    scheduleRecovery(0.10,function() replaceRecovery(remaining-1) end)
  end
  doneId=registerAnonymousEventHandler("sysDownloadDone",function(_,downloaded) if downloaded~=path then return end; disarmDownload(); replaceRecovery(300) end)
  errorId=registerAnonymousEventHandler("sysDownloadError",function(_,_,failedUrl) if failedUrl==url then finish("Companion download failed.") end end)
  timeoutId=tempTimer(45,function() finish("Companion download timed out.") end)
  local queued=downloadFile(path,url); if queued==false then finish("Companion download could not start."); return nil,"recovery companion download could not start" end; return true
end
function Adapter:checkLatestAsync(updater,done)
  local settings=updater.settings; local github=settings.github or {}; local policy=settings.update or {}
  if github.owner=="GITHUB_OWNER" or not tostring(github.owner):match("^[%w_.-]+$") or not tostring(github.repository):match("^[%w_.-]+$") then return nil,"configure the GitHub owner and repository first" end
  local base=Adapter.updateBase(getMudletHomeDir()); local staging=base.."/staging"; lfs.mkdir(base); lfs.mkdir(staging)
  local releasePath=staging.."/latest-release.json"; local manifestPath=staging.."/startup-manifest.json"; local ids={}; local timeoutId; local finished=false
  local function cleanup() for _,id in ipairs(ids) do killAnonymousEventHandler(id) end; ids={}; if timeoutId then killTimer(timeoutId); timeoutId=nil end end
  local function finish(manifest,message,raw) if finished then return end; finished=true; cleanup(); done(manifest,message,raw) end
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadError",function(_,message,url) if url and url:find(github.repository,1,true) then finish(nil,message) end end)
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadDone",function(_,path)
    if path==releasePath then
      local raw=readFile(path); if not raw or #raw>1048576 then finish(nil,"release metadata is missing or too large"); return end
      local ok,release=pcall(yajl.to_value,raw); if not ok or type(release)~="table" then finish(nil,"release metadata JSON is invalid"); return end
      local version=type(release.tag_name)=="string" and release.tag_name:match("^v(%d+%.%d+%.%d+)$")
      if not version then finish(nil,"latest release has an invalid version tag"); return end
      os.remove(manifestPath); local queued,queueErr=downloadFile(manifestPath,Adapter.versionManifestUrl(github,version)); if queued==false then finish(nil,queueErr or "manifest download could not start") end; return
    end
    if path~=manifestPath then return end
    local raw=readFile(path); if not raw or #raw>(policy.manifest_limit or 65536) then finish(nil,"manifest is missing or too large"); return end
    local ok,manifest=pcall(yajl.to_value,raw); if not ok then finish(nil,"manifest JSON is invalid"); return end
    local valid,why=updater:validateManifest(manifest); if not valid then finish(nil,why); return end
    finish(manifest,nil,raw)
  end)
  updateNonce=updateNonce+1; os.remove(releasePath)
  local queued,queueErr=downloadFile(releasePath,Adapter.latestReleaseUrl(github))
  if queued==false then finish(nil,queueErr or "release metadata download could not start"); return nil,queueErr or "release metadata download could not start" end
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
  local function request(path,url)
    expectedPath=path; expectedUrl=url; updater.expected_path=path; armTimeout()
    local queued,queueErr=downloadFile(path,url)
    if queued==false then fail(queueErr or "download could not start"); return nil end
    return true
  end
  local function parseManifest(path)
    local raw=readFile(path); if not raw or #raw>(policy.manifest_limit or 65536) then return nil,nil,"manifest is missing or too large" end
    local ok,manifest=pcall(yajl.to_value,raw); if not ok then return nil,nil,"manifest JSON is invalid" end
    local valid,why=updater:validateManifest(manifest); if not valid then return nil,nil,why end
    return manifest,raw
  end
  local function exactInstalled(manifest) return manifest and tostring(manifest.version)==tostring(settings.version) end
  local function runtimeHealthy(version,retiredRuntime)
    if not hasPackage("DragonsGateHUD") then return nil,"installed HUD package was not registered" end
    local hud=rawget(_G,"DGHUD")
    if type(hud)~="table" or type(hud.settings)~="table" or tostring(hud.settings.version)~=tostring(version) then return nil,"installed HUD version did not activate" end
    if retiredRuntime~=nil and hud==retiredRuntime then return nil,"installed HUD runtime did not restart" end
    if type(hud.healthCheck)~="function" then return nil,"installed HUD health check is unavailable" end
    local ok,healthy,why=pcall(hud.healthCheck)
    if not ok then return nil,"installed HUD health check failed" end
    if not healthy then return nil,why or "installed HUD is not healthy" end
    return true
  end
  local function markUpdateHandoff(destinationSchema)
    Adapter.markUpdateHandoff(rawget(_G,"DGHUD"),destinationSchema)
  end
  local function clearUpdateHandoff()
    local hud=rawget(_G,"DGHUD")
    if type(hud)~="table" then return end
    hud._update_reinstall_pending=nil
    if type(hud.controller)=="table" then hud.controller.update_handoff=nil; hud.controller.update_preserve_view=nil end
  end
  local function awaitRuntime(version,attempts,done,retiredRuntime)
    local remaining=tonumber(attempts) or 12
    local function probe()
      local healthy,why=runtimeHealthy(version,retiredRuntime)
      if healthy then done(true); return end
      if remaining<=0 then done(nil,why); return end
      remaining=remaining-1
      schedule(0.25,probe)
    end
    -- Synchronous activation succeeds without paying a fixed quarter-second;
    -- deferred Mudlet activation still receives the full three-second window.
    probe()
  end
  local function removeWhenReady(name,attempts,message,done)
    local remaining=tonumber(attempts) or 1
    local function attempt()
      if not hasPackage(name) then done(true); return end
      local removed=uninstallPackage(name)
      if removed then done(true); return end
      if remaining<=0 then done(nil,message); return end
      remaining=remaining-1
      schedule(0.10,attempt)
    end
    attempt()
  end
  local beginReplacement
  local function stageRollback(payload,preverified)
    if preverified~=true and not Adapter.verifyArchive(payload,rollbackManifest.sha256) then return fail("rollback package checksum mismatch") end
    local written,writeErr=writeFile(previousPath,payload); if not written then return fail("could not stage rollback package: "..tostring(writeErr)) end
    previousDigest=tostring(rollbackManifest.sha256):lower(); beginReplacement()
  end
  local function bootstrapRollback()
    updater:stage("Preparing rollback")
    local cachedManifestRaw=readFile(currentManifestPath)
    if cachedManifestRaw then
      local ok,cachedManifest=pcall(yajl.to_value,cachedManifestRaw)
      if ok then
        local valid=updater:validateManifest(cachedManifest)
        local cachedSize=fileSize(currentPath)
        if valid and exactInstalled(cachedManifest) and cachedSize and cachedSize<=(policy.package_limit or 10485760) then
          self:verifyFileAsync(currentPath,cachedManifest.sha256,function(verified)
            if finished then return end
            if verified then
              local cached=readFile(currentPath); if not cached then return fail("cached rollback package disappeared") end
              rollbackManifest=cachedManifest; stageRollback(cached,true); return
            end
            updateNonce=updateNonce+1
            request(rollbackManifestPath,Adapter.versionManifestUrl(github,settings.version,tostring(os.time()).."-"..tostring(updateNonce)))
          end)
          return
        end
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
      if not Adapter.isCanonicalArchivePath(packagePath) then replaceDone(nil,"package archive filename is not canonical"); return end
      local prepareCalled,prepared,prepareWarning=pcall(Adapter.prepareDataDirectory,getMudletHomeDir())
      if not prepareCalled or not prepared or prepareWarning then replaceDone(nil,"persistent data preflight failed; nothing was removed: "..tostring((not prepareCalled and prepared) or prepareWarning or "filesystem is unavailable")); return end
      local retiredRuntime=rawget(_G,"DGHUD")
      markUpdateHandoff(targetManifest.view_schema)
      local retryWindow=math.max(12,math.ceil((tonumber(policy.timeout_seconds) or 30)/0.10))
      removeWhenReady(name,retryWindow,"could not remove existing HUD package while Mudlet was saving",function(removed,removeErr)
        if not removed then clearUpdateHandoff(); replaceDone(nil,removeErr); return end
        -- Mudlet queues a full profile save on the next event-loop pass after
        -- an uninstall. Install in this same callback so that save contains the
        -- replacement rather than forcing installation to wait behind it.
        local installed=installPackage(packagePath)
        if installed==nil then replaceDone(nil,"could not install HUD package"); return end
        awaitRuntime(targetManifest.version,12,replaceDone,retiredRuntime)
      end)
    end
    self.healthCheck=nil
    self.rollbackAsync=function(_,name,rollbackDone)
      if name~="DragonsGateHUD" or not fileSize(previousPath) then rollbackDone(nil,"no rollback package available"); return end
      self:verifyFileAsync(previousPath,previousDigest,function(verified)
        if not verified then rollbackDone(nil,"rollback package checksum mismatch"); return end
        local rollbackPayload=readFile(previousPath); if not rollbackPayload then rollbackDone(nil,"no rollback package available"); return end
        -- Mudlet derives the installed package identity from the archive filename.
        -- Installing previous.mpackage registers a package named "previous" and
        -- leaves DragonsGateHUD missing, so stage the verified bytes under the
        -- canonical package filename before restoring.
        if not Adapter.isCanonicalArchivePath(rollbackInstallPath) then rollbackDone(nil,"rollback archive filename is not canonical"); return end
        local staged,stageErr=writeFile(rollbackInstallPath,rollbackPayload); if not staged then rollbackDone(nil,"could not stage rollback install: "..tostring(stageErr)); return end
        local retiredRuntime=rawget(_G,"DGHUD")
        local prepareCalled,prepared,prepareWarning=pcall(Adapter.prepareDataDirectory,getMudletHomeDir())
        if not prepareCalled or not prepared or prepareWarning then rollbackDone(nil,"rollback data preflight failed; nothing was removed: "..tostring((not prepareCalled and prepared) or prepareWarning or "filesystem is unavailable")); return end
        markUpdateHandoff(rollbackManifest and rollbackManifest.view_schema)
        local retryWindow=math.max(12,math.ceil((tonumber(policy.timeout_seconds) or 30)/0.10))
        removeWhenReady(name,retryWindow,"could not remove failed HUD package while Mudlet was saving",function(removed,removeErr)
          if not removed then clearUpdateHandoff(); rollbackDone(nil,removeErr); return end
          -- A successful uninstall guarantees no profile save was active at that
          -- instant. Install in the same callback, before its deferred save runs.
          local restored=installPackage(rollbackInstallPath)
          if restored==nil then clearUpdateHandoff(); rollbackDone(nil,"could not restore rollback package"); return end
          local healthAttempts=math.max(12,math.ceil((tonumber(policy.timeout_seconds) or 30)/0.25))
          awaitRuntime(rollbackManifest and rollbackManifest.version or settings.version,healthAttempts,rollbackDone,retiredRuntime)
        end)
      end)
    end
    local completed=false
    local started,why=updater:installVerifiedAsync(readFile(packagePath),targetManifest.sha256,function(installed,message)
      completed=true
      if not installed then fail(message); return end
      local cachedPackage,cachePackageErr=writeFile(currentPath,readFile(packagePath)); local cachedManifest,cacheManifestErr=writeFile(currentManifestPath,targetManifestRaw)
      if not cachedPackage or not cachedManifest then cecho("\n<yellow>[DGHUD Update]<reset> Update succeeded, but the rollback cache could not be refreshed: "..tostring(cachePackageErr or cacheManifestErr).."\n") end
      if finished then return end; updater:stage("Completed"); local elapsed=updater.update_started_at and math.max(0,updater.adapter:updateClock()-updater.update_started_at) or 0; finished=true; cleanup(); cecho(string.format("\n<green>[DGHUD Update]<reset> Installed version %s (%.1fs)\n",tostring(targetManifest.version),elapsed)); if done then done(true) end; local activated,activateErr=self:activateInstalledHUD(); if not activated then cecho("\n<yellow>[DGHUD Update]<reset> Installed successfully; automatic HUD reload was unavailable: "..tostring(activateErr).."\n") end
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
      local size=fileSize(path)
      if not size or size>(policy.package_limit or 10485760) then return fail("package is missing or too large") end
      self:verifyFileAsync(path,targetManifest.sha256,function(verified)
        if finished then return end
        if not verified then return fail("package checksum mismatch") end
        bootstrapRollback()
      end)
    elseif path==rollbackManifestPath then
      local manifest,_,why=parseManifest(path); if not manifest then return fail("rollback bootstrap failed: "..tostring(why)) end
      if not exactInstalled(manifest) then return fail("rollback bootstrap returned the wrong installed version") end
      rollbackManifest=manifest
      local cachedSize=fileSize(currentPath)
      if cachedSize and cachedSize<=(policy.package_limit or 10485760) then
        self:verifyFileAsync(currentPath,manifest.sha256,function(verified)
          if finished then return end
          if verified then local cached=readFile(currentPath); if cached then stageRollback(cached,true); return end end
          request(rollbackPackagePath,manifest.archive_url)
        end)
      else request(rollbackPackagePath,manifest.archive_url) end
    elseif path==rollbackPackagePath then
      local size=fileSize(path)
      if not size or size>(policy.package_limit or 10485760) then return fail("rollback package is missing or too large") end
      self:verifyFileAsync(path,rollbackManifest.sha256,function(verified)
        if finished then return end
        if not verified then return fail("rollback package checksum mismatch") end
        local payload=readFile(path); if not payload then return fail("rollback package disappeared") end
        stageRollback(payload,true)
      end)
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
