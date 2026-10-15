local Visibility={}; Visibility.__index=Visibility
local Parser=require("command_parser")
local MAX_LINES,MAX_BYTES,DEFAULT_TIMEOUT=64,16384,300

function Visibility.clean(line)
  return tostring(line or ""):gsub("\27%[[0-?]*[ -/]*[@-~]",""):gsub("\7",""):match("^%s*(.-)%s*$")
end
function Visibility.content(line)
  return Visibility.clean(line):gsub("^%[%d+%]%s+%d+/%d+%s+hp,%s+%d+/%d+%s+ftg%s*>%s*",""):gsub("^>%s*","")
end
local function name(value)
  if type(value)~="string" then return nil end
  value=value:match("^%s*(.-)%s*$"):gsub("%s+"," "):lower()
  if value=="" then return nil end
  return value
end
-- Identity comes from the current session, never from the INFO being checked.
-- Providers may return a name string, name/full_name (or name/surname) table,
-- or name, full_name.
function Visibility.selfIdentity(provider)
  if type(provider)~="function" then return nil end
  local ok,value,full=pcall(provider)
  if not ok then return nil end
  local short
  if type(value)=="table" then
    value=value.character or value
    short=name(value.name); full=name(value.full_name)
    local surname=name(value.surname)
    if not full and short and surname then full=short.." "..surname end
    if not full and short and short:find(" ",1,true) then full=short end
  elseif type(value)=="string" then
    short=name(value); full=name(full)
    if short and short:find(" ",1,true) and not full then full=short; short=nil end
  end
  if not short and not full then return nil end
  return {name=short or full:match("^%S+"),full_name=full}
end
function Visibility.sameSelf(a,b)
  if not a or not b then return a==b end
  if a.full_name and b.full_name then return a.full_name==b.full_name end
  return a.name==b.name
end
function Visibility.infoOwned(parsed,identity,allowUnknown)
  if not identity then return allowUnknown==true end
  local full=type(parsed)=="table" and type(parsed.character)=="table" and name(parsed.character.full_name)
  if not full then return false end
  if identity.full_name then return full==identity.full_name end
  return full==identity.name or full:match("^%S+")==identity.name
end
function Visibility.now(self)
  return (self.adapter and self.adapter.epoch and self.adapter:epoch()) or os.time()
end

-- Shared bounded reconstruction for unsolicited, wrapped INFO. Every biography
-- line stays quarantined until its terminal prompt, including foreign conditions.
function Visibility.observeInfo(self,line,source,observeInfo)
  local plain=Visibility.clean(line); local content=Visibility.content(plain)
  if observeInfo==false then self.pending_info=nil; self.info_discard=nil; return true end
  local header=content:match('^You are %a[^,"]-,')
  local pending=self.pending_info
  if pending then
    if header or #pending.lines>=MAX_LINES or pending.bytes+#plain>MAX_BYTES
        or Visibility.now(self)-pending.timestamp>(self.stale_after or DEFAULT_TIMEOUT) then
      self.pending_info=nil; self.info_discard=true
    else
      pending.lines[#pending.lines+1]=plain; pending.bytes=pending.bytes+#plain
      if Parser.isPrompt(plain) then
        self.pending_info=nil
        local ok,parsed=pcall(Parser.parseInfo,pending.lines)
        return true,ok and parsed or nil,pending.source
      end
      return true
    end
  elseif not self.info_discard and header then
    if #content<=MAX_BYTES then
      self.pending_info={lines={content},bytes=#content,timestamp=Visibility.now(self),source=source or "output"}
    else self.info_discard=true end
    return true
  end
  if self.info_discard then
    if Parser.isPrompt(plain) then self.info_discard=nil end
    return true
  end
  return false
end

local notices={
  ["You slip into the shadows!"]="hidden",
  ["You are already unable to be seen!"]="hidden",
  ["You are hidden."]="hidden",
  ["You are invisible."]="hidden",
  ["You are now invisible."]="hidden",
  ["You are no longer invisible."]="visible",
  ["You reveal yourself!"]="visible",
  ["You are visible."]="visible",
}
local function quotedContinuation(self,line)
  local content=Visibility.content(line)
  if self.quote_guard then
    local closed=self.quote_guard=="'" and content:match("'%s*[.!?]?$")
      or (self.quote_guard~="prompt" and self.quote_guard~="'" and content:find(self.quote_guard,1,true))
    if Parser.isPrompt(Visibility.clean(line)) or closed then
      self.quote_guard=nil
    end
    return true
  end
  -- A wrapped speech/chat body may itself be an exact self sentence. Keep only
  -- its delimiter (no chat data) until the closing quote or server prompt.
  if content:match("^%[[A-Z_]+%]") then self.quote_guard="prompt"; return true end
  local tail
  for _,verb in ipairs({"say","says","tells","reads","whispers","thinks","asks","shouts","yells"}) do
    tail=content:match("%f[%a]"..verb.."%f[%A](.*)$")
    if tail then break end
  end
  if tail then
    local first=tail:find('"',1,true); local delimiter='"'
    if not first then first=tail:find("'",1,true); delimiter="'" end
    if not first then first=tail:find("“",1,true); delimiter="”" end
    if not first then first=tail:find("‘",1,true); delimiter="’" end
    local closed=first and (delimiter=="'" and tail:sub(first+1):match("'%s*[.!?]?$")
      or (delimiter~="'" and tail:find(delimiter,first+1,true)))
    if first and not closed then self.quote_guard=delimiter; return true end
  end
  return false
end
local function infoStatus(text)
  text=text:gsub("%s+"," "):match("^%s*(.-)%s*$")
  -- INFO conditions are self sentences. Quotes, NPC/chat text and unfinished
  -- tails cannot turn a matching substring into a confirmed condition.
  if text:find('["“”‘’:]') then return nil end
  local found
  while text~="" do
    local sentence,tail=text:match("^([^.!?]+[.!?])%s*(.*)$")
    if not sentence or not (sentence:match("^You are ") or sentence:match("^You're ")
        or sentence:match("^Your thirst is ") or sentence=="You reveal yourself!") then return nil end
    local status=notices[sentence]
    if status then
      if found and found~=status then return nil end
      found=status
    end
    text=tail
  end
  return found
end
function Visibility.new(adapter,onChange,selfProvider)
  return setmetatable({adapter=adapter,onChange=onChange,selfProvider=selfProvider,
    identity=Visibility.selfIdentity(selfProvider),state={status="unknown"},stale_after=DEFAULT_TIMEOUT},Visibility)
end
function Visibility:reset()
  local discard=self.pending_info~=nil or self.info_discard
  self.pending_info=nil; self.info_discard=discard or nil; self.state={status="unknown"}
  self.identity=Visibility.selfIdentity(self.selfProvider)
  if self.onChange then self.onChange(self:status()) end
  return true
end
function Visibility:syncSelf()
  local identity=Visibility.selfIdentity(self.selfProvider)
  if not Visibility.sameSelf(self.identity,identity) then
    self:reset()
  else self.identity=identity end
end
function Visibility:setStaleAfter(seconds)
  seconds=tonumber(seconds)
  if not seconds or seconds<=0 or seconds~=seconds or seconds==math.huge then return false end
  self.stale_after=seconds; return true
end
function Visibility:apply(status,source)
  self.state={status=status,timestamp=Visibility.now(self),source=source or "output"}
  if self.onChange then self.onChange(self:status()) end
  return true
end
function Visibility:onInfo(parsed,source)
  self:syncSelf()
  if type(parsed)~="table" or type(parsed.condition_text)~="string"
      or #parsed.condition_text>MAX_BYTES or not Visibility.infoOwned(parsed,self.identity,false) then return false end
  self.pending_info=nil; self.info_discard=nil
  self.quote_guard=nil
  local status=infoStatus(parsed.condition_text)
  -- Even a fresh, complete self biography without hidden does not prove visible.
  if not status then return false end
  return self:apply(status,source or "info")
end
function Visibility:onLine(line,source,observeInfo)
  self:syncSelf()
  if self.selfProvider and not self.identity then return false end
  if not self.pending_info and not self.info_discard and quotedContinuation(self,line) then return false end
  local handled,parsed,infoSource=Visibility.observeInfo(self,line,source,observeInfo)
  if handled then return parsed and self:onInfo(parsed,infoSource) or false end
  local status=notices[Visibility.content(line)]
  if not status then return false end
  return self:apply(status,source)
end
function Visibility:status()
  self:syncSelf()
  local state=self.state
  return {status=state.status,timestamp=state.timestamp,source=state.source,
    stale=state.timestamp~=nil and Visibility.now(self)-state.timestamp>=self.stale_after or false}
end
return Visibility
