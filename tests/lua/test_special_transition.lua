local MapperModel=require("mapper_model")
local Special=require("special_transition")

local function fakeTimerAdapter()
  local adapter={timers={},nextTimer=0}
  function adapter:schedule(delay,callback)
    self.nextTimer=self.nextTimer+1
    local id="special-timer-"..self.nextTimer
    self.timers[id]={delay=delay,callback=callback}
    return id
  end
  function adapter:cancelTimer(id)
    if self.cancelError then return nil,self.cancelError end
    self.timers[id]=nil
    return true
  end
  function adapter:fireOnlyTimer()
    for id,timer in pairs(self.timers) do
      self.timers[id]=nil
      timer.callback()
      return
    end
  end
  function adapter:timerCount()
    local count=0
    for _ in pairs(self.timers) do count=count+1 end
    return count
  end
  return adapter
end

test("confirms only the final genuine special-travel command",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  eq(tracker:onOutgoing("open gate",100),nil); assert(tracker:onOutgoing("go gate",100))
  eq(tracker:onRoom(100),nil)
  local transition=assert(tracker:onRoom(900))
  eq(transition.from,100); eq(transition.to,900); eq(transition.command,"go gate")
  eq(transition.category,"gate")
  eq(tracker:pending(),nil)
end)
test("classifies each configurable special-travel category",function()
  for _,pair in ipairs({{"go gate","gate"},{"go portal","portal"},{"go door","door"},{"go arch","arch"},{"go path","path"},{"climb rope","other"}}) do local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3); assert(tracker:onOutgoing(pair[1],100)); eq(assert(tracker:onRoom(900)).category,pair[2]) end
end)

test("normalizes command keys while classifying directions and controls safely",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  eq(tracker:onOutgoing("  NoRtH  ",100),nil)
  eq(tracker:onOutgoing("  DGHUD UPDATE  ",100),nil)
  assert(tracker:onOutgoing("  Go   Through   The   PORTAL  ",100))
  local transition=assert(tracker:onRoom(900))
  eq(transition.command,"go through the portal")
end)

test("directions controls and expired candidates never become special exits",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  eq(tracker:onOutgoing("north",100),nil)
  eq(tracker:onOutgoing("dghud update",100),nil)
  assert(tracker:onOutgoing("climb rope",100)); adapter:fireOnlyTimer()
  eq(tracker:onRoom(900),nil)
end)

test("normal commands never arm a special transition",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  local controls={"dghud","walkto","walkstop","mapcenter","inventory","inv","stat","info","look","l","who","say","whisper","link","attack","kill","get","drop","read","cast","open","close","lock","unlock","wear","remove"}
  for _,command in ipairs(controls) do
    eq(tracker:onOutgoing(command,100),nil)
    eq(tracker:onOutgoing(command.." example",100),nil)
  end
  eq(tracker:pending(),nil); eq(adapter:timerCount(),0)
end)

test("accepts conservative traversal verbs and the four special go nouns",function()
  local accepted={"go gate","go the door","go through portal","go crumbling iron arch","go path","enter tunnel","leave","climb rope","crawl passage","cross bridge","board ferry","disembark"}
  for _,command in ipairs(accepted) do
    local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,12)
    assert(tracker:onOutgoing(command,100),command)
    eq(adapter.timers[tracker.timer].delay,12)
  end
end)

test("supports explicit extra travel patterns without broadening defaults",function()
  local adapter=fakeTimerAdapter()
  local tracker=Special.new(MapperModel,adapter,12,nil,{"^squeeze%s+through ",function(value) return value=="use ferry" end})
  assert(tracker:onOutgoing("  SQUEEZE through crack ",100)); assert(tracker:cancel())
  assert(tracker:onOutgoing("use ferry",100)); assert(tracker:cancel())
  eq(tracker:onOutgoing("use potion",100),nil)
end)

test("a slow arrival confirms while pending but a stale arrival cannot",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,12)
  assert(tracker:onOutgoing("go gate",100))
  local transition=assert(tracker:onRoom(900))
  eq(transition.command,"go gate"); eq(adapter:timerCount(),0)

  assert(tracker:onOutgoing("enter tunnel",900)); adapter:fireOnlyTimer()
  eq(tracker:onRoom(901),nil); eq(tracker:pending(),nil)
end)

test("known failed traversal output cancels before unrelated movement",function()
  for _,line in ipairs({"You cannot move in that direction.","You cannot go that way.","You can't go that way.","I don't see what you are referring to.","There is no gate here."}) do
    local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,12)
    assert(tracker:onOutgoing("go gate",100)); assert(tracker:onLine(line)); eq(tracker:pending(),nil); eq(tracker:onRoom(900),nil)
  end
end)

test("replacement disconnect and cancellation failures clear candidate ownership",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  assert(tracker:onOutgoing("enter tunnel",100)); assert(tracker:cancel("disconnect"))
  eq(tracker:pending(),nil); eq(adapter:timerCount(),0)
  adapter.cancelError="cancel exploded"; assert(tracker:onOutgoing("climb rope",100))
  local ok,err=tracker:cancel("shutdown"); eq(ok,nil); assert(err:find("cancel exploded",1,true))
  eq(tracker:pending(),nil)

  adapter=fakeTimerAdapter(); tracker=Special.new(MapperModel,adapter,3)
  assert(tracker:onOutgoing("enter tunnel",100))
  function adapter:cancelTimer() error("cancel threw") end
  ok,err=tracker:cancel("shutdown"); eq(ok,nil); assert(err:find("cancel threw",1,true))
  eq(tracker:pending(),nil)
end)

test("replacement cancellation failure is bounded aborts replacement and leaves stale callback inert",function()
  local adapter=fakeTimerAdapter(); local statuses={}
  local tracker=Special.new(MapperModel,adapter,3,function(kind) statuses[#statuses+1]=kind end)
  assert(tracker:onOutgoing("enter tunnel",100))
  local oldTimer=tracker.timer; local staleCallback=adapter.timers[oldTimer].callback
  adapter.cancelError="cancel rejected "..string.rep("x",500)
  local ok,err=tracker:onOutgoing("Go New Door",100)
  eq(ok,nil); eq(err:find("special transition replacement cancellation failed",1,true),1); eq(#err<=200,true)
  eq(tracker:pending(),nil); eq(tracker.timer,nil); eq(adapter.nextTimer,1)

  adapter.cancelError=nil
  assert(tracker:onOutgoing("Go Final Door",100))
  local replacementTimer=tracker.timer
  staleCallback()
  eq(tracker:pending().command,"go final door"); eq(tracker.timer,replacementTimer)
  eq(statuses[#statuses],nil)
end)

test("timer creation failures never leave pending candidates",function()
  local adapter=fakeTimerAdapter(); function adapter:schedule() return nil,"schedule failed" end
  local tracker=Special.new(MapperModel,adapter,3)
  local ok,err=tracker:onOutgoing("climb rope",100)
  eq(ok,nil); eq(err,"schedule failed"); eq(tracker:pending(),nil)

  function adapter:schedule() error("schedule exploded") end
  ok,err=tracker:onOutgoing("enter tunnel",100)
  eq(ok,nil); assert(err:find("schedule exploded",1,true)); eq(tracker:pending(),nil)
end)

test("shutdown cancels the owned timer",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  assert(tracker:onOutgoing("climb rope",100)); assert(tracker:shutdown())
  eq(tracker:pending(),nil); eq(adapter:timerCount(),0)
end)

test("reports lifecycle status only when a candidate changes",function()
  local adapter=fakeTimerAdapter(); local statuses={}
  local tracker=Special.new(MapperModel,adapter,3,function(kind) statuses[#statuses+1]=kind end)
  eq(tracker:onOutgoing("north",100),nil); eq(tracker:onOutgoing("dghud update",100),nil)
  eq(#statuses,0)
  eq(tracker:onOutgoing("open gate",100),nil); assert(tracker:onOutgoing("go gate",100))
  eq(#statuses,0)
  assert(tracker:onOutgoing("enter tunnel",100)); eq(#statuses,1); eq(statuses[1],"replaced")
  adapter:fireOnlyTimer(); eq(#statuses,2); eq(statuses[2],"expired")
end)
