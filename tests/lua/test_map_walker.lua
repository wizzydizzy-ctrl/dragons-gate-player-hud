local Walker=require("map_walker")

local function fakeAdapter()
  local adapter={sent={},timers={},canceled={},nextTimer=0}
  function adapter:sendCommand(command,generated)
    self.sent[#self.sent+1]={command=command,generated=generated}
    return true
  end
  function adapter:schedule(delay,callback)
    self.nextTimer=self.nextTimer+1
    local id="walk-timer-"..self.nextTimer
    self.timers[id]={delay=delay,callback=callback}
    return id
  end
  function adapter:cancelTimer(id)
    self.canceled[#self.canceled+1]=id
    self.timers[id]=nil
    return true
  end
  function adapter:fire(id)
    local timer=self.timers[id]
    if timer then self.timers[id]=nil; timer.callback() end
  end
  function adapter:validateStep(_,_,command)
    local aliases={north="n",northeast="ne",east="e",southeast="se",south="s",southwest="sw",west="w",northwest="nw",u="up",d="down"}; local value=tostring(command):lower()
    return true,aliases[value] or value
  end
  return adapter
end

test("walker sends one command and waits for each exact GMCP room",function()
  local adapter=fakeAdapter(); local statuses={}
  local walker=Walker.new(adapter,function(kind,message) statuses[#statuses+1]={kind,message} end)
  assert(walker:start({rooms={176,177,180},commands={"ne","e"}},180))
  eq(adapter.sent[1].command,"ne"); eq(adapter.sent[2],nil); eq(adapter.timers["walk-timer-1"].delay,12)
  walker:onRoom(177); eq(adapter.sent[2].command,"e"); eq(adapter.canceled[1],"walk-timer-1")
  walker:onRoom(180); eq(walker:active(),false); eq(adapter.canceled[2],"walk-timer-2")
  eq(statuses[#statuses][1],"arrived"); eq(statuses[#statuses][2],"Arrived at 180")
end)

test("walker pauses between rooms during roundtime and resumes when ready",function()
  local adapter=fakeAdapter(); local statuses={}
  local walker=Walker.new(adapter,function(kind,message) statuses[#statuses+1]={kind,message} end)
  assert(walker:start({rooms={176,177,180},commands={"ne","e"}},180))
  walker:onRoundtime(4)
  assert(walker:onRoom(177))
  eq(#adapter.sent,1); eq(walker:active(),true); eq(walker.waiting_roundtime,true); eq(walker.timeout,nil)
  eq(statuses[#statuses][1],"paused")
  assert(walker:onRoundtime(2)); eq(#adapter.sent,1)
  assert(walker:onRoundtime(0)); eq(#adapter.sent,2); eq(adapter.sent[2].command,"e")
  eq(walker.waiting_roundtime,nil); eq(adapter.timers[walker.timeout].delay,12)
end)

test("walker clears a roundtime pause safely on stop",function()
  local adapter=fakeAdapter(); local walker=Walker.new(adapter,function() end)
  assert(walker:start({rooms={1,2,3},commands={"n","e"}},3))
  walker:onRoundtime(8); assert(walker:onRoom(2)); eq(walker.waiting_roundtime,true)
  assert(walker:stop("requested")); eq(walker:active(),false); eq(walker.waiting_roundtime,nil)
  assert(walker:onRoundtime(0)); eq(#adapter.sent,1)
end)

test("repeated room refreshes during roundtime cannot complete an unsent step",function()
  local adapter=fakeAdapter(); local statuses={}
  local walker=Walker.new(adapter,function(kind) statuses[#statuses+1]=kind end)
  assert(walker:start({rooms={1,2,3},commands={"n","e"}},3))
  walker:onRoundtime(4); assert(walker:onRoom(2))
  for _=1,3 do
    assert(walker:onRoom(2)); eq(walker:active(),true); eq(walker.index,2)
    eq(walker.origin,2); eq(walker.expected,nil); eq(walker.timeout,nil); eq(#adapter.sent,1)
    eq(statuses[#statuses],"paused")
  end
  eq(#adapter.canceled,1); eq(adapter.nextTimer,1)
  assert(walker:onRoundtime(0)); assert(walker:onRoundtime(0))
  eq(#adapter.sent,2); eq(adapter.sent[2].command,"e"); eq(walker.expected,3); eq(adapter.nextTimer,2)
  local timer=walker.timeout; assert(walker:onRoom(2)); eq(walker.timeout,timer)
  assert(walker:onRoom(3)); eq(walker:active(),false); eq(statuses[#statuses],"arrived"); eq(#adapter.canceled,2)
end)

test("an initially paused route ignores current-room refreshes until its first send",function()
  local adapter=fakeAdapter(); local walker=Walker.new(adapter,function() end)
  walker:onRoundtime(4); assert(walker:start({rooms={1,2},commands={"n"}},2))
  for _=1,3 do
    assert(walker:onRoom(1)); eq(walker:active(),true); eq(walker.index,1)
    eq(walker.origin,1); eq(walker.expected,nil); eq(walker.timeout,nil)
  end
  eq(#adapter.sent,0); eq(adapter.nextTimer,0)
  assert(walker:onRoundtime(0)); eq(#adapter.sent,1); eq(adapter.sent[1].command,"n"); eq(walker.expected,2)
  assert(walker:onRoom(2)); eq(walker:active(),false)
end)

test("paused routes reject other rooms or invalid updates without acknowledging an unsent step",function()
  for _,initialPause in ipairs({true,false}) do
    for _,update in ipairs({{room=3},{room="invalid"},{}}) do
      local adapter=fakeAdapter(); local statuses={}
      local walker=Walker.new(adapter,function(kind) statuses[#statuses+1]=kind end)
      if initialPause then walker:onRoundtime(4) end
      assert(walker:start({rooms={1,2,3},commands={"n","e"}},3))
      if not initialPause then walker:onRoundtime(4); assert(walker:onRoom(2)) end
      local sent=initialPause and 0 or 1
      assert(walker:onRoom(update.room))
      eq(walker:active(),false); eq(#adapter.sent,sent); eq(statuses[#statuses],"stopped")
      assert(walker:onRoundtime(0)); eq(#adapter.sent,sent)
    end
  end
end)

test("walker ignores same-origin room refresh while awaiting destination",function()
  local adapter=fakeAdapter(); local walker=Walker.new(adapter,function() end)
  assert(walker:start({rooms={176,177},commands={"ne"}},177)); local timer=walker.timeout
  assert(walker:onRoom(176)); eq(walker:active(),true); eq(walker.timeout,timer)
  eq(adapter.canceled[1],nil); eq(#adapter.sent,1)
  assert(walker:onRoom(177)); eq(walker:active(),false)
end)

test("walker stops on unexpected room wrong direction timeout and manual movement",function()
  local adapter=fakeAdapter(); local stopped={}
  local walker=Walker.new(adapter,function(kind,message) if kind=="stopped" then stopped[#stopped+1]=message end end)
  walker:start({rooms={1,2},commands={"n"}},2); walker:onRoom(99); eq(walker:active(),false); eq(stopped[#stopped],"Walk stopped: unexpected room 99")
  walker:start({rooms={99,100},commands={"e"}},100); walker:onWrongDirection(); eq(stopped[#stopped],"Walk stopped: wrong direction")
  walker:start({rooms={99,100},commands={"e"}},100); local timer=walker.timeout; adapter:fire(timer); eq(stopped[#stopped],"Walk stopped: movement timed out")
  walker:start({rooms={99,100},commands={"e"}},100); walker:onManualMovement("north"); eq(stopped[#stopped],"Walk stopped: manual movement")
end)

test("generated movement does not cancel itself and shutdown cancels exactly once",function()
  local adapter=fakeAdapter(); local walker=Walker.new(adapter,function() end)
  walker:start({rooms={10,11},commands={"north"}},11)
  walker:onManualMovement("north",true); eq(walker:active(),true)
  walker:shutdown(); eq(walker:active(),false); eq(#adapter.canceled,1)
  walker:shutdown(); eq(#adapter.canceled,1)
end)

test("walker sends a confirmed special command exactly and waits for its exact room",function()
  local adapter=fakeAdapter(); local validated={}
  function adapter:validateStep(from,to,command)
    validated[#validated+1]={from=from,to=to,command=command}
    if from==1 and to==2 and command=="Go Gate" then return true,command end
    if from==2 and to==3 and command=="north" then return true,"n" end
    return nil,"exit is not confirmed"
  end
  local walker=Walker.new(adapter,function() end)
  assert(walker:start({rooms={1,2,3},commands={"Go Gate","north"}},3))
  eq(#validated,2); eq(validated[1].from,1); eq(validated[1].to,2); eq(validated[1].command,"Go Gate")
  eq(adapter.sent[1].command,"Go Gate"); eq(adapter.sent[2],nil)
  assert(walker:onRoom(2)); eq(adapter.sent[2].command,"n")
end)

test("walker validates every special edge before activation",function()
  local adapter=fakeAdapter(); local validated={}
  function adapter:validateStep(from,to,command)
    validated[#validated+1]={from=from,to=to,command=command}
    if from==1 and to==2 and command=="go gate" then return true end
    return nil,"special exit is not confirmed from "..from.." to "..to
  end
  local walker=Walker.new(adapter,function() end)
  local ok,err=walker:start({rooms={1,2,3},commands={"go gate","pull lever"}},3)
  eq(ok,nil); eq(err,"special exit is not confirmed from 2 to 3")
  eq(#validated,2); eq(#adapter.sent,0); eq(walker:active(),false)
end)

test("walker validates every directional edge before sending anything",function()
  local adapter=fakeAdapter(); local checked={}; function adapter:validateStep(from,to,command) checked[#checked+1]={from,to,command}; if from==1 and to==2 then return true,"n" end; return nil,"standard exit is not persisted from "..from.." to "..to end
  local walker=Walker.new(adapter,function() end); local ok,err=walker:start({rooms={1,2,3},commands={"north","east"}},3)
  eq(ok,nil); eq(err,"standard exit is not persisted from 2 to 3"); eq(#checked,2); eq(#adapter.sent,0)
end)

test("walker rejects unconfirmed special route commands and contains validator exceptions",function()
  local adapter=fakeAdapter(); function adapter:validateStep() return nil,"special exit is not confirmed" end
  local ok,err=Walker.new(adapter,function() end):start({rooms={1,2},commands={"pull lever"}},2)
  eq(ok,nil); eq(err,"special exit is not confirmed")
  function adapter:validateStep() error("validation exploded") end
  ok,err=Walker.new(adapter,function() end):start({rooms={1,2},commands={"pull lever"}},2)
  eq(ok,nil); eq(tostring(err):find("validation exploded",1,true)~=nil,true)
end)

test("walker rejects malformed routes",function()
  local walker=Walker.new(fakeAdapter(),function() end)
  local ok,err=walker:start({rooms={1},commands={"n"}},2); eq(ok,nil); eq(err,"route rooms and commands do not match")
  ok,err=walker:start({rooms={1,2},commands={"n"}},3); eq(ok,nil); eq(err,"route destination does not match 3")
  ok,err=walker:start({rooms={1,2.5},commands={"n"}},2.5); eq(ok,nil); eq(err,"invalid route room 2.5")
end)

test("walker stops safely when its one-shot timer cannot be created",function()
  local adapter=fakeAdapter(); function adapter:schedule() return nil end
  local walker=Walker.new(adapter,function() end); local ok,err=walker:start({rooms={1,2},commands={"n"}},2)
  eq(ok,nil); eq(err,"movement timer could not be created"); eq(walker:active(),false)
end)

test("walker propagates movement send failures without leaving active state",function()
  local adapter=fakeAdapter(); function adapter:sendCommand() return nil,"send failed" end
  local walker=Walker.new(adapter,function() end); local ok,err=walker:start({rooms={1,2},commands={"n"}},2)
  eq(ok,nil); eq(err,"send failed"); eq(walker:active(),false)
end)

test("walker contains adapter exceptions and clears all state",function()
  for _,boundary in ipairs({"send","schedule","cancel"}) do
    local adapter=fakeAdapter()
    if boundary=="send" then function adapter:sendCommand() error("send exploded") end end
    if boundary=="schedule" then function adapter:schedule() error("schedule exploded") end end
    if boundary=="cancel" then function adapter:cancelTimer() error("cancel exploded") end end
    local statuses={}; local walker=Walker.new(adapter,function(kind,message) statuses[#statuses+1]={kind,message} end)
    local ok,err=walker:start({rooms={1,2},commands={"n"}},2)
    if boundary=="cancel" then ok,err=walker:stop("requested") end
    eq(ok,nil); eq(tostring(err):find("exploded",1,true)~=nil,true)
    eq(walker:active(),false); eq(walker.timeout,nil); eq(walker.expected,nil); eq(walker.origin,nil)
    eq(#statuses,2)
  end
end)

test("walker stops once when transition timer cancellation throws",function()
  local adapter=fakeAdapter(); local staleCallback
  function adapter:cancelTimer(id)
    staleCallback=self.timers[id].callback
    error("cancel exploded during transition")
  end
  adapter.generated=true
  function adapter:clearGenerated() self.generated=false end
  local statuses={}; local walker=Walker.new(adapter,function(kind,message) statuses[#statuses+1]={kind,message} end)
  assert(walker:start({rooms={1,2,3},commands={"n","e"}},3))
  local ok,err=walker:onRoom(2)
  eq(ok,nil); eq(tostring(err):find("cancel exploded during transition",1,true)~=nil,true)
  eq(walker:active(),false); eq(walker.timeout,nil); eq(walker.expected,nil); eq(walker.origin,nil)
  eq(adapter.generated,false); eq(#adapter.sent,1)
  eq(#statuses,2); eq(statuses[2][1],"stopped")
  staleCallback()
  eq(walker:active(),false); eq(#adapter.sent,1); eq(#statuses,2)
end)
