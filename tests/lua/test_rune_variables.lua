local Runes=require("rune_variables")
test("rune variables replace fresh counts and remove retired runes without deleting user globals",function()
  local namespace={}; local userFunction=function() end; local env={light=userFunction,custom=17}
  local vars=Runes.new(namespace,env)
  assert(vars:save({{name="Disruption",remaining=3},{name="Light",remaining=100},{name="Life Force",remaining=19}}))
  eq(namespace.runes.disruption,3); eq(env.disruption,3); eq(env.life_force,19)
  eq(namespace.runes.remaining.disruption,3); eq(namespace.runes.by_name["life force"].remaining,19); eq(#namespace.runes.items,3)
  eq(namespace.runes.light,100); eq(env.light,userFunction); eq(env.custom,17)
  local retained=namespace.runes
  vars:clear(); eq(namespace.runes,retained); eq(next(namespace.runes.values),nil); eq(namespace.runes.disruption,nil); eq(env.disruption,nil); eq(env.life_force,nil); eq(env.light,userFunction)
  assert(vars:save({{name="Disruption",remaining=43}})); eq(env.disruption,43); eq(env.life_force,nil)
  env.disruption="user edit"; vars:clear(); eq(env.disruption,"user edit"); eq(env.custom,17)
end)
test("rune variables allow zero and reject malformed data before publishing",function()
  local root={}; local env={}; local vars=Runes.new(root,env)
  assert(vars:save({{name="Force",remaining=0}})); eq(env.force,0)
  for _,items in ipairs({
    {{name="Force",remaining=-1}},{{name="Force",remaining=.5}},{{name="Force",remaining=math.huge}},
    {{name="Force",remaining="3"}},{{name="force; quit",remaining=3}},{{name="",remaining=3}},
    {{name="Force",remaining=3},{name="FORCE",remaining=4}},
  }) do eq(vars:save(items),nil); eq(root.runes.force,0); eq(env.force,0) end
  assert(vars:save({})); eq(env.force,nil); eq(next(root.runes.values),nil)
end)
test("rune snapshot normalizes names and deduplicates without mutating its input",function()
  local source={{name="  Life   Force  ",remaining=0},{name="LIFE FORCE",remaining=0},{name="Healing",remaining=19}}
  local rows,err,values=Runes.snapshot(source)
  eq(err,nil); eq(#rows,2); eq(rows[1].name,"Life Force"); eq(rows[1].remaining,0)
  eq(rows[2].name,"Healing"); eq(values.life_force,0); eq(values.healing,19)
  rows[1].remaining=999; eq(source[1].remaining,0); eq(source[1].name,"  Life   Force  ")
  local root={}; local env={}; local vars=Runes.new(root,env)
  assert(vars:save(source)); eq(env.life_force,0); eq(root.runes.by_name["life force"].remaining,0)
  eq(root.runes.items[1].name,"Life Force"); eq(root.runes.remaining["life force"],0)
end)
test("incomplete or decorated rune arrays reject before clearing confirmed variables",function()
  local root={}; local env={}; local vars=Runes.new(root,env)
  assert(vars:save({{name="Force",remaining=97}}))
  local item={name="Healing",remaining=14}
  for _,items in ipairs({{[2]=item},{[1]=item,[3]=item},{[0]=item},{[-1]=item},{[1.5]=item},
      {[257]=item},{[1]=item,extra=item},setmetatable({item},{}),
      {setmetatable({}, {__index=function() error("must not read untrusted metamethod") end})}}) do
    local rows,err=Runes.snapshot(items); eq(rows,nil); eq(type(err),"string")
    eq(vars:save(items),nil); eq(root.runes.values.force,97); eq(env.force,97)
    eq(root.runes.remaining.force,97); eq(env.healing,nil)
  end
  vars:clear()
end)
test("rune snapshots accept the bounded complete list and reject one extra row",function()
  local items={}
  for index=1,256 do
    items[index]={name="Rune "..string.char(97+math.floor((index-1)/26))..string.char(97+(index-1)%26),remaining=index}
  end
  local rows,err=Runes.snapshot(items); eq(err,nil); eq(#rows,256)
  items[257]={name="Overflow",remaining=0}
  eq(Runes.snapshot(items),nil)
  rows,err=Runes.snapshot({}); eq(err,nil); eq(#rows,0)
end)
