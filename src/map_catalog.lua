local Catalog={}

local LIMITS={maps=1000,slug=64,name=100,author=80,publisher=39,description=500,version=32,areas=100,area=100,subareas=200,subarea=100,rooms=100000}
local REQUIRED_FIELDS={slug=true,name=true,author=true,publisher=true,description=true,version=true,areas=true,room_count=true,bytes=true,download_url=true,sha256=true}
local ENTRY_FIELDS={slug=true,name=true,author=true,publisher=true,description=true,version=true,areas=true,subareas=true,scope=true,map_name=true,area_name=true,subarea_name=true,room_count=true,bytes=true,download_url=true,sha256=true}
local SCOPES={full_map=true,area=true,subarea=true}

local function fail(message) return nil,"invalid map catalog: "..message end
local function integer(value) return type(value)=="number" and value==math.floor(value) end
local function plain(value,limit,allow_empty)
  return type(value)=="string" and #value<=limit and (allow_empty or #value>0) and not value:find("[%z\1-\31\127]")
end
local function dense(array,limit)
  if type(array)~="table" then return false end
  local count=0
  for key in pairs(array) do
    if not integer(key) or key<1 or key>limit then return false end
    count=count+1
  end
  for index=1,count do if array[index]==nil then return false end end
  return true,count
end
local function copyEntry(entry)
  local out={}
  for key in pairs(ENTRY_FIELDS) do out[key]=entry[key] end
  out.areas={}
  for index,area in ipairs(entry.areas) do out.areas[index]=area end
  out.subareas={}
  for index,subarea in ipairs(entry.subareas or {}) do out.subareas[index]=subarea end
  out.scope=entry.scope or "full_map"
  return out
end
local function semanticVersion(value)
  if not plain(value,LIMITS.version) then return false end
  local core,suffix=value:match("^(%d+%.%d+%.%d+)(.*)$")
  if not core then return false end
  return suffix=="" or suffix:match("^%-[0-9A-Za-z][0-9A-Za-z%.%-]*$")~=nil
end

local function validateEntry(entry,index)
  if type(entry)~="table" then return fail("maps["..index.."] must be an object") end
  for key in pairs(entry) do if not ENTRY_FIELDS[key] then return fail("maps["..index.."] has unknown field "..tostring(key)) end end
  for key in pairs(REQUIRED_FIELDS) do if entry[key]==nil then return fail("maps["..index.."] is missing "..key) end end
  if not plain(entry.slug,LIMITS.slug) or not entry.slug:match("^[a-z0-9][a-z0-9_%-]*$") then return fail("maps["..index.."].slug is invalid") end
  if not plain(entry.name,LIMITS.name) then return fail("maps["..index.."].name is invalid") end
  if not plain(entry.author,LIMITS.author) then return fail("maps["..index.."].author is invalid") end
  if not plain(entry.publisher,LIMITS.publisher) or not entry.publisher:match("^[A-Za-z0-9][A-Za-z0-9%-]*$") or entry.publisher:sub(-1)=="-" or entry.publisher:find("%-%-") then return fail("maps["..index.."].publisher is invalid") end
  if not plain(entry.description,LIMITS.description,true) then return fail("maps["..index.."].description is invalid") end
  if not semanticVersion(entry.version) then return fail("maps["..index.."].version is invalid") end
  local areas_ok,area_count=dense(entry.areas,LIMITS.areas)
  if not areas_ok or area_count<1 then return fail("maps["..index.."].areas must be a non-empty dense array") end
  local seen={}
  for area_index,area in ipairs(entry.areas) do
    if not plain(area,LIMITS.area) then return fail("maps["..index.."].areas["..area_index.."] is invalid") end
    if seen[area] then return fail("maps["..index.."].areas contains a duplicate") end
    seen[area]=true
  end
  if entry.scope~=nil and not SCOPES[entry.scope] then return fail("maps["..index.."].scope is invalid") end
  for _,key in ipairs({"map_name","area_name","subarea_name"}) do if entry[key]~=nil and not plain(entry[key],LIMITS.area) then return fail("maps["..index.."]."..key.." is invalid") end end
  if entry.subareas~=nil then
    local subareas_ok,subarea_count=dense(entry.subareas,LIMITS.subareas)
    if not subareas_ok then return fail("maps["..index.."].subareas must be a dense array") end
    local subarea_seen={}
    for subarea_index=1,subarea_count do local subarea=entry.subareas[subarea_index]; if not plain(subarea,LIMITS.subarea) then return fail("maps["..index.."].subareas["..subarea_index.."] is invalid") end; if subarea_seen[subarea] then return fail("maps["..index.."].subareas contains a duplicate") end; subarea_seen[subarea]=true end
  end
  if not integer(entry.room_count) or entry.room_count<1 or entry.room_count>LIMITS.rooms then return fail("maps["..index.."].room_count is invalid") end
  if not integer(entry.bytes) or entry.bytes<1 or entry.bytes>20000000 then return fail("maps["..index.."].bytes is invalid") end
  if type(entry.sha256)~="string" or #entry.sha256~=64 or not entry.sha256:match("^[0-9a-f]+$") then return fail("maps["..index.."].sha256 is invalid") end
  if type(entry.download_url)~="string" or #entry.download_url>300 then return fail("maps["..index.."].download_url is invalid") end
  local prefix="https://raw.githubusercontent.com/wizzydizzy%-ctrl/dragons%-gate%-map%-library/"
  local ref,path=entry.download_url:match("^"..prefix.."([A-Za-z0-9][A-Za-z0-9._%-]*)/(maps/.+)$")
  local expected="maps/"..entry.publisher.."/"..entry.slug..".json"
  if not ref or path~=expected then return fail("maps["..index.."].download_url is not an approved library path") end
  return copyEntry(entry)
end

function Catalog.validate(catalog)
  if type(catalog)~="table" then return fail("root must be an object") end
  for key in pairs(catalog) do if key~="schema" and key~="maps" then return fail("root has unknown field "..tostring(key)) end end
  if catalog.schema~=1 and catalog.schema~=2 then return fail("schema must equal 1 or 2") end
  local maps_ok,count=dense(catalog.maps,LIMITS.maps)
  if not maps_ok then return fail("maps must be a dense array") end
  local normalized={schema=catalog.schema,maps={}}
  local identities={}
  for index=1,count do
    local entry,err=validateEntry(catalog.maps[index],index)
    if not entry then return nil,err end
    local identity=entry.publisher:lower().."/"..entry.slug
    if identities[identity] then return fail("maps contains duplicate "..identity) end
    identities[identity]=true
    normalized.maps[index]=entry
  end
  return normalized
end

function Catalog.select(catalog,publisher,slug)
  local normalized,err=Catalog.validate(catalog)
  if not normalized then return nil,err end
  if type(publisher)~="string" or type(slug)~="string" then return fail("selection requires publisher and slug") end
  for _,entry in ipairs(normalized.maps) do
    if entry.publisher:lower()==publisher:lower() and entry.slug==slug then return entry end
  end
  return nil,"map not found"
end

function Catalog.search(catalog,query)
  local normalized,err=Catalog.validate(catalog)
  if not normalized then return nil,err end
  if type(query)~="string" or #query>100 or query:find("[%z\1-\31\127]") then return fail("search query is invalid") end
  local needle=query:lower()
  local matches={}
  for _,entry in ipairs(normalized.maps) do
    local haystack=table.concat({entry.name,entry.author,entry.publisher,entry.description,entry.map_name or "",entry.area_name or "",entry.subarea_name or "",table.concat(entry.areas,"\n"),table.concat(entry.subareas or {},"\n")},"\n"):lower()
    if needle=="" or haystack:find(needle,1,true) then matches[#matches+1]=entry end
  end
  return matches
end

function Catalog.filterEntries(entries,query,scope)
  query=tostring(query or ""):lower(); scope=tostring(scope or "all")
  local matches={}
  for _,entry in ipairs(entries or {}) do
    local entryScope=SCOPES[entry.scope] and entry.scope or "full_map"
    local haystack=table.concat({tostring(entry.name or ""),tostring(entry.author or ""),tostring(entry.publisher or ""),tostring(entry.description or ""),tostring(entry.map_name or ""),tostring(entry.area_name or ""),tostring(entry.subarea_name or ""),table.concat(entry.areas or {},"\n"),table.concat(entry.subareas or {},"\n")},"\n"):lower()
    if (scope=="all" or scope==entryScope) and (query=="" or haystack:find(query,1,true)) then matches[#matches+1]=entry end
  end
  return matches
end

function Catalog.scopeLabel(entry)
  local scope=type(entry)=="table" and entry.scope or nil
  return scope=="area" and "Area" or scope=="subarea" and "Subarea" or "Full Map"
end

Catalog.limits=LIMITS
return Catalog
