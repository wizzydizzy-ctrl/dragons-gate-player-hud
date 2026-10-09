-- Also runnable directly, without runner registration or an installed LuaFileSystem.
local standalone=type(test)~="function"
if standalone then package.path="src/?.lua;"..package.path end
local total,failed=0,0
local test=test or function(name,fn)
  total=total+1; local ok,err=pcall(fn)
  if ok then print("ok "..total.." - "..name)
  else failed=failed+1; print("not ok "..total.." - "..name.."\n  "..tostring(err)) end
end
local eq=eq or function(actual,expected)
  if actual~=expected then error("expected "..tostring(expected)..", got "..tostring(actual),2) end
end
local Audio=require("autoroller_audio")
local SHA256=require("sha256")
local function little(n,count)
  local out={}; for i=1,count do out[i]=string.char(n%256); n=math.floor(n/256) end; return table.concat(out)
end
local function uint(bytes,offset,count)
  local value=0; for i=count-1,0,-1 do value=value*256+bytes:byte(offset+i) end; return value
end
local function chunk(id,bytes) return id..little(#bytes,4)..bytes..(#bytes%2==1 and "\0" or "") end
local function riff(body) return "RIFF"..little(4+#body,4).."WAVE"..body end
local function wav(options)
  options=options or {}
  local channels,bits,rate=options.channels or 1,options.bits or 16,options.rate or 8000
  local align=channels*bits/8
  local fmt=little(options.format or 1,2)..little(channels,2)..little(rate,4)
    ..little(options.byteRate or rate*align,4)..little(options.align or align,2)..little(bits,2)
  if options.extra then fmt=fmt..options.extra end
  return riff((options.before or "")..chunk("fmt ",fmt)
    ..chunk("data",options.data or string.rep("\0",160))..(options.after or ""))
end
local function quote(value) return "'"..value:gsub("'","'\\''").."'" end
local function run(command)
  local result=os.execute(command.." >/dev/null 2>&1")
  return result==true or result==0
end
local function output(command)
  local pipe=assert(io.popen(command)); local value=pipe:read("*l"); pipe:close(); return assert(value)
end
local function fixture(fn)
  -- Every byte is actually read/written on disk. The injected filesystem shim
  -- models Windows' failing full-table symlinkattributes, using mode only.
  -- Shell operations exist only in this Unix test fixture, never in the module.
  local relative=output("mktemp -d ./.autoroller-audio-test.XXXXXX")
  assert(relative:match("^%./%.autoroller%-audio%-test%.[%w]+$"))
  local root=output("pwd").."/"..relative:sub(3)
  local ctx={root=root,base=root.."/data",source=root.."/source",files={},dirs={root},played={},stopped={},inspections=0,opens=0,dialogs=0}
  local fs={}
  function fs.symlinkattributes(path,key)
    ctx.inspections=ctx.inspections+1
    if key~="mode" then error("Windows cannot retrieve a link target in a full attribute table") end
    if run("test -L "..quote(path)) then return "link" end
    if run("test -d "..quote(path)) then return "directory" end
    if run("test -f "..quote(path)) then return "file" end
    if run("test -e "..quote(path)) then return "other" end
    return nil,"cannot find the file: "..path,2
  end
  function fs.mkdir(path)
    if not run("mkdir "..quote(path)) then return nil,"mkdir failed: "..path end
    ctx.dirs[#ctx.dirs+1]=path; return true
  end
  function fs.rmdir(path) return run("rmdir "..quote(path)) end
  function fs.link(source,destination,symbolic)
    if fs.symlinkattributes(destination,"mode")~=nil then return nil,"destination exists: "..destination end
    if not run("ln "..(symbolic and "-s " or "")..quote(source).." "..quote(destination)) then return nil,"link failed" end
    ctx.files[#ctx.files+1]=destination; return true
  end
  ctx.fs=fs
  ctx.fileIo={open=function(path,mode)
    ctx.opens=ctx.opens+1
    if mode=="wb" then ctx.files[#ctx.files+1]=path end
    return io.open(path,mode)
  end}
  function ctx:write(path,bytes)
    local file=assert(self.fileIo.open(path,"wb")); assert(file:write(bytes)); assert(file:close()); return path
  end
  function ctx:read(path) local file=assert(io.open(path,"rb")); local bytes=file:read("*a"); file:close(); return bytes end
  function ctx:new(overrides)
    local options={base=self.base,fs=fs,io=self.fileIo,os=os,
      invokeFileDialog=function(open,title)
        eq(open,true); assert(title:find("WAV",1,true)); self.dialogs=self.dialogs+1; return self.selection
      end,
      playSoundFile=function(record) self.played[#self.played+1]=record; return true end,
      stopSounds=function(record) self.stopped[#self.stopped+1]=record; return true end}
    for key,value in pairs(overrides or {}) do options[key]=value end
    return assert(Audio.new(options))
  end
  assert(fs.mkdir(ctx.source))
  local ok,err=pcall(fn,ctx)
  for i=#ctx.files,1,-1 do os.remove(ctx.files[i]) end
  for i=#ctx.dirs,1,-1 do fs.rmdir(ctx.dirs[i]) end
  assert(not run("test -e "..quote(root)),"test fixture was not cleaned up")
  if not ok then error(err,0) end
end
local function privateError(err,path)
  assert(type(err)=="string" and err~="")
  if path then assert(not err:find(path,1,true),"error exposed the source path") end
end

test("autoroller audio defaults are complete independent and preserve explicit OFF",function()
  local config=Audio.defaults(); eq(config.enabled,true); eq(config.sound,"three_tone"); eq(config.volume,75); eq(config.repeat_enabled,false)
  config.volume=1; eq(Audio.defaults().volume,75)
  local clean=assert(Audio.validate({enabled=false,repeat_enabled=true,volume=100,sound="horn",unknown="discard"}))
  eq(clean.enabled,false); eq(clean.repeat_enabled,true); eq(clean.volume,100); eq(clean.sound,"horn"); eq(clean.unknown,nil)
  eq(Audio.validate(nil).sound,"three_tone")
end)
test("autoroller audio validates sound enums booleans volume and hashed filenames",function()
  for _,id in ipairs({"three_tone","chime","alarm","horn","custom"}) do eq(assert(Audio.validate({sound=id})).sound,id) end
  for _,bad in ipairs({false,"yes",{enabled=1},{repeat_enabled="true"},{sound="staff"},{sound={}},{sound="https://host/s.wav"},
    {volume=0},{volume=101},{volume=0/0},{volume=math.huge},{volume=1.2},{volume="75"},
    {custom_file="/private/a.wav"},{custom_file=string.rep("z",64)..".wav"},{custom_file=string.rep("a",63)..".wav"},
    {custom_file=string.rep("a",64)..".wav.exe"},{custom_name="/private/a.wav"},{custom_name="C:\\private\\a.wav"},{custom_name="../a.wav"},{custom_name=false}}) do
    local result,err=Audio.validate(bad); eq(result,nil); privateError(err)
  end
  eq(assert(Audio.validate({custom_file=string.rep("A",64)..".wav"})).custom_file,string.rep("a",64)..".wav")
end)
test("autoroller custom labels are bounded sanitized basenames without hidden controls",function()
  local clean=assert(Audio.validate({custom_name="  --Ding.. <tone>\n\0é.wav",custom_file=string.rep("b",64)..".wav"}))
  assert(not clean.custom_name:find("[/\\:%c<>]")); assert(not clean.custom_name:find("..",1,true))
  local bounded=assert(Audio.validate({custom_name=string.rep("a",250)..".wav"})).custom_name
  eq(#bounded,Audio.MAX_NAME); eq(assert(Audio.validate({custom_name="Nice tone.wav"})).custom_name,"Nice tone.wav")
end)
test("autoroller generated catalog WAVs are deterministic distinct bounded unclipped PCM",function()
  local seen={}; eq(#Audio.catalog,4)
  for _,record in ipairs(Audio.catalog) do
    assert(type(record.label)=="string"); eq(record.file,nil)
    local bytes=assert(Audio.wav(record.id)); eq(bytes,Audio.wav(record.id)); eq(seen[bytes],nil); seen[bytes]=true
    eq(bytes:sub(1,4),"RIFF"); eq(bytes:sub(9,12),"WAVE"); eq(uint(bytes,5,4),#bytes-8)
    eq(uint(bytes,21,2),1); eq(uint(bytes,23,2),1); eq(uint(bytes,25,4),22050); eq(uint(bytes,35,2),16)
    eq(uint(bytes,41,4),#bytes-44); assert(#bytes>4000 and #bytes<65536)
    local duration=assert(Audio.validateWav(bytes)); assert(duration>0 and duration<2)
    local peak=0
    for p=45,#bytes,2 do local sample=uint(bytes,p,2); if sample>=32768 then sample=sample-65536 end; peak=math.max(peak,math.abs(sample)) end
    assert(peak>1000 and peak<16000)
  end
  eq(Audio.wav("custom"),nil); eq(Audio.wav("../../s.wav"),nil)
end)
test("WAV validation accepts ordinary PCM widths stereo extensions and padded metadata",function()
  for _,bits in ipairs({8,16,24,32}) do
    local bytes=wav({bits=bits,channels=2,data=string.rep("\0",bits/8*2*100)})
    eq(Audio.validateWav(bytes),100/8000)
  end
  local bytes=wav({extra=little(0,2),before=chunk("JUNK","a"),after=chunk("LIST","metadata")})
  eq(Audio.validateWav(bytes),.01)
  eq(Audio.validateWav(wav({rate=1,bits=8,data=string.rep("\0",60)})),60)
end)
test("WAV validation safely accepts finite IEEE float and rejects NaN and infinity",function()
  local sample32=string.char(0,0,0,63); local sample64=string.char(0,0,0,0,0,0,224,63)
  eq(Audio.validateWav(wav({format=3,bits=32,data=sample32})),1/8000)
  eq(Audio.validateWav(wav({format=3,bits=64,data=sample64,extra=little(0,2)})),1/8000)
  for _,bytes in ipairs({wav({format=3,bits=32,data=string.char(0,0,128,127)}),
    wav({format=3,bits=32,data=string.char(1,0,128,255)}),wav({format=3,bits=64,data=string.char(0,0,0,0,0,0,240,127)})}) do eq(Audio.validateWav(bytes),nil) end
end)
test("WAV validation rejects corrupt bounds ambiguous chunks compressed formats and limits",function()
  local normal=wav()
  local bad={"not audio",normal:sub(1,-2),normal.."junk",normal:gsub("RIFF","RIFX",1),normal:gsub("WAVE","AVI ",1),
    riff("fmt "..little(4294967295,4).."x"),riff(chunk("JUNK","x")),
    riff(chunk("fmt ",string.rep("\0",15))..chunk("data","a")),
    riff(chunk("data","aa")..chunk("data","aa")..normal:sub(13,36)),
    riff(normal:sub(13,36)..normal:sub(13,36)..normal:sub(37)),
    wav({format=2}),wav({format=65534}),wav({channels=3}),wav({bits=12,align=2}),wav({format=3,bits=16}),
    wav({rate=192001}),wav({byteRate=1}),wav({align=4}),wav({data="x"}),wav({data=""}),
    wav({extra=little(5,2)}),wav({extra="x"}),riff(normal:sub(13).."J"),
    wav({bits=8,rate=8000,data=string.rep("\0",8000*61)}),string.rep("\0",Audio.MAX_BYTES+1)}
  for index,bytes in ipairs(bad) do local duration,err=Audio.validateWav(bytes); eq(duration,nil); privateError(err); assert(index) end
  eq(Audio.validateWav(false),nil)
  eq(Audio.validateWav(wav({rate=1,bits=8,data=string.rep("\0",61)})),nil)
end)
test("audio construction cancellation and disabled alerts do no startup file work",function()
  fixture(function(ctx)
    ctx.inspections,ctx.opens=0,0
    local audio=ctx:new(); eq(ctx.inspections,0); eq(ctx.opens,0); eq(ctx.dialogs,0)
    for _,value in ipairs({false,""}) do ctx.selection=value; local record,err=audio:chooseCustom(); eq(record,nil); eq(err,"cancelled") end
    ctx.selection=nil; local record,err=audio:chooseCustom(); eq(record,nil); eq(err,"cancelled")
    eq(audio:play({enabled=false,sound="custom"}),false)
    eq(ctx.inspections,0); eq(ctx.opens,0); eq(#ctx.played,0); eq(ctx.dialogs,3)
  end)
end)
test("custom WAV import supports spaces Unicode names and Windows mode-only attributes",function()
  fixture(function(ctx)
    local bytes=wav({before=chunk("JUNK","odd")})
    ctx.selection=ctx:write(ctx.source.."/Door chime é Ω 音.WAV",bytes)
    local record=assert(ctx:new():chooseCustom())
    eq(record.custom_file,SHA256.hex(bytes)..".wav"); assert(#record.custom_name<=Audio.MAX_NAME)
    assert(not record.custom_name:find("[/\\%c]")); assert(record.custom_name:find("Door chime",1,true))
    eq(ctx:read(ctx.base.."/autoroller-sounds-v1/"..record.custom_file),bytes)
    eq(ctx:read(ctx.selection),bytes); eq(record.path,nil); assert(ctx.inspections>0)
  end)
end)
test("invalid selections reject controls URLs directories wrong extensions and corrupt WAV",function()
  fixture(function(ctx)
    local valid=ctx:write(ctx.source.."/valid.wav",wav())
    local invalid=ctx:write(ctx.source.."/bad.wav","not a WAV")
    local audio=ctx:new()
    for _,path in ipairs({ctx.source,ctx.source.."/missing.wav",ctx:write(ctx.source.."/not.mp3",wav()),invalid,
      valid.."\n",valid.."\0.wav","https://host/private.wav","file://"..valid,"C:stream.wav",ctx.source.."/../source/valid.wav",valid..":stream"}) do
      ctx.selection=path; local record,err=audio:chooseCustom(); eq(record,nil); privateError(err,path)
    end
    eq(ctx.fs.symlinkattributes(ctx.base,"mode"),nil)
  end)
end)
test("custom importer rejects oversize and overlong files before creating a cache",function()
  fixture(function(ctx)
    local audio=ctx:new()
    for index,bytes in ipairs({string.rep("x",Audio.MAX_BYTES+1),wav({bits=8,rate=1,data=string.rep("\0",61)})}) do
      ctx.selection=ctx:write(ctx.source.."/large"..index..".wav",bytes)
      local record,err=audio:chooseCustom(); eq(record,nil); privateError(err,ctx.selection)
    end
    eq(ctx.fs.symlinkattributes(ctx.base,"mode"),nil)
  end)
end)
test("custom chooser and filesystem failures hide private paths and backend errors",function()
  fixture(function(ctx)
    ctx.selection=ctx:write(ctx.source.."/private.wav",wav())
    local audio=ctx:new({invokeFileDialog=function() error(ctx.selection) end})
    local result,err=audio:chooseCustom(); eq(result,nil); privateError(err,ctx.selection)
    audio=ctx:new({io={open=function() error(ctx.selection) end}})
    result,err=audio:chooseCustom(); eq(result,nil); privateError(err,ctx.selection)
    audio=ctx:new({fs={symlinkattributes=function() error(ctx.selection) end}})
    result,err=audio:chooseCustom(); eq(result,nil); privateError(err,ctx.selection)
    audio=ctx:new({fs={symlinkattributes=function() return nil,ctx.selection,13 end}})
    result,err=audio:chooseCustom(); eq(result,nil); privateError(err,ctx.selection)
    audio=ctx:new({invokeFileDialog={}}); eq(audio:chooseCustom(),nil)
  end)
end)
test("custom source files and source parents cannot be symbolic links",function()
  fixture(function(ctx)
    local source=ctx:write(ctx.source.."/sound.wav",wav())
    local fileLink=ctx.root.."/link.wav"; assert(ctx.fs.link(source,fileLink,true))
    local dirLink=ctx.root.."/linked"; assert(ctx.fs.link(ctx.source,dirLink,true))
    for _,path in ipairs({fileLink,dirLink.."/sound.wav"}) do
      ctx.selection=path; local result,err=ctx:new():chooseCustom(); eq(result,nil); privateError(err,path)
    end
    eq(ctx:read(source),wav()); eq(ctx.fs.symlinkattributes(ctx.base,"mode"),nil)
  end)
end)
test("custom cache symlink directories and ancestors never receive writes",function()
  fixture(function(ctx)
    ctx.selection=ctx:write(ctx.source.."/sound.wav",wav())
    assert(ctx.fs.link(ctx.source,ctx.base,true))
    local result,err=ctx:new():chooseCustom(); eq(result,nil); privateError(err,ctx.selection)
    assert(os.remove(ctx.base)); assert(ctx.fs.mkdir(ctx.base))
    assert(ctx.fs.link(ctx.source,ctx.base.."/autoroller-sounds-v1",true))
    result,err=ctx:new():chooseCustom(); eq(result,nil); privateError(err,ctx.selection)
    local linked=ctx.root.."/linked"; assert(ctx.fs.link(ctx.source,linked,true))
    result,err=ctx:new({base=linked.."/new-data"}):chooseCustom(); eq(result,nil); privateError(err,ctx.selection)
    eq(ctx:read(ctx.selection),wav()); eq(ctx.fs.symlinkattributes(ctx.source.."/new-data","mode"),nil)
  end)
end)
test("custom import keeps previous choices and rejects conflicting cache files without overwrite",function()
  fixture(function(ctx)
    local first=wav(); local second=wav({data=string.rep("\1",160)})
    ctx.selection=ctx:write(ctx.source.."/first.wav",first)
    local audio=ctx:new(); local old=assert(audio:chooseCustom())
    local directory=ctx.base.."/autoroller-sounds-v1"
    ctx.selection=ctx:write(ctx.source.."/second.wav",second)
    local nextRecord=assert(audio:chooseCustom()); assert(nextRecord.custom_file~=old.custom_file)
    eq(ctx:read(directory.."/"..old.custom_file),first)
    eq(assert(audio:chooseCustom()).custom_file,nextRecord.custom_file)
    local corrupt="must remain intact"
    ctx:write(directory.."/"..nextRecord.custom_file,corrupt)
    local result,err=audio:chooseCustom(); eq(result,nil); privateError(err,ctx.selection)
    eq(ctx:read(directory.."/"..nextRecord.custom_file),corrupt); eq(ctx:read(directory.."/"..old.custom_file),first)
    ctx.selection=nil; eq(audio:chooseCustom(),nil); eq(ctx:read(directory.."/"..old.custom_file),first)
  end)
end)
test("existing cache symlinks and directories are refused and preserved",function()
  fixture(function(ctx)
    local bytes=wav(); ctx.selection=ctx:write(ctx.source.."/sound.wav",bytes)
    assert(ctx.fs.mkdir(ctx.base)); local directory=ctx.base.."/autoroller-sounds-v1"; assert(ctx.fs.mkdir(directory))
    local destination=directory.."/"..SHA256.hex(bytes)..".wav"
    assert(ctx.fs.link(ctx.selection,destination,true))
    eq(ctx:new():chooseCustom(),nil); eq(ctx.fs.symlinkattributes(destination,"mode"),"link"); eq(ctx:read(ctx.selection),bytes)
    assert(os.remove(destination)); assert(ctx.fs.mkdir(destination))
    eq(ctx:new():chooseCustom(),nil); eq(ctx.fs.symlinkattributes(destination,"mode"),"directory")
  end)
end)
test("failed cache publication and racing destinations preserve every existing byte",function()
  fixture(function(ctx)
    local bytes=wav(); ctx.selection=ctx:write(ctx.source.."/sound.wav",bytes)
    local audio=ctx:new(); local old=assert(audio:chooseCustom()); local directory=ctx.base.."/autoroller-sounds-v1"
    local other=wav({data=string.rep("\2",160)}); ctx.selection=ctx:write(ctx.source.."/other.wav",other)
    local destination=directory.."/"..SHA256.hex(other)..".wav"
    ctx.fs.link=function(_,path) ctx:write(path,"competing file"); return nil,"cannot replace existing file" end
    local result,err=audio:chooseCustom(); eq(result,nil); privateError(err,ctx.selection)
    eq(ctx:read(destination),"competing file"); eq(ctx:read(directory.."/"..old.custom_file),bytes)
    eq(ctx.fs.symlinkattributes(destination..".pending","mode"),nil)
  end)
end)
test("failed writes and closes clean only newly staged output and preserve old audio",function()
  fixture(function(ctx)
    local bytes=wav(); ctx.selection=ctx:write(ctx.source.."/old.wav",bytes)
    local old=assert(ctx:new():chooseCustom()); local directory=ctx.base.."/autoroller-sounds-v1"
    local second=wav({data=string.rep("\3",160)}); ctx.selection=ctx:write(ctx.source.."/new.wav",second)
    local destination=directory.."/"..SHA256.hex(second)..".wav"
    for _,failure in ipairs({"write","close"}) do
      local fakeIo={open=function(path,mode)
        local file,err=ctx.fileIo.open(path,mode); if not file or mode~="wb" then return file,err end
        return {write=function(_,value) if failure=="write" then return nil,ctx.selection end; return file:write(value) end,
          close=function() file:close(); if failure=="close" then return nil,ctx.selection end; return true end}
      end}
      local result,err=ctx:new({io=fakeIo}):chooseCustom(); eq(result,nil); privateError(err,ctx.selection)
      eq(ctx:read(directory.."/"..old.custom_file),bytes); eq(ctx.fs.symlinkattributes(destination,"mode"),nil)
      eq(ctx.fs.symlinkattributes(destination..".pending","mode"),nil)
    end
  end)
end)
test("cache staging collision cannot truncate or remove an existing staging file",function()
  fixture(function(ctx)
    local bytes=wav(); ctx.selection=ctx:write(ctx.source.."/sound.wav",bytes)
    assert(ctx.fs.mkdir(ctx.base)); local directory=ctx.base.."/autoroller-sounds-v1"; assert(ctx.fs.mkdir(directory))
    local stage=directory.."/"..SHA256.hex(bytes)..".wav.pending"; assert(ctx.fs.mkdir(stage))
    local existing=ctx:write(stage.."/sound.wav","keep this staging file")
    eq(ctx:new():chooseCustom(),nil); eq(ctx:read(existing),"keep this staging file")
  end)
end)
test("preview and alert playback use relative volume one loop and distinct owned filters",function()
  fixture(function(ctx)
    local audio=ctx:new()
    local ok,warning,duration=audio:play({sound="horn",volume=37,repeat_enabled=true})
    eq(ok,true); eq(warning,nil); assert(duration>0 and duration<2)
    eq(#ctx.played,1); local record=ctx.played[1]
    eq(record.key,"DGHUD.AutorollerAlert"); eq(record.tag,record.key); eq(record.volume,37); eq(record.loops,1); eq(record.url,nil)
    eq(record.absolute,nil); eq(record.name:find("://",1,true),nil)
    eq(ctx:read(record.name),Audio.wav("horn"))
    eq(audio:play({enabled=false,sound="chime",volume=1},true),true)
    eq(ctx.played[2].key,"DGHUD.AutorollerPreview"); eq(ctx.played[2].tag,"DGHUD.AutorollerPreview"); eq(ctx.played[2].volume,1)
    eq(audio:stop(),true); eq(audio:stop(true),true)
    eq(#ctx.stopped,4); eq(ctx.stopped[1].key,"DGHUD.AutorollerAlert"); eq(ctx.stopped[1].tag,ctx.stopped[1].key)
    eq(ctx.stopped[2].key,"DGHUD.AutorollerPreview"); eq(ctx.stopped[2].tag,ctx.stopped[2].key)
    for _,filter in ipairs(ctx.stopped) do local count=0; for _ in pairs(filter) do count=count+1 end; eq(count,2) end
  end)
end)
test("saved custom playback is local checked and reports its real duration",function()
  fixture(function(ctx)
    local bytes=wav({data=string.rep("\0",320)})
    ctx.selection=ctx:write(ctx.source.."/custom.wav",bytes)
    local audio=ctx:new(); local record=assert(audio:chooseCustom())
    local ok,warning,duration=audio:play({sound="custom",custom_file=record.custom_file,custom_name=record.custom_name,volume=100})
    eq(ok,true); eq(warning,nil); eq(duration,.02)
    eq(ctx.played[1].name,ctx.base.."/autoroller-sounds-v1/"..record.custom_file); eq(ctx.played[1].volume,100)
  end)
end)
test("repeated previews stop only their own key and tag before every playback",function()
  fixture(function(ctx)
    local active={chat=true,game=true,alert=true,preview=true}; local events={}
    local audio=ctx:new({stopSounds=function(filter)
      eq(filter.key,filter.tag)
      local selected=filter.key=="DGHUD.AutorollerPreview" and "preview" or "alert"
      eq(filter.key,selected=="preview" and "DGHUD.AutorollerPreview" or "DGHUD.AutorollerAlert")
      active[selected]=false; events[#events+1]="stop "..selected; return true
    end,playSoundFile=function(record)
      local selected=record.key=="DGHUD.AutorollerPreview" and "preview" or "alert"
      eq(active[selected],false); active[selected]=true; events[#events+1]="play "..selected; return true
    end})
    assert(audio:play({},true)); assert(audio:play({},true))
    eq(table.concat(events,","),"stop preview,play preview,stop preview,play preview")
    eq(active.chat,true); eq(active.game,true); eq(active.alert,true)
    assert(audio:play({})); eq(events[5],"stop alert"); eq(events[6],"play alert"); eq(active.preview,true)
  end)
end)
test("custom backend rejection and exceptions use a verified built-in fallback with warning",function()
  fixture(function(ctx)
    local bytes=wav({format=3,bits=32,data=string.char(0,0,0,63)})
    ctx.selection=ctx:write(ctx.source.."/float.wav",bytes)
    local custom=assert(ctx:new():chooseCustom()); local path=ctx.base.."/autoroller-sounds-v1/"..custom.custom_file
    for _,failure in ipairs({"reject","throw","nil-error"}) do
      local calls,events={},{}
      local audio=ctx:new({stopSounds=function(filter) events[#events+1]="stop"; eq(filter.key,"DGHUD.AutorollerPreview"); eq(filter.tag,filter.key); return true end,
        playSoundFile=function(record)
          calls[#calls+1]=record; events[#events+1]="play"
          if record.name==path then
            if failure=="throw" then error(ctx.selection) end
            if failure=="nil-error" then return nil,ctx.selection end
            return false,ctx.selection
          end
          eq(ctx:read(record.name),Audio.wav("three_tone")); return true
        end})
      local ok,warning,duration=audio:play({sound="custom",custom_file=custom.custom_file,volume=29},true)
      eq(ok,true); assert(warning:find("could not play",1,true)); privateError(warning,ctx.selection)
      eq(duration,Audio.validateWav(Audio.wav("three_tone"))); eq(#calls,2)
      eq(table.concat(events,","),"stop,play,stop,play")
      for _,record in ipairs(calls) do eq(record.key,"DGHUD.AutorollerPreview"); eq(record.tag,record.key); eq(record.volume,29); eq(record.loops,1) end
      eq(ctx:read(path),bytes)
    end
    local audio=ctx:new({playSoundFile=function() error(ctx.selection) end})
    local ok,err=audio:play({sound="custom",custom_file=custom.custom_file}); eq(ok,nil); privateError(err,ctx.selection)
  end)
end)
test("unavailable atomic publication safely refuses without POSIX rename or overwrite",function()
  fixture(function(ctx)
    ctx.selection=ctx:write(ctx.source.."/sound.wav",wav())
    ctx.fs.link=nil
    local audio=ctx:new({os={remove=os.remove,rename=function() error("POSIX rename must not replace files") end}})
    local record,err=audio:chooseCustom(); eq(record,nil); privateError(err,ctx.selection)
    eq(ctx:read(ctx.selection),wav())
    local destination=ctx.base.."/autoroller-sounds-v1/"..SHA256.hex(wav())..".wav"
    eq(ctx.fs.symlinkattributes(destination,"mode"),nil); eq(ctx.fs.symlinkattributes(destination..".pending","mode"),nil)
  end)
end)
test("missing hard-link support plays built-ins from an exclusively reserved verified directory",function()
  fixture(function(ctx)
    ctx.fs.link=nil
    local renames=0
    local audio=ctx:new({os={remove=os.remove,rename=function() renames=renames+1; error("must not replace destinations") end}})
    local ok,warning,duration=audio:play({sound="chime"},true)
    eq(ok,true); eq(warning,nil); eq(duration,Audio.validateWav(Audio.wav("chime"))); eq(renames,0)
    local path=ctx.played[1].name
    assert(path:find("/builtin-",1,true)); eq(ctx:read(path),Audio.wav("chime"))
    eq(audio:play({sound="chime"},true),true); eq(ctx.played[2].name,path)
    ctx:write(path,"keep existing corrupt fallback")
    eq(audio:play({sound="chime"},true),nil); eq(ctx:read(path),"keep existing corrupt fallback")
    local played,fallbackWarning=audio:play({sound="custom"})
    eq(played,true); assert(fallbackWarning); eq(ctx:read(ctx.played[#ctx.played].name),Audio.wav("three_tone"))
    eq(renames,0)
  end)
end)
test("failed hard-link support and a symlink in the built-in namespace never overwrite targets",function()
  fixture(function(ctx)
    ctx.fs.link=function() return nil,"unsupported" end
    local audio=ctx:new(); assert(audio:play({sound="alarm"}))
    local path=ctx.played[1].name; local external=ctx:write(ctx.source.."/external.wav","preserve this file")
    assert(os.remove(path))
    assert(run("ln -s "..quote(external).." "..quote(path))); ctx.files[#ctx.files+1]=path
    local played,err=audio:play({sound="alarm"}); eq(played,nil); privateError(err,external)
    eq(ctx:read(external),"preserve this file"); eq(ctx.fs.symlinkattributes(path,"mode"),"link")
  end)
end)
test("missing corrupt and checksum-mismatched custom sounds fall back with a helpful warning",function()
  fixture(function(ctx)
    local bytes=wav(); ctx.selection=ctx:write(ctx.source.."/custom.wav",bytes)
    local audio=ctx:new(); local custom=assert(audio:chooseCustom()); local path=ctx.base.."/autoroller-sounds-v1/"..custom.custom_file
    for _,replacement in ipairs({false,"broken",wav({data=string.rep("\9",160)})}) do
      if replacement==false then assert(os.remove(path)) else ctx:write(path,replacement) end
      local ok,warning,duration=audio:play({sound="custom",custom_file=custom.custom_file})
      eq(ok,true); assert(warning:find("choose",1,true)); privateError(warning,ctx.selection)
      eq(duration,Audio.validateWav(Audio.wav("three_tone"))); eq(ctx:read(ctx.played[#ctx.played].name),Audio.wav("three_tone"))
    end
    local ok,warning=audio:play({sound="custom"}); eq(ok,true); assert(warning)
  end)
end)
test("custom cache symlinks fall back without touching targets or playing external paths",function()
  fixture(function(ctx)
    local bytes=wav(); ctx.selection=ctx:write(ctx.source.."/custom.wav",bytes)
    local audio=ctx:new(); local custom=assert(audio:chooseCustom()); local path=ctx.base.."/autoroller-sounds-v1/"..custom.custom_file
    assert(os.remove(path)); assert(ctx.fs.link(ctx.selection,path,true))
    local ok,warning=audio:play({sound="custom",custom_file=custom.custom_file}); eq(ok,true); assert(warning)
    eq(ctx:read(ctx.selection),bytes); eq(ctx.fs.symlinkattributes(path,"mode"),"link")
    assert(ctx.played[1].name~=ctx.selection and ctx.played[1].name~=path)
  end)
end)
test("built-in cache mismatches are refused without overwrite or unsafe fallback",function()
  fixture(function(ctx)
    local audio=ctx:new(); assert(audio:play({sound="alarm"}))
    local path=ctx.played[1].name; ctx:write(path,"preserve unrelated data")
    local ok,err=audio:play({sound="alarm"}); eq(ok,nil); privateError(err,path)
    eq(ctx:read(path),"preserve unrelated data"); eq(#ctx.played,1)
  end)
end)
test("backend failures are contained and mute is never changed",function()
  fixture(function(ctx)
    local audio=ctx:new({playSoundFile=function() return false,"muted: "..ctx.selection end})
    ctx.selection="/private/not-for-errors"
    local ok,err=audio:play({sound="three_tone"}); eq(ok,nil); privateError(err,ctx.selection); assert(err:find("mute",1,true))
    local cannotStop=ctx:new({stopSounds=function() error("private stop backend") end})
    ok,err=cannotStop:stop(true); eq(ok,nil); privateError(err); assert(not err:find("private",1,true))
    eq(cannotStop:play({}),nil)
    audio=ctx:new({playSoundFile=function() error(ctx.selection) end}); ok,err=audio:play({}); eq(ok,nil); privateError(err,ctx.selection)
    audio=ctx:new({playSoundFile={},stopSounds={}}); eq(audio:play({}),nil); eq(audio:stop(),nil)
    audio=ctx:new({playSoundFile=function(record) eq(record.volume,75); eq(record.absolute,nil); return nil end,
      os={remove=os.remove,rename=function() error("must not replace cache") end,
        execute=function() error("module must not invoke a shell") end}})
    eq(audio:play({}),true)
  end)
end)

if standalone then
  print(string.format("%d tests, %d failures",total,failed))
  os.exit(failed==0 and 0 or 1)
end
