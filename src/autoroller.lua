local Roller={}; Roller.__index=Roller
local order={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP","MP"}
local legacyOrder={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"}
local oldOrder=order
local creatorFirst={"STR","INT","WIS","DEX","AGI","CON"}
local creatorSecond={"CHA","WIL","VOI","PER","APP","MP"}
local currentCreatorSecond={"CHA","WIL","VOI","PER","APP"}
local ranks={awful=1,poor=2,low=3,aver=4,average=4,fair=5,good=6,great=7,excel=7,superb=7}
local rankLabels={[1]="Awful",[2]="Poor",[3]="Low",[4]="Aver",[5]="Fair",[6]="Good",[7]="Great"}
local maximumTotal=#order*7
local arrangeOrders={[11]=legacyOrder,[12]=order}
local captureLineLimit=8
local arrangeModes={manual=true,game_auto=true,minimums=true}

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
local function parsePool(line)
  local body=trim(cleanLine(line)):match("^[Pp][Oo][Oo][Ll]%s*:%s*(.-)%s*$")
  if not body then return nil end
  if body:lower()=="(empty)" then return "empty",{} end
  local found=words(body); if #found<1 or #found>12 then return "malformed" end
  local out={}; for index,word in ipairs(found) do local value=ranks[word:lower()]; if not value then return "malformed" end; out[index]=value end
  return (#out==11 or #out==12) and "full" or "partial",out
end
local function samePool(left,right)
  if type(left)~="table" or type(right)~="table" or #left~=#right then return false end
  local counts={}
  for _,value in ipairs(left) do counts[value]=(counts[value] or 0)+1 end
  for _,value in ipairs(right) do
    if not counts[value] then return false end
    counts[value]=counts[value]-1
    if counts[value]==0 then counts[value]=nil end
  end
  return next(counts)==nil
end
local function assignmentValues(line,names)
  local found={}
  for token in cleanLine(line):gmatch("%S+") do
    local lower=token:lower()
    if lower=="--" then found[#found+1]=false
    elseif ranks[lower] then found[#found+1]=ranks[lower]
    else return nil end
  end
  if #found~=#names then return nil end
  return found
end
local function statText(stats)
  local out={}; for _,name in ipairs(order) do if stats[name]~=nil then out[#out+1]=name.." "..tostring(stats[name]) end end; return table.concat(out,"  ")
end
local function autoStartEnabled(config) return config.auto_start_on_name~=false end
local function promptProtocol(line)
  local lower=trim(cleanLine(line)):lower():gsub("^>%s*","")
  if lower:match("^<stat>%s+<label>%s+auto%s+clear%s+reroll%s+done%s+%?%s*help%s*$") then return "arrange" end
  if lower:match("^reroll%s+done%s+%?%s*help%s*$") then return "creator" end
  if lower:match("use%s+this%s+body%s*%?%s*y%s*,%s*n") then return "legacy" end
  return nil
end
local function rerollCommand(protocol) return (protocol=="creator" or protocol=="arrange") and "reroll" or "n" end
local function acceptanceCommand(protocol) return (protocol=="creator" or protocol=="arrange") and "done" or "y" end

function Roller.new(adapter,settings,onConfig)
  local config=copy(settings or {})
  -- Older DGHUD releases persisted "n" for the retired body prompt. The new
  -- creator uses a named command; normalize the old value without losing any
  -- of the player's score or logging preferences.
  if trim(config.reroll_command):lower()~="reroll" then config.reroll_command="reroll" end
  for _,key in ipairs({"target_total","hard_stop","max_rolls","minimum_greats","minimum_good_plus"}) do if config[key]==false then config[key]=nil end end
  config.arrange_mode=trim(config.arrange_mode):lower(); if not arrangeModes[config.arrange_mode] then config.arrange_mode="manual" end
  config.min_stats=copy(config.min_stats or {}); for _,key in ipairs(order) do if config.min_stats[key]==false then config.min_stats[key]=nil end end
  local self=setmetatable({adapter=adapter,cfg=config,onConfig=onConfig},Roller); self:reset(); return self
end
function Roller:echo(message) if self.adapter.reportRoller then self.adapter:reportRoller(message) end end
function Roller:cancelReroll()
  local s=self.state; if not s then return true end
  s.timer_generation=(tonumber(s.timer_generation) or 0)+1
  if s.timer then pcall(self.adapter.cancelTimer,self.adapter,s.timer) end
  s.timer=nil; return true
end
function Roller:clearCapture()
  local s=self.state; if not s then return true end
  s.expected=nil; s.partial=nil; s.pending_stats=nil; s.pending_pool=nil; s.arrangement=nil; s.passive_lines=0; s.capture_lines=0; s.protocol=nil; s.fresh_roll=false; s.awaiting_new_roll=false; s.expected_echo=nil; s.owned_outgoing=nil; return true
end
function Roller:reset()
  local timerGeneration=0
  if self.state then self:cancelReroll(); timerGeneration=tonumber(self.state.timer_generation) or 0 end
  if self.state and self.state.log and self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log) end
  self.state={active=false,rolls=0,sum=0,last=nil,best=nil,worst=nil,expected=nil,partial=nil,pending_stats=nil,pending_pool=nil,arrangement=nil,passive_lines=0,capture_lines=0,protocol=nil,fresh_roll=false,timer=nil,timer_generation=timerGeneration,auto_suppressed=false,log=nil,result_held=false,held_protocol=nil,awaiting_new_roll=false,phase="idle",expected_echo=nil,owned_outgoing=nil}; return true
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
function Roller:assignmentPlan(pool)
  local activeOrder=arrangeOrders[#pool]
  if type(pool)~="table" or not activeOrder then return nil,"the pool is incomplete" end
  local wanted={}
  if self.cfg.use_min_stats==true then
    for index,name in ipairs(activeOrder) do local needed=tonumber((self.cfg.min_stats or {})[name]); if needed then wanted[#wanted+1]={name=name,needed=needed,index=index} end end
  end
  table.sort(wanted,function(a,b) if a.needed~=b.needed then return a.needed>b.needed end; return a.index<b.index end)
  local available=copy(pool); table.sort(available,function(a,b) return a>b end); local plan={}
  for _,entry in ipairs(wanted) do
    local chosen
    for index,value in ipairs(available) do if value>=entry.needed then chosen=index; break end end
    if not chosen then return nil,entry.name.." cannot reach "..tostring(entry.needed) end
    local value=table.remove(available,chosen); plan[#plan+1]={stat=entry.name,value=value,label=rankLabels[value]}
  end
  return plan,available
end
function Roller:poolFailures(pool)
  local out={}; local greats,goodPlus=0,0
  for _,value in ipairs(pool or {}) do if value>=7 then greats=greats+1 end; if value>=6 then goodPlus=goodPlus+1 end end
  local neededGreats=limit(self.cfg.minimum_greats); if neededGreats and greats<neededGreats then out[#out+1]="Greats "..greats.."<"..neededGreats end
  local neededGoodPlus=limit(self.cfg.minimum_good_plus); if neededGoodPlus and goodPlus<neededGoodPlus then out[#out+1]="Good+ "..goodPlus.."<"..neededGoodPlus end
  local mode=self.cfg.arrange_mode or "manual"
  local needsPlan=self.cfg.use_min_stats==true and (mode=="minimums" or (mode=="manual" and self.cfg.require_min_stats_to_stop~=false))
  if needsPlan then local plan,err=self:assignmentPlan(pool); if not plan then out[#out+1]=err end end
  return out
end
function Roller:qualified(roll)
  local hard=limit(self.cfg.hard_stop); if hard and roll.total>=hard then return true,"hard stop "..hard end
  local target=limit(self.cfg.target_total); if not target or roll.total<target then return false,"below target "..tostring(target or "disabled") end
  local failures=roll.pool and self:poolFailures(roll.pool) or self:minimumFailures(roll.stats)
  if #failures>0 and (roll.pool or self.cfg.require_min_stats_to_stop~=false) then return false,table.concat(failures,", ") end
  return true,"target "..target
end
function Roller:start()
  if self.state.active then self:echo("Already running."); return true end
  if self.adapter.standaloneRollerPresent and self.adapter:standaloneRollerPresent() then if not self.state.conflict_warned then self:echo("Built-in roller paused: the standalone og-dg-roller package is active. Disable or uninstall that package before using DGHUD's roller."); self.state.conflict_warned=true end; return nil,"standalone roller conflict" end
  self:reset(); self.state.active=true; self.state.phase="observing"
  if self.cfg.logging_enabled~=false and self.adapter.startRollerLog then local ok,log,err=pcall(self.adapter.startRollerLog,self.adapter,self.cfg); if ok then self.state.log=log; if not log then self:echo("Logging unavailable: "..tostring(err or "unknown error")) end else self:echo("Logging unavailable: "..tostring(log)) end end
  self:log("Started")
  self:echo("Started — target "..tostring(limit(self.cfg.target_total) or "disabled").." / "..maximumTotal.." (11 characteristics)."); return true
end
function Roller:stop(reason,holdResult)
  local heldProtocol=self.state.protocol or self.state.held_protocol
  self.state.active=false; self:cancelReroll(); self:clearCapture(); self.state.result_held=holdResult==true; self.state.held_protocol=holdResult==true and heldProtocol or nil; self.state.phase=holdResult==true and "held" or "idle"
  self:report(reason or "Stopped"); self:log(reason or "Stopped")
  if not holdResult and self.state.log and self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log); self.state.log=nil end
  return true
end
function Roller:rollText(roll)
  if roll.pool then local labels={}; for _,value in ipairs(roll.pool) do labels[#labels+1]=rankLabels[value] end; return "Roll #"..roll.roll.."  Total="..roll.total.."/"..roll.maximum.."  Pool: "..table.concat(labels," ") end
  return "Roll #"..roll.roll.."  Total="..roll.total.."/"..roll.maximum.."  "..statText(roll.stats)
end
function Roller:report(reason)
  local s=self.state; local lines={reason or "Roller statistics","Rolls: "..s.rolls.."  Average: "..string.format("%.2f",s.rolls>0 and s.sum/s.rolls or 0)}
  if s.best then lines[#lines+1]="Best: "..self:rollText(s.best) end; if s.worst then lines[#lines+1]="Worst: "..self:rollText(s.worst) end; self:echo(table.concat(lines,"\n")); return true
end
function Roller:record(stats,protocol,names)
  local total=0; for _,name in ipairs(names) do local value=stats[name]; if not value then return false end; total=total+value end
  local s=self.state; s.rolls=s.rolls+1; s.sum=s.sum+total
  local roll={roll=s.rolls,total=total,maximum=#names*7,stats=copy(stats),protocol=protocol}; s.last=roll
  if not s.best or total>s.best.total then s.best=roll end; if not s.worst or total<s.worst.total then s.worst=roll end
  s.protocol=protocol; s.fresh_roll=true; s.expected=nil; s.partial=nil; s.capture_lines=0; s.awaiting_new_roll=false; s.phase="awaiting_prompt"; local text=self:rollText(roll); if self.cfg.show_every_roll~=false then self:echo(text) end; self:log(text); return true
end
function Roller:recordPool(pool)
  local activeOrder=arrangeOrders[#pool]; if not activeOrder then return false end
  local total=0; for _,value in ipairs(pool or {}) do if not rankLabels[value] then return false end; total=total+value end
  local s=self.state; s.rolls=s.rolls+1; s.sum=s.sum+total
  local roll={roll=s.rolls,total=total,maximum=#activeOrder*7,pool=copy(pool),protocol="arrange"}; s.last=roll
  if not s.best or total>s.best.total then s.best=roll end; if not s.worst or total<s.worst.total then s.worst=roll end
  s.protocol="arrange"; s.fresh_roll=true; s.expected=nil; s.partial=nil; s.pending_pool=nil; s.capture_lines=0; s.awaiting_new_roll=false; s.phase="awaiting_prompt"; local text=self:rollText(roll); if self.cfg.show_every_roll~=false then self:echo(text) end; self:log(text); return true
end
function Roller:beginBlock(protocol,names,resetPartial)
  if not self.state.active then return false end
  local s=self.state; s.protocol=protocol; s.fresh_roll=false; s.expected=names; s.capture_lines=0; s.awaiting_new_roll=false; s.phase="capturing"
  if resetPartial then self:cancelReroll(); s.partial={}
  elseif type(s.partial)~="table" then s.partial={} end
  return true
end
function Roller:captureExpected(line)
  local s=self.state; if type(s.expected)~="table" then return false end
  local values=rankValues(line,#s.expected)
  if not values then
    if trim(line)~="" then s.expected=nil; s.partial=nil; s.fresh_roll=false; s.capture_lines=0 end
    return false
  end
  for index,name in ipairs(s.expected) do s.partial[name]=values[index] end; s.capture_lines=0
  local protocol=s.protocol; s.expected=nil
  if protocol=="legacy" then return self:record(s.partial,protocol,legacyOrder) end
  local complete=true; for _,name in ipairs(order) do if s.partial[name]==nil then complete=false; break end end
  if complete then
    if not s.active then s.pending_stats=copy(s.partial); s.passive_lines=0; s.expected=nil; s.partial=nil; return true end
    return self:record(s.partial,protocol,order)
  end
  return true
end
function Roller:prepareForReroll(protocol)
  local s=self.state; self:cancelReroll(); s.expected=nil; s.partial=nil; s.pending_stats=nil; s.pending_pool=nil; s.arrangement=nil; s.capture_lines=0; s.passive_lines=0; s.fresh_roll=false; s.result_held=false; s.held_protocol=nil; s.protocol=protocol or s.protocol; s.awaiting_new_roll=true; s.phase="waiting_new_roll"; return true
end
function Roller:rearmForManualReroll(protocol)
  local s=self.state; local controlled=s.active or s.result_held or s.held_protocol~=nil
  if not controlled then return false end
  local previous=protocol or s.protocol or s.held_protocol or "arrange"
  if not s.active then s.active=true; s.result_held=false; s.phase="observing" end
  self:prepareForReroll(previous)
  local command=rerollCommand(previous); self.state.awaiting_new_roll=true; self.state.phase="waiting_new_roll"
  local sent,err=self:sendOwnedCommand(command); if not sent then return self:stop("Could not send manual reroll: "..tostring(err),true) end
  return true
end
function Roller:sendOwnedCommand(command)
  local s=self.state; local normalized=trim(command):lower(); s.owned_outgoing=normalized; s.expected_echo=normalized
  local called,sent,err=pcall(self.adapter.sendCommand,self.adapter,command)
  if not called or sent==false or (sent==nil and err~=nil) then if s.owned_outgoing==normalized then s.owned_outgoing=nil end; return nil,tostring((not called and sent) or err or "send failed") end
  return true
end
function Roller:onOutgoing(command)
  local normalized=trim(command):lower(); if normalized=="" then return false end
  local s=self.state
  if s.owned_outgoing==normalized then s.owned_outgoing=nil; return true end
  if normalized:match("^rr%s") or normalized=="rr" or normalized:match("^dghud%s") or normalized=="dghud" then return false end
  if normalized=="reroll" or (normalized=="n" and (s.protocol=="legacy" or s.held_protocol=="legacy")) then return self:rearmForManualReroll(normalized=="n" and "legacy" or nil) end
  if s.result_held and (normalized=="done" or normalized=="y" or normalized=="<" or normalized=="back" or normalized=="q" or normalized=="quit") then return self:stop("Character creation continued") end
  if s.active or s.timer or s.arrangement then return self:stop("Player command cancelled automatic rolling",true) end
  return false
end
function Roller:onDisconnect()
  if self.state.active or self.state.result_held or self.state.log then return self:stop("Disconnected") end
  self:cancelReroll(); self:clearCapture(); self.state.result_held=false; self.state.held_protocol=nil; self.state.phase="idle"; return true
end
function Roller:reroll(protocol)
  if self.state.timer then return true end
  local delay=math.max(0,tonumber(self.cfg.reroll_delay) or 0); local command=rerollCommand(protocol)
  self.state.timer_generation=(tonumber(self.state.timer_generation) or 0)+1; local generation=self.state.timer_generation; self.state.phase="reroll_delay"
  local called,id,err=pcall(self.adapter.schedule,self.adapter,delay,function()
    if self.state.timer_generation~=generation or self.state.phase~="reroll_delay" then return end
    self.state.timer=nil
    if self.state.active then
      self.state.awaiting_new_roll=true; self.state.phase="waiting_new_roll"; self.state.expected_echo=command
      local sent,sendErr=self:sendOwnedCommand(command); if not sent then self:stop("Could not send reroll: "..tostring(sendErr),true) end
    end
  end)
  if not called then err=id or "timer unavailable"; id=nil end
  if not id then self:stop("Could not schedule reroll: "..tostring(err)); return nil,err end; self.state.timer=id; return true
end
function Roller:sendArrangementCommand(entry)
  local sequence=self.state.arrangement; entry.confirmed=false; entry.pool_confirmed=false; entry.pool_empty=false; entry.board_complete=false; sequence.awaiting=entry
  if entry.auto then sequence.display_expected=nil; sequence.display_stats={}; sequence.auto_board_complete=false end
  local sent,err=self:sendOwnedCommand(entry.command)
  if not sent then return self:stop("Could not send arrangement command: "..tostring(err),true) end
  return true
end
function Roller:advanceArrangement()
  local sequence=self.state.arrangement; if not sequence then return false end
  local awaiting=sequence.awaiting
  if awaiting then
    if awaiting.auto then
      if not (awaiting.pool_empty and sequence.auto_board_complete) then return self:stop("Automatic placement was not fully confirmed — prompt left waiting for you",true) end
      return self:stop("Arrangement complete — prompt left waiting for manual done",true)
    end
    if not (awaiting.confirmed and awaiting.pool_confirmed) then return self:stop("Placement was not fully confirmed — prompt left waiting for you",true) end
  end
  sequence.index=sequence.index+1; local entry=sequence.commands[sequence.index]
  if not entry then return self:stop("Minimum placements complete — prompt left waiting for manual done",true) end
  return self:sendArrangementCommand(entry)
end
function Roller:beginArrangement(roll,reason)
  local mode=self.cfg.arrange_mode or "manual"
  if mode=="manual" then self:echo("TARGET HIT — pool left waiting for your placements and manual done.\n"..self:rollText(roll)); return self:stop(reason,true) end
  local commands={}
  if mode=="minimums" then
    local plan,remaining=self:assignmentPlan(roll.pool)
    if not plan then self:echo("TARGET HIT, but configured minimums cannot be placed — pool left untouched.\n"..self:rollText(roll)); return self:stop(reason,true) end
    local expectedPool=copy(roll.pool)
    for _,entry in ipairs(plan) do
      local removed=false
      for poolIndex,value in ipairs(expectedPool) do
        if value==entry.value then table.remove(expectedPool,poolIndex); removed=true; break end
      end
      if not removed then self:echo("TARGET HIT, but its placement plan no longer matches the pool — pool left untouched.\n"..self:rollText(roll)); return self:stop(reason,true) end
      commands[#commands+1]={command=entry.stat:lower().." "..entry.label:lower(),stat=entry.stat,value=entry.value,expected_pool=copy(expectedPool)}
    end
    if #remaining>0 then commands[#commands+1]={command="auto",auto=true} end
  else commands[1]={command="auto",auto=true} end
  self.state.fresh_roll=false; self.state.phase="assigning"; self.state.arrangement={mode=mode,commands=commands,index=0,awaiting=nil,display_expected=nil,display_stats={},auto_board_complete=false,order=arrangeOrders[#roll.pool] or order}
  self:echo("TARGET HIT — "..(mode=="minimums" and "placing configured minimums, then using game auto" or "using game auto").."; done remains manual.\n"..self:rollText(roll))
  return self:advanceArrangement()
end
function Roller:onLine(line)
  line=tostring(line or "")
  local lower=trim(cleanLine(line)):lower(); local bare=lower:gsub("^>%s*",""); local s=self.state
  if lower:match("step%s+7%s+of%s+10") then
    local suppressed=s.auto_suppressed; self:reset(); self.state.auto_suppressed=suppressed; return false
  end
  if s.expected_echo and bare==s.expected_echo then s.expected_echo=nil; return true end
  if bare=="reroll" and s.awaiting_new_roll then return true end
  if bare=="reroll" and (s.active or s.result_held or s.held_protocol~=nil) then return self:rearmForManualReroll() end
  if s.active then
    local protocol=s.protocol
    if ((protocol=="creator" or protocol=="arrange") and (bare=="done" or lower:match("step%s+[89]%s+of%s+10"))) or (protocol=="legacy" and bare=="y") then return self:stop("Character creation continued") end
    if protocol=="legacy" and bare=="n" then return self:rearmForManualReroll("legacy") end
    local stat,label=bare:match("^([a-z]+)%s+([a-z]+)$"); local assignment=false
    if stat and ranks[label] then for _,name in ipairs(order) do if stat==name:lower() then assignment=true; break end end end
    if protocol=="arrange" and (bare=="auto" or bare=="clear" or bare=="?" or bare=="help" or bare=="<" or bare=="back" or bare=="q" or bare=="quit" or assignment) then return self:stop("Player took control of roll placement",true) end
  end

  local poolKind,pool=parsePool(line)
  if s.arrangement then
    local sequence=s.arrangement; local awaiting=sequence.awaiting
    local stat,label=trim(cleanLine(line)):match("^([A-Za-z]+)%s+placed:%s*([A-Za-z]+)%.?$")
    if stat and awaiting and awaiting.stat and stat:upper()==awaiting.stat and ranks[label:lower()]==awaiting.value then awaiting.confirmed=true; return true end
    if headerMatches(line,creatorFirst) then sequence.display_expected=creatorFirst; sequence.display_stats={}; return true end
    if headerMatches(line,currentCreatorSecond) or headerMatches(line,creatorSecond) then sequence.display_expected=headerMatches(line,creatorSecond) and creatorSecond or currentCreatorSecond; return true end
    if sequence.display_expected then
      local names=sequence.display_expected; local values=assignmentValues(line,names); sequence.display_expected=nil
      if values then
        for index,name in ipairs(names) do sequence.display_stats[name]=values[index] end
        local activeOrder=sequence.order or order; local complete=true; for _,name in ipairs(activeOrder) do if type(sequence.display_stats[name])~="number" then complete=false; break end end
        if complete then sequence.auto_board_complete=true end
        return true
      end
    end
    if poolKind then
      if awaiting then
        if awaiting.auto then awaiting.pool_empty=poolKind=="empty"
        elseif (poolKind=="full" or poolKind=="partial" or poolKind=="empty") and samePool(pool,awaiting.expected_pool) then awaiting.pool_confirmed=true end
      end
      return true
    end
    if promptProtocol(line)=="arrange" then return self:advanceArrangement() end
    return false
  end
  if s.result_held and (bare=="done" or bare=="y" or bare=="<" or bare=="back" or bare=="q" or bare=="quit" or lower:match("step%s+[89]%s+of%s+10")) then return self:stop("Character creation continued") end
  if s.result_held then return false end
  if line:match("Name%s*:%s*.-%s+Race%s*:%s*%S+") then if autoStartEnabled(self.cfg) and not self.state.auto_suppressed and not self.state.active then return self:start() end; return self.state.active end

  if poolKind then
    if poolKind~="full" then if not s.active then s.pending_pool=nil end; return false end
    if not s.active then if not autoStartEnabled(self.cfg) or s.auto_suppressed then return false end; s.protocol="arrange"; s.pending_pool=copy(pool); s.pending_stats=nil; s.passive_lines=0; return true end
    if s.fresh_roll or (s.phase=="reroll_delay" and not s.awaiting_new_roll) then return false end
    if not (s.awaiting_new_roll or s.rolls==0 or s.phase=="observing" or s.phase=="capturing") then return false end
    self:cancelReroll(); return self:recordPool(pool)
  end

  -- Passively collect the new split layout, then auto-start only after its
  -- exact decision prompt identifies Roll in place or Roll and arrange.
  if headerMatches(line,creatorFirst) then
    if s.active and (s.protocol=="arrange" or s.fresh_roll or (s.phase=="reroll_delay" and not s.awaiting_new_roll)) then return false end
    if not s.active and (not autoStartEnabled(self.cfg) or s.auto_suppressed) then return false end
    if not s.active then s.protocol="creator"; s.fresh_roll=false; s.expected=creatorFirst; s.partial={}; s.pending_stats=nil; s.passive_lines=0; return true end
    return self:beginBlock("creator",creatorFirst,true)
  end
  if headerMatches(line,currentCreatorSecond) or headerMatches(line,creatorSecond) then
    local second=headerMatches(line,creatorSecond) and creatorSecond or currentCreatorSecond
    if s.active and s.protocol=="arrange" then return false end
    if s.active and s.protocol=="creator" and type(s.partial)~="table" then return false end
    if not s.active and not (autoStartEnabled(self.cfg) and s.protocol=="creator" and type(s.partial)=="table") then return false end
    if not s.active then s.expected=second; return true end
    return self:beginBlock("creator",second,false)
  end
  if (self.state.active or (autoStartEnabled(self.cfg) and self.state.protocol=="creator")) and self:captureExpected(line) then return true end

  local protocol=promptProtocol(line)
  if protocol=="arrange" and not self.state.active and autoStartEnabled(self.cfg) and self.state.pending_pool then
    local pending=copy(self.state.pending_pool); local started,err=self:start(); if not started then return started,err end
    self:recordPool(pending)
  end
  if protocol=="creator" and not self.state.active and autoStartEnabled(self.cfg) and self.state.pending_stats then
    local pending=copy(self.state.pending_stats); local started,err=self:start(); if not started then return started,err end
    self:record(pending,"creator",order)
  end
  if not self.state.active and (self.state.pending_stats or self.state.pending_pool) then
    self.state.passive_lines=(self.state.passive_lines or 0)+1
    if self.state.passive_lines>8 or lower:match("step%s+8%s+of%s+10") or lower:find("dragon's gate menu",1,true) then self.state.pending_stats=nil; self.state.pending_pool=nil; self.state.protocol=nil; self.state.passive_lines=0 end
  end
  if self.state.protocol=="creator" and self.state.partial and not self.state.expected and not self.state.fresh_roll and trim(cleanLine(line))~="" then
    self.state.capture_lines=(self.state.capture_lines or 0)+1
    if self.state.capture_lines>captureLineLimit then self.state.partial=nil; self.state.capture_lines=0 end
  end
  if not self.state.active then return false end
  if headerMatches(line,legacyOrder) then return self:beginBlock("legacy",legacyOrder,true) end
  if protocol then
    if self.state.partial and not self.state.fresh_roll then self.state.expected=nil; self.state.partial=nil; self.state.capture_lines=0; return false end
    local roll=self.state.last; if not roll or not self.state.fresh_roll or roll.protocol~=protocol then return false end
    self.state.fresh_roll=false; local cap=limit(self.cfg.max_rolls); if cap and self.state.rolls>=cap then return self:stop("Reached max rolls "..cap) end
    local target,hard=limit(self.cfg.target_total),limit(self.cfg.hard_stop)
    if not cap and not ((target and target<=roll.maximum) or (hard and hard<=roll.maximum)) then return self:stop("Configured total cannot be reached by this "..roll.maximum.."-point roll format") end
    local ok,reason=self:qualified(roll); if ok and protocol=="arrange" then return self:beginArrangement(roll,reason) end
    if ok then self:echo("TARGET HIT — prompt left waiting for manual "..acceptanceCommand(protocol)..".\n"..self:rollText(roll)); return self:stop(reason,true) end
    return self:reroll(protocol)
  end
  return false
end
function Roller:set(key,value)
  key=trim(key):upper(); value=trim(value); local values
  if key=="TOTAL" then values={target_total=value}
  elseif key=="HARD" then values={hard_stop=value}
  elseif key=="MAX" then values={max_rolls=value}
  elseif key=="DELAY" then values={reroll_delay=value}
  elseif key=="GREATS" then values={minimum_greats=value}
  elseif key=="GOODPLUS" or key=="GOODS" then values={minimum_good_plus=value}
  elseif key=="ARRANGE" or key=="MODE" then values={arrange_mode=value}
  elseif ranks[key:lower()] then return nil,"use a stat name, not a rank"
  else
    local valid=false; for _,name in ipairs(order) do if key==name then valid=true end end; if not valid then return nil,"unknown roller setting" end
    local enable=true; if value:lower()=="off" then enable=false; for _,name in ipairs(order) do if name~=key and (self.cfg.min_stats or {})[name] then enable=true; break end end end
    values={use_min_stats=enable,min_stats={[key]=value}}
  end
  local ok,err=self:configure(values,true); if not ok then return nil,err end
  local shown=key=="TOTAL" and self.cfg.target_total or key=="HARD" and self.cfg.hard_stop or key=="MAX" and self.cfg.max_rolls or key=="DELAY" and self.cfg.reroll_delay or key=="GREATS" and self.cfg.minimum_greats or (key=="GOODPLUS" or key=="GOODS") and self.cfg.minimum_good_plus or (key=="ARRANGE" or key=="MODE") and self.cfg.arrange_mode or (self.cfg.min_stats or {})[key]
  self:echo("Set "..key.." to "..tostring(shown or "off")); return true
end
function Roller:configure(values,silent)
  values=type(values)=="table" and values or {}; local candidate=copy(self.cfg); candidate.reroll_command="reroll"
  local numeric={{"target_total",1,maximumTotal,true},{"hard_stop",1,maximumTotal,true},{"max_rolls",1,nil,true},{"reroll_delay",0,nil,false},{"minimum_greats",1,#order,true},{"minimum_good_plus",1,#order,true}}
  for _,spec in ipairs(numeric) do
    local key,min,max,optional=spec[1],spec[2],spec[3],spec[4]; local raw=values[key]
    if raw~=nil then
      raw=trim(raw); local off=optional and (raw=="" or raw:lower()=="off"); local number=tonumber(raw)
      if off then candidate[key]=nil
      elseif not number or number~=number or number==math.huge or number==-math.huge or number<min or (max and number>max) or (key~="reroll_delay" and number~=math.floor(number)) then return nil,key.." is invalid" else candidate[key]=number end
    end
  end
  if values.reroll_command~=nil then local command=trim(values.reroll_command):lower(); if command~="reroll" then return nil,"reroll command must remain reroll" end; candidate.reroll_command=command end
  if values.arrange_mode~=nil then local mode=trim(values.arrange_mode):lower(); if mode=="auto" then mode="game_auto" elseif mode=="custom" then mode="minimums" end; if not arrangeModes[mode] then return nil,"arrange mode must be manual, game_auto, or minimums" end; candidate.arrange_mode=mode end
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
  if lower=="start" then return self:start() elseif lower=="stop" then self.state.auto_suppressed=true; return self:stop("Manual stop") elseif lower=="stats" then return self:report("Roller statistics") elseif lower=="last" then if self.state.last then self:echo(self:rollText(self.state.last)) else self:echo("No roll captured yet.") end; return true elseif lower=="reset" then self:reset(); self:echo("Reset complete."); return true end
  local key,value=action:match("^[Ss][Ee][Tt]%s+(%S+)%s+(%S+)%s*$"); if key then local ok,err=self:set(key,value); if not ok then self:echo(err) end; return ok,err end
  self:echo("Commands: rr start|stop|stats|last|reset|help; rr set total|hard|max|delay|greats|goodplus|arrange|STAT <value>. Roll-and-arrange modes: manual, game_auto, minimums. The HUD never sends done."); return true
end
function Roller:shutdown() self:cancelReroll(); self.state.active=false; self:clearCapture(); if self.state.log and self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log); self.state.log=nil end; return true end
Roller.order=order; Roller.ranks=ranks; Roller.maximumTotal=maximumTotal
return Roller
