--[[
  ccOS                                                        v2.1

  A windowed desktop for CC: Tweaked across every screen it can find:
  the computer's desktop and advanced monitors as touch-only media hubs,
  smaller monitors as information panels, two speakers as a stereo pair,
  plus printers and disk drives.

  Every app is an ordinary CC program running in its own window, so the
  CraftOS shell, edit, paint and friends work unchanged; ccOS's own
  apps add the `ccos` API on top.
]]

local VERSION = "2.1"
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

local gfx = loadModule(ROOT .. "/lib/gfx.lua")
local HEX = gfx.HEX
local clock = loadModule(ROOT .. "/lib/time.lua")
local catalog = loadModule(ROOT .. "/lib/catalog.lua")
local json = loadModule(ROOT .. "/lib/json.lua")
local sha256=loadModule(ROOT.."/lib/sha256.lua")
local installer=loadModule(ROOT.."/lib/install.lua")
K.clock, K.catalog, K.json = clock, catalog, json

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------

local DEFAULTS = {
  user = "Home", theme = "ccos", wallpaper = "ccos",
  clock24 = false, seconds = false, leadingZero = false, timezone = "local", utcOffset = 0,
  sounds = true, touchSounds = true, uiVolume = 0.6, musicVolume = 0.8, balance = 0, swapSpeakers = false,
  screens = {}, panelRotate = 12, idle = 300, shadows = true,
  desktop = { "files", "terminal", "music", "piano", "clock", "calc", "print", "tasks", "settings", "agent", "notes", "checklist" },
  fullSync=false, autoUpdates=true,
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
  if cfg.theme == "aurora" then cfg.theme = "ccos" end
  if cfg.wallpaper == "aurora" then cfg.wallpaper = "ccos" end
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
-- Themes. Every theme fills the same 16 slots, so the semantic colours
-- below never change; only what each slot looks like does.
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

local THEMES = {
  ccos = { name = "ccOS", palette = pal({ 0x0E1020, 0x1F2440, 0x2E3560, 0x8C93BF, 0xEEF1FF, 0x3DDBD9,
    0x4D7CFF, 0x9B6BFF, 0xD66BFF, 0xFF7EB6, 0x6BFFB0, 0x2FB67C, 0xFFD36B, 0xFF9B54, 0xFF5C73, 0x7FC8FF }) },
  midnight = { name = "Midnight", palette = pal({ 0x0B0F1A, 0x161E2E, 0x22304A, 0x7D8BA6, 0xE8EEF9, 0x5AB0FF,
    0x3D7BFF, 0x7A6CFF, 0xB86CFF, 0xFF79A8, 0x6EE7A8, 0x2E9E6E, 0xFFD479, 0xFFA15C, 0xFF5F6D, 0x9CCBFF }) },
  sunset = { name = "Sunset", palette = pal({ 0x1A0F14, 0x2B1A24, 0x3D2533, 0xA88C99, 0xFFF1EC, 0xFF9E64,
    0xFF6B8B, 0xC86BFA, 0xFF5DA2, 0xFF8FB1, 0xB8E986, 0x6BBF8A, 0xFFD56B, 0xFF8A4C, 0xFF4F5E, 0x8FB8FF }) },
  forest = { name = "Forest", palette = pal({ 0x0D1510, 0x17241B, 0x223527, 0x86A08F, 0xEEF6EF, 0x6BE3A4,
    0x4FA3FF, 0x9C7BFF, 0xD27BFF, 0xFF8FA8, 0xA6F06B, 0x3BA55C, 0xF2D86B, 0xF2A65A, 0xF2665A, 0x8CD3FF }) },
  ocean = { name = "Ocean", palette = pal({ 0x07131C, 0x0F2230, 0x173246, 0x7FA2B8, 0xE9F6FF, 0x2EE6D6,
    0x2A8CFF, 0x6C7BFF, 0xB07BFF, 0xFF7FB0, 0x5CF2A8, 0x1FA67A, 0xFFE07A, 0xFFB26B, 0xFF6B6B, 0x7FD8FF }) },
  classic = { name = "Classic", palette = { [C.brown] = 0x333333 } },
}
local THEME_ORDER = { "ccos", "midnight", "sunset", "forest", "ocean", "classic" }
K.THEMES, K.THEME_ORDER = THEMES, THEME_ORDER

local function applyPalette(t)
  local th = THEMES[K.cfg.theme] or THEMES.ccos
  for i = 0, 15 do
    local c = floor(2 ^ i)
    local v = th.palette[c]
    if v then
      t.setPaletteColour(c, v)
    else
      t.setPaletteColour(c, term.nativePaletteColour(c))
    end
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
  app.touch = app.touch or ({clock=true,piano=true,calc=true})[app.id] or false
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
  if role == "panel" then needW, needH = 40, 8
  elseif role == "picture" then needW, needH = 60, 19
  elseif role == "mirror" then needW, needH = nativeTerm.getSize() end
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
  s.taskH = (s.kind == "monitor" and s.h >= 24) and 3 or 1
  s.touch = s.kind == "monitor"
  s.menu, s.popup = nil, nil
  applyPalette(s.target)
  s.target.setCursorBlink(false)
  s.dirty = true
end

function K.homeScreen()
  for _, s in ipairs(screens) do
    if s.kind == "monitor" and s.role == "desktop" then return s end
  end
  return screenByName.term
end

function K.activeScreen()
  if K.focus and K.focus.screen.role == "desktop" then return K.focus.screen end
  if K.lastScreen and K.lastScreen.role == "desktop" and screenByName[K.lastScreen.name] then return K.lastScreen end
  return K.homeScreen()
end

function K.buildScreens()
  local list, byName = {}, {}
  local function make(name, target, kind, defaultRole)
    local s = screenByName[name] or { name = name, hits = {}, cache = {} }
    local conf = K.cfg.screens[name] or {}
    s.target, s.kind = target, kind
    local was = s.role
    s.role = conf.role or defaultRole
    if was=="picture"and s.role~="picture"and byName.term then
      local dest=byName.term;dest.dialogs=dest.dialogs or {}
      for _,d in ipairs(s.dialogs or {})do d.screen=dest;dest.dialogs[#dest.dialogs+1]=d end
      s.dialogs={}
    end
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
  make("term", nativeTerm, "term", "desktop").role = "desktop"
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
  -- Upgrade the main display once; later role choices remain explicit.
  if K.cfg.screenLayout < 2 and mons[1] and mons[1].color then
    local conf = K.cfg.screens[mons[1].name] or {}
    if not conf.role or conf.role == "mirror" or conf.role == "desktop" then conf.role = "picture"; conf.scale = "auto" end
    K.cfg.screens[mons[1].name] = conf
    K.cfg.screenLayout = 2
    K.saveConfig()
  end
  K.primaryMonitorName=mons[1]and mons[1].color and mons[1].name or nil
  for _,m in ipairs(mons)do if m.color and m.name==K.cfg.mainMonitor then K.primaryMonitorName=m.name;break end end
  -- The biggest advanced monitor is a touch-only hub; the rest are panels.
  local first = true
  for _, x in ipairs(mons) do
    if x.name==K.primaryMonitorName and K.cfg.fullSync then
      K.cfg.screens[x.name]=K.cfg.screens[x.name]or {};K.cfg.screens[x.name].role="mirror";K.cfg.screens[x.name].scale="auto"
    end
    make(x.name, x.m, "monitor", (x.color and first) and "picture" or "panel")
    if x.color then first = false end
  end
  screens, screenByName = list, byName
  K.screens = list
  for _, s in ipairs(list) do
    if s.role ~= "off" then setupScreen(s) end
  end
  local home = K.homeScreen()
  for _, w in ipairs(wins) do
    if not byName[w.screen.name] or (w.screen.role ~= "desktop" and w.screen.role ~= "picture") then w.screen = home end
    layout(w)
  end
  if markAll then markAll() end
end

function K.pictureScreen()
  local s=K.primaryMonitorName and screenByName[K.primaryMonitorName]
  if s and s.role=="picture"then return s end
  for _,candidate in ipairs(screens)do if candidate.kind=="monitor"and candidate.role=="picture"then return candidate end end
end
function K.setFullSync(enabled)
  local current=K.pictureScreen()
  local name=current and current.name or K.primaryMonitorName
  if not name then return false,"No advanced monitor is connected"end
  K.cfg.fullSync=enabled==true;K.cfg.mainMonitor=name
  local conf=K.cfg.screens[name]or {};conf.role=enabled and "mirror"or "picture";conf.scale="auto";K.cfg.screens[name]=conf
  K.saveConfig();K.buildScreens();return true
end

------------------------------------------------------------------------
-- Windows
------------------------------------------------------------------------

local function workHeight(s) return s.h - s.taskH end

function layout(w)
  local s = w.screen
  local ah = workHeight(s)
  if s.role == "picture" then
    w.x, w.y, w.w, w.h = 1, 1, max(12, s.w), max(3, s.h - 2)
  elseif w.state == "max" then
    w.x, w.y, w.w, w.h = 1, 1, s.w, ah - 1
  elseif w.state == "left" or w.state == "right" then
    local half = floor(s.w / 2)
    w.y, w.h = 1, ah - 1
    if w.state == "left" then w.x, w.w = 1, half else w.x, w.w = half + 1, s.w - half end
  else
    w.w = clamp(w.w, 12, s.w)
    w.h = clamp(w.h, 3, ah - 1)
    w.x = clamp(w.x, 1, s.w - w.w + 1)
    w.y = clamp(w.y, 1, ah - w.h)
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

local function windowsOn(s)
  local list = {}
  for _, w in ipairs(wins) do if w.screen == s then list[#list + 1] = w end end
  return list
end

function newWindow(p, o)
  local s = o.screen or K.activeScreen()
  local ah = workHeight(s)
  local w = { id = p.id, proc = p, screen = s, title = o.title or p.title, app = p.app, state = "normal", opened = now() }
  local grow = (s.touch and s.w >= 120) and 1.3 or 1
  w.w, w.h = min(floor((o.w or 60) * grow), s.w), min(floor((o.h or 20) * grow), ah - 1)
  if s.w < 60 or w.w >= s.w - 2 or w.h >= ah - 2 then w.state = "max" end
  local n = #windowsOn(s)
  w.x = floor((s.w - w.w) / 2) + 1 + (n % 5) * 3 - 6
  w.y = floor((ah - w.h) / 2) + (n % 5) - 1
  w.buf = makeBuffer(w.w, w.h)
  wins[#wins + 1] = w
  layout(w)
  K.focusWindow(w)
  return w
end

function K.focusWindow(w)
  if not w then return end
  for i, x in ipairs(wins) do
    if x == w then table.remove(wins, i); break end
  end
  wins[#wins + 1] = w
  if w.state == "min" then w.state = w.restore or "normal"; layout(w) end
  K.focus = w
  markDirty(w.screen)
end

function removeWindow(w)
  for i, x in ipairs(wins) do
    if x == w then table.remove(wins, i); break end
  end
  if capture and capture.win == w then capture = nil end
  if K.drag and K.drag.win == w then K.drag = nil end
  if K.focus == w then
    K.focus = nil
    for i = #wins, 1, -1 do
      if wins[i].screen == w.screen and wins[i].state ~= "min" then K.focus = wins[i]; break end
    end
  end
  markDirty(w.screen)
end

function K.closeWindow(w)
  post(w.proc, { "terminate", n = 1 })
  killList[#killList + 1] = w.proc
  K.sfx("close")
end

function K.minimize(w)
  if w.state ~= "min" then w.restore = w.state end
  w.state = "min"
  if K.focus == w then
    K.focus = nil
    for i = #wins, 1, -1 do
      if wins[i] ~= w and wins[i].screen == w.screen and wins[i].state ~= "min" then K.focus = wins[i]; break end
    end
  end
  markDirty(w.screen)
end

function K.toggleMax(w)
  if w.state == "max" then w.state = "normal" else w.state = "max" end
  layout(w)
  K.focusWindow(w)
end

function K.snap(w, side)
  w.state = (w.state == side) and "normal" or side
  layout(w)
  K.focusWindow(w)
end

local function desktops()
  local list = {}
  for _, s in ipairs(screens) do if s.role == "desktop" then list[#list + 1] = s end end
  return list
end

function K.moveToScreen(w, s)
  local old = w.screen
  w.screen = s
  if w.state == "normal" then
    w.x, w.y = floor((s.w - w.w) / 2) + 1, 2
  end
  layout(w)
  K.focusWindow(w)
  markDirty(old)
end

function K.moveToNextScreen(w)
  local ds = desktops()
  for i, s in ipairs(ds) do
    if s == w.screen then return K.moveToScreen(w, ds[i % #ds + 1]) end
  end
end

-- Keys go to the top window on the computer's screen, which is the one
-- the player can see while typing; failing that, the focused window.
function K.keyTarget()
  if K.focus and K.focus.screen.kind == "term" and K.focus.state ~= "min" then return K.focus end
  for i = #wins, 1, -1 do
    local w = wins[i]
    if w.screen.kind == "term" and w.state ~= "min" then return w end
  end
  if K.focus and K.focus.screen.role ~= "picture" and K.focus.state ~= "min" then return K.focus end
end

function K.cycleFocus()
  local s = screenByName.term
  local list = windowsOn(s)
  if #list == 0 then return end
  K.focusWindow(list[1])
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
  -- Big Picture keeps the prompt on the monitor and bridges its field to
  -- the computer input console. Other monitor roles use a desktop prompt.
  if o.input and s.kind ~= "term" and s.role~="picture" then
    K.notify("Type on the computer", o.title or "", { icon = "terminal", quiet = true, time = 6000 })
    s = screenByName.term
  end
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

-- The splash while booting.
local function drawSplash(s)
  -- the same key drawWall uses, so an ccos desktop reuses this one
  local key = "ccos" .. s.w .. "x" .. s.h
  if s.wallKey ~= key then
    s.wall, s.wallKey = gfx.wallpaper("ccos", s.w, s.h), key
  end
  for y = 1, s.h do
    local r = s.wall[y]
    B.setCursorPos(1, y)
    B.blit(r[1], r[2], r[3])
  end
  local scale = 1
  for k = 6, 1, -1 do
    local logo = gfx.logo(k)
    if gfx.cellsWidth(logo) <= s.w * 0.6 and #logo <= s.h * 0.4 then scale = k; break end
  end
  local logo = gfx.logo(scale)
  local lw = gfx.cellsWidth(logo)
  local ly = max(1, floor((s.h - #logo) / 2) - 1)
  gfx.drawCells(B, floor((s.w - lw) / 2) + 1, ly, logo)
  local frac = clamp((now() - K.bootStart) / 2200, 0, 1)
  local bw = min(s.w - 4, max(16, lw))
  local bx, by = floor((s.w - bw) / 2) + 1, ly + #logo + 1
  if by <= s.h then
    fill(bx, by, bw, 1, T.surface)
    fill(bx, by, floor(bw * frac + 0.5), 1, T.accent)
  end
  if by + 2 <= s.h then
    local msg = frac < 0.4 and "Waking the screens" or (frac < 0.8 and "Tuning the speakers" or "Welcome")
    put(floor((s.w - #msg) / 2) + 1, by + 2, msg, T.muted, T.bg)
  end
end

local function drawWall(s)
  local key = K.cfg.wallpaper .. s.w .. "x" .. s.h
  if s.wallKey ~= key then
    s.wall, s.wallKey = gfx.wallpaper(K.cfg.wallpaper, s.w, s.h), key
  end
  for y = 1, s.h do
    local r = s.wall[y]
    B.setCursorPos(1, y)
    B.blit(r[1], r[2], r[3])
  end
end

-- Text straight onto the wallpaper, keeping its colours behind.
local function wallText(s, x, y, text, fg)
  if y < 1 or y > s.h then return end
  local row = s.wall[y]
  local bgs = row[3]:sub(x, x + #text - 1)
  if #bgs < #text then bgs = bgs .. ("f"):rep(#text - #bgs) end
  B.setCursorPos(x, y)
  B.blit(text, (HEX[fg or T.text]):rep(#text), bgs)
end

local function drawIcons(s)
  local big = s.w >= 100 and s.h >= 30
  local scale, iw, ih = big and 2 or 1, big and 8 or 4, big and 4 or 2
  local slotW, slotH = big and 14 or 12, ih + 3
  local rows = max(1, floor((workHeight(s) - 1) / slotH))
  for i, id in ipairs(K.cfg.desktop) do
    local app = appById(id)
    if app then
      local col, row = floor((i - 1) / rows), (i - 1) % rows
      local x, y = 2 + col * slotW, 2 + row * slotH
      if x + slotW - 1 <= s.w and y + ih <= workHeight(s) then
        gfx.icon(B, x + floor((slotW - iw) / 2), y, app.id, scale)
        local label = trunc(app.name, slotW)
        local labelW=min(slotW,#label+2)
        local labelX=x+floor((slotW-labelW)/2)
        fill(labelX,y+ih,labelW,1,T.bg)
        put(labelX+floor((labelW-#label)/2),y+ih,label,T.text,T.bg)
        hit(x, y, x + slotW - 1, y + ih + 1, function() K.launch(app.id, nil, { screen = s }) end)
      end
    end
  end
end

local lastTitleClick = { t = 0 }

local function drawWindow(s, w)
  local focused = K.focus == w
  local x, y, ww, wh = w.x, w.y, w.w, w.h
  if K.cfg.shadows and w.state == "normal" then
    shade(x + 1, y + wh + 1, ww, 1)
    shade(x + ww, y + 1, 1, wh + 1)
  end
  local tb = focused and T.raised or T.surface
  local tf = focused and T.text or T.muted
  fill(x, y, ww, 1, tb)
  local g = gfx.GLYPHS[w.app and w.app.id or ""] or { "\7", T.accent }
  put(x + 1, y, g[1], focused and g[2] or T.muted, tb)
  local bw = s.touch and 5 or 3
  local bx = x + ww - 4 * bw
  put(x + 3, y, trunc(w.title, max(0, bx - x - 4)), tf, tb)
  hit(x, y, bx - 1, y, function(hx, hy, btn, kind)
    K.focusWindow(w)
    if kind == "click" then
      local t = now()
      if lastTitleClick.win == w and t - lastTitleClick.t < 400 then
        K.toggleMax(w)
        lastTitleClick.t = 0
        return
      end
      lastTitleClick.win, lastTitleClick.t = w, t
      K.drag = { kind = "move", win = w, dx = hx - w.x, dy = hy - w.y }
    end
  end)
  local labels = { "\4", "-", w.state == "normal" and "\30" or "\31", "\215" }
  local actions = {
    function() K.windowMenu(w, s) end,
    function() K.minimize(w) end,
    function() K.toggleMax(w) end,
    function() K.closeWindow(w) end,
  }
  for i = 1, 4 do
    local cx = bx + (i - 1) * bw
    local fg = (i == 4 and focused) and T.danger or tf
    put(cx, y, centre(labels[i], bw), fg, tb)
    hit(cx, y, cx + bw - 1, y, actions[i])
  end
  for row = 1, wh do
    local t, f, b = w.buf.getLine(row)
    if t then
      B.setCursorPos(x, y + row)
      B.blit(t, f, b)
    end
  end
  hit(x, y + 1, x + ww - 1, y + wh, nil, { content = w })
  if not s.touch and w.state == "normal" then
    put(x + ww, y + wh + 1, "\127", T.muted, T.bg)
    hit(x + ww, y + wh + 1, x + ww, y + wh + 1, function(_, _, _, kind)
      if kind == "click" then K.drag = { kind = "resize", win = w } end
    end)
  end
end

local function trayItems(s)
  local items = {}
  local info = audio.info()
  if K.agent and (K.agent.busy or K.agent.configured())then
    items[#items+1]={label=K.agent.pending and "AI!"or(K.agent.busy and "AI.."or "AI"),color=T.accent,fn=function()K.launch("agent",{}, {screen=screenByName.term})end}
  end
  if info.state ~= "stopped" or info.disc then
    local name = info.disc and info.discTitle or info.title or "Music"
    local glyph = info.state == "playing" and "\16" or "\14"
    items[#items + 1] = { label = glyph .. " " .. trunc(name, s.w >= 100 and 22 or 9), color = T.accent2,
      fn = function(x) K.musicPopup(s, x) end }
  end
  for _, d in ipairs(K.hw.drives or {}) do
    if d.present then
      items[#items + 1] = { label = "\8 " .. trunc(d.label or (d.audio and "Record") or "Disk", s.w >= 100 and 12 or 6),
        color = T.text, fn = function(x) K.drivePopup(s, x, d) end }
    end
  end
  local pr = (K.hw.printers or {})[1]
  if pr and s.w >= 60 then
    local low = (pr.paper or 0) < 4 or (pr.ink or 0) < 4
    items[#items + 1] = { label = "\20", color = low and T.warn or T.muted, fn = function() K.launch("print", nil, { screen = s }) end }
  end
  local vol = floor((K.cfg.musicVolume or 0) * 100 + 0.5)
  items[#items + 1] = { label = "\17" .. vol .. "%", color = T.muted, fn = function(x) K.volumePopup(s, x) end }
  items[#items + 1] = { label = "\7" .. (K.unread > 0 and (" " .. K.unread) or ""), color = K.unread > 0 and T.accent or T.muted,
    fn = function(x) K.notificationPopup(s, x) end }
  return items
end

local function drawTaskbar(s)
  local th = s.taskH
  local y0 = s.h - th + 1
  local my = y0 + floor((th - 1) / 2)
  fill(1, y0, s.w, th, T.surface)
  -- Start button
  local wide = s.w >= 70
  local startW = wide and 11 or 5
  fill(1, y0, startW, th, s.menu and T.accent2 or T.accent)
  put(1, my, centre(wide and "\4 ccOS" or "\4", startW), T.bg, s.menu and T.accent2 or T.accent)
  hit(1, y0, startW, s.h, function() K.toggleStart(s) end)
  -- Clock and tray, right to left
  local rx = s.w
  local ct = clockText(K.cfg.seconds)
  local cw = #ct + 2
  rx = rx - cw + 1
  put(rx, my, centre(ct, cw), T.text, T.surface)
  if th >= 3 then put(rx, my + 1, centre(clock.date(K.cfg, "%d %b"), cw), T.muted, T.surface) end
  hit(rx, y0, s.w, s.h, function() K.launch("clock", nil, { screen = s }) end)
  local items = trayItems(s)
  for i = #items, 1, -1 do
    local it = items[i]
    local w = #it.label + 2
    if rx - w < startW + 12 then break end
    rx = rx - w
    put(rx, my, " " .. it.label .. " ", it.color, T.surface)
    local ix = rx
    hit(rx, y0, rx + w - 1, s.h, function() it.fn(ix) end)
  end
  if s.w >= 60 then
    local label = " \16 Run "
    rx = rx - #label - 1
    if rx > startW + 12 then
      put(rx, my, label, T.muted, T.surface)
      hit(rx, y0, rx + #label - 1, s.h, function() K.togglePalette(s) end)
    else
      rx = rx + #label + 1
    end
  end
  -- Window buttons
  local list = windowsOn(s)
  table.sort(list, function(a, b) return a.opened < b.opened end)
  local x = startW + 2
  local avail = rx - x - 1
  if #list > 0 and avail > 4 then
    local bw = clamp(floor(avail / #list), 5, 26)
    for _, w in ipairs(list) do
      if x + bw - 1 > rx - 1 then break end
      local focused = K.focus == w
      local bg = focused and T.raised or T.surface
      fill(x, y0, bw - 1, th, bg)
      local g = gfx.GLYPHS[w.app and w.app.id or ""] or { "\7", T.accent }
      put(x + 1, my, g[1], w.state == "min" and T.muted or g[2], bg)
      put(x + 3, my, trunc(w.title, bw - 5), w.state == "min" and T.muted or T.text, bg)
      if focused then fill(x, y0 + th - 1, bw - 1, 1, T.accent) end
      if focused and th == 1 then put(x, y0, " ", T.text, T.accent) end
      hit(x, y0, x + bw - 2, s.h, function()
        if K.focus == w and w.state ~= "min" then K.minimize(w) else K.focusWindow(w) end
      end)
      x = x + bw
    end
  end
end

local function visibleApps(search, category)
  local list = {}
  search = (search or ""):lower()
  for _, a in ipairs(APPS) do
    local matchesCategory = not category or category == "All" or a.category == category
    if category == "Favorites" then for _,id in ipairs(K.cfg.desktop)do if id==a.id then matchesCategory=true end end end
    if not a.hidden and matchesCategory and (search == "" or a.name:lower():find(search, 1, true) or a.id:find(search, 1, true)) then
      list[#list + 1] = a
    end
  end
  return list
end

local function drawStartMenu(s)
  local m = s.menu
  local th = s.taskH
  local mw = min(s.w, 50)
  local apps = visibleApps(m.search, m.search ~= "" and "All" or (m.category or "All"))
  local cols = mw >= 44 and 2 or 1
  local tileW, tileH = floor((mw - 2) / cols), 3
  local maxH = workHeight(s) - 1
  local gridRows = ceil(#apps / cols)
  local mh = min(maxH, 6 + gridRows * tileH)
  local x0, y0 = 1, s.h - th - mh + 1
  hit(1, 1, s.w, s.h, function() s.menu = nil end)
  fill(x0, y0, mw, mh, T.surface)
  fill(x0, y0, mw, 1, T.raised)
  put(x0 + 1, y0, trunc(greeting() .. ", " .. K.cfg.user, mw - 10), T.text, T.raised)
  local date = clock.date(K.cfg, "%a %d %b")
  if mw > #date + 20 then put(x0 + mw - #date - 1, y0, date, T.muted, T.raised) end
  local query = (m.search ~= "" and m.search) or "Type to search apps"
  put(x0 + 1, y0 + 1, "\16 ", T.accent, T.surface)
  put(x0 + 3, y0 + 1, trunc(query, mw - 4), m.search ~= "" and T.text or T.muted, T.surface)
  hit(x0, y0, x0 + mw - 1, y0 + mh - 1, function() end)
  local categories={"All"};for _,name in ipairs(catalog.categories)do categories[#categories+1]=name end
  local index=1;for i,name in ipairs(categories)do if name==(m.category or "All")then index=i end end
  put(x0+2,y0+2,"Category: "..(m.category or "All"),T.accent,T.surface)
  button(x0+mw-9,y0+2," < ",T.text,T.raised,function()m.category=categories[(index-2)%#categories+1];m.scroll=0 end)
  button(x0+mw-5,y0+2," > ",T.text,T.raised,function()m.category=categories[index%#categories+1];m.scroll=0 end)
  local gy = y0 + 3
  local visible = max(1, floor((mh - 6) / tileH))
  m.scroll = clamp(m.scroll or 0, 0, max(0, gridRows - visible))
  if gridRows > visible then
    hit(x0, gy, x0 + mw - 1, gy + visible * tileH - 1, nil, {
      scroll = function(dir) m.scroll = (m.scroll or 0) + dir end,
    })
  end
  for i, a in ipairs(apps) do
    local r = floor((i - 1) / cols) - m.scroll
    local c = (i - 1) % cols
    if r >= 0 and r < visible then
      local tx, ty = x0 + 1 + c * tileW, gy + r * tileH
      gfx.icon(B, tx, ty, a.id)
      put(tx + 5, ty, trunc(a.name, tileW - 6), T.text, T.surface)
      put(tx + 5, ty + 1, trunc(a.desc or "", tileW - 6), T.muted, T.surface)
      hit(tx, ty, tx + tileW - 2, ty + tileH - 1, function()
        s.menu = nil
        K.launch(a.id, nil, { screen = s })
      end)
    end
  end
  if gridRows > visible then
    -- Scroll-only regions must not mask the tile click handlers above.
    local py = y0 + mh - 2
    button(x0 + 1, py, " < Prev ", T.text, T.raised, function() m.scroll = max(0, m.scroll - visible) end)
    button(x0 + mw - 9, py, " Next > ", T.text, T.raised, function() m.scroll = min(gridRows - visible, m.scroll + visible) end)
  end
  -- Power row
  local py = y0 + mh - 1
  fill(x0, py, mw, 1, T.raised)
  local bx = x0 + 1
  bx = button(bx, py, " Settings ", T.text, T.raised, function() s.menu = nil; K.launch("settings", nil, { screen = s }) end) + 1
  bx = button(bx, py, " Run ", T.text, T.raised, function() s.menu = nil; K.togglePalette(s) end) + 1
  local right = { { " Exit ", function() K.confirmPower(s, "exit") end },
    { " Restart ", function() K.confirmPower(s, "reboot") end },
    { " Off ", function() K.confirmPower(s, "shutdown") end } }
  local rx = x0 + mw - 1
  for i = #right, 1, -1 do
    local label = right[i][1]
    rx = rx - #label
    if rx <= bx then break end
    button(rx, py, label, i == 3 and T.danger or T.muted, T.raised, right[i][2])
    rx = rx - 1
  end
end

local function drawPopup(s)
  local p = s.popup
  local w = 0
  for _, it in ipairs(p.items) do w = max(w, #it.label) end
  if p.title then w = max(w, #p.title) end
  w = min(s.w - 2, w + 4)
  local h = #p.items + (p.title and 1 or 0)
  local x = clamp(p.x, 1, s.w - w + 1)
  local y = p.y or (workHeight(s) - h + 1)
  y = clamp(y, 1, workHeight(s) - h + 1)
  hit(1, 1, s.w, s.h, function() s.popup = nil end)
  shade(x + 1, y + h, w, 1)
  shade(x + w, y + 1, 1, h)
  fill(x, y, w, h, T.surface)
  local yy = y
  if p.title then
    fill(x, yy, w, 1, T.raised)
    put(x + 1, yy, trunc(p.title, w - 2), T.accent, T.raised)
    yy = yy + 1
  end
  for _, it in ipairs(p.items) do
    put(x + 2, yy, trunc(it.label, w - 3), it.disabled and T.muted or (it.color or T.text), T.surface)
    if not it.disabled and it.fn then
      local fn = it.fn
      hit(x, yy, x + w - 1, yy, function()
        if not it.stay then s.popup = nil end
        fn()
      end)
    else
      hit(x, yy, x + w - 1, yy, function() end)
    end
    yy = yy + 1
  end
end

function K.popup(s, x, y, items, title)
  s.popup = { x = x, y = y, items = items, title = title }
  s.menu = nil
  markDirty(s)
end

function K.windowMenu(w, s)
  local items = {
    { label = w.state == "max" and "Restore" or "Maximise", fn = function() K.toggleMax(w) end },
    { label = "Snap left", fn = function() K.snap(w, "left") end },
    { label = "Snap right", fn = function() K.snap(w, "right") end },
    { label = "Minimise", fn = function() K.minimize(w) end },
  }
  if s.touch and w.state == "normal" then
    items[#items + 1] = { label = "Move (tap a spot)", fn = function() K.moveMode = { win = w, screen = s } end }
  end
  for _, d in ipairs(desktops()) do
    if d ~= w.screen then
      items[#items + 1] = { label = "Move to " .. (d.kind == "term" and "computer" or d.name), fn = function() K.moveToScreen(w, d) end }
    end
  end
  items[#items + 1] = { label = "Close", color = T.danger, fn = function() K.closeWindow(w) end }
  K.popup(s, w.x + w.w - 4 * (s.touch and 5 or 3), w.y + 1, items, w.title)
end

function K.musicPopup(s, x)
  local info = audio.info()
  local items = {}
  if info.disc then
    items[#items + 1] = { label = "Stop the record", fn = function() audio.stopDisc() end }
  end
  if info.state ~= "stopped" then
    items[#items + 1] = { label = info.state == "playing" and "Pause" or "Play", fn = audio.toggle }
    items[#items + 1] = { label = "Next", fn = audio.next }
    items[#items + 1] = { label = "Previous", fn = audio.prev }
    items[#items + 1] = { label = "Stop", fn = audio.stop }
  end
  items[#items + 1] = { label = "Open Music", fn = function() K.launch("music", nil, { screen = s }) end }
  K.popup(s, x, nil, items, info.title or info.discTitle or "Music")
end

function K.volumePopup(s, x)
  local function pct() return floor((K.cfg.musicVolume or 0) * 100 + 0.5) .. "%" end
  local function bal()
    local b = floor((K.cfg.balance or 0) * 100 + 0.5)
    return b == 0 and "centre" or (b < 0 and (-b .. "% left") or (b .. "% right"))
  end
  local items
  items = {
    { label = "Louder (" .. pct() .. ")", stay = true, fn = function() audio.setVolume((K.cfg.musicVolume or 0) + 0.1); items[1].label = "Louder (" .. pct() .. ")"; items[2].label = "Quieter (" .. pct() .. ")" end },
    { label = "Quieter (" .. pct() .. ")", stay = true, fn = function() audio.setVolume((K.cfg.musicVolume or 0) - 0.1); items[1].label = "Louder (" .. pct() .. ")"; items[2].label = "Quieter (" .. pct() .. ")" end },
    { label = "Balance left", stay = true, fn = function() audio.setBalance((K.cfg.balance or 0) - 0.25); items[5].label = "Balance: " .. bal() end },
    { label = "Balance right", stay = true, fn = function() audio.setBalance((K.cfg.balance or 0) + 0.25); items[5].label = "Balance: " .. bal() end },
    { label = "Balance: " .. bal(), disabled = true },
    { label = (K.cfg.sounds and "Mute" or "Unmute") .. " system sounds", fn = function() K.cfg.sounds = not K.cfg.sounds; K.saveConfig() end },
    { label = "Test left speaker", stay = true, fn = function() audio.note("bell", 12, -1, 1.5) end },
    { label = "Test right speaker", stay = true, fn = function() audio.note("bell", 12, 1, 1.5) end },
  }
  K.popup(s, x, nil, items, "Sound")
end

function K.drivePopup(s, x, d)
  local items = {}
  if d.mount then
    items[#items + 1] = { label = "Open /" .. d.mount, fn = function() K.launch("files", { "/" .. d.mount }, { screen = s }) end }
  end
  if d.audio then
    items[#items + 1] = { label = "Play " .. trunc(d.audio, 24), fn = function() audio.playDisc(d.name) end }
    items[#items + 1] = { label = "Stop the record", fn = function() audio.stopDisc() end }
  end
  if d.mount then
    items[#items + 1] = { label = "Label...", fn = function()
      K.spawn(function()
        local text = K.api.prompt("Label the disk", "New label", d.label or "")
        if text then pcall(peripheral.call, d.name, "setDiskLabel", text ~= "" and text or nil); os.queueEvent("ccos_hw") end
      end, { title = "Label" })
    end }
  end
  items[#items + 1] = { label = "Eject", color = T.warn, fn = function()
    K.spawn(function() pcall(peripheral.call, d.name, "ejectDisk") end, { title = "Eject" })
  end }
  K.popup(s, x, nil, items, d.label or (d.audio and "Record") or "Disk")
end

function K.notificationPopup(s, x)
  K.unread = 0
  local items = {}
  for i = 1, min(10, #K.notifs) do
    local n = K.notifs[i]
    items[#items + 1] = { label = clock.format(K.cfg, false, floor(n.t / 1000)) .. " " .. trunc(n.title .. (n.text ~= "" and (": " .. n.text) or ""), 44),
      color = n.color, fn = n.action }
  end
  if #items == 0 then items[1] = { label = "Nothing new", disabled = true } end
  items[#items + 1] = { label = "Clear all", color = T.muted, fn = function() K.notifs = {}; K.toasts = {} end }
  K.popup(s, x, nil, items, "Notifications")
end

function K.toggleStart(s)
  if s.menu then s.menu = nil else s.menu = { search = "" }; s.popup = nil end
  markDirty(s)
end

function K.confirmPower(s, what)
  s.menu = nil
  local words = { exit = "Exit to CraftOS", reboot = "Restart the computer", shutdown = "Shut down the computer" }
  K.dialog({ screen = s, title = words[what] .. "?", text = "Open windows will close.", buttons = { "Cancel", words[what] },
    cb = function(i)
      if i == 2 then K.power = what; K.running = false end
    end })
end

local function drawDialog(s, d)
  local w = min(s.w - 4, 52)
  local lines = wrap(d.text, w - 4)
  local h = 3 + #lines + (d.field and 2 or 0) + 1
  local x, y = floor((s.w - w) / 2) + 1, max(1, floor((workHeight(s) - h) / 2))
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
  local bx = x + w - 1
  for i = #d.buttons, 1, -1 do
    local label = " " .. d.buttons[i] .. " "
    bx = bx - #label - 1
    local primary = i == #d.buttons
    local bh = s.touch and 1 or 1
    put(bx, yy, label, primary and T.bg or T.text, primary and T.accent or T.raised)
    local index = i
    hit(bx, yy - (bh - 1), bx + #label - 1, yy, function() answer(s, d, index) end)
  end
end

local function drawToasts(s)
  local tw = min(40, s.w - 4)
  local y = 2
  for _, t in ipairs(K.toasts) do
    local n = t.n
    local lines = n.text ~= "" and wrap(n.text, tw - 4) or {}
    local h = 2 + min(2, #lines)
    if y + h > workHeight(s) then break end
    local x = s.w - tw
    shade(x + 1, y + h, tw, 1)
    shade(x + tw, y + 1, 1, h)
    fill(x, y, tw, h, T.surface)
    fill(x, y, 1, h, n.color or T.accent)
    put(x + 2, y, trunc(n.title, tw - 6), T.text, T.surface)
    put(x + tw - 2, y, "\215", T.muted, T.surface)
    for i = 1, min(2, #lines) do put(x + 2, y + i, lines[i], T.muted, T.surface) end
    local toast = t
    hit(x, y, x + tw - 1, y + h - 1, function()
      for i, other in ipairs(K.toasts) do if other == toast then table.remove(K.toasts, i); break end end
      if n.action then n.action() end
    end)
    y = y + h + 1
  end
end

------------------------------------------------------------------------
-- The command palette
------------------------------------------------------------------------

local COMMANDS, CMD_ORDER = {}, {}

local function suggestions(text)
  local list = {}
  local first = text:match("^%s*(%S*)") or ""
  local lower = text:lower()
  if text == "" then
    for _, a in ipairs(visibleApps("")) do list[#list + 1] = { label = a.name, hint = a.desc or "", run = "open " .. a.id } end
    return list
  end
  for _, a in ipairs(visibleApps(lower)) do
    list[#list + 1] = { label = "Open " .. a.name, hint = a.desc or "", run = "open " .. a.id }
  end
  for _, n in ipairs(CMD_ORDER) do
    if n:find(first:lower(), 1, true) == 1 then
      local c = COMMANDS[n]
      list[#list + 1] = { label = c.usage, hint = c.desc, run = (first == n and text) or n, complete = n .. " " }
    end
  end
  if #list == 0 then list[1] = { label = "Run \"" .. text .. "\" in a terminal", hint = "shell command", run = "run " .. text } end
  return list
end

function K.togglePalette(s)
  if K.palette then
    K.palette = nil
  else
    K.palette = { screen = s or K.activeScreen(), text = "", sel = 1, out = {} }
  end
  markAll()
end

local function runPalette(line)
  local p = K.palette
  if not p or line:match("^%s*$") then return end
  p.out = { { "> " .. line, T.muted } }
  local out = function(text, color)
    for _, l in ipairs(wrap(tostring(text), 66)) do p.out[#p.out + 1] = { l, color or T.text } end
    if #p.out > 40 then table.remove(p.out, 2) end
    markDirty(p.screen)
  end
  local words = line:match("^%s*(%S+)")
  K.spawn(function()
    local ok, handled = pcall(K.exec, line, out, p.screen)
    if not ok then out(handled, T.danger) end
    if ok and handled == false then out("Unknown command. Try \"help\".", T.warn) end
    if K.palette == p and (words == "open" or words == "run") then K.palette = nil; markAll() end
  end, { title = "Command" })
  p.text, p.sel = "", 1
end

local function drawPalette(s)
  local p = K.palette
  local w = min(s.w - 4, 72)
  local x = floor((s.w - w) / 2) + 1
  local sug = suggestions(p.text)
  local shown = min(#sug, #p.out > 0 and 3 or 7)
  local outN = min(#p.out, max(0, workHeight(s) - 6 - shown))
  local h = 2 + shown + (outN > 0 and outN + 1 or 0) + 1
  local y = 2
  hit(1, 1, s.w, s.h, function() K.palette = nil; markAll() end)
  shade(x + 1, y + h, w, 1)
  shade(x + w, y + 1, 1, h)
  fill(x, y, w, h, T.surface)
  hit(x, y, x + w - 1, y + h - 1, function() end)
  fill(x, y, w, 1, T.raised)
  put(x + 1, y, "\16", T.accent, T.raised)
  local text = p.text
  if #text > w - 5 then text = text:sub(-(w - 5)) end
  put(x + 3, y, text ~= "" and text or "", T.text, T.raised)
  if p.text == "" then put(x + 3, y, "Type a command or an app name", T.muted, T.raised) end
  s.cursor = { x = x + 3 + #text, y = y, color = T.accent }
  p.sel = clamp(p.sel, 1, max(1, #sug))
  for i = 1, shown do
    local it = sug[i]
    local yy = y + 1 + i
    local sel = i == p.sel
    local bg = sel and T.select or T.surface
    fill(x, yy, w, 1, bg)
    put(x + 2, yy, trunc(it.label, floor(w * 0.45)), T.text, bg)
    put(x + floor(w * 0.45) + 3, yy, trunc(it.hint, w - floor(w * 0.45) - 5), sel and T.text or T.muted, bg)
    hit(x, yy, x + w - 1, yy, function() runPalette(it.run) end)
  end
  if outN > 0 then
    local oy = y + 2 + shown + 1
    for i = 1, outN do
      local line = p.out[#p.out - outN + i]
      put(x + 2, oy + i - 1, trunc(line[1], w - 4), line[2], T.surface)
    end
  end
  put(x + 2, y + h - 1, trunc("Enter run   Tab complete   Up/Down choose   Alt+Space close", w - 4), T.muted, T.surface)
end

local function paletteInput(ev)
  local p = K.palette
  local e = ev[1]
  if e == "char" then p.text = p.text .. ev[2]; p.sel = 1
  elseif e == "paste" then p.text = p.text .. ev[2]
  elseif e == "key" then
    local k = ev[2]
    local sug = suggestions(p.text)
    if k == keys.backspace then p.text = p.text:sub(1, -2); p.sel = 1
    elseif k == keys.enter then
      local it = sug[p.sel]
      if p.text ~= "" and not COMMANDS[p.text:match("^%s*(%S+)") or ""] and it then runPalette(it.run)
      elseif p.text == "" and it then runPalette(it.run)
      else runPalette(p.text) end
    elseif k == keys.tab then
      local it = sug[p.sel]
      if it then p.text = it.complete or it.run end
    elseif k == keys.up then p.sel = p.sel - 1
    elseif k == keys.down then p.sel = p.sel + 1
    end
  end
  markDirty(p.screen)
end

------------------------------------------------------------------------
-- The panel: a small monitor showing the time, music and devices
------------------------------------------------------------------------


local function bigClock(s, y, h)
  local t = clockText(false)
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
      put(2, y, clock.format(K.cfg, false, floor(n.t / 1000)), T.muted, T.bg)
      put(8, y, trunc(n.title .. (n.text ~= "" and (" - " .. n.text) or ""), s.w - 9), T.text, T.bg)
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
  elseif s.kind=="term" and K.pictureScreen()then
    inputConsole.draw(s,K.pictureScreen())
    local d=topDialog(s);if d and not d.field then drawDialog(s,d)end
  elseif s.role == "picture" then
    picture.draw(s)
    local d = topDialog(s); if d then drawDialog(s,d) end
  else
    drawWall(s)
    drawIcons(s)
    for _, w in ipairs(wins) do
      if w.screen == s and w.state ~= "min" then drawWindow(s, w) end
    end
    drawTaskbar(s)
    -- Keep active app controls clear; unread notifications remain in the tray.
    if not K.focus or K.focus.screen~=s or K.focus.state=="min"then drawToasts(s)end
    if s.menu then drawStartMenu(s) end
    if s.popup then drawPopup(s) end
    if K.palette and K.palette.screen == s then drawPalette(s) end
    local d = topDialog(s)
    if d then drawDialog(s, d) end
    if K.moveMode and K.moveMode.screen == s then
      local msg = " Tap where the window's corner should go "
      put(floor((s.w - #msg) / 2) + 1, 1, msg, T.bg, T.warn)
    end
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
  if not cur and not K.booting and not K.saver and s.role == "desktop" and not(s.kind=="term"and K.pictureScreen())and not s.menu and not s.popup
    and not topDialog(s) and not (K.palette and K.palette.screen == s) then
    local w = K.focus
    if w and w.screen == s and w.state ~= "min" and w.buf.getCursorBlink and w.buf.getCursorBlink() then
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

-- A mirror shows the computer's screen centred on a monitor, framed by
-- the wallpaper; taps on it are clicks on the computer (see dispatch).
local function presentMirror(m, src)
  m.dirty = false
  local ox, oy = max(0, floor((m.w - src.w) / 2)), max(0, floor((m.h - src.h) / 2))
  m.ox, m.oy = ox, oy
  local key = "mirror" .. K.cfg.wallpaper .. m.w .. "x" .. m.h
  if m.wallKey ~= key then
    m.wall, m.wallKey = gfx.wallpaper(K.cfg.wallpaper, m.w, m.h), key
    -- a dark edge between the margins and the mirrored screen
    for y = 1, m.h do
      local r = m.wall[y]
      for _, x in ipairs({ ox, ox + src.w + 1 }) do
        if x >= 1 and x <= m.w then
          r[1] = r[1]:sub(1, x - 1) .. " " .. r[1]:sub(x + 1)
          r[3] = r[3]:sub(1, x - 1) .. "f" .. r[3]:sub(x + 1)
        end
      end
    end
  end
  local tgt, cache = m.target, m.cache
  local n = min(src.w, m.w - ox)
  for y = 1, m.h do
    local wt, wf, wb = m.wall[y][1], m.wall[y][2], m.wall[y][3]
    local sy = y - oy
    local t, f, b = wt, wf, wb
    if sy >= 1 and sy <= src.h then
      local st, sf, sb = src.buf.getLine(sy)
      t = wt:sub(1, ox) .. st:sub(1, n) .. wt:sub(ox + n + 1)
      f = wf:sub(1, ox) .. sf:sub(1, n) .. wf:sub(ox + n + 1)
      b = wb:sub(1, ox) .. sb:sub(1, n) .. wb:sub(ox + n + 1)
    end
    local c = cache[y]
    if not c or c[1] ~= t or c[2] ~= f or c[3] ~= b then
      tgt.setCursorPos(1, y)
      tgt.blit(t, f, b)
      cache[y] = { t, f, b }
    end
  end
  local cur = src.lastCursor
  if cur and cur.x <= n then
    tgt.setCursorPos(ox + cur.x, oy + cur.y)
    tgt.setTextColor(cur.color)
    tgt.setCursorBlink(true)
  else
    tgt.setCursorBlink(false)
  end
end

local function render()
  local home = screenByName.term
  for _, s in ipairs(screens) do
    if s.role == "mirror" and s.dirty then home.dirty = true end
  end
  for _, s in ipairs(screens) do
    if s.dirty and s.role ~= "off" and s.role ~= "mirror" then
      s.dirty = false
      local ok, err = pcall(compose, s)
      if not ok then
        -- Usually a monitor removed mid-frame; peripheral events rebuild.
        logCrash({ title = "render " .. s.name }, err)
      end
      if s == home then
        for _, m in ipairs(screens) do
          if m.role == "mirror" then
            local okM, errM = pcall(presentMirror, m, s)
            if not okM then logCrash({ title = "mirror " .. m.name }, errM) end
          end
        end
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

local function dragTo(x, y)
  local d = K.drag
  local w = d.win
  if d.kind == "move" then
    if w.state ~= "normal" then
      w.state = "normal"
      w.w, w.h = w.normalW or w.w, w.normalH or w.h
      d.dx = min(d.dx, w.w - 1)
    end
    w.x, w.y = x - d.dx, max(1, y - d.dy)
  else
    w.w, w.h = max(12, x - w.x), max(3, y - w.y - 1)
    w.normalW, w.normalH = w.w, w.h
  end
  layout(w)
end

local function pointer(s, kind, btn, x, y)
  K.lastScreen = s
  if wakeSaver() or K.booting then return end
  if kind == "drag" then
    if K.drag then dragTo(x, y)
    elseif capture then
      local w = capture.win
      post(w.proc, { "mouse_drag", btn, x - w.x + 1, y - w.y, n = 4 })
    end
    return
  elseif kind == "up" then
    if K.drag then K.drag = nil; markDirty(s)
    elseif capture then
      local w = capture.win
      post(w.proc, { "mouse_up", btn, x - w.x + 1, y - w.y, n = 4 })
      capture = nil
    end
    return
  end
  if K.moveMode and kind ~= "scroll" then
    local w = K.moveMode.win
    K.moveMode = nil
    if w.screen == s and not w.proc.dead then
      w.state = "normal"
      w.x, w.y = x, y
      layout(w)
    end
    markDirty(s)
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

local function shortcut(k)
  local w = K.keyTarget()
  if k == keys.space then K.togglePalette(screenByName.term)
  elseif k == keys.tab then K.cycleFocus()
  elseif k == keys.enter or k == keys.up then if w then K.toggleMax(w) end
  elseif k == keys.down then if w then K.minimize(w) end
  elseif k == keys.left then if w then K.snap(w, "left") end
  elseif k == keys.right then if w then K.snap(w, "right") end
  elseif k == keys.q then if w then K.closeWindow(w) end
  elseif k == keys.m then if w then K.moveToNextScreen(w) end
  elseif k == keys.a then K.launch("agent", nil, { screen = screenByName.term })
  elseif k == keys.t then K.launch("terminal", nil, { screen = screenByName.term })
  elseif k == keys.f then K.launch("files", nil, { screen = screenByName.term })
  elseif k == keys.s then K.toggleStart(screenByName.term)
  else return false end
  return true
end

local function dialogInput(s, d, ev)
  local e = ev[1]
  if e == "char" or e == "paste" then
    d.field.text = (d.field.text .. ev[2]):sub(1, d.field.secret and 1024 or 12000)
  elseif e == "key" then
    if ev[2] == keys.backspace then d.field.text = d.field.text:sub(1, -2)
    elseif ev[2] == keys.enter then answer(s, d, #d.buttons) end
  end
  markDirty(s)
end

local function keyboard(ev)
  local e = ev[1]
  if e == "key" then held[ev[2]] = true elseif e == "key_up" then held[ev[2]] = nil end
  if e ~= "key_up" and wakeSaver() then return end
  if K.booting then return end
  local alt = held[keys.leftAlt] or held[keys.rightAlt]
  local pictureTarget=K.pictureScreen()
  if pictureTarget then
    if e=="key"and((alt and ev[2]==keys.a)or ev[2]==keys.f1)then K.launch("agent",{},{screen=pictureTarget});return end
    for _,ss in ipairs(screens)do local dialog=topDialog(ss);if dialog and not dialog.field then
      if e=="key"and ev[2]==keys.enter then answer(ss,dialog,dialog.enterChoice or 1)end
      return
    end end
    inputConsole.keyboard(ev,pictureTarget);return
  end
  if e == "key" and ev[2] == keys.f1 then K.launch("agent", nil, {screen=screenByName.term}); return end
  if alt and e == "key" and shortcut(ev[2]) then markAll(); return end
  if alt and e == "char" then return end
  if K.palette and e ~= "key_up" then paletteInput(ev); return end
  for _, s in ipairs(screens) do
    local d = topDialog(s)
    if d and e ~= "key_up" then
      if d.field then dialogInput(s, d, ev)
      elseif e == "key" and ev[2] == keys.enter then answer(s, d, d.enterChoice or #d.buttons) end
      return
    end
  end
  for _, s in ipairs(screens) do
    if s.menu and e ~= "key_up" then
      if e == "char" then s.menu.search = s.menu.search .. ev[2]
      elseif e == "key" and ev[2] == keys.backspace then s.menu.search = s.menu.search:sub(1, -2)
      elseif e == "key" and ev[2] == keys.enter then
        local first = visibleApps(s.menu.search)[1]
        if first then s.menu = nil; K.launch(first.id, nil, { screen = s }) end
      end
      markDirty(s)
      return
    end
  end
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
  if s.role=="picture"and ({files=true,music=true,settings=true,notifications=true,devices=true})[id]then
    s.picture=s.picture or {page=1,path="/",category="Favorites"};s.picture.view=id;s.picture.page=1
    if id=="files"and args[1]then s.picture.path=args[1]end
    markDirty(s);return {id=0,virtual=true}
  end
  if s.role == "picture" and not K.canTouchApp(app,s) then
    K.dialog({screen=s,title="Open desktop tool?",text=app.name.." needs the desktop. Switch to Full Sync?",buttons={"Cancel","Full Sync"},cb=function(i)if i==2 then K.setFullSync(true);K.launch(id,args,{screen=screenByName.term})end end})
    return nil,"Full Sync required"

  elseif s.role ~= "desktop" and s.role ~= "picture" then s = K.homeScreen() end
  if s.role == "picture" and app.touch then s.picture=s.picture or {page=1,path="/",category="Favorites"};s.picture.view=id end
  if id=="agent"then
    for _,w in ipairs(wins)do if w.app and w.app.id==id and w.screen==s and not w.proc.dead then K.focusWindow(w);if s.role=="picture"then s.picture.appPid=w.id end;return w.proc end end
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
  if s.role=="picture" then s.picture.appPid=p.id;markDirty(screenByName.term)end
  K.sfx("open")
  return p
end

-- A shell command in a new terminal window that stays open afterwards.
function K.runCommand(line, s)
  local app = appById("terminal")
  return K.spawn(function()
    local ok = rootShell.run(line)
    waitToClose(ok)
  end, { title = trunc(line, 30), app = app, window = { screen = s or K.activeScreen(), w = app.w, h = app.h } })
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
-- Commands, for the shell (in /ccos/bin) and the palette
------------------------------------------------------------------------

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
command("theme", "theme [name]", "Show or change the theme", function(a, out)
  if a[1] then
    if not THEMES[a[1]] then error("Themes: " .. table.concat(THEME_ORDER, ", "), 0) end
    API.config("theme", a[1])
  end
  out("Theme " .. K.cfg.theme .. " (" .. table.concat(THEME_ORDER, ", ") .. ")")
end)
command("wallpaper", "wallpaper [name]", "Show or change the wallpaper", function(a, out)
  if a[1] then API.config("wallpaper", a[1]) end
  out("Wallpaper " .. K.cfg.wallpaper .. " (" .. table.concat(gfx.WALLPAPERS, ", ") .. ")")
end)
command("screens", "screens", "List the displays", function(_, out)
  for _, s in ipairs(screens) do
    local scale = s.kind == "monitor" and s.target.getTextScale and (" scale " .. s.target.getTextScale()) or ""
    out(padR(s.name, 12) .. padR(s.role, 9) .. (s.w or 0) .. "x" .. (s.h or 0) .. scale)
  end
end)
command("screen", "screen <name> <picture|desktop|mirror|panel|off> [scale]", "Set what a monitor shows", function(a, out)
  local name, role = a[1], a[2]
  if not name or not (role == "picture" or role == "desktop" or role == "mirror" or role == "panel" or role == "off") then
    error("Usage: screen <name> <picture|desktop|mirror|panel|off> [scale]", 0)
  end
  if name == "term" then error("The computer's own screen is always a desktop", 0) end
  local conf = K.cfg.screens[name] or {}
  conf.role = role
  if name==K.primaryMonitorName then K.cfg.fullSync=role=="mirror"end
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
  if #a>0 then local ok,err=K.agent.start(table.concat(a," ")); if not ok then out(err,T.warn)end end
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
    rootShell.setCompletionFunction("ccos/bin/theme.lua", complete.build({ complete.choice, THEME_ORDER }))
    rootShell.setCompletionFunction("ccos/bin/wallpaper.lua", complete.build({ complete.choice, gfx.WALLPAPERS }))
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
-- Whether the last tap or click came from a monitor.
function API.touchInput() return K.lastTouch == true end
function API.pictureScreenName()local s=K.pictureScreen();return s and s.name end
function API.setFullSync(on)return K.setFullSync(on)end
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
  local booleans={clock24=true,seconds=true,leadingZero=true,sounds=true,touchSounds=true,shadows=true,swapSpeakers=true,agentConfirm=true,fullSync=true,autoUpdates=true}
  if booleans[key] then return type(value)=="boolean", "Expected a boolean" end
  if key=="timezone" then return type(value)=="string" and clock.valid(value), "Unsupported time zone" end
  if key=="theme" then return type(value)=="string" and THEMES[value]~=nil, "Unknown theme" end
  if key=="wallpaper" then for _,v in ipairs(gfx.WALLPAPERS)do if value==v then return true end end;return false,"Unknown wallpaper" end
  if key=="user" then return type(value)=="string" and #value>0 and #value<=40,"Name must be 1-40 characters" end
  if key=="agentModel" then return type(value)=="string" and #value<=160 and value:match("^[%w%._:/~%-]+$")~=nil,"Invalid model id" end
  local ranges={utcOffset={-720,840},musicVolume={0,1},uiVolume={0,1},balance={-1,1},idle={0,86400},panelRotate={4,3600},agentMaxSteps={1,40},agentMaxTokens={256,8192}}
  if ranges[key]then local r=ranges[key];return type(value)=="number" and value==value and value>=r[1] and value<=r[2],"Value out of range" end
  return false,"Setting cannot be changed through this interface"
end
function API.config(key, value)
  if value == nil then return K.cfg[key] end
  if key=="fullSync"then return K.setFullSync(value)end
  K.cfg[key] = value
  K.saveConfig()
  if key == "theme" then
    for _, s in ipairs(screens) do if s.role ~= "off" then applyPalette(s.target); s.cache = {} end end
    os.queueEvent("ccos_theme")
  elseif key == "wallpaper" then
    for _, s in ipairs(screens) do s.wallKey = nil end
  elseif key == "swapSpeakers" then
    audio.detect()
  elseif key=="autoUpdates"and value and K.updates then K.updates.check(false)
  elseif key == "screens" then
    K.buildScreens()
  end
  markAll()
end
function API.themes() return THEME_ORDER, THEMES end
function API.wallpapers() return gfx.WALLPAPERS end
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
  if role then conf.role = role;if name==K.primaryMonitorName then K.cfg.fullSync=role=="mirror"end end
  if scale then conf.scale = scale end
  K.cfg.screens[name] = conf
  K.saveConfig()
  K.buildScreens()
end
function API.hw() return K.hw end
function API.recent() return K.cfg.recent end
function API.addRecent(path) K.addRecent(path) end
function API.desktopApps() return K.cfg.desktop end
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
    K.notify(greeting() .. ", " .. K.cfg.user, "ccOS is ready. Alt+Space opens the command palette.", { icon = "about", quiet = true, silent = true })
  end
  local changed = false
  for i = #K.toasts, 1, -1 do
    if K.toasts[i].untilT < t then table.remove(K.toasts, i); changed = true end
  end
  if changed then markAll() end
  local minute = clockText(false)
  if minute ~= K.lastMinute or K.cfg.seconds then
    K.lastMinute = minute
    for _, s in ipairs(screens) do if s.role == "desktop" then markDirty(s) end end
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
    if s and s.role == "mirror" then
      local home = screenByName.term
      local x, y = ev[3] - (s.ox or 0), ev[4] - (s.oy or 0)
      if x >= 1 and y >= 1 and x <= home.w and y <= home.h then pointer(home, "touch", 1, x, y) end
    elseif s and s.role ~= "off" then
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
      setupScreen(s)
      for _, w in ipairs(wins) do if w.screen == s then layout(w) end end
    end
    broadcast(ev)
  elseif e == "term_resize" then
    local s = screenByName.term
    setupScreen(s)
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
