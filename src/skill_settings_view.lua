local SkillSort=require("skill_sort")
local SkillSettingsView={}
function SkillSettingsView.attach(View,helpers)
  local label,viewCopy,safeText=helpers.label,helpers.copy,helpers.safeText
  local function place(widget,x,y,w,h) widget:move(x,y); widget:resize(w,h); widget:show() end
local skillSortKeys={"level","uses","name","number","ready","category"}
local skillSortLabels={level="Level",uses="Remaining uses",name="Name",number="Skill number",ready="Training readiness<br>(0 uses)",category="Category<br>Combat / Utility",none="None"}
local skillSortDirections={asc="Ascending",desc="Descending"}
local skillFilterExamples="Main order changes on your next skill command; sidebar order changes when you save.<br>skill combat: all combat skills, including 0 uses.<br>skill utility: all utility skills, including 0 uses.<br>skill train: only 0-use skills (green). Displays only; does not train.<br>Zero-use rows stay green in every group.<br>The sidebar keeps all skills. Filters still work with custom colors and formatting OFF.<br>skill weapons and name prefixes also work."
local skillSortHelp="Training readiness: ascending puts 0 uses first; descending puts other skills first.<br>Category: ascending puts Combat first; descending puts Utility first.<br>Save applies both tabs; Cancel discards this draft."
local function skillSettingsSnapshot(display)
  display=type(display)=="table" and display or {}
  return {main_skills=display.main_skills~=false,
    main_skill_sort=viewCopy(SkillSort.normalize(display.main_skill_sort)),
    sidebar_skill_sort=viewCopy(SkillSort.normalize(display.sidebar_skill_sort))}
end
function View:skillSettingsWidgets()
  local widgets={}
  for _,name in ipairs({"overlay","panel","bg","title","content","text","format","preset","primary_caption","direction_caption","secondary_caption","secondary_direction_caption","summary","status","reset","cancel","save"}) do
    widgets[#widgets+1]=self["skill_settings_"..name]
  end
  for _,group in ipairs({"tabs","primary_buttons","secondary_buttons","direction_buttons","secondary_direction_buttons"}) do
    for _,button in pairs(self["skill_settings_"..group] or {}) do widgets[#widgets+1]=button end
  end
  return widgets
end
function View:createSkillSettings()
  local t=self.settings.theme
  self.skill_settings_overlay=label("DGHUD.SkillSettings.Overlay",self.root,"background:rgba(0,0,0,0.72);")
  self.skill_settings_panel=Geyser.Container:new({name="DGHUD.SkillSettings.Panel",x=0,y=0,width=640,height=720},self.root)
  self.skill_settings_bg=label("DGHUD.SkillSettings.Background",self.skill_settings_panel,"background:"..t.panel..";border:2px solid "..t.accent..";border-radius:8px;")
  self.skill_settings_title=label("DGHUD.SkillSettings.Title",self.skill_settings_panel)
  self.skill_settings_content=Geyser.ScrollBox:new({name="DGHUD.SkillSettings.Content",x=12,y=44,width=616,height=664},self.skill_settings_panel)
  for _,name in ipairs({"text","format","preset","primary_caption","direction_caption","secondary_caption","secondary_direction_caption","summary","status","reset","cancel","save"}) do
    self["skill_settings_"..name]=label("DGHUD.SkillSettings."..name,self.skill_settings_content)
  end
  self.skill_settings_tabs={}
  for _,key in ipairs({"main","sidebar"}) do self.skill_settings_tabs[key]=label("DGHUD.SkillSettings.Tab."..key,self.skill_settings_content) end
  for _,group in ipairs({"primary","secondary","direction","secondary_direction"}) do
    local buttons={}; self["skill_settings_"..group.."_buttons"]=buttons
    local keys=(group=="direction" or group=="secondary_direction") and {"asc","desc"} or skillSortKeys
    for _,key in ipairs(keys) do buttons[key]=label("DGHUD.SkillSettings."..group.."."..key,self.skill_settings_content) end
    if group=="secondary" then buttons.none=label("DGHUD.SkillSettings.secondary.none",self.skill_settings_content) end
    for _,key in ipairs({"ready","category"}) do
      local button=buttons[key]
      if button and button.setToolTip then
        local tooltip=key=="ready" and "Training readiness means 0 uses. Ascending: 0 uses first. Descending: other skills first." or "Ascending: Combat first. Descending: Utility first."
        pcall(button.setToolTip,button,tooltip)
      end
    end
  end
  self:bindSkillSettingsCallbacks()
  self.skill_settings_visible=false
  for _,widget in ipairs(self:skillSettingsWidgets()) do widget:hide() end
end
function View:bindSkillSettingsCallbacks()
  local function live() return not self.disposed and self.root and self.skill_settings_visible and self.skill_settings_draft and not self.skill_settings_saving end
  for _,key in ipairs({"main","sidebar"}) do
    local tab=key
    self.skill_settings_tabs[tab]:setClickCallback(function()
      if not live() then return nil,"Skills settings are unavailable." end
      self.skill_settings_target=tab; self:renderSkillSettings(); return true
    end)
  end
  for _,group in ipairs({"primary","secondary","direction","secondary_direction"}) do
    for key,button in pairs(self["skill_settings_"..group.."_buttons"]) do
      local field,value=group,key
      button:setClickCallback(function() return self:changeSkillSort(field,value) end)
    end
  end
  self.skill_settings_format:setClickCallback(function()
    if not live() then return nil,"Skills settings are unavailable." end
    self.skill_settings_draft.main_skills=not self.skill_settings_draft.main_skills
    self.skill_settings_dirty=true; self.skill_settings_error=nil; self:renderSkillSettings(); return true
  end)
  self.skill_settings_preset:setClickCallback(function()
    if not live() then return nil,"Skills settings are unavailable." end
    self.skill_settings_draft[self.skill_settings_target.."_skill_sort"]=skillSettingsSnapshot().main_skill_sort
    self.skill_settings_dirty=true; self.skill_settings_error=nil; self:renderSkillSettings(); return true
  end)
  self.skill_settings_reset:setClickCallback(function()
    if not live() then return nil,"Skills settings are unavailable." end
    self.skill_settings_draft=skillSettingsSnapshot()
    self.skill_settings_dirty=true; self.skill_settings_error=nil; self:renderSkillSettings(); return true
  end)
  self.skill_settings_save:setClickCallback(function() return self:saveSkillSettings() end)
  self.skill_settings_cancel:setClickCallback(function() return self:hideSkillSettings() end)
  self.skill_settings_overlay:setClickCallback(function() return self:hideSkillSettings() end)
end
function View:setSkillSortPreferences(display)
  if self.disposed or not self.root then return nil,"HUD view is unavailable." end
  local snapshot=skillSettingsSnapshot(display)
  -- Runtime may refresh the view inside Save. Apply only its successful result.
  if self.skill_settings_saving then self.skill_settings_pending_snapshot=snapshot; return true end
  if type(self.settings.display)~="table" then self.settings.display={} end
  for _,key in ipairs({"main_skills","main_skill_sort","sidebar_skill_sort"}) do self.settings.display[key]=viewCopy(snapshot[key]) end
  self:setMainSkillsEnabled(snapshot.main_skills)
  if self.skill_settings_visible and not self.skill_settings_dirty then self.skill_settings_draft=viewCopy(snapshot); self:renderSkillSettings() end
  self.skills_signature=nil
  if self.last_state then self:renderSkills(self.last_state) end
  return true
end
function View:showSkillSettings(snapshot)
  if self.disposed or not self.root then return nil,"HUD view is unavailable." end
  if self.skill_settings_visible then return true end
  if snapshot==nil then
    if not self.options_action_callback then return nil,"Skills settings are unavailable." end
    local called,value,err=pcall(self.options_action_callback,"skill_settings")
    if not called then return nil,tostring(value) end
    if type(value)~="table" then return nil,err or "Skills settings are unavailable." end
    snapshot=value
  end
  self:hideHelp(); self:hideMapSettings(); self:hideMapLibrary(); self:hideRollerSettings()
  self:hideChatSettings(); self:hideKeybindingSettings(); self:hideColorSettings(); self:hideSupport(); self:hideLatentPsionAlert()
  if self.feedback_visible then
    local hidden,err=self:hideFeedback(); if not hidden then return nil,err end
  end
  self:setColorMenuVisible(false)
  self.skill_settings_draft=skillSettingsSnapshot(snapshot)
  self.skill_settings_target="sidebar"; self.skill_settings_dirty=false; self.skill_settings_error=nil; self.skill_settings_visible=true
  if self.layout then self:layoutSkillSettings(self.layout) end
  return true
end
function View:hideSkillSettings()
  self.skill_settings_visible=false; self.skill_settings_draft=nil; self.skill_settings_dirty=false; self.skill_settings_error=nil
  for _,widget in ipairs(self:skillSettingsWidgets()) do widget:hide() end
  return true
end
function View:changeSkillSort(field,value)
  if self.disposed or not self.root or not self.skill_settings_visible or not self.skill_settings_draft or self.skill_settings_saving then return nil,"Skills settings are unavailable." end
  local buttons=self["skill_settings_"..tostring(field).."_buttons"]
  if type(buttons)~="table" or not buttons[value] then return nil,"Invalid skill sort choice." end
  local config=self.skill_settings_draft[self.skill_settings_target.."_skill_sort"]
  config[field]=value
  self.skill_settings_dirty=true; self.skill_settings_error=nil; self:renderSkillSettings(); return true
end
function View:skillSettingsValues()
  if not self.skill_settings_draft then return nil,"Skills settings are unavailable." end
  return viewCopy(self.skill_settings_draft)
end
function View:saveSkillSettings()
  if self.disposed or not self.root or not self.skill_settings_visible or not self.skill_settings_draft or self.skill_settings_saving then return nil,"Skills settings are unavailable." end
  local function failed(err)
    self.skill_settings_saving=false; self.skill_settings_pending_snapshot=nil
    self.skill_settings_error=tostring(err or "Could not save Skills settings.")
    self:renderSkillSettings(); if self.layout then self:layoutSkillSettings(self.layout) end
    return nil,self.skill_settings_error
  end
  if not self.options_action_callback then return failed("Skills settings are unavailable.") end
  local draft=self:skillSettingsValues()
  for _,key in ipairs({"main_skill_sort","sidebar_skill_sort"}) do
    local ok,err=SkillSort.validate(draft[key]); if not ok then return failed(err or "Invalid skill sort settings.") end
  end
  self.skill_settings_saving=true
  local called,saved,err=pcall(self.options_action_callback,"skill_settings_save",draft)
  if not called then return failed(saved) end
  if type(saved)~="table" then return failed(err) end
  if type(saved.main_skills)~="boolean" then return failed("Save returned invalid Skills settings.") end
  for _,key in ipairs({"main_skill_sort","sidebar_skill_sort"}) do
    local ok,why=SkillSort.validate(saved[key]); if not ok then return failed(why or "Save returned invalid skill sort settings.") end
  end
  self.skill_settings_saving=false; self.skill_settings_pending_snapshot=nil
  local applied,why=self:setSkillSortPreferences(saved); if not applied then return failed(why) end
  self:hideSkillSettings(); return saved
end
function View:renderSkillSettings()
  if self.disposed or not self.root then return nil,"HUD view is unavailable." end
  if not self.skill_settings_visible or not self.skill_settings_draft then return true end
  local t=self.settings.theme; local font=self.skill_settings_font or 13
  local function text(widget,value) widget:setStyleSheet("background:transparent;color:"..t.text..";font-size:"..font.."px;"); widget:echo(View.withFont(value,font)) end
  local function button(widget,value,active)
    widget:setStyleSheet("background:"..(active and "#193024" or "#151d18")..";border:"..(active and "2" or "1").."px solid "..(active and t.jade or t.border)..";border-radius:5px;color:"..(active and t.jade or t.text)..";font-size:"..font.."px;")
    widget:echo(View.withFont("<center><b>"..value.."</b></center>",font))
  end
  self.skill_settings_title:setStyleSheet("background:transparent;color:"..t.accent..";font-weight:700;")
  self.skill_settings_title:echo(View.withFont("<b>SKILL SETTINGS</b>",font+3))
  text(self.skill_settings_text,skillFilterExamples)
  for _,key in ipairs({"main","sidebar"}) do button(self.skill_settings_tabs[key],key=="main" and "MAIN DISPLAY" or "SIDEBAR",self.skill_settings_target==key) end
  button(self.skill_settings_format,"MAIN SKILLS FORMAT: "..(self.skill_settings_draft.main_skills and "ON" or "OFF"),self.skill_settings_draft.main_skills)
  button(self.skill_settings_preset,"LEVEL THEN USES<br>Highest level, fewest uses",false)
  local config=self.skill_settings_draft[self.skill_settings_target.."_skill_sort"]
  text(self.skill_settings_primary_caption,"<b>PRIMARY SORT KEY</b>")
  text(self.skill_settings_direction_caption,"<b>PRIMARY DIRECTION</b>")
  text(self.skill_settings_secondary_caption,"<b>SECONDARY KEY (OPTIONAL)</b>")
  text(self.skill_settings_secondary_direction_caption,"<b>SECONDARY DIRECTION</b>")
  for _,group in ipairs({"primary","secondary","direction","secondary_direction"}) do
    for key,widget in pairs(self["skill_settings_"..group.."_buttons"]) do button(widget,skillSortDirections[key] or skillSortLabels[key],config[group]==key) end
  end
  local primary=skillSortLabels[config.primary]:gsub("<br>"," ")
  local secondary=skillSortLabels[config.secondary]:gsub("<br>"," ")
  text(self.skill_settings_summary,"<b>"..(self.skill_settings_target=="main" and "Main display" or "Sidebar")..":</b> "..primary.." · "..skillSortDirections[config.direction]..(config.secondary~="none" and "<br>then "..secondary.." · "..skillSortDirections[config.secondary_direction] or "<br>No secondary key"))
  text(self.skill_settings_status,self.skill_settings_error and "<span style='color:"..t.hp.."'><b>"..safeText(self.skill_settings_error).."</b></span>" or skillSortHelp)
  button(self.skill_settings_reset,"RESET TO DEFAULTS",false); button(self.skill_settings_cancel,"CANCEL",false); button(self.skill_settings_save,"SAVE",false)
  return true
end
function View:layoutSkillSettings(layout)
  if self.disposed or not self.root then return nil,"HUD view is unavailable." end
  local widgets=self:skillSettingsWidgets()
  if not self.skill_settings_visible then for _,widget in ipairs(widgets) do widget:hide() end; return true end
  local width,height=math.max(1,tonumber(layout.window_width) or 1200),math.max(1,tonumber(layout.window_height) or 800)
  local margin=math.min(18,math.floor(width/20),math.floor(height/20))
  local anchor=self.options_anchor or {}
  local top=math.min(height-1,math.max(0,(tonumber(anchor.y) or 0)+(tonumber(anchor.height) or 0)+4))
  local pw,ph=math.min(660,width-margin*2),math.min(760,math.max(1,height-top-margin))
  local padding=math.min(12,math.floor(pw/10),math.floor(ph/10)); local header=math.min(44,math.floor(ph*.4))
  place(self.skill_settings_overlay,0,0,"100%","100%")
  place(self.skill_settings_panel,0,top,pw,ph)
  place(self.skill_settings_bg,0,0,pw,ph)
  place(self.skill_settings_title,padding,padding,math.max(1,pw-padding*2),math.max(1,header-padding))
  if header<22 then self.skill_settings_title:hide() end
  local viewport=math.max(1,pw-padding*2)
  place(self.skill_settings_content,padding,header,viewport,math.max(1,ph-header-padding))
  -- Very narrow windows retain readable text and permit horizontal scrolling.
  local inner=math.max(220,viewport-18); self.skill_settings_content.content_width=inner
  self.skill_settings_font=math.max(13,math.min(15,tonumber(layout.body_font) or 13))
  local font=self.skill_settings_font; local row=font*2+12; local y=0; local gap=6
  local function full(widget,h) place(widget,0,y,inner,h); y=y+h+gap end
  local hintRows=0
  local hintColumns=math.max(1,math.floor(inner/(font*.65)))
  for line in (skillFilterExamples.."<br>"):gmatch("(.-)<br>") do
    local plainLine=line:gsub("<[^>]+>","")
    hintRows=hintRows+math.max(1,math.ceil(#plainLine/hintColumns))+1
  end
  full(self.skill_settings_text,hintRows*(font+6))
  local tabw=(inner-gap)/2
  place(self.skill_settings_tabs.main,0,y,tabw,row); place(self.skill_settings_tabs.sidebar,tabw+gap,y,tabw,row); y=y+row+gap
  full(self.skill_settings_format,row); full(self.skill_settings_preset,row+font)
  local columns=inner>=480 and 3 or inner>=260 and 2 or 1
  local function choices(buttons,keys)
    local bw=(inner-gap*(columns-1))/columns
    for index,key in ipairs(keys) do local col=(index-1)%columns; local line=math.floor((index-1)/columns); place(buttons[key],col*(bw+gap),y+line*(row+font+gap),bw,row+font) end
    y=y+math.ceil(#keys/columns)*(row+font+gap)
  end
  local function directions(buttons)
    place(buttons.asc,0,y,tabw,row); place(buttons.desc,tabw+gap,y,tabw,row); y=y+row+gap
  end
  full(self.skill_settings_primary_caption,font+10); choices(self.skill_settings_primary_buttons,skillSortKeys)
  full(self.skill_settings_direction_caption,font+10); directions(self.skill_settings_direction_buttons)
  full(self.skill_settings_secondary_caption,font+10)
  local secondary={"none"}; for _,key in ipairs(skillSortKeys) do secondary[#secondary+1]=key end
  choices(self.skill_settings_secondary_buttons,secondary)
  full(self.skill_settings_secondary_direction_caption,font+10); directions(self.skill_settings_secondary_direction_buttons)
  full(self.skill_settings_summary,(font+6)*3)
  local status=self.skill_settings_error or skillSortHelp
  local statusRows=0
  for line in (status.."<br>"):gmatch("(.-)<br>") do statusRows=statusRows+math.max(1,math.ceil(#line/math.max(1,math.floor(inner/(font*.58))))) end
  full(self.skill_settings_status,math.max(3,statusRows)*(font+6))
  full(self.skill_settings_reset,row)
  place(self.skill_settings_cancel,0,y,tabw,row); place(self.skill_settings_save,tabw+gap,y,tabw,row); y=y+row+gap
  self.skill_settings_content.content_height=y
  self:renderSkillSettings(); View.raiseCards(widgets); return true
end

end
function SkillSettingsView.validate(candidate,widgetValid,labelValid)
  local panel=candidate.skill_settings_panel
  local content=candidate.skill_settings_content
  for _,name in ipairs({"panel","content","overlay","bg","title","text","format","preset","primary_caption","direction_caption","secondary_caption","secondary_direction_caption","summary","status","reset","cancel","save"}) do
    local widget=candidate["skill_settings_"..name]
    local valid=(name=="panel" or name=="content") and widgetValid or labelValid
    if not valid(widget) then return nil,"preserved HUD view is missing skill_settings_"..name end
    local parent=(name=="panel" or name=="overlay") and candidate.root or (name=="bg" or name=="title" or name=="content") and panel or content
    if widget.container~=parent then return nil,"preserved HUD skill settings parent is invalid" end
    if ({overlay=true,format=true,preset=true,reset=true,cancel=true,save=true})[name] and type(widget.setClickCallback)~="function" then return nil,"preserved HUD skill settings button is incomplete" end
  end
  for _,group in ipairs({"tabs","primary_buttons","secondary_buttons","direction_buttons","secondary_direction_buttons"}) do
    local buttons=candidate["skill_settings_"..group]
    if type(buttons)~="table" then return nil,"preserved HUD skill settings controls are incomplete" end
    local keys=group=="tabs" and {"main","sidebar"} or group:find("direction",1,true) and {"asc","desc"} or {"level","uses","name","number","ready","category"}
    if group=="secondary_buttons" then keys[#keys+1]="none" end
    for _,key in ipairs(keys) do
      local widget=buttons[key]
      if not labelValid(widget) or type(widget.setClickCallback)~="function" or widget.container~=content then return nil,"preserved HUD skill settings control is incomplete: "..group.."."..key end
    end
  end
  if type(candidate.option_action_buttons)~="table" or not labelValid(candidate.option_action_buttons.skill_settings) or type(candidate.option_action_buttons.skill_settings.setClickCallback)~="function" then return nil,"preserved HUD skill settings action is incomplete" end
  return true
end
return SkillSettingsView
