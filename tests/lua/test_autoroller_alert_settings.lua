local Audio=require("autoroller_audio")
local Adapter=require("mudlet_adapter")
local Settings=require("settings")
local defaults=require("defaults")
test("old roller settings acquire alert defaults without losing saved roll requirements",function()
  local config={target_total=65,hard_stop=70,auto_start_on_name=false,min_stats={STR=6}}
  local snapshot=assert(Adapter.rollerSettingsSnapshot(config))
  eq(snapshot.alerts.enabled,true); eq(snapshot.alerts.volume,75); eq(snapshot.alerts.sound,"three_tone")
  eq(snapshot.alerts.repeat_enabled,false); eq(snapshot.target_total,65); eq(snapshot.min_stats.STR,6)
  eq(config.alerts,nil); eq(snapshot.schema,4)
end)
test("roller sound settings serialized source preserves off and custom choices",function()
  local config={target_total=53,alerts={enabled=false,volume=95,repeat_enabled=true,sound="custom",
    custom_file=string.rep("a",64)..".wav",custom_name="Fiora's train horn.wav"},min_stats={}}
  local source=assert(Adapter.rollerSettingsSource(config)); local compile=loadstring or load
  local loaded=assert(compile(source))(); eq(loaded.alerts.enabled,false); eq(loaded.alerts.volume,95)
  eq(loaded.alerts.repeat_enabled,true); eq(loaded.alerts.custom_name,assert(Audio.validate(config.alerts)).custom_name)
  eq(loaded.alerts.custom_file,config.alerts.custom_file); eq(loaded.target_total,53)
  local resolved=Settings.resolve(defaults,{schema=1,roller=loaded}); eq(resolved.roller.alerts.enabled,false)
  eq(resolved.roller.alerts.sound,"custom"); eq(resolved.roller.alerts.custom_file,loaded.alerts.custom_file)
  eq(defaults.roller.alerts.enabled,true); eq(defaults.roller.alerts.volume,75)
end)
test("invalid roller sound settings cannot be serialized into executable paths",function()
  for _,alerts in ipairs({{sound="https://bad/file.wav"},{volume=0},{enabled="yes"},
    {sound="custom",custom_file="../../other.lua",custom_name="file.wav"}}) do
    eq(Adapter.rollerSettingsSnapshot({alerts=alerts}),nil); eq(Adapter.rollerSettingsSource({alerts=alerts}),nil)
  end
end)
test("roller saved sounds survive repeated settings resolution and every character",function()
  for _,enabled in ipairs({true,false}) do
    local saved={schema=1,roller={target_total=61,min_stats={STR=7},alerts={enabled=enabled,sound="alarm",volume=40,repeat_enabled=true}}}
    local resolved,migrated=Settings.resolve(defaults,saved)
    local cold=Settings.resolve(defaults,migrated)
    for _,settings in ipairs({resolved,cold,(Settings.resolve(defaults,saved))}) do
      eq(settings.roller.alerts.enabled,enabled); eq(settings.roller.alerts.sound,"alarm")
      eq(settings.roller.alerts.volume,40); eq(settings.roller.alerts.repeat_enabled,true); eq(settings.roller.target_total,61)
    end
  end
end)
