local Needs={}; Needs.__index=Needs
local Parser=require("command_parser")
local function clean(line) return tostring(line or ""):gsub("\27%[[%d;]*m",""):gsub("\27%[[%d;]*[A-Za-z]","") end
local function detected(line)
  local raw=clean(line); local text=raw:lower(); local hunger,thirst
  if text:find("you are satiated",1,true) then hunger="satiated"
  elseif text:find("feel like you're starving",1,true) or text:find("you are starving",1,true) then hunger="starving"
  elseif text:find("you are ravenously hungry",1,true) or text:find("you are ravenous",1,true) then hunger="ravenous"
  elseif text:find("you are hungry",1,true) or text:find("starting to feel hungry",1,true) then hunger="hungry" end
  if text:find("your thirst is quenched.",1,true) then thirst="quenched"
  elseif text:find("you are dehydrated",1,true) then thirst="dehydrated"
  elseif text:find("you are parched",1,true) then thirst="parched"
  elseif text:find("you are very thirsty",1,true) then thirst="very_thirsty"
  elseif text:find("you are thirsty",1,true) or text:find("starting to feel thirsty",1,true) then thirst="thirsty" end
  return hunger,thirst,raw
end
function Needs.new(adapter,onChange) return setmetatable({adapter=adapter,onChange=onChange,state={hunger={status="unknown"},thirst={status="unknown"}}},Needs) end
function Needs:apply(hunger,thirst,raw,source)
  if not hunger and not thirst then return false end
  local stamp=(self.adapter and self.adapter.epoch and self.adapter:epoch()) or os.time()
  if hunger then self.state.hunger={status=hunger,timestamp=stamp,source=source or "output",raw=raw} end
  if thirst then self.state.thirst={status=thirst,timestamp=stamp,source=source or "output",raw=raw} end
  if self.onChange then self.onChange(self:status()) end; return true
end
function Needs:onInfo(parsed,source)
  -- An empty condition string is meaningful only on a complete biography.
  -- Attribute-only INFO refreshes and ordinary output must not clear warnings.
  if type(parsed)~="table" or type(parsed.condition_text)~="string" then return false end
  self.pending_info=nil
  local hunger,thirst,raw=detected(parsed.condition_text)
  return self:apply(hunger or "ok",thirst or "ok",raw,source or "info")
end
function Needs:onLine(line,source,observeInfo)
  local plain=clean(line):match("^%s*(.-)%s*$")
  local content=plain:gsub("^%[%d+%]%s+%d+/%d+%s+hp,%s+%d+/%d+%s+ftg%s*>%s*",""):gsub("^>%s*","")
  if observeInfo==false then
    -- The command collector owns this response and will apply one full snapshot.
    self.pending_info=nil
  elseif content:match('^You are %a[^,%."]-,') then
    self.pending_info=#content<=16384 and {lines={content},bytes=#content} or nil
  elseif self.pending_info then
    local pending=self.pending_info
    if #pending.lines>=64 or pending.bytes+#plain>16384 then
      self.pending_info=nil
    else
      pending.lines[#pending.lines+1]=plain; pending.bytes=pending.bytes+#plain
      if Parser.isPrompt(plain) then
        self.pending_info=nil
        local parsed=Parser.parseInfo(pending.lines)
        if self:onInfo(parsed,source or "output") then return true end
      end
    end
  end
  local hunger,thirst,raw=detected(line)
  return self:apply(hunger,thirst,raw,source)
end
function Needs:status() local function c(v) return {status=v.status,timestamp=v.timestamp,source=v.source,raw=v.raw} end; return {hunger=c(self.state.hunger),thirst=c(self.state.thirst)} end
Needs.detected=detected
return Needs
