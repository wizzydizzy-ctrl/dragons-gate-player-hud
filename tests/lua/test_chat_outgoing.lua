local Outgoing=require("chat_outgoing")
local Parser=require("chat_parser")

local identity="Nera_O'Vale"
local now="2026-10-14T12:00:00-04:00"
local function request(target,body)
  return assert(Outgoing.parse("contact "..target.." "..(body or "Same body"),identity,now))
end
local function echo(target,body,speaker)
  speaker=speaker or identity; body=body or "Same body"
  local context=target=="room" and "thoughts echoing through the area" or "thoughts"
  return assert(Parser.parse('You pick up '..speaker..'\'s '..context..', "'..body..'"',identity,now))
end

test("outgoing CONTACT parses only complete requests and keeps existing scalar metadata",function()
  for _,case in ipairs({
    {"contact all Hello.", "all","Hello."},
    {"CONTACT ROOM Hello.", "room","Hello."},
    {"  CoNtAcT   Aerin   Exact  spaces and CASE.  ", "Aerin","Exact  spaces and CASE."},
    {"contact O'Vale A quote: \"hello\".", "O'Vale",'A quote: "hello".'},
    {"contact Lark_2-West hello", "Lark_2-West","hello"},
  }) do
    local entry=assert(Outgoing.parse(case[1],identity,now))
    eq(entry.schema,1); eq(entry.timestamp,now); eq(entry.character,identity)
    eq(entry.category,"MENTAL"); eq(entry.source,"outgoing"); eq(entry.speaker,identity)
    eq(entry.target,case[2]); eq(entry.message,case[3])
    eq(entry.line,"You -> "..case[2].." (outgoing request): "..case[3])
    for key,value in pairs(entry) do
      assert(type(value)=="string" or type(value)=="number")
      assert(key~="command" and key~="delivered" and key~="pending" and key~="skipDedupe")
    end
  end
end)

test("outgoing CONTACT rejects incomplete help unrelated commands and command controls",function()
  for _,command in ipairs({
    "", "contact", "contact all", "contact room", "contact Aerin", "contact help",
    "contact help all", "CONTACT HELP syntax", "contact all    ", "contact ? help",
    "contacts all body", "c all body", "psi all body", "cast contact all body",
    "password synthetic-placeholder", "help contact all", "send contact all body",
    'contact "Aerin North" body', "contact all/body", "contact -target body",
  }) do eq(Outgoing.parse(command,identity,now),nil) end
  for byte=0,31 do eq(Outgoing.parse("contact all before"..string.char(byte).."after",identity,now),nil) end
  eq(Outgoing.parse("contact all before"..string.char(127).."after",identity,now),nil)
  eq(Outgoing.parse("contact all hello\ncontact room second",identity,now),nil)
  for _,value in ipairs({false,true,0,{}}) do eq(Outgoing.parse(value,identity,now),nil) end
  eq(Outgoing.parse(nil,identity,now),nil)
end)

test("outgoing CONTACT caps command target body and confirmed character without truncation",function()
  assert(Outgoing.parse("contact "..string.rep("a",Outgoing.MAX_TARGET).." x",identity,now))
  eq(Outgoing.parse("contact "..string.rep("a",Outgoing.MAX_TARGET+1).." x",identity,now),nil)
  eq(Outgoing.MAX_COMMAND,4096); eq(Outgoing.MAX_MESSAGE,2000)
  local longestBody=string.rep("x",Outgoing.MAX_MESSAGE)
  assert(Outgoing.parse("contact all "..longestBody,identity,now))
  eq(Outgoing.parse("contact all "..longestBody.."x",identity,now),nil)
  local longestCommand=string.rep(" ",Outgoing.MAX_COMMAND-#"contact all "-#longestBody).."contact all "..longestBody
  assert(Outgoing.parse(longestCommand,identity,now))
  eq(Outgoing.parse(" "..longestCommand,identity,now),nil)
  eq(Outgoing.parse("contact all "..string.rep("x",Outgoing.MAX_MESSAGE+1),identity,now),nil)
  eq(Outgoing.parse(string.rep(" ",Outgoing.MAX_COMMAND).."contact all x",identity,now),nil)
  assert(Outgoing.parse("contact all x",string.rep("a",Outgoing.MAX_CHARACTER),now))
  for _,value in ipairs({"", " ", "Unknown", " UNKNOWN ", "unknown", "A\nB", string.rep("a",Outgoing.MAX_CHARACTER+1),false,{},42}) do
    eq(Outgoing.parse("contact all x",value,now),nil)
  end
  eq(Outgoing.parse("contact all x",nil,now),nil)
  local entry=assert(Outgoing.parse("contact all x",identity,"bad\nclock"))
  assert(not entry.timestamp:find("%c"))
end)

test("outgoing short server identity requires independent matching GMCP full name",function()
  local character="Wizzy Dizzy"
  eq(Outgoing.serverName(character,{Char={Status={name="Wizzy",surname="Dizzy"}}}),"Wizzy")
  eq(Outgoing.serverName("Wizzy",{Char={Status={name="Wizzy"}}}),"Wizzy")
  for _,status in ipairs({
    {},{name="Wizzy"},{name="Wizzy",surname="Other"},{name="Other",surname="Dizzy"},
    {name="Unknown",surname="Dizzy"},{name="Wizzy\n",surname="Dizzy"},
    {name="Wizzy",surname="Dizzy\n"},{name="Wizzy",surname=false},
    {name="Wizzy",surname={}},{name="Wizzy",surname=string.rep("a",129)},
  }) do eq(Outgoing.serverName(character,{Char={Status=status}}),nil) end
  for _,data in ipairs({false,12,{}, {Char=false},{Char={Status=false}}}) do
    eq(Outgoing.serverName(character,data),nil)
  end
  eq(Outgoing.serverName(character,nil),nil)
  eq(Outgoing.serverName("Unknown",{Char={Status={name="Wizzy",surname="Dizzy"}}}),nil)
end)

test("outgoing reconciliation accepts verified short own broadcasts and retains another speaker",function()
  local character="Wizzy Dizzy"
  local serverName=Outgoing.serverName(character,{Char={Status={name="Wizzy",surname="Dizzy"}}})
  local queue=Outgoing.new()
  for _,target in ipairs({"all","room"}) do
    queue:record(assert(Outgoing.parse("contact "..target.." Same body",character,now)),100,serverName)
  end
  local function frame(speaker,context)
    return assert(Parser.parse('You pick up '..speaker..'\'s '..context..', "Same body"',character,now))
  end
  eq(queue:reconcile(frame("Other","thoughts"),character,101,serverName),false); eq(#queue.pending,2)
  eq(queue:reconcile(frame("Wizzy","thoughts"),character,101),false); eq(#queue.pending,2)
  eq(queue:reconcile(frame("Wizzy","thoughts"),character,101,serverName),true); eq(#queue.pending,1)
  eq(queue:reconcile(frame("Other","thoughts echoing through the area"),character,101,serverName),false)
  eq(queue:reconcile(frame("Wizzy","thoughts echoing through the area"),character,101,serverName),true)
  eq(#queue.pending,0)
  queue:record(assert(Outgoing.parse("contact all Same body",character,now)),100)
  eq(queue:reconcile(frame("Wizzy","thoughts"),character,101,serverName),false); eq(#queue.pending,1)
end)

test("outgoing maximum message still reconciles its exact server broadcast frame",function()
  local body=string.rep("x",Outgoing.MAX_MESSAGE)
  local queue=Outgoing.new(); queue:record(request("all",body),100)
  local entry=echo("all",body)
  eq(#entry.message,Outgoing.MAX_MESSAGE)
  eq(queue:reconcile(entry,identity,101),true); eq(#queue.pending,0)
end)

test("outgoing reconciliation consumes one broadcast request per exact context identity and body",function()
  local queue=Outgoing.new()
  queue:record(request("all"),100); queue:record(request("all"),100)
  queue:record(request("room"),100); queue:record(request("Aerin"),100)
  eq(#queue.pending,4)
  eq(queue:reconcile(echo("room"),identity,101),true); eq(#queue.pending,3)
  eq(queue:reconcile(echo("room"),identity,101),false); eq(#queue.pending,3)
  eq(queue:reconcile(echo("all"),identity,101),true); eq(#queue.pending,2)
  eq(queue:reconcile(echo("all"),identity,101),true); eq(#queue.pending,1)
  eq(queue:reconcile(echo("all"),identity,101),false)
  eq(queue.pending[1].target,"Aerin")
end)

test("outgoing reconciliation preserves direct messages other chat and uncertain same-body matches",function()
  local queue=Outgoing.new(); queue:record(request("all"),100)
  for _,line in ipairs({
    'Someone thinks to you, "Same body"',
    'Nera_O\'Vale thinks to you, "Same body"',
    'You pick up Someone\'s thoughts, "Same body"',
    'You pick up Nera\'s thoughts, "Same body"',
    'Nera (ESP): "Same body"',
    'You pick up Nera\'s mental link, "Same body"',
    'You pick up Nera O\'Vale\'s Psycian link, "Same body"',
    'You pick up Nera_O\'Vale\'s thoughts, "same body"',
    'You pick up Nera_O\'Vale\'s thoughts, "Same  body"',
    'You pick up Nera_O\'Vale\'s thoughts echoing through the area, "Same body"',
  }) do
    local entry=assert(Parser.parse(line,identity,now))
    eq(queue:reconcile(entry,identity,101),false); eq(#queue.pending,1)
  end
  local entry=echo("all"); entry.source="custom"
  eq(queue:reconcile(entry,identity,101),false)
  entry=echo("all"); entry.target=identity; eq(queue:reconcile(entry,identity,101),false)
  entry=echo("all"); entry.speaker="Someone"; eq(queue:reconcile(entry,identity,101),false)
  entry=echo("all"); entry.message="different"; eq(queue:reconcile(entry,identity,101),false)
  entry=echo("all"); entry.character="Someone"; eq(queue:reconcile(entry,identity,101),false)
  entry=echo("all"); entry.line=entry.line.." [rank-1]"; eq(queue:reconcile(entry,identity,101),false)
  eq(#queue.pending,1); eq(queue:reconcile(echo("all"),identity,101),true)
end)

test("outgoing reconciliation accepts known ranked broadcast echoes and ANSI wrappers",function()
  for _,suffix in ipairs({""," [r-1]"," [ r-27 ]"}) do
    local queue=Outgoing.new(); queue:record(request("all"),100)
    local entry=echo("all"); entry.line="\27[35m"..entry.line..suffix.."\27[0m"
    eq(queue:reconcile(entry,identity,101),true); eq(#queue.pending,0)
  end
end)

test("outgoing request queue is bounded expires and never follows a changed or unknown identity",function()
  local queue=Outgoing.new()
  for index=1,Outgoing.MAX_PENDING+10 do queue:record(request("all","Body "..index),100) end
  eq(#queue.pending,Outgoing.MAX_PENDING)
  eq(queue:reconcile(echo("all","Body 1"),identity,101),false)
  eq(queue:reconcile(echo("all","Body 11"),identity,101),true)
  queue:clear(); queue:record(request("all"),100)
  eq(queue:reconcile(echo("all"),identity,100+Outgoing.EXPIRY_SECONDS+.01),false); eq(#queue.pending,0)
  queue:record(request("all"),100)
  eq(queue:reconcile(echo("all"),identity,99),false); eq(#queue.pending,0)
  queue:record(request("all"),100)
  eq(queue:reconcile(echo("all"),"Other Character",101),false); eq(#queue.pending,0)
  queue:record(request("all"),100)
  eq(queue:reconcile(echo("all"),"Unknown",101),false); eq(#queue.pending,0)
  queue:record(request("all"),100); queue:clear(); eq(#queue.pending,0)
end)
