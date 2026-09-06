local Model={}

local aliases={
  north="n",n="n",northeast="ne",ne="ne",east="e",e="e",
  southeast="se",se="se",south="s",s="s",southwest="sw",sw="sw",
  west="w",w="w",northwest="nw",nw="nw",up="up",u="up",
  down="down",d="down",["in"]="in",out="out",
}
local opposites={n="s",ne="sw",e="w",se="nw",s="n",sw="ne",w="e",nw="se",up="down",down="up",["in"]="out",out="in"}
local vectors={
  n={0,1,0},ne={1,1,0},e={1,0,0},se={1,-1,0},
  s={0,-1,0},sw={-1,-1,0},w={-1,0,0},nw={-1,1,0},
  up={0,0,1},down={0,0,-1},["in"]={0,0,0},out={0,0,0},
}

function Model.direction(value)
  local command=tostring(value or ""):lower():match("^%s*(.-)%s*$")
  command=command:match("^swim%s+(.+)$") or command
  return aliases[command]
end

function Model.opposite(value)
  return opposites[Model.direction(value)]
end

function Model.destination(origin,direction)
  local vector=vectors[Model.direction(direction)]
  if not vector then return nil end
  origin=origin or {}
  return {x=(origin.x or 0)+vector[1],y=(origin.y or 0)+vector[2],z=(origin.z or 0)+vector[3]}
end

function Model.normalizeRoom(info)
  local id=type(info)=="table" and info.num or nil
  if type(id)~="number" or id~=id or id==math.huge or id==-math.huge or id<=0 or id%1~=0 then
    return nil,"room requires a positive numeric ID"
  end
  local exits={}
  for _,value in ipairs(type(info.exits)=="table" and info.exits or {}) do
    local direction=Model.direction(value)
    if direction then exits[#exits+1]=direction end
  end
  local flags={}
  for _,value in ipairs(type(info.flags)=="table" and info.flags or {}) do flags[#flags+1]=value end
  return {
    id=info.num,
    name=tostring(info.name or ""),
    area_key=tostring(info.area or ""),
    environment=tostring(info.environment or ""),
    exits=exits,
    flags=flags,
  }
end

function Model.nearestFree(desired,isOccupied)
  local x,y,z=desired.x or 0,desired.y or 0,desired.z or 0
  if not isOccupied(x,y,z) then return {x=x,y=y,z=z} end
  local radius=1
  while true do
    for dy=-radius,radius do
      for dx=-radius,radius do
        if math.abs(dx)==radius or math.abs(dy)==radius then
          if not isOccupied(x+dx,y+dy,z) then return {x=x+dx,y=y+dy,z=z} end
        end
      end
    end
    radius=radius+1
  end
end

return Model
