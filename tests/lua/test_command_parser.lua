local Parser=require("command_parser")

local inventory={"Items carried:","  A wooden torch [1.0 lb].","  A wooden torch [0.1 lbs].","  A simple spear [0.5 lbs].","Your inventory totals 1.6 lbs.",">"}
local stat={"Body Armor: 4%.","OR:  18  DR: 70  Move Rate: 6/6 UDs  Dam Bonus: Good/None  Stance: Aggressive","You are in the center of the area!","You are still protected by the 80 hour novice protection.","  ::: Equipment Readied :::","  A simple spear.","  A wooden shield.",">"}
local info={"You are Test Tester, a light boned and stocky bodied 28 year old Entropic Male young Monitanian.  You are 6'10\" and weigh 309 lbs.","HP: 201 of 201  Ftg:  69 of  69  Carry: 15.9 of 380.0 lbs."," Str   Int   Wis   Dex   Agi   Con   Cha   Wil   Voi   Per   App","Good  Low   Fair  Fair  Fair  Good  Good  Good  Aver  Fair  Fair",">"}
local religion={"You are a Novitiate follower of Unknown.","You have earned 57000 favors.","You are Balanced within your Entropic alignment.",">"}
local runes={"You have the following elemental runes available to you...","  force       - 100 weaves remain   healing     -  14 weaves remain","  holy        -  99 weaves remain   vigor       - 100 weaves remain","  light       - 100 weaves remain",">"}
local skills={"Skill                     Remain Level","Biting                    105    4","Clawing                   276    2","Pole Weapons               42    4","Identify Armor Quality    100    1",">"}
local time={"Current time is: Wed Sep  2 00:40:30 2026 EST.","It is now 3:22 am on the 4th day of the 8th month in the year 362.","You have been adventuring for 14 secs this session.",">"}
local namedTime={"Server local time is: Mon Sep 14 01:13:51 2026 (pacific).","Today is the 59th day of Majus in the year 362. The time is 4:29.","You have been adventuring for 4 hrs, 50 mins, 30 secs this session.","[9006] 301/301 hp, 173/173 ftg >"}

test("parses inventory items without merging duplicates",function()
  local r=assert(Parser.parseInventory(inventory)); eq(#r.items,3); eq(r.items[1].name,"A wooden torch"); eq(r.items[2].weight,0.1); eq(r.total_weight,1.6)
end)
test("parses staff inventory and accepts the staff vitals prompt",function()
  local lines={'Items carried:','[ 1] "An open large leather backpack" (0d0+0, +AR 0%(+0)) [66.0 lbs]','[ 2] "A massive breathtaking bluesteel war hammer" (3d12+8, +AR 0%(+0)) [7.7 lbs]','Your inventory totals 335.1 lbs.','[199] 301/301 hp, 173/173 ftg >'}
  local r=assert(Parser.parseInventory(lines)); eq(r.items[1].name,"An open large leather backpack"); eq(r.items[2].weight,7.7); eq(Parser.isComplete("inventory",lines),true)
end)
test("rejects incomplete inventory",function() eq(Parser.parseInventory({"Items carried:","  A torch [1.0 lb]."}),nil) end)
test("inventory parses all eight unnumbered player items from the October 8 log",function()
  local lines={"Items equipped:","",
    "  A simple wooden boomerang [3.3 lbs] (right hand)",
    "  A heavy tin armor [22.0 lbs] (body armor)",
    "  A bone shield [2.2 lbs] (shield arm)",
    "  A grey sash of Unknown [0.2 lbs] (on belt)","",
    "Items carried:","",
    "  An open large leather backpack [15.1 lbs]",
    "  A simple wooden long sword [0.2 lbs]",
    "  A simple wooden cudgel [0.5 lbs]",
    "  A simple wooden spear [0.5 lbs]","",
    "Your inventory totals 120.5 lbs.",">"}
  local expected={
    {"A simple wooden boomerang",3.3,"equipped","right hand"},
    {"A heavy tin armor",22,"equipped","body armor"},
    {"A bone shield",2.2,"equipped","shield arm"},
    {"A grey sash of Unknown",.2,"equipped","on belt"},
    {"An open large leather backpack",15.1,"carried"},
    {"A simple wooden long sword",.2,"carried"},
    {"A simple wooden cudgel",.5,"carried"},
    {"A simple wooden spear",.5,"carried"},
  }
  local r=assert(Parser.parseInventory(lines)); eq(#r.items,8); eq(r.total_weight,120.5)
  for index,item in ipairs(expected) do
    eq(r.items[index].name,item[1]); eq(r.items[index].weight,item[2])
    eq(r.items[index].section,item[3]); eq(r.items[index].location,item[4])
  end
  eq(Parser.isComplete("inventory",lines),true)
end)
test("inventory preserves balanced nested locations in numbered and unnumbered rows",function()
  local locations={"legs (pants)","torso (shirt)","body (armor (lining))"}
  for _,prefix in ipairs({'  A test item','[1] "A test item"'}) do
    for _,location in ipairs(locations) do
      local r=assert(Parser.parseInventory({"Items equipped:",
        prefix.." [0.4 lbs] ("..location..")","Your inventory totals 0.4 lbs."}))
      eq(#r.items,1); eq(r.items[1].name,"A test item"); eq(r.items[1].weight,.4)
      eq(r.items[1].section,"equipped"); eq(r.items[1].location,location)
    end
  end
end)
test("inventory rejects unbalanced nested locations and repeated outer blocks",function()
  local tails={"(legs (pants)","(legs pants))","(legs (pants)))","((legs (pants))",
    "(legs )pants))(","(legs (pants)) (torso (shirt))","(legs (pants))(torso (shirt))"}
  for _,prefix in ipairs({'  A malformed item','[1] "A malformed item"'}) do
    for _,tail in ipairs(tails) do
      local r=assert(Parser.parseInventory({"Items equipped:",prefix.." [0.4 lbs] "..tail,
        "  A valid item [1.0 lb] (right hand)","Your inventory totals 1.0 lbs."}))
      eq(#r.items,1); eq(r.items[1].name,"A valid item"); eq(r.items[1].location,"right hand")
    end
  end
end)
test("inventory parses all ten items from the October 8 15-20-10 log",function()
  local lines={"Items equipped:","",
    "  A silver studded snakeskin gauntlets [1.2 lb] (over hands)",
    "  Some plain leather boots [0.9 lbs] (on feet)",
    "  A pair of plain cotton pants [0.4 lbs] (legs (pants))",
    "  A plain cotton shirt [0.2 lbs] (torso (shirt))",
    "  An open canvas sack [0.0 lbs] (on belt)",
    "  A closed small hardened leather sheath [0.2 lbs] (on belt)","",
    "Items carried:","",
    "  An open large leather backpack [41.6 lbs]",
    "  A small vial of healing [0.1 lbs]",
    "  A heavy tin armor [18.0 lbs]",
    "  A two-handed elm lance [6.3 lbs]","",
    "Your inventory totals 68.9 lbs.",">"}
  local expected={
    {"A silver studded snakeskin gauntlets",1.2,"equipped","over hands"},
    {"Some plain leather boots",.9,"equipped","on feet"},
    {"A pair of plain cotton pants",.4,"equipped","legs (pants)"},
    {"A plain cotton shirt",.2,"equipped","torso (shirt)"},
    {"An open canvas sack",0,"equipped","on belt"},
    {"A closed small hardened leather sheath",.2,"equipped","on belt"},
    {"An open large leather backpack",41.6,"carried"},
    {"A small vial of healing",.1,"carried"},
    {"A heavy tin armor",18,"carried"},
    {"A two-handed elm lance",6.3,"carried"},
  }
  local r=assert(Parser.parseInventory(lines)); eq(#r.items,10); eq(r.total_weight,68.9)
  local equipped,carried=0,0
  for index,item in ipairs(expected) do
    local actual=r.items[index]
    eq(actual.name,item[1]); eq(actual.weight,item[2]); eq(actual.section,item[3]); eq(actual.location,item[4])
    if actual.section=="equipped" then equipped=equipped+1 elseif actual.section=="carried" then carried=carried+1 end
  end
  eq(equipped,6); eq(carried,4); eq(Parser.isComplete("inventory",lines),true)
end)
test("unnumbered inventory preserves duplicate rows across equipped and carried sections",function()
  local r=assert(Parser.parseInventory({"Items equipped:","  A wooden torch [1.0 lb] (right hand)",
    "Items carried:","  A wooden torch [1.0 lb]","  A wooden torch [1.0 lb]",
    "  A wooden torch [0.2 lbs].","Your inventory totals 3.2 lbs."}))
  eq(#r.items,4)
  for _,item in ipairs(r.items) do eq(item.name,"A wooden torch") end
  eq(r.items[1].section,"equipped"); eq(r.items[1].location,"right hand")
  for index=2,4 do eq(r.items[index].section,"carried"); eq(r.items[index].location,nil) end
  eq(r.items[2].weight,1); eq(r.items[3].weight,1); eq(r.items[4].weight,.2)
end)
test("new unnumbered inventory rows require indentation and an inventory section",function()
  local r=assert(Parser.parseInventory({"  A row outside inventory [9.0 lbs]",
    "  A row outside inventory [9.0 lbs] (right hand)","  A legacy torch [0.5 lbs].",
    "Items carried:","A row without indentation [9.0 lbs]",
    "  A valid torch [1.0 lb]","Your inventory totals 1.5 lbs."}))
  eq(#r.items,2); eq(r.items[1].name,"A legacy torch"); eq(r.items[1].section,nil)
  eq(r.items[2].name,"A valid torch"); eq(r.items[2].section,"carried")
end)
test("unnumbered inventory rejects malformed weights locations and trailing text",function()
  local r=assert(Parser.parseInventory({"Items equipped:",
    "  A bad item [1..2 lbs] (right hand)","  A bad item [1.0 lbs] extra",
    "  A bad item [1.0 lbs] (right hand) extra","  A bad item [1.0 lbs] ()",
    "  A bad item [1.0 lbs] (right (hand)","  A bad item [1.0 lbs] (right\t hand)",
    "  A bad item [1.0 lbs] ("..string.rep("x",81)..")",
    "  A bad item [1.0 lbs] (right hand) [99.0 lbs].","  [1.0 lbs]",
    "  A valid item [1.0 lb] (right hand)","Your inventory totals 1.0 lbs."}))
  eq(#r.items,1); eq(r.items[1].name,"A valid item"); eq(r.items[1].location,"right hand")
end)
test("inventory retains equipped hand locations and carried items from the new format",function()
  local lines={"Items equipped:",
    '[ 8] "A practice long-bow" (0d0+0, +AR 0%(+0)) [2.2 lbs] (right hand)',
    '[ 9] "A quiver of practice arrows" (0d0+0, +AR 0%(+0)) [0.8 lbs] (left hand)',
    "Items carried:",'[ 1] "An open leather backpack" (0d0+0, +AR 0%(+0)) [66.0 lbs]',
    "Your inventory totals 69.0 lbs.","[199] 299/299 hp, 188/188 ftg >"}
  local r=assert(Parser.parseInventory(lines)); eq(#r.items,3); eq(r.total_weight,69)
  eq(r.items[1].section,"equipped"); eq(r.items[1].location,"right hand"); eq(r.items[1].weight,2.2)
  eq(r.items[2].section,"equipped"); eq(r.items[2].location,"left hand"); eq(r.items[2].weight,.8)
  eq(r.items[3].section,"carried"); eq(r.items[3].location,nil); eq(r.items[3].weight,66)
  eq(Parser.isComplete("inventory",lines),true)
end)
test("inventory preserves duplicates across equipped and carried sections",function()
  local r=assert(Parser.parseInventory({"Items equipped:",'[1] "A wooden torch" [1.0 lb] (right hand)',
    "Items carried:",'[2] "A wooden torch" [0.1 lbs]',"  A wooden torch [0.2 lbs].","Your inventory totals 1.3 lbs."}))
  eq(#r.items,3); eq(r.items[1].name,r.items[2].name); eq(r.items[1].location,"right hand")
  eq(r.items[2].section,"carried"); eq(r.items[3].section,"carried"); eq(r.items[3].weight,.2)
end)
test("inventory does not accept malformed weights or unrelated trailing text",function()
  local r=assert(Parser.parseInventory({"Items equipped:",
    '[1] "A bad item" [1..2 lbs] (right hand)', '[2] "A bad item" [1.0 lbs] (right hand) extra',
    '[3] "A bad item" [1.0 lbs] ()', '[4] "A bad item" [1.0 lbs] (right (hand)',
    '[5] "A bad item" [1.0 lbs] (right\t hand)', '[6] "A valid item" [1.0 lbs] (right hand)',
    "Your inventory totals 1.0 lbs."}))
  eq(#r.items,1); eq(r.items[1].name,"A valid item")
end)
test("malformed indexed inventory cannot fall through to legacy sentence parsing",function()
  local r=assert(Parser.parseInventory({"Items equipped:",
    '  [1] "A fake item" [1.0 lbs] (right hand) [99.0 lbs].',
    '  [2] "A fake item" [1.0 lbs].',
    '  [3] "A fake item" [1..2 lbs].',
    '  A real torch [0.5 lbs].', "Your inventory totals 0.5 lbs."}))
  eq(#r.items,1); eq(r.items[1].name,"A real torch"); eq(r.items[1].weight,.5)
end)
test("parses stat combat protection and readied equipment",function()
  local r=assert(Parser.parseStat(stat)); eq(r.body_armor,4); eq(r.or_rating,18); eq(r.dr,70); eq(r.move.current,6); eq(r.move.maximum,6); eq(r.damage_bonus,"Good/None"); eq(r.stance,"Aggressive"); eq(r.area_position,"center"); eq(r.novice_protected,true); eq(r.equipment[2],"A wooden shield")
end)
test("STAT combat fields parse before a prompt without equipment or posture deltas",function()
  local r=assert(Parser.parseStatCombat({stat[1],stat[2]}))
  eq(r.body_armor,4); eq(r.or_rating,18); eq(r.dr,70); eq(r.move.current,6); eq(r.move.maximum,6)
  eq(r.damage_bonus,"Good/None"); eq(r.stance,"Aggressive"); eq(r.equipment,nil); eq(r.standing,nil)
  eq(Parser.parseStat({stat[1],stat[2]}),nil); eq(Parser.isComplete("stat",{stat[1],stat[2]}),false)
end)
test("STAT parses ANSI prompt prefixes and wrapped combat fields and values",function()
  local lines={"\27[38;5;32m[199] 301/301 hp, 173/173 ftg > Body Armor: 9%.\27[0m",
    "> OR: 25 DR: 115", "Move Rate: 3/", "6 UDs Dam Bonus: Good/", "None Stance:", "Frenzied"}
  local r=assert(Parser.parseStatCombat(lines)); eq(r.body_armor,9); eq(r.or_rating,25); eq(r.dr,115)
  eq(r.move.current,3); eq(r.move.maximum,6); eq(r.damage_bonus,"Good/None"); eq(r.stance,"Frenzied")
  lines[#lines+1]=">"; eq(Parser.isComplete("stat",lines),true); eq(assert(Parser.parseStat(lines)).equipment,nil)
end)
test("STAT combat parser accepts partial fields and rejects malformed values",function()
  local r=assert(Parser.parseStatCombat({"DR: 81", "Stance: Defensive"})); eq(r.dr,81); eq(r.stance,"Defensive"); eq(r.or_rating,nil)
  eq(Parser.parseStatCombat({"OR: 1..2 DR: nope", "Move Rate: 6/x UDs", "Stance: Frenzied<script>"}),nil)
end)
test("STAT reconstructs split labels and units while retaining damage bonus token formats",function()
  local r=assert(Parser.parseStatCombat({"Body Armor:","9%.","OR: 25 DR: 115 Move", "Rate: 3/6", "UDs Dam", "Bonus: 10/+2 Stance:","Normal"}))
  eq(r.body_armor,9); eq(r.or_rating,25); eq(r.dr,115); eq(r.move.current,3); eq(r.move.maximum,6)
  eq(r.damage_bonus,"10/+2"); eq(r.stance,"Normal")
end)
test("standalone strategy confirmations accept alphabetic stances and prompt prefixes",function()
  for _,stance in ipairs({"Frenzied","Aggressive","Normal","Defensive","Cautious"}) do
    for _,prefix in ipairs({"","> ","[199] 301/301 hp, 173/173 ftg > "}) do
      eq(Parser.parseStance("\27[36m"..prefix.."Attack strategy set to: "..stance.." -- Throw caution to the wind.\27[0m"),stance)
    end
  end
  eq(Parser.parseStance("Attack strategy set to: Normal"),"Normal")
  for _,line in ipairs({"A goblin says: Attack strategy set to: Frenzied -- Attack!",
    "Attack strategy set to: Frenzied<script> -- Attack!", "Attack strategy set to: Frenzied2 -- Attack!",
    "Attack strategy set to: Frenzied nonsense", "A goblin stands up.", "  A goblin draws a spear."}) do
    eq(Parser.parseStance(line),nil); eq(Parser.parseStatCombat({line}),nil)
  end
end)
test("complete partial STAT omits absent equipment and unrelated NPC protection",function()
  local r=assert(Parser.parseStat({"Body Armor: 8%.","A goblin has novice protection.",">"}))
  eq(r.body_armor,8); eq(r.equipment,nil); eq(r.novice_protected,nil); eq(r.standing,nil)
  eq(#assert(Parser.parseStat({"Body Armor: 8%.","::: Equipment Readied :::",">"})).equipment,0)
end)
test("STAT equipment section ignores NPC prose after the response boundary",function()
  local r=assert(Parser.parseStat({stat[1],"::: Equipment Readied :::","  A spear.","","  A shield.",
    "A goblin stands up.","  A goblin draws a sword.",">"}))
  eq(#r.equipment,2); eq(r.equipment[2],"A shield"); eq(r.standing,nil)
end)
test("parses info physical data and all attributes",function()
  local r=assert(Parser.parseInfo(info)); eq(r.physical.age,28); eq(r.physical.sex,"Male"); eq(r.physical.height,"6'10\""); eq(r.physical.weight,309); eq(r.attributes.STR,"Good"); eq(r.attributes.APP,"Fair")
end)
test("info parses from its data rows but collector completion waits for a prompt",function()
  local without_prompt={}; for i=1,#info-1 do without_prompt[i]=info[i] end
  local r=assert(Parser.parseInfo(without_prompt)); eq(r.attributes.STR,"Good"); eq(Parser.isComplete("info",without_prompt),false); eq(Parser.isComplete("info",info),true)
end)
test("info tolerates condition text appended to the physical sentence",function()
  local with_conditions={}; for i,line in ipairs(info) do with_conditions[i]=line end
  with_conditions[1]=with_conditions[1].." You are hungry. You are thirsty."
  local r=assert(Parser.parseInfo(with_conditions)); eq(r.physical.weight,309); eq(r.attributes.APP,"Fair")
end)
test("complete unconditioned INFO has an empty condition delta while partial INFO has none",function()
  local biography=[[You are Dace Alterac, a delicate boned and skinny bodied 28 year old Entropic Male young Monitanian. You are 7'0" and weigh 247 lbs.]]
  for _,lines in ipairs({{biography,">"},{"\27[32m"..biography.."\27[0m",">"},
    {"You are Dace Alterac, a delicate boned and skinny bodied 28 year old Entropic Male young Monitanian.",
      [[You are 7'0" and weigh 247 lbs.]],">"}}) do
    local parsed=assert(Parser.parseInfo(lines)); eq(parsed.condition_text,""); eq(Parser.isComplete("info",lines),true)
  end
  for _,lines in ipairs({
    {"Str Int Wis Dex Agi Con Cha Wil Pre Per Luk","Good Good Good Good Good Good Good Good Good Good Good",">"},
    {"HP: 213 of 213 Ftg: 81 of 81 Carry: 174.4 of 354.0 lbs.",">"},
    {"You are Dace Alterac, a young Monitanian.","HP: 213 of 213",">"},
  }) do eq(assert(Parser.parseInfo(lines)).condition_text,nil) end
  eq(Parser.isComplete("info",{biography}),false)
  eq(Parser.isComplete("info",{"You are Dace Alterac, a young Monitanian.",">"}),false)
end)
test("healthy INFO preserves satiated and quenched conditions across standalone ANSI combined and wrapped lines",function()
  local biography=[[You are Dace Alterac, a delicate boned and skinny bodied 28 year old Entropic Male young Monitanian.  You are 7'0" and weigh 247 lbs.  You are satiated.]]
  for _,lines in ipairs({
    {biography,"Your thirst is quenched.",">"},
    {"\27[32m"..biography.."\27[0m"," \t\27[36mYour thirst is quenched.\27[0m ",">"},
    {biography.." Your thirst is quenched.",">"},
    {"You are Dace Alterac, a delicate boned and skinny bodied 28 year old Entropic Male young Monitanian.",
      [[You are 7'0" and weigh 247 lbs. You are]],"satiated. Your thirst is","quenched.",">"},
  }) do
    local r=assert(Parser.parseInfo(lines)); eq(Parser.isComplete("info",lines),true)
    eq(r.character.full_name,"Dace Alterac"); eq(r.character.race,"Monitanian")
    eq(r.physical.age,28); eq(r.physical.height,[[7'0"]]); eq(r.physical.weight,247)
    eq(r.condition_text,"You are satiated. Your thirst is quenched.")
    local hunger,thirst=require("needs_tracker").detected(r.condition_text)
    eq(hunger,"satiated"); eq(thirst,"quenched")
  end
end)
test("info parses multiword Dragon stage and all attributes",function()
  local lines={"You are Deklan Marrowen, a average boned and wiry-tough bodied 21 year old Entropic Male 1st stage Dragon.  You are 7'1\" and weigh 312 lbs."," Str Int Wis Dex Agi Con Cha Wil Voi Per App","Good Good Great Good Good Good Good Good Good Great Good",">"}
  local r=assert(Parser.parseInfo(lines)); eq(r.character.race,"Dragon"); eq(r.physical.life_stage,"1st stage"); eq(r.attributes.APP,"Good")
end)
test("info reconstructs wrapped Dragon details conditions vitals and expanded ranks",function()
  local lines={
    "You are Deklan Marrowen, a delicate boned and skinny bodied 21 year old Entropic Male 1st stage Dragon.  You are 7'6\" and weigh 292 lbs.  You are hungry.  You are",
    "thirsty.",
    "HP: 213 of 213  Ftg:  81 of  81  Carry: 174.4 of 354.0 lbs.",
    " Str   Int   Wis   Dex   Agi   Con   Cha   Wil   Voi   Per   App",
    "Godly Super Excel Super Super Super Super Super Super Super Super",
    "Use: INFO <subject> for more info.",
    ">",
  }
  local r=assert(Parser.parseInfo(lines)); eq(r.character.full_name,"Deklan Marrowen"); eq(r.character.race,"Dragon"); eq(r.physical.life_stage,"1st stage"); eq(r.physical.weight,292)
  eq(r.condition_text,"You are hungry. You are thirsty."); eq(r.vitals.hp,213); eq(r.vitals.fatigue_max,81); eq(r.vitals.carry,174.4); eq(r.vitals.carry_max,354)
  eq(r.attributes.STR,"Godly"); eq(r.attributes.INT,"Super"); eq(r.attributes.WIS,"Excel"); eq(r.attributes.APP,"Super")
end)
test("info accepts wrapped attribute headers and value rows",function()
  local lines={"Str Int Wis Dex Agi Con","Cha Wil Voi Per App","Godly Super Excel Super Super","Super Super Super Super Super Super",">"}
  local r=assert(Parser.parseInfo(lines)); eq(r.attributes.STR,"Godly"); eq(r.attributes.WIS,"Excel"); eq(r.attributes.APP,"Super")
end)
test("info accepts one attribute header and rank per physical line",function()
  local lines={"Str","Int","Wis","Dex","Agi","Con","Cha","Wil","Voi","Per","App","Awful","Poor","Low","Aver","Fair","Good","Great","Excel","Super","Godly","Fair",">"}
  local r=assert(Parser.parseInfo(lines)); eq(r.attributes.STR,"Awful"); eq(r.attributes.CON,"Good"); eq(r.attributes.PER,"Godly"); eq(r.attributes.APP,"Fair")
end)
test("info keeps uppercase attribute headings out of condition text",function()
  local lines={"You are Deklan Marrowen, a skinny bodied 21 year old Entropic Male 1st stage Dragon. You are 7'6\" and weigh 292 lbs. You are hungry.","STR INT WIS DEX AGI CON CHA WIL VOI PER APP","Godly Super Excel Super Super Super Super Super Super Super Super",">"}
  local r=assert(Parser.parseInfo(lines)); eq(r.condition_text,"You are hungry."); eq(r.attributes.STR,"Godly")
end)
test("info requires its terminal prompt after parsed data",function()
  local lines={">","You are Deklan Marrowen, a skinny bodied 21 year old Entropic Male 1st stage Dragon. You are 7'6\" and weigh 292 lbs."}
  eq(Parser.isComplete("info",lines),false); lines[#lines+1]="Str Int Wis Dex Agi Con Cha Wil Voi Per App"; lines[#lines+1]="Godly Super Excel Super Super Super Super Super Super Super Super"; eq(Parser.isComplete("info",lines),false)
  lines[#lines+1]=">"; eq(Parser.isComplete("info",lines),true)
end)
test("info rejects malformed numeric-only output",function()
  eq(Parser.parseInfo({"HP: 1..2 of 213 Ftg: 8..1 of 81 Carry: 17..4 of 354.0 lbs.",">"}),nil)
end)
test("info retains the optional staff MP column and numeric values",function()
  local lines={" Str Int Wis Dex Agi Con Cha Wil Voi Per App MP","Great Great Great Great Great Great Great Great Great Great Great Great"," 18 18 18 18 18 18 18 18 18 18 18 18","[199] 301/301 hp, 173/173 ftg >"}
  local r=assert(Parser.parseInfo(lines)); eq(r.attributes.STR,"Great"); eq(r.attributes.APP,"Great"); eq(r.attributes.MP,"Great")
  eq(r.attribute_values.STR,18); eq(r.attribute_values.APP,18); eq(r.attribute_values.MP,18); eq(Parser.isComplete("info",lines),true)
end)
test("updated info parses PRE and LUK with an optional staff MP column",function()
  local lines={"You are Test Tester, a light boned and muscular bodied 43 year old Entropic Male adolescent Psycian. You are 7'7\" and weigh 239 lbs.",
    "HP: 299 of 299  Ftg: 188 of 188  Psi: 40 of 40  Carry: 94.9 of 6553.5 lbs.",
    " Str   Int   Wis   Dex   Agi   Con   Cha   Wil   Pre   Per   Luk   MP",
    "Super Super Super Super Super Super Super Super Great Excel Good Super",
    "18 18 18 18 18 18 18 18 17 16 15 18",
    "[5130] 299/299 hp, 188/188 ftg >"}
  local r=assert(Parser.parseInfo(lines))
  eq(r.attributes.PRE,"Great"); eq(r.attributes.PER,"Excel"); eq(r.attributes.LUK,"Good")
  eq(r.attributes.MP,"Super"); eq(r.attribute_values.PRE,17); eq(r.attribute_values.PER,16); eq(r.attribute_values.LUK,15); eq(r.attribute_values.MP,18)
  eq(r.attributes.VOI,nil); eq(r.attributes.APP,nil); eq(Parser.isComplete("info",lines),true)
end)
test("updated info accepts wrapped PRE LUK headers and eleven values",function()
  local lines={"Str Int Wis Dex Agi Con","Cha Wil Pre Per Luk",
    "Awful Poor Low Aver Fair Good","Great Excel Super Godly Fair",">"}
  local r=assert(Parser.parseInfo(lines))
  eq(r.attributes.STR,"Awful"); eq(r.attributes.CON,"Good")
  eq(r.attributes.PRE,"Super"); eq(r.attributes.LUK,"Fair")
end)
test("updated info accepts Superb without retaining a stale attribute snapshot",function()
  local lines={"Str Int Wis Dex Agi Con Cha Wil Pre Per Luk",
    "Superb Great Great Good Good Fair Fair Fair Great Good Superb",">"}
  local r=assert(Parser.parseInfo(lines))
  eq(r.attributes.STR,"Superb"); eq(r.attributes.PRE,"Great"); eq(r.attributes.LUK,"Superb")
end)
test("info keeps distinct staff ranks and numbers aligned including MP",function()
  local lines={"Str Int Wis Dex Agi Con Cha Wil Voi Per App MP","Awful Poor Low Aver Fair Good Great Excel Super Godly Aver Fair","11 12 13 14 15 16 17 18 19 20 21 22","[199] 301/301 hp, 173/173 ftg >"}
  local r=assert(Parser.parseInfo(lines)); eq(r.attributes.STR,"Awful"); eq(r.attributes.CON,"Good"); eq(r.attributes.WIL,"Excel"); eq(r.attributes.PER,"Godly"); eq(r.attributes.APP,"Aver")
  eq(r.attributes.MP,"Fair"); eq(r.attribute_values.STR,11); eq(r.attribute_values.APP,21); eq(r.attribute_values.MP,22)
end)
test("info accepts a wrapped optional MP header rank and numeric row",function()
  local r=assert(Parser.parseInfo({"Str Int Wis Dex Agi Con","Cha Wil Pre Per Luk","MP",
    "Awful Poor Low Aver Fair Good","Great Excel Super Godly Fair","Superb",
    "1 2 3 4 5 6","7 8 9 10 11","12",">"}))
  eq(r.attributes.STR,"Awful"); eq(r.attributes.LUK,"Fair"); eq(r.attributes.MP,"Superb")
  eq(r.attribute_values.STR,1); eq(r.attribute_values.LUK,11); eq(r.attribute_values.MP,12)
end)
test("info does not invent MP and malformed numeric rows preserve ranks only",function()
  local header="Str Int Wis Dex Agi Con Cha Wil Pre Per Luk"
  local ranks="Awful Poor Low Aver Fair Good Great Excel Super Godly Fair"
  local r=assert(Parser.parseInfo({header,ranks,"1 2 3 4 5 6 7 8 9 10 11",">"}))
  eq(r.attributes.MP,nil); eq(r.attribute_values.MP,nil); eq(r.attribute_values.LUK,11)
  for _,numbers in ipairs({"1 2 3 4 5 6 7 8 9 10", "1 2 3 4 5 6 7 8 9 10 1..2", "1 2 3 4 5 6 7 8 9 10 9999999"}) do
    r=assert(Parser.parseInfo({header,ranks,numbers,">"})); eq(r.attributes.LUK,"Fair"); eq(next(r.attribute_values),nil)
  end
end)
test("missing or partial MP never discards eleven confirmed characteristic ranks",function()
  local header="Str Int Wis Dex Agi Con Cha Wil Pre Per Luk MP"
  local ranks="Awful Poor Low Aver Fair Good Great Excel Super Godly Fair"
  for _,tail in ipairs({"Use: INFO <subject> for more info.","Su",">"}) do
    local r=assert(Parser.parseInfo({header,ranks,tail,">"}))
    eq(r.attributes.STR,"Awful"); eq(r.attributes.LUK,"Fair"); eq(r.attributes.MP,nil)
  end
  local r=assert(Parser.parseInfo({header,ranks.." Su","1 2 3 4 5 6 7 8 9 10 11",">"}))
  eq(r.attributes.LUK,"Fair"); eq(r.attributes.MP,nil); eq(r.attribute_values.LUK,11)
end)
test("optional MP allows eleven numeric values but rejects malformed numeric rows",function()
  local header="Str Int Wis Dex Agi Con Cha Wil Pre Per Luk MP"
  local ranks="Awful Poor Low Aver Fair Good Great Excel Super Godly Fair"
  for _,suffix in ipairs({""," Superb"}) do
    local r=assert(Parser.parseInfo({header,ranks..suffix,"1 2 3 4 5 6 7 8 9 10 11","Use: INFO <subject> for more info.",">"}))
    eq(r.attribute_values.STR,1); eq(r.attribute_values.LUK,11); eq(r.attribute_values.MP,nil)
    r=assert(Parser.parseInfo({header,ranks..suffix,"1 2 3 4 5 6","7 8 9 10 11",">"}))
    eq(r.attribute_values.LUK,11); eq(r.attribute_values.MP,nil)
    r=assert(Parser.parseInfo({header,ranks..suffix,"1 2 3 4 5 6 7 8 9 10 11 bad",">"}))
    eq(next(r.attribute_values),nil); eq(r.attributes.LUK,"Fair")
  end
end)
test("info locates a valid rank row through harmless interleaved lines",function()
  local lines={" Str Int Wis Dex Agi Con Cha Wil Voi Per App","",">","info","great GOOD fair Aver low Poor awful Good Fair Aver Great",">"}
  local r=assert(Parser.parseInfo(lines)); eq(r.attributes.STR,"Great"); eq(r.attributes.APP,"Great"); eq(Parser.isComplete("info",lines),true)
end)
test("info accepts attributes independently of physical details",function()
  local lines={"Str Int Wis Dex Agi Con Cha Wil Voi Per App","Good Good Good Good Good Good Good Good Good Good Good",">"}; local r=assert(Parser.parseInfo(lines)); eq(r.attributes.STR,"Good"); eq(r.physical.age,nil)
end)
test("detects completed command responses",function() eq(Parser.isComplete("inventory",inventory),true); eq(Parser.isComplete("inventory",{"Items carried:","Your inventory totals 0 lbs."}),false); eq(Parser.isComplete("stat",stat),true); eq(Parser.isComplete("info",info),true); eq(Parser.isComplete("info",{"You are Test"}),false) end)
test("parses info religion rank deity balance and alignment",function()
  local r=assert(Parser.parseReligion(religion)); eq(r.rank,"Novitiate"); eq(r.deity,"Unknown"); eq(r.favors,57000); eq(r.balance,"Balanced"); eq(r.alignment,"Entropic"); eq(Parser.isComplete("info religion",religion),true)
end)
test("parses an undedicated staff character religion response",function()
  local lines={"You have not yet dedicated to a deity.","You are Balanced within your Entropic alignment.","[199] 301/301 hp, 173/173 ftg >"}
  local r=assert(Parser.parseReligion(lines)); eq(r.rank,"None"); eq(r.deity,"None"); eq(r.balance,"Balanced"); eq(Parser.isComplete("info religion",lines),true)
end)
test("parses both rune columns and sorts lowest remaining first",function()
  local r=assert(Parser.parseRunes(runes)); eq(#r.items,5); eq(r.items[1].name,"Healing"); eq(r.items[1].remaining,14); eq(r.items[2].name,"Holy"); eq(r.items[5].name,"Vigor"); eq(Parser.isComplete("info magic",runes),true); eq(Parser.isComplete("info mag",runes),true)
  eq(Parser.parseRunes({runes[1],runes[2]}),nil); eq(Parser.parseRunes({runes[2],">"}),nil)
end)
test("parses every skill and ranks by level then lowest remaining uses",function()
  local r=assert(Parser.parseSkills(skills)); eq(#r.items,4)
  eq(r.items[1].name,"Pole Weapons"); eq(r.items[1].level,4); eq(r.items[1].remain,42)
  eq(r.items[2].name,"Biting"); eq(r.items[3].name,"Clawing"); eq(r.items[4].name,"Identify Armor Quality")
end)
test("skill parsing requires a header rows and final prompt",function()
  eq(Parser.parseSkills({"Skill Remain Level","Biting 100 1"}),nil)
  eq(Parser.parseSkills({"Biting 100 1",">"}),nil)
  eq(Parser.isComplete("skill",skills),true)
end)
test("owned blank boundary skill parsing retains strict header and nonempty row requirements",function()
  eq(Parser.parseSkills({"Skill Remain Level",""},true),nil)
  eq(Parser.parseSkills({"Biting 100 1",""},true),nil)
  eq(Parser.parseSkills({"Skill Remain Level","Biting 100 1",""}),nil)
  local parsed=assert(Parser.parseSkills({"Skill Remain Level","Biting 100 1",""},true))
  eq(#parsed.items,1); eq(parsed.items[1].name,"Biting")
end)
test("staff skill output strips readiness markers and completes on vitals prompt",function()
  local lines={"Skill Remain Level","*Psionics 0 50"," First Aid 0 50","[199] 301/301 hp, 173/173 ftg >"}
  local r=assert(Parser.parseSkills(lines)); eq(r.items[1].name,"First Aid"); eq(r.items[2].name,"Psionics"); eq(Parser.isComplete("skill",lines),true)
end)
test("skill parsing ignores a stale prompt before its header",function()
  local contaminated={"You are Balanced within your Entropic alignment.",">","Skill                     Remain Level","Biting                    105    4","Clawing                   276    2"}
  eq(Parser.parseSkills(contaminated),nil); contaminated[#contaminated+1]=">"
  local r=assert(Parser.parseSkills(contaminated)); eq(#r.items,2)
end)
test("parses game time and completes only at the prompt",function()
  local r=assert(Parser.parseTime(time)); eq(r.hour,3); eq(r.minute,22); eq(r.day,4); eq(r.month,8); eq(r.year,362)
  eq(Parser.parseTime({time[1],time[2]}),nil); eq(Parser.isComplete("time",time),true)
  local pm={time[1],"It is now 12:07 pm on the 4th day of the 8th month in the year 362.",time[3],">"}
  eq(assert(Parser.parseTime(pm)).hour,12)
  local midnight={time[1],"It is now 12:07 am on the 4th day of the 8th month in the year 362.",time[3],">"}
  eq(assert(Parser.parseTime(midnight)).hour,0)
end)
test("parses named game months from Dragon's Gate 4.0.9.4",function()
  local r=assert(Parser.parseTime(namedTime)); eq(r.hour,4); eq(r.minute,29); eq(r.day,59); eq(r.month,4); eq(r.month_name,"Majus"); eq(r.year,362); eq(r.days_per_month,60); eq(r.months_per_year,6)
  eq(Parser.parseTime({namedTime[1],namedTime[2],namedTime[3]}),nil); eq(Parser.isComplete("time",namedTime),true)
end)

return {inventory=inventory,stat=stat,info=info,religion=religion,skills=skills,time=time}
