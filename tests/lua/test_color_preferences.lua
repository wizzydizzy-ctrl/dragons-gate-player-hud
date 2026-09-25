-- Also runnable directly, without changing the shared tests/run.lua.
local test, eq = test, eq
local standalone, total, failed = type(test) ~= "function", 0, 0
if standalone then
  local root = (arg and arg[0] or ""):match("^(.*)/tests/lua/test_color_preferences%.lua$") or "."
  package.path = root.."/src/?.lua;"..package.path
  test = function(name, fn)
    total = total + 1
    local ok, err = pcall(fn)
    if ok then print("ok "..total.." - "..name)
    else failed = failed + 1; print("not ok "..total.." - "..name.."\n  "..tostring(err)) end
  end
  eq = function(actual, expected)
    if actual ~= expected then error("expected "..tostring(expected)..", got "..tostring(actual), 2) end
  end
end

local Preferences = require("color_preferences")
local Styles = require("color_styles")
local HOME, DIR = "/profile", "/profile/DGHUDData"
local PATH = DIR.."/color-settings.dat"
local HEADER = "DGHUD-COLORS|1\n"

local function reject(fn, ...)
  local ok, value, err = pcall(fn, ...)
  eq(ok, true); eq(value, nil); eq(type(err), "string"); assert(#err > 0)
  return err
end

local function fake(seed)
  local api = {files={}, modes={[HOME]="directory", [DIR]="directory"}, writes=0, mutations=0, renames=0, reads={}}
  for path, text in pairs(seed or {}) do api.files[path] = text end
  function api.symlinkattributes(path)
    if api.statFailure == path then return nil, "permission denied", 13 end
    local mode = api.modes[path] or (api.files[path] ~= nil and "file")
    if mode then return {mode=mode} end
    return nil, "missing", 2
  end
  function api.read(path, limit)
    api.reads[#api.reads+1] = {path=path, limit=limit}
    if api.readFailure == path then return nil, "permission denied", 13 end
    local text = api.files[path]
    if text == nil then return nil end
    return text:sub(1, limit)
  end
  function api.mkdir(path)
    api.mutations = api.mutations + 1
    api.modes[path] = "directory"
    return true
  end
  function api.write(path, text)
    api.mutations, api.writes = api.mutations + 1, api.writes + 1
    if api.partial then
      api.files[path] = text:sub(1, 7)
      if api.partial == "success" then return true end
      if api.partial == "throw" then error("write failure") end
      return nil, "disk full"
    end
    api.files[path] = text
    return true
  end
  function api.rename(from, to)
    api.mutations, api.renames = api.mutations + 1, api.renames + 1
    if api.failRename and api.failRename[api.renames] then return nil, "rename denied" end
    if api.throwRename == api.renames then error("rename failure") end
    -- Match Windows: never overwrite a destination, or rename open handles.
    if api.files[to] ~= nil then return nil, "destination exists" end
    if api.opened and (api.opened[from] or api.opened[to]) then return nil, "file still open" end
    if api.files[from] == nil then return nil, "missing source" end
    api.files[to], api.files[from] = api.files[from], nil
    return true
  end
  function api.remove(path)
    api.mutations = api.mutations + 1
    if api.failRemove == path then return nil, "remove denied" end
    api.files[path] = nil
    return true
  end
  return api
end

test("color preferences keep absent toggles sparse and preserve every false toggle", function()
  local empty = assert(Preferences.snapshot({}))
  eq(next(empty.styles), nil); eq(empty.enabled, nil)
  local config = {enabled=false, highlights_enabled=false}
  for _, feature in ipairs({"room","exits","currency","races","classes","portal","presence","attack","damage","danger","recovery","upkeep","spell","discovery","illumination","notice"}) do
    config[feature.."_enabled"] = false
  end
  local decoded = assert(Preferences.decode(assert(Preferences.encode(config))))
  for key in pairs(config) do eq(decoded[key], false) end
  eq(next(decoded.styles), nil)
end)

test("color preferences save default RGB values without freezing registry defaults", function()
  local config = require("defaults").colorization
  local saved = assert(Preferences.snapshot(config))
  eq(next(saved.styles), nil)
  eq(saved.enabled, config.enabled)
  local toggled = assert(Preferences.snapshot({enabled=false, room_color={224,184,79}}))
  eq(next(toggled.styles), nil)
end)

test("color preferences migrate customized legacy RGB and preserve notice styling", function()
  local saved = assert(Preferences.snapshot({
    enabled=false, room_color={1,2,3}, notice_color={4,5,6}, label_color={139,45,45},
  }))
  eq(saved.styles.room.foreground, "#010203")
  eq(saved.styles.notice.foreground, "#040506")
  eq(saved.styles.notice.background, "#501914")
  eq(saved.styles.notice.bold, true); eq(saved.styles.notice.underline, true)
  eq(saved.styles.label, nil); eq(saved.room_color, nil)
  local restored = assert(Preferences.decode(assert(Preferences.encode(saved))))
  eq(restored.styles.room.foreground, "#010203"); eq(restored.enabled, false)
end)

test("color preferences give explicit styles precedence and retain legacy colors for partial edits", function()
  local saved = assert(Preferences.snapshot({
    room_color={1,2,3}, notice_color={4,5,6},
    styles={room={bold=true, enabled=false}, notice={foreground="#aabbcc", background=false, underline=false}},
  }))
  eq(saved.styles.room.foreground, "#010203"); eq(saved.styles.room.bold, true)
  eq(saved.styles.room.enabled, false); eq(saved.styles.notice.foreground, "#AABBCC")
  eq(saved.styles.notice.background, false); eq(saved.styles.notice.underline, false)
end)

test("color preferences support all registry IDs including names with spaces and hyphens", function()
  local config = {styles={}}
  for _, entry in ipairs(Styles.entries()) do
    config.styles[entry.id] = {foreground={1,2,3}, background="#aabbcc", enabled=false, bold=true, underline=false}
  end
  local decoded = assert(Preferences.decode(assert(Preferences.encode(config))))
  for _, entry in ipairs(Styles.entries()) do
    local style = decoded.styles[entry.id]
    eq(style.foreground, "#010203"); eq(style.background, "#AABBCC")
    eq(style.enabled, false); eq(style.bold, true); eq(style.underline, false)
  end
  assert(decoded.styles["race:fir elf"]); assert(decoded.styles["class:non-elemental mage"])
end)

test("color preferences migrate known legacy named palettes and reject unknown names", function()
  local result = assert(Preferences.snapshot({
    race_colors={human={1,2,3}}, class_colors={["rune mage"]={4,5,6}},
  }))
  eq(result.styles["race:human"].foreground, "#010203")
  eq(result.styles["class:rune mage"].foreground, "#040506")
  reject(Preferences.snapshot, {race_colors={unknown={1,2,3}}})
  reject(Preferences.snapshot, {class_colors=false})
end)

test("color preferences are detached from caller input and deterministic", function()
  local input = {enabled=false, styles={room={foreground={1,2,3}}}}
  local a = assert(Preferences.snapshot(input))
  a.styles.room.foreground = "#FFFFFF"; a.enabled = true
  eq(input.enabled, false); eq(input.styles.room.foreground[1], 1)
  eq(input.styles.room.background, nil)
  local b = assert(Preferences.snapshot(input))
  eq(b.styles.room.foreground, "#010203")
  local text = assert(Preferences.encode(input))
  eq(text, assert(Preferences.encode(assert(Preferences.decode(text)))))
  eq(text, assert(Preferences.encode({styles={room={foreground="#010203"}}, enabled=false})))
end)

test("color preferences reject unknown keys, types, paths and malformed legacy colors", function()
  for _, config in ipairs({
    {enabled=0}, {highlights_enabled="false"}, {room=true}, {darkness_enabled=true},
    {filename="/tmp/other"}, {colorization={}}, {unknown_color={1,2,3}}, {styles=false},
    {styles={unknown={}}}, {styles={room={path="anything"}}},
    {styles={room={bold=1}}}, {styles={room={enabled="false"}}},
    {room_color={1,2}}, {room_color={1,2,3,4}}, {room_color={r=1,g=2,b=3}},
    {room_color={-1,2,3}}, {room_color={256,2,3}}, {room_color={1.5,2,3}},
    {room_color={"1",2,3}}, {room_color={0/0,2,3}}, {room_color={math.huge,2,3}},
    {room_color="#12345"}, {room_color="#GGGGGG"}, {room_color="#123456;os.exit()"},
    {styles={room={foreground="#000000", background="none"}}},
  }) do
    reject(Preferences.snapshot, config)
    reject(Preferences.encode, config)
  end
  reject(Preferences.snapshot, nil); reject(Preferences.snapshot, "return {}")
end)

test("color preferences reject metatables without executing metamethods", function()
  local calls = 0
  local mt = {__index=function() calls=calls+1; error("executed") end,
    __pairs=function() calls=calls+1; error("executed") end}
  reject(Preferences.snapshot, setmetatable({}, mt))
  reject(Preferences.snapshot, {styles=setmetatable({}, mt)})
  reject(Preferences.snapshot, {styles={room=setmetatable({}, mt)}})
  reject(Preferences.snapshot, {room_color=setmetatable({1,2,3}, mt)})
  eq(calls, 0)
end)

test("color preferences reject duplicate, unknown, incomplete and executable records", function()
  for _, text in ipairs({
    "", "return {enabled=true}", "DGHUD-COLORS|2\n", HEADER.."toggle|enabled|true\n",
    HEADER.."toggle|enabled|1\n".."toggle|enabled|0\n",
    HEADER.."toggle|unknown_enabled|1\n", HEADER.."toggle|enabled|1|extra\n",
    HEADER.."toggle|enabled|1", HEADER.."\n", HEADER.."# comment\n",
    HEADER.."style|room|#112233|-|0|0|1\nstyle|room|#112233|-|0|0|1\n",
    HEADER.."style|race:unknown|#112233|-|0|0|1\n",
    HEADER.."style|../../escape|#112233|-|0|0|1\n",
    HEADER.."style|room|#12345|-|0|0|1\n", HEADER.."style|room|1,2,3|-|0|0|1\n",
    HEADER.."style|room|#112233|false|0|0|1\n", HEADER.."style|room|#112233|-|0|0|2\n",
    HEADER.."style|room|#112233|-|0|0|1|extra\n",
    HEADER.."style|room|#112233|-|0|0|1\nos.execute('anything')\n",
    HEADER.."toggle|enabled|1\0\n", HEADER.."toggle|enabled|1\r\n",
    HEADER.."toggle|enabled|1\n--\n", HEADER.."style|room|#FFFFFF|-|0|0|1\nreturn {}\n",
  }) do reject(Preferences.decode, text) end
  reject(Preferences.decode, {}); reject(Preferences.decode, nil)
end)

test("color preferences reject oversized strings and overlong records", function()
  reject(Preferences.decode, string.rep("x", 65537))
  reject(Preferences.decode, HEADER..string.rep("x", 257).."\n")
  reject(Preferences.decode, HEADER..string.rep("toggle|enabled|1\n", 100))
  eq(Preferences.decode(HEADER).enabled, nil)
end)

test("color preferences validate all settings before any filesystem operation", function()
  local api = fake({[PATH]="original"})
  reject(Preferences.save, HOME, {enabled=false, styles={room={foreground="#GG0000"}}}, api)
  eq(api.mutations, 0); eq(#api.reads, 0); eq(api.files[PATH], "original")
end)

test("color preferences save and reload only the fixed profile file", function()
  local api = fake()
  assert(Preferences.save(HOME, {enabled=false, room_color={1,2,3}}, api))
  local result = assert(Preferences.load(HOME, api))
  eq(result.enabled, false); eq(result.styles.room.foreground, "#010203")
  eq(api.files[PATH..".tmp"], nil); eq(api.files[PATH..".bak"], nil)
  eq(api.renames, 1)
  for path in pairs(api.files) do eq(path, PATH) end
end)

test("color preferences replace existing settings with Windows rename semantics", function()
  local api = fake({[PATH]=HEADER.."toggle|enabled|1\n"})
  assert(Preferences.save(HOME, {enabled=false, styles={notice={background=false}}}, api))
  eq(api.renames, 2); eq(api.files[PATH..".tmp"], nil); eq(api.files[PATH..".bak"], nil)
  local result = assert(Preferences.load(HOME, api))
  eq(result.enabled, false); eq(result.styles.notice.background, false)
end)

test("color preferences leave original intact after failed or incomplete writes", function()
  for _, failure in ipairs({"return", "throw", "success"}) do
    local api = fake({[PATH]="original bytes"})
    api.partial = failure
    reject(Preferences.save, HOME, {enabled=false}, api)
    eq(api.files[PATH], "original bytes"); eq(api.files[PATH..".tmp"], nil)
    eq(api.files[PATH..".bak"], nil); eq(api.renames, 0)
  end
end)

test("color preferences restore original after either rename step fails", function()
  for _, step in ipairs({1,2}) do
    for _, throwing in ipairs({false,true}) do
      local api = fake({[PATH]="original bytes"})
      if throwing then api.throwRename=step else api.failRename={[step]=true} end
      reject(Preferences.save, HOME, {enabled=false}, api)
      eq(api.files[PATH], "original bytes"); eq(api.files[PATH..".tmp"], nil)
      eq(api.files[PATH..".bak"], nil)
    end
  end
end)

test("color preferences clean staging after a failed initial install", function()
  local api = fake()
  api.failRename = {[1]=true}
  reject(Preferences.save, HOME, {enabled=false}, api)
  eq(api.files[PATH], nil); eq(api.files[PATH..".tmp"], nil); eq(api.files[PATH..".bak"], nil)
end)

test("color preferences preserve a recoverable backup if rollback also fails", function()
  local original = HEADER.."toggle|enabled|0\n"
  local api = fake({[PATH]=original})
  api.failRename = {[2]=true, [3]=true}
  local err = reject(Preferences.save, HOME, {enabled=true}, api)
  assert(err:find("rollback failed", 1, true))
  eq(api.files[PATH], nil); eq(api.files[PATH..".bak"], original)
  local before = api.mutations
  eq(assert(Preferences.load(HOME, api)).enabled, false); eq(api.mutations, before)
  api.failRename = nil
  assert(Preferences.save(HOME, {enabled=true}, api))
  eq(assert(Preferences.load(HOME, api)).enabled, true)
  eq(api.files[PATH..".bak"], nil); eq(api.files[PATH..".tmp"], nil)
end)

test("color preferences retain successful save if backup cleanup fails", function()
  local api = fake({[PATH]=HEADER.."toggle|enabled|1\n"})
  api.failRemove = PATH..".bak"
  assert(Preferences.save(HOME, {enabled=false}, api))
  eq(assert(Preferences.load(HOME, api)).enabled, false)
  eq(api.files[PATH..".bak"], HEADER.."toggle|enabled|1\n")
  api.failRemove = nil
  assert(Preferences.save(HOME, {enabled=true}, api))
  eq(assert(Preferences.load(HOME, api)).enabled, true)
  eq(api.files[PATH..".bak"], nil); eq(api.files[PATH..".tmp"], nil)
end)

test("color preferences never overwrite unrecognized staging files or backups", function()
  for _, suffix in ipairs({".tmp", ".bak"}) do
    local api = fake({[PATH]="original", [PATH..suffix]="reserved"})
    reject(Preferences.save, HOME, {enabled=false}, api)
    eq(api.mutations, 0); eq(api.files[PATH], "original"); eq(api.files[PATH..suffix], "reserved")
  end
end)

test("color preferences load absent files quietly without creating directories", function()
  local api = fake()
  local config, err = Preferences.load(HOME, api)
  eq(config, nil); eq(err, nil); eq(api.mutations, 0)
  api.read = function() return nil, "No such file or directory", 2 end
  config, err = Preferences.load(HOME, api)
  eq(config, nil); eq(err, nil)
end)

test("color preferences fail closed on permission and read errors", function()
  local api = fake({[PATH]=HEADER})
  api.readFailure = PATH
  reject(Preferences.load, HOME, api); reject(Preferences.save, HOME, {}, api)
  eq(api.mutations, 0)
  api.read = function() error("read failed") end
  reject(Preferences.load, HOME, api)
  api.read = function() return false end
  reject(Preferences.load, HOME, api)
end)

test("color preferences request bounded reads and reject an oversized file", function()
  local api = fake({[PATH]=HEADER..string.rep("x", 100000)})
  reject(Preferences.load, HOME, api); reject(Preferences.save, HOME, {}, api)
  for _, read in ipairs(api.reads) do eq(read.limit, 65537) end
  eq(api.mutations, 0)
end)

test("color preferences never fall back from corrupt primary data to a backup", function()
  local api = fake({[PATH]="return {}", [PATH..".bak"]=HEADER.."toggle|enabled|1\n"})
  reject(Preferences.load, HOME, api); eq(api.mutations, 0)
end)

test("color preferences reject symlinks and nonregular storage paths before mutation", function()
  for _, path in ipairs({HOME, DIR, PATH, PATH..".tmp", PATH..".bak"}) do
    for _, mode in ipairs({"link", "socket"}) do
      local api = fake({[PATH]=HEADER})
      api.modes[path] = mode
      reject(Preferences.save, HOME, {}, api); reject(Preferences.load, HOME, api)
      eq(api.mutations, 0); eq(api.files[PATH], HEADER)
    end
  end
  local api = fake({[PATH]=HEADER})
  api.statFailure = PATH
  reject(Preferences.load, HOME, api); reject(Preferences.save, HOME, {}, api)
  eq(api.mutations, 0)
end)

test("color preferences also use injected lfs symlink inspection", function()
  local api = fake({[PATH]=HEADER})
  api.lfs = {symlinkattributes=api.symlinkattributes}
  api.symlinkattributes = nil; api.modes[PATH] = "link"
  reject(Preferences.load, HOME, api); reject(Preferences.save, HOME, {}, api)
  eq(api.mutations, 0)
end)

test("color preferences contain mkdir errors and do not mutate on invalid homes or APIs", function()
  local api = fake({[PATH]="original"})
  api.mkdir = function() error("mkdir denied") end
  reject(Preferences.save, HOME, {}, api); eq(api.files[PATH], "original"); eq(api.writes, 0)
  for _, home in ipairs({"", "../escape", "/profile/../escape", "/profile\0other", "/profile\nother"}) do
    reject(Preferences.save, home, {}, api); reject(Preferences.load, home, api)
  end
  reject(Preferences.save, HOME, {}, false); reject(Preferences.load, HOME, false)
  reject(Preferences.save, HOME, {}, {}); reject(Preferences.load, HOME, {})
end)

test("color preferences support spaces and Windows profile paths", function()
  local api = fake()
  local home = "C:\\Users\\Player Name\\profile\\"
  assert(Preferences.save(home, {enabled=false}, api))
  local path = "C:\\Users\\Player Name\\profile/DGHUDData/color-settings.dat"
  assert(api.files[path]); eq(assert(Preferences.load(home, api)).enabled, false)
end)

test("color preferences detect competing updates before replacing the original", function()
  local api = fake({[PATH]="original"})
  local write = api.write
  api.write = function(path, text)
    local ok = write(path, text)
    api.files[PATH] = "newer concurrent data"
    return ok
  end
  reject(Preferences.save, HOME, {}, api)
  eq(api.files[PATH], "newer concurrent data"); eq(api.renames, 0)
end)

-- Exercise native handle management with an in-memory filesystem. All global
-- functions are restored even when an assertion fails.
local function withNative(fault, fn)
  local api = fake({[PATH]=HEADER.."toggle|enabled|1\n"})
  local oldOpen, oldRename, oldRemove, oldLfs = io.open, os.rename, os.remove, rawget(_G, "lfs")
  api.opened = {}
  _G.lfs = {
    symlinkattributes=api.symlinkattributes, mkdir=api.mkdir,
    attributes=function(path) return api.modes[path] end,
  }
  os.rename, os.remove = api.rename, api.remove
  io.open = function(path, mode)
    if mode == "rb" and api.files[path] == nil then return nil, "missing", 2 end
    if mode == "wb" then api.files[path] = "" end
    api.opened[path] = true
    return {
      read=function(_, limit)
        eq(type(limit), "number"); assert(limit <= 65537)
        if fault == "read" then error("read failed") end
        return api.files[path]:sub(1, limit)
      end,
      write=function(self, text)
        api.files[path] = text
        if fault == "write" then return nil, "write failed" end
        return self
      end,
      flush=function()
        if fault == "flush" then return nil, "flush failed" end
        return true
      end,
      close=function()
        api.opened[path] = nil
        if fault == "close" and path == PATH..".tmp" then return nil, "close failed" end
        return true
      end,
    }
  end
  local ok, err = pcall(fn, api)
  io.open, os.rename, os.remove, _G.lfs = oldOpen, oldRename, oldRemove, oldLfs
  assert(ok, err)
end

test("color preferences native IO flushes and closes before Windows renames", function()
  withNative(nil, function(api)
    assert(Preferences.save(HOME, {enabled=false}))
    eq(assert(Preferences.load(HOME)).enabled, false); eq(next(api.opened), nil)
  end)
end)

test("color preferences native IO closes handles and preserves original on failures", function()
  for _, fault in ipairs({"read", "write", "flush", "close"}) do
    withNative(fault, function(api)
      reject(Preferences.save, HOME, {enabled=false})
      eq(api.files[PATH], HEADER.."toggle|enabled|1\n"); eq(next(api.opened), nil)
      eq(api.renames, 0)
    end)
  end
end)

local recoveryOriginal = HEADER.."toggle|enabled|0\nstyle|room|#010203|-|0|0|1\n"
local recoveryBackup = HEADER.."toggle|enabled|1\nstyle|room|#111213|-|0|0|1\n"
local recoveryTemp = HEADER.."toggle|enabled|1\nstyle|room|#212223|-|0|0|1\n"
local recoveryCases = {
  {primary=true, backup=true}, {primary=true, temp=true},
  {primary=true, backup=true, temp=true}, {backup=true},
  {temp=true}, {backup=true, temp=true},
}
local function recoveryFiles(case)
  local files = {}
  if case.primary then files[PATH] = recoveryOriginal end
  if case.backup then files[PATH..".bak"] = recoveryBackup end
  if case.temp then files[PATH..".tmp"] = recoveryTemp end
  return files, case.primary and recoveryOriginal or (case.backup and recoveryBackup or recoveryTemp)
end

test("color preferences load verified leftovers by priority without changing files", function()
  for _, case in ipairs(recoveryCases) do
    local files, expected = recoveryFiles(case)
    local api = fake(files)
    local loaded = assert(Preferences.load(HOME, api))
    eq(loaded.styles.room.foreground, assert(Preferences.decode(expected)).styles.room.foreground)
    eq(api.mutations, 0)
    for path, value in pairs(files) do eq(api.files[path], value) end
  end
end)

test("color preferences reconcile valid leftovers and allow repeated saves", function()
  for _, case in ipairs(recoveryCases) do
    local files = recoveryFiles(case)
    local api = fake(files)
    assert(Preferences.save(HOME, {enabled=false, room_color={3,4,5}}, api))
    eq(assert(Preferences.load(HOME, api)).styles.room.foreground, "#030405")
    eq(api.files[PATH..".bak"], nil); eq(api.files[PATH..".tmp"], nil)
    assert(Preferences.save(HOME, {enabled=true, room_color={6,7,8}}, api))
    eq(assert(Preferences.load(HOME, api)).styles.room.foreground, "#060708")
    for path in pairs(api.files) do eq(path, PATH) end
  end
end)

test("color preferences preserve the authoritative original if a write fails after recovery", function()
  for _, case in ipairs(recoveryCases) do
    local files, expected = recoveryFiles(case)
    local api = fake(files)
    api.partial = "return"
    reject(Preferences.save, HOME, {enabled=true}, api)
    eq(api.files[PATH], expected)
    eq(api.files[PATH..".bak"], nil); eq(api.files[PATH..".tmp"], nil)
    api.partial = nil
    assert(Preferences.save(HOME, {enabled=true}, api))
  end
end)

test("color preferences preserve both recovery sources when restoration fails", function()
  for _, case in ipairs({{backup=true, temp=true}, {temp=true}}) do
    for _, throwing in ipairs({false, true}) do
      local files = recoveryFiles(case)
      local api = fake(files)
      if throwing then api.throwRename = 1 else api.failRename = {[1]=true} end
      reject(Preferences.save, HOME, {enabled=false}, api)
      eq(api.files[PATH], nil); eq(api.writes, 0)
      for path, value in pairs(files) do eq(api.files[path], value) end
      api.throwRename, api.failRename = nil, nil
      assert(Preferences.save(HOME, {enabled=false}, api))
    end
  end
end)

test("color preferences roll back to the recovered original when the new install fails", function()
  for _, step in ipairs({2,3}) do
    local api = fake({[PATH..".bak"]=recoveryBackup, [PATH..".tmp"]=recoveryTemp})
    -- Rename 1 restores the backup, 2 stages it again, 3 installs the new data.
    api.failRename = {[step]=true}
    reject(Preferences.save, HOME, {enabled=false}, api)
    eq(api.files[PATH], recoveryBackup)
    eq(api.files[PATH..".bak"], nil); eq(api.files[PATH..".tmp"], nil)
    api.failRename = nil
    assert(Preferences.save(HOME, {enabled=false}, api))
  end
end)

test("color preferences keep the only restored original when temporary cleanup fails", function()
  local api = fake({[PATH..".bak"]=recoveryBackup, [PATH..".tmp"]=recoveryTemp})
  api.failRemove = PATH..".tmp"
  reject(Preferences.save, HOME, {enabled=false}, api)
  eq(api.files[PATH], recoveryBackup); eq(api.files[PATH..".tmp"], recoveryTemp)
  eq(api.writes, 0)
  api.failRemove = nil
  assert(Preferences.save(HOME, {enabled=false}, api))
  eq(api.files[PATH..".tmp"], nil)
end)

test("color preferences retry leftover cleanup after a transient removal error", function()
  for _, suffix in ipairs({".bak", ".tmp"}) do
    local api = fake({[PATH]=recoveryOriginal, [PATH..suffix]=recoveryBackup})
    api.failRemove = PATH..suffix
    reject(Preferences.save, HOME, {enabled=true}, api)
    eq(api.files[PATH], recoveryOriginal); eq(api.files[PATH..suffix], recoveryBackup)
    eq(api.writes, 0)
    api.failRemove = nil
    assert(Preferences.save(HOME, {enabled=true}, api))
    eq(api.files[PATH..".bak"], nil); eq(api.files[PATH..".tmp"], nil)
  end
end)

test("color preferences preserve corrupt unknown and oversized leftovers without any recovery mutation", function()
  for _, invalid in ipairs({
    "", "unknown backup bytes", "DGHUD-COLORS|2\n", "return {enabled=false}",
    HEADER.."style|unknown|#112233|-|0|0|1\n",
    HEADER.."toggle|enabled|0\ntoggle|enabled|1\n", string.rep("x", 65537),
  }) do
    for _, suffix in ipairs({".bak", ".tmp"}) do
      for _, hasPrimary in ipairs({false, true}) do
        local files = {[PATH..".bak"]=recoveryBackup, [PATH..".tmp"]=recoveryTemp}
        if hasPrimary then files[PATH] = recoveryOriginal end
        files[PATH..suffix] = invalid
        local api = fake(files)
        reject(Preferences.save, HOME, {enabled=true}, api)
        eq(api.mutations, 0)
        for path, value in pairs(files) do eq(api.files[path], value) end
        if hasPrimary then
          eq(assert(Preferences.load(HOME, api)).styles.room.foreground, "#010203")
        elseif suffix == ".bak" then
          reject(Preferences.load, HOME, api)
        end
        eq(api.mutations, 0)
      end
    end
  end
end)

test("color preferences never discard a valid backup for a corrupt original", function()
  local api = fake({[PATH]="corrupt original", [PATH..".bak"]=recoveryBackup, [PATH..".tmp"]=recoveryTemp})
  reject(Preferences.save, HOME, {enabled=true}, api)
  eq(api.files[PATH], "corrupt original")
  eq(api.files[PATH..".bak"], recoveryBackup); eq(api.files[PATH..".tmp"], recoveryTemp)
  eq(api.mutations, 0)
end)

test("color preferences reject corrupt first-save staging and preserve its bytes", function()
  local api = fake({[PATH..".tmp"]="incomplete staged data"})
  reject(Preferences.load, HOME, api); reject(Preferences.save, HOME, {}, api)
  eq(api.files[PATH..".tmp"], "incomplete staged data"); eq(api.mutations, 0)
end)

test("color preferences do not recover any files before validating the requested settings", function()
  local api = fake({[PATH..".bak"]=recoveryBackup, [PATH..".tmp"]=recoveryTemp})
  reject(Preferences.save, HOME, {enabled="false"}, api)
  eq(api.mutations, 0); eq(#api.reads, 0)
  eq(api.files[PATH..".bak"], recoveryBackup); eq(api.files[PATH..".tmp"], recoveryTemp)
end)

test("color preferences preserve changed leftovers instead of deleting unvalidated replacements", function()
  local api = fake({[PATH]=recoveryOriginal, [PATH..".bak"]=recoveryBackup})
  local read, count = api.read, 0
  api.read = function(path, limit)
    if path == PATH..".bak" then
      count = count + 1
      if count == 2 then api.files[path] = "externally replaced backup" end
    end
    return read(path, limit)
  end
  reject(Preferences.save, HOME, {enabled=true}, api)
  eq(api.files[PATH], recoveryOriginal); eq(api.files[PATH..".bak"], "externally replaced backup")
  eq(api.mutations, 0)
end)

test("color preferences preserve leftovers when recovery inspection or reads fail", function()
  for _, path in ipairs({PATH..".bak", PATH..".tmp"}) do
    for _, failure in ipairs({"readFailure", "statFailure"}) do
      local files = {[PATH]=recoveryOriginal, [PATH..".bak"]=recoveryBackup, [PATH..".tmp"]=recoveryTemp}
      local api = fake(files); api[failure] = path
      reject(Preferences.save, HOME, {enabled=true}, api)
      eq(api.mutations, 0)
      for name, value in pairs(files) do eq(api.files[name], value) end
    end
  end
end)

if standalone then
  print(string.format("%d color preference tests, %d failures", total, failed))
  assert(failed == 0, "color preference tests failed")
end
