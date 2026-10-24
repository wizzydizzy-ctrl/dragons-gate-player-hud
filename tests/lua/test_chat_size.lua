local ChatSize=require("chat_size")
local Settings=require("settings")

local function same(actual,expected)
  eq(type(actual),type(expected))
  if type(expected)~="table" then
    if type(expected)=="number" and expected~=expected then eq(actual~=actual,true) else eq(actual,expected) end
    return
  end
  for key,value in pairs(expected) do same(actual[key],value) end
  for key in pairs(actual) do assert(expected[key]~=nil,"unexpected key "..tostring(key)) end
end

test("chat size clamp accepts finite numeric values and rounds within the supported bounds",function()
  eq(ChatSize.MIN_HEIGHT,80); eq(ChatSize.MAX_HEIGHT,600)
  for _,case in ipairs({{80,80},{600,600},{239.49,239},{239.5,240},{"321.5",322},{" 80 ",80},
    {-100,80},{79.9,80},{600.1,600},{1e300,600},{-1e300,80}}) do
    eq(ChatSize.clamp(case[1]),case[2])
  end
  eq(ChatSize.clamp(nil),nil)
  for _,invalid in ipairs({false,true,"","bad","80px","nan","inf",0/0,math.huge,-math.huge,{},function() end}) do
    eq(ChatSize.clamp(invalid),nil)
  end
end)

test("chat size mode defaults safely and requires a finite custom height",function()
  eq(ChatSize.mode(nil),"normal"); eq(ChatSize.mode(false),"normal")
  for _,mode in ipairs({"compact","normal","large"}) do
    eq(ChatSize.mode({size_mode=mode}),mode)
  end
  for _,height in ipairs({80,240,600,"321.5"}) do
    eq(ChatSize.mode({size_mode="custom",height_pixels=height}),"custom")
  end
  for _,chat in ipairs({{}, {size_mode="unknown"}, {size_mode="CUSTOM",height_pixels=240},
    {size_mode="custom"}, {size_mode="custom",height_pixels=false},
    {size_mode="custom",height_pixels="bad"}, {size_mode="custom",height_pixels=0/0},
    {size_mode="custom",height_pixels=math.huge}, {size_mode="custom",height_pixels=-math.huge}}) do
    eq(ChatSize.mode(chat),"normal")
  end
end)

test("chat size layout configuration preserves legacy geometry without mutating preferences",function()
  local legacy={target_height=287,min_height=91,max_height=411,height_percent=.27,
    visible=false,all_sources={ROOM=false},personal={value="keep"}}
  local original=Settings.merge({},legacy)
  local result=ChatSize.forLayout(legacy)
  assert(result~=legacy); same(legacy,original)
  for _,key in ipairs({"target_height","min_height","max_height","height_percent","visible"}) do eq(result[key],legacy[key]) end
  result.target_height=123; eq(legacy.target_height,287)
  eq(type(ChatSize.forLayout(nil)),"table"); eq(type(ChatSize.forLayout(false)),"table")
end)

test("explicit chat size presets override legacy geometry with canonical bounds",function()
  for _,case in ipairs({{"compact",120,80,160},{"normal",240,160,320},{"large",320,200,480}}) do
    local chat={size_mode=case[1],target_height=499,min_height=450,max_height=550,height_percent=.7}
    local original=Settings.merge({},chat)
    local result=ChatSize.forLayout(chat)
    eq(result.target_height,case[2]); eq(result.min_height,case[3]); eq(result.max_height,case[4])
    eq(result.height_percent,.21); same(chat,original)
  end
end)

test("chat size changes produce independent candidates and change only the size choice",function()
  local current={visible=false,capture_outgoing=false,combine_links=true,tab_order={"STAFF","ALL"},
    all_sources={ROOM=false,COMBAT=true},sounds={volume=30,tabs={STAFF={enabled=false,sound="staff"}}},
    target_height=287,height_percent=.27,min_height=91,max_height=411,personal={value="keep"}}
  local original=Settings.merge({},current)
  for _,wanted in ipairs({"compact","normal","large","reset",80,600,239.5,"321.5"}) do
    local candidate,err=ChatSize.change(current,wanted)
    assert(candidate,err); eq(err,nil); assert(candidate~=current)
    local custom=type(wanted)=="number" or tonumber(wanted)~=nil
    eq(candidate.size_mode,custom and "custom" or (wanted=="reset" and "normal" or wanted))
    eq(candidate.height_pixels,custom and ChatSize.clamp(wanted) or nil)
    for key,value in pairs(current) do same(candidate[key],value) end
    same(current,original)
  end
end)

test("normal reset clears custom pixels and restores canonical geometry without resetting preferences",function()
  for _,wanted in ipairs({"reset","normal"}) do
    local current={size_mode="custom",height_pixels=573,target_height=499,min_height=450,max_height=550,
      height_percent=.7,visible=false,personal="keep",all_sources={COMBAT=false}}
    local candidate=assert(ChatSize.change(current,wanted))
    eq(candidate.size_mode,"normal"); eq(candidate.height_pixels,nil)
    eq(current.height_pixels,573); eq(current.size_mode,"custom")
    eq(candidate.visible,false); eq(candidate.personal,"keep"); eq(candidate.all_sources.COMBAT,false)
    local result=ChatSize.forLayout(candidate)
    eq(result.target_height,240); eq(result.min_height,160); eq(result.max_height,320); eq(result.height_percent,.21)
  end
end)

test("invalid chat size requests return an error without mutating the caller",function()
  local current={size_mode="custom",height_pixels=321,personal={value="keep"}}
  local original=Settings.merge({},current)
  local function rejected(value)
    local result,err=ChatSize.change(current,value)
    eq(result,nil); eq(type(err),"string"); assert(#err>0); same(current,original)
  end
  rejected(nil)
  for _,invalid in ipairs({false,true,"","custom","80px","nan","inf",79.9,600.1,
    0/0,math.huge,-math.huge,{},function() end}) do rejected(invalid) end
end)
