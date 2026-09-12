local Controller=require("chat_controller")
local Parser=require("chat_parser")
local History=require("chat_history")

local function fake(entries)
  local f={next=0,triggers={},storageAppends=0,storageEntries=entries or {},storedCharacters={},errors=0,epochValue=100,timestampValue="2026-08-31T13:00:00-04:00",character="Dace Alterac",loadRecentCalls=0,loadedCharacterKeys={}}
  function f:addLineTrigger(fn) if self.triggerFailure then error(self.triggerFailure) end; self.next=self.next+1; local id="trigger-"..self.next; self.triggers[id]=fn; return id end
  function f:killTrigger(id) self.triggers[id]=nil end
  function f:line(value) for _,fn in pairs(self.triggers) do fn(value) end end
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
    return true
  end
  return f
end

local function makeController(f,onChange)
  return Controller.new(f,Parser,History.new(1000,3),f.storage,onChange or function() end,function() return f.character end)
end

test("one owned line trigger captures and persists recognized chat",function()
  local f=fake(); local controller=makeController(f); controller:start(); f:line('Tekk (ESP): "hello"')
  eq(controller:entries()[1].category,"ESP"); eq(f.storageAppends,1); eq(f:count(f.triggers),1)
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
