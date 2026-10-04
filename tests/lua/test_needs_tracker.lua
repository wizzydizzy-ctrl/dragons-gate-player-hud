local Needs=require("needs_tracker")
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end

local Parser=require("command_parser")
local biography=[[You are Dace Alterac, a delicate boned and skinny bodied 28 year old Entropic Male young Monitanian. You are 7'0" and weigh 247 lbs.]]

test("quoted room biographies cannot default either need to ok",function()
  local prose=[[You are in a gallery, where a plaque reads "You are Synthetic Tester, a stocky bodied 28 year old Entropic Male young Human. You are 6'0" and weigh 180 lbs."]]
  for _,lines in ipairs({
    {prose,">"},
    {"\27[32m"..prose.."\27[0m",">"},
    {[[You are in a gallery, where a plaque reads "You are Synthetic Tester,]],
      [[a stocky bodied 28 year old Entropic Male young Human. You are 6'0" and weigh 180 lbs."]],">"},
  }) do
    eq(Parser.parseInfo(lines),nil)
    local changes=0
    local n=Needs.new({epoch=function() return 10 end},function() changes=changes+1 end)
    assert(n:onLine("You are ravenous. You are parched."))
    local before=n:status()
    for _,line in ipairs(lines) do n:onLine(line) end
    local after=n:status()
    for _,need in ipairs({"hunger","thirst"}) do
      for _,field in ipairs({"status","timestamp","source","raw"}) do eq(after[need][field],before[need][field]) end
    end
    eq(changes,1)
  end
end)

test("complete INFO overwrites both needs and defaults each missing condition to ok",function()
  for _,case in ipairs({{"","ok","ok"},{" You are hungry.","hungry","ok"},
    {" You are thirsty.","ok","thirsty"},{" You are satiated. Your thirst is quenched.","satiated","quenched"}}) do
    local stamp=10; local n=Needs.new({epoch=function() return stamp end})
    assert(n:onLine("You are ravenous. You are parched.")); stamp=11
    assert(n:onInfo(assert(Parser.parseInfo({biography..case[1],">"}))))
    local s=n:status(); eq(s.hunger.status,case[2]); eq(s.thirst.status,case[3])
    eq(s.hunger.timestamp,11); eq(s.thirst.timestamp,11)
    assert(n:onLine("You are starving.")); eq(n:status().thirst.status,case[3])
    assert(n:onLine("You are very thirsty.")); eq(n:status().hunger.status,"starving")
  end
end)

test("attribute and vitals INFO deltas cannot reset needs even with retained biography elsewhere",function()
  local n=Needs.new({epoch=function() return 10 end}); assert(n:onLine("You are ravenous. You are parched."))
  for _,lines in ipairs({
    {"Str Int Wis Dex Agi Con Cha Wil Pre Per Luk","Good Good Good Good Good Good Good Good Good Good Good",">"},
    {"HP: 213 of 213 Ftg: 81 of 81 Carry: 174.4 of 354.0 lbs.",">"},
    {"You are Dace Alterac, a delicate boned young Monitanian.","HP: 213 of 213",">"},
  }) do
    local parsed=assert(Parser.parseInfo(lines)); eq(parsed.condition_text,nil); eq(n:onInfo(parsed),false)
    eq(n:status().hunger.status,"ravenous"); eq(n:status().thirst.status,"parched")
  end
  eq(n:onInfo(nil),false); eq(n:onInfo({}),false)
end)

test("unsolicited INFO accepts plain wrapped ANSI and prompt-prefixed biographies only at a real prompt",function()
  local cases={
    {lines={biography},prompt=">",hunger="ok",thirst="ok"},
    {lines={"> "..biography.." You are hungry."},prompt=">",hunger="hungry",thirst="ok"},
    {lines={"\27[32m[199] 301/301 hp, 173/173 ftg > "..biography.." You are thirsty.\27[0m"},
      prompt="[199] 301/301 hp, 173/173 ftg >",hunger="ok",thirst="thirsty"},
    {lines={"\27[32m> You are Dace Alterac, a delicate boned and skinny bodied 28 year old Entropic Male young Monitanian.\27[0m",
      [[You are 7'0" and weigh 247 lbs. You are]],"satiated. Your thirst is","quenched."},
      prompt=">",hunger="satiated",thirst="quenched"},
  }
  for _,case in ipairs(cases) do
    local n=Needs.new({epoch=function() return 10 end}); n:onLine("You are ravenous. You are parched.")
    for _,line in ipairs(case.lines) do n:onLine(line) end
    if case.hunger=="ok" then eq(n:status().hunger.status,"ravenous") end
    if case.thirst=="ok" then eq(n:status().thirst.status,"parched") end
    n:onLine(case.prompt); eq(n:status().hunger.status,case.hunger); eq(n:status().thirst.status,case.thirst)
  end
end)

test("startup prompts prose actions and incomplete or malformed biographies never infer ok",function()
  for _,seed in ipairs({false,true}) do
    local n=Needs.new({epoch=function() return 10 end})
    if seed then n:onLine("You are ravenous. You are parched.") end
    for _,line in ipairs({"",">","[199] 301/301 hp, 173/173 ftg >","The room is quiet.",
      "You eat the last of your bread.","You drink the last of your water.",
      "You are Dace Alterac, a delicate boned and skinny bodied 28 year old Entropic Male young Monitanian.",">",
      [[You are Dace Alterac, a young Monitanian. You are tall and weigh many lbs.]],">",biography}) do n:onLine(line) end
    eq(n:status().hunger.status,seed and "ravenous" or "unknown")
    eq(n:status().thirst.status,seed and "parched" or "unknown")
  end
end)

test("unsolicited INFO overflow does not reset needs and a new bounded biography recovers",function()
  for _,overflow in ipairs({"lines","bytes"}) do
    local n=Needs.new({epoch=function() return 10 end}); n:onLine("You are ravenous. You are parched.")
    n:onLine(biography)
    if overflow=="lines" then for _=1,65 do n:onLine("Harmless extra INFO detail.") end
    else n:onLine(string.rep("x",16385)) end
    n:onLine(">"); eq(n:status().hunger.status,"ravenous"); eq(n:status().thirst.status,"parched")
    n:onLine(biography); n:onLine(">"); eq(n:status().hunger.status,"ok"); eq(n:status().thirst.status,"ok")
  end
end)

test("standalone and ANSI healthy notices update only their own need",function()
  for _,ansi in ipairs({false,true}) do
    local stamp=10; local n=Needs.new({epoch=function() return stamp end})
    local function line(value) return ansi and " \t\27[32m"..value.."\27[0m " or value end
    assert(n:onLine("You are hungry. You are parched.","info"))
    stamp=11; assert(n:onLine(line("You are satiated.")))
    local s=n:status(); eq(s.hunger.status,"satiated"); eq(s.hunger.timestamp,11); eq(s.hunger.source,"output")
    eq(s.thirst.status,"parched"); eq(s.thirst.timestamp,10); eq(s.thirst.source,"info")
    stamp=12; assert(n:onLine(line("Your thirst is quenched.")))
    s=n:status(); eq(s.thirst.status,"quenched"); eq(s.thirst.timestamp,12); eq(s.thirst.source,"output")
    eq(s.hunger.status,"satiated"); eq(s.hunger.timestamp,11)
  end
end)

test("healthy needs can worsen and recover independently",function()
  local n=Needs.new({epoch=function() return 42 end})
  for _,step in ipairs({
    {"You are satiated. Your thirst is quenched.","satiated","quenched"},
    {"You are hungry.","hungry","quenched"},
    {"You are very thirsty.","hungry","very_thirsty"},
    {"You are satiated.","satiated","very_thirsty"},
    {"Your thirst is quenched.","satiated","quenched"},
    {"You are ravenous.","ravenous","quenched"},
    {"You are parched.","ravenous","parched"},
    {"You are starving.","starving","parched"},
  }) do assert(n:onLine(step[1])); local s=n:status(); eq(s.hunger.status,step[2]); eq(s.thirst.status,step[3]) end
end)

test("actions and bare quenched prose do not infer healthy needs",function()
  local changes=0; local n=Needs.new({epoch=function() return 7 end},function() changes=changes+1 end)
  assert(n:onLine("You are hungry. You are very thirsty.","info"))
  local before=n:status()
  for _,line in ipairs({"You eat the last of your bread.","You drink the last of your water.",
    "Quenched.","The fire is quenched.","Your thirst is quenched","Your thirst is not quenched."}) do
    eq(n:onLine(line),false)
    local s=n:status()
    for _,need in ipairs({"hunger","thirst"}) do
      for _,field in ipairs({"status","timestamp","source","raw"}) do eq(s[need][field],before[need][field]) end
    end
  end
  eq(changes,1)
end)

test("confirmed hunger and thirst phrases update independent states",function()
  local n=Needs.new({epoch=function() return 42 end})
  for phrase,want in pairs({["You are starting to feel hungry."]="hungry",["You are hungry."]="hungry",["You are ravenous."]="ravenous",["You are ravenously hungry."]="ravenous",["You are starving."]="starving",["You feel like you're starving, you're so hungry."]="starving",["You are satiated."]="satiated"}) do n:onLine(phrase); eq(n:status().hunger.status,want) end
  for phrase,want in pairs({["You are starting to feel thirsty."]="thirsty",["You are thirsty."]="thirsty",["You are very thirsty."]="very_thirsty",["You are parched."]="parched"}) do n:onLine(phrase); eq(n:status().thirst.status,want) end
end)
test("combined INFO ANSI and action lines remain conservative",function()
  local n=Needs.new({epoch=function() return 7 end}); n:onLine("\27[31mYou are hidden. You are hungry. You are very thirsty.\27[0m","info")
  local s=n:status(); eq(s.hunger.status,"hungry"); eq(s.thirst.status,"very_thirsty"); eq(s.thirst.timestamp,7); eq(s.thirst.source,"info")
  eq(n:onLine("You eat the last of your bread."),false); eq(n:onLine("You drink the last of your water."),false); eq(n:status().hunger.status,"hungry"); eq(n:status().thirst.status,"very_thirsty")
end)
