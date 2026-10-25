local Channels=require("chat_channels")

test("PRIVATE and WHISPER labels recover complete broadcast and direct frames without mutating records",function()
  local rows={
    {[[Tester (ESP): "Synthetic broadcast."]],"MENTAL",false},
    {[=[You pick up Tester's thoughts, "Synthetic global." [r-1]]=],"MENTAL",false},
    {[[You pick up Tester's thoughts echoing through the area, "Synthetic room."]],"MENTAL",false},
    {[=[You pick up Tester's mental link, "Synthetic generic." [r-2]]=],"MENTAL",false},
    {[[Listener picks up Tester's mental link, "Synthetic observed."]],"MENTAL",false},
    {[=[You pick up Tester's Psycian link, "Synthetic racial." [r-1]]=],"PSYCIAN",false},
    {[[You pick up Tester's Dragon link, "Synthetic racial."]],"DRAGON",false},
    {[[You pick up Tester's Secian link, "Synthetic racial."]],"SECIAN",false},
    {[[Tester thinks to you, "Synthetic direct."]],"MENTAL",true},
    {[[Tester whispers to you, "Synthetic whisper."]],"WHISPER",true},
  }
  for _,category in ipairs({"PRIVATE","WHISPER"}) do
    for _,source in ipairs({"builtin","gmcp","custom"}) do
      for _,row in ipairs(rows) do
        for _,line in ipairs({row[1],"\27[35m\7"..row[1].."\27[0m"}) do
          local value={category=category,source=source,line=line,message="Synthetic metadata.",speaker="Fixture",
            target="Synthetic Listener",schema=1,timestamp="2026-10-24T12:00:00Z",character="Synthetic Keeper"}
          local original={}; for key,item in pairs(value) do original[key]=item end
          eq(Channels.entryCategory(value),row[2]); eq(Channels.inPrivate(value),row[3])
          local projected=Channels.project(value)
          eq(projected.category,row[2])
          for key,item in pairs(original) do
            eq(value[key],item)
            if key~="category" then eq(projected[key],item) end
          end
          for key,item in pairs(value) do eq(original[key],item) end
        end
      end
    end
  end
end)

test("PRIVATE recovery requires complete framing and never guesses from metadata quoted or malformed text",function()
  for _,line in ipairs({
    [[Tester says, "You pick up Other's Psycian link, 'Quoted.'"]],
    [[Report: You pick up Tester's Dragon link, "Synthetic."]],
    [=[You pick up Tester's Psycian link, "Synthetic." [r-x]]=],
    [[You pick up Tester's mental link, "Synthetic." extra]],
    "You pick up Tester's Dragon link, \"Synthetic.\nSecond line.\"",
    "You pick up Tester's Dragon link, \"Synthetic.\rSecond line.\"",
    "You pick up Tester's Dragon link, \"Synthetic.\0Hidden.\"",
    [[Tester (ESP): "Synthetic." trailing]],
    [=[Tester thinks to you, "Synthetic." [r-1]]=],
    "Unrecognized intentional custom message.",
  }) do
    for _,category in ipairs({"PRIVATE","WHISPER"}) do
      local value={category=category,source="custom",line=line,target="Synthetic Listener",
        message=[[You pick up Tester's Psycian link, "Metadata is not framing."]]}
      eq(Channels.entryCategory(value),category)
      eq(Channels.project(value),value)
    end
  end
  for _,category in ipairs({"ROOM","STAFF","QUEST","LINK","LINK VIEW"}) do
    eq(Channels.entryCategory({category=category,line=[[You pick up Tester's Psycian link, "Synthetic."]]}),category)
  end
  eq(Channels.entryCategory({category="PRIVATE",source="gmcp",target="Tester",
    message=[[Tester (ESP): "Metadata only."]]}),"PRIVATE")
end)

local function entry(category,line) return {category=category,line=line,message="hello",speaker="Tester"} end
test("PRIVATE accepts only whispers and explicitly direct mental conversations",function()
  eq(Channels.inPrivate(nil),false); eq(Channels.inPrivate("MENTAL"),false)
  for _,category in ipairs({"MENTAL","CONTACT","ESP"}) do
    local direct=entry(category,'Tester thinks to you, "hello"')
    eq(Channels.inPrivate(direct),true); eq(direct.category,category)
    eq(Channels.inPrivate(entry(category,'\27[35m\7Tester thinks to you, "hello"\27[0m')),true)
  end
  eq(Channels.inPrivate(entry("WHISPER",'Tester whispers to you, "hello"')),true)
  eq(Channels.inPrivate(entry("WHISPER",'You whisper to Tester, "hello"')),true)
  for _,category in ipairs({"ROOM","OWN","STAFF","COMBAT","WORLD","DRAGON","PSYCIAN","SECIAN"}) do
    eq(Channels.inPrivate(entry(category,'Tester thinks to you, "hello"')),false)
  end
end)

test("PRIVATE never guesses directness from broadcast categories targets or quoted bodies",function()
  for _,line in ipairs({
    'Tester (ESP): "hello"',
    'You pick up Tester\'s thoughts, "hello" [r-1]',
    'You pick up Tester\'s thoughts echoing through the area, "hello"',
    'You pick up Tester\'s mental link, "hello" [r-1]',
    'Listener picks up Tester\'s mental link, "hello"',
    'You pick up Tester\'s Dragon link, "hello" [r-1]',
    'You pick up Tester\'s Psycian link, "hello" [r-1]',
    'You pick up Tester\'s Secian link, "hello" [r-1]',
    'Say: Tester thinks to you, "hello"',
    'Tester (ESP): "Someone thinks to you, hello"',
    'Tester thinks to you, "hello" [r-1]',
    'Tester thinks to you, "hello"\nAnother line',
  }) do
    for _,category in ipairs({"MENTAL","CONTACT","ESP"}) do
      local value=entry(category,line); value.target="Current Character"
      eq(Channels.inPrivate(value),false)
    end
  end
  eq(Channels.inPrivate({category="CONTACT",message='Tester thinks to you, "hello"'}),false)
end)

test("outgoing named contacts are PRIVATE but all and room remain broadcasts",function()
  for _,target in ipairs({"Tester","O'Brien","Target-Name","Player_2"}) do
    local value={category="MENTAL",source="outgoing",target=target}
    eq(Channels.inPrivate(value),true); eq(value.target,target)
  end
  for _,target in ipairs({"all","ALL","room","Room","","a b","bad\nname","bad;command",string.rep("a",65)}) do
    eq(Channels.inPrivate({category="MENTAL",source="outgoing",target=target}),false)
  end
  eq(Channels.inPrivate({category="MENTAL",source="outgoing"}),false)
  eq(Channels.inPrivate({category="MENTAL",source="gmcp",target="Tester"}),false)
  eq(Channels.inPrivate({category="STAFF",source="outgoing",target="Tester"}),false)
end)

test("combined LINK uses a reserved filter alongside personal LINK and LINK VIEW",function()
  local separate={"ALL","STAFF","PSYCIAN","ROOM","MENTAL","DRAGON","SECIAN","LINK","LINK VIEW","QUEST"}
  local combined,ok=Channels.combinedOrder(separate,{"LINK","LINK VIEW","QUEST"})
  eq(Channels.linkFilter,"@LINK"); eq(ok,true)
  eq(table.concat(combined,","),"ALL,STAFF,@LINK,ROOM,LINK,LINK VIEW,QUEST")
  eq(table.concat(separate,","),"ALL,STAFF,PSYCIAN,ROOM,MENTAL,DRAGON,SECIAN,LINK,LINK VIEW,QUEST")
  local reordered=Channels.combinedOrder(separate,{"LINK","LINK VIEW","QUEST"},{"QUEST","LINK VIEW","ALL"})
  eq(table.concat(reordered,","),"QUEST,@LINK,ALL,STAFF,ROOM,LINK,LINK VIEW")
  local current=Channels.combinedOrder(separate,{"LINK","LINK VIEW","QUEST"},{"LINK VIEW","QUEST","@LINK","ALL"})
  eq(table.concat(current,","),"LINK VIEW,QUEST,@LINK,ALL,STAFF,ROOM,LINK")
end)

test("only combined order migration maps the legacy virtual name and remains idempotent",function()
  local legacy={"STAFF","LINK VIEW","ALL","CONTACT","LINK","LINK VIEW"}
  eq(table.concat(Channels.tabOrder(legacy),","),"STAFF,LINK VIEW,ALL,MENTAL,LINK")
  local migrated=Channels.combinedTabOrder(legacy)
  eq(table.concat(migrated,","),"STAFF,@LINK,ALL,MENTAL,LINK")
  eq(table.concat(Channels.combinedTabOrder(migrated),","),table.concat(migrated,","))
  eq(table.concat(legacy,","),"STAFF,LINK VIEW,ALL,CONTACT,LINK,LINK VIEW")
  local current={"LINK VIEW"," @link ","LINK","ALL"}
  eq(table.concat(Channels.combinedTabOrder(current),","),"LINK VIEW,@LINK,LINK,ALL")
  eq(table.concat(Channels.tabOrder({"@LINK","@OTHER","LINK VIEW","@link","OWN","WHISPER"}),","),"@LINK,LINK VIEW")
  eq(Channels.category("LINK VIEW"),"LINK VIEW")
end)

test("MENTAL wire families stay distinct without guessing from message bodies",function()
  for _,row in ipairs({
    {'Tester (ESP): "hello"',"esp","broadcast"},
    {'Tester thinks to you, "hello"',"contact","direct"},
    {'You pick up Tester\'s thoughts, "hello" [r-1]',"contact"},
    {'You pick up Tester\'s thoughts echoing through the area, "hello"',"contact"},
    {'You pick up Tester\'s mental link, "hello" [r-1]',"link"},
    {'Listener picks up Tester\'s mental link, "hello"',"link"},
  }) do
    local kind,audience=Channels.mentalKind(entry("MENTAL",row[1]))
    eq(kind,row[2]); eq(audience,row[3] or "broadcast")
    local coloredKind,coloredAudience=Channels.mentalKind(entry("MENTAL","\27[35m"..row[1].."\27[0m"))
    eq(coloredKind,row[2]); eq(coloredAudience,row[3] or "broadcast")
  end
  eq(Channels.mentalKind(entry("ESP","hello")),"esp")
  eq(Channels.mentalKind(entry("CONTACT","hello")),"contact")
  eq(Channels.mentalKind(entry("MENTAL","hello")),nil)
  local _,legacyAudience=Channels.mentalKind(entry("CONTACT","hello")); eq(legacyAudience,nil)
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
