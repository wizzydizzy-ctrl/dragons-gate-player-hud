local Collections=require("map_collections")
local digest=string.rep("a",64)
local nextID=0
local function manager(state)
  return assert(Collections.new(state,{clock=function() return 100+nextID end,id_factory=function() nextID=nextID+1; return "collection-"..nextID end}))
end

test("map collections create named local collections and return defensive copies",function()
  nextID=0; local maps=manager(); local created=assert(maps:create("My Map")); eq(created.id,"collection-1"); eq(created.source.kind,"local_map"); eq(created.editable,true)
  created.name="changed"; eq(maps:get("collection-1").name,"My Map"); eq(#maps:list(),1)
end)

test("map collections maintain one valid active selection",function()
  nextID=0; local maps=manager(); local one=assert(maps:create("One")); local two=assert(maps:create("Two"))
  assert(maps:setActive(two.id)); eq(maps:active().name,"Two"); eq(maps:setActive("missing"),nil); eq(maps:active().id,two.id)
  assert(maps:setActive(nil)); eq(maps:active(),nil); eq(maps:exportState().active_collection_id,nil)
end)

test("library source identity is immutable and retained by editable forks",function()
  nextID=0; local maps=manager(); local source={kind="library",artifact_id="sha256:original",publisher="gia-afari",slug="spur"}
  local original=assert(maps:create("Gia's Map",source,false)); eq(maps:updateSnapshot(original.id,{path="x",sha256=digest,room_count=1,bytes=2}),nil)
  local fork=assert(maps:fork(original.id,"My Gia Fork")); eq(fork.editable,true); eq(fork.forked_from,original.id); eq(fork.source.artifact_id,"sha256:original")
  source.artifact_id="changed"; eq(maps:get(original.id).source.artifact_id,"sha256:original"); eq(maps:get(fork.id).source.publisher,"gia-afari")
end)

test("snapshot and backup metadata are validated and copied",function()
  nextID=0; local maps=manager(); local item=assert(maps:create("Working"))
  local snapshot={path="collections/one/map.json",sha256=digest,room_count=83,bytes=4096}; assert(maps:updateSnapshot(item.id,snapshot))
  local backup={path="collections/one/backups/100.json",sha256=digest,room_count=83,bytes=4100,created_at=120}; assert(maps:recordBackup(item.id,backup))
  snapshot.path="changed"; backup.room_count=0; local saved=maps:get(item.id); eq(saved.snapshot.path,"collections/one/map.json"); eq(saved.backup.room_count,83)
end)

test("state validation rejects malformed identities metadata and active references",function()
  eq(Collections.validate({schema=2,collections={}}),nil)
  eq(Collections.validate({schema=1,collections={},active_collection_id="missing"}),nil)
  eq(Collections.validate({schema=1,collections={{id="bad id",name="Map",created_at=1,updated_at=1,editable=true,source={kind="local_map"}}}}),nil)
  eq(Collections.validate({schema=1,collections={{id="one",name="Map",created_at=2,updated_at=1,editable=true,source={kind="local_map"}}}}),nil)
  eq(Collections.validate({schema=1,collections={{id="one",name="Map",created_at=1,updated_at=1,editable=true,source={kind="library"}}}}),nil)
end)

test("validated state is normalized without sharing mutable input",function()
  local input={schema=1,active_collection_id="one",collections={{id="one",name="Legacy",created_at=1,updated_at=2,editable=true,source={kind="legacy"},snapshot={path="map.json",sha256=digest,room_count=2,bytes=20}}}}
  local normalized=assert(Collections.validate(input)); input.collections[1].name="changed"; eq(normalized.collections[1].name,"Legacy")
  local maps=assert(Collections.new(normalized,{clock=function() return 3 end,id_factory=function() return "two" end})); eq(maps:active().id,"one")
end)

test("unknown fields and unsafe text fail closed",function()
  eq(Collections.validate({schema=1,collections={},extra=true}),nil)
  nextID=0; local maps=manager(); eq(maps:create("bad\nname"),nil)
  local item=assert(maps:create("Good")); eq(maps:updateSnapshot(item.id,{path="x",sha256="bad",room_count=1,bytes=1}),nil)
  eq(maps:recordBackup(item.id,{path="x",sha256=digest,room_count=1,bytes=1}),nil)
end)

test("collections delete safely without permitting an empty library",function()
  nextID=0; local maps=manager(); local one=assert(maps:create("One")); local two=assert(maps:create("Two")); assert(maps:setActive(two.id))
  assert(maps:remove(two.id)); eq(maps:active(),nil); eq(#maps:list(),1); eq(maps:remove(one.id),nil)
end)
