local History=require("chat_history")
local Storage={}
Storage.__index=Storage
Storage.MAX_ENTRIES=History.MAX_ENTRIES

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

function Storage.safeCharacter(name)
  local safe=trim(name):lower():gsub("[^a-z0-9_-]+","_"):gsub("_+","_"):gsub("^_+",""):gsub("_+$","")
  return safe~="" and safe or "unknown"
end

local function path(base,name)
  return base.."/"..name
end

local function date(timestamp)
  return tostring(timestamp or ""):match("^(%d%d%d%d%-%d%d%-%d%d)T") or os.date("%Y-%m-%d")
end

local function datedFiles(files)
  local result={}
  for _,file in ipairs(files or {}) do
    if type(file)=="string" and file:match("^%d%d%d%d%-%d%d%-%d%d%.jsonl$") then result[#result+1]=file end
  end
  table.sort(result,function(a,b) return a>b end)
  return result
end

local function entryIdentity(entry)
  local fields={"schema","timestamp","character","category","speaker","target","language","message","line","source"}; local values={}
  for index,name in ipairs(fields) do values[index]=tostring(entry[name] or "") end
  return table.concat(values,"\0")
end

local function earlier(a,b)
  if a.timestamp~=b.timestamp then return a.timestamp<b.timestamp end
  if a.lineIndex~=b.lineIndex then return a.lineIndex<b.lineIndex end
  if a.directory~=b.directory then return a.directory<b.directory end
  return a.sequence<b.sequence
end

-- Keep an oldest-first heap for each fixed retention bucket. The identity map
-- contains only selected records, so a large day or repeated legacy copies
-- cannot accumulate unbounded decoded entries or deduplication keys.
local function siftDown(heap,index)
  local record=heap[index]
  while index*2<=#heap do
    local child=index*2
    if child<#heap and earlier(heap[child+1],heap[child]) then child=child+1 end
    if not earlier(heap[child],record) then break end
    heap[index]=heap[child]; heap[index].index=index; index=child
  end
  heap[index]=record; record.index=index
end

local function selectRecord(buckets,seen,limit,record)
  local bucket=History.retentionKey(record.entry)
  local heap=buckets[bucket]
  if not heap then heap={}; buckets[bucket]=heap end
  record.identity=entryIdentity(record.entry)
  local duplicate=seen[record.identity]
  if duplicate then
    -- Use the newest occurrence as the stable representative of an overlap.
    -- A previously evicted copy can only return if its occurrence ranks newer.
    if earlier(duplicate,record) then
      heap[duplicate.index]=record; seen[record.identity]=record
      siftDown(heap,duplicate.index)
    end
  elseif #heap<limit then
    local index=#heap+1
    while index>1 do
      local parent=math.floor(index/2)
      if not earlier(record,heap[parent]) then break end
      heap[index]=heap[parent]; heap[index].index=index; index=parent
    end
    heap[index]=record; record.index=index; seen[record.identity]=record
  elseif earlier(heap[1],record) then
    seen[heap[1].identity]=nil
    heap[1]=record; seen[record.identity]=record; siftDown(heap,1)
  end
end

local function call(api,name,...)
  local ok,result,err=pcall(api[name],...)
  if not ok then return nil,tostring(result) end
  return result,err
end

function Storage.new(api,basePath,visibleLimit)
  assert(type(api)=="table","storage api is required")
  visibleLimit=History.visibleLimit(visibleLimit)
  return setmetatable({api=api,basePath=tostring(basePath or ""),visibleLimit=visibleLimit,reportedMalformed=false},Storage)
end

function Storage:characterKey()
  return "profile"
end

function Storage:recordError(message)
  self.lastStorageError=tostring(message or "could not access chat log")
  return self.lastStorageError
end

function Storage:lastError()
  return self.lastStorageError
end

function Storage:append(entry)
  if type(entry)~="table" then return nil,self:recordError("chat entry is required") end
  local directory=path(self.basePath,self:characterKey())
  local ok,err=call(self.api,"mkdir",self.basePath)
  if not ok then return nil,self:recordError(err or "could not create chat storage") end
  ok,err=call(self.api,"mkdir",directory)
  if not ok then return nil,self:recordError(err or "could not create character storage") end
  local encoded=call(self.api,"encode",entry)
  if type(encoded)~="string" then return nil,self:recordError("could not encode chat entry") end
  local appended,appendErr=call(self.api,"append",path(directory,date(entry.timestamp)..".jsonl"),encoded.."\n")
  if not appended then return nil,self:recordError(appendErr or "could not append chat log") end
  return appended
end

function Storage:reportMalformed()
  if self.reportedMalformed then return end
  self.reportedMalformed=true
  if type(self.api.report)=="function" then pcall(self.api.report,"skipped malformed chat log entry") end
end

function Storage:reportFailure(message)
  self:recordError(message)
  if self.reportedFailure then return end
  self.reportedFailure=true
  if type(self.api.report)=="function" then pcall(self.api.report,self.lastStorageError) end
end

function Storage:loadRecent()
  local directory=path(self.basePath,self:characterKey())
  local created,createErr=call(self.api,"mkdir",self.basePath)
  if not created then
    self:reportFailure(createErr or "could not create chat storage")
    return {}
  end
  created,createErr=call(self.api,"mkdir",directory)
  if not created then
    self:reportFailure(createErr or "could not create character storage")
    return {}
  end
  local directories={directory}; local rootEntries,rootErr=call(self.api,"list",self.basePath)
  if type(rootEntries)~="table" then if rootErr then self:reportFailure(rootErr) end else
    for _,name in ipairs(rootEntries) do
      if type(name)=="string" and name~="profile" and name:match("^[a-z0-9_-]+$") then directories[#directories+1]=path(self.basePath,name) end
    end
  end
  table.sort(directories)
  local byDate,dateSet={},{}
  for _,candidate in ipairs(directories) do
    local files,listErr=call(self.api,"list",candidate)
    if type(files)=="table" then
      for _,file in ipairs(datedFiles(files)) do
        byDate[file]=byDate[file] or {}; byDate[file][#byDate[file]+1]=candidate; dateSet[file]=true
      end
    elseif candidate==directory and listErr then self:reportFailure(listErr) end
  end
  local dates={}; for file in pairs(dateSet) do dates[#dates+1]=file end; table.sort(dates,function(a,b) return a>b end)
  local buckets,seen={},{}; local sequence=0
  for _,file in ipairs(dates) do
    for _,candidate in ipairs(byDate[file]) do
      local lineIndex=0
      local function include(line)
        if line=="" then return end
        lineIndex=lineIndex+1
        local ok,entry=pcall(self.api.decode,line)
        if ok and type(entry)=="table" then
          sequence=sequence+1
          selectRecord(buckets,seen,self.visibleLimit,{entry=entry,timestamp=tostring(entry.timestamp or file),lineIndex=lineIndex,directory=candidate,sequence=sequence})
        else self:reportMalformed() end
      end
      if type(self.api.eachLine)=="function" then
        local read,readErr=call(self.api,"eachLine",path(candidate,file),include)
        if not read then self:reportFailure(readErr or "could not read chat log") end
      else
        -- Small injected/fake APIs may still supply read(). Avoid building a
        -- second table of all lines even when streaming is unavailable.
        local content,readErr=call(self.api,"read",path(candidate,file))
        if readErr then self:reportFailure(readErr) end
        for line in tostring(content or ""):gmatch("[^\n]+") do include(line) end
      end
    end
    -- Scan every date: even a full COMBAT bucket says nothing about older
    -- STAFF or private conversations. Selection stays bounded across dates.
  end
  local records={}
  for _,heap in pairs(buckets) do for _,record in ipairs(heap) do records[#records+1]=record end end
  table.sort(records,earlier)
  local chronological={}
  for _,record in ipairs(records) do chronological[#chronological+1]=record.entry end
  local retained=History.retained(chronological,self.visibleLimit)
  return retained
end

function Storage:clearProfileHistory(confirmed)
  if confirmed~=true then return nil,"explicit confirmation is required to permanently clear saved chat history" end
  if type(self.api.remove)~="function" then return nil,self:recordError("chat log removal is unavailable") end

  local profileDirectory=path(self.basePath,self:characterKey())
  local created,createErr=call(self.api,"mkdir",self.basePath)
  if not created then return nil,self:recordError(createErr or "could not access chat storage") end
  created,createErr=call(self.api,"mkdir",profileDirectory)
  if not created then return nil,self:recordError(createErr or "could not access profile chat storage") end

  local rootEntries,rootErr=call(self.api,"list",self.basePath)
  if type(rootEntries)~="table" then return nil,self:recordError(rootErr or "could not list chat storage") end
  local directories={profileDirectory}
  for _,name in ipairs(rootEntries) do
    if type(name)=="string" and name~="profile" and name:match("^[a-z0-9_-]+$") then directories[#directories+1]=path(self.basePath,name) end
  end
  table.sort(directories)

  local targets={}
  for _,directory in ipairs(directories) do
    local files,listErr=call(self.api,"list",directory)
    if type(files)~="table" then return nil,self:recordError(listErr or "could not list profile chat storage") end
    for _,file in ipairs(datedFiles(files)) do targets[#targets+1]=path(directory,file) end
  end
  table.sort(targets)

  local removed=0
  for _,target in ipairs(targets) do
    local ok,removeErr=call(self.api,"remove",target)
    if not ok then
      return nil,self:recordError((removeErr or "could not remove saved chat log").." after removing "..removed.." of "..#targets.." chat log files")
    end
    removed=removed+1
  end
  self.lastStorageError=nil
  self.reportedMalformed=false
  self.reportedFailure=false
  return true,removed
end

function Storage:close()
  return true
end

local function startsWith(value,prefix)
  return value:sub(1,#prefix)==prefix and (value==prefix or value:sub(#prefix+1,#prefix+1)=="/")
end

local function safeRelative(value,root,allowFile)
  if type(value)~="string" or not startsWith(value,root) then return nil end
  local relative=value:sub(#root+1):match("^/(.+)$")
  if not relative then return value==root and "" or nil end
  for segment in relative:gmatch("[^/]+") do
    if not segment:match("^[a-z0-9_-]+$") and not (allowFile and segment:match("^%d%d%d%d%-%d%d%-%d%d%.jsonl$")) then return nil end
  end
  return relative
end

function Storage.mudletApi(home,dataFolder)
  home=tostring(home or getMudletHomeDir()):gsub("/+$","")
  dataFolder=tostring(dataFolder or "DGHUDData")
  if not dataFolder:match("^[A-Za-z0-9_-]+$") then error("invalid chat data folder",0) end
  local root=home.."/"..dataFolder.."/chat"
  local function ensure(directory)
    local relative=safeRelative(directory,root,false)
    if relative==nil then return nil,"unsafe chat storage path" end
    if not lfs or type(lfs.mkdir)~="function" then return nil,"filesystem is unavailable" end
    local current=home
    for _,segment in ipairs({dataFolder,"chat"}) do
      current=current.."/"..segment
      local ok,err=lfs.mkdir(current)
      if not ok and (type(lfs.attributes)~="function" or lfs.attributes(current,"mode")~="directory") then return nil,err or "could not create chat storage" end
    end
    for segment in relative:gmatch("[^/]+") do
      current=current.."/"..segment
      local ok,err=lfs.mkdir(current)
      if not ok and (type(lfs.attributes)~="function" or lfs.attributes(current,"mode")~="directory") then return nil,err or "could not create chat storage" end
    end
    return true
  end
  local function open(pathname,mode)
    if not safeRelative(pathname,root,true) then return nil,"unsafe chat storage path" end
    if not io or type(io.open)~="function" then return nil,"file access is unavailable" end
    return io.open(pathname,mode)
  end
  return {
    mkdir=ensure,
    append=function(pathname,text)
      local file,err=open(pathname,"ab")
      if not file then return nil,err end
      local ok,writeErr=file:write(text)
      file:close()
      if not ok then return nil,writeErr or "could not append chat log" end
      return true
    end,
    list=function(directory)
      if safeRelative(directory,root,false)==nil then return nil,"unsafe chat storage path" end
      if not lfs or type(lfs.dir)~="function" then return nil,"filesystem is unavailable" end
      local ok,iterator,state=pcall(lfs.dir,directory)
      if not ok then return nil,tostring(iterator) end
      if type(iterator)~="function" then return nil,tostring(state or "could not list chat storage") end
      local files={}
      for name in iterator,state do if name~="." and name~=".." then files[#files+1]=name end end
      return files
    end,
    read=function(pathname)
      local file,err=open(pathname,"rb")
      if not file then return nil,err or "could not open chat log" end
      local content,readErr=file:read("*a")
      file:close()
      if content==nil then return nil,readErr or "could not read chat log" end
      return content
    end,
    eachLine=function(pathname,consume)
      local file,err=open(pathname,"rb")
      if not file then return nil,err or "could not open chat log" end
      -- Both read and callback errors must close the native handle. Decode
      -- failures are handled by the consumer without exposing chat contents.
      local ok,readErr=pcall(function()
        while true do
          local line,lineErr=file:read("*l")
          if line==nil then
            if lineErr then error(lineErr,0) end
            break
          end
          consume(line)
        end
      end)
      local closed,closeResult,closeErr=pcall(file.close,file)
      if not ok then return nil,tostring(readErr) end
      if not closed then return nil,tostring(closeResult) end
      if not closeResult then return nil,closeErr or "could not close chat log" end
      return true
    end,
    remove=function(pathname)
      local relative=safeRelative(pathname,root,true)
      if not relative or not relative:match("^[a-z0-9_-]+/%d%d%d%d%-%d%d%-%d%d%.jsonl$") then return nil,"unsafe chat storage path" end
      if not os or type(os.remove)~="function" then return nil,"file removal is unavailable" end
      local ok,removed,removeErr=pcall(os.remove,pathname)
      if not ok then return nil,tostring(removed) end
      if not removed then return nil,removeErr or "could not remove chat log" end
      return true
    end,
    encode=function(entry) return yajl.to_string(entry) end,
    decode=function(line) return yajl.to_value(line) end,
    report=function(message) if type(cecho)=="function" then cecho("\n<red>[DGHUD Chat]<reset> "..tostring(message).."\n") end end,
  }
end

return Storage
