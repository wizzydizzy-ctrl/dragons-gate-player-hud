local Styles = require("color_styles")
local Colorizer = require("output_colorizer")

-- Independent fixtures copied from the original colorizer's RGB palettes.
local baseColors = {
  room={224,184,79}, label={139,45,45}, direction={191,91,33}, gold={224,184,79},
  silver={192,192,192}, portal={55,190,200}, presence={136,190,153}, presence_phrase={255,220,90},
  attack={205,62,62}, damage={255,70,70},
  danger={205,135,45}, recovery={90,165,105}, upkeep={185,105,45}, spell={145,95,190},
  discovery={225,185,70}, illumination={220,200,85}, darkness={105,120,140}, notice={255,215,80},
}
local raceColors = {
  ["go-blin-al"]={153,204,255}, ["muatana-al"]={102,153,204}, ["drag-al"]={0,204,204},
  ["fir elf"]={102,204,153}, ["san elf"]={153,153,255}, ["usil elf"]={102,102,255}, ["oog-ra"]={0,153,153},
  anthian={102,204,255}, arachnian={204,153,255}, dragon={51,153,255}, draco={51,153,255},
  drake={51,153,255}, imperial={51,153,255}, firian={102,204,153}, sanene={153,153,255},
  usilin={102,102,255}, frontacian={0,153,204}, flerian={102,255,204}, hithual={51,204,153},
  human={102,255,255}, leuian={0,204,255}, monitanian={102,204,102}, oogra={0,153,153},
  penthanian={0,204,153}, psycian={153,204,204}, secian={204,255,255}, thugian={0,102,204}, goblin={153,255,204},
}
local classColors = {
  ["non-elemental mages"]={204,102,153}, ["non-elemental mage"]={204,102,153},
  ["elemental mages"]={255,179,71}, ["elemental mage"]={255,179,71},
  ["hand cleric"]={255,204,153}, ["heart cleric"]={255,153,153}, ["sword cleric"]={204,102,51},
  ["rune mage"]={255,102,0}, ["air mage"]={255,204,102}, ["earth mage"]={204,119,34},
  ["fire mage"]={255,51,0}, ["water mage"]={255,102,102}, runemages={255,102,0}, runemage={255,102,0},
  barbarian={255,102,102}, bard={255,153,204}, cleric={255,204,102}, fighter={255,153,51},
  forester={255,204,51}, psion={255,102,204}, thief={255,102,153},
}
local baseOrder = {
  "room", "label", "direction", "gold", "silver", "portal", "presence", "presence_phrase", "attack", "damage",
  "danger", "recovery", "upkeep", "spell", "discovery", "illumination", "darkness", "notice",
}
local features = {label="exits", direction="exits", gold="currency", silver="currency", darkness="illumination", presence_phrase="presence"}
local styleFields = {foreground=true, background=true, bold=true, underline=true, enabled=true}

local function rejected(value, err)
  eq(value, nil)
  eq(type(err), "string")
  assert(#err > 0)
end
local function rgbEquals(actual, expected)
  eq(#actual, 3)
  for index=1,3 do eq(actual[index], expected[index]) end
end
local function completeStyle(style)
  local count = 0
  for key in pairs(style) do assert(styleFields[key]); count = count+1 end
  eq(count, 5)
  eq(style.foreground, assert(Styles.normalizeColor(style.foreground)))
  if style.background ~= false then eq(style.background, assert(Styles.normalizeColor(style.background))) end
  for _, key in ipairs({"bold", "underline", "enabled"}) do eq(type(style[key]), "boolean") end
  eq(getmetatable(style), nil)
end
local function styleEquals(actual, expected)
  completeStyle(actual)
  for key in pairs(styleFields) do eq(actual[key], expected[key]) end
end

test("style registry includes all 67 base and named palette entries with stable metadata", function()
  local entries, again, seen = Styles.entries(), Styles.entries(), {}
  eq(#entries, 67)
  for index, entry in ipairs(entries) do
    eq(seen[entry.id], nil); seen[entry.id] = entry
    eq(again[index].id, entry.id)
    for _, key in ipairs({"id", "label", "group", "kind", "feature"}) do
      eq(type(entry[key]), "string"); assert(#entry[key] > 0)
    end
    completeStyle(entry.default)
    eq(entry.default.enabled, true)
    styleEquals(Styles.defaults(entry.id), entry.default)
    if not entry.name then
      eq(entry.id, baseOrder[index]); eq(entry.kind, entry.id)
      eq(entry.feature, features[entry.id] or entry.id)
      rgbEquals(Styles.toRGB(entry.default.foreground), assert(baseColors[entry.id]))
    end
  end
  for id in pairs(baseColors) do assert(seen[id]) end
  local count = 18
  for _, palette in ipairs({{raceColors, "race", "races", "Races"}, {classColors, "class", "classes", "Classes"}}) do
    local names = {}
    for name, rgb in pairs(palette[1]) do
      names[#names+1] = name
      local entry = assert(seen[palette[2]..":"..name])
      eq(entry.name, name); eq(entry.kind, palette[3]); eq(entry.feature, palette[3]); eq(entry.group, palette[4])
      rgbEquals(Styles.toRGB(entry.default.foreground), rgb)
    end
    table.sort(names)
    for _, name in ipairs(names) do count = count+1; eq(entries[count].id, palette[2]..":"..name) end
  end
  eq(count, #entries)
  eq(seen.portal.label, "Travel objects / shops")
  eq(seen.portal.default.bold, false)
end)

test("registry defaults match every existing parser segment kind and named palette color", function()
  local samples = {
    "[Old Cemetery.]", "Obvious exits: north.", "Gold and silver.",
    "An open gate is here.", "A wooden chest is here.", "The hound bites you!", "Your head takes 8 points of impact damage!",
    "You cannot move in that direction.", "** You are fully rested.",
    "You expend 1 fatigue keeping up the ward.", "The acolyte casts a curse at you!",
    "You have discovered a secret path!", "This area is illuminated.",
    "This area is not illuminated.", "(There are new version notes.)",
  }
  local seen = {}
  for _, line in ipairs(samples) do
    for _, part in ipairs(assert(Colorizer.parse(line))) do
      local defaults = assert(Styles.defaults(part.kind))
      rgbEquals(Styles.toRGB(defaults.foreground), part.color)
      seen[part.kind] = true
      eq(defaults.bold, part.bold == true); eq(defaults.underline, part.underline == true)
      if part.background then rgbEquals(Styles.toRGB(defaults.background), part.background)
      else eq(defaults.background, false) end
    end
  end
  for id in pairs(baseColors) do assert(seen[id], "missing parser sample: "..id) end
  for _, palette in ipairs({{raceColors, "race", "races"}, {classColors, "class", "classes"}}) do
    for name in pairs(palette[1]) do
      local parts = assert(Colorizer.parse(name))
      eq(#parts, 1); eq(parts[1].kind, palette[3]); eq(parts[1].length, #name)
      rgbEquals(Styles.toRGB(Styles.defaults(palette[2]..":"..name).foreground), parts[1].color)
    end
  end
end)

test("notice defaults preserve emphasis and every other entry starts without emphasis", function()
  for _, entry in ipairs(Styles.entries()) do
    local notice = entry.id == "notice"
    eq(entry.default.bold, notice); eq(entry.default.underline, notice)
    eq(entry.default.background, notice and "#501914" or false)
  end
  eq(Styles.defaults("notice").foreground, "#FFD750")
end)

test("color normalization accepts only exact hex or integer RGB and uppercases output", function()
  eq(Styles.normalizeColor("#abcdef"), "#ABCDEF")
  eq(Styles.normalizeColor("#aB00fF"), "#AB00FF")
  eq(Styles.normalizeColor({0,255,16}), "#00FF10")
  eq(Styles.normalizeColor({255,0,255}), "#FF00FF")
  for _, hex in ipairs({"#000000", "#FFFFFF", "#8B2D2D", "#501914"}) do
    eq(Styles.normalizeColor(Styles.toRGB(hex)), hex)
  end
  local first = Styles.toRGB("#123456"); first[1] = 0
  rgbEquals(Styles.toRGB("#123456"), {18,52,86})
end)

test("color validation rejects injection control bytes names and malformed hex", function()
  for _, value in ipairs({
    "", "red", "#abc", "#12345678", "123456", "#GG0011", " #123456", "#123456 ",
    "#123456\n", "#123456\0", "#123456; color:red", "<red>", "rgb(1,2,3)",
    "\27[31m", "#123456]]; error('injected'); --", "url(file:///tmp/style)", string.rep("A",10000),
  }) do
    rejected(Styles.normalizeColor(value))
    rejected(Styles.toRGB(value))
    rejected(Styles.validateStyle("room", {foreground=value}))
    rejected(Styles.validateStyle("room", {background=value}))
  end
end)

test("RGB validation rejects missing extra fractional nonnumeric and nonfinite channels", function()
  for _, value in ipairs({
    {}, {1,2}, {1,2,3,4}, {[1]=1,[3]=3}, {r=1,g=2,b=3}, {1,2,3,extra=true},
    {[-1]=0,1,2,3}, {"1",2,3}, {false,2,3}, {1.5,2,3}, {-1,2,3}, {256,2,3},
    {0/0,2,3}, {1,math.huge,3}, {1,2,-math.huge}, {1,2,{3}},
  }) do rejected(Styles.normalizeColor(value)) end
  rejected(Styles.normalizeColor(nil)); rejected(Styles.normalizeColor(false))
  rejected(Styles.normalizeColor(123456)); rejected(Styles.normalizeColor(0/0))
  rejected(Styles.normalizeColor(function() end))
  rejected(Styles.toRGB({1,2,3})); rejected(Styles.toRGB(false))
end)

test("style validation returns complete normalized styles from partial overrides", function()
  local input = {foreground={1,2,3}, background="#aabbcc", bold=true}
  local actual = assert(Styles.validateStyle("room", input))
  styleEquals(actual, {foreground="#010203",background="#AABBCC",bold=true,underline=false,enabled=true})
  eq(input.foreground[1], 1); eq(input.background, "#aabbcc"); eq(input.enabled, nil)
  styleEquals(Styles.validateStyle("notice", {}), Styles.defaults("notice"))
  styleEquals(Styles.validateStyle("notice", {background=false,bold=false,underline=false,enabled=false}),
    {foreground="#FFD750",background=false,bold=false,underline=false,enabled=false})
  for _, entry in ipairs(Styles.entries()) do
    completeStyle(assert(Styles.validateStyle(entry.id, {foreground="#123456",background={0,0,0},bold=true,underline=true,enabled=false})))
  end
end)

test("style validation strictly rejects unknown fields and incorrect field types", function()
  for _, key in ipairs({"color", "fg", "name", "id", "feature", "styles", "__index", "__proto__", "display_text"}) do
    rejected(Styles.validateStyle("room", {[key]="#123456"}))
  end
  rejected(Styles.validateStyle("room", {[1]="#123456"}))
  rejected(Styles.validateStyle("room", {[{}]=true}))
  for _, value in ipairs({"false", 0, 1, 0/0, {}, function() end}) do
    for _, key in ipairs({"bold", "underline", "enabled"}) do
      rejected(Styles.validateStyle("room", {[key]=value}))
    end
  end
  for _, value in ipairs({false, true, 12, {}}) do rejected(Styles.validateStyle("room", {foreground=value})) end
  for _, value in ipairs({true, 12, {}}) do rejected(Styles.validateStyle("room", {background=value})) end
  rejected(Styles.validateStyle("room", nil)); rejected(Styles.validateStyle("room", false))
  rejected(Styles.validateStyle("room", "#123456"))
end)

test("all id-based APIs reject unknown noncanonical and nonstring ids", function()
  for _, id in ipairs({"missing", "race:Human", "races:human", "class:mage", "race:human\n", "room; error('x')", {}, true, 1, 0/0}) do
    rejected(Styles.defaults(id)); rejected(Styles.resolve({}, id)); rejected(Styles.validateStyle(id, {}))
  end
  rejected(Styles.defaults(nil)); rejected(Styles.resolve({}, nil)); rejected(Styles.validateStyle(nil, {}))
end)

test("legacy foreground migration covers every base style without modifying config", function()
  for id in pairs(baseColors) do
    local legacy = {1,2,3}
    local config = {[id.."_color"]=legacy}
    local resolved = Styles.resolve(config, id)
    eq(resolved.foreground, "#010203"); completeStyle(resolved)
    eq(config[id.."_color"], legacy); eq(legacy[1], 1); eq(config.styles, nil)
    config[id.."_color"] = "#abCdEf"
    eq(Styles.resolve(config, id).foreground, "#ABCDEF")
  end
  local notice = Styles.resolve({notice_color="#123456"}, "notice")
  eq(notice.background, "#501914"); eq(notice.bold, true); eq(notice.underline, true)
end)

test("named palettes resolve their original fallback and optional legacy palette colors", function()
  for _, palette in ipairs({{raceColors, "race", "race_colors"}, {classColors, "class", "class_colors"}}) do
    for name, rgb in pairs(palette[1]) do
      local id = palette[2]..":"..name
      rgbEquals(Styles.toRGB(Styles.resolve({}, id).foreground), rgb)
      local config = {[palette[3]]={[name]={12,34,56}}}
      eq(Styles.resolve(config, id).foreground, "#0C2238")
      config.styles = {[id]={foreground="#abcdef",enabled=false}}
      eq(Styles.resolve(config, id).foreground, "#ABCDEF"); eq(Styles.resolve(config, id).enabled, false)
      eq(config[palette[3]][name][1], 12)
    end
  end
end)

test("style overrides take precedence while unspecified fields retain migrated values", function()
  local config = {
    room_color={1,2,3}, label_color="#111111", direction_color="#222222",
    styles={room={bold=true,enabled=false}, label={foreground="#abcdef"}, notice={background=false}},
  }
  styleEquals(Styles.resolve(config, "room"),
    {foreground="#010203",background=false,bold=true,underline=false,enabled=false})
  eq(Styles.resolve(config, "label").foreground, "#ABCDEF")
  eq(Styles.resolve(config, "direction").foreground, "#222222")
  local notice = Styles.resolve(config, "notice")
  eq(notice.background, false); eq(notice.bold, true); eq(notice.underline, true)
  config.styles.room.foreground = "#987654"
  eq(Styles.resolve(config, "room").foreground, "#987654")
end)

test("entry enabled switches remain independent of group and master switches", function()
  local config = {enabled=false,highlights_enabled=false,styles={}}
  for _, entry in ipairs(Styles.entries()) do config[entry.feature.."_enabled"] = false end
  for _, entry in ipairs(Styles.entries()) do eq(Styles.resolve(config, entry.id).enabled, true) end
  config.enabled = true
  for _, entry in ipairs(Styles.entries()) do
    config[entry.feature.."_enabled"] = true
    config.styles[entry.id] = {enabled=false}
    eq(Styles.resolve(config, entry.id).enabled, false)
  end
  eq(Styles.resolve({exits_enabled=true,styles={label={enabled=false}}}, "direction").enabled, true)
  eq(Styles.resolve({races_enabled=true,styles={["race:human"]={enabled=false}}}, "race:anthian").enabled, true)
end)

test("invalid saved colors and styles safely fall back without accepting partial invalid overrides", function()
  for _, value in ipairs({"red", "#123456; injected", {1,2,0/0}, false, function() end}) do
    eq(Styles.resolve({room_color=value}, "room").foreground, Styles.defaults("room").foreground)
    eq(Styles.resolve({race_colors={human=value}}, "race:human").foreground, Styles.defaults("race:human").foreground)
  end
  for _, input in ipairs({false, 7, "bad", {foreground="red"}, {foreground="#FFFFFF",bold="yes"}, {enabled=false,evil=true}}) do
    styleEquals(Styles.resolve({room_color="#123456",styles={room=input}}, "room"),
      {foreground="#123456",background=false,bold=false,underline=false,enabled=true})
  end
  for _, config in ipairs({false, "bad", 1, {styles=false}, {styles="bad"}}) do
    styleEquals(Styles.resolve(config, "room"), Styles.defaults("room"))
  end
  styleEquals(Styles.resolve(nil, "room"), Styles.defaults("room"))
end)

test("registry and returned styles cannot be changed through caller-owned copies", function()
  local entries = Styles.entries()
  entries[1].id = "changed"; entries[1].default.foreground = "#000000"
  entries[19].name = "changed"; entries[19].default.enabled = false; entries[2] = nil
  eq(Styles.entries()[1].id, "room"); eq(Styles.entries()[19].name, "anthian")
  eq(Styles.entries()[19].default.enabled, true); eq(#Styles.entries(), 67)
  local defaults = Styles.defaults("room"); defaults.foreground = "#000000"
  eq(Styles.defaults("room").foreground, "#E0B84F")
  local config = {room_color={1,2,3},styles={room={background={4,5,6}}}}
  local style = Styles.resolve(config, "room"); style.enabled = false; style.background = false
  eq(Styles.resolve(config, "room").background, "#040506"); eq(Styles.resolve(config, "room").enabled, true)
  config.room_color[1] = 255; config.styles.room.background[1] = 255
  eq(style.foreground, "#010203")
  eq(Styles.defaults("room").foreground, "#E0B84F")
end)

test("override validation returns detached complete styles and accepts the full registry", function()
  local all = {}
  for _, entry in ipairs(Styles.entries()) do all[entry.id] = {enabled=false} end
  local valid = assert(Styles.validateOverrides(all))
  local count = 0
  for id, style in pairs(valid) do count = count+1; completeStyle(style); eq(style.enabled, false); eq(all[id].foreground, nil) end
  eq(count, #Styles.entries())
  eq(next(assert(Styles.validateOverrides({}))), nil)
  local input = {room={foreground={1,2,3},background={4,5,6}}}
  local first = assert(Styles.validateOverrides(input))
  first.room.enabled = false
  eq(Styles.validateOverrides(input).room.enabled, true)
  input.room.foreground[1] = 255; input.room.background[1] = 255
  eq(first.room.foreground, "#010203"); eq(first.room.background, "#040506")
  eq(Styles.defaults("room").enabled, true)
end)

test("override validation rejects unknown ids oversize maps and invalid values atomically", function()
  rejected(Styles.validateOverrides(nil)); rejected(Styles.validateOverrides(false)); rejected(Styles.validateOverrides("bad"))
  rejected(Styles.validateOverrides({[1]={}}))
  rejected(Styles.validateOverrides({room={},missing={}}))
  rejected(Styles.validateOverrides({room={foreground="#FFFFFF"},gold={enabled="yes"}}))
  rejected(Styles.validateOverrides({room=false}))
  local all = {}
  for _, entry in ipairs(Styles.entries()) do all[entry.id] = {} end
  all.extra = {}
  rejected(Styles.validateOverrides(all))
  eq(Styles.defaults("room").foreground, "#E0B84F")
end)

test("validation never invokes table metadata or follows recursive input", function()
  local calls = 0
  local function trap() calls=calls+1; error("input metamethod executed") end
  local metadata = {__index=trap,__pairs=trap,__len=trap,__tostring=trap}
  local color = setmetatable({1,2,3}, metadata)
  local input = setmetatable({foreground="#123456"}, metadata)
  local overrides = setmetatable({room={foreground="#123456"}}, metadata)
  rejected(Styles.normalizeColor(color))
  rejected(Styles.validateStyle("room", input))
  rejected(Styles.validateStyle("room", {foreground=color}))
  rejected(Styles.validateOverrides(overrides))
  rejected(Styles.validateOverrides({room=input}))
  rejected(Styles.defaults(input))
  eq(Styles.resolve(overrides, "room").foreground, "#E0B84F")
  eq(Styles.resolve({room_color=color,styles=overrides}, "room").foreground, "#E0B84F")
  eq(Styles.resolve({styles={room=input}}, "room").foreground, "#E0B84F")
  eq(Styles.resolve({race_colors=overrides}, "race:human").foreground, "#66FFFF")
  local cyclic = {}; cyclic[1] = cyclic
  rejected(Styles.normalizeColor(cyclic))
  rejected(Styles.validateStyle("room", {foreground=cyclic}))
  rejected(Styles.validateOverrides({room={foreground=cyclic}}))
  local protected = setmetatable({1,2,3}, {__metatable=false,__index=trap})
  rejected(Styles.normalizeColor(protected))
  eq(calls, 0)
end)
