local Adapter=require("mudlet_adapter")
local Settings=require("settings")

test("quick command snapshots default ON and preserve independent explicit OFF values",function()
  local legacy=assert(Adapter.displaySettingsSnapshot({side_text_scale=1}))
  for _,key in ipairs({"shoprenew","shoprenewall","trainall"}) do
    eq(legacy[key],true)
    local config={side_text_scale=1,[key]=false}; local snapshot=assert(Adapter.displaySettingsSnapshot(config))
    eq(snapshot[key],false)
    for _,invalid in ipairs({"false",0,1,{},function() end}) do
      config[key]=invalid; eq(Adapter.displaySettingsSnapshot(config),nil)
    end
  end
end)

test("combined display snapshot defaults legacy fields and validates exact enum types",function()
  local legacy=assert(Adapter.displaySettingsSnapshot({side_text_scale=1}))
  eq(legacy.combine_skills_runes,true); eq(legacy.skills_runes_tab,"skills")
  for _,enabled in ipairs({false,true}) do
    for _,tab in ipairs({"skills","runes"}) do
      local config={side_text_scale=.9,combine_skills_runes=enabled,skills_runes_tab=tab,skill_filter=false,main_skills=false,auto_wrap=false,align_input=true}
      local snapshot=assert(Adapter.displaySettingsSnapshot(config))
      eq(snapshot.combine_skills_runes,enabled); eq(snapshot.skills_runes_tab,tab)
      eq(snapshot.skill_filter,false); eq(snapshot.main_skills,false); eq(snapshot.auto_wrap,false); eq(snapshot.align_input,true)
      snapshot.skills_runes_tab="changed"; eq(config.skills_runes_tab,tab)
    end
  end
  for _,invalid in ipairs({"false","true",0,1,{},function() end}) do eq(Adapter.displaySettingsSnapshot({side_text_scale=1,combine_skills_runes=invalid}),nil) end
  for _,invalid in ipairs({"SKILLS","RUNES","","runes; os.execute()",false,true,0,{},function() end}) do eq(Adapter.displaySettingsSnapshot({side_text_scale=1,skills_runes_tab=invalid}),nil) end
end)

test("combined settings serialize privately per profile and retain saved choices on every write failure",function()
  local previous={io=io,os=os,lfs=lfs,getMudletHomeDir=getMudletHomeDir,loadfile=loadfile}
  local files={}; local failure; local writes=0; local home="/combined-settings-profile-a"
  local function destination() return home.."/DGHUDData/display-settings.lua" end
  local ok,err=xpcall(function()
    io={open=function(name,mode)
      if mode=="rb" then return files[name] and {close=function() return true end} or nil,"missing" end
      eq(name,destination()..".tmp"); eq(mode,"wb")
      if failure=="open" then return nil,"open failed" end
      return {write=function(self,source)
        writes=writes+1; if failure=="write" then return nil,"write failed" end
        files[name]=source; return self
      end,close=function() if failure=="close" then return nil,"close failed" end; return true end}
    end}
    os={remove=function(name) files[name]=nil; return true end,rename=function(from,to)
      if failure=="backup" and from==destination() then return nil,"backup failed" end
      if failure=="replace" and from==destination()..".tmp" then return nil,"replace failed" end
      if files[from]==nil then return nil,"missing" end
      files[to]=files[from]; files[from]=nil; return true
    end}
    lfs={mkdir=function(base) eq(base,home.."/DGHUDData"); return true end}
    getMudletHomeDir=function() return home end
    loadfile=function(name) if not files[name] then return nil,"missing" end; return loadstring(files[name]) end
    local config={side_text_scale=.9,combine_skills_runes=false,skills_runes_tab="runes",auto_wrap=false,align_input=true,main_skills=false,skill_filter=false,shoprenew=false,shoprenewall=true,trainall=false}
    for _,enabled in ipairs({false,true}) do
      for _,tab in ipairs({"skills","runes"}) do
        config.combine_skills_runes=enabled; config.skills_runes_tab=tab; assert(Adapter.new():saveDisplaySettings(config))
        local loaded=assert(Adapter.loadDisplaySettings()); eq(loaded.combine_skills_runes,enabled); eq(loaded.skills_runes_tab,tab)
        eq(loaded.auto_wrap,false); eq(loaded.align_input,true); eq(loaded.main_skills,false); eq(loaded.skill_filter,false)
        eq(loaded.shoprenew,false); eq(loaded.shoprenewall,true); eq(loaded.trainall,false)
        local resolved=Settings.resolve(require("defaults"),{schema=1,display=loaded,update={auto_apply=true}})
        eq(resolved.display.skills_runes_tab,tab); eq(resolved.display.combine_skills_runes,enabled); eq(resolved.update.auto_apply,true)
      end
    end
    config.combine_skills_runes=false; config.skills_runes_tab="runes"; assert(Adapter.new():saveDisplaySettings(config))
    local first=files[destination()]
    home="/combined-settings-profile-b"; config.combine_skills_runes=true; config.skills_runes_tab="skills"; assert(Adapter.new():saveDisplaySettings(config))
    eq(assert(Adapter.loadDisplaySettings()).skills_runes_tab,"skills")
    home="/combined-settings-profile-a"; eq(files[destination()],first); eq(assert(Adapter.loadDisplaySettings()).skills_runes_tab,"runes")
    for _,stage in ipairs({"open","write","close","backup","replace"}) do
      failure=stage; local result=Adapter.new():saveDisplaySettings(config); eq(result,nil); eq(files[destination()],first)
      local loaded=assert(Adapter.loadDisplaySettings()); eq(loaded.combine_skills_runes,false); eq(loaded.skills_runes_tab,"runes")
      eq(loaded.shoprenew,false); eq(loaded.shoprenewall,true); eq(loaded.trainall,false)
    end
    failure=nil; local before=writes
    config.skills_runes_tab="runes; error('injection')"; eq(Adapter.new():saveDisplaySettings(config),nil); eq(writes,before); eq(files[destination()],first)
    config.skills_runes_tab="skills"; config.combine_skills_runes="false"; eq(Adapter.new():saveDisplaySettings(config),nil); eq(writes,before)
    files[destination()]="return {side_text_scale=.9,auto_wrap=false,align_input=true,main_skills=false,skill_filter=false,combine_skills_runes='invalid',skills_runes_tab='INVALID'}"
    local legacy=assert(Adapter.loadDisplaySettings())
    eq(legacy.shoprenew,true); eq(legacy.shoprenewall,true); eq(legacy.trainall,true)
    eq(legacy.combine_skills_runes,true); eq(legacy.skills_runes_tab,"skills"); eq(legacy.auto_wrap,false); eq(legacy.align_input,true); eq(legacy.main_skills,false); eq(legacy.skill_filter,false)
    files[destination()]="return {side_text_scale=1,auto_wrap=false}"
    eq(assert(Adapter.loadDisplaySettings()).combine_skills_runes,true); eq(assert(Adapter.loadDisplaySettings()).skills_runes_tab,"skills")
  end,debug.traceback)
  io=previous.io; os=previous.os; lfs=previous.lfs; getMudletHomeDir=previous.getMudletHomeDir; loadfile=previous.loadfile
  if not ok then error(err,0) end
end)
