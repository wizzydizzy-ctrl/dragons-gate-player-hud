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
local currentSecondHeader="  CHA         WIL         VOI         PER         APP"
local updatedSecondHeader="  CHA         WIL         PRE         PER         LUK"
local creatorPrompt="reroll  done  ? help"
local arrangePrompt="<stat> <label>  auto  clear  reroll  done  ? help"
local arrangeResetPrompt="<stat> <label>  auto  reset  reroll  done  ? help"
local function poolLine(labels) return #labels==0 and "Pool: (empty)" or "Pool: "..table.concat(labels," ") end
local function removeLabel(labels,label)
  for index,value in ipairs(labels) do if value:lower()==label:lower() then table.remove(labels,index); return true end end
  return false
end
local function newRoll(r,first,second)
  assert(r:onLine(firstHeader)); assert(r:onLine(first)); r:onLine(""); assert(r:onLine(secondHeader)); assert(r:onLine(second))
end
local function currentRoll(r,first,second)
  assert(r:onLine(firstHeader)); assert(r:onLine(first)); r:onLine(""); assert(r:onLine(currentSecondHeader)); assert(r:onLine(second))
end
local function updatedRoll(r,first,second)
  assert(r:onLine(firstHeader)); assert(r:onLine(first)); r:onLine(""); assert(r:onLine(updatedSecondHeader)); assert(r:onLine(second))
end

test("updated roll in place captures PRE and LUK and sends only one confirmed reroll",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,reroll_delay=0,auto_start_on_name=true})
  updatedRoll(r,"Good Excel Fair Aver Fair Fair","Low Fair Fair Aver Awful")
  assert(r:onLine(creatorPrompt)); eq(r.state.rolls,1); eq(r.state.last.total,50)
  eq(r.state.last.stats.PRE,5); eq(r.state.last.stats.LUK,1)
  eq(r.state.last.stats.VOI,nil); eq(r.state.last.stats.APP,nil)
  local timer=r.state.timer; assert(timer and f.timers[timer]); eq(r:onLine(creatorPrompt),false)
  f.timers[timer].fn(); eq(#f.sent,1); eq(f.sent[1],"reroll")
  r:onLine("> reroll"); r:onLine("That set was too weak to offer -- rolling again.")
  updatedRoll(r,"Great Great Great Great Great Great","Great Great Great Great Great")
  assert(r:onLine(creatorPrompt)); eq(r.state.rolls,2); eq(r.state.active,false); eq(#f.sent,1)
  assert(r.state.result_held); assert(f.messages[#f.messages-1]:find("manual done",1,true))
end)

test("updated arranged pool assigns PRE and LUK before asking the game to fill",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,auto_start_on_name=true,use_min_stats=true,arrange_mode="minimums",min_stats={PRE=7,LUK=6}})
  assert(r:onLine(firstHeader)); r:onLine("-- -- -- -- -- --"); r:onLine(updatedSecondHeader); r:onLine("-- -- -- -- --")
  assert(r:onLine("Pool: Great Good Good Good Good Good Fair Fair Fair Fair Fair"))
  assert(r:onLine(arrangeResetPrompt)); eq(r.state.last.order[9],"PRE"); eq(r.state.last.order[11],"LUK")
  eq(f.sent[1],"pre great")
  assert(r:onLine("PRE placed: Great.")); assert(r:onLine("Pool: Good Good Good Good Good Fair Fair Fair Fair Fair"))
  assert(r:onLine(arrangeResetPrompt)); eq(f.sent[2],"luk good")
  assert(r:onLine("LUK placed: Good.")); assert(r:onLine("Pool: Good Good Good Good Fair Fair Fair Fair Fair"))
  assert(r:onLine(arrangeResetPrompt)); eq(f.sent[3],"auto")
  for _,command in ipairs(f.sent) do assert(command~="done") end
end)

test("assign method never sends a reroll without the exact rolling prompt",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,auto_start_on_name=true})
  r:onLine("Step 7 of 10 - Characteristics")
  updatedRoll(r,"Poor Poor Awful Awful Awful Awful","Awful Awful Awful Awful Awful")
  eq(r:onLine("raise <stat>  lower <stat>  reset  done  ? help"),false)
  eq(r.state.active,false); eq(#f.sent,0)
end)

test("manual start survives a creator choice of either rolling method",function()
  for _,method in ipairs({"2","3"}) do
    local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=false})
    r:onLine("Step 7 of 10 - Characteristics"); assert(r:start())
    eq(r:onOutgoing(method),false); eq(r.state.active,true); eq(r.state.result_held,false)
    if method=="2" then
      assert(r:onLine("Pool: Good Good Good Good Good Good Good Good Good Good Good"))
    else
      updatedRoll(r,"Good Good Good Good Good Good","Good Good Good Good Good")
    end
    eq(r.state.rolls,1); eq(#f.sent,0)
  end
end)

test("legacy stat labels honor current slot minimums",function()
  local f=fake(); local r=Roller.new(f,{target_total=53,hard_stop=62,auto_start_on_name=true,
    use_min_stats=true,require_min_stats_to_stop=true,min_stats={PRE=5,LUK=5}})
  currentRoll(r,"Good Good Good Good Good Good","Good Good Awful Good Awful")
  assert(r:onLine(creatorPrompt)); eq(r.state.last.total,56)
  eq(r.state.active,true); eq(r.state.result_held,false)
  assert(r.state.timer); eq(#f.sent,0)
end)

test("old minimum commands update the renamed current stat slots",function()
  local f=fake(); local r=Roller.new(f,{target_total=53,use_min_stats=true,min_stats={PRE=5,LUK=5}})
  assert(r:set("VOI","7")); eq(r.cfg.min_stats.PRE,7); eq(r.cfg.min_stats.VOI,7)
  assert(f.messages[#f.messages]:find("formerly VOI",1,true))
  assert(r:set("APP","6")); eq(r.cfg.min_stats.LUK,6); eq(r.cfg.min_stats.APP,6)
  assert(r:set("PRE","off")); eq(r.cfg.min_stats.PRE,nil); eq(r.cfg.min_stats.VOI,nil)
end)

test("current eleven-stat roll in place auto-starts and scores 77",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=true})
  currentRoll(r,"Great Great Excel Superb Great Great","Great Great Great Great Great")
  assert(r:onLine(creatorPrompt)); eq(r.state.rolls,1); eq(r.state.last.total,77); eq(r.state.last.maximum,77); eq(r.state.last.stats.APP,7); eq(r.state.last.stats.MP,nil); eq(r.state.active,false); eq(#f.sent,0)
end)

test("manual start captures the current eleven-stat roll in place",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,reroll_delay=0,auto_start_on_name=false}); assert(r:start())
  currentRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low"); eq(r.state.rolls,1); assert(r:onLine(creatorPrompt)); f.timers[1].fn(); eq(#f.sent,1); eq(f.sent[1],"reroll")
end)

test("step seven banner does not cancel an explicit manual start",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,reroll_delay=0,auto_start_on_name=false}); assert(r:start())
  eq(r:onLine("Step 7 of 10 - Characteristics"),false); eq(r.state.active,true); eq(r.state.rolls,0); eq(r.state.phase,"observing")
  currentRoll(r,"Great Fair Good Aver Good Aver","Fair Fair Aver Low Aver")
  eq(r.state.rolls,1); eq(r.state.last.maximum,77)
end)

test("manual reroll redetects roll in place after a stale arrange protocol",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,reroll_delay=0,auto_start_on_name=false}); assert(r:start())
  r.state.protocol="arrange"; r.state.phase="waiting_new_roll"; r.state.awaiting_new_roll=true
  assert(r:onOutgoing("reroll")); eq(r.state.protocol,nil)
  currentRoll(r,"Great Fair Good Aver Good Aver","Fair Fair Aver Low Aver")
  eq(r.state.rolls,1); eq(r.state.last.protocol,"creator"); eq(r.state.last.maximum,77)
  assert(r:onLine(creatorPrompt)); local timer=r.state.timer; assert(timer and f.timers[timer]); f.timers[timer].fn(); eq(f.sent[1],"reroll")
end)

test("split characteristic header resynchronizes an active stale arrange protocol",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,reroll_delay=0,auto_start_on_name=false}); assert(r:start())
  r.state.protocol="arrange"; r.state.phase="waiting_new_roll"; r.state.awaiting_new_roll=true
  currentRoll(r,"Great Fair Good Aver Good Aver","Fair Fair Aver Low Aver")
  eq(r.state.rolls,1); eq(r.state.last.protocol,"creator"); eq(r.state.last.stats.STR,7); eq(r.state.last.stats.APP,4)
end)

test("current roll in place continues for fifty rejected rolls without duplicates",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,reroll_delay=0,auto_start_on_name=true})
  for index=1,50 do
    currentRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low")
    assert(r:onLine(creatorPrompt)); eq(r.state.rolls,index)
    local timer=r.state.timer; local pending=timer and f.timers[timer]; assert(pending); f.timers[timer]=nil; pending.fn(); eq(#f.sent,index); eq(f.sent[index],"reroll")
    assert(r:onLine("> reroll")); assert(r:onLine("reroll")); r:onLine(">"); if index%3==0 then r:onLine("That set was too weak to offer -- rolling again.") end; eq(#f.sent,index)
  end
end)

test("current roll and arrange accepts reset prompt and continues for fifty rejected pools",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,reroll_delay=0,auto_start_on_name=true,use_min_stats=false,arrange_mode="manual"})
  local pool="Pool: Good Good Fair Fair Fair Aver Aver Aver Low Low Poor"
  for index=1,50 do
    assert(r:onLine(pool)); assert(r:onLine(arrangeResetPrompt)); eq(r.state.rolls,index)
    local timer=r.state.timer; local pending=timer and f.timers[timer]; assert(pending); f.timers[timer]=nil; pending.fn(); eq(#f.sent,index); eq(f.sent[index],"reroll")
    assert(r:onLine("> reroll")); assert(r:onLine("reroll")); r:onLine(">"); if index%3==0 then r:onLine("That set was too weak to offer -- rolling again.") end; eq(#f.sent,index)
  end
end)

test("current pool capture ignores the placeholder assignment board",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,reroll_delay=0,auto_start_on_name=true,use_min_stats=false,arrange_mode="manual"})
  assert(r:onLine(firstHeader)); eq(r:onLine("-- -- -- -- -- --"),false); r:onLine(""); eq(r:onLine(currentSecondHeader),false); eq(r:onLine("-- -- -- -- --"),false)
  assert(r:onLine("Pool: Superb Excel Good Fair Aver Low Poor Good Fair Aver Low")); r:onLine("Fit for a Fighter: Awful    primes: STR DEX")
  assert(r:onLine(arrangeResetPrompt)); eq(r.state.rolls,1); eq(r.state.last.maximum,77); eq(r.state.last.total,52); eq(r.state.active,true); eq(r.state.timer~=nil,true)
end)

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

test("current totals validate through 77",function()
  local r=Roller.new(fake(),{target_total=53,min_stats={}})
  assert(r:command("set total 77")); eq(r.cfg.target_total,77)
  local ok,err=r:command("set total 78"); eq(ok,nil); assert(err:find("invalid",1,true)); eq(r.cfg.target_total,77)
end)

test("rr show reports every setting in clear groups without changing state",function()
  local f=fake(); local saves=0
  local r=Roller.new(f,{
    target_total=55,hard_stop=false,max_rolls=5000,reroll_delay=.25,reroll_command="reroll",
    arrange_mode="minimums",minimum_greats=2,minimum_good_plus=5,
    auto_start_on_name=false,use_min_stats=true,require_min_stats_to_stop=false,
    show_every_roll=false,logging_enabled=false,log_folder="private_rolls",master_file="summary.txt",
    min_stats={STR=5,INT=7,LUK=false,MP=6},
  },function() saves=saves+1; return true end)
  local state=r.state
  assert(r:command("show")); eq(r.state,state); eq(r.state.active,false); eq(saves,0); eq(#f.sent,0)
  local output=f.messages[#f.messages]
  for _,expected in ipairs({
    "Autoroller status","State: INACTIVE","Protocol: Not detected yet","Auto-start is off",
    "[Roll rules]","Target total: 55 / 77","Hard stop: off","Maximum rolls: 5000",
    "Reroll delay: 0.25 seconds","Reroll command: reroll (fixed)",
    "[Characteristic minimums]","Minimums enabled: ON","Require minimums to stop: OFF",
    "STR: 5 (Fair)","INT: 7 (Great)","LUK: off","Legacy MP: 6 (Good)",
    "[Roll-and-arrange only]","MY MINIMUMS + AUTO (minimums)","Minimum Great values: 2",
    "Minimum Good-or-Great values: 5","apply only to Roll-and-arrange pools",
    "[Startup, output, and logs]","Print every roll: OFF","Roll logging: OFF",
    "Log folder: private_rolls (profile-local name)","Master log: summary.txt (profile-local name)",
  }) do assert(output:find(expected,1,true),"missing from rr show: "..expected.."\n"..output) end
end)

test("rr status explains inactive observing capturing prompt and reroll wait states",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,reroll_delay=.2,auto_start_on_name=false})
  assert(r:command("status")); local output=f.messages[#f.messages]
  assert(output:find("State: INACTIVE",1,true)); assert(output:find("Protocol: Not detected yet",1,true)); assert(output:find("Phase: Idle",1,true)); assert(output:find("Auto-start is off",1,true))

  assert(r:start()); assert(r:command("status")); output=f.messages[#f.messages]
  assert(output:find("State: ACTIVE",1,true)); assert(output:find("Phase: Observing",1,true)); assert(output:find("Waiting for a complete supported roll",1,true))

  assert(r:onLine(firstHeader)); assert(r:command("status")); output=f.messages[#f.messages]
  assert(output:find("Protocol: Roll in place",1,true)); assert(output:find("Phase: Capturing roll",1,true)); assert(output:find("Reading the characteristic values",1,true))

  assert(r:onLine("Low Low Low Low Low Low")); r:onLine(""); assert(r:onLine(currentSecondHeader)); assert(r:onLine("Low Low Low Low Low")); assert(r:command("status")); output=f.messages[#f.messages]
  assert(output:find("Phase: Waiting for prompt",1,true)); assert(output:find("Roll captured; waiting for the exact decision prompt",1,true))

  assert(r:onLine(creatorPrompt)); assert(r:command("status")); output=f.messages[#f.messages]
  assert(output:find("Phase: Reroll delay",1,true)); assert(output:find("waiting for the configured reroll delay",1,true))
  local timer=r.state.timer; f.timers[timer].fn(); assert(r:command("status")); output=f.messages[#f.messages]
  assert(output:find("Phase: Waiting for next roll",1,true)); assert(output:find("Reroll sent or observed",1,true)); eq(#f.sent,1)
end)

test("rr status identifies a held qualifying result and its protocol",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=true})
  currentRoll(r,"Great Great Great Great Great Great","Great Great Great Great Great"); assert(r:onLine(creatorPrompt)); assert(r:command("status"))
  local output=f.messages[#f.messages]
  assert(output:find("State: INACTIVE",1,true)); assert(output:find("Protocol: Roll in place",1,true)); assert(output:find("Phase: Result held",1,true)); assert(output:find("manual done or reroll",1,true)); assert(output:find("never sends done",1,true)); eq(#f.sent,0)
end)

test("rr status explains arranged-pool auto confirmation wait",function()
  local f=fake(); local r=Roller.new(f,{target_total=50,auto_start_on_name=true,use_min_stats=false,arrange_mode="game_auto"})
  assert(r:onLine("Pool: Great Good Good Good Fair Fair Fair Aver Aver Low Low")); assert(r:onLine(arrangePrompt)); assert(r:command("status"))
  local output=f.messages[#f.messages]
  assert(output:find("State: ACTIVE",1,true)); assert(output:find("Protocol: Roll and arrange",1,true)); assert(output:find("Phase: Arranging pool",1,true)); assert(output:find("complete assignment board and an empty pool",1,true)); eq(f.sent[1],"auto")
end)

test("rr status explains passive prompt detection and manual-stop suppression",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=true})
  currentRoll(r,"Great Great Great Great Great Great","Great Great Great Great Great"); assert(r:command("status"))
  local output=f.messages[#f.messages]
  assert(output:find("State: INACTIVE",1,true)); assert(output:find("Protocol: Roll in place",1,true)); assert(output:find("Phase: Checking decision prompt",1,true)); assert(output:find("complete roll was seen",1,true))

  assert(r:command("stop")); assert(r:command("status")); output=f.messages[#f.messages]
  assert(output:find("State: INACTIVE",1,true)); assert(output:find("Phase: Idle",1,true)); assert(output:find("Manual stop is holding automatic rolling off",1,true)); assert(output:find("Auto-start: ON",1,true))
end)

test("rr status explains the next confirmed minimum placement wait",function()
  local f=fake(); local r=Roller.new(f,{target_total=50,auto_start_on_name=true,use_min_stats=true,arrange_mode="minimums",min_stats={INT=6}})
  assert(r:onLine("Pool: Great Good Good Good Fair Fair Fair Aver Aver Low Low")); assert(r:onLine(arrangePrompt)); assert(r:command("status"))
  local output=f.messages[#f.messages]
  assert(output:find("Protocol: Roll and arrange",1,true)); assert(output:find("Phase: Arranging pool",1,true)); assert(output:find("next minimum placement and updated pool",1,true)); eq(f.sent[1],"int great")
end)

test("rr config and settings alias rr show while help advertises status and show",function()
  local f=fake(); local r=Roller.new(f,{target_total=53,min_stats={}})
  assert(r:command("config")); local config=f.messages[#f.messages]; assert(config:find("[Roll rules]",1,true))
  assert(r:command("settings")); eq(f.messages[#f.messages],config)
  assert(r:command("help")); local help=f.messages[#f.messages]
  assert(help:find("rr start|stop|status|show|stats|last|reset|help",1,true)); assert(help:find("rr status to see what the roller is waiting for",1,true)); assert(help:find("rr show to display every saved setting",1,true))
end)

test("rr reports never expose legacy log paths",function()
  local f=fake(); local r=Roller.new(f,{target_total=53,log_folder="/Users/example/private",master_file="C:\\private\\rolls.txt",min_stats={}})
  assert(r:command("show")); local output=f.messages[#f.messages]
  assert(output:find("Log folder: custom name hidden",1,true)); assert(output:find("Master log: custom name hidden",1,true))
  assert(not output:find("/Users/example",1,true)); assert(not output:find("C:\\private",1,true))
  assert(r:command("status")); output=f.messages[#f.messages]
  assert(not output:find("private",1,true)); assert(not output:find("rolls.txt",1,true))
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
  assert(r:onLine("Pool: Great Good Good Good Good Good Fair Fair Aver Low Low")); assert(r:onLine(arrangePrompt))
  local labels={"Great","Good","Good","Good","Good","Good","Fair","Fair","Aver","Low","Low"}
  for index=1,#Roller.order do local command=f.sent[index]
    local stat,label=command:match("^(%a+)%s+(%a+)$"); assert(stat and label); assert(r:onLine(stat:upper().." placed: "..label:sub(1,1):upper()..label:sub(2).."."))
    assert(removeLabel(labels,label)); assert(r:onLine(poolLine(labels))); assert(r:onLine(arrangePrompt))
  end
  eq(#f.sent,11); eq(r.state.active,false)
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
  assert(r:onOutgoing("reroll")); assert(r:onLine("> reroll")); eq(#f.sent,0); assert(r:onLine(offered)); assert(r:onLine(arrangePrompt)); eq(r.state.rolls,2); eq(#f.sent,0)
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
  local ok,err=r:configure({target_total="70",hard_stop="off",max_rolls="1000",reroll_delay="0.2",reroll_command="reroll",auto_start_on_name=false,use_min_stats=true,require_min_stats_to_stop=true,logging_enabled=true,log_folder="rolls",master_file="master.txt",min_stats={STR="6",INT="off",MP="5"}})
  assert(ok,err); eq(saves,1); eq(r.cfg.target_total,70); eq(r.cfg.hard_stop,nil); eq(r.cfg.min_stats.MP,5); eq(saved.max_rolls,1000)
  ok,err=r:configure({target_total="banana"}); eq(ok,nil); eq(r.cfg.target_total,70); eq(saves,1)
  ok,err=r:configure({reroll_command="n"}); eq(ok,nil); assert(err:find("must remain reroll",1,true)); eq(r.cfg.reroll_command,"reroll")
end)

test("bulk settings leave live config unchanged when persistence fails",function()
  local r=Roller.new(fake(),{target_total=53,hard_stop=62,reroll_command="n",min_stats={STR=5}},function() return nil,"disk full" end)
  local ok,err=r:configure({target_total="70"}); eq(ok,nil); eq(err,"disk full"); eq(r.cfg.target_total,53); eq(r.cfg.reroll_command,"reroll")
end)

test("protocol controls reroll commands even if live config is tampered",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,reroll_command="anything",reroll_delay=0}); r:start(); newRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low Low"); r:onLine(creatorPrompt); r.cfg.reroll_command="n"; f.timers[1].fn(); eq(f.sent[1],"reroll")
end)

test("latent psion discovery cancels a queued reroll before alerting",function()
  local f=fake(); local alerts={}; local r=Roller.new(f,{target_total=77,reroll_delay=1,auto_start_on_name=false},nil,function(message) alerts[#alerts+1]=message end)
  assert(r:start()); currentRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low"); assert(r:onLine(creatorPrompt))
  local timerId=r.state.timer; local stale=f.timers[timerId].fn
  assert(r:onLine("\27[35mSomething stirs behind your eyes. You have a latent psionic gift.\27[0m"))
  eq(r.state.active,false); eq(r.state.latent_psion,true); eq(r.state.auto_suppressed,true); eq(r.state.timer,nil); eq(f.timers[timerId],nil)
  eq(#alerts,1); assert(alerts[1]:find("LATENT PSION DETECTED",1,true)); eq(r:phaseText(),"LATENT PSION FOUND")
  stale(); eq(#f.sent,0)
  assert(r:onLine("Something stirs behind your eyes. You have a latent psionic gift.")); eq(#alerts,1); eq(#f.sent,0)
end)

test("latent psion discovery is detected while inactive and across wrapped output",function()
  local alerts=0; local r=Roller.new(fake(),{auto_start_on_name=false},nil,function() alerts=alerts+1 end)
  assert(r:onLine("[123] 20/20 hp > Something stirs behind your eyes.")); eq(alerts,0)
  assert(r:onLine("You have a latent psionic gift.")); eq(alerts,1); eq(r.state.latent_psion,true); eq(r.state.active,false)
  assert(r:waitReason():find("Automatic input is disabled",1,true))
end)

test("latent psion detector ignores quoted speech and resets on disconnect",function()
  local alerts=0; local r=Roller.new(fake(),{},nil,function() alerts=alerts+1 end)
  eq(r:onLine([[Gia says, "Something stirs behind your eyes. You have a latent psionic gift."]]),false); eq(alerts,0)
  assert(r:onLine("Something stirs behind your eyes. You have a latent psionic gift.")); eq(alerts,1)
  assert(r:onDisconnect()); eq(r.state.latent_psion,false); eq(r.state.auto_suppressed,false); eq(r:phaseText(),"Idle")
end)

test("latent psion alert callback failures cannot resume automatic input",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,reroll_delay=1,auto_start_on_name=false},nil,function() error("audio unavailable") end)
  assert(r:start()); currentRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low"); assert(r:onLine(creatorPrompt)); local stale=f.timers[1].fn
  assert(r:onLine("Something stirs behind your eyes. You have a latent psionic gift.")); stale()
  eq(r.state.active,false); eq(r.state.latent_psion,true); eq(#f.sent,0)
end)

-- Session-high expectations are computed from synthetic captures, independently
-- of Roller.order, Roller.ranks, and the implementation's running aggregates.
local sessionNames={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","PRE","PER","LUK"}
local sessionLegacyNames={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"}
local sessionOldNames={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP","MP"}
local sessionLabels={"Awful","Poor","Low","Aver","Fair","Good","Great"}
local function sessionStats(value,names)
  local out={}; for _,name in ipairs(names or sessionNames) do out[name]=value end; return out
end
local function confirmSession(r,protocol)
  assert(type(r.confirmSessionRoll)=="function","planned Roller:confirmSessionRoll(protocol) API is missing")
  assert(r:confirmSessionRoll(protocol),"complete capture must be confirmed by its matching protocol")
end
local function recordSessionStats(r,stats,protocol,names)
  -- Direct API fixtures represent distinct game reroll transactions.
  assert(r:prepareForReroll(protocol))
  assert(r:record(stats,protocol,names)); confirmSession(r,protocol)
end
local function recordSessionPool(r,pool)
  assert(r:prepareForReroll("arrange"))
  assert(r:recordPool(pool)); confirmSession(r,"arrange")
end
local function sessionRow(rows,name)
  for _,row in ipairs(rows) do if row.name==name then return row end end
  error("missing session row for "..name,2)
end
local function scalarRow(row,allowed)
  assert(type(row)=="table"); eq(getmetatable(row),nil)
  for key,value in pairs(row) do
    assert(allowed[key],"unexpected session row field: "..tostring(key))
    assert(type(value)=="string" or type(value)=="number" or type(value)=="boolean","session row exposes a non-scalar "..tostring(key))
  end
end
local function sessionSnapshot(r)
  assert(type(r.sessionSummary)=="function","planned Roller:sessionSummary() API is missing")
  local summary=r:sessionSummary(); assert(type(summary)=="table"); eq(getmetatable(summary),nil)
  local allowed={active=true,rolls=true,stat_rolls=true,pool_rolls=true,best_total=true,average=true,maximum=true,phase=true,stats=true,pool=true,warning=true,unmet=true}
  for key,value in pairs(summary) do
    assert(allowed[key],"snapshot exposes an internal field: "..tostring(key))
    if key~="stats" and key~="pool" and key~="unmet" then
      assert(type(value)=="string" or type(value)=="number" or type(value)=="boolean","snapshot exposes a non-scalar "..tostring(key))
    end
  end
  eq(type(summary.active),"boolean"); eq(type(summary.phase),"string")
  for _,key in ipairs({"rolls","stat_rolls","pool_rolls","average","maximum"}) do eq(type(summary[key]),"number") end
  eq(type(summary.stats),"table"); eq(type(summary.pool),"table"); eq(type(summary.unmet),"table")
  local fields={name=true,value=true,label=true,roll=true,target=true,target_label=true}
  for _,row in ipairs(summary.stats) do
    scalarRow(row,fields); eq(type(row.name),"string")
    if row.value~=nil then eq(row.label,sessionLabels[row.value]); assert(row.roll>=1) end
    if row.target~=nil then eq(row.target_label,sessionLabels[row.target]) end
  end
  for index,row in ipairs(summary.pool) do
    scalarRow(row,{slot=true,value=true,label=true,roll=true}); eq(row.slot,index)
    eq(row.label,sessionLabels[row.value]); assert(row.roll>=1)
  end
  return summary
end
local function sessionOrderIs(summary,names)
  eq(#summary.stats,#names)
  for index,name in ipairs(names) do eq(summary.stats[index].name,name) end
end
local function sessionPhaseIs(summary,raw,display)
  assert(summary.phase==raw or summary.phase==display,"unexpected session phase: "..tostring(summary.phase))
end
local function fireSessionTimer(f,r)
  local id=r.state.timer; local pending=id and f.timers[id]; assert(pending,"expected one scheduled reroll")
  f.timers[id]=nil; pending.fn(); return pending.delay
end
local function observedNotice(message)
  local text=message:lower()
  return (text:find("observ",1,true) or text:find("best seen",1,true))
    and text:find("not",1,true) and text:find("confirm",1,true)
    and (text:find("cap",1,true) or text:find("limit",1,true))
end
local function noticeCount(messages)
  local count=0
  for _,message in ipairs(messages) do
    if message:find("MINIMUMS NOT YET SEEN",1,true) then
      assert(observedNotice(message),"minimum notice must distinguish observed highs from confirmed caps")
      count=count+1
    end
  end
  return count
end

test("session summary starts empty and exposes only defensive scalar data",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=false})
  local first=sessionSnapshot(r); local second=sessionSnapshot(r)
  assert(first~=second); assert(first.stats~=second.stats); assert(first.pool~=second.pool); assert(first.unmet~=second.unmet)
  eq(first.active,false); eq(first.rolls,0); eq(first.stat_rolls,0); eq(first.pool_rolls,0)
  eq(first.average,0); eq(first.maximum,77); sessionPhaseIs(first,"idle","Idle"); eq(#first.pool,0); eq(#first.unmet,0)
  for _,row in ipairs(first.stats) do eq(row.value,nil); eq(row.roll,nil); eq(row.target,nil); eq(row.target_label,nil) end
  first.active=true; first.rolls=999; first.stats[1]={name="INJECTED",value=7}; first.pool[1]={slot=1,value=7}
  local fresh=sessionSnapshot(r); eq(fresh.active,false); eq(fresh.rolls,0); eq(#fresh.pool,0)
  for _,row in ipairs(fresh.stats) do assert(row.name~="INJECTED"); eq(row.value,nil) end
  eq(#f.sent,0); eq(f.next,0)
end)

test("record tracks independent named highs on rejected totals and retains first tied roll",function()
  local r=Roller.new(fake(),{target_total=77,auto_start_on_name=false,use_min_stats=true,min_stats={INT=7,PRE=7,LUK=6}})
  assert(r:start())
  local first=sessionStats(5); first.STR=6; first.INT=4
  local second=sessionStats(1); second.STR=6; second.INT=6; second.PRE=6; second.LUK=5
  recordSessionStats(r,first,"creator",sessionNames); recordSessionStats(r,second,"creator",sessionNames)
  eq(r:qualified(r.state.last),false)
  local summary=sessionSnapshot(r); sessionOrderIs(summary,sessionNames)
  eq(summary.active,true); eq(summary.rolls,2); eq(summary.stat_rolls,2); eq(summary.pool_rolls,0)
  eq(summary.best_total,55); eq(summary.average,42.5); eq(summary.maximum,77); sessionPhaseIs(summary,"awaiting_prompt","Waiting for prompt")
  for _,name in ipairs(sessionNames) do
    local row=sessionRow(summary.stats,name)
    local improved=name=="INT" or name=="PRE"
    eq(row.value,(improved or name=="STR") and 6 or 5); eq(row.roll,improved and 2 or 1)
    eq(r.state.stat_highs[name].value,row.value); eq(r.state.stat_highs[name].roll,row.roll)
  end
  eq(sessionRow(summary.stats,"INT").target,7); eq(sessionRow(summary.stats,"INT").target_label,"Great")
  eq(sessionRow(summary.stats,"LUK").target,6); eq(sessionRow(summary.stats,"STR").target,nil)
  recordSessionStats(r,second,"creator",sessionNames); eq(sessionRow(sessionSnapshot(r).stats,"INT").roll,2)
  eq(sessionRow(summary.stats,"INT").roll,2); eq(summary.rolls,2)
end)

test("mixed current and legacy formats reset evidence and preserve actual screen labels",function()
  local r=Roller.new(fake(),{target_total=77,auto_start_on_name=false,use_min_stats=true,min_stats={PRE=7,LUK=6}})
  assert(r:start())
  updatedRoll(r,"Poor Poor Poor Poor Poor Poor","Poor Poor Good Poor Fair")
  confirmSession(r,"creator")
  assert(r:onOutgoing("reroll"))
  currentRoll(r,"Low Low Low Low Low Low","Low Low Aver Low Great")
  confirmSession(r,"creator")
  local legacy=sessionSnapshot(r); sessionOrderIs(legacy,sessionLegacyNames)
  eq(sessionRow(legacy.stats,"VOI").value,4); eq(sessionRow(legacy.stats,"VOI").target,7)
  eq(sessionRow(legacy.stats,"APP").value,7); eq(sessionRow(legacy.stats,"APP").target,6)
  eq(legacy.stat_rolls,1); eq(legacy.rolls,2)
  eq(r.state.stat_highs.PRE,nil)
  eq(r.state.stat_highs.VOI.value,4); eq(r.state.stat_highs.VOI.roll,2)
  eq(r.state.stat_highs.LUK,nil)
  eq(r.state.stat_highs.APP.value,7); eq(r.state.stat_highs.APP.roll,2)
  assert(r:onOutgoing("reroll")); newRoll(r,"Aver Aver Aver Aver Aver Aver","Aver Aver Aver Aver Aver Good")
  confirmSession(r,"creator")
  local old=sessionSnapshot(r); sessionOrderIs(old,sessionOldNames); eq(old.maximum,84)
  eq(sessionRow(old.stats,"MP").value,6); eq(sessionRow(old.stats,"MP").roll,3)
  eq(old.stat_rolls,1); eq(sessionRow(old.stats,"VOI").roll,3); eq(sessionRow(old.stats,"APP").value,4)
  assert(r:onOutgoing("reroll")); updatedRoll(r,"Low Low Low Low Low Low","Low Low Low Low Aver")
  confirmSession(r,"creator")
  local current=sessionSnapshot(r); sessionOrderIs(current,sessionNames); eq(current.maximum,84); eq(current.best_total,50)
  eq(current.stat_rolls,1); eq(current.pool_rolls,0); eq(current.rolls,4)
  eq(sessionRow(current.stats,"PRE").value,3); eq(sessionRow(current.stats,"PRE").roll,4)
  eq(sessionRow(current.stats,"LUK").value,4); eq(sessionRow(current.stats,"LUK").roll,4)
  eq(r.state.stat_highs.MP,nil); eq(r.state.stat_highs.VOI,nil); eq(r.state.stat_highs.APP,nil)
  for index,name in ipairs(sessionNames) do eq(r.state.stat_order[index],name) end
end)

test("rank aliases and ANSI captures produce canonical observed labels",function()
  local r=Roller.new(fake(),{target_total=77,auto_start_on_name=false}); assert(r:start())
  assert(r:onLine("\27[36m"..firstHeader.."\27[0m"))
  assert(r:onLine("\27[32mAwful Poor Low Average Fair Good\27[0m"))
  assert(r:onLine("\27[36m"..updatedSecondHeader.."\27[0m"))
  assert(r:onLine("\27[32mExcel Superb Aver Great Good\27[0m"))
  confirmSession(r,"creator")
  local expected={1,2,3,4,5,6,7,7,4,7,6}; local summary=sessionSnapshot(r)
  for index,name in ipairs(sessionNames) do local row=sessionRow(summary.stats,name); eq(row.value,expected[index]); eq(row.label,sessionLabels[expected[index]]); eq(row.roll,1) end
  eq(summary.stat_rolls,1); eq(summary.best_total,52)
  assert(r:onOutgoing("reroll")); assert(r:onLine("Pool: Excel Superb Great Good Fair Average Aver Low Poor Awful Good"))
  confirmSession(r,"arrange")
  summary=sessionSnapshot(r); eq(summary.pool_rolls,1); eq(summary.stat_rolls,1)
  eq(summary.pool[1].label,"Great"); eq(summary.pool[2].label,"Great"); eq(summary.pool[3].label,"Great")
  eq(sessionRow(summary.stats,"STR").value,1)
end)

test("sorted pool slots keep first highs and global roll indices without assigning named stats",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=false}); assert(r:start())
  local first={3,7,2,6,4,6,1,5,2,4,5}; local original={3,7,2,6,4,6,1,5,2,4,5}
  recordSessionPool(r,first); local poolOnly=sessionSnapshot(r)
  eq(poolOnly.rolls,1); eq(poolOnly.stat_rolls,0); eq(poolOnly.pool_rolls,1)
  for _,row in ipairs(poolOnly.stats) do eq(row.value,nil); eq(row.roll,nil) end
  eq(next(r.state.stat_highs),nil)
  for index,value in ipairs(original) do eq(first[index],value); eq(r.state.last.pool[index],value) end
  recordSessionStats(r,sessionStats(4),"creator",sessionNames)
  recordSessionPool(r,{6,3,5,4,5,6,3,4,3,6,3})
  local summary=sessionSnapshot(r); local expected={7,6,6,5,5,4,4,3,3,3,3}
  eq(summary.rolls,3); eq(summary.stat_rolls,1); eq(summary.pool_rolls,2); eq(#summary.pool,11)
  for index,value in ipairs(expected) do
    local row=summary.pool[index]; eq(row.slot,index); eq(row.value,value); eq(row.roll,index>=9 and 3 or 1)
    eq(r.state.pool_highs[index].value,value); eq(r.state.pool_highs[index].roll,row.roll)
  end
  for _,row in ipairs(summary.stats) do eq(row.value,4); eq(row.roll,2) end
  eq(poolOnly.pool[9].value,2); eq(poolOnly.pool[9].roll,1)
  eq(#f.sent,0); eq(f.next,0)
end)

test("twelve to eleven pool slots reset highs and retain the confirmed best denominator",function()
  local r=Roller.new(fake(),{target_total=77,auto_start_on_name=false}); assert(r:start())
  recordSessionPool(r,{7,7,7,7,7,7,7,7,7,7,7,7}); local twelve=sessionSnapshot(r)
  eq(twelve.maximum,84); eq(twelve.best_total,84); eq(#twelve.pool,12); eq(twelve.pool[12].value,7); eq(twelve.pool[12].roll,1)
  recordSessionPool(r,{6,6,6,6,6,6,6,6,6,6,6}); local eleven=sessionSnapshot(r)
  eq(eleven.maximum,84); eq(eleven.best_total,84); eq(eleven.average,75); eq(eleven.pool_rolls,1); eq(eleven.rolls,2); eq(#eleven.pool,11)
  for index=1,11 do eq(eleven.pool[index].value,6); eq(eleven.pool[index].roll,2) end
  eq(r.state.pool_highs[12],nil)
  eq(eleven.stat_rolls,0); eq(next(r.state.stat_highs),nil)
end)

test("original settings stats order and pool mutations cannot rewrite observed history",function()
  local settings={target_total=77,auto_start_on_name=false,use_min_stats=true,min_stats={INT=7}}
  local r=Roller.new(fake(),settings); settings.min_stats.INT=1; settings.target_total=1
  assert(r:start()); local stats=sessionStats(5); local names={}
  for index,name in ipairs(sessionNames) do names[index]=name end
  assert(r:record(stats,"creator",names)); stats.INT=7; stats.STR=nil; names[1]="INJECTED"; names[12]="MP"
  confirmSession(r,"creator")
  assert(r:prepareForReroll("arrange"))
  local pool={1,2,3,4,5,6,7,1,2,3,4}; assert(r:recordPool(pool)); pool[1]=7; pool[7]=1; pool[12]=7
  confirmSession(r,"arrange")
  local summary=sessionSnapshot(r); sessionOrderIs(summary,sessionNames)
  eq(sessionRow(summary.stats,"INT").value,5); eq(sessionRow(summary.stats,"INT").target,7)
  eq(sessionRow(summary.stats,"STR").value,5); eq(r.cfg.target_total,77)
  eq(r.state.stat_order[1],"STR"); eq(#r.state.stat_order,11); eq(#r.state.last.pool,11)
  eq(r.state.last.pool[1],1); eq(r.state.last.pool[7],7); eq(summary.pool[1].value,7)
  summary.stats[1].value=99; summary.stats[1].roll=999; summary.stats[2].target=1
  summary.pool[1].value=99; summary.pool[1].roll=999; summary.rolls=999; summary.stats[1]=nil
  summary.unmet[1].value=99; summary.unmet[1].roll=999; summary.unmet[1].target=1
  local fresh=sessionSnapshot(r); eq(fresh.rolls,2); eq(sessionRow(fresh.stats,"STR").value,5)
  eq(sessionRow(fresh.stats,"STR").roll,1); eq(sessionRow(fresh.stats,"INT").target,7)
  eq(sessionRow(fresh.unmet,"INT").value,5); eq(sessionRow(fresh.unmet,"INT").target,7)
  eq(fresh.pool[1].value,7); eq(fresh.pool[1].roll,2)
end)

test("partial malformed expired and informational stat captures do not advance session highs",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=false}); assert(r:start())
  local invalid={
    {firstHeader,"Good Good Good",updatedSecondHeader,"Good Good Good Good Good",creatorPrompt},
    {firstHeader,"Good Good Good Good Good Mystery",updatedSecondHeader,"Good Good Good Good Good",creatorPrompt},
    {firstHeader,"Good Good Good Good Good Good",updatedSecondHeader,"Good Good Good Good",creatorPrompt},
    {"Fit for a Fighter: Great    primes: STR DEX","A guide says Great Great Great Great Great Great",creatorPrompt},
  }
  for _,lines in ipairs(invalid) do for _,line in ipairs(lines) do r:onLine(line) end end
  assert(r:onLine(firstHeader)); assert(r:onLine("Good Good Good Good Good Good"))
  for index=1,9 do r:onLine("unrelated line "..index) end
  r:onLine(updatedSecondHeader); r:onLine("Great Great Great Great Great"); r:onLine(creatorPrompt)
  local summary=sessionSnapshot(r); eq(summary.rolls,0); eq(summary.stat_rolls,0); eq(next(r.state.stat_highs),nil)
  eq(#f.sent,0); eq(f.next,0)
  updatedRoll(r,"Fair Fair Fair Fair Fair Fair","Fair Fair Fair Fair Fair"); assert(r:onLine(creatorPrompt))
  local first=sessionSnapshot(r); eq(first.rolls,1); eq(first.stat_rolls,1)
  eq(r:onLine(creatorPrompt),false); r:onLine("Fit for a Fighter: Great    primes: STR DEX")
  local repeated=sessionSnapshot(r); eq(repeated.rolls,1); eq(sessionRow(repeated.stats,"STR").value,5); eq(sessionRow(repeated.stats,"STR").roll,1)
  eq(f.next,1); eq(#f.sent,0)
end)

test("passive complete captures count only at a supported prompt and never duplicate redraws",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=true,reroll_delay=.25})
  updatedRoll(r,"Good Good Good Good Good Good","Good Good Good Good Good")
  eq(sessionSnapshot(r).stat_rolls,0)
  eq(r:onLine([[A guide says, "reroll done ? help"]]),false); eq(sessionSnapshot(r).rolls,0)
  assert(r:onLine(creatorPrompt)); eq(sessionSnapshot(r).stat_rolls,1)
  eq(r:onLine(creatorPrompt),false); eq(sessionSnapshot(r).rolls,1); eq(f.next,1)
  eq(fireSessionTimer(f,r),.25); eq(#f.sent,1); eq(f.sent[1],"reroll")
  assert(r:onLine("> reroll")); r:onLine("That set was too weak to offer -- rolling again.")
  assert(r:onLine("Pool: Good Good Good Good Good Good Good Good Good Good Good")); assert(r:onLine(arrangeResetPrompt))
  eq(sessionSnapshot(r).rolls,2); eq(sessionSnapshot(r).stat_rolls,1); eq(sessionSnapshot(r).pool_rolls,1)
  eq(r:onLine(arrangeResetPrompt),false); eq(r:onLine("Pool: Good Good Good Good Good Good Good Good Good Good Good"),false)
  eq(sessionSnapshot(r).pool_rolls,1); eq(#f.sent,1); eq(f.next,2)
end)

test("partial malformed and empty pools never become session slot highs",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=true})
  for _,line in ipairs({"Pool: Good Good Fair","Pool: Good Mystery Fair","Pool: (empty)","Pool: Good Good Good Good Good Good Good Good Good Good Good Good Good"}) do
    r:onLine(line); r:onLine(arrangePrompt)
  end
  local summary=sessionSnapshot(r); eq(summary.rolls,0); eq(summary.pool_rolls,0); eq(#summary.pool,0)
  eq(#f.sent,0); eq(f.next,0)
  assert(r:onLine("Pool: Good Good Good Good Good Good Good Good Good Good Good"))
  eq(sessionSnapshot(r).pool_rolls,0); r:onLine("Pool: Good Good Fair"); eq(r:onLine(arrangePrompt),false)
  eq(sessionSnapshot(r).pool_rolls,0)
end)

test("stop and manual reroll preserve highs while reset and a new start clear them",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=false,reroll_delay=1}); assert(r:start())
  updatedRoll(r,"Good Good Good Good Good Good","Good Good Good Good Good"); assert(r:onLine(creatorPrompt))
  local stale=f.timers[r.state.timer].fn
  assert(r:onOutgoing("reroll")); stale(); eq(#f.sent,0)
  local rerolled=sessionSnapshot(r); eq(rerolled.rolls,1); eq(sessionRow(rerolled.stats,"INT").value,6)
  updatedRoll(r,"Fair Fair Fair Fair Fair Fair","Fair Fair Fair Fair Fair"); confirmSession(r,"creator"); eq(sessionSnapshot(r).rolls,2)
  eq(sessionRow(sessionSnapshot(r).stats,"INT").value,6); eq(sessionRow(sessionSnapshot(r).stats,"INT").roll,1)
  assert(r:command("stop")); local stopped=sessionSnapshot(r)
  eq(stopped.active,false); sessionPhaseIs(stopped,"idle","Idle"); eq(stopped.stat_rolls,2); eq(stopped.rolls,2)
  eq(sessionRow(stopped.stats,"INT").value,6); eq(sessionRow(stopped.stats,"INT").roll,1)
  assert(r:reset()); local reset=sessionSnapshot(r)
  eq(reset.rolls,0); eq(reset.stat_rolls,0); eq(reset.pool_rolls,0); eq(#reset.pool,0)
  assert(not reset.warning); eq(#reset.unmet,0)
  eq(next(r.state.stat_highs),nil); eq(next(r.state.pool_highs),nil)
  assert(r:start()); recordSessionPool(r,{7,6,5,4,3,2,1,6,5,4,3}); assert(r:stop())
  eq(sessionSnapshot(r).pool_rolls,1); eq(sessionSnapshot(r).pool[1].value,7)
  assert(r:start()); local restarted=sessionSnapshot(r)
  eq(restarted.active,true); eq(restarted.rolls,0); eq(restarted.stat_rolls,0); eq(restarted.pool_rolls,0)
  eq(#restarted.pool,0); eq(next(r.state.stat_highs),nil); eq(next(r.state.pool_highs),nil)
  eq(stopped.rolls,2); eq(sessionRow(stopped.stats,"INT").value,6)
end)

test("fifth constructor callback receives reset start record pool configure and stop snapshots",function()
  local f=fake(); local events={}; local saves=0; local alerts=0
  local r=Roller.new(f,{target_total=77,auto_start_on_name=false,min_stats={INT=7}},
    function() saves=saves+1; return true end,function() alerts=alerts+1 end,
    function(summary) events[#events+1]=summary end)
  eq(#events,1); eq(events[1].active,false); eq(events[1].rolls,0); sessionPhaseIs(events[1],"idle","Idle")
  assert(r:start()); eq(events[#events].active,true); eq(events[#events].rolls,0)
  local before=#events; assert(r:record(sessionStats(6),"creator",sessionNames)); eq(#events,before+1)
  eq(events[#events].stat_rolls,0); eq(events[#events].rolls,0)
  before=#events; confirmSession(r,"creator"); eq(#events,before+1)
  eq(events[#events].stat_rolls,1); sessionPhaseIs(events[#events],"awaiting_prompt","Waiting for prompt")
  assert(r:prepareForReroll("arrange"))
  before=#events; assert(r:recordPool({7,6,5,4,3,2,1,6,5,4,3})); eq(#events,before+1)
  eq(events[#events].pool_rolls,0); eq(events[#events].rolls,1)
  before=#events; confirmSession(r,"arrange"); eq(#events,before+1)
  eq(events[#events].pool_rolls,1); eq(events[#events].rolls,2)
  before=#events; assert(r:configure({use_min_stats=true,min_stats={INT=7}})); eq(#events,before+1)
  eq(sessionRow(events[#events].stats,"INT").target,7); eq(saves,1); eq(alerts,0)
  before=#events; assert(r:stop()); eq(#events,before+1); eq(events[#events].active,false); eq(events[#events].rolls,2)
  before=#events; assert(r:reset()); eq(#events,before+1); eq(events[#events].rolls,0)
  for index,event in ipairs(events) do
    for other=1,index-1 do assert(event~=events[other]); assert(event.stats~=events[other].stats); assert(event.pool~=events[other].pool) end
  end
  eq(events[1].rolls,0); eq(events[1].active,false); eq(#f.sent,0); eq(f.next,0)
end)

test("session callback mutations are isolated from config highs and later callbacks",function()
  local f=fake(); local calls=0
  local r=Roller.new(f,{target_total=77,auto_start_on_name=false,use_min_stats=true,min_stats={INT=7}},nil,nil,function(summary)
    calls=calls+1; summary.active=false; summary.rolls=999
    for _,row in ipairs(summary.stats) do row.value=1; row.roll=999; row.target=1 end
    for _,row in ipairs(summary.pool) do row.value=1; row.roll=999 end
    for _,row in ipairs(summary.unmet) do row.value=1; row.roll=999; row.target=1 end
    summary.stats={}; summary.pool={}; summary.unmet={}
  end)
  assert(r:start()); recordSessionStats(r,sessionStats(6),"creator",sessionNames)
  recordSessionPool(r,{7,6,5,4,3,2,1,6,5,4,3})
  local summary=sessionSnapshot(r); assert(calls>=4); eq(summary.active,true); eq(summary.rolls,2)
  eq(sessionRow(summary.stats,"INT").value,6); eq(sessionRow(summary.stats,"INT").roll,1)
  eq(sessionRow(summary.stats,"INT").target,7); eq(r.cfg.min_stats.INT,7)
  eq(summary.pool[1].value,7); eq(summary.pool[1].roll,2); eq(#f.sent,0); eq(f.next,0)
end)

test("throwing session callbacks never break recording configuration or reroll timers",function()
  local f=fake(); local calls=0; local saves=0
  local r=Roller.new(f,{target_total=77,auto_start_on_name=false,reroll_delay=.5},function() saves=saves+1; return true end,nil,function()
    calls=calls+1; error("synthetic session renderer failure")
  end)
  assert(r:start()); updatedRoll(r,"Good Good Good Good Good Good","Good Good Good Good Good")
  assert(r:onLine(creatorPrompt)); eq(#f.sent,0); eq(f.next,1); eq(fireSessionTimer(f,r),.5)
  eq(#f.sent,1); eq(f.sent[1],"reroll"); eq(r.state.active,true)
  assert(r:configure({show_every_roll=false})); eq(saves,1)
  recordSessionPool(r,{7,6,5,4,3,2,1,6,5,4,3}); assert(r:stop()); assert(r:reset())
  assert(calls>=7,"every session publication must safely invoke the callback")
  eq(r.state.rolls,0); eq(r.state.active,false); eq(#f.sent,1)
end)

test("invalid captures and failed configure do not publish a changed session",function()
  local events={}; local r=Roller.new(fake(),{target_total=77,auto_start_on_name=false},function() return nil,"synthetic save failure" end,nil,function(summary) events[#events+1]=summary end)
  assert(r:start()); local before=#events
  eq(r:record({STR=7},"creator",sessionNames),false)
  for _,bad in ipairs({0,8,"Good",math.huge,0/0}) do
    local stats=sessionStats(6); stats.INT=bad; eq(r:record(stats,"creator",sessionNames),false)
  end
  eq(r:recordPool({7,6,5}),false); eq(r:recordPool({7,6,5,4,3,2,1,6,5,4,8}),false)
  local ok=r:configure({target_total="invalid"}); eq(ok,nil)
  local saved,err=r:configure({target_total=60}); eq(saved,nil); eq(err,"synthetic save failure")
  eq(#events,before); eq(r.cfg.target_total,77); eq(sessionSnapshot(r).rolls,0)
end)

test("disabled or achieved stat minimums have no unmet warning or inferred targets",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=false,show_every_roll=false,use_min_stats=false,min_stats={INT=7}})
  assert(r:start()); for index=1,100 do recordSessionStats(r,sessionStats(6),"creator",sessionNames) end
  local disabled=sessionSnapshot(r); eq(disabled.stat_rolls,100); assert(not disabled.warning); eq(#disabled.unmet,0)
  for _,row in ipairs(disabled.stats) do eq(row.target,nil); eq(row.target_label,nil) end
  eq(noticeCount(f.messages),0)
  assert(r:configure({use_min_stats=true,min_stats={INT=6}}))
  local achieved=sessionSnapshot(r); eq(sessionRow(achieved.stats,"INT").target,6)
  eq(sessionRow(achieved.stats,"INT").target_label,"Good"); assert(not achieved.warning); eq(#achieved.unmet,0)
  assert(r:configure({use_min_stats=false})); eq(sessionRow(sessionSnapshot(r).stats,"INT").target,nil)
  eq(r.state.stat_highs.INT.value,6); eq(r.state.stat_highs.INT.roll,1); eq(#f.sent,0); eq(f.next,0)
end)

test("warning checkpoints count only complete named stat rolls and never pool slots",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=false,show_every_roll=false,use_min_stats=true,min_stats={INT=7}})
  assert(r:start()); for index=1,99 do recordSessionStats(r,sessionStats(6),"creator",sessionNames) end
  for index=1,3 do recordSessionPool(r,{7,7,7,7,7,7,7,7,7,7,7}) end
  local before=sessionSnapshot(r); eq(before.rolls,102); eq(before.stat_rolls,99); eq(before.pool_rolls,3)
  assert(not before.warning); eq(noticeCount(f.messages),0); eq(sessionRow(before.stats,"INT").value,6)
  recordSessionStats(r,sessionStats(6),"creator",sessionNames); local at=sessionSnapshot(r)
  eq(at.stat_rolls,100); assert(at.warning); eq(noticeCount(f.messages),1)
  eq(sessionRow(at.unmet,"INT").target,7)
  for index=1,3 do recordSessionPool(r,{7,7,7,7,7,7,7,7,7,7,7}) end
  recordSessionStats(r,sessionStats(5),"creator",sessionNames); eq(noticeCount(f.messages),1)
  eq(sessionRow(sessionSnapshot(r).stats,"INT").value,6); eq(#f.sent,0); eq(f.next,0)
end)

test("425 synthetic valid rolls report target Great versus observed Good without changing commands",function()
  local f=fake(); local saves=0; local publications={}; local checkpoints={}
  local r=Roller.new(f,{target_total=53,auto_start_on_name=false,reroll_delay=.125,show_every_roll=false,
    use_min_stats=true,require_min_stats_to_stop=true,min_stats={INT=7,PRE=7,LUK=7}},
    function() saves=saves+1; return true end,nil,function(summary) publications[#publications+1]=summary end)
  assert(r:start()); local expectedHighs={}; local expectedSum=0; local expectedBest=0
  for index=1,425 do
    local labels={}; local total=0
    for slot,name in ipairs(sessionNames) do
      local value=1+((index*5+slot*3)%6); labels[slot]=sessionLabels[value]; total=total+value
      if not expectedHighs[name] or value>expectedHighs[name].value then expectedHighs[name]={value=value,roll=index} end
    end
    expectedSum=expectedSum+total; expectedBest=math.max(expectedBest,total)
    local before=#f.messages
    updatedRoll(r,table.concat(labels," ",1,6),table.concat(labels," ",7,11))
    assert(r:onLine(creatorPrompt)); eq(r:onLine(creatorPrompt),false); eq(r.state.rolls,index)
    for message=before+1,#f.messages do
      if f.messages[message]:find("MINIMUMS NOT YET SEEN",1,true) then assert(observedNotice(f.messages[message])); checkpoints[#checkpoints+1]=index end
    end
    eq(fireSessionTimer(f,r),.125); eq(#f.sent,index); eq(f.sent[index],"reroll")
    eq(r:onLine(creatorPrompt),false); assert(r:onLine("> reroll")); r:onLine("That set was too weak to offer -- rolling again.")
  end
  local summary=sessionSnapshot(r); sessionOrderIs(summary,sessionNames)
  eq(summary.rolls,425); eq(summary.stat_rolls,425); eq(summary.pool_rolls,0); eq(summary.maximum,77)
  eq(summary.best_total,expectedBest); eq(summary.average,expectedSum/425); eq(summary.active,true)
  for _,name in ipairs(sessionNames) do
    local row=sessionRow(summary.stats,name); eq(row.value,expectedHighs[name].value); eq(row.value,6)
    eq(row.label,"Good"); eq(row.roll,expectedHighs[name].roll)
  end
  assert(summary.warning); eq(#summary.unmet,3)
  for _,name in ipairs({"INT","PRE","LUK"}) do
    eq(sessionRow(summary.stats,name).target,7); eq(sessionRow(summary.stats,name).target_label,"Great")
    eq(sessionRow(summary.unmet,name).target,7); eq(r.cfg.min_stats[name],7)
  end
  eq(#checkpoints,4); for index,roll in ipairs({100,200,300,400}) do eq(checkpoints[index],roll) end
  eq(saves,0); eq(r.cfg.target_total,53); eq(f.next,425); eq(next(f.timers),nil)
  assert(#publications>=427); eq(publications[#publications].stat_rolls,425)
  assert(r:command("stats")); local report=f.messages[#f.messages]
  assert(observedNotice(report),"report must identify observed highs as not a confirmed cap")
  for _,name in ipairs(sessionNames) do assert(report:find(name,1,true),"report table is missing "..name) end
  for _,name in ipairs({"INT","PRE","LUK"}) do
    local found=false
    for line in report:gmatch("[^\n]+") do if line:find(name,1,true) and line:find("Great",1,true) and line:find("Good",1,true) then found=true end end
    assert(found,"report must show target Great and observed Good for "..name)
  end
  eq(#f.sent,425); eq(saves,0)
end)

test("session publishing preserves modern and legacy manual acceptance and stale timer safety",function()
  for _,legacy in ipairs({false,true}) do
    local f=fake(); local events={}; local r=Roller.new(f,{target_total=77,auto_start_on_name=false,reroll_delay=.25},nil,nil,function(summary) events[#events+1]=summary end)
    assert(r:start())
    local function capture(label)
      if legacy then assert(r:onLine(legacyHeader)); assert(r:onLine(table.concat({label,label,label,label,label,label,label,label,label,label,label}," ")))
      else updatedRoll(r,table.concat({label,label,label,label,label,label}," "),table.concat({label,label,label,label,label}," ")) end
      assert(r:onLine(legacy and legacyPrompt or creatorPrompt))
    end
    capture("Good"); local stale=f.timers[r.state.timer].fn
    assert(r:onOutgoing(legacy and "n" or "reroll")); stale(); eq(#f.sent,0)
    capture("Fair"); eq(fireSessionTimer(f,r),.25); eq(#f.sent,1); eq(f.sent[1],legacy and "n" or "reroll")
    capture("Great"); local summary=sessionSnapshot(r)
  eq(summary.active,false); sessionPhaseIs(summary,"held","Result held"); eq(summary.stat_rolls,3); eq(summary.rolls,3)
    eq(sessionRow(summary.stats,"INT").value,7); eq(sessionRow(summary.stats,"INT").roll,3)
    eq(#f.sent,1); assert(r.state.result_held); assert(#events>0)
    eq(r:onLine(legacy and legacyPrompt or creatorPrompt),false); stale(); eq(#f.sent,1)
    assert(r:onOutgoing(legacy and "y" or "done")); eq(sessionSnapshot(r).stat_rolls,3); eq(#f.sent,1)
    for _,command in ipairs(f.sent) do assert(command~="done" and command~="y") end
  end
end)

test("a checkpoint notice leaves normal qualification at the next prompt intact",function()
  local f=fake(); local r=Roller.new(f,{target_total=66,auto_start_on_name=false,show_every_roll=false,
    use_min_stats=true,require_min_stats_to_stop=false,min_stats={INT=7}})
  assert(r:start()); for index=1,99 do recordSessionStats(r,sessionStats(6),"creator",sessionNames) end
  assert(r:onOutgoing("reroll")); updatedRoll(r,"Good Good Good Good Good Good","Good Good Good Good Good")
  local captured=sessionSnapshot(r); eq(captured.stat_rolls,99); eq(captured.active,true); assert(not captured.warning)
  eq(noticeCount(f.messages),0); eq(#f.sent,0); eq(f.next,0); eq(r.cfg.min_stats.INT,7)
  assert(r:onLine(creatorPrompt)); local held=sessionSnapshot(r)
  eq(held.active,false); eq(held.rolls,100); sessionPhaseIs(held,"held","Result held")
  eq(held.stat_rolls,100); eq(noticeCount(f.messages),1)
  assert(r.state.result_held); eq(#f.sent,0); eq(f.next,0); eq(r.cfg.target_total,66); eq(r.cfg.min_stats.INT,7)
end)

test("assignment method and quoted decision prompts leave complete captures provisional",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=false,show_every_roll=false}); assert(r:start())
  r:onLine("Step 7 of 10 - Characteristics")
  updatedRoll(r,"Great Great Great Great Great Great","Great Great Great Great Great")
  eq(r.state.rolls,1); eq(r.state.last.total,77)
  eq(r:onLine("raise <stat>  lower <stat>  reset  done  ? help"),false)
  eq(r:onLine([[A guide says, "reroll done ? help"]]),false)
  local summary=sessionSnapshot(r); eq(summary.rolls,0); eq(summary.stat_rolls,0); eq(summary.pool_rolls,0)
  eq(summary.best_total,nil); eq(summary.average,0); eq(next(r.state.stat_highs),nil); eq(r.state.stat_order,nil)
  for _,row in ipairs(summary.stats) do eq(row.value,nil); eq(row.roll,nil) end
  assert(r:command("stats")); local report=f.messages[#f.messages]
  assert(report:find("Confirmed rolls: 0",1,true)); assert(not report:find("Best:",1,true)); assert(not report:find("Worst:",1,true))
  eq(#f.sent,0); eq(f.next,0)
end)

test("one hundred legacy redraws before a decision prompt produce one confirmed observation",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=false,show_every_roll=false,use_min_stats=true,min_stats={PRE=7}})
  assert(r:start())
  for index=1,100 do
    local labels={}; for slot=1,11 do labels[slot]=index==1 and "Great" or "Good" end
    assert(r:onLine(legacyHeader)); assert(r:onLine(table.concat(labels," ")))
  end
  local provisional=sessionSnapshot(r); eq(r.state.rolls,100); eq(provisional.rolls,0); eq(provisional.stat_rolls,0)
  eq(provisional.best_total,nil); eq(provisional.average,0); eq(next(r.state.stat_highs),nil); eq(noticeCount(f.messages),0)
  assert(r:onLine(legacyPrompt)); local confirmed=sessionSnapshot(r)
  eq(r.state.rolls,100); eq(confirmed.rolls,1); eq(confirmed.stat_rolls,1); eq(confirmed.best_total,66); eq(confirmed.average,66)
  sessionOrderIs(confirmed,sessionLegacyNames)
  for _,row in ipairs(confirmed.stats) do eq(row.value,6); eq(row.label,"Good"); eq(row.roll,1) end
  eq(r:onLine(legacyPrompt),false); eq(r:onLine(legacyPrompt),false); eq(sessionSnapshot(r).rolls,1)
  eq(noticeCount(f.messages),0); eq(#f.sent,0); eq(f.next,1)
  assert(r:command("stats")); local report=f.messages[#f.messages]
  assert(report:find("Confirmed rolls: 1",1,true)); assert(report:find("Total=66/77",1,true)); assert(not report:find("Total=77/77",1,true))
end)

test("ninety nine legacy observations plus one current format do not trigger a hundred roll warning",function()
  local f=fake(); local r=Roller.new(f,{target_total=77,auto_start_on_name=false,show_every_roll=false,use_min_stats=true,min_stats={PRE=7}})
  assert(r:start()); for index=1,99 do recordSessionStats(r,sessionStats(6,sessionLegacyNames),"legacy",sessionLegacyNames) end
  eq(sessionSnapshot(r).stat_rolls,99); eq(noticeCount(f.messages),0)
  recordSessionStats(r,sessionStats(5),"creator",sessionNames)
  local changed=sessionSnapshot(r); eq(changed.rolls,100); eq(changed.stat_rolls,1); eq(changed.best_total,66)
  eq(changed.maximum,77); sessionOrderIs(changed,sessionNames); assert(not changed.warning); eq(noticeCount(f.messages),0)
  eq(r.state.stat_highs.VOI,nil); eq(r.state.stat_highs.APP,nil); eq(r.state.stat_highs.MP,nil)
  for _,row in ipairs(changed.stats) do eq(row.value,5); eq(row.roll,100) end
  for index=1,99 do recordSessionStats(r,sessionStats(5),"creator",sessionNames) end
  local checkpoint=sessionSnapshot(r); eq(checkpoint.rolls,199); eq(checkpoint.stat_rolls,100); assert(checkpoint.warning)
  eq(noticeCount(f.messages),1); eq(#f.sent,0); eq(f.next,0)
end)

test("confirmation requires an active fresh matching capture and publishes each capture once",function()
  local f=fake(); local events={}; local r=Roller.new(f,{target_total=77,auto_start_on_name=false},nil,nil,function(summary) events[#events+1]=summary end)
  assert(r:record(sessionStats(7),"creator",sessionNames)); eq(r:confirmSessionRoll("creator"),false)
  eq(sessionSnapshot(r).rolls,0)
  assert(r:start()); assert(r:record(sessionStats(6),"creator",sessionNames)); local before=#events
  eq(r:confirmSessionRoll("legacy"),false); eq(r:confirmSessionRoll("arrange"),false)
  eq(#events,before); eq(sessionSnapshot(r).rolls,0); eq(next(r.state.stat_highs),nil)
  confirmSession(r,"creator"); eq(#events,before+1); eq(sessionSnapshot(r).rolls,1)
  eq(r:confirmSessionRoll("creator"),false); eq(#events,before+1); eq(sessionSnapshot(r).stat_rolls,1)
  assert(r:onOutgoing("reroll")); before=#events; eq(r:confirmSessionRoll("creator"),false); eq(#events,before)
  assert(r:stop()); eq(r:confirmSessionRoll("creator"),false); eq(sessionSnapshot(r).rolls,1)
  eq(#f.sent,0); eq(f.next,0)
end)

test("full legacy redraw while reroll is pending confirms once until the timer sends n",function()
  local f=fake(); local events={}
  local r=Roller.new(f,{target_total=77,auto_start_on_name=false,show_every_roll=false,reroll_delay=.5},nil,nil,function(summary) events[#events+1]=summary end)
  assert(r:start())
  local function block()
    assert(r:onLine(legacyHeader)); assert(r:onLine("Good Good Good Good Good Good Good Good Good Good Good"))
    assert(r:onLine(legacyPrompt))
  end
  block(); local first=sessionSnapshot(r); eq(first.rolls,1); eq(first.stat_rolls,1); eq(r.state.rolls,1)
  local stale=f.timers[r.state.timer].fn; eq(#f.sent,0)
  block(); local redraw=sessionSnapshot(r)
  eq(r.state.rolls,2); eq(redraw.rolls,1); eq(redraw.stat_rolls,1); eq(redraw.average,66); eq(redraw.best_total,66)
  eq(#f.sent,0); assert(r.state.timer and f.timers[r.state.timer])
  for _,row in ipairs(redraw.stats) do eq(row.value,6); eq(row.roll,1) end
  stale(); eq(#f.sent,0)
  eq(fireSessionTimer(f,r),.5); eq(#f.sent,1); eq(f.sent[1],"n")
  block(); local after=sessionSnapshot(r)
  eq(r.state.rolls,3); eq(after.rolls,2); eq(after.stat_rolls,2); eq(after.average,66); eq(after.best_total,66)
  eq(#f.sent,1); eq(events[#events].rolls,2); eq(events[#events].stat_rolls,2)
  for _,row in ipairs(after.stats) do eq(row.value,6); eq(row.roll,1) end
  eq(r:onLine(legacyPrompt),false); eq(sessionSnapshot(r).rolls,2); eq(#f.sent,1)
  eq(first.rolls,1); eq(first.stat_rolls,1)
  for _,command in ipairs(f.sent) do assert(command~="y" and command~="done") end
end)
