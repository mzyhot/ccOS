-- Music: a stereo player with a library, a visualiser and the drive's
-- music discs.
local ui = ccos.ui
local T = ui.T
local A = ccos.audio
local HEX = ccos.gfx.HEX
local floor, max, min = math.floor, math.max, math.min

local app = { title = "Music", tick = 0.2, lib = { scroll = 0 }, tab = 1 }

local function isAudio(name)
  local e = (name:match("%.(%w+)$") or ""):lower()
  return (e == "dfpwm" and not name:match("%.r%.dfpwm$")) or e == "wav"
end

function app:scan()
  local list, seen = {}, {}
  local function walk(dir, depth)
    local ok, names = pcall(fs.list, dir)
    if not ok then return end
    table.sort(names)
    for _, n in ipairs(names) do
      local p = fs.combine(dir, n)
      if fs.isDir(p) then
        if depth < 3 and p ~= "rom" and p ~= "ccos" then walk(p, depth + 1) end
      elseif isAudio(n) and not seen[p] then
        seen[p] = true
        local it = A.item("/" .. p)
        it.where = dir == "" and "/" or ("/" .. dir)
        list[#list + 1] = it
      end
    end
  end
  walk("", 0)
  self.library = list
end

function app:init()
  if not fs.exists("/music") then pcall(fs.makeDir, "/music") end
  self:scan()
end

local function bars(g, x, y, w, h)
  -- Stereo levels over time: left grows up from the middle, right down.
  local hist = A.history(w)
  local mid = y + floor(h / 2)
  local up, down = mid - y, y + h - 1 - mid
  for c = 1, w do
    local v = hist[#hist - w + c]
    local l, r = v and v[1] or 0, v and v[2] or 0
    local nl, nr = floor(l * up * 2 + 0.5), floor(r * down * 2 + 0.5)
    for k = 1, up do
      local units = nl - (k - 1) * 2
      local ch = units >= 2 and " " or (units == 1 and "\143" or nil)
      if ch then
        term.setCursorPos(x + c - 1, mid - k)
        if ch == " " then term.blit(" ", HEX[T.accent], HEX[T.accent]) else term.blit(ch, HEX[T.bg], HEX[T.accent]) end
      end
    end
    for k = 1, down do
      local units = nr - (k - 1) * 2
      local ch = units >= 2 and " " or (units == 1 and "\131" or nil)
      if ch then
        term.setCursorPos(x + c - 1, mid + k)
        if ch == " " then term.blit(" ", HEX[T.accent2], HEX[T.accent2]) else term.blit(ch, HEX[T.accent2], HEX[T.bg]) end
      end
    end
  end
  g:text(x, mid, ("\140"):rep(w), T.surface, T.bg)
end

function app:drawNow(g, x, y, w, h)
  local info = A.info()
  local touch = ui.touch()
  local bh = touch and 3 or 1
  local name = info.disc and (info.discTitle or "Record") or (info.title or "Nothing playing")
  g:text(x, y, ui.trunc(name, w), info.state == "stopped" and not info.disc and T.muted or T.text, T.bg)
  local sub
  if info.disc then sub = "Music disc in the drive"
  elseif info.state == "stopped" then sub = #(self.library or {}) .. " tracks in the library"
  else sub = (info.state == "playing" and "Playing" or "Paused") .. "  \183  track " .. info.index .. " of " .. info.count end
  if info.message then sub = info.message end
  g:text(x, y + 1, ui.trunc(sub, w), info.message and T.warn or T.muted, T.bg)
  -- from the bottom: volume, transport, meters, progress; the visualiser
  -- takes whatever is left
  local vy = y + h - bh
  local cy = vy - bh - 1
  local py = cy - 4
  local vizH = py - (y + 3) - 1
  if vizH >= 2 then bars(g, x, y + 3, w, vizH) end
  local el, len = A.elapsed(), info.len or 0
  local tl = ui.time(el) .. " / " .. ui.time(len)
  local pw = w - #tl - 1
  g:hbar(x, py, pw, len > 0 and el / len or 0, T.accent, T.surface)
  g:text(x + pw + 1, py, tl, T.muted, T.bg)
  g:hit(x, py, x + pw - 1, py, function(cx) if len > 0 then A.seek((cx - x) / pw) end end)
  -- meters
  local l, r = A.meter()
  g:text(x, py + 1, "L", T.muted, T.bg)
  g:hbar(x + 2, py + 1, w - 2, l, T.accent, T.surface)
  g:text(x, py + 2, "R", T.muted, T.bg)
  g:hbar(x + 2, py + 2, w - 2, r, T.accent2, T.surface)
  -- transport
  local playing = info.state == "playing"
  local items = {
    { "\17\17", A.prev },
    { playing and "||" or " \16 ", A.toggle, { active = true } },
    { "\16\16", A.next },
    { "Stop", A.stop },
    { "Shuffle", function() A.shuffle = not A.shuffle end, { active = A.shuffle, activeBg = T.accent2 } },
    { "Loop " .. A.loop, function() A.loop = ({ off = "all", all = "one", one = "off" })[A.loop] end },
  }
  if info.disc then items = { { "Stop record", A.stopDisc, { active = true } } } end
  g:buttons(x, cy, items, 1, bh)
  -- volume and balance
  if vy > cy + bh then
    local vol = floor((ccos.config("musicVolume") or 0) * 100 + 0.5)
    local b = floor((ccos.config("balance") or 0) * 100 + 0.5)
    local bx = g:button(x, vy, "-", function() A.setVolume((ccos.config("musicVolume") or 0) - 0.05) end, { h = bh })
    g:text(bx + 1, vy + floor((bh - 1) / 2), ("Vol %3d%%"):format(vol), T.text, T.bg)
    bx = g:button(bx + 10, vy, "+", function() A.setVolume((ccos.config("musicVolume") or 0) + 0.05) end, { h = bh }) + 2
    bx = g:button(bx, vy, "L", function() A.setBalance((ccos.config("balance") or 0) - 0.1) end, { h = bh })
    local label = b == 0 and "centre" or (b < 0 and (-b .. "% L") or (b .. "% R"))
    g:text(bx + 1, vy + floor((bh - 1) / 2), ui.pad(label, 7), T.text, T.bg)
    g:button(bx + 9, vy, "R", function() A.setBalance((ccos.config("balance") or 0) + 0.1) end, { h = bh })
  end
end

function app:drawLibrary(g, x, y, w, h)
  local rows = {}
  for _, d in ipairs(ccos.hw().drives or {}) do
    if d.audio then rows[#rows + 1] = { disc = d } end
  end
  for i, it in ipairs(self.library or {}) do rows[#rows + 1] = { item = it, index = i } end
  local info = A.info()
  local touch = ui.touch()
  local rowH = touch and 2 or 1
  g:list(self.lib, x, y, w, h, rows, function(r, _, rx, ry, rw)
    local current = r.item and A.track == r.item
    if r.item and A.track and A.track.path == r.item.path then current = true end
    local bg = current and T.raised or T.bg
    g:fill(rx, ry, rw, rowH, bg)
    if r.disc then
      g:text(rx + 1, ry, "\8", T.warn, bg)
      g:text(rx + 3, ry, ui.trunc("Record: " .. r.disc.audio, rw - 4), T.text, bg)
    else
      g:text(rx + 1, ry, current and (info.state == "playing" and "\16" or "|") or "\14", current and T.accent or T.accent2, bg)
      g:text(rx + 3, ry, ui.trunc(r.item.title, rw - 4), current and T.accent or T.text, bg)
      if rowH > 1 or rw > 40 then
        local where = r.item.where or ""
        if rowH > 1 then g:text(rx + 3, ry + 1, ui.trunc(where, rw - 4), T.muted, bg)
        elseif rw > 40 then g:text(rx + rw - 14, ry, ui.padL(ui.trunc(where, 13), 13), T.muted, bg) end
      end
    end
  end, function(r)
    if r.disc then A.playDisc(r.disc.name) else A.play(self.library, r.index) end
  end, rowH)
  if #rows == 0 then
    local lines = ui.wrap("No music yet. Put .dfpwm or .wav files in /music or on a disk, or play a link.", w - 2)
    for i, l in ipairs(lines) do g:text(x + 1, y + i, l, T.muted, T.bg) end
  end
end

function app:draw(g)
  local w, h = g.w, g.h
  local touch = ui.touch()
  local bh = touch and 3 or 1
  -- top bar
  g:fill(1, 1, w, bh, T.surface)
  if w < 60 then
    g:tabs(1, 1, 30, { "Now playing", "Library" }, self.tab, function(i) self.tab = i end, bh)
  end
  g:buttons(w - 24, 1, {
    { "Rescan", function() self:scan() end },
    { "Play link", function()
      local url = ccos.prompt("Play from the web", "Link to a .dfpwm or .wav file", "https://")
      if url and url:match("^https?://.+") then A.play({ A.item(url) }) end
    end },
  }, 1, bh)
  local top = bh + 2
  if w >= 60 then
    local lw = floor(w * 0.42)
    g:header(2, top, lw - 2, "Library")
    self:drawLibrary(g, 2, top + 1, lw - 2, h - top)
    self:drawNow(g, lw + 2, top, w - lw - 3, h - top)
  elseif self.tab == 1 then
    self:drawNow(g, 2, top, w - 3, h - top)
  else
    self:drawLibrary(g, 1, top, w, h - top + 1)
  end
end

function app:onKey(k)
  if k == keys.space then A.toggle()
  elseif k == keys.right then A.next()
  elseif k == keys.left then A.prev()
  elseif k == keys.up then A.setVolume((ccos.config("musicVolume") or 0) + 0.05)
  elseif k == keys.down then A.setVolume((ccos.config("musicVolume") or 0) - 0.05)
  else return false end
end

function app:onTick()
  -- only redraw while something moves
  local info = A.info()
  local changed = self.lastState ~= info.state
  self.lastState = info.state
  return changed or info.state == "playing" or info.disc ~= nil
end

function app:onEvent(ev)
  if ev[1] == "disk" or ev[1] == "disk_eject" then self:scan(); return true end
end

ui.run(app)
