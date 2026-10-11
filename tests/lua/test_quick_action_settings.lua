local Settings=require("settings")
local SkillSettingsView=require("skill_settings_view")
local quickKeys={"shoprenew","shoprenewall","trainall"}
local function copy(value) return type(value)=="table" and Settings.merge({},value) or value end
local function snapshot(overrides)
  return Settings.merge({main_skills=true,skill_filter=true,shoprenew=true,shoprenewall=true,trainall=true,
    main_skill_sort={primary="uses",direction="asc",secondary="name",secondary_direction="desc"},
    sidebar_skill_sort={primary="category",direction="desc",secondary="number",secondary_direction="asc"}},overrides)
end
local function withView(display,fn)
  local previous=Geyser
  local function widget(name,container)
    return {name=name,container=container,
      move=function(self,x,y) self.x=x; self.y=y end,
      resize=function(self,w,h) self.width=w; self.height=h end,
      show=function(self) self.visible=true end,hide=function(self) self.visible=false end,
      raise=function() end,setStyleSheet=function(self,value) self.style=value end,
      echo=function(self,value) self.text=value end,setToolTip=function() end,
      setClickCallback=function(self,callback) self.click=callback end}
  end
  local class={withFont=function(value) return value end,raiseCards=function() end}
  SkillSettingsView.attach(class,{label=widget,copy=copy,
    safeText=function(value) return tostring(value):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;") end})
  class.__index=class
  class.setMainSkillsEnabled=function(self,value) self.main_skills_enabled=value end
  class.renderSkills=function(self) self.skill_renders=(self.skill_renders or 0)+1 end
  for _,name in ipairs({"hideHelp","hideMapSettings","hideMapLibrary","hideRollerSettings","hideChatSettings",
      "hideKeybindingSettings","hideColorSettings","hideSupport","hideLatentPsionAlert","setColorMenuVisible"}) do
    class[name]=function() return true end
  end
  Geyser={Container={new=function(_,config,container) return widget(config.name,container) end},
    ScrollBox={new=function(_,config,container) return widget(config.name,container) end}}
  local ok,err=xpcall(function()
    local view=setmetatable({root=widget("root"),settings=Settings.resolve(require("defaults"),{display=display}),
      layout={window_width=1200,window_height=800,body_font=13},options_anchor={y=4,height=26}},class)
    view:createSkillSettings()
    view.option_action_buttons={skill_settings=widget("action",view.root)}
    fn(view)
  end,debug.traceback)
  Geyser=previous
  if not ok then error(err,0) end
end
local function widgetValid(widget)
  return type(widget)=="table" and type(widget.move)=="function" and type(widget.resize)=="function"
    and type(widget.show)=="function" and type(widget.hide)=="function"
end
local function labelValid(widget)
  return widgetValid(widget) and type(widget.echo)=="function" and type(widget.setStyleSheet)=="function"
end

test("Skills and Runes quick toggles show legacy ON and independent explicit OFF snapshots",function()
  for _,initial in ipairs({{},snapshot({shoprenew=false,trainall=false}),snapshot({shoprenewall=false})}) do
    withView(initial,function(view)
      assert(view:showSkillSettings(initial)); eq(view.skill_settings_dirty,false)
      assert(view.skill_settings_title.text:find("SKILLS &amp; RUNES SETTINGS",1,true))
      local values=assert(view:skillSettingsValues())
      for _,key in ipairs(quickKeys) do
        local expected=initial[key]~=false
        eq(values[key],expected); eq(view["skill_settings_"..key].container,view.skill_settings_content)
        assert(view["skill_settings_"..key].text:find(key:upper()..": "..(expected and "ON" or "OFF"),1,true))
        values[key]=not expected; eq(view:skillSettingsValues()[key],expected)
      end
      assert(view.skill_settings_quick_help.text:find("fewer than 20 weaves",1,true))
      assert(view.skill_settings_quick_help.text:find("renew all runes",1,true))
      assert(view.skill_settings_quick_help.text:find("0-use skills",1,true))
      assert(view.skill_settings_quick_help.text:find("1 command/sec",1,true))
      assert(view.skill_settings_quick_help.text:find("shoprenewstop",1,true))
      assert(view.skill_settings_quick_help.text:find("trainallstop",1,true))
      view:hideSkillSettings()
      for _,widget in ipairs(view:skillSettingsWidgets()) do eq(widget.visible,false) end
    end)
  end
end)

test("quick toggles edit only their draft fields and cancel or overlay discard all edits",function()
  withView(snapshot(),function(view)
    local active=snapshot(); local writes=0
    view.options_action_callback=function(action)
      eq(action,"skill_settings"); return active
    end
    for _,close in ipairs({"cancel","overlay"}) do
      assert(view:showSkillSettings())
      for index,key in ipairs(quickKeys) do
        assert(view["skill_settings_"..key].click()); eq(view.skill_settings_dirty,true)
        for otherIndex,other in ipairs(quickKeys) do
          eq(view:skillSettingsValues()[other],otherIndex>index)
          eq(view.settings.display[other],true); eq(active[other],true)
        end
      end
      view.skill_settings_tabs.main.click(); view.skill_settings_primary_buttons.name.click()
      eq(view:skillSettingsValues().main_skill_sort.primary,"name")
      eq(view:skillSettingsValues().sidebar_skill_sort.primary,"category")
      eq(view:skillSettingsValues().main_skills,true); eq(view:skillSettingsValues().skill_filter,true)
      assert(view["skill_settings_"..close].click())
      eq(writes,0); eq(view.skill_settings_visible,false); eq(view.skill_settings_draft,nil)
      eq(active.main_skill_sort.primary,"uses")
    end
    assert(view:showSkillSettings())
    for _,key in ipairs(quickKeys) do eq(view:skillSettingsValues()[key],true) end
  end)
end)

test("quick draft save passes independent booleans and sorts through a copied persistence snapshot",function()
  withView({auto_wrap=false,align_input=true,side_text_scale=.9,personal="keep"},function(view)
    local active=snapshot(); local persisted; local payload; local writes=0
    view.options_action_callback=function(action,draft)
      if action=="skill_settings" then return active end
      eq(action,"skill_settings_save"); writes=writes+1; payload=draft
      persisted=copy(draft); active=copy(persisted)
      view:setSkillSortPreferences(active)
      return copy(persisted)
    end
    assert(view:showSkillSettings())
    view.skill_settings_shoprenew.click(); view.skill_settings_trainall.click()
    view.skill_settings_filter.click(); view.skill_settings_format.click()
    view.skill_settings_primary_buttons.ready.click()
    view.skill_settings_tabs.main.click(); view.skill_settings_secondary_direction_buttons.asc.click()
    eq(writes,0); eq(persisted,nil)
    local saved=assert(view.skill_settings_save.click()); eq(writes,1)
    eq(saved.shoprenew,false); eq(saved.shoprenewall,true); eq(saved.trainall,false)
    eq(saved.main_skills,false); eq(saved.skill_filter,false)
    eq(saved.sidebar_skill_sort.primary,"ready"); eq(saved.main_skill_sort.secondary_direction,"asc")
    for _,key in ipairs(quickKeys) do eq(view.settings.display[key],persisted[key]) end
    eq(view.settings.display.auto_wrap,false); eq(view.settings.display.align_input,true)
    eq(view.settings.display.side_text_scale,.9); eq(view.settings.display.personal,"keep")
    eq(view.skill_settings_visible,false); eq(view.skill_settings_pending_snapshot,nil)
    payload.trainall=true; saved.shoprenew=true; saved.main_skill_sort.primary="number"
    eq(persisted.trainall,false); eq(view.settings.display.trainall,false)
    eq(view.settings.display.shoprenew,false); eq(view.settings.display.main_skill_sort.primary,"uses")
    assert(view:showSkillSettings()); eq(view:skillSettingsValues().trainall,false)
    eq(view:skillSettingsValues().shoprenew,false); eq(view:skillSettingsValues().shoprenewall,true)
  end)
end)

test("quick Reset defaults remain draft until Save and Cancel keeps saved OFF values",function()
  withView(snapshot({shoprenew=false,shoprenewall=false,trainall=false}),function(view)
    local active=snapshot({shoprenew=false,shoprenewall=false,trainall=false}); local writes=0
    view.options_action_callback=function(action,draft)
      if action=="skill_settings" then return active end
      writes=writes+1; active=copy(draft); return copy(active)
    end
    assert(view:showSkillSettings()); view.skill_settings_reset.click()
    for _,key in ipairs(quickKeys) do eq(view:skillSettingsValues()[key],true); eq(view.settings.display[key],false) end
    eq(writes,0); view.skill_settings_cancel.click(); assert(view:showSkillSettings())
    for _,key in ipairs(quickKeys) do eq(view:skillSettingsValues()[key],false) end
    view.skill_settings_reset.click(); assert(view.skill_settings_save.click()); eq(writes,1)
    for _,key in ipairs(quickKeys) do eq(active[key],true); eq(view.settings.display[key],true) end
    eq(active.main_skill_sort.primary,"level"); eq(active.sidebar_skill_sort.primary,"level")
  end)
end)

test("quick preference propagation refreshes clean drafts while preserving every dirty edit",function()
  withView(snapshot(),function(view)
    assert(view:showSkillSettings(snapshot()))
    local updated=snapshot({shoprenew=false,trainall=false,main_skills=false,skill_filter=false})
    assert(view:setSkillSortPreferences(updated))
    for _,key in ipairs(quickKeys) do eq(view:skillSettingsValues()[key],updated[key]) end
    view.skill_settings_shoprenewall.click(); view.skill_settings_primary_buttons.ready.click()
    local draft=view.skill_settings_draft
    local nextSnapshot=snapshot({shoprenew=false,shoprenewall=true,trainall=true})
    view.last_state={skills={items={}}}
    assert(view:setSkillSortPreferences(nextSnapshot)); eq(view.skill_renders,1)
    eq(view.skill_settings_draft,draft); eq(draft.shoprenew,false); eq(draft.shoprenewall,false); eq(draft.trainall,false)
    eq(draft.sidebar_skill_sort.primary,"ready"); eq(draft.main_skills,false); eq(draft.skill_filter,false)
    for _,key in ipairs(quickKeys) do eq(view.settings.display[key],nextSnapshot[key]) end
    nextSnapshot.sidebar_skill_sort.primary="name"; eq(view.settings.display.sidebar_skill_sort.primary,"category")
  end)
end)

test("quick failed and throwing Saves retain the edited draft and reject reentrant preference updates",function()
  withView(snapshot(),function(view)
    local active=snapshot(); local writes=0; local throws=false
    view.options_action_callback=function(action,payload)
      if action=="skill_settings" then return active end
      writes=writes+1
      view:setSkillSortPreferences(snapshot({shoprenew=false,shoprenewall=false,trainall=false,main_skills=false}))
      for _,key in ipairs(quickKeys) do eq(view["skill_settings_"..key].click(),nil) end
      payload.shoprenew=true; payload.main_skill_sort.primary="number"
      if throws then error("disk <crash>") end
      return nil,"disk <full>"
    end
    assert(view:showSkillSettings()); view.skill_settings_shoprenew.click()
    local draft=view.skill_settings_draft
    for _,throwing in ipairs({false,true}) do
      throws=throwing
      local saved,err=view.skill_settings_save.click(); eq(saved,nil); assert(err:find("disk <",1,true))
      eq(view.skill_settings_draft,draft); eq(draft.shoprenew,false); eq(draft.main_skill_sort.primary,"uses")
      for _,key in ipairs(quickKeys) do eq(view.settings.display[key],true) end
      eq(view.settings.display.main_skills,true); eq(view.skill_settings_visible,true); eq(view.skill_settings_dirty,true)
      eq(view.skill_settings_saving,false); eq(view.skill_settings_pending_snapshot,nil)
      assert(view.skill_settings_status.text:find("disk &lt;",1,true))
    end
    eq(writes,2)
    view.options_action_callback=function(_,payload) return payload end
    assert(view.skill_settings_save.click()); eq(view.settings.display.shoprenew,false)
  end)
end)

test("quick Save rejects nonboolean draft fields before any persistence callback",function()
  for _,key in ipairs(quickKeys) do
    for _,invalid in ipairs({{}, {value="false"},{value=0},{value={}}}) do
      withView(snapshot(),function(view)
        local writes=0
        view.options_action_callback=function() writes=writes+1; return snapshot() end
        assert(view:showSkillSettings(snapshot()))
        view.skill_settings_draft[key]=invalid.value
        local saved,err=view.skill_settings_save.click(); eq(saved,nil); assert(err:find(key,1,true))
        eq(writes,0); eq(view.settings.display[key],true); eq(view.skill_settings_visible,true)
      end)
    end
  end
end)

test("quick Save validates returned boolean fields before applying a queued snapshot",function()
  for _,key in ipairs(quickKeys) do
    for _,invalid in ipairs({{}, {value="false"},{value=1},{value={}}}) do
      withView(snapshot(),function(view)
        assert(view:showSkillSettings(snapshot())); view["skill_settings_"..key].click()
        local draft=view.skill_settings_draft
        view.options_action_callback=function(_,payload)
          view:setSkillSortPreferences(snapshot({shoprenew=false,shoprenewall=false,trainall=false}))
          payload[key]=invalid.value; return payload
        end
        local saved,err=view.skill_settings_save.click(); eq(saved,nil); assert(err:find(key,1,true))
        eq(view.skill_settings_draft,draft); eq(draft[key],false); eq(view.skill_settings_visible,true)
        for _,other in ipairs(quickKeys) do eq(view.settings.display[other],true) end
        eq(view.skill_settings_saving,false); eq(view.skill_settings_pending_snapshot,nil)
      end)
    end
  end
end)

test("quick Save applies the successful returned snapshot independently of draft and queued values",function()
  withView(snapshot(),function(view)
    assert(view:showSkillSettings(snapshot())); view.skill_settings_shoprenew.click()
    view.options_action_callback=function(_,payload)
      eq(payload.shoprenew,false)
      view:setSkillSortPreferences(snapshot({shoprenew=false,shoprenewall=false,trainall=false}))
      return snapshot({shoprenew=true,shoprenewall=false,trainall=true})
    end
    local saved=assert(view.skill_settings_save.click())
    eq(saved.shoprenew,true); eq(view.settings.display.shoprenew,true)
    eq(view.settings.display.shoprenewall,false); eq(view.settings.display.trainall,true)
    eq(view.skill_settings_visible,false)
  end)
end)

test("quick controls help and Save stay within scrollable content across narrow and short sizes",function()
  withView(snapshot(),function(view)
    assert(view:showSkillSettings(snapshot()))
    local panel,content=view.skill_settings_panel,view.skill_settings_content
    for _,size in ipairs({{1200,900},{640,480},{400,300},{320,260},{240,120},{160,100},{40,40},{1,1}}) do
      assert(view:layoutSkillSettings({window_width=size[1],window_height=size[2],body_font=15}))
      eq(view.skill_settings_panel,panel); eq(view.skill_settings_content,content)
      assert(panel.x>=0 and panel.y>=0 and panel.x+panel.width<=size[1] and panel.y+panel.height<=size[2])
      assert(content.width>0 and content.height>0 and content.x+content.width<=panel.width and content.y+content.height<=panel.height)
      assert(view.skill_settings_font>=13); assert(content.content_height>=view.skill_settings_save.y+view.skill_settings_save.height)
      if view.skill_settings_title.visible then
        assert(view.skill_settings_title.height>=view.skill_settings_title_lines*21)
      end
      local buttons={}
      for _,widget in ipairs(view:skillSettingsWidgets()) do
        if widget.container==content then
          eq(widget.visible,true)
          assert(widget.x>=0 and widget.y>=0 and widget.width>0 and widget.height>0)
          assert(widget.x+widget.width<=content.content_width)
          assert(widget.y+widget.height<=content.content_height)
          if widget.click then buttons[#buttons+1]=widget end
        end
      end
      for i=1,#buttons do for j=i+1,#buttons do
        local a,b=buttons[i],buttons[j]
        eq(a.x<b.x+b.width and b.x<a.x+a.width and a.y<b.y+b.height and b.y<a.y+a.height,false)
      end end
      for _,key in ipairs(quickKeys) do assert(view["skill_settings_"..key].y<view.skill_settings_save.y) end
      assert(view.skill_settings_quick_help.height>=4*(view.skill_settings_font+6))
      assert(content.content_height>content.height)
    end
  end)
end)

test("quick controls participate in reuse validation and require the correct parent and callbacks",function()
  withView(snapshot(),function(view)
    assert(SkillSettingsView.validate(view,widgetValid,labelValid))
    for _,key in ipairs({"quick_help","shoprenew","shoprenewall","trainall"}) do
      local name="skill_settings_"..key; local widget=view[name]
      view[name]=nil
      local valid,err=SkillSettingsView.validate(view,widgetValid,labelValid)
      eq(valid,nil); assert(err:find(name,1,true)); view[name]=widget
      widget.container=view.root
      valid,err=SkillSettingsView.validate(view,widgetValid,labelValid)
      eq(valid,nil); assert(err:find("parent",1,true)); widget.container=view.skill_settings_content
      if key~="quick_help" then
        local callback=widget.setClickCallback; widget.setClickCallback=nil
        valid,err=SkillSettingsView.validate(view,widgetValid,labelValid)
        eq(valid,nil); assert(err:find("button",1,true)); widget.setClickCallback=callback
      end
    end
    assert(SkillSettingsView.validate(view,widgetValid,labelValid))
  end)
end)

test("quick callbacks can be rebound and are unavailable while hidden or disposed",function()
  withView(snapshot(),function(view)
    for _,key in ipairs(quickKeys) do eq(view["skill_settings_"..key].click(),nil) end
    assert(view:showSkillSettings(snapshot()))
    view:bindSkillSettingsCallbacks()
    for _,key in ipairs(quickKeys) do assert(view["skill_settings_"..key].click()); eq(view:skillSettingsValues()[key],false) end
    view:hideSkillSettings()
    for _,key in ipairs(quickKeys) do eq(view["skill_settings_"..key].click(),nil) end
    assert(view:showSkillSettings(snapshot())); view.disposed=true
    for _,key in ipairs(quickKeys) do eq(view["skill_settings_"..key].click(),nil) end
    eq(view:saveSkillSettings(),nil)
  end)
end)
