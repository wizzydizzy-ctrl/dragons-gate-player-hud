local Channels={}
Channels.order={"ALL","ROOM","PRIVATE","MENTAL","DRAGON","PSYCIAN","STAFF","COMBAT","WORLD"}
Channels.sourceOrder={"ROOM","WHISPER","MENTAL","DRAGON","PSYCIAN","SECIAN","STAFF","COMBAT","WORLD"}
local aliases={ESP="MENTAL",CONTACT="MENTAL"}
local linkCategories={ESP=true,CONTACT=true,MENTAL=true,DRAGON=true,PSYCIAN=true,SECIAN=true}
local activeName="([%w_%-'][%w_%-%' ]*)"
Channels.linkFilter="LINK VIEW"
Channels.linkMembers={MENTAL=true,DRAGON=true,PSYCIAN=true,SECIAN=true}

function Channels.combinedOrder(order,categories,preferred)
  local available,result,seen={}, {}, {}
  for _,value in ipairs(order or {}) do
    local category=Channels.category(value)
    available[Channels.linkMembers[category] and Channels.linkFilter or category]=true
  end
  -- A custom category with the internal filter's name must stay independent.
  for _,value in ipairs(categories or {}) do
    if Channels.category(value)==Channels.linkFilter then return Channels.tabOrder(order),false end
  end
  local function add(value)
    local category=Channels.category(value)
    if Channels.linkMembers[category] then category=Channels.linkFilter end
    if available[category] and not seen[category] then result[#result+1]=category; seen[category]=true end
  end
  for _,value in ipairs(preferred or {}) do add(value) end
  for _,value in ipairs(order or {}) do add(value) end
  return result,true
end

function Channels.category(value)
  local key=tostring(value or ""):upper():match("^%s*(.-)%s*$")
  return aliases[key] or key
end

local function validLinkSuffix(value)
  return value=="" or value:match("^%s+%[%s*r%-%d+%s*%]$")~=nil
end
function Channels.entryCategory(entry)
  local raw=tostring(type(entry)=="table" and entry.category or ""):upper():match("^%s*(.-)%s*$")
  if linkCategories[raw] then
    local line=tostring(entry.line or ""):gsub("\27%[[0-?]*[ -/]*[@-~]",""):match("^%s*(.-)%s*$")
    local _,kind,_,suffix=line:match("^You pick up "..activeName.."'s (%a+) link, \"(.*)\"(.*)$")
    if kind and validLinkSuffix(suffix) then
      local named={Dragon="DRAGON",Secian="SECIAN",Psycian="PSYCIAN",mental="MENTAL"}
      if named[kind] then return named[kind] end
    end
    local listener,speaker,message,tail=line:match("^"..activeName.." picks up "..activeName.."'s mental link, \"(.*)\"(.*)$")
    if listener and speaker and message and validLinkSuffix(tail) then return "MENTAL" end
  end
  return Channels.category(raw)
end
function Channels.project(entry)
  if type(entry)~="table" then return entry end
  local category=Channels.entryCategory(entry)
  if category==entry.category then return entry end
  -- Presentation migration only: never rewrite a saved message or its text.
  local projected={}
  for key,value in pairs(entry) do projected[key]=value end
  projected.category=category
  return projected
end

function Channels.mentalKind(entry)
  if type(entry)~="table" or Channels.entryCategory(entry)~="MENTAL" then return nil end
  local line=tostring(entry.line or ""):gsub("\27%[[0-?]*[ -/]*[@-~]",""):match("^%s*(.-)%s*$")
  if line:match("^"..activeName..' %(ESP%): "(.*)"$') then return "esp" end
  if line:match("^"..activeName..' thinks to you, "(.*)"$') then return "contact" end
  local speaker,body,tail=line:match("^You pick up "..activeName.."'s thoughts, \"(.*)\"(.*)$")
  if speaker and body and validLinkSuffix(tail) then return "contact" end
  if line:match("^You pick up "..activeName.."'s thoughts echoing through the area, \"(.*)\"$") then return "contact" end
  speaker,body,tail=line:match("^You pick up "..activeName.."'s mental link, \"(.*)\"(.*)$")
  if speaker and body and validLinkSuffix(tail) then return "link" end
  local listener
  listener,speaker,body,tail=line:match("^"..activeName.." picks up "..activeName.."'s mental link, \"(.*)\"(.*)$")
  if listener and speaker and body and validLinkSuffix(tail) then return "link" end
  -- Older records may identify their source without carrying the full game line.
  local raw=tostring(entry.category or ""):upper():match("^%s*(.-)%s*$")
  if raw=="ESP" then return "esp" end
  if raw=="CONTACT" then return "contact" end
  return nil
end

function Channels.tabOrder(values)
  local result,seen={},{}
  for _,value in ipairs(type(values)=="table" and values or {}) do
    local key=Channels.category(value)
    if key~="" and #key<=32 and key:match("^[A-Z][A-Z0-9 _%-]*$") and key~="OWN" and key~="WHISPER" and not seen[key] then
      result[#result+1]=key; seen[key]=true
    end
  end
  return result
end

function Channels.allSources(values)
  values=type(values)=="table" and values or {}
  local result={}
  for key,value in pairs(values) do result[key]=value end
  -- A merged source stays enabled when either previous source was enabled.
  -- An explicit new choice always wins, including a saved OFF.
  if result.MENTAL==nil then result.MENTAL=values.ESP~=false or values.CONTACT~=false end
  if result.PSYCIAN==nil then result.PSYCIAN=values.ESP~=false end
  result.ESP=nil; result.CONTACT=nil
  for _,key in ipairs(Channels.sourceOrder) do
    if result[key]==nil then result[key]=key~="COMBAT" end
  end
  return result
end
function Channels.inAll(category,sources)
  if type(sources)~="table" then return true end
  local key=Channels.category(category)
  if key=="OWN" then key="ROOM" end
  local value=sources[key]
  if key=="MENTAL" and value==nil then value=sources.ESP~=false or sources.CONTACT~=false end
  if key=="PSYCIAN" and value==nil then value=sources.ESP end
  return value==nil or value==true
end

return Channels
