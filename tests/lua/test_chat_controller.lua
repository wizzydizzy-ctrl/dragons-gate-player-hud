local Controller=require("chat_controller")
local Parser=require("chat_parser")
local History=require("chat_history")

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
  {category="ESP",source="ESP",line='Tekk (ESP): "First ESP message."',nextLine='Tekk (ESP): "Second ESP message."',combined="PRIVATE"},
  {category="DRAGON",source="DRAGON",line='You pick up Losmir\'s mental link, "First dragon message."',nextLine='You pick up Losmir\'s mental link, "Second dragon message."',combined="PRIVATE"},
  {category="SECIAN",source="SECIAN",line='You pick up Shayla\'s Secian link, "First Secian message." [r-1]',nextLine='You pick up Shayla\'s Secian link, "Second Secian message." [r-1]',combined="PRIVATE"},
  {category="CONTACT",source="CONTACT",line='Seaux thinks to you, "First contact message."',nextLine='Seaux thinks to you, "Second contact message."',combined="PRIVATE"},
  {category="STAFF",source="STAFF",line="[GUIDE] Aerin: First staff message.",nextLine="[GM] Aerin: Second staff message."},
}

local function allSources(overrides)
  local sources={}
  for category,enabled in pairs(require("defaults").chat.all_sources) do sources[category]=enabled end
  for category,enabled in pairs(overrides or {}) do sources[category]=enabled end
  return sources
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

local playerStatNames={"strength","intelligence","wisdom","dexterity","agility","constitution","charisma","will","voice","perception","appearance","presence","luck"}

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
    if case.combined then assert(controller:setFilter(case.combined)); sameEntries(controller:entries(),accepted) end
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
    sameEntries(controller.history:entries("ALL"),accepted); sameEntries(f.appendedEntries,accepted)
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
  sameEntries(controller.history:entries("ALL"),accepted); sameEntries(f.appendedEntries,accepted)
  eq(f.storageAppends,#lines); eq(f.storageClears,0); eq(controller.trigger,trigger)
  assert(controller:shutdown())
end)

test("profile reload hydrates hidden sources and continues capturing them",function()
  local first=fake(); local original=makeController(first,nil,nil,hiddenSources())
  assert(original:start())
  for _,case in ipairs(sourceCases) do first:line(case.line) end
  eq(#original:entries(),0); eq(first.storageAppends,#sourceCases)
  local stored=first.appendedEntries; eq(#stored,#sourceCases)
  sameEntries(original.history:entries("ALL"),stored); assert(original:shutdown())

  local second=fake(stored); local accepted={}
  local restored=makeController(second,nil,function(entry) accepted[#accepted+1]=entry end,hiddenSources())
  assert(restored:start()); eq(#restored:entries(),0); eq(second.loadRecentCalls,1)
  eq(second.storageAppends,0); eq(#accepted,0)
  sameEntries(restored.history:entries("ALL"),stored)
  for index,case in ipairs(sourceCases) do
    local expected=case.category=="ROOM" and {stored[2],stored[3]} or {stored[index]}
    assert(restored:setFilter(case.category)); sameEntries(restored:entries(),expected)
  end
  assert(restored:setFilter("ALL")); second.character="Gia"; assert(restored:syncCharacter())
  eq(#restored:entries(),0); sameEntries(restored.history:entries("ALL"),stored); eq(second.loadRecentCalls,1)
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
  sameEntries(restored.history:entries("ALL"),stored)
  for index,case in ipairs(sourceCases) do
    local expected=case.category=="ROOM" and {stored[2],stored[3]} or {stored[index]}
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
  sameEntries(restored:entries(),{stored[2]}); sameEntries(restored.history:entries("ALL"),stored)
  eq(table.concat(restored.history:categories(),","),"COMBAT,ROOM")
  eq(restored.history.lastKey,handoff.last_key); eq(restored.history.lastEpoch,handoff.last_epoch)
  second:line(sourceCases[2].line)
  eq(second.storageAppends,0); eq(#accepted,0); sameEntries(restored.history:entries("ALL"),stored)
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
  end,{ESP=false})
  assert(controller:start()); f:line('Tekk (ESP): "hello"')
  eq(#accepted,1); eq(accepted[1].category,"ESP"); eq(#controller:entries(),0)
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
  eq(controller:entries()[1].category,"ESP"); eq(f.storageAppends,1); eq(f:count(f.triggers),1)
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
  eq(#entries,1); eq(entries[1].category,"CONTACT"); eq(entries[1].speaker,"Seaux"); eq(entries[1].message,"Hello")
  eq(f.storageAppends,1); assert(controller:setFilter("PRIVATE")); eq(#controller:entries(),1)
end)

test("ranked Psycian links flow through the owned trigger into ESP and private filters",function()
  local f=fake(); local controller=makeController(f); assert(controller:start()); assert(controller:setFilter("ESP"))
  f:line('You pick up Seaux\'s Psycian link, "Hello." [r-1]')
  local entries=controller:entries()
  eq(#entries,1); eq(entries[1].category,"ESP"); eq(entries[1].speaker,"Seaux"); eq(entries[1].message,"Hello.")
  eq(f.storageAppends,1); assert(controller:setFilter("PRIVATE")); eq(#controller:entries(),1)
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

test("Secian links flow through the owned trigger private filter and dedupe",function()
  local f=fake(); local controller=makeController(f); assert(controller:start())
  local line='You pick up Marcelline\'s Secian link, "Hello?" [r-1]'
  f:line(line); f.epochValue=101; f:line(line)
  eq(#controller:entries(),1); eq(controller:entries()[1].category,"SECIAN"); eq(controller:entries()[1].speaker,"Marcelline")
  eq(f.storageAppends,1); assert(controller:setFilter("PRIVATE")); eq(#controller:entries(),1)
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
