local Needs={}; Needs.__index=Needs
local function clean(line) return tostring(line or ""):gsub("\27%[[%d;]*m",""):gsub("\27%[[%d;]*[A-Za-z]","") end
local function detected(line)
  local raw=clean(line); local text=raw:lower(); local hunger,thirst
  if text:find("you are satiated",1,true) then hunger="satiated"
  elseif text:find("feel like you're starving",1,true) or text:find("you are starving",1,true) then hunger="starving"
  elseif text:find("you are ravenously hungry",1,true) or text:find("you are ravenous",1,true) then hunger="ravenous"
  elseif text:find("you are hungry",1,true) or text:find("starting to feel hungry",1,true) then hunger="hungry" end
  if text:find("you are parched",1,true) then thirst="parched"
  elseif text:find("you are very thirsty",1,true) then thirst="very_thirsty"
  elseif text:find("you are thirsty",1,true) or text:find("starting to feel thirsty",1,true) then thirst="thirsty" end
  return hunger,thirst,raw
end
function Needs.new(adapter,onChange) return setmetatable({adapter=adapter,onChange=onChange,state={hunger={status="unknown"},thirst={status="unknown"}}},Needs) end
function Needs:onLine(line,source)
  local hunger,thirst,raw=detected(line); if not hunger and not thirst then return false end
  local stamp=(self.adapter and self.adapter.epoch and self.adapter:epoch()) or os.time()
  if hunger then self.state.hunger={status=hunger,timestamp=stamp,source=source or "output",raw=raw} end
  if thirst then self.state.thirst={status=thirst,timestamp=stamp,source=source or "output",raw=raw} end
  if self.onChange then self.onChange(self:status()) end; return true
end
function Needs:status() local function c(v) return {status=v.status,timestamp=v.timestamp,source=v.source,raw=v.raw} end; return {hunger=c(self.state.hunger),thirst=c(self.state.thirst)} end
Needs.detected=detected
return Needs
