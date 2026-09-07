local View=require("view"); local Storage=require("chat_storage"); local MapAdapter=require("map_adapter"); local SHA256=require("sha256")
local Adapter={}; Adapter.__index=Adapter
function Adapter.updateBase(home) return home.."/DGHUDUpdater" end
function Adapter.updateArchivePath(home) return Adapter.updateBase(home).."/staging/DragonsGateHUD.mpackage" end
function Adapter.verifyArchive(payload,digest) return type(payload)=="string" and type(digest)=="string" and SHA256.hex(payload)==digest end
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
function Adapter:saveMapDiagnostic(payload)
  local base=getMudletHomeDir().."/DragonsGateHUD"; lfs.mkdir(base); local directory=base.."/diagnostics"; lfs.mkdir(directory)
  local path=directory.."/mapper-"..os.date("%Y%m%d-%H%M%S")..".txt"; local file,err=io.open(path,"wb"); if not file then return nil,err end
  local ok,writeErr=file:write(tostring(payload or "")); if not ok then file:close(); return nil,writeErr end; file:close(); return path
end
function Adapter:saveFailureReport(report)
  local ok,payload=pcall(yajl.to_string,report); if not ok or type(payload)~="string" then return nil,"could not encode failure report" end; if #payload>16000 then return nil,"failure report exceeds the safety limit" end
  local base=getMudletHomeDir().."/DragonsGateHUD"; lfs.mkdir(base); local directory=base.."/diagnostics"; lfs.mkdir(directory); local path=directory.."/failure-"..os.date("%Y%m%d-%H%M%S")..".json"; local file,err=io.open(path,"wb"); if not file then return nil,err end
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
  local base=getMudletHomeDir().."/DragonsGateHUD"; lfs.mkdir(base); local directory=base.."/diagnostics"; lfs.mkdir(directory)
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
  local base=getMudletHomeDir().."/DragonsGateHUD"; local directory=base.."/maps"
  for _,path in ipairs({base,directory}) do if lfs.attributes(path,"mode")~="directory" then local ok,err=lfs.mkdir(path); if not ok and lfs.attributes(path,"mode")~="directory" then return nil,"could not create map export directory "..path..": "..tostring(err) end end end
  return directory
end
function Adapter:mapCollectionDirectory()
  local base=getMudletHomeDir().."/DragonsGateHUD"; local directory=base.."/map-collections"
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
  return {path=path,sha256=SHA256.hex(payload),room_count=roomCount,bytes=#payload}
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
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadDone",function(_,actual) if actual~=path then return end; local raw,readErr=libraryRead(path,20000000); if not raw then return finish(nil,readErr) end; if #raw~=entry.bytes then return finish(nil,"downloaded map size does not match the catalog") end; if require("sha256").hex(raw)~=entry.sha256 then return finish(nil,"downloaded map checksum does not match the catalog") end; local ok,value=pcall(yajl.to_value,raw); if not ok then return finish(nil,"downloaded map JSON is invalid") end; finish(value) end)
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
  else cecho(string.format("\n<gold>[DGHUD]<reset> Installed version: %s  Latest version: %s\n",tostring(installed),tostring(latest))) end
end
function Adapter:openSettings() cecho("\n<gold>[DGHUD]<reset> Settings: "..getMudletHomeDir().."/DragonsGateHUD/settings.lua\n") end
local function readFile(path) local f=io.open(path,"rb"); if not f then return nil end; local data=f:read("*a"); f:close(); return data end
local function writeFile(path,data) local f=assert(io.open(path,"wb")); f:write(data); f:close() end
local function hasPackage(name) for _,value in ipairs(getPackages() or {}) do if value==name then return true end end return false end
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
      os.remove(manifestPath); downloadFile(manifestPath,Adapter.versionManifestUrl(github,version)); return
    end
    if path~=manifestPath then return end
    local raw=readFile(path); if not raw or #raw>(policy.manifest_limit or 65536) then finish(nil,"manifest is missing or too large"); return end
    local ok,manifest=pcall(yajl.to_value,raw); if not ok then finish(nil,"manifest JSON is invalid"); return end
    local valid,why=updater:validateManifest(manifest); if not valid then finish(nil,why); return end
    finish(manifest,nil,raw)
  end)
  updateNonce=updateNonce+1; os.remove(releasePath)
  downloadFile(releasePath,Adapter.latestReleaseUrl(github))
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
        if valid and exactInstalled(cachedManifest) and #cached<=(policy.package_limit or 10485760) and Adapter.verifyArchive(cached,cachedManifest.sha256) then rollbackManifest=cachedManifest; return stageRollback(cached,true) end
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
      if hasPackage(name) then local removed=uninstallPackage(name); if removed==nil then replaceDone(nil,"could not remove existing HUD package"); return end end
      schedule(0.10,function()
        local installed=installPackage(packagePath)
        if installed==nil then replaceDone(nil,"could not install HUD package"); return end
        -- Mudlet defers execution of scripts from a package installed by a
        -- callback until the callback chain has unwound. Waiting for the new
        -- DGHUD global here therefore deadlocks the self-updater: the new entry
        -- script cannot run until replaceDone returns. The archive checksum and
        -- canonical package registration are the synchronous transaction checks;
        -- the package's normal startup performs its strict runtime health check.
        replaceDone(true)
      end)
    end
    -- During self-replacement the old package remains the executing callback.
    -- A runtime probe here would inspect the shutting-down old controller. The
    -- new package performs strict health checks once Mudlet activates its scripts.
    self.healthCheck=function() return true end
    self.rollbackAsync=function(_,name,rollbackDone)
      local rollbackPayload=readFile(previousPath)
      if name~="DragonsGateHUD" or not rollbackPayload then rollbackDone(nil,"no rollback package available"); return end
      if not Adapter.verifyArchive(rollbackPayload,previousDigest) then rollbackDone(nil,"rollback package checksum mismatch"); return end
      if DGHUD then DGHUD._update_reinstall_pending=true end
      if hasPackage(name) then uninstallPackage(name) end
      schedule(0.10,function()
        -- Mudlet derives the installed package identity from the archive filename.
        -- Installing previous.mpackage registers a package named "previous" and
        -- leaves DragonsGateHUD missing, so stage the verified bytes under the
        -- canonical package filename before restoring.
        writeFile(rollbackInstallPath,rollbackPayload)
        local restored=installPackage(rollbackInstallPath)
        schedule(0.50,function() rollbackDone(restored~=nil,restored==nil and "could not restore rollback package" or nil) end)
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
      if cached and #cached<=(policy.package_limit or 10485760) and Adapter.verifyArchive(cached,manifest.sha256) then stageRollback(cached,true)
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
