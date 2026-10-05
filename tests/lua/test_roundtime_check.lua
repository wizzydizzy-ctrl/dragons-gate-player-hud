local Check = require("roundtime_check")

local function reply(value) return "You have " .. tostring(value) .. " second(s) remaining!" end

local function fake()
  local f = {now = 100, next_id = 0, timers = {}, history = {}, sends = {}, hidden = {},
    readings = {}, observed = {}, schedule_calls = 0, cancel_calls = 0, allowed = true}
  function f:chatSoundTime() return self.now end
  function f:epoch() return self.now end
  function f:schedule(seconds, fn)
    self.schedule_calls = self.schedule_calls + 1
    if self.schedule_failure and (not self.schedule_fail_at or self.schedule_calls == self.schedule_fail_at) then
      if self.schedule_failure == "throw" then error("schedule failed") end
      if self.schedule_failure == "false" then return false end
      return nil, "schedule failed"
    end
    self.next_id = self.next_id + 1
    local timer = {at = self.now + seconds, fn = fn}
    self.timers[self.next_id] = timer; self.history[self.next_id] = timer
    return self.next_id
  end
  function f:cancelTimer(id)
    self.cancel_calls = self.cancel_calls + 1
    if self.cancel_failure == "throw" then error("cancel failed") end
    if self.cancel_failure == "false" then return false end
    if self.cancel_failure == "nil-error" then return nil, "cancel failed" end
    self.timers[id] = nil
    return true
  end
  function f:sendRoundtimeCheck()
    self.sends[#self.sends + 1] = self.now
    if self.send_mode == "wrong-event" then
      self.observed[#self.observed + 1] = self.check:onOutgoing("look")
    elseif self.send_mode == "async-event" then
      self:schedule(.1, function() self.observed[#self.observed + 1] = self.check:onOutgoing("delay") end)
    elseif self.send_mode ~= "no-event" then
      self.observed[#self.observed + 1] = self.check:onOutgoing("delay")
    end
    if self.during_send then self.during_send() end
    if self.send_failure == "throw" then error("send failed") end
    if self.send_failure == "false" then return false end
    if self.send_failure == "nil-error" then return nil, "send failed" end
    if self.send_failure == "nil" then return nil end
    return true
  end
  function f:hideRoundtimeCheckLine(raw)
    self.hide_attempts = (self.hide_attempts or 0) + 1
    if self.hide_failure == "throw" then error("hide failed") end
    if self.hide_failure == "false" then return false end
    if self.hide_failure == "nil" then return nil end
    self.hidden[#self.hidden + 1] = raw
    return true
  end
  function f:advance(seconds)
    local target, steps = self.now + seconds, 0
    while true do
      local nextID, at
      for id, timer in pairs(self.timers) do
        if timer.at <= target and (not at or timer.at < at or timer.at == at and id < nextID) then
          nextID, at = id, timer.at
        end
      end
      if not nextID then break end
      steps = steps + 1; assert(steps <= 100, "unexpected timer/send loop")
      self.now = at
      local fn = self.timers[nextID].fn; self.timers[nextID] = nil; fn()
    end
    self.now = target
  end
  function f:timerCount()
    local count = 0; for _ in pairs(self.timers) do count = count + 1 end; return count
  end
  local check = Check.new(f, function(value)
    if f.callback_failure == "throw" then error("callback failed") end
    if f.callback_failure == "false" then return false end
    if f.callback_failure == "nil-error" then return nil, "callback failed" end
    f.readings[#f.readings + 1] = value
    if f.during_callback then f.during_callback(value) end
    return true
  end, function()
    if f.permission_failure then error("canSend failed") end
    return f.allowed
  end)
  f.check = check
  return f, check
end

local function close(actual, expected)
  assert(math.abs(actual - expected) < .00001, "expected " .. expected .. ", got " .. actual)
end

local function probe(f, c)
  eq(c:onDelay(7), true); f:advance(.25)
  eq(#f.sends, 1); eq(f.observed[1], true)
end

local function visible(c, raw, value)
  local remaining, hidden = c:onLine(raw)
  eq(remaining, value); eq(hidden, false)
end

local function suspended(f, c)
  eq(c.paused, true); eq(#c.pending, 0); eq(c.probe_timer, nil); eq(c.reply_timer, nil)
  eq(c:onDelay(7), false)
end

test("roundtime check starts idle and pauses neither absent capability nor gated sends", function()
  local f, c = fake(); eq(c.paused, false); f.sendRoundtimeCheck = nil
  eq(c:onDelay(7), false); eq(f:timerCount(), 0); eq(c.paused, false)
  f, c = fake(); f.allowed = false
  eq(c:onDelay(7), false); eq(f:timerCount(), 0)
  c.canSend = nil; eq(c:onDelay(7), false); eq(#f.sends, 0)
end)

test("roundtime check debounces only positive printed delay bursts and never polls", function()
  local f, c = fake()
  c:onDelay(7); f:advance(.2); c:onDelay(2); f:advance(.2); c:onDelay(4)
  f:advance(.24); eq(#f.sends, 0); f:advance(.01); eq(#f.sends, 1)
  close(f.sends[1], 100.65)
  local value, hidden = c:onLine(reply(12)); eq(value, 12); eq(hidden, true)
  f:advance(120); eq(#f.sends, 1); eq(f:timerCount(), 0)
end)

test("roundtime check enforces three seconds between requested sends", function()
  local f, c = fake(); probe(f, c); c:onLine(reply(6))
  c:onDelay(2); f:advance(.25); eq(#f.sends, 1)
  f:advance(2.74); eq(#f.sends, 1); f:advance(.01); eq(#f.sends, 2)
  close(f.sends[2] - f.sends[1], 3)
  c:onLine(reply(2)); f:advance(60); eq(#f.sends, 2)
end)

test("roundtime check holds a requested followup until the owned reply drains", function()
  local f, c = fake(); probe(f, c); c:onDelay(2)
  f:advance(3); eq(#f.sends, 1); eq(#c.pending, 1)
  eq(select(2, c:onLine(reply(3))), true); f:advance(0); eq(#f.sends, 2)
  c:onLine(reply(3)); f:advance(10); eq(#f.sends, 2)
end)

test("roundtime check prefers the fractional clock and can fall back to epoch", function()
  local f, c = fake(); f.epoch = function() error("epoch must not be used") end
  probe(f, c); eq(select(2, c:onLine(reply(5))), true)
  f, c = fake(); f.chatSoundTime = nil; probe(f, c)
  eq(select(2, c:onLine(reply(5))), true)
end)

test("roundtime check rechecks eligibility and send capability before sending", function()
  for _, change in ipairs({"gate", "capability"}) do
    local f, c = fake(); c:onDelay(7)
    if change == "gate" then f.allowed = false else f.sendRoundtimeCheck = nil end
    f:advance(.25); eq(#f.sends, 0); eq(f:timerCount(), 0); eq(c.paused, false)
  end
end)

test("roundtime check proves the actual synchronous owned command and passes the raw reply to gag", function()
  local f, c = fake(); probe(f, c)
  local raw = "\27[36m" .. reply(12) .. "\27[0m\r"
  local remaining, hidden = c:onLine(raw)
  eq(remaining, 12); eq(hidden, true); eq(f.readings[1], 12); eq(f.hidden[1], raw)
  eq(#c.pending, 0); eq(f:timerCount(), 0)
end)

test("roundtime check replaces remaining time rather than adding printed penalties", function()
  local f, c = fake(); local current = 19
  c.onRemaining = function(value) current = value; return true end
  probe(f, c); c:onLine(reply(12)); eq(current, 12)
  eq(c:onOutgoing("delay"), false); c:onLine(reply(0)); eq(current, 0); eq(#f.hidden, 1)
end)

test("roundtime check accepts a nil send result only with synchronous outgoing proof", function()
  local f, c = fake(); f.send_failure = "nil"; probe(f, c)
  eq(select(2, c:onLine(reply(12))), true); eq(c.paused, false)
end)

test("roundtime check true outgoing return is exclusive to the one synchronous HUD event", function()
  local f, c = fake()
  for _, command in ipairs({"look", "north", "delay extra", "delay;look", "delay\ndelay", "", "d"}) do
    eq(c:onOutgoing(command), false)
  end
  eq(c:onOutgoing(nil), false); eq(c:onOutgoing({}), false)
  eq(c:onOutgoing("  DeLaY\r\n"), false); eq(c.pending[1].kind, "manual")
  visible(c, reply(5), 5); eq(#f.hidden, 0)
  probe(f, c); eq(c:onOutgoing("delay"), false)
  visible(c, reply(5), 5); visible(c, reply(4), 4)
end)

test("roundtime check manual before auto cancels the queued probe and is always visible", function()
  local f, c = fake(); c:onDelay(7)
  local stale = f.history[c.probe_timer.id].fn
  eq(c:onOutgoing("delay"), false); eq(c.probe_timer, nil); eq(c.queued_at, nil)
  stale(); f:advance(.3); eq(#f.sends, 0)
  eq(c:onDelay(2), false); visible(c, reply(12), 12)
  eq(f.readings[1], 12); eq(#f.hidden, 0); eq(#c.pending, 0)
  c:onDelay(2); f:advance(.25); eq(#f.sends, 1)
end)

test("roundtime check manual FIFO updates each reply and prevents automatic sends", function()
  local f, c = fake(); eq(c:onOutgoing("delay"), false); f:advance(.5)
  eq(c:onOutgoing("delay"), false); eq(#c.pending, 2)
  eq(c:onDelay(7), false); visible(c, reply(6), 6); eq(#c.pending, 1)
  eq(c:onDelay(7), false); visible(c, reply(5), 5)
  eq(f.readings[1], 6); eq(f.readings[2], 5); eq(#f.hidden, 0); eq(f:timerCount(), 0)
end)

test("roundtime check manual overlapping auto makes the entire ambiguous batch visible", function()
  local f, c = fake(); probe(f, c); c:onDelay(2)
  eq(c:onOutgoing("delay"), false); eq(c:onOutgoing("delay"), false)
  eq(c.ambiguous, true); eq(c.pending[1].ambiguous, true); eq(c.queued_at, nil)
  -- Either apparent ordering of numeric replies is unsafe to conceal.
  visible(c, reply(9), 9); visible(c, reply(8), 8); visible(c, reply(7), 7)
  eq(#f.hidden, 0); eq(#c.pending, 0); eq(c.ambiguous, false)
  f:advance(3); c:onDelay(7); f:advance(.25)
  eq(select(2, c:onLine(reply(6))), true); eq(#f.hidden, 1)
end)

test("roundtime check manual after a completed auto is visible without retroactive ambiguity", function()
  local f, c = fake(); probe(f, c)
  eq(select(2, c:onLine(reply(8))), true)
  eq(c:onOutgoing("delay"), false); visible(c, reply(7), 7); eq(#f.hidden, 1)
end)

test("roundtime check a second outgoing delay inside the owned send is ambiguous", function()
  local f, c = fake()
  f.during_send = function() eq(c:onOutgoing("delay"), false) end
  probe(f, c); eq(#c.pending, 2)
  visible(c, reply(8), 8); visible(c, reply(7), 7); eq(#f.hidden, 0)
end)

test("roundtime check manual arriving during the remaining callback prevents the gag", function()
  local f, c = fake(); probe(f, c)
  f.during_callback = function() f.during_callback = nil; eq(c:onOutgoing("delay"), false) end
  visible(c, reply(8), 8); visible(c, reply(7), 7)
  eq(#f.hidden, 0); eq(#c.pending, 0)
end)

test("roundtime check synchronous response inside send is visible until send success is known", function()
  local f, c = fake()
  f.during_send = function() visible(c, reply(8), 8) end
  probe(f, c); eq(f.readings[1], 8); eq(#f.hidden, 0); eq(f:timerCount(), 0)
end)

test("roundtime check unsolicited responses never update or conceal roundtime", function()
  local f, c = fake()
  visible(c, reply(12), 12); visible(c, "> " .. reply(12), 12)
  eq(#f.readings, 0); eq(#f.hidden, 0); eq(f:timerCount(), 0)
end)

test("roundtime check literal second(s) singular and plural are exact bounded replies", function()
  local f, c = fake()
  for _, raw in ipairs({reply(12), "You have 1 second remaining!", "You have 2 seconds remaining!",
      reply(0), reply(86400)}) do
    eq(c:onOutgoing("delay"), false)
    local value = tonumber(raw:match("You have (%d+)"))
    visible(c, raw, value)
    eq(f.readings[#f.readings], value)
  end
  eq(#f.hidden, 0)
end)

test("roundtime check known prompt prefixes update an owned reply but cannot be gagged", function()
  for _, prefix in ipairs({"> ", "[199] 301/301 hp, 173/173 ftg > "}) do
    local f, c = fake(); probe(f, c)
    visible(c, "\27[32m" .. prefix .. reply(12) .. "\27[0m\r", 12)
    eq(f.readings[1], 12); eq(#f.hidden, 0); eq(#c.pending, 0); eq(c.paused, false)
  end
end)

test("roundtime check rejects malformed mixed quoted multiline and excessive replies", function()
  local f, c = fake(); probe(f, c)
  local invalid = {"", "You have -1 second(s) remaining!", "You have 1.5 second(s) remaining!",
    "You have 86401 second(s) remaining!", "You have many second(s) remaining!",
    "You have 1 second(s) remaining.", "you have 1 second(s) remaining!",
    'Bob says "' .. reply(12) .. '"', "Other output. " .. reply(12), reply(12) .. " Other output.",
    reply(12) .. " >", reply(12) .. "\nOther output.", "You have 1\r2 second(s) remaining!",
    "unknown > " .. reply(12), "> > " .. reply(12), "\0" .. reply(12), "\27]0;title\7" .. reply(12),
    string.rep(" ", 2049) .. reply(12), "You have " .. string.rep("9", 1500) .. " second(s) remaining!"}
  for _, raw in ipairs(invalid) do visible(c, raw, nil) end
  visible(c, nil, nil); visible(c, {}, nil); visible(c, 12, nil)
  eq(#f.readings, 0); eq(#f.hidden, 0); eq(#c.pending, 1)
  eq(select(2, c:onLine(reply(12))), true)
end)

test("roundtime check enforces the raw 2048 byte boundary before ANSI normalization", function()
  local f, c = fake(); probe(f, c)
  local raw = string.rep(" ", 2048 - #reply(12)) .. reply(12)
  eq(select(2, c:onLine(raw)), true)
  f, c = fake(); probe(f, c); visible(c, " " .. raw, nil)
  eq(#c.pending, 1); eq(#f.hidden, 0)
end)

test("roundtime check invalid printed delays create no work or state", function()
  local f, c = fake()
  for _, value in ipairs({0, -1, 86401, math.huge, -math.huge, 0 / 0, "bad", "", {},
      string.rep("1", 65)}) do eq(c:onDelay(value), false) end
  eq(c:onDelay(nil), false); eq(f:timerCount(), 0); eq(#f.sends, 0); eq(c.paused, false)
  eq(c:onDelay(".5"), true); f:advance(.25); eq(#f.sends, 1)
end)

test("roundtime check missing synchronous event fails open and never retries automatically", function()
  for _, mode in ipairs({"no-event", "wrong-event", "async-event"}) do
    local f, c = fake(); f.send_mode = mode; c:onDelay(7); f:advance(.25)
    suspended(f, c); eq(#f.sends, 1); visible(c, reply(12), 12); eq(#f.readings, 0)
    f:advance(.2)
    if mode == "async-event" then
      eq(f.observed[1], false); visible(c, reply(11), 11); eq(f.readings[1], 11)
    end
    f:advance(60); eq(#f.sends, 1); eq(#f.hidden, 0)
  end
end)

test("roundtime check owned timeout cancels queued work and ignores unattributed late output", function()
  local f, c = fake(); local personal = f:schedule(60, function() end)
  probe(f, c); c:onDelay(2); f:advance(4)
  suspended(f, c); eq(f.timers[personal] ~= nil, true); eq(f:timerCount(), 1)
  visible(c, reply(12), 12); eq(#f.readings, 0); eq(#f.hidden, 0)
  c:onOutgoing("delay"); visible(c, reply(5), 5)
  eq(f.readings[1], 5); eq(#f.hidden, 0); eq(c.paused, true)
  f:advance(10); eq(#f.sends, 1)
end)

test("roundtime check an expired reply is rejected even if the timer has not fired", function()
  local f, c = fake(); probe(f, c); f.now = f.now + 4
  visible(c, reply(12), 12); suspended(f, c); eq(#f.readings, 0); eq(#f.hidden, 0)
end)

test("roundtime check manual FIFO deadlines stay anchored to each actual outgoing event", function()
  local f, c = fake(); c:onOutgoing("delay"); f:advance(1); c:onOutgoing("delay")
  f:advance(2); visible(c, reply(5), 5); eq(#c.pending, 1)
  f:advance(1.99); eq(c.paused, false); f:advance(.01); suspended(f, c)
  visible(c, reply(4), 4); eq(#f.readings, 1)
end)

test("roundtime check the pending FIFO cannot grow past thirty two requests", function()
  local f, c = fake()
  for i = 1, 32 do eq(c:onOutgoing("delay"), false); eq(#c.pending, i) end
  eq(f:timerCount(), 1); eq(c:onDelay(7), false)
  eq(c:onOutgoing("delay"), false); suspended(f, c); eq(f:timerCount(), 0)
  for _ = 1, 100 do c:onOutgoing("delay"); assert(#c.pending <= 32); assert(f:timerCount() <= 1) end
  eq(#f.sends, 0); eq(#f.hidden, 0)
end)

test("roundtime check scheduler exceptions and unsuccessful results suspend before any send", function()
  for _, mode in ipairs({"throw", "nil", "false"}) do
    local f, c = fake(); f.schedule_failure = mode
    eq(c:onDelay(7), false); suspended(f, c); eq(#f.sends, 0); eq(f:timerCount(), 0)
    f, c = fake(); f.schedule_failure = mode; f.schedule_fail_at = 2
    c:onDelay(7); f:advance(.25); suspended(f, c); eq(#f.sends, 0); eq(f:timerCount(), 0)
  end
end)

test("roundtime check missing schedule or cancellation support fails open without sends", function()
  for _, method in ipairs({"schedule", "cancelTimer"}) do
    local f, c = fake(); f[method] = nil
    eq(c:onDelay(7), false); suspended(f, c); eq(#f.sends, 0); eq(f:timerCount(), 0)
  end
end)

test("roundtime check rejects a synchronous scheduler without recursion or leaked ownership", function()
  local f, c = fake()
  function f:schedule(_, fn)
    self.next_id = self.next_id + 1
    local id = self.next_id; self.timers[id] = {at = self.now, fn = fn}
    fn(); return id
  end
  eq(c:onDelay(7), false); suspended(f, c); eq(#f.sends, 0); eq(f:timerCount(), 0)
end)

test("roundtime check send exceptions and unsuccessful results leave replies visible", function()
  for _, mode in ipairs({"throw", "false", "nil-error"}) do
    local f, c = fake(); f.send_failure = mode; c:onDelay(7); f:advance(.25)
    suspended(f, c); visible(c, reply(12), 12)
    eq(#f.sends, 1); eq(#f.hidden, 0); eq(#f.readings, 0); eq(f:timerCount(), 0)
  end
end)

test("roundtime check hide failures stop further checks while keeping the failing reply visible", function()
  for _, mode in ipairs({"throw", "false", "nil", "missing"}) do
    local f, c = fake(); probe(f, c)
    if mode == "missing" then f.hideRoundtimeCheckLine = nil else f.hide_failure = mode end
    visible(c, reply(12), 12); suspended(f, c)
    eq(f.readings[1], 12); eq(#f.hidden, 0); eq(f:timerCount(), 0)
  end
end)

test("roundtime check only gags after a successful remaining callback", function()
  for _, mode in ipairs({"throw", "false", "nil-error"}) do
    local f, c = fake(); probe(f, c); f.callback_failure = mode
    visible(c, reply(12), 12); suspended(f, c); eq(f.hide_attempts, nil); eq(#f.hidden, 0)
  end
  local f, c = fake(); probe(f, c); c.onRemaining = function(value) f.readings[1] = value end
  eq(select(2, c:onLine(reply(12))), true); eq(f.readings[1], 12)
end)

test("roundtime check canSend and clock exceptions suspend without leaking callbacks", function()
  local f, c = fake(); f.permission_failure = true
  eq(c:onDelay(7), false); suspended(f, c); eq(#f.sends, 0)
  f, c = fake(); c:onDelay(7); f.permission_failure = true
  f:advance(.25); suspended(f, c); eq(#f.sends, 0)
  for _, value in ipairs({"throw", "missing", -1, math.huge, 0 / 0}) do
    f, c = fake()
    if value == "missing" then f.chatSoundTime = nil; f.epoch = nil
    else f.chatSoundTime = function() if value == "throw" then error("clock failed") end; return value end end
    eq(c:onDelay(7), false); suspended(f, c); eq(#f.sends, 0)
  end
end)

test("roundtime check cancellation failures invalidate stale timers and prevent a reply gag", function()
  for _, mode in ipairs({"throw", "false", "nil-error"}) do
    local f, c = fake(); c:onDelay(7)
    local stale = f.history[c.probe_timer.id].fn; f.cancel_failure = mode
    eq(c:onDelay(2), false); suspended(f, c); stale(); eq(#f.sends, 0)
    f, c = fake(); probe(f, c); f.cancel_failure = mode
    visible(c, reply(12), 12); suspended(f, c); eq(#f.hidden, 0)
    f:advance(10); eq(#f.sends, 1)
  end
end)

test("roundtime check clean reset invalidates queued callbacks and remains usable", function()
  local f, c = fake(); c:onDelay(7)
  local stale = f.history[c.probe_timer.id].fn
  eq(c:reset(), true); eq(c.paused, false); stale(); eq(#f.sends, 0)
  probe(f, c); eq(select(2, c:onLine(reply(12))), true)
end)

test("roundtime check reset abandoning auto or manual replies stays paused across character changes", function()
  for _, kind in ipairs({"auto", "manual"}) do
    local f, c = fake()
    if kind == "auto" then probe(f, c) else c:onOutgoing("delay") end
    local stale = f.history[c.reply_timer.id].fn
    eq(c:reset(), true); suspended(f, c)
    stale(); visible(c, reply(12), 12); eq(#f.readings, 0); eq(#f.hidden, 0)
    c:reset(); eq(c.paused, true)
    eq(c:onOutgoing("delay"), false); visible(c, reply(5), 5); eq(f.readings[1], 5)
    eq(#f.hidden, 0)
  end
end)

test("roundtime check timeout suspension survives a subsequent clean reset", function()
  local f, c = fake(); probe(f, c); f:advance(4); c:reset()
  suspended(f, c); visible(c, reply(12), 12); eq(#f.readings, 0)
end)

test("roundtime check reset during callback invalidates the old request before gagging", function()
  local f, c = fake(); probe(f, c)
  f.during_callback = function() c:reset() end
  visible(c, reply(12), 12); suspended(f, c); eq(#f.hidden, 0)
end)

test("roundtime check nested reply callback fails open without unbounded recursion", function()
  local f, c = fake(); probe(f, c)
  f.during_callback = function() visible(c, reply(11), 11) end
  visible(c, reply(12), 12); suspended(f, c); eq(#f.readings, 1); eq(#f.hidden, 0)
end)

test("roundtime check shutdown is permanent and preserves unrelated timers", function()
  for _, stage in ipairs({"queued", "pending"}) do
    local f, c = fake(); local personal = f:schedule(60, function() end)
    c:onDelay(7); if stage == "pending" then f:advance(.25) end
    local ticket = c.probe_timer or c.reply_timer; local stale = f.history[ticket.id].fn
    local sends = #f.sends; eq(c:shutdown(), true); eq(c:shutdown(), true)
    eq(f.timers[personal] ~= nil, true); eq(f:timerCount(), 1)
    stale(); eq(c:onDelay(7), false); eq(c:onOutgoing("delay"), false)
    visible(c, reply(12), nil); eq(#f.readings, 0); eq(#f.hidden, 0)
    c:reset(); eq(c:onDelay(7), false); eq(#f.sends, sends)
  end
end)
