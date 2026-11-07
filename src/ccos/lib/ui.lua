-- ccOS app toolkit: themed drawing, buttons, scrolling lists and an
-- event loop. Apps are ordinary CC programs drawing to `term`; this keeps
-- them short and consistent.

local ui = {}
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local T = ccos.theme()
ui.T = T
local HEX = ccos.gfx.HEX

function ui.clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end
local clamp = ui.clamp

function ui.trunc(s, w)
  s = tostring(s)
  if w <= 0 then return "" end
  if #s > w then return w > 1 and (s:sub(1, w - 1) .. "\187") or s:sub(1, w) end
  return s
end
local trunc = ui.trunc

function ui.pad(s, w) s = trunc(s, w); return s .. (" "):rep(w - #s) end
function ui.padL(s, w) s = trunc(s, w); return (" "):rep(w - #s) .. s end

function ui.wrap(text, w)
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
  return lines
end

function ui.bytes(n)
  if type(n) ~= "number" then return tostring(n) end
  if n < 1024 then return floor(n) .. " B" end
  if n < 1048576 then return ("%.1f KB"):format(n / 1024) end
  return ("%.1f MB"):format(n / 1048576)
end

function ui.time(sec)
  sec = floor(sec or 0)
  if sec >= 3600 then return ("%d:%02d:%02d"):format(floor(sec / 3600), floor(sec / 60) % 60, sec % 60) end
  return ("%d:%02d"):format(floor(sec / 60), sec % 60)
end

function ui.touch() return ccos.isTouch() end

------------------------------------------------------------------------
-- Drawing context: one per app, rebuilt each frame
------------------------------------------------------------------------

local G = {}
G.__index = G

function ui.context() return setmetatable({ hits = {}, scrolls = {} }, G) end

function G:reset()
  self.hits, self.scrolls = {}, {}
  self.w, self.h = term.getSize()
end

function G:text(x, y, s, fg, bg)
  if y < 1 or y > self.h then return end
  s = tostring(s)
  if x < 1 then s = s:sub(2 - x); x = 1 end
  s = s:sub(1, max(0, self.w - x + 1))
  term.setCursorPos(x, y)
  term.setTextColor(fg or T.text)
  term.setBackgroundColor(bg or T.bg)
  term.write(s)
end

function G:fill(x, y, w, h, bg)
  local right, bottom = min(self.w, x + w - 1), min(self.h, y + h - 1)
  x, y = max(1, x), max(1, y)
  w, h = right - x + 1, bottom - y + 1
  if w <= 0 or h <= 0 then return end
  term.setBackgroundColor(bg)
  local line = (" "):rep(w)
  for yy = y, y + h - 1 do
    term.setCursorPos(x, yy)
    term.write(line)
  end
end

function G:center(y, s, fg, bg, x, w)
  x, w = x or 1, w or self.w
  s = trunc(s, w)
  self:text(x + floor((w - #s) / 2), y, s, fg, bg)
end

function G:hit(x1, y1, x2, y2, fn)
  x1, y1, x2, y2 = max(1, x1), max(1, y1), min(self.w, x2), min(self.h, y2)
  if x2 < x1 or y2 < y1 then return end
  self.hits[#self.hits + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, fn = fn }
end

function G:hitAt(x, y)
  for i = #self.hits, 1, -1 do
    local h = self.hits[i]
    if x >= h.x1 and x <= h.x2 and y >= h.y1 and y <= h.y2 then return h end
  end
end

function G:onScroll(x1, y1, x2, y2, fn)
  self.scrolls[#self.scrolls + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, fn = fn }
end

-- o: fg, bg, w (minimum width), h (rows), active, disabled, align.
function G:button(x, y, label, fn, o)
  o = o or {}
  local w = min(max(o.w or 0, #label + 2), self.w - x + 1)
  if w <= 0 then return x end
  label = trunc(label, max(1, w - 2))
  local h = o.h or 1
  local bg = o.active and (o.activeBg or T.accent) or (o.bg or T.raised)
  local fg = o.active and (o.activeFg or T.bg) or (o.fg or T.text)
  if o.disabled then fg = T.muted end
  -- A one-row label only centres in an odd number of rows; an even height
  -- keeps its full touch target but draws one row shorter.
  local vh = h % 2 == 0 and h - 1 or h
  self:fill(x, y, w, vh, bg)
  local lx = o.align == "left" and x + 1 or x + floor((w - #label) / 2)
  self:text(lx, y + floor((vh - 1) / 2), trunc(label, w), fg, bg)
  if fn and not o.disabled then self:hit(x, y, x + w - 1, y + h - 1, fn) end
  return x + w
end

-- A row of buttons; items {label, fn, o}. Returns the x after the last.
function G:buttons(x, y, items, gap, h)
  for _, it in ipairs(items) do
    local o = it[3] or {}
    o.h = o.h or h
    x = self:button(x, y, it[1], it[2], o) + (gap or 1)
  end
  return x
end

function G:hbar(x, y, w, frac, color, bg)
  if w <= 0 then return end
  local halves = floor(clamp(frac or 0, 0, 1) * w * 2 + 0.5)
  local full = floor(halves / 2)
  local t, f, b = {}, {}, {}
  local c, k = HEX[color or T.accent], HEX[bg or T.surface]
  for i = 1, w do
    if i <= full then t[i], f[i], b[i] = " ", c, c
    elseif i == full + 1 and halves % 2 == 1 then t[i], f[i], b[i] = "\149", c, k
    else t[i], f[i], b[i] = " ", k, k end
  end
  term.setCursorPos(x, y)
  term.blit(table.concat(t), table.concat(f), table.concat(b))
end

function G:header(x, y, w, text, color, bg)
  text = trunc(text, w)
  self:text(x, y, text, color or T.accent, bg or T.bg)
  if w - #text - 1 > 0 then self:text(x + #text + 1, y, ("\140"):rep(w - #text - 1), T.surface, bg or T.bg) end
end

function G:icon(x, y, name) ccos.gfx.icon(term, x, y, name) end

-- A label and value on one line.
function G:kv(x, y, w, label, value, color, lw)
  lw = lw or min(14, floor(w / 2))
  self:text(x, y, ui.pad(label, lw), T.muted, T.bg)
  self:text(x + lw, y, trunc(value, w - lw), color or T.text, T.bg)
end

-- A scrolling list. state keeps .scroll; row(item, i, x, y, w) draws one
-- row; pick(item, i) runs when a row is tapped.
function G:list(state, x, y, w, h, items, row, pick, rowH)
  rowH = rowH or 1
  local visible = max(1, floor(h / rowH))
  local maxOff = max(0, #items - visible)
  state.scroll = clamp(state.scroll or 0, 0, maxOff)
  local cw = maxOff > 0 and w - (h==1 and 2 or 1) or w
  for i = 1, visible do
    local idx = state.scroll + i
    local it = items[idx]
    if not it then break end
    local ry = y + (i - 1) * rowH
    row(it, idx, x, ry, cw)
    if pick then
      self:hit(x, ry, x + cw - 1, ry + rowH - 1, function() pick(it, idx) end)
    end
  end
  if maxOff > 0 then
    local sx = x + w - 1
    local step = max(1, floor(visible / 2))
    self:fill(sx, y, 1, h, T.surface)
    if h > 2 then
      local track = h - 2
      local th = clamp(floor(track * visible / #items), 1, track)
      local ty = y + 1 + floor((track - th) * state.scroll / maxOff + 0.5)
      self:fill(sx, ty, 1, th, T.muted)
    end
    local upX=h==1 and sx-1 or sx
    self:text(upX, y, "\30", T.text, T.surface)
    self:text(sx, y + h - 1, "\31", T.text, T.surface)
    self:hit(upX, y, upX, y, function() state.scroll = state.scroll - step end)
    self:hit(sx, y + h - 1, sx, y + h - 1, function() state.scroll = state.scroll + step end)
  end
  self:onScroll(x, y, x + w - 1, y + h - 1, function(dir) state.scroll = (state.scroll or 0) + dir end)
end

-- Tabs across the top; returns the next free row.
function G:tabs(x, y, w, names, current, pick, h)
  h = h or 1
  self:fill(x, y, w, h, T.surface)
  local tx = x
  for i, name in ipairs(names) do
    local label = " " .. name .. " "
    local on = i == current
    self:fill(tx, y, #label, h, on and T.bg or T.surface)
    self:text(tx, y + floor((h - 1) / 2), label, on and T.accent or T.text, on and T.bg or T.surface)
    self:hit(tx, y, tx + #label - 1, y + h - 1, function() pick(i) end)
    tx = tx + #label
  end
  return y + h
end

------------------------------------------------------------------------
-- The event loop
------------------------------------------------------------------------

-- app: draw(g) is required; optional init, onKey(key, held), onChar(ch),
-- onPaste(text), onClick(x, y, button), onDrag, onUp, onScroll(dir, x, y),
-- onEvent(ev) (return true to redraw), onTick (every app.tick seconds),
-- onClose (return false to stay open). Set app.quit to leave.
function ui.run(app)
  local g = ui.context()
  app.g = g
  if app.title then ccos.setTitle(app.title) end
  if app.init then app:init() end
  local tick = app.tick and os.startTimer(app.tick)
  local function redraw()
    g:reset()
    term.setBackgroundColor(app.bg or T.bg)
    term.clear()
    term.setCursorBlink(false)
    app:draw(g)
    if ccos.isPocket and ccos.isPocket()and g.focus and #g.hits>0 then
      g.focus=(g.focus-1)%#g.hits+1;local h=g.hits[g.focus]
      term.setCursorPos(h.x1,h.y1);term.setCursorBlink(true)
    end
  end
  redraw()
  while not app.quit do
    local ev = table.pack(os.pullEventRaw())
    local e = ev[1]
    local dirty = false
    if e == "terminate" then
      if not app.onClose or app:onClose() ~= false then break end
    elseif e == "mouse_click" then
      local h = g:hitAt(ev[3], ev[4])
      if h then
        h.fn(ev[3], ev[4], ev[2])
        dirty = true
      elseif app.onClick then
        dirty = app:onClick(ev[3], ev[4], ev[2]) ~= false
      end
    elseif e == "mouse_drag" then
      if app.onDrag then dirty = app:onDrag(ev[3], ev[4], ev[2]) ~= false end
    elseif e == "mouse_up" then
      if app.onUp then dirty = app:onUp(ev[3], ev[4], ev[2]) ~= false end
    elseif e == "mouse_scroll" then
      for i = #g.scrolls, 1, -1 do
        local s = g.scrolls[i]
        if ev[3] >= s.x1 and ev[3] <= s.x2 and ev[4] >= s.y1 and ev[4] <= s.y2 then
          s.fn(ev[2])
          dirty = true
          break
        end
      end
      if not dirty and app.onScroll then dirty = app:onScroll(ev[2], ev[3], ev[4]) ~= false end
    elseif e == "key" then
      if ccos.isPocket and ccos.isPocket()and ev[2]==keys.tab then
        if #g.hits>0 then g.focus=(g.focus or 0)%#g.hits+1 end;dirty=true
      elseif ccos.isPocket and ccos.isPocket()and ev[2]==keys.enter and g.focus and g.hits[g.focus]then
        local h=g.hits[g.focus];h.fn(h.x1,h.y1,1);dirty=true
      else
        g.focus=nil
        if app.onKey then dirty = app:onKey(ev[2], ev[3]) ~= false end
      end
    elseif e == "char" then
      if app.onChar then dirty = app:onChar(ev[2]) ~= false end
    elseif e == "paste" then
      if app.onPaste then dirty = app:onPaste(ev[2]) ~= false
      elseif app.onChar then
        for i = 1, #ev[2] do app:onChar(ev[2]:sub(i, i)) end
        dirty = true
      end
    elseif e == "term_resize" or e == "ccos_theme" then
      dirty = true
    elseif e == "timer" and ev[2] == tick then
      tick = os.startTimer(app.tick)
      dirty = not app.onTick or app:onTick() ~= false
    end
    if app.onEvent and app:onEvent(ev) then dirty = true end
    if dirty and not app.quit then redraw() end
  end
end

return ui
