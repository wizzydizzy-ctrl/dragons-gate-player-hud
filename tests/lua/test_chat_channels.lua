local Channels=require("chat_channels")
local function entry(category,line) return {category=category,line=line,message="hello",speaker="Tester"} end

test("combined LINK is reversible presentation with independent custom LINK",function()
  local separate={"ALL","STAFF","PSYCIAN","ROOM","MENTAL","DRAGON","SECIAN","LINK","QUEST"}
  local combined,ok=Channels.combinedOrder(separate,{"LINK","QUEST"})
  eq(ok,true); eq(table.concat(combined,","),"ALL,STAFF,LINK VIEW,ROOM,LINK,QUEST")
  eq(table.concat(separate,","),"ALL,STAFF,PSYCIAN,ROOM,MENTAL,DRAGON,SECIAN,LINK,QUEST")
  local reordered=Channels.combinedOrder(separate,{"LINK","QUEST"},{"QUEST","LINK VIEW","ALL"})
  eq(table.concat(reordered,","),"QUEST,LINK VIEW,ALL,STAFF,ROOM,LINK")
  local collision,allowed=Channels.combinedOrder(separate,{"LINK VIEW"})
  eq(allowed,false); eq(table.concat(collision,","),table.concat(separate,","))
end)

test("MENTAL wire families stay distinct without guessing from message bodies",function()
  for _,row in ipairs({
    {'Tester (ESP): "hello"',"esp"},
    {'Tester thinks to you, "hello"',"contact"},
    {'You pick up Tester\'s thoughts, "hello" [r-1]',"contact"},
    {'You pick up Tester\'s thoughts echoing through the area, "hello"',"contact"},
    {'You pick up Tester\'s mental link, "hello" [r-1]',"link"},
    {'Listener picks up Tester\'s mental link, "hello"',"link"},
  }) do
    eq(Channels.mentalKind(entry("MENTAL",row[1])),row[2])
    eq(Channels.mentalKind(entry("MENTAL","\27[35m"..row[1].."\27[0m")),row[2])
  end
  eq(Channels.mentalKind(entry("ESP","hello")),"esp")
  eq(Channels.mentalKind(entry("CONTACT","hello")),"contact")
  eq(Channels.mentalKind(entry("MENTAL","hello")),nil)
  eq(Channels.mentalKind(entry("MENTAL",'Say: Tester (ESP): "hello"')),nil)
  eq(Channels.mentalKind(entry("MENTAL",'Tester thinks to you, "mental link"')),"contact")
  eq(Channels.mentalKind(entry("ESP",'You pick up Tester\'s Psycian link, "hello" [r-1]')),nil)
  eq(Channels.mentalKind(entry("STAFF",'Tester (ESP): "hello"')),nil)
  eq(Channels.mentalKind(entry("MENTAL",'You pick up Tester\'s mental link, "hello" [r-x]')),nil)
end)

test("MENTAL merges ESP and CONTACT names without duplicate saved tabs",function()
  eq(Channels.category(" esp "),"MENTAL"); eq(Channels.category("contact"),"MENTAL")
  eq(table.concat(Channels.tabOrder({"STAFF","CONTACT","DRAGON","ESP","MENTAL","PSYCIAN"}),","),"STAFF,MENTAL,DRAGON,PSYCIAN")
  eq(table.concat(Channels.tabOrder({"OWN","WHISPER","<script>","LINE\nBREAK","MENTAL"}),","),"MENTAL")
end)
test("named links use separate channels while generic mental links stay neutral",function()
  for _,row in ipairs({{"Psycian","PSYCIAN"},{"Dragon","DRAGON"},{"Secian","SECIAN"},{"mental","MENTAL"}}) do
    for _,rank in ipairs({""," [r-1]"," [r-30]"}) do
      local value=entry("ESP",'You pick up Tester\'s '..row[1]..' link, "hello"'..rank)
      eq(Channels.entryCategory(value),row[2])
    end
  end
  eq(Channels.entryCategory(entry("DRAGON",'Listener picks up Tester\'s mental link, "hello"')),"MENTAL")
end)
test("historical projection preserves original records and quoted text",function()
  local original=entry("ESP",'You pick up Fiora\'s Psycian link, "hello" [r-1]')
  original.timestamp="2026-10-05T12:00:00-04:00"; original.character="Existing Character"
  local projected=Channels.project(original)
  eq(projected.category,"PSYCIAN"); eq(original.category,"ESP")
  for _,key in ipairs({"timestamp","character","speaker","message","line"}) do eq(projected[key],original[key]) end
  local generic=entry("DRAGON",'You pick up Tester\'s mental link, "hello"')
  eq(Channels.project(generic).category,"MENTAL"); eq(generic.category,"DRAGON")
end)
test("link classification uses framing not quoted channel words",function()
  local dragon=entry("DRAGON",'You pick up Tester\'s Dragon link, "Psycian link and Secian link are not this channel." [r-1]')
  eq(Channels.entryCategory(dragon),"DRAGON")
  eq(Channels.entryCategory(entry("DRAGON",'You pick up Tester\'s Psycian link, "hello" [r-x]')),"DRAGON")
  eq(Channels.entryCategory(entry("DRAGON",'Say: You pick up Tester\'s Psycian link, "hello"')),"DRAGON")
  eq(Channels.entryCategory(entry("STAFF",'You pick up Tester\'s Psycian link, "quoted report"')),"STAFF")
  eq(Channels.entryCategory(entry("ESP",'\27[36mYou pick up Tester\'s Psycian link, "hello" [r-1]\27[0m')),"PSYCIAN")
end)
test("MENTAL ALL inclusion merges legacy choices and honors an explicit OFF",function()
  local merged=Channels.allSources({ESP=false,CONTACT=true,ROOM=false})
  eq(merged.MENTAL,true); eq(merged.PSYCIAN,false); eq(merged.ROOM,false)
  eq(merged.ESP,nil); eq(merged.CONTACT,nil)
  eq(Channels.allSources({ESP=false,CONTACT=false}).MENTAL,false)
  local explicit=Channels.allSources({MENTAL=false,PSYCIAN=true,ESP=true,CONTACT=true})
  eq(explicit.MENTAL,false); eq(explicit.PSYCIAN,true)
  eq(Channels.allSources().COMBAT,false)
end)
test("ALL source checks keep unrelated partial-source semantics and aliases",function()
  eq(Channels.inAll("ESP",{MENTAL=false}),false); eq(Channels.inAll("CONTACT",{MENTAL=false}),false)
  eq(Channels.inAll("MENTAL",{ESP=false,CONTACT=false}),false)
  eq(Channels.inAll("PSYCIAN",{ESP=false}),false)
  eq(Channels.inAll("PSYCIAN",{PSYCIAN=true,ESP=false}),true)
  eq(Channels.inAll("COMBAT",{MENTAL=false}),true)
  eq(Channels.inAll("OWN",{ROOM=false}),false)
  eq(Channels.inAll("CUSTOM",{CUSTOM=false}),false)
  eq(Channels.inAll("MENTAL",nil),true)
end)
