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
  lfs,io,yajl=originalLfs,originalIo,originalYajl
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
