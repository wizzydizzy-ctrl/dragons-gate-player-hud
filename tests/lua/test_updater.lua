local Updater=require("updater"); local SHA=require("sha256"); local Adapter=require("mudlet_adapter"); local Roller=require("autoroller")
local function releaseManifest(version)
  return {package="DragonsGateHUD",version=version,minimum_mudlet="5.0.0",view_schema=4,view_contract=string.rep("b",64),archive_url="https://github.com/wizzydizzy-ctrl/dragons-gate-hud/releases/download/v"..version.."/DragonsGateHUD.mpackage",sha256=string.rep("a",64),archive_size=100}
end
local updateSettings={version="0.2.83",github={owner="wizzydizzy-ctrl",repository="dragons-gate-hud"},update={package_limit=1000}}
local function withChatSoundClock(run)
  local names={"getEpoch","tempTimer","killTimer","createStopWatch","startStopWatch","stopStopWatch","deleteStopWatch","getStopWatchTime"}; local saved={}
  for _,name in ipairs(names) do saved[name]=rawget(_G,name) end
  local oldTime=os.time; local h={reads=0,resources=0,fallbacks=0}
  local ok,err=xpcall(function()
    os.time=function() h.fallbacks=h.fallbacks+1; return 1234 end
    getEpoch=nil
    for index=2,#names do _G[names[index]]=function() h.resources=h.resources+1; error("chat clock must not allocate timer or stopwatch resources") end end
    h.adapter=Adapter.new(); run(h); eq(h.resources,0)
  end,debug.traceback)
  os.time=oldTime
  for _,name in ipairs(names) do rawset(_G,name,saved[name]) end
  if not ok then error(err,0) end
end

test("chat sound clock preserves fractional seconds across integer second boundaries",function()
  withChatSoundClock(function(h)
    local now=100.99
    getEpoch=function() h.reads=h.reads+1; return now end
    local first=h.adapter:chatSoundTime(); eq(first,100.99)
    now=101.01; local second=h.adapter:chatSoundTime(); eq(second,101.01)
    assert(math.abs((second-first)-.02)<.000001); assert(second-first<1)
    now=101.99; assert(h.adapter:chatSoundTime()-first>=1)
    eq(h.reads,3); eq(h.fallbacks,0); eq(h.resources,0)
  end)
end)

test("chat sound clock uses getEpoch seconds without scaling and leaves the epoch API unchanged",function()
  withChatSoundClock(function(h)
    for _,value in ipairs({0,100.125,1788221000.375,"1788221000.375"}) do
      getEpoch=function() return value end
      eq(h.adapter:chatSoundTime(),tonumber(value))
    end
    eq(h.fallbacks,0); eq(h.adapter:epoch(),1234); eq(h.fallbacks,1)
  end)
end)

test("chat sound clock falls back safely when fractional time is missing invalid or throws",function()
  withChatSoundClock(function(h)
    eq(h.adapter:chatSoundTime(),1234)
    getEpoch="unavailable"; eq(h.adapter:chatSoundTime(),1234)
    getEpoch=function() return nil,"unavailable" end; eq(h.adapter:chatSoundTime(),1234)
    for _,value in ipairs({false,{},"invalid",0/0,math.huge,-math.huge}) do
      getEpoch=function() return value end
      eq(h.adapter:chatSoundTime(),1234)
    end
    getEpoch=function() error("clock unavailable") end; eq(h.adapter:chatSoundTime(),1234)
    eq(h.fallbacks,10); eq(h.resources,0)
  end)
end)

test("repeated chat sound clock reads allocate no timers stopwatches or adapter state",function()
  withChatSoundClock(function(h)
    local before={}; for key,value in pairs(h.adapter) do before[key]=value end
    getEpoch=function() h.reads=h.reads+1; return 200+h.reads/1000 end
    for index=1,100 do eq(h.adapter:chatSoundTime(),200+index/1000) end
    for key,value in pairs(h.adapter) do eq(value,before[key]); before[key]=nil end
    eq(next(before),nil); eq(h.reads,100); eq(h.fallbacks,0); eq(h.resources,0)
  end)
end)

test("roller settings serialization preserves arrangement choices disabled limits and MP",function()
  local source=Adapter.rollerSettingsSource({target_total=nil,hard_stop=nil,max_rolls=nil,reroll_delay=.1,reroll_command="reroll",arrange_mode="minimums",minimum_greats=2,minimum_good_plus=nil,auto_start_on_name=false,use_min_stats=true,require_min_stats_to_stop=true,show_every_roll=true,logging_enabled=true,log_folder="rolls",master_file="master.txt",min_stats={STR=6,MP=nil}})
  local compile=loadstring or load; local chunk,err=compile(source); assert(chunk,err); local saved=chunk()
  eq(saved.schema,3); eq(saved.target_total,false); eq(saved.hard_stop,false); eq(saved.max_rolls,false); eq(saved.arrange_mode,"minimums"); eq(saved.minimum_greats,2); eq(saved.minimum_good_plus,false); eq(saved.min_stats.STR,6); eq(saved.min_stats.MP,false)
  local restored=Roller.new({},saved); eq(restored.cfg.target_total,nil); eq(restored.cfg.hard_stop,nil); eq(restored.cfg.max_rolls,nil); eq(restored.cfg.arrange_mode,"minimums"); eq(restored.cfg.minimum_greats,2); eq(restored.cfg.minimum_good_plus,nil); eq(restored.cfg.min_stats.STR,6); eq(restored.cfg.min_stats.MP,nil); eq(restored.cfg.reroll_command,"reroll")
end)
test("legacy roller settings preserve nil limits and do not invent an MP minimum",function()
  local oldOpen,oldLoadfile,oldHome=io.open,loadfile,rawget(_G,"getMudletHomeDir"); getMudletHomeDir=function() return "/profile" end
  local ok,result=pcall(function()
    io.open=function() return {read=function() return "return { target_total=nil, hard_stop=62, max_rolls=nil, reroll_command='n', min_stats={STR=6, INT=nil} }" end,close=function() return true end} end
    loadfile=function() return function() return {target_total=nil,hard_stop=62,max_rolls=nil,reroll_command="n",min_stats={STR=6,INT=nil}} end end
    local value=Adapter.loadRollerSettings(); eq(value.schema,3); eq(value.target_total,false); eq(value.hard_stop,62); eq(value.max_rolls,false); eq(value.reroll_command,"reroll"); eq(value.arrange_mode,"manual"); eq(value.minimum_greats,false); eq(value.minimum_good_plus,false); eq(value.min_stats.STR,6); eq(value.min_stats.INT,false); eq(value.min_stats.MP,false)
  end)
  io.open,loadfile=oldOpen,oldLoadfile; rawset(_G,"getMudletHomeDir",oldHome); if not ok then error(result,0) end
end)
test("schema two roller settings migrate to safe manual arrangement defaults",function()
  local oldOpen,oldLoadfile,oldHome=io.open,loadfile,rawget(_G,"getMudletHomeDir"); getMudletHomeDir=function() return "/profile" end
  local ok,result=pcall(function()
    io.open=function() return {read=function() return "return { schema=2, target_total=60, min_stats={MP=false} }" end,close=function() return true end} end
    loadfile=function() return function() return {schema=2,target_total=60,min_stats={MP=false}} end end
    local value=Adapter.loadRollerSettings(); eq(value.schema,3); eq(value.target_total,60); eq(value.arrange_mode,"manual"); eq(value.minimum_greats,false); eq(value.minimum_good_plus,false); eq(value.min_stats.MP,false)
  end)
  io.open,loadfile=oldOpen,oldLoadfile; rawset(_G,"getMudletHomeDir",oldHome); if not ok then error(result,0) end
end)
test("update staging lives outside the installed package directory",function()
  local base=Adapter.updateBase("/profile")
  eq(base,"/profile/DGHUDUpdater")
  eq(base:find("/DragonsGateHUD",1,true),nil)
end)
test("download completion paths tolerate file URLs slashes and Windows drive case",function()
  eq(Adapter.sameDownloadPath("file:///profile/DGHUDUpdater/staging/manifest.json","/profile/DGHUDUpdater/staging/manifest.json"),true)
  eq(Adapter.sameDownloadPath([[C:\Profile\DGHUDUpdater\manifest.json]],[[c:\Profile\DGHUDUpdater\manifest.json]]),true)
  eq(Adapter.sameDownloadPath("/unowned/manifest.json","/profile/DGHUDUpdater/manifest.json"),false)
end)
test("mutable HUD data lives outside the replaceable package directory",function()
  local base=Adapter.dataBase("/profile")
  eq(base,"/profile/DGHUDData")
  eq(base:find("/DragonsGateHUD",1,true),nil)
  eq(Adapter.dataBase([[C:\profile\]]),[[C:\profile/DGHUDData]])
end)
test("display text settings accept only a bounded side-panel scale",function()
  local legacy=Adapter.displaySettingsSnapshot({side_text_scale=.8}); eq(legacy.side_text_scale,.8); eq(legacy.auto_wrap,true)
  local manual=Adapter.displaySettingsSnapshot({side_text_scale=1.2,auto_wrap=false}); eq(manual.side_text_scale,1.2); eq(manual.auto_wrap,false)
  local value,err=Adapter.displaySettingsSnapshot({side_text_scale=.79}); eq(value,nil); assert(err:find("between 0.8 and 1.2",1,true))
  value,err=Adapter.displaySettingsSnapshot({side_text_scale="large"}); eq(value,nil); assert(err:find("between 0.8 and 1.2",1,true))
  value,err=Adapter.displaySettingsSnapshot({side_text_scale=1,auto_wrap="no"}); eq(value,nil); assert(err:find("must be a boolean",1,true))
end)
test("legacy mapper settings default missing submap choices off and preserve explicit true",function()
  local oldLoadfile,oldHome=loadfile,rawget(_G,"getMudletHomeDir"); getMudletHomeDir=function() return "/profile" end
  local ok,result=pcall(function()
    loadfile=function() return function() return {enabled=true,transition_submaps={door=true,gate=false}} end end
    local value=assert(Adapter.loadMapperSettings()); eq(value.schema,2); eq(value.transition_submaps.door,true); eq(value.transition_submaps.gate,false)
    for _,key in ipairs({"portal","arch","path","other"}) do eq(value.transition_submaps[key],false) end
  end)
  loadfile=oldLoadfile; rawset(_G,"getMudletHomeDir",oldHome); if not ok then error(result,0) end
end)
test("chat settings snapshot sanitizes persistent tab order as data",function()
  local value=assert(Adapter.chatSettingsSnapshot({tab_order={" staff ","ALL","STAFF","OWN","<BAD>","ROOM\nESP"},all_sources={ROOM=true,COMBAT=false}}))
  eq(table.concat(value.tab_order,","),"STAFF,ALL")
  eq(value.all_sources.ROOM,true); eq(value.all_sources.COMBAT,false); eq(value.all_sources.ESP,true)
  local missing,err=Adapter.chatSettingsSnapshot({tab_order={}}); eq(missing,nil); assert(err:find("empty",1,true))
  missing,err=Adapter.chatSettingsSnapshot({tab_order={"ALL"},all_sources={COMBAT="no"}}); eq(missing,nil); assert(err:find("booleans",1,true))
end)

local function withChatSettingsFiles(run)
  local oldOpen,oldLoadfile,oldRename,oldRemove=io.open,loadfile,os.rename,os.remove
  local oldLfs,oldHome=rawget(_G,"lfs"),rawget(_G,"getMudletHomeDir")
  local h={files={},path="/profile/DGHUDData/chat-settings.lua",writes=0}
  local ok,err=xpcall(function()
    getMudletHomeDir=function() return "/profile" end
    lfs={mkdir=function() return true end}
    io.open=function(path,mode)
      if mode=="rb" then
        if h.files[path]==nil then return nil,"missing file" end
        return {read=function() return h.files[path] end,close=function() return true end}
      end
      eq(mode,"wb"); eq(path,h.path..".tmp")
      if h.fail=="open" then return nil,"disk full at open" end
      local file={}
      function file:write(source)
        h.writes=h.writes+1
        if h.fail=="write" then return nil,"disk full at write" end
        h.files[path]=source; return self
      end
      function file:close() if h.fail=="close" then return nil,"disk full at close" end; return true end
      return file
    end
    os.remove=function(path) h.files[path]=nil; return true end
    os.rename=function(from,to)
      if (h.fail=="backup" and from==h.path) or (h.fail=="install" and from==h.path..".tmp") then return nil,"disk full at "..h.fail end
      if h.files[from]==nil then return nil,"missing file" end
      h.files[to]=h.files[from]; h.files[from]=nil; return true
    end
    loadfile=function(path)
      local source=h.files[path]; if not source then return nil,"missing file" end
      return (loadstring or load)(source)
    end
    run(h)
  end,debug.traceback)
  io.open,loadfile,os.rename,os.remove=oldOpen,oldLoadfile,oldRename,oldRemove
  rawset(_G,"lfs",oldLfs); rawset(_G,"getMudletHomeDir",oldHome)
  if not ok then error(err,0) end
end

test("chat visibility snapshots preserve booleans and default legacy records to visible",function()
  for _,visible in ipairs({false,true}) do
    local config={visible=visible,tab_order={" staff ","ALL"},all_sources={ROOM=false,COMBAT=true}}
    local snapshot=assert(Adapter.chatSettingsSnapshot(config))
    eq(snapshot.visible,visible); eq(table.concat(snapshot.tab_order,","),"STAFF,ALL")
    eq(snapshot.all_sources.ROOM,false); eq(snapshot.all_sources.COMBAT,true); eq(snapshot.all_sources.ESP,true)
    eq(config.tab_order[1]," staff "); eq(config.visible,visible)
  end
  eq(assert(Adapter.chatSettingsSnapshot({tab_order={"ALL"}})).visible,true)
end)

test("chat visibility rejects nonboolean persisted values",function()
  for _,visible in ipairs({"false",0,1,{}}) do
    local value,err=Adapter.chatSettingsSnapshot({visible=visible,tab_order={"ALL"}})
    eq(value,nil); eq(type(err),"string")
  end
end)

test("chat settings save and load round trip visibility with tab order and ALL sources",function()
  withChatSettingsFiles(function(h)
    local adapter=Adapter.new()
    for _,visible in ipairs({false,true,false}) do
      local config={visible=visible,tab_order={"STAFF","ALL","ROOM"},all_sources={ROOM=false,COMBAT=true}}
      assert(adapter:saveChatSettings(config))
      local serialized=assert((loadstring or load)(assert(h.files[h.path])))()
      eq(serialized.visible,visible); eq(type(serialized.visible),"boolean")
      local loaded=assert(Adapter.loadChatSettings())
      eq(loaded.visible,visible); eq(table.concat(loaded.tab_order,","),"STAFF,ALL,ROOM")
      eq(loaded.all_sources.ROOM,false); eq(loaded.all_sources.COMBAT,true); eq(loaded.all_sources.ESP,true)
      eq(config.visible,visible); eq(config.tab_order[1],"STAFF"); eq(h.files[h.path..".tmp"],nil); eq(h.files[h.path..".bak"],nil)
    end
    eq(h.writes,3)
  end)
end)

test("legacy chat settings without visibility load visible and persist the new boolean",function()
  withChatSettingsFiles(function(h)
    h.files[h.path]="return {tab_order={'STAFF','ALL'},all_sources={ROOM=false,COMBAT=true}}"
    local loaded=assert(Adapter.loadChatSettings())
    eq(loaded.visible,true); eq(loaded.tab_order[1],"STAFF"); eq(loaded.all_sources.ROOM,false)
    assert(Adapter.new():saveChatSettings(loaded))
    local serialized=assert((loadstring or load)(h.files[h.path]))()
    eq(serialized.visible,true); eq(assert(Adapter.loadChatSettings()).all_sources.COMBAT,true)
  end)
end)

test("failed chat visibility persistence retains the previous complete settings file",function()
  for _,prior in ipairs({false,true}) do
    for _,stage in ipairs({"open","write","close","backup","install"}) do
      withChatSettingsFiles(function(h)
        local adapter=Adapter.new()
        assert(adapter:saveChatSettings({visible=prior,tab_order={"STAFF","ALL"},all_sources={ROOM=false,COMBAT=true}}))
        local original=h.files[h.path]; h.fail=stage
        local candidate={visible=not prior,tab_order={"ALL","ROOM"},all_sources={ROOM=true,COMBAT=false}}
        local saved,err=adapter:saveChatSettings(candidate)
        eq(saved,nil); assert(tostring(err):find("disk full",1,true)); eq(h.files[h.path],original)
        local loaded=assert(Adapter.loadChatSettings())
        eq(loaded.visible,prior); eq(table.concat(loaded.tab_order,","),"STAFF,ALL")
        eq(loaded.all_sources.ROOM,false); eq(loaded.all_sources.COMBAT,true)
        eq(candidate.visible,not prior); eq(candidate.tab_order[1],"ALL"); eq(candidate.all_sources.ROOM,true)
      end)
    end
  end
end)

test("sound settings round trip all tabs and preserve other chat preferences",function()
  withChatSettingsFiles(function(h)
    local Sounds=require("chat_sounds"); local sounds=Sounds.defaults()
    sounds.volume=73; sounds.tabs.STAFF.enabled=false; sounds.tabs.ROOM={enabled=true,sound="staff"}
    sounds.tabs["QUEST - NIGHT"]={enabled=true,sound="esp"}
    local config={visible=false,tab_order={"STAFF","ALL","QUEST - NIGHT"},all_sources={ROOM=false,COMBAT=true},sounds=sounds}
    assert(Adapter.new():saveChatSettings(config))
    local loaded=assert(Adapter.loadChatSettings()); eq(loaded.sounds.volume,73)
    eq(loaded.visible,false); eq(table.concat(loaded.tab_order,","),"STAFF,ALL,QUEST - NIGHT")
    eq(loaded.all_sources.ROOM,false); eq(loaded.all_sources.COMBAT,true)
    for tab,value in pairs(sounds.tabs) do eq(loaded.sounds.tabs[tab].enabled,value.enabled); eq(loaded.sounds.tabs[tab].sound,value.sound) end
    loaded.sounds.tabs.ROOM.sound="room"; eq(sounds.tabs.ROOM.sound,"staff")
    eq(assert(Adapter.loadChatSettings()).sounds.tabs.ROOM.sound,"staff")
    eq(h.files[h.path..".tmp"],nil); eq(h.files[h.path..".bak"],nil)
  end)
end)

test("sound settings at the 64 total tab boundary survive save load and revalidation",function()
  withChatSettingsFiles(function(h)
    local Sounds=require("chat_sounds"); local tabs={STAFF={enabled=false,sound="dragon"}}
    for index=1,55 do tabs["CUSTOM"..index]={enabled=index%2==0,sound="esp"} end
    local config={visible=false,tab_order={"STAFF","ALL"},all_sources={ROOM=false},sounds={volume=42,tabs=tabs}}
    local snapshot=assert(Adapter.chatSettingsSnapshot(config))
    local count=0; for _ in pairs(snapshot.sounds.tabs) do count=count+1 end; eq(count,64)
    local adapter=Adapter.new(); assert(adapter:saveChatSettings(snapshot))
    local loaded=assert(Adapter.loadChatSettings()); local normalized=assert(Sounds.validate(loaded.sounds))
    count=0; for _ in pairs(normalized.tabs) do count=count+1 end; eq(count,64)
    eq(loaded.visible,false); eq(loaded.all_sources.ROOM,false); eq(loaded.sounds.volume,42)
    eq(loaded.sounds.tabs.STAFF.enabled,false); eq(loaded.sounds.tabs.STAFF.sound,"dragon")
    for index=1,55 do eq(loaded.sounds.tabs["CUSTOM"..index].enabled,index%2==0); eq(loaded.sounds.tabs["CUSTOM"..index].sound,"esp") end
    local serialized=h.files[h.path]; assert(adapter:saveChatSettings(loaded)); eq(h.files[h.path],serialized)
    assert(Adapter.loadChatSettings())
  end)
end)

test("missing persisted sounds remain absent while supplied settings receive sound defaults",function()
  withChatSettingsFiles(function(h)
    eq(Adapter.loadChatSettings(),nil)
    h.files[h.path]="return {tab_order={'STAFF','ALL'}}"
    local legacy=assert(Adapter.loadChatSettings()); eq(legacy.sounds,nil)
    local defaults=require("chat_sounds").defaults(); defaults.volume=37; defaults.tabs.STAFF.enabled=false
    local merged=require("settings").merge({sounds=defaults},legacy)
    eq(merged.sounds.volume,37); eq(merged.sounds.tabs.STAFF.enabled,false)
    assert(Adapter.new():saveChatSettings(legacy)); eq(assert(Adapter.loadChatSettings()).sounds,nil)
    eq(h.files[h.path]:find("sounds",1,true),nil)
    local snapshot=assert(Adapter.chatSettingsSnapshot({tab_order={"ALL"},sounds={tabs={ROOM={enabled=true}}}}))
    eq(snapshot.sounds.volume,60); eq(snapshot.sounds.tabs.STAFF.enabled,true)
    eq(snapshot.sounds.tabs.STAFF.sound,"staff"); eq(snapshot.sounds.tabs.ROOM.enabled,true)
    assert(Adapter.new():saveChatSettings({tab_order={"ALL"},sounds={}}))
    local defaults=assert(Adapter.loadChatSettings()).sounds
    eq(defaults.volume,60); eq(defaults.tabs.STAFF.enabled,true); eq(defaults.tabs.ROOM.enabled,false)
  end)
end)

test("invalid sounds fail validation before writes and invalid persisted sounds do not load",function()
  withChatSettingsFiles(function(h)
    local adapter=Adapter.new(); assert(adapter:saveChatSettings({tab_order={"ALL"},sounds={}}))
    local original=h.files[h.path]; local writes=h.writes
    local invalid={false,"staff",{volume=0},{volume=101},{volume=1.5},{volume="60"},{volume=0/0},{volume=math.huge},
      {tabs=false},{tabs={STAFF={enabled="yes"}}},{tabs={STAFF={sound="../staff.wav"}}},
      {tabs={STAFF={sound="https://example.test/tone.wav"}}},{tabs={STAFF={sound='staff"}; error("injection") --'}}}}
    for _,sounds in ipairs(invalid) do
      local config={tab_order={"ALL"},sounds=sounds}
      local snapshot,err=Adapter.chatSettingsSnapshot(config); eq(snapshot,nil); eq(type(err),"string")
      local saved,saveErr=adapter:saveChatSettings(config); eq(saved,nil); eq(type(saveErr),"string")
      eq(h.writes,writes); eq(h.files[h.path],original)
    end
    for _,source in ipairs({"false","{volume=0}","{tabs={STAFF={sound='../bad.wav'}}}","{tabs={STAFF={enabled='yes'}}}"}) do
      h.files[h.path]="return {tab_order={'ALL'},sounds="..source.."}"
      eq(Adapter.loadChatSettings(),nil)
    end
  end)
end)

test("sound persistence failures preserve the previous complete chat settings",function()
  for _,stage in ipairs({"open","write","close","backup","install"}) do
    withChatSettingsFiles(function(h)
      local adapter=Adapter.new(); assert(adapter:saveChatSettings({visible=false,tab_order={"STAFF","ALL"},sounds={volume=29,tabs={STAFF={enabled=false,sound="esp"}}}}))
      local original=h.files[h.path]; h.fail=stage
      local saved,err=adapter:saveChatSettings({visible=true,tab_order={"ALL"},sounds={volume=80}})
      eq(saved,nil); assert(err); eq(h.files[h.path],original)
      local loaded=assert(Adapter.loadChatSettings()); eq(loaded.visible,false); eq(loaded.sounds.volume,29)
      eq(loaded.sounds.tabs.STAFF.enabled,false); eq(loaded.sounds.tabs.STAFF.sound,"esp")
    end)
  end
end)

local function withChatSoundPlayback(run)
  local names={"lfs","getMudletHomeDir","playSoundFile","setVolume","muteSounds","unmuteSounds","downloadFile"}; local saved={}
  for _,name in ipairs(names) do saved[name]=rawget(_G,name) end
  local oldOpen,oldRemove=io.open,os.remove; local Sounds=require("chat_sounds"); local oldWav,oldGet=Sounds.wav,Sounds.get
  local h={base="/profile/DGHUDData",directory="/profile/DGHUDData/chat-sounds-v1",path="/profile/DGHUDData/chat-sounds-v1/chat-staff-v1.wav",files={},modes={},plays={},opens={},mkdirs={},inspections={},writes=0,closes=0,generations=0}
  function h:failure(stage)
    if self.fail~=stage then return false end
    if self.throw then error("failure at "..stage) end
    return true
  end
  local ok,err=xpcall(function()
    getMudletHomeDir=function() return "/profile/" end
    for _,name in ipairs({"setVolume","muteSounds","unmuteSounds","downloadFile"}) do _G[name]=function() error("unexpected global media change or download") end end
    Sounds.wav=function(id)
      h.generations=h.generations+1
      if h:failure("generate") then return nil,"failure at generate" end
      return oldWav(id)
    end
    lfs={
      symlinkattributes=function(path,field)
        eq(field,"mode"); h.inspections[#h.inspections+1]=path
        assert(path==h.base or path==h.directory or path:match("^/profile/DGHUDData/chat%-sounds%-v1/chat%-[a-z]+%-v1%.wav$"))
        if h:failure("inspect") then return nil,"failure at inspect",13 end
        local mode=h.modes[path] or (h.files[path]~=nil and "file" or nil)
        if mode then return mode end
        return nil,"missing file",2
      end,
      mkdir=function(path)
        h.mkdirs[#h.mkdirs+1]=path; assert(path==h.base or path==h.directory)
        local stage=path==h.base and "mkdirParent" or "mkdirCache"
        if h:failure(stage) then return nil,"failure at "..stage end
        h.modes[path]="directory"; return true
      end,
    }
    io.open=function(path,mode)
      h.opens[#h.opens+1]={path=path,mode=mode}
      assert(path:match("^/profile/DGHUDData/chat%-sounds%-v1/chat%-[a-z]+%-v1%.wav$")); assert(mode=="rb" or mode=="wb")
      if h:failure("open") then return nil,"failure at open" end
      if mode=="wb" then eq(h.files[path],nil); h.files[path]="" end
      return {
        read=function(_,limit) eq(mode,"rb"); eq(limit,65536); if h:failure("read") then return nil,"failure at read" end; return h.files[path]:sub(1,limit) end,
        write=function(_,value) eq(mode,"wb"); h.writes=h.writes+1; if h:failure("write") then return nil,"failure at write" end; h.files[path]=value; return true end,
        close=function() h.closes=h.closes+1; if h:failure("close") then return nil,"failure at close" end; return true end,
      }
    end
    os.remove=function(path) eq(path,h.path); h.files[path]=nil; return true end
    playSoundFile=function(options) h.plays[#h.plays+1]=options; return true end
    h.adapter=Adapter.new(); h.wav=oldWav; run(h,Sounds)
  end,debug.traceback)
  io.open,os.remove=oldOpen,oldRemove; Sounds.wav,Sounds.get=oldWav,oldGet
  for _,name in ipairs(names) do rawset(_G,name,saved[name]) end
  if not ok then error(err,0) end
end

test("chat playback lazily prepares fixed persistent sounds and caches only completed files",function()
  withChatSoundPlayback(function(h)
    eq(h.generations,0); eq(#h.opens,0); eq(#h.mkdirs,0)
    assert(h.adapter:playChatSound("staff",60))
    eq(h.files[h.path],h.wav("staff")); eq(#h.mkdirs,2); eq(h.writes,1); eq(h.closes,1)
    local options=h.plays[1]; eq(options.name,h.path); eq(options.volume,60); eq(options.loops,1)
    eq(options.key,"DGHUD.ChatAlert"); eq(options.tag,"DGHUD.ChatAlert")
    local count=0; for _ in pairs(options) do count=count+1 end; eq(count,5)
    assert(h.adapter:playChatSound("staff",100)); eq(h.generations,1); eq(h.writes,1); eq(#h.opens,1); eq(h.plays[2].volume,100)
  end)
end)

test("each built-in sound resolves through the catalog to its fixed cache filename",function()
  withChatSoundPlayback(function(h,Sounds)
    for _,record in ipairs(Sounds.catalog) do
      assert(h.adapter:playChatSound(record.id,1))
      eq(h.plays[#h.plays].name,h.directory.."/"..record.file)
      eq(h.files[h.directory.."/"..record.file],h.wav(record.id))
    end
    eq(#h.plays,9); eq(#h.mkdirs,2)
  end)
end)

test("chat sound preparation accepts missing-file errors without a numeric filesystem code",function()
  withChatSoundPlayback(function(h)
    local inspect=lfs.symlinkattributes
    lfs.symlinkattributes=function(path,field)
      local mode,err,code=inspect(path,field)
      if code==2 then return nil,"No such file or directory" end
      return mode,err,code
    end
    assert(h.adapter:playChatSound("staff",60)); eq(h.files[h.path],h.wav("staff"))
  end)
end)

test("unbounded or malformed generated audio is rejected before creating cache files",function()
  for _,value in ipairs({false,"not a WAV","RIFF"..string.rep("x",4).."WAVE"..string.rep("x",65536)}) do
    withChatSoundPlayback(function(h,Sounds)
      Sounds.wav=function() return value end
      local played,err=h.adapter:playChatSound("staff",60); eq(played,nil); assert(err)
      eq(#h.inspections,0); eq(#h.mkdirs,0); eq(#h.opens,0); eq(#h.plays,0)
    end)
  end
end)

test("a matching existing WAV is reused without writing and conflicting files are retained",function()
  withChatSoundPlayback(function(h)
    h.files[h.path]=h.wav("staff"); assert(h.adapter:playChatSound("staff",60)); eq(h.writes,0); eq(h.opens[1].mode,"rb")
  end)
  for _,content in ipairs({"unrelated data",string.rep("x",65536)}) do
    withChatSoundPlayback(function(h)
      h.files[h.path]=content
      local played,err=h.adapter:playChatSound("staff",60); eq(played,nil); assert(err:find("conflicts",1,true))
      eq(h.files[h.path],content); eq(h.writes,0); eq(#h.plays,0); eq(h.adapter.chatSoundsReady,nil)
    end)
  end
end)

test("chat playback rejects arbitrary paths catalog paths and invalid volume before file access",function()
  withChatSoundPlayback(function(h,Sounds)
    for _,id in ipairs({false,{},"unknown","../staff.wav","/tmp/staff.wav","https://example.test/tone.wav","staff\0"}) do
      local played,err=h.adapter:playChatSound(id,60); eq(played,nil); eq(type(err),"string")
    end
    for _,volume in ipairs({false,"60",0,101,-1,1.5,0/0,math.huge,-math.huge}) do
      local played,err=h.adapter:playChatSound("staff",volume); eq(played,nil); eq(type(err),"string")
    end
    eq(h.adapter:playChatSound("staff"),nil)
    for _,file in ipairs({"../chat-staff-v1.wav","sounds/chat-staff-v1.wav","https://example.test/staff.wav"}) do
      Sounds.get=function() return {id="staff",file=file} end
      eq(h.adapter:playChatSound("staff",60),nil)
    end
    eq(h.generations,0); eq(#h.inspections,0); eq(#h.opens,0); eq(#h.plays,0)
  end)
end)

test("cache preparation failures and exceptions remain retryable and never play partial output",function()
  for _,stage in ipairs({"generate","inspect","mkdirParent","mkdirCache","open","write","close"}) do
    for _,throws in ipairs({false,true}) do
      withChatSoundPlayback(function(h)
        h.fail=stage; h.throw=throws
        local played,err=h.adapter:playChatSound("staff",60); eq(played,nil); eq(type(err),"string")
        eq(#h.plays,0); eq(h.adapter.chatSoundsReady,nil); eq(h.files[h.path],nil)
        h.fail=nil; assert(h.adapter:playChatSound("staff",60)); eq(#h.plays,1); eq(h.files[h.path],h.wav("staff"))
      end)
    end
  end
end)

test("existing cache read and close failures preserve the file and permit a later retry",function()
  for _,stage in ipairs({"read","close"}) do
    for _,throws in ipairs({false,true}) do
      withChatSoundPlayback(function(h)
        h.files[h.path]=h.wav("staff"); local original=h.files[h.path]; h.fail=stage; h.throw=throws
        local played,err=h.adapter:playChatSound("staff",60); eq(played,nil); assert(err)
        eq(h.files[h.path],original); eq(h.writes,0); eq(#h.plays,0); eq(h.adapter.chatSoundsReady,nil); eq(h.closes,1)
        h.fail=nil; assert(h.adapter:playChatSound("staff",60)); eq(h.writes,0)
      end)
    end
  end
end)

test("chat sound cache refuses links directories and special files at owned paths",function()
  for _,target in ipairs({"base","directory","path"}) do
    for _,mode in ipairs({"link","socket",target=="path" and "directory" or "file"}) do
      withChatSoundPlayback(function(h)
        h.modes[h[target]]=mode
        local played,err=h.adapter:playChatSound("staff",60); eq(played,nil); assert(err)
        eq(#h.opens,0); eq(#h.plays,0); eq(h.modes[h[target]],mode)
      end)
    end
  end
end)

test("missing media filesystem or profile APIs fail safely without playback",function()
  for _,name in ipairs({"playSoundFile","getMudletHomeDir","lfs"}) do
    withChatSoundPlayback(function(h)
      _G[name]=nil; local played,err=h.adapter:playChatSound("staff",60)
      eq(played,nil); assert(err); eq(#h.opens,0); eq(#h.plays,0)
    end)
  end
  withChatSoundPlayback(function(h)
    getMudletHomeDir=function() error("profile unavailable") end
    eq(h.adapter:playChatSound("staff",60),nil); eq(#h.opens,0)
  end)
end)

test("playSoundFile nil without error succeeds and false nil-error or exceptions fail safely",function()
  local outcomes={
    {fn=function() end,success=true},
    {fn=function() return true end,success=true},
    {fn=function() return false,"muted" end},
    {fn=function() return nil,"media unavailable" end},
    {fn=function() error("playback failure") end},
  }
  for _,outcome in ipairs(outcomes) do
    withChatSoundPlayback(function(h)
      playSoundFile=outcome.fn
      local played,err=h.adapter:playChatSound("staff",60)
      if outcome.success then eq(played,true); eq(err,nil) else eq(played,nil); eq(type(err),"string") end
      eq(h.files[h.path],h.wav("staff"))
    end)
  end
end)

test("legacy mutable data migrates without moving package resources",function()
  local oldLfs,oldOpen,oldRename,oldRemove=lfs,io.open,os.rename,os.remove
  local directories={['/profile/DragonsGateHUD']=true,['/profile/DragonsGateHUD/map-collections']=true}
  local files={['/profile/DragonsGateHUD/roller-settings.lua']='legacy roller',['/profile/DragonsGateHUD/map-collections/collections.json']='legacy index',['/profile/DGHUDData/mapper-settings.lua']='new mapper'}
  local renames={}
  local ok,err=pcall(function()
    lfs={
      symlinkattributes=function(path,field) local value=directories[path] and "directory" or (files[path]~=nil and "file" or nil); return field=="mode" and value or value end,
      mkdir=function(path) directories[path]=true; return true end,
      dir=function(path)
        local listed={['/profile/DragonsGateHUD']={".","..","DragonsGateHUD.xml","DGHUDRuntime.lua","config.lua","map-collections","roller-settings.lua","mapper-settings.lua"},['/profile/DragonsGateHUD/map-collections']={".","..","collections.json"}}
        local names=listed[path] or {".",".."}; local index=0
        return function() index=index+1; return names[index] end
      end,
    }
    io.open=function(path,mode)
      if mode=="rb" then if files[path]==nil then return nil,"missing" end; local finished=false; return {read=function(_,amount) if amount=="*a" then return files[path] end; if finished then return nil end; finished=true; return files[path] end,close=function() return true end} end
      if mode=="wb" then return {write=function(_,value) files[path]=value; return true end,close=function() return true end} end
    end
    os.remove=function(path) files[path]=nil; return true end
    os.rename=function(source,destination) renames[#renames+1]={source,destination}; if files[source]==nil then return nil,"missing" end; files[destination]=files[source]; files[source]=nil; return true end
    eq(Adapter.prepareDataDirectory("/profile"),true)
    eq(directories['/profile/DGHUDData'],true)
    eq(files['/profile/DGHUDData/roller-settings.lua'],'legacy roller')
    eq(files['/profile/DGHUDData/map-collections/collections.json'],'legacy index')
    eq(files['/profile/DGHUDData/mapper-settings.lua'],'new mapper')
    eq(files['/profile/DragonsGateHUD/roller-settings.lua'],'legacy roller')
    for _,move in ipairs(renames) do eq(move[1]:find('/profile/DragonsGateHUD/',1,true),nil) end
  end)
  lfs,io.open,os.rename,os.remove=oldLfs,oldOpen,oldRename,oldRemove; if not ok then error(err,0) end
end)
test("normal update preflight never reads persistent map data",function()
  local oldLfs,oldOpen=lfs,io.open; local reads=0
  local ok,err=pcall(function()
    lfs={
      symlinkattributes=function(path) if path=='/profile/DragonsGateHUD' or path=='/profile/DGHUDData' then return 'directory' elseif path=='/profile/DGHUDData/maps/huge.dat' then return 'file' end end,
      mkdir=function() return true end,
      dir=function(path) local names={'.','..','DragonsGateHUD.xml','DGHUDRuntime.lua','config.lua'}; local index=0; return function() index=index+1; return names[index] end end,
    }
    io.open=function() reads=reads+1; return nil,'persistent data must not be opened' end
    eq(Adapter.prepareDataDirectory('/profile'),true); eq(reads,0)
  end)
  lfs,io.open=oldLfs,oldOpen; if not ok then error(err,0) end
end)
test("failed migration returns a warning without destructively moving legacy data",function()
  local oldLfs,oldOpen=lfs,io.open
  local ok,err=pcall(function()
    lfs={symlinkattributes=function(path) if path=='/profile/DragonsGateHUD' or path=='/profile/DGHUDData' then return 'directory' elseif path=='/profile/DragonsGateHUD/update-settings.lua' then return 'file' end end,mkdir=function() return true end,dir=function() local names={'.','..','update-settings.lua'}; local index=0; return function() index=index+1; return names[index] end end}
    io.open=function(path,mode) if mode=='rb' then return {read=function() return 'legacy' end,close=function() return true end} end; return nil,'denied' end
    local prepared,warning=Adapter.prepareDataDirectory('/profile'); eq(prepared,true); assert(warning:find('denied',1,true))
  end)
  lfs,io.open=oldLfs,oldOpen; if not ok then error(err,0) end
end)
test("different legacy and persistent files abort migration without overwriting either",function()
  local oldLfs,oldOpen=lfs,io.open
  local files={['/profile/DragonsGateHUD/update-settings.lua']='legacy',['/profile/DGHUDData/update-settings.lua']='current'}
  local ok,err=pcall(function()
    lfs={symlinkattributes=function(path) if path=='/profile/DragonsGateHUD' or path=='/profile/DGHUDData' then return 'directory' elseif files[path]~=nil then return 'file' end end,mkdir=function() return true end,dir=function() local names={'.','..','update-settings.lua'}; local index=0; return function() index=index+1; return names[index] end end}
    io.open=function(path,mode) if mode~='rb' or files[path]==nil then return nil,'missing' end; local finished=false; return {read=function(_,amount) if amount=='*a' then return files[path] end; if finished then return nil end; finished=true; return files[path] end,close=function() return true end} end
    local prepared,warning=Adapter.prepareDataDirectory('/profile'); eq(prepared,true); assert(warning:find('destination differs',1,true)); eq(files['/profile/DragonsGateHUD/update-settings.lua'],'legacy'); eq(files['/profile/DGHUDData/update-settings.lua'],'current')
  end)
  lfs,io.open=oldLfs,oldOpen; if not ok then error(err,0) end
end)
test("filesystem inspection errors fail closed before migration",function()
  local oldLfs=lfs; local ok,err=pcall(function()
    lfs={symlinkattributes=function(path) if path=='/profile/DGHUDData' then return 'directory' end; error('permission denied') end,mkdir=function() return true end}
    local prepared,why=Adapter.prepareDataDirectory('/profile'); eq(prepared,nil); assert(why:find('permission denied',1,true))
  end)
  lfs=oldLfs; if not ok then error(err,0) end
end)
test("explicit migration read errors fail closed instead of looking like EOF",function()
  local oldLfs,oldOpen=lfs,io.open
  local ok,err=pcall(function()
    lfs={symlinkattributes=function(path) if path=='/profile/DragonsGateHUD' or path=='/profile/DGHUDData' then return 'directory' elseif path:find('settings.lua',1,true) then return 'file' end end,mkdir=function() return true end,dir=function() local names={'.','..','settings.lua'}; local index=0; return function() index=index+1; return names[index] end end}
    io.open=function(path,mode) if mode~='rb' then return nil,'denied' end; return {read=function() return nil,'disk read failed' end,close=function() return true end} end
    local prepared,warning=Adapter.prepareDataDirectory('/profile'); eq(prepared,true); assert(warning:find('disk read failed',1,true))
  end)
  lfs,io.open=oldLfs,oldOpen; if not ok then error(err,0) end
end)
test("update handoff retains only an exact contracted view lease",function()
  local contract=string.rep("a",64); local settingsContract=string.rep("b",64); local view={root={},view_contract=contract,view_settings_contract=settingsContract}; local snapshot={schema=1,character_key="dace",filter="ALL",entries={{message="kept"}}}; local retired={[6]=true}
  local hud={settings={view_schema=1,view_contract=contract,view_settings_contract=settingsContract},controller={view=view,chat={handoff=function() return snapshot end},keybindings={ids={north=7},retiredIds=retired}}}
  local lease=Adapter.markUpdateHandoff(hud,1,contract); eq(lease.view,view); eq(lease.settings_contract,settingsContract); eq(hud.controller.update_handoff,true)
  eq(hud._chat_handoff,snapshot)
  eq(hud.controller.keybinding_retired_ids,retired); eq(retired[6],true); eq(retired[7],true); eq(retired["7"],true)
  eq(Adapter.markUpdateHandoff(hud,2,contract),nil)
  eq(Adapter.markUpdateHandoff(hud,1,nil),nil)
end)
test("verified update archive retains the Mudlet package name",function()
  eq(Adapter.updateArchivePath("/profile"),"/profile/DGHUDUpdater/staging/DragonsGateHUD.mpackage")
  eq(Adapter.isCanonicalArchivePath("/profile/DGHUDUpdater/staging/DragonsGateHUD.mpackage"),true)
  eq(Adapter.isCanonicalArchivePath([[C:\\profile\\DGHUDUpdater\\DragonsGateHUD.mpackage]]),true)
  eq(Adapter.isCanonicalArchivePath("/profile/DGHUDUpdater/current.mpackage"),false)
  eq(Adapter.verifyArchive("prior",SHA.hex("prior")),true); eq(Adapter.verifyArchive("tampered",SHA.hex("prior")),false)
end)
test("native checksum helpers are cross-platform and parse common tool output",function()
  local hash=string.rep("ab",32)
  local program,args=Adapter.nativeHashSpec("mac","/tmp/HUD package.mpackage"); eq(program,"/usr/bin/shasum"); eq(args[1],"-a"); eq(args[3],"/tmp/HUD package.mpackage")
  program,args=Adapter.nativeHashSpec("windows","C:/HUD package.mpackage"); assert(program:lower():find("certutil.exe",1,true)); eq(args[1],"-hashfile"); eq(args[3],"SHA256")
  eq(Adapter.parseNativeHash(hash.."  /tmp/file"),hash)
  eq(Adapter.parseNativeHash("SHA256 hash\n"..hash:gsub("(%x%x)","%1 ").."\nCertUtil: completed"),hash)
end)
test("native checksum verification preserves exact SHA validation",function()
  local oldSpawn,oldGetOS,oldTimer=_G.spawn,_G.getOS,_G.tempTimer; local closed=false; local hash=string.rep("cd",32); local result
  getOS=function() return "mac" end
  spawn=function(read,program,a,b,path) eq(program,"/usr/bin/shasum"); eq(a,"-a"); eq(b,"256"); read(hash.."  "..path); return {isRunning=function() return false end,close=function() closed=true end} end
  tempTimer=function(_,fn) fn(); return 1 end
  local ok,err=pcall(function() Adapter.new():verifyFileAsync("/not/read/native.mpackage",hash,function(valid,message) result={valid,message} end) end)
  _G.spawn,_G.getOS,_G.tempTimer=oldSpawn,oldGetOS,oldTimer; if not ok then error(err,0) end
  eq(result[1],true); eq(result[2],nil); eq(closed,true)
end)
local function recoveryHarness(options,body)
  options=options or {}; local names={"DGHUDRecovery","lfs","getMudletHomeDir","getPackages","getPackageInfo","registerAnonymousEventHandler","killAnonymousEventHandler","tempTimer","killTimer","tempAlias","killAlias","downloadFile","uninstallPackage","installPackage","cecho"}; local saved={}
  for _,name in ipairs(names) do saved[name]=_G[name] end
  local h={installed=options.installed~=false,version=options.version,busy=tonumber(options.busy) or 0,handlers={},timers={},downloads={},uninstalls=0,installs=0,nextID=0,messages={}}
  local expectedOwner=options.owner or "wizzydizzy-ctrl"; local expectedRepository=options.repository or "dragons-gate-player-hud"
  local ok,err=pcall(function()
    DGHUDRecovery=options.runtimeVersion and {version=options.runtimeVersion,owner=options.runtimeOwner or expectedOwner,repository=options.runtimeRepository or expectedRepository,alias=options.runtimeAlias or 90,run=function() end} or nil
    lfs={mkdir=function() return true end}; getMudletHomeDir=function() return "/profile" end
    getPackages=function() return h.installed and {"DGHUDRecovery"} or {} end
    getPackageInfo=function(name,key) if name=="DGHUDRecovery" and key=="version" and h.installed then return h.version end end
    registerAnonymousEventHandler=function(name,fn) h.nextID=h.nextID+1; h.handlers[name]=fn; return h.nextID end
    killAnonymousEventHandler=function() end
    tempTimer=function(delay,fn) h.nextID=h.nextID+1; h.timers[h.nextID]={delay=delay,fn=fn}; return h.nextID end
    killTimer=function(id) h.timers[id]=nil end
    tempAlias=function(_,fn) h.nextID=h.nextID+1; h.aliasFn=fn; return h.nextID end
    killAlias=function() return true end
    downloadFile=function(path,url) h.downloads[#h.downloads+1]={path=path,url=url}; return true end
    uninstallPackage=function() h.uninstalls=h.uninstalls+1; if h.busy>0 then h.busy=h.busy-1; return nil end; h.installed=false; h.version=nil; return true end
    installPackage=function() h.installs=h.installs+1; h.installed=true; if options.deferActivation then h.pendingRuntime=true else DGHUDRecovery={version=Adapter.recovery_version,owner=expectedOwner,repository=expectedRepository,alias=91,run=function() end} end; return true end
    cecho=function(message) h.messages[#h.messages+1]=message end
    function h:download() self.handlers.sysDownloadDone(nil,self.downloads[1].path) end
    function h:run(delay) for id,timer in pairs(self.timers) do if timer.delay==delay then self.timers[id]=nil; timer.fn(); if self.pendingRuntime then DGHUDRecovery={version=Adapter.recovery_version,owner=expectedOwner,repository=expectedRepository,alias=92,run=function() end}; self.pendingRuntime=nil end; return true end end return false end
    h.adapter=Adapter.new(); h.adapter.settings={github={owner=expectedOwner,repository=expectedRepository}}; body(h)
  end)
  for _,name in ipairs(names) do _G[name]=saved[name] end
  if not ok then error(err,0) end
end
test("current recovery companion is retained without a download",function()
  recoveryHarness({version="1.7.0",runtimeVersion="1.7.0"},function(h) eq(h.adapter:ensureRecoveryPackage(),true); eq(#h.downloads,0); eq(h.uninstalls,0) end)
end)
test("previous recovery companion is upgraded so clean-view recovery reaches existing users",function()
  recoveryHarness({version="1.6.0",runtimeVersion="1.6.0"},function(h) eq(h.adapter:ensureRecoveryPackage(),true); eq(#h.downloads,1); eq(h.uninstalls,0) end)
end)
test("package metadata alone cannot prove recovery runtime activation",function()
  recoveryHarness({version="1.7.0"},function(h) eq(h.adapter:ensureRecoveryPackage(),true); eq(#h.downloads,1); eq(h.uninstalls,0) end)
end)
test("recovery runtime without a callable registered alias is replaced",function()
  recoveryHarness({version="1.7.0",runtimeVersion="1.7.0",runtimeAlias=0},function(h) eq(h.adapter:ensureRecoveryPackage(),true); eq(#h.downloads,1) end)
end)
test("recovery companion from the other HUD edition is replaced",function()
  recoveryHarness({version="1.7.0",runtimeVersion="1.7.0",runtimeRepository="dragons-gate-staff-hud"},function(h) eq(h.adapter:ensureRecoveryPackage(),true); eq(#h.downloads,1) end)
end)
test("outdated recovery companion waits out a save and verifies deferred activation",function()
  recoveryHarness({version="1.0.0",runtimeVersion="1.0.0",busy=1,deferActivation=true},function(h)
    eq(h.adapter:ensureRecoveryPackage(),true); eq(#h.downloads,1); h:download(); eq(h.uninstalls,1); eq(h.installs,0); eq(h.adapter.recovery_installing,true)
    assert(h:run(.10)); eq(h.uninstalls,2); eq(h.installs,1); eq(h.adapter.recovery_installing,true)
    assert(h:run(.25)); eq(h.adapter.recovery_installing,false); eq(DGHUDRecovery.version,"1.7.0"); eq(DGHUDRecovery.repository,"dragons-gate-player-hud"); assert(DGHUDRecovery.alias>0); eq(type(DGHUDRecovery.run),"function"); eq(#h.messages,0)
  end)
end)
test("stable manifest downloads avoid slow cache-busting redirects",function()
  local url=Adapter.manifestUrl({owner="wizzydizzy-ctrl",repository="dragons-gate-hud"},1788221000)
  eq(url,"https://github.com/wizzydizzy-ctrl/dragons-gate-hud/releases/latest/download/manifest.json")
  eq(Adapter.versionManifestUrl({owner="wizzydizzy-ctrl",repository="dragons-gate-hud"},"1.2.3",1788221000),"https://github.com/wizzydizzy-ctrl/dragons-gate-hud/releases/download/v1.2.3/manifest.json")
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
test("replacement failure before package mutation does not reinstall a healthy HUD",function()
  local rolledBack=false; local result
  local adapter={replacePackageAsync=function(_,_,_,done) done(nil,"preflight failed; nothing was removed",false) end,rollbackAsync=function() rolledBack=true end}
  Updater.new(adapter,{}):installVerifiedAsync("payload",SHA.hex("payload"),function(ok,err) result={ok,err} end)
  eq(rolledBack,false); eq(result[1],nil); eq(result[2],"preflight failed; nothing was removed")
end)
test("manifest compatibility blocks replacement on an older known Mudlet",function()
  local u=Updater.new({mudletVersion=function() return "4.17.2" end},updateSettings)
  local ok,err=u:validateManifest(releaseManifest("0.2.84")); eq(ok,nil); assert(err:find("older than required",1,true))
end)
test("post-install refresh joins rather than restarts the new controller startup sequence",function()
  local prior=_G.DGHUD; local entries=0; local refreshed=0
  local collector={active=nil,refreshed=false,refresh=function(self) refreshed=refreshed+1; self.refreshed=true; self.active={command="inventory"}; return true end}
  _G.DGHUD={controller={character_entry_started=false,onCharacterEntry=function(self) entries=entries+1; self.character_entry_started=true; return true end,collector=collector}}
  local ok,err=pcall(function() eq(Adapter.new():refreshCharacterData(),true); eq(Adapter.new():refreshCharacterData(),true); eq(Adapter.new():refreshCharacterData(),true) end)
  _G.DGHUD=prior; if not ok then error(err,0) end
  eq(entries,1); eq(refreshed,1)
end)
test("retiring updater leaves reinstall refresh for the new package",function()
  local prior=_G.DGHUD; local entries=0
  _G.DGHUD={_update_reinstall_pending=true,controller={onCharacterEntry=function() entries=entries+1 end}}
  local ok,err=pcall(function() eq(Adapter.new():refreshCharacterData(),true); eq(DGHUD._update_reinstall_pending,true); eq(entries,0) end)
  _G.DGHUD=prior; if not ok then error(err,0) end
end)
test("Mudlet activity detection survives asynchronous non-prompt output",function()
  local oldDGHUD,oldCurrent=DGHUD,getCurrentLine; DGHUD={controller={character_entry_started=true}}; getCurrentLine=function() return "The dark hound claws at you!" end
  local ok,err=pcall(function() eq(Adapter.new():isCharacterActive(),true) end); DGHUD,getCurrentLine=oldDGHUD,oldCurrent; if not ok then error(err,0) end
end)
test("Mudlet menu evidence overrides stale character activity",function()
  local oldDGHUD,oldCurrent=DGHUD,getCurrentLine; DGHUD={controller={character_entry_started=true}}; getCurrentLine=function() return "Your selection, GM?" end
  local ok,err=pcall(function() eq(Adapter.new():isCharacterActive(),false) end); DGHUD,getCurrentLine=oldDGHUD,oldCurrent; if not ok then error(err,0) end
end)
test("Mudlet version adapter captures the API numeric tuple",function()
  local prior=_G.getMudletVersion; _G.getMudletVersion=function(mode) eq(mode,"table"); return 5,0,1 end
  local value=Adapter.new():mudletVersion(); _G.getMudletVersion=prior
  eq(value[1],5); eq(value[2],0); eq(value[3],1)
end)
test("successful package replacement relies on native activation without resetting profile",function()
  local oldSave,oldReset,oldTimer=_G.saveProfile,_G.resetProfile,_G.tempTimer; local saved,reloaded,timers=0,0,0
  saveProfile=function() saved=saved+1 end; resetProfile=function() reloaded=reloaded+1 end; tempTimer=function() timers=timers+1; return 1 end
  local ok,err=Adapter.new():activateInstalledHUD(); saveProfile,resetProfile,tempTimer=oldSave,oldReset,oldTimer
  eq(ok,true); eq(err,nil); eq(saved,0); eq(reloaded,0); eq(timers,0)
end)
local function replacementHarness(options,body)
  options=options or {}; local globalNames={"lfs","yajl","getMudletHomeDir","registerAnonymousEventHandler","killAnonymousEventHandler","tempTimer","killTimer","downloadFile","getPackages","uninstallPackage","installPackage","cecho","DGHUD","getMudletVersion"}
  globalNames[#globalNames+1]="getEpoch"
  for _,name in ipairs({"send","sendAll","expandAlias","DGHUDMigration","DGHUDRecovery"}) do globalNames[#globalNames+1]=name end
  local saved={}; for _,name in ipairs(globalNames) do saved[name]=_G[name] end
  local originalOpen,originalRename,originalRemove=io.open,os.rename,os.remove; local h={files={},downloads={},handlers={},timers={},nextID=0,active=true,uninstalls=0,installs={},result=nil,targetUninstallBusy=tonumber(options.targetUninstallBusy) or 0,rollbackUninstallBusy=tonumber(options.rollbackUninstallBusy) or 0}
  local installedVersion=options.legacyRollbackManifest and "0.3.32" or "0.2.83"
  local target=releaseManifest(options.legacyRollbackManifest and "0.3.33" or "0.2.84"); target.sha256=SHA.hex("new-package")
  local rollback=releaseManifest(installedVersion); rollback.sha256=SHA.hex("old-package")
  if options.legacyRollbackManifest then rollback.view_contract=nil end
  h.manifests={latest={tag_name="v"..target.version},target=target,rollback=rollback}
  local harnessSettings={version=installedVersion,github=updateSettings.github,update=updateSettings.update}
  local originalHex=SHA.hex; local originalPrepare=Adapter.prepareDataDirectory
  local function restore() SHA.hex=originalHex; Adapter.prepareDataDirectory=originalPrepare; io.open=originalOpen; os.rename,os.remove=originalRename,originalRemove; for _,name in ipairs(globalNames) do _G[name]=saved[name] end end
  local ok,err=pcall(function()
    h.hashCalls=0; SHA.hex=function(payload) h.hashCalls=h.hashCalls+1; return originalHex(payload) end
    if options.prepareWarning then Adapter.prepareDataDirectory=function() return true,options.prepareWarning end end
    io.open=function(path,mode)
      if mode=="wb" and options.failRollbackStage and path=="/profile/DGHUDUpdater/previous.mpackage.writing" then return nil,"disk full" end
      if mode=="rb" and h.files[path]==nil then return nil end
      return {read=function() return h.files[path] end,write=function(_,data) h.files[path]=data; return true end,close=function() return true end}
    end
    os.remove=function(path) h.files[path]=nil; return true end
    os.rename=function(source,destination) if h.files[source]==nil then return nil,"missing" end; h.files[destination]=h.files[source]; h.files[source]=nil; return true end
    lfs={mkdir=function() return true end,symlinkattributes=function() return nil end}; getMudletHomeDir=function() return "/profile" end; getMudletVersion=nil
    yajl={to_value=function(raw) return assert(h.manifests[raw],"unexpected manifest payload") end}
    registerAnonymousEventHandler=function(name,fn) h.nextID=h.nextID+1; h.handlers[name]=fn; return h.nextID end
    killAnonymousEventHandler=function() end
    tempTimer=function(delay,fn) h.nextID=h.nextID+1; h.timers[h.nextID]={delay=delay,fn=fn}; return h.nextID end
    killTimer=function(id) h.timers[id]=nil end
    downloadFile=function(path,url) h.downloads[#h.downloads+1]={path=path,url=url}; if options.initialDownloadFails and #h.downloads==1 then return false,"offline" end; return true end
    getPackages=function() return h.active and {"DragonsGateHUD"} or {} end
    uninstallPackage=function()
      h.uninstalls=h.uninstalls+1
      if h.targetUninstallBusy>0 then h.targetUninstallBusy=h.targetUninstallBusy-1; return false end
      if h.uninstalls>1 and h.rollbackUninstallBusy>0 then h.rollbackUninstallBusy=h.rollbackUninstallBusy-1; return nil end
      h.active=false
      return true
    end
    installPackage=function(path)
      h.installs[#h.installs+1]=path
      h.handoffAtInstall={pending=DGHUD and DGHUD._update_reinstall_pending,controller=DGHUD and DGHUD.controller and DGHUD.controller.update_handoff}
      if options.failTarget and path==Adapter.updateArchivePath("/profile") then return nil end
      h.active=true
      local version=path=="/profile/DGHUDUpdater/DragonsGateHUD.mpackage" and rollback.version or target.version
      if not (options.suppressTargetActivation and version==target.version) then
        if (options.deferTargetActivation and version==target.version) or (options.deferRollbackActivation and version==rollback.version) then h.pendingVersion=version else DGHUD={settings={version=version},healthCheck=function() return true end} end
      end
      return true
    end
    h.messages={}; h.now=0; getEpoch=function() return h.now end
    h.failures={}; h.executions=0; h.completions=0
    local function executed() h.executions=h.executions+1 end
    send=executed; sendAll=executed; expandAlias=executed; DGHUDMigration={run=executed}; DGHUDRecovery={run=executed}
    cecho=function(message) h.messages[#h.messages+1]=message end
    DGHUD={settings={version=rollback.version},controller={captureFailure=function(self,category,message,context)
      eq(self,DGHUD.controller); h.failures[#h.failures+1]={category=category,message=message,context=context}
    end},shutdown=function() end,healthCheck=function() return true end}
    function h:done(path,payload) self.files[path]=payload; self.handlers.sysDownloadDone(nil,path) end
    function h:error(url,message) self.handlers.sysDownloadError(nil,message or "download failed",url) end
    function h:run(delay) for id,timer in pairs(self.timers) do if timer.delay==delay then self.timers[id]=nil; timer.fn(); if self.pendingVersion then DGHUD={settings={version=self.pendingVersion},healthCheck=function() return true end}; self.pendingVersion=nil end; return true end end return false end
    h.adapter=Adapter.new(); h.updater=Updater.new(h.adapter,harnessSettings)
    if not options.manualStart then
      assert(h.updater:update(function(success,message) h.completions=h.completions+1; h.result={success,message} end,options.manifest,options.manifestRaw))
    end
    body(h)
  end)
  restore(); if not ok then error(err,0) end
end
local function deliverTarget(h)
  h:done(h.downloads[1].path,"target")
  h:done(h.downloads[2].path,"new-package")
end

local safeUpgradePrefix="persistent data preflight failed; nothing was removed: "
local safeUpgradeReason="persistent destination differs; run the DGHUD safe-upgrade bridge"
local safeUpgradeConflict=safeUpgradePrefix.."/profile/DragonsGateHUD/roller-settings.lua: "..safeUpgradeReason
local otherUpdateErrors={
  "disk full",
  safeUpgradePrefix.."disk read failed",
  safeUpgradePrefix.."could not write copied data",
  "download timed out",
  "could not stage rollback package: disk full",
  "could not install HUD package; rollback failed: could not restore rollback package",
  "rollback data preflight failed; nothing was removed: "..safeUpgradeReason,
  "could not install HUD package; rollback failed: "..safeUpgradeConflict,
  safeUpgradeConflict.."; rollback failed: "..safeUpgradeReason,
  "quoted error: "..safeUpgradeConflict,
  " "..safeUpgradeConflict,
  "\n"..safeUpgradeConflict,
  safeUpgradeReason,
  safeUpgradePrefix..safeUpgradeReason..".",
  safeUpgradePrefix..safeUpgradeReason.." ",
  safeUpgradePrefix..safeUpgradeReason.."\n",
  safeUpgradePrefix..safeUpgradeReason.." (previous attempt)",
  safeUpgradePrefix.."persistent destination differs",
  safeUpgradePrefix.."persistent destination differs; run the DGHUD safe-upgrade bridges",
}
local function assertFailureDiagnostic(h,message)
  eq(#h.failures,1)
  eq(h.failures[1].category,"updater"); eq(h.failures[1].message,message)
  eq(h.failures[1].context.operation,"update_install"); eq(h.failures[1].context.stage,"install")
end
local function assertSafeUpgradeAdvice(output,edition)
  local command='lua installPackage("https://github.com/wizzydizzy-ctrl/dragons-gate-'..edition..'-hud/releases/latest/download/DGHUDMigration.mpackage")'
  assert(output:find("Nothing was deleted.",1,true))
  -- A committed marker can suppress bridge autorun, so the retry advice repeats the command.
  assert(output:find("If nothing starts, run <white>dghud safe update<reset> again.",1,true))
  local _,commandMentions=output:gsub("dghud safe update","")
  eq(commandMentions,2)
  local _,friendlyBlocks=output:gsub("Update stopped safely%. Nothing was deleted%.","")
  eq(friendlyBlocks,1)
  assert(output:find('unknown command',1,true))
  assert(output:find(command,1,true))
  eq(output:find(safeUpgradePrefix,1,true),nil)
  eq(output:find(safeUpgradeReason,1,true),nil)
  eq(output:find("Update failed:",1,true),nil)
  eq(output:find("REPORT A PROBLEM",1,true),nil)
  local otherEdition=edition=="staff" and "player" or "staff"
  eq(output:find("dragons-gate-"..otherEdition.."-hud",1,true),nil)
end
local function assertNoRecoveryExecution(h)
  eq(h.executions,0); eq(#h.installs,0); eq(h.uninstalls,0)
end

test("safe-upgrade classifier accepts the exact persistent conflict with optional path context",function()
  eq(Adapter.isSafeUpgradeConflict(safeUpgradePrefix..safeUpgradeReason),true)
  eq(Adapter.isSafeUpgradeConflict(safeUpgradeConflict),true)
end)
test("safe-upgrade classifier rejects unrelated failures and prefix suffix or rollback lookalikes",function()
  for _,message in ipairs(otherUpdateErrors) do
    assert(Adapter.isSafeUpgradeConflict(message)==false,"misclassified: "..message)
  end
end)
test("safe-upgrade classifier rejects nonstring values without coercion",function()
  eq(Adapter.isSafeUpgradeConflict(nil),false)
  for _,message in ipairs({false,true,0,{},function() end,setmetatable({},{__tostring=function() return safeUpgradeConflict end})}) do
    eq(Adapter.isSafeUpgradeConflict(message),false)
  end
  eq(Adapter.isSafeUpgradeConflict(""),false)
end)

for _,edition in ipairs({"player","staff"}) do
  test("safe-upgrade advice uses the fixed official "..edition.." URL and retains raw diagnostics",function()
    replacementHarness({manualStart=true},function(h)
      h.adapter.settings={edition=edition,github={owner='untrusted.example");send("injected")--',repository="untrusted-hud"}}
      local message=safeUpgradePrefix.."https://untrusted.example/legacy.lua: "..safeUpgradeReason
      h.adapter:reportUpdateFailure(message)
      eq(#h.messages,1); assertSafeUpgradeAdvice(h.messages[1],edition)
      eq(h.messages[1]:find("untrusted",1,true),nil)
      assertFailureDiagnostic(h,message)
      assertNoRecoveryExecution(h); eq(#h.downloads,0); eq(next(h.timers),nil); eq(next(h.handlers),nil); eq(next(h.files),nil)
    end)
  end)
end

test("safe-upgrade advice falls back to this repository edition when adapter edition is absent",function()
  replacementHarness({manualStart=true},function(h)
    local expectedEdition="player"
    eq(require("defaults").edition,expectedEdition)
    for _,settings in ipairs({false,{},{github={owner="untrusted",repository="untrusted-hud"}}}) do
      h.adapter.settings=settings or nil; h.messages={}; h.failures={}
      h.adapter:reportUpdateFailure(safeUpgradeConflict)
      eq(#h.messages,1); assertSafeUpgradeAdvice(h.messages[1],expectedEdition)
      assertFailureDiagnostic(h,safeUpgradeConflict)
    end
    assertNoRecoveryExecution(h); eq(#h.downloads,0); eq(next(h.timers),nil)
  end)
end)
test("safe-upgrade advice remains available without a diagnostics controller",function()
  replacementHarness({manualStart=true},function(h)
    for _,hud in ipairs({false,{},{controller={}}}) do
      DGHUD=hud or nil; h.messages={}
      h.adapter:reportUpdateFailure(safeUpgradeConflict)
      eq(#h.messages,1); assertSafeUpgradeAdvice(h.messages[1],"player")
    end
    eq(#h.failures,0); assertNoRecoveryExecution(h); eq(#h.downloads,0); eq(next(h.timers),nil)
  end)
end)
test("nonmatching update failures retain the original display and diagnostic without recovery advice",function()
  replacementHarness({manualStart=true},function(h)
    for _,message in ipairs(otherUpdateErrors) do
      h.messages={}; h.failures={}
      h.adapter:reportUpdateFailure(message)
      eq(#h.messages,1)
      eq(h.messages[1],"\n<red>[DGHUD Update]<reset> Update failed: "..message..". A privacy-safe report is ready under Map Library > REPORT A PROBLEM.\n")
      eq(h.messages[1]:find("Nothing was deleted.",1,true),nil)
      eq(h.messages[1]:find("dghud safe update",1,true),nil)
      eq(h.messages[1]:find("DGHUDMigration.mpackage",1,true),nil)
      assertFailureDiagnostic(h,message)
    end
    assertNoRecoveryExecution(h); eq(#h.downloads,0); eq(next(h.timers),nil)
  end)
end)
test("persistent conflict during an update reports friendly advice once and returns the raw failure",function()
  local reason="/profile/DragonsGateHUD/roller-settings.lua: "..safeUpgradeReason
  replacementHarness({prepareWarning=reason},function(h)
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h:done(h.downloads[4].path,"old-package")
    eq(h.completions,1); eq(h.result[1],nil); eq(h.result[2],safeUpgradeConflict)
    assertFailureDiagnostic(h,safeUpgradeConflict)
    assertSafeUpgradeAdvice(table.concat(h.messages),"player")
    local adviceCount=0
    for _,message in ipairs(h.messages) do if message:find("Nothing was deleted.",1,true) then adviceCount=adviceCount+1 end end
    eq(adviceCount,1); assertNoRecoveryExecution(h); eq(#h.downloads,4); eq(h.active,true)
    eq(h.updater.lock,nil); eq(h.updater.expected_path,nil); eq(next(h.timers),nil)
  end)
end)
test("startUpdate suppresses the raw conflict only when a callback receives it unchanged",function()
  replacementHarness({manualStart=true,prepareWarning=safeUpgradeReason},function(h)
    local calls=0; local result
    assert(h.updater:acquire("update"))
    assert(h.adapter:startUpdate(h.updater,function(...) calls=calls+1; result={n=select("#",...),...} end))
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h:done(h.downloads[4].path,"old-package")
    eq(calls,1); eq(result.n,2); eq(result[1],nil); eq(result[2],safeUpgradePrefix..safeUpgradeReason)
    local output=table.concat(h.messages)
    eq(output:find(safeUpgradeReason,1,true),nil); eq(output:find("Nothing was deleted.",1,true),nil)
    eq(#h.failures,0); assertNoRecoveryExecution(h); eq(h.active,true)
    eq(h.updater.lock,nil); eq(next(h.timers),nil)
  end)
end)
test("startUpdate without a callback keeps the raw persistent conflict visible",function()
  replacementHarness({manualStart=true,prepareWarning=safeUpgradeReason},function(h)
    assert(h.updater:acquire("update")); assert(h.adapter:startUpdate(h.updater))
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h:done(h.downloads[4].path,"old-package")
    local expected="\n<red>[DGHUD Update]<reset> "..safeUpgradePrefix..safeUpgradeReason.."\n"
    eq(h.messages[#h.messages],expected)
    local rawCount=0
    for _,message in ipairs(h.messages) do if message==expected then rawCount=rawCount+1 end end
    eq(rawCount,1); eq(table.concat(h.messages):find("Nothing was deleted.",1,true),nil)
    eq(#h.failures,0); assertNoRecoveryExecution(h); eq(h.active,true)
    eq(h.updater.lock,nil); eq(next(h.timers),nil)
  end)
end)
test("startUpdate keeps nonmatching raw failures visible with a callback",function()
  for _,message in ipairs(otherUpdateErrors) do
    replacementHarness({manualStart=true},function(h)
      local calls=0; local result
      assert(h.updater:acquire("update"))
      assert(h.adapter:startUpdate(h.updater,function(...) calls=calls+1; result={n=select("#",...),...} end))
      h.messages={}
      h:error(h.downloads[1].url,message)
      eq(calls,1); eq(result.n,2); eq(result[1],nil); eq(result[2],message)
      eq(#h.messages,1); eq(h.messages[1],"\n<red>[DGHUD Update]<reset> "..message.."\n")
      h:error(h.downloads[1].url,message)
      eq(calls,1); eq(#h.messages,1)
      eq(#h.failures,0); assertNoRecoveryExecution(h)
      eq(h.updater.lock,nil); eq(next(h.timers),nil)
    end)
  end
end)

test("update can bootstrap a checksum-verified exact legacy rollback manifest",function()
  replacementHarness({legacyRollbackManifest=true},function(h)
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h:done(h.downloads[4].path,"old-package")
    eq(h.result[1],true); eq(h.uninstalls,1); eq(h.files["/profile/DGHUDUpdater/previous.mpackage"],"old-package")
  end)
end)
test("first updater-managed update bootstraps exact rollback before uninstall",function()
  replacementHarness({},function(h)
    deliverTarget(h); eq(h.uninstalls,0); eq(#h.downloads,3)
    assert(h.downloads[3].url:find("/releases/download/v0.2.83/manifest.json",1,true)); h.handlers.sysDownloadDone(nil,"/unowned/path"); h:error("https://unrelated.example/failure","ignore me"); eq(h.uninstalls,0)
    h:done(h.downloads[3].path,"rollback"); eq(h.uninstalls,0); eq(#h.downloads,4)
    h:done(h.downloads[4].path,"old-package"); eq(h.uninstalls,1); eq(h.handoffAtInstall.pending,true); eq(h.handoffAtInstall.controller,true); eq(h.files["/profile/DGHUDUpdater/previous.mpackage"],"old-package")
    eq(h.result[1],true); eq(h.active,true); eq(h.hashCalls,2); eq(h:run(.10),false)
  end)
end)
test("target replacement waits when Mudlet returns false during a profile save",function()
  replacementHarness({targetUninstallBusy=1},function(h)
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h:done(h.downloads[4].path,"old-package")
    eq(h.uninstalls,1); eq(#h.installs,0); eq(h.result,nil); eq(h.active,true)
    assert(h:run(.10)); eq(h.uninstalls,2); eq(#h.installs,1); eq(h.result[1],true); eq(DGHUD.settings.version,"0.2.84")
  end)
end)
test("persistent data preflight aborts before removing the active package",function()
  replacementHarness({prepareWarning="legacy map copy was denied"},function(h)
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h:done(h.downloads[4].path,"old-package")
    eq(h.uninstalls,0); eq(#h.installs,0); eq(h.active,true); eq(h.result[1],nil)
    assert(h.result[2]:find("persistent data preflight failed",1,true))
  end)
end)
test("rollback staging write failure aborts before removing the active package",function()
  replacementHarness({failRollbackStage=true},function(h)
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h:done(h.downloads[4].path,"old-package")
    eq(h.uninstalls,0); eq(#h.installs,0); eq(h.active,true); eq(h.result[1],nil); assert(h.result[2]:find("could not stage rollback package",1,true))
  end)
end)
test("a download that cannot start fails immediately and releases the updater",function()
  replacementHarness({initialDownloadFails=true},function(h)
    eq(#h.downloads,1); eq(h.result[1],false); assert(h.result[2]:find("offline",1,true)); eq(h.updater.lock,nil); eq(h.uninstalls,0)
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
    eq(h.uninstalls,1); eq(h.active,true); eq(h.installs[#h.installs],"/profile/DGHUDUpdater/DragonsGateHUD.mpackage"); eq(h.files[h.installs[#h.installs]],"old-package"); eq(h.result[1],nil); assert(h.result[2]:find("could not install HUD package",1,true))
  end)
end)
test("registered target without a healthy runtime rolls back before reporting failure",function()
  replacementHarness({suppressTargetActivation=true},function(h)
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h:done(h.downloads[4].path,"old-package")
    for _=1,12 do assert(h:run(.25)) end
    eq(h.result[1],nil); assert(h.result[2]:find("did not activate",1,true)); eq(DGHUD.settings.version,"0.2.83")
  end)
end)
test("rollback waits out an active Mudlet profile save before replacing the failed package",function()
  replacementHarness({suppressTargetActivation=true,rollbackUninstallBusy=2},function(h)
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h:done(h.downloads[4].path,"old-package")
    for _=1,12 do assert(h:run(.25)) end
    eq(h.result,nil); eq(#h.installs,1); eq(h.active,true)
    assert(h:run(.10)); eq(h.result,nil); eq(#h.installs,1)
    assert(h:run(.10)); eq(h.result[1],nil); eq(h.installs[#h.installs],"/profile/DGHUDUpdater/DragonsGateHUD.mpackage"); eq(DGHUD.settings.version,"0.2.83")
  end)
end)
test("rollback accepts a queued install only after its exact runtime activates",function()
  replacementHarness({suppressTargetActivation=true,deferRollbackActivation=true,rollbackUninstallBusy=1},function(h)
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h:done(h.downloads[4].path,"old-package")
    for _=1,12 do assert(h:run(.25)) end
    eq(h.result,nil); assert(h:run(.10)); eq(h.result,nil); assert(h:run(.25)); eq(h.result[1],nil); eq(DGHUD.settings.version,"0.2.83")
  end)
end)
test("startup check skips installation when current and continues startup",function()
  local order={}; local completed
  local adapter={checkLatestAsync=function(_,updater,done) order[#order+1]="check"; done(releaseManifest("0.2.83")) end}
  local u=Updater.new(adapter,updateSettings)
  eq(u:checkAtCharacterEntry(function(updated,err) completed={updated,err}; order[#order+1]="commands" end),true)
  eq(table.concat(order,","),"check,commands"); eq(completed[1],false); eq(completed[2],nil); eq(u.lock,nil)
end)
test("manual check reports installed and latest versions",function()
  local reported; local result
  local adapter={checkLatestAsync=function(_,_,done) done(releaseManifest("0.2.83")) end,reportVersionStatus=function(_,installed,latest,current) reported={installed,latest,current} end}
  local u=Updater.new(adapter,updateSettings)
  assert(u:check(function(value,err) result={value,err} end))
  eq(reported[1],"0.2.83"); eq(reported[2],"0.2.83"); eq(reported[3],true)
  eq(result[1].installed,"0.2.83"); eq(result[1].current,true); eq(u.lock,nil)
end)
test("manual update skips package replacement when already current",function()
  local reported; local replaced=false; local result
  local adapter={checkLatestAsync=function(_,_,done) done(releaseManifest("0.2.83"),nil,"raw") end,reportVersionStatus=function(_,installed,latest,current) reported={installed,latest,current} end,startUpdate=function() replaced=true end,updateClock=function() return 0 end}
  local u=Updater.new(adapter,updateSettings)
  assert(u:update(function(updated,err) result={updated,err} end))
  eq(replaced,false); eq(reported[1],"0.2.83"); eq(reported[3],true)
  eq(result[1],false); eq(result[2],nil); eq(u.lock,nil)
end)
test("startup check reports an update without replacing the running HUD",function()
  local order={}; local completed; local reported
  local adapter={
    checkLatestAsync=function(_,updater,done) order[#order+1]="check"; done(releaseManifest("0.2.84"),nil,"validated-raw") end,
    startUpdate=function() error("login check must not replace the package") end,
    reportVersionStatus=function(_,installed,latest,current) reported={installed,latest,current} end,
  }
  local u=Updater.new(adapter,updateSettings)
  eq(u:checkAtCharacterEntry(function(updated,err) completed={updated,err}; order[#order+1]="commands" end),true)
  eq(table.concat(order,","),"check,commands"); eq(completed[1],false); eq(completed[2],"update available; run dghud update"); eq(u.lock,nil)
  eq(reported[1],"0.2.83"); eq(reported[2],"0.2.84"); eq(reported[3],false)
end)
test("manual update fetches latest manifest exactly once and reports timed stages",function()
  replacementHarness({},function(h)
    eq(#h.downloads,1); assert(h.downloads[1].url:find("/releases/latest/download/manifest.json",1,true)); eq(h.downloads[1].url:find("api.github.com",1,true),nil)
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h.now=1.2; h:done(h.downloads[4].path,"old-package")
    eq(h.result[1],true)
    local output=table.concat(h.messages)
    assert(output:find("Checking",1,true)); assert(output:find("Downloading package",1,true)); assert(output:find("Preparing rollback",1,true)); assert(output:find("Installing",1,true)); assert(output:find("Completed",1,true)); assert(output:find("1.2s",1,true))
  end)
end)
test("startup update reuses its validated manifest without another manifest download",function()
  local manifest=releaseManifest("0.2.84"); manifest.sha256=SHA.hex("new-package")
  replacementHarness({manifest=manifest,manifestRaw="target"},function(h)
    eq(#h.downloads,1); eq(h.downloads[1].path,Adapter.updateArchivePath("/profile")); eq(h.downloads[1].url,manifest.archive_url)
    h:done(h.downloads[1].path,"new-package"); eq(#h.downloads,2)
    assert(h.downloads[2].url:find("/releases/download/v0.2.83/manifest.json",1,true))
    h:done(h.downloads[2].path,"rollback"); h:done(h.downloads[3].path,"old-package")
    eq(h.result[1],true)
  end)
end)
test("deferred Mudlet activation is still health-checked after the fast handoff",function()
  replacementHarness({deferTargetActivation=true},function(h)
    deliverTarget(h); h:done(h.downloads[3].path,"rollback"); h:done(h.downloads[4].path,"old-package")
    eq(h.result,nil); assert(h:run(.25)); assert(h:run(.25)); eq(h.result[1],true)
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
