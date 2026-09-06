local Model=require("mapper_model")

test("normalizes a Dragons Gate room",function()
  local info={num=176,name="Training square.",area=1,environment="Plains/Grasslands",exits={"northeast","UP","unknown"},flags={"indoor"}}
  local room=assert(Model.normalizeRoom(info))
  eq(room.id,176); eq(room.name,"Training square."); eq(room.area_key,"1"); eq(room.environment,"Plains/Grasslands")
  eq(#room.exits,2); eq(room.exits[1],"ne"); eq(room.exits[2],"up"); eq(room.flags[1],"indoor")
  info.exits[1]="south"; info.flags[1]="outdoor"
  eq(room.exits[1],"ne"); eq(room.flags[1],"indoor")
end)

test("maps every canonical direction alias vector and opposite",function()
  local cases={
    {"north","n",0,1,0,"s"},
    {"northeast","ne",1,1,0,"sw"},
    {"east","e",1,0,0,"w"},
    {"southeast","se",1,-1,0,"nw"},
    {"south","s",0,-1,0,"n"},
    {"southwest","sw",-1,-1,0,"ne"},
    {"west","w",-1,0,0,"e"},
    {"northwest","nw",-1,1,0,"se"},
    {"up","u",0,0,1,"down"},
    {"down","d",0,0,-1,"up"},
    {"in","in",0,0,0,"out"},
    {"out","out",0,0,0,"in"},
  }
  for _,case in ipairs(cases) do
    local full,abbreviation,dx,dy,dz,opposite=case[1],case[2],case[3],case[4],case[5],case[6]
    local canonical=Model.direction(full)
    eq(canonical,Model.direction(abbreviation:upper()))
    eq(Model.opposite(full),opposite)
    eq(Model.opposite(Model.opposite(full)),canonical)
    local point=Model.destination({x=4,y=7,z=2},abbreviation)
    eq(point.x,4+dx); eq(point.y,7+dy); eq(point.z,2+dz)
  end
  eq(Model.direction("sideways"),nil)
  eq(Model.destination({x=4,y=7,z=0},"sideways"),nil)
  eq(Model.direction("swim north"),"n"); eq(Model.direction("  SWIM southwest  "),"sw")
end)

test("rejects rooms without positive numeric IDs",function()
  local room,err=Model.normalizeRoom({name="Unknown"}); eq(room,nil); eq(type(err),"string")
  eq(Model.normalizeRoom({num=0}),nil); eq(Model.normalizeRoom({num=-1}),nil); eq(Model.normalizeRoom({num="176"}),nil)
  eq(Model.normalizeRoom({num=0/0}),nil); eq(Model.normalizeRoom({num=math.huge}),nil)
  eq(Model.normalizeRoom({num=-math.huge}),nil); eq(Model.normalizeRoom({num=176.5}),nil)
end)

test("finds the nearest free coordinate deterministically",function()
  local occupied={ ["0:0:0"]=true,["-1:-1:0"]=true,["0:-1:0"]=true }
  local point=Model.nearestFree({x=0,y=0,z=0},function(x,y,z) return occupied[x..":"..y..":"..z] end)
  eq(point.x,1); eq(point.y,-1); eq(point.z,0)
  local desired=Model.nearestFree({x=3,y=2,z=1},function() return false end)
  eq(desired.x,3); eq(desired.y,2); eq(desired.z,1)
end)
