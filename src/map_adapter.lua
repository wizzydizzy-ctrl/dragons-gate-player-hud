local MapAdapter={}
MapAdapter.__index=MapAdapter
local MapperModel=require("mapper_model")
local unpackValues=table.unpack or unpack

local reverse={n="s",ne="sw",e="w",se="nw",s="n",sw="ne",w="e",nw="se",up="down",down="up",["in"]="out",out="in"}
local LEGACY_ROOM_NAME_MIGRATION_KEY="dghud.legacy_room_names_schema"
local LEGACY_ROOM_NAME_MIGRATION_SCHEMA="1"

local function areaName(key)
  local value=tostring(key)
  local destination=value:match("^special:(%d+)$")
  if destination then return "Dragons Gate - Submap "..destination end
  local isolated=value:match("^isolated:(%d+)$")
  if isolated then return "Dragons Gate - Isolated "..isolated end
  return "Dragons Gate - "..value
end

local function missing(name)
  return nil,"Mudlet mapper API "..name.." is unavailable"
end

local function invoke(api,name,...)
  local fn=api[name]
  if type(fn)~="function" then return missing(name) end
  local ok,a,b,c=pcall(fn,...)
  if not ok then return nil,"Mudlet mapper API "..name.." failed: "..tostring(a) end
  if a==nil and b~=nil then return nil,tostring(b) end
  if a==false then return nil,"Mudlet mapper API "..name.." failed" end
  return a,b,c
end

local function read(api,name,...)
  local fn=api[name]
  if type(fn)~="function" then return missing(name) end
  local ok,a,b,c=pcall(fn,...)
  if not ok then return nil,"Mudlet mapper API "..name.." failed: "..tostring(a) end
  if a==nil and b~=nil then return nil,tostring(b) end
  return a,b,c
end

local function optionalRoomUserData(api,roomID,key)
  local value,valueErr=read(api,"getRoomUserData",roomID,key)
  if value==nil and valueErr~=nil then return nil,valueErr end
  if value==nil or tostring(value)=="" then return nil end
  return tostring(value)
end

local function absentUserData(errorMessage)
  local message=tostring(errorMessage or ""):lower()
  return message:find("no user data with key",1,true)~=nil or message:find("user data key does not exist",1,true)~=nil
end

local function positiveInteger(value)
  local number=tonumber(value)
  if not number or number~=number or number==math.huge or number==-math.huge or number<=0 or number%1~=0 then return nil end
  return number
end

local function finiteNumber(value)
  local number=tonumber(value)
  if not number or number~=number or number==math.huge or number==-math.huge then return nil end
  return number
end

local function normalizeCommand(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function splitSorted(value)
  local out,seen={},{}
  for item in tostring(value or ""):gmatch("[^,]+") do local clean=item:match("^%s*(.-)%s*$"); if clean~="" and not seen[clean] then seen[clean]=true; out[#out+1]=clean end end
  table.sort(out); return out
end

local function labelKey(kind,value)
  return "dghud.map_label."..kind.."."..tostring(value):gsub(".",function(c) return string.format("%02x",string.byte(c)) end)
end

local function friendlyLabel(value)
  value=tostring(value or ""):match("^%s*(.-)%s*$")
  if value=="" or #value>100 or value:find("[%z\1-\31\127]") then return nil,"name must be 1-100 plain-text characters" end
  return value
end

local function areaForPartition(self,key,areas)
  local found
  for _,area in pairs(areas) do
    area=positiveInteger(area)
    if area then
      local owner,ownerErr=read(self.api,"getAreaUserData",area,"dghud.owner"); if owner==nil and ownerErr~=nil and not absentUserData(ownerErr) then return nil,ownerErr end
      local partition,partitionErr=read(self.api,"getAreaUserData",area,"dghud.partition"); if partition==nil and partitionErr~=nil and not absentUserData(partitionErr) then return nil,partitionErr end
      if owner==self.owner and tostring(partition or "")==key then if found and found~=area then return nil,"multiple DGHUD mapper areas claim partition "..key end; found=area end
    end
  end
  if found then return found end
  local legacy=positiveInteger(areas[areaName(key)])
  if legacy then
    local owner,ownerErr=read(self.api,"getAreaUserData",legacy,"dghud.owner"); if owner==nil and ownerErr~=nil and not absentUserData(ownerErr) then return nil,ownerErr end
    if owner~=self.owner then return nil,"area "..areaName(key).." is not owned by DragonsGateHUD" end
    local marked,markErr=invoke(self.api,"setAreaUserData",legacy,"dghud.partition",key); if not marked then return nil,markErr end; return legacy
  end
end

local function specialDestination(exits,command)
  for destination,commands in pairs(exits or {}) do
    if type(commands)=="table" and commands[command]~=nil then return destination end
  end
  return nil
end

local function requireCapabilities(api,names)
  for _,name in ipairs(names) do
    if type(api[name])~="function" then return missing(name) end
  end
  return true
end

local function rollbackCreated(api,deleteName,id,originalError)
  local deleted,deleteError=invoke(api,deleteName,id)
  if deleted==nil then
    return nil,tostring(originalError).."; rollback failed: "..tostring(deleteError)
  end
  return nil,originalError
end

function MapAdapter.new(api)
  return setmetatable({api=api or {},owner="DragonsGateHUD",schema="1",areas={},createdAreas={},createdRooms={}},MapAdapter)
end

function MapAdapter:isOwned(id)
  if type(self.api.getRoomUserData)~="function" then return false end
  local owner=read(self.api,"getRoomUserData",id,"dghud.owner")
  return owner==self.owner
end

function MapAdapter:listRooms()
  local rooms,roomsErr=read(self.api,"getRooms"); if rooms==nil then return nil,roomsErr end
  if type(rooms)~="table" then return nil,"Mudlet mapper API getRooms returned invalid data" end
  local ids={}
  for key in pairs(rooms) do
    local id=type(key)=="number" and positiveInteger(key) or nil; if not id then return nil,"Mudlet mapper API getRooms returned invalid data" end
    local owner,ownerErr=read(self.api,"getRoomUserData",id,"dghud.owner"); if owner==nil and ownerErr~=nil and not absentUserData(ownerErr) then return nil,ownerErr end
    if owner==self.owner then ids[#ids+1]=id end
  end
  table.sort(ids); return ids
end

function MapAdapter:mapLabel(kind,key)
  if kind~="area" and kind~="subarea" then return nil,"map label kind is invalid" end
  local all,err=read(self.api,"getAllMapUserData"); if all==nil then return nil,err end
  return tostring(all[labelKey(kind,key)] or "")
end

function MapAdapter:setMapLabel(kind,key,value)
  if kind~="area" and kind~="subarea" then return nil,"map label kind is invalid" end
  local clean,err=friendlyLabel(value); if not clean then return nil,err end
  local ok,writeErr=invoke(self.api,"setMapUserData",labelKey(kind,key),clean); if ok==nil then return nil,writeErr end
  return clean
end

function MapAdapter:restoreMapLabel(kind,key,value)
  if kind~="area" and kind~="subarea" then return nil,"map label kind must be area or subarea" end
  local saved,saveErr=invoke(self.api,"setMapUserData",labelKey(kind,key),tostring(value or ""))
  if not saved then return nil,saveErr end
  return true
end

function MapAdapter:renameNativePartition(partition)
  local key=tostring(partition or ""); local areas,areasErr=read(self.api,"getAreaTable"); if areas==nil then return nil,areasErr end
  local area,findErr=areaForPartition(self,key,areas); if not area then return nil,findErr or "mapper area for this subarea was not found" end
  local record,recordErr=self:areaRecord(area); if not record then return nil,recordErr end; if not record.owned then return nil,"mapper area is not owned by DragonsGateHUD" end
  local rooms,roomsErr=self:roomsInArea(area); if not rooms then return nil,roomsErr end; local gameArea
  for _,roomID in ipairs(rooms) do local room,roomErr=self:roomRecord(roomID); if not room then return nil,roomErr end; if not room.owned or tostring(room.partition or "")~=key then return nil,"mapper area contains rooms from another map partition" end; gameArea=gameArea or tostring(room.game_area or "unknown") end
  local areaLabel=self:mapLabel("area",gameArea or "unknown") or ""; local subLabel=self:mapLabel("subarea",key) or ""; local suffix
  local special=key:match("^special:(%d+)$"); local isolated=key:match("^isolated:(%d+)$")
  if special then suffix=" ["..special.."]" elseif isolated then suffix=" [Isolated "..isolated.."]" else suffix=" [Area "..key.."]" end
  local title=subLabel~="" and ((areaLabel~="" and areaLabel.." - " or "")..subLabel) or (areaLabel~="" and areaLabel or areaName(key):gsub("^Dragons Gate %- ",""))
  local wanted=title..suffix; local collision=positiveInteger(areas[wanted]); if collision and collision~=area then return nil,"another mapper area already uses the name "..wanted end
  local renamed,renameErr=invoke(self.api,"setAreaName",area,wanted); if not renamed then return nil,renameErr end
  self.areas[key]=area; if type(self.api.updateMap)=="function" then invoke(self.api,"updateMap") end; return wanted
end

function MapAdapter:listTransferScopes()
  local ids,err=self:listRooms(); if not ids then return nil,err end
  local areas,partitions,areaSeen,partitionSeen={},{},{},{}
  for _,id in ipairs(ids) do
    local room,roomErr=self:getRoom(id); if not room then return nil,roomErr end
    if not areaSeen[room.area] then areaSeen[room.area]=true; areas[#areas+1]={key=room.area,label=self:mapLabel("area",room.area) or ""} end
    if not partitionSeen[room.partition] then partitionSeen[room.partition]=true; partitions[#partitions+1]={key=room.partition,area=room.area,label=self:mapLabel("subarea",room.partition) or ""} end
  end
  local function order(a,b) return (a.label~="" and a.label or a.key):lower()<(b.label~="" and b.label or b.key):lower() end
  table.sort(areas,order); table.sort(partitions,order)
  return {areas=areas,subareas=partitions}
end

function MapAdapter:currentTransferScope(roomID)
  local room,err=self:getRoom(roomID); if not room then return nil,err or "current room is not managed by DGHUD" end
  return {area=room.area,partition=room.partition,area_name=self:mapLabel("area",room.area) or "",subarea_name=self:mapLabel("subarea",room.partition) or ""}
end

function MapAdapter:getRoom(roomID)
  local id=positiveInteger(roomID); if not id then return nil,"room ID must be a positive integer" end
  local exists,existsErr=read(self.api,"roomExists",id); if exists==nil then return nil,existsErr end; if not exists then return nil end
  local owner,ownerErr=read(self.api,"getRoomUserData",id,"dghud.owner"); if owner==nil and ownerErr~=nil and not absentUserData(ownerErr) then return nil,ownerErr end
  if owner~=self.owner then return {id=id,owner=tostring(owner or "")~="" and tostring(owner) or "personal"} end
  local record,recordErr=self:roomRecord(id); if not record then return nil,recordErr end
  local exits,exitsErr=read(self.api,"getRoomExits",id); if exits==nil then return nil,exitsErr end; if type(exits)~="table" then return nil,"Mudlet mapper API getRoomExits returned invalid data" end
  local special,specialErr=read(self.api,"getSpecialExits",id,true); if special==nil then return nil,specialErr end; if type(special)~="table" then return nil,"Mudlet mapper API getSpecialExits returned invalid data" end
  local ordinary={}; for direction,to in pairs(exits) do if positiveInteger(to) then ordinary[#ordinary+1]={direction=tostring(direction):lower(),to=positiveInteger(to)} end end
  table.sort(ordinary,function(a,b) return a.direction==b.direction and a.to<b.to or a.direction<b.direction end)
  local specialList={}; for destination,commands in pairs(special) do local to=positiveInteger(destination); if not to or type(commands)~="table" then return nil,"Mudlet mapper API getSpecialExits returned invalid data" end; for command in pairs(commands) do specialList[#specialList+1]={command=normalizeCommand(command):lower(),to=to} end end
  table.sort(specialList,function(a,b) return a.command==b.command and a.to<b.to or a.command<b.command end)
  local function metadata(key) local value,valueErr=read(self.api,"getRoomUserData",id,key); if value==nil and valueErr~=nil and not absentUserData(valueErr) then return nil,valueErr end; return tostring(value or "") end
  local roomName,roomNameErr=metadata("dghud.room_name"); if roomName==nil then return nil,roomNameErr end
  local poi,poiErr=metadata("dghud.poi_tags"); if poi==nil then return nil,poiErr end
  local stash,stashErr=metadata("dghud.stash_owner"); if stash==nil then return nil,stashErr end
  local artifact,artifactErr=metadata("dghud.derived_from_artifact"); if artifact==nil then return nil,artifactErr end
  local author,authorErr=metadata("dghud.derived_from_author"); if author==nil then return nil,authorErr end
  local publisher,publisherErr=metadata("dghud.derived_from_publisher"); if publisher==nil then return nil,publisherErr end
  local slug,slugErr=metadata("dghud.derived_from_slug"); if slug==nil then return nil,slugErr end
  return {id=id,owner=self.owner,area=tostring(record.game_area or "unknown"),partition=tostring(record.partition or record.game_area or "unknown"),x=record.coordinates.x,y=record.coordinates.y,z=record.coordinates.z,name=roomName,environment=tostring(record.environment or ""),flags=splitSorted(record.flags),poi=splitSorted(poi),exits=ordinary,special_exits=specialList,stash_owner=stash~="" and stash or nil,derived_from=artifact~="" and {artifact_id=artifact,author=author,publisher=publisher,slug=slug,verified=false} or nil,read_only=record.read_only==true}
end

function MapAdapter:putRoom(room)
  if type(room)~="table" then return nil,"room transfer record is required" end
  local id=positiveInteger(room.id); if not id then return nil,"room ID must be a positive integer" end
  local exists,existsErr=read(self.api,"roomExists",id); if exists==nil then return nil,existsErr end
  if exists then local owner,ownerErr=read(self.api,"getRoomUserData",id,"dghud.owner"); if owner==nil and ownerErr~=nil then return nil,ownerErr end; if owner~=self.owner then return nil,"room "..id.." belongs to another mapper" end end
  local partition=tostring(room.partition or room.area or "unknown"); local area,areaErr=self:ensureArea(partition); if not area then return nil,areaErr end
  if not exists then local added,addErr=invoke(self.api,"addRoom",id); if not added then return nil,addErr end end
  local operations={{"setRoomUserData",id,"dghud.owner",self.owner},{"setRoomUserData",id,"dghud.state","provisional"},{"setRoomUserData",id,"dghud.mapper_schema",self.schema},{"setRoomUserData",id,"dghud.environment",tostring(room.environment or "")},{"setRoomUserData",id,"dghud.flags",table.concat(room.flags or {},",")},{"setRoomUserData",id,"dghud.room_name",tostring(room.name or "")},{"setRoomUserData",id,"dghud.partition",partition},{"setRoomUserData",id,"dghud.game_area",tostring(room.area or "unknown")},{"setRoomUserData",id,"dghud.poi_tags",table.concat(room.poi or {},",")},{"setRoomUserData",id,"dghud.stash_owner",tostring(room.stash_owner or "")},{"setRoomUserData",id,"dghud.derived_from_artifact",tostring(room.derived_from and room.derived_from.artifact_id or "")},{"setRoomUserData",id,"dghud.derived_from_author",tostring(room.derived_from and room.derived_from.author or "")},{"setRoomUserData",id,"dghud.derived_from_publisher",tostring(room.derived_from and room.derived_from.publisher or "")},{"setRoomUserData",id,"dghud.derived_from_slug",tostring(room.derived_from and room.derived_from.slug or "")},{"setRoomUserData",id,"dghud.derived_from_verified","false"},{"setRoomUserData",id,"dghud.library_readonly",room.read_only and "true" or "false"},{"setRoomArea",id,area},{"setRoomCoordinates",id,tonumber(room.x) or 0,tonumber(room.y) or 0,tonumber(room.z) or 0},{"setRoomName",id,""}}
  for _,operation in ipairs(operations) do local ok,operationErr=invoke(self.api,unpackValues(operation)); if not ok then return nil,operationErr end end
  local wanted={}; for _,entry in ipairs(room.exits or {}) do wanted[tostring(entry.direction):lower()]=positiveInteger(entry.to) end
  local current,currentErr=read(self.api,"getRoomExits",id); if current==nil then return nil,currentErr end
  for direction in pairs(current) do if wanted[tostring(direction):lower()]==nil then local removed,removeErr=invoke(self.api,"setExit",id,-1,direction); if not removed then return nil,removeErr end end end
  for direction,to in pairs(wanted) do local linked,linkErr=invoke(self.api,"setExit",id,to,direction); if not linked then return nil,linkErr end end
  local oldSpecial,oldSpecialErr=read(self.api,"getSpecialExits",id,true); if oldSpecial==nil then return nil,oldSpecialErr end
  for _,commands in pairs(oldSpecial) do for command in pairs(commands or {}) do local removed,removeErr=invoke(self.api,"removeSpecialExit",id,command); if not removed then return nil,removeErr end end end
  for _,entry in ipairs(room.special_exits or {}) do local linked,linkErr=invoke(self.api,"addSpecialExit",id,entry.to,entry.command); if not linked then return nil,linkErr end end
  local ready,readyErr=invoke(self.api,"setRoomUserData",id,"dghud.state","ready"); if not ready then return nil,readyErr end
  return true
end

function MapAdapter:deleteTransferRoom(roomID)
  local id=positiveInteger(roomID); if not id then return nil,"room ID must be a positive integer" end
  local exists,existsErr=read(self.api,"roomExists",id); if exists==nil then return nil,existsErr end; if not exists then return true end
  local owner,ownerErr=read(self.api,"getRoomUserData",id,"dghud.owner"); if owner==nil and ownerErr~=nil then return nil,ownerErr end
  if owner~=self.owner then return nil,"room "..id.." belongs to another mapper" end
  return invoke(self.api,"deleteRoom",id)
end

function MapAdapter:deleteRoom(roomID) return self:deleteTransferRoom(roomID) end

function MapAdapter:clearOwnedRoomNames()
  local rooms,roomsErr=read(self.api,"getRooms")
  if rooms==nil then return nil,roomsErr end
  if type(rooms)~="table" then return nil,"Mudlet mapper API getRooms returned invalid data" end
  local ids={}
  for key in pairs(rooms) do
    local id=type(key)=="number" and positiveInteger(key) or nil
    if not id then return nil,"Mudlet mapper API getRooms returned invalid data" end
    ids[id]=true
  end
  local changed=0
  for id in pairs(ids) do
    local owner,ownerErr=read(self.api,"getRoomUserData",id,"dghud.owner")
    if owner==nil and ownerErr~=nil then return nil,ownerErr end
    if owner==self.owner then
      local ok,err=invoke(self.api,"setRoomName",id,"")
      if ok==nil then return nil,err end
      changed=changed+1
    end
  end
  return changed
end

function MapAdapter:migrateLegacyRoomNames()
  local ready,readyErr=requireCapabilities(self.api,{"getAllMapUserData","setMapUserData"})
  if not ready then return nil,readyErr end
  local metadata,metadataErr=read(self.api,"getAllMapUserData")
  if metadata==nil then return nil,metadataErr end
  if type(metadata)~="table" then return nil,"Mudlet mapper API getAllMapUserData returned invalid data" end
  if tostring(metadata[LEGACY_ROOM_NAME_MIGRATION_KEY] or "")==LEGACY_ROOM_NAME_MIGRATION_SCHEMA then return 0,false end
  local changed,cleanupErr=self:clearOwnedRoomNames()
  if changed==nil then return nil,cleanupErr end
  local marked,markErr=invoke(self.api,"setMapUserData",LEGACY_ROOM_NAME_MIGRATION_KEY,LEGACY_ROOM_NAME_MIGRATION_SCHEMA)
  if marked==nil then return nil,markErr end
  return changed,true
end

function MapAdapter:ensureArea(areaKey)
  local key=tostring(areaKey or "unknown")
  local name=areaName(key)
  local areas,areasErr=read(self.api,"getAreaTable")
  if areas==nil then return nil,areasErr end
  local cached=self.areas[key]
  if cached~=nil then
    local cachedExists=false
    for _,areaID in pairs(areas) do if positiveInteger(areaID)==positiveInteger(cached) then cachedExists=true; break end end
    if cachedExists then
      local owner,ownerErr=read(self.api,"getAreaUserData",cached,"dghud.owner")
      if owner==nil and ownerErr~=nil and not absentUserData(ownerErr) then return nil,ownerErr end
      local partition,partitionErr=read(self.api,"getAreaUserData",cached,"dghud.partition")
      if partition==nil and partitionErr~=nil and not absentUserData(partitionErr) then return nil,partitionErr end
      if owner==self.owner and tostring(partition or "")==key then return cached end
      return nil,"area "..name.." is not owned by DragonsGateHUD"
    end
    self.areas[key]=nil; self.createdAreas[cached]=nil
  end
  local area,findErr=areaForPartition(self,key,areas)
  if not area and findErr then return nil,findErr end
  local createdThisCall=false
  if area~=nil then
    local owner,ownerErr=read(self.api,"getAreaUserData",area,"dghud.owner")
    if ownerErr then return nil,ownerErr end
    if owner~=self.owner and self.createdAreas[area]~=true then return nil,"area "..name.." is not owned by DragonsGateHUD" end
  else
    local addErr
    area,addErr=invoke(self.api,"addAreaName",name)
    if area==nil then return nil,addErr end
    createdThisCall=true
    self.createdAreas[area]=true
  end
  local areaOperations={{"setAreaUserData",area,"dghud.owner",self.owner},{"setAreaUserData",area,"dghud.partition",key},{"setAreaUserData",area,"dghud.state","provisional"},{"setAreaUserData",area,"dghud.mapper_schema",self.schema}}
  for index,operation in ipairs(areaOperations) do
    local ok,err=invoke(self.api,unpackValues(operation))
    if ok==nil then
      if createdThisCall and index==1 then
        local _,rollbackError=rollbackCreated(self.api,"deleteArea",area,err)
        self.createdAreas[area]=nil
        return nil,rollbackError
      end
      return nil,err
    end
  end
  local readyOk,readyErr=invoke(self.api,"setAreaUserData",area,"dghud.state","ready"); if readyOk==nil then return nil,readyErr end
  self.createdAreas[area]=nil
  self.areas[key]=area
  return area
end

function MapAdapter:areaDeletionSafe(areaID)
  local area=positiveInteger(areaID)
  if not area then return nil,"mapper area ID must be a positive integer" end
  local labels,labelsErr=read(self.api,"getMapLabels",area)
  if labels==nil then return nil,labelsErr or "map label ownership cannot be verified" end
  if type(labels)~="table" then return nil,"Mudlet mapper API getMapLabels returned invalid data" end
  if next(labels)~=nil then return nil,"mapper area "..tostring(area).." contains labels not demonstrably owned by DragonsGateHUD" end
  return true
end

function MapAdapter:roomRecord(roomID)
  local ready,readyErr=requireCapabilities(self.api,{"roomExists","getRoomUserData","getRoomArea","getRoomCoordinates"})
  if not ready then return nil,readyErr end
  local exists,existsErr=read(self.api,"roomExists",roomID)
  if exists==nil then return nil,existsErr or "Mudlet mapper API roomExists failed" end
  local record={exists=not not exists,owned=false,placement_needed=not exists}
  if not exists then return record end
  local owner,ownerErr=read(self.api,"getRoomUserData",roomID,"dghud.owner")
  if owner==nil and ownerErr~=nil then return nil,ownerErr end
  record.owned=owner==self.owner
  local state,stateErr=optionalRoomUserData(self.api,roomID,"dghud.state")
  if stateErr then return nil,stateErr end
  record.state=state
  local mapperSchema,schemaErr=optionalRoomUserData(self.api,roomID,"dghud.mapper_schema")
  if schemaErr then return nil,schemaErr end
  record.mapper_schema=mapperSchema
  local environment,environmentErr=optionalRoomUserData(self.api,roomID,"dghud.environment")
  if environmentErr then return nil,environmentErr end
  record.environment=environment
  local flags,flagsErr=optionalRoomUserData(self.api,roomID,"dghud.flags")
  if flagsErr then return nil,flagsErr end
  record.flags=flags
  local partition,partitionErr=optionalRoomUserData(self.api,roomID,"dghud.partition")
  if partitionErr then return nil,partitionErr end
  record.partition=partition
  local gameArea,gameAreaErr=optionalRoomUserData(self.api,roomID,"dghud.game_area")
  if gameAreaErr then return nil,gameAreaErr end
  record.game_area=gameArea
  local area,areaErr=read(self.api,"getRoomArea",roomID)
  if area==nil and areaErr~=nil then return nil,areaErr end
  record.area=area
  local x,y,z=read(self.api,"getRoomCoordinates",roomID)
  if x==nil and y~=nil then return nil,y end
  if x~=nil then record.coordinates={x=x,y=y,z=z} end
  local ownerOnlyInterrupted=record.owned and record.state==nil and record.mapper_schema==nil and record.environment==nil and record.flags==nil and record.partition==nil and record.game_area==nil
  record.placement_needed=self.createdRooms[roomID]==true or (record.owned and record.state=="provisional") or ownerOnlyInterrupted
  return record
end

function MapAdapter:areaRecord(areaID)
  local area=positiveInteger(areaID)
  if not area then return nil,"mapper area ID must be a positive integer" end
  local areas,areasErr=read(self.api,"getAreaTable")
  if areas==nil then return nil,areasErr or "Mudlet mapper API getAreaTable failed" end
  if type(areas)~="table" then return nil,"Mudlet mapper API getAreaTable returned invalid data" end
  local exists=false
  for _,id in pairs(areas) do if positiveInteger(id)==area then exists=true; break end end
  if not exists then return nil,"mapper area "..tostring(area).." does not exist" end
  local owner,ownerErr=read(self.api,"getAreaUserData",area,"dghud.owner")
  if owner==nil and ownerErr~=nil and not absentUserData(ownerErr) then return nil,ownerErr end
  if owner==nil then
    local legacyName=false
    for name,id in pairs(areas) do if positiveInteger(id)==area and tostring(name):match("^Dragons Gate %-") then legacyName=true; break end end
    if legacyName then
      local rooms,roomsErr=self:roomsInArea(area); if rooms==nil then return nil,roomsErr end
      local allOwned=#rooms>0
      for _,roomID in ipairs(rooms) do local room,roomErr=self:roomRecord(roomID); if room==nil then return nil,roomErr end; if not room.owned then allOwned=false; break end end
      if allOwned then owner=self.owner end
    end
  end
  return {id=area,exists=true,owned=owner==self.owner,owner=owner}
end

function MapAdapter:roomsInArea(areaID)
  local area=positiveInteger(areaID)
  if not area then return nil,"mapper area ID must be a positive integer" end
  local rooms,roomsErr=read(self.api,"getAreaRooms1",area)
  if rooms==nil then return nil,roomsErr or "Mudlet mapper API getAreaRooms1 failed" end
  if type(rooms)~="table" then return nil,"Mudlet mapper API getAreaRooms1 returned invalid data" end
  local unique={}; local count=0; local minimum; local maximum
  for index,value in pairs(rooms) do
    local room=type(value)=="number" and positiveInteger(value) or nil
    if type(index)~="number" or index%1~=0 or index<0 or not room then
      return nil,"Mudlet mapper API getAreaRooms1 returned invalid data"
    end
    count=count+1; minimum=minimum and math.min(minimum,index) or index; maximum=maximum and math.max(maximum,index) or index
    unique[room]=true
  end
  if count>0 and (minimum>1 or count~=maximum-minimum+1) then return nil,"Mudlet mapper API getAreaRooms1 returned invalid data" end
  local normalized={}
  for room in pairs(unique) do normalized[#normalized+1]=room end
  table.sort(normalized)
  return normalized
end

function MapAdapter:beginAreaRoomScan(areaIDs)
  if type(areaIDs)~="table" then return nil,"mapper area IDs must be a table" end
  local normalized={}
  for index,value in ipairs(areaIDs) do
    local area=positiveInteger(value); if not area then return nil,"mapper area ID must be a positive integer" end
    normalized[index]=area
  end
  return {area_ids=normalized,area_index=1,current=nil}
end

function MapAdapter:scanAreaRoomBatch(scan,limit)
  if type(scan)~="table" or type(scan.area_ids)~="table" then return nil,nil,"invalid mapper area scan" end
  local maximum=positiveInteger(limit); if not maximum then return nil,nil,"mapper scan limit must be a positive integer" end
  local found={}
  while #found<maximum do
    local area=scan.area_ids[scan.area_index]
    if not area then return found,true end
    if not scan.current then
      local rooms,err=read(self.api,"getAreaRooms1",area)
      if rooms==nil then return nil,nil,err or "Mudlet mapper API getAreaRooms1 failed" end
      if type(rooms)~="table" then return nil,nil,"Mudlet mapper API getAreaRooms1 returned invalid data" end
      scan.current={rooms=rooms,key=nil,count=0,minimum=nil,maximum=nil,area=area}
    end
    local current=scan.current
    local key,value=next(current.rooms,current.key); current.key=key
    if key==nil then
      if current.count>0 and (current.minimum>1 or current.count~=current.maximum-current.minimum+1) then return nil,nil,"Mudlet mapper API getAreaRooms1 returned invalid data" end
      scan.current=nil; scan.area_index=scan.area_index+1
    else
      local room=type(value)=="number" and positiveInteger(value) or nil
      if type(key)~="number" or key%1~=0 or key<0 or not room then return nil,nil,"Mudlet mapper API getAreaRooms1 returned invalid data" end
      current.count=current.count+1; current.minimum=current.minimum and math.min(current.minimum,key) or key; current.maximum=current.maximum and math.max(current.maximum,key) or key
      found[#found+1]={id=room,area=area}
    end
  end
  return found,false
end

function MapAdapter:beginInboundScan()
  local rooms,err=read(self.api,"getRooms")
  if rooms==nil then return nil,err or "Mudlet mapper API getRooms failed" end
  if type(rooms)~="table" then return nil,"Mudlet mapper API getRooms returned invalid data" end
  return {rooms=rooms,key=nil}
end

function MapAdapter:scanInboundBatch(scan,deleting,limit)
  if type(scan)~="table" or type(scan.rooms)~="table" or type(deleting)~="table" then return nil,nil,"invalid inbound mapper scan" end
  local maximum=positiveInteger(limit); if not maximum then return nil,nil,"mapper scan limit must be a positive integer" end
  local inspected=0; local sources={}
  while inspected<maximum do
    local key,name=next(scan.rooms,scan.key); scan.key=key
    if key==nil then return sources,true end
    local source=type(key)=="number" and positiveInteger(key) or nil
    if not source or type(name)~="string" then return nil,nil,"Mudlet mapper API getRooms returned invalid data" end
    inspected=inspected+1
    if not deleting[source] then
      local ordinary,ordinaryErr=read(self.api,"getRoomExits",source)
      if ordinary==nil then return nil,nil,ordinaryErr or "Mudlet mapper API getRoomExits failed" end
      if type(ordinary)~="table" then return nil,nil,"Mudlet mapper API getRoomExits returned invalid data" end
      local special,specialErr=read(self.api,"getSpecialExits",source,true)
      if special==nil then return nil,nil,specialErr or "Mudlet mapper API getSpecialExits failed" end
      if type(special)~="table" then return nil,nil,"Mudlet mapper API getSpecialExits returned invalid data" end
      local inbound=false
      for _,destination in pairs(ordinary) do if deleting[positiveInteger(destination)] then inbound=true; break end end
      if not inbound then for destination in pairs(special) do if deleting[positiveInteger(destination)] then inbound=true; break end end end
      if inbound then
        local record,recordErr=self:roomRecord(source); if not record then return nil,nil,recordErr end
        if not record.exists or not record.owned then return nil,nil,"unowned room "..tostring(source).." has an inbound exit" end
        sources[#sources+1]=source
      end
    end
  end
  return sources,false
end

function MapAdapter:inboundSources(roomIDs)
  if type(roomIDs)~="table" then return nil,"room IDs must be a table" end
  local deleting={}
  for _,value in pairs(roomIDs) do
    local room=positiveInteger(value)
    if room then deleting[room]=true end
  end
  local rooms,roomsErr=read(self.api,"getRooms")
  if rooms==nil then return nil,roomsErr or "Mudlet mapper API getRooms failed" end
  if type(rooms)~="table" then return nil,"Mudlet mapper API getRooms returned invalid data" end
  local existing={}
  for roomID,roomName in pairs(rooms) do
    local source=type(roomID)=="number" and positiveInteger(roomID) or nil
    if not source or type(roomName)~="string" then return nil,"Mudlet mapper API getRooms returned invalid data" end
    existing[source]=true
  end
  local inbound={}
  for source in pairs(existing) do
    local ordinary,ordinaryErr=read(self.api,"getRoomExits",source)
    if ordinary==nil then return nil,ordinaryErr or "Mudlet mapper API getRoomExits failed" end
    if type(ordinary)~="table" then return nil,"Mudlet mapper API getRoomExits returned invalid data" end
    local special,specialErr=read(self.api,"getSpecialExits",source,true)
    if special==nil then return nil,specialErr or "Mudlet mapper API getSpecialExits failed" end
    if type(special)~="table" then return nil,"Mudlet mapper API getSpecialExits returned invalid data" end
    if not deleting[source] then
      for _,destination in pairs(ordinary) do
        if deleting[positiveInteger(destination)] then inbound[source]=true; break end
      end
      if not inbound[source] then
        for destination in pairs(special) do
          if deleting[positiveInteger(destination)] then inbound[source]=true; break end
        end
      end
    end
  end
  local sources={}
  for source in pairs(inbound) do sources[#sources+1]=source end
  table.sort(sources)
  return sources
end

function MapAdapter:deleteOwnedRoom(roomID)
  local room=positiveInteger(roomID)
  if not room then return nil,"room ID must be a positive integer" end
  local record,recordErr=self:roomRecord(room)
  if record==nil then return nil,recordErr end
  if not record.exists then return nil,"room "..tostring(room).." does not exist" end
  if not record.owned then return nil,"room "..tostring(room).." is not owned by DragonsGateHUD" end
  local deleted,deleteErr=invoke(self.api,"deleteRoom",room)
  if deleted==nil then return nil,deleteErr end
  return true
end

function MapAdapter:deleteEmptyOwnedArea(areaID)
  local record,recordErr=self:areaRecord(areaID)
  if record==nil then return nil,recordErr end
  if not record.owned then return nil,"mapper area "..tostring(record.id).." is not owned by DragonsGateHUD" end
  local safe,safeErr=self:areaDeletionSafe(record.id); if not safe then return nil,safeErr end
  local rooms,roomsErr=self:roomsInArea(record.id)
  if rooms==nil then return nil,roomsErr end
  if #rooms>0 then return nil,"mapper area "..tostring(record.id).." is not empty" end
  local deleted,deleteErr=invoke(self.api,"deleteArea",record.id)
  if deleted==nil then return nil,deleteErr end
  return true
end

function MapAdapter:invalidateDeleted(roomIDs,areaID)
  for _,roomID in pairs(roomIDs or {}) do
    local room=positiveInteger(roomID)
    if room then self.createdRooms[room]=nil end
  end
  local area=positiveInteger(areaID)
  if area then
    self.createdAreas[area]=nil
    for key,cachedArea in pairs(self.areas) do if cachedArea==area then self.areas[key]=nil end end
  end
  return true
end

local function partitionForArea(self,area)
  if area==nil then return nil,"map area is unavailable" end
  local stored,storedErr=read(self.api,"getAreaUserData",area,"dghud.partition")
  if stored==nil and storedErr~=nil and not absentUserData(storedErr) then return nil,storedErr end
  if stored~=nil and tostring(stored)~="" then return tostring(stored) end
  local areas,areasErr=read(self.api,"getAreaTable")
  if areas==nil then return nil,areasErr end
  local partition
  for name,id in pairs(areas) do
    if id==area then
      local areaNameValue=tostring(name)
      local destination=areaNameValue:match("^Dragons Gate %- Submap (%d+)$")
      local isolated=areaNameValue:match("^Dragons Gate %- Isolated (%d+)$")
      partition=destination and ("special:"..destination) or isolated and ("isolated:"..isolated) or areaNameValue:match("^Dragons Gate %- (.+)$")
      if partition then
        local owner=read(self.api,"getAreaUserData",area,"dghud.owner")
        if owner==self.owner then invoke(self.api,"setAreaUserData",area,"dghud.partition",partition) end
        break
      end
    end
  end
  partition=partition or ("area:"..tostring(area))
  return partition
end

function MapAdapter:effectivePartition(roomID)
  local record,recordErr=self:roomRecord(roomID)
  if record==nil then return nil,recordErr end
  if not record.exists then return nil,"room "..tostring(roomID).." does not exist" end
  if not record.owned then return nil,"room "..tostring(roomID).." is not owned by DragonsGateHUD" end
  if record.partition then return record.partition end
  return partitionForArea(self,record.area)
end

function MapAdapter:ensureRoom(room,coordinates,partitionKey)
  if type(room)~="table" or room.id==nil then return nil,"room ID is required" end
  coordinates=coordinates or {}
  local ready,readyErr=requireCapabilities(self.api,{"roomExists","addRoom","deleteRoom","getAreaTable","addAreaName","deleteArea","setAreaUserData","getAreaUserData","setRoomArea","setRoomName","setRoomCoordinates","setRoomUserData","getRoomUserData","getRoomArea","getRoomCoordinates"})
  if not ready then return nil,readyErr end
  local record,recordErr=self:roomRecord(room.id)
  if record==nil then return nil,recordErr end
  local exists=record.exists
  if exists and not record.owned and self.createdRooms[room.id]~=true then
    return nil,"room "..tostring(room.id).." is not owned by DragonsGateHUD"
  end
  local continuingCreation=exists and record.placement_needed
  local needsPlacement=not exists or continuingCreation
  local effectiveKey
  if needsPlacement then
    effectiveKey=record.partition or tostring(partitionKey or room.area_key or "unknown")
  else
    effectiveKey=record.partition
    if not effectiveKey then
      effectiveKey,recordErr=partitionForArea(self,record.area)
      if effectiveKey==nil then return nil,recordErr end
    end
  end
  local area=record.area
  if needsPlacement then
    local areaErr
    area,areaErr=self:ensureArea(effectiveKey)
    if area==nil then return nil,areaErr end
  end
  local createdThisCall=false
  if not exists then
    local added,addErr=invoke(self.api,"addRoom",room.id)
    if added==nil then return nil,addErr end
    createdThisCall=true
    self.createdRooms[room.id]=true
  end
  if needsPlacement then
    local ownerOk,ownerErr=invoke(self.api,"setRoomUserData",room.id,"dghud.owner",self.owner)
    if ownerOk==nil then
      if createdThisCall then
        local _,rollbackError=rollbackCreated(self.api,"deleteRoom",room.id,ownerErr)
        self.createdRooms[room.id]=nil
        return nil,rollbackError
      end
      return nil,ownerErr
    end
    local provisionalOk,provisionalErr=invoke(self.api,"setRoomUserData",room.id,"dghud.state","provisional"); if provisionalOk==nil then return nil,provisionalErr end
  end
  local operations={
    {"setRoomUserData",room.id,"dghud.mapper_schema",self.schema},
    {"setRoomUserData",room.id,"dghud.environment",tostring(room.environment or "")},
    {"setRoomUserData",room.id,"dghud.flags",table.concat(room.flags or {},",")},
    {"setRoomUserData",room.id,"dghud.room_name",tostring(room.name or ("Room "..tostring(room.id)))},
    {"setRoomName",room.id,""},
  }
  if not record.partition then operations[#operations+1]={"setRoomUserData",room.id,"dghud.partition",effectiveKey} end
  if record.game_area==nil then operations[#operations+1]={"setRoomUserData",room.id,"dghud.game_area",tostring(room.area_key)} end
  if needsPlacement then
    operations[#operations+1]={"setRoomArea",room.id,area}
    operations[#operations+1]={"setRoomCoordinates",room.id,tonumber(coordinates.x) or 0,tonumber(coordinates.y) or 0,tonumber(coordinates.z) or 0}
  end
  for _,operation in ipairs(operations) do
    local ok,err=invoke(self.api,unpackValues(operation))
    if ok==nil then return nil,err end
  end
  local readyOk,readyErr=invoke(self.api,"setRoomUserData",room.id,"dghud.state","ready"); if readyOk==nil then return nil,readyErr end
  self.createdRooms[room.id]=nil
  return true
end

function MapAdapter:ensureStub(roomID,direction)
  if not self:isOwned(roomID) then return nil,"room "..tostring(roomID).." is not owned by DragonsGateHUD" end
  local ok,err=invoke(self.api,"setExitStub",roomID,direction,true)
  if ok==nil then return nil,err end
  return true
end

function MapAdapter:connect(fromID,toID,direction,confirmedReverse)
  if not self:isOwned(fromID) then return nil,"room "..tostring(fromID).." is not owned by DragonsGateHUD" end
  if not self:isOwned(toID) then return nil,"room "..tostring(toID).." is not owned by DragonsGateHUD" end
  if type(self.api.setExit)~="function" then return missing("setExit") end
  local backwards=reverse[direction]
  if confirmedReverse and not backwards then return nil,"unsupported map direction "..tostring(direction) end
  local ok,err=invoke(self.api,"setExit",fromID,toID,direction)
  if ok==nil then return nil,err end
  if confirmedReverse then
    local reverseOk,reverseErr=invoke(self.api,"setExit",toID,fromID,backwards)
    if reverseOk==nil then return nil,reverseErr end
  end
  return true
end

function MapAdapter:specialExitMatches(fromID,toID,command)
  local from=positiveInteger(fromID); local to=positiveInteger(toID)
  if not from or not to then return nil,"special exit endpoints require positive numeric IDs" end
  local normalized=normalizeCommand(command)
  if normalized=="" then return nil,"special exit command is required" end
  local exits,exitsErr=read(self.api,"getSpecialExits",from,true)
  if exits==nil then return nil,exitsErr end
  local destination=specialDestination(exits,normalized)
  return positiveInteger(destination)==to
end

function MapAdapter:validateRouteStep(fromID,toID,command)
  local from=positiveInteger(fromID); local to=positiveInteger(toID)
  if not from or not to then return nil,"route endpoints require positive numeric IDs" end
  if not self:isOwned(from) or not self:isOwned(to) then return nil,"route endpoints are not owned by DragonsGateHUD" end
  local direction=MapperModel.direction(command)
  if direction then
    local exits,exitsErr=read(self.api,"getRoomExits",from)
    if exits==nil then return nil,exitsErr end
    if type(exits)~="table" then return nil,"Mudlet mapper API getRoomExits returned invalid data" end
    if positiveInteger(exits[direction])==to then return true,direction end
    return nil,"standard exit is not persisted from "..tostring(from).." to "..tostring(to)
  end
  local normalized=normalizeCommand(command)
  if self:specialExitMatches(from,to,normalized) then return true,normalized end
  return nil,"special exit is not confirmed from "..tostring(from).." to "..tostring(to)
end

function MapAdapter:defer(callback)
  if type(callback)~="function" then return nil,"deferred callback is required" end
  return invoke(self.api,"tempTimer",0,callback)
end

function MapAdapter:connectSpecial(fromID,toID,command)
  local from=positiveInteger(fromID); local to=positiveInteger(toID)
  if not from or not to then return nil,"special exit endpoints require positive numeric IDs" end
  local normalized=normalizeCommand(command)
  if normalized=="" then return nil,"special exit command is required" end
  if not self:isOwned(from) or not self:isOwned(to) then return nil,"special exit endpoints are not owned by DragonsGateHUD" end
  local exits,exitsErr=read(self.api,"getSpecialExits",from,true)
  if exits==nil then return nil,exitsErr end
  local destination=specialDestination(exits,normalized)
  if destination~=nil then
    if positiveInteger(destination)==to then return true end
    return nil,"special exit command already has a different destination"
  end
  local added,addErr=invoke(self.api,"addSpecialExit",from,to,normalized)
  if added==nil then return nil,addErr end
  return true
end

function MapAdapter:setCurrent(roomID)
  if not self:isOwned(roomID) then return nil,"room "..tostring(roomID).." is not owned by DragonsGateHUD" end
  local ok,err=invoke(self.api,"centerview",roomID)
  if ok==nil then return nil,err end
  return true
end

function MapAdapter:coordinates(roomID)
  local x,y,z=invoke(self.api,"getRoomCoordinates",roomID)
  if x==nil then return nil,y end
  return {x=x,y=y,z=z}
end

function MapAdapter:roomsAt(areaKey,x,y,z)
  local area,areaErr=self:ensureArea(areaKey)
  if area==nil then return nil,areaErr end
  local rooms,err=invoke(self.api,"getRoomsByPosition",area,x,y,z)
  if rooms==nil then return nil,err end
  return rooms
end

local function coordinateKey(x,y,z)
  return tostring(x)..","..tostring(y)..","..tostring(z)
end

function MapAdapter:reserveDirectionalCoordinate(areaKey,desired,direction,protectedRoomID)
  local vector=MapperModel.destination({x=0,y=0,z=0},direction)
  if not vector or vector.x==0 and vector.y==0 and vector.z==0 then return nil,"direction cannot expand mapper coordinates" end
  local ready,readyErr=requireCapabilities(self.api,{"getAreaRooms1","getRoomUserData","getRoomCoordinates","setRoomCoordinates"})
  if not ready then return nil,readyErr end
  local area,areaErr=self:ensureArea(areaKey); if area==nil then return nil,areaErr end
  local roomIDs,roomsErr=self:roomsInArea(area); if roomIDs==nil then return nil,roomsErr end
  local records,occupied={},{}
  local blocked=false
  for _,roomID in ipairs(roomIDs) do
    local owner,ownerErr=read(self.api,"getRoomUserData",roomID,"dghud.owner")
    if owner==nil and ownerErr~=nil then return nil,ownerErr end
    local x,y,z=invoke(self.api,"getRoomCoordinates",roomID); if x==nil then return nil,y end
    local record={id=roomID,x=x,y=y,z=z,owned=owner==self.owner}; records[#records+1]=record
    occupied[coordinateKey(x,y,z)]=record
    if x==desired.x and y==desired.y and z==desired.z then blocked=true end
  end
  if not blocked then return {x=desired.x,y=desired.y,z=desired.z} end
  local function outward(record)
    local xOut=vector.x<0 and record.x<=desired.x or vector.x>0 and record.x>=desired.x or false
    local yOut=vector.y<0 and record.y<=desired.y or vector.y>0 and record.y>=desired.y or false
    local zOut=vector.z<0 and record.z<=desired.z or vector.z>0 and record.z>=desired.z or false
    return xOut or yOut or zOut
  end
  local moving={}
  for _,record in ipairs(records) do
    if outward(record) then
      if record.id==tonumber(protectedRoomID) then return nil,"mapper expansion would move its origin room" end
      if not record.owned then return nil,"mapper expansion encountered unowned room "..tostring(record.id) end
      moving[record.id]=record
    end
  end
  for _,record in pairs(moving) do
    local targetKey=coordinateKey(record.x+vector.x,record.y+vector.y,record.z+vector.z)
    local collision=occupied[targetKey]
    if collision and not moving[collision.id] then return nil,"mapper expansion would overlap room "..tostring(collision.id) end
  end
  local ordered={}; for _,record in pairs(moving) do ordered[#ordered+1]=record end
  table.sort(ordered,function(a,b)
    local aProjection=a.x*vector.x+a.y*vector.y+a.z*vector.z
    local bProjection=b.x*vector.x+b.y*vector.y+b.z*vector.z
    if aProjection~=bProjection then return aProjection>bProjection end
    return a.id<b.id
  end)
  local moved={}
  for _,record in ipairs(ordered) do
    local ok,err=invoke(self.api,"setRoomCoordinates",record.id,record.x+vector.x,record.y+vector.y,record.z+vector.z)
    if ok==nil then
      local rollbackError
      for index=#moved,1,-1 do
        local prior=moved[index]
        local restored,restoreErr=invoke(self.api,"setRoomCoordinates",prior.id,prior.x,prior.y,prior.z)
        if restored==nil and not rollbackError then rollbackError=restoreErr end
      end
      if rollbackError then return nil,tostring(err).."; coordinate rollback failed: "..tostring(rollbackError) end
      return nil,err
    end
    moved[#moved+1]=record
  end
  return {x=desired.x,y=desired.y,z=desired.z},#moved
end

function MapAdapter:route(fromID,toID)
  local route,err=invoke(self.api,"getPath",fromID,toID)
  if route==nil then return nil,err end
  return route
end

function MapAdapter:center(roomID)
  local ready,readyErr=requireCapabilities(self.api,{"centerview","updateMap"})
  if not ready then return nil,readyErr end
  local centered,centerErr=invoke(self.api,"centerview",roomID)
  if centered==nil then return nil,centerErr end
  local refreshed,refreshErr=invoke(self.api,"updateMap")
  if refreshed==nil then return nil,refreshErr end
  return true
end

function MapAdapter:currentZoom(roomID)
  local room=positiveInteger(roomID)
  if not room then return nil,"room ID must be a positive integer" end
  local ready,readyErr=requireCapabilities(self.api,{"getRoomUserData","getRoomArea","getAreaUserData","getMapZoom"})
  if not ready then return nil,readyErr end
  local owner,ownerErr=read(self.api,"getRoomUserData",room,"dghud.owner")
  if owner==nil and ownerErr~=nil then return nil,ownerErr end
  if owner~=self.owner then return nil,"room "..tostring(room).." is not owned by DragonsGateHUD" end
  local area,areaErr=read(self.api,"getRoomArea",room)
  if area==nil then return nil,areaErr or ("room "..tostring(room).." has no mapper area") end
  local areaOwner,areaOwnerErr=read(self.api,"getAreaUserData",area,"dghud.owner")
  if areaOwner==nil and areaOwnerErr~=nil then return nil,areaOwnerErr end
  if areaOwner~=self.owner then return nil,"mapper area "..tostring(area).." is not owned by DragonsGateHUD" end
  local zoom,zoomErr=read(self.api,"getMapZoom",area)
  if zoom==nil then return nil,zoomErr or ("mapper area "..tostring(area).." has no zoom value") end
  return zoom,area
end

function MapAdapter:zoom(roomID,visualDirection,step,minimum,maximum)
  if visualDirection~="larger" and visualDirection~="smaller" then return nil,"map zoom direction must be larger or smaller" end
  local amount=finiteNumber(step); local lower=finiteNumber(minimum); local upper=finiteNumber(maximum)
  if not amount or amount<=0 then return nil,"map zoom step must be positive" end
  if not lower or not upper then return nil,"map zoom bounds are invalid" end
  lower=math.max(3.0,lower)
  if lower>upper then return nil,"map zoom bounds are invalid" end
  local current,area=self:currentZoom(roomID)
  if current==nil then return nil,area end
  current=finiteNumber(current)
  if not current then return nil,"current map zoom is invalid" end
  local applied=visualDirection=="larger" and current-amount or current+amount
  applied=math.max(lower,math.min(upper,applied))
  local setOk,setErr=invoke(self.api,"setMapZoom",applied,area)
  if setOk==nil then return nil,setErr end
  local refreshOk,refreshErr=invoke(self.api,"updateMap")
  if refreshOk==nil then
    local rollbackOk,rollbackErr=invoke(self.api,"setMapZoom",current,area)
    if rollbackOk==nil then return nil,tostring(refreshErr).."; zoom rollback failed: "..tostring(rollbackErr) end
    return nil,refreshErr
  end
  return applied
end

function MapAdapter.mudletApi(globals)
  globals=globals or _G
  local api={}
  local names={"addRoom","deleteRoom","addAreaName","deleteArea","setAreaName","getAreaTable","getAreaRooms1","getMapLabels","setAreaUserData","getAreaUserData","setRoomArea","getRoomArea","setRoomName","setRoomCoordinates","setRoomUserData","getRoomUserData","setExitStub","setExit","getRoomExits","addSpecialExit","removeSpecialExit","getSpecialExits","getRoomCoordinates","getRooms","getRoomsByPosition","getAllMapUserData","setMapUserData","getMapZoom","setMapZoom","setRoomIDbyHash","centerview","updateMap","tempTimer"}
  local function wrapper(name)
    return function(...)
      local fn=globals[name]
      if type(fn)~="function" then return missing(name) end
      local ok,a,b,c=pcall(fn,...)
      if not ok then return nil,"Mudlet mapper API "..name.." failed: "..tostring(a) end
      if a==nil and b==nil then return true end
      return a,b,c
    end
  end
  local mutations={addRoom=true,deleteRoom=true,addAreaName=true,deleteArea=true,setAreaName=true,setAreaUserData=true,setRoomArea=true,setRoomName=true,setRoomCoordinates=true,setRoomUserData=true,setExitStub=true,setExit=true,addSpecialExit=true,removeSpecialExit=true,setMapUserData=true,setMapZoom=true,setRoomIDbyHash=true,centerview=true,updateMap=true,tempTimer=true}
  for _,name in ipairs(names) do
    if mutations[name] then
      api[name]=wrapper(name)
    else
      api[name]=function(...)
        local fn=globals[name]
        if type(fn)~="function" then return missing(name) end
        local ok,a,b,c=pcall(fn,...)
        if not ok then return nil,"Mudlet mapper API "..name.." failed: "..tostring(a) end
        return a,b,c
      end
    end
  end
  api.getPath=function(fromID,toID)
    local fn=globals.getPath
    if type(fn)~="function" then return missing("getPath") end
    local ok,found=pcall(fn,fromID,toID)
    if not ok then return nil,"Mudlet mapper API getPath failed: "..tostring(found) end
    if not found then return nil,"no map route from "..tostring(fromID).." to "..tostring(toID) end
    if type(globals.speedWalkPath)~="table" then return nil,"Mudlet mapper API getPath did not provide speedWalkPath" end
    if type(globals.speedWalkDir)~="table" then return nil,"Mudlet mapper API getPath did not provide speedWalkDir" end
    local route={rooms={},commands={}}
    for index,roomID in ipairs(globals.speedWalkPath) do route.rooms[index]=roomID end
    for index,direction in ipairs(globals.speedWalkDir) do route.commands[index]=direction end
    return route
  end
  api.roomExists=function(id)
    if type(globals.roomExists)=="function" then
      local ok,value=pcall(globals.roomExists,id)
      if not ok then return nil,"Mudlet mapper API roomExists failed: "..tostring(value) end
      return not not value
    end
    if type(globals.getRoomName)=="function" then
      local ok,value=pcall(globals.getRoomName,id)
      if not ok then return nil,"Mudlet mapper API getRoomName failed: "..tostring(value) end
      return value~=nil and value~=""
    end
    return missing("roomExists")
  end
  return api
end

return MapAdapter
