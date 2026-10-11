-- May be dofile'd by tests/run.lua or run directly with Lua 5.1.
local standalone=type(test)~="function"
local test,eq=test,eq
local total,failed=0,0
if standalone then
  local root=arg[0]:match("^(.*)/tests/lua/test_quick_actions%.lua$") or "."
  package.path=root.."/src/?.lua;"..package.path
  function test(name,fn)
    total=total+1
    local ok,err=pcall(fn)
    if ok then print("ok "..total.." - "..name)
    else failed=failed+1; print("not ok "..total.." - "..name.."\n  "..tostring(err)) end
  end
  function eq(actual,expected)
    if actual~=expected then error("expected "..tostring(expected)..", got "..tostring(actual),2) end
  end
end
local QuickActions=require("quick_actions")
local Parser=require("command_parser")
local function fixture()
  local f={now=0,nextTimer=0,timers={},history={},sent={},canceled={},notices={},
    enabled={shoprenew=true,shoprenewall=true,trainall=true}}
  function f:schedule(delay,callback)
    self.nextTimer=self.nextTimer+1
    local id=self.nextTimer
    local timer={at=self.now+delay,delay=delay,callback=callback}
    self.timers[id]=timer; self.history[id]=timer
    return id
  end
  function f:cancelTimer(id) self.canceled[#self.canceled+1]=id; self.timers[id]=nil; return true end
  function f:sendCommand(command)
    self.sent[#self.sent+1]={command=command,at=self.now,marked=self.q.sending}
    self.q:onOutgoing(command)
    if self.onSend then self.onSend(command) end
    return true
  end
  function f:advance(seconds)
    local target=self.now+seconds
    while true do
      local id,earliest
      for candidate,timer in pairs(self.timers) do
        if timer.at<=target and (not earliest or timer.at<earliest
            or timer.at==earliest and candidate<id) then id=candidate; earliest=timer.at end
      end
      if not id then break end
      local timer=self.timers[id]; self.timers[id]=nil; self.now=earliest; timer.callback()
    end
    self.now=target
  end
  function f:actions()
    local result={}
    for _,entry in ipairs(self.sent) do
      if entry.command:match("^shop renew ") or entry.command:match("^train raise ") then
        result[#result+1]=entry.command
      end
    end
    return table.concat(result,",")
  end
  function f:pending() local n=0; for _ in pairs(self.timers) do n=n+1 end; return n end
  local c={requests={},callbacks={},snapshot={
    runes={items={{name="Cached",remaining=0}}},skills={items={{name="Brawling",remain=0,level=1}}}}}
  function c:request(command,done)
    self.requests[#self.requests+1]=command; self.callbacks[#self.callbacks+1]=done
    local sent,err=f:sendCommand(command=="info mag" and self.canonicalize and "info magic" or command)
    if sent==false or err~=nil then return nil,err or "request send failed" end
    return true
  end
  function c:reply(result,err,index) self.callbacks[index or #self.callbacks](result,err) end
  local q=QuickActions.new(f,c,{
    enabled=function(name) return f.enabled[name] end,
    notify=function(message) f.notices[#f.notices+1]=message end})
  f.q=q
  return q,f,c
end
local function runes(...)
  local items={}
  for _,row in ipairs({...}) do items[#items+1]={name=row[1],remaining=row[2]} end
  return {items=items}
end
local function skills(...)
  local items={}
  for _,row in ipairs({...}) do items[#items+1]={name=row[1],remain=row[2],level=row[3]} end
  return {items=items}
end
local function rejected(name,result,err)
  local q,f,c=fixture()
  assert(q:start(name)); c:reply(result,err)
  eq(q:busy(),false); eq(f:pending(),0); f:advance(10); eq(f:actions(),""); eq(#f.sent,1)
end

test("quick actions request exact info mag and wait for fresh callback, ignoring cache",function()
  local q,f,c=fixture()
  assert(q:start("shoprenew")); eq(q:busy(),true); eq(c.requests[1],"info mag")
  eq(f.sent[1].command,"info mag"); eq(f.sent[1].marked,true); eq(q.sending,false)
  f:advance(10); eq(#f.sent,1); eq(f:pending(),0)
  c:reply(runes({"Force",19})); eq(#f.sent,1); eq(f:pending(),1)
  f:advance(1); eq(f:actions(),"shop renew force"); eq(q:busy(),false)
end)
test("quick actions renew 19 and 0 but not 20, sorted with one second cadence",function()
  local q,f,c=fixture()
  assert(q:start("shoprenew"))
  c:reply(runes({"Vigor",20},{"Healing",19},{"Force",0},{"Light Blue",1}))
  eq(f:pending(),1); eq(f.history[1].delay,1)
  f:advance(.99); eq(#f.sent,1); eq(q:busy(),true)
  f:advance(.01); eq(f:actions(),"shop renew force"); eq(f.sent[2].at,1)
  f:advance(.99); eq(#f.sent,2)
  f:advance(.01); eq(f:actions(),"shop renew force,shop renew healing"); eq(f.sent[3].at,2)
  f:advance(1); eq(f:actions(),"shop renew force,shop renew healing,shop renew light blue")
  eq(f.sent[4].at,3); eq(q:busy(),false); eq(f:pending(),0)
  for _,entry in ipairs(f.sent) do eq(entry.marked,true) end
end)
test("quick actions renew all unique runes even at 20 and above",function()
  local q,f,c=fixture()
  assert(q:start("shoprenewall")); eq(c.requests[1],"info mag")
  c:reply(runes({"Vigor",100},{"Force",0},{"Healing",20},{"healing",20}))
  f:advance(3); eq(f:actions(),"shop renew force,shop renew healing,shop renew vigor")
  eq(q:busy(),false)
end)
test("quick actions dedupe case insensitive runes without mutating response",function()
  local q,f,c=fixture()
  local result=runes({"Force",19},{"FORCE",19},{"force",19})
  assert(q:start("shoprenew")); c:reply(result); f:advance(5)
  eq(f:actions(),"shop renew force"); eq(#result.items,3); eq(result.items[1].name,"Force")
end)
test("quick actions train ready skills by authoritative IDs in numeric order",function()
  local q,f,c=fixture()
  assert(q:start("trainall")); eq(c.requests[1],"skill"); eq(f.sent[1].command,"skill")
  c:reply(skills({"Shield Use",0,4},{"Future Skill",0,1},{"Biting",0,2},
    {"Brawling",0,10},{"Dodging",1,2},{"Swimming",0,3}))
  f:advance(4)
  eq(f:actions(),"train raise 1,train raise 7,train raise 23,train raise 46")
  for index=2,#f.sent do eq(f.sent[index].at,index-1) end
  eq(q:busy(),false)
end)
test("quick actions dedupe old and new skill names with their original IDs",function()
  local q,f,c=fixture(); assert(q:start("trainall"))
  c:reply(skills({"Pole Weapons",0,3},{"Piercing Weapons",0,3},{"Poles",0,3},
    {"Throw Weapons",0,4},{"Thrown Weapons",0,4},{"Throws",0,4},
    {"Shield Parry",0,5},{"Shield Use",0,5},{"Shield Use",0,5}))
  f:advance(3); eq(f:actions(),"train raise 4,train raise 5,train raise 7")
end)
test("quick actions skip every unknown skill ID and never use row ordinals",function()
  local q,f,c=fixture(); assert(q:start("trainall"))
  c:reply(skills({"Unknown",0,1},{"Piercing Weapons Training",0,2},
    {"Shield Use; train raise 1",0,1},{"Biting",0,1}))
  f:advance(5); eq(f:actions(),"train raise 46")
end)
test("quick actions accept valid empty and no eligible responses without action timers",function()
  for _,case in ipairs({
    {"shoprenew",runes()},{"shoprenewall",runes()},{"trainall",skills()},
    {"shoprenew",runes({"Force",20})},{"trainall",skills({"Brawling",1,1})},
    {"trainall",skills({"Unknown",0,1})},
  }) do
    local q,f,c=fixture(); assert(q:start(case[1])); c:reply(case[2])
    eq(q:busy(),false); eq(f:pending(),0); eq(#f.sent,1)
  end
end)
test("quick actions reject errors and incomplete parsed response shapes",function()
  for _,name in ipairs({"shoprenew","shoprenewall","trainall"}) do
    rejected(name,nil,"incomplete response"); rejected(name,{items={}},"timeout")
    rejected(name,nil); rejected(name,false); rejected(name,{})
    rejected(name,{items="unparsed"}); rejected(name,{{name="Force",remaining=0}})
    for _,marker in ipairs({{complete=false},{confirmed=false},{cached=true},{incomplete=true}}) do
      marker.items={}; rejected(name,marker)
    end
    rejected(name,setmetatable({items={}},{__index=function() error("inherited data") end}))
    rejected(name,{items=setmetatable({},{__index=function() error("inherited data") end})})
  end
end)
test("quick actions reject partial raw rune and skill responses even with cached rows",function()
  local runeResult,runeErr=Parser.parseRunes({
    "You have the following elemental runes available to you..."," force - 0 weaves remain"})
  local skillResult,skillErr=Parser.parseSkills({"Skill Remain Level","Brawling 0 1"})
  rejected("shoprenew",runeResult,runeErr); rejected("trainall",skillResult,skillErr)
end)
test("quick actions reject all injection characters and malformed rune spacing",function()
  local names={""," force","force ","two  spaces","force\nquit","force\rquit","force\tquit",
    "force;quit","force|quit","force&quit","force'","force\"","force\\quit","force/quit",
    "force"..string.char(96).."quit","force$(quit)","force<quit","force>quit","force!","force%quit",
    "force"..string.char(0),"force"..string.char(27).."[0m","f0rce","forcé",string.rep("a",81)}
  for _,name in ipairs(names) do
    rejected("shoprenew",runes({name,0}))
    rejected("shoprenewall",runes({"Safe",0},{name,100}))
  end
  rejected("shoprenew",{items={{name={},remaining=0}}})
end)
test("quick actions accept a bounded ASCII name of eighty letters",function()
  local q,f,c=fixture(); local name=string.rep("A",80)
  assert(q:start("shoprenew")); c:reply(runes({name,0})); f:advance(1)
  eq(f:actions(),"shop renew "..name:lower())
end)
test("quick actions reject nonfinite negative fractional or coerced rune counts",function()
  for _,row in ipairs({{},{value=-1},{value=.5},{value=math.huge},{value=-math.huge},
    {value=0/0},{value="19"},{value=true},{value={}},{value=9007199254740992}}) do
    rejected("shoprenew",{items={{name="Safe",remaining=0},{name="Force",remaining=row.value}}})
  end
end)
test("quick actions validate remain and level even on unknown or ineligible skill rows",function()
  for _,row in ipairs({{},{value=-1},{value=.5},{value=math.huge},{value=-math.huge},
    {value=0/0},{value="0"},{value=true},{value={}},{value=9007199254740992}}) do
    rejected("trainall",skills({"Brawling",0,1},{"Unknown",row.value,1}))
    rejected("trainall",skills({"Brawling",0,1},{"Dodging",1,row.value}))
  end
  rejected("trainall",skills({"",0,1})); rejected("trainall",skills({string.rep("a",2049),0,1}))
  rejected("trainall",{items={{name={},remain=0,level=1}}})
end)
test("quick actions reject sparse nonarray inherited and oversized item lists",function()
  local valid={name="Force",remaining=0}
  for _,items in ipairs({{[2]=valid},{[1]=valid,[3]=valid},{[0]=valid},{[257]=valid},
    {named=valid},{[1.5]=valid},{[1]=false},{setmetatable(valid,{})}}) do
    rejected("shoprenew",{items=items})
  end
  local oversized={}; for index=1,257 do oversized[index]={name="Force",remaining=0} end
  rejected("shoprenewall",{items=oversized})
  local skillRows={}; for index=1,257 do skillRows[index]={name="Brawling",remain=0,level=1} end
  rejected("trainall",{items=skillRows})
end)
test("quick actions accept at most 256 valid rows and dedupe before scheduling",function()
  local q,f,c=fixture(); local result={items={}}
  for index=1,256 do result.items[index]={name="Force",remaining=0} end
  assert(q:start("shoprenewall")); c:reply(result); f:advance(3)
  eq(f:actions(),"shop renew force")
end)
test("quick actions reject conflicting duplicate rows before spending",function()
  rejected("shoprenew",runes({"Force",19},{"force",20}))
  rejected("shoprenewall",runes({"Force",19},{"force",20}))
  rejected("trainall",skills({"Pole Weapons",0,1},{"Piercing Weapons",2,1}))
  rejected("trainall",skills({"Shield Use",0,1},{"Shield Parry",0,2}))
end)
test("quick actions snapshot validated commands against later table mutation",function()
  local q,f,c=fixture(); local result=runes({"Force",0},{"Healing",0})
  assert(q:start("shoprenew")); c:reply(result)
  result.items[1].name="evil;quit"; result.items[2]=nil; result.items[3]={name="New",remaining=0}
  f:advance(2); eq(f:actions(),"shop renew force,shop renew healing")
end)
test("quick actions reject overlap during requests and queued command sequences",function()
  local q,f,c=fixture(); assert(q:start("shoprenew"))
  for _,name in ipairs({"shoprenew","shoprenewall","trainall"}) do
    local ok,err=q:start(name); eq(ok,nil); eq(err,"A shortcut is already running. Use shoprenewstop or trainallstop to stop it.")
  end
  eq(#c.requests,1); c:reply(runes({"Force",0},{"Healing",0}))
  eq(q:start("trainall"),nil); f:advance(1); eq(q:start("shoprenewall"),nil)
  f:advance(1); assert(q:start("trainall")); eq(#c.requests,2); eq(q:busy(),true)
end)
test("quick actions reject unknown disabled and nonboolean-enabled aliases before requests",function()
  local q,f,c=fixture()
  for _,name in ipairs({"ShopRenew","shoprenew force","","trainall;quit",false,{}}) do
    eq(q:start(name),nil)
  end
  eq(q:start(nil),nil)
  for _,value in ipairs({false,1,"true"}) do
    f.enabled.shoprenew=value; eq(q:start("shoprenew"),nil); eq(q:busy(),false)
  end
  f.enabled.shoprenew=nil; eq(q:start("shoprenew"),nil)
  eq(#c.requests,0); eq(#f.sent,0); eq(q.sending,false)
end)
test("quick actions settingsChanged cancels the active alias only",function()
  local q,f,c=fixture(); assert(q:start("shoprenew"))
  f.enabled.trainall=false; assert(q:settingsChanged()); eq(q:busy(),true)
  c:reply(runes({"Force",0},{"Healing",0})); local stale=f.history[1].callback
  f.enabled.shoprenew=false; assert(q:settingsChanged()); eq(q:busy(),false)
  eq(f:pending(),0); stale(); f:advance(5); eq(f:actions(),"")
  assert(q:settingsChanged())
end)
test("quick actions recheck disabled settings at response and timer boundaries",function()
  local q,f,c=fixture(); assert(q:start("shoprenew")); f.enabled.shoprenew=false
  c:reply(runes({"Force",0})); eq(q:busy(),false); eq(f:pending(),0)
  q,f,c=fixture(); assert(q:start("trainall"))
  c:reply(skills({"Brawling",0,1},{"Biting",0,2})); f:advance(1)
  f.enabled.trainall=false; f:advance(1)
  eq(f:actions(),"train raise 1"); eq(q:busy(),false)
end)
test("quick actions fail closed if options.enabled throws",function()
  local q,f,c=fixture()
  q.options.enabled=function() error("setting error") end
  eq(q:start("shoprenew"),nil); eq(#c.requests,0); eq(q:busy(),false)
  q,f,c=fixture(); assert(q:start("shoprenew")); c:reply(runes({"Force",0}))
  q.options.enabled=function() error("setting error") end
  f:advance(1); eq(f:actions(),""); eq(q:busy(),false)
end)
test("quick actions cancel user interference during capture and allow empty prompt nudges",function()
  local q,f,c=fixture(); c.canonicalize=true; assert(q:start("shoprenew"))
  eq(f.sent[1].command,"info magic"); eq(q:busy(),true)
  assert(q:onOutgoing("")); eq(q:busy(),true); eq(#f.sent,1)
  assert(q:onOutgoing("look")); eq(q:busy(),false)
  c:reply(runes({"Force",0})); f:advance(3); eq(f:actions(),"")
end)
test("quick actions unmarked matching commands and skill filters still interrupt",function()
  for _,command in ipairs({"info mag","info magic","shop renew force","skill","skill ready"," ","\n"}) do
    local q,f,c=fixture(); assert(q:start("shoprenew")); c:reply(runes({"Force",0}))
    q:onOutgoing(command); f:advance(3); eq(q:busy(),false); eq(f:actions(),"")
  end
end)
test("quick actions own marked sends do not mask a different reentrant user command",function()
  local q,f,c=fixture(); assert(q:start("shoprenew")); c:reply(runes({"Force",0},{"Healing",0}))
  f.onSend=function(command)
    if command=="shop renew force" then eq(q.sending,true); q:onOutgoing("look") end
  end
  f:advance(5); eq(f:actions(),"shop renew force"); eq(q:busy(),false); eq(q.sending,false)
end)
test("quick actions cancellation invalidates callbacks across disconnect character swap and update",function()
  for _,reason in ipairs({"disconnected","character swap","package update","cancelled"}) do
    local q,f,c=fixture(); assert(q:start("shoprenew")); local old=c.callbacks[1]
    assert(q:cancel(reason)); eq(q:busy(),false); assert(q:start("trainall"))
    old(runes({"Force",0})); eq(q:busy(),true); eq(f:pending(),0)
    c:reply(skills({"Biting",0,1})); f:advance(1)
    eq(f:actions(),"train raise 46"); eq(q:busy(),false)
  end
end)
test("quick actions stale timers and duplicate timer delivery cannot advance new work",function()
  local q,f,c=fixture(); assert(q:start("shoprenew")); c:reply(runes({"Force",0},{"Healing",0}))
  local old=f.history[1].callback; assert(q:cancel("disconnected")); assert(q:start("trainall"))
  c:reply(skills({"Brawling",0,1},{"Biting",0,1})); local current=f.history[2].callback
  old(); eq(f:actions(),""); eq(f:pending(),1)
  f:advance(1); eq(f:actions(),"train raise 1"); eq(f:pending(),1)
  current(); old(); eq(f:actions(),"train raise 1"); eq(f:pending(),1)
  f:advance(1); eq(f:actions(),"train raise 1,train raise 46"); eq(q:busy(),false)
end)
test("quick actions repeated collector callbacks cannot replace or duplicate the queue",function()
  local q,f,c=fixture(); assert(q:start("shoprenew")); local done=c.callbacks[1]
  done(runes({"Force",0},{"Healing",0})); done(runes({"Vigor",0})); done(nil,"late error")
  f:advance(2); eq(f:actions(),"shop renew force,shop renew healing")
  done(runes({"Vigor",0})); f:advance(5); eq(f:actions(),"shop renew force,shop renew healing")
end)
test("quick actions shutdown is permanent idempotent and invalidates pending callbacks",function()
  local q,f,c=fixture(); assert(q:start("shoprenew")); local done=c.callbacks[1]
  assert(q:shutdown()); assert(q:shutdown()); done(runes({"Force",0}))
  eq(q:start("shoprenew"),nil); eq(q:busy(),false); eq(f:pending(),0); eq(#f.sent,1)
  q,f,c=fixture(); assert(q:start("trainall")); c:reply(skills({"Brawling",0,1}))
  local stale=f.history[1].callback; assert(q:shutdown()); stale(); eq(f:actions(),"")
end)
test("quick actions synchronous successful responses wait for confirmation and timer delay",function()
  local q,f,c=fixture(); local request=c.request
  function c:request(command,done)
    local accepted,err=request(self,command,done)
    done(runes({"Healing",0},{"Force",0})); eq(f:pending(),0); eq(q:busy(),true)
    return accepted,err
  end
  assert(q:start("shoprenew")); eq(f:pending(),1); eq(#f.sent,1); eq(q.sending,false)
  f:advance(2); eq(f:actions(),"shop renew force,shop renew healing")
end)
test("quick actions synchronous callback data is snapshotted before request returns",function()
  local q,f,c=fixture(); local request=c.request
  function c:request(command,done)
    request(self,command,done)
    local result=runes({"Force",0}); done(result); result.items[1].name="Healing"; return true
  end
  assert(q:start("shoprenew")); f:advance(1); eq(f:actions(),"shop renew force")
end)
test("quick actions never schedule synchronous responses when requests are refused or throw",function()
  for _,mode in ipairs({"nil","false","throw","error with true","unconfirmed"}) do
    local q,f,c=fixture()
    function c:request(_,done)
      done(runes({"Force",0})); eq(f:pending(),0)
      if mode=="throw" then error("request threw") end
      if mode=="error with true" then return true,"send failed" end
      if mode=="false" then return false,"busy" end
      if mode=="unconfirmed" then return 1 end
      return nil,"busy"
    end
    eq(q:start("shoprenew"),nil); eq(q:busy(),false); eq(q.sending,false)
    f:advance(5); eq(#f.sent,0); eq(f:pending(),0)
  end
end)
test("quick actions synchronous callback errors propagate from start",function()
  for _,result in ipairs({{},runes({"unsafe;quit",0})}) do
    local q,f,c=fixture()
    function c:request(_,done) done(result); return true end
    local ok,err=q:start("shoprenew"); eq(ok,nil); eq(type(err),"string"); eq(q:busy(),false)
  end
  local q,f,c=fixture()
  function c:request(_,done) done(nil,"incomplete response"); return true end
  local ok,err=q:start("shoprenew"); eq(ok,nil); eq(err,"shoprenew stopped because a fresh, complete rune list could not be confirmed. Refresh it and try again."); eq(f:pending(),0)
end)
test("quick actions collector request send failures stop and reset sending protection",function()
  for _,mode in ipairs({"false","nil error","throw"}) do
    local q,f,c=fixture()
    function f:sendCommand()
      eq(q.sending,true)
      if mode=="throw" then error("send error") end
      if mode=="false" then return false,"send error" end
      return nil,"send error"
    end
    eq(q:start("shoprenew"),nil); eq(q:busy(),false); eq(q.sending,false); eq(f:pending(),0)
  end
end)
test("quick actions queued send errors stop subsequent spending and reset sending",function()
  for _,mode in ipairs({"false","nil error","throw","true error"}) do
    local q,f,c=fixture(); assert(q:start("shoprenew")); c:reply(runes({"Force",0},{"Healing",0}))
    local calls=0
    function f:sendCommand(command)
      calls=calls+1; eq(command,"shop renew force"); eq(q.sending,true); q:onOutgoing(command)
      if mode=="throw" then error("send error") end
      if mode=="false" then return false end
      if mode=="true error" then return true,"send error" end
      return nil,"send error"
    end
    f:advance(10); eq(calls,1); eq(q:busy(),false); eq(q.sending,false); eq(f:pending(),0)
  end
end)
test("quick actions support void send and cancel returns used by Mudlet adapters",function()
  local q,f,c=fixture(); local send=f.sendCommand
  function f:sendCommand(command) send(self,command) end
  function f:cancelTimer(id) self.timers[id]=nil end
  assert(q:start("shoprenew")); c:reply(runes({"Force",0},{"Healing",0}))
  f:advance(1); eq(f:actions(),"shop renew force"); assert(q:cancel("user cancelled"))
  f:advance(5); eq(f:actions(),"shop renew force")
end)
test("quick actions timer scheduling errors and immediate callbacks cannot spend",function()
  for _,mode in ipairs({"nil","false","throw","callback","id error"}) do
    local q,f,c=fixture(); assert(q:start("shoprenew")); local schedule=f.schedule
    function f:schedule(delay,callback)
      eq(delay,1)
      if mode=="throw" then error("timer error") end
      if mode=="callback" then callback(); return schedule(self,delay,callback) end
      if mode=="id error" then return schedule(self,delay,callback),"timer error" end
      if mode=="false" then return false end
      return nil,"timer error"
    end
    c:reply(runes({"Force",0})); eq(q:busy(),false); f:advance(5); eq(f:actions(),""); eq(f:pending(),0)
  end
end)
test("quick actions cancellation during timer registration cannot resurrect a timer",function()
  local q,f,c=fixture(); assert(q:start("shoprenew")); local schedule=f.schedule
  function f:schedule(delay,callback)
    local id=schedule(self,delay,callback); q:cancel("disconnected"); return id
  end
  c:reply(runes({"Force",0})); eq(q:busy(),false); eq(f:pending(),0); eq(#f.canceled,1)
  f.history[1].callback(); eq(f:actions(),"")
end)
test("quick actions failed timer cancellation still invalidates stale work",function()
  for _,mode in ipairs({"false","nil error","throw"}) do
    local q,f,c=fixture(); assert(q:start("shoprenew")); c:reply(runes({"Force",0}))
    local stale=f.history[1].callback
    function f:cancelTimer()
      stale()
      if mode=="throw" then error("cancel error") end
      if mode=="false" then return false end
      return nil,"cancel error"
    end
    eq(q:cancel("disconnected"),nil); eq(q:busy(),false); stale(); f:advance(10)
    eq(f:actions(),""); eq(q.sending,false)
  end
end)
test("quick actions tolerate absent or throwing notifications without hidden sends",function()
  for _,mode in ipairs({"absent","throw"}) do
    local q,f,c=fixture()
    q.options.notify=mode=="throw" and function() error("notification error") end or nil
    assert(q:start("shoprenew")); c:reply(runes({"Force",0})); f:advance(1)
    eq(f:actions(),"shop renew force"); eq(#f.sent,2); eq(q:busy(),false)
    assert(q:cancel()); assert(q:onOutgoing("look")); eq(#f.sent,2)
  end
end)
test("quick actions reject overlap from reentrant collector request calls",function()
  local q,f,c=fixture(); local request=c.request
  function c:request(command,done) eq(q:start("trainall"),nil); return request(self,command,done) end
  assert(q:start("shoprenew")); eq(#c.requests,1); eq(q:busy(),true)
end)

test("quick actions show a refresh confirmation and an exact deduped queue length",function()
  local q,f,c=fixture(); assert(q:start("shoprenew"))
  eq(f.notices[1],"Refreshing your runes for shoprenew... Use shoprenewstop to stop.")
  c:reply(runes({"Healing",0},{"Force",0},{"force",0},{"Vigor",20}))
  eq(f.notices[2],"shoprenew: 2 runes queued for renewal, one per second. Use shoprenewstop to stop.")
  f:advance(2); eq(f.notices[3],"shoprenew finished.")
  q,f,c=fixture(); assert(q:start("trainall")); c:reply(skills({"Biting",0,1}))
  eq(f.notices[1],"Refreshing your skills for trainall... Use trainallstop to stop.")
  eq(f.notices[2],"trainall: 1 skill queued for training, one per second. Use trainallstop to stop.")
end)
test("quick actions humanize disabled busy and shutdown errors",function()
  local q,f,c=fixture(); f.enabled.shoprenew=false
  local ok,err=q:start("shoprenew")
  eq(ok,nil); eq(err,"shoprenew is OFF. Enable it in OPTIONS → Skills & Runes, then Save.")
  eq(f.notices[1],err); eq(#c.requests,0)
  f.enabled.shoprenew=true; assert(q:start("shoprenew"))
  ok,err=q:start("trainall")
  eq(ok,nil); eq(err,"A shortcut is already running. Use shoprenewstop or trainallstop to stop it.")
  assert(q:shutdown())
  ok,err=q:start("shoprenew"); eq(ok,nil); eq(err,"Shortcuts are unavailable because the HUD has closed.")
end)
test("quick actions humanize collector busy incomplete send and scheduler failures",function()
  local q,f,c=fixture()
  function c:request() return nil,"collector busy" end
  local ok,err=q:start("shoprenew")
  eq(ok,nil); eq(err,"The HUD is already refreshing your character. Wait for it to finish, then try shoprenew again.")
  q,f,c=fixture(); assert(q:start("trainall")); c:reply(nil,"incomplete skill response")
  eq(f.notices[2],"trainall stopped because a fresh, complete skill list could not be confirmed. Refresh it and try again.")
  q,f,c=fixture(); assert(q:start("shoprenew")); c:reply(runes({"Force",0}))
  function f:sendCommand() error("raw send error") end
  f:advance(1)
  eq(f.notices[3],"shoprenew stopped because a command could not be sent. Check your connection, then try again.")
  q,f,c=fixture(); assert(q:start("shoprenew"))
  function f:schedule() return nil,"internal timer error" end
  c:reply(runes({"Force",0}))
  eq(f.notices[3],"shoprenew stopped because the next action could not be scheduled. Try the shortcut again.")
end)
test("quick actions explain why an empty queue or user interruption stopped work",function()
  local q,f,c=fixture(); assert(q:start("shoprenew")); c:reply(runes({"Force",20}))
  eq(f.notices[2],"shoprenew: No runes have fewer than 20 weaves remaining.")
  q,f,c=fixture(); assert(q:start("trainall")); c:reply(skills({"Unknown",0,1}))
  eq(f.notices[2],"trainall: No known skills are ready to train.")
  q,f,c=fixture(); assert(q:start("shoprenew")); q:onOutgoing("look")
  eq(f.notices[2],"shoprenew stopped because you sent another command.")
end)
test("quick actions notification cancellation prevents requests or queued commands",function()
  local q,f,c=fixture()
  q.options.notify=function() q:cancel("user cancelled") end
  eq(q:start("shoprenew"),nil); eq(#c.requests,0); eq(q:busy(),false)
  q,f,c=fixture(); assert(q:start("shoprenew"))
  q.options.notify=function() q:cancel("user cancelled") end
  c:reply(runes({"Force",0})); eq(q:busy(),false); eq(f:pending(),0); eq(f:actions(),"")
end)

if standalone then
  print(string.format("%d quick actions tests, %d failures",total,failed))
  assert(failed==0,"quick actions tests failed")
end
