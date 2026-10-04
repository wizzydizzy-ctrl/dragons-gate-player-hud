local Parser=require("chat_parser")

test("captures only exact diligent-training fatigue notices in ALL",function()
  local line="Due to your diligent training, you have gained additional fatigue!"
  for _,input in ipairs({line," \t\27[32m"..line.."\27[0m \r\n"}) do
    local e=assert(Parser.parse(input,"Dace Alterac"))
    eq(e.category,"ALL"); eq(e.source,"builtin"); eq(e.message,line); eq(e.line,line)
    eq(e.speaker,nil); eq(e.target,nil); eq(e.language,nil)
  end
  for _,input in ipairs({"Due to your diligent training,",line:sub(1,-2),
    "The sign reads: "..line,line.." Again."}) do eq(Parser.parse(input),nil) end
  local quoted='Eilan says, "'..line..'"'
  local speech=assert(Parser.parse(quoted,"Dace Alterac"))
  eq(speech.category,"ROOM"); eq(speech.source,"builtin"); eq(speech.speaker,"Eilan")
  eq(speech.message,line); eq(speech.line,quoted)
end)

local playerStatNames={"strength","intelligence","wisdom","dexterity","agility","constitution","charisma","will","voice","perception","appearance","presence","luck"}

test("captures all thirteen current and legacy stat increases with case ANSI and whitespace normalization",function()
  for _,stat in ipairs(playerStatNames) do
    local line="Your "..stat.." has increased!"
    local e=assert(Parser.parse(line,"Dace Alterac","2026-08-31T13:00:00-04:00"),line)
    eq(e.schema,1); eq(e.category,"ALL"); eq(e.source,"builtin")
    eq(e.message,line); eq(e.line,line); eq(e.character,"Dace Alterac"); eq(e.timestamp,"2026-08-31T13:00:00-04:00")
    eq(e.speaker,nil); eq(e.target,nil); eq(e.language,nil)
    local mixedCase="yOuR "..stat:upper().." hAs InCrEaSeD!"
    local input=" \t\27[1;32myOuR \27[0m"..stat:upper().." hAs InCrEaSeD!\27[0m \r\n"
    local normalized=assert(Parser.parse(input,"Dace Alterac"),stat)
    eq(normalized.category,"ALL"); eq(normalized.source,"builtin")
    eq(normalized.message,mixedCase); eq(normalized.line,mixedCase)
  end
end)

test("stat increases reject unrelated names malformed notices and surrounding narration",function()
  for _,line in ipairs({
    "Your health has increased!","Your fatigue has increased!","Your skill has increased!",
    "Your willpower has increased!","Your voice training has increased!","Your  has increased!",
    "Your will has decreased!","Your constitution has increased.","Your strength has increased",
    "The sign reads: Your will has increased!","Your constitution has increased! Again.",
    '"Your will has increased!"',"Your strength has increased!\nYour will has increased!",
  }) do
    eq(Parser.parse("\27[32m"..line.."\27[0m","Dace Alterac"),nil)
  end
end)

test("speech quoting every accepted stat increase retains ROOM and the original full line",function()
  for _,stat in ipairs(playerStatNames) do
    local message="Your "..stat.." has increased!"
    local line='Eilan says, "'..message..'"'
    local e=assert(Parser.parse("\27[32m"..line.."\27[0m","Dace Alterac"),line)
    eq(e.category,"ROOM"); eq(e.source,"builtin"); eq(e.speaker,"Eilan")
    eq(e.message,message); eq(e.line,line); eq(e.target,nil); eq(e.language,nil)
  end
end)

test("captures training-ready notices for any nonempty skill in ALL",function()
  for _,skill in ipairs({"Biting.","Sharp Weapons.","Identify Gems/Minerals.","Dragon's Breath"}) do
    local line="You now feel prepared to train further in "..skill
    local e=assert(Parser.parse("\27[32m"..line.."\27[0m","Dace Alterac"))
    eq(e.category,"ALL"); eq(e.message,line); eq(e.line,line); eq(e.source,"builtin"); eq(e.speaker,nil)
  end
  eq(Parser.parse("You now feel prepared to train further in"),nil)
  eq(Parser.parse("You now feel prepared to train further in   "),nil)
  eq(Parser.parse("The sign reads: You now feel prepared to train further in Biting."),nil)
  eq(assert(Parser.parse('Eilan says, "You now feel prepared to train further in Biting."')).category,"ROOM")
end)

test("parses room speech target and verb",function()
  local e=assert(Parser.parse('Ocinaiya says to Suupidosutaa, "Especially you."',"Dace Alterac","2026-08-31T13:00:00-04:00"))
  eq(e.schema,1); eq(e.timestamp,"2026-08-31T13:00:00-04:00"); eq(e.character,"Dace Alterac")
  eq(e.category,"ROOM"); eq(e.speaker,"Ocinaiya"); eq(e.target,"Suupidosutaa"); eq(e.message,"Especially you.")
  eq(e.line,'Ocinaiya says to Suupidosutaa, "Especially you."'); eq(e.source,"builtin")
end)

test("parses Dragons Gate direct-target asks without a to keyword",function()
  local room=assert(Parser.parse('Eilan asks Atrax, "You asked two already, didn\'t you?"',"Dace Alterac"))
  eq(room.category,"ROOM"); eq(room.speaker,"Eilan"); eq(room.target,"Atrax"); eq(room.message,"You asked two already, didn't you?")
  local language=assert(Parser.parse('Eilan asks Atrax in Secian, "Can you hear me?"',"Dace Alterac"))
  eq(language.category,"ROOM"); eq(language.target,"Atrax"); eq(language.language,"Secian")
  local own=assert(Parser.parse('Dace Alterac asks Atrax, "Ready?"',"Dace Alterac"))
  eq(own.category,"OWN"); eq(own.speaker,"Dace Alterac"); eq(own.target,"Atrax")
end)

test("parses actor-facing directed asks and says with clean target metadata",function()
  local asked=assert(Parser.parse('You ask Atrax, "Ready?"',"Dace Alterac"))
  eq(asked.category,"OWN"); eq(asked.speaker,"Dace Alterac"); eq(asked.target,"Atrax"); eq(asked.message,"Ready?")
  local askedLanguage=assert(Parser.parse('You ask Atrax in Secian, "Ready?"',"Dace Alterac"))
  eq(askedLanguage.target,"Atrax"); eq(askedLanguage.language,"Secian"); eq(askedLanguage.message,"Ready?")
  local said=assert(Parser.parse('You say to Atrax, "Hello."',"Dace Alterac"))
  eq(said.category,"OWN"); eq(said.target,"Atrax"); eq(said.message,"Hello.")
  local saidLanguage=assert(Parser.parse('You say in Secian to Atrax, "Hello."',"Dace Alterac"))
  eq(saidLanguage.target,"Atrax"); eq(saidLanguage.language,"Secian"); eq(saidLanguage.message,"Hello.")
end)

test("parses room speech languages and all approved verbs",function()
  local asks=assert(Parser.parse('Ocinaiya asks in Elvish to Suupidosutaa, "Are you ready?"',"Dace Alterac"))
  eq(asks.category,"ROOM"); eq(asks.target,"Suupidosutaa"); eq(asks.language,"Elvish")
  for _,verb in ipairs({"exclaims","shouts","yells"}) do
    eq(assert(Parser.parse('Ocinaiya '..verb..' in Common, "Hello!"')).category,"ROOM")
  end
end)

test("parses room target then language clauses",function()
  local e=assert(Parser.parse('Ocinaiya says to Suupidosutaa in Elvish, "Especially you."',"Dace Alterac"))
  eq(e.category,"ROOM"); eq(e.speaker,"Ocinaiya"); eq(e.target,"Suupidosutaa"); eq(e.language,"Elvish")
end)

test("parses mixed-case active multi-word language then target clauses",function()
  local e=assert(Parser.parse('DACE Alterac says in Common to Suupidosutaa, "I am here."',"dace alterac"))
  eq(e.category,"OWN"); eq(e.speaker,"DACE Alterac"); eq(e.target,"Suupidosutaa"); eq(e.language,"Common")
end)

test("parses active character speech and unquoted own output",function()
  local spoken=assert(Parser.parse('Dace Alterac says, "I am here."',"Dace Alterac"))
  eq(spoken.category,"OWN"); eq(spoken.speaker,"Dace Alterac"); eq(spoken.message,"I am here.")
  local e=assert(Parser.parse("You say I'm new.","Dace Alterac"))
  eq(e.category,"OWN"); eq(e.speaker,"Dace Alterac"); eq(e.message,"I'm new.")
  eq(e.target,nil); eq(e.language,nil)
end)

test("parses incoming and outgoing whispers",function()
  local direct=assert(Parser.parse('Kaida whispers, "hello"',"Dace Alterac"))
  eq(direct.category,"WHISPER"); eq(direct.speaker,"Kaida"); eq(direct.target,"Dace Alterac"); eq(direct.message,"hello")
  local incoming=assert(Parser.parse('Ocinaiya whispers to you, "Keep this quiet."',"Dace Alterac"))
  eq(incoming.category,"WHISPER"); eq(incoming.speaker,"Ocinaiya"); eq(incoming.target,"Dace Alterac")
  local outgoing=assert(Parser.parse('You whisper to Ocinaiya, "I will."',"Dace Alterac"))
  eq(outgoing.category,"WHISPER"); eq(outgoing.speaker,"Dace Alterac"); eq(outgoing.target,"Ocinaiya")
end)

test("parses private mental and staff channels",function()
  local esp=assert(Parser.parse('Tekk (ESP): "ahhh and she returns"'))
  eq(esp.category,"ESP"); eq(esp.speaker,"Tekk"); eq(esp.message,"ahhh and she returns")
  local thought=assert(Parser.parse('Seaux thinks to you, "Hello"',"Dace Alterac"))
  eq(thought.category,"CONTACT"); eq(thought.speaker,"Seaux"); eq(thought.target,nil); eq(thought.message,"Hello")
  local named=assert(Parser.parse('\27[35mAeron Del\'mar thinks to you, "Testing."\27[0m',"Dace Alterac"))
  eq(named.category,"CONTACT"); eq(named.speaker,"Aeron Del'mar"); eq(named.message,"Testing.")
  local broadcast=assert(Parser.parse('You pick up Seaux\'s thoughts, "TEST MESSAGE" [r-1]'))
  eq(broadcast.category,"CONTACT"); eq(broadcast.speaker,"Seaux"); eq(broadcast.message,"TEST MESSAGE")
  local psycian=assert(Parser.parse('You pick up Seaux\'s Psycian link, "Hello." [r-1]'))
  eq(psycian.category,"ESP"); eq(psycian.speaker,"Seaux"); eq(psycian.message,"Hello.")
  local dragon=assert(Parser.parse('You pick up Losmir\'s mental link, "dragon door... is unlocked"'))
  eq(dragon.category,"DRAGON"); eq(dragon.speaker,"Losmir"); eq(dragon.message,"dragon door... is unlocked")
  local contact=assert(Parser.parse('You pick up Faolann\'s thoughts echoing through the area, "leave me be"'))
  eq(contact.category,"CONTACT"); eq(contact.speaker,"Faolann"); eq(contact.message,"leave me be")
  eq(assert(Parser.parse('Aerin (ELDER): "Please remain calm."')).category,"STAFF")
  eq(assert(Parser.parse('[GUIDE] Aerin: Follow the northern road.')).category,"STAFF")
end)

test("parses Dragons Gate GM and staff voice channels",function()
  local gm=assert(Parser.parse("[GM] Kaida: and if you could add the staff stuff"))
  eq(gm.category,"STAFF"); eq(gm.speaker,"Kaida"); eq(gm.message,"and if you could add the staff stuff")
  local report=assert(Parser.parse("[GM] Orchist [mdonahue] reports: wiz im not on my computer."))
  eq(report.category,"STAFF"); eq(report.speaker,"Orchist"); eq(report.message,"wiz im not on my computer.")
  local bug=assert(Parser.parse("[GM] Vaeltherion [forhekset] reports a bug in room 10532: Traveling merchants displaced the mobs."))
  eq(bug.category,"STAFF"); eq(bug.speaker,"Vaeltherion"); eq(bug.message,"reports a bug in room 10532: Traveling merchants displaced the mobs.")
  local resolved=assert(Parser.parse("[GM] Wizzy resolved report #21: Air mages have a tested level 2 spell."))
  eq(resolved.category,"STAFF"); eq(resolved.speaker,"Wizzy"); eq(resolved.message,"resolved report #21: Air mages have a tested level 2 spell.")
  local voice=assert(Parser.parse('You hear the voice of Wizzy say, "will do"'))
  eq(voice.category,"STAFF"); eq(voice.speaker,"Wizzy"); eq(voice.message,"will do")
  local question=assert(Parser.parse('You hear the voice of Nythriss\'a ask, "hell no, this majestic beast?"'))
  eq(question.category,"STAFF"); eq(question.speaker,"Nythriss'a"); eq(question.target,nil); eq(question.message,"hell no, this majestic beast?")
  local targeted=assert(Parser.parse('You hear the voice of Wizzy ask Tamalon, "you a sword?"'))
  eq(targeted.category,"STAFF"); eq(targeted.speaker,"Wizzy"); eq(targeted.target,"Tamalon"); eq(targeted.message,"you a sword?")
  local sent=assert(Parser.parse("Nythriss'a sends: check check"))
  eq(sent.category,"STAFF"); eq(sent.speaker,"Nythriss'a"); eq(sent.message,"check check")
  eq(Parser.parse('You hear the voice of the wind say, "nothing"'),nil)
end)

test("parses GUIDE assistance requests with room and pending count",function()
  local request=assert(Parser.parse("[GUIDE] Bork Biigfeet (room 174) requests your assistance.  (1 total requests pending.)"))
  eq(request.category,"STAFF"); eq(request.speaker,"Bork Biigfeet")
  eq(request.message,"requests your assistance in room 174 (1 total requests pending).")
  eq(request.line,"[GUIDE] Bork Biigfeet (room 174) requests your assistance.  (1 total requests pending.)")
  local apostrophe=assert(Parser.parse("[GUIDE] Aeron Del'mar (room 9001) requests your assistance. (12 total requests pending.)"))
  eq(apostrophe.category,"STAFF"); eq(apostrophe.speaker,"Aeron Del'mar")
  eq(apostrophe.message,"requests your assistance in room 9001 (12 total requests pending).")
  eq(Parser.parse("[GUIDE] Bork Biigfeet (room unknown) requests your assistance. (1 total requests pending.)"),nil)
end)

test("parses GUIDE assistance request cancellations",function()
  local canceled=assert(Parser.parse("[GUIDE] Wizzy Dizzy just canceled his assistance request."))
  eq(canceled.category,"STAFF"); eq(canceled.speaker,"Wizzy Dizzy")
  eq(canceled.message,"just canceled his assistance request.")
  eq(canceled.line,"[GUIDE] Wizzy Dizzy just canceled his assistance request.")
  local apostrophe=assert(Parser.parse("[GUIDE] Aeron Del'mar just canceled their assistance request."))
  eq(apostrophe.category,"STAFF"); eq(apostrophe.speaker,"Aeron Del'mar")
  local ansi=assert(Parser.parse("\27[36m[GUIDE] Gia Afari just canceled her assistance request.\27[0m"))
  eq(ansi.category,"STAFF"); eq(ansi.speaker,"Gia Afari"); eq(ansi.message,"just canceled her assistance request.")
  eq(Parser.parse("[GUIDE] Wizzy Dizzy canceled his assistance request."),nil)
end)

test("parses GUIDE assistance handling assignments",function()
  local handling=assert(Parser.parse("[GUIDE] Aeron is handling Marcelline Willowsby's assist.  (0 more pending.)"))
  eq(handling.category,"STAFF"); eq(handling.speaker,"Aeron"); eq(handling.target,"Marcelline Willowsby")
  eq(handling.message,"is handling Marcelline Willowsby's assist (0 more pending).")
  eq(handling.line,"[GUIDE] Aeron is handling Marcelline Willowsby's assist.  (0 more pending.)")
  local names=assert(Parser.parse("\27[36m[GUIDE] Aeron Del'mar is handling Gia Afari's assist. (12 more pending.)\27[0m"))
  eq(names.speaker,"Aeron Del'mar"); eq(names.target,"Gia Afari"); eq(names.message,"is handling Gia Afari's assist (12 more pending).")
end)

test("parses multi-word GUIDE and GM names",function()
  local guide=assert(Parser.parse("[GUIDE] Bork Biigfeet: Please wait there."))
  eq(guide.category,"STAFF"); eq(guide.speaker,"Bork Biigfeet"); eq(guide.message,"Please wait there.")
  local gm=assert(Parser.parse("[GM] Aeron Del'mar: Checking now."))
  eq(gm.category,"STAFF"); eq(gm.speaker,"Aeron Del'mar"); eq(gm.message,"Checking now.")
end)

test("parses ranked GM Dragon links",function()
  local senior=assert(Parser.parse('You pick up Wizzy\'s Dragon link, "test" [r-1]'))
  eq(senior.category,"DRAGON"); eq(senior.speaker,"Wizzy"); eq(senior.message,"test")
  eq(senior.line,'You pick up Wizzy\'s Dragon link, "test" [r-1]')
  local standard=assert(Parser.parse('You pick up Nythrael\'s Dragon link, "Ayep" [r-0]'))
  eq(standard.category,"DRAGON"); eq(standard.speaker,"Nythrael"); eq(standard.message,"Ayep")
  local arbitrary=assert(Parser.parse('You pick up Kaida\'s Dragon link, "Ranked" [r-27]')); eq(arbitrary.speaker,"Kaida"); eq(arbitrary.message,"Ranked")
end)
test("parses ranked and unranked Secian links",function()
  local question=assert(Parser.parse('You pick up Marcelline\'s Secian link, "Hello?" [r-1]'))
  eq(question.category,"SECIAN"); eq(question.speaker,"Marcelline"); eq(question.message,"Hello?")
  eq(question.line,'You pick up Marcelline\'s Secian link, "Hello?" [r-1]')
  local greeting=assert(Parser.parse('You pick up Shayla\'s Secian link, "hello!" [r-0]'))
  eq(greeting.category,"SECIAN"); eq(greeting.speaker,"Shayla"); eq(greeting.message,"hello!")
  local unranked=assert(Parser.parse('You pick up Nythriss\'a\'s Secian link, "No rank shown."'))
  eq(unranked.category,"SECIAN"); eq(unranked.speaker,"Nythriss'a"); eq(unranked.message,"No rank shown.")
  local ansi=assert(Parser.parse('\27[36mYou pick up Shayla\'s Secian link, "colored" [r-1]\27[0m'))
  eq(ansi.category,"SECIAN"); eq(ansi.speaker,"Shayla"); eq(ansi.line,'You pick up Shayla\'s Secian link, "colored" [r-1]')
end)
test("parses third-person mental links using the linked speaker",function()
  local entry=assert(Parser.parse('Mieglyn picks up Kiki\'s mental link, "Four dragons."')); eq(entry.category,"DRAGON"); eq(entry.speaker,"Kiki"); eq(entry.message,"Four dragons.")
end)

test("normalizes ANSI before parsing",function()
  local e=assert(Parser.parse('\27[31mTekk\27[0m (ESP): "ahhh and she returns"'))
  eq(e.speaker,"Tekk"); eq(e.line,'Tekk (ESP): "ahhh and she returns"')
end)

test("captures weapon attacks and combat results independently of highlighting",function()
  for _,line in ipairs({
    "The fighting puppet swings a sharpened dried bamboo stake at you!",
    "The academy bully punches at you!",
    "You swing your two-handed simple wooden broadsword at the fighting puppet!",
    "You kick at the academy bully!",
    "You fire your bow at the academy bully!",
    "The swing is a well-delivered blow to the left arm.",
    "The swing is an exceptional blow to the head.",
    "The attack is an amazing shot to the torso.",
    "The attack is a decent punch to the torso.",
    "The swing barely misses.",
    "The attack misses.",
    "The attack is a decent blow to the torso, but is totally deflected by your wooden shield!",
  }) do
    local e=assert(Parser.parse("\27[32m"..line.."\27[0m","Dace Alterac"),line)
    eq(e.category,"COMBAT"); eq(e.message,line); eq(e.line,line); eq(e.source,"builtin")
  end
  for _,line in ipairs({
    'Eilan says, "You swing your broadsword at the fighting puppet!"',
    "The mural depicts a fighting puppet that swings a stake at you!",
    "The sign reads: The attack misses.",
    "You swing the gate open.",
    "The fighting puppet swings a stake at Atrax!",
    "You now feel prepared to train further in Sharp Weapons.",
  }) do
    local e=Parser.parse(line,"Dace Alterac")
    eq(e and e.category=="COMBAT" or false,false)
  end
end)

test("captures only conservatively recognized combat lines",function()
  local damage=assert(Parser.parse("Your head takes 8 points of impact damage!","Dace Alterac"))
  eq(damage.category,"COMBAT"); eq(damage.message,"Your head takes 8 points of impact damage!"); eq(damage.source,"builtin")
  eq(assert(Parser.parse("The dark hound claws at you!","Dace Alterac")).category,"COMBAT")
  eq(assert(Parser.parse("You cannot move in that direction.","Dace Alterac")).category,"COMBAT")
  eq(assert(Parser.parse("You expend 1 fatigue keeping up the dragon dart on the ork.","Dace Alterac")).category,"COMBAT")
  eq(Parser.parse("The mural depicts a dark hound that claws at you!","Dace Alterac"),nil)
  eq(Parser.parse("The dark hound claws at Atrax!","Dace Alterac"),nil)
end)

test("rejects malformed empty and misleading narration",function()
  eq(Parser.parse("The teller whispers to you about opening an account."),nil)
  eq(Parser.parse('Ocinaiya says, Especially you.'),nil)
  eq(Parser.parse('Ocinaiya says, "Especially you.'),nil)
  eq(Parser.parse('Ocinaiya says, ""'),nil)
  eq(Parser.parse('Tekk (ESP): "   "'),nil)
  eq(Parser.parse('Seaux thinks to you about the weather.'),nil)
  eq(Parser.parse('You pick up Seaux\'s thoughts, "missing rank" [rank-1]'),nil)
  eq(Parser.parse('[GM] Orchist [] reports: malformed account'),nil)
  eq(Parser.parse('[GM] Orchist [account] reports a bug in room unknown: malformed room'),nil)
  eq(Parser.parse('[GUIDE] Aerin:   '),nil)
  eq(Parser.parse('You pick up Shayla\'s Secian linkage, "hello" [r-1]'),nil)
  eq(Parser.parse('You pick up Shayla\'s Secian link, "hello [r-1]'),nil)
end)

test("validates safe custom categories and preserves supplied metadata",function()
  eq(Parser.category(" quest-log "),"QUEST-LOG")
  eq(Parser.category("QUEST_LOG"),"QUEST_LOG")
  eq(Parser.category("quest log"),nil)
  eq(Parser.category("QUEST!"),nil)
  local entry=assert(Parser.custom(" quest-log ","The invasion has started.",{
    speaker="Herald",target="Dace Alterac",language="Common",timestamp="2026-08-31T13:00:00-04:00",line="Herald announces the invasion.",
  },"Dace Alterac","2026-08-31T12:00:00-04:00"))
  eq(entry.schema,1); eq(entry.timestamp,"2026-08-31T13:00:00-04:00"); eq(entry.character,"Dace Alterac")
  eq(entry.category,"QUEST-LOG"); eq(entry.speaker,"Herald"); eq(entry.target,"Dace Alterac"); eq(entry.language,"Common")
  eq(entry.message,"The invasion has started."); eq(entry.line,"Herald announces the invasion."); eq(entry.source,"custom")
  eq(Parser.custom("bad category!","hello"),nil)
  eq(Parser.custom("QUEST","   "),nil)
end)
