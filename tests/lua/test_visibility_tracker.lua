local Visibility=require("visibility_tracker")
local Parser=require("command_parser")
local biography=[[You are Synthetic Tester, a light boned and muscular bodied 57 year old Entropic Male young Elder. You are 7'7" and weigh 239 lbs.]]
local function fixture()
  local f={stamp=10,changes=0,identity={name="Synthetic",full_name="Synthetic Tester"}}
  function f:epoch() return self.stamp end
  function f:sendCommand() error("visibility must never poll") end
  function f:schedule() error("visibility must never schedule polls") end
  local v=Visibility.new(f,function() f.changes=f.changes+1 end,function() return f.identity end)
  return v,f
end
local function unchanged(v,before)
  for _,field in ipairs({"status","timestamp","source","stale"}) do eq(v:status()[field],before[field]) end
end

test("visibility exact confirmed self notices accept ANSI BEL and game prompts",function()
  for _,decorate in ipairs({
    function(s) return s end,
    function(s) return " \t\27[32m"..s.."\27[0m\7 " end,
    function(s) return "> "..s end,
    function(s) return "\7\27[32m[199] 299/299 hp, 188/188 ftg >"..s.."\27[0m" end,
  }) do
    local v,f=fixture(); eq(v:status().status,"unknown"); eq(v:status().stale,false)
    for _,step in ipairs({{"You slip into the shadows!","hidden"},
      {"You are already unable to be seen!","hidden"},{"You reveal yourself!","visible"},
      {"You are hidden.","hidden"},{"You are visible.","visible"}}) do
      assert(v:onLine(decorate(step[1]),"game")); local s=v:status()
      eq(s.status,step[2]); eq(s.timestamp,10); eq(s.source,"game"); eq(s.stale,false)
    end
    eq(f.changes,5)
  end
end)

test("October 14 own invisible INFO confirms hidden visibility only for the active self",function()
  -- New Oct 14 staff file, lines 138-154. Biography name is synthetic.
  for _,foreign in ipairs({false,true}) do
    local v=fixture()
    local own=foreign and biography:gsub("Synthetic Tester","Other Tester") or biography
    local lines={own.." You are invisible. You are", "satiated. Your thirst is quenched.","",
      "HP: 299 of 299 Ftg: 188 of 188 Psi: 40 of 40 Carry: 663.2 of 6553.5 lbs.","",
      "Str Int Wis Dex Agi Con Cha Wil Pre Per Luk MP",
      "Super Super Super Super Super Super Super Super Super Super Super Super",">"}
    for index=1,#lines-1 do eq(v:onLine(lines[index]),false) end
    eq(v:onLine(">"),not foreign); eq(v:status().status,foreign and "unknown" or "hidden")
    local direct=fixture(); eq(direct:onInfo(assert(Parser.parseInfo(lines))),not foreign)
    eq(direct:status().status,foreign and "unknown" or "hidden")
  end
end)

test("latest staff hide own INFO reveal INFO omission and failed hide sequence is conservative",function()
  -- Oct 5-named staff file, updated Oct 14, lines 144747-144799. Names sanitized.
  local v,f=fixture()
  eq(v:onLine("You fail in your attempt to hide!"),false); eq(v:status().status,"unknown")
  assert(v:onLine("You slip into the shadows!")); eq(v:status().status,"hidden")
  v:onLine(biography.." You are hidden. You are satiated.")
  v:onLine("Your thirst is quenched."); assert(v:onLine(">")); eq(v:status().source,"output")
  assert(v:onLine("You reveal yourself!")); eq(v:status().status,"visible")
  eq(v:onLine("Usage: REVEAL <target>"),false)
  local before=v:status(); f.stamp=11
  for _,line in ipairs({biography.." You are satiated. Your thirst is","quenched.",">",
      "You fail in your attempt to hide!"}) do eq(v:onLine(line),false) end
  unchanged(v,before)
end)

test("failed hide movement combat and ambiguous output never confirm visible",function()
  for _,seed in ipairs({false,true}) do
    local v=fixture(); if seed then v:onLine("You slip into the shadows!") end
    local before=v:status()
    for _,line in ipairs({"You fail in your attempt to hide!","You cannot hide here!",
      "You notice Synthetic Guard slip into the shadows!","Synthetic Guard reveals himself!",
      "You attack the guard.","You move north.","Obvious paths: north south.",
      "You are no longer", "hidden.","You reveal yourself",">hide",">reveal"}) do
      eq(v:onLine(line),false); unchanged(v,before)
    end
  end
end)

test("visibility quoted chat NPC and room prose cannot spoof self notices",function()
  local v=fixture(); v:onLine("You reveal yourself!"); local before=v:status()
  for _,phrase in ipairs({"You slip into the shadows!","You are already unable to be seen!",
      "You are hidden.","You are invisible.","You reveal yourself!","You are visible."}) do
    for _,line in ipairs({'Synthetic Guard says, "'..phrase..'"',
      "Synthetic Guard tells you, '"..phrase.."'",'[CHAT] Synthetic: '..phrase,
      'You say, "'..phrase..'"',"A plaque reads. "..phrase,
      '"'..phrase..'"',"'"..phrase.."'",phrase.." says the guard."}) do
      eq(v:onLine("\27[32m> "..line.."\27[0m"),false); unchanged(v,before)
    end
  end
end)

test("visibility only independently confirmed own INFO can apply conditions",function()
  local v,f=fixture(); local own=assert(Parser.parseInfo({biography.." You are hidden.",">"}))
  assert(v:onInfo(own,"collector")); eq(v:status().status,"hidden"); eq(v:status().source,"collector")
  local before=v:status(); f.stamp=11
  local foreign=assert(Parser.parseInfo({biography:gsub("Synthetic Tester","Other Tester").." You are visible.",">"}))
  eq(v:onInfo(foreign),false); unchanged(v,before)
  for _,conditions in ipairs({"","You are seated.",[[Synthetic Guard says, "You are visible."]],
      [[You are seated. 'You are hidden.']],"You are hidden. You are"}) do
    eq(v:onInfo({character={full_name="Synthetic Tester"},condition_text=conditions}),false); unchanged(v,before)
  end
  eq(v:onInfo({condition_text="You are hidden."}),false)
  eq(v:onInfo({character={full_name="Synthetic Tester"}}),false)
  local unknown=Visibility.new(f)
  eq(unknown:onInfo(own),false); eq(unknown:status().status,"unknown")
end)

test("visibility wrapped quoted speech and chat cannot spoof standalone or INFO conditions",function()
  for _,frame in ipairs({{[[Synthetic Guard says, "Listen:]],'"'},
      {"Synthetic Guard tells you, 'You're listening:","'"},
      {"Synthetic Guard says, “Listen:","”"},{"[CHAT] Synthetic: Listen:",">"}}) do
    local v=fixture(); v:onLine("You reveal yourself!"); local before=v:status()
    eq(v:onLine(frame[1]),false)
    eq(v:onLine("You are hidden."),false); eq(v:onLine("You slip into the shadows!"),false)
    eq(v:onLine("You're still listening."),false)
    eq(v:onLine(biography.." You are hidden."),false)
    eq(v:onLine(frame[2]),false); unchanged(v,before)
    assert(v:onLine("You slip into the shadows!")); eq(v:status().status,"hidden")
  end
end)

test("visibility wrapped own INFO waits for its prompt and ignores foreign continuations",function()
  for _,foreign in ipairs({false,true}) do
    local v=fixture(); local full=foreign and "Other Tester" or "Synthetic Tester"
    local lines={"You are "..full..", a light boned and muscular bodied",
      [[57 year old Entropic Male young Elder. You are 7'7" and weigh 239 lbs. You are]],
      "hidden. You are satiated.","Your thirst is quenched.","",
      "HP: 299 of 299 Ftg: 188 of 188",">"}
    for index=1,#lines-1 do eq(v:onLine("\7\27[32m"..lines[index].."\27[0m"),false); eq(v:status().status,"unknown") end
    eq(v:onLine(">"),not foreign); eq(v:status().status,foreign and "unknown" or "hidden")
  end
end)

test("visibility collector-owned INFO lines cannot apply standalone conditions early",function()
  local v=fixture()
  for _,line in ipairs({biography,"You are hidden.","You reveal yourself!",">"}) do
    eq(v:onLine(line,"game",false),false)
  end
  eq(v:status().status,"unknown")
  assert(v:onInfo(assert(Parser.parseInfo({biography,"You are hidden.",">"}))))
  eq(v:status().status,"hidden")
end)

test("visibility staleness preserves last confirmation and partial INFO cannot freshen it",function()
  local v,f=fixture(); v:onLine("You slip into the shadows!"); f.stamp=309; eq(v:status().stale,false)
  f.stamp=310; eq(v:status().stale,true); local before=v:status()
  eq(v:onInfo(assert(Parser.parseInfo({"HP: 299 of 299",">"}))),false)
  eq(v:onInfo(assert(Parser.parseInfo({biography.." You are satiated.",">"}))),false)
  eq(v:onLine("You fail in your attempt to hide!"),false); unchanged(v,before)
  assert(v:setStaleAfter(600)); eq(v:status().stale,false)
  for _,invalid in ipairs({0,-1,"invalid",math.huge}) do eq(v:setStaleAfter(invalid),false) end
  eq(v:setStaleAfter(0/0),false)
  f.stamp=611; eq(v:status().stale,true); assert(v:onLine("You reveal yourself!")); eq(v:status().stale,false)
end)

test("visibility stale and oversized INFO discard every continuation until a prompt",function()
  for _,mode in ipairs({"stale","lines","bytes","multiple"}) do
    local v,f=fixture(); v:onLine("You reveal yourself!"); local before=v:status()
    v:onLine(biography)
    if mode=="stale" then f.stamp=311
    elseif mode=="lines" then for _=1,64 do v:onLine("Harmless INFO detail.") end
    elseif mode=="bytes" then v:onLine(string.rep("x",16385))
    else v:onLine(biography) end
    eq(v:onLine("You are hidden."),false); eq(v:onLine(">"),false)
    eq(v:status().status,before.status); eq(v:status().timestamp,before.timestamp)
    v:onLine(biography.." You are hidden."); assert(v:onLine(">")); eq(v:status().status,"hidden")
  end
end)

test("visibility accepts complete INFO exactly at its line and byte caps",function()
  for _,mode in ipairs({"lines","bytes"}) do
    local v=fixture(); local first=biography.." You are hidden."
    v:onLine(first)
    if mode=="lines" then for _=1,62 do v:onLine("") end
    else v:onLine("HP:"..string.rep("x",16384-#first-1-3)) end
    assert(v:onLine(">")); eq(v:status().status,"hidden")
  end
end)

test("visibility character changes disconnect and explicit reset clear state and pending INFO",function()
  local v,f=fixture(); v:onLine("You slip into the shadows!"); v:onLine(biography)
  f.identity={name="Other",full_name="Other Tester"}; eq(v:status().status,"unknown"); eq(v.pending_info,nil)
  eq(v:onLine("You are hidden."),false); eq(v:onLine(">"),false); eq(v:status().status,"unknown")
  eq(v:onInfo(assert(Parser.parseInfo({biography.." You are hidden.",">"}))),false)
  v:onLine("You reveal yourself!"); f.identity=nil
  local s=v:status(); eq(s.status,"unknown"); eq(s.timestamp,nil); eq(s.source,nil); eq(s.stale,false)
  eq(v:onLine("You reveal yourself!"),false); eq(v:onLine("You are hidden."),false)
  eq(v:status().status,"unknown")
  f.identity="Synthetic"; assert(v:onInfo(assert(Parser.parseInfo({biography.." You are hidden.",">"}))))
  assert(v:reset()); eq(v:status().status,"unknown")
  s=v:status(); s.status="hidden"; eq(v:status().status,"unknown")
end)

test("visibility rejected INFO and explicit reset cannot release a pending foreign biography tail",function()
  for _,reset in ipairs({false,true}) do
    local v=fixture()
    v:onLine(biography:gsub("Synthetic Tester","Other Tester"))
    if reset then v:reset()
    else eq(v:onInfo({character={full_name="Other Tester"},condition_text="You are hidden."}),false) end
    eq(v:onLine("You are hidden."),false); eq(v:onLine(">"),false)
    eq(v:status().status,"unknown"); assert(v:onLine("You slip into the shadows!"))
  end
end)

test("visibility independent GMCP name and surname require an exact full name",function()
  local v,f=fixture(); f.identity={name="Synthetic",surname="Tester"}
  assert(v:onInfo(assert(Parser.parseInfo({biography.." You are hidden.",">"}))))
  local before=v:status()
  eq(v:onInfo(assert(Parser.parseInfo({biography:gsub("Synthetic Tester","Synthetic Other").." You are visible.",">"}))),false)
  unchanged(v,before)
end)
