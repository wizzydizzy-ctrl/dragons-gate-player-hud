local Storage={}
Storage.__index=Storage
Storage.MAX_ENTRIES=1000

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

local function lines(text)
  local result={}
  for line in (tostring(text or "").."\n"):gmatch("(.-)\n") do
    if line~="" then result[#result+1]=line end
  end
  return result
end

local function entryIdentity(entry)
  local fields={"schema","timestamp","character","category","speaker","target","language","message","line","source"}; local values={}
  for index,name in ipairs(fields) do values[index]=tostring(entry[name] or "") end
  return table.concat(values,"\0")
end

local function call(api,name,...)
  local ok,result,err=pcall(api[name],...)
  if not ok then return nil,tostring(result) end
  return result,err
end

function Storage.new(api,basePath,visibleLimit)
  assert(type(api)=="table","storage api is required")
  visibleLimit=math.min(Storage.MAX_ENTRIES,math.max(1,math.floor(tonumber(visibleLimit) or Storage.MAX_ENTRIES)))
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
  local records,seen={},{}; local sequence=0
  for _,file in ipairs(dates) do
    for _,candidate in ipairs(byDate[file]) do
      local content,readErr=call(self.api,"read",path(candidate,file)); if readErr then self:reportFailure(readErr) end
      for lineIndex,line in ipairs(lines(content)) do
        local ok,entry=pcall(self.api.decode,line)
        if ok and type(entry)=="table" then
          local identity=entryIdentity(entry)
          if not seen[identity] then
            seen[identity]=true; sequence=sequence+1
            records[#records+1]={entry=entry,order=tostring(entry.timestamp or file).."\0"..string.format("%08d",lineIndex).."\0"..candidate,sequence=sequence}
          end
        else self:reportMalformed() end
      end
    end
    if #records>=self.visibleLimit then break end
  end
  table.sort(records,function(a,b) if a.order==b.order then return a.sequence<b.sequence end; return a.order<b.order end)
  local unique={}
  for _,record in ipairs(records) do unique[#unique+1]=record.entry end
  local chronological={}; local first=math.max(1,#unique-self.visibleLimit+1)
  for index=first,#unique do chronological[#chronological+1]=unique[index] end
  return chronological
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
    encode=function(entry) return yajl.to_string(entry) end,
    decode=function(line) return yajl.to_value(line) end,
    report=function(message) if type(cecho)=="function" then cecho("\n<red>[DGHUD Chat]<reset> "..tostring(message).."\n") end end,
  }
end

return Storage
