local Adapter=require("mudlet_adapter")
local Display=require("wealth_display")

-- Entirely synthetic fixtures. Model native selections, replacement tails, and
-- format setters affecting both selected cells and the next scripted output.
local function copy(value)
  if type(value)~="table" then return value end
  local out={}; for key,item in pairs(value) do out[key]=copy(item) end
  return out
end
local function same(actual,expected)
  if type(expected)~="table" then eq(actual,expected); return end
  eq(type(actual),"table")
  for key,value in pairs(expected) do same(actual[key],value) end
  for key in pairs(actual) do assert(expected[key]~=nil,"unexpected field: "..tostring(key)) end
end
local function native(lines)
  local f={lines=copy(lines),cells={},cursor=10,column=4,replacements=0,writes=0,moves=0,resets=0,reads=0,forbidden=0}
  f.defaults={foreground={205,210,215},background={7,12,19},bold=false,underline=false}
  f.format={foreground={255,30,20},background={90,20,15},bold=true,underline=true}
  for row,line in pairs(f.lines) do
    f.cells[row]={}
    for index=1,#line do f.cells[row][index]=copy(f.format) end
  end
  local api={}
  api.getLineNumber=function() return f.cursor end
  api.getColumnNumber=function() return f.column end
  api.getBackgroundColor=function(window) eq(window,"main"); return 7,12,19,255 end
  api.getLines=function(first,last)
    eq(last,first+1); f.reads=f.reads+1
    return {f.lines[first]}
  end
  api.moveCursor=function(column,row)
    f.moves=f.moves+1; f.cursor=row; f.column=column; return true
  end
  api.selectSection=function(start,length)
    assert(f.lines[f.cursor],"selection outside main console")
    assert(start>=0 and length>=1 and start+length<=#f.lines[f.cursor],"selection outside native row")
    f.selected={row=f.cursor,start=start,length=length}
    f.column=start+length
    f.writes=f.writes+1
    return true
  end
  api.replace=function(text)
    local s=assert(f.selected,"replace requires native selection")
    eq(s.row,f.cursor)
    local before=f.lines[s.row]
    f.lines[s.row]=before:sub(1,s.start)..text..before:sub(s.start+s.length+1)
    local cells={}
    for index=1,s.start do cells[#cells+1]=copy(f.cells[s.row][index]) end
    for _=1,#text do cells[#cells+1]=copy(f.format) end
    for index=s.start+s.length+1,#before do cells[#cells+1]=copy(f.cells[s.row][index]) end
    f.cells[s.row]=cells
    f.replacements=f.replacements+1; f.writes=f.writes+1
  end
  local function paint(field,value)
    f.format[field]=copy(value)
    local s=assert(f.selected,"formatting must select the replacement")
    for index=s.start+1,s.start+s.length do
      assert(f.cells[s.row][index],"formatting outside replacement")[field]=copy(value)
    end
    f.writes=f.writes+1
  end
  api.setFgColor=function(r,g,b) paint("foreground",{r,g,b}) end
  api.setBgColor=function(r,g,b) paint("background",{r,g,b}) end
  api.setBold=function(value) paint("bold",value) end
  api.setUnderline=function(value) paint("underline",value) end
  api.deselect=function() f.selected=nil end
  api.resetFormat=function() f.resets=f.resets+1; f.format=copy(f.defaults); f.selected=nil end
  for _,name in ipairs({"echo","cecho","decho","hecho","insertText","deleteLine","send","sendAll",
      "appendBuffer","raiseEvent","postHTTP","downloadFile","writeFile","getBgColor"}) do
    api[name]=function() f.forbidden=f.forbidden+1; error("forbidden wealth side effect: "..name) end
  end
  local adapter=Adapter.new()
  adapter.settings={colorization={enabled=true,notice={bold=true,underline=true,background="#FF0000"}}}
  return f,api,adapter
end
local function fixture()
  local lines={[0]="Synthetic room output",[2]="Synthetic Low has 3 silver",
    [3]="Synthetic chat remains here",[5]="Synthetic High has 20000 silver",
    [8]="Done.       ",[10]="Synthetic prompt>"}
  local f,api,a=native(lines)
  local rows={
    {line_number=2,source_line=lines[2],display_text="Name             Silver"},
    {line_number=5,source_line=lines[5],display_text="Synthetic High   20,000"},
    {line_number=8,source_line=lines[8],display_text="Synthetic Low         3"},
  }
  return f,api,a,rows
end
local function rejected(change)
  local f,api,a,rows=fixture()
  change(rows,f,api)
  local before=copy(f.lines); local cells=copy(f.cells); local format=copy(f.format)
  local cursor,column=f.cursor,f.column
  local ok,err=a:replaceWealthOutput(rows,api)
  eq(ok,nil); eq(type(err),"string"); assert(#err>0)
  same(f.lines,before); same(f.cells,cells); same(f.format,format)
  eq(f.writes,0); eq(f.moves,0); eq(f.resets,0); eq(f.replacements,0); eq(f.forbidden,0)
  eq(f.cursor,cursor); eq(f.column,column)
end

test("wealth trigger delegates its callback and trigger identity to colorizer",function()
  local a=Adapter.new(); local captured
  a.addColorizerTrigger=function(self,fn) eq(self,a); captured=fn; return 741 end
  local text,row
  local fn=function(value,number) text=value; row=number end
  eq(a:addWealthDisplayTrigger(fn),741); eq(captured,fn)
  captured("Synthetic Example has 5 silver",17)
  eq(text,"Synthetic Example has 5 silver"); eq(row,17)
end)
test("wealth replacement uses native slots including Done and leaves interleaved chat intact",function()
  local f,api,a,rows=fixture(); local before=copy(f.lines); local cells=copy(f.cells)
  local shared=a.applyLineColors; local calls=0
  a.applyLineColors=function(self,segments,guarded)
    calls=calls+1; eq(#segments,3)
    return shared(self,segments,guarded)
  end
  assert(a:replaceWealthOutput(rows,api)); eq(calls,1)
  for _,row in ipairs(rows) do eq(f.lines[row.line_number],row.display_text) end
  for _,row in ipairs({0,3,10}) do eq(f.lines[row],before[row]); same(f.cells[row],cells[row]) end
  eq(f.replacements,3); eq(f.cursor,10); eq(f.column,4); eq(f.selected,nil); eq(f.forbidden,0)
end)
test("wealth text clears inherited notice formatting over every replacement cell",function()
  local f,api,a,rows=fixture()
  assert(a:replaceWealthOutput(rows,api))
  for _,row in ipairs(rows) do
    eq(#f.cells[row.line_number],#row.display_text)
    for _,cell in ipairs(f.cells[row.line_number]) do
      same(cell,{foreground={220,224,220},background={7,12,19},bold=false,underline=false})
    end
  end
  same(f.format,f.defaults); assert(f.resets>0); eq(f.selected,nil)
end)
test("wealth replacement restores cursor and column when the original cursor is a replaced slot",function()
  for _,position in ipairs({2,5,8}) do
    local f,api,a,rows=fixture(); f.cursor=position; f.column=7
    assert(a:replaceWealthOutput(rows,api))
    eq(f.cursor,position); eq(f.column,7); eq(f.selected,nil)
  end
end)
test("wealth source padding selects the full native line without leftover tails",function()
  for _,padding in ipairs({""," ","                 "}) do
    local f,api,a,rows=fixture()
    f.lines[2]=f.lines[2]..padding; rows[1].source_line=rows[1].source_line.."  "
    rows[1].display_text="Name Silver"; rows[3].source_line="Done."
    assert(a:replaceWealthOutput(rows,api))
    eq(f.lines[2],"Name Silver"); eq(f.lines[8],rows[3].display_text)
    eq(#f.cells[2],#"Name Silver")
  end
end)
test("wealth replacement supports line zero and two-slot minimum",function()
  local lines={[0]="Synthetic Solo has 0 silver",[1]=" Done. "}
  local f,api,a=native(lines)
  assert(a:replaceWealthOutput({
    {line_number=0,source_line=lines[0],display_text="Name           Silver"},
    {line_number=1,source_line=lines[1],display_text="Synthetic Solo      0"},
  },api))
  eq(f.replacements,2); eq(f.lines[0],"Name           Silver"); eq(f.cursor,10); eq(f.column,4)
end)
test("wealth replacement accepts the 513-slot maximum without changing batch data",function()
  local lines,rows={},{}
  for index=1,513 do
    lines[index]=index==513 and "Done." or "SyntheticUnit"..index.." has "..index.." silver"
    rows[index]={line_number=index,source_line=lines[index],display_text=index==1 and "Name Silver" or "Synthetic 1"}
  end
  local before=copy(rows); local f,api,a=native(lines)
  assert(a:replaceWealthOutput(rows,api)); eq(f.replacements,513); same(rows,before)
end)
test("wealth native table preserves 29 sorted synthetic amounts and right aligned silver",function()
  local lines,rows,expected={}, {}, {}
  local items={}
  local nameWidth,silverWidth=#"Synthetic Unit 01",6
  local function formatted(name,silver)
    return name..string.rep(" ",nameWidth-#name).."  "..string.rep(" ",silverWidth-#silver)..silver
  end
  expected[1]=formatted("Name","Silver")
  for index=1,29 do
    local name=string.format("Synthetic Unit %02d",index)
    local amount=string.format("%d",index)
    lines[index*2]=name.." has "..amount.." silver"
    items[index]={name=name,silver=amount}
    expected[index+1]=formatted(string.format("Synthetic Unit %02d",30-index),tostring(30-index))
    lines[index*2+1]="Synthetic interleaved chat "..index
  end
  lines[60]="Done."; lines[70]="Synthetic prompt>"
  local formattedLines=assert(Display.formatRows(items)); same(formattedLines,expected)
  for index=1,30 do
    local slot=index==30 and 60 or index*2
    rows[index]={line_number=slot,source_line=lines[slot],display_text=formattedLines[index]}
  end
  local f,api,a=native(lines); f.cursor=70; f.column=3
  local before=copy(f.cells)
  assert(a:replaceWealthOutput(rows,api))
  for index,row in ipairs(rows) do
    eq(f.lines[row.line_number],expected[index]); eq(#f.lines[row.line_number],nameWidth+2+silverWidth)
    eq(f.lines[row.line_number]:sub(nameWidth+1,nameWidth+2),"  ")
    for _,cell in ipairs(f.cells[row.line_number]) do
      same(cell,{foreground={220,224,220},background={7,12,19},bold=false,underline=false})
    end
  end
  for index=1,29 do eq(f.lines[index*2+1],lines[index*2+1]); same(f.cells[index*2+1],before[index*2+1]) end
  eq(f.replacements,30); eq(f.cursor,70); eq(f.column,3); eq(f.forbidden,0); same(f.format,f.defaults)
end)
test("wealth source accepts horizontal tabs through the shared parser and renders printable columns",function()
  for _,source in ipairs({
    "\tSynthetic Unit has 0007 silver",
    "Synthetic Unit\thas\t0007\tsilver",
    " \tSynthetic Unit \t has \t 0007 \t silver\t ",
  }) do
    local item=assert(Display.parseRow(source)); eq(item.name,"Synthetic Unit"); eq(item.silver,"7")
    local output=assert(Display.formatRows({item}))
    local lines={[2]=source,[3]="Synthetic chat between tabbed rows",[5]="\t Done.\t "}
    local f,api,a=native(lines); local chat=copy(f.cells[3])
    assert(a:replaceWealthOutput({
      {line_number=2,source_line=source,display_text=output[1]},
      {line_number=5,source_line=lines[5],display_text=output[2]},
    },api))
    eq(f.lines[2],output[1]); eq(f.lines[5],output[2])
    assert(not f.lines[2]:find("\t")); assert(not f.lines[5]:find("\t"))
    same(f.cells[3],chat); eq(f.lines[3],lines[3])
    eq(f.cursor,10); eq(f.column,4); same(f.format,f.defaults); eq(f.forbidden,0)
  end
end)
test("wealth preflight does not normalize tab spacing when comparing captured native sources",function()
  rejected(function(rows,f)
    rows[2].source_line="Synthetic High\thas\t20000\tsilver"
    f.lines[5]="Synthetic High has 20000 silver"
  end)
end)
test("wealth native output preserves all 32 amount digits from the shared formatter",function()
  local amount=string.rep("9",32)
  local source="Synthetic Precision\thas\t"..amount.."\tsilver"
  local item=assert(Display.parseRow(source)); local output=assert(Display.formatRows({item}))
  local f,api,a=native({[1]=source,[2]="Done."})
  assert(a:replaceWealthOutput({
    {line_number=1,source_line=source,display_text=output[1]},
    {line_number=2,source_line="Done.",display_text=output[2]},
  },api))
  local rendered=f.lines[2]:match("([0-9,]+)$")
  eq(rendered:gsub(",",""),amount); eq(f.replacements,2)
end)
test("wealth adapter accepts ASCII name punctuation and 32 digit amounts without numeric conversion",function()
  local f,api,a,rows=fixture()
  rows[1].source_line="  Synthetic O'Unit_7-Test has "..string.rep("9",32).." silver  "
  f.lines[2]=rows[1].source_line
  assert(a:replaceWealthOutput(rows,api))
  eq(f.replacements,3)
end)
test("wealth adapter accepts bounded source and display text limits",function()
  local f,api,a,rows=fixture()
  rows[1].source_line=string.rep("N",80).." has 1 silver"
  rows[1].source_line=rows[1].source_line..string.rep(" ",512-#rows[1].source_line)
  rows[1].display_text=string.rep("A",256); f.lines[2]=rows[1].source_line
  assert(a:replaceWealthOutput(rows,api)); eq(#f.lines[2],256)
end)

local badCoordinates={-1,1.5,math.huge,-math.huge,0/0,"2",false}
for index,value in ipairs(badCoordinates) do
  test("wealth preflight rejects invalid coordinate "..index,function()
    rejected(function(rows) rows[2].line_number=value end)
  end)
end
for _,mode in ipairs({"duplicate","decreasing","missing","shifted","changed-first","changed-last","changed-leading","changed-interior","oversized-native","native-control"}) do
  test("wealth whole batch preflight rejects "..mode.." before editing",function()
    rejected(function(rows,f)
      if mode=="duplicate" then rows[2].line_number=2
      elseif mode=="decreasing" then rows[2].line_number=1
      elseif mode=="missing" then f.lines[5]=nil
      elseif mode=="shifted" then f.lines[6]=f.lines[5]; f.lines[5]=f.lines[3]
      elseif mode=="changed-first" then f.lines[2]="Synthetic Different has 3 silver"
      elseif mode=="changed-last" then f.lines[8]="Synthetic chat replaced the terminator"
      elseif mode=="changed-leading" then f.lines[5]=" "..f.lines[5]
      elseif mode=="changed-interior" then f.lines[5]="Synthetic  High has 20000 silver"
      elseif mode=="oversized-native" then f.lines[8]="Done."..string.rep(" ",508)
      elseif mode=="native-control" then f.lines[8]="Done.\t" end
    end)
  end)
end
local badSources={
  "",false,{},string.rep("A",513),"Synthetic Unit has -1 silver","Synthetic Unit has 1.5 silver",
  "Synthetic Unit has 1,000 silver","Synthetic Unit has 1e2 silver","Synthetic Unit has 0x10 silver",
  "Synthetic Unit has 1 gold","Synthetic Unit has 1 silver suffix","9Synthetic has 1 silver",
  "Synthetic/Unit has 1 silver","Synthetic:Unit has 1 silver","Synthetic.Unit has 1 silver",
  string.rep("N",81).." has 1 silver","Synthetic Unit has "..string.rep("9",33).." silver",
  "<red>Synthetic Unit has 1 silver","Synthetic Unit has 1 silver\n","Synthetic\tUnit has 1 silver",
  "Synthetic Unit has 1 silver\0","Synthetic Unit has 1 silver"..string.char(127),
  "Synthetic Unit has 1 silver"..string.char(128),"Done.",
}
for index,value in ipairs(badSources) do
  test("wealth preflight rejects malformed source field "..index,function()
    rejected(function(rows,f) rows[1].source_line=value; f.lines[2]=value end)
  end)
end
local badDisplays={"",false,{},string.rep("A",257),"<red>Name Silver","Name <reset> Silver",
  "Name\tSilver","Name\nSilver","Name\rSilver","Name\27[31mSilver","Name\0Silver","Name"..string.char(127),
  "Name"..string.char(128)}
for index,value in ipairs(badDisplays) do
  test("wealth preflight rejects malformed display field "..index,function()
    rejected(function(rows) rows[3].display_text=value end)
  end)
end
for _,value in ipairs({"Done","done.","Done. suffix"," Done.\v","Synthetic End has 2 silver"}) do
  test("wealth preflight requires exact trimmed final Done syntax "..#value,function()
    rejected(function(rows,f) rows[3].source_line=value; f.lines[8]=value end)
  end)
end
for _,mode in ipairs({"empty","one","too-many","hole","extra-index","string-key","metatable","row-metatable",
    "row-type","missing-source","missing-display","missing-position","remove","style"}) do
  test("wealth preflight rejects invalid batch shape "..mode,function()
    rejected(function(rows)
      if mode=="empty" then for key in pairs(rows) do rows[key]=nil end
      elseif mode=="one" then rows[2]=nil; rows[3]=nil
      elseif mode=="too-many" then for i=4,514 do rows[i]=copy(rows[3]) end
      elseif mode=="hole" then rows[2]=nil
      elseif mode=="extra-index" then rows[0]=rows[1]
      elseif mode=="string-key" then rows.extra=true
      elseif mode=="metatable" then setmetatable(rows,{__index=function() error("must not invoke batch metatable") end})
      elseif mode=="row-metatable" then setmetatable(rows[2],{__index=function() error("must not invoke row metatable") end})
      elseif mode=="row-type" then rows[2]=false
      elseif mode=="missing-source" then rows[2].source_line=nil
      elseif mode=="missing-display" then rows[2].display_text=nil
      elseif mode=="missing-position" then rows[2].line_number=nil
      elseif mode=="remove" then rows[2].remove=true
      elseif mode=="style" then rows[2].style_id="notice" end
    end)
  end)
end
test("wealth adapter refuses non-table batches and APIs without raising",function()
  local _,api,a=fixture()
  for _,value in ipairs({false,1,"rows",function() end}) do
    local ok,err=a:replaceWealthOutput(value,api); eq(ok,nil); eq(type(err),"string")
    ok,err=a:replaceWealthOutput({},value); eq(ok,nil); eq(type(err),"string")
  end
  eq(a:replaceWealthOutput(nil,api),nil)
end)
local required={"getLines","getLineNumber","getColumnNumber","getBackgroundColor","moveCursor","selectSection",
  "replace","setFgColor","setBgColor","setBold","setUnderline","deselect","resetFormat"}
for _,key in ipairs(required) do
  test("wealth requires native API "..key.." before any edits",function()
    rejected(function(_,_,api) api[key]=nil end)
  end)
end
for _,key in ipairs({"getLines","getLineNumber","getColumnNumber","getBackgroundColor"}) do
  test("wealth preflight handles throwing native read "..key,function()
    rejected(function(_,_,api) api[key]=function() error("synthetic native read failure") end end)
  end)
end
for _,key in ipairs({"getLineNumber","getColumnNumber"}) do
  for index,value in ipairs(badCoordinates) do
    test("wealth preflight rejects native "..key.." coordinate "..index,function()
      rejected(function(_,_,api) api[key]=function() return value end end)
    end)
  end
end
for index,value in ipairs({-1,256,1.5,math.huge,0/0,"7",false}) do
  test("wealth preflight rejects invalid default main background "..index,function()
    rejected(function(_,_,api) api.getBackgroundColor=function() return 7,value,19 end end)
  end)
end
test("wealth preflight rejects missing default main background channels",function()
  rejected(function(_,_,api) api.getBackgroundColor=function() return 7,12 end end)
end)
for _,key in ipairs({"moveCursor","selectSection","replace","setFgColor","setBgColor","setBold","setUnderline","deselect","resetFormat"}) do
  for _,mode in ipairs({"false","nil-error","throw"}) do
    test("wealth reports native "..key.." "..mode.." and restores console state",function()
      local f,api,a,rows=fixture(); local original=api[key]; local failed=false
      api[key]=function(...)
        if not failed then
          failed=true
          if mode=="false" then return false,"synthetic failure"
          elseif mode=="nil-error" then return nil,"synthetic failure"
          else error("synthetic failure") end
        end
        return original(...)
      end
      local ok,err=a:replaceWealthOutput(rows,api)
      eq(ok,nil); eq(type(err),"string")
      eq(f.cursor,10); eq(f.column,4); eq(f.selected,nil); same(f.format,f.defaults); eq(f.forbidden,0)
      if key=="moveCursor" or key=="selectSection" or key=="replace" then eq(f.replacements,0) end
    end)
  end
end
test("wealth detects a stale row on native renderer recheck rather than silently skipping it",function()
  local f,api,a,rows=fixture(); local get=api.getLines; local reads=0
  api.getLines=function(first,last)
    reads=reads+1
    if reads==4 then f.lines[2]="Synthetic replacement chat" end
    return get(first,last)
  end
  local ok,err=a:replaceWealthOutput(rows,api)
  eq(ok,nil); assert(err:find("wealth source row changed",1,true))
  eq(f.replacements,0); eq(f.lines[2],"Synthetic replacement chat"); eq(f.cursor,10); eq(f.column,4)
end)
test("wealth reports later native failure and never touches interleaved chat",function()
  local f,api,a,rows=fixture(); local replace=api.replace; local attempts=0
  local chat=copy(f.cells[3])
  api.replace=function(value)
    attempts=attempts+1; if attempts==2 then return false,"synthetic failure" end
    return replace(value)
  end
  local ok,err=a:replaceWealthOutput(rows,api)
  eq(ok,nil); eq(type(err),"string"); eq(f.replacements,1); eq(f.lines[3],"Synthetic chat remains here")
  same(f.cells[3],chat); eq(f.cursor,10); eq(f.column,4); same(f.format,f.defaults); eq(f.forbidden,0)
end)
test("wealth reports persistent cleanup failures without masking the rendering error",function()
  local f,api,a,rows=fixture()
  api.replace=function() return false,"synthetic replace failure" end
  api.resetFormat=function() error("synthetic cleanup failure") end
  local ok,err=a:replaceWealthOutput(rows,api)
  eq(ok,nil); assert(err:find("replace failed",1,true))
  eq(f.cursor,10); eq(f.column,4); eq(f.selected,nil); eq(f.replacements,0)
end)
