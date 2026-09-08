local Needs=require("needs_tracker")
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
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
