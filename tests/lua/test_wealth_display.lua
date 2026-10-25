local Display=require("wealth_display")

-- Amounts from the requested 29-row example, deliberately detached from all
-- player identities. Everything else in this file is synthetic test input.
local suppliedAmounts={
  "1506","8402","125","19127","15368","2294","35529","20","935","15134",
  "776905","6118","19434","239934","7","15415","5869","0","100002","8284",
  "1449","0","4599","22","641","16693","0","33353","9159",
}
local suppliedOrder={11,14,19,7,28,13,4,26,16,5,10,29,2,20,12,17,23,6,1,21,9,25,3,24,8,15,18,22,27}
local function fixtureName(index) return string.format("Fixture %02d",index) end
local function raw(name,amount) return name.." has "..amount.." silver" end
local function count(values) local n=0; for _ in pairs(values) do n=n+1 end; return n end
local function grouped(digits)
  local parts={}
  while #digits>3 do table.insert(parts,1,digits:sub(-3)); digits=digits:sub(1,-4) end
  table.insert(parts,1,digits); return table.concat(parts,",")
end
local function checkTable(lines,expected)
  eq(#lines,#expected+1)
  assert(lines[1]:match("^Name%s%s+Silver$"),"expected exactly Name and Silver columns")
  local width=#lines[1]
  for index,item in ipairs(expected) do
    local text=lines[index+1]
    eq(type(text),"string"); eq(#text,width,"Silver must share a right edge")
    local name,amount=text:match("^(.-)%s%s+(%d[%d,]*)$")
    eq(name,item.name); eq(amount,grouped(item.silver))
    assert(not text:find("[%c<>]"),"plain two-column text only")
  end
end
local function newFake(packageName,autoStart)
  local f={next=0,events={},triggers={},timers={},history={},batches={},clock=0,maxTimers=0,lines={}}
  function f:addWealthDisplayTrigger(fn)
    if self.failTrigger then return nil,"synthetic trigger failure" end
    self.next=self.next+1; local id="wealth-trigger-"..self.next; self.triggers[id]=fn; self.trigger=fn; return id
  end
  function f:killTrigger(id) self.triggers[id]=nil end
  function f:addEvent(event,fn)
    if self.failEvent then return nil,"synthetic event failure" end
    self.next=self.next+1; self.events[self.next]={event=event,fn=fn}; return self.next
  end
  function f:killEvent(id) self.events[id]=nil end
  function f:emit(event,...)
    local handlers={}; for _,item in pairs(self.events) do if item.event==event then handlers[#handlers+1]=item.fn end end
    for _,fn in ipairs(handlers) do fn(...) end
  end
  function f:schedule(delay,fn)
    if self.failSchedule then return nil,"synthetic timer failure" end
    self.next=self.next+1; local id=self.next
    local timer={delay=delay,at=self.clock+delay,fn=fn}
    self.timers[id]=timer; self.history[#self.history+1]=timer
    self.maxTimers=math.max(self.maxTimers,count(self.timers)); return id
  end
  function f:cancelTimer(id) self.timers[id]=nil end
  function f:advance(seconds)
    local target=self.clock+seconds
    for _=1,32 do
      local chosen
      for id,item in pairs(self.timers) do
        if item.at<=target and (not chosen or item.at<self.timers[chosen].at
            or (item.at==self.timers[chosen].at and id<chosen)) then chosen=id end
      end
      if not chosen then self.clock=target; return end
      local item=self.timers[chosen]; self.timers[chosen]=nil; self.clock=item.at; item.fn()
    end
    error("unbounded synthetic wealth timers")
  end
  function f:replaceWealthOutput(rows)
    self.batches[#self.batches+1]=rows
    if self.failReplace then error("synthetic replacement failure") end
    return true
  end
  -- Sensitive output must never cause any transmission, disk write, or chat copy.
  for _,method in ipairs({"sendCommand","send","saveSettings","saveWealth","appendChat","createChatStorage",
      "saveChatSettings","submitFeedback","fetchMapCatalog","downloadFile"}) do
    f[method]=function() error("wealth display attempted forbidden side effect: "..method) end
  end
  local d=Display.new(f,packageName or "SyntheticHUD")
  function f:feed(text,row)
    if type(row)=="number" and row==row and row>=0 and row<math.huge then self.lines[row]=text end
    return self.trigger(text,row)
  end
  if autoStart~=false then assert(d:start()) end
  return f,d
end
local function complete(f,d,first)
  first=first or 10
  d:onOutgoing("breakd wealth")
  f:feed(raw("Synthetic Low","0"),first)
  f:feed(raw("Synthetic High","1200"),first+1)
  f:feed("Done.",first+2)
end
local function allLate(f) for _,timer in ipairs(f.history) do timer.fn() end end
local function assertUntouched(f)
  eq(#f.batches,0); eq(next(f.timers),nil)
end

test("wealth constants bound every response resource",function()
  eq(Display.MAX_ROWS,512); eq(Display.MAX_LINES,1024); eq(Display.MAX_LINE_BYTES,512)
  eq(Display.MAX_AMOUNT_DIGITS,32); eq(Display.RESPONSE_TIMEOUT,5)
end)

test("wealth command accepts only the two exact case-insensitive tokens with spaces or tabs",function()
  for _,command in ipairs({"breakd wealth","breakdown wealth"," BREAKD WEALTH ","\tBrEaKd\twealth\t",
      "  breakdown \t WEALTH  "}) do eq(Display.isCommand(command),true) end
end)

test("wealth command rejects batches extra arguments prefixes and every other control byte",function()
  for _,command in ipairs({"","breakd","wealth","breakdwealth","break wealth","breakdown wealth extra",
      "breakd wealth;look","look;breakd wealth","breakd wealth|look","breakd wealth&&look",
      "> breakd wealth","say breakd wealth","breakdowns wealth","breakd  wealthy","breakd wealth\n",
      "\rbreakd wealth","breakd\nwealth","breakd wealth\27[0m"}) do eq(Display.isCommand(command),false) end
  for byte=0,31 do
    if byte~=9 then
      local control=string.char(byte)
      eq(Display.isCommand(control.."breakd wealth"),false)
      eq(Display.isCommand("breakd"..control.."wealth"),false)
      eq(Display.isCommand("breakd wealth"..control),false)
    end
  end
  eq(Display.isCommand("breakd wealth"..string.char(127)),false)
  for _,value in ipairs({false,42,{}}) do eq(Display.isCommand(value),false) end
  eq(Display.isCommand(nil),false)
end)

test("wealth rows parse complete native syntax into canonical decimal strings",function()
  for _,case in ipairs({
    {"Synthetic has 0 silver","Synthetic","0"},
    {" Fixture 01 has 0001200 silver ","Fixture 01","1200"},
    {"O'Fixture-Test_2 has 000 silver","O'Fixture-Test_2","0"},
    {"Long Synthetic Name has 9007199254740993 silver","Long Synthetic Name","9007199254740993"},
    {"Fixture has "..string.rep("9",32).." silver","Fixture",string.rep("9",32)},
  }) do
    local row=assert(Display.parseRow(case[1])); eq(row.name,case[2]); eq(row.silver,case[3]); eq(type(row.silver),"string")
  end
end)
test("wealth parser handles ANSI BEL and trailing CRLF without emitting controls",function()
  local row=assert(Display.parseRow("\27[32mFixture 01\27[0m has 001234 silver\7\r\n"))
  eq(row.name,"Fixture 01"); eq(row.silver,"1234")
end)

test("wealth parser rejects malformed negative fractional grouped overflow and embedded records",function()
  for _,text in ipairs({
    "Fixture has -1 silver","Fixture has +1 silver","Fixture has 1.5 silver","Fixture has 1e6 silver",
    "Fixture has 1,000 silver","Fixture has 1 000 silver","Fixture has silver","Fixture has 1 gold",
    "Fixture has 1 silver extra","Fixture has "..string.rep("9",33).." silver",
    "Fixture has 1 silver\nOther has 2 silver","Fixture\0 has 1 silver","<Fixture> has 1 silver",
    string.rep("A",81).." has 1 silver",string.rep(" ",513).."Fixture has 1 silver",
  }) do eq(Display.parseRow(text),nil,text) end
  eq(Display.parseRow(nil),nil); eq(Display.parseRow({}),nil); eq(Display.parseRow(12),nil)
end)

test("wealth formats all 29 anonymized supplied amounts with zeros stable and aligned",function()
  eq(#suppliedAmounts,29); eq(#suppliedOrder,29)
  local items,expected,original={},{},{}
  for index,amount in ipairs(suppliedAmounts) do
    items[index]={name=fixtureName(index),silver=amount}; original[index]=items[index]
  end
  for _,index in ipairs(suppliedOrder) do expected[#expected+1]={name=fixtureName(index),silver=suppliedAmounts[index]} end
  checkTable(Display.formatRows(items),expected)
  for index,item in ipairs(items) do
    eq(item,original[index]); eq(item.name,fixtureName(index)); eq(item.silver,suppliedAmounts[index]); eq(count(item),2)
  end
end)

test("wealth compares large decimal strings exactly above double precision and at 32 digits",function()
  local items={
    {name="Tiny Nine",silver="9"},{name="Large Lower",silver="9007199254740992"},
    {name="Max Lower",silver="99999999999999999999999999999998"},
    {name="Tiny Ten",silver="10"},{name="Large Higher",silver="9007199254740993"},
    {name="Max Higher",silver="99999999999999999999999999999999"},
  }
  checkTable(Display.formatRows(items),{items[6],items[3],items[5],items[2],items[4],items[1]})
end)

test("wealth equal silver preserves original nonalphabetical order including zero balances",function()
  local items={{name="Zulu Synthetic",silver="5"},{name="Alpha Synthetic",silver="5"},
    {name="Zero Zulu",silver="0"},{name="Zero Alpha",silver="0"}}
  checkTable(Display.formatRows(items),items)
end)

test("wealth formats empty and single-row responses using only two columns",function()
  local lines=Display.formatRows({}); eq(#lines,1); assert(lines[1]:match("^Name%s%s+Silver$"))
  checkTable(Display.formatRows({{name="Synthetic",silver="0"}}),{{name="Synthetic",silver="0"}})
end)

test("wealth startup idempotence and shutdown preserve unrelated handlers",function()
  local f,d=newFake(nil,false)
  local personal=f:addEvent("sysDisconnectionEvent",function() end)
  f.triggers.personal=function() end
  d:onOutgoing("breakd wealth"); d:onLine(raw("Synthetic","1"),1); d:onLine("Done.",2)
  eq(#f.history,0); eq(#f.batches,0)
  assert(d:start()); local nextId=f.next; assert(d:start()); eq(f.next,nextId)
  eq(next(f.timers),nil)
  complete(f,d); d:shutdown(); d:shutdown(); allLate(f)
  eq(count(f.events),1); assert(f.events[personal]); eq(count(f.triggers),1); assert(f.triggers.personal)
  assertUntouched(f)
end)

test("wealth ignores unsolicited and echoed commands without an outgoing observation",function()
  local f,d=newFake()
  f:feed("breakd wealth",1); f:feed("> breakd wealth",2)
  f:feed(raw("Synthetic","99"),3); f:feed("Done.",4); f:advance(0)
  eq(#f.history,0); assertUntouched(f); d:shutdown()
end)

test("wealth refused command batches never arm a response",function()
  for _,command in ipairs({"breakd wealth;look","breakd wealth\nlook","breakdown wealth extra",
      "say breakd wealth","breakd wealth\r"}) do
    local f,d=newFake(); d:onOutgoing(command)
    f:feed(raw("Synthetic","99"),1); f:feed("Done.",2); f:advance(0)
    eq(#f.history,0); assertUntouched(f); d:shutdown()
  end
end)

test("wealth collects the full 29-row fixture then defers exactly one N plus Done slot rewrite",function()
  local f,d=newFake(); d:onOutgoing("\tBREAKDOWN \t wealth ")
  for index,amount in ipairs(suppliedAmounts) do f:feed(raw(fixtureName(index),amount),index+10) end
  eq(#f.batches,0); eq(count(f.timers),1)
  f:feed("Done.",40); eq(#f.batches,0); eq(count(f.timers),1)
  local _,timer=next(f.timers); eq(timer.delay,0)
  f:advance(0); eq(#f.batches,1); eq(next(f.timers),nil)
  local batch=f.batches[1]; eq(#batch,30)
  local lines,expected={},{}
  for index,row in ipairs(batch) do
    eq(row.line_number,index+10); eq(row.source_line,index==30 and "Done." or raw(fixtureName(index),suppliedAmounts[index]))
    eq(row.remove,nil); lines[index]=row.display_text
  end
  for _,index in ipairs(suppliedOrder) do expected[#expected+1]={name=fixtureName(index),silver=suppliedAmounts[index]} end
  checkTable(lines,expected)
  f:feed("Done.",41); f:advance(0); eq(#f.batches,1); d:shutdown()
end)

test("wealth interleaved chat and prose are excluded from replacement slots",function()
  local f,d=newFake(); d:onOutgoing("breakd wealth")
  f:feed(raw("Synthetic Low","0"),10)
  f:feed('Synthetic Voice says, "hello".',11); f:feed("A distant bell rings.",12); f:feed("A door opens.",13)
  f:feed(raw("Synthetic High","1200"),16); f:feed("Done.",20); f:advance(0)
  eq(#f.batches,1); local rows=f.batches[1]
  eq(#rows,3); eq(rows[1].line_number,10); eq(rows[2].line_number,16); eq(rows[3].line_number,20)
  eq(rows[1].source_line,raw("Synthetic Low","0")); eq(rows[2].source_line,raw("Synthetic High","1200")); eq(rows[3].source_line,"Done.")
  checkTable({rows[1].display_text,rows[2].display_text,rows[3].display_text},
    {{name="Synthetic High",silver="1200"},{name="Synthetic Low",silver="0"}})
  eq(f.lines[11],'Synthetic Voice says, "hello".'); eq(f.lines[12],"A distant bell rings."); eq(f.lines[13],"A door opens.")
  d:shutdown()
end)

test("wealth decorated rows normalize source guards while waiting for exact Done",function()
  local f,d=newFake(); d:onOutgoing("breakd wealth")
  f:feed("\27[32mSynthetic\27[0m has 1234 silver\7\r\n",1)
  f:feed("\27[0mDone.\7\r\n",2); f:advance(0)
  eq(#f.batches,1); eq(f.batches[1][1].source_line,"Synthetic has 1234 silver"); eq(f.batches[1][2].source_line,"Done.")
  checkTable({f.batches[1][1].display_text,f.batches[1][2].display_text},{{name="Synthetic",silver="1234"}})
  d:shutdown()
end)

test("wealth incomplete responses and near Done text never trigger replacement",function()
  for _,ending in ipairs({false,"","Done","DONE.","Done. extra",">"}) do
    local f,d=newFake(); d:onOutgoing("breakd wealth"); f:feed(raw("Synthetic","1"),1)
    if ending then f:feed(ending,2) end
    f:advance(4.99); eq(#f.batches,0); f:advance(.01); allLate(f); assertUntouched(f); d:shutdown()
  end
end)

test("wealth timeout expires five seconds after manual request even without rows",function()
  local f,d=newFake(); d:onOutgoing("breakd wealth")
  eq(count(f.timers),1); local _,timer=next(f.timers); eq(timer.delay,5)
  f:advance(5); f:feed(raw("Synthetic","1"),1); f:feed("Done.",2); f:advance(0)
  assertUntouched(f); d:shutdown()
end)

test("wealth traffic does not extend the response deadline",function()
  local f,d=newFake(); d:onOutgoing("breakd wealth"); f:advance(4)
  f:feed(raw("Synthetic","1"),1); f:feed("Unrelated prose",2); f:advance(1)
  f:feed("Done.",3); f:advance(0); assertUntouched(f); d:shutdown()
end)

test("wealth Done without any rows leaves native output alone",function()
  local f,d=newFake(); d:onOutgoing("breakd wealth"); f:feed("Done.",1); f:advance(0)
  assertUntouched(f); d:shutdown()
end)

test("wealth any outgoing command invalidates collection and a deferred generation",function()
  for _,phase in ipairs({"collecting","pending"}) do
    for _,command in ipairs({"look","breakd wealth;look","breakdown wealth extra"}) do
      local f,d=newFake(); d:onOutgoing("breakd wealth"); f:feed(raw("Synthetic","1"),1)
      if phase=="pending" then f:feed("Done.",2) end
      d:onOutgoing(command); f:feed("Done.",3); allLate(f); assertUntouched(f); d:shutdown()
    end
  end
end)

test("wealth blank outgoing prompt nudges preserve observed collection and deferred work",function()
  for _,phase in ipairs({"collecting","pending"}) do
    for _,command in ipairs({""," ","\t"," \t "}) do
      local f,d=newFake(); d:onOutgoing("breakd wealth"); f:feed(raw("Synthetic","1"),1)
      if phase=="pending" then f:feed("Done.",2) end
      d:onOutgoing(command)
      if phase=="collecting" then f:feed("Done.",2) end
      f:advance(0); eq(#f.batches,1); d:shutdown()
    end
  end
end)

test("wealth exact prompt before Done cancels collection and leaves the incomplete report raw",function()
  for _,prompt in ipairs({">","\27[0m>"}) do
    local f,d=newFake(); d:onOutgoing("breakd wealth"); f:feed(raw("Synthetic","1"),1)
    f:feed(prompt,2); f:feed("Done.",3); allLate(f); assertUntouched(f); d:shutdown()
  end
end)

test("wealth repeated manual command cancels stale generations and replaces only the new report",function()
  for _,phase in ipairs({"waiting","collecting","pending"}) do
    local f,d=newFake(); d:onOutgoing("breakd wealth")
    if phase~="waiting" then f:feed(raw("Old Synthetic","999"),1) end
    if phase=="pending" then f:feed("Done.",2) end
    local late={}; for _,timer in ipairs(f.history) do late[#late+1]=timer.fn end
    d:onOutgoing("breakdown wealth")
    for _,fn in ipairs(late) do fn() end
    eq(#f.batches,0); eq(count(f.timers),1)
    f:feed(raw("New Synthetic","2"),10); f:feed("Done.",11); f:advance(0)
    eq(#f.batches,1); eq(#f.batches[1],2); eq(f.batches[1][1].line_number,10)
    assert(f.batches[1][2].display_text:find("New Synthetic",1,true)); d:shutdown()
  end
end)

test("wealth menu creator and welcome boundaries cancel collected or deferred output",function()
  for _,line in ipairs({"Dragon's Gate Menu","Dragon's Gate Character Creator","Welcome to Dragon's Gate, Synthetic!"}) do
    for _,phase in ipairs({"collecting","pending"}) do
      local f,d=newFake(); d:onOutgoing("breakd wealth"); f:feed(raw("Synthetic","1"),1)
      if phase=="pending" then f:feed("Done.",2) end
      f:feed(line,3); f:feed("Done.",4); allLate(f); assertUntouched(f); d:shutdown()
    end
  end
end)

test("wealth disconnect and owning package install uninstall invalidate every response phase",function()
  for _,event in ipairs({"sysDisconnectionEvent","sysInstallPackage","sysUninstallPackage"}) do
    for _,phase in ipairs({"waiting","collecting","pending"}) do
      local f,d=newFake("SyntheticHUD"); d:onOutgoing("breakd wealth")
      if phase~="waiting" then f:feed(raw("Synthetic","1"),1) end
      if phase=="pending" then f:feed("Done.",2) end
      f:emit(event,event,"SyntheticHUD"); f:feed("Done.",3); allLate(f); assertUntouched(f); d:shutdown()
    end
  end
end)

test("wealth unrelated packages do not cancel an observed manual response",function()
  local f,d=newFake("SyntheticHUD"); d:onOutgoing("breakd wealth")
  f:emit("sysInstallPackage","sysInstallPackage","OtherHUD"); f:emit("sysUninstallPackage","sysUninstallPackage","OtherHUD")
  f:feed(raw("Synthetic","1"),1); f:feed("Done.",2); f:advance(0); eq(#f.batches,1); d:shutdown()
end)

test("wealth explicit cancel and shutdown invalidate late callbacks without flushing raw output",function()
  for _,method in ipairs({"cancel","shutdown"}) do
    for _,phase in ipairs({"waiting","collecting","pending"}) do
      local f,d=newFake(); d:onOutgoing("breakd wealth")
      if phase~="waiting" then f:feed(raw("Synthetic","1"),1) end
      if phase=="pending" then f:feed("Done.",2) end
      d[method](d); allLate(f); assertUntouched(f); d:shutdown()
    end
  end
end)

test("wealth malformed wealth-like records cancel safely instead of rendering a partial table",function()
  for _,text in ipairs({"Broken has -1 silver","Broken has 1.5 silver","Broken has 1,000 silver",
      "Broken has "..string.rep("9",33).." silver","Broken has 2 silver extra",
      "Broken@Name has 2 silver","<Broken> has 2 silver","Broken:Name has 2 silver",
      "Broken@Name has 2 silver extra"}) do
    local f,d=newFake(); d:onOutgoing("breakd wealth"); f:feed(raw("Synthetic","1"),1)
    f:feed(text,2); f:feed("Done.",3); allLate(f); assertUntouched(f); d:shutdown()
  end
end)

test("wealth invalid native row positions cancel both data and Done without rewriting",function()
  local positions={false,"2",-1,1.5,math.huge,-math.huge,0/0}
  for _,done in ipairs({false,true}) do
    for _,row in ipairs(positions) do
      local f,d=newFake(); d:onOutgoing("breakd wealth")
      if done then f:feed(raw("Synthetic","1"),0) end
      f:feed(done and "Done." or raw("Synthetic","1"),row); f:feed("Done.",10)
      allLate(f); assertUntouched(f); d:shutdown()
    end
    local f,d=newFake(); d:onOutgoing("breakd wealth")
    if done then f:feed(raw("Synthetic","1"),0) end
    f:feed(done and "Done." or raw("Synthetic","1"),nil); f:feed("Done.",10)
    allLate(f); assertUntouched(f); d:shutdown()
  end
end)

test("wealth coordinates must increase uniquely across data and final Done slots",function()
  for _,position in ipairs({9,10}) do
    for _,done in ipairs({false,true}) do
      local f,d=newFake(); d:onOutgoing("breakd wealth"); f:feed(raw("Synthetic","1"),10)
      f:feed(done and "Done." or raw("Other Synthetic","2"),position); f:feed("Done.",20)
      allLate(f); assertUntouched(f); d:shutdown()
    end
  end
end)

test("wealth accepts zero-based row coordinates",function()
  local f,d=newFake(); d:onOutgoing("breakd wealth"); f:feed(raw("Synthetic","1"),0); f:feed("Done.",1); f:advance(0)
  eq(#f.batches,1); eq(f.batches[1][1].line_number,0); d:shutdown()
end)

test("wealth row limit accepts exactly 512 rows and refuses the 513th",function()
  for _,size in ipairs({512,513}) do
    local f,d=newFake(); d:onOutgoing("breakd wealth")
    for index=1,size do f:feed(raw(fixtureName(index),tostring(index)),index) end
    f:feed("Done.",size+1); f:advance(0)
    if size==512 then eq(#f.batches,1); eq(#f.batches[1],513) else assertUntouched(f) end
    d:shutdown(); eq(next(f.timers),nil)
  end
end)

test("wealth line limit cancels a report after 1024 interleaved lines",function()
  local f,d=newFake(); d:onOutgoing("breakd wealth")
  f:feed(raw("Synthetic","1"),1)
  for index=2,1026 do f:feed("Unrelated synthetic prose",index) end
  f:feed("Done.",1027); allLate(f); assertUntouched(f); d:shutdown()
end)

test("wealth oversized raw lines cancel before ANSI normalization can bypass the byte bound",function()
  for _,text in ipairs({string.rep("x",513),string.rep("\27[0m",129)}) do
    local f,d=newFake(); d:onOutgoing("breakd wealth"); f:feed(raw("Synthetic","1"),1)
    f:feed(text,2); f:feed("Done.",3); allLate(f); assertUntouched(f); d:shutdown()
  end
end)

test("wealth repeated cancellation keeps at most one owned timer and never starts polling",function()
  local f,d=newFake()
  for _=1,100 do complete(f,d); d:cancel() end
  assert(f.maxTimers<=1); assertUntouched(f); d:shutdown()
end)

test("wealth timer registration failure fails closed and permits a fresh manual request",function()
  local f,d=newFake(); f.failSchedule=true; d:onOutgoing("breakd wealth")
  f:feed(raw("Synthetic","1"),1); f:feed("Done.",2); assertUntouched(f)
  f.failSchedule=false; complete(f,d,10); f:advance(0); eq(#f.batches,1); d:shutdown()
end)

test("wealth deferred scheduling failure preserves the report",function()
  local f,d=newFake(); d:onOutgoing("breakd wealth"); f:feed(raw("Synthetic","1"),1)
  f.failSchedule=true; f:feed("Done.",2); allLate(f); assertUntouched(f); d:shutdown()
end)

test("wealth replacement failures cannot leak timers or repeat a rewrite",function()
  local f,d=newFake(); f.failReplace=true; complete(f,d)
  f:advance(0); eq(#f.batches,1); eq(next(f.timers),nil); f:advance(10); eq(#f.batches,1); d:shutdown()
end)

test("wealth unavailable adapter and partial startup leave no owned handlers",function()
  for _,method in ipairs({"addWealthDisplayTrigger","replaceWealthOutput","addEvent","killEvent","killTrigger","schedule","cancelTimer"}) do
    local f,d=newFake(nil,false); f[method]=nil; assert(not d:start(),method)
    eq(next(f.events),nil); eq(next(f.triggers),nil); eq(next(f.timers),nil)
  end
  for _,failure in ipairs({"failTrigger","failEvent"}) do
    local f,d=newFake(nil,false); f[failure]=true; assert(not d:start()); d:shutdown()
    eq(next(f.events),nil); eq(next(f.triggers),nil); assertUntouched(f)
  end
end)
