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
