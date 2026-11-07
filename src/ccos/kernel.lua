--[[
  ccOS                                                        v3.0

  A Windows 8.1-style touch OS for CC: Tweaked. The main advanced monitor
  runs Big Picture (Start tiles, full-screen apps, PC settings) and the
  computer becomes its keyboard; with no monitor the computer runs Big
  Picture itself. Smaller monitors show information panels, two speakers
  form a stereo pair, and printers and disk drives are built in.

  Every app is an ordinary CC program in its own full-screen window, so
  the CraftOS shell, edit, paint and friends work unchanged; ccOS's own
  apps add the `ccos` API on top.
]]

local VERSION = "3.0"
local ROOT = "/ccos"
local CONFIG_PATH = ROOT .. "/config.cfg"
local nativeTerm = term.current()
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local function now() return os.epoch("utc") end

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end
local function trunc(s, w)
  s = tostring(s)
  if w <= 0 then return "" end
  if #s > w then return s:sub(1, w) end
  return s
end
local function padR(s, w) s = trunc(s, w); return s .. (" "):rep(w - #s) end
local function padL(s, w) s = trunc(s, w); return (" "):rep(w - #s) .. s end
local function centre(s, w)
  s = trunc(s, w)
  local l = floor((w - #s) / 2)
  return (" "):rep(l) .. s .. (" "):rep(w - #s - l)
end
local function wrap(text, w)
  local lines = {}
  for para in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    local line = ""
    for found in para:gmatch("%S+") do
      local word = found
      while #word > w do
        if #line > 0 then lines[#lines + 1] = line; line = "" end
        lines[#lines + 1] = word:sub(1, w)
        word = word:sub(w + 1)
      end
      if #line == 0 then line = word
      elseif #line + 1 + #word <= w then line = line .. " " .. word
      else lines[#lines + 1] = line; line = word end
    end
    lines[#lines + 1] = line
  end
  while #lines > 1 and lines[#lines] == "" do lines[#lines] = nil end
  return lines
end
local function fmtDur(sec)
  sec = floor(sec)
  if sec < 60 then return sec .. "s" end
  local m = floor(sec / 60)
  if m < 60 then return ("%dm %02ds"):format(m, sec % 60) end
  local h = floor(m / 60)
  if h < 24 then return ("%dh %02dm"):format(h, m % 60) end
  return ("%dd %02dh"):format(floor(h / 24), h % 24)
end
local function fmtTime(sec)
  sec = floor(sec or 0)
  return ("%d:%02d"):format(floor(sec / 60), sec % 60)
end

local K = { version = VERSION, root = ROOT, require = require, running = true }
local rootShell = shell

local function loadModule(path)
  local fn, err = loadfile(path, nil, setmetatable({}, { __index = _G }))
  if not fn then error(err, 0) end
  return fn()
end

local device=loadModule(ROOT.."/lib/device.lua")
K.device=device.detect(pocket,nativeTerm)
local gfx = loadModule(ROOT .. "/lib/gfx.lua")
local HEX = gfx.HEX
local clock = loadModule(ROOT .. "/lib/time.lua")
local catalog = loadModule(ROOT .. "/lib/catalog.lua")
local json = loadModule(ROOT .. "/lib/json.lua")
local sha256=loadModule(ROOT.."/lib/sha256.lua")
local encoding=loadModule(ROOT.."/lib/encoding.lua")
K.encoding=encoding
local installer=loadModule(ROOT.."/lib/install.lua")
K.clock, K.catalog, K.json = clock, catalog, json

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------

local DEFAULTS = {
  user = "Home", startColor = "purple", accentColor = "teal",
  clock24 = false, seconds = false, leadingZero = false, timezone = "local", utcOffset = 0,
  sounds = true, touchSounds = true, uiVolume = 0.6, musicVolume = 0.8, balance = 0, swapSpeakers = false,
  screens = {}, panelRotate = 12, idle = 300,
  autoUpdates=true, deviceKind="desktop",
  monitorFavorites={"files","music","clock","calc","settings","agent","notes","checklist","worldclock","units","redstone","peripherals"},
  recent = {}, screenLayout = 0, setupComplete = false, agentModel = "openrouter/auto", agentConfirm = true, agentMaxSteps = 16, agentMaxTokens = 2048,
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

local function loadConfig()
  local cfg = {}
  for k, v in pairs(DEFAULTS) do cfg[k] = copy(v) end
  local configSource = fs.exists(CONFIG_PATH) and CONFIG_PATH or "/aurora/config.cfg"
  if fs.exists(configSource) then
    local h = fs.open(configSource, "r")
    local data = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(data) == "table" then
      for k, v in pairs(data) do
        if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then cfg[k] = v end
      end
    end
  end
  cfg.deviceKind=K.device.kind
  K.cfg = cfg
end

function K.saveConfig()
  local h = fs.open(CONFIG_PATH, "w")
  if h then
    h.write(textutils.serialize(K.cfg))
    h.close()
  end
end

------------------------------------------------------------------------
-- Colours. Every screen uses one flat Windows 8.1 palette: dark app
-- surfaces, white type and saturated tile colours. The semantic slots
-- below never change; the Start background (select) and the accent follow
-- the chosen Start and accent colours.
------------------------------------------------------------------------

local C = colors
local T = {
  bg = C.black, surface = C.gray, raised = C.brown, text = C.white, muted = C.lightGray,
  accent = C.cyan, accent2 = C.purple, select = C.blue, danger = C.red, ok = C.lime,
  warn = C.yellow, info = C.lightBlue, hot = C.pink, orange = C.orange, green = C.green, magenta = C.magenta,
}
K.T = T

local function pal(t)
  return {
    [C.black] = t[1], [C.gray] = t[2], [C.brown] = t[3], [C.lightGray] = t[4], [C.white] = t[5],
    [C.cyan] = t[6], [C.blue] = t[7], [C.purple] = t[8], [C.magenta] = t[9], [C.pink] = t[10],
    [C.lime] = t[11], [C.green] = t[12], [C.yellow] = t[13], [C.orange] = t[14], [C.red] = t[15],
    [C.lightBlue] = t[16],
  }
end

local START_COLORS = {
  { id = "purple", name = "Purple", rgb = 0x2A1660 }, { id = "indigo", name = "Indigo", rgb = 0x1B2A6B },
  { id = "blue", name = "Blue", rgb = 0x00316E }, { id = "teal", name = "Teal", rgb = 0x00575E },
  { id = "green", name = "Green", rgb = 0x1A5627 }, { id = "olive", name = "Olive", rgb = 0x4F5A12 },
  { id = "orange", name = "Rust", rgb = 0x8A2E0C }, { id = "red", name = "Crimson", rgb = 0x7A0A26 },
  { id = "magenta", name = "Magenta", rgb = 0x6E0F5E }, { id = "charcoal", name = "Charcoal", rgb = 0x262626 },
}
local ACCENT_COLORS = {
  { id = "teal", name = "Teal", rgb = 0x00ABA9 }, { id = "blue", name = "Blue", rgb = 0x2D89EF },
  { id = "cobalt", name = "Cobalt", rgb = 0x0050EF }, { id = "violet", name = "Violet", rgb = 0x8E44D8 },
  { id = "magenta", name = "Magenta", rgb = 0xD80073 }, { id = "red", name = "Red", rgb = 0xE51400 },
  { id = "orange", name = "Orange", rgb = 0xF09609 }, { id = "lime", name = "Lime", rgb = 0x8CBF26 },
  { id = "emerald", name = "Emerald", rgb = 0x008A00 },
}
K.START_COLORS, K.ACCENT_COLORS = START_COLORS, ACCENT_COLORS
local function pick(list, id)
  for _, c in ipairs(list) do if c.id == id then return c.rgb end end
  return list[1].rgb
end
local function metroPalette()
  return pal({ 0x1D1D1D, 0x2B2B2B, 0x464646, 0xA6A6A6, 0xFFFFFF, pick(ACCENT_COLORS, K.cfg.accentColor),
    pick(START_COLORS, K.cfg.startColor), 0x603CBA, 0x9F00A7, 0xD80073, 0x00A300, 0x1E7145, 0xE3A21A, 0xDA532C, 0xE51400, 0x2D89EF })
end
K.metroPalette = metroPalette

local function applyPalette(t)
  local p = metroPalette()
  for i = 0, 15 do
    local c = floor(2 ^ i)
    t.setPaletteColour(c, p[c] or term.nativePaletteColour(c))
  end
end

local function resetPalette(t)
  for i = 0, 15 do
    local c = floor(2 ^ i)
    t.setPaletteColour(c, term.nativePaletteColour(c))
  end
end

------------------------------------------------------------------------
-- Apps
------------------------------------------------------------------------

local APPS = {
  { id = "files", name = "Files", desc = "Browse, copy and open files", path = "files", w = 78, h = 24 },
  { id = "terminal", name = "Terminal", desc = "The CraftOS shell", shell = true, w = 64, h = 20 },
  { id = "music", name = "Music", desc = "Stereo player and library", path = "music", w = 74, h = 24 },
  { id = "piano", name = "Piano", desc = "Play notes across both speakers", path = "piano", w = 76, h = 20 },
  { id = "clock", name = "Clock", desc = "Time, stopwatch and timers", path = "clock", w = 56, h = 20 },
  { id = "calc", name = "Calculator", desc = "Sums with history", path = "calc", w = 34, h = 22 },
  { id = "print", name = "Print Center", desc = "Print files, notes and banners", path = "print", w = 60, h = 22 },
  { id = "tasks", name = "Tasks", desc = "Windows, processes and devices", path = "tasks", w = 70, h = 22 },
  { id = "settings", name = "Settings", desc = "Themes, sound and screens", path = "settings", w = 74, h = 24 },
  { id = "about", name = "About", desc = "About ccOS", path = "about", w = 56, h = 18 },
  { id = "viewer", name = "Viewer", desc = "Read a text file", path = "viewer", w = 76, h = 24, hidden = true },
  { id = "edit", name = "Editor", desc = "Edit a file", program = "/rom/programs/edit.lua", needsFile = true, w = 76, h = 22 },
  { id = "paint", name = "Paint", desc = "Draw an image", program = "/rom/programs/fun/advanced/paint.lua", needsFile = true, w = 60, h = 20 },
  { id = "lua", name = "Lua", desc = "Interactive Lua prompt", program = "/rom/programs/lua.lua", w = 64, h = 18 },
  { id = "worm", name = "Worm", desc = "The classic snake game", program = "/rom/programs/fun/worm.lua", w = 51, h = 19 },
}
APPS[#APPS + 1] = { id="notifications", name="Notifications", desc="System and agent notifications", path="notifications", category="System", touch=true, w=64,h=22 }
APPS[#APPS + 1] = { id="devices", name="Devices", desc="Drives, printer and speakers", path="tasks", category="System", touch=true,w=70,h=22 }
APPS[#APPS + 1] = { id="agent", name="AI Agent", desc="OpenRouter assistant with OS tools", path="agent", category="AI", touch=true, w=76, h=24 }
for _, app in ipairs(APPS) do
  app.category = app.category or catalog.base[app.id] or "System"
  -- Every app runs full screen in Big Picture.
  app.touch = true
end
for _, app in ipairs(catalog.apps()) do APPS[#APPS+1] = app end
local categoryIcons={Files="files",Time="clock",Media="music",Math="calc",Text="viewer",Developer="terminal",System="tasks",Games="worm",AI="agent"}
for _,a in ipairs(APPS)do
  local source=categoryIcons[a.category]or "about"
  gfx.ICONS[a.id]=gfx.ICONS[a.id]or gfx.ICONS[source]
  gfx.GLYPHS[a.id]=gfx.GLYPHS[a.id]or gfx.GLYPHS[source]
end
K.APPS = APPS
function K.canTouchApp(app, screen)
  local minimum={agent=8,clock=12,calc=12,calendar=12,lights=12,memory=12,tictactoe=12}
  return app and app.touch and screen.w>=32 and screen.h-2>=(minimum[app.id]or 8)
end
local function appById(id)
  for _, a in ipairs(APPS) do if a.id == id then return a end end
end

------------------------------------------------------------------------
-- Processes. Each runs in a coroutine with its own terminal; the kernel
-- resumes them with events like multishell does, but several are shown
-- at once.
------------------------------------------------------------------------

local procs, wins = {}, {}
local nextPid = 1
local running = nil
local capture = nil
local killList = {}
K.procs, K.wins = procs, wins

local layout, removeWindow, newWindow, markDirty, markAll

local function makeBuffer(w, h)
  local win = window.create(nativeTerm, 1, 1, w, h, false)
  local buf = setmetatable({ changed = true, raw = win }, { __index = win })
  for _, k in ipairs({ "write", "blit", "clear", "clearLine", "scroll", "setCursorPos", "setCursorBlink",
    "setTextColor", "setTextColour", "setBackgroundColor", "setBackgroundColour" }) do
    local f = win[k]
    buf[k] = function(...)
      buf.changed = true
      return f(...)
    end
  end
  return buf
end

local function post(p, ev)
  if p and not p.dead then p.inbox[#p.inbox + 1] = ev end
end
K.post = post

local function logCrash(p, err)
  local h = fs.open(ROOT .. "/crash.log", "a")
  if h then
    h.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(p.title) .. ": " .. tostring(err))
    h.close()
  end
end

local function onExit(p)
  for _,s in ipairs(K.screens or {})do
    for i=#(s.dialogs or {}),1,-1 do if s.dialogs[i].owner==p then table.remove(s.dialogs,i);if markDirty then markDirty(s)end end end
  end
  if p.win then removeWindow(p.win) end
  if p.err and not p.killed then
    logCrash(p, p.err)
    K.notify(p.title .. " stopped", tostring(p.err), { color = T.danger, icon = "tasks" })
  end
end

local function resume(p, ev)
  if p.dead then return end
  if p.filter and p.filter ~= ev[1] and ev[1] ~= "terminate" then return end
  local prev = term.current()
  if p.term then term.redirect(p.term) end
  local before = running
  running = p
  local t0 = now()
  local ok, res = coroutine.resume(p.co, table.unpack(ev, 1, ev.n or #ev))
  p.cpu = p.cpu + (now() - t0)
  running = before
  if p.term then p.term = term.current() end
  term.redirect(prev)
  if not ok then
    p.dead, p.err = true, res
    onExit(p)
  elseif coroutine.status(p.co) == "dead" then
    p.dead = true
    onExit(p)
  else
    p.filter = res
  end
  if p.win and p.win.buf.changed then
    p.win.buf.changed = false
    markDirty(p.win.screen)
  end
end

-- opts: title, app, service, window = {screen, w, h}
function K.spawn(fn, opts)
  opts = opts or {}
  local p = { id = nextPid, title = opts.title or "Task", app = opts.app, cpu = 0, started = now(),
    inbox = { { n = 0 } }, service = opts.service }
  nextPid = nextPid + 1
  p.co = coroutine.create(fn)
  if opts.window then
    p.win = newWindow(p, opts.window)
    p.term = p.win.buf
  end
  procs[#procs + 1] = p
  os.queueEvent("ccos_wake")
  return p
end

function K.kill(p)
  if p.dead then return end
  p.dead, p.killed = true, true
  onExit(p)
end

local function broadcast(ev)
  for i = 1, #procs do
    local p = procs[i]
    if p and not p.dead then resume(p, ev) end
  end
end

local function drain()
  for _ = 1, 64 do
    local any = false
    local i = 1
    while i <= #procs do
      local p = procs[i]
      if not p.dead and #p.inbox > 0 then
        any = true
        resume(p, table.remove(p.inbox, 1))
      end
      i = i + 1
    end
    if not any then break end
  end
  for _, p in ipairs(killList) do K.kill(p) end
  killList = {}
  for i = #procs, 1, -1 do
    if procs[i].dead then table.remove(procs, i) end
  end
end

------------------------------------------------------------------------
-- Screens
------------------------------------------------------------------------

local screens, screenByName = {}, {}
K.screens = screens

local function monitorBlocks(m)
  local s = m.getTextScale and m.getTextScale() or 1
  local w, h = m.getSize()
  return floor(w * s * 6 / 64 + 0.3125 + 0.5), floor(h * s * 9 / 64 + 0.3125 + 0.5)
end
K.monitorBlocks = monitorBlocks

local function charsAt(bw, bh, s)
  return max(1, floor((bw - 0.3125) / (s * 6 / 64) + 0.5)), max(1, floor((bh - 0.3125) / (s * 9 / 64) + 0.5))
end

local function autoScale(m, role)
  local bw, bh = monitorBlocks(m)
  local needW, needH = 60, 30
  if role == "panel" then needW, needH = 40, 8 end
  for s = 5, 0.5, -0.5 do
    local w, h = charsAt(bw, bh, s)
    if w >= needW and h >= needH then return s end
  end
  return 0.5
end

local function setupScreen(s)
  if s.kind == "monitor" then
    local want = s.scaleCfg == "auto" and autoScale(s.target, s.role) or s.scaleCfg
    local cur = s.target.getTextScale and s.target.getTextScale()
    if cur ~= want then
      s.target.setTextScale(want)
      s.scaleAt = now()
    end
  end
  s.w, s.h = s.target.getSize()
  s.buf = window.create(s.target, 1, 1, s.w, s.h, false)
  s.cache = {}
  s.touch = s.kind == "monitor"
  applyPalette(s.target)
  s.target.setCursorBlink(false)
  s.dirty = true
end

-- Big Picture is the only shell. The main advanced monitor runs it and the
-- computer becomes its keyboard console; with no such monitor the computer
-- runs Big Picture itself. Pocket computers keep their compact launcher.
function K.pictureScreen()
  if K.device.pocket then return nil end
  local s = K.primaryMonitorName and screenByName[K.primaryMonitorName]
  if s and s.role == "picture" then return s end
  for _, c in ipairs(screens) do if c.kind == "monitor" and c.role == "picture" then return c end end
  local t = screenByName.term
  if t and t.role == "picture" then return t end
end

function K.homeScreen()
  return K.pictureScreen() or screenByName.term
end

function K.activeScreen()
  local last = K.lastScreen
  if last and last.role == "picture" and screenByName[last.name] == last then return last end
  return K.homeScreen()
end

-- The app a Big Picture screen shows full screen, if any.
function K.pictureApp(s)
  local v = s and s.picture
  if not v or not v.appPid then return end
  for _, w in ipairs(wins) do
    if w.id == v.appPid and w.screen == s and not w.proc.dead then return w end
  end
end

local function hosts(s) return s.role == "picture" or s.role == "pocket" end

function K.buildScreens()
  local list, byName = {}, {}
  -- The retired desktop and Full Sync roles become Big Picture.
  local migrated = false
  for _, conf in pairs(K.cfg.screens) do
    if type(conf) == "table" and (conf.role == "desktop" or conf.role == "mirror") then
      conf.role, conf.scale, migrated = "picture", "auto", true
    end
  end
  if K.cfg.screenLayout < 3 then K.cfg.screenLayout, migrated = 3, true end
  if migrated then K.saveConfig() end
  local function make(name, target, kind, defaultRole, color)
    local s = screenByName[name] or { name = name, hits = {}, cache = {} }
    local conf = K.cfg.screens[name] or {}
    s.target, s.kind = target, kind
    local was = s.role
    s.role = conf.role or defaultRole
    -- Basic monitors cannot be touched, so they show the info panel.
    if kind == "monitor" and s.role == "picture" and not color then s.role = "panel" end
    s.scaleCfg = conf.scale or "auto"
    if was and was ~= "off" and s.role == "off" then
      pcall(function()
        resetPalette(target)
        target.setBackgroundColor(colors.black)
        target.clear()
      end)
    end
    list[#list + 1] = s
    byName[name] = s
    return s
  end
  local home = make("term", nativeTerm, "term", "picture", true)
  local mons = {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "monitor" then
      local m = peripheral.wrap(n)
      local bw, bh = monitorBlocks(m)
      mons[#mons + 1] = { name = n, m = m, area = bw * bh, color = m.isColor and m.isColor() or false }
    end
  end
  table.sort(mons, function(a, b)
    if a.color ~= b.color then return a.color end
    return a.area > b.area
  end)
  K.primaryMonitorName = mons[1] and mons[1].color and mons[1].name or nil
  -- The biggest advanced monitor runs Big Picture; the rest are panels.
  local first = true
  for _, x in ipairs(mons) do
    make(x.name, x.m, "monitor", (x.color and first) and "picture" or "panel", x.color)
    if x.color then first = false end
  end
  local monitorPicture = false
  for _, s in ipairs(list) do if s.kind == "monitor" and s.role == "picture" then monitorPicture = true end end
  home.role = K.device.pocket and "pocket" or (monitorPicture and "console" or "picture")
  local old = screens
  screens, screenByName = list, byName
  K.screens = list
  for _, s in ipairs(list) do
    if s.role ~= "off" then setupScreen(s) end
  end
  local dest = K.homeScreen()
  -- Prompts and apps on a screen that left Big Picture follow to the new one.
  for _, s in ipairs(old) do
    if s ~= dest and (byName[s.name] ~= s or not hosts(s)) and s.dialogs and #s.dialogs > 0 and s.role ~= "console" then
      dest.dialogs = dest.dialogs or {}
      for _, d in ipairs(s.dialogs) do d.screen = dest; dest.dialogs[#dest.dialogs + 1] = d end
      s.dialogs = {}
    end
  end
  for _, s in ipairs(old) do
    -- Big Picture carries on where it was: the same page or app in front.
    if s ~= dest and s.picture and (byName[s.name] ~= s or not hosts(s)) and dest.role == "picture" then
      local was, now = s.picture, dest.picture
      if not now or now.view == "home" then
        dest.picture = { view = was.view or "home", page = 1, path = was.path or "/", appPid = was.appPid, settingsPage = was.settingsPage }
      end
      s.picture = nil
    end
  end
  for _, w in ipairs(wins) do
    if byName[w.screen.name] ~= w.screen or not hosts(w.screen) then w.screen = dest end
    layout(w)
  end
  if markAll then markAll() end
end

------------------------------------------------------------------------
-- Windows
------------------------------------------------------------------------

-- Apps always fill their screen: below the title bar in Big Picture and
-- between the pocket launcher's top and bottom bars.
function layout(w)
  local s = w.screen
  w.state = "max"
  if s.role == "pocket" then
    w.x, w.y, w.w, w.h = 1, 1, s.w, max(3, s.h - 2)
  else
    w.x, w.y, w.w, w.h = 1, 1, max(12, s.w), max(3, s.h - 1)
  end
  local bw, bh = w.buf.getSize()
  if bw ~= w.w or bh ~= w.h then
    w.buf.reposition(1, 1, w.w, w.h)
    w.buf.changed = true
    post(w.proc, { "term_resize", n = 1 })
  end
  markDirty(s)
end
K.layout = layout

function newWindow(p, o)
  local s = o.screen or K.activeScreen()
  local w = { id = p.id, proc = p, screen = s, title = o.title or p.title, app = p.app, state = "max", opened = now() }
  w.w, w.h = s.w, s.h
  w.buf = makeBuffer(w.w, w.h)
  if o.background then table.insert(wins, 1, w) else wins[#wins + 1] = w end
  layout(w)
  if not o.background then K.focusWindow(w) end
  return w
end

function K.focusWindow(w)
  if not w then return end
  for i, x in ipairs(wins) do
    if x == w then table.remove(wins, i); break end
  end
  wins[#wins + 1] = w
  w.state = "max"
  K.focus = w
  local s = w.screen
  if s.role == "picture" and w.app then
    s.picture = s.picture or { view = "home", page = 1, path = "/" }
    s.picture.view, s.picture.appPid, s.picture.flyout = w.app.id, w.id, nil
  elseif s.role == "pocket" then
    s.pocketHome = false
  end
  -- The keyboard console shows what is in front, so it redraws too.
  markAll()
end

function removeWindow(w)
  for i, x in ipairs(wins) do
    if x == w then table.remove(wins, i); break end
  end
  if capture and capture.win == w then capture = nil end
  local s = w.screen
  if s.picture and s.picture.appPid == w.id then
    s.picture.appPid = nil
    if s.picture.view == (w.app and w.app.id) then s.picture.view = "home" end
  end
  if K.focus == w then
    K.focus = nil
    for i = #wins, 1, -1 do
      if wins[i].screen == s then K.focus = wins[i]; break end
    end
  end
  markAll()
end

function K.closeWindow(w)
  post(w.proc, { "terminate", n = 1 })
  killList[#killList + 1] = w.proc
  K.sfx("close")
end

-- Minimise leaves the app running and returns its screen to Start.
function K.minimize(w)
  local s = w.screen
  if s.picture and s.picture.appPid == w.id then
    s.picture.view, s.picture.appPid = "home", nil
  elseif s.role == "pocket" then
    s.pocketHome = true
  end
  markAll()
end

-- Keys go to the app in front: the one Big Picture shows full screen, or
-- the open pocket app.
function K.keyTarget()
  local ps = K.pictureScreen()
  if ps then return K.pictureApp(ps) end
  local s = screenByName.term
  if s.pocketHome then return end
  if K.focus and K.focus.screen == s and not K.focus.proc.dead then return K.focus end
end

------------------------------------------------------------------------
-- Notifications, dialogs and the palette state
------------------------------------------------------------------------

K.notifs, K.toasts, K.unread = {}, {}, 0
local audio

function K.sfx(name)
  if audio then audio.sfx(name) end
end

-- opts: icon, color, quiet (no sound), silent (no pop-up), time (ms), action
function K.notify(title, text, opts)
  opts = opts or {}
  local n = { title = tostring(title), text = text and tostring(text) or "", icon = opts.icon,
    color = opts.color or T.accent, t = now(), action = opts.action }
  table.insert(K.notifs, 1, n)
  if #K.notifs > 60 then table.remove(K.notifs) end
  K.unread = K.unread + 1
  if not opts.silent then
    table.insert(K.toasts, 1, { n = n, untilT = now() + (opts.time or 5000) })
    while #K.toasts > 3 do table.remove(K.toasts) end
  end
  if not opts.quiet then K.sfx("notify") end
  if markAll then markAll() end
  return n
end

local nextDialog = 1

-- A modal box on screen s. o: title, text, buttons, input (default text),
-- cb(index, text). Also queues ccos_dialog id index text.
function K.dialog(o)
  local s = o.screen or K.activeScreen()
  -- Prompts show where they were asked; a monitor's text field is typed on
  -- the computer's keyboard console.
  if s.role ~= "picture" and s.role ~= "pocket" and s.role ~= "console" then s = K.homeScreen() end
  local d = { id = nextDialog, title = o.title or "ccOS", text = o.text or "", buttons = o.buttons or { "OK" },
    cb = o.cb, screen = s, owner = not o.detached and running or nil, enterChoice=o.enterChoice }
  nextDialog = nextDialog + 1
  if o.input then d.field = { text = tostring(o.input == true and "" or o.input), secret = o.secret } end
  s.dialogs = s.dialogs or {}
  s.dialogs[#s.dialogs + 1] = d
  K.sfx("open")
  markAll()
  return d.id
end

local function answer(s, d, index)
  for i, x in ipairs(s.dialogs) do
    if x == d then table.remove(s.dialogs, i); break end
  end
  local text = d.field and d.field.text
  if d.cb then pcall(d.cb, index, text) end
  os.queueEvent("ccos_dialog", d.id, index, text)
  markAll()
end
K.answerDialog=answer

local function topDialog(s) return s.dialogs and s.dialogs[1] end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------

local B, CS   -- buffer and screen being drawn
local picture = loadModule(ROOT .. "/lib/picture.lua")(K, gfx, T)
local inputConsole=loadModule(ROOT.."/lib/input.lua")(K,T)
local pocketUI=loadModule(ROOT.."/lib/pocket.lua")(K,T)
K.pocketUI=pocketUI
local powerAnimation=loadModule(ROOT.."/lib/power.lua")(K,gfx,T)
K.panelPage, K.panelPinned, K.panelAt = 1, false, now()
local PANEL_PAGES = { "clock", "music", "notes", "system" }

local function put(x, y, s, fg, bg)
  B.setCursorPos(x, y)
  B.setTextColor(fg or T.text)
  B.setBackgroundColor(bg or T.bg)
  B.write(s)
end

local function fill(x, y, w, h, bg)
  if w <= 0 or h <= 0 then return end
  B.setBackgroundColor(bg)
  local line = (" "):rep(w)
  for yy = y, y + h - 1 do
    B.setCursorPos(x, yy)
    B.write(line)
  end
end

-- Dim a rectangle already drawn: the shadow under windows.
local function shade(x, y, w, h)
  for yy = y, y + h - 1 do
    if yy >= 1 and yy <= CS.h then
      local t, f, b = B.getLine(yy)
      local a, z = max(1, x), min(CS.w, x + w - 1)
      if a <= z then
        local n = z - a + 1
        f = f:sub(1, a - 1) .. ("7"):rep(n) .. f:sub(z + 1)
        b = b:sub(1, a - 1) .. ("f"):rep(n) .. b:sub(z + 1)
        B.setCursorPos(1, yy)
        B.blit(t, f, b)
      end
    end
  end
end

-- Touch target. extra: content = window, scroll = fn(dir), keep = bool.
local function hit(x1, y1, x2, y2, fn, extra)
  local h = extra or {}
  h.x1, h.y1, h.x2, h.y2, h.fn = x1, y1, x2, y2, fn
  CS.hits[#CS.hits + 1] = h
  return h
end

local function hitAt(s, x, y)
  for i = #s.hits, 1, -1 do
    local h = s.hits[i]
    if x >= h.x1 and x <= h.x2 and y >= h.y1 and y <= h.y2 then return h end
  end
end

local function button(x, y, label, fg, bg, fn)
  put(x, y, label, fg, bg)
  hit(x, y, x + #label - 1, y, fn)
  return x + #label
end

-- A box with a title strip; returns the content origin.
local function panelBox(x, y, w, h, title, accent)
  fill(x, y, w, h, T.surface)
  if title then
    fill(x, y, w, 1, T.raised)
    put(x + 1, y, trunc(title, w - 2), accent or T.text, T.raised)
  end
end

function markDirty(s)
  if not s then return end
  s.dirty = true
  if not K.renderTimer then K.renderTimer = os.startTimer(0.05) end
end

function markAll()
  for _, s in ipairs(screens) do markDirty(s) end
end
K.markAll, K.markDirty = markAll, markDirty

-- Something changed; when music starts, panels flip to it.
function K.changed(what)
  if what == "audio" and audio then
    local playing = audio.state == "playing" or audio.disc ~= nil
    if playing and not K.wasPlaying then
      for i, p in ipairs(PANEL_PAGES) do if p == "music" then K.panelPage = i end end
      K.panelAt = now()
    end
    K.wasPlaying = playing
  end
  markAll()
end

local function clockText(seconds) return clock.format(K.cfg, seconds) end
K.clockText = clockText

local function greeting()
  local h = tonumber(clock.date(K.cfg, "%H")) or 12
  if h < 5 then return "Good night" elseif h < 12 then return "Good morning"
  elseif h < 18 then return "Good afternoon" end
  return "Good evening"
end
K.greeting = greeting

local function gameClock()
  local t = os.time("ingame")
  local h = floor(t)
  local shown=K.cfg.clock24 and h or ((h+11)%12+1)
  local hour=K.cfg.leadingZero and ("%02d"):format(shown)or tostring(shown)
  return "Day "..os.day("ingame")..", "..hour..(":%02d"):format(floor((t-h)*60))..(K.cfg.clock24 and ""or(h<12 and " AM"or " PM"))
end
K.gameClock = gameClock

-- The splash while booting: the Start colour, a light "ccOS" and the
-- 8.1 progress ring, then a welcome for the user.
local function drawSplash(s)
  fill(1, 1, s.w, s.h, T.select)
  local frac = clamp((now() - K.bootStart) / 2200, 0, 1)
  local M = gfx.metro
  local big = s.w >= 60 and s.h >= 24
  local title = M.markCells(M.textRows("ccOS", big and 2 or 1), HEX[T.text], HEX[T.select], 0, 0)
  local ring, rw = powerAnimation.ring(s.w, s.h, floor((now() - K.bootStart) / 60), HEX[T.select], HEX[T.text], big and 8 or 5)
  local msg = frac < 0.7 and "Starting ccOS" or ("Welcome, " .. K.cfg.user)
  local tw = gfx.cellsWidth(title)
  local h = #title + 2 + #ring + 2
  local y = max(1, floor((s.h - h) / 2) + 1)
  if tw <= s.w and h <= s.h then
    gfx.drawCells(B, floor((s.w - tw) / 2) + 1, y, title)
    gfx.drawCells(B, floor((s.w - rw) / 2) + 1, y + #title + 2, ring)
    put(max(1, floor((s.w - #msg) / 2) + 1), min(s.h, y + h - 1), trunc(msg, s.w), T.text, T.select)
  else
    put(max(1, floor((s.w - 4) / 2) + 1), max(1, floor(s.h / 2)), "ccOS", T.text, T.select)
  end
  -- Keep the ring turning until boot finishes.
  markDirty(s)
end

function K.confirmPower(s, what)
  local words = { exit = "Exit to CraftOS", reboot = "Restart the computer", shutdown = "Shut down the computer" }
  K.dialog({ screen = s, title = words[what] .. "?", text = "Open apps will close and unsaved work is lost.", buttons = { "Cancel", words[what] },
    cb = function(i)
      if i == 2 then K.power = what; K.running = false end
    end })
end

-- Big Picture: a Windows 8.1 message band across the full width (drawn by
-- the picture module so dialogs and its own prompts look the same).
local function drawBand(s, d)
  local buttons = {}
  for i, label in ipairs(d.buttons) do buttons[i] = { label, function() answer(s, d, i) end } end
  picture.band(s, d.title or "", d.text or "", buttons, nil, { field = d.field, primary = d.choice or d.enterChoice or #d.buttons })
end

local function drawDialog(s, d)
  if s.role == "picture" and s.w >= 40 then return drawBand(s, d) end
  local w = min(s.w - (K.device.pocket and 2 or 4), 52)
  local total=0;for _,label in ipairs(d.buttons)do total=total+#label+3 end
  local stacked=total>w-2
  local extra=stacked and #d.buttons-1 or 0
  local lines=wrap(d.text,w-4)
  local maxLines=max(0,s.h-6-(d.field and 2 or 0)-extra)
  while #lines>maxLines do table.remove(lines)end
  local h = 3 + #lines + (d.field and 2 or 0) + 1+extra
  local x, y = floor((s.w - w) / 2) + 1, max(1, floor((s.h - h) / 2))
  hit(1, 1, s.w, s.h, function() end)
  shade(x + 1, y + h, w, 1)
  shade(x + w, y + 1, 1, h)
  fill(x, y, w, h, T.surface)
  fill(x, y, w, 1, T.raised)
  put(x + 2, y, trunc(d.title, w - 4), T.text, T.raised)
  for i, l in ipairs(lines) do put(x + 2, y + 1 + i, l, T.text, T.surface) end
  local yy = y + 2 + #lines
  if d.field then
    fill(x + 2, yy, w - 4, 1, T.bg)
    local shown = d.field.secret and ("*"):rep(#d.field.text) or d.field.text
    local room = w - 6
    if #shown > room then shown = shown:sub(-room) end
    put(x + 3, yy, shown, T.text, T.bg)
    if s.kind=="term"then s.cursor = { x = x + 3 + #shown, y = yy, color = T.accent }end
    yy = yy + 2
  end
  local bx=x+w-1
  for i=#d.buttons,1,-1 do
    local label=" "..d.buttons[i].." "
    local primary=i==(d.choice or d.enterChoice or #d.buttons)
    local by=stacked and(yy+i-1)or yy
    if stacked then bx=x+2;label=centre(label,w-4)else bx=bx-#label-1 end
    put(bx,by,label,primary and T.bg or T.text,primary and T.accent or T.raised)
    local index=i;hit(bx,by,bx+#label-1,by,function()answer(s,d,index)end)
  end
end

------------------------------------------------------------------------
-- The panel: a small monitor showing the time, music and devices
------------------------------------------------------------------------


local function bigClock(s, y, h)
  local t=clockText(false):gsub(" [AP]M$","")
  local scale = 1
  for k = 4, 1, -1 do
    local cells = gfx.pixelText(t, k, "0", "f")
    if gfx.cellsWidth(cells) <= s.w - 2 and #cells <= h then scale = k; break end
  end
  local cells = gfx.pixelText(t, scale, "0", "f")
  local cw = gfx.cellsWidth(cells)
  if #cells <= h and cw <= s.w then
    gfx.drawCells(B, floor((s.w - cw) / 2) + 1, y, cells)
    return #cells
  end
  put(floor((s.w - #t) / 2) + 1, y, t, T.text, T.bg)
  return 1
end

local function meter(x, y, w, v, color)
  local n = floor(clamp(v, 0, 1) * w + 0.5)
  B.setCursorPos(x, y)
  local col = HEX[color]
  B.blit(("\149"):rep(w), (col):rep(n) .. ("7"):rep(w - n), ("f"):rep(w))
end

local function drawPanel(s)
  fill(1, 1, s.w, s.h, T.bg)
  local info = audio.info()
  if info.state == "stopped" and not info.disc and PANEL_PAGES[K.panelPage] == "music" then K.panelPage = 1 end
  local page = PANEL_PAGES[K.panelPage]
  local small = s.h < 8
  if page == "clock" then
    if small then
      put(2, 1, clockText(true), T.text, T.bg)
      put(2, 2, clock.date(K.cfg, "%A %d %B"), T.muted, T.bg)
      put(2, 3, gameClock(), T.accent, T.bg)
    else
      local used = bigClock(s, 1, s.h - 4)
      local suffix=clockText(false):match(" ([AP]M)$")
      if suffix then put(floor((s.w-#suffix)/2)+1,used+1,suffix,T.accent,T.bg)end
      local date = clock.date(K.cfg, "%A %d %B")
      put(floor((s.w - #date) / 2) + 1, used + 2, date, T.muted, T.bg)
      local game = gameClock()
      put(floor((s.w - #game) / 2) + 1, used + 3, game, T.accent, T.bg)
    end
  elseif page == "music" then
    local name = info.disc and (info.discTitle or "Record") or (info.title or "")
    put(2, 1, "\14", T.accent2, T.bg)
    put(4, 1, trunc(name, s.w - 5), T.text, T.bg)
    if not small then
      local state = info.state == "playing" and "Playing" or (info.state == "paused" and "Paused" or "Record")
      put(4, 2, state .. (info.count > 1 and (" \183 " .. info.index .. "/" .. info.count) or ""), T.muted, T.bg)
    end
    local el = audio.elapsed()
    local len = info.len or 0
    local by = small and 2 or 4
    local tl = fmtTime(el) .. " / " .. fmtTime(len)
    local bw = s.w - #tl - 4
    if bw > 4 and not info.disc then
      fill(2, by, bw, 1, T.surface)
      fill(2, by, floor(bw * clamp(len > 0 and el / len or 0, 0, 1) + 0.5), 1, T.accent2)
      put(s.w - #tl, by, tl, T.muted, T.bg)
    end
    local l, r = audio.meter()
    if not small then
      put(2, by + 2, "L", T.muted, T.bg)
      meter(4, by + 2, s.w - 5, l, T.accent)
      put(2, by + 3, "R", T.muted, T.bg)
      meter(4, by + 3, s.w - 5, r, T.accent2)
    end
    local cy = small and 3 or s.h - 1
    local controls = { { " \17\17 ", audio.prev }, { info.state == "playing" and " || " or " \16 ", audio.toggle }, { " \16\16 ", audio.next } }
    local total = 0
    for _, c in ipairs(controls) do total = total + #c[1] + 1 end
    local cx = floor((s.w - total) / 2) + 1
    if cy <= s.h and not info.disc then
      for _, c in ipairs(controls) do cx = button(cx, cy, c[1], T.text, T.raised, c[2]) + 1 end
    end
  elseif page == "notes" then
    put(2, 1, "Notifications", T.accent, T.bg)
    local y = 2
    for i = 1, #K.notifs do
      if y > s.h - 1 then break end
      local n = K.notifs[i]
      local stamp=clock.format(K.cfg,false,floor(n.t/1000))
      local nx=2+#stamp+2
      put(2,y,stamp,T.muted,T.bg)
      put(nx,y,trunc(n.title..(n.text~=""and(" - "..n.text)or ""),s.w-nx),T.text,T.bg)
      y = y + 1
    end
    if #K.notifs == 0 then put(2, 2, "Nothing new", T.muted, T.bg) end
  else
    put(2, 1, "System", T.accent, T.bg)
    local rows = {}
    local d = (K.hw.drives or {})[1]
    rows[#rows + 1] = { "Disk", d and (d.present and (d.label or (d.audio and ("Record: " .. d.audio)) or "unlabelled") or "empty") or "no drive" }
    local pr = (K.hw.printers or {})[1]
    rows[#rows + 1] = { "Printer", pr and (("%d paper, %d ink"):format(pr.paper or 0, pr.ink or 0)) or "none" }
    rows[#rows + 1] = { "Speakers", info.speakers >= 2 and "stereo" or (info.speakers == 1 and "mono" or "none") }
    rows[#rows + 1] = { "Windows", tostring(#wins) }
    rows[#rows + 1] = { "Up", fmtDur(os.clock()) }
    for i, r in ipairs(rows) do
      if i + 1 > s.h - 1 then break end
      put(2, i + 1, padR(r[1], 10), T.muted, T.bg)
      put(12, i + 1, trunc(r[2], s.w - 13), T.text, T.bg)
    end
  end
  -- page dots; tap left or right half to flip
  local dots = ""
  for i = 1, #PANEL_PAGES do dots = dots .. (i == K.panelPage and "\7" or "\183") end
  put(s.w - #dots, s.h, dots, K.panelPinned and T.accent or T.muted, T.bg)
  for _, tt in ipairs(K.toasts) do
    fill(1, s.h, s.w - #dots - 1, 1, T.surface)
    put(2, s.h, trunc(tt.n.title .. ": " .. tt.n.text, s.w - #dots - 3), T.text, T.surface)
    break
  end
  hit(1, 1, floor(s.w / 3), s.h, function() K.panelPage = (K.panelPage - 2) % #PANEL_PAGES + 1; K.panelAt = now() end)
  hit(floor(s.w / 3) + 1, 1, s.w - floor(s.w / 3), s.h, function() K.panelPinned = not K.panelPinned end)
  hit(s.w - floor(s.w / 3) + 1, 1, s.w, s.h, function() K.panelPage = K.panelPage % #PANEL_PAGES + 1; K.panelAt = now() end)
  -- the music controls sit on top of the page-flip areas
  if page == "music" and not info.disc then
    local cy = small and 3 or s.h - 1
    local controls = { audio.prev, audio.toggle, audio.next }
    local labels = { " \17\17 ", info.state == "playing" and " || " or " \16 ", " \16\16 " }
    local total = 0
    for _, l in ipairs(labels) do total = total + #l + 1 end
    local cx = floor((s.w - total) / 2) + 1
    for i, l in ipairs(labels) do
      hit(cx, cy, cx + #l - 1, cy, controls[i])
      cx = cx + #l + 1
    end
  end
end

local function drawSaver(s)
  fill(1, 1, s.w, s.h, T.bg)
  local r = gfx.rng(floor(now() / 1000))
  for _ = 1, floor(s.w * s.h / 60) do
    put(r(s.w) + 1, r(s.h) + 1, r(3) == 0 and "\7" or "\183", r(4) == 0 and T.accent or T.muted, T.bg)
  end
  local t = clockText(false)
  local cells
  for k = 6, 1, -1 do
    cells = gfx.pixelText(t, k, { "9", "9", "a", "a", "6" }, "f")
    if gfx.cellsWidth(cells) <= s.w * 0.7 and #cells <= s.h * 0.5 then break end
  end
  local cw = gfx.cellsWidth(cells)
  local minute = floor(now() / 60000)
  local dx = (minute * 7) % max(1, s.w - cw - 2)
  local dy = (minute * 3) % max(1, s.h - #cells - 4)
  gfx.drawCells(B, 2 + dx, 2 + dy, cells)
  local date = clock.date(K.cfg, "%A %d %B")
  put(2 + dx + floor((cw - #date) / 2), 3 + dy + #cells, date, T.muted, T.bg)
  hit(1, 1, s.w, s.h, function() end)
end

local function compose(s)
  B, CS = s.buf, s
  s.hits = {}
  s.cursor = nil
  if K.booting then
    drawSplash(s)
  elseif s.role == "panel" then
    drawPanel(s)
  elseif K.saver then
    drawSaver(s)
  elseif s.role == "console" then
    inputConsole.draw(s, K.pictureScreen())
    local d = topDialog(s); if d and not d.field then drawDialog(s, d) end
  elseif s.role == "pocket" then
    pocketUI.draw(s)
    local d = topDialog(s); if d then drawDialog(s, d) end
  elseif s.role == "picture" then
    picture.draw(s)
    local d = topDialog(s)
    if d then drawDialog(s, d) else picture.toasts(s) end
  end
  -- Copy changed lines to the screen.
  local tgt, cache = s.target, s.cache
  for y = 1, s.h do
    local t, f, b = B.getLine(y)
    local c = cache[y]
    if not c or c[1] ~= t or c[2] ~= f or c[3] ~= b then
      tgt.setCursorPos(1, y)
      tgt.blit(t, f, b)
      cache[y] = { t, f, b }
    end
  end
  local cur = s.cursor
  if not cur and not K.booting and not K.saver and not topDialog(s) then
    -- The blinking cursor of the app in front, where it is drawn.
    local w
    if s.role == "picture" then w = K.pictureApp(s)
    elseif s.role == "pocket" and not s.pocketHome then w = K.focus end
    if w and w.screen == s and w.buf.getCursorBlink and w.buf.getCursorBlink() then
      local cx, cy = w.buf.getCursorPos()
      if cx >= 1 and cx <= w.w and cy >= 1 and cy <= w.h then
        cur = { x = w.x + cx - 1, y = w.y + cy, color = w.buf.getTextColor() }
      end
    end
  end
  s.lastCursor = cur
  if cur then
    tgt.setCursorPos(cur.x, cur.y)
    tgt.setTextColor(cur.color)
    tgt.setCursorBlink(true)
  else
    tgt.setCursorBlink(false)
  end
end

local function render()
  for _, s in ipairs(screens) do
    if s.dirty and s.role ~= "off" then
      s.dirty = false
      local ok, err = pcall(compose, s)
      if not ok then
        -- Usually a monitor removed mid-frame; peripheral events rebuild.
        logCrash({ title = "render " .. s.name }, err)
      end
    end
  end
end

------------------------------------------------------------------------
-- Input
------------------------------------------------------------------------

local function wakeSaver()
  K.lastInput = now()
  if K.saver then
    K.saver = false
    markAll()
    return true
  end
end

local function pointer(s, kind, btn, x, y)
  K.lastScreen = s
  if wakeSaver() or K.booting then return end
  if kind == "drag" or kind == "up" then
    if capture then
      local w = capture.win
      post(w.proc, { kind == "drag" and "mouse_drag" or "mouse_up", btn, x - w.x + 1, y - w.y, n = 4 })
      if kind == "up" then capture = nil end
    end
    return
  end
  local h = hitAt(s, x, y)
  if kind == "scroll" then
    if not (h and h.content) then
      for i = #s.hits, 1, -1 do
        local r = s.hits[i]
        if r.scroll and x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then h = r; break end
      end
    end
    if h and h.content then
      local w = h.content
      post(w.proc, { "mouse_scroll", btn, x - w.x + 1, y - w.y, n = 4 })
    elseif h and h.scroll then
      h.scroll(btn)
    end
    markDirty(s)
    return
  end
  K.lastTouch = kind == "touch"
  if kind == "touch" and K.cfg.touchSounds then K.sfx("click") end
  if not h then return end
  if h.content then
    local w = h.content
    if K.focus ~= w then K.focusWindow(w) end
    local rx, ry = x - w.x + 1, y - w.y
    post(w.proc, { "mouse_click", btn, rx, ry, n = 4 })
    if kind == "touch" then
      post(w.proc, { "mouse_up", btn, rx, ry, n = 4 })
    else
      capture = { win = w }
    end
  elseif h.fn then
    h.fn(x, y, btn, kind)
  end
  markDirty(s)
end

local held = {}

local function dialogInput(s, d, ev)
  local e = ev[1]
  if e == "char" or e == "paste" then
    d.field.text = (d.field.text .. ev[2]):sub(1, d.field.secret and 1024 or 12000)
  elseif e == "key" then
    if ev[2] == keys.backspace then d.field.text = d.field.text:sub(1, -2)
    elseif ev[2] == keys.enter then answer(s, d, #d.buttons)
    elseif ev[2] == keys.escape then answer(s, d, 1) end
  end
  markAll()
end

-- The computer keyboard. Prompts come first wherever they are shown, then
-- Big Picture: F2 returns to Start, the app in front gets every key, and
-- on Start typing searches. A monitor's agent chat is typed on the console.
local function keyboard(ev)
  local e = ev[1]
  if e == "key" then held[ev[2]] = true elseif e == "key_up" then held[ev[2]] = nil end
  if e ~= "key_up" and wakeSaver() then return end
  if K.booting then return end
  local alt = held[keys.leftAlt] or held[keys.rightAlt]
  if e == "key" and ((alt and ev[2] == keys.a) or ev[2] == keys.f1) then
    K.launch("agent", {}, { screen = K.homeScreen() }); return
  end
  for _, s in ipairs(screens) do
    local d = topDialog(s)
    if d and e ~= "key_up" then
      if d.field then dialogInput(s, d, ev)
      elseif e == "key" then
        local n = #d.buttons
        local cur = d.choice or d.enterChoice or n
        if ev[2] == keys.left or ev[2] == keys.up or ev[2] == keys.tab and held[keys.leftShift] then d.choice = (cur - 2) % n + 1; markAll()
        elseif ev[2] == keys.right or ev[2] == keys.down or ev[2] == keys.tab then d.choice = cur % n + 1; markAll()
        elseif ev[2] == keys.enter or ev[2] == keys.numPadEnter then answer(s, d, cur)
        elseif ev[2] == keys.escape then answer(s, d, 1) end
      end
      return
    end
  end
  local ps = K.pictureScreen()
  if ps then
    if e == "key" and ev[2] == keys.f2 then picture.home(ps); return end
    local v = ps.picture or {}
    if ps.kind == "monitor" and v.view == "agent" and inputConsole.keyboard(ev, ps) then return end
    local app = K.pictureApp(ps)
    if app then post(app.proc, ev); return end
    if e ~= "key_up" then picture.keyboard(ps, ev) end
    return
  end
  if e == "key" and ev[2] == keys.f2 then pocketUI.home(); return end
  if e == "key" and K.agent.pending then
    if ev[2] == keys.f3 then K.agent.approve(true); return elseif ev[2] == keys.f4 then K.agent.approve(false); return end
  end
  if pocketUI.keyboard(ev) then return end
  local target = K.keyTarget()
  if target then post(target.proc, ev) end
end

------------------------------------------------------------------------
-- Launching
------------------------------------------------------------------------

local API = {}
K.api = API
local ui

local function makeEnv(dir)
  local env = setmetatable({ shell = rootShell, ccos = API, aurora = API }, { __index = _G })
  if K.require then
    local ok, r = pcall(K.require, "cc.require")
    if ok and r then env.require, env.package = r.make(env, dir or "/") end
  end
  return env
end
K.makeEnv = makeEnv

local function waitToClose(ok)
  local old = term.getTextColor()
  term.setTextColor(colors.lightGray)
  print()
  print((ok and "Finished." or "Stopped with an error.") .. " Press a key or tap to close.")
  term.setTextColor(old)
  while true do
    local e = os.pullEvent()
    if e == "key" or e == "mouse_click" then return end
  end
end

local function programFn(path, args, keep)
  return function()
    local env = makeEnv(fs.getDir(path))
    local ok = os.run(env, path, table.unpack(args or {}))
    if keep or not ok then waitToClose(ok) end
  end
end

local function appFn(app, args)
  return function()
    local env = makeEnv(ROOT .. "/apps")
    local fn, err = loadfile(ROOT .. "/apps/" .. app.path .. ".lua", nil, env)
    if not fn then error(err, 0) end
    local actual = {}
    if app.tool then actual[#actual+1] = app.tool end
    for _, a in ipairs(args or {}) do actual[#actual+1] = a end
    fn(table.unpack(actual))
  end
end

function K.launch(id, args, opts)
  local app = appById(id)
  if not app then return nil, "No app called " .. tostring(id) end
  opts = opts or {}
  args = args or {}
  local s = opts.screen or K.activeScreen()
  if not hosts(s) then s = K.homeScreen() end
  if s.role == "pocket" and id == "settings" then pocketUI.home("settings"); return { id = 0, virtual = true } end
  if s.role == "picture" then
    s.picture = s.picture or { view = "home", page = 1, path = "/" }
    local v = s.picture
    if ({ files = true, music = true, settings = true, notifications = true, devices = true })[id] then
      v.view, v.page, v.appPid, v.flyout = id, 1, nil, nil
      if id == "files" and args[1] then v.path = args[1] end
      markAll(); return { id = 0, virtual = true }
    end
    if not K.canTouchApp(app, s) then return nil, app.name .. " needs a bigger screen" end
    -- Apps are single instance: opening one again brings it back.
    if #args == 0 and not opts.new then
      for _, w in ipairs(wins) do
        if w.app and w.app.id == id and w.screen == s and not w.proc.dead then K.focusWindow(w); return w.proc end
      end
    end
  end
  local fn
  if app.shell then
    fn = programFn("/rom/programs/shell.lua", {}, false)
  elseif app.program then
    if app.needsFile and #args == 0 then
      fn = function()
        local name = API.prompt("Open with " .. app.name, "Which file?", "")
        if name and name ~= "" then programFn(app.program, { name }, false)() end
      end
    else
      fn = programFn(app.program, args, false)
    end
  else
    fn = appFn(app, args)
  end
  local title = opts.title or (app.needsFile and args[1] and (app.name .. ": " .. fs.getName(args[1]))) or app.name
  local p = K.spawn(fn, { title = title, app = app, window = { screen = s, w = app.w, h = app.h } })
  K.sfx("open")
  return p
end

-- A shell command in a terminal that stays open afterwards. Commands the
-- agent runs open in the background; Terminal on Start brings them up.
function K.runCommand(line, s, background)
  local app = appById("terminal")
  s = s or K.activeScreen()
  if not hosts(s) then s = K.homeScreen() end
  return K.spawn(function()
    local ok = rootShell.run(line)
    waitToClose(ok)
  end, { title = trunc(line, 30), app = app, window = { screen = s, w = app.w, h = app.h, background = background } })
end

function K.addRecent(path)
  local list = K.cfg.recent
  for i = #list, 1, -1 do if list[i] == path then table.remove(list, i) end end
  table.insert(list, 1, path)
  while #list > 12 do table.remove(list) end
  K.saveConfig()
end

local AUDIO_EXT = { dfpwm = true, wav = true }

function K.openFile(path, s)
  if fs.isDir(path) then return K.launch("files", { path }, { screen = s }) end
  K.addRecent(path)
  local ext = (path:match("%.(%w+)$") or ""):lower()
  if AUDIO_EXT[ext] then
    audio.play(path)
    return
  end
  if ext == "nfp" then return K.launch("paint", { path }, { screen = s }) end
  return K.launch("viewer", { path }, { screen = s })
end

------------------------------------------------------------------------
-- Commands, for the shell (in /ccos/bin) and the agent
------------------------------------------------------------------------

local COMMANDS, CMD_ORDER = {}, {}

local function command(name, usage, desc, fn)
  COMMANDS[name] = { name = name, usage = usage, desc = desc, fn = fn }
  CMD_ORDER[#CMD_ORDER + 1] = name
end

local function tokenize(line)
  local words = {}
  local i = 1
  while i <= #line do
    local c = line:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif c == '"' then
      local j = line:find('"', i + 1, true) or (#line + 1)
      words[#words + 1] = line:sub(i + 1, j - 1)
      i = j + 1
    else
      local j = line:find("%s", i) or (#line + 1)
      words[#words + 1] = line:sub(i, j - 1)
      i = j
    end
  end
  return words
end

local function resolve(p)
  if p:sub(1, 1) == "/" then return p end
  return "/" .. fs.combine(rootShell.dir(), p)
end

local function audioFiles(dir, out, depth)
  out = out or {}
  for _, name in ipairs(fs.list(dir)) do
    local p = fs.combine(dir, name)
    if fs.isDir(p) then
      if (depth or 0) < 2 and p ~= "rom" then audioFiles(p, out, (depth or 0) + 1) end
    elseif name:match("%.dfpwm$") and not name:match("%.r%.dfpwm$") or name:match("%.wav$") then
      out[#out + 1] = audio.item("/" .. p)
    end
  end
  return out
end
K.audioFiles = audioFiles

-- Run an ccOS command line; out(text, colour). Returns false when the
-- first word isn't a command.
function K.exec(line, out, s)
  local words = tokenize(line)
  local c = COMMANDS[words[1] or ""]
  if not c then return false end
  table.remove(words, 1)
  c.fn(words, out or function() end, s)
  return true
end

command("help", "help [command]", "List commands, or explain one", function(a, out)
  local c = a[1] and COMMANDS[a[1]]
  if c then out(c.usage, T.accent); out(c.desc); return end
  for _, n in ipairs(CMD_ORDER) do out(padR(n, 14) .. COMMANDS[n].desc) end
end)
command("apps", "apps", "List the apps", function(_, out)
  for _, app in ipairs(APPS) do
    if not app.hidden then out(padR(app.id, 10) .. app.name .. (app.desc and (" - " .. app.desc) or "")) end
  end
end)
command("open", "open <app|path> [args]", "Open an app, a folder or a file", function(a, out, s)
  local target = a[1]
  if not target then error("Usage: open <app|path>", 0) end
  if appById(target) then
    K.launch(target, { table.unpack(a, 2) }, { screen = s })
    out("Opened " .. appById(target).name, T.ok)
    return
  end
  local path = resolve(target)
  if not fs.exists(path) then error("No app or file called " .. target, 0) end
  K.openFile(path, s)
  out("Opened " .. path, T.ok)
end)
command("run", "run <command>", "Run a shell command in a new terminal window", function(a, out, s)
  if #a == 0 then error("Usage: run <command>", 0) end
  K.runCommand(table.concat(a, " "), s)
  out("Started " .. a[1], T.ok)
end)
command("ps", "ps", "List windows and background tasks", function(_, out)
  out(padR("ID", 5) .. padR("Name", 22) .. padR("Screen", 12) .. "CPU ms", T.muted)
  for _, p in ipairs(procs) do
    if not p.dead then
      out(padR(tostring(p.id), 5) .. padR(p.title, 22) .. padR(p.win and p.win.screen.name or "-", 12) .. floor(p.cpu))
    end
  end
end)
command("kill", "kill <id>", "Stop a window or task", function(a, out)
  local id = tonumber(a[1] or "")
  for _, p in ipairs(procs) do
    if p.id == id then K.kill(p); out("Stopped " .. p.title, T.ok); return end
  end
  error("No task " .. tostring(a[1]), 0)
end)
command("focus", "focus <id>", "Bring a window to the front", function(a)
  local id = tonumber(a[1] or "")
  for _, w in ipairs(wins) do if w.id == id then K.focusWindow(w); return end end
  error("No window " .. tostring(a[1]), 0)
end)
command("notify", "notify <title> [message]", "Show a notification", function(a, out)
  if #a == 0 then error("Usage: notify <title> [message]", 0) end
  K.notify(a[1], table.concat(a, " ", 2))
  out("Sent", T.ok)
end)
command("notifications", "notifications [clear]", "List or clear notifications", function(a, out)
  if a[1] == "clear" then K.notifs, K.toasts, K.unread = {}, {}, 0; markAll(); out("Cleared", T.ok); return end
  for i = 1, min(15, #K.notifs) do
    local n = K.notifs[i]
    out(clock.format(K.cfg, false, floor(n.t / 1000)) .. " " .. n.title .. (n.text ~= "" and (": " .. n.text) or ""))
  end
  if #K.notifs == 0 then out("Nothing new", T.muted) end
end)
command("play", "play [file|folder|url]", "Play music, or resume", function(a, out)
  if not a[1] then audio.resume(); out("Playing", T.ok); return end
  local target = table.concat(a, " ")
  if target:match("^https?://") then audio.play({ audio.item(target) }); out("Streaming " .. target, T.ok); return end
  local path = resolve(target)
  if fs.isDir(path) then
    local list = audioFiles(path)
    if #list == 0 then error("No music in " .. path, 0) end
    audio.play(list, 1)
    out(("Playing %d tracks from %s"):format(#list, path), T.ok)
  elseif fs.exists(path) then
    audio.play(path)
    out("Playing " .. path, T.ok)
  else
    error("Nothing at " .. path, 0)
  end
end)
command("pause", "pause", "Pause the music", function(_, out) audio.pause(); out("Paused") end)
command("stop", "stop", "Stop the music", function(_, out) audio.stop(); out("Stopped") end)
command("next", "next", "Skip to the next track", function(_, out) audio.next(); out("Next") end)
command("prev", "prev", "Back to the previous track", function(_, out) audio.prev(); out("Previous") end)
command("np", "np", "Show what's playing", function(_, out)
  local i = audio.info()
  if i.disc then out("Record: " .. (i.discTitle or "?"), T.accent2) end
  if i.state == "stopped" then out("Nothing playing", T.muted); return end
  out(i.title or "?", T.accent2)
  out(("%s  %s / %s  track %d of %d"):format(i.state, fmtTime(audio.elapsed()), fmtTime(i.len), i.index, i.count))
end)
command("vol", "vol [0-100]", "Show or set the music volume", function(a, out)
  if a[1] then audio.setVolume((tonumber(a[1]) or 0) / 100) end
  out("Volume " .. floor(K.cfg.musicVolume * 100 + 0.5) .. "%")
end)
command("balance", "balance [-100..100]", "Show or set the left/right balance", function(a, out)
  if a[1] then audio.setBalance((tonumber(a[1]) or 0) / 100) end
  out("Balance " .. floor(K.cfg.balance * 100 + 0.5) .. " (negative is left)")
end)
command("shuffle", "shuffle [on|off]", "Shuffle the queue", function(a, out)
  if a[1] then audio.shuffle = a[1] == "on" else audio.shuffle = not audio.shuffle end
  out("Shuffle " .. (audio.shuffle and "on" or "off"))
end)
command("loop", "loop [off|all|one]", "Repeat the queue or one track", function(a, out)
  if a[1] == "off" or a[1] == "all" or a[1] == "one" then audio.loop = a[1] end
  out("Loop " .. audio.loop)
end)
command("queue", "queue [add <path>]", "Show the queue or add to it", function(a, out)
  if a[1] == "add" and a[2] then audio.enqueue(resolve(table.concat(a, " ", 2))); out("Added", T.ok); return end
  for i, it in ipairs(audio.queue) do out((i == audio.index and "\16 " or "  ") .. i .. ". " .. it.title) end
  if #audio.queue == 0 then out("The queue is empty", T.muted) end
end)
command("disc", "disc [play|stop]", "Play or stop a music disc in the drive", function(a, out)
  if a[1] == "stop" then audio.stopDisc(); out("Stopped"); return end
  for _, d in ipairs(K.hw.drives or {}) do
    if d.audio then audio.playDisc(d.name); out("Playing " .. d.audio, T.ok); return end
  end
  error("No music disc in a drive", 0)
end)
command("eject", "eject [drive]", "Eject the disk", function(a, out)
  local name = a[1]
  if not name then
    for _, d in ipairs(K.hw.drives or {}) do if d.present then name = d.name; break end end
  end
  if not name then error("No disk to eject", 0) end
  peripheral.call(name, "ejectDisk")
  out("Ejected " .. name, T.ok)
end)
command("label", "label [text]", "Show or set the disk's label", function(a, out)
  local d
  for _, x in ipairs(K.hw.drives or {}) do if x.present then d = x; break end end
  if not d then error("No disk in a drive", 0) end
  if #a > 0 then
    peripheral.call(d.name, "setDiskLabel", table.concat(a, " "))
    os.queueEvent("ccos_hw")
    out("Labelled", T.ok)
  else
    out(d.label or "(no label)")
  end
end)
command("lp", "lp <file>", "Print a text file", function(a, out)
  if not a[1] then error("Usage: lp <file>", 0) end
  local path = resolve(a[1])
  local h = fs.open(path, "r")
  if not h then error("Can't read " .. path, 0) end
  local text = h.readAll()
  h.close()
  local ok, err = API.printText(fs.getName(path), text)
  if not ok then error(err, 0) end
  out("Printed " .. err .. " page(s)", T.ok)
end)
command("banner", "banner <text>", "Print big letters, one per page", function(a, out)
  if #a == 0 then error("Usage: banner <text>", 0) end
  local ok, err = API.printBanner(table.concat(a, " "))
  if not ok then error(err, 0) end
  out("Printed " .. err .. " page(s)", T.ok)
end)
local function colourIds(list)
  local ids = {}
  for _, c in ipairs(list) do ids[#ids + 1] = c.id end
  return table.concat(ids, ", ")
end
command("colour", "colour [start|accent] [name]", "Show or change the Start and accent colours", function(a, out)
  local which = a[1]
  if which and which ~= "start" and which ~= "accent" then error("Usage: colour [start|accent] [name]", 0) end
  if which and a[2] then
    local ok, why = K.validateSetting(which .. "Color", a[2])
    if not ok then error(why .. ". Choose: " .. colourIds(which == "start" and START_COLORS or ACCENT_COLORS), 0) end
    API.config(which .. "Color", a[2])
  end
  out("Start " .. K.cfg.startColor .. " (" .. colourIds(START_COLORS) .. ")")
  out("Accent " .. K.cfg.accentColor .. " (" .. colourIds(ACCENT_COLORS) .. ")")
end)
command("screens", "screens", "List the displays", function(_, out)
  for _, s in ipairs(screens) do
    local scale = s.kind == "monitor" and s.target.getTextScale and (" scale " .. s.target.getTextScale()) or ""
    out(padR(s.name, 12) .. padR(s.role, 9) .. (s.w or 0) .. "x" .. (s.h or 0) .. scale)
  end
end)
command("screen", "screen <name> <picture|panel|off> [scale]", "Set what a monitor shows", function(a, out)
  local name, role = a[1], a[2]
  if not name or not (role == "picture" or role == "panel" or role == "off") then
    error("Usage: screen <name> <picture|panel|off> [scale]", 0)
  end
  if name == "term" then error("The computer runs Big Picture or its monitor's keyboard console", 0) end
  local conf = K.cfg.screens[name] or {}
  conf.role = role
  if a[3] then conf.scale = a[3] == "auto" and "auto" or tonumber(a[3]) end
  K.cfg.screens[name] = conf
  K.saveConfig()
  K.buildScreens()
  out(name .. " is now a " .. role, T.ok)
end)
command("sound", "sound [on|off]", "System sounds on or off", function(a, out)
  if a[1] then K.cfg.sounds = a[1] == "on" else K.cfg.sounds = not K.cfg.sounds end
  K.saveConfig()
  out("System sounds " .. (K.cfg.sounds and "on" or "off"))
end)
command("chime", "chime [left|right|both]", "Play a test sound", function(a, out)
  local side = a[1] or "both"
  if side == "left" then audio.note("bell", 12, -1, 1.5)
  elseif side == "right" then audio.note("bell", 12, 1, 1.5)
  else audio.sfx("notify") end
  local i = audio.info()
  out(i.speakers >= 2 and ("Left: " .. tostring(audio.spk.l) .. ", right: " .. tostring(audio.spk.r)) or
    (i.speakers == 1 and "One speaker: mono" or "No speakers attached"))
end)
command("sysinfo", "sysinfo", "Describe this computer", function(_, out)
  local info = API.sysinfo()
  for _, row in ipairs(info) do out(padR(row[1], 14) .. row[2]) end
end)
command("time", "time", "Real and in-game time", function(_, out)
  out(clock.date(K.cfg, "%A %d %B %Y, ") .. clockText(true))
  out(gameClock() .. " in game")
end)
command("ai", "ai [task]", "Open the ccOS agent or give it a task", function(a,out)
  K.launch("agent", nil, {screen=screenByName.term})
  if #a>0 then local ok,err=K.agent.start(table.concat(a," "),"terminal"); if not ok then out(err,T.warn)end end
end)
command("update","update [check]","Check for or install ccOS updates",function(a,out)
  local ok,why;if a[1]=="check"then ok,why=K.updates.check(true)else ok,why=K.updates.install()end
  if not ok then out(why,T.warn)end
end)
command("timezone", "timezone <zone|fixed> [minutes]", "Set the system time zone", function(a,out)
  if not a[1]then out(clock.label(K.cfg));return end
  assert(clock.valid(a[1]),"Unsupported time zone")
  if a[1]=="fixed"then local n=assert(tonumber(a[2]),"Give a UTC offset in minutes");assert(n>=-720 and n<=840,"Offset out of range");K.api.config("utcOffset",n)end
  K.api.config("timezone",a[1]);out(clock.label(K.cfg))
end)
command("exit", "exit", "Leave ccOS for CraftOS", function() K.power = "exit"; K.running = false end)
command("reboot", "reboot", "Restart the computer", function() K.power = "reboot"; K.running = false end)
command("shutdown", "shutdown", "Turn the computer off", function() K.power = "shutdown"; K.running = false end)

-- Shell programs for each command, so `play song.dfpwm` works in a terminal.
local function writeBin()
  local dir = ROOT .. "/bin"
  if not fs.exists(dir) then fs.makeDir(dir) end
  local function stub(name, body)
    local path = dir .. "/" .. name .. ".lua"
    local h = fs.open(path, "w")
    if h then h.write(body); h.close() end
  end
  -- Commands from older versions (the retired desktop) no longer exist.
  for _, old in ipairs({ "theme", "wallpaper" }) do
    if not COMMANDS[old] and fs.exists(dir .. "/" .. old .. ".lua") then fs.delete(dir .. "/" .. old .. ".lua") end
  end
  for _, n in ipairs(CMD_ORDER) do
    stub(n, ("-- ccOS command; see `help %s`.\nif not ccos then printError(\"ccOS isn't running.\") return end\nccos.cli(%q, ...)\n"):format(n, n))
  end
  stub("ccos", "-- ccos <command> [args]: run any ccOS command.\nif not ccos then printError(\"ccOS isn't running.\") return end\nccos.cli(...)\n")
  local path = rootShell.path()
  if not path:find(dir, 1, true) then rootShell.setPath(path .. ":" .. dir) end
  local complete = K.require and pcall(K.require, "cc.shell.completion") and K.require("cc.shell.completion")
  if complete then
    local appNames = {}
    for _, a in ipairs(APPS) do if not a.hidden then appNames[#appNames + 1] = a.id end end
    rootShell.setCompletionFunction("ccos/bin/open.lua", complete.build({ complete.choice, appNames, true }))
    rootShell.setCompletionFunction("ccos/bin/colour.lua", complete.build({ complete.choice, { "start", "accent" } }))
    rootShell.setCompletionFunction("ccos/bin/play.lua", complete.build(complete.file))
    rootShell.setCompletionFunction("ccos/bin/lp.lua", complete.build(complete.file))
    rootShell.setCompletionFunction("ccos/bin/help.lua", complete.build({ complete.choice, CMD_ORDER }))
  end
end

------------------------------------------------------------------------
-- The API for apps (also _G.ccos while ccOS runs)
------------------------------------------------------------------------

API.version = VERSION
API.gfx = gfx
API.json = json
API.catalog = catalog
API.time = clock
function API.gameClock() return gameClock() end
function API.clock(seconds, at) return clock.format(K.cfg, seconds, at) end
function API.date(fmt, at) return clock.date(K.cfg, fmt, at) end
function API.timezoneLabel() return clock.label(K.cfg) end

local function callerWindow() return running and running.win end
local function callerScreen()
  local w = callerWindow()
  return w and w.screen or K.activeScreen()
end

function API.theme() return T end
function API.device()return copy(K.device)end
function API.isPocket()return K.device.pocket end
-- Whether the last tap or click came from a monitor.
function API.touchInput() return K.lastTouch == true end
function API.pictureScreenName()local s=K.pictureScreen();return s and s.name end
-- Read or set the Big Picture view (home, apps, music, files, settings, ...).
function API.pictureView(view)
  local s=K.pictureScreen();if not s then return nil end
  s.picture=s.picture or {view="home",page=1,path="/"}
  if view~=nil then
    if type(view)~="string"then error("Expected a view name",2)end
    s.picture.view,s.picture.page,s.picture.flyout,s.picture.appPid=view,1,nil,nil;markAll()
  end
  return s.picture.view
end
function API.isTouch()
  local s = callerScreen()
  return s and s.touch or false
end
function API.screenName() return callerScreen().name end
function API.setTitle(title)
  local w = callerWindow()
  if w then w.title = tostring(title); markDirty(w.screen) end
end
function API.notify(title, text, opts) return K.notify(title, text, opts) end
function API.notifications() return K.notifs end
function API.markNotificationsRead() K.unread=0;markAll() end
function API.launch(id, args, screenName)
  local target
  if screenName then for _,s in ipairs(screens)do if s.name==screenName then target=s end end;assert(target,"Unknown screen")end
  return K.launch(id,args or {},{screen=target or callerScreen()})
end
function API.open(target, ...)
  local s = callerScreen()
  if appById(target) then return K.launch(target, { ... }, { screen = s }) end
  return K.openFile(target, s)
end
function API.openFile(path) return K.openFile(path, callerScreen()) end
function API.runFile(path, ...)
  local app = appById("terminal")
  return K.spawn(programFn(path, { ... }, true), { title = fs.getName(path), app = app,
    window = { screen = callerScreen(), w = app.w, h = app.h } })
end
function API.run(line) return K.runCommand(line, callerScreen()) end
function API.exec(line, out) return K.exec(line, out, callerScreen()) end
function API.cli(name, ...)
  local args = { ... }
  local line = name
  for _, a in ipairs(args) do line = line .. " " .. (a:find("%s") and ('"' .. a .. '"') or a) end
  local function out(text, color)
    if term.isColor() and color then term.setTextColor(color) end
    print(text)
    term.setTextColor(colors.white)
  end
  local ok, err = pcall(K.exec, line, out, callerScreen())
  if not ok then printError(err)
  elseif err == false then printError("Unknown command: " .. tostring(name) .. ". Try `help`.") end
end
function API.commands()
  local list = {}
  for _, n in ipairs(CMD_ORDER) do list[#list + 1] = COMMANDS[n] end
  return list
end
function API.apps()
  local list = {}
  for _, a in ipairs(APPS) do list[#list + 1] = a end
  return list
end
function API.windows()
  local list = {}
  for _, w in ipairs(wins) do
    list[#list + 1] = { id = w.id, title = w.title, app = w.app and w.app.id, screen = w.screen.name, state = w.state,
      focused = K.focus == w, cpu = w.proc.cpu, started = w.proc.started }
  end
  return list
end
function API.tasks()
  local list = {}
  for _, p in ipairs(procs) do
    if not p.dead then
      list[#list + 1] = { id = p.id, title = p.title, window = p.win ~= nil, service = p.service, cpu = p.cpu, started = p.started,
        screen = p.win and p.win.screen.name }
    end
  end
  return list
end
function API.focus(id)
  for _, w in ipairs(wins) do if w.id == id then K.focusWindow(w); return true end end
end
function API.close(id)
  for _, w in ipairs(wins) do if w.id == id then K.closeWindow(w); return true end end
end
function API.kill(id)
  for _, p in ipairs(procs) do if p.id == id then killList[#killList + 1] = p; return true end end
end
function API.sfx(name) K.sfx(name) end

-- Dialogs block the calling program until answered.
local function waitDialog(id)
  while true do
    local _, did, index, text = os.pullEvent("ccos_dialog")
    if did == id then return index, text end
  end
end
function API.alert(title, text)
  waitDialog(K.dialog({ screen = callerScreen(), title = title, text = text or "", buttons = { "OK" } }))
end
function API.confirm(title, text, yes, no)
  local i = waitDialog(K.dialog({ screen = callerScreen(), title = title, text = text or "", buttons = { no or "Cancel", yes or "OK" } }))
  return i == 2
end
function API.secretPrompt(title, text, default)
  local i, value = waitDialog(K.dialog({ screen = screenByName.term, title = title, text = text or "", input = default or "", secret=true, buttons={"Cancel","Save"} }))
  if i == 2 then return value end
end
function API.prompt(title, text, default)
  local i, value = waitDialog(K.dialog({ screen = callerScreen(), title = title, text = text or "", input = default or "",
    buttons = { "Cancel", "OK" } }))
  if i == 2 then return value end
end

function K.validateSetting(key, value)
  local booleans={clock24=true,seconds=true,leadingZero=true,sounds=true,touchSounds=true,swapSpeakers=true,agentConfirm=true,autoUpdates=true}
  if booleans[key] then return type(value)=="boolean", "Expected a boolean" end
  if key=="timezone" then return type(value)=="string" and clock.valid(value), "Unsupported time zone" end
  if key=="startColor" then for _,c in ipairs(START_COLORS)do if c.id==value then return true end end;return false,"Unknown Start colour" end
  if key=="accentColor" then for _,c in ipairs(ACCENT_COLORS)do if c.id==value then return true end end;return false,"Unknown accent colour" end
  if key=="user" then return type(value)=="string" and #value>0 and #value<=40,"Name must be 1-40 characters" end
  if key=="agentModel" then return type(value)=="string" and #value<=160 and value:match("^[%w%._:/~%-]+$")~=nil,"Invalid model id" end
  local ranges={utcOffset={-720,840},musicVolume={0,1},uiVolume={0,1},balance={-1,1},idle={0,86400},panelRotate={4,3600},agentMaxSteps={1,40},agentMaxTokens={256,8192}}
  if ranges[key]then local r=ranges[key];return type(value)=="number" and value==value and value>=r[1] and value<=r[2],"Value out of range" end
  return false,"Setting cannot be changed through this interface"
end
function API.config(key, value)
  if value == nil then return K.cfg[key] end
  K.cfg[key] = value
  K.saveConfig()
  if key == "startColor" or key == "accentColor" then
    for _, s in ipairs(screens) do if s.role ~= "off" then applyPalette(s.target); s.cache = {} end end
    os.queueEvent("ccos_theme")
  elseif key == "swapSpeakers" then
    audio.detect()
  elseif key=="autoUpdates"and value and K.updates then K.updates.check(false)
  elseif key == "screens" then
    K.buildScreens()
  end
  markAll()
end
function API.colours() return START_COLORS, ACCENT_COLORS end
function API.screens()
  local list = {}
  for _, s in ipairs(screens) do
    list[#list + 1] = { name = s.name, kind = s.kind, role = s.role, w = s.w, h = s.h,
      scale = s.kind == "monitor" and s.target.getTextScale and s.target.getTextScale() or nil, scaleCfg = s.scaleCfg }
  end
  return list
end
function API.setScreen(name, role, scale)
  local conf = K.cfg.screens[name] or {}
  if role then
    if role ~= "picture" and role ~= "panel" and role ~= "off" then error("Roles: picture, panel, off", 2) end
    conf.role = role
  end
  if scale then conf.scale = scale end
  K.cfg.screens[name] = conf
  K.saveConfig()
  K.buildScreens()
end
function API.hw() return K.hw end
function API.recent() return K.cfg.recent end
function API.addRecent(path) K.addRecent(path) end
function API.exit() K.power = "exit"; K.running = false end
function API.reboot() K.power = "reboot"; K.running = false end
function API.shutdown() K.power = "shutdown"; K.running = false end

local function findPrinter()
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "printer" then return n end
  end
end

-- Print text across as many pages as it needs. Returns true and the page
-- count, or false and why. Runs in the calling program.
function API.printText(title, text)
  local name = findPrinter()
  if not name then return false, "No printer attached" end
  local p = peripheral.wrap(name)
  local pw, ph = 25, 21
  local lines = {}
  for _, l in ipairs(wrap(text, pw)) do lines[#lines + 1] = l end
  local pages = max(1, ceil(#lines / ph))
  for pg = 1, pages do
    if not p.newPage() then return false, "Out of paper or ink (printed " .. (pg - 1) .. ")" end
    pw, ph = p.getPageSize()
    p.setPageTitle(trunc(title, 20) .. (pages > 1 and (" " .. pg .. "/" .. pages) or ""))
    for i = 1, ph do
      local l = lines[(pg - 1) * ph + i]
      if not l then break end
      p.setCursorPos(1, i)
      p.write(l)
    end
    if not p.endPage() then return false, "The output tray is full" end
  end
  K.notify("Printed", ("%s: %d page%s"):format(title, pages, pages == 1 and "" or "s"), { icon = "print", quiet = true })
  os.queueEvent("ccos_hw")
  return true, pages
end

-- One big letter per page, from the 3x5 font.
function API.printBanner(text)
  local name = findPrinter()
  if not name then return false, "No printer attached" end
  local p = peripheral.wrap(name)
  local pages = 0
  for i = 1, #text do
    local ch = text:sub(i, i):upper()
    if ch ~= " " then
      local g = gfx.FONT[ch] or gfx.FONT["?"]
      if not p.newPage() then return false, "Out of paper or ink" end
      local pw, ph = p.getPageSize()
      local sx, sy = floor(pw / #g[1]), floor(ph / 5)
      local ox = floor((pw - sx * #g[1]) / 2)
      p.setPageTitle("Banner " .. i .. ": " .. ch)
      for r = 1, 5 do
        for k = 0, sy - 1 do
          local row = ""
          for c = 1, #g[r] do row = row .. ((g[r]:sub(c, c) == "1") and ("#"):rep(sx) or (" "):rep(sx)) end
          p.setCursorPos(1 + ox, (r - 1) * sy + k + 1)
          p.write(row)
        end
      end
      if not p.endPage() then return false, "The output tray is full" end
      pages = pages + 1
    end
  end
  K.notify("Banner printed", ("%q on %d page%s"):format(text, pages, pages == 1 and "" or "s"), { icon = "print", quiet = true })
  os.queueEvent("ccos_hw")
  return true, pages
end

function API.sysinfo()
  local host = _HOST or ""
  local rows = {
    { "ccOS", VERSION },
    { "CC: Tweaked", host:match("ComputerCraft ([%w%.%-]+)") or "?" },
    { "Minecraft", host:match("Minecraft ([%w%.%-]+)") or "?" },
    { "Computer", "#" .. os.getComputerID() .. (os.getComputerLabel() and (" " .. os.getComputerLabel()) or "") },
    { "Up", fmtDur(os.clock()) },
  }
  local okF, free = pcall(fs.getFreeSpace, "/")
  local okC, cap = pcall(fs.getCapacity, "/")
  if okF and okC and type(free) == "number" and type(cap) == "number" then
    rows[#rows + 1] = { "Disk", ("%d KB free of %d KB"):format(floor(free / 1024), floor(cap / 1024)) }
  end
  for _, s in ipairs(screens) do
    rows[#rows + 1] = { "Screen " .. s.name, s.role .. ", " .. (s.w or 0) .. "x" .. (s.h or 0) }
  end
  local ai = audio.info()
  rows[#rows + 1] = { "Speakers", ai.speakers >= 2 and ("stereo: " .. tostring(audio.spk.l) .. " L, " .. tostring(audio.spk.r) .. " R")
    or (ai.speakers == 1 and "one (mono)" or "none") }
  for _, d in ipairs(K.hw.drives or {}) do
    rows[#rows + 1] = { "Drive " .. d.name, d.present and (d.label or (d.audio and ("record " .. d.audio)) or "disk") or "empty" }
  end
  for _, pr in ipairs(K.hw.printers or {}) do
    rows[#rows + 1] = { "Printer " .. pr.name, ("%d paper, %d ink"):format(pr.paper or 0, pr.ink or 0) }
  end
  rows[#rows + 1] = { "Windows", tostring(#wins) }
  return rows
end

------------------------------------------------------------------------
-- Services
------------------------------------------------------------------------

K.hw = { drives = {}, printers = {} }

-- Peripheral calls can wait on the server, so devices are read here, in
-- a coroutine of their own, and the kernel draws from what it found.
local function hwService()
  while true do
    local hw = { drives = {}, printers = {} }
    for _, n in ipairs(peripheral.getNames()) do
      local ty = peripheral.getType(n)
      local function call(m, ...)
        local ok, v = pcall(peripheral.call, n, m, ...)
        if ok then return v end
      end
      if ty == "drive" then
        local d = { name = n, present = call("isDiskPresent") }
        if d.present then
          d.label = call("getDiskLabel")
          if call("hasData") then d.mount = call("getMountPath") end
          if call("hasAudio") then d.audio = call("getAudioTitle") or "Record" end
          d.id = call("getDiskID")
        end
        hw.drives[#hw.drives + 1] = d
      elseif ty == "printer" then
        hw.printers[#hw.printers + 1] = { name = n, paper = call("getPaperLevel"), ink = call("getInkLevel") }
      end
    end
    K.hw = hw
    markAll()
    local timer = os.startTimer(5)
    while true do
      local e, p = os.pullEvent()
      if (e == "timer" and p == timer) or e == "disk" or e == "disk_eject" or e == "peripheral"
        or e == "peripheral_detach" or e == "ccos_hw" then
        break
      end
    end
  end
end

------------------------------------------------------------------------
-- Main loop
------------------------------------------------------------------------

local tickTimer, animTimer

local function onTick()
  tickTimer = os.startTimer(1)
  local t = now()
  if K.updates then K.updates.maybePrompt()end
  if K.booting and t - K.bootStart > 2200 then
    K.booting = false
    markAll()
    K.notify(greeting() .. ", " .. K.cfg.user, K.device.pocket and "ccOS is ready. F2 returns to Start." or "ccOS is ready. Tap a tile, or press F2 for Start.", { icon = "about", quiet = true, silent = true })
  end
  local changed = false
  for i = #K.toasts, 1, -1 do
    if K.toasts[i].untilT < t then table.remove(K.toasts, i); changed = true end
  end
  if changed then markAll() end
  local minute = clockText(false)
  if minute ~= K.lastMinute or K.cfg.seconds then
    K.lastMinute = minute
    for _, s in ipairs(screens) do if s.role == "pocket" or s.role == "console" then markDirty(s) end end
  end
  for _, s in ipairs(screens) do if s.role == "panel" or s.role == "picture" then markDirty(s) end end
  if K.cfg.idle and K.cfg.idle > 0 and not K.saver and not K.booting and t - K.lastInput > K.cfg.idle * 1000 then
    K.saver = true
    markAll()
  end
  if K.saver then markAll() end
  if not K.panelPinned and t - K.panelAt > (K.cfg.panelRotate or 12) * 1000 then
    K.panelAt = t
    local info = audio.info()
    repeat
      K.panelPage = K.panelPage % #PANEL_PAGES + 1
    until PANEL_PAGES[K.panelPage] ~= "music" or info.state ~= "stopped" or info.disc
  end
end

local function dispatch(ev)
  local e = ev[1]
  if K.agent and K.agent.consume(ev) then return end
  if e == "timer" then
    if ev[2] == K.renderTimer then K.renderTimer = nil; render(); return end
    if ev[2] == tickTimer then onTick(); return end
    if ev[2] == animTimer then
      animTimer = nil
      local info = audio.info()
      if info.state == "playing" then
        for _, s in ipairs(screens) do if s.role == "panel" then markDirty(s) end end
        animTimer = os.startTimer(0.25)
      end
      return
    end
    broadcast(ev)
  elseif e == "mouse_click" or e == "mouse_drag" or e == "mouse_up" or e == "mouse_scroll" then
    local s = screenByName.term
    local kind = ({ mouse_click = "click", mouse_drag = "drag", mouse_up = "up", mouse_scroll = "scroll" })[e]
    pointer(s, kind, ev[2], ev[3], ev[4])
  elseif e == "monitor_touch" then
    local s = screenByName[ev[2]]
    if s and s.role ~= "off" then
      pointer(s, "touch", 1, ev[3], ev[4])
    else
      broadcast(ev)
    end
  elseif e == "key" or e == "key_up" or e == "char" or e == "paste" then
    keyboard(ev)
  elseif e == "terminate" then
    local target = K.keyTarget()
    if target then post(target.proc, ev) end
  elseif e == "monitor_resize" then
    local s = screenByName[ev[2]]
    if s and s.role ~= "off" then
      setupScreen(s);markDirty(s)
      for _, w in ipairs(wins) do if w.screen == s then layout(w) end end
    end
    broadcast(ev)
  elseif e == "term_resize" then
    local s = screenByName.term
    setupScreen(s);markDirty(s)
    for _, w in ipairs(wins) do if w.screen == s then layout(w) end end
  elseif e == "peripheral" or e == "peripheral_detach" then
    local ty = e == "peripheral" and peripheral.getType(ev[2])
    if e == "peripheral" and ty then
      K.notify("Connected", ty .. " on " .. ev[2], { icon = "tasks", quiet = true, time = 3000 })
    end
    if ty == "monitor" or screenByName[ev[2]] then K.buildScreens() end
    broadcast(ev)
  elseif e == "disk" then
    K.notify("Disk inserted", "Drive " .. tostring(ev[2]), { icon = "disk", quiet = true, action = function()
      local mount = pcall(peripheral.call, ev[2], "getMountPath") and peripheral.call(ev[2], "getMountPath")
      if mount then K.launch("files", { "/" .. mount }) end
    end })
    K.sfx("disk")
    broadcast(ev)
  elseif e == "disk_eject" then
    K.notify("Disk ejected", "Drive " .. tostring(ev[2]), { icon = "disk", quiet = true, time = 3000 })
    broadcast(ev)
  elseif e == "ccos_audio" then
    broadcast(ev)
    if not animTimer then animTimer = os.startTimer(0.25) end
  else
    broadcast(ev)
  end
end

local function boot()
  loadConfig()
  K.lastInput = now()
  audio = loadModule(ROOT .. "/lib/audio.lua")(K)
  K.audio = audio
  API.audio = audio
  K.buildScreens()
  if K.device.pocket then screenByName.term.pocketHome=true end
  _G.ccos = API
  _G.aurora = API
  ui = loadModule(ROOT .. "/lib/ui.lua")
  API.ui = ui
  K.agent = loadModule(ROOT .. "/lib/agent.lua")(K, json)
  API.agent = K.agent
  K.updates=loadModule(ROOT.."/lib/updater.lua")(K,json,sha256,installer)
  API.updates=K.updates
  API.suite = loadModule(ROOT .. "/lib/suite.lua")
  writeBin()
  K.booting, K.bootStart = true, now()
  K.spawn(audio.service, { title = "Audio", service = true })
  K.spawn(hwService, { title = "Devices", service = true })
  K.spawn(K.updates.service,{title="Update monitor",service=true})
  audio.boot()
  tickTimer = os.startTimer(0.2)
  markAll()
end

local function shutdown()
  for _, s in ipairs(screens) do
    pcall(function()
      resetPalette(s.target)
      s.target.setBackgroundColor(colors.black)
      s.target.setTextColor(colors.white)
      s.target.clear()
      s.target.setCursorPos(1, 1)
      s.target.setCursorBlink(s.kind == "term")
      if s.kind == "monitor" then s.target.setTextScale(1) end
    end)
  end
  _G.ccos = nil
  _G.aurora = nil
  if audio then pcall(function()
    if audio.spk.l then peripheral.call(audio.spk.l, "stop") end
    if audio.spk.r and audio.spk.r ~= audio.spk.l then peripheral.call(audio.spk.r, "stop") end
  end) end
end

local ok, err = pcall(function()
  boot()
  while K.running do
    local ev = table.pack(os.pullEventRaw())
    dispatch(ev)
    drain()
  end
end)

if ok and(K.power=="shutdown"or K.power=="reboot")then pcall(powerAnimation.play,K.power)end
shutdown()
term.redirect(nativeTerm)
if not ok then
  printError("ccOS stopped: " .. tostring(err))
  logCrash({ title = "kernel" }, err)
  print("Details are in " .. ROOT .. "/crash.log. Run " .. ROOT .. "/kernel.lua to start again.")
elseif K.power == "reboot" then
  os.reboot()
elseif K.power == "shutdown" then
  os.shutdown()
else
  print("Left ccOS. Type " .. ROOT .. "/kernel.lua to return.")
end
