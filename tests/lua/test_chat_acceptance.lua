local Main=require("main")

local function fakeChatRuntimeWithPersonalTrigger()
  local f={next=0,borders={0,0,0,0},callbacks={},events={},aliases={},triggers={},timers={},chatEntries={},character="Dace Alterac"}
  function f:getBorders() return self.borders[1],self.borders[2],self.borders[3],self.borders[4] end
  function f:setBorders() end
  function f:getWindowSize() return 1920,1080 end
  function f:createView() return {root={},update=function() end,applyLayout=function() end,renderChat=function() end,setChatFilterCallback=function() end,delete=function() end} end
  function f:addEvent(name,fn) self.next=self.next+1; local id="event-"..self.next; self.events[id]={name=name,fn=fn}; return id end
  function f:killEvent(id) self.events[id]=nil end
  function f:addAlias(pattern,fn) self.next=self.next+1; local id="alias-"..self.next; self.aliases[id]={pattern=pattern,fn=fn}; return id end
  function f:killAlias(id) self.aliases[id]=nil end
  function f:addLineTrigger(fn) self.next=self.next+1; local id="trigger-"..self.next; self.triggers[id]=fn; return id end
  function f:addColorizerTrigger(fn) self.next=self.next+1; local id="trigger-"..self.next; self.triggers[id]=fn; return id end
  function f:applyLineColors() return true end
  function f:reportColorizerStatus(enabled) self.reportedColorizer=enabled; return true end
  function f:killTrigger(id) self.triggers[id]=nil end
  function f:line(value) for _,fn in pairs(self.triggers) do fn(value) end end
  function f:getGMCP() return {Char={Status={name="Dace",surname="Alterac"},Vitals={hp=1,hp_max=1}}} end
  function f:isCharacterActive() return false end
  function f:epoch() return self.epochValue or 100 end
  function f:timestamp() return "2026-08-31T13:00:00-04:00" end
  function f:reportChatErrorOnce() self.chatErrorReports=(self.chatErrorReports or 0)+1 end
  function f:reportChatStatus(status) self.reportedChatStatus=status; return status end
  function f:schedule(_,fn) self.next=self.next+1; local id="timer-"..self.next; self.timers[id]=fn; return id end
  function f:cancelTimer(id) self.timers[id]=nil end
  function f:sendCommand() end
  function f:createChatStorage()
    local storage={entries=self.chatEntries}
    function storage:loadRecent() return self.entries end
    function storage:append(entry)
      if f.storageFailure then return nil,f.storageFailure end
      self.entries[#self.entries+1]=entry
      return true
    end
    function storage:close() return true end
    function storage:characterKey() return "profile" end
    return storage
  end
  return f
end

local function findAlias(runtime,pattern)
  for _,alias in pairs(runtime.aliases) do if alias.pattern==pattern then return alias.fn end end
end

test("capture reload shutdown and chat status preserve personal runtime",function()
  local runtime=fakeChatRuntimeWithPersonalTrigger()
  local personal=runtime:addLineTrigger(function(line)
    runtime.personalTrigger=true
    if line=="The quest begins." then DGHUD.chat.capture("QUEST",line) end
  end)
  local hud=Main.new(runtime,{layout={},chat={enabled=true,visible_limit=1000,dedupe_seconds=3}})
  DGHUD={controller=hud}; Main.installChatApi(DGHUD)
  eq(hud:start(),true); runtime:line('Tekk (ESP): "hello"'); runtime:line("The quest begins.")
  eq(hud.chat:entries()[1].message,"hello"); eq(hud.chat:entries()[2].category,"QUEST")
  runtime.storageFailure="disk full"; runtime.epochValue=104; assert(DGHUD.chat.capture("QUEST","still visible"))
  assert(DGHUD.chat.setFilter("QUEST"))
  local status=findAlias(runtime,"^dghud chatstatus$")(); eq(status.active_filter,"QUEST"); eq(status.visible_count,2)
  eq(status.storage_key,"profile"); eq(status.last_storage_error,"disk full"); eq(runtime.reportedChatStatus,status)
  hud:reload(); eq(runtime.triggers[personal]~=nil,true); eq(runtime.personalTrigger,true); eq(hud.chat:entries()[1].message,"hello")
  hud:shutdown(); eq(runtime.triggers[personal]~=nil,true); DGHUD=nil
end)

test("disabled chat leaves personal trigger runtime untouched",function()
  local runtime=fakeChatRuntimeWithPersonalTrigger()
  local personal=runtime:addLineTrigger(function() runtime.personalTrigger=true end)
  local hud=Main.new(runtime,{layout={},chat={enabled=false}})
  eq(hud:start(),true); eq(hud.chat,nil); eq(hud:healthCheck(),true)
  runtime:line("personal line"); eq(runtime.personalTrigger,true); hud:shutdown(); eq(runtime.triggers[personal]~=nil,true)
end)
