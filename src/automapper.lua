local Automapper={}; Automapper.__index=Automapper

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function contains(values,wanted)
  for _,value in ipairs(values or {}) do if value==wanted then return true end end
  return false
end

local function positiveInteger(value)
  local number=tonumber(value)
  if not number or number~=number or number==math.huge or number==-math.huge or number<=0 or number%1~=0 then return nil end
  return number
end

function Automapper.new(model,map,onStatus,transitionSubmaps)
  return setmetatable({model=model,map=map,onStatus=onStatus or function() end,transition_submaps=transitionSubmaps or {},current_id=nil,pending=nil,direction_queue={}},Automapper)
end

function Automapper:status(kind,message)
  pcall(self.onStatus,kind,tostring(message or ""))
end

function Automapper:onOutgoing(command)
  local value=trim(command)
  local classified=value:lower()
  local direction=self.model.direction(classified)
  if direction and self.current_id then
    if self.pending and self.pending.direction then
      self.direction_queue[#self.direction_queue+1]=direction
    else
      self.direction_queue={}
      self.pending={from=self.current_id,direction=direction}
    end
  else
    self.direction_queue={}
    self.pending=nil
  end
  return direction
end

function Automapper:onSpecialTransition(transition)
  self.direction_queue={}
  local from=type(transition)=="table" and positiveInteger(transition.from) or nil
  local to=type(transition)=="table" and positiveInteger(transition.to) or nil
  local command=type(transition)=="table" and trim(transition.command) or ""
  if not from or not to or from==to or command=="" or transition.kind~="special" then
    self.pending=nil
    return nil,"invalid special transition"
  end
  local category=tostring(transition.category or "other"); local newSubmap=self.transition_submaps[category]~=false
  self.pending={kind="special",from=from,to=to,command=command,category=category,new_submap=newSubmap}
  return true
end

function Automapper:roomRecord(roomID)
  if type(self.map.roomRecord)=="function" then return self.map:roomRecord(roomID) end
  local coordinates,coordinatesErr=self.map:coordinates(roomID)
  if coordinates then return {exists=true,owned=true,coordinates=coordinates,placement_needed=false,legacy=true} end
  if coordinatesErr then return nil,coordinatesErr end
  return {exists=false,owned=false,placement_needed=true,legacy=true}
end

function Automapper:partitionFor(room,record)
  if record.exists and not record.placement_needed then
    if record.partition then return record.partition end
    if record.legacy then return room.area_key end
    if record.owned then return self.map:effectivePartition(room.id) end
    return room.area_key
  end
  if self.pending and self.pending.kind=="special" and self.pending.new_submap~=false and self.pending.from~=room.id then
    return "special:"..tostring(room.id)
  end
  if self.pending and self.pending.kind=="special" and self.pending.new_submap==false and self.pending.from~=room.id then
    local origin,err=self:roomRecord(self.pending.from); if not origin then return nil,err end
    if not origin.exists or not origin.owned then return nil,"special transition origin is not owned by DragonsGateHUD" end
    return origin.partition or self.map:effectivePartition(self.pending.from)
  end
  if self.pending and self.pending.direction and self.pending.from~=room.id then
    local origin,originErr=self:roomRecord(self.pending.from)
    if origin==nil then return nil,originErr end
    if origin.exists and origin.owned then
      local originPartition=origin.partition
      if not originPartition then originPartition,originErr=self.map:effectivePartition(self.pending.from) end
      if originPartition==nil and originErr then return nil,originErr end
      if originPartition~=nil then return originPartition end
    end
  end
  if self.current_id and self.current_id~=room.id and not self.pending then
    local origin,originErr=self:roomRecord(self.current_id)
    if origin==nil then return nil,originErr end
    if origin.exists and origin.owned then
      if origin.game_area==room.area_key then
        local originPartition=origin.partition
        if not originPartition then originPartition,originErr=self.map:effectivePartition(self.current_id) end
        if originPartition==nil and originErr then return nil,originErr end
        if originPartition~=nil then return originPartition end
      end
      return "isolated:"..tostring(room.id)
    end
    return room.area_key
  end
  return room.area_key
end

function Automapper:coordinatesFor(room,partition,record)
  if not record or not record.placement_needed then
    if record and record.coordinates then return record.coordinates end
    local existing,existingErr=self.map:coordinates(room.id)
    if existing then return existing end
    if existingErr then return nil,existingErr end
  end
  local desired={x=0,y=0,z=0}
  if self.pending then
    local origin=self.map:coordinates(self.pending.from)
    desired=origin and self.model.destination(origin,self.pending.direction) or desired
  end
  if self.pending and self.pending.direction and type(self.map.reserveDirectionalCoordinate)=="function" then
    local reserved,reserveErr=self.map:reserveDirectionalCoordinate(partition,desired,self.pending.direction,self.pending.from)
    if reserved then return reserved end
    if reserveErr then return nil,reserveErr end
  end
  local occupancyErr
  local coordinates=self.model.nearestFree(desired,function(x,y,z)
    local occupied,err=self.map:roomsAt(partition,x,y,z)
    if occupied==nil then occupancyErr=err or "room occupancy lookup failed"; return false end
    for _,id in pairs(occupied) do if tonumber(id)~=room.id then return true end end
    return false
  end)
  if occupancyErr then return nil,occupancyErr end
  return coordinates
end

local function hasObservedPlacementIntent(self,room)
  local pending=self.pending
  if not pending or pending.from==room.id or self.current_id~=pending.from then return false end
  local special=pending.kind=="special" and pending.to==room.id
  local directional=pending.kind==nil and pending.direction~=nil
  if not special and not directional then return false end
  local origin,originErr=self:roomRecord(pending.from)
  if origin==nil then return nil,originErr end
  if not origin.exists or not origin.owned then return false end
  if directional then
    local coordinates,coordinatesErr=self.map:coordinates(pending.from)
    if not coordinates then return nil,coordinatesErr end
  end
  return true
end

local function failUnensuredRoom(self,room,sameOrigin,kind,err)
  if not sameOrigin then self.pending=nil; self.direction_queue={} end
  if not room or (self.current_id and self.current_id~=room.id) then self.current_id=nil end
  self:status(kind,err)
  return nil,err
end

local function failEnsuredRoom(self,roomID,sameOrigin,kind,err)
  if not sameOrigin then
    self.pending=nil; self.direction_queue={}
    self.current_id=roomID
    local current,currentErr=self.map:setCurrent(roomID)
    if not current then
      self.current_id=nil
      self:status(kind,tostring(err).."; destination synchronization failed: "..tostring(currentErr))
      return nil,err
    end
  end
  self:status(kind,err)
  return nil,err
end

function Automapper:onRoom(raw)
  local room,normalizeErr=self.model.normalizeRoom(raw)
  if not room then return failUnensuredRoom(self,nil,false,"invalid_room",normalizeErr) end
  local sameOrigin=self.pending and self.pending.from==room.id
  local specialArrival=self.pending and self.pending.kind=="special" and not sameOrigin
  local specialCommand=specialArrival and self.pending.command or nil
  if specialArrival and self.pending.to~=room.id then
    local err="special transition destination did not match GMCP room"
    return failUnensuredRoom(self,room,sameOrigin,"invalid_room",err)
  end
  local record,recordErr=self:roomRecord(room.id)
  if not record then return failUnensuredRoom(self,room,sameOrigin,"invalid_room",recordErr) end
  if record.exists and record.placement_needed then
    local hasIntent,intentErr=hasObservedPlacementIntent(self,room)
    if not hasIntent then
      local err=intentErr or ("room "..tostring(room.id).." placement requires an observed transition")
      return failUnensuredRoom(self,room,sameOrigin,"invalid_room",err)
    end
  end
  local partition,partitionErr=self:partitionFor(room,record)
  if not partition then return failUnensuredRoom(self,room,sameOrigin,"invalid_room",partitionErr) end
  local coordinates,coordinatesErr
  if specialArrival and self.pending.new_submap~=false and (not record.exists or record.placement_needed) then coordinates={x=0,y=0,z=0} else coordinates,coordinatesErr=self:coordinatesFor(room,partition,record) end
  if not coordinates then return failUnensuredRoom(self,room,sameOrigin,"invalid_room",coordinatesErr) end
  local ensured,ensureErr=self.map:ensureRoom(room,coordinates,partition)
  if not ensured then
    local kind=tostring(ensureErr):find("not owned",1,true) and "ownership_conflict" or "invalid_room"
    return failUnensuredRoom(self,room,sameOrigin,kind,ensureErr)
  end
  for _,direction in ipairs(room.exits) do
    local stubbed,stubErr=self.map:ensureStub(room.id,direction)
    if not stubbed then
      local kind=tostring(stubErr):find("not owned",1,true) and "ownership_conflict" or "invalid_room"
      return failEnsuredRoom(self,room.id,sameOrigin,kind,stubErr)
    end
  end
  local previous=self.current_id
  if self.pending and self.pending.from~=room.id then
    local connected,connectErr
    if self.pending.kind=="special" then
      connected,connectErr=self.map:connectSpecial(self.pending.from,room.id,self.pending.command)
    else
      local reverse=self.model.opposite(self.pending.direction)
      connected,connectErr=self.map:connect(self.pending.from,room.id,self.pending.direction,contains(room.exits,reverse))
    end
    if not connected then return failEnsuredRoom(self,room.id,sameOrigin,"invalid_room",connectErr) end
  end
  local completedPending=self.pending
  local hadPending=completedPending~=nil
  if not sameOrigin then
    self.pending=nil
    if completedPending and completedPending.direction and #self.direction_queue>0 then
      self.pending={from=room.id,direction=table.remove(self.direction_queue,1)}
    else
      self.direction_queue={}
    end
  end
  self.current_id=room.id
  local current,currentErr=self.map:setCurrent(room.id)
  if not current then self.current_id=nil; self:status("invalid_room",currentErr); return nil,currentErr end
  if previous and previous~=room.id and not hadPending then
    self:status("teleport","room changed without a tracked direction; isolated room "..tostring(room.id))
  elseif specialArrival then
    self:status("mapped",(completedPending and completedPending.new_submap==false and "mapped special exit on current map at room " or "entered submap at room ")..tostring(room.id).." via "..tostring(specialCommand or "special exit"))
  else
    self:status("mapped","room "..tostring(room.id))
  end
  return true
end

function Automapper:onWrongDirection()
  self.pending=nil
  if #self.direction_queue>0 and self.current_id then self.pending={from=self.current_id,direction=table.remove(self.direction_queue,1)} else self.direction_queue={} end
  return true
end
function Automapper:onDisconnect() self.pending=nil; self.direction_queue={}; return true end
function Automapper:currentRoom() return self.current_id end
function Automapper:shutdown() self.pending=nil; self.direction_queue={}; self.current_id=nil; return true end

return Automapper
