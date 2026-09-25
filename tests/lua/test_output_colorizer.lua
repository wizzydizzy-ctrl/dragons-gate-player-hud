local Colorizer=require("output_colorizer")
local MudletAdapter=require("mudlet_adapter")

local function fake()
  local f={next=0,triggers={},killed={},applied={}}
  function f:addColorizerTrigger(fn) self.next=self.next+1; self.triggers[self.next]=fn; return self.next end
  function f:killTrigger(id) self.killed[id]=true; self.triggers[id]=nil; return true end
  function f:applyLineColors(segments) self.applied[#self.applied+1]=segments; return true end
  return f
end

test("parses an isolated bracketed room title",function()
  local parts=assert(Colorizer.parse("[Old Cemetery.]")); eq(#parts,1); eq(parts[1].kind,"room"); eq(parts[1].start,1); eq(parts[1].length,15)
  eq(Colorizer.parse("prefix [Old Cemetery.]"),nil); eq(Colorizer.parse("[broken] trailing"),nil)
end)

test("parses exits label and only known direction words",function()
  local line="Obvious exits: north northeast east southeast south southwest west northwest up down out."
  local parts=assert(Colorizer.parse(line)); eq(#parts,12); eq(parts[1].kind,"label"); eq(line:sub(parts[1].start,parts[1].start+parts[1].length-1),"Obvious exits:")
  for index=2,#parts do eq(parts[index].kind,"direction") end
  local paths=assert(Colorizer.parse("  Obvious paths: north east west.")); eq(#paths,4); eq(paths[1].start,3)
  eq(Colorizer.parse("The obvious exits: north."),nil)
end)

test("preserves non-direction text after the owned label",function()
  local line="Obvious exits: north through a gate and west."
  local parts=assert(Colorizer.parse(line)); eq(#parts,3)
  eq(line:sub(parts[2].start,parts[2].start+parts[2].length-1),"north")
  eq(line:sub(parts[3].start,parts[3].start+parts[3].length-1),"west")
end)

test("accepts case spacing and abbreviated directions",function()
  local line="  OBVIOUS paths : N ne in OUT.  "
  local parts=assert(Colorizer.parse(line)); eq(#parts,5)
  eq(line:sub(parts[1].start,parts[1].start+parts[1].length-1),"OBVIOUS paths :")
  for index=2,#parts do eq(parts[index].kind,"direction") end
end)

test("colors exact gold silver gp and sp words",function()
  local line="Gold 12gp, Silver 4sp; golden and spill stay plain."
  local parts=assert(Colorizer.parse(line)); eq(#parts,4)
  eq(parts[1].kind,"gold"); eq(parts[2].kind,"gold"); eq(parts[3].kind,"silver"); eq(parts[4].kind,"silver")
end)

test("colors every race and class occurrence with longest names taking precedence",function()
  local line="A Monitanian Fighter greets a Human Cleric and a Fir Elf Rune Mage."
  local parts=assert(Colorizer.parse(line)); eq(#parts,6)
  local words={}; for _,part in ipairs(parts) do words[#words+1]={line:sub(part.start,part.start+part.length-1),part.kind,part.color} end
  eq(words[1][1],"Monitanian"); eq(words[1][2],"races"); eq(words[1][3][1],102); eq(words[1][3][2],204); eq(words[1][3][3],102)
  eq(words[2][1],"Fighter"); eq(words[2][2],"classes")
  eq(words[3][1],"Human"); eq(words[3][2],"races"); eq(words[4][1],"Cleric"); eq(words[4][2],"classes")
  eq(words[5][1],"Fir Elf"); eq(words[5][2],"races"); eq(words[6][1],"Rune Mage"); eq(words[6][2],"classes")
end)

test("race and class toggles independently filter all positional matches",function()
  local f=fake(); local c=Colorizer.new(f,true,{races_enabled=false,classes_enabled=true}); assert(c:start())
  assert(c:onLine("Monitanian Fighter and Human Cleric")); eq(#f.applied[1],2); eq(f.applied[1][1].kind,"classes"); eq(f.applied[1][2].kind,"classes")
  assert(c:setFeature("races",true)); eq(c:setFeature("classes",false),false); assert(c:onLine("Monitanian Fighter and Human Cleric")); eq(#f.applied[2],2); eq(f.applied[2][1].kind,"races"); eq(f.applied[2][2].kind,"races"); c:shutdown()
end)

test("colors travel objects without swallowing surrounding prose",function()
  local line="The wall is cracked. An open sinister black iron gate is here."
  local parts=assert(Colorizer.parse(line)); eq(#parts,2); eq(parts[1].kind,"portal")
  eq(line:sub(parts[1].start,parts[1].start+parts[1].length-1),"An open sinister black iron gate")
  local plural=assert(Colorizer.parse("An arch and a portal to the temples are here.")); eq(plural[1].kind,"portal")
  local padded=assert(Colorizer.parse("  An open gate is here.   ")); eq(padded[1].start,3); eq(padded[1].length,12)
  eq(Colorizer.parse("The door is old and covered in rust."),nil)
end)

test("room objects and terminal presence phrases use distinct exact spans",function()
  for _,sample in ipairs({
    {"The wall is cracked. An open iron gate is here.","is here",{{"portal","An open iron gate"}}},
    {"An arch and a portal to the temples are here.","are here",{{"portal","An arch"},{"portal","a portal to the temples"}}},
    {"  A SHOP IS HERE.  ","IS HERE",{{"portal","A SHOP"}}},
    {"A shop is here","is here",{{"portal","A shop"}}},
    {"A battered wooden chest is here.","is here",{{"presence","A battered wooden chest"}}},
    {"A fountain and a torch are here.","are here",{{"presence","A fountain"},{"presence","a torch"}}},
    {"A merchant blocking the gate is here.","is here",{{"presence","A merchant blocking the gate"}}},
  }) do
    local line,phrase,subjects=sample[1],sample[2],sample[3]
    local first=assert(line:find(phrase,1,true))
    local parts=assert(Colorizer.parse(line))
    eq(#parts,#subjects+1)
    for index,wanted in ipairs(subjects) do
      local part=parts[index]
      eq(part.kind,wanted[1]); eq(part.start,assert(line:find(wanted[2],1,true))); eq(part.length,#wanted[2])
      assert(part.start+part.length<=first)
      if part.kind=="presence" then eq(table.concat(assert(part.color),","),"136,190,153")
      else eq(table.concat(assert(part.color),","),"55,190,200") end
    end
    local ending=parts[#parts]
    eq(ending.kind,"presence_phrase"); eq(ending.start,first); eq(ending.length,#phrase)
    eq(table.concat(assert(ending.color),","),"255,220,90")
  end
end)

test("presence coloring excludes plain prose chat and nonterminal mentions",function()
  local f=fake(); local c=Colorizer.new(f,true); assert(c:start())
  for _,line in ipairs({
    "The phrase is here for illustration.",
    "I think the gate is here.",
    'Someone says, "A gate is here."',
    "You say, A gate is here.",
    "[CHAT] Someone: A shop is here.",
    "A sign reads: A gate is here.",
    "A gate is here. trailing prose",
    "is here.", "are here.",
  }) do
    eq(Colorizer.parse(line),nil)
    eq(c:onLine(line),false)
  end
  eq(#f.applied,0); c:shutdown()
end)

test("presence subjects and here words are independently customizable and toggleable",function()
  local f=fake()
  local c=Colorizer.new(f,true,{styles={
    presence={foreground="#123456"},
    presence_phrase={foreground="#FEDCBA"},
  }})
  assert(c:start())
  assert(c:onLine("A wooden chest is here.",100))
  eq(f.applied[1][1].kind,"presence")
  eq(table.concat(f.applied[1][1].color,","),"18,52,86")
  eq(f.applied[1][2].kind,"presence_phrase")
  eq(table.concat(f.applied[1][2].color,","),"254,220,186")
  eq(c:setFeature("presence",false),false)
  eq(c:onLine("A wooden chest is here.",101),false)
  assert(c:onLine("An open gate is here.",102))
  eq(#f.applied[2],1); eq(f.applied[2][1].kind,"portal")
  c:shutdown()
end)

test("classifies restrained combat danger recovery upkeep spell and discovery lines",function()
  local samples={
    {"The unholy acolyte kicks at you!","attack"},
    {"The dark hound claws towards you!","attack"},
    {"The dark hound bites you!","attack"},
    {"Your head takes 8 points of impact damage!","damage"},
    {"The 2nd fighting puppet blocks you from leaving!","danger"},
    {"You cannot move in that direction.","danger"},
    {"You cannot move more than 6 UDs per turn!","danger"},
    {" ** You are fully rested.","recovery"},
    {"** You are fully healed.","recovery"},
    {"You expend 1 fatigue keeping up the dragon dart on the ork.","upkeep"},
    {"The novice hithual cleric quickly casts his gaze across the room.","spell"},
    {"The novice hithual cleric casts a curse at you!","spell"},
    {"You have discovered a secret path!","discovery"},
    {"This area is illuminated.","illumination"},
    {"This room is illuminated.","illumination"},
  }
  for _,sample in ipairs(samples) do
    local parts=assert(Colorizer.parse(sample[1])); local found
    for _,part in ipairs(parts) do if part.kind==sample[2] then found=part; break end end
    assert(found); eq(sample[1]:sub(found.start,found.start+found.length-1),sample[1]:match("^%s*(.-)%s*$"))
  end
  eq(Colorizer.parse("The dark hound claws at Gia!"),nil)
  eq(Colorizer.parse("The mural depicts attacks at you!"),nil)
  eq(Colorizer.parse("The fisherman casts his net across the room."),nil)
  local untargeted=assert(Colorizer.parse("The novice hithual cleric casts a curse at Gia!")); eq(#untargeted,2); eq(untargeted[1].kind,"races"); eq(untargeted[2].kind,"classes")
  eq(Colorizer.parse("The teller whispers to you about a gate."),nil)
  local dark=assert(Colorizer.parse("This area is not illuminated.")); eq(dark[1].kind,"darkness"); eq(dark[1].color[1],105)
  eq(assert(Colorizer.parse("This room is not illuminated."))[1].kind,"darkness")
end)
test("formats player and staff version notes as prominent important notices",function()
  for _,line in ipairs({"(There are new version notes and gm version notes.)","There  are\tnew version notes and GM version notes\r"," ( THERE ARE NEW VERSION NOTES ) "}) do
    local part=assert(Colorizer.parse(line))[1]; eq(part.kind,"notice"); eq(part.bold,true); eq(part.underline,true); eq(part.color[1],255); eq(part.background[1],80)
    assert(part.display_text:find("IMPORTANT %- PLEASE READ"))
  end
  eq(Colorizer.parse("Display notices and version notes."),nil)
end)
test("Mudlet adapter aborts notice formatting when selection fails",function()
  local formatted=0; local api={selectSection=function() return false end,setFgColor=function() formatted=formatted+1 end,deselect=function() end}
  local ok,err=MudletAdapter.new():applyLineColors(assert(Colorizer.parse("(There are new version notes.)")),api); eq(ok,nil); assert(err:find("could not select",1,true)); eq(formatted,0)
end)

test("special lines retain independently filterable currency segments",function()
  local parts=assert(Colorizer.parse("You have discovered 10 gold!")); eq(#parts,2); eq(parts[1].kind,"discovery"); eq(parts[2].kind,"gold")
  local f=fake(); local c=Colorizer.new(f,true,{highlights_enabled=false,currency_enabled=true}); assert(c:start())
  assert(c:onLine("You have discovered 10 gold!")); eq(#f.applied[1],1); eq(f.applied[1][1].kind,"gold"); c:shutdown()
end)

test("optional controller owns one trigger and cleans it up",function()
  local f=fake(); local c=Colorizer.new(f,false); assert(c:start()); eq(c:onLine("[Old Cemetery.]"),false); eq(#f.applied,0)
  eq(c:toggle(),true); eq(c:onLine("[Old Cemetery.]"),true); eq(#f.applied,1); eq(c:status().enabled,true)
  local id=c.trigger; assert(c:shutdown()); eq(f.killed[id],true); eq(c:status().started,false); eq(c:onLine("[Old Cemetery.]"),false)
end)

test("controller contains adapter coloring failures",function()
  local f=fake(); function f:applyLineColors() return nil,"selection failed" end
  local c=Colorizer.new(f,true); assert(c:start()); local ok,err=c:onLine("Obvious paths: east west."); eq(ok,nil); eq(err,"selection failed"); c:shutdown()
end)

test("feature toggles independently filter owned color ranges",function()
  local f=fake(); local c=Colorizer.new(f,true,{room_enabled=false,exits_enabled=true,currency_enabled=false}); assert(c:start())
  eq(c:onLine("[Old Cemetery.]"),false); eq(c:onLine("Gold 2gp"),false); eq(c:onLine("Obvious exits: north west."),true)
  assert(c:setFeature("currency",true)); eq(c:onLine("Gold 2gp"),true); local result,err=c:setFeature("unknown",true); eq(result,nil); eq(err,"unknown color feature")
  c:shutdown()
end)

test("legacy highlight group and individual feature toggles coexist",function()
  local f=fake(); local c=Colorizer.new(f,true,{highlights_enabled=false}); assert(c:start())
  eq(c:onLine("Your head takes 8 points of impact damage!"),false)
  eq(c:onLine("This area is illuminated."),false)
  eq(c:onLine("This area is not illuminated."),false)
  assert(c:setFeature("damage",true)); eq(c:onLine("Your head takes 8 points of impact damage!"),true); eq(c:status().highlights,false)
  assert(c:setFeature("highlights",true)); eq(c:status().highlights,true); eq(c:onLine("This area is illuminated."),true); eq(c:onLine("This area is not illuminated."),true)
  c:shutdown()
end)

test("Mudlet adapter changes only selected foreground ranges",function()
  local selected,colors,deselected={},{},0
  local api={
    selectSection=function(start,length) selected[#selected+1]={start,length} end,
    setFgColor=function(r,g,b) colors[#colors+1]={r,g,b} end,
    deselect=function() deselected=deselected+1 end,
  }
  local segments=assert(Colorizer.parse("Obvious paths: north east west."))
  assert(MudletAdapter.new():applyLineColors(segments,api)); eq(#selected,4); eq(selected[1][1],0); eq(selected[1][2],14); eq(selected[2][1],15); eq(selected[2][2],5); eq(#colors,4); eq(deselected,1)
end)
test("Mudlet adapter applies prominent notice styling and replacement",function()
  local selected,replaced,fg,bg,bold,underline={}; local api={
    selectSection=function(start,length) selected[#selected+1]={start,length} end,replace=function(value) replaced=value end,
    setFgColor=function(...) fg={...} end,setBgColor=function(...) bg={...} end,setBold=function(value) bold=value end,setUnderline=function(value) underline=value end,deselect=function() end,
  }
  assert(MudletAdapter.new():applyLineColors(assert(Colorizer.parse("(There are new version notes and gm version notes.)")),api))
  assert(replaced:find("IMPORTANT %- PLEASE READ")); eq(fg[1],255); eq(bg[1],80); eq(bold,true); eq(underline,true); eq(#selected,2)
end)

test("Mudlet colorizer registration forwards every line to the conservative parser",function()
  local previousTrigger,previousLine=tempRegexTrigger,line; local pattern,callback
  tempRegexTrigger=function(value,fn) pattern=value; callback=fn; return 77 end
  local received={}; local adapter=MudletAdapter.new(); eq(adapter:addColorizerTrigger(function(value) received[#received+1]=value end),77); eq(pattern,"^.*$")
  for _,sample in ipairs({"An open grey iron gate is here.","The hound claws at you!","Your head takes 8 points of impact damage!"," ** You are fully rested."}) do line=sample; callback() end
  eq(#received,4); eq(received[1],"An open grey iron gate is here."); eq(received[4]," ** You are fully rested.")
  tempRegexTrigger,line=previousTrigger,previousLine
end)
test("controller applies independently editable text styles without changing adjacent categories",function()
  local f=fake(); local c=Colorizer.new(f,true,{styles={
    direction={foreground="#ABCDEF",background="#112233",bold=true,underline=true},
    ["race:human"]={foreground="#010203"},
    ["class:fighter"]={enabled=false},
    notice={foreground="#AABBCC",background=false,bold=false,underline=false},
  }}); assert(c:start())
  assert(c:onLine("Obvious paths: north east."))
  eq(f.applied[1][1].kind,"label"); eq(f.applied[1][2].color[1],171)
  eq(f.applied[1][2].background[2],34); eq(f.applied[1][2].bold,true); eq(f.applied[1][2].underline,true)
  assert(c:onLine("Human Fighter and Human Cleric"))
  eq(#f.applied[2],3); eq(f.applied[2][1].color[1],1); eq(f.applied[2][2].color[3],3)
  assert(c:onLine("(There are new version notes.)"))
  eq(f.applied[3][1].background,nil); eq(f.applied[3][1].bold,false); eq(f.applied[3][1].underline,false)
  c:shutdown()
end)

test("wrapped travel matches use captured console rows even when other triggers insert output",function()
  local f=fake(); local c=Colorizer.new(f,true); assert(c:start())
  eq(c:onLine("A dark hole and a sputtering smoky torch are",100),false)
  assert(c:onLine("here.",107))
  local segment=f.applied[1][1]; eq(segment.line_number,100); eq(segment.source_line,"A dark hole and a sputtering smoky torch are")
  eq(segment.source_line:sub(segment.start,segment.start+segment.length-1),"A dark hole")
  c:setEnabled(false); c:setEnabled(true)
  eq(c:onLine("here.",108),false)
  c:shutdown()
end)

test("wrapped travel without trustworthy old row numbers is not applied to the current line",function()
  local f=fake(); local c=Colorizer.new(f,true); assert(c:start())
  c:onLine("A dark hole and a sputtering smoky torch are")
  eq(c:onLine("here."),false); eq(#f.applied,0); c:shutdown()
end)

test("ANSI and Unicode retain exact travel byte spans for safe character selection",function()
  local f=fake(); local c=Colorizer.new(f,true); assert(c:start())
  assert(c:onLine("\27[36mCafé. An exit is here.\27[0m",20))
  local segment=f.applied[1][1]; eq(segment.source_line,"Café. An exit is here.")
  local selected
  local api={getLineNumber=function() return 20 end,getColumnNumber=function() return 0 end,
    getLines=function() return {"Café. An exit is here."} end,
    selectSection=function(start,length) selected={start,length}; return true end,
    setFgColor=function() end,deselect=function() end}
  assert(MudletAdapter.new():applyLineColors({segment},api)); eq(selected[1],6); eq(selected[2],7)
  c:shutdown()
end)

test("prior-line coloring verifies source text and restores the native cursor",function()
  local cursor,selected,moves=107,{},{}
  local lines={[100]="A dark hole and a torch are",[107]="here."}
  local api={getLineNumber=function() return cursor end,getColumnNumber=function() return 3 end,
    getLines=function(first) return {lines[first]} end,
    moveCursor=function(x,y) moves[#moves+1]={x,y}; cursor=y; return true end,
    selectSection=function(start,length) selected[#selected+1]={cursor,start,length}; return true end,
    setFgColor=function() end,deselect=function() end}
  local part={start=1,length=11,color={1,2,3},line_number=100,source_line=lines[100]}
  assert(MudletAdapter.new():applyLineColors({part},api)); eq(#selected,1); eq(selected[1][1],100); eq(cursor,107)
  eq(moves[#moves][1],3)
  lines[100]="Another trigger replaced this line"
  assert(MudletAdapter.new():applyLineColors({part},api)); eq(#selected,1); eq(cursor,107)
  lines[100]=part.source_line; api.setFgColor=function() error("native failure") end
  local ok,err=MudletAdapter.new():applyLineColors({part},api); eq(ok,nil); assert(err:find("native failure",1,true)); eq(cursor,107)
end)

test("emoji spans use UTF-16 units after ANSI stripping",function()
  local samples={
    {"🌟. An exit is here.",4,7},
    {"🌟🌙. An exit is here.",6,7},
    {"Café’s 🌟. An exit is here.",11,7},
    {"🌟. A glowing 🌙 portal is here.",4,19},
    {"A 👩‍🚀 portal is here.",0,14},
  }
  for _,sample in ipairs(samples) do
    local f=fake(); local c=Colorizer.new(f,true); assert(c:start())
    assert(c:onLine("\27[36m"..sample[1].."\27[0m",20))
    local segment=f.applied[1][1]; eq(segment.source_line,sample[1])
    local selected
    local api={getLineNumber=function() return 20 end,getColumnNumber=function() return 0 end,
      getLines=function(first,last) eq(first,20); eq(last,21); return {sample[1]} end,
      selectSection=function(start,length) selected={start,length}; return true end,
      setFgColor=function() end,deselect=function() end}
    assert(MudletAdapter.new():applyLineColors({segment},api))
    eq(selected[1],sample[2]); eq(selected[2],sample[3])
    c:shutdown()
  end
end)

test("emoji spans on earlier console rows preserve UTF-16 offsets and the cursor",function()
  local f=fake(); local c=Colorizer.new(f,true); assert(c:start())
  local source="🌟. A glowing 🌙 portal"
  eq(c:onLine(source,100),false); assert(c:onLine("is here.",107))
  local cursor,column,selected=107,4,nil
  local api={getLineNumber=function() return cursor end,getColumnNumber=function() return column end,
    getLines=function(first,last) eq(first,100); eq(last,101); return {source} end,
    moveCursor=function(x,y) column,cursor=x,y; return true end,
    selectSection=function(start,length) selected={cursor,start,length}; return true end,
    setFgColor=function() end,deselect=function() end}
  local earlier={}
  for _,part in ipairs(f.applied[1]) do if part.line_number==100 then earlier[#earlier+1]=part end end
  eq(#earlier,1)
  assert(MudletAdapter.new():applyLineColors(earlier,api))
  eq(selected[1],100); eq(selected[2],4); eq(selected[3],19)
  eq(cursor,107); eq(column,4); c:shutdown()
end)

test("replacement text is reselected using UTF-16 start and length",function()
  local source="🌟. A portal is here."
  local selected,replaced={},nil
  local api={getLineNumber=function() return 20 end,getColumnNumber=function() return 0 end,
    getLines=function() return {source} end,
    selectSection=function(start,length) selected[#selected+1]={start,length}; return true end,
    replace=function(text) replaced=text end,setFgColor=function() end,deselect=function() end}
  local item={start=assert(source:find("A portal",1,true)),length=8,source_line=source,
    line_number=20,color={1,2,3},display_text="✨ New 🌟"}
  assert(MudletAdapter.new():applyLineColors({item},api))
  eq(replaced,"✨ New 🌟"); eq(#selected,2)
  eq(selected[1][1],4); eq(selected[1][2],8)
  eq(selected[2][1],4); eq(selected[2][2],8)
end)

-- Exercise controller ordering through the real adapter, keeping the final
-- foreground of every selected character as well as the native paint order.
local function colorSurface(lines)
  local f=fake(); f.cursor=100; f.column=3; f.painted={}; f.paintCalls={}
  local selection
  local api={getLineNumber=function() return f.cursor end,getColumnNumber=function() return f.column end,
    getLines=function(first,last) eq(last,first+1); return {lines[first]} end,
    moveCursor=function(x,y) f.column,f.cursor=x,y; return true end,
    selectSection=function(start,length)
      assert(lines[f.cursor]); assert(start>=0 and start+length<=#lines[f.cursor])
      selection={row=f.cursor,start=start,length=length}; return true
    end,
    setFgColor=function(r,g,b)
      assert(selection); local color=table.concat({r,g,b},",")
      f.paintCalls[#f.paintCalls+1]={row=selection.row,start=selection.start,length=selection.length,color=color}
      f.painted[selection.row]=f.painted[selection.row] or {}
      for index=selection.start+1,selection.start+selection.length do f.painted[selection.row][index]=color end
    end,
    deselect=function() selection=nil end}
  function f:applyLineColors(segments)
    self.applied[#self.applied+1]=segments
    return MudletAdapter.new():applyLineColors(segments,api)
  end
  function f:assertColor(row,text,expected)
    local first=assert(lines[row]:find(text,1,true))
    for index=first,first+#text-1 do eq((self.painted[row] or {})[index],expected) end
  end
  return f
end

local overlapStyles={styles={
  portal={foreground="#112233"},gold={foreground="#DDEEFF"},silver={foreground="#445566"},
  ["race:human"]={foreground="#778899"},["class:cleric"]={foreground="#AABBCC"},
}}

test("ordinary room objects paint muted subjects and a brighter terminal phrase",function()
  local lines={[100]="A battered wooden chest is here.",[101]="A fountain and a torch are here."}
  local f=colorSurface(lines); local c=Colorizer.new(f,true); assert(c:start())
  for _,sample in ipairs({
    {100,{"A battered wooden chest"},"is here"},
    {101,{"A fountain","a torch"},"are here"},
  }) do
    local row,subjects,phrase=sample[1],sample[2],sample[3]
    f.cursor=row
    assert(c:onLine(lines[row],row))
    local expected={}
    for _,subject in ipairs(subjects) do
      local first=assert(lines[row]:find(subject,1,true))
      for index=first,first+#subject-1 do expected[index]="136,190,153" end
    end
    local first=assert(lines[row]:find(phrase,1,true))
    for index=first,first+#phrase-1 do expected[index]="255,220,90" end
    for index=1,#lines[row] do eq((f.painted[row] or {})[index],expected[index]) end
  end
  c:shutdown()
end)

test("current-row travel color is painted before intersecting currency race and class styles",function()
  local prefix="A gold coin rests nearby. "
  local subject="A silver gate to the Human Cleric temple"
  local lines={[100]=prefix..subject.." is here."}
  local f=colorSurface(lines); local c=Colorizer.new(f,true,overlapStyles); assert(c:start())
  assert(c:onLine(lines[100],100))
  eq(#f.paintCalls,6); eq(f.applied[1][1].kind,"portal")
  eq(f.paintCalls[1].row,100); eq(f.paintCalls[1].start,#prefix)
  eq(f.paintCalls[1].length,#subject); eq(f.paintCalls[1].color,"17,34,51")
  f:assertColor(100,"gate","17,34,51")
  f:assertColor(100,"gold","221,238,255")
  f:assertColor(100,"silver","68,85,102")
  f:assertColor(100,"Human","119,136,153")
  f:assertColor(100,"Cleric","170,187,204")
  local suffixColor=(f.painted[100] or {})[assert(lines[100]:find("is here",1,true))]
  assert(suffixColor and suffixColor~="17,34,51")
  f:assertColor(100,"is here",suffixColor)
  eq((f.painted[100] or {})[#lines[100]],nil)
  eq(f.cursor,100); eq(f.column,3); c:shutdown()
end)

test("wrapped travel replays only intersecting prior-row overlays after all broad spans",function()
  local prefix="A gold coin rests nearby. "
  local subject="A silver gate to the Human Cleric temple"
  local lines={[100]=prefix..subject.." and",[107]="a silver door are here."}
  local f=colorSurface(lines); local c=Colorizer.new(f,true,overlapStyles); assert(c:start())
  assert(c:onLine(lines[100],100))
  eq(#f.applied[1],4) -- Initial currency/race/class colors precede travel confirmation.
  f.paintCalls={}; f.cursor=107; f.column=4
  assert(c:onLine(lines[107],107))
  local parts=f.applied[2]; eq(#parts,7); eq(#f.paintCalls,7)
  eq(parts[1].kind,"portal"); eq(parts[1].line_number,100)
  eq(parts[2].kind,"portal"); eq(parts[2].line_number,107)
  eq(f.paintCalls[1].start,#prefix); eq(f.paintCalls[1].length,#subject)
  eq(f.paintCalls[1].color,"17,34,51"); eq(f.paintCalls[2].color,"17,34,51")
  local replayed={}
  for index=3,#parts do
    local part=parts[index]; assert(part.kind~="portal")
    if part.line_number==100 then
      assert(part.kind=="silver" or part.kind=="races" or part.kind=="classes")
      eq(part.source_line,lines[100]); replayed[part.kind]=(replayed[part.kind] or 0)+1
    end
  end
  eq(replayed.silver,1); eq(replayed.races,1); eq(replayed.classes,1)
  -- The gold outside the travel phrase retains its first-pass color without replay.
  f:assertColor(100,"gold","221,238,255")
  f:assertColor(100,"gate","17,34,51")
  f:assertColor(100,"silver","68,85,102")
  f:assertColor(100,"Human","119,136,153")
  f:assertColor(100,"Cleric","170,187,204")
  f:assertColor(100,"and",nil)
  f:assertColor(107,"door","17,34,51")
  f:assertColor(107,"silver","68,85,102")
  local suffixColor=(f.painted[107] or {})[assert(lines[107]:find("are here",1,true))]
  assert(suffixColor and suffixColor~="17,34,51")
  f:assertColor(107,"are here",suffixColor)
  eq((f.painted[107] or {})[#lines[107]],nil)
  eq(f.cursor,107); eq(f.column,4); c:shutdown()
end)
