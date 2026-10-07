local View=require("view")
local ColorPreferences=require("color_preferences")
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
test("names pane distinguishes startup unknown and per-side jade Ok defaults",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  for _,case in ipairs({
    {"unknown","unknown","—","—",theme.muted,theme.muted},
    {"ok","ok","Ok","Ok",theme.jade,theme.jade},
    {"hungry","ok","Hungry","Ok","#d6a84b",theme.jade},
    {"ok","thirsty","Ok","Thirsty",theme.jade,"#d6a84b"},
    {"satiated","quenched","Satiated","Quenched",theme.jade,theme.jade},
  }) do
    local identity=View.identityContent({full_name="Dace Alterac",race="Monitanian",class="Fighter"},theme,layout,
      {hunger={status=case[1]},thirst={status=case[2]}})
    for index,label in ipairs({"Food","Water"}) do
      eq(identity:find(label..": </span><span style='color:"..case[index+4].."'><b>"..case[index+2].."</b>",1,true)~=nil,true)
    end
  end
end)
test("names pane shows Food Satiated and Water Quenched in jade",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  local identity=View.identityContent({full_name="Dace Alterac",race="Monitanian",class="Fighter"},theme,layout,
    {hunger={status="satiated"},thirst={status="quenched"}})
  local visible=identity:gsub("<[^>]+>","")
  eq(visible:find("Food: Satiated",1,true)~=nil,true); eq(visible:find("Water: Quenched",1,true)~=nil,true)
  for _,label in ipairs({"Satiated","Quenched"}) do
    eq(identity:find("<span style='color:"..theme.jade.."'><b>"..label.."</b></span>",1,true)~=nil,true)
  end
  eq(visible:find("Food: OK",1,true),nil)
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
  eq(identity:find("Unknown · Novitiate · 57,000",1,true)~=nil,true); eq(identity:find("Novitiate · Unknown",1,true),nil)
  eq(identity:lower():find("favors",1,true),nil); eq(identity:find("Balanced · Entropic",1,true)~=nil,true)
end)
test("identity keeps grouped favors including zero inline after deity and devotion",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  for _,case in ipairs({{0,"0"},{12,"12"},{1000,"1,000"},{57000,"57,000"},{1234567,"1,234,567"}}) do
    local identity=View.identityContent({full_name="Synthetic Tester",race="Human",class="Fighter",
      deity="Unknown",religion="Novitiate",favors=case[1],religious_balance="Balanced",alignment="order"},theme,layout)
    local visible=identity:gsub("<br>","\n"):gsub("<[^>]+>","")
    eq(visible:find("\nUnknown · Novitiate · "..case[2].."\n",1,true)~=nil,true)
    eq(visible:lower():find("favors",1,true),nil)
    local _,breaks=identity:gsub("<br>",""); eq(breaks,4)
    local _,counts=visible:gsub(case[2],""); eq(counts,1)
  end
end)
test("identity safely renders captured favors before faith and never invents a missing count",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  for _,faith in ipairs({{},{deity="",religion=""},{deity="Unknown"},{religion="Novitiate"}}) do
    local character={full_name="Synthetic Tester",race="Human",class="Fighter",
      deity=faith.deity,religion=faith.religion,favors=57000}
    local identity=View.identityContent(character,theme,layout)
    local visible=identity:gsub("<br>","\n"):gsub("<[^>]+>","")
    eq(visible:find("57,000",1,true)~=nil,true); eq(visible:lower():find("favors",1,true),nil)
    eq(visible:find("nil",1,true),nil); eq(visible:find(" ·  · ",1,true),nil)
    if faith.deity and faith.deity~="" then eq(visible:find("\nUnknown · 57,000\n",1,true)~=nil,true) end
    if faith.religion and faith.religion~="" then eq(visible:find("\nNovitiate · 57,000\n",1,true)~=nil,true) end
    character.favors=nil
    visible=View.identityContent(character,theme,layout):gsub("<br>","\n"):gsub("<[^>]+>","")
    eq(visible:find("57,000",1,true),nil); eq(visible:find("0",1,true),nil); eq(visible:find("nil",1,true),nil)
    eq(visible:lower():find("favors",1,true),nil)
  end
  local identity=View.identityContent({full_name="Synthetic Tester",race="Human",class="Fighter",
    deity="Unknown",religion="Novitiate"},theme,layout)
  local visible=identity:gsub("<br>","\n"):gsub("<[^>]+>","")
  eq(visible:find("\nUnknown · Novitiate\n",1,true)~=nil,true); eq(visible:find("0",1,true),nil)
end)
test("right rail details keep combat information without attributes",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25,details_columns=2}
  local details=View.detailsContent({body_armor=4,or_rating=18,dr=70,stance="Aggressive"},{STR="Good",INT="Low",WIS="Fair"},theme,layout)
  eq(details:find("Stance <b>Aggressive</b>",1,true)~=nil,true)
  eq(details:find("STR",1,true),nil); eq(details:find("INT",1,true),nil); eq(details:find("WIS",1,true),nil)
end)
test("attribute strip shows updated PRE and LUK while retaining old labels for archived info",function()
  local theme={muted="#91a098"}
  local updated=View.attributeStripContent({PRE="Great",LUK="Fair"},theme,{attribute_strip_font=12})
  assert(updated:find("PRE",1,true)); assert(updated:find("LUK",1,true))
  eq(updated:find("VOI",1,true),nil); eq(updated:find("APP",1,true),nil)
  local archived=View.attributeStripContent({VOI="Good",APP="Low"},theme,{attribute_strip_font=12})
  assert(archived:find("VOI",1,true)); assert(archived:find("APP",1,true))
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
test("narrow Combat stacks every field with readable explicit sizing and escaped values",function()
  local layout=require("layout").compute(960,1000)
  local html=View.detailsContent({body_armor=100,stance="Aggressive",or_rating=125,dr=315},nil,{accent="#d8ae53"},layout,{roundtime=12,position=-1,standing=true})
  eq(html:find("<table",1,true),nil); assert(html:find("font-size:13px",1,true))
  for _,text in ipairs({"COMBAT","Armor <b>100%</b>","Stance<br><b>Aggressive</b>","OR <b>125</b>","Roundtime<br><b>12</b>","DR <b>315</b>","Position <b>-1</b>","Standing"}) do assert(html:find(text,1,true),text) end
  local _,breaks=html:gsub("<br>",""); eq(breaks+2<=require("layout").detailsCardRows(1),true)
  local escaped=View.detailsContent({stance="<bad&stance>"},nil,{accent="#d8ae53"},layout,{})
  assert(escaped:find("&lt;bad&amp;stance&gt;",1,true)); eq(escaped:find("<bad",1,true),nil)
  assert(escaped:find("OR <b>—</b>",1,true)); assert(escaped:find("DR <b>—</b>",1,true)); assert(escaped:find("READY",1,true))
end)

local function fakeGeyser(glyphWidth,scrollbarWidth,measureFails)
  glyphWidth=tonumber(glyphWidth) or 6
  local function widget(cons,parent,kind)
    local item={name=cons.name,parent=parent,container=parent,kind=kind,visible=true,echoes={},currentScroll=0,lastLine=0}
    function item:setStyleSheet(value) self.style=value end
    function item:move(x,y) self.x=x; self.y=y end
    function item:resize(width,height) self.width=width; self.height=height end
    function item:get_width() return self.width end
    function item:show() self.visible=true; self.showCalls=(self.showCalls or 0)+1 end
    function item:hide() self.visible=false end
    function item:raise() self.raised=true end
    function item:delete() self.deleted=true end
    function item:setClickCallback(callback) self.click=callback end
    function item:setReleaseCallback(callback) self.release=callback end
    function item:setAction(callback) self.action=callback end
    function item:setToolTip(value) self.tooltip=value end
    function item:print(value) self.text=tostring(value) end
    function item:getText() return self.text or "" end
    function item:echo(value,color)
      self.echo_color=color
      if self.kind=="console" then
        self.echoes[#self.echoes+1]=value
        self.echoFormats=self.echoFormats or {}
        self.echoFormats[#self.echoFormats+1]={foreground=self.currentFg,background=self.currentBg,bold=self.currentBold,underline=self.currentUnderline}
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
    function item:setFgColor(r,g,b) self.currentFg=type(r)=="string" and r:upper() or string.format("#%02X%02X%02X",r,g,b) end
    function item:setBgColor(r,g,b) self.currentBg=type(r)=="string" and r:upper() or string.format("#%02X%02X%02X",r,g,b) end
    function item:setBold(value) self.currentBold=value end
    function item:setUnderline(value) self.currentUnderline=value end
    function item:resetFormat() self.currentFg=nil; self.currentBg=nil; self.currentBold=nil; self.currentUnderline=nil; self.formatResets=(self.formatResets or 0)+1 end
    function item:clear() self.clearCalls=(self.clearCalls or 0)+1; self.echoes={}; self.echoFormats={}; self.hechoes={}; self.lastLine=0; self.renderedEntries={} end
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

local function chatView(glyphWidth,scrollbarWidth,measureFails,chatVisible,chatSounds,display)
  local original=Geyser; Geyser=fakeGeyser(glyphWidth,scrollbarWidth,measureFails)
  local view=View.new({version="0.3.30",view_contract=VIEW_CONTRACT,view_settings_contract=SETTINGS_CONTRACT,theme={background="#080b0a",panel="#0d1210",border="#423825",text="#d7d0bf",muted="#75857c",accent="#e0b56c",jade="#79b386",hp="#ba5147",fatigue="#8bad4e"},chat={timestamps=true,visible=chatVisible,sounds=chatSounds},display=display})
  Geyser=original
  return view
end

local function chatWidgets(view)
  local widgets={view.chat_container,view.chat_bg,view.chat_tabs,view.chat_output}
  for _,button in ipairs(view.chat_buttons or {}) do widgets[#widgets+1]=button end
  return widgets
end
local function checkChatVisible(view,wanted)
  for _,widget in ipairs(chatWidgets(view)) do eq(widget.visible,wanted) end
end

test("chat visibility defaults on and applies saved off before initial layout",function()
  local view=chatView(); eq(view.chat_visible,true); checkChatVisible(view,true)
  view=chatView(nil,nil,nil,false); eq(view.chat_visible,false); checkChatVisible(view,false)
  eq(view.chat_container.height,0); eq(view.chat_output.height,0)
  view:renderChat({{category="ROOM",line="Captured while hidden"}},{"ROOM"},"ROOM")
  checkChatVisible(view,false); eq(#view.chat_entries,1); eq(#view.chat_output.echoes,1)
  eq(view:setChatVisible(true),true); checkChatVisible(view,true); eq(#view.chat_buttons>0,true)
  eq(view.chat_active_filter,"ROOM"); eq(#view.chat_entries,1)
end)

test("chat visibility toggle accepts saved false and stays reachable through Options",function()
  local view=chatView(); local calls={}
  view:setOptionsActionCallback(function(action,key,wanted)
    calls[#calls+1]={action=action,key=key,wanted=wanted}; return wanted
  end)
  view:applyLayout(require("layout").compute(320,260)); view:renderChat({},{"QUEST"},"ALL")
  view.color_toggle.click(); view.option_action_buttons.chat_settings.click()
  local button=view.chat_settings_visibility
  eq(button.parent,view.chat_settings_content); eq(button.visible,true)
  assert(button.message:find("SHOW CHATBOX: ON",1,true))
  assert(view.chat_settings_text.message:find("Capture and history continue",1,true))
  assert(view.chat_settings_text.message:find("main console",1,true))
  eq(button.click(),false); eq(#calls,1); eq(calls[1].action,"chat_visibility"); eq(calls[1].key,nil); eq(calls[1].wanted,false)
  checkChatVisible(view,false); eq(view.chat_settings_panel.visible,true)
  assert(button.message:find("SHOW CHATBOX: OFF",1,true))
  view.chat_settings_close.click(); eq(button.visible,false); eq(view.color_toggle.visible,true)
  view.color_toggle.click(); eq(view.option_action_buttons.chat_settings.visible,true)
  view.option_action_buttons.chat_settings.click(); eq(button.visible,true); checkChatVisible(view,false)
  eq(button.click(),true); eq(#calls,2); eq(calls[2].wanted,true)
  checkChatVisible(view,true); assert(button.message:find("SHOW CHATBOX: ON",1,true))
  eq(view.chat_settings_panel.visible,true)
end)

test("failed chat visibility saves keep the prior state and show the error",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view:renderChat({},{},"ALL")
  view:setOptionsActionCallback(function(action,key,wanted)
    eq(action,"chat_visibility"); eq(key,nil); eq(wanted,view.chat_visible==false)
    return nil,"disk <full>"
  end)
  for _,visible in ipairs({true,false}) do
    view:setChatVisible(visible); view:showChatSettings()
    local ok,err=view.chat_settings_visibility.click()
    eq(ok,nil); eq(err,"disk <full>"); eq(view.chat_visible,visible); checkChatVisible(view,visible)
    eq(view.chat_settings_panel.visible,true); eq(view.chat_settings_visibility.visible,true)
    assert(view.chat_settings_visibility.message:find("SHOW CHATBOX: "..(visible and "ON" or "OFF"),1,true))
    assert(view.chat_settings_status.message:find("disk &lt;full&gt;",1,true))
  end
  view:setOptionsActionCallback(nil)
  local ok,err=view.chat_settings_visibility.click()
  eq(ok,nil); assert(err:find("unavailable",1,true)); checkChatVisible(view,false)
  assert(view.chat_settings_status.message:find("unavailable",1,true))
end)

test("hidden chat never shows widgets during resize tab rendering or full HUD updates",function()
  local Layout=require("layout"); local view=chatView()
  view:applyLayout(Layout.compute(320,260)); view:renderChat({},{"QUEST","EVENTS"},"ALL")
  assert(view.chat_overflow_button); eq(view:setChatVisible(false),false)
  local widgets=chatWidgets(view); for _,widget in ipairs(widgets) do widget.showCalls=0 end
  local entries={{category="ESP",line="First hidden message"},{category="SECIAN",line="Second hidden message"}}
  for _,size in ipairs({{1920,1080},{320,260},{1000,700},{760,700},{1920,1080}}) do
    -- The view must also resist a stale visible layout while setting sync runs.
    view:applyLayout(Layout.compute(size[1],size[2]))
    view:renderChat(entries,{"ESP","SECIAN","QUEST"},"SECIAN")
    view:renderChatTabs(view.chat_categories,view.chat_active_filter)
    view:update(require("state").normalize({}))
    checkChatVisible(view,false); eq(view.chat_container.height,0); eq(view.chat_output.height,0)
    eq(view.color_toggle.visible,true); eq(#view.chat_entries,2); eq(#view.chat_output.echoes,2)
    for _,widget in ipairs(widgets) do eq(widget.showCalls,0); eq(widget.deleted,nil) end
  end
  eq(view:setChatVisible(true),true); checkChatVisible(view,true)
  eq(view.chat_container.height,view.layout.chat_height); eq(view.chat_active_filter,"SECIAN")
  eq(view.chat_filter_order[#view.chat_filter_order],"QUEST"); eq(#view.chat_entries,2)
  local found=false; for _,button in ipairs(view.chat_buttons) do if button.category=="SECIAN" then found=true end end
  eq(found,true)
end)

test("explicit hidden layout overrides visibility sync and survives rendering",function()
  local Layout=require("layout"); local view=chatView(); local layout=Layout.compute(1200,800)
  layout.chat_visible=false; layout.chat_height=0; layout.chat_output_height=0; layout.console_top=layout.header_height
  view:applyLayout(layout); checkChatVisible(view,false)
  view:setChatVisible(true); view:renderChat({{category="ROOM",line="Still captured"}},{},"ALL")
  checkChatVisible(view,false); eq(layout.chat_height,0); eq(layout.chat_output_height,0); eq(layout.console_top,layout.header_height)
  view:renderChatTabs({"EVENTS","CUSTOM"},"CUSTOM"); checkChatVisible(view,false)
  eq(View.validateReusable(view,view.settings),true)
  view:applyLayout(Layout.compute(1200,800)); checkChatVisible(view,true)
  eq(#view.chat_entries,1); eq(#view.chat_buttons>0,true)
  eq(view.chat_active_filter,"CUSTOM"); eq(view.chat_filter_order[#view.chat_filter_order],"CUSTOM")
  local found=false; for _,button in ipairs(view.chat_buttons) do if button.category=="CUSTOM" then found=true end end
  eq(found,true)
end)

test("preserved view adoption reapplies saved chat visibility after showing the root",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view:renderChat({{category="ROOM",line="Kept"}},{},"ALL")
  view:showChatSettings(); local output=view.chat_output
  function view.root:show() self.visible=true; for _,widget in ipairs(chatWidgets(view)) do widget:show() end end
  local settings={view_contract=VIEW_CONTRACT,view_settings_contract=SETTINGS_CONTRACT,theme=view.settings.theme,chat={visible=false}}
  eq(view:prepareForReuse(settings),true); checkChatVisible(view,false)
  eq(View.validateReusable(view,settings),true)
  eq(view.chat_settings_visibility.visible,false); eq(view.chat_output,output); eq(#view.chat_entries,1)
  view:applyLayout(require("layout").compute(1200,800)); checkChatVisible(view,false)
  settings.chat.visible=true; eq(view:prepareForReuse(settings),true); checkChatVisible(view,true)
end)

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

local ColorStyles=require("color_styles")
local function colorEditor(config,id,width,height)
  local view=chatView(); view:setColorStyles(config or {})
  view:applyLayout(require("layout").compute(width or 1200,height or 800)); view:showColorSettings()
  view.color_settings_styles_tab.click(); assert(view.color_style_rows[id or "room"].click())
  return view
end
local function customEditor(config,width,height)
  local view=chatView(); view:setColorStyles(config or {})
  view:applyLayout(require("layout").compute(width or 1200,height or 800)); view:showColorSettings()
  assert(view.color_settings_custom_tab.click())
  return view
end
local function customRules(count)
  local rules={}
  for index=1,count do
    rules[index]={phrase="Phrase "..index,foreground="#FFFFFF",background=false,bold=false,underline=false,enabled=true}
  end
  return rules
end
test("custom phrases have a separate saved catalog and escaped labels",function()
  local config={custom_rules={{phrase="a <gate> & sign",foreground="#12AB34",background=false,bold=false,underline=false,enabled=true},{phrase="Hidden door",foreground="#AABBCC",background="#112233",bold=true,underline=true,enabled=false}}}
  local view=customEditor(config,420,360)
  eq(view.color_settings_page,"custom"); eq(view.custom_highlight_list.kind,"scrollbox")
  eq(#view.custom_highlight_rules,2); eq(#view.custom_highlight_rows,2)
  eq(view.custom_highlight_rows[1].parent,view.custom_highlight_list)
  assert(view.custom_highlight_rows[1].message:find("a &lt;gate&gt; &amp; sign",1,true))
  eq(view.custom_highlight_rows[1].message:find("<gate>",1,true),nil)
  assert(view.custom_highlight_rows[2].message:find("(off)",1,true))
  config.custom_rules[1].phrase="changed"; eq(view.custom_highlight_rules[1].phrase,"a <gate> & sign")
  assert(view.custom_highlight_rows[2].click()); eq(view.custom_highlight_selected,"Hidden door")
  eq(view.custom_highlight_phrase.text,"Hidden door"); eq(view.custom_highlight_fields.background.input.text,"#112233")
  eq(view.custom_highlight_toggles.bold.visible,true); eq(view.custom_highlight_delete.visible,true)
  view.color_settings_styles_tab.click(); eq(view.color_settings_page,"styles")
  eq(view.custom_highlight_draft,nil); eq(view.color_style_rows.room.visible,true)
end)
test("custom phrase editor stays bounded and scrollable from small to wide windows",function()
  local view=customEditor({},320,260); assert(view.custom_highlight_add.click())
  local phraseField=view.custom_highlight_phrase
  for _,size in ipairs({{320,260},{420,280},{560,360},{760,700},{1920,1080}}) do
    view:applyLayout(require("layout").compute(size[1],size[2]))
    local panel=view.color_settings_panel
    eq(panel.x>=0 and panel.y>=0,true); eq(panel.x+panel.width<=size[1] and panel.y+panel.height<=size[2],true)
    eq(view.custom_highlight_phrase,phraseField); eq(view.custom_highlight_content.kind,"scrollbox")
    eq(view.custom_highlight_content.y+view.custom_highlight_content.height<=view.custom_highlight_save.y,true)
    eq(view.custom_highlight_status.y+view.custom_highlight_status.height<=view.custom_highlight_content.y,true)
    for _,widget in ipairs(view.color_style_widgets) do
      if widget.visible and (widget.parent==panel or widget.parent==view.custom_highlight_content) then
        eq(widget.x>=0 and widget.y>=0,true)
        eq(widget.x+widget.width<=widget.parent.width,true)
        if widget.parent==panel then eq(widget.y+widget.height<=panel.height,true) end
      end
    end
    if size[2]<400 then eq(view.custom_highlight_content.content_height>view.custom_highlight_content.height,true) end
  end
  view.custom_highlight_cancel.click(); eq(view.color_settings_page,"custom")
  view:applyLayout(require("layout").compute(320,260))
  eq(view.custom_highlight_list.content_height>view.custom_highlight_list.height,true)
  eq(view.color_settings_custom_tab.message:find("CUSTOM",1,true)~=nil,true)
end)
test("custom add and edit save complete detached rules only after success",function()
  local view=customEditor(); local calls={}
  view:setCustomHighlightCallbacks(function(oldPhrase,rule)
    calls[#calls+1]={old=oldPhrase,rule=rule}
    rule.foreground="#000000"; return true
  end,function() return true end)
  view.custom_highlight_add.click(); view.custom_highlight_phrase:print("  hidden gate  ")
  view.custom_highlight_fields.foreground.input.action(" #55ccaa ")
  view.custom_highlight_palette_targets.background.click(); view.custom_highlight_swatches[4].click()
  view.custom_highlight_toggles.bold.click(); view.custom_highlight_toggles.underline.click()
  eq(#calls,0); eq(view.custom_highlight_fields.background.input.text,"#000000")
  assert(view.custom_highlight_save.click()); eq(#calls,1); eq(calls[1].old,nil)
  eq(calls[1].rule.phrase,"hidden gate"); eq(calls[1].rule.foreground,"#000000")
  eq(view.custom_highlight_rules[1].foreground,"#55CCAA"); eq(view.custom_highlight_rules[1].background,"#000000")
  eq(view.custom_highlight_rules[1].bold,true); eq(view.custom_highlight_rules[1].underline,true)
  assert(view.custom_highlight_status.message:find("Saved.",1,true))
  view.custom_highlight_phrase:print("secret gate"); view.custom_highlight_fields.foreground.input:print("#ABCDEF")
  assert(view.custom_highlight_save.click()); eq(calls[2].old,"hidden gate")
  eq(#view.custom_highlight_rules,1); eq(view.custom_highlight_rules[1].phrase,"secret gate")
  eq(view.custom_highlight_rules[1].foreground,"#ABCDEF")
end)
test("custom phrase bounds uniqueness and unsafe colors reject before callbacks",function()
  local view=customEditor({custom_rules={{phrase="Known",foreground="#123456",background=false,bold=false,underline=false,enabled=true}}})
  local calls=0; view:setCustomHighlightCallbacks(function() calls=calls+1; return true end,function() return true end)
  view.custom_highlight_add.click()
  for _,phrase in ipairs({"",string.rep("x",121),"bad\nphrase","known"}) do
    view.custom_highlight_phrase:print(phrase); local ok=view.custom_highlight_save.click(); eq(ok,nil); eq(calls,0)
  end
  view.custom_highlight_phrase:print("<b>safe & literal</b>")
  view:previewCustomHighlight()
  assert(view.custom_highlight_preview.message:find("&lt;b&gt;safe &amp; literal&lt;/b&gt;",1,true))
  view.custom_highlight_fields.foreground.input:print("#123456;background:red")
  eq(view.custom_highlight_save.click(),nil); eq(calls,0)
  eq(view.custom_highlight_preview.style:find("background:red",1,true),nil)
  view.custom_highlight_fields.foreground.input:print("#ABCDEF")
  view.custom_highlight_toggles.background_enabled.click(); view.custom_highlight_fields.background.input:print("url(evil)")
  eq(view.custom_highlight_save.click(),nil); eq(calls,0)
  view.custom_highlight_toggles.background_enabled.click(); assert(view.custom_highlight_save.click()); eq(calls,1)
end)
test("custom catalog keeps all 1000 rows accessible and reuses widgets across layouts",function()
  eq(ColorPreferences.MAX_CUSTOM_RULES,1000)
  local rules=customRules(1000)
  local view=customEditor({custom_rules=rules},320,260)
  local rows={}; local widgetCount=#view.color_style_widgets
  eq(#view.custom_highlight_rules,1000); eq(#view.custom_highlight_rows,1000)
  assert(view.custom_highlight_help.message:find("Up to 1000 saved rules.",1,true))
  assert(view.custom_highlight_count.message:find("1000 / 1000 saved",1,true))
  for index,row in ipairs(view.custom_highlight_rows) do rows[index]=row end
  for _,size in ipairs({{320,260},{420,280},{560,360},{760,700},{1920,1080}}) do
    view:applyLayout(require("layout").compute(size[1],size[2]))
    local panel,list=view.color_settings_panel,view.custom_highlight_list
    eq(panel.x>=0 and panel.y>=0,true)
    eq(panel.x+panel.width<=size[1] and panel.y+panel.height<=size[2],true)
    eq(list.kind,"scrollbox"); eq(list.y+list.height<=panel.height,true)
    eq(list.content_height,112+1000*38); eq(list.content_height>list.height,true)
    for index,row in ipairs(view.custom_highlight_rows) do
      eq(row,rows[index]); eq(row.container,list); eq(row.visible,true)
      eq(row.y,112+(index-1)*38); eq(row.y+row.height<=list.content_height,true)
      eq(row.x>=0 and row.x+row.width<=list.width,true)
      assert(row.message:find(rules[index].phrase.." &nbsp;",1,true))
    end
    eq(#view.color_style_widgets,widgetCount)
  end
  for index,row in ipairs(rows) do
    assert(row.click()); eq(view.custom_highlight_selected,rules[index].phrase)
    eq(view.custom_highlight_phrase.text,rules[index].phrase)
    assert(view.custom_highlight_cancel.click())
  end
  view:setColorStyles({custom_rules=rules})
  eq(#view.color_style_widgets,widgetCount)
  for index,row in ipairs(rows) do eq(view.custom_highlight_rows[index],row) end
end)
test("custom snapshots retain 1000 valid unique rules and truncate the 1001st",function()
  local rules=customRules(1001)
  table.insert(rules,1,{phrase="invalid",foreground="url(evil)",background=false})
  table.insert(rules,3,{phrase="pHrAsE 1",foreground="#123456",background=false})
  local view=customEditor({custom_rules=rules})
  eq(#view.custom_highlight_rules,1000); eq(#view.custom_highlight_rows,1000)
  eq(view.custom_highlight_rules[1].phrase,"Phrase 1")
  eq(view.custom_highlight_rules[1].foreground,"#FFFFFF")
  eq(view.custom_highlight_rules[1000].phrase,"Phrase 1000")
  assert(view.custom_highlight_rows[1000].click())
  eq(view.custom_highlight_phrase.text,"Phrase 1000")
  eq(view:selectCustomHighlight("Phrase 1001"),nil)
end)
test("custom add saves the 1000th rule and rejects 1001st adds and stale saves",function()
  local view=customEditor({custom_rules=customRules(999)}); local calls=0
  view:setCustomHighlightCallbacks(function(oldPhrase,rule)
    eq(oldPhrase,nil); eq(rule.phrase,"Phrase 1000"); calls=calls+1; return true
  end,function() return true end)
  assert(view.custom_highlight_count.message:find("999 / 1000 saved",1,true))
  assert(view.custom_highlight_add.click()); view.custom_highlight_phrase:print("Phrase 1000")
  assert(view.custom_highlight_save.click()); eq(calls,1)
  eq(#view.custom_highlight_rules,1000); eq(#view.custom_highlight_rows,1000)
  eq(view.custom_highlight_rules[1000].phrase,"Phrase 1000")
  view.custom_highlight_cancel.click()
  assert(view.custom_highlight_count.message:find("1000 / 1000 saved",1,true))
  local ok,err=view.custom_highlight_add.click()
  eq(ok,nil); assert(err:find("1000-rule limit",1,true)); eq(calls,1)
  eq(view.custom_highlight_draft,nil); eq(#view.custom_highlight_rules,1000)
  -- Another snapshot can fill the last slot while an add draft is open.
  view:setColorStyles({custom_rules=customRules(999)})
  assert(view.custom_highlight_add.click()); view.custom_highlight_phrase:print("Phrase 1001")
  view:setColorStyles({custom_rules=customRules(1000)})
  ok,err=view.custom_highlight_save.click()
  eq(ok,nil); assert(err:find("1000-rule limit",1,true)); eq(calls,1)
  eq(#view.custom_highlight_rules,1000); eq(view.custom_highlight_phrase.text,"Phrase 1001")
  assert(view.custom_highlight_draft)
end)
test("custom edits and confirmed deletes work at 1000 and reuse the freed row",function()
  local view=customEditor({custom_rules=customRules(1000)}); local saves,deletes=0,0
  local lastRow=view.custom_highlight_rows[1000]; local widgetCount=#view.color_style_widgets
  view:setCustomHighlightCallbacks(function(oldPhrase,rule)
    saves=saves+1
    if saves==1 then eq(oldPhrase,"Phrase 1000"); eq(rule.phrase,"Renamed last phrase")
    else eq(oldPhrase,nil); eq(rule.phrase,"Replacement phrase") end
    return true
  end,function(phrase)
    eq(phrase,"Renamed last phrase"); deletes=deletes+1; return true
  end)
  assert(lastRow.click()); view.custom_highlight_phrase:print("Renamed last phrase")
  view.custom_highlight_fields.foreground.input:print("#ABCDEF")
  assert(view.custom_highlight_save.click()); eq(saves,1); eq(#view.custom_highlight_rules,1000)
  eq(view.custom_highlight_rules[1000].phrase,"Renamed last phrase")
  eq(view.custom_highlight_rules[1000].foreground,"#ABCDEF")
  assert(view.custom_highlight_delete.click()); eq(deletes,0); eq(#view.custom_highlight_rules,1000)
  assert(view.custom_highlight_delete.click()); eq(deletes,1); eq(#view.custom_highlight_rules,999)
  eq(lastRow.visible,false); eq(view.custom_highlight_rules[999].phrase,"Phrase 999")
  assert(view.custom_highlight_count.message:find("999 / 1000 saved",1,true))
  assert(view.custom_highlight_add.click()); view.custom_highlight_phrase:print("Replacement phrase")
  assert(view.custom_highlight_save.click()); eq(saves,2); eq(#view.custom_highlight_rules,1000)
  view.custom_highlight_cancel.click()
  eq(view.custom_highlight_rows[1000],lastRow); eq(lastRow.visible,true)
  eq(#view.color_style_widgets,widgetCount)
  assert(lastRow.click()); eq(view.custom_highlight_phrase.text,"Replacement phrase")
end)
test("preserved 1000-rule views validate actual containers and retain rows through reuse",function()
  local view=customEditor({custom_rules=customRules(1000)},420,280)
  local superclass={name="WindowClass"}; local rows={}
  for index,row in ipairs(view.custom_highlight_rows) do
    rows[index]=row; row.parent=nil; setmetatable(row,{__index={parent=superclass}})
    row.clickCallback=row.click; row.click=nil
    eq(row.parent,superclass); eq(row.container,view.custom_highlight_list)
  end
  assert(View.validateReusable(view,view.settings))
  local last=rows[1000]
  for _,container in ipairs({false,view.root}) do
    last.container=container or nil
    local ok,err=View.validateReusable(view,view.settings)
    eq(ok,nil); assert(err:find("custom highlight row",1,true))
  end
  last.container=view.custom_highlight_list
  view.custom_highlight_rules[1001]=customRules(1001)[1001]
  local ok,err=View.validateReusable(view,view.settings)
  eq(ok,nil); assert(err:find("custom highlights are incomplete",1,true))
  view.custom_highlight_rules[1001]=nil
  assert(last.clickCallback()); view.custom_highlight_phrase:print("Unsaved rename")
  view:setCustomHighlightCallbacks(function() error("retired save") end,function() error("retired delete") end)
  assert(view:prepareForReuse(view.settings))
  eq(view.custom_highlight_save_callback,nil); eq(view.custom_highlight_delete_callback,nil)
  eq(view.custom_highlight_draft,nil); eq(#view.custom_highlight_rules,1000)
  assert(View.validateReusable(view,view.settings))
  view:showColorSettings(); view.color_settings_custom_tab.click()
  for index,row in ipairs(rows) do
    eq(view.custom_highlight_rows[index],row); eq(row.visible,true)
    eq(row.container,view.custom_highlight_list)
  end
  assert(last.clickCallback()); eq(view.custom_highlight_phrase.text,"Phrase 1000")
  view:delete()
end)
test("custom callback failures retain saved state and draft even with an in-flight snapshot",function()
  local view=customEditor(); view.custom_highlight_add.click(); view.custom_highlight_phrase:print("secret <door>")
  view.custom_highlight_fields.foreground.input:print("#ABCDEF")
  view:setCustomHighlightCallbacks(function(_,rule)
    view:setColorStyles({custom_rules={rule}}); return nil,"disk <full>"
  end,function() return true end)
  local ok,err=view.custom_highlight_save.click(); eq(ok,nil); assert(err:find("disk <full>",1,true))
  eq(#view.custom_highlight_rules,0); eq(view.color_styles_config.custom_rules,nil)
  eq(view.custom_highlight_phrase.text,"secret <door>"); eq(view.custom_highlight_fields.foreground.input.text,"#ABCDEF")
  assert(view.custom_highlight_status.message:find("disk &lt;full&gt;",1,true))
  view:setCustomHighlightCallbacks(function() error("save broke") end,function() return true end)
  eq(view.custom_highlight_save.click(),nil); eq(#view.custom_highlight_rules,0)
  view:setCustomHighlightCallbacks(nil,nil); eq(view.custom_highlight_save.click(),nil)
  view:setCustomHighlightCallbacks(function(_,rule) view:setColorStyles({custom_rules={rule}}); return true end,nil)
  assert(view.custom_highlight_save.click()); eq(#view.custom_highlight_rules,1)
  eq(view.custom_highlight_rules[1].phrase,"secret <door>")
end)
test("custom deletion requires confirmation and failed deletion preserves the rule",function()
  local rule={phrase="secret gate",foreground="#FFFFFF",background=false,bold=false,underline=false,enabled=true}
  local view=customEditor({custom_rules={rule}}); local calls=0
  view:setCustomHighlightCallbacks(function() return true end,function(phrase)
    eq(phrase,"secret gate"); calls=calls+1; view:setColorStyles({custom_rules={}}); return nil,"disk <full>"
  end)
  view.custom_highlight_rows[1].click()
  assert(view.custom_highlight_delete.click()); eq(calls,0)
  assert(view.custom_highlight_delete.message:find("CONFIRM DELETE",1,true))
  eq(view.custom_highlight_delete.click(),nil); eq(calls,1); eq(#view.custom_highlight_rules,1)
  assert(view.custom_highlight_status.message:find("disk &lt;full&gt;",1,true))
  view.custom_highlight_cancel.click(); view.custom_highlight_rows[1].click()
  view:setCustomHighlightCallbacks(function() return true end,function(phrase)
    calls=calls+1; view:setColorStyles({custom_rules={}}); return true
  end)
  view.custom_highlight_delete.click(); assert(view.custom_highlight_delete.click())
  eq(calls,2); eq(#view.custom_highlight_rules,0); eq(view.color_settings_page,"custom")
  assert(view.custom_highlight_status.message:find("Deleted",1,true)); eq(view.custom_highlight_rows[1].visible,false)
end)
test("custom controls never send a game command and hide with Color Settings",function()
  local view=customEditor(); local previous=rawget(_G,"send"); local sends=0
  _G.send=function() sends=sends+1 end
  local ok,err=pcall(function()
    view.custom_highlight_add.click(); view.custom_highlight_phrase.action("word")
    view.custom_highlight_fields.foreground.input.action("#AABBCC")
    view.custom_highlight_fields.background.input.action("#112233")
    view.custom_highlight_save.click(); view.color_settings_close.click()
    eq(view.color_settings_visible,false); eq(view.custom_highlight_draft,nil)
    for _,widget in ipairs(view:colorSettingsWidgets()) do eq(widget.visible,false) end
    eq(sends,0)
  end)
  _G.send=previous; if not ok then error(err,0) end
end)
test("custom highlight handoff keeps saved rows but retires callbacks and drafts",function()
  local view=customEditor({custom_rules={{phrase="a gate",foreground="#123456",background=false,bold=false,underline=false,enabled=true}}},420,280)
  view.custom_highlight_rows[1].click(); view.custom_highlight_phrase:print("unsaved rename")
  view:setCustomHighlightCallbacks(function() error("retired save") end,function() error("retired delete") end)
  assert(View.validateReusable(view,view.settings))
  assert(view:prepareForReuse(view.settings)); eq(view.custom_highlight_save_callback,nil); eq(view.custom_highlight_delete_callback,nil)
  eq(view.custom_highlight_draft,nil); eq(view.custom_highlight_rules[1].phrase,"a gate")
  view:showColorSettings(); view.color_settings_custom_tab.click(); view.custom_highlight_rows[1].click()
  eq(view.custom_highlight_phrase.text,"a gate")
  view:delete()
end)
test("color style catalog includes every registry entry and selectable race and class groups",function()
  local view=chatView(); view:applyLayout(require("layout").compute(420,360)); view:showColorSettings()
  view.color_settings_styles_tab.click(); eq(view.color_style_catalog.kind,"scrollbox")
  eq(view.color_style_catalog.content_height>view.color_style_catalog.height,true)
  for _,entry in ipairs(ColorStyles.entries()) do
    local row=view.color_style_rows[entry.id]; assert(row,entry.id); eq(row.parent,view.color_style_catalog); eq(row.visible,true)
    assert(row.click()); eq(view.color_style_selected,entry.id); eq(view.color_style_fields.foreground.input.text,ColorStyles.defaults(entry.id).foreground)
    view.color_style_cancel.click()
  end
  for _,group in ipairs({"Races","Classes"}) do
    view.color_style_group_buttons[group].click()
    for _,entry in ipairs(ColorStyles.entries()) do eq(view.color_style_rows[entry.id].visible,entry.group==group) end
  end
  view.color_style_group_buttons.all.click(); eq(view.color_style_rows.darkness.visible,true)
  view.color_settings_groups_tab.click(); for _,key in ipairs(view.color_option_order) do eq(view.color_option_buttons[key].visible,true) end
  eq(view:selectColorStyle("not-a-style"),nil); eq(view:selectColorStyleGroup("not-a-group"),nil)
end)
test("color editor and catalog stay bounded at compact and wide sizes with scroll access",function()
  local view=colorEditor({},"notice"); local field=view.color_style_fields.foreground.input
  for _,size in ipairs({{320,260},{420,280},{560,360},{760,700},{1200,800},{1920,1080}}) do
    view:applyLayout(require("layout").compute(size[1],size[2]))
    local panel=view.color_settings_panel
    eq(panel.x>=0 and panel.y>=0,true); eq(panel.x+panel.width<=size[1] and panel.y+panel.height<=size[2],true)
    eq(view.color_style_fields.foreground.input,field)
    eq(view.color_style_content.kind,"scrollbox"); eq(view.color_style_content.height>=60,true)
    for _,widget in ipairs(view.color_style_widgets) do
      if widget.visible then
        eq(widget.x>=0 and widget.y>=0,true)
        eq(widget.x+widget.width<=widget.parent.width,true)
        if widget.parent==panel then eq(widget.y+widget.height<=panel.height,true) end
      end
    end
    eq(view.color_style_content.y+view.color_style_content.height<=view.color_style_save.y,true)
    eq(view.color_style_status.y+view.color_style_status.height<=view.color_style_content.y,true)
    eq(view.color_style_reset.x+view.color_style_reset.width<view.color_style_cancel.x,true)
    eq(view.color_style_cancel.x+view.color_style_cancel.width<view.color_style_save.x,true)
    if size[2]<400 then eq(view.color_style_content.content_height>view.color_style_content.height,true) end
    view.color_style_cancel.click()
    for _,entry in ipairs(ColorStyles.entries()) do local row=view.color_style_rows[entry.id]; eq(row.x+row.width<=view.color_style_catalog.width-18,true); eq(row.height>=28,true) end
    view.color_style_rows.notice.click()
  end
end)
test("color snapshots are detached and retain raw editor drafts through refresh and resize",function()
  local config={enabled=true,room_color={12,34,56},styles={gold={foreground="#123456"}}}
  local view=colorEditor(config); eq(view.color_style_fields.foreground.input.text,"#0C2238")
  config.styles.gold.foreground="#ABCDEF"; eq(view.color_style_saved.gold.foreground,"#123456")
  view.color_style_fields.foreground.input:print("unfinished hex")
  view.color_style_fields.background.input:print("#112233"); view.color_style_toggles.background_enabled.click(); view.color_style_toggles.bold.click()
  view:setColorStyles({enabled=true,room_enabled=false,styles={room={foreground="#654321"}}})
  for _,size in ipairs({{320,260},{1920,1080},{420,360}}) do
    view:applyLayout(require("layout").compute(size[1],size[2])); eq(view.color_style_fields.foreground.input.text,"unfinished hex")
    eq(view.color_style_fields.background.input.text,"#112233"); eq(view.color_style_draft.bold,true); eq(view.color_style_draft.background_enabled,true)
  end
  eq(view.color_style_saved.room.foreground,"#654321"); view.color_style_cancel.click(); view.color_style_rows.room.click()
  eq(view.color_style_fields.foreground.input.text,"#654321"); assert(view.color_style_status.message:find("category is currently off",1,true))
end)
test("color hex validation rejects malformed text without saving or injecting preview styles",function()
  local view=colorEditor(); local calls=0; view:setColorStyleCallback(function() calls=calls+1; return true end)
  local original=view.color_style_saved.room.foreground; local preview=view.color_style_preview.style
  for _,value in ipairs({"", "red", "#123", "#1234567", "#GGGGGG", "#123456;background:red", "<b>red</b>", "#123456\n#654321"}) do
    view.color_style_fields.foreground.input:print(value); local ok,err=view.color_style_save.click()
    eq(ok,nil); assert(err:find("Text color",1,true)); eq(calls,0); eq(view.color_style_saved.room.foreground,original)
    eq(view.color_style_preview.style,preview); eq(view.color_style_status.visible,true)
  end
  view.color_style_fields.foreground.input.action("  #a1b2c3  "); eq(calls,0); assert(view.color_style_preview.style:find("#A1B2C3",1,true))
  view.color_style_toggles.background_enabled.click(); view.color_style_fields.background.input:print("no")
  local ok,err=view.color_style_save.click(); eq(ok,nil); assert(err:find("Highlight color",1,true)); eq(calls,0)
  view.color_style_toggles.background_enabled.click(); assert(view.color_style_save.click()); eq(calls,1)
  eq(view.color_style_saved.room.foreground,"#A1B2C3"); eq(view.color_style_saved.room.background,false)
end)
test("color palette previews foreground highlight emphasis and enabled state without applying",function()
  local view=colorEditor(); local calls=0; view:setColorStyleCallback(function() calls=calls+1; return true end)
  view.color_style_swatches[1].click(); eq(view.color_style_fields.foreground.input.text,"#FFFFFF")
  view.color_style_palette_targets.background.click(); view.color_style_swatches[4].click()
  eq(view.color_style_draft.background_enabled,true); eq(view.color_style_fields.background.input.text,"#000000"); eq(view.color_style_fields.background.input.visible,true)
  view.color_style_toggles.bold.click(); view.color_style_toggles.underline.click()
  assert(view.color_style_preview.style:find("background:#000000",1,true)); assert(view.color_style_preview.style:find("font-weight:bold",1,true)); assert(view.color_style_preview.style:find("text-decoration:underline",1,true))
  view.color_style_toggles.enabled.click(); assert(view.color_style_status.message:find("This style is off",1,true))
  assert(view.color_style_preview.style:find("font-weight:normal",1,true)); eq(calls,0)
  eq(view.color_style_saved.room.foreground,ColorStyles.defaults("room").foreground)
  view.color_style_cancel.click(); view.color_style_rows.room.click(); eq(view.color_style_draft.bold,false); eq(view.color_style_draft.enabled,true)
end)
test("color style save passes only a detached complete style and commits only after true",function()
  local view=colorEditor({enabled=false,currency_enabled=false,styles={silver={foreground="#123456"}}},"gold")
  local calls=0; view:setColorStyleCallback(function(id,style)
    calls=calls+1; eq(id,"gold"); eq(style.foreground,"#ABCDEF"); eq(style.background,false); eq(style.bold,true); eq(style.underline,false); eq(style.enabled,true)
    local count=0; for _ in pairs(style) do count=count+1 end; eq(count,5)
    style.foreground="#000000"; return true
  end)
  view.color_style_fields.foreground.input:print("#abcdef"); view.color_style_toggles.bold.click(); assert(view.color_style_save.click())
  eq(calls,1); eq(view.color_style_saved.gold.foreground,"#ABCDEF"); eq(view.color_styles_config.styles.gold.foreground,"#ABCDEF")
  eq(view.color_style_saved.silver.foreground,"#123456"); eq(view.color_options.enabled,false); eq(view.color_options.currency,false)
  assert(view.color_style_status.message:find("Saved.",1,true)); assert(view.color_style_status.message:find("All highlights",1,true))
end)
test("color failed callbacks preserve saved catalog snapshot and draft and escape errors",function()
  local view=colorEditor(); local original=view.color_style_saved.room.foreground
  view.color_style_fields.foreground.input:print("#ABCDEF")
  view:setColorStyleCallback(function(id,style)
    view:setColorStyles({styles={[id]=style}}); return nil,"disk <full>"
  end)
  local ok,err=view.color_style_save.click(); eq(ok,nil); assert(err:find("disk <full>",1,true))
  eq(view.color_style_saved.room.foreground,original); eq(view.color_styles_config.styles,nil)
  eq(view.color_style_fields.foreground.input.text,"#ABCDEF"); eq(view.color_settings_page,"editor")
  assert(view.color_style_status.message:find("disk &lt;full&gt;",1,true)); eq(view.color_style_status.parent,view.color_settings_panel)
  view:setColorStyleCallback(function() error("save failed") end); eq(view.color_style_save.click(),nil); eq(view.color_style_saved.room.foreground,original)
  view:setColorStyleCallback(function() return "yes" end); eq(view.color_style_save.click(),nil)
  view:setColorStyleCallback(nil); eq(view.color_style_save.click(),nil); eq(view.color_style_saved.room.foreground,original)
  view:setColorStyleCallback(function(id,style) view:setColorStyles({styles={[id]=style}}); return true end)
  assert(view.color_style_save.click()); eq(view.color_style_saved.room.foreground,"#ABCDEF"); eq(view.color_style_error,nil)
end)
test("reset selected default is a draft until saved and preserves other styles and categories",function()
  local config={enabled=true,notice_enabled=false,styles={notice={foreground="#010203",background=false,bold=false,underline=false,enabled=false},gold={foreground="#112233"}}}
  local view=colorEditor(config,"notice"); local calls=0; view:setColorStyleCallback(function() calls=calls+1; return true end)
  assert(view.color_style_reset.click()); local default=ColorStyles.defaults("notice")
  for _,key in ipairs({"foreground","background","bold","underline","enabled"}) do eq(view.color_style_draft[key],default[key]) end
  eq(calls,0); eq(view.color_style_saved.notice.foreground,"#010203"); eq(view.color_style_saved.gold.foreground,"#112233")
  view.color_style_cancel.click(); view.color_style_rows.notice.click(); eq(view.color_style_draft.foreground,"#010203")
  view.color_style_reset.click(); assert(view.color_style_save.click()); eq(calls,1); eq(view.color_style_saved.notice.foreground,default.foreground)
  eq(view.color_style_saved.gold.foreground,"#112233"); eq(view.color_options.notice,false)
end)
test("color editor hides every input swatch and action across modal transitions",function()
  local transitions={
    function(v) v:showHelp() end, function(v) v:showChatSettings() end,
    function(v) v:showKeybindingSettings({}) end, function(v) v:showMapSettings({}) end,
    function(v) v:showMapLibrary() end, function(v) v:showRollerSettings({}) end,
    function(v) v:showFeedback() end, function(v) v:showSupport() end,
    function(v) v:showLatentPsionAlert() end, function(v) v:setColorMenuVisible(true) end,
    function(v) v.color_settings_close.click() end, function(v) v.color_settings_overlay.click() end,
  }
  for _,transition in ipairs(transitions) do
    local view=colorEditor(); local calls=0; view:setColorStyleCallback(function() calls=calls+1; return true end)
    view.color_style_fields.foreground.input:print("#123456"); transition(view)
    eq(view.color_settings_visible,false); eq(view.color_style_draft,nil); eq(calls,0)
    for _,widget in ipairs(view:colorSettingsWidgets()) do eq(widget.visible,false) end
  end
  local view=chatView(); for _,widget in ipairs(view.color_style_widgets) do eq(widget.visible,false) end
  view:showKeybindingSettings({}); view:showColorSettings(); eq(view.keybindings_visible,false)
end)
test("color editor cleanup and reuse release drafts and save callbacks",function()
  local view=colorEditor(); view:setColorStyleCallback(function() return true end)
  assert(view:prepareForReuse(view.settings)); eq(view.color_style_callback,nil); eq(view.color_style_draft,nil)
  for _,widget in ipairs(view:colorSettingsWidgets()) do eq(widget.visible,false) end
  view:showColorSettings(); view:selectColorStyle("room"); view:delete(); eq(view.root,nil); eq(view.color_style_callback,nil)
  for _,widget in ipairs(view:colorSettingsWidgets()) do eq(widget.visible,false) end
end)
test("reusable color editor rejects incomplete inputs catalog and palette",function()
  local view=chatView(); view.color_style_fields.background.input.getText=nil; eq(View.validateReusable(view,view.settings),nil)
  view=chatView(); view.color_style_rows.darkness=nil; eq(View.validateReusable(view,view.settings),nil)
  view=chatView(); view.color_style_swatches[1].deleted=true; eq(View.validateReusable(view,view.settings),nil)
  view=chatView(); view.color_style_group_order=nil; eq(View.validateReusable(view,view.settings),nil)
  view=chatView(); view.color_style_toggle_order[1]=nil; eq(View.validateReusable(view,view.settings),nil)
  view=chatView(); view.color_style_widgets[1]={}; eq(View.validateReusable(view,view.settings),nil)
  view=chatView(); view.custom_highlight_phrase.getText=nil; eq(View.validateReusable(view,view.settings),nil)
  view=chatView(); view.custom_highlight_swatches[1].deleted=true; eq(View.validateReusable(view,view.settings),nil)
  view=chatView(); view:setColorStyles({custom_rules={{phrase="gate",foreground="#FFFFFF",background=false,bold=false,underline=false,enabled=true}}}); view.custom_highlight_rows[1]=nil; eq(View.validateReusable(view,view.settings),nil)
end)
local function withColorViewAdapter(run)
  local original=Geyser; Geyser=fakeGeyser()
  local ok,err=xpcall(function()
    local settings=require("settings").merge(require("defaults"),{view_contract=VIEW_CONTRACT,view_settings_contract=SETTINGS_CONTRACT})
    run(require("mudlet_adapter").new(),settings)
  end,debug.traceback)
  Geyser=original; if not ok then error(err,0) end
end
test("adapter cold view construction accepts saved color settings before the first layout",function()
  withColorViewAdapter(function(adapter,settings)
    local view=adapter:createView(settings)
    eq(view.layout,nil); eq(type(view.map_center_callback),"function")
    for _,widget in ipairs(view:colorSettingsWidgets()) do eq(widget.visible,false) end
    assert(view:setColorStyles({enabled=true,races_enabled=false,styles={["race:human"]={foreground="#010203",background="#112233",bold=true,underline=true,enabled=true}}}))
    assert(View.validateReusable(view,settings)); view:applyLayout(require("layout").compute(320,260)); view:update(require("state").normalize({}))
    assert(view:showColorSettings()); assert(view:selectColorStyle("race:human"))
    eq(view.color_style_fields.foreground.input.text,"#010203"); eq(view.color_style_fields.background.input.text,"#112233")
    assert(view.color_style_status.message:find("category is currently off",1,true))
    view:delete(); eq(view.root,nil)
  end)
end)
test("adapter rejects an old view before rebinding methods and can construct its replacement",function()
  withColorViewAdapter(function(adapter,settings)
    local old=adapter:createView(settings); local root=old.root
    for key in pairs(old) do if key:match("^color_style") then old[key]=nil end end
    old.color_settings_groups_tab=nil; old.color_settings_styles_tab=nil; old.color_settings_status=nil
    local oldMethods={delete=function(self) self.root:delete(); self.root=nil end}
    local oldMetatable={__index=oldMethods}; setmetatable(old,oldMetatable)
    local called,adopted,err=pcall(adapter.adoptView,adapter,old,settings)
    eq(called,true); eq(adopted,nil); assert(err:find("missing color_settings",1,true)); eq(getmetatable(old),oldMetatable)
    old:delete(); eq(root.deleted,true)
    local replacement=adapter:createView(settings); assert(replacement~=old)
    replacement:setColorStyles(settings.colorization); replacement:applyLayout(require("layout").compute(1200,800)); replacement:update(require("state").normalize({}))
    assert(View.validateReusable(replacement,settings)); replacement:showColorSettings(); replacement:selectColorStyle("notice")
    eq(replacement.color_style_fields.foreground.input.visible,true); replacement:delete()
  end)
end)
test("rejected damaged view cleanup removes its root even when editor cleanup is incomplete",function()
  withColorViewAdapter(function(adapter,settings)
    local damaged=adapter:createView(settings); local root=damaged.root
    damaged.color_option_buttons=nil
    local called,adopted=pcall(adapter.adoptView,adapter,damaged,settings); eq(called,true); eq(adopted,nil)
    assert(pcall(damaged.delete,damaged)); eq(root.deleted,true); eq(damaged.root,nil)
    local replacement=adapter:createView(settings); assert(View.validateReusable(replacement,settings)); replacement:delete()
  end)
end)
test("compatible view adoption keeps saved colors while discarding unsaved color edits",function()
  withColorViewAdapter(function(adapter,settings)
    local view=adapter:createView(settings); local root=view.root
    view:setColorStyles({styles={room={foreground="#123456"}}}); view:applyLayout(require("layout").compute(420,280))
    view:showColorSettings(); view:selectColorStyle("room"); view.color_style_fields.foreground.input:print("#ABCDEF")
    view:setColorStyleCallback(function() error("retired callback") end)
    local adopted=assert(adapter:adoptView(view,settings)); eq(adopted,view); eq(view.root,root); eq(root.deleted,nil)
    eq(view.color_style_callback,nil); eq(view.color_style_draft,nil)
    for _,widget in ipairs(view:colorSettingsWidgets()) do eq(widget.visible,false) end
    view:showColorSettings(); view:selectColorStyle("room"); eq(view.color_style_fields.foreground.input.text,"#123456")
    view:delete()
  end)
end)
test("adapter adoption preserves custom phrase widgets and saved rules",function()
  withColorViewAdapter(function(adapter,settings)
    local view=adapter:createView(settings); local root=view.root
    view:setColorStyles({custom_rules={{phrase="old gate",foreground="#79D98B",background=false,bold=false,underline=false,enabled=true}}})
    view:applyLayout(require("layout").compute(420,280)); view:showColorSettings(); view.color_settings_custom_tab.click()
    local row=view.custom_highlight_rows[1]; row.click(); view.custom_highlight_phrase:print("unsaved")
    view:setCustomHighlightCallbacks(function() error("retired") end,function() error("retired") end)
    assert(adapter:adoptView(view,settings)); eq(view.root,root); eq(root.deleted,nil)
    eq(view.custom_highlight_save_callback,nil); eq(view.custom_highlight_delete_callback,nil)
    eq(view.custom_highlight_draft,nil); eq(view.custom_highlight_rules[1].phrase,"old gate")
    view:showColorSettings(); view.color_settings_custom_tab.click(); eq(view.custom_highlight_rows[1],row)
    row.click(); eq(view.custom_highlight_phrase.text,"old gate")
    view:delete()
  end)
end)
test("color preview explicitly renders chosen text color and emphasis under Geyser label wrapping",function()
  local view=colorEditor({styles={room={foreground="#010203",background="#112233",bold=true,underline=true,enabled=true}}})
  eq(view.color_style_preview.echo_color,"nocolor")
  assert(view.color_style_preview.message:find("color:#010203",1,true))
  assert(view.color_style_preview.message:find("<u><b>The town square</b></u>",1,true))
  view.color_style_toggles.enabled.click()
  assert(view.color_style_preview.message:find("color:"..view.settings.theme.text,1,true))
  eq(view.color_style_preview.message:find("<b>",1,true),nil); eq(view.color_style_preview.message:find("<u>",1,true),nil)
end)
test("category persistence failures leave displayed switch state unchanged and show an error",function()
  local view=chatView(); view:applyLayout(require("layout").compute(320,260)); view:showColorSettings()
  local before=view.color_option_buttons.damage.style
  view:setColorOptionsCallback(function(key,wanted) eq(key,"damage"); eq(wanted,false); return nil,"disk <full>" end)
  local ok,err=view.color_option_buttons.damage.click(); eq(ok,nil); eq(err,"disk <full>")
  eq(view.color_options.damage,true); eq(view.color_option_buttons.damage.style,before); eq(view.color_settings_visible,true)
  eq(view.color_settings_status.visible,true); eq(view.color_settings_status.parent,view.color_settings_panel)
  assert(view.color_settings_status.message:find("disk &lt;full&gt;",1,true))
  view:setColorToggleCallback(function() return nil,"not saved" end); eq(view.color_option_buttons.enabled.click(),nil); eq(view.color_enabled,true)
  view:setColorOptionsCallback(function() error("not saved") end); eq(view.color_option_buttons.damage.click(),nil); eq(view.color_options.damage,true)
  view:setColorOptionsCallback(function(_,wanted) return wanted end); eq(view.color_option_buttons.damage.click(),false)
  eq(view.color_options.damage,false); eq(view.color_settings_error,nil)
  local called; view:setColorOptionsCallback(function(key,wanted) called=key; return wanted end)
  eq(view.color_option_buttons.mapper.click(),false); eq(called,"mapper"); eq(view.color_styles_config.mapper,nil)
end)
test("color snapshot respects group switches and legacy highlights without changing mapper",function()
  local view=chatView(); view:setColorOptions({mapper=false})
  view:setColorStyles({enabled=false,room_enabled=false,exits_enabled=false,highlights_enabled=false,illumination_enabled=true})
  eq(view.color_options.mapper,false); eq(view.color_options.enabled,false); eq(view.color_options.room,false); eq(view.color_options.exits,false)
  eq(view.color_options.attack,false); eq(view.color_options.notice,false); eq(view.color_options.illumination,true); eq(view.color_options.currency,true)
end)

test("WORLD UI and chat honor legacy highlights fallback unless explicitly overridden",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view:showColorSettings()
  local entries={{category="WORLD",message="just arrived in the world.",line=" ** Test just arrived in the world."},{category="WORLD",message="has left the world unexpectedly.",line=" ** Test has left the world unexpectedly."}}
  for _,case in ipairs({
    {{highlights_enabled=false},false},
    {{highlights_enabled=true},true},
    {{highlights_enabled=false,world_enabled=true},true},
    {{highlights_enabled=true,world_enabled=false},false},
  }) do
    local config,wanted=case[1],case[2]; assert(view:setColorStyles(config))
    eq(view.color_options.world,wanted); assert(view.color_option_buttons.world.message:find(wanted and "ON" or "OFF",1,true))
    view:renderChat(entries,{"WORLD"},"WORLD"); eq(#view.chat_entries,2); eq(view.chat_active_filter,"WORLD")
    for index,entry in ipairs(entries) do
      local style=require("color_styles").resolve({},index==1 and "world_arrival" or "world_departure")
      eq(view.chat_output.echoFormats[index].foreground,wanted and style.foreground or nil)
      eq(view.chat_output.hechoes[index],wanted and style.foreground.."WORLD#r" or "#9eafc6WORLD#r")
      eq(view.chat_output.echoes[index]," "..entry.line.."\n")
    end
  end
end)

test("color options menu exposes current and future feature toggles",function()
  local view=chatView(); local calls={}
  view:setColorToggleCallback(function() calls[#calls+1]={key="enabled"}; return false end)
  view:setColorOptionsCallback(function(key,value) calls[#calls+1]={key=key,value=value}; return value end)
  view:setColorOptions({enabled=true,notice=true,room=true,exits=false,currency=true,races=true,classes=true,portal=true,attack=true,damage=true,danger=true,recovery=true,upkeep=true,spell=true,discovery=true,illumination=true})
  view:applyLayout(require("layout").compute(1200,800)); view.color_toggle.click()
  eq(view.color_menu_visible,true); eq(view.color_menu.visible,true); eq(view.color_menu_scrim.visible,true)
  eq(#view.option_action_order,15); view:setAutoUpdateEnabled(false); eq(view.option_action_buttons.auto_update.option_text,"AUTOMATIC UPDATES: OFF"); view:setAutoUpdateEnabled(true); eq(view.option_action_buttons.auto_update.option_text,"AUTOMATIC UPDATES: ON"); eq(view:setDisplayTextSize("small"),"small"); eq(view.option_action_buttons.text_size.option_text,"HUD TEXT: SMALL"); eq(view:setMainConsoleAutoWrap(false),false); eq(view.option_action_buttons.auto_main_wrap.option_text,"AUTO MAIN WRAP: OFF"); eq(view:setMainConsoleAutoWrap(true),true); eq(view.option_action_buttons.auto_main_wrap.option_text,"AUTO MAIN WRAP: ON"); view.option_action_buttons.color_settings.click(); eq(view.color_settings_visible,true)
  for _,key in ipairs(view.color_option_order) do eq(view.color_option_buttons[key].visible,true) end
  eq(view.color_option_buttons.room.message:find("ROOM TITLES",1,true)~=nil,true)
  eq(view.color_option_buttons.exits.message:find("OFF",1,true)~=nil,true)
  eq(view.color_option_buttons.damage.message:find("DAMAGE TO YOU",1,true)~=nil,true)
  eq(view.color_option_buttons.races.message:find("RACES",1,true)~=nil,true); eq(view.color_option_buttons.classes.message:find("CLASSES",1,true)~=nil,true)
  eq(view.color_option_buttons.illumination.message:find("ILLUMINATED AREAS",1,true)~=nil,true)
  eq(view.color_option_buttons.notice.message:find("IMPORTANT GAME NOTICES",1,true)~=nil,true)
  view.color_option_buttons.exits.click(); eq(calls[#calls].key,"exits"); eq(calls[#calls].value,true); eq(view.color_settings_visible,true)
  view.color_option_buttons.damage.click(); eq(calls[#calls].key,"damage"); eq(calls[#calls].value,false)
  view.color_option_buttons.enabled.click(); eq(calls[#calls].key,"enabled"); eq(view.color_enabled,false)
end)

test("main input alignment defaults off immediately after automatic main wrap",function()
  local view=chatView(); local button=view.option_action_buttons.align_main_input
  eq(view.main_input_aligned,false); eq(button.option_text,"ALIGN INPUT: OFF")
  eq(button.tooltip,"Align input with main display (left edge only). Input ends before Mudlet's native Search/status controls, which stay visible on the right. Your normal input, draft, history, and aliases remain available. OFF restores the previous input style and compact-input preference."); eq(button.parent,view.options_scroll)
  eq(table.concat(view.option_action_order,","),"command_help,refresh_data,auto_update,base_ui_toggle,text_size,auto_main_wrap,align_main_input,main_skills,skill_settings,chat_settings,keybindings_settings,color_settings,map_settings,roller_settings,support")
  view:applyLayout(require("layout").compute(1200,800)); view.color_toggle.click()
  eq(button.visible,true); assert(button.message:find("ALIGN INPUT: OFF",1,true))
  local wrap=view.option_action_buttons.auto_main_wrap
  eq(button.y,wrap.y+wrap.height)
end)
test("Mudlet starter UI option is reversible and refreshes its actual status",function()
  local view=chatView(); local button=view.option_action_buttons.base_ui_toggle
  eq(button.option_text,"MUDLET UI: UNAVAILABLE")
  assert(button.tooltip:find("starter panel",1,true))
  local visible=true; local checked=0
  view:setBaseUIStatusCallback(function() checked=checked+1; view:setBaseUIVisible(visible,true) end)
  view:setOptionsActionCallback(function(action)
    eq(action,"base_ui_toggle"); visible=not visible; return view:setBaseUIVisible(visible,true)
  end)
  view:applyLayout(require("layout").compute(420,360)); view.color_toggle.click()
  eq(checked,1); eq(button.option_text,"MUDLET UI: ON"); eq(button.visible,true)
  eq(button.click(),false); eq(button.option_text,"MUDLET UI: OFF"); eq(view.color_menu_visible,false)
  view.color_toggle.click(); eq(checked,2); eq(button.option_text,"MUDLET UI: OFF")
end)

test("main input alignment setter refreshes hidden and open menus independently of wrap",function()
  local view=chatView(); local button=view.option_action_buttons.align_main_input
  view:setMainConsoleAutoWrap(false)
  eq(view:setMainInputAligned(true),true); eq(view.main_input_aligned,true)
  eq(button.option_text,"ALIGN INPUT: ON"); eq(view.color_menu_visible,false)
  view:applyLayout(require("layout").compute(1200,800)); view.color_toggle.click()
  assert(button.message:find("ALIGN INPUT: ON",1,true))
  eq(view:setMainInputAligned(false),false); eq(view.main_input_aligned,false)
  assert(button.message:find("ALIGN INPUT: OFF",1,true)); eq(view.color_menu_visible,true)
  eq(view.main_console_auto_wrap,false); eq(view.option_action_buttons.auto_main_wrap.option_text,"AUTO MAIN WRAP: OFF")
  local tooltip=button.tooltip
  view:setMainInputAligned(true); view:applyLayout(require("layout").compute(320,260))
  assert(button.message:find("ALIGN INPUT: ON",1,true)); eq(button.tooltip,tooltip)
end)

test("main input alignment clicks delegate toggling to the options callback",function()
  local view=chatView(); local calls={}; local aligned=false
  view:setOptionsActionCallback(function(action,...)
    calls[#calls+1]=action; eq(select("#",...),0); eq(view.color_menu_visible,false)
    aligned=not aligned; return view:setMainInputAligned(aligned)
  end)
  view:applyLayout(require("layout").compute(1200,800))
  for _,wanted in ipairs({true,false}) do
    view.color_toggle.click(); eq(view.option_action_buttons.align_main_input.click(),wanted)
    eq(calls[#calls],"align_main_input"); eq(view.main_input_aligned,wanted)
    view.color_toggle.click(); assert(view.option_action_buttons.align_main_input.message:find(wanted and "ALIGN INPUT: ON" or "ALIGN INPUT: OFF",1,true))
    view.color_toggle.click()
  end
  eq(#calls,2)
end)

test("main input alignment keeps its state when the options action is unavailable or fails",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view.color_toggle.click()
  local ok,err=view.option_action_buttons.align_main_input.click()
  eq(ok,nil); eq(err,"options action is unavailable"); eq(view.main_input_aligned,false)
  view:setMainInputAligned(true)
  view:setOptionsActionCallback(function(action) eq(action,"align_main_input"); return nil,"Could not save alignment" end)
  view.color_toggle.click(); ok,err=view.option_action_buttons.align_main_input.click()
  eq(ok,nil); eq(err,"Could not save alignment"); eq(view.main_input_aligned,true)
  eq(view.option_action_buttons.align_main_input.option_text,"ALIGN INPUT: ON")
end)

test("chat settings separates visible clearing from confirmed saved-history deletion",function()
  local view=chatView(); local actions={}; local sourceCall; view:setOptionsActionCallback(function(action,key,wanted) actions[#actions+1]=action; if action=="chat_all_source" then sourceCall={key=key,wanted=wanted}; return wanted elseif action=="chat_clear_visible" then return true,12 elseif action=="chat_clear_saved" then return true,3 end; return true end)
  view:setChatAllSources({ROOM=true,COMBAT=false})
  view:applyLayout(require("layout").compute(1024,600)); view.color_toggle.click(); view.option_action_buttons.chat_settings.click()
  eq(view.chat_settings_visible,true); eq(view.chat_settings_panel.visible,true)
  assert(view.chat_all_source_buttons.COMBAT.message:find("OFF",1,true)); assert(view.chat_all_source_buttons.ROOM.message:find("ON",1,true))
  eq(view.chat_all_source_buttons.COMBAT.click(),true); eq(sourceCall.key,"COMBAT"); eq(sourceCall.wanted,true); assert(view.chat_all_source_buttons.COMBAT.message:find("ON",1,true))
  eq(view.chat_all_source_buttons.ROOM.click(),false); eq(sourceCall.key,"ROOM"); eq(sourceCall.wanted,false); assert(view.chat_all_source_buttons.ROOM.message:find("OFF",1,true))
  assert(view.chat_settings_clear_visible.click()); eq(actions[#actions],"chat_clear_visible"); eq(view.chat_settings_status.message:find("12 visible",1,true)~=nil,true)
  assert(view.chat_settings_clear_saved.click()); eq(actions[#actions],"chat_clear_visible"); eq(view.chat_settings_clear_pending,true)
  assert(view.chat_settings_clear_saved.click()); eq(actions[#actions],"chat_clear_saved"); eq(view.chat_settings_clear_pending,false); eq(view.chat_settings_status.message:find("3 saved",1,true)~=nil,true)
  view.chat_settings_close.click(); eq(view.chat_settings_visible,false)
end)
test("chat sound defaults expose all ten labeled sounds through Options",function()
  local Sounds=require("chat_sounds"); local view=chatView(); local used={}
  view:applyLayout(require("layout").compute(1200,800)); view.color_toggle.click(); view.option_action_buttons.chat_settings.click()
  eq(view.chat_settings_visible,true); eq(#view.chat_sound_order,10); eq(view.chat_sounds.volume,60)
  for index,key in ipairs({"ALL","ROOM","PRIVATE","ESP","DRAGON","SECIAN","CONTACT","STAFF","COMBAT","WORLD"}) do
    eq(view.chat_sound_order[index],key)
    local setting=view.chat_sounds.tabs[key]; local row=view.chat_sound_rows[key]
    eq(setting.enabled,key=="STAFF"); eq(setting.sound,key:lower()); eq(used[setting.sound],nil); used[setting.sound]=true
    assert(row.enabled.message:find(setting.enabled and "ON" or "OFF",1,true))
    assert(row.choice.message:find(Sounds.get(setting.sound).label,1,true)); eq(row.preview.visible,true)
  end
  assert(view.chat_sound_explanation.message:find("Staff ON; other tabs OFF. Choose a sound, Preview, changes save automatically.",1,true))
  eq(view.chat_sound_explanation.message:find("fallback",1,true),nil); eq(view.chat_sound_explanation.message:find("bursts",1,true),nil)
  assert(view.chat_sound_explanation.tooltip:find("Preview works even when OFF. Mudlet/media mute still applies.",1,true))
  assert(view.chat_sound_caption.tooltip:find("ALL is a fallback",1,true))
  assert(view.chat_sound_caption.tooltip:find("one ding per second per tab",1,true))
end)
test("chat sound toggles send each tab and accept saved false only after persistence",function()
  local view=chatView(); local calls={}
  view:setOptionsActionCallback(function(action,tab,value)
    eq(action,"chat_sound_enabled"); eq(type(value),"boolean"); eq(view:chatSoundSetting(tab).enabled,not value)
    calls[#calls+1]={action,tab,value}; return value
  end)
  for _,key in ipairs(view.chat_sound_order) do
    local row=view.chat_sound_rows[key]; local original=view:chatSoundSetting(key).enabled
    eq(row.enabled.click(),not original); eq(view:chatSoundSetting(key).enabled,not original)
    eq(calls[#calls][2],key); eq(calls[#calls][3],not original)
    eq(row.enabled.click(),original); eq(view:chatSoundSetting(key).enabled,original)
    eq(view.settings.chat.sounds.tabs[key].enabled,original)
  end
  eq(#calls,20)
end)
test("chat sound selectors cycle the catalog in both directions with exact payloads",function()
  local Sounds=require("chat_sounds"); local view=chatView(); local calls={}
  view:applyLayout(require("layout").compute(1200,800)); view:showChatSettings()
  view:setOptionsActionCallback(function(action,tab,value)
    eq(action,"chat_sound_choice"); assert(Sounds.get(value)); calls[#calls+1]={tab,value}; return value
  end)
  for index,key in ipairs(Sounds.tabOrder) do
    local row=view.chat_sound_rows[key]; local nextId=Sounds.catalog[index%#Sounds.catalog+1].id
    eq(row.next.click(),nextId); eq(calls[#calls][1],key); eq(calls[#calls][2],nextId)
    eq(view:chatSoundSetting(key).sound,nextId); assert(row.choice.message:find(Sounds.get(nextId).label,1,true))
    eq(row.previous.click(),key:lower()); eq(view:chatSoundSetting(key).sound,key:lower())
  end
  eq(view.chat_sound_rows.ALL.previous.click(),"world"); eq(view.chat_sound_rows.ALL.next.click(),"all")
  eq(#calls,22)
end)
test("chat sound previews work while OFF and never save or toggle settings",function()
  local view=chatView(); local calls={}; local saved=view.settings.chat.sounds
  view:applyLayout(require("layout").compute(1200,800)); view:showChatSettings()
  view:setOptionsActionCallback(function(action,tab,value)
    calls[#calls+1]={action,tab,value}; return true
  end)
  for _,key in ipairs(view.chat_sound_order) do
    local before=view:chatSoundSetting(key).enabled
    eq(view.chat_sound_rows[key].preview.click(),true)
    eq(calls[#calls][1],"chat_sound_preview"); eq(calls[#calls][2],key); eq(calls[#calls][3],key:lower())
    eq(view:chatSoundSetting(key).enabled,before); eq(view.settings.chat.sounds,saved)
  end
  eq(#calls,#view.chat_sound_order)
  view:setOptionsActionCallback(function() return nil,"Media is muted" end)
  local ok,err=view.chat_sound_rows.ROOM.preview.click(); eq(ok,nil); eq(err,"Media is muted")
  eq(view:chatSoundSetting("ROOM").enabled,false); assert(view.chat_sound_status.message:find("Media is muted",1,true))
end)
test("chat sound save failures preserve toggles choices volume and saved settings",function()
  local Sounds=require("chat_sounds"); local config=Sounds.defaults(); local view=chatView(nil,nil,nil,nil,config)
  view:applyLayout(require("layout").compute(320,260)); view:showChatSettings()
  view:setOptionsActionCallback(function() return nil,"disk <full>" end)
  for _,button in ipairs({view.chat_sound_rows.STAFF.enabled,view.chat_sound_rows.ROOM.enabled,view.chat_sound_rows.STAFF.next,view.chat_sound_volume_up}) do
    local ok,err=button.click(); eq(ok,nil); eq(err,"disk <full>")
    eq(view.chat_sounds.tabs.STAFF.enabled,true); eq(view.chat_sounds.tabs.ROOM.enabled,false)
    eq(view.chat_sounds.tabs.STAFF.sound,"staff"); eq(view.chat_sounds.volume,60); eq(view.settings.chat.sounds,config)
    assert(view.chat_sound_status.message:find("disk &lt;full&gt;",1,true))
  end
  assert(view.chat_sound_rows.STAFF.enabled.message:find("ON",1,true)); assert(view.chat_sound_rows.ROOM.enabled.message:find("OFF",1,true))
  assert(view.chat_sound_rows.STAFF.choice.message:find("Staff Three-Tone",1,true)); assert(view.chat_sound_volume.message:find("60%",1,true))
  view:setOptionsActionCallback(function() error("save failed") end)
  local ok,err=view.chat_sound_rows.STAFF.enabled.click(); eq(ok,nil); assert(err:find("save failed",1,true)); eq(view.chat_sounds.tabs.STAFF.enabled,true)
  view:setOptionsActionCallback(nil); ok,err=view.chat_sound_rows.ROOM.next.click(); eq(ok,nil); assert(err:find("unavailable",1,true)); eq(view.chat_sounds.tabs.ROOM.sound,"room")
end)
test("chat sound volume uses shared ten point steps and clamps at one and one hundred",function()
  local view=chatView(); local calls={}
  view:setOptionsActionCallback(function(action,tab,value)
    eq(action,"chat_sound_volume"); eq(tab,nil); calls[#calls+1]=value; return value
  end)
  eq(view.chat_sound_volume_down.click(),50); eq(view.chat_sound_volume_up.click(),60)
  for _=1,6 do view.chat_sound_volume_up.click() end
  eq(view.chat_sounds.volume,100); eq(calls[#calls],100)
  for _=1,12 do view.chat_sound_volume_down.click() end
  eq(view.chat_sounds.volume,1); eq(calls[#calls],1); eq(view.settings.chat.sounds.volume,1)
  view:setOptionsActionCallback(function() return 35 end)
  eq(view.chat_sound_volume_up.click(),35); eq(view.chat_sounds.volume,35)
end)
test("chat sound config initializes updates and captures settings without aliasing callers",function()
  local config={volume=40,tabs={STAFF={enabled=false,sound="room"}}}; local view=chatView(nil,nil,nil,nil,config)
  eq(view.chat_sounds.volume,40); eq(view.chat_sounds.tabs.STAFF.enabled,false); eq(view.chat_sounds.tabs.STAFF.sound,"room")
  config.volume=70; config.tabs.STAFF.sound="esp"; eq(view.chat_sounds.volume,40); eq(view.chat_sounds.tabs.STAFF.sound,"room")
  view:showChatSettings(); eq(view.chat_sounds.volume,70); eq(view.chat_sounds.tabs.STAFF.sound,"esp")
  view:applyLayout(require("layout").compute(900,700))
  local update={volume=25,tabs={ROOM={enabled=true,sound="contact"}}}; assert(view:setChatSounds(update))
  update.tabs.ROOM.sound="combat"; eq(view.chat_sounds.tabs.ROOM.sound,"contact")
  assert(view.chat_sound_rows.ROOM.choice.message:find("Mind Echo",1,true)); assert(view.chat_sound_volume.message:find("25%",1,true))
  local before=view.chat_sounds
  local ok=view:setChatSounds({volume=101}); eq(ok,nil); eq(view.chat_sounds,before)
  ok=view:setChatSounds({tabs={ROOM={sound="https://example.invalid/tone.wav"}}}); eq(ok,nil); eq(view.chat_sounds,before)
end)
test("chat sound controls reject unknown sounds tabs and malformed callback results",function()
  local view=chatView(); local calls=0
  view:setOptionsActionCallback(function() calls=calls+1; return true end)
  eq(view:changeChatSound("chat_sound_choice","ROOM","../tone.wav"),nil)
  eq(view:changeChatSound("chat_sound_enabled","UNKNOWN",true),nil)
  eq(view:changeChatSound("chat_sound_enabled","ROOM","false"),nil)
  eq(view:changeChatSound("chat_sound_volume",nil,0/0),nil); eq(calls,0)
  for _,case in ipairs({{"chat_sound_enabled","STAFF",false,"false"},{"chat_sound_choice","ROOM","esp",true},{"chat_sound_volume",nil,70,101}}) do
    view:setOptionsActionCallback(function() return case[4] end)
    eq(view:changeChatSound(case[1],case[2],case[3]),nil)
    eq(view.chat_sounds.tabs.STAFF.enabled,true); eq(view.chat_sounds.tabs.ROOM.sound,"room"); eq(view.chat_sounds.volume,60)
  end
end)
test("chat sound custom rows canonicalize actual tabs and default OFF with Soft Bell",function()
  local view=chatView(); view.settings.chat.tab_order={"QUEST LOG","OWN","WHISPER","<BAD>"}
  view:applyLayout(require("layout").compute(1200,800))
  view:renderChat({},{"QUEST LOG","EVENTS-2","OWN","WHISPER","<BAD>",string.rep("A",33)},"ALL")
  view:showChatSettings(); eq(#view.chat_sound_order,12)
  eq(view.chat_sound_rows.OWN,nil); eq(view.chat_sound_rows.WHISPER,nil); eq(view.chat_sound_rows["<BAD>"],nil)
  for _,key in ipairs({"QUEST LOG","EVENTS-2"}) do
    local row=view.chat_sound_rows[key]; assert(row); eq(view:chatSoundSetting(key).enabled,false); eq(view:chatSoundSetting(key).sound,"all")
    assert(row.choice.message:find("Soft Bell",1,true))
  end
  local calls={}; view:setOptionsActionCallback(function(action,tab,value) calls[#calls+1]={action,tab,value}; return value end)
  eq(view.chat_sound_rows["QUEST LOG"].enabled.click(),true); eq(calls[1][1],"chat_sound_enabled"); eq(calls[1][2],"QUEST LOG"); eq(calls[1][3],true)
  eq(view.chat_sound_rows["QUEST LOG"].next.click(),"room"); eq(view.settings.chat.sounds.tabs["QUEST LOG"].sound,"room")
  view:hideChatSettings(); view:showChatSettings(); eq(view:chatSoundSetting("QUEST LOG").enabled,true)
  local old=view.chat_sound_rows["EVENTS-2"].preview; view:renderChat({},{"QUEST LOG"},"ALL"); eq(old.deleted,true); eq(view.chat_sound_rows["EVENTS-2"],nil)
  local categories={}; for i=1,80 do categories[i]="CUSTOM "..i end
  view:renderChat({},categories,"ALL"); eq(#view.chat_sound_order,require("chat_sounds").MAX_TABS)
end)
test("all chat sound controls scroll without overlap and Close stays fixed at small and large sizes",function()
  local view=chatView(); view:renderChat({},{string.rep("A",32)},"ALL"); view:showChatSettings()
  for _,size in ipairs({{280,240},{320,260},{400,300},{420,500},{760,700},{1920,1080}}) do
    for _,bodyFont in ipairs({14,24}) do
      local layout=require("layout").compute(size[1],size[2]); layout.body_font=bodyFont; view:applyLayout(layout)
      local content,panel,close=view.chat_settings_content,view.chat_settings_panel,view.chat_settings_close
      eq(content.kind,"scrollbox"); eq(close.parent,panel); eq(content.y+content.height<=close.y,true); eq(close.y+close.height<=panel.height,true)
      eq(panel.x>=0 and panel.x+panel.width<=size[1],true); eq(panel.y>=0 and panel.y+panel.height<=size[2],true)
      eq(view.chat_sound_caption.y>=view.chat_settings_visibility.y+view.chat_settings_visibility.height,true)
      eq(view.chat_settings_text.y>view.chat_sound_rows.COMBAT.preview.y,true)
      local children={}
      for _,widget in ipairs(view:chatSettingsWidgets()) do
        if widget.parent==content then
          children[#children+1]=widget; eq(widget.visible,true); eq(widget.width>0 and widget.height>0,true)
          eq(widget.x>=0 and widget.x+widget.width<=content.width-18,true)
          eq(widget.y>=0 and widget.y+widget.height<=content.content_height,true)
          if widget.click then
            eq(widget.height<=content.height,true)
            local scroll=math.min(widget.y,content.content_height-content.height)
            eq(widget.y-scroll>=0 and widget.y+widget.height-scroll<=content.height,true)
          end
        end
      end
      for i=1,#children do for j=i+1,#children do
        local a,b=children[i],children[j]
        local overlap=a.x<b.x+b.width and b.x<a.x+a.width and a.y<b.y+b.height and b.y<a.y+a.height
        if overlap then error("overlapping chat settings controls: "..a.name.." / "..b.name) end
      end end
      for _,key in ipairs(view.chat_sound_order) do
        local row=view.chat_sound_rows[key]
        for _,name in ipairs({"caption","enabled","previous","choice","next","preview"}) do eq(row[name].parent,content); eq(row[name].visible,true) end
        eq(row.preview.y+row.preview.height<=view.chat_settings_clear_visible.y,true)
      end
      eq(content.content_height>content.height,true)
    end
  end
end)
test("all ten sound rows fit without scrolling on regular desktop screens",function()
  local view=chatView(); view:showChatSettings()
  for _,size in ipairs({{1024,768},{1200,800},{1366,768},{1920,1080}}) do
    view:applyLayout(require("layout").compute(size[1],size[2]))
    local content=view.chat_settings_content
    eq(view.chat_settings_panel.height<=740,true)
    for _,key in ipairs(view.chat_sound_order) do
      for _,name in ipairs({"caption","enabled","previous","choice","next","preview"}) do
        local widget=view.chat_sound_rows[key][name]
        eq(widget.y+widget.height<=content.height,true)
      end
    end
    eq(view.chat_settings_close.y>=content.y+content.height,true)
  end
end)
test("chat sound startup and resize accept Geyser px constraints through pixel getters",function()
  local original=Geyser; local geyser=fakeGeyser(); local newLabel=geyser.Label.new
  function geyser.Label:new(cons,parent)
    local item=newLabel(self,cons,parent)
    if cons.name:match("^DGHUD%.ChatSettings%.Sounds%.Row%.") then
      -- Geyser.calc_constraints converts numbers to px strings on creation
      -- and every resize; get_width supplies the resolved numeric pixels.
      function item:resize(width,height)
        self.pixel_width=math.floor(width); self.width=string.format("%dpx",self.pixel_width)
        self.height=string.format("%dpx",math.floor(height))
      end
      function item:get_width() self.width_reads=(self.width_reads or 0)+1; return self.pixel_width end
      item:resize(cons.width,cons.height)
    end
    return item
  end
  Geyser=geyser
  local ok,err=xpcall(function()
    local settings=require("settings").resolve(require("defaults"),{})
    local view=View.new(settings); local calls=0
    view:setOptionsActionCallback(function() calls=calls+1; return true end)
    for _,key in ipairs(view.chat_sound_order) do
      local caption=view.chat_sound_rows[key].caption
      eq(caption.width,"10px"); eq(caption.width_reads,nil); eq(caption:get_width(),10); eq(caption.message,nil)
    end
    for _,size in ipairs({{1920,1080},{320,260},{1200,800}}) do
      view:applyLayout(require("layout").compute(size[1],size[2])); view:showChatSettings()
      for _,key in ipairs(view.chat_sound_order) do
        local caption=view.chat_sound_rows[key].caption; local before=caption.width_reads
        assert(caption.width:match("^%d+px$")); eq(caption:get_width()>10,true)
        view:renderChatSounds(); eq(caption.width_reads>before+1,true)
        assert(caption.message:find(key,1,true))
      end
      view:hideChatSettings(); assert(view:setChatSounds(settings.chat.sounds))
    end
    eq(calls,0)
  end,debug.traceback)
  Geyser=original; assert(ok,err)
end)
test("chat sound caption width safely falls back when pixel getters are unavailable",function()
  local view=chatView(); local caption=view.chat_sound_rows.STAFF.caption
  view:applyLayout(require("layout").compute(1200,800)); view:showChatSettings()
  caption.width="100%" -- Raw constraints must never be used for arithmetic.
  caption.get_width=function() return 14 end
  view:renderChatSounds(); eq(caption.message:find("STAFF",1,true),nil)
  for _,getter in ipairs({false,function() error("not ready") end,function() return nil end,function() return "10px" end,function() return 0 end,function() return -1 end,function() return 0/0 end,function() return math.huge end}) do
    caption.get_width=getter
    view:renderChatSounds(); assert(caption.message:find("STAFF",1,true))
  end
end)
test("hidden sound settings cache updates without painting until the dialog is shown",function()
  local original=Geyser; local geyser=fakeGeyser(); local newLabel=geyser.Label.new; local nativeCalls,echoes=0,0
  function geyser.Label:new(cons,parent)
    local item=newLabel(self,cons,parent)
    if cons.name:match("^DGHUD%.ChatSettings%.Sounds%.") then
      for _,name in ipairs({"echo","setStyleSheet","setToolTip","move","resize","show","hide","delete","get_width"}) do
        local method=item[name]
        item[name]=function(self,...)
          nativeCalls=nativeCalls+1; if name=="echo" then echoes=echoes+1 end
          return method(self,...)
        end
      end
    end
    return item
  end
  Geyser=geyser
  local ok,err=xpcall(function()
    local settings=require("settings").resolve(require("defaults"),{})
    local view=View.new(settings); eq(echoes,0)
    local before=nativeCalls
    assert(view:setChatSounds(settings.chat.sounds)); assert(view:renderChatSounds()); assert(view:renderChatSettings())
    eq(nativeCalls,before); eq(echoes,0)
    view:applyLayout(require("layout").compute(1200,800)); eq(echoes,0)
    local redrawEchoes=6+#view.chat_sound_order*6
    assert(view:showChatSettings()); eq(echoes,redrawEchoes)
    view:hideChatSettings(); before=nativeCalls
    local config=require("chat_sounds").defaults(); config.tabs.STAFF.enabled=false; config.tabs.STAFF.sound="room"; config.volume=30
    settings.chat.sounds=config -- Main updates its saved settings before notifying View.
    assert(view:setChatSounds(config)); assert(view:renderChatSounds()); assert(view:renderChatSettings())
    eq(nativeCalls,before); eq(echoes,redrawEchoes); eq(view.chat_sounds.tabs.STAFF.enabled,false)
    assert(view:showChatSettings()); eq(echoes,redrawEchoes*2)
    assert(view.chat_sound_rows.STAFF.enabled.message:find("OFF",1,true)); assert(view.chat_sound_rows.STAFF.choice.message:find("Room Chime",1,true))
    assert(view.chat_sound_volume.message:find("30%",1,true))
    view.root.hidden=true; before=nativeCalls
    assert(view:setChatSounds(config)); assert(view:renderChatSounds()); assert(view:renderChatSettings()); eq(nativeCalls,before)
    view.root.hidden=nil; view.root.auto_hidden=true
    assert(view:setChatSounds(config)); assert(view:renderChatSounds()); assert(view:renderChatSettings()); eq(nativeCalls,before)
    view.root.auto_hidden=nil
    view.root.hidden=nil; view:renderChatSounds(); eq(echoes,redrawEchoes*3)
  end,debug.traceback)
  Geyser=original; assert(ok,err)
end)
test("disposed and rootless sound views reject setters rendering layout and retired callbacks",function()
  for _,dispose in ipairs({true,false}) do
    local view=chatView(); local calls=0; local layout=require("layout").compute(1200,800)
    view:applyLayout(layout); view:showChatSettings()
    view:setOptionsActionCallback(function() calls=calls+1; return true end)
    local callbacks={view.chat_sound_rows.STAFF.enabled.click,view.chat_sound_rows.STAFF.previous.click,view.chat_sound_rows.STAFF.next.click,view.chat_sound_rows.STAFF.preview.click,view.chat_sound_volume_down.click,view.chat_sound_volume_up.click,view.option_action_buttons.chat_settings.click,view.chat_settings_close.click,view.chat_settings_visibility.click,view.chat_settings_clear_visible.click,view.chat_settings_clear_saved.click}
    local root=view.root; local rootDelete=root.delete
    function root:delete()
      eq(view.disposed,true); eq(view.root,nil); eq(view.options_action_callback,nil)
      for _,callback in ipairs(callbacks) do eq(callback(),nil) end
      return rootDelete(self)
    end
    if dispose then assert(view:delete()); assert(view:delete()) else view.root=nil end
    local config=view.chat_sounds; local nativeCalls=0
    for _,widget in ipairs(view:chatSettingsWidgets()) do
      for _,name in ipairs({"echo","setStyleSheet","setToolTip","move","resize","show","hide","delete","get_width"}) do
        widget[name]=function() nativeCalls=nativeCalls+1; error("retired native widget touched") end
      end
    end
    for _,invoke in ipairs({
      function() return view:setChatSounds({volume=20}) end,
      function() return view:renderChatSounds() end,
      function() return view:syncChatSoundRows() end,
      function() return view:createChatSoundControls() end,
      function() return view:showChatSettings() end,
      function() return view:hideChatSettings() end,
      function() return view:layoutChatSettings(layout) end,
      function() return view:layoutChatSounds(600,0,12) end,
      function() return view:renderChatSettings() end,
      function() return view:cycleChatSound("STAFF",1) end,
      function() return view:changeChatSound("chat_sound_preview","STAFF","staff") end,
    }) do local accepted,why=invoke(); eq(accepted,nil); assert(why:find("unavailable",1,true)) end
    for _,callback in ipairs(callbacks) do eq(callback(),nil) end
    eq(view.chat_sounds,config); eq(nativeCalls,0); eq(calls,0)
    eq(View.validateReusable(view,view.settings),nil)
  end
end)
test("showing the HUD repaints chat settings changed while its root was hidden",function()
  local original=Geyser; local geyser=fakeGeyser(); local newContainer=geyser.Container.new
  function geyser.Container:new(cons,parent)
    local item=newContainer(self,cons,parent)
    if cons.name=="DGHUD.Root" then
      function item:show(automatic)
        if automatic then self.auto_hidden=false else self.hidden=false end
        self.visible=not (self.hidden or self.auto_hidden)
      end
    end
    return item
  end
  Geyser=geyser
  local ok,err=xpcall(function()
    for _,automatic in ipairs({false,true}) do
      local settings=require("settings").resolve(require("defaults"),{})
      local view=View.new(settings); view:applyLayout(require("layout").compute(1200,800)); view:showChatSettings()
      assert(view.chat_sound_rows.STAFF.enabled.message:find("ON",1,true))
      if automatic then view.root.auto_hidden=true else view.root.hidden=true end
      local config=require("chat_sounds").defaults(); config.tabs.STAFF.enabled=false
      settings.chat.sounds=config; assert(view:setChatSounds(config)); eq(view.chat_settings_dirty,true)
      assert(view.chat_sound_rows.STAFF.enabled.message:find("ON",1,true))
      view.root:show(automatic)
      assert(view.chat_sound_rows.STAFF.enabled.message:find("OFF",1,true)); eq(view.chat_settings_dirty,false)
      local root=view.root; view:delete(); eq(root:show(),nil)
    end
  end,debug.traceback)
  Geyser=original; assert(ok,err)
end)
test("failed native view deletion keeps a cleanup handle without reviving callbacks",function()
  local view=chatView(); local root=view.root; local nativeDelete=root.delete; local calls=0
  local callback=view.chat_sound_rows.STAFF.enabled.click
  function root:delete()
    calls=calls+1; eq(view.disposed,true); eq(view.root,nil); eq(callback(),nil)
    local again,why=view:delete(); eq(again,nil); assert(why:find("already running",1,true))
    if calls==1 then error("native cleanup interrupted") end
    return nativeDelete(self)
  end
  local ok,why=pcall(view.delete,view); eq(ok,false); assert(why:find("native cleanup interrupted",1,true))
  eq(view._pending_delete_root,root); eq(View.validateReusable(view,view.settings),nil)
  assert(view:delete()); eq(calls,2); eq(view._pending_delete_root,nil)
  assert(view:delete()); eq(calls,2)
end)
test("a save callback that disposes the view cannot resume painting retired controls",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view:showChatSettings()
  local before=view.chat_sounds; local calls=0
  view:setOptionsActionCallback(function()
    calls=calls+1; view:delete()
    for _,widget in ipairs(view:chatSettingsWidgets()) do
      widget.echo=function() error("post-save echo after disposal") end
      widget.setStyleSheet=function() error("post-save style after disposal") end
    end
    return false
  end)
  local saved,err=view.chat_sound_rows.STAFF.enabled.click()
  eq(saved,nil); assert(err:find("unavailable",1,true)); eq(calls,1); eq(view.chat_sounds,before)
end)
test("removed custom sound rows retire callbacks before native deletion and recreation",function()
  local view=chatView(); view:renderChat({},{"QUEST"},"ALL")
  local old=view.chat_sound_rows.QUEST; local calls=0
  view:setOptionsActionCallback(function() calls=calls+1; return true end)
  local remove=old.caption.delete
  function old.caption:delete()
    eq(view.chat_sound_rows.QUEST,nil)
    eq(old.enabled.click(),nil); eq(old.previous.click(),nil); eq(old.next.click(),nil); eq(old.preview.click(),nil)
    return remove(self)
  end
  view:renderChat({},{},"ALL"); view:renderChat({},{"QUEST"},"ALL")
  eq(view.chat_sound_rows.QUEST==old,false)
  eq(old.enabled.click(),nil); eq(old.preview.click(),nil); eq(calls,0)
  eq(view.chat_sound_rows.QUEST.enabled.click(),true); eq(calls,1)
end)
test("chat sound show hide resize redraw and reuse never trigger playback",function()
  local Sounds=require("chat_sounds"); local config=Sounds.defaults(); config.tabs.ROOM.enabled=true
  local view=chatView(nil,nil,nil,nil,config); local calls=0; local oldPlay=rawget(_G,"playSoundFile")
  _G.playSoundFile=function() error("view must not play audio directly") end
  local ok,err=pcall(function()
    local function callback() calls=calls+1; return true end
    view:setOptionsActionCallback(callback)
    for _,size in ipairs({{320,260},{1920,1080}}) do
      view:applyLayout(require("layout").compute(size[1],size[2])); view:showChatSettings(); view:renderChatSettings(); view:hideChatSettings()
      for _,widget in ipairs(view:chatSettingsWidgets()) do eq(widget.visible,false) end
      view:renderChat({{category="STAFF",line="History replay"}},{"STAFF"},"ALL"); view:setChatSounds(config)
    end
    eq(calls,0); view:showChatSettings(); eq(view.chat_sound_rows.ROOM.preview.click(),true); eq(calls,1)
    assert(view:prepareForReuse(view.settings)); eq(view.chat_settings_visible,false); eq(calls,1)
    view:setOptionsActionCallback(callback); view:showChatSettings(); view:renderChat({{category="ROOM",line="Same saved entry"}},{"ROOM"},"ROOM")
    eq(calls,1); eq(view.chat_sounds.tabs.ROOM.enabled,true)
    local cold=chatView(nil,nil,nil,nil,config); cold:setOptionsActionCallback(callback); cold:showChatSettings(); cold:hideChatSettings(); eq(calls,1)
  end)
  _G.playSoundFile=oldPlay; assert(ok,err)
end)
test("reusable view validation requires intact sound controls",function()
  local view=chatView(); eq(View.validateReusable(view,view.settings),true)
  view.chat_sound_rows.STAFF.preview=nil
  local ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("sound control",1,true))
  view=chatView(); view.chat_sound_caption=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("chat_sound_caption",1,true))
end)
test("keybinding settings are editable responsive and save the full keypad",function()
  local view=chatView(); local saved; view:setOptionsActionCallback(function(action) if action=="keybindings_settings" then return {enabled=false,commands={["8"]="north",Plus="up"}} end end); view:setKeybindingSettingsCallback(function(values) saved=values; return true,nil,values,{active=0,conflicts={}} end); view:applyLayout(require("layout").compute(420,360)); view.color_toggle.click(); assert(view.option_action_buttons.keybindings_settings.click()); eq(view.keybindings_visible,true); eq(view.keybinding_fields["8"].input.text,"north"); view.keybindings_enable.click(); view.keybinding_fields["0"].input:print("look"); assert(view.keybindings_save.click()); eq(saved.enabled,true); eq(saved.commands["0"],"look"); eq(view.keybindings_visible,false)
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
    local bottom=0
    for _,key in ipairs(view.option_action_order) do
      local button=view.option_action_buttons[key]
      eq(button.parent,view.options_scroll); eq(button.visible,true)
      eq(button.x>=0,true); eq(button.x+button.width<=view.options_scroll.width,true)
      eq(button.y,bottom); eq(button.height>=30,true); bottom=button.y+button.height
    end
    eq(view.options_scroll.content_height,bottom)
    if size[2]<=120 then eq(view.options_scroll.content_height>view.options_scroll.height,true) end
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

local function rollerSessionFixture()
  local summary={active=true,rolls=12,stat_rolls=12,pool_rolls=0,best_total=66,average=60,maximum=77,phase="Waiting for next roll",stats={},pool={},unmet={}}
  for _,name in ipairs({"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","PRE","PER","LUK"}) do
    summary.stats[#summary.stats+1]={name=name,value=6,label="Good",roll=12,target=7,target_label="Great"}
  end
  return summary
end
local function rollerSessionHtml(view) return view.roller_session_best.message or "" end

test("autoroller session snapshots are defensive and never open the modal",function()
  local view=chatView(); view:applyLayout(require("layout").compute(420,280))
  local summary=rollerSessionFixture(); summary.pool={{slot=1,value=7,label="Great",roll=5}}; summary.unmet={summary.stats[1]}
  assert(view:setRollerSession(summary))
  summary.rolls=999; summary.stats[1].label="changed"; summary.pool[1].label="changed"; summary.unmet[1].target=1
  eq(view.roller_session.rolls,12); eq(view.roller_session.stats[1].label,"Good"); eq(view.roller_session.pool[1].label,"Great"); eq(view.roller_session.unmet[1].target,7)
  eq(view.roller_settings_visible,false); eq(view.roller_overlay.visible,false); eq(view.roller_session_best.visible,false)
  view:showRollerSettings({use_min_stats=true,min_stats={STR=7}})
  assert(rollerSessionHtml(view):find("Confirmed rolls: 12",1,true)); assert(rollerSessionHtml(view):find("Best total: 66/77",1,true))
  eq(view.roller_session_best.parent,view.roller_content); eq(view.roller_action_buttons.roller_start.y,0)
  eq(view.roller_session_best.y>view.roller_action_buttons.roller_start.height,true)
end)

test("autoroller session defaults to eleven empty current stat rows",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view:showRollerSettings({})
  local html=rollerSessionHtml(view)
  assert(html:find("Best total: —/77",1,true)); assert(html:find("Observed highs are not confirmed race/class limits; targets never auto lowered.",1,true))
  for _,name in ipairs({"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","PRE","PER","LUK"}) do
    assert(html:find("<td>"..name.."</td><td>—</td><td>—</td><td>—</td>",1,true))
  end
  local _,rows=html:gsub("<tr>",""); eq(rows,12)
  assert(view:setRollerSession({stats={}})); eq(rollerSessionHtml(view),html)
  view:setRollerSession(rollerSessionFixture()); assert(view:setRollerSession(nil)); eq(rollerSessionHtml(view),html)
  eq(view.roller_draft.min_stats.STR,nil)
end)

test("autoroller shows supplied ranks and orange unmet targets without claiming a cap",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view:showRollerSettings({})
  local summary=rollerSessionFixture(); summary.stats[2].target=6; summary.stats[2].target_label="Good"; summary.stats[3].target=nil
  summary.stats[4].value=nil; summary.stats[4].label=nil; summary.stats[4].roll=nil
  view:setRollerSession(summary); local html=rollerSessionHtml(view)
  assert(html:find("<td>STR</td><td><span style='color:#ffb347'><b>Great (7)</b></span></td><td>Good (6)</td><td>12</td>",1,true))
  assert(html:find("<td>INT</td><td>Good (6)</td><td>Good (6)</td>",1,true))
  assert(html:find("<td>WIS</td><td>—</td><td>Good (6)</td>",1,true))
  assert(html:find("<td>DEX</td><td><span style='color:#ffb347'><b>Great (7)</b></span></td><td>—</td><td>—</td>",1,true))
  eq(html:find("capped",1,true),nil); eq(summary.stats[1].target,7)
  for _,row in ipairs(summary.stats) do row.target=nil end
  view:setRollerSession(summary); eq(rollerSessionHtml(view):find("color:#ffb347",1,true),nil)
end)

test("autoroller uses captured legacy names instead of assigning current names",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view:showRollerSettings({})
  local summary=rollerSessionFixture(); summary.stats[9].name="VOI"; summary.stats[11].name="APP"
  summary.stats[12]={name="MP",value=7,label="Great",roll=4}
  view:setRollerSession(summary); local html=rollerSessionHtml(view)
  for _,name in ipairs({"VOI","APP","MP"}) do assert(html:find("<td>"..name.."</td>",1,true)) end
  eq(html:find("<td>PRE</td>",1,true),nil); eq(html:find("<td>LUK</td>",1,true),nil)
end)

test("autoroller pool highs stay explicitly unassigned until named stats are captured",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view:showRollerSettings({})
  local summary=rollerSessionFixture(); summary.stat_rolls=0; summary.pool_rolls=5; summary.rolls=5
  for _,row in ipairs(summary.stats) do row.value=nil; row.label=nil; row.roll=nil end
  summary.pool={{slot=1,value=7,label="Great",roll=5},{slot=2,value=6,label="Good",roll=2}}
  view:setRollerSession(summary); local html=rollerSessionHtml(view)
  assert(html:find("Pool values are unassigned; per-stat limits cannot be inferred.",1,true))
  assert(html:find("<td>1</td><td>Great (7)</td><td>5</td>",1,true))
  assert(html:find("<td>2</td><td>Good (6)</td><td>2</td>",1,true))
  eq(html:find("<td>STR</td>",1,true),nil); eq(html:find("<b>Target</b>",1,true),nil)
  summary.stat_rolls=1; summary.stats[1].value=5; summary.stats[1].label="Fair"; summary.stats[1].roll=6
  view:setRollerSession(summary); html=rollerSessionHtml(view)
  assert(html:find("<td>STR</td>",1,true)); assert(html:find("RANKED POOL-SLOT HIGHS",1,true))
end)

test("autoroller escapes every supplied label name phase and late warning",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view:showRollerSettings({})
  local summary=rollerSessionFixture(); summary.stat_rolls=100; summary.phase="<phase&>"; summary.stats[1].name="<STR&>"
  summary.stats[1].label="<Good&>"; summary.stats[1].target_label="<Great&>"; summary.pool={{slot=1,value=7,label="<Pool&>",roll=5}}
  summary.warning="After 100 complete stat rolls, <minimum&> unseen. Observed highs are not confirmed limits."
  view:setRollerSession(summary); local html=rollerSessionHtml(view)
  for _,label in ipairs({"phase","STR","Good","Great","Pool","minimum"}) do
    assert(html:find("&lt;"..label.."&amp;&gt;",1,true)); eq(html:find("<"..label,1,true),nil)
  end
end)

test("autoroller conditional warning appears after 100 stat rolls without shifting controls",function()
  local view=chatView(); view:applyLayout(require("layout").compute(420,280)); view:showRollerSettings({})
  local summary=rollerSessionFixture(); summary.stat_rolls=99; summary.rolls=199; summary.pool_rolls=100
  summary.warning="After 100 complete stat rolls, some configured minimums have not been seen. Observed highs are not confirmed limits."
  view:setRollerSession(summary); eq(rollerSessionHtml(view):find("After 100",1,true),nil)
  local y,height=view.roller_fields.STR.input.y,view.roller_content.content_height
  summary.stat_rolls=100; view:setRollerSession(summary)
  assert(rollerSessionHtml(view):find("After 100",1,true)); eq(view.roller_fields.STR.input.y,y); eq(view.roller_content.content_height,height)
  summary.warning=nil; view:setRollerSession(summary); eq(rollerSessionHtml(view):find("After 100",1,true),nil)
end)

test("autoroller live refresh stop and reset preserve all inputs draft error and scroll",function()
  local view=chatView(); view:applyLayout(require("layout").compute(420,280))
  view:showRollerSettings({use_min_stats=true,arrange_mode="minimums",min_stats={STR=7}})
  local draft=view.roller_draft; view.roller_error="unsaved validation error"; local inputs={}
  for key,field in pairs(view.roller_fields) do
    local text="unsaved "..key; field.input:print(text); inputs[key]={widget=field.input,text=text,x=field.input.x,y=field.input.y}
    field.input.print=function() error("live session update repopulated a settings field") end
    field.input.move=function() error("routine session update moved a settings field") end
  end
  view.roller_content.currentScroll=800
  view.roller_content.move=function() error("session refresh moved the scrollbox") end
  view.roller_content.resize=function() error("session refresh resized the scrollbox") end
  view.roller_content.scrollTo=function() error("session refresh reset the scroll") end
  for _,summary in ipairs({rollerSessionFixture(),{active=false,rolls=12,stat_rolls=12,stats=rollerSessionFixture().stats},{rolls=0,stats={}},{}}) do
    assert(view:setRollerSession(summary)); eq(view.roller_draft,draft); eq(view.roller_error,"unsaved validation error")
    eq(view.roller_settings_visible,true); eq(view.roller_content.currentScroll,800); eq(draft.min_stats.STR,7); eq(draft.arrange_mode,"minimums")
    for key,input in pairs(inputs) do eq(view.roller_fields[key].input,input.widget); eq(input.widget.text,input.text); eq(input.widget.x,input.x); eq(input.widget.y,input.y) end
  end
end)

test("autoroller section growth preserves scroll and never shrinks the open scroll extent",function()
  local view=chatView(); view:applyLayout(require("layout").compute(420,280)); view:showRollerSettings({min_stats={STR=7}})
  local draft=view.roller_draft; local y,height=view.roller_fields.STR.input.y,view.roller_content.content_height
  view.roller_content.currentScroll=500; view.roller_fields.STR.input:print("unsaved 7")
  local summary=rollerSessionFixture()
  for slot=1,11 do summary.pool[slot]={slot=slot,value=6,label="Good",roll=slot} end
  view:setRollerSession(summary)
  eq(view.roller_content.currentScroll,500); eq(view.roller_draft,draft); eq(view.roller_fields.STR.input.text,"unsaved 7")
  local delta=view.roller_content.content_height-height
  eq(delta>0,true); eq(view.roller_fields.STR.input.y,y+delta)
  height=view.roller_content.content_height; y=view.roller_fields.STR.input.y
  view:setRollerSession(nil); eq(view.roller_content.content_height,height); eq(view.roller_fields.STR.input.y,y); eq(view.roller_content.currentScroll,500)
end)

test("autoroller session layout fits narrow modals and keeps the section before settings",function()
  local view=chatView(); local summary=rollerSessionFixture()
  for slot=1,11 do summary.pool[slot]={slot=slot,value=7,label="Great",roll=slot} end
  view:setRollerSession(summary); view:showRollerSettings({})
  for _,size in ipairs({{420,280},{420,500},{760,700},{1200,800},{1920,1080}}) do
    view:applyLayout(require("layout").compute(size[1],size[2]))
    local section=view.roller_session_best; eq(section.visible,true); eq(section.parent,view.roller_content)
    for _,key in ipairs({"roller_start","roller_stop","roller_stats"}) do
      local action=view.roller_action_buttons[key]; eq(action.y,0); eq(action.visible,true)
      eq(action.y+action.height<section.y,true); eq(action.x+action.width<=view.roller_content.width,true)
    end
    eq(section.x+section.width<=view.roller_content.width,true)
    eq(view.roller_arrange_caption.y>section.y+section.height,true)
    eq(view.roller_fields.target_total.caption.y>section.height,true)
    eq(view.roller_content.content_height>section.height,true); eq(view.roller_content.height>0,true)
    if size[1]==420 then eq(rollerSessionHtml(view):find("Seen on roll",1,true),nil) else assert(rollerSessionHtml(view):find("Seen on roll",1,true)) end
    eq(view.roller_save.y+view.roller_save.height<=view.roller_panel.height,true)
  end
end)

test("autoroller SESSION BEST button keeps the existing stats action and draft",function()
  local view=chatView(); view:applyLayout(require("layout").compute(420,280)); view:showRollerSettings({})
  local draft=view.roller_draft; view.roller_fields.STR.input:print("7")
  view:setOptionsActionCallback(function(action) eq(action,"roller_stats"); view:setRollerSession(rollerSessionFixture()); return true end)
  local button=view.roller_action_buttons.roller_stats
  eq(button.option_text,"SESSION BEST"); assert(button.message:find("SESSION BEST",1,true)); assert(button.click())
  eq(view.roller_settings_visible,true); eq(view.roller_draft,draft); eq(view.roller_fields.STR.input.text,"7")
end)

test("autoroller session widget participates in reuse visibility and retirement",function()
  local view=chatView(); view:applyLayout(require("layout").compute(420,280)); view:showRollerSettings({})
  view:setRollerSession(rollerSessionFixture()); local label=view.roller_session_best
  view:hideRollerSettings(); eq(label.visible,false); view:setRollerSession({rolls=4}); eq(label.visible,false)
  view:showRollerSettings({}); assert(rollerSessionHtml(view):find("Confirmed rolls: 4",1,true))
  assert(View.validateReusable(view,view.settings)); assert(view:prepareForReuse(view.settings))
  eq(view.roller_session,nil); eq(label.visible,false); eq(view.roller_session_best,label)
  view:showRollerSettings({}); assert(rollerSessionHtml(view):find("Confirmed rolls: 0",1,true))
  view:delete(); local message=label.message; local ok=view:setRollerSession(rollerSessionFixture())
  eq(ok,nil); eq(view.roller_session,nil); eq(label.message,message); eq(view:renderRollerSession(),false)
  view=chatView(); view.roller_session_best=nil
  local valid,err=View.validateReusable(view,view.settings); eq(valid,nil); assert(err:find("roller_session_best",1,true))
end)

test("autoroller high callbacks retain unsaved values through phases and confirmed roll counts",function()
  local view=chatView(); view:applyLayout(require("layout").compute(420,280))
  view:showRollerSettings({use_min_stats=true,min_stats={STR=7}})
  local draft=view.roller_draft; view.roller_fields.STR.input:print("pending Great"); view.roller_fields.target_total.input:print("pending 70")
  local summary=rollerSessionFixture(); local y=view.roller_fields.STR.input.y
  for _,phase in ipairs({"Capturing roll","Waiting for prompt","Reroll delay","Waiting for next roll","Result held","Idle"}) do
    summary.phase=phase; summary.rolls=1000; summary.stat_rolls=100
    summary.warning="After 100 complete stat rolls, some configured minimums have not been seen. Observed highs are not confirmed limits."
    view:setRollerSession(summary)
    eq(view.roller_draft,draft); eq(view.roller_fields.STR.input.text,"pending Great"); eq(view.roller_fields.target_total.input.text,"pending 70")
    eq(view.roller_fields.STR.input.y,y); eq(view.roller_settings_visible,true)
    assert(rollerSessionHtml(view):find("Confirmed rolls: 1,000",1,true)); assert(rollerSessionHtml(view):find(phase,1,true))
  end
end)

test("autoroller mixed twelve then eleven pool slots refresh locally in a narrow modal",function()
  local view=chatView(); view:applyLayout(require("layout").compute(420,280)); view:showRollerSettings({min_stats={STR=7}})
  local summary=rollerSessionFixture(); summary.pool_rolls=1
  for slot=1,12 do summary.pool[slot]={slot=slot,value=6,label="Good",roll=slot} end
  view:setRollerSession(summary); local label=view.roller_session_best; local draft=view.roller_draft
  view.roller_content.currentScroll=700; view.roller_fields.STR.input:print("unsaved 7")
  local y,height=view.roller_fields.STR.input.y,view.roller_content.content_height
  assert(rollerSessionHtml(view):find("<td>12</td><td>Good (6)</td>",1,true))
  summary.pool[12]=nil; summary.pool_rolls=2; summary.rolls=14; view:setRollerSession(summary)
  eq(view.roller_session_best,label); eq(view.roller_draft,draft); eq(view.roller_fields.STR.input.text,"unsaved 7")
  eq(view.roller_content.currentScroll,700); eq(view.roller_fields.STR.input.y,y); eq(view.roller_content.content_height,height)
  eq(rollerSessionHtml(view):find("<td>12</td><td>Good (6)</td>",1,true),nil)
  assert(rollerSessionHtml(view):find("<td>11</td><td>Good (6)</td>",1,true)); assert(rollerSessionHtml(view):find("<td>STR</td>",1,true))
  eq(rollerSessionHtml(view):find("Seen on roll",1,true),nil)
  for _,key in ipairs({"roller_start","roller_stop","roller_stats"}) do eq(view.roller_action_buttons[key].y,0) end
end)

test("autoroller closed-modal callbacks store snapshots without rendering HTML",function()
  local view=chatView(); view:applyLayout(require("layout").compute(420,280)); view:showRollerSettings({}); view:hideRollerSettings()
  local label=view.roller_session_best; local echo=label.echo
  label.echo=function() error("closed-modal callback rendered session HTML") end
  eq(view:renderRollerSession(),false); assert(view:renderRollerSettings(false))
  for _,phase in ipairs({"Observing","Capturing roll","Waiting for next roll","Idle"}) do
    local summary=rollerSessionFixture(); summary.phase=phase; assert(view:setRollerSession(summary)); eq(view.roller_session.phase,phase)
    eq(view.roller_settings_visible,false); eq(label.visible,false); eq(view.roller_overlay.visible,false)
  end
  label.echo=echo; view:showRollerSettings({}); assert(rollerSessionHtml(view):find("Idle",1,true))
end)

test("autoroller reserves wrapped metrics and warning space at narrow widths and larger fonts",function()
  local view=chatView(); local summary=rollerSessionFixture()
  summary.phase="Waiting for the game to confirm a complete assignment board and an empty pool."
  local wide,wideHeight=View.rollerSessionContent(summary,view.settings.theme,14,760)
  local narrow,narrowHeight=View.rollerSessionContent(summary,view.settings.theme,14,376)
  eq(narrowHeight>wideHeight,true); assert(narrow:find("font-size:14px",1,true)); assert(wide:find("Seen on roll",1,true))
  summary.stat_rolls=100; summary.warning="Some minimums have not been seen after 100 complete stat rolls. Observed highs are not confirmed race/class limits; targets are unchanged."
  local warned,warnedHeight=View.rollerSessionContent(summary,view.settings.theme,14,376)
  eq(warnedHeight,narrowHeight); assert(warned:find(summary.warning,1,true))
  for _,font in ipairs({14,20,30}) do
    local layout=require("layout").compute(420,280); layout.body_font=font
    view:applyLayout(layout); view:setRollerSession(summary); view:showRollerSettings({})
    if font>=20 then eq(view.roller_session_best.height>=warnedHeight,true) end
    eq(view.roller_session_best.height>=12*24,true)
    eq(view.roller_arrange_caption.y>view.roller_session_best.y+view.roller_session_best.height,true)
    eq(view.roller_content.height>0,true); eq(view.roller_save.y+view.roller_save.height<=view.roller_panel.height,true)
    for _,key in ipairs({"roller_start","roller_stop","roller_stats"}) do eq(view.roller_action_buttons[key].y,0) end
  end
end)

test("autoroller rejects a preserved summary label in the wrong scroll container",function()
  local view=chatView(); view.roller_session_best.container=view.root
  local valid,err=View.validateReusable(view,view.settings); eq(valid,nil); assert(err:find("autoroller session parent",1,true))
end)

test("reusable view uses Geyser containers rather than superclass parents",function()
  withColorViewAdapter(function(adapter,settings)
    local view=adapter:createView(settings); local root=view.root
    view:setColorStyles({custom_rules={{phrase="gate",foreground="#FFFFFF",background=false,bold=false,underline=false,enabled=true}}})
    -- Real Geyser stores the owner in .container and inherits .parent from
    -- its widget class. setClickCallback stores .clickCallback, not .click.
    local superclass={name="WindowClass"}
    for _,widget in ipairs({view.roller_session_best,view.custom_highlight_rows[1]}) do
      local owner=widget.container
      widget.parent=nil
      setmetatable(widget,{__index={parent=superclass}})
      widget.clickCallback=widget.click; widget.click=nil
      eq(widget.parent,superclass); eq(widget.container,owner)
    end
    assert(View.validateReusable(view,settings))
    eq(assert(adapter:adoptView(view,settings)),view); eq(view.root,root); eq(root.deleted,nil)
    assert(View.validateReusable(view,settings))
  end)
end)

test("reusable view rejects missing and mismatched actual containers",function()
  for _,missing in ipairs({false,true}) do
    local view=chatView()
    view.roller_session_best.parent=view.roller_content
    if missing then view.roller_session_best.container=nil else view.roller_session_best.container=view.root end
    local valid,err=View.validateReusable(view,view.settings)
    eq(valid,nil); assert(err:find("autoroller session parent",1,true))
    view=chatView()
    view:setColorStyles({custom_rules={{phrase="gate",foreground="#FFFFFF",background=false,bold=false,underline=false,enabled=true}}})
    view.custom_highlight_rows[1].parent=view.custom_highlight_list
    if missing then view.custom_highlight_rows[1].container=nil else view.custom_highlight_rows[1].container=view.root end
    valid,err=View.validateReusable(view,view.settings)
    eq(valid,nil); assert(err:find("custom highlight row",1,true))
  end
end)

test("autoroller settings modal validates through one save callback and remains bounded",function()
  local view=chatView(); local received; view:setRollerSettingsCallback(function(values) received=values; if values.target_total=="bad" then return nil,"bad target" end; return true end)
  view:showRollerSettings({target_total=53,hard_stop=62,max_rolls=nil,reroll_delay=.1,reroll_command="reroll",arrange_mode="manual",minimum_greats=2,minimum_good_plus=5,auto_start_on_name=true,use_min_stats=true,require_min_stats_to_stop=true,logging_enabled=true,log_folder="rolls",master_file="master.txt",min_stats={STR=5,INT=5,WIS=5,DEX=5,AGI=5,CON=5,CHA=5,WIL=5,PRE=5,PER=5,LUK=5}})
  eq(view.roller_fields.reroll_command,nil)
  for _,size in ipairs({{420,280},{420,500},{760,700},{1200,800},{1920,1080}}) do local layout=require("layout").compute(size[1],size[2]); view:applyLayout(layout); eq(view.roller_panel.x>=0,true); eq(view.roller_panel.y>=0,true); eq(view.roller_panel.x+view.roller_panel.width<=size[1],true); eq(view.roller_panel.y+view.roller_panel.height<=size[2],true); eq(view.roller_content.parent,view.roller_panel); eq(view.roller_fields.STR.input.parent,view.roller_content); eq(view.roller_fields.INT.caption.y>=view.roller_fields.STR.input.y+view.roller_fields.STR.input.height,true); if layout.mode=="compact" then eq(view.roller_fields.STR.caption.x,view.roller_fields.target_total.caption.x); eq(view.roller_fields.STR.caption.y>view.roller_toggles.logging_enabled.y,true); eq(view.roller_arrange_buttons.manual.width>120,true); eq(view.roller_arrange_buttons.game_auto.x>view.roller_arrange_buttons.manual.x+view.roller_arrange_buttons.manual.width,true); eq(view.roller_arrange_buttons.minimums.y>view.roller_arrange_buttons.manual.y+view.roller_arrange_buttons.manual.height,true); eq(view.roller_arrange_buttons.minimums.width,view.roller_content.width) end end
  eq(view.roller_draft.arrange_mode,"manual"); eq(view.roller_arrange_buttons.manual.width>0,true); view.roller_arrange_buttons.game_auto.click(); eq(view.roller_draft.arrange_mode,"game_auto"); view.roller_arrange_buttons.minimums.click(); eq(view.roller_draft.arrange_mode,"minimums"); eq(view.roller_arrange_buttons.minimums.x+view.roller_arrange_buttons.minimums.width<=view.roller_content.width,true)
  view.roller_fields.target_total.input.text="bad"; local ok,err=view:saveRollerSettings(); eq(ok,nil); eq(err,"bad target"); eq(view.roller_settings_visible,true)
  view.roller_fields.target_total.input.text="60"; assert(view:saveRollerSettings()); eq(received.target_total,"60"); eq(received.arrange_mode,"minimums"); eq(received.minimum_greats,"2"); eq(received.minimum_good_plus,"5"); eq(received.min_stats.LUK,"5"); eq(view.roller_settings_visible,false)
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

test("weapons skill group appears in the visible and copyable help guide",function()
  local view=chatView(); local copied
  view:setCopyTextCallback(function(value) copied=value; return true end)
  view:applyLayout(require("layout").compute(1000,700)); view:showHelp()
  assert(view.help_copy.click()); assert(type(copied)=="string")
  for _,fragment in ipairs({"skill weapons","Sharp, Blunt, Pole, Throw, and Missile Weapons",
      "Biting, Clawing, Breath Weapon, Webbing, and Stinging"}) do
    assert(view.help_content.message:find(fragment,1,true),"missing visible weapons help: "..fragment)
    assert(copied:find(fragment,1,true),"missing copyable weapons help: "..fragment)
  end
end)

test("color grouped skill commands appear in visible and copyable help",function()
  local view=chatView(); local copied
  view:setCopyTextCallback(function(value) copied=value; return true end)
  view:applyLayout(require("layout").compute(1000,700)); view:showHelp()
  assert(view.help_copy.click()); assert(type(copied)=="string")
  for _,command in ipairs({"skill combat","skill utility","skill train"}) do
    assert(view.help_content.message:find(command,1,true),"missing visible help: "..command)
    assert(copied:find(command,1,true),"missing copyable help: "..command)
  end
  for _,kind in ipairs({"combat","utility"}) do
    local text="Show all "..kind.." skills, including ready-to-train skills. Zero-use rows stay green."
    assert(view.help_content.message:find(text,1,true),"missing inclusive help: "..kind)
    assert(copied:find(text,1,true),"missing copyable inclusive help: "..kind)
  end
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
test("multiview panes retain all Combat fields and top-aligned readable scrollable lists",function()
  local Layout=require("layout")
  local state={character={full_name="Test",physical={}},attributes={},combat={body_armor=100,stance="Aggressive",or_rating=125,dr=315},equipment={items={}},inventory={items={{name="Torch",weight=.1}}},runes={items={{name="Force",remaining=10}}},skills={items={{name="Biting",level=4,remain=105}}},vitals={hp={current=1,maximum=1},fatigue={current=1,maximum=1},carry={current=25.7,maximum=255,percent=10.1},psi={visible=false},web={visible=false},gold=12345,silver=98765,roundtime=12,position=-1,standing=true},room={name="Room",players={},flags={},exits={}}}
  for _,width in ipairs({800,900,960,1000,1075,1100}) do
    for _,height in ipairs({600,1000}) do
      local view=chatView(8); local layout=Layout.compute(width,height)
      view.last_state=state; view:applyLayout(layout); view:update(state)
      eq(layout.details_columns,1); eq(view.details.visible,true)
      eq(view.details.message:find("<table",1,true),nil)
      for _,value in ipairs({"100%","Aggressive","125","315","12","-1","Standing"}) do assert(view.details.message:find(value,1,true),value) end
      eq(view.details.y+view.details.height<=view.right_list_tabs.inventory.y,true)
      eq(view.details.width+layout.panel_padding*2,layout.right)
      assert(view.details.style:find("qproperty-alignment: 'AlignTop | AlignLeft'",1,true))
      for _,key in ipairs({"inventory","runes","skills"}) do
        view.right_list_tabs[key].click()
        local card,output,content=view[key],view[key.."_output"],view[key.."_content"]
        eq(card.visible,true); eq(output.visible,true); eq(content.visible,true)
        eq(content.fontSize,13); eq(view.list_measure.fontSize,content.fontSize)
        assert(content.style:find("qproperty-alignment: 'AlignTop | AlignLeft'",1,true))
        eq(content.x,0); eq(content.y,0); eq(content.width>output.width,true)
        eq(output.height>=layout.list_row_height+layout.list_horizontal_scrollbar_height,true)
        eq(output.y+output.height<=card.y+card.height,true)
        eq(card.y+card.height<=height-12,true)
        if key=="inventory" then
          eq(output.y+output.height<=view.inventory_footer.y,true)
          for _,value in ipairs({"12345gp","98765sp","25.7","255","10.1%"}) do assert(view.inventory_footer.message:find(value,1,true),value) end
        end
      end
      -- Resize alone must repaint the Combat structure without waiting for GMCP.
      view:applyLayout(Layout.compute(1920,1080)); eq(view.layout.details_columns,2)
      assert(view.details.message:find("<table",1,true))
      view:applyLayout(Layout.compute(width,height)); eq(view.layout.details_columns,1)
      eq(view.details.message:find("<table",1,true),nil)
      assert(view.inventory_content.style:find("AlignTop | AlignLeft",1,true))
    end
  end
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
test("map settings treat every missing submap choice as off",function()
  local view=chatView(); view:showMapSettings({transition_submaps={}})
  assert(view.map_settings_status.message:find("Solid: directions. Dotted: special exits.",1,true))
  local values=view:mapSettingsValues()
  for _,key in ipairs({"gate","portal","door","arch","path","other"}) do eq(view.map_settings_draft[key],false); eq(values.transition_submaps[key],false) end
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

local function shortPaneInventoryState(count)
  local items={}; for index=1,count do items[index]={name="A long carried item name "..index,weight=12.3} end
  return {character={full_name="Test",physical={}},attributes={},combat={},equipment={items={}},inventory={items=items},runes={items={}},skills={items={}},
    vitals={hp={current=1,maximum=1},fatigue={current=1,maximum=1},carry={current=174.4,maximum=354,percent=49.3},psi={visible=false},web={visible=false},gold=12345,silver=98765,roundtime=0,position=0},
    room={name="R",players={},flags={},exits={}}}
end
local function assertInventoryRowFits(view,layout)
  local output=view.inventory_output
  local scrollbar=view.inventory_horizontal_overflow and layout.list_horizontal_scrollbar_height or 0
  eq(output.visible,true); eq(output.height>=layout.list_row_height+scrollbar,true)
  eq(output.y>=view.inventory.y,true); eq(output.y+output.height<=view.inventory.y+view.inventory.height,true)
  eq(view.inventory_content.width>=view.list_viewport_width,true)
  eq(view.inventory_content.fontSize,layout.list_font)
  if view.inventory_footer_scrolling then
    local footer=view.inventory_scroll_footer
    eq(view.inventory_footer.visible,false); eq(footer.visible,true); eq(footer.parent,output)
    eq(footer.fontSize,layout.list_font+2)
    eq(footer.y>=view.inventory_content.y+view.inventory_content.height,true)
    eq(footer.x+footer.width<=output.width-view.list_resolved_scrollbar_width,true)
    -- Each footer line must fit above the horizontal scrollbar even when the
    -- footer as a whole needs vertical scrolling.
    eq(footer.height/view.inventory_footer_rows<=output.height-scrollbar,true)
    assert(footer.message:find("12345gp",1,true)); assert(footer.message:find("98765sp",1,true)); assert(footer.message:find("49.3%",1,true))
  else
    eq(view.inventory_scroll_footer.visible,false)
    eq(output.y+output.height<=view.inventory_footer.y,true)
  end
end
test("short MultiView panes keep a full inventory row and scrollbars at normal and large font sizes",function()
  local Layout=require("layout")
  for _,width in ipairs({800,960,1075}) do
    for _,scale in ipairs({1,1.1}) do
      for _,count in ipairs({0,1,40}) do
        local view=chatView(7,24); local state=shortPaneInventoryState(count)
        local layout=Layout.compute(width,500,nil,nil,state.vitals,{side_text_scale=scale})
        view:applyLayout(layout); view:update(state)
        eq(layout.list_font,scale==1 and 13 or 14)
        assertInventoryRowFits(view,layout)
        view:applyLayout(layout); view:renderInventory(state)
        assertInventoryRowFits(view,layout)
      end
    end
  end
end)
test("408px Large inventory reduces only local vertical padding to fit a row and scrollbar",function()
  local Layout=require("layout"); local view=chatView(7,24); local state=shortPaneInventoryState(1)
  for _,height in ipairs({408,500,408}) do
    local layout=Layout.compute(800,height,nil,nil,state.vitals,{side_text_scale=1.1})
    view:applyLayout(layout); view:update(state)
    local output,card=view.inventory_output,view.inventory
    eq(layout.list_padding,7); eq(layout.list_font,14); eq(view.inventory_content.fontSize,14)
    eq(view.inventory_scroll_footer.fontSize,16); eq(view.inventory_footer_scrolling,true)
    eq(output.height>=layout.list_row_height+layout.list_horizontal_scrollbar_height,true)
    eq(output.y+output.height<=card.y+card.height,true)
    if height==408 then
      eq(view.inventory_title.visible,false); eq(output.height,40)
      eq(output.y-card.y,4); eq(card.y+card.height-output.y-output.height,4)
    else
      eq(view.inventory_title.visible,true); eq(output.y-card.y,layout.list_padding+layout.list_row_height+4)
    end
    local outputHeight=output.height
    view.right_list_tabs.runes.click()
    eq(view.runes_output.y-view.runes.y,layout.list_padding+layout.list_row_height+4)
    view.right_list_tabs.inventory.click(); eq(view.inventory_output.height,outputHeight)
  end
end)
test("inventory footer changes between fixed and scrolling on height font and tab transitions",function()
  local Layout=require("layout"); local view=chatView(7,24); local state=shortPaneInventoryState(1)
  for _,size in ipairs({{800,500,1},{800,800,1},{800,500,1.1},{960,500,1},{1075,500,1.1},{1920,1080,1},{799,600,1},{800,500,1.1}}) do
    local layout=Layout.compute(size[1],size[2],nil,nil,state.vitals,{side_text_scale=size[3]})
    view:applyLayout(layout); view:update(state)
    if layout.mode=="compact" then
      eq(view.inventory_scroll_footer.visible,false); eq(view.inventory_footer_scrolling,false)
    else
      assertInventoryRowFits(view,layout)
      if size[2]==500 then eq(view.inventory_footer_scrolling,true) else eq(view.inventory_footer_scrolling,false) end
      if layout.right_lists_mode=="tabbed" then
        for _,tab in ipairs({"runes","skills","inventory"}) do
          view.right_list_tabs[tab].click()
          if tab=="inventory" then assertInventoryRowFits(view,layout)
          else
            eq(view.inventory_scroll_footer.visible,false); eq(view.inventory_footer.visible,false)
            eq(view.inventory_scroll_footer.y,0); eq(view.inventory_scroll_footer.height,1)
          end
        end
      end
    end
  end
end)
test("scrolling inventory footer follows changing item counts and safely renders updated values",function()
  local Layout=require("layout"); local view=chatView(7,24)
  for _,count in ipairs({40,1,0,12}) do
    local state=shortPaneInventoryState(count)
    local layout=Layout.compute(800,500,nil,nil,state.vitals,{side_text_scale=1.1})
    view:applyLayout(layout); view:update(state); assertInventoryRowFits(view,layout)
    eq(view.inventory_content.height,math.max(1,count*layout.list_row_height))
    state.vitals.gold="<gold>"; state.vitals.carry.percent="<percent>"
    view:renderInventory(state)
    assert(view.inventory_scroll_footer.message:find("&lt;gold&gt;",1,true))
    assert(view.inventory_scroll_footer.message:find("&lt;percent&gt;",1,true))
    eq(view.inventory_scroll_footer.y,view.inventory_content.height+4)
  end
end)
test("refreshing a scrolling inventory never temporarily removes its footer scroll extent",function()
  local view=chatView(7,24); local state=shortPaneInventoryState(40)
  local layout=require("layout").compute(800,500,nil,nil,state.vitals,{side_text_scale=1.1})
  view:applyLayout(layout); view:update(state); eq(view.inventory_footer_scrolling,true)
  local footer=view.inventory_scroll_footer; local bottom=footer.y+footer.height
  local move,resize,hide=footer.move,footer.resize,footer.hide
  function footer:move(x,y) eq(y+self.height>=bottom,true); return move(self,x,y) end
  function footer:resize(width,height) eq(self.y+height>=bottom,true); return resize(self,width,height) end
  function footer:hide() error("visible footer removed during inventory refresh") end
  view:applyLayout(layout); view:update(state); assertInventoryRowFits(view,layout)
  footer.move=move; footer.resize=resize; footer.hide=hide
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
test("rail footer rows scale measured point-font height in tabbed and stacked layouts",function()
  for _,case in ipairs({{960,1000,6},{1920,1080,13}}) do
    for _,measuredRow in ipairs({20,26}) do
      local layout=require("layout").compute(case[1],case[2]); local view=chatView(case[3])
      view.list_measure.getSizeHint=function() return case[3]*10,measuredRow*5 end
      view.last_state={vitals={psi={visible=false},web={visible=false},gold=3,silver=9,carry={current=174.4,maximum=354,percent=49.3}},equipment={items={}},inventory={items={{name="Torch",weight=.1}}}}
      view:applyLayout(layout)
      eq(layout.list_font,13); eq(layout.list_row_height,measuredRow); eq(view.inventory_footer.fontSize,15)
      eq(view.inventory_footer_rows,3); eq(view.inventory_footer.visible,true)
      local expected=math.ceil(measuredRow*15/13)
      eq(view.inventory_footer.height,expected*3+6)
      eq(view.inventory_output.y+view.inventory_output.height<=view.inventory_footer.y,true)
      eq(view.inventory_footer.y+view.inventory_footer.height<=view.inventory.y+view.inventory.height,true)
      assert(view.inventory_footer.message:find("49.3%",1,true))
    end
  end
end)
test("compact footer scales measured line height before deciding whether it fits",function()
  for _,measuredRow in ipairs({15,17}) do
    local layout=require("layout").compute(320,700); local view=chatView(13)
    view.list_measure.getSizeHint=function() return 130,measuredRow*5 end
    local vitals={psi={visible=false},web={visible=false},gold=3,silver=9,carry={current=174.4,maximum=354,percent=49.3}}
    view.last_state={vitals=vitals,equipment={items={}},inventory={items={{name="Torch",weight=.1}}}}
    view:applyLayout(layout)
    eq(layout.list_font,10); eq(layout.list_row_height,measuredRow); eq(view.inventory_footer.fontSize,12)
    local lines=View.inventoryFooterLines(vitals,view.settings.theme,view.inventory_footer_capacity); eq(#lines,3)
    if measuredRow==15 then
      eq(view.inventory_footer.visible,true)
      eq(view.inventory_footer.height,math.ceil(measuredRow*12/10)*3+3)
      eq(view.inventory_output.y+view.inventory_output.height<=view.inventory_footer.y,true)
      assert(view.inventory_footer.message:find("49.3%",1,true))
    else
      eq(view.inventory_footer.visible,false)
    end
    eq(view.inventory_output.height>=measuredRow,true)
    eq(view.inventory_output.y+view.inventory_output.height<=view.inventory.y+view.inventory.height,true)
  end
end)
test("chat settings controls never overlap or leave the panel on short compact windows",function()
  local view=chatView(); view:showChatSettings()
  for _,size in ipairs({{400,300},{320,260},{800,600},{1024,600}}) do
    local layout=require("layout").compute(size[1],size[2]); view:applyLayout(layout); local panel=view.chat_settings_panel
    eq(panel.x>=0,true); eq(panel.y>=0,true); eq(panel.x+panel.width<=size[1],true); eq(panel.y+panel.height<=size[2],true)
    eq(view.chat_settings_title.y+view.chat_settings_title.height<=view.chat_settings_content.y,true)
    eq(view.chat_settings_content.y+view.chat_settings_content.height<=view.chat_settings_close.y,true)
    eq(view.chat_settings_close.y+view.chat_settings_close.height<=panel.height,true)
    eq(view.chat_settings_visibility.y,0); eq(view.chat_settings_visibility.visible,true)
    eq(view.chat_settings_visibility.width<=view.chat_settings_content.width,true)
    eq(view.chat_settings_visibility.height>=36,true)
    eq(view.chat_settings_text.y>=view.chat_settings_visibility.y+view.chat_settings_visibility.height,true)
    eq(view.chat_settings_sources_caption.y>=view.chat_settings_text.y+view.chat_settings_text.height,true)
    local buttons={}; for _,key in ipairs(view.chat_all_source_order) do local button=view.chat_all_source_buttons[key]; buttons[#buttons+1]=button; eq(button.x>=0,true); eq(button.y>=0,true); eq(button.x+button.width<=view.chat_settings_content.width,true); eq(button.width>0,true); eq(button.height>0,true) end
    for first=1,#buttons do for second=first+1,#buttons do local a,b=buttons[first],buttons[second]; local overlap=a.x<b.x+b.width and b.x<a.x+a.width and a.y<b.y+b.height and b.y<a.y+a.height; eq(overlap,false) end end
    eq(view.chat_settings_clear_visible.y>=view.chat_all_source_buttons.COMBAT.y+view.chat_all_source_buttons.COMBAT.height,true)
    eq(view.chat_settings_clear_saved.y>=view.chat_settings_clear_visible.y+view.chat_settings_clear_visible.height,true)
    eq(view.chat_settings_status.y>=view.chat_settings_clear_saved.y+view.chat_settings_clear_saved.height,true)
    eq(view.chat_settings_content.content_height>=view.chat_settings_status.y+view.chat_settings_status.height,true)
    if size[2]<=300 then eq(view.chat_settings_content.content_height>view.chat_settings_content.height,true) end
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
  for _,name in ipairs({"clock_header","attribute_strip","mapper","chat_settings_clear_saved","chat_settings_visibility","inventory_scroll_footer"}) do
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

local function copiedChatEntries(entries)
  local copied={}
  for index,entry in ipairs(entries) do copied[index]={}; for key,value in pairs(entry) do copied[index][key]=value end end
  return copied
end
local function finiteChatBuffer(output,limit,batch,supportsSizing)
  output.bufferLimit=limit; output.bufferBatch=batch; output.evictedLines=0
  local echo=output.echo
  function output:echo(value,color)
    echo(self,value,color)
    while self.lastLine>self.bufferLimit do
      self.lastLine=self.lastLine-self.bufferBatch; self.evictedLines=self.evictedLines+self.bufferBatch
      local retained={}
      for _,range in ipairs(self.renderedEntries) do
        if range.last>self.bufferBatch then retained[#retained+1]={first=math.max(1,range.first-self.bufferBatch),last=range.last-self.bufferBatch} end
      end
      self.renderedEntries=retained
    end
  end
  if supportsSizing then
    function output:setBufferSize(lines,deletion)
      self.bufferLimit=lines; self.bufferBatch=deletion; self.bufferSizeCalls=(self.bufferSizeCalls or 0)+1
    end
  end
end

test("chat display matching preserves a healthy adopted display and reading position",function()
  local view=chatView(); local entries={}
  for index=1,12 do entries[index]={schema=1,timestamp="2026-10-04T12:00:00Z",character="Synthetic",category="ROOM",speaker="Test",target="",language="Common",message="message-"..index,line=string.rep("wrapped-"..index.." ",40),source="test"} end
  view:renderChat(entries,{"ROOM","QUEST"},"room"); local output=view.chat_output
  output.currentScroll=view.chat_line_ranges[5].first+1
  local line,clears,scrolls,ranges=output.currentScroll,output.clearCalls,#output.scrollCalls,view.chat_line_ranges
  assert(view:prepareForReuse(view.settings)); local buttons=view.chat_buttons
  eq(view:chatDisplayMatches(copiedChatEntries(entries),{"ROOM","QUEST"},"ROOM"),true)
  eq(output.clearCalls,clears); eq(#output.scrollCalls,scrolls); eq(output.currentScroll,line)
  eq(view.chat_line_ranges,ranges); eq(view.chat_buttons,buttons)
  -- A healthy view rendered by the previous runtime may have only its ranges.
  view.chat_last_line=nil
  eq(view:chatDisplayMatches(copiedChatEntries(entries),{"ROOM","QUEST"},"ROOM"),true)
end)

test("chat display matching compares every scalar record field and filter categories",function()
  local view=chatView(); local entries={{schema=1,timestamp="2026-10-04T12:00:00Z",character="Synthetic",category="ROOM",speaker="Test",target="Target",language="Common",message="message",line="line",source="test"}}
  view:renderChat(entries,{"ROOM","QUEST"},"ALL")
  for _,field in ipairs({"schema","timestamp","character","category","speaker","target","language","message","line","source"}) do
    local copied=copiedChatEntries(entries); copied[1][field]=field=="schema" and 2 or "changed"
    eq(view:chatDisplayMatches(copied,{"ROOM","QUEST"},"ALL"),false)
  end
  eq(view:chatDisplayMatches(entries,{"ROOM","QUEST"},"ROOM"),false)
  eq(view:chatDisplayMatches(entries,{"QUEST","ROOM"},"ALL"),false)
  eq(view:chatDisplayMatches(entries,{"ROOM"},"ALL"),false)
  eq(view:chatDisplayMatches({}, {"ROOM","QUEST"},"ALL"),false)
  local copied=copiedChatEntries(entries); copied[1].schema="1"
  eq(view:chatDisplayMatches(copied,{"ROOM","QUEST"},"ALL"),false)
  copied=copiedChatEntries(entries); copied[1].source={}
  eq(view:chatDisplayMatches(copied,{"ROOM","QUEST"},"ALL"),false)
end)

test("chat display matching compares only the requested latest thousand entries",function()
  local view=chatView(); local entries={}
  for index=1,1200 do entries[index]={category="ROOM",line="line-"..index} end
  view:renderChat(entries,{"ROOM"},"ALL"); local copied=copiedChatEntries(entries)
  copied[1].line="outside the display"
  eq(#view.chat_entries,1000); eq(view:chatDisplayMatches(copied,{"ROOM"},"ALL"),true)
  copied[201].line="changed visible record"
  eq(view:chatDisplayMatches(copied,{"ROOM"},"ALL"),false)
end)

test("chat display matching rejects empty truncated extended and unverifiable native buffers",function()
  local view=chatView(); local entries={{category="ROOM",line=string.rep("wrapped ",40)},{category="ROOM",line="last"}}
  view:renderChat(entries,{"ROOM"},"ALL"); local output=view.chat_output; local last=output.lastLine
  for _,nativeLast in ipairs({0,last-1,last+1}) do output.lastLine=nativeLast; eq(view:chatDisplayMatches(entries,{"ROOM"},"ALL"),false) end
  output.lastLine=last; eq(view:chatDisplayMatches(entries,{"ROOM"},"ALL"),true)
  local getLast=output.getLastLineNumber
  function output:getLastLineNumber() error("synthetic unavailable buffer") end
  eq(view:chatDisplayMatches(entries,{"ROOM"},"ALL"),false)
  function output:getLastLineNumber() return nil end
  eq(view:chatDisplayMatches(entries,{"ROOM"},"ALL"),false)
  output.getLastLineNumber=getLast
  view.chat_line_ranges[2].first=view.chat_line_ranges[2].first+1
  eq(view:chatDisplayMatches(entries,{"ROOM"},"ALL"),false)
  view:renderChat(entries,{"ROOM"},"ALL"); view.chat_line_ranges[2]=nil
  eq(view:chatDisplayMatches(entries,{"ROOM"},"ALL"),false)
end)

test("chat display matching accepts a rendered empty filter and rejects an unrendered view",function()
  local view=chatView(); eq(view:chatDisplayMatches({}, {},"ALL"),false)
  view:renderChat({}, {"ROOM"},"PRIVATE")
  eq(view:chatDisplayMatches({}, {"ROOM"},"private"),true)
  view.chat_output.lastLine=1; eq(view:chatDisplayMatches({}, {"ROOM"},"PRIVATE"),false)
end)

test("copied chat anchors retain the same wrapped record and offset after bounded append",function()
  local view=chatView(); local entries={}
  for index=1,1000 do entries[index]={schema=1,timestamp="2026-10-04T12:00:00Z",character="Synthetic",category="ROOM",speaker="Test",target="",language="Common",message="message-"..index,line=string.rep("wrapped-"..index.." ",40),source="test"} end
  view:renderChat(entries,{"ROOM"},"ROOM"); local output=view.chat_output
  output.currentScroll=view.chat_line_ranges[100].first+2
  local copied=copiedChatEntries(entries); copied[1001]={category="ROOM",line="new message"}
  view:renderChat(copied,{"ROOM"},"ROOM")
  eq(#view.chat_entries,1000); eq(view.chat_entries[99].message,"message-100")
  eq(output.currentScroll,view.chat_line_ranges[99].first+2)
  output.currentScroll=output.lastLine; copied[1002]={category="ROOM",line="next message"}
  view:renderChat(copiedChatEntries(copied),{"ROOM"},"ROOM")
  eq(output.scrollCalls[#output.scrollCalls],"bottom")
end)

test("synthetic finite buffers demonstrate wrapped eviction without a sizing API",function()
  local view=chatView(); local output=view.chat_output; finiteChatBuffer(output,10000,1000,false)
  local entries={}; for index=1,1000 do entries[index]={category="ROOM",line=string.rep("wrapped message ",100)} end
  view:renderChat(entries,{"ROOM"},"ALL")
  assert(output.evictedLines>0); assert(#output.renderedEntries<1000)
  eq(view:chatDisplayMatches(entries,{"ROOM"},"ALL"),false)
end)

test("bounded native sizing prevents synthetic wrapped eviction and stays finite",function()
  local view=chatView(); local output=view.chat_output; finiteChatBuffer(output,10000,1000,true)
  local entries={}; for index=1,1000 do entries[index]={category="ROOM",line=string.rep("wrapped message ",100)} end
  view:renderChat(entries,{"ROOM"},"ALL")
  eq(output.evictedLines,0); eq(#output.renderedEntries,1000); eq(#view.chat_entries,1000)
  assert(output.bufferLimit>10000 and output.bufferLimit<=100000)
  assert(output.bufferBatch>0 and output.bufferBatch<output.bufferLimit)
  eq(view:chatDisplayMatches(copiedChatEntries(entries),{"ROOM"},"ALL"),true)
  local calls=output.bufferSizeCalls; view:renderChat(entries,{"ROOM"},"ALL"); eq(output.bufferSizeCalls,calls)
  entries[1].line=string.rep("large ",20000); output.wrap=1
  view:renderChat(entries,{"ROOM"},"ALL"); assert(output.bufferLimit<=100000); assert(output.evictedLines>0)
end)

test("chat rendering tolerates native buffer sizing failures",function()
  for _,failure in ipairs({"throw","reject","error"}) do
    local view=chatView()
    function view.chat_output:setBufferSize()
      if failure=="throw" then error("synthetic sizing failure") elseif failure=="reject" then return false else return nil,"synthetic sizing failure" end
    end
    local entries={{category="ROOM",line="synthetic message"}}
    eq(view:renderChat(entries,{"ROOM"},"ALL"),true)
    eq(view:chatDisplayMatches(entries,{"ROOM"},"ALL"),true)
  end
end)

test("WORLD is a reserved default tab and preserves all existing custom tab order",function()
  eq(table.concat(View.chatFilterOrder({},nil),","),"ALL,ROOM,PRIVATE,ESP,DRAGON,CONTACT,STAFF,COMBAT,WORLD")
  local preferred={"QUEST","STAFF","SECIAN","ALL","COMBAT","ROOM","PRIVATE","CONTACT","ESP","DRAGON","EVENTS"}
  local categories={"EVENTS","QUEST","SECIAN","WORLD","world"}
  local order=View.chatFilterOrder(categories,preferred)
  eq(table.concat(order,","),table.concat(preferred,",")..",WORLD")
  local worldFirst=View.chatFilterOrder(categories,{"world","QUEST","STAFF","WORLD"})
  eq(worldFirst[1],"WORLD"); eq(worldFirst[2],"QUEST"); eq(worldFirst[3],"STAFF")
  local count=0; for _,key in ipairs(worldFirst) do if key=="WORLD" then count=count+1 end end; eq(count,1)
end)

test("WORLD arrivals use the editable green style and preserve the full statement",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800))
  local line=" ** Obatalla Ogoun just arrived in the world."
  view:renderChat({{category="WORLD",speaker="Obatalla Ogoun",message="just arrived in the world.",line=line}},{"WORLD"},"WORLD")
  local style=assert(require("color_styles").resolve({},"world_arrival")); local rgb=assert(require("color_styles").toRGB(style.foreground))
  assert(rgb[2]>rgb[1] and rgb[2]>rgb[3],"arrival default must be green")
  eq(view.chat_output.hechoes[1],style.foreground.."WORLD#r")
  eq(view.chat_output.echoFormats[1].foreground,style.foreground)
  eq(view.chat_output.echoes[1]," "..line.."\n")
  eq(view.chat_active_filter,"WORLD"); eq(view.chat_filter_order[#view.chat_filter_order],"WORLD")
end)

test("WORLD departures including unexpected departures use the editable red style",function()
  local Styles=require("color_styles"); local style=assert(Styles.resolve({},"world_departure")); local rgb=assert(Styles.toRGB(style.foreground))
  assert(rgb[1]>rgb[2] and rgb[1]>rgb[3],"departure default must be red")
  local view=chatView(); local entries={}
  for _,message in ipairs({"has left the world.","has left the world unexpectedly."}) do
    entries[#entries+1]={category="WORLD",speaker="Obatalla Ogoun",message=message,line=" ** Obatalla Ogoun "..message}
  end
  entries[#entries+1]={category="ROOM",message="normal text",line="normal text"}
  view:renderChat(entries,{"WORLD","ROOM"},"ALL")
  for index=1,2 do eq(view.chat_output.hechoes[index],style.foreground.."WORLD#r"); eq(view.chat_output.echoFormats[index].foreground,style.foreground) end
  eq(view.chat_output.echoFormats[3].foreground,nil); eq(view.chat_output.echoFormats[3].background,nil)
  eq(view.chat_output.echoFormats[3].bold,nil); eq(view.chat_output.echoFormats[3].underline,nil)
  eq(view.chat_output.formatResets,2)
end)

test("WORLD chat rendering honors saved foreground highlight bold and underline without interpreting game text",function()
  local view=chatView(); local styles={world_arrival={foreground="#1289AB",background="#233445",bold=true,underline=true},world_departure={foreground="#E84B98",background=false,bold=false,underline=false}}
  assert(view:setColorStyles({styles=styles}))
  local line=" ** #123456<player>& just arrived in the world."
  view:renderChat({{category="WORLD",speaker="#123456<player>&",message="just arrived in the world.",line=line},{category="WORLD",message="has left the world unexpectedly.",line=" ** Test has left the world unexpectedly."}},{"WORLD"},"WORLD")
  eq(view.chat_output.hechoes[1],"#1289ABWORLD#r"); eq(view.chat_output.hechoes[2],"#E84B98WORLD#r")
  eq(view.chat_output.echoes[1]," "..line.."\n")
  local rendered=view.chat_output.echoFormats[1]
  eq(rendered.foreground,"#1289AB"); eq(rendered.background,"#233445"); eq(rendered.bold,true); eq(rendered.underline,true)
  eq(view.chat_output.echoFormats[2].background,nil); eq(view.chat_output.echoFormats[2].bold,false); eq(view.chat_output.echoFormats[2].underline,false)
  eq(view.chat_output.currentFg,nil); eq(view.chat_output.currentBg,nil)
end)

test("WORLD highlighting controls never disable WORLD capture or dedicated display",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view:showColorSettings()
  eq(view.color_option_buttons.world.option_text,"WORLD ARRIVALS / DEPARTURES"); eq(view.color_options.world,true)
  assert(view.color_style_by_id.world_arrival); assert(view.color_style_by_id.world_departure)
  view:setColorOptionsCallback(function(key,wanted)
    eq(key,"world"); view:setColorStyles({world_enabled=wanted}); return wanted
  end)
  eq(view.color_option_buttons.world.click(),false); eq(view.color_options.world,false)
  local entry={category="WORLD",message="just arrived in the world.",line=" ** Test just arrived in the world."}
  for _,config in ipairs({{world_enabled=false},{enabled=false},{styles={world_arrival={enabled=false}}}}) do
    assert(view:setColorStyles(config)); view:renderChat({entry},{"WORLD"},"WORLD")
    eq(#view.chat_entries,1); eq(view.chat_active_filter,"WORLD")
    eq(view.chat_output.hechoes[1],"#9eafc6WORLD#r"); eq(view.chat_output.echoFormats[1].foreground,nil)
    eq(view.chat_output.echoes[1]," "..entry.line.."\n")
  end
  view:setColorStyles({}); eq(view.color_options.world,true)
  for _,options in ipairs({{world=false},{enabled=false,world=true}}) do
    view:setColorOptions(options); view:renderChat({entry},{"WORLD"},"WORLD")
    eq(#view.chat_entries,1); eq(view.chat_output.echoFormats[1].foreground,nil)
  end
  view:setColorOptions({enabled=true,world=true})
  local message="just arrived in the world. and said something unrelated"
  view:renderChat({{category="WORLD",message=message,line=message}},{"WORLD"},"WORLD")
  eq(view.chat_output.hechoes[1],"#9eafc6WORLD#r"); eq(view.chat_output.echoFormats[1].foreground,nil)
end)

test("WORLD arrival and departure styles have editable previews in Color Settings",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1200,800)); view:showColorSettings()
  view.color_settings_styles_tab.click()
  for _,case in ipairs({{"world_arrival","#5AA569","just arrived in the world."},{"world_departure","#CD3E3E","has left the world."}}) do
    local id,color,sample=case[1],case[2],case[3]
    assert(view.color_style_rows[id]); assert(view:selectColorStyle(id))
    eq(view.color_style_fields.foreground.input.text,color); assert(view.color_style_preview.message:find(sample,1,true))
    view.color_style_fields.foreground.input:print("#12AB34"); view:previewColorStyle()
    assert(view.color_style_preview.message:find("#12AB34",1,true)); assert(view.color_style_preview.message:find(sample,1,true))
    view:cancelColorStyle()
  end
end)

test("WORLD remains selectable through narrow overflow and its active tab stays bounded",function()
  local layout=require("layout").compute(280,700); local view=chatView(); view:applyLayout(layout)
  local entries={{category="WORLD",line=" ** Xlade Vespar just arrived in the world."}}; local selected
  view:setChatFilterCallback(function(category) selected=category; view:renderChat(category=="WORLD" and entries or {},{"WORLD"},category); return true end)
  view:renderChat({}, {"WORLD"}, "ALL")
  local found=false; for _,key in ipairs(view.chat_overflow_categories) do if key=="WORLD" then found=true end end; eq(found,true)
  for _=1,#view.chat_filter_order do if selected=="WORLD" then break end; view.chat_overflow_button.click() end
  eq(selected,"WORLD"); eq(view.chat_active_filter,"WORLD"); eq(#view.chat_entries,1)
  local visible=false
  for _,button in ipairs(view.chat_buttons) do
    if button.category=="WORLD" then visible=true end
    eq(button.x>=0 and button.x+button.width<=layout.chat_width,true)
  end
  eq(visible,true)
end)

test("WORLD can be moved first and its saved position survives wide and narrow layouts",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1920,1080)); local saved
  view:setChatOrderCallback(function(order) saved=table.concat(order,","); return true end)
  view:renderChat({}, {"WORLD"}, "WORLD"); assert(view:reorderChatTab("WORLD",1))
  eq(saved,"WORLD,ALL,ROOM,PRIVATE,ESP,DRAGON,CONTACT,STAFF,COMBAT")
  for _,width in ipairs({280,1200,1920}) do
    view:applyLayout(require("layout").compute(width,800))
    eq(view.chat_filter_order[1],"WORLD"); eq(table.concat(view.settings.chat.tab_order,","),saved)
    eq(view.chat_active_filter,"WORLD")
  end
end)

test("WORLD Show in ALL defaults ON and turning it OFF leaves dedicated capture and history intact",function()
  local history=require("chat_history").new(); local view=chatView(); local sources={ROOM=true,COMBAT=false}
  assert(history:append({category="WORLD",speaker="Obatalla Ogoun",message="just arrived in the world.",line=" ** Obatalla Ogoun just arrived in the world."},100))
  assert(history:append({category="WORLD",speaker="Obatalla Ogoun",message="has left the world.",line=" ** Obatalla Ogoun has left the world."},101))
  view:setChatAllSources(sources); view:applyLayout(require("layout").compute(1200,800)); view:showChatSettings()
  eq(view.chat_all_source_order[#view.chat_all_source_order],"WORLD"); eq(view.chat_all_sources.WORLD,true)
  eq(view.chat_all_source_buttons.WORLD.option_text,"WORLD"); assert(view.chat_all_source_buttons.WORLD.message:find("WORLD: ON",1,true))
  view:setOptionsActionCallback(function(action,key,wanted) eq(action,"chat_all_source"); eq(key,"WORLD"); sources[key]=wanted; return wanted end)
  view:renderChat(history:entries("WORLD",sources),history:categories(),"WORLD")
  eq(view.chat_all_source_buttons.WORLD.click(),false); eq(#view.chat_entries,2); eq(#history:entries("WORLD",sources),2)
  assert(view.chat_all_source_buttons.WORLD.message:find("WORLD: OFF",1,true)); eq(sources.COMBAT,false); eq(sources.ROOM,true)
  view:renderChat(history:entries("ALL",sources),history:categories(),"ALL"); eq(#view.chat_entries,0)
  assert(history:append({category="WORLD",speaker="Xlade Vespar",message="just arrived in the world.",line=" ** Xlade Vespar just arrived in the world."},102))
  view:renderChat(history:entries("ALL",sources),history:categories(),"ALL"); eq(#view.chat_entries,0)
  view:renderChat(history:entries("WORLD",sources),history:categories(),"WORLD"); eq(#view.chat_entries,3)
  eq(view.chat_all_source_buttons.WORLD.click(),true)
  view:renderChat(history:entries("ALL",sources),history:categories(),"ALL"); eq(#view.chat_entries,3); eq(#history.items,3)
end)

test("WORLD sound controls keep all 55 legacy custom tabs accessible without dropping preferences",function()
  local Sounds=require("chat_sounds"); local config=Sounds.defaults(); config.tabs.WORLD=nil
  local preferred={}
  for _,key in ipairs(Sounds.tabOrder) do if key~="WORLD" then preferred[#preferred+1]=key end end
  for index=1,55 do
    local key="CUSTOM "..index; preferred[#preferred+1]=key
    config.tabs[key]={enabled=index%2==0,sound="contact"}
  end
  eq(#preferred,64)
  local view=chatView(nil,nil,nil,nil,config); view.settings.chat.tab_order=preferred
  view:applyLayout(require("layout").compute(320,700)); view:renderChat({},preferred,"WORLD"); view:showChatSettings()
  eq(#view.chat_sound_order,Sounds.MAX_TABS); eq(view.chat_filter_order[#view.chat_filter_order],"WORLD")
  for index,key in ipairs(preferred) do eq(view.chat_filter_order[index],key) end
  for index=1,55 do
    local key="CUSTOM "..index; local row=view.chat_sound_rows[key]; assert(row)
    eq(view:chatSoundSetting(key).enabled,index%2==0); eq(view:chatSoundSetting(key).sound,"contact")
    eq(row.preview.visible,true); eq(row.preview.y+row.preview.height<=view.chat_settings_content.content_height,true)
  end
  eq(view:chatSoundSetting("WORLD").enabled,false); eq(view:chatSoundSetting("WORLD").sound,"world")
  assert(View.validateReusable(view,view.settings))
end)

test("WORLD sound settings are accessible while OFF and saved preferences survive view reuse",function()
  local config={volume=35,tabs={STAFF={enabled=false,sound="private"},QUEST={enabled=true,sound="dragon"}}}
  local view=chatView(nil,nil,nil,nil,config); view.settings.chat.tab_order={"QUEST","STAFF","ALL"}
  view:applyLayout(require("layout").compute(1200,800)); view:showChatSettings()
  local row=view.chat_sound_rows.WORLD; eq(view:chatSoundSetting("WORLD").enabled,false); eq(view:chatSoundSetting("WORLD").sound,"world")
  eq(row.preview.visible,true); assert(row.choice.message:find("World Notice",1,true)); assert(row.enabled.message:find("OFF",1,true))
  local calls={}; view:setOptionsActionCallback(function(action,tab,value) calls[#calls+1]={action,tab,value}; return action=="chat_sound_preview" and true or value end)
  eq(row.preview.click(),true); eq(calls[1][1],"chat_sound_preview"); eq(calls[1][2],"WORLD"); eq(calls[1][3],"world")
  eq(view:chatSoundSetting("WORLD").enabled,false); eq(row.enabled.click(),true); eq(row.next.click(),"all")
  assert(view:prepareForReuse(view.settings)); view:showChatSettings()
  eq(view:chatSoundSetting("WORLD").enabled,true); eq(view:chatSoundSetting("WORLD").sound,"all"); eq(view.chat_sound_rows.WORLD,row)
  eq(view:chatSoundSetting("STAFF").enabled,false); eq(view:chatSoundSetting("STAFF").sound,"private")
  eq(view:chatSoundSetting("QUEST").enabled,true); eq(view:chatSoundSetting("QUEST").sound,"dragon"); eq(view.chat_sounds.volume,35)
  eq(table.concat(view.settings.chat.tab_order,","),"QUEST,STAFF,ALL")
end)

test("reusable sound views require the reserved WORLD row",function()
  local view=chatView(); assert(View.validateReusable(view,view.settings))
  view.chat_sound_rows.WORLD.preview=nil
  local ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("sound control",1,true))
  view=chatView(); table.remove(view.chat_sound_order,#view.chat_sound_order)
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("sound tabs",1,true))
end)

test("chat tabs stay inside narrow panels and expose deterministic overflow",function()
  local layout=require("layout").compute(280,700); local view=chatView(); view:applyLayout(layout); local selected
  view:setChatFilterCallback(function(category) selected=category end)
  view:renderChat({}, {"QUEST","EVENTS","QUEST<script>","LINE\nBREAK"}, "ALL")
  eq(table.concat(view.chat_filter_order,","),"ALL,ROOM,PRIVATE,ESP,DRAGON,CONTACT,STAFF,COMBAT,WORLD,QUEST,EVENTS")
  eq(#view.chat_overflow_categories>0,true)
  for _,button in ipairs(view.chat_buttons) do
    eq(button.x+button.width<=layout.chat_width,true); eq(tostring(button.message):find("<script>",1,true),nil)
  end
  local first=view.chat_overflow_categories[1]; view.chat_overflow_button.click(); eq(selected,first)
end)

test("chat tab order sanitizes saved preferences and appends missing categories",function()
  local order=View.chatFilterOrder({"QUEST","EVENTS"},{" events ","ROOM","OWN","<BAD>","EVENTS","ALL"})
  eq(table.concat(order,","),"EVENTS,ROOM,ALL,PRIVATE,ESP,DRAGON,CONTACT,STAFF,COMBAT,WORLD,QUEST")
end)

test("chat tabs drag left and right, persist once, and keep click filtering",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1920,1080)); local selected,saved,calls
  view:setChatFilterCallback(function(category) selected=category; return true end)
  view:setChatOrderCallback(function(order) saved=table.concat(order,","); calls=(calls or 0)+1; return true end)
  view:renderChat({}, {}, "ALL")
  local room=view.chat_buttons[2]; room.click({button="LeftButton",globalX=100}); room.release({button="LeftButton",globalX=20})
  eq(saved,"ROOM,ALL,PRIVATE,ESP,DRAGON,CONTACT,STAFF,COMBAT,WORLD"); eq(calls,1); eq(view.chat_active_filter,"ALL")
  local all=view.chat_buttons[2]; all.click({button="LeftButton",globalX=100}); all.release({button="LeftButton",globalX=101})
  eq(selected,"ALL"); eq(calls,1)
end)

test("failed chat tab persistence leaves the visible order unchanged",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1920,1080)); view:setChatOrderCallback(function() return nil,"disk full" end); view:renderChat({}, {}, "ALL")
  local before=table.concat(view.chat_filter_order,","); local ok,err=view:reorderChatTab("ROOM",1)
  eq(ok,nil); eq(err,"disk full"); eq(table.concat(view.chat_filter_order,","),before)
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

test("latent psion warning remains visible and bounded through responsive layouts",function()
  local Layout=require("layout"); local view=chatView()
  view:applyLayout(Layout.compute(1920,1080)); assert(view:showLatentPsionAlert("Automatic rolling has stopped. Do not reroll."))
  eq(view.latent_alert_visible,true); eq(view.latent_alert_panel.visible,true); eq(view.latent_alert_overlay.visible,true)
  assert(view.latent_alert_title.message:find("LATENT PSIONIC GIFT",1,true)); assert(view.latent_alert_text.message:find("Do not reroll",1,true))
  view:applyLayout(Layout.compute(640,480))
  eq(view.latent_alert_panel.visible,true); eq(view.latent_alert_panel.x>=0,true); eq(view.latent_alert_panel.y>=0,true)
  eq(view.latent_alert_panel.x+view.latent_alert_panel.width<=640,true); eq(view.latent_alert_panel.y+view.latent_alert_panel.height<=480,true)
  view.latent_alert_close.click(); eq(view.latent_alert_visible,false); eq(view.latent_alert_panel.visible,false); eq(view.latent_alert_overlay.visible,false)
end)

test("main skills display option starts on toggles independently and preserves sidebar formatting",function()
  local view=chatView(); local button=view.option_action_buttons.main_skills
  eq(view.main_skills_enabled,true); eq(button.option_text,"MAIN SKILLS: ON")
  eq(button.parent,view.options_scroll); eq(view:setMainSkillsEnabled(false),false); eq(button.option_text,"MAIN SKILLS: OFF")
  local action; view:setOptionsActionCallback(function(value) action=value; return false end)
  button.click(); eq(action,"main_skills")
  eq(View.skillDisplayName("Sharp Weapons"),"Sharp Weapons")
  eq(view:setMainSkillsEnabled(true),true); eq(button.option_text,"MAIN SKILLS: ON")
end)

local function skillSettingsFixture(mainEnabled,filterEnabled)
  local SkillSort=require("skill_sort")
  return {main_skills=mainEnabled~=false,skill_filter=filterEnabled~=false,main_skill_sort=SkillSort.normalize(),sidebar_skill_sort=SkillSort.normalize()}
end
local function skillSettingsView(display)
  local view=chatView(nil,nil,nil,nil,nil,display)
  view:applyLayout(require("layout").compute(1200,800))
  return view
end
test("Skills Settings defaults missing filters to ON and preserves saved OFF snapshots",function()
  eq(skillSettingsView().settings.display.skill_filter,true)
  local legacy=skillSettingsFixture(); legacy.skill_filter=nil
  for _,snapshot in ipairs({legacy,skillSettingsFixture(false,true),skillSettingsFixture(true,false)}) do
    local view=skillSettingsView(snapshot); local expected=snapshot.skill_filter~=false
    eq(view.settings.display.skill_filter,expected)
    assert(view:showSkillSettings(snapshot))
    eq(view.skill_settings_draft.skill_filter,expected); eq(view.skill_settings_dirty,false)
    eq(view.skill_settings_filter.parent,view.skill_settings_content); eq(view.skill_settings_filter.visible,true)
    assert(view.skill_settings_filter.message:find("SKILL FILTERS: "..(expected and "ON" or "OFF"),1,true))
    local values=assert(view:skillSettingsValues()); eq(values.skill_filter,expected)
    values.skill_filter=not expected; values.main_skill_sort.primary="name"
    eq(view.skill_settings_draft.skill_filter,expected); eq(view.skill_settings_draft.main_skill_sort.primary,"level")
    view:hideSkillSettings(); eq(view.skill_settings_filter.visible,false)
  end
end)
test("Skills Settings filter clicks edit a shared draft independently of main formatting",function()
  local active=skillSettingsFixture(); local view=skillSettingsView(active); local saves=0
  view:setOptionsActionCallback(function(action)
    if action=="skill_settings" then return active end
    saves=saves+1; return active
  end)
  assert(view:showSkillSettings())
  assert(view.skill_settings_filter.click()); eq(view.skill_settings_draft.skill_filter,false)
  eq(view.skill_settings_draft.main_skills,true); eq(view.settings.display.skill_filter,true); eq(active.skill_filter,true)
  eq(view.skill_settings_dirty,true); eq(saves,0)
  assert(view.skill_settings_filter.message:find("SKILL FILTERS: OFF",1,true))
  view.skill_settings_tabs.main.click(); eq(view.skill_settings_draft.skill_filter,false)
  view.skill_settings_format.click(); eq(view.skill_settings_draft.main_skills,false); eq(view.skill_settings_draft.skill_filter,false)
  assert(view.skill_settings_filter.click()); eq(view.skill_settings_draft.skill_filter,true)
  assert(view.skill_settings_filter.message:find("SKILL FILTERS: ON",1,true))
  view.skill_settings_tabs.sidebar.click(); eq(view.skill_settings_draft.skill_filter,true)
  eq(view.settings.display.main_skills,true); eq(saves,0)
end)
test("Skills Settings routes through Options and retains the main skills action",function()
  local view=skillSettingsView(); local calls={}
  view:setOptionsActionCallback(function(action)
    calls[#calls+1]=action
    if action=="skill_settings" then return skillSettingsFixture(false) end
    if action=="main_skills" then return true end
  end)
  view.color_toggle.click()
  local button=view.option_action_buttons.skill_settings
  eq(button.option_text,"SKILL SETTINGS…"); eq(button.visible,true); eq(button.parent,view.options_scroll)
  assert(button.click()); eq(calls[1],"skill_settings"); eq(view.color_menu_visible,false)
  eq(view.skill_settings_visible,true); eq(view.skill_settings_draft.main_skills,false)
  eq(view.skill_settings_draft.skill_filter,true); eq(view.skill_settings_filter.visible,true)
  view:hideSkillSettings(); assert(view.option_action_buttons.main_skills.click()); eq(calls[2],"main_skills")
end)
test("Skills Settings edits both independent tabs as a draft and applies the saved snapshot",function()
  local view=skillSettingsView(); local snapshot=skillSettingsFixture(false); local payload; local saves=0
  view:setOptionsActionCallback(function(action,draft)
    if action=="skill_settings" then return snapshot end
    eq(action,"skill_settings_save"); saves=saves+1; payload=draft
    draft.sidebar_skill_sort.secondary_direction="desc"; return draft
  end)
  assert(view:showSkillSettings())
  assert(view.skill_settings_filter.click()); eq(view.skill_settings_draft.skill_filter,false)
  view.skill_settings_primary_buttons.name.click(); view.skill_settings_direction_buttons.asc.click()
  view.skill_settings_secondary_buttons.number.click(); view.skill_settings_secondary_direction_buttons.desc.click()
  view.skill_settings_tabs.main.click(); view.skill_settings_primary_buttons.uses.click()
  view.skill_settings_direction_buttons.asc.click(); view.skill_settings_secondary_buttons.none.click()
  eq(view.settings.display.sidebar_skill_sort.primary,"level"); eq(snapshot.sidebar_skill_sort.primary,"level")
  eq(view.skill_settings_draft.main_skills,false); eq(view.settings.display.skill_filter,true); eq(snapshot.skill_filter,true); eq(saves,0)
  local saved=assert(view.skill_settings_save.click())
  eq(saves,1); eq(saved,payload); eq(payload.main_skills,false); eq(payload.skill_filter,false)
  eq(view.settings.display.skill_filter,false); eq(snapshot.skill_filter,true); eq(view.skill_settings_filter.visible,false)
  eq(view.settings.display.sidebar_skill_sort.primary,"name")
  eq(view.settings.display.sidebar_skill_sort.direction,"asc"); eq(view.settings.display.sidebar_skill_sort.secondary,"number")
  eq(view.settings.display.main_skill_sort.primary,"uses"); eq(view.settings.display.main_skill_sort.secondary,"none")
  eq(view.main_skills_enabled,false); eq(view.skill_settings_visible,false); eq(view.skill_settings_draft,nil)
end)
test("failed Skills Settings saves keep the edited draft visible and active settings unchanged",function()
  local view=skillSettingsView(); local active=skillSettingsFixture(false); view:setSkillSortPreferences(active)
  view:setOptionsActionCallback(function(action,draft)
    if action=="skill_settings" then return active end
    -- A reentrant runtime refresh or callback mutation must not apply a failed save.
    view:setSkillSortPreferences(skillSettingsFixture(true,false))
    draft.sidebar_skill_sort.primary="number"
    draft.skill_filter=true
    return nil,"disk <full>"
  end)
  view:showSkillSettings(); view.skill_settings_primary_buttons.name.click(); view.skill_settings_format.click()
  view.skill_settings_filter.click()
  local draft=view.skill_settings_draft
  local ok,err=view.skill_settings_save.click(); eq(ok,nil); eq(err,"disk <full>")
  eq(view.skill_settings_draft,draft); eq(draft.sidebar_skill_sort.primary,"name"); eq(draft.main_skills,true)
  eq(draft.skill_filter,false); eq(view.settings.display.skill_filter,true)
  assert(view.skill_settings_filter.message:find("SKILL FILTERS: OFF",1,true))
  eq(view.settings.display.main_skills,false); eq(view.settings.display.sidebar_skill_sort.primary,"level")
  eq(view.skill_settings_visible,true); eq(view.skill_settings_panel.visible,true)
  assert(view.skill_settings_status.message:find("disk &lt;full&gt;",1,true))
  view:setOptionsActionCallback(function() error("save <crashed>") end)
  ok,err=view.skill_settings_save.click(); eq(ok,nil); assert(err:find("save <crashed>",1,true))
  eq(view.skill_settings_draft,draft); eq(view.skill_settings_visible,true)
  eq(draft.skill_filter,false); eq(view.settings.display.skill_filter,true)
end)
test("Skills Settings rejects missing or nonboolean saved filters without applying queued preferences",function()
  for _,invalid in ipairs({{}, {skill_filter="false"}, {skill_filter=0}}) do
    local active=skillSettingsFixture(); local view=skillSettingsView(active)
    view:setOptionsActionCallback(function(action,payload)
      if action=="skill_settings" then return active end
      eq(action,"skill_settings_save"); eq(payload.skill_filter,false)
      view:setSkillSortPreferences(skillSettingsFixture(false,false))
      payload.skill_filter=invalid.skill_filter; return payload
    end)
    assert(view:showSkillSettings()); assert(view.skill_settings_filter.click())
    local draft=view.skill_settings_draft
    local ok,err=view.skill_settings_save.click(); eq(ok,nil); eq(type(err),"string"); assert(#err>0)
    eq(view.settings.display.skill_filter,true); eq(view.settings.display.main_skills,true)
    eq(view.skill_settings_visible,true); eq(view.skill_settings_draft,draft); eq(draft.skill_filter,false)
    eq(view.skill_settings_saving,false); eq(view.skill_settings_pending_snapshot,nil)
  end
end)
test("Skills Settings applies the returned filter snapshot after a successful save",function()
  local view=skillSettingsView(); local saves=0
  view:setOptionsActionCallback(function(action,payload)
    if action=="skill_settings" then return skillSettingsFixture() end
    eq(action,"skill_settings_save"); eq(payload.skill_filter,false); saves=saves+1
    return skillSettingsFixture(false,true)
  end)
  assert(view:showSkillSettings()); view.skill_settings_filter.click()
  local saved=assert(view.skill_settings_save.click()); eq(saved.skill_filter,true); eq(saves,1)
  eq(view.settings.display.skill_filter,true); eq(view.settings.display.main_skills,false)
  eq(view.skill_settings_visible,false); eq(view.skill_settings_draft,nil)
end)
test("Skills Settings cancel and reset make no writes and reopening discards unsaved edits",function()
  local view=skillSettingsView(); local active=skillSettingsFixture(false,false); active.sidebar_skill_sort.primary="name"
  view:setSkillSortPreferences(active); local saves=0
  view:setOptionsActionCallback(function(action) if action=="skill_settings" then return active end; saves=saves+1; return nil end)
  view:showSkillSettings(); view.skill_settings_reset.click()
  eq(view.skill_settings_draft.skill_filter,true); eq(view.settings.display.skill_filter,false)
  assert(view.skill_settings_filter.message:find("SKILL FILTERS: ON",1,true))
  eq(view.skill_settings_draft.main_skills,true); eq(view.skill_settings_draft.sidebar_skill_sort.primary,"level")
  eq(view.skill_settings_draft.main_skill_sort.direction,"desc"); eq(view.skill_settings_draft.sidebar_skill_sort.secondary_direction,"asc")
  eq(view.settings.display.main_skills,false); eq(view.settings.display.sidebar_skill_sort.primary,"name")
  view.skill_settings_cancel.click(); eq(saves,0); eq(view.skill_settings_draft,nil)
  for _,widget in ipairs(view:skillSettingsWidgets()) do eq(widget.visible,false) end
  view:showSkillSettings(); eq(view.skill_settings_draft.sidebar_skill_sort.primary,"name"); eq(view.skill_settings_draft.main_skills,false)
  eq(view.skill_settings_draft.skill_filter,false)
  view.skill_settings_filter.click(); eq(view.skill_settings_draft.skill_filter,true)
  view.skill_settings_overlay.click(); eq(saves,0); eq(view.skill_settings_visible,false)
  eq(view.settings.display.skill_filter,false)
  view:showSkillSettings(); eq(view.skill_settings_draft.skill_filter,false)
  view.skill_settings_filter.click(); view.skill_settings_cancel.click(); eq(saves,0)
  eq(view.settings.display.skill_filter,false); eq(view.skill_settings_draft,nil)
  view:showSkillSettings(); eq(view.skill_settings_draft.skill_filter,false)
end)
test("Skills Settings Reset restores filters only after Save",function()
  local active=skillSettingsFixture(false,false); local view=skillSettingsView(); local saves=0
  view:setSkillSortPreferences(active)
  view:setOptionsActionCallback(function(action,payload)
    if action=="skill_settings" then return active end
    eq(action,"skill_settings_save"); eq(payload.skill_filter,true); saves=saves+1; return payload
  end)
  assert(view:showSkillSettings()); view.skill_settings_reset.click()
  eq(view.skill_settings_draft.skill_filter,true); eq(view.settings.display.skill_filter,false); eq(saves,0)
  assert(view.skill_settings_save.click()); eq(saves,1); eq(view.settings.display.skill_filter,true)
  eq(active.skill_filter,false); eq(view.skill_settings_visible,false)
end)
test("preference and main format refreshes preserve dirty Skills Settings drafts",function()
  local view=skillSettingsView(); view:showSkillSettings(skillSettingsFixture())
  view.skill_settings_primary_buttons.number.click()
  view.skill_settings_filter.click()
  local draft=view.skill_settings_draft
  local active=skillSettingsFixture(false); active.main_skill_sort.primary="name"
  view:setSkillSortPreferences(active); view:setMainSkillsEnabled(true); view:setDisplayTextSize("large")
  eq(view.skill_settings_draft,draft); eq(draft.sidebar_skill_sort.primary,"number")
  eq(draft.main_skills,true); eq(draft.main_skill_sort.primary,"level")
  eq(draft.skill_filter,false); eq(view.settings.display.skill_filter,true)
  eq(view.settings.display.main_skill_sort.primary,"name")
  view:hideSkillSettings(); view:showSkillSettings(active)
  active.main_skill_sort.primary="uses"; active.skill_filter=false; view:setSkillSortPreferences(active)
  eq(view.skill_settings_draft.main_skill_sort.primary,"uses"); eq(view.skill_settings_dirty,false)
  eq(view.skill_settings_draft.skill_filter,false); eq(view.settings.display.skill_filter,false)
  view:setMainSkillsEnabled(true); view:setDisplayTextSize("small")
  eq(view.settings.display.skill_filter,false); eq(view.skill_settings_draft.skill_filter,false)
  assert(view.skill_settings_filter.message:find("SKILL FILTERS: OFF",1,true))
end)
test("Skills Settings keys directions and level then uses preset are independently selectable",function()
  local view=skillSettingsView(); view:showSkillSettings(skillSettingsFixture(false))
  for _,target in ipairs({"main","sidebar"}) do
    view.skill_settings_tabs[target].click()
    for _,key in ipairs({"level","uses","name","number","ready","category"}) do
      assert(view.skill_settings_primary_buttons[key].click()); eq(view.skill_settings_draft[target.."_skill_sort"].primary,key)
      for _,direction in ipairs({"asc","desc"}) do
        assert(view.skill_settings_direction_buttons[direction].click())
        local config=view.skill_settings_draft[target.."_skill_sort"]; eq(config.direction,direction)
        for _,secondary in ipairs({"level","uses","name","number","ready","category","none"}) do
          view.skill_settings_secondary_buttons[secondary].click(); eq(config.secondary,secondary)
          for _,secondDirection in ipairs({"asc","desc"}) do
            view.skill_settings_secondary_direction_buttons[secondDirection].click()
            eq(config.secondary_direction,secondDirection); eq(config.direction,direction)
          end
        end
      end
    end
    assert(view.skill_settings_preset.click())
    local config=view.skill_settings_draft[target.."_skill_sort"]
    eq(config.primary,"level"); eq(config.direction,"desc"); eq(config.secondary,"uses"); eq(config.secondary_direction,"asc")
    eq(view.skill_settings_draft.main_skills,false)
  end
  local ok,err=view:changeSkillSort("primary","none"); eq(ok,nil); eq(err,"Invalid skill sort choice.")
  ok=view:changeSkillSort("bogus","name"); eq(ok,nil)
end)
local function skillRows(view)
  return (view.skills_content.message:gsub("&nbsp;"," "):gsub("<br>","\n"):gsub("<[^>]+>",""))
end
test("saved sidebar sorting immediately rerenders every source skill without mutating State",function()
  local view=skillSettingsView()
  local items={{name="Biting",level=2,remain=0},{name="Brawling",level=7,remain=10},{name="Hiding",level=7,remain=1},{name="Unknown Skill",level=1,remain=5}}
  local state={skills={items=items}}; view.last_state=state; view:renderSkills(state)
  local rows=skillRows(view); assert(rows:find("Hiding",1,true)<rows:find("Brawling",1,true))
  local snapshot=skillSettingsFixture(); snapshot.sidebar_skill_sort={primary="name",direction="asc",secondary="none",secondary_direction="desc"}
  view.settings.display.auto_main_wrap=false; view.settings.display.text_size="large"
  local width,height=view.skills_content.width,view.skills_content.height; view.skills_output.currentScroll=9
  assert(view:setSkillSortPreferences(snapshot)); rows=skillRows(view)
  assert(rows:find("Biting",1,true)<rows:find("Brawling",1,true)); assert(rows:find("Brawling",1,true)<rows:find("Hiding",1,true))
  eq(view.last_state,state); eq(state.skills.items,items); eq(items[1].name,"Biting"); eq(items[2].name,"Brawling"); eq(items[3].name,"Hiding")
  eq(items[1].level,2); eq(items[1].remain,0); assert(rows:find("Unknown Skill",1,true))
  eq(view.skills_content.width,width); eq(view.skills_content.height,height); eq(view.skills_output.currentScroll,9)
  eq(view.settings.display.auto_main_wrap,false); eq(view.settings.display.text_size,"large")
  snapshot.sidebar_skill_sort.primary="uses"; eq(view.settings.display.sidebar_skill_sort.primary,"name")
end)
test("sidebar sort supports ready category number and independent secondary directions",function()
  local view=skillSettingsView()
  local state={skills={items={{name="Hiding",level=7,remain=1},{name="Brawling",level=7,remain=10},{name="Biting",level=2,remain=0}}}}
  view.last_state=state
  for _,case in ipairs({
    {"ready","asc","none","desc","Biting"},{"ready","desc","none","asc","Brawling"},
    {"category","asc","name","desc","Brawling"},{"category","desc","name","asc","Hiding"},
    {"number","asc","none","asc","Brawling"},{"number","desc","none","asc","Biting"},
    {"level","desc","uses","asc","Hiding"},{"level","desc","uses","desc","Brawling"},
  }) do
    local snapshot=skillSettingsFixture(); snapshot.sidebar_skill_sort={primary=case[1],direction=case[2],secondary=case[3],secondary_direction=case[4]}
    view:setSkillSortPreferences(snapshot)
    eq(skillRows(view):match("^%s*(.-)%s+%d"),case[5])
  end
end)
test("Skills Settings remains bounded readable and scrollable on narrow and short windows",function()
  local view=skillSettingsView(); view:showSkillSettings(skillSettingsFixture())
  local panel=view.skill_settings_panel; local content=view.skill_settings_content
  for _,size in ipairs({{1200,900},{640,480},{400,300},{320,260},{240,120},{160,100},{40,40}}) do
    view:applyLayout(require("layout").compute(size[1],size[2]))
    eq(view.skill_settings_panel,panel); eq(view.skill_settings_content,content)
    eq(view.skill_settings_filter.visible,true); eq(view.skill_settings_filter.container,content)
    eq(panel.x,0); eq(panel.y,math.min(size[2]-1,view.options_anchor.y+view.options_anchor.height+4))
    eq(panel.x>=0,true); eq(panel.y>=0,true); eq(panel.x+panel.width<=size[1],true); eq(panel.y+panel.height<=size[2],true)
    eq(content.width>0,true); eq(content.height>0,true)
    eq(content.x+content.width<=panel.width,true); eq(content.y+content.height<=panel.height,true)
    eq(view.skill_settings_font>=13,true); eq(content.content_height>=view.skill_settings_save.y+view.skill_settings_save.height,true)
    eq(view.skill_settings_filter.y+view.skill_settings_filter.height<=content.content_height,true)
    eq(view.skill_settings_filter.y+view.skill_settings_filter.height<=view.skill_settings_save.y,true)
    local buttons={}
    for _,widget in ipairs(view:skillSettingsWidgets()) do
      if widget.container==content then
        eq(widget.x>=0,true); eq(widget.y>=0,true); eq(widget.width>0,true); eq(widget.height>0,true)
        eq(widget.x+widget.width<=content.content_width,true)
        if widget.click then buttons[#buttons+1]=widget end
      end
    end
    for i=1,#buttons do for j=i+1,#buttons do
      local a,b=buttons[i],buttons[j]
      eq(a.x<b.x+b.width and b.x<a.x+a.width and a.y<b.y+b.height and b.y<a.y+a.height,false)
    end end
    if size[2]<=480 then eq(content.content_height>content.height,true) end
  end
end)
test("opening other settings hides Skills Settings and opening it hides other popups",function()
  local view=skillSettingsView()
  for _,open in ipairs({
    function() view:showChatSettings() end,function() view:showKeybindingSettings({}) end,
    function() view:showColorSettings() end,function() view:showMapSettings({}) end,
    function() view:showRollerSettings({}) end,function() view:showMapLibrary() end,
    function() view:showHelp() end,function() view:showSupport() end,function() view:showFeedback() end,
  }) do
    view:showSkillSettings(skillSettingsFixture()); open()
    eq(view.skill_settings_visible,false); eq(view.skill_settings_draft,nil)
    for _,widget in ipairs(view:skillSettingsWidgets()) do eq(widget.visible,false) end
    view:showSkillSettings(skillSettingsFixture())
    for _,key in ipairs({"chat_settings","keybindings","color_settings","map_settings","roller_settings","map_library","help","support","feedback"}) do
      eq(view[key.."_visible"],false)
      local panel=key=="roller_settings" and view.roller_panel or view[key.."_panel"]
      eq(panel.visible,false)
    end
  end
end)
test("Skills Settings explains all grouped filters without covering tabs at small sizes",function()
  local view=skillSettingsView(); view:showSkillSettings(skillSettingsFixture())
  for _,size in ipairs({{1200,900},{420,500},{320,260},{160,100}}) do
    view:applyLayout(require("layout").compute(size[1],size[2]))
    local hint=view.skill_settings_text
    for _,command in ipairs({"skill combat","skill utility","skill train"}) do
      assert(hint.message:find(command,1,true),"missing settings hint: "..command)
    end
    assert(hint.message:find("all combat skills, including 0 uses",1,true))
    assert(hint.message:find("all utility skills, including 0 uses",1,true))
    assert(hint.message:find("Zero-use rows stay green in every group",1,true))
    assert(hint.message:find("skill Rath",1,true),"missing native staff command example")
    assert(hint.message:find("OFF",1,true),"missing filter OFF explanation")
    assert(view.skill_settings_filter.message:find("SKILL FILTERS: ON",1,true))
    eq(view.skill_settings_filter.y,0); eq(view.skill_settings_filter.width,view.skill_settings_content.content_width)
    assert(hint.y>=view.skill_settings_filter.y+view.skill_settings_filter.height,"filter toggle overlaps skill hint")
    assert(view.skill_settings_tabs.main.y>=hint.y+hint.height,"skill hint overlaps tabs")
    assert(view.skill_settings_content.content_height>=view.skill_settings_save.y+view.skill_settings_save.height)
  end
end)

test("Skills Settings reuse validates new controls hides drafts and drops retired callbacks",function()
  local view=skillSettingsView()
  eq(View.validateReusable(view,view.settings),true)
  local primary=view.skill_settings_primary_buttons.ready; view.skill_settings_primary_buttons.ready=nil
  local ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("skill settings control",1,true))
  view.skill_settings_primary_buttons.ready=primary
  local save=view.skill_settings_save; view.skill_settings_save=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("skill_settings_save",1,true))
  view.skill_settings_save=save
  local filter=view.skill_settings_filter; view.skill_settings_filter=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("skill_settings_filter",1,true))
  view.skill_settings_filter=filter
  local parent=filter.container; filter.container=view.root
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("skill settings parent",1,true))
  filter.container=parent
  local bind=filter.setClickCallback; filter.setClickCallback=nil
  ok,err=View.validateReusable(view,view.settings); eq(ok,nil); assert(err:find("skill settings button",1,true))
  filter.setClickCallback=bind; eq(View.validateReusable(view,view.settings),true)
  view:setOptionsActionCallback(function() error("retired callback") end)
  view:showSkillSettings(skillSettingsFixture()); view.skill_settings_format.click()
  view.skill_settings_filter.click()
  local oldClick=view.skill_settings_save.click; local root=view.root
  local snapshot=skillSettingsFixture(false,false)
  local settings={view_contract=VIEW_CONTRACT,view_settings_contract=SETTINGS_CONTRACT,theme=view.settings.theme,chat=view.settings.chat,display=snapshot}
  assert(view:prepareForReuse(settings)); eq(view.root,root); eq(view.options_action_callback,nil)
  eq(view.skill_settings_visible,false); eq(view.skill_settings_draft,nil); eq(view.main_skills_enabled,false)
  eq(view.settings.display.skill_filter,false); eq(view.skill_settings_filter,filter); eq(filter.visible,false)
  eq(oldClick(),nil)
  eq(filter.click(),nil)
  for _,widget in ipairs(view:skillSettingsWidgets()) do eq(widget.visible,false) end
  eq(View.validateReusable(view,settings),true)
  assert(view:showSkillSettings(snapshot)); eq(view.skill_settings_draft.skill_filter,false)
  assert(filter.message:find("SKILL FILTERS: OFF",1,true)); assert(filter.click())
  eq(view.skill_settings_draft.skill_filter,true); eq(view.settings.display.skill_filter,false)
  view.skill_settings_cancel.click(); eq(view.settings.display.skill_filter,false)
  view:delete(); eq(view.root,nil); eq(view.skill_settings_draft,nil)
  eq(oldClick(),nil); eq(view.skill_settings_format.click(),nil); eq(view:showSkillSettings(snapshot),nil)
  eq(filter.click(),nil)
end)
