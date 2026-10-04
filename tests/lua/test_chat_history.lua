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

-- Retention fixtures are synthetic and never read a Mudlet profile or chat log.
local retentionBuckets={"ROOM","WHISPER","ESP","DRAGON","SECIAN","CONTACT","STAFF","COMBAT","ALL","OTHER"}

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
    eq(actual[index].category,entry.category)
    eq(actual[index].message,entry.message)
  end
end

test("retention exposes a thousand-entry bucket cap and ten-thousand-entry total bound",function()
  eq(History.MAX_ENTRIES,1000)
  eq(History.MAX_RETAINED_ENTRIES,10000)
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
      eq(#history.items,10*limit)
      assert(#history.items<=History.MAX_RETAINED_ENTRIES)
      for _,category in ipairs({"ROOM","WHISPER","ESP","DRAGON","SECIAN","CONTACT","STAFF","COMBAT"}) do
        eq(#history:entries(category),limit)
      end
      -- History returns every matching retained private entry, even above limit.
      eq(#history:entries("PRIVATE"),5*limit)
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
  sameRetained(history:entries("STAFF"),{expected[27],live,nextStaff})
  eq(#history:entries("ALL"),30)
end)

test("clearing all retained buckets resets their quotas dedupe and sibling state",function()
  local history=History.new(3,4)
  local entries,expected=retentionFixture(3)
  assert(history:hydrate(entries))
  local sibling=history:newSibling()
  eq(sibling.limit,3); eq(sibling.dedupeSeconds,4); eq(#sibling:entries(),0)
  eq(history:clearVisible(),30)
  eq(#history:entries(),0); eq(#history:categories(),0)
  eq(history.lastKey,nil); eq(history.lastEpoch,nil)
  for index,entry in ipairs(expected) do assert(history:append(entry,index*4)) end
  sameRetained(history:entries(),expected)
  eq(history:append(expected[#expected],#expected*4),false)
  eq(#sibling:entries(),0)
  assert(sibling:append({category="ROOM",message="synthetic-sibling"},200))
  sameRetained(history:entries(),expected)
end)
