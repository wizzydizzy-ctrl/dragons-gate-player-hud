local Sounds=require("chat_sounds")

test("sound rows use canonical MENTAL and PSYCIAN while legacy sound IDs remain valid",function()
  eq(table.concat(Sounds.tabOrder,","),"ALL,ROOM,PRIVATE,MENTAL,PSYCIAN,DRAGON,SECIAN,STAFF,COMBAT,WORLD")
  eq(Sounds.tabKey(" esp "),"MENTAL"); eq(Sounds.tabKey("contact"),"MENTAL")
  eq(Sounds.tabKey("mental"),"MENTAL"); eq(Sounds.tabKey("psycian"),"PSYCIAN")
  local defaults=Sounds.defaults(); eq(defaults.tabs.ESP,nil); eq(defaults.tabs.CONTACT,nil)
  eq(defaults.tabs.MENTAL.sound,"mental"); eq(defaults.tabs.PSYCIAN.sound,"psycian")
  eq(Sounds.get("esp").file,"chat-esp-v1.wav"); eq(Sounds.get("contact").file,"chat-contact-v1.wav")
  eq(Sounds.get("mental").file,"chat-mental-v1.wav"); eq(Sounds.get("psycian").file,"chat-psycian-v1.wav")
end)

test("chat sound defaults give every tab a distinct sound with only staff enabled",function()
  local defaults=Sounds.defaults(); local seen={}; eq(defaults.volume,60)
  for _,tab in ipairs(Sounds.tabOrder) do
    local entry=defaults.tabs[tab]; eq(entry.enabled,tab=="STAFF"); assert(Sounds.get(entry.sound)); eq(seen[entry.sound],nil); seen[entry.sound]=true
  end
  defaults.tabs.STAFF.enabled=false; eq(Sounds.defaults().tabs.STAFF.enabled,true)
end)

test("legacy ESP and CONTACT migrate ON OFF and sound choices deterministically",function()
  local cases={
    {tabs={},mental={false,"mental"},psycian={false,"psycian"}},
    {tabs={ESP={enabled=true,sound="room"},CONTACT={enabled=true,sound="dragon"}},mental={true,"room"},psycian={true,"room"}},
    {tabs={ESP={enabled=false,sound="esp"},CONTACT={enabled=true,sound="contact"}},mental={true,"contact"},psycian={false,"esp"}},
    {tabs={ESP={enabled=true,sound="private"},CONTACT={enabled=false,sound="world"}},mental={true,"private"},psycian={true,"private"}},
    {tabs={ESP={enabled=false,sound="combat"},CONTACT={enabled=false,sound="world"}},mental={false,"combat"},psycian={false,"combat"}},
    {tabs={CONTACT={enabled=true,sound="contact"}},mental={true,"contact"},psycian={false,"psycian"}},
    {tabs={CONTACT={enabled=false,sound="secian"}},mental={false,"secian"},psycian={false,"psycian"}},
    {tabs={ESP={enabled=false},CONTACT={enabled=false,sound="world"}},mental={false,"world"},psycian={false,"esp"}},
    {tabs={ESP={enabled=true}},mental={true,"esp"},psycian={true,"esp"}},
    {tabs={ESP={},CONTACT={}},mental={false,"mental"},psycian={false,"esp"}},
    {tabs={MENTAL={enabled=false,sound="mental"},ESP={enabled=true,sound="esp"},CONTACT={enabled=true,sound="contact"}},mental={false,"mental"},psycian={true,"esp"}},
    {tabs={MENTAL={enabled=true,sound="world"},ESP={enabled=false,sound="room"},CONTACT={enabled=false,sound="contact"}},mental={true,"world"},psycian={false,"room"}},
    {tabs={MENTAL={},ESP={enabled=true,sound="esp"}},mental={false,"mental"},psycian={true,"esp"}},
    {tabs={PSYCIAN={enabled=false,sound="psycian"},ESP={enabled=true,sound="esp"}},mental={true,"esp"},psycian={false,"psycian"}},
    {tabs={PSYCIAN={enabled=true,sound="contact"},ESP={enabled=false,sound="esp"}},mental={false,"esp"},psycian={true,"contact"}},
    {tabs={PSYCIAN={},ESP={enabled=true,sound="private"}},mental={true,"private"},psycian={false,"psycian"}},
    {tabs={MENTAL={enabled=true,sound="esp"},PSYCIAN={enabled=true,sound="contact"}},mental={true,"esp"},psycian={true,"contact"}},
  }
  for _,case in ipairs(cases) do
    local input={volume=37,tabs=case.tabs}
    local originals={}
    for key,value in pairs(input.tabs) do originals[key]={enabled=value.enabled,sound=value.sound} end
    local config=assert(Sounds.validate(input)); eq(config.volume,37)
    eq(config.tabs.MENTAL.enabled,case.mental[1]); eq(config.tabs.MENTAL.sound,case.mental[2])
    eq(config.tabs.PSYCIAN.enabled,case.psycian[1]); eq(config.tabs.PSYCIAN.sound,case.psycian[2])
    eq(config.tabs.ESP,nil); eq(config.tabs.CONTACT,nil)
    local saved=assert(Sounds.validate(config))
    for key,value in pairs(config.tabs) do eq(saved.tabs[key].enabled,value.enabled); eq(saved.tabs[key].sound,value.sound) end
    config.tabs.MENTAL.enabled=not config.tabs.MENTAL.enabled
    local before,after=0,0
    for key,value in pairs(originals) do before=before+1; eq(input.tabs[key].enabled,value.enabled); eq(input.tabs[key].sound,value.sound) end
    for _ in pairs(input.tabs) do after=after+1 end
    eq(after,before)
  end
end)

test("only intentional legacy sound merges permit duplicate canonical aliases",function()
  local merged=assert(Sounds.validate({tabs={[" esp "]={enabled=true,sound="room"},contact={enabled=true,sound="contact"},MENTAL={enabled=false}}}))
  eq(merged.tabs.MENTAL.enabled,false); eq(merged.tabs.PSYCIAN.enabled,true)
  for _,tabs in ipairs({
    {ESP={},esp={}}, {CONTACT={},[" contact "]={}}, {MENTAL={},mental={}},
    {PSYCIAN={},psycian={}}, {OWN={},ROOM={}}, {WHISPER={},PRIVATE={}},
    {QUEST={},quest={}},
    {MENTAL={enabled=false},ESP={enabled="yes"}},
    {MENTAL={enabled=false},CONTACT={sound="../unsafe"}},
    {PSYCIAN={enabled=false},ESP={sound="unknown"}},
  }) do eq(Sounds.validate({tabs=tabs}),nil) end
end)
test("chat sound validation preserves explicit off and custom tab choices",function()
  local config=assert(Sounds.validate({volume=30,tabs={STAFF={enabled=false,sound="room"},QUEST={enabled=true,sound="dragon"}}}))
  eq(config.tabs.STAFF.enabled,false); eq(config.tabs.STAFF.sound,"room"); eq(config.tabs.QUEST.enabled,true); eq(config.tabs.ROOM.enabled,false)
  eq(Sounds.tabKey("whisper"),"PRIVATE"); eq(Sounds.tabKey("OWN"),"ROOM")
  for _,bad in ipairs({false,"yes",{volume=0},{volume=101},{volume=0/0},{volume=1.5},{volume="60"},{tabs=false},{tabs={STAFF={enabled="no"}}},{tabs={STAFF={sound="../../file"}}},{tabs={["<script>"]={}}},{tabs={STAFF=false}}}) do eq(Sounds.validate(bad),nil) end
  local many={}; for i=1,65 do many["TAB"..i]={} end; eq(Sounds.validate({tabs=many}),nil)
  local boundary={}; for i=1,Sounds.MAX_TABS-#Sounds.tabOrder do boundary["CUSTOM"..i]={enabled=false,sound="all"} end
  local normalized=assert(Sounds.validate({tabs=boundary})); assert(Sounds.validate(normalized))
  boundary["CUSTOM"..(Sounds.MAX_TABS+1-#Sounds.tabOrder)]={}; eq(Sounds.validate({tabs=boundary}),nil)
end)
test("WORLD sound validation adds a silent default while preserving every prior sound choice",function()
  local prior=Sounds.defaults(); prior.tabs.WORLD=nil; prior.volume=25
  prior.tabs.ROOM={enabled=true,sound="esp"}; prior.tabs.STAFF={enabled=false,sound="combat"}; prior.tabs.QUEST={enabled=true,sound="secian"}
  local config=assert(Sounds.validate(prior))
  eq(config.tabs.WORLD.enabled,false); eq(config.tabs.WORLD.sound,"world"); eq(config.volume,25)
  for key,setting in pairs(prior.tabs) do eq(config.tabs[key].enabled,setting.enabled); eq(config.tabs[key].sound,setting.sound) end
  eq(prior.tabs.WORLD,nil); config.tabs.ROOM.sound="world"; eq(prior.tabs.ROOM.sound,"esp")
  local saved=assert(Sounds.validate({tabs={WORLD={enabled=true,sound="staff"}}}))
  eq(saved.tabs.WORLD.enabled,true); eq(saved.tabs.WORLD.sound,"staff")
  eq(Sounds.tabKey(" world "),"WORLD"); eq(Sounds.tabOrder[#Sounds.tabOrder],"WORLD")
  eq(Sounds.catalog[#Sounds.catalog].id,"world"); eq(Sounds.get("world").file,"chat-world-v1.wav")
end)

test("WORLD upgrades all legacy 64-tab sound settings without losing custom preferences",function()
  local legacy={volume=75,tabs={}}; local before=0
  for _,key in ipairs({"ALL","ROOM","PRIVATE","ESP","DRAGON","SECIAN","CONTACT","STAFF","COMBAT"}) do legacy.tabs[key]={enabled=key=="ROOM",sound="private"}; before=before+1 end
  for index=1,55 do legacy.tabs["CUSTOM "..index]={enabled=index%2==0,sound=index%2==0 and "secian" or "combat"}; before=before+1 end
  eq(before,64); eq(Sounds.MAX_TABS,65)
  local updated=assert(Sounds.validate(legacy)); local count=0
  for key,value in pairs(updated.tabs) do
    count=count+1
    if key=="WORLD" then eq(value.enabled,false); eq(value.sound,"world")
    elseif key=="MENTAL" or key=="PSYCIAN" then eq(value.enabled,false); eq(value.sound,"private")
    else eq(value.enabled,legacy.tabs[key].enabled); eq(value.sound,legacy.tabs[key].sound) end
  end
  eq(count,65); eq(updated.volume,75); eq(legacy.tabs.WORLD,nil)
  assert(Sounds.validate(updated)); legacy.tabs.EXTRA={}; eq(Sounds.validate(legacy),nil)
end)

test("merged legacy and canonical preferences keep all 55 custom sound slots",function()
  local config=Sounds.defaults()
  config.tabs.ESP={enabled=true,sound="esp"}; config.tabs.CONTACT={enabled=true,sound="contact"}
  for index=1,55 do config.tabs["CUSTOM "..index]={enabled=index%2==0,sound=index%2==0 and "esp" or "contact"} end
  local saved=assert(Sounds.validate(config)); local count=0
  for key,value in pairs(saved.tabs) do
    count=count+1
    if key:match("^CUSTOM ") then eq(value.enabled,config.tabs[key].enabled); eq(value.sound,config.tabs[key].sound) end
  end
  eq(count,65); eq(saved.tabs.MENTAL.enabled,false); eq(saved.tabs.PSYCIAN.enabled,false)
  assert(Sounds.validate(saved)); config.tabs.EXTRA={}; eq(Sounds.validate(config),nil)
end)

test("WORLD sound stays OFF by default and its own alert is independent of Show in ALL",function()
  local config=Sounds.defaults(); eq(Sounds.choose(config,"WORLD",{WORLD=true}),nil)
  config.tabs.ALL.enabled=true
  local id,tab=Sounds.choose(config,"WORLD",{WORLD=true}); eq(id,"all"); eq(tab,"ALL")
  eq(Sounds.choose(config,"WORLD",{WORLD=false}),nil)
  config.tabs.WORLD.enabled=true
  id,tab=Sounds.choose(config,"WORLD",{WORLD=false}); eq(id,"world"); eq(tab,"WORLD")
  local adapter={now=100,played={}}
  function adapter:epoch() return self.now end
  function adapter:playChatSound(sound,volume) self.played[#self.played+1]={sound,volume}; return true end
  local sounds=assert(Sounds.new(adapter))
  eq(sounds:onEntry({category="WORLD"},{WORLD=true}),false); eq(#adapter.played,0)
  assert(sounds:play("world")); eq(#adapter.played,1); eq(sounds.config.tabs.WORLD.enabled,false)
  assert(sounds:setConfig(config)); assert(sounds:onEntry({category="WORLD"},{WORLD=false}))
  eq(adapter.played[2][1],"world"); eq(adapter.played[2][2],60); eq(#adapter.played,2)
  eq(sounds:onEntry({category="WORLD"},{WORLD=false}),false); eq(#adapter.played,2)
  adapter.now=101; assert(sounds:onEntry({category="WORLD"},{WORLD=false})); eq(#adapter.played,3)
end)

test("sound selection never duplicates ALL PRIVATE and specific tab notifications",function()
  local config=Sounds.defaults(); config.tabs.ALL.enabled=true; config.tabs.PRIVATE.enabled=true
  config.tabs.MENTAL.enabled=true
  local direct={category="CONTACT",line=[[Alara thinks to you, "Direct message."]]}
  local sound,tab=Sounds.choose(config,"ESP",{}); eq(sound,"mental"); eq(tab,"MENTAL")
  sound,tab=Sounds.choose(config,direct,{}); eq(sound,"mental"); eq(tab,"MENTAL")
  config.tabs.MENTAL.enabled=false; sound,tab=Sounds.choose(config,direct,{}); eq(sound,"private"); eq(tab,"PRIVATE")
  config.tabs.PRIVATE.enabled=false; sound,tab=Sounds.choose(config,direct,{}); eq(sound,"all"); eq(tab,"ALL")
  eq(Sounds.choose(config,direct,{MENTAL=false}),nil)
  eq(Sounds.choose(config,"ESP",{MENTAL=false}),nil)
  eq(Sounds.choose(config,"STAFF",{STAFF=false}),"staff")
  config.tabs.ROOM.enabled=true; eq(Sounds.choose(config,"OWN",{}),"room")
  config.tabs.PRIVATE.enabled=true; eq(Sounds.choose(config,"WHISPER",{}),"private")
  config.tabs.QUEST={enabled=true,sound="dragon"}; eq(Sounds.choose(config,"QUEST",{}),"dragon")
end)

local function directSoundEntries()
  return {
    {category="WHISPER",line=[[Alara whispers to you, "Quiet message."]]},
    {category="MENTAL",line=[[Alara thinks to you, "Direct message."]]},
    {category="CONTACT",line=[[Alara thinks to you, "Legacy direct message."]]},
    {category="ESP",line=[[Alara thinks to you, "Legacy ESP direct message."]]},
    {category="CONTACT",line="\27[36m"..[[Alara thinks to you, "Colored direct message."]].."\7\27[0m"},
  }
end

local function broadcastSoundEntries()
  return {
    {category="MENTAL",line=[[You pick up Alara's thoughts, "Global message."]]},
    {category="CONTACT",line=[=[You pick up Alara's thoughts, "Legacy global message." [r-1]]=]},
    {category="MENTAL",line=[[You pick up Alara's thoughts echoing through the area, "Room message."]]},
    {category="CONTACT",line=[[You pick up Alara's thoughts echoing through the area, "Legacy room message."]]},
    {category="MENTAL",line=[[Alara (ESP): "Generic ESP message."]]},
    {category="ESP",line=[[Alara (ESP): "Legacy ESP message."]]},
    {category="CONTACT",line=[[Alara (ESP): "ESP stored as CONTACT."]]},
    {category="MENTAL",line=[[You pick up Alara's mental link, "Generic mental link."]]},
    {category="CONTACT",line=[[You pick up Alara's mental link, "Legacy mental link."]]},
    {category="ESP",line=[=[You pick up Alara's Psycian link, "Named Psycian link." [r-321]]=]},
    {category="CONTACT",line=[[You pick up Alara's Dragon link, "Named Dragon link."]]},
    {category="ESP",line=[[You pick up Alara's Secian link, "Named Secian link."]]},
    {category="PSYCIAN",line=[[You pick up Alara's Psycian link, "Psycian link."]]},
    {category="DRAGON",line=[[You pick up Alara's Dragon link, "Dragon link."]]},
    {category="SECIAN",line=[[You pick up Alara's Secian link, "Secian link."]]},
    {category="SECIAN",line=[[Alara picks up Dace's mental link, "Observed mental link."]]},
    {category="CONTACT",line=[[Alara (ESP): "Dace thinks to you, 'Quoted direct frame.'"]]},
    {category="CONTACT",line="Alara thinks to you, \"First line.\nSecond line.\""},
    {category="CONTACT",line=[[Alara thinks to you, "Direct prefix." extra]]},
    {category="MENTAL"}, {category="ESP"}, {category="CONTACT"},
    {category="PSYCIAN"}, {category="DRAGON"}, {category="SECIAN"},
  }
end

local function soundAdapter()
  local adapter={now=100,played={}}
  function adapter:epoch() return self.now end
  function adapter:playChatSound(id,volume) self.played[#self.played+1]={id,volume}; return true end
  return adapter
end

local function soundController(saved,config,sources)
  local adapter=soundAdapter(); adapter.appends=0; adapter.accepted=0; adapter.loads=0
  function adapter:addLineTrigger(fn) self.trigger=fn; return 1 end
  function adapter:killTrigger() self.trigger=nil end
  function adapter:isCharacterActive() return true end
  function adapter:timestamp() return "2026-10-15T12:00:00Z" end
  local storage={}
  function storage:loadRecent() adapter.loads=adapter.loads+1; return saved or {} end
  function storage:append() adapter.appends=adapter.appends+1; return true end
  local sounds=assert(Sounds.new(adapter,config))
  local controller=require("chat_controller").new(adapter,require("chat_parser"),require("chat_history").new(1000,3),
    storage,nil,function() return "Synthetic Listener" end,sources,function(entry)
      adapter.accepted=adapter.accepted+1; sounds:onEntry(entry,sources)
    end)
  return controller,adapter,sounds
end


test("mislabeled PRIVATE broadcasts select only their effective source or ALL and never consume PRIVATE cooldown",function()
  local rows={
    {[[Tester (ESP): "Synthetic ESP."]],"MENTAL"},
    {[=[You pick up Tester's thoughts, "Synthetic global." [r-1]]=],"MENTAL"},
    {[[You pick up Tester's thoughts echoing through the area, "Synthetic room."]],"MENTAL"},
    {[[You pick up Tester's mental link, "Synthetic generic."]],"MENTAL"},
    {[[Listener picks up Tester's mental link, "Synthetic observed."]],"MENTAL"},
    {[=[You pick up Tester's Psycian link, "Synthetic racial." [r-1]]=],"PSYCIAN"},
    {[[You pick up Tester's Dragon link, "Synthetic racial."]],"DRAGON"},
    {[[You pick up Tester's Secian link, "Synthetic racial."]],"SECIAN"},
  }
  for _,category in ipairs({"PRIVATE","WHISPER"}) do
    for _,source in ipairs({"builtin","gmcp","custom"}) do
      for _,row in ipairs(rows) do
        local entry={category=category,source=source,line=row[1]}
        local config=Sounds.defaults(); config.tabs.STAFF.enabled=false; config.tabs.PRIVATE.enabled=true
        local adapter=soundAdapter(); local sounds=assert(Sounds.new(adapter,config))
        eq(Sounds.choose(config,entry,{}),nil); eq(sounds:onEntry(entry,{}),false)
        eq(#adapter.played,0); eq(next(sounds.lastPlayed),nil)
        local direct={category="CONTACT",line=[[Tester thinks to you, "Synthetic direct."]]}
        assert(sounds:onEntry(direct,{})); eq(#adapter.played,1); eq(adapter.played[1][1],"private")
        config.tabs[row[2]].enabled=true
        local id,tab=Sounds.choose(config,entry,{[row[2]]=false})
        eq(id,row[2]:lower()); eq(tab,row[2])
        config.tabs[row[2]].enabled=false; config.tabs.ALL.enabled=true
        eq(Sounds.choose(config,entry,{[row[2]]=false}),nil)
        id,tab=Sounds.choose(config,entry,{[row[2]]=true})
        eq(id,"all"); eq(tab,"ALL")
        eq(entry.category,category); eq(entry.source,source); eq(entry.line,row[1])
      end
    end
  end
end)

test("restored and live PRIVATE captures isolate broadcasts from direct alerts without replay or raw history rewrites",function()
  local Channels=require("chat_channels")
  local saved={
    {category="PRIVATE",source="gmcp",line=[[You pick up Tester's Dragon link, "Saved synthetic broadcast."]],message="Saved broadcast."},
    {category="PRIVATE",source="custom",line=[[Tester thinks to you, "Saved synthetic direct."]],message="Saved direct."},
  }
  local config=Sounds.defaults(); config.tabs.STAFF.enabled=false; config.tabs.PRIVATE.enabled=true
  local controller,adapter,sounds=soundController(saved,config,{MENTAL=false,DRAGON=false,PSYCIAN=false,WHISPER=false})
  assert(controller:setLinkCombined(true)); assert(controller:start())
  eq(#adapter.played,0); eq(adapter.accepted,0); eq(adapter.appends,0)
  assert(controller:setFilter("PRIVATE")); eq(#controller:entries(),1)
  assert(controller:setFilter(Channels.linkFilter)); eq(#controller:entries(),1)
  assert(controller:capture("PRIVATE","Live synthetic broadcast.",{
    line=[=[You pick up Tester's Psycian link, "Live synthetic broadcast." [r-1]]=]}))
  eq(#adapter.played,0); eq(next(sounds.lastPlayed),nil)
  assert(controller:onLine([[You pick up Tester's mental link, "Live synthetic generic."]]))
  eq(#adapter.played,0)
  assert(controller:capture("PRIVATE","Live synthetic direct.",{line=[[Tester thinks to you, "Live synthetic direct."]]}))
  eq(#adapter.played,1); eq(adapter.played[1][1],"private")
  assert(controller:setFilter("PRIVATE")); eq(#controller:entries(),2)
  assert(controller:setFilter(Channels.linkFilter)); eq(#controller:entries(),3)
  eq(#controller.history.items,5); eq(adapter.appends,3)
  eq(saved[1].category,"PRIVATE"); eq(saved[2].category,"PRIVATE")
  eq(controller.history.items[3].category,"PRIVATE"); eq(controller.history.items[3].source,"custom")
  eq(controller.history.items[5].category,"PRIVATE"); eq(controller.history.items[5].source,"custom")
  eq(saved[1].line,[[You pick up Tester's Dragon link, "Saved synthetic broadcast."]])
  assert(controller:shutdown())
end)

test("PRIVATE alone alerts on whispers and exact direct frames including legacy CONTACT without target metadata",function()
  local config=Sounds.defaults(); config.tabs.STAFF.enabled=false; config.tabs.PRIVATE.enabled=true
  local sources={MENTAL=false,PSYCIAN=false,ESP=false,CONTACT=false,DRAGON=false,SECIAN=false,WHISPER=false,ROOM=false}
  local adapter=soundAdapter(); local sounds=assert(Sounds.new(adapter,config))
  for index,entry in ipairs(directSoundEntries()) do
    local category,line=entry.category,entry.line
    local id,tab=Sounds.choose(config,entry,sources); eq(id,"private"); eq(tab,"PRIVATE")
    adapter.now=100+index; assert(sounds:onEntry(entry,sources))
    eq(#adapter.played,index); eq(adapter.played[index][1],"private")
    eq(entry.category,category); eq(entry.line,line); eq(entry.target,nil)
  end
  eq(Sounds.choose(config,"ROOM",sources),nil); eq(Sounds.choose(config,"OWN",sources),nil)
  config.tabs.PRIVATE.enabled=false
  for _,entry in ipairs(directSoundEntries()) do eq(Sounds.choose(config,entry,sources),nil) end
end)

test("PRIVATE alone stays silent for global room racial and generic ESP broadcasts",function()
  local config=Sounds.defaults(); config.tabs.STAFF.enabled=false; config.tabs.PRIVATE.enabled=true
  local adapter=soundAdapter(); local sounds=assert(Sounds.new(adapter,config))
  for index,entry in ipairs(broadcastSoundEntries()) do
    local category,line=entry.category,entry.line
    adapter.now=100+index
    eq(Sounds.choose(config,entry,{}),nil); eq(sounds:onEntry(entry,{}),false)
    eq(entry.category,category); eq(entry.line,line)
  end
  eq(#adapter.played,0); eq(next(sounds.lastPlayed),nil)
end)

test("broadcasts retain effective source sound priority and ALL fallback without PRIVATE",function()
  local Channels=require("chat_channels")
  for _,entry in ipairs(broadcastSoundEntries()) do
    local config=Sounds.defaults(); config.tabs.ALL.enabled=true; config.tabs.PRIVATE.enabled=true
    local category=Channels.entryCategory(entry)
    config.tabs[category]={enabled=true,sound="contact"}
    local sources={[category]=false}
    local id,tab=Sounds.choose(config,entry,sources); eq(id,"contact"); eq(tab,category)
    config.tabs[category].enabled=false
    eq(Sounds.choose(config,entry,sources),nil)
    sources[category]=true
    id,tab=Sounds.choose(config,entry,sources); eq(id,"all"); eq(tab,"ALL")
    local adapter=soundAdapter(); local sounds=assert(Sounds.new(adapter,config))
    assert(sounds:onEntry(entry,sources)); eq(#adapter.played,1); eq(adapter.played[1][1],"all")
    config.tabs[category].enabled=true; assert(sounds:setConfig(config))
    adapter.now=101; assert(sounds:onEntry(entry,{[category]=false}))
    eq(#adapter.played,2); eq(adapter.played[2][1],"contact")
  end
end)

test("live direct alerts choose specific before PRIVATE before ALL without duplicate playback",function()
  local config=Sounds.defaults(); config.tabs.ALL.enabled=true; config.tabs.PRIVATE.enabled=true
  config.tabs.MENTAL={enabled=true,sound="contact"}
  local adapter=soundAdapter(); local sounds=assert(Sounds.new(adapter,config))
  local entry={category="CONTACT",line=[[Alara thinks to you, "Direct priority."]]}
  local expected={"contact","private","all"}
  for index,id in ipairs(expected) do
    adapter.now=100+index; assert(sounds:setConfig(config)); assert(sounds:onEntry(entry,{}))
    eq(#adapter.played,index); eq(adapter.played[index][1],id)
    if index==1 then config.tabs.MENTAL.enabled=false else config.tabs.PRIVATE.enabled=false end
  end
  eq(sounds:onEntry(entry,{}),false); eq(#adapter.played,3)
end)

test("outgoing named CONTACT remains silent through Controller with every applicable alert enabled",function()
  local config=Sounds.defaults(); config.volume=31
  config.tabs.ALL.enabled=true; config.tabs.PRIVATE.enabled=true
  config.tabs.MENTAL={enabled=true,sound="contact"}
  local controller,adapter,sounds=soundController(nil,config,{MENTAL=false})
  assert(controller:start())
  local fallback=Sounds.defaults(); fallback.tabs.PRIVATE.enabled=true
  for index,target in ipairs({"all","room","Alara"}) do
    adapter.now=100+index; assert(controller:onOutgoing("contact "..target.." Outgoing request."))
    local entry=controller.history.items[index]
    eq(entry.source,"outgoing"); eq(entry.target,target)
    eq(Sounds.choose(fallback,entry,{MENTAL=false}),target=="Alara" and "private" or nil)
    eq(adapter.accepted,0); eq(#adapter.played,0); eq(next(sounds.lastPlayed),nil)
  end
  eq(adapter.appends,3)
  adapter.now=104; assert(controller:onLine([[Alara thinks to you, "Incoming reply."]]))
  eq(adapter.accepted,1); eq(#adapter.played,1); eq(adapter.played[1][1],"contact"); eq(adapter.played[1][2],31)
  eq(config.tabs.MENTAL.enabled,true); eq(config.tabs.MENTAL.sound,"contact"); eq(config.volume,31)
  assert(controller:shutdown())
end)

test("PRIVATE sounds do not replay old direct or broadcast history on cold full or partial restore",function()
  local Parser=require("chat_parser")
  local Outgoing=require("chat_outgoing")
  local Channels=require("chat_channels")
  for _,mode in ipairs({"cold","full","partial"}) do
    local saved={}
    local lines={
      [[Alara thinks to you, "Saved direct message."]],
      [[Alara whispers to you, "Saved whisper."]],
      [[You pick up Alara's thoughts, "Saved broadcast."]],
      [[You pick up Alara's Psycian link, "Saved racial link."]],
    }
    for index,line in ipairs(lines) do saved[index]=assert(Parser.parse(line,"Synthetic Listener","2026-10-14T12:00:00Z")) end
    saved[1].category="CONTACT"; saved[3].category="CONTACT"; saved[4].category="ESP"
    for _,target in ipairs({"Alara","all","room"}) do
      saved[#saved+1]=assert(Outgoing.parse("contact "..target.." Saved outgoing request.","Synthetic Listener","2026-10-14T12:00:00Z"))
    end
    local originals={}
    for index,entry in ipairs(saved) do
      originals[index]={}; for key,value in pairs(entry) do originals[index][key]=value end
    end
    local config=Sounds.defaults(); config.tabs.STAFF.enabled=false; config.tabs.PRIVATE.enabled=true
    local sources={MENTAL=false,WHISPER=false,PSYCIAN=false}
    local controller,adapter,sounds=soundController(saved,config,sources)
    if mode~="cold" then
      assert(controller:restoreHandoff({schema=1,filter="PRIVATE",entries=mode=="partial" and {saved[1]} or saved,partial=mode=="partial"}))
    end
    assert(controller:setLinkCombined(true)); assert(controller:start())
    eq(adapter.loads,mode=="full" and 0 or 1); eq(#controller.history.items,#saved)
    for _,filter in ipairs({"PRIVATE",Channels.linkFilter,"ALL"}) do assert(controller:setFilter(filter)); controller:entries() end
    assert(sounds:setConfig(config))
    eq(adapter.appends,0); eq(adapter.accepted,0); eq(#adapter.played,0); eq(next(sounds.lastPlayed),nil)
    for index,entry in ipairs(saved) do
      for key,value in pairs(originals[index]) do eq(entry[key],value) end
      for key,value in pairs(entry) do eq(value,originals[index][key]) end
    end
    adapter.now=105; assert(controller:onLine([[Alara thinks to you, "New direct message."]]))
    eq(adapter.appends,1); eq(adapter.accepted,1); eq(#adapter.played,1); eq(adapter.played[1][1],"private")
    eq(config.tabs.PRIVATE.enabled,true); eq(config.tabs.MENTAL.enabled,false); eq(config.tabs.ALL.enabled,false)
    eq(sources.MENTAL,false); eq(sources.WHISPER,false); eq(sources.PSYCIAN,false)
    assert(controller:shutdown())
  end
end)

test("ALL sound selection follows merged legacy flags and explicit canonical OFF",function()
  local config=Sounds.defaults(); config.tabs.ALL.enabled=true
  for _,category in ipairs({"MENTAL","ESP","CONTACT"}) do
    eq(Sounds.choose(config,category,{ESP=false,CONTACT=false}),nil)
    eq(Sounds.choose(config,category,{ESP=true,CONTACT=false}),"all")
    eq(Sounds.choose(config,category,{ESP=false,CONTACT=true}),"all")
    eq(Sounds.choose(config,category,{MENTAL=false,ESP=true,CONTACT=true}),nil)
    eq(Sounds.choose(config,category,{MENTAL=true,ESP=false,CONTACT=false}),"all")
  end
  eq(Sounds.choose(config,"PSYCIAN",{PSYCIAN=false,MENTAL=true}),nil)
  eq(Sounds.choose(config,"PSYCIAN",{PSYCIAN=true,MENTAL=false}),"all")
end)

test("merged mental aliases select one alert and share the same cooldown",function()
  local adapter={now=100,played={}}
  function adapter:chatSoundTime() return self.now end
  function adapter:playChatSound(id,volume) self.played[#self.played+1]={id,volume}; return true end
  local sounds=assert(Sounds.new(adapter,{tabs={
    ALL={enabled=true},PRIVATE={enabled=true},
    ESP={enabled=true,sound="room"},CONTACT={enabled=true,sound="contact"},
  }}))
  assert(sounds:onEntry({category="ESP"})); eq(#adapter.played,1); eq(adapter.played[1][1],"room")
  adapter.now=100.1; eq(sounds:onEntry({category="CONTACT"}),false)
  adapter.now=100.99; eq(sounds:onEntry({category="MENTAL"}),false); eq(#adapter.played,1)
  adapter.now=101; assert(sounds:onEntry({category="CONTACT"})); eq(#adapter.played,2)
  eq(adapter.played[2][1],"room"); eq(sounds.lastPlayed.MENTAL,101)
  eq(sounds.lastPlayed.ESP,nil); eq(sounds.lastPlayed.CONTACT,nil)
end)

test("stored Psycian lines use the effective channel while generic mental links stay MENTAL",function()
  local adapter={now=100,played={}}
  function adapter:epoch() return self.now end
  function adapter:playChatSound(id) self.played[#self.played+1]=id; return true end
  local sounds=assert(Sounds.new(adapter,{tabs={
    MENTAL={enabled=true},PSYCIAN={enabled=true},DRAGON={enabled=true},SECIAN={enabled=true},
  }}))
  local entries={
    {category="ESP",line=[=[You pick up Alara's Psycian link, "First." [ r-321 ]]=],expected="psycian"},
    {category="CONTACT",line=[[You pick up Alara's mental link, "Second."]],expected="mental"},
    {category="ESP",line=[[Alara (ESP): "Third."]],expected="mental"},
    {category="CONTACT",line=[[Alara thinks to you, "Fourth."]],expected="mental"},
    {category="MENTAL",line=[[You pick up Alara's mental link, "Fifth."]],expected="mental"},
    {category="PSYCIAN",line=[[You pick up Alara's Psycian link, "Sixth."]],expected="psycian"},
    {category="DRAGON",line=[[A dragon's thoughts reach you.]],expected="dragon"},
    {category="SECIAN",line=[[A Secian's thoughts reach you.]],expected="secian"},
    {category="CONTACT",line=[[You pick up Alara's Dragon link, "Ninth."]],expected="dragon"},
    {category="ESP",line=[[You pick up Alara's Secian link, "Tenth."]],expected="secian"},
    {category="DRAGON",line=[[You pick up Alara's mental link, "Eleventh."]],expected="mental"},
    {category="CONTACT",line=[=[You pick up Alara's Psycian link, "Twelfth." [ r-0 ]]=],expected="psycian"},
    {category="DRAGON",line=[=[You pick up Alara's mental link, "Thirteenth." [ r-321 ]]=],expected="mental"},
    {category="SECIAN",line=[=[Alara picks up Dace's mental link, "Fourteenth." [ r-321 ]]=],expected="mental"},
    {category="ESP",line=[[Alara says, 'You pick up Dace's Psycian link, "Quoted."']],expected="mental"},
    {category="CONTACT",line=[=[You pick up Alara's Psycian link, "Invalid rank." [ r-nope ]]=],expected="mental"},
    {category="ESP",line=[[You pick up Alara's Psycian link, "Trailing text." extra]],expected="mental"},
    {category="DRAGON",line=[=[You pick up Alara's mental link, "Invalid rank." [ r--1 ]]=],expected="dragon"},
    {category="SECIAN",line=[[You pick up Alara's mental link, "Trailing text." extra]],expected="secian"},
  }
  for index,entry in ipairs(entries) do
    local category,line=entry.category,entry.line
    adapter.now=100+index
    assert(sounds:onEntry(entry,{MENTAL=false,PSYCIAN=false,DRAGON=false,SECIAN=false}))
    eq(adapter.played[index],entry.expected)
    eq(entry.category,category); eq(entry.line,line)
  end
  local off=Sounds.defaults(); off.tabs.MENTAL.enabled=true; off.tabs.ALL.enabled=true
  assert(sounds:setConfig(off)); adapter.now=140
  eq(sounds:onEntry(entries[1],{PSYCIAN=false,MENTAL=true}),false); eq(#adapter.played,#entries)
  off.tabs.PRIVATE.enabled=true; assert(sounds:setConfig(off))
  eq(sounds:onEntry(entries[1],{PSYCIAN=false,MENTAL=true}),false); eq(#adapter.played,#entries)
  off.tabs.PSYCIAN.enabled=true; assert(sounds:setConfig(off))
  assert(sounds:onEntry(entries[1],{PSYCIAN=false,MENTAL=true})); eq(adapter.played[#entries+1],"psycian")
end)
test("sound playback is bounded per tab and preview does not change toggles",function()
  local adapter={now=100,played={}}
  function adapter:epoch() return self.now end
  function adapter:playChatSound(id,volume) self.played[#self.played+1]={id,volume}; return true end
  local sound=assert(Sounds.new(adapter))
  assert(sound:onEntry({category="STAFF"})); eq(#adapter.played,1)
  eq(sound:onEntry({category="STAFF"}),false); eq(#adapter.played,1)
  eq(sound:onEntry({category="ROOM"}),false)
  adapter.now=101; assert(sound:onEntry({category="STAFF"})); eq(#adapter.played,2)
  assert(sound:play("room")); eq(#adapter.played,3); eq(sound.config.tabs.ROOM.enabled,false)
  eq(sound:play("https://unsafe/file.wav"),nil)
  local candidate=Sounds.defaults(); candidate.tabs.STAFF.enabled=false; assert(sound:setConfig(candidate))
  adapter.now=103; eq(sound:onEntry({category="STAFF"}),false); eq(#adapter.played,3)
end)
test("missing or failing sound APIs never throw into chat",function()
  local sound=assert(Sounds.new({})); eq(sound:onEntry({category="STAFF"}),nil)
  sound=assert(Sounds.new({playChatSound=function() error("bad backend") end})); eq(sound:play("staff"),nil)
  sound=assert(Sounds.new({playChatSound=function() return false,"muted" end})); local ok,err=sound:play("staff"); eq(ok,nil); eq(err,"muted")
end)
test("sound cooldown uses fractional time across whole second boundaries",function()
  local now,count=100.99,0
  local sound=assert(Sounds.new({epoch=function() return math.floor(now) end,chatSoundTime=function() return now end,playChatSound=function() count=count+1; return true end}))
  assert(sound:onEntry({category="STAFF"})); now=101.01
  eq(sound:onEntry({category="STAFF"}),false); eq(count,1)
  now=102; assert(sound:onEntry({category="STAFF"})); eq(count,2)
end)
local function uint(data,offset,bytes)
  local value=0; for i=bytes-1,0,-1 do value=value*256+data:byte(offset+i) end; return value
end
test("twelve local tones have deterministic catalog entries and distinct bounded valid PCM WAV files",function()
  local seen,ids,files={},{},{}; eq(#Sounds.catalog,12)
  for _,record in ipairs(Sounds.catalog) do
    eq(ids[record.id],nil); ids[record.id]=true; eq(files[record.file],nil); files[record.file]=true
    eq(Sounds.get(record.id),record); assert(type(record.label)=="string" and #record.label>0)
    local wav=assert(Sounds.wav(record.id)); eq(wav:sub(1,4),"RIFF"); eq(wav:sub(9,16),"WAVEfmt "); eq(wav:sub(37,40),"data")
    eq(uint(wav,5,4),#wav-8); eq(uint(wav,41,4),#wav-44)
    eq(uint(wav,21,2),1); eq(uint(wav,23,2),1); eq(uint(wav,25,4),22050); eq(uint(wav,35,2),16)
    assert(#wav>4000 and #wav<65536); eq(seen[wav],nil); seen[wav]=true; eq(Sounds.wav(record.id),wav)
    local peak=0; for i=45,#wav,2 do local n=uint(wav,i,2); if n>=32768 then n=n-65536 end; peak=math.max(peak,math.abs(n)) end
    assert(peak>1000 and peak<16000,"tone must be audible without clipping")
    assert(record.file:match("^chat%-%l+%-v1%.wav$"))
  end
  eq(Sounds.wav("../arbitrary"),nil)
end)
