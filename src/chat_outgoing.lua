local Outgoing={}
Outgoing.__index=Outgoing
Outgoing.MAX_COMMAND=4096
Outgoing.MAX_MESSAGE=2000
Outgoing.MAX_TARGET=64
Outgoing.MAX_CHARACTER=128
Outgoing.MAX_PENDING=32
Outgoing.EXPIRY_SECONDS=5

local function trim(value)
  return value:match("^ *(.-) *$")
end

function Outgoing.character(value)
  if type(value)~="string" or #value>Outgoing.MAX_CHARACTER or value:find("%c") then return nil end
  value=trim(value)
  if value=="" or value:lower()=="unknown" or not value:match("^[%a][%w_%-' ]*$") then return nil end
  return value
end

function Outgoing.serverName(character,data)
  character=Outgoing.character(character)
  local status=type(data)=="table" and type(data.Char)=="table" and data.Char.Status
  if not character or type(status)~="table" then return nil end
  local name=Outgoing.character(status.name)
  local surname=status.surname
  if surname==nil then surname="" end
  if not name or type(surname)~="string" or #surname>Outgoing.MAX_CHARACTER or surname:find("%c") then return nil end
  surname=trim(surname)
  -- The server's independent identity must verify the whole provider name.
  -- Never infer a short identity by splitting an arbitrary full name.
  local full=Outgoing.character(name..(surname~="" and " "..surname or ""))
  return full==character and name or nil
end

function Outgoing.parse(command,character,now)
  -- Observe only complete CONTACT requests. Reject controls before trimming so
  -- login text, pasted command batches and terminal escapes never enter logs.
  character=Outgoing.character(character)
  if not character or type(command)~="string" or #command>Outgoing.MAX_COMMAND or command:find("%c") then return nil end
  local verb,target,message=command:match("^ *([%a]+) +([%a][%w_%-']*) +(.+)$")
  if not verb or verb:lower()~="contact" or #target>Outgoing.MAX_TARGET or target:lower()=="help" then return nil end
  message=trim(message)
  if message=="" or #message>Outgoing.MAX_MESSAGE then return nil end
  local kind=target:lower()
  if kind=="all" or kind=="room" then target=kind end
  if type(now)~="string" or now=="" or #now>64 or now:find("%c") then now=os.date("%Y-%m-%dT%H:%M:%S%z") end
  return {schema=1,timestamp=now,character=character,category="MENTAL",
    speaker=character,target=target,message=message,source="outgoing",
    line="You -> "..target.." (outgoing request): "..message}
end

local function clock(value)
  value=tonumber(value)
  if not value or value~=value or value==math.huge or value==-math.huge then return os.time() end
  return value
end

function Outgoing.new()
  return setmetatable({pending={}},Outgoing)
end

function Outgoing:clear()
  self.pending={}
end

function Outgoing:prune(epoch,character)
  local now=clock(epoch)
  local retained={}
  for _,request in ipairs(self.pending) do
    local age=now-request.epoch
    if request.character==character and age>=0 and age<=Outgoing.EXPIRY_SECONDS then retained[#retained+1]=request end
  end
  self.pending=retained
  return now
end

function Outgoing:record(entry,epoch,serverName)
  local now=self:prune(epoch,entry.character)
  if #self.pending>=Outgoing.MAX_PENDING then table.remove(self.pending,1) end
  self.pending[#self.pending+1]={character=entry.character,target=entry.target,message=entry.message,epoch=now,serverName=Outgoing.character(serverName)}
end

local activeName="([%w_%-'][%w_%-%' ]*)"
local function broadcast(entry)
  if type(entry)~="table" or entry.category~="MENTAL" or entry.source~="builtin" or type(entry.line)~="string" or #entry.line>Outgoing.MAX_COMMAND then return nil end
  local line=entry.line:gsub("\27%[[0-?]*[ -/]*[@-~]",""):match("^%s*(.-)%s*$")
  local speaker,body=line:match("^You pick up "..activeName.."'s thoughts echoing through the area, \"(.*)\"$")
  if speaker then return "room",speaker,body end
  local suffix
  speaker,body,suffix=line:match("^You pick up "..activeName.."'s thoughts, \"(.*)\"(.*)$")
  if speaker and (suffix=="" or suffix:match("^%s+%[%s*r%-%d+%s*%]$")) then return "all",speaker,body end
end

function Outgoing:reconcile(entry,character,epoch,serverName)
  character=Outgoing.character(character)
  if not character then self:clear(); return false end
  serverName=Outgoing.character(serverName)
  self:prune(epoch,character)
  local target,speaker,body=broadcast(entry)
  -- Exact verified identity and body, plus known broadcast wording, are required.
  -- Direct messages, ESP, links, other speakers and custom frames stay visible.
  if not target or entry.speaker~=speaker or entry.message~=body or (entry.character and entry.character~=character) or entry.target~=nil then return false end
  for index,request in ipairs(self.pending) do
    local ownSpeaker=speaker==character or (serverName and speaker==serverName and request.serverName==serverName)
    if ownSpeaker and request.target==target and request.message==body then
      table.remove(self.pending,index)
      return true
    end
  end
  return false
end

return Outgoing
