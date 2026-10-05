-- Printed delays may request one reconciliation; remaining-time snapshots never do.
local Check = {}; Check.__index = Check
local DEBOUNCE, MIN_INTERVAL, REPLY_TIMEOUT = .25, 3, 4
local MAX_PENDING, MAX_LINE, MAX_REMAINING = 32, 2048, 86400

local function finite(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
end

local function response(raw)
  if type(raw) ~= "string" or #raw > MAX_LINE then return nil end
  local plain = raw:gsub("\27%[[0-?]*[ -/]*[@-~]", ""):gsub("\r+$", "")
  plain = plain:match("^[ \t]*(.-)[ \t]*$")
  if plain:find("[%z\1-\31\127]") then return nil end
  local content, prompts = plain:gsub("^%[%d+%] +%d+/%d+ +hp, +%d+/%d+ +ftg *> *", "", 1)
  if prompts == 0 then content, prompts = plain:gsub("^> *", "", 1) end
  local digits = content:match("^You have (%d+) second%(s%) remaining!$")
    or content:match("^You have (%d+) seconds? remaining!$")
  local value = digits and tonumber(digits)
  if not finite(value) or value < 0 or value > MAX_REMAINING or value % 1 ~= 0 then return nil end
  -- A native whole-line gag must never erase a prompt sharing the response.
  return value, prompts == 0
end

function Check.new(adapter, onRemaining, canSend)
  return setmetatable({
    adapter = adapter or {}, onRemaining = onRemaining, canSend = canSend,
    pending = {}, generation = 0, paused = false, suspended = false, stopped = false, ambiguous = false,
  }, Check)
end

function Check:_cancelHandle(id)
  if type(self.adapter.cancelTimer) ~= "function" then return false end
  local called, result, err = pcall(self.adapter.cancelTimer, self.adapter, id)
  return called and result ~= false and not (result == nil and err ~= nil)
end

function Check:_cancel(slot)
  local ticket = self[slot]
  self[slot] = nil
  if not ticket then return true end
  ticket.active = false
  return ticket.id == nil or self:_cancelHandle(ticket.id)
end

function Check:_clear()
  -- Invalidate first, including callbacks from timers whose cancellation fails.
  self.generation = self.generation + 1
  self.queued_at = nil; self.sending = nil; self.pending = {}; self.ambiguous = false
  local probeOK = self:_cancel("probe_timer")
  local replyOK = self:_cancel("reply_timer")
  return probeOK and replyOK
end

function Check:_fail()
  self.paused = true; self.suspended = true
  self:_clear()
  return false
end

function Check:_clock()
  local fn = self.adapter.chatSoundTime
  if type(fn) ~= "function" then fn = self.adapter.epoch end
  if type(fn) ~= "function" then self:_fail(); return nil end
  local called, value = pcall(fn, self.adapter)
  if not called or not finite(value) or value < 0 then self:_fail(); return nil end
  value = math.max(value, self.last_now or value)
  self.last_now = value
  return value
end

function Check:_allowed()
  if type(self.canSend) ~= "function" then return false end
  local called, allowed = pcall(self.canSend)
  if not called then return self:_fail() end
  return allowed == true
end

function Check:_schedule(slot, seconds, fn)
  if type(self.adapter.schedule) ~= "function" or type(self.adapter.cancelTimer) ~= "function" then
    return self:_fail()
  end
  local ticket = {generation = self.generation, active = true}
  self[slot] = ticket
  local called, id = pcall(self.adapter.schedule, self.adapter, seconds, function()
    if not ticket.active or self[slot] ~= ticket or ticket.generation ~= self.generation
      or self.stopped or (self.paused and slot == "probe_timer") then return end
    -- A scheduler must defer callbacks; a synchronous callback cannot establish ownership.
    if ticket.id == nil then self:_fail(); return end
    self[slot] = nil; ticket.active = false
    if not pcall(fn) then self:_fail() end
  end)
  if not called or id == nil or id == false then return self:_fail() end
  ticket.id = id
  if not ticket.active or self[slot] ~= ticket or ticket.generation ~= self.generation then
    self:_cancelHandle(id)
    return self:_fail()
  end
  return true
end

function Check:_hasManual()
  for _, request in ipairs(self.pending) do
    if request.kind == "manual" then return true end
  end
  return false
end

function Check:_markAmbiguous()
  for _, request in ipairs(self.pending) do
    if request.kind == "auto" then request.ambiguous = true; self.ambiguous = true end
  end
  if self.sending then self.sending.ambiguous = true; self.ambiguous = true end
end

function Check:_expire(now)
  if self.pending[1] and now >= self.pending[1].deadline then self:_fail(); return true end
  return false
end

function Check:_armReply()
  if self.reply_timer or not self.pending[1] then return true end
  local request = self.pending[1]
  local now = self:_clock()
  if not now or self:_expire(now) then return false end
  return self:_schedule("reply_timer", request.deadline - now, function()
    if self.pending[1] == request then self:_fail() end
  end)
end

function Check:_queueProbe()
  if self.stopped or self.paused or self.queued_at == nil then return false end
  if self.probe_timer or #self.pending > 0 then return true end
  local now = self:_clock()
  if not now then return false end
  local due = math.max(self.queued_at, self.last_send and self.last_send + MIN_INTERVAL or now)
  return self:_schedule("probe_timer", math.max(0, due - now), function() self:_sendProbe() end)
end

function Check:_sendProbe()
  if self.stopped or self.paused or self.queued_at == nil or #self.pending > 0 then return false end
  if type(self.adapter.sendRoundtimeCheck) ~= "function" or not self:_allowed() then
    self.queued_at = nil
    return false
  end
  local now = self:_clock()
  if not now then return false end
  if self.last_send and now < self.last_send + MIN_INTERVAL then return self:_queueProbe() end
  local generation = self.generation
  local request = {kind = "auto", proven = false, ambiguous = false, deadline = now + REPLY_TIMEOUT}
  self.queued_at = nil; self.pending[1] = request
  -- Install the deadline before sending so a missing timer cannot leave an owned request.
  if not self:_armReply() then return false end
  if generation ~= self.generation or self.paused then return false end
  if self.pending[1] ~= request or #self.pending ~= 1 or request.ambiguous then return self:_fail() end
  self.sending = request; self.last_send = now
  local called, result, err = pcall(self.adapter.sendRoundtimeCheck, self.adapter)
  if self.sending == request then self.sending = nil end
  if generation ~= self.generation or self.stopped or self.paused then return false end
  -- Mudlet send can return nil on success. Only its synchronous outgoing event
  -- proves this request belongs to us; an eventual/asynchronous event cannot.
  if not called or result == false or (result == nil and err ~= nil) or not request.proven then
    return self:_fail()
  end
  return true
end

function Check:onDelay(value)
  if self.stopped or self.paused or (type(value) ~= "number" and type(value) ~= "string") then return false end
  if type(value) == "string" and #value > 64 then return false end
  value = tonumber(value)
  if not finite(value) or value <= 0 or value > MAX_REMAINING then return false end
  if type(self.adapter.sendRoundtimeCheck) ~= "function" or not self:_allowed() then return false end
  local now = self:_clock()
  if not now or self:_expire(now) or self:_hasManual() then return false end
  self.queued_at = now + DEBOUNCE
  if not self:_cancel("probe_timer") then return self:_fail() end
  return self:_queueProbe()
end

function Check:onOutgoing(command)
  if type(command) ~= "string" or #command > MAX_LINE or self.stopped then return false end
  if command:match("^%s*(.-)%s*$"):lower() ~= "delay" then return false end
  local now = self:_clock()
  if not now then return false end
  self:_expire(now)
  local owned = self.sending
  if owned and not owned.proven and self.pending[1] == owned then
    owned.proven = true
    return true
  end
  -- An additional delay, even inside the send call, is manual/ambiguous.
  self:_markAmbiguous()
  self.queued_at = nil
  if not self:_cancel("probe_timer") then self:_fail(); return false end
  if #self.pending >= MAX_PENDING then self:_fail(); return false end
  self.pending[#self.pending + 1] = {kind = "manual", deadline = now + REPLY_TIMEOUT}
  self:_armReply()
  return false
end

-- Returns remaining, hidden; unrecognized output returns nil, false.
function Check:onLine(raw)
  if self.stopped then return nil, false end
  local remaining, isolated = response(raw)
  if remaining == nil then return nil, false end
  if self.handling then self:_fail(); return remaining, false end
  if self.pending[1] then
    local now = self:_clock()
    if now then self:_expire(now) end
  end
  local generation, request = self.generation, self.pending[1]
  -- Outgoing observation is required even for visible/manual updates. Old
  -- replies after a timeout or character reset have no current attribution.
  if not request or (request.kind == "auto" and not request.proven) then return remaining, false end
  self.handling = true
  local called, result, err = pcall(self.onRemaining, remaining)
  self.handling = false
  if not called or result == false or (result == nil and err ~= nil) then
    self:_fail()
    return remaining, false
  end
  if generation ~= self.generation or self.stopped then return remaining, false end
  if not request or self.pending[1] ~= request then return remaining, false end
  table.remove(self.pending, 1)
  if not self:_cancel("reply_timer") then self:_fail(); return remaining, false end
  if #self.pending == 0 then self.ambiguous = false end
  if not self:_armReply() then return remaining, false end
  local hidden = false
  if not self.paused and isolated and request.kind == "auto" and request.proven and not request.ambiguous
    and not self.ambiguous and not self.sending then
    if type(self.adapter.hideRoundtimeCheckLine) ~= "function" then
      self:_fail()
      return remaining, false
    end
    local hideCalled, hideResult = pcall(self.adapter.hideRoundtimeCheckLine, self.adapter, raw)
    if not hideCalled or hideResult ~= true then
      self:_fail()
      return remaining, false
    end
    hidden = true
  end
  self:_queueProbe()
  return remaining, hidden
end

function Check:reset()
  if #self.pending > 0 or self.sending then self.suspended = true end
  local cleared = self:_clear()
  if not cleared then self.suspended = true end
  self.last_send = nil; self.last_now = nil
  self.paused = self.stopped or self.suspended
  return cleared
end

function Check:shutdown()
  self.stopped = true; self.paused = true
  return self:_clear()
end

return Check
