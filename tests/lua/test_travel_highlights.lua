local Travel=require("travel_highlights")

local function phrases(line,expected)
  local parts=Travel.parse(line)
  if #expected==0 then eq(parts,nil); return end
  assert(parts,"missing travel phrase: "..line); eq(#parts,#expected)
  local previous=0
  for index,part in ipairs(parts) do
    eq(part.kind,"portal"); eq(part.line_offset,nil)
    assert(part.start>previous); assert(part.length>0)
    eq(line:sub(part.start,part.start+part.length-1),expected[index])
    previous=part.start+part.length-1
  end
end

local function wrapped(lines,expected)
  local parser=Travel.new()
  for index=1,#lines-1 do eq(parser:onLine(lines[index]),nil) end
  local parts=parser:onLine(lines[#lines])
  if #expected==0 then eq(parts,nil); return parser end
  assert(parts,"missing wrapped travel phrase"); eq(#parts,#expected)
  for index,part in ipairs(parts) do
    local wanted=expected[index]
    local offset=part.line_offset or 0
    eq(offset,wanted[1]); eq(part.kind,"portal")
    eq(part.source_line,lines[#lines+offset])
    eq(part.source_line:sub(part.start,part.start+part.length-1),wanted[2])
    assert(offset<=0 and offset>=-3)
  end
  eq(#parser.lines,0); eq(parser.bytes,0)
  return parser
end

test("travel phrases exclude the presence suffix and preceding prose",function()
  phrases("The wall is cracked. An open iron gate is here.",{"An open iron gate"})
  phrases("  An open gate is here.   ",{"An open gate"})
  phrases("\tA SHOP\tIS\tHERE. \r",{"A SHOP"})
  phrases("A shop is here",{"A shop"})
end)

test("travel allows SHOP instructions before a confirmed exit",function()
  phrases("SHOP gives you a list of available options, with HAGGLE and UNLOCK at the top of the list.  An exit is here.",{"An exit"})
  phrases("You can learn when you can enter the shop. An open gate is here.",{"An open gate"})
end)

test("travel allows balanced Good and Dark prose quotes before a wrapped gate",function()
  wrapped({'broken up into two teams, the "Good" team and the "Dark" team. Whose team are you on? An open black obsidian gate to the arena and a flaming black iron lamp post',
    "are here."},{{-1,"An open black obsidian gate to the arena"}})
end)

test("travel preserves final objects after descriptive prose and wrapped quotes",function()
  phrases("You have arrived at a crossroads. An arch is here.",{"An arch"})
  wrapped({'You notice a list titled "Hold Back - Not Ready',
    'for the city" on the desk. You notice your name is absent. An embossed chair, a steelwood desk, a',
    'tall oak chair, an arch to the classroom, and an open ivory door are here.'},
    {{0,"an arch to the classroom"},{0,"an open ivory door"}})
  wrapped({"The academy is where you can see who tells the", "tallest tale. A store, a fountain, and a tavern are here."},
    {{0,"A store"},{0,"a tavern"}})
end)

test("travel recognizes shops and established transition nouns",function()
  for _,noun in ipairs({"shop","store","pawnshop","tavern","hole","door","doors",
    "doorway","gate","gates","arch","arches","archway","portal","portals",
    "staircase","stairway","stairs","ladder","ladders","trapdoor","bridge",
    "tunnel","passage","passageway","entrance","exit","exits","path","paths"}) do
    phrases("The old "..noun.." is here.",{"The old "..noun})
  end
end)

test("travel includes confirmed dirt paths and excludes narrative paths",function()
  phrases("A dirt path is here.",{"A dirt path"})
  phrases("A flaming black iron lamp post and a dirt path are here.",{"a dirt path"})
  phrases("Some winding paths are here.",{"Some winding paths"})
  phrases("The dirt path winds between the trees.",{})
  phrases("You follow a dirt path. A gate is here.",{})
  phrases("A merchant guarding the path is here.",{})
  phrases("A sign pointing to the path is here.",{})
  wrapped({"A flaming lamp post and a dirt", "path are here."},{{-1,"a dirt"},{0,"path"}})
end)

-- Generic room-object regressions distilled from the supplied log. No account,
-- character, chat, address, or raw log fixtures are retained.
test("travel separates shops from fountain and lamp in a mixed room list",function()
  phrases("A store, a pawnshop, a tavern, a fountain, and a burning lamp post are here.",
    {"A store","a pawnshop","a tavern"})
end)

test("travel separates gate and exit from dropped equipment",function()
  phrases("An open iron gate, a broken leather armor, and a spent wooden torch are here.",{"An open iron gate"})
  phrases("An exit and a broken tin lockpick are here.",{"An exit"})
  phrases("A torch, a fountain, and an exit are here.",{"an exit"})
  phrases("A torch, an exit, and a shop are here.",{"an exit","a shop"})
end)

test("travel handles holes and later subjects after unrelated furniture",function()
  phrases("A wooden sign and a dark hole are here.",{"a dark hole"})
  phrases("A dark hole, an explorer's lantern, and a sign are here.",{"A dark hole"})
  phrases("Some tables and chairs and an exit are here.",{"an exit"})
  phrases("A tall oak chair, an arch to the classroom, and an open ivory door are here.",
    {"an arch to the classroom","an open ivory door"})
end)

test("travel keeps destination modifiers and adjective conjunctions",function()
  phrases("An arch and a portal to the temples are here.",{"An arch","a portal to the temples"})
  phrases("A hole in the ground and a door leading to the cellar are here.",
    {"A hole in the ground","a door leading to the cellar"})
  phrases("A black and white door is here.",{"A black and white door"})
  phrases("Some stairs and ladders are here.",{"Some stairs","ladders"})
end)

test("travel does not classify mentions inside other subjects",function()
  for _,line in ipairs({
    "A merchant guarding the gate is here.","A merchant blocking the gate is here.",
    "A merchant beside the gate is here.","A merchant near the shop is here.",
    "A torch from the shop is here.","A sign for the tavern is here.",
    "A picture of a gate is here.","A shop owner is here.","A gate key is here.",
    "A doorway-shaped chest is here.","A shopkeeper is here.",
    "The door is old and covered in rust.","A battered wooden chest is here.",
    "A fountain and a torch are here.","A merchant opens the gate and is here.",
  }) do phrases(line,{}) end
end)

test("travel ignores quoted chat commands and movement narratives",function()
  for _,line in ipairs({
    'You say, "A gate is here."',"You say, A gate is here.",
    'Someone says, "A gate is here."',"Someone sends: A gate is here.",
    '[CHAT] Someone: A shop is here.',"'A shop is here.'",
    'A sign reads "A portal is here."',"A sign reads: A gate is here.",
    "You walk north. A shop is here.","A traveler walks east. A gate is here.",
    "shop", "shop list", "buy shop", "enter shop", "look shop",
    "look shop. A gate is here.","[A gate is here.]","> A gate is here.",
    "[100/100]", "A gate is here. trailing prose", "‘A shop is here.’",
    "A traveler says hello. A gate is here.",
  }) do phrases(line,{}) end
end)

test("travel preserves literal Unicode apostrophes and byte positions",function()
  local line="The café is quiet. A trader’s shop and a dark hole are here."
  phrases(line,{"A trader’s shop","a dark hole"})
  local parts=Travel.parse(line)
  eq(parts[1].start,line:find("A trader",1,true))
  eq(parts[2].start,line:find("a dark hole",1,true))
  phrases("A trader's shop is here.",{"A trader's shop"})
  phrases("The café is quiet. A trader’s shop is here.",{ "A trader’s shop" })
  phrases("Someone says, “A trader’s shop is here.”",{})
end)

test("travel rejects invalid types controls and oversized input",function()
  eq(Travel.parse(nil),nil); eq(Travel.parse(false),nil); eq(Travel.parse({}),nil)
  for _,line in ipairs({"","   ","\27[31mA gate is here.","A gate\0 is here.",
    "A gate\nis here.","A gate\ris here.",string.rep(" ",2049).."A gate is here."}) do phrases(line,{}) end
end)

test("travel waits for presence confirmation across a wrapped adjective",function()
  wrapped({"The wall is cracked. A mysterious shadowy  "," portal is here."},
    {{-1,"A mysterious shadowy"},{0,"portal"}})
  wrapped({"An open", "crumbling iron gate is here."},{{-1,"An open"},{0,"crumbling iron gate"}})
end)

test("travel handles split list objects and split destination modifiers",function()
  wrapped({"An arch and an", "open ivory door are here."},
    {{-1,"An arch"},{-1,"an"},{0,"open ivory door"}})
  wrapped({"An arch, a portal", "to the temples, and a burning lamp post are here."},
    {{-1,"An arch"},{-1,"a portal"},{0,"to the temples"}})
  wrapped({"An arch, a portal to the temples,", "and a burning lamp post are here."},
    {{-1,"An arch"},{-1,"a portal to the temples"}})
end)

test("travel supports four observed lines and split presence words",function()
  wrapped({"An arch,", "a portal to", "the temples, and a torch", "are here."},
    {{-3,"An arch"},{-2,"a portal to"},{-1,"the temples"}})
  wrapped({"A shop", "is", "here."},{{-2,"A shop"}})
  wrapped({"A gate and a shop are", "here."},{{-1,"A gate"},{-1,"a shop"}})
end)

test("travel emits source text on current and previous server lines",function()
  local line="  A trader’s shop is here."
  local parser=Travel.new(); local parts=assert(parser:onLine(line))
  eq(parts[1].source_line,line); eq(parts[1].line_offset,nil); eq(parts[1].start,3)
  wrapped({"A trader’s", "shop and a dark hole are here."},
    {{-1,"A trader’s"},{0,"shop"},{0,"a dark hole"}})
end)

test("travel resets on prompts chat room titles blanks and unrelated output",function()
  for _,stop in ipairs({"", "   ", ">", "100h 50m>", "[A different room.]",
    "Obvious exits: north.","Inventory:","You walk north.","A breeze passes.",
    'Someone says, "hello"',"You say hello.","[CHAT] Someone: hello", "shop list"}) do
    local parser=Travel.new(); eq(parser:onLine("A portal to"),nil)
    eq(parser:onLine(stop),nil); eq(parser:onLine("the temples is here."),nil)
    local parts=assert(parser:onLine("A shop is here.")); eq(parts[1].line_offset,nil)
  end
end)

test("travel does not join independent subjects or reuse completed clauses",function()
  wrapped({"A gate", "A torch is here."},{})
  local parser=wrapped({"A gate", "is here."},{{-1,"A gate"}})
  eq(parser:onLine("is here."),nil)
  eq(parser:onLine("A gate"),nil); parser:reset(); eq(parser:onLine("is here."),nil)
  eq(parser:onLine("A gate"),nil); eq(parser:onLine(nil),nil); eq(parser:onLine("is here."),nil)
end)

test("travel clears a stale subject before a new room-prose tail",function()
  wrapped({"A gate", "The breeze passes. A shop", "is here."},{{-1,"A shop"}})
end)

test("travel rejects wrapped quoted chat including complete middle sentences",function()
  wrapped({'You say, "Listen:',"A gate is here.",'We should go."'},{})
  wrapped({"Someone says, “Listen:","A shop is here.","We should go.”"},{})
  wrapped({'You say, "A gate', 'is here."'},{})
  local parser=Travel.new()
  eq(parser:onLine("A shop"),nil); eq(parser:onLine('You say, "hello"'),nil)
  eq(parser:onLine("is here."),nil)
  assert(parser:onLine("A shop is here."))
end)

test("travel rejects wrapped nontravel subjects and movement narratives",function()
  wrapped({"A merchant guarding", "the gate is here."},{})
  wrapped({"A torch from", "the shop is here."},{})
  wrapped({"You walk through", "a gate is here."},{})
  wrapped({"A traveler walks east.", "is here."},{})
end)

test("travel drops candidates exceeding four lines instead of sliding them",function()
  local parser=Travel.new()
  for _,line in ipairs({"An open", "old", "dark", "iron"}) do
    eq(parser:onLine(line),nil); assert(#parser.lines<=4); assert(parser.bytes<=2048)
  end
  eq(parser:onLine("gate is here."),nil); eq(#parser.lines,0)
  assert(parser:onLine("A shop is here."))
end)

test("travel enforces the byte bound including joining spaces",function()
  local suffix="gate is here."
  local first="An "..string.rep(" ",2048-#suffix-1-3)
  wrapped({first,suffix},{{-1,"An"},{0,"gate"}})
  wrapped({first.." ",suffix},{})
  local parser=Travel.new()
  eq(parser:onLine("A gate"),nil); eq(parser:onLine(string.rep("x",2049)),nil)
  eq(parser:onLine("is here."),nil); eq(parser.bytes,0)
end)

test("travel parser instances keep independent pending state",function()
  local first,second=Travel.new(),Travel.new()
  eq(first:onLine("A gate"),nil); eq(second:onLine("is here."),nil)
  eq(assert(first:onLine("is here."))[1].source_line,"A gate")
end)

test("travel is deterministic and owns only bounded text state",function()
  local parser=Travel.new()
  for index=1,100 do
    local line=index%5==0 and "An open" or "old"
    eq(parser:onLine(line),nil); assert(#parser.lines<=4); assert(parser.bytes<=2048)
  end
  parser:reset()
  local a=Travel.parse("A gate is here."); a[1].start=99
  eq(Travel.parse("A gate is here.")[1].start,1)
  eq(parser.bytes,0); eq(#parser.lines,0)
end)
