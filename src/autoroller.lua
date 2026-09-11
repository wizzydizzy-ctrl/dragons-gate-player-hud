local Roller={}; Roller.__index=Roller
local order={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP","MP"}
local legacyOrder={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"}
local creatorFirst={"STR","INT","WIS","DEX","AGI","CON"}
local creatorSecond={"CHA","WIL","VOI","PER","APP","MP"}
local ranks={awful=1,poor=2,low=3,aver=4,average=4,fair=5,good=6,great=7}
local maximumTotal=#order*7

local function copy(value)
  if type(value)~="table" then return value end; local out={}; for k,v in pairs(value) do out[k]=copy(v) end; return out
end
local function trim(value) return tostring(value or ""):match("^%s*(.-)%s*$") end
local function limit(value) value=tonumber(value); return value and value>=1 and value==math.floor(value) and value or nil end
local function cleanLine(line) return tostring(line or ""):gsub("\27%[[%d;]*m","") end
local function words(line)
  local text=cleanLine(line)
  local out={}; for word in text:gmatch("%a+") do out[#out+1]=word end; return out
end
local function headerMatches(line,names)
  local found=words(line); if #found~=#names then return false end
  for index,name in ipairs(names) do if found[index]:upper()~=name then return false end end
  return true
end
local function rankValues(line,count)
  local found=words(line); if #found~=count then return nil end
  local out={}; for index,word in ipairs(found) do local value=ranks[word:lower()]; if not value then return nil end; out[index]=value end
  return out
end
local function statText(stats)
  local out={}; for _,name in ipairs(order) do if stats[name]~=nil then out[#out+1]=name.." "..tostring(stats[name]) end end; return table.concat(out,"  ")
end
local function autoStartEnabled(config) return config.auto_start_on_name~=false end
local function promptProtocol(line)
  local lower=trim(cleanLine(line)):lower():gsub("^>%s*","")
  if lower:match("^reroll%s+done%s+%?%s*help%s*$") then return "creator" end
  if lower:match("use%s+this%s+body%s*%?%s*y%s*,%s*n") then return "legacy" end
  return nil
end
local function rerollCommand(protocol) return protocol=="creator" and "reroll" or "n" end
local function acceptanceCommand(protocol) return protocol=="creator" and "done" or "y" end

function Roller.new(adapter,settings,onConfig)
  local config=copy(settings or {})
  -- Older DGHUD releases persisted "n" for the retired body prompt. The new
  -- creator uses a named command; normalize the old value without losing any
  -- of the player's score or logging preferences.
  if trim(config.reroll_command):lower()~="reroll" then config.reroll_command="reroll" end
  for _,key in ipairs({"target_total","hard_stop","max_rolls"}) do if config[key]==false then config[key]=nil end end
  config.min_stats=copy(config.min_stats or {}); for _,key in ipairs(order) do if config.min_stats[key]==false then config.min_stats[key]=nil end end
  local self=setmetatable({adapter=adapter,cfg=config,onConfig=onConfig},Roller); self:reset(); return self
end
function Roller:echo(message) if self.adapter.reportRoller then self.adapter:reportRoller(message) end end
function Roller:reset()
  if self.state and self.state.log and self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log) end
  self.state={active=false,rolls=0,sum=0,last=nil,best=nil,worst=nil,expected=nil,partial=nil,pending_stats=nil,passive_lines=0,protocol=nil,fresh_roll=false,timer=nil,log=nil}; return true
end
function Roller:log(message)
  if not self.state.log or not self.adapter.appendRollerLog then return end
  local called,ok,err=pcall(self.adapter.appendRollerLog,self.adapter,self.state.log,message)
  if not called or not ok then self:echo("Logging stopped: "..tostring((not called and ok) or err or "write failed")); if self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log) end; self.state.log=nil end
end
function Roller:minimumFailures(stats)
  local out={}; if self.cfg.use_min_stats~=true then return out end
  for _,name in ipairs(order) do local needed=tonumber((self.cfg.min_stats or {})[name]); if needed and stats[name]~=nil and stats[name]<needed then out[#out+1]=name.." "..stats[name].."<"..needed end end
  return out
end
function Roller:qualified(roll)
  local hard=limit(self.cfg.hard_stop); if hard and roll.total>=hard then return true,"hard stop "..hard end
  local target=limit(self.cfg.target_total); if not target or roll.total<target then return false,"below target "..tostring(target or "disabled") end
  local failures=self:minimumFailures(roll.stats); if self.cfg.require_min_stats_to_stop~=false and #failures>0 then return false,table.concat(failures,", ") end
  return true,"target "..target
end
function Roller:start()
  if self.state.active then self:echo("Already running."); return true end
  if self.adapter.standaloneRollerPresent and self.adapter:standaloneRollerPresent() then if not self.state.conflict_warned then self:echo("Built-in roller paused: the standalone og-dg-roller package is active. Disable or uninstall that package before using DGHUD's roller."); self.state.conflict_warned=true end; return nil,"standalone roller conflict" end
  self:reset(); self.state.active=true
  if self.cfg.logging_enabled~=false and self.adapter.startRollerLog then local ok,log,err=pcall(self.adapter.startRollerLog,self.adapter,self.cfg); if ok then self.state.log=log; if not log then self:echo("Logging unavailable: "..tostring(err or "unknown error")) end else self:echo("Logging unavailable: "..tostring(log)) end end
  self:log("Started")
  self:echo("Started — target "..tostring(limit(self.cfg.target_total) or "disabled").." / "..maximumTotal.." (12 characteristics including MP)."); return true
end
function Roller:stop(reason)
  self.state.active=false; if self.state.timer then pcall(self.adapter.cancelTimer,self.adapter,self.state.timer); self.state.timer=nil end
  self:report(reason or "Stopped"); self:log(reason or "Stopped")
  if self.state.log and self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log); self.state.log=nil end
  return true
end
function Roller:rollText(roll) return "Roll #"..roll.roll.."  Total="..roll.total.."/"..roll.maximum.."  "..statText(roll.stats) end
function Roller:report(reason)
  local s=self.state; local lines={reason or "Roller statistics","Rolls: "..s.rolls.."  Average: "..string.format("%.2f",s.rolls>0 and s.sum/s.rolls or 0)}
  if s.best then lines[#lines+1]="Best: "..self:rollText(s.best) end; if s.worst then lines[#lines+1]="Worst: "..self:rollText(s.worst) end; self:echo(table.concat(lines,"\n")); return true
end
function Roller:record(stats,protocol,names)
  local total=0; for _,name in ipairs(names) do local value=stats[name]; if not value then return false end; total=total+value end
  local s=self.state; s.rolls=s.rolls+1; s.sum=s.sum+total
  local roll={roll=s.rolls,total=total,maximum=#names*7,stats=copy(stats),protocol=protocol}; s.last=roll
  if not s.best or total>s.best.total then s.best=roll end; if not s.worst or total<s.worst.total then s.worst=roll end
  s.fresh_roll=true; s.expected=nil; s.partial=nil; local text=self:rollText(roll); if self.cfg.show_every_roll~=false then self:echo(text) end; self:log(text); return true
end
function Roller:beginBlock(protocol,names,resetPartial)
  if not self.state.active then return false end
  local s=self.state; s.protocol=protocol; s.fresh_roll=false; s.expected=names
  if resetPartial then if s.timer then pcall(self.adapter.cancelTimer,self.adapter,s.timer); s.timer=nil end; s.partial={}
  elseif type(s.partial)~="table" then s.partial={} end
  return true
end
function Roller:captureExpected(line)
  local s=self.state; if type(s.expected)~="table" then return false end
  local values=rankValues(line,#s.expected)
  if not values then
    if trim(line)~="" then s.expected=nil; s.partial=nil; s.fresh_roll=false end
    return false
  end
  for index,name in ipairs(s.expected) do s.partial[name]=values[index] end
  local protocol=s.protocol; s.expected=nil
  if protocol=="legacy" then return self:record(s.partial,protocol,legacyOrder) end
  local complete=true; for _,name in ipairs(order) do if s.partial[name]==nil then complete=false; break end end
  if complete then
    if not s.active then s.pending_stats=copy(s.partial); s.passive_lines=0; s.expected=nil; s.partial=nil; return true end
    return self:record(s.partial,protocol,order)
  end
  return true
end
function Roller:reroll(protocol)
  if self.state.timer then return true end
  local delay=math.max(0,tonumber(self.cfg.reroll_delay) or 0); local command=rerollCommand(protocol)
  local called,id,err=pcall(self.adapter.schedule,self.adapter,delay,function()
    self.state.timer=nil
    if self.state.active then local sentCall,sent,sendErr=pcall(self.adapter.sendCommand,self.adapter,command); if not sentCall or sent==false or (sent==nil and sendErr~=nil) then self:stop("Could not send reroll: "..tostring((not sentCall and sent) or sendErr or "send failed")) end end
  end)
  if not called then err=id or "timer unavailable"; id=nil end
  if not id then self:stop("Could not schedule reroll: "..tostring(err)); return nil,err end; self.state.timer=id; return true
end
function Roller:onLine(line)
  line=tostring(line or "")
  if line:match("Name%s*:%s*.-%s+Race%s*:%s*%S+") then if autoStartEnabled(self.cfg) and not self.state.active then return self:start() end; return self.state.active end

  -- Passively collect the new split layout, then auto-start only after its
  -- unique decision prompt confirms Roll in place. This avoids taking over
  -- INFO output or another characteristic-assignment method.
  if headerMatches(line,creatorFirst) then
    if not self.state.active and not autoStartEnabled(self.cfg) then return false end
    if not self.state.active then self.state.protocol="creator"; self.state.fresh_roll=false; self.state.expected=creatorFirst; self.state.partial={}; self.state.pending_stats=nil; self.state.passive_lines=0; return true end
    return self:beginBlock("creator",creatorFirst,true)
  end
  if headerMatches(line,creatorSecond) then
    if not self.state.active and not (autoStartEnabled(self.cfg) and self.state.protocol=="creator" and type(self.state.partial)=="table") then return false end
    if not self.state.active then self.state.expected=creatorSecond; return true end
    return self:beginBlock("creator",creatorSecond,false)
  end
  if (self.state.active or (autoStartEnabled(self.cfg) and self.state.protocol=="creator")) and self:captureExpected(line) then return true end

  local protocol=promptProtocol(line)
  if protocol=="creator" and not self.state.active and autoStartEnabled(self.cfg) and self.state.pending_stats then
    local pending=copy(self.state.pending_stats); local started,err=self:start(); if not started then return started,err end
    self:record(pending,"creator",order)
  end
  if not self.state.active and self.state.pending_stats then
    local lower=trim(cleanLine(line)):lower(); self.state.passive_lines=(self.state.passive_lines or 0)+1
    if self.state.passive_lines>8 or lower:match("step%s+8%s+of%s+10") or lower:find("dragon's gate menu",1,true) then self.state.pending_stats=nil; self.state.protocol=nil; self.state.passive_lines=0 end
  end
  if not self.state.active then return false end
  if headerMatches(line,legacyOrder) then return self:beginBlock("legacy",legacyOrder,true) end
  if protocol then
    local roll=self.state.last; if not roll or not self.state.fresh_roll or roll.protocol~=protocol then return false end
    self.state.fresh_roll=false; local cap=limit(self.cfg.max_rolls); if cap and self.state.rolls>=cap then return self:stop("Reached max rolls "..cap) end
    local ok,reason=self:qualified(roll); if ok then self:echo("TARGET HIT — prompt left waiting for manual "..acceptanceCommand(protocol)..".\n"..self:rollText(roll)); return self:stop(reason) end
    return self:reroll(protocol)
  end
  local lower=trim(line):lower()
  if self.state.protocol=="creator" and (lower=="done" or lower=="> done" or lower:match("step%s+8%s+of%s+10")) then return self:stop("Character creation continued") end
  return false
end
function Roller:set(key,value)
  key=trim(key):upper(); value=trim(value); local values
  if key=="TOTAL" then values={target_total=value}
  elseif key=="HARD" then values={hard_stop=value}
  elseif key=="MAX" then values={max_rolls=value}
  elseif key=="DELAY" then values={reroll_delay=value}
  elseif ranks[key:lower()] then return nil,"use a stat name, not a rank"
  else
    local valid=false; for _,name in ipairs(order) do if key==name then valid=true end end; if not valid then return nil,"unknown roller setting" end
    local enable=true; if value:lower()=="off" then enable=false; for _,name in ipairs(order) do if name~=key and (self.cfg.min_stats or {})[name] then enable=true; break end end end
    values={use_min_stats=enable,min_stats={[key]=value}}
  end
  local ok,err=self:configure(values,true); if not ok then return nil,err end
  local shown=key=="TOTAL" and self.cfg.target_total or key=="HARD" and self.cfg.hard_stop or key=="MAX" and self.cfg.max_rolls or key=="DELAY" and self.cfg.reroll_delay or (self.cfg.min_stats or {})[key]
  self:echo("Set "..key.." to "..tostring(shown or "off")); return true
end
function Roller:configure(values,silent)
  values=type(values)=="table" and values or {}; local candidate=copy(self.cfg); candidate.reroll_command="reroll"
  local numeric={{"target_total",1,maximumTotal,true},{"hard_stop",1,maximumTotal,true},{"max_rolls",1,nil,true},{"reroll_delay",0,nil,false}}
  for _,spec in ipairs(numeric) do
    local key,min,max,optional=spec[1],spec[2],spec[3],spec[4]; local raw=values[key]
    if raw~=nil then
      raw=trim(raw); local off=optional and (raw=="" or raw:lower()=="off"); local number=tonumber(raw)
      if off then candidate[key]=nil
      elseif not number or number~=number or number==math.huge or number==-math.huge or number<min or (max and number>max) or (key~="reroll_delay" and number~=math.floor(number)) then return nil,key.." is invalid" else candidate[key]=number end
    end
  end
  if values.reroll_command~=nil then local command=trim(values.reroll_command):lower(); if command~="reroll" then return nil,"reroll command must remain reroll" end; candidate.reroll_command=command end
  for _,key in ipairs({"auto_start_on_name","use_min_stats","require_min_stats_to_stop","show_every_roll","logging_enabled"}) do if values[key]~=nil then if type(values[key])~="boolean" then return nil,key.." must be true or false" end; candidate[key]=values[key] end end
  for _,key in ipairs({"log_folder","master_file"}) do if values[key]~=nil then local value=trim(values[key]); if value=="" or value=="." or value==".." or not value:match("^[%w%._%-]+$") then return nil,key.." must be a safe name without a path" end; candidate[key]=value end end
  candidate.min_stats=copy(candidate.min_stats or {})
  for _,key in ipairs(order) do if values.min_stats and values.min_stats[key]~=nil then local raw=trim(values.min_stats[key]); local number=tonumber(raw); if raw=="" or raw:lower()=="off" then candidate.min_stats[key]=nil elseif not number or number<1 or number>7 or number~=math.floor(number) then return nil,key.." minimum must be 1-7 or off" else candidate.min_stats[key]=number end end end
  if not candidate.target_total and not candidate.hard_stop and not candidate.max_rolls then return nil,"enable a target, hard stop, or maximum rolls" end
  if candidate.use_min_stats then local any=false; for _,key in ipairs(order) do if candidate.min_stats[key] then any=true; break end end; if not any then return nil,"enable at least one stat minimum or turn minimums off" end end
  if self.onConfig then local saved,err=self.onConfig(copy(candidate)); if saved==nil or saved==false then return nil,err or "could not save settings" end end
  self.cfg=candidate; if not silent then self:echo("Settings saved.") end; return true
end
function Roller:command(action)
  action=trim(action); local lower=action:lower()
  if lower=="start" then return self:start() elseif lower=="stop" then return self:stop("Manual stop") elseif lower=="stats" then return self:report("Roller statistics") elseif lower=="last" then if self.state.last then self:echo(self:rollText(self.state.last)) else self:echo("No roll captured yet.") end; return true elseif lower=="reset" then self:reset(); self:echo("Reset complete."); return true end
  local key,value=action:match("^[Ss][Ee][Tt]%s+(%S+)%s+(%S+)%s*$"); if key then local ok,err=self:set(key,value); if not ok then self:echo(err) end; return ok,err end
  self:echo("Commands: rr start|stop|stats|last|reset|help; rr set total|hard|max|delay|STAT <value>. New creation rolls all 12 characteristics including MP; rejected rolls send reroll and a target hit leaves done waiting for you."); return true
end
function Roller:shutdown() if self.state.timer then pcall(self.adapter.cancelTimer,self.adapter,self.state.timer) end; self.state.timer=nil; self.state.active=false; if self.state.log and self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log); self.state.log=nil end; return true end
Roller.order=order; Roller.ranks=ranks; Roller.maximumTotal=maximumTotal
return Roller
