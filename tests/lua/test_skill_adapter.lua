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
    setFgColor=function(r,g,b) f.colors[f.cursor]={r,g,b} end,
    setBgColor=function(r,g,b) f.backgrounds[f.cursor]={r,g,b} end,
    setBold=function(value) f.bold[f.cursor]=value end,
    deselect=function() end,
  }
  local adapter=Adapter.new(); adapter.settings={colorization=settings or {}}
  return f,api,adapter
end
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
