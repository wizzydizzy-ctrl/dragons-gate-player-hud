local Adapter=require("mudlet_adapter")
test("automatic delay uses a fixed command with quiet echo only",function()
  local adapter=Adapter.new(); local commands={}
  local api={send=function(...) commands[#commands+1]={...} end}
  assert(adapter:sendRoundtimeCheck(api)); eq(#commands,1); eq(commands[1][1],"delay"); eq(commands[1][2],false); eq(#commands[1],2)
end)
test("automatic delay send failure is returned without retrying",function()
  local adapter=Adapter.new()
  for _,api in ipairs({{}, {send=function() return false,"blocked" end}, {send=function() return nil,"blocked" end}, {send=function() error("blocked") end}}) do
    local ok,err=adapter:sendRoundtimeCheck(api); eq(ok,nil); assert(type(err)=="string")
  end
end)
test("automatic delay hides only an unchanged isolated native response",function()
  local adapter=Adapter.new()
  for _,raw in ipairs({"You have 12 second(s) remaining!"," You have 0 seconds remaining! ","\27[32mYou have 1 second remaining!\27[0m"}) do
    local deleted=0
    local api={getCurrentLine=function() return raw end,deleteLine=function() deleted=deleted+1 end}
    assert(adapter:hideRoundtimeCheckLine(raw,api)); eq(deleted,1)
  end
end)
test("delay hiding cannot delete prompts other output shifted rows or malformed content",function()
  local adapter=Adapter.new(); local deleted=0
  local response="You have 12 second(s) remaining!"
  local api={getCurrentLine=function() return "A new combat line!" end,deleteLine=function() deleted=deleted+1 end}
  eq(adapter:hideRoundtimeCheckLine(response,api),false)
  for _,raw in ipairs({"> "..response,"[199] 301/301 hp, 173/173 ftg >"..response,response.." More output","A different line.","You have -1 second(s) remaining!",string.rep("x",2049)}) do
    api.getCurrentLine=function() return raw end
    eq(adapter:hideRoundtimeCheckLine(raw,api),false)
  end
  eq(deleted,0)
end)
test("missing or throwing native gag APIs leave the response visible",function()
  local adapter=Adapter.new(); local response="You have 12 second(s) remaining!"
  for _,api in ipairs({{}, {getCurrentLine=function() error("read failed") end,deleteLine=function() error("must not be called") end},
      {getCurrentLine=function() return response end,deleteLine=function() return false end},
      {getCurrentLine=function() return response end,deleteLine=function() error("gag failed") end}}) do
    eq(adapter:hideRoundtimeCheckLine(response,api),false)
  end
end)
