-- Tasks: windows and background tasks with their CPU use, and devices.
local ui = ccos.ui
local T = ui.T
local floor, max, min = math.floor, math.max, math.min
local function now() return os.epoch("utc") end

local app = { title = "Tasks", tick = 1, tab = 1, list = { scroll = 0 }, devs = { scroll = 0 }, last = {}, rate = {} }

function app:sample()
  local t = now()
  local tasks = ccos.tasks()
  for _, p in ipairs(tasks) do
    local prev = self.last[p.id]
    if prev then self.rate[p.id] = (p.cpu - prev.cpu) / max(1, t - prev.t) * 100 end
    self.last[p.id] = { cpu = p.cpu, t = t }
  end
  self.tasks = tasks
end

function app:init() self:sample() end
function app:onTick() self:sample() end

local function devices()
  local rows = {}
  for _, n in ipairs(peripheral.getNames()) do
    local ty = peripheral.getType(n)
    local info = ""
    if ty == "monitor" then
      local m = peripheral.wrap(n)
      local w, h = m.getSize()
      info = ("%dx%d characters%s"):format(w, h, m.isColor() and ", advanced (touch)" or "")
    elseif ty == "modem" then
      info = peripheral.call(n, "isWireless") and "wireless" or "wired"
    elseif ty == "speaker" then
      local a = ccos.audio.spk
      info = (a.l == n and "left channel") or (a.r == n and "right channel") or "speaker"
    end
    rows[#rows + 1] = { n, ty, info }
  end
  for _, d in ipairs(ccos.hw().drives or {}) do
    for _, r in ipairs(rows) do
      if r[1] == d.name then r[3] = d.present and (d.label or (d.audio and ("record: " .. d.audio)) or "disk inserted") or "empty" end
    end
  end
  for _, p in ipairs(ccos.hw().printers or {}) do
    for _, r in ipairs(rows) do
      if r[1] == p.name then r[3] = ("%d paper, %d ink"):format(p.paper or 0, p.ink or 0) end
    end
  end
  return rows
end

function app:draw(g)
  local w, h = g.w, g.h
  local touch = ui.touch()
  local bh = touch and 3 or 1
  local y = g:tabs(1, 1, w, { "Running", "Devices", "Screens" }, self.tab, function(i) self.tab = i end, bh) + 1
  if self.tab == 1 then
    g:text(2, y, ui.pad("ID", 5) .. ui.pad("Name", 24) .. ui.pad("Where", 12) .. ui.pad("CPU", 7) .. "Up", T.muted, T.bg)
    local rows = self.tasks or {}
    g:list(self.list, 2, y + 1, w - 2, h - y - bh - 1, rows, function(p, _, x, ry, rw)
      local sel = self.sel == p.id
      local bg = sel and T.select or T.bg
      g:fill(x, ry, rw, 1, bg)
      local cpu = self.rate[p.id] or 0
      local line = ui.pad(tostring(p.id), 5) .. ui.pad(p.title, 24) .. ui.pad(p.window and p.screen or "background", 12)
      g:text(x, ry, line, p.service and T.muted or T.text, bg)
      g:text(x + 41, ry, ui.pad(("%.1f%%"):format(cpu), 7), cpu > 20 and T.warn or T.ok, bg)
      g:text(x + 48, ry, ui.trunc(ui.time((now() - p.started) / 1000), rw - 48), T.muted, bg)
    end, function(p) self.sel = p.id end)
    local by = h - bh + 1
    g:fill(1, by, w, bh, T.surface)
    local sel
    for _, p in ipairs(self.tasks or {}) do if p.id == self.sel then sel = p end end
    if sel then
      g:buttons(2, by, {
        { "Show", function() ccos.focus(sel.id) end, { disabled = not sel.window } },
        { "Close", function() ccos.close(sel.id) end, { disabled = not sel.window } },
        { "Stop", function() ccos.kill(sel.id) end, { fg = T.danger, disabled = sel.service } },
      }, 1, bh)
    else
      g:text(2, by + floor((bh - 1) / 2), ("%d running  \183  up %s"):format(#(self.tasks or {}), ui.time(os.clock())), T.muted, T.surface)
    end
  elseif self.tab == 2 then
    local rows = devices()
    g:text(2, y, ui.pad("Name", 16) .. ui.pad("Type", 12) .. "Details", T.muted, T.bg)
    g:list(self.devs, 2, y + 1, w - 2, h - y - 1, rows, function(r, _, x, ry, rw)
      g:text(x, ry, ui.pad(r[1], 16), T.text, T.bg)
      g:text(x + 16, ry, ui.pad(r[2], 12), T.accent, T.bg)
      g:text(x + 28, ry, ui.trunc(r[3], rw - 28), T.muted, T.bg)
    end)
    if #rows == 0 then g:text(2, y + 2, "Nothing attached", T.muted, T.bg) end
  else
    g:text(2, y, ui.pad("Screen", 14) .. ui.pad("Role", 10) .. ui.pad("Size", 10) .. "Scale", T.muted, T.bg)
    for i, s in ipairs(ccos.screens()) do
      g:text(2, y + i, ui.pad(s.name, 14), T.text, T.bg)
      g:text(16, y + i, ui.pad(s.role, 10), (s.role == "desktop" or s.role == "mirror") and T.accent or T.accent2, T.bg)
      g:text(26, y + i, ui.pad((s.w or 0) .. "x" .. (s.h or 0), 10), T.text, T.bg)
      g:text(36, y + i, s.scale and tostring(s.scale) or "-", T.muted, T.bg)
    end
    g:text(2, h, "Change roles in Settings, or with the `screen` command.", T.muted, T.bg)
  end
end

ui.run(app)
