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

test("colors only travel-object clauses at the end of room prose",function()
  local line="The wall is cracked. An open sinister black iron gate is here."
  local parts=assert(Colorizer.parse(line)); eq(#parts,1); eq(parts[1].kind,"portal")
  eq(line:sub(parts[1].start,parts[1].start+parts[1].length-1),"An open sinister black iron gate is here.")
  local plural=assert(Colorizer.parse("An arch and a portal to the temples are here.")); eq(plural[1].kind,"portal")
  local padded=assert(Colorizer.parse("  An open gate is here.   ")); eq(padded[1].start,3); eq(padded[1].length,21)
  eq(Colorizer.parse("A battered wooden chest is here."),nil)
  eq(Colorizer.parse("The door is old and covered in rust."),nil)
  eq(Colorizer.parse("A merchant blocking the gate is here."),nil)
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
  }
  for _,sample in ipairs(samples) do local parts=assert(Colorizer.parse(sample[1])); eq(#parts,1); eq(parts[1].kind,sample[2]); eq(sample[1]:sub(parts[1].start,parts[1].start+parts[1].length-1),sample[1]:match("^%s*(.-)%s*$")) end
  eq(Colorizer.parse("The dark hound claws at Gia!"),nil)
  eq(Colorizer.parse("The mural depicts attacks at you!"),nil)
  eq(Colorizer.parse("The fisherman casts his net across the room."),nil)
  eq(Colorizer.parse("The novice hithual cleric casts a curse at Gia!"),nil)
  eq(Colorizer.parse("The teller whispers to you about a gate."),nil)
  eq(Colorizer.parse("This area is not illuminated."),nil)
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
  assert(c:setFeature("damage",true)); eq(c:onLine("Your head takes 8 points of impact damage!"),true); eq(c:status().highlights,false)
  assert(c:setFeature("highlights",true)); eq(c:status().highlights,true); eq(c:onLine("This area is illuminated."),true)
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

test("Mudlet colorizer registration forwards every line to the conservative parser",function()
  local previousTrigger,previousLine=tempRegexTrigger,line; local pattern,callback
  tempRegexTrigger=function(value,fn) pattern=value; callback=fn; return 77 end
  local received={}; local adapter=MudletAdapter.new(); eq(adapter:addColorizerTrigger(function(value) received[#received+1]=value end),77); eq(pattern,"^.*$")
  for _,sample in ipairs({"An open grey iron gate is here.","The hound claws at you!","Your head takes 8 points of impact damage!"," ** You are fully rested."}) do line=sample; callback() end
  eq(#received,4); eq(received[1],"An open grey iron gate is here."); eq(received[4]," ** You are fully rested.")
  tempRegexTrigger,line=previousTrigger,previousLine
end)
