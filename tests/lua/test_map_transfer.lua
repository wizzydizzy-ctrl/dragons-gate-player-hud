local Transfer=require("map_transfer")

local function clone(value) if type(value)~="table" then return value end; local out={}; for key,item in pairs(value) do out[key]=clone(item) end; return out end
local function backend(seed)
  local store={rooms=clone(seed or {}),writes=0,deletes=0,fail_on_write=nil}
  function store:listRooms() local ids={}; for id in pairs(self.rooms) do ids[#ids+1]=id end; table.sort(ids); return ids end
  function store:getRoom(id) return clone(self.rooms[id]) end
  function store:putRoom(room) self.writes=self.writes+1; if self.fail_on_write==self.writes then return nil,"injected write failure" end; self.rooms[room.id]=clone(room); return true end
  function store:deleteRoom(id) self.deletes=self.deletes+1; self.rooms[id]=nil; return true end
  return store
end
local function room(id,area,x)
  return {id=id,area=area or "Academy",partition=area or "Academy",x=x or id,y=0,z=0,name="Room "..id,environment="Plains",flags={"safe","indoor"},poi={"trainer"},exits={},special_exits={}}
end
local function artifact(rooms)
  return {format="DragonsGateHUD-map",schema=1,provenance={artifact_id="sha256:abc",author="Gia",publisher="gia",slug="academy"},rooms=rooms}
end

test("map transfer validation canonicalizes deterministic rooms tags and exits",function()
  local a,b=room(2,"B",2),room(1,"A",1); a.flags={"safe","indoor"}; a.poi={"shop","bank"}; a.exits={{direction="west",to=1}}; a.special_exits={{command="  GO Door ",to=1}}
  local model=assert(Transfer.new(backend()):validate(artifact({a,b})))
  eq(model.provenance.verified,false)
  eq(model.rooms[1].id,1); eq(model.rooms[2].id,2); eq(table.concat(model.rooms[2].flags,","),"indoor,safe"); eq(table.concat(model.rooms[2].poi,","),"bank,shop")
  eq(model.rooms[2].exits[1].direction,"w"); eq(model.rooms[2].special_exits[1].command,"go door")
end)

test("map transfer rejects sparse duplicate and colliding data while repairing external links",function()
  local transfer=Transfer.new(backend())
  local sparse=artifact({room(1)}); sparse.rooms[3]=room(3); eq(transfer:validate(sparse),nil)
  local duplicate=artifact({room(1),room(1,"B",2)}); eq(transfer:validate(duplicate),nil)
  local collision=artifact({room(1,"A",1),room(2,"A",1)}); eq(transfer:validate(collision),nil)
  local linked=artifact({room(1)}); linked.rooms[1].exits={{direction="n",to=999}}; eq(#assert(transfer:validate(linked)).rooms[1].exits,0)
end)

test("export is deterministic JSON-ready and carries POI plus provenance",function()
  local one,two=room(1,"A",1),room(2,"A",2); two.exits={{direction="w",to=1}}; two.special_exits={{command="go arch",to=1}}
  local transfer=Transfer.new(backend({[2]=two,[1]=one})); local out=assert(transfer:exportData({artifact_id="local:1",author="Deklan"}))
  eq(out.format,"DragonsGateHUD-map"); eq(out.rooms[1].id,1); eq(out.rooms[2].exits[1].to,1); eq(out.rooms[2].special_exits[1].command,"go arch"); eq(out.rooms[1].poi[1],"trainer")
end)

test("export omits links to personal or otherwise excluded rooms",function()
  local one=room(1); one.exits={{direction="e",to=99}}; one.special_exits={{command="go gate",to=99}}
  local out=assert(Transfer.new(backend({[1]=one})):exportData({artifact_id="local:1",author="Deklan"}))
  eq(#out.rooms[1].exits,0); eq(#out.rooms[1].special_exits,0)
end)

test("export repairs legacy coordinate collisions without mutating the backend",function()
  local one,two=room(1,"A",1),room(2,"A",1); local store=backend({[1]=one,[2]=two})
  local out=assert(Transfer.new(store):exportData({artifact_id="local:1",author="Deklan"}))
  assert(out.rooms[1].x~=out.rooms[2].x or out.rooms[1].y~=out.rooms[2].y); eq(store.rooms[2].x,1); eq(store.rooms[2].y,0)
end)

test("legacy exits to omitted rooms are repaired during import",function()
  local one=room(1); one.exits={{direction="e",to=99}}
  local value=assert(Transfer.new(backend()):validate(artifact({one})))
  eq(#value.rooms[1].exits,0)
end)

test("shared maps reject unsafe and ambiguous special travel commands",function()
  local one,two=room(1),room(2); one.special_exits={{command="quit",to=2}}
  local value,err=Transfer.new(backend()):validate(artifact({one,two})); eq(value,nil); assert(err:find("unsafe travel command",1,true))
  one.special_exits={{command="go gate",to=1},{command="go gate",to=2}}
  value,err=Transfer.new(backend()):validate(artifact({one,two})); eq(value,nil); assert(err:find("duplicated",1,true))
end)

test("skipping an absent destination removes its incoming imported links",function()
  local one,two=room(1,"A",1),room(2,"B",2); one.exits={{direction="e",to=2}}; one.special_exits={{command="go gate",to=2}}
  local store=backend(); local transfer=Transfer.new(store); local plan=assert(transfer:preview(artifact({one,two}),{A="use_imported",B="skip_area"}))
  assert(transfer:apply(plan,"Deklan")); eq(#store.rooms[1].exits,0); eq(#store.rooms[1].special_exits,0); eq(store.rooms[2],nil)
end)

test("preview groups conflicts by area and performs zero mutation",function()
  local mine=room(1,"Academy",7); mine.owner="DragonsGateHUD"; local personal=room(3,"Temple",3); personal.owner="Personal"
  local store=backend({[1]=mine,[3]=personal}); local before=clone(store.rooms)
  local plan=assert(Transfer.new(store):preview(artifact({room(1,"Academy",1),room(2,"Academy",2),room(3,"Temple",3)}),{Academy="keep_mine",Temple="use_imported"}))
  eq(#plan.areas,2); eq(plan.areas[1].name,"Academy"); eq(plan.conflicts,2); eq(plan.keeps,1); eq(plan.creates,1); eq(plan.blocked,true); eq(store.writes,0); eq(store.deletes,0); eq(store.rooms[1].x,before[1].x)
end)

test("skip area and keep mine preserve canonical local rooms while importing safe rooms",function()
  local mine=room(1,"A",9); mine.owner="DragonsGateHUD"; local store=backend({[1]=mine}); local transfer=Transfer.new(store)
  local plan=assert(transfer:preview(artifact({room(1,"A",1),room(2,"A",2),room(3,"B",3)}),{A="keep_mine",B="skip_area"}))
  local result=assert(transfer:apply(plan,"Deklan")); eq(result.applied,1); eq(store.rooms[1].x,9); eq(store.rooms[2].stash_owner,"Deklan"); eq(store.rooms[3],nil)
  eq(store.rooms[2].derived_from.author,"Gia"); eq(store.rooms[2].derived_from.verified,false); eq(store.rooms[2].read_only,false)
end)

test("use imported replaces only DGHUD collisions and records editable derived stash",function()
  local mine=room(1,"A",9); mine.owner="DragonsGateHUD"; local store=backend({[1]=mine}); local transfer=Transfer.new(store)
  local plan=assert(transfer:preview(artifact({room(1,"A",1)}),{A="use_imported"})); local result=assert(transfer:apply(plan,"Deklan"))
  eq(result.replaced,1); eq(store.rooms[1].x,1); eq(store.rooms[1].owner,"DragonsGateHUD"); eq(store.rooms[1].stash_owner,"Deklan"); eq(store.rooms[1].derived_from.artifact_id,"sha256:abc"); eq(store.rooms[1].derived_from.publisher,"gia"); eq(store.rooms[1].derived_from.slug,"academy"); eq(store.rooms[1].read_only,false)
end)

test("room policy overrides its containing area policy",function()
  local one,two=room(1,"A",8),room(2,"A",9); one.owner="DragonsGateHUD"; two.owner="DragonsGateHUD"
  local store=backend({[1]=one,[2]=two}); local transfer=Transfer.new(store)
  local plan=assert(transfer:preview(artifact({room(1,"A",1),room(2,"A",2)}),{A="keep_mine",rooms={[2]="use_imported"}}))
  eq(plan.keeps,1); eq(plan.replaces,1); assert(transfer:apply(plan,"Deklan")); eq(store.rooms[1].x,8); eq(store.rooms[2].x,2)
end)

test("apply creates all room shells before linking exits",function()
  local store=backend(); local native=store.putRoom
  function store:putRoom(value)
    for _,exit in ipairs(value.exits or {}) do if not self.rooms[exit.to] then return nil,"missing destination" end end
    return native(self,value)
  end
  local one,two=room(1,"A",1),room(2,"A",2); one.exits={{direction="e",to=2}}
  local transfer=Transfer.new(store); local plan=assert(transfer:preview(artifact({one,two}),{A="use_imported"}))
  assert(transfer:apply(plan,"Deklan")); eq(store.rooms[1].exits[1].to,2)
end)

test("blocked personal room collision cannot be applied under any import policy",function()
  local personal=room(1,"A",9); personal.owner="Personal"; local store=backend({[1]=personal}); local transfer=Transfer.new(store)
  local plan=assert(transfer:preview(artifact({room(1,"A",1)}),{A="use_imported"})); eq(plan.blocked,true)
  local ok,err=transfer:apply(plan,"Deklan"); eq(ok,nil); eq(err,"import has blocked room-ID conflicts"); eq(store.rooms[1].x,9); eq(store.writes,0)
end)

test("apply rollback restores replaced rooms and removes creations exactly",function()
  local mine=room(1,"A",9); mine.owner="DragonsGateHUD"; mine.poi={"original"}; local store=backend({[1]=mine}); local transfer=Transfer.new(store)
  local plan=assert(transfer:preview(artifact({room(1,"A",1),room(2,"A",2)}),{A="use_imported"})); store.fail_on_write=2
  local ok,err=transfer:apply(plan,"Deklan"); eq(ok,nil); eq(err,"injected write failure"); eq(store.rooms[1].x,9); eq(store.rooms[1].poi[1],"original"); eq(store.rooms[2],nil)
end)

test("apply rejects stale collision state without mutation",function()
  local store=backend(); local transfer=Transfer.new(store); local plan=assert(transfer:preview(artifact({room(1,"A",1)}),{A="use_imported"}))
  local personal=room(1,"A",8); personal.owner="Personal"; store.rooms[1]=personal
  local ok,err=transfer:apply(plan,"Deklan"); eq(ok,nil); eq(err,"import preview is stale; run preview again"); eq(store.rooms[1].x,8); eq(store.writes,0)
end)

test("backend write exceptions trigger rollback",function()
  local mine=room(1,"A",9); mine.owner="DragonsGateHUD"; local store=backend({[1]=mine}); local native=store.putRoom
  function store:putRoom(value) if value.id==2 then error("write exploded") end; return native(self,value) end
  local transfer=Transfer.new(store); local plan=assert(transfer:preview(artifact({room(1,"A",1),room(2,"A",2)}),{A="use_imported"}))
  local ok,err=transfer:apply(plan,"Deklan"); eq(ok,nil); assert(err:find("write exploded",1,true)); eq(store.rooms[1].x,9); eq(store.rooms[2],nil)
end)

test("validation bounds aggregate untrusted text",function()
  local transfer=Transfer.new(backend(),{string_limit=20}); local ok,err=transfer:validate(artifact({room(1,"Academy",1)}))
  eq(ok,nil); eq(err,"map text exceeds import safety limit")
end)

test("preview requires an explicit policy for every imported area",function()
  local plan,err=Transfer.new(backend()):preview(artifact({room(1,"A",1)}),{})
  eq(plan,nil); eq(err,"missing conflict policy for area A")
end)
