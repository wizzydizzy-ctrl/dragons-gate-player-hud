local History={}
History.__index=History
History.MAX_ENTRIES=1000
History.MAX_RETAINED_ENTRIES=10000

local private={WHISPER=true,ESP=true,DRAGON=true,SECIAN=true,CONTACT=true}
-- A busy source must not consume another source's history. Custom categories
-- share one bounded bucket rather than allocating memory for arbitrary names.
local retainedSources={ROOM=true,WHISPER=true,ESP=true,DRAGON=true,SECIAN=true,CONTACT=true,STAFF=true,COMBAT=true,ALL=true}

local function normalized(value)
  return tostring(value or ""):lower():match("^%s*(.-)%s*$"):gsub("%s+"," ")
end

local function key(entry)
  return table.concat({normalized(entry.category),normalized(entry.speaker),normalized(entry.target),normalized(entry.message)},"\0")
end

local function identity(entry)
  local fields={"schema","timestamp","character","category","speaker","target","language","message","line","source"}
  local values={}
  for index,name in ipairs(fields) do values[index]=tostring(entry[name] or "") end
  return table.concat(values,"\0")
end

local function rebuildCategories(history)
  history.categoryOrder={}
  history.knownCategories={}
  for _,entry in ipairs(history.items) do
    local category=tostring(entry.category or ""):upper()
    if category~="" and not history.knownCategories[category] then
      history.knownCategories[category]=true
      history.categoryOrder[#history.categoryOrder+1]=category
    end
  end
end

function History.visibleLimit(limit)
  return math.min(History.MAX_ENTRIES,math.max(1,math.floor(tonumber(limit) or History.MAX_ENTRIES)))
end

function History.retentionKey(entry)
  local category=tostring(type(entry)=="table" and entry.category or ""):upper():match("^%s*(.-)%s*$")
  if category=="OWN" then category="ROOM" end
  return retainedSources[category] and category or "OTHER"
end

function History.retained(entries,limit)
  limit=History.visibleLimit(limit)
  local source=type(entries)=="table" and entries or {}
  local reversed,counts={},{}
  for index=#source,1,-1 do
    local entry=source[index]
    if type(entry)=="table" then
      local bucket=History.retentionKey(entry)
      if (counts[bucket] or 0)<limit then
        counts[bucket]=(counts[bucket] or 0)+1
        reversed[#reversed+1]=entry
      end
    end
  end
  local result={}
  for index=#reversed,1,-1 do result[#result+1]=reversed[index] end
  return result,counts
end

function History.new(limit,dedupeSeconds)
  return setmetatable({limit=History.visibleLimit(limit),dedupeSeconds=math.max(0,tonumber(dedupeSeconds) or 3),items={},retentionCounts={},retentionBuckets={},categoryOrder={},knownCategories={}},History)
end
function History:newSibling() return History.new(self.limit,self.dedupeSeconds) end

function History:append(entry,epoch)
  if type(entry)~="table" then return false end
  epoch=tonumber(epoch) or os.time()
  local entryKey=key(entry)
  local elapsed=epoch-(self.lastEpoch or epoch)
  if self.lastKey==entryKey and elapsed>=0 and elapsed<=self.dedupeSeconds then return false end
  self.lastKey=entryKey
  self.lastEpoch=epoch
  self.items[#self.items+1]=entry
  local bucket=History.retentionKey(entry)
  self.retentionBuckets[#self.retentionBuckets+1]=bucket
  self.retentionCounts[bucket]=(self.retentionCounts[bucket] or 0)+1
  if self.retentionCounts[bucket]>self.limit then
    for index,existingBucket in ipairs(self.retentionBuckets) do
      if existingBucket==bucket then table.remove(self.items,index); table.remove(self.retentionBuckets,index); break end
    end
    self.retentionCounts[bucket]=self.limit
    if bucket=="OTHER" then rebuildCategories(self) end
  end
  local category=tostring(entry.category or ""):upper()
  if category~="" and not self.knownCategories[category] then
    self.knownCategories[category]=true
    self.categoryOrder[#self.categoryOrder+1]=category
  end
  return true
end

function History:hydrate(entries)
  local combined,seen={},{}
  local function include(entry)
    if type(entry)~="table" then return end
    local entryIdentity=identity(entry)
    if seen[entryIdentity] then return end
    seen[entryIdentity]=true
    combined[#combined+1]=entry
  end
  for _,entry in ipairs(type(entries)=="table" and entries or {}) do include(entry) end
  for _,entry in ipairs(self.items) do include(entry) end
  self.items,self.retentionCounts=History.retained(combined,self.limit)
  self.retentionBuckets={}
  for index,entry in ipairs(self.items) do self.retentionBuckets[index]=History.retentionKey(entry) end
  rebuildCategories(self)
  return true
end

local function includedInAll(category,sources)
  if type(sources)~="table" then return true end
  if category=="OWN" then category="ROOM" end
  local enabled=sources[category]
  return enabled==nil or enabled==true
end

function History:entries(filter,allSources)
  filter=tostring(filter or "ALL"):upper()
  local entries={}
  for _,entry in ipairs(self.items) do
    local category=tostring(entry.category or ""):upper()
    if (filter=="ALL" and includedInAll(category,allSources)) or category==filter or (filter=="ROOM" and category=="OWN") or (filter=="PRIVATE" and private[category]) then entries[#entries+1]=entry end
  end
  return entries
end

function History:categories()
  local categories={}
  for index,category in ipairs(self.categoryOrder) do categories[index]=category end
  return categories
end

function History:clearVisible()
  local removed=#self.items
  self.items={}
  self.retentionCounts={}
  self.retentionBuckets={}
  self.categoryOrder={}
  self.knownCategories={}
  self.lastKey=nil
  self.lastEpoch=nil
  return removed
end

return History
