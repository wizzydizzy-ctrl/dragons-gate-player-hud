local History=require("chat_history")

test("deduplicates only identical adjacent entries",function()
  local history=History.new(1000,3)
  local entry={category="ESP",speaker="Tekk",message="hello"}
  eq(history:append(entry,100),true)
  eq(history:append(entry,101),false)
  eq(history:append({category="ESP",speaker="Gia",message="hello"},102),true)
  eq(history:append(entry,103),true)
end)

test("deduplicates only within the inclusive forward time window",function()
  local entry={category="ESP",speaker="Tekk",message="hello"}
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
  eq(history:append({category=" esp ",speaker=" Tekk  Prime ",target=" Dace   Alterac ",message=" Hello   there "},100),true)
  eq(history:append({category="ESP",speaker="tekk prime",target="dace alterac",message="hello there"},101),false)
  eq(history:append({category="ESP",speaker="tekk prime",target="Other",message="hello there"},102),true)
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
  local overlap={schema=1,timestamp="2026-08-31T12:00:00-04:00",character="Dace Alterac",category="ESP",speaker="Tekk",message="overlap",line='Tekk (ESP): "overlap"',source="builtin"}
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
  eq(table.concat(history:categories(),","),"ROOM,ESP,QUEST")
end)

test("filters private categories and preserves category insertion order",function()
  local history=History.new(10,3)
  history:append({category="ROOM",message="room"},1)
  history:append({category="WHISPER",message="whisper"},2)
  history:append({category="ESP",message="esp"},3)
  history:append({category="DRAGON",message="dragon"},4)
  history:append({category="SECIAN",message="secian"},5)
  history:append({category="CONTACT",message="contact"},6)
  history:append({category="STAFF",message="staff"},7)
  eq(#history:entries("PRIVATE"),5)
  eq(history:entries("PRIVATE")[1].message,"whisper")
  local categories=history:categories()
  eq(categories[1],"ROOM")
  eq(categories[7],"STAFF")
end)

test("room filter includes both nearby speakers and the active character",function()
  local history=History.new(10,3)
  history:append({category="ROOM",message="Gia asks Dace"},1)
  history:append({category="OWN",message="Dace answers Gia"},2)
  history:append({category="ESP",message="remote"},3)
  local entries=history:entries("ROOM")
  eq(#entries,2); eq(entries[1].category,"ROOM"); eq(entries[2].category,"OWN")
  eq(#history:entries("PRIVATE"),1)
end)

test("ALL source settings hide only selected categories and map OWN to ROOM",function()
  local history=History.new(10,3)
  for index,category in ipairs({"ROOM","OWN","WHISPER","ESP","COMBAT","QUEST"}) do history:append({category=category,message=category},index) end
  local sources={ROOM=false,WHISPER=true,ESP=true,COMBAT=false}
  local entries=history:entries("ALL",sources)
  eq(#entries,3); eq(entries[1].category,"WHISPER"); eq(entries[2].category,"ESP"); eq(entries[3].category,"QUEST")
  eq(#history:entries("ROOM",sources),2); eq(#history:entries("COMBAT",sources),1); eq(#history:entries("PRIVATE",sources),2)
end)

test("ALL source visibility changes never remove stored entries or category filters",function()
  local history=History.new(20,3)
  local categories={"COMBAT","ROOM","OWN","WHISPER","ESP","DRAGON","SECIAN","CONTACT","STAFF","QUEST"}
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
  eq(#history:entries("PRIVATE",sources),5); eq(#history.items,#entries)
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
  local history=History.new(10,3); local sources={COMBAT=false,ROOM=false,ESP=false,STAFF=false}
  local damage={schema=1,timestamp="2026-08-31T12:00:00-04:00",category="COMBAT",message="Your head takes 8 points of impact damage!",source="builtin"}
  local room={schema=1,timestamp="2026-08-31T12:01:00-04:00",category="ROOM",message="nearby",source="builtin"}
  local esp={schema=1,timestamp="2026-08-31T12:02:00-04:00",category="ESP",message="private",source="builtin"}
  local staff={schema=1,timestamp="2026-08-31T12:03:00-04:00",category="STAFF",message="staff",source="builtin"}
  eq(history:append(esp,100),true); eq(history:append(staff,104),true)
  local lastKey,lastEpoch=history.lastKey,history.lastEpoch
  assert(history:hydrate({damage,room,esp})); eq(#history:entries("ALL",sources),0)
  local expected={damage,room,esp,staff}
  eq(#history.items,#expected)
  for index,entry in ipairs(expected) do
    eq(history.items[index],entry); eq(history:entries(entry.category,sources)[1],entry)
  end
  eq(table.concat(history:categories(),","),"COMBAT,ROOM,ESP,STAFF")
  eq(history.lastKey,lastKey); eq(history.lastEpoch,lastEpoch); eq(history:append(staff,105),false)
  local attack={category="COMBAT",message="The dark hound claws at you!",source="builtin"}
  eq(history:append(attack,108),true); eq(#history:entries("ALL",sources),0)
  sources.COMBAT=true
  local visible=history:entries("ALL",sources)
  eq(#visible,2); eq(visible[1],damage); eq(visible[2],attack)
  eq(#history.items,5); eq(#history:entries("PRIVATE",sources),1)
end)

test("clears only the visible in-memory history and resets dedupe state",function()
  local history=History.new(10,3)
  local entry={category="ESP",speaker="Tekk",message="repeatable"}
  assert(history:append(entry,100)); assert(history:append({category="ROOM",message="nearby"},104))
  eq(history:clearVisible(),2)
  eq(#history:entries("ALL"),0); eq(#history:categories(),0); eq(history.lastKey,nil); eq(history.lastEpoch,nil)
  eq(history:append(entry,100),true); eq(#history:entries("ALL"),1)
end)
