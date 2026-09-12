local View=require("view")
local VIEW_CONTRACT=string.rep("a",64)
local SETTINGS_CONTRACT=string.rep("b",64)
test("rich text receives an explicit responsive font size",function()
  eq(View.withFont("Status",20),"<span style='font-size:20px'>Status</span>")
end)
test("portable list font selection chooses an available fixed-width family",function()
  eq(View.monospaceFont({Menlo=true}),"Menlo")
  eq(View.monospaceFont({Consolas=true,["Courier New"]=true}),"Consolas")
  eq(View.monospaceFont({}),"Courier New")
end)

test("identity and right rail content remain separate",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  local character={full_name="Test Tester",race="Monitanian",class="Fighter",alignment="entropy"}
  local identity=View.identityContent(character,theme,layout)
  local equipment=View.equipmentContent({weapon_readied=true,shield_readied=false,gold=3,silver=9},theme,layout)
  eq(identity:find("Test Tester",1,true)~=nil,true); eq(identity:find("Monitanian",1,true)~=nil,true)
  eq(identity:find("Fighter",1,true)~=nil,true); eq(identity:find("Entropic",1,true)~=nil,true)
  eq(identity:find("EQUIPMENT",1,true)==nil,true); eq(equipment:find("Test Tester",1,true)==nil,true)
  eq(equipment:find("EQUIPMENT",1,true)~=nil,true); eq(equipment:find("WEALTH",1,true)==nil,true)
end)
test("identity places orderly beside religious balance",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  local identity=View.identityContent({full_name="Muthulas Vaelith",race="Leuian",class="Cleric",alignment="order",religious_balance="Balanced"},theme,layout)
  eq(identity:find("Balanced · Orderly",1,true)~=nil,true); eq(identity:find(">order</span>",1,true),nil)
end)
test("identity displays normalized alignment names",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  for raw,display in pairs({order="Orderly",entropy="Entropic",chaos="Chaotic"}) do
    local identity=View.identityContent({full_name="Test",race="Human",class="Fighter",alignment=raw,religious_balance="Balanced"},theme,layout)
    eq(identity:find("Balanced · "..display,1,true)~=nil,true)
  end
end)
test("identity displays food and water while vital bars remain resource-only",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  local identity=View.identityContent({full_name="Test",race="Dragon",class="Fighter"},theme,layout,{hunger={status="ravenous"},thirst={status="parched"}})
  eq(identity:find("Food:",1,true)~=nil,true); eq(identity:find("Ravenous",1,true)~=nil,true)
  eq(identity:find("Water:",1,true)~=nil,true); eq(identity:find("Parched",1,true)~=nil,true)
end)
test("dragon identity displays its lifecycle stage instead of an empty class",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  for _,stage in ipairs({"1st stage","2nd stage","3rd stage","4th stage"}) do
    local identity=View.identityContent({full_name="Test",race="Dragon",class="None",physical={life_stage=stage}},theme,layout)
    local expected=stage:gsub(" stage$"," Stage")
    eq(identity:find("Dragon · "..expected,1,true)~=nil,true); eq(identity:find("Dragon · None",1,true),nil)
  end
end)
test("equipment uses its smaller dedicated font",function()
  local html=View.equipmentContent({weapon_readied=true,shield_readied=false},{},{accent="#da5",jade="#7b8"},{body_font=20,equipment_font=15})
  eq(html:find("font%-size:15px")~=nil,true)
  eq(html:find("<br><br>",1,true),nil)
end)

test("visible header removes protocol wording",function()
  local h=View.headerContent({mode="wide",body_font=20,heading_font=25},{accent="#d8ae53",jade="#72bd82",text="#fff",muted="#777"},"Test Tester")
  eq(h:find("GMCP",1,true),nil); eq(h:find("LIVE",1,true),nil); eq(h:find("DRAGONS GATE",1,true)~=nil,true); eq(h:find("Real Time:",1,true),nil)
end)
test("header clock uses the responsive clock-specific font",function()
  local h=View.clockContent({mode="medium",body_font=16,heading_font=21,header_clock_font=10},{accent="#da5",jade="#7b8",text="#fff",muted="#777"},{real_time="12:41:06 AM",game_time="3:24 AM",period="Night"})
  eq(h:find("font%-size:10px")~=nil,true)
  eq(h:find("Real Time:",1,true)~=nil,true); eq(h:find("Game Time:",1,true)~=nil,true); eq(h:find("Night",1,true)~=nil,true)
end)
test("inventory truncates without splitting rows",function()
  local rows=View.inventoryRows({{name="One",weight=1},{name="Two",weight=2},{name="Three",weight=3}},2)
  eq(#rows,2); eq(rows[1].name,"One"); eq(rows[2].label,"+2 more"); eq(rows[2].overflow,2)
end)
test("inventory footer renders currency and carry capacity without redundant total",function()
  local theme={accent="#d8ae53",muted="#91a098",gold="#e0b84f",silver="#c0c0c0"}
  local html=View.inventoryContent({items={},total_weight=0},{gold=12,silver=34,carry={current=25.7,maximum=255,percent=10.1}},theme,{inventory_font=18},4)
  eq(html:find("WEALTH",1,true),nil)
  eq(html:find("Total",1,true),nil); eq(html:find("Carry <b>25.7/255</b>",1,true)~=nil,true); eq(html:find("10.1%",1,true)~=nil,true)
  eq(html:find("12gp",1,true)~=nil,true); eq(html:find("34sp",1,true)~=nil,true)
  eq(html:find("color:#e0b84f",1,true)~=nil,true); eq(html:find("color:#c0c0c0",1,true)~=nil,true)
  eq(html:find("12gp",1,true)<html:find("34sp",1,true),true)
end)
test("narrow inventory footers wrap complete carry data instead of clipping it",function()
  local lines,tooltip=View.inventoryFooterLines({gold=12345,silver=98765,carry={current=174.4,maximum=354,percent=49.3}},{gold="#gold",silver="#silver",muted="#muted"},12)
  local html=table.concat(lines,"<br>")
  eq(html:find("12345gp",1,true)~=nil,true); eq(html:find("98765sp",1,true)~=nil,true)
  eq(html:find("174.4/354",1,true)~=nil,true); eq(html:find("49.3%",1,true)~=nil,true)
  eq(tooltip,"Carry: 174.4 / 354 / 49.3%")
end)
test("inventory content width follows the longest retained item",function()
  eq(View.inventoryRequiredColumns({{name="Torch",weight=.1}}),36)
  eq(View.inventoryRequiredColumns({{name=string.rep("x",80),weight=12.3}})>80,true)
  eq(View.inventoryRequiredColumns({{name=string.rep("x",300),weight=1}}),160)
end)
test("skill rows use stable aligned name level and remaining columns",function()
  local header=View.skillHeader(24); local short=View.skillLine({name="Biting",level=4,remain=105},24); local long=View.skillLine({name="Identify Armor Quality",level=1,remain=7},24)
  eq(header:find("LVL",1,true)~=nil,true); eq(header:find("USES",1,true)~=nil,true)
  eq(short:find("4",1,true),long:find("1",1,true)); eq(short:find("105",1,true)+2,long:find("7",1,true))
end)
test("skill display names abbreviate identify categories without changing source data",function()
  local cases={
    {"Identify Gems/Minerals","ID Gems"},
    {"Identify Weapon Quality","ID Weapon"},
    {"Identify Armor Quality","ID Armor"},
    {"Identify Magick","ID Magick"},
  }
  for _,case in ipairs(cases) do
    local skill={name=case[1],level=3,remain=100}
    local row=View.skillLine(skill,20,2,3,4)
    eq(row:sub(1,20):match("^%s*(.-)%s*$"),case[2])
    eq(skill.name,case[1])
  end
end)
test("identity details render while attributes move to the top strip",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  local identity=View.identityContent({full_name="Test Tester",race="Monitanian",class="Fighter",alignment="entropy",physical={age=28,sex="Male",height="6'10\""}},theme,layout)
  local details=View.detailsContent({body_armor=4,or_rating=18,dr=70,stance="Aggressive"},{STR="Good",APP="Fair"},theme,layout,{roundtime=8,position=1})
  local equipment=View.equipmentContent({weapon_readied=true,shield_readied=true},{"A spear","A shield"},theme,layout)
  local strip=View.attributeStripContent({STR="Good",APP="Fair"},theme,{attribute_strip_font=12})
  eq(identity:find("28",1,true)~=nil,true); eq(details:find("Aggressive",1,true)~=nil,true); eq(details:find("STR",1,true),nil)
  eq(details:find("COMBAT",1,true)~=nil,true); eq(details:find("CHARACTER",1,true),nil)
  eq(details:find("Roundtime",1,true)~=nil,true); eq(details:find("Position",1,true)~=nil,true)
  eq(strip:find("STR",1,true)~=nil,true); eq(strip:find("Good",1,true)~=nil,true); eq(strip:find("APP",1,true)~=nil,true); eq(strip:find("Fair",1,true)~=nil,true)
  eq(equipment:find("A spear",1,true),nil); eq(equipment:find("Weapon",1,true)~=nil,true); eq(equipment:find("Shield",1,true)~=nil,true)
end)
test("identity includes compact religion information",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  local identity=View.identityContent({full_name="Test Tester",race="Monitanian",class="Fighter",alignment="entropy",religion="Novitiate",deity="Unknown",favors=57000,religious_balance="Balanced"},theme,layout)
  eq(identity:find("Novitiate · Unknown",1,true)~=nil,true); eq(identity:find("Favors: 57,000",1,true)~=nil,true); eq(identity:find("Unknown (57,000 favors)",1,true),nil); eq(identity:find("Balanced · Entropic",1,true)~=nil,true)
end)
test("right rail details keep combat information without attributes",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25,details_columns=2}
  local details=View.detailsContent({body_armor=4,or_rating=18,dr=70,stance="Aggressive"},{STR="Good",INT="Low",WIS="Fair"},theme,layout)
  eq(details:find("Stance <b>Aggressive</b>",1,true)~=nil,true)
  eq(details:find("STR",1,true),nil); eq(details:find("INT",1,true),nil); eq(details:find("WIS",1,true),nil)
end)
test("right rail cards can be raised above their shared background",function()
  local raised=0; local card={raise=function() raised=raised+1 end}
  View.raiseCards({card,card,card}); eq(raised,3)
end)
test("combat card renders ready roundtime and position without a status heading",function()
  local html=View.detailsContent({},nil,{accent="#d8ae53"},{inventory_font=18},{roundtime=0,position=1})
  eq(html:find("COMBAT",1,true)~=nil,true); eq(html:find("STATUS",1,true),nil)
  eq(html:find("Roundtime",1,true)~=nil,true); eq(html:find("READY",1,true)~=nil,true); eq(html:find("Position",1,true)~=nil,true)
end)
test("combat pairs stance with OR and roundtime with DR on right",function()
  local html=View.detailsContent({or_rating=25,dr=115,stance="Normal"},nil,{accent="#d8ae53"},{inventory_font=18},{roundtime=0,position=0})
  eq(html:find("Stance <b>Normal</b></td><td align='right'>OR <b>25</b>",1,true)~=nil,true)
  eq(html:find("Roundtime <b>READY</b></td><td align='right'>DR <b>115</b>",1,true)~=nil,true)
  eq(html:find("font-size:16px",1,true)~=nil,true)
end)
test("combat uses one compact grid and aligns posture beneath DR",function()
  local html=View.detailsContent({body_armor=4,or_rating=25,dr=115,stance="Normal"},nil,{accent="#d8ae53"},{inventory_font=18},{roundtime=0,position=-1,standing=true})
  eq(html:find("Armor <b>4%</b></td><td align='right'>&nbsp;</td></tr><tr><td>Stance",1,true)~=nil,true)
  eq(html:find("Roundtime <b>READY</b></td><td align='right'>DR <b>115</b>",1,true)~=nil,true)
  eq(html:find("Position <b>-1</b></td><td align='right'><b>Standing</b>",1,true)~=nil,true)
  eq(html:find("<br><br>",1,true),nil)
end)
test("combat position displays posture with sitting taking defensive precedence",function()
  local theme={accent="#d8ae53"}; local layout={inventory_font=18}
  local standing=View.detailsContent({},nil,theme,layout,{roundtime=0,position=0,standing=true,sitting=false})
  local sitting=View.detailsContent({},nil,theme,layout,{roundtime=0,position=-1,standing=true,sitting=true})
  eq(standing:find("Position",1,true)~=nil,true); eq(standing:find("Standing",1,true)~=nil,true)
  eq(sitting:find("Sitting",1,true)~=nil,true); eq(sitting:find("Standing",1,true),nil)
end)

local function fakeGeyser(glyphWidth,scrollbarWidth,measureFails)
  glyphWidth=tonumber(glyphWidth) or 6
  local function widget(cons,parent,kind)
    local item={name=cons.name,parent=parent,kind=kind,visible=true,echoes={},currentScroll=0,lastLine=0}
    function item:setStyleSheet(value) self.style=value end
    function item:move(x,y) self.x=x; self.y=y end
    function item:resize(width,height) self.width=width; self.height=height end
    function item:get_width() return self.width end
    function item:show() self.visible=true end
    function item:hide() self.visible=false end
    function item:raise() self.raised=true end
    function item:delete() self.deleted=true end
    function item:setClickCallback(callback) self.click=callback end
    function item:setAction(callback) self.action=callback end
    function item:setToolTip(value) self.tooltip=value end
    function item:print(value) self.text=tostring(value) end
    function item:getText() return self.text or "" end
    function item:echo(value)
      if self.kind=="console" then
        self.echoes[#self.echoes+1]=value
        local first=self.lastLine+1
        local columns=math.max(1,tonumber(self.wrap) or 80)
        local rows=math.max(1,math.ceil(#tostring(value)/columns))
        self.lastLine=self.lastLine+rows
        self.renderedEntries=self.renderedEntries or {}
        self.renderedEntries[#self.renderedEntries+1]={first=first,last=self.lastLine}
      else self.message=value end
    end
    function item:hecho(value)
      self.hechoes=self.hechoes or {}
      self.hechoes[#self.hechoes+1]=value
    end
    function item:clear() self.clearCalls=(self.clearCalls or 0)+1; self.echoes={}; self.hechoes={}; self.lastLine=0; self.renderedEntries={} end
    function item:setWrap(value) self.wrap=value; return true end
    function item:setFontSize(value) self.fontSize=value end
    function item:setFont(value) self.font=value end
    function item:getSizeHint()
      if measureFails then error("size hint unavailable") end
      local message=tostring(self.message or "")
      local _,rows=message:gsub("<br>","")
      local longest=0
      for line in (message.."<br>"):gmatch("(.-)<br>") do
        local rendered=line:gsub("<[^>]+>","")
        longest=math.max(longest,#rendered)
      end
      return math.ceil(longest*glyphWidth),math.ceil((self.fontSize or 8)*1.6)*(rows+1)
    end
    function item:enableScrollBar() self.scrollBar=true end
    function item:disableHorizontalScrollBar() self.horizontalScrollBar=false end
    function item:getScroll() return self.currentScroll end
    function item:getLastLineNumber() return self.lastLine end
    function item:scrollTo(line) self.scrollCalls=self.scrollCalls or {}; self.scrollCalls[#self.scrollCalls+1]=line==nil and "bottom" or line; self.currentScroll=line or self.lastLine end
    function item:setValue(current,maximum,text) self.value={current,maximum,text} end
    return item
  end
  local geyser={}
  geyser.Container={new=function(_,cons,parent) return widget(cons,parent,"container") end}
  geyser.ScrollBox={new=function(_,cons,parent) return widget(cons,parent,"scrollbox") end}
  geyser.Label={new=function(_,cons,parent) return widget(cons,parent,"label") end}
  geyser.MiniConsole={new=function(_,cons,parent) return widget(cons,parent,"console") end}
  geyser.CommandLine={new=function(_,cons,parent) return widget(cons,parent,"commandline") end}
  geyser.Mapper={new=function(_,cons,parent) return widget(cons,parent,"mapper") end}
  geyser.Gauge={new=function(_,cons,parent)
    local item=widget(cons,parent,"gauge"); item.front=widget({},item,"label"); item.back=widget({},item,"label"); item.text=widget({},item,"label"); return item
  end}
  return geyser
end

local function chatView(glyphWidth,scrollbarWidth,measureFails)
  local original=Geyser; Geyser=fakeGeyser(glyphWidth,scrollbarWidth,measureFails)
  local view=View.new({version="0.3.30",view_contract=VIEW_CONTRACT,view_settings_contract=SETTINGS_CONTRACT,theme={background="#080b0a",panel="#0d1210",border="#423825",text="#d7d0bf",muted="#75857c",accent="#e0b56c",jade="#79b386",hp="#ba5147",fatigue="#8bad4e"},chat={timestamps=true}})
  Geyser=original
  return view
end

test("view has no standalone wealth widget",function()
  local view=chatView(); eq(view.wealth,nil)
end)
test("preserved view reuse closes transient panels and drops controller callbacks",function()
  local view=chatView(); view.options_action_callback=function() end; view.map_settings_action_callback=function() end; view.feedback_sending=true
  view.color_menu_visible=true; view.color_menu:show(); view.support_visible=true; view.support_panel:show()
  local settings={view_contract=VIEW_CONTRACT,view_settings_contract=SETTINGS_CONTRACT,theme=view.settings.theme,chat=view.settings.chat}; eq(view:prepareForReuse(settings),true)
  eq(view.settings,settings); eq(view.color_menu_visible,false); eq(view.color_menu.visible,false); eq(view.support_visible,false); eq(view.support_panel.visible,false)
  eq(view.options_action_callback,nil); eq(view.map_settings_action_callback,nil); eq(view.feedback_sending,false)
end)

test("fatigue gauge uses its configured fill color without changing health",function()
  local view=chatView()
  eq(view.fatigue.front.style:find("background:#8bad4e",1,true)~=nil,true)
  eq(view.hp.front.style:find("background:#ba5147",1,true)~=nil,true)
end)

test("header owns a responsive top-left options button above the brand",function()
  local view=chatView()
  for _,size in ipairs({{760,700},{800,700},{1200,800},{1920,1080}}) do
    local layout=require("layout").compute(size[1],size[2]); view:applyLayout(layout)
    eq(view.color_toggle.visible,true); eq(view.color_toggle.x>=0,true)
    eq(view.color_toggle.x+view.color_toggle.width<=size[1],true)
    eq(view.color_toggle.y+view.color_toggle.height<=layout.header_height,true)
    eq(view.color_toggle.x,0)
    eq(view.color_toggle.y,4)
    eq(view.color_toggle.y+view.color_toggle.height<layout.header_height,true)
    eq(view.version_label.visible,true); eq(view.version_label.message:find("v0.3.30",1,true)~=nil,true)
    eq(view.version_label.x>=view.color_toggle.x+view.color_toggle.width,true)
    eq(view.version_label.x+view.version_label.width<=size[1],true)
    eq(view.version_label.y+view.version_label.height<=layout.header_height,true)
  end
  eq(view.color_toggle.tooltip,"Open DGHUD options")
  eq(view.version_label.tooltip,"Installed DGHUD version")
end)

test("preserved pre-version view creates and repaints the installed version label",function()
  local view=chatView(); view.version_label=nil
  local settings={version="0.3.31",view_contract=VIEW_CONTRACT,view_settings_contract=SETTINGS_CONTRACT,theme=view.settings.theme,chat=view.settings.chat}
  assert(view:prepareForReuse(settings)); view:applyLayout(require("layout").compute(760,700))
  eq(view.version_label.message:find("v0.3.31",1,true)~=nil,true)
  local versionText=view.version_label.message; view:setColorEnabled(false); eq(view.version_label.message,versionText)
end)
test("damaged preserved version label is recreated before layout",function()
  local view=chatView(); local damaged=view.version_label; damaged.setStyleSheet=nil
  local replacement=view:ensureVersionLabel()
  eq(replacement~=damaged,true); eq(damaged.deleted,true); eq(type(replacement.setStyleSheet),"function"); eq(type(replacement.raise),"function")
end)

test("color options button renders overall enabled and disabled states",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1000,700))
  view:setColorEnabled(true); eq(view.color_enabled,true); eq(view.color_toggle.message:find("OPTIONS",1,true)~=nil,true); eq(view.color_toggle.style:find("#79b386",1,true)~=nil,true)
  view:setColorEnabled(false); eq(view.color_enabled,false); eq(view.color_toggle.message:find("OPTIONS",1,true)~=nil,true); eq(view.color_toggle.style:find("#75857c",1,true)~=nil,true)
end)

test("color options menu exposes current and future feature toggles",function()
  local view=chatView(); local calls={}
  view:setColorToggleCallback(function() calls[#calls+1]={key="enabled"}; return false end)
  view:setColorOptionsCallback(function(key,value) calls[#calls+1]={key=key,value=value}; return value end)
  view:setColorOptions({enabled=true,room=true,exits=false,currency=true,races=true,classes=true,portal=true,attack=true,damage=true,danger=true,recovery=true,upkeep=true,spell=true,discovery=true,illumination=true})
  view:applyLayout(require("layout").compute(1200,800)); view.color_toggle.click()
  eq(view.color_menu_visible,true); eq(view.color_menu.visible,true); eq(view.color_menu_scrim.visible,true)
  eq(#view.option_action_order,9); view:setAutoUpdateEnabled(false); eq(view.option_action_buttons.auto_update.option_text,"AUTOMATIC UPDATES: OFF"); view:setAutoUpdateEnabled(true); eq(view.option_action_buttons.auto_update.option_text,"AUTOMATIC UPDATES: ON"); eq(view:setDisplayTextSize("small"),"small"); eq(view.option_action_buttons.text_size.option_text,"HUD TEXT: SMALL"); view.option_action_buttons.color_settings.click(); eq(view.color_settings_visible,true)
  for _,key in ipairs(view.color_option_order) do eq(view.color_option_buttons[key].visible,true) end
  eq(view.color_option_buttons.room.message:find("ROOM TITLES",1,true)~=nil,true)
  eq(view.color_option_buttons.exits.message:find("OFF",1,true)~=nil,true)
  eq(view.color_option_buttons.damage.message:find("DAMAGE TO YOU",1,true)~=nil,true)
  eq(view.color_option_buttons.races.message:find("RACES",1,true)~=nil,true); eq(view.color_option_buttons.classes.message:find("CLASSES",1,true)~=nil,true)
  eq(view.color_option_buttons.illumination.message:find("ILLUMINATED AREAS",1,true)~=nil,true)
  view.color_option_buttons.exits.click(); eq(calls[#calls].key,"exits"); eq(calls[#calls].value,true); eq(view.color_settings_visible,true)
  view.color_option_buttons.damage.click(); eq(calls[#calls].key,"damage"); eq(calls[#calls].value,false)
  view.color_option_buttons.enabled.click(); eq(calls[#calls].key,"enabled"); eq(view.color_enabled,false)
end)

test("chat settings separates visible clearing from confirmed saved-history deletion",function()
  local view=chatView(); local actions={}; view:setOptionsActionCallback(function(action) actions[#actions+1]=action; if action=="chat_clear_visible" then return true,12 elseif action=="chat_clear_saved" then return true,3 end; return true end)
  view:applyLayout(require("layout").compute(1024,600)); view.color_toggle.click(); view.option_action_buttons.chat_settings.click()
  eq(view.chat_settings_visible,true); eq(view.chat_settings_panel.visible,true)
  assert(view.chat_settings_clear_visible.click()); eq(actions[#actions],"chat_clear_visible"); eq(view.chat_settings_status.message:find("12 visible",1,true)~=nil,true)
  assert(view.chat_settings_clear_saved.click()); eq(actions[#actions],"chat_clear_visible"); eq(view.chat_settings_clear_pending,true)
  assert(view.chat_settings_clear_saved.click()); eq(actions[#actions],"chat_clear_saved"); eq(view.chat_settings_clear_pending,false); eq(view.chat_settings_status.message:find("3 saved",1,true)~=nil,true)
  view.chat_settings_close.click(); eq(view.chat_settings_visible,false)
end)

test("color options menu closes by button outside click and resize remains bounded",function()
  local view=chatView()
  for _,size in ipairs({{220,120},{420,500},{760,700},{800,650},{1200,800},{1920,1080}}) do
    local layout=require("layout").compute(size[1],size[2]); view:applyLayout(layout); view.color_toggle.click(); view.option_action_buttons.color_settings.click()
    eq(view.color_menu.x>=0,true); eq(view.color_menu.x+view.color_menu.width<=size[1],true)
    eq(view.color_menu.x,0)
    eq(view.color_menu.y,view.options_anchor.y+view.options_anchor.height+4)
    eq(view.color_menu.y+view.color_menu.height<=size[2],true)
    eq(view.color_settings_panel.x>=0,true); eq(view.color_settings_panel.x+view.color_settings_panel.width<=size[1],true)
    for _,key in ipairs(view.color_option_order) do local button=view.color_option_buttons[key]; eq(button.parent,view.color_settings_content); eq(button.x>=0,true); eq(button.x+button.width<=view.color_settings_content.width,true); eq(button.y>=0,true); eq(button.height>=25,true) end
    view.color_settings_overlay.click(); eq(view.color_settings_visible,false); eq(view.color_settings_panel.visible,false)
    view.color_toggle.click(); view.color_toggle.click(); eq(view.color_menu_visible,false)
  end
end)

test("open options menu remains flush left through responsive resizing",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view.color_toggle.click()
  for _,size in ipairs({{1920,1080},{800,650},{420,500},{220,120},{760,700}}) do
    local layout=require("layout").compute(size[1],size[2]); view:applyLayout(layout)
    eq(view.color_menu_visible,true); eq(view.color_menu.x,0)
    eq(view.color_menu.x>=0,true); eq(view.color_menu.y+view.color_menu.height<=size[2],true)
    for _,key in ipairs(view.option_action_order) do local button=view.option_action_buttons[key]; eq(button.x>=0,true); eq(button.x+button.width<=view.options_scroll.width,true) end
  end
end)

test("options menu exposes every autoroller command and settings action",function()
  local view=chatView(); local calls={}; view:setOptionsActionCallback(function(action) calls[#calls+1]=action; if action=="roller_settings" then return {target_total=53,hard_stop=62,reroll_delay=.1,reroll_command="n",min_stats={STR=5}} end; return true end)
  view:applyLayout(require("layout").compute(1200,800)); view.color_toggle.click()
  for _,key in ipairs(view.option_action_order) do eq(view.option_action_buttons[key].visible,true) end
  view.option_action_buttons.roller_settings.click(); eq(view.roller_settings_visible,true); eq(view.roller_fields.target_total.input.text,"53")
  for _,key in ipairs(view.roller_action_order) do eq(view.roller_action_buttons[key].visible,true) end
  view.roller_action_buttons.roller_start.click(); eq(calls[#calls],"roller_start")
  view.roller_action_buttons.roller_status.click(); eq(calls[#calls],"roller_status")
  view.roller_action_buttons.roller_show.click(); eq(calls[#calls],"roller_show")
end)

test("feedback option opens an in-game anonymous submission form",function()
  local view=chatView(); local sent,finish
  view:setFeedbackCallback(function(payload,done) sent=payload; finish=done; return true end)
  view:applyLayout(require("layout").compute(1200,800)); view.color_toggle.click(); view.option_action_buttons.support.click(); eq(view.support_visible,true); view.support_feedback.click()
  eq(view.feedback_visible,true); eq(view.feedback_panel.visible,true); eq(view.feedback_explanation.message:find("no GitHub account",1,true)~=nil,true)
  view.feedback_kind.click(); eq(view.feedback_draft.kind,"request")
  view.feedback_summary:print("Add a better clock"); view.feedback_details:print("Please show the next sunrise and sunset beside game time.")
  assert(view.feedback_send.click()); eq(sent.kind,"request"); eq(sent.summary,"Add a better clock"); eq(sent.details,"Please show the next sunrise and sunset beside game time."); eq(view.feedback_sending,true)
  finish({report_id="DG-1234"}); eq(view.feedback_sending,false); eq(view.feedback_status.message:find("DG%-1234")~=nil,true)
end)

test("feedback form contains callback failures and remains editable",function()
  local view=chatView(); view:setFeedbackCallback(function() error("network exploded") end); view:applyLayout(require("layout").compute(760,700)); view:showFeedback(); view.feedback_summary:print("Mapper suggestion"); view.feedback_details:print("Please make the room labels easier to move.")
  local ok,err=view:sendFeedback(); eq(ok,nil); eq(err:find("network exploded",1,true)~=nil,true); eq(view.feedback_sending,false); eq(view.feedback_visible,true)
end)
test("options command center opens the complete help guide",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view.color_toggle.click(); assert(view.option_action_buttons.command_help.click()); eq(view.help_visible,true); eq(view.color_menu_visible,false)
end)
test("map settings opens a responsive map library presentation",function()
  local view=chatView(); view:setMapSettingsActionCallback(function(action) if action=="map_library" then return view:showMapLibrary() end end); view:applyLayout(require("layout").compute(1200,800)); view:showMapSettings({transition_submaps={}})
  eq(view.option_action_buttons.map_library,nil); eq(view.map_settings_library.visible,true); assert(view.map_settings_library.click()); eq(view.map_library_visible,true); eq(view.map_settings_visible,false)
  for _,size in ipairs({{320,260},{760,700},{1200,800},{1920,1080}}) do
    local layout=require("layout").compute(size[1],size[2]); view:applyLayout(layout)
    eq(view.map_library_panel.x>=0,true); eq(view.map_library_panel.y>=0,true); eq(view.map_library_panel.x+view.map_library_panel.width<=size[1],true); eq(view.map_library_panel.y+view.map_library_panel.height<=size[2],true)
    for _,key in ipairs(view.map_collection_action_order) do local button=view.map_collection_actions[key]; eq(button.visible,true); eq(button.x>=0,true); eq(button.x+button.width<=view.map_library_panel.width,true); eq(button.y+button.height<=view.map_library_panel.height,true) end
    for _,key in ipairs({"keep","replace","skip","confirm","cancel"}) do eq(view.map_library_actions[key].visible,false) end
  end
  view.map_library_close.click(); eq(view.map_library_visible,false); eq(view.map_library_panel.visible,false)
end)
test("map library presents local collections with nontechnical editable actions",function()
  local view=chatView(); local calls={}; view:setMapCollectionActionCallback(function(action,item) calls[#calls+1]={action,item.id}; return true end)
  view:applyLayout(require("layout").compute(760,700)); view:showMapLibrary(); view:setMapCollections({
    {id="mine",name="Treehaven — My Copy",creator="Gia",area_count=8,room_count=412,active=true,editable=true},
    {id="spur",name="Spurian Academy",creator="Retro",areas={"Town","Temple"},room_count=90,update_available=true},
  })
  eq(view.map_library_mode,"collections"); eq(#view.map_collection_rows,2); assert(view.map_collection_rows[1].click()); eq(view:selectedMapCollection().id,"mine")
  for _,key in ipairs({"use_collection","share_collection","rename_collection","duplicate_edit","backup_collection","delete_collection"}) do assert(view.map_collection_actions[key].click()); eq(calls[#calls][1],key); eq(calls[#calls][2],"mine") end
  eq(view.map_collection_actions.share_collection.option_text,"SHARE SELECTED MAP")
  eq(view.map_collection_rows[1].message:find("ACTIVE",1,true)~=nil,true); eq(view.map_collection_rows[2].message:find("UPDATE AVAILABLE",1,true)~=nil,true)
end)
test("map collection replacement requires a large second-click warning",function()
  local view=chatView(); local replaced=0; view:setMapCollectionActionCallback(function(action) if action=="replace_collection" then replaced=replaced+1 end; return true end)
  view:applyLayout(require("layout").compute(760,700)); view:showMapLibrary(); view:setMapCollections({{id="mine",name="My Map",room_count=10}}); assert(view.map_collection_rows[1].click())
  local ok,err=view.map_collection_actions.replace_collection.click(); eq(ok,nil); eq(err,"replace confirmation required"); eq(replaced,0); eq(view.map_collection_replace_pending,true); eq(view.map_collection_actions.replace_collection.message:find("WARNING: CLICK AGAIN",1,true)~=nil,true)
  assert(view.map_collection_actions.replace_collection.click()); eq(replaced,1); eq(view.map_collection_replace_pending,false)
end)
test("shared library exposes download update and upload-my-version actions",function()
  local view=chatView(); local calls={}; view:setMapLibraryActionCallback(function(action,entry) calls[#calls+1]={action,entry and entry.slug}; return true end); view:applyLayout(require("layout").compute(760,700)); view:showMapLibrary(); assert(view:setMapLibraryMode("library")); view:setMapLibraryCatalog({{name="Spur",author="Gia",publisher="gia",slug="spur",room_count=42,version="1.0.0",areas={"Spur"}}}); assert(view.map_library_rows[1].click())
  for _,key in ipairs(view.map_library_download_action_order) do eq(view.map_library_download_actions[key].visible,true); if key=="replace_current" then eq(view.map_library_download_actions[key].click(),nil); assert(view.map_library_download_actions[key].click()) else assert(view.map_library_download_actions[key].click()) end; eq(calls[#calls][1],key); eq(calls[#calls][2],"spur") end
  eq(view.map_collection_list.visible,false); eq(view.map_library_list.visible,true); eq(view:setMapLibraryMode("unknown"),nil)
  eq(view.map_library_download_actions.merge_current.option_text,"ADD TO CURRENT MAP")
end)
test("collection and shared-library controls stay bounded on compact windows",function()
  local view=chatView(); view:showMapLibrary(); view:setMapCollections({{id="one",name="One",room_count=1}})
  for _,size in ipairs({{320,260},{420,500},{760,700},{1920,1080}}) do local layout=require("layout").compute(size[1],size[2]); view:applyLayout(layout); for _,button in pairs(view.map_library_modes) do eq(button.x>=0,true); eq(button.x+button.width<=view.map_library_panel.width,true) end; for _,button in pairs(view.map_collection_actions) do eq(button.x>=0,true); eq(button.x+button.width<=view.map_library_panel.width,true); eq(button.y+button.height<=view.map_library_panel.height,true) end end
end)
test("options keeps map settings reachable when mapper controls are hidden",function()
  local view=chatView(); view:setOptionsActionCallback(function(action) if action=="map_settings" then return {enabled=false,transition_submaps={}} end end); view:applyLayout(require("layout").compute(320,260)); view.color_toggle.click(); assert(view.option_action_buttons.map_settings.click()); eq(view.map_settings_visible,true)
end)
test("map settings contains callback exceptions and keeps the dialog open",function()
  local view=chatView(); view:setMapSettingsCallback(function() error("disk failed") end); view:applyLayout(require("layout").compute(800,650)); view:showMapSettings({transition_submaps={}}); local ok,err=view:saveMapSettings(); eq(ok,nil); eq(err:find("disk failed",1,true)~=nil,true); eq(view.map_settings_visible,true)
end)
test("map library actions are explicit presentation callbacks",function()
  local view=chatView(); local selected; view:setMapLibraryActionCallback(function(action) selected=action; return true end); view:applyLayout(require("layout").compute(1000,700)); view:showMapLibrary()
  for _,key in ipairs(view.map_library_action_order) do selected=nil; assert(view.map_library_actions[key].click()); eq(selected,key) end
end)
test("map library displays and selects downloaded catalog entries internally",function()
  local view=chatView(); view:applyLayout(require("layout").compute(760,700)); view:showMapLibrary(); view:setMapLibraryCatalog({{name="Spur",author="Gia",publisher="gia",slug="spur",room_count=42,version="1.0.0",areas={"Spur"}}}); eq(#view.map_library_rows,1); assert(view.map_library_rows[1].click()); eq(view:selectedMapLibraryEntry().slug,"spur"); eq(view.map_library_status:find("42 rooms",1,true)~=nil,true)
end)
test("map library searches friendly metadata and filters map scopes",function()
  local view=chatView(); view:applyLayout(require("layout").compute(900,700)); view:showMapLibrary()
  view:setMapLibraryCatalog({
    {name="Complete Spur",author="Gia",publisher="gia",slug="spur",scope="full_map",room_count=42,version="1.0.0",areas={"Spur"}},
    {name="Temple District",author="Retro",publisher="retro",slug="temple",scope="area",room_count=12,version="1.0.0",areas={"Spur"}},
    {name="Hidden Cellar",author="Gia",publisher="gia",slug="cellar",scope="subarea",room_count=4,version="1.0.0",areas={"Spur"},subareas={"Cellar"}},
    {name="Legacy Map",author="Old Mapper",publisher="old",slug="legacy",room_count=8,version="1.0.0",areas={"Treehaven"}},
  })
  eq(#view.map_library_rows,4); assert(view:setMapLibraryFilter("area")); eq(#view.map_library_rows,1); eq(view.map_library_visible_catalog[1].slug,"temple")
  assert(view:setMapLibraryFilter("all")); assert(view:setMapLibrarySearch("gia")); eq(#view.map_library_rows,2)
  assert(view:setMapLibrarySearch("cellar")); eq(#view.map_library_rows,1); eq(view.map_library_visible_catalog[1].slug,"cellar")
  assert(view:setMapLibrarySearch("")); assert(view:setMapLibraryFilter("full_map")); eq(#view.map_library_rows,2); eq(view.map_library_visible_catalog[2].slug,"legacy")
  eq(view:setMapLibraryFilter("unknown"),nil)
end)
test("map library search field applies on enter and remains inside the panel",function()
  local view=chatView(); local layout=require("layout").compute(760,700); view:applyLayout(layout); view:showMapLibrary(); view:setMapLibraryMode("library"); view:setMapLibraryCatalog({{name="Spur",author="Gia",publisher="gia",slug="spur",room_count=42,version="1.0.0",areas={"Spur"}}})
  assert(view.map_library_search.action("Gia")); eq(view.map_library_query,"Gia"); eq(#view.map_library_rows,1)
  eq(view.map_library_search.visible,true); eq(view.map_library_search.x>=0,true); eq(view.map_library_search.x+view.map_library_search.width<=view.map_library_panel.width,true)
  for _,key in ipairs(view.map_library_filter_order) do eq(view.map_library_filters[key].visible,true) end
end)
test("map library shows conflict choices only during installation review",function()
  local view=chatView(); view:applyLayout(require("layout").compute(760,700)); view:showMapLibrary(); view:setMapLibraryImportPending(true)
  for _,key in ipairs({"keep","replace","skip","confirm","cancel","report"}) do eq(view.map_library_actions[key].visible,true) end
  for _,key in ipairs({"browse","install","publish_all","publish_area","publish_subarea","export_all","export_area","export_subarea"}) do eq(view.map_library_actions[key].visible,false) end
  view:setMapLibraryImportPending(false); view:setMapLibraryMode("library"); eq(view.map_library_actions.browse.visible,true); eq(view.map_library_actions.keep.visible,false)
end)
test("combined-map review names current and downloaded map collision priority",function()
  local view=chatView(); view:applyLayout(require("layout").compute(760,700)); view:showMapLibrary(); view:setMapLibraryImportPending(true,true)
  eq(view.map_library_actions.keep.message:find("CURRENT MAP WINS",1,true)~=nil,true)
  eq(view.map_library_actions.replace.message:find("DOWNLOADED MAP WINS",1,true)~=nil,true)
  eq(view.map_library_actions.skip.message:find("SKIP COLLISIONS",1,true)~=nil,true)
  eq(view.map_library_actions.confirm.message:find("CREATE COMBINED MAP",1,true)~=nil,true)
end)
test("help and map library expose copyable plain-text instructions",function()
  local view=chatView(); local copied={}; view:setCopyTextCallback(function(value) copied[#copied+1]=value; return true end); view:applyLayout(require("layout").compute(1000,700))
  view:showHelp(); assert(view.help_copy.click()); eq(copied[#copied]:find("dghud update",1,true)~=nil,true); eq(copied[#copied]:find("<span",1,true),nil)
  view:showMapLibrary(); assert(view.map_library_copy_button.click()); eq(copied[#copied]:find("No GitHub account is needed",1,true)~=nil,true)
end)
test("map import conflict review defaults safely and accepts only known choices",function()
  local rows=View.mapImportConflictModel({{area="Spur",local_rooms=12,imported_rooms=15},{area="Temple",local_rooms=4,imported_rooms=7}}, {[1]="keep_mine",[2]="use_imported"})
  eq(rows[1].choice,"keep_mine"); eq(rows[2].choice,"use_imported"); eq(rows[1].area,"Spur")
  local safe=View.mapImportConflictModel({{area="Unknown",local_rooms="bad"}}, {[1]="delete_everything"}); eq(safe[1].choice,"skip_area"); eq(safe[1].local_rooms,0)
end)
test("zoom-aware POI tags truncate suppress overlap and retain full tooltips",function()
  local points={{x=1,y=1,text="Ancient Temple",priority=1},{x=1.1,y=1.1,text="Shop",priority=9},{x=9,y=3,text="North Gate",priority=2}}
  local tags=View.poiTags(points,.5,10); eq(#tags,2); eq(tags[1].text,"Shop"); eq(tags[1].tooltip,"Shop"); eq(tags[2].text,"Nort…"); eq(tags[2].tooltip,"North Gate")
  local zoomed=View.poiTags({{x=2,y=2,text="Ancient Temple"}},2,10); eq(zoomed[1].text,"Ancient T…"); eq(zoomed[1].tooltip,"Ancient Temple")
end)

test("autoroller settings modal validates through one save callback and remains bounded",function()
  local view=chatView(); local received; view:setRollerSettingsCallback(function(values) received=values; if values.target_total=="bad" then return nil,"bad target" end; return true end)
  view:showRollerSettings({target_total=53,hard_stop=62,max_rolls=nil,reroll_delay=.1,reroll_command="reroll",arrange_mode="manual",minimum_greats=2,minimum_good_plus=5,auto_start_on_name=true,use_min_stats=true,require_min_stats_to_stop=true,logging_enabled=true,log_folder="rolls",master_file="master.txt",min_stats={STR=5,INT=5,WIS=5,DEX=5,AGI=5,CON=5,CHA=5,WIL=5,VOI=5,PER=5,APP=5}})
  eq(view.roller_fields.reroll_command,nil)
  for _,size in ipairs({{420,280},{420,500},{760,700},{1200,800},{1920,1080}}) do local layout=require("layout").compute(size[1],size[2]); view:applyLayout(layout); eq(view.roller_panel.x>=0,true); eq(view.roller_panel.y>=0,true); eq(view.roller_panel.x+view.roller_panel.width<=size[1],true); eq(view.roller_panel.y+view.roller_panel.height<=size[2],true); eq(view.roller_content.parent,view.roller_panel); eq(view.roller_fields.STR.input.parent,view.roller_content); eq(view.roller_fields.INT.caption.y>=view.roller_fields.STR.input.y+view.roller_fields.STR.input.height,true); if layout.mode=="compact" then eq(view.roller_fields.STR.caption.x,view.roller_fields.target_total.caption.x); eq(view.roller_fields.STR.caption.y>view.roller_toggles.logging_enabled.y,true); eq(view.roller_arrange_buttons.manual.width>120,true); eq(view.roller_arrange_buttons.game_auto.x>view.roller_arrange_buttons.manual.x+view.roller_arrange_buttons.manual.width,true); eq(view.roller_arrange_buttons.minimums.y>view.roller_arrange_buttons.manual.y+view.roller_arrange_buttons.manual.height,true); eq(view.roller_arrange_buttons.minimums.width,view.roller_content.width) end end
  eq(view.roller_draft.arrange_mode,"manual"); eq(view.roller_arrange_buttons.manual.width>0,true); view.roller_arrange_buttons.game_auto.click(); eq(view.roller_draft.arrange_mode,"game_auto"); view.roller_arrange_buttons.minimums.click(); eq(view.roller_draft.arrange_mode,"minimums"); eq(view.roller_arrange_buttons.minimums.x+view.roller_arrange_buttons.minimums.width<=view.roller_content.width,true)
  view.roller_fields.target_total.input.text="bad"; local ok,err=view:saveRollerSettings(); eq(ok,nil); eq(err,"bad target"); eq(view.roller_settings_visible,true)
  view.roller_fields.target_total.input.text="60"; assert(view:saveRollerSettings()); eq(received.target_total,"60"); eq(received.arrange_mode,"minimums"); eq(received.minimum_greats,"2"); eq(received.minimum_good_plus,"5"); eq(received.min_stats.APP,"5"); eq(view.roller_settings_visible,false)
end)

test("help and autoroller settings overlays are mutually exclusive",function()
  local view=chatView(); view:applyLayout(require("layout").compute(800,650)); view:showHelp(); eq(view.help_panel.visible,true)
  view:showRollerSettings({target_total=53,reroll_command="n",min_stats={}}); eq(view.help_visible,false); eq(view.help_panel.visible,false); eq(view.roller_panel.visible,true)
  view:showHelp(); eq(view.roller_settings_visible,false); eq(view.roller_panel.visible,false); eq(view.help_panel.visible,true)
end)

test("help overlay distinguishes commands descriptions and warnings",function()
  local view=chatView(); local layout=require("layout").compute(1200,800); view:applyLayout(layout)
  view:showHelp()
  eq(view.help_visible,true); eq(view.help_overlay.visible,true); eq(view.help_panel.visible,true); eq(view.help_output.visible,true)
  eq(view.help_content.message:find("dghud update",1,true)~=nil,true)
  eq(view.help_content.message:find("both 11-characteristic rolling methods",1,true)~=nil,true)
  eq(view.help_content.message:find("arranged-pool counts",1,true)~=nil,true)
  eq(view.help_content.message:find(view.settings.theme.jade,1,true)~=nil,true)
  eq(view.help_content.message:find(view.settings.theme.text,1,true)~=nil,true)
  eq(view.help_content.message:find(view.settings.theme.hp,1,true)~=nil,true)
end)

test("help overlay remains bounded and readable at every layout mode",function()
  local view=chatView(); view:showHelp()
  for _,size in ipairs({{420,500},{760,700},{800,650},{1200,800},{1920,1080}}) do
    local layout=require("layout").compute(size[1],size[2]); view:applyLayout(layout)
    eq(view.help_panel.visible,true); eq(view.help_panel.x>=0,true); eq(view.help_panel.y>=0,true)
    eq(view.help_panel.x+view.help_panel.width<=size[1],true); eq(view.help_panel.y+view.help_panel.height<=size[2],true)
    eq(view.help_font>=11,true); eq(view.help_close.x+view.help_close.width<=view.help_panel.width,true)
  end
end)

test("help close control dismisses panel and invokes integration callback",function()
  local view=chatView(); local calls=0; view:setHelpCloseCallback(function() calls=calls+1 end)
  view:applyLayout(require("layout").compute(1000,700)); view:showHelp(); view.help_close.click()
  eq(calls,1); eq(view.help_visible,false); eq(view.help_overlay.visible,false); eq(view.help_panel.visible,false)
  view:setHelpVisible(true); eq(view.help_visible,true); view:hideHelp(); eq(view.help_visible,false)
end)

test("help overlay preserves open state and content across resize",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1920,1080))
  view:showHelp({{command="custom command",description="Custom description."}})
  view:applyLayout(require("layout").compute(760,700))
  eq(view.help_visible,true); eq(view.help_content.message:find("custom command",1,true)~=nil,true)
  eq(view.help_content.message:find("Custom description.",1,true)~=nil,true)
end)

test("inventory runes and skills evenly fill the available right rail",function()
  local view=chatView(); local layout=require("layout").compute(1920,1080); view:applyLayout(layout)
  for _,pair in ipairs({{view.inventory_output,view.inventory_content,view.inventory_title},{view.runes_output,view.runes_content,view.runes_title},{view.skills_output,view.skills_content,view.skills_title}}) do
    eq(pair[1].kind,"scrollbox"); eq(pair[2].parent,pair[1]); eq(pair[1].height>=layout.list_row_height*5,true)
    eq(pair[2].fontSize,layout.list_font); eq(pair[2].font,view.list_font_family); eq(pair[3].fontSize,layout.list_title_font)
  end
  eq(view.inventory_footer.fontSize,layout.list_font+2)
  eq(view.runes_title.font,view.runes_content.font); eq(view.skills_title.font,view.skills_content.font)
  eq(math.abs(view.inventory.height-view.runes.height)<=1,true); eq(math.abs(view.runes.height-view.skills.height)<=1,true)
end)

test("runes retain supplied order and scroll beyond five visible rows",function()
  local view=chatView(); local layout=require("layout").compute(1920,1080); view:applyLayout(layout)
  local runes={}; for i=1,30 do runes[i]={name="Rune "..i,remaining=200-i} end
  local state={character={full_name="Test",physical={}},attributes={},combat={},equipment={items={}},inventory={items={}},runes={items=runes},skills={items={}},vitals={hp={current=1,maximum=1},fatigue={current=1,maximum=1},carry={current=1,maximum=1},psi={visible=false},web={visible=false},gold=0,silver=0,roundtime=0,position=0},room={name="R",players={},flags={},exits={}}}
  view:update(state)
  eq(view.runes_content.message:find("Rune 1",1,true)<view.runes_content.message:find("Rune 12",1,true),true)
  eq(view.runes_content.message:find("199 weaves remain",1,true)~=nil,true)
  eq(view.runes_content.height,view.list_row_height*30); eq(view.runes_content.height>view.runes_output.height,true)
end)
test("scrollable list content uses resolved numeric widths",function()
  local view=chatView(); local layout=require("layout").compute(1920,1080); view:applyLayout(layout)
  local state={character={physical={}},attributes={},combat={},equipment={items={}},inventory={items={{name="One",weight=1}},total_weight=1},skills={items={{name="Biting",level=4,remain=10}}},vitals={hp={current=1,maximum=1},fatigue={current=1,maximum=1},carry={current=1,maximum=1},psi={visible=false},web={visible=false},gold=0,silver=0,roundtime=0,position=0},room={players={},flags={},exits={}}}
  view:update(state)
  eq(type(view.inventory_content.width),"number"); eq(type(view.skills_content.width),"number")
  eq(view.inventory_content.width<view.inventory_output.width,true); eq(view.skills_content.width<view.skills_output.width,true)
  eq(view.inventory_content.raised,true); eq(view.skills_content.raised,true)
end)
test("narrow list panes preserve readable fonts and overflow horizontally",function()
  local view=chatView(7); local layout=require("layout").compute(1000,900); view:applyLayout(layout)
  eq(view.inventory_content.fontSize,layout.list_font); eq(view.skills_content.fontSize,layout.list_font)
  eq(view.inventory_content.width>view.inventory_output.width,true)
  eq(view.skill_name_width,20); eq(view.skill_level_width>=3,true); eq(view.skill_use_width>=4,true)
  eq(view.inventory_output.height>=layout.list_viewport_height+layout.list_horizontal_scrollbar_height,true)
  eq(view.inventory_content.height,view.inventory_output.height)
  view.right_list_tabs.skills.click(); eq(view.skills.visible,true); eq(view.inventory.visible,false)
  eq(view.skills_content.width>view.skills_output.width,true)
  eq(view.skills_output.height>=layout.list_viewport_height+layout.list_horizontal_scrollbar_height,true)
  eq(view.skills_content.height,view.skills_output.height)
end)
test("map settings toolbar label remains bounded at the medium breakpoint",function()
  local layout=require("layout").compute(1000,700); local view=chatView(7)
  view:applyLayout(layout)
  eq(view.map_clear_all.visible,true)
  eq(view.map_clear_all.message:find("MAP SETTINGS",1,true)~=nil,true)
  view:setMapClearPending(true)
  eq(view.map_clear_all.message:find("MAP SETTINGS",1,true)~=nil,true)
  eq(view.map_zoom_in.x+view.map_zoom_in.width<=view.map_clear_all.x,true)
end)
test("map settings popup is responsive and submits transition choices",function()
  local view=chatView(); local received; view:setMapSettingsCallback(function(values) received=values; return true,nil,values end)
  assert(view:showMapSettings({enabled=true,minimum_height=90,height_percent=.4,maximum_height=380,zoom_step=2.5,zoom_min=3,zoom_max=60,walk_timeout=12,special_timeout=12,transition_submaps={gate=true,portal=false,door=true,arch=true,path=true,other=true}}))
  view:applyLayout(require("layout").compute(1000,700)); eq(view.map_settings_panel.visible,true); eq(view.map_settings_panel.x>=0,true); eq(view.map_settings_panel.x+view.map_settings_panel.width<=1000,true)
  eq(view.map_settings_draft.portal,false); view.map_settings_fields.minimum_height.input.text="120"; assert(view:saveMapSettings()); eq(received.minimum_height,"120"); eq(received.transition_submaps.portal,false); eq(view.map_settings_visible,false)
end)
test("map naming buttons apply names and show the native mapper label",function()
  local view=chatView(); local calls={}
  view:setMapSettingsActionCallback(function(action,value)
    calls[#calls+1]=action..":"..value
    if action=="rename_area" then return value,"Spur" end
    return value,"Spur - Town Square Center Area"
  end)
  assert(view:showMapSettings({current_area_name="",current_subarea_name="",transition_submaps={}}))
  view.map_settings_area_name.text="Spur"; assert(view.map_settings_rename_area.click())
  eq(calls[1],"rename_area:Spur"); eq(view.map_settings_draft.current_area_name,"Spur")
  eq(view.map_settings_status.message:find("Saved map name: Spur",1,true)~=nil,true)
  view.map_settings_subarea_name.text="Town Square Center Area"; assert(view.map_settings_rename_subarea.click())
  eq(calls[2],"rename_subarea:Town Square Center Area")
  eq(view.map_settings_status.message:find("Spur - Town Square Center Area",1,true)~=nil,true)
end)
test("saving map settings applies changed area and subarea names first",function()
  local view=chatView(); local calls={}
  view:setMapSettingsActionCallback(function(action,value)
    calls[#calls+1]=action
    return value,action=="rename_area" and "Spur" or "Spur - Town Square Center Area"
  end)
  view:setMapSettingsCallback(function(values) calls[#calls+1]="save"; return true,nil,values end)
  assert(view:showMapSettings({current_area_name="Old",current_subarea_name="Old Center",transition_submaps={}}))
  view.map_settings_area_name.text="Spur"; view.map_settings_subarea_name.text="Town Square Center Area"
  assert(view:saveMapSettings())
  eq(table.concat(calls,","),"rename_area,rename_subarea,save")
  eq(view.map_settings_visible,false)
end)
test("skill viewport uses live geometry with a conservative scrollbar reservation",function()
  local view=chatView(7); local layout=require("layout").compute(1920,1080); view:applyLayout(layout)
  eq(view.list_resolved_scrollbar_width>=18,true)
  eq(view.list_content_width,math.max(view.skills_output:get_width()-view.list_resolved_scrollbar_width,29*view.list_character_width))
  local header=View.skillHeader(view.skill_name_width,view.skill_column_gaps,view.skill_level_width,view.skill_use_width)
  local row=View.skillLine({name="Identify Armor Quality",level=30,remain=7},view.skill_name_width,view.skill_column_gaps,view.skill_level_width,view.skill_use_width)
  eq(#header*view.list_character_width<=view.list_content_width,true)
  eq(#row*view.list_character_width<=view.list_content_width,true)
end)
test("failed glyph measurement uses a conservative skill width",function()
  local view=chatView(7,32,true); local layout=require("layout").compute(1920,1080); view:applyLayout(layout)
  eq(view.list_character_width>=layout.list_font,true)
  local header=View.skillHeader(view.skill_name_width,view.skill_column_gaps,view.skill_level_width,view.skill_use_width)
  local row=View.skillLine({name="Identify Armor Quality",level=30,remain=7},view.skill_name_width,view.skill_column_gaps,view.skill_level_width,view.skill_use_width)
  eq(#header*view.list_character_width<=view.list_content_width,true)
  eq(#row*view.list_character_width<=view.list_content_width,true)
end)
test("measured fixed-width skill columns fit before scaled scrollbars",function()
  local cases={
    {1000,900,6,24},
    {1000,900,7,24},
    {1000,900,8},
    {1000,900,10},
    {1000,900,12},
    {1024,768,6,24},
    {1200,800,7,24},
    {1366,768,8,24},
    {1920,1080,10,24},
    {1920,1080,12,40},
  }
  for _,case in ipairs(cases) do
    local width,height,glyph,scrollbar=case[1],case[2],case[3],case[4]
    local view=chatView(glyph); view.list_scrollbar_width=scrollbar
    local layout=require("layout").compute(width,height); view:applyLayout(layout)
    if layout.right_lists_mode=="tabbed" then view.right_list_tabs.skills.click() end
    local header=View.skillHeader(view.skill_name_width,view.skill_column_gaps,view.skill_level_width,view.skill_use_width)
    local row=View.skillLine({name=string.rep("Wide Skill ",5),level=30,remain=7},view.skill_name_width,view.skill_column_gaps,view.skill_level_width,view.skill_use_width)
    eq(view.list_character_width,glyph)
    eq(view.list_content_width,math.max(view.skills_output.width-view.list_resolved_scrollbar_width,29*glyph))
    eq(#header*glyph<=view.list_content_width,true)
    eq(#row*glyph<=view.list_content_width,true)
    local levelColumn=row:find("30",1,true)-1
    local usesColumn=row:find("7",levelColumn+3,true)-1
    eq(header:sub(levelColumn+1,levelColumn+3):match("%S")~=nil,true)
    eq(header:sub(usesColumn+1,usesColumn+4):match("%S")~=nil,true)
    eq(header:sub(1,view.skill_name_width):match("%S")~=nil,true)
  end
end)

test("scrollable cards render every inventory item and every ranked skill",function()
  local view=chatView(); local layout=require("layout").compute(1920,1080); view:applyLayout(layout)
  local items,skills={},{}; for i=1,12 do items[i]={name="Item "..i,weight=i}; skills[i]={name="Skill "..i,level=20-i,remain=i} end
  view:update({character={full_name="Test",race="Monitanian",class="Fighter",alignment="entropy",physical={}},attributes={},combat={},equipment={items={}},inventory={items=items,total_weight=78},skills={items=skills},vitals={hp={current=1,maximum=1},fatigue={current=1,maximum=1},carry={current=1,maximum=1},psi={visible=false},web={visible=false},gold=2,silver=3,roundtime=0,position=0,weapon_readied=false,shield_readied=false},room={name="Room",num=1,area=1,environment="Plain",players={},flags={},exits={}}})
  eq(view.inventory_content.message:find("Item 12",1,true)~=nil,true); eq(view.skills_content.message:find("Skill&nbsp;12",1,true)~=nil,true)
  eq(view.inventory_content.height>=view.list_row_height*12,true); eq(view.skills_content.height>=view.list_row_height*12,true); eq(view.inventory_content.height>view.inventory_output.height,true); eq(view.skills_content.height>view.skills_output.height,true); eq(view.inventory_footer.message:find("2gp",1,true)~=nil,true)
  eq(view.skills_content.message:find("white-space:pre",1,true),nil); eq(view.skills_content.message:find("&nbsp;",1,true)~=nil,true)
  local resized=require("layout").compute(1200,800); view:applyLayout(resized)
  eq(view.inventory_content.height>=view.list_row_height*12,true); if resized.right_lists_mode=="tabbed" then view.right_list_tabs.skills.click() end; eq(view.skills_content.height>=view.list_row_height*12,true)
end)

test("unchanged HUD refreshes preserve inventory and skill scroll positions",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1920,1080))
  local state={character={full_name="Test",race="M",class="F",alignment="e",physical={}},attributes={},combat={},equipment={items={}},inventory={items={{name="One",weight=1}},total_weight=1},skills={items={{name="Biting",level=4,remain=10}}},vitals={hp={current=1,maximum=1},fatigue={current=1,maximum=1},carry={current=1,maximum=1},psi={visible=false},web={visible=false},gold=0,silver=0,roundtime=0,position=0},room={name="R",players={},flags={},exits={}}}
  view:update(state); local inventoryMessage=view.inventory_content.message; local skillMessage=view.skills_content.message
  view:update(state); eq(view.inventory_content.message,inventoryMessage); eq(view.skills_content.message,skillMessage)
  state.skills.items={{name="Clawing",level=5,remain=2}}; view:update(state); eq(view.skills_content.message:find("Clawing",1,true)~=nil,true)
end)

test("right rail orders combat inventory runes and skills without overlap",function()
  for _,size in ipairs({{1920,1080},{1200,800},{1200,650}}) do
    local layout=require("layout").compute(size[1],size[2]); local view=chatView(); view.last_state={vitals={psi={visible=false},web={visible=false}},equipment={items={}}}; view:applyLayout(layout)
    if view.inventory.visible and view.skills.visible then
      eq(view.runes.visible,true); eq(view.runes_output.visible,true)
      eq(view.details.visible,true); eq(view.details.y+view.details.height<=view.inventory.y,true); eq(view.inventory.y+view.inventory.height<=view.runes.y,true)
      local inventory_runes_gap=view.runes.y-(view.inventory.y+view.inventory.height); eq(inventory_runes_gap>=0,true); eq(inventory_runes_gap<=12,true)
      eq(view.runes.y+view.runes.height<=view.skills.y,true)
      eq(view.skills.y+view.skills.height<=layout.window_height-12,true)
    else
      eq(view.skills.visible,false)
      if view.inventory.visible then eq(view.inventory.y+view.inventory.height<=layout.window_height-12,true) end
    end
  end
end)

test("native mapper is embedded immediately above the compass",function()
  local layout=require("layout").compute(1920,1080); local view=chatView(); view:applyLayout(layout)
  eq(view.mapper_frame~=nil,true); eq(view.mapper~=nil,true)
  eq(view.mapper.parent,view.mapper_frame); eq(view.mapper_frame.visible,true)
  eq(view.mapper_frame.y+view.mapper_frame.height+layout.lower_mapper_gap,view.compass_area.y)
  eq(view.mapper.raised,true); eq(view.compass_area.raised,true)
end)

test("vitals span the center bottom and carry is not a gauge",function()
  local layout=require("layout").compute(1920,1080); local view=chatView()
  view.last_state={vitals={psi={visible=true},web={visible=false}},equipment={items={}}}
  view:applyLayout(layout)
  eq(view.vitals_right~=nil,true)
  eq(view.hp.parent,view.vitals_right); eq(view.fatigue.parent,view.vitals_right); eq(view.psi.parent,view.vitals_right)
  eq(view.vitals_right.x,layout.console_left); eq(view.vitals_right.width,layout.console_width)
  eq(view.vitals_right.y,"100%-"..layout.bottom); eq(view.vitals_right.height,layout.vitals_strip_height); eq(view.carry.visible,false)
  eq(view.hp.y+view.hp.height,layout.vitals_strip_height)
  eq(view.mapper_frame.height>=300,true)
  eq(view.room.y,layout.lower_panel_padding)
end)

test("mapper owns visible minus center and plus controls without covering compass",function()
  local view=chatView(); local layout=require("layout").compute(1920,1080); view:applyLayout(layout)
  eq(view.map_zoom_out.visible,true); eq(view.map_center.visible,true); eq(view.map_zoom_in.visible,true)
  eq(view.map_zoom_in.parent,view.mapper_frame)
  eq(view.map_zoom_in.y+view.map_zoom_in.height<=view.mapper_frame.height,true)
  eq(view.mapper.y>=layout.lower_mapper_toolbar_height,true)
  eq(view.map_zoom_out.tooltip~=nil,true); eq(view.map_center.tooltip~=nil,true); eq(view.map_zoom_in.tooltip~=nil,true)
end)

test("zoom buttons invoke visual actions",function()
  local view=chatView(); local calls={}; view:setMapZoomCallback(function(action) calls[#calls+1]=action end)
  view.map_zoom_in.click(); view.map_zoom_out.click(); view.map_center.click()
  eq(table.concat(calls,","),"larger,smaller,center")
end)
test("mapper owns a top-right map settings button",function()
  local layout=require("layout").compute(1920,1080); local view=chatView(); local calls=0
  view:setMapClearAllCallback(function() calls=calls+1 end); view:applyLayout(layout)
  eq(view.map_clear_all.visible,true); eq(view.map_clear_all.x+view.map_clear_all.width<=layout.left-2*layout.lower_panel_padding,true)
  eq(view.map_clear_all.tooltip,"Open Map Settings")
  view.map_clear_all.click(); eq(calls,1)
  view:setMapClearPending(true); eq(view.map_clear_all.message:find("MAP SETTINGS",1,true)~=nil,true)
end)

test("repeated mapper resize reuses controls and callbacks while hidden layouts hide them",function()
  local Layout=require("layout"); local view=chatView(); local calls=0
  view:setMapZoomCallback(function() calls=calls+1 end)
  local zoomOut,center,zoomIn=view.map_zoom_out,view.map_center,view.map_zoom_in
  for _,size in ipairs({{1920,1080},{1200,800},{1200,650},{1000,650},{1920,1080}}) do view:applyLayout(Layout.compute(size[1],size[2])) end
  eq(view.map_zoom_out,zoomOut); eq(view.map_center,center); eq(view.map_zoom_in,zoomIn)
  view.map_zoom_in.click(); eq(calls,1)
  view:applyLayout(Layout.compute(760,700))
  eq(view.map_zoom_out.visible,false); eq(view.map_center.visible,false); eq(view.map_zoom_in.visible,false)
end)

test("responsive mapper survives short layouts and hides cleanly in compact mode",function()
  local Layout=require("layout"); local view=chatView()
  for _,size in ipairs({{1200,800},{1200,650},{1000,650}}) do
    local layout=Layout.compute(size[1],size[2]); view:applyLayout(layout)
    eq(view.mapper_frame.visible,true); eq(view.mapper_frame.height>=90,true)
    eq(view.utility_area.y+view.utility_area.height<=view.right.height,true)
  end
  view:applyLayout(Layout.compute(760,700))
  eq(view.mapper_frame.visible,false); eq(view.mapper.visible,false)
  eq(view.map_zoom_out.visible,false); eq(view.map_center.visible,false); eq(view.map_zoom_in.visible,false)
end)

test("roundtime progress bar remains visible and empty when ready",function()
  local Layout=require("layout"); local layout=Layout.compute(1920,1080); local view=chatView(); view:applyLayout(layout)
  eq(view.roundtime_bar.visible,true); eq(view.roundtime_bar.value[1],0); eq(view.roundtime_bar.value[3],"Roundtime  READY")
  eq(view:updateRoundtime(8,8),true); eq(view.roundtime_bar.visible,true); eq(view.roundtime_bar.value[1],8); eq(view.roundtime_bar.value[2],8)
  eq(view.roundtime_bar.value[3],"Roundtime  8s"); eq(view.utility_area.y+view.utility_area.height+layout.lower_roundtime_gap,view.roundtime_bar.y)
  local consoleWidth=layout.console_width; local bottom=layout.bottom
  view:updateRoundtime(4,8); eq(view.roundtime_bar.value[1],4); eq(view.roundtime_bar.value[2],8)
  eq(layout.console_width,consoleWidth); eq(layout.bottom,bottom)
  eq(view:updateRoundtime(0,8),false); eq(view.roundtime_bar.visible,true); eq(view.roundtime_bar.value[1],0); eq(view.roundtime_bar.value[2],1); eq(view.roundtime_bar.value[3],"Roundtime  READY")
  eq(view.utility_area.y+view.utility_area.height+layout.lower_roundtime_gap,view.roundtime_bar.y)
end)

test("roundtime bar stays hidden in compact mode",function()
  local Layout=require("layout"); local view=chatView(); view:updateRoundtime(5,5); view:applyLayout(Layout.compute(760,700)); eq(view.roundtime_bar.visible,false)
end)

test("short layouts keep center vitals separate from the mapper",function()
  local layout=require("layout").compute(1200,650); local view=chatView()
  view.last_state={vitals={psi={visible=true},web={visible=true}},equipment={items={}}}
  view:applyLayout(layout)
  eq(view.hp.parent,view.vitals_right); eq(view.vitals_right.x,layout.console_left); eq(view.vitals_right.width,layout.console_width)
  if view.room.visible then eq(view.room.y+view.room.height<=view.mapper_frame.y,true) end
end)

test("compact PSI and Web use two readable rows while ordinary vitals use one",function()
  local Layout=require("layout")
  local ordinary=Layout.compute(600,700,nil,nil,{psi={visible=false},web={visible=false}})
  local both=Layout.compute(600,700,nil,nil,{psi={visible=true},web={visible=true}})
  eq(ordinary.vitals_strip_rows,1); eq(both.vitals_strip_rows,2); eq(both.bottom>ordinary.bottom,true)
  local view=chatView(); view.last_state={vitals={psi={visible=true},web={visible=true}},equipment={items={}}}; view:applyLayout(both)
  eq(view.hp.y,view.fatigue.y); eq(view.psi.y,view.web.y); eq(view.psi.y>view.hp.y,true)
  eq(view.web.x+view.web.width<=view.vitals_right.width,true)
end)

test("right-side vitals preserve required combat and scrollable lists",function()
  local layout=require("layout").compute(1200,600); local view=chatView()
  view.last_state={vitals={psi={visible=false},web={visible=false}},equipment={items={}}}
  view:applyLayout(layout)
  eq(view.inventory.visible,true)
  eq(view.details.visible,true); eq(view.details.y+view.details.height<=view.inventory.y,true)
  eq(view.right_list_tabs.skills.visible,true); view.right_list_tabs.skills.click(); eq(view.skills.visible,true); eq(view.skills_output.visible,true); eq(view.inventory.visible,false)
  eq(view.inventory.y+view.inventory.height<=layout.window_height-12,true)
end)
test("short desktop windows retain every list behind readable tabs",function()
  for _,size in ipairs({{800,600},{1000,600},{1200,600},{1400,600}}) do
    local layout=require("layout").compute(size[1],size[2]); local view=chatView(7)
    view.last_state={vitals={psi={visible=false},web={visible=false}},equipment={items={}},inventory={items={}},runes={items={}},skills={items={}}}
    view:applyLayout(layout)
    eq(layout.right_lists_mode,"tabbed"); eq(view.inventory.visible,true); eq(view.inventory_output.visible,true)
    if size[1]==800 then eq(view.right_list_tabs.inventory.message:find("INV",1,true)~=nil,true); eq(view.right_list_tabs.runes.message:find("RUN",1,true)~=nil,true); eq(view.right_list_tabs.skills.message:find("SKL",1,true)~=nil,true) end
    for _,key in ipairs({"runes","skills","inventory"}) do view.right_list_tabs[key].click(); eq(view[key].visible,true); eq(view[key.."_output"].visible,true); eq(view[key].y+view[key].height<=layout.window_height-12,true) end
  end
end)
test("compact windows retain scrollable inventory runes and skills above the chatbox",function()
  for _,size in ipairs({{799,600},{760,700},{400,300},{320,260}}) do
    local layout=require("layout").compute(size[1],size[2]); local view=chatView(7)
    view.last_state={character={full_name="Test",race="Human",class="Fighter",physical={}},clock={},attributes={},combat={},needs={},vitals={hp={current=1,maximum=1},fatigue={current=1,maximum=1},gold=3,silver=9,carry={current=12,maximum=100,percent=12},roundtime=0,position=0,psi={visible=false},web={visible=false}},equipment={items={}},inventory={items={{name="Torch",weight=.1}}},runes={items={{name="Force",remaining=10}}},skills={items={{name="Biting",level=4,remain=105}}},room={name="Room",num=1,area=1,environment="Test",players={},flags={},exits={"north"}}}
    view:applyLayout(layout); view:update(view.last_state)
    eq(layout.right_lists_mode,"compact-tabs"); eq(view.right_list_tabs.inventory.visible,true); eq(view.inventory.visible,true); eq(view.inventory_output.visible,true); eq(view.inventory.y+view.inventory.height<=layout.header_height,true)
    for _,key in ipairs({"runes","skills","inventory"}) do view.right_list_tabs[key].click(); eq(view[key].visible,true); eq(view[key.."_output"].visible,true); eq(view[key].y+view[key].height<=layout.header_height,true) end
  end
end)
test("tiny compact layouts never overlap inventory and wealth when extra vitals are visible",function()
  local state={character={full_name="Test",race="Arachnian",class="Psion",physical={}},clock={},attributes={},combat={},needs={},vitals={hp={current=1,maximum=1},fatigue={current=1,maximum=1},gold=3,silver=9,carry={current=12,maximum=100,percent=12},roundtime=0,position=0,psi={visible=true,current=1,maximum=1},web={visible=true,current=1,maximum=1}},equipment={items={}},inventory={items={{name="Torch",weight=.1}}},runes={items={}},skills={items={}},room={name="Room",num=1,area=1,environment="Test",players={},flags={},exits={}}}
  for _,size in ipairs({{400,300},{320,260}}) do
    local layout=require("layout").compute(size[1],size[2],nil,nil,state.vitals); local view=chatView(7); view.last_state=state; view:applyLayout(layout); view:update(state)
    eq(layout.console_remainder>=60,true)
    eq(view.right_list_tabs.inventory.visible,true); eq(view.inventory.visible,true); eq(view.inventory_output.visible,true)
    eq(view.inventory_output.y+view.inventory_output.height<=view.inventory.y+view.inventory.height,true)
    if view.inventory_footer.visible then eq(view.inventory_output.y+view.inventory_output.height<=view.inventory_footer.y,true) end
    for _,key in ipairs({"runes","skills","inventory"}) do view.right_list_tabs[key].click(); eq(view[key].visible,true); eq(view[key.."_output"].visible,true); eq(view[key.."_output"].height>=layout.list_row_height,true); eq(view[key.."_output"].y+view[key.."_output"].height<=view[key].y+view[key].height,true) end
    if layout.compact_minimal_header then eq(view.clock_header.visible,false); eq(view.attribute_strip.visible,false); eq(view.color_toggle.visible,true) end
  end
end)
test("large HUD text keeps the inventory viewport above its wrapped footer and redraws on resize",function()
  local View=require("view"); local Layout=require("layout"); local view=chatView(7)
  local state={character={full_name="Test",physical={}},attributes={},combat={},equipment={items={}},inventory={items={{name="A very long carried item name",weight=12.3}}},runes={items={}},skills={items={}},vitals={hp={current=1,maximum=1},fatigue={current=1,maximum=1},carry={current=174.4,maximum=354,percent=49.3},psi={visible=false},web={visible=false},gold=12345,silver=98765,roundtime=0,position=0},room={name="R",players={},flags={},exits={}}}
  view:applyLayout(Layout.compute(1920,1080,nil,nil,state.vitals,{side_text_scale=1.1})); view:update(state); local wide=view.inventory_footer.message
  view:applyLayout(Layout.compute(1000,600,nil,nil,state.vitals,{side_text_scale=1.1})); eq(view.inventory.visible,true)
  eq(view.inventory_output.y+view.inventory_output.height<=view.inventory_footer.y,true)
  local lines=View.inventoryFooterLines(state.vitals,view.settings.theme,view.inventory_footer_capacity)
  eq(view.inventory_footer_rows,#lines); eq(view.inventory_footer.message,table.concat(lines,"<br>")); eq(view.inventory_footer.message~=wide,true)
end)

test("crossing responsive breakpoints repeatedly restores every desktop card",function()
  local Layout=require("layout"); local view=chatView(7)
  view.last_state={vitals={psi={visible=false},web={visible=false}},equipment={items={}},inventory={items={}},skills={items={}}}
  for _,size in ipairs({{1400,800},{1399,800},{1000,800},{999,800},{760,800},{999,800},{1400,800}}) do
    local layout=Layout.compute(size[1],size[2]); view:applyLayout(layout)
    if layout.mode=="compact" then eq(view.compact.visible,true); for _,key in ipairs({"inventory","runes","skills"}) do view.right_list_tabs[key].click(); eq(view[key].visible,true) end else
      for _,widget in ipairs({view.identity,view.details,view.right}) do eq(widget.visible,true) end
      if layout.right_lists_mode=="tabbed" then for _,key in ipairs({"inventory","runes","skills"}) do view.right_list_tabs[key].click(); eq(view[key].visible,true); eq(view[key.."_output"].visible,true) end else for _,widget in ipairs({view.inventory,view.inventory_title,view.inventory_output,view.inventory_content,view.runes,view.runes_title,view.runes_output,view.runes_content,view.skills,view.skills_title,view.skills_output,view.skills_content}) do eq(widget.visible,true) end end
    end
  end
end)
test("chat settings controls never overlap or leave the panel on short compact windows",function()
  local view=chatView(); view:showChatSettings()
  for _,size in ipairs({{400,300},{320,260},{800,600},{1024,600}}) do
    local layout=require("layout").compute(size[1],size[2]); view:applyLayout(layout); local panel=view.chat_settings_panel
    local ordered={view.chat_settings_title,view.chat_settings_text,view.chat_settings_clear_visible,view.chat_settings_clear_saved}
    for index,item in ipairs(ordered) do eq(item.y>=0,true); eq(item.y+item.height<=panel.height,true); if index>1 then eq(item.y>=ordered[index-1].y+ordered[index-1].height,true) end end
    if view.chat_settings_status.visible then eq(view.chat_settings_status.y>=view.chat_settings_clear_saved.y+view.chat_settings_clear_saved.height,true); eq(view.chat_settings_status.y+view.chat_settings_status.height<=view.chat_settings_close.y,true) end
    eq(view.chat_settings_close.y>=view.chat_settings_clear_saved.y+view.chat_settings_clear_saved.height,true); eq(view.chat_settings_close.y+view.chat_settings_close.height<=panel.height,true)
  end
end)
test("reusable view validation rejects missing responsive list tab structures",function()
  local View=require("view"); local view=chatView(); local settings=view.settings
  eq(View.validateReusable(view,settings),true)
  local tabs=view.right_list_tabs; local skillsTab=tabs.skills; view.right_list_tabs=nil
  local ok,err=View.validateReusable(view,settings); eq(ok,nil); assert(err:find("list tabs",1,true))
  view.right_list_tabs=tabs; view.right_list_tabs.skills=nil
  ok,err=View.validateReusable(view,settings); eq(ok,nil); assert(err:find("list tabs",1,true))
  view.right_list_tabs.skills=skillsTab; view.right_list_active="missing"
  ok,err=View.validateReusable(view,settings); eq(ok,nil); assert(err:find("active list tab",1,true))
end)
test("reusable view validation rejects damaged structural widgets and controls",function()
  local View=require("view")
  for _,name in ipairs({"clock_header","attribute_strip","mapper","chat_settings_clear_saved"}) do
    local view=chatView(); view[name]=nil
    local ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find(name,1,true))
  end
  local view=chatView(); view.option_action_buttons.chat_settings=nil
  local ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("controls",1,true))
  view=chatView(); view.hp.text=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("gauge",1,true))
  view=chatView(); view.roundtime_bar.back=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("gauge",1,true))
  view=chatView(); view.hp.text.setStyleSheet=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("gauge",1,true))
  view=chatView(); view.right_list_tabs.inventory.move=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("list tabs",1,true))
  view=chatView(); view.right_list_tabs.inventory.echo=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("list tabs",1,true))
  view=chatView(); view.option_action_buttons.chat_settings.setStyleSheet=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("controls",1,true))
  view=chatView(); view.map_library_rows={view.version_label}; view.map_library_rows[1].hide=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("map library rows",1,true))
  view=chatView(); view.map_collection_rows={view.version_label}; view.map_collection_rows[1].echo=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("map collection rows",1,true))
  view=chatView(); view.map_settings_fields.minimum_height.input.setStyleSheet=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("mapper settings",1,true))
  view=chatView(); view.header.echo=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("header",1,true))
  view=chatView(); view.chat_output.clear=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("chat_output",1,true))
  view=chatView(); view.attribute_strip.raise=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("attribute_strip",1,true))
  view=chatView(); view.root.delete=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("view is unavailable",1,true))
  view=chatView(); view.color_options=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("color state",1,true))
end)

test("equipment is optional below identity while combat remains required",function()
  for _,size in ipairs({{1920,420},{2560,420}}) do
    local layout=require("layout").compute(size[1],size[2]); local view=chatView()
    view.last_state={vitals={psi={visible=true},web={visible=true}},equipment={items={}}}
    view:applyLayout(layout)
    if view.equipment.visible then
      eq(view.equipment.x,layout.panel_padding); eq(view.equipment.y>=view.identity.y+view.identity.height,true)
      eq(view.equipment.y+view.equipment.height<=layout.window_height-view.right.height,true)
    end
    eq(view.details.visible,true)
    eq(view.hp.visible,true); eq(view.fatigue.visible,true); eq(view.carry.visible,false); eq(view.psi.visible,true); eq(view.web.visible,true)
  end
end)

test("mapper stack has exact non-overlapping bounds across resolutions and vital states",function()
  local Layout=require("layout")
  local sizes={{1920,1080},{2560,1400},{1200,800},{1200,650},{1000,650}}
  local states={{false,false},{true,false},{false,true},{true,true}}
  for _,size in ipairs(sizes) do for _,flags in ipairs(states) do
    local layout=Layout.compute(size[1],size[2]); local view=chatView()
    view.last_state={vitals={psi={visible=flags[1]},web={visible=flags[2]}},equipment={items={}}}
    view:applyLayout(layout)
    local panel=view.right.height
    if view.room.visible then
      eq(view.room.height>=layout.lower_room_min_height,true)
      if view.mapper_frame.visible then eq(view.room.y+view.room.height<=view.mapper_frame.y,true) end
    end
    if view.mapper_frame.visible then
      eq(view.mapper_frame.height>=layout.lower_mapper_min_height,true)
      eq(view.mapper_frame.y+view.mapper_frame.height+layout.lower_mapper_gap,view.compass_area.y)
      eq(view.mapper_frame.y>=0,true)
    end
    eq(view.compass_area.y+view.compass_area.height<=view.utility_area.y,true)
    eq(view.utility_area.y+view.utility_area.height<=panel,true)
    for _,widget in ipairs({view.room,view.compass_area,view.utility_area}) do
      if widget.visible then eq(widget.y>=0 and widget.y+widget.height<=panel,true) end
    end
    for _,widget in ipairs({view.hp,view.fatigue,view.psi,view.web}) do if widget.visible then eq(widget.y>=0 and widget.y+widget.height<=layout.bottom,true) end end
  end end
end)

test("view centers the native map through its adapter boundary",function()
  local view=chatView(); local calls={}
  view:setMapCenterCallback(function(roomID) calls[#calls+1]=roomID; return true end)
  eq(view:centerMap(175),true); eq(calls[1],175)
end)

test("chat output colors its trusted prefix without printing HTML markup literally",function()
  local view=chatView()
  view:renderChat({{category="ROOM",timestamp="2026-08-31T20:12:00-04:00",line='Gia says, "hey"'}},{"ROOM"},"ALL")
  eq(#(view.chat_output.hechoes or {}),1)
  eq(view.chat_output.hechoes[1]:find("<span",1,true),nil)
  eq(view.chat_output.hechoes[1]:find("<",1,true),nil)
  eq(view.chat_output.hechoes[1],"#75857c[20:12]#r #d7d0bfROOM#r")
  eq(#view.chat_output.echoes,1)
  eq(view.chat_output.echoes[1]:find('Gia says, "hey"',1,true)~=nil,true)
end)

test("Secian chat entries receive their own readable category color",function()
  local view=chatView()
  view:renderChat({{category="SECIAN",timestamp="2026-08-31T20:12:00-04:00",line='You pick up Shayla\'s Secian link, "hello!" [r-1]'}},{"SECIAN"},"ALL")
  eq(view.chat_output.hechoes[1],"#75857c[20:12]#r #8fcbd4SECIAN#r")
  eq(view.chat_filter_order[#view.chat_filter_order],"SECIAN")
end)

test("view owns a scrollable chat panel above the main console",function()
  local view=chatView()
  eq(view.chat_container~=nil,true); eq(view.chat_tabs~=nil,true); eq(view.chat_output~=nil,true)
  eq(view.chat_output.parent,view.chat_container); eq(view.chat_output.scrollBar,true); eq(view.chat_output.horizontalScrollBar,false)
end)

test("attribute strip spans the center header above the chatbox",function()
  local layout=require("layout").compute(1920,1080); local view=chatView(); view:applyLayout(layout)
  eq(view.attribute_strip.x,layout.console_left); eq(view.attribute_strip.y,0)
  eq(view.attribute_strip.width<=layout.console_width+layout.console_gutter,true); eq(view.attribute_strip.x+view.attribute_strip.width<=1920-layout.right,true); eq(view.attribute_strip.height,layout.header_height)
  eq(layout.attribute_strip_font>=10,true); eq(layout.attribute_strip_font<=14,true)
end)

test("chat panel occupies the center while side cards stay at the header",function()
  local layout=require("layout").compute(1920,1080); local view=chatView(); view:applyLayout(layout)
  eq(view.header.height,layout.header_height)
  eq(view.chat_container.x,layout.chat_x); eq(view.chat_container.y,layout.header_height)
  eq(view.chat_container.width,layout.chat_width); eq(view.chat_container.height,layout.chat_height)
  eq(view.identity.y,layout.header_height); eq(view.left.y,layout.header_height)
  if view.equipment.visible then eq(view.equipment.y,view.identity.y+view.identity.height+10) end
end)
test("clock occupies the top-right header rail across responsive modes",function()
  local wide=require("layout").compute(1920,1080); local view=chatView(); view:applyLayout(wide)
  eq(view.clock_header.x,"100%-"..wide.right); eq(view.clock_header.y,0); eq(view.clock_header.width,wide.right); eq(view.clock_header.height,wide.header_height)
  local compact=require("layout").compute(760,700); view:applyLayout(compact)
  eq(view.clock_header.x,"50%"); eq(view.clock_header.y,0); eq(view.clock_header.width,"50%"); eq(view.clock_header.height,compact.header_height)
end)

test("chat rendering keeps only the newest thousand and isolates untrusted text from color markup",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1920,1080)); local entries={}
  for index=1,1001 do entries[index]={category="ROOM",timestamp="2026-08-31T13:00:00-04:00",line="line-"..index} end
  entries[1001].line="<b>owned &\n\27[31m"
  view:renderChat(entries,{"ROOM","QUEST<script>","EVENTS\n"},"ALL")
  eq(#view.chat_output.echoes,1000); eq(view.chat_output.echoes[1]:find("line-2",1,true)~=nil,true)
  local last=view.chat_output.echoes[#view.chat_output.echoes]
  eq(last:find("<b>owned &",1,true)~=nil,true); eq(last:find("\n\27",1,true),nil)
  eq(view.chat_output.hechoes[#view.chat_output.hechoes]:find("#75857c",1,true)~=nil,true)
end)

test("chat tabs stay inside narrow panels and expose deterministic overflow",function()
  local layout=require("layout").compute(280,700); local view=chatView(); view:applyLayout(layout); local selected
  view:setChatFilterCallback(function(category) selected=category end)
  view:renderChat({}, {"QUEST","EVENTS","QUEST<script>","LINE\nBREAK"}, "ALL")
  eq(table.concat(view.chat_filter_order,","),"ALL,ROOM,PRIVATE,ESP,DRAGON,CONTACT,STAFF,COMBAT,QUEST,EVENTS,QUEST<SCRIPT>,LINE\nBREAK")
  eq(#view.chat_overflow_categories>0,true)
  for _,button in ipairs(view.chat_buttons) do
    eq(button.x+button.width<=layout.chat_width,true); eq(tostring(button.message):find("<script>",1,true),nil)
  end
  local first=view.chat_overflow_categories[1]; view.chat_overflow_button.click(); eq(selected,first)
end)

test("chat wrap reflows on resize while preserving scroll intent and filter",function()
  local Layout=require("layout"); local wide=Layout.compute(1920,1080); local narrow=Layout.compute(1000,700); local view=chatView()
  view:applyLayout(wide); view:renderChat({
    {category="ESP",timestamp="2026-08-31T13:00:00-04:00",line=string.rep("long message ",30)},
    {category="ESP",timestamp="2026-08-31T13:01:00-04:00",line="newest"},
  },{"ESP"},"ESP")
  view.chat_output.currentScroll=0; view:applyLayout(narrow)
  eq(view.chat_output.wrap,narrow.chat_wrap_columns); eq(view.chat_output.scrollCalls[#view.chat_output.scrollCalls],0)
  eq(view.chat_active_filter,"ESP"); eq(#view.chat_output.echoes,2)
  view.chat_output.currentScroll=view.chat_output.lastLine; view:applyLayout(wide)
  eq(view.chat_output.wrap,wide.chat_wrap_columns); eq(view.chat_output.scrollCalls[#view.chat_output.scrollCalls],"bottom")
  eq(view.chat_active_filter,"ESP")
end)

test("chat reflow keeps the same wrapped entry visible while narrowing and widening",function()
  local Layout=require("layout"); local wide=Layout.compute(1920,1080); local narrow=Layout.compute(1000,700); local view=chatView(); local entries={}
  for index=1,20 do entries[index]={category="ESP",timestamp="2026-08-31T13:00:00-04:00",line=string.rep("entry-"..index.." ",40)} end
  view:applyLayout(wide); view:renderChat(entries,{"ESP"},"ESP")
  view.chat_output.currentScroll=view.chat_output.renderedEntries[10].first+1
  view:applyLayout(narrow)
  local narrowed=view.chat_output.renderedEntries[10]
  eq(view.chat_output.currentScroll>=narrowed.first and view.chat_output.currentScroll<=narrowed.last,true)
  view:applyLayout(wide)
  local widened=view.chat_output.renderedEntries[10]
  eq(view.chat_output.currentScroll>=widened.first and view.chat_output.currentScroll<=widened.last,true)
end)

test("chat wrap uses live MiniConsole metrics after resize and font application",function()
  local layout=require("layout").compute(1000,700); local view=chatView(); local output=view.chat_output
  output.metricWidth=12
  function output:calcFontSize() self.metricFontSeen=self.fontSize; return self.metricWidth,18 end
  function output:get_width() return layout.chat_width-(2*layout.chat_padding) end
  view:applyLayout(layout)
  eq(layout.chat_wrap_columns==52,false)
  eq(output.metricFontSeen,layout.chat_font)
  eq(output.wrap,math.max(1,math.floor((layout.chat_width-(2*layout.chat_padding)-layout.chat_scrollbar_allowance)/output.metricWidth)))

  local entries={}
  for index=1,20 do entries[index]={category="ESP",timestamp="2026-08-31T13:00:00-04:00",line=string.rep("entry-"..index.." ",40)} end
  view:renderChat(entries,{"ESP"},"ESP"); output.currentScroll=output.renderedEntries[10].first+1
  output.metricWidth=16; view:applyLayout(layout)
  local anchored=output.renderedEntries[10]
  eq(output.wrap,math.max(1,math.floor((layout.chat_width-(2*layout.chat_padding)-layout.chat_scrollbar_allowance)/output.metricWidth))); eq(output.currentScroll>=anchored.first and output.currentScroll<=anchored.last,true)
  output.currentScroll=output.lastLine; output.metricWidth=10; view:applyLayout(layout)
  eq(output.wrap,math.max(1,math.floor((layout.chat_width-(2*layout.chat_padding)-layout.chat_scrollbar_allowance)/output.metricWidth))); eq(output.scrollCalls[#output.scrollCalls],"bottom")
end)

test("chat wrap accepts legacy Geyser setters that return no value",function()
  local layout=require("layout").compute(1920,1080); local view=chatView()
  function view.chat_output:setWrap(value) self.wrap=value end
  local applied,err=view:applyChatWrap(layout)
  eq(applied,true); eq(err,nil); eq(view.chat_output.wrap,layout.chat_wrap_columns)
  eq(view.chat_wrap_columns,layout.chat_wrap_columns); eq(view.chat_font,layout.chat_font)
end)

test("chat wrap reports explicit Geyser setter failures",function()
  local layout=require("layout").compute(1920,1080); local view=chatView()
  function view.chat_output:setWrap() return nil,"manual wrap rejected" end
  local applied,err=view:applyChatWrap(layout)
  eq(applied,nil); eq(err,"manual wrap rejected")
end)
