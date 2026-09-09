local function fakeFilesystem(seed)
  seed=seed or {}
  local fs={files={},dirs={},links={},readErrors=seed.readErrors or {}}
  for path in pairs(seed.dirs or {}) do fs.dirs[path]=true end
  for path,value in pairs(seed.files or {}) do fs.files[path]=value end
  for path,value in pairs(seed.links or {}) do fs.links[path]=value end
  local function parent(path) return path:match("^(.*)/[^/]+$") end
  local fakeLfs={}
  function fakeLfs.symlinkattributes(path,key)
    local mode=fs.links[path] and "link" or (fs.dirs[path] and "directory" or (fs.files[path]~=nil and "file" or nil))
    if key=="mode" then return mode end
    return mode and {mode=mode} or nil
  end
  function fakeLfs.mkdir(path)
    local base=parent(path)
    if base and not fs.dirs[base] then return nil,"parent missing" end
    if fs.files[path]~=nil or fs.links[path] then return nil,"occupied" end
    fs.dirs[path]=true; return true
  end
  function fakeLfs.dir(path)
    if not fs.dirs[path] then error("not a directory") end
    local found={['.']=true,['..']=true}; local prefix=path.."/"
    local function collect(entries)
      for candidate in pairs(entries) do
        if candidate:sub(1,#prefix)==prefix then
          local rest=candidate:sub(#prefix+1); local name=rest:match("^([^/]+)")
          if name then found[name]=true end
        end
      end
    end
    collect(fs.files); collect(fs.dirs); collect(fs.links)
    local names={}; for name in pairs(found) do names[#names+1]=name end; table.sort(names)
    local index=0; return function() index=index+1; return names[index] end
  end
  local fakeIo={}
  function fakeIo.open(path,mode)
    if mode=="rb" then
      local value=fs.files[path]; if value==nil then return nil,"missing" end
      local offset=1
      return {
        read=function(_,amount)
          if fs.readErrors[path] then return nil,fs.readErrors[path] end
          if amount=="*a" then local result=value:sub(offset); offset=#value+1; return result end
          if offset>#value then return nil end
          local result=value:sub(offset,offset+amount-1); offset=offset+#result; return result
        end,
        close=function() return true end,
      }
    end
    if mode=="wb" then
      local chunks={}
      return {
        write=function(_,value) chunks[#chunks+1]=value; return true end,
        close=function() fs.files[path]=table.concat(chunks); return true end,
      }
    end
    return nil,"unsupported mode"
  end
  local fakeOs={
    date=function(pattern) if pattern and pattern:sub(1,1)=="!" then return "2026-09-09T00:00:00Z" end; return "20260909-000000" end,
    time=function() return 1788900000 end,
  }
  function fakeOs.remove(path)
    if fs.files[path]~=nil or fs.links[path] then fs.files[path]=nil; fs.links[path]=nil; return true end
    return nil,"missing"
  end
  function fakeOs.rename(source,destination)
    if fs.files[source]==nil or fs.files[destination]~=nil or fs.dirs[destination] or fs.links[destination] then return nil,"rename failed" end
    fs.files[destination]=fs.files[source]; fs.files[source]=nil; return true
  end
  return fs,fakeLfs,fakeIo,fakeOs
end

local function loadBridge(seed)
  local keys={'lfs','io','os','tempAlias','killAlias','tempTimer','expandAlias','getMudletHomeDir','uninstallPackage','DGHUD','DGHUDMigration','DGHUD_MIGRATION_TEST_MODE','cecho'}
  local saved={}
  for _,key in ipairs(keys) do saved[#saved+1]={key=key,value=rawget(_G,key)} end
  local fs,fakeLfs,fakeIo,fakeOs=fakeFilesystem(seed)
  lfs=fakeLfs; io=fakeIo; os=fakeOs; tempAlias=function() return 91 end; killAlias=function() end; cecho=function() end
  getMudletHomeDir=function() return (seed and seed.home) or '/profile' end
  DGHUD_MIGRATION_TEST_MODE=true; DGHUDMigration=nil; DGHUD=nil
  dofile("src/migration_bridge.lua")
  local bridge=DGHUDMigration
  local function restore() for _,item in ipairs(saved) do _G[item.key]=item.value end end
  return bridge,fs,restore
end

local function withBridge(seed,callback)
  local bridge,fs,restore=loadBridge(seed)
  local ok,err=pcall(callback,bridge,fs)
  restore()
  if not ok then error(err,0) end
end

local marker='/profile/DGHUDData/.dghud-migration/state-v0.3.15.txt'
local conflicts='/profile/DGHUDData/.dghud-migration/conflicts/20260909-000000'

test("safe upgrade copies and verifies nested mutable data but excludes package resources",function()
  withBridge({
    dirs={['/profile']=true,['/profile/DragonsGateHUD']=true,['/profile/DragonsGateHUD/map-collections']=true},
    files={
      ['/profile/DragonsGateHUD/DragonsGateHUD.xml']='package',
      ['/profile/DragonsGateHUD/config.lua']='package config',
      ['/profile/DragonsGateHUD/mapper-settings.lua']='return {enabled=true}',
      ['/profile/DragonsGateHUD/map-collections/collections.json']='{"active":"mine"}',
      ['/profile/DragonsGateHUD/map-collections/mine.dat']=string.rep('map',30000),
    },
  },function(bridge,fs)
    local result,err=bridge.migrate('/profile'); assert(result,err)
    eq(result.files,3); eq(fs.files['/profile/DGHUDData/mapper-settings.lua'],'return {enabled=true}')
    eq(fs.files['/profile/DGHUDData/map-collections/mine.dat'],string.rep('map',30000))
    eq(fs.files['/profile/DGHUDData/DragonsGateHUD.xml'],nil)
    assert(fs.files[marker]:find('state=prepared',1,true)); eq(bridge.migrationComplete('/profile'),false)
  end)
end)

test("legacy data wins a conflict while the prior persistent copy remains recoverable",function()
  withBridge({
    dirs={['/profile']=true,['/profile/DragonsGateHUD']=true,['/profile/DGHUDData']=true},
    files={
      ['/profile/DragonsGateHUD/update-settings.lua']='latest legacy',
      ['/profile/DGHUDData/update-settings.lua']='prior persistent',
    },
  },function(bridge,fs)
    local first,firstErr=bridge.migrate('/profile'); assert(first,firstErr); eq(first.conflicts,1)
    eq(fs.files['/profile/DGHUDData/update-settings.lua'],'latest legacy')
    eq(fs.files[conflicts..'/update-settings.lua'],'prior persistent')
    local second,secondErr=bridge.migrate('/profile'); assert(second,secondErr)
    eq(second.files,0); eq(second.conflicts,0); eq(second.skipped,1)
    eq(fs.files[conflicts..'/update-settings.lua.previous-1'],nil)
  end)
end)

test("safe upgrade rejects linked entries and never starts the update after failure",function()
  withBridge({dirs={['/profile']=true,['/profile/DragonsGateHUD']=true},links={['/profile/DragonsGateHUD/maps']='/outside'}},function(bridge)
    local updates=0; DGHUD={updater={update=function() updates=updates+1 end}}; uninstallPackage=function() return true end
    local result=bridge.run()
    eq(result,nil); eq(updates,0)
  end)
end)

test("only a committed migration marker prevents repeated automatic upgrade work",function()
  withBridge({
    dirs={['/profile']=true,['/profile/DGHUDData']=true,['/profile/DGHUDData/.dghud-migration']=true},
    files={[marker]='version=1.1.0\nstate=prepared\nupdated=2026-09-09T00:00:00Z\nconflict_stamp=none\n'},
  },function(bridge,fs)
    eq(bridge.migrationComplete('/profile'),false)
    fs.files[marker]='version=1.1.0\nstate=committed\nupdated=2026-09-09T00:00:00Z\nconflict_stamp=none\n'
    eq(bridge.migrationComplete('/profile'),true); eq(bridge.migrationComplete('/another-profile'),false)
  end)
end)

test("profiles without legacy data remain incomplete until explicitly committed",function()
  withBridge({dirs={['/profile']=true}},function(bridge,fs)
    local result,err=bridge.migrate('/profile'); assert(result,err); assert(fs.files[marker]:find('state=prepared',1,true)); eq(bridge.migrationComplete('/profile'),false)
    result,err=bridge.migrate('/profile','committed'); assert(result,err); eq(bridge.migrationComplete('/profile'),true)
  end)
end)

test("safe upgrade rejects explicit read errors instead of treating them as EOF",function()
  withBridge({
    dirs={['/profile']=true,['/profile/DragonsGateHUD']=true},
    files={['/profile/DragonsGateHUD/maps.dat']='important'},
    readErrors={['/profile/DragonsGateHUD/maps.dat']='disk read failed'},
  },function(bridge)
    local result,err=bridge.migrate('/profile'); eq(result,nil); assert(err:find('disk read failed',1,true))
  end)
end)

test("migration staging never deletes a preexisting similarly named file",function()
  withBridge({
    dirs={['/profile']=true,['/profile/DragonsGateHUD']=true,['/profile/DGHUDData']=true},
    files={
      ['/profile/DragonsGateHUD/maps.dat']='map data',
      ['/profile/DGHUDData/maps.dat.dghud-tmp-1']='unrelated data',
    },
  },function(bridge,fs)
    local result,err=bridge.migrate('/profile'); assert(result,err)
    eq(fs.files['/profile/DGHUDData/maps.dat'],'map data')
    eq(fs.files['/profile/DGHUDData/maps.dat.dghud-tmp-1'],'unrelated data')
  end)
end)

test("Windows trailing separators normalize to the same profile root",function()
  local windowsMarker='C:/profile/DGHUDData/.dghud-migration/state-v0.3.15.txt'
  withBridge({home='C:/profile',dirs={['C:/profile']=true}},function(bridge,fs)
    local result,err=bridge.migrate([[C:/profile\]],'committed'); assert(result,err)
    assert(fs.files[windowsMarker]); eq(bridge.migrationComplete([[C:/profile\]]),true)
  end)
end)

test("final uninstall-boundary sync captures late legacy writes before committing",function()
  withBridge({
    dirs={['/profile']=true,['/profile/DragonsGateHUD']=true},
    files={['/profile/DragonsGateHUD/maps.dat']='early map'},
  },function(bridge,fs)
    local removals=0
    local completion
    uninstallPackage=function(name)
      eq(name,'DragonsGateHUD'); removals=removals+1
      eq(fs.files['/profile/DGHUDData/maps.dat'],'late map')
      fs.files['/profile/DragonsGateHUD/maps.dat']=nil; fs.dirs['/profile/DragonsGateHUD']=nil
      return true
    end
    local updater={update=function(_,done) completion=done; return true end}
    DGHUD={settings={version='0.3.15'},updater=updater,healthCheck=function() return true end}
    eq(bridge.run(),true); eq(bridge.running,true); eq(removals,0)
    fs.files['/profile/DragonsGateHUD/maps.dat']='late map'
    eq(uninstallPackage('DragonsGateHUD'),true)
    DGHUD={settings={version='0.3.17'},healthCheck=function() return true end}; completion(true)
    eq(bridge.running,false); eq(removals,1); eq(fs.files['/profile/DGHUDData/maps.dat'],'late map')
    eq(fs.files[conflicts..'/maps.dat'],'early map'); eq(bridge.migrationComplete('/profile'),true)
    assert(fs.files[marker]:find('state=committed',1,true))
  end)
end)

test("every busy uninstall retry re-syncs newer legacy data",function()
  withBridge({
    dirs={['/profile']=true,['/profile/DragonsGateHUD']=true},
    files={['/profile/DragonsGateHUD/maps.dat']='initial'},
  },function(bridge,fs)
    local attempts=0; local completion
    uninstallPackage=function()
      attempts=attempts+1
      if attempts==1 then return false end
      fs.files['/profile/DragonsGateHUD/maps.dat']=nil; fs.dirs['/profile/DragonsGateHUD']=nil; return true
    end
    DGHUD={settings={version='0.3.15'},healthCheck=function() return true end,updater={update=function(_,done) completion=done; return true end}}
    assert(bridge.run())
    fs.files['/profile/DragonsGateHUD/maps.dat']='after first download'
    eq(uninstallPackage('DragonsGateHUD'),false); eq(fs.files['/profile/DGHUDData/maps.dat'],'after first download')
    fs.files['/profile/DragonsGateHUD/maps.dat']='last possible write'
    eq(uninstallPackage('DragonsGateHUD'),true); eq(fs.files['/profile/DGHUDData/maps.dat'],'last possible write')
    DGHUD={settings={version='0.3.17'},healthCheck=function() return true end}; completion(true)
    eq(attempts,2); eq(bridge.migrationComplete('/profile'),true)
  end)
end)

test("failed activation leaves migration retryable and restores uninstall function",function()
  withBridge({
    dirs={['/profile']=true,['/profile/DragonsGateHUD']=true},
    files={['/profile/DragonsGateHUD/maps.dat']='map'},
  },function(bridge,fs)
    local baseUninstall=function() return true end; uninstallPackage=baseUninstall
    DGHUD={settings={version='0.3.15'},healthCheck=function() return true end,updater={update=function(_,done) done(nil,'install failed'); return true end}}
    eq(bridge.run(),true); eq(uninstallPackage,baseUninstall); eq(bridge.migrationComplete('/profile'),false)
    assert(fs.files[marker]:find('state=failed',1,true))
  end)
end)
