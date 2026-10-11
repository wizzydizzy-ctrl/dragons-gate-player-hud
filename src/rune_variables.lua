local Runes={}; Runes.__index=Runes
local function validCount(value)
  return type(value)=="number" and value==value and value>=0 and value<=9007199254740991 and value%1==0
end
function Runes.new(namespace,environment)
  namespace=type(namespace)=="table" and namespace or {}
  local api=type(namespace.runes)=="table" and namespace.runes or {}
  namespace.runes=api
  local self=setmetatable({namespace=namespace,api=api,environment=environment or _G,owned={},api_owned={},values={}},Runes)
  api.values=self.values
  return self
end
function Runes:clear()
  for key,value in pairs(self.owned) do
    -- Delete only the exact value exported by this HUD, not a later user edit.
    if rawget(self.environment,key)==value then rawset(self.environment,key,nil) end
  end
  self.owned={}
  for key,value in pairs(self.api_owned) do
    if rawget(self.api,key)==value then rawset(self.api,key,nil) end
  end
  self.api_owned={}
  for key in pairs(self.values) do self.values[key]=nil end
  self.api.items={}; self.api.by_name={}; self.api.remaining={}
  self.api.values=self.values
  return true
end
function Runes.snapshot(items)
  if type(items)~="table" or getmetatable(items)~=nil then return nil,"Invalid rune list." end
  local count,highest=0,0
  for key in next,items do
    count=count+1
    if count>256 or not validCount(key) or key<1 or key>256 then return nil,"Invalid rune list." end
    if key>highest then highest=key end
  end
  if count~=highest then return nil,"Incomplete rune list." end
  local values,rows={},{}
  for _,item in ipairs(items) do
    if type(item)~="table" or getmetatable(item)~=nil or type(item.name)~="string" or #item.name>80 or not validCount(item.remaining) then
      return nil,"Invalid rune value."
    end
    local display=item.name:match("^%s*(.-)%s*$"):gsub("%s+"," ")
    local name=display:lower()
    if name=="" or name:find("[^a-z ]") then return nil,"Invalid rune name." end
    local key=name:gsub(" ","_")
    if values[key]~=nil and values[key]~=item.remaining then return nil,"Conflicting rune counts." end
    if values[key]==nil then rows[#rows+1]={name=display,remaining=item.remaining} end
    values[key]=item.remaining
  end
  return rows,nil,values
end
function Runes:save(items)
  local rows,err,values=Runes.snapshot(items)
  if not rows then return nil,err end
  self:clear()
  for index,item in ipairs(rows) do
    local name=item.name:lower():match("^%s*(.-)%s*$"):gsub("%s+"," ")
    self.api.items[index]={name=item.name,remaining=item.remaining}
    self.api.by_name[name]={name=item.name,remaining=item.remaining}; self.api.remaining[name]=item.remaining
  end
  for key,value in pairs(values) do
    self.values[key]=value
    if rawget(self.api,key)==nil then self.api[key]=value; self.api_owned[key]=value end
    -- Namespaced values always exist. Never overwrite an unrelated global.
    if rawget(self.environment,key)==nil then
      rawset(self.environment,key,value); self.owned[key]=value
    end
  end
  return true
end
return Runes
