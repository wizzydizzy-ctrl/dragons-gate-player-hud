local Updater=require("updater"); local SHA=require("sha256"); local Adapter=require("mudlet_adapter")
local function releaseManifest(version)
  return {package="DragonsGateHUD",version=version,minimum_mudlet="5.0.0",archive_url="https://github.com/wizzydizzy-ctrl/dragons-gate-hud/releases/download/v"..version.."/DragonsGateHUD.mpackage",sha256=string.rep("a",64),archive_size=100}
end
local updateSettings={version="0.2.83",github={owner="wizzydizzy-ctrl",repository="dragons-gate-hud"},update={package_limit=1000}}
test("update staging lives outside the installed package directory",function()
  local base=Adapter.updateBase("/profile")
  eq(base,"/profile/DGHUDUpdater")
  eq(base:find("/DragonsGateHUD",1,true),nil)
end)
test("verified update archive retains the Mudlet package name",function()
  eq(Adapter.updateArchivePath("/profile"),"/profile/DGHUDUpdater/staging/DragonsGateHUD.mpackage")
  eq(Adapter.verifyArchive("prior",SHA.hex("prior")),true); eq(Adapter.verifyArchive("tampered",SHA.hex("prior")),false)
end)
test("stable manifest downloads use a unique cache-busting URL",function()
  local url=Adapter.manifestUrl({owner="wizzydizzy-ctrl",repository="dragons-gate-hud"},1788221000)
  eq(url,"https://github.com/wizzydizzy-ctrl/dragons-gate-hud/releases/latest/download/manifest.json?dghud=1788221000")
end)
test("character prompt detection accepts an echoed command but rejects account menu",function()
  eq(Adapter.characterPrompt(">dghud update"),true)
  eq(Adapter.characterPrompt("[199] 301/301 hp, 173/173 ftg >"),true)
  eq(Adapter.characterPrompt("[199] 301/301 hp, 173/173 ftg >inventory"),true)
  eq(Adapter.characterPrompt("Your selection? dghud update"),false)
end)
test("update lock rejects overlapping operations",function() local u=Updater.new({},{}); eq(u:acquire("update"),true); local ok,err=u:acquire("check"); eq(ok,nil); eq(err,"update already in progress"); u:release(); eq(u:acquire("check"),true) end)
test("download events correlate by exact owned path",function() local u=Updater.new({},{data_dir="/profile/DragonsGateHUD"}); u.expected_path="/profile/DragonsGateHUD/staging/package.mpackage"; eq(u:acceptDownload("/other/script/file"),false); eq(u:acceptDownload(u.expected_path),true) end)
test("archive checksum mismatch blocks replacement",function() local called=false; local u=Updater.new({replacePackage=function() called=true end},{}); local ok=u:installVerified("payload",string.rep("0",64)); eq(ok,nil); eq(called,false); eq(SHA.hex("payload")~=string.rep("0",64),true) end)
test("successful verified install requires health check",function() local calls=0; local u=Updater.new({replacePackage=function() calls=calls+1; return true end,healthCheck=function() return true end},{}); eq(u:installVerified("payload",SHA.hex("payload")),true); eq(calls,1) end)
test("async install verifies before replacement and completes after health check",function()
  local order={}
  local adapter={
    replacePackageAsync=function(_,payload,name,done)
      order[#order+1]="replace:"..name..":"..payload
      done(true)
    end,
    healthCheck=function() order[#order+1]="health"; return true end,
  }
  local result
  local u=Updater.new(adapter,{})
  eq(u:installVerifiedAsync("payload",SHA.hex("payload"),function(ok,err) result={ok,err} end),true)
  eq(order[1],"replace:DragonsGateHUD:payload")
  eq(order[2],"health")
  eq(result[1],true)
end)
test("successful in-session update refreshes command-backed character data",function()
  local refreshed=false
  local adapter={replacePackageAsync=function(_,_,_,done) done(true) end,healthCheck=function() return true end,refreshCharacterData=function() refreshed=true; return true end}
  local u=Updater.new(adapter,{}); u.refresh_after_install=true
  u:installVerifiedAsync("payload",SHA.hex("payload"),function() end)
  eq(refreshed,true)
end)
test("replacement failure attempts rollback before completing",function()
  local order={}; local result
  local adapter={replacePackageAsync=function(_,_,_,done) order[#order+1]="replace"; done(nil,"install failed") end,rollbackAsync=function(_,_,done) order[#order+1]="rollback"; done(true) end}
  Updater.new(adapter,{}):installVerifiedAsync("payload",SHA.hex("payload"),function(ok,err) result={ok,err}; order[#order+1]="done" end)
  eq(table.concat(order,","),"replace,rollback,done"); eq(result[1],nil); eq(result[2],"install failed")
end)
test("manifest compatibility blocks replacement on an older known Mudlet",function()
  local u=Updater.new({mudletVersion=function() return "4.17.2" end},updateSettings)
  local ok,err=u:validateManifest(releaseManifest("0.2.84")); eq(ok,nil); assert(err:find("older than required",1,true))
end)
test("post-install refresh joins the new controller startup sequence",function()
  local prior=_G.DGHUD; local entries=0; local forced=0
  _G.DGHUD={controller={character_entry_started=false,onCharacterEntry=function(self) entries=entries+1; self.character_entry_started=true; return true end,collector={restartRefresh=function() forced=forced+1; return true end}}}
  local ok,err=pcall(function() eq(Adapter.new():refreshCharacterData(),true); eq(Adapter.new():refreshCharacterData(),true) end)
  _G.DGHUD=prior; if not ok then error(err,0) end
  eq(entries,1); eq(forced,1)
end)
test("Mudlet activity detection survives asynchronous non-prompt output",function()
  local oldDGHUD,oldCurrent=DGHUD,getCurrentLine; DGHUD={controller={character_entry_started=true}}; getCurrentLine=function() return "The dark hound claws at you!" end
  local ok,err=pcall(function() eq(Adapter.new():isCharacterActive(),true) end); DGHUD,getCurrentLine=oldDGHUD,oldCurrent; if not ok then error(err,0) end
end)
test("Mudlet version adapter captures the API numeric tuple",function()
  local prior=_G.getMudletVersion; _G.getMudletVersion=function(mode) eq(mode,"table"); return 5,0,1 end
  local value=Adapter.new():mudletVersion(); _G.getMudletVersion=prior
  eq(value[1],5); eq(value[2],0); eq(value[3],1)
end)
local function replacementHarness(options,body)
  options=options or {}; local globalNames={"lfs","yajl","getMudletHomeDir","registerAnonymousEventHandler","killAnonymousEventHandler","tempTimer","killTimer","downloadFile","getPackages","uninstallPackage","installPackage","cecho","DGHUD","getMudletVersion"}
  globalNames[#globalNames+1]="getEpoch"
  local saved={}; for _,name in ipairs(globalNames) do saved[name]=_G[name] end
  local originalOpen=io.open; local h={files={},downloads={},handlers={},timers={},nextID=0,active=true,uninstalls=0,installs={},result=nil}
  local target=releaseManifest("0.2.84"); target.sha256=SHA.hex("new-package")
  local rollback=releaseManifest("0.2.83"); rollback.sha256=SHA.hex("old-package")
  h.manifests={target=target,rollback=rollback}
  local originalHex=SHA.hex
  local function restore() SHA.hex=originalHex; io.open=originalOpen; for _,name in ipairs(globalNames) do _G[name]=saved[name] end end
  local ok,err=pcall(function()
    h.hashCalls=0; SHA.hex=function(payload) h.hashCalls=h.hashCalls+1; return originalHex(payload) end
    io.open=function(path,mode)
      if mode=="rb" and h.files[path]==nil then return nil end
      return {read=function() return h.files[path] end,write=function(_,data) h.files[path]=data end,close=function() end}
    end
    lfs={mkdir=function() return true end}; getMudletHomeDir=function() return "/profile" end; getMudletVersion=nil
    yajl={to_value=function(raw) return assert(h.manifests[raw],"unexpected manifest payload") end}
    registerAnonymousEventHandler=function(name,fn) h.nextID=h.nextID+1; h.handlers[name]=fn; return h.nextID end
    killAnonymousEventHandler=function() end
    tempTimer=function(delay,fn) h.nextID=h.nextID+1; h.timers[h.nextID]={delay=delay,fn=fn}; return h.nextID end
    killTimer=function(id) h.timers[id]=nil end
    downloadFile=function(path,url) h.downloads[#h.downloads+1]={path=path,url=url}; return true end
    getPackages=function() return h.active and {"DragonsGateHUD"} or {} end
    uninstallPackage=function() h.uninstalls=h.uninstalls+1; h.active=false; return true end
    installPackage=function(path) h.installs[#h.installs+1]=path; if options.failTarget and path==Adapter.updateArchivePath("/profile") then return nil end; h.active=true; return true end
    h.messages={}; h.now=0; getEpoch=function() return h.now end
    cecho=function(message) h.messages[#h.messages+1]=message end; DGHUD={shutdown=function() end,healthCheck=function() return true end}
    function h:done(path,payload) self.files[path]=payload; self.handlers.sysDownloadDone(nil,path) end
    function h:error(url,message) self.handlers.sysDownloadError(nil,message or "download failed",url) end
    function h:run(delay) for id,timer in pairs(self.timers) do if timer.delay==delay then self.timers[id]=nil; timer.fn(); return true end end return false end
    h.adapter=Adapter.new(); h.updater=Updater.new(h.adapter,updateSettings); assert(h.updater:update(function(success,message) h.result={success,message} end,options.manifest,options.manifestRaw))
    body(h)
  end)
  restore(); if not ok then error(err,0) end
end
local function deliverTarget(h)
  h:done(h.downloads[1].path,"target")
  h:done(h.downloads[2].path,"new-package")
end
test("first updater-managed update bootstraps exact rollback before uninstall",function()
  replacementHarness({},function(h)
    deliverTarget(h); eq(h.uninstalls,0); eq(#h.downloads,3)
    assert(h.downloads[3].url:find("/releases/download/v0.2.83/manifest.json",1,true)); h.handlers.sysDownloadDone(nil,"/unowned/path"); h:error("https://unrelated.example/failure","ignore me"); eq(h.uninstalls,0)
    h:done(h.downloads[3].path,"rollback"); eq(h.uninstalls,0); eq(#h.downloads,4)
    h:done(h.downloads[4].path,"old-package"); eq(h.uninstalls,1); eq(DGHUD._update_reinstall_pending,true); eq(h.files["/profile/DGHUDUpdater/previous.mpackage"],"old-package")
    assert(h:run(.10)); assert(h:run(.50)); eq(h.result[1],true); eq(h.active,true); eq(h.hashCalls,2)
  end)
end)
test("rollback bootstrap timeout aborts before touching active package",function()
  replacementHarness({},function(h)
    deliverTarget(h); eq(h.result,nil); eq(h.uninstalls,0); assert(h:run(30))
    eq(h.result[1],nil); assert(h.result[2]:find("timed out",1,true)); eq(h.uninstalls,0); eq(h.active,true)
  end)
end)
test("failed first replacement restores checksum-verified bootstrapped package",function()
  replacementHarness({failTarget=true},function(h)
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h:done(h.downloads[4].path,"old-package")
    eq(h.uninstalls,1); assert(h:run(.10)); eq(h.active,false); assert(h:run(.10)); assert(h:run(.50))
    eq(h.active,true); eq(h.installs[#h.installs],"/profile/DGHUDUpdater/DragonsGateHUD.mpackage"); eq(h.files[h.installs[#h.installs]],"old-package"); eq(h.result[1],nil); assert(h.result[2]:find("could not install HUD package",1,true))
  end)
end)
test("startup check skips installation when current and continues startup",function()
  local order={}; local completed
  local adapter={checkLatestAsync=function(_,updater,done) order[#order+1]="check"; done(releaseManifest("0.2.83")) end}
  local u=Updater.new(adapter,updateSettings)
  eq(u:checkAtCharacterEntry(function(updated,err) completed={updated,err}; order[#order+1]="commands" end),true)
  eq(table.concat(order,","),"check,commands"); eq(completed[1],false); eq(completed[2],nil); eq(u.lock,nil)
end)
test("startup check updates before allowing startup commands",function()
  local order={}; local completed; local passedManifest; local passedRaw
  local adapter={
    checkLatestAsync=function(_,updater,done) order[#order+1]="check"; done(releaseManifest("0.2.84"),nil,"validated-raw") end,
    startUpdate=function(_,updater,done,manifest,raw) order[#order+1]="update"; passedManifest=manifest; passedRaw=raw; done(true); return true end,
    isCharacterActive=function() return true end,
  }
  local u=Updater.new(adapter,updateSettings)
  eq(u:checkAtCharacterEntry(function(updated,err) completed={updated,err}; order[#order+1]="commands" end),true)
  eq(table.concat(order,","),"check,update,commands"); eq(completed[1],true); eq(completed[2],nil); eq(u.lock,nil)
  eq(passedManifest.version,"0.2.84"); eq(passedRaw,"validated-raw")
end)
test("manual update fetches latest manifest exactly once and reports timed stages",function()
  replacementHarness({},function(h)
    eq(#h.downloads,1); assert(h.downloads[1].url:find("/releases/latest/download/manifest.json",1,true))
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h:done(h.downloads[4].path,"old-package")
    h.now=1.2; assert(h:run(.10)); h.now=1.8; assert(h:run(.50))
    eq(h.result[1],true)
    local output=table.concat(h.messages)
    assert(output:find("Checking",1,true)); assert(output:find("Downloading package",1,true)); assert(output:find("Preparing rollback",1,true)); assert(output:find("Installing",1,true)); assert(output:find("Completed",1,true)); assert(output:find("1.8s",1,true))
  end)
end)
test("startup update reuses its validated manifest without another manifest download",function()
  local manifest=releaseManifest("0.2.84"); manifest.sha256=SHA.hex("new-package")
  replacementHarness({manifest=manifest,manifestRaw="target"},function(h)
    eq(#h.downloads,1); eq(h.downloads[1].path,Adapter.updateArchivePath("/profile")); eq(h.downloads[1].url,manifest.archive_url)
    h:done(h.downloads[1].path,"new-package"); eq(#h.downloads,2)
    assert(h.downloads[2].url:find("/releases/download/v0.2.83/manifest.json",1,true))
    h:done(h.downloads[2].path,"rollback"); h:done(h.downloads[3].path,"old-package")
    assert(h:run(.10)); assert(h:run(.50)); eq(h.result[1],true)
  end)
end)
test("startup check failure reports briefly and still allows startup commands",function()
  local reported; local completed
  local adapter={
    checkLatestAsync=function(_,updater,done) done(nil,"network timed out") end,
    reportUpdateCheckFailure=function(_,message) reported=message end,
  }
  local u=Updater.new(adapter,updateSettings)
  eq(u:checkAtCharacterEntry(function(updated,err) completed={updated,err} end),true)
  eq(reported,"network timed out"); eq(completed[1],false); eq(completed[2],"network timed out"); eq(u.lock,nil)
end)
test("startup check contains adapter exceptions and still allows startup commands",function()
  local reported; local completed
  local adapter={
    checkLatestAsync=function() error("network exploded") end,
    reportUpdateCheckFailure=function(_,message) reported=message end,
  }
  local u=Updater.new(adapter,updateSettings)
  local ok,err=u:checkAtCharacterEntry(function(updated,message) completed={updated,message} end)
  eq(ok,nil); eq(err,"network exploded"); eq(reported,"network exploded"); eq(completed[1],false); eq(completed[2],"network exploded"); eq(u.lock,nil)
end)
test("startup check rejects overlap and completes only once",function()
  local manifestDone; local completions=0
  local adapter={checkLatestAsync=function(_,_,done) manifestDone=done; return true end}
  local u=Updater.new(adapter,updateSettings)
  eq(u:checkAtCharacterEntry(function() completions=completions+1 end),true)
  local ok,err=u:checkAtCharacterEntry(function() completions=completions+1 end); eq(ok,nil); eq(err,"startup check already in progress")
  manifestDone(releaseManifest("0.2.83")); manifestDone(releaseManifest("0.2.83")); eq(completions,1)
end)
test("async checksum mismatch never starts replacement",function()
  local called=false
  local u=Updater.new({replacePackageAsync=function() called=true end},{})
  local result
  local ok=u:installVerifiedAsync("payload",string.rep("0",64),function(success,err) result={success,err} end)
  eq(ok,nil)
  eq(called,false)
  eq(result[1],nil)
  eq(result[2],"package checksum mismatch")
end)
test("async failed health check triggers rollback",function()
  local rolledBack=false
  local adapter={
    replacePackageAsync=function(_,_,_,done) done(true) end,
    healthCheck=function() return nil,"HUD did not start" end,
    rollbackAsync=function(_,_,done) rolledBack=true; done(true) end,
  }
  local result
  local u=Updater.new(adapter,{})
  u:installVerifiedAsync("payload",SHA.hex("payload"),function(ok,err) result={ok,err} end)
  eq(rolledBack,true)
  eq(result[1],nil)
  eq(result[2],"HUD did not start")
end)
