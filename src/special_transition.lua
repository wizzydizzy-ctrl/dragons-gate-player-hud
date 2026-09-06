local Special={}; Special.__index=Special

local specialNouns={gate=true,door=true,portal=true,arch=true,path=true}
local traversalVerbs={enter=true,leave=true,climb=true,crawl=true,cross=true,board=true,disembark=true}

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function normalize(value)
  return trim(value):lower():gsub("%s+"," ")
end

local function positive(value)
  local number=tonumber(value)
  return number and number==number and number~=math.huge and number~=-math.huge and number>0 and number%1==0
end

local function builtInTravel(value)
  local verb,arguments=value:match("^(%S+)%s*(.*)$")
  if verb=="go" then
    for word in arguments:gmatch("[%w_'-]+") do
      if specialNouns[word] then return word end
    end
    return nil
  end
  if not traversalVerbs[verb] then return nil end
  return (verb=="leave" or verb=="disembark" or arguments~="") and "other" or nil
end

local function configuredTravel(value,patterns)
  for _,pattern in ipairs(patterns or {}) do
    if type(pattern)=="string" and value:match(pattern) then return true end
    if type(pattern)=="function" then
      local ok,result=pcall(pattern,value)
      if ok and result then return true end
    end
  end
  return false
end

local function boundedError(prefix,detail)
  local message=tostring(prefix)
  if detail~=nil and tostring(detail)~="" then message=message..": "..tostring(detail) end
  if #message>200 then return message:sub(1,197).."..." end
  return message
end

local failurePatterns={
  "^you cannot move in that direction%.?$",
  "^you cannot go that way%.?$",
  "^you can't go that way%.?$",
  "^i don't see what you are referring to%.?$",
  "^there is no .+ here%.?$",
}

function Special.new(model,adapter,timeoutSeconds,onStatus,extraPatterns)
  return setmetatable({model=model,adapter=adapter,timeout_seconds=tonumber(timeoutSeconds) or 12,onStatus=onStatus or function() end,extra_patterns=extraPatterns or {}},Special)
end

function Special:status(kind)
  pcall(self.onStatus,kind)
end

function Special:pending()
  return self.candidate
end

function Special:cancel(reason)
  local timer=self.timer
  local owned=timer~=nil or self.candidate~=nil
  self.timer=nil; self.candidate=nil
  if timer~=nil then
    local callOk,ok,err=pcall(self.adapter.cancelTimer,self.adapter,timer)
    if not callOk then return nil,ok end
    if ok==false or ok==nil and err then return nil,err or "special transition timer cancellation failed" end
  end
  if owned and reason then self:status(reason) end
  return true
end

function Special:onOutgoing(command,originID)
  local cancelled,cancelErr=self:cancel("replaced")
  if not cancelled then return nil,boundedError("special transition replacement cancellation failed",cancelErr) end
  local classified=normalize(command)
  if not positive(originID) or classified=="" or self.model.direction(classified) then return nil end
  local category=builtInTravel(classified)
  if not category and configuredTravel(classified,self.extra_patterns) then category="other" end
  if not category then return nil end
  local timer,err
  local callOk
  callOk,timer,err=pcall(self.adapter.schedule,self.adapter,self.timeout_seconds,function()
    if self.timer==timer then self.timer=nil; self.candidate=nil; self:status("expired") end
  end)
  if not callOk then err=timer; timer=nil end
  if not timer then return nil,err or "special transition timer could not be created" end
  self.timer=timer; self.candidate={from=tonumber(originID),command=classified,category=category}
  return true
end

function Special:onRoom(roomID)
  local destination=positive(roomID) and tonumber(roomID) or nil
  if not self.candidate or not destination or destination==self.candidate.from then return nil end
  local result={from=self.candidate.from,to=destination,command=self.candidate.command,category=self.candidate.category or "other",kind="special"}
  local ok,err=self:cancel("confirmed")
  if not ok then return nil,err end
  return result
end

function Special:onLine(line)
  if not self.candidate then return nil end
  local value=normalize(line)
  for _,pattern in ipairs(failurePatterns) do
    if value:match(pattern) then return self:cancel("failed") end
  end
  return nil
end

function Special:shutdown()
  return self:cancel("shutdown")
end

return Special
