local Channels=require("chat_channels")
local History={}
History.__index=History
History.MAX_ENTRIES=1000
History.MAX_RETAINED_ENTRIES=13000

local private={WHISPER=true,ESP=true,CONTACT=true,MENTAL=true,PSYCIAN=true,DRAGON=true,SECIAN=true}
-- A busy source must not consume another source's history. Custom categories
-- share one bounded bucket rather than allocating memory for arbitrary names.
local retainedSources={ROOM=true,WHISPER=true,ESP=true,DRAGON=true,SECIAN=true,CONTACT=true,MENTAL=true,PSYCIAN=true,STAFF=true,COMBAT=true,WORLD=true,ALL=true}

local function normalized(value)
  return tostring(value or ""):lower():match("^%s*(.-)%s*$"):gsub("%s+"," ")
end

local function key(entry,category)
  return table.concat({normalized(category or Channels.entryCategory(entry)),normalized(entry.speaker),normalized(entry.target),normalized(entry.message)},"\0")
end

local mentalKinds={esp=true,contact=true,link=true}

function History:restoreDedupe(lastKey,lastEpoch,lastMentalKind)
  self.lastKey=type(lastKey)=="string" and lastKey or nil
  self.lastEpoch=tonumber(lastEpoch)
  self.lastMentalKind=nil
  local last=self.items[#self.items]
  -- Old handoffs carry raw category keys. Reclassify only a matching key,
  -- keeping its timestamp and the retained record itself unchanged.
  if last and self.lastKey==key(last,last.category) then self.lastKey=key(last) end
  if last and self.lastKey==key(last) and Channels.entryCategory(last)=="MENTAL" then
    -- A deduped text frame may enrich an unknown original record. Only the
    -- transient handoff carries that family; older handoffs derive it here.
    self.lastMentalKind=(type(lastMentalKind)=="string" and mentalKinds[lastMentalKind] and lastMentalKind) or Channels.mentalKind(last)
  end
end

local function identity(entry,projectedOverlap)
  local fields={"schema","timestamp","character","category","speaker","target","language","message","line","source","outgoing_id"}
  local values={}
  for index,name in ipairs(fields) do
    local value=entry[name]
    if projectedOverlap and name=="category" then value=Channels.entryCategory(entry) end
    values[index]=tostring(value or "")
  end
  return table.concat(values,"\0")
end

local function rebuildCategories(history)
  history.categoryOrder={}
  history.knownCategories={}
  for _,entry in ipairs(history.items) do
    local category=Channels.entryCategory(entry)
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

function History:append(entry,epoch,force)
  if type(entry)~="table" then return false end
  epoch=tonumber(epoch) or os.time()
  local entryKey=key(entry)
  local mentalKind=Channels.mentalKind(entry)
  local elapsed=epoch-(self.lastEpoch or epoch)
  local compatible=self.lastMentalKind==nil or mentalKind==nil or self.lastMentalKind==mentalKind
  if force~=true and self.lastKey==entryKey and compatible and elapsed>=0 and elapsed<=self.dedupeSeconds then
    self.lastMentalKind=self.lastMentalKind or mentalKind
    return false
  end
  self.lastKey=entryKey
  self.lastEpoch=epoch
  self.lastMentalKind=mentalKind
  self.items[#self.items+1]=entry
  local bucket=History.retentionKey(entry)
  self.retentionBuckets[#self.retentionBuckets+1]=bucket
  self.retentionCounts[bucket]=(self.retentionCounts[bucket] or 0)+1
  if self.retentionCounts[bucket]>self.limit then
    local removedCategory
    for index,existingBucket in ipairs(self.retentionBuckets) do
      if existingBucket==bucket then
        removedCategory=Channels.entryCategory(table.remove(self.items,index))
        table.remove(self.retentionBuckets,index)
        break
      end
    end
    self.retentionCounts[bucket]=self.limit
    if bucket=="OTHER" or removedCategory~=Channels.entryCategory(entry) then rebuildCategories(self) end
  end
  local category=Channels.entryCategory(entry)
  if category~="" and not self.knownCategories[category] then
    self.knownCategories[category]=true
    self.categoryOrder[#self.categoryOrder+1]=category
  end
  return true
end

function History:hydrate(entries,projectedOverlap)
  local combined,seen={},{}
  local function include(entry)
    if type(entry)~="table" then return end
    local entryIdentity=identity(entry,projectedOverlap)
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

function History:entries(filter,allSources,combinedLinks)
  filter=Channels.category(filter or "ALL")
  local entries={}
  for _,entry in ipairs(self.items) do
    local category=Channels.entryCategory(entry)
    if (filter==Channels.linkFilter and combinedLinks==true and Channels.linkMembers[category])
      or (filter=="ALL" and Channels.inAll(category,allSources)) or category==filter
      or (filter=="ROOM" and category=="OWN") or (filter=="PRIVATE" and private[category]) then entries[#entries+1]=Channels.project(entry) end
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
  self.lastMentalKind=nil
  return removed
end

return History
