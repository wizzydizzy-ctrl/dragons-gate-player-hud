local Transfer={}
Transfer.__index=Transfer

local DIRECTIONS={n=true,ne=true,e=true,se=true,s=true,sw=true,w=true,nw=true,up=true,down=true,["in"]=true,out=true}
local POLICIES={keep_mine=true,use_imported=true,skip_area=true}

local function copy(value,seen)
  if type(value)~="table" then return value end
  seen=seen or {}; if seen[value] then return seen[value] end
  local out={}; seen[value]=out
  for key,item in pairs(value) do out[copy(key,seen)]=copy(item,seen) end
  return out
end
local function invoke(target,name,...)
  local fn=target and target[name]; if type(fn)~="function" then return nil,"map transfer backend "..name.." is unavailable" end
  local ok,a,b=pcall(fn,target,...); if not ok then return nil,tostring(a) end
  if a==nil and b~=nil then return nil,tostring(b) end
  return a,b
end
local function integer(value) local n=tonumber(value); return n and n>0 and n%1==0 and n or nil end
local function dense(value,maximum)
  if type(value)~="table" then return nil end
  local count,top=0,0
  for key in pairs(value) do if type(key)~="number" or key<1 or key%1~=0 then return nil end; count=count+1; top=math.max(top,key) end
  if count~=top or top>(maximum or top) then return nil end
  return top
end
local function text(value,limit,empty)
  if type(value)~="string" or #value>(limit or 256) or (not empty and value=="") or value:find("[%z\1-\8\11\12\14-\31]") then return nil end
  return value
end
local function sortedStrings(values,limit)
  local count=dense(values,limit); if not count then return nil end
  local out,seen={},{}
  for index=1,count do local value=text(values[index],128,false); if not value or seen[value] then return nil end; seen[value]=true; out[#out+1]=value end
  table.sort(out); return out
end
local function sortedExits(values,special,roomIDs)
  local count=dense(values,256); if not count then return nil end
  local out,seen={},{}
  for index=1,count do
    local item=values[index]; if type(item)~="table" then return nil end
    local to=integer(item.to); if not to or not roomIDs[to] then return nil end
    local key
    if special then
      local command=text(item.command,160,false); if not command then return nil end
      command=command:match("^%s*(.-)%s*$"):lower(); if command=="" then return nil end
      key=command.."\0"..to; item={command=command,to=to}
    else
      local direction=type(item.direction)=="string" and item.direction:lower() or nil
      if not DIRECTIONS[direction] then return nil end
      key=direction; item={direction=direction,to=to}
    end
    if seen[key] then return nil end; seen[key]=true; out[#out+1]=item
  end
  table.sort(out,function(a,b) local ak=special and a.command or a.direction; local bk=special and b.command or b.direction; return ak==bk and a.to<b.to or ak<bk end)
  return out
end
local function canonicalRoom(room,roomIDs)
  if type(room)~="table" then return nil,"room must be an object" end
  local id=integer(room.id); local partition=text(room.partition,160,false); local area=text(room.area,160,false)
  local name=text(room.name or "",512,true); local environment=text(room.environment or "",160,true)
  if not id or not partition or not area or not name or not environment then return nil,"room has invalid identity fields" end
  local position={}; for _,key in ipairs({"x","y","z"}) do local n=tonumber(room[key]); if not n or n~=n or n==math.huge or n==-math.huge or n%1~=0 or math.abs(n)>1000000 then return nil,"room has invalid coordinates" end; position[key]=n end
  local flags=sortedStrings(room.flags or {},64); local poi=sortedStrings(room.poi or {},64)
  if not flags or not poi then return nil,"room has invalid flags or POI tags" end
  local exits=sortedExits(room.exits or {},false,roomIDs); local special=sortedExits(room.special_exits or {},true,roomIDs)
  if not exits or not special then return nil,"room has invalid exits" end
  return {id=id,area=area,partition=partition,x=position.x,y=position.y,z=position.z,name=name,environment=environment,flags=flags,poi=poi,exits=exits,special_exits=special}
end

function Transfer.new(backend,options)
  options=options or {}
  return setmetatable({backend=backend,room_limit=tonumber(options.room_limit) or 20000,string_limit=tonumber(options.string_limit) or 1048576},Transfer)
end

function Transfer:validate(data)
  if type(data)~="table" or data.format~="DragonsGateHUD-map" or data.schema~=1 then return nil,"unsupported map format" end
  if type(data.provenance)~="table" then return nil,"map provenance is required" end
  local artifact=text(data.provenance.artifact_id,128,false); local author=text(data.provenance.author,128,false)
  local publisher=text(data.provenance.publisher or "unknown",64,false); local slug=text(data.provenance.slug or "map",64,false)
  if not artifact or not author or not publisher or not slug then return nil,"map provenance is invalid" end
  local count=dense(data.rooms,self.room_limit); if not count or count==0 then return nil,"rooms must be a non-empty dense array" end
  local roomIDs={}; for index=1,count do local id=type(data.rooms[index])=="table" and integer(data.rooms[index].id); if not id or roomIDs[id] then return nil,"map contains an invalid or duplicate canonical room ID" end; roomIDs[id]=true end
  local rooms,coordinates={},{}; local stringBytes=#artifact+#author
  for index=1,count do
    local room,err=canonicalRoom(data.rooms[index],roomIDs); if not room then return nil,err.." at index "..index end
    stringBytes=stringBytes+#room.area+#room.partition+#room.name+#room.environment
    for _,value in ipairs(room.flags) do stringBytes=stringBytes+#value end; for _,value in ipairs(room.poi) do stringBytes=stringBytes+#value end
    for _,value in ipairs(room.special_exits) do stringBytes=stringBytes+#value.command end
    if stringBytes>self.string_limit then return nil,"map text exceeds import safety limit" end
    local coordinate=room.partition.."\0"..room.x..","..room.y..","..room.z
    if coordinates[coordinate] then return nil,"rooms collide at one partition coordinate" end
    coordinates[coordinate]=room.id; rooms[#rooms+1]=room
  end
  table.sort(rooms,function(a,b) return a.id<b.id end)
  -- File-supplied attribution is descriptive, never proof of authorship. A future
  -- signed distribution layer may promote it only after external verification.
  return {format="DragonsGateHUD-map",schema=1,provenance={artifact_id=artifact,author=author,publisher=publisher,slug=slug,derived_from=copy(data.provenance.derived_from),verified=false},rooms=rooms}
end

function Transfer:exportData(provenance)
  if type(self.backend)~="table" or type(self.backend.listRooms)~="function" or type(self.backend.getRoom)~="function" then return nil,"map transfer backend is unavailable" end
  local ids,err=invoke(self.backend,"listRooms"); if not ids then return nil,err end
  local count=dense(ids,self.room_limit); if not count then return nil,"backend returned an invalid room list" end
  local rooms={}; for index=1,count do local room,readErr=invoke(self.backend,"getRoom",ids[index]); if not room then return nil,readErr or "room read failed" end; rooms[#rooms+1]=copy(room) end
  return self:validate({format="DragonsGateHUD-map",schema=1,provenance=copy(provenance),rooms=rooms})
end

local function policyFor(policies,area,roomID)
  local policy=type(policies)=="table" and ((type(policies.rooms)=="table" and policies.rooms[roomID]) or policies[area] or policies.default) or nil
  return POLICIES[policy] and policy or nil
end

function Transfer:preview(data,policies)
  local model,err=self:validate(data); if not model then return nil,err end
  if type(self.backend)~="table" or type(self.backend.getRoom)~="function" then return nil,"map transfer backend is unavailable" end
  local plan={model=model,policies=copy(policies),areas={},conflicts=0,creates=0,keeps=0,replaces=0,skips=0,blocked=false}
  local grouped={}
  for _,room in ipairs(model.rooms) do grouped[room.area]=grouped[room.area] or {}; grouped[room.area][#grouped[room.area]+1]=room end
  local names={}; for name in pairs(grouped) do names[#names+1]=name end; table.sort(names)
  for _,area in ipairs(names) do
    local areaPolicy=policyFor(policies,area); if not areaPolicy then return nil,"missing conflict policy for area "..area end
    local report={name=area,policy=areaPolicy,rooms={},conflicts=0,blocked=false}; plan.areas[#plan.areas+1]=report
    for _,room in ipairs(grouped[area]) do
      local policy=policyFor(policies,area,room.id)
      local existing,readErr=invoke(self.backend,"getRoom",room.id)
      if readErr then return nil,readErr end
      local action
      if policy=="skip_area" then action="skip"; plan.skips=plan.skips+1
      elseif not existing then action="create"; plan.creates=plan.creates+1
      else
        report.conflicts=report.conflicts+1; plan.conflicts=plan.conflicts+1
        if existing.owner and existing.owner~="DragonsGateHUD" then action="blocked"; report.blocked=true; plan.blocked=true
        elseif policy=="keep_mine" then action="keep"; plan.keeps=plan.keeps+1
        else action="replace"; plan.replaces=plan.replaces+1 end
      end
      report.rooms[#report.rooms+1]={id=room.id,action=action}
    end
  end
  return plan
end

function Transfer:apply(plan,character)
  if type(plan)~="table" or type(plan.model)~="table" or type(plan.areas)~="table" then return nil,"validated preview is required" end
  if plan.blocked then return nil,"import has blocked room-ID conflicts" end
  character=text(character,128,false); if not character then return nil,"current character is required" end
  local backend=self.backend
  if type(backend.putRoom)~="function" or type(backend.deleteRoom)~="function" or type(backend.getRoom)~="function" then return nil,"transactional map backend is unavailable" end
  local fresh,freshErr=self:preview(plan.model,plan.policies); if not fresh then return nil,freshErr end
  local function shape(value)
    local out={}; for _,area in ipairs(value.areas) do for _,entry in ipairs(area.rooms) do out[#out+1]=area.name.."\0"..area.policy.."\0"..entry.id.."\0"..entry.action end end; table.sort(out); return table.concat(out,"\1")
  end
  if fresh.blocked or shape(fresh)~=shape(plan) then return nil,"import preview is stale; run preview again" end
  plan=fresh
  local byID={}; for _,room in ipairs(plan.model.rooms) do byID[room.id]=room end
  local actions={}; for _,area in ipairs(plan.areas) do for _,entry in ipairs(area.rooms) do actions[#actions+1]={id=entry.id,action=entry.action} end end
  table.sort(actions,function(a,b) return a.id<b.id end)
  local journal={}
  local function rollback(message)
    local failures={}
    for index=#journal,1,-1 do
      local item=journal[index]; local ok,restoreErr
      if item.before then ok,restoreErr=invoke(backend,"putRoom",copy(item.before)) else ok,restoreErr=invoke(backend,"deleteRoom",item.id) end
      if not ok then failures[#failures+1]=tostring(restoreErr or ("room "..item.id.." rollback failed")) end
    end
    if #failures>0 then message=tostring(message).."; rollback failed: "..table.concat(failures,"; ") end
    return nil,message
  end
  local applied,prepared=0,{}
  for _,entry in ipairs(actions) do if entry.action=="create" or entry.action=="replace" then
    local before,readErr=invoke(backend,"getRoom",entry.id); if readErr then return rollback(readErr) end
    journal[#journal+1]={id=entry.id,before=copy(before)}
    local room=copy(byID[entry.id]); room.owner="DragonsGateHUD"; room.stash_owner=character
    room.derived_from={artifact_id=plan.model.provenance.artifact_id,author=plan.model.provenance.author,publisher=plan.model.provenance.publisher,slug=plan.model.provenance.slug,verified=false}
    room.read_only=false
    prepared[#prepared+1]=room
    local shell=copy(room); shell.exits={}; shell.special_exits={}
    local ok,writeErr=invoke(backend,"putRoom",shell); if not ok then return rollback(writeErr or ("room "..entry.id.." preparation failed")) end
  end end
  -- Link only after every destination room exists. Mudlet rejects exits whose
  -- destination has not yet been created, which otherwise made valid imports
  -- dependent on numeric room ordering.
  for _,room in ipairs(prepared) do
    local ok,writeErr=invoke(backend,"putRoom",room); if not ok then return rollback(writeErr or ("room "..room.id.." import failed")) end
    applied=applied+1
  end
  return {applied=applied,created=plan.creates,replaced=plan.replaces,kept=plan.keeps,skipped=plan.skips,stash_owner=character,derived_from=copy(plan.model.provenance)}
end

return Transfer
