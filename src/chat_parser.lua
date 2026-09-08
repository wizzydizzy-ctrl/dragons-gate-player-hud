local Parser={}

local name="([%w_%-']+)"
local activeName="([%w_%-'][%w_%-%' ]*)"

local function trim(value)
  if type(value)~="string" then return nil end
  value=value:match("^%s*(.-)%s*$")
  return value~="" and value or nil
end

local function plain(value)
  if type(value)~="string" then return nil end
  value=value:gsub("\27%[[0-?]*[ -/]*[@-~]","")
  return trim(value)
end

local function timestamp(now)
  if type(now)=="string" then return trim(now) or os.date("%Y-%m-%dT%H:%M:%S%z") end
  if type(now)=="number" then return os.date("%Y-%m-%dT%H:%M:%S%z",now) end
  return os.date("%Y-%m-%dT%H:%M:%S%z")
end

function Parser.category(value)
  value=tostring(value or ""):upper():match("^%s*(.-)%s*$")
  return value:match("^[A-Z][A-Z0-9_%-]*$") and value or nil
end

local function entry(category,message,metadata,character,now,source,line)
  message=trim(message)
  if not message then return nil end
  local result={
    schema=1,
    timestamp=timestamp(now),
    category=category,
    message=message,
    line=plain(line) or message,
    source=source,
  }
  local characterName=trim(character)
  if characterName then result.character=characterName end
  metadata=type(metadata)=="table" and metadata or {}
  for _,field in ipairs({"speaker","target","language"}) do
    local value=trim(metadata[field])
    if value then result[field]=value end
  end
  return result
end

local rules={
  {category="ESP",pattern='^'..name..' %(ESP%): "(.*)"$',speaker=1,message=2},
  {category="STAFF",pattern='^'..name..' %(ELDER%): "(.*)"$',speaker=1,message=2},
  {category="STAFF",pattern='^%[GUIDE%] '..name..': (.+)$',speaker=1,message=2},
  {category="STAFF",pattern='^%[GM%] '..name..': (.+)$',speaker=1,message=2},
  {category="STAFF",pattern='^'..name..' sends: (.+)$',speaker=1,message=2},
  {category="DRAGON",pattern="^You pick up "..name.."'s mental link, \"(.*)\"$",speaker=1,message=2},
  {category="DRAGON",pattern="^"..name.." picks up "..name.."'s mental link, \"(.*)\"$",speaker=2,message=3},
  {category="DRAGON",pattern="^You pick up "..name.."'s Dragon link, \"(.*)\" %[%s*r%-(%d+)%s*%]$",speaker=1,message=2},
  {category="CONTACT",pattern="^You pick up "..name.."'s thoughts echoing through the area, \"(.*)\"$",speaker=1,message=2},
}

local function builtIn(category,message,metadata,character,now,line)
  return entry(category,message,metadata,character,now,"builtin",line)
end

local function parseStaffVoice(line,character,now)
  for _,verb in ipairs({"say","ask","exclaim","shout","yell"}) do
    local speaker,target,message=line:match('^You hear the voice of '..name..' '..verb..' '..name..', "(.*)"$')
    if speaker then return builtIn("STAFF",message,{speaker=speaker,target=target},character,now,line) end
    speaker,message=line:match('^You hear the voice of '..name..' '..verb..', "(.*)"$')
    if speaker then return builtIn("STAFF",message,{speaker=speaker},character,now,line) end
  end
end

local function roomCategory(speaker,character)
  local active=trim(character)
  if active and speaker:lower()==active:lower() then return "OWN" end
  return "ROOM"
end

local function parseActiveRoom(line,character,now)
  local active=trim(character)
  if not active then return nil end
  for _,verb in ipairs({"says","asks","exclaims","shouts","yells"}) do
    local speaker,target,language,message=line:match("^"..activeName.." "..verb.." to "..name.." in (.+), \"(.*)\"$")
    if speaker and speaker:lower()==active:lower() then return builtIn("OWN",message,{speaker=speaker,target=target,language=language},character,now,line) end
    speaker,language,target,message=line:match("^"..activeName.." "..verb.." in (.+) to "..name..", \"(.*)\"$")
    if speaker and speaker:lower()==active:lower() then return builtIn("OWN",message,{speaker=speaker,target=target,language=language},character,now,line) end
    speaker,target,message=line:match("^"..activeName.." "..verb.." to "..name..", \"(.*)\"$")
    if speaker and speaker:lower()==active:lower() then return builtIn("OWN",message,{speaker=speaker,target=target},character,now,line) end
    speaker,language,message=line:match("^"..activeName.." "..verb.." in (.+), \"(.*)\"$")
    if speaker and speaker:lower()==active:lower() then return builtIn("OWN",message,{speaker=speaker,language=language},character,now,line) end
    speaker,message=line:match("^"..activeName.." "..verb..", \"(.*)\"$")
    if speaker and speaker:lower()==active:lower() then return builtIn("OWN",message,{speaker=speaker},character,now,line) end
  end
end

local function parseRoom(line,character,now)
  local activeEntry=parseActiveRoom(line,character,now)
  if activeEntry then return activeEntry end
  for _,verb in ipairs({"says","asks","exclaims","shouts","yells"}) do
    local speaker,target,language,message=line:match("^"..name.." "..verb.." to "..name.." in (.+), \"(.*)\"$")
    if speaker then return builtIn(roomCategory(speaker,character),message,{speaker=speaker,target=target,language=language},character,now,line) end
    speaker,language,target,message=line:match("^"..name.." "..verb.." in (.+) to "..name..", \"(.*)\"$")
    if speaker then return builtIn(roomCategory(speaker,character),message,{speaker=speaker,target=target,language=language},character,now,line) end
    speaker,target,message=line:match("^"..name.." "..verb.." to "..name..", \"(.*)\"$")
    if speaker then return builtIn(roomCategory(speaker,character),message,{speaker=speaker,target=target},character,now,line) end
    speaker,language,message=line:match("^"..name.." "..verb.." in (.+), \"(.*)\"$")
    if speaker then return builtIn(roomCategory(speaker,character),message,{speaker=speaker,language=language},character,now,line) end
    speaker,message=line:match("^"..name.." "..verb..", \"(.*)\"$")
    if speaker then return builtIn(roomCategory(speaker,character),message,{speaker=speaker},character,now,line) end
  end
end

function Parser.parse(line,character,now)
  line=plain(line)
  if not line then return nil end
  local staffVoice=parseStaffVoice(line,character,now)
  if staffVoice then return staffVoice end
  for _,rule in ipairs(rules) do
    local captures={line:match(rule.pattern)}
    if #captures>0 then
      return builtIn(rule.category,captures[rule.message],{speaker=captures[rule.speaker]},character,now,line)
    end
  end
  local message=line:match("^You say (.+)$")
  if message then return builtIn("OWN",message,{speaker=trim(character)},character,now,line) end
  local speaker,message=line:match("^"..name.." whispers to you, \"(.*)\"$")
  if speaker then return builtIn("WHISPER",message,{speaker=speaker,target=trim(character)},character,now,line) end
  speaker,message=line:match("^"..name.." whispers, \"(.*)\"$")
  if speaker then return builtIn("WHISPER",message,{speaker=speaker,target=trim(character)},character,now,line) end
  local target
  target,message=line:match("^You whisper to "..name..", \"(.*)\"$")
  if target then return builtIn("WHISPER",message,{speaker=trim(character),target=target},character,now,line) end
  return parseRoom(line,character,now)
end

function Parser.custom(category,text,metadata,character,now)
  category=Parser.category(category)
  if not category then return nil,"invalid chat category" end
  metadata=type(metadata)=="table" and metadata or {}
  local result=entry(category,text,metadata,character,metadata.timestamp or now,"custom",metadata.line or text)
  if not result then return nil,"chat text is empty" end
  return result
end

return Parser
