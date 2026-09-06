local Main=require("main")
local MudletAdapter=require("mudlet_adapter")
local MapAdapter=require("map_adapter")
local MapperModel=require("mapper_model")
local Events=require("events")
local function fake()
  local f={next=0,killed={},deleted=0,borders={10,20,30,40},set_borders={},callbacks={},layouts={},triggers={},timers={},timer_delays={},timer_cancels={},events={},aliases={}}
  function f:getBorders() return self.borders[1],self.borders[2],self.borders[3],self.borders[4] end
  function f:setBorders(a,b,c,d) self.set_borders={a,b,c,d} end
  function f:getWindowSize() return self.width or 1920,self.height or 1080 end
  function f:createView() return {
    update=function(self,state) self.state=state; f.viewUpdates=(f.viewUpdates or 0)+1 end,
    updateClock=function(self,clock) self.state.clock=clock; f.clockUpdates=(f.clockUpdates or 0)+1 end,
    applyLayout=function(self,layout) f.layouts[#f.layouts+1]=layout end,
    renderChat=function(self,entries,categories,filter) f.chatRenders=(f.chatRenders or 0)+1; f.renderedChat={entries=entries,categories=categories,filter=filter} end,
    setChatFilterCallback=function(self,callback) f.chatFilterCallback=callback end,
    setColorToggleCallback=function(self,callback) f.colorToggleCallback=callback end,
    setColorOptionsCallback=function(self,callback) f.colorOptionsCallback=callback end,
    setColorOptions=function(self,options) f.viewColorOptions=options; f.viewColorEnabled=options.enabled end,
    setColorEnabled=function(self,enabled) f.viewColorEnabled=enabled end,
    setOptionsActionCallback=function(self,callback) f.optionsActionCallback=callback end,
    setRollerSettingsCallback=function(self,callback) f.rollerSettingsCallback=callback end,
    setMapCenterCallback=function(self,callback) f.mapCenterCallback=callback end,
    setMapZoomCallback=function(self,callback) f.mapZoomCallback=callback; f.mapZoomCallbackSets=(f.mapZoomCallbackSets or 0)+1 end,
    setMapClearAllCallback=function(self,callback) f.mapClearAllCallback=callback end,
    setMapClearPending=function(self,pending) f.mapClearPending=pending end,
    centerMap=function(self,roomID) f.centeredRooms=f.centeredRooms or {}; f.centeredRooms[#f.centeredRooms+1]=roomID; return true end,
    delete=function() f.deleted=f.deleted+1 end,
  } end
  function f:addEvent(name,fn) self.next=self.next+1; self.callbacks[name]=fn; local id="event-"..self.next; self.events[id]=name; return id end
  function f:addAlias(pattern,fn) self.next=self.next+1; local id="alias-"..self.next; self.aliases[id]={pattern=pattern,fn=fn}; return id end
  function f:killEvent(id) self.killed[id]=true; self.events[id]=nil end
  function f:killAlias(id) self.killed[id]=true; self.aliases[id]=nil end
  function f:getGMCP() return self.gmcp or {Char={Vitals={hp=1,hp_max=1}}} end
  function f:isCharacterActive() return self.character_active==true end
  function f:consumeUpdateReinstall() local pending=self.update_reinstall==true; self.update_reinstall=false; return pending end
  function f:addLineTrigger(fn)
    self.lineTriggerCalls=(self.lineTriggerCalls or 0)+1
    if self.failChatTrigger and self.lineTriggerCalls==2 then error("chat trigger registration failed") end
    self.next=self.next+1; local id="trigger-"..self.next; self.triggers[id]=fn; return id
  end
  function f:addColorizerTrigger(fn)
    self.next=self.next+1; local id="trigger-"..self.next; self.triggers[id]=fn; self.colorizerTrigger=id; return id
  end
  function f:applyLineColors(segments) self.coloredSegments=segments; return true end
  function f:reportColorizerStatus(enabled) self.reportedColorizer=enabled; return true end
  function f:killTrigger(id) self.killed[id]=true; self.triggers[id]=nil end
  function f:epoch() return self.epochValue or 100 end
  function f:localTime() return self.localTimeValue or "12:41:06 AM" end
  function f:startClockTimer(fn) self.next=self.next+1; local id="clock-"..self.next; self.clockTimers=self.clockTimers or {}; self.clockTimers[id]=fn; return id end
  function f:stopClockTimer(id) self.clockTimerStopped=id; self.clockTimers[id]=nil; return true end
  function f:cleanupClock() return self.cleanupTime or 1000 end
  function f:cleanupToken() self.cleanupTokenCalls=(self.cleanupTokenCalls or 0)+1; return self.cleanupTokenValue or "ABC123" end
  function f:reportMapCleanup(message,isError)
    self.cleanupReports=self.cleanupReports or {}; self.cleanupReports[#self.cleanupReports+1]={message=tostring(message),error=isError==true}; return true
  end
  function f:refreshMap() self.mapRefreshes=(self.mapRefreshes or 0)+1; if self.refreshMapError then return nil,self.refreshMapError end; return true end
  function f:timestamp() return self.timestampValue or "2026-08-31T13:00:00-04:00" end
  function f:reportChatErrorOnce() self.chatErrors=(self.chatErrors or 0)+1 end
  function f:createChatStorage(visibleLimit)
    f.chatVisibleLimit=visibleLimit
    f.chatEntries=f.chatEntries or {}; local storage={entries=f.chatEntries}
    function storage:characterKey(character)
      local key=tostring(character or ""):lower():gsub("[^a-z0-9_-]+","_"):gsub("_+","_"):gsub("^_+",""):gsub("_+$","")
      return key~="" and key or "unknown"
    end
    function storage:loadRecent(character)
      f.loadRecentCalls=(f.loadRecentCalls or 0)+1
      local key=self:characterKey(character); f.loadedCharacterKeys=f.loadedCharacterKeys or {}; f.loadedCharacterKeys[#f.loadedCharacterKeys+1]=key
      if f.chatEntriesByKey then return f.chatEntriesByKey[key] or {} end
      return self.entries
    end
    function storage:append(entry) f.chatStorageAppends=(f.chatStorageAppends or 0)+1; self.entries[#self.entries+1]=entry; return true end
    function storage:close() if f.onStorageClose then f.onStorageClose() end; return true end
    return storage
  end
  function f:schedule(delay,fn)
    if self.failSchedule=="return" then return nil,"special schedule failed" end
    if self.failSchedule=="throw" then error("special schedule exploded") end
    self.next=self.next+1; local id="timer-"..self.next; self.timers[id]=fn; self.timer_delays[id]=delay; return id
  end
  function f:cancelTimer(id)
    self.timer_cancels[id]=(self.timer_cancels[id] or 0)+1
    self.timers[id]=nil
    if self.failCancel then error("special cancellation exploded") end
    return true
  end
  function f:fireTimer() local id,fn=next(self.timers); if id then self.timers[id]=nil; fn() end end
  function f:sendCommand(command) self.sent=command; self.sentCommands=self.sentCommands or {}; self.sentCommands[#self.sentCommands+1]=command; return true end
  function f:saveRollerSettings(config) self.savedRollerSettings=config; return true end
  function f:count(tableValue) local n=0; for _ in pairs(tableValue) do n=n+1 end; return n end
  function f:createMapAdapter()
    local map={rooms={},areas={},areaNames={},stubs={},links={},special={},current=nil,shutdowns=0,api={}}
    function map.api.getAreaTable() local result={}; for name,id in pairs(map.areaNames) do result[name]=id end; return result end
    function map:migrateLegacyRoomNames() f.mapLabelMigrations=(f.mapLabelMigrations or 0)+1; return 0,false end
    function map:ensureRoom(room,coordinates,partition)
      local record=self.rooms[room.id]
      if record then record.room=room else self.rooms[room.id]={room=room,coordinates=coordinates,partition=partition or room.area_key,game_area=room.area_key,owned=true} end
      return true
    end
    function map:ensureStub() return true end
    function map:connect(from,to,direction,reverse) self.links[#self.links+1]={from=from,to=to,direction=direction,reverse=reverse}; return true end
    function map:connectSpecial(from,to,command)
      if f.failSpecialMap=="return" then return nil,"special mapping failed" end
      if f.failSpecialMap=="throw" then error("special mapping exploded") end
      self.special[#self.special+1]={from=from,to=to,command=command}; return true
    end
    function map:setCurrent(id) self.current=id; return self:center(id) end
    function map:center(id) self.centered=id; f.mapCenterCalls=(f.mapCenterCalls or 0)+1; return true end
    function map:zoom(id,action,step,minimum,maximum)
      f.mapZoomCalls=f.mapZoomCalls or {}; f.mapZoomCalls[#f.mapZoomCalls+1]={id,action,step,minimum,maximum}
      if f.zoomError then return nil,f.zoomError end
      return f.zoomResult or 17.5
    end
    function map:coordinates(id) local item=self.rooms[id]; return item and item.coordinates end
    function map:roomRecord(id)
      local record=self.rooms[id]
      if not record then return {exists=false,owned=false,placement_needed=true} end
      return {exists=true,owned=record.owned,coordinates=record.coordinates,partition=record.partition,game_area=record.game_area,area=record.area}
    end
    function map:areaRecord(id) local area=self.areas[id]; if not area then return {id=id,exists=false,owned=false} end; return {id=id,exists=true,owned=area.owned} end
    function map:roomsInArea(id) local result={}; for roomID,record in pairs(self.rooms) do if record.area==id then result[#result+1]=roomID end end; table.sort(result); return result end
    function map:inboundSources() return {} end
    function map:deleteOwnedRoom(id) local record=self.rooms[id]; if not record or not record.owned then return nil,"room is not owned" end; self.rooms[id]=nil; return true end
    function map:deleteEmptyOwnedArea(id) if #self:roomsInArea(id)>0 then return nil,"area is not empty" end; if not self.areas[id] or not self.areas[id].owned then return nil,"area is not owned" end; self.areas[id]=nil; return true end
    function map:invalidateDeleted(ids,areaID) self.invalidated={ids=ids,area_id=areaID}; return true end
    function map:effectivePartition(id) local record=self.rooms[id]; return record and record.partition end
    function map:roomsAt() return {} end
    function map:isOwned(id) return self.rooms[id]~=nil end
    function map:route(fromID,toID)
      if f.routeError then return nil,f.routeError end
      return f.route or {rooms={fromID,toID},commands={"n"}}
    end
    function map:validateRouteStep(from,to,command)
      local direction=MapperModel.direction(command)
      if direction then
        for _,link in ipairs(self.links) do
          if link.from==from and link.to==to and link.direction==direction then return true,direction end
        end
        local route=f.route
        if type(route)=="table" then
          for index,routeCommand in ipairs(route.commands or {}) do
            if route.rooms[index]==from and route.rooms[index+1]==to and MapperModel.direction(routeCommand)==direction then return true,direction end
          end
        end
        return nil,"standard exit is not persisted from "..from.." to "..to
      end
      for _,exit in ipairs(self.special) do
        if exit.from==from and exit.to==to and exit.command==tostring(command):match("^%s*(.-)%s*$") and self:isOwned(from) and self:isOwned(to) then return true,exit.command end
      end
      return nil,"special exit is not confirmed from "..from.." to "..to
    end
    self.createdMaps=(self.createdMaps or 0)+1; self.map=map; return map
  end
  function f:suppressDefaultMapInfo() self.mapInfoSuppressions=(self.mapInfoSuppressions or 0)+1; return true end
  function f:reportMapperStatus(kind,message) self.mapperStatuses=self.mapperStatuses or {}; self.mapperStatuses[#self.mapperStatuses+1]={kind,message} end
  return f
end

test("runtime synchronizes game time ticks header clock and removes its owned timer",function()
  local f=fake(); local hud=Main.new(f,{layout={},chat={enabled=false},mapper={enabled=false},time={speed=2,sunrise_hour=6,sunset_hour=18},theme={background="#000",panel="#111",border="#222",text="#fff",muted="#888",accent="#da5",jade="#7b8",hp="#b54",fatigue="#8a4",gold="#db4",silver="#ccc"}})
  assert(hud:start()); hud.collector.snapshot.time={hour=17,minute=59,day=4,month=8,year=362}; hud:onClockSync(hud.collector.snapshot.time)
  eq(f.createView and hud.last_state.clock.real_time,"12:41:06 AM"); eq(hud.last_state.clock.game_time,"5:59 PM"); eq(hud.last_state.clock.period,"Daytime")
  local fullUpdates=f.viewUpdates; f.epochValue=130; local timer=hud.clock_timer; assert(timer and f.clockTimers[timer]); f.clockTimers[timer](); eq(hud.last_state.clock.game_time,"6:00 PM"); eq(hud.last_state.clock.period,"Night")
  eq(f.clockUpdates,2); eq(f.viewUpdates,fullUpdates)
  hud:shutdown(); eq(f.clockTimers[timer],nil); eq(f.clockTimerStopped,timer)
end)

test("startup consults the bounded owned-room label migration gate",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); assert(hud:start()); eq(f.mapLabelMigrations,1)
end)
test("startup suppresses only Mudlet's duplicate default map information",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); assert(hud:start()); eq(f.mapInfoSuppressions,1)
end)
test("Mudlet adapter suppresses the Short and Full default map information",function()
  local disabled={}; local updates=0
  local adapter=MudletAdapter.new(); eq(adapter:suppressDefaultMapInfo({
    disableMapInfo=function(name) disabled[#disabled+1]=name end,
    updateMap=function() updates=updates+1 end,
  }),true)
  eq(disabled[1],"Short"); eq(disabled[2],"Full"); eq(#disabled,2); eq(updates,1)
end)

local function gmcpRoom(id)
  return {Char={Vitals={hp=1,hp_max=1}},Room={Info={num=id,name="Room "..id,area=1,exits={}}}}
end

local function aliasCallback(f,pattern)
  for _,alias in pairs(f.aliases) do if alias.pattern==pattern then return alias.fn end end
end

local function addCleanupRoom(f,id,area,partition)
  f.map.areas[area]=f.map.areas[area] or {owned=true}
  f.map.rooms[id]={owned=true,area=area,partition=partition,coordinates={x=0,y=0,z=0}}
end

test("cleanup aliases preview exact targets and confirmation is token-bound",function()
  local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,100,7,"zone")
  local preview=assert(aliasCallback(f,"^dghud map delete room (\\d+)$")); assert(preview({"","100"}))
  eq(hud.cleanup:pending().room_ids[1],100); eq(f.cleanupReports[1].message,"Operation: delete_room\nArea: 7\nCount: 1\nRoom IDs: 100\n[DGHUD Map] Preview ABC123 expires in 30 seconds.\n[DGHUD Map] Confirm with: dghud map confirm ABC123")
  local confirm=assert(aliasCallback(f,"^dghud map confirm (\\S+)$")); local ok,err=confirm({"","WRONG"}); eq(ok,nil); eq(err,"cleanup confirmation token is invalid"); eq(f.map.rooms[100]~=nil,true)
  assert(confirm({"",hud.cleanup:pending().token})); eq(f.map.rooms[100],nil); eq(f.cleanupReports[#f.cleanupReports].message,"Deleted IDs: 100\nFailed ID: none\nUntouched IDs: none\nArea deleted: false")
end)

test("cleanup aliases expose only exact approved command shapes and reject malformed targets",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); assert(hud:start())
  eq(type(aliasCallback(f,"^dghud map delete room (\\d+)$")),"function")
  eq(type(aliasCallback(f,"^dghud map clear submap (\\d+)$")),"function")
  eq(type(aliasCallback(f,"^dghud map clear area (.+)$")),"function")
  eq(type(aliasCallback(f,"^dghud map clear current$")),"function")
  eq(type(aliasCallback(f,"^dghud map confirm (\\S+)$")),"function")
  eq(type(aliasCallback(f,"^dghud map cancel$")),"function")
  eq(type(aliasCallback(f,"^dghud map clear all$")),"function")
  eq(aliasCallback(f,"^dghud map delete room (.+)$"),nil); eq(aliasCallback(f,"^dghud map clear area (.*)$"),nil)
  local ok,err=aliasCallback(f,"^dghud map delete room (\\d+)$")({"","0"}); eq(ok,nil); eq(err,"room ID must be a positive integer")
  eq(f.cleanupReports[#f.cleanupReports].error,true)
end)

test("clear-current alias resolves the live GMCP room and recreates it after confirmation",function()
  local f=fake(); f.gmcp=gmcpRoom(200); local hud=Main.new(f,{layout={}}); assert(hud:start())
  addCleanupRoom(f,200,8,"zone"); addCleanupRoom(f,201,8,"zone"); f.map.areaNames.Alpha=8
  assert(aliasCallback(f,"^dghud map clear current$")())
  local plan=hud.cleanup:pending(); eq(plan.operation,"clear_current"); eq(plan.area_id,8); eq(plan.allow_current,true)
  assert(aliasCallback(f,"^dghud map confirm (\\S+)$")({"",plan.token}))
  eq(f.map.rooms[201],nil); eq(f.map.rooms[200]~=nil,true); eq(f.map.rooms[200].owned,true)
end)

test("map clear button previews then confirms a complete owned-map reset",function()
  local f=fake(); f.gmcp=gmcpRoom(200); local hud=Main.new(f,{layout={}}); assert(hud:start())
  addCleanupRoom(f,200,8,"zone"); addCleanupRoom(f,201,8,"zone"); f.map.areaNames.Alpha=8
  assert(f.mapClearAllCallback()); eq(f.mapClearPending,true); eq(f.map.rooms[200]~=nil,true)
  f.cleanupTime=1001
  assert(f.mapClearAllCallback()); eq(f.mapClearPending,false)
  eq(f.map.areas[8],nil); eq(f.map.rooms[201],nil); eq(f.map.rooms[200]~=nil,true)
  eq(f.map.rooms[200].owned,true); eq(f.cleanupReports[#f.cleanupReports].error,false)
end)
test("map clear button rejects immediate double click while typed confirmation remains immediate",function()
  local f=fake(); f.gmcp=gmcpRoom(200); local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,200,8,"zone"); addCleanupRoom(f,201,8,"zone"); f.map.areaNames.Alpha=8
  assert(f.mapClearAllCallback()); local result,err=f.mapClearAllCallback(); eq(result,nil); eq(err,"wait one second before confirming clear all"); eq(f.map.rooms[201]~=nil,true)
  assert(aliasCallback(f,"^dghud map confirm (\\S+)$")({"",hud.cleanup:pending().token})); eq(f.map.rooms[201],nil)
end)
test("clear-all preview reports bounded counts instead of every room id",function()
  local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start()); for area=1,25 do f.map.areaNames["Area"..area]=area; addCleanupRoom(f,area+1000,area,"zone"..area) end
  assert(f.mapClearAllCallback()); local report=f.cleanupReports[#f.cleanupReports].message; eq(report:find("Rooms: 25 total",1,true)~=nil,true); eq(report:find("Areas: 25 total",1,true)~=nil,true); eq(report:find("Room IDs:",1,true),nil); eq(#report<1000,true)
end)

test("typed clear-all confirmation resets the mapper warning button",function()
  local f=fake(); f.gmcp=gmcpRoom(200); local hud=Main.new(f,{layout={}}); assert(hud:start())
  addCleanupRoom(f,200,8,"zone"); f.map.areaNames.Alpha=8
  assert(f.mapClearAllCallback()); eq(f.mapClearPending,true)
  local token=hud.cleanup:pending().token
  assert(aliasCallback(f,"^dghud map confirm (\\S+)$")({"",token}))
  eq(f.mapClearPending,false)
end)

test("cleanup preview cancellation invalidates the pending token",function()
  local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,100,7,"zone")
  assert(aliasCallback(f,"^dghud map delete room (\\d+)$")({"","100"})); local token=hud.cleanup:pending().token
  assert(aliasCallback(f,"^dghud map cancel$")()); eq(hud.cleanup:pending(),nil); eq(f.cleanupReports[#f.cleanupReports].message,"Cleanup preview cancelled.")
  local ok,err=aliasCallback(f,"^dghud map confirm (\\S+)$")({"",token}); eq(ok,nil); eq(err,"cleanup confirmation token is invalid"); eq(f.map.rooms[100]~=nil,true)
end)

test("cleanup safety blocks current active and uncertain movement state",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,100,7,"zone"); addCleanupRoom(f,101,7,"zone")
  local room=aliasCallback(f,"^dghud map delete room (\\d+)$"); local ok,err=room({"","100"}); eq(ok,nil); eq(err,"cleanup includes the current room")
  hud.walker.route={rooms={100,101},commands={"n"}}; hud.walker.index=1; hud.walker.destination=101
  ok,err=room({"","101"}); eq(ok,nil); eq(err,"map walking is active"); hud.walker.route=nil
  hud.generated_command="n"; ok,err=room({"","101"}); eq(ok,nil); eq(err,"cleanup safety state is unavailable"); hud.generated_command=nil
  _G.speedWalkPath="malformed"; ok,err=room({"","101"}); eq(ok,nil); eq(err,"cleanup safety state is unavailable"); _G.speedWalkPath=nil
end)

test("cleanup safety rejects partial sparse and inconsistent native speedwalk state",function()
  local oldPath,oldDir=_G.speedWalkPath,_G.speedWalkDir
  local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,100,7,"zone")
  local room=aliasCallback(f,"^dghud map delete room (\\d+)$")
  local invalid={
    {{1,100},nil},
    {nil,{"n"}},
    {{[1]=1,[3]=100},{[1]="n",[2]="n"}},
    {{1,100},{[1]="n",[3]="e"}},
    {{1,100},{"n","e","s"}},
    {{1,-100},{"n"}},
    {{"100"},{"n"}},
    {{1,100},{""}},
  }
  for _,state in ipairs(invalid) do
    _G.speedWalkPath,_G.speedWalkDir=state[1],state[2]
    local ok,err=room({"","100"}); _G.speedWalkPath,_G.speedWalkDir=nil,nil
    eq(ok,nil); eq(err,"cleanup safety state is unavailable"); eq(f.map.rooms[100]~=nil,true)
  end
  _G.speedWalkPath,_G.speedWalkDir={100},{"n"}
  local ok,err=room({"","100"}); _G.speedWalkPath,_G.speedWalkDir=nil,nil
  eq(ok,nil); eq(err,"map walking is active")
  _G.speedWalkPath,_G.speedWalkDir=oldPath,oldDir
end)

test("cleanup safety accepts Mudlet idle empty speedwalk globals",function()
  local oldPath,oldDir=_G.speedWalkPath,_G.speedWalkDir
  local states={{{},nil},{nil,{}},{{},{}},{nil,nil}}
  for _,state in ipairs(states) do
    _G.speedWalkPath,_G.speedWalkDir=state[1],state[2]
    local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,100,7,"zone")
    assert(aliasCallback(f,"^dghud map delete room (\\d+)$")({"","100"})); assert(hud.cleanup:pending())
    hud:shutdown()
  end
  _G.speedWalkPath,_G.speedWalkDir=oldPath,oldDir
end)

test("cleanup safety rejects inconsistent walker route destination and index state",function()
  local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,100,7,"zone")
  local room=aliasCallback(f,"^dghud map delete room (\\d+)$")
  local invalid={
    {route={rooms={[1]=1,[3]=100},commands={"n"}},index=1,destination=100},
    {route={rooms={1,100},commands={}},index=1,destination=100},
    {route={rooms={1,100},commands={"n"}},index=2,destination=100},
    {route={rooms={1,100},commands={"n"}},index=1,destination=999},
  }
  for _,state in ipairs(invalid) do
    hud.walker.route=state.route; hud.walker.index=state.index; hud.walker.destination=state.destination
    local ok,err=room({"","100"}); hud.walker.route=nil; hud.walker.index=nil; hud.walker.destination=nil
    eq(ok,nil); eq(err,"cleanup safety state is unavailable"); eq(f.map.rooms[100]~=nil,true)
  end
  hud.walker.route=nil; hud.walker.index=nil; hud.walker.destination=nil
end)

test("cleanup safety blocks pending automapper and special transitions",function()
  local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,100,7,"zone")
  local room=aliasCallback(f,"^dghud map delete room (\\d+)$")
  hud.automapper.pending={from=1,direction="n"}; local ok,err=room({"","100"}); eq(ok,nil); eq(err,"automapper movement is pending"); hud.automapper.pending=nil
  hud.special_transition.candidate={from=1,command="go gate"}; ok,err=room({"","100"}); eq(ok,nil); eq(err,"special transition is pending"); hud.special_transition.candidate=nil
end)

test("cleanup lifecycle stops movement clears caches refreshes and remaps surviving current room",function()
  local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,100,7,"zone"); hud.managed_rooms[100]=true
  local remaps=0; local original=hud.automapper.onRoom; hud.automapper.onRoom=function(self,info) remaps=remaps+1; return original(self,info) end
  assert(aliasCallback(f,"^dghud map delete room (\\d+)$")({"","100"})); assert(aliasCallback(f,"^dghud map confirm (\\S+)$")({"","ABC123"}))
  eq(hud.managed_rooms[100],nil); eq(f.map.invalidated.ids[1],100); eq(f.mapRefreshes,1); eq(remaps,1)
end)

test("cleanup preparation requires explicit automapper cancellation success",function()
  for _,returned in ipairs({false,"nil"}) do
    local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,100,7,"zone")
    assert(aliasCallback(f,"^dghud map delete room (\\d+)$")({"","100"}))
    hud.automapper.onWrongDirection=function() if returned=="nil" then return nil,"automapper cancel failed" end; return false,"automapper cancel failed" end
    local result,err=aliasCallback(f,"^dghud map confirm (\\S+)$")({"","ABC123"})
    eq(result,nil); eq(err,"automapper cancel failed"); eq(f.map.rooms[100]~=nil,true)
  end
end)

test("cleanup preparation requires explicit special transition cancellation success",function()
  for _,returned in ipairs({false,"nil"}) do
    local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,100,7,"zone")
    assert(aliasCallback(f,"^dghud map delete room (\\d+)$")({"","100"}))
    hud.special_transition.cancel=function() if returned=="nil" then return nil,"special cancel failed" end; return false,"special cancel failed" end
    local result,err=aliasCallback(f,"^dghud map confirm (\\S+)$")({"","ABC123"})
    eq(result,nil); eq(err,"special cancel failed"); eq(f.map.rooms[100]~=nil,true)
  end
end)

test("cleanup reconciliation reports GMCP read exceptions after mutation",function()
  local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,100,7,"zone")
  assert(aliasCallback(f,"^dghud map delete room (\\d+)$")({"","100"}))
  local reads=0; function f:getGMCP() reads=reads+1; if reads==1 then return gmcpRoom(1) end; error("GMCP read failed") end
  local result=assert(aliasCallback(f,"^dghud map confirm (\\S+)$")({"","ABC123"}))
  eq(f.map.rooms[100],nil); eq(result.lifecycle_error,"cleanup current room state is unavailable"); eq(result.error,result.lifecycle_error)
end)

test("cleanup reconciliation requires a valid fresh current room after mutation",function()
  local invalid={false,{},{Room={Info={}}},{Room={Info={num=0}}},{Room={Info={num="bad"}}}}
  for _,gmcpValue in ipairs(invalid) do
    local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,100,7,"zone")
    assert(aliasCallback(f,"^dghud map delete room (\\d+)$")({"","100"})); local reads=0
    function f:getGMCP() reads=reads+1; if reads==1 then return gmcpRoom(1) end; return gmcpValue==false and nil or gmcpValue end
    local result=assert(aliasCallback(f,"^dghud map confirm (\\S+)$")({"","ABC123"}))
    eq(f.map.rooms[100],nil); eq(result.lifecycle_error,"cleanup current room state is unavailable"); eq(result.error,result.lifecycle_error)
  end
end)

test("cleanup shutdown removes all seven owned map aliases",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); assert(hud:start()); local before=f:count(f.aliases); eq(before,#Events.aliases+11)
  local owned={}; for id,alias in pairs(f.aliases) do if alias.pattern:match("%^dghud map ") then owned[id]=true end end; eq(f:count(owned),7)
  assert(hud:shutdown()); for id in pairs(owned) do eq(f.killed[id],true) end; eq(f:count(f.aliases),0)
end)

test("Mudlet cleanup adapter contains refresh exceptions and creates opaque tokens from secure bytes",function()
  local adapter=MudletAdapter.new(); local updates=0
  eq(adapter:cleanupClock(),os.time())
  local closed=0; local source={open=function(path,mode) eq(path,"/dev/urandom"); eq(mode,"rb"); return {read=function(_,count) eq(count,16); return "0123456789abcdef" end,close=function() closed=closed+1 end} end}
  local token=assert(adapter:cleanupToken(source)); eq(token,"9f9f5111f7b27a78"); eq(token:match("^[A-Za-z0-9]+$")~=nil,true); eq(closed,1)
  eq(adapter:refreshMap({updateMap=function() updates=updates+1 end}),true); eq(updates,1)
  local ok,err=adapter:refreshMap({updateMap=function() error("native refresh failed") end}); eq(ok,nil); eq(type(err),"string")
end)

test("Mudlet cleanup token generation fails closed without complete secure entropy",function()
  local adapter=MudletAdapter.new()
  local token,err=adapter:cleanupToken({open=function() return nil,"unsupported" end}); eq(token,nil); eq(err,"secure random source is unavailable")
  local closed=0; token,err=adapter:cleanupToken({open=function() return {read=function() return "short" end,close=function() closed=closed+1 end} end})
  eq(token,nil); eq(err,"secure random source returned incomplete data"); eq(closed,1)
  token,err=adapter:cleanupToken({open=function() return {read=function() error("read failed") end,close=function() error("close failed") end} end})
  eq(token,nil); eq(err,"secure random source read failed")
end)

test("cleanup preview fails closed when secure token entropy is unavailable",function()
  local f=fake(); f.gmcp=gmcpRoom(1); function f:cleanupToken() return nil,"secure random source is unavailable" end
  local hud=Main.new(f,{layout={}}); assert(hud:start()); addCleanupRoom(f,100,7,"zone")
  local preview,err=aliasCallback(f,"^dghud map delete room (\\d+)$")({"","100"})
  eq(preview,nil); eq(err,"secure random source is unavailable"); eq(hud.cleanup:pending(),nil); eq(f.map.rooms[100]~=nil,true); eq(f.cleanupReports[#f.cleanupReports].error,true)
end)

test("successful room ingestion centers the embedded mapper",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=175,name="Training grounds.",area=1,exits={"west"}}}}
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  eq(f.mapCenterCalls,1); eq(f.map.centered,175)
end)
test("Mudlet adapter centers and refreshes the native map after selecting an owned room",function()
  local calls={}
  local api={
    getRoomUserData=function(id,key) if id==175 and key=="dghud.owner" then return "DragonsGateHUD" end end,
    centerview=function(id) calls[#calls+1]={"center",id}; return true end,
    updateMap=function() calls[#calls+1]={"update"}; return true end,
  }
  local adapter=MudletAdapter.new(); local map=adapter:createMapAdapter(api)
  eq(map:setCurrent(175),true); eq(calls[1][1],"center"); eq(calls[1][2],175); eq(calls[2][1],"update")
end)
test("startup is idempotent and shutdown owns exact runtime IDs",function()
  local f=fake(); local hud=Main.new(f,{layout={left_width=190,right_width=270}}); eq(hud:start(),true); local first=f.next; eq(hud:start(),true); eq(f.next,first); eq(hud:shutdown(),true); eq(f.deleted,1); eq(f.set_borders[1],0); eq(f.set_borders[2],0); eq(f:count(f.events),0); eq(f:count(f.aliases),0); eq(f:count(f.triggers),0); eq(f:count(f.timers),0)
end)
test("health check requires root handlers and an owned chat trigger",function()
  local hud=Main.new(fake(),{layout={left_width=190,right_width=270}}); eq(hud:healthCheck(),nil); hud:start(); eq(hud:healthCheck(),true); hud.chat.trigger=nil; eq(hud:healthCheck(),nil)
end)
test("window resize recomputes absolute borders and view layout",function()
  local f=fake(); f.borders={1290,234,1610,120}; local hud=Main.new(f,{layout={}}); hud:start(); eq(f.layouts[#f.layouts].mode,"wide"); eq(f.set_borders[1],336); eq(f.set_borders[2],314); eq(f.set_borders[3],336); eq(f.set_borders[4],f.layouts[#f.layouts].vitals_strip_height); f.width=760; f.height=700; f.callbacks["sysWindowResizeEvent"](); eq(f.layouts[#f.layouts].mode,"compact"); eq(f.set_borders[1],0); eq(f.set_borders[2],276); eq(f.set_borders[3],0); eq(f.set_borders[4],f.layouts[#f.layouts].vitals_strip_height)
end)
test("runtime wires one mapper toolbar callback across resize and reports zoom outcomes",function()
  local f=fake(); f.gmcp=gmcpRoom(175); f.zoomResult=17.5
  local hud=Main.new(f,{layout={},mapper={zoom_step=2.5,zoom_min=3,zoom_max=60}}); assert(hud:start())
  eq(type(f.mapZoomCallback),"function"); eq(f.mapZoomCallbackSets,1)
  eq(f.mapZoomCallback("larger"),17.5)
  local call=f.mapZoomCalls[1]; eq(call[1],175); eq(call[2],"larger"); eq(call[3],2.5); eq(call[4],3); eq(call[5],60)
  eq(f.mapperStatuses[#f.mapperStatuses][1],"zoom"); eq(hud.last_mapper_status,"Map zoom 17.5")
  f.mapZoomCallback("center"); eq(f.map.centered,175); eq(f.mapperStatuses[#f.mapperStatuses][1],"centered")
  f.callbacks["sysWindowResizeEvent"](); f.callbacks["sysWindowResizeEvent"](); eq(f.mapZoomCallbackSets,1)
  f.zoomError="native zoom failed"; local value,e=f.mapZoomCallback("smaller")
  eq(value,nil); eq(e,"native zoom failed"); eq(hud.last_mapper_error,"native zoom failed"); eq(f.mapperStatuses[#f.mapperStatuses][1],"error")
end)
test("chat controller renders through the view and tab callbacks select filters",function()
  local f=fake(); local hud=Main.new(f,{layout={},chat={visible_limit=1000,dedupe_seconds=3}}); hud:start()
  eq(f.renderedChat.filter,"ALL"); eq(type(f.chatFilterCallback),"function")
  assert(hud.chat:capture("QUEST","The quest begins.")); f.chatFilterCallback("QUEST")
  eq(hud.chat.filter,"QUEST"); eq(f.renderedChat.filter,"QUEST"); eq(f.renderedChat.entries[1].message,"The quest begins.")
end)
test("resize preserves chat controller history and trigger ownership",function()
  local f=fake(); local hud=Main.new(f,{layout={},chat={height_percent=.25}}); hud:start(); assert(hud.chat:capture("QUEST","kept"))
  local controller=hud.chat; local trigger=controller.trigger; local runtime=f:count(f.triggers)
  f.width,f.height=1000,650; f.callbacks["sysWindowResizeEvent"]()
  eq(hud.chat,controller); eq(hud.chat.trigger,trigger); eq(f:count(f.triggers),runtime); eq(hud.chat:entries()[1].message,"kept")
  eq(f.layouts[#f.layouts].chat_height>160,true); eq(f.set_borders[2],f.layouts[#f.layouts].console_top)
end)
test("controller merges collector snapshots and removes owned trigger runtime",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); hud.collector.snapshot.info={attributes={STR="Good"}}; hud:refresh(); eq(hud.last_state.attributes.STR,"Good"); eq(f:count(f.triggers),5); hud:shutdown(); eq(f:count(f.triggers),0); eq(f:count(f.timers),0)
end)
test("GMCP identity arrival hydrates persisted character history without appending it",function()
  local f=fake()
  f.chatEntriesByKey={
    unknown={},
    dace_alterac={{schema=1,timestamp="2026-08-31T12:00:00-04:00",character="Dace Alterac",category="ESP",message="persisted after login",line="persisted after login",source="builtin"}},
  }
  local hud=Main.new(f,{layout={},chat={visible_limit=1000,dedupe_seconds=3}}); assert(hud:start())
  eq(table.concat(f.loadedCharacterKeys,","),"unknown"); eq(#hud.chat:entries(),0)
  f.gmcp={Char={Status={name="Dace",surname="Alterac"},Vitals={hp=1,hp_max=1}}}; hud:refresh()
  eq(table.concat(f.loadedCharacterKeys,","),"unknown,dace_alterac")
  eq(#hud.chat:entries(),1); eq(hud.chat:entries()[1].message,"persisted after login"); eq(f.chatStorageAppends or 0,0)
end)
test("welcome identity switches chat history before delayed GMCP status changes",function()
  local f=fake(); f.chatEntriesByKey={unknown={{category="ROOM",message="old"}},dace={{category="ESP",message="new"}}}
  local hud=Main.new(f,{layout={},chat={visible_limit=1000,dedupe_seconds=3}}); assert(hud:start()); eq(hud.chat:entries()[1].message,"old")
  hud.collector:onLine("Welcome to Dragon's Gate, Dace!")
  eq(hud:characterName(),"Dace"); eq(hud.chat:entries()[1].message,"new"); eq(table.concat(f.loadedCharacterKeys,","),"unknown,dace")
end)
test("controller status and storage use the effective bounded visible limit",function()
  local oversized=fake(); oversized.chatEntries={}
  for index=1,1001 do oversized.chatEntries[index]={category="ROOM",message="line-"..index} end
  local hud=Main.new(oversized,{layout={},chat={visible_limit=1500,dedupe_seconds=3}}); assert(hud:start())
  local status=hud:chatStatus(); eq(oversized.chatVisibleLimit,1000); eq(status.visible_count,1000)
  eq(hud.chat:entries()[1].message,"line-2"); eq(hud.chat:entries()[1000].message,"line-1001")

  local lower=fake(); lower.chatEntries={{category="ROOM",message="one"},{category="ROOM",message="two"},{category="ROOM",message="three"}}
  local lowerHud=Main.new(lower,{layout={},chat={visible_limit=2,dedupe_seconds=3}}); assert(lowerHud:start())
  eq(lower.chatVisibleLimit,2); eq(lowerHud:chatStatus().visible_count,2); eq(lowerHud.chat:entries()[1].message,"two")
end)
test("startup checks for updates before refreshing command data at an in-game prompt",function()
  local f=fake(); f.character_active=true; local order={}
  local hud=Main.new(f,{layout={}})
  hud.updater={checkAtCharacterEntry=function(_,done) order[#order+1]="check"; eq(#(f.sentCommands or {}),0); done(false); return true end}
  assert(hud:start()); order[#order+1]=f.sent
  eq(table.concat(order,","),"check,inventory")
end)
test("replacement package skips a redundant update check and refreshes immediately",function()
  local f=fake(); f.character_active=true; f.update_reinstall=true; local checks=0
  local hud=Main.new(f,{layout={}})
  hud.updater={checkAtCharacterEntry=function() checks=checks+1; return true end}
  assert(hud:start())
  eq(checks,0); eq(f.sent,"inventory"); eq(f.update_reinstall,false)
end)
test("welcome character entry checks only once and never refreshes before completion",function()
  local f=fake(); local pending; local checks=0
  local hud=Main.new(f,{layout={}})
  hud.updater={checkAtCharacterEntry=function(_,done) checks=checks+1; pending=done; return true end}
  hud:start()
  for _,fn in pairs(f.triggers) do fn("Welcome to Dragon's Gate, Test!") end
  for _,fn in pairs(f.triggers) do fn("Welcome to Dragon's Gate, Test!") end
  eq(checks,1); eq(#(f.sentCommands or {}),0); pending(false); eq(f.sent,"inventory")
end)
test("a different character welcome performs another update check without disconnect",function()
  local f=fake(); local completions={}; local checks=0
  local hud=Main.new(f,{layout={}})
  hud.updater={checkAtCharacterEntry=function(_,done) checks=checks+1; completions[#completions+1]=done; return true end}
  hud:start(); hud.collector:onLine("Welcome to Dragon's Gate, Muthulas!"); completions[1](false)
  hud.collector:cancelActive(); hud.collector.refreshed=true
  hud.collector:onLine("Welcome to Dragon's Gate, Dace!")
  eq(checks,2); eq(#completions,2)
end)
test("reload leaves one command collector",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); hud:reload(); eq(f:count(f.triggers),5); local outgoing=0; for _,name in pairs(f.events) do if name=="sysDataSendRequest" then outgoing=outgoing+1 end end; eq(outgoing,2)
end)

test("runtime wires one automapper handler per event and cleans it exactly",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=100,name="A",area=1,exits={"north"}}}}
  local personal=f:addEvent("gmcp.Room.Info",function() end); local hud=Main.new(f,{layout={}}); assert(hud:start())
  eq(f.createdMaps,1); eq(hud.automapper:currentRoom(),100)
  local function count(name) local n=0; for _,value in pairs(f.events) do if value==name then n=n+1 end end; return n end
  eq(count("gmcp.Room.Info"),2); eq(count("gmcp.Room.WrongDir"),1); eq(count("sysDisconnectionEvent"),2); eq(count("sysDataSendRequest"),2)
  hud:reload(); eq(f.createdMaps,2); eq(count("gmcp.Room.Info"),2); eq(count("gmcp.Room.WrongDir"),1); eq(count("sysDataSendRequest"),2)
  hud:shutdown(); eq(f.events[personal],"gmcp.Room.Info"); eq(count("gmcp.Room.Info"),1); eq(count("gmcp.Room.WrongDir"),0); eq(count("sysDataSendRequest"),0)
end)

test("runtime routes movement, wrong direction, teleport commands, and disconnect",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=100,name="A",area=1,exits={"north"}}}}
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"north"); eq(hud.automapper.pending.direction,"n")
  f.callbacks["gmcp.Room.WrongDir"](); eq(hud.automapper.pending,nil)
  f.callbacks["sysDataSendRequest"](nil,"north"); f.callbacks["sysDataSendRequest"](nil,"go portal"); eq(hud.automapper.pending,nil)
  f.callbacks["sysDataSendRequest"](nil,"north"); f.callbacks["sysDisconnectionEvent"](); eq(hud.automapper.pending,nil)
end)
test("runtime confirms the final non-direction command from the next canonical room",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={},mapper={special_timeout=7}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"pull lever"); f.callbacks["sysDataSendRequest"](nil,"go gate")
  local ownedTimer=hud.special_transition.timer; eq(f.timer_delays[ownedTimer],7)
  f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(f.map.special[1].from,100); eq(f.map.special[1].to,900); eq(f.map.special[1].command,"go gate")
  eq(hud.special_transition:pending(),nil); eq(f.timer_cancels[ownedTimer],1); eq(f:count(f.timers),0)
end)
test("expired arbitrary special command cannot reuse an earlier direction",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"north")
  f.callbacks["sysDataSendRequest"](nil,"climb rope")
  local timer=hud.special_transition.timer; local expire=assert(f.timers[timer]); f.timers[timer]=nil; expire()
  eq(hud.special_transition:pending(),nil)
  f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(#f.map.links,0); eq(#f.map.special,0)
end)
test("unscheduled arbitrary special command cannot reuse an earlier direction",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"north")
  f.failSchedule="return"; f.callbacks["sysDataSendRequest"](nil,"climb rope"); f.failSchedule=nil
  eq(hud.special_transition:pending(),nil)
  f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(#f.map.links,0); eq(#f.map.special,0)
end)
test("excluded control command cannot reuse an earlier direction",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"north")
  f.callbacks["sysDataSendRequest"](nil,"look")
  eq(hud.special_transition:pending(),nil)
  f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(#f.map.links,0); eq(#f.map.special,0)
end)
test("successful arbitrary special command owns the transition exactly",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"north")
  f.callbacks["sysDataSendRequest"](nil,"  Climb RuneRope  ")
  f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(#f.map.links,0); eq(#f.map.special,1)
  eq(f.map.special[1].from,100); eq(f.map.special[1].to,900); eq(f.map.special[1].command,"climb runerope")
end)
test("runtime wires configured game-specific traversal patterns",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={},mapper={special_patterns={"^squeeze%s+through "}}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"Squeeze through crack")
  f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(#f.map.special,1); eq(f.map.special[1].command,"squeeze through crack")
end)
test("runtime reports tracker scheduler failures without retaining candidates",function()
  for _,mode in ipairs({"return","throw"}) do
    local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start()); f.failSchedule=mode
    local callbackOk=pcall(f.callbacks["sysDataSendRequest"],nil,"climb rope")
    eq(callbackOk,true); eq(hud.special_transition:pending(),nil); eq(f:count(f.timers),0)
    eq(tostring(hud.last_mapper_error):find("special schedule",1,true)~=nil,true)
    f.failSchedule=nil; hud:shutdown()
  end
end)
test("runtime reports bounded replacement cancellation failures and does not schedule a replacement",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); local scheduled=f.next
  f.failCancel=true
  local callbackOk=pcall(f.callbacks["sysDataSendRequest"],nil,"Open New Door")
  eq(callbackOk,true); eq(hud.special_transition:pending(),nil); eq(f.next,scheduled)
  eq(tostring(hud.last_mapper_error):find("special transition replacement cancellation failed",1,true),1)
  eq(#tostring(hud.last_mapper_error)<=200,true)
  f.failCancel=nil; hud:shutdown()
end)
test("runtime contains cancellation exceptions and preserves personal timers",function()
  local f=fake(); local personalTimer=f:schedule(60,function() end); f.gmcp=gmcpRoom(100)
  local hud=Main.new(f,{layout={}}); assert(hud:start()); f.callbacks["sysDataSendRequest"](nil,"enter tunnel")
  local ownedTimer=hud.special_transition.timer; f.failCancel=true
  local callbackOk=pcall(f.callbacks["sysDisconnectionEvent"])
  eq(callbackOk,true); eq(hud.special_transition:pending(),nil); eq(f.timer_cancels[ownedTimer],1)
  eq(tostring(hud.last_mapper_error):find("special cancellation exploded",1,true)~=nil,true)
  eq(f.timers[personalTimer]~=nil,true); f.failCancel=nil; hud:shutdown(); eq(f.timers[personalTimer]~=nil,true)
end)
test("runtime contains mapper failure after confirmation and clears transition state",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"go gate"); f.failSpecialMap="throw"; f.gmcp=gmcpRoom(900)
  local callbackOk=pcall(f.callbacks["gmcp.Room.Info"])
  eq(callbackOk,true); eq(hud.special_transition:pending(),nil); eq(hud.automapper.pending,nil); eq(f:count(f.timers),0)
  eq(#f.map.special,0); eq(tostring(hud.last_mapper_error):find("special mapping exploded",1,true)~=nil,true)
  hud:shutdown()
end)
test("runtime continues from an ensured special destination after edge persistence fails",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"go gate"); f.failSpecialMap="return"; f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(#f.map.special,0); eq(hud.automapper:currentRoom(),900); eq(f.map.current,900)
  eq(f.map.rooms[900].partition,"special:900")

  f.failSpecialMap=nil; f.callbacks["sysDataSendRequest"](nil,"north"); f.gmcp=gmcpRoom(901); f.callbacks["gmcp.Room.Info"]()
  eq(#f.map.links,1); eq(f.map.links[1].from,900); eq(f.map.links[1].to,901); eq(f.map.links[1].direction,"n")
  eq(f.map.rooms[901].partition,"special:900")
  hud:shutdown()
end)
test("repeated reload cancels each candidate once and retains unrelated runtime",function()
  local f=fake(); local personalAlias=f:addAlias("personal",function() end); local personalEvent=f:addEvent("personal",function() end); local personalTimer=f:schedule(60,function() end); f.gmcp=gmcpRoom(100)
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  for _=1,3 do
    f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); local tracker=hud.special_transition; local ownedTimer=tracker.timer
    assert(hud:reload()); eq(tracker:pending(),nil); eq(f.timer_cancels[ownedTimer],1); eq(hud.special_transition==tracker,false)
  end
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); local tracker=hud.special_transition; local ownedTimer=tracker.timer
  hud:shutdown(); eq(tracker:pending(),nil); eq(f.timer_cancels[ownedTimer],1)
  eq(f.aliases[personalAlias]~=nil,true); eq(f.events[personalEvent]~=nil,true); eq(f.timers[personalTimer]~=nil,true)
end)
test("runtime confirms a generated special transition",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  assert(hud.walker.adapter:sendCommand("go arch")); f.callbacks["sysDataSendRequest"](nil,"go arch")
  f.gmcp=gmcpRoom(901); f.callbacks["gmcp.Room.Info"]()
  eq(f.map.special[1].from,100); eq(f.map.special[1].to,901); eq(f.map.special[1].command,"go arch")
end)
test("runtime cancels candidates on movement and mapper lifecycle boundaries",function()
  local f=fake(); local personalTimer=f:schedule(60,function() end); f.gmcp=gmcpRoom(100)
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); eq(hud.special_transition:pending().command,"enter tunnel")
  f.callbacks["sysDataSendRequest"](nil,"north"); eq(hud.special_transition:pending(),nil)
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); f.callbacks["gmcp.Room.WrongDir"](); eq(hud.special_transition:pending(),nil)
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); f.callbacks["sysDisconnectionEvent"](); eq(hud.special_transition:pending(),nil)
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); hud.settings.mapper={enabled=false}; f.callbacks["sysDataSendRequest"](nil,"look"); eq(hud.special_transition:pending(),nil)
  local first=hud.special_transition; hud.settings.mapper={}; assert(hud:reload()); eq(first:pending(),nil); eq(hud.special_transition==first,false)
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); local second=hud.special_transition; hud:shutdown(); eq(second:pending(),nil)
  eq(f.timers[personalTimer]~=nil,true); eq(f:count(f.timers),1)
end)
test("roundtime counts down once per second and becomes ready",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); hud:onRoundtime(2); eq(hud.last_state.vitals.roundtime,2)
  f:fireTimer(); eq(hud.last_state.vitals.roundtime,1); f:fireTimer(); eq(hud.last_state.vitals.roundtime,0); eq(f:count(f.timers),0)
end)
test("refresh preserves the posture tracker's confirmed state",function()
  local f=fake(); function f:getPostureVariables() return {standing=true,sitting=false} end
  local hud=Main.new(f,{layout={}}); assert(hud:start()); eq(hud.last_state.vitals.standing,true); eq(hud.last_state.vitals.sitting,false)
  function f:getPostureVariables() return {standing=false,sitting=true} end
  hud:refresh(); eq(hud.last_state.vitals.standing,true); eq(hud.last_state.vitals.sitting,false)
  hud.posture:onLine("You sit down."); eq(hud.last_state.vitals.standing,false); eq(hud.last_state.vitals.sitting,true)
  hud:refresh(); eq(hud.last_state.vitals.standing,false); eq(hud.last_state.vitals.sitting,true); hud:shutdown()
end)
test("GMCP vitals starts and resynchronizes the visible roundtime countdown",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1,roundtime=3}}}; local hud=Main.new(f,{layout={}}); assert(hud:start()); eq(hud.last_state.vitals.roundtime,3); f:fireTimer(); eq(hud.last_state.vitals.roundtime,2)
  f.gmcp.Char.Vitals.roundtime=5; f.callbacks["gmcp.Char.Vitals"](); eq(hud.last_state.vitals.roundtime,5); f:fireTimer(); eq(hud.last_state.vitals.roundtime,4)
end)
test("GMCP roundtime pauses controlled walking until a ready vitals update",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1,roundtime=0}},Room={Info={num=175,name="A",area=1,exits={"north"}}}}
  f.route={rooms={175,176,180},commands={"north","east"}}
  local hud=Main.new(f,{layout={},mapper={walk_timeout=12}}); assert(hud:start())
  assert(aliasCallback(f,"^walkto\\s+(\\d+)$")("180")); eq(#f.sentCommands,1)
  f.gmcp.Char.Vitals.roundtime=4; f.gmcp.Room.Info={num=176,name="B",area=1,exits={"east"}}; f.callbacks["gmcp.Room.Info"]()
  eq(#f.sentCommands,1); eq(hud.walker.waiting_roundtime,true)
  f.gmcp.Char.Vitals.roundtime=2; f.callbacks["gmcp.Char.Vitals"](); eq(#f.sentCommands,1)
  f.gmcp.Char.Vitals.roundtime=0; f.callbacks["gmcp.Char.Vitals"](); eq(#f.sentCommands,2); eq(f.sentCommands[2],"e")
  hud:shutdown()
end)
test("repeated resize changes typography without growing runtime",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); local runtime=f:count(f.events)+f:count(f.triggers)+f:count(f.aliases)
  for _,size in ipairs({{2056,1177},{1200,800},{760,700},{3840,2160},{1200,800}}) do
    f.width,f.height=size[1],size[2]; f.callbacks["sysWindowResizeEvent"](); local r=f.layouts[#f.layouts]
    eq(r.inventory_row_height>=r.inventory_font+8,true); eq(r.details_line_height>=r.body_font+4,true); eq(r.console_width>=math.floor(size[1]*.65),true); eq(f:count(f.events)+f:count(f.triggers)+f:count(f.aliases),runtime)
  end
end)
test("optional output colors toggle through one owned alias and public API",function()
  local f=fake(); local personal=f:addLineTrigger(function() end); local hud=Main.new(f,{layout={}}); assert(hud:start())
  DGHUD={controller=hud}; Main.installChatApi(DGHUD)
  local colors=assert(aliasCallback(f,"^dghud colors(?: (.*))?$")); eq(DGHUD.colors.status().enabled,true); eq(colors({"","off"}),false); eq(f.reportedColorizer.enabled,false)
  eq(colors({"","on"}),true); eq(colors({"","exits off"}),false); eq(DGHUD.colors.status().exits,false); eq(colors({"","exits on"}),true)
  eq(colors({"","races off"}),false); eq(DGHUD.colors.status().races,false); eq(colors({"","classes off"}),false); eq(DGHUD.colors.status().classes,false); eq(colors({"","races on"}),true); eq(colors({"","classes on"}),true)
  eq(colors({"","highlights off"}),false); eq(DGHUD.colors.status().highlights,false); eq(DGHUD.user_settings.colorization.highlights_enabled,false); eq(DGHUD.colors.setFeature("highlights",true),true); eq(colors({"","highlights on"}),true)
  local trigger=assert(f.triggers[f.colorizerTrigger]); trigger("Obvious paths: north east west."); eq(#f.coloredSegments,4)
  eq(DGHUD.colors.toggle(),false); eq(DGHUD.user_settings.colorization.enabled,false); eq(DGHUD.colors.setEnabled(true),true); eq(DGHUD.colors.status().started,true); eq(hud.colorizer_enabled,true); eq(f.viewColorEnabled,true)
  eq(f.colorToggleCallback(),false); eq(DGHUD.user_settings.colorization.enabled,false); eq(f.colorToggleCallback(),true)
  local owned=f.colorizerTrigger; hud:reload(); eq(f.triggers[owned],nil); eq(hud.colorizer:status().enabled,true); eq(f.triggers[personal]~=nil,true)
  hud:shutdown(); eq(f:count(f.triggers),1); DGHUD=nil
end)
test("legacy disabled game highlights persist into every individual option across reload",function()
  local f=fake(); local hud=Main.new(f,{layout={},colorization={highlights_enabled=false}}); assert(hud:start())
  eq(hud.colorizer:status().highlights,false); eq(f.viewColorOptions.damage,false); eq(f.viewColorOptions.portal,false)
  hud:reload(); eq(hud.colorizer:status().highlights,false); eq(f.viewColorOptions.damage,false); eq(f.viewColorOptions.portal,false); hud:shutdown()
end)
test("help alias opens the owned responsive guide",function()
  local f=fake(); local shown=0; local view=f:createView(); function view:showHelp() shown=shown+1; return true end; function f:createView() return view end
  local hud=Main.new(f,{layout={}}); assert(hud:start()); assert(aliasCallback(f,"^dghud help$")()); eq(shown,1); hud:shutdown()
end)
test("autoroller options commands and atomic settings use the active roller",function()
  local f=fake(); local hud=Main.new(f,{layout={},roller={target_total=53,hard_stop=62,reroll_delay=.1,reroll_command="n",use_min_stats=true,min_stats={STR=5}}}); assert(hud:start())
  local config=f.optionsActionCallback("roller_settings"); eq(config.target_total,53); assert(f.optionsActionCallback("roller_start")); eq(hud.roller.state.active,true); assert(f.optionsActionCallback("roller_stop")); eq(hud.roller.state.active,false)
  local ok,err=f.rollerSettingsCallback({target_total="60",hard_stop="62",reroll_delay="0.2",reroll_command="n",use_min_stats=true,min_stats={STR="6"}}); assert(ok,err); eq(hud.roller.cfg.target_total,60); eq(f.savedRollerSettings.target_total,60)
  hud:shutdown()
end)
test("public autoroller status returns defensive configuration copies",function()
  local f=fake(); local hud=Main.new(f,{layout={},roller={target_total=53,hard_stop=62,reroll_command="n",min_stats={STR=5}}}); assert(hud:start()); DGHUD={controller=hud}; Main.installChatApi(DGHUD)
  local status=DGHUD.roller.status(); status.config.target_total=77; status.config.min_stats.STR=1; eq(hud.roller.cfg.target_total,53); eq(hud.roller.cfg.min_stats.STR,5); hud:shutdown(); DGHUD=nil
end)
test("rune API exposes sorted trigger-safe variables and copies",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); assert(hud:start()); DGHUD={controller=hud}; Main.installChatApi(DGHUD)
  hud.collector.snapshot.runes={items={{name="Healing",remaining=14},{name="Force",remaining=100}}}; hud:refresh()
  eq(DGHUD.runes.items[1].name,"Healing"); eq(DGHUD.runes.by_name.healing.remaining,14); eq(DGHUD.runes.remaining.force,100); eq(DGHUD.runes.getRemaining("FORCE"),100)
  local copy=DGHUD.runes.get("healing"); copy.remaining=999; eq(DGHUD.runes.by_name.healing.remaining,14); local all=DGHUD.runes.all(); eq(#all,2); eq(all[2].name,"Force")
  hud:shutdown(); DGHUD=nil
end)
test("chat trigger registration failure rolls back partial HUD runtime",function()
  local f=fake(); f.failChatTrigger=true; local hud=Main.new(f,{layout={}}); local started,err=hud:start()
  eq(started,nil); eq(tostring(err):find("chat trigger registration failed",1,true)~=nil,true); eq(hud.started,false); eq(hud.chat,nil); eq(hud:healthCheck(),nil)
  eq(f.deleted,1); eq(f:count(f.triggers),0); eq(f:count(f.events),0); eq(f:count(f.aliases),0); eq(f:count(f.timers),0)
end)
test("chat runtime has one owned trigger and cached personal API survives reload safely",function()
  local f=fake(); local unrelated=f:addLineTrigger(function() end); local hud=Main.new(f,{layout={}}); hud:start()
  eq(hud.chat.started,true); eq(f:count(f.triggers),6)
  DGHUD={controller=hud}; Main.installChatApi(DGHUD); local capture=DGHUD.chat.capture
  assert(capture("QUEST","before reload")); hud:reload(); DGHUD={controller=hud}; Main.installChatApi(DGHUD)
  eq(f:count(f.triggers),6); eq(f.loadRecentCalls,2); eq(#hud.chat:entries(),1); eq(hud.chat:entries()[1].message,"before reload")
  assert(capture("QUEST","after reload")); eq(#hud.chat:entries(),2); eq(hud.chat:entries()[2].message,"after reload")
  hud:shutdown(); eq(f:count(f.triggers),1); eq(f.triggers[unrelated]~=nil,true)
  local result,err=capture("QUEST","during shutdown"); eq(result,nil); eq(err,"chatbox is not running"); DGHUD=nil
end)
test("public capture fails while storage cleanup is re-entrant",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); DGHUD={controller=hud}; Main.installChatApi(DGHUD); local capture=DGHUD.chat.capture
  f.onStorageClose=function() f.reentrantResult,f.reentrantError=capture("QUEST","during close") end
  hud:shutdown(); eq(f.reentrantResult,nil); eq(f.reentrantError,"chatbox is not running"); eq(#f.chatEntries,0); DGHUD=nil
end)

test("reload and shutdown retain unrelated aliases events and timers",function()
  local f=fake(); local personalAlias=f:addAlias(); local personalEvent=f:addEvent("personal",function() end); local personalTimer=f:schedule(1,function() end)
  local hud=Main.new(f,{layout={}}); hud:start(); hud:reload(); hud:shutdown()
  eq(f.aliases[personalAlias]~=nil,true); eq(f.events[personalEvent]~=nil,true); eq(f.timers[personalTimer]~=nil,true)
end)

test("map adapter construction exceptions and nil results roll back startup",function()
  for _,mode in ipairs({"throw","nil"}) do
    local f=fake()
    function f:createMapAdapter()
      if mode=="throw" then error("adapter exploded") end
      return nil,"adapter unavailable"
    end
    local hud=Main.new(f,{layout={}}); local ok,err=hud:start()
    eq(ok,nil); eq(tostring(err):find(mode=="throw" and "adapter exploded" or "adapter unavailable",1,true)~=nil,true)
    eq(hud.started,false); eq(hud.map,nil); eq(hud.automapper,nil); eq(f:count(f.events),0); eq(f:count(f.aliases),0); eq(f:count(f.triggers),0)
  end
end)

test("automapper construction exceptions and nil results roll back startup",function()
  for _,mode in ipairs({"throw","nil"}) do
    local f=fake(); local hud=Main.new(f,{layout={}})
    hud.createAutomapper=function()
      if mode=="throw" then error("automapper exploded") end
      return nil,"automapper unavailable"
    end
    local ok,err=hud:start()
    eq(ok,nil); eq(tostring(err):find(mode=="throw" and "automapper exploded" or "automapper unavailable",1,true)~=nil,true)
    eq(hud.started,false); eq(hud.map,nil); eq(hud.automapper,nil); eq(f:count(f.events),0); eq(f:count(f.aliases),0); eq(f:count(f.triggers),0)
  end
end)

test("every post-hook startup failure restores hook and cleans runtime",function()
  local oldHook=_G.doSpeedWalk; local personal=function() return "personal" end
  for _,boundary in ipairs({"view","layout","collector","event","alias"}) do
    _G.doSpeedWalk=personal; local f=fake(); local hud=Main.new(f,{layout={}})
    if boundary=="view" then function f:createView() error("view exploded") end end
    if boundary=="layout" then function f:setBorders() error("layout exploded") end end
    if boundary=="collector" then function f:addLineTrigger() error("collector exploded") end end
    if boundary=="event" then function f:addEvent() error("event exploded") end end
    if boundary=="alias" then function f:addAlias() error("alias exploded") end end
    local ok,err=hud:start(); eq(ok,nil); eq(tostring(err):find("exploded",1,true)~=nil,true)
    eq(_G.doSpeedWalk,personal); eq(hud.started,false); eq(hud.walker,nil); eq(hud.special_transition,nil)
    eq(f:count(f.events),0); eq(f:count(f.aliases),0); eq(f:count(f.triggers),0); eq(f:count(f.timers),0)
  end
  _G.doSpeedWalk=oldHook
end)

test("walk failures emit one stopped status and clear generated marker",function()
  for _,boundary in ipairs({"send","schedule"}) do
    local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=1,name="A",area=1,exits={"north"}}}}; f.route={rooms={1,2},commands={"north"}}
    if boundary=="send" then function f:sendCommand() error("send exploded") end
    else function f:schedule() error("schedule exploded") end end
    local hud=Main.new(f,{layout={}}); assert(hud:start()); local before=#(f.mapperStatuses or {})
    local ok=aliasCallback(f,"^walkto\\s+(\\d+)$")("2"); eq(ok,nil); eq(hud.walker:active(),false); eq(hud.generated_command,nil)
    local stopped=0; for index=before+1,#f.mapperStatuses do if f.mapperStatuses[index][1]=="stopped" then stopped=stopped+1 end end
    eq(stopped,1); eq(f.mapperStatuses[#f.mapperStatuses][1],"stopped"); hud:shutdown()
  end
end)

test("walk aliases validate current room route safely and share one walker",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=175,name="A",area=1,exits={"north"}}}}
  f.route={rooms={175,176,180},commands={"north","east"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  local walkto=assert(aliasCallback(f,"^walkto\\s+(\\d+)$")); local walkstop=assert(aliasCallback(f,"^walkstop$")); local mapcenter=assert(aliasCallback(f,"^mapcenter$"))
  assert(walkto("180")); eq(f.sentCommands[#f.sentCommands],"n"); eq(hud.walker:active(),true)
  f.callbacks["sysDataSendRequest"](nil,"n"); eq(hud.walker:active(),true)
  f.callbacks["gmcp.Room.Info"](); eq(#f.sentCommands,1)
  walkstop(); eq(hud.walker:active(),false)
  mapcenter(); eq(f.map.centered,175)
end)

test("map adapter validates exact owned route steps and preserves special command syntax",function()
  local owners={[1]="DragonsGateHUD",[2]="DragonsGateHUD",[3]="DragonsGateHUD"}
  local adapter=MapAdapter.new({
    getRoomUserData=function(id,key) if key=="dghud.owner" then return owners[id] or "" end end,
    getRoomExits=function() return {} end,
    getSpecialExits=function(from,listAll) eq(from,1); eq(listAll,true); return {[2]={['Go Gate']="0"}} end,
  })
  local ok,command=adapter:validateRouteStep(1,2,"Go Gate")
  eq(ok,true); eq(command,"Go Gate")
  ok,command=adapter:validateRouteStep(1,2,"go gate")
  eq(ok,nil); eq(command,"special exit is not confirmed from 1 to 2")
  ok,command=adapter:validateRouteStep(1,3,"Go Gate")
  eq(ok,nil); eq(command,"special exit is not confirmed from 1 to 3")
  ok,command=adapter:validateRouteStep(1,2,"leave gate")
  eq(ok,nil); eq(command,"special exit is not confirmed from 1 to 2")
  owners[2]="Personal"
  ok,command=adapter:validateRouteStep(1,2,"Go Gate")
  eq(ok,nil); eq(command,"route endpoints are not owned by DragonsGateHUD")
end)

test("walkto crosses a confirmed special exit one command at a time around roundtime",function()
  local f=fake(); f.gmcp=gmcpRoom(1); f.route={rooms={1,2,3},commands={"  Go Gate  ","north"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  hud.map.rooms[2]={}; hud.map.rooms[3]={}; hud.map.special[1]={from=1,to=2,command="Go Gate"}
  local walkto=assert(aliasCallback(f,"^walkto\\s+(\\d+)$")); assert(walkto("3"))
  eq(f.sentCommands[1],"Go Gate"); eq(f.sentCommands[2],nil); eq(hud.generated_command,"Go Gate")
  f.callbacks["sysDataSendRequest"](nil,"Go Gate"); eq(hud.generated_command,nil); eq(hud.walker:active(),true)
  f.gmcp=gmcpRoom(2); f.gmcp.Char.Vitals.roundtime=4; f.callbacks["gmcp.Room.Info"]()
  eq(#f.sentCommands,1); eq(hud.walker.waiting_roundtime,true)
  f.gmcp.Char.Vitals.roundtime=0; f.callbacks["gmcp.Char.Vitals"]()
  eq(f.sentCommands[2],"n"); eq(f.sentCommands[3],nil)
  f.callbacks["sysDataSendRequest"](nil,"n"); f.gmcp=gmcpRoom(3); f.callbacks["gmcp.Room.Info"]()
  eq(hud.walker:active(),false); eq(hud.generated_command,nil)
end)

test("native map click crosses a confirmed special exit with exact generated isolation",function()
  local oldHook,oldPath,oldDir=_G.doSpeedWalk,_G.speedWalkPath,_G.speedWalkDir
  local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start())
  hud.map.rooms[2]={}; hud.map.rooms[3]={}; hud.map.special[1]={from=1,to=2,command="go gate"}; hud.map.links[1]={from=2,to=3,direction="e"}
  _G.speedWalkPath={1,2,3}; _G.speedWalkDir={"go gate","east"}; assert(_G.doSpeedWalk())
  eq(f.sentCommands[1],"go gate"); eq(hud.generated_command,"go gate")
  f.callbacks["sysDataSendRequest"](nil,"go gate"); f.gmcp=gmcpRoom(2); f.callbacks["gmcp.Room.Info"]()
  eq(f.sentCommands[2],"e"); eq(f.sentCommands[3],nil)
  hud:shutdown(); _G.doSpeedWalk=oldHook; _G.speedWalkPath=oldPath; _G.speedWalkDir=oldDir
end)

test("special walking stops on an unexpected room and movement timeout",function()
  local f=fake(); f.gmcp=gmcpRoom(1); f.route={rooms={1,2},commands={"go gate"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start()); hud.map.rooms[2]={}; hud.map.special[1]={from=1,to=2,command="go gate"}
  local walkto=assert(aliasCallback(f,"^walkto\\s+(\\d+)$")); assert(walkto("2"))
  f.callbacks["sysDataSendRequest"](nil,"go gate"); f.gmcp=gmcpRoom(99); f.callbacks["gmcp.Room.Info"]()
  eq(hud.walker:active(),false); eq(hud.last_mapper_status,"Walk stopped: unexpected room 99")
  f.gmcp=gmcpRoom(1); hud.automapper.current_id=1; assert(walkto("2")); local timeout=hud.walker.timeout
  local callback=assert(f.timers[timeout]); f.timers[timeout]=nil; callback()
  eq(hud.walker:active(),false); eq(hud.generated_command,nil); eq(hud.last_mapper_status,"Walk stopped: movement timed out")
end)

test("manually typed non-direction command replaces a generated special walk",function()
  local f=fake(); f.gmcp=gmcpRoom(1); f.route={rooms={1,2},commands={"go gate"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start()); hud.map.rooms[2]={}; hud.map.special[1]={from=1,to=2,command="go gate"}
  assert(aliasCallback(f,"^walkto\\s+(\\d+)$")("2")); eq(hud.generated_command,"go gate")
  f.callbacks["sysDataSendRequest"](nil,"pull lever")
  eq(hud.walker:active(),false); eq(hud.generated_command,nil); eq(hud.last_mapper_status,"Walk stopped: manual movement")
  eq(hud.special_transition:pending(),nil)
end)

test("routine walking stops are statuses and do not overwrite mapper errors",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=175,name="A",area=1,exits={"north"}}}}; f.route={rooms={175,176},commands={"north"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start()); hud.last_mapper_error="earlier failure"
  assert(aliasCallback(f,"^walkto\\s+(\\d+)$")("176")); aliasCallback(f,"^walkstop$")()
  local status=hud:mapStatus(); eq(status.last_error,"earlier failure"); eq(status.last_status,"Walk stopped: requested")
  assert(aliasCallback(f,"^walkto\\s+(\\d+)$")("176")); f.callbacks["sysDataSendRequest"](nil,"east")
  status=hud:mapStatus(); eq(status.last_error,"earlier failure"); eq(status.last_status,"Walk stopped: manual movement")
  hud:shutdown(); eq(hud.last_mapper_error,"earlier failure")
end)

test("walkto rejects missing current rooms route errors and unconfirmed special exits",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); assert(hud:start())
  local walkto=assert(aliasCallback(f,"^walkto\\s+(\\d+)$")); local ok,err=walkto("20"); eq(ok,nil); eq(err,"current room is unavailable")
  hud.automapper.current_id=10; f.routeError="no route"; ok,err=walkto("20"); eq(ok,nil); eq(err,"no route")
  f.routeError=nil; f.route={rooms={10,20},commands={"go portal"}}; ok,err=walkto("20"); eq(ok,nil); eq(err,"special exit is not confirmed from 10 to 20")
end)

test("native map click uses walker route and restores the previous global hook",function()
  local previous=function() return "personal" end; local oldHook=_G.doSpeedWalk; _G.doSpeedWalk=previous
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=175,name="A",area=1,exits={"north"}}}}
  local hud=Main.new(f,{layout={}}); assert(hud:start()); local ownedHook=_G.doSpeedWalk; eq(ownedHook~=previous,true)
  hud.map.rooms[176]={}; hud.map.links[1]={from=175,to=176,direction="n"}; _G.speedWalkPath={175,176}; _G.speedWalkDir={"north"}; assert(ownedHook()); eq(f.sentCommands[#f.sentCommands],"n")
  hud:shutdown(); eq(_G.doSpeedWalk,previous); eq(f:count(f.timers),0); eq(f:count(f.aliases),0)
  _G.doSpeedWalk=oldHook; _G.speedWalkPath=nil; _G.speedWalkDir=nil
end)

test("native map click snapshots route globals before ownership checks",function()
  local oldHook,oldPath,oldDir=_G.doSpeedWalk,_G.speedWalkPath,_G.speedWalkDir
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=175,name="A",area=1,exits={"north"}}}}
  local hud=Main.new(f,{layout={}}); assert(hud:start()); hud.map.rooms[176]={}; hud.map.links[1]={from=175,to=176,direction="n"}
  local originalIsOwned=hud.map.isOwned; local changed=false
  hud.map.isOwned=function(map,id)
    if not changed then changed=true; _G.speedWalkPath={999}; _G.speedWalkDir={"south"} end
    return originalIsOwned(map,id)
  end
  _G.speedWalkPath={175,176}; _G.speedWalkDir={"north"}; assert(_G.doSpeedWalk()); eq(f.sentCommands[#f.sentCommands],"n")
  hud:shutdown(); _G.doSpeedWalk=oldHook; _G.speedWalkPath=oldPath; _G.speedWalkDir=oldDir
end)

test("disabled mapper never replaces personal speedwalk hook",function()
  local old=_G.doSpeedWalk; local personal=function() return "personal" end; _G.doSpeedWalk=personal
  local f=fake(); local hud=Main.new(f,{layout={},mapper={enabled=false}}); assert(hud:start()); eq(_G.doSpeedWalk,personal); hud:shutdown(); eq(_G.doSpeedWalk,personal); _G.doSpeedWalk=old
end)

test("map click delegates unowned and mixed routes but handles wholly owned routes",function()
  local oldHook,oldPath,oldDir=_G.doSpeedWalk,_G.speedWalkPath,_G.speedWalkDir
  local delegated=0; local personal=function() delegated=delegated+1; return "personal" end; _G.doSpeedWalk=personal
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=175,name="A",area=1,exits={"north"}}}}
  local hud=Main.new(f,{layout={},mapper={}}); assert(hud:start()); hud.map.isOwned=function(_,id) return id==175 or id==176 end
  _G.speedWalkPath={900,901}; _G.speedWalkDir={"n"}; eq(_G.doSpeedWalk(),"personal"); eq(delegated,1)
  _G.speedWalkPath={175,901}; _G.speedWalkDir={"n"}; eq(_G.doSpeedWalk(),"personal"); eq(delegated,2)
  hud.map.links[1]={from=175,to=176,direction="n"}; _G.speedWalkPath={175,176}; _G.speedWalkDir={"n"}; assert(_G.doSpeedWalk()); eq(delegated,2)
  hud:shutdown(); eq(_G.doSpeedWalk,personal); _G.doSpeedWalk=oldHook; _G.speedWalkPath=oldPath; _G.speedWalkDir=oldDir
end)

test("native map click accepts speedWalkPath without the current room",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=175,name="A",area=1,exits={"north"}}}}
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  hud.map.rooms[176]={}; hud.map.links[1]={from=175,to=176,direction="n"}; _G.speedWalkPath={176}; _G.speedWalkDir={"north"}; assert(_G.doSpeedWalk()); eq(hud.walker:active(),true); eq(f.sentCommands[#f.sentCommands],"n")
  hud:shutdown(); _G.speedWalkPath=nil; _G.speedWalkDir=nil
end)

test("Mudlet send with no return value still starts controlled walking",function()
  local f=fake(); function f:sendCommand(command) self.sentCommands=self.sentCommands or {}; self.sentCommands[#self.sentCommands+1]=command end
  f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=1,name="A",area=1,exits={"north"}}}}; f.route={rooms={1,2},commands={"north"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start()); local walkto=assert(aliasCallback(f,"^walkto\\s+(\\d+)$"))
  assert(walkto("2")); eq(hud.walker:active(),true); eq(f.sentCommands[#f.sentCommands],"n"); hud:shutdown()
end)

test("walker stops on disconnect WrongDir unexpected room manual movement and shutdown",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=1,name="A",area=1,exits={"north"}}}}; f.route={rooms={1,2},commands={"north"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start()); local walkto=assert(aliasCallback(f,"^walkto\\s+(\\d+)$"))
  walkto("2"); f.callbacks["sysDataSendRequest"](nil,"east"); eq(hud.walker:active(),false)
  walkto("2"); f.callbacks["gmcp.Room.WrongDir"](); eq(hud.walker:active(),false)
  walkto("2"); f.gmcp.Room.Info={num=99,name="Elsewhere",area=1,exits={}}; f.callbacks["gmcp.Room.Info"](); eq(hud.walker:active(),false)
  f.gmcp.Room.Info={num=1,name="A",area=1,exits={"north"}}; hud.automapper.current_id=1; walkto("2"); f.callbacks["sysDisconnectionEvent"](); eq(hud.walker:active(),false)
  walkto("2"); hud:shutdown(); eq(f:count(f.timers),0)
end)
