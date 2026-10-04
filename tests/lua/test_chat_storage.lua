local Storage=require("chat_storage")
local Controller=require("chat_controller")
local History=require("chat_history")

local function fakeStorageApi()
  local api={directories={},appends={},files={},removals={}}
  function api.mkdir(path) api.directories[#api.directories+1]=path; return true end
  function api.append(path,text)
    api.lastPath=path
    api.appends[#api.appends+1]={path=path,text=text}
    api.files[path]=(api.files[path] or "")..text
    return true
  end
  function api.list(path) if api.listings then return api.listings[path] or {} end; return api.listed or {} end
  function api.read(path) return api.files[path] end
  function api.remove(path)
    if api.removeFailure==path then return nil,"remove denied" end
    api.removals[#api.removals+1]=path; api.files[path]=nil; return true
  end
  function api.encode(entry) return entry.message end
  function api.decode(line) return api.decoded and api.decoded[line] or nil,"invalid json" end
  return api
end

local function fakeStorageApiWithLines(lines)
  local api=fakeStorageApi()
  api.listed={"2026-08-30.jsonl"}
  api.files["/chat/profile/2026-08-30.jsonl"]=table.concat(lines,"\n").."\n"
  api.decoded={['{"category":"ESP","message":"valid"}']={category="ESP",message="valid"}}
  return api
end

local function seedLog(api,directory,day,entries)
  api.listings=api.listings or {["/chat"]={"profile"}}
  local dirname="/chat/"..directory
  if not api.listings[dirname] then
    api.listings[dirname]={}
    if directory~="profile" then api.listings["/chat"][#api.listings["/chat"]+1]=directory end
  end
  local filename=day..".jsonl"
  api.listings[dirname][#api.listings[dirname]+1]=filename
  local source={}; api.decoded=api.decoded or {}
  for index,entry in ipairs(entries) do
    source[index]=entry.message; api.decoded[entry.message]=entry
  end
  api.files[dirname.."/"..filename]=table.concat(source,"\n").."\n"
end

local function bucketCounts(entries)
  local counts={}
  for _,entry in ipairs(entries) do
    local bucket=History.retentionKey(entry)
    counts[bucket]=(counts[bucket] or 0)+1
  end
  return counts
end

local function withNativeLogs(logs,run)
  local originalLfs,originalIo,originalYajl=lfs,io,yajl
  local trace={opened=0,closed=0,reads=0,reports={}}
  local ok,err=pcall(function()
    lfs={mkdir=function() return true end,dir=function(directory)
      local files={}
      if directory=="/profile/DGHUDData/chat" then files={"profile"}
      elseif directory=="/profile/DGHUDData/chat/profile" then for filename in pairs(logs) do files[#files+1]=filename end end
      local index=0
      return function() index=index+1; return files[index] end
    end}
    io={open=function(pathname,mode)
      eq(mode,"rb"); trace.opened=trace.opened+1
      local fixture=assert(logs[pathname:match("([^/]+)$")],"unexpected log path")
      if fixture.openError then return nil,fixture.openError end
      local index=0
      return {read=function(_,format)
        eq(format,"*l"); trace.reads=trace.reads+1; index=index+1
        if index<=#fixture.lines then return fixture.lines[index] end
        if fixture.readThrows then error(fixture.readThrows,0) end
        return nil,fixture.readError
      end,close=function()
        trace.closed=trace.closed+1
        if fixture.closeThrows then error(fixture.closeThrows,0) end
        if fixture.closeError then return nil,fixture.closeError end
        return true
      end}
    end}
    yajl={to_value=function(line)
      local category,message=line:match("^(%u+):(.+)$")
      if not category then error("invalid synthetic JSON",0) end
      return {category=category,message=message}
    end}
    local api=Storage.mudletApi("/profile")
    api.report=function(message) trace.reports[#trace.reports+1]=message end
    run(api,trace)
  end)
  lfs,io,yajl=originalLfs,originalIo,originalYajl
  if not ok then error(err,0) end
end

test("appends profile-wide dated JSONL while retaining character metadata",function()
  local api=fakeStorageApi()
  local storage=Storage.new(api,"/profile/DGHUDData/chat",1000)
  assert(storage:append({timestamp="2026-08-31T13:00:00-04:00",character="Dace/Alterac",category="ROOM",message="hello"}))
  eq(api.lastPath,"/profile/DGHUDData/chat/profile/2026-08-31.jsonl")
  eq(api.appends[1].text,"hello\n")
  eq(Storage.safeCharacter("../../Dace"),"dace")
  eq(Storage.safeCharacter("/absolute"),"absolute")
  eq(Storage.safeCharacter(nil),"unknown")
end)

test("retains successive append-only entries in one dated log",function()
  local api=fakeStorageApi()
  local storage=Storage.new(api,"/chat",1000)
  assert(storage:append({timestamp="2026-08-31T13:00:00-04:00",character="Dace",message="first"}))
  assert(storage:append({timestamp="2026-08-31T13:01:00-04:00",character="Dace",message="second"}))
  eq(api.files["/chat/profile/2026-08-31.jsonl"],"first\nsecond\n")
end)

test("profile history recovers and combines legacy character directories",function()
  local api=fakeStorageApi()
  api.listings={
    ["/chat"]={"profile","dace","gia","notes.txt"},
    ["/chat/profile"]={"2026-09-11.jsonl"},
    ["/chat/dace"]={"2026-09-11.jsonl"},
    ["/chat/gia"]={"2026-09-11.jsonl"},
  }
  api.files["/chat/profile/2026-09-11.jsonl"]="shared\n"
  api.files["/chat/dace/2026-09-11.jsonl"]="dace\nshared\n"
  api.files["/chat/gia/2026-09-11.jsonl"]="gia\n"
  api.decoded={
    shared={schema=1,timestamp="2026-09-11T18:01:00-04:00",character="Dace",category="ROOM",message="shared"},
    dace={schema=1,timestamp="2026-09-11T18:00:00-04:00",character="Dace",category="ROOM",message="dace"},
    gia={schema=1,timestamp="2026-09-11T18:02:00-04:00",character="Gia",category="ROOM",message="gia"},
  }
  local entries=Storage.new(api,"/chat",1000):loadRecent()
  eq(#entries,3); eq(entries[1].message,"dace"); eq(entries[2].message,"shared"); eq(entries[3].message,"gia")
end)

test("legacy duplicates do not hide older unique profile history",function()
  local api=fakeStorageApi()
  api.listings={
    ["/chat"]={"profile","dace","gia"},
    ["/chat/profile"]={"2026-09-11.jsonl","2026-09-10.jsonl"},
    ["/chat/dace"]={"2026-09-11.jsonl"},
    ["/chat/gia"]={"2026-09-11.jsonl"},
  }
  api.files["/chat/profile/2026-09-11.jsonl"]="shared\n"
  api.files["/chat/dace/2026-09-11.jsonl"]="shared\n"
  api.files["/chat/gia/2026-09-11.jsonl"]="shared\n"
  api.files["/chat/profile/2026-09-10.jsonl"]="older\n"
  api.decoded={
    shared={schema=1,timestamp="2026-09-11T18:01:00-04:00",character="Dace",category="ROOM",message="shared"},
    older={schema=1,timestamp="2026-09-10T18:00:00-04:00",character="Gia",category="ROOM",message="older"},
  }
  local entries=Storage.new(api,"/chat",2):loadRecent()
  eq(#entries,2); eq(entries[1].message,"older"); eq(entries[2].message,"shared")
end)

test("contains mkdir encode and append exceptions",function()
  for _,name in ipairs({"mkdir","encode","append"}) do
    local api=fakeStorageApi()
    api[name]=function() error(name.." failure") end
    local protected,result,err=pcall(function()
      return Storage.new(api,"/chat",1000):append({timestamp="2026-08-31T13:00:00-04:00",character="Dace",message="hello"})
    end)
    eq(protected,true)
    eq(result,nil)
    eq(type(err),"string")
  end
end)

test("skips malformed JSONL while loading later entries",function()
  local api=fakeStorageApiWithLines({'not json','{"category":"ESP","message":"valid"}'})
  local entries=Storage.new(api,"/chat",1000):loadRecent("Dace Alterac")
  eq(#entries,1)
  eq(entries[1].message,"valid")
end)

test("reports malformed JSONL once without interrupting recovery",function()
  local api=fakeStorageApiWithLines({'not json','still not json','{"category":"ESP","message":"valid"}'})
  api.reports=0
  api.report=function() api.reports=api.reports+1 end
  local entries=Storage.new(api,"/chat",1000):loadRecent("Dace Alterac")
  eq(#entries,1)
  eq(api.reports,1)
end)

test("loads newest dated files first without deleting older logs",function()
  local api=fakeStorageApi()
  api.listed={"2026-08-30.jsonl","2026-08-31.jsonl","notes.txt"}
  api.files["/chat/profile/2026-08-31.jsonl"]="newest\n"
  api.files["/chat/profile/2026-08-30.jsonl"]="older\n"
  api.decoded={newest={message="newest"},older={message="older"}}
  local storage=Storage.new(api,"/chat",1)
  local entries=storage:loadRecent("Dace")
  eq(#entries,1)
  eq(entries[1].message,"newest")
  eq(#api.appends,0)
end)

test("returns the newest N entries in chronological order across dated files",function()
  local api=fakeStorageApi()
  api.listed={"2026-08-30.jsonl","2026-08-31.jsonl"}
  api.files["/chat/profile/2026-08-30.jsonl"]="old-one\nold-two\n"
  api.files["/chat/profile/2026-08-31.jsonl"]="new-one\nnew-two\nnew-three\n"
  api.decoded={
    ["old-one"]={message="old-one"},["old-two"]={message="old-two"},
    ["new-one"]={message="new-one"},["new-two"]={message="new-two"},["new-three"]={message="new-three"},
  }
  local entries=Storage.new(api,"/chat",4):loadRecent("Dace")
  eq(#entries,4)
  eq(entries[1].message,"old-two")
  eq(entries[2].message,"new-one")
  eq(entries[3].message,"new-two")
  eq(entries[4].message,"new-three")
end)

test("hard caps oversized storage reads at the newest thousand",function()
  local api=fakeStorageApi(); local source={}
  api.listed={"2026-08-31.jsonl"}; api.decoded={}
  for index=1,1501 do
    local line="line-"..index; source[index]=line; api.decoded[line]={message=line}
  end
  api.files["/chat/profile/2026-08-31.jsonl"]=table.concat(source,"\n").."\n"
  local entries=Storage.new(api,"/chat",1500):loadRecent("Dace")
  eq(#entries,1000)
  eq(entries[1].message,"line-502")
  eq(entries[1000].message,"line-1501")
end)

test("live combat floods across dates preserve scarce chat through disk reload",function()
  local api=fakeStorageApi(); api.decoded={}
  api.encode=function(entry) api.decoded[entry.message]=entry; return entry.message end
  api.list=function(directory)
    if directory=="/chat" then return {"profile"} end
    local result={}; local prefix=directory.."/"
    for pathname in pairs(api.files) do
      if pathname:sub(1,#prefix)==prefix then result[#result+1]=pathname:sub(#prefix+1) end
    end
    return result
  end
  local epoch=0
  local adapter={addLineTrigger=function() return "synthetic-chat" end,killTrigger=function() end,
    epoch=function() epoch=epoch+1; return epoch end}
  local function controller()
    return Controller.new(adapter,nil,History.new(1000,0),Storage.new(api,"/chat",1000),nil,nil,{COMBAT=false})
  end
  local live=controller(); assert(live:start())
  for _,category in ipairs({"ROOM","WHISPER","STAFF","ALL"}) do
    assert(live:accept({category=category,message="rare-"..category,timestamp="1999-01-01T12:00:00Z"}))
  end
  for _,day in ipairs({"2026-09-30","2026-10-04"}) do
    for index=1,1501 do
      assert(live:accept({category="COMBAT",message=day.."-combat-"..index,timestamp=day.."T12:00:00Z"}))
    end
  end
  eq(#live:entries(),4); eq(#live.history:entries("COMBAT"),1000)
  local savedOld=api.files["/chat/profile/1999-01-01.jsonl"]
  local appendCount=#api.appends; assert(live:shutdown())
  local reloaded=controller(); assert(reloaded:start())
  eq(#reloaded:entries(),4); eq(#reloaded.history.items,1004)
  for index,category in ipairs({"ROOM","WHISPER","STAFF","ALL"}) do eq(reloaded:entries()[index].message,"rare-"..category) end
  local combat=reloaded.history:entries("COMBAT")
  eq(#combat,1000); eq(combat[1].message,"2026-10-04-combat-502"); eq(combat[1000].message,"2026-10-04-combat-1501")
  eq(#api.appends,appendCount); eq(#api.removals,0); eq(api.files["/chat/profile/1999-01-01.jsonl"],savedOld)
  local liveEntry={category="STAFF",message="new staff after reload",timestamp="2026-10-04T13:00:00Z"}
  assert(reloaded:accept(liveEntry)); eq(#reloaded:entries(),5); assert(reloaded:shutdown())
  local secondReload=controller(); assert(secondReload:start()); eq(#secondReload:entries(),5)
  eq(secondReload:entries()[5].message,liveEntry.message); assert(secondReload:shutdown())
end)

test("storage retains newest entries per shared ROOM and fixed private buckets across legacy dates",function()
  local api=fakeStorageApi()
  local older={}
  for _,category in ipairs({"ROOM","WHISPER","ESP","DRAGON","SECIAN","CONTACT","STAFF","ALL"}) do
    older[#older+1]={category=category,message="older-"..category,timestamp="2000-01-01T12:00:00Z"}
  end
  seedLog(api,"legacy","2000-01-01",older)
  seedLog(api,"profile","2026-10-03",{
    {category="ROOM",message="room newer",timestamp="2026-10-03T12:00:00Z"},
    {category="OWN",message="own newest",timestamp="2026-10-03T13:00:00Z"},
  })
  local flood={}
  for index=1,1001 do flood[index]={category="COMBAT",message="combat-"..index,timestamp="2026-10-04T12:00:00Z"} end
  seedLog(api,"profile","2026-10-04",flood)
  local entries=Storage.new(api,"/chat",2):loadRecent(); local counts=bucketCounts(entries)
  eq(#entries,11); eq(counts.ROOM,2); eq(counts.COMBAT,2)
  for _,category in ipairs({"WHISPER","ESP","DRAGON","SECIAN","CONTACT","STAFF","ALL"}) do eq(counts[category],1) end
  eq(entries[8].message,"room newer"); eq(entries[9].message,"own newest")
  eq(entries[10].message,"combat-1000"); eq(entries[11].message,"combat-1001")
  eq(#api.appends,0); eq(#api.removals,0)
end)

test("custom empty and unknown categories share one bounded disk retention bucket",function()
  local api=fakeStorageApi(); local source={}
  for index=1,1501 do
    local category="CUSTOM_"..index
    if index%3==0 then category="" elseif index%5==0 then category=nil end
    source[index]={category=category,message="custom-"..index,timestamp="2026-10-04T12:00:00Z"}
  end
  seedLog(api,"profile","2026-10-04",source)
  local entries=Storage.new(api,"/chat",50000):loadRecent()
  eq(#entries,1000); eq(entries[1].message,"custom-502"); eq(entries[1000].message,"custom-1501")
  eq(bucketCounts(entries).OTHER,1000)
end)

test("repeated legacy copies do not consume bucket capacity or obscure older rare entries",function()
  local api=fakeStorageApi(); local copied={}
  for index=1,1201 do copied[index]={category="COMBAT",message="copy-"..index,timestamp="2026-10-04T12:00:00Z"} end
  for _,directory in ipairs({"profile","copy_a","copy_b","copy_c"}) do seedLog(api,directory,"2026-10-04",copied) end
  local rare={category="STAFF",message="rare staff",timestamp="1990-01-01T12:00:00Z"}
  seedLog(api,"profile","1990-01-01",{rare}); seedLog(api,"copy_a","1990-01-01",{rare})
  seedLog(api,"copy_c","1990-01-01",{{category="WHISPER",message="rare whisper",timestamp="1990-01-01T13:00:00Z"}})
  local storage=Storage.new(api,"/chat",1000)
  local entries=storage:loadRecent(); eq(#entries,1002)
  eq(entries[1].message,"rare staff"); eq(entries[2].message,"rare whisper")
  eq(entries[3].message,"copy-202"); eq(entries[1002].message,"copy-1201")
  local seen={}; for _,entry in ipairs(entries) do eq(seen[entry.message],nil); seen[entry.message]=true end
  local second=storage:loadRecent(); eq(#second,#entries)
  for index,entry in ipairs(entries) do eq(second[index].message,entry.message) end
  eq(#api.removals,0); eq(#api.appends,0)
end)

test("storage selection uses timestamps and stable line ordering even in unsorted archives",function()
  local api=fakeStorageApi()
  seedLog(api,"profile","2026-10-04",{
    {category="ROOM",message="late",timestamp="2026-10-04T14:00:00Z"},
    {category="ROOM",message="early",timestamp="2026-10-04T12:00:00Z"},
    {category="ROOM",message="tie first",timestamp="2026-10-04T13:00:00Z"},
    {category="ROOM",message="tie second",timestamp="2026-10-04T13:00:00Z"},
  })
  seedLog(api,"legacy","2026-10-03",{{category="STAFF",message="timestamp wins over filename",timestamp="2026-10-04T15:00:00Z"}})
  local storage=Storage.new(api,"/chat",3)
  local entries,loadErr=storage:loadRecent()
  eq(loadErr,nil); eq(#entries,4)
  eq(entries[1].message,"tie first"); eq(entries[2].message,"tie second")
  eq(entries[3].message,"late"); eq(entries[4].message,"timestamp wins over filename")
  local second=storage:loadRecent()
  for index,entry in ipairs(entries) do eq(second[index].message,entry.message) end
end)

test("streaming recovery bounds selected decoded records throughout every date and legacy copy",function()
  local api=fakeStorageApi(); local categories={"ROOM","WHISPER","ESP","DRAGON","SECIAN","CONTACT","STAFF","COMBAT","ALL","OTHER"}
  api.listings={
    ["/chat"]={"profile","legacy"},
    ["/chat/profile"]={"2026-10-04.jsonl","2026-10-03.jsonl"},
    ["/chat/legacy"]={"2026-10-04.jsonl","2026-10-03.jsonl"},
  }
  local live=setmetatable({},{__mode="k"}); local decoded,peak,scanned=0,0,0
  api.decode=function(line)
    local day,bucket,index=line:match("^(%d%d%d%d%-%d%d%-%d%d):(%w+):(%d+)$")
    local entry={timestamp=day.."T12:00:00Z",category=bucket=="OTHER" and "CUSTOM_"..index or bucket,message=line}
    live[entry]=true; decoded=decoded+1
    if decoded%128==0 then
      collectgarbage("collect")
      local count=0; for _ in pairs(live) do count=count+1 end
      peak=math.max(peak,count); assert(count<=History.MAX_RETAINED_ENTRIES+1,"unbounded decoded records: "..count)
    end
    return entry
  end
  api.eachLine=function(pathname,consume)
    scanned=scanned+1; local day=pathname:match("(%d%d%d%d%-%d%d%-%d%d)%.jsonl$")
    for _,category in ipairs(categories) do for index=1,1201 do consume(day..":"..category..":"..index) end end
    return true
  end
  api.read=function() error("whole-file fallback must not run when streaming is available") end
  local entries=Storage.new(api,"/chat",1000):loadRecent()
  eq(scanned,4); eq(decoded,48040); eq(#entries,10000)
  assert(peak>=10000); assert(peak<=10001)
  local counts=bucketCounts(entries)
  for _,category in ipairs(categories) do eq(counts[category],1000) end
  for _,entry in ipairs(entries) do
    eq(entry.timestamp,"2026-10-04T12:00:00Z")
    assert(tonumber(entry.message:match(":(%d+)$"))>=202)
  end
  eq(#api.removals,0); eq(#api.appends,0)
end)

test("contains list errors and recovers after a read error",function()
  local unavailable=fakeStorageApi()
  unavailable.list=function() error("directory unavailable") end
  local protected,entries=pcall(function() return Storage.new(unavailable,"/chat",1000):loadRecent("Dace") end)
  eq(protected,true)
  eq(#entries,0)
  local api=fakeStorageApi()
  api.listed={"2026-08-30.jsonl","2026-08-31.jsonl"}
  api.read=function(path)
    if path=="/chat/profile/2026-08-31.jsonl" then error("read failure") end
    return "older\n"
  end
  api.decoded={older={message="older"}}
  protected,entries=pcall(function() return Storage.new(api,"/chat",1000):loadRecent("Dace") end)
  eq(protected,true)
  eq(#entries,1)
  eq(entries[1].message,"older")
end)

test("exposes the latest internal storage failure for diagnostics",function()
  local api=fakeStorageApi()
  api.list=function() error("directory unavailable") end
  local storage=Storage.new(api,"/chat",1000)
  eq(#storage:loadRecent("Dace"),0)
  eq(storage:lastError():find("directory unavailable",1,true)~=nil,true)
end)

test("saved profile clear requires literal confirmation and otherwise retains files",function()
  local api=fakeStorageApi()
  api.listings={
    ["/chat"]={"profile"},
    ["/chat/profile"]={"2026-09-11.jsonl"},
  }
  api.files["/chat/profile/2026-09-11.jsonl"]="saved\n"
  local storage=Storage.new(api,"/chat",1000)
  for _,confirmation in ipairs({false,"yes",1}) do
    local ok,err=storage:clearProfileHistory(confirmation)
    eq(ok,nil); eq(err:find("explicit confirmation",1,true)~=nil,true)
  end
  local ok,err=storage:clearProfileHistory()
  eq(ok,nil); eq(err:find("explicit confirmation",1,true)~=nil,true)
  eq(#api.removals,0); eq(api.files["/chat/profile/2026-09-11.jsonl"],"saved\n")
end)

test("confirmed profile clear removes dated shared and legacy logs only",function()
  local api=fakeStorageApi()
  api.listings={
    ["/chat"]={"profile","dace","gia","notes.txt","../escape"},
    ["/chat/profile"]={"2026-09-11.jsonl","keep.txt"},
    ["/chat/dace"]={"2026-09-10.jsonl"},
    ["/chat/gia"]={"2026-09-09.jsonl","settings.json"},
  }
  for _,pathname in ipairs({"/chat/profile/2026-09-11.jsonl","/chat/dace/2026-09-10.jsonl","/chat/gia/2026-09-09.jsonl","/chat/profile/keep.txt","/chat/gia/settings.json"}) do api.files[pathname]="data" end
  local storage=Storage.new(api,"/chat",1000); storage.lastStorageError="old failure"
  local ok,removed=storage:clearProfileHistory(true)
  eq(ok,true); eq(removed,3); eq(#api.removals,3); eq(storage:lastError(),nil)
  eq(api.files["/chat/profile/2026-09-11.jsonl"],nil); eq(api.files["/chat/dace/2026-09-10.jsonl"],nil); eq(api.files["/chat/gia/2026-09-09.jsonl"],nil)
  eq(api.files["/chat/profile/keep.txt"],"data"); eq(api.files["/chat/gia/settings.json"],"data")
end)

test("profile clear enumerates safely before deleting and reports removal failures",function()
  local api=fakeStorageApi()
  api.listings={
    ["/chat"]={"profile","dace"},
    ["/chat/profile"]={"2026-09-11.jsonl"},
  }
  local list=api.list
  api.list=function(path) if path=="/chat/dace" then return nil,"list denied" end; return list(path) end
  local storage=Storage.new(api,"/chat",1000)
  local ok,err=storage:clearProfileHistory(true)
  eq(ok,nil); eq(err,"list denied"); eq(#api.removals,0)

  api.list=list
  api.listings["/chat/dace"]={"2026-09-10.jsonl"}; api.removeFailure="/chat/profile/2026-09-11.jsonl"
  ok,err=storage:clearProfileHistory(true)
  eq(ok,nil); eq(err:find("remove denied",1,true)~=nil,true); eq(#api.removals,1)
end)

test("Mudlet storage facade treats new character history as empty but reports real failures",function()
  local originalLfs,originalIo=lfs,io
  local ok,err=pcall(function()
    lfs=nil
    local unavailable=Storage.new(Storage.mudletApi("/profile"),"/profile/DGHUDData/chat",1000)
    eq(#unavailable:loadRecent("Dace"),0)
    eq(unavailable:lastError(),"filesystem is unavailable")
    local controller=Controller.new({addLineTrigger=function() return "chat-trigger" end,killTrigger=function() end},nil,History.new(1000,3),unavailable,function() end,function() return "Dace" end)
    eq(controller:start(),true)
    eq(controller:status().last_storage_error,"filesystem is unavailable")
    local directories={}
    lfs={
      mkdir=function(path) directories[path]=true; return true end,
      dir=function(path)
        if not directories[path] then return nil,"No such file or directory" end
        return function() return nil end
      end,
    }
    local firstRun=Storage.new(Storage.mudletApi("/profile"),"/profile/DGHUDData/chat",1000)
    eq(#firstRun:loadRecent("Brand New Character"),0)
    eq(firstRun:lastError(),nil)
    lfs={
      mkdir=function() return true end,
      dir=function() return nil,"permission denied" end,
    }
    local deniedList=Storage.new(Storage.mudletApi("/profile"),"/profile/DGHUDData/chat",1000)
    eq(#deniedList:loadRecent("Dace"),0)
    eq(deniedList:lastError(),"permission denied")
    lfs={
      mkdir=function() return true end,
      dir=function()
      local sent=false
      return function() if sent then return nil end; sent=true; return "2026-08-31.jsonl" end
      end,
    }
    io={open=function(_,mode) if mode=="rb" then return nil,"permission denied" end end}
    local unreadable=Storage.new(Storage.mudletApi("/profile"),"/profile/DGHUDData/chat",1000)
    eq(#unreadable:loadRecent("Dace"),0)
    eq(unreadable:lastError(),"permission denied")
    io={open=function(_,mode)
      if mode=="rb" then return {read=function() return nil,"read denied" end,close=function() return true end} end
    end}
    local readFailure=Storage.new(Storage.mudletApi("/profile"),"/profile/DGHUDData/chat",1000)
    eq(#readFailure:loadRecent("Dace"),0)
    eq(readFailure:lastError(),"read denied")
  end)
  lfs,io=originalLfs,originalIo
  if not ok then error(err,0) end
end)

test("Mudlet storage factory confines file access beneath its chat root",function()
  local originalLfs,originalIo,originalYajl=lfs,io,yajl
  local made={}
  lfs={mkdir=function(directory) made[#made+1]=directory; return true end,dir=function() return function() return nil end end}
  io={open=function() error("unexpected file access") end}
  yajl={to_string=function() return "{}" end,to_value=function() return {} end}
  local api=Storage.mudletApi("/profile")
  assert(api.mkdir("/profile/DGHUDData/chat/dace"))
  eq(made[1],"/profile/DGHUDData")
  eq(made[2],"/profile/DGHUDData/chat")
  eq(made[3],"/profile/DGHUDData/chat/dace")
  eq(api.mkdir("/tmp/escape"),nil)
  eq(api.append("/tmp/escape/log.jsonl","bad"),nil)
  eq(api.append("/profile/DGHUDData/chat/dace/../escape.jsonl","bad"),nil)
  eq(api.eachLine("/tmp/escape/log.jsonl",function() end),nil)
  eq(api.eachLine("/profile/DGHUDData/chat/dace/../escape.jsonl",function() end),nil)
  lfs,io,yajl=originalLfs,originalIo,originalYajl
end)

test("native recovery streams every dated log and closes handles despite malformed entries",function()
  withNativeLogs({
    ["2026-10-04.jsonl"]={lines={"COMBAT:new first","","malformed synthetic record","COMBAT:new last"}},
    ["1999-01-01.jsonl"]={lines={"STAFF:rare staff","WHISPER:rare whisper"}},
  },function(api,trace)
    api.read=function() error("native recovery read a whole file") end
    local storage=Storage.new(api,"/profile/DGHUDData/chat",1)
    local entries=storage:loadRecent()
    eq(#entries,3); eq(entries[1].message,"rare staff"); eq(entries[2].message,"rare whisper"); eq(entries[3].message,"new last")
    eq(trace.opened,2); eq(trace.closed,2); eq(trace.reads,8); eq(storage:lastError(),nil)
    eq(#trace.reports,1); eq(trace.reports[1],"skipped malformed chat log entry")
  end)
end)

test("native streaming closes on returned and thrown read errors and recovers older buckets",function()
  for _,field in ipairs({"readError","readThrows"}) do
    local failed={lines={"COMBAT:before failure"}}; failed[field]="synthetic read denied"
    withNativeLogs({["2026-10-04.jsonl"]=failed,["1999-01-01.jsonl"]={lines={"STAFF:older staff"}}},function(api,trace)
      local storage=Storage.new(api,"/profile/DGHUDData/chat",1000)
      local protected,entries=pcall(function() return storage:loadRecent() end)
      eq(protected,true); eq(#entries,2); eq(entries[1].message,"older staff"); eq(entries[2].message,"before failure")
      eq(trace.opened,2); eq(trace.closed,2); eq(storage:lastError(),"synthetic read denied")
    end)
  end
end)

test("native streaming preserves rare old chat behind multiple days of combat floods",function()
  local logs={["1999-01-01.jsonl"]={lines={"STAFF:rare staff","WHISPER:rare whisper"}}}
  for _,day in ipairs({"2026-10-03","2026-10-04"}) do
    local source={}
    for index=1,1501 do source[index]="COMBAT:"..day.."-combat-"..index end
    logs[day..".jsonl"]={lines=source}
  end
  withNativeLogs(logs,function(api,trace)
    local storage=Storage.new(api,"/profile/DGHUDData/chat",1000)
    local entries=storage:loadRecent(); eq(#entries,1002)
    eq(entries[1].message,"rare staff"); eq(entries[2].message,"rare whisper")
    eq(entries[3].message,"2026-10-04-combat-502"); eq(entries[1002].message,"2026-10-04-combat-1501")
    eq(trace.opened,3); eq(trace.closed,3); eq(storage:lastError(),nil)
  end)
end)

test("native streaming closes a handle when its consumer throws",function()
  withNativeLogs({["2026-10-04.jsonl"]={lines={"STAFF:synthetic"}}},function(api,trace)
    local protected,result,err=pcall(function()
      return api.eachLine("/profile/DGHUDData/chat/profile/2026-10-04.jsonl",function() error("consumer failure",0) end)
    end)
    eq(protected,true); eq(result,nil); eq(err,"consumer failure"); eq(trace.closed,1); eq(trace.reads,1)
  end)
end)

test("native streaming reports open and close failures without leaking or throwing",function()
  for _,field in ipairs({"openError","closeError","closeThrows"}) do
    local failed={lines={}}; failed[field]="synthetic file failure"
    withNativeLogs({["2026-10-04.jsonl"]=failed},function(api,trace)
      local protected,result,err=pcall(function()
        return api.eachLine("/profile/DGHUDData/chat/profile/2026-10-04.jsonl",function() end)
      end)
      eq(protected,true); eq(result,nil); eq(err,"synthetic file failure")
      eq(trace.opened,1); eq(trace.closed,field=="openError" and 0 or 1)
    end)
  end
end)

test("streaming API failures are contained without falling back to whole-file reads",function()
  local api=fakeStorageApi()
  seedLog(api,"profile","2026-10-04",{{category="COMBAT",message="ignored newest"}})
  seedLog(api,"profile","1999-01-01",{{category="STAFF",message="older staff"}})
  api.read=function() error("stream failures must not trigger whole-file reads") end
  api.eachLine=function(pathname,consume)
    if pathname:find("2026-10-04",1,true) then error("stream unavailable",0) end
    consume("older staff"); return true
  end
  local storage=Storage.new(api,"/chat",1000)
  local protected,entries=pcall(function() return storage:loadRecent() end)
  eq(protected,true); eq(#entries,1); eq(entries[1].message,"older staff"); eq(storage:lastError(),"stream unavailable")
end)

test("Mudlet storage factory removes only dated JSONL beneath one chat directory",function()
  local originalLfs,originalIo,originalYajl,originalRemove=lfs,io,yajl,os.remove
  local ok,err=pcall(function()
    lfs={mkdir=function() return true end,dir=function() return function() return nil end end}
    io={open=function() error("unexpected file access") end}
    yajl={to_string=function() return "{}" end,to_value=function() return {} end}
    local removed={}; os.remove=function(pathname) removed[#removed+1]=pathname; return true end
    local api=Storage.mudletApi("/profile")
    eq(api.remove("/profile/DGHUDData/chat/profile/2026-09-11.jsonl"),true)
    eq(api.remove("/profile/DGHUDData/chat/profile/settings.json"),nil)
    eq(api.remove("/profile/DGHUDData/chat/2026-09-11.jsonl"),nil)
    eq(api.remove("/profile/DGHUDData/chat/profile/../2026-09-11.jsonl"),nil)
    eq(api.remove("/tmp/2026-09-11.jsonl"),nil)
    eq(#removed,1); eq(removed[1],"/profile/DGHUDData/chat/profile/2026-09-11.jsonl")
  end)
  lfs,io,yajl,os.remove=originalLfs,originalIo,originalYajl,originalRemove
  if not ok then error(err,0) end
end)

test("Mudlet storage factory appends valid in-root JSONL paths",function()
  local originalLfs,originalIo,originalYajl=lfs,io,yajl
  local opened={}
  lfs={mkdir=function() return true end,dir=function() return function() return nil end end}
  io={open=function(pathname,mode)
    opened.path,opened.mode=pathname,mode
    return {write=function(_,text) opened.text=text; return true end,close=function() return true end}
  end}
  yajl={to_string=function() return "{}" end,to_value=function() return {} end}
  local api=Storage.mudletApi("/profile")
  eq(api.append("/profile/DGHUDData/chat/dace/2026-08-31.jsonl","entry\n"),true)
  eq(opened.path,"/profile/DGHUDData/chat/dace/2026-08-31.jsonl")
  eq(opened.mode,"ab")
  eq(opened.text,"entry\n")
  lfs,io,yajl=originalLfs,originalIo,originalYajl
end)

test("Mudlet storage factory accepts existing owned directories",function()
  local originalLfs,originalIo,originalYajl=lfs,io,yajl
  lfs={mkdir=function() return nil,"File exists" end,attributes=function() return "directory" end,dir=function() return function() return nil end end}
  io={open=function() error("unexpected file access") end}
  yajl={to_string=function() return "{}" end,to_value=function() return {} end}
  local api=Storage.mudletApi("/profile")
  eq(api.mkdir("/profile/DGHUDData/chat/dace"),true)
  lfs,io,yajl=originalLfs,originalIo,originalYajl
end)
