local Settings = require("settings")
local defaults = require("defaults")

test("merges nested overrides without changing defaults", function()
  local defaults={schema=1,theme={accent="#aa8844",panel="#111111"},github={owner="OWNER"}}
  local merged=Settings.merge(defaults,{theme={accent="#00ff00"},custom="keep"})
  eq(merged.theme.accent,"#00ff00"); eq(merged.theme.panel,"#111111"); eq(merged.custom,"keep"); eq(defaults.theme.accent,"#aa8844")
end)

test("mapper settings merge without removing user overrides",function()
  local merged=Settings.merge(defaults,{mapper={walk_timeout=20,personal_option="keep"},personal="untouched"})
  eq(merged.mapper.enabled,true); eq(merged.mapper.walk_timeout,20); eq(merged.mapper.minimum_height,90); eq(merged.mapper.schema,1)
  eq(merged.mapper.personal_option,"keep"); eq(merged.personal,"untouched")
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

test("colorization defaults enabled and preserves unrelated overrides",function()
  local resolved,migrated=Settings.resolve(defaults,{personal="untouched",colorization={exits_enabled=false,personal_option="keep"}})
  eq(resolved.colorization.enabled,true); eq(resolved.colorization.room_enabled,true); eq(resolved.colorization.exits_enabled,false); eq(resolved.colorization.currency_enabled,true); eq(resolved.colorization.personal_option,"keep")
  eq(migrated.personal,"untouched"); eq(migrated.colorization.personal_option,"keep")
end)

test("legacy highlight preference migrates to every individual category",function()
  local resolved,migrated,changed=Settings.resolve(defaults,{colorization={highlights_enabled=false}})
  eq(changed,true)
  for _,name in ipairs({"portal","attack","damage","danger","recovery","upkeep","spell","discovery","illumination"}) do
    eq(migrated.colorization[name.."_enabled"],false); eq(resolved.colorization[name.."_enabled"],false)
  end
end)

test("colorization persistence helper changes only its enabled override",function()
  local user={personal="untouched",colorization={personal_option="keep"}}
  local result=Settings.setColorEnabled(user,false)
  eq(result,user); eq(user.colorization.enabled,false); eq(user.colorization.personal_option,"keep"); eq(user.personal,"untouched")
  eq(Settings.colorEnabled(Settings.merge(defaults,user)),false)
  Settings.setColorEnabled(user,true); eq(Settings.colorEnabled(Settings.merge(defaults,user)),true)
end)
