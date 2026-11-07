-- A headless CC: Tweaked for running ccOS on a desktop.
--   lua harness.lua <src dir> <scenario> [html out]
-- Mocks term/window, an in-memory filesystem, monitors, speakers, a printer,
-- a disk drive and a modem, drives a virtual clock and scripted input, and
-- writes every captured screen to an HTML page drawn with the real palette.
local SRC, SCENARIO, HTML = arg[1], arg[2] or "home", arg[3]
local realOs, realPrint, realLoad = os, print, load
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local function log(...) io.stdout:write(table.concat({ ... }, " "), "\n") end
local FAIL = {}
local function fail(msg) FAIL[#FAIL + 1] = msg; io.stderr:write("FAIL: ", msg, "\n") end

---------------------------------------------------------------- colours
colors = { white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32, pink = 64,
  gray = 128, lightGray = 256, cyan = 512, purple = 1024, blue = 2048, brown = 4096, green = 8192,
  red = 16384, black = 32768 }
colours = colors
local HEXOF, COLOF = {}, {}
for i = 0, 15 do
  local h = ("0123456789abcdef"):sub(i + 1, i + 1)
  HEXOF[floor(2 ^ i)], COLOF[h] = h, floor(2 ^ i)
end
local function hexOf(c)
  local h = HEXOF[c]
  if not h then error("bad colour: " .. tostring(c), 3) end
  return h
end
local DEFAULT_PAL = { 0xF0F0F0, 0xF2B233, 0xE57FD8, 0x99B2F2, 0xDEDE6C, 0x7FCC19, 0xF2B2CC, 0x4C4C4C,
  0x999999, 0x4C99B2, 0xB266E5, 0x3366CC, 0x7F664C, 0x57A64E, 0xCC4C4C, 0x111111 }

---------------------------------------------------------------- terminals and windows
-- One implementation for the computer, monitors and windows.
local function makeTerm(w, h, opts)
  opts = opts or {}
  local t = { w = w, h = h, cx = 1, cy = 1, fg = "0", bg = "f", blink = false, text = {}, fgs = {}, bgs = {}, pal = {} }
  for i = 1, 16 do t.pal[i] = DEFAULT_PAL[i] end
  local o = { _t = t }
  local function blankRow() return (" "):rep(t.w), t.fg:rep(t.w), t.bg:rep(t.w) end
  for y = 1, t.h do t.text[y], t.fgs[y], t.bgs[y] = blankRow() end
  local function writeAt(s, f, b)
    local y = t.cy
    if y >= 1 and y <= t.h and #s > 0 then
      local x0 = t.cx
      local a, z = max(1, x0), min(t.w, x0 + #s - 1)
      if a <= z then
        local i0, i1 = a - x0 + 1, z - x0 + 1
        t.text[y] = t.text[y]:sub(1, a - 1) .. s:sub(i0, i1) .. t.text[y]:sub(z + 1)
        t.fgs[y] = t.fgs[y]:sub(1, a - 1) .. f:sub(i0, i1) .. t.fgs[y]:sub(z + 1)
        t.bgs[y] = t.bgs[y]:sub(1, a - 1) .. b:sub(i0, i1) .. t.bgs[y]:sub(z + 1)
      end
    end
    t.cx = t.cx + #s
  end
  function o.getSize() return t.w, t.h end
  function o.setCursorPos(x, y)
    assert(type(x) == "number" and type(y) == "number", "setCursorPos: numbers expected")
    t.cx, t.cy = floor(x), floor(y)
  end
  function o.getCursorPos() return t.cx, t.cy end
  function o.setCursorBlink(b) t.blink = b and true or false end
  function o.getCursorBlink() return t.blink end
  function o.setTextColor(c) t.fg = hexOf(c) end
  function o.setBackgroundColor(c) t.bg = hexOf(c) end
  function o.getTextColor() return COLOF[t.fg] end
  function o.getBackgroundColor() return COLOF[t.bg] end
  o.setTextColour, o.setBackgroundColour, o.getTextColour, o.getBackgroundColour =
    o.setTextColor, o.setBackgroundColor, o.getTextColor, o.getBackgroundColor
  function o.write(s)
    if type(s) ~= "string" and type(s) ~= "number" then error("bad argument #1 to 'write' (string expected, got " .. type(s) .. ")", 2) end
    s = tostring(s)
    writeAt(s, t.fg:rep(#s), t.bg:rep(#s))
  end
  function o.blit(s, f, b)
    if type(s) ~= "string" or type(f) ~= "string" or type(b) ~= "string" then error("blit: strings expected", 2) end
    if #s ~= #f or #f ~= #b then error(("Arguments must be the same length (%d, %d, %d)"):format(#s, #f, #b), 2) end
    if f:find("[^0-9a-fA-F]") or b:find("[^0-9a-fA-F]") then error("blit: bad colour", 2) end
    writeAt(s, f:lower(), b:lower())
  end
  function o.clear() for y = 1, t.h do t.text[y], t.fgs[y], t.bgs[y] = blankRow() end end
  function o.clearLine()
    if t.cy >= 1 and t.cy <= t.h then t.text[t.cy], t.fgs[t.cy], t.bgs[t.cy] = blankRow() end
  end
  function o.scroll(n)
    n = floor(n)
    local T, F, B = {}, {}, {}
    for y = 1, t.h do
      local src = y + n
      if src >= 1 and src <= t.h then T[y], F[y], B[y] = t.text[src], t.fgs[src], t.bgs[src]
      else T[y], F[y], B[y] = blankRow() end
    end
    t.text, t.fgs, t.bgs = T, F, B
  end
  function o.isColor() return opts.color ~= false end
  o.isColour = o.isColor
  function o.getLine(y)
    if y < 1 or y > t.h then error("Line is out of range.", 2) end
    return t.text[y], t.fgs[y], t.bgs[y]
  end
  function o.setPaletteColour(c, r, g, b)
    local i = math.log(c, 2) + 1
    if g then t.pal[floor(i + 0.5)] = floor(r * 255) * 65536 + floor(g * 255) * 256 + floor(b * 255)
    else t.pal[floor(i + 0.5)] = r end
  end
  o.setPaletteColor = o.setPaletteColour
  function o.getPaletteColour(c)
    local v = t.pal[floor(math.log(c, 2) + 1.5)]
    return floor(v / 65536) / 255, floor(v / 256) % 256 / 255, v % 256 / 255
  end
  o.getPaletteColor = o.getPaletteColour
  function o.resize(nw, nh)
    for y = 1, nh do
      local r, f, b = t.text[y], t.fgs[y], t.bgs[y]
      if not r then r, f, b = (" "):rep(nw), t.fg:rep(nw), t.bg:rep(nw)
      elseif #r < nw then r, f, b = r .. (" "):rep(nw - #r), f .. t.fg:rep(nw - #f), b .. t.bg:rep(nw - #b)
      else r, f, b = r:sub(1, nw), f:sub(1, nw), b:sub(1, nw) end
      t.text[y], t.fgs[y], t.bgs[y] = r, f, b
    end
    for y = nh + 1, #t.text do t.text[y], t.fgs[y], t.bgs[y] = nil, nil, nil end
    t.w, t.h = nw, nh
  end
  -- window-only methods
  function o.reposition(x, y, nw, nh)
    if nw and nh then o.resize(nw, nh) end
  end
  function o.setVisible() end
  function o.isVisible() return false end
  function o.redraw() end
  function o.restoreCursor() end
  function o.getPosition() return 1, 1 end
  return o
end

local computer = makeTerm(51, 19)
local current = computer
term = {}
function term.current() return current end
function term.native() return computer end
function term.redirect(target)
  assert(type(target) == "table", "redirect target")
  for _, k in ipairs({ "write", "blit", "setCursorPos", "getSize", "setTextColor", "setBackgroundColor", "clear" }) do
    if type(target[k]) ~= "function" then error("Redirect object is missing method " .. k, 2) end
  end
  local old = current
  current = target
  return old
end
function term.nativePaletteColour(c)
  local v = DEFAULT_PAL[floor(math.log(c, 2) + 1.5)]
  return floor(v / 65536) / 255, floor(v / 256) % 256 / 255, v % 256 / 255
end
for _, k in ipairs({ "write", "blit", "clear", "clearLine", "getCursorPos", "setCursorPos", "setCursorBlink", "getCursorBlink",
  "isColor", "isColour", "getSize", "scroll", "setTextColor", "setTextColour", "getTextColor", "getTextColour",
  "setBackgroundColor", "setBackgroundColour", "getBackgroundColor", "getBackgroundColour",
  "setPaletteColour", "setPaletteColor", "getPaletteColour", "getPaletteColor" }) do
  term[k] = function(...) return current[k](...) end
end

window = {}
function window.create(parent, x, y, w, h, visible)
  assert(type(parent) == "table", "window.create: parent")
  return makeTerm(w, h)
end

---------------------------------------------------------------- clock and events
local queue, timers, nextTimer = {}, {}, 1
local tick, epochMs = 0, 1793980800000
local dayTime = 1000
local function push(...) queue[#queue + 1] = table.pack(...) end
local later = {}
local function at(t, fn) later[t] = later[t] or {}; table.insert(later[t], fn) end

os = {}
function os.epoch(kind)
  if kind == "utc" then return epochMs end
  if kind == "local" then return epochMs + 3600000 end
  return floor(dayTime * 3600)
end
function os.clock() return tick * 0.05 end
function os.startTimer(sec)
  assert(type(sec) == "number", "startTimer: number expected")
  local id = nextTimer
  nextTimer = nextTimer + 1
  timers[id] = tick + max(1, ceil(sec / 0.05 - 1e-9))
  return id
end
function os.cancelTimer(id) timers[id] = nil end
function os.queueEvent(...) push(...) end
function os.pullEventRaw(f) return coroutine.yield(f) end
function os.pullEvent(f)
  local ev = table.pack(coroutine.yield(f))
  if ev[1] == "terminate" then error("Terminated", 0) end
  return table.unpack(ev, 1, ev.n)
end
function os.sleep(s)
  local id = os.startTimer(s or 0)
  repeat local _, p = os.pullEvent("timer") until p == id
end
sleep = os.sleep
function os.time() return (dayTime + 6000) % 24000 / 1000.0 end
function os.day() return floor((dayTime + 6000) / 24000) + 1 end
function os.date(fmt, t) return realOs.date(fmt, t or floor(epochMs/1000)) end
function os.getComputerID() return 12 end
function os.getComputerLabel() return "Home" end
local powered = nil
function os.reboot() powered = "reboot"; error("REBOOT", 0) end
function os.shutdown() powered = "shutdown"; error("SHUTDOWN", 0) end
function os.version() return "CraftOS 1.9" end

---------------------------------------------------------------- filesystem
local root = { dir = true, kids = {} }
local function parts(p)
  local out = {}
  for part in tostring(p):gmatch("[^/\\]+") do
    if part == ".." then table.remove(out) elseif part ~= "." then out[#out + 1] = part end
  end
  return out
end
local function node(p, create)
  local n = root
  for _, part in ipairs(parts(p)) do
    if not n.dir then return nil end
    local k = n.kids[part]
    if not k then
      if not create then return nil end
      k = { dir = true, kids = {} }
      n.kids[part] = k
    end
    n = k
  end
  return n
end
local function parentAndName(p)
  local ps = parts(p)
  local name = table.remove(ps)
  return node(table.concat(ps, "/"), false), name, table.concat(ps, "/")
end
local function usedBytes(n)
  if not n.dir then return #n.data end
  local s = 0
  for _, k in pairs(n.kids) do s = s + usedBytes(k) end
  return s
end
local mounts = { rom = "rom", disk = "disk" }

fs = {}
function fs.combine(a, ...)
  local s = tostring(a)
  for _, b in ipairs({ ... }) do s = s .. "/" .. tostring(b) end
  return table.concat(parts(s), "/")
end
function fs.getName(p) local ps = parts(p); return ps[#ps] or "root" end
function fs.getDir(p)
  local ps = parts(p)
  if #ps == 0 then return ".." end
  table.remove(ps)
  return table.concat(ps, "/")
end
function fs.exists(p) return node(p) ~= nil end
function fs.isDir(p) local n = node(p); return n ~= nil and n.dir == true end
function fs.isReadOnly(p) return parts(p)[1] == "rom" end
function fs.getDrive(p)
  local first = parts(p)[1]
  if not node(p) then return nil end
  return mounts[first or ""] or "hdd"
end
function fs.list(p)
  local n = node(p)
  if not n or not n.dir then error("/" .. fs.combine(p) .. ": Not a directory", 2) end
  local out = {}
  for k in pairs(n.kids) do out[#out + 1] = k end
  table.sort(out)
  return out
end
function fs.getSize(p)
  local n = node(p)
  if not n then error("/" .. fs.combine(p) .. ": No such file", 2) end
  return n.dir and 0 or #n.data
end
function fs.getCapacity() return 1000000 end
function fs.getFreeSpace() return 1000000 - usedBytes(root) end
function fs.makeDir(p)
  if fs.isReadOnly(p) then error("Access denied", 2) end
  node(p, true)
end
function fs.delete(p)
  if fs.isReadOnly(p) then error("Access denied", 2) end
  local parent, name = parentAndName(p)
  if parent and parent.kids then parent.kids[name] = nil end
end
local function deep(n)
  if not n.dir then return { data = n.data } end
  local c = { dir = true, kids = {} }
  for k, v in pairs(n.kids) do c.kids[k] = deep(v) end
  return c
end
function fs.copy(a, b)
  local n = node(a)
  if not n then error("No such file", 2) end
  if fs.exists(b) then error("File exists", 2) end
  local parent, name, dir = parentAndName(b)
  parent = node(dir, true)
  parent.kids[name] = deep(n)
end
function fs.move(a, b)
  if fs.isReadOnly(a) then error("Access denied", 2) end
  fs.copy(a, b)
  fs.delete(a)
end
function fs.open(p, mode)
  local readMode = mode == "r" or mode == "rb"
  if readMode then
    local n = node(p)
    if not n or n.dir then return nil, "/" .. fs.combine(p) .. ": No such file" end
    local data, pos = n.data, 1
    local h = {}
    function h.readAll() local s = data:sub(pos); pos = #data + 1; return s end
    function h.readLine()
      if pos > #data then return nil end
      local e = data:find("\n", pos, true)
      local line = data:sub(pos, (e or #data + 1) - 1)
      pos = (e or #data) + 1
      return line
    end
    function h.read(count)
      if pos > #data then return nil end
      if mode == "rb" and count == nil then local b = data:byte(pos); pos = pos + 1; return b end
      count = count or 1
      local s = data:sub(pos, pos + count - 1)
      pos = pos + count
      return s
    end
    function h.seek(whence, off)
      whence, off = whence or "cur", off or 0
      if whence == "set" then pos = off + 1 elseif whence == "end" then pos = #data + off + 1 else pos = pos + off end
      return pos - 1
    end
    function h.close() end
    return h
  end
  if fs.isReadOnly(p) then return nil, "Access denied" end
  local parent, name, dir = parentAndName(p)
  parent = node(dir, true)
  local n = parent.kids[name]
  if not n or n.dir then n = { data = "" }; parent.kids[name] = n end
  if mode == "w" or mode == "wb" then n.data = "" end
  local h = {}
  function h.write(s) n.data = n.data .. (type(s) == "number" and string.char(s) or tostring(s)) end
  function h.writeLine(s) n.data = n.data .. tostring(s) .. "\n" end
  function h.flush() end
  function h.close() end
  return h
end
local function writeFile(p, data)
  local parent, name, dir = parentAndName(p)
  parent = node(dir, true)
  parent.kids[name] = { data = data }
end

-- Copy ccOS's sources in.
local function readReal(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end
local SOURCE_FILES = { "ccos/apps/about.lua", "ccos/apps/agent.lua", "ccos/apps/calc.lua", "ccos/apps/clock.lua", "ccos/apps/files.lua", "ccos/apps/music.lua", "ccos/apps/notifications.lua", "ccos/apps/piano.lua", "ccos/apps/print.lua", "ccos/apps/settings.lua", "ccos/apps/tasks.lua", "ccos/apps/tools.lua", "ccos/apps/viewer.lua", "ccos/kernel.lua", "ccos/lib/agent.lua", "ccos/lib/audio.lua", "ccos/lib/catalog.lua", "ccos/lib/gfx.lua", "ccos/lib/json.lua", "ccos/lib/picture.lua", "ccos/lib/suite.lua", "ccos/lib/time.lua", "ccos/lib/ui.lua", "ccos/setup.lua" }
for _, rel in ipairs(SOURCE_FILES) do
  local s = readReal(SRC .. "/" .. rel)
  if not s then error("missing " .. rel) end
  writeFile(rel, s)
end

-- Stand-ins for ROM programs.
writeFile("rom/programs/shell.lua", [[
local parent = shell
term.setTextColor(colors.yellow)
print("CraftOS 1.9 (harness)")
while true do
  term.setTextColor(colors.yellow)
  write(shell.dir() .. "> ")
  term.setTextColor(colors.white)
  local line = read()
  if line == "exit" then return end
  if line ~= "" then parent.run(line) end
end
]])
writeFile("rom/programs/edit.lua", [[
local path = ...
term.clear(); term.setCursorPos(1, 1)
print("edit " .. tostring(path))
local h = fs.open(shell.resolve(path or ""), "r")
if h then for i = 1, 10 do local l = h.readLine(); if not l then break end; print(l) end; h.close() end
term.setCursorBlink(true)
while true do os.pullEvent("key") end
]])
writeFile("rom/programs/lua.lua", "print('Lua prompt (harness)') while true do os.pullEvent() end")
writeFile("rom/programs/fun/worm.lua", "print('worm (harness)') while true do os.pullEvent() end")
writeFile("rom/programs/fun/advanced/paint.lua", "print('paint (harness)') while true do os.pullEvent() end")
writeFile("rom/programs/hello.lua", "print('Hello, world!')")

-- Music: a mono DFPWM, a stereo pair, a WAV and a mixtape disk.
local function bytes(n, seed)
  local t = {}
  for i = 1, n do t[i] = string.char((i * 37 + seed) % 256) end
  return table.concat(t)
end
writeFile("music/ccOS Theme.dfpwm", bytes(12000, 1))
writeFile("music/Duet.l.dfpwm", bytes(9000, 2))
writeFile("music/Duet.r.dfpwm", bytes(9000, 3))
local function le16(v) return string.char(v % 256, floor(v / 256) % 256) end
local function le32(v) return le16(v % 65536) .. le16(floor(v / 65536)) end
do
  local frames = 22050
  local pcm = {}
  for i = 1, frames do
    local l = floor(math.sin(i / 20) * 12000) % 65536
    local r = floor(math.sin(i / 13) * 12000) % 65536
    pcm[#pcm + 1] = le16(l) .. le16(r)
  end
  local data = table.concat(pcm)
  local fmt = le16(1) .. le16(2) .. le32(22050) .. le32(22050 * 4) .. le16(4) .. le16(16)
  writeFile("music/Chord.wav", "RIFF" .. le32(36 + #data) .. "WAVE" .. "fmt " .. le32(16) .. fmt .. "data" .. le32(#data) .. data)
end
writeFile("disk/Mixtape Song.dfpwm", bytes(6000, 9))
writeFile("notes/todo.txt", "Feed the cats\nCraft more paper for the printer\nBuild the stereo speakers left and right\n")
writeFile("programs/hello.lua", "-- a greeting\nlocal name = ...\nprint(\"Hello, \" .. (name or \"world\"))\nfor i = 1, 3 do\n  print(i * 2) -- doubled\nend\n")

loadfile = function(path, mode, env)
  local n = node(path)
  if not n or n.dir then return nil, "File not found: " .. path end
  return realLoad(n.data, "@/" .. fs.combine(path), "t", env or _G)
end
dofile = function(path) return assert(loadfile(path))() end

---------------------------------------------------------------- text output and input, like CraftOS
function write(s)
  s = tostring(s)
  local t = term.current()
  local w, h = t.getSize()
  local x, y = t.getCursorPos()
  local lines = 0
  local function newline()
    if y + 1 <= h then y = y + 1 else t.scroll(1) end
    x = 1
    t.setCursorPos(x, y)
    lines = lines + 1
  end
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == "\n" then newline()
    else
      if x > w then newline() end
      t.setCursorPos(x, y)
      t.write(c)
      x = x + 1
    end
  end
  t.setCursorPos(x, y)
  return lines
end
print = function(...)
  local parts2 = {}
  for i = 1, select("#", ...) do parts2[#parts2 + 1] = tostring(select(i, ...)) end
  return write(table.concat(parts2, "\t") .. "\n")
end
function printError(...)
  local old = term.getTextColor()
  term.setTextColor(colors.red)
  print(...)
  term.setTextColor(old)
end
function read(mask)
  local line = ""
  local x, y = term.getCursorPos()
  term.setCursorBlink(true)
  while true do
    local e, p = os.pullEvent()
    if e == "char" then line = line .. p; term.setCursorPos(x, y); term.write(mask and ("*"):rep(#line) or line)
    elseif e == "paste" then line = line .. p; term.setCursorPos(x, y); term.write(mask and ("*"):rep(#line) or line)
    elseif e == "key" and p == keys.backspace and #line > 0 then
      line = line:sub(1, -2); term.setCursorPos(x, y); term.write(line .. " ")
    elseif e == "key" and p == keys.enter then
      term.setCursorBlink(false)
      print()
      return line
    end
  end
end

---------------------------------------------------------------- shell
local shellDir, shellPath = "", ".:/rom/programs:/rom/programs/fun:/rom/programs/fun/advanced"
local completions = {}
shell = {}
function shell.dir() return shellDir end
function shell.setDir(d) shellDir = fs.combine(d) end
function shell.path() return shellPath end
function shell.setPath(p) shellPath = p end
function shell.resolve(p)
  if p:sub(1, 1) == "/" or p:sub(1, 1) == "\\" then return fs.combine(p) end
  return fs.combine(shellDir, p)
end
function shell.resolveProgram(name)
  if name:find("/") then
    local p = shell.resolve(name)
    if fs.exists(p) and not fs.isDir(p) then return p end
    if fs.exists(p .. ".lua") then return p .. ".lua" end
    return nil
  end
  for dir in shellPath:gmatch("[^:]+") do
    local base = dir == "." and shellDir or fs.combine(dir)
    for _, cand in ipairs({ fs.combine(base, name), fs.combine(base, name .. ".lua") }) do
      if fs.exists(cand) and not fs.isDir(cand) then return cand end
    end
  end
end
function shell.aliases() return {} end
function shell.setAlias() end
function shell.setCompletionFunction(p, f) completions[p] = f end
function shell.getRunningProgram() return "" end
function shell.run(...)
  local line = table.concat({ ... }, " ")
  local words = {}
  local token,quote={},nil
  for i=1,#line do local c=line:sub(i,i)
    if quote then if c==quote then quote=nil else token[#token+1]=c end
    elseif c=='"'or c=="'"then quote=c
    elseif c:match("%s")then if #token>0 then words[#words+1]=table.concat(token);token={}end
    else token[#token+1]=c end
  end
  if #token>0 then words[#words+1]=table.concat(token)end
  if not words[1] then return false end
  local path = shell.resolveProgram(words[1])
  if not path then printError("No such program"); return false end
  return os.run({ shell = shell }, path, table.unpack(words, 2))
end

function os.run(env, path, ...)
  local mt = getmetatable(env)
  if not mt then setmetatable(env, { __index = _G }) end
  local fn, err = loadfile(path, nil, env)
  if not fn then printError(err); return false end
  local ok, e = pcall(fn, ...)
  if not ok then
    if e and e ~= "" then printError(e) end
    return false
  end
  return true
end

local MODULES = {
  ["cc.audio.dfpwm"] = {
    make_decoder = function()
      return function(data)
        local t = {}
        for i = 1, #data * 8 do t[i] = ((i * 7) % 96) - 48 end
        return t
      end
    end,
  },
  ["cc.shell.completion"] = {
    build = function() return function() return {} end end,
    choice = function() end, file = function() end, dir = function() end,
  },
}
MODULES["cc.require"] = { make = function() return require, {} end }
require = function(name)
  local m = MODULES[name]
  if not m then error("module '" .. name .. "' not found", 2) end
  return m
end

---------------------------------------------------------------- textutils and keys
textutils = {}
local function ser(v, indent)
  local t = type(v)
  if t == "string" then return ("%q"):format(v) end
  if t ~= "table" then return tostring(v) end
  local out = {}
  for k, x in pairs(v) do
    local key = type(k) == "string" and ("[%q]"):format(k) or ("[" .. tostring(k) .. "]")
    out[#out + 1] = key .. "=" .. ser(x)
  end
  return "{" .. table.concat(out, ",") .. "}"
end
textutils.serialize = ser
textutils.serialise = ser
function textutils.unserialize(s)
  local f = realLoad("return " .. s, "unserialize", "t", {})
  if not f then return nil end
  local ok, v = pcall(f)
  return ok and v or nil
end

local KEYS = { space = 32, enter = 257, tab = 258, backspace = 259, delete = 261, right = 262, left = 263,
  down = 264, up = 265, pageUp = 266, pageDown = 267, home = 268, ["end"] = 269, leftShift = 340,
  leftCtrl = 341, leftAlt = 342, rightAlt = 346, f1 = 290, f5 = 294, numPadEnter = 335 }
for i = 0, 9 do KEYS[({ "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" })[i + 1]] = 48 + i end
for c = 97, 122 do KEYS[string.char(c)] = c - 32 end
keys = {}
local NAMEOF = {}
for k, v in pairs(KEYS) do keys[k] = v; NAMEOF[v] = k end
function keys.getName(code) return NAMEOF[code] end

_HOST = "ComputerCraft 1.113.1 (Minecraft 1.21.1)"
http = nil

---------------------------------------------------------------- peripherals
local devices = {}
local function attach(name, ty, obj)
  obj._name = name
  devices[name] = { type = ty, obj = obj }
end
local function detach(name)
  devices[name] = nil
  push("peripheral_detach", name)
end

peripheral = {}
function peripheral.getNames()
  local n = {}
  for k in pairs(devices) do n[#n + 1] = k end
  table.sort(n)
  return n
end
function peripheral.isPresent(n) return devices[n] ~= nil end
function peripheral.getType(n) return devices[n] and devices[n].type end
function peripheral.wrap(n) return devices[n] and devices[n].obj end
function peripheral.call(n, m, ...)
  local d = devices[n]
  if not d then error("No peripheral attached", 2) end
  if type(d.obj[m]) ~= "function" then error("No such method " .. m, 2) end
  return d.obj[m](...)
end
function peripheral.find(ty)
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    if devices[n].type == ty then out[#out + 1] = devices[n].obj end
  end
  return table.unpack(out)
end

local function makeMonitor(bw, bh, colour)
  local scale = 1
  local function size(s)
    return max(1, floor((bw - 0.3125) / (s * 6 / 64) + 0.5)), max(1, floor((bh - 0.3125) / (s * 9 / 64) + 0.5))
  end
  local m = makeTerm(size(1), nil and 0 or select(2, size(1)), { color = colour })
  m.scaleSets = 0
  function m.setTextScale(s)
    assert(type(s) == "number" and s >= 0.5 and s <= 5 and (s * 2) % 1 == 0, "Expected number in range 0.5-5")
    if s ~= scale then
      scale = s
      m.resize(size(s))
      m.scaleSets = m.scaleSets + 1
      push("monitor_resize", m._name)
    end
  end
  function m.getTextScale() return scale end
  return m
end

function peripheral.getMethods(name)
  local out={};local d=devices[name];if not d then return out end
  for key,value in pairs(d.obj)do if type(value)=="function"and key:sub(1,1)~="_"then out[#out+1]=key end end;table.sort(out);return out
end
function peripheral.hasType(name,kind)return peripheral.getType(name)==kind end
local signals,bundles={},{}
redstone={}
function redstone.getAnalogInput(side)return 0 end
function redstone.getInput(side)return false end
function redstone.getAnalogOutput(side)return signals[side]or 0 end
function redstone.getOutput(side)return(signals[side]or 0)>0 end
function redstone.setAnalogOutput(side,n)signals[side]=n end
function redstone.setOutput(side,on)signals[side]=on and 15 or 0 end
function redstone.getBundledOutput(side)return bundles[side]or 0 end
function redstone.setBundledOutput(side,n)bundles[side]=n end
function redstone.getBundledInput(side)return 0 end
local audioLog = { notes = {}, samples = {} }
local function makeSpeaker(name)
  local spk = { queued = 0 }
  function spk.playNote(inst, vol, pitch)
    assert(type(inst) == "string", "instrument")
    vol, pitch = vol or 1, pitch or 12
    if vol < 0 or vol > 3 then fail("speaker volume out of range: " .. vol) end
    if pitch < 0 or pitch > 24 then fail("pitch out of range: " .. pitch) end
    audioLog.notes[#audioLog.notes + 1] = name .. ":" .. inst .. ":" .. floor(pitch)
    return true
  end
  function spk.playAudio(samples, vol)
    if type(samples) ~= "table" or #samples == 0 or #samples > 128 * 1024 then fail("bad audio buffer size " .. tostring(#samples)) end
    if vol and (vol < 0 or vol > 3) then fail("audio volume out of range: " .. vol) end
    for i = 1, #samples, 997 do
      local v = samples[i]
      if type(v) ~= "number" or v < -128 or v > 127 or v ~= floor(v) then fail("bad sample " .. tostring(v)); break end
    end
    -- Like a real speaker: chunks play one after another, and a new one is
    -- taken while less than one chunk is waiting behind the playing one.
    spk.ends = spk.ends or {}
    local waiting = 0
    for _, e in ipairs(spk.ends) do if e > tick then waiting = waiting + 1 end end
    if waiting >= 2 then return false end
    local last = tick
    for _, e in ipairs(spk.ends) do if e > last then last = e end end
    local finish = last + ceil(#samples / 48000 * 20)
    spk.ends[#spk.ends + 1] = finish
    audioLog.samples[name] = (audioLog.samples[name] or 0) + #samples
    local gen = spk.gen
    at(finish - ceil(#samples / 48000 * 20), function()
      if spk.gen == gen then push("speaker_audio_empty", name) end
    end)
    return true
  end
  function spk.stop() spk.ends = {}; spk.gen = (spk.gen or 0) + 1 end
  function spk.playSound() return true end
  return spk
end

local printed = {}
local function makePrinter()
  local p = { paper = 16, ink = 16 }
  local page, cx, cy = nil, 1, 1
  function p.newPage()
    if p.paper <= 0 or p.ink <= 0 then return false end
    p.paper, p.ink = p.paper - 1, p.ink - 1
    page = { title = "", lines = {} }
    for i = 1, 21 do page.lines[i] = (" "):rep(25) end
    cx, cy = 1, 1
    return true
  end
  function p.endPage()
    if not page then error("Page not started", 2) end
    printed[#printed + 1] = page
    page = nil
    return true
  end
  function p.write(s)
    if not page then error("Page not started", 2) end
    s = tostring(s)
    local l = page.lines[cy]
    if l then page.lines[cy] = (l:sub(1, cx - 1) .. s .. l:sub(cx + #s)):sub(1, 25) end
    cx = cx + #s
  end
  function p.setCursorPos(x, y) cx, cy = x, y end
  function p.getCursorPos() return cx, cy end
  function p.getPageSize() return 25, 21 end
  function p.setPageTitle(t) if page then page.title = t end end
  function p.getPaperLevel() return p.paper end
  function p.getInkLevel() return p.ink end
  return p
end

local function makeDrive()
  local d = { present = true, label = "Mixtape", mount = "disk", audio = nil, playing = false }
  function d.isDiskPresent() return d.present end
  function d.getDiskLabel() return d.present and d.label or nil end
  function d.setDiskLabel(l) d.label = l end
  function d.hasData() return d.present and d.mount ~= nil end
  function d.getMountPath() return d.present and d.mount or nil end
  function d.hasAudio() return d.present and d.audio ~= nil end
  function d.getAudioTitle() return d.audio end
  function d.playAudio() d.playing = true end
  function d.stopAudio() d.playing = false end
  function d.getDiskID() return 3 end
  function d.ejectDisk()
    if not d.present then return end
    d.present = false
    root.kids.disk = nil
    push("disk_eject", d._name)
  end
  return d
end

local function makeModem(open)
  local ch = {}
  for _, c in ipairs(open or {}) do ch[c] = true end
  return {
    isWireless = function() return true end, isOpen = function(c) return ch[c] == true end,
    open = function(c) ch[c] = true end, close = function(c) ch[c] = nil end, transmit = function() end,
  }
end

local mainMon, panelMon = makeMonitor(8, 3, true), makeMonitor(3, 1, true)
attach("monitor_0", "monitor", mainMon)
attach("monitor_1", "monitor", panelMon)
attach("speaker_0", "speaker", makeSpeaker("speaker_0"))
attach("speaker_1", "speaker", makeSpeaker("speaker_1"))
attach("printer_0", "printer", makePrinter())
local drive = makeDrive()
attach("drive_0", "drive", drive)
attach("top", "modem", makeModem())

---------------------------------------------------------------- capture
local SCREENS = { term = computer, main = mainMon, panel = panelMon }
local captures = {}

local function capture(label, which)
  for _, key in ipairs(which or { "main", "panel", "term" }) do
    local o = SCREENS[key]
    local t = o._t
    local rows = {}
    for y = 1, t.h do rows[y] = { t.text[y], t.fgs[y], t.bgs[y] } end
    local pal = {}
    for i = 1, 16 do pal[i] = t.pal[i] end
    captures[#captures + 1] = { label = label .. " (" .. key .. ")", w = t.w, h = t.h, rows = rows, pal = pal }
  end
end

-- Text of a screen, for finding things to tap.
local function findText(key, text, nth, fromBottom)
  local t = SCREENS[key]._t
  local n = 0
  for y = fromBottom and t.h or 1, fromBottom and 1 or t.h, fromBottom and -1 or 1 do
    local from = 1
    while true do
      local x = t.text[y]:find(text, from, true)
      if not x then break end
      n = n + 1
      if n == (nth or 1) then return x, y end
      from = x + 1
    end
  end
end

local function tap(key, text, opts)
  opts = opts or {}
  return function()
    local x, y = findText(key, text, opts.nth, opts.bottom)
    if not x then fail("tap: \"" .. text .. "\" isn't on " .. key .. " at tick " .. tick); return end
    x = x + (opts.dx or 0)
    y = y + (opts.dy or 0)
    if realOs.getenv("TAP_DEBUG") then io.stderr:write(("tap %s %q at %d,%d tick %d\n"):format(key, text, x, y, tick)) end
    if key == "term" then
      push("mouse_click", 1, x, y)
      push("mouse_up", 1, x, y)
    else
      push("monitor_touch", key == "main" and "monitor_0" or "monitor_1", x, y)
    end
  end
end
local function tapXY(key, x, y)
  return function()
    local t = SCREENS[key]._t
    if y < 0 then y = t.h + 1 + y end
    if key == "term" then push("mouse_click", 1, x, y); push("mouse_up", 1, x, y)
    else push("monitor_touch", key == "main" and "monitor_0" or "monitor_1", x, y) end
  end
end
local function keyPress(name) return function() push("key", keys[name], false); push("key_up", keys[name]) end end
local function typeText(s)
  return function()
    for i = 1, #s do push("char", s:sub(i, i)) end
  end
end
local function alt(name)
  return function()
    push("key", keys.leftAlt, false)
    push("key", keys[name], false)
    push("key_up", keys[name])
    push("key_up", keys.leftAlt)
  end
end
local function expect(key, text, why)
  return function()
    if not findText(key, text) then fail(("expected %q on %s at tick %d (%s)"):format(text, key, tick, why or "")) end
  end
end

---------------------------------------------------------------- scenario
local T0 = 0
local script = {}
local function step(dt, fn) script[#script + 1] = { dt = dt, fn = fn } end

if SCENARIO == "home" then
  -- this run tests the big monitor as its own widescreen desktop
  writeFile("ccos/config.cfg", '{["screenLayout"]=2,["screens"]={["monitor_0"]={["role"]="desktop"}}}')
  step(20, function() capture("Boot splash") end)
  step(80, function() capture("Desktop") end)
  step(2, expect("main", "Files", "desktop icon"))
  step(2, expect("panel", ":", "panel clock"))
  -- Files on the big monitor
  step(2, tap("main", "Files"))
  step(10, function() capture("Files", { "main" }) end)
  step(2, tap("main", "music/", {}))
  step(4, tap("main", "music/", {}))
  step(10, function() capture("Files: music", { "main" }) end)
  step(2, tap("main", "ccOS Theme"))
  step(4, tap("main", "Play"))
  step(30, function() capture("Playing", { "main", "panel" }) end)
  step(2, expect("panel", "ccOS Theme", "now playing on the panel"))
  -- Start menu and Music
  step(2, tapXY("main", 3, -2))
  step(6, function() capture("Start menu", { "main" }) end)
  step(2, tap("main", "Stereo player", { bottom = true }))
  step(20, function() capture("Music", { "main" }) end)
  step(2, tap("main", "Chord"))
  step(30, function() capture("Music: WAV", { "main", "panel" }) end)
  step(2, tap("main", "Duet"))
  step(30, function() capture("Music: stereo pair", { "main" }) end)
  -- snap via the window menu
  step(2, tap("main", "\4", { nth = 2 }))
  step(4, function() capture("Window menu", { "main" }) end)
  step(2, tap("main", "Snap right"))
  step(6, function() capture("Snapped", { "main" }) end)
  -- Command palette on the computer
  step(2, alt("space"))
  step(4, typeText("help"))
  step(4, keyPress("enter"))
  step(10, function() capture("Palette help", { "term" }) end)
  step(2, expect("term", "Enter run", "palette on the computer"))
  step(2, typeText("banner HI"))
  step(2, keyPress("enter"))
  step(20, function() capture("Palette banner", { "term" }) end)
  step(2, alt("space"))
  -- Terminal with ccOS commands
  step(2, alt("t"))
  step(10, typeText("np"))
  step(2, keyPress("enter"))
  step(10, typeText("screens"))
  step(2, keyPress("enter"))
  step(10, typeText("theme sunset"))
  step(2, keyPress("enter"))
  step(20, function() capture("Terminal commands", { "term", "main" }) end)
  step(2, typeText("theme ccos"))
  step(2, keyPress("enter"))
  -- drag the terminal window by its title
  step(4, function()
    local x, y = findText("term", "Terminal")
    if x then push("mouse_click", 1, x + 2, y); push("mouse_drag", 1, x + 6, y + 2); push("mouse_up", 1, x + 6, y + 2) end
  end)
  -- more apps on the monitor
  for _, name in ipairs({ "Clock", "Calculator", "Piano", "Tasks", "Print Center", "Settings" }) do
    step(4, tapXY("main", 3, -2))
    step(4, tap("main", name, { bottom = true }))
    step(20, function() capture(name, { "main" }) end)
  end
  step(2, tap("main", "Sound"))
  step(6, function() capture("Settings: sound", { "main" }) end)
  step(2, tap("main", "Screens"))
  step(6, function() capture("Settings: screens", { "main" }) end)
  -- disk out and back
  step(2, function() drive.ejectDisk() end)
  step(10, function() capture("Disk ejected", { "main" }) end)
  step(2, function()
    drive.present, drive.label, drive.mount, drive.audio = true, nil, nil, "C418 - cat"
    push("disk", "drive_0")
  end)
  step(20, function() capture("Music disc", { "main", "panel" }) end)
  -- panel pages
  step(2, tap("panel", "\183", {}))
  step(4, function() capture("Panel next", { "panel" }) end)
  -- screen saver: no input for a while
  step(2, function() push("monitor_touch", "monitor_1", 50, 9) end)
  step(2, function() capture("End", { "main", "panel", "term" }) end)
  step(2, function() push("char", "x") end)
  step(4, alt("space"))
  step(2, typeText("exit"))
  step(2, keyPress("enter"))
elseif SCENARIO == "picture" or SCENARIO == "picture-small" or SCENARIO == "picture-compact" or SCENARIO == "picture-upgrade" then
  if SCENARIO == "picture-small"or SCENARIO == "picture-compact"then
    writeFile("ccos/config.cfg", '{["screenLayout"]=2,["screens"]={["monitor_0"]={["role"]="picture"},["monitor_1"]={["role"]="panel"}}}')
    mainMon=SCENARIO=="picture-small"and makeMonitor(4,3,true)or makeMonitor(2,1,true);attach("monitor_0","monitor",mainMon);SCREENS.main=mainMon
  elseif SCENARIO=="picture-upgrade"then writeFile("aurora/config.cfg",'{["user"]="Legacy",["theme"]="aurora",["screens"]={["monitor_0"]={["role"]="mirror"}}}')end
  local function noTyping()
    for _,word in ipairs({"BIG SCREEN","Big Screen","Ask ccOS...","Type to search","Enter text"})do if findText("main",word)then fail("unwanted monitor element: "..word)end end
    if mainMon._t.blink then fail("monitor typing cursor")end
  end
  local function category(name)
    if SCENARIO=="picture-compact"then
      for _=1,10 do step(3,function()local row=mainMon._t.text[2];if not row or not row:find(name,1,true)then tap("main","Cat >")()end end)end
    else
      local order={"Favorites","Files","Time","Media","Math","Text","Developer","System","Games","AI"}
      for i,label in ipairs(order)do if label==name then step(3,tapXY("main",5,i+1))end end
    end
  end
  local function home()step(3,tap("main","< Tools"));step(4,noTyping)end
  step(100,function()capture("ccOS compact monitor");noTyping()end)
  step(2,expect("main","ccOS","renamed OS"))
  if SCENARIO~="picture-compact"then
    step(2,expect("main","AI Agent","agent favorite"))
    step(2,tap("main","Music"));step(8,tap("main","Mixtape Song"));step(10,expect("main","Pause","shared audio"));step(2,function()capture("ccOS music",{"main"});noTyping()end);home()
    category("Time");step(3,tap("main","World clocks"));step(8,expect("main","America/Chicago","world clocks"));step(2,function()capture("ccOS world clocks",{"main"});noTyping()end);home()
    category("Math");step(3,tap("main","Unit converter"));step(8,expect("main","From m","unit conversion"));step(2,tap("main","+1"));step(2,function()capture("ccOS units",{"main"});noTyping()end);home()
    category("System");step(3,tap("main","Redstone"));step(8,tap("main","Turn on"));step(4,function()if not redstone.getOutput("left")then fail("redstone touch control failed")end;capture("ccOS redstone",{"main"})end);home()
    category("AI");step(3,tap("main","AI Agent"));step(8,expect("main","Inspect system","agent touch actions"));step(2,function()capture("ccOS agent monitor",{"main"});noTyping()end);home()
    category("Favorites");step(3,tap("main","Settings"));step(8,expect("main","Time zone:","zone settings"));step(2,tap("main","24-hour clock:"));step(4,function()capture("ccOS monitor settings",{"main"});noTyping()end);home()
  else
    step(3,tap("main","Files"));step(6,expect("main","+ ccos/","compact file list"));home()
    category("Games");step(3,function()if not findText("main","Dice")then tap("main","Next >")()end end);step(3,tap("main","Dice"));step(6,tap("main","Roll"));step(4,function()capture("ccOS compact dice",{"main"});noTyping()end);home()
  end
  step(2,alt("a"));step(10,expect("term","Ask ccOS...","desktop AI composer"));step(2,noTyping)
  step(2,alt("space"));step(2,typeText("exit"));step(2,keyPress("enter"))
elseif SCENARIO=="tool-logic"then
  step(100,function()
    local checkTools=assert(realLoad(readReal("suite_checks.lua")))()
    local ok,count=pcall(checkTools,{makeTerm=makeTerm})
    if not ok then fail("Tool behavior check: "..tostring(count))else log(tostring(count).." tool behavior assertions passed")end
  end)
  step(2,alt("space"));step(2,typeText("exit"));step(2,keyPress("enter"))
elseif SCENARIO=="agent"or SCENARIO=="agent-error"or SCENARIO=="agent-malformed"or SCENARIO=="agent-cancel"or SCENARIO=="agent-cancel-http"or SCENARIO=="agent-timeout"or SCENARIO=="agent-deny"then
  local factory=assert(realLoad(readReal("agent_mock.lua")))()
  http=factory({scenario=SCENARIO,push=push,after=function(dt,fn)at(tick+dt,fn)end})
  step(100,function()
    ccos.agent.setKey("sk-or-test-key");ccos.launch("agent",{},"term")
    local ok,err=ccos.agent.start("Create and edit a note, run a test program and update the clock and volume.");if not ok then fail(err)end
  end)
  if SCENARIO=="agent"then
    for _=1,40 do step(2,function()if ccos.agent.pending then ccos.agent.approve(true)end end)end
    step(15,function()
      if ccos.agent.busy then fail("agent did not finish")end
      if ccos.agent.status~="Done"then fail("agent failed: "..ccos.agent.status)end
      local file=node("notes/agent.txt");if not file or file.data~="hello ccOS\ndone\n"then fail("agent file edit result is wrong")end
      if ccos.config("utcOffset")~=330 or ccos.config("timezone")~="fixed"then fail("agent settings were not applied")end
      if ccos.config("musicVolume")~=0.4 then fail("agent volume was not applied")end
      if redstone.getAnalogOutput("left")~=7 then fail("agent redstone was not applied")end
      local calls,closed=http.stats();if calls~=5 or closed~=5 then fail("HTTP tool rounds/handles differ")end
      local log=node("ccos/logs/agent.log");if not log or log.data:find("sk-or-test-key",1,true)then fail("agent audit log missing or leaked key")end
      capture("ccOS agent completed",{"term","main"})
    end)
    step(2,alt("a"));step(5,function()capture("ccOS agent conversation",{"term"})end)
  elseif SCENARIO=="agent-timeout"then
    step(1010,function()if ccos.agent.busy or ccos.agent.status~="Error"then fail("request timeout was not handled")end end)
  elseif SCENARIO=="agent-cancel-http"then
    step(1,function()ccos.agent.cancel()end)
    step(5,function()local ok=ccos.agent.start("Another task");if ok then fail("overlapping response could be mistaken for a new task")end end)
    step(20,function()local _,closed=http.stats();if ccos.agent.inflight or closed~=1 then fail("late HTTP response was not closed")end end)
  elseif SCENARIO=="agent-deny"then
    step(5,function()if not ccos.agent.pending then fail("mutation should require review")end;ccos.agent.approve(false)end)
    step(10,function()if node("notes/denied.txt")then fail("denied mutation ran")end;if ccos.agent.status~="Done"then fail("denied action did not return to model")end end)
  elseif SCENARIO=="agent-cancel"then
    step(15,function()if not ccos.agent.pending then fail("agent should be waiting for review")end;capture("ccOS agent review",{"term"});ccos.agent.cancel()end)
    step(8,function()if ccos.agent.busy then fail("cancel did not stop agent")end;if node("notes/agent.txt")then fail("cancelled action wrote a file")end end)
  else
    step(15,function()if ccos.agent.busy then fail("error handling did not finish")end
      if SCENARIO=="agent-error"and ccos.agent.status~="Error"then fail("HTTP failure not shown")end
      if SCENARIO=="agent-malformed"and ccos.agent.status~="Done"then fail("malformed tool error did not recover")end
      capture("ccOS agent response handling",{"term"})
    end)
  end
  step(2,alt("space"));step(2,typeText("exit"));step(2,keyPress("enter"))
elseif SCENARIO == "tools-desktop"or SCENARIO == "tools-monitor"then
  local toolCatalog=assert(realLoad(readReal(SRC.."/ccos/lib/catalog.lua")))()
  step(100,function()capture("ccOS desktop",{"term"})end)
  for _,def in ipairs(toolCatalog.apps())do
    local id,title=def.id,def.name
    if SCENARIO=="tools-desktop"or def.touch then
      step(2,function()ccos.launch(id,{},SCENARIO=="tools-monitor"and "monitor_0"or "term")end)
      step(6,function()
        local screen=SCENARIO=="tools-monitor"and "main"or "term"
        if not findText(screen,title)then fail("Tool did not render: "..id)end
        if ({units=true,calendar=true,redstone=true,json=true,peripherals=true,lights=true,base64=true,focus=true})[id]then capture(title,{screen})end
      end)
      step(2,function()for _,w in ipairs(ccos.windows())do if w.app==id then ccos.close(w.id)end end end)
      step(3,function()end)
    end
  end
  step(2,alt("space"));step(2,typeText("exit"));step(2,keyPress("enter"))
elseif SCENARIO == "desktop-menu" then
  step(100, function() capture("Computer desktop", { "term" }) end)
  step(2, alt("s"))
  step(5, expect("term", "Files", "start menu"))
  step(2, tap("term", "Files"))
  step(10, expect("term", "Files - /", "start menu app click"))
  step(2, alt("s"))
  step(5, tap("term", "Next >"))
  step(5, expect("term", "Editor", "start menu pagination reaches later apps"))
  step(2, function() capture("Computer start menu page 2", { "term" }) end)
  step(2, tap("term", "Settings", { bottom = true }))
  step(10, expect("term", "Appearance", "settings opened"))
  step(2, tapXY("term", 50, 2))
  step(5, expect("term", "Sound", "section navigation"))
  step(2, tapXY("term", 50, 2))
  step(5, expect("term", "Screens", "screen section"))
  step(2, expect("term", "Role", "role action fits computer width"))
  step(2, expect("term", "Scale -", "scale action fits computer width"))
  step(2, expect("term", "Auto", "auto scale action fits computer width"))
  step(2, function() capture("Computer screen settings", { "term" }) end)
  step(2, alt("space"))
  step(2, typeText("exit"))
  step(2, keyPress("enter"))
elseif SCENARIO == "mirror" then
  writeFile("ccos/config.cfg", '{["screenLayout"]=2,["screens"]={["monitor_0"]={["role"]="mirror"}}}')
  local function sameAsComputer(why)
    return function()
      local m, t = mainMon._t, computer._t
      local ox, oy = floor((m.w - t.w) / 2), floor((m.h - t.h) / 2)
      for y = 1, t.h do
        local row = m.text[y + oy]:sub(ox + 1, ox + t.w)
        if row ~= t.text[y] or m.bgs[y + oy]:sub(ox + 1, ox + t.w) ~= t.bgs[y] then
          fail(("mirror row %d differs from the computer (%s)"):format(y, why))
          return
        end
      end
    end
  end
  step(30, function() capture("Mirror: booting", { "main" }) end)
  step(80, function() capture("Mirror: desktop", { "main", "term" }) end)
  step(2, sameAsComputer("desktop"))
  step(2, function()
    local m, t = mainMon._t, computer._t
    push("monitor_touch", "monitor_0", floor((m.w - t.w) / 2) + 2, floor((m.h - t.h) / 2) + t.h)
  end)
  step(6, function() capture("Mirror: start menu by touch", { "main" }) end)
  step(2, expect("term", "Type to search", "start menu opened on the computer by a tap on the monitor"))
  step(2, sameAsComputer("start menu"))
  step(2, tap("main", "Files", { bottom = true }))
  step(20, function() capture("Mirror: Files by touch", { "main", "term" }) end)
  step(2, expect("term", "Files - /", "Files opened on the computer"))
  step(2, tap("main", "music/"))
  step(2, tap("main", "music/"))
  step(10, function() capture("Mirror folder result", { "term" }); expect("term", "Chord.wav", "two taps opened a folder")() end)
  step(2, alt("t"))
  step(10, typeText("np"))
  step(2, keyPress("enter"))
  step(10, function() capture("Mirror: typing on the computer", { "main" }) end)
  step(2, sameAsComputer("terminal"))
  step(2, alt("space"))
  step(2, typeText("exit"))
  step(2, keyPress("enter"))
elseif SCENARIO=="setup-rollback"or SCENARIO=="setup-no-space"then
  writeFile("setup.lua",readReal(SRC.."/../setup.lua"))
  writeFile("ccos/kernel.lua","-- previous kernel")
  writeFile("ccos/apps/calc.lua","-- previous calculator")
  writeFile("ccos/apps/piano.lua","-- previous piano")
  writeFile("startup.lua","-- previous startup")
  if SCENARIO=="setup-no-space"then fs.getFreeSpace=function()return 0 end
  else
    local move=fs.move;local moves=0;local injected=false
    fs.move=function(src,dst)
      if not injected and src:find("/.ccos-stage-",1,true)and not src:find("-previous",1,true)then moves=moves+1;if moves==3 then injected=true;error("simulated interrupted install")end end
      return move(src,dst)
    end
  end
elseif SCENARIO=="install"or SCENARIO=="setup"or SCENARIO=="setup-offline"or SCENARIO=="setup-reinstall"then
  if SCENARIO~="setup-reinstall"then root.kids.ccos=nil end
  writeFile("ccos/data/preserved.txt","preserved user data")
  if SCENARIO=="setup-reinstall"then writeFile("ccos/private/openrouter.cfg","sk-or-preserved-key")end
  writeFile("setup.lua",readReal(SRC.."/../setup.lua"))
  writeFile("startup.lua","-- existing startup\nprint('old')\n")
  writeFile("aurora/config.cfg",'{["user"]="Old name",["theme"]="aurora",["clock24"]=true}')
  local function enter(text)step(4,typeText(text));step(2,keyPress("enter"))end
  enter("Finn")
  enter("3")
  enter("12")
  enter("n")
  enter("midnight")
  if SCENARIO=="setup-offline"or SCENARIO=="setup-reinstall"then enter("n")else enter("y");enter("sk-or-setup-test-key")end
  enter("test/tool-model")
  enter("y")
  step(2,function()capture("ccOS setup summary",{"term"})end)
  enter("y")
  step(100,function()
    capture("ccOS installed and rebooted")
    for _,rel in ipairs(SOURCE_FILES)do local n=node(rel);if not n or n.data~=readReal(SRC.."/"..rel)then fail("Installed source differs: "..rel)end end
    local h=fs.open("ccos/config.cfg","r");local cfg=textutils.unserialize(h.readAll());h.close()
    if not cfg.setupComplete or cfg.user~="Finn"or cfg.timezone~="America/Chicago"or cfg.clock24~=false or cfg.leadingZero~=false then fail("Wizard preferences were not saved")end
    if not node("startup.before-ccos.lua")then fail("Old startup was not preserved")end
    if not node("startup.lua").data:find("ccos/kernel.lua",1,true)then fail("Startup does not boot ccOS")end
    local key=node("ccos/private/openrouter.cfg")
    if SCENARIO=="setup-offline"then if key then fail("Offline setup unexpectedly saved a key")end
    elseif not key or key.data~=(SCENARIO=="setup-reinstall"and "sk-or-preserved-key"or "sk-or-setup-test-key")then fail("Wizard key was not saved/preserved")end
    if not ccos then fail("Setup did not restart into the OS")end
    if node("ccos/data/preserved.txt").data~="preserved user data"then fail("Setup changed user data")end
  end)
  step(2,alt("space"));step(2,typeText("exit"));step(2,keyPress("enter"))
elseif SCENARIO == "small" then
  -- one small monitor desktop, no panel, one speaker
  devices.monitor_1, devices.speaker_1 = nil, nil
  mainMon = makeMonitor(4, 3, true)
  attach("monitor_0", "monitor", mainMon)
  SCREENS.main = mainMon
  step(100, function() capture("Small desktop", { "main", "term" }) end)
  step(2, tap("main", "Music"))
  step(20, function() capture("Small music", { "main" }) end)
  step(2, alt("f"))
  step(20, function() capture("Files on the computer", { "term" }) end)
  step(2, alt("space"))
  step(2, typeText("exit"))
  step(2, keyPress("enter"))
end

---------------------------------------------------------------- run
local chunk
if SCENARIO=="install"or SCENARIO:match("^setup")then
  chunk=function()
    shell.run("setup")
    if powered=="reboot"then powered=nil;shell.run("startup.lua")end
  end
else
  chunk = assert(loadfile("ccos/kernel.lua", nil, setmetatable({ shell = shell, require = require }, { __index = _G })))
end
local main = coroutine.create(function() return chunk() end)
local filter
local function resume(ev)
  local ok, f = coroutine.resume(main, table.unpack(ev, 1, ev.n))
  if not ok then
    if f == "REBOOT" or f == "SHUTDOWN" then return end
    io.stderr:write("PROGRAM ERROR: ", debug.traceback(main, f), "\n")
    FAIL[#FAIL + 1] = "program error"
  end
  filter = f
end
resume({ n = 0 })
local nextStep, stepAt = 1, T0
while coroutine.status(main) ~= "dead" and tick < 4000 do
  while #queue > 0 and coroutine.status(main) ~= "dead" do
    local ev = table.remove(queue, 1)
    if filter == nil or filter == ev[1] or ev[1] == "terminate" then resume(ev) end
  end
  if coroutine.status(main) == "dead" then break end
  tick = tick + 1
  epochMs = epochMs + 50
  dayTime = dayTime + 1
  local due = {}
  for id, t in pairs(timers) do if t <= tick then due[#due + 1] = id end end
  table.sort(due)
  for _, id in ipairs(due) do timers[id] = nil; push("timer", id) end
  if later[tick] then for _, fn in ipairs(later[tick]) do fn() end; later[tick] = nil end
  if script[nextStep] and tick >= stepAt + script[nextStep].dt then
    stepAt = tick
    script[nextStep].fn()
    nextStep = nextStep + 1
  end
end
if nextStep <= #script then fail(("script stopped at step %d of %d (tick %d)"):format(nextStep, #script, tick)) end

if SCENARIO=="setup-rollback"or SCENARIO=="setup-no-space"then
  if node("ccos/kernel.lua").data~="-- previous kernel"then fail("Failed setup changed the old kernel")end
  if node("startup.lua").data~="-- previous startup"then fail("Failed setup changed startup")end
  if node("ccos/apps/calc.lua").data~="-- previous calculator"or node("ccos/apps/piano.lua").data~="-- previous piano"then fail("Rollback failed to restore apps")end
  for _,name in ipairs(fs.list("/"))do if name:find(".ccos-stage-",1,true)then fail("Failed setup left staging files")end end
end

-- crash log in the virtual disk is a failure too
local crash = node("ccos/crash.log")
if crash then fail("crash.log:\n" .. crash.data) end

log(("---- %s: tick %d, %d captures, notes %d, samples L %d R %d, pages printed %d, main scale sets %d"):format(
  SCENARIO, tick, #captures, #audioLog.notes, audioLog.samples.speaker_0 or 0, audioLog.samples.speaker_1 or 0,
  #printed, mainMon.scaleSets))
for i, p in ipairs(printed) do
  if i <= 2 then
    log("page " .. i .. ": " .. p.title)
    for r = 1, 21 do if p.lines[r]:find("%S") then log("  |" .. p.lines[r] .. "|") end end
  end
end
log("terminal after exit:")
for y = 1, computer._t.h do if computer._t.text[y]:find("%S") then log("  " .. computer._t.text[y]) end end

-- HTML: each capture drawn on a canvas with its palette.
if HTML then
  local out = {}
  local function js(s) return (s:gsub("\\", "\\\\"):gsub('"', '\\"')) end
  out[#out + 1] = [[<!doctype html><meta charset="utf-8"><title>ccOS screens</title>
<style>body{background:#1b1b1f;color:#ddd;font:14px system-ui;margin:20px} h2{font-weight:500;margin:26px 0 8px} canvas{image-rendering:pixelated;border:6px solid #2a2a30;border-radius:4px}</style>
<script>const CAPS=[]</script>]]
  for _, c in ipairs(captures) do
    local rows = {}
    for _, r in ipairs(c.rows) do
      local codes = {}
      for i = 1, #r[1] do codes[i] = r[1]:byte(i) end
      rows[#rows + 1] = ('[[%s],"%s","%s"]'):format(table.concat(codes, ","), r[2], r[3])
    end
    out[#out + 1] = ('<script>CAPS.push({label:"%s",w:%d,h:%d,pal:[%s],rows:[%s]})</script>'):format(
      js(c.label), c.w, c.h, table.concat(c.pal, ","), table.concat(rows, ","))
  end
  out[#out + 1] = [[<div id=root></div><script>
const CP437="\u0000☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼";
const CW=8,CH=12;
const only=new URLSearchParams(location.search).get("i");
if(only!==null){document.body.style.margin="0";}
CAPS.forEach((c,ci)=>{ if(only!==null&&+only!==ci) return;
  const h=document.createElement("h2");h.textContent=c.label+"  "+c.w+"x"+c.h;root.appendChild(h);
  const cv=document.createElement("canvas");cv.width=c.w*CW;cv.height=c.h*CH;root.appendChild(cv);
  const g=cv.getContext("2d");g.font="11px Menlo, monospace";g.textBaseline="middle";g.textAlign="center";
  const col=d=>"#"+c.pal[parseInt(d,16)].toString(16).padStart(6,"0");
  c.rows.forEach((r,y)=>{const [codes,fg,bg]=r;codes.forEach((ch,x)=>{
    g.fillStyle=col(bg[x]);g.fillRect(x*CW,y*CH,CW,CH);
    if(ch>=128&&ch<160){const bits=ch-128;g.fillStyle=col(fg[x]);
      for(let i=0;i<5;i++){if(bits&(1<<i)){const px=i%2,py=Math.floor(i/2);g.fillRect(x*CW+px*CW/2,y*CH+py*CH/3,CW/2,CH/3);}}}
    else if(ch!==32){let s=ch<32?CP437[ch]:(ch===127?"▒":String.fromCharCode(ch));g.fillStyle=col(fg[x]);g.fillText(s,x*CW+CW/2,y*CH+CH/2+1);}
  });});
  if(only!==null){h.remove();cv.style.border="0";}
});</script>]]
  local f = io.open(HTML, "w")
  f:write(table.concat(out, "\n"))
  f:close()
  log("wrote " .. HTML)
end

if #FAIL > 0 then
  log(#FAIL .. " failure(s)")
  realOs.exit(1)
end
log("ok")
