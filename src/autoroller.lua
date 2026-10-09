local Audio=require("autoroller_audio")
local Roller={}; Roller.__index=Roller
local order={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","PRE","PER","LUK"}
local legacyOrder={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"}
local oldOrder={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP","MP"}
local supportedStats={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","PRE","PER","LUK","VOI","APP","MP"}
local pairedStat={PRE="VOI",LUK="APP",VOI="PRE",APP="LUK"}
local creatorFirst={"STR","INT","WIS","DEX","AGI","CON"}
local creatorSecond={"CHA","WIL","VOI","PER","APP","MP"}
local legacyCreatorSecond={"CHA","WIL","VOI","PER","APP"}
local currentCreatorSecond={"CHA","WIL","PRE","PER","LUK"}
local ranks={awful=1,poor=2,low=3,aver=4,average=4,fair=5,good=6,great=7,excel=7,superb=7}
local rankLabels={[1]="Awful",[2]="Poor",[3]="Low",[4]="Aver",[5]="Fair",[6]="Good",[7]="Great"}
-- MP was removed from the live creator. Keep the old 12-value tables only so
-- archived/partially-updated screens cannot confuse capture, but all current
-- limits and defaults are based on the eleven live characteristics.
local maximumTotal=#order*7
local observationWarningInterval=100
local arrangeOrders={[11]=order,[12]=oldOrder}
local captureLineLimit=8
local arrangeModes={manual=true,game_auto=true,minimums=true}
local latentPsionMessage="Something stirs behind your eyes. You have a latent psionic gift."
local latentPsionAlert="RARE CHARACTER ALERT — LATENT PSION DETECTED\nAutomatic rolling has stopped. Do not leave this profession screen until you decide how to continue."

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
local function secondHeader(line)
  if headerMatches(line,currentCreatorSecond) then return currentCreatorSecond,order end
  if headerMatches(line,legacyCreatorSecond) then return legacyCreatorSecond,legacyOrder end
  if headerMatches(line,creatorSecond) then return creatorSecond,oldOrder end
  return nil
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
local function statText(stats,names)
  local out={}; for _,name in ipairs(names or order) do if stats[name]~=nil then out[#out+1]=name.." "..tostring(stats[name]) end end; return table.concat(out,"  ")
end
local function autoStartEnabled(config) return config.auto_start_on_name~=false end
local function promptProtocol(line)
  local lower=trim(cleanLine(line)):lower():gsub("^>%s*","")
  if lower:match("^<stat>%s+<label>%s+auto%s+clear%s+reroll%s+done%s+%?%s*help%s*$")
    or lower:match("^<stat>%s+<label>%s+auto%s+reset%s+reroll%s+done%s+%?%s*help%s*$") then return "arrange" end
  if lower:match("^reroll%s+done%s+%?%s*help%s*$") then return "creator" end
  if lower:match("use%s+this%s+body%s*%?%s*y%s*,%s*n") then return "legacy" end
  return nil
end
local function rerollCommand(protocol) return (protocol=="creator" or protocol=="arrange") and "reroll" or "n" end
local function acceptanceCommand(protocol) return (protocol=="creator" or protocol=="arrange") and "done" or "y" end
local function placementCommand(command)
  if command=="auto" then return true end
  local stat,label=command:match("^([a-z]+)%s+([a-z]+)$")
  if not stat or not ranks[label] then return false end
  for _,name in ipairs(supportedStats) do if stat==name:lower() then return true end end
  return false
end
local function onOff(value,defaultEnabled)
  local enabled=value
  if enabled==nil then enabled=defaultEnabled==true end
  return enabled and "ON" or "OFF"
end
local function optionalValue(value)
  if value==nil or value==false or trim(value)=="" then return "off" end
  return tostring(value)
end
local function rankSetting(value)
  local number=tonumber(value)
  if not number or not rankLabels[number] then return "off" end
  return tostring(number).." ("..rankLabels[number]..")"
end
local function minimumFor(config,name)
  local minimums=config.min_stats or {}
  local value=minimums[name]
  if value==nil and pairedStat[name] then value=minimums[pairedStat[name]] end
  return tonumber(value)
end
local function safeLocalName(value)
  local name=trim(value)
  if name=="" then return "not configured" end
  if not name:match("^[%w%._%-]+$") then return "custom name hidden" end
  return name
end
local function protocolText(protocol)
  return ({creator="Roll in place",arrange="Roll and arrange",legacy="Legacy body roller"})[protocol] or "Not detected yet"
end
local function arrangeModeText(mode)
  return ({manual="LET ME PLACE (manual)",game_auto="GAME AUTO (game_auto)",minimums="MY MINIMUMS + AUTO (minimums)"})[mode] or "LET ME PLACE (manual)"
end

function Roller.new(adapter,settings,onConfig,onAlert,onSession,onResult,onResultCleared)
  local config=copy(settings or {})
  config.alerts=Audio.validate(config.alerts) or Audio.defaults()
  -- Older DGHUD releases persisted "n" for the retired body prompt. The new
  -- creator uses a named command; normalize the old value without losing any
  -- of the player's score or logging preferences.
  if trim(config.reroll_command):lower()~="reroll" then config.reroll_command="reroll" end
  for _,key in ipairs({"target_total","hard_stop","max_rolls","minimum_greats","minimum_good_plus"}) do if config[key]==false then config[key]=nil end end
  config.arrange_mode=trim(config.arrange_mode):lower(); if not arrangeModes[config.arrange_mode] then config.arrange_mode="manual" end
  config.min_stats=copy(config.min_stats or {})
  if config.min_stats.PRE==nil and config.min_stats.VOI~=nil then config.min_stats.PRE=config.min_stats.VOI end
  if config.min_stats.LUK==nil and config.min_stats.APP~=nil then config.min_stats.LUK=config.min_stats.APP end
  for _,key in ipairs(supportedStats) do if config.min_stats[key]==false then config.min_stats[key]=nil end end
  local self=setmetatable({adapter=adapter,cfg=config,onConfig=onConfig,onAlert=onAlert,onSession=onSession,onResult=onResult,onResultCleared=onResultCleared},Roller); self:reset(); return self
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
  s.expected=nil; s.partial=nil; s.pending_stats=nil; s.pending_pool=nil; s.arrangement=nil; s.passive_lines=0; s.capture_lines=0; s.protocol=nil; s.characteristic_order=nil; s.fresh_roll=false; s.awaiting_new_roll=false; s.expected_echo=nil; s.owned_outgoing=nil; return true
end
function Roller:clearResult()
  if self.state then self.state.result_notified=false end
  if type(self.onResultCleared)=="function" then pcall(self.onResultCleared) end
  return true
end
function Roller:reset()
  local timerGeneration=0
  if self.state then self:cancelReroll(); timerGeneration=tonumber(self.state.timer_generation) or 0 end
  if self.state and self.state.log and self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log) end
  self.state={active=false,rolls=0,sum=0,last=nil,best=nil,worst=nil,observed_rolls=0,observed_sum=0,observed_best=nil,observed_worst=nil,observed_last=nil,observed_capture=nil,observation_transaction=0,observed_transaction=nil,stat_rolls=0,pool_rolls=0,stat_highs={},pool_highs={},stat_order=nil,pool_size=nil,warning_roll_checkpoint=0,expected=nil,partial=nil,pending_stats=nil,pending_pool=nil,arrangement=nil,passive_lines=0,capture_lines=0,protocol=nil,fresh_roll=false,timer=nil,timer_generation=timerGeneration,auto_suppressed=false,log=nil,result_held=false,held_protocol=nil,awaiting_new_roll=false,phase="idle",expected_echo=nil,owned_outgoing=nil,latent_psion=false}; self:clearResult(); self:notifySession(); return true
end
-- A fixed number of scalar maxima, not an ever-growing list of rolls. These
-- observations never claim a racial/profession cap or change minimum settings.
function Roller:sessionSummary()
  local s=self.state or {}; local best=s.observed_best; local summary={active=s.active==true,rolls=s.observed_rolls or 0,stat_rolls=s.stat_rolls or 0,pool_rolls=s.pool_rolls or 0,best_total=best and best.total or nil,average=(s.observed_rolls or 0)>0 and s.observed_sum/s.observed_rolls or 0,maximum=best and best.maximum or maximumTotal,phase=self:phaseText(),stats={},pool={},unmet={}}
  for _,name in ipairs(s.stat_order or order) do
    local high=(s.stat_highs or {})[name]; local target=self.cfg.use_min_stats==true and minimumFor(self.cfg,name) or nil
    if not rankLabels[target] then target=nil end
    local row={name=name,value=high and high.value or nil,label=high and rankLabels[high.value] or nil,roll=high and high.roll or nil,target=target,target_label=target and rankLabels[target] or nil}
    summary.stats[#summary.stats+1]=row
    if target and high and high.value<target then summary.unmet[#summary.unmet+1]=copy(row) end
  end
  for slot,high in ipairs(s.pool_highs or {}) do summary.pool[#summary.pool+1]={slot=slot,value=high.value,label=rankLabels[high.value],roll=high.roll} end
  if summary.stat_rolls>=observationWarningInterval and #summary.unmet>0 then summary.warning="Some minimums have not been seen after "..summary.stat_rolls.." complete stat rolls. Observed highs are not confirmed race/class limits; targets are unchanged." end
  return summary
end
function Roller:notifySession()
  if type(self.onSession)=="function" then pcall(self.onSession,self:sessionSummary()) end
  return true
end
function Roller:confirmSessionRoll(protocol)
  local s=self.state; local roll=s.last
  -- A captured table is provisional until the exact matching decision prompt.
  -- This excludes assignment screens and repeated redraws before a decision.
  if not s.active or not s.fresh_roll or not roll or roll.protocol~=protocol or s.observed_capture==roll.roll or s.observed_transaction==s.observation_transaction then return false end
  s.observed_capture=roll.roll; s.observed_transaction=s.observation_transaction; s.observed_rolls=s.observed_rolls+1; s.observed_sum=s.observed_sum+roll.total
  local observed=copy(roll); observed.roll=s.observed_rolls; s.observed_last=observed
  if not s.observed_best or roll.total>s.observed_best.total then s.observed_best=observed end
  if not s.observed_worst or roll.total<s.observed_worst.total then s.observed_worst=observed end
  if roll.pool then
    if s.pool_size~=#roll.pool then s.pool_highs={}; s.pool_rolls=0; s.pool_size=#roll.pool end
    s.pool_rolls=s.pool_rolls+1; local sorted=copy(roll.pool); table.sort(sorted,function(a,b) return a>b end)
    for slot,value in ipairs(sorted) do local high=s.pool_highs[slot]; if not high or value>high.value then s.pool_highs[slot]={value=value,roll=s.observed_rolls} end end
  else
    local same=type(s.stat_order)=="table" and #s.stat_order==#roll.order
    if same then for index,name in ipairs(roll.order) do if s.stat_order[index]~=name then same=false; break end end end
    if not same then s.stat_order=copy(roll.order); s.stat_highs={}; s.stat_rolls=0; s.warning_roll_checkpoint=0 end
    s.stat_rolls=s.stat_rolls+1
    for _,name in ipairs(roll.order) do local high=s.stat_highs[name]; if not high or roll.stats[name]>high.value then s.stat_highs[name]={value=roll.stats[name],roll=s.observed_rolls} end end
  end
  self:notifySession(); if not roll.pool then self:warnUnseenMinimums() end; return true
end
function Roller:sessionLines()
  local summary=self:sessionSummary(); local lines={"BEST SEEN THIS SESSION — observations, not confirmed limits"}
  if summary.stat_rolls>0 or summary.pool_rolls==0 then
    lines[#lines+1]=string.format("%-5s %-8s %-9s %s","Stat","Target","Best seen","First roll")
    for _,row in ipairs(summary.stats) do lines[#lines+1]=string.format("%-5s %-8s %-9s %s",row.name,row.target_label or "off",row.label or "--",row.roll and ("#"..row.roll) or "--") end
    lines[#lines+1]="Each stat's high can come from a different roll; this is not one available character."
  end
  if summary.pool_rolls>0 then
    lines[#lines+1]="Pool values are unassigned: per-stat limits cannot be inferred."
    lines[#lines+1]=string.format("%-5s %-9s %s","Slot","Best seen","First roll")
    for _,row in ipairs(summary.pool) do lines[#lines+1]=string.format("%-5s %-9s #%d",row.slot,row.label,row.roll) end
    lines[#lines+1]="Slots are sorted highest to lowest on each pool; highs can come from different rolls."
  end
  if summary.warning then lines[#lines+1]=summary.warning end
  return lines
end
function Roller:warnUnseenMinimums()
  local s=self.state; local count=s.stat_rolls or 0
  if count<observationWarningInterval or count%observationWarningInterval~=0 or s.warning_roll_checkpoint==count then return true end
  s.warning_roll_checkpoint=count
  local summary=self:sessionSummary(); if not summary.warning then return true end
  local unmet={}; for _,row in ipairs(summary.unmet) do unmet[#unmet+1]=row.name..": target "..row.target_label..", best seen "..row.label end
  self:echo("MINIMUMS NOT YET SEEN ("..count.." stat rolls): "..table.concat(unmet,"; ").."\nPossible rare roll or race/class limit — not a confirmed cap. Review SESSION BEST in Options > Autoroller or rr stats. This notice does not stop rolling or change targets.")
  return true
end
function Roller:log(message)
  if not self.state.log or not self.adapter.appendRollerLog then return end
  local called,ok,err=pcall(self.adapter.appendRollerLog,self.adapter,self.state.log,message)
  if not called or not ok then self:echo("Logging stopped: "..tostring((not called and ok) or err or "write failed")); if self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log) end; self.state.log=nil end
end
function Roller:minimumFailures(stats,names)
  local out={}; if self.cfg.use_min_stats~=true then return out end
  for _,name in ipairs(names or order) do local needed=minimumFor(self.cfg,name); if needed and stats[name]~=nil and stats[name]<needed then out[#out+1]=name.." "..stats[name].."<"..needed end end
  return out
end
function Roller:assignmentPlan(pool,activeOrder)
  activeOrder=activeOrder or arrangeOrders[#pool]
  if type(pool)~="table" or not activeOrder then return nil,"the pool is incomplete" end
  local wanted={}
  if self.cfg.use_min_stats==true then
    for index,name in ipairs(activeOrder) do local needed=minimumFor(self.cfg,name); if needed then wanted[#wanted+1]={name=name,needed=needed,index=index} end end
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
function Roller:poolFailures(pool,activeOrder)
  local out={}; local greats,goodPlus=0,0
  for _,value in ipairs(pool or {}) do if value>=7 then greats=greats+1 end; if value>=6 then goodPlus=goodPlus+1 end end
  local neededGreats=limit(self.cfg.minimum_greats); if neededGreats and greats<neededGreats then out[#out+1]="Greats "..greats.."<"..neededGreats end
  local neededGoodPlus=limit(self.cfg.minimum_good_plus); if neededGoodPlus and goodPlus<neededGoodPlus then out[#out+1]="Good+ "..goodPlus.."<"..neededGoodPlus end
  local mode=self.cfg.arrange_mode or "manual"
  local needsPlan=self.cfg.use_min_stats==true and (mode=="minimums" or (mode=="manual" and self.cfg.require_min_stats_to_stop~=false))
  if needsPlan then local plan,err=self:assignmentPlan(pool,activeOrder); if not plan then out[#out+1]=err end end
  return out
end
function Roller:qualified(roll)
  local hard=limit(self.cfg.hard_stop); if hard and roll.total>=hard then return true,"hard stop "..hard end
  local target=limit(self.cfg.target_total); if not target or roll.total<target then return false,"below target "..tostring(target or "disabled") end
  local failures=roll.pool and self:poolFailures(roll.pool,roll.order) or self:minimumFailures(roll.stats,roll.order)
  if #failures>0 and (roll.pool or self.cfg.require_min_stats_to_stop~=false) then return false,table.concat(failures,", ") end
  return true,"target "..target
end
function Roller:start()
  if self.state.active then self:echo("Already running."); return true end
  if self.adapter.standaloneRollerPresent and self.adapter:standaloneRollerPresent() then if not self.state.conflict_warned then self:echo("Built-in roller paused: the standalone og-dg-roller package is active. Disable or uninstall that package before using DGHUD's roller."); self.state.conflict_warned=true end; return nil,"standalone roller conflict" end
  self:reset(); self.state.active=true; self.state.phase="observing"
  if self.cfg.logging_enabled~=false and self.adapter.startRollerLog then local ok,log,err=pcall(self.adapter.startRollerLog,self.adapter,self.cfg); if ok then self.state.log=log; if not log then self:echo("Logging unavailable: "..tostring(err or "unknown error")) end else self:echo("Logging unavailable: "..tostring(log)) end end
  self:log("Started")
  self:echo("Started — target "..tostring(limit(self.cfg.target_total) or "disabled").." / "..maximumTotal.." (11 characteristics). See live SESSION BEST in Options > Autoroller or rr stats."); self:notifySession(); return true
end
function Roller:stop(reason,holdResult)
  local heldProtocol=self.state.protocol or self.state.held_protocol
  self.state.active=false; self:cancelReroll(); self:clearCapture(); self.state.result_held=holdResult==true; self.state.held_protocol=holdResult==true and heldProtocol or nil; self.state.phase=holdResult==true and "held" or "idle"
  self:report(reason or "Stopped"); self:log(reason or "Stopped")
  if not holdResult and self.state.log and self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log); self.state.log=nil end
  if not holdResult then self:clearResult() end
  self:notifySession(); return true
end
function Roller:holdTargetResult(reason,placement)
  local s=self.state
  if not s.last or s.result_notified then return false end
  -- Only verified success routes call this helper. A cancellation can also
  -- hold the prompt, so result_held alone must never announce a target hit.
  local result={kind="target_hit",reason=reason,roll=copy(s.last),rolls=s.rolls,protocol=s.protocol or s.last.protocol,placement=placement}
  s.result_notified=true
  self:stop(reason,true)
  if type(self.onResult)=="function" then pcall(self.onResult,result) end
  return true
end
function Roller:rollText(roll)
  if roll.pool then local labels={}; for _,value in ipairs(roll.pool) do labels[#labels+1]=rankLabels[value] end; return "Roll #"..roll.roll.."  Total="..roll.total.."/"..roll.maximum.."  Pool: "..table.concat(labels," ") end
  return "Roll #"..roll.roll.."  Total="..roll.total.."/"..roll.maximum.."  "..statText(roll.stats,roll.order)
end
function Roller:report(reason)
  local s=self.state; local summary=self:sessionSummary(); local lines={reason or "Roller statistics","Confirmed rolls: "..summary.rolls.."  Average: "..string.format("%.2f",summary.average)}
  if s.observed_best then lines[#lines+1]="Best: "..self:rollText(s.observed_best) end; if s.observed_worst then lines[#lines+1]="Worst: "..self:rollText(s.observed_worst) end; for _,line in ipairs(self:sessionLines()) do lines[#lines+1]=line end; self:echo(table.concat(lines,"\n")); return true
end
function Roller:waitReason()
  local s=self.state or {}
  if s.latent_psion then return "Latent psion detected. Automatic input is disabled; choose the profession yourself." end
  if s.result_held then return "A result is held at the creator prompt for your manual done or reroll." end
  if not s.active then
    if s.pending_stats or s.pending_pool then return "A complete roll was seen; waiting for the exact decision prompt before auto-starting." end
    if s.auto_suppressed then return "Manual stop is holding automatic rolling off; use rr start to resume." end
    if autoStartEnabled(self.cfg) then return "Waiting for a supported rolling screen and its exact decision prompt; auto-start is on." end
    return "Auto-start is off; use rr start while you are at the rolling screen."
  end
  local phase=s.phase
  if phase=="observing" then return "Waiting for a complete supported roll." end
  if phase=="capturing" then return "Reading the characteristic values from the current roll." end
  if phase=="awaiting_prompt" then return "Roll captured; waiting for the exact decision prompt before acting." end
  if phase=="reroll_delay" then return "Roll rejected; waiting for the configured reroll delay." end
  if phase=="waiting_new_roll" then return "Reroll sent or observed; waiting for the next complete roll." end
  if phase=="assigning" then
    local sequence=s.arrangement; local awaiting=sequence and sequence.awaiting
    if awaiting and awaiting.auto then return "Waiting for the game to confirm a complete assignment board and an empty pool." end
    if awaiting and awaiting.stat then return "Waiting for the game to confirm the next minimum placement and updated pool." end
    return "Preparing the next confirmed arranged-pool placement."
  end
  return "Waiting for the next recognized creator event."
end
function Roller:phaseText()
  local s=self.state or {}
  if s.latent_psion then return "LATENT PSION FOUND" end
  if s.result_held then return "Result held" end
  if not s.active and (s.pending_stats or s.pending_pool) then return "Checking decision prompt" end
  if not s.active then return "Idle" end
  return ({observing="Observing",capturing="Capturing roll",awaiting_prompt="Waiting for prompt",reroll_delay="Reroll delay",waiting_new_roll="Waiting for next roll",assigning="Arranging pool"})[s.phase] or "Observing"
end
function Roller:onLatentPsion()
  local s=self.state
  if s.latent_psion then return true end
  self:cancelReroll(); self:clearCapture()
  s.active=false; s.auto_suppressed=true; s.result_held=false; s.held_protocol=nil; s.latent_psion=true; s.phase="latent_psion"
  self:clearResult()
  self:log("Latent psion detected; automatic input stopped")
  if s.log and self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,s.log); s.log=nil end
  self:echo(latentPsionAlert)
  if type(self.onAlert)=="function" then pcall(self.onAlert,latentPsionAlert) end
  self:notifySession()
  return true
end
function Roller:statusLines()
  local s=self.state or {}; local protocol=s.protocol or s.held_protocol
  return {
    "Autoroller status",
    "State: "..(s.active and "ACTIVE" or "INACTIVE"),
    "Protocol: "..protocolText(protocol),
    "Phase: "..self:phaseText(),
    "Waiting: "..self:waitReason(),
    "Session rolls: "..tostring(tonumber(s.rolls) or 0),
    "Auto-start: "..onOff(autoStartEnabled(self.cfg),false),
    "Safety: DGHUD never sends done; final acceptance is always manual.",
    "Rare safety: latent psion discovery stops all automatic input and opens a persistent HUD alert.",
  }
end
function Roller:statusText() return table.concat(self:statusLines(),"\n") end
function Roller:settingsText()
  local cfg=self.cfg or {}; local lines=self:statusLines(); local minimums=cfg.min_stats or {}
  lines[#lines+1]=""
  lines[#lines+1]="[Roll rules]"
  lines[#lines+1]="Target total: "..optionalValue(cfg.target_total).." / "..maximumTotal
  lines[#lines+1]="Hard stop: "..optionalValue(cfg.hard_stop).." (bypasses normal filters when reached)"
  lines[#lines+1]="Maximum rolls: "..optionalValue(cfg.max_rolls)
  lines[#lines+1]="Reroll delay: "..tostring(math.max(0,tonumber(cfg.reroll_delay) or 0)).." seconds"
  lines[#lines+1]="Reroll command: reroll (fixed)"
  lines[#lines+1]=""
  lines[#lines+1]="[Characteristic minimums]"
  lines[#lines+1]="Minimums enabled: "..onOff(cfg.use_min_stats,false)
  lines[#lines+1]="Require minimums to stop: "..onOff(cfg.require_min_stats_to_stop,true)
  for index=1,#order,2 do
    local left=order[index]..": "..rankSetting(minimums[order[index]])
    local right=order[index+1]
    lines[#lines+1]=right and (left.."    "..right..": "..rankSetting(minimums[right])) or left
  end
  for _,key in ipairs({"VOI","APP","MP"}) do
    if minimums[key]~=nil then lines[#lines+1]="Legacy "..key..": "..rankSetting(minimums[key]).." (ignored by current 11-stat screens)" end
  end
  lines[#lines+1]=""
  lines[#lines+1]="[Roll-and-arrange only]"
  lines[#lines+1]="Qualifying-pool action: "..arrangeModeText(cfg.arrange_mode)
  lines[#lines+1]="Minimum Great values: "..optionalValue(cfg.minimum_greats)
  lines[#lines+1]="Minimum Good-or-Great values: "..optionalValue(cfg.minimum_good_plus)
  lines[#lines+1]="Note: Great and Good-or-Great counts apply only to Roll-and-arrange pools."
  lines[#lines+1]=""
  lines[#lines+1]="[Startup, output, and logs]"
  lines[#lines+1]="Auto-start: "..onOff(autoStartEnabled(cfg),false)
  lines[#lines+1]="Print every roll: "..onOff(cfg.show_every_roll,true)
  lines[#lines+1]="Roll logging: "..onOff(cfg.logging_enabled,true)
  lines[#lines+1]="Log folder: "..safeLocalName(cfg.log_folder).." (profile-local name)"
  lines[#lines+1]="Master log: "..safeLocalName(cfg.master_file).." (profile-local name)"
  lines[#lines+1]="Use rr status for a shorter live-state report."
  return table.concat(lines,"\n")
end
function Roller:record(stats,protocol,names)
  if type(stats)~="table" or type(names)~="table" or (#names~=11 and #names~=12) then return false end
  local total=0; for _,name in ipairs(names) do local value=stats[name]; if not rankLabels[value] then return false end; total=total+value end
  local s=self.state; s.rolls=s.rolls+1; s.sum=s.sum+total
  local roll={roll=s.rolls,total=total,maximum=#names*7,stats=copy(stats),order=copy(names),protocol=protocol}; s.last=roll
  if not s.best or total>s.best.total then s.best=roll end; if not s.worst or total<s.worst.total then s.worst=roll end
  s.protocol=protocol; s.fresh_roll=true; s.expected=nil; s.partial=nil; s.capture_lines=0; s.awaiting_new_roll=false; s.phase="awaiting_prompt"; local text=self:rollText(roll); if self.cfg.show_every_roll~=false then self:echo(text) end; self:log(text); self:notifySession(); return true
end
function Roller:recordPool(pool)
  if type(pool)~="table" then return false end
  local activeOrder=self.state.characteristic_order
  if type(activeOrder)~="table" or #activeOrder~=#pool then activeOrder=arrangeOrders[#pool] end
  if not activeOrder then return false end
  local total=0; for _,value in ipairs(pool or {}) do if not rankLabels[value] then return false end; total=total+value end
  local s=self.state; s.rolls=s.rolls+1; s.sum=s.sum+total
  local roll={roll=s.rolls,total=total,maximum=#activeOrder*7,pool=copy(pool),order=copy(activeOrder),protocol="arrange"}; s.last=roll
  if not s.best or total>s.best.total then s.best=roll end; if not s.worst or total<s.worst.total then s.worst=roll end
  s.protocol="arrange"; s.fresh_roll=true; s.expected=nil; s.partial=nil; s.pending_pool=nil; s.capture_lines=0; s.awaiting_new_roll=false; s.phase="awaiting_prompt"; local text=self:rollText(roll); if self.cfg.show_every_roll~=false then self:echo(text) end; self:log(text); self:notifySession(); return true
end
function Roller:beginBlock(protocol,names,resetPartial)
  if not self.state.active then return false end
  local s=self.state; s.protocol=protocol; s.fresh_roll=false; s.expected=names; s.capture_lines=0; s.awaiting_new_roll=false; s.phase="capturing"
  if resetPartial then self:cancelReroll(); s.partial={}
  elseif type(s.partial)~="table" then s.partial={} end
  self:notifySession(); return true
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
  local activeOrder=s.characteristic_order or order; local complete=true; for _,name in ipairs(activeOrder) do if s.partial[name]==nil then complete=false; break end end
  if complete then
    if not s.active then s.pending_stats=copy(s.partial); s.passive_lines=0; s.expected=nil; s.partial=nil; return true end
    return self:record(s.partial,protocol,activeOrder)
  end
  return true
end
function Roller:prepareForReroll(protocol)
  self.state.observation_transaction=self.state.observation_transaction+1
  local s=self.state; self:cancelReroll(); s.expected=nil; s.partial=nil; s.pending_stats=nil; s.pending_pool=nil; s.arrangement=nil; s.characteristic_order=nil; s.capture_lines=0; s.passive_lines=0; s.fresh_roll=false; s.result_held=false; s.held_protocol=nil; s.protocol=protocol or s.protocol; s.awaiting_new_roll=true; s.phase="waiting_new_roll"; self:clearResult(); self:notifySession(); return true
end
function Roller:rearmForManualReroll(protocol)
  local s=self.state; local controlled=s.active or s.result_held or s.held_protocol~=nil
  if not controlled then return false end
  local previous=protocol or s.protocol or s.held_protocol or "arrange"
  if not s.active then s.active=true; s.result_held=false; s.phase="observing" end
  self:prepareForReroll(previous)
  -- A player can change creator rolling methods before manually entering
  -- reroll.  Do not carry a stale modern protocol into the next response:
  -- the next explicit Pool: line or split characteristic header is a safer
  -- source of truth.  Legacy body rolling must retain its distinct n command.
  if previous~="legacy" then s.protocol=nil end
  -- sysDataSendRequest observes the player's command immediately before Mudlet
  -- transmits it. Sending here duplicates that command on the wire. Manual
  -- rerolls only re-arm capture; sendOwnedCommand is reserved for HUD timers.
  self.state.awaiting_new_roll=true; self.state.phase="waiting_new_roll"
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
  if s.active and s.rolls==0 and s.protocol==nil and s.phase=="observing" then
    -- A manual start can precede the creator's method choice. Choosing a
    -- rolling method is not a request to cancel, and cannot send a reroll.
    if normalized=="2" or normalized=="3" then return false end
    if normalized=="1" then return self:stop("Assign method selected") end
  end
  if s.result_held and s.held_protocol=="arrange" and s.result_notified and placementCommand(normalized) then return self:clearResult() end
  if s.result_held and (normalized=="done" or normalized=="y" or normalized=="<" or normalized=="back" or normalized=="q" or normalized=="quit") then return self:stop("Character creation continued") end
  if s.active or s.timer or s.arrangement then return self:stop("Player command cancelled automatic rolling",true) end
  return false
end
function Roller:onDisconnect()
  if self.state.latent_psion then return self:reset() end
  if self.state.active or self.state.result_held or self.state.log then return self:stop("Disconnected") end
  self:cancelReroll(); self:clearCapture(); self.state.result_held=false; self.state.held_protocol=nil; self.state.phase="idle"; self:clearResult(); return true
end
function Roller:reroll(protocol)
  if self.state.timer then return true end
  local delay=math.max(0,tonumber(self.cfg.reroll_delay) or 0); local command=rerollCommand(protocol)
  self.state.timer_generation=(tonumber(self.state.timer_generation) or 0)+1; local generation=self.state.timer_generation; self.state.phase="reroll_delay"
  local called,id,err=pcall(self.adapter.schedule,self.adapter,delay,function()
    if self.state.timer_generation~=generation or self.state.phase~="reroll_delay" then return end
    self.state.timer=nil
    if self.state.active then
      self.state.observation_transaction=self.state.observation_transaction+1
      self.state.awaiting_new_roll=true; self.state.phase="waiting_new_roll"; self.state.expected_echo=command; self:notifySession()
      local sent,sendErr=self:sendOwnedCommand(command); if not sent then self:stop("Could not send reroll: "..tostring(sendErr),true) end
    end
  end)
  if not called then err=id or "timer unavailable"; id=nil end
  if not id then self:stop("Could not schedule reroll: "..tostring(err)); return nil,err end; self.state.timer=id; self:notifySession(); return true
end
function Roller:sendArrangementCommand(entry)
  local sequence=self.state.arrangement; entry.confirmed=false; entry.pool_confirmed=false; entry.pool_empty=false; entry.board_complete=false; sequence.awaiting=entry
  if entry.auto then sequence.display_expected=nil; sequence.display_stats={}; sequence.auto_board_complete=false end
  local sent,err=self:sendOwnedCommand(entry.command)
  if not sent then return self:stop("Could not send arrangement command: "..tostring(err),true) end
  self:notifySession()
  return true
end
function Roller:advanceArrangement()
  local sequence=self.state.arrangement; if not sequence then return false end
  local awaiting=sequence.awaiting
  if awaiting then
    if awaiting.auto then
      if not (awaiting.pool_empty and sequence.auto_board_complete) then return self:stop("Automatic placement was not fully confirmed — prompt left waiting for you",true) end
      return self:holdTargetResult("Arrangement complete — prompt left waiting for manual done","complete")
    end
    if not (awaiting.confirmed and awaiting.pool_confirmed) then return self:stop("Placement was not fully confirmed — prompt left waiting for you",true) end
  end
  sequence.index=sequence.index+1; local entry=sequence.commands[sequence.index]
  if not entry then return self:holdTargetResult("Minimum placements complete — prompt left waiting for manual done","complete") end
  return self:sendArrangementCommand(entry)
end
function Roller:beginArrangement(roll,reason)
  local mode=self.cfg.arrange_mode or "manual"
  if mode=="manual" then self:echo("TARGET HIT — pool left waiting for your placements and manual done.\n"..self:rollText(roll)); return self:holdTargetResult(reason,"manual") end
  local commands={}
  if mode=="minimums" then
    local plan,remaining=self:assignmentPlan(roll.pool,roll.order)
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
  self.state.fresh_roll=false; self.state.phase="assigning"; self.state.arrangement={mode=mode,commands=commands,index=0,awaiting=nil,display_expected=nil,display_stats={},auto_board_complete=false,order=roll.order or order}
  self:echo("TARGET HIT — "..(mode=="minimums" and "placing configured minimums, then using game auto" or "using game auto").."; done remains manual.\n"..self:rollText(roll))
  return self:advanceArrangement()
end
function Roller:onLine(line)
  line=tostring(line or "")
  local lower=trim(cleanLine(line)):lower(); local bare=lower:gsub("^>%s*",""); local s=self.state
  local cleaned=trim(cleanLine(line)):gsub("%s+"," ")
  local latentCandidate=cleaned
  local afterPrompt=cleaned:match(">%s*(.-)%s*$")
  if afterPrompt and afterPrompt~="" then latentCandidate=afterPrompt end
  if latentCandidate==latentPsionMessage then s.latent_phrase_buffer=nil; return self:onLatentPsion() end
  if s.latent_phrase_buffer then
    local joined=(s.latent_phrase_buffer.." "..latentCandidate):gsub("%s+"," ")
    s.latent_phrase_buffer=nil
    if joined==latentPsionMessage then return self:onLatentPsion() end
  end
  if latentPsionMessage:sub(1,#latentCandidate)==latentCandidate and latentCandidate~="" then s.latent_phrase_buffer=latentCandidate; return true end
  if lower:match("step%s+7%s+of%s+10") then
    local suppressed=s.auto_suppressed
    if s.active then
      -- START ROLLER may be pressed just before Mudlet receives the Step 7
      -- banner.  Keep that explicit running state and its session/log alive;
      -- only discard stale capture fragments from a previous creator screen.
      self:cancelReroll(); self:clearCapture(); s.active=true; s.auto_suppressed=suppressed; s.result_held=false; s.held_protocol=nil; s.latent_psion=false; s.phase="observing"
    else
      self:reset(); self.state.auto_suppressed=suppressed
    end
    return false
  end
  if lower:match("step%s+[89]%s+of%s+10") then
    if s.active or s.result_held or s.protocol or s.pending_stats or s.pending_pool or s.log then return self:stop("Character creation continued") end
    return false
  end
  if s.expected_echo and bare==s.expected_echo then s.expected_echo=nil; return true end
  if bare=="reroll" and s.awaiting_new_roll then return true end
  if bare=="reroll" and (s.active or s.result_held or s.held_protocol~=nil) then return self:rearmForManualReroll() end
  if bare=="n" and (s.protocol=="legacy" or s.held_protocol=="legacy") then
    if s.awaiting_new_roll then return true end
    return self:rearmForManualReroll("legacy")
  end
  if s.active then
    local protocol=s.protocol
    if ((protocol=="creator" or protocol=="arrange") and bare=="done") or (protocol=="legacy" and bare=="y") then return self:stop("Character creation continued") end
    local stat,label=bare:match("^([a-z]+)%s+([a-z]+)$"); local assignment=false
    if stat and ranks[label] then for _,name in ipairs(order) do if stat==name:lower() then assignment=true; break end end end
    if protocol=="arrange" and (bare=="auto" or bare=="clear" or bare=="reset" or bare=="?" or bare=="help" or bare=="<" or bare=="back" or bare=="q" or bare=="quit" or assignment) then return self:stop("Player took control of roll placement",true) end
  end

  local poolKind,pool=parsePool(line)
  if s.arrangement then
    local sequence=s.arrangement; local awaiting=sequence.awaiting
    local stat,label=trim(cleanLine(line)):match("^([A-Za-z]+)%s+placed:%s*([A-Za-z]+)%.?$")
    if stat and awaiting and awaiting.stat and stat:upper()==awaiting.stat and ranks[label:lower()]==awaiting.value then awaiting.confirmed=true; return true end
    if headerMatches(line,creatorFirst) then sequence.display_expected=creatorFirst; sequence.display_stats={}; return true end
    local second=secondHeader(line)
    if second then sequence.display_expected=second; return true end
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
  if s.result_held and (bare=="done" or bare=="y" or bare=="<" or bare=="back" or bare=="q" or bare=="quit") then return self:stop("Character creation continued") end
  if s.result_held and s.held_protocol=="arrange" and s.result_notified and placementCommand(bare) then return self:clearResult() end
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
    if s.active and (s.fresh_roll or (s.phase=="reroll_delay" and not s.awaiting_new_roll)) then return false end
    if not s.active and (not autoStartEnabled(self.cfg) or s.auto_suppressed) then return false end
    s.characteristic_order=nil
    -- The creator may move from Roll and arrange to Roll in place without
    -- restarting DGHUD.  An explicit six-column characteristic header is
    -- authoritative, so recover from a stale arrange protocol instead of
    -- silently discarding every subsequent roll.
    if s.active and s.protocol=="arrange" then
      s.pending_pool=nil
      return self:beginBlock("creator",creatorFirst,true)
    end
    if not s.active then s.protocol="creator"; s.fresh_roll=false; s.expected=creatorFirst; s.partial={}; s.pending_stats=nil; s.passive_lines=0; return true end
    return self:beginBlock("creator",creatorFirst,true)
  end
  local second,activeOrder=secondHeader(line)
  if second then
    s.characteristic_order=activeOrder
    if s.active and s.protocol=="arrange" then return false end
    if s.active and s.protocol=="creator" and type(s.partial)~="table" then return false end
    if not s.active and not (autoStartEnabled(self.cfg) and s.protocol=="creator" and type(s.partial)=="table") then return false end
    if not s.active then s.expected=second; return true end
    return self:beginBlock("creator",second,false)
  end
  if (self.state.active or (autoStartEnabled(self.cfg) and self.state.protocol=="creator")) and self:captureExpected(line) then return true end

  local protocol=promptProtocol(line)
  if protocol=="arrange" and not self.state.active and autoStartEnabled(self.cfg) and self.state.pending_pool then
    local pending=copy(self.state.pending_pool); local names=self.state.characteristic_order; local started,err=self:start(); if not started then return started,err end
    self.state.characteristic_order=names
    self:recordPool(pending)
  end
  if protocol=="creator" and not self.state.active and autoStartEnabled(self.cfg) and self.state.pending_stats then
    local pending=copy(self.state.pending_stats); local names=self.state.characteristic_order or (pending.MP~=nil and oldOrder or pending.PRE~=nil and order or legacyOrder)
    local started,err=self:start(); if not started then return started,err end
    self:record(pending,"creator",names)
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
    self:confirmSessionRoll(protocol)
    self.state.fresh_roll=false; local cap=limit(self.cfg.max_rolls); if cap and self.state.rolls>=cap then return self:stop("Reached max rolls "..cap) end
    local target,hard=limit(self.cfg.target_total),limit(self.cfg.hard_stop)
    if not cap and not ((target and target<=roll.maximum) or (hard and hard<=roll.maximum)) then return self:stop("Configured total cannot be reached by this "..roll.maximum.."-point roll format") end
    local ok,reason=self:qualified(roll); if ok and protocol=="arrange" then return self:beginArrangement(roll,reason) end
    if ok then self:echo("TARGET HIT — prompt left waiting for manual "..acceptanceCommand(protocol)..".\n"..self:rollText(roll)); return self:holdTargetResult(reason,"manual") end
    return self:reroll(protocol)
  end
  return false
end
function Roller:set(key,value)
  key=trim(key):upper(); value=trim(value); local values
  local requested=key
  local legacyAlias
  if key=="VOI" then key="PRE"; legacyAlias="VOI"
  elseif key=="APP" then key="LUK"; legacyAlias="APP"
  elseif key=="PRE" then legacyAlias="VOI"
  elseif key=="LUK" then legacyAlias="APP" end
  if key=="TOTAL" then values={target_total=value}
  elseif key=="HARD" then values={hard_stop=value}
  elseif key=="MAX" then values={max_rolls=value}
  elseif key=="DELAY" then values={reroll_delay=value}
  elseif key=="GREATS" then values={minimum_greats=value}
  elseif key=="GOODPLUS" or key=="GOODS" then values={minimum_good_plus=value}
  elseif key=="ARRANGE" or key=="MODE" then values={arrange_mode=value}
  elseif ranks[key:lower()] then return nil,"use a stat name, not a rank"
  else
    local valid=false; for _,name in ipairs(supportedStats) do if key==name then valid=true end end; if not valid then return nil,"unknown roller setting" end
    local enable=true; if value:lower()=="off" then enable=false; for _,name in ipairs(supportedStats) do if name~=key and name~=legacyAlias and (self.cfg.min_stats or {})[name] then enable=true; break end end end
    values={use_min_stats=enable,min_stats={[key]=value}}
    if legacyAlias then values.min_stats[legacyAlias]=value end
  end
  local ok,err=self:configure(values,true); if not ok then return nil,err end
  local shown=key=="TOTAL" and self.cfg.target_total or key=="HARD" and self.cfg.hard_stop or key=="MAX" and self.cfg.max_rolls or key=="DELAY" and self.cfg.reroll_delay or key=="GREATS" and self.cfg.minimum_greats or (key=="GOODPLUS" or key=="GOODS") and self.cfg.minimum_good_plus or (key=="ARRANGE" or key=="MODE") and self.cfg.arrange_mode or (self.cfg.min_stats or {})[key]
  local note=requested~=key and " (formerly "..requested..")" or key=="MP" and " (legacy 12-stat screens only)" or ""
  self:echo("Set "..key.." to "..tostring(shown or "off")..note); return true
end
function Roller:configure(values,silent)
  values=type(values)=="table" and values or {}; local candidate=copy(self.cfg); candidate.reroll_command="reroll"
  if values.alerts~=nil then local alerts,err=Audio.validate(values.alerts); if not alerts then return nil,err end; candidate.alerts=alerts end
  local numeric={{"target_total",1,maximumTotal,true},{"hard_stop",1,maximumTotal,true},{"max_rolls",1,nil,true},{"reroll_delay",0,nil,false},{"minimum_greats",1,#legacyOrder,true},{"minimum_good_plus",1,#legacyOrder,true}}
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
  for _,key in ipairs(supportedStats) do if values.min_stats and values.min_stats[key]~=nil then local raw=trim(values.min_stats[key]); local number=tonumber(raw); if raw=="" or raw:lower()=="off" then candidate.min_stats[key]=nil elseif not number or number<1 or number>7 or number~=math.floor(number) then return nil,key.." minimum must be 1-7 or off" else candidate.min_stats[key]=number end end end
  if not candidate.target_total and not candidate.hard_stop and not candidate.max_rolls then return nil,"enable a target, hard stop, or maximum rolls" end
  if candidate.use_min_stats then local any=false; for _,key in ipairs(supportedStats) do if candidate.min_stats[key] then any=true; break end end; if not any then return nil,"enable at least one stat minimum or turn minimums off" end end
  if self.onConfig then local saved,err=self.onConfig(copy(candidate)); if saved==nil or saved==false then return nil,err or "could not save settings" end end
  self.cfg=candidate; if not silent then self:echo("Settings saved.") end; self:notifySession(); return true
end
function Roller:command(action)
  action=trim(action); local lower=action:lower()
  if lower=="start" then return self:start() elseif lower=="stop" then self.state.auto_suppressed=true; return self:stop("Manual stop") elseif lower=="status" then self:echo(self:statusText()); return true elseif lower=="show" or lower=="config" or lower=="settings" then self:echo(self:settingsText()); return true elseif lower=="stats" then return self:report("Roller statistics") elseif lower=="last" then if self.state.last then self:echo(self:rollText(self.state.last)) else self:echo("No roll captured yet.") end; return true elseif lower=="reset" then self:reset(); self:echo("Reset complete."); return true end
  local key,value=action:match("^[Ss][Ee][Tt]%s+(%S+)%s+(%S+)%s*$"); if key then local ok,err=self:set(key,value); if not ok then self:echo(err) end; return ok,err end
  self:echo("Commands: rr start|stop|status|show|stats|last|reset|help; rr set total|hard|max|delay|greats|goodplus|arrange|STAT <value>. Use rr status to see what the roller is waiting for and rr show to display every saved setting. Roll-and-arrange modes: manual, game_auto, minimums. The HUD never sends done."); return true
end
function Roller:shutdown() self:cancelReroll(); self.state.active=false; self:clearCapture(); if self.state.log and self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log); self.state.log=nil end; self:clearResult(); return true end
Roller.order=order; Roller.ranks=ranks; Roller.maximumTotal=maximumTotal; Roller.observationWarningInterval=observationWarningInterval
return Roller
