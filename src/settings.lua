local Settings={CURRENT_SCHEMA=1}
local function copy(value,seen)
  if type(value)~="table" then return value end
  seen=seen or {}; if seen[value] then return seen[value] end
  local result={}; seen[value]=result; for k,v in pairs(value) do result[copy(k,seen)]=copy(v,seen) end; return result
end
local function overlay(target,source)
  for k,v in pairs(source or {}) do if type(v)=="table" and type(target[k])=="table" then overlay(target[k],v) else target[k]=copy(v) end end
end
function Settings.merge(defaults,overrides) local result=copy(defaults or {}); overlay(result,overrides or {}); return result end
function Settings.migrate(input)
  local result=copy(input or {}); local changed=false; local schema=tonumber(result.schema) or 0
  if schema<1 then result.update=result.update or {}; result.update.auto_apply=false; result.auto_update=nil; result.schema=1; changed=true end
  local colors=type(result.colorization)=="table" and result.colorization or nil
  if colors and colors.highlights_enabled~=nil then
    for _,name in ipairs({"portal","attack","damage","danger","recovery","upkeep","spell","discovery","illumination"}) do
      local key=name.."_enabled"; if colors[key]==nil then colors[key]=colors.highlights_enabled~=false; changed=true end
    end
  end
  return result,changed
end
function Settings.resolve(defaults,input)
  local migrated,changed=Settings.migrate(input)
  return Settings.merge(defaults,migrated),migrated,changed
end
function Settings.colorEnabled(settings)
  local colorization=type(settings)=="table" and settings.colorization or nil
  return not (type(colorization)=="table" and colorization.enabled==false)
end
function Settings.setColorEnabled(userSettings,enabled)
  userSettings=type(userSettings)=="table" and userSettings or {}
  userSettings.colorization=type(userSettings.colorization)=="table" and userSettings.colorization or {}
  userSettings.colorization.enabled=enabled~=false
  return userSettings
end
return Settings
