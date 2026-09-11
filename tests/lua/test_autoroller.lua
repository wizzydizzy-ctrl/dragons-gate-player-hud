local Roller=require("autoroller")
local function fake()
  local f={messages={},sent={},timers={},next=0}
  function f:reportRoller(value) self.messages[#self.messages+1]=value end
  function f:schedule(delay,fn) self.next=self.next+1; self.timers[self.next]={delay=delay,fn=fn}; return self.next end
  function f:cancelTimer(id) self.timers[id]=nil end
  function f:sendCommand(value) self.sent[#self.sent+1]=value end
  return f
end
local legacyHeader=" Str   Int   Wis   Dex   Agi   Con   Cha   Wil   Voi   Per   App"
local legacyPrompt="Use this body ? Y,n"
local firstHeader="  STR         INT         WIS         DEX         AGI         CON"
local secondHeader="  CHA         WIL         VOI         PER         APP         MP"
local creatorPrompt="reroll  done  ? help"
local arrangePrompt="<stat> <label>  auto  clear  reroll  done  ? help"
local function poolLine(labels) return #labels==0 and "Pool: (empty)" or "Pool: "..table.concat(labels," ") end
local function removeLabel(labels,label)
  for index,value in ipairs(labels) do if value:lower()==label:lower() then table.remove(labels,index); return true end end
  return false
end
local function newRoll(r,first,second)
  assert(r:onLine(firstHeader)); assert(r:onLine(first)); r:onLine(""); assert(r:onLine(secondHeader)); assert(r:onLine(second))
end

test("new creator buffers twelve ranks and auto-starts only at its decision prompt",function()
  local f=fake(); local r=Roller.new(f,{target_total=84,reroll_delay=.5,auto_start_on_name=true})
  newRoll(r,"Great Great Great Great Great Great","Great Great Great Great Great Great")
  eq(r.state.active,false); eq(r.state.rolls,0); eq(r:onLine("Fit for a RuneMage: Great    primes: INT WIL MP"),false); eq(r.state.active,false)
  assert(r:onLine(creatorPrompt)); eq(r.state.active,false); eq(r.state.rolls,1); eq(r.state.last.total,84); eq(r.state.last.maximum,84); eq(r.state.last.stats.MP,7); eq(#f.sent,0)
  assert(f.messages[#f.messages-1]:find("manual done",1,true)); assert(f.messages[#f.messages]:find("MP 7",1,true))
end)

test("new creator accepts every rank from Awful through Great",function()
  local f=fake(); local r=Roller.new(f,{target_total=84,reroll_delay=0,auto_start_on_name=true})
  newRoll(r,"Awful Poor Low Aver Fair Good","Great Good Fair Aver Low Poor")
  assert(r:onLine(creatorPrompt)); eq(r.state.last.total,48); eq(r.state.last.stats.STR,1); eq(r.state.last.stats.MP,2)
  f.timers[1].fn(); eq(f.sent[1],"reroll")
end)

test("new creator requires the exact decision prompt before taking control",function()
  local f=fake(); local r=Roller.new(f,{target_total=84,auto_start_on_name=true})
  newRoll(r,"Great Great Great Great Great Great","Great Great Great Great Great Great")
  eq(r:onLine([[A guide says, "reroll done ? help"]]),false); eq(r.state.active,false); eq(r.state.rolls,0)
  assert(r:onLine(">  reroll  done  ? help")); eq(r.state.last.total,84); eq(r.state.active,false)
end)

test("an abandoned passive creator capture expires before a later prompt",function()
  local r=Roller.new(fake(),{target_total=84,auto_start_on_name=true})
  newRoll(r,"Great Great Great Great Great Great","Great Great Great Great Great Great")
  for index=1,9 do r:onLine("unrelated line "..index) end
  eq(r.state.pending_stats,nil); eq(r:onLine(creatorPrompt),false); eq(r.state.rolls,0); eq(r.state.active,false)
end)

test("new creator sends reroll once for a rejected split roll",function()
  local f=fake(); local r=Roller.new(f,{target_total=61,reroll_delay=.25,auto_start_on_name=true})
  newRoll(r,"Low Good Good Great Great Low","Fair Fair Good Aver Aver Aver")
  assert(r:onLine(creatorPrompt)); eq(r.state.active,true); eq(r.state.last.total,60); eq(f.timers[1].delay,.25); eq(#f.sent,0)
  eq(r:onLine(creatorPrompt),false); eq(f.next,1); f.timers[1].fn(); eq(f.sent[1],"reroll")
  r:onLine("> reroll"); r:onLine("reroll"); r:onLine(">"); eq(r.state.rolls,1); eq(#f.sent,1)
end)

test("new prompt honors MP minimum and leaves done waiting",function()
  local f=fake(); local r=Roller.new(f,{target_total=50,reroll_delay=0,auto_start_on_name=true,use_min_stats=true,require_min_stats_to_stop=true,min_stats={MP=5}})
  newRoll(r,"Great Great Great Great Great Great","Great Great Great Great Great Aver")
  assert(r:onLine(creatorPrompt)); f.timers[1].fn(); eq(f.sent[1],"reroll"); eq(r.state.active,true)
  newRoll(r,"Good Good Good Good Good Good","Good Good Good Good Good Fair")
  assert(r:onLine(creatorPrompt)); eq(r.state.active,false); eq(#f.sent,1); eq(r.state.last.stats.MP,5)
end)

test("new totals validate through 84 and include MP settings",function()
  local r=Roller.new(fake(),{target_total=53,min_stats={}})
  assert(r:command("set total 84")); eq(r.cfg.target_total,84)
  local ok,err=r:command("set total 85"); eq(ok,nil); assert(err:find("invalid",1,true)); eq(r.cfg.target_total,84)
  assert(r:command("set MP 7")); eq(r.cfg.min_stats.MP,7); eq(r.cfg.use_min_stats,true)
  ok,err=r:command("set MP 8"); eq(ok,nil); assert(err:find("1%-7"))
end)

test("malformed or incomplete new rows never reuse a previous roll",function()
  local f=fake(); local r=Roller.new(f,{target_total=84,reroll_delay=0,auto_start_on_name=true})
  newRoll(r,"Great Great Great Great Great Great","Great Great Great Great Great Great"); assert(r:onLine(creatorPrompt)); eq(r.state.rolls,1)
  assert(r:onLine("> reroll"))
  assert(r:onLine(firstHeader)); eq(r:onLine("Low Low Low"),false); eq(r:onLine(secondHeader),false); eq(r:onLine("Low Low Low Low Low Low"),false); eq(r:onLine(creatorPrompt),false); eq(r.state.rolls,1); eq(#f.sent,0)
  r:onLine("That set was too weak to offer -- rolling again."); r:onLine("Fit for a RuneMage: Poor primes: INT WIL MP"); eq(r.state.rolls,1)
end)

test("auto-start can be disabled for the new creator",function()
  local r=Roller.new(fake(),{target_total=60,auto_start_on_name=false})
  eq(r:onLine(firstHeader),false); eq(r:onLine("Great Great Great Great Great Great"),false); eq(r:onLine(secondHeader),false); eq(r:onLine("Great Great Great Great Great Great"),false); eq(r:onLine(creatorPrompt),false); eq(r.state.active,false); eq(r.state.rolls,0)
end)

test("new creator accepts ANSI-colored headers values and prompt",function()
  local f=fake(); local r=Roller.new(f,{target_total=84,auto_start_on_name=true})
  assert(r:onLine("\27[36mSTR INT WIS DEX AGI CON\27[0m")); assert(r:onLine("\27[32mGreat Great Great Great Great Great\27[0m")); assert(r:onLine("\27[36mCHA WIL VOI PER APP MP\27[0m")); assert(r:onLine("\27[32mGreat Great Great Great Great Great\27[0m"))
  assert(r:onLine("\27[33mreroll  done  ? help\27[0m")); eq(r.state.last.total,84); eq(r.state.active,false); eq(#f.sent,0)
end)

test("a manually requested next roll cancels a stale scheduled reroll",function()
  local f=fake(); local r=Roller.new(f,{target_total=70,reroll_delay=1,auto_start_on_name=false}); assert(r:start())
  newRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low Low"); assert(r:onLine(creatorPrompt)); eq(f.timers[1]~=nil,true)
  assert(r:onOutgoing("reroll")); assert(r:onLine(firstHeader)); eq(f.timers[1],nil); eq(r.state.timer,nil)
end)

test("manual done cancels the first auto-started reroll including stale callbacks",function()
  local f=fake(); local r=Roller.new(f,{target_total=70,reroll_delay=1,auto_start_on_name=true})
  newRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low Low"); assert(r:onLine(creatorPrompt)); local stale=f.timers[1].fn
  assert(r:onLine("> done")); eq(r.state.active,false); eq(r.state.timer,nil); stale(); eq(#f.sent,0)
end)

test("manual reroll cancels a queued automatic reroll including stale callbacks",function()
  local f=fake(); local r=Roller.new(f,{target_total=70,reroll_delay=1,auto_start_on_name=true})
  newRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low Low"); assert(r:onLine(creatorPrompt)); local stale=f.timers[1].fn
  assert(r:onLine("> reroll")); eq(r.state.active,true); eq(r.state.timer,nil); stale(); eq(#f.sent,0)
  newRoll(r,"Great Great Great Great Great Great","Great Great Great Great Great Great"); assert(r:onLine(creatorPrompt)); eq(r.state.active,false); eq(r.state.rolls,2)
end)

test("stale timer generations remain invalid after stopping and restarting",function()
  local f=fake(); local r=Roller.new(f,{target_total=70,reroll_delay=1,auto_start_on_name=false}); assert(r:start())
  newRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low Low"); assert(r:onLine(creatorPrompt)); local stale=f.timers[1].fn
  assert(r:command("stop")); assert(r:command("start")); newRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low Low"); assert(r:onLine(creatorPrompt)); local current
  for _,timer in pairs(f.timers) do current=timer.fn end
  stale(); eq(#f.sent,0); current(); eq(#f.sent,1); eq(f.sent[1],"reroll")
end)

test("manual stop clears a partial roll and suppresses automatic restart",function()
  local f=fake(); local r=Roller.new(f,{target_total=70,auto_start_on_name=true}); assert(r:start())
  assert(r:onLine(firstHeader)); assert(r:onLine("Great Great Great Great Great Great")); assert(r:command("stop"))
  eq(r.state.partial,nil); eq(r.state.protocol,nil); eq(r:onLine(secondHeader),false); eq(r:onLine("Great Great Great Great Great Great"),false); eq(r:onLine(creatorPrompt),false); eq(r.state.rolls,0)
  eq(r:onLine(firstHeader),false); eq(r:onLine("Great Great Great Great Great Great"),false); eq(r:onLine(secondHeader),false); eq(r:onLine("Great Great Great Great Great Great"),false); eq(r:onLine(creatorPrompt),false); eq(r.state.active,false)
  assert(r:command("start")); eq(r.state.active,true)
end)

test("an active or passive first-half capture expires instead of combining later rows",function()
  for _,autoStart in ipairs({false,true}) do
    local f=fake(); local r=Roller.new(f,{target_total=84,auto_start_on_name=autoStart}); if not autoStart then assert(r:start()) end
    assert(r:onLine(firstHeader)); assert(r:onLine("Great Great Great Great Great Great")); for index=1,9 do r:onLine("unrelated line "..index) end
    eq(r.state.partial,nil); r:onLine(secondHeader); r:onLine("Great Great Great Great Great Great"); eq(r:onLine(creatorPrompt),false); eq(r.state.rolls,0)
  end
end)

test("manual start captures the new split layout immediately",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,reroll_delay=0,auto_start_on_name=false}); assert(r:start())
  newRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low Low"); eq(r.state.rolls,1); assert(r:onLine(creatorPrompt)); f.timers[1].fn(); eq(f.sent[1],"reroll")
end)

test("roll and arrange passively captures a pool and leaves manual placement untouched",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,auto_start_on_name=true,use_min_stats=false,arrange_mode="manual"})
  assert(r:onLine("Pool: Great Good Good Good Good Good Fair Fair Aver Low Low Low")); eq(r.state.active,false)
  r:onLine("Fit for a RuneMage: Awful    primes: INT WIL MP")
  assert(r:onLine(arrangePrompt)); eq(r.state.rolls,1); eq(r.state.last.total,60); eq(r.state.active,false); eq(#f.sent,0)
  assert(f.messages[#f.messages-1]:find("pool left waiting",1,true)); assert(f.messages[#f.messages]:find("Pool: Great Good",1,true))
end)

test("roll and arrange rejection sends exactly one reroll",function()
  local f=fake(); local r=Roller.new(f,{target_total=64,reroll_delay=.2,auto_start_on_name=true,use_min_stats=false,arrange_mode="manual"})
  assert(r:onLine("Pool: Great Good Good Good Good Good Fair Fair Aver Low Low Low")); assert(r:onLine(arrangePrompt)); eq(r.state.active,true); eq(f.timers[1].delay,.2)
  eq(r:onLine(arrangePrompt),false); f.timers[1].fn(); eq(#f.sent,1); eq(f.sent[1],"reroll")
end)

test("each reroll transaction counts an identical pool once while redraws count zero",function()
  local offered="Pool: Good Good Good Good Good Good Fair Fair Aver Low Low Low"
  local f=fake(); local r=Roller.new(f,{target_total=84,max_rolls=100,reroll_delay=0,auto_start_on_name=true,use_min_stats=false,arrange_mode="manual"})
  for index=1,41 do
    if index>1 then local pending; for _,timer in pairs(f.timers) do pending=timer end; assert(pending); pending.fn() end
    assert(r:onLine(offered)); assert(r:onLine(arrangePrompt))
  end
  eq(r.state.rolls,41); eq(#f.sent,40); local stale; for _,timer in pairs(f.timers) do stale=timer.fn end
  assert(r:onOutgoing("int good")); stale(); eq(#f.sent,40); eq(r:onLine("Pool: Good Good Good Good Good Fair Fair Aver Low Low Low"),false); eq(r:onLine(offered),false); eq(r.state.rolls,41)
end)

test("partial and malformed pools invalidate a stale passive candidate",function()
  local offered="Pool: Great Good Good Good Good Good Fair Fair Aver Low Low Low"
  for _,replacement in ipairs({"Pool: Good Good Fair","Pool: Good Excellent Fair"}) do
    local r=Roller.new(fake(),{target_total=60,auto_start_on_name=true,use_min_stats=false,arrange_mode="manual"})
    assert(r:onLine(offered)); eq(r:onLine(replacement),false); eq(r:onLine(arrangePrompt),false); eq(r.state.rolls,0)
  end
end)

test("game auto mode assigns a qualifying pool but never sends done",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,auto_start_on_name=true,use_min_stats=false,arrange_mode="game_auto"})
  assert(r:onLine("Pool: Great Good Good Good Good Good Fair Fair Aver Low Low Low")); assert(r:onLine(arrangePrompt)); eq(f.sent[1],"auto"); eq(r.state.active,true)
  r:onLine(firstHeader); r:onLine("Aver Great Great Great Great Good"); r:onLine(secondHeader); r:onLine("Aver Good Low Low Low Good"); r:onLine("Pool: (empty)")
  assert(r:onLine(arrangePrompt)); eq(r.state.active,false); eq(#f.sent,1); eq(f.sent[1],"auto")
end)

test("game auto relies on pool counts rather than promising positional minimums",function()
  local f=fake(); local r=Roller.new(f,{target_total=50,auto_start_on_name=true,use_min_stats=true,require_min_stats_to_stop=true,arrange_mode="game_auto",min_stats={INT=7,WIL=7},minimum_greats=1})
  assert(r:onLine("Pool: Great Good Fair Fair Fair Fair Fair Aver Aver Low Low Poor")); assert(r:onLine(arrangePrompt)); eq(f.sent[1],"auto")
end)

test("minimum mode places configured stats in priority order then auto fills",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,auto_start_on_name=true,use_min_stats=true,require_min_stats_to_stop=true,arrange_mode="minimums",min_stats={INT=7,WIL=6,MP=6}})
  assert(r:onLine("Pool: Great Good Good Good Good Good Fair Fair Aver Low Low Low")); assert(r:onLine(arrangePrompt)); eq(f.sent[1],"int great")
  assert(r:onLine("INT placed: Great.")); assert(r:onLine("Pool: Good Good Good Good Good Fair Fair Aver Low Low Low")); assert(r:onLine(arrangePrompt)); eq(f.sent[2],"wil good")
  assert(r:onLine("WIL placed: Good.")); assert(r:onLine("Pool: Good Good Good Good Fair Fair Aver Low Low Low")); assert(r:onLine(arrangePrompt)); eq(f.sent[3],"mp good")
  assert(r:onLine("MP placed: Good.")); assert(r:onLine("Pool: Good Good Good Fair Fair Aver Low Low Low")); assert(r:onLine(arrangePrompt)); eq(f.sent[4],"auto")
  assert(r:onLine(firstHeader)); assert(r:onLine("Aver Great Great Great Great Good")); assert(r:onLine(secondHeader)); assert(r:onLine("Aver Good Low Low Low Good")); assert(r:onLine("Pool: (empty)"))
  assert(r:onLine(arrangePrompt)); eq(r.state.active,false); eq(#f.sent,4)
  for _,command in ipairs(f.sent) do assert(command~="done") end
end)

test("minimum mode with all stats configured does not send auto into an empty pool",function()
  local f=fake(); local mins={}; for _,name in ipairs(Roller.order) do mins[name]=1 end
  local r=Roller.new(f,{target_total=12,auto_start_on_name=true,use_min_stats=true,arrange_mode="minimums",min_stats=mins})
  assert(r:onLine("Pool: Great Good Good Good Good Good Fair Fair Aver Low Low Low")); assert(r:onLine(arrangePrompt))
  local labels={"Great","Good","Good","Good","Good","Good","Fair","Fair","Aver","Low","Low","Low"}
  for index=1,#Roller.order do local command=f.sent[index]
    local stat,label=command:match("^(%a+)%s+(%a+)$"); assert(stat and label); assert(r:onLine(stat:upper().." placed: "..label:sub(1,1):upper()..label:sub(2).."."))
    assert(removeLabel(labels,label)); assert(r:onLine(poolLine(labels))); assert(r:onLine(arrangePrompt))
  end
  eq(#f.sent,12); eq(r.state.active,false)
end)

test("pool thresholds count Great separately and Good or better together",function()
  local f=fake(); local r=Roller.new(f,{target_total=50,minimum_greats=2,minimum_good_plus=4,auto_start_on_name=true,use_min_stats=false,arrange_mode="manual",reroll_delay=0})
  assert(r:onLine("Pool: Great Good Good Good Fair Fair Fair Aver Aver Low Low Poor")); assert(r:onLine(arrangePrompt)); f.timers[1].fn(); eq(f.sent[1],"reroll")
  r:onLine("> reroll"); assert(r:onLine("Pool: Great Great Good Good Fair Fair Fair Aver Aver Low Low Poor")); assert(r:onLine(arrangePrompt)); eq(r.state.active,false); eq(#f.sent,1)
end)

test("an impossible custom placement rejects normally and hard stop leaves it safe",function()
  local pool="Pool: Great Good Fair Fair Fair Fair Fair Aver Aver Low Low Poor"
  local f=fake(); local r=Roller.new(f,{target_total=50,auto_start_on_name=true,use_min_stats=true,require_min_stats_to_stop=true,arrange_mode="minimums",min_stats={INT=7,WIL=7},reroll_delay=0})
  assert(r:onLine(pool)); assert(r:onLine(arrangePrompt)); f.timers[1].fn(); eq(f.sent[1],"reroll")
  local safe=fake(); local hard=Roller.new(safe,{target_total=50,hard_stop=50,auto_start_on_name=true,use_min_stats=true,arrange_mode="minimums",min_stats={INT=7,WIL=7}})
  assert(hard:onLine(pool)); assert(hard:onLine(arrangePrompt)); eq(hard.state.active,false); eq(#safe.sent,0); assert(safe.messages[#safe.messages-1]:find("cannot be placed",1,true))
end)

test("unconfirmed placement stops instead of sending the rest of the sequence",function()
  local f=fake(); local r=Roller.new(f,{target_total=50,auto_start_on_name=true,use_min_stats=true,arrange_mode="minimums",min_stats={INT=6,WIL=6}})
  assert(r:onLine("Pool: Great Good Good Good Fair Fair Fair Aver Aver Low Low Poor")); assert(r:onLine(arrangePrompt)); eq(#f.sent,1)
  assert(r:onLine(arrangePrompt)); eq(r.state.active,false); eq(#f.sent,1); assert(f.messages[#f.messages]:find("Placement was not fully confirmed",1,true))
end)

test("manual result remains held through clear redraws until an explicit reroll",function()
  local offered="Pool: Great Good Good Good Good Good Fair Fair Aver Low Low Low"
  local f=fake(); local r=Roller.new(f,{target_total=60,auto_start_on_name=true,use_min_stats=false,arrange_mode="manual"})
  assert(r:onLine(offered)); assert(r:onLine(arrangePrompt)); eq(r.state.rolls,1); eq(r.state.result_held,true)
  eq(r:onLine("> clear"),false); eq(r:onLine(offered),false); eq(r:onLine(arrangePrompt),false); eq(r.state.rolls,1); eq(#f.sent,0)
  assert(r:onOutgoing("reroll")); assert(r:onLine(offered)); assert(r:onLine(arrangePrompt)); eq(r.state.rolls,2); eq(#f.sent,0)
end)

test("any player command cancels a queued reroll and invalidates its callback",function()
  local f=fake(); local r=Roller.new(f,{target_total=70,reroll_delay=1,auto_start_on_name=true,use_min_stats=false,arrange_mode="manual"})
  assert(r:onLine("Pool: Good Good Good Good Good Good Fair Fair Aver Low Low Low")); assert(r:onLine(arrangePrompt)); local stale=f.timers[1].fn
  assert(r:onOutgoing("auto")); eq(r.state.active,false); eq(r.state.result_held,true); stale(); eq(#f.sent,0)
end)

test("HUD-owned outgoing commands do not cancel their own transaction",function()
  local f=fake(); local r
  function f:sendCommand(value) self.sent[#self.sent+1]=value; r:onOutgoing(value) end
  r=Roller.new(f,{target_total=70,reroll_delay=0,auto_start_on_name=true,use_min_stats=false,arrange_mode="game_auto"})
  assert(r:onLine("Pool: Good Good Good Good Good Good Fair Fair Aver Low Low Low")); assert(r:onLine(arrangePrompt)); f.timers[1].fn()
  eq(f.sent[1],"reroll"); eq(r.state.active,true); eq(r.state.phase,"waiting_new_roll")
  assert(r:onLine("Pool: Great Great Great Great Great Great Great Great Great Great Great Great")); assert(r:onLine(arrangePrompt)); eq(f.sent[2],"auto"); eq(r.state.active,true); eq(r.state.phase,"assigning")
end)

test("automatic placement requires both a complete board and an empty pool",function()
  local offered="Pool: Great Good Good Good Good Good Fair Fair Aver Low Low Low"
  local f=fake(); local r=Roller.new(f,{target_total=60,auto_start_on_name=true,use_min_stats=false,arrange_mode="game_auto"})
  assert(r:onLine(offered)); assert(r:onLine(arrangePrompt)); eq(f.sent[1],"auto")
  assert(r:onLine("Pool: (empty)")); assert(r:onLine(arrangePrompt)); eq(r.state.active,false); eq(r.state.result_held,true); eq(#f.sent,1)
  assert(f.messages[#f.messages]:find("not fully confirmed",1,true))
end)

test("completed automatic placement stays held through clear and full-pool redraws",function()
  local offered="Pool: Great Good Good Good Good Good Fair Fair Aver Low Low Low"
  local f=fake(); local r=Roller.new(f,{target_total=60,auto_start_on_name=true,use_min_stats=false,arrange_mode="game_auto"})
  assert(r:onLine(offered)); assert(r:onLine(arrangePrompt)); assert(r:onLine(firstHeader)); assert(r:onLine("Aver Great Great Great Great Good")); assert(r:onLine(secondHeader)); assert(r:onLine("Aver Good Low Low Low Good")); assert(r:onLine("Pool: (empty)")); assert(r:onLine(arrangePrompt))
  eq(r.state.result_held,true); eq(#f.sent,1); eq(r:onLine("> clear"),false); eq(r:onLine(offered),false); eq(r:onLine(arrangePrompt),false); eq(#f.sent,1); eq(r.state.rolls,1)
end)

test("minimum placement requires its matching pool decrement",function()
  local f=fake(); local r=Roller.new(f,{target_total=50,auto_start_on_name=true,use_min_stats=true,arrange_mode="minimums",min_stats={INT=6}})
  assert(r:onLine("Pool: Great Good Good Good Fair Fair Fair Aver Aver Low Low Poor")); assert(r:onLine(arrangePrompt)); eq(f.sent[1],"int great")
  assert(r:onLine("INT placed: Great.")); assert(r:onLine(arrangePrompt)); eq(r.state.active,false); eq(#f.sent,1); assert(f.messages[#f.messages]:find("not fully confirmed",1,true))
end)

test("minimum placement rejects a same-size pool with the wrong rank removed",function()
  local f=fake(); local r=Roller.new(f,{target_total=50,auto_start_on_name=true,use_min_stats=true,arrange_mode="minimums",min_stats={INT=6,WIL=6}})
  assert(r:onLine("Pool: Great Good Good Good Fair Fair Fair Aver Aver Low Low Poor")); assert(r:onLine(arrangePrompt)); eq(f.sent[1],"int great")
  assert(r:onLine("INT placed: Great.")); assert(r:onLine("Pool: Great Good Good Good Fair Fair Fair Aver Aver Low Low")); assert(r:onLine(arrangePrompt))
  eq(r.state.active,false); eq(#f.sent,1); assert(f.messages[#f.messages]:find("not fully confirmed",1,true))
end)

test("roll and arrange settings validate modes and pool counts",function()
  local r=Roller.new(fake(),{target_total=53,min_stats={}})
  assert(r:command("set arrange auto")); eq(r.cfg.arrange_mode,"game_auto")
  assert(r:command("set arrange minimums")); eq(r.cfg.arrange_mode,"minimums")
  assert(r:command("set greats 3")); eq(r.cfg.minimum_greats,3)
  assert(r:command("set goodplus 6")); eq(r.cfg.minimum_good_plus,6)
  local ok,err=r:command("set greats 13"); eq(ok,nil); assert(err:find("invalid",1,true))
  ok,err=r:command("set arrange unsafe"); eq(ok,nil); assert(err:find("arrange mode",1,true))
end)

test("ANSI roll and arrange pool and prompt are accepted",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,auto_start_on_name=true,use_min_stats=false,arrange_mode="game_auto"})
  assert(r:onLine("\27[32mPool: Great Good Good Good Good Good Fair Fair Aver Low Low Low\27[0m")); assert(r:onLine("\27[33m<stat> <label>  auto  clear  reroll  done  ? help\27[0m")); eq(f.sent[1],"auto")
end)

test("legacy body roller remains compatible and leaves qualifying prompt untouched",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,reroll_command="n",reroll_delay=.5,auto_start_on_name=true,use_min_stats=true,min_stats={MP=7}})
  assert(r:onLine("Name : Dace Alterac  Race : Monitanian")); assert(r:onLine(legacyHeader)); assert(r:onLine("Great Great Great Great Great Great Great Great Great Great Great"))
  eq(r.state.last.total,77); eq(r.state.last.maximum,77); assert(r:onLine(legacyPrompt)); eq(r.state.active,false); eq(#f.sent,0); eq(r.state.last.stats.APP,7); eq(r.state.last.stats.MP,nil)
end)

test("legacy body roller still sends n after a failed prompt",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,reroll_delay=.25,auto_start_on_name=true})
  r:onLine("Name : Test Tester Race : Human"); r:onLine(legacyHeader); r:onLine("Low Low Low Low Low Low Low Low Low Low Low"); assert(r:onLine(legacyPrompt))
  eq(#f.sent,0); eq(f.timers[1].delay,.25); f.timers[1].fn(); eq(f.sent[1],"n"); eq(r.state.active,true)
end)

test("legacy manual y and n cancel queued automatic rejection",function()
  for _,choice in ipairs({"y","n"}) do
    local f=fake(); local r=Roller.new(f,{target_total=70,reroll_delay=1,auto_start_on_name=true})
    r:onLine("Name : Test Tester Race : Human"); r:onLine(legacyHeader); r:onLine("Low Low Low Low Low Low Low Low Low Low Low"); assert(r:onLine(legacyPrompt)); local stale=f.timers[1].fn
    assert(r:onLine("> "..choice)); eq(r.state.timer,nil); stale(); eq(#f.sent,0); eq(r.state.active,choice=="n")
  end
end)

test("legacy mode stops instead of looping forever on an impossible uncapped target",function()
  local f=fake(); local r=Roller.new(f,{target_total=84,hard_stop=nil,max_rolls=nil,reroll_delay=0,auto_start_on_name=true})
  r:onLine("Name : Test Tester Race : Human"); r:onLine(legacyHeader); r:onLine("Great Great Great Great Great Great Great Great Great Great Great"); assert(r:onLine(legacyPrompt))
  eq(r.state.active,false); eq(r.state.last.maximum,77); eq(#f.sent,0); eq(next(f.timers),nil); assert(f.messages[#f.messages]:find("cannot be reached",1,true))
end)

test("roller settings and per-stat minimums persist through callback",function()
  local f=fake(); local saved; local r=Roller.new(f,{target_total=60,min_stats={}},function(value) saved=value; return true end)
  assert(r:command("set total 65")); eq(r.cfg.target_total,65); eq(saved.target_total,65)
  assert(r:command("set STR 5")); eq(r.cfg.min_stats.STR,5); eq(r.cfg.use_min_stats,true); eq(saved.min_stats.STR,5)
  assert(r:command("set STR off")); eq(r.cfg.min_stats.STR,nil)
end)

test("roller rejects impossible score settings",function()
  local r=Roller.new(fake(),{min_stats={}})
  local ok,err=r:command("set total 85"); eq(ok,nil); assert(err:find("invalid",1,true))
  ok,err=r:command("set STR 8"); eq(ok,nil); assert(err:find("1%-7"))
  ok,err=r:command("set total 53.9"); eq(ok,nil); eq(r.cfg.target_total,nil)
  local guarded=Roller.new(fake(),{target_total=53,hard_stop=nil,max_rolls=nil,min_stats={}}); ok,err=guarded:command("set total off"); eq(ok,nil); eq(guarded.cfg.target_total,53)
  ok,err=guarded:command("set delay 1e999"); eq(ok,nil); eq(guarded.cfg.reroll_delay,nil)
end)

test("standalone roller conflict prevents automatic creator startup",function()
  local f=fake(); function f:standaloneRollerPresent() return true end
  local r=Roller.new(f,{target_total=84,auto_start_on_name=true}); newRoll(r,"Great Great Great Great Great Great","Great Great Great Great Great Great")
  local ok,err=r:onLine(creatorPrompt); eq(ok,nil); eq(err,"standalone roller conflict"); eq(r.state.active,false); eq(r.state.rolls,0)
end)

test("reroll send failure stops safely",function()
  local f=fake(); function f:sendCommand() error("send failed") end
  local r=Roller.new(f,{target_total=60,reroll_delay=.1}); r:start(); newRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low Low"); r:onLine(creatorPrompt)
  f.timers[1].fn(); eq(r.state.active,false); assert(f.messages[#f.messages]:find("Could not send reroll",1,true))
end)

test("non-throwing reroll send failure stops safely",function()
  local f=fake(); function f:sendCommand() return nil,"send failed" end
  local r=Roller.new(f,{target_total=60,reroll_delay=.1}); r:start(); newRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low Low"); r:onLine(creatorPrompt)
  f.timers[1].fn(); eq(r.state.active,false)
end)

test("bulk settings validate and persist atomically while migrating old command",function()
  local f=fake(); local saves=0; local saved
  local r=Roller.new(f,{target_total=53,hard_stop=62,reroll_delay=.1,reroll_command="n",use_min_stats=true,min_stats={STR=5}},function(value) saves=saves+1; saved=value; return true end)
  eq(r.cfg.reroll_command,"reroll")
  local ok,err=r:configure({target_total="80",hard_stop="off",max_rolls="1000",reroll_delay="0.2",reroll_command="reroll",auto_start_on_name=false,use_min_stats=true,require_min_stats_to_stop=true,logging_enabled=true,log_folder="rolls",master_file="master.txt",min_stats={STR="6",INT="off",MP="5"}})
  assert(ok,err); eq(saves,1); eq(r.cfg.target_total,80); eq(r.cfg.hard_stop,nil); eq(r.cfg.min_stats.MP,5); eq(saved.max_rolls,1000)
  ok,err=r:configure({target_total="banana"}); eq(ok,nil); eq(r.cfg.target_total,80); eq(saves,1)
  ok,err=r:configure({reroll_command="n"}); eq(ok,nil); assert(err:find("must remain reroll",1,true)); eq(r.cfg.reroll_command,"reroll")
end)

test("bulk settings leave live config unchanged when persistence fails",function()
  local r=Roller.new(fake(),{target_total=53,hard_stop=62,reroll_command="n",min_stats={STR=5}},function() return nil,"disk full" end)
  local ok,err=r:configure({target_total="70"}); eq(ok,nil); eq(err,"disk full"); eq(r.cfg.target_total,53); eq(r.cfg.reroll_command,"reroll")
end)

test("protocol controls reroll commands even if live config is tampered",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,reroll_command="anything",reroll_delay=0}); r:start(); newRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low Low"); r:onLine(creatorPrompt); r.cfg.reroll_command="n"; f.timers[1].fn(); eq(f.sent[1],"reroll")
end)
