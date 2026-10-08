local Collector=require("command_collector")
local Parser=require("command_parser")
local inventory={"Items carried:","  A torch [1.0 lb].","Your inventory totals 1.0 lbs.",">"}
local stat={"Body Armor: 4%.","OR: 18  DR: 70  Move Rate: 6/6 UDs  Dam Bonus: Good/None  Stance: Aggressive","::: Equipment Readied :::","  A spear.",">"}
local info={"You are Test Tester, a stocky bodied 28 year old Entropic Male young Monitanian.  You are 6'10\" and weigh 309 lbs.","Str Int Wis Dex Agi Con Cha Wil Voi Per App","Good Low Fair Fair Fair Good Good Good Aver Fair Fair",">"}
local religion={"You are a Novitiate follower of Unknown.","You have earned 57000 favors.","You are Balanced within your Entropic alignment.",">"}
local runes={"You have the following elemental runes available to you...","  force       - 100 weaves remain   healing     -  14 weaves remain","  holy        -  99 weaves remain   vigor       - 100 weaves remain","  light       - 100 weaves remain",">"}
local skills={"Skill                     Remain Level","Biting                    105    4","Clawing                   276    2",">"}
local time={"Current time is: Wed Sep  2 00:40:30 2026 EST.","It is now 3:22 am on the 4th day of the 8th month in the year 362.","You have been adventuring for 14 secs this session.",">"}
local namedTime={"Server local time is: Mon Sep 14 01:13:51 2026 (pacific).","Today is the 59th day of Majus in the year 362. The time is 4:29.","You have been adventuring for 4 hrs, 50 mins, 30 secs this session.","[9006] 301/301 hp, 173/173 ftg >"}
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
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("inventory")
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
  f:lines(religion); eq(f.sent[5],"info magic")
  f:lines(runes); eq(f.sent[6],"skill")
  f:lines(skills); eq(f.sent[7],"time")
  f:lines(time); eq(changes,10); eq(c.snapshot.religion.deity,"Unknown"); eq(c.snapshot.religion.favors,57000); eq(c.snapshot.runes.items[1].name,"Healing"); eq(#c.snapshot.skills.items,2); eq(c.snapshot.time.minute,22)
  f:line("Welcome to Dragon's Gate, Test!"); eq(#f.sent,7)
end)
test("collector completes every startup command with staff vitals prompts",function()
  local function staff(lines)
    local copy={}; for i,value in ipairs(lines) do copy[i]=value end
    copy[#copy]="[199] 301/301 hp, 173/173 ftg >"; return copy
  end
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:line("Welcome to Dragon's Gate, Wizzy!")
  f:lines(staff(inventory)); f:lines(staff(stat)); f:lines(staff(info)); f:lines(staff(religion)); f:lines(staff(runes)); f:lines(staff(skills)); f:lines(staff(time))
  eq(table.concat(f.sent,","),"inventory,stat,info,info religion,info magic,skill,time"); eq(c.active,nil); eq(c.snapshot.skills.items[1].name,"Biting"); eq(c.snapshot.time.minute,22)
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
test("new named-month time response completes without injecting blank prompts",function()
  local f=fake(); local changed; local c=Collector.new(f,Parser,function(_,key) changed=key end); c:start(); f:outgoing("time")
  eq(f:fireDelay(.15),false); eq(#f.sent,0); f:lines(namedTime)
  eq(changed,"time"); eq(c.snapshot.time.month_name,"Majus"); eq(c.snapshot.time.minute,29); eq(c.active,nil); eq(#f.sent,0)
end)
test("unknown time format ends at its natural prompt without injecting Enter",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("time"); f:lines({"A future time format.","[9006] 301/301 hp, 173/173 ftg >"})
  eq(c.active,nil); eq(#f.sent,0); eq(f:fireDelay(2),false)
end)
test("collector captures manual info religion commands",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("info religion"); f:lines(religion); eq(c.snapshot.religion.rank,"Novitiate")
end)
test("collector refreshes runes whenever info magic is entered manually",function()
  local f=fake(); local changed; local c=Collector.new(f,Parser,function(_,key) changed=key end); c:start(); f:outgoing("info magic"); f:lines(runes)
  eq(changed,"runes"); eq(c.snapshot.runes.items[1].name,"Healing"); eq(c.snapshot.runes.items[1].remaining,14)
end)
test("collector retains info mag as a manual compatibility alias",function()
  local f=fake(); local changed; local c=Collector.new(f,Parser,function(_,key) changed=key end); c:start(); f:outgoing("info mag"); f:lines(runes)
  eq(changed,"runes"); eq(c.snapshot.runes.items[1].name,"Healing"); eq(c.snapshot.runes.items[1].remaining,14)
end)
test("collector refreshes skills whenever skill is entered manually",function()
  local f=fake(); local changed; local c=Collector.new(f,Parser,function(_,key) changed=key end); c:start(); f:outgoing("skill"); f:lines(skills)
  eq(changed,"skills"); eq(c.snapshot.skills.items[1].name,"Biting")
end)
test("blank terminated skills refresh on the next event turn without Enter or a prompt",function()
  local f=fake(); local changes=0; local c=Collector.new(f,Parser,function(_,key) if key=="skills" then changes=changes+1 end end); c:start(); f:outgoing("skill")
  eq(f:fireDelay(.15),false); f:lines({"",skills[1],skills[2],skills[3],"",""})
  eq(changes,0); eq(f:fireDelay(0),true); eq(changes,1); eq(#c.snapshot.skills.items,2)
  eq(c.active,nil); eq(#f.sent,0); eq(f:hasDelay(3),false); eq(f:fireDelay(0),false)
  c:shutdown(); eq(f:owned(),0)
end)
test("skill boundary ignores leading blanks and keeps later rows from the same burst",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("skill")
  f:lines({"",skills[1],""}); eq(f:fireDelay(0),false)
  f:lines({skills[2],""}); eq(f:hasDelay(0),true)
  f:line(skills[3]); eq(f:hasDelay(0),false); f:line(""); assert(f:fireDelay(0))
  eq(#c.snapshot.skills.items,2); eq(#f.sent,0)
end)
test("skill boundary finishes before later combat output without consuming its fields",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("skill")
  f:lines({skills[1],skills[2],skills[3],"","You punch at the practice target!","[4 sec. delay]"})
  assert(f:fireDelay(0)); eq(#c.snapshot.skills.items,2); eq(c.active,nil); eq(#f.sent,0)
end)
test("stale skill boundary cannot update another command or survive shutdown",function()
  for _,action in ipairs({"command","disconnect","shutdown"}) do
    local f=fake(); local changes=0; local c=Collector.new(f,Parser,function(_,key) if key=="skills" then changes=changes+1 end end); c:start(); f:outgoing("skill")
    f:lines({skills[1],skills[2],""}); local stale=f.timers[c.skill_boundary]
    if action=="command" then f:outgoing("time") elseif action=="disconnect" then f:disconnect() else c:shutdown() end
    eq(c.skill_boundary,nil)
    local expected=action=="command" and 1 or 0
    eq(changes,expected); stale(); eq(changes,expected)
    if action=="command" then eq(#c.snapshot.skills.items,1); eq(c.active.command,"time") else eq(c.snapshot.skills,nil) end
  end
end)
test("a completed skill table is retained before a new command interrupts its deferred callback",function()
  local f=fake(); local changes=0; local c=Collector.new(f,Parser,function(_,key) if key=="skills" then changes=changes+1 end end)
  c:start(); f:outgoing("skill"); f:lines({skills[1],skills[2],skills[3],""})
  local stale=f.timers[c.skill_boundary]; f:outgoing("info")
  eq(changes,1); eq(#c.snapshot.skills.items,2); eq(c.active.command,"info"); eq(#f.sent,0)
  stale(); eq(changes,1); eq(c.active.command,"info")
  f:lines(info); eq(changes,1); eq(c.snapshot.info.physical.age,28); eq(#c.snapshot.skills.items,2)
  c:shutdown(); eq(f:owned(),0)
end)
test("startup proceeds to time immediately after a blank terminated skill table",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); c:refresh()
  f:lines(inventory); f:lines(stat); f:lines(info); f:lines(religion); f:lines(runes)
  f:lines({skills[1],skills[2],skills[3],""}); assert(f:fireDelay(0))
  eq(c.active.command,"time"); eq(f.sent[#f.sent],"time"); eq(#c.snapshot.skills.items,2)
end)
test("collector captures manual commands and removes owned runtime",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("inventory"); f:lines(inventory); eq(c.snapshot.inventory.total_weight,1); c:shutdown(); eq(f:owned(),0)
end)
test("partial info refresh merges without erasing prior physical data",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("info"); f:lines(info); eq(c.snapshot.info.physical.age,28)
  f:outgoing("info"); f:lines({"Str Int Wis Dex Agi Con Cha Wil Voi Per App","Great Great Great Great Great Great Great Great Great Great Great",">"}); eq(c.snapshot.info.physical.age,28); eq(c.snapshot.info.attributes.APP,"Great")
end)
test("inventory collector keeps equipped locations and section metadata",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); assert(c:start()); f:outgoing("inventory")
  f:lines({"Items equipped:",'[1] "A practice bow" [2.2 lbs] (right hand)',
    "Items carried:",'[2] "A backpack" [10.0 lbs]',"Your inventory totals 12.2 lbs.",">"})
  eq(#c.snapshot.inventory.items,2); eq(c.snapshot.inventory.items[1].location,"right hand")
  eq(c.snapshot.inventory.items[2].section,"carried"); eq(c.active,nil)
end)
-- Item and rune rows from the October 8 player log; unrelated room/chat text is omitted.
local playerInventory={"Items equipped:","",
  "  A simple wooden boomerang [3.3 lbs] (right hand)",
  "  A heavy tin armor [22.0 lbs] (body armor)",
  "  A bone shield [2.2 lbs] (shield arm)",
  "  A grey sash of Unknown [0.2 lbs] (on belt)","",
  "Items carried:","",
  "  An open large leather backpack [15.1 lbs]",
  "  A simple wooden long sword [0.2 lbs]",
  "  A simple wooden cudgel [0.5 lbs]",
  "  A simple wooden spear [0.5 lbs]","",
  "Your inventory totals 120.5 lbs.",">"}
local playerRunes={"info magic","l","",
  "You have the following elemental runes available to you...","",
  "   force       -  62 weaves remain   metal       -  59 weaves remain",
  "   strength    -  60 weaves remain   agility     -  58 weaves remain",
  "   dexterity   -  57 weaves remain   war         -  64 weaves remain","",">"}
local function withPrompt(lines,prompt)
  local copy={}; for index,value in ipairs(lines) do copy[index]=value end
  copy[#copy]=prompt; return copy
end
local function assertPlayerInventory(parsed)
  local expected={
    {"A simple wooden boomerang",3.3,"equipped","right hand"},
    {"A heavy tin armor",22,"equipped","body armor"},
    {"A bone shield",2.2,"equipped","shield arm"},
    {"A grey sash of Unknown",.2,"equipped","on belt"},
    {"An open large leather backpack",15.1,"carried"},
    {"A simple wooden long sword",.2,"carried"},
    {"A simple wooden cudgel",.5,"carried"},
    {"A simple wooden spear",.5,"carried"},
  }
  eq(#parsed.items,8); eq(parsed.total_weight,120.5)
  for index,item in ipairs(expected) do
    eq(parsed.items[index].name,item[1]); eq(parsed.items[index].weight,item[2])
    eq(parsed.items[index].section,item[3]); eq(parsed.items[index].location,item[4])
  end
end
local function assertPlayerRunes(parsed)
  local expected={{"Dexterity",57},{"Agility",58},{"Metal",59},{"Strength",60},{"Force",62},{"War",64}}
  eq(#parsed.items,6)
  for index,rune in ipairs(expected) do
    eq(parsed.items[index].name,rune[1]); eq(parsed.items[index].remaining,rune[2])
  end
end
for _,case in ipairs({{name="plain",prompt=">"},{name="vitals",prompt="[199] 301/301 hp, 173/173 ftg >"}}) do
  local prompt=case.prompt
  test("manual collector applies all eight player inventory items with "..case.name.." prompt",function()
    local f=fake(); local applied; local changes=0
    local c=Collector.new(f,Parser,function(snapshot,key,parsed)
      if key=="inventory" then changes=changes+1; applied=parsed; eq(snapshot.inventory,parsed) end
    end); assert(c:start()); f:outgoing("inventory")
    local response=withPrompt(playerInventory,prompt)
    for index=1,#response-1 do f:line(response[index]) end
    eq(changes,0); eq(c.snapshot.inventory,nil); eq(c.active.command,"inventory")
    f:line(response[#response]); eq(changes,1); eq(applied,c.snapshot.inventory)
    assertPlayerInventory(applied); eq(c.active,nil); eq(c.timeout,nil); eq(c.prompt_nudge,nil); eq(#f.sent,0)
    c:shutdown(); eq(f:owned(),0)
  end)
  test("startup collector retains all eight player inventory items with "..case.name.." prompt",function()
    local f=fake(); local changes=0; local applied
    local c=Collector.new(f,Parser,function(snapshot,key)
      if key=="inventory" then changes=changes+1; applied=snapshot.inventory end
    end); assert(c:start()); f:line("Welcome to Dragon's Gate, Test!")
    eq(c.active.command,"inventory"); eq(f.sent[1],"inventory")
    f:lines(withPrompt(playerInventory,prompt)); eq(changes,1); assertPlayerInventory(applied)
    eq(c.active.command,"stat"); eq(f.sent[2],"stat")
    f:lines(withPrompt(stat,prompt)); f:lines(withPrompt(info,prompt)); f:lines(withPrompt(religion,prompt))
    f:lines(withPrompt(playerRunes,prompt)); f:lines(withPrompt(skills,prompt)); f:lines(withPrompt(time,prompt))
    eq(c.snapshot.inventory,applied); assertPlayerInventory(c.snapshot.inventory)
    eq(table.concat(f.sent,","),"inventory,stat,info,info religion,info magic,skill,time")
    eq(c.active,nil); eq(c.sequence_index,nil); c:shutdown(); eq(f:owned(),0)
  end)
  test("manual collector retains six logged runes through look and "..case.name.." prompt interleaving",function()
    local f=fake(); local applied; local changes=0
    local c=Collector.new(f,Parser,function(snapshot,key,parsed)
      if key=="runes" then changes=changes+1; applied=parsed; eq(snapshot.runes,parsed) end
    end); assert(c:start()); f:outgoing("info magic"); local active=c.active
    f:line(prompt); eq(c.active,active); eq(changes,0)
    f:outgoing("l"); eq(c.active,active)
    local response=withPrompt(playerRunes,prompt)
    for index=1,#response-1 do f:line(response[index]) end
    eq(c.active,active); eq(c.snapshot.runes,nil); eq(changes,0)
    f:line(response[#response]); eq(changes,1); assertPlayerRunes(applied); eq(c.active,nil)
    f:line(prompt); f:outgoing("skill"); f:line(prompt); f:lines(withPrompt(skills,prompt))
    eq(changes,1); eq(c.snapshot.runes,applied); assertPlayerRunes(c.snapshot.runes)
    eq(#c.snapshot.skills.items,2); eq(#f.sent,0); c:shutdown(); eq(f:owned(),0)
  end)
  test("startup collector retains six logged runes through look and "..case.name.." prompt interleaving",function()
    local f=fake(); local changes=0; local applied
    local c=Collector.new(f,Parser,function(snapshot,key)
      if key=="runes" then changes=changes+1; applied=snapshot.runes end
    end); assert(c:start()); f:line("Welcome to Dragon's Gate, Test!")
    f:lines(withPrompt(playerInventory,prompt)); f:lines(withPrompt(stat,prompt))
    f:lines(withPrompt(info,prompt)); f:lines(withPrompt(religion,prompt))
    eq(c.active.command,"info magic"); eq(f.sent[5],"info magic"); local active=c.active
    f:line(prompt); eq(c.active,active); eq(changes,0)
    f:outgoing("l"); eq(c.active,active)
    local response=withPrompt(playerRunes,prompt)
    for index=1,#response-1 do f:line(response[index]) end
    eq(c.active,active); eq(c.snapshot.runes,nil); eq(changes,0)
    f:line(response[#response]); eq(changes,1); assertPlayerRunes(applied)
    eq(c.active.command,"skill"); eq(f.sent[6],"skill")
    f:line(prompt); f:lines(withPrompt(skills,prompt)); f:lines(withPrompt(time,prompt))
    eq(changes,1); eq(c.snapshot.runes,applied); assertPlayerRunes(c.snapshot.runes)
    assertPlayerInventory(c.snapshot.inventory)
    eq(table.concat(f.sent,","),"inventory,stat,info,info religion,info magic,skill,time")
    eq(c.active,nil); eq(c.sequence_index,nil); c:shutdown(); eq(f:owned(),0)
  end)
end

-- Bounded October 8 startup output; local command echoes and private log data
-- are excluded. The interleaved look is represented by synthetic room text.
local octoberStartupRunes={"","You have the following elemental runes available to you...","",
  "   force       - 100 weaves remain   heal        -  99 weaves remain",
  "   holy        - 100 weaves remain   vigor       - 100 weaves remain",
  "   light       - 100 weaves remain   purify      - 100 weaves remain",
  "   strength    - 100 weaves remain   translocation - 100 weaves remain",
  "   death       - 100 weaves remain   aegis       - 100 weaves remain",""}
local octoberStartupSkills={"","Skill                     Remain Level",
  " First Aid                 481    5",
  "*Spellcasting              0      5",
  " Channeling                149    5",
  "*Piercing Weapons          0      5",
  "*Sharp Weapons             0      5",
  "*Blunt Weapons             0      5",
  "*Missile Weapons           0      5",
  "*Thrown Weapons            0      5",
  "*Brawling                  0      5",
  "*Quickdraw                 0      5",
  " Shield Use                424    5",
  "*Hiding                    0      5",
  " Stealth                   100    1",
  " Bargaining                510    5",
  " Disarming                 194    2",
  " Swimming                  134    5",
  " Play Instruments          550    5",
  " Identify Magick           154    5",
  "*Identify Gems/Minerals    0      5",
  " Identify Weapon Quality   526    5",
  " Identify Armor Quality    550    5",
  " Detect Traps              100    1",""}
local function assertOctoberStartupRunes(parsed)
  local expected={{"Heal",99},{"Aegis",100},{"Death",100},{"Force",100},{"Holy",100},
    {"Light",100},{"Purify",100},{"Strength",100},{"Translocation",100},{"Vigor",100}}
  eq(#parsed.items,10)
  for index,rune in ipairs(expected) do
    eq(parsed.items[index].name,rune[1]); eq(parsed.items[index].remaining,rune[2])
  end
end
for _,case in ipairs({{name="plain",prompt=">"},{name="vitals",prompt="[199] 301/301 hp, 173/173 ftg >"}}) do
  test("startup retains all ten October 8 runes through prompt nudges skill and time with "..case.name.." prompt",function()
    local f=fake(); local prompt=case.prompt; local applied; local runeChanges=0
    local send=f.sendCommand
    function f:sendCommand(command) send(self,command); self:outgoing(command) end
    local c=Collector.new(f,Parser,function(snapshot,key)
      if key=="runes" then runeChanges=runeChanges+1; applied=snapshot.runes end
    end); assert(c:start()); f:line("Welcome to Dragon's Gate, SyntheticTester!")
    local syntheticInfo={}; for index,line in ipairs(info) do syntheticInfo[index]=line:gsub("Test Tester","SyntheticTester") end
    for _,response in ipairs({{command="inventory",lines=inventory},{command="stat",lines=stat},
        {command="info",lines=syntheticInfo},{command="info religion",lines=religion}}) do
      eq(c.active.command,response.command); eq(f:fireDelay(.15),true); eq(f.sent[#f.sent],"")
      eq(f:fireDelay(.15),false); f:lines(withPrompt(response.lines,prompt))
    end
    eq(c.active.command,"info magic"); local active=c.active
    eq(f:fireDelay(.15),true); eq(f.sent[#f.sent],""); eq(f:fireDelay(.15),false)
    f:line(prompt); f:lines(octoberStartupRunes)
    eq(c.active,active); eq(c.snapshot.runes,nil); eq(runeChanges,0)
    f:outgoing("l"); f:lines({"Synthetic room output from an interleaved look.",""})
    eq(c.active,active); f:line(prompt)
    eq(runeChanges,1); assertOctoberStartupRunes(applied); eq(c.active.command,"skill")
    eq(f:fireDelay(.15),false); f:lines(octoberStartupSkills)
    eq(c.active.command,"skill"); eq(c.snapshot.skills,nil); eq(c.snapshot.runes,applied)
    eq(f:fireDelay(0),true); eq(c.active.command,"time"); eq(#c.snapshot.skills.items,22)
    eq(runeChanges,1); eq(c.snapshot.runes,applied); assertOctoberStartupRunes(c.snapshot.runes)
    eq(f:fireDelay(.15),false); f:line(prompt)
    f:lines({"","Server local time is: Thu Oct  8 12:20:18 2026 (pacific).","",
      "Today is the 46th day of Mateth in the year 362. The time is 2:42.","",
      "You have been adventuring for 1 sec this session.","",prompt})
    eq(c.snapshot.time.hour,2); eq(c.snapshot.time.minute,42); eq(c.snapshot.time.day,46)
    eq(c.snapshot.time.month_name,"Mateth"); eq(runeChanges,1); eq(c.snapshot.runes,applied)
    assertOctoberStartupRunes(c.snapshot.runes)
    eq(table.concat(f.sent,","),"inventory,,stat,,info,,info religion,,info magic,,skill,time")
    eq(c.active,nil); eq(c.sequence_index,nil); c:shutdown(); eq(f:owned(),0)
  end)
end

test("INFO rank refresh removes stale MP and stale numeric values",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); assert(c:start())
  local header="Str Int Wis Dex Agi Con Cha Wil Pre Per Luk"
  local ranks="Awful Poor Low Aver Fair Good Great Excel Super Godly Fair"
  f:outgoing("info"); f:lines({header.." MP",ranks.." Superb","1 2 3 4 5 6 7 8 9 10 11 12",">"})
  eq(c.snapshot.info.attributes.MP,"Superb"); eq(c.snapshot.info.attribute_values.MP,12)
  f:outgoing("info"); f:lines({"HP: 200 of 201",">"})
  eq(c.snapshot.info.attribute_values.MP,12); eq(c.snapshot.info.attributes.MP,"Superb")
  f:outgoing("info"); f:lines({header,ranks,">"})
  eq(c.snapshot.info.attributes.MP,nil); eq(c.snapshot.info.attribute_values.MP,nil); eq(next(c.snapshot.info.attribute_values),nil)
  f:outgoing("info"); f:lines({header,ranks,"11 12 13 14 15 16 17 18 19 20 21",">"})
  eq(c.snapshot.info.attribute_values.LUK,21); eq(c.snapshot.info.attribute_values.MP,nil)
end)
test("updated info replaces old characteristic names without losing physical details",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("info"); f:lines(info)
  eq(c.snapshot.info.attributes.VOI,"Aver"); eq(c.snapshot.info.physical.age,28)
  f:outgoing("info"); f:lines({"Str Int Wis Dex Agi Con Cha Wil Pre Per Luk",
    "Great Great Great Great Great Great Great Great Fair Good Low",">"})
  eq(c.snapshot.info.physical.age,28); eq(c.snapshot.info.attributes.PRE,"Fair")
  eq(c.snapshot.info.attributes.LUK,"Low"); eq(c.snapshot.info.attributes.VOI,nil); eq(c.snapshot.info.attributes.APP,nil)
end)
test("INFO callbacks distinguish empty completed conditions from absent partial deltas",function()
  local f=fake(); local deltas={}; local n=require("needs_tracker").new({epoch=function() return 10 end})
  local c=Collector.new(f,Parser,function(_,key,parsed)
    if key=="info" then deltas[#deltas+1]=parsed; n:onInfo(parsed) end
  end); assert(c:start())
  local biography=[[You are Dace Alterac, a young Monitanian bodied 28 year old Entropic Male young Monitanian. You are 7'0" and weigh 247 lbs.]]
  f:outgoing("info"); f:lines({biography.." You are ravenous. You are parched.",">"})
  eq(n:status().hunger.status,"ravenous"); eq(n:status().thirst.status,"parched")
  f:outgoing("info"); f:line(biography); eq(#deltas,1)
  f:line(">"); eq(#deltas,2); eq(deltas[2].condition_text,"")
  eq(c.snapshot.info.condition_text,""); eq(n:status().hunger.status,"ok"); eq(n:status().thirst.status,"ok")
  n:onLine("You are hungry. You are thirsty.")
  for _,lines in ipairs({
    {"Str Int Wis Dex Agi Con Cha Wil Pre Per Luk","Good Good Good Good Good Good Good Good Good Good Good",">"},
    {"HP: 213 of 213 Ftg: 81 of 81 Carry: 174.4 of 354.0 lbs.",">"},
  }) do
    f:outgoing("info"); f:lines(lines); eq(deltas[#deltas].condition_text,nil)
    eq(c.snapshot.info.character.full_name,"Dace Alterac"); eq(c.snapshot.info.condition_text,"")
    eq(n:status().hunger.status,"hungry"); eq(n:status().thirst.status,"thirsty")
  end
  c:shutdown(); eq(f:owned(),0)
end)
test("collector exposes only the newly parsed wrapped info payload to callbacks",function()
  local f=fake(); local delta; local c=Collector.new(f,Parser,function(_,key,parsed) if key=="info" then delta=parsed end end); c:start(); f:outgoing("info")
  f:lines({"You are Deklan Marrowen, a skinny bodied 21 year old Entropic Male 1st stage Dragon. You are 7'6\" and weigh 292 lbs. You are hungry. You are","thirsty.","HP: 213 of 213 Ftg: 81 of 81 Carry: 174.4 of 354.0 lbs.","Str Int Wis Dex Agi Con Cha Wil Voi Per App","Godly Super Excel Super Super Super Super Super Super Super Super",">"})
  eq(delta.condition_text,"You are hungry. You are thirsty."); eq(delta.vitals.carry,174.4); eq(c.snapshot.info.attributes.STR,"Godly")
end)
test("collector ignores a stale prompt until wrapped INFO reaches its terminal prompt",function()
  local f=fake(); local changes=0; local c=Collector.new(f,Parser,function(_,key) if key=="info" then changes=changes+1 end end); c:start(); f:outgoing("info")
  f:lines({">","You are Deklan Marrowen, a skinny bodied 21 year old Entropic Male 1st stage Dragon. You are 7'6\" and weigh 292 lbs.","Str Int Wis Dex Agi Con Cha Wil Voi Per App","Godly Super Excel Super Super Super Super Super Super Super Super"})
  eq(changes,0); eq(c.active.command,"info"); f:line(">"); eq(changes,1); eq(c.snapshot.info.attributes.APP,"Super")
end)
test("collector treats inv as a manual inventory command",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("inv"); f:lines(inventory); eq(c.snapshot.inventory.total_weight,1)
end)
test("collector reports explicit game delay lines",function()
  local f=fake(); local delay; local c=Collector.new(f,Parser,function() end,function(value) delay=value end); c:start(); f:line("[8 sec. delay]"); eq(delay,8)
end)
test("collector emits every numeric colored delay marker in arrival order with text metadata",function()
  local f=fake(); local delays={}; local sources={}
  local c=Collector.new(f,Parser,function() end,function(value,metadata) delays[#delays+1]=value; sources[#sources+1]=metadata.source end); c:start()
  f:line("\27[32m[8 sec. delay]\27[0m attack [\27[31m2\27[0m sec. delay] [8 sec. delay] [0 sec. delay] [2.5 sec. delay]")
  eq(table.concat(delays,","),"8,2,8,0,2.5"); eq(table.concat(sources,","),"text,text,text,text,text")
  f:line("[bad sec. delay] [-2 sec. delay] [1..2 sec. delay]"); eq(#delays,5); eq(#f.sent,0)
end)
test("multiple delay markers remain compatible with single argument callbacks",function()
  local f=fake(); local delays={}; local c=Collector.new(f,Parser,function() end,function(value) delays[#delays+1]=value end); c:start()
  f:line("[3 sec. delay] [1 sec. delay]"); eq(table.concat(delays,","),"3,1")
end)
test("interrupted STAT retains combat fields immediately when INFO replaces capture",function()
  local f=fake(); local changes={}; local c=Collector.new(f,Parser,function(_,key) changes[#changes+1]=key end); c:start()
  f:outgoing("stat"); f:line(stat[1]); eq(c.snapshot.stat.body_armor,4); f:line(stat[2])
  eq(c.snapshot.stat.or_rating,18); eq(c.snapshot.stat.dr,70); eq(c.snapshot.stat.stance,"Aggressive"); eq(c.active.command,"stat"); eq(#changes,2)
  f:outgoing("info"); f:lines(info); eq(c.snapshot.stat.body_armor,4); eq(c.snapshot.stat.damage_bonus,"Good/None"); eq(c.snapshot.info.physical.age,28)
  f:outgoing("stat"); f:lines({"Body Armor: 8%.",">"})
  eq(c.snapshot.stat.body_armor,8); eq(c.snapshot.stat.or_rating,18); eq(c.snapshot.stat.move.maximum,6); eq(c.snapshot.stat.stance,"Aggressive")
  eq(table.concat(changes,","),"stat,stat,info,stat,stat")
end)
test("partial STAT preserves prior equipment and position while explicitly empty equipment clears",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("stat")
  f:lines({stat[1],stat[2],"You are in the center of the area!","::: Equipment Readied :::","  A spear.",">"})
  local equipment=c.snapshot.stat.equipment; f:outgoing("stat"); f:lines({"DR: 90",">"})
  eq(c.snapshot.stat.dr,90); eq(c.snapshot.stat.or_rating,18); eq(c.snapshot.stat.equipment,equipment); eq(c.snapshot.stat.area_position,"center")
  f:outgoing("stat"); f:lines({"Body Armor: 8%.","::: Equipment Readied :::",">"}); eq(#c.snapshot.stat.equipment,0)
end)
test("startup STAT interrupted by INFO retains every captured combat field and resumes STAT",function()
  local f=fake(); local changes={}; local c=Collector.new(f,Parser,function(_,key) changes[#changes+1]=key end); c:start()
  f:line("Welcome to Dragon's Gate, Test!"); f:lines(inventory); eq(c.active.command,"stat")
  f:lines({stat[1],stat[2],"You are in the center of the area!","You are still protected by the 80 hour novice protection."})
  eq(c.snapshot.stat.area_position,"center"); eq(c.snapshot.stat.novice_protected,true)
  f:outgoing("info"); f:lines(info); eq(c.active.command,"stat"); eq(f.sent[3],"stat")
  eq(c.snapshot.stat.or_rating,18); eq(c.snapshot.stat.stance,"Aggressive"); eq(c.snapshot.stat.equipment,nil)
  f:lines({"Body Armor: 8%.",">"}); eq(c.active.command,"info"); eq(c.snapshot.stat.body_armor,8); eq(c.snapshot.stat.dr,70)
  eq(c.snapshot.stat.area_position,"center"); eq(c.snapshot.stat.novice_protected,true)
  eq(table.concat(changes,","),"reset,inventory,stat,stat,stat,stat,info,stat,stat")
end)
test("incremental STAT notifies before a prompt with changed fields only and no equal movement spam",function()
  local f=fake(); local deltas={}; local c; c=Collector.new(f,Parser,function(snapshot,key,delta)
    eq(key,"stat"); eq(snapshot,c.snapshot); deltas[#deltas+1]=delta
  end)
  local equipment={"A spear"}; c.snapshot.stat={body_armor=4,equipment=equipment,area_position="center"}; c:start(); f:outgoing("stat")
  local line="\27[36m> OR: 25 DR: 115 Move Rate: 3/6 UDs Dam Bonus: Good/None Stance: Frenzied\27[0m"
  f:line(line); eq(#deltas,1); eq(c.active.command,"stat"); eq(deltas[1].or_rating,25); eq(deltas[1].dr,115); eq(deltas[1].stance,"Frenzied")
  eq(deltas[1].move.current,3); eq(deltas[1].move.maximum,6); eq(deltas[1].body_armor,nil); eq(deltas[1].equipment,nil); eq(deltas[1].area_position,nil)
  local move=c.snapshot.stat.move; f:line(line); f:line("Move Rate: 3/6 UDs"); eq(#deltas,1); eq(c.snapshot.stat.move,move)
  f:line("DR: 116"); eq(#deltas,2); eq(deltas[2].dr,116); eq(deltas[2].or_rating,nil); eq(deltas[2].stance,nil); eq(deltas[2].move,nil)
  f:line(">"); eq(#deltas,3); eq(c.active,nil); eq(c.snapshot.stat.equipment,equipment)
  f:outgoing("stat"); f:line("DR: 116"); eq(#deltas,3); f:line(">"); eq(#deltas,4)
  eq(deltas[4].dr,116); eq(deltas[4].or_rating,nil); eq(deltas[4].stance,nil); eq(deltas[4].equipment,nil)
end)
test("movement changes compare current and maximum numerically",function()
  local f=fake(); local deltas={}; local c=Collector.new(f,Parser,function(_,_,delta) deltas[#deltas+1]=delta end); c:start()
  c.snapshot.stat={move={current="3",maximum="6"}}; f:outgoing("stat"); f:line("Move Rate: 3/6 UDs"); eq(#deltas,0)
  f:line("Move Rate: 2/6 UDs"); eq(#deltas,1); eq(deltas[1].move.current,2); eq(deltas[1].move.maximum,6)
  f:line("Move Rate: 2/7 UDs"); eq(#deltas,2); eq(deltas[2].move.maximum,7)
end)
test("completed STAT retains equipment through blank header lines and rejects interleaved NPC output",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("stat")
  f:lines({stat[1],stat[2],"::: Equipment Readied :::","","  \27[0m","  A spear.","","  A shield.",
    "A goblin stands up.","  A goblin draws a sword.",">"})
  eq(#c.snapshot.stat.equipment,2); eq(c.snapshot.stat.equipment[1],"A spear"); eq(c.snapshot.stat.equipment[2],"A shield"); eq(c.snapshot.stat.standing,nil)
  f:outgoing("stat"); f:lines({"DR: 81", "A goblin says: ::: Equipment Readied :::", "  A goblin draws a sword.",">"})
  eq(#c.snapshot.stat.equipment,2); eq(c.snapshot.stat.equipment[2],"A shield")
end)
test("STAT without a prompt captures wrapped combat fields through timeout and INFO interruption",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("stat")
  f:lines({"\27[36m> OR: 25 DR: 115\27[0m","Move Rate: 3/","6 UDs Dam Bonus: Good/","None Stance:","Frenzied"})
  eq(c.snapshot.stat.or_rating,25); eq(c.snapshot.stat.dr,115); eq(c.snapshot.stat.move.current,3); eq(c.snapshot.stat.move.maximum,6)
  eq(c.snapshot.stat.damage_bonus,"Good/None"); eq(c.snapshot.stat.stance,"Frenzied"); eq(c.active.command,"stat")
  assert(f:fireDelay(2)); assert(f:fireDelay(2)); assert(f:fireDelay(.5)); eq(c.active,nil); eq(c.snapshot.stat.dr,115)
  f:outgoing("info"); f:lines(info); eq(c.snapshot.stat.stance,"Frenzied")
end)
test("standalone stance updates immediately without changing equipment position or posture",function()
  local f=fake(); local deltas={}; local c=Collector.new(f,Parser,function(snapshot,key,parsed)
    eq(key,"stat"); eq(snapshot.stat.stance,parsed.stance); deltas[#deltas+1]=parsed
  end); c:start()
  local equipment={"A spear"}; c.snapshot.stat={dr=70,equipment=equipment,area_position="center",standing=true}
  f:line("\27[36m[199] 301/301 hp, 173/173 ftg > Attack strategy set to: Frenzied -- Throw caution to the wind.\27[0m")
  eq(c.snapshot.stat.stance,"Frenzied"); eq(#deltas,1); eq(deltas[1].dr,nil); eq(deltas[1].equipment,nil)
  eq(c.snapshot.stat.dr,70); eq(c.snapshot.stat.equipment,equipment); eq(c.snapshot.stat.area_position,"center"); eq(c.snapshot.stat.standing,true)
  f:lines({"Attack strategy set to: Frenzied -- Throw caution to the wind.","A goblin stands up.","  A goblin draws a sword.","A goblin says: Attack strategy set to: Defensive -- Beware!"})
  eq(c.snapshot.stat.stance,"Frenzied"); eq(c.snapshot.stat.equipment,equipment); eq(c.snapshot.stat.standing,true); eq(#deltas,1); eq(#f.sent,0)
end)
test("stance confirmation during another command does not interrupt sequential startup",function()
  local f=fake(); local changes={}; local c=Collector.new(f,Parser,function(_,key) changes[#changes+1]=key end); c:start(); f:line("Welcome to Dragon's Gate, Test!")
  f:line("Attack strategy set to: Frenzied -- Throw caution to the wind."); eq(c.snapshot.stat.stance,"Frenzied"); eq(c.active.command,"inventory"); eq(#f.sent,1)
  f:lines(inventory); eq(c.active.command,"stat"); f:lines(stat); eq(c.active.command,"info")
  f:line("Attack strategy set to: Defensive -- Beware!"); f:lines(info); eq(c.snapshot.stat.stance,"Defensive"); eq(c.active.command,"info religion")
  eq(table.concat(changes,","),"reset,stat,inventory,stat,stat,stat,stat,info")
end)
test("stance confirmation inside STAT survives its completion",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("stat"); f:lines({stat[1],stat[2]})
  f:line("Attack strategy set to: Frenzied -- Throw caution to the wind."); eq(c.snapshot.stat.stance,"Frenzied")
  f:line(">"); eq(c.snapshot.stat.stance,"Frenzied"); eq(c.snapshot.stat.dr,70); eq(c.active,nil)
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
test("collector stale timeout ownership survives cancellation and later captures in every timeout stage",function()
  for _,stage in ipairs({"initial","recovery","drain"}) do
    for _,action in ipairs({"command","disconnect","restart","shutdown"}) do
      local f=fake(); local changes=0
      local c=Collector.new(f,Parser,function() changes=changes+1 end); assert(c:start()); f:outgoing("skill")
      if stage~="initial" then assert(f:fireDelay(3)) end
      if stage=="drain" then assert(f:fireDelay(3)) end
      eq(c.active.timeout_stage,stage)
      local retiredActive,retiredTimer=c.active,c.timeout; local late=assert(f.timers[retiredTimer])
      if action=="command" then f:outgoing("skill")
      elseif action=="disconnect" then f:disconnect(); f:outgoing("skill")
      elseif action=="restart" then assert(c:restartRefresh())
      else assert(c:shutdown()); assert(c:start()); f:outgoing("skill") end
      local active,timer,nudge=c.active,c.timeout,c.prompt_nudge
      local callback=assert(f.timers[timer]); local sent,nextID=#f.sent,f.next
      assert(active~=retiredActive); assert(timer~=retiredTimer); eq(f.timers[retiredTimer],nil)
      late()
      eq(c.active,active); eq(c.timeout,timer); eq(c.prompt_nudge,nudge)
      eq(active.timeout_stage,"initial"); eq(f.timers[timer],callback)
      eq(#f.sent,sent); eq(f.next,nextID); eq(changes,0); eq(next(c.snapshot),nil)
      c:cancelActive(); eq(f.timers[timer],nil)
      if nudge then eq(f.timers[nudge],nil) end
      assert(c:shutdown()); eq(f:owned(),0)
    end
  end
end)
test("collector stale timeout ownership cannot replay earlier stages of the same active capture",function()
  local f=fake(); local changes=0
  local c=Collector.new(f,Parser,function() changes=changes+1 end); assert(c:start()); f:outgoing("skill")
  local active=c.active; local initial=assert(f.timers[c.timeout])
  assert(f:fireDelay(3)); eq(c.active,active); eq(active.timeout_stage,"recovery")
  local recoveryTimer=c.timeout; local recovery=assert(f.timers[recoveryTimer]); local nextID=f.next
  initial()
  eq(c.active,active); eq(c.timeout,recoveryTimer); eq(active.timeout_stage,"recovery")
  eq(f.timers[recoveryTimer],recovery); eq(f.next,nextID); eq(#f.sent,0); eq(changes,0)
  assert(f:fireDelay(3)); eq(c.active,active); eq(active.timeout_stage,"drain")
  local drainTimer=c.timeout; local drain=assert(f.timers[drainTimer]); nextID=f.next
  initial(); recovery()
  eq(c.active,active); eq(c.timeout,drainTimer); eq(active.timeout_stage,"drain")
  eq(f.timers[drainTimer],drain); eq(f.next,nextID); eq(#f.sent,0); eq(changes,0)
  assert(f:fireDelay(.5)); eq(c.active,nil); eq(c.timeout,nil)
  initial(); recovery(); drain()
  eq(c.active,nil); eq(c.timeout,nil); eq(#f.sent,0); eq(changes,0)
  assert(c:shutdown()); eq(f:owned(),0)
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
  f:lines({"Use: INFO <subject> for more info.",">","You are a Novitiate follower of Unknown.","You are Balanced within your Entropic alignment.",">"}); eq(c.active.command,"info magic")
  f:lines(runes); eq(c.active.command,"skill")
  f:lines({">","Skill                     Remain Level","Biting                    105    4","Clawing                   276    2",">"}); eq(c.active.command,"time"); eq(#c.snapshot.skills.items,2)
  f:lines(time); eq(c.snapshot.time.minute,22); eq(table.concat(changes,","),"reset,inventory,stat,stat,stat,info,religion,runes,skills,time")
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
test("returning to the account menu ends character activity and cancels collection",function()
  local f=fake(); local exits=0; local c=Collector.new(f,Parser,function() end,nil,function() end,function() exits=exits+1 end); c:start()
  f:line("Welcome to Dragon's Gate, Test!"); eq(c.active_character,"Test"); assert(c:refresh()); eq(c.active.command,"inventory")
  f:line("    Dragon's Gate Menu"); eq(c.active_character,nil); eq(c.active,nil); eq(c.refreshed,false); eq(exits,1)
end)
