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
  for _,query in ipairs({"bites","bite weapon","ting","weapon","gems","quality","steal.*"}) do
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


-- Multi-command regression coverage uses synthetic console rows and virtual time.
local regressionSkillRows={
  " Sharp Weapons       400 4"," Climbing       17 1",
  " Channeling       0 9"," Stealth       3 2",
}
local function assertRegressionSkills(f,first,names,enabled)
  if enabled then assert(f.lines[first]:match("^Number%s+Skill%s+LVL%s+USES$"))
  else eq(f.lines[first],"Skill Remain Level") end
  for index,expected in ipairs(names) do
    local value=assert(f.lines[first+index])
    if enabled then
      assert(value:find(expected,1,true),"missing skill "..expected.." in "..value)
    else
      local raw
      for _,source in ipairs(regressionSkillRows) do if source:find(expected,1,true) then raw=source end end
      eq(value,assert(raw))
    end
  end
end

test("skill filter repeated prefixes then bare and all retain complete independent console tables",function()
  for _,enabled in ipairs({true,false}) do
    for _,boundary in ipairs({">",""}) do
      local f,d=fakeSkills(enabled,{primary="number",direction="asc",secondary="none"})
      f:feed("A notice before skills.",0)
      local full=enabled and {"Sharps","Climbing","Stealth","Channeling"} or {"Sharp Weapons","Climbing","Channeling","Stealth"}
      local commands={
        {query="c",names={"Climbing","Channeling"}},{query="ste",names={"Stealth"}},
        {query="c",names={"Climbing","Channeling"}},{names=full},{query="all",names=full},
      }
      for _,command in ipairs(commands) do
        local history={}; for row,value in pairs(f.lines) do history[row]=value end
        eq(d:filterPending(),false)
        if command.query then assert(d:requestFilter(command.query))
        else d:cancel() end -- The runtime cancels filter intent for manual bare skill.
        local echo=f.cursor+1
        f:feed(">skill"..(command.query and (" "..command.query) or ""),echo)
        local first=echo+1; local previousRows=f.lastRows; local deleted=f.deletions
        f:feed("Skill Remain Level",first)
        for index,raw in ipairs(regressionSkillRows) do f:feed(raw,first+index) end
        f:feed(boundary,first+5)
        for index,raw in ipairs(regressionSkillRows) do eq(f.lines[first+index],raw) end
        f:advance(0)
        assertRegressionSkills(f,first,command.names,enabled)
        eq(f.deletions-deleted,4-#command.names)
        eq(f.lines[first+#command.names+1],boundary); eq(f.cursor,first+#command.names+1)
        eq(f.lines[f.cursor+1],nil); eq(f.column,3)
        for row,value in pairs(history) do eq(f.lines[row],value) end
        if not enabled and not command.query then eq(f.lastRows,previousRows) end
        eq(d.enabled,enabled); eq(d:filterPending(),false); eq(d.response,nil); eq(d.pending,nil)
        eq(next(f.timers),nil)
      end
      d:shutdown()
    end
  end
end)

test("skill filters survive delayed headers rows and final prompts within their response deadlines",function()
  for _,enabled in ipairs({true,false}) do
    for _,boundary in ipairs({">",""}) do
      local f,d=fakeSkills(enabled,{primary="number",direction="asc",secondary="none"})
      assert(d:requestFilter("c")); local intentCallback=f.timers[d.timer].fn
      f:feed(">skill c",0); f:advance(Display.RESPONSE_TIMEOUT-.25)
      eq(d:filterPending(),true); eq(f.deletions,0)
      f:feed("Skill Remain Level",1); local responseTimer=d.timer
      intentCallback(); eq(d.timer,responseTimer); eq(d.response.filter_query,"c")
      f:advance(2); f:feed(regressionSkillRows[1],2)
      f:advance(2); f:feed(regressionSkillRows[2],3)
      f:advance(.5); f:feed(regressionSkillRows[3],4)
      eq(f.replacements,0); eq(f.deletions,0); eq(#d.response.rows,3)
      local watchdog=f.timers[d.timer].fn
      f:feed(boundary,5); watchdog(); eq(f.replacements,0)
      f:advance(0); assertRegressionSkills(f,1,{"Climbing","Channeling"},enabled)
      eq(f.deletions,1); eq(f.lines[4],boundary); eq(f.cursor,4)
      eq(d:filterPending(),false); eq(next(f.timers),nil)
      local replacements,deletions=f.replacements,f.deletions
      f:advance(Display.RESPONSE_TIMEOUT+1)
      f:feed("[0] 10/10 hp, 8/8 ftg >",5)
      eq(f.lines[5],"[0] 10/10 hp, 8/8 ftg >")
      eq(f.replacements,replacements); eq(f.deletions,deletions); eq(d.pending,nil)
      eq(f.lines[6],nil); d:shutdown()
    end
  end
end)

test("skill filters cancel an internal blank boundary and let the final prompt supersede its callback",function()
  for _,enabled in ipairs({true,false}) do
    local f,d=fakeSkills(enabled,{primary="number",direction="asc",secondary="none"})
    assert(d:requestFilter("c")); f:feed("Skill Remain Level",1)
    f:feed(regressionSkillRows[1],2); f:feed("",3)
    local internalTimer=d.timer; local internalCallback=f.timers[internalTimer].fn
    f:feed("An enemy strikes you for 12 damage.",4); f:feed(regressionSkillRows[2],5)
    f:feed(regressionSkillRows[3],6); f:feed(regressionSkillRows[4],7)
    local collectingTimer=d.timer
    internalCallback(); eq(d.timer,collectingTimer); eq(#d.response.rows,4)
    f:advance(.25); eq(f.replacements,0); eq(f.deletions,0)
    f:feed("",8); local finalTimer=d.timer; local finalCallback=f.timers[finalTimer].fn
    f:feed("[0] 10/10 hp, 8/8 ftg >",9); local replacementTimer=d.timer
    internalCallback(); finalCallback(); eq(d.timer,replacementTimer)
    eq(f.timers[internalTimer],nil); eq(f.timers[finalTimer],nil)
    local rows=d.pending; eq(#rows,5)
    eq(rows[2].line_number,2); eq(rows[3].line_number,5)
    eq(rows[4].remove,true); eq(rows[5].remove,true)
    f:advance(0)
    assert(f.lines[2]:find("Climbing",1,true)); assert(f.lines[5]:find("Channeling",1,true))
    eq(f.lines[3],""); eq(f.lines[4],"An enemy strikes you for 12 damage.")
    eq(f.lines[6],""); eq(f.lines[7],"[0] 10/10 hp, 8/8 ftg >")
    eq(f.lines[8],nil); eq(f.cursor,7); eq(f.deletions,2); eq(f.replacements,3)
    eq(d.enabled,enabled); eq(d:filterPending(),false); eq(next(f.timers),nil)
    d:shutdown()
  end
end)

test("cancelled filter callbacks cannot change a subsequent bare or all skill response",function()
  for _,enabled in ipairs({true,false}) do
    for _,phase in ipairs({"intent","collecting","blank","deferred"}) do
      for _,nextCommand in ipairs({"bare","all"}) do
        local f,d=fakeSkills(enabled,{primary="number",direction="asc",secondary="none"})
        f:feed(">skill ste",0); assert(d:requestFilter("ste"))
        if phase~="intent" then
          f:feed("Skill Remain Level",1); f:feed(regressionSkillRows[1],2); f:feed(regressionSkillRows[4],3)
        end
        if phase=="blank" then f:feed("",4) elseif phase=="deferred" then f:feed(">",4) end
        local oldTimer=d.timer; local late=f.timers[oldTimer].fn
        d:cancel(); eq(f.timers[oldTimer],nil)
        f:feed(">skill"..(nextCommand=="all" and " all" or ""),f.cursor+1)
        if nextCommand=="all" then assert(d:requestFilter("all")) end
        local first=f.cursor+1; f:feed("Skill Remain Level",first)
        for index,raw in ipairs(regressionSkillRows) do f:feed(raw,first+index) end
        f:feed(">",first+5)
        local timer,response,pending,generation=d.timer,d.response,d.pending,d.generation
        late(); late()
        eq(d.timer,timer); eq(d.response,response); eq(d.pending,pending); eq(d.generation,generation)
        eq(f.replacements,0); eq(f.deletions,0)
        f:advance(0)
        local full=enabled and {"Sharps","Climbing","Stealth","Channeling"} or {"Sharp Weapons","Climbing","Channeling","Stealth"}
        assertRegressionSkills(f,first,full,enabled)
        eq(f.deletions,0); eq(f.lines[first+5],">"); eq(f.cursor,first+5)
        if phase~="intent" then
          eq(f.lines[1],"Skill Remain Level"); eq(f.lines[2],regressionSkillRows[1]); eq(f.lines[3],regressionSkillRows[4])
        end
        local replacements=f.replacements; late(); eq(f.replacements,replacements); eq(f.deletions,0)
        eq(d.enabled,enabled); eq(d:filterPending(),false); eq(next(f.timers),nil); d:shutdown()
      end
    end
  end
end)

test("a deferred filtered response preserves later look output and interleaved combat",function()
  for _,enabled in ipairs({true,false}) do
    local f,d=fakeSkills(enabled); assert(d:requestFilter("ste"))
    f:feed(">skill ste",0); f:feed("Skill Remain Level",1); f:feed(regressionSkillRows[1],2)
    f:feed("An enemy strikes you for 12 damage.",3)
    f:feed(regressionSkillRows[2],4); f:feed(regressionSkillRows[3],5); f:feed(regressionSkillRows[4],6)
    f:feed(">",7); local replacement=d.timer
    f:feed(">look",8); f:feed("A room description.",9); f:feed("[0] 10/10 hp, 8/8 ftg >",10)
    eq(d.timer,replacement); eq(f.replacements,0); eq(f.deletions,0)
    f:advance(0); assertRegressionSkills(f,1,{"Stealth"},enabled)
    eq(f.lines[0],">skill ste"); eq(f.lines[3],"An enemy strikes you for 12 damage.")
    eq(f.lines[4],">"); eq(f.lines[5],">look"); eq(f.lines[6],"A room description.")
    eq(f.lines[7],"[0] 10/10 hp, 8/8 ftg >"); eq(f.lines[8],nil)
    eq(f.cursor,7); eq(f.column,3); eq(f.replacements,2); eq(f.deletions,3)
    f:advance(Display.RESPONSE_TIMEOUT+1); eq(f.replacements,2); eq(f.deletions,3)
    eq(d:filterPending(),false); eq(next(f.timers),nil); d:shutdown()
  end
end)

test("blank terminated no match filters preserve combat blanks and a delayed prompt exactly once",function()
  for _,enabled in ipairs({true,false}) do
    local f,d=fakeSkills(enabled); assert(d:requestFilter("nosuch"))
    f:feed(">skill nosuch",0); f:feed("Skill Remain Level",1)
    f:feed(regressionSkillRows[1],2); f:feed("Combat continues.",3); f:feed(regressionSkillRows[4],4)
    f:feed("",5); local boundary=d.timer; local late=f.timers[boundary].fn
    f:feed("An enemy retreats.",6); f:advance(0)
    eq(f.lines[0],">skill nosuch"); eq(f.lines[1],"No skills match: nosuch")
    eq(f.lines[2],"Combat continues."); eq(f.lines[3],""); eq(f.lines[4],"An enemy retreats.")
    eq(f.lines[5],nil); eq(f.cursor,4); eq(f.deletions,2); eq(f.replacements,1)
    eq(d:filterPending(),false); eq(d.pending,nil); eq(next(f.timers),nil)
    late(); f:advance(Display.RESPONSE_TIMEOUT+1); f:feed(">",5)
    eq(f.lines[3],""); eq(f.lines[4],"An enemy retreats."); eq(f.lines[5],">")
    eq(f.replacements,1); eq(f.deletions,2); eq(d.enabled,enabled); eq(next(f.timers),nil)
    assert(d:requestFilter("ste")); f:feed(">skill ste",6); f:feed("Skill Remain Level",7)
    f:feed(regressionSkillRows[1],8); f:feed(regressionSkillRows[4],9); f:feed(">",10)
    f:advance(0); assertRegressionSkills(f,7,{"Stealth"},enabled)
    eq(f.lines[1],"No skills match: nosuch"); eq(f.lines[5],">"); eq(f.lines[9],">")
    eq(f.lines[10],nil); eq(f.cursor,9); eq(f.deletions,3); eq(f.replacements,3)
    eq(d:filterPending(),false); eq(next(f.timers),nil); d:shutdown()
  end
end)


-- The named weapons group is an exact catalog allowlist, not a substring search.
-- Keep fixtures independent of the production allowlist so accidental widening fails.
local groupedWeaponCases={
  {name="Sharp Weapons",id=2,remain=400,level=4},
  {name="Blunt Weapons",id=3,remain=395,level=4},
  {name="Pole Weapons",id=4,remain=400,level=4},
  {name="Throw Weapons",id=5,remain=269,level=3},
  {name="Missile Weapons",id=6,remain=550,level=5},
  {name="Biting",id=46,remain=414,level=4},
  {name="Clawing",id=47,remain=0,level=3},
  {name="Breath Weapon",id=49,remain=200,level=2},
  {name="Webbing",id=48,remain=25,level=3},
  {name="Stinging",id=57,remain=0,level=2},
}
local groupedWeaponExcluded={
  {name="Shield Parry",id=7,remain=0,level=99},
  {name="First Aid",id=42,remain=0,level=98},
  {name="Focus Force",id=10,remain=0,level=97},
  {name="Weapon Smithing",id=35,remain=0,level=96},
  {name="Identify Weapon Quality",id=32,remain=0,level=95},
  {name="Future Weapons",remain=0,level=94},
  {name="Weapons Training",remain=0,level=93},
  {name="Swimming",id=23,remain=0,level=92},
}
local function groupedWeaponRaw(skill)
  return " "..skill.name.."       "..skill.remain.." "..skill.level
end
local function groupedWeaponFixture()
  local result={}
  for _,skill in ipairs(groupedWeaponCases) do result[#result+1]=skill end
  for _,skill in ipairs(groupedWeaponExcluded) do result[#result+1]=skill end
  return result
end
local function groupedWeaponFeed(f,first,skills,boundary)
  f:feed("Skill Remain Level",first)
  for index,skill in ipairs(skills) do f:feed(groupedWeaponRaw(skill),first+index) end
  f:feed(boundary or ">",first+#skills+1)
end
local function groupedWeaponIds(rows)
  local ids={}
  for index=2,#rows do
    local row=rows[index]
    if not row.remove then ids[#ids+1]=assert(row.display_text:match("^%s*(%S+)%s")) end
  end
  return table.concat(ids,",")
end

test("skill weapons exact normalized keyword includes only five weapons and five natural attacks",function()
  eq(#groupedWeaponCases,10)
  for _,query in ipairs({"weapons","WEAPONS","  WeApOnS   "}) do
    eq(Display.normalizeFilter(query),"weapons")
    local seen={}
    for _,skill in ipairs(groupedWeaponCases) do
      eq(Display.matchesFilter(skill.name,query),true)
      local messy="\27[32m  ** "..skill.name:upper():gsub(" "," \t ").."  \27[0m"
      eq(Display.matchesFilter(messy,query),true)
      eq(Display.skillId(skill.name),skill.id); assert(not seen[skill.id]); seen[skill.id]=true
    end
  end
end)

test("skill weapons recognizes existing canonical shortened weapon names without broad aliases",function()
  for alias,id in pairs({Sharps=2,Blunts=3,Poles=4,Throws=5,Missiles=6}) do
    eq(Display.matchesFilter(alias,"weapons"),true)
    eq(Display.matchesFilter(" ** "..alias:upper(),"  WEAPONS  "),true)
    eq(Display.skillId(alias),id)
  end
  for _,uncatalogued in ipairs({"Claw","Bite","Breath","Web","Sting","Sharp","Blunt","Pole","Throw","Missile"}) do
    eq(Display.matchesFilter(uncatalogued,"weapons"),false)
  end
end)

test("skill weapons excludes support smithing identify and future arbitrary weapons prose",function()
  local excluded={"Brawling","Shield Parry","First Aid","Focus Force","Quickdraw","Dodging","Disarming",
    "Armor Smithing","Weapon Smithing","Identify Weapon Quality","ID Weapon","ID Weapon Quality",
    "Weapons","Weapons Training","Future Weapons","Future Sharp Weapons","Sharp Weapons Training",
    "Breath Weapons","Future Biting","Webbing Training","Quantum Weapons"}
  for _,skill in ipairs(excluded) do
    eq(Display.matchesFilter(skill,"weapons"),false)
    eq(Display.matchesFilter(" ** "..skill:upper(),"  WEAPONS  "),false)
    eq(Display.matchesFilter(skill,"all"),true)
  end
  for _,skill in ipairs(groupedWeaponExcluded) do eq(Display.matchesFilter(skill.name,"weapons"),false) end
end)

test("skill weapons reserves only the exact keyword and keeps singular and ordinary literal prefixes",function()
  for _,query in ipairs({"weapon","weapo","weap","WEA"}) do
    eq(Display.matchesFilter("Weapon Smithing",query),true)
    eq(Display.matchesFilter("Weapons Training",query),true)
    eq(Display.matchesFilter("Sharp Weapons",query),false)
    eq(Display.matchesFilter("Biting",query),false)
  end
  eq(Display.matchesFilter("Clawing","c"),true)
  eq(Display.matchesFilter("Climbing","c"),true)
  eq(Display.matchesFilter("Stealth","ste"),true)
  eq(Display.matchesFilter("Stinging","ste"),false)
  eq(Display.matchesFilter("Identify Weapon Quality","id"),true)
  eq(Display.matchesFilter("Biting","bite"),true)
  eq(Display.matchesFilter("Webbing","w"),true)
  for _,case in ipairs({
    {query="weapons training",name="Weapons Training"},
    {query="weaponsx",name="Weaponsx"},
    {query="weapons.*",name="Weapons.* Training"},
    {query="weapons;quit",name="Weapons;quit"},
  }) do
    eq(Display.matchesFilter(case.name,case.query),true)
    for _,skill in ipairs(groupedWeaponCases) do eq(Display.matchesFilter(skill.name,case.query),false) end
  end
end)

test("skill weapons enabled integration captures the full response then preserves ids sorting colors and aligned columns",function()
  local f,d=fakeSkills(); local fixture=groupedWeaponFixture()
  assert(d:requestFilter("  WEAPONS  ")); f:feed(">skill weapons",0)
  f:feed("Skill Remain Level",1)
  for index,skill in ipairs(fixture) do f:feed(groupedWeaponRaw(skill),1+index) end
  eq(#d.response.rows,#fixture); eq(f.replacements,0); eq(f.deletions,0)
  for index,skill in ipairs(fixture) do
    eq(f.lines[1+index],groupedWeaponRaw(skill)); eq(d.response.rows[index].skill.name,skill.name)
  end
  f:feed(">",#fixture+2)
  local rows=d.pending; eq(#rows,#fixture+1)
  eq(groupedWeaponIds(rows),"6,3,4,2,46,47,48,5,57,49")
  eq(rows[1].category,"neutral"); eq(rows[1].style_id,nil)
  local byId={}; for _,skill in ipairs(groupedWeaponCases) do byId[skill.id]=skill end
  local heading=string.format("%6s  %-13s  %3s  %4s","Number","Skill","LVL","USES")
  eq(rows[1].display_text,heading)
  for index=2,11 do
    local row=rows[index]; local id=tonumber(row.display_text:match("^%s*(%d+)%s"))
    local skill=assert(byId[id]); local category=skill.remain==0 and "ready" or "combat"
    eq(row.category,category); eq(row.style_id,"skill_"..category); eq(row.remove,nil)
    eq(row.display_text,string.format("%6d  %-13s  %3d  %4d",id,Display.displayName(skill.name),skill.level,skill.remain))
    eq(#row.display_text,#heading)
  end
  for index=12,#rows do eq(rows[index].remove,true); eq(rows[index].display_text,nil) end
  eq(f.replacements,0); eq(f.deletions,0); f:advance(0)
  eq(f.lastRows,rows); eq(f.deletions,#fixture-10); eq(f.replacements,11)
  eq(f.lines[0],">skill weapons"); eq(f.lines[12],">"); eq(f.lines[13],nil)
  eq(f.cursor,12); eq(f.column,3); eq(d:filterPending(),false); eq(next(f.timers),nil); d:shutdown()
end)

test("skill weapons formatting off filters only possessed rows and leaves server order styling and toggle unchanged",function()
  local f,d=fakeSkills(false); local fixture=groupedWeaponFixture()
  assert(d:requestFilter("weapons")); groupedWeaponFeed(f,1,fixture)
  local rows=d.pending; eq(#rows,#fixture+1); eq(rows[1].display_text,"Skill Remain Level")
  for index,skill in ipairs(groupedWeaponCases) do
    local row=rows[index+1]; eq(row.display_text,groupedWeaponRaw(skill))
    eq(row.category,"neutral"); eq(row.style_id,nil); eq(row.remove,nil)
  end
  for index=12,#rows do eq(rows[index].remove,true) end
  f:advance(0); eq(f.lines[1],"Skill Remain Level")
  for index,skill in ipairs(groupedWeaponCases) do eq(f.lines[index+1],groupedWeaponRaw(skill)) end
  eq(f.lines[12],">"); eq(f.lines[13],nil); eq(f.deletions,#fixture-10); eq(f.replacements,11)
  eq(d.enabled,false); eq(d:filterPending(),false); eq(next(f.timers),nil); d:shutdown()
end)

test("skill weapons never invents missing weapons or natural attacks for a partial character skill list",function()
  for _,enabled in ipairs({true,false}) do
    local f,d=fakeSkills(enabled,{primary="number",direction="asc",secondary="none"})
    local possessed={groupedWeaponCases[1],groupedWeaponCases[6],groupedWeaponExcluded[1]}
    assert(d:requestFilter("weapons")); groupedWeaponFeed(f,1,possessed)
    local rows=d.pending; eq(#rows,4); eq(rows[4].remove,true)
    if enabled then eq(groupedWeaponIds(rows),"2,46")
    else
      eq(rows[2].display_text,groupedWeaponRaw(possessed[1]))
      eq(rows[3].display_text,groupedWeaponRaw(possessed[2]))
    end
    f:advance(0); eq(f.deletions,1); eq(f.replacements,3); eq(f.lines[4],">"); eq(f.lines[5],nil)
    eq(d.enabled,enabled); eq(next(f.timers),nil); d:shutdown()
  end
end)

test("skill weapons no matches and empty responses show one notice without creating skills or deleting combat",function()
  for _,enabled in ipairs({true,false}) do
    for _,empty in ipairs({true,false}) do
      local f,d=fakeSkills(enabled); assert(d:requestFilter(" WEAPONS "))
      f:feed(">skill weapons",0); f:feed("Skill Remain Level",1)
      if empty then f:feed(">",2)
      else
        f:feed(groupedWeaponRaw(groupedWeaponExcluded[1]),2)
        f:feed("An enemy attacks you!",3)
        f:feed(groupedWeaponRaw(groupedWeaponExcluded[4]),4); f:feed(">",5)
      end
      eq(d.pending[1].display_text,"No skills match: weapons")
      eq(#d.pending,empty and 1 or 3); f:advance(0)
      eq(f.lines[0],">skill weapons"); eq(f.lines[1],"No skills match: weapons")
      eq(f.replacements,1); eq(f.deletions,empty and 0 or 2)
      if empty then eq(f.lines[2],">"); eq(f.lines[3],nil)
      else eq(f.lines[2],"An enemy attacks you!"); eq(f.lines[3],">"); eq(f.lines[4],nil) end
      eq(d.enabled,enabled); eq(d:filterPending(),false); eq(next(f.timers),nil); d:shutdown()
    end
  end
end)

test("skill weapons deferred integration keeps interleaved combat and subsequent full game output intact",function()
  for _,enabled in ipairs({true,false}) do
    local f,d=fakeSkills(enabled,{primary="number",direction="asc",secondary="none"})
    assert(d:requestFilter("weapons")); f:feed(">skill weapons",0); f:feed("Skill Remain Level",1)
    f:feed(groupedWeaponRaw(groupedWeaponExcluded[1]),2); f:feed("The acolyte hits you!",3)
    f:feed(groupedWeaponRaw(groupedWeaponCases[6]),4); f:feed(groupedWeaponRaw(groupedWeaponCases[1]),5)
    f:feed("Combat continues.",6); f:feed(groupedWeaponRaw(groupedWeaponExcluded[8]),7)
    eq(#d.response.rows,4); f:feed(">",8); local pending=d.pending
    f:feed(">look",9); f:feed("A room description.",10); f:feed("[0] 10/10 hp, 8/8 ftg >",11)
    eq(f.replacements,0); eq(f.deletions,0)
    eq(f.lines[2],groupedWeaponRaw(groupedWeaponExcluded[1]))
    if enabled then eq(groupedWeaponIds(pending),"2,46")
    else
      eq(pending[2].display_text,groupedWeaponRaw(groupedWeaponCases[6]))
      eq(pending[3].display_text,groupedWeaponRaw(groupedWeaponCases[1]))
    end
    eq(pending[4].remove,true); eq(pending[5].remove,true); f:advance(0)
    eq(f.lines[0],">skill weapons"); eq(f.lines[3],"The acolyte hits you!")
    eq(f.lines[5],"Combat continues."); eq(f.lines[6],">"); eq(f.lines[7],">look")
    eq(f.lines[8],"A room description."); eq(f.lines[9],"[0] 10/10 hp, 8/8 ftg >")
    eq(f.lines[10],nil); eq(f.cursor,9); eq(f.column,3); eq(f.replacements,3); eq(f.deletions,2)
    eq(d:filterPending(),false); eq(next(f.timers),nil); d:shutdown()
  end
end)

test("skill weapons successive grouped singular prefix all and bare queries never retain a previous filter",function()
  for _,enabled in ipairs({true,false}) do
    local f,d=fakeSkills(enabled,{primary="number",direction="asc",secondary="none"})
    local fixture=groupedWeaponFixture()
    local fullOrder=enabled and {1,2,3,4,5,11,13,18,15,14,12,6,7,9,8,10,16,17} or
      {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18}
    local groupedOrder=enabled and {1,2,3,4,5,6,7,9,8,10} or {1,2,3,4,5,6,7,8,9,10}
    for _,case in ipairs({
      {query="weapons",order=groupedOrder},{query="weapon",order={14,17}},
      {query="c",order={7}},{query="all",order=fullOrder},{order=fullOrder},
    }) do
      local prior={}; for row,value in pairs(f.lines) do prior[row]=value end
      if case.query then assert(d:requestFilter(case.query)) else d:cancel() end
      local first=f.cursor+1; local deletions,replacements=f.deletions,f.replacements
      groupedWeaponFeed(f,first,fixture); f:advance(0)
      if enabled then assert(f.lines[first]:match("^Number%s+Skill%s+LVL%s+USES$"))
      else eq(f.lines[first],"Skill Remain Level") end
      for index,fixtureIndex in ipairs(case.order) do
        local skill=fixture[fixtureIndex]; local text=assert(f.lines[first+index])
        if enabled then
          eq(text:match("^%s*(%S+)%s"),tostring(skill.id or "?"))
          assert(text:find(Display.displayName(skill.name),1,true))
        else eq(text,groupedWeaponRaw(skill)) end
      end
      eq(f.deletions-deletions,#fixture-#case.order)
      eq(f.replacements-replacements,(enabled or case.query~=nil) and (#case.order+1) or 0)
      eq(f.lines[first+#case.order+1],">"); eq(f.lines[first+#case.order+2],nil)
      for row,value in pairs(prior) do eq(f.lines[row],value) end
      eq(d.enabled,enabled); eq(d:filterPending(),false); eq(next(f.timers),nil)
    end
    d:shutdown()
  end
end)

test("skill weapons honors independent chosen number name and uses orders without changing categories",function()
  for _,case in ipairs({
    {sort={primary="number",direction="asc",secondary="none"},ids="2,3,4,5,6,46,47,48,49,57"},
    {sort={primary="number",direction="desc",secondary="none"},ids="57,49,48,47,46,6,5,4,3,2"},
    {sort={primary="name",direction="asc",secondary="none"},ids="46,3,49,47,6,4,2,57,5,48"},
    {sort={primary="uses",direction="asc",secondary="none"},ids="47,57,48,49,5,3,4,2,46,6"},
  }) do
    local f,d=fakeSkills(true,case.sort); assert(d:requestFilter("weapons"))
    groupedWeaponFeed(f,1,groupedWeaponCases); eq(groupedWeaponIds(d.pending),case.ids)
    for index=2,#d.pending do
      local row=d.pending[index]; local id=tonumber(row.display_text:match("^%s*(%d+)%s"))
      local ready=id==47 or id==57; eq(row.category,ready and "ready" or "combat")
      eq(row.style_id,ready and "skill_ready" or "skill_combat"); eq(row.remove,nil)
    end
    f:advance(0); eq(f.deletions,0); eq(f.replacements,11); eq(f.lines[12],">")
    eq(d.sort.primary,case.sort.primary); eq(d.sort.direction,case.sort.direction); d:shutdown()
  end
end)

-- Combat/utility membership includes ready rows; readiness still controls styling.
-- This independent catalog pins every identifier and its skill category.
local semanticSkillCatalog={
  {"Brawling","combat"},{"Sharp Weapons","combat"},{"Blunt Weapons","combat"},
  {"Pole Weapons","combat"},{"Throw Weapons","combat"},{"Missile Weapons","combat"},
  {"Shield Parry","combat"},{"Quickdraw","combat"},{"Dodging","combat"},
  {"Focus Force","combat"},{"Berserk Attack","combat"},{"Parry Blows","combat"},
  {"Bargaining","utility"},{"Identify Gems/Minerals","utility"},{"Climbing","utility"},
  {"Detect Traps","utility"},{"Remove Traps","utility"},{"Skinning","utility"},
  {"Disguise","utility"},{"Pick Locks","utility"},{"Riding","utility"},
  {"Hiding","utility"},{"Swimming","utility"},{"Alchemy","utility"},
  {"Backstab","combat"},{"Martial Arts","combat"},{"Picking Pockets","utility"},
  {"Shoplifting","utility"},{"Stealth","utility"},{"Poisoning","combat"},
  {"Identify Magick","utility"},{"Identify Weapon Quality","utility"},{"Play Instruments","utility"},
  {"Armor Smithing","utility"},{"Weapon Smithing","utility"},{"Singing","utility"},
  {"Fletching","utility"},{"Tracking","utility"},{"Disarming","combat"},
  {"Psionics","combat"},{"Channeling","combat"},{"First Aid","combat"},
  {"Body Building","combat"},{"Turn Undead","combat"},{"Draining","combat"},
  {"Biting","combat"},{"Clawing","combat"},{"Webbing","combat"},
  {"Breath Weapon","combat"},{"Identify Armor Quality","utility"},{"Linguistics","utility"},
  {"Herbalism","utility"},{"Healing","combat"},{"Spellcasting","combat"},
  {"Conjuration","combat"},{"Delving","utility"},{"Stinging","combat"},
}
local semanticSkillRows={
  {name="Sharp Weapons",id=2,remain=400,level=4},
  {name="Weapon Smithing",id=35,remain=0,level=9999},
  {name="Swimming",id=23,remain=5,level=7},
  {name="Brawling",id=1,remain=0,level=9},
  {name="First Aid",id=42,remain=1000000000000,level=123},
  {name="Identify Weapon Quality",id=32,remain=42,level=2},
  {name="Channeling",id=41,remain=0,level=1},
  {name="Future Art",remain=10,level=3},
  {name="Riding",id=21,remain=0,level=12},
}
local semanticQueries={"combat","utility","train"}
local semanticNumberOrder={combat={4,1,7,5},utility={9,3,6,2,8},train={4,9,2,7}}
local semanticServerOrder={combat={1,4,5,7},utility={2,3,6,8,9},train={2,4,7,9}}
local function semanticFeed(f,first,skills,boundary,heading)
  f:feed(heading or "Skill Remain Level",first)
  for index,skill in ipairs(skills) do f:feed(groupedWeaponRaw(skill),first+index) end
  f:feed(boundary or ">",first+#skills+1)
end
local function assertSemanticOutput(f,first,order,enabled)
  if enabled then assert(f.lines[first]:match("^Number%s+Skill%s+LVL%s+USES$"))
  else eq(f.lines[first],"Skill Remain Level") end
  for index,fixtureIndex in ipairs(order) do
    local skill=semanticSkillRows[fixtureIndex]; local text=assert(f.lines[first+index])
    if enabled then
      eq(text:match("^%s*(%S+)%s"),tostring(skill.id or "?"))
      assert(text:find(Display.displayName(skill.name),1,true))
      eq(tonumber(text:match("(%d+)$")),skill.remain)
    else eq(text,groupedWeaponRaw(skill)) end
  end
end

test("skill semantic groups cover all 57 names including ready rows with independent readiness styling",function()
  eq(#semanticSkillCatalog,57); local counts={combat=0,utility=0}; local seen={}
  for id,entry in ipairs(semanticSkillCatalog) do
    local skillName,category=entry[1],entry[2]
    eq(Display.skillId(skillName),id); assert(not seen[skillName]); seen[skillName]=true
    counts[category]=counts[category]+1
    for _,remain in ipairs({0,1,17,1000000000000}) do
      eq(Display.combatCategory({name=skillName,remain=remain}),category)
      eq(Display.category({name=skillName,remain=remain}),remain==0 and "ready" or category)
      for _,query in ipairs(semanticQueries) do
        local expected=query=="train" and remain==0 or query==category
        eq(Display.matchesFilter(skillName,query,remain),expected)
        local messy="\27[35m ** "..skillName:upper():gsub(" "," \t ").."  \27[0m"
        eq(Display.matchesFilter(messy,"  "..query:upper().."  ",remain),expected)
      end
    end
  end
  eq(counts.combat,30); eq(counts.utility,27)
end)

test("skill semantic groups normalize exact keywords and retain literal near keyword prefixes",function()
  for _,case in ipairs({{query="combat",name="Sharp Weapons"},{query="utility",name="Swimming"},
    {query="train",name="Brawling"}}) do
    local remain=case.query=="train" and 0 or 1
    for _,query in ipairs({case.query,case.query:upper(),"  "..case.query:upper().."   "}) do
      eq(Display.normalizeFilter(query),case.query)
      eq(Display.matchesFilter(case.name,query,remain),true)
    end
    for _,suffix in ipairs({" skills","x",".*",";quit"}) do
      local query=case.query..suffix
      eq(Display.normalizeFilter(query),query)
      eq(Display.matchesFilter(case.name,query,remain),false)
      eq(Display.matchesFilter(query.." Lore",query,17),true)
    end
    local prefix=case.query:sub(1,3)
    eq(Display.matchesFilter(case.name,prefix,remain),false)
    eq(Display.matchesFilter(case.query.." Lore",prefix,0),true)
    eq(Display.matchesFilter(case.name,"\t"..case.query,remain),false)
  end
  eq(Display.matchesFilter("Training Lore","tra",17),true)
  eq(Display.matchesFilter("Training Lore","train",17),false)
  eq(Display.matchesFilter("Training Lore","train",0),true)
end)

test("skill semantic groups handle canonical labels support skills and unknown skills without inventing ids",function()
  for _,skillName in ipairs({"Sharps","Blunts","Poles","Throws","Missiles","First Aid","Shield Parry"}) do
    eq(Display.matchesFilter(skillName,"combat",1),true)
    eq(Display.matchesFilter(skillName,"utility",1),false)
    eq(Display.matchesFilter(skillName,"combat",0),true)
    eq(Display.matchesFilter(skillName,"utility",0),false)
    eq(Display.matchesFilter(skillName,"train",1),false)
    eq(Display.matchesFilter(skillName,"train",0),true)
  end
  for _,skillName in ipairs({"ID Weapon","ID Armor Quality","Weapon Smithing","Future Art",
    "Future Sharp Weapons","Quantum Élan 🐉"}) do
    eq(Display.matchesFilter(skillName,"utility",1),true)
    eq(Display.matchesFilter(skillName,"combat",1),false)
    eq(Display.matchesFilter(skillName,"utility",0),true)
    eq(Display.matchesFilter(skillName,"combat",0),false)
    eq(Display.matchesFilter(skillName,"train",0),true)
    eq(Display.matchesFilter(skillName,"train",1),false)
  end
  eq(Display.skillId("Future Art"),nil)
  eq(Display.matchesFilter("Future Art","train"),false)
end)

test("skill semantic remain argument leaves weapons ordinary prefixes and all behavior unchanged",function()
  for _,entry in ipairs(semanticSkillCatalog) do
    for _,query in ipairs({"weapons","weapon","c","ste","id","bite",""," ALL "}) do
      local expected=Display.matchesFilter(entry[1],query)
      eq(Display.matchesFilter(entry[1],query,0),expected)
      eq(Display.matchesFilter(entry[1],query,17),expected)
    end
  end
  eq(Display.matchesFilter("Clawing","weapons",0),true)
  eq(Display.matchesFilter("Weapon Smithing","weapons",0),false)
  eq(Display.matchesFilter("Channeling","c",0),true)
end)

test("skill semantic filtered output captures all rows before sorting and aligns only the matching rows",function()
  for _,case in ipairs({
    {query="combat",order={5,4,1,7},widths={6,10,3,13},category="combat"},
    {query="utility",order={2,9,3,8,6},widths={6,23,4,4},category="utility"},
    {query="train",order={2,9,4,7},widths={6,15,4,4},category="ready"},
  }) do
    local f,d=fakeSkills(); assert(d:requestFilter("  "..case.query:upper().."  "))
    f:feed(">skill "..case.query,0); f:feed("Skill Remain Level",1)
    for index,skill in ipairs(semanticSkillRows) do f:feed(groupedWeaponRaw(skill),index+1) end
    eq(#d.response.rows,#semanticSkillRows); eq(d.pending,nil)
    for index,skill in ipairs(semanticSkillRows) do
      eq(f.lines[index+1],groupedWeaponRaw(skill)); eq(d.response.rows[index].skill.remain,skill.remain)
    end
    eq(f.replacements,0); eq(f.deletions,0); f:feed(">",11)
    local rows=d.pending; eq(#rows,10)
    local widths=case.widths
    local format="%"..widths[1].."s  %-"..widths[2].."s  %"..widths[3].."s  %"..widths[4].."s"
    local heading=string.format(format,"Number","Skill","LVL","USES")
    eq(rows[1].display_text,heading); eq(rows[1].category,"neutral"); eq(rows[1].style_id,nil)
    for index,fixtureIndex in ipairs(case.order) do
      local skill=semanticSkillRows[fixtureIndex]; local row=rows[index+1]
      eq(row.display_text,string.format(format,tostring(skill.id or "?"),Display.displayName(skill.name),
        tostring(skill.level),tostring(skill.remain)))
      local category=skill.remain==0 and "ready" or case.category
      eq(#row.display_text,#heading); eq(row.category,category)
      eq(row.style_id,"skill_"..category); eq(row.remove,nil)
    end
    for index=2,#rows do
      eq(rows[index].line_number,index); eq(rows[index].source_line,groupedWeaponRaw(semanticSkillRows[index-1]))
      if index>#case.order+1 then eq(rows[index].remove,true); eq(rows[index].display_text,nil) end
    end
    eq(f.replacements,0); eq(f.deletions,0); f:advance(0)
    eq(f.lastRows,rows); eq(f.deletions,9-#case.order); eq(f.replacements,#case.order+1)
    eq(f.lines[0],">skill "..case.query); eq(f.lines[#case.order+2],">")
    eq(f.lines[#case.order+3],nil); eq(f.cursor,#case.order+2); eq(f.column,3)
    eq(d:filterPending(),false); eq(next(f.timers),nil); d:shutdown()
  end
end)

test("skill semantic filters honor chosen number name and uses sorting without changing membership",function()
  for _,case in ipairs({
    {query="combat",sort={primary="number",direction="asc",secondary="none"},ids="1,2,41,42"},
    {query="utility",sort={primary="number",direction="desc",secondary="none"},ids="35,32,23,21,?"},
    {query="train",sort={primary="name",direction="asc",secondary="none"},ids="1,41,21,35"},
    {query="utility",sort={primary="uses",direction="asc",secondary="none"},ids="21,35,23,?,32"},
  }) do
    local f,d=fakeSkills(true,case.sort); assert(d:requestFilter(case.query))
    semanticFeed(f,1,semanticSkillRows); eq(groupedWeaponIds(d.pending),case.ids)
    for index=2,#d.pending do
      if not d.pending[index].remove then
        local row=d.pending[index]
        local remain=tonumber(row.display_text:match("(%d+)$"))
        local category=remain==0 and "ready" or case.query
        eq(row.category,category); eq(row.style_id,"skill_"..category)
      end
    end
    f:advance(0); eq(d.sort.primary,case.sort.primary); eq(d.sort.direction,case.sort.direction)
    eq(d:filterPending(),false); eq(next(f.timers),nil); d:shutdown()
  end
end)

test("skill semantic formatting off preserves raw matched rows server order and the disabled toggle",function()
  for _,query in ipairs(semanticQueries) do
    local f,d=fakeSkills(false,{primary="number",direction="desc",secondary="none"})
    local heading="  Skill                     Remain Level  "
    assert(d:requestFilter(query)); semanticFeed(f,1,semanticSkillRows,">",heading)
    local rows=d.pending; local order=semanticServerOrder[query]
    eq(#rows,10); eq(rows[1].display_text,heading)
    for index,fixtureIndex in ipairs(order) do
      local row=rows[index+1]; eq(row.display_text,groupedWeaponRaw(semanticSkillRows[fixtureIndex]))
      eq(row.category,"neutral"); eq(row.style_id,nil); eq(row.remove,nil)
    end
    for index=#order+2,#rows do eq(rows[index].remove,true) end
    f:advance(0); eq(f.lines[1],heading)
    for index,fixtureIndex in ipairs(order) do eq(f.lines[index+1],groupedWeaponRaw(semanticSkillRows[fixtureIndex])) end
    eq(f.deletions,9-#order); eq(f.replacements,#order+1); eq(f.lines[#order+2],">")
    eq(f.lines[#order+3],nil); eq(d.enabled,false); eq(d:filterPending(),false)
    local previous=f.lastRows; semanticFeed(f,f.cursor+1,semanticSkillRows)
    eq(f.lastRows,previous); eq(d.pending,nil); eq(next(f.timers),nil); d:shutdown()
  end
end)

test("skill semantic groups retain zero use rows with default green coloring and train excludes positive uses",function()
  for _,query in ipairs(semanticQueries) do
    local f,d=fakeSkills(true,{primary="number",direction="asc",secondary="none"})
    local colors={}
    f.api.setFgColor=function(r,g,b) colors[f.cursor]=table.concat({r,g,b},",") end
    assert(d:requestFilter(query)); semanticFeed(f,1,semanticSkillRows)
    local order=semanticNumberOrder[query]
    f:advance(0); assertSemanticOutput(f,1,order,true)
    local ready=0
    for index,fixtureIndex in ipairs(order) do
      local skill=semanticSkillRows[fixtureIndex]; local row=f.lastRows[index+1]
      if skill.remain==0 then
        ready=ready+1; eq(row.category,"ready"); eq(row.style_id,"skill_ready")
        eq(colors[index+1],"80,210,120")
      else
        assert(query~="train"); eq(row.category,query); eq(row.style_id,"skill_"..query)
        assert(colors[index+1]~="80,210,120")
      end
    end
    eq(ready,query=="train" and 4 or 2)
    eq(f.deletions,9-#order); eq(f.replacements,#order+1)
    eq(d:filterPending(),false); eq(next(f.timers),nil); d:shutdown()
  end
end)

test("skill semantic groups keep membership when all style colors coincide or highlighting is disabled",function()
  for _,query in ipairs(semanticQueries) do
    for _,mode in ipairs({"custom","master-off","skills-off","style-off"}) do
      local f,d=fakeSkills(true,{primary="number",direction="asc",secondary="none"})
      local styles={}
      for _,id in ipairs({"skill_combat","skill_utility","skill_ready"}) do
        styles[id]={foreground="#AA11CC",enabled=mode~="style-off"}
      end
      f.settings={colorization={styles=styles,enabled=mode~="master-off",skills_enabled=mode~="skills-off"}}
      local colors={}; f.api.setFgColor=function(r,g,b) colors[#colors+1]=table.concat({r,g,b},",") end
      assert(d:requestFilter(query)); semanticFeed(f,1,semanticSkillRows)
      local rows=d.pending; local order=semanticNumberOrder[query]
      for index,fixtureIndex in ipairs(order) do
        local category=semanticSkillRows[fixtureIndex].remain==0 and "ready" or query
        eq(rows[index+1].category,category); eq(rows[index+1].style_id,"skill_"..category)
      end
      f:advance(0); assertSemanticOutput(f,1,order,true)
      local custom=0; for _,color in ipairs(colors) do if color=="170,17,204" then custom=custom+1 end end
      eq(custom,mode=="custom" and #order or 0)
      eq(d:filterPending(),false); eq(next(f.timers),nil); d:shutdown()
    end
  end
end)

test("skill semantic no matches and empty responses preserve combat prompts and a single normalized notice",function()
  local excluded={combat={semanticSkillRows[2],semanticSkillRows[3]},
    utility={semanticSkillRows[4],semanticSkillRows[1]},train={semanticSkillRows[1],semanticSkillRows[3]}}
  for _,query in ipairs(semanticQueries) do
    for _,enabled in ipairs({true,false}) do
      for _,empty in ipairs({true,false}) do
        local f,d=fakeSkills(enabled); assert(d:requestFilter("  "..query:upper().."  "))
        f:feed("Skill Remain Level",1)
        if empty then f:feed(">",2)
        else
          f:feed(groupedWeaponRaw(excluded[query][1]),2); f:feed("Combat continues.",3)
          f:feed(groupedWeaponRaw(excluded[query][2]),4); f:feed(">",5)
        end
        eq(d.pending[1].display_text,"No skills match: "..query); eq(#d.pending,empty and 1 or 3)
        for index=2,#d.pending do eq(d.pending[index].remove,true); eq(d.pending[index].display_text,nil) end
        f:advance(0); eq(f.lines[1],"No skills match: "..query)
        eq(f.replacements,1); eq(f.deletions,empty and 0 or 2)
        if empty then eq(f.lines[2],">"); eq(f.lines[3],nil)
        else eq(f.lines[2],"Combat continues."); eq(f.lines[3],">"); eq(f.lines[4],nil) end
        eq(d.enabled,enabled); eq(d:filterPending(),false); eq(next(f.timers),nil); d:shutdown()
      end
    end
  end
end)

test("skill semantic successive groups weapons prefixes all and bare requests retain independent tables",function()
  for _,enabled in ipairs({true,false}) do
    for _,boundary in ipairs({">",""}) do
      local f,d=fakeSkills(enabled,{primary="number",direction="asc",secondary="none"})
      local full=enabled and {4,1,9,3,6,2,7,5,8} or {1,2,3,4,5,6,7,8,9}
      for _,case in ipairs({
        {query="combat"},{query="utility"},{query="train"},{query="combat"},
        {query="weapons",order={1}},{query="c",order={7}},{query="all",order=full},{order=full},
      }) do
        local prior={}; for row,value in pairs(f.lines) do prior[row]=value end
        if case.query then assert(d:requestFilter(case.query)) else d:cancel() end
        local order=case.order or (enabled and semanticNumberOrder[case.query] or semanticServerOrder[case.query])
        local first=f.cursor+1; local deletions,replacements=f.deletions,f.replacements
        semanticFeed(f,first,semanticSkillRows,boundary); f:advance(0)
        assertSemanticOutput(f,first,order,enabled)
        eq(f.deletions-deletions,9-#order)
        eq(f.replacements-replacements,(enabled or case.query~=nil) and (#order+1) or 0)
        eq(f.lines[first+#order+1],boundary); eq(f.lines[first+#order+2],nil)
        for row,value in pairs(prior) do eq(f.lines[row],value) end
        eq(d.enabled,enabled); eq(d:filterPending(),false); eq(d.response,nil); eq(d.pending,nil)
        eq(next(f.timers),nil)
      end
      d:shutdown()
    end
  end
end)

test("skill semantic cancelled phase callbacks cannot change a later different group",function()
  for queryIndex,query in ipairs(semanticQueries) do
    local nextQuery=semanticQueries[queryIndex%#semanticQueries+1]
    for _,phase in ipairs({"intent","collecting","blank","deferred"}) do
      for _,action in ipairs({"cancel","disconnect","install","uninstall","menu","off"}) do
        local f,d=fakeSkills(); assert(d:requestFilter(query))
        if phase~="intent" then f:feed("Skill Remain Level",1); f:feed(groupedWeaponRaw(semanticSkillRows[1]),2) end
        if phase=="blank" then f:feed("",3) elseif phase=="deferred" then f:feed(">",3) end
        local oldTimer=d.timer; local late=f.timers[oldTimer].fn
        if action=="cancel" then d:cancel()
        elseif action=="disconnect" then f:emit("sysDisconnectionEvent")
        elseif action=="install" then f:emit("sysInstallPackage",nil,"DragonsGateHUD")
        elseif action=="uninstall" then f:emit("sysUninstallPackage",nil,"DragonsGateHUD")
        elseif action=="menu" then f:feed("Dragon's Gate Menu",4)
        else d:setEnabled(false) end
        eq(f.timers[oldTimer],nil); eq(d:filterPending(),false); eq(d.pending,nil); eq(d.response,nil)
        if not d.enabled then d:setEnabled(true) end
        assert(d:requestFilter(nextQuery)); semanticFeed(f,10,semanticSkillRows)
        local pending,timer,generation=d.pending,d.timer,d.generation
        late(); late(); eq(d.pending,pending); eq(d.timer,timer); eq(d.generation,generation)
        eq(f.replacements,0); eq(f.deletions,0); f:advance(0)
        local changed=f.replacements; late(); eq(f.replacements,changed)
        eq(changed,#semanticNumberOrder[nextQuery]+1); eq(f.deletions,9-#semanticNumberOrder[nextQuery])
        eq(d:filterPending(),false); eq(next(f.timers),nil); d:shutdown()
      end
    end
  end
end)

test("skill semantic expired requests and incomplete captures cannot narrow a later all response",function()
  for _,query in ipairs(semanticQueries) do
    for _,enabled in ipairs({true,false}) do
      for _,phase in ipairs({"intent","collecting"}) do
        local f,d=fakeSkills(enabled,{primary="number",direction="asc",secondary="none"})
        assert(d:requestFilter(query)); local intent=f.timers[d.timer].fn
        if phase=="collecting" then
          f:advance(Display.RESPONSE_TIMEOUT-.25); f:feed("Skill Remain Level",1)
          f:feed(groupedWeaponRaw(semanticSkillRows[1]),2)
          local timer=d.timer; intent(); eq(d.timer,timer); eq(d.response.filter_query,query)
        end
        local late=f.timers[d.timer].fn; f:advance(Display.RESPONSE_TIMEOUT)
        eq(d:filterPending(),false); eq(d.response,nil); eq(f.replacements,0); eq(f.deletions,0)
        assert(d:requestFilter("all")); semanticFeed(f,10,semanticSkillRows)
        local pending,timer=d.pending,d.timer; late(); eq(d.pending,pending); eq(d.timer,timer)
        f:advance(0); eq(#f.lastRows,10); eq(f.deletions,0)
        for _,row in ipairs(f.lastRows) do eq(row.remove,nil) end
        eq(f.lines[20],">"); eq(d.enabled,enabled); eq(next(f.timers),nil); d:shutdown()
      end
    end
  end
end)

test("skill semantic requests send only skill and keep the full sidebar collector snapshot in either observer order",function()
  local Main=require("main"); local Collector=require("command_collector"); local Parser=require("command_parser")
  for _,query in ipairs(semanticQueries) do
    for _,enabled in ipairs({true,false}) do
      for _,displayFirst in ipairs({true,false}) do
        for _,boundary in ipairs({">",""}) do
          local f,d=fakeSkills(enabled,{primary="number",direction="asc",secondary="none"})
          local updates=0; local collector=Collector.new(f,Parser,function(_,key) if key=="skills" then updates=updates+1 end end)
          local hud={started=true,adapter=f,skill_display=d,collector=collector}
          local sent={}
          function f:sendCommand(command) sent[#sent+1]=command; collector:onOutgoing(command); return true end
          local feed=f.feed
          function f:feed(text,row)
            if not displayFirst then collector:onLine(text) end
            feed(self,text,row)
            if displayFirst then collector:onLine(text) end
          end
          assert(Main.requestSkills(hud," "..query:upper().." "))
          eq(#sent,1); eq(sent[1],"skill"); eq(hud.skills_filter_sending,nil)
          semanticFeed(f,1,semanticSkillRows,boundary); f:advance(0)
          local snapshot=assert(collector.snapshot.skills); eq(#snapshot.items,9); eq(updates,1)
          local byName={}; for _,skill in ipairs(snapshot.items) do byName[skill.name]=skill end
          for _,skill in ipairs(semanticSkillRows) do
            local retained=assert(byName[skill.name]); eq(retained.remain,skill.remain); eq(retained.level,skill.level)
          end
          local order=enabled and semanticNumberOrder[query] or semanticServerOrder[query]
          assertSemanticOutput(f,1,order,enabled); eq(f.deletions,9-#order)
          eq(collector.snapshot.skills,snapshot); eq(collector.active,nil)
          f:advance(Display.RESPONSE_TIMEOUT+1); eq(#sent,1); eq(sent[1],"skill")
          eq(d.enabled,enabled); eq(d:filterPending(),false); eq(next(f.timers),nil)
          collector:shutdown(); d:shutdown()
        end
      end
    end
  end
end)
