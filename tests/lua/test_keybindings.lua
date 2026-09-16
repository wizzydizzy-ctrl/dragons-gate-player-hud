local Keybindings=require("keybindings")
local function fake()
  local f={used={},added={},removed={},saved=nil,next=0,sent={}}
  function f:isKeyBindingUsed(key) return self.used[key]==true,self.used[key] and "personal key" or nil end
  function f:addKeyBinding(key,callback) self.next=self.next+1; self.added[key]={id=self.next,callback=callback}; return self.next end
  function f:removeKeyBinding(id) self.removed[id]=true; return true end
  function f:sendCommand(command) self.sent[#self.sent+1]=command; return true end
  function f:saveKeybindingSettings(config) self.saved=config; return true end
  return f
end
test("numpad movement is disabled by default",function() local f=fake(); local manager=Keybindings.new(f,Keybindings.defaults); manager:start(); eq(next(f.added),nil); eq(manager:status().active,0) end)
test("standard and extended keypad commands install as owned temporary callbacks",function()
  local f=fake(); local config=assert(Keybindings.validate(Keybindings.defaults)); config.enabled=true; local manager=Keybindings.new(f,config); manager:start(); eq(manager:status().active,11); f.added["8"].callback(); f.added.Plus.callback(); f.added.Minus.callback(); eq(table.concat(f.sent,","),"north,up,down"); manager:stop(); eq(f.removed[f.added["8"].id],true)
end)
test("one personal collision leaves the complete HUD keypad inactive",function() local f=fake(); f.used["8"]=true; local config=assert(Keybindings.validate(Keybindings.defaults)); config.enabled=true; local manager=Keybindings.new(f,config); manager:start(); eq(next(f.added),nil); eq(#manager:status().conflicts,1) end)
test("custom commands validate persist and blank keys stay unassigned",function() local f=fake(); local manager=Keybindings.new(f,Keybindings.defaults); local config=manager:snapshot(); config.enabled=true; config.commands["8"]="  swim north  "; config.commands["9"]=""; local ok,err,saved=manager:configure(config); eq(ok,true); eq(err,nil); eq(saved.commands["8"],"swim north"); eq(f.added["9"],nil); eq(f.saved.commands["8"],"swim north") end)
test("restart ignores only the HUD temporary keys Mudlet is still retiring",function()
  local f=fake(); local config=assert(Keybindings.validate(Keybindings.defaults)); config.enabled=true
  function f:isKeyBindingUsed(_,_,ignored) for _,entry in pairs(self.added) do if not (ignored and ignored[entry.id]) then return true,"old HUD key still visible" end end; return false end
  local manager=Keybindings.new(f,config); manager:start(); eq(manager:status().active,11); manager:start(); eq(manager:status().active,11); eq(#manager:status().conflicts,0)
end)
test("failed key removal stays visible and prevents a duplicate install",function()
  local f=fake(); local config=assert(Keybindings.validate(Keybindings.defaults)); config.enabled=true; local manager=Keybindings.new(f,config); manager:start()
  function f:removeKeyBinding() return nil,"busy" end
  manager:start(); eq(manager:status().active,11); eq(#manager:status().conflicts,11)
end)
test("Mudlet adapter uses symbolic keypad codes and removes only returned IDs",function()
  local Adapter=require("mudlet_adapter"); local calls={}; local api={mudlet={key={["8"]=56},keymodifier={Keypad=512}}}
  function api.findItems(name,itemType,exact) calls.find={name,itemType,exact}; return {11} end
  function api.getKeyCode(id) calls.used=id; return 65,0 end
  function api.tempKey(modifier,code,callback) calls.added={modifier,code,callback}; return 77 end
  function api.killKey(id) calls.killed=id; return true end
  local adapter=Adapter.new(); eq(adapter:isKeyBindingUsed("8",api),false); eq(calls.find[2],"keybind"); eq(calls.used,11); eq(adapter:addKeyBinding("8",function() end,api),77); eq(adapter:removeKeyBinding(77,api),true); eq(calls.killed,77)
  function api.getKeyCode() return 56,512 end; local used,why=adapter:isKeyBindingUsed("8",api); eq(used,true); eq(why,"already assigned in Mudlet")
  function api.getKeyCode() return nil,"missing" end; used,why=adapter:isKeyBindingUsed("8",api); eq(used,true); eq(why,"collision detection failed")
  used=adapter:isKeyBindingUsed("8",api,{[11]=true}); eq(used,false)
  function api.killKey() return nil,"missing" end; local removed,removeErr=adapter:removeKeyBinding(77,api); eq(removed,nil); eq(removeErr,"missing")
  function api.tempKey() return -1 end; local rejected,rejectedErr=adapter:addKeyBinding("8",function() end,api); eq(rejected,nil); eq(rejectedErr,"Mudlet rejected the binding")
end)
