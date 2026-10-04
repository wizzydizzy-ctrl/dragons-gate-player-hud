local Needs=require("needs_tracker")
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end

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
