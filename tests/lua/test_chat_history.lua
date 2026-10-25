local History=require("chat_history")
local Channels=require("chat_channels")

for _,mode in ipairs({"append","hydrate"}) do
  test(mode.." partitions mislabeled PRIVATE broadcasts from direct contacts and preserves raw history",function()
    local rows={
      {[[Tester (ESP): "Synthetic ESP."]],"MENTAL"},
      {[=[You pick up Tester's thoughts, "Synthetic global." [r-1]]=],"MENTAL"},
      {[[You pick up Tester's thoughts echoing through the area, "Synthetic room."]],"MENTAL"},
      {[[You pick up Tester's mental link, "Synthetic generic."]],"MENTAL"},
      {[[Listener picks up Tester's mental link, "Synthetic observed."]],"MENTAL"},
      {[=[You pick up Tester's Psycian link, "Synthetic racial." [r-1]]=],"PSYCIAN"},
      {[[You pick up Tester's Dragon link, "Synthetic racial."]],"DRAGON"},
      {[[You pick up Tester's Secian link, "Synthetic racial."]],"SECIAN"},
    }
    local history=History.new(100,0); local entries,expected,originals={},{},{}
    local function add(value,category)
      value.schema=1; value.timestamp="2026-10-24T12:00:00Z"; value.character="Synthetic Keeper"
      value.message="Synthetic fixture "..(#entries+1); value.speaker="Tester"
      entries[#entries+1]=value; expected[#entries]=category
      originals[#entries]={}; for key,item in pairs(value) do originals[#entries][key]=item end
    end
    for _,category in ipairs({"PRIVATE","WHISPER"}) do
      for _,source in ipairs({"builtin","gmcp","custom"}) do
        for _,row in ipairs(rows) do add({category=category,source=source,line=row[1]},row[2]) end
      end
    end
    local broadcastCount=#entries
    for _,category in ipairs({"PRIVATE","WHISPER","CONTACT","MENTAL","ESP"}) do
      add({category=category,source="builtin",line=[[Tester thinks to you, "Synthetic direct."]]},"MENTAL")
    end
    add({category="WHISPER",source="builtin",line=[[Tester whispers to you, "Synthetic quiet."]]},"WHISPER")
    add({category="MENTAL",source="outgoing",target="Tester"},"MENTAL")
    add({category="PRIVATE",source="custom",line=[[Tester says, "You pick up Other's Dragon link, 'Quoted.'"]]},"PRIVATE")
    add({category="PRIVATE",source="custom",line="Intentional custom private message."},"PRIVATE")
    if mode=="hydrate" then assert(history:hydrate(entries))
    else for index,value in ipairs(entries) do assert(history:append(value,index*4)) end end
    local lastKey,lastEpoch=history.lastKey,history.lastEpoch
    local hidden={MENTAL=false,PSYCIAN=false,DRAGON=false,SECIAN=false,WHISPER=false,PRIVATE=false}
    local private=history:entries("PRIVATE",hidden)
    local links=history:entries(Channels.linkFilter,hidden,true)
    eq(#links,broadcastCount); eq(#private,#entries-broadcastCount)
    eq(#history:entries(Channels.linkFilter,hidden,false),0)
    eq(#history:entries("ALL"),#entries); eq(#history:entries("ALL",hidden),0)
    local seen={}
    for index,value in ipairs(links) do
      eq(value.message,entries[index].message); eq(value.category,expected[index])
      eq(value.line,entries[index].line); eq(value.source,entries[index].source)
      eq(seen[value.message],nil); seen[value.message]="LINK"
    end
    for index,value in ipairs(private) do
      local rawIndex=broadcastCount+index
      eq(value.message,entries[rawIndex].message); eq(value.category,expected[rawIndex])
      eq(seen[value.message],nil); seen[value.message]="PRIVATE"
    end
    for index,value in ipairs(entries) do
      eq(history.items[index],value)
      for key,item in pairs(originals[index]) do eq(value[key],item) end
      for key,item in pairs(value) do eq(originals[index][key],item) end
    end
    eq(#history.items,#entries); eq(history.lastKey,lastKey); eq(history.lastEpoch,lastEpoch)
  end)
end


-- Policy fixtures are synthetic; no profile data or real conversations are used.
test("PRIVATE accepts whispers and exact incoming direct frames without matching metadata",function()
  eq(Channels.inPrivate(nil),false); eq(Channels.inPrivate(false),false)
  eq(Channels.inPrivate("Lark thinks to you, \"Synthetic.\""),false)
  for _,entry in ipairs({
    {category=" whisper ",message="Synthetic whisper."},
    {category="MENTAL",line='Lark thinks to you, "Synthetic."'},
    {category="CONTACT",speaker="Different fixture",message="Unrelated metadata.",
      line='Nera O\'Vale thinks to you, "Synthetic."'},
    {category="ESP",source="custom",line=' \t\7\27[35mNera_O\'Vale thinks to you, "Synthetic."\27[0m\7 '},
  }) do
    local category,line,message,speaker,source=entry.category,entry.line,entry.message,entry.speaker,entry.source
    eq(Channels.inPrivate(entry),true)
    eq(entry.category,category); eq(entry.line,line); eq(entry.message,message)
    eq(entry.speaker,speaker); eq(entry.source,source)
  end
end)

test("PRIVATE rejects generic broadcast racial quoted malformed and multiline mental frames",function()
  local lines={
    'Lark (ESP): "Synthetic."',
    'You pick up Lark\'s thoughts, "Synthetic." [r-1]',
    'You pick up Lark\'s thoughts echoing through the area, "Synthetic."',
    'You pick up Lark\'s mental link, "Synthetic."',
    'Listener picks up Lark\'s mental link, "Synthetic." [r-1]',
    'You pick up Lark\'s Dragon link, "Synthetic."',
    'You pick up Lark\'s Psycian link, "Synthetic."',
    'You pick up Lark\'s Secian link, "Synthetic." [r-1]',
    'Lark thinks to you, "Synthetic." [r-1]',
    'Lark thinks to you, "Synthetic.',
    'Lark thinks to You, "Synthetic."',
    'Say: Lark thinks to you, "Synthetic."',
    'Lark says, "Nera thinks to you, \\"Synthetic.\\""',
    'Lark thinks to you, "Synthetic.\nSecond line."',
    'Lark thinks to you, "Synthetic.\rSecond line."',
    'Lark thinks to you, "Synthetic.\0Hidden text."',
  }
  for _,category in ipairs({"ESP","CONTACT","MENTAL","DRAGON","PSYCIAN","SECIAN"}) do
    eq(Channels.inPrivate({category=category,target="Synthetic",message='Lark thinks to you, "Synthetic."'}),false)
    for _,line in ipairs(lines) do
      eq(Channels.inPrivate({category=category,target="Synthetic",line=line,source="builtin"}),false)
    end
  end
  for _,category in ipairs({"ROOM","OWN","STAFF","QUEST"}) do
    eq(Channels.inPrivate({category=category,line='Lark thinks to you, "Quoted fixture."'}),false)
  end
end)

test("PRIVATE outgoing proof requires MENTAL outgoing source and a valid named target",function()
  for _,target in ipairs({"Lark","Nera_O'Vale","Synthetic-Target",string.rep("A",64)}) do
    eq(Channels.inPrivate({category="MENTAL",source="outgoing",target=target}),true)
    eq(Channels.inPrivate({category="MENTAL",source="builtin",target=target}),false)
    eq(Channels.inPrivate({category="MENTAL",source="custom",target=target}),false)
    eq(Channels.inPrivate({category="DRAGON",source="outgoing",target=target}),false)
  end
  eq(Channels.inPrivate({category="MENTAL",source="outgoing"}),false)
  for _,target in ipairs({"all","ALL","room","RoOm",""," Lark","Lark ","Lark North","1Lark",
    "Lark\n","Lark\7","<Lark>",string.rep("A",65),false,123,{}}) do
    eq(Channels.inPrivate({category="MENTAL",source="outgoing",target=target,
      line='Lark thinks to you, "Incoming-looking fixture."'}),false)
  end
end)

for _,mode in ipairs({"append","hydrate"}) do
  test(mode.." partitions direct PRIVATE and broadcast LINK while preserving raw records and ALL sources",function()
    local entries={
      {category="WHISPER",message="Synthetic whisper."},
      {category="CONTACT",line='Lark thinks to you, "Synthetic direct."'},
      {category="ESP",line='\7\27[35mNera O\'Vale thinks to you, "Synthetic legacy direct."\27[0m'},
      {category="MENTAL",source="outgoing",target="Lark",message="Synthetic named request."},
      {category="MENTAL",source="outgoing",target="all",message="Synthetic global request."},
      {category="MENTAL",source="outgoing",target="room",message="Synthetic room request."},
      {category="ESP",line='Lark (ESP): "Synthetic global."'},
      {category="CONTACT",line='You pick up Lark\'s thoughts, "Synthetic global thoughts." [r-1]'},
      {category="DRAGON",line='You pick up Lark\'s Dragon link, "Synthetic racial."'},
      {category="PSYCIAN",line='You pick up Lark\'s Psycian link, "Synthetic racial."'},
      {category="SECIAN",line='You pick up Lark\'s Secian link, "Synthetic racial."'},
      {category="MENTAL",message="Synthetic unknown frame."},
      {category="ROOM",message="Synthetic nearby."},
    }
    local history=History.new(20,3); local raw={}
    for index,entry in ipairs(entries) do
      entry.schema=1; entry.timestamp="2026-10-15T12:00:00Z"; entry.character="Synthetic Keeper"
      entry.message=entry.message or ("Synthetic fixture "..index)
      raw[index]={}; for key,value in pairs(entry) do raw[index][key]=value end
    end
    if mode=="hydrate" then assert(history:hydrate(entries))
    else for index,entry in ipairs(entries) do eq(history:append(entry,index*4),true) end end
    local lastKey,lastEpoch=history.lastKey,history.lastEpoch
    local hidden={ROOM=false,WHISPER=false,MENTAL=false,DRAGON=false,PSYCIAN=false,SECIAN=false}
    eq(#history:entries("ALL",hidden),0); eq(#history:entries("ALL"),#entries)
    eq(#history:entries("MENTAL",hidden),8)
    for _,category in ipairs({"DRAGON","PSYCIAN","SECIAN","WHISPER","ROOM"}) do
      eq(#history:entries(category,hidden),1)
    end
    local private=history:entries("PRIVATE",hidden)
    local link=history:entries(Channels.linkFilter,hidden,true)
    eq(#private,4); eq(#link,8); eq(#history:entries(Channels.linkFilter,hidden,false),0)
    for index,entry in ipairs(private) do
      eq(entry.line,entries[index].line); eq(entry.message,entries[index].message)
      eq(entry.source,entries[index].source); eq(entry.target,entries[index].target)
    end
    for index,entry in ipairs(link) do
      eq(entry.line,entries[index+4].line); eq(entry.message,entries[index+4].message)
      eq(entry.source,entries[index+4].source); eq(entry.target,entries[index+4].target)
    end
    local mentalOnly=history:entries("ALL",{ROOM=false,WHISPER=false,MENTAL=true,DRAGON=false,PSYCIAN=false,SECIAN=false})
    eq(#mentalOnly,8)
    for index=2,8 do
      eq(mentalOnly[index-1].message,entries[index].message)
    end
    eq(mentalOnly[8].message,entries[12].message)
    eq(#history.items,#entries)
    for index,entry in ipairs(entries) do
      eq(history.items[index],entry)
      for key,value in pairs(raw[index]) do eq(entry[key],value) end
      for key,value in pairs(entry) do eq(raw[index][key],value) end
    end
    eq(history.lastKey,lastKey); eq(history.lastEpoch,lastEpoch)
  end)
end


test("WORLD has a dedicated retention bucket and remains visible in its own tab when hidden in ALL",function()
  local history=History.new(3,3)
  local arrival={category="WORLD",speaker="Obatalla Ogoun",message="just arrived in the world."}
  local departure={category="WORLD",speaker="Obatalla Ogoun",message="has left the world."}
  eq(History.retentionKey(arrival),"WORLD"); eq(History.retentionKey({category=" world "}),"WORLD")
  eq(history:append(arrival,100),true); eq(history:append(arrival,101),false)
  eq(history:append(departure,104),true)
  eq(#history:entries("ALL",{WORLD=false}),0); eq(#history:entries("WORLD",{WORLD=false}),2)
  eq(#history:entries("PRIVATE"),0); eq(#history:entries("ROOM"),0)
  eq(history:entries("WORLD")[1],arrival); eq(history:entries("WORLD")[2],departure)
  eq(#history:entries("ALL",{WORLD=true}),2); eq(#history.items,2)
  eq(table.concat(history:categories(),","),"WORLD")
end)

for _,mode in ipairs({"append","hydrate"}) do
  test(mode.." keeps WORLD independent of COMBAT and the shared custom category bucket",function()
    local history=History.new(3,0)
    local entries={{category="WORLD",speaker="Obatalla Ogoun",message="just arrived in the world."},
      {category="STAFF",message="protected staff"}}
    for index=1,7 do
      entries[#entries+1]={category="COMBAT",message="combat-"..index}
      entries[#entries+1]={category="CUSTOM_"..index,message="custom-"..index}
    end
    if mode=="hydrate" then assert(history:hydrate(entries))
    else for index,entry in ipairs(entries) do eq(history:append(entry,index*4),true) end end
    eq(#history:entries("WORLD"),1); eq(history:entries("WORLD")[1],entries[1])
    eq(history.retentionCounts.WORLD,1); eq(history.retentionCounts.OTHER,3); eq(history.retentionCounts.COMBAT,3)
    for index=1,7 do eq(history:append({category="WORLD",speaker="Traveler-"..index,message="has left the world."},100+index*4),true) end
    eq(#history:entries("WORLD"),3); eq(history:entries("WORLD")[1].speaker,"Traveler-5")
    eq(#history:entries("COMBAT"),3); eq(history.retentionCounts.OTHER,3); eq(#history:entries("STAFF"),1)
    eq(#history.items,10); eq(#history:entries("ALL",{WORLD=false,COMBAT=true}),7)
  end)
end
test("deduplicates only identical adjacent entries",function()
  local history=History.new(1000,3)
  local entry={category="MENTAL",speaker="Tekk",message="hello"}
  eq(history:append(entry,100),true)
  eq(history:append(entry,101),false)
  eq(history:append({category="MENTAL",speaker="Gia",message="hello"},102),true)
  eq(history:append(entry,103),true)
end)

test("deduplicates only within the inclusive forward time window",function()
  local entry={category="MENTAL",speaker="Tekk",message="hello"}
  local exact=History.new(10,3)
  eq(exact:append(entry,100),true)
  eq(exact:append(entry,103),false)
  local outside=History.new(10,3)
  eq(outside:append(entry,100),true)
  eq(outside:append(entry,104),true)
  local earlier=History.new(10,3)
  eq(earlier:append(entry,200),true)
  eq(earlier:append(entry,100),true)
end)

test("normalizes every dedupe field while retaining a changed target",function()
  local history=History.new(10,3)
  eq(history:append({category=" mental ",speaker=" Tekk  Prime ",target=" Dace   Alterac ",message=" Hello   there "},100),true)
  eq(history:append({category="MENTAL",speaker="tekk prime",target="dace alterac",message="hello there"},101),false)
  eq(history:append({category="MENTAL",speaker="tekk prime",target="Other",message="hello there"},102),true)
  eq(#history:entries("ALL"),2)
end)

test("retains only the newest visible limit",function()
  local history=History.new(2,3)
  history:append({category="ROOM",message="one"},1)
  history:append({category="ROOM",message="two"},2)
  history:append({category="ROOM",message="three"},3)
  eq(#history:entries("ALL"),2)
  eq(history:entries("ALL")[1].message,"two")
end)

test("hard caps an oversized visible limit at the newest thousand",function()
  local history=History.new(1500,3)
  for index=1,1501 do history:append({category="ROOM",message="line-"..index},index) end
  local entries=history:entries("ALL")
  eq(#entries,1000)
  eq(entries[1].message,"line-502")
  eq(entries[1000].message,"line-1501")
end)
test("new sibling history preserves limits without sharing entries",function()
  local first=History.new(2,4); first:append({category="ROOM",message="first"},1); local second=first:newSibling()
  eq(second.limit,2); eq(second.dedupeSeconds,4); eq(#second:entries(),0); eq(#first:entries(),1)
end)

test("hydrates older entries without duplicating overlap or disturbing live order",function()
  local history=History.new(4,3)
  local overlap={schema=1,timestamp="2026-08-31T12:00:00-04:00",character="Dace Alterac",category="MENTAL",speaker="Tekk",message="overlap",line='Tekk (ESP): "overlap"',source="builtin"}
  history:append(overlap,100)
  history:append({schema=1,timestamp="2026-08-31T13:00:00-04:00",character="Unknown",category="QUEST",message="live",line="live",source="custom"},104)
  history:hydrate({
    {schema=1,timestamp="2026-08-31T11:00:00-04:00",character="Dace Alterac",category="ROOM",speaker="Gia",message="older",line='Gia says, "older"',source="builtin"},
    overlap,
  })
  local entries=history:entries("ALL")
  eq(#entries,3)
  eq(entries[1].message,"older")
  eq(entries[2].message,"overlap")
  eq(entries[3].message,"live")
  eq(table.concat(history:categories(),","),"ROOM,MENTAL,QUEST")
end)

test("filters direct private messages and preserves category insertion order",function()
  local history=History.new(10,3)
  history:append({category="ROOM",message="room"},1)
  history:append({category="WHISPER",message="whisper"},2)
  history:append({category="MENTAL",message="esp"},3)
  history:append({category="DRAGON",message="dragon"},4)
  history:append({category="SECIAN",message="secian"},5)
  history:append({category="PSYCIAN",message="contact"},6)
  history:append({category="STAFF",message="staff"},7)
  eq(#history:entries("PRIVATE"),1)
  eq(history:entries("PRIVATE")[1].message,"whisper")
  local categories=history:categories()
  eq(categories[1],"ROOM")
  eq(categories[7],"STAFF")
end)

test("room filter includes both nearby speakers and the active character",function()
  local history=History.new(10,3)
  history:append({category="ROOM",message="Gia asks Dace"},1)
  history:append({category="OWN",message="Dace answers Gia"},2)
  history:append({category="MENTAL",message="remote"},3)
  local entries=history:entries("ROOM")
  eq(#entries,2); eq(entries[1].category,"ROOM"); eq(entries[2].category,"OWN")
  eq(#history:entries("PRIVATE"),0)
end)

test("ALL source settings hide only selected categories and map OWN to ROOM",function()
  local history=History.new(10,3)
  for index,category in ipairs({"ROOM","OWN","WHISPER","MENTAL","COMBAT","QUEST"}) do history:append({category=category,message=category},index) end
  local sources={ROOM=false,WHISPER=true,MENTAL=true,COMBAT=false}
  local entries=history:entries("ALL",sources)
  eq(#entries,3); eq(entries[1].category,"WHISPER"); eq(entries[2].category,"MENTAL"); eq(entries[3].category,"QUEST")
  eq(#history:entries("ROOM",sources),2); eq(#history:entries("COMBAT",sources),1); eq(#history:entries("PRIVATE",sources),1)
end)

test("ALL source visibility changes never remove stored entries or category filters",function()
  local history=History.new(20,3)
  local categories={"COMBAT","ROOM","OWN","WHISPER","MENTAL","DRAGON","SECIAN","PSYCIAN","STAFF","QUEST"}
  local entries={}; local sources={}
  for index,category in ipairs(categories) do
    local entry={category=category,message=category=="COMBAT" and "Your head takes 8 points of impact damage!" or category}
    entries[index]=entry; sources[category]=false; eq(history:append(entry,index),true)
  end
  local lastKey,lastEpoch=history.lastKey,history.lastEpoch
  eq(#history:entries("ALL",sources),0)
  for index,category in ipairs(categories) do
    local source=category=="OWN" and "ROOM" or category
    local filtered=history:entries(category,sources)
    eq(#filtered,category=="ROOM" and 2 or 1); eq(filtered[1],entries[index])
    if category=="ROOM" then eq(filtered[2],entries[3]) end
    sources[source]=true
    local visible=history:entries("ALL",sources)
    eq(#visible,source=="ROOM" and 2 or 1)
    if source=="ROOM" then eq(visible[1],entries[2]); eq(visible[2],entries[3]) else eq(visible[1],entries[index]) end
    sources[source]=false; eq(#history:entries("ALL",sources),0)
  end
  eq(#history:entries("PRIVATE",sources),1); eq(#history.items,#entries)
  for index,entry in ipairs(entries) do eq(history.items[index],entry) end
  eq(table.concat(history:categories(),","),table.concat(categories,","))
  eq(history.lastKey,lastKey); eq(history.lastEpoch,lastEpoch)
  eq(#history:entries("ALL"),#entries)
end)

test("hidden COMBAT entries appended before and after live toggles keep their order and dedupe",function()
  local history=History.new(10,3); local sources={COMBAT=false}
  local first={category="COMBAT",message="Your head takes 8 points of impact damage!"}
  local second={category="COMBAT",message="The dark hound claws at you!"}
  eq(history:append(first,100),true); eq(#history:entries("ALL",sources),0)
  sources.COMBAT=true; eq(history:entries("ALL",sources)[1],first)
  eq(history:append(second,104),true); eq(#history:entries("ALL",sources),2)
  local lastKey,lastEpoch=history.lastKey,history.lastEpoch
  sources.COMBAT=false; eq(#history:entries("ALL",sources),0)
  eq(#history:entries("COMBAT",sources),2)
  eq(history:append(second,105),false); eq(history.lastKey,lastKey); eq(history.lastEpoch,lastEpoch)
  eq(history:append(first,108),true); eq(#history:entries("ALL",sources),0)
  sources.COMBAT=true
  for _,filter in ipairs({"ALL","COMBAT"}) do
    local entries=history:entries(filter,sources)
    eq(#entries,3); eq(entries[1],first); eq(entries[2],second); eq(entries[3],first)
  end
  eq(table.concat(history:categories(),","),"COMBAT")
end)

test("hydration retains hidden source overlap and future live entries",function()
  local history=History.new(10,3); local sources={COMBAT=false,ROOM=false,MENTAL=false,STAFF=false}
  local damage={schema=1,timestamp="2026-08-31T12:00:00-04:00",category="COMBAT",message="Your head takes 8 points of impact damage!",source="builtin"}
  local room={schema=1,timestamp="2026-08-31T12:01:00-04:00",category="ROOM",message="nearby",source="builtin"}
  local esp={schema=1,timestamp="2026-08-31T12:02:00-04:00",category="MENTAL",message="private",source="builtin"}
  local staff={schema=1,timestamp="2026-08-31T12:03:00-04:00",category="STAFF",message="staff",source="builtin"}
  eq(history:append(esp,100),true); eq(history:append(staff,104),true)
  local lastKey,lastEpoch=history.lastKey,history.lastEpoch
  assert(history:hydrate({damage,room,esp})); eq(#history:entries("ALL",sources),0)
  local expected={damage,room,esp,staff}
  eq(#history.items,#expected)
  for index,entry in ipairs(expected) do
    eq(history.items[index],entry); eq(history:entries(entry.category,sources)[1],entry)
  end
  eq(table.concat(history:categories(),","),"COMBAT,ROOM,MENTAL,STAFF")
  eq(history.lastKey,lastKey); eq(history.lastEpoch,lastEpoch); eq(history:append(staff,105),false)
  local attack={category="COMBAT",message="The dark hound claws at you!",source="builtin"}
  eq(history:append(attack,108),true); eq(#history:entries("ALL",sources),0)
  sources.COMBAT=true
  local visible=history:entries("ALL",sources)
  eq(#visible,2); eq(visible[1],damage); eq(visible[2],attack)
  eq(#history.items,5); eq(#history:entries("PRIVATE",sources),0)
end)

test("clears only the visible in-memory history and resets dedupe state",function()
  local history=History.new(10,3)
  local entry={category="MENTAL",speaker="Tekk",message="repeatable"}
  assert(history:append(entry,100)); assert(history:append({category="ROOM",message="nearby"},104))
  eq(history:clearVisible(),2)
  eq(#history:entries("ALL"),0); eq(#history:categories(),0); eq(history.lastKey,nil); eq(history.lastEpoch,nil)
  eq(history:append(entry,100),true); eq(#history:entries("ALL"),1)
end)

-- Retention fixtures are synthetic and never read a Mudlet profile or chat log.
local retentionBuckets={"ROOM","WHISPER","ESP","DRAGON","SECIAN","CONTACT","MENTAL","PSYCIAN","STAFF","COMBAT","WORLD","ALL","OTHER"}

local function retentionFixture(limit)
  local entries,expected={},{}
  for index=1,limit+2 do
    for _,bucket in ipairs(retentionBuckets) do
      local category=bucket
      if bucket=="ROOM" and index%2==0 then category="OWN" end
      if bucket=="OTHER" then category="SYNTHETIC_"..index end
      local entry={schema=1,timestamp="2026-10-04T00:00:00Z",character="SyntheticAlpha",
        category=category,message="synthetic-"..bucket.."-"..index,source="custom"}
      entries[#entries+1]=entry
      if index>2 then expected[#expected+1]=entry end
    end
  end
  return entries,expected
end

local function sameRetained(actual,expected)
  eq(#actual,#expected)
  for index,entry in ipairs(expected) do
    eq(actual[index].category,Channels.entryCategory(entry))
    eq(actual[index].message,entry.message)
  end
end

for _,mode in ipairs({"append","hydrate"}) do
  test(mode.." returns every matching direct entry above the per-source limit without changing retention",function()
    local entries,retained=retentionFixture(3)
    for _,entry in ipairs(entries) do
      if entry.category=="CONTACT" then entry.line='SyntheticContact thinks to you, "'..entry.message..'"' end
    end
    local history=History.new(3,3)
    if mode=="hydrate" then assert(history:hydrate(entries))
    else for index,entry in ipairs(entries) do eq(history:append(entry,index*4),true) end end
    sameRetained(history:entries("ALL"),retained); eq(#history.items,39)
    local expected={}
    for _,entry in ipairs(retained) do
      if entry.category=="WHISPER" or entry.category=="CONTACT" then expected[#expected+1]=entry end
    end
    sameRetained(history:entries("PRIVATE"),expected); eq(#expected,6)
    eq(#history:entries(Channels.linkFilter,nil,true),15)
    for _,bucket in ipairs(retentionBuckets) do eq(history.retentionCounts[bucket],3) end
    for index,entry in ipairs(retained) do eq(history.items[index],entry) end
  end)
end

test("retention exposes a thousand-entry bucket cap and thirteen-thousand-entry total bound",function()
  eq(History.MAX_ENTRIES,1000)
  eq(History.MAX_RETAINED_ENTRIES,13000)
end)

for _,mode in ipairs({"append","hydrate"}) do
  for _,requestedLimit in ipairs({1,3,1500}) do
    test(mode.." retains the newest entries in EACH fixed bucket at limit "..requestedLimit,function()
      local limit=math.min(requestedLimit,1000)
      local history=History.new(requestedLimit,3)
      local entries,expected=retentionFixture(limit)
      if mode=="hydrate" then assert(history:hydrate(entries))
      else for index,entry in ipairs(entries) do eq(history:append(entry,index*4),true) end end
      eq(history.limit,limit)
      sameRetained(history:entries("ALL"),expected)
      eq(#history.items,13*limit)
      assert(#history.items<=History.MAX_RETAINED_ENTRIES)
      for _,category in ipairs({"ROOM","WHISPER","DRAGON","SECIAN","PSYCIAN","STAFF","COMBAT","WORLD"}) do
        eq(#history:entries(category),limit)
      end
      for _,category in ipairs({"MENTAL","ESP","CONTACT"}) do eq(#history:entries(category),3*limit) end
      -- Generic mental/racial fixtures remain retained; only WHISPER is direct.
      eq(#history:entries("PRIVATE"),limit)
      eq(#history:entries(Channels.linkFilter,nil,true),6*limit)
      local notices=0
      for _,entry in ipairs(history:entries("ALL")) do
        if entry.category=="ALL" then notices=notices+1 end
      end
      eq(notices,limit)
      eq(#history:entries("SYNTHETIC_1"),0)
      eq(#history:entries("SYNTHETIC_"..(limit+2)),1)
    end)
  end

  test(mode.." makes OWN consume ROOM quota while independent STAFF survives",function()
    local history=History.new(3,3)
    local entries={
      {category="ROOM",message="synthetic-room-old"},
      {category="OWN",message="synthetic-own-old"},
      {category="STAFF",message="synthetic-staff"},
      {category="ROOM",message="synthetic-room-middle"},
      {category="OWN",message="synthetic-own-middle"},
      {category="ROOM",message="synthetic-room-new"},
      {category="OWN",message="synthetic-own-new"},
    }
    if mode=="hydrate" then assert(history:hydrate(entries))
    else for index,entry in ipairs(entries) do assert(history:append(entry,index*4)) end end
    sameRetained(history:entries("ALL"),{entries[3],entries[5],entries[6],entries[7]})
    sameRetained(history:entries("ROOM"),{entries[5],entries[6],entries[7]})
    sameRetained(history:entries("OWN"),{entries[5],entries[7]})
  end)

  test(mode.." bounds custom unknown PRIVATE OTHER empty and missing categories together",function()
    local history=History.new(3,3)
    local entries={{category="STAFF",message="synthetic-protected-staff"}}
    for index=1,1005 do
      local category="SYNTHETIC_CATEGORY_"..index
      if index==1001 then category="PRIVATE"
      elseif index==1002 then category="OTHER"
      elseif index==1003 then category=""
      elseif index==1004 then category=nil end
      entries[#entries+1]={category=category,message="synthetic-other-"..index}
    end
    if mode=="hydrate" then assert(history:hydrate(entries))
    else for index,entry in ipairs(entries) do assert(history:append(entry,index*4)) end end
    sameRetained(history:entries("ALL"),{entries[1],entries[1004],entries[1005],entries[1006]})
    eq(#history:entries("STAFF"),1)
    eq(#history:entries("SYNTHETIC_CATEGORY_1"),0)
    eq(#history:entries("PRIVATE"),0)
    eq(#history:entries("OTHER"),0)
  end)
end

test("more than a thousand hidden COMBAT entries retain earlier conversations and ALL notices",function()
  local history=History.new(1000,3)
  local conversations={}
  for index,category in ipairs({"ROOM","OWN","WHISPER","ESP","DRAGON","SECIAN","CONTACT","STAFF","ALL","SYNTHETIC"}) do
    conversations[index]={category=category,message="synthetic-saved-"..category}
    assert(history:append(conversations[index],index*4))
  end
  for index=1,1005 do assert(history:append({category="COMBAT",message="synthetic-combat-"..index},100+index*4)) end
  local sources={COMBAT=false}
  sameRetained(history:entries("ALL",sources),conversations)
  eq(#history:entries("ALL"),1010)
  local combat=history:entries("COMBAT",sources)
  eq(#combat,1000); eq(combat[1].message,"synthetic-combat-6"); eq(combat[1000].message,"synthetic-combat-1005")
  sources.COMBAT=true; eq(#history:entries("ALL",sources),1010)
  sources.COMBAT=false; sameRetained(history:entries("ALL",sources),conversations)
end)

test("hydrating every bucket deduplicates saved overlap preserves live dedupe and trims within each bucket",function()
  local history=History.new(3,3)
  local saved,expected=retentionFixture(3)
  local live={category="STAFF",message="synthetic-live-staff"}
  assert(history:append(live,100))
  local lastKey,lastEpoch=history.lastKey,history.lastEpoch
  saved[#saved+1]=saved[#saved]
  assert(history:hydrate(saved))
  -- The live STAFF entry replaces only the oldest of the three saved STAFF entries.
  local merged={}
  for _,entry in ipairs(expected) do
    if entry.message~="synthetic-STAFF-3" then merged[#merged+1]=entry end
  end
  merged[#merged+1]=live
  sameRetained(history:entries("ALL"),merged)
  assert(history:hydrate(saved)); sameRetained(history:entries("ALL"),merged)
  eq(history.lastKey,lastKey); eq(history.lastEpoch,lastEpoch)
  eq(history:append(live,103),false); sameRetained(history:entries("ALL"),merged)
  local nextStaff={category="STAFF",message="synthetic-next-staff"}
  eq(history:append(nextStaff,104),true)
  local newestSavedStaff
  for _,entry in ipairs(expected) do if entry.category=="STAFF" then newestSavedStaff=entry end end
  sameRetained(history:entries("STAFF"),{newestSavedStaff,live,nextStaff})
  eq(#history:entries("ALL"),39)
end)

test("clearing all retained buckets resets their quotas dedupe and sibling state",function()
  local history=History.new(3,4)
  local entries,expected=retentionFixture(3)
  assert(history:hydrate(entries))
  local sibling=history:newSibling()
  eq(sibling.limit,3); eq(sibling.dedupeSeconds,4); eq(#sibling:entries(),0)
  eq(history:clearVisible(),39)
  eq(#history:entries(),0); eq(#history:categories(),0)
  eq(history.lastKey,nil); eq(history.lastEpoch,nil)
  for index,entry in ipairs(expected) do assert(history:append(entry,index*4)) end
  sameRetained(history:entries(),expected)
  eq(history:append(expected[#expected],#expected*4),false)
  eq(#sibling:entries(),0)
  assert(sibling:append({category="ROOM",message="synthetic-sibling"},200))
  sameRetained(history:entries(),expected)
end)

local function legacyRoutingEntries()
  local cases={
    {raw="ESP",effective="PSYCIAN",line='You pick up Nera O\'Vale\'s Psycian link, "Named fixture." [r-1]'},
    {raw="ESP",effective="MENTAL",line='Lark (ESP): "ESP fixture."'},
    {raw="CONTACT",effective="MENTAL",line='Nera O\'Vale thinks to you, "Contact fixture."'},
    {raw="DRAGON",effective="MENTAL",line='You pick up Lark\'s mental link, "Generic fixture."'},
    {raw="DRAGON",effective="MENTAL",line='Rook picks up Lark\'s mental link, "Third-person fixture." [r-0]'},
    {raw="DRAGON",effective="DRAGON",line='You pick up Rook\'s Dragon link, "Dragon fixture." [r-1]'},
    {raw="SECIAN",effective="SECIAN",line='You pick up Lark\'s Secian link, "Secian fixture."'},
    {raw="ESP",effective="MENTAL",line='Rook says, "You pick up Lark\'s Psycian link, \"Quoted fixture.\""'},
    {raw="DRAGON",effective="DRAGON",line='You pick up Lark\'s mental link, "Malformed fixture." [rank-1]'},
    {raw="ESP",effective="MENTAL",line='You pick up Lark\'s psycian link, "Wrong case fixture."'},
  }
  local entries={}
  for index,case in ipairs(cases) do
    entries[index]={schema=1,timestamp="2026-10-13T12:00:00Z",character="Synthetic Keeper",
      category=case.raw,speaker="Lark",message="Saved fixture "..index,line=case.line,source="builtin",
      metadata={marker="synthetic"}}
  end
  return entries,cases
end

for _,mode in ipairs({"append","hydrate"}) do
  test(mode.." projects legacy history only in views with canonical category deduplication",function()
    local saved,cases=legacyRoutingEntries()
    local history=History.new(1000,3)
    if mode=="hydrate" then assert(history:hydrate(saved))
    else for index,entry in ipairs(saved) do assert(history:append(entry,index*4)) end end
    local visible=history:entries("ALL")
    eq(#visible,#saved)
    for index,entry in ipairs(saved) do
      eq(history.items[index],entry); eq(entry.category,cases[index].raw)
      eq(History.retentionKey(entry),cases[index].raw)
      eq(visible[index].category,cases[index].effective)
      for key,value in pairs(entry) do if key~="category" then eq(visible[index][key],value) end end
      if cases[index].raw~=cases[index].effective then
        assert(visible[index]~=entry)
        visible[index].message="Changed view fixture."
        eq(entry.message,"Saved fixture "..index)
        eq(history:entries("ALL")[index].message,entry.message)
      end
    end
    eq(table.concat(history:categories(),","),"PSYCIAN,MENTAL,DRAGON,SECIAN")
    eq(history.knownCategories.ESP,nil); eq(history.knownCategories.CONTACT,nil)
    for _,filter in ipairs({"MENTAL"," esp ","CONTACT"}) do eq(#history:entries(filter),6) end
    eq(#history:entries("PSYCIAN"),1); eq(#history:entries("DRAGON"),2)
    eq(#history:entries("SECIAN"),1); eq(#history:entries("PRIVATE"),1)
    eq(history:entries("PRIVATE")[1].line,saved[3].line)
    eq(#history:entries(Channels.linkFilter,nil,true),9)
    assert(history:hydrate(saved)); eq(#history.items,#saved)
    for index,entry in ipairs(saved) do eq(history.items[index],entry); eq(entry.category,cases[index].raw) end
  end)
end

test("legacy and new mental retention buckets stay separate through hydrate and live overflow",function()
  local saved={}
  for index=1,4 do
    for _,category in ipairs({"ESP","CONTACT","MENTAL","PSYCIAN"}) do
      saved[#saved+1]={category=category,message=category.."-"..index,line=category.."-"..index}
    end
  end
  local history=History.new(2,0); assert(history:hydrate(saved))
  eq(#history.items,8); eq(#history:entries("MENTAL"),6); eq(#history:entries("PSYCIAN"),2)
  eq(table.concat(history:categories(),","),"MENTAL,PSYCIAN")
  for _,category in ipairs({"ESP","CONTACT","MENTAL","PSYCIAN"}) do eq(history.retentionCounts[category],2) end
  for index=5,8 do assert(history:append({category="MENTAL",message="MENTAL-"..index},index*4)) end
  eq(#history.items,8); eq(#history:entries("MENTAL"),6); eq(#history:entries("PRIVATE"),0)
  eq(#history:entries(Channels.linkFilter,nil,true),8)
  eq(history:entries("MENTAL")[1].message,"ESP-3"); eq(history:entries("MENTAL")[2].message,"CONTACT-3")
  eq(history.retentionCounts.ESP,2); eq(history.retentionCounts.CONTACT,2)
  eq(history.items[1].category,"ESP"); eq(history.items[2].category,"CONTACT")
end)

test("mixed legacy ALL flags merge while explicit MENTAL and PSYCIAN settings win",function()
  local history=History.new(10,0)
  assert(history:append({category="ESP",message="ESP fixture."},1))
  assert(history:append({category="CONTACT",message="Contact fixture."},2))
  assert(history:append({category="MENTAL",message="New mental fixture."},3))
  assert(history:append({category="ESP",message="Named fixture.",line='You pick up Lark\'s Psycian link, "Named fixture."'},4))
  local cases={
    {sources={ESP=false,CONTACT=false},mental=false,psycian=false},
    {sources={ESP=true,CONTACT=false},mental=true,psycian=true},
    {sources={ESP=false,CONTACT=true},mental=true,psycian=false},
    {sources={ESP=false,CONTACT=false,MENTAL=true},mental=true,psycian=false},
    {sources={ESP=true,CONTACT=true,MENTAL=false,PSYCIAN=false},mental=false,psycian=false},
    {sources={ESP=false,CONTACT=false,PSYCIAN=true},mental=false,psycian=true},
  }
  for _,case in ipairs(cases) do
    local expected=(case.mental and 3 or 0)+(case.psycian and 1 or 0)
    eq(#history:entries("ALL",case.sources),expected)
    eq(#history:entries("MENTAL",case.sources),3); eq(#history:entries("PSYCIAN",case.sources),1)
    eq(#history:entries("PRIVATE",case.sources),0); eq(#history.items,4)
    eq(#history:entries(Channels.linkFilter,case.sources,true),4)
  end
end)

test("adjacent legacy and current dedupe keys use effective channels and preserve raw records",function()
  for _,case in ipairs({
    {raw="ESP",effective="MENTAL",line='Lark (ESP): "Same fixture."'},
    {raw="CONTACT",effective="MENTAL",line='Lark thinks to you, "Same fixture."'},
    {raw="DRAGON",effective="MENTAL",line='You pick up Lark\'s mental link, "Same fixture."'},
    {raw="ESP",effective="PSYCIAN",line='You pick up Lark\'s Psycian link, "Same fixture." [r-1]'},
  }) do
    local history=History.new(10,3)
    local raw={category=case.raw,speaker="Lark",message="Same fixture.",line=case.line}
    eq(history:append(raw,100),true)
    eq(history:append({category=case.effective,speaker="lark",message=" same   fixture. ",line=case.line},103),false)
    eq(history.items[1],raw); eq(raw.category,case.raw); eq(history.lastEpoch,100)
    eq(history:append({category=case.effective,speaker="Lark",message="Same fixture.",line=case.line},104),true)
    eq(#history.items,2)
  end
  local history=History.new(10,3)
  eq(history:append({category="MENTAL",speaker="Lark",message="Same fixture."},100),true)
  eq(history:append({category="PSYCIAN",speaker="Lark",message="Same fixture."},101),true)
end)

test("legacy mixed-bucket eviction rebuilds only surviving effective categories",function()
  local history=History.new(1,0)
  assert(history:append({category="ESP",message="Named fixture.",line='You pick up Lark\'s Psycian link, "Named fixture."'},1))
  eq(table.concat(history:categories(),","),"PSYCIAN")
  assert(history:append({category="ESP",message="ESP fixture.",line='Lark (ESP): "ESP fixture."'},2))
  eq(table.concat(history:categories(),","),"MENTAL"); eq(history.knownCategories.PSYCIAN,nil)
  eq(history.retentionCounts.ESP,1); eq(history.items[1].category,"ESP")
end)

test("partial projected overlap prefers saved raw records without rewriting default hydration",function()
  local raw={schema=1,timestamp="2026-10-13T12:00:00Z",category="ESP",speaker="Lark",
    message="Named fixture.",line='You pick up Lark\'s Psycian link, "Named fixture." [r-1]',source="builtin"}
  local projected=Channels.project(raw)
  local history=History.new(10,3); assert(history:hydrate({projected}))
  assert(history:hydrate({raw},true))
  eq(#history.items,1); eq(history.items[1],raw); eq(history.items[1].category,"ESP")
  eq(history:entries("PSYCIAN")[1].category,"PSYCIAN")
  local ordinary=History.new(10,3); assert(ordinary:hydrate({raw,projected}))
  eq(#ordinary.items,2); eq(ordinary.items[1].category,"ESP"); eq(ordinary.items[2].category,"PSYCIAN")
end)

local mentalWireLines={
  esp='Tester (ESP): "hello"',
  contact='Tester thinks to you, "hello"',
  global='You pick up Tester\'s thoughts, "hello" [r-1]',
  room='You pick up Tester\'s thoughts echoing through the area, "hello"',
  link='You pick up Tester\'s mental link, "hello"',
}
local function mentalWireEntry(kind,category)
  return {category=category or "MENTAL",speaker="Tester",message="hello",line=mentalWireLines[kind] or "hello",source=kind and "builtin" or "custom"}
end

test("same-body ESP contact and generic link families remain distinct while adjacent repeats dedupe",function()
  local cases={
    {frame="esp",family="esp",audience="broadcast"},
    {frame="contact",family="contact",audience="direct"},
    {frame="global",family="contact",audience="broadcast"},
    {frame="room",family="contact",audience="broadcast"},
    {frame="link",family="link",audience="broadcast"},
  }
  for _,first in ipairs(cases) do
    for _,second in ipairs(cases) do
      local history=History.new(10,3)
      local original=mentalWireEntry(first.frame)
      local distinct=first.family~=second.family or first.audience~=second.audience
      eq(history:append(original,100),true); eq(history.lastMentalKind,first.family)
      eq(history:append(mentalWireEntry(first.frame),100.5),false)
      eq(history:append(mentalWireEntry(second.frame),101),distinct)
      eq(#history.items,distinct and 2 or 1); eq(history.lastMentalKind,second.family)
      eq(history:append(mentalWireEntry(second.frame),102),false)
      eq(history.items[1],original); eq(original.line,mentalWireLines[first.frame])
      eq(original.lastMentalKind,nil); eq(original.mental_kind,nil)
    end
  end
  local history=History.new(10,3)
  assert(history:append(mentalWireEntry("contact"),100))
  eq(history:append({category="MENTAL",speaker="Tester",message="hello",line='You pick up Tester\'s thoughts, "hello" [r-1]'},101),true)
  assert(history:append(mentalWireEntry("link"),102))
  eq(history:append({category="MENTAL",speaker="Tester",message="hello",line='Rook picks up Tester\'s mental link, "hello" [r-1]'},103),false)
  eq(#history.items,3)
end)

local contactAudienceLines={
  direct='Lark thinks to you, "hello"',
  global='You pick up Lark\'s thoughts, "hello" [r-1]',
  room='You pick up Lark\'s thoughts echoing through the area, "hello"',
}
local contactAudiencePairs={{"direct","global"},{"global","direct"},{"direct","room"},{"room","direct"}}
local function contactAudienceEntry(frame,category)
  return {category=category or "MENTAL",speaker="Lark",message="hello",
    line=contactAudienceLines[frame],source="builtin"}
end

test("mental audiences require exact frames and never infer proof from raw fallback or metadata",function()
  for _,frame in ipairs({"direct","global","room"}) do
    local family,audience=Channels.mentalKind(contactAudienceEntry(frame))
    eq(family,"contact"); eq(audience,frame=="direct" and "direct" or "broadcast")
  end
  for _,entry in ipairs({
    {category="CONTACT"},{category="ESP"},
    {category="CONTACT",line='Say: Lark thinks to you, "hello"'},
    {category="MENTAL",source="gmcp",speaker="Lark",message="hello",target="Synthetic Keeper"},
    {category="MENTAL",source="outgoing",target="Lark",message="hello"},
  }) do
    local _,audience=Channels.mentalKind(entry)
    eq(audience,nil)
  end
end)

for _,pair in ipairs(contactAudiencePairs) do
  test("same-text "..pair[1].." then "..pair[2].." contact frames retain both and dedupe exact repeats",function()
    local history=History.new(10,3)
    local first,second=contactAudienceEntry(pair[1]),contactAudienceEntry(pair[2])
    local raw={}
    for index,entry in ipairs({first,second}) do
      raw[index]={}; for key,value in pairs(entry) do raw[index][key]=value end
    end
    eq(history:append(first,100),true); eq(history:append(contactAudienceEntry(pair[1]),100.5),false)
    eq(history.lastEpoch,100)
    eq(history:append(second,101),true); eq(history:append(contactAudienceEntry(pair[2]),102),false)
    eq(#history.items,2); eq(history.items[1],first); eq(history.items[2],second)
    eq(history.lastKey,table.concat({"mental","lark","","hello",0},"\0")); eq(history.lastEpoch,101)
    eq(history.lastMentalKind,"contact")
    local direct=pair[1]=="direct" and first or second
    local broadcast=pair[1]=="direct" and second or first
    eq(#history:entries("PRIVATE"),1); eq(history:entries("PRIVATE")[1],direct)
    local link=history:entries(Channels.linkFilter,{MENTAL=false},true)
    eq(#link,1); eq(link[1],broadcast); eq(#history:entries("MENTAL"),2)
    eq(#history:entries("ALL",{MENTAL=false}),0); eq(#history:entries("ALL"),2)
    for index,entry in ipairs(history.items) do
      for key,value in pairs(raw[index]) do eq(entry[key],value) end
      for key,value in pairs(entry) do eq(raw[index][key],value) end
    end
  end)
end

test("restored contact dedupe derives direct versus broadcast from retained raw frames without changing keys",function()
  for _,pair in ipairs(contactAudiencePairs) do
    for _,category in ipairs({"MENTAL","CONTACT"}) do
      local first=contactAudienceEntry(pair[1],category)
      local history=History.new(10,3); assert(history:hydrate({first}))
      local legacyKey=table.concat({category:lower(),"lark","","hello",0},"\0")
      history:restoreDedupe(legacyKey,100)
      eq(history.lastKey,table.concat({"mental","lark","","hello",0},"\0"))
      eq(history:append(contactAudienceEntry(pair[1]),100.5),false)
      eq(history:append(contactAudienceEntry(pair[2]),101),true)
      eq(history:append(contactAudienceEntry(pair[2]),102),false)
      eq(#history.items,2); eq(history.items[1],first); eq(first.category,category)
      eq(first.line,contactAudienceLines[pair[1]]); eq(first.source,"builtin")
    end
  end
end)

test("unknown GMCP and raw CONTACT fallback keep audience dedupe conservative in either order",function()
  for _,frame in ipairs({"direct","global","room"}) do
    for _,category in ipairs({"MENTAL","CONTACT"}) do
      for _,unknownFirst in ipairs({false,true}) do
        local unknown={category=category,speaker="Lark",message="hello",source="gmcp"}
        local known=contactAudienceEntry(frame)
        local original=unknownFirst and unknown or known
        local history=History.new(10,3); assert(history:append(original,100))
        local lastKey=history.lastKey
        eq(history:append(unknownFirst and known or unknown,101),false)
        eq(#history.items,1); eq(history.items[1],original)
        eq(history.lastKey,lastKey); eq(history.lastEpoch,100); eq(history.lastMentalKind,"contact")
        local opposite=frame=="direct" and "global" or "direct"
        eq(history:append(contactAudienceEntry(opposite),102),not unknownFirst)
        eq(#history.items,unknownFirst and 1 or 2)
        eq(unknown.line,nil); eq(unknown.source,"gmcp"); eq(unknown.category,category)
        eq(original.audience,nil); eq(original.mental_audience,nil); eq(original.lastMentalAudience,nil)
      end
    end
  end
end)

test("unknown mental duplicates enrich only transient family state and cannot bridge recognized families",function()
  for _,kind in ipairs({"esp","contact","link"}) do
    for _,knownFirst in ipairs({false,true}) do
      local history=History.new(10,3)
      local original=mentalWireEntry(knownFirst and kind or nil)
      local line,source=original.line,original.source
      assert(history:append(original,100)); local lastKey=history.lastKey
      local incoming=knownFirst and mentalWireEntry(nil) or mentalWireEntry(kind)
      eq(history:append(incoming,101),false)
      eq(history:append(mentalWireEntry(nil),102),false)
      eq(history.lastMentalKind,kind); eq(history.lastKey,lastKey); eq(history.lastEpoch,100)
      eq(#history.items,1); eq(history.items[1],original); eq(original.line,line); eq(original.source,source)
      eq(original.lastMentalKind,nil); eq(original.mental_kind,nil)
      local other=kind=="contact" and "esp" or "contact"
      eq(history:append(mentalWireEntry(other),103),true)
      eq(history.lastMentalKind,other); eq(#history.items,2)
    end
  end
  local history=History.new(10,3)
  assert(history:append(mentalWireEntry(nil),100))
  eq(history:append(mentalWireEntry(nil),101),false); eq(history.lastMentalKind,nil)
end)

test("legacy restore derives wire families without changing raw entries or the dedupe window",function()
  for _,case in ipairs({
    {kind="esp",raw="ESP"},{kind="contact",raw="CONTACT"},{kind="link",raw="DRAGON"},
  }) do
    local raw=mentalWireEntry(case.kind,case.raw)
    local history=History.new(10,3); assert(history:hydrate({raw}))
    local legacyKey=table.concat({case.raw:lower(),"tester","","hello",0},"\0")
    history:restoreDedupe(legacyKey,100)
    eq(history.lastMentalKind,case.kind); eq(history.lastEpoch,100)
    eq(history:append(mentalWireEntry(case.kind),103),false)
    local other=case.kind=="esp" and "contact" or "esp"
    eq(history:append(mentalWireEntry(other),103),true)
    eq(history.items[1],raw); eq(raw.category,case.raw); eq(raw.line,mentalWireLines[case.kind])
    eq(raw.lastMentalKind,nil); eq(raw.mental_kind,nil)
  end
end)

test("restored transient family accepts only the whitelist with legacy derivation as fallback",function()
  local values={"esp","contact","link","none","ESP","invalid",false,true,42,{}}
  for _,kind in ipairs({"esp","unknown"}) do
    for _,value in ipairs(values) do
      local raw=kind=="unknown" and mentalWireEntry(nil) or mentalWireEntry(kind)
      local history=History.new(10,3); assert(history:append(raw,100))
      local lastKey=history.lastKey
      history:restoreDedupe(lastKey,100,value)
      local whitelisted=value=="esp" or value=="contact" or value=="link"
      eq(history.lastMentalKind,whitelisted and value or (kind=="esp" and "esp" or nil))
      eq(history.items[1],raw); eq(raw.lastMentalKind,nil); eq(raw.mental_kind,nil)
    end
  end
  local history=History.new(10,3); assert(history:append({category="ROOM",message="hello"},100))
  history:restoreDedupe(history.lastKey,100,"esp"); eq(history.lastMentalKind,nil)
  history:restoreDedupe(nil,100,"esp"); eq(history.lastMentalKind,nil)
end)

test("hydration preserves transient enrichment and clear sibling and nonmental capture reset it",function()
  local history=History.new(1,3)
  local unknown=mentalWireEntry(nil)
  assert(history:append(unknown,100)); eq(history:append(mentalWireEntry("esp"),101),false)
  assert(history:hydrate({unknown})); eq(history.lastMentalKind,"esp"); eq(#history.items,1)
  eq(history:newSibling().lastMentalKind,nil)
  eq(history:clearVisible(),1); eq(history.lastMentalKind,nil)
  assert(history:append(mentalWireEntry("contact"),102)); eq(history.lastMentalKind,"contact")
  assert(history:append({category="ROOM",message="hello"},103)); eq(history.lastMentalKind,nil)
  eq(History.MAX_RETAINED_ENTRIES,13000); eq(history.limit,1); eq(#history.items,2)
end)
