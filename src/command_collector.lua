local Collector={}; Collector.__index=Collector
local SPECS={inventory={parser="parseInventory",snapshot="inventory"},stat={parser="parseStat",snapshot="stat"},info={parser="parseInfo",snapshot="info"},["info religion"]={parser="parseReligion",snapshot="religion"},["info magic"]={parser="parseRunes",snapshot="runes"},skill={parser="parseSkills",snapshot="skills"},time={parser="parseTime",snapshot="time"}}
-- TIME now returns a complete prompt on its own. Nudging it injects visible,
-- duplicate prompts on Dragon's Gate 4.0.9.4 and later.
local PROMPT_NUDGE={inventory=true,stat=true,info=true,["info religion"]=true,["info magic"]=true}
local RESPONSE_WAIT={inventory=2.5,stat=2,info=2.5,["info religion"]=2,["info magic"]=2.5,skill=3,time=2}
local RECOVERY_WAIT={inventory=2.5,stat=2,info=2.5,["info religion"]=2,["info magic"]=2.5,skill=3,time=2}
function Collector.new(adapter,parser,onChange,onRoundtime,onCharacterEntry,onCharacterExit)
  return setmetatable({adapter=adapter,parser=parser,onChange=onChange,onRoundtime=onRoundtime,onCharacterEntry=onCharacterEntry,onCharacterExit=onCharacterExit,snapshot={},sequence={"inventory","stat","info","info religion","info magic","skill","time"},runtime={triggers={},events={}},started=false,refreshed=false,prompt_nudge_delay=.15,drain_delay=.5},Collector)
end
function Collector:cancelActive()
  self:cancelSkillBoundary()
  if self.timeout then self.adapter:cancelTimer(self.timeout); self.timeout=nil end
  if self.prompt_nudge then self.adapter:cancelTimer(self.prompt_nudge); self.prompt_nudge=nil end
  self.active=nil; self.sequence_index=nil; self.retry_startup=false
end
function Collector:cancelSkillBoundary()
  if self.skill_boundary then self.adapter:cancelTimer(self.skill_boundary); self.skill_boundary=nil end
end
function Collector:queueSkillBoundary(active)
  if self.skill_boundary then return end
  local ok,result=pcall(self.parser.parseSkills,active.lines,true)
  if not ok or not result then return end
  -- The server terminates SKILL with blank lines even without a prompt. Wait
  -- only for this output burst to finish, not for another command/Enter.
  local timer
  timer=self.adapter:schedule(0,function()
    if self.skill_boundary~=timer or self.active~=active then return end
    self.skill_boundary=nil; self:finish(active.lines,true)
  end)
  self.skill_boundary=timer
end
function Collector:schedulePromptNudge(command)
  if not PROMPT_NUDGE[command] then return end
  self.prompt_nudge=self.adapter:schedule(self.prompt_nudge_delay,function()
    self.prompt_nudge=nil
    if self.active and self.active.command==command then self.adapter:sendCommand("") end
  end)
end
function Collector:scheduleTimeout(active,delay,fn)
  self.timeout=self.adapter:schedule(delay,function()
    self.timeout=nil
    if self.active==active then fn() end
  end)
end
function Collector:startRecovery(active)
  active.timeout_stage="recovery"
  -- Keep the same capture active: a delayed response must never become input for
  -- the following command. A second blank prompt request is safe and cheap.
  if PROMPT_NUDGE[active.command] then self.adapter:sendCommand("") end
  self:scheduleTimeout(active,RECOVERY_WAIT[active.command] or 2.5,function() self:startDrain(active) end)
end
function Collector:startDrain(active)
  active.timeout_stage="drain"
  self:scheduleTimeout(active,self.drain_delay,function() self:finish(nil) end)
end
function Collector:begin(command,startup)
  if self.active then return false end
  self.active={command=command,lines={},startup=startup==true,timeout_stage="initial"}
  local active=self.active
  self:scheduleTimeout(active,RESPONSE_WAIT[command] or 2.5,function() self:startRecovery(active) end)
  if startup then self.sending_startup_command=command; self.adapter:sendCommand(command); self.sending_startup_command=nil end
  self:schedulePromptNudge(command)
  return true
end
function Collector:refresh()
  if self.active or self.refreshed then return false end
  self.refreshed=true; self.sequence_index=1
  return self:begin(self.sequence[1],true)
end
function Collector:forceRefresh()
  if self.active then return false end
  self.refreshed=false
  return self:refresh()
end
function Collector:restartRefresh()
  self:cancelActive()
  self.refreshed=false
  return self:refresh()
end
function Collector:mergeStat(parsed)
  local stat=self.snapshot.stat or {}; self.snapshot.stat=stat; local delta={}
  for key,value in pairs(parsed) do
    local previous=stat[key]; local changed=previous~=value
    if key=="move" and type(value)=="table" and type(previous)=="table" then
      changed=tonumber(previous.current)~=tonumber(value.current) or tonumber(previous.maximum)~=tonumber(value.maximum)
    end
    if changed then stat[key]=value; delta[key]=value end
  end
  return stat,delta
end
function Collector:finish(lines,tableBoundary)
  local active=self.active; if not active then return end
  if self.timeout then self.adapter:cancelTimer(self.timeout); self.timeout=nil end
  if self.prompt_nudge then self.adapter:cancelTimer(self.prompt_nudge); self.prompt_nudge=nil end
  self:cancelSkillBoundary()
  self.active=nil
  if lines then
    local spec=SPECS[active.command]; local fn=spec and self.parser[spec.parser]
    local ok,result=pcall(fn,lines,active.command=="skill" and tableBoundary==true)
    if ok and result then
      local parsed=result
      if spec.snapshot=="stat" then result=self:mergeStat(result)
      elseif spec.snapshot=="info" and type(self.snapshot.info)=="table" then
        local previous=self.snapshot.info
        for key,value in pairs(result) do
          if key=="attributes" and type(value)=="table" and next(value)~=nil then
            -- A game-format change must not leave retired characteristic names
            -- beside the current ones in the retained INFO snapshot.
            previous[key]=value
          elseif type(value)=="table" and type(previous[key])=="table" then
            for child,childValue in pairs(value) do previous[key][child]=childValue end
          else previous[key]=value end
        end
        result=previous
      end
      self.snapshot[spec.snapshot]=result; self.onChange(self.snapshot,spec.snapshot,parsed)
    end
  end
  if self.retry_startup and self.sequence_index then
    self.retry_startup=false; self:begin(self.sequence[self.sequence_index],true)
  elseif active.startup or self.sequence_index then
    self.sequence_index=(self.sequence_index or 1)+1; local command=self.sequence[self.sequence_index]
    if command then self:begin(command,true) else self.sequence_index=nil end
  end
end
function Collector:onLine(value)
  value=tostring(value or "")
  local plain=value:gsub("\27%[[0-?]*[ -/]*[@-~]",""):match("^%s*(.-)%s*$")
  if plain=="Dragon's Gate Menu" or plain:find("Dragon's Gate Character Creator",1,true) then
    self:cancelActive(); self.refreshed=false; self.active_character=nil
    if self.onCharacterExit then self.onCharacterExit() end
    return
  end
  if self.onRoundtime then
    for marker in plain:gmatch("%[(%d+%.?%d*)%s+sec%.%s+delay%]") do
      local delay=tonumber(marker); if delay then self.onRoundtime(delay,{source="text"}) end
    end
  end
  local character=value:match("^Welcome to Dragon's Gate, (.+)!%s*$")
  if character then
    if self.active_character==character then return end
    self:cancelActive(); self.refreshed=false; self.active_character=character; self.snapshot={}; self.onChange(self.snapshot,"reset")
    if self.onCharacterEntry then self.onCharacterEntry(character) else self:refresh() end
    return
  end
  local stance=self.parser.parseStance and self.parser.parseStance(value)
  if stance then
    local _,delta=self:mergeStat({stance=stance})
    if next(delta) then self.onChange(self.snapshot,"stat",delta) end
  end
  if not self.active then return end
  -- Lines remain owned by the timed-out command throughout recovery/drain. A
  -- complete delayed response can still succeed before the bounded drain ends.
  if #self.active.lines==1 and self.parser.isPrompt(self.active.lines[1]) and not self.parser.isPrompt(value) then self.active.lines={} end
  self.active.lines[#self.active.lines+1]=value
  if self.active.command=="skill" then
    if plain=="" then self:queueSkillBoundary(self.active)
    elseif plain:match("^%s*(.-)%s+(%d+)%s+(%d+)%s*$")
        or plain:match("^Skill%s+Remain%s+Level$") then
      -- A later row in the same burst makes an earlier blank non-terminal.
      self:cancelSkillBoundary()
    end
  end
  if self.active.command=="stat" and self.parser.parseStatCombat then
    local ok,parsed=pcall(self.parser.parseStatCombat,self.active.lines)
    -- Publish only changed, recognized combat fields before a prompt or interruption.
    -- Completion callbacks still fire normally; equipment stays inside completed STAT.
    if ok and parsed then
      local _,delta=self:mergeStat(parsed)
      if next(delta) then self.onChange(self.snapshot,"stat",delta) end
    end
  end
  if self.parser.isComplete(self.active.command,self.active.lines) then self:finish(self.active.lines)
  elseif self.active.command=="time" and #self.active.lines>1 and self.parser.isPrompt(value) then
    -- A natural terminal prompt ends TIME even if a future server format cannot
    -- be parsed. Never stall startup or manufacture another prompt with Enter.
    self:finish(nil)
  end
end
function Collector:onOutgoing(command)
  command=tostring(command or ""):match("^%s*(.-)%s*$"):lower()
  if command=="inv" then command="inventory" end
  if command=="info mag" then command="info magic" end
  if not SPECS[command] or self.sending_startup_command==command then return end
  if self.active then
    if self.active.command=="skill" and self.skill_boundary then
      -- Another tracked command can start before the zero-delay boundary fires.
      -- Retain its already-complete table before transferring capture ownership;
      -- do not send or advance startup commands from this interruption path.
      local ok,result=pcall(self.parser.parseSkills,self.active.lines,true)
      if ok and result then self.snapshot.skills=result; self.onChange(self.snapshot,"skills",result) end
    end
    if self.active.startup then self.retry_startup=true end
    if self.timeout then self.adapter:cancelTimer(self.timeout); self.timeout=nil end
    if self.prompt_nudge then self.adapter:cancelTimer(self.prompt_nudge); self.prompt_nudge=nil end
    self:cancelSkillBoundary()
    self.active=nil
  end
  self:begin(command,false)
end
function Collector:start()
  if self.started then return true end
  self.runtime.triggers[1]=self.adapter:addLineTrigger(function(value) self:onLine(value) end)
  self.runtime.events[1]=self.adapter:addEvent("sysDataSendRequest",function(_,command) self:onOutgoing(command) end)
  self.runtime.events[2]=self.adapter:addEvent("sysDisconnectionEvent",function() self:cancelActive(); self.refreshed=false; self.active_character=nil end)
  self.started=true; return true
end
function Collector:shutdown()
  self:cancelActive()
  for _,id in ipairs(self.runtime.triggers) do self.adapter:killTrigger(id) end
  for _,id in ipairs(self.runtime.events) do self.adapter:killEvent(id) end
  self.runtime={triggers={},events={}}; self.refreshed=false; self.active_character=nil; self.started=false; return true
end
return Collector
