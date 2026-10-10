local Main=require("main")
local Settings=require("settings")
local defaults=require("defaults")

-- Minimal in-memory runtime: no live Mudlet API, profile, map, or MUD access.
local function fake()
  local f={next=0,events={},aliases={},triggers={},timers={},sent={},saves=0,view_sets=0}
  function f:id() self.next=self.next+1; return self.next end
  function f:epoch() return 100 end
  function f:cleanupClock() return 100 end
  function f:localTime() return "12:00:00 PM" end
  function f:getWindowSize() return 1920,1080 end
  function f:setBorders() end
  function f:getGMCP() return self.gmcp or {Char={Status={},Vitals={hp=10,hp_max=10}}} end
  function f:isCharacterActive() return false end
  function f:createMapAdapter() return {} end
  function f:createView(settings)
    self.view_creates=(self.view_creates or 0)+1
    local view={root={},view_contract=settings.view_contract,view_settings_contract=settings.view_settings_contract}
    function view:update(state) self.state=state end
    function view:applyLayout(layout) self.layout=layout end
    function view:delete() end
    function view:setOptionsActionCallback(callback) f.options=callback end
    function view:setCombinedSkillsRunes(enabled) self.combined=enabled; f.view_sets=f.view_sets+1 end
    function view:setSkillsRunesTab(tab) self.tab=tab; f.view_sets=f.view_sets+1 end
    function view:clickTab(tab) return f.options("skills_runes_tab",tab) end
    f.view=view; return view
  end
  function f:adoptView(view) self.view=view; self.view_adoptions=(self.view_adoptions or 0)+1; return view end
  function f:addEvent(name,fn) local id=self:id(); self.events[id]={name=name,fn=fn}; return id end
  function f:addAlias(pattern,fn) local id=self:id(); self.aliases[id]={pattern=pattern,fn=fn}; return id end
  function f:addLineTrigger(fn) local id=self:id(); self.triggers[id]=fn; return id end
  f.addColorizerTrigger=f.addLineTrigger; f.addSkillDisplayTrigger=f.addLineTrigger
  function f:killEvent(id) self.events[id]=nil end
  function f:killAlias(id) self.aliases[id]=nil end
  function f:killTrigger(id) self.triggers[id]=nil end
  function f:schedule(delay,fn) local id=self:id(); self.timers[id]=fn; return id end
  function f:cancelTimer(id) self.timers[id]=nil end
  function f:sendCommand(command) self.sent[#self.sent+1]=command; return true end
  function f:reportCommandError(message) self.error=message end
  function f:saveDisplaySettings(config)
    self.saves=self.saves+1
    if self.onSave then self.onSave(config) end
    if self.failure=="throw" then error("private storage detail") end
    if self.failure=="nil" then return nil,"disk full" end
    if self.failure=="false" then return false,"disk full" end
    self.saved=Settings.merge({},config); return true
  end
  function f:saveUpdateSettings(config) self.savedUpdate=Settings.merge({},config); return true end
  function f:setMainInputAlignment() return true end
  return f
end
local function runtime(overrides,f)
  f=f or fake()
  local settings=Settings.resolve(defaults,Settings.merge({schema=1,chat={enabled=false},mapper={enabled=false},roller={auto_start_on_name=false}},overrides))
  local hud=Main.new(f,settings); assert(hud:start()); return hud,f
end
local function withRoot(fn)
  local previous=_G.DGHUD
  local ok,err=xpcall(fn,debug.traceback)
  _G.DGHUD=previous
  if not ok then error(err,0) end
end

test("combined panel controller starts with defaults and syncs persisted tab without sending commands",function()
  local hud,f=runtime()
  eq(f.view.combined,true); eq(f.view.tab,"skills"); eq(f.saves,0); eq(#f.sent,0); assert(hud:shutdown())
  local saved,g=runtime({display={combine_skills_runes=false,skills_runes_tab="runes"}})
  eq(g.view.combined,false); eq(g.view.tab,"runes"); eq(g.saves,0); eq(#g.sent,0); assert(saved:shutdown())
end)

test("combined panel setters save before touching active user or view state",function()
  withRoot(function()
    local hud,f=runtime({display={personal="keep"},update={auto_apply=true}})
    _G.DGHUD={user_settings={display={personal="keep"},update={auto_apply=true},custom="keep"}}
    f.onSave=function(candidate)
      eq(candidate.combine_skills_runes,false); eq(candidate.skills_runes_tab,"skills")
      eq(hud.settings.display.combine_skills_runes,true); eq(_G.DGHUD.user_settings.display.combine_skills_runes,nil); eq(f.view.combined,true)
    end
    eq(hud:setCombinedSkillsRunes(false),false)
    eq(hud.settings.display.combine_skills_runes,false); eq(_G.DGHUD.user_settings.display.combine_skills_runes,false); eq(f.view.combined,false)
    f.onSave=function(candidate)
      eq(candidate.combine_skills_runes,false); eq(candidate.skills_runes_tab,"runes")
      eq(hud.settings.display.skills_runes_tab,"skills"); eq(_G.DGHUD.user_settings.display.skills_runes_tab,nil); eq(f.view.tab,"skills")
    end
    eq(hud:setSkillsRunesTab("runes"),"runes")
    eq(hud.settings.display.skills_runes_tab,"runes"); eq(_G.DGHUD.user_settings.display.skills_runes_tab,"runes"); eq(f.view.tab,"runes")
    eq(hud.settings.display.personal,"keep"); eq(_G.DGHUD.user_settings.custom,"keep"); eq(_G.DGHUD.user_settings.update.auto_apply,true); eq(#f.sent,0)
    assert(hud:shutdown())
  end)
end)

test("combined panel rejects invalid setter arguments before saving or applying",function()
  local hud,f=runtime(); local count=f.view_sets
  for _,invalid in ipairs({"false","true",0,1,{},function() end}) do
    local result,err=hud:setCombinedSkillsRunes(invalid); eq(result,nil); assert(err:find("ON or OFF",1,true))
    result,err=hud:setSkillsRunesTab(invalid); eq(result,nil); assert(err:find("Skills or Runes",1,true))
  end
  for _,invalid in ipairs({"SKILLS","RUnes","inventory","","skills; runes"}) do eq(hud:setSkillsRunesTab(invalid),nil) end
  eq(hud:setCombinedSkillsRunes(nil),nil); eq(hud:setSkillsRunesTab(nil),nil)
  eq(f.saves,0); eq(f.view_sets,count); eq(hud:combinedSkillsRunesEnabled(),true); eq(hud:skillsRunesTab(),"skills"); eq(#f.sent,0)
  assert(hud:shutdown())
end)

test("combined panel save failures preserve active user and view state without leaking raw errors",function()
  withRoot(function()
    for _,failure in ipairs({"nil","false","throw","missing"}) do
      local hud,f=runtime({display={combine_skills_runes=false,skills_runes_tab="runes"}})
      _G.DGHUD={user_settings={display={combine_skills_runes=false,skills_runes_tab="runes",personal="keep"},update={auto_apply=true}}}
      local display=hud.settings.display; local user=_G.DGHUD.user_settings; local userDisplay=user.display; local count=f.view_sets
      f.failure=failure; if failure=="missing" then f.saveDisplaySettings=nil end
      for _,call in ipairs({function() return hud:setCombinedSkillsRunes(true) end,function() return hud:setSkillsRunesTab("skills") end}) do
        local result,err=call(); eq(result,nil); eq(err,"Could not save Skills / Runes settings. Try again."); eq(f.error,err)
        eq(hud.settings.display,display); eq(_G.DGHUD.user_settings,user); eq(user.display,userDisplay)
        eq(display.combine_skills_runes,false); eq(display.skills_runes_tab,"runes"); eq(userDisplay.combine_skills_runes,false); eq(userDisplay.skills_runes_tab,"runes")
        eq(f.view.combined,false); eq(f.view.tab,"runes"); eq(f.view_sets,count); eq(userDisplay.personal,"keep"); eq(user.update.auto_apply,true)
      end
      eq(#f.sent,0); assert(hud:shutdown())
    end
    local hud,f=runtime(); _G.DGHUD={}; f.failure="nil"
    eq(hud:setSkillsRunesTab("runes"),nil); eq(_G.DGHUD.user_settings,nil); assert(hud:shutdown())
  end)
end)

test("options combine toggle and tab clicks use controller without requesting game data",function()
  local hud,f=runtime()
  eq(f.options("combine_skills_runes"),false); eq(f.view.combined,false)
  eq(f.view:clickTab("runes"),"runes"); eq(f.view.tab,"runes")
  eq(f.options("combine_skills_runes"),true); eq(f.view.combined,true); eq(f.view.tab,"runes")
  eq(f.view:clickTab("skills"),"skills"); eq(f.view.tab,"skills"); eq(f.saves,4); eq(#f.sent,0)
  f.failure="nil"; eq(f.view:clickTab("runes"),nil); eq(f.view.tab,"skills"); eq(f.options("combine_skills_runes"),nil); eq(f.view.combined,true)
  assert(hud:shutdown())
end)

test("unrelated display and auto update saves preserve combined panel choices",function()
  withRoot(function()
    for _,autoApply in ipairs({true,false}) do
      local hud,f=runtime({display={combine_skills_runes=false,skills_runes_tab="runes"},update={auto_apply=autoApply}})
      _G.DGHUD={user_settings={display={combine_skills_runes=false,skills_runes_tab="runes"},update={auto_apply=autoApply}}}
      local function preserved()
        eq(f.saved.combine_skills_runes,false); eq(f.saved.skills_runes_tab,"runes")
        eq(hud.settings.display.combine_skills_runes,false); eq(hud.settings.display.skills_runes_tab,"runes")
        eq(_G.DGHUD.user_settings.display.combine_skills_runes,false); eq(_G.DGHUD.user_settings.display.skills_runes_tab,"runes")
        eq(hud.settings.update.auto_apply,autoApply); eq(_G.DGHUD.user_settings.update.auto_apply,autoApply)
      end
      eq(hud:setDisplayTextSize("small"),"small"); preserved()
      eq(hud:setMainSkillsEnabled(false),false); preserved()
      eq(hud:setMainConsoleAutoWrap(false),false); preserved()
      eq(hud:setMainInputAligned(true),true); preserved()
      local config=hud:skillSettings(); config.skill_filter=false; config.main_skill_sort.primary="uses"; assert(hud:setSkillSettings(config)); preserved()
      eq(f.options("auto_update"),not autoApply); eq(f.savedUpdate.auto_apply,not autoApply)
      eq(hud:setSkillsRunesTab("skills"),"skills"); eq(hud.settings.update.auto_apply,not autoApply); eq(_G.DGHUD.user_settings.update.auto_apply,not autoApply)
      eq(f.saved.combine_skills_runes,false); eq(f.saved.skills_runes_tab,"skills")
      assert(hud:shutdown())
    end
  end)
end)

test("combined preferences survive character exit reload and package replacement resolution",function()
  local hud,f=runtime(); eq(hud:setCombinedSkillsRunes(false),false); eq(hud:setSkillsRunesTab("runes"),"runes")
  local saved=Settings.merge({},f.saved)
  assert(hud:onCharacterEntry("First Character")); assert(hud:onCharacterEntry("Another Character")); hud:refresh()
  eq(hud:combinedSkillsRunesEnabled(),false); eq(hud:skillsRunesTab(),"runes"); eq(f.view.tab,"runes")
  assert(hud:reload()); eq(f.view.combined,false); eq(f.view.tab,"runes"); eq(f.saved.skills_runes_tab,"runes")
  hud.update_handoff=true; assert(hud:shutdown())
  local cold,g=runtime({display=saved,version="old",update={auto_apply=true}})
  eq(cold.settings.version,defaults.version); eq(cold.settings.edition,defaults.edition)
  eq(g.view.combined,false); eq(g.view.tab,"runes"); eq(cold.settings.update.auto_apply,true); eq(#g.sent,0)
  assert(cold:shutdown())
end)

test("compatible live view reuse rebinds controller and restores saved combined choices without changing auto update",function()
  withRoot(function()
    local hud,f=runtime({update={auto_apply=true}})
    _G.DGHUD={user_settings={update={auto_apply=true}}}
    eq(hud:setCombinedSkillsRunes(false),false); eq(hud:setSkillsRunesTab("runes"),"runes")
    local contract=string.rep("a",64); hud.settings.view_contract=contract; hud.view.view_contract=contract
    local view=hud.view; local handoff={schema=hud.settings.view_schema,contract=contract,settings_contract=hud.settings.view_settings_contract,view=view}
    local saves=f.saves
    hud.update_handoff=true; hud.update_preserve_view=true; assert(hud:shutdown())
    -- The startup sync must repair even a stale but structurally reusable view.
    view.combined=true; view.tab="skills"
    local installed=Settings.merge(defaults,{view_contract=contract})
    local settings=Settings.resolve(installed,{schema=1,display=f.saved,update={auto_apply=true},chat={enabled=false},mapper={enabled=false},roller={auto_start_on_name=false}})
    local replacement=Main.new(f,settings,handoff); assert(replacement:start())
    eq(replacement.view,view); eq(f.view_creates,1); eq(f.view_adoptions,1)
    eq(view.combined,false); eq(view.tab,"runes"); eq(f.saves,saves)
    eq(replacement.settings.update.auto_apply,true); eq(_G.DGHUD.user_settings.update.auto_apply,true)
    eq(view:clickTab("skills"),"skills"); eq(replacement.settings.display.skills_runes_tab,"skills")
    eq(hud.settings.display.skills_runes_tab,"runes"); eq(#f.sent,0)
    assert(replacement:shutdown())
  end)
end)
