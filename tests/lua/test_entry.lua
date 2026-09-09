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
  function Main.new(_,settings,viewHandoff)
    local controller={adapter=adapter,settings=settings,view_handoff=viewHandoff,reloads=0,starts=0,shutdowns=0}
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
