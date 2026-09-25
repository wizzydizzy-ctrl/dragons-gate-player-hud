-- Data-only persistence for the colorization table, never the root settings.
-- api (optional) supplies read(path, limit), write(path, text), mkdir(path),
-- rename(from, to), remove(path), and optionally symlinkattributes(path).
-- read returns nil without an error (or errno 2) for an absent file. mkdir is
-- idempotent. write must flush/close before reporting success. All paths are
-- derived here; saved data cannot select a path. One writer owns each profile.
local Styles = require("color_styles")
local Preferences = {MAX_BYTES=65536, HEADER="DGHUD-COLORS|1"}
local MAX_BYTES, HEADER = Preferences.MAX_BYTES, Preferences.HEADER
local toggles, toggleSet = {"enabled", "highlights_enabled"}, {}
for _, feature in ipairs({
  "room", "exits", "currency", "races", "classes", "portal", "attack",
  "damage", "danger", "recovery", "upkeep", "spell", "discovery",
  "illumination", "notice",
}) do
  toggles[#toggles+1] = feature.."_enabled"
end
table.sort(toggles)
for _, key in ipairs(toggles) do toggleSet[key] = true end

local entries, ids, legacyKeys, palettes = Styles.entries(), {}, {}, {
  race_colors={}, class_colors={},
}
for _, entry in ipairs(entries) do
  ids[entry.id] = true
  local prefix, name = entry.id:match("^(%a+):(.+)$")
  if prefix == "race" then
    palettes.race_colors[name] = entry.id
  elseif prefix == "class" then
    palettes.class_colors[name] = entry.id
  else
    legacyKeys[entry.id.."_color"] = entry.id
  end
end

local function plain(value)
  return type(value) == "table" and getmetatable(value) == nil
end

function Preferences.snapshot(config)
  if not plain(config) then return nil, "colorization must be a plain table" end
  local result, legacy, count = {styles={}}, {}, 0
  for key, value in next, config do
    count = count + 1
    if count > #toggles + #entries + 3 then return nil, "too many color settings" end
    if toggleSet[key] then
      if type(value) ~= "boolean" then return nil, "color toggles must be booleans" end
      result[key] = value
    elseif legacyKeys[key] then
      local color, err = Styles.normalizeColor(value)
      if not color then return nil, err end
      legacy[legacyKeys[key]] = color
    elseif palettes[key] then
      if not plain(value) then return nil, "legacy palette must be a plain table" end
      local size = 0
      for name, rgb in next, value do
        size = size + 1
        if size > #entries or not palettes[key][name] then return nil, "unknown legacy palette entry" end
        local color, err = Styles.normalizeColor(rgb)
        if not color then return nil, err end
        legacy[palettes[key][name]] = color
      end
    elseif key ~= "styles" then
      return nil, "unknown color setting"
    end
  end
  local inputStyles = rawget(config, "styles")
  if inputStyles == nil then inputStyles = {} end
  local overrides, err = Styles.validateOverrides(inputStyles)
  if not overrides then return nil, err end
  for id in next, overrides do
    -- Resolve only after validation. Partial style edits retain a legacy
    -- foreground; explicit full styles take precedence over legacy settings.
    result.styles[id] = Styles.resolve(config, id)
  end
  for id, color in next, legacy do
    if result.styles[id] == nil and color ~= Styles.defaults(id).foreground then
      result.styles[id] = Styles.resolve(config, id)
    end
  end
  return result
end

local function bit(value) return value and "1" or "0" end

function Preferences.encode(config)
  local normalized, err = Preferences.snapshot(config)
  if not normalized then return nil, err end
  local lines, ordered = {HEADER}, {}
  for _, key in ipairs(toggles) do
    if normalized[key] ~= nil then lines[#lines+1] = "toggle|"..key.."|"..bit(normalized[key]) end
  end
  for id in next, normalized.styles do ordered[#ordered+1] = id end
  table.sort(ordered)
  for _, id in ipairs(ordered) do
    local style = normalized.styles[id]
    lines[#lines+1] = table.concat({
      "style", id, style.foreground, style.background or "-",
      bit(style.bold), bit(style.underline), bit(style.enabled),
    }, "|")
  end
  local text = table.concat(lines, "\n").."\n"
  if #text > MAX_BYTES then return nil, "color settings exceed 64 KiB" end
  return text
end

function Preferences.decode(text)
  if type(text) ~= "string" then return nil, "color settings must be text" end
  if #text > MAX_BYTES then return nil, "color settings exceed 64 KiB" end
  if text:sub(1, #HEADER+1) ~= HEADER.."\n" or text:sub(-1) ~= "\n" then
    return nil, "invalid or incomplete color settings header/record"
  end
  if text:find("[%z\1-\9\11-\31\127]") then return nil, "invalid color settings characters" end
  local result, seen, count = {styles={}}, {}, 0
  for line in text:sub(#HEADER+2):gmatch("(.-)\n") do
    count = count + 1
    if count > #toggles + #entries or #line > 256 then return nil, "too many or oversized color records" end
    local key, value = line:match("^toggle|([a-z_]+)|([01])$")
    if key then
      if not toggleSet[key] or seen[key] then return nil, "unknown or duplicate toggle" end
      seen[key], result[key] = true, value == "1"
    else
      local id, foreground, background, bold, underline, enabled =
        line:match("^style|([^|]+)|([^|]+)|([^|]+)|([01])|([01])|([01])$")
      if not id or not ids[id] or result.styles[id] then return nil, "invalid, unknown or duplicate style" end
      local input = {
        foreground=foreground, background=background,
        bold=bold == "1", underline=underline == "1", enabled=enabled == "1",
      }
      if background == "-" then input.background = false end
      local style, err = Styles.validateStyle(id, input)
      if not style then return nil, err end
      result.styles[id] = style
    end
  end
  return result
end

local function call(api, name, ...)
  if type(api[name]) ~= "function" then return nil, "missing storage operation: "..name end
  local ok, value, err, code = pcall(api[name], ...)
  if not ok then return nil, "storage "..name.." failed" end
  return value, err, code
end

local function missing(err, code)
  return err == nil or code == 2 or code == "ENOENT"
end

local function nativeApi()
  local lfs = rawget(_G, "lfs")
  if type(lfs) ~= "table" then
    local ok, module = pcall(require, "lfs")
    if ok and type(module) == "table" then lfs = module end
  end
  local api = {rename=os.rename, remove=os.remove}
  if type(lfs) == "table" and type(lfs.symlinkattributes) == "function" then
    api.symlinkattributes = lfs.symlinkattributes
  end
  function api.mkdir(path)
    if type(lfs) ~= "table" or type(lfs.mkdir) ~= "function" then
      -- Without lfs we can still use an existing directory. A missing directory
      -- is reported by io.open; do not construct a shell command from home.
      return true
    end
    if type(lfs.attributes) == "function" and lfs.attributes(path, "mode") == "directory" then return true end
    return lfs.mkdir(path)
  end
  function api.read(path, limit)
    local file, err, code = io.open(path, "rb")
    if not file then return nil, err, code end
    -- The extra byte detects oversize input without ever doing an unbounded read.
    local ok, text, readErr = pcall(file.read, file, limit)
    local closed, closeResult = pcall(file.close, file)
    if not ok then return nil, "could not read color settings" end
    if readErr then return nil, readErr end
    if not closed or not closeResult then return nil, "could not close color settings" end
    return text or ""
  end
  function api.write(path, text)
    local file, err = io.open(path, "wb")
    if not file then return nil, err end
    local ok, written, writeErr = pcall(file.write, file, text)
    local flushed, flushResult = false, nil
    if ok and written then flushed, flushResult = pcall(file.flush, file) end
    local closed, closeResult = pcall(file.close, file)
    if not ok or not written then return nil, writeErr or "could not write color settings" end
    if not flushed or not flushResult then return nil, "could not flush color settings" end
    if not closed or not closeResult then return nil, "could not close color settings" end
    return true
  end
  return api
end

local function storage(home, api)
  if type(home) ~= "string" or home == "" or #home > 4096 or home:find("[%z\1-\31\127]") then
    return nil, "invalid profile home"
  end
  for component in home:gmatch("[^/\\]+") do
    if component == "." or component == ".." then return nil, "invalid profile home" end
  end
  local base = home:gsub("[/\\]+$", "")
  if base == "" then base = "/" end
  local directory = base == "/" and "/DGHUDData" or base.."/DGHUDData"
  local path = directory.."/color-settings.dat"
  if api == nil then api = nativeApi() end
  if type(api) ~= "table" then return nil, "invalid storage API" end
  -- An injected lfs is convenient for adapters and tests, without mixing fake
  -- file operations with the real filesystem.
  if api.symlinkattributes == nil and type(api.lfs) == "table" and type(api.lfs.symlinkattributes) == "function" then
    local wrapped = {}
    for key, value in pairs(api) do wrapped[key] = value end
    wrapped.symlinkattributes = api.lfs.symlinkattributes
    api = wrapped
  end
  return {api=api, home=base, directory=directory, path=path, temp=path..".tmp", backup=path..".bak"}
end

local function guard(store, path, kind)
  if store.api.symlinkattributes == nil then return true end
  local attr, err, code = call(store.api, "symlinkattributes", path)
  if attr == nil then
    if missing(err, code) then return true end
    return nil, err or "could not inspect color settings"
  end
  local mode = type(attr) == "table" and attr.mode or attr
  if mode ~= kind then return nil, "unsafe color settings path (expected "..kind..")" end
  return true
end

local function inspect(store)
  for _, item in ipairs({
    {store.home, "directory"}, {store.directory, "directory"},
    {store.path, "file"}, {store.temp, "file"}, {store.backup, "file"},
  }) do
    local ok, err = guard(store, item[1], item[2])
    if not ok then return nil, err end
  end
  return true
end

local function read(store, path)
  local safe, err = guard(store, path, "file")
  if not safe then return nil, err end
  local text, readErr, code = call(store.api, "read", path, MAX_BYTES+1)
  if text == nil then
    if missing(readErr, code) then return nil end
    return nil, readErr or "could not read color settings"
  end
  if type(text) ~= "string" then return nil, "invalid storage read" end
  if #text > MAX_BYTES then return nil, "color settings exceed 64 KiB" end
  return text
end

local function cleanup(store, path)
  local safe = guard(store, path, "file")
  if safe then return call(store.api, "remove", path) end
end

-- Reconcile only fully validated leftovers. The committed file wins; when it
-- is absent, restore the original backup before considering a staged first
-- save. Load stays read-only, while the next save repairs these reserved paths.
local function recover(store)
  local files = {
    {path=store.path, label="original"},
    {path=store.backup, label="backup"},
    {path=store.temp, label="temporary file"},
  }
  for _, file in ipairs(files) do
    local err
    file.text, err = read(store, file.path)
    if err then return nil, err end
  end
  local original, backup, temp = files[1], files[2], files[3]
  if backup.text == nil and temp.text == nil then return original.text end

  -- Validate the complete recovery set before a rename or removal. In
  -- particular, never delete a good backup in favor of a corrupt original.
  for _, file in ipairs(files) do
    if file.text ~= nil then
      local config, err = Preferences.decode(file.text)
      if not config then return nil, "color settings recovery: "..file.label.." preserved: "..err end
    end
  end
  local function unchanged(file)
    local current, err = read(store, file.path)
    if err then return nil, err end
    if current ~= file.text then return nil, "color settings changed during recovery; files preserved" end
    return true
  end
  for _, file in ipairs(files) do
    local ok, err = unchanged(file)
    if not ok then return nil, err end
  end

  if original.text == nil then
    local source = backup.text ~= nil and backup or temp
    -- Moving, rather than deleting/copying, preserves the only verified copy
    -- even if the subsequent write or replacement fails.
    local ok, err = call(store.api, "rename", source.path, original.path)
    if not ok then return nil, err or "could not restore color settings; files preserved" end
    original.text, source.text = source.text, nil
  end
  for _, leftover in ipairs({backup, temp}) do
    if leftover.text ~= nil then
      -- Recheck both copies before deleting a stale transaction artifact.
      local ok, err = unchanged(original)
      if not ok then return nil, err end
      ok, err = unchanged(leftover)
      if not ok then return nil, err end
      ok, err = cleanup(store, leftover.path)
      if not ok then return nil, err or "could not remove verified color settings "..leftover.label end
      leftover.text = nil
    end
  end
  return original.text
end

function Preferences.save(home, config, api)
  -- Validate every setting before directory creation or any other mutation.
  local text, err = Preferences.encode(config)
  if not text then return nil, err end
  local store
  store, err = storage(home, api)
  if not store then return nil, err end
  for _, operation in ipairs({"read", "write", "mkdir", "rename", "remove"}) do
    if type(store.api[operation]) ~= "function" then return nil, "missing storage operation: "..operation end
  end
  local safe
  safe, err = inspect(store)
  if not safe then return nil, err end
  local original
  original, err = recover(store)
  if err then return nil, err end
  local ok
  ok, err = call(store.api, "mkdir", store.directory)
  if not ok then return nil, err or "could not create color settings directory" end
  safe, err = inspect(store)
  if not safe then return nil, err end
  ok, err = call(store.api, "write", store.temp, text)
  if not ok then
    cleanup(store, store.temp)
    return nil, err or "could not write color settings"
  end
  local staged
  staged, err = read(store, store.temp)
  if staged ~= text then
    cleanup(store, store.temp)
    return nil, err or "incomplete color settings write"
  end
  -- Reject changed paths and competing updates before moving the original.
  safe, err = inspect(store)
  if not safe then cleanup(store, store.temp); return nil, err end
  local current
  current, err = read(store, store.path)
  if err or current ~= original then
    cleanup(store, store.temp)
    return nil, err or "color settings changed during save"
  end
  local backup
  backup, err = read(store, store.backup)
  if err or backup ~= nil then
    cleanup(store, store.temp)
    return nil, err or "color settings backup already exists"
  end
  if original ~= nil then
    ok, err = call(store.api, "rename", store.path, store.backup)
    if not ok then cleanup(store, store.temp); return nil, err or "could not back up color settings" end
  end
  -- Windows rename cannot replace an existing destination. All handles are
  -- closed, and the original is moved aside before installing the staged file.
  ok, err = call(store.api, "rename", store.temp, store.path)
  if not ok then
    if original ~= nil then
      local restored = call(store.api, "rename", store.backup, store.path)
      if not restored then
        cleanup(store, store.temp)
        return nil, "could not install color settings; rollback failed; original preserved in color-settings.dat.bak"
      end
    end
    cleanup(store, store.temp)
    return nil, err or "could not install color settings"
  end
  -- A cleanup failure must not discard the newly installed settings or backup.
  if original ~= nil then cleanup(store, store.backup) end
  return true
end

function Preferences.load(home, api)
  local store, err = storage(home, api)
  if not store then return nil, err end
  local safe
  safe, err = inspect(store)
  if not safe then return nil, err end
  local text
  text, err = read(store, store.path)
  if err then return nil, err end
  -- A process interruption between renames leaves the original in .bak.
  -- Loading recovers its data without changing any files or caller settings.
  if text == nil then text, err = read(store, store.backup) end
  if err then return nil, err end
  -- A first-ever save may have finished staging before its final rename.
  if text == nil then text, err = read(store, store.temp) end
  if text == nil then return nil, err end
  return Preferences.decode(text)
end

return Preferences
