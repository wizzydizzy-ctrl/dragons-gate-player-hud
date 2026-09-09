local previous=rawget(_G,"DGHUDMigration")
local Bridge={version="1.1.0",running=false}
local packageFiles={['DragonsGateHUD.xml']=true,['DGHUDRuntime.lua']=true,['config.lua']=true}

local function announce(color,message)
  if type(cecho)=="function" then cecho("\n<"..color..">[DGHUD Safe Upgrade]<reset> "..tostring(message).."\n") end
end

local function normalizeHome(home)
  return tostring(home or (type(getMudletHomeDir)=="function" and getMudletHomeDir()) or ""):gsub("[/\\\\]+$","")
end

local function nodeMode(path)
  if not lfs or type(lfs.symlinkattributes)~="function" then return nil,"safe filesystem inspection is unavailable" end
  local ok,value,message,code=pcall(lfs.symlinkattributes,path,"mode")
  if not ok then return nil,tostring(value) end
  if value==nil and message then
    local lower=tostring(message):lower()
    if tonumber(code)~=2 and not lower:find("no such file",1,true) and not lower:find("cannot find the file",1,true) then return nil,tostring(message) end
  end
  return value
end

local function ensureDirectory(path)
  local mode,modeErr=nodeMode(path); if modeErr then return nil,modeErr end
  if mode=="directory" then return true end
  if mode~=nil then return nil,"path is not a directory: "..path end
  local made,makeErr=lfs.mkdir(path)
  if made then return true end
  local retry,retryErr=nodeMode(path)
  if retry=="directory" then return true end
  return nil,tostring(makeErr or retryErr or "could not create directory")
end

local temporaryCounter=0
local function uniqueTemporary(destination)
  for _=1,1000 do
    temporaryCounter=temporaryCounter+1
    local candidate=destination..".dghud-tmp-"..temporaryCounter
    local mode,modeErr=nodeMode(candidate); if modeErr then return nil,modeErr end
    if mode==nil then return candidate end
  end
  return nil,"could not reserve a unique migration staging path"
end

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

local function stageVerified(source,destination)
  local input,inputErr=io.open(source,"rb"); if not input then return nil,nil,tostring(inputErr) end
  local temporary,tempErr=uniqueTemporary(destination); if not temporary then input:close(); return nil,nil,tempErr end
  local output,outputErr=io.open(temporary,"wb"); if not output then input:close(); return nil,nil,tostring(outputErr) end
  local bytes=0
  while true do
    local chunk,readErr,readOK=readChunk(input)
    if not readOK then input:close(); output:close(); os.remove(temporary); return nil,nil,readErr end
    if chunk==nil then break end
    local writeOK,wrote,writeErr=pcall(output.write,output,chunk)
    if not writeOK or not wrote then input:close(); output:close(); os.remove(temporary); return nil,nil,tostring((not writeOK and wrote) or writeErr or "could not write migrated data") end
    bytes=bytes+#chunk
  end
  input:close(); local closeOK,closed,closeErr=pcall(output.close,output)
  if not closeOK or closed==nil then os.remove(temporary); return nil,nil,tostring((not closeOK and closed) or closeErr or "could not close migrated data") end
  local same,verifyErr=filesEqual(source,temporary)
  if not same then os.remove(temporary); return nil,nil,verifyErr or "copied data verification failed" end
  return temporary,bytes
end

local function installStaged(temporary,destination)
  local renameOK,installed,installErr=pcall(os.rename,temporary,destination)
  if not renameOK or not installed then return nil,tostring((not renameOK and installed) or installErr or "could not finalize migrated data") end
  return true
end

local function copyVerified(source,destination)
  local temporary,bytes,stageErr=stageVerified(source,destination); if not temporary then return nil,stageErr end
  local installed,installErr=installStaged(temporary,destination)
  if not installed then os.remove(temporary); return nil,installErr end
  return bytes
end

local function safeName(name)
  return type(name)=="string" and name~="" and name~="." and name~=".." and not name:find("[/\\]") and not name:find("[%z\1-\31]")
end

local function readMarker(path)
  local file=io.open(path,"rb"); if not file then return nil end
  local ok,raw,readErr=pcall(file.read,file,"*a"); file:close()
  if not ok or raw==nil then return nil,tostring(ok and readErr or raw) end
  local values={}
  for key,value in tostring(raw):gmatch("([%w_]+)=([^\r\n]+)") do values[key]=value end
  return values
end

local function writeMarker(path,state,stats,stamp)
  local temporary,tempErr=uniqueTemporary(path); if not temporary then return nil,tempErr end
  local file,openErr=io.open(temporary,"wb"); if not file then return nil,tostring(openErr) end
  local body=table.concat({
    "version="..Bridge.version,
    "state="..tostring(state),
    "updated="..os.date("!%Y-%m-%dT%H:%M:%SZ"),
    "conflict_stamp="..tostring(stamp or "none"),
    "files="..tostring(stats.files or 0),
    "bytes="..tostring(stats.bytes or 0),
    "conflicts="..tostring(stats.conflicts or 0),
  },"\n").."\n"
  local writeOK,wrote,writeErr=pcall(file.write,file,body); local closeOK,closed,closeErr=pcall(file.close,file)
  if not writeOK or not wrote or not closeOK or closed==nil then os.remove(temporary); return nil,tostring((not writeOK and wrote) or writeErr or (not closeOK and closed) or closeErr or "could not write migration state") end
  local oldMode,modeErr=nodeMode(path); if modeErr then os.remove(temporary); return nil,modeErr end
  if oldMode~=nil and oldMode~="file" then os.remove(temporary); return nil,"migration state path has the wrong type" end
  if oldMode=="file" then
    local removed,removeErr=os.remove(path); if not removed then os.remove(temporary); return nil,tostring(removeErr or "could not replace migration state") end
  end
  local installed,installErr=installStaged(temporary,path)
  if not installed then os.remove(temporary); return nil,installErr end
  return true
end

local function versionAtLeast(actual,required)
  local function tuple(value) local a,b,c=tostring(value or ""):match("^(%d+)%.(%d+)%.(%d+)$"); if not a then return nil end; return tonumber(a),tonumber(b),tonumber(c) end
  local aa,ab,ac=tuple(actual); local ra,rb,rc=tuple(required); if not aa or not ra then return false end
  if aa~=ra then return aa>ra end; if ab~=rb then return ab>rb end; return ac>=rc
end

local function paths(home)
  local target=home.."/DGHUDData"; local metadata=target.."/.dghud-migration"
  return home.."/DragonsGateHUD",target,metadata,metadata.."/state-v0.3.15.txt"
end

function Bridge.migrationComplete(home)
  home=normalizeHome(home); if home=="" then return false end
  local _,_,_,marker=paths(home)
  local mode=nodeMode(marker); if mode~="file" then return false end
  local values=readMarker(marker)
  return type(values)=="table" and values.version==Bridge.version and values.state=="committed" and values.updated~=nil
end

function Bridge.migrate(home,state)
  home=normalizeHome(home); if home=="" then return nil,"Mudlet profile directory is unavailable" end
  state=state or "prepared"
  if state~="prepared" and state~="committed" and state~="failed" then return nil,"invalid migration state" end
  local legacy,target,metadata,marker=paths(home)
  local made,makeErr=ensureDirectory(target); if not made then return nil,"could not create DGHUDData: "..tostring(makeErr) end
  made,makeErr=ensureDirectory(metadata); if not made then return nil,"could not create migration metadata: "..tostring(makeErr) end
  local legacyMode,legacyErr=nodeMode(legacy); if legacyErr then return nil,legacyErr end
  local stats={files=0,bytes=0,conflicts=0,skipped=0,target=target,state=state}
  local prior=readMarker(marker); local stamp=type(prior)=="table" and prior.conflict_stamp or nil
  if legacyMode==nil then
    local marked,markerErr=writeMarker(marker,state,stats,stamp or "none")
    if not marked then return nil,"could not record migration state: "..tostring(markerErr) end
    return stats
  end
  if legacyMode~="directory" then return nil,"legacy HUD data path is not a directory" end

  local conflictRoot
  local function ensureConflictRoot()
    if not stamp or stamp=="none" then stamp=os.date("%Y%m%d-%H%M%S") end
    local base=metadata.."/conflicts"; local ok,err=ensureDirectory(base); if not ok then return nil,err end
    conflictRoot=base.."/"..stamp; return ensureDirectory(conflictRoot)
  end
  local function ensureRelativeParent(root,relative)
    local parent=relative:match("^(.*)/[^/]+$"); if not parent then return true end
    local current=root
    for name in parent:gmatch("[^/]+") do
      if not safeName(name) then return nil,"unsafe path component in legacy data" end
      current=current.."/"..name; local ok,err=ensureDirectory(current); if not ok then return nil,err end
    end
    return true
  end
  local function backupCurrent(relative,current)
    local ok,err=ensureConflictRoot(); if not ok then return nil,nil,err end
    ok,err=ensureRelativeParent(conflictRoot,relative); if not ok then return nil,nil,err end
    local base=conflictRoot.."/"..relative
    for suffix=0,999 do
      local candidate=suffix==0 and base or (base..".previous-"..suffix)
      local mode,modeErr=nodeMode(candidate); if modeErr then return nil,nil,modeErr end
      if mode==nil then
        local copied,copyErr=copyVerified(current,candidate); if not copied then return nil,nil,copyErr end
        return candidate,false
      end
      if mode=="file" then
        local same,sameErr=filesEqual(current,candidate); if sameErr then return nil,nil,sameErr end
        if same then return candidate,true end
      else return nil,nil,"migration conflict backup has the wrong type: "..relative end
    end
    return nil,nil,"too many migration conflict backups for "..relative
  end
  local function replaceWithLegacy(source,destination,relative)
    local staged,bytes,stageErr=stageVerified(source,destination); if not staged then return nil,stageErr end
    local backup,alreadyBackedUp,backupErr=backupCurrent(relative,destination)
    if not backup then os.remove(staged); return nil,backupErr end
    local removed,removeErr=os.remove(destination)
    if not removed then os.remove(staged); return nil,tostring(removeErr or "could not replace persistent data") end
    local installed,installErr=installStaged(staged,destination)
    if not installed then
      os.remove(staged)
      local restored,restoreErr=copyVerified(backup,destination)
      return nil,"could not activate migrated data: "..tostring(installErr)..(restored and "; prior data restored" or "; prior data restore failed: "..tostring(restoreErr))
    end
    stats.conflicts=stats.conflicts+1
    if alreadyBackedUp then stats.skipped=stats.skipped+1 end
    stats.files=stats.files+1; stats.bytes=stats.bytes+bytes
    return true
  end

  local copyNode
  copyNode=function(source,destination,relative,depth)
    if depth>16 then return nil,"legacy data nesting exceeds the safety limit" end
    local sourceMode,sourceErr=nodeMode(source); if sourceErr then return nil,sourceErr end
    if sourceMode~="file" and sourceMode~="directory" then return nil,"unsupported or linked legacy entry: "..relative end
    local destinationMode,destinationErr=nodeMode(destination); if destinationErr then return nil,destinationErr end
    if sourceMode=="file" then
      if destinationMode==nil then
        local copied,copyErr=copyVerified(source,destination); if not copied then return nil,copyErr end
        stats.files=stats.files+1; stats.bytes=stats.bytes+copied; return true
      end
      if destinationMode~="file" then return nil,"migration destination has the wrong type: "..relative end
      local same,sameErr=filesEqual(source,destination); if sameErr then return nil,sameErr end
      if same then stats.skipped=stats.skipped+1; return true end
      return replaceWithLegacy(source,destination,relative)
    end
    if destinationMode==nil then local ok,err=ensureDirectory(destination); if not ok then return nil,err end
    elseif destinationMode~="directory" then return nil,"migration directory has the wrong type: "..relative end
    local opened,iterator,iteratorState=pcall(lfs.dir,source)
    if not opened or type(iterator)~="function" then return nil,"could not inspect legacy directory: "..relative end
    for name in iterator,iteratorState do
      if name~="." and name~=".." then
        if not safeName(name) then return nil,"unsafe name in legacy data" end
        local childRelative=relative=="" and name or (relative.."/"..name)
        local copied,copyErr=copyNode(source.."/"..name,destination.."/"..name,childRelative,depth+1)
        if not copied then return nil,copyErr end
      end
    end
    return true
  end

  local opened,iterator,iteratorState=pcall(lfs.dir,legacy)
  if not opened or type(iterator)~="function" then return nil,"could not inspect legacy HUD data" end
  for name in iterator,iteratorState do
    if name~="." and name~=".." and not packageFiles[name] then
      if not safeName(name) then return nil,"unsafe name in legacy HUD data" end
      local copied,copyErr=copyNode(legacy.."/"..name,target.."/"..name,name,1)
      if not copied then return nil,tostring(name)..": "..tostring(copyErr) end
    end
  end
  local marked,markerErr=writeMarker(marker,state,stats,stamp or "none")
  if not marked then return nil,"could not record migration state: "..tostring(markerErr) end
  stats.conflict_stamp=stamp or "none"
  return stats
end

local function runtimeHealthy()
  local hud=rawget(_G,"DGHUD")
  if type(hud)~="table" or type(hud.settings)~="table" or not versionAtLeast(hud.settings.version,"0.3.16") then return nil,"the new HUD runtime is not active" end
  if type(hud.healthCheck)~="function" then return nil,"the new HUD health check is unavailable" end
  local ok,healthy,why=pcall(hud.healthCheck)
  if not ok or healthy~=true then return nil,tostring(ok and why or healthy or "the new HUD is not healthy") end
  return true
end

function Bridge.run()
  if Bridge.running then announce("yellow","Safe upgrade is already running."); return nil,"already running" end
  local home=normalizeHome(); if home=="" then announce("red","Mudlet profile directory is unavailable."); return nil,"profile directory unavailable" end
  Bridge.running=true; Bridge.finalErrorAnnounced=false
  announce("gold","Preserving personal HUD data before update…")
  local migrateOK,result,why=pcall(Bridge.migrate,home,"prepared")
  if not migrateOK or not result then
    Bridge.running=false; announce("red","Data preservation failed; the HUD was not updated: "..tostring(migrateOK and why or result)); return nil,why or result
  end
  Bridge.lastStats=result
  announce("green",string.format("Verified %d files (%d bytes); %d prior copies preserved.",result.files,result.bytes,result.conflicts))

  local hud=rawget(_G,"DGHUD"); local updater=type(hud)=="table" and hud.updater or nil
  local originalUninstall=rawget(_G,"uninstallPackage")
  if type(updater)~="table" or type(updater.update)~="function" or type(originalUninstall)~="function" then
    Bridge.running=false; announce("yellow","Data is safe, but the running HUD updater is unavailable. Reinstall the main HUD or use dghud recover, then run this bridge again."); return nil,"HUD updater unavailable"
  end

  local wrappedUninstall
  local callbackFinished=false
  local function restoreUninstall()
    if rawget(_G,"uninstallPackage")==wrappedUninstall then _G.uninstallPackage=originalUninstall end
  end
  wrappedUninstall=function(name,...)
    if name~="DragonsGateHUD" then return originalUninstall(name,...) end
    local finalOK,finalResult,finalWhy=pcall(Bridge.migrate,home,"prepared")
    if not finalOK or not finalResult then
      Bridge.lastError=tostring(finalOK and finalWhy or finalResult)
      if not Bridge.finalErrorAnnounced then Bridge.finalErrorAnnounced=true; announce("red","Final data sync failed; package removal was blocked: "..Bridge.lastError) end
      return false
    end
    Bridge.lastStats=finalResult
    return originalUninstall(name,...)
  end
  _G.uninstallPackage=wrappedUninstall

  local function finished(updated,message)
    if callbackFinished then return end; callbackFinished=true; restoreUninstall(); Bridge.running=false
    local healthy,healthErr=runtimeHealthy()
    if healthy then
      local committed,commitErr=Bridge.migrate(home,"committed")
      if committed then announce("green","Upgrade completed and persistent data was verified."); return end
      announce("red","The HUD updated, but migration completion could not be recorded: "..tostring(commitErr)); return
    end
    local failedStats=Bridge.lastStats or result
    local _,_,metadata,marker=paths(home); ensureDirectory(metadata); writeMarker(marker,"failed",failedStats,failedStats.conflict_stamp)
    announce("red","The update did not activate a healthy HUD. Personal data remains preserved: "..tostring(message or healthErr))
  end

  announce("gold","Starting the verified HUD update now.")
  local callOK,started,startErr=pcall(updater.update,updater,finished)
  if not callOK then finished(nil,started); return nil,started end
  if started==nil and not callbackFinished then finished(nil,startErr or "update did not start"); return nil,startErr end
  return true
end

local aliasOK,alias=pcall(function() return type(tempAlias)=="function" and tempAlias("^dghud safe update$",Bridge.run) or nil end)
if aliasOK and type(alias)=="number" and alias>0 then Bridge.alias=alias end
DGHUDMigration=Bridge
if type(previous)=="table" and type(previous.alias)=="number" and previous.alias~=Bridge.alias and type(killAlias)=="function" then pcall(killAlias,previous.alias) end
if rawget(_G,"DGHUD_MIGRATION_TEST_MODE")~=true and not Bridge.migrationComplete() then
  if type(tempTimer)=="function" then tempTimer(0,Bridge.run) else Bridge.run() end
end
