local Adapter=require("mudlet_adapter")
local margins={console_left=212,console_right=284}
local function aligned(style,left)
  return style..string.format("\nQPlainTextEdit { margin-left:%dpx; }",left)
end
local function fakeInput(compact,style)
  local h={files={},path="/profile/DGHUDData/input-layout-baseline.lua",style=style or "QPlainTextEdit { color: #abcdef; }",compact=compact==true,calls={},writes=0,renames=0,removes=0,reads=0}
  local api={}; h.api=api
  api.getMudletHomeDir=function() return "/profile" end
  api.lfs={attributes=function() return "directory" end,mkdir=function() return true end}
  api.io={open=function(path,mode)
    if mode=="rb" then
      h.reads=h.reads+1
      if h.diskFailure=="read_open" then return nil,"read denied",13 end
      if h.files[path]==nil then return nil,"missing file",2 end
      return {read=function(_,limit) if h.diskFailure=="read" then return nil,"read failed" end; return h.files[path]:sub(1,limit) end,close=function() return true end}
    end
    eq(mode,"wb")
    if h.diskFailure=="open" then return nil,"open failed" end
    return {
      write=function(self,source) h.writes=h.writes+1; if h.diskFailure=="write" then return nil,"write failed" end; h.files[path]=source; return self end,
      close=function() if h.diskFailure=="close" then return nil,"close failed" end; return true end,
    }
  end}
  api.os={
    rename=function(from,to)
      h.renames=h.renames+1
      if h.diskFailure=="rename" then return nil,"rename failed" end
      assert(h.files[from]); h.files[to]=h.files[from]; h.files[from]=nil; return true
    end,
    remove=function(path)
      h.removes=h.removes+1
      if h.diskFailure=="remove" then return nil,"remove failed" end
      if h.files[path]==nil then return nil,"missing file",2 end
      h.files[path]=nil; return true
    end,
  }
  local function setter(name,value)
    h.calls[#h.calls+1]={name,value}
    -- Deliberately mutate before failure to model a partially applied setter.
    if name=="style" then h.style=value else h.compact=value; if h.resetStyleOnCompact then h.style="native reset" end end
    if h.onSet then h.onSet(name,value) end
    if h.setterFailure==name then
      if h.failOnce then h.setterFailure=nil end
      if h.failureMode=="throw" then error("setter failed") end
      if h.failureMode=="false" then return false,"setter failed" end
      return nil,"setter failed"
    end
    return true
  end
  api.getCmdLineStyleSheet=function(name) eq(name,"main"); return h.style end
  api.getConfig=function(key) eq(key,"compactInputLine"); return h.compact end
  api.setCmdLineStyleSheet=function(name,value) eq(name,"main"); return setter("style",value) end
  api.setConfig=function(key,value) eq(key,"compactInputLine"); return setter("compact",value) end
  -- Any attempt to touch input text/history, send commands, or personal runtime fails.
  for _,name in ipairs({"getCmdLine","clearCmdLine","printCmdLine","send","expandAlias","createCommandLine","killTrigger","killAlias","resetProfile"}) do
    api[name]=function() error("input alignment touched unrelated state") end
  end
  return h
end

test("main input alignment defaults strictly off in display snapshots",function()
  eq(assert(Adapter.displaySettingsSnapshot({side_text_scale=1})).align_input,false)
  for _,value in ipairs({true,false}) do eq(assert(Adapter.displaySettingsSnapshot({side_text_scale=1,align_input=value})).align_input,value) end
  for _,value in ipairs({"false",0,1,{}}) do local result,err=Adapter.displaySettingsSnapshot({side_text_scale=1,align_input=value}); eq(result,nil); assert(err:find("boolean",1,true)) end
end)

test("input alignment display settings round trip and legacy files default off",function()
  local h=fakeInput(); local saved={io=io,os=os,lfs=lfs,getMudletHomeDir=getMudletHomeDir,loadfile=loadfile}
  local ok,err=xpcall(function()
    io=h.api.io; os=h.api.os; lfs=h.api.lfs; getMudletHomeDir=h.api.getMudletHomeDir
    loadfile=function(path) if not h.files[path] then return nil,"missing" end; return (loadstring or load)(h.files[path]) end
    local path="/profile/DGHUDData/display-settings.lua"
    h.files[path]="return {side_text_scale=1.1,auto_wrap=false}"
    eq(assert(Adapter.loadDisplaySettings()).align_input,false)
    for _,value in ipairs({true,false}) do
      assert(Adapter.new():saveDisplaySettings({side_text_scale=.9,auto_wrap=false,align_input=value}))
      local loaded=assert(Adapter.loadDisplaySettings()); eq(loaded.align_input,value); eq(loaded.side_text_scale,.9); eq(loaded.auto_wrap,false)
    end
    local before=h.files[path]; h.diskFailure="rename"
    eq(Adapter.new():saveDisplaySettings({side_text_scale=1,align_input=true}),nil); eq(h.files[path],before)
  end,debug.traceback)
  io=saved.io; os=saved.os; lfs=saved.lfs; getMudletHomeDir=saved.getMudletHomeDir; loadfile=saved.loadfile
  if not ok then error(err,0) end
end)

test("main input OFF without ownership performs no mutations or native calls",function()
  local h=fakeInput(); local adapter=Adapter.new()
  h.api.getCmdLineStyleSheet=nil; h.api.getConfig=nil; h.api.setConfig=nil; h.api.setCmdLineStyleSheet=nil
  eq(adapter:setMainInputAlignment(false,nil,h.api),true); eq(adapter:setMainInputAlignment(false,nil,h.api),true)
  eq(#h.calls,0); eq(h.writes,0); eq(h.renames,0); eq(h.removes,0); eq(h.reads,1)
end)

test("main input ON persists original before mutation and resizes without accumulating CSS",function()
  local h=fakeInput(true); local original=h.style; local adapter=Adapter.new()
  h.onSet=function() local backup=assert(Adapter.parseInputLayoutBaseline(h.files[h.path])); eq(backup.style,original); eq(backup.compact_input,true) end
  eq(adapter:setMainInputAlignment(true,margins,h.api),true)
  eq(h.style,aligned(original,212)); eq(h.compact,false); eq(h.writes,1); eq(h.renames,1); eq(h.files[h.path..".tmp"],nil)
  eq(h.calls[1][1],"compact"); eq(h.calls[1][2],false)
  local calls=#h.calls
  local reads=h.reads
  eq(adapter:setMainInputAlignment(true,margins,h.api),true); eq(#h.calls,calls); eq(h.reads,reads)
  eq(adapter:setMainInputAlignment(true,{console_left=0},h.api),true)
  eq(h.style,aligned(original,0)); eq(h.writes,1)
  eq(adapter:setMainInputAlignment(false,nil,h.api),true); eq(h.style,original); eq(h.compact,true); eq(h.files[h.path],nil)
  calls=#h.calls; reads=h.reads; eq(adapter:setMainInputAlignment(false,nil,h.api),true); eq(#h.calls,calls); eq(h.reads,reads)
end)

test("main input restores original compact true and recaptures after a completed OFF",function()
  local h=fakeInput(true,""); local adapter=Adapter.new()
  assert(adapter:setMainInputAlignment(true,margins,h.api)); eq(h.compact,false); assert(adapter:setMainInputAlignment(false,nil,h.api)); eq(h.style,""); eq(h.compact,true)
  h.style="new personal style"; h.compact=false
  assert(adapter:setMainInputAlignment(true,margins,h.api)); assert(adapter:setMainInputAlignment(false,nil,h.api)); eq(h.style,"new personal style"); eq(h.compact,false)
end)

test("main input recovers ORIGINAL after restart whether startup is ON or OFF",function()
  for _,originalCompact in ipairs({true,false}) do
    for _,resume in ipairs({true,false}) do
      local h=fakeInput(originalCompact); local original=h.style
      assert(Adapter.new():setMainInputAlignment(true,margins,h.api)); local backup=h.files[h.path]; eq(h.compact,false)
      local restarted=Adapter.new()
      eq(restarted:setMainInputAlignment(resume,margins,h.api),true)
      if resume then eq(h.compact,false); eq(h.files[h.path],backup); eq(h.writes,1); assert(restarted:setMainInputAlignment(false,nil,h.api)) end
      eq(h.style,original); eq(h.compact,originalCompact); eq(h.files[h.path],nil)
    end
  end
end)

test("left-only input alignment ignores the right margin and retains native noncompact mode",function()
  local h=fakeInput(false,"QPlainTextEdit { color: #abcdef; margin-right:9px; }"); local original=h.style; local adapter=Adapter.new()
  assert(adapter:setMainInputAlignment(true,{console_left=212},h.api))
  eq(h.style,aligned(original,212)); eq(h.compact,false); eq(#h.calls,1); eq(h.calls[1][1],"style")
  local reads,writes=h.reads,h.writes
  for _,right in ipairs({0,999,-1,math.huge,0/0,false,"ignored",{}}) do
    eq(adapter:setMainInputAlignment(true,{console_left=212,console_right=right},h.api),true)
    eq(h.style,aligned(original,212)); eq(h.compact,false); eq(#h.calls,1)
  end
  local leftOnly=setmetatable({console_left=212},{__index=function(_,key) error("unexpected layout read: "..tostring(key)) end})
  assert(adapter:setMainInputAlignment(true,leftOnly,h.api)); eq(#h.calls,1); eq(h.reads,reads); eq(h.writes,writes)
  assert(adapter:setMainInputAlignment(false,nil,h.api)); eq(h.style,original); eq(h.compact,false)
end)

test("persisted v0.3.58 two-margin compact input migrates using the ORIGINAL backup",function()
  for _,originalCompact in ipairs({true,false}) do
    for _,resume in ipairs({true,false}) do
      local original="QPlainTextEdit { color: #abcdef; }"
      local legacyStyle=original.."\nQPlainTextEdit { margin-left:212px; margin-right:284px; }"
      local h=fakeInput(true,legacyStyle)
      -- Model a crash while v0.3.58 was aligned: native state persists, and
      -- its existing recovery file contains the pre-alignment original.
      local backup=assert(Adapter.inputLayoutBaselineSource({style=original,compact_input=originalCompact}))
      h.files[h.path]=backup
      local adapter=Adapter.new()
      eq(adapter:setMainInputAlignment(resume,{console_left=190},h.api),true)
      if resume then
        eq(h.style,aligned(original,190)); eq(h.style:find("margin-right",1,true),nil); eq(h.compact,false)
        eq(h.files[h.path],backup); eq(h.writes,0); eq(h.renames,0); eq(h.removes,0)
        local calls=#h.calls; assert(adapter:setMainInputAlignment(true,{console_left=190,console_right=999},h.api)); eq(#h.calls,calls)
        assert(adapter:setMainInputAlignment(false,nil,h.api))
      end
      eq(h.style,original); eq(h.compact,originalCompact); eq(h.files[h.path],nil); eq(h.writes,0); eq(h.renames,0)
    end
  end
end)

test("main input backup is byte exact and parsed as data without executing Lua",function()
  local style="quotes '\" \\ \n\r\0 ]=] return os.execute('bad') "..string.char(255).." café"
  for _,compact in ipairs({false,true}) do
    local source=assert(Adapter.inputLayoutBaselineSource({style=style,compact_input=compact}))
    local result=assert(Adapter.parseInputLayoutBaseline(source)); eq(result.style,style); eq(result.compact_input,compact)
    eq(Adapter.parseInputLayoutBaseline(source.."error('executed')"),nil)
  end
  for _,source in ipairs({"", "return os.execute('bad')", 'return {schema=1,compact_input=false,style_hex="a"}\n', 'return {schema=1,compact_input=no,style_hex=""}\n'}) do eq(Adapter.parseInputLayoutBaseline(source),nil) end
  eq(Adapter.inputLayoutBaselineSource({style=string.rep("x",262145),compact_input=false}),nil)
end)

test("main input refuses a corrupt or unreadable backup without native mutations",function()
  for _,failure in ipairs({"corrupt","read_open","read"}) do
    local h=fakeInput(); h.files[h.path]=failure=="corrupt" and "return error('do not run')" or assert(Adapter.inputLayoutBaselineSource({style="original",compact_input=false}))
    if failure~="corrupt" then h.diskFailure=failure end
    local backup=h.files[h.path]
    for _,enabled in ipairs({true,false}) do
      local result,err=Adapter.new():setMainInputAlignment(enabled,margins,h.api); eq(result,nil); eq(type(err),"string")
    end
    eq(#h.calls,0); eq(h.writes,0); eq(h.files[h.path],backup)
  end
end)

test("main input never mutates native state if atomic backup creation fails",function()
  for _,failure in ipairs({"open","write","close","rename"}) do
    local h=fakeInput(); h.diskFailure=failure
    local adapter=Adapter.new(); local result,err=adapter:setMainInputAlignment(true,margins,h.api)
    eq(result,nil); assert(err:find(failure,1,true)); eq(#h.calls,0); eq(h.files[h.path],nil); eq(adapter._main_input_alignment_busy,nil)
    h.diskFailure=nil; assert(adapter:setMainInputAlignment(true,margins,h.api))
  end
end)

test("main input requires valid native getters setters and a finite nonnegative left margin",function()
  for _,name in ipairs({"getCmdLineStyleSheet","getConfig","setCmdLineStyleSheet","setConfig"}) do
    local h=fakeInput(); h.api[name]=nil
    local result,err=Adapter.new():setMainInputAlignment(true,margins,h.api); eq(result,nil); assert(err:find(name,1,true)); eq(#h.calls,0); eq(h.writes,0)
  end
  for _,layout in ipairs({{}, {console_left=-1}, {console_left=0/0}, {console_left=math.huge}}) do
    local h=fakeInput(); eq(Adapter.new():setMainInputAlignment(true,layout,h.api),nil); eq(#h.calls,0); eq(h.writes,0)
  end
  local h=fakeInput(); eq(Adapter.new():setMainInputAlignment("false",margins,h.api),nil); eq(h.reads,0)
  h.api.getConfig=function() return "false" end
  eq(Adapter.new():setMainInputAlignment(true,margins,h.api),nil); eq(h.writes,0)
end)

test("main input contains reentrant native setter calls and releases guard",function()
  local h=fakeInput(true); local adapter=Adapter.new(); local reentries=0
  h.onSet=function()
    reentries=reentries+1
    eq(adapter:setMainInputAlignment(true,margins,h.api),true)
    eq(adapter:setMainInputAlignment(false,nil,h.api),true)
  end
  assert(adapter:setMainInputAlignment(true,margins,h.api)); eq(reentries,2); eq(h.compact,false)
  assert(adapter:setMainInputAlignment(false,nil,h.api)); eq(reentries,4); eq(h.compact,true); eq(adapter._main_input_alignment_busy,nil)
end)

test("main input failed setters roll back partial changes and retain recoverable baseline",function()
  for _,setter in ipairs({"compact","style"}) do
    for _,mode in ipairs({"nil","false","throw"}) do
      local h=fakeInput(true); local original=h.style; local adapter=Adapter.new()
      h.setterFailure=setter; h.failureMode=mode; h.failOnce=true
      local result,err=adapter:setMainInputAlignment(true,margins,h.api)
      eq(result,nil); assert(err:find("setter failed",1,true)); eq(h.style,original); eq(h.compact,true); assert(h.files[h.path]); eq(adapter._main_input_alignment_busy,nil)
      eq(h.calls[1][1],"compact"); eq(h.calls[1][2],false)
      assert(adapter:setMainInputAlignment(false,nil,h.api)); eq(h.files[h.path],nil)
    end
  end
end)

test("main input failed OFF or backup removal keeps original for retry",function()
  for _,failure in ipairs({"style","compact","remove"}) do
    local h=fakeInput(true); local original=h.style; local adapter=Adapter.new()
    assert(adapter:setMainInputAlignment(true,margins,h.api)); local backup=h.files[h.path]; eq(h.compact,false)
    if failure=="remove" then h.diskFailure=failure else h.setterFailure=failure; h.failOnce=true end
    local result,err=adapter:setMainInputAlignment(false,nil,h.api); eq(result,nil); eq(type(err),"string"); eq(h.files[h.path],backup)
    if failure=="remove" then eq(h.style,original); eq(h.compact,true) else eq(h.style,aligned(original,212)); eq(h.compact,false) end
    h.diskFailure=nil; assert(adapter:setMainInputAlignment(false,nil,h.api)); eq(h.style,original); eq(h.compact,true); eq(h.files[h.path],nil)
  end
end)

test("retained main input OFF permits rollback ON without writes when disk persistence fails",function()
  for _,failure in ipairs({"open","write","rename"}) do
    local h=fakeInput(true); local original=h.style; local adapter=Adapter.new()
    assert(adapter:setMainInputAlignment(true,margins,h.api))
    local backup=h.files[h.path]; local baseline=adapter._main_input_baseline
    local reads,writes,renames,removes=h.reads,h.writes,h.renames,h.removes
    h.diskFailure=failure
    eq(adapter:setMainInputAlignment(false,nil,h.api,true),true)
    eq(h.style,original); eq(h.compact,true); eq(h.files[h.path],backup); eq(adapter._main_input_baseline,baseline)
    -- The caller's settings save failed: roll the visible change back to ON.
    eq(adapter:setMainInputAlignment(true,margins,h.api),true)
    eq(h.style,aligned(original,212)); eq(h.compact,false)
    eq(h.files[h.path],backup); eq(adapter._main_input_baseline,baseline)
    eq(h.reads,reads); eq(h.writes,writes); eq(h.renames,renames); eq(h.removes,removes)
    h.diskFailure=nil
    assert(adapter:setMainInputAlignment(false,nil,h.api)); eq(h.style,original); eq(h.compact,true); eq(h.files[h.path],nil)
  end
end)

test("normal main input OFF finalizes a retained baseline without repeating native changes",function()
  local h=fakeInput(true); local original=h.style; local adapter=Adapter.new()
  assert(adapter:setMainInputAlignment(true,margins,h.api))
  assert(adapter:setMainInputAlignment(false,nil,h.api,true))
  local calls,reads,writes,renames,removes=#h.calls,h.reads,h.writes,h.renames,h.removes
  assert(adapter:setMainInputAlignment(false,nil,h.api,true))
  eq(h.removes,removes); assert(h.files[h.path]); assert(adapter._main_input_baseline)
  -- The caller's settings save succeeded: a normal OFF releases ownership.
  eq(adapter:setMainInputAlignment(false,nil,h.api),true)
  eq(h.style,original); eq(h.compact,true); eq(h.files[h.path],nil); eq(adapter._main_input_baseline,nil)
  eq(#h.calls,calls); eq(h.reads,reads); eq(h.writes,writes); eq(h.renames,renames); eq(h.removes,removes+1)
  assert(adapter:setMainInputAlignment(false,nil,h.api,true)); eq(#h.calls,calls); eq(h.reads,reads); eq(h.removes,removes+1)
end)

test("retained main input baseline remains recoverable after restart",function()
  local h=fakeInput(true,"personal style"); local adapter=Adapter.new()
  assert(adapter:setMainInputAlignment(true,margins,h.api)); local backup=h.files[h.path]
  assert(adapter:setMainInputAlignment(false,nil,h.api,true)); eq(h.files[h.path],backup)
  local writes,renames=h.writes,h.renames; h.diskFailure="write"
  local restarted=Adapter.new()
  assert(restarted:setMainInputAlignment(true,margins,h.api))
  eq(h.style,aligned("personal style",212)); eq(h.compact,false); eq(h.files[h.path],backup); eq(h.writes,writes); eq(h.renames,renames)
  assert(restarted:setMainInputAlignment(false,nil,h.api)); eq(h.style,"personal style"); eq(h.compact,true); eq(h.files[h.path],nil)
end)

test("main input repairs drift and reapplies original style after compact reset",function()
  local h=fakeInput(true); local original=h.style; local adapter=Adapter.new(); h.resetStyleOnCompact=true
  assert(adapter:setMainInputAlignment(true,margins,h.api)); eq(h.compact,false); h.style="drift"; h.compact=true
  assert(adapter:setMainInputAlignment(true,margins,h.api)); eq(h.style,aligned(original,212)); eq(h.compact,false); eq(h.writes,1)
  assert(adapter:setMainInputAlignment(false,nil,h.api)); eq(h.style,original); eq(h.compact,true)
end)

test("main input reports rollback failure without discarding the recovery record",function()
  local h=fakeInput(true); local original=h.style; local adapter=Adapter.new(); h.setterFailure="style"
  local result,err=adapter:setMainInputAlignment(true,margins,h.api); eq(result,nil); assert(err:find("rollback failed",1,true)); assert(h.files[h.path])
  h.setterFailure=nil; assert(Adapter.new():setMainInputAlignment(false,nil,h.api)); eq(h.style,original); eq(h.compact,true)
end)
