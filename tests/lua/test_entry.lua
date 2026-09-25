local Settings=require("settings")

local entryModules={"defaults","settings","mudlet_adapter","main","updater","chat_storage"}

local function withEntryStubs(fn)
  local savedGlobal=rawget(_G,"DGHUD")
  local savedMudletHome=rawget(_G,"getMudletHomeDir")
  getMudletHomeDir=function() return "/profile" end
  local savedPreload,savedLoaded={},{}
  for _,name in ipairs(entryModules) do
    savedPreload[name]=package.preload[name]
    savedLoaded[name]=package.loaded[name]
    package.loaded[name]=nil
  end
  local controllers={}
  local defaults={schema=1,chat={enabled=true,height_percent=.21,target_height=240,min_height=160,max_height=320,visible_limit=1000,dedupe_seconds=3,timestamps=true}}
  local adapter={}
  local Main={}
  function Main.new(_,settings,viewHandoff,chatHandoff)
    local controller={adapter=adapter,settings=settings,view_handoff=viewHandoff,chat_handoff=chatHandoff,reloads=0,starts=0,shutdowns=0}
    function controller:start() self.starts=self.starts+1; if adapter.failStart then return nil,adapter.failStart end; return true end
    function controller:shutdown() self.shutdowns=self.shutdowns+1; return true end
    function controller:reload() self.reloads=self.reloads+1; return true end
    function controller:healthCheck() return true end
    controllers[#controllers+1]=controller
    return controller
  end
  function Main.installChatApi(namespace) namespace.chat={}; return namespace.chat end
  local Adapter={new=function() return adapter end}
  local Updater={new=function(_,settings) return {settings=settings} end}
  local Storage={mudletApi=function() return {} end}
  local stubs={
    defaults=function() return defaults end,
    settings=function() return Settings end,
    mudlet_adapter=function() return Adapter end,
    main=function() return Main end,
    updater=function() return Updater end,
    chat_storage=function() return Storage end,
  }
  local function install(name,loader) package.preload[name]=loader end
  for name,loader in pairs(stubs) do install(name,loader) end
  local ok,result=xpcall(function() return fn({defaults=defaults,controllers=controllers,stubs=stubs,install=install,adapter=adapter}) end,debug.traceback)
  for _,name in ipairs(entryModules) do package.preload[name]=savedPreload[name]; package.loaded[name]=savedLoaded[name] end
  rawset(_G,"DGHUD",savedGlobal)
  rawset(_G,"getMudletHomeDir",savedMudletHome)
  if not ok then error(result,0) end
  return result
end

test("public reload re-resolves current nested user settings without replacing unknown keys",function()
  withEntryStubs(function(context)
    DGHUD={user_settings={chat={height_percent=.25,personal_option="keep"},personal="untouched"},shutdown=function() return true end}
    dofile("src/entry.lua")
    eq(DGHUD.settings.chat.height_percent,.25)
    DGHUD.user_settings.chat.height_percent=.30
    eq(DGHUD.reload(),true)
    eq(DGHUD.settings.chat.height_percent,.30)
    eq(DGHUD.settings.chat.personal_option,"keep")
    eq(DGHUD.settings.personal,"untouched")
    eq(DGHUD.controller.settings.chat.height_percent,.30)
    eq(DGHUD.updater.settings.chat.height_percent,.30)
  end)
end)

test("persisted hidden chat survives package replacement and public reload",function()
  withEntryStubs(function(context)
    context.defaults.chat.visible=true
    local persisted={visible=false,tab_order={"STAFF","ALL","ROOM"},all_sources={COMBAT=false,ROOM=true}}
    context.install("mudlet_adapter",function() return {loadChatSettings=function() return persisted end,new=function() return context.adapter end} end)
    DGHUD={user_settings={chat={visible=true,personal_option="keep"}},shutdown=function() return true end}
    dofile("src/entry.lua")
    eq(DGHUD.user_settings.chat.visible,false); eq(DGHUD.settings.chat.visible,false)
    eq(DGHUD.controller.settings.chat.visible,false); eq(DGHUD.settings.chat.enabled,true)
    eq(DGHUD.settings.chat.personal_option,"keep"); eq(DGHUD.settings.chat.tab_order[1],"STAFF")
    eq(DGHUD.settings.chat.all_sources.COMBAT,false)
    assert(DGHUD.reload()); eq(DGHUD.settings.chat.visible,false)
    eq(DGHUD.controller.settings.chat.visible,false)
  end)
end)
test("legacy color choices migrate once and survive a cold entry",function()
  withEntryStubs(function(context)
    local persisted,saves=nil,0
    context.install("mudlet_adapter",function() return {
      new=function() return context.adapter end,
      loadColorSettings=function() return persisted end,
      saveColorSettings=function(_,value) saves=saves+1; persisted=Settings.merge({},value); return true end,
    } end)
    DGHUD={user_settings={colorization={enabled=false,direction_color={12,34,56}}},shutdown=function() return true end}
    dofile("src/entry.lua"); eq(saves,1); eq(DGHUD.settings.colorization.enabled,false)
    DGHUD=nil; dofile("src/entry.lua")
    eq(saves,1); eq(DGHUD.settings.colorization.enabled,false); eq(DGHUD.settings.colorization.direction_color[2],34)
  end)
end)
test("unreadable color preferences are never overwritten by migration",function()
  for _,throws in ipairs({false,true}) do
    withEntryStubs(function(context)
      local saves=0
      context.install("mudlet_adapter",function() return {
        new=function() return context.adapter end,
        loadColorSettings=function() if throws then error("unavailable") end; return nil,"invalid data" end,
        saveColorSettings=function() saves=saves+1; return true end,
      } end)
      DGHUD={user_settings={colorization={enabled=false}},shutdown=function() return true end}
      dofile("src/entry.lua"); eq(saves,0); eq(DGHUD.settings.colorization.enabled,false); eq(DGHUD.healthCheck(),true)
    end)
  end
end)
test("failed legacy color migration preserves the active HUD and choices",function()
  withEntryStubs(function(context)
    context.install("mudlet_adapter",function() return {
      new=function() return context.adapter end,loadColorSettings=function() return nil end,
      saveColorSettings=function() return nil,"disk full" end,
    } end)
    DGHUD={user_settings={colorization={enabled=false}},shutdown=function() return true end}
    dofile("src/entry.lua"); eq(DGHUD.settings.colorization.enabled,false); eq(DGHUD.healthCheck(),true)
  end)
end)

test("persisted roller settings override stale live values during package replacement",function()
  withEntryStubs(function(context)
    context.defaults.roller={schema=3,target_total=53,hard_stop=62,max_rolls=false,arrange_mode="manual",minimum_greats=false,minimum_good_plus=false,auto_start_on_name=true,min_stats={STR=5,MP=5}}
    local persisted={schema=3,target_total=false,hard_stop=70,max_rolls=500,arrange_mode="minimums",minimum_greats=2,minimum_good_plus=5,auto_start_on_name=false,min_stats={STR=6,MP=false}}
    context.install("mudlet_adapter",function() return {loadRollerSettings=function() return persisted end,new=function() return context.adapter end} end)
    DGHUD={user_settings={roller={target_total=80,hard_stop=80,auto_start_on_name=true,min_stats={MP=7}}},shutdown=function() return true end}
    dofile("src/entry.lua")
    eq(DGHUD.user_settings.roller.target_total,false); eq(DGHUD.user_settings.roller.auto_start_on_name,false); eq(DGHUD.user_settings.roller.min_stats.MP,false)
    eq(DGHUD.settings.roller.target_total,false); eq(DGHUD.settings.roller.hard_stop,70); eq(DGHUD.settings.roller.max_rolls,500); eq(DGHUD.settings.roller.arrange_mode,"minimums"); eq(DGHUD.settings.roller.minimum_greats,2); eq(DGHUD.settings.roller.minimum_good_plus,5)
  end)
end)

test("persisted display settings override stale live preferences",function()
  withEntryStubs(function(context)
    context.defaults.display={side_text_scale=1}
    context.install("mudlet_adapter",function() return {loadDisplaySettings=function() return {side_text_scale=.9,auto_wrap=false} end,new=function() return context.adapter end} end)
    DGHUD={user_settings={display={side_text_scale=1.1,auto_wrap=true}},shutdown=function() return true end}
    dofile("src/entry.lua")
    eq(DGHUD.user_settings.display.side_text_scale,.9); eq(DGHUD.settings.display.side_text_scale,.9); eq(DGHUD.user_settings.display.auto_wrap,false); eq(DGHUD.settings.display.auto_wrap,false)
  end)
end)
test("persisted mapper submap choices override stale nested live values",function()
  withEntryStubs(function(context)
    context.defaults.mapper={schema=2,enabled=true,transition_submaps={gate=false,portal=false,door=false,arch=false,path=false,other=false}}
    context.install("mudlet_adapter",function() return {loadMapperSettings=function() return {schema=2,enabled=true,transition_submaps={gate=false,portal=false,door=true,arch=false,path=false,other=false}} end,new=function() return context.adapter end} end)
    DGHUD={user_settings={mapper={transition_submaps={gate=true,door=false},personal_option="keep"}},shutdown=function() return true end}
    dofile("src/entry.lua")
    eq(DGHUD.user_settings.mapper.transition_submaps.gate,false); eq(DGHUD.user_settings.mapper.transition_submaps.door,true)
    eq(DGHUD.settings.mapper.transition_submaps.gate,false); eq(DGHUD.settings.mapper.transition_submaps.door,true); eq(DGHUD.settings.mapper.personal_option,"keep")
  end)
end)

test("replacement handoff bypasses legacy map serialization before shutdown",function()
  withEntryStubs(function()
    local observed; local retiring={map_collections={large=true}}
    DGHUD={user_settings={},_update_reinstall_pending=true,controller=retiring,shutdown=function() observed=retiring.map_collections; return true end}
    dofile("src/entry.lua")
    eq(observed,nil)
    eq(retiring.update_handoff,true)
  end)
end)
test("replacement entry carries a preserved compatible view into the new controller",function()
  withEntryStubs(function(context)
    local handoff={schema=1,view={root={}}}
    DGHUD={user_settings={},_update_reinstall_pending=true,_view_handoff=handoff,controller={map_collections={}},shutdown=function() return true end}
    dofile("src/entry.lua")
    eq(DGHUD.controller.view_handoff,handoff); eq(DGHUD._view_handoff,nil)
  end)
end)
test("replacement entry carries the original manual wrap baseline",function()
  withEntryStubs(function()
    local retiring={map_collections={},original_main_console_wrap=141}
    DGHUD={user_settings={display={side_text_scale=1,auto_wrap=true}},_update_reinstall_pending=true,controller=retiring,shutdown=function() return true end}
    dofile("src/entry.lua")
    eq(DGHUD.controller.original_main_console_wrap,141); eq(DGHUD._main_wrap_baseline,nil)
  end)
end)
test("replacement entry carries live chat history and filter into the new controller",function()
  withEntryStubs(function()
    local history={lastKey="dedupe",lastEpoch=100}
    function history:entries() return {{category="DRAGON",message="still visible",timestamp="2026-09-11T21:00:00-04:00"}} end
    local retiring={map_collections={},chat={history=history,currentCharacterKey="wizzy",filter="DRAGON"}}
    DGHUD={user_settings={},_update_reinstall_pending=true,controller=retiring,shutdown=function() return true end}
    dofile("src/entry.lua")
    eq(DGHUD.controller.chat_handoff.character_key,"wizzy"); eq(DGHUD.controller.chat_handoff.filter,"DRAGON")
    eq(DGHUD.controller.chat_handoff.entries[1].message,"still visible"); eq(DGHUD._chat_handoff,nil)
  end)
end)

test("ordinary entry leaves map serialization available to shutdown",function()
  withEntryStubs(function()
    local collections={large=true}; local observed; local retiring={map_collections=collections}
    DGHUD={user_settings={},controller=retiring,shutdown=function() observed=retiring.map_collections; return true end}
    dofile("src/entry.lua")
    eq(observed,collections)
    eq(retiring.update_handoff,nil)
  end)
end)

test("failed entry replacement preserves settings for rollback before module loading",function()
  withEntryStubs(function(context)
    local overrides={chat={height_percent=.25,personal_option="keep"},personal="untouched"}
    DGHUD={user_settings=overrides,shutdown=function() return true end}
    context.install("defaults",function() error("new package failed while loading") end)
    local loaded=pcall(dofile,"src/entry.lua")
    eq(loaded,false)
    eq(DGHUD.user_settings,overrides)
    eq(DGHUD.user_settings.chat.personal_option,"keep")
    context.install("defaults",context.stubs.defaults)
    eq(pcall(dofile,"src/entry.lua"),true)
    eq(DGHUD.settings.chat.height_percent,.25)
    eq(DGHUD.settings.chat.personal_option,"keep")
    eq(DGHUD.settings.personal,"untouched")
  end)
end)

test("failed entry replacement preserves a direct capture wrapper for rollback",function()
  withEntryStubs(function(context)
    local oldChat={}
    function oldChat.capture()
      local active=rawget(_G,"DGHUD")
      if not (active and active.controller) then return nil,"chatbox is not running" end
      return true
    end
    DGHUD={user_settings={},chat=oldChat,shutdown=function() return true end}
    context.install("defaults",function() error("replacement require failed") end)
    eq(pcall(dofile,"src/entry.lua"),false)
    eq(DGHUD.chat,oldChat)
    local called,result,err=pcall(function() return DGHUD.chat.capture("QUEST","during rollback") end)
    eq(called,true); eq(result,nil); eq(err,"chatbox is not running")
  end)
end)

test("failed first entry load creates a fail-safe direct capture API",function()
  withEntryStubs(function(context)
    DGHUD={user_settings={},shutdown=function() return true end}
    context.install("defaults",function() error("initial require failed") end)
    eq(pcall(dofile,"src/entry.lua"),false)
    local called,result,err=pcall(function() return DGHUD.chat.capture("QUEST","during failure") end)
    eq(called,true); eq(result,nil); eq(err,"chatbox is not running")
  end)
end)

test("entry rejects a package whose HUD runtime does not start",function()
  withEntryStubs(function(context)
    DGHUD={user_settings={},shutdown=function() return true end}
    context.adapter.failStart="view construction failed"
    local loaded,message=pcall(dofile,"src/entry.lua")
    eq(loaded,false)
    assert(tostring(message):find("DGHUD startup failed: view construction failed",1,true))
  end)
end)
test("persistent data preparation failure warns without aborting HUD startup",function()
  withEntryStubs(function(context)
    context.install("mudlet_adapter",function() return {prepareDataDirectory=function() return nil,"permission denied" end,new=function() return context.adapter end} end)
    DGHUD={user_settings={},shutdown=function() return true end}
    eq(pcall(dofile,"src/entry.lua"),true); eq(DGHUD:healthCheck(),true)
  end)
end)
