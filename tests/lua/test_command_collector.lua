local Collector=require("command_collector")
local Parser=require("command_parser")
local inventory={"Items carried:","  A torch [1.0 lb].","Your inventory totals 1.0 lbs.",">"}
local stat={"Body Armor: 4%.","OR: 18  DR: 70  Move Rate: 6/6 UDs  Dam Bonus: Good/None  Stance: Aggressive","::: Equipment Readied :::","  A spear.",">"}
local info={"You are Test Tester, a stocky bodied 28 year old Entropic Male young Monitanian.  You are 6'10\" and weigh 309 lbs.","Str Int Wis Dex Agi Con Cha Wil Voi Per App","Good Low Fair Fair Fair Good Good Good Aver Fair Fair",">"}
local religion={"You are a Novitiate follower of Unknown.","You have earned 57000 favors.","You are Balanced within your Entropic alignment.",">"}
local runes={"You have the following elemental runes available to you...","  force       - 100 weaves remain   healing     -  14 weaves remain","  holy        -  99 weaves remain   vigor       - 100 weaves remain","  light       - 100 weaves remain",">"}
local skills={"Skill                     Remain Level","Biting                    105    4","Clawing                   276    2",">"}
local time={"Current time is: Wed Sep  2 00:40:30 2026 EST.","It is now 3:22 am on the 4th day of the 8th month in the year 362.","You have been adventuring for 14 secs this session.",">"}
local function fake()
  local f={next=0,triggers={},events={},timers={},timer_delays={},sent={}}
  local function id(self,prefix) self.next=self.next+1; return prefix..self.next end
  function f:addLineTrigger(fn) local key=id(self,"t"); self.triggers[key]=fn; return key end
  function f:killTrigger(key) self.triggers[key]=nil end
  function f:addEvent(name,fn) local key=id(self,"e"); self.events[key]={name=name,fn=fn}; return key end
  function f:killEvent(key) self.events[key]=nil end
  function f:schedule(delay,fn) self.last_delay=delay; local key=id(self,"m"); self.timers[key]=fn; self.timer_delays[key]=delay; return key end
  function f:cancelTimer(key) self.timers[key]=nil; self.timer_delays[key]=nil end
  function f:sendCommand(command) self.sent[#self.sent+1]=command end
  function f:line(value) for _,fn in pairs(self.triggers) do fn(value) end end
  function f:lines(values) for _,value in ipairs(values) do self:line(value) end end
  function f:outgoing(command) for _,event in pairs(self.events) do if event.name=="sysDataSendRequest" then event.fn(nil,command) end end end
  function f:disconnect() for _,event in pairs(self.events) do if event.name=="sysDisconnectionEvent" then event.fn() end end end
  function f:fireTimer() local key,fn=next(self.timers); if key then self.timers[key]=nil; fn() end end
  function f:fireDelay(delay) for key,value in pairs(self.timer_delays) do if value==delay then local fn=self.timers[key]; self.timers[key]=nil; self.timer_delays[key]=nil; fn(); return true end end return false end
  function f:hasDelay(delay) for _,value in pairs(self.timer_delays) do if value==delay then return true end end return false end
  function f:owned() local n=0; for _ in pairs(self.triggers) do n=n+1 end; for _ in pairs(self.events) do n=n+1 end; for _ in pairs(self.timers) do n=n+1 end; return n end
  return f
end

test("tracked commands send one delayed blank prompt nudge",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("skill")
  eq(#f.sent,0); eq(f:fireDelay(.15),true); eq(#f.sent,1); eq(f.sent[1],""); eq(f:fireDelay(.15),false)
end)
test("completed output cancels its pending blank prompt nudge",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("inventory"); f:lines(inventory)
  eq(c.snapshot.inventory.total_weight,1); eq(f:fireDelay(.15),false); eq(#f.sent,0)
end)

test("collector runs one sequential refresh after character entry",function()
  local f=fake(); local changes=0; local c=Collector.new(f,Parser,function() changes=changes+1 end); c:start()
  f:line("Welcome to Dragon's Gate, Test!"); eq(f.sent[1],"inventory"); eq(#f.sent,1)
  f:lines(inventory); eq(f.sent[2],"stat")
  f:lines(stat); eq(f.sent[3],"info")
  f:lines(info); eq(f.sent[4],"info religion")
  f:lines(religion); eq(f.sent[5],"info mag")
  f:lines(runes); eq(f.sent[6],"skill")
  f:lines(skills); eq(f.sent[7],"time")
  f:lines(time); eq(changes,8); eq(c.snapshot.religion.deity,"Unknown"); eq(c.snapshot.religion.favors,57000); eq(c.snapshot.runes.items[1].name,"Healing"); eq(#c.snapshot.skills.items,2); eq(c.snapshot.time.minute,22)
  f:line("Welcome to Dragon's Gate, Test!"); eq(#f.sent,7)
end)
test("collector completes every startup command with staff vitals prompts",function()
  local function staff(lines)
    local copy={}; for i,value in ipairs(lines) do copy[i]=value end
    copy[#copy]="[199] 301/301 hp, 173/173 ftg >"; return copy
  end
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:line("Welcome to Dragon's Gate, Wizzy!")
  f:lines(staff(inventory)); f:lines(staff(stat)); f:lines(staff(info)); f:lines(staff(religion)); f:lines(staff(runes)); f:lines(staff(skills)); f:lines(staff(time))
  eq(table.concat(f.sent,","),"inventory,stat,info,info religion,info mag,skill,time"); eq(c.active,nil); eq(c.snapshot.skills.items[1].name,"Biting"); eq(c.snapshot.time.minute,22)
end)
test("collector can refresh after an in-session package install",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start()
  eq(c:refresh(),true); eq(f.sent[1],"inventory"); eq(c.refreshed,true); eq(f:hasDelay(2.5),true)
  eq(c:refresh(),false); eq(#f.sent,1)
end)
test("collector force refresh bypasses the session guard without overlapping a sequence",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start()
  eq(c:refresh(),true); eq(c:forceRefresh(),false); eq(#f.sent,1)
  f:lines(inventory); f:lines(stat); f:lines(info); f:lines(religion); f:lines(runes); f:lines(skills); f:lines(time)
  eq(c:forceRefresh(),true); eq(f.sent[8],"inventory")
end)
test("post-update restart refresh replaces a stalled sequence and begins from inventory",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); eq(c:refresh(),true); eq(c.active.command,"inventory")
  f:outgoing("skill"); eq(c.active.command,"skill"); eq(c:restartRefresh(),true); eq(c.active.command,"inventory"); eq(f.sent[#f.sent],"inventory")
end)
test("collector captures manual time commands",function()
  local f=fake(); local changed; local c=Collector.new(f,Parser,function(_,key) changed=key end); c:start(); f:outgoing("time"); f:lines(time)
  eq(changed,"time"); eq(c.snapshot.time.hour,3); eq(c.snapshot.time.minute,22)
end)
test("collector captures manual info religion commands",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("info religion"); f:lines(religion); eq(c.snapshot.religion.rank,"Novitiate")
end)
test("collector refreshes runes whenever info mag is entered manually",function()
  local f=fake(); local changed; local c=Collector.new(f,Parser,function(_,key) changed=key end); c:start(); f:outgoing("info mag"); f:lines(runes)
  eq(changed,"runes"); eq(c.snapshot.runes.items[1].name,"Healing"); eq(c.snapshot.runes.items[1].remaining,14)
end)
test("collector refreshes skills whenever skill is entered manually",function()
  local f=fake(); local changed; local c=Collector.new(f,Parser,function(_,key) changed=key end); c:start(); f:outgoing("skill"); f:lines(skills)
  eq(changed,"skills"); eq(c.snapshot.skills.items[1].name,"Biting")
end)
test("collector captures manual commands and removes owned runtime",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("inventory"); f:lines(inventory); eq(c.snapshot.inventory.total_weight,1); c:shutdown(); eq(f:owned(),0)
end)
test("partial info refresh merges without erasing prior physical data",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("info"); f:lines(info); eq(c.snapshot.info.physical.age,28)
  f:outgoing("info"); f:lines({"Str Int Wis Dex Agi Con Cha Wil Voi Per App","Great Great Great Great Great Great Great Great Great Great Great",">"}); eq(c.snapshot.info.physical.age,28); eq(c.snapshot.info.attributes.APP,"Great")
end)
test("collector treats inv as a manual inventory command",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("inv"); f:lines(inventory); eq(c.snapshot.inventory.total_weight,1)
end)
test("collector reports explicit game delay lines",function()
  local f=fake(); local delay; local c=Collector.new(f,Parser,function() end,function(value) delay=value end); c:start(); f:line("[8 sec. delay]"); eq(delay,8)
end)
test("character welcome clears old data and bounded recovery advances startup",function()
  local f=fake(); local reset; local c=Collector.new(f,Parser,function(snapshot,key) if key=="reset" then reset=snapshot end end); c.snapshot.inventory={total_weight=7}; c:start(); f:line("Welcome to Dragon's Gate, Test!")
  eq(c.snapshot.inventory,nil); eq(reset,c.snapshot)
  eq(f:fireDelay(2.5),true); eq(c.active.command,"inventory"); eq(c.active.timeout_stage,"recovery"); eq(f.sent[#f.sent],"")
  eq(f:fireDelay(2.5),true); eq(c.active.command,"inventory"); eq(c.active.timeout_stage,"drain")
  eq(f:fireDelay(.5),true); eq(f.sent[#f.sent],"stat")
end)
test("premature prompt does not advance an unrecognized startup response",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:line("Welcome to Dragon's Gate, Test!"); f:lines({"unexpected inventory format",">"}); eq(#f.sent,1); eq(c.active.command,"inventory")
  assert(f:fireDelay(2.5)); eq(c.active.command,"inventory"); assert(f:fireDelay(2.5)); eq(c.active.command,"inventory"); assert(f:fireDelay(.5)); eq(f.sent[#f.sent],"stat")
end)
test("command-specific timeout keeps slower skill collection bounded",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("skill")
  eq(f:hasDelay(3),true); eq(f:fireDelay(3),true); eq(c.active.command,"skill"); eq(c.active.timeout_stage,"recovery")
  eq(f:fireDelay(3),true); eq(c.active.timeout_stage,"drain"); eq(f:fireDelay(.5),true); eq(c.active,nil)
end)
test("delayed output during recovery remains owned by and completes original command",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:line("Welcome to Dragon's Gate, Test!")
  eq(f:fireDelay(2.5),true); eq(c.active.command,"inventory"); f:lines(inventory)
  eq(c.snapshot.inventory.total_weight,1); eq(c.active.command,"stat"); eq(f.sent[#f.sent],"stat")
end)
test("late unrelated lines during drain cannot be assigned to the next command",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:line("Welcome to Dragon's Gate, Test!")
  eq(f:fireDelay(2.5),true); eq(f:fireDelay(2.5),true); eq(c.active.timeout_stage,"drain")
  f:lines(stat); eq(c.snapshot.stat,nil); eq(c.active.command,"inventory")
  eq(f:fireDelay(.5),true); eq(c.active.command,"stat")
end)
test("delayed religion and skill output cannot be assigned to the next command",function()
  local f=fake(); local changes={}; local c=Collector.new(f,Parser,function(_,key) changes[#changes+1]=key end); c:start(); f:line("Welcome to Dragon's Gate, Test!")
  f:lines(inventory); f:lines(stat)
  local info_without_prompt={}; for i=1,#info-1 do info_without_prompt[i]=info[i] end; f:lines(info_without_prompt); eq(c.active.command,"info"); f:line(">"); eq(c.active.command,"info religion")
  f:lines({"Use: INFO <subject> for more info.",">","You are a Novitiate follower of Unknown.","You are Balanced within your Entropic alignment.",">"}); eq(c.active.command,"info mag")
  f:lines(runes); eq(c.active.command,"skill")
  f:lines({">","Skill                     Remain Level","Biting                    105    4","Clawing                   276    2",">"}); eq(c.active.command,"time"); eq(#c.snapshot.skills.items,2)
  f:lines(time); eq(c.snapshot.time.minute,22); eq(table.concat(changes,","),"reset,inventory,stat,info,religion,runes,skills,time")
end)
test("manual tracked commands replace active startup capture and update before startup resumes",function()
  local f=fake(); local changes={}; local c=Collector.new(f,Parser,function(_,key) changes[#changes+1]=key end); c:start(); f:line("Welcome to Dragon's Gate, Test!"); f:outgoing("skill")
  eq(c.active.command,"skill"); f:lines(skills); eq(c.active.command,"inventory"); eq(f.sent[2],"inventory"); f:lines(inventory); eq(c.active.command,"stat"); eq(f.sent[3],"stat"); eq(table.concat(changes,","),"reset,skills,inventory")
end)
test("disconnect permits one refresh after re-entry",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:line("Welcome to Dragon's Gate, Test!"); f:disconnect(); f:line("Welcome to Dragon's Gate, Test!"); eq(f.sent[#f.sent],"inventory")
end)
test("switching characters without disconnect starts a fresh character entry",function()
  local f=fake(); local names={}; local c=Collector.new(f,Parser,function() end,nil,function(name) names[#names+1]=name end); c:start()
  f:line("Welcome to Dragon's Gate, Muthulas!"); f:line("Welcome to Dragon's Gate, Muthulas!"); f:line("Welcome to Dragon's Gate, Dace!")
  eq(table.concat(names,","),"Muthulas,Dace")
end)
