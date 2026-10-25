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

test("every quick alias registers exactly once and reload retires its old runtime",function()
  local hud,f=runtime(); local owned={}
  for _,name in ipairs({"shoprenew","shoprenewall","trainall","shoprenewstop","trainallstop"}) do
    local count=0
    for id,entry in pairs(f.aliases) do if entry.pattern=="^(?i:"..name..")$" then count=count+1; owned[#owned+1]=id end end
    eq(count,1)
  end
  assert(hud:reload())
  for _,id in ipairs(owned) do eq(f.aliases[id],nil) end
  for _,name in ipairs({"shoprenew","shoprenewall","trainall","shoprenewstop","trainallstop"}) do
    local count=0; for _,entry in pairs(f.aliases) do if entry.pattern=="^(?i:"..name..")$" then count=count+1 end end; eq(count,1)
  end
  assert(hud:shutdown()); eq(next(f.aliases),nil)
end)
test("quick command aliases refresh runes export counts and send renewals one second apart",function()
  withRoot(function()
    _G.DGHUD={}
    local f=fake(); local delays={}
    local originalSchedule=f.schedule
    function f:schedule(delay,fn) local id=originalSchedule(self,delay,fn); delays[id]=delay; return id end
    function f:fireQuickTimer()
      local id,entry
      for key,delay in pairs(delays) do if delay==1 and self.timers[key] then id=key; entry=self.timers[key]; break end end
      assert(id,"Expected a one-second quick timer"); self.timers[id]=nil; delays[id]=nil; entry()
    end
    function f:sendCommand(command)
      self.sent[#self.sent+1]=command
      for _,event in pairs(self.events) do if event.name=="sysDataSendRequest" then event.fn(nil,command) end end
      return true
    end
    local hud=runtime({display={skill_filter=false}},f); _G.DGHUD.controller=hud; Main.installRunesApi(_G.DGHUD)
    local alias
    for _,entry in pairs(f.aliases) do if entry.pattern=="^(?i:shoprenew)$" then alias=entry.fn end end
    assert(alias); assert(alias()); eq(f.sent[1],"info magic"); eq(hud.collector.active.command,"info magic")
    for _,line in ipairs({"You have the following elemental runes available to you...",
        "  disruption - 3 weaves remain   force - 20 weaves remain","  light - 19 weaves remain",">"}) do hud.collector:onLine(line) end
    eq(_G.DGHUD.runes.values.disruption,3); eq(_G.DGHUD.runes.disruption,3); eq(_G.disruption,3)
    eq(_G.DGHUD.runes.getRemaining("force"),20); eq(#f.sent,1)
    f:fireQuickTimer(); eq(f.sent[2],"shop renew disruption")
    f:fireQuickTimer(); eq(f.sent[3],"shop renew light"); eq(hud.quick_actions:busy(),false)
    assert(hud:runQuickAction("shoprenewall")); eq(f.sent[4],"info magic")
    eq(_G.disruption,nil); eq(_G.DGHUD.runes.getRemaining("disruption"),nil); eq(_G.DGHUD.runes.values.disruption,nil)
    hud.collector:onLine("You have the following elemental runes available to you...")
    hud.collector:onLine("  force - 100 weaves remain"); hud.collector:onLine(">")
    eq(_G.DGHUD.runes.getRemaining("force"),100); f:fireQuickTimer(); eq(f.sent[5],"shop renew force")
    assert(hud:shutdown()); eq(_G.disruption,nil); eq(_G.force,nil)
  end)
end)
local runeHeader="You have the following elemental runes available to you..."
local modifierHeading="You may use the following modifier runes upon them..."
local shapeHeading="You may use them with the following shapes..."
local runeFooter="See INFO RUNESPELLS for memorized corridors."
local runeGlobalNames={"force","disruption","vigor","healing","small","average","aura","blast","chi","mist","eagle","body","spirit"}
local function withRuneRuntime(fn)
  withRoot(function()
    local previous={}
    for _,name in ipairs(runeGlobalNames) do previous[name]=rawget(_G,name); rawset(_G,name,nil) end
    _G.DGHUD={}
    local hud,f
    local ok,err=xpcall(function()
      hud,f=runtime({display={skills_runes_tab="runes"}})
      _G.DGHUD.controller=hud
      local update=f.view.update
      function f.view:update(state) self.updates=(self.updates or 0)+1; return update(self,state) end
      fn(hud,f)
    end,debug.traceback)
    if hud then hud:shutdown() end
    for _,name in ipairs(runeGlobalNames) do rawset(_G,name,previous[name]) end
    if not ok then error(err,0) end
  end)
end
local function assertElementalRunes(hud,f)
  eq(#hud.last_state.runes.items,3); eq(#f.view.state.runes.items,3)
  for index,item in ipairs({{"Vigor",0},{"Disruption",61},{"Force",97}}) do
    eq(f.view.state.runes.items[index].name,item[1]); eq(f.view.state.runes.items[index].remaining,item[2])
    local name=item[1]:lower()
    eq(_G.DGHUD.runes.values[name],item[2]); eq(_G.DGHUD.runes[name],item[2]); eq(rawget(_G,name),item[2])
    eq(_G.DGHUD.runes.get(name).remaining,item[2]); eq(_G.DGHUD.runes.getRemaining(name),item[2])
  end
  eq(#_G.DGHUD.runes.all(),3)
  for index=5,#runeGlobalNames do
    local name=runeGlobalNames[index]
    eq(rawget(_G,name),nil); eq(_G.DGHUD.runes[name],nil); eq(_G.DGHUD.runes.values[name],nil)
    eq(_G.DGHUD.runes.get(name),nil); eq(_G.DGHUD.runes.getRemaining(name),nil)
  end
end
local function elementalLines(hud)
  for _,line in ipairs({runeHeader,""," force - 97 weaves remain   disruption - 61 weaves remain",
      " vigor - 0 weaves remain",""}) do hud.collector:onLine(line) end
end
local function fireRenewal(hud,f)
  local operation=assert(hud.quick_actions.current)
  local timer=assert(operation.timer,"Expected a delayed renewal")
  local callback=assert(f.timers[timer.id]); f.timers[timer.id]=nil; callback()
end

for _,name in ipairs({"shoprenew","shoprenewall"}) do
  test(name.." alias requests and sends info magic once through outgoing events",function()
    withRuneRuntime(function(hud,f)
      local requests={}; local request=hud.collector.request
      function hud.collector:request(command,done)
        requests[#requests+1]=command; return request(self,command,done)
      end
      function f:sendCommand(command)
        self.sent[#self.sent+1]=command
        for _,event in pairs(self.events) do if event.name=="sysDataSendRequest" then event.fn(nil,command) end end
        return true
      end
      local alias
      for _,entry in pairs(f.aliases) do if entry.pattern=="^(?i:"..name..")$" then alias=entry.fn end end
      assert(alias); assert(alias())
      eq(#requests,1); eq(requests[1],"info magic")
      eq(#f.sent,1); eq(f.sent[1],"info magic"); eq(hud.collector.active.command,"info magic")
      eq(hud.quick_actions:busy(),true)
      for _,line in ipairs({runeHeader," force - 0 weaves remain",">"}) do hud.collector:onLine(line) end
      eq(#f.sent,1); fireRenewal(hud,f)
      hud.collector:onLine(">")
      eq(#requests,1); eq(#f.sent,2); eq(f.sent[2],"shop renew force"); eq(hud.quick_actions:busy(),false)
    end)
  end)
end

test("shoprenewall clears old variables and publishes elementals once before the full magic tail finishes",function()
  withRuneRuntime(function(hud,f)
    hud.collector:onOutgoing("info magic")
    for _,line in ipairs({runeHeader," force - 3 weaves remain   healing - 14 weaves remain",">"}) do hud.collector:onLine(line) end
    eq(_G.force,3); eq(_G.healing,14)
    assert(hud:runQuickAction("shoprenewall")); eq(f.sent[1],"info magic")
    eq(_G.force,nil); eq(_G.healing,nil); eq(next(_G.DGHUD.runes.values),nil)
    eq(_G.DGHUD.runes.getRemaining("force"),nil); eq(#_G.DGHUD.runes.all(),0)
    eq(#f.view.state.runes.items,0)
    local clearedUpdates=f.view.updates
    elementalLines(hud)
    eq(f.view.updates,clearedUpdates); eq(#f.view.state.runes.items,0)
    eq(hud.quick_actions.current.timer,nil); eq(#f.sent,1)
    local active=hud.collector.active
    hud.collector:onLine(modifierHeading)
    eq(hud.collector.active,active); eq(f.view.updates,clearedUpdates+1)
    assertElementalRunes(hud,f); eq(_G.healing,nil)
    eq(hud.quick_actions.current.timer,nil); eq(#f.sent,1)
    for _,line in ipairs({""," small average","",shapeHeading,""," aura blast chi mist eagle body"," spirit","",runeFooter,""}) do
      hud.collector:onLine(line)
      eq(hud.collector.active,active); eq(f.view.updates,clearedUpdates+1)
      eq(hud.quick_actions.current.timer,nil); eq(#f.sent,1)
    end
    assertElementalRunes(hud,f)
    hud.collector:onLine("[199] 301/301 hp, 173/173 ftg >")
    eq(hud.collector.active,nil); eq(f.view.updates,clearedUpdates+1); eq(#f.sent,1)
    assertElementalRunes(hud,f)
    for index,name in ipairs({"disruption","force","vigor"}) do fireRenewal(hud,f); eq(f.sent[index+1],"shop renew "..name) end
    eq(#f.sent,4); eq(hud.quick_actions:busy(),false)
  end)
end)
test("manual info magic immediately refreshes sidebar and legacy rune APIs at each recognized boundary",function()
  for _,command in ipairs({"info mag","info magic"}) do
    for _,heading in ipairs({modifierHeading,shapeHeading,runeFooter}) do
      withRuneRuntime(function(hud,f)
        hud.collector:onOutgoing(command)
        local clearedUpdates=f.view.updates
        elementalLines(hud)
        eq(#f.view.state.runes.items,0); eq(f.view.updates,clearedUpdates)
        local active=hud.collector.active
        hud.collector:onLine(heading)
        eq(hud.collector.active,active); eq(f.view.updates,clearedUpdates+1)
        assertElementalRunes(hud,f)
        if heading==modifierHeading then hud.collector:onLine(" small average")
        elseif heading==shapeHeading then hud.collector:onLine(" aura spirit") end
        hud.collector:onLine(""); eq(hud.collector.active,active)
        eq(f.view.updates,clearedUpdates+1); eq(#f.sent,0)
        hud.collector:onLine(">")
        eq(hud.collector.active,nil); eq(f.view.updates,clearedUpdates+1)
        assertElementalRunes(hud,f); eq(#f.sent,0)
      end)
    end
  end
end)
test("shoprenewall never publishes partial elemental rows or schedules renewals from them",function()
  for _,row in ipairs({" disruption - 6 weaves rem"," disruption - -1 weaves remain"," force - 97 weaves remain suffix"}) do
    withRuneRuntime(function(hud,f)
      assert(hud:runQuickAction("shoprenewall")); local clearedUpdates=f.view.updates
      for _,line in ipairs({runeHeader," force - 97 weaves remain",row,"",modifierHeading," small average",shapeHeading," spirit",runeFooter}) do hud.collector:onLine(line) end
      eq(f.view.updates,clearedUpdates); eq(#f.view.state.runes.items,0)
      eq(next(_G.DGHUD.runes.values),nil); eq(_G.force,nil)
      eq(hud.quick_actions.current.timer,nil); eq(#f.sent,1)
      hud.collector:onLine(">")
      eq(hud.collector.active,nil); eq(hud.quick_actions:busy(),false)
      eq(#f.sent,1); eq(#f.view.state.runes.items,0)
    end)
  end
end)
test("shoprenewall retains early elemental display but fails closed on an unsafe magic tail",function()
  for _,row in ipairs({" small - 0 weaves remain"," 1 2 3"," spirit; shop renew force"}) do
    withRuneRuntime(function(hud,f)
      assert(hud:runQuickAction("shoprenewall")); elementalLines(hud)
      hud.collector:onLine(modifierHeading); assertElementalRunes(hud,f)
      local publishedUpdates=f.view.updates
      hud.collector:onLine(row); hud.collector:onLine(shapeHeading); hud.collector:onLine(" spirit")
      eq(hud.quick_actions.current.timer,nil); eq(#f.sent,1)
      hud.collector:onLine(">")
      eq(hud.collector.active,nil); eq(hud.quick_actions:busy(),false)
      eq(f.view.updates,publishedUpdates); eq(#f.sent,1); assertElementalRunes(hud,f)
    end)
  end
end)
test("conflicting rune counts fail closed in the sidebar variables and legacy API",function()
  for _,owned in ipairs({false,true}) do
    withRuneRuntime(function(hud,f)
      hud.collector:onOutgoing("info magic"); elementalLines(hud)
      hud.collector:onLine(modifierHeading); hud.collector:onLine(">")
      assertElementalRunes(hud,f)
      if owned then assert(hud:runQuickAction("shoprenewall")) else hud.collector:onOutgoing("info magic") end
      for _,line in ipairs({runeHeader," force - 3 weaves remain   force - 4 weaves remain",modifierHeading}) do hud.collector:onLine(line) end
      local function assertCleared()
        eq(#hud.collector.snapshot.runes.items,0); eq(#hud.last_state.runes.items,0); eq(#f.view.state.runes.items,0)
        eq(next(_G.DGHUD.runes.values),nil); eq(#_G.DGHUD.runes.all(),0)
        for _,name in ipairs({"force","disruption","vigor"}) do
          eq(rawget(_G,name),nil); eq(_G.DGHUD.runes[name],nil)
          eq(_G.DGHUD.runes.get(name),nil); eq(_G.DGHUD.runes.getRemaining(name),nil)
        end
      end
      assertCleared(); assert(hud.collector.active)
      if owned then eq(hud.quick_actions.current.timer,nil) end
      hud.collector:onLine(" small average"); hud.collector:onLine(shapeHeading)
      hud.collector:onLine(" spirit"); hud.collector:onLine(">")
      eq(hud.collector.active,nil); eq(hud.quick_actions:busy(),false)
      assertCleared(); hud:refresh(); assertCleared()
      eq(#f.sent,owned and 1 or 0)
    end)
  end
end)
test("validated rune refresh preserves owned counts and unrelated or user edited globals",function()
  withRuneRuntime(function(hud,f)
    _G.force=777; _G.DGHUD.runes.force=888
    hud.collector:onOutgoing("info magic"); elementalLines(hud)
    hud.collector:onLine(modifierHeading); hud.collector:onLine(">")
    for _=1,3 do
      hud:refresh()
      eq(#f.view.state.runes.items,3); eq(#_G.DGHUD.runes.all(),3)
      eq(_G.force,777); eq(_G.DGHUD.runes.force,888)
      eq(_G.disruption,61); eq(_G.vigor,0)
      eq(_G.DGHUD.runes.values.force,97); eq(_G.DGHUD.runes.getRemaining("force"),97)
      eq(_G.DGHUD.runes.values.disruption,61); eq(_G.DGHUD.runes.get("disruption").remaining,61)
    end
    _G.disruption=12345; hud:refresh()
    eq(_G.disruption,12345); eq(_G.DGHUD.runes.values.disruption,61)
    hud.collector:onOutgoing("info magic")
    eq(next(_G.DGHUD.runes.values),nil); eq(#_G.DGHUD.runes.all(),0)
    eq(_G.DGHUD.runes.getRemaining("force"),nil); eq(_G.DGHUD.runes.getRemaining("disruption"),nil)
    eq(_G.force,777); eq(_G.DGHUD.runes.force,888); eq(_G.disruption,12345); eq(_G.vigor,nil)
    eq(#f.view.state.runes.items,0); eq(#f.sent,0)
  end)
end)
test("legacy rune API rejects injected conflicts without mutating valid exported globals",function()
  withRuneRuntime(function(hud,f)
    hud.collector:onOutgoing("info magic"); elementalLines(hud)
    hud.collector:onLine(modifierHeading); hud.collector:onLine(">")
    assertElementalRunes(hud,f)
    local rows={{name="Force",remaining=3},{name="force",remaining=4}}
    local valid,err=Main.syncRunesApi({runes={items=rows}})
    eq(valid,nil); eq(type(err),"string")
    eq(#_G.DGHUD.runes.all(),0); eq(next(_G.DGHUD.runes.by_name),nil); eq(next(_G.DGHUD.runes.remaining),nil)
    eq(_G.DGHUD.runes.get("force"),nil); eq(_G.DGHUD.runes.getRemaining("force"),nil)
    eq(_G.force,97); eq(_G.disruption,61); eq(_G.vigor,0)
    eq(_G.DGHUD.runes.values.force,97); eq(_G.DGHUD.runes.force,97)
    eq(#rows,2); eq(rows[1].remaining,3); eq(rows[2].remaining,4)
    eq(rows[1].name,"Force"); eq(rows[2].name,"force")
    hud:refresh(); assertElementalRunes(hud,f); eq(#f.sent,0)
  end)
end)
test("legacy rune sync preserves exporter keys after whitespace normalization and deduplication",function()
  withRoot(function()
    _G.DGHUD={}
    local environment={}
    local exporter=require("rune_variables").new(_G.DGHUD,environment)
    local rows={{name="  Stone\t  Skin  ",remaining=0},{name="STONE SKIN",remaining=0},{name=" Force ",remaining=97}}
    assert(exporter:save(rows)); Main.installRunesApi(_G.DGHUD)
    local api=_G.DGHUD.runes; local values=api.values
    eq(api.getRemaining("stone skin"),0); eq(api.get("stone skin").name,"Stone Skin")
    for _=1,3 do
      local valid,err=Main.syncRunesApi({runes={items=rows}})
      eq(valid,true); eq(err,nil); eq(api.values,values)
      eq(#api.all(),2); eq(api.all()[1].name,"Stone Skin"); eq(api.all()[2].name,"Force")
      eq(api.get("STONE SKIN").name,"Stone Skin"); eq(api.getRemaining("stone skin"),0)
      eq(api.by_name["stone skin"].remaining,0); eq(api.remaining["stone skin"],0)
      eq(api.getRemaining("force"),97); eq(values.stone_skin,0); eq(api.stone_skin,0); eq(environment.stone_skin,0)
      local count=0; for _ in pairs(api.by_name) do count=count+1 end; eq(count,2)
      local item=api.get("stone skin"); item.name="Edited"; item.remaining=99
      local all=api.all(); all[1].remaining=88; all[2]=nil
      eq(api.get("stone skin").name,"Stone Skin"); eq(api.getRemaining("stone skin"),0); eq(#api.all(),2)
    end
    eq(rows[1].name,"  Stone\t  Skin  "); eq(rows[2].name,"STONE SKIN"); eq(#rows,3)
    exporter:clear(); eq(environment.stone_skin,nil); eq(api.getRemaining("stone skin"),nil)
  end)
end)
test("legacy rune sync rejects malformed lists without changing owned exports and recovers on refresh",function()
  withRuneRuntime(function(hud,f)
    hud.collector:onOutgoing("info magic"); elementalLines(hud)
    hud.collector:onLine(modifierHeading); hud.collector:onLine(">")
    for _,rows in ipairs({{[2]={name="Force",remaining=3}},setmetatable({},{}),{{name="Force",remaining="3"}}}) do
      local valid,err=Main.syncRunesApi({runes={items=rows}})
      eq(valid,nil); eq(type(err),"string")
      eq(#_G.DGHUD.runes.all(),0); eq(next(_G.DGHUD.runes.by_name),nil); eq(next(_G.DGHUD.runes.remaining),nil)
      eq(_G.DGHUD.runes.get("force"),nil); eq(_G.DGHUD.runes.getRemaining("force"),nil)
      eq(_G.DGHUD.runes.values.force,97); eq(_G.DGHUD.runes.force,97); eq(_G.force,97)
      hud:refresh(); assertElementalRunes(hud,f)
    end
    eq(#f.sent,0)
  end)
end)
test("legacy rune sync rejects an explicit false list instead of treating it as empty",function()
  withRuneRuntime(function(hud,f)
    hud.collector:onOutgoing("info magic"); elementalLines(hud)
    hud.collector:onLine(modifierHeading); hud.collector:onLine(">")
    local valid,err=Main.syncRunesApi({runes={items=false}})
    eq(valid,nil); eq(type(err),"string")
    eq(#_G.DGHUD.runes.all(),0); eq(_G.DGHUD.runes.getRemaining("force"),nil)
    eq(_G.DGHUD.runes.values.force,97); eq(_G.DGHUD.runes.force,97); eq(_G.force,97)
    hud:refresh(); assertElementalRunes(hud,f); eq(#f.sent,0)
  end)
end)
test("a valid capture after a rejected refresh restores sidebar and rune API parity",function()
  for _,owned in ipairs({false,true}) do
    withRuneRuntime(function(hud,f)
      hud.collector:onOutgoing("info magic"); elementalLines(hud)
      hud.collector:onLine(modifierHeading); hud.collector:onLine(">")
      assertElementalRunes(hud,f)
      if owned then assert(hud:runQuickAction("shoprenewall")) else hud.collector:onOutgoing("info magic") end
      for _,line in ipairs({runeHeader," force - 3 weaves remain   force - 4 weaves remain",modifierHeading,">"}) do hud.collector:onLine(line) end
      eq(hud.collector.active,nil); eq(hud.quick_actions:busy(),false)
      eq(#f.view.state.runes.items,0); eq(#_G.DGHUD.runes.all(),0); eq(_G.force,nil)
      if owned then assert(hud:runQuickAction("shoprenewall")) else hud.collector:onOutgoing("info magic") end
      for _,line in ipairs({runeHeader," force - 0 weaves remain",modifierHeading}) do hud.collector:onLine(line) end
      eq(#f.view.state.runes.items,1); eq(f.view.state.runes.items[1].remaining,0)
      eq(_G.force,0); eq(_G.DGHUD.runes.values.force,0); eq(_G.DGHUD.runes.force,0)
      eq(_G.DGHUD.runes.get("force").remaining,0); eq(_G.DGHUD.runes.getRemaining("force"),0); eq(#_G.DGHUD.runes.all(),1)
      eq(_G.disruption,nil); eq(_G.vigor,nil); eq(_G.DGHUD.runes.getRemaining("disruption"),nil)
      local updates=f.view.updates
      if owned then eq(hud.quick_actions.current.timer,nil) end
      hud.collector:onLine(">"); eq(f.view.updates,updates)
      if owned then fireRenewal(hud,f); eq(f.sent[3],"shop renew force") end
      eq(hud.quick_actions:busy(),false); eq(#f.sent,owned and 3 or 0)
      hud:refresh(); eq(_G.force,0); eq(_G.DGHUD.runes.getRemaining("force"),0); eq(#f.view.state.runes.items,1)
    end)
  end
end)
test("identical rune counts deduplicate display variables legacy API and renewal targets",function()
  withRuneRuntime(function(hud,f)
    assert(hud:runQuickAction("shoprenewall"))
    for _,line in ipairs({runeHeader," force - 3 weaves remain   Force - 3 weaves remain",modifierHeading}) do hud.collector:onLine(line) end
    eq(#hud.collector.snapshot.runes.items,1); eq(#f.view.state.runes.items,1)
    eq(_G.force,3); eq(_G.DGHUD.runes.values.force,3); eq(_G.DGHUD.runes.getRemaining("force"),3)
    eq(#_G.DGHUD.runes.all(),1); eq(hud.quick_actions.current.timer,nil); eq(#f.sent,1)
    hud.collector:onLine(" small average"); hud.collector:onLine(">")
    eq(#hud.collector.snapshot.runes.items,1); eq(#f.view.state.runes.items,1)
    fireRenewal(hud,f)
    eq(f.sent[2],"shop renew force"); eq(#f.sent,2); eq(hud.quick_actions:busy(),false)
  end)
end)
test("trainall uses fresh authoritative game IDs independently of skill filters and stops on settings changes",function()
  withRoot(function()
    _G.DGHUD={}
    local f=fake(); local delays={}
    local originalSchedule=f.schedule
    function f:schedule(delay,fn) local id=originalSchedule(self,delay,fn); delays[id]=delay; return id end
    local hud=runtime({display={skill_filter=false}},f)
    assert(hud:runQuickAction("trainall")); eq(f.sent[1],"skill")
    for _,line in ipairs({"Skill Remain Level","Sharp Weapons 0 4","Pole Weapons 0 2",
      "Identify Armor Quality 0 2","Swimming 10 2","Future Unknown Skill 0 1",">"}) do hud.collector:onLine(line) end
    local function nextQuick()
      for id,delay in pairs(delays) do if delay==1 and f.timers[id] then
        local fn=f.timers[id]; f.timers[id]=nil; delays[id]=nil; return fn
      end end
      error("No queued quick timer")
    end
    nextQuick()(); eq(f.sent[2],"train raise 2")
    local stale=nextQuick()
    local config=hud:skillSettings(); config.trainall=false
    assert(hud:setSkillSettings(config)); eq(f.saved.trainall,false); eq(f.saved.shoprenew,true)
    stale(); eq(#f.sent,2); eq(hud.quick_actions:busy(),false)
    local ok,err=hud:runQuickAction("trainall"); eq(ok,nil); assert(type(err)=="string"); eq(#f.sent,2)
    assert(hud:shutdown())
  end)
end)
test("quick settings retain explicit OFF through unrelated saves and request interruption cancels spending",function()
  withRoot(function()
    _G.DGHUD={user_settings={}}
    local hud,f=runtime()
    local config=hud:skillSettings(); config.shoprenew=false; config.shoprenewall=false; config.trainall=false
    assert(hud:setSkillSettings(config)); eq(_G.DGHUD.user_settings.display.shoprenew,false)
    eq(hud:setDisplayTextSize("small"),"small")
    eq(f.saved.shoprenew,false); eq(f.saved.shoprenewall,false); eq(f.saved.trainall,false)
    assert(hud:shutdown())
    local restored,g=runtime({display=f.saved}); eq(restored:quickActionEnabled("shoprenew"),false)
    eq(restored:runQuickAction("shoprenew"),nil); eq(#g.sent,0)
    local enabled=restored:skillSettings(); enabled.shoprenew=true; assert(restored:setSkillSettings(enabled))
    assert(restored:runQuickAction("shoprenew")); eq(g.sent[1],"info magic")
    restored.collector:onOutgoing("skill")
    eq(restored.quick_actions:busy(),false)
    restored.collector:onLine("Skill Remain Level"); restored.collector:onLine("Sharp Weapons 0 2"); restored.collector:onLine(">")
    eq(#g.sent,1); assert(restored:shutdown())
  end)
end)
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
