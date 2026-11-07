-- Piano: two octaves of note-block pitches spread across the two
-- speakers, low notes on the left and high on the right.
local ui = ccos.ui
local T = ui.T
local A = ccos.audio
local floor, max, min = math.floor, math.max, math.min
local function now() return os.epoch("utc") end

local NAMES = { "F#", "G", "G#", "A", "A#", "B", "C", "C#", "D", "D#", "E", "F" }
local INSTRUMENTS = { "harp", "bell", "chime", "flute", "guitar", "xylophone", "iron_xylophone", "pling",
  "bit", "banjo", "bass", "didgeridoo", "cow_bell", "basedrum", "snare", "hat" }
-- Keyboard: z x c v b n m / q w e r t y u for the white keys, and the
-- rows above them for the black keys.
local KEYMAP = {
  z = 1, s = 2, x = 3, d = 4, c = 5, v = 6, g = 7, b = 8, h = 9, n = 10, m = 11, k = 12,
  q = 13, ["2"] = 14, w = 15, ["3"] = 16, e = 17, r = 18, ["5"] = 19, t = 20, ["6"] = 21, y = 22, u = 23, ["8"] = 24,
  a = 0,
}
local ODE = { { 10, 300 }, { 10, 300 }, { 11, 300 }, { 13, 300 }, { 13, 300 }, { 11, 300 }, { 10, 300 }, { 8, 300 },
  { 6, 300 }, { 6, 300 }, { 8, 300 }, { 10, 300 }, { 10, 450 }, { 8, 150 }, { 8, 600 } }

local function isBlack(p) local n = NAMES[p % 12 + 1]; return n:find("#") ~= nil end

local app = { title = "Piano", tick = 0.1, inst = 1, vol = 1.2, spread = 0.8, lit = {}, rec = nil, take = {}, play = nil }

function app:note(p, quiet)
  local pan = ((p / 24) * 2 - 1) * self.spread
  A.note(INSTRUMENTS[self.inst], p, pan, self.vol)
  self.lit[p] = now() + 220
  if self.recording and not quiet then
    self.take[#self.take + 1] = { t = now() - self.recording, p = p, inst = self.inst }
  end
end

function app:startPlayback(seq)
  self.play = { seq = seq, i = 1, t0 = now() }
end

function app:onTick()
  local t = now()
  local pl = self.play
  if pl then
    while pl.seq[pl.i] and pl.seq[pl.i].t <= t - pl.t0 do
      local ev = pl.seq[pl.i]
      local keep = self.inst
      if ev.inst then self.inst = ev.inst end
      self:note(ev.p, true)
      self.inst = keep
      pl.i = pl.i + 1
    end
    if not pl.seq[pl.i] then self.play = nil end
  end
  for p, until_ in pairs(self.lit) do if until_ < t then self.lit[p] = nil end end
  return true
end

-- White keys left to right, each with its pitch.
local WHITE = {}
for p = 0, 24 do if not isBlack(p) then WHITE[#WHITE + 1] = p end end

function app:draw(g)
  local w, h = g.w, g.h
  local touch = ui.touch()
  local bh = touch and h >= 18 and 3 or 1
  local twoRows = w < 100
  local controlsH = twoRows and (bh * 2 + 1) or bh
  -- controls
  g:fill(1, 1, w, controlsH, T.surface)
  local x = 2
  x = g:button(x, 1, "<", function() self.inst = (self.inst - 2) % #INSTRUMENTS + 1 end, { h = bh })
  g:text(x + 1, 1 + floor((bh - 1) / 2), ui.pad(INSTRUMENTS[self.inst], 14), T.accent, T.surface)
  x = g:button(x + 16, 1, ">", function() self.inst = self.inst % #INSTRUMENTS + 1 end, { h = bh }) + 2
  x = g:button(x, 1, "Vol -", function() self.vol = max(0.2, self.vol - 0.2) end, { h = bh }) + 1
  x = g:button(x, 1, "Vol +", function() self.vol = min(3, self.vol + 0.2) end, { h = bh }) + 1
  local actionY = twoRows and (bh + 2) or 1
  if twoRows then x = 2 end
  x = g:button(x, actionY, "Spread " .. floor(self.spread * 100) .. "%", function()
    self.spread = self.spread >= 1 and 0 or self.spread + 0.25
  end, { h = bh }) + 1
  local rows = { { self.recording and "Stop" or "Rec", function()
    if self.recording then self.recording = nil else self.take, self.recording = {}, now() end
  end, { active = self.recording ~= nil, activeBg = T.danger } },
    { "Play take", function() if #self.take > 0 then self:startPlayback(self.take) end end, { disabled = #self.take == 0 } },
    { "Demo", function()
      local seq, t = {}, 0
      for _, n in ipairs(ODE) do seq[#seq + 1] = { t = t, p = n[1] }; t = t + n[2] end
      self:startPlayback(seq)
    end } }
  local need = 0
  for _, r in ipairs(rows) do need = need + #r[1] + 3 end
  if x + need <= w then g:buttons(w - need + 1, actionY, rows, 1, bh) end
  -- keys
  local top = controlsH + 2
  local kh = h - top
  local kw = max(2, floor((w - 2) / #WHITE))
  local kx = floor((w - kw * #WHITE) / 2) + 1
  local blackH = max(2, floor(kh * 0.6))
  g:fill(kx - 1, top, kw * #WHITE + 1, kh, T.muted)
  for i, p in ipairs(WHITE) do
    local x0 = kx + (i - 1) * kw
    local lit = self.lit[p]
    g:fill(x0, top, kw - 1, kh, lit and T.accent or T.text)
    if kw >= 3 then
      local name = NAMES[p % 12 + 1]
      g:text(x0 + floor((kw - 1 - #name) / 2), top + kh - 1, name, lit and T.bg or T.muted, lit and T.accent or T.text)
    end
    g:hit(x0, top + blackH, x0 + kw - 2, top + kh - 1, function() self:note(p) end)
    g:hit(x0, top, x0 + kw - 2, top + kh - 1, function() self:note(p) end)
  end
  -- black keys sit over the gap after the white key below them
  local bw = max(1, floor(kw * 0.6))
  for p = 0, 24 do
    if isBlack(p) then
      local below = nil
      for i, wp in ipairs(WHITE) do if wp == p - 1 then below = i end end
      local cx
      if below then cx = kx + below * kw - floor(bw / 2) - 1 else cx = kx - floor(bw / 2) end
      if p == 24 then cx = kx + #WHITE * kw - floor(bw / 2) - 1 end
      cx = max(kx, min(cx, kx + #WHITE * kw - bw))
      local lit = self.lit[p]
      g:fill(cx, top, bw, blackH, lit and T.accent2 or T.surface)
      if blackH > 2 and not lit then g:fill(cx, top + blackH - 1, bw, 1, T.raised) end
      g:hit(cx, top, cx + bw - 1, top + blackH - 1, function() self:note(p) end)
    end
  end
  if A.info().speakers == 0 then
    g:center(top + kh - 2, " No speakers attached ", T.bg, T.warn)
  end
end

function app:onChar(ch)
  local p = KEYMAP[ch:lower()]
  if p then self:note(p) else return false end
end

ui.run(app)
