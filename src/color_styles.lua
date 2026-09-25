-- Pure style registry. The caller owns persistence and group/master toggles.
local ColorStyles = {}
local ordered, byId = {}, {}
local fields = {foreground=true, background=true, bold=true, underline=true, enabled=true}

local function plainTable(value)
  return type(value) == "table" and getmetatable(value) == nil
end

local function copyStyle(style)
  return {
    foreground=style.foreground, background=style.background,
    bold=style.bold, underline=style.underline, enabled=style.enabled,
  }
end

local function add(id, label, group, kind, name, feature, foreground)
  local notice = id == "notice"
  local entry = {
    id=id, label=label, group=group, kind=kind, name=name, feature=feature,
    default={
      foreground=foreground, background=notice and "#501914" or false,
      bold=notice, underline=notice, enabled=true,
    },
  }
  ordered[#ordered+1], byId[id] = entry, entry
end

-- Keep the original output_colorizer palette, including separate exit styles.
add("room", "Room titles", "Room and exits", "room", nil, "room", "#E0B84F")
add("label", "Exit labels", "Room and exits", "label", nil, "exits", "#8B2D2D")
add("direction", "Exit directions", "Room and exits", "direction", nil, "exits", "#BF5B21")
add("gold", "Gold", "Currency", "gold", nil, "currency", "#E0B84F")
add("silver", "Silver", "Currency", "silver", nil, "currency", "#C0C0C0")
add("portal", "Travel objects / shops", "Highlights", "portal", nil, "portal", "#37BEC8")
add("presence", "Other room objects", "Highlights", "presence", nil, "presence", "#88BE99")
add("presence_phrase", "Is here / are here", "Highlights", "presence_phrase", nil, "presence", "#FFDC5A")
add("attack", "Incoming attacks", "Highlights", "attack", nil, "attack", "#CD3E3E")
add("damage", "Damage taken", "Highlights", "damage", nil, "damage", "#FF4646")
add("danger", "Movement warnings", "Highlights", "danger", nil, "danger", "#CD872D")
add("recovery", "Rest and healing", "Highlights", "recovery", nil, "recovery", "#5AA569")
add("upkeep", "Spell upkeep", "Highlights", "upkeep", nil, "upkeep", "#B9692D")
add("spell", "Spell activity", "Highlights", "spell", nil, "spell", "#915FBE")
add("discovery", "Discoveries", "Highlights", "discovery", nil, "discovery", "#E1B946")
add("illumination", "Illuminated rooms", "Highlights", "illumination", nil, "illumination", "#DCC855")
add("darkness", "Dark rooms", "Highlights", "darkness", nil, "illumination", "#69788C")
add("notice", "Version notices", "Highlights", "notice", nil, "notice", "#FFD750")

-- Aliases are individual editable entries, just as they are in the parser.
local raceColors = {
  ["go-blin-al"]="#99CCFF", ["muatana-al"]="#6699CC", ["drag-al"]="#00CCCC",
  ["fir elf"]="#66CC99", ["san elf"]="#9999FF", ["usil elf"]="#6666FF", ["oog-ra"]="#009999",
  anthian="#66CCFF", arachnian="#CC99FF", dragon="#3399FF", draco="#3399FF",
  drake="#3399FF", imperial="#3399FF", firian="#66CC99", sanene="#9999FF",
  usilin="#6666FF", frontacian="#0099CC", flerian="#66FFCC", hithual="#33CC99",
  human="#66FFFF", leuian="#00CCFF", monitanian="#66CC66", oogra="#009999",
  penthanian="#00CC99", psycian="#99CCCC", secian="#CCFFFF", thugian="#0066CC", goblin="#99FFCC",
}
local classColors = {
  ["non-elemental mages"]="#CC6699", ["non-elemental mage"]="#CC6699",
  ["elemental mages"]="#FFB347", ["elemental mage"]="#FFB347",
  ["hand cleric"]="#FFCC99", ["heart cleric"]="#FF9999", ["sword cleric"]="#CC6633",
  ["rune mage"]="#FF6600", ["air mage"]="#FFCC66", ["earth mage"]="#CC7722",
  ["fire mage"]="#FF3300", ["water mage"]="#FF6666", runemages="#FF6600", runemage="#FF6600",
  barbarian="#FF6666", bard="#FF99CC", cleric="#FFCC66", fighter="#FF9933",
  forester="#FFCC33", psion="#FF66CC", thief="#FF6699",
}
local function addPalette(palette, prefix, kind, group)
  local names = {}
  for name in pairs(palette) do names[#names+1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local label = name:gsub("%f[%a]%l", string.upper)
    add(prefix..":"..name, label, group, kind, name, kind, palette[name])
  end
end
addPalette(raceColors, "race", "races", "Races")
addPalette(classColors, "class", "classes", "Classes")

local function entryFor(id)
  if type(id) ~= "string" or not byId[id] then return nil, "unknown style id" end
  return byId[id]
end

-- Fresh copies prevent option editors from changing the shared registry.
function ColorStyles.entries()
  local result = {}
  for index, entry in ipairs(ordered) do
    result[index] = {
      id=entry.id, label=entry.label, group=entry.group, kind=entry.kind,
      name=entry.name, feature=entry.feature, default=copyStyle(entry.default),
    }
  end
  return result
end

-- Only canonical hex or a plain, exactly three-channel RGB array is accepted.
-- Never coerce strings/numbers or invoke user-supplied table metamethods.
function ColorStyles.normalizeColor(value)
  if type(value) == "string" then
    if #value == 7 and value:match("^#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") then
      return value:upper()
    end
  elseif plainTable(value) then
    for key in next, value do
      if key ~= 1 and key ~= 2 and key ~= 3 then return nil, "RGB color must contain exactly three channels" end
    end
    for index=1,3 do
      local channel = rawget(value, index)
      if type(channel) ~= "number" or channel ~= channel or channel < 0 or channel > 255 or channel % 1 ~= 0 then
        return nil, "RGB channels must be integers from 0 to 255"
      end
    end
    return string.format("#%02X%02X%02X", value[1], value[2], value[3])
  end
  return nil, "color must be #RRGGBB or an RGB array"
end

function ColorStyles.toRGB(hex)
  if type(hex) ~= "string" then return nil, "color must be #RRGGBB" end
  local normalized, err = ColorStyles.normalizeColor(hex)
  if not normalized then return nil, err end
  return {tonumber(normalized:sub(2,3),16), tonumber(normalized:sub(4,5),16), tonumber(normalized:sub(6,7),16)}
end

function ColorStyles.defaults(id)
  local entry, err = entryFor(id)
  if not entry then return nil, err end
  return copyStyle(entry.default)
end

-- Validate partial input, returning a complete, normalized, detached style.
local function validateInto(id, input, base)
  local entry, err = entryFor(id)
  if not entry then return nil, err end
  if not plainTable(input) then return nil, "style must be a plain table" end
  local result = copyStyle(base or entry.default)
  for key, value in next, input do
    if type(key) ~= "string" or not fields[key] then return nil, "unknown style field" end
    if key == "foreground" or key == "background" then
      if key == "background" and value == false then
        result.background = false
      else
        local color, colorErr = ColorStyles.normalizeColor(value)
        if not color then return nil, key..": "..colorErr end
        result[key] = color
      end
    else
      if type(value) ~= "boolean" then return nil, key.." must be true or false" end
      result[key] = value
    end
  end
  return result
end

function ColorStyles.validateStyle(id, input)
  return validateInto(id, input)
end

-- Validate the entire saved override map atomically, bounded by registry size.
-- Absent IDs stay absent; every present ID produces a complete style.
function ColorStyles.validateOverrides(styles)
  if not plainTable(styles) then return nil, "styles must be a plain table" end
  local result, count = {}, 0
  for id, input in next, styles do
    count = count + 1
    if count > #ordered then return nil, "too many style overrides" end
    local style, err = ColorStyles.validateStyle(id, input)
    if not style then return nil, err end
    result[id] = style
  end
  return result
end

-- config is the colorization table itself, not the root settings table.
-- Precedence: registry default < legacy foreground < styles[id].
-- Invalid persisted values safely fall back; explicit validators reject them.
-- enabled is per-entry only. Callers apply feature/master switches separately.
function ColorStyles.resolve(config, id)
  local entry, err = entryFor(id)
  if not entry then return nil, err end
  local result = copyStyle(entry.default)
  if not plainTable(config) then return result end
  local legacy
  if entry.name then
    local key = entry.kind == "races" and "race_colors" or "class_colors"
    local palette = rawget(config, key)
    if plainTable(palette) then legacy = rawget(palette, entry.name) end
  else
    legacy = rawget(config, id.."_color")
  end
  local foreground = ColorStyles.normalizeColor(legacy)
  if foreground then result.foreground = foreground end
  local styles = rawget(config, "styles")
  if plainTable(styles) then
    local input = rawget(styles, id)
    if input ~= nil then
      local validated = validateInto(id, input, result)
      if validated then return validated end
    end
  end
  return result
end

return ColorStyles
