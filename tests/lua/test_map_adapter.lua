local Adapter=require("map_adapter")
local Automapper=require("automapper")
local Model=require("mapper_model")

local function copy(value)
  if type(value)~="table" then return value end
  local result={}; for key,item in pairs(value) do result[key]=copy(item) end; return result
end

local function fakeMapApi(seed)
  local api={rooms=seed or {},areas={},areaUser={},mapUser={},labels={},nextArea=1,fail={},path=nil,refreshed=0,deletedRooms={},deletedAreas={},special={},specialAdds=0,zoom={},custom={},customAdds=0,customWrites={}}
  local function gate(name)
    if api.fail[name]=="throw" then error(name.." exploded") end
    if api.fail[name] then return nil,name.." rejected" end
    return true
  end
  function api.roomExists(id) local ok,e=gate("roomExists"); if not ok then return nil,e end; return api.rooms[id]~=nil end
  function api.addRoom(id) local ok,e=gate("addRoom"); if not ok then return nil,e end; api.rooms[id]={area=-1,x=0,y=0,z=0,user={},exits={},stubs={}}; return true end
  function api.deleteRoom(id) local ok,e=gate("deleteRoom"); if not ok then return nil,e end; api.rooms[id]=nil; api.deletedRooms[#api.deletedRooms+1]=id; return true end
  function api.getAreaTable() local ok,e=gate("getAreaTable"); if not ok then return nil,e end; local t={}; for n,id in pairs(api.areas) do t[n]=id end; return t end
  function api.addAreaName(name) local ok,e=gate("addAreaName"); if not ok then return nil,e end; if api.areas[name] then return nil,"area already exists" end; local id=api.nextArea; api.nextArea=id+1; api.areas[name]=id; api.areaUser[id]={}; return id end
  function api.setAreaName(id,name) local ok,e=gate("setAreaName"); if not ok then return nil,e end; if api.areas[name] and api.areas[name]~=id then return nil,"area already exists" end; local old; for label,areaID in pairs(api.areas) do if areaID==id then old=label; break end end; if not old then return nil,"area does not exist" end; api.areas[old]=nil; api.areas[name]=id; return true end
  function api.deleteArea(id) local ok,e=gate("deleteArea"); if not ok then return nil,e end; for name,areaID in pairs(api.areas) do if areaID==id then api.areas[name]=nil end end; api.areaUser[id]=nil; api.deletedAreas[#api.deletedAreas+1]=id; return true end
  function api.setAreaUserData(id,k,v) local ok,e=gate("setAreaUserData"); if not ok then return nil,e end; api.areaUser[id]=api.areaUser[id] or {}; api.areaUser[id][k]=v; return true end
  function api.getAreaUserData(id,k) local ok,e=gate("getAreaUserData"); if not ok then return nil,e end; return api.areaUser[id] and api.areaUser[id][k] end
  function api.getAreaRooms1(id)
    local ok,e=gate("getAreaRooms1"); if not ok then return nil,e end
    local out,index={},0
    for roomID,room in pairs(api.rooms) do if room.area==id then out[index]=roomID; index=index+1 end end
    return out
  end
  function api.getMapLabels(id) local ok,e=gate("getMapLabels"); if not ok then return nil,e end; return api.labels[id] or {} end
  function api.setRoomArea(id,v) local ok,e=gate("setRoomArea"); if not ok then return nil,e end; api.rooms[id].area=v; return true end
  function api.getRoomArea(id) local ok,e=gate("getRoomArea"); if not ok then return nil,e end; return api.rooms[id] and api.rooms[id].area end
  function api.setRoomName(id,v) local ok,e=gate("setRoomName"); if not ok then return nil,e end; api.rooms[id].name=v; return true end
  function api.setRoomCoordinates(id,x,y,z) local ok,e=gate("setRoomCoordinates"); if not ok then return nil,e end; local r=api.rooms[id]; r.x=x;r.y=y;r.z=z; return true end
  function api.setRoomUserData(id,k,v) local ok,e=gate("setRoomUserData"); if not ok then return nil,e end; api.rooms[id].user[k]=v; return true end
  function api.getRoomUserData(id,k)
    local ok,e=gate("getRoomUserData"); if not ok then return nil,e end
    local room=api.rooms[id]
    if not room then return "" end
    local value=room.user[k]
    return value==nil and "" or value
  end
  function api.setExitStub(id,d) local ok,e=gate("setExitStub"); if not ok then return nil,e end; api.rooms[id].stubs[d]=true; return true end
  function api.setExit(id,to,d) local ok,e=gate("setExit"); if not ok then return nil,e end; if tonumber(to) and tonumber(to)<1 then api.rooms[id].exits[d]=nil else api.rooms[id].exits[d]=to end; return true end
  function api.getRoomExits(id)
    local ok,e=gate("getRoomExits"); if not ok then return nil,e end
    local out={}; for direction,to in pairs((api.rooms[id] and api.rooms[id].exits) or {}) do out[direction]=to end; return out
  end
  function api.addSpecialExit(from,to,command)
    local ok,e=gate("addSpecialExit"); if not ok then return nil,e end
    api.special[from]=api.special[from] or {}; api.special[from][command]=to; api.specialAdds=api.specialAdds+1; return true
  end
  function api.removeSpecialExit(from,command) local ok,e=gate("removeSpecialExit"); if not ok then return nil,e end; if api.special[from] then api.special[from][command]=nil end; if api.custom[from] then api.custom[from][command]=nil end; return true end
  function api.getSpecialExits(from,listAll)
    local ok,e=gate("getSpecialExits"); if not ok then return nil,e end
    eq(listAll,true)
    local grouped={}
    for command,to in pairs(api.special[from] or {}) do grouped[to]=grouped[to] or {}; grouped[to][command]="0" end
    return grouped
  end
  function api.getRoomCoordinates(id) local ok,e=gate("getRoomCoordinates"); if not ok then return nil,e end; local r=api.rooms[id]; return r and r.x,r and r.y,r and r.z end
  function api.getCustomLines(id)
    local ok,e=gate("getCustomLines"); if not ok then return nil,e end
    if not api.rooms[id] then return nil,"room does not exist" end
    return copy(api.custom[id] or {})
  end
  function api.addCustomLine(from,to,command,style,color,arrow)
    local ok,e=gate("addCustomLine"); if not ok then return nil,e end
    if not api.rooms[from] or not api.rooms[to] then return nil,"room does not exist" end
    if api.rooms[from].area~=api.rooms[to].area then return nil,"different mapper area" end
    if not (api.special[from] and api.special[from][command]) and not api.rooms[from].exits[command] then return nil,"exit does not exist" end
    api.custom[from]=api.custom[from] or {}
    api.custom[from][command]={attributes={style=style,color={r=color[1],g=color[2],b=color[3]},arrow=arrow},points={[0]={x=api.rooms[to].x,y=api.rooms[to].y}}}
    api.customAdds=api.customAdds+1; api.customWrites[#api.customWrites+1]={from=from,to=to,command=command,style=style,color=copy(color),arrow=arrow}
    return true
  end
  function api.removeCustomLine(from,command)
    local ok,e=gate("removeCustomLine"); if not ok then return nil,e end
    if not api.custom[from] or not api.custom[from][command] then return nil,"custom line does not exist" end
    api.custom[from][command]=nil; return true
  end
  function api.getRooms() local ok,e=gate("getRooms"); if not ok then return nil,e end; local out={}; for id,r in pairs(api.rooms) do out[id]=r.name or ("Room "..id) end; return out end
  function api.getAllMapUserData() local ok,e=gate("getAllMapUserData"); if not ok then return nil,e end; local out={}; for k,v in pairs(api.mapUser) do out[k]=v end; return out end
  function api.setMapUserData(k,v) local ok,e=gate("setMapUserData"); if not ok then return nil,e end; api.mapUser[k]=v; return true end
  function api.getRoomsByPosition(area,x,y,z) local ok,e=gate("getRoomsByPosition"); if not ok then return nil,e end; local out,i={},0; for id,r in pairs(api.rooms) do if r.area==area and r.x==x and r.y==y and r.z==z then out[i]=id;i=i+1 end end; return out end
  function api.getMapZoom(area) local ok,e=gate("getMapZoom"); if not ok then return nil,e end; return api.zoom[area] end
  function api.setMapZoom(value,area) local ok,e=gate("setMapZoom"); if not ok then return nil,e end; api.zoom[area]=value; return true end
  function api.centerview(id) local ok,e=gate("centerview"); if not ok then return nil,e end; api.centered=id; return true end
  function api.getPath(a,b) local ok,e=gate("getPath"); if not ok then return nil,e end; return api.path or {rooms={a,b},commands={a.."-"..b}} end
  function api.updateMap() local ok,e=gate("updateMap"); if not ok then return nil,e end; api.refreshed=api.refreshed+1; return true end
  function api.tempTimer(_,callback) local ok,e=gate("tempTimer"); if not ok then return nil,e end; callback(); return 1 end
  return api
end

test("friendly area and subarea names preserve stable room identity",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:putRoom({id=10,area="1",partition="special:10",x=0,y=0,z=0,name="Gate",environment="City",flags={},poi={},exits={},special_exits={}}))
  assert(map:setMapLabel("area","1","Spurian Academy")); assert(map:setMapLabel("subarea","special:10","Temple Gate"))
  eq(assert(map:renameNativePartition("special:10")),"Spurian Academy - Temple Gate")
  eq(api.areas["Spurian Academy - Temple Gate"],api.rooms[10].area)
  local current=assert(map:currentTransferScope(10)); eq(current.area,"1"); eq(current.partition,"special:10"); eq(current.area_name,"Spurian Academy"); eq(current.subarea_name,"Temple Gate")
  local scopes=assert(map:listTransferScopes()); eq(scopes.areas[1].label,"Spurian Academy"); eq(scopes.subareas[1].label,"Temple Gate")
  local room=assert(map:getRoom(10)); eq(room.id,10); eq(room.area,"1"); eq(room.partition,"special:10")
  local originalArea=api.rooms[10].area
  assert(map:putRoom({id=10,area="1",partition="special:10",x=0,y=0,z=0,name="Gate",environment="City",flags={},poi={},exits={},special_exits={}}))
  eq(api.rooms[10].area,originalArea)
  eq(api.nextArea,2)
end)

test("native map names add a stable suffix only when the friendly name collides",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  api.areas["Spur - Town Square"]=99
  assert(map:putRoom({id=10,area="1",partition="special:10",x=0,y=0,z=0,name="Gate",environment="City",flags={},poi={},exits={},special_exits={}}))
  assert(map:setMapLabel("area","1","Spur")); assert(map:setMapLabel("subarea","special:10","Town Square"))
  eq(assert(map:renameNativePartition("special:10")),"Spur - Town Square [10]")
  eq(api.areas["Spur - Town Square [10]"],api.rooms[10].area)
end)

local function descriptor(id,area,name)
  return {id=id,name=name or ("Room "..id),area_key=area or "A",environment="Plain",flags={"indoor"},exits={}}
end

local function gmcpRoom(id,area,name,exits)
  return {num=id,name=name or ("Room "..id),area=area or 1,environment="Plain",flags={"indoor"},exits=exits or {}}
end

test("new directional rooms follow a manually moved source without claiming its area",function()
  local api=fakeMapApi(); local map=Adapter.new(api); local mapper=Automapper.new(Model,map)
  assert(mapper:onRoom(gmcpRoom(100))); local original=api.rooms[100].area
  local personal=assert(api.addAreaName("My new area")); api.areaUser[personal].notes="personal"
  assert(api.setRoomArea(100,personal)); assert(api.setRoomCoordinates(100,4,5,1))
  eq(api.rooms[100].user["dghud.partition"],"1")
  mapper:onOutgoing("north"); assert(mapper:onRoom(gmcpRoom(101)))
  eq(api.rooms[101].area,personal); eq(api.rooms[101].x,4); eq(api.rooms[101].y,6); eq(api.rooms[101].z,1)
  eq(api.rooms[101].user["dghud.partition"],"area:"..personal)
  eq(api.rooms[100].area,personal); eq(api.rooms[100].y,5); eq(api.rooms[100].user["dghud.partition"],"1")
  eq(api.rooms[100].exits.n,101); eq(api.areas["Dragons Gate - 1"],original)
  eq(api.areaUser[personal].notes,"personal"); eq(api.areaUser[personal]["dghud.owner"],nil); eq(api.areaUser[personal]["dghud.partition"],nil)
  eq(api.nextArea,3); eq(#api.deletedRooms,0); eq(#api.deletedAreas,0)

  local reloaded=Automapper.new(Model,Adapter.new(api))
  assert(reloaded:onRoom(gmcpRoom(101))); reloaded:onOutgoing("east"); assert(reloaded:onRoom(gmcpRoom(102,2)))
  eq(api.rooms[102].area,personal); eq(api.rooms[102].x,5); eq(api.rooms[102].y,6); eq(api.nextArea,3)
end)

test("new rooms use the actual renamed owned area instead of the source cached partition",function()
  local api=fakeMapApi(); local map=Adapter.new(api); local mapper=Automapper.new(Model,map)
  assert(mapper:onRoom(gmcpRoom(100))); local actual=assert(map:ensureArea("special:500"))
  assert(api.setAreaName(actual,"My renamed submap")); assert(api.setRoomArea(100,actual))
  eq(map:effectivePartition(100),"special:500")
  mapper:onOutgoing("east"); assert(mapper:onRoom(gmcpRoom(101)))
  eq(api.rooms[101].area,actual); eq(api.rooms[101].user["dghud.partition"],"special:500"); eq(api.nextArea,3)
end)

test("queued expansion rechecks the actual area of each source after manual moves",function()
  local api=fakeMapApi(); local mapper=Automapper.new(Model,Adapter.new(api))
  assert(mapper:onRoom(gmcpRoom(100))); mapper:onOutgoing("north"); mapper:onOutgoing("east")
  local first=assert(api.addAreaName("First manual area")); assert(api.setRoomArea(100,first))
  assert(mapper:onRoom(gmcpRoom(101))); eq(api.rooms[101].area,first)
  local second=assert(api.addAreaName("Second manual area")); assert(api.setRoomArea(101,second))
  assert(mapper:onRoom(gmcpRoom(102))); eq(api.rooms[102].area,second); eq(api.rooms[101].area,second)
  eq(api.rooms[100].area,first); eq(api.nextArea,4)
end)

test("untracked same-game-area expansion inherits a manually selected area",function()
  local api=fakeMapApi(); local mapper=Automapper.new(Model,Adapter.new(api))
  assert(mapper:onRoom(gmcpRoom(100))); local actual=assert(api.addAreaName("Manual same-map area"))
  assert(api.setRoomArea(100,actual)); assert(mapper:onRoom(gmcpRoom(101)))
  eq(api.rooms[101].area,actual); eq(api.rooms[100].exits.n,nil); eq(api.nextArea,3)
end)

test("special movement inherits manual areas unless its category explicitly enables a submap",function()
  for _,enabled in ipairs({false,true}) do
    local api=fakeMapApi(); local mapper=Automapper.new(Model,Adapter.new(api),nil,{door=enabled})
    assert(mapper:onRoom(gmcpRoom(100))); local actual=assert(api.addAreaName("Manual portal area"))
    assert(api.setRoomArea(100,actual)); assert(api.setRoomCoordinates(100,4,5,1))
    assert(mapper:onSpecialTransition({from=100,to=900,command="go door",category="door",kind="special"}))
    assert(mapper:onRoom(gmcpRoom(900,2)))
    if enabled then
      eq(api.rooms[900].area,api.areas["Dragons Gate - Submap 900"]); assert(api.rooms[900].area~=actual)
      eq(api.rooms[900].x,0); eq(api.rooms[900].y,0); eq(api.nextArea,4)
    else
      eq(api.rooms[900].area,actual); eq(api.rooms[900].x,4); eq(api.rooms[900].y,6); eq(api.nextArea,3)
    end
    eq(api.special[100]["go door"],900); eq(api.rooms[100].area,actual); eq(next(api.areaUser[actual]),nil)
  end
end)

test("known destinations retain manual area and coordinates for ordinary and special arrivals",function()
  for _,special in ipairs({false,true}) do
    local api=fakeMapApi(); local map=Adapter.new(api); local mapper=Automapper.new(Model,map,nil,{door=true})
    assert(map:ensureRoom(descriptor(900,"1"),{x=8,y=9,z=2},"special:900"))
    local actual=assert(api.addAreaName("Known manual destination")); assert(api.setRoomArea(900,actual))
    assert(mapper:onRoom(gmcpRoom(100)))
    if special then assert(mapper:onSpecialTransition({from=100,to=900,command="go door",category="door",kind="special"})) else mapper:onOutgoing("north") end
    assert(mapper:onRoom(gmcpRoom(900)))
    eq(api.rooms[900].area,actual); eq(api.rooms[900].x,8); eq(api.rooms[900].y,9); eq(api.rooms[900].z,2)
    eq(api.rooms[900].user["dghud.partition"],"special:900")
    mapper:onOutgoing("north"); assert(mapper:onRoom(gmcpRoom(901)))
    eq(api.rooms[901].area,actual); eq(api.rooms[901].y,10); eq(api.nextArea,4)
  end
end)

test("manual-area coordinate collisions preserve existing personal and HUD room positions",function()
  local api=fakeMapApi(); local map=Adapter.new(api); local mapper=Automapper.new(Model,map)
  assert(mapper:onRoom(gmcpRoom(100))); assert(map:ensureRoom(descriptor(200,"1"),{x=0,y=1,z=0}))
  local actual=assert(api.addAreaName("My arranged map"))
  api.areaUser[actual]["dghud.owner"]="OtherMapper"; api.areaUser[actual].notes="keep this area"
  assert(api.setRoomArea(100,actual)); assert(api.setRoomArea(200,actual))
  api.rooms[201]={area=actual,x=0,y=2,z=0,user={},name="Personal room",exits={},stubs={}}
  mapper:onOutgoing("north"); assert(mapper:onRoom(gmcpRoom(101)))
  eq(api.rooms[101].area,actual); assert(api.rooms[101].x~=0 or api.rooms[101].y~=1)
  eq(api.rooms[200].x,0); eq(api.rooms[200].y,1); eq(api.rooms[201].x,0); eq(api.rooms[201].y,2)
  eq(api.rooms[201].name,"Personal room"); eq(next(api.rooms[201].user),nil); eq(api.nextArea,3)
  eq(api.areaUser[actual]["dghud.owner"],"OtherMapper"); eq(api.areaUser[actual].notes,"keep this area")
  eq(api.areaUser[actual]["dghud.partition"],nil); eq(#api.deletedRooms,0); eq(#api.deletedAreas,0)
end)

test("manual-area inheritance works with missing room and area partition metadata",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"1"),{x=4,y=5,z=1}))
  local actual=assert(api.addAreaName("Hand made area")); assert(api.setRoomArea(100,actual))
  api.rooms[100].user["dghud.partition"]=nil; api.rooms[100].user["dghud.game_area"]=nil
  local getAreaUserData=api.getAreaUserData
  api.getAreaUserData=function(id,key)
    local value=getAreaUserData(id,key)
    if value==nil then return nil,"no user data with key '"..key.."'" end
    return value
  end
  local mapper=Automapper.new(Model,Adapter.new(api))
  assert(mapper:onRoom(gmcpRoom(100))); mapper:onOutgoing("north"); assert(mapper:onRoom(gmcpRoom(101)))
  eq(api.rooms[100].area,actual); eq(api.rooms[100].x,4); eq(api.rooms[100].y,5)
  eq(api.rooms[100].user["dghud.partition"],"area:"..actual); eq(api.rooms[101].area,actual)
  eq(api.rooms[101].user["dghud.partition"],"area:"..actual); eq(next(api.areaUser[actual]),nil); eq(api.nextArea,3)
end)

test("source area without partition metadata is resolved live rather than from the cached old partition",function()
  for _,name in ipairs({"Dragons Gate - Castle","Renamed owned area"}) do
    local api=fakeMapApi(); local map=Adapter.new(api); local mapper=Automapper.new(Model,map)
    assert(mapper:onRoom(gmcpRoom(100)))
    local actual=assert(api.addAreaName(name)); api.areaUser[actual]["dghud.owner"]="DragonsGateHUD"
    assert(api.setRoomArea(100,actual)); mapper:onOutgoing("north"); assert(mapper:onRoom(gmcpRoom(101)))
    local expected=name=="Dragons Gate - Castle" and "Castle" or ("area:"..actual)
    eq(api.rooms[101].area,actual); eq(api.rooms[101].user["dghud.partition"],expected)
    eq(api.rooms[100].user["dghud.partition"],"1"); eq(api.nextArea,3)
  end
end)

test("source-area lookup failures never fall back to the old partition or create rooms",function()
  for _,failure in ipairs({"getRoomArea","getAreaTable","getAreaUserData","missing area","invalid area","invalid area table","unowned source","missing source"}) do
    local api=fakeMapApi(); local mapper=Automapper.new(Model,Adapter.new(api))
    assert(mapper:onRoom(gmcpRoom(100))); local actual=assert(api.addAreaName("My area"))
    assert(api.setRoomArea(100,actual)); mapper:onOutgoing("north")
    if failure=="missing area" then api.areas["My area"]=nil
    elseif failure=="invalid area" then api.rooms[100].area=-1
    elseif failure=="invalid area table" then api.getAreaTable=function() return false end
    elseif failure=="unowned source" then api.rooms[100].user["dghud.owner"]="OtherMapper"
    elseif failure=="missing source" then api.rooms[100]=nil
    else api.fail[failure]=true end
    local mutations=0
    for _,method in ipairs({"addRoom","deleteRoom","addAreaName","deleteArea","setAreaUserData","setRoomArea","setRoomName","setRoomCoordinates","setRoomUserData","setExit","setExitStub","centerview"}) do
      local native=api[method]; api[method]=function(...) mutations=mutations+1; return native(...) end
    end
    local ok,err=mapper:onRoom(gmcpRoom(101)); eq(ok,nil); assert(type(err)=="string" and err~="")
    eq(mutations,0); eq(api.rooms[101],nil); eq(api.nextArea,3); eq(next(api.areaUser[actual]),nil)
  end
end)

test("inheriting a personal area requires a valid owned placed source room",function()
  for _,source in ipairs({0,999,100,200}) do
    local api=fakeMapApi(); local actual=assert(api.addAreaName("Personal area"))
    api.rooms[100]={area=actual,x=0,y=0,z=0,user={},exits={},stubs={}}
    api.rooms[200]={area=actual,x=0,y=0,z=0,user={["dghud.owner"]="DragonsGateHUD",["dghud.state"]="provisional"},exits={},stubs={}}
    local ok,err=Adapter.new(api):ensureRoom(descriptor(101),{},"1",source)
    eq(ok,nil); assert(type(err)=="string" and err~=""); eq(api.rooms[101],nil); eq(api.nextArea,2)
    eq(next(api.areaUser[actual]),nil); eq(#api.deletedRooms,0); eq(#api.deletedAreas,0)
  end
end)

test("interrupted inherited placement can retry in a manual area after adapter reload",function()
  for _,failure in ipairs({"setRoomArea","setRoomCoordinates"}) do
    local api=fakeMapApi(); local mapper=Automapper.new(Model,Adapter.new(api))
    assert(mapper:onRoom(gmcpRoom(100))); local actual=assert(api.addAreaName("Personal retry area"))
    assert(api.setRoomArea(100,actual)); mapper:onOutgoing("north"); api.fail[failure]=true
    local ok,err=mapper:onRoom(gmcpRoom(101)); eq(ok,nil); eq(err,failure.." rejected")
    eq(api.rooms[101].user["dghud.state"],"provisional")
    api.fail[failure]=nil; mapper=Automapper.new(Model,Adapter.new(api))
    assert(mapper:onRoom(gmcpRoom(100))); mapper:onOutgoing("north"); assert(mapper:onRoom(gmcpRoom(101)))
    eq(api.rooms[101].area,actual); eq(api.rooms[101].y,1); eq(api.rooms[101].user["dghud.state"],"ready")
    eq(api.nextArea,3); eq(next(api.areaUser[actual]),nil); eq(#api.deletedRooms,0); eq(#api.deletedAreas,0)
  end
end)

test("creates a fully tagged room and finalizes readiness last",function()
  local api=fakeMapApi(); local calls={}; local native=api.setRoomUserData
  api.setRoomUserData=function(id,k,v) calls[#calls+1]=k; return native(id,k,v) end
  assert(Adapter.new(api):ensureRoom(descriptor(176,"1","Training square."),{x=0,y=1,z=2}))
  local r=api.rooms[176]; eq(r.name,""); eq(r.user["dghud.owner"],"DragonsGateHUD"); eq(calls[#calls],"dghud.state"); eq(r.user["dghud.state"],"ready")
  eq(r.user["dghud.mapper_schema"],"1"); eq(r.user["dghud.environment"],"Plain"); eq(r.user["dghud.flags"],"indoor")
  eq(r.x,0); eq(r.y,1); eq(r.z,2); eq(api.areaUser[r.area]["dghud.owner"],"DragonsGateHUD")
end)

test("transfer backend lists only owned canonical rooms and snapshots complete state",function()
  local api=fakeMapApi(); local map=Adapter.new(api); local source=descriptor(10,"A","Market"); source.flags={"safe","shop"}
  assert(map:ensureRoom(source,{x=2,y=3,z=1},"A")); assert(map:ensureRoom(descriptor(11,"A","North"),{x=2,y=4,z=1},"A")); assert(map:connect(10,11,"n",false)); assert(map:connectSpecial(10,11,"go arch"))
  api.rooms[99]={name="Personal",area=7,x=9,y=9,z=0,user={},exits={},stubs={}}
  assert(api.setRoomUserData(10,"dghud.poi_tags","bank,trainer")); assert(api.setRoomUserData(10,"dghud.stash_owner","Deklan")); assert(api.setRoomUserData(10,"dghud.derived_from_artifact","sha256:abc")); assert(api.setRoomUserData(10,"dghud.derived_from_author","Gia"))
  local ids=assert(map:listRooms()); eq(table.concat(ids,","),"10,11")
  local room=assert(map:getRoom(10)); eq(room.id,10); eq(room.area,"A"); eq(room.partition,"A"); eq(room.x,2); eq(room.y,3); eq(room.z,1); eq(room.name,"Market"); eq(table.concat(room.flags,","),"safe,shop"); eq(table.concat(room.poi,","),"bank,trainer"); eq(room.exits[1].direction,"n"); eq(room.exits[1].to,11); eq(room.special_exits[1].command,"go arch"); eq(room.stash_owner,"Deklan"); eq(room.derived_from.author,"Gia")
  eq(assert(map:getRoom(99)).owner,"personal")
end)
test("transfer export ignores missing ownership on personal rooms and absent optional metadata",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(10,"A","Market"),{x=2,y=3,z=0},"A")); api.rooms[99]={name="Personal",area=7,x=9,y=9,z=0,user={},exits={},stubs={}}
  local native=api.getRoomUserData; api.getRoomUserData=function(id,key) local value=native(id,key); if value=="" then return nil,"no user data with key '"..key.."' in roomID "..id end; return value end
  local ids=assert(map:listRooms()); eq(table.concat(ids,","),"10"); local room=assert(map:getRoom(10)); eq(room.stash_owner,nil); eq(room.derived_from,nil); eq(assert(map:getRoom(99)).owner,"personal")
end)

test("transfer put replaces a whole owned room and removes stale exits",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(20,"Old","Old"),{x=8,y=8,z=2},"Old")); assert(map:ensureRoom(descriptor(21,"Old","Peer"),{},"Old")); assert(map:connect(20,21,"n",false)); assert(map:connectSpecial(20,21,"old door"))
  local replacement={id=20,area="New",partition="special:20",x=1,y=2,z=3,name="Imported",environment="City",flags={"safe"},poi={"bank"},exits={{direction="e",to=21}},special_exits={{command="go arch",to=21}},stash_owner="Deklan",derived_from={artifact_id="sha256:new",author="Gia",verified=false},read_only=false}
  assert(map:putRoom(replacement)); local saved=assert(map:getRoom(20)); eq(saved.area,"New"); eq(saved.partition,"special:20"); eq(saved.x,1); eq(saved.name,"Imported"); eq(saved.exits[1].direction,"e"); eq(#saved.exits,1); eq(saved.special_exits[1].command,"go arch"); eq(#saved.special_exits,1); eq(saved.poi[1],"bank"); eq(saved.stash_owner,"Deklan")
end)

test("transfer backend refuses writes and deletes against personal rooms",function()
  local personal={name="Personal",area=9,x=4,y=5,z=0,user={},exits={},stubs={}}; local api=fakeMapApi({[30]=personal}); local map=Adapter.new(api)
  local record={id=30,area="A",partition="A",x=0,y=0,z=0,name="Bad",environment="",flags={},poi={},exits={},special_exits={}}
  local ok,err=map:putRoom(record); eq(ok,nil); assert(err:find("another mapper",1,true)); ok,err=map:deleteRoom(30); eq(ok,nil); assert(err:find("another mapper",1,true)); eq(api.rooms[30],personal)
end)

test("transfer whole-room restore repairs partial failed replacement",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(40,"A","Original"),{x=7,y=6,z=1},"A")); assert(map:ensureRoom(descriptor(41,"A","Peer"),{},"A")); assert(map:connect(40,41,"n",false)); assert(map:connectSpecial(40,41,"old gate")); local snapshot=assert(map:getRoom(40))
  local replacement={id=40,area="B",partition="B",x=0,y=0,z=0,name="Replacement",environment="Dark",flags={},poi={},exits={{direction="e",to=41}},special_exits={{command="new gate",to=41}}}
  api.fail.addSpecialExit=true; local ok,err=map:putRoom(replacement); eq(ok,nil); eq(err,"addSpecialExit rejected"); api.fail.addSpecialExit=nil
  assert(map:putRoom(snapshot)); local restored=assert(map:getRoom(40)); eq(restored.area,snapshot.area); eq(restored.partition,snapshot.partition); eq(restored.x,snapshot.x); eq(restored.y,snapshot.y); eq(restored.z,snapshot.z); eq(restored.name,snapshot.name); eq(restored.exits[1].direction,"n"); eq(#restored.exits,1); eq(restored.special_exits[1].command,"old gate"); eq(#restored.special_exits,1)
end)

test("HUD rooms keep native mapper labels blank while preserving descriptive metadata",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(176,"1","Training square."),{x=0,y=0,z=0}))
  eq(api.rooms[176].name,"")
  eq(api.rooms[176].user["dghud.room_name"],"Training square.")
  assert(map:ensureRoom(descriptor(176,"1","Training Center."),{x=9,y=9,z=9}))
  eq(api.rooms[176].name,"")
  eq(api.rooms[176].user["dghud.room_name"],"Training Center.")
end)

test("legacy label cleanup changes only HUD-owned rooms",function()
  local api=fakeMapApi({
    [10]={name="Old HUD label",user={["dghud.owner"]="DragonsGateHUD"}},
    [11]={name="Personal room",user={}},
    [12]={name="Other package",user={["dghud.owner"]="SomeoneElse"}},
  })
  local count=assert(Adapter.new(api):clearOwnedRoomNames())
  eq(count,1); eq(api.rooms[10].name,""); eq(api.rooms[11].name,"Personal room"); eq(api.rooms[12].name,"Other package")
end)

test("legacy label cleanup consumes documented room IDs and reports read failures",function()
  local api=fakeMapApi({[10]={name="Old",user={["dghud.owner"]="DragonsGateHUD"}}})
  local nativeGetRooms=api.getRooms
  api.getRooms=function() return {[10]="Old"} end
  eq(Adapter.new(api):clearOwnedRoomNames(),1)
  api.getRooms=nativeGetRooms
  api.fail.getRooms=true
  local count,err=Adapter.new(api):clearOwnedRoomNames(); eq(count,nil); eq(err,"getRooms rejected")
end)

test("legacy label cleanup never interprets a numeric room name as an ID",function()
  local api=fakeMapApi({
    [50]={name="100",user={["dghud.owner"]="DragonsGateHUD"}},
    [100]={name="Keep room 100",user={["dghud.owner"]="DragonsGateHUD"}},
  })
  api.getRooms=function() return {[50]="100"} end
  local count=assert(Adapter.new(api):clearOwnedRoomNames())
  eq(count,1); eq(api.rooms[50].name,""); eq(api.rooms[100].name,"Keep room 100")
end)

test("legacy label migration scans once and persists a map-level completion gate",function()
  local api=fakeMapApi({
    [10]={name="Old HUD label",user={["dghud.owner"]="DragonsGateHUD"}},
    [11]={name="Personal room",user={}},
  })
  local calls=0; local nativeGetRooms=api.getRooms
  api.getRooms=function(...) calls=calls+1; return nativeGetRooms(...) end
  local changed,ran=assert(Adapter.new(api):migrateLegacyRoomNames())
  eq(changed,1); eq(ran,true); eq(calls,1); eq(api.rooms[10].name,""); eq(api.rooms[11].name,"Personal room")
  changed,ran=assert(Adapter.new(api):migrateLegacyRoomNames())
  eq(changed,0); eq(ran,false); eq(calls,1)
end)

test("legacy label migration marks complete only after an ownership-safe scan succeeds",function()
  local api=fakeMapApi({[10]={name="Old HUD label",user={["dghud.owner"]="DragonsGateHUD"}}})
  api.fail.setRoomName=true
  local changed,err=Adapter.new(api):migrateLegacyRoomNames(); eq(changed,nil); eq(err,"setRoomName rejected"); eq(api.mapUser["dghud.legacy_room_names_schema"],nil)
  api.fail.setRoomName=nil; api.fail.setMapUserData=true
  changed,err=Adapter.new(api):migrateLegacyRoomNames(); eq(changed,nil); eq(err,"setMapUserData rejected"); eq(api.mapUser["dghud.legacy_room_names_schema"],nil)
end)

test("reuses a persisted owned area after adapter reload",function()
  local api=fakeMapApi(); assert(Adapter.new(api):ensureRoom(descriptor(1,"Castle"),{})); local area=api.rooms[1].area
  assert(Adapter.new(api):ensureRoom(descriptor(2,"Castle"),{})); eq(api.rooms[2].area,area); eq(api.nextArea,2)
end)

test("cached area IDs are validated and recreated after external backend clearing",function()
  local api=fakeMapApi(); local map=Adapter.new(api); local first=assert(map:ensureArea("Castle")); api.areas={}; api.areaUser={}; api.nextArea=first+1
  local recreated=assert(map:ensureArea("Castle")); assert(recreated~=first); eq(api.areaUser[recreated]["dghud.owner"],"DragonsGateHUD")
end)

test("area deletion fails closed for labels or unavailable label inspection",function()
  local api=fakeMapApi(); local map=Adapter.new(api); local area=assert(map:ensureArea("Owned")); api.labels[area]={[1]={text="personal"}}
  local ok,err=map:deleteEmptyOwnedArea(area); eq(ok,nil); assert(err:find("contains labels",1,true)); eq(api.areas["Dragons Gate - Owned"],area)
  api.labels[area]={}; api.fail.getMapLabels=true; ok,err=map:deleteEmptyOwnedArea(area); eq(ok,nil); eq(err,"getMapLabels rejected")
end)

test("rejects an unowned area collision before adding a room",function()
  local api=fakeMapApi(); api.areas["Dragons Gate - Castle"]=41; api.areaUser[41]={}; api.nextArea=42
  local ok,e=Adapter.new(api):ensureRoom(descriptor(7,"Castle"),{}); eq(ok,nil); eq(e,"area Dragons Gate - Castle is not owned by DragonsGateHUD"); eq(api.rooms[7],nil)
end)

test("creates distinct areas with distinct IDs",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(1,"A"),{})); assert(map:ensureRoom(descriptor(2,"B"),{})); assert(api.rooms[1].area~=api.rooms[2].area)
end)

test("persists a special destination partition keyed by canonical room ID",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(900,"1","Vault"),{x=0,y=0,z=0},"special:900"))
  eq(api.rooms[900].user["dghud.partition"],"special:900")
  eq(api.rooms[900].user["dghud.game_area"],"1")
  eq(api.areas["Dragons Gate - Submap 900"],api.rooms[900].area)
  local record=assert(Adapter.new(api):roomRecord(900))
  eq(record.exists,true); eq(record.owned,true); eq(record.partition,"special:900"); eq(record.area,api.rooms[900].area)
  eq(record.coordinates.x,0); eq(record.coordinates.y,0); eq(record.coordinates.z,0); eq(record.placement_needed,false)
end)

test("persists an isolated destination area keyed by canonical room ID",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(901,"7","Unexpected arrival"),{x=0,y=0,z=0},"isolated:901"))
  eq(api.rooms[901].user["dghud.partition"],"isolated:901")
  eq(api.areas["Dragons Gate - Isolated 901"],api.rooms[901].area)
  eq(assert(Adapter.new(api):effectivePartition(901)),"isolated:901")
end)

test("existing canonical rooms retain their area coordinates and partition",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(900,"1"),{x=0,y=0,z=0},"special:900"))
  local area=api.rooms[900].area
  assert(map:ensureRoom(descriptor(900,"2","Revisited"),{x=8,y=8,z=4},"special:other"))
  eq(api.rooms[900].area,area); eq(api.rooms[900].x,0); eq(api.rooms[900].y,0); eq(api.rooms[900].z,0)
  eq(api.rooms[900].user["dghud.partition"],"special:900")
  eq(api.rooms[900].user["dghud.game_area"],"1")
  eq(api.rooms[900].name,""); eq(api.rooms[900].user["dghud.room_name"],"Revisited")
end)

test("migrates an existing owned room to its current effective partition without moving it",function()
  local existing={name="Legacy",area=41,x=3,y=4,z=1,user={["dghud.owner"]="DragonsGateHUD",["dghud.state"]="ready"},exits={},stubs={}}
  local api=fakeMapApi({[900]=existing}); api.areas["Dragons Gate - Castle"]=41; api.areaUser[41]={["dghud.owner"]="DragonsGateHUD"}; api.nextArea=42
  local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(900,"1","Migrated"),{x=8,y=8,z=4},"special:900"))
  eq(existing.area,41); eq(existing.x,3); eq(existing.y,4); eq(existing.z,1)
  eq(existing.user["dghud.partition"],"Castle"); eq(existing.user["dghud.game_area"],"1")
  eq(assert(map:effectivePartition(900)),"Castle"); eq(api.nextArea,42)
end)

test("migration from an unowned area never authorizes new placement",function()
  local existing={name="Legacy",area=41,x=3,y=4,z=1,user={["dghud.owner"]="DragonsGateHUD",["dghud.state"]="ready"},exits={},stubs={}}
  local api=fakeMapApi({[900]=existing}); api.areas["Dragons Gate - Castle"]=41; api.areaUser[41]={}; api.nextArea=42
  local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(900,"1","Migrated"),{x=8,y=8,z=4},"special:900"))
  eq(existing.area,41); eq(existing.x,3); eq(existing.y,4); eq(existing.z,1); eq(existing.user["dghud.partition"],"Castle")

  local mutations=0
  for _,name in ipairs({"addRoom","deleteRoom","addAreaName","deleteArea","setAreaUserData","setRoomArea","setRoomName","setRoomCoordinates","setRoomUserData"}) do
    local native=api[name]
    api[name]=function(...) mutations=mutations+1; return native(...) end
  end
  local ok,e=map:ensureRoom(descriptor(901,"Castle"),{x=5,y=5,z=0},"Castle")
  eq(ok,nil); eq(e,"area Dragons Gate - Castle is not owned by DragonsGateHUD")
  eq(mutations,0); eq(api.rooms[901],nil); eq(api.nextArea,42)
end)

test("refuses an unowned canonical room collision with zero mutation",function()
  local original={name="Personal",area=9,user={},x=8,y=7,z=6,exits={},stubs={}}; local api=fakeMapApi({[176]=original})
  local mutations=0
  for _,name in ipairs({"addRoom","deleteRoom","addAreaName","deleteArea","setAreaUserData","setRoomArea","setRoomName","setRoomCoordinates","setRoomUserData"}) do
    local native=api[name]
    api[name]=function(...) mutations=mutations+1; return native(...) end
  end
  local map=Adapter.new(api); local record=assert(map:roomRecord(176))
  eq(record.exists,true); eq(record.owned,false); eq(record.area,9); eq(record.coordinates.x,8)
  local ok,e=map:ensureRoom(descriptor(176),{x=0},"special:176")
  eq(ok,nil); eq(e,"room 176 is not owned by DragonsGateHUD"); eq(mutations,0)
  eq(original.name,"Personal"); eq(original.area,9); eq(original.x,8); eq(original.y,7); eq(original.z,6); eq(next(original.user),nil)
end)

test("updates owned rooms and retains ownership on failure",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(1),{})); assert(map:ensureRoom(descriptor(1,"A","Changed"),{x=2,y=3,z=0})); eq(api.rooms[1].name,""); eq(api.rooms[1].user["dghud.room_name"],"Changed")
  api.fail.setRoomName=true; local ok,e=map:ensureRoom(descriptor(1,"A","Nope"),{}); eq(ok,nil); eq(e,"setRoomName rejected"); eq(api.rooms[1].user["dghud.owner"],"DragonsGateHUD")
end)

test("post-create room mutation failures remain safely retryable",function()
  for _,name in ipairs({"setRoomArea","setRoomName","setRoomCoordinates"}) do
    local api=fakeMapApi(); local map=Adapter.new(api); api.fail[name]=true; local ok,e=map:ensureRoom(descriptor(20),{})
    eq(ok,nil); eq(e,name.." rejected"); eq(api.rooms[20].user["dghud.owner"],"DragonsGateHUD"); eq(api.rooms[20].user["dghud.state"],"provisional")
    api.fail[name]=nil; assert(map:ensureRoom(descriptor(20),{x=2,y=3,z=4})); eq(api.rooms[20].user["dghud.state"],"ready")
    assert(api.rooms[20].area); eq(api.rooms[20].x,2); eq(api.rooms[20].y,3); eq(api.rooms[20].z,4)
  end
  for failureCall=2,6 do
    local api=fakeMapApi(); local map=Adapter.new(api); local native=api.setRoomUserData; local calls=0
    api.setRoomUserData=function(...) calls=calls+1; if calls==failureCall then return nil,"room metadata rejected" end; return native(...) end
    local ok,e=map:ensureRoom(descriptor(21),{}); eq(ok,nil); eq(e,"room metadata rejected"); api.setRoomUserData=native
    assert(map:ensureRoom(descriptor(21),{})); eq(api.rooms[21].user["dghud.owner"],"DragonsGateHUD"); eq(api.rooms[21].user["dghud.state"],"ready")
  end
end)

test("fresh adapter recovers an owned room after its provisional state write failed",function()
  local api=fakeMapApi(); local native=api.setRoomUserData; local rejectProvisional=true
  api.setRoomUserData=function(id,k,v)
    if rejectProvisional and k=="dghud.state" and v=="provisional" then return nil,"provisional state rejected" end
    return native(id,k,v)
  end
  local ok,e=Adapter.new(api):ensureRoom(descriptor(22,"Castle"),{x=1,y=2,z=3},"special:22")
  eq(ok,nil); eq(e,"provisional state rejected"); assert(api.rooms[22]); eq(api.rooms[22].user["dghud.owner"],"DragonsGateHUD")
  eq(api.rooms[22].user["dghud.state"],nil); eq(api.rooms[22].user["dghud.mapper_schema"],nil); eq(api.rooms[22].user["dghud.environment"],nil)
  eq(api.rooms[22].user["dghud.flags"],nil); eq(api.rooms[22].user["dghud.partition"],nil); eq(api.rooms[22].user["dghud.game_area"],nil)
  eq(api.rooms[22].area,-1); eq(api.rooms[22].x,0); eq(api.rooms[22].y,0); eq(api.rooms[22].z,0); eq(#api.deletedRooms,0)
  local interrupted=assert(Adapter.new(api):roomRecord(22))
  eq(interrupted.state,nil); eq(interrupted.mapper_schema,nil); eq(interrupted.environment,nil)
  eq(interrupted.flags,nil); eq(interrupted.partition,nil); eq(interrupted.game_area,nil); eq(interrupted.placement_needed,true)

  rejectProvisional=false
  local mutations={}; local nativeArea=api.setRoomArea; local nativeCoordinates=api.setRoomCoordinates
  api.setRoomUserData=function(id,k,v) mutations[#mutations+1]=k.."="..v; return native(id,k,v) end
  api.setRoomArea=function(id,v) mutations[#mutations+1]="area="..v; return nativeArea(id,v) end
  api.setRoomCoordinates=function(id,x,y,z) mutations[#mutations+1]="coordinates="..x..","..y..","..z; return nativeCoordinates(id,x,y,z) end
  assert(Adapter.new(api):ensureRoom(descriptor(22,"Castle"),{x=1,y=2,z=3},"special:22"))
  local intendedArea=api.areas["Dragons Gate - Submap 22"]; eq(api.rooms[22].area,intendedArea)
  eq(api.rooms[22].user["dghud.partition"],"special:22"); eq(api.rooms[22].user["dghud.game_area"],"Castle")
  eq(api.rooms[22].x,1); eq(api.rooms[22].y,2); eq(api.rooms[22].z,3); eq(api.rooms[22].user["dghud.state"],"ready")
  eq(mutations[#mutations-4],"dghud.partition=special:22"); eq(mutations[#mutations-3],"dghud.game_area=Castle")
  eq(mutations[#mutations-2],"area="..intendedArea); eq(mutations[#mutations-1],"coordinates=1,2,3"); eq(mutations[#mutations],"dghud.state=ready")
  eq(#api.deletedRooms,0)
end)

test("fresh automapper retry places an owner-only special destination in its destination submap",function()
  local api=fakeMapApi(); local rejectProvisional=false; local nativeUserData=api.setRoomUserData; local statuses={}
  api.setRoomUserData=function(id,key,value)
    if rejectProvisional and id==900 and key=="dghud.state" and value=="provisional" then return nil,"provisional state rejected" end
    return nativeUserData(id,key,value)
  end
  local first=Automapper.new(Model,Adapter.new(api),function(kind,message) statuses[#statuses+1]={kind=kind,message=message} end,{other=true})
  assert(first:onRoom(gmcpRoom(100,1,"Outside")))
  assert(first:onSpecialTransition({from=100,to=900,command="go gate",kind="special"}))
  rejectProvisional=true
  local ok,e=first:onRoom(gmcpRoom(900,1,"Inside")); eq(ok,nil); eq(e,"provisional state rejected")
  eq(api.rooms[900].area,-1); eq(api.rooms[900].x,0); eq(api.rooms[900].y,0); eq(api.rooms[900].z,0)

  rejectProvisional=false
  ok,e=first:onRoom(gmcpRoom(900,1,"Inside refreshed"))
  eq(ok,nil); eq(e,"room 900 placement requires an observed transition")
  eq(statuses[#statuses].kind,"invalid_room"); eq(statuses[#statuses].message,e)
  local stillInterrupted=assert(Adapter.new(api):roomRecord(900))
  eq(stillInterrupted.placement_needed,true); eq(stillInterrupted.state,nil); eq(stillInterrupted.partition,nil)
  eq(stillInterrupted.area,-1); eq(stillInterrupted.coordinates.x,0); eq(stillInterrupted.coordinates.y,0); eq(stillInterrupted.coordinates.z,0)
  eq(first:currentRoom(),nil); eq(api.special[100],nil)

  local retried=Automapper.new(Model,Adapter.new(api),function() end,{other=true})
  assert(retried:onRoom(gmcpRoom(100,1,"Outside")))
  assert(retried:onSpecialTransition({from=100,to=900,command="go gate",kind="special"}))
  assert(retried:onRoom(gmcpRoom(900,1,"Inside")))
  local submapArea=api.areas["Dragons Gate - Submap 900"]
  local record=assert(Adapter.new(api):roomRecord(900))
  eq(record.partition,"special:900"); eq(record.area,submapArea)
  eq(record.coordinates.x,0); eq(record.coordinates.y,0); eq(record.coordinates.z,0); eq(record.state,"ready")
  eq(api.special[100]["go gate"],900)
end)

test("fresh automapper retry derives coordinates for a provisional directional continuation",function()
  local api=fakeMapApi(); local statuses={}
  assert(Adapter.new(api):ensureRoom(descriptor(900,"1","Root"),{x=0,y=0,z=0},"special:900"))
  local submapArea=api.areas["Dragons Gate - Submap 900"]

  local first=Automapper.new(Model,Adapter.new(api),function(kind,message) statuses[#statuses+1]={kind=kind,message=message} end)
  assert(first:onRoom(gmcpRoom(900,1,"Root",{"north"})))
  assert(first:onOutgoing("north"))
  api.fail.setRoomCoordinates=true
  local ok,e=first:onRoom(gmcpRoom(901,1,"Hall",{"south"}))
  eq(ok,nil); eq(e,"setRoomCoordinates rejected")
  local interrupted=assert(Adapter.new(api):roomRecord(901))
  eq(interrupted.state,"provisional"); eq(interrupted.placement_needed,true)
  eq(interrupted.partition,"special:900"); eq(interrupted.area,submapArea)
  eq(interrupted.coordinates.x,0); eq(interrupted.coordinates.y,0); eq(interrupted.coordinates.z,0)

  api.fail.setRoomCoordinates=nil
  ok,e=first:onRoom(gmcpRoom(901,1,"Hall refreshed",{"south"}))
  eq(ok,nil); eq(e,"room 901 placement requires an observed transition")
  eq(statuses[#statuses].kind,"invalid_room"); eq(statuses[#statuses].message,e)
  local stillInterrupted=assert(Adapter.new(api):roomRecord(901))
  eq(stillInterrupted.placement_needed,true); eq(stillInterrupted.state,"provisional")
  eq(stillInterrupted.partition,"special:900"); eq(stillInterrupted.area,submapArea)
  eq(stillInterrupted.coordinates.x,0); eq(stillInterrupted.coordinates.y,0); eq(stillInterrupted.coordinates.z,0)
  eq(first:currentRoom(),nil); eq(api.rooms[900].exits.n,nil); eq(api.rooms[901].exits.s,nil)

  local retried=Automapper.new(Model,Adapter.new(api),function() end)
  assert(retried:onRoom(gmcpRoom(900,1,"Root",{"north"})))
  assert(retried:onOutgoing("north"))
  assert(retried:onRoom(gmcpRoom(901,1,"Hall",{"south"})))
  local record=assert(Adapter.new(api):roomRecord(901))
  eq(record.state,"ready"); eq(record.placement_needed,false)
  eq(record.partition,"special:900"); eq(record.area,submapArea)
  eq(record.coordinates.x,0); eq(record.coordinates.y,1); eq(record.coordinates.z,0)
  eq(api.rooms[900].exits.n,901); eq(api.rooms[901].exits.s,900)
end)

test("mature owned legacy room without state is never relocated",function()
  local existing={name="Legacy",area=41,x=3,y=4,z=1,user={["dghud.owner"]="DragonsGateHUD",["dghud.mapper_schema"]="1"},exits={},stubs={}}
  local api=fakeMapApi({[24]=existing}); api.areas["Dragons Gate - Castle"]=41; api.areaUser[41]={["dghud.owner"]="DragonsGateHUD"}; api.nextArea=42
  assert(Adapter.new(api):ensureRoom(descriptor(24,"2","Refreshed"),{x=8,y=8,z=4},"special:24"))
  eq(existing.area,41); eq(existing.x,3); eq(existing.y,4); eq(existing.z,1); eq(existing.name,""); eq(existing.user["dghud.room_name"],"Refreshed")
  eq(existing.user["dghud.partition"],"Castle"); eq(existing.user["dghud.game_area"],"2"); eq(existing.user["dghud.state"],"ready")
  eq(api.nextArea,42); eq(#api.deletedRooms,0)
end)

test("fresh adapter finishes provisional coordinates before marking the room ready",function()
  local api=fakeMapApi(); api.fail.setRoomCoordinates=true
  local ok,e=Adapter.new(api):ensureRoom(descriptor(23,"Castle"),{x=1,y=2,z=3},"special:23")
  eq(ok,nil); eq(e,"setRoomCoordinates rejected"); eq(api.rooms[23].user["dghud.state"],"provisional")
  assert(api.rooms[23].area); eq(api.rooms[23].x,0); eq(api.rooms[23].y,0); eq(api.rooms[23].z,0); eq(#api.deletedRooms,0)
  local record=assert(Adapter.new(api):roomRecord(23)); eq(record.state,"provisional"); eq(record.placement_needed,true)

  ok,e=Adapter.new(api):ensureRoom(descriptor(23,"Castle"),{x=7,y=8,z=9},"special:23")
  eq(ok,nil); eq(e,"setRoomCoordinates rejected"); eq(api.rooms[23].user["dghud.state"],"provisional"); eq(#api.deletedRooms,0)

  api.fail.setRoomCoordinates=nil
  local mutations={}; local nativeCoordinates=api.setRoomCoordinates; local nativeUserData=api.setRoomUserData
  api.setRoomCoordinates=function(...) mutations[#mutations+1]="coordinates"; return nativeCoordinates(...) end
  api.setRoomUserData=function(id,k,v) mutations[#mutations+1]=k.."="..v; return nativeUserData(id,k,v) end
  assert(Adapter.new(api):ensureRoom(descriptor(23,"Castle"),{x=7,y=8,z=9},"special:23"))
  eq(api.rooms[23].x,7); eq(api.rooms[23].y,8); eq(api.rooms[23].z,9)
  eq(api.rooms[23].user["dghud.state"],"ready"); eq(mutations[#mutations],"dghud.state=ready"); eq(#api.deletedRooms,0)
end)

test("post-create area metadata failures remain safely retryable",function()
  for _,failureCall in ipairs({2,3,4}) do
    local api=fakeMapApi(); local map=Adapter.new(api); local native=api.setAreaUserData; local calls=0
    api.setAreaUserData=function(...) calls=calls+1; if calls==failureCall then return nil,"area metadata rejected" end; return native(...) end
    local ok,e=map:ensureArea("Retry"); eq(ok,nil); eq(e,"area metadata rejected")
    local id=api.areas["Dragons Gate - Retry"]; assert(id); api.setAreaUserData=native
    assert(map:ensureArea("Retry")); eq(api.areaUser[id]["dghud.owner"],"DragonsGateHUD"); eq(api.areaUser[id]["dghud.state"],"ready")
  end
end)

test("rolls back a new area when its first ownership write fails across reload",function()
  local api=fakeMapApi(); local native=api.setAreaUserData; local calls=0
  api.setAreaUserData=function(...) calls=calls+1; if calls==1 then return nil,"area ownership rejected" end; return native(...) end
  local ok,e=Adapter.new(api):ensureArea("Restart"); eq(ok,nil); eq(e,"area ownership rejected")
  eq(api.areas["Dragons Gate - Restart"],nil); eq(#api.deletedAreas,1)
  api.setAreaUserData=native
  local area=assert(Adapter.new(api):ensureArea("Restart")); assert(area); eq(api.areaUser[area]["dghud.owner"],"DragonsGateHUD")
end)

test("rolls back a new room when its first ownership write fails across reload",function()
  local api=fakeMapApi(); local native=api.setRoomUserData; local calls=0
  api.setRoomUserData=function(...) calls=calls+1; if calls==1 then return nil,"room ownership rejected" end; return native(...) end
  local ok,e=Adapter.new(api):ensureRoom(descriptor(31,"Restart"),{}); eq(ok,nil); eq(e,"room ownership rejected")
  eq(api.rooms[31],nil); eq(api.deletedRooms[1],31)
  api.setRoomUserData=native
  assert(Adapter.new(api):ensureRoom(descriptor(31,"Restart"),{})); eq(api.rooms[31].user["dghud.owner"],"DragonsGateHUD")
end)

test("reports ownership and rollback failures together",function()
  local areaApi=fakeMapApi(); areaApi.fail.setAreaUserData=true; areaApi.fail.deleteArea=true
  local ok,e=Adapter.new(areaApi):ensureArea("Broken"); eq(ok,nil); assert(e:find("setAreaUserData rejected",1,true)); assert(e:find("rollback failed",1,true)); assert(e:find("deleteArea rejected",1,true))

  local roomApi=fakeMapApi(); assert(Adapter.new(roomApi):ensureArea("A")); roomApi.fail.setRoomUserData=true; roomApi.fail.deleteRoom=true
  ok,e=Adapter.new(roomApi):ensureRoom(descriptor(32,"A"),{}); eq(ok,nil); assert(e:find("setRoomUserData rejected",1,true)); assert(e:find("rollback failed",1,true)); assert(e:find("deleteRoom rejected",1,true))
end)

test("never deletes preexisting collisions or owned rooms on update failure",function()
  local personal={name="Personal",user={},exits={},stubs={}}; local api=fakeMapApi({[40]=personal})
  api.areas["Dragons Gate - Personal"]=9; api.areaUser[9]={}
  local map=Adapter.new(api); eq(map:ensureRoom(descriptor(40),{}),nil); eq(map:ensureArea("Personal"),nil)
  eq(#api.deletedRooms,0); eq(#api.deletedAreas,0); eq(api.rooms[40],personal); eq(api.areas["Dragons Gate - Personal"],9)

  local managed=fakeMapApi(); local managedMap=Adapter.new(managed); assert(managedMap:ensureRoom(descriptor(41),{}))
  managed.fail.setRoomName=true; eq(managedMap:ensureRoom(descriptor(41,"A","Changed"),{}),nil)
  eq(#managed.deletedRooms,0); eq(#managed.deletedAreas,0); assert(managed.rooms[41])

  local persistedArea=fakeMapApi(); assert(Adapter.new(persistedArea):ensureArea("Owned")); persistedArea.fail.setAreaUserData=true
  eq(Adapter.new(persistedArea):ensureArea("Owned"),nil); eq(#persistedArea.deletedAreas,0); assert(persistedArea.areas["Dragons Gate - Owned"])
end)

test("never adopts preexisting unowned provisional-looking objects",function()
  local api=fakeMapApi({[20]={user={['dghud.state']='provisional'},exits={},stubs={}}})
  api.areas["Dragons Gate - Personal"]=9; api.areaUser[9]={['dghud.state']='provisional'}
  local map=Adapter.new(api); local ok=map:ensureRoom(descriptor(20),{}); eq(ok,nil); ok=map:ensureArea("Personal"); eq(ok,nil)
end)

test("individual deletion accepts only a persisted HUD-owned room",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"A"),{x=0,y=0,z=0}))
  eq(map:deleteOwnedRoom(100),true); eq(api.rooms[100],nil); eq(api.deletedRooms[1],100)

  api.rooms[101]={area=9,user={},exits={},stubs={}}
  local ok,e=map:deleteOwnedRoom(101)
  eq(ok,nil); eq(e,"room 101 is not owned by DragonsGateHUD"); eq(api.rooms[101]~=nil,true); eq(#api.deletedRooms,1)
end)

test("legacy DGHUD areas tolerate Mudlet missing-key errors when every room is owned",function()
  local api=fakeMapApi({[100]={area=1,user={['dghud.owner']='DragonsGateHUD'},exits={},stubs={}}})
  api.areas['Dragons Gate - 1']=1; api.areaUser[1]={}
  local nativeGet=api.getAreaUserData
  function api.getAreaUserData(id,key) local value=nativeGet(id,key); if value~=nil then return value end; return nil,"no user data with key '"..key.."' in areaID "..id end
  local record=assert(Adapter.new(api):areaRecord(1)); eq(record.owned,true); eq(record.owner,'DragonsGateHUD'); eq(api.areaUser[1]['dghud.owner'],'DragonsGateHUD')
end)

test("legacy area ownership persists before its final room is deleted and survives restart",function()
  local api=fakeMapApi({[100]={area=1,user={['dghud.owner']='DragonsGateHUD'},exits={},stubs={}}})
  api.areas['Dragons Gate - 1']=1; api.areaUser[1]={}
  local nativeGet=api.getAreaUserData
  function api.getAreaUserData(id,key) local value=nativeGet(id,key); if value~=nil then return value end; return nil,"no user data with key '"..key.."' in areaID "..id end
  local map=Adapter.new(api); eq(map:deleteOwnedRoom(100),true); eq(api.areaUser[1]['dghud.owner'],'DragonsGateHUD')
  map=Adapter.new(api); eq(assert(map:areaRecord(1)).owned,true); eq(map:deleteEmptyOwnedArea(1),true)
  eq(api.areas['Dragons Gate - 1'],nil); eq(api.deletedAreas[1],1)
end)

test("map context reset drops every numeric-ID cache before another collection loads",function()
  local map=Adapter.new(fakeMapApi()); map.areas.old=7; map.createdAreas[7]=true; map.createdRooms[100]=true
  assert(map:resetMapContext()); eq(next(map.areas),nil); eq(next(map.createdAreas),nil); eq(next(map.createdRooms),nil)
end)

test("individual deletion rechecks persisted ownership immediately before mutation",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"A"),{x=0,y=0,z=0}))
  assert(map:roomRecord(100)); api.rooms[100].user["dghud.owner"]="PersonalMapper"
  local ok,e=map:deleteOwnedRoom(100)
  eq(ok,nil); eq(e,"room 100 is not owned by DragonsGateHUD"); eq(api.rooms[100]~=nil,true); eq(#api.deletedRooms,0)
end)

test("area inspection and membership use persisted state and normalized sorted IDs",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  local area=assert(map:ensureArea("Owned"))
  api.getAreaRooms1=function(id) eq(id,area); return {[0]=12,[1]=10,[2]=12,[3]=11} end
  local record=assert(map:areaRecord(area)); eq(record.id,area); eq(record.exists,true); eq(record.owned,true); eq(record.owner,"DragonsGateHUD")
  local rooms=assert(map:roomsInArea(area)); eq(#rooms,3); eq(rooms[1],10); eq(rooms[2],11); eq(rooms[3],12)

  local missing,e=map:areaRecord(999)
  eq(missing,nil); eq(e,"mapper area 999 does not exist")
end)

test("incremental room and inbound scans never process more than their limit",function()
  local api=fakeMapApi(); local map=Adapter.new(api); local owned=assert(map:ensureArea("Owned")); local personal=assert(map:ensureArea("Other"))
  api.areaUser[personal]["dghud.owner"]="Personal"
  for id=1,205 do api.rooms[id]={name="",area=owned,user={["dghud.owner"]="DragonsGateHUD"},exits={},stubs={}} end
  api.rooms[1000]={name="Personal",area=personal,user={},exits={n=1},stubs={}}
  local scan=assert(map:beginAreaRoomScan({owned})); local discovered={}; local calls=0
  while true do local batch,done=assert(map:scanAreaRoomBatch(scan,37)); calls=calls+1; assert(#batch<=37); for _,item in ipairs(batch) do discovered[item.id]=true end; if done then break end end
  eq(calls,6); eq(discovered[1],true); eq(discovered[205],true)
  local inbound=assert(map:beginInboundScan()); local deleting={}; for id=1,205 do deleting[id]=true end
  local seenError
  while true do local batch,done,err=map:scanInboundBatch(inbound,deleting,31); assert(batch==nil or #batch<=31); if not batch then seenError=err; break end; if done then break end end
  eq(seenError,"unowned room 1000 has an inbound exit")
end)

test("numeric room names never replace documented getRooms ID keys",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"A"),{x=0,y=0,z=0}))
  api.rooms[50]={name="100",area=9,user={},exits={n=100},stubs={}}
  local sources=assert(map:inboundSources({100}))
  eq(#sources,1); eq(sources[1],50)
  eq(api.rooms[50].exits.n,100); eq(api.rooms[100]~=nil,true); eq(#api.deletedRooms,0)
end)

test("malformed getRooms entries fail closed before exit inspection",function()
  local api=fakeMapApi(); api.getRooms=function() return {[50]="Personal",bad="Room 60"} end
  local sources,e=Adapter.new(api):inboundSources({100})
  eq(sources,nil); eq(e,"Mudlet mapper API getRooms returned invalid data")
end)

test("unowned ordinary and special inbound sources are reported without mutation",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"A"),{x=0,y=0,z=0})); assert(map:ensureRoom(descriptor(101,"A"),{x=1,y=0,z=0}))
  api.rooms[50]={name="Personal ordinary",area=9,user={},exits={n=100},stubs={}}
  api.rooms[40]={name="Personal special",area=9,user={},exits={},stubs={}}; api.special[40]={gate=101}
  api.rooms[100].exits.s=101; api.special[101]={back=100}
  local sources=assert(map:inboundSources({101,100,101}))
  eq(#sources,2); eq(sources[1],40); eq(sources[2],50)
  eq(api.rooms[50].exits.n,100); eq(api.special[40].gate,101); eq(api.rooms[100]~=nil,true); eq(api.rooms[101]~=nil,true)
end)

test("inbound inspection fails closed on every required mapper read",function()
  for _,name in ipairs({"getRooms","getRoomExits","getSpecialExits"}) do
    local api=fakeMapApi(); api.rooms[50]={name="Personal",area=9,user={},exits={n=100},stubs={}}; api.fail[name]=true
    local sources,e=Adapter.new(api):inboundSources({100})
    eq(sources,nil); eq(e,name.." rejected")
  end
end)

test("empty area deletion requires persisted ownership and current emptiness",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  api.areas["Personal"]=41; api.areaUser[41]={}; api.nextArea=42
  local ok,e=map:deleteEmptyOwnedArea(41)
  eq(ok,nil); eq(e,"mapper area 41 is not owned by DragonsGateHUD"); eq(api.areas["Personal"],41); eq(#api.deletedAreas,0)

  local owned=assert(map:ensureArea("Owned")); api.rooms[100]={area=owned,user={["dghud.owner"]="DragonsGateHUD"},exits={},stubs={}}
  ok,e=map:deleteEmptyOwnedArea(owned)
  eq(ok,nil); eq(e,"mapper area "..owned.." is not empty"); eq(api.areas["Dragons Gate - Owned"],owned); eq(#api.deletedAreas,0)
  api.rooms[100]=nil; eq(map:deleteEmptyOwnedArea(owned),true); eq(api.areas["Dragons Gate - Owned"],nil); eq(api.deletedAreas[1],owned)
end)

test("malformed area membership blocks deletion with zero mutation",function()
  local malformed={
    {[0]=0},
    {[0]=-1},
    {[0]=1.5},
    {[0]="12"},
    {extra=12},
    {[0]=12,[2]=13},
  }
  for _,membership in ipairs(malformed) do
    local api=fakeMapApi(); local map=Adapter.new(api); local area=assert(map:ensureArea("Owned"))
    api.getAreaRooms1=function() return membership end
    local ok,e=map:deleteEmptyOwnedArea(area)
    eq(ok,nil); eq(e,"Mudlet mapper API getAreaRooms1 returned invalid data")
    eq(api.areas["Dragons Gate - Owned"],area); eq(#api.deletedAreas,0)
  end
end)

test("deleted map objects are invalidated from adapter caches",function()
  local map=Adapter.new(fakeMapApi()); map.areas.A=7; map.areas.B=8; map.createdAreas[7]=true; map.createdRooms[100]=true; map.createdRooms[101]=true
  eq(map:invalidateDeleted({101,100},7),true)
  eq(map.areas.A,nil); eq(map.areas.B,8); eq(map.createdAreas[7],nil); eq(map.createdRooms[100],nil); eq(map.createdRooms[101],nil)
end)

test("creates stubs one-way and confirmed reverse links",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(1),{})); assert(map:ensureRoom(descriptor(2),{})); assert(map:ensureStub(1,"n"))
  assert(map:connect(1,2,"e",false)); eq(api.rooms[2].exits.w,nil); assert(map:connect(1,2,"n",true)); eq(api.rooms[2].exits.s,1)
end)

test("route validation requires exact persisted directional connectivity",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(1),{})); assert(map:ensureRoom(descriptor(2),{})); assert(map:ensureRoom(descriptor(3),{}))
  assert(map:connect(1,2,"n",false))
  local ok,command=map:validateRouteStep(1,2,"north"); eq(ok,true); eq(command,"n")
  ok,command=map:validateRouteStep(1,3,"north"); eq(ok,nil); eq(command,"standard exit is not persisted from 1 to 3")
  api.rooms[2].user["dghud.owner"]="Personal"
  ok,command=map:validateRouteStep(1,2,"north"); eq(ok,nil); eq(command,"route endpoints are not owned by DragonsGateHUD")
end)

test("reports stub forward and reverse failures",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(1),{})); assert(map:ensureRoom(descriptor(2),{}))
  api.fail.setExitStub=true; local ok,e=map:ensureStub(1,"n"); eq(ok,nil); eq(e,"setExitStub rejected")
  api.fail.setExitStub=nil; api.fail.setExit=true; ok,e=map:connect(1,2,"n",false); eq(ok,nil); eq(e,"setExit rejected")
  api.fail.setExit=nil; local native,count=api.setExit,0; api.setExit=function(...) count=count+1; if count==2 then return nil,"reverse rejected" end; return native(...) end
  ok,e=map:connect(1,2,"n",true); eq(ok,nil); eq(e,"reverse rejected")
end)

test("adds only an observed one-way special exit and is idempotent",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"1"),{},"1")); assert(map:ensureRoom(descriptor(900,"1"),{},"special:900"))
  assert(map:connectSpecial(100,900,"  GO Gate  ")); assert(Adapter.new(api):connectSpecial(100,900,"GO Gate"))
  eq(api.special[100]["GO Gate"],900); eq(api.special[900],nil); eq(api.specialAdds,1)
  eq(map:specialExitMatches(100,900,"GO Gate"),true)
  eq(map:specialExitMatches(100,900,"go gate"),false)
  eq(map:specialExitMatches(100,900,"leave gate"),false)
  eq(map:specialExitMatches(100,901,"go gate"),false)
end)

test("never replaces a different-destination special exit with the same command",function()
  for _,existing in ipairs({
    {destination=777,owner="PersonalMapper"},
    {destination=901,owner="DragonsGateHUD"},
  }) do
    local api=fakeMapApi(); local map=Adapter.new(api)
    assert(map:ensureRoom(descriptor(100,"1"),{},"1")); assert(map:ensureRoom(descriptor(900,"1"),{},"special:900"))
    api.rooms[existing.destination]={area=77,user={["dghud.owner"]=existing.owner},exits={},stubs={}}
    api.special[100]={["go gate"]=existing.destination}
    local ok,e=map:connectSpecial(100,900,"go gate")
    eq(ok,nil); eq(e,"special exit command already has a different destination")
    eq(api.special[100]["go gate"],existing.destination); eq(api.specialAdds,0)
  end
end)

test("an exact command and destination tuple remains idempotent",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"1"),{},"1")); assert(map:ensureRoom(descriptor(900,"1"),{},"special:900"))
  api.special[100]={["go gate"]=900}
  assert(map:connectSpecial(100,900,"go gate"))
  eq(api.special[100]["go gate"],900); eq(api.specialAdds,0)
end)

test("contains special-exit read and write failures without inventing an edge",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"1"),{},"1")); assert(map:ensureRoom(descriptor(900,"1"),{},"special:900"))
  api.fail.getSpecialExits=true; local ok,e=map:connectSpecial(100,900,"go gate")
  eq(ok,nil); eq(e,"getSpecialExits rejected"); eq(api.specialAdds,0)
  api.fail.getSpecialExits=nil; api.fail.addSpecialExit=true; ok,e=map:connectSpecial(100,900,"go gate")
  eq(ok,nil); eq(e,"addSpecialExit rejected"); eq(api.specialAdds,0); eq(next(api.special),nil)
end)

test("rejects invalid or unowned special-exit endpoints without mapper mutation",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"1"),{},"1")); assert(map:ensureRoom(descriptor(900,"1"),{},"special:900"))
  for _,values in ipairs({{0,900,"go gate"},{100,-1,"go gate"},{100,900,"   "}}) do
    local ok=map:connectSpecial(values[1],values[2],values[3]); eq(ok,nil)
  end
  api.rooms[900].user["dghud.owner"]="PersonalMapper"
  local ok,e=map:connectSpecial(100,900,"go gate")
  eq(ok,nil); eq(e,"special exit endpoints are not owned by DragonsGateHUD"); eq(api.specialAdds,0); eq(next(api.special),nil)
  api.rooms[900].user["dghud.owner"]="DragonsGateHUD"; api.rooms[100].user["dghud.owner"]="PersonalMapper"
  ok,e=map:connectSpecial(100,900,"go gate")
  eq(ok,nil); eq(e,"special exit endpoints are not owned by DragonsGateHUD"); eq(api.specialAdds,0); eq(next(api.special),nil)
end)

test("reads zero-indexed occupancy route and view",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(10,"7"),{x=3,y=4,z=1})); local p=assert(map:coordinates(10)); eq(p.x,3); eq(p.y,4); eq(p.z,1)
  local occupied=assert(map:roomsAt("7",3,4,1)); eq(occupied[0],10); api.path={rooms={10,11,20},commands={"n","e"}}; eq(assert(map:route(10,20)).commands[2],"e"); assert(map:setCurrent(10)); assert(map:center(10)); eq(api.refreshed,1)
end)

test("directional coordinate reservation expands an occupied half-plane",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(1,"A"),{x=0,y=0,z=0}))
  assert(map:ensureRoom(descriptor(2,"A"),{x=-1,y=0,z=0}))
  assert(map:ensureRoom(descriptor(3,"A"),{x=-2,y=0,z=0}))
  assert(map:ensureRoom(descriptor(4,"A"),{x=0,y=1,z=0}))
  local reserved,moved=assert(map:reserveDirectionalCoordinate("A",{x=-1,y=0,z=0},"west",1))
  eq(reserved.x,-1); eq(reserved.y,0); eq(moved,2)
  eq(api.rooms[1].x,0); eq(api.rooms[2].x,-2); eq(api.rooms[3].x,-3); eq(api.rooms[4].x,0)
end)

test("diagonal coordinate reservation shifts both outward axes",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(1,"A"),{x=0,y=0,z=0}))
  assert(map:ensureRoom(descriptor(2,"A"),{x=-1,y=-1,z=0}))
  assert(map:ensureRoom(descriptor(3,"A"),{x=-2,y=1,z=0}))
  assert(map:ensureRoom(descriptor(4,"A"),{x=1,y=-2,z=0}))
  local reserved,moved=assert(map:reserveDirectionalCoordinate("A",{x=-1,y=-1,z=0},"sw",1))
  eq(reserved.x,-1); eq(reserved.y,-1); eq(moved,3)
  eq(api.rooms[2].x,-2); eq(api.rooms[2].y,-2)
  eq(api.rooms[3].x,-3); eq(api.rooms[3].y,0)
  eq(api.rooms[4].x,0); eq(api.rooms[4].y,-3)
  eq(api.rooms[1].x,0); eq(api.rooms[1].y,0)
end)

test("directional coordinate reservation rolls back partial movement",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(1,"A"),{x=0,y=0,z=0}))
  assert(map:ensureRoom(descriptor(2,"A"),{x=-1,y=0,z=0}))
  assert(map:ensureRoom(descriptor(3,"A"),{x=-2,y=0,z=0}))
  local native=api.setRoomCoordinates; local calls=0
  api.setRoomCoordinates=function(...)
    calls=calls+1; if calls==2 then return nil,"move rejected" end
    return native(...)
  end
  local reserved,err=map:reserveDirectionalCoordinate("A",{x=-1,y=0,z=0},"w",1)
  eq(reserved,nil); eq(err,"move rejected"); eq(api.rooms[2].x,-1); eq(api.rooms[3].x,-2)
end)

test("visual zoom direction hides Mudlet numeric inversion and clamps per area",function()
  local api=fakeMapApi(); api.rooms[100]={area=7,user={["dghud.owner"]="DragonsGateHUD"}}; api.areaUser[7]={["dghud.owner"]="DragonsGateHUD"}; api.zoom[7]=20
  local map=Adapter.new(api)
  eq(map:currentZoom(100),20)
  eq(map:zoom(100,"larger",2.5,3,60),17.5); eq(api.zoom[7],17.5)
  eq(map:zoom(100,"smaller",2.5,3,60),20); eq(api.zoom[7],20)
  api.zoom[7]=3; eq(map:zoom(100,"larger",2.5,3,60),3)
end)

test("zoom enforces Mudlet's absolute minimum over a lower configured minimum",function()
  local api=fakeMapApi(); api.rooms[100]={area=7,user={["dghud.owner"]="DragonsGateHUD"}}; api.areaUser[7]={["dghud.owner"]="DragonsGateHUD"}; api.zoom[7]=4
  eq(Adapter.new(api):zoom(100,"larger",2.5,1,60),3)
  eq(api.zoom[7],3)
end)

test("zoom rejects a configured maximum below Mudlet's absolute minimum",function()
  local api=fakeMapApi(); api.rooms[100]={area=7,user={["dghud.owner"]="DragonsGateHUD"}}; api.areaUser[7]={["dghud.owner"]="DragonsGateHUD"}; api.zoom[7]=4
  local value,e=Adapter.new(api):zoom(100,"smaller",2.5,1,2.5)
  eq(value,nil); eq(e,"map zoom bounds are invalid"); eq(api.zoom[7],4)
end)

test("zoom rejects invalid ownership and preserves the previous value on API failures",function()
  local api=fakeMapApi(); api.rooms[100]={area=7,user={["dghud.owner"]="DragonsGateHUD"}}; api.areaUser[7]={["dghud.owner"]="DragonsGateHUD"}; api.zoom[7]=20
  local map=Adapter.new(api)
  api.rooms[100].user["dghud.owner"]="PersonalMapper"
  local value,e=map:currentZoom(100); eq(value,nil); eq(e,"room 100 is not owned by DragonsGateHUD")
  value,e=map:zoom(100,"larger",2.5,3,60); eq(value,nil); eq(e,"room 100 is not owned by DragonsGateHUD"); eq(api.zoom[7],20)
  api.rooms[100].user["dghud.owner"]="DragonsGateHUD"
  for _,name in ipairs({"getRoomArea","getMapZoom","setMapZoom"}) do
    api.fail[name]=true; value,e=map:zoom(100,"larger",2.5,3,60); eq(value,nil); eq(e,name.." rejected"); eq(api.zoom[7],20); api.fail[name]=nil
  end
  api.fail.updateMap=true; value,e=map:zoom(100,"larger",2.5,3,60); eq(value,nil); eq(e,"updateMap rejected"); eq(api.zoom[7],20)
end)

test("zoom refuses an unowned area even when the room is HUD owned",function()
  local api=fakeMapApi(); api.rooms[100]={area=7,user={["dghud.owner"]="DragonsGateHUD"}}; api.areaUser[7]={["dghud.owner"]="PersonalMapper"}; api.zoom[7]=20
  local map=Adapter.new(api)
  local value,e=map:currentZoom(100)
  eq(value,nil); eq(e,"mapper area 7 is not owned by DragonsGateHUD")
  value,e=map:zoom(100,"larger",2.5,3,60)
  eq(value,nil); eq(e,"mapper area 7 is not owned by DragonsGateHUD"); eq(api.zoom[7],20)
end)

test("reload resolves persisted owned area before checking occupied coordinates",function()
  local api=fakeMapApi(); local first=Adapter.new(api)
  assert(first:ensureRoom(descriptor(10,"Castle"),{x=0,y=1,z=0}))

  local reloaded=Adapter.new(api)
  local occupied=assert(reloaded:roomsAt("Castle",0,1,0))
  eq(occupied[0],10)
end)

test("occupancy reload rejects unowned areas and propagates area query failures",function()
  local collision=fakeMapApi(); collision.areas["Dragons Gate - Castle"]=41; collision.areaUser[41]={}
  local rooms,e=Adapter.new(collision):roomsAt("Castle",0,0,0)
  eq(rooms,nil); eq(e,"area Dragons Gate - Castle is not owned by DragonsGateHUD")

  local api=fakeMapApi(); assert(Adapter.new(api):ensureRoom(descriptor(10,"Castle"),{x=0,y=1,z=0}))
  api.fail.getRoomsByPosition=true
  rooms,e=Adapter.new(api):roomsAt("Castle",0,1,0)
  eq(rooms,nil); eq(e,"getRoomsByPosition rejected")
end)

test("contains mapper API exceptions",function()
  local api=fakeMapApi(); api.fail.getAreaTable="throw"; local ok,e=Adapter.new(api):ensureRoom(descriptor(1),{}); eq(ok,nil); assert(e:find("Mudlet mapper API getAreaTable failed",1,true))
end)

test("returns explicit errors for missing capabilities",function()
  local map=Adapter.new({roomExists=function() return false end}); local ok,e=map:ensureRoom(descriptor(1),{}); eq(ok,nil); eq(e,"Mudlet mapper API addRoom is unavailable")
  local route,routeError=map:route(1,2); eq(route,nil); eq(routeError,"Mudlet mapper API getPath is unavailable")
end)

test("production factory guards area APIs",function()
  local api=Adapter.mudletApi({}); local value,e=api.getAreaTable(); eq(value,nil); eq(e,"Mudlet mapper API getAreaTable is unavailable")
end)

test("production factory exposes private rollback wrappers",function()
  local deletedRoom,deletedArea
  local api=Adapter.mudletApi({deleteRoom=function(id) deletedRoom=id end,deleteArea=function(id) deletedArea=id end})
  assert(api.deleteRoom(51)); assert(api.deleteArea(6)); eq(deletedRoom,51); eq(deletedArea,6)
end)

test("production factory exposes guarded special-exit APIs",function()
  local added; local globals={}
  globals.addSpecialExit=function(from,to,command) added={from,to,command} end
  globals.getSpecialExits=function(from,listAll) return {[900]={["go gate"]="0"}},from,listAll end
  local api=Adapter.mudletApi(globals)
  assert(api.addSpecialExit(100,900,"go gate")); eq(added[1],100); eq(added[2],900); eq(added[3],"go gate")
  local exits,from,listAll=api.getSpecialExits(100,true); eq(exits[900]["go gate"],"0"); eq(from,100); eq(listAll,true)
end)

test("production factory exposes guarded cleanup inspection APIs",function()
  local globals={}
  globals.getAreaRooms1=function(area) return {[0]=100},area end
  globals.getRoomExits=function(room) return {n=101},room end
  local api=Adapter.mudletApi(globals)
  local rooms,area=api.getAreaRooms1(7); eq(rooms[0],100); eq(area,7)
  local exits,room=api.getRoomExits(100); eq(exits.n,101); eq(room,100)
  globals.getRoomExits=function() error("inspection exploded") end
  local value,e=api.getRoomExits(100); eq(value,nil); assert(e:find("Mudlet mapper API getRoomExits failed",1,true))
end)

test("production factory exposes guarded native zoom APIs",function()
  local zoom={[7]=20}; local globals={}
  globals.getMapZoom=function(area) return zoom[area] end
  globals.setMapZoom=function(value,area) zoom[area]=value end
  local api=Adapter.mudletApi(globals)
  eq(api.getMapZoom(7),20); assert(api.setMapZoom(17.5,7)); eq(zoom[7],17.5)
end)

test("production route atomically snapshots path and directions",function()
  local globals={speedWalkPath={99},speedWalkDir={"old"}}
  globals.getPath=function()
    globals.speedWalkPath={1,2,3}
    globals.speedWalkDir={"north","east"}
    return true
  end
  local route=assert(Adapter.new(Adapter.mudletApi(globals)):route(1,3))
  eq(route.rooms[1],1); eq(route.rooms[2],2); eq(route.rooms[3],3)
  eq(route.commands[1],"north"); eq(route.commands[2],"east")
  globals.speedWalkPath[2]=88
  globals.speedWalkDir[1]="changed"
  eq(route.rooms[2],2); eq(route.commands[1],"north")
end)

test("production route requires both Mudlet route globals",function()
  local globals={speedWalkDir={"north"},getPath=function() return true end}
  local route,err=Adapter.new(Adapter.mudletApi(globals)):route(1,2)
  eq(route,nil); eq(err,"Mudlet mapper API getPath did not provide speedWalkPath")

  globals.speedWalkPath={1,2}; globals.speedWalkDir=nil
  route,err=Adapter.new(Adapter.mudletApi(globals)):route(1,2)
  eq(route,nil); eq(err,"Mudlet mapper API getPath did not provide speedWalkDir")
end)

local function lineFixture()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(1,"A"),{x=0,y=0,z=0},"A"))
  assert(map:ensureRoom(descriptor(2,"A"),{x=2,y=0,z=0},"A"))
  assert(map:connectSpecial(1,2,"go door"))
  return api,map
end

local function lineMetadataKey(command)
  return "dghud.special_line."..command:gsub(".",function(c) return string.format("%02x",string.byte(c)) end)
end

local function forbidGraphWrites(api)
  for _,name in ipairs({"addRoom","deleteRoom","addAreaName","deleteArea","setRoomArea","setRoomCoordinates","setRoomName","setExit","setExitStub","addSpecialExit","removeSpecialExit","removeCustomLine"}) do
    api[name]=function() error("renderer attempted "..name) end
  end
  local native=api.setRoomUserData
  api.setRoomUserData=function(id,key,value) assert(key:find("dghud.special_line.",1,true)==1); return native(id,key,value) end
  api.getRooms=function() error("renderer attempted whole-map enumeration") end
end

test("TG-shaped sparse exits draw seven dots for twelve saved links without graph writes",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  local edges={{38,174,"go door"},{174,38,"go door"},{173,178,"go arch"},{178,173,"go arch"},{173,6190,"go door"},{6190,173,"go door"},{216,8422,"go gate"},{8370,215,"go path"},{9441,9443,"go gate"},{9443,9441,"go gate"},{10543,10556,"go gate"},{10556,10543,"go gate"}}
  local ids={}; for _,edge in ipairs(edges) do ids[edge[1]]=true; ids[edge[2]]=true end
  local count=0
  for id in pairs(ids) do count=count+1; assert(map:ensureRoom(descriptor(id,"A"),{x=count,y=0,z=0},"A")) end
  for index=count+1,158 do assert(map:ensureRoom(descriptor(20000+index,"A"),{x=index,y=0,z=0},"A")) end
  for _,edge in ipairs(edges) do assert(map:connectSpecial(edge[1],edge[2],edge[3])) end
  local before=copy(api.rooms); forbidGraphWrites(api)
  local stats=map:syncSpecialExitLines(38)
  eq(stats.scanned,158); eq(stats.special_edges,12); eq(stats.created,7); eq(stats.updated,0); eq(#stats.errors,0); eq(stats.noop,false)
  eq(api.customAdds,7); eq(api.specialAdds,12)
  for _,edge in ipairs(edges) do eq(api.special[edge[1]][edge[3]],edge[2]) end
  for id,room in pairs(api.rooms) do for _,key in ipairs({"area","x","y","z","name"}) do eq(room[key],before[id][key]) end end
  for _,line in ipairs(api.customWrites) do eq(line.style,"dot line"); eq(line.arrow,false); eq(table.concat(line.color,","),"80,180,190") end
  stats=Adapter.new(api):syncSpecialExitLines(38)
  eq(stats.created,0); eq(stats.updated,0); eq(stats.unchanged,7); eq(stats.noop,true); eq(api.customAdds,7); eq(#stats.errors,0)
end)

test("special-line representative survives reverse and alternate commands after reload",function()
  local api,map=lineFixture(); assert(map:connectSpecial(2,1,"GO Door"))
  eq(map:syncSpecialExitLines(1).created,1)
  assert(map:connectSpecial(1,2,"climb rope"))
  local stats=Adapter.new(api):syncSpecialExitLines(2)
  eq(stats.unchanged,1); eq(api.customAdds,1); assert(api.custom[1]["go door"]); eq(api.custom[1]["climb rope"],nil); eq(api.custom[2],nil)
end)

test("renderer treats confirmed travel commands as exact opaque keys",function()
  for _,command in ipairs({"GO Shop","go pawn","go hole","go tav","go exit","climb Rope","enter  portal","cross $bridge"}) do
    local api,map=lineFixture(); api.special[1]={}; assert(map:connectSpecial(1,2,command))
    forbidGraphWrites(api)
    local stats=map:syncSpecialExitLines(1)
    eq(stats.created,1); eq(#stats.errors,0); assert(api.custom[1][command]); eq(api.customWrites[1].command,command)
  end
end)

test("manual lines including identical dots on either exit protect the pair",function()
  for _,source in ipairs({1,2}) do
    local api,map=lineFixture(); assert(map:connectSpecial(2,1,"leave gate"))
    local command=source==1 and "go door" or "leave gate"; local target=source==1 and 2 or 1
    assert(api.addCustomLine(source,target,command,"solid line",{1,2,3},true))
    local original=api.custom[source][command]; local stats=map:syncSpecialExitLines(1)
    eq(stats.preserved,1); eq(stats.created,0); eq(api.custom[source][command],original); eq(api.rooms[source].user[lineMetadataKey(command)],nil)
  end
  local api,map=lineFixture(); assert(api.addCustomLine(1,2,"go door","dot line",{80,180,190},false))
  eq(map:syncSpecialExitLines(1).preserved,1); eq(api.rooms[1].user[lineMetadataKey("go door")],nil)
end)

test("manual geometry style color arrow and extra points release generated ownership",function()
  local changes={
    function(line) line.points[0].x=44 end,
    function(line) line.attributes.style="solid line" end,
    function(line) line.attributes.color.r=255 end,
    function(line) line.attributes.arrow=true end,
    function(line) line.points[1]={x=2,y=9} end,
  }
  for _,change in ipairs(changes) do
    local api,map=lineFixture(); eq(map:syncSpecialExitLines(1).created,1)
    change(api.custom[1]["go door"]); local original=api.custom[1]["go door"]
    local stats=Adapter.new(api):syncSpecialExitLines(1)
    eq(stats.preserved,1); eq(stats.updated,0); eq(api.custom[1]["go door"],original)
    eq(api.rooms[1].user[lineMetadataKey("go door")],"1|suppressed|2")
    api.custom[1]["go door"]=nil
    stats=Adapter.new(api):syncSpecialExitLines(1); eq(stats.created,0); eq(stats.preserved,1)
  end
end)

test("manual deletion stays suppressed even after a reverse exit is added",function()
  local api,map=lineFixture(); eq(map:syncSpecialExitLines(1).created,1)
  api.custom[1]["go door"]=nil
  eq(Adapter.new(api):syncSpecialExitLines(1).preserved,1)
  assert(map:connectSpecial(2,1,"go gate"))
  local stats=Adapter.new(api):syncSpecialExitLines(2)
  eq(stats.created,0); eq(stats.preserved,1); eq(api.customAdds,1); eq(api.custom[2],nil)
end)

test("unknown malformed and different-destination ownership records are protected",function()
  for _,value in ipairs({"2|active|2|2|0|80|180|190","bad","1|active|3|2|0|80|180|190",string.rep("x",300)}) do
    local api,map=lineFixture(); api.rooms[1].user[lineMetadataKey("go door")]=value
    local stats=map:syncSpecialExitLines(1)
    eq(stats.preserved,1); eq(stats.created,0); eq(api.rooms[1].user[lineMetadataKey("go door")],value)
  end
end)

test("unchanged managed endpoints update from saved room coordinates without reflow",function()
  local api,map=lineFixture(); eq(map:syncSpecialExitLines(1).created,1)
  api.rooms[2].x=7; api.rooms[2].y=3; forbidGraphWrites(api)
  local stats=Adapter.new(api):syncSpecialExitLines(1)
  eq(stats.updated,1); eq(stats.created,0); eq(api.custom[1]["go door"].points[0].x,7); eq(api.custom[1]["go door"].points[0].y,3)
  eq(api.rooms[1].x,0); eq(api.rooms[1].y,0); eq(api.rooms[2].x,7); eq(api.rooms[2].y,3)
  eq(Adapter.new(api):syncSpecialExitLines(1).unchanged,1)
  stats=map:syncSpecialExitLines(1,{color={5,6,7}}); eq(stats.updated,1); eq(api.custom[1]["go door"].attributes.color.r,5)
end)

test("renderer completes every preflight read before any mutation",function()
  local api,map=lineFixture(); assert(map:ensureRoom(descriptor(3,"A"),{x=3,y=0,z=0},"A"))
  local native=api.getCustomLines
  api.getCustomLines=function(id) if id==3 then return nil,"late inspection failure" end; return native(id) end
  local writes=0; api.setRoomUserData=function() writes=writes+1; return true end
  local stats=map:syncSpecialExitLines(1)
  eq(stats.created,0); eq(api.customAdds,0); eq(writes,0); eq(stats.errors[1],"late inspection failure")
end)

test("room and aggregate edge caps preflight without partial drawings",function()
  local api,map=lineFixture()
  for id=3,1001 do api.rooms[id]=copy(api.rooms[2]); api.rooms[id].x=id end
  local stats=map:syncSpecialExitLines(1,{max_rooms=5000})
  eq(stats.limited,true); eq(api.customAdds,0); eq(stats.scanned,0)
  api,map=lineFixture(); stats=map:syncSpecialExitLines(1,{max_rooms=1})
  eq(stats.limited,true); eq(api.customAdds,0)
  api,map=lineFixture(); api.special[1]={}; api.special[2]={}
  for index=1,2050 do api.special[1]["go a"..index]=2; api.special[2]["go b"..index]=1 end
  stats=map:syncSpecialExitLines(1,{max_edges=9999}); eq(stats.limited,true); eq(api.customAdds,0)
  api,map=lineFixture(); api.special[1]["go gate"]=2
  stats=map:syncSpecialExitLines(1,{max_edges=1}); eq(stats.limited,true); eq(api.customAdds,0)
end)

test("missing native and injected capabilities degrade to harmless stats",function()
  for _,name in ipairs({"roomExists","getRoomArea","getAreaRooms1","getRoomCoordinates","getRoomUserData","setRoomUserData","getSpecialExits","getCustomLines","addCustomLine"}) do
    local api,map=lineFixture(); api[name]=nil
    local stats=map:syncSpecialExitLines(1)
    eq(stats.noop,true); eq(stats.unavailable,name); eq(stats.skipped,1); eq(#stats.errors,0); eq(api.customAdds,0)
  end
  local stats=Adapter.new(Adapter.mudletApi({})):syncSpecialExitLines(1)
  eq(stats.noop,true); eq(stats.skipped,1); eq(#stats.errors,0)
  local api,map=lineFixture(); api.updateMap=nil; eq(map:syncSpecialExitLines(1).created,1)
end)

test("special-line metadata inspection is linear in edges and respects remaining budget",function()
  local api,map=lineFixture()
  for id=3,12 do assert(map:ensureRoom(descriptor(id,"A"),{x=id,y=0,z=0},"A")); assert(map:connectSpecial(1,id,"go gate"..id)) end
  local native=api.getRoomUserData; local metadataReads=0
  api.getRoomUserData=function(id,key)
    if key:find("dghud.special_line.",1,true)==1 then metadataReads=metadataReads+1 end
    return native(id,key)
  end
  local stats=map:syncSpecialExitLines(1)
  eq(stats.created,11); eq(metadataReads,22)
  api,map=lineFixture(); api.special[2]={["go back"]=1,["go portal"]=1}; native=api.getRoomUserData; metadataReads=0
  api.getRoomUserData=function(id,key) if key:find("dghud.special_line.",1,true)==1 then metadataReads=metadataReads+1 end; return native(id,key) end
  stats=map:syncSpecialExitLines(1,{max_edges=2})
  eq(stats.limited,true); eq(metadataReads,2); eq(api.customAdds,0)
end)

test("changed endpoint ownership or graph after preflight prevents drawing",function()
  for _,change in ipairs({function(api) api.rooms[2].user["dghud.owner"]="Personal" end,function(api) api.special[1]["go door"]=3 end}) do
    local api,map=lineFixture(); local native=api.getCustomLines; local reads=0
    api.getCustomLines=function(id) if id==1 then reads=reads+1; if reads==2 then change(api) end end; return native(id) end
    local stats=map:syncSpecialExitLines(1)
    eq(stats.created,0); eq(stats.skipped,1); eq(#stats.errors,1); eq(api.customAdds,0)
  end
end)

test("drawing exceptions and nil or false failures never affect the graph",function()
  for _,failure in ipairs({true,"throw","false","nil"}) do
    local api,map=lineFixture()
    if failure=="false" then api.addCustomLine=function() return false end
    elseif failure=="nil" then api.addCustomLine=function() return nil end
    else api.fail.addCustomLine=failure end
    local stats=map:syncSpecialExitLines(1)
    eq(stats.created,0); eq(#stats.errors,1); eq(api.special[1]["go door"],2); eq(api.specialAdds,1); eq(api.rooms[1].user[lineMetadataKey("go door")],nil)
  end
end)

test("failed metadata and readback leave new lines unclaimed and preserved",function()
  for _,failure in ipairs({"metadata","readback"}) do
    local api,map=lineFixture(); local native=api.getCustomLines
    if failure=="metadata" then api.fail.setRoomUserData=true
    else api.getCustomLines=function(id) if api.customAdds>0 then return nil,"readback failed" end; return native(id) end end
    local stats=map:syncSpecialExitLines(1)
    eq(stats.created,1); eq(#stats.errors,1); eq(api.rooms[1].user[lineMetadataKey("go door")],nil)
    api.fail.setRoomUserData=nil; api.getCustomLines=native
    stats=Adapter.new(api):syncSpecialExitLines(1)
    eq(stats.preserved,1); eq(stats.created,0); eq(stats.updated,0); eq(api.customAdds,1)
  end
end)

test("manual lines appearing after preflight are preserved",function()
  local api,map=lineFixture(); local native=api.getCustomLines; local reads=0
  api.getCustomLines=function(id)
    if id==1 then reads=reads+1; if reads==2 then assert(api.addCustomLine(1,2,"go door","solid line",{3,4,5},true)) end end
    return native(id)
  end
  local stats=map:syncSpecialExitLines(1)
  eq(stats.created,0); eq(stats.preserved,1); eq(api.custom[1]["go door"].attributes.style,"solid line")
end)

test("unsafe geometry ownership and reserved command slots are skipped",function()
  for _,change in ipairs({
    function(api) api.rooms[2].area=99 end,
    function(api) api.rooms[2].z=1 end,
    function(api) api.rooms[2].x=0 end,
    function(api) api.rooms[2].x=0/0 end,
    function(api) api.rooms[2].user["dghud.owner"]="Personal" end,
    function(api) api.rooms[2].user["dghud.state"]="provisional" end,
    function(api) api.rooms[2].user["dghud.library_readonly"]="true" end,
    function(api) api.rooms[2]=nil end,
  }) do
    local api,map=lineFixture(); change(api)
    local stats=map:syncSpecialExitLines(1); eq(stats.created,0); eq(api.customAdds,0); eq(stats.noop,true)
  end
  for _,command in ipairs({"north","N","north-east","i","o","1","go\ngate",string.rep("x",161)}) do
    local api,map=lineFixture(); api.special[1]={[command]=2}
    eq(map:syncSpecialExitLines(1).created,0); eq(api.customAdds,0)
  end
  local api,map=lineFixture(); eq(map:syncSpecialExitLines(1,{read_only=true}).created,0)
end)

test("malformed inspection and options return errors without writes",function()
  local api,map=lineFixture()
  for _,options in ipairs({false,"bad",{color={1,2}},{color={1,2,256}},{max_rooms=0},{max_edges=-1}}) do
    local stats=map:syncSpecialExitLines(1,options); eq(#stats.errors,1); eq(api.customAdds,0)
  end
  api.getSpecialExits=function() return {[2]={["go door"]="0"},[3]={["go door"]="0"}} end
  local stats=map:syncSpecialExitLines(1); eq(#stats.errors,1); eq(api.customAdds,0)
end)

test("custom-line wrappers preserve shapes and native capability checks",function()
  local called; local line={attributes={style="dot line",color={r=80,g=180,b=190},arrow=false},points={[0]={x=9,y=2}}}
  local globals={getCustomLines=function() return {["go Door"]=copy(line)} end,addCustomLine=function(...) called={...}; return true end}
  local api=Adapter.mudletApi(globals)
  eq(api.hasCapability("addCustomLine"),true); eq(api.hasCapability("removeCustomLine"),false)
  assert(api.addCustomLine(1,2,"go Door","dot line",{80,180,190},false)); eq(called[3],"go Door"); eq(called[6],false)
  eq(api.getCustomLines(1)["go Door"].points[0].x,9)
  globals.addCustomLine=function() return nil,"rejected" end
  local ok,err=api.addCustomLine(1,2,"go Door","dot line",{80,180,190},false); eq(ok,nil); eq(err,"rejected")
end)

test("ordinary exits normalize native long keys for snapshots and route checks",function()
  local api,map=lineFixture()
  local directions={north="n",northeast="ne",east="e",southeast="se",south="s",southwest="sw",west="w",northwest="nw",up="up",down="down",["in"]="in",out="out"}
  for long,short in pairs(directions) do
    api.rooms[1].exits={[long]=2}
    local ok,command=map:validateRouteStep(1,2,short); eq(ok,true); eq(command,short)
    eq(assert(map:getRoom(1)).exits[1].direction,short)
  end
  local wrapped=Adapter.mudletApi({getRoomExits=function() return {north=2,n=2,east=3},17 end})
  local exits,context=wrapped.getRoomExits(1); eq(exits.n,2); eq(exits.e,3); eq(exits.north,nil); eq(context,17)
end)

test("putRoom reconciles normalized keys and preflights alias conflicts",function()
  local api,map=lineFixture(); api.rooms[1].exits={n=2,e=2}
  local native=api.getRoomExits
  api.getRoomExits=function(id) local exits=native(id); return {north=exits.n,east=exits.e} end
  local room=assert(map:getRoom(1)); room.exits={{direction="north",to=2},{direction="n",to=2}}
  assert(map:putRoom(room)); eq(api.rooms[1].exits.n,2); eq(api.rooms[1].exits.e,nil)
  local writes=0; api.setRoomUserData=function() writes=writes+1; return true end
  api.getRoomExits=function() return {north=2,n=3} end
  local ok,err=map:putRoom(room); eq(ok,nil); assert(err:find("conflicting",1,true)); eq(writes,0)
  ok,err=map:validateRouteStep(1,2,"n"); eq(ok,nil); assert(err:find("conflicting",1,true))
  eq(map:getRoom(1),nil)
  api.getRoomExits=native; room.exits={{direction="north",to=2},{direction="n",to=3}}
  ok,err=map:putRoom(room); eq(ok,nil); assert(err:find("conflicting",1,true)); eq(writes,0)
end)
