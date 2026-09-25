local Walker={}; Walker.__index=Walker

local directions={n=true,ne=true,e=true,se=true,s=true,sw=true,w=true,nw=true,up=true,down=true,["in"]=true,out=true}
local aliases={north="n",northeast="ne",east="e",southeast="se",south="s",southwest="sw",west="w",northwest="nw",u="up",d="down"}

local function direction(value)
  value=tostring(value or ""):lower():match("^%s*(.-)%s*$")
  value=aliases[value] or value
  return directions[value] and value or nil
end

function Walker.new(adapter,onStatus,timeoutSeconds)
  return setmetatable({adapter=adapter,onStatus=onStatus or function() end,timeout_seconds=tonumber(timeoutSeconds) or 12,roundtime=0},Walker)
end

function Walker:status(kind,message,isError) pcall(self.onStatus,kind,message,isError==true) end
function Walker:active() return self.route~=nil end

function Walker:clearTimer()
  if self.timeout==nil then return true end
  local id=self.timeout; self.timeout=nil
  local ok,result,err=pcall(self.adapter.cancelTimer,self.adapter,id)
  if not ok then return nil,result end
  if result==false or result==nil and err then return nil,err or "movement timer cancellation failed" end
  return true
end

function Walker:stop(reason,isError)
  if not self.route then return true end
  local timerOk,timerErr=self:clearTimer()
  self.route=nil; self.expected=nil; self.origin=nil; self.index=nil; self.destination=nil; self.waiting_roundtime=nil
  if self.adapter.clearGenerated then pcall(self.adapter.clearGenerated,self.adapter) end
  if reason=="arrived" then self:status("arrived","Arrived at "..tostring(self.last_destination))
  else self:status("stopped","Walk stopped: "..tostring(reason or "stopped"),isError) end
  if not timerOk then return nil,timerErr end
  return true
end

function Walker:sendNext()
  local command=self.route and self.route.commands[self.index]
  if not command then self.last_destination=self.destination; return self:stop("arrived") end
  self.origin=self.route.rooms[self.index]
  if self.roundtime>0 then
    self.expected=nil
    self.waiting_roundtime=true
    self:status("paused","Walk paused for roundtime "..tostring(self.roundtime))
    return true
  end
  self.waiting_roundtime=nil
  self.expected=self.route.rooms[self.index+1]
  local callOk,sent,err=pcall(self.adapter.sendCommand,self.adapter,command,true)
  if not callOk then err=sent; sent=nil end
  if sent==nil or sent==false then local reason=err or "movement command failed"; self:stop(reason,true); return nil,reason end
  local scheduleOk,timer,scheduleErr=pcall(self.adapter.schedule,self.adapter,self.timeout_seconds,function() self.timeout=nil; self:stop("movement timed out",true) end)
  if not scheduleOk then scheduleErr=timer; timer=nil end
  self.timeout=timer
  if scheduleErr then self:stop(scheduleErr,true); return nil,scheduleErr end
  if self.timeout==nil then self:stop("movement timer could not be created",true); return nil,"movement timer could not be created" end
  return true
end

function Walker:start(route,destination)
  if self.route then self:stop("replaced") end
  if type(route)~="table" or type(route.rooms)~="table" or type(route.commands)~="table" then return nil,"invalid route" end
  if #route.rooms~=#route.commands+1 then return nil,"route rooms and commands do not match" end
  if #route.commands==0 then return nil,"route has no movement commands" end
  local rooms={}
  for index,roomID in ipairs(route.rooms) do
    local numeric=tonumber(roomID)
    if not numeric or numeric<=0 or numeric%1~=0 then return nil,"invalid route room "..tostring(roomID) end
    rooms[index]=numeric
  end
  destination=tonumber(destination or route.rooms[#route.rooms])
  if not destination or tonumber(route.rooms[#route.rooms])~=destination then return nil,"route destination does not match "..tostring(destination) end
  local commands={}
  for index,command in ipairs(route.commands) do
    local canonical=direction(command)
    local validate=self.adapter and self.adapter.validateStep
    if type(validate)~="function" then return nil,(canonical and "standard" or "special").." exit is not confirmed from "..rooms[index].." to "..rooms[index+1] end
    local callOk,confirmed,validated=pcall(validate,self.adapter,rooms[index],rooms[index+1],command)
    if not callOk then return nil,confirmed end
    if not confirmed then return nil,validated or (canonical and "standard" or "special").." exit is not confirmed from "..rooms[index].." to "..rooms[index+1] end
    commands[index]=validated or canonical or command
  end
  self.route={rooms=rooms,commands=commands}
  self.destination=destination; self.index=1
  self:status("walking","Walking to "..tostring(destination))
  return self:sendNext()
end

function Walker:onRoom(roomID)
  if not self.route then return true end
  local actual=tonumber(roomID)
  if actual==tonumber(self.origin) then return true end
  if not self.expected or actual~=tonumber(self.expected) then return self:stop("unexpected room "..tostring(roomID),true) end
  local timerOk,timerErr=self:clearTimer()
  if not timerOk then
    self:stop(timerErr or "movement timer cancellation failed",true)
    return nil,timerErr or "movement timer cancellation failed"
  end
  self.index=self.index+1
  return self:sendNext()
end

function Walker:onRoundtime(value)
  self.roundtime=math.max(0,math.floor(tonumber(value) or 0))
  if self.route and self.waiting_roundtime and self.roundtime==0 then
    self.waiting_roundtime=nil
    return self:sendNext()
  end
  return true
end

function Walker:onWrongDirection() if self.route then return self:stop("wrong direction",true) end; return true end
function Walker:onManualMovement(command,generated)
  if self.route and not generated then return self:stop("manual movement") end
  return true
end
function Walker:shutdown() if self.route then return self:stop("shutdown") end; return true end

return Walker
