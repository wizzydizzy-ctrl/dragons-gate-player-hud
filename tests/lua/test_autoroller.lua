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
  assert(r:onLine(firstHeader)); eq(f.timers[1],nil); eq(r.state.timer,nil)
end)

test("manual start captures the new split layout immediately",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,reroll_delay=0,auto_start_on_name=false}); assert(r:start())
  newRoll(r,"Low Low Low Low Low Low","Low Low Low Low Low Low"); eq(r.state.rolls,1); assert(r:onLine(creatorPrompt)); f.timers[1].fn(); eq(f.sent[1],"reroll")
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
