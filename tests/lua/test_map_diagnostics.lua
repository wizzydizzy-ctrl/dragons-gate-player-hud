local Diagnostics=require("map_diagnostics")
test("mapper diagnostics are bounded and exclude sensitive game content",function()
  local d=Diagnostics.new("1.2.3","player",function() return 42 end)
  for i=1,25 do d:record("error","failure "..i) end
  local text=d:render({enabled=true,current_room=199,owned_room_count=5,owned_area_count=2,last_error="failure 25",settings={transition_submaps={gate=true,door=false}}})
  eq(text:find("events=20",1,true)~=nil,true); eq(text:find("event_20=42|error|failure 25",1,true)~=nil,true); eq(text:find("submap_door=false",1,true)~=nil,true)
  eq(text:find("password",1,true),nil); eq(text:find("room descriptions",1,true)~=nil,true)
end)
