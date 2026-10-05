local Display=require("skill_display")
local SkillSort=require("skill_sort")
local Adapter=require("mudlet_adapter")
local function fakeSkills(enabled,sort,packageName)
  local f={next=0,timers={},cancelled={},events={},lines={},replacements=0,deletions=0,deleted={},cursor=0,column=3,selected={},clock=0}
  function f:addSkillDisplayTrigger(fn) self.trigger=fn; return "skill-trigger" end
  function f:killTrigger() self.trigger=nil end
  function f:addEvent(event,fn) self.next=self.next+1; self.events[self.next]={event=event,fn=fn}; return self.next end
  function f:killEvent(id) self.events[id]=nil end
  function f:emit(event,...)
    local handlers={}; for _,item in pairs(self.events) do if item.event==event then handlers[#handlers+1]=item.fn end end
    for _,fn in ipairs(handlers) do fn(...) end
  end
  function f:schedule(delay,fn)
    if self.failSchedule then return nil end
    self.next=self.next+1; self.timers[self.next]={delay=delay,at=self.clock+delay,fn=fn}; return self.next
  end
  function f:cancelTimer(id) self.cancelled[id]=self.timers[id]; self.timers[id]=nil end
  function f:runTimer(id)
    local item=self.timers[id]; assert(item); self.timers[id]=nil; self.clock=math.max(self.clock,item.at); item.fn()
  end
  function f:advance(seconds)
    local target=self.clock+seconds
    for _=1,512 do
      local nextId,nextAt
      for id,item in pairs(self.timers) do
        if item.at<=target and (not nextAt or item.at<nextAt or (item.at==nextAt and id<nextId)) then nextId,nextAt=id,item.at end
      end
      if not nextId then self.clock=target; return end
      self:runTimer(nextId)
    end
    error("diagnostic timer limit exceeded")
  end
  local api={
    getLineNumber=function() return f.cursor end,getColumnNumber=function() return f.column end,
    getLines=function(first) return {f.lines[first]} end,
    moveCursor=function(column,row) f.column=column; f.cursor=row; return true end,
    selectSection=function(start,length) f.selected[#f.selected+1]={start=start,length=length,row=f.cursor}; return not f.failSelect end,
    replace=function(text) f.lines[f.cursor]=text; f.replacements=f.replacements+1 end,
    deleteLine=function()
      local row,last=f.cursor,f.cursor
      f.deleted[#f.deleted+1]={row=row,source=f.lines[row]}
      for number in pairs(f.lines) do last=math.max(last,number) end
      for number=row,last do f.lines[number]=f.lines[number+1] end
      f.deletions=f.deletions+1; f.cursor=math.min(row,math.max(0,last-1)); return true
    end,
    setFgColor=function() end,deselect=function() f.deselections=(f.deselections or 0)+1 end,
  }
  f.api=api
  function f:applyLineColors(segments,provided) return Adapter.new():applyLineColors(segments,provided) end
  function f:replaceSkillOutput(rows) self.lastRows=rows; return Adapter.replaceSkillOutput(self,rows,api) end
  local display=Display.new(f,enabled,packageName,sort); assert(display:start())
  function f:feed(text,row)
    if row~=nil then self.lines[row]=text:gsub("\27%[[0-?]*[ -/]*[@-~]",""):gsub("\r",""); self.cursor=row end
    self.trigger(text,row)
  end
  return f,display
end

test("main skills authoritative 57 identifiers are unique and normalize case whitespace and stars",function()
  local expected={
    "Brawling","Sharp Weapons","Blunt Weapons","Pole Weapons","Throw Weapons","Missile Weapons",
    "Shield Parry","Quickdraw","Dodging","Focus Force","Berserk Attack","Parry Blows","Bargaining",
    "Identify Gems/Minerals","Climbing","Detect Traps","Remove Traps","Skinning","Disguise","Pick Locks",
    "Riding","Hiding","Swimming","Alchemy","Backstab","Martial Arts","Picking Pockets","Shoplifting",
    "Stealth","Poisoning","Identify Magick","Identify Weapon Quality","Play Instruments","Armor Smithing",
    "Weapon Smithing","Singing","Fletching","Tracking","Disarming","Psionics","Channeling","First Aid",
    "Body Building","Turn Undead","Draining","Biting","Clawing","Webbing","Breath Weapon",
    "Identify Armor Quality","Linguistics","Herbalism","Healing","Spellcasting","Conjuration","Delving","Stinging",
  }
  eq(#expected,57); local seen={}
  for id,value in ipairs(expected) do
    eq(Display.skillId(value),id)
    local messy="  ** "..value:upper():gsub(" "," \t ").."  "
    eq(Display.skillId(messy),id); assert(not seen[Display.skillId(value)]); seen[id]=true
  end
  eq(Display.skillId("Future Art"),nil)
  eq(Display.format({name="* Sharp Weapons",level=4,remain=400}),"     2  Sharps    4   400")
end)

test("main skills only formats possessed rows after completion and keeps raw observers unchanged",function()
  local f,d=fakeSkills(); local raw=" Sharp Weapons             400    4   "
  f:feed("Skill                     Remain Level",10); f:feed(raw,11)
  eq(f.lines[11],raw); eq(f.replacements,0); eq(d.pending,nil)
  f:feed(">",12); eq(f.replacements,0); eq(#d.pending,2)
  eq(f.timers[d.timer].delay,0); f:runTimer(d.timer)
  eq(f.lines[11],"     2  Sharps    4   400"); eq(f.lines[12],">")
  eq(f.replacements,2); eq(f.lines[10],"Number  Skill   LVL  USES")
  eq(f.cursor,12); eq(f.column,3); eq(next(f.timers),nil); d:shutdown()
end)

test("main skills sorting matches parser and leaves header blank rows combat and prompt in their slots",function()
  local f,d=fakeSkills()
  f:feed("Skill Remain Level",20)
  f:feed(" Sharp Weapons       400 4",21)
  f:feed("An enemy strikes you for 12 damage.",22)
  f:feed(" Dodging       50 4",23)
  f:feed("",24)
  f:feed(" First Aid       50 4",25)
  f:feed(" Brawling       0 5",26)
  f:feed("[0] 10/10 hp, 8/8 ftg >",27); f:runTimer(d.timer)
  eq(f.lines[21],"     1  Brawling     5     0")
  eq(f.lines[23],"     9  Dodging      4    50")
  eq(f.lines[25],"    42  First Aid    4    50")
  eq(f.lines[26],"     2  Sharps       4   400")
  eq(f.lines[20],"Number  Skill      LVL  USES"); eq(f.lines[22],"An enemy strikes you for 12 damage.")
  eq(f.lines[24],""); eq(f.lines[27],"[0] 10/10 hp, 8/8 ftg >"); d:shutdown()
end)

test("main skills generic class specific and future Unicode skills remain visible with unknown marker",function()
  local f,d=fakeSkills()
  f:feed("Skill Remain Level",1)
  f:feed(" Quantum Élan 🐉       10 3",2)
  f:feed(" *Stinging       20 2",3)
  f:feed(" *Conjuration       0 1",4)
  f:feed(">",5); f:runTimer(d.timer)
  eq(f.lines[2],"     ?  Quantum Élan 🐉    3    10")
  eq(f.lines[3],"    57  Stinging          2    20")
  eq(f.lines[4],"    55  Conjuration       1     0")
  local raw=" Quantum Élan 🐉       10 3"
  local _,points=raw:gsub("[^\128-\191]",""); local _,extra=raw:gsub("[\240-\244]","")
  local selected; for _,item in ipairs(f.selected) do if item.row==2 and not selected then selected=item end end
  eq(selected.length,points+extra); d:shutdown()
end)

test("main skills ANSI header rows and prompt use original plain console coordinates",function()
  local f,d=fakeSkills()
  f:feed("\27[33mSkill Remain Level\27[0m",1)
  f:feed("\27[32m *  sHaRp   Weapons       400 4 \27[0m",2)
  f:feed("\27[0m>\r",3); f:runTimer(d.timer)
  eq(f.lines[2],"     2  Sharps    4   400"); eq(f.lines[3],">"); d:shutdown()
end)

test("main skills stale deleted or shifted source rows abort the whole batch without changing combat",function()
  for _,changed in ipairs({"An enemy attacks.",false," Brawling       5 2"}) do
    local f,d=fakeSkills(); f:feed("Skill Remain Level",1)
    local raw=" Sharp Weapons       400 4"; f:feed(raw,2); f:feed(" Dodging       10 5",3); f:feed(">",4)
    f.lines[3]=changed or nil; f:runTimer(d.timer)
    eq(f.lines[2],raw); eq(f.lines[3],changed or nil); eq(f.lines[4],">"); eq(f.replacements,0); d:shutdown()
  end
end)

test("main skills unavailable selection API and failed selection leave game output alone",function()
  for _,mode in ipairs({"missing","failed"}) do
    local f,d=fakeSkills(); f:feed("Skill Remain Level",1); f:feed(" Sharp Weapons       400 4",2); f:feed(">",3)
    if mode=="missing" then f.api.replace=nil else f.failSelect=true end
    f:runTimer(d.timer); eq(f.replacements,0); eq(f.cursor,3); d:shutdown()
  end
end)

test("main skills requires table context and trustworthy unique row coordinates",function()
  local f,d=fakeSkills(); f:feed(" Sharp Weapons       400 4",2); eq(d.response,nil)
  for _,number in ipairs({-1,1.5}) do
    f:feed("Skill Remain Level",1); f:feed(" Sharp Weapons       400 4",number); eq(d.response,nil)
  end
  f:feed("Skill Remain Level",1); f:feed(" Sharp Weapons       400 4"); eq(d.response,nil)
  f:feed("Skill Remain Level",1); f:feed(" Sharp Weapons       400 4",2); f:feed(" Dodging       10 4",2)
  eq(d.response,nil); eq(f.replacements,0); d:shutdown()
end)

test("main skills cancellation invalidates late timer callbacks on off disconnect update and shutdown",function()
  for _,action in ipairs({"off","disconnect","install","uninstall","shutdown","menu"}) do
    for _,phase in ipairs({"collecting","blank","complete"}) do
      local f,d=fakeSkills(); f:feed("Skill Remain Level",1); local raw=" Sharp Weapons       400 4"; f:feed(raw,2)
      if phase=="complete" then f:feed(">",3) elseif phase=="blank" then f:feed("",3) end
      local timer=d.timer; local late=f.timers[timer].fn
      if action=="off" then d:setEnabled(false)
      elseif action=="disconnect" then f:emit("sysDisconnectionEvent")
      elseif action=="install" then f:emit("sysInstallPackage",nil,"DragonsGateHUD")
      elseif action=="uninstall" then f:emit("sysUninstallPackage",nil,"DragonsGateHUD")
      elseif action=="menu" then f:feed("Dragon's Gate Menu",4)
      else d:shutdown() end
      eq(d.timer,nil); eq(d.response,nil); eq(d.pending,nil); eq(f.timers[timer],nil)
      late(); eq(f.lines[2],raw); eq(f.replacements,0); d:shutdown(); eq(next(f.events),nil)
    end
  end
end)

test("main skills disabled mode and reenable do not reuse a partial response",function()
  local f,d=fakeSkills(false)
  f:feed("Skill Remain Level",1); f:feed(" Sharp Weapons       400 4",2); f:feed(">",3)
  eq(d.timer,nil); eq(f.replacements,0)
  d:setEnabled(true); f:feed(" Sharp Weapons       400 4",4); f:feed(">",5); eq(d.timer,nil)
  f:feed("Skill Remain Level",6); f:feed(" Sharp Weapons       400 4",7); f:feed(">",8); f:runTimer(d.timer)
  eq(f.lines[7],"     2  Sharps    4   400"); d:shutdown()
end)

test("main skills incomplete oversized or flooded responses release their single bounded timer",function()
  local f,d=fakeSkills(); f:feed("Skill Remain Level",1); f:feed(" Sharp Weapons       400 4",2)
  f:runTimer(d.timer); eq(d.response,nil); eq(f.replacements,0)
  f:feed("Skill Remain Level",1); f:feed(string.rep("x",Display.MAX_LINE_BYTES+1),2); eq(d.timer,nil)
  f:feed("Skill Remain Level",1)
  for row=1,Display.MAX_LINES+1 do f:feed("Interleaved combat.",row+1) end
  eq(d.response,nil); eq(next(f.timers),nil)
  f:feed("Skill Remain Level",1)
  for row=1,Display.MAX_ROWS+1 do f:feed(" Future Skill "..row.."       100 1",row+1) end
  eq(d.response,nil); eq(next(f.timers),nil); eq(f.replacements,0); d:shutdown()
end)

test("main skills empty response scheduling failure and successive headers fail safely",function()
  local f,d=fakeSkills(); f:feed("Skill Remain Level",1); f:feed(">",2); eq(d.timer,nil)
  f.failSchedule=true; f:feed("Skill Remain Level",3); eq(d.response,nil); eq(d.timer,nil)
  f.failSchedule=false; f:feed("Skill Remain Level",4); f:feed(" Sharp Weapons       400 4",5); f:feed(">",6)
  local late=f.timers[d.timer].fn
  f:feed("Skill Remain Level",7); late(); eq(f.replacements,0); eq(#d.response.rows,0); d:shutdown()
end)

test("main skills display settings validate booleans default on and roundtrip saved false",function()
  eq(Adapter.displaySettingsSnapshot({side_text_scale=1}).main_skills,true)
  eq(Adapter.displaySettingsSnapshot({side_text_scale=1,main_skills=false}).main_skills,false)
  eq(Adapter.displaySettingsSnapshot({side_text_scale=1,main_skills="false"}),nil)
  local oldBase,oldLfs,oldOpen,oldRename,oldRemove,oldLoad=Adapter.dataBase,_G.lfs,io.open,os.rename,os.remove,_G.loadfile
  local files={}
  local ok,err=pcall(function()
    Adapter.dataBase=function() return "/offline-skill-fixture" end
    _G.lfs={mkdir=function() return true end}
    io.open=function(path,mode)
      if mode=="rb" then if not files[path] then return nil end; return {close=function() return true end} end
      return {write=function(_,payload) files[path]=payload; return true end,close=function() return true end}
    end
    os.remove=function(path) files[path]=nil; return true end
    os.rename=function(from,to) files[to]=files[from]; files[from]=nil; return true end
    _G.loadfile=function(path) if files[path] then return (loadstring or load)(files[path]) end end
    assert(Adapter.new():saveDisplaySettings({side_text_scale=1,auto_wrap=false,align_input=true,main_skills=false}))
    local loaded=assert(Adapter.loadDisplaySettings()); eq(loaded.main_skills,false); eq(loaded.auto_wrap,false); eq(loaded.align_input,true)
    assert(Adapter.new():saveDisplaySettings({side_text_scale=.9,main_skills=true}))
    eq(Adapter.loadDisplaySettings().main_skills,true)
  end)
  Adapter.dataBase=oldBase; _G.lfs=oldLfs; io.open=oldOpen; os.rename=oldRename; os.remove=oldRemove; _G.loadfile=oldLoad
  assert(ok,err)
end)

test("main skills replaces the heading only after a nonempty complete response and guards its source",function()
  local f,d=fakeSkills(); f:feed(">skill",0); f:feed("Skill Remain Level",1)
  eq(f.lines[1],"Skill Remain Level"); f:feed(" Sharp Weapons       400 4",2); f:feed(">",3)
  eq(f.lines[0],">skill"); eq(f.lines[1],"Skill Remain Level")
  f.lines[1]="An unrelated notice."; f:runTimer(d.timer)
  eq(f.lines[1],"An unrelated notice."); eq(f.lines[2]," Sharp Weapons       400 4"); eq(f.replacements,0)
  f:feed("Skill Remain Level",4); f:feed(">",5); eq(d.pending,nil); eq(f.lines[4],"Skill Remain Level"); d:shutdown()
end)

test("main skills bottom to top replacement survives wrapped row insertion without moving slot mappings",function()
  local f,d=fakeSkills(); f:feed(">skill",0); f:feed("Skill Remain Level",1)
  f:feed(" Sharp Weapons       400 4",2); f:feed("Interleaved combat.",3)
  f:feed(" Dodging       50 5",4); f:feed(">",5)
  local order={}
  f.api.replace=function(text)
    local row=f.cursor; order[#order+1]=row
    local last=5; for number in pairs(f.lines) do last=math.max(last,number) end
    for number=last,row+1,-1 do f.lines[number+1]=f.lines[number] end
    f.lines[row]=text; f.lines[row+1]="[wrapped continuation]"; f.replacements=f.replacements+1
  end
  f:runTimer(d.timer); eq(table.concat(order,","),"4,2,1")
  eq(f.lines[1],"Number  Skill    LVL  USES")
  eq(f.lines[3],"     9  Dodging    5    50")
  eq(f.lines[5],"Interleaved combat."); eq(f.lines[6],"     2  Sharps     4   400")
  eq(f.lines[8],">"); eq(f.lines[0],">skill"); d:shutdown()
end)

test("main skills unavailable current console APIs preserve the raw heading rows and prompt",function()
  for _,missing in ipairs({"getLines","getLineNumber","getColumnNumber","moveCursor","invalid_cursor"}) do
    local f,d=fakeSkills(); f:feed("Skill Remain Level",1); f:feed(" Sharp Weapons       400 4",2); f:feed(">",3)
    if missing=="invalid_cursor" then f.api.getLineNumber=function() return nil end else f.api[missing]=nil end
    f:runTimer(d.timer); eq(f.replacements,0); eq(f.lines[1],"Skill Remain Level")
    eq(f.lines[2]," Sharp Weapons       400 4"); eq(f.lines[3],">"); d:shutdown()
  end
end)

test("main skills nonempty blank terminated tables finish next tick without a prompt or extra enter",function()
  local f,d=fakeSkills()
  local possessed={"Brawling","Sharp Weapons","Blunt Weapons","Pole Weapons","Throw Weapons","Missile Weapons",
    "Shield Parry","Quickdraw","Dodging","Focus Force","Berserk Attack","Parry Blows","Bargaining",
    "Identify Gems/Minerals","Climbing","Detect Traps","Remove Traps","Skinning","Disguise","Pick Locks",
    "Riding","Hiding","Swimming","Alchemy","Backstab"}
  f:feed("Skill Remain Level",0)
  local watchdog=f.timers[d.timer].fn
  for index,skill in ipairs(possessed) do f:feed(" "..skill.."       "..(26-index).." "..index,index) end
  eq(#d.response.rows,25); f:feed("",26)
  local boundary=d.timer; eq(f.timers[boundary].delay,0)
  f:feed("   ",27); eq(d.timer,boundary)
  f:feed("An enemy strikes you for 12 damage.",28)
  watchdog(); eq(d.timer,boundary); eq(f.replacements,0)
  eq(f.replacements,0); f:runTimer(boundary)
  eq(f.replacements,0); eq(#d.pending,26); eq(f.timers[d.timer].delay,0)
  f:advance(0); eq(f.replacements,26); eq(#f.lastRows,26)
  eq(f.lines[26],""); eq(f.lines[27],"   "); eq(f.lines[28],"An enemy strikes you for 12 damage.")
  for row=1,25 do eq(tonumber(f.lines[row]:match("^%s*(%d+)%s")),26-row) end
  eq(d.response,nil); eq(d.pending,nil); eq(next(f.timers),nil)
  f:advance(4); f:feed(">l",29); f:feed("A room description.",30); f:feed(">",31)
  eq(f.replacements,26); eq(f.lines[29],">l"); eq(f.lines[30],"A room description."); d:shutdown()
end)

test("main skills a row after an internal blank cancels the boundary and retains the entire batch",function()
  local f,d=fakeSkills(); f:feed("Skill Remain Level",1); f:feed(" Sharp Weapons       400 4",2)
  f:feed("",3); local boundary=d.timer; local late=f.timers[boundary].fn
  f:feed("Interleaved combat.",4); f:feed(" Dodging       50 5",5)
  eq(f.timers[boundary],nil); eq(#d.response.rows,2); eq(d.response.ending,nil)
  local watchdog=d.timer; late(); eq(d.timer,watchdog); eq(f.replacements,0)
  f:advance(0.1); eq(f.replacements,0); eq(#d.response.rows,2)
  f:feed("",6); f:advance(0)
  eq(f.replacements,3); eq(f.lines[2],"     9  Dodging    5    50")
  eq(f.lines[5],"     2  Sharps     4   400"); eq(f.lines[3],""); eq(f.lines[4],"Interleaved combat.")
  eq(next(f.timers),nil); d:shutdown()
end)

test("main skills blanks before rows and pauses between rows do not finish a partial table",function()
  local f,d=fakeSkills(); f:feed("Skill Remain Level",1); local watchdog=d.timer
  f:feed("",2); eq(d.timer,watchdog); f:advance(0.1); eq(f.replacements,0)
  f:feed(" Sharp Weapons       400 4",3); f:advance(0.1)
  eq(f.replacements,0); eq(#d.response.rows,1)
  f:feed(" Dodging       50 5",4); f:feed("",5); f:advance(0)
  eq(f.replacements,3); eq(#f.lastRows,3); eq(f.lines[2],""); d:shutdown()
end)

test("main skills a prompt supersedes a pending blank boundary without duplicate replacement",function()
  local f,d=fakeSkills(); f:feed("Skill Remain Level",1); f:feed(" Sharp Weapons       400 4",2); f:feed("",3)
  local boundary=d.timer; local late=f.timers[boundary].fn
  f:feed(">",4); local replacement=d.timer
  eq(f.timers[boundary],nil); eq(f.timers[replacement].delay,0)
  late(); eq(d.timer,replacement); eq(#d.pending,2)
  f:advance(0); eq(f.replacements,2); f:advance(0.1); eq(f.replacements,2); d:shutdown()
end)

test("main skills stale blank terminated batches and failed boundary scheduling preserve raw output",function()
  for _,mode in ipairs({"changed","schedule"}) do
    local f,d=fakeSkills(); local raw=" Sharp Weapons       400 4"
    f:feed("Skill Remain Level",1); f:feed(raw,2)
    if mode=="schedule" then f.failSchedule=true end
    f:feed("",3)
    if mode=="changed" then f.lines[1]="An unrelated notice." end
    f:advance(0); eq(f.replacements,0); eq(f.lines[2],raw); eq(f.lines[3],"")
    eq(d.response,nil); eq(d.pending,nil); eq(next(f.timers),nil); d:shutdown()
  end
end)

test("main skills aligned columns share widths from every possessed row including long names and uses",function()
  local f,d=fakeSkills(); f:feed("Skill Remain Level",1)
  f:feed(" Sharp Weapons       400 4",2); f:feed(" Brawling       0 5",3)
  f:feed(" Identify Weapon Quality       1000000000000 9999",4); f:feed("",5); f:advance(0)
  eq(f.lines[1],"Number  Skill                     LVL           USES")
  eq(f.lines[2],"    32  Identify Weapon Quality  9999  1000000000000")
  eq(f.lines[3],"     1  Brawling                    5              0")
  eq(f.lines[4],"     2  Sharps                      4            400")
  for row=2,4 do eq(#f.lines[row],#f.lines[1]) end
  eq(#f.lastRows,4); d:shutdown()
end)

test("main skills zero remaining uses override combat utility and unknown categories",function()
  for _,skill in ipairs({"Sharp Weapons","Focus Force","Clawing","First Aid","Swimming","Riding","Identify Weapon Quality","Future Art"}) do
    eq(Display.category({name=skill,remain=0}),"ready")
  end
end)

test("main skills keeps compact labels separate from consistently aligned numeric rows",function()
  local f,d=fakeSkills(); f:feed("Skill Remain Level",1)
  f:feed(" Sharp Weapons       400 4",2); f:feed(" Identify Gems/Minerals       20 12",3)
  f:feed(" First Aid       0 5",4); f:feed("",5); f:advance(0)
  assert(f.lines[1]:match("^Number%s+Skill%s+LVL%s+USES$"))
  local levelEnd=f.lines[1]:find("LVL",1,true)+2; local usesEnd=f.lines[1]:find("USES",1,true)+3
  for row=2,4 do
    local text=f.lines[row]; eq(#text,#f.lines[1]); assert(not text:find("Level",1,true)); assert(not text:find("Remain",1,true))
    local _,levelLast=text:find("%d+%s+%d+$")
    eq(levelLast,usesEnd)
    local beforeUses=text:sub(1,levelEnd); assert(beforeUses:match("%d+$"))
    assert(text:sub(levelEnd+1):match("^  +%d+$")); assert(text:match("^%s*%d+  %S"))
  end
  d:shutdown()
end)

test("main skills explicit combat identifiers avoid identify and smithing substring matches",function()
  for _,skill in ipairs({"Brawling","Sharp Weapons","Blunt Weapons","Pole Weapons","Throw Weapons","Missile Weapons",
    "Shield Parry","Quickdraw","Dodging","Focus Force","Berserk Attack","Parry Blows","Clawing","First Aid"}) do
    eq(Display.category({name=" ** "..skill:upper(),remain=1}),"combat")
  end
  for _,skill in ipairs({"Swimming","Riding","Identify Gems/Minerals","Identify Magick","Identify Weapon Quality",
    "Identify Armor Quality","Weapon Smithing","Armor Smithing","Future Art","Future Sharp Weapons"}) do
    eq(Display.category({name=skill,remain=1}),"utility")
  end
end)

test("main skills row categories and style ids follow sorted skills and the heading stays neutral",function()
  local f,d=fakeSkills(); f:feed("Skill Remain Level",1)
  f:feed(" Swimming       1 1",2); f:feed(" Focus Force       20 3",3)
  f:feed(" First Aid       0 2",4); f:feed(" Future Art       4 1",5); f:feed("",6); f:advance(0)
  eq(f.lastRows[1].category,"neutral"); eq(f.lastRows[2].category,"combat")
  eq(f.lastRows[3].category,"ready"); eq(f.lastRows[4].category,"utility"); eq(f.lastRows[5].category,"utility")
  eq(f.lastRows[1].style_id,nil); eq(f.lastRows[2].style_id,"skill_combat")
  eq(f.lastRows[3].style_id,"skill_ready"); eq(f.lastRows[4].style_id,"skill_utility"); eq(f.lastRows[5].style_id,"skill_utility")
  eq(tonumber(f.lastRows[2].display_text:match("^%s*(%d+)%s")),10)
  eq(tonumber(f.lastRows[3].display_text:match("^%s*(%d+)%s")),42)
  eq(f.lastRows[4].display_text:match("^%s*(%S+)%s"),"23")
  eq(f.lastRows[5].display_text:match("^%s*(%S+)%s"),"?"); d:shutdown()
end)

test("main skills optional sort preferences are normalized copied and preserve the package argument",function()
  local config={primary="number",direction="asc",secondary="none",secondary_direction=false}
  local f,d=fakeSkills(true,config,"CustomHUD")
  eq(d.package_name,"CustomHUD"); eq(d.sort.primary,"number"); eq(d.sort.secondary_direction,"asc")
  assert(d.sort~=config); config.primary="level"; eq(d.sort.primary,"number")
  f:feed("Skill Remain Level",1); f:feed(" Future Art       0 9",2)
  f:feed(" Sharp Weapons       400 4",3); f:feed(" Brawling       1 1",4)
  f:feed(">",5); f:advance(0)
  eq(f.lastRows[2].display_text:match("^%s*(%S+)%s"),"1")
  eq(f.lastRows[3].display_text:match("^%s*(%S+)%s"),"2")
  eq(f.lastRows[4].display_text:match("^%s*(%S+)%s"),"?"); d:shutdown()
  local _,default=fakeSkills(); eq(default.sort.primary,"level"); eq(default.sort.direction,"desc")
  eq(default.sort.secondary,"uses"); eq(default.sort.secondary_direction,"asc"); default:shutdown()
end)

test("main skills setSort validates atomically without cancelling an active capture",function()
  local f,d=fakeSkills(); f:feed("Skill Remain Level",1); f:feed(" Sharp Weapons       400 4",2)
  local response,timer,generation,sort=d.response,d.timer,d.generation,d.sort
  for _,invalid in ipairs({false,true,"name",{primary="none"},{direction="up"},{extra=true},{secondary=false}}) do
    local result,err=d:setSort(invalid); eq(result,nil); eq(type(err),"string")
    eq(d.response,response); eq(d.timer,timer); eq(d.generation,generation); eq(d.sort,sort)
  end
  local result,err=d:setSort(nil); eq(result,nil); eq(type(err),"string")
  local config={primary="number",direction="desc",secondary="none"}
  local accepted=assert(d:setSort(config)); eq(accepted,d.sort); assert(d.sort~=config)
  config.direction="asc"; eq(d.sort.direction,"desc")
  eq(d.response,response); eq(d.timer,timer); eq(d.generation,generation)
  f:feed(" Stinging       1 1",3); f:feed(">",4); f:advance(0)
  eq(f.lastRows[2].display_text:match("^%s*(%S+)%s"),"57")
  eq(f.lastRows[3].display_text:match("^%s*(%S+)%s"),"2"); d:shutdown()
end)

test("main skills changing sort preserves a successful pending capture and affects subsequent captures",function()
  local f,d=fakeSkills(); f:feed("Skill Remain Level",1)
  f:feed(" Sharp Weapons       400 4",2); f:feed(" Stinging       1 1",3); f:feed(">",4)
  local pending,timer,generation=d.pending,d.timer,d.generation
  assert(d:setSort({primary="number",direction="desc",secondary="none"}))
  eq(d.pending,pending); eq(d.timer,timer); eq(d.generation,generation)
  local result=d:setSort({direction=false}); eq(result,nil); eq(d.pending,pending); eq(d.timer,timer)
  f:advance(0); eq(f.replacements,3)
  eq(f.lastRows[2].display_text:match("^%s*(%S+)%s"),"2")
  eq(f.lastRows[3].display_text:match("^%s*(%S+)%s"),"57")
  f:feed("Skill Remain Level",5); f:feed(" Sharp Weapons       400 4",6)
  f:feed(" Stinging       1 1",7); f:feed(">",8); f:advance(0)
  eq(f.replacements,6); eq(f.lastRows[2].display_text:match("^%s*(%S+)%s"),"57"); d:shutdown()
end)

test("main skills changing sort during a blank boundary retains the capture and readiness colors",function()
  local f,d=fakeSkills(); f:feed("Skill Remain Level",1)
  f:feed(" Swimming       0 4",2); f:feed(" First Aid       9 1",3); f:feed(" Brawling       0 2",4)
  f:feed("",5); local response,timer,generation=d.response,d.timer,d.generation
  assert(d:setSort({primary="category",direction="asc",secondary="ready",secondary_direction="desc"}))
  eq(d.response,response); eq(d.timer,timer); eq(d.generation,generation); f:advance(0)
  eq(f.lastRows[2].display_text:match("^%s*(%S+)%s"),"42"); eq(f.lastRows[2].style_id,"skill_combat")
  eq(f.lastRows[3].display_text:match("^%s*(%S+)%s"),"1"); eq(f.lastRows[3].style_id,"skill_ready")
  eq(f.lastRows[4].display_text:match("^%s*(%S+)%s"),"23"); eq(f.lastRows[4].style_id,"skill_ready")
  eq(f.lines[5],""); d:shutdown()
end)

test("main skills finish delegates to the shared sorter and retains captured source objects",function()
  local f,d=fakeSkills(); f:feed("Skill Remain Level",1)
  f:feed(" Sharp Weapons       400 4",2); f:feed(" Brawling       0 1",3)
  local response=d.response; local first,second=response.rows[1].skill,response.rows[2].skill
  local original=SkillSort.sorted; local calls=0
  SkillSort.sorted=function(items,config)
    calls=calls+1; eq(config,d.sort); eq(items[1],first); eq(items[2],second)
    return {second,first}
  end
  local ok,err=pcall(function() f:feed(">",4); f:advance(0) end)
  SkillSort.sorted=original; assert(ok,err); eq(calls,1)
  eq(response.rows[1].skill,first); eq(response.rows[2].skill,second)
  eq(first.name,"Sharp Weapons"); eq(first.level,4); eq(first.remain,400)
  eq(f.lastRows[2].display_text:match("^%s*(%S+)%s"),"1"); d:shutdown()
end)
test("skill filters normalize bounded strings without coercion or control characters",function()
  for _,query in ipairs({""," ","   ALL  ","AlL"}) do eq(Display.normalizeFilter(query),"") end
  eq(Display.normalizeFilter("  ID   Weapon   QUALITY  "),"id weapon quality")
  eq(Display.normalizeFilter("All Skills"),"all skills")
  eq(Display.normalizeFilter(string.rep("x",128)),string.rep("x",128))
  eq(Display.normalizeFilter(string.rep("é",64)),string.rep("é",64))
  local coerced=false
  local invalid={false,true,123,{},function() end,string.rep("x",129),string.rep("é",65),
    string.rep(" ",129),setmetatable({},{__tostring=function() coerced=true; return "ste" end})}
  for byte=0,31 do invalid[#invalid+1]="ste"..string.char(byte) end
  invalid[#invalid+1]="ste"..string.char(127)
  for _,query in ipairs(invalid) do
    local normalized,err=Display.normalizeFilter(query); eq(normalized,nil); eq(type(err),"string")
  end
  local normalized,err=Display.normalizeFilter(nil); eq(normalized,nil); eq(type(err),"string"); eq(coerced,false)
end)

test("skill filters use only leading full names shortened labels and the exact bite alias",function()
  for _,skill in ipairs({"Channeling","Climbing","Clawing","Conjuration"}) do
    eq(Display.matchesFilter(skill," C "),true)
  end
  for _,skill in ipairs({"Stealth","Stinging","Spellcasting","Identify Magick","Future Stealth"}) do
    eq(Display.matchesFilter(skill,"STE"),skill=="Stealth")
    eq(Display.matchesFilter(skill,"c"),false)
  end
  for full,short in pairs({["Sharp Weapons"]="Sharps",["Blunt Weapons"]="Blunts",["Pole Weapons"]="Poles",
    ["Throw Weapons"]="Throws",["Missile Weapons"]="Missiles"}) do
    eq(Display.matchesFilter(" ** "..full:upper(),short:upper()),true)
    eq(Display.matchesFilter(short,full:lower()),true)
  end
  eq(Display.matchesFilter(" ** sTeAlTh  ","sTEal"),true)
  eq(Display.matchesFilter("Biting","BITE"),true); eq(Display.matchesFilter("Biting","bit"),true)
  for _,query in ipairs({"bites","bite weapon","ting","weapons","gems","quality","steal.*"}) do
    eq(Display.matchesFilter("Biting",query),false)
    eq(Display.matchesFilter("Identify Weapon Quality",query),false)
    eq(Display.matchesFilter("Sharp Weapons",query),false)
  end
  eq(Display.matchesFilter("Future Biting","bite"),false)
  eq(Display.matchesFilter("Biting","bitingx"),false)
  eq(Display.matchesFilter("Future Art","all"),true)
  eq(Display.matchesFilter("Future Art",""),true)
  eq(Display.matchesFilter(nil,"ste"),false); eq(Display.matchesFilter({},""),false)
  eq(Display.matchesFilter("Stealth",nil),false)
end)

test("skill filters support current identify abbreviations including mineral and quality omissions",function()
  local aliases={
    ["Identify Gems/Minerals"]={"identify gems","ID","id gems","ID Gems/Minerals"},
    ["Identify Magick"]={"identify mag","ID","id magick"},
    ["Identify Weapon Quality"]={"identify weapon","ID","id weapon","ID Weapon Quality"},
    ["Identify Armor Quality"]={"identify armor","ID","id armor","ID Armor Quality"},
  }
  for full,queries in pairs(aliases) do
    for _,query in ipairs(queries) do eq(Display.matchesFilter(full,query),true) end
    eq(Display.matchesFilter(full,"id gems"),full=="Identify Gems/Minerals")
    eq(Display.matchesFilter(full,"id weapon"),full=="Identify Weapon Quality")
  end
  eq(Display.matchesFilter("ID Gems","identify gems/minerals"),true)
  eq(Display.matchesFilter("ID Weapon","identify weapon quality"),true)
  eq(Display.matchesFilter("ID Armor Quality","identify armor"),true)
  eq(Display.matchesFilter("Identify Future Art","id future"),true)
end)

test("future identify skills accept literal id prefixes only at the beginning",function()
  eq(Display.matchesFilter("Identify Foo","id f"),true)
  eq(Display.matchesFilter(" ** IDENTIFY   Future Art "," ID   F "),true)
  eq(Display.matchesFilter("Future Identify Foo","id f"),false)
  eq(Display.matchesFilter("IdentifyFoo","id f"),false)
  eq(Display.matchesFilter("Identify Foo","id f.*"),false)
  eq(Display.matchesFilter("Identify F.* Art","id f.*"),true)
  eq(Display.skillId("Identify Foo"),nil)
end)

test("skill filter metacharacters and code shaped strings remain literal data",function()
  local f,d=fakeSkills()
  local old=_G.__skillFilterExecuted; _G.__skillFilterExecuted=nil
  for _,query in ipairs({"c.*","^ste","%a+","[","*","ste;quit","ste|quit",
    "ste\\quit","$(quit)","_G.__skillFilterExecuted=true"}) do
    eq(Display.normalizeFilter(query),query:lower())
    eq(Display.matchesFilter("Stealth",query),false)
    eq(Display.matchesFilter("Channeling",query),false)
    assert(d:requestFilter(query)); eq(d:filterPending(),true); d:cancel()
  end
  eq(Display.matchesFilter("C.* Future Art","c.*"),true)
  eq(_G.__skillFilterExecuted,nil); _G.__skillFilterExecuted=old
  eq(f.replacements,0); eq(f.deletions,0); d:shutdown()
end)

test("skill filtering captures every row before sorting matches into the first native skill slots",function()
  local f,d=fakeSkills(true,{primary="name",direction="desc",secondary="none"})
  assert(d:requestFilter(" C ")); eq(d:filterPending(),true)
  f:feed("Skill Remain Level",10)
  local raw={" Sharp Weapons       400 9"," Climbing       10 2"," Channeling       0 7"," Clawing       30 5"}
  f:feed(raw[1],11); f:feed("An enemy attacks.",12); f:feed(raw[2],13)
  f:feed("",14); f:feed(raw[3],15); f:feed(raw[4],16)
  eq(#d.response.rows,4); eq(d.pending,nil); eq(f.replacements,0); eq(f.deletions,0)
  eq(f.lines[11],raw[1]); f:feed(">",17)
  eq(d:filterPending(),true); local rows=d.pending; eq(#rows,5)
  for index,number in ipairs({10,11,13,15,16}) do eq(rows[index].line_number,number) end
  for index,source in ipairs(raw) do eq(rows[index+1].source_line,source) end
  eq(rows[2].display_text,Display.format({name="Climbing",level=2,remain=10},{6,10,3,4}))
  eq(rows[3].display_text,Display.format({name="Clawing",level=5,remain=30},{6,10,3,4}))
  eq(rows[4].display_text,Display.format({name="Channeling",level=7,remain=0},{6,10,3,4}))
  eq(rows[4].style_id,"skill_ready")
  eq(rows[5].remove,true); eq(rows[5].display_text,nil)
  eq(f.lines[12],"An enemy attacks."); eq(f.lines[14],""); eq(f.lines[17],">")
  eq(f.deletions,0); f:advance(0); eq(f.lastRows,rows); eq(d:filterPending(),false)
  eq(f.replacements,4); eq(f.deletions,1); eq(f.lines[11],rows[2].display_text)
  eq(f.lines[13],rows[3].display_text); eq(f.lines[15],rows[4].display_text)
  eq(f.lines[12],"An enemy attacks."); eq(f.lines[14],""); eq(f.lines[16],">")
  eq(f.cursor,16); eq(f.column,3); d:shutdown()
end)

test("skill filters select multiple prefixes and preserve future skills and authoritative ids",function()
  local names={"Climbing","Channeling","Stealth","Stinging","Biting","Identify Gems/Minerals","Future Art"}
  local cases={
    {query="c",ids={15,41}},{query="STE",ids={29}},{query="bite",ids={46}},
    {query="id gems",ids={14}},{query="future",ids={"?"}},
  }
  for _,case in ipairs(cases) do
    local f,d=fakeSkills(true,{primary="number",direction="asc",secondary="none"})
    assert(d:requestFilter(case.query)); f:feed("Skill Remain Level",0)
    for index,skill in ipairs(names) do f:feed(" *"..skill.."       10 2",index) end
    f:feed(">",8); local rows=d.pending; eq(#rows,8)
    for index,id in ipairs(case.ids) do eq(rows[index+1].display_text:match("^%s*(%S+)%s"),tostring(id)) end
    for index=#case.ids+2,#rows do eq(rows[index].remove,true) end
    f:advance(0); eq(f.lastRows,rows)
    eq(f.deletions,#names-#case.ids); eq(f.replacements,#case.ids+1)
    for index=1,#case.ids do eq(f.lines[index],rows[index+1].display_text) end
    eq(f.lines[#case.ids+1],">"); eq(f.cursor,#case.ids+1); d:shutdown()
  end
  eq(Display.matchesFilter("Quantum Élan 🐉","QUANTUM"),true)
end)

test("skill filters leave mode off and keep the raw matched header and rows in server order",function()
  local f,d=fakeSkills(false,{primary="level",direction="desc"})
  local heading="  Skill                     Remain Level  "
  local first=" * Climbing              17    1   "
  local second=" CHANNELING       0 99"
  assert(d:requestFilter("C")); eq(d.enabled,false)
  f:feed(heading,1); f:feed(" Sharp Weapons       400 4",2)
  f:feed(first,3); f:feed(second,4); f:feed(">",5)
  local rows=d.pending; eq(#rows,4); eq(rows[1].display_text,heading)
  eq(rows[2].display_text,first); eq(rows[2].source_line," Sharp Weapons       400 4")
  eq(rows[3].display_text,second); eq(rows[3].source_line,first)
  eq(rows[2].style_id,nil); eq(rows[3].style_id,nil); eq(rows[4].remove,true)
  eq(d.enabled,false); f:advance(0); eq(f.lastRows,rows); eq(d.enabled,false); eq(d:filterPending(),false)
  eq(f.lines[1],heading); eq(f.lines[2],first); eq(f.lines[3],second); eq(f.lines[4],">")
  eq(f.deletions,1); eq(f.replacements,3); eq(f.cursor,4); eq(f.column,3)
  f:feed("Skill Remain Level",20); f:feed(" Stealth       3 1",21); f:feed(">",22)
  eq(d.response,nil); eq(d.pending,nil); eq(d.timer,nil); eq(f.lastRows,rows); d:shutdown()
end)

test("skill filters with no matches rewrite only the header and flag every original skill slot",function()
  for _,enabled in ipairs({true,false}) do
    local f,d=fakeSkills(enabled); assert(d:requestFilter("  NoSuch   Skill  "))
    f:feed("Skill Remain Level",1); f:feed(" Climbing       17 1",2)
    f:feed("Combat continues.",3); f:feed(" Stealth       3 1",4); f:feed(">",5)
    local rows=d.pending; eq(#rows,3); eq(rows[1].display_text,"No skills match: nosuch skill")
    eq(rows[2].remove,true); eq(rows[2].line_number,2); eq(rows[2].source_line," Climbing       17 1")
    eq(rows[3].remove,true); eq(rows[3].line_number,4); eq(rows[3].source_line," Stealth       3 1")
    eq(rows[2].display_text,nil); eq(rows[3].display_text,nil)
    eq(f.replacements,0); eq(f.deletions,0); f:advance(0); eq(f.lastRows,rows)
    eq(f.lines[1],"No skills match: nosuch skill"); eq(f.lines[2],"Combat continues."); eq(f.lines[3],">")
    eq(f.replacements,1); eq(f.deletions,2); eq(f.cursor,3); eq(f.column,3)
    eq(d.enabled,enabled); eq(d:filterPending(),false); d:shutdown()
  end
end)

test("skill filters on an empty response show no match while bare and all keep empty tables unchanged",function()
  local f,d=fakeSkills(false); assert(d:requestFilter("ste"))
  f:feed("Skill Remain Level",1); f:feed(">",2)
  eq(#d.pending,1); eq(d.pending[1].display_text,"No skills match: ste")
  f:advance(0); eq(f.lines[1],"No skills match: ste"); eq(f.lines[2],">"); d:shutdown()
  for _,query in ipairs({"","all"}) do
    local empty,display=fakeSkills(); assert(display:requestFilter(query))
    empty:feed("Skill Remain Level",1); empty:feed(">",2)
    eq(display.pending,nil); eq(display:filterPending(),false); eq(empty.replacements,0); display:shutdown()
  end
end)

test("bare and all filter requests retain full output in either mode",function()
  for _,query in ipairs({""," ALL "}) do
    for _,enabled in ipairs({true,false}) do
      local f,d=fakeSkills(enabled); assert(d:requestFilter(query)); eq(d.filter_query,"")
      f:feed("Skill Remain Level",1); f:feed(" Sharp Weapons       400 4",2)
      f:feed(" Climbing       1 5",3); f:feed(">",4)
      local rows=d.pending; eq(#rows,3)
      for _,row in ipairs(rows) do eq(row.remove,nil) end
      if enabled then
        eq(rows[2].display_text:match("^%s*(%S+)%s"),"15")
        eq(rows[3].display_text:match("^%s*(%S+)%s"),"2")
      else
        eq(rows[1].display_text,"Skill Remain Level")
        eq(rows[2].display_text," Sharp Weapons       400 4"); eq(rows[3].display_text," Climbing       1 5")
      end
      f:advance(0); eq(d:filterPending(),false); eq(d.enabled,enabled); d:shutdown()
    end
  end
end)

test("filterPending rejects duplicate requests without disturbing intent capture boundary or deferred rows",function()
  for _,phase in ipairs({"intent","collecting","blank","deferred"}) do
    local f,d=fakeSkills(); eq(d:filterPending(),false); assert(d:requestFilter("ste"))
    if phase~="intent" then f:feed("Skill Remain Level",1); f:feed(" Stealth       3 1",2) end
    if phase=="blank" then f:feed("",3) elseif phase=="deferred" then f:feed(">",3) end
    local timer,generation,response,pending,query=d.timer,d.generation,d.response,d.pending,d.filter_query
    local accepted,err=d:requestFilter("c"); eq(accepted,nil); eq(type(err),"string")
    eq(d:filterPending(),true); eq(d.timer,timer); eq(d.generation,generation)
    eq(d.response,response); eq(d.pending,pending); eq(d.filter_query,query)
    accepted,err=d:requestFilter("\nquit"); eq(accepted,nil); eq(type(err),"string")
    eq(d.timer,timer); eq(d.generation,generation); eq(d.response,response); eq(d.pending,pending)
    if phase=="intent" then f:feed("Skill Remain Level",1); f:feed(" Stealth       3 1",2) end
    if phase=="intent" or phase=="collecting" then f:feed(">",3) end
    f:advance(0); eq(f.lastRows[2].display_text:match("^%s*(%S+)%s"),"29")
    eq(d:filterPending(),false); d:shutdown()
  end
end)

test("valid filter requests cancel an earlier unrestricted capture and invalidate its late callbacks",function()
  for _,phase in ipairs({"collecting","deferred"}) do
    local f,d=fakeSkills(); f:feed("Skill Remain Level",1); f:feed(" Sharp Weapons       400 4",2)
    if phase=="deferred" then f:feed(">",3) end
    local timer=d.timer; local late=f.timers[timer].fn; eq(d:filterPending(),false)
    assert(d:requestFilter("ste")); local requestTimer=d.timer
    eq(f.timers[timer],nil); eq(d.response,nil); eq(d.pending,nil)
    late(); eq(d.timer,requestTimer); eq(d:filterPending(),true); eq(f.replacements,0)
    f:feed("Skill Remain Level",10); f:feed(" Stealth       3 1",11); f:feed(">",12)
    f:advance(0); eq(f.lastRows[2].display_text:match("^%s*(%S+)%s"),"29"); d:shutdown()
  end
end)

test("invalid filter requests do not cancel ordinary output and scheduling failures clear intent",function()
  local f,d=fakeSkills(); f:feed("Skill Remain Level",1); f:feed(" Stealth       3 1",2)
  local response,timer,generation=d.response,d.timer,d.generation
  for _,query in ipairs({false,{},string.rep("x",129),"ste\nquit"}) do
    local result,err=d:requestFilter(query); eq(result,nil); eq(type(err),"string")
    eq(d.response,response); eq(d.timer,timer); eq(d.generation,generation); eq(d:filterPending(),false)
  end
  d:cancel(); f.failSchedule=true
  local result,err=d:requestFilter("ste"); eq(result,nil); eq(type(err),"string")
  eq(d:filterPending(),false); eq(d.timer,nil); eq(d.pending,nil); eq(d.response,nil)
  f.failSchedule=false; assert(d:requestFilter("ste")); d:shutdown()
  result,err=d:requestFilter("ste"); eq(result,nil); eq(type(err),"string"); eq(d:filterPending(),false)
end)

test("skill filter intent and incomplete captures expire and cannot filter a later response",function()
  for _,phase in ipairs({"intent","collecting"}) do
    local f,d=fakeSkills(); assert(d:requestFilter("ste")); eq(f.timers[d.timer].delay,Display.RESPONSE_TIMEOUT)
    if phase=="collecting" then f:feed("Skill Remain Level",1); f:feed(" Stealth       3 1",2) end
    f:advance(Display.RESPONSE_TIMEOUT); eq(d:filterPending(),false); eq(d.response,nil); eq(next(f.timers),nil)
    eq(f.replacements,0); eq(f.deletions,0)
    f:feed("Skill Remain Level",10); f:feed(" Climbing       1 1",11); f:feed(" Stealth       3 1",12)
    f:feed(">",13); f:advance(0); eq(#f.lastRows,3)
    for _,row in ipairs(f.lastRows) do eq(row.remove,nil) end
    d:shutdown()
  end
end)

test("skill filter lifecycle cancellation clears every phase and invalidates delayed callbacks",function()
  for _,action in ipairs({"cancel","disconnect","install","uninstall","shutdown","menu","off"}) do
    for _,phase in ipairs({"intent","collecting","blank","deferred"}) do
      local f,d=fakeSkills(); assert(d:requestFilter("ste"))
      if phase~="intent" then f:feed("Skill Remain Level",1); f:feed(" Stealth       3 1",2) end
      if phase=="blank" then f:feed("",3) elseif phase=="deferred" then f:feed(">",3) end
      local timer=d.timer; local late=f.timers[timer].fn
      if action=="cancel" then d:cancel()
      elseif action=="disconnect" then f:emit("sysDisconnectionEvent")
      elseif action=="install" then f:emit("sysInstallPackage",nil,"DragonsGateHUD")
      elseif action=="uninstall" then f:emit("sysUninstallPackage",nil,"DragonsGateHUD")
      elseif action=="menu" then f:feed("Dragon's Gate Menu",4)
      elseif action=="off" then d:setEnabled(false)
      else d:shutdown() end
      eq(d:filterPending(),false); eq(d.filter_query,nil); eq(d.pending_filter,nil)
      eq(d.response,nil); eq(d.pending,nil); eq(d.timer,nil); eq(next(f.timers),nil)
      late(); eq(f.replacements,0); eq(f.deletions,0); d:shutdown()
    end
  end
end)

test("skill filters apply once and a replacement header does not inherit an already consumed intent",function()
  local f,d=fakeSkills(); assert(d:requestFilter("ste"))
  f:feed("Skill Remain Level",1); f:feed(" Stealth       3 1",2); f:feed(">",3); f:advance(0)
  eq(d:filterPending(),false); assert(d:requestFilter("ste"))
  f:feed("Skill Remain Level",10); f:feed(" Stealth       3 1",11)
  local late=f.timers[d.timer].fn
  f:feed("Skill Remain Level",12); eq(d:filterPending(),false)
  f:feed(" Climbing       1 1",13); f:feed(" Stealth       3 1",14)
  late(); eq(#d.response.rows,2); f:feed(">",15); f:advance(0); eq(#f.lastRows,3)
  for _,row in ipairs(f.lastRows) do eq(row.remove,nil) end
  d:shutdown()
end)

test("filtered rewrites and removals keep every original coordinate and source guard for the adapter",function()
  for _,changedRow in ipairs({1,2,4}) do
    local f,d=fakeSkills(); assert(d:requestFilter("ste"))
    f:feed("Skill Remain Level",1); f:feed(" Climbing       1 1",2)
    f:feed("Combat continues.",3); f:feed(" Stealth       3 1",4); f:feed(">",5)
    local rows=d.pending; eq(rows[1].source_line,"Skill Remain Level")
    eq(rows[2].line_number,2); eq(rows[2].source_line," Climbing       1 1")
    eq(rows[3].line_number,4); eq(rows[3].source_line," Stealth       3 1"); eq(rows[3].remove,true)
    f.lines[changedRow]="Unrelated output."; f:advance(0)
    eq(f.replacements,0); eq(f.deletions,0); eq(f.lines[changedRow],"Unrelated output.")
    eq(f.lines[3],"Combat continues."); eq(f.lines[5],">"); d:shutdown()
  end
end)
