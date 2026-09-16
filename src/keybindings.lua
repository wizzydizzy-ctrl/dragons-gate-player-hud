local Keybindings={}; Keybindings.__index=Keybindings
Keybindings.order={"8","9","6","3","2","1","4","7","5","Plus","Minus","0","Period","Asterisk","Slash","Enter"}
Keybindings.labels={Plus="+",Minus="-",Period="Decimal",Asterisk="*",Slash="/",Enter="Enter"}
Keybindings.defaults={enabled=false,commands={["8"]="north",["9"]="northeast",["6"]="east",["3"]="southeast",["2"]="south",["1"]="southwest",["4"]="west",["7"]="northwest",["5"]="look",Plus="up",Minus="down",["0"]="",Period="",Asterisk="",Slash="",Enter=""}}
local function copy(config)
  local result={enabled=type(config)=="table" and config.enabled==true,commands={}}; local commands=type(config)=="table" and config.commands or nil
  for _,key in ipairs(Keybindings.order) do local value=commands and commands[key]; if value==nil then value=Keybindings.defaults.commands[key] end; result.commands[key]=tostring(value or "") end
  return result
end
function Keybindings.validate(config)
  if type(config)~="table" then return nil,"keybinding settings must be a table" end
  if config.enabled~=nil and type(config.enabled)~="boolean" then return nil,"enabled must be true or false" end
  if config.commands~=nil and type(config.commands)~="table" then return nil,"commands must be a table" end
  local result=copy(config)
  for _,key in ipairs(Keybindings.order) do local command=result.commands[key]:match("^%s*(.-)%s*$"); if #command>80 then return nil,"Numpad "..(Keybindings.labels[key] or key).." command is longer than 80 characters" end; if command:find("[%c]") then return nil,"Numpad "..(Keybindings.labels[key] or key).." command contains a control character" end; result.commands[key]=command end
  return result
end
local function sameConfig(first,second)
  if type(first)~="table" or type(second)~="table" or first.enabled~=second.enabled then return false end
  for _,key in ipairs(Keybindings.order) do if first.commands[key]~=second.commands[key] then return false end end
  return true
end
local function configuredCount(config) local count=0; if config.enabled then for _,key in ipairs(Keybindings.order) do if config.commands[key]~="" then count=count+1 end end end; return count end
function Keybindings.new(adapter,config) local valid,err=Keybindings.validate(config or Keybindings.defaults); if not valid then error(err,0) end; return setmetatable({adapter=adapter,config=valid,ids={},retiredIds={},conflicts={},applied=nil},Keybindings) end
function Keybindings:snapshot() return copy(self.config) end
function Keybindings:stop()
  local removed,failed={},{ }
  for key,id in pairs(self.ids) do
    local called,ok,err=pcall(self.adapter.removeKeyBinding,self.adapter,id)
    if called and ok then self.ids[key]=nil; removed[id]=true; removed[tostring(id)]=true; self.retiredIds[id]=true; self.retiredIds[tostring(id)]=true
    else failed[key]=called and (err or "Mudlet rejected key removal") or tostring(ok) end
  end
  if next(failed) then return nil,failed,removed end
  self.applied=nil
  return true,nil,removed
end
function Keybindings:start()
  local active=0; for _ in pairs(self.ids) do active=active+1 end
  if sameConfig(self.applied,self.config) and active==configuredCount(self.config) then self.conflicts={}; return true,self:status() end
  local stopped,removeErrors=self:stop(); self.conflicts={}
  if not stopped then for key,why in pairs(removeErrors) do self.conflicts[key]="could not remove previous binding: "..tostring(why) end; return true,self:status() end
  if not self.config.enabled then self.applied=copy(self.config); return true,self:status() end
  local blocked={}
  for _,key in ipairs(Keybindings.order) do local command=self.config.commands[key]; if command~="" then local used,why=self.adapter:isKeyBindingUsed(key,nil,self.retiredIds); if used then blocked[key]=why or "already assigned" end end end
  if next(blocked) then self.conflicts=blocked; return true,self:status() end
  for _,key in ipairs(Keybindings.order) do local command=self.config.commands[key]; if command~="" then local sentCommand=command; local id,err=self.adapter:addKeyBinding(key,function() return self.adapter:sendCommand(sentCommand) end); if not id then local rolledBack,rollbackErrors=self:stop(); self.conflicts[key]=err or "could not install"; if not rolledBack then for rollbackKey,rollbackErr in pairs(rollbackErrors) do self.conflicts[rollbackKey]="could not remove partial binding: "..tostring(rollbackErr) end end; return true,self:status() end; self.ids[key]=id end end
  self.applied=copy(self.config)
  return true,self:status()
end
function Keybindings:status() local active=0; for _ in pairs(self.ids) do active=active+1 end; local conflicts={}; for _,key in ipairs(Keybindings.order) do if self.conflicts[key] then conflicts[#conflicts+1]="Numpad "..(Keybindings.labels[key] or key).." ("..self.conflicts[key]..")" end end; return {enabled=self.config.enabled,active=active,conflicts=conflicts} end
function Keybindings:configure(config) local valid,err=Keybindings.validate(config); if not valid then return nil,err end; local saved,saveErr=self.adapter:saveKeybindingSettings(valid); if not saved then return nil,"Could not save keybindings: "..tostring(saveErr) end; self.config=valid; local _,status=self:start(); return true,nil,self:snapshot(),status end
return Keybindings
