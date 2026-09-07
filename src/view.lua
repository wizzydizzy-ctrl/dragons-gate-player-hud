local Navigation=require("navigation")
local Layout=require("layout")
local MapCatalog=require("map_catalog")
local View={}; View.__index=View
function View.withFont(text,size) return "<span style='font-size:"..tonumber(size).."px'>"..text.."</span>" end
function View.raiseCards(cards) for _,card in ipairs(cards or {}) do if card and card.raise then card:raise() end end end
function View.monospaceFont(available)
  available=type(available)=="table" and available or {}
  for _,name in ipairs({"DejaVu Sans Mono","Liberation Mono","Consolas","Menlo","Monaco","Courier New","Courier","Monospace"}) do if available[name] then return name end end
  return "Courier New"
end
local function esc(v) return tostring(v or ""):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;") end
local function safeText(v) return esc(tostring(v or ""):gsub("%c"," ")) end
local function safeChatText(v) return tostring(v or ""):gsub("%c"," ") end
local function groupedNumber(value)
  local text=tostring(math.floor(tonumber(value) or 0)); local changed
  repeat text,changed=text:gsub("^(-?%d+)(%d%d%d)","%1,%2") until changed==0
  return text
end
local function alignmentLabel(value)
  local raw=tostring(value or ""); local key=raw:lower()
  if key=="order" then return "Orderly" elseif key=="entropy" then return "Entropic" elseif key=="chaos" then return "Chaotic" end
  return raw
end
local chat_colors={ROOM="text",OWN="jade",WHISPER="#d49bc8",ESP="#a6a3e8",DRAGON="#d9a869",CONTACT="#8bc6b0",STAFF="#e09672"}
local function chatScroll(output,ranges)
  local okCurrent,current=pcall(function() return output:getScroll() end)
  local okLast,last=pcall(function() return output:getLastLineNumber() end)
  if not okCurrent or not okLast or current==nil or last==nil then return {at_bottom=true,line=0} end
  local state={at_bottom=current>=last,line=current}
  if not state.at_bottom then
    for index,range in ipairs(ranges or {}) do
      if current>=range.first and current<=range.last then
        state.entry=range.entry; state.index=index; state.offset=current-range.first; break
      end
    end
  end
  return state
end
local function restoreChatScroll(output,state,ranges)
  if state.at_bottom then pcall(function() output:scrollTo() end); return end
  local ok,last=pcall(function() return output:getLastLineNumber() end)
  local line=state.line
  for index,range in ipairs(ranges or {}) do
    if range.entry==state.entry or (state.entry==nil and index==state.index) then
      line=range.first+math.min(math.max(0,state.offset or 0),range.last-range.first); break
    end
  end
  pcall(function() output:scrollTo(math.min(line,(ok and tonumber(last)) or line)) end)
end
function View.chatLine(entry,t,timestamps)
  entry=type(entry)=="table" and entry or {}
  local category=tostring(entry.category or "CHAT"):upper()
  local color=chat_colors[category] or t.accent
  if color=="text" then color=t.text elseif color=="jade" then color=t.jade end
  local stamp=""
  if timestamps~=false then
    local time=tostring(entry.timestamp or ""):match("T(%d%d:%d%d)")
    if time then stamp="#"..t.muted:gsub("^#","").."["..time.."]#r " end
  end
  local prefix=stamp.."#"..tostring(color):gsub("^#","")..safeText(category).."#r"
  return prefix," "..safeChatText(entry.line or entry.message).."\n"
end
function View.identityContent(character,t,layout)
  local physical=character.physical or {}; local detail=""
  if physical.age or physical.sex or physical.height then detail="<br><span style='color:"..t.muted.."'>"..esc(physical.age or "")..(physical.age and " · " or "")..esc(physical.sex or "")..(physical.height and " · "..esc(physical.height) or "").."</span>" end
  local faith=""; if character.deity or character.religion then
    local values={}; if character.religion and character.religion~="" then values[#values+1]=esc(character.religion) end; if character.deity and character.deity~="" then values[#values+1]=esc(character.deity) end
    faith="<br><span style='color:"..t.muted.."'>"..table.concat(values," · ").."</span>"
  end
  local favorsLine=character.favors~=nil and "<br><span style='color:"..t.muted.."'>Favors: "..groupedNumber(character.favors).."</span>" or ""
  local standing={}; if character.religious_balance and character.religious_balance~="" then standing[#standing+1]=esc(character.religious_balance) end; local alignment=alignmentLabel(character.alignment); if alignment~="" then standing[#standing+1]=esc(alignment) end
  local standingLine=#standing>0 and "<br><span style='color:"..t.muted.."'>"..table.concat(standing," · ").."</span>" or ""
  return View.withFont("<span style='color:"..t.accent..";font-size:"..layout.heading_font.."px'><b>"..esc(character.full_name).."</b></span><br><span style='color:"..t.jade.."'><b>"..esc(character.race).." · "..esc(character.class).."</b></span>"..detail..faith..favorsLine..standingLine,layout.body_font)
end
function View.headerContent(layout,t,fullName)
  local detail=layout.mode=="compact" and " &nbsp; <span style='color:"..t.text.."'><b>"..esc(fullName).."</b></span>" or ""
  return View.withFont("<span style='color:"..t.accent..";font-size:"..layout.heading_font.."px'><b>DRAGONS GATE</b></span>"..detail,layout.body_font)
end
function View.clockContent(layout,t,clock)
  clock=type(clock)=="table" and clock or {}
  local clockFont=math.max(10,tonumber(layout.header_clock_font) or ((tonumber(layout.body_font) or 16)-4))
  return "<div style='text-align:right'><span style='font-size:"..clockFont.."px;line-height:1.05'><span style='color:"..t.muted.."'>Real Time:</span> <b>"..esc(clock.real_time or "—").."</b><br><span style='color:"..t.muted.."'>Game Time:</span> <b>"..esc(clock.game_time or "—").."</b> <span style='color:"..t.jade.."'>· <b>"..esc(clock.period or "—").."</b></span></span></div>"
end
function View.inventoryRows(items,capacity)
  items=items or {}; capacity=math.max(0,tonumber(capacity) or 0); local rows={}
  if #items<=capacity then for _,item in ipairs(items) do rows[#rows+1]=item end; return rows end
  local visible=math.max(0,capacity-1); for i=1,visible do rows[#rows+1]=items[i] end
  if capacity>0 then rows[#rows+1]={label="+"..(#items-visible).." more",overflow=#items-visible} end
  return rows
end
local function clipped(value,width)
  value=tostring(value or ""):gsub("%c"," "); width=math.max(1,tonumber(width) or 1)
  if #value<=width then return value end
  return width>1 and value:sub(1,width-1).."~" or value:sub(1,1)
end
local function skillFormat(nameWidth,gaps,levelWidth,useWidth)
  gaps=math.max(0,math.min(2,tonumber(gaps) or 2))
  levelWidth=math.max(1,tonumber(levelWidth) or 3)
  useWidth=math.max(1,tonumber(useWidth) or 4)
  return "%-"..nameWidth.."s"..(gaps>=1 and " " or "").."%"..levelWidth.."s"..(gaps>=2 and " " or "").."%"..useWidth.."s"
end
local function skillHeading(value,width,alternatives)
  width=math.max(1,tonumber(width) or 1)
  if #value<=width then return value end
  for _,short in ipairs(alternatives or {}) do if #short<=width then return short end end
  return value:sub(1,width)
end
function View.skillHeader(nameWidth,gaps,levelWidth,useWidth)
  levelWidth=math.max(1,tonumber(levelWidth) or 3); useWidth=math.max(1,tonumber(useWidth) or 4)
  return string.format(skillFormat(nameWidth,gaps,levelWidth,useWidth),skillHeading("SKILLS",nameWidth,{"SKILL","SK","S"}),skillHeading("LVL",levelWidth,{"LV","L"}),skillHeading("USES",useWidth,{"USE","U"}))
end
function View.skillDisplayName(value)
  value=tostring(value or ""):gsub("%c"," ")
  value=value:gsub("^Identify%s+","ID "):gsub("Gems/Minerals","Gems"):gsub("%s+Quality$","")
  return value
end
function View.skillLine(skill,nameWidth,gaps,levelWidth,useWidth)
  nameWidth=math.max(1,tonumber(nameWidth) or 22); skill=skill or {}
  return string.format(skillFormat(nameWidth,gaps,levelWidth,useWidth),clipped(View.skillDisplayName(skill.name),nameWidth),tonumber(skill.level) or 0,tonumber(skill.remain) or 0)
end
function View.detailsContent(combat,attributes,t,layout,vitals)
  combat=combat or {}; attributes=attributes or {}
  vitals=vitals or {}
  local roundtime=tonumber(vitals.roundtime) or 0
  local armor="Armor <b>"..(combat.body_armor~=nil and esc(combat.body_armor).."%" or "—").."</b>"
  local stance="Stance <b>"..esc(combat.stance or "—").."</b>"; local offense=combat.or_rating~=nil and "OR <b>"..esc(combat.or_rating).."</b>" or ""
  local timing="Roundtime <b>"..(roundtime==0 and "READY" or esc(roundtime)).."</b>"; local defense=combat.dr~=nil and "DR <b>"..esc(combat.dr).."</b>" or ""
  local posture=vitals.sitting and "Sitting" or (vitals.standing and "Standing" or nil)
  local position="Position <b>"..esc(vitals.position~=nil and vitals.position or "—").."</b>"
  local function right(value) return value~="" and value or "&nbsp;" end
  local rows="<table width='100%' cellspacing='0' cellpadding='0'>"..
    "<tr><td>"..armor.."</td><td align='right'>&nbsp;</td></tr>"..
    "<tr><td>"..stance.."</td><td align='right'>"..right(offense).."</td></tr>"..
    "<tr><td>"..timing.."</td><td align='right'>"..right(defense).."</td></tr>"..
    "<tr><td>"..position.."</td><td align='right'>"..right(posture and "<b>"..posture.."</b>" or "").."</td></tr></table>"
  local baseFont=layout.combat_font or layout.equipment_font or layout.inventory_font or layout.body_font or 12
  return View.withFont("<span style='color:"..t.accent.."'><b>COMBAT</b></span><br>"..rows,math.max(8,baseFont-2))
end
function View.attributeStripContent(attributes,t,layout)
  local parts={}; attributes=attributes or {}
  for _,key in ipairs({"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"}) do
    parts[#parts+1]="<span style='color:"..t.muted.."'>"..key.."</span> <b>"..esc(attributes[key] or "—").."</b>"
  end
  return View.withFont(table.concat(parts," &nbsp; "),layout.attribute_strip_font or layout.small_font)
end
function View.equipmentContent(v,items,t,layout)
  if layout==nil then layout=t; t=items; items={} end
  local function ready(value) return value and "<span style='color:"..t.jade.."'><b>READY</b></span>" or "<span style='color:#c85b4b'><b>NOT READY</b></span>" end
  local body="Weapon &nbsp; "..ready(v.weapon_readied).."<br>Shield &nbsp; "..ready(v.shield_readied)
  return View.withFont("<span style='color:"..t.accent.."'><b>EQUIPMENT</b></span><br>"..body,layout.equipment_font or layout.body_font)
end
function View.inventoryContent(inventory,vitals,t,layout,capacity)
  inventory=inventory or {}; vitals=vitals or {}
  local rows=View.inventoryRows(inventory.items,capacity); local lines={"<span style='color:"..t.accent.."'><b>INVENTORY</b></span>"}
  for _,item in ipairs(rows) do if item.overflow then lines[#lines+1]="<span style='color:"..t.muted.."'>"..item.label.."</span>" else lines[#lines+1]=esc(item.name).." <span style='color:"..t.muted.."'>"..esc(item.weight or "").." lb</span>" end end
  lines[#lines+1]="<span style='color:"..(t.gold or "#e0b84f").."'><b>"..esc(vitals.gold or 0).."gp</b></span> &nbsp; <span style='color:"..(t.silver or "#c0c0c0").."'><b>"..esc(vitals.silver or 0).."sp</b></span>"
  local carry=vitals.carry or {}; lines[#lines+1]="Carry <b>"..esc(carry.current or 0).." / "..esc(carry.maximum or 0).." / </b><span style='color:"..t.muted.."'><b>"..esc(carry.percent or 0).."%</b></span>"
  return View.withFont(table.concat(lines,"<br>"),layout.inventory_font)
end
local function label(name,parent,style,geyser)
  local item=(geyser or Geyser).Label:new({name=name,x=0,y=0,width=10,height=10},parent); item:setStyleSheet(style or "background:transparent;"); return item
end
local function input(name,parent,geyser)
  local api=geyser or Geyser
  return api.CommandLine:new({name=name,x=0,y=0,width=100,height=24},parent)
end
local function gauge(name,parent,color,theme)
  local g=Geyser.Gauge:new({name=name,x=0,y=0,width=100,height=18},parent)
  g.front:setStyleSheet("background:"..color..";border-radius:5px;"); g.back:setStyleSheet("background:#080b0a;border:1px solid "..theme.border..";border-radius:5px;"); g.text:setStyleSheet("background:transparent;color:"..theme.text..";font-size:11px;font-weight:600;")
  return g
end
local function place(item,x,y,w,h) item:move(x,y); item:resize(w,h); item:show() end
local help_entries={
  {command="dghud help",description="Open this command guide."},
  {command="dghud colors [on|off|toggle|status]",description="Control all optional DGHUD output colors."},
  {command="dghud colors <feature> on|off|toggle|status",description="Toggle room, exits, currency, races, classes, travel, combat, spell, discovery, or illumination highlights."},
  {command="dghud check",description="Check GitHub for a newer HUD release."},
  {command="dghud update",description="Install the newest verified HUD release, then refresh character data."},
  {command="dghud reload",description="Reload the HUD using your saved preferences."},
  {command="rr start|stop|stats|last|reset|help",description="Control the built-in OG Dragons Gate stat autoroller."},
  {command="rr set total|hard|max|delay|STAT <value>",description="Adjust and persist autoroller targets without editing scripts."},
  {command="dghud config",description="Open the DGHUD settings location."},
  {command="dghud purge",description="Remove DGHUD-owned installed data.",warning=true},
  {command="dghud chatstatus",description="Show chat capture, filter, and storage status."},
  {command="dghud mapstatus",description="Show mapper, walking, and latest-error status."},
  {command="dghud map debug",description="Send a sanitized mapper diagnostic anonymously and show its reference number."},
  {command="dghud map debug folder",description="Save a private local diagnostic copy and open its folder."},
  {command="dghud map library",description="Open the community map library inside the HUD."},
  {command="MAP SETTINGS → MAP LIBRARY…",description="Browse credited maps, export your map, review an import, or prepare an editable stash for publication."},
  {command="dghud map export <name> <publisher>",description="Create a private local JSON backup. Use Map Library → SHARE to submit maps anonymously for review."},
  {command="dghud map folder",description="Open the local export/import folder."},
  {command="dghud map import <name>",description="Validate a downloaded map and preview canonical room-ID conflicts without changing the map."},
  {command="dghud map import area <area> keep|replace|skip",description="Choose the conflict policy for one imported area."},
  {command="dghud map import room <number> keep|replace|skip",description="Override the choice for one canonical room number."},
  {command="dghud map import confirm|cancel",description="Apply the exact reviewed import transaction or discard its preview."},
  {command="dghud mapper [on|off|toggle|status]",description="Show or hide the mapper and enable or pause automatic mapping without deleting saved rooms."},
  {command="walkto <room number>",description="Walk to a known mapped room."},
  {command="walkstop",description="Stop the current automatic walk."},
  {command="mapcenter",description="Center the embedded map on your current room."},
  {command="dghud map delete room <number>",description="Preview deletion of one DGHUD-owned room.",warning=true},
  {command="dghud map clear submap <number>",description="Preview deletion of one DGHUD-owned submap.",warning=true},
  {command="dghud map clear area <name>",description="Preview deletion of one DGHUD-owned area.",warning=true},
  {command="dghud map clear current",description="Preview deletion of the HUD map or submap containing your current room.",warning=true},
  {command="dghud map clear all",description="Preview a reset of every DGHUD-owned map and submap.",warning=true},
  {command="dghud map cancel",description="Cancel a pending map cleanup preview."},
  {command="dghud map confirm <token>",description="Confirm the exact pending cleanup preview.",warning=true},
}
function View.defaultHelpEntries()
  local result={}; for i,entry in ipairs(help_entries) do result[i]={command=entry.command,description=entry.description,warning=entry.warning} end; return result
end
function View.helpContent(entries,t,layout)
  local font=math.max(11,tonumber(layout and layout.help_font) or 13); local lines={}
  for _,entry in ipairs(entries or View.defaultHelpEntries()) do
    local commandColor=entry.warning and t.hp or t.jade
    lines[#lines+1]="<span style='color:"..commandColor..";font-size:"..font.."px'><b>"..safeText(entry.command).."</b></span><br><span style='color:"..t.text..";font-size:"..font.."px'>"..safeText(entry.description).."</span>"
  end
  return table.concat(lines,"<br><br>")
end
function View.helpText(entries)
  local lines={}; for _,entry in ipairs(entries or View.defaultHelpEntries()) do lines[#lines+1]=tostring(entry.command).." — "..tostring(entry.description) end; return table.concat(lines,"\n")
end
function View.mapImportConflictModel(conflicts,choices)
  local allowed={keep_mine=true,use_imported=true,skip_area=true}; local rows={}
  for index,item in ipairs(type(conflicts)=="table" and conflicts or {}) do
    local choice=type(choices)=="table" and choices[index] or nil
    rows[#rows+1]={area=tostring(item.area or "Unknown area"),local_rooms=tonumber(item.local_rooms) or 0,imported_rooms=tonumber(item.imported_rooms) or 0,choice=allowed[choice] and choice or "skip_area"}
  end
  return rows
end
function View.poiTags(points,zoom,maxWidth)
  zoom=math.max(.1,tonumber(zoom) or 1); maxWidth=math.max(4,math.floor(tonumber(maxWidth) or 18)); local result={}; local occupied={}
  table.sort(points or {},function(a,b) local ap,bp=tonumber(a.priority) or 0,tonumber(b.priority) or 0; if ap~=bp then return ap>bp end; return tostring(a.text or "")<tostring(b.text or "") end)
  for _,point in ipairs(points or {}) do
    local full=tostring(point.text or ""):match("^%s*(.-)%s*$"); local x,y=tonumber(point.x),tonumber(point.y)
    if full~="" and x and y then
      local limit=math.max(4,math.min(maxWidth,math.floor(maxWidth*math.min(1,zoom))))
      local shown=#full>limit and full:sub(1,math.max(1,limit-1)).."…" or full
      local key=math.floor(x*zoom+.5)..":"..math.floor(y*zoom+.5)
      if not occupied[key] then occupied[key]=true; result[#result+1]={x=x,y=y,text=shown,tooltip=full,priority=tonumber(point.priority) or 0} end
    end
  end
  return result
end
local function listViewportWidth(output,plannedWidth,override)
  local outer=tonumber(plannedWidth) or 1
  if output and type(output.get_width)=="function" then
    local ok,value=pcall(output.get_width,output); value=ok and tonumber(value) or nil
    if value and value>0 and math.abs(value-outer)<=1 then outer=value end
  end
  local scrollbar=tonumber(override)
  if not scrollbar then scrollbar=math.max(40,math.min(48,math.ceil(outer*.16))) end
  return math.max(1,outer-math.max(0,math.min(scrollbar,outer-1))),scrollbar
end
function View.new(settings)
  local self=setmetatable({settings=settings,geyser=Geyser,direction_buttons={},utility_buttons={},exit_available={}},View); local t=settings.theme
  local available={}; if type(rawget(_G,"getAvailableFonts"))=="function" then local ok,value=pcall(getAvailableFonts); if ok and type(value)=="table" then available=value end end
  self.list_font_family=View.monospaceFont(available)
  self.root=Geyser.Container:new({name="DGHUD.Root",x=0,y=0,width="100%",height="100%"})
  self.header=label("DGHUD.Header",self.root,"background:"..t.background..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:10px 18px;")
  self.color_toggle=label("DGHUD.Header.ColorToggle",self.root,"background:#17231c;border:1px solid "..t.jade..";border-radius:4px;color:"..t.jade..";font-weight:700;")
  if self.color_toggle.setToolTip then pcall(self.color_toggle.setToolTip,self.color_toggle,"Open DGHUD options") end
  self.color_menu_scrim=label("DGHUD.Header.ColorMenuScrim",self.root,"background:transparent;")
  self.color_menu=Geyser.Container:new({name="DGHUD.Header.ColorMenu",x=0,y=0,width=220,height=164},self.root)
  self.color_menu_bg=label("DGHUD.Header.ColorMenu.Background",self.color_menu,"background:"..t.panel..";border:1px solid "..t.border..";border-radius:6px;")
  self.options_scroll=Geyser.ScrollBox:new({name="DGHUD.Header.Options.Scroll",x=4,y=4,width=212,height=156},self.color_menu)
  self.color_settings_overlay=label("DGHUD.ColorSettings.Overlay",self.root,"background:rgba(0,0,0,0.72);")
  self.color_settings_panel=Geyser.Container:new({name="DGHUD.ColorSettings.Panel",x=0,y=0,width=620,height=520},self.root)
  self.color_settings_bg=label("DGHUD.ColorSettings.Background",self.color_settings_panel,"background:"..t.panel..";border:2px solid "..t.accent..";border-radius:8px;")
  self.color_settings_title=label("DGHUD.ColorSettings.Title",self.color_settings_panel,"background:transparent;color:"..t.accent..";font-weight:700;")
  self.color_settings_content=Geyser.ScrollBox:new({name="DGHUD.ColorSettings.Content",x=14,y=48,width=592,height=410},self.color_settings_panel)
  self.color_settings_close=label("DGHUD.ColorSettings.Close",self.color_settings_panel,"background:#17231c;border:1px solid "..t.border..";border-radius:5px;color:"..t.text..";font-weight:700;")
  self.color_option_buttons={}
  self.color_option_order={"mapper","enabled","room","exits","currency","races","classes","portal","attack","damage","danger","recovery","upkeep","spell","discovery","illumination"}
  local optionLabels={mapper="MAPPER",enabled="ALL HIGHLIGHTS",room="ROOM TITLES",exits="EXITS / DIRECTIONS",currency="CURRENCY",races="RACES",classes="CLASSES",portal="TRAVEL OBJECTS",attack="ATTACKS ON YOU",damage="DAMAGE TO YOU",danger="DANGER / BLOCKS",recovery="RECOVERY",upkeep="ONGOING COSTS",spell="SPELL THREATS",discovery="DISCOVERY / LOOT",illumination="ILLUMINATED AREAS"}
  for _,key in ipairs(self.color_option_order) do
    local option={key,optionLabels[key]}
    local key,text=option[1],option[2]; local button=label("DGHUD.ColorSettings."..key,self.color_settings_content)
    button:setClickCallback(function() return self:selectColorOption(key) end); button.option_text=text; self.color_option_buttons[key]=button
  end
  self.option_action_order={"command_help","color_settings","map_settings","roller_settings","support"}
  local actionLabels={command_help="HELP & COMMANDS…",color_settings="COLOR SETTINGS…",map_settings="MAP SETTINGS…",roller_settings="AUTOROLLER…",support="SUPPORT…"}
  self.option_action_buttons={}
  for _,key in ipairs(self.option_action_order) do local button=label("DGHUD.Header.Options."..key,self.options_scroll); button.option_text=actionLabels[key]; button:setClickCallback(function() return self:selectOptionsAction(key) end); self.option_action_buttons[key]=button end
  self.color_options={}; for _,key in ipairs(self.color_option_order) do self.color_options[key]=true end; self.color_menu_visible=false
  self.color_toggle:setClickCallback(function() return self:setColorMenuVisible(not self.color_menu_visible) end)
  self.color_menu_scrim:setClickCallback(function() return self:setColorMenuVisible(false) end)
  self.color_settings_close:setClickCallback(function() return self:hideColorSettings() end); self.color_settings_overlay:setClickCallback(function() return self:hideColorSettings() end); self.color_settings_visible=false
  for _,widget in ipairs({self.color_menu_scrim,self.color_menu,self.color_menu_bg,self.options_scroll}) do widget:hide() end
  for _,widget in ipairs({self.color_settings_overlay,self.color_settings_panel,self.color_settings_bg,self.color_settings_title,self.color_settings_content,self.color_settings_close}) do widget:hide() end; for _,button in pairs(self.color_option_buttons) do button:hide() end
  for _,button in pairs(self.option_action_buttons) do button:hide() end
  self.clock_header=label("DGHUD.Header.Clock",self.root,"background:transparent;color:"..t.text..";padding:8px 18px;")
  self.attribute_strip=label("DGHUD.AttributeStrip",self.root,"background:transparent;color:"..t.text..";padding:10px 12px;")
  self.chat_container=Geyser.Container:new({name="DGHUD.Chat",x=0,y=0,width=100,height=240},self.root)
  self.chat=self.chat_container
  self.chat_bg=label("DGHUD.Chat.Background",self.chat_container,"background:#0d1210;border:1px solid "..t.border..";")
  self.chat_tabs=Geyser.Container:new({name="DGHUD.Chat.Tabs",x=0,y=0,width="100%",height=32},self.chat_container)
  self.chat_output=Geyser.MiniConsole:new({name="DGHUD.Chat.Output",x=8,y=36,width="100%-16",height="100%-44"},self.chat_container)
  self.chat_output:enableScrollBar()
  self.chat_output:disableHorizontalScrollBar()
  self.left_bg=label("DGHUD.LeftBackground",self.root,"background:"..t.panel..";border-right:1px solid "..t.border..";")
  self.identity=label("DGHUD.Identity",self.root,"background:"..t.panel..";border-right:1px solid "..t.border..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:18px;")
  self.details=label("DGHUD.Details",self.root,"background:"..t.panel..";border:1px solid "..t.border..";color:"..t.text..";padding:18px;")
  self.left=label("DGHUD.LeftRail",self.root,"background:"..t.panel..";border-left:1px solid "..t.border..";color:"..t.text..";padding:18px;")
  self.equipment=label("DGHUD.Equipment",self.root,"background:#101713;border:1px solid "..t.border..";border-radius:7px;color:"..t.text..";padding:14px;")
  self.inventory=label("DGHUD.Inventory",self.root,"background:#101713;border:1px solid "..t.border..";border-radius:7px;color:"..t.text..";padding:14px;")
  self.inventory_title=label("DGHUD.Inventory.Title",self.root,"background:transparent;color:"..t.accent..";")
  self.inventory_output=Geyser.ScrollBox:new({name="DGHUD.Inventory.Output",x=0,y=0,width=100,height=100},self.root)
  self.inventory_content=label("DGHUD.Inventory.Content",self.inventory_output,"background:#101713;color:"..t.text..";")
  self.inventory_footer=label("DGHUD.Inventory.Footer",self.root,"background:transparent;color:"..t.text..";")
  self.runes=label("DGHUD.Runes",self.root,"background:#101713;border:1px solid "..t.border..";border-radius:7px;color:"..t.text..";")
  self.runes_title=label("DGHUD.Runes.Title",self.root,"background:transparent;color:"..t.accent..";")
  self.runes_output=Geyser.ScrollBox:new({name="DGHUD.Runes.Output",x=0,y=0,width=100,height=100},self.root)
  self.runes_content=label("DGHUD.Runes.Content",self.runes_output,"background:#101713;color:"..t.text..";")
  self.skills=label("DGHUD.Skills",self.root,"background:#101713;border:1px solid "..t.border..";border-radius:7px;color:"..t.text..";")
  self.skills_title=label("DGHUD.Skills.Title",self.root,"background:transparent;color:"..t.accent..";")
  self.skills_output=Geyser.ScrollBox:new({name="DGHUD.Skills.Output",x=0,y=0,width=100,height=100},self.root)
  self.skills_content=label("DGHUD.Skills.Content",self.skills_output,"background:#101713;color:"..t.text..";")
  self.list_measure=label("DGHUD.List.Measure",self.root,"background:transparent;color:transparent;")
  self.list_measure:move(-1000,-1000); self.list_measure:hide()
  self.right=Geyser.Container:new({name="DGHUD.RightRail",x=0,y=0,width=300,height=500},self.root)
  self.right_bg=label("DGHUD.RightBackground",self.right,"background:"..t.panel..";border-right:1px solid "..t.border..";")
  self.right_title=label("DGHUD.RightTitle",self.right,"background:transparent;color:"..t.accent..";font-size:13px;font-weight:700;padding:10px 14px;")
  self.vitals_right=Geyser.Container:new({name="DGHUD.CenterVitals",x=0,y=0,width=300,height=48},self.root)
  self.hp=gauge("DGHUD.Health",self.vitals_right,t.hp,t); self.fatigue=gauge("DGHUD.Fatigue",self.vitals_right,t.fatigue,t); self.carry=gauge("DGHUD.Carry",self.vitals_right,"#c9a359",t); self.psi=gauge("DGHUD.Psi",self.vitals_right,"#6a72c9",t); self.web=gauge("DGHUD.Web",self.vitals_right,"#9b78b5",t)
  self.room=label("DGHUD.Room",self.right,"background:#101a16;border:1px solid #385044;border-radius:6px;color:"..t.text..";padding:10px 12px;")
  self.mapper_frame=label("DGHUD.MapperFrame",self.right,"background:#101713;border:1px solid "..t.border..";border-radius:7px;")
  self.mapper=self.geyser.Mapper:new({name="DGHUD.Mapper",x=4,y=4,width="100%-8",height="100%-8"},self.mapper_frame)
  local mapButtonStyle="background:#17231c;border:1px solid #385044;border-radius:4px;color:"..t.jade..";font-weight:700;"
  self.map_zoom_out=label("DGHUD.Mapper.ZoomOut",self.mapper_frame,mapButtonStyle)
  self.map_center=label("DGHUD.Mapper.Center",self.mapper_frame,mapButtonStyle)
  self.map_zoom_in=label("DGHUD.Mapper.ZoomIn",self.mapper_frame,mapButtonStyle)
  self.map_clear_all=label("DGHUD.Mapper.ClearAll",self.mapper_frame,"background:#17231c;border:1px solid "..t.jade..";border-radius:4px;color:"..t.jade..";font-weight:700;")
  if self.map_clear_all.setToolTip then pcall(self.map_clear_all.setToolTip,self.map_clear_all,"Open Map Settings") end
  self.map_clear_all:setClickCallback(function() if self.map_clear_all_callback then return self.map_clear_all_callback() end end)
  for _,control in ipairs({
    {self.map_zoom_out,"−","Show more rooms","smaller"},
    {self.map_center,"◎","Center current room","center"},
    {self.map_zoom_in,"+","Make rooms larger","larger"},
  }) do
    local button,symbol,tooltip,action=control[1],control[2],control[3],control[4]
    button:echo("<center><b>"..symbol.."</b></center>")
    if button.setToolTip then pcall(button.setToolTip,button,tooltip) end
    button:setClickCallback(function() if self.map_zoom_callback then return self.map_zoom_callback(action) end end)
  end
  self.compass_area=Geyser.Container:new({name="DGHUD.Compass",x=0,y=0,width=100,height=100},self.right)
  self.compass_center=label("DGHUD.Compass.Center",self.compass_area,"background:transparent;color:"..t.muted..";"); self.compass_center:echo("<center>◆</center>")
  for i,direction in ipairs(Navigation.directions) do local b=label("DGHUD.Compass."..direction.key,self.compass_area); b:setClickCallback(function() if self.exit_available[direction.key] then send(direction.command) end end); self.direction_buttons[i]={label=b,direction=direction} end
  self.utility_area=Geyser.Container:new({name="DGHUD.Utilities",x=0,y=0,width=100,height=60},self.right)
  for i,utility in ipairs(Navigation.utilities) do local b=label("DGHUD.Utility."..i,self.utility_area); b:setClickCallback(function() send(utility.command) end); self.utility_buttons[i]={label=b,utility=utility} end
  self.roundtime_bar=gauge("DGHUD.Roundtime",self.right,"#a86532",t)
  self.roundtime_bar:setValue(0,1,"Roundtime  READY"); self.roundtime_bar:hide(); self.roundtime_remaining=0; self.roundtime_total=1
  self.bottom=label("DGHUD.Bottom",self.root,"background:#151713;border-top:1px solid "..t.border..";color:"..t.muted..";padding:9px 15px;")
  self.compact=label("DGHUD.Compact",self.root,"background:"..t.panel..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:8px 12px;")
  self.help_overlay=label("DGHUD.Help.Overlay",self.root,"background:rgba(0,0,0,0.72);")
  self.help_panel=Geyser.Container:new({name="DGHUD.Help.Panel",x=0,y=0,width=600,height=500},self.root)
  self.help_bg=label("DGHUD.Help.Background",self.help_panel,"background:"..t.panel..";border:2px solid "..t.accent..";border-radius:8px;")
  self.help_title=label("DGHUD.Help.Title",self.help_panel,"background:transparent;color:"..t.accent..";font-weight:700;")
  self.help_close=label("DGHUD.Help.Close",self.help_panel,"background:#17231c;border:1px solid "..t.border..";border-radius:4px;color:"..t.text..";font-weight:700;")
  self.help_copy=label("DGHUD.Help.Copy",self.help_panel,"background:#17231c;border:1px solid "..t.jade..";border-radius:4px;color:"..t.jade..";font-weight:700;")
  self.help_output=Geyser.ScrollBox:new({name="DGHUD.Help.Output",x=12,y=54,width=576,height=434},self.help_panel)
  self.help_content=label("DGHUD.Help.Content",self.help_output,"background:transparent;color:"..t.text..";")
  self.help_close:setClickCallback(function() self:hideHelp(); if self.help_close_callback then return self.help_close_callback() end end)
  self.help_copy:setClickCallback(function() if self.copy_text_callback then return self.copy_text_callback(View.helpText(self.help_entries or View.defaultHelpEntries())) end end)
  self.roller_overlay=label("DGHUD.RollerSettings.Overlay",self.root,"background:rgba(0,0,0,0.72);")
  self.roller_panel=Geyser.Container:new({name="DGHUD.RollerSettings.Panel",x=0,y=0,width=760,height=560},self.root)
  self.roller_bg=label("DGHUD.RollerSettings.Background",self.roller_panel,"background:"..t.panel..";border:2px solid "..t.border..";border-radius:8px;")
  self.roller_content=Geyser.ScrollBox:new({name="DGHUD.RollerSettings.Content",x=14,y=44,width=732,height=440},self.roller_panel)
  self.roller_title=label("DGHUD.RollerSettings.Title",self.roller_panel,"background:transparent;color:"..t.accent..";font-weight:700;")
  self.roller_status=label("DGHUD.RollerSettings.Status",self.roller_panel,"background:transparent;color:"..t.muted..";")
  self.roller_save=label("DGHUD.RollerSettings.Save",self.roller_panel,"background:#193024;border:1px solid "..t.jade..";border-radius:5px;color:"..t.jade..";font-weight:700;")
  self.roller_cancel=label("DGHUD.RollerSettings.Cancel",self.roller_panel,"background:#171b18;border:1px solid "..t.border..";border-radius:5px;color:"..t.text..";font-weight:700;")
  self.roller_fields={}; self.roller_field_order={"target_total","hard_stop","max_rolls","reroll_delay","reroll_command","log_folder","master_file","STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"}
  local fieldLabels={target_total="Target total (1-77/off)",hard_stop="Hard stop (1-77/off)",max_rolls="Maximum rolls (off=unlimited)",reroll_delay="Reroll delay (seconds)",reroll_command="Rejected-roll response (must be n)",log_folder="Log folder",master_file="Master log filename"}
  for _,key in ipairs(self.roller_field_order) do local caption=label("DGHUD.RollerSettings.Caption."..key,self.roller_content,"background:transparent;color:"..t.text..";"); local edit=input("DGHUD.RollerSettings.Input."..key,self.roller_content,self.geyser); self.roller_fields[key]={caption=caption,input=edit,label=fieldLabels[key] or (key.." minimum (1-7/off)")} end
  self.roller_toggle_order={"auto_start_on_name","use_min_stats","require_min_stats_to_stop","show_every_roll","logging_enabled"}; self.roller_toggles={}
  local toggleLabels={auto_start_on_name="Auto-start on Name/Race",use_min_stats="Enable stat minimums",require_min_stats_to_stop="Require minimums to stop",show_every_roll="Print every roll",logging_enabled="Enable roll logging"}
  for _,key in ipairs(self.roller_toggle_order) do local button=label("DGHUD.RollerSettings.Toggle."..key,self.roller_content); button.option_text=toggleLabels[key]; button:setClickCallback(function() self.roller_draft[key]=not self.roller_draft[key]; self:renderRollerSettings(false); return self.roller_draft[key] end); self.roller_toggles[key]=button end
  self.roller_action_order={"roller_start","roller_stop","roller_stats","roller_last","roller_reset","roller_help"}; self.roller_action_buttons={}; local rollerActionLabels={roller_start="START ROLLER",roller_stop="STOP ROLLER",roller_stats="SESSION STATS",roller_last="SHOW LAST ROLL",roller_reset="RESET SESSION",roller_help="ROLLER HELP"}
  for _,key in ipairs(self.roller_action_order) do local button=label("DGHUD.RollerSettings.Action."..key,self.roller_content); button.option_text=rollerActionLabels[key]; button:setClickCallback(function() if self.options_action_callback then return self.options_action_callback(key) end; return nil,"autoroller action is unavailable" end); self.roller_action_buttons[key]=button end
  self.roller_save:setClickCallback(function() return self:saveRollerSettings() end); self.roller_cancel:setClickCallback(function() return self:hideRollerSettings() end); self.roller_overlay:setClickCallback(function() return self:hideRollerSettings() end)
  self.roller_settings_visible=false
  self.map_settings_overlay=label("DGHUD.MapSettings.Overlay",self.root,"background:rgba(0,0,0,0.72);")
  self.map_settings_panel=Geyser.Container:new({name="DGHUD.MapSettings.Panel",x=0,y=0,width=760,height=600},self.root)
  self.map_settings_bg=label("DGHUD.MapSettings.Background",self.map_settings_panel,"background:"..t.panel..";border:2px solid "..t.border..";border-radius:8px;")
  self.map_settings_content=Geyser.ScrollBox:new({name="DGHUD.MapSettings.Content",x=14,y=44,width=732,height=470},self.map_settings_panel)
  self.map_settings_title=label("DGHUD.MapSettings.Title",self.map_settings_panel,"background:transparent;color:"..t.accent..";font-weight:700;")
  self.map_settings_status=label("DGHUD.MapSettings.Status",self.map_settings_panel,"background:transparent;color:"..t.muted..";")
  self.map_settings_save=label("DGHUD.MapSettings.Save",self.map_settings_panel,"background:#193024;border:1px solid "..t.jade..";border-radius:5px;color:"..t.jade..";font-weight:700;")
  self.map_settings_cancel=label("DGHUD.MapSettings.Cancel",self.map_settings_panel,"background:#171b18;border:1px solid "..t.border..";border-radius:5px;color:"..t.text..";font-weight:700;")
  self.map_settings_fields={}; self.map_settings_field_order={"minimum_height","height_percent","maximum_height","zoom_step","zoom_min","zoom_max","walk_timeout","special_timeout"}
  local mapFieldLabels={minimum_height="Minimum map height (90-300 px)",height_percent="Map height share (20-70%)",maximum_height="Maximum map height (140-700 px)",zoom_step="Zoom change per click (0.5-10)",zoom_min="Minimum zoom (3-30)",zoom_max="Maximum zoom (10-100)",walk_timeout="Autowalk timeout (3-60 sec)",special_timeout="Gate/portal detection timeout (3-60 sec)"}
  for _,key in ipairs(self.map_settings_field_order) do local caption=label("DGHUD.MapSettings.Caption."..key,self.map_settings_content,"background:transparent;color:"..t.text..";"); local edit=input("DGHUD.MapSettings.Input."..key,self.map_settings_content,self.geyser); self.map_settings_fields[key]={caption=caption,input=edit,label=mapFieldLabels[key]} end
  self.map_settings_toggle_order={"enabled","gate","portal","door","arch","path","other"}; self.map_settings_toggles={}
  local mapToggleLabels={enabled="AUTOMAPPING",gate="GATES CREATE SUBMAP",portal="PORTALS CREATE SUBMAP",door="DOORS CREATE SUBMAP",arch="ARCHES CREATE SUBMAP",path="PATHS CREATE SUBMAP",other="OTHER SPECIAL TRAVEL CREATES SUBMAP"}
  for _,key in ipairs(self.map_settings_toggle_order) do local button=label("DGHUD.MapSettings.Toggle."..key,self.map_settings_content); button.option_text=mapToggleLabels[key]; button:setClickCallback(function() self.map_settings_draft[key]=not self.map_settings_draft[key]; self:renderMapSettings(false) end); self.map_settings_toggles[key]=button end
  self.map_settings_clear_current=label("DGHUD.MapSettings.ClearCurrent",self.map_settings_content,"background:#302018;border:1px solid #9b6a42;border-radius:5px;color:#e5b17a;font-weight:700;")
  self.map_settings_clear_all=label("DGHUD.MapSettings.ClearAll",self.map_settings_content,"background:#3a1715;border:1px solid #a94d46;border-radius:5px;color:#ffb0a8;font-weight:700;")
  self.map_settings_library=label("DGHUD.MapSettings.Library",self.map_settings_content,"background:#193024;border:1px solid "..t.jade..";border-radius:5px;color:"..t.jade..";font-weight:700;")
  self.map_settings_area_name=input("DGHUD.MapSettings.AreaName",self.map_settings_content,self.geyser)
  self.map_settings_subarea_name=input("DGHUD.MapSettings.SubareaName",self.map_settings_content,self.geyser)
  self.map_settings_rename_area=label("DGHUD.MapSettings.RenameArea",self.map_settings_content,"background:#17231c;border:1px solid "..t.jade..";border-radius:5px;color:"..t.jade..";font-weight:700;")
  self.map_settings_rename_subarea=label("DGHUD.MapSettings.RenameSubarea",self.map_settings_content,"background:#17231c;border:1px solid "..t.jade..";border-radius:5px;color:"..t.jade..";font-weight:700;")
  self.map_settings_save:setClickCallback(function() return self:saveMapSettings() end); self.map_settings_cancel:setClickCallback(function() return self:hideMapSettings() end); self.map_settings_overlay:setClickCallback(function() return self:hideMapSettings() end)
  self.map_settings_clear_current:setClickCallback(function() if self.map_settings_action_callback then return self.map_settings_action_callback("clear_current") end end)
  self.map_settings_clear_all:setClickCallback(function() if self.map_settings_action_callback then return self.map_settings_action_callback("clear_all") end end)
  self.map_settings_library:setClickCallback(function() if self.map_settings_action_callback then return self.map_settings_action_callback("map_library") end end)
  local function renameMapPart(action,input,key)
    if not self.map_settings_action_callback then return nil,"map naming is unavailable" end
    local ok,native=self.map_settings_action_callback(action,input:getText())
    if not ok then self.map_settings_error=native; self:renderMapSettings(false); return nil,native end
    self.map_settings_error=nil; self.map_settings_draft[key]=ok; self.map_settings_status_text="Saved map name: "..tostring(native or ok); self:renderMapSettings(false); return ok
  end
  self.map_settings_rename_area:setClickCallback(function() return renameMapPart("rename_area",self.map_settings_area_name,"current_area_name") end)
  self.map_settings_rename_subarea:setClickCallback(function() return renameMapPart("rename_subarea",self.map_settings_subarea_name,"current_subarea_name") end)
  self.map_settings_visible=false
  self.feedback_overlay=label("DGHUD.Feedback.Overlay",self.root,"background:rgba(0,0,0,0.72);")
  self.feedback_panel=Geyser.Container:new({name="DGHUD.Feedback.Panel",x=0,y=0,width=680,height=430},self.root)
  self.feedback_bg=label("DGHUD.Feedback.Background",self.feedback_panel,"background:"..t.panel..";border:2px solid "..t.accent..";border-radius:8px;")
  self.feedback_title=label("DGHUD.Feedback.Title",self.feedback_panel,"background:transparent;color:"..t.accent..";font-weight:700;")
  self.feedback_explanation=label("DGHUD.Feedback.Explanation",self.feedback_panel,"background:transparent;color:"..t.text..";")
  self.feedback_kind=label("DGHUD.Feedback.Kind",self.feedback_panel,"background:#193024;border:1px solid "..t.jade..";border-radius:4px;color:"..t.jade..";font-weight:700;")
  self.feedback_summary_label=label("DGHUD.Feedback.SummaryLabel",self.feedback_panel,"background:transparent;color:"..t.muted..";")
  self.feedback_summary=input("DGHUD.Feedback.Summary",self.feedback_panel,self.geyser)
  self.feedback_details_label=label("DGHUD.Feedback.DetailsLabel",self.feedback_panel,"background:transparent;color:"..t.muted..";")
  self.feedback_details=input("DGHUD.Feedback.Details",self.feedback_panel,self.geyser)
  self.feedback_status=label("DGHUD.Feedback.Status",self.feedback_panel,"background:transparent;color:"..t.muted..";")
  self.feedback_send=label("DGHUD.Feedback.Send",self.feedback_panel,"background:#193024;border:1px solid "..t.jade..";border-radius:5px;color:"..t.jade..";font-weight:700;")
  self.feedback_cancel=label("DGHUD.Feedback.Cancel",self.feedback_panel,"background:#171b18;border:1px solid "..t.border..";border-radius:5px;color:"..t.text..";font-weight:700;")
  self.feedback_kind:setClickCallback(function() self.feedback_draft.kind=self.feedback_draft.kind=="request" and "feedback" or "request"; return self:renderFeedback(false) end)
  self.feedback_send:setClickCallback(function() return self:sendFeedback() end); self.feedback_cancel:setClickCallback(function() return self:hideFeedback() end); self.feedback_overlay:setClickCallback(function() return self:hideFeedback() end)
  self.feedback_visible=false; self.feedback_sending=false
  for _,widget in ipairs({self.feedback_overlay,self.feedback_panel,self.feedback_bg,self.feedback_title,self.feedback_explanation,self.feedback_kind,self.feedback_summary_label,self.feedback_summary,self.feedback_details_label,self.feedback_details,self.feedback_status,self.feedback_send,self.feedback_cancel}) do widget:hide() end
  self.support_overlay=label("DGHUD.Support.Overlay",self.root,"background:rgba(0,0,0,0.72);"); self.support_panel=Geyser.Container:new({name="DGHUD.Support.Panel",x=0,y=0,width=520,height=330},self.root); self.support_bg=label("DGHUD.Support.Background",self.support_panel,"background:"..t.panel..";border:2px solid "..t.accent..";border-radius:8px;"); self.support_title=label("DGHUD.Support.Title",self.support_panel,"background:transparent;color:"..t.accent..";font-weight:700;"); self.support_text=label("DGHUD.Support.Text",self.support_panel,"background:transparent;color:"..t.text..";"); self.support_feedback=label("DGHUD.Support.Feedback",self.support_panel,"background:#193024;border:1px solid "..t.jade..";border-radius:5px;color:"..t.jade..";font-weight:700;"); self.support_debug=label("DGHUD.Support.Debug",self.support_panel,"background:#17231c;border:1px solid "..t.border..";border-radius:5px;color:"..t.accent..";font-weight:700;"); self.support_close=label("DGHUD.Support.Close",self.support_panel,"background:#171b18;border:1px solid "..t.border..";border-radius:5px;color:"..t.text..";font-weight:700;"); self.support_status=label("DGHUD.Support.Status",self.support_panel,"background:transparent;color:"..t.muted..";")
  self.support_feedback:setClickCallback(function() self:hideSupport(); return self:showFeedback() end); self.support_debug:setClickCallback(function() if not self.options_action_callback then return nil,"debug submission is unavailable" end; self.support_status_text="Sending privacy-safe debug report…"; self:renderSupport(); local ok,err=self.options_action_callback("send_debug"); if not ok then self.support_status_text="Could not send: "..tostring(err); self:renderSupport() end; return ok,err end); self.support_close:setClickCallback(function() return self:hideSupport() end); self.support_overlay:setClickCallback(function() return self:hideSupport() end); self.support_visible=false
  for _,widget in ipairs({self.support_overlay,self.support_panel,self.support_bg,self.support_title,self.support_text,self.support_feedback,self.support_debug,self.support_close,self.support_status}) do widget:hide() end
  local rollerWidgets={self.roller_overlay,self.roller_panel,self.roller_bg,self.roller_content,self.roller_title,self.roller_status,self.roller_save,self.roller_cancel}; for _,entry in pairs(self.roller_fields) do rollerWidgets[#rollerWidgets+1]=entry.caption; rollerWidgets[#rollerWidgets+1]=entry.input end; for _,button in pairs(self.roller_toggles) do rollerWidgets[#rollerWidgets+1]=button end; for _,button in pairs(self.roller_action_buttons) do rollerWidgets[#rollerWidgets+1]=button end; for _,widget in ipairs(rollerWidgets) do widget:hide() end
  if self.help_close.setToolTip then pcall(self.help_close.setToolTip,self.help_close,"Close DGHUD command guide") end
  self.help_visible=false
  for _,widget in ipairs({self.help_overlay,self.help_panel,self.help_bg,self.help_title,self.help_copy,self.help_close,self.help_output,self.help_content}) do widget:hide() end
  self.map_library_overlay=label("DGHUD.MapLibrary.Overlay",self.root,"background:rgba(0,0,0,0.72);")
  self.map_library_panel=Geyser.Container:new({name="DGHUD.MapLibrary.Panel",x=0,y=0,width=720,height=520},self.root)
  self.map_library_bg=label("DGHUD.MapLibrary.Background",self.map_library_panel,"background:"..t.panel..";border:2px solid "..t.accent..";border-radius:8px;")
  self.map_library_title=label("DGHUD.MapLibrary.Title",self.map_library_panel,"background:transparent;color:"..t.accent..";font-weight:700;")
  self.map_library_copy=label("DGHUD.MapLibrary.Copy",self.map_library_panel,"background:transparent;color:"..t.text..";")
  self.map_library_search_label=label("DGHUD.MapLibrary.SearchLabel",self.map_library_panel,"background:transparent;color:"..t.muted..";")
  self.map_library_search=input("DGHUD.MapLibrary.Search",self.map_library_panel,self.geyser)
  self.map_library_modes={}; self.map_library_mode_order={"collections","library"}; self.map_library_mode="collections"
  local modeLabels={collections="MY MAPS",library="SHARED LIBRARY"}
  for _,key in ipairs(self.map_library_mode_order) do local button=label("DGHUD.MapLibrary.Mode."..key,self.map_library_panel); button.option_text=modeLabels[key]; button:setClickCallback(function() return self:setMapLibraryMode(key) end); self.map_library_modes[key]=button end
  self.map_library_filters={}; self.map_library_filter_order={"all","full_map","area","subarea"}; self.map_library_filter="all"; self.map_library_query=""
  local filterLabels={all="ALL",full_map="FULL MAPS",area="AREAS",subarea="SUBAREAS"}
  for _,key in ipairs(self.map_library_filter_order) do local button=label("DGHUD.MapLibrary.Filter."..key,self.map_library_panel); button.option_text=filterLabels[key]; button:setClickCallback(function() return self:setMapLibraryFilter(key) end); self.map_library_filters[key]=button end
  if self.map_library_search.setAction then self.map_library_search:setAction(function(value) if self.map_library_mode=="collections" then self.map_collection_name=tostring(value or ""); return true end; return self:setMapLibrarySearch(value) end) end
  self.map_library_list=Geyser.ScrollBox:new({name="DGHUD.MapLibrary.List",x=18,y=154,width=684,height=214},self.map_library_panel)
  self.map_library_rows={}; self.map_library_catalog={}; self.map_library_visible_catalog={}; self.map_library_selected=nil; self.map_library_import_pending=false; self.map_library_status="Choose FIND MAPS to see shared maps, or SHARE MY MAP to send yours for review."
  self.map_collection_list=Geyser.ScrollBox:new({name="DGHUD.MapLibrary.Collections",x=18,y=154,width=684,height=214},self.map_library_panel)
  self.map_collection_rows={}; self.map_collections={}; self.map_collection_selected=nil; self.map_collection_replace_pending=false
  self.map_library_copy_button=label("DGHUD.MapLibrary.CopyButton",self.map_library_panel,"background:#17231c;border:1px solid "..t.jade..";border-radius:4px;color:"..t.jade..";font-weight:700;")
  self.map_library_close=label("DGHUD.MapLibrary.Close",self.map_library_panel,"background:#17231c;border:1px solid "..t.border..";border-radius:4px;color:"..t.text..";font-weight:700;")
  self.map_library_actions={}; self.map_library_action_order={"browse","install","publish_all","publish_area","publish_subarea","export_all","export_area","export_subarea","keep","replace","skip","confirm","cancel","report"}
  local libraryLabels={browse="FIND SHARED MAPS",install="USE SELECTED MAP",publish_all="SHARE ALL",publish_area="SHARE CURRENT AREA",publish_subarea="SHARE CURRENT SUBAREA",export_all="BACK UP ALL",export_area="BACK UP CURRENT AREA",export_subarea="BACK UP CURRENT SUBAREA",keep="KEEP MY MAP",replace="USE SHARED MAP",skip="SKIP THIS AREA",confirm="FINISH INSTALLING",cancel="GO BACK",report="REPORT A PROBLEM"}
  for _,key in ipairs(self.map_library_action_order) do local button=label("DGHUD.MapLibrary.Action."..key,self.map_library_panel,"background:#17231c;border:1px solid "..t.border..";border-radius:5px;color:"..t.jade..";font-weight:700;"); button.option_text=libraryLabels[key]; button:setClickCallback(function() if self.map_library_action_callback then return self.map_library_action_callback(key) end; return nil,"map library action is not connected" end); self.map_library_actions[key]=button end
  self.map_collection_actions={}; self.map_collection_action_order={"use_collection","rename_collection","duplicate_edit","backup_collection","delete_collection","replace_collection"}
  local collectionLabels={use_collection="USE",rename_collection="RENAME",duplicate_edit="DUPLICATE & EDIT",backup_collection="BACKUP",delete_collection="DELETE",replace_collection="REPLACE"}
  for _,key in ipairs(self.map_collection_action_order) do local button=label("DGHUD.MapLibrary.CollectionAction."..key,self.map_library_panel,"background:#17231c;border:1px solid "..t.border..";border-radius:5px;color:"..t.jade..";font-weight:700;"); button.option_text=collectionLabels[key]; button:setClickCallback(function() return self:selectMapCollectionAction(key) end); self.map_collection_actions[key]=button end
  self.map_library_download_actions={}; self.map_library_download_action_order={"download_new","replace_current","update_collection","upload_my_version"}; local downloadLabels={download_new="DOWNLOAD AS NEW",replace_current="REPLACE CURRENT",update_collection="UPDATE MY COPY",upload_my_version="UPLOAD MY VERSION"}
  for _,key in ipairs(self.map_library_download_action_order) do local button=label("DGHUD.MapLibrary.DownloadAction."..key,self.map_library_panel,"background:#17231c;border:1px solid "..t.border..";border-radius:5px;color:"..t.jade..";font-weight:700;"); button.option_text=downloadLabels[key]; button:setClickCallback(function() return self:selectMapLibraryDownloadAction(key) end); self.map_library_download_actions[key]=button end
  self.map_library_close:setClickCallback(function() return self:hideMapLibrary() end); self.map_library_overlay:setClickCallback(function() return self:hideMapLibrary() end)
  self.map_library_copy_button:setClickCallback(function() if self.copy_text_callback then return self.copy_text_callback("Map Library\n\nFIND SHARED MAPS: Load maps shared by other players.\nUSE SELECTED MAP: Download the map you clicked and review any room conflicts.\nSHARE MY MAP: Send your current map to the owner for safety review. No GitHub account is needed.\nSAVE A BACKUP: Keep a private JSON copy on your computer.\nREPORT A PROBLEM: Send the most recent map error for help.\n\nShared maps never silently overwrite personal rooms. You choose whether to keep yours, use the shared rooms, or skip an area before installation.") end end)
  self.map_library_visible=false
  for _,widget in ipairs({self.map_library_overlay,self.map_library_panel,self.map_library_bg,self.map_library_title,self.map_library_copy,self.map_library_search_label,self.map_library_search,self.map_library_list,self.map_collection_list,self.map_library_copy_button,self.map_library_close}) do widget:hide() end; for _,button in pairs(self.map_library_filters) do button:hide() end; for _,button in pairs(self.map_library_modes) do button:hide() end; for _,button in pairs(self.map_library_actions) do button:hide() end; for _,button in pairs(self.map_collection_actions) do button:hide() end; for _,button in pairs(self.map_library_download_actions) do button:hide() end
  return self
end
local default_chat_filters={"ALL","ROOM","PRIVATE","ESP","DRAGON","CONTACT","STAFF"}
local reserved_chat_filters={ALL=true,ROOM=true,PRIVATE=true,ESP=true,DRAGON=true,CONTACT=true,STAFF=true,OWN=true,WHISPER=true}
local function chatFilterOrder(categories)
  local result={}; local seen={}
  for _,category in ipairs(default_chat_filters) do result[#result+1]=category; seen[category]=true end
  for _,value in ipairs(categories or {}) do
    local category=tostring(value or ""):upper()
    if category~="" and not reserved_chat_filters[category] and not seen[category] then result[#result+1]=category; seen[category]=true end
  end
  return result
end
local function chatTabWidth(category,font)
  return math.max(42,math.min(96,math.floor(#tostring(category)*(tonumber(font) or 13)*.55+18)))
end
function View:setChatFilterCallback(callback)
  self.chat_filter_callback=type(callback)=="function" and callback or nil
  return true
end
function View:renderChatTabs(categories,activeFilter)
  for _,button in ipairs(self.chat_buttons or {}) do if button.delete then button:delete() end end
  self.chat_buttons={}; self.chat_overflow_button=nil; self.chat_filter_order=chatFilterOrder(categories)
  local width=math.max(80,tonumber(self.layout and self.layout.chat_width) or 640)
  local font=tonumber(self.layout and self.layout.chat_font) or 13
  local gap,padding,overflowWidth=4,8,64
  local total=padding
  for _,category in ipairs(self.chat_filter_order) do total=total+chatTabWidth(category,font)+gap end
  local visible={}; local hidden={}
  if total+padding-gap<=width then
    for _,category in ipairs(self.chat_filter_order) do visible[#visible+1]=category end
  else
    local room=math.max(42,width-padding*2-overflowWidth-gap)
    local used=0
    for _,category in ipairs(self.chat_filter_order) do
      local needed=chatTabWidth(category,font)+(used>0 and gap or 0)
      if used+needed<=room or #visible==0 then visible[#visible+1]=category; used=used+needed else hidden[#hidden+1]=category end
    end
    local active=tostring(activeFilter or "ALL"):upper(); local activeHidden=false
    for _,category in ipairs(hidden) do if category==active then activeHidden=true; break end end
    if activeHidden and #visible>0 then visible[#visible]=active; hidden={}; local selected={}
      for _,category in ipairs(visible) do selected[category]=true end
      for _,category in ipairs(self.chat_filter_order) do if not selected[category] then hidden[#hidden+1]=category end end
    end
  end
  self.chat_overflow_categories=hidden
  local t=self.settings.theme; local x=padding; local active=tostring(activeFilter or "ALL"):upper()
  local maxNormal=width-padding-(#hidden>0 and overflowWidth+gap or 0)
  for _,category in ipairs(visible) do
    local remaining=maxNormal-x; if remaining<=0 then break end
    local button=label("DGHUD.Chat.Tab."..(#self.chat_buttons+1),self.chat_tabs,nil,self.geyser)
    local buttonWidth=math.min(chatTabWidth(category,font),remaining)
    place(button,x,4,buttonWidth,24); x=x+buttonWidth+gap
    local selected=category
    button.category=selected
    button:setStyleSheet("background:"..(selected==active and "#26382d" or "#121a16")..";border:1px solid "..(selected==active and t.jade or t.border)..";border-radius:4px;color:"..(selected==active and t.jade or t.muted)..";font-size:"..font.."px;")
    button:echo("<center><b>"..safeText(selected).."</b></center>")
    button:setClickCallback(function() if self.chat_filter_callback then self.chat_filter_callback(selected) end end)
    self.chat_buttons[#self.chat_buttons+1]=button
  end
  if #hidden>0 then
    local button=label("DGHUD.Chat.Tab.More",self.chat_tabs,nil,self.geyser); place(button,math.max(padding,width-padding-overflowWidth),4,overflowWidth,24)
    button:setStyleSheet("background:#121a16;border:1px solid "..t.border..";border-radius:4px;color:"..t.muted..";font-size:"..font.."px;")
    button:echo("<center><b>MORE "..#hidden.."</b></center>")
    button:setClickCallback(function()
      self.chat_overflow_cursor=((self.chat_overflow_cursor or 0)%#self.chat_overflow_categories)+1
      if self.chat_filter_callback then self.chat_filter_callback(self.chat_overflow_categories[self.chat_overflow_cursor]) end
    end)
    self.chat_overflow_button=button; self.chat_buttons[#self.chat_buttons+1]=button
  end
end
function View:applyLayout(layout)
  self.layout=layout; local top,bottom=layout.header_height or layout.top,0; local t=self.settings.theme; local p=layout.panel_padding; local lp=layout.lower_panel_padding
  local side_bottom=layout.command_line_clearance or 0
  local header_top_padding=math.max(10,(layout.color_toggle_height or 20)+8)
  self.header:setStyleSheet("background:"..t.background..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:"..header_top_padding.."px "..p.."px 6px "..p.."px;font-size:"..layout.body_font.."px;")
  self.clock_header:setStyleSheet("background:transparent;color:"..t.text..";padding:8px "..p.."px;text-align:right;")
  self.attribute_strip:setStyleSheet("background:transparent;color:"..t.text..";padding:10px 12px;font-size:"..layout.attribute_strip_font.."px;")
  self.identity:setStyleSheet("background:"..t.panel..";border-right:1px solid "..t.border..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:"..p.."px;font-size:"..layout.body_font.."px;")
  self.details:setStyleSheet("background:"..t.panel..";border:1px solid "..t.border..";border-radius:7px;color:"..t.text..";padding:"..(layout.combat_padding or layout.equipment_padding or p).."px;font-size:"..(layout.combat_font or layout.equipment_font or layout.body_font).."px;")
  self.left:setStyleSheet("background:"..t.panel..";border-left:1px solid "..t.border..";color:"..t.text..";padding:"..p.."px;font-size:"..layout.body_font.."px;")
  self.equipment:setStyleSheet("background:#101713;border:1px solid "..t.border..";border-radius:7px;color:"..t.text..";padding:"..(layout.equipment_padding or p).."px;font-size:"..(layout.equipment_font or layout.body_font).."px;")
  for _,card in ipairs({self.inventory,self.runes,self.skills}) do card:setStyleSheet("background:#101713;border:1px solid "..t.border..";border-radius:7px;color:"..t.text..";padding:"..(layout.list_padding or p).."px;font-size:"..layout.body_font.."px;") end
  for _,title in ipairs({self.inventory_title,self.runes_title,self.skills_title}) do title:setStyleSheet("background:transparent;color:"..t.accent..";font-size:"..layout.list_title_font.."px;font-weight:700;") end
  self.inventory_footer:setStyleSheet("background:transparent;color:"..t.text..";font-size:"..(layout.list_font+2).."px;")
  for _,widget in ipairs({self.inventory_content,self.runes_content,self.skills_content,self.list_measure}) do
    if widget.setFont then widget:setFont(self.list_font_family) end
    if widget.setFontSize then widget:setFontSize(layout.list_font) end
  end
  for _,title in ipairs({self.inventory_title,self.runes_title,self.skills_title}) do
    if title.setFont then title:setFont(self.list_font_family) end
    if title.setFontSize then title:setFontSize(layout.list_title_font) end
  end
  if self.inventory_footer.setFontSize then self.inventory_footer:setFontSize(layout.list_font+2) end
  self.list_measure:setStyleSheet("background:transparent;color:transparent;font-family:'"..self.list_font_family.."';font-size:"..layout.list_font.."px;")
  local glyphRun=string.rep("M",10)
  self.list_measure:echo(table.concat({glyphRun,glyphRun,glyphRun,glyphRun,glyphRun},"<br>"))
  local measured,measuredWidth
  if self.list_measure.getSizeHint then
    local ok,width,height=pcall(self.list_measure.getSizeHint,self.list_measure)
    if ok then measuredWidth=tonumber(width); measured=tonumber(height) end
  end
  local fallbackCharacterWidth=math.max(1,layout.list_font)
  self.list_character_width=measuredWidth and measuredWidth>0 and measuredWidth/#glyphRun or fallbackCharacterWidth
  local fallback=math.ceil(layout.list_font*1.3)*5
  layout.list_viewport_height=measured and measured>0 and math.ceil(measured) or fallback
  layout.list_row_height=layout.list_viewport_height/5
  self.list_row_height=layout.list_row_height
  for _,content in ipairs({self.inventory_content,self.runes_content,self.skills_content}) do content:setStyleSheet("background:#101713;color:"..t.text..";font-family:'"..self.list_font_family.."';font-size:"..layout.list_font.."px;") end
  self.right_title:setStyleSheet("background:transparent;color:"..t.accent..";font-size:"..layout.lower_body_font.."px;font-weight:700;padding:"..lp.."px;")
  self.room:setStyleSheet("background:#101a16;border:1px solid #385044;border-radius:7px;color:"..t.text..";padding:"..lp.."px;font-size:"..layout.lower_body_font.."px;")
  self.bottom:setStyleSheet("background:#151713;border-top:1px solid "..t.border..";color:"..t.muted..";padding:9px "..p.."px;font-size:"..layout.small_font.."px;")
  self.compact:setStyleSheet("background:"..t.panel..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:10px "..p.."px;font-size:"..layout.body_font.."px;")
  for _,g in ipairs({self.hp,self.fatigue,self.psi,self.web}) do g.text:setStyleSheet("background:transparent;color:"..t.text..";font-size:"..layout.lower_small_font.."px;font-weight:700;"); if g.text.setFontSize then g.text:setFontSize(layout.lower_small_font) end end
  self.carry:hide()
  place(self.header,0,0,"100%",top)
  local windowWidth=tonumber(layout.window_width) or 1200; local clock_x=layout.mode=="compact" and math.floor(windowWidth*.5) or windowWidth-layout.right
  local toggle_width=math.max(72,math.min(92,math.floor(windowWidth*.10))); local toggle_x=0; local toggle_y=4
  local attributeWidth=math.max(1,clock_x-(layout.console_left or layout.left)-6)
  place(self.attribute_strip,layout.console_left or layout.left,0,attributeWidth,top); self.attribute_strip:raise()
  place(self.color_toggle,toggle_x,toggle_y,toggle_width,layout.color_toggle_height); self.options_anchor={x=toggle_x,y=toggle_y,width=toggle_width,height=layout.color_toggle_height}; self:setColorEnabled(self.color_enabled~=false); self.color_toggle:raise()
  if layout.mode=="compact" then place(self.clock_header,"50%",0,"50%",top) else place(self.clock_header,"100%-"..layout.right,0,layout.right,top) end
  self.clock_header:raise(); self.bottom:hide()
  place(self.chat_container,layout.chat_x or layout.left,top,layout.chat_width or layout.console_width,layout.chat_height or 240)
  place(self.chat_bg,0,0,"100%","100%")
  place(self.chat_tabs,0,0,"100%",32)
  place(self.chat_output,layout.chat_padding or 8,36,"100%-"..((layout.chat_padding or 8)*2),"100%-44")
  if layout.mode=="wide" or layout.mode=="medium" then
    self.compact:hide()
    place(self.left_bg,0,top,layout.left,"100%-"..top)
    place(self.identity,0,top,layout.left,layout.identity_height)
    place(self.left,"100%-"..layout.right,top,layout.right,"100%-"..(top+side_bottom))
    local available=math.max(100,(layout.window_height or 800)-top-side_bottom)
    local psi_visible=self.last_state and self.last_state.vitals.psi.visible or false
    local web_visible=self.last_state and self.last_state.vitals.web.visible or false
    local lower=Layout.lowerPanelGeometry(layout,psi_visible,web_visible,true)
    local panel_height=math.min(available,lower.panel_height)
    layout.lower_geometry=lower
    place(self.right,0,"100%-"..(side_bottom+panel_height),layout.left,panel_height)
    local lower_y=(layout.window_height or 800)-side_bottom-panel_height
    local card_x="100%-"..(layout.right-p); local card_w=layout.right-p*2; local eq_rows=2
    local rp=layout.list_padding or p; local list_x="100%-"..(layout.right-p-rp); local list_w=card_w-rp*2
    self.list_outer_width=list_w
    self.list_viewport_width,self.list_resolved_scrollbar_width=listViewportWidth(self.skills_output,self.list_outer_width,self.list_scrollbar_width)
    self.skills_content_width=math.max(self.list_viewport_width,29*self.list_character_width)
    self.runes_content_width=math.max(self.list_viewport_width,28*self.list_character_width)
    self.inventory_content_width=math.max(self.list_viewport_width,36*self.list_character_width)
    self.list_content_width=self.skills_content_width
    self.list_horizontal_overflow=self.skills_content_width>self.list_outer_width or self.runes_content_width>self.list_outer_width or self.inventory_content_width>self.list_outer_width
    self.skill_character_capacity=math.max(1,math.floor(self.skills_content_width/self.list_character_width))
    self.skill_level_width=self.skill_character_capacity>=8 and 3 or 2
    self.skill_use_width=self.skill_character_capacity>=8 and 4 or 3
    local fixedColumns=self.skill_level_width+self.skill_use_width
    self.skill_column_gaps=math.min(2,math.max(0,self.skill_character_capacity-fixedColumns-1))
    self.skill_name_width=math.min(20,math.max(1,self.skill_character_capacity-fixedColumns-self.skill_column_gaps))
    local inventory_rows=self.last_state and self.last_state.inventory and #(self.last_state.inventory.items or {}) or 0
    local rune_rows=self.last_state and self.last_state.runes and #(self.last_state.runes.items or {}) or 0
    local skill_rows=self.last_state and self.last_state.skills and #(self.last_state.skills.items or {}) or 0
    self.inventory_content:resize(self.inventory_content_width,math.max(layout.list_row_height*5,inventory_rows*layout.list_row_height))
    self.runes_content:resize(self.runes_content_width,math.max(layout.list_row_height*5,rune_rows*layout.list_row_height))
    self.skills_content:resize(self.skills_content_width,math.max(layout.list_row_height*5,skill_rows*layout.list_row_height))
    local equipment_padding=layout.equipment_padding or p
    local equipment_h=(layout.equipment_font or layout.body_font)+eq_rows*(layout.equipment_line_height or layout.details_line_height)+equipment_padding*2+10
    local identity_bottom=top+layout.identity_height
    if lower_y-identity_bottom>=equipment_h+20 then place(self.equipment,p,identity_bottom+10,layout.left-p*2,equipment_h) else self.equipment:hide() end
    local details_placement=Layout.detailsPlacement()
    layout.details_columns=2
    self.details:hide()
    local combat_padding=layout.combat_padding or equipment_padding
    local right_details_h=(layout.combat_line_height or layout.details_line_height)*Layout.detailsCardRows(layout.details_columns)+combat_padding*2+4
    local combat_y=top+p
    place(self.details,card_x,combat_y,card_w,right_details_h)
    local inventory_y=combat_y+right_details_h+10; local rail_bottom=(layout.window_height or 800)-side_bottom-12
    local rows=layout.list_visible_rows or 5; local list_h=layout.list_viewport_height or layout.list_row_height*rows
    if self.list_horizontal_overflow then list_h=list_h+(layout.list_horizontal_scrollbar_height or 18) end
    local title_h=layout.list_row_height+4; local footer_h=layout.list_row_height*2+6
    local inventory_h=rp*2+title_h+list_h+footer_h+8; local runes_h=rp*2+title_h+list_h+4; local skills_h=rp*2+title_h+list_h+4
    local required=inventory_h+12+runes_h+12+skills_h
    if rail_bottom-inventory_y>=required then
      local skills_y=rail_bottom-skills_h
      local runes_y=skills_y-12-runes_h
      inventory_y=runes_y-12-inventory_h
      place(self.inventory,card_x,inventory_y,card_w,inventory_h)
      place(self.inventory_title,list_x,inventory_y+rp,list_w,title_h)
      place(self.inventory_output,list_x,inventory_y+rp+title_h,list_w,list_h)
      place(self.inventory_footer,list_x,inventory_y+rp+title_h+list_h+4,list_w,footer_h)
      place(self.runes,card_x,runes_y,card_w,runes_h); place(self.runes_title,list_x,runes_y+rp,list_w,title_h); place(self.runes_output,list_x,runes_y+rp+title_h,list_w,list_h)
      place(self.skills,card_x,skills_y,card_w,skills_h); place(self.skills_title,list_x,skills_y+rp,list_w,title_h); place(self.skills_output,list_x,skills_y+rp+title_h,list_w,list_h)
    else
      local fallback_h=math.max(0,rail_bottom-inventory_y); local gap=8
      local minimum_inventory=rp*2+title_h+layout.list_row_height+footer_h+4
      local minimum_runes=rp*2+title_h+layout.list_row_height+4
      local minimum_skills=rp*2+title_h+layout.list_row_height+4
      if fallback_h>=minimum_inventory+gap+minimum_runes+gap+minimum_skills then
        local usable=fallback_h-gap*2; local inventory_h=math.floor(usable/3); local runes_h=math.floor((usable-inventory_h)/2); local skills_h=usable-inventory_h-runes_h
        local runes_y=inventory_y+inventory_h+gap; local skills_y=runes_y+runes_h+gap
        place(self.inventory,card_x,inventory_y,card_w,inventory_h); place(self.inventory_title,list_x,inventory_y+rp,list_w,title_h); place(self.inventory_output,list_x,inventory_y+rp+title_h,list_w,math.min(list_h,math.max(layout.list_row_height,inventory_h-rp*2-title_h-footer_h-4))); place(self.inventory_footer,list_x,inventory_y+inventory_h-rp-footer_h,list_w,footer_h)
        place(self.runes,card_x,runes_y,card_w,runes_h); place(self.runes_title,list_x,runes_y+rp,list_w,title_h); place(self.runes_output,list_x,runes_y+rp+title_h,list_w,math.min(list_h,math.max(layout.list_row_height,runes_h-rp*2-title_h-4)))
        place(self.skills,card_x,skills_y,card_w,skills_h); place(self.skills_title,list_x,skills_y+rp,list_w,title_h); place(self.skills_output,list_x,skills_y+rp+title_h,list_w,math.min(list_h,math.max(layout.list_row_height,skills_h-rp*2-title_h-4)))
      else
        self.inventory:hide(); self.inventory_title:hide(); self.inventory_output:hide(); self.inventory_footer:hide(); self.runes:hide(); self.runes_title:hide(); self.runes_output:hide(); self.skills:hide(); self.skills_title:hide(); self.skills_output:hide()
      end
    end
    if self.inventory_output.visible then self.inventory_content:show() end
    if self.runes_output.visible then self.runes_content:show() end
    if self.skills_output.visible then self.skills_content:show() end
    View.raiseCards({self.equipment,self.inventory,self.details,self.runes,self.skills,self.inventory_title,self.inventory_output,self.inventory_content,self.inventory_footer,self.runes_title,self.runes_output,self.runes_content,self.skills_title,self.skills_output,self.skills_content})
  else
    self.left_bg:hide(); self.identity:hide(); self.details:hide(); self.left:hide(); self.equipment:hide(); self.inventory:hide(); self.inventory_title:hide(); self.inventory_output:hide(); self.inventory_footer:hide(); self.runes:hide(); self.runes_title:hide(); self.runes_output:hide(); self.skills:hide(); self.skills_title:hide(); self.skills_output:hide(); self.mapper_frame:hide(); self.mapper:hide(); self.map_zoom_out:hide(); self.map_center:hide(); self.map_zoom_in:hide(); self.map_clear_all:hide(); self.roundtime_bar:hide(); self.right:hide(); self.attribute_strip:hide(); place(self.compact,0,62,"100%",top-62)
  end
  do
    local vitals=self.last_state and self.last_state.vitals or {}; local bars={self.hp,self.fatigue}
    if vitals.psi and vitals.psi.visible then bars[#bars+1]=self.psi else self.psi:hide() end
    if vitals.web and vitals.web.visible then bars[#bars+1]=self.web else self.web:hide() end
    local inset=layout.vitals_strip_padding or 6; local gap=layout.vitals_strip_gap or 6
    local rows=layout.vitals_strip_rows or 1; local columns=math.ceil(#bars/rows)
    local width=math.max(1,tonumber(layout.console_width) or 1); local usable=math.max(columns,width-inset*2-gap*(columns-1)); local barWidth=usable/columns
    place(self.vitals_right,layout.console_left or 0,"100%-"..(layout.bottom or 0),layout.console_width or "100%",layout.vitals_strip_height)
    for index,g in ipairs(bars) do local row=math.floor((index-1)/columns); local column=(index-1)%columns; place(g,inset+column*(barWidth+gap),inset+row*(layout.lower_gauge_height+gap),barWidth,layout.lower_gauge_height) end
    self.carry:hide(); self.vitals_right:raise()
  end
  if layout.mode~="compact" then
    place(self.right_bg,0,0,"100%","100%"); self.right_title:hide()
    local panel_height=tonumber(self.right.height) or math.max(0,(layout.window_height or 800)-top-bottom)
    local lower=layout.lower_geometry or Layout.lowerPanelGeometry(layout,false,false,true)
    local inset=lp
    local compass_h,utility_h=lower.compass_height,lower.utility_height
    local utility_y,compass_y=lower.utility_y,lower.compass_y
    local mapper_h,mapper_y=lower.mapper_height,lower.mapper_y
    local content_top=lower.content_top
    local room_h=lower.room_height
    layout.lower_room_visible_height=room_h
    if room_h>0 then place(self.room,inset,content_top,"100%-"..(inset*2),room_h) else self.room:hide() end
    if layout.mapper_visible and mapper_h>0 then
      place(self.mapper_frame,inset,mapper_y,"100%-"..(inset*2),mapper_h)
      local toolbar=layout.lower_mapper_toolbar_height or 0; local button_h=math.max(16,toolbar-6)
      local frame_w=math.max(1,layout.left-inset*2); local clear_w=math.max(54,math.min(110,frame_w-60))
      local zoom_w=math.max(12,math.min(24,math.floor((frame_w-clear_w-8)/3)))
      place(self.map_zoom_out,4,3,zoom_w,button_h); place(self.map_center,4+zoom_w,3,zoom_w,button_h); place(self.map_zoom_in,4+zoom_w*2,3,zoom_w,button_h)
      place(self.map_clear_all,frame_w-clear_w-4,3,clear_w,button_h)
      self.map_zoom_out:echo(View.withFont("<center><b>−</b></center>",layout.lower_utility_font)); self.map_center:echo(View.withFont("<center><b>◎</b></center>",layout.lower_utility_font)); self.map_zoom_in:echo(View.withFont("<center><b>+</b></center>",layout.lower_utility_font))
      self:setMapClearPending(self.map_clear_pending)
      place(self.mapper,4,toolbar,"100%-8","100%-"..toolbar); self.mapper:raise()
      self.map_zoom_out:raise(); self.map_center:raise(); self.map_zoom_in:raise(); self.map_clear_all:raise()
    else self.mapper_frame:hide(); self.mapper:hide(); self.map_zoom_out:hide(); self.map_center:hide(); self.map_zoom_in:hide(); self.map_clear_all:hide() end
    place(self.compass_area,inset,compass_y,"100%-"..(inset*2),compass_h); self.compass_area:raise()
    local cell_width=33.333; for _,entry in ipairs(self.direction_buttons) do local d=entry.direction; place(entry.label,(d.col-1)*cell_width.."%",(d.row-1)*layout.lower_compass_cell,cell_width.."%",layout.lower_compass_cell) end
    place(self.compass_center,cell_width.."%",layout.lower_compass_cell,cell_width.."%",layout.lower_compass_cell)
    place(self.utility_area,inset,utility_y,"100%-"..(inset*2),utility_h); self.utility_area:raise()
    for i,entry in ipairs(self.utility_buttons) do local col=(i-1)%2; local row=math.floor((i-1)/2); place(entry.label,(col*50).."%",row*(layout.lower_utility_height+2),"49%",layout.lower_utility_height) end
    if lower.roundtime_visible then
      place(self.roundtime_bar,inset,lower.roundtime_y,"100%-"..(inset*2),lower.roundtime_height)
      self.roundtime_bar.text:setStyleSheet("background:transparent;color:"..self.settings.theme.text..";font-size:"..layout.lower_roundtime_font.."px;font-weight:700;")
      self.roundtime_bar:raise()
    else self.roundtime_bar:hide() end
  end
  self:applyChatWrap(layout)
  self:layoutColorMenu(layout)
  self:layoutColorSettings(layout)
  self:layoutHelp(layout)
  self:layoutFeedback(layout)
  self:layoutSupport(layout)
  self:layoutRollerSettings(layout)
  self:layoutMapSettings(layout)
  self:layoutMapLibrary(layout)
end
function View:layoutColorMenu(layout)
  if not self.color_menu_visible then
    self.color_menu_scrim:hide(); self.color_menu:hide(); self.color_menu_bg:hide(); self.options_scroll:hide(); for _,button in pairs(self.option_action_buttons or {}) do button:hide() end; return true
  end
  local width=math.max(1,tonumber(layout.window_width) or 1200); local height=math.max(1,tonumber(layout.window_height) or 800)
  local all={}; for _,key in ipairs(self.option_action_order or {}) do all[#all+1]={kind="action",key=key} end
  local anchor=self.options_anchor or {}; local anchorY=tonumber(anchor.y) or 0; local anchorHeight=tonumber(anchor.height) or 0
  local columns=1; local rows=#all
  local menuWidth=math.min(250,math.max(1,width-8)); local rowHeight=math.max(30,(layout.color_toggle_font or 11)+16); local y=anchorY+anchorHeight+4; local availableHeight=math.max(1,height-y-4); local menuHeight=math.min(availableHeight,rowHeight*rows+8)
  local x=0
  place(self.color_menu_scrim,0,0,"100%","100%"); place(self.color_menu,x,y,menuWidth,menuHeight); place(self.color_menu_bg,0,0,"100%","100%"); place(self.options_scroll,4,4,menuWidth-8,math.max(1,menuHeight-8))
  local columnWidth=(menuWidth-8)/columns; self.options_scroll.content_height=rowHeight*rows
  for index,item in ipairs(all) do local column=0; local row=index-1; local button=self.option_action_buttons[item.key]; place(button,column*columnWidth,row*rowHeight,columnWidth,rowHeight) end
  self:renderColorOptions()
  local raised={self.color_menu_scrim,self.color_menu,self.color_menu_bg,self.options_scroll}; for _,item in ipairs(all) do raised[#raised+1]=self.option_action_buttons[item.key] end; raised[#raised+1]=self.color_toggle; View.raiseCards(raised)
  return true
end
function View:colorSettingsWidgets() local widgets={self.color_settings_overlay,self.color_settings_panel,self.color_settings_bg,self.color_settings_title,self.color_settings_content,self.color_settings_close}; for _,button in pairs(self.color_option_buttons) do widgets[#widgets+1]=button end; return widgets end
function View:layoutColorSettings(layout)
  local widgets=self:colorSettingsWidgets(); if not self.color_settings_visible then for _,widget in ipairs(widgets) do widget:hide() end; return true end
  local width,height=math.max(1,layout.window_width or 1200),math.max(1,layout.window_height or 800); local margin=layout.mode=="compact" and 8 or 18; local pw,ph=math.min(640,width-margin*2),math.min(590,height-margin*2); local x=math.floor((width-pw)/2); local y=math.floor((height-ph)/2); local font=math.max(10,math.min(14,(layout.body_font or 14)-2)); local columns=pw>=430 and 2 or 1; local gap=8; local cw=(pw-28-gap*(columns-1))/columns; local row=math.max(34,font+20); local rows=math.ceil(#self.color_option_order/columns)
  place(self.color_settings_overlay,0,0,"100%","100%"); place(self.color_settings_panel,x,y,pw,ph); place(self.color_settings_bg,0,0,"100%","100%"); place(self.color_settings_title,14,10,pw-150,30); self.color_settings_title:echo(View.withFont("<b>COLOR SETTINGS</b>",font+3)); place(self.color_settings_close,pw-116,8,102,32); self.color_settings_close:echo(View.withFont("<center><b>CLOSE</b></center>",font)); place(self.color_settings_content,14,48,pw-28,math.max(1,ph-64)); self.color_settings_content.content_height=rows*row
  for index,key in ipairs(self.color_option_order) do local column=(index-1)%columns; local line=math.floor((index-1)/columns); place(self.color_option_buttons[key],column*(cw+gap),line*row,cw,row-4) end; self:renderColorOptions(); View.raiseCards(widgets); return true
end
function View:layoutRollerSettings(layout)
  local widgets={self.roller_overlay,self.roller_panel,self.roller_bg,self.roller_content,self.roller_title,self.roller_status,self.roller_save,self.roller_cancel}; for _,entry in pairs(self.roller_fields or {}) do widgets[#widgets+1]=entry.caption; widgets[#widgets+1]=entry.input end; for _,button in pairs(self.roller_toggles or {}) do widgets[#widgets+1]=button end; for _,button in pairs(self.roller_action_buttons or {}) do widgets[#widgets+1]=button end
  if not self.roller_settings_visible then for _,widget in ipairs(widgets) do widget:hide() end; return true end
  local width=math.max(1,tonumber(layout.window_width) or 1200); local height=math.max(1,tonumber(layout.window_height) or 800); local margin=math.min(18,math.max(6,math.floor(math.min(width,height)*.025)))
  local panelWidth=math.min(820,math.max(1,width-margin*2)); local panelHeight=math.min(650,math.max(1,height-margin*2)); local x=math.floor((width-panelWidth)/2); local y=math.floor((height-panelHeight)/2)
  place(self.roller_overlay,0,0,"100%","100%"); place(self.roller_panel,x,y,panelWidth,panelHeight); place(self.roller_bg,0,0,"100%","100%")
  local font=math.max(10,math.min(14,(layout.body_font or 14)-3)); local header=math.min(math.max(30,font+20),math.max(30,panelHeight*.28)); local buttonHeight=math.max(24,font+14); local footer=panelHeight<220 and buttonHeight+14 or math.max(76,font*4+20)
  place(self.roller_title,14,9,panelWidth-28,header-10); self.roller_title:echo(View.withFont("<b>AUTOROLLER SETTINGS</b>",font+2))
  local gap=10; local contentWidth=math.max(1,panelWidth-28); local columns=layout.mode~="compact" and panelWidth>=400 and 2 or 1; local columnWidth=columns==2 and (contentWidth-gap)/2 or contentWidth; local contentTop=header; local viewportHeight=math.max(1,panelHeight-header-footer); local rowHeight=42
  place(self.roller_content,14,contentTop,contentWidth,viewportHeight)
  local left={"target_total","hard_stop","max_rolls","reroll_delay","reroll_command","log_folder","master_file","auto_start_on_name","use_min_stats","require_min_stats_to_stop","show_every_roll","logging_enabled","roller_start","roller_stop","roller_stats","roller_last","roller_reset","roller_help"}
  local right={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"}
  local function layoutColumn(items,column)
    local cx=(column-1)*(columnWidth+gap)
    for index,key in ipairs(items) do local ry=(index-1)*rowHeight; local field=self.roller_fields[key]
      if field then local captionHeight=math.max(10,math.min(font+5,rowHeight*.42)); place(field.caption,cx,ry,columnWidth,captionHeight); place(field.input,cx,ry+captionHeight,columnWidth,math.max(12,rowHeight-captionHeight-2)); field.input:setStyleSheet("background:#080b0a;border:1px solid "..self.settings.theme.border..";border-radius:3px;color:"..self.settings.theme.text..";font-size:"..font.."px;")
      else local button=self.roller_toggles[key] or self.roller_action_buttons[key]; place(button,cx,ry+2,columnWidth,math.max(16,rowHeight-4)) end
    end
  end
  local contentRows
  if columns==2 then layoutColumn(left,1); layoutColumn(right,2); contentRows=math.max(#left,#right)
  else local combined={}; for _,key in ipairs(left) do combined[#combined+1]=key end; for _,key in ipairs(right) do combined[#combined+1]=key end; layoutColumn(combined,1); contentRows=#combined end
  self.roller_content.content_height=contentRows*rowHeight
  local statusY=panelHeight-footer+5; if panelHeight>=220 then place(self.roller_status,14,statusY,panelWidth-28,math.max(24,font*2+4)) else self.roller_status:hide() end
  local buttonY=panelHeight-buttonHeight-8; local buttonWidth=math.min(130,(panelWidth-38)/2); place(self.roller_cancel,panelWidth-14-buttonWidth*2-10,buttonY,buttonWidth,buttonHeight); place(self.roller_save,panelWidth-14-buttonWidth,buttonY,buttonWidth,buttonHeight); self.roller_cancel:echo(View.withFont("<center><b>CANCEL</b></center>",font)); self.roller_save:echo(View.withFont("<center><b>SAVE</b></center>",font))
  self:renderRollerSettings(false); View.raiseCards(widgets); return true
end
function View:layoutMapSettings(layout)
  local widgets={self.map_settings_overlay,self.map_settings_panel,self.map_settings_bg,self.map_settings_content,self.map_settings_title,self.map_settings_status,self.map_settings_save,self.map_settings_cancel,self.map_settings_library,self.map_settings_clear_current,self.map_settings_clear_all,self.map_settings_area_name,self.map_settings_subarea_name,self.map_settings_rename_area,self.map_settings_rename_subarea}
  for _,v in pairs(self.map_settings_fields or {}) do widgets[#widgets+1]=v.caption; widgets[#widgets+1]=v.input end; for _,v in pairs(self.map_settings_toggles or {}) do widgets[#widgets+1]=v end
  if not self.map_settings_visible then for _,w in ipairs(widgets) do w:hide() end; return true end
  local width,height=math.max(1,layout.window_width or 1200),math.max(1,layout.window_height or 800); local margin=layout.mode=="compact" and 8 or 18
  local pw,ph=math.min(780,width-margin*2),math.min(650,height-margin*2); place(self.map_settings_overlay,0,0,"100%","100%"); place(self.map_settings_panel,math.floor((width-pw)/2),math.floor((height-ph)/2),pw,ph); place(self.map_settings_bg,0,0,"100%","100%")
  local font=math.max(10,math.min(14,(layout.body_font or 14)-3)); place(self.map_settings_title,14,9,pw-28,32); self.map_settings_title:echo(View.withFont("<b>MAP SETTINGS</b>",font+2))
  local footer=74; place(self.map_settings_content,14,44,pw-28,ph-44-footer); local columns=pw>=600 and 2 or 1; local gap=10; local cw=columns==2 and (pw-38)/2 or pw-28; local row=44; local items={}
  for _,key in ipairs(self.map_settings_toggle_order) do items[#items+1]={kind="toggle",key=key} end; for _,key in ipairs(self.map_settings_field_order) do items[#items+1]={kind="field",key=key} end
  for i,item in ipairs(items) do local col=columns==2 and ((i-1)%2) or 0; local r=columns==2 and math.floor((i-1)/2) or i-1; local x=col*(cw+gap); local y=r*row
    if item.kind=="toggle" then place(self.map_settings_toggles[item.key],x,y+3,cw,row-6) else local f=self.map_settings_fields[item.key]; place(f.caption,x,y,cw,18); place(f.input,x,y+19,cw,row-21); f.input:setStyleSheet("background:#080b0a;border:1px solid "..self.settings.theme.border..";border-radius:3px;color:"..self.settings.theme.text..";font-size:"..font.."px;") end
  end
  local rows=math.ceil(#items/columns); local namesY=rows*row+12
  local inputStyle="background:#080b0a;border:1px solid "..self.settings.theme.border..";border-radius:3px;color:"..self.settings.theme.text..";font-size:"..font.."px;"
  place(self.map_settings_area_name,0,namesY,cw,30); place(self.map_settings_rename_area,columns==2 and cw+gap or 0,namesY+((columns==1) and 34 or 0),cw,30)
  place(self.map_settings_subarea_name,0,namesY+((columns==1) and 70 or 36),cw,30); place(self.map_settings_rename_subarea,columns==2 and cw+gap or 0,namesY+((columns==1) and 104 or 36),cw,30)
  self.map_settings_area_name:setStyleSheet(inputStyle); self.map_settings_subarea_name:setStyleSheet(inputStyle)
  local libraryY=namesY+((columns==1) and 142 or 74); place(self.map_settings_library,0,libraryY,pw-28,38); local dangerY=libraryY+44; place(self.map_settings_clear_current,0,dangerY,cw,38); place(self.map_settings_clear_all,columns==2 and cw+gap or 0,dangerY+((columns==1) and 44 or 0),cw,38); self.map_settings_content.content_height=dangerY+((columns==1) and 90 or 46)
  place(self.map_settings_status,14,ph-footer+5,pw-300,28); local bw=120; place(self.map_settings_cancel,pw-14-bw*2-10,ph-42,bw,32); place(self.map_settings_save,pw-14-bw,ph-42,bw,32); self.map_settings_cancel:echo(View.withFont("<center><b>CANCEL</b></center>",font)); self.map_settings_save:echo(View.withFont("<center><b>SAVE</b></center>",font)); self:renderMapSettings(false); View.raiseCards(widgets); return true
end
function View:layoutHelp(layout)
  if not self.help_visible then
    for _,widget in ipairs({self.help_overlay,self.help_panel,self.help_bg,self.help_title,self.help_copy,self.help_close,self.help_output,self.help_content}) do widget:hide() end
    return true
  end
  local width=math.max(1,tonumber(layout.window_width) or 1200); local height=math.max(1,tonumber(layout.window_height) or 800)
  local margin=layout.mode=="compact" and 12 or math.max(18,layout.panel_padding or 12)
  local panelWidth
  if layout.mode=="compact" then panelWidth=math.max(1,width-margin*2)
  else panelWidth=math.min(780,math.max(360,math.floor((layout.console_width or width)*.72))) end
  panelWidth=math.min(panelWidth,math.max(1,width-margin*2))
  local panelHeight=math.min(layout.mode=="compact" and math.floor(height*.84) or 620,math.max(180,math.floor(height*.72)))
  panelHeight=math.min(panelHeight,math.max(1,height-margin*2))
  local x=math.max(0,math.floor((width-panelWidth)/2)); local y=math.max(0,math.floor((height-panelHeight)/2))
  self.help_font=math.max(11,math.min(15,tonumber(layout.body_font or 16)-3)); layout.help_font=self.help_font
  place(self.help_overlay,0,0,"100%","100%"); place(self.help_panel,x,y,panelWidth,panelHeight); place(self.help_bg,0,0,"100%","100%")
  local closeWidth=math.max(64,math.min(94,math.floor(panelWidth*.22))); local headerHeight=math.max(40,self.help_font+24)
  local copyWidth=math.max(64,math.min(94,math.floor(panelWidth*.22))); place(self.help_title,16,10,panelWidth-closeWidth-copyWidth-50,headerHeight-14); self.help_title:echo(View.withFont("<b>DGHUD COMMAND GUIDE</b>",self.help_font+2))
  place(self.help_copy,panelWidth-closeWidth-copyWidth-18,8,copyWidth,headerHeight-14); self.help_copy:echo(View.withFont("<center><b>COPY</b></center>",self.help_font)); place(self.help_close,panelWidth-closeWidth-12,8,closeWidth,headerHeight-14); self.help_close:echo(View.withFont("<center><b>× CLOSE</b></center>",self.help_font))
  local outputHeight=math.max(1,panelHeight-headerHeight-14); place(self.help_output,12,headerHeight,panelWidth-24,outputHeight)
  local contentWidth=math.max(1,panelWidth-52); local entries=self.help_entries or View.defaultHelpEntries()
  local contentHeight=math.max(outputHeight,#entries*math.ceil(self.help_font*3.8)+20)
  place(self.help_content,8,6,contentWidth,contentHeight); self.help_content:echo(View.helpContent(entries,self.settings.theme,layout))
  View.raiseCards({self.help_overlay,self.help_panel,self.help_bg,self.help_title,self.help_copy,self.help_close,self.help_output,self.help_content})
  return true
end
function View:feedbackWidgets() return {self.feedback_overlay,self.feedback_panel,self.feedback_bg,self.feedback_title,self.feedback_explanation,self.feedback_kind,self.feedback_summary_label,self.feedback_summary,self.feedback_details_label,self.feedback_details,self.feedback_status,self.feedback_send,self.feedback_cancel} end
function View:layoutFeedback(layout)
  local widgets=self:feedbackWidgets(); if not self.feedback_visible then for _,widget in ipairs(widgets) do widget:hide() end; return true end
  local width,height=math.max(1,tonumber(layout.window_width) or 1200),math.max(1,tonumber(layout.window_height) or 800); local margin=layout.mode=="compact" and 8 or 18
  local pw,ph=math.min(700,width-margin*2),math.min(460,height-margin*2); local x=math.max(0,math.floor((width-pw)/2)); local y=math.max(0,math.floor((height-ph)/2)); local font=math.max(10,math.min(14,(layout.body_font or 14)-2))
  place(self.feedback_overlay,0,0,"100%","100%"); place(self.feedback_panel,x,y,pw,ph); place(self.feedback_bg,0,0,"100%","100%")
  place(self.feedback_title,16,10,pw-32,30); place(self.feedback_explanation,16,44,pw-32,76); place(self.feedback_kind,16,124,math.min(190,pw-32),32)
  place(self.feedback_summary_label,16,164,pw-32,22); place(self.feedback_summary,16,187,pw-32,32)
  place(self.feedback_details_label,16,226,pw-32,22); place(self.feedback_details,16,249,pw-32,math.max(32,ph-335))
  local buttonWidth=math.min(140,(pw-42)/2); place(self.feedback_status,16,ph-78,pw-buttonWidth*2-48,60); place(self.feedback_cancel,pw-buttonWidth*2-26,ph-50,buttonWidth,34); place(self.feedback_send,pw-buttonWidth-16,ph-50,buttonWidth,34)
  local style="background:#080b0a;border:1px solid "..self.settings.theme.border..";border-radius:3px;color:"..self.settings.theme.text..";font-size:"..font.."px;"; self.feedback_summary:setStyleSheet(style); self.feedback_details:setStyleSheet(style)
  self:renderFeedback(false); View.raiseCards(widgets); return true
end
function View:supportWidgets() return {self.support_overlay,self.support_panel,self.support_bg,self.support_title,self.support_text,self.support_feedback,self.support_debug,self.support_close,self.support_status} end
function View:layoutSupport(layout)
  local widgets=self:supportWidgets(); if not self.support_visible then for _,widget in ipairs(widgets) do widget:hide() end; return true end
  local width,height=math.max(1,layout.window_width or 1200),math.max(1,layout.window_height or 800); local margin=layout.mode=="compact" and 8 or 18; local pw,ph=math.min(560,width-margin*2),math.min(360,height-margin*2); local x=math.floor((width-pw)/2); local y=math.floor((height-ph)/2); local font=math.max(10,math.min(14,(layout.body_font or 14)-2))
  place(self.support_overlay,0,0,"100%","100%"); place(self.support_panel,x,y,pw,ph); place(self.support_bg,0,0,"100%","100%"); place(self.support_title,16,10,pw-32,32); place(self.support_text,16,50,pw-32,70); place(self.support_feedback,16,126,pw-32,40); place(self.support_debug,16,174,pw-32,40); place(self.support_status,16,222,pw-32,math.max(24,ph-278)); place(self.support_close,pw-126,ph-48,110,34); self:renderSupport(font); View.raiseCards(widgets); return true
end
function View:renderSupport(font) font=font or (self.layout and math.max(10,math.min(14,(self.layout.body_font or 14)-2)) or 11); self.support_title:echo(View.withFont("<b>SUPPORT</b>",font+3)); self.support_text:echo(View.withFont("Send feedback, request a feature, or anonymously submit the latest privacy-safe debug report. No GitHub account or browser is needed.",font)); self.support_feedback:echo(View.withFont("<center><b>FEEDBACK & REQUESTS…</b></center>",font)); self.support_debug:echo(View.withFont("<center><b>SEND LAST DEBUG REPORT</b></center>",font)); self.support_status:echo(View.withFont(safeText(self.support_status_text or "Debug reports exclude chat, room prose, credentials, character names, and command history."),font)); self.support_close:echo(View.withFont("<center><b>CLOSE</b></center>",font)); return true end
function View:showSupport() self:hideHelp(); self:hideMapSettings(); self:hideMapLibrary(); self:hideRollerSettings(); if self.color_settings_visible then self:hideColorSettings() end; self.support_visible=true; self.support_status_text=nil; self:setColorMenuVisible(false); if self.layout then self:layoutSupport(self.layout) end; return true end
function View:hideSupport() self.support_visible=false; if self.layout then self:layoutSupport(self.layout) end; return true end
function View:setSupportStatus(message) self.support_status_text=tostring(message or ""); if self.support_visible then self:renderSupport() end; return true end
function View:setHelpCloseCallback(callback) self.help_close_callback=type(callback)=="function" and callback or nil; return true end
function View:setHelpVisible(visible,entries)
  self.help_visible=visible==true
  if self.help_visible then self:setColorMenuVisible(false); self:hideRollerSettings(); self:hideMapSettings(); self:hideMapLibrary(); if self.feedback_visible then self:hideFeedback() end; if self.color_settings_visible then self:hideColorSettings() end; if self.support_visible then self:hideSupport() end end
  if entries~=nil then self.help_entries=type(entries)=="table" and entries or View.defaultHelpEntries() end
  if self.layout then return self:layoutHelp(self.layout) end
  return true
end
function View:showHelp(entries) return self:setHelpVisible(true,entries) end
function View:hideHelp() return self:setHelpVisible(false) end
function View:setMapCenterCallback(callback) self.map_center_callback=type(callback)=="function" and callback or nil; return true end
function View:setColorToggleCallback(callback) self.color_toggle_callback=type(callback)=="function" and callback or nil; return true end
function View:setColorOptionsCallback(callback) self.color_options_callback=type(callback)=="function" and callback or nil; return true end
function View:setOptionsActionCallback(callback) self.options_action_callback=type(callback)=="function" and callback or nil; return true end
function View:setFeedbackCallback(callback) self.feedback_callback=type(callback)=="function" and callback or nil; return true end
function View:setCopyTextCallback(callback) self.copy_text_callback=type(callback)=="function" and callback or nil; return true end
function View:setMapLibraryActionCallback(callback) self.map_library_action_callback=type(callback)=="function" and callback or nil; return true end
function View:setMapCollectionActionCallback(callback) self.map_collection_action_callback=type(callback)=="function" and callback or nil; return true end
function View:setRollerSettingsCallback(callback) self.roller_settings_callback=type(callback)=="function" and callback or nil; return true end
function View:setMapSettingsCallback(callback) self.map_settings_callback=type(callback)=="function" and callback or nil; return true end
function View:setMapSettingsActionCallback(callback) self.map_settings_action_callback=type(callback)=="function" and callback or nil; return true end
function View:selectOptionsAction(action)
  self:setColorMenuVisible(false)
  if action=="command_help" then return self:showHelp() end
  if action=="color_settings" then return self:showColorSettings() end
  if action=="support" then return self:showSupport() end
  if action=="map_settings" then if self.options_action_callback then local config=self.options_action_callback(action); if type(config)=="table" then return self:showMapSettings(config) end; return config end; return nil,"map settings are unavailable" end
  if action=="roller_settings" then if self.options_action_callback then local config=self.options_action_callback(action); if type(config)=="table" then return self:showRollerSettings(config) end; return config end; return nil,"autoroller settings are unavailable" end
  if self.options_action_callback then return self.options_action_callback(action) end
  return nil,"options action is unavailable"
end
function View:showColorSettings() self:hideHelp(); self:hideMapSettings(); self:hideMapLibrary(); self:hideRollerSettings(); if self.feedback_visible then self:hideFeedback() end; if self.support_visible then self:hideSupport() end; self.color_settings_visible=true; self:setColorMenuVisible(false); if self.layout then self:layoutColorSettings(self.layout) end; return true end
function View:hideColorSettings() self.color_settings_visible=false; if self.layout then self:layoutColorSettings(self.layout) end; return true end
function View:showFeedback()
  self:hideHelp(); self:hideMapSettings(); self:hideMapLibrary(); self:hideRollerSettings(); if self.color_settings_visible then self:hideColorSettings() end; if self.support_visible then self:hideSupport() end; self:setColorMenuVisible(false); self.feedback_draft={kind="feedback"}; self.feedback_visible=true; self.feedback_sending=false; self.feedback_error=nil; self.feedback_result=nil
  if self.feedback_summary.print then self.feedback_summary:print("") end; if self.feedback_details.print then self.feedback_details:print("") end
  if self.layout then self:layoutFeedback(self.layout) end; return true
end
function View:hideFeedback() if self.feedback_sending then return nil,"feedback is being sent" end; self.feedback_visible=false; self.feedback_draft=nil; if self.layout then self:layoutFeedback(self.layout) end; return true end
function View:renderFeedback()
  if not self.feedback_draft then return true end; local font=self.layout and math.max(10,math.min(14,(self.layout.body_font or 14)-2)) or 11; local kind=self.feedback_draft.kind=="request" and "FEATURE REQUEST" or "FEEDBACK"
  self.feedback_title:echo(View.withFont("<b>FEEDBACK & REQUESTS</b>",font+3)); self.feedback_explanation:echo(View.withFont("Tell us what happened or what you would like added. Be as detailed as possible. This submits anonymously to the DGHUD GitHub project; no GitHub account or browser is needed. Do not include passwords or private account information.",font))
  self.feedback_kind:echo(View.withFont("<center><b>TYPE: "..kind.."</b></center>",font)); self.feedback_summary_label:echo(View.withFont("Short summary",font)); self.feedback_details_label:echo(View.withFont("Detailed description",font))
  local status=self.feedback_error and ("<span style='color:"..self.settings.theme.hp.."'><b>"..safeText(self.feedback_error).."</b></span>") or safeText(self.feedback_result or "Click the type button to switch between feedback and a feature request."); self.feedback_status:echo(View.withFont(status,font)); self.feedback_cancel:echo(View.withFont("<center><b>CANCEL</b></center>",font)); self.feedback_send:echo(View.withFont("<center><b>"..(self.feedback_sending and "SENDING…" or "SEND").."</b></center>",font)); return true
end
function View:finishFeedback(result,err)
  self.feedback_sending=false; if err then self.feedback_error="Could not send: "..tostring(err) else self.feedback_error=nil; self.feedback_result="Sent anonymously. Reference: "..tostring(result and (result.report_id or result.number) or "received"); if self.feedback_summary.print then self.feedback_summary:print("") end; if self.feedback_details.print then self.feedback_details:print("") end end; self:renderFeedback(false); return err==nil
end
function View:sendFeedback()
  if self.feedback_sending then return nil,"feedback is already being sent" end; if not self.feedback_callback then self.feedback_error="Feedback service is unavailable"; self:renderFeedback(false); return nil,self.feedback_error end
  local payload={kind=self.feedback_draft and self.feedback_draft.kind or "feedback",summary=self.feedback_summary.getText and self.feedback_summary:getText() or "",details=self.feedback_details.getText and self.feedback_details:getText() or ""}
  self.feedback_sending=true; self.feedback_error=nil; self:renderFeedback(false); local called,ok,err=pcall(self.feedback_callback,payload,function(result,sendErr) self:finishFeedback(result,sendErr) end); if not called then err=tostring(ok); ok=nil end; if not ok then self.feedback_sending=false; self.feedback_error=err or "Could not start upload"; self:renderFeedback(false); return nil,self.feedback_error end; return true
end
function View:showMapLibrary()
  self:hideMapSettings(); self.map_library_visible=true; self:setColorMenuVisible(false); self:hideHelp(); self:hideRollerSettings(); if self.feedback_visible then self:hideFeedback() end; if self.color_settings_visible then self:hideColorSettings() end; if self.support_visible then self:hideSupport() end; if self.layout then self:layoutMapLibrary(self.layout) end; return true
end
function View:hideMapLibrary() self.map_library_visible=false; if self.layout then self:layoutMapLibrary(self.layout) end; return true end
function View:layoutMapLibrary(layout)
  local widgets={self.map_library_overlay,self.map_library_panel,self.map_library_bg,self.map_library_title,self.map_library_copy,self.map_library_search_label,self.map_library_search,self.map_library_list,self.map_collection_list,self.map_library_copy_button,self.map_library_close}; for _,group in ipairs({self.map_library_filters,self.map_library_modes,self.map_library_actions,self.map_collection_actions,self.map_library_download_actions}) do for _,button in pairs(group or {}) do widgets[#widgets+1]=button end end; for _,row in ipairs(self.map_library_rows or {}) do widgets[#widgets+1]=row end; for _,row in ipairs(self.map_collection_rows or {}) do widgets[#widgets+1]=row end
  if not self.map_library_visible then for _,widget in ipairs(widgets) do widget:hide() end; return true end
  local width,height=math.max(1,tonumber(layout.window_width) or 1200),math.max(1,tonumber(layout.window_height) or 800); local margin=layout.mode=="compact" and 8 or 18
  local panelWidth=math.min(760,math.max(1,width-margin*2)); local panelHeight=math.min(560,math.max(1,height-margin*2)); local x=math.floor((width-panelWidth)/2); local y=math.floor((height-panelHeight)/2); local font=math.max(10,math.min(15,(layout.body_font or 16)-2))
  place(self.map_library_overlay,0,0,"100%","100%"); place(self.map_library_panel,x,y,panelWidth,panelHeight); place(self.map_library_bg,0,0,"100%","100%")
  local closeWidth=math.min(92,math.max(58,math.floor(panelWidth*.2))); local copyWidth=math.min(92,math.max(58,math.floor(panelWidth*.2))); place(self.map_library_title,16,10,panelWidth-closeWidth-copyWidth-48,34); place(self.map_library_copy_button,panelWidth-closeWidth-copyWidth-18,8,copyWidth,30); place(self.map_library_close,panelWidth-closeWidth-12,8,closeWidth,30)
  self.map_library_title:echo(View.withFont("<b>MAP LIBRARY</b>",font+2)); self.map_library_copy_button:echo(View.withFont("<center><b>COPY</b></center>",font)); self.map_library_close:echo(View.withFont("<center><b>× CLOSE</b></center>",font))
  local tabTop=44; local tabGap=6; local tabWidth=(panelWidth-36-tabGap)/2
  for index,key in ipairs(self.map_library_mode_order) do local button=self.map_library_modes[key]; local active=self.map_library_mode==key; button:setStyleSheet("background:"..(active and "#193024" or "#111512")..";border:1px solid "..(active and self.settings.theme.jade or self.settings.theme.border)..";border-radius:4px;color:"..(active and self.settings.theme.jade or self.settings.theme.muted)..";font-weight:700;"); button:echo(View.withFont("<center><b>"..button.option_text.."</b></center>",font)); place(button,18+(index-1)*(tabWidth+tabGap),tabTop,tabWidth,28) end
  place(self.map_library_copy,18,76,panelWidth-36,50); self.map_library_copy:echo(View.withFont(safeText(self.map_library_status or "Map library ready."),font))
  local libraryMode=self.map_library_mode=="library" or self.map_library_import_pending
  local searchTop=126; place(self.map_library_search_label,18,searchTop,64,28); self.map_library_search_label:echo(View.withFont(libraryMode and "<b>SEARCH</b>" or "<b>NAME</b>",font)); place(self.map_library_search,82,searchTop,panelWidth-100,28); if self.map_library_search.setStyleSheet then self.map_library_search:setStyleSheet("background:#080b0a;color:"..self.settings.theme.text..";border:1px solid "..self.settings.theme.border..";") end
  local filterTop=158; local filterGap=4; local filterWidth=(panelWidth-36-filterGap*3)/4
  for index,key in ipairs(self.map_library_filter_order) do local button=self.map_library_filters[key]; if libraryMode then local active=self.map_library_filter==key; button:setStyleSheet("background:"..(active and "#193024" or "#111512")..";border:1px solid "..(active and self.settings.theme.jade or self.settings.theme.border)..";border-radius:4px;color:"..(active and self.settings.theme.jade or self.settings.theme.muted)..";font-weight:700;"); button:echo(View.withFont("<center>"..button.option_text.."</center>",math.max(9,font-1))); place(button,18+(index-1)*(filterWidth+filterGap),filterTop,filterWidth,26) else button:hide() end end
  for _,group in ipairs({self.map_library_actions,self.map_collection_actions,self.map_library_download_actions}) do for _,button in pairs(group or {}) do button:hide() end end
  local actionOrder,actionSource
  if self.map_library_import_pending then actionOrder={"keep","replace","skip","confirm","cancel","report"}; actionSource=self.map_library_actions
  elseif libraryMode then actionOrder={"browse","download_new","replace_current","update_collection","upload_my_version","report"}; actionSource={browse=self.map_library_actions.browse,report=self.map_library_actions.report,download_new=self.map_library_download_actions.download_new,replace_current=self.map_library_download_actions.replace_current,update_collection=self.map_library_download_actions.update_collection,upload_my_version=self.map_library_download_actions.upload_my_version}
  else actionOrder=self.map_collection_action_order; actionSource=self.map_collection_actions end
  local gap=6; local columns=panelWidth<430 and 1 or 2; local buttonHeight=math.max(28,font+14); local actionRows=math.ceil(#actionOrder/columns); local top=panelHeight-actionRows*(buttonHeight+gap)-12; local listTop=188; local activeList=libraryMode and self.map_library_list or self.map_collection_list; local inactiveList=libraryMode and self.map_collection_list or self.map_library_list; inactiveList:hide(); place(activeList,18,listTop,panelWidth-36,math.max(1,top-listTop-8)); local rowHeight=math.max(48,font*3+10)
  for index,row in ipairs(self.map_library_rows or {}) do place(row,0,(index-1)*(rowHeight+4),panelWidth-58,rowHeight) end; self.map_library_list.content_height=math.max(1,#(self.map_library_rows or {})*(rowHeight+4))
  for index,row in ipairs(self.map_collection_rows or {}) do place(row,0,(index-1)*(rowHeight+4),panelWidth-58,rowHeight) end; self.map_collection_list.content_height=math.max(1,#(self.map_collection_rows or {})*(rowHeight+4))
  local buttonWidth=(panelWidth-36-gap*(columns-1))/columns
  for index,key in ipairs(actionOrder) do local column=(index-1)%columns; local row=math.floor((index-1)/columns); local button=actionSource[key]; place(button,18+column*(buttonWidth+gap),top+row*(buttonHeight+gap),buttonWidth,buttonHeight); local warning=(key=="replace_collection" and self.map_collection_replace_pending) or (key=="replace_current" and self.map_library_replace_pending); button:setStyleSheet(warning and "background:#4b1111;border:2px solid #ff6860;border-radius:5px;color:#fff;font-weight:700;" or "background:#17231c;border:1px solid "..self.settings.theme.border..";border-radius:5px;color:"..self.settings.theme.jade..";font-weight:700;"); button:echo(View.withFont("<center><b>"..(warning and "WARNING: CLICK AGAIN TO REPLACE" or button.option_text).."</b></center>",font)) end
  View.raiseCards(widgets); return true
end
function View:setMapLibraryCatalog(entries,status)
  self.map_library_catalog=entries or {}; self.map_library_selected=nil; self.map_library_status=status or (#self.map_library_catalog==0 and "No community maps have been published yet." or "Search by map, area, subarea, or creator. Press Enter to search.")
  return self:refreshMapLibraryRows()
end
function View:setMapLibraryMode(mode)
  if mode~="collections" and mode~="library" then return nil,"unknown map library mode" end
  self.map_library_mode=mode; self.map_collection_replace_pending=false
  self.map_library_status=mode=="collections" and (#self.map_collections==0 and "No map collections are available yet." or "Choose one of your maps, then choose what you want to do.") or "Find complete maps or smaller area sets shared by other players."
  if self.layout then self:layoutMapLibrary(self.layout) end; return true
end
function View:setMapCollections(collections,status)
  for _,row in ipairs(self.map_collection_rows or {}) do if row.delete then pcall(row.delete,row) else row:hide() end end
  self.map_collection_rows={}; self.map_collections={}; self.map_collection_selected=nil; self.map_collection_replace_pending=false
  for _,source in ipairs(type(collections)=="table" and collections or {}) do
    local item={id=source.id,name=tostring(source.name or "Unnamed Map"),creator=tostring(source.creator or source.author or "You"),area_count=math.max(0,tonumber(source.area_count) or #(source.areas or {})),room_count=math.max(0,tonumber(source.room_count) or 0),active=source.active==true,editable=source.editable~=false,update_available=source.update_available==true,version=source.version}
    self.map_collections[#self.map_collections+1]=item; local index=#self.map_collections
    local row=label("DGHUD.MapLibrary.CollectionRow."..index,self.map_collection_list,"background:#111814;border:1px solid "..self.settings.theme.border..";border-radius:4px;color:"..self.settings.theme.text..";",self.geyser)
    row:setClickCallback(function() self.map_collection_selected=index; self.map_collection_replace_pending=false; self.map_library_status=item.name.." — "..item.area_count.." areas, "..item.room_count.." rooms"; if self.layout then self:layoutMapLibrary(self.layout) end; return true end)
    local state=item.active and "ACTIVE" or (item.update_available and "UPDATE AVAILABLE" or (item.editable and "EDITABLE COPY" or "READ ONLY")); row:echo(View.withFont("<span style='color:"..self.settings.theme.jade.."'><b>"..state.."</b></span> &nbsp; <b>"..safeText(item.name).."</b><br>"..safeText(item.area_count).." areas · "..safeText(item.room_count).." rooms · by "..safeText(item.creator),11)); self.map_collection_rows[index]=row
  end
  self.map_library_status=status or (#self.map_collections==0 and "No map collections are available yet." or "Choose one of your maps, then choose what you want to do.")
  if self.layout then self:layoutMapLibrary(self.layout) end; return true
end
function View:selectedMapCollection() return self.map_collection_selected and self.map_collections[self.map_collection_selected] or nil end
function View:selectMapLibraryDownloadAction(action)
  local entry=self:selectedMapLibraryEntry(); if not entry then self.map_library_status="Choose a shared map first."; if self.layout then self:layoutMapLibrary(self.layout) end; return nil,"select a shared map first" end
  if action=="replace_current" and not self.map_library_replace_pending then self.map_library_replace_pending=true; self.map_library_status="WARNING: This replaces every room in the active map. A backup will be made first. Click the red button again to continue."; if self.layout then self:layoutMapLibrary(self.layout) end; return nil,"replace confirmation required" end
  self.map_library_replace_pending=false; if self.map_library_action_callback then return self.map_library_action_callback(action,entry) end; return nil,"map library action is not connected"
end
function View:selectMapCollectionAction(action)
  local selected=self:selectedMapCollection(); if not selected then self.map_library_status="Choose one of your maps first."; if self.layout then self:layoutMapLibrary(self.layout) end; return nil,"select a map collection first" end
  if action=="replace_collection" and not self.map_collection_replace_pending then self.map_collection_replace_pending=true; self.map_library_status="WARNING: Replacing can discard changes in this copy. Click the red button again only if you want to continue."; if self.layout then self:layoutMapLibrary(self.layout) end; return nil,"replace confirmation required" end
  self.map_collection_replace_pending=false
  if self.map_collection_action_callback then return self.map_collection_action_callback(action,selected,self.map_collection_name) end
  return nil,"map collection action is not connected"
end
function View:refreshMapLibraryRows()
  for _,row in ipairs(self.map_library_rows or {}) do if row.delete then pcall(row.delete,row) else row:hide() end end; self.map_library_rows={}; self.map_library_visible_catalog=MapCatalog.filterEntries(self.map_library_catalog,self.map_library_query,self.map_library_filter); self.map_library_selected=nil
  for index,entry in ipairs(self.map_library_visible_catalog) do local row=label("DGHUD.MapLibrary.Row."..index,self.map_library_list,"background:#111814;border:1px solid "..self.settings.theme.border..";border-radius:4px;color:"..self.settings.theme.text..";",self.geyser); row:setClickCallback(function() self.map_library_selected=index; self.map_library_status=entry.name.." by "..entry.author.." — "..entry.room_count.." rooms; "..table.concat(entry.areas or {},", "); if self.layout then self:layoutMapLibrary(self.layout) end; return true end); local scope=MapCatalog.scopeLabel(entry):upper(); row:echo(View.withFont("<span style='color:"..self.settings.theme.jade.."'><b>"..scope.."</b></span> &nbsp; <b>"..safeText(entry.name).."</b><br>by "..safeText(entry.author or entry.publisher).." · "..safeText(entry.room_count).." rooms · "..safeText(table.concat(entry.areas or {},", ")),11)); self.map_library_rows[index]=row end
  if #self.map_library_visible_catalog==0 and #self.map_library_catalog>0 then self.map_library_status="No shared maps match this search and filter." end
  if self.layout then self:layoutMapLibrary(self.layout) end; return true
end
function View:setMapLibrarySearch(query) self.map_library_query=tostring(query or ""):gsub("^%s+",""):gsub("%s+$",""); return self:refreshMapLibraryRows() end
function View:setMapLibraryFilter(scope) if scope~="all" and scope~="full_map" and scope~="area" and scope~="subarea" then return nil,"unknown map library filter" end; self.map_library_filter=scope; return self:refreshMapLibraryRows() end
function View:selectedMapLibraryEntry() return self.map_library_selected and self.map_library_visible_catalog[self.map_library_selected] or nil end
function View:setMapLibraryImportPending(value) self.map_library_import_pending=value==true; if self.layout then self:layoutMapLibrary(self.layout) end; return true end
function View:setColorMenuVisible(visible)
  self.color_menu_visible=visible==true
  if self.color_menu_visible and self.roller_settings_visible then self:hideRollerSettings() end
  if self.layout then return self:layoutColorMenu(self.layout) end
  return true
end
function View:renderColorOptions()
  local t=self.settings.theme; local font=self.layout and self.layout.color_toggle_font or 11
  for key,button in pairs(self.color_option_buttons or {}) do
    local enabled=self.color_options[key]~=false; local color=enabled and t.jade or t.muted
    button:setStyleSheet("background:"..(enabled and "#17231c" or "#111512")..";border:1px solid "..(enabled and "#385044" or t.border)..";border-radius:4px;color:"..color..";font-weight:700;")
    button:echo(View.withFont("<center>"..button.option_text.." &nbsp; <b>"..(enabled and "ON" or "OFF").."</b></center>",font))
  end
  for _,button in pairs(self.option_action_buttons or {}) do button:setStyleSheet("background:#151d18;border:1px solid "..t.border..";border-radius:4px;color:"..t.accent..";font-weight:700;"); button:echo(View.withFont("<center>"..button.option_text.."</center>",font)) end
  return true
end
local function viewCopy(value) if type(value)~="table" then return value end; local out={}; for key,item in pairs(value) do out[key]=viewCopy(item) end; return out end
function View:showRollerSettings(config)
  self:hideHelp(); self:hideMapSettings(); self:hideMapLibrary(); if self.feedback_visible then self:hideFeedback() end; if self.color_settings_visible then self:hideColorSettings() end; if self.support_visible then self:hideSupport() end; self.roller_draft=viewCopy(config or {}); self.roller_draft.min_stats=viewCopy(self.roller_draft.min_stats or {}); self.roller_settings_visible=true; self:setColorMenuVisible(false); self.roller_error=nil; self:renderRollerSettings(true); if self.layout then self:layoutRollerSettings(self.layout) end; return true
end
function View:showMapSettings(config)
  self:hideHelp(); self:hideRollerSettings(); self:hideMapLibrary(); if self.feedback_visible then self:hideFeedback() end; if self.color_settings_visible then self:hideColorSettings() end; if self.support_visible then self:hideSupport() end; self.map_settings_draft=viewCopy(config or {}); local t=self.map_settings_draft.transition_submaps or {}; for _,key in ipairs({"gate","portal","door","arch","path","other"}) do self.map_settings_draft[key]=t[key]~=false end
  self.map_settings_visible=true; self:setColorMenuVisible(false); self.map_settings_error=nil; self:renderMapSettings(true); if self.layout then self:layoutMapSettings(self.layout) end; return true
end
function View:hideMapSettings() self.map_settings_visible=false; self.map_settings_draft=nil; self.map_settings_error=nil; if self.layout then self:layoutMapSettings(self.layout) end; return true end
function View:renderMapSettings(populate)
  if not self.map_settings_draft then return true end; local t=self.settings.theme; local font=self.layout and math.max(10,(self.layout.body_font or 14)-3) or 11
  for _,key in ipairs(self.map_settings_field_order) do local f=self.map_settings_fields[key]; local value=self.map_settings_draft[key]; if key=="height_percent" then value=(tonumber(value) or .4)*100 end; f.caption:echo(View.withFont(f.label,font)); if populate and f.input.print then f.input:print(tostring(value or "")) end end
  for _,key in ipairs(self.map_settings_toggle_order) do local enabled=self.map_settings_draft[key]~=false; local b=self.map_settings_toggles[key]; b:setStyleSheet("background:"..(enabled and "#193024" or "#111512")..";border:1px solid "..(enabled and t.jade or t.border)..";border-radius:4px;color:"..(enabled and t.jade or t.muted)..";font-weight:700;"); b:echo(View.withFont("<center>"..b.option_text.." &nbsp; <b>"..(enabled and "ON" or "OFF").."</b></center>",font)) end
  if populate then if self.map_settings_area_name.print then self.map_settings_area_name:print(tostring(self.map_settings_draft.current_area_name or "")) end; if self.map_settings_subarea_name.print then self.map_settings_subarea_name:print(tostring(self.map_settings_draft.current_subarea_name or "")) end end
  self.map_settings_rename_area:echo(View.withFont("<center><b>NAME CURRENT AREA</b></center>",font)); self.map_settings_rename_subarea:echo(View.withFont("<center><b>NAME CURRENT SUBAREA</b></center>",font))
  self.map_settings_library:echo(View.withFont("<center><b>MAP LIBRARY…</b></center>",font)); self.map_settings_clear_current:echo(View.withFont("<center><b>DELETE CURRENT MAP…</b></center>",font)); self.map_settings_clear_all:echo(View.withFont("<center><b>"..(self.map_clear_pending and "CLICK AGAIN TO CLEAR ALL" or "WARNING: CLEAR ALL MAPS…").."</b></center>",font))
  self.map_settings_status:echo(View.withFont(self.map_settings_error and ("<span style='color:"..t.hp.."'><b>"..safeText(self.map_settings_error).."</b></span>") or safeText(self.map_settings_status_text or "Names are labels only; saved room numbers stay canonical."),font)); return true
end
function View:mapSettingsValues()
  local values={transition_submaps={}}; for _,key in ipairs(self.map_settings_field_order) do local f=self.map_settings_fields[key]; values[key]=f.input.getText and f.input:getText() or "" end; values.height_percent=(tonumber(values.height_percent) or 0)/100; values.enabled=self.map_settings_draft.enabled~=false; for _,key in ipairs({"gate","portal","door","arch","path","other"}) do values.transition_submaps[key]=self.map_settings_draft[key]~=false end; return values
end
function View:saveMapSettings()
  if not self.map_settings_callback then return nil,"map settings callback is unavailable" end
  for _,entry in ipairs({{"rename_area",self.map_settings_area_name,"current_area_name"},{"rename_subarea",self.map_settings_subarea_name,"current_subarea_name"}}) do
    local value=entry[2].getText and entry[2]:getText() or ""; value=tostring(value):match("^%s*(.-)%s*$")
    if value~="" and value~=tostring(self.map_settings_draft[entry[3]] or "") then
      if not self.map_settings_action_callback then self.map_settings_error="map naming is unavailable"; self:renderMapSettings(false); return nil,self.map_settings_error end
      local named,nameErr=self.map_settings_action_callback(entry[1],value)
      if not named then self.map_settings_error=nameErr; self:renderMapSettings(false); return nil,nameErr end
      self.map_settings_draft[entry[3]]=named
    end
  end
  local called,ok,err,config=pcall(self.map_settings_callback,self:mapSettingsValues()); if not called then err="Could not save mapper settings: "..tostring(ok); ok=nil end; if not ok then self.map_settings_error=err; self:renderMapSettings(false); return nil,err end; self:hideMapSettings(); return true,config
end
function View:hideRollerSettings() self.roller_settings_visible=false; self.roller_draft=nil; self.roller_error=nil; if self.layout then self:layoutRollerSettings(self.layout) end; return true end
function View:renderRollerSettings(populate)
  if not self.roller_draft then return true end; local t=self.settings.theme; local font=self.layout and math.max(10,(self.layout.body_font or 14)-3) or 11
  for _,key in ipairs(self.roller_field_order) do local field=self.roller_fields[key]; local value=key:match("^[A-Z]+$") and (self.roller_draft.min_stats or {})[key] or self.roller_draft[key]; if value==nil then value="off" end; field.caption:echo(View.withFont(field.label,font)); if populate and field.input.print then field.input:print(tostring(value)) end end
  for _,key in ipairs(self.roller_toggle_order) do local enabled=self.roller_draft[key]==true; local button=self.roller_toggles[key]; button:setStyleSheet("background:"..(enabled and "#193024" or "#111512")..";border:1px solid "..(enabled and t.jade or t.border)..";border-radius:4px;color:"..(enabled and t.jade or t.muted)..";font-weight:700;"); button:echo(View.withFont("<center>"..button.option_text.." &nbsp; <b>"..(enabled and "ON" or "OFF").."</b></center>",font)) end
  for _,key in ipairs(self.roller_action_order or {}) do local button=self.roller_action_buttons[key]; button:setStyleSheet("background:#151d18;border:1px solid "..t.border..";border-radius:4px;color:"..t.accent..";font-weight:700;"); button:echo(View.withFont("<center><b>"..button.option_text.."</b></center>",font)) end
  self.roller_status:echo(View.withFont(self.roller_error and ("<span style='color:"..t.hp.."'><b>"..safeText(self.roller_error).."</b></span>") or "Ranks: 1 Awful · 2 Poor · 3 Low · 4 Aver · 5 Fair · 6 Good · 7 Great",font))
  return true
end
function View:rollerSettingsValues()
  local values={min_stats={}}; for _,key in ipairs(self.roller_field_order) do local field=self.roller_fields[key]; local value=field.input.getText and field.input:getText() or ""; if key:match("^[A-Z]+$") then values.min_stats[key]=value else values[key]=value end end
  for _,key in ipairs(self.roller_toggle_order) do values[key]=self.roller_draft[key]==true end; return values
end
function View:saveRollerSettings()
  if not self.roller_settings_callback then self.roller_error="Save callback is unavailable"; self:renderRollerSettings(false); return nil,self.roller_error end
  local values=self:rollerSettingsValues(); local ok,err,config=self.roller_settings_callback(values)
  if not ok then self.roller_error=err or "Could not save settings"; self:renderRollerSettings(false); return nil,self.roller_error end
  self:hideRollerSettings(); return true,config
end
function View:setColorOptions(options)
  options=type(options)=="table" and options or {}
  for _,key in ipairs(self.color_option_order) do if options[key]~=nil then self.color_options[key]=options[key]~=false end end
  self.color_enabled=self.color_options.enabled~=false; self:setColorEnabled(self.color_enabled); self:renderColorOptions(); return true
end
function View:selectColorOption(key)
  if not self.color_option_buttons[key] then return nil,"unknown color option" end
  local wanted=not (self.color_options[key]~=false); local result
  if key=="enabled" and self.color_toggle_callback then result=self.color_toggle_callback(wanted)
  elseif self.color_options_callback then result=self.color_options_callback(key,wanted) end
  if type(result)=="boolean" then wanted=result end
  self.color_options[key]=wanted; if key=="enabled" then self:setColorEnabled(wanted) else self:renderColorOptions() end
  self:setColorMenuVisible(false); return wanted
end
function View:setColorEnabled(enabled)
  self.color_enabled=enabled~=false
  self.color_options.enabled=self.color_enabled
  local t=self.settings.theme; local color=self.color_enabled and t.jade or t.muted
  self.color_toggle:setStyleSheet("background:"..(self.color_enabled and "#17231c" or "#111512")..";border:1px solid "..color..";border-radius:4px;color:"..color..";font-weight:700;")
  local font=self.layout and self.layout.color_toggle_font or 11
  self.color_toggle:echo(View.withFont("<center><b>OPTIONS ▾</b></center>",font)); self:renderColorOptions()
  return true
end
function View:setMapZoomCallback(callback) self.map_zoom_callback=type(callback)=="function" and callback or nil; return true end
function View:setMapClearAllCallback(callback) self.map_clear_all_callback=type(callback)=="function" and callback or nil; return true end
function View:setMapClearPending(pending)
  self.map_clear_pending=pending==true
  local font=self.layout and self.layout.lower_utility_font or 12
  self.map_clear_all:echo(View.withFont("<center><b>MAP SETTINGS</b></center>",font))
  if self.map_settings_draft then self:renderMapSettings(false) end
  return true
end
function View:centerMap(roomID)
  if not self.map_center_callback then return nil,"map center callback is unavailable" end
  return self.map_center_callback(roomID)
end
function View:renderNavigation(exits)
  if not self.layout or self.layout.mode=="compact" then return end
  local t=self.settings.theme; self.exit_available=Navigation.availability(exits)
  for _,entry in ipairs(self.direction_buttons) do local active=self.exit_available[entry.direction.key]; entry.label:setStyleSheet("background:"..(active and "#193024" or "rgba(16,23,19,0.28)")..";border:1px solid "..(active and "#5d9b71" or "#273029")..";border-radius:5px;color:"..(active and "#b8efc2" or "#536058")..";font-weight:700;"); entry.label:echo(View.withFont("<center><b>"..entry.direction.label.."</b></center>",self.layout.lower_compass_font)) end
  for _,entry in ipairs(self.utility_buttons) do entry.label:setStyleSheet("background:#17231c;border:1px solid #385044;border-radius:5px;color:"..t.jade..";font-weight:700;"); entry.label:echo(View.withFont("<center><b>"..entry.utility.label.."</b></center>",self.layout.lower_utility_font)) end
end
function View:updateRoundtime(remaining,total)
  remaining=tonumber(remaining) or 0; if remaining<0 then remaining=0 end
  if remaining<=0 then
    self.roundtime_remaining=0; self.roundtime_total=1; self.roundtime_bar:setValue(0,1,"Roundtime  READY")
  else
    total=tonumber(total)
    if not total or total<=0 then total=math.max(remaining,tonumber(self.roundtime_total) or 0) end
    total=math.max(remaining,total,1); self.roundtime_remaining=remaining; self.roundtime_total=total
    self.roundtime_bar:setValue(remaining,total,"Roundtime  "..tostring(math.ceil(remaining)).."s")
  end
  local isActive=self.roundtime_remaining>0
  if self.layout and self.layout.mode~="compact" then self.roundtime_bar:show(); self.roundtime_bar:raise() end
  return isActive
end
function View:renderInventory(s)
  local t=self.settings.theme; local layout=self.layout; if not layout or layout.mode=="compact" then return end
  local inventory=s.inventory or {}; local v=s.vitals or {}; local carry=v.carry or {}; local signature={tostring(inventory.total_weight or ""),tostring(v.gold or 0),tostring(v.silver or 0),tostring(carry.current or ""),tostring(carry.maximum or ""),tostring(carry.percent or "")}
  for _,item in ipairs(inventory.items or {}) do signature[#signature+1]=tostring(item.name or "").."\31"..tostring(item.weight or "") end
  signature=table.concat(signature,"\30"); if signature==self.inventory_signature then return end; self.inventory_signature=signature
  self.inventory_title:echo("<b>INVENTORY</b>")
  local lines={}; for _,item in ipairs(inventory.items or {}) do lines[#lines+1]=esc(item.name or "").."  <span style='color:"..t.muted.."'>"..esc(item.weight or "").." lb</span>" end
  self.inventory_content:echo("<div style='white-space:nowrap'>"..table.concat(lines,"<br>").."</div>"); self.inventory_content:move(0,0); self.inventory_content:resize(self.inventory_content_width or self.list_content_width or 1,math.max(layout.list_row_height*5,#lines*layout.list_row_height)); self.inventory_content:show()
  self.inventory_footer:echo("<span style='color:"..(t.gold or "#e0b84f").."'><b>"..esc(v.gold or 0).."gp</b></span> &nbsp; <span style='color:"..(t.silver or "#c0c0c0").."'><b>"..esc(v.silver or 0).."sp</b></span><br>Carry <b>"..esc(carry.current or 0).." / "..esc(carry.maximum or 0).." / </b><span style='color:"..t.muted.."'><b>"..esc(carry.percent or 0).."%</b></span>")
end
function View:renderRunes(s)
  local layout=self.layout; if not layout or layout.mode=="compact" then return end
  local runes=s.runes or {}; local items=runes.items or {}; local signature={}
  for _,rune in ipairs(items) do signature[#signature+1]=tostring(rune.name or rune.rune or rune.label or "").."\31"..tostring(rune.remaining or rune.remain or rune.weaves or rune.count or "") end
  signature=table.concat(signature,"\30"); if signature==self.runes_signature then return end; self.runes_signature=signature
  self.runes_title:echo("<b>RUNES</b>")
  local lines={}; for _,rune in ipairs(items) do
    local name=esc(rune.name or rune.rune or rune.label or "—"); local amount=rune.remaining or rune.remain or rune.weaves or rune.count
    lines[#lines+1]=name..(amount~=nil and " <span style='color:"..self.settings.theme.muted.."'>- "..esc(amount).." weaves remain</span>" or "")
  end
  self.runes_content:echo("<div style='white-space:nowrap'>"..table.concat(lines,"<br>").."</div>"); self.runes_content:move(0,0); self.runes_content:resize(self.runes_content_width or self.list_content_width or 1,math.max(layout.list_row_height*5,#lines*layout.list_row_height)); self.runes_content:show()
end
function View:renderSkills(s)
  local layout=self.layout; if not layout or layout.mode=="compact" then return end
  local nameWidth=self.skill_name_width or 22; local signature={tostring(nameWidth)}; local items=(s.skills or {}).items or {}
  for _,skill in ipairs(items) do signature[#signature+1]=tostring(skill.name or "").."\31"..tostring(skill.level or "").."\31"..tostring(skill.remain or "") end
  signature=table.concat(signature,"\30"); if signature==self.skills_signature then return end; self.skills_signature=signature
  local function fixed(value) return (esc(value):gsub(" ","&nbsp;")) end
  self.skills_title:echo("<b>"..fixed(View.skillHeader(nameWidth,self.skill_column_gaps,self.skill_level_width,self.skill_use_width)).."</b>")
  local lines={}; for _,skill in ipairs(items) do lines[#lines+1]=fixed(View.skillLine(skill,nameWidth,self.skill_column_gaps,self.skill_level_width,self.skill_use_width)) end
  self.skills_content:echo("<div style='white-space:nowrap'>"..table.concat(lines,"<br>").."</div>"); self.skills_content:move(0,0); self.skills_content:resize(self.skills_content_width or self.list_content_width or 1,math.max(layout.list_row_height*5,#lines*layout.list_row_height)); self.skills_content:show()
end
function View:renderChat(entries,categories,activeFilter,savedScroll)
  entries=type(entries)=="table" and entries or {}; categories=type(categories)=="table" and categories or {}
  local state=savedScroll or chatScroll(self.chat_output,self.chat_line_ranges); local first=math.max(1,#entries-999)
  self.chat_entries={}; for index=first,#entries do self.chat_entries[#self.chat_entries+1]=entries[index] end
  self.chat_categories={}; for index,value in ipairs(categories) do self.chat_categories[index]=value end
  self.chat_active_filter=tostring(activeFilter or "ALL"):upper()
  self:renderChatTabs(self.chat_categories,self.chat_active_filter)
  self.chat_output:clear()
  local chatSettings=self.settings.chat or {}
  self.chat_line_ranges={}
  for index,entry in ipairs(self.chat_entries) do
    local okBefore,before=pcall(function() return self.chat_output:getLastLineNumber() end)
    local prefix,message=View.chatLine(entry,self.settings.theme,chatSettings.timestamps)
    self.chat_output:hecho(prefix)
    self.chat_output:echo(message)
    local okAfter,after=pcall(function() return self.chat_output:getLastLineNumber() end)
    before=okBefore and tonumber(before) or 0; after=okAfter and tonumber(after) or before
    self.chat_line_ranges[index]={entry=entry,first=before+1,last=math.max(before+1,after)}
  end
  restoreChatScroll(self.chat_output,state,self.chat_line_ranges)
  return true
end
local function chatFontWidth(output)
  if type(output.calcFontSize)=="function" then
    local ok,width=pcall(output.calcFontSize,output)
    width=ok and tonumber(width) or nil
    if width and width>0 then return width end
  end
  local calculator=rawget(_G,"calcFontSize")
  if type(calculator)=="function" and output.name then
    local ok,width=pcall(calculator,output.name)
    width=ok and tonumber(width) or nil
    if width and width>0 then return width end
  end
end
local function chatConsoleWidth(output,layout)
  if type(output.get_width)=="function" then
    local ok,width=pcall(output.get_width,output)
    width=ok and tonumber(width) or nil
    if width and width>0 then return width end
  end
  return math.max(1,(tonumber(layout.chat_width) or 1)-(2*(tonumber(layout.chat_padding) or 0)))
end
local function liveChatColumns(output,layout)
  local fontWidth=chatFontWidth(output)
  if not fontWidth then return math.max(1,math.floor(tonumber(layout.chat_wrap_columns) or 1)) end
  local allowance=output.scrollBar==false and 0 or (tonumber(layout.chat_scrollbar_allowance) or 15)
  local width=math.max(1,chatConsoleWidth(output,layout)-allowance)
  return math.max(1,math.floor(width/fontWidth)),fontWidth
end
function View:applyChatWrap(layout)
  layout=layout or self.layout or {}; local output=self.chat_output
  local font=math.max(1,math.floor(tonumber(layout.chat_font) or 13))
  local previousState=chatScroll(output,self.chat_line_ranges)
  pcall(function() output:setFontSize(font) end)
  local columns,fontWidth=liveChatColumns(output,layout)
  local changed=self.chat_wrap_columns~=columns or self.chat_font~=font
  local state=changed and previousState or nil
  local ok,applied,why=pcall(function() return output:setWrap(columns) end)
  if not ok then return nil,tostring(applied) end
  if applied==false or (applied==nil and why~=nil) then return nil,tostring(why or "could not apply chat wrap") end
  self.chat_wrap_columns=columns; self.chat_font=font; self.chat_character_width=fontWidth
  if changed then
    if self.chat_entries then self:renderChat(self.chat_entries,self.chat_categories,self.chat_active_filter,state)
    else restoreChatScroll(output,state,self.chat_line_ranges) end
  end
  return true
end
function View:update(s)
  self.last_state=s; local t=self.settings.theme; local v=s.vitals; local layout=self.layout or {mode="wide",heading_font=20}; local ready=function(x) return x and "<span style='color:"..t.jade.."'><b>READY</b></span>" or "<span style='color:"..t.hp.."'><b>NOT READY</b></span>" end
  self.header:echo(View.headerContent(layout,t,s.character.full_name)); self:updateClock(s.clock); self.attribute_strip:echo(View.attributeStripContent(s.attributes,t,layout))
  self.identity:echo(View.identityContent(s.character,t,layout))
  self.equipment:echo(View.equipmentContent(v,s.equipment.items,t,layout))
  self:updateRoundtime(v.roundtime)
  local activeBars=2+(v.psi.visible and 1 or 0)+(v.web.visible and 1 or 0)
  local shortLabels=(tonumber(layout.console_width) or 1200)/activeBars<150
  self.hp:setValue(v.hp.current,math.max(v.hp.maximum,1),(shortLabels and "HP  " or "Health  ")..v.hp.current.." / "..v.hp.maximum); self.fatigue:setValue(v.fatigue.current,math.max(v.fatigue.maximum,1),(shortLabels and "FAT  " or "Fatigue  ")..v.fatigue.current.." / "..v.fatigue.maximum)
  if v.psi.visible then self.psi:setValue(v.psi.current,math.max(v.psi.maximum,1),"PSI  "..v.psi.current.." / "..v.psi.maximum) end; if v.web.visible then self.web:setValue(v.web.current,math.max(v.web.maximum,1),"Web  "..v.web.current.." / "..v.web.maximum) end
  self.room:echo(View.withFont("<span style='color:"..t.accent..";font-size:"..layout.lower_heading_font.."px'><b>"..esc(s.room.name).."</b></span><br><span style='color:"..t.muted.."'>Room "..esc(s.room.num or "—").." · Area "..esc(s.room.area or "—").."</span><br><br>"..esc(s.room.environment).."<br>Players &nbsp; <b>"..#s.room.players.."</b><br>Flags &nbsp; "..esc(table.concat(s.room.flags,", ")),layout.lower_body_font))
  self.compact:echo(View.withFont("<span style='color:"..(t.gold or "#e0b84f").."'><b>"..esc(v.gold or 0).."gp</b></span> &nbsp; <span style='color:"..(t.silver or "#c0c0c0").."'><b>"..esc(v.silver or 0).."sp</b></span><br>Carry <b>"..esc(v.carry.current or 0).." / "..esc(v.carry.maximum or 0).." / "..esc(v.carry.percent or 0).."%</b><br><span style='color:"..t.accent.."'>"..esc(s.room.name).."</span> &nbsp; EXITS "..esc(table.concat(s.room.exits,", ")),layout.body_font))
  self.bottom:echo(View.withFont("EXITS &nbsp; <b>"..esc(table.concat(s.room.exits,", ")).."</b> &nbsp;&nbsp; | &nbsp;&nbsp; CARRY &nbsp; <b>"..v.carry.current.." / "..v.carry.maximum.."</b> &nbsp;&nbsp; | &nbsp;&nbsp; ROUND &nbsp; <b>"..(v.roundtime==0 and "READY" or v.roundtime).."</b>",layout.small_font))
  if self.layout then self:applyLayout(self.layout); self.details:echo(View.detailsContent(s.combat,s.attributes,t,self.layout,v)); self:renderInventory(s); self:renderRunes(s); self:renderSkills(s); self:renderNavigation(s.room.exits) end
end
function View:updateClock(clock)
  local layout=self.layout or {mode="wide",body_font=16,heading_font=20}; local t=self.settings.theme
  self.clock_header:echo(View.clockContent(layout,t,clock))
  return true
end
function View:delete() if self.root then self.root:delete(); self.root=nil end end
return View
