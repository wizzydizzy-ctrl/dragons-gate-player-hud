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
function Keybindings.new(adapter,config) local valid,err=Keybindings.validate(config or Keybindings.defaults); if not valid then error(err,0) end; return setmetatable({adapter=adapter,config=valid,ids={},conflicts={}},Keybindings) end
function Keybindings:snapshot() return copy(self.config) end
function Keybindings:stop() for _,id in pairs(self.ids) do pcall(self.adapter.removeKeyBinding,self.adapter,id) end; self.ids={}; return true end
function Keybindings:start()
  self:stop(); self.conflicts={}; if not self.config.enabled then return true,self:status() end
  local blocked={}
  for _,key in ipairs(Keybindings.order) do local command=self.config.commands[key]; if command~="" then local used,why=self.adapter:isKeyBindingUsed(key); if used then blocked[key]=why or "already assigned" end end end
  if next(blocked) then self.conflicts=blocked; return true,self:status() end
  for _,key in ipairs(Keybindings.order) do local command=self.config.commands[key]; if command~="" then local sentCommand=command; local id,err=self.adapter:addKeyBinding(key,function() return self.adapter:sendCommand(sentCommand) end); if not id then self:stop(); self.conflicts[key]=err or "could not install"; return true,self:status() end; self.ids[key]=id end end
  return true,self:status()
end
function Keybindings:status() local active=0; for _ in pairs(self.ids) do active=active+1 end; local conflicts={}; for _,key in ipairs(Keybindings.order) do if self.conflicts[key] then conflicts[#conflicts+1]="Numpad "..(Keybindings.labels[key] or key).." ("..self.conflicts[key]..")" end end; return {enabled=self.config.enabled,active=active,conflicts=conflicts} end
function Keybindings:configure(config) local valid,err=Keybindings.validate(config); if not valid then return nil,err end; local saved,saveErr=self.adapter:saveKeybindingSettings(valid); if not saved then return nil,"Could not save keybindings: "..tostring(saveErr) end; self.config=valid; local _,status=self:start(); return true,nil,self:snapshot(),status end
return Keybindings
