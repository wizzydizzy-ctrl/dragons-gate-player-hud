local Adapter=require("mudlet_adapter")
local Styles=require("color_styles")
local Preferences=require("color_preferences")
local function console(lines,settings)
  local f={lines=lines,cursor=9,column=2,colors={},selections={},replaced=0,bold={},backgrounds={}}
  local api={
    getLineNumber=function() return f.cursor end,getColumnNumber=function() return f.column end,
    getLines=function(first) return {f.lines[first]} end,
    moveCursor=function(column,row) f.column=column; f.cursor=row; return true end,
    selectSection=function(start,length)
      assert(start==0); assert(length<=#f.lines[f.cursor],"selection extends beyond native row")
      f.selections[#f.selections+1]={row=f.cursor,length=length}; return true
    end,
    replace=function(text) f.lines[f.cursor]=text; f.replaced=f.replaced+1 end,
    deleteLine=function()
      local last=f.cursor
      for row in pairs(f.lines) do if type(row)=="number" then last=math.max(last,row) end end
      for row=f.cursor,last do f.lines[row]=f.lines[row+1] end
      f.deleted=(f.deleted or 0)+1
    end,
    setFgColor=function(r,g,b) f.colors[f.cursor]={r,g,b} end,
    setBgColor=function(r,g,b) f.backgrounds[f.cursor]={r,g,b} end,
    setBold=function(value) f.bold[f.cursor]=value end,
    deselect=function() end,
  }
  local adapter=Adapter.new(); adapter.settings={colorization=settings or {}}
  return f,api,adapter
end

-- Synthetic Mudlet console state: replace uses the current format; setters paint
-- selected text AND affect later output. resetFormat restores profile defaults
-- and deselects without repainting the selected text.
-- Keep the profile background nonblack to catch hardcoded "clear to black" fixes.
local function copyFormat(style)
  local result={}
  for key,value in pairs(style) do
    result[key]=type(value)=="table" and {value[1],value[2],value[3]} or value
  end
  return result
end
local function formattedConsole(lines,settings)
  local f,api,a=console(lines,settings)
  f.defaultFormat={foreground={220,224,220},background={9,13,17},bold=false,underline=false,italics=false}
  f.format={foreground={255,215,80},background={80,25,20},bold=true,underline=true,italics=false}
  f.cells={}
  for row,text in pairs(lines) do
    f.cells[row]={}
    for column=1,#text do f.cells[row][column]=copyFormat(f.defaultFormat) end
  end
  local select,replace,delete=api.selectSection,api.replace,api.deleteLine
  api.selectSection=function(start,length)
    local ok=select(start,length)
    f.selected={row=f.cursor,start=start,length=length}
    return ok
  end
  api.replace=function(text)
    assert(f.selected and f.selected.row==f.cursor,"replacement lost its native selection")
    eq(f.selected.start,0); eq(f.selected.length,#f.lines[f.cursor])
    replace(text)
    f.cells[f.cursor]={}
    for column=1,#text do f.cells[f.cursor][column]=copyFormat(f.format) end
  end
  api.deleteLine=function()
    local row=f.cursor; local last=row
    for number in pairs(f.cells) do last=math.max(last,number) end
    delete()
    for number=row,last do f.cells[number]=f.cells[number+1] end
    f.selected=nil
  end
  api.deselect=function() f.selected=nil end
  api.resetFormat=function()
    f.format=copyFormat(f.defaultFormat)
    api.deselect()
  end
  local function apply(field,value)
    f.format[field]=type(value)=="table" and {value[1],value[2],value[3]} or value
    local selected=f.selected
    if selected then
      for column=selected.start+1,selected.start+selected.length do
        local cell=assert(f.cells[selected.row][column],"formatting extends beyond replacement")
        cell[field]=type(value)=="table" and {value[1],value[2],value[3]} or value
      end
    end
  end
  api.setFgColor=function(r,g,b) f.colors[f.cursor]={r,g,b}; apply("foreground",{r,g,b}) end
  api.setBgColor=function(r,g,b) f.backgrounds[f.cursor]={r,g,b}; apply("background",{r,g,b}) end
  api.setBold=function(value) f.bold[f.cursor]=value; apply("bold",value) end
  api.setUnderline=function(value) apply("underline",value) end
  api.getBgColor=function()
    if not f.selected then return nil,"no selected text" end
    local color=f.cells[f.selected.row][f.selected.start+1].background
    return color[1],color[2],color[3]
  end
  api.getBackgroundColor=function(window)
    assert(window==nil or window=="main")
    local color=f.defaultFormat.background
    return color[1],color[2],color[3],255
  end
  api.echo=function(text) f.echoed={text=text,format=copyFormat(f.format)} end
  return f,api,a
end
local function formatEquals(actual,expected,context)
  for _,field in ipairs({"foreground","background","bold","underline","italics"}) do
    if type(expected[field])=="table" then
      for channel=1,3 do
        assert(actual[field][channel]==expected[field][channel],
          context.." "..field.." channel "..channel..": expected "..expected[field][channel]..", got "..actual[field][channel])
      end
    else
      assert(actual[field]==expected[field],context.." "..field..": expected "..tostring(expected[field])..", got "..tostring(actual[field]))
    end
  end
end
local function rowFormatEquals(f,row,expected)
  eq(#f.cells[row],#f.lines[row])
  for column,cell in ipairs(f.cells[row]) do formatEquals(cell,expected,"row "..row.." column "..column) end
end

-- Mudlet deletes buffer rows without changing the painted viewport. Its empty
-- main-console echo refreshes tail mode but does not add a line or send a command.
local function viewportConsole(lines,scroll)
  local f,api,a=console(lines)
  local function lastLine()
    local last=0
    for row in pairs(f.lines) do if type(row)=="number" then last=math.max(last,row) end end
    return last
  end
  f.cursor=lastLine(); f.visibleLast=scroll or f.cursor; f.tail=scroll==nil; f.refreshes=0
  api.getLastLineNumber=function(window) eq(window,"main"); return lastLine() end
  api.getScroll=function(window) eq(window,"main"); return math.min(f.visibleLast,lastLine()) end
  api.echo=function(window,text)
    eq(window,"main"); eq(text,"")
    f.refreshes=f.refreshes+1
    if f.tail then f.visibleLast=lastLine() end
    return true
  end
  return f,api,a,lastLine
end
local function filteredViewportRows(lines)
  return {
    {line_number=1,source_line=lines[1],display_text="Number  Skill    LVL  USES"},
    {line_number=2,source_line=lines[2],display_text="    47  Clawing    3   201",style_id="skill_combat"},
    {line_number=4,source_line=lines[4],remove=true},
    {line_number=5,source_line=lines[5],remove=true},
  }
end
local function viewportLines()
  return {[1]="Skill Remain Level",[2]=" Biting       400 4",[3]="An enemy attacks!",
    [4]=" Clawing       201 3",[5]=" Swimming       100 1",[6]=">"}
end

test("filtered skills refresh the tail viewport immediately without new output",function()
  local lines=viewportLines(); local f,api,a,lastLine=viewportConsole(lines)
  assert(a:replaceSkillOutput(filteredViewportRows(lines),api))
  eq(f.visibleLast,lastLine()); eq(f.refreshes,1)
  eq(f.lines[3],"An enemy attacks!"); eq(f.lines[4],">"); eq(f.lines[5],nil)
  eq(f.cursor,4); eq(f.column,2); eq(f.deleted,2)
end)
test("no-match filtering refreshes once and leaves only its message and existing prompt",function()
  local lines={[1]="Skill Remain Level",[2]=" Biting       400 4",[3]=" Clawing       201 3",[4]=">"}
  local f,api,a,lastLine=viewportConsole(lines)
  assert(a:replaceSkillOutput({{line_number=1,source_line=lines[1],display_text="No skills match: xyz"},
    {line_number=2,source_line=lines[2],remove=true},{line_number=3,source_line=lines[3],remove=true}},api))
  eq(f.visibleLast,lastLine()); eq(f.refreshes,1); eq(f.lines[1],"No skills match: xyz")
  eq(f.lines[2],">"); eq(f.lines[3],nil); eq(f.cursor,2)
end)
test("filtered skills do not pull a reader out of scrollback",function()
  local lines=viewportLines(); local f,api,a=viewportConsole(lines,2)
  assert(a:replaceSkillOutput(filteredViewportRows(lines),api))
  eq(f.visibleLast,2); eq(f.tail,false); eq(f.refreshes,0)
  eq(f.cursor,4); eq(f.lines[4],">")
end)
test("optional viewport APIs cannot block skill filtering or add output",function()
  for _,mode in ipairs({"missing-scroll","missing-last","missing-echo","scroll-error","last-error",
      "negative","fractional","nan","infinite","string","echo-error"}) do
    local lines=viewportLines(); local f,api,a=viewportConsole(lines)
    if mode=="missing-scroll" then api.getScroll=nil
    elseif mode=="missing-last" then api.getLastLineNumber=nil
    elseif mode=="missing-echo" then api.echo=nil
    elseif mode=="scroll-error" then api.getScroll=function() error("unavailable") end
    elseif mode=="last-error" then api.getLastLineNumber=function() error("unavailable") end
    elseif mode=="echo-error" then api.echo=function() error("unavailable") end
    else
      api.getScroll=function()
        if mode=="negative" then return -1 elseif mode=="fractional" then return 1.5
        elseif mode=="nan" then return 0/0 elseif mode=="infinite" then return math.huge end
        return "6"
      end
    end
    assert(a:replaceSkillOutput(filteredViewportRows(lines),api))
    eq(f.refreshes,0); eq(f.deleted,2); eq(f.lines[4],">"); eq(f.lines[5],nil)
  end
end)
test("failed preflight and first native deletion never refresh or mutate the viewport",function()
  for _,mode in ipairs({"changed-row","delete-error"}) do
    local lines=viewportLines(); local f,api,a=viewportConsole(lines); local rows=filteredViewportRows(lines)
    if mode=="changed-row" then rows[3].source_line=" Clawing       200 3"
    else api.deleteLine=function() return false,"unavailable" end end
    eq(a:replaceSkillOutput(rows,api),nil)
    eq(f.refreshes,0); eq(f.visibleLast,6); eq(f.deleted,nil); eq(f.replaced,0)
    eq(f.cursor,6); eq(f.column,2); eq(f.lines[6],">")
  end
end)
test("partial deletion failure refreshes changed rows while preserving its error and prompt cursor",function()
  local lines=viewportLines(); local f,api,a,lastLine=viewportConsole(lines)
  local delete=api.deleteLine; local attempts=0
  api.deleteLine=function()
    attempts=attempts+1
    if attempts==2 then return false,"unavailable" end
    return delete()
  end
  local ok,err=a:replaceSkillOutput(filteredViewportRows(lines),api)
  eq(ok,nil); assert(err:find("could not hide",1,true))
  eq(f.deleted,1); eq(f.visibleLast,lastLine()); eq(f.refreshes,1)
  eq(f.lines[1],"Skill Remain Level"); eq(f.lines[3],"An enemy attacks!")
  eq(f.lines[4]," Clawing       201 3"); eq(f.lines[5],">"); eq(f.cursor,5); eq(f.column,2)
end)
test("retained skill cursor failures after deletion are reported rather than silently showing a wrong skill",function()
  local lines=viewportLines(); local f,api,a,lastLine=viewportConsole(lines)
  local move=api.moveCursor
  api.moveCursor=function(column,row)
    if column==0 and row==2 then return false end
    return move(column,row)
  end
  local ok,err=a:replaceSkillOutput(filteredViewportRows(lines),api)
  eq(ok,nil); assert(type(err)=="string"); eq(f.deleted,2); eq(f.refreshes,1)
  eq(f.visibleLast,lastLine()); eq(f.lines[4],">"); eq(f.cursor,4); eq(f.column,2)
end)
test("explicit native replacement failure after deletion is reported and the viewport still settles",function()
  for _,mode in ipairs({"false","nil-error"}) do
    local lines=viewportLines(); local f,api,a,lastLine=viewportConsole(lines)
    local rows=filteredViewportRows(lines); rows[1].display_text="Skills"; rows[2].display_text="Clawing"
    api.replace=function()
      if mode=="false" then return false,"unavailable" end
      return nil,"unavailable"
    end
    local ok,err=a:replaceSkillOutput(rows,api)
    eq(ok,nil); assert(type(err)=="string"); eq(f.refreshes,1); eq(f.deleted,2)
    eq(f.visibleLast,lastLine()); eq(f.lines[4],">"); eq(f.cursor,4); eq(f.column,2)
  end
end)
test("full skill formatting without removed rows does not request a compaction repaint",function()
  local lines={[1]="Skill Remain Level",[2]=" Clawing       201 3",[3]=">"}
  local f,api,a=viewportConsole(lines)
  assert(a:replaceSkillOutput({{line_number=1,source_line=lines[1],display_text="Number  Skill    LVL  USES"},
    {line_number=2,source_line=lines[2],display_text="    47  Clawing    3   201"}},api))
  eq(f.refreshes,0); eq(f.deleted,nil); eq(f.lines[3],">"); eq(f.cursor,3); eq(f.column,2)
end)
test("skill filtering compacts only skill rows and preserves interleaved combat and prompt",function()
  local lines={[1]="Skill Remain Level",[2]=" Biting       400 4",[3]="An enemy attacks!",
    [4]=" Clawing       201 3",[5]=" Swimming       100 1",[6]=">"}
  local f,api,a=console(lines); f.cursor=6
  assert(a:replaceSkillOutput({
    {line_number=1,source_line=lines[1],display_text="Number  Skill    LVL  USES"},
    {line_number=2,source_line=lines[2],display_text="    47  Clawing    3   201",style_id="skill_combat"},
    {line_number=4,source_line=lines[4],remove=true},
    {line_number=5,source_line=lines[5],remove=true},
  },api))
  eq(f.lines[1],"Number  Skill    LVL  USES"); eq(f.lines[2],"    47  Clawing    3   201")
  eq(f.lines[3],"An enemy attacks!"); eq(f.lines[4],">"); eq(f.lines[5],nil)
  eq(f.cursor,4); eq(f.column,2); eq(f.deleted,2)
end)
test("a no-match skill result keeps a message and prompt instead of empty skill rows",function()
  local lines={[1]="Skill Remain Level",[2]=" Biting       400 4",[3]=" Clawing       201 3",[4]=">"}
  local f,api,a=console(lines); f.cursor=4
  assert(a:replaceSkillOutput({{line_number=1,source_line=lines[1],display_text="No skills match: xyz"},
    {line_number=2,source_line=lines[2],remove=true},{line_number=3,source_line=lines[3],remove=true}},api))
  eq(f.lines[1],"No skills match: xyz"); eq(f.lines[2],">"); eq(f.lines[3],nil); eq(f.cursor,2)
end)
test("filtered skills preflight all source rows before any deletion",function()
  local lines={[1]="Skill Remain Level",[2]=" Biting       400 4",[3]="A new combat line!",[4]=">"}
  local f,api,a=console(lines)
  eq(a:replaceSkillOutput({{line_number=1,source_line=lines[1],display_text="No skills match: xyz"},
    {line_number=2,source_line=lines[2],remove=true},
    {line_number=3,source_line=" Clawing       201 3",remove=true}},api),nil)
  eq(f.deleted,nil); eq(f.replaced,0); eq(f.lines[3],"A new combat line!"); eq(f.lines[4],">")
end)
test("skill filtering refuses prompts combat nonboolean actions and absent header ownership",function()
  for _,source in ipairs({">","An enemy hits you for 12 damage.","OR:  13 DR: 74"}) do
    local f,api,a=console({[1]="Skill Remain Level",[2]=source})
    eq(a:replaceSkillOutput({{line_number=1,source_line="Skill Remain Level",display_text="No match"},
      {line_number=2,source_line=source,remove=true}},api),nil)
    eq(f.deleted,nil); eq(f.replaced,0)
  end
  for _,rows in ipairs({{{line_number=2,source_line=" Biting       400 4",remove=true}},
      {{line_number=2,source_line=" Biting       400 4",display_text="x",remove="true"}}}) do
    local f,api,a=console({[2]=" Biting       400 4"})
    eq(a:replaceSkillOutput(rows,api),nil); eq(f.deleted,nil); eq(f.replaced,0)
  end
end)
test("missing or rejected native deletion keeps filtered skill output unchanged",function()
  for _,mode in ipairs({"missing","false","nil-error","throw"}) do
    local lines={[1]="Skill Remain Level",[2]=" Biting       400 4",[3]=">"}
    local f,api,a=console(lines)
    if mode=="missing" then api.deleteLine=nil
    elseif mode=="false" then api.deleteLine=function() return false end
    elseif mode=="nil-error" then api.deleteLine=function() return nil,"failed" end
    else api.deleteLine=function() error("failed") end end
    eq(a:replaceSkillOutput({{line_number=1,source_line=lines[1],display_text="No match"},
      {line_number=2,source_line=lines[2],remove=true}},api),nil)
    eq(f.deleted,nil); eq(f.replaced,0); eq(f.lines[2]," Biting       400 4"); eq(f.lines[3],">")
  end
end)
test("filtered skills validate the original cursor before any console mutation",function()
  for _,invalid in ipairs({"missing","negative","nan","throw"}) do
    local lines={[1]="Skill Remain Level",[2]=" Biting       400 4",[3]=">"}
    local f,api,a=console(lines)
    api.getColumnNumber=function()
      if invalid=="negative" then return -1 elseif invalid=="nan" then return 0/0
      elseif invalid=="throw" then error("cursor unavailable") end
    end
    eq(a:replaceSkillOutput({{line_number=1,source_line=lines[1],display_text="No match"},
      {line_number=2,source_line=lines[2],remove=true}},api),nil)
    eq(f.deleted,nil); eq(f.replaced,0); eq(f.lines[3],">")
  end
end)
test("skill adapter tolerates only trailing fixed-width padding and selects exact buffer length",function()
  for _,buffer in ipairs({" Sharp Weapons       400 4"," Sharp Weapons       400 4      "}) do
    local f,api,a=console({[1]="Skill Remain Level",[2]=buffer})
    assert(a:replaceSkillOutput({{line_number=1,source_line="Skill Remain Level  ",display_text="No.  Skill  Level  Uses"},
      {line_number=2,source_line=" Sharp Weapons       400 4   ",display_text="2.  Sharps  4  400",style_id="skill_combat"}},api))
    eq(f.replaced,2); eq(f.selections[1].length,#buffer); eq(f.cursor,9); eq(f.column,2)
  end
end)
test("skill adapter still rejects changed interior text partial wraps and shifted rows atomically",function()
  for _,buffer in ipairs({"Sharp Weapons       400 4"," Sharp Weapons       399 4"," Sharp Weapons       400", "A different line."}) do
    local f,api,a=console({[1]="Skill Remain Level",[2]=buffer})
    local ok=a:replaceSkillOutput({{line_number=1,source_line="Skill Remain Level",display_text="No. Skill Level Uses"},
      {line_number=2,source_line=" Sharp Weapons       400 4   ",display_text="2.  Sharps  4  400"}},api)
    eq(ok,nil); eq(f.replaced,0); eq(f.lines[1],"Skill Remain Level"); eq(f.lines[2],buffer)
  end
end)
test("skill adapter applies full-row green blue yellow styles with ready priority metadata",function()
  local rows,lines={},{}
  for row,id in ipairs({"skill_ready","skill_combat","skill_utility"}) do
    lines[row]=" Original Skill       100 1"
    rows[row]={line_number=row,source_line=lines[row],display_text="1.  Skill  1  100",style_id=id}
  end
  local f,api,a=console(lines); assert(a:replaceSkillOutput(rows,api))
  for row,id in ipairs({"skill_ready","skill_combat","skill_utility"}) do
    local expected=assert(Styles.toRGB(Styles.defaults(id).foreground))
    for index=1,3 do eq(f.colors[row][index],expected[index]) end
    eq(f.selections[(4-row)*2].length,#rows[row].display_text)
  end
end)
test("skill row colors honor master category and individual toggles without disabling formatting",function()
  for _,config in ipairs({{enabled=false},{skills_enabled=false},{highlights_enabled=false},{styles={skill_combat={enabled=false}}}}) do
    local raw=" Sharp Weapons       400 4"; local f,api,a=console({[2]=raw},config)
    assert(a:replaceSkillOutput({{line_number=2,source_line=raw,display_text="2. Sharps 4 400",style_id="skill_combat"}},api))
    eq(f.replaced,1); eq(f.colors[2][1],220); eq(f.colors[2][2],224); eq(f.colors[2][3],220)
  end
end)
test("skill colors are editable and saved as data with category enabled state",function()
  local config={skills_enabled=false,styles={skill_utility={foreground="#123456",background="#223344",bold=true,underline=false,enabled=true}}}
  local saved=assert(Preferences.decode(assert(Preferences.encode(config))))
  eq(saved.skills_enabled,false); eq(saved.styles.skill_utility.foreground,"#123456")
  saved.skills_enabled=true
  local raw=" Swimming       100 1"; local f,api,a=console({[2]=raw},saved)
  assert(a:replaceSkillOutput({{line_number=2,source_line=raw,display_text="23. Swimming 1 100",style_id="skill_utility"}},api))
  eq(f.colors[2][1],18); eq(f.colors[2][2],52); eq(f.colors[2][3],86)
  eq(f.backgrounds[2][1],34); eq(f.bold[2],true)
end)

-- All fixtures are synthetic; no player logs, profile files, or live APIs.
for _,id in ipairs({"skill_ready","skill_combat","skill_utility"}) do
  test(id.." replacement clears inherited red background and other console attributes",function()
    local raw=" Original Skill       100 1"
    local f,api,a=formattedConsole({[2]=raw,[9]=">"})
    for _,cell in ipairs(f.cells[2]) do cell.background={80,25,20} end
    local text="1. Skill 1 100"
    assert(a:replaceSkillOutput({{line_number=2,source_line=raw,display_text=text,style_id=id}},api))
    local expected=copyFormat(f.defaultFormat)
    expected.foreground=assert(Styles.toRGB(Styles.defaults(id).foreground))
    rowFormatEquals(f,2,expected); eq(f.lines[2],text)
    rowFormatEquals(f,9,f.defaultFormat); eq(f.cursor,9); eq(f.column,2); eq(f.selected,nil)
  end)
end
for _,text in ipairs({"Number  Skill  LVL  USES","No skills match: xyz"}) do
  test("neutral skill replacement clears inherited formatting: "..text,function()
    local raw="Skill Remain Level"; local f,api,a=formattedConsole({[1]=raw,[9]=">"})
    assert(a:replaceSkillOutput({{line_number=1,source_line=raw,display_text=text}},api))
    rowFormatEquals(f,1,f.defaultFormat); eq(f.lines[1],text)
    eq(f.cursor,9); eq(f.column,2); eq(f.selected,nil)
  end)
end
test("filtered skill replacement clears inherited background without painting combat or prompt",function()
  local lines=viewportLines(); local f,api,a=formattedConsole(lines); f.cursor=6
  assert(a:replaceSkillOutput(filteredViewportRows(lines),api))
  local expected=copyFormat(f.defaultFormat); expected.foreground=assert(Styles.toRGB(Styles.defaults("skill_combat").foreground))
  rowFormatEquals(f,1,f.defaultFormat); rowFormatEquals(f,2,expected)
  eq(f.lines[3],"An enemy attacks!"); eq(f.lines[4],">"); eq(f.lines[5],nil)
  rowFormatEquals(f,3,f.defaultFormat); rowFormatEquals(f,4,f.defaultFormat)
  eq(f.deleted,2); eq(f.cursor,4); eq(f.column,2); eq(f.selected,nil)
end)
for _,disabled in ipairs({
  {name="master",config={enabled=false}},
  {name="Skill Row Colors",config={skills_enabled=false}},
  {name="legacy highlights",config={highlights_enabled=false}},
  {name="individual skill",config={styles={skill_combat={enabled=false}}}},
}) do
  test("skill replacement with "..disabled.name.." off clears inherited formatting and ignores overrides",function()
    local raw=" Sharp Weapons       400 4"; local config={}
    for key,value in pairs(disabled.config) do config[key]=value end
    local enabled=not (config.styles and config.styles.skill_combat.enabled==false)
    config.styles={skill_combat={enabled=enabled,foreground="#123456",background="#223344",bold=true,underline=true}}
    local f,api,a=formattedConsole({[2]=raw,[9]=">"},config)
    assert(a:replaceSkillOutput({{line_number=2,source_line=raw,display_text="2. Sharps 4 400",style_id="skill_combat"}},api))
    rowFormatEquals(f,2,f.defaultFormat); eq(f.replaced,1); eq(f.cursor,9); eq(f.column,2)
  end)
end
test("Skill Row Colors on then off removes the previous intentional background on replacement",function()
  local raw=" Swimming       100 1"
  local config={skills_enabled=true,styles={skill_utility={foreground="#123456",background="#223344",bold=true,underline=true}}}
  local f,api,a=formattedConsole({[2]=raw,[9]=">"},config)
  local text="23. Swimming 1 100"
  assert(a:replaceSkillOutput({{line_number=2,source_line=raw,display_text=text,style_id="skill_utility"}},api))
  local expected=copyFormat(f.defaultFormat)
  expected.foreground={18,52,86}; expected.background={34,51,68}; expected.bold=true; expected.underline=true
  -- First prove the configured style was applied, then toggle the same adapter.
  for _,cell in ipairs(f.cells[2]) do
    for channel=1,3 do
      eq(cell.foreground[channel],expected.foreground[channel])
      eq(cell.background[channel],expected.background[channel])
    end
    eq(cell.bold,true); eq(cell.underline,true)
  end
  config.skills_enabled=false
  assert(a:replaceSkillOutput({{line_number=2,source_line=text,display_text="23. Swimming 1 99",style_id="skill_utility"}},api))
  rowFormatEquals(f,2,f.defaultFormat); eq(f.replaced,2); eq(f.cursor,9); eq(f.column,2)
  api.echo("Synthetic future output after toggle off")
  formatEquals(f.echoed.format,f.defaultFormat,"future output after toggle off")
end)
for _,background in ipairs({false,"#223344","#501914"}) do
  test("skill replacement preserves configured foreground bold underline and background "..tostring(background),function()
    for _,attributes in ipairs({
      {bold=true,underline=true}, {bold=true,underline=false},
      {bold=false,underline=true}, {bold=false,underline=false},
    }) do
      local raw=" Swimming       100 1"
      local config={styles={skill_utility={
        foreground="#123456",background=background,
        bold=attributes.bold,underline=attributes.underline,
      }}}
      local f,api,a=formattedConsole({[2]=raw,[9]=">"},config)
      assert(a:replaceSkillOutput({{line_number=2,source_line=raw,display_text="23. Swimming 1 100",style_id="skill_utility"}},api))
      local expected=copyFormat(f.defaultFormat); expected.foreground={18,52,86}
      if background then expected.background=assert(Styles.toRGB(background)) end
      expected.bold=attributes.bold; expected.underline=attributes.underline
      rowFormatEquals(f,2,expected)
      eq(f.cursor,9); eq(f.column,2); eq(f.selected,nil)
    end
  end)
end
test("skill replacement settles the current console format after an intentional row background",function()
  local raw=" Swimming       100 1"
  local f,api,a=formattedConsole({[2]=raw,[9]=">"},{styles={skill_utility={foreground="#123456",background="#223344",bold=true,underline=true}}})
  assert(a:replaceSkillOutput({{line_number=2,source_line=raw,display_text="23. Swimming 1 100",style_id="skill_utility"}},api))
  api.echo("Synthetic future output")
  eq(f.echoed.text,"Synthetic future output")
  formatEquals(f.echoed.format,f.defaultFormat,"future output after replacement")
  eq(f.selected,nil); eq(f.cursor,9); eq(f.column,2)
end)
test("skill replacement cleans current formatting after a later row fails",function()
  local lines={[1]="Skill Remain Level",[2]=" Swimming       100 1",[9]=">"}
  local f,api,a=formattedConsole(lines,{styles={skill_utility={background="#223344",bold=true,underline=true}}})
  local replace=api.replace
  api.replace=function(text)
    if f.cursor==1 then return false,"synthetic replacement failure" end
    return replace(text)
  end
  local ok,err=a:replaceSkillOutput({
    {line_number=1,source_line=lines[1],display_text="Number Skill LVL USES"},
    {line_number=2,source_line=lines[2],display_text="23. Swimming 1 100",style_id="skill_utility"},
  },api)
  eq(ok,nil); assert(err:find("could not replace",1,true))
  eq(f.replaced,1); eq(f.lines[1],"Skill Remain Level")
  api.echo("Synthetic future output after failure")
  formatEquals(f.echoed.format,f.defaultFormat,"future output after failed replacement")
  eq(f.selected,nil); eq(f.cursor,9); eq(f.column,2)
end)
test("failed skill preflight leaves inherited formatting and unrelated rows untouched",function()
  local raw=" Swimming       100 1"; local f,api,a=formattedConsole({[2]=raw,[9]=">"})
  local before=copyFormat(f.format)
  eq(a:replaceSkillOutput({{line_number=2,source_line=" Swimming       99 1",display_text="23. Swimming 1 99",style_id="skill_utility"}},api),nil)
  eq(f.replaced,0); eq(f.lines[2],raw)
  formatEquals(f.format,before,"current format after rejected preflight")
  rowFormatEquals(f,2,f.defaultFormat); rowFormatEquals(f,9,f.defaultFormat)
  eq(f.cursor,9); eq(f.column,2); eq(f.selected,nil)
end)
test("native notice formatting is preserved while later skill rows and unrelated echoes stay clean",function()
  for _,id in ipairs({"skill_combat","skill_utility"}) do
    local notice="(There are new version notes.)"; local raw=" Original Skill       100 1"
    local f,api,a=formattedConsole({[1]=notice,[2]=raw,[9]=">"})
    f.format=copyFormat(f.defaultFormat)
    local style=assert(Styles.defaults("notice"))
    local expected=copyFormat(f.defaultFormat)
    expected.foreground=assert(Styles.toRGB(style.foreground))
    expected.background=assert(Styles.toRGB(style.background))
    expected.bold=style.bold; expected.underline=style.underline
    assert(a:applyLineColors({{line_number=1,source_line=notice,start=1,length=#notice,
      display_text="*** IMPORTANT - PLEASE READ: SYNTHETIC VERSION NOTES ***",
      color=expected.foreground,background=expected.background,bold=style.bold,underline=style.underline}},api))
    rowFormatEquals(f,1,expected)
    api.echo("Synthetic output after notice")
    local afterNotice=copyFormat(f.echoed.format)
    eq(f.cursor,9); eq(f.column,2); eq(f.selected,nil)
    assert(a:replaceSkillOutput({{line_number=2,source_line=raw,display_text="1. Skill 1 100",style_id=id}},api))
    local skill=copyFormat(f.defaultFormat); skill.foreground=assert(Styles.toRGB(Styles.defaults(id).foreground))
    rowFormatEquals(f,2,skill); rowFormatEquals(f,1,expected)
    api.echo("Synthetic output after skills")
    formatEquals(afterNotice,f.defaultFormat,"future output after notice")
    formatEquals(f.echoed.format,f.defaultFormat,"future output after notice and skills")
    eq(f.cursor,9); eq(f.column,2); eq(f.selected,nil)
  end
end)
test("native notice setter exception restores cursor and future echo formatting",function()
  local notice="(There are new version notes.)"
  local f,api,a=formattedConsole({[1]=notice,[9]=">"})
  f.format=copyFormat(f.defaultFormat)
  local underline=api.setUnderline
  api.setUnderline=function(value) underline(value); error("synthetic underline failure") end
  local ok,err=a:applyLineColors({{line_number=1,source_line=notice,start=1,length=#notice,
    display_text="*** SYNTHETIC NOTICE ***",color={255,215,80},background={80,25,20},bold=true,underline=true}},api)
  eq(ok,nil); assert(err:find("synthetic underline failure",1,true)); eq(f.replaced,1)
  eq(f.cursor,9); eq(f.column,2); eq(f.selected,nil)
  api.echo("Synthetic output after notice exception")
  formatEquals(f.echoed.format,f.defaultFormat,"future output after notice setter exception")
end)
test("skill style setter exception restores cursor and future echo formatting",function()
  local raw=" Swimming       100 1"
  local f,api,a=formattedConsole({[2]=raw,[9]=">"},{styles={skill_utility={background="#223344",bold=true,underline=true}}})
  local underline=api.setUnderline
  api.setUnderline=function(value) underline(value); error("synthetic skill underline failure") end
  local ok,err=a:replaceSkillOutput({{line_number=2,source_line=raw,display_text="23. Swimming 1 100",style_id="skill_utility"}},api)
  eq(ok,nil); assert(err:find("synthetic skill underline failure",1,true)); eq(f.replaced,1)
  eq(f.cursor,9); eq(f.column,2); eq(f.selected,nil)
  api.echo("Synthetic output after skill setter exception")
  formatEquals(f.echoed.format,f.defaultFormat,"future output after skill setter exception")
end)
test("generic foreground coloring preserves a selected object's intentional background",function()
  local raw="A synthetic object is here."; local f,api,a=formattedConsole({[2]=raw,[9]=">"})
  f.format=copyFormat(f.defaultFormat)
  for _,cell in ipairs(f.cells[2]) do cell.background={42,41,40} end
  assert(a:applyLineColors({{line_number=2,source_line=raw,start=1,length=#raw,color={18,52,86},bold=false,underline=false}},api))
  local expected=copyFormat(f.defaultFormat); expected.foreground={18,52,86}; expected.background={42,41,40}
  rowFormatEquals(f,2,expected); eq(f.replaced,0)
  api.echo("Synthetic output after object coloring")
  formatEquals(f.echoed.format,f.defaultFormat,"future output after generic coloring")
  eq(f.cursor,9); eq(f.column,2); eq(f.selected,nil)
end)
test("skill default background safely falls back when the native background API is absent or invalid",function()
  for _,mode in ipairs({
    "missing","throw","nil","string","table","negative","large",
    "fractional","nan","infinite","missing-channel",
  }) do
    local raw=" Original Skill       100 1"; local f,api,a=formattedConsole({[2]=raw,[9]=">"})
    if mode=="missing" then api.getBackgroundColor=nil
    else
      api.getBackgroundColor=function(window)
        eq(window,"main")
        if mode=="throw" then error("synthetic background API failure")
        elseif mode=="nil" then return nil,"unavailable"
        elseif mode=="string" then return "9",13,17
        elseif mode=="table" then return {9,13,17}
        elseif mode=="negative" then return -1,13,17
        elseif mode=="large" then return 9,256,17
        elseif mode=="fractional" then return 9,13,17.5
        elseif mode=="nan" then return 0/0,13,17
        elseif mode=="infinite" then return 9,math.huge,17 end
        return 9,13
      end
    end
    assert(a:replaceSkillOutput({{line_number=2,source_line=raw,display_text="1. Skill 1 100",style_id="skill_combat"}},api))
    local expected=copyFormat(f.defaultFormat)
    expected.foreground=assert(Styles.toRGB(Styles.defaults("skill_combat").foreground))
    expected.background={0,0,0}
    rowFormatEquals(f,2,expected); eq(f.cursor,9); eq(f.column,2); eq(f.selected,nil)
    api.echo("Synthetic output with background fallback")
    formatEquals(f.echoed.format,f.defaultFormat,"future output after background fallback "..mode)
  end
end)
