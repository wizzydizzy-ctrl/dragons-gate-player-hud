local Roundtime={}; Roundtime.__index=Roundtime
local CORRELATION_WINDOW=.5
local function duration(value)
  value=tonumber(value)
  if not value or value~=value or value==math.huge or value==-math.huge or value<0 or value>86400 then return nil end
  return value
end
function Roundtime.new(clock)
  return setmetatable({clock=clock or os.time,deadline=0,now_seen=0},Roundtime)
end
function Roundtime:now(tick)
  local value=tonumber(self.clock())
  if not value or value~=value or value==math.huge or value==-math.huge then value=self.now_seen end
  value=math.max(self.now_seen,value)
  -- Coarse clocks (and adapters without a fractional clock) still advance on
  -- the owned one-second timer; delayed timers use actual elapsed time.
  if self.tick_seen==nil then self.tick_seen=value end
  if tick then
    if value<=self.tick_seen then value=self.tick_seen+1 end
    self.tick_seen=value
  end
  self.now_seen=value
  return value
end
function Roundtime:remaining(now)
  return math.max(0,self.deadline-(now or self:now()))
end
function Roundtime:display() return math.ceil(self:remaining()) end
function Roundtime:reset()
  self.deadline=0; self.last_gmcp=nil; self.text_at=nil; self.credit=nil; self.credit_at=nil; self.tick_seen=nil
end
function Roundtime:handoff()
  return {schema=1,deadline=self.deadline,last_gmcp=self.last_gmcp,
    credit=self.credit,credit_at=self.credit_at,text_at=self.text_at}
end
function Roundtime:restore(snapshot)
  if type(snapshot)~="table" or snapshot.schema~=1 then return false end
  local now=self:now(); local deadline=tonumber(snapshot.deadline)
  if not deadline or deadline~=deadline or deadline<0 or deadline>now+86400 then return false end
  if snapshot.last_gmcp~=nil and not duration(snapshot.last_gmcp) then return false end
  if snapshot.credit~=nil and not duration(snapshot.credit) then return false end
  for _,key in ipairs({"credit_at","text_at"}) do
    local value=snapshot[key]
    if value~=nil and (type(value)~="number" or value~=value or value<0 or value>now+CORRELATION_WINDOW) then return false end
  end
  if (tonumber(snapshot.credit) or 0)>0 and snapshot.credit_at==nil then return false end
  self:reset(); self.deadline=deadline; self.last_gmcp=duration(snapshot.last_gmcp); self.tick_seen=now
  self.credit=duration(snapshot.credit); self.credit_at=snapshot.credit_at; self.text_at=snapshot.text_at
  return true
end
function Roundtime:text(value)
  value=duration(value); if not value or value==0 then return self:display() end
  local now=self:now(); local credit=0
  if self.credit_at and now-self.credit_at<=CORRELATION_WINDOW then credit=math.min(value,self.credit or 0) end
  self.credit=math.max(0,(self.credit or 0)-credit)
  self.deadline=math.max(now,self.deadline)+value-credit; self.text_at=now
  return math.ceil(self:remaining(now))
end
function Roundtime:gmcp(value)
  value=duration(value); if not value then return self:display() end
  local now=self:now()
  -- Vitals can repeat an unchanged, cached roundtime on unrelated HP/carry
  -- updates. It is a snapshot, not another delay, even after local expiry.
  if value==self.last_gmcp then return math.ceil(self:remaining(now)) end
  self.last_gmcp=value
  local previous=math.max(now,self.deadline)
  local recentText=self.text_at and now-self.text_at<=CORRELATION_WINDOW
  if recentText then
    -- A matching snapshot arriving just before/after printed delays must not
    -- double-charge them or erase an additional fumble delay already printed.
    self.deadline=math.max(previous,now+value)
  else self.deadline=now+value end
  local unused=self.credit_at and now-self.credit_at<=CORRELATION_WINDOW and (self.credit or 0) or 0
  self.credit=recentText and unused+math.max(0,self.deadline-previous) or value; self.credit_at=now
  return math.ceil(self:remaining(now))
end
function Roundtime:tick()
  return math.ceil(self:remaining(self:now(true)))
end
return Roundtime
