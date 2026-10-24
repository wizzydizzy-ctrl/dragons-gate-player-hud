local Settings = require("settings")
local defaults = require("defaults")

do
  test("chat size choices survive migration and cold resolution without replacing unrelated preferences",function()
    for _,schema in ipairs({0,1}) do
      for _,choice in ipairs({{size_mode="compact"},{size_mode="normal"},{size_mode="large"},{size_mode="custom",height_pixels=417}}) do
        local user={schema=schema,chat=Settings.merge(choice,{visible=false,capture_outgoing=false,personal_option="keep",
          all_sources={ROOM=false,COMBAT=true},sounds={volume=30,tabs={STAFF={enabled=false,sound="staff"}}}}),
          display={auto_wrap=false},personal="untouched"}
        local resolved,migrated=Settings.resolve(defaults,user)
        local cold=Settings.resolve(defaults,migrated)
        for _,config in ipairs({resolved,cold}) do
          eq(config.chat.size_mode,choice.size_mode); eq(config.chat.height_pixels,choice.height_pixels)
          eq(config.chat.visible,false); eq(config.chat.capture_outgoing,false)
          eq(config.chat.all_sources.ROOM,false); eq(config.chat.all_sources.COMBAT,true)
          eq(config.chat.sounds.volume,30); eq(config.chat.sounds.tabs.STAFF.enabled,false)
          eq(config.chat.personal_option,"keep"); eq(config.personal,"untouched"); eq(config.display.auto_wrap,false)
        end
        eq(user.chat.size_mode,choice.size_mode); eq(user.chat.height_pixels,choice.height_pixels)
        resolved.chat.sounds.volume=60; eq(user.chat.sounds.volume,30)
      end
    end
  end)

  test("legacy chat geometry survives settings resolution until the user explicitly resets size",function()
    local user={schema=1,chat={height_percent=.27,target_height=287,min_height=91,max_height=411,personal_option="keep"}}
    local resolved,migrated=Settings.resolve(defaults,user)
    eq(resolved.chat.size_mode,nil); eq(migrated.chat.size_mode,nil); eq(user.chat.size_mode,nil)
    for _,config in ipairs({resolved,(Settings.resolve(defaults,migrated))}) do
      eq(config.chat.height_percent,.27); eq(config.chat.target_height,287)
      eq(config.chat.min_height,91); eq(config.chat.max_height,411); eq(config.chat.personal_option,"keep")
    end
  end)

  test("malformed saved size choices normalize safely without changing other settings",function()
    for _,choice in ipairs({{size_mode="unknown",height_pixels=417},{size_mode="custom"},
      {size_mode="custom",height_pixels=0/0},{size_mode="custom",height_pixels=math.huge},
      {size_mode="custom",height_pixels=-math.huge},{size_mode="custom",height_pixels=false},
      {size_mode="normal",height_pixels=417},{height_pixels=417}}) do
      local user={schema=1,chat=Settings.merge(choice,{visible=false,capture_outgoing=false,
        all_sources={ROOM=false},personal_option="keep"}),display={auto_wrap=false}}
      local resolved=Settings.resolve(defaults,user)
      eq(resolved.chat.size_mode,"normal"); eq(resolved.chat.height_pixels,nil)
      eq(resolved.chat.visible,false); eq(resolved.chat.capture_outgoing,false)
      eq(resolved.chat.all_sources.ROOM,false); eq(resolved.chat.personal_option,"keep"); eq(resolved.display.auto_wrap,false)
      eq(user.chat.size_mode,choice.size_mode)
    end
    for _,case in ipairs({{0,80},{999,600},{"417.5",418}}) do
      local resolved=Settings.resolve(defaults,{chat={size_mode="custom",height_pixels=case[1],visible=false}})
      eq(resolved.chat.size_mode,"custom"); eq(resolved.chat.height_pixels,case[2]); eq(resolved.chat.visible,false)
    end
  end)

  local function withChatSizeFiles(run)
    local Adapter=require("mudlet_adapter")
    local previous={io=io,os=os,lfs=lfs,getMudletHomeDir=getMudletHomeDir,loadfile=loadfile}
    local files={}; local stage; local writes=0
    local path="/chat-size-test/DGHUDData/chat-settings.lua"
    local ok,err=xpcall(function()
      -- All IO is synthetic and constrained to this fixture, never a live profile.
      local function allowed(name)
        assert(name==path or name==path..".tmp" or name==path..".bak","unexpected fixture path")
      end
      io={open=function(name,mode)
        allowed(name)
        if mode=="rb" then return files[name] and {close=function() return true end} or nil,"missing" end
        eq(mode,"wb"); if stage=="open" then return nil,"synthetic open failure" end
        return {write=function(self,source)
          writes=writes+1; if stage=="write" then return nil,"synthetic write failure" end
          files[name]=source; return self
        end,close=function() if stage=="close" then return nil,"synthetic close failure" end; return true end}
      end}
      os={remove=function(name) allowed(name); files[name]=nil; return true end,
        rename=function(from,to)
          allowed(from); allowed(to)
          if stage=="replace" and from==path..".tmp" then return nil,"synthetic replace failure" end
          if files[from]==nil then return nil,"missing" end
          files[to]=files[from]; files[from]=nil; return true
        end}
      lfs={mkdir=function(name) eq(name,"/chat-size-test/DGHUDData"); return true end}
      getMudletHomeDir=function() return "/chat-size-test" end
      loadfile=function(name)
        allowed(name); if not files[name] then return nil,"missing" end
        -- Evaluate only the adapter's generated Lua settings in an empty environment.
        local loader,loadErr=loadstring(files[name]); if loader then setfenv(loader,{}) end
        return loader,loadErr
      end
      run(Adapter,files,path,function(value) stage=value end,function() return writes end)
    end,debug.traceback)
    io=previous.io; os=previous.os; lfs=previous.lfs; getMudletHomeDir=previous.getMudletHomeDir; loadfile=previous.loadfile
    if not ok then error(err,0) end
  end

  test("chat size snapshots and serialized settings round trip presets custom pixels and reset",function()
    withChatSizeFiles(function(Adapter,files,path)
      local ChatSize=require("chat_size")
      local chat={tab_order={"STAFF","ALL","ROOM"},visible=false,capture_outgoing=false,
        all_sources={ROOM=false,COMBAT=true},sounds={volume=30,tabs={STAFF={enabled=false,sound="staff"}}}}
      for _,wanted in ipairs({"compact","normal","large",80,"417.5",600,"reset"}) do
        chat=assert(ChatSize.change(chat,wanted)); assert(Adapter.new():saveChatSettings(chat))
        assert(type(files[path])=="string")
        local loaded=assert(Adapter.loadChatSettings())
        eq(loaded.size_mode,chat.size_mode); eq(loaded.height_pixels,chat.height_pixels)
        eq(loaded.visible,false); eq(loaded.capture_outgoing,false)
        eq(loaded.all_sources.ROOM,false); eq(loaded.all_sources.COMBAT,true)
        eq(loaded.tab_order[1],"STAFF"); eq(loaded.sounds.volume,30); eq(loaded.sounds.tabs.STAFF.enabled,false)
        local cold=Settings.resolve(defaults,{chat=loaded})
        eq(cold.chat.size_mode,chat.size_mode); eq(cold.chat.height_pixels,chat.height_pixels)
      end
      local legacy=assert(Adapter.chatSettingsSnapshot({tab_order={"ALL","STAFF"},visible=false}))
      eq(legacy.size_mode,nil); eq(legacy.height_pixels,nil)
    end)
  end)

  test("failed serialized chat size saves keep the prior bytes and requested height",function()
    withChatSizeFiles(function(Adapter,files,path,fail,writes)
      local ChatSize=require("chat_size")
      local prior={size_mode="custom",height_pixels=417,tab_order={"ALL","STAFF"},visible=false,capture_outgoing=false}
      assert(Adapter.new():saveChatSettings(prior)); local saved=files[path]
      local candidate=assert(ChatSize.change(prior,"large"))
      for _,stage in ipairs({"open","write","close","replace"}) do
        fail(stage)
        local result,err=Adapter.new():saveChatSettings(candidate)
        eq(result,nil); eq(type(err),"string"); eq(files[path],saved)
        local loaded=assert(Adapter.loadChatSettings())
        eq(loaded.size_mode,"custom"); eq(loaded.height_pixels,417); eq(loaded.visible,false); eq(loaded.capture_outgoing,false)
      end
      fail(nil); local before=writes()
      eq(ChatSize.change(prior,math.huge),nil); eq(writes(),before); eq(files[path],saved)
    end)
  end)
end

test("new chat and visibility choices survive repeat resolution without changing update preference",function()
  for _,value in ipairs({false,true}) do
    local user={schema=1,chat={capture_outgoing=value,combine_links=value,combined_tab_order={"STAFF","LINK VIEW","ALL"}},
      display={visibility_status=value,auto_wrap=false},update={auto_apply=true}}
    local resolved,migrated=Settings.resolve(defaults,user)
    local cold=Settings.resolve(defaults,migrated)
    eq(cold.chat.capture_outgoing,value); eq(cold.chat.combine_links,true); eq(cold.display.visibility_status,value)
    eq(cold.display.auto_wrap,false); eq(cold.update.auto_apply,true)
    eq(table.concat(cold.chat.combined_tab_order,","),"STAFF,"..require("chat_channels").linkFilter..",ALL")
    eq(table.concat(user.chat.combined_tab_order,","),"STAFF,LINK VIEW,ALL")
  end
  eq(defaults.chat.capture_outgoing,true); eq(defaults.chat.combine_links,true); eq(defaults.display.visibility_status,true)
end)

test("mental tab migration preserves unrelated choices and explicit OFF on repeated loads",function()
  local user={schema=1,chat={visible=false,tab_order={"STAFF","CONTACT","DRAGON","ESP","ALL"},
    all_sources={ESP=false,CONTACT=false,COMBAT=true,ROOM=false},sounds={volume=35}},update={auto_apply=true}}
  local resolved,migrated=Settings.resolve(defaults,user)
  eq(table.concat(migrated.chat.tab_order,","),"STAFF,MENTAL,DRAGON,ALL")
  eq(table.concat(user.chat.tab_order,","),"STAFF,CONTACT,DRAGON,ESP,ALL")
  eq(user.chat.all_sources.ESP,false); eq(migrated.chat.all_sources.ESP,nil)
  eq(resolved.chat.visible,false); eq(resolved.chat.all_sources.MENTAL,false); eq(resolved.chat.all_sources.PSYCIAN,false)
  eq(resolved.chat.all_sources.COMBAT,true); eq(resolved.chat.all_sources.ROOM,false)
  eq(resolved.update.auto_apply,true)
  local cold=Settings.resolve(defaults,migrated)
  eq(cold.chat.all_sources.MENTAL,false); eq(cold.chat.all_sources.PSYCIAN,false)
  eq(table.concat(cold.chat.tab_order,","),table.concat(resolved.chat.tab_order,","))
  local explicit=Settings.resolve(defaults,{schema=1,chat={all_sources={MENTAL=false,PSYCIAN=false,ESP=true,CONTACT=true}}})
  eq(explicit.chat.all_sources.MENTAL,false); eq(explicit.chat.all_sources.PSYCIAN,false)
end)

test("quick commands default ON for fresh and legacy display settings without mutating input",function()
  for _,key in ipairs({"shoprenew","shoprenewall","trainall"}) do eq(defaults.display[key],true) end
  for _,schema in ipairs({0,1}) do
    local user={schema=schema,display={main_skills=false,skill_filter=false,auto_wrap=false,personal="keep",
      main_skill_sort={primary="uses",direction="asc",secondary="name",secondary_direction="desc"}}}
    local resolved,migrated=Settings.resolve(defaults,user)
    for _,key in ipairs({"shoprenew","shoprenewall","trainall"}) do
      eq(resolved.display[key],true); eq(user.display[key],nil); eq(migrated.display[key],nil)
      eq(Settings.resolve(defaults,migrated).display[key],true)
    end
    eq(resolved.display.main_skills,false); eq(resolved.display.skill_filter,false)
    eq(resolved.display.auto_wrap,false); eq(resolved.display.personal,"keep")
    eq(resolved.display.main_skill_sort.primary,"uses"); eq(resolved.display.main_skill_sort.secondary_direction,"desc")
    eq(resolved.version,defaults.version)
  end
end)

test("quick command booleans resolve independently and explicit false survives cold resolution",function()
  for _,shoprenew in ipairs({false,true}) do
    for _,shoprenewall in ipairs({false,true}) do
      for _,trainall in ipairs({false,true}) do
        local display={shoprenew=shoprenew,shoprenewall=shoprenewall,trainall=trainall,personal="keep"}
        for _,schema in ipairs({0,1}) do
          local user={schema=schema,display=display}
          local resolved,migrated=Settings.resolve(defaults,user)
          local cold=Settings.resolve(defaults,migrated)
          for _,key in ipairs({"shoprenew","shoprenewall","trainall"}) do
            eq(resolved.display[key],display[key]); eq(cold.display[key],display[key])
            eq(migrated.display[key],display[key]); eq(defaults.display[key],true)
          end
          resolved.display.trainall=not trainall; eq(display.trainall,trainall)
          eq(resolved.display.personal,"keep")
        end
      end
    end
  end
end)

test("invalid quick command values normalize to ON without erasing other saved choices",function()
  for _,key in ipairs({"shoprenew","shoprenewall","trainall"}) do
    for _,invalid in ipairs({"false","true",0,1,{},function() end}) do
      local display={shoprenew=false,shoprenewall=false,trainall=false,skill_filter=false,personal="keep"}
      display[key]=invalid
      local resolved=Settings.resolve(defaults,{schema=1,display=display})
      for _,other in ipairs({"shoprenew","shoprenewall","trainall"}) do eq(resolved.display[other],other==key) end
      eq(display[key],invalid); eq(resolved.display.skill_filter,false); eq(resolved.display.personal,"keep")
    end
  end
  for _,invalid in ipairs({false,"invalid",1}) do
    local resolved=Settings.resolve(defaults,{display=invalid})
    for _,key in ipairs({"shoprenew","shoprenewall","trainall"}) do eq(resolved.display[key],true) end
  end
end)

test("combined skills and runes defaults migrate without changing unrelated preferences",function()
  eq(defaults.display.combine_skills_runes,true); eq(defaults.display.skills_runes_tab,"skills")
  for _,schema in ipairs({0,1}) do
    local user={schema=schema,display={auto_wrap=false,personal="keep"},update={auto_apply=true}}
    local resolved,migrated=Settings.resolve(defaults,user)
    eq(resolved.display.combine_skills_runes,true); eq(resolved.display.skills_runes_tab,"skills")
    eq(resolved.display.auto_wrap,false); eq(resolved.display.personal,"keep")
    eq(user.display.combine_skills_runes,nil); eq(user.display.skills_runes_tab,nil)
    eq(Settings.resolve(defaults,migrated).display.skills_runes_tab,"skills")
    if schema==1 then eq(resolved.update.auto_apply,true) end
  end
end)

test("combined panel explicit choices survive resolution and invalid new fields cannot erase old choices",function()
  for _,enabled in ipairs({false,true}) do
    for _,tab in ipairs({"skills","runes"}) do
      local user={schema=1,display={combine_skills_runes=enabled,skills_runes_tab=tab,skill_filter=false,personal="keep"},update={auto_apply=true}}
      local resolved,migrated=Settings.resolve(defaults,user)
      eq(resolved.display.combine_skills_runes,enabled); eq(resolved.display.skills_runes_tab,tab)
      eq(Settings.resolve(defaults,migrated).display.combine_skills_runes,enabled); eq(Settings.resolve(defaults,migrated).display.skills_runes_tab,tab)
      eq(user.display.skills_runes_tab,tab); eq(resolved.display.skill_filter,false); eq(resolved.display.personal,"keep"); eq(resolved.update.auto_apply,true)
    end
  end
  for _,invalid in ipairs({"invalid",0,{},function() end}) do
    local resolved=Settings.resolve(defaults,{schema=1,display={combine_skills_runes=invalid,skills_runes_tab=invalid,auto_wrap=false},update={auto_apply=true}})
    eq(resolved.display.combine_skills_runes,true); eq(resolved.display.skills_runes_tab,"skills"); eq(resolved.display.auto_wrap,false); eq(resolved.update.auto_apply,true)
  end
  eq(Settings.resolve(defaults,{display=false}).display.combine_skills_runes,true)
  eq(defaults.display.combine_skills_runes,true); eq(defaults.display.skills_runes_tab,"skills")
end)

test("skill filters default on and explicit choices survive migration and cold resolution",function()
  eq(defaults.display.skill_filter,true)
  for _,schema in ipairs({0,1}) do
    local legacy={schema=schema,display={main_skills=false,auto_wrap=false,personal="keep"}}
    eq(Settings.resolve(defaults,legacy).display.skill_filter,true); eq(legacy.display.skill_filter,nil)
    for _,enabled in ipairs({false,true}) do
      local user=Settings.merge(legacy,{display={skill_filter=enabled}})
      local resolved,migrated=Settings.resolve(defaults,user)
      eq(resolved.display.skill_filter,enabled); eq(migrated.display.skill_filter,enabled)
      eq(Settings.resolve(defaults,migrated).display.skill_filter,enabled)
      eq(resolved.display.main_skills,false); eq(resolved.display.auto_wrap,false); eq(resolved.display.personal,"keep")
      eq(user.display.skill_filter,enabled); eq(defaults.display.skill_filter,true)
    end
  end
end)

test("skill filter display snapshots default legacy values on and reject non boolean values",function()
  local Adapter=require("mudlet_adapter")
  eq(assert(Adapter.displaySettingsSnapshot({side_text_scale=1})).skill_filter,true)
  for _,enabled in ipairs({false,true}) do
    local config={side_text_scale=.9,main_skills=false,align_input=true,auto_wrap=false,skill_filter=enabled}
    local snapshot=assert(Adapter.displaySettingsSnapshot(config))
    eq(snapshot.skill_filter,enabled); eq(snapshot.main_skills,false); eq(snapshot.align_input,true); eq(snapshot.auto_wrap,false)
    snapshot.skill_filter=not enabled; eq(config.skill_filter,enabled)
  end
  for _,invalid in ipairs({"false","true",0,1,{},function() end}) do
    local result,err=Adapter.displaySettingsSnapshot({side_text_scale=1,skill_filter=invalid})
    eq(result,nil); assert(err:find("boolean",1,true))
  end
end)

test("skill filter serialized settings round trip and failed writes retain the last saved choice",function()
  local Adapter=require("mudlet_adapter")
  local previous={io=io,os=os,lfs=lfs,getMudletHomeDir=getMudletHomeDir,loadfile=loadfile}
  local files={}; local failure; local writes=0
  local path="/skill-filter-test/DGHUDData/display-settings.lua"
  local ok,err=xpcall(function()
    -- Only synthetic files exist in this fixture; no profile or real disk access.
    io={open=function(name,mode)
      if mode=="rb" then return files[name] and {close=function() return true end} or nil,"missing" end
      eq(mode,"wb")
      if failure=="open" then return nil,"open failed" end
      return {write=function(self,source)
        writes=writes+1
        if failure=="write" then return nil,"write failed" end
        files[name]=source; return self
      end,close=function() if failure=="close" then return nil,"close failed" end; return true end}
    end}
    os={remove=function(name) files[name]=nil; return true end,rename=function(from,to)
      if failure=="replace" and from==path..".tmp" then return nil,"replace failed" end
      if files[from]==nil then return nil,"missing" end
      files[to]=files[from]; files[from]=nil; return true
    end}
    lfs={mkdir=function() return true end}
    getMudletHomeDir=function() return "/skill-filter-test" end
    loadfile=function(name) if not files[name] then return nil,"missing" end; return loadstring(files[name]) end
    files[path]="return {side_text_scale=1,main_skills=false,auto_wrap=false}"
    eq(assert(Adapter.loadDisplaySettings()).skill_filter,true)
    local config={side_text_scale=.9,main_skills=false,auto_wrap=false,align_input=true,skill_filter=true}
    for _,enabled in ipairs({false,true}) do
      config.skill_filter=enabled; assert(Adapter.new():saveDisplaySettings(config))
      assert(files[path]:find("skill_filter="..tostring(enabled),1,true))
      local loaded=assert(Adapter.loadDisplaySettings())
      eq(loaded.skill_filter,enabled); eq(loaded.main_skills,false); eq(loaded.auto_wrap,false); eq(loaded.align_input,true)
      eq(Settings.resolve(defaults,{display=loaded}).display.skill_filter,enabled)
    end
    config.skill_filter=false; assert(Adapter.new():saveDisplaySettings(config))
    local saved=files[path]; config.skill_filter=true
    for _,stage in ipairs({"open","write","close","replace"}) do
      failure=stage; eq(Adapter.new():saveDisplaySettings(config),nil); eq(files[path],saved)
      eq(assert(Adapter.loadDisplaySettings()).skill_filter,false)
    end
    failure=nil; local before=writes; config.skill_filter="false"
    eq(Adapter.new():saveDisplaySettings(config),nil); eq(writes,before); eq(files[path],saved)
  end,debug.traceback)
  io=previous.io; os=previous.os; lfs=previous.lfs; getMudletHomeDir=previous.getMudletHomeDir; loadfile=previous.loadfile
  if not ok then error(err,0) end
end)

test("display skill ordering defaults and persisted choices resolve independently without changing callers",function()
  local input={display={main_skills=false,auto_wrap=false,personal="keep",
    main_skill_sort={primary="uses",direction="asc",secondary="level",secondary_direction="desc"},
    sidebar_skill_sort={primary="category",direction="desc",secondary="name",secondary_direction="asc"}}}
  local resolved,migrated=Settings.resolve(defaults,input)
  eq(resolved.display.main_skills,false); eq(resolved.display.personal,"keep")
  eq(resolved.display.main_skill_sort.primary,"uses"); eq(resolved.display.sidebar_skill_sort.primary,"category")
  local restarted=Settings.resolve(defaults,migrated)
  eq(restarted.display.main_skill_sort.secondary_direction,"desc"); eq(restarted.display.sidebar_skill_sort.direction,"desc")
  resolved.display.main_skill_sort.primary="number"; eq(input.display.main_skill_sort.primary,"uses")
  eq(defaults.display.main_skill_sort.primary,"level")
  local invalid=Settings.resolve(defaults,{display={auto_wrap=false,main_skills=false,main_skill_sort=false,sidebar_skill_sort={primary="invalid"}}})
  eq(invalid.display.auto_wrap,false); eq(invalid.display.main_skills,false)
  eq(invalid.display.main_skill_sort.primary,"level"); eq(invalid.display.sidebar_skill_sort.primary,"level")
end)


test("WORLD defaults to its own tab and inclusion in ALL for fresh and older settings",function()
  eq(defaults.chat.all_sources.WORLD,true)
  local count=0; for _,tab in ipairs(defaults.chat.tab_order) do if tab=="WORLD" then count=count+1 end end
  eq(count,1)
  local legacyOrder={"STAFF","ALL","ROOM","PRIVATE","ESP","DRAGON","CONTACT","COMBAT"}
  for _,user in ipairs({{}, {schema=0,chat={tab_order=legacyOrder,all_sources={COMBAT=false}}},
    {schema=1,chat={tab_order={"STAFF","ALL","ROOM"},all_sources={ROOM=false}}}}) do
    local resolved=Settings.resolve(defaults,user)
    eq(resolved.chat.all_sources.WORLD,true)
    -- Legacy ESP/CONTACT positions combine once; View adds missing built-ins.
    if not user.chat then eq(table.concat(resolved.chat.tab_order,","),table.concat(defaults.chat.tab_order,",")) end
    for index,tab in ipairs(require("chat_channels").tabOrder(user.chat and user.chat.tab_order or {})) do eq(resolved.chat.tab_order[index],tab) end
    if user.chat then eq(user.chat.all_sources.WORLD,nil) end
  end
  eq(table.concat(legacyOrder,","),"STAFF,ALL,ROOM,PRIVATE,ESP,DRAGON,CONTACT,COMBAT")
end)

test("explicit WORLD false survives migration and repeated resolution without disabling its tab",function()
  for _,schema in ipairs({0,1}) do
    local user={schema=schema,chat={tab_order={"WORLD","STAFF","ALL","ROOM"},all_sources={WORLD=false,ROOM=false,COMBAT=true},personal_option="keep"}}
    local resolved,migrated=Settings.resolve(defaults,user)
    eq(resolved.chat.all_sources.WORLD,false); eq(migrated.chat.all_sources.WORLD,false); eq(user.chat.all_sources.WORLD,false)
    eq(resolved.chat.all_sources.ROOM,false); eq(resolved.chat.all_sources.COMBAT,true); eq(resolved.chat.enabled,true)
    eq(resolved.chat.tab_order[1],"WORLD"); eq(resolved.chat.tab_order[2],"STAFF")
    eq(resolved.chat.personal_option,"keep")
    local reloaded=Settings.resolve(defaults,migrated)
    eq(reloaded.chat.all_sources.WORLD,false); eq(reloaded.chat.tab_order[1],"WORLD")
    eq(defaults.chat.all_sources.WORLD,true)
  end
end)
test("saved roller thresholds migrate by characteristic slot without changing the original",function()
  local old={schema=1,roller={min_stats={VOI=7,APP=6,INT=5}}}
  local resolved,migrated,changed=Settings.resolve(defaults,old)
  eq(changed,true); eq(resolved.roller.min_stats.PRE,7); eq(resolved.roller.min_stats.LUK,6)
  eq(migrated.roller.min_stats.VOI,7); eq(migrated.roller.min_stats.APP,6)
  eq(old.roller.min_stats.PRE,nil); eq(old.roller.min_stats.LUK,nil)
  local newer=Settings.resolve(defaults,{schema=1,roller={min_stats={VOI=7,APP=6,PRE=4,LUK=false}}})
  eq(newer.roller.min_stats.PRE,4); eq(newer.roller.min_stats.LUK,false)
end)

test("input alignment is opt-in and saved choices survive settings resolution",function()
  eq(defaults.display.align_input,false)
  eq(Settings.resolve(defaults,{}).display.align_input,false)
  local resolved=Settings.resolve(defaults,{display={align_input=true,auto_wrap=false}})
  eq(resolved.display.align_input,true); eq(resolved.display.auto_wrap,false)
  eq(Settings.resolve(defaults,resolved).display.align_input,true)
end)

test("chat visibility defaults on for fresh and legacy settings",function()
  eq(defaults.chat.visible,true)
  for _,user in ipairs({{}, {schema=0,chat={tab_order={"STAFF","ALL"},all_sources={COMBAT=false},personal_option="keep"}}, {schema=1,chat={timestamps=false}}}) do
    local resolved=Settings.resolve(defaults,user)
    eq(resolved.chat.visible,true); eq(resolved.chat.enabled,true)
    eq(user.chat and user.chat.visible,nil)
    if user.chat and user.chat.personal_option then
      eq(resolved.chat.personal_option,"keep"); eq(resolved.chat.tab_order[1],"STAFF"); eq(resolved.chat.all_sources.COMBAT,false)
    end
  end
end)

test("chat visibility survives migration and repeated resolution without changing capture or defaults",function()
  for _,schema in ipairs({0,1}) do
    for _,visible in ipairs({false,true}) do
      local user={schema=schema,personal="untouched",chat={visible=visible,tab_order={"STAFF","ALL"},all_sources={ROOM=false,COMBAT=true},personal_option="keep"}}
      local resolved,migrated=Settings.resolve(defaults,user)
      eq(resolved.chat.visible,visible); eq(migrated.chat.visible,visible); eq(user.chat.visible,visible)
      eq(resolved.chat.enabled,true); eq(resolved.chat.visible_limit,1000); eq(resolved.chat.timestamps,true)
      eq(resolved.chat.tab_order[1],"STAFF"); eq(resolved.chat.all_sources.ROOM,false); eq(resolved.chat.all_sources.COMBAT,true)
      eq(resolved.chat.personal_option,"keep"); eq(resolved.personal,"untouched")
      local reloaded=Settings.resolve(defaults,migrated); eq(reloaded.chat.visible,visible); eq(defaults.chat.visible,true)
    end
  end
end)


test("merges nested overrides without changing defaults", function()
  local defaults={schema=1,theme={accent="#aa8844",panel="#111111"},github={owner="OWNER"}}
  local merged=Settings.merge(defaults,{theme={accent="#00ff00"},custom="keep"})
  eq(merged.theme.accent,"#00ff00"); eq(merged.theme.panel,"#111111"); eq(merged.custom,"keep"); eq(defaults.theme.accent,"#aa8844")
end)

test("mapper settings merge without removing user overrides",function()
  local merged=Settings.merge(defaults,{mapper={walk_timeout=20,personal_option="keep"},personal="untouched"})
  eq(merged.mapper.enabled,true); eq(merged.mapper.walk_timeout,20); eq(merged.mapper.minimum_height,90); eq(merged.mapper.schema,2)
  eq(merged.mapper.personal_option,"keep"); eq(merged.personal,"untouched")
end)

test("special submap creation defaults off while explicit choices survive resolution",function()
  local fresh=Settings.resolve(defaults,{})
  for _,key in ipairs({"gate","portal","door","arch","path","other"}) do eq(fresh.mapper.transition_submaps[key],false) end
  local resolved=Settings.resolve(defaults,{mapper={transition_submaps={door=true}}})
  eq(resolved.mapper.transition_submaps.door,true)
  for _,key in ipairs({"gate","portal","arch","path","other"}) do eq(resolved.mapper.transition_submaps[key],false) end
end)

test("mapper settings survive migration with unknown nested values",function()
  local resolved,migrated,changed=Settings.resolve(defaults,{schema=0,mapper={walk_timeout=19,future_option="keep"},future_root={value=7}})
  eq(changed,true); eq(migrated.mapper.future_option,"keep"); eq(resolved.mapper.enabled,true); eq(resolved.mapper.walk_timeout,19)
  eq(resolved.mapper.future_option,"keep"); eq(resolved.future_root.value,7)
end)

test("migrates schema zero while preserving unknown keys", function()
  local migrated,changed=Settings.migrate({schema=0,auto_update=true,personal="untouched"})
  eq(changed,true); eq(migrated.schema,1); eq(migrated.update.auto_apply,false); eq(migrated.personal,"untouched")
end)

test("chat settings retain defaults around migrated user overrides",function()
  local user={schema=0,auto_update=true,personal="untouched",chat={height_percent=.25,personal_option="keep"}}
  local migrated,changed=Settings.migrate(user)
  local merged=Settings.merge(defaults,migrated)
  eq(changed,true); eq(merged.chat.enabled,true); eq(merged.chat.height_percent,.25); eq(merged.chat.target_height,240)
  eq(merged.chat.min_height,160); eq(merged.chat.max_height,320); eq(merged.chat.visible_limit,1000)
  eq(merged.chat.dedupe_seconds,3); eq(merged.chat.timestamps,true); eq(merged.chat.personal_option,"keep")
  eq(merged.personal,"untouched"); eq(user.chat.personal_option,"keep")
end)

test("resolves migrated chat settings without discarding user keys",function()
  local resolved,migrated,changed=Settings.resolve(defaults,{schema=0,chat={timestamps=false,personal_option="keep"},personal="untouched"})
  eq(changed,true); eq(resolved.chat.timestamps,false); eq(resolved.chat.visible_limit,1000)
  eq(migrated.chat.personal_option,"keep"); eq(resolved.personal,"untouched")
end)

test("release identity cannot be replaced by stale persisted preferences",function()
  local installed={schema=1,view_schema=4,view_contract=string.rep("a",64),edition="player",package_name="DragonsGateHUD",version="2.0.0",github={owner="safe",repository="player"},theme={accent="#112233"}}
  local resolved,migrated=Settings.resolve(installed,{view_schema=1,view_contract=string.rep("b",64),edition="staff",package_name="Other",version="1.0.0",github={owner="other",repository="other"},theme={accent="#abcdef"},personal="kept"})
  eq(resolved.view_schema,4); eq(resolved.view_contract,string.rep("a",64)); eq(resolved.edition,"player")
  eq(resolved.package_name,"DragonsGateHUD"); eq(resolved.version,"2.0.0"); eq(resolved.github.owner,"safe"); eq(resolved.github.repository,"player")
  eq(resolved.theme.accent,"#abcdef"); eq(resolved.personal,"kept"); eq(migrated.version,"1.0.0")
end)

test("view settings contract is deterministic and changes with the resolved theme",function()
  local a=Settings.viewSettingsContract({theme={text="#ffffff",panel="#000000"}})
  local b=Settings.viewSettingsContract({theme={panel="#000000",text="#ffffff"}})
  local c=Settings.viewSettingsContract({theme={panel="#000000",text="#eeeeee"}})
  eq(#a,64); eq(a,b); eq(a==c,false)
end)

test("colorization defaults enabled and preserves unrelated overrides",function()
  local resolved,migrated=Settings.resolve(defaults,{personal="untouched",colorization={exits_enabled=false,personal_option="keep"}})
  eq(resolved.colorization.enabled,true); eq(resolved.colorization.room_enabled,true); eq(resolved.colorization.exits_enabled,false); eq(resolved.colorization.currency_enabled,true); eq(resolved.colorization.personal_option,"keep")
  eq(migrated.personal,"untouched"); eq(migrated.colorization.personal_option,"keep")
end)

test("legacy highlight preference migrates to every individual category",function()
  local resolved,migrated,changed=Settings.resolve(defaults,{colorization={highlights_enabled=false}})
  eq(changed,true)
  for _,name in ipairs({"portal","presence","attack","damage","danger","recovery","upkeep","spell","discovery","illumination","notice","world","skills"}) do
    eq(migrated.colorization[name.."_enabled"],false); eq(resolved.colorization[name.."_enabled"],false)
  end
end)
test("explicit skill color preference survives legacy-group migration and resolution",function()
  for _,enabled in ipairs({true,false}) do
    local resolved,migrated=Settings.resolve(defaults,{colorization={highlights_enabled=not enabled,skills_enabled=enabled}})
    eq(resolved.colorization.skills_enabled,enabled); eq(migrated.colorization.skills_enabled,enabled)
    local restarted=Settings.resolve(defaults,migrated); eq(restarted.colorization.skills_enabled,enabled)
  end
end)

test("colorization persistence helper changes only its enabled override",function()
  local user={personal="untouched",colorization={personal_option="keep"}}
  local result=Settings.setColorEnabled(user,false)
  eq(result,user); eq(user.colorization.enabled,false); eq(user.colorization.personal_option,"keep"); eq(user.personal,"untouched")
  eq(Settings.colorEnabled(Settings.merge(defaults,user)),false)
  Settings.setColorEnabled(user,true); eq(Settings.colorEnabled(Settings.merge(defaults,user)),true)
end)
