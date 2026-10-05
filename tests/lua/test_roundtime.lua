local Roundtime=require("roundtime")
local function tracker()
  local now=100
  local rt=Roundtime.new(function() return now end)
  return rt,function(value) now=value end
end
test("roundtime adds distinct printed double claws and fumble penalties",function()
  for _,pair in ipairs({{7,7},{4,4},{3,2},{3,4},{5,2},{5,4},{7,2},{7,4}}) do
    local rt=tracker(); eq(rt:text(pair[1]),pair[1]); eq(rt:text(pair[2]),pair[1]+pair[2])
  end
end)
test("roundtime reconciles text before GMCP without charging twice",function()
  local rt=tracker(); rt:gmcp(0); eq(rt:text(7),7); eq(rt:gmcp(7),7)
  eq(rt:text(2),9); eq(rt:gmcp(9),9)
end)
test("roundtime reconciles GMCP before printed delays without charging twice",function()
  local rt=tracker(); eq(rt:gmcp(9),9); eq(rt:text(7),9); eq(rt:text(2),9)
end)
test("roundtime reconciles interleaved base and penalty snapshots",function()
  local rt=tracker(); eq(rt:text(7),7); eq(rt:gmcp(9),9); eq(rt:text(2),9)
end)
test("unchanged cached GMCP cannot restart the countdown after expiry",function()
  local rt,clock=tracker(); rt:gmcp(3); clock(101); eq(rt:gmcp(3),2)
  clock(104); eq(rt:gmcp(3),0); eq(rt:gmcp(nil),0)
end)
test("unrelated missing or invalid roundtime leaves the deadline alone",function()
  local rt=tracker(); rt:text(7)
  for _,bad in ipairs({"bad",-1,math.huge,0/0,86401}) do eq(rt:gmcp(bad),7); eq(rt:text(bad),7) end
  eq(rt:gmcp(nil),7)
end)
test("stale shorter snapshots within the text burst do not erase fumble penalties",function()
  local rt=tracker(); rt:text(7); rt:text(2); eq(rt:gmcp(7),9)
end)
test("fresh GMCP remaining time is authoritative after the output burst",function()
  local rt,clock=tracker(); rt:text(7); rt:text(2); clock(102); eq(rt:gmcp(3),3)
  eq(rt:gmcp(0),0)
end)
test("positive snapshots followed by their text are deduplicated during existing RT",function()
  local rt,clock=tracker(); rt:gmcp(3); clock(101); eq(rt:gmcp(5),5); eq(rt:text(5),5)
end)
test("roundtime accounts for time elapsed between delays and late timers",function()
  local rt,clock=tracker(); rt:text(7); clock(102); eq(rt:text(2),7)
  clock(108); eq(rt:tick(),1); clock(111); eq(rt:tick(),0)
end)
test("roundtime resets source credits between characters",function()
  local rt=tracker(); rt:gmcp(7); rt:reset(); eq(rt:display(),0)
  eq(rt:text(7),7); eq(rt:gmcp(7),7)
end)
test("clock reads just before a tick cannot expire roundtime one second early",function()
  for _,start in ipairs({100,100.25}) do
    local rt,clock=tracker(); clock(start); rt:text(7)
    clock(start+6); eq(rt:gmcp(nil),1); eq(rt:tick(),1)
    clock(start+7); eq(rt:tick(),0)
  end
end)
test("interleaved snapshots retain unconsumed double claw and fumble credit",function()
  for _,pair in ipairs({{7,7},{7,2},{7,4}}) do
    local rt=tracker(); local total=pair[1]+pair[2]
    rt:gmcp(total); rt:text(pair[1]); rt:gmcp(pair[1])
    eq(rt:text(pair[2]),total)
  end
  local rt=tracker(); rt:gmcp(7); rt:text(3); rt:gmcp(9)
  eq(rt:text(4),9); eq(rt:text(2),9)
end)
test("update handoff preserves an expired snapshot and elapsed active deadline",function()
  local old,clock=tracker(); old:gmcp(7); clock(102)
  local fresh,newClock=tracker(); newClock(103); assert(fresh:restore(old:handoff()))
  eq(fresh:display(),4); eq(fresh:gmcp(7),4)
  newClock(108)
  local actual,nextClock=tracker(); nextClock(108); assert(actual:restore(fresh:handoff()))
  eq(actual:display(),0); eq(actual:gmcp(7),0)
end)
test("invalid roundtime handoffs do not mutate the current countdown",function()
  local rt=tracker(); rt:text(5)
  for _,snapshot in ipairs({{}, {schema=2,deadline=101}, {schema=1,deadline=math.huge},
      {schema=1,deadline=-1}, {schema=1,deadline=101,last_gmcp="bad"}}) do
    eq(rt:restore(snapshot),false); eq(rt:display(),5)
  end
end)
test("an immediate reload preserves unconsumed snapshot credit and text correlation",function()
  for _,pair in ipairs({{7,7},{7,2},{7,4}}) do
    local old=tracker(); old:gmcp(pair[1]+pair[2]); old:text(pair[1])
    local fresh=tracker(); assert(fresh:restore(old:handoff()))
    eq(fresh:text(pair[2]),pair[1]+pair[2])
  end
  local old=tracker(); old:text(7); old:text(2)
  local fresh=tracker(); assert(fresh:restore(old:handoff()))
  eq(fresh:gmcp(7),9)
end)
test("handoff rejects invalid reconciliation timestamps and credits",function()
  local rt=tracker(); rt:text(5)
  for _,snapshot in ipairs({{schema=1,deadline=107,credit=-1}, {schema=1,deadline=107,credit=7},
      {schema=1,deadline=107,credit_at=math.huge}, {schema=1,deadline=107,text_at=0/0},
      {schema=1,deadline=107,text_at=102}}) do
    eq(rt:restore(snapshot),false); eq(rt:display(),5)
  end
end)
