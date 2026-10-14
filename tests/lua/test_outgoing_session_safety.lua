local Main=require("main")
local Adapter=require("mudlet_adapter")
local Settings=require("settings")

-- Reuse only the existing mock fixture; do not execute or register its tests.
local ownPath=debug.getinfo(1,"S").source:sub(2)
local runtimePath=ownPath:gsub("test_outgoing_session_safety%.lua$","test_runtime.lua")
local runtimeFile=assert(io.open(runtimePath,"rb"))
local runtimeSource=runtimeFile:read("*a"); runtimeFile:close()
local fixtureSource=assert(runtimeSource:match("^(.-)\ntest%("),"runtime fixture boundary missing")
local runtimeFake=assert(loadstring(fixtureSource.."\nreturn fake","@"..runtimePath..":fixture"))()
assert(type(runtimeFake)=="function","runtime fake missing")

local numericPrompt="[199] 299/299 hp, 188/188 ftg >"
local biography=[[You are Synthetic Tester, a light boned and muscular bodied 57 year old Entropic Male young Elder. You are 7'7" and weigh 239 lbs. You are satiated. Your thirst is quenched.]]

local function withRuntime(enabled,currentLine,run)
  local globalNames={"DGHUD","gmcp","getCurrentLine","doSpeedWalk","standing","sitting","unconscious"}
  local previous={}
  for _,key in ipairs(globalNames) do previous[key]=rawget(_G,key) end
  local f=runtimeFake()
  f.character_active=true -- Deliberately independent of the trusted session gate.
  f.currentLine=currentLine or "Password:"
  f.gmcp={Char={Status={name="Synthetic",surname="Tester"},Vitals={hp=299,hp_max=299}}}
  getCurrentLine=function() return f.currentLine end
  gmcp=f.gmcp
  function f:hasConfirmedCharacterPrompt() return Adapter.hasConfirmedCharacterPrompt(self) end

  -- Native anonymous event handles are positive integers. Preserve numeric
  -- fixture IDs; remap legacy string IDs in their existing dispatch slot.
  local addEvent=f.addEvent
  function f:addEvent(name,callback)
    if name=="sysDataSendRequest" and self.observerFailure then
      if self.observerFailure=="throw" then error("synthetic observer registration failure") end
      if self.observerFailure=="false" then return false,"synthetic observer registration failure" end
      return nil,"synthetic observer registration failure"
    end
    local oldID=addEvent(self,name,callback); local id=self.next
    if oldID~=id then
      self.events[id]=self.events[oldID]; self.eventFns[id]=self.eventFns[oldID]
      self.events[oldID]=nil; self.eventFns[oldID]=nil
      self.eventOrder[#self.eventOrder]=id
    end
    return id
  end
  function f:line(value)
    self.currentLine=value
    local callbacks={}
    for _,callback in pairs(self.triggers) do callbacks[#callbacks+1]=callback end
    for _,callback in ipairs(callbacks) do callback(value) end
  end
  function f:outgoing(message)
    self:emit("sysDataSendRequest","sysDataSendRequest","contact all "..message)
  end
  local createView=f.createView
  function f:createView(settings)
    local view=createView(self,settings)
    function view:setChatPresentation(outgoing,combined)
      self.chat_capture_outgoing=outgoing; self.chat_combine_links=combined
      return true
    end
    return view
  end
  local settings=Settings.resolve(require("defaults"),{
    chat={capture_outgoing=enabled,combine_links=false},
    update={auto_apply=false},mapper={enabled=false},colorization={enabled=false},
  })
  local hud=Main.new(f,settings)
  DGHUD={controller=hud,settings=settings,user_settings={chat={capture_outgoing=enabled,combine_links=false}}}
  f.savedChatSettings=Settings.merge({},settings.chat)
  local ok,err=xpcall(function()
    assert(hud:start())
    run(hud,f)
  end,debug.traceback)
  local cleaned,cleanupErr=pcall(hud.shutdown,hud)
  for _,key in ipairs(globalNames) do rawset(_G,key,previous[key]) end
  if not ok then error(err,0) end
  assert(cleaned,cleanupErr)
end

local function freshInfo(hud,f,text)
  hud.collector:cancelActive()
  hud.collector.sequence_index=nil
  assert(hud.collector:begin("info",false))
  f:line(text)
  f:line("HP: 299 of 299 Ftg: 188 of 188 Carry: 2 of 100 lbs.")
  eq(hud.outgoing_session_confirmed==true,false)
  f:line(">")
end

test("outgoing safety rejects password and generic prompts despite cached GMCP and active adapter",function()
  for _,prompt in ipairs({"Password:","Account name:",">"}) do
    withRuntime(true,prompt,function(hud,f)
      eq(f:isCharacterActive(),true)
      eq(f:hasConfirmedCharacterPrompt(),false)
      eq(hud.outgoing_session_confirmed==true,false)
      eq(hud.chat:outgoingCharacter(),nil)
      local sent=#(f.sentCommands or {})
      f:outgoing("synthetic authentication input")
      eq(f.chatStorageAppends or 0,0)
      eq(#hud.chat.history.items,0)
      eq(#hud.chat.outgoing.pending,0)
      eq(#(f.sentCommands or {}),sent)
    end)
  end
end)

test("outgoing safety accepts a real welcome after an unconfirmed cached session",function()
  withRuntime(true,"Password:",function(hud,f)
    f:line("Welcome to Dragon's Gate, Synthetic Tester!")
    eq(hud.outgoing_session_confirmed,true)
    f:outgoing("welcome confirmed")
    eq(f.chatStorageAppends,1)
    eq(f.chatEntries[1].character,"Synthetic Tester")
    eq(f.chatEntries[1].source,"outgoing")
  end)
end)

test("outgoing safety accepts a numeric character prompt at cold startup",function()
  withRuntime(true,"\27[32m"..numericPrompt.."\27[0m",function(hud,f)
    eq(f:hasConfirmedCharacterPrompt(),true)
    eq(hud.outgoing_session_confirmed,true)
    f:outgoing("cold prompt confirmed")
    eq(f.chatStorageAppends,1)
  end)
end)

test("outgoing safety accepts fresh numeric prompt output after unconfirmed startup",function()
  withRuntime(true,"Password:",function(hud,f)
    f:line(numericPrompt)
    eq(hud.outgoing_session_confirmed,true)
    f:outgoing("fresh prompt confirmed")
    eq(f.chatStorageAppends,1)
  end)
end)

test("outgoing safety confirms only fresh completed owned INFO",function()
  withRuntime(true,"Password:",function(hud,f)
    -- A hydrated snapshot alone must never establish a logged-in session.
    hud.collector.snapshot.info={character={full_name="Synthetic Tester"},condition_text="You are satiated."}
    hud:refresh()
    f:outgoing("cached INFO is not confirmation")
    eq(f.chatStorageAppends or 0,0)
    freshInfo(hud,f,biography)
    eq(hud.outgoing_session_confirmed,true)
    f:outgoing("fresh owned INFO confirmed")
    eq(f.chatStorageAppends,1)
    eq(f.chatEntries[1].character,"Synthetic Tester")
  end)
end)

test("outgoing safety rejects fresh foreign INFO despite matching cached GMCP",function()
  withRuntime(true,"Password:",function(hud,f)
    freshInfo(hud,f,biography:gsub("Synthetic Tester","Other Tester"))
    eq(hud.outgoing_session_confirmed==true,false)
    f:outgoing("foreign INFO is not confirmation")
    eq(f.chatStorageAppends or 0,0)
  end)
end)

for _,exit in ipairs({"menu","disconnect","logout"}) do
  local action=exit
  test("outgoing safety clears confirmed session on "..action.." while GMCP remains cached",function()
    withRuntime(true,"Password:",function(hud,f)
      f:line("Welcome to Dragon's Gate, Synthetic Tester!")
      f:outgoing("before "..action); eq(f.chatStorageAppends,1)
      if action=="menu" then f:line("Dragon's Gate Menu")
      elseif action=="disconnect" then f:emit("sysDisconnectionEvent","sysDisconnectionEvent")
      else hud:onCharacterExit("logout") end
      f.currentLine="Password:"
      eq(f.gmcp.Char.Status.name,"Synthetic")
      eq(f:isCharacterActive(),true)
      eq(hud.outgoing_session_confirmed==true,false)
      f:outgoing("after "..action); eq(f.chatStorageAppends,1)
      eq(#hud.chat.outgoing.pending,0)
      -- Menu/disconnect also reset the collector's welcome identity. The direct
      -- logout hook above exercises session invalidation without inventing UI.
      if action~="logout" then
        f:line("Welcome to Dragon's Gate, Synthetic Tester!")
        f:outgoing("reentered "..action); eq(f.chatStorageAppends,2)
      end
    end)
  end)
end

for _,failure in ipairs({"throw","nil","false"}) do
  local mode=failure
  test("outgoing safety leaves OFF settings unchanged when observer registration returns "..mode,function()
    withRuntime(false,"Password:",function(hud,f)
      local disk=f.savedChatSettings
      f.observerFailure=mode
      local accepted,err=hud:setChatPreference("capture_outgoing",true)
      eq(accepted,nil); assert(type(err)=="string" and #err>0)
      eq(f.chatSettingsSaves or 0,0); eq(f.savedChatSettings,disk)
      eq(hud.settings.chat.capture_outgoing,false)
      eq(DGHUD.user_settings.chat.capture_outgoing,false)
      eq(hud.chat.captureOutgoing,false); eq(hud.chat.outgoingEvent,nil)
      eq(hud.view.chat_capture_outgoing,false)
    end)
  end)
end

test("outgoing safety rolls observer activation back when saving the ON preference fails",function()
  withRuntime(false,"Password:",function(hud,f)
    local disk=f.savedChatSettings; local observer
    f.failChatSettingsSave="synthetic disk failure"
    f.onChatSettingsSave=function(config)
      eq(config.capture_outgoing,true); eq(hud.chat.captureOutgoing,true)
      observer=hud.chat.outgoingEvent
      assert(type(observer)=="number" and f.events[observer]=="sysDataSendRequest")
    end
    local accepted,err=hud:setChatPreference("capture_outgoing",true)
    eq(accepted,nil); assert(err:find("synthetic disk failure",1,true))
    eq(f.chatSettingsSaves,1); eq(f.savedChatSettings,disk)
    eq(hud.settings.chat.capture_outgoing,false)
    eq(DGHUD.user_settings.chat.capture_outgoing,false)
    eq(hud.chat.captureOutgoing,false); eq(hud.chat.outgoingEvent,nil)
    eq(f.events[observer],nil); eq(f.killed[observer],true)
    eq(hud.view.chat_capture_outgoing,false)
  end)
end)

test("outgoing safety saves successful activation and disabling removes only its observer",function()
  withRuntime(false,"Password:",function(hud,f)
    eq(hud:setChatPreference("capture_outgoing",true),true)
    local observer=hud.chat.outgoingEvent
    eq(f.savedChatSettings.capture_outgoing,true)
    eq(DGHUD.user_settings.chat.capture_outgoing,true)
    eq(hud.view.chat_capture_outgoing,true)
    f:line("Welcome to Dragon's Gate, Synthetic Tester!")
    f:outgoing("enabled"); eq(f.chatStorageAppends,1)
    eq(hud:setChatPreference("capture_outgoing",false),false)
    eq(f.savedChatSettings.capture_outgoing,false)
    eq(DGHUD.user_settings.chat.capture_outgoing,false)
    eq(f.events[observer],nil); eq(hud.chat.outgoingEvent,nil)
    eq(hud.view.chat_capture_outgoing,false)
    f:outgoing("disabled"); eq(f.chatStorageAppends,1)
    eq(hud:healthCheck(),true)
  end)
end)

test("outgoing safety repeated start preserves confirmed session and one observer on nonnumeric output",function()
  withRuntime(true,numericPrompt,function(hud,f)
    local observer=hud.chat.outgoingEvent
    local registrations=#f.eventOrder
    local eventCount=f:count(f.events)
    eq(hud.outgoing_session_confirmed,true)
    f.currentLine="A synthetic guard looks around."
    eq(f:hasConfirmedCharacterPrompt(),false)
    for _=1,3 do
      eq(hud:start(),true)
      eq(hud.outgoing_session_confirmed,true)
      eq(hud.chat.outgoingEvent,observer)
      eq(f.events[observer],"sysDataSendRequest")
      eq(#f.eventOrder,registrations)
      eq(f:count(f.events),eventCount)
    end
    local occurrences=0
    for _,id in ipairs(f.eventOrder) do if id==observer then occurrences=occurrences+1 end end
    eq(occurrences,1)
    f:outgoing("still confirmed after repeated start")
    eq(f.chatStorageAppends,1)
    eq(hud:healthCheck(),true)
  end)
end)

test("outgoing safety health check rejects enabled capture with a missing observer",function()
  withRuntime(true,numericPrompt,function(hud,f)
    eq(hud:healthCheck(),true)
    f:killEvent(hud.chat.outgoingEvent); hud.chat.outgoingEvent=nil
    local healthy,err=hud:healthCheck()
    eq(healthy,nil); assert(type(err)=="string" and #err>0)
  end)
end)
