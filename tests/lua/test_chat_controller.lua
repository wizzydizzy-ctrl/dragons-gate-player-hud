local Controller=require("chat_controller")
local Parser=require("chat_parser")
local History=require("chat_history")
local Channels=require("chat_channels")

local function fake(entries)
  local f={next=0,triggers={},timers={},storageAppends=0,storageClears=0,storageEntries=entries or {},appendedEntries={},storedCharacters={},errors=0,epochValue=100,timestampValue="2026-08-31T13:00:00-04:00",character="Dace Alterac",loadRecentCalls=0,loadedCharacterKeys={}}
  function f:addLineTrigger(fn) if self.triggerFailure then error(self.triggerFailure) end; self.next=self.next+1; local id="trigger-"..self.next; self.triggers[id]=fn; return id end
  function f:killTrigger(id) self.triggers[id]=nil end
  function f:line(value) for _,fn in pairs(self.triggers) do fn(value) end end
  function f:schedule(_,fn) self.next=self.next+1; local id="timer-"..self.next; self.timers[id]=fn; return id end
  function f:cancelTimer(id) self.timers[id]=nil; return true end
  function f:fireTimer() local id,fn=next(self.timers); if id then self.timers[id]=nil; fn() end end
  function f:count(value) local total=0; for _ in pairs(value) do total=total+1 end; return total end
  function f:epoch() return self.epochValue end
  function f:timestamp() return self.timestampValue end
  function f:reportChatErrorOnce() self.errors=self.errors+1 end
  f.storage={}
  function f.storage:characterKey() return "profile" end
  function f.storage:loadRecent()
    f.loadRecentCalls=f.loadRecentCalls+1
    local key="profile"; f.loadedCharacterKeys[#f.loadedCharacterKeys+1]=key
    if f.loadFailure then error(f.loadFailure) end
    if f.storageEntriesByKey then return f.storageEntriesByKey[key] or {} end
    return f.storageEntries
  end
  function f.storage:append(entry)
    f.storageAppends=f.storageAppends+1
    f.storedCharacters[#f.storedCharacters+1]=entry.character
    if f.storageFailure then return nil,"disk full" end
    f.appendedEntries[#f.appendedEntries+1]=entry
    return true
  end
  function f.storage:clearProfileHistory(confirmed)
    f.storageClears=f.storageClears+1; f.storageClearConfirmed=confirmed
    if f.storageClearFailure then return nil,"delete denied" end
    return true,f.storageRemoved or 0
  end
  return f
end

local function makeController(f,onChange,onAccepted,allSources)
  return Controller.new(f,Parser,History.new(1000,3),f.storage,onChange or function() end,function() return f.character end,allSources,onAccepted)
end

local sourceCases={
  {category="COMBAT",source="COMBAT",line="Your head takes 8 points of impact damage!",nextLine="The dark hound claws at you!"},
  {category="ROOM",source="ROOM",line='Aerin says, "First room message."',nextLine='Aerin asks, "Second room message?"',combined="ROOM"},
  {category="OWN",source="ROOM",line='Dace Alterac says, "First own message."',nextLine='You ask Aerin, "Second own message?"',combined="ROOM"},
  {category="WHISPER",source="WHISPER",line='Aerin whispers to you, "First whisper."',nextLine='Aerin whispers to you, "Second whisper."',combined="PRIVATE"},
  {category="MENTAL",source="MENTAL",line='Tekk (ESP): "First ESP message."',nextLine='Tekk (ESP): "Second ESP message."',combined=Channels.linkFilter},
  {category="MENTAL",source="MENTAL",line='You pick up Losmir\'s mental link, "First dragon message."',nextLine='You pick up Losmir\'s mental link, "Second dragon message."',combined=Channels.linkFilter},
  {category="SECIAN",source="SECIAN",line='You pick up Shayla\'s Secian link, "First Secian message." [r-1]',nextLine='You pick up Shayla\'s Secian link, "Second Secian message." [r-1]',combined=Channels.linkFilter},
  {category="MENTAL",source="MENTAL",line='Seaux thinks to you, "First contact message."',nextLine='Seaux thinks to you, "Second contact message."',combined="PRIVATE"},
  {category="DRAGON",source="DRAGON",line='You pick up Rook\'s Dragon link, "First named Dragon message."',nextLine='You pick up Rook\'s Dragon link, "Second named Dragon message."',combined=Channels.linkFilter},
  {category="PSYCIAN",source="PSYCIAN",line='You pick up Seaux\'s Psycian link, "First Psycian message."',nextLine='You pick up Seaux\'s Psycian link, "Second Psycian message."',combined=Channels.linkFilter},
  {category="STAFF",source="STAFF",line="[GUIDE] Aerin: First staff message.",nextLine="[GM] Aerin: Second staff message."},
  {category="WORLD",source="WORLD",line="** Obatalla Ogoun just arrived in the world.",nextLine="** Xlade Vespar has left the world unexpectedly."},
}

local function allSources(overrides)
  local sources={}
  for category,enabled in pairs(require("defaults").chat.all_sources) do sources[category]=enabled end
  for category,enabled in pairs(overrides or {}) do sources[category]=enabled end
  return sources
end

local function sourceEntries(entries,category)
  local result={}
  for _,entry in ipairs(entries) do
    if entry.category==category or (category=="ROOM" and entry.category=="OWN") then result[#result+1]=entry end
  end
  return result
end

local function hiddenSources()
  local sources=allSources()
  for category in pairs(sources) do sources[category]=false end
  return sources
end

local function sameEntries(actual,expected)
  eq(#actual,#expected)
  for index,entry in ipairs(expected) do
    for _,field in ipairs({"schema","timestamp","character","category","speaker","target","language","message","line","source"}) do
      eq(actual[index][field],entry[field])
    end
  end
end

local function sameViewEntries(actual,expected)
  local projected={}
  for index,entry in ipairs(expected) do projected[index]=Channels.project(entry) end
  sameEntries(actual,projected)
end

local playerStatNames={"strength","intelligence","wisdom","dexterity","agility","constitution","charisma","will","voice","perception","appearance","presence","luck"}

local referralCases={
  {line="1. Corin refers Aerin North (sample-user): 'An item is misflagged.' [2 days, 4 secs ago.]",
    speaker="Corin",target="Aerin North",message="refers Aerin North (sample-user): 'An item is misflagged.' [2 days, 4 secs ago.]"},
  {line="<Corin O'Vale refers Aerin D'North (sample_9.user-2): 'The item's flag needs review.'>",
    speaker="Corin O'Vale",target="Aerin D'North",message="refers Aerin D'North (sample_9.user-2): 'The item's flag needs review.'>"},
  {line="[GM] Keeper O'Vale is handling Corin O'Vale's referral.  (3 more pending.)",
    speaker="Keeper O'Vale",target="Corin O'Vale",message="is handling Corin O'Vale's referral (3 more pending)."},
}

local function referralHarness(sources)
  local f=fake(); f.character="Synthetic Keeper"; f.scheduledDelays={}; f.sideEffects=0
  local append=f.storage.append
  function f.storage:append(entry)
    eq(entry.staff_referral,nil)
    return append(self,entry)
  end
  local schedule=f.schedule
  function f:schedule(delay,fn)
    self.scheduledDelays[#self.scheduledDelays+1]=delay
    return schedule(self,delay,fn)
  end
  local function sideEffect() f.sideEffects=f.sideEffects+1 end
  f.send=sideEffect; f.sendCommand=sideEffect; f.gag=sideEffect; f.deleteLine=sideEffect
  local accepted={}
  local controller=makeController(f,nil,function(entry)
    eq(entry.staff_referral,nil)
    accepted[#accepted+1]=entry
  end,sources)
  assert(controller:start())
  return f,controller,accepted
end

test("complete referrals immediately persist and alert once with STAFF hidden in ALL",function()
  for _,case in ipairs(referralCases) do
    local f,controller,accepted=referralHarness(allSources({STAFF=false}))
    f:line(" \t\27[36m"..case.line.."\27[0m \r\n")
    eq(#accepted,1); eq(f.storageAppends,1); eq(#controller:entries(),0)
    local e=accepted[1]
    eq(e.category,"STAFF"); eq(e.source,"builtin"); eq(e.schema,1)
    eq(e.speaker,case.speaker); eq(e.target,case.target); eq(e.message,case.message); eq(e.line,case.line)
    eq(e.character,"Synthetic Keeper"); eq(e.timestamp,f.timestampValue); eq(e.staff_referral,nil)
    eq(controller.pendingStaffMessage,nil); eq(next(f.timers),nil)
    f:line(case.line); f:line("A synthetic breeze passes through the room."); f:line(">")
    eq(#accepted,1); eq(f.storageAppends,1); eq(e.line,case.line)
    assert(controller:setFilter("STAFF")); sameEntries(controller:entries(),accepted)
    assert(controller:setFilter("ALL")); eq(#controller:entries(),0)
    assert(controller:setAllSources(allSources({STAFF=true}))); sameEntries(controller:entries(),accepted)
    eq(f.sideEffects,0); assert(controller:shutdown()); eq(f:count(f.triggers),0)
  end
end)

test("numbered referrals join wrapped body and age and flush at their closing age",function()
  local f,controller,accepted=referralHarness(allSources({STAFF=false}))
  local first="1. Corin O'Vale refers Aerin D'North (sample_9.user-2): 'The item's flag"
  local second="needs review.' [2 days,"
  local final="4 secs ago.]"
  f:line("\27[36m"..first.."\27[0m"); f:line(second)
  eq(#accepted,0); eq(f.storageAppends,0); eq(f:count(f.timers),1)
  local _,lateTimer=next(f.timers)
  local timestamp=f.timestampValue; f.timestampValue="2026-10-10T12:35:00-04:00"
  f:line("\27[36m"..final.."\27[0m")
  eq(#accepted,1); eq(f.storageAppends,1); eq(next(f.timers),nil)
  local e=accepted[1]
  eq(e.message,"refers Aerin D'North (sample_9.user-2): 'The item's flag needs review.' [2 days, 4 secs ago.]")
  eq(e.line,first.." "..second.." "..final); eq(e.speaker,"Corin O'Vale"); eq(e.target,"Aerin D'North")
  eq(e.timestamp,timestamp); eq(e.staff_referral,nil); eq(#controller:entries(),0)
  f:line("An unrelated synthetic item lies here."); lateTimer(); f:fireTimer()
  eq(#accepted,1); eq(f.storageAppends,1); eq(e.line,first.." "..second.." "..final)
  assert(controller:setFilter("STAFF")); sameEntries(controller:entries(),accepted); assert(controller:shutdown())
end)

test("complete multiline referral payloads flush immediately and preserve their original line",function()
  for _,case in ipairs({
    {prefix="<",suffix=">"},
    {prefix="5. ",suffix=" [2 days,\n4 secs ago.]"},
  }) do
    local f,controller,accepted=referralHarness()
    local payload="Corin refers Aerin North (sample-user): 'An item\nis misflagged.'"
    local line=case.prefix..payload..case.suffix
    f:line("\27[36m"..line.."\27[0m")
    eq(#accepted,1); eq(f.storageAppends,1); eq(next(f.timers),nil)
    eq(accepted[1].line,line); eq(accepted[1].message,payload:sub(#"Corin "+1)..case.suffix)
    eq(accepted[1].staff_referral,nil)
    f:line("Unrelated synthetic output after a complete multiline entry.")
    eq(#accepted,1); eq(accepted[1].line,line); assert(controller:shutdown())
  end
end)

test("referral age beginning on its own bracketed line continues across age wraps",function()
  for _,ageLines in ipairs({{"[2 days, 4 secs ago.]"},{"[2 days,","4 secs ago.]"}}) do
    local f,controller,accepted=referralHarness()
    local first="2. Corin refers Aerin North (sample-user): 'An item is misflagged.'"
    f:line(first); eq(#accepted,0)
    for index,line in ipairs(ageLines) do
      f:line("\27[36m"..line.."\27[0m")
      eq(#accepted,index==#ageLines and 1 or 0)
    end
    eq(accepted[1].line,first.." "..table.concat(ageLines," "))
    eq(accepted[1].message,"refers Aerin North (sample-user): 'An item is misflagged.' [2 days, 4 secs ago.]")
    eq(f.storageAppends,1); eq(next(f.timers),nil); eq(controller.pendingStaffMessage,nil)
    f:line("Synthetic output after the age."); eq(f.storageAppends,1); assert(controller:shutdown())
  end
end)

test("detail referrals retain internal apostrophes and angle text and flush only at the final quote angle",function()
  local f,controller,accepted=referralHarness()
  local first="<Corin refers Aerin North (sample-user): 'The item's label contains '> inside"
  local second="the sample text, and [2 secs ago.] is quoted content."
  local final="The final flag needs review.'>"
  f:line(first); f:line(second); eq(#accepted,0); eq(f.storageAppends,0)
  f:line(final); eq(#accepted,1); eq(f.storageAppends,1); eq(next(f.timers),nil)
  eq(accepted[1].line,first.." "..second.." "..final)
  eq(accepted[1].message,(first.." "..second.." "..final):sub(#"<Corin "+1))
  eq(accepted[1].speaker,"Corin"); eq(accepted[1].target,"Aerin North"); eq(accepted[1].staff_referral,nil)
  f:line("A synthetic room description follows."); eq(#accepted,1); assert(controller:shutdown())
end)

test("detail referral closing quote followed by a standalone angle terminator flushes immediately",function()
  local f,controller,accepted=referralHarness()
  local first="<Corin refers Aerin North (sample-user): 'An item is misflagged.'"
  f:line(first); eq(#accepted,0); eq(f.storageAppends,0)
  local _,lateTimer=next(f.timers)
  f:line(" \t\27[36m>\27[0m ")
  eq(#accepted,1); eq(f.storageAppends,1); eq(next(f.timers),nil); eq(controller.pendingStaffMessage,nil)
  eq(accepted[1].line:gsub("'%s*>$","'>"),first..">")
  eq(accepted[1].message:gsub("'%s*>$","'>"),first:sub(#"<Corin "+1)..">")
  eq(accepted[1].staff_referral,nil)
  f:line("Unrelated synthetic output after the standalone terminator."); lateTimer()
  eq(#accepted,1); eq(f.storageAppends,1); assert(controller:shutdown())
end)

test("consecutive numbered referrals details and handling remain separate entries",function()
  local f,controller,accepted=referralHarness()
  local first="1. Corin refers Aerin North (sample-user): 'First synthetic line"
  local finish="has a flag issue.' [4 secs ago.]"
  f:line(first); f:line(finish); eq(#accepted,1)
  local second="2. Future Referrer refers Future Player Name (sample.user-2): 'A second item needs review.' [1 day ago.]"
  f:line(second); eq(#accepted,2); eq(accepted[2].speaker,"Future Referrer"); eq(accepted[2].target,"Future Player Name")
  f:line(referralCases[2].line); eq(#accepted,3)
  f:line(referralCases[3].line); eq(#accepted,4)
  eq(accepted[1].line,first.." "..finish); eq(accepted[2].line,second)
  eq(accepted[3].line,referralCases[2].line); eq(accepted[4].line,referralCases[3].line)
  for _,entry in ipairs(accepted) do eq(entry.category,"STAFF"); eq(entry.staff_referral,nil) end
  eq(f.storageAppends,4); eq(next(f.timers),nil); sameEntries(controller:entries(),accepted)
  eq(f.sideEffects,0); assert(controller:shutdown())
end)

test("unfinished referrals stop at prompts blank lines and independently parsed chat boundaries",function()
  for _,boundary in ipairs({
    {line=">"},{line="[12] HP:100 >"},{line="[GUIDE] Unrecognized system output"},{line=""},
    {line='Listener says, "A synthetic room message."',category="ROOM"},
    {line="[GUIDE] Listener: A synthetic staff message.",category="STAFF"},
    {line=referralCases[1].line,category="STAFF"},
    {line=referralCases[2].line,category="STAFF"},
    {line=referralCases[3].line,category="STAFF"},
  }) do
    for _,prefix in ipairs({"8. ","<"}) do
      local f,controller,accepted=referralHarness()
      local first=prefix.."Future Referrer refers Future Player Name (sample-user): 'Unfinished sample"
      f:line(first); eq(#accepted,0)
      f:line(boundary.line)
      local count=boundary.category and 2 or 1
      eq(#accepted,count); eq(f.storageAppends,count); eq(next(f.timers),nil)
      eq(accepted[1].line,first); eq(accepted[1].staff_referral,nil)
      eq(accepted[1].message,"refers Future Player Name (sample-user): 'Unfinished sample")
      if boundary.category then eq(accepted[2].category,boundary.category); eq(accepted[2].line,boundary.line) end
      f:line("Unrelated synthetic output after the boundary."); eq(#accepted,count)
      assert(controller:shutdown())
    end
  end
end)

test("unfinished referrals use the existing 0.4 second idle fallback once",function()
  for _,prefix in ipairs({"3. ","<"}) do
    local f,controller,accepted=referralHarness()
    local first=prefix.."Corin refers Aerin North (sample-user): 'A synthetic item"
    f:line(first); f:line("needs further review")
    eq(#accepted,0); eq(f.storageAppends,0); eq(f:count(f.timers),1)
    for _,delay in ipairs(f.scheduledDelays) do eq(delay,.4) end
    local _,lateTimer=next(f.timers)
    f:fireTimer(); eq(#accepted,1); eq(f.storageAppends,1); eq(next(f.timers),nil)
    eq(accepted[1].line,first.." needs further review"); eq(accepted[1].staff_referral,nil)
    lateTimer(); f:line("Unrelated synthetic output after idle."); eq(#accepted,1); eq(f.storageAppends,1)
    assert(controller:shutdown())
  end
end)

test("canceled referral callbacks cannot flush or detach a later referral timer",function()
  for _,completion in ipairs({"terminator","idle"}) do
    local f,controller,accepted=referralHarness()
    f:line("<Old Referrer refers Old Player Name (sample-old): 'An old synthetic item")
    local _,oldTimer=next(f.timers)
    if completion=="terminator" then f:line("needs review.'>") else f:fireTimer() end
    eq(#accepted,1); eq(f.storageAppends,1)

    local first="<Corin refers Aerin North (sample-user): 'A new synthetic item"
    f:line(first); eq(#accepted,1)
    local pending=controller.pendingStaffMessage
    local currentTimerId,currentTimer=next(f.timers)
    oldTimer()
    eq(#accepted,1); eq(f.storageAppends,1); eq(controller.pendingStaffMessage,pending)
    eq(controller.staffMessageTimer,currentTimerId); eq(f.timers[currentTimerId],currentTimer)
    f:line("has another sample flag")
    local replacementTimerId,replacementTimer=next(f.timers)
    currentTimer()
    eq(#accepted,1); eq(f.storageAppends,1); eq(controller.pendingStaffMessage,pending)
    eq(controller.staffMessageTimer,replacementTimerId); eq(f.timers[replacementTimerId],replacementTimer)
    f:line("that needs review.'>")
    eq(#accepted,2); eq(f.storageAppends,2); eq(next(f.timers),nil)
    eq(accepted[2].line,first.." has another sample flag that needs review.'>")
    eq(accepted[2].staff_referral,nil); assert(controller:shutdown())
  end
end)

test("confirmed saved-history deletion discards pending referrals and stale callbacks stay silent",function()
  for _,prefix in ipairs({"11. ","<"}) do
    local f,controller,accepted=referralHarness()
    f:line(referralCases[1].line); eq(#accepted,1); eq(f.storageAppends,1)
    f:line(prefix.."Old Referrer refers Old Player Name (sample-old): 'A synthetic pending item")
    f:line("that predates deletion")
    local _,oldTimer=next(f.timers)
    f.storageRemoved=1
    local cleared,removed=controller:clearSavedHistory(true)
    eq(cleared,true); eq(removed,1); eq(f.storageClears,1); eq(f.storageClearConfirmed,true)
    eq(controller.pendingStaffMessage,nil); eq(controller.pendingStaffMessageLines,nil)
    eq(next(f.timers),nil); eq(#controller.history.items,0); eq(#controller:entries(),0)
    oldTimer(); f:line("a discarded continuation.'>")
    eq(#accepted,1); eq(f.storageAppends,1); eq(#controller.history.items,0)

    local first="<Corin refers Aerin North (sample-user): 'A synthetic item after deletion"
    f:line(first)
    local pending=controller.pendingStaffMessage
    local currentTimerId,currentTimer=next(f.timers)
    oldTimer()
    eq(controller.pendingStaffMessage,pending); eq(controller.staffMessageTimer,currentTimerId)
    eq(f.timers[currentTimerId],currentTimer); eq(#accepted,1); eq(f.storageAppends,1)
    f:line("needs review.'>")
    eq(#accepted,2); eq(f.storageAppends,2); eq(#controller.history.items,1)
    eq(controller.history.items[1].line,first.." needs review.'>")
    eq(controller.history.items[1].staff_referral,nil); eq(next(f.timers),nil)
    assert(controller:shutdown()); eq(f.storageAppends,2)
  end
end)

test("failed or unconfirmed saved-history deletion preserves pending referrals and their timers",function()
  for _,mode in ipairs({"failed","false","missing"}) do
    for _,prefix in ipairs({"12. ","<"}) do
      local f,controller,accepted=referralHarness()
      local first=prefix.."Corin refers Aerin North (sample-user): 'An unfinished synthetic item"
      f:line(first)
      local pending=controller.pendingStaffMessage
      local timerId,timer=next(f.timers)
      if mode=="failed" then f.storageClearFailure=true end
      local confirmed
      if mode=="failed" then confirmed=true elseif mode=="false" then confirmed=false end
      local cleared,err=controller:clearSavedHistory(confirmed)
      eq(cleared,nil); eq(type(err),"string"); eq(f.storageClears,mode=="failed" and 1 or 0)
      eq(controller.pendingStaffMessage,pending); eq(controller.staffMessageTimer,timerId)
      eq(f.timers[timerId],timer); eq(#accepted,0); eq(f.storageAppends,0)
      local final=prefix=="<" and "needs review.'>" or "needs review.' [2 secs ago.]"
      f:line(final)
      eq(#accepted,1); eq(f.storageAppends,1); eq(accepted[1].line,first.." "..final)
      eq(accepted[1].staff_referral,nil); eq(next(f.timers),nil); assert(controller:shutdown())
    end
  end
end)

test("completed referrals reload and hand off silently with STAFF hidden and metadata intact",function()
  local sources=allSources({STAFF=false})
  local f,controller,accepted=referralHarness(sources)
  for _,case in ipairs(referralCases) do f:line(case.line) end
  eq(#accepted,3); assert(controller:setFilter("STAFF"))
  local handoff=controller:handoff(); sameEntries(handoff.entries,accepted); eq(handoff.filter,"STAFF")
  for _,entry in ipairs(handoff.entries) do eq(entry.staff_referral,nil) end
  assert(controller:shutdown())

  local reloaded=fake(f.appendedEntries); reloaded.character="Synthetic Reload Keeper"; local alerts=0
  local restored=makeController(reloaded,nil,function() alerts=alerts+1 end,sources)
  assert(restored:start()); eq(#restored:entries(),0); eq(alerts,0); eq(reloaded.storageAppends,0)
  assert(restored:setFilter("STAFF")); sameEntries(restored:entries(),accepted)
  for _,entry in ipairs(restored:entries()) do eq(entry.staff_referral,nil) end
  assert(restored:shutdown())

  local replacement=fake(); replacement.character="Synthetic Replacement Keeper"
  local updated=makeController(replacement,nil,function() alerts=alerts+1 end,sources)
  assert(updated:restoreHandoff(handoff)); assert(updated:start(true))
  sameEntries(updated:entries(),accepted); eq(replacement.loadRecentCalls,0); eq(alerts,0)
  replacement:line(referralCases[3].line); eq(replacement.storageAppends,0); eq(alerts,0)
  replacement.epochValue=104; replacement:line(referralCases[1].line)
  eq(replacement.storageAppends,1); eq(alerts,1); eq(#updated:entries(),4)
  eq(updated:entries()[4].character,"Synthetic Replacement Keeper"); eq(updated:entries()[4].staff_referral,nil)
  assert(updated:setFilter("ALL")); eq(#updated:entries(),0); assert(updated:shutdown())
end)

test("unfinished referral handoff and shutdown flush once without alerting or leaking framing",function()
  for _,action in ipairs({"handoff","shutdown"}) do
    for _,prefix in ipairs({"9. ","<"}) do
      local f,controller,accepted=referralHarness()
      local first=prefix.."Corin refers Aerin North (sample-user): 'An unfinished synthetic item"
      f:line(first); f:line("needs review")
      local _,lateTimer=next(f.timers)
      local result=controller[action](controller)
      eq(#accepted,0); eq(f.storageAppends,1); eq(#controller.history.items,1); eq(next(f.timers),nil)
      eq(f.appendedEntries[1].line,first.." needs review"); eq(f.appendedEntries[1].staff_referral,nil)
      if action=="handoff" then sameEntries(result.entries,f.appendedEntries); eq(result.entries[1].staff_referral,nil) end
      lateTimer(); assert(controller:shutdown()); eq(#accepted,0); eq(f.storageAppends,1)
    end
  end
end)

test("unfinished referral buffers stop at twenty lines and four thousand characters",function()
  for _,prefix in ipairs({"10. ","<"}) do
    local f,controller,accepted=referralHarness()
    local first=prefix.."Corin refers Aerin North (sample-user): 'Synthetic first line"
    f:line(first); eq(#accepted,0)
    local lines={first}
    for index=2,20 do
      local line="synthetic continuation "..index; lines[#lines+1]=line; f:line(line)
      eq(#accepted,index==20 and 1 or 0)
    end
    eq(f.storageAppends,1); eq(accepted[1].line,table.concat(lines," "))
    eq(accepted[1].staff_referral,nil); eq(next(f.timers),nil); eq(controller.pendingStaffMessage,nil)
    f:line("synthetic continuation outside the buffer"); eq(f.storageAppends,1); assert(controller:shutdown())

    for _,wrapped in ipairs({false,true}) do
      local bounded,boundedController,boundedAccepted=referralHarness()
      local start=prefix.."Corin refers Aerin North (sample-user): '"..string.rep("x",wrapped and 1000 or 5000)
      bounded:line(start)
      if wrapped then eq(#boundedAccepted,0); bounded:line(string.rep("y",5000)) end
      eq(#boundedAccepted,1); eq(bounded.storageAppends,1)
      eq(#boundedAccepted[1].message,4000); eq(#boundedAccepted[1].line,4000)
      eq(boundedAccepted[1].staff_referral,nil); eq(next(bounded.timers),nil)
      bounded:line("synthetic text beyond the character bound"); eq(bounded.storageAppends,1)
      assert(boundedController:shutdown())
    end
  end
end)


test("WORLD notifications retain full metadata and hidden dedicated history across characters reload and handoff",function()
  local f=fake(); local accepted={}; local redraws={}
  local sources=allSources({WORLD=false})
  local controller=makeController(f,function(entries) redraws[#redraws+1]=entries end,
    function(entry) accepted[#accepted+1]=entry end,sources)
  assert(controller:start()); local trigger=controller.trigger
  local arrival="** Obatalla Ogoun just arrived in the world."
  f:line("\27[33m"..arrival.."\27[0m"); f:line(arrival)
  eq(#accepted,1); eq(f.storageAppends,1); eq(#controller:entries(),0)
  eq(accepted[1].speaker,"Obatalla Ogoun"); eq(accepted[1].message,"just arrived in the world.")
  eq(accepted[1].character,"Dace Alterac"); eq(accepted[1].line,arrival)
  eq(accepted[1].timestamp,f.timestampValue); eq(accepted[1].source,"builtin"); eq(accepted[1].schema,1)
  assert(controller:setFilter("WORLD")); sameEntries(controller:entries(),accepted); sameEntries(redraws[#redraws],accepted)
  f.character="Gia Afari"; assert(controller:syncCharacter()); eq(f.loadRecentCalls,1)
  f.epochValue=104; f:line("** Xlade Vespar has left the world unexpectedly.")
  eq(#accepted,2); eq(accepted[2].speaker,"Xlade Vespar"); eq(accepted[2].message,"has left the world unexpectedly.")
  eq(accepted[2].character,"Gia Afari"); sameEntries(controller:entries(),accepted)
  local handoff=controller:handoff(); eq(handoff.filter,"WORLD"); eq(handoff.character_key,"profile")
  sameEntries(handoff.entries,accepted); eq(f.storageClears,0); assert(controller:shutdown()); eq(f.triggers[trigger],nil)

  local nextProfile=fake(f.appendedEntries); nextProfile.character="Deklan Marrowen"
  local restored=makeController(nextProfile,nil,nil,sources)
  assert(restored:start()); eq(#restored:entries(),0); eq(nextProfile.loadRecentCalls,1)
  assert(restored:setFilter("WORLD")); sameEntries(restored:entries(),accepted); eq(nextProfile.storageAppends,0)
  assert(restored:shutdown())
  local upgradeProfile=fake(); upgradeProfile.character="Wizzy Dizzy"; upgradeProfile.epochValue=104
  local replacement=makeController(upgradeProfile,nil,nil,sources)
  assert(replacement:restoreHandoff(handoff)); assert(replacement:start(true))
  eq(upgradeProfile.loadRecentCalls,0); eq(upgradeProfile.storageAppends,0)
  eq(replacement.filter,"WORLD"); sameEntries(replacement:entries(),accepted)
  upgradeProfile:line("** Xlade Vespar has left the world unexpectedly."); eq(upgradeProfile.storageAppends,0)
  upgradeProfile.epochValue=108; upgradeProfile:line("** Obatalla Ogoun has left the world.")
  eq(upgradeProfile.storageAppends,1); eq(#replacement:entries(),3)
  eq(replacement:entries()[3].message,"has left the world."); eq(replacement:entries()[3].character,"Wizzy Dizzy")
  assert(replacement:setFilter("ALL")); eq(#replacement:entries(),0)
  assert(replacement:setAllSources(allSources({WORLD=true}))); eq(#replacement:entries(),3)
  eq(upgradeProfile.storageClears,0); assert(replacement:shutdown())
end)

test("WORLD and unknown source floods retain independent quotas without consuming STAFF or ROOM",function()
  local f=fake(); local history=History.new(3,0)
  local controller=Controller.new(f,Parser,history,f.storage,function() end,function() return f.character end,allSources({WORLD=false}))
  assert(controller:start())
  f:line('[GM] Wizzy: protected staff'); f:line('Eilan says, "protected room"')
  local world={}
  for index=1,7 do
    f.epochValue=100+index*4
    f:line("** Traveler-"..index.." just arrived in the world.")
    world[index]=f.appendedEntries[#f.appendedEntries]
  end
  for index=1,7 do assert(controller:capture("CUSTOM_"..index,"unrelated custom "..index)) end
  eq(history.retentionCounts.WORLD,3); eq(history.retentionCounts.OTHER,3)
  eq(history.retentionCounts.STAFF,1); eq(history.retentionCounts.ROOM,1)
  assert(controller:setFilter("WORLD")); sameEntries(controller:entries(),{world[5],world[6],world[7]})
  assert(controller:setFilter("STAFF")); eq(controller:entries()[1].message,"protected staff")
  assert(controller:setFilter("ROOM")); eq(controller:entries()[1].message,"protected room")
  eq(#history.items,8); eq(f.storageAppends,16); eq(f.storageClears,0); assert(controller:shutdown())
end)
test("generic skill improvements save and render in ALL with COMBAT hidden deduplicate and reload",function()
  local f=fake(); local redraws={}; local sources=allSources({COMBAT=false})
  local controller=makeController(f,function(entries) redraws[#redraws+1]=entries end,nil,sources)
  assert(controller:start()); eq(controller.allSources.COMBAT,false)
  for index,skill in ipairs({"Biting","Sharp Weapons","Identify Gems-Minerals","Identify Gems/Minerals","Dragon's Breath","Future Skill of Tomorrow"}) do
    local line="You now feel more skilled in "..skill.."."
    f:line(" \t\27[32m"..line.."\27[0m \r\n"); f:line(line)
    local entries=controller:entries(); eq(#entries,index); eq(f.storageAppends,index)
    local e=entries[index]
    eq(e.category,"ALL"); eq(e.source,"builtin"); eq(e.message,line); eq(e.line,line)
    eq(e.character,f.character); eq(e.timestamp,f.timestampValue); eq(f.appendedEntries[index],e)
  end
  local entries=controller:entries()
  sameEntries(redraws[#redraws],entries); sameEntries(f.appendedEntries,entries)
  assert(controller:setFilter("COMBAT")); eq(#controller:entries(),0)
  assert(controller:setFilter("ALL")); sameEntries(controller:entries(),entries)
  assert(controller:shutdown())
  local reloaded=fake(f.appendedEntries); local reloadRedraws={}
  local restored=makeController(reloaded,function(items) reloadRedraws[#reloadRedraws+1]=items end,nil,sources)
  assert(restored:start()); eq(restored.allSources.COMBAT,false)
  sameEntries(restored:entries(),entries); sameEntries(reloadRedraws[#reloadRedraws],entries)
  eq(reloaded.loadRecentCalls,1); eq(reloaded.storageAppends,0); assert(restored:shutdown())
end)

test("diligent-training fatigue displays and saves in ALL with COMBAT hidden deduplicates and reloads",function()
  local f=fake(); local redraws={}; local sources=allSources({COMBAT=false})
  local controller=makeController(f,function(entries) redraws[#redraws+1]=entries end,nil,sources)
  assert(controller:start()); eq(controller.allSources.COMBAT,false)
  local line="Due to your diligent training, you have gained additional fatigue!"
  f:line(" \t\27[32m"..line.."\27[0m \r\n"); f:line(line)
  local entries=controller:entries(); eq(#entries,1); eq(f.storageAppends,1)
  local e=entries[1]
  eq(e.category,"ALL"); eq(e.source,"builtin"); eq(e.message,line); eq(e.line,line)
  eq(e.character,f.character); eq(e.timestamp,f.timestampValue)
  eq(f.appendedEntries[1],e); sameEntries(redraws[#redraws],entries)
  assert(controller:setFilter("COMBAT")); eq(#controller:entries(),0)
  assert(controller:setFilter("ALL")); sameEntries(controller:entries(),entries)
  assert(controller:shutdown())
  local reloaded=fake(f.appendedEntries); local restored=makeController(reloaded,nil,nil,sources)
  assert(restored:start()); eq(restored.allSources.COMBAT,false)
  sameEntries(restored:entries(),entries); eq(reloaded.loadRecentCalls,1); eq(reloaded.storageAppends,0)
  assert(restored:shutdown())
end)

test("all thirteen stat increases display and persist in ALL with COMBAT hidden and survive reload",function()
  local f=fake(); local accepted={}; local redraws={}
  local sources=allSources({COMBAT=false})
  local controller=makeController(f,function(entries) redraws[#redraws+1]=entries end,
    function(entry) accepted[#accepted+1]=entry end,sources)
  assert(controller:start()); eq(controller.allSources.COMBAT,false); eq(f:count(f.triggers),1)
  for index,stat in ipairs(playerStatNames) do
    local line="Your "..stat.." has increased!"
    f:line(" \t\27[32m"..line.."\27[0m \r\n")
    eq(#accepted,index); eq(f.storageAppends,index); eq(#controller:entries(),index)
    local e=accepted[index]
    eq(e.category,"ALL"); eq(e.source,"builtin"); eq(e.message,line); eq(e.line,line)
    eq(e.character,f.character); eq(e.timestamp,f.timestampValue)
    eq(e.speaker,nil); eq(e.target,nil); eq(e.language,nil)
    eq(f.appendedEntries[index],e); eq(controller.history.items[index],e)
    f:line(line); eq(#accepted,index); eq(f.storageAppends,index)
  end
  sameEntries(controller:entries(),accepted); sameEntries(redraws[#redraws],accepted)
  eq(table.concat(controller.history:categories(),","),"ALL")
  for _,filter in ipairs({"ROOM","OWN","PRIVATE","WHISPER","ESP","DRAGON","SECIAN","CONTACT","STAFF","COMBAT"}) do
    assert(controller:setFilter(filter)); eq(#controller:entries(),0)
  end
  assert(controller:setFilter("ALL")); sameEntries(controller:entries(),accepted)
  sameEntries(f.appendedEntries,accepted); eq(f.storageClears,0); assert(controller:shutdown())
  eq(f:count(f.triggers),0)

  local reloaded=fake(f.appendedEntries); local reloadRedraws={}
  local restored=makeController(reloaded,function(entries) reloadRedraws[#reloadRedraws+1]=entries end,nil,sources)
  assert(restored:start()); eq(restored.allSources.COMBAT,false)
  sameEntries(restored:entries(),accepted); sameEntries(reloadRedraws[#reloadRedraws],accepted)
  eq(reloaded.loadRecentCalls,1); eq(reloaded.storageAppends,0)
  assert(restored:setFilter("COMBAT")); eq(#restored:entries(),0)
  assert(restored:setFilter("ALL")); sameEntries(restored:entries(),accepted)
  assert(restored:shutdown())
end)

for _,case in ipairs(sourceCases) do
  test("hiding "..case.category.." in ALL preserves owned-trigger capture storage and its own filter",function()
    local f=fake(); local accepted={}; local redraws={}
    local controller=makeController(f,function(entries) redraws[#redraws+1]=entries end,
      function(entry) accepted[#accepted+1]=entry end,allSources({[case.source]=false}))
    if case.category=="COMBAT" then eq(require("defaults").chat.all_sources.COMBAT,false) end
    assert(controller:start()); eq(f:count(f.triggers),1)
    f:line("\27[32m"..case.line.."\27[0m")
    eq(#accepted,1); eq(f.storageAppends,1); eq(#f.appendedEntries,1)
    local entry=accepted[1]
    eq(entry.category,case.category); eq(entry.source,"builtin"); eq(entry.line,case.line)
    eq(entry.character,f.character); eq(entry.timestamp,f.timestampValue)
    eq(controller.history.items[1],entry); eq(f.appendedEntries[1],entry)
    eq(#controller:entries(),0); eq(#redraws[#redraws],0)
    eq(table.concat(controller.history:categories(),","),case.category)
    assert(controller:setFilter(case.category)); sameEntries(controller:entries(),accepted)
    if case.combined then
      if case.combined=="PRIVATE" or case.combined==Channels.linkFilter then assert(controller:setLinkCombined(true)) end
      assert(controller:setFilter(case.combined)); sameEntries(controller:entries(),accepted)
      assert(controller:setFilter(case.combined=="PRIVATE" and Channels.linkFilter or "PRIVATE"))
      eq(#controller:entries(),0)
    end
    eq(f.storageAppends,1); eq(#accepted,1); eq(f.loadRecentCalls,1)
    assert(controller:shutdown()); eq(f:count(f.triggers),0)
  end)

  test("live "..case.category.." ALL source toggles retain past and future captures",function()
    local f=fake(); local accepted={}; local redraws={}
    local controller=makeController(f,function(entries) redraws[#redraws+1]=entries end,
      function(entry) accepted[#accepted+1]=entry end,allSources({[case.source]=false}))
    assert(controller:start()); local trigger=controller.trigger
    f:line(case.line); eq(#controller:entries(),0); eq(f.storageAppends,1)
    assert(controller:setAllSources(allSources({[case.source]=true})))
    sameEntries(controller:entries(),accepted); sameEntries(redraws[#redraws],accepted)
    f.epochValue=104; f:line(case.nextLine); eq(#accepted,2)
    sameEntries(controller:entries(),accepted)
    assert(controller:setAllSources(allSources({[case.source]=false})))
    eq(#controller:entries(),0); eq(#redraws[#redraws],0)
    assert(controller:setFilter(case.category)); sameEntries(controller:entries(),accepted)
    assert(controller:setAllSources(allSources({[case.source]=true})))
    eq(controller.filter,case.category); sameEntries(controller:entries(),accepted)
    assert(controller:setAllSources(allSources({[case.source]=false})))
    eq(controller.filter,case.category); sameEntries(controller:entries(),accepted)
    assert(controller:setFilter("ALL"))
    f.epochValue=108; f:line(case.line); eq(#accepted,3); eq(#controller:entries(),0)
    assert(controller:setAllSources(allSources({[case.source]=true})))
    sameEntries(controller:entries(),accepted); sameEntries(redraws[#redraws],accepted)
    sameViewEntries(controller.history:entries("ALL"),accepted); sameEntries(f.appendedEntries,accepted)
    eq(accepted[1].line,case.line); eq(accepted[2].line,case.nextLine); eq(accepted[3].line,case.line)
    eq(f.storageAppends,3); eq(f.storageClears,0); eq(f.loadRecentCalls,1)
    eq(controller.trigger,trigger); eq(f:count(f.triggers),1)
    assert(controller:shutdown())
  end)
end

test("real weapon swings own attacks and attack results are captured while COMBAT is hidden in ALL",function()
  local f=fake(); local accepted={}; local redraws={}
  local controller=makeController(f,function(entries) redraws[#redraws+1]=entries end,
    function(entry) accepted[#accepted+1]=entry end,allSources({COMBAT=false}))
  assert(controller:start()); local trigger=controller.trigger
  local lines={
    "The academy bully swings a jagged quartz rock at you!",
    "The enticing forest siren punches at you!",
    "You swing your two-handed simple wooden broadsword at the fighting puppet!",
    "The attack is a well-delivered blow to the torso.",
    "The swing barely misses.",
  }
  for index,line in ipairs(lines) do
    f.epochValue=100+index*4; f:line("\27[32m"..line.."\27[0m")
    eq(#accepted,index); eq(f.storageAppends,index); eq(#f.appendedEntries,index)
    local entry=accepted[index]
    eq(entry.category,"COMBAT"); eq(entry.source,"builtin"); eq(entry.message,line); eq(entry.line,line)
    eq(f.appendedEntries[index],entry); eq(controller.history.items[index],entry)
    eq(#controller:entries(),0); eq(#redraws[#redraws],0)
  end
  assert(controller:setFilter("COMBAT")); sameEntries(controller:entries(),accepted)
  assert(controller:setFilter("ALL")); eq(#controller:entries(),0)
  assert(controller:setAllSources(allSources({COMBAT=true}))); sameEntries(controller:entries(),accepted)
  assert(controller:setAllSources(allSources({COMBAT=false}))); eq(#controller:entries(),0)
  sameViewEntries(controller.history:entries("ALL"),accepted); sameEntries(f.appendedEntries,accepted)
  eq(f.storageAppends,#lines); eq(f.storageClears,0); eq(controller.trigger,trigger)
  assert(controller:shutdown())
end)

test("profile reload hydrates hidden sources and continues capturing them",function()
  local first=fake(); local original=makeController(first,nil,nil,hiddenSources())
  assert(original:start())
  for _,case in ipairs(sourceCases) do first:line(case.line) end
  eq(#original:entries(),0); eq(first.storageAppends,#sourceCases)
  local stored=first.appendedEntries; eq(#stored,#sourceCases)
  sameViewEntries(original.history:entries("ALL"),stored); assert(original:shutdown())

  local second=fake(stored); local accepted={}
  local restored=makeController(second,nil,function(entry) accepted[#accepted+1]=entry end,hiddenSources())
  assert(restored:start()); eq(#restored:entries(),0); eq(second.loadRecentCalls,1)
  eq(second.storageAppends,0); eq(#accepted,0)
  sameViewEntries(restored.history:entries("ALL"),stored)
  for index,case in ipairs(sourceCases) do
    local expected=sourceEntries(stored,case.category)
    assert(restored:setFilter(case.category)); sameEntries(restored:entries(),expected)
  end
  assert(restored:setFilter("ALL")); second.character="Gia"; assert(restored:syncCharacter())
  eq(#restored:entries(),0); sameViewEntries(restored.history:entries("ALL"),stored); eq(second.loadRecentCalls,1)
  second:line(sourceCases[1].nextLine)
  eq(second.storageAppends,1); eq(#accepted,1); eq(accepted[1].category,"COMBAT"); eq(accepted[1].character,"Gia")
  eq(#restored:entries(),0); assert(restored:setFilter("COMBAT"))
  sameEntries(restored:entries(),{stored[1],accepted[1]})
  assert(restored:setFilter("ALL")); local sources=hiddenSources(); sources.COMBAT=true
  assert(restored:setAllSources(sources)); sameEntries(restored:entries(),{stored[1],accepted[1]})
  eq(second.storageClears,0); assert(restored:shutdown())
end)

test("handoff retains every hidden source and preserves later capture without reloading storage",function()
  local first=fake(); local original=makeController(first,nil,nil,hiddenSources())
  assert(original:start())
  for _,case in ipairs(sourceCases) do first:line(case.line) end
  eq(#original:entries(),0); eq(first.storageAppends,#sourceCases)
  local stored=first.appendedEntries; local handoff=original:handoff()
  eq(handoff.filter,"ALL"); sameEntries(handoff.entries,stored)
  assert(original:shutdown()); eq(first:count(first.triggers),0)

  local second=fake(); local accepted={}; local restored=makeController(second,nil,
    function(entry) accepted[#accepted+1]=entry end,hiddenSources())
  assert(restored:restoreHandoff(handoff)); assert(restored:start(true))
  eq(restored.filter,"ALL"); eq(#restored:entries(),0); eq(#accepted,0)
  eq(second.loadRecentCalls,0); eq(second.storageAppends,0)
  sameViewEntries(restored.history:entries("ALL"),stored)
  for index,case in ipairs(sourceCases) do
    local expected=sourceEntries(stored,case.category)
    assert(restored:setFilter(case.category)); sameEntries(restored:entries(),expected)
  end
  assert(restored:setFilter("ALL")); second:line(sourceCases[#sourceCases].line)
  eq(second.storageAppends,0); eq(#accepted,0)
  second.epochValue=104; second:line(sourceCases[1].nextLine)
  eq(second.storageAppends,1); eq(#accepted,1); eq(accepted[1].category,"COMBAT"); eq(#restored:entries(),0)
  assert(restored:setFilter("COMBAT")); sameEntries(restored:entries(),{stored[1],accepted[1]})
  assert(restored:setFilter("ALL")); assert(restored:setAllSources(allSources({COMBAT=true})))
  local expected={}; for index,entry in ipairs(stored) do expected[index]=entry end; expected[#expected+1]=accepted[1]
  sameEntries(restored:entries(),expected); sameEntries(restored:handoff().entries,expected)
  eq(second.storageAppends,1); eq(second.storageClears,0); assert(restored:shutdown())
end)

test("partial ALL handoff merges persisted hidden COMBAT and deduplicates the visible ROOM overlap",function()
  local first=fake(); local original=makeController(first,nil,nil,allSources())
  assert(original:start()); first:line(sourceCases[1].line); first:line(sourceCases[2].line)
  local stored=first.appendedEntries
  eq(#stored,2); eq(stored[1].category,"COMBAT"); eq(stored[2].category,"ROOM")
  local handoff=original:handoff()
  handoff.partial=true; handoff.entries=original:entries()
  eq(handoff.filter,"ALL"); sameEntries(handoff.entries,{stored[2]})
  assert(original:shutdown())

  local second=fake(stored); local accepted={}
  local restored=makeController(second,nil,function(entry) accepted[#accepted+1]=entry end,allSources())
  assert(restored:restoreHandoff(handoff)); assert(restored:start(true))
  eq(second.loadRecentCalls,1); eq(second.storageAppends,0); eq(#accepted,0)
  eq(restored.allSources.COMBAT,false); eq(restored.filter,"ALL")
  sameEntries(restored:entries(),{stored[2]}); sameViewEntries(restored.history:entries("ALL"),stored)
  eq(table.concat(restored.history:categories(),","),"COMBAT,ROOM")
  eq(restored.history.lastKey,handoff.last_key); eq(restored.history.lastEpoch,handoff.last_epoch)
  second:line(sourceCases[2].line)
  eq(second.storageAppends,0); eq(#accepted,0); sameViewEntries(restored.history:entries("ALL"),stored)
  assert(restored:setFilter("COMBAT")); sameEntries(restored:entries(),{stored[1]})
  assert(restored:setFilter("ALL")); assert(restored:setAllSources(allSources({COMBAT=true})))
  sameEntries(restored:entries(),stored)
  assert(restored:setAllSources(allSources())); sameEntries(restored:entries(),{stored[2]})
  second.epochValue=104; second:line(sourceCases[1].nextLine)
  eq(second.storageAppends,1); eq(#accepted,1); eq(accepted[1].category,"COMBAT")
  sameEntries(restored:entries(),{stored[2]})
  assert(restored:setFilter("COMBAT")); sameEntries(restored:entries(),{stored[1],accepted[1]})
  sameEntries(restored:handoff().entries,{stored[1],stored[2],accepted[1]})
  eq(second.loadRecentCalls,1); eq(second.storageClears,0); assert(restored:shutdown())
end)

test("authoritative cleared handoff skips persisted hidden sources and keeps the cleared view empty",function()
  local first=fake(); local original=makeController(first,nil,nil,allSources())
  assert(original:start()); first:line(sourceCases[1].line); first:line(sourceCases[2].line)
  local stored=first.appendedEntries; eq(#stored,2)
  assert(original:clearVisibleHistory()); local handoff=original:handoff()
  eq(#handoff.entries,0); eq(handoff.partial,nil); assert(original:shutdown())

  local second=fake(stored); local restored=makeController(second,nil,nil,allSources())
  assert(restored:restoreHandoff(handoff)); assert(restored:start(true))
  eq(second.loadRecentCalls,0); eq(second.storageAppends,0); eq(second.storageClears,0)
  eq(#restored:entries(),0); eq(#restored.history:entries("ALL"),0)
  assert(restored:setFilter("COMBAT")); eq(#restored:entries(),0)
  assert(restored:setFilter("ALL")); assert(restored:setAllSources(allSources({COMBAT=true})))
  eq(#restored:entries(),0)
  second:line(sourceCases[1].line)
  eq(second.storageAppends,1); eq(#restored:entries(),1)
  eq(restored:entries()[1].category,"COMBAT"); eq(restored:entries()[1].line,sourceCases[1].line)
  assert(restored:shutdown())
end)

test("accepted callback receives each live entry once after history and storage append",function()
  local f=fake(); local accepted={}; local observations={}; local controller
  controller=makeController(f,nil,function(entry)
    accepted[#accepted+1]=entry
    observations[#observations+1]={latest=controller.history.items[#controller.history.items],stored=f.storageAppends}
  end,{MENTAL=false})
  assert(controller:start()); f:line('Tekk (ESP): "hello"')
  eq(#accepted,1); eq(accepted[1].category,"MENTAL"); eq(#controller:entries(),0)
  eq(observations[1].latest,accepted[1]); eq(observations[1].stored,1)
  f:line('Tekk (ESP): "hello"'); eq(#accepted,1); eq(f.storageAppends,1)
  assert(controller:capture("QUEST","live custom")); assert(controller:capture("QUEST","live custom"))
  eq(#accepted,2); eq(accepted[2].source,"custom"); eq(f.storageAppends,2)
  f.epochValue=104; assert(controller:capture("QUEST","live custom")); eq(#accepted,3)
  eq(controller:accept(nil),false); eq(#accepted,3)
end)

test("hydration filter changes redraws and character synchronization stay silent",function()
  local f=fake({{category="STAFF",message="saved report"}}); local accepted=0
  local controller=makeController(f,nil,function() accepted=accepted+1 end)
  assert(controller:start()); assert(controller:start()); eq(#controller:entries(),1)
  assert(controller:setFilter("STAFF")); assert(controller:setAllSources({STAFF=false})); controller:notify()
  f.character="Gia"; assert(controller:syncCharacter()); eq(accepted,0); eq(f.storageAppends,0)
  assert(controller:clearVisibleHistory()); eq(accepted,0)
end)

test("wrapped STAFF reports alert only once at their final boundary or timer flush",function()
  for _,flush in ipairs({"boundary","timer"}) do
    local f=fake(); local accepted={}
    local controller=makeController(f,nil,function(entry) accepted[#accepted+1]=entry end)
    assert(controller:start())
    local first="[GM] Vaeltherion [forhekset] reports a bug in room 10532: First line"
    f:line(first); f:line("and the final line."); eq(#accepted,0); eq(f.storageAppends,0)
    if flush=="boundary" then f:line(">") else f:fireTimer() end
    eq(#accepted,1); eq(accepted[1].category,"STAFF")
    eq(accepted[1].message,"reports a bug in room 10532: First line and the final line.")
    eq(f.storageAppends,1); eq(next(f.timers),nil)
    f:line(first); f:line("and the final line."); f:line(">")
    eq(#accepted,1); eq(f.storageAppends,1)
  end
end)

test("handoff and shutdown flush STAFF history and storage without alerts",function()
  for _,action in ipairs({"handoff","shutdown"}) do
    local f=fake(); local accepted=0
    local controller=makeController(f,nil,function() accepted=accepted+1 end)
    assert(controller:start()); f:line("[GM] Wizzy resolved report #21: First line"); f:line("final line.")
    local _,lateTimer=next(f.timers)
    local result=controller[action](controller)
    eq(accepted,0); eq(f.storageAppends,1); eq(#controller.history.items,1); eq(next(f.timers),nil)
    eq(controller.history.items[1].message,"resolved report #21: First line final line.")
    if action=="handoff" then eq(#result.entries,1); eq(result.entries[1].category,"STAFF") end
    lateTimer(); controller:shutdown(); eq(accepted,0); eq(f.storageAppends,1)
  end
end)

test("restoring handoff is silent and keeps duplicate suppression for subsequent live entries",function()
  local first=fake(); local original=makeController(first); assert(original:start()); assert(original:capture("STAFF","saved staff"))
  local second=fake(); local accepted=0; local restored=makeController(second,nil,function() accepted=accepted+1 end)
  assert(restored:restoreHandoff(original:handoff())); assert(restored:start(true))
  eq(accepted,0); eq(second.loadRecentCalls,0); eq(second.storageAppends,0)
  assert(restored:capture("STAFF","saved staff")); eq(accepted,0); eq(second.storageAppends,0)
  second.epochValue=104; assert(restored:capture("STAFF","new staff")); eq(accepted,1); eq(second.storageAppends,1)
end)

test("accepted callback failures cannot interrupt capture persistence or later entries",function()
  local f=fake(); local attempts=0; local notifications=0
  local controller=makeController(f,function() notifications=notifications+1 end,function() attempts=attempts+1; error("sound API failed") end)
  assert(controller:start()); f:line('Tekk (ESP): "hello"'); assert(controller:capture("STAFF","second"))
  eq(attempts,2); eq(f.storageAppends,2); eq(#controller:entries(),2); eq(notifications,3); eq(f.errors,0)
end)

test("storage and redraw failures still permit one callback per accepted history entry",function()
  local f=fake(); f.storageFailure=true; local accepted=0
  local controller=makeController(f,function() error("view unavailable") end,function() accepted=accepted+1 end)
  assert(controller:start()); assert(controller:capture("STAFF","first")); assert(controller:capture("STAFF","second"))
  eq(accepted,2); eq(f.storageAppends,2); eq(#controller:entries(),2); eq(f.errors,1)
  controller.storage.append=function() error("storage exception") end
  assert(controller:capture("STAFF","third")); eq(accepted,3); eq(#controller:entries(),3)
end)

test("one owned line trigger captures and persists recognized chat",function()
  local f=fake(); local controller=makeController(f); controller:start(); f:line('Tekk (ESP): "hello"')
  eq(controller:entries()[1].category,"MENTAL"); eq(f.storageAppends,1); eq(f:count(f.triggers),1)
end)

test("training-ready notices persist in ALL with combat excluded and other tabs unchanged",function()
  local f=fake(); local controller=makeController(f,nil,nil,{COMBAT=false})
  assert(controller:start())
  local line="You now feel prepared to train further in Sharp Weapons."
  f:line(line); f:line(line)
  eq(#controller:entries(),1); eq(controller:entries()[1].category,"ALL"); eq(controller:entries()[1].line,line)
  eq(f.storageAppends,1)
  for _,filter in ipairs({"ROOM","PRIVATE","ESP","DRAGON","SECIAN","CONTACT","STAFF","COMBAT"}) do
    assert(controller:setFilter(filter)); eq(#controller:entries(),0)
  end
  assert(controller:setFilter("ALL")); eq(#controller:entries(),1)
  local restored=makeController(fake()); assert(restored:restoreHandoff(controller:handoff())); assert(restored:start(true))
  eq(#restored:entries(),1); eq(restored:entries()[1].line,line)
  restored:shutdown(); controller:shutdown()
end)

test("direct thoughts flow through the owned trigger into contact and private filters",function()
  local f=fake(); local controller=makeController(f); assert(controller:start()); assert(controller:setFilter("CONTACT"))
  f:line('Seaux thinks to you, "Hello"')
  local entries=controller:entries()
  eq(#entries,1); eq(entries[1].category,"MENTAL"); eq(entries[1].speaker,"Seaux"); eq(entries[1].message,"Hello")
  eq(f.storageAppends,1); assert(controller:setFilter("PRIVATE")); eq(#controller:entries(),1)
end)

test("ranked Psycian links flow through the owned trigger into PSYCIAN and LINK only",function()
  local f=fake(); local controller=makeController(f); assert(controller:start()); assert(controller:setFilter("PSYCIAN"))
  f:line('You pick up Seaux\'s Psycian link, "Hello." [r-1]')
  local entries=controller:entries()
  eq(#entries,1); eq(entries[1].category,"PSYCIAN"); eq(entries[1].speaker,"Seaux"); eq(entries[1].message,"Hello.")
  eq(f.storageAppends,1); assert(controller:setFilter("PRIVATE")); eq(#controller:entries(),0)
  assert(controller:setLinkCombined(true)); assert(controller:setFilter(Channels.linkFilter)); sameEntries(controller:entries(),entries)
  assert(controller:shutdown())
end)

test("GUIDE assistance requests flow through the owned trigger into staff chat",function()
  local f=fake(); local controller=makeController(f); assert(controller:start()); assert(controller:setFilter("STAFF"))
  local line="[GUIDE] Bork Biigfeet (room 174) requests your assistance.  (1 total requests pending.)"
  f:line(line)
  local entries=controller:entries()
  eq(#entries,1); eq(entries[1].category,"STAFF"); eq(entries[1].speaker,"Bork Biigfeet"); eq(entries[1].line,line)
  eq(f.storageAppends,1)
end)

test("GUIDE assistance cancellations flow through the owned trigger into staff chat",function()
  local f=fake(); local controller=makeController(f); assert(controller:start()); assert(controller:setFilter("STAFF"))
  local line="[GUIDE] Wizzy Dizzy just canceled his assistance request."
  f:line(line)
  local entries=controller:entries()
  eq(#entries,1); eq(entries[1].category,"STAFF"); eq(entries[1].speaker,"Wizzy Dizzy"); eq(entries[1].line,line)
  eq(f.storageAppends,1)
end)

test("GUIDE assistance handling assignments flow through the owned trigger into staff chat",function()
  local f=fake(); local controller=makeController(f); assert(controller:start()); assert(controller:setFilter("STAFF"))
  local line="[GUIDE] Aeron is handling Marcelline Willowsby's assist.  (0 more pending.)"
  f:line(line)
  local entries=controller:entries()
  eq(#entries,1); eq(entries[1].category,"STAFF"); eq(entries[1].speaker,"Aeron"); eq(entries[1].target,"Marcelline Willowsby"); eq(entries[1].line,line)
  eq(f.storageAppends,1)
end)

test("wrapped GM bug reports flow through the owned trigger as one staff entry",function()
  local f=fake(); local controller=makeController(f); assert(controller:start()); assert(controller:setFilter("STAFF"))
  local first="[GM] Vaeltherion [forhekset] reports a bug in room 10532: Traveling Drag-al Merchants have spawned in the hunting area .. and all the mobs are gone. And I can't"
  f:line(first); f:line("finish the hunt or find the original creatures."); f:line(">")
  local entries=controller:entries()
  eq(#entries,1); eq(entries[1].speaker,"Vaeltherion")
  eq(entries[1].message,"reports a bug in room 10532: Traveling Drag-al Merchants have spawned in the hunting area .. and all the mobs are gone. And I can't finish the hunt or find the original creatures.")
  eq(f.storageAppends,1); eq(next(f.timers),nil)
end)
test("wrapped GM resolved reports flow through the owned trigger as one staff entry",function()
  local f=fake(); local controller=makeController(f); assert(controller:start()); assert(controller:setFilter("STAFF"))
  f:line("[GM] Wizzy resolved report #21: Air mages have a level 2 spell that works and is tested. Just need to find/figure it out, all runes/shapes are avialable at level 1")
  f:line("and start with air mage, for the level 2 spell."); f:line(">")
  local entries=controller:entries(); eq(#entries,1); eq(entries[1].speaker,"Wizzy")
  eq(entries[1].message,"resolved report #21: Air mages have a level 2 spell that works and is tested. Just need to find/figure it out, all runes/shapes are avialable at level 1 and start with air mage, for the level 2 spell.")
  eq(f.storageAppends,1); eq(next(f.timers),nil)
end)

test("targeted asks are captured and visible in the room tab",function()
  local f=fake(); local controller=makeController(f); assert(controller:start()); assert(controller:setFilter("ROOM"))
  f:line('Eilan asks Atrax, "You asked two already, didn\'t you?"')
  f.epochValue=104; f:line('Dace Alterac asks Atrax, "Ready?"')
  local entries=controller:entries()
  eq(#entries,2); eq(entries[1].target,"Atrax"); eq(entries[1].category,"ROOM")
  eq(entries[2].target,"Atrax"); eq(entries[2].category,"OWN"); eq(f.storageAppends,2)
end)

test("Secian links flow through the owned trigger LINK filter and dedupe",function()
  local f=fake(); local controller=makeController(f); assert(controller:start())
  local line='You pick up Marcelline\'s Secian link, "Hello?" [r-1]'
  f:line(line); f.epochValue=101; f:line(line)
  eq(#controller:entries(),1); eq(controller:entries()[1].category,"SECIAN"); eq(controller:entries()[1].speaker,"Marcelline")
  eq(f.storageAppends,1); assert(controller:setFilter("PRIVATE")); eq(#controller:entries(),0)
  assert(controller:setLinkCombined(true)); assert(controller:setFilter(Channels.linkFilter)); eq(#controller:entries(),1)
  eq(controller:entries()[1],controller.history.items[1]); eq(#controller.history.items,1)
  assert(controller:shutdown())
end)

test("does not start when owned trigger registration fails",function()
  local f=fake(); f.triggerFailure="chat trigger registration failed"; local controller=makeController(f)
  local started,err=controller:start(); eq(started,nil); eq(tostring(err):find("chat trigger registration failed",1,true)~=nil,true); eq(controller.started,false); eq(controller.trigger,nil); eq(f:count(f.triggers),0)
end)

test("custom API creates a filter without editing HUD triggers",function()
  local f=fake(); local controller=makeController(f); controller:start(); assert(controller:capture("QUEST","The quest begins."))
  eq(controller:entries()[1].source,"custom"); eq(controller.history:categories()[1],"QUEST"); eq(f:count(f.triggers),1)
end)

test("custom API treats an adjacent duplicate as a successful no-op",function()
  local f=fake(); local controller=makeController(f); controller:start()
  eq(controller:capture("QUEST","The quest begins."),true); eq(controller:capture("QUEST","The quest begins."),true)
  eq(f.storageAppends,1)
end)

test("storage errors report once while in-memory capture continues",function()
  local f=fake(); f.storageFailure=true; local controller=makeController(f); controller:start()
  eq(controller:capture("QUEST","first"),true); f.epochValue=101; eq(controller:capture("QUEST","second"),true)
  eq(#controller:entries(),2); eq(f.storageAppends,2); eq(f.errors,1)
end)

test("reports a startup history failure once and continues capturing",function()
  local f=fake(); f.loadFailure="history read exploded"; local controller=makeController(f)
  eq(controller:start(),true); eq(f.errors,1); eq(f.loadRecentCalls,1); f:line('Tekk (ESP): "hello"'); f.epochValue=104; eq(controller:capture("QUEST","continues"),true)
  eq(#controller:entries(),2); eq(f.storageAppends,2); controller:start(); eq(f.errors,1); eq(f.loadRecentCalls,1)
end)

test("loads recent entries once and rotates later captures to the active character",function()
  local f=fake({{category="ESP",message="earlier",character="Dace Alterac",timestamp="2026-08-31T12:00:00-04:00"}}); local controller=makeController(f)
  controller:start(); eq(controller:entries()[1].message,"earlier")
  assert(controller:capture("QUEST","for Dace")); f.character="Gia"; f.epochValue=104; assert(controller:capture("QUEST","for Gia"))
  eq(f.storedCharacters[1],"Dace Alterac"); eq(f.storedCharacters[2],"Gia")
end)

test("character transitions retain one profile-wide history without reloading or re-persisting",function()
  local f=fake(); f.character=nil
  f.storageEntriesByKey={profile={{schema=1,timestamp="2026-08-31T12:00:00-04:00",character="Earlier",category="ROOM",message="profile recent",line="profile recent",source="builtin"}}}
  local controller=makeController(f); controller:start(); assert(controller:capture("QUEST","live unknown"))
  eq(f.storageAppends,1); eq(table.concat(f.loadedCharacterKeys,","),"profile")
  f.character="Dace/Alterac"; assert(controller:syncCharacter())
  assert(controller:capture("QUEST","live Dace")); f.character="Gia"; assert(controller:syncCharacter()); assert(controller:capture("QUEST","live Gia"))
  local entries=controller:entries(); eq(#entries,4); eq(entries[1].message,"profile recent"); eq(entries[4].message,"live Gia")
  eq(table.concat(f.loadedCharacterKeys,","),"profile"); eq(f.loadRecentCalls,1); eq(f.storageAppends,3)
end)

test("filter changes notify with only matching entries and shutdown removes its trigger",function()
  local f=fake(); local calls={}; local controller=makeController(f,function(entries,_,filter) calls[#calls+1]={entries=entries,filter=filter} end)
  controller:start(); assert(controller:capture("QUEST","quest")); f.epochValue=104; assert(controller:capture("EVENTS","event")); controller:setFilter("QUEST")
  eq(calls[#calls].filter,"QUEST"); eq(calls[#calls].entries[1].message,"quest"); controller:shutdown(); eq(f:count(f.triggers),0); eq(controller:capture("QUEST","late"),nil)
end)

test("chat handoff preserves bounded history filter dedupe and transient identity gaps",function()
  local first=fake(); local original=makeController(first); assert(original:start())
  assert(original:capture("EVENTS","earlier")); first.epochValue=104; assert(original:capture("QUEST","keep me")); assert(original:setFilter("QUEST"))
  local handoff=original:handoff(); eq(handoff.schema,1); eq(handoff.character_key,"profile"); eq(handoff.filter,"QUEST"); eq(#handoff.entries,2)

  local second=fake(); second.character=nil; second.epochValue=104; local notifications=0
  local restored=makeController(second,function() notifications=notifications+1 end)
  assert(restored:restoreHandoff(handoff)); assert(restored:start(true))
  eq(notifications,0); eq(second.loadRecentCalls,0); eq(restored.filter,"QUEST"); eq(restored:entries()[1].message,"keep me")
  eq(#restored.history:entries("ALL"),2)
  assert(restored:capture("QUEST","keep me")); eq(second.storageAppends,0); eq(#restored.history:entries("ALL"),2)
  second.character="Dace Alterac"; assert(restored:syncCharacter()); eq(second.loadRecentCalls,0)
end)

test("chat handoff remains profile-wide when the replacement has another character",function()
  local first=fake(); local original=makeController(first); assert(original:start()); assert(original:capture("QUEST","Dace only"))
  local handoff=original:handoff(); local second=fake(); second.character="Gia"; second.storageEntriesByKey={profile={{category="ESP",message="older disk line"}}}
  local restored=makeController(second); assert(restored:restoreHandoff(handoff)); assert(restored:start(true))
  eq(second.loadRecentCalls,0); eq(restored.currentCharacterKey,"profile"); eq(restored:entries()[1].message,"Dace only")
end)

test("visible clear empties memory without touching saved profile history",function()
  local f=fake(); local notifications=0
  local controller=makeController(f,function() notifications=notifications+1 end)
  assert(controller:start()); assert(controller:capture("QUEST","keep on disk")); local before=notifications
  local ok,removed=controller:clearVisibleHistory()
  eq(ok,true); eq(removed,1); eq(#controller:entries(),0); eq(#controller.history:categories(),0)
  eq(f.storageAppends,1); eq(f.storageClears,0); eq(notifications,before+1)
  assert(controller:capture("QUEST","keep on disk")); eq(f.storageAppends,2)
end)

test("saved clear requires literal confirmation and defaults to retaining all history",function()
  local f=fake(); local controller=makeController(f); assert(controller:start()); assert(controller:capture("QUEST","retain me"))
  for _,confirmation in ipairs({false,"yes",1}) do
    local ok,err=controller:clearSavedHistory(confirmation)
    eq(ok,nil); eq(err:find("explicit confirmation",1,true)~=nil,true)
  end
  local ok,err=controller:clearSavedHistory()
  eq(ok,nil); eq(err:find("explicit confirmation",1,true)~=nil,true)
  eq(f.storageClears,0); eq(#controller:entries(),1)
end)

test("confirmed saved clear removes profile history from disk and memory",function()
  local f=fake(); f.storageRemoved=4; local notifications=0
  local controller=makeController(f,function() notifications=notifications+1 end)
  assert(controller:start()); assert(controller:capture("QUEST","remove me")); assert(controller:setFilter("QUEST")); local before=notifications
  local ok,removed=controller:clearSavedHistory(true)
  eq(ok,true); eq(removed,4); eq(f.storageClears,1); eq(f.storageClearConfirmed,true)
  eq(#controller.history:entries("ALL"),0); eq(controller.filter,"QUEST"); eq(controller.currentCharacterKey,"profile")
  eq(notifications,before+1); eq(#controller:handoff().entries,0)
  f.character="Gia"; assert(controller:syncCharacter()); eq(f.loadRecentCalls,1); eq(#controller:entries(),0)
end)

test("failed saved clear retains memory and reports the storage failure",function()
  local f=fake(); f.storageClearFailure=true; local controller=makeController(f); assert(controller:start()); assert(controller:capture("QUEST","retain after failure"))
  local ok,err=controller:clearSavedHistory(true)
  eq(ok,nil); eq(err,"delete denied"); eq(#controller:entries(),1); eq(f.storageClears,1); eq(f.errors,1)
end)

-- All retention scenarios use generated records and the in-memory fake storage.
local function copyRetentionValue(value)
  if type(value)~="table" then return value end
  local copy={}
  for key,item in pairs(value) do copy[key]=copyRetentionValue(item) end
  return copy
end

local function sameRetentionValue(actual,expected)
  if type(expected)~="table" then eq(actual,expected); return end
  eq(type(actual),"table")
  for key,value in pairs(expected) do sameRetentionValue(actual[key],value) end
  for key in pairs(actual) do assert(expected[key]~=nil,"unexpected setting "..tostring(key)) end
end

local function syntheticAdapter(entries)
  local f=fake(entries)
  f.character="SyntheticAlpha"; f.timestampValue="2026-10-04T00:00:00Z"
  return f
end

local function retentionController(f,limit,sources,onChange,onAccepted)
  local settings={visible_limit=limit or 1000,dedupe_seconds=3,all_sources=sources or allSources(),
    timestamps=false,tab_order={"STAFF","ALL","ROOM","PRIVATE","COMBAT"},personal_option="synthetic-option"}
  local controller=Controller.new(f,Parser,History.new(settings.visible_limit,settings.dedupe_seconds),f.storage,
    onChange or function() end,function() return f.character end,settings.all_sources,onAccepted)
  return controller,settings
end

local function newestRetentionEntries(entries,limit)
  local result={}
  for index=math.max(1,#entries-limit+1),#entries do result[#result+1]=entries[index] end
  return result
end

local function controllerRetentionFixture(limit)
  local entries,expected={},{}
  for index=1,limit+2 do
    for _,bucket in ipairs({"ROOM","WHISPER","ESP","DRAGON","SECIAN","CONTACT","MENTAL","PSYCIAN","STAFF","COMBAT","WORLD","ALL","OTHER"}) do
      local category=bucket
      if bucket=="ROOM" and index%2==0 then category="OWN" end
      if bucket=="OTHER" then
        category="SYNTHETIC_"..index
        if index%3==0 then category=nil elseif index%2==0 then category="" end
      end
      local entry={schema=1,timestamp="2026-10-04T00:00:00Z",character="SyntheticAlpha",
        category=category,message="synthetic-"..bucket.."-"..index,line="synthetic-"..bucket.."-"..index,source="custom"}
      entries[#entries+1]=entry
      if index>2 then expected[#expected+1]=entry end
    end
  end
  return entries,expected
end

local function captureRetentionFlood(controller,f)
  local lines={
    'SyntheticNeighbor says, "synthetic-room-seed."',
    'You say "synthetic-own-seed."',
    'SyntheticNeighbor whispers to you, "synthetic-whisper-seed."',
    'SyntheticRemote (ESP): "synthetic-esp-seed."',
    'You pick up SyntheticDragon\'s mental link, "synthetic-dragon-seed."',
    'You pick up SyntheticSecian\'s Secian link, "synthetic-secian-seed." [r-1]',
    'SyntheticContact thinks to you, "synthetic-contact-seed."',
    '[GUIDE] SyntheticGuide: synthetic-staff-seed.',
    'Your strength has increased!',
    'You pick up SyntheticNamedDragon\'s Dragon link, "synthetic-named-dragon-seed."',
    'You pick up SyntheticPsycian\'s Psycian link, "synthetic-psycian-seed."',
  }
  for _,line in ipairs(lines) do f.epochValue=f.epochValue+4; f:line(line) end
  f.epochValue=f.epochValue+4; assert(controller:capture("SYNTHETIC_QUEST","synthetic-custom-seed"))
  eq(f.storageAppends,12)
  local conversations={}
  for index,entry in ipairs(f.appendedEntries) do conversations[index]=entry end
  eq(table.concat(controller.history:categories(),","),"ROOM,OWN,WHISPER,MENTAL,SECIAN,STAFF,ALL,DRAGON,PSYCIAN,SYNTHETIC_QUEST")
  for index=1,1005 do
    f.epochValue=f.epochValue+4
    f:line("Your head takes "..index.." points of impact damage!")
  end
  eq(f.storageAppends,1017)
  local combat=newestRetentionEntries(f.appendedEntries,1000)
  local retained={}
  for _,entry in ipairs(conversations) do retained[#retained+1]=entry end
  for _,entry in ipairs(combat) do retained[#retained+1]=entry end
  return conversations,combat,retained
end

local function assertRetentionFlood(controller,conversations,combat,retained)
  sameViewEntries(controller.history:entries("ALL"),retained)
  eq(#retained,1012)
  assert(controller:setFilter("ALL")); sameEntries(controller:entries(),conversations)
  assert(controller:setFilter("ROOM")); sameEntries(controller:entries(),{conversations[1],conversations[2]})
  assert(controller:setFilter("OWN")); sameEntries(controller:entries(),{conversations[2]})
  for _,category in ipairs({"WHISPER","MENTAL","DRAGON","SECIAN","PSYCIAN","STAFF"}) do
    assert(controller:setFilter(category)); sameEntries(controller:entries(),sourceEntries(conversations,category))
  end
  assert(controller:setFilter("PRIVATE"))
  sameEntries(controller:entries(),{conversations[3],conversations[7]})
  assert(controller:setFilter("SYNTHETIC_QUEST")); sameEntries(controller:entries(),{conversations[12]})
  assert(controller:setFilter("COMBAT")); sameEntries(controller:entries(),combat)
  eq(combat[1].line,"Your head takes 6 points of impact damage!")
  eq(combat[1000].line,"Your head takes 1005 points of impact damage!")
  assert(controller:setFilter("ALL")); sameEntries(controller:entries(),conversations)
end

test("over a thousand live COMBAT lines preserve older chat with COMBAT off ALL and keep its own newest thousand",function()
  local f=syntheticAdapter(); local accepted=0; local redraw
  local defaultsBefore=copyRetentionValue(require("defaults").chat)
  local controller,settings=retentionController(f,1000,allSources(),function(entries) redraw=entries end,
    function() accepted=accepted+1 end)
  local settingsBefore=copyRetentionValue(settings)
  assert(controller:start())
  local conversations,combat,retained=captureRetentionFlood(controller,f)
  sameEntries(redraw,conversations); assertRetentionFlood(controller,conversations,combat,retained)
  eq(accepted,1017); eq(f.loadRecentCalls,1); eq(f.storageClears,0)
  local sourcesBefore=copyRetentionValue(controller.allSources)
  assert(controller:setAllSources(allSources({COMBAT=true})))
  sameEntries(controller:entries(),combat); sameEntries(redraw,combat)
  sameViewEntries(controller.history:entries("ALL"),retained)
  assert(controller:setAllSources(settings.all_sources)); sameEntries(controller:entries(),conversations)
  sameRetentionValue(controller.allSources,sourcesBefore)
  f:line(combat[1000].line); eq(accepted,1017); eq(f.storageAppends,1017)
  sameRetentionValue(settings,settingsBefore); sameRetentionValue(require("defaults").chat,defaultsBefore)
  assert(controller:shutdown())
end)

test("controller renders newest configured limit AFTER ALL source and PRIVATE filtering while history returns all matches",function()
  local saved,retained=controllerRetentionFixture(3)
  for _,entry in ipairs(saved) do
    if entry.category=="CONTACT" then
      entry.line='SyntheticContact thinks to you, "'..entry.message..'"'; entry.source="builtin"
    end
  end
  local f=syntheticAdapter(saved); local redraw
  local sources=allSources({ROOM=false,WHISPER=false,COMBAT=false})
  local controller,settings=retentionController(f,3,sources,function(entries) redraw=entries end)
  local settingsBefore=copyRetentionValue(settings)
  assert(controller:start()); sameViewEntries(controller.history:entries("ALL"),retained)
  local visible=controller.history:entries("ALL",sources)
  eq(#visible,30); sameEntries(controller:entries(),newestRetentionEntries(visible,3))
  sameEntries(redraw,controller:entries()); eq(controller:status().visible_count,3)
  assert(controller:setFilter("PRIVATE"))
  local private=controller.history:entries("PRIVATE",sources)
  eq(#private,6); sameEntries(controller:entries(),newestRetentionEntries(private,3))
  for _,entry in ipairs(private) do
    assert(entry.category=="WHISPER" or entry.line:match('^SyntheticContact thinks to you, "'))
  end
  sameEntries(redraw,controller:entries())
  assert(controller:setFilter("ROOM")); eq(#controller:entries(),3)
  assert(controller:setFilter("COMBAT")); eq(#controller:entries(),3)
  assert(controller:setFilter("ALL")); sameEntries(controller:entries(),newestRetentionEntries(visible,3))
  sameViewEntries(controller.history:entries("ALL"),retained)
  eq(controller.history.limit,3); eq(f.loadRecentCalls,1); eq(f.storageAppends,0); eq(f.storageClears,0)
  sameRetentionValue(settings,settingsBefore); assert(controller:shutdown())
end)

test("full update handoff copies every retained bucket up to thirteen thousand even from a filtered tab",function()
  local saved,retained=controllerRetentionFixture(1000)
  local f=syntheticAdapter(saved); local accepted=0
  local controller,settings=retentionController(f,1000,allSources(),nil,function() accepted=accepted+1 end)
  local settingsBefore=copyRetentionValue(settings)
  assert(controller:start()); assert(controller:setFilter("PRIVATE"))
  eq(#controller:entries(),1000); eq(#controller.history:entries("PRIVATE"),1000)
  local handoff=controller:handoff()
  eq(handoff.schema,1); eq(handoff.filter,"PRIVATE"); eq(handoff.partial,nil)
  eq(#handoff.entries,13000); sameEntries(handoff.entries,retained)
  for index,entry in ipairs(handoff.entries) do assert(entry~=retained[index],"handoff must copy retained entry "..index) end
  handoff.entries[1].message="synthetic-mutated-snapshot"
  sameViewEntries(controller.history:entries("ALL"),retained)
  eq(accepted,0); eq(f.storageAppends,0); eq(f.storageClears,0); eq(f.loadRecentCalls,1)
  sameRetentionValue(settings,settingsBefore); assert(controller:shutdown())
end)

for _,limit in ipairs({3,1000}) do
  test("full handoff restore bounds EACH bucket including shared OTHER at configured limit "..limit,function()
    local saved,retained=controllerRetentionFixture(limit)
    local handoff={schema=1,character_key="profile",filter="PRIVATE",entries=saved}
    local f=syntheticAdapter({{category="STAFF",message="synthetic-disk-must-not-load"}})
    local accepted,redraws=0,0
    local controller,settings=retentionController(f,limit,allSources({COMBAT=false,ROOM=false}),
      function() redraws=redraws+1 end,function() accepted=accepted+1 end)
    local settingsBefore=copyRetentionValue(settings); local expected=copyRetentionValue(retained)
    assert(controller:restoreHandoff(handoff)); assert(controller:start(true))
    sameViewEntries(controller.history:entries("ALL"),expected)
    eq(#controller.history.items,13*limit); assert(#controller.history.items<=13000)
    eq(#controller.history:entries("PRIVATE"),limit)
    sameEntries(controller:entries(),newestRetentionEntries(controller.history:entries("PRIVATE"),limit))
    eq(controller.filter,"PRIVATE"); eq(controller.history.limit,limit)
    eq(redraws,0); eq(accepted,0); eq(f.loadRecentCalls,0); eq(f.storageAppends,0); eq(f.storageClears,0)
    handoff.entries[21].message="synthetic-mutated-input"
    sameViewEntries(controller.history:entries("ALL"),expected)
    sameRetentionValue(settings,settingsBefore); assert(controller:shutdown())
  end)
end

test("combat-flood full update survives identity gaps character switches reconnect and silent duplicate suppression",function()
  local first=syntheticAdapter(); local original,settings=retentionController(first)
  local settingsBefore=copyRetentionValue(settings)
  assert(original:start())
  local conversations,combat,retained=captureRetentionFlood(original,first)
  assert(original:setFilter("ROOM"))
  local handoff=original:handoff(); sameEntries(handoff.entries,retained)
  eq(handoff.filter,"ROOM"); eq(handoff.last_key,original.history.lastKey); eq(handoff.last_epoch,first.epochValue)
  assert(original:shutdown()); eq(first:count(first.triggers),0)

  local second=syntheticAdapter(first.appendedEntries); second.character=nil; second.epochValue=first.epochValue
  local accepted,redraws=0,0
  local restored,restoredSettings=retentionController(second,settings.visible_limit,copyRetentionValue(settings.all_sources),
    function() redraws=redraws+1 end,function() accepted=accepted+1 end)
  assert(restored:restoreHandoff(handoff)); assert(restored:start(true))
  eq(restored.filter,"ROOM"); sameEntries(restored:entries(),{conversations[1],conversations[2]})
  eq(restored.history.lastKey,handoff.last_key); eq(restored.history.lastEpoch,handoff.last_epoch)
  eq(redraws,0); eq(accepted,0); eq(second.storageAppends,0); eq(second.loadRecentCalls,0)
  second:line(combat[1000].line)
  eq(accepted,0); eq(second.storageAppends,0); eq(redraws,0)
  for _,character in ipairs({"SyntheticBeta",false,"SyntheticAlpha"}) do
    second.character=character or nil; assert(restored:syncCharacter())
    sameViewEntries(restored.history:entries("ALL"),retained)
    eq(restored.currentCharacterKey,"profile")
  end
  assert(restored:shutdown()); eq(second:count(second.triggers),0)
  assert(restored:start(true)); eq(second:count(second.triggers),1)
  eq(second.loadRecentCalls,0); eq(accepted,0); eq(second.storageAppends,0); eq(redraws,0)
  assertRetentionFlood(restored,conversations,combat,retained)
  second.epochValue=second.epochValue+4; second:line('You say "synthetic-own-after-update."')
  second.epochValue=second.epochValue+4; second:line("[GUIDE] SyntheticGuide: synthetic-staff-after-update.")
  eq(accepted,2); eq(second.storageAppends,2); eq(second.storedCharacters[1],"SyntheticAlpha")
  assert(restored:setFilter("ROOM")); eq(#restored:entries(),3)
  sameEntries(newestRetentionEntries(restored:entries(),1),{second.appendedEntries[1]})
  assert(restored:setFilter("STAFF")); sameEntries(restored:entries(),{conversations[8],second.appendedEntries[2]})
  assert(restored:setFilter("COMBAT")); sameEntries(restored:entries(),combat)
  eq(second.storageClears,0)
  sameRetentionValue(settings,settingsBefore); sameRetentionValue(restoredSettings,settingsBefore)
  assert(restored:shutdown())
end)

for _,transition in ipairs({"character switches","reconnect","profile hydration"}) do
  test("combat-flood retention persists across "..transition.." without replay alerts or saved-history writes",function()
    local f=syntheticAdapter(); local accepted=0
    local controller,settings=retentionController(f,1000,allSources(),nil,function() accepted=accepted+1 end)
    local settingsBefore=copyRetentionValue(settings)
    assert(controller:start())
    local conversations,combat,retained=captureRetentionFlood(controller,f)
    eq(accepted,1017)
    if transition=="character switches" then
      for _,character in ipairs({"SyntheticBeta",false,"SyntheticAlpha"}) do
        f.character=character or nil; assert(controller:syncCharacter())
        sameViewEntries(controller.history:entries("ALL"),retained)
      end
    elseif transition=="reconnect" then
      assert(controller:shutdown()); eq(f:count(f.triggers),0)
      assert(controller:start()); assert(controller:start()); eq(f:count(f.triggers),1)
    else
      local saved={}
      for _,entry in ipairs(f.appendedEntries) do saved[#saved+1]=entry end
      saved[#saved+1]=conversations[1]; saved[#saved+1]=combat[1000]
      assert(controller:shutdown())
      f=syntheticAdapter(saved); accepted=0
      controller=retentionController(f,1000,settings.all_sources,nil,function() accepted=accepted+1 end)
      assert(controller:start()); eq(accepted,0); eq(f.storageAppends,0)
      assert(controller.history:hydrate(saved)); assert(controller.history:hydrate(saved))
    end
    assertRetentionFlood(controller,conversations,combat,retained)
    eq(accepted,transition=="profile hydration" and 0 or 1017)
    eq(f.storageAppends,transition=="profile hydration" and 0 or 1017)
    eq(f.loadRecentCalls,1); eq(f.storageClears,0); eq(controller.currentCharacterKey,"profile")
    sameRetentionValue(settings,settingsBefore); assert(controller:shutdown())
  end)
end

test("partial visible handoff hydrates all retained combat-flood buckets silently and deduplicates the overlap",function()
  local first=syntheticAdapter(); local original=retentionController(first)
  assert(original:start())
  local conversations,combat,retained=captureRetentionFlood(original,first)
  local handoff=original:handoff(); handoff.partial=true; handoff.entries=original:entries()
  sameEntries(handoff.entries,conversations); assert(original:shutdown())
  local second=syntheticAdapter(first.appendedEntries); second.epochValue=first.epochValue
  local accepted,redraws=0,0
  local restored=retentionController(second,1000,allSources(),function() redraws=redraws+1 end,
    function() accepted=accepted+1 end)
  assert(restored:restoreHandoff(handoff)); assert(restored:start(true))
  eq(second.loadRecentCalls,1); eq(second.storageAppends,0); eq(accepted,0); eq(redraws,0)
  sameViewEntries(restored.history:entries("ALL"),retained)
  second:line(combat[1000].line); eq(second.storageAppends,0); eq(accepted,0)
  assertRetentionFlood(restored,conversations,combat,retained)
  sameEntries(restored:handoff().entries,retained)
  eq(second.storageClears,0); assert(restored:shutdown())
end)

test("explicit clear after combat overflow is authoritative through full update character switches and reconnect",function()
  local first=syntheticAdapter(); local original=retentionController(first)
  assert(original:start())
  local _,combat=captureRetentionFlood(original,first)
  assert(original:setFilter("COMBAT"))
  local ok,removed=original:clearVisibleHistory()
  eq(ok,true); eq(removed,1012); eq(#original.history:entries("ALL"),0)
  eq(#original.history:categories(),0); eq(original.history.lastKey,nil); eq(original.history.lastEpoch,nil)
  local handoff=original:handoff()
  eq(#handoff.entries,0); eq(handoff.filter,"COMBAT"); eq(handoff.partial,nil)
  eq(handoff.last_key,nil); eq(handoff.last_epoch,nil)
  eq(first.storageClears,0); eq(first.storageAppends,1017); assert(original:shutdown())

  local second=syntheticAdapter(first.appendedEntries); second.epochValue=first.epochValue; second.character=nil
  local accepted=0
  local restored,settings=retentionController(second,1000,allSources(),nil,function() accepted=accepted+1 end)
  local settingsBefore=copyRetentionValue(settings)
  assert(restored:restoreHandoff(handoff)); assert(restored:start(true))
  second.character="SyntheticBeta"; assert(restored:syncCharacter())
  assert(restored:shutdown()); assert(restored:start(true))
  for _,filter in ipairs({"ALL","ROOM","OWN","PRIVATE","WHISPER","ESP","DRAGON","SECIAN","CONTACT","STAFF","COMBAT","SYNTHETIC_QUEST"}) do
    assert(restored:setFilter(filter)); eq(#restored:entries(),0)
  end
  eq(#restored:handoff().entries,0); eq(second.loadRecentCalls,0); eq(second.storageAppends,0); eq(accepted,0)
  sameRetentionValue(settings,settingsBefore)
  assert(restored:setFilter("ALL")); assert(restored:setAllSources(allSources({COMBAT=true})))
  eq(#restored:entries(),0)
  second:line(combat[1000].line)
  eq(second.storageAppends,1); eq(accepted,1); eq(#restored.history:entries("COMBAT"),1)
  second.epochValue=second.epochValue+4; second:line('SyntheticNeighbor says, "synthetic-after-clear."')
  eq(second.storageAppends,2); eq(accepted,2); eq(#restored.history:entries("ALL"),2)
  assert(restored:setFilter("ROOM")); sameEntries(restored:entries(),{second.appendedEntries[2]})
  eq(second.storageClears,0); assert(restored:shutdown())
end)

test("all mental formats capture while hidden in ALL and share dedicated and legacy filters",function()
  local lines={
    'Lark (ESP): "ESP fixture."',
    'Nera O\'Vale thinks to you, "Direct thoughts fixture."',
    'You pick up Nera O\'Vale\'s thoughts, "Ranked thoughts fixture." [r-1]',
    'You pick up Lark\'s thoughts echoing through the area, "Area thoughts fixture."',
    'You pick up Lark\'s mental link, "Generic fixture."',
    'Rook picks up Lark\'s mental link, "Third-person fixture." [r-27]',
  }
  local f=fake(); local accepted={}
  local sources={MENTAL=false,PSYCIAN=false}
  local controller=makeController(f,nil,function(entry) accepted[#accepted+1]=entry end,sources)
  assert(controller:start())
  for index,line in ipairs(lines) do
    f.epochValue=100+index*4
    f:line("\27[35m"..line.."\27[0m"); f:line(line)
    eq(f.storageAppends,index); eq(#accepted,index); eq(#controller:entries(),0)
    eq(accepted[index].category,"MENTAL"); eq(accepted[index].line,line)
    eq(controller.history.items[index],f.appendedEntries[index])
  end
  for _,filter in ipairs({"MENTAL"," esp ","CONTACT"}) do
    assert(controller:setFilter(filter)); sameEntries(controller:entries(),accepted)
    eq(controller.filter,"MENTAL")
  end
  assert(controller:setFilter("PRIVATE")); sameEntries(controller:entries(),{accepted[2]})
  assert(controller:setFilter("PSYCIAN")); eq(#controller:entries(),0)
  assert(controller:setFilter("ALL")); assert(controller:setAllSources({ESP=false,CONTACT=true,PSYCIAN=false}))
  sameEntries(controller:entries(),accepted)
  assert(controller:setAllSources({ESP=true,CONTACT=true,MENTAL=false,PSYCIAN=false}))
  eq(#controller:entries(),0); eq(f.storageAppends,#lines)
  local handoff=controller:handoff(); sameEntries(handoff.entries,f.appendedEntries)
  assert(controller:shutdown())
  for _,mode in ipairs({"reload","handoff"}) do
    local second=fake(f.appendedEntries); second.epochValue=f.epochValue
    local alerts=0
    local restored=makeController(second,nil,function() alerts=alerts+1 end,sources)
    if mode=="handoff" then assert(restored:restoreHandoff(handoff)) end
    assert(restored:start(true)); eq(#restored:entries(),0); eq(alerts,0); eq(second.storageAppends,0)
    for _,filter in ipairs({"MENTAL","ESP","CONTACT"}) do
      assert(restored:setFilter(filter)); sameEntries(restored:entries(),accepted)
    end
    assert(restored:setFilter("PRIVATE")); sameEntries(restored:entries(),{accepted[2]})
    assert(restored:setFilter("MENTAL"))
    if mode=="handoff" then second:line(lines[#lines]); eq(second.storageAppends,0); eq(alerts,0) end
    second.epochValue=second.epochValue+4; second:line('Lark (ESP): "Fresh fixture."')
    eq(second.storageAppends,1); eq(alerts,1); eq(#restored:entries(),#lines+1)
    eq(second.storageClears,0); assert(restored:shutdown())
  end
end)

test("hidden named Psycian Dragon and Secian links remain separate through reload",function()
  local f=fake(); local accepted={}
  local sources={MENTAL=false,PSYCIAN=false,DRAGON=false,SECIAN=false}
  local controller=makeController(f,nil,function(entry) accepted[#accepted+1]=entry end,sources)
  assert(controller:start())
  local categories={"PSYCIAN","DRAGON","SECIAN"}
  for index,kind in ipairs({"Psycian","Dragon","Secian"}) do
    local line='You pick up Lark\'s '..kind..' link, "Same fixture." [r-1]'
    f.epochValue=100+index*4; f:line(line); f:line(line)
    eq(f.storageAppends,index); eq(#accepted,index); eq(accepted[index].category,categories[index])
    eq(#controller:entries(),0); assert(controller:setFilter(categories[index]))
    sameEntries(controller:entries(),{accepted[index]}); assert(controller:setFilter("ALL"))
  end
  assert(controller:setFilter("MENTAL")); eq(#controller:entries(),0)
  assert(controller:setFilter("PRIVATE")); eq(#controller:entries(),0)
  assert(controller:shutdown())
  local second=fake(f.appendedEntries); local alerts=0
  local restored=makeController(second,nil,function() alerts=alerts+1 end,sources); assert(restored:start())
  eq(#restored:entries(),0)
  for index,category in ipairs(categories) do
    assert(restored:setFilter(category)); sameEntries(restored:entries(),{accepted[index]})
  end
  eq(second.storageAppends,0); eq(alerts,0); eq(second.storageClears,0); assert(restored:shutdown())
end)

test("legacy history reload and full handoff project views while preserving every raw field",function()
  local saved={
    {category="ESP",speaker="Lark",message="Named fixture.",line='You pick up Lark\'s Psycian link, "Named fixture." [r-1]'},
    {category="ESP",speaker="Rook",message="ESP fixture.",line='Rook (ESP): "ESP fixture."'},
    {category="CONTACT",speaker="Nera O'Vale",message="Contact fixture.",line='Nera O\'Vale thinks to you, "Contact fixture."'},
    {category="DRAGON",speaker="Lark",message="Generic fixture.",line='You pick up Lark\'s mental link, "Generic fixture."'},
    {category="DRAGON",speaker="Rook",message="Dragon fixture.",line='You pick up Rook\'s Dragon link, "Dragon fixture."'},
  }
  for _,entry in ipairs(saved) do
    entry.schema=1; entry.timestamp="2026-10-13T12:00:00Z"; entry.character="Synthetic Alpha"; entry.source="builtin"
  end
  local expectedRaw=copyRetentionValue(saved)
  local sources={MENTAL=false,PSYCIAN=false,DRAGON=false}
  local f=fake(saved); local alerts=0
  local controller=makeController(f,nil,function() alerts=alerts+1 end,sources)
  assert(controller:start()); eq(#controller:entries(),0); eq(alerts,0); eq(f.storageAppends,0)
  eq(table.concat(controller.history:categories(),","),"PSYCIAN,MENTAL,DRAGON")
  assert(controller:setFilter("PSYCIAN")); sameViewEntries(controller:entries(),{saved[1]})
  for _,filter in ipairs({"MENTAL","ESP","CONTACT"}) do
    assert(controller:setFilter(filter)); eq(controller.filter,"MENTAL")
    sameViewEntries(controller:entries(),{saved[2],saved[3],saved[4]})
  end
  assert(controller:setFilter("DRAGON")); sameEntries(controller:entries(),{saved[5]})
  assert(controller:setFilter("PRIVATE")); sameViewEntries(controller:entries(),{saved[3]})
  sameRetentionValue(saved,expectedRaw); sameEntries(controller.history.items,expectedRaw)
  local handoff=controller:handoff(); sameEntries(handoff.entries,expectedRaw)
  for index,entry in ipairs(handoff.entries) do assert(entry~=saved[index]) end
  assert(controller:shutdown())
  local second=fake(); local restored=makeController(second,nil,function() alerts=alerts+1 end,sources)
  assert(restored:restoreHandoff(handoff)); assert(restored:start(true))
  sameEntries(restored.history.items,expectedRaw); sameViewEntries(restored:entries(),{saved[3]})
  sameEntries(restored:handoff().entries,expectedRaw)
  eq(second.loadRecentCalls,0); eq(second.storageAppends,0); eq(alerts,0)
  eq(second.storageClears,0); sameRetentionValue(saved,expectedRaw); assert(restored:shutdown())
end)

test("old handoff filters and raw adjacent keys canonicalize silently with matching legacy records",function()
  for _,case in ipairs({
    {raw="ESP",filter=" esp ",effective="MENTAL",line='Lark (ESP): "Same fixture."'},
    {raw="CONTACT",filter="CONTACT",effective="MENTAL",line='Lark thinks to you, "Same fixture."'},
    {raw="DRAGON",filter="ESP",effective="MENTAL",line='You pick up Lark\'s mental link, "Same fixture."'},
    {raw="ESP",filter="PSYCIAN",effective="PSYCIAN",line='You pick up Lark\'s Psycian link, "Same fixture." [r-1]'},
  }) do
    local raw={schema=1,timestamp="2026-10-13T12:00:00Z",category=case.raw,speaker="Lark",
      message="Same fixture.",line=case.line,source="builtin"}
    -- Lua 5.1 legacy keys include the final gsub replacement count.
    local lastKey=table.concat({case.raw:lower(),"lark","","same fixture.",1},"\0")
    local handoff={schema=1,filter=case.filter,entries={raw},last_key=lastKey,last_epoch=100}
    local f=fake(); local alerts=0
    local restored=makeController(f,nil,function() alerts=alerts+1 end,{MENTAL=false,PSYCIAN=false})
    assert(restored:restoreHandoff(handoff)); assert(restored:start(true))
    eq(restored.filter,case.effective); eq(restored:status().active_filter,case.effective)
    eq(restored.history.items[1].category,case.raw); eq(restored:entries()[1].category,case.effective)
    f.epochValue=103; f:line(case.line); eq(f.storageAppends,0); eq(alerts,0)
    eq(restored.history.lastEpoch,100); eq(#restored.history.items,1)
    f.epochValue=104; f:line(case.line); eq(f.storageAppends,1); eq(alerts,1)
    eq(f.appendedEntries[1].category,case.effective); eq(#restored:entries(),2)
    eq(raw.category,case.raw); eq(restored:handoff().entries[1].category,case.raw)
    eq(f.loadRecentCalls,0); eq(f.storageClears,0); assert(restored:shutdown())
  end
  local f=fake(); local controller=makeController(f); assert(controller:start())
  local value,message=controller:setFilter("bad category!")
  eq(value,nil); eq(message,"invalid chat category"); eq(controller.filter,"ALL")
  assert(controller:shutdown())
end)

test("partial projected legacy handoffs prefer raw disk records and deduplicate their overlap",function()
  for _,case in ipairs({
    {raw="ESP",effective="PSYCIAN",line='You pick up Lark\'s Psycian link, "Same fixture." [r-1]'},
    {raw="DRAGON",effective="MENTAL",line='You pick up Lark\'s mental link, "Same fixture."'},
    {raw="CONTACT",effective="MENTAL",line='Lark thinks to you, "Same fixture."'},
  }) do
    local raw={schema=1,timestamp="2026-10-13T12:00:00Z",category=case.raw,speaker="Lark",
      message="Same fixture.",line=case.line,source="builtin"}
    local f=fake({raw}); local alerts=0
    local controller=makeController(f,nil,function() alerts=alerts+1 end,{MENTAL=false,PSYCIAN=false})
    local lastKey=table.concat({case.raw:lower(),"lark","","same fixture.",1},"\0")
    local handoff={schema=1,partial=true,filter="ALL",entries={Channels.project(raw)},last_key=lastKey,last_epoch=100}
    assert(controller:restoreHandoff(handoff)); assert(controller:start(true))
    eq(#controller:entries(),0); eq(#controller.history.items,1)
    eq(controller.history.items[1],raw); eq(raw.category,case.raw)
    assert(controller:setFilter(case.effective)); eq(controller:entries()[1].category,case.effective)
    eq(controller:handoff().entries[1].category,case.raw); eq(#controller:handoff().entries,1)
    f:line(case.line); eq(f.storageAppends,0); eq(alerts,0)
    eq(f.loadRecentCalls,1); eq(f.storageClears,0); assert(controller:shutdown())
  end
end)

test("incomplete mental lines do not buffer or consume the following chat",function()
  for _,kind in ipairs({"Psycian","Dragon","Secian","mental"}) do
    local f=fake(); local accepted={}
    local controller=makeController(f,nil,function(entry) accepted[#accepted+1]=entry end)
    assert(controller:start())
    f:line('You pick up Lark\'s '..kind..' link, "Wrapped fixture')
    f:line('continuation." [r-1]')
    eq(f.storageAppends,0); eq(#accepted,0); eq(controller.pendingStaffMessage,nil); eq(next(f.timers),nil)
    local line='Rook says, "Following room fixture."'
    f:line(line); eq(f.storageAppends,1); eq(#accepted,1)
    eq(accepted[1].category,"ROOM"); eq(accepted[1].line,line); eq(accepted[1].message,"Following room fixture.")
    eq(f.storageClears,0); assert(controller:shutdown())
  end
end)

local collisionMentalLines={
  esp='Tester (ESP): "hello"',
  contact='Tester thinks to you, "hello"',
  link='You pick up Tester\'s mental link, "hello"',
}

test("owned trigger captures same-body ESP contact and generic mental frames separately with ALL off",function()
  local f=fake(); local accepted={}
  local controller=makeController(f,nil,function(entry) accepted[#accepted+1]=entry end,{MENTAL=false})
  assert(controller:start())
  for index,kind in ipairs({"esp","contact","link"}) do
    f.epochValue=99+index; f:line(collisionMentalLines[kind]); f:line(collisionMentalLines[kind])
    eq(f.storageAppends,index); eq(#accepted,index); eq(controller.history.lastMentalKind,kind)
    eq(#controller:entries(),0); eq(accepted[index].category,"MENTAL"); eq(accepted[index].line,collisionMentalLines[kind])
    eq(accepted[index].lastMentalKind,nil); eq(accepted[index].mental_kind,nil)
  end
  assert(controller:setFilter("MENTAL")); sameEntries(controller:entries(),accepted)
  local handoff=controller:handoff(); eq(handoff.last_mental_kind,"link"); sameEntries(handoff.entries,accepted)
  assert(controller:shutdown())
  for _,mode in ipairs({"reload","handoff"}) do
    local second=fake(f.appendedEntries); second.epochValue=f.epochValue; local alerts=0
    local restored=makeController(second,nil,function() alerts=alerts+1 end,{MENTAL=false})
    if mode=="handoff" then assert(restored:restoreHandoff(handoff)) end
    assert(restored:start(true)); eq(alerts,0); eq(second.storageAppends,0)
    assert(restored:setFilter("MENTAL")); sameEntries(restored:entries(),accepted)
    if mode=="handoff" then second:line(collisionMentalLines.link); eq(second.storageAppends,0); eq(alerts,0) end
    second.epochValue=103; second:line(collisionMentalLines.contact)
    eq(second.storageAppends,1); eq(alerts,1); eq(#restored:entries(),4)
    eq(second.storageClears,0); assert(restored:shutdown())
  end
end)

test("unknown GMCP originals gain transient text family and preserve it through a silent handoff",function()
  for _,kind in ipairs({"esp","contact","link"}) do
    local f=fake(); local accepted=0
    local controller=makeController(f,nil,function() accepted=accepted+1 end,{MENTAL=false})
    assert(controller:start()); assert(controller:capture("MENTAL","hello",{speaker="Tester"}))
    local original=f.appendedEntries[1]; local saved=copyRetentionValue(original)
    eq(controller.history.lastMentalKind,nil)
    f.epochValue=101; f:line(collisionMentalLines[kind])
    eq(f.storageAppends,1); eq(accepted,1); eq(controller.history.lastMentalKind,kind)
    eq(controller.history.lastEpoch,100); sameRetentionValue(original,saved)
    local handoff=controller:handoff(); eq(handoff.last_mental_kind,kind); sameEntries(handoff.entries,{original})
    eq(handoff.entries[1].lastMentalKind,nil); eq(handoff.entries[1].mental_kind,nil)
    assert(controller:shutdown())
    local second=fake(); second.epochValue=102; local alerts=0
    local restored=makeController(second,nil,function() alerts=alerts+1 end,{MENTAL=false})
    assert(restored:restoreHandoff(handoff)); assert(restored:start(true))
    eq(restored.history.lastMentalKind,kind); eq(second.loadRecentCalls,0)
    second:line(collisionMentalLines[kind]); assert(restored:capture("MENTAL","hello",{speaker="Tester"}))
    eq(second.storageAppends,0); eq(alerts,0); eq(restored.history.lastMentalKind,kind)
    local other=kind=="contact" and "esp" or "contact"
    second:line(collisionMentalLines[other]); eq(second.storageAppends,1); eq(alerts,1)
    eq(restored.history.lastMentalKind,other); eq(#restored.history.items,2)
    sameRetentionValue(restored.history.items[1],saved)
    eq(second.storageClears,0); assert(restored:shutdown())
  end
end)

test("older handoffs derive raw ESP CONTACT and generic link families and retain later distinct frames",function()
  for _,case in ipairs({
    {kind="esp",raw="ESP"},{kind="contact",raw="CONTACT"},{kind="link",raw="DRAGON"},
  }) do
    local raw={category=case.raw,speaker="Tester",message="hello",line=collisionMentalLines[case.kind],source="builtin"}
    local handoff={schema=1,filter="MENTAL",entries={raw},
      last_key=table.concat({case.raw:lower(),"tester","","hello",0},"\0"),last_epoch=100}
    local f=fake(); f.epochValue=101; local alerts=0
    local controller=makeController(f,nil,function() alerts=alerts+1 end,{MENTAL=false})
    assert(controller:restoreHandoff(handoff)); assert(controller:start(true))
    eq(controller.history.lastMentalKind,case.kind)
    f:line(collisionMentalLines[case.kind]); eq(f.storageAppends,0); eq(alerts,0)
    local other=case.kind=="esp" and "contact" or "esp"
    f:line(collisionMentalLines[other]); eq(f.storageAppends,1); eq(alerts,1)
    eq(controller.history.items[1].category,case.raw); eq(raw.category,case.raw)
    eq(raw.lastMentalKind,nil); eq(raw.mental_kind,nil); eq(f.loadRecentCalls,0)
    assert(controller:shutdown())
  end
end)

test("handoff family values are whitelisted and clear cannot restore stale transient state",function()
  for _,value in ipairs({"none","ESP","invalid",false,true,17,{}}) do
    local f=fake(); local original=makeController(f); assert(original:start())
    assert(original:capture("MENTAL","hello",{speaker="Tester"}))
    local handoff=original:handoff(); handoff.last_mental_kind=value; assert(original:shutdown())
    local second=fake(); local restored=makeController(second)
    assert(restored:restoreHandoff(handoff)); assert(restored:start(true))
    eq(restored.history.lastMentalKind,nil)
    second.epochValue=101; second:line(collisionMentalLines.esp)
    eq(second.storageAppends,0); eq(restored.history.lastMentalKind,"esp")
    assert(restored:clearVisibleHistory()); eq(restored.history.lastMentalKind,nil)
    local cleared=restored:handoff(); eq(cleared.last_mental_kind,nil); eq(#cleared.entries,0)
    cleared.last_mental_kind="contact"
    local empty=makeController(fake()); assert(empty:restoreHandoff(cleared)); assert(empty:start(true))
    eq(empty.history.lastMentalKind,nil); eq(#empty.history.items,0); assert(empty:shutdown())
    assert(restored:shutdown())
  end
end)

local function outgoingAdapter(entries)
  local f=fake(entries); f.events={}; f.active=true; f.eventAdds=0; f.eventKills=0; f.sideEffects=0
  function f:isCharacterActive()
    if self.activeFailure then error("synthetic active guard failure") end
    return self.active
  end
  function f:addEvent(name,fn)
    if self.eventFailure then return nil,"synthetic observer failure" end
    self.next=self.next+1; local id=self.next
    self.events[id]={name=name,fn=fn}; self.eventAdds=self.eventAdds+1; return id
  end
  function f:killEvent(id) self.events[id]=nil; self.eventKills=self.eventKills+1; return true end
  function f:outgoing(command)
    for _,event in pairs(self.events) do
      eq(event.name,"sysDataSendRequest"); event.fn(event.name,command)
    end
  end
  local function sideEffect() f.sideEffects=f.sideEffects+1 end
  f.send=sideEffect; f.sendCommand=sideEffect; f.gag=sideEffect; f.deleteLine=sideEffect
  return f
end

test("outgoing observer defaults on registers once and cleans up on disable shutdown and restart",function()
  local f=outgoingAdapter(); local controller=makeController(f)
  eq(controller.captureOutgoing,true); eq(f.eventAdds,0)
  assert(controller:start()); assert(controller:start()); eq(f.eventAdds,1); eq(f:count(f.events),1)
  local stale=f.events[controller.outgoingEvent].fn
  f:outgoing("contact all hello"); eq(f.storageAppends,1)
  assert(controller:setCaptureOutgoing(false)); eq(f:count(f.events),0); eq(#controller.outgoing.pending,0)
  stale("sysDataSendRequest","contact all ignored"); eq(f.storageAppends,1)
  assert(controller:setCaptureOutgoing(true)); assert(controller:setCaptureOutgoing(true)); eq(f.eventAdds,2)
  stale("sysDataSendRequest","contact all ignored after reenable"); eq(f.storageAppends,1)
  f:outgoing("contact room second"); eq(f.storageAppends,2)
  local retired=f.events[controller.outgoingEvent].fn
  assert(controller:shutdown()); eq(f:count(f.events),0); eq(f:count(f.triggers),0)
  eq(#controller.outgoing.pending,0); retired("sysDataSendRequest","contact all ignored after shutdown")
  assert(controller:start()); retired("sysDataSendRequest","contact all ignored after restart")
  eq(f.storageAppends,2); f:outgoing("contact Aerin fresh"); eq(f.storageAppends,3)
  eq(f.sideEffects,0); assert(controller:shutdown()); eq(f.eventKills,3)
end)

test("outgoing can start disabled and remains optional for adapters without events",function()
  local f=outgoingAdapter()
  local controller=Controller.new(f,Parser,History.new(1000,3),f.storage,nil,function() return f.character end,nil,nil,false)
  assert(controller:start()); eq(controller.captureOutgoing,false); eq(f.eventAdds,0)
  eq(controller:onOutgoing("contact all ignored"),false)
  eq(controller:setCaptureOutgoing("true"),nil); eq(controller.captureOutgoing,false)
  assert(controller:setCaptureOutgoing(true)); eq(f.eventAdds,1); assert(controller:shutdown())
  f=fake(); controller=makeController(f)
  assert(controller:start()); eq(controller.outgoingEvent,nil)
  f:line('[GM] Keeper: Incoming still works.'); eq(f.storageAppends,1)
  eq(controller:onOutgoing("contact all no active guard"),false); assert(controller:shutdown())
end)

test("outgoing event registration failure rolls back owned trigger and can retry",function()
  local f=outgoingAdapter(); f.eventFailure=true
  local controller=makeController(f); local ok,err=controller:start()
  eq(ok,nil); assert(type(err)=="string"); eq(controller.started,false)
  eq(f:count(f.triggers),0); eq(f:count(f.events),0)
  f.eventFailure=false; assert(controller:start()); eq(f:count(f.events),1); assert(controller:shutdown())
end)

test("outgoing requires strictly active adapter and confirmed self provider before any transcript",function()
  local f=outgoingAdapter(); local controller=makeController(f); assert(controller:start())
  for _,active in ipairs({false,"true",1,{}}) do
    f.active=active; f:outgoing("contact all synthetic auth input"); eq(f.storageAppends,0)
  end
  f.active=nil; f:outgoing("contact all synthetic auth input"); eq(f.storageAppends,0)
  f.activeFailure=true; f:outgoing("contact all synthetic auth input"); eq(f.storageAppends,0)
  f.activeFailure=false; f.active=true
  for _,character in ipairs({"Unknown"," unknown ","",false,1,{}}) do
    f.character=character; f:outgoing("contact all synthetic auth input"); eq(f.storageAppends,0)
  end
  f.character=nil; f:outgoing("contact all synthetic auth input"); eq(f.storageAppends,0)
  controller.characterProvider=function() error("synthetic provider failure") end
  f:outgoing("contact all synthetic auth input"); eq(f.storageAppends,0)
  controller.characterProvider=function() return "Dace Alterac" end
  f:outgoing("password synthetic-placeholder"); f:outgoing("contact"); f:outgoing("contact help syntax")
  f:outgoing("psi all ignored"); f:outgoing("contact all first\ncontact room second"); eq(f.storageAppends,0)
  f:outgoing("CONTACT Aerin hello"); eq(f.storageAppends,1)
  eq(f.appendedEntries[1].speaker,"Dace Alterac"); eq(f.sideEffects,0); eq(f.errors,0)
  assert(controller:shutdown())
end)

test("outgoing transcripts stay silent hidden sources still retain them and rapid repeats survive dedupe",function()
  local f=outgoingAdapter(); local alerts=0
  local controller=makeController(f,nil,function() alerts=alerts+1 end,allSources({MENTAL=false}))
  assert(controller:start())
  for _,target in ipairs({"all","all","room","Aerin","Aerin","Beren"}) do f:outgoing("contact "..target.." Exact body") end
  eq(f.storageAppends,6); eq(#controller.history.items,6); eq(#controller:entries(),0); eq(alerts,0)
  assert(controller:setFilter("MENTAL")); eq(#controller:entries(),6)
  assert(controller:setFilter("PRIVATE"))
  sameEntries(controller:entries(),{controller.history.items[4],controller.history.items[5],controller.history.items[6]})
  assert(controller:setLinkCombined(true)); assert(controller:setFilter(Channels.linkFilter))
  sameEntries(controller:entries(),{controller.history.items[1],controller.history.items[2],controller.history.items[3]})
  for index,entry in ipairs(controller.history.items) do
    eq(entry.category,"MENTAL"); eq(entry.source,"outgoing"); eq(entry.character,f.character)
    eq(entry.speaker,f.character); eq(entry.message,"Exact body")
    eq(entry.line,"You -> "..entry.target.." (outgoing request): Exact body")
    eq(entry.skipDedupe,nil); eq(entry.pending,nil); eq(entry.delivered,nil)
    eq(f.appendedEntries[index],entry)
  end
  eq(f.sideEffects,0); assert(controller:shutdown())
end)

test("outgoing broadcast reconciliation matches one pending request and leaves uncertain incoming visible",function()
  local f=outgoingAdapter(); f.character="Nera_O'Vale"; local alerts=0
  local controller=makeController(f,nil,function() alerts=alerts+1 end); assert(controller:start())
  f:outgoing("contact all Same body"); f:outgoing("contact all Same body")
  f:outgoing("contact room Same body"); f:outgoing("contact Aerin Same body")
  f:outgoing("contact Beren Same body"); eq(f.storageAppends,5)
  local all='You pick up Nera_O\'Vale\'s thoughts, "Same body" [r-1]'
  local room='You pick up Nera_O\'Vale\'s thoughts echoing through the area, "Same body"'
  f:line(room); f:line(all); f:line(all); eq(f.storageAppends,5); eq(alerts,0)
  eq(#controller.outgoing.pending,2)
  f:line(all); eq(f.storageAppends,6); eq(alerts,1)
  f:line('Someone thinks to you, "Same body"'); eq(f.storageAppends,7); eq(alerts,2)
  f:line('Nera_O\'Vale thinks to you, "Same body"'); eq(f.storageAppends,8); eq(alerts,3)
  f:line('Nera (ESP): "Same body"'); eq(f.storageAppends,9); eq(alerts,4)
  f:line(room); eq(f.storageAppends,10); eq(alerts,5)
  eq(f.sideEffects,0); assert(controller:shutdown())
end)

test("outgoing pending requests expire clear on identity loss and never enter handoff or replay",function()
  local f=outgoingAdapter(); f.character="Lark"; local controller=makeController(f); assert(controller:start())
  f:outgoing("contact all expiry"); f.epochValue=106
  f:line('You pick up Lark\'s thoughts, "expiry"'); eq(f.storageAppends,2)
  f:outgoing("contact all identity"); f.active=false; f:outgoing("contact all ignored")
  f.active=true; f:line('You pick up Lark\'s thoughts, "identity"'); eq(f.storageAppends,4)
  f:outgoing("contact room handoff"); local snapshot=controller:handoff()
  eq(#controller.outgoing.pending,0); eq(snapshot.pending,nil); eq(snapshot.outgoing,nil)
  assert(controller:shutdown())
  local second=outgoingAdapter(); second.character="Lark"; local restored=makeController(second)
  assert(restored:restoreHandoff(snapshot)); assert(restored:start(true))
  eq(second.storageAppends,0); eq(second.sideEffects,0); eq(#restored.outgoing.pending,0)
  second:line('You pick up Lark\'s thoughts echoing through the area, "handoff"')
  eq(second.storageAppends,1); eq(second.sideEffects,0); assert(restored:shutdown())
end)

test("clearing history discards only transient outgoing matches and leaves capture enabled",function()
  for _,mode in ipairs({"visible","saved"}) do
    local f=outgoingAdapter(); f.character="Lark"; local controller=makeController(f); assert(controller:start())
    f:outgoing("contact all before clear"); eq(#controller.outgoing.pending,1)
    if mode=="saved" then assert(controller:clearSavedHistory(true)) else assert(controller:clearVisibleHistory()) end
    eq(#controller.outgoing.pending,0); eq(controller.captureOutgoing,true); eq(f:count(f.events),1)
    f:line('You pick up Lark\'s thoughts, "before clear"'); eq(f.storageAppends,2)
    f:outgoing("contact all after clear"); eq(f.storageAppends,3); assert(controller:shutdown())
  end
end)

test("outgoing CONTACT flushes an earlier wrapped STAFF message without attaching its own text",function()
  local f=outgoingAdapter(); local alerts=0
  local controller=makeController(f,nil,function() alerts=alerts+1 end); assert(controller:start())
  f:line("[GM] Keeper [sample-user] submits an idea: Earlier staff text")
  eq(f.storageAppends,0); assert(controller.pendingStaffMessage)
  f:outgoing("contact all New contact text")
  eq(f.storageAppends,2); eq(alerts,1); eq(controller.pendingStaffMessage,nil)
  eq(f.appendedEntries[1].category,"STAFF"); eq(f.appendedEntries[2].source,"outgoing")
  assert(not f.appendedEntries[1].message:find("New contact text",1,true))
  eq(next(f.timers),nil); assert(controller:shutdown())
end)

test("outgoing short own server broadcasts reconcile only with matching full GMCP identity",function()
  local f=outgoingAdapter(); f.character="Wizzy Dizzy"
  f.gmcp={Char={Status={name="Wizzy",surname="Dizzy"}}}
  function f:getGMCP() return self.gmcp end
  local alerts=0; local controller=makeController(f,nil,function() alerts=alerts+1 end)
  assert(controller:start())
  f:outgoing("contact all Same body"); f:outgoing("contact room Same body")
  eq(f.storageAppends,2)
  f:line('You pick up Other\'s thoughts, "Same body"')
  f:line('You pick up Wizzy Other\'s thoughts, "Same body"')
  eq(f.storageAppends,4); eq(alerts,2); eq(#controller.outgoing.pending,2)
  f:line('You pick up Wizzy\'s thoughts, "Same body" [r-1]')
  f:line('You pick up Wizzy\'s thoughts echoing through the area, "Same body"')
  eq(f.storageAppends,4); eq(alerts,2); eq(#controller.outgoing.pending,0)
  eq(f.appendedEntries[1].speaker,"Wizzy Dizzy"); eq(f.appendedEntries[2].speaker,"Wizzy Dizzy")
  eq(f.appendedEntries[3].speaker,"Other"); eq(f.appendedEntries[4].speaker,"Wizzy Other")
  f:outgoing("contact Nera Direct body")
  f:line('Wizzy thinks to you, "Direct body"')
  eq(f.storageAppends,6); eq(alerts,3); eq(#controller.outgoing.pending,1)
  for _,entry in ipairs(controller.history.items) do eq(entry.delivered,nil) end
  eq(f.sideEffects,0); assert(controller:shutdown())
end)

test("outgoing never guesses short prefixes or trusts stale missing or failed GMCP",function()
  for _,data in ipairs({
    {}, {Char={Status={name="Wizzy"}}},
    {Char={Status={name="Wizzy",surname="Other"}}},
    {Char={Status={name="Other",surname="Dizzy"}}},
    {Char={Status={name="Wizzy",surname="Dizzy\n"}}}, false,
  }) do
    local f=outgoingAdapter(); f.character="Wizzy Dizzy"; f.gmcp=data
    function f:getGMCP() return self.gmcp end
    local controller=makeController(f); assert(controller:start())
    f:outgoing("contact all Same body")
    f:line('You pick up Wizzy\'s thoughts, "Same body"')
    eq(f.storageAppends,2); eq(#controller.outgoing.pending,1); assert(controller:shutdown())
  end
  local f=outgoingAdapter(); f.character="Wizzy Dizzy"
  function f:getGMCP() error("synthetic GMCP failure") end
  local controller=makeController(f); assert(controller:start())
  f:outgoing("contact room Same body")
  f:line('You pick up Wizzy\'s thoughts echoing through the area, "Same body"')
  eq(f.storageAppends,2); assert(controller:shutdown())
end)

test("outgoing short identity is verified at send and again when the echo arrives",function()
  for _,change in ipairs({"lost","arrived"}) do
    local f=outgoingAdapter(); f.character="Wizzy Dizzy"
    local verified={Char={Status={name="Wizzy",surname="Dizzy"}}}
    f.gmcp=change=="lost" and verified or {}
    function f:getGMCP() return self.gmcp end
    local controller=makeController(f); assert(controller:start())
    f:outgoing("contact all Same body")
    f.gmcp=change=="lost" and {Char={Status={name="Wizzy",surname="Other"}}} or verified
    f:line('You pick up Wizzy\'s thoughts, "Same body"')
    eq(f.storageAppends,2); eq(#controller.outgoing.pending,1); assert(controller:shutdown())
  end
end)

test("outgoing intentional repeats keep unique bounded IDs across same-second reloads and handoffs",function()
  local f=outgoingAdapter(); local controller=makeController(f); assert(controller:start())
  for index=1,3 do f:outgoing("contact all Same body") end
  local snapshot=controller:handoff(); eq(#snapshot.entries,3); assert(controller:shutdown())
  for _,mode in ipairs({"reload","handoff"}) do
    local second=outgoingAdapter(mode=="reload" and snapshot.entries or nil)
    local restored=makeController(second)
    if mode=="handoff" then assert(restored:restoreHandoff(snapshot)) end
    assert(restored:start(true)); eq(#restored.history.items,3)
    second:outgoing("contact all Same body"); second:outgoing("contact all Same body")
    eq(#restored.history.items,5); eq(second.storageAppends,2)
    local seen={}
    for _,entry in ipairs(restored.history.items) do
      assert(type(entry.outgoing_id)=="string" and #entry.outgoing_id<=64)
      assert(not seen[entry.outgoing_id]); seen[entry.outgoing_id]=true
    end
    assert(restored:shutdown())
  end
end)

test("combined link controller passes its flag and restores constituent filters on disable",function()
  for _,filter in ipairs({"MENTAL","DRAGON","PSYCIAN","SECIAN","ESP","CONTACT"}) do
    local f=fake(); local controller=makeController(f); assert(controller:start()); assert(controller:setFilter(filter))
    local expected=Channels.category(filter); local originalEntries=controller.history.entries; local seen
    function controller.history:entries(selected,sources,combined)
      seen={selected=selected,sources=sources,combined=combined}
      return originalEntries(self,selected,sources,combined)
    end
    eq(controller.linkCombined,false); assert(controller:setLinkCombined(true))
    eq(controller.filter,Channels.linkFilter); eq(controller.linkPriorFilter,expected)
    controller:entries(); eq(seen.selected,Channels.linkFilter); eq(seen.combined,true); eq(seen.sources,controller.allSources)
    assert(controller:setLinkCombined(false)); eq(controller.filter,expected); eq(controller.linkPriorFilter,nil)
    controller:entries(); eq(seen.combined,false); assert(controller:shutdown())
  end
end)

test("combined link mode leaves ALL STAFF and personal LINK selection and content unchanged",function()
  for _,filter in ipairs({"ALL","STAFF","LINK","PERSONAL"}) do
    local f=fake(); local controller=makeController(f); assert(controller:start())
    assert(controller:capture("LINK","Personal LINK fixture",{speaker="Synthetic"}))
    assert(controller:setFilter(filter)); assert(controller:setLinkCombined(true)); eq(controller.filter,filter)
    eq(controller.history.items[1].category,"LINK"); eq(controller.history.items[1].message,"Personal LINK fixture")
    assert(controller:setLinkCombined(false)); eq(controller.filter,filter)
    eq(controller:setLinkCombined("true"),nil); eq(controller.linkCombined,false)
    assert(controller:shutdown())
  end
  local controller=makeController(fake()); assert(controller:start()); assert(controller:setFilter("MENTAL"))
  assert(controller:setLinkCombined(true)); assert(controller:setFilter("STAFF"))
  assert(controller:setLinkCombined(false)); eq(controller.filter,"STAFF"); assert(controller:shutdown())
end)

test("combined link mode redirects constituent selection and remembers the selected constituent",function()
  local controller=makeController(fake()); assert(controller:start()); assert(controller:setLinkCombined(true))
  assert(controller:setFilter("PSYCIAN")); eq(controller.filter,Channels.linkFilter); eq(controller.linkPriorFilter,"PSYCIAN")
  assert(controller:setFilter(Channels.linkFilter)); assert(controller:setLinkCombined(false)); eq(controller.filter,"PSYCIAN")
  eq(controller:setFilter("not\nvalid"),nil); eq(controller:setFilter(string.rep("A",33)),nil)
  assert(controller:shutdown())
end)

test("a stored custom LINK VIEW and future personal captures leave combined mode enabled",function()
  local f=fake({{category="LINK VIEW",message="Existing custom",source="custom"}})
  local controller=makeController(f); assert(controller:setLinkCombined(true)); assert(controller:start())
  eq(controller.linkCombined,true)
  assert(controller:setFilter("LINK VIEW")); eq(controller:entries()[1].message,"Existing custom"); assert(controller:shutdown())
  f=fake(); controller=makeController(f); assert(controller:start()); assert(controller:setFilter("DRAGON"))
  assert(controller:setLinkCombined(true)); local append=controller.history.append
  function controller.history:append(entry,epoch,options)
    if entry.category=="LINK VIEW" or entry.category=="LINK" then eq(controller.linkCombined,true); eq(controller.filter,Channels.linkFilter) end
    return append(self,entry,epoch,options)
  end
  assert(controller:capture("LINK VIEW","Future real custom",{speaker="Synthetic"}))
  assert(controller:capture("LINK","Future LINK custom",{speaker="Synthetic"}))
  eq(controller.linkCombined,true); eq(f.storageAppends,2)
  eq(f.appendedEntries[1].category,"LINK VIEW"); eq(f.appendedEntries[1].source,"custom")
  eq(#controller:entries(),0)
  assert(controller:setFilter("LINK VIEW")); eq(#controller:entries(),1); eq(controller:entries()[1].message,"Future real custom")
  assert(controller:setFilter("LINK")); eq(#controller:entries(),1); eq(controller:entries()[1].message,"Future LINK custom")
  assert(controller:setLinkCombined(true)); assert(controller:shutdown())
end)

test("disabling combined links preserves a personal LINK VIEW selection including after restore",function()
  local f=fake(); local controller=makeController(f); assert(controller:start())
  assert(controller:capture("LINK VIEW","Personal virtual-name fixture",{speaker="Synthetic"}))
  assert(controller:setFilter("LINK VIEW"))
  assert(controller:setLinkCombined(false)); eq(controller.filter,"LINK VIEW")
  eq(controller:entries()[1].message,"Personal virtual-name fixture")
  local snapshot=controller:handoff(); assert(controller:shutdown())
  local restored=makeController(fake()); assert(restored:restoreHandoff(snapshot))
  assert(restored:setLinkCombined(false)); assert(restored:start(true))
  eq(restored.filter,"LINK VIEW"); eq(restored:entries()[1].message,"Personal virtual-name fixture")
  assert(restored:setLinkCombined(true)); eq(restored.filter,"LINK VIEW")
  assert(restored:shutdown())
end)

test("combined link handoff carries only bounded prior filter and mode applies after restore",function()
  local f=fake(); local controller=makeController(f); assert(controller:start()); assert(controller:setFilter("SECIAN"))
  assert(controller:setLinkCombined(true)); local snapshot=controller:handoff()
  eq(snapshot.filter,Channels.linkFilter); eq(snapshot.previous_link_filter,"SECIAN"); eq(snapshot.linkCombined,nil)
  assert(controller:shutdown())
  local restored=makeController(fake()); assert(restored:restoreHandoff(snapshot)); assert(restored:setLinkCombined(true))
  assert(restored:start(true)); eq(restored.filter,Channels.linkFilter)
  assert(restored:setLinkCombined(false)); eq(restored.filter,"SECIAN"); assert(restored:shutdown())
  for _,value in ipairs({string.rep("A",33),"bad\nfilter",{},"LINK VIEW",Channels.linkFilter,"STAFF",false,12}) do
    snapshot.previous_link_filter=value; restored=makeController(fake())
    assert(restored:restoreHandoff(snapshot)); eq(restored.linkPriorFilter,nil)
    assert(restored:setLinkCombined(false)); eq(restored.filter,"MENTAL"); assert(restored:shutdown())
  end
end)

test("reserved LINK stays independent through cold full and partial handoffs with outgoing OFF and saved sounds",function()
  local Sounds=require("chat_sounds")
  local saved={}
  for index,category in ipairs({"MENTAL","DRAGON","PSYCIAN","SECIAN","LINK","LINK VIEW","QUEST","STAFF"}) do
    saved[index]={schema=1,timestamp="2026-10-14T12:00:0"..index.."Z",character="Synthetic Alpha",
      category=category,speaker="Tester",target="Synthetic Alpha",language="Common",message="Saved "..category,
      line="Raw "..category,source=index<=4 and "builtin" or "custom"}
  end
  local raw=copyRetentionValue(saved)
  local sources=allSources({MENTAL=false,DRAGON=false,PSYCIAN=false,SECIAN=false,STAFF=false})
  local sourceBefore=copyRetentionValue(sources)
  local config={volume=27,tabs={MENTAL={enabled=true,sound="contact"},DRAGON={enabled=false,sound="dragon"},
    LINK={enabled=true,sound="room"},["LINK VIEW"]={enabled=false,sound="private"}}}
  local configBefore=copyRetentionValue(config)
  for _,mode in ipairs({"cold","handoff","legacy","partial"}) do
    local f=outgoingAdapter(saved); f.played={}
    function f:playChatSound(id,volume) self.played[#self.played+1]={id=id,volume=volume}; return true end
    local sounds=assert(Sounds.new(f,config)); local soundBefore=copyRetentionValue(sounds.config); local accepted=0
    local controller=makeController(f,nil,function(entry) accepted=accepted+1; sounds:onEntry(entry,sources) end,sources)
    assert(controller:setCaptureOutgoing(false))
    if mode~="cold" then
      assert(controller:restoreHandoff({schema=1,filter=mode=="handoff" and Channels.linkFilter or "LINK VIEW",
        previous_link_filter="DRAGON",entries=mode=="partial" and {saved[5]} or saved,partial=mode=="partial"}))
    end
    assert(controller:setLinkCombined(true)); assert(controller:start())
    eq(controller.filter,mode=="cold" and "ALL" or mode=="handoff" and Channels.linkFilter or "LINK VIEW")
    eq(controller.linkCombined,true); eq(controller.captureOutgoing,false); eq(f.eventAdds,0)
    eq(f.loadRecentCalls,(mode=="cold" or mode=="partial") and 1 or 0)
    eq(f.storageAppends,0); eq(accepted,0); eq(#f.played,0)
    sameEntries(controller.history.items,raw)
    assert(controller:setFilter("ALL")); sameEntries(controller:entries(),{saved[5],saved[6],saved[7]})
    assert(controller:setFilter(Channels.linkFilter)); sameEntries(controller:entries(),{saved[1],saved[2],saved[3],saved[4]})
    assert(controller:capture("LINK","Later personal LINK",{speaker="Synthetic"}))
    assert(controller:capture(" link view ","Later personal LINK VIEW",{speaker="Synthetic"}))
    eq(controller.linkCombined,true); eq(controller.filter,Channels.linkFilter)
    eq(f.storageAppends,2); eq(accepted,2); eq(#f.played,1); eq(f.played[1].id,"room"); eq(f.played[1].volume,27)
    sameEntries(controller:entries(),{saved[1],saved[2],saved[3],saved[4]})
    for index,category in ipairs({"LINK","LINK VIEW"}) do
      assert(controller:setFilter(category)); eq(#controller:entries(),2)
      eq(controller:entries()[1].message,"Saved "..category); eq(controller:entries()[2].category,category)
      eq(f.appendedEntries[index].category,category); eq(f.appendedEntries[index].source,"custom")
    end
    f:outgoing("contact all Must remain ignored"); eq(f.storageAppends,2); eq(f.eventAdds,0)
    assert(controller:setFilter(Channels.linkFilter))
    local snapshot=controller:handoff(); eq(snapshot.filter,Channels.linkFilter); sameEntries(snapshot.entries,controller.history.items)
    local second=outgoingAdapter(); local restored=makeController(second,nil,nil,sources)
    assert(restored:setCaptureOutgoing(false)); assert(restored:restoreHandoff(snapshot)); assert(restored:setLinkCombined(true))
    assert(restored:start(true)); eq(restored.filter,Channels.linkFilter); eq(restored.captureOutgoing,false)
    sameEntries(restored.history.items,snapshot.entries); sameEntries(restored:entries(),{saved[1],saved[2],saved[3],saved[4]})
    eq(second.loadRecentCalls,0); eq(second.storageAppends,0); eq(second.eventAdds,0)
    sameRetentionValue(sources,sourceBefore); sameRetentionValue(config,configBefore); sameRetentionValue(sounds.config,soundBefore)
    sameRetentionValue(saved,raw); eq(f.storageClears,0); eq(f.sideEffects,0)
    assert(restored:shutdown()); assert(controller:shutdown())
  end
end)

test("legacy LINK VIEW virtual handoffs migrate when combined mode applies before or after restore",function()
  for _,applyFirst in ipairs({false,true}) do
    local saved={category="SECIAN",message="Saved Secian",source="builtin"}
    local handoff={schema=1,filter="LINK VIEW",previous_link_filter="SECIAN",entries={saved}}
    local original=copyRetentionValue(handoff)
    local f=fake(); local controller=makeController(f)
    if applyFirst then assert(controller:setLinkCombined(true)) end
    assert(controller:restoreHandoff(handoff))
    eq(controller.filter,applyFirst and Channels.linkFilter or "LINK VIEW")
    assert(controller:setLinkCombined(true)); assert(controller:start(true))
    eq(controller.filter,Channels.linkFilter); eq(controller:entries()[1].message,"Saved Secian")
    eq(controller:handoff().filter,Channels.linkFilter); eq(controller.history.items[1].category,"SECIAN")
    sameRetentionValue(handoff,original); eq(f.storageAppends,0); eq(f.storageClears,0)
    assert(controller:setLinkCombined(false)); eq(controller.filter,"SECIAN"); assert(controller:shutdown())
  end
  local controller=makeController(fake())
  assert(controller:restoreHandoff({schema=1,filter="LINK VIEW",previous_link_filter="DRAGON",entries={}}))
  assert(controller:setLinkCombined(false)); eq(controller.filter,"DRAGON"); assert(controller:shutdown())
end)

test("personal LINK VIEW selection stays literal even when empty or captured after legacy restore",function()
  for _,capture in ipairs({false,true}) do
    local controller=makeController(fake())
    assert(controller:restoreHandoff({schema=1,filter="LINK VIEW",entries={}})); assert(controller:start(true))
    if capture then assert(controller:capture("LINK VIEW","New personal history")) end
    assert(controller:setFilter("LINK VIEW")); assert(controller:setLinkCombined(true))
    eq(controller.filter,"LINK VIEW"); eq(controller.linkCombined,true); eq(#controller:entries(),capture and 1 or 0)
    assert(controller:setLinkCombined(false)); eq(controller.filter,"LINK VIEW"); assert(controller:shutdown())
  end
end)

test("reserved LINK is accepted only as a filter and never as a custom message category",function()
  local f=fake(); local controller=makeController(f); assert(controller:start()); assert(controller:setLinkCombined(true))
  for _,category in ipairs({Channels.linkFilter," @link ","@OTHER"}) do
    eq(Parser.custom(category,"Rejected fixture"),nil)
    eq(controller:capture(category,"Rejected fixture"),nil)
  end
  eq(#controller.history.items,0); eq(f.storageAppends,0)
  assert(controller:setFilter(" @link ")); eq(controller.filter,Channels.linkFilter)
  eq(controller:setFilter("@OTHER"),nil)
  -- Even a malformed old record cannot make the reserved filter a raw category.
  local history=History.new(1000,3)
  assert(history:hydrate({{category="@LINK",message="Malformed raw token"},
    {category="LINK VIEW",message="Personal fixture"},{category="DRAGON",message="Dragon fixture"}}))
  eq(#history:entries(Channels.linkFilter,nil,false),0)
  local combined=history:entries(Channels.linkFilter,nil,true)
  eq(#combined,1); eq(combined[1].category,"DRAGON")
  eq(history:entries("LINK VIEW",nil,true)[1].message,"Personal fixture")
  eq(history.items[1].category,"@LINK"); assert(controller:shutdown())
end)

for _,mode in ipairs({"cold","full","legacy","partial"}) do
  test(mode.." restore partitions direct PRIVATE and broadcast LINK with default v104 mode and custom names intact",function()
    local saved={
      {category="ESP",line='Lark (ESP): "Synthetic global."'},
      {category="CONTACT",speaker="Metadata differs",message="Different saved body.",
        line='Nera O\'Vale thinks to you, "Synthetic direct."'},
      {category="ESP",line='You pick up Lark\'s Psycian link, "Synthetic racial." [r-1]'},
      {category="CONTACT",line='You pick up Lark\'s thoughts, "Synthetic global thoughts." [r-1]'},
      {category="MENTAL",source="outgoing",target="Nera_O'Vale",message="Synthetic direct request."},
      {category="MENTAL",source="outgoing",target="all",message="Synthetic global request."},
      {category="MENTAL",source="outgoing",target="room",message="Synthetic room request."},
      {category="WHISPER",message="Synthetic whisper."},
      {category="LINK",source="custom",message="Synthetic personal LINK."},
      {category="LINK VIEW",source="custom",message="Synthetic personal LINK VIEW."},
      {category="MENTAL",target="Nera",message="Synthetic unproven target."},
    }
    for index,entry in ipairs(saved) do
      entry.schema=1; entry.timestamp="2026-10-15T12:00:00Z"; entry.character="Synthetic Keeper"
      entry.message=entry.message or ("Synthetic saved "..index); entry.source=entry.source or "builtin"
    end
    local raw=copyRetentionValue(saved)
    local sources=allSources({WHISPER=false,MENTAL=false,DRAGON=false,PSYCIAN=false,SECIAN=false})
    local sourcesBefore=copyRetentionValue(sources); local f=outgoingAdapter(saved); local alerts=0
    local controller=makeController(f,nil,function() alerts=alerts+1 end,sources)
    local handoff
    if mode~="cold" then
      handoff={schema=1,filter=mode=="legacy" and "CONTACT" or "PRIVATE",entries=saved}
      if mode=="partial" then
        handoff.partial=true; handoff.entries={Channels.project(saved[2]),saved[9]}
      end
      assert(controller:restoreHandoff(handoff))
    end
    local defaults=require("defaults").chat
    eq(defaults.combine_links,true)
    assert(controller:setLinkCombined(defaults.combine_links)); assert(controller:start(true))
    eq(controller.linkCombined,true)
    eq(controller.filter,mode=="cold" and "ALL" or mode=="legacy" and Channels.linkFilter or "PRIVATE")
    eq(f.loadRecentCalls,(mode=="cold" or mode=="partial") and 1 or 0)
    eq(f.storageAppends,0); eq(f.storageClears,0); eq(alerts,0)
    sameEntries(controller.history.items,raw)
    assert(controller:setFilter("PRIVATE")); sameViewEntries(controller:entries(),{saved[2],saved[5],saved[8]})
    local link={saved[1],saved[3],saved[4],saved[6],saved[7],saved[11]}
    assert(controller:setFilter(Channels.linkFilter)); sameViewEntries(controller:entries(),link)
    assert(controller:setFilter("ALL")); sameEntries(controller:entries(),{saved[9],saved[10]})
    assert(controller:setAllSources(allSources({COMBAT=true}))); sameViewEntries(controller:entries(),saved)
    assert(controller:setLinkCombined(false)); assert(controller:setFilter("MENTAL"))
    sameViewEntries(controller:entries(),{saved[1],saved[2],saved[4],saved[5],saved[6],saved[7],saved[11]})
    assert(controller:setLinkCombined(true)); eq(controller.filter,Channels.linkFilter)
    sameViewEntries(controller:entries(),link)
    for _,index in ipairs({9,10}) do
      assert(controller:setFilter(saved[index].category)); sameEntries(controller:entries(),{saved[index]})
    end
    local snapshot=controller:handoff(); sameEntries(snapshot.entries,raw)
    sameRetentionValue(saved,raw); sameRetentionValue(sources,sourcesBefore)
    eq(f.storageAppends,0); eq(f.storageClears,0); eq(alerts,0); eq(f.sideEffects,0)
    assert(controller:shutdown())
  end)
end

test("live direct thoughts whispers and repeated named requests enter PRIVATE without duplicating broadcast LINK",function()
  local f=outgoingAdapter(); f.character="Synthetic Keeper"; local alerts=0
  local controller=makeController(f,nil,function() alerts=alerts+1 end,hiddenSources())
  assert(controller:setLinkCombined(require("defaults").chat.combine_links)); assert(controller:start())
  f:line('Nera thinks to you, "Synthetic direct."')
  f:outgoing("contact all Synthetic global")
  f:outgoing("contact room Synthetic room")
  f:outgoing("contact Nera Synthetic repeated direct")
  f:outgoing("contact Nera Synthetic repeated direct")
  f:line('Lark whispers to you, "Synthetic whisper."')
  assert(controller:capture("MENTAL","Synthetic unknown.",{target="Nera"}))
  local raw=copyRetentionValue(f.appendedEntries)
  eq(#raw,7); eq(#controller:entries(),0); eq(f.storageAppends,7); eq(alerts,3)
  assert(raw[4].outgoing_id~=raw[5].outgoing_id)
  assert(controller:setFilter("PRIVATE")); sameEntries(controller:entries(),{raw[1],raw[4],raw[5],raw[6]})
  assert(controller:setFilter(Channels.linkFilter)); sameEntries(controller:entries(),{raw[2],raw[3],raw[7]})
  assert(controller:setFilter("ALL")); assert(controller:setAllSources(allSources()))
  sameEntries(controller:entries(),raw); sameEntries(controller.history.items,raw)
  local snapshot=controller:handoff(); sameEntries(snapshot.entries,raw); assert(controller:shutdown())
  for _,mode in ipairs({"reload","handoff"}) do
    local second=outgoingAdapter(raw); local restoredAlerts=0
    local restored=makeController(second,nil,function() restoredAlerts=restoredAlerts+1 end,hiddenSources())
    if mode=="handoff" then assert(restored:restoreHandoff(snapshot)) end
    assert(restored:setLinkCombined(true)); assert(restored:start(true))
    assert(restored:setFilter("PRIVATE")); sameEntries(restored:entries(),{raw[1],raw[4],raw[5],raw[6]})
    assert(restored:setFilter(Channels.linkFilter)); sameEntries(restored:entries(),{raw[2],raw[3],raw[7]})
    sameEntries(restored:handoff().entries,raw); sameEntries(restored.history.items,raw)
    eq(restored.history.items[4].outgoing_id,raw[4].outgoing_id)
    eq(restored.history.items[5].outgoing_id,raw[5].outgoing_id)
    eq(second.storageAppends,0); eq(second.storageClears,0); eq(restoredAlerts,0); eq(second.sideEffects,0)
    assert(restored:shutdown())
  end
  eq(f.sideEffects,0)
end)

local contactCollisionLines={
  direct='Lark thinks to you, "hello"',
  global='You pick up Lark\'s thoughts, "hello" [r-1]',
  room='You pick up Lark\'s thoughts echoing through the area, "hello"',
}
local contactCollisionPairs={{"direct","global"},{"global","direct"},{"direct","room"},{"room","direct"}}

local function assertContactCollisionViews(controller,first,second,firstFrame)
  local direct=firstFrame=="direct" and first or second
  local broadcast=firstFrame=="direct" and second or first
  assert(controller:setFilter("ALL")); eq(#controller:entries(),0)
  assert(controller:setFilter("PRIVATE")); sameViewEntries(controller:entries(),{direct})
  assert(controller:setFilter(Channels.linkFilter)); sameViewEntries(controller:entries(),{broadcast})
  sameViewEntries(controller.history:entries("MENTAL"),{first,second})
  sameEntries(controller:handoff().entries,{first,second})
end

for _,pair in ipairs(contactCollisionPairs) do
  test("owned trigger keeps same-text "..pair[1].." then "..pair[2].." contact frames and dedupes repeats",function()
    local f=fake(); local accepted={}
    local controller=makeController(f,nil,function(entry) accepted[#accepted+1]=entry end,{MENTAL=false})
    assert(controller:setLinkCombined(true)); assert(controller:start())
    f:line(contactCollisionLines[pair[1]]); f:line(contactCollisionLines[pair[1]])
    eq(f.storageAppends,1); eq(#accepted,1); eq(controller.history.lastEpoch,100)
    f.epochValue=101; f:line(contactCollisionLines[pair[2]]); f:line(contactCollisionLines[pair[2]])
    eq(f.storageAppends,2); eq(#accepted,2); eq(controller.history.lastEpoch,101)
    eq(controller.history.lastKey,table.concat({"mental","lark","","hello",0},"\0"))
    eq(controller.history.lastMentalKind,"contact"); eq(#controller.history.items,2)
    for index,entry in ipairs(accepted) do
      sameRetentionValue(entry,Parser.parse(contactCollisionLines[pair[index]],f.character,f.timestampValue))
    end
    sameEntries(f.appendedEntries,accepted)
    assertContactCollisionViews(controller,accepted[1],accepted[2],pair[1])
    local snapshot=controller:handoff()
    eq(snapshot.schema,1); eq(snapshot.last_key,controller.history.lastKey)
    local fields={schema=true,character_key=true,filter=true,previous_link_filter=true,entries=true,
      last_key=true,last_epoch=true,last_mental_kind=true}
    for field in pairs(snapshot) do assert(fields[field],"unexpected handoff field "..field) end
    eq(f.storageClears,0); assert(controller:shutdown())
  end)
end

for _,mode in ipairs({"full","legacy","partial"}) do
  for _,pair in ipairs(contactCollisionPairs) do
    test(mode.." handoff preserves same-text "..pair[1].." versus "..pair[2].." audience dedupe",function()
      local first=fake(); local original=makeController(first,nil,nil,{MENTAL=false})
      assert(original:start()); first:line(contactCollisionLines[pair[1]])
      local handoff=original:handoff(); assert(original:shutdown())
      local raw=copyRetentionValue(handoff.entries[1])
      if mode~="full" then
        raw.category="CONTACT"
        handoff.last_key=table.concat({"contact","lark","","hello",0},"\0")
        handoff.last_mental_kind=nil
        handoff.entries={mode=="partial" and Channels.project(raw) or raw}
      end
      if mode=="partial" then handoff.partial=true end
      local handoffBefore=copyRetentionValue(handoff); local rawBefore=copyRetentionValue(raw)
      local f=fake({raw}); f.epochValue=100.5; local accepted={}
      local restored=makeController(f,nil,function(entry) accepted[#accepted+1]=entry end,{MENTAL=false})
      assert(restored:restoreHandoff(handoff)); assert(restored:setLinkCombined(true)); assert(restored:start(true))
      eq(f.loadRecentCalls,mode=="partial" and 1 or 0)
      eq(f.storageAppends,0); eq(#accepted,0); eq(#restored.history.items,1)
      eq(restored.history.lastKey,table.concat({"mental","lark","","hello",0},"\0"))
      eq(restored.history.lastEpoch,100); eq(restored.history.lastMentalKind,"contact")
      sameRetentionValue(restored.history.items[1],rawBefore)
      f:line(contactCollisionLines[pair[1]])
      eq(f.storageAppends,0); eq(#accepted,0); eq(restored.history.lastEpoch,100)
      f.epochValue=101; f:line(contactCollisionLines[pair[2]])
      eq(f.storageAppends,1); eq(#accepted,1); eq(#restored.history.items,2)
      f.epochValue=102; f:line(contactCollisionLines[pair[2]])
      eq(f.storageAppends,1); eq(#accepted,1); eq(restored.history.lastEpoch,101)
      sameRetentionValue(accepted[1],Parser.parse(contactCollisionLines[pair[2]],f.character,f.timestampValue))
      assertContactCollisionViews(restored,rawBefore,accepted[1],pair[1])
      sameRetentionValue(restored.history.items[1],rawBefore)
      sameRetentionValue(raw,rawBefore); sameRetentionValue(handoff,handoffBefore)
      eq(f.storageClears,0); assert(restored:shutdown())
    end)
  end
end

test("unknown GMCP-style originals never gain audience proof through full legacy or partial handoff",function()
  for _,mode in ipairs({"full","legacy","partial"}) do
    for _,frame in ipairs({"direct","global","room"}) do
      local first=fake(); local original=makeController(first,nil,nil,{MENTAL=false})
      assert(original:start()); assert(original:capture("MENTAL","hello",{speaker="Lark"}))
      local unknown=copyRetentionValue(first.appendedEntries[1])
      first.epochValue=100.5; first:line(contactCollisionLines[frame])
      eq(first.storageAppends,1); eq(original.history.lastMentalKind,"contact")
      local handoff=original:handoff(); assert(original:shutdown())
      if mode~="full" then
        unknown.category="CONTACT"; handoff.last_mental_kind=nil
        handoff.last_key=table.concat({"contact","lark","","hello",0},"\0")
        handoff.entries={mode=="partial" and Channels.project(unknown) or unknown}
      end
      if mode=="partial" then handoff.partial=true end
      local rawBefore=copyRetentionValue(unknown); local handoffBefore=copyRetentionValue(handoff)
      local f=fake({unknown}); f.epochValue=101; local alerts=0
      local restored=makeController(f,nil,function() alerts=alerts+1 end,{MENTAL=false})
      assert(restored:restoreHandoff(handoff)); assert(restored:setLinkCombined(true)); assert(restored:start(true))
      f:line(contactCollisionLines[frame])
      f.epochValue=102; f:line(contactCollisionLines[frame=="direct" and "global" or "direct"])
      eq(f.storageAppends,0); eq(alerts,0); eq(#restored.history.items,1)
      eq(restored.history.lastEpoch,100); eq(restored.history.lastMentalKind,"contact")
      sameRetentionValue(restored.history.items[1],rawBefore)
      assert(restored:setFilter("PRIVATE")); eq(#restored:entries(),0)
      assert(restored:setFilter(Channels.linkFilter)); sameViewEntries(restored:entries(),{rawBefore})
      sameRetentionValue(handoff,handoffBefore); sameRetentionValue(unknown,rawBefore)
      eq(f.loadRecentCalls,mode=="partial" and 1 or 0); eq(f.storageClears,0)
      assert(restored:shutdown())
    end
  end
end)
