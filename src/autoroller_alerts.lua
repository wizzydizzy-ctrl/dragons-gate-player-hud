-- Completion reminders never send commands or change the held creator result.
local Audio=require("autoroller_audio")
local Alerts={}; Alerts.__index=Alerts
local INTERVAL,MAX_SECONDS=10,300
local function finite(value) return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge end
local function invoke(object,name,...)
  if type(object)~="table" or type(object[name])~="function" then return nil,"Alert control is unavailable." end
  local called,value,err,extra=pcall(object[name],object,...)
  if not called then return nil,"Alert control could not complete." end
  return value,err,extra
end
function Alerts.new(adapter,audio,view,getSettings)
  return setmetatable({adapter=adapter or {},audio=audio,view=view,getSettings=getSettings,generation=0},Alerts)
end
function Alerts:_settings()
  local called,value=pcall(self.getSettings or function() return nil end)
  return Audio.validate(called and value or nil) or Audio.defaults()
end
function Alerts:_clock()
  local value=invoke(self.adapter,"chatSoundTime")
  if not finite(value) then value=invoke(self.adapter,"epoch") end
  if not finite(value) then return nil end
  self.last_time=math.max(value,self.last_time or value); return self.last_time
end
function Alerts:_cancel()
  self.generation=self.generation+1
  for _,slot in ipairs({"timer","expiry"}) do
    local ticket=self[slot]; self[slot]=nil
    if ticket then ticket.active=false; if ticket.id then invoke(self.adapter,"cancelTimer",ticket.id) end end
  end
end
function Alerts:_warn(message)
  if not message or self.last_warning==message then return end
  self.last_warning=message; invoke(self.adapter,"reportRoller",message)
end
function Alerts:_play(config,preview)
  local ok,warning,duration=invoke(self.audio,"play",config,preview==true)
  if not ok then self:_warn(warning or "Could not play the autoroller sound. Use Preview and check Mudlet's media volume.")
  elseif warning then self:_warn(warning) end
  return ok,warning,finite(duration) and math.max(0,math.min(60,duration)) or 0
end
function Alerts:_stopPreview()
  local ok,err=invoke(self.audio,"stop",true)
  -- A failed stop may leave audio playing. Retain ownership for later cleanup.
  if ok then self.preview_active=false end
  return ok,err
end
function Alerts:_schedule(slot,seconds,callback)
  local generation=self.generation
  local ticket={active=true}; self[slot]=ticket
  local id=invoke(self.adapter,"schedule",seconds,function()
    if not ticket.active or generation~=self.generation or self.stopped then return end
    ticket.active=false; self[slot]=nil; callback()
  end)
  if not id then ticket.active=false; self[slot]=nil; return false end
  ticket.id=id; return true
end
function Alerts:_arm(duration)
  local config=self:_settings()
  if self.stopped or not self.event or self.acknowledged or not config.enabled or not config.repeat_enabled then return end
  local now=self:_clock()
  if not now or not self.started_at then return end
  local remaining=MAX_SECONDS-(now-self.started_at)
  if remaining<=0 then self:silence(false); return end
  if not self.expiry then self:_schedule("expiry",remaining,function() self:silence(false) end) end
  local delay=math.max(INTERVAL,(duration or 0)+.1)
  if delay>=remaining then return end
  self:_schedule("timer",delay,function()
    local current=self:_settings(); local clock=self:_clock()
    if self.acknowledged or not self.event or not current.enabled or not current.repeat_enabled then return end
    if not clock or clock-self.started_at>=MAX_SECONDS then self:silence(false); return end
    local ok,_,length=self:_play(current,false)
    if ok then self:_arm(length) else self:silence(false) end
  end)
end
function Alerts:result(event)
  if self.stopped or type(event)~="table" or event.kind~="target_hit" then return false end
  if self.event then return false end -- A held result has one notice, including prompt redraws.
  self:_cancel(); self:_stopPreview()
  self.event=event; self.acknowledged=false; self.last_warning=nil; self.started_at=self:_clock()
  invoke(self.view,"showRollerResultAlert",event)
  local config=self:_settings()
  if config.enabled then local ok,_,duration=self:_play(config,false); if ok then self:_arm(duration) end end
  return true
end
function Alerts:silence(hide)
  self.acknowledged=true; self:_cancel(); invoke(self.audio,"stop",false); self:_stopPreview()
  if hide~=false then invoke(self.view,"hideRollerResultAlert") end
  return true
end
function Alerts:clear()
  if not self.event and not self.preview_active and not self.timer and not self.expiry then return true end
  self:silence(); self.event=nil; self.started_at=nil; self.last_warning=nil; return true
end
function Alerts:settingsChanged()
  self:_cancel(); invoke(self.audio,"stop",false)
  if not self.acknowledged then self:_arm(0) end
  return true
end
function Alerts:action(action,settings)
  if self.stopped then return nil,"Autoroller alerts are unavailable." end
  if action=="silence" then return self:silence() end
  if action=="stop_preview" then return self:_stopPreview() end
  if action=="choose" then return invoke(self.audio,"chooseCustom") end
  if action=="preview" then
    local config,err=Audio.validate(settings); if not config then return nil,err end
    -- Preview cannot overlap a live reminder; it acknowledges audio only, not the roll.
    if self.event then self:silence(false) end
    local previous=self.preview_active
    local ok,warning,duration=self:_play(config,true); self.preview_active=ok==true or previous==true
    return ok,warning,duration
  end
  return nil,"Unknown autoroller alert control."
end
function Alerts:shutdown() self:clear(); self.stopped=true; return true end
return Alerts
