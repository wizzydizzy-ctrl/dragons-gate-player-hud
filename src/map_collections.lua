local Collections={}; Collections.__index=Collections

local LIMITS={collections=100,name=100,id=80,path=500,identity=160,rooms=1000000,bytes=20000000}
local COLLECTION_FIELDS={id=true,name=true,created_at=true,updated_at=true,editable=true,source=true,forked_from=true,snapshot=true,backup=true}
local STATE_FIELDS={schema=true,active_collection_id=true,collections=true}
local SOURCE_FIELDS={kind=true,artifact_id=true,publisher=true,slug=true}
local FILE_FIELDS={path=true,sha256=true,room_count=true,bytes=true,created_at=true}
local SOURCE_KINDS={local_map=true,library=true,legacy=true}

local function copy(value,seen)
  if type(value)~="table" then return value end
  seen=seen or {}; if seen[value] then error("collection data must not contain cycles") end; seen[value]=true
  local out={}; for key,item in pairs(value) do out[copy(key,seen)]=copy(item,seen) end; seen[value]=nil; return out
end
local function plain(value,limit)
  return type(value)=="string" and #value>0 and #value<=limit and not value:find("[%z\1-\31\127]")
end
local function integer(value,minimum,maximum)
  return type(value)=="number" and value==math.floor(value) and value>=minimum and value<=maximum
end
local function checksum(value) return type(value)=="string" and #value==64 and value:match("^[0-9a-f]+$")~=nil end
local function dense(value,limit)
  if type(value)~="table" then return nil end
  local count=0; for key in pairs(value) do if not integer(key,1,limit) then return nil end; count=count+1 end
  for index=1,count do if value[index]==nil then return nil end end
  return count
end
local function allowed(value,fields,label)
  for key in pairs(value) do if not fields[key] then return nil,label.." has unknown field "..tostring(key) end end
  return true
end
local function validID(value) return plain(value,LIMITS.id) and value:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")~=nil end

local function validateSource(value,label)
  label=label or "source"
  if type(value)~="table" then return nil,label.." must be an object" end
  local ok,err=allowed(value,SOURCE_FIELDS,label); if not ok then return nil,err end
  if not SOURCE_KINDS[value.kind] then return nil,label.." kind is invalid" end
  for _,key in ipairs({"artifact_id","publisher","slug"}) do
    if value[key]~=nil and not plain(value[key],LIMITS.identity) then return nil,label.." "..key.." is invalid" end
  end
  if value.kind=="library" and (not value.artifact_id or not value.publisher or not value.slug) then return nil,label.." library identity is incomplete" end
  return copy(value)
end

local function validateFile(value,label,backup)
  if value==nil then return nil end
  if type(value)~="table" then return nil,label.." must be an object" end
  local ok,err=allowed(value,FILE_FIELDS,label); if not ok then return nil,err end
  if not plain(value.path,LIMITS.path) then return nil,label.." path is invalid" end
  if not checksum(value.sha256) then return nil,label.." checksum is invalid" end
  if not integer(value.room_count,0,LIMITS.rooms) then return nil,label.." room count is invalid" end
  if not integer(value.bytes,1,LIMITS.bytes) then return nil,label.." byte count is invalid" end
  if backup and not integer(value.created_at,0,9007199254740991) then return nil,label.." timestamp is invalid" end
  local out=copy(value); if not backup then out.created_at=nil end; return out
end

local function validateCollection(value,index)
  local label="collections["..index.."]"
  if type(value)~="table" then return nil,label.." must be an object" end
  local ok,err=allowed(value,COLLECTION_FIELDS,label); if not ok then return nil,err end
  if not validID(value.id) then return nil,label.." id is invalid" end
  if not plain(value.name,LIMITS.name) then return nil,label.." name is invalid" end
  if not integer(value.created_at,0,9007199254740991) or not integer(value.updated_at,0,9007199254740991) or value.updated_at<value.created_at then return nil,label.." timestamps are invalid" end
  if type(value.editable)~="boolean" then return nil,label.." editable must be boolean" end
  local source,sourceErr=validateSource(value.source,label.." source"); if not source then return nil,sourceErr end
  if value.forked_from~=nil and not validID(value.forked_from) then return nil,label.." forked_from is invalid" end
  local snapshot,snapshotErr=validateFile(value.snapshot,label.." snapshot",false); if value.snapshot~=nil and not snapshot then return nil,snapshotErr end
  local backup,backupErr=validateFile(value.backup,label.." backup",true); if value.backup~=nil and not backup then return nil,backupErr end
  return {id=value.id,name=value.name,created_at=value.created_at,updated_at=value.updated_at,editable=value.editable,source=source,forked_from=value.forked_from,snapshot=snapshot,backup=backup}
end

function Collections.validate(state)
  if type(state)~="table" then return nil,"collection state must be an object" end
  local ok,err=allowed(state,STATE_FIELDS,"collection state"); if not ok then return nil,err end
  if state.schema~=1 then return nil,"collection schema must equal 1" end
  local count=dense(state.collections,LIMITS.collections); if not count then return nil,"collections must be a bounded dense array" end
  local out={schema=1,active_collection_id=state.active_collection_id,collections={}}; local ids={}
  for index=1,count do
    local item,itemErr=validateCollection(state.collections[index],index); if not item then return nil,itemErr end
    if ids[item.id] then return nil,"collection id is duplicated" end; ids[item.id]=true; out.collections[index]=item
  end
  if out.active_collection_id~=nil and (not validID(out.active_collection_id) or not ids[out.active_collection_id]) then return nil,"active collection does not exist" end
  for _,item in ipairs(out.collections) do if item.forked_from==item.id then return nil,"collection cannot fork itself" end end
  return out
end

function Collections.new(state,options)
  options=options or {}; local normalized,err=Collections.validate(state or {schema=1,collections={}}); if not normalized then return nil,err end
  return setmetatable({state=normalized,clock=options.clock or os.time,id_factory=options.id_factory},Collections)
end
function Collections:_now() local value=self.clock(); if not integer(value,0,9007199254740991) then return nil,"collection clock returned an invalid timestamp" end; return value end
function Collections:_id()
  if type(self.id_factory)~="function" then return nil,"collection ID factory is unavailable" end
  local id=self.id_factory(); if not validID(id) then return nil,"collection ID factory returned an invalid ID" end
  if self:_index(id) then return nil,"collection ID already exists" end; return id
end
function Collections:_index(id) for index,item in ipairs(self.state.collections) do if item.id==id then return index,item end end end
function Collections:get(id) local _,item=self:_index(id); return item and copy(item) or nil end
function Collections:list() return copy(self.state.collections) end
function Collections:exportState() return copy(self.state) end
function Collections:active() return self.state.active_collection_id and self:get(self.state.active_collection_id) or nil end

function Collections:create(name,source,editable)
  if not plain(name,LIMITS.name) then return nil,"collection name is invalid" end
  local normalized,sourceErr=validateSource(source or {kind="local_map"}); if not normalized then return nil,sourceErr end
  local id,idErr=self:_id(); if not id then return nil,idErr end; local now,timeErr=self:_now(); if not now then return nil,timeErr end
  local item={id=id,name=name,created_at=now,updated_at=now,editable=editable~=false,source=normalized}
  self.state.collections[#self.state.collections+1]=item; return copy(item)
end
function Collections:fork(id,name)
  local _,original=self:_index(id); if not original then return nil,"source collection does not exist" end
  local fork,forkErr=self:create(name,original.source,true); if not fork then return nil,forkErr end
  local _,stored=self:_index(fork.id); stored.forked_from=original.id; stored.snapshot=copy(original.snapshot); return copy(stored)
end
function Collections:rename(id,name)
  if not plain(name,LIMITS.name) then return nil,"collection name is invalid" end
  local _,item=self:_index(id); if not item then return nil,"collection does not exist" end
  local now,err=self:_now(); if not now then return nil,err end; item.name=name; item.updated_at=now; return copy(item)
end
function Collections:setActive(id)
  if id~=nil and not self:_index(id) then return nil,"active collection does not exist" end
  self.state.active_collection_id=id; return self:active() or true
end
function Collections:updateSnapshot(id,metadata)
  local _,item=self:_index(id); if not item then return nil,"collection does not exist" end
  if not item.editable then return nil,"collection is read-only; fork it before editing" end
  local snapshot,err=validateFile(metadata,"snapshot",false); if not snapshot then return nil,err end
  local now,timeErr=self:_now(); if not now then return nil,timeErr end; item.snapshot=snapshot; item.updated_at=now; return copy(item)
end
function Collections:recordBackup(id,metadata)
  local _,item=self:_index(id); if not item then return nil,"collection does not exist" end
  local backup,err=validateFile(metadata,"backup",true); if not backup then return nil,err end
  item.backup=backup; return copy(item)
end
function Collections:remove(id)
  local index,item=self:_index(id); if not item then return nil,"collection does not exist" end
  if #self.state.collections<=1 then return nil,"the last map collection cannot be deleted" end
  table.remove(self.state.collections,index)
  if self.state.active_collection_id==id then self.state.active_collection_id=nil end
  return copy(item)
end
function Collections:setEditable(id,value)
  local _,item=self:_index(id); if not item then return nil,"collection does not exist" end
  local now,err=self:_now(); if not now then return nil,err end
  item.editable=value==true; item.updated_at=now; return copy(item)
end
function Collections:updateLibrarySource(id,source)
  local _,item=self:_index(id); if not item then return nil,"collection does not exist" end
  local normalized,err=validateSource(source,"source"); if not normalized then return nil,err end
  if item.source.kind~="library" or normalized.kind~="library" or item.source.publisher~=normalized.publisher or item.source.slug~=normalized.slug then return nil,"library source identity does not match" end
  local now,timeErr=self:_now(); if not now then return nil,timeErr end; item.source=normalized; item.updated_at=now; return copy(item)
end

return Collections
