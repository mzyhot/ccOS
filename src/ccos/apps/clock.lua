-- Clock: the time large, a stopwatch and a countdown timer.
local ui = ccos.ui
local T = ui.T
local gfx = ccos.gfx
local floor, max, min = math.floor, math.max, math.min
local function now() return os.epoch("utc") end

local args = {...}
local app = { title = "Clock", tick = 0.1, tab = tonumber(args[1]) or 1,
  sw = { running = false, acc = 0, start = 0, laps = {} },
  timer = { total = 300, left = 300, running = false, ends = 0 } }

local function big(g, text, y, maxH, colors)
  local w = g.w
  local cells
  for k = 5, 1, -1 do
    cells = gfx.pixelText(text, k, colors, "f")
    if gfx.cellsWidth(cells) <= w - 2 and #cells <= maxH then break end
  end
  gfx.drawCells(term, floor((w - gfx.cellsWidth(cells)) / 2) + 1, y, cells)
  return #cells
end

local function stopwatchMs(sw) return sw.acc + (sw.running and (now() - sw.start) or 0) end
local function fmtWatch(ms)
  local s = floor(ms / 1000)
  return (ccos.config("leadingZero") and "%02d:%02d.%d" or "%d:%02d.%d"):format(floor(s / 60), s % 60, floor(ms / 100) % 10)
end

function app:draw(g)
  local w, h = g.w, g.h
  local touch = ui.touch()
  local bh = touch and 3 or 1
  local y = g:tabs(1, 1, w, { "Clock", "Stopwatch", "Timer" }, self.tab, function(i) self.tab = i end, bh) + 1
  local room = h - y - (touch and 5 or 3)
  if self.tab == 1 then
    local used = big(g, ccos.clock(true), y, room, { "0" })
    g:center(y + used + 1, ccos.date("%A %d %B %Y"), T.muted, T.bg)
    local t = os.time("ingame")
    g:center(y + used + 2, "In game: "..ccos.gameClock(), T.accent, T.bg)
    g:center(y + used + 3, ccos.timezoneLabel(), T.muted, T.bg)
  elseif self.tab == 2 then
    local sw = self.sw
    local used = big(g, fmtWatch(stopwatchMs(sw)), y, room, { "9" })
    local by = y + used + 1
    g:buttons(floor(w / 2) - 14, by, {
      { sw.running and "Stop" or "Start", function()
        if sw.running then sw.acc = sw.acc + now() - sw.start; sw.running = false
        else sw.start = now(); sw.running = true end
      end, { active = true, w = 9 } },
      { "Lap", function() if sw.running then table.insert(sw.laps, 1, stopwatchMs(sw)) end end, { w = 8 } },
      { "Reset", function() sw.acc, sw.running, sw.laps = 0, false, {} end, { w = 8 } },
    }, 1, bh)
    for i, lap in ipairs(sw.laps) do
      local ly = by + bh + i
      if ly > h then break end
      g:center(ly, ("Lap %d   %s"):format(#sw.laps - i + 1, fmtWatch(lap)), T.muted, T.bg)
    end
  else
    local tm = self.timer
    local left = tm.running and max(0, (tm.ends - now()) / 1000) or tm.left
    local s = floor(left + 0.999)
    local used = big(g, (ccos.config("leadingZero") and "%02d:%02d" or "%d:%02d"):format(floor(s / 60), s % 60), y, room, { tm.running and "5" or "0" })
    local by = y + used + 1
    local bx = floor(w / 2) - 22
    bx = g:buttons(bx, by, {
      { "-1m", function() if not tm.running then tm.left = max(10, tm.left - 60); tm.total = tm.left end end },
      { "+1m", function() if not tm.running then tm.left = tm.left + 60; tm.total = tm.left end end },
      { "+5m", function() if not tm.running then tm.left = tm.left + 300; tm.total = tm.left end end },
      { tm.running and "Pause" or "Start", function()
        if tm.running then tm.left = max(0, (tm.ends - now()) / 1000); tm.running = false
        else tm.ends = now() + tm.left * 1000; tm.running = true end
      end, { active = true, w = 9 } },
      { "Reset", function() tm.running = false; tm.left = tm.total end },
    }, 1, bh)
    g:hbar(floor(w / 2) - 22, by + bh + 1, 44, tm.total > 0 and 1 - left / tm.total or 0, T.ok, T.surface)
  end
end

function app:onTick()
  local tm = self.timer
  if tm.running and now() >= tm.ends then
    tm.running, tm.left = false, tm.total
    ccos.sfx("alarm")
    ccos.notify("Timer done", ("%d:%02d is up"):format(floor(tm.total / 60), floor(tm.total) % 60), { icon = "clock", color = T.ok })
  end
  -- redraw only what moves: the clock each second, running watches always
  if self.tab == 1 then
    local s = ccos.date("%S")
    if s == self.lastS then return false end
    self.lastS = s
  elseif self.tab == 2 and not self.sw.running then
    return false
  elseif self.tab == 3 and not tm.running then
    return false
  end
end

function app:onKey(k)
  if k == keys.tab then self.tab = self.tab % 3 + 1 else return false end
end

ui.run(app)
