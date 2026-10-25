local Main=require("main")

local function fakeChatRuntimeWithPersonalTrigger()
  local f={next=0,borders={0,0,0,0},callbacks={},events={},aliases={},triggers={},timers={},chatEntries={},character="Dace Alterac"}
  function f:getBorders() return self.borders[1],self.borders[2],self.borders[3],self.borders[4] end
  function f:setBorders() end
  function f:getWindowSize() return 1920,1080 end
  function f:createView() return {root={},validateReusable=function() return true end,update=function() end,applyLayout=function() end,renderChat=function() end,setChatFilterCallback=function() end,delete=function() end} end
  function f:addEvent(name,fn) self.next=self.next+1; local id=self.next; self.events[id]={name=name,fn=fn}; return id end
  function f:killEvent(id) self.events[id]=nil end
  function f:addAlias(pattern,fn) self.next=self.next+1; local id="alias-"..self.next; self.aliases[id]={pattern=pattern,fn=fn}; return id end
  function f:killAlias(id) self.aliases[id]=nil end
  function f:addLineTrigger(fn) self.next=self.next+1; local id="trigger-"..self.next; self.triggers[id]=fn; return id end
  function f:addColorizerTrigger(fn) self.next=self.next+1; local id="trigger-"..self.next; self.triggers[id]=fn; return id end
  function f:applyLineColors() return true end
  function f:reportColorizerStatus(enabled) self.reportedColorizer=enabled; return true end
  function f:killTrigger(id) self.triggers[id]=nil end
  function f:line(value) for _,fn in pairs(self.triggers) do fn(value) end end
  function f:getGMCP() return {Char={Status={name="Dace",surname="Alterac"},Vitals={hp=1,hp_max=1}}} end
  function f:isCharacterActive() return false end
  function f:epoch() return self.epochValue or 100 end
  function f:timestamp() return "2026-08-31T13:00:00-04:00" end
  function f:reportChatErrorOnce() self.chatErrorReports=(self.chatErrorReports or 0)+1 end
  function f:reportChatStatus(status) self.reportedChatStatus=status; return status end
  function f:schedule(_,fn) self.next=self.next+1; local id="timer-"..self.next; self.timers[id]=fn; return id end
  function f:cancelTimer(id) self.timers[id]=nil end
  function f:sendCommand() end
  function f:createChatStorage()
    local storage={entries=self.chatEntries}
    function storage:loadRecent() return self.entries end
    function storage:append(entry)
      if f.storageFailure then return nil,f.storageFailure end
      self.entries[#self.entries+1]=entry
      return true
    end
    function storage:clearProfileHistory(confirmed) if confirmed~=true then return nil,"confirmation required" end; self.entries={}; return true,2 end
    function storage:close() return true end
    function storage:characterKey() return "profile" end
    return storage
  end
  return f
end

local function findAlias(runtime,pattern)
  for _,alias in pairs(runtime.aliases) do if alias.pattern==pattern then return alias.fn end end
end

test("capture reload shutdown and chat status preserve personal runtime",function()
  local runtime=fakeChatRuntimeWithPersonalTrigger()
  local personal=runtime:addLineTrigger(function(line)
    runtime.personalTrigger=true
    if line=="The quest begins." then DGHUD.chat.capture("QUEST",line) end
  end)
  local hud=Main.new(runtime,{layout={},chat={enabled=true,visible_limit=1000,dedupe_seconds=3}})
  DGHUD={controller=hud}; Main.installChatApi(DGHUD)
  eq(hud:start(),true); runtime:line('Tekk (ESP): "hello"'); runtime:line("The quest begins.")
  eq(hud.chat:entries()[1].message,"hello"); eq(hud.chat:entries()[2].category,"QUEST")
  runtime.storageFailure="disk full"; runtime.epochValue=104; assert(DGHUD.chat.capture("QUEST","still visible"))
  assert(DGHUD.chat.setFilter("QUEST"))
  local status=findAlias(runtime,"^dghud chatstatus$")(); eq(status.active_filter,"QUEST"); eq(status.visible_count,2)
  eq(status.storage_key,"profile"); eq(status.last_storage_error,"disk full"); eq(runtime.reportedChatStatus,status)
  hud:reload(); eq(runtime.triggers[personal]~=nil,true); eq(runtime.personalTrigger,true); eq(hud.chat:entries()[1].message,"hello")
  hud:shutdown(); eq(runtime.triggers[personal]~=nil,true); DGHUD=nil
end)

test("chat clear aliases keep saved logs unless the full confirmation command is used",function()
  local runtime=fakeChatRuntimeWithPersonalTrigger(); local hud=Main.new(runtime,{layout={},chat={enabled=true,visible_limit=1000,dedupe_seconds=3}}); DGHUD={controller=hud}; Main.installChatApi(DGHUD); assert(hud:start()); assert(hud.chat:capture("QUEST","keep on disk"))
  local clear=findAlias(runtime,"^dghud chat clear$"); assert(clear()); eq(#hud.chat:entries(),0)
  assert(hud.chat:capture("QUEST","delete from disk")); local arm=findAlias(runtime,"^dghud chat clear saved$"); local ok,why=arm(); eq(ok,nil); eq(why,"confirmation required"); eq(#hud.chat:entries(),1)
  local confirm=findAlias(runtime,"^dghud chat clear saved confirm$"); local saved,count=confirm(); eq(saved,true); eq(count,2); eq(#hud.chat:entries(),0); hud:shutdown(); DGHUD=nil
end)

test("restored adopted chat skips repaint only for a verified matching display",function()
  for _,mode in ipairs({"matching","empty","stale","throws","unavailable","cleared"}) do
    local runtime=fakeChatRuntimeWithPersonalTrigger()
    local hud=Main.new(runtime,{layout={},chat={enabled=true,visible_limit=1000,dedupe_seconds=3}})
    local saved={{category="STAFF",message="synthetic retained message",line="synthetic retained message"}}
    hud.chat_handoff={schema=1,character_key="profile",filter="STAFF",entries=mode=="cleared" and {} or saved}
    hud.view_adopted=true
    local checks,repaints=0,0
    hud.view={renderChat=function(_,entries,categories,filter)
      repaints=repaints+1; eq(#entries,mode=="cleared" and 0 or 1); eq(filter,"STAFF")
      if #entries>0 then eq(entries[1].message,saved[1].message); eq(categories[1],"STAFF") end
    end}
    if mode~="unavailable" then hud.view.chatDisplayMatches=function(_,entries,categories,filter)
      checks=checks+1; eq(#entries,mode=="cleared" and 0 or 1); eq(filter,"STAFF")
      if mode=="throws" then error("synthetic native console unavailable") end
      return mode=="matching"
    end end
    assert(hud:startChat()); eq(repaints,mode=="matching" and 0 or 1)
    eq(checks,mode=="unavailable" and 0 or 1); eq(#hud.chat:entries(),mode=="cleared" and 0 or 1)
    eq(hud.chat_handoff,nil); assert(hud.chat:shutdown())
  end
end)

local function partitionAcceptanceRows()
  return {
    {category="CONTACT",line='Sable thinks to you, "Synthetic direct."'},
    {category="PRIVATE",line='Sable thinks to you, "Synthetic legacy direct."'},
    {category="WHISPER",line='Sable whispers to you, "Synthetic whisper."'},
    {category="PRIVATE",line='You pick up Sable\'s mental link, "Synthetic legacy shared." [r-1]'},
    {category="WHISPER",line='You pick up Sable\'s Dragon link, "Synthetic mislabeled shared." [r-1]'},
    {category="ESP",line='Sable (ESP): "Synthetic broadcast."'},
    {category="LINK",line="Synthetic personal LINK."},
    {category="LINK VIEW",line="Synthetic personal LINK VIEW."},
  }
end
local function partitionAcceptanceView()
  local view={repaints=0,chat_output={lastLine=0,lines={}},
    chatDisplayMatches=require("view").chatDisplayMatches}
  function view.chat_output:getLastLineNumber() return self.lastLine end
  function view:setChatFilterCallback(callback) self.filter_callback=callback end
  function view:setChatPresentation(_,combined) self.combined=combined end
  function view:renderChat(entries,categories,filter)
    self.repaints=self.repaints+1
    self.chat_entries={}; self.chat_categories={}; self.chat_line_ranges={}
    self.chat_active_filter=filter; self.chat_output.lines={}
    for index,entry in ipairs(entries) do
      self.chat_entries[index]=entry; self.chat_output.lines[index]=entry.line
      self.chat_line_ranges[index]={entry=entry,first=index,last=index}
    end
    for index,category in ipairs(categories) do self.chat_categories[index]=category end
    self.chat_last_line=#entries; self.chat_output.lastLine=#entries
  end
  return view
end
local function assertPartitionAcceptance(view,hud,rows,filter)
  local expected=filter=="PRIVATE" and {1,2,3}
    or filter==require("chat_channels").linkFilter and {4,5,6}
    or filter=="LINK" and {7} or {8}
  eq(hud:chatStatus().active_filter,filter); eq(view.chat_active_filter,filter)
  eq(#view.chat_entries,#expected); eq(#view.chat_output.lines,#expected)
  for index,source in ipairs(expected) do
    eq(view.chat_entries[index].line,rows[source].line)
    eq(view.chat_output.lines[index],rows[source].line)
  end
  eq(rows[2].category,"PRIVATE"); eq(rows[4].category,"PRIVATE"); eq(rows[5].category,"WHISPER")
  eq(view:chatDisplayMatches(hud.chat:entries(),hud.chat.history:categories(),filter),true)
end

test("main PRIVATE LINK callbacks partition cold and handed off legacy records without storage writes",function()
  local link=require("chat_channels").linkFilter
  for _,mode in ipairs({"cold","handoff"}) do
    local runtime=fakeChatRuntimeWithPersonalTrigger(); local rows=partitionAcceptanceRows()
    local appends=0
    runtime.chatEntries=rows
    function runtime:createChatStorage()
      return {loadRecent=function() return rows end,
        append=function() appends=appends+1; error("selection must not persist synthetic history") end,
        close=function() return true end}
    end
    local view=partitionAcceptanceView()
    local hud=Main.new(runtime,{chat={enabled=true,combine_links=false,visible_limit=1000}})
    hud.view=view
    if mode=="handoff" then hud.chat_handoff={schema=1,character_key="profile",filter="PRIVATE",entries=rows} end
    assert(hud:startChat()); eq(view.combined,true)
    for _,filter in ipairs({"PRIVATE",link,"PRIVATE",link,"LINK","LINK VIEW","PRIVATE"}) do
      local paints=view.repaints
      assert(view.filter_callback(filter)); eq(view.repaints,paints+1)
      assertPartitionAcceptance(view,hud,rows,filter)
    end
    eq(appends,0); eq(#hud.chat:handoff().entries,#rows); assert(hud.chat:shutdown())
  end
end)

test("main adopted PRIVATE LINK display verification repairs equal count stale output and rebinds selection",function()
  local link=require("chat_channels").linkFilter
  for _,filter in ipairs({"PRIVATE",link}) do
    for _,mode in ipairs({"matching","opposite","cleared"}) do
      local runtime=fakeChatRuntimeWithPersonalTrigger(); local rows=partitionAcceptanceRows()
      runtime.chatEntries=rows
      local view=partitionAcceptanceView()
      local settings={chat={enabled=true,visible_limit=1000}}
      local old=Main.new(runtime,settings); old.view=view
      assert(old:startChat()); assert(view.filter_callback(filter))
      local handoff=old.chat:handoff(); assert(old.chat:shutdown())
      if mode=="opposite" then
        local opposite=filter=="PRIVATE" and link or "PRIVATE"
        view:renderChat(old.chat.history:entries(opposite,nil,true),old.chat.history:categories(),opposite)
        eq(#view.chat_entries,3) -- Equal counts cannot establish a matching display.
      elseif mode=="cleared" then
        view.chat_output.lastLine=0; view.chat_output.lines={}
      end
      local paints=view.repaints
      local hud=Main.new(runtime,settings); hud.view=view; hud.view_adopted=true; hud.chat_handoff=handoff
      assert(hud:startChat()); eq(view.repaints,paints+(mode=="matching" and 0 or 1))
      assertPartitionAcceptance(view,hud,rows,filter)
      for _,nextFilter in ipairs({link,"PRIVATE",link}) do
        assert(view.filter_callback(nextFilter)); assertPartitionAcceptance(view,hud,rows,nextFilter)
      end
      eq(old.chat.filter,filter); eq(old.chat.started,false)
      eq(#runtime.chatEntries,8); assert(hud.chat:shutdown())
    end
  end
end)

test("disabled chat leaves personal trigger runtime untouched",function()
  local runtime=fakeChatRuntimeWithPersonalTrigger()
  local personal=runtime:addLineTrigger(function() runtime.personalTrigger=true end)
  local hud=Main.new(runtime,{layout={},chat={enabled=false}})
  eq(hud:start(),true); eq(hud.chat,nil); eq(hud:healthCheck(),true)
  runtime:line("personal line"); eq(runtime.personalTrigger,true); hud:shutdown(); eq(runtime.triggers[personal]~=nil,true)
end)
