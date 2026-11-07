-- Print Center: the printer's paper and ink, and things to print.
local ui = ccos.ui
local T = ui.T
local floor, max, min = math.floor, math.max, math.min

local app = { title = "Print Center", tick = 2, jobs = {} }

local function printer()
  return (ccos.hw().printers or {})[1]
end

function app:job(name, ok, info)
  table.insert(self.jobs, 1, { name = name, ok = ok, info = info, t = ccos.clock(false) })
  while #self.jobs > 20 do table.remove(self.jobs) end
end

function app:run(name, fn)
  self.busy = name
  self.g:reset()
  term.setBackgroundColor(T.bg)
  term.clear()
  self:draw(self.g)
  local ok, res = fn()
  self.busy = nil
  self:job(name, ok, ok and (res .. " page" .. (res == 1 and "" or "s")) or res)
end

local function report()
  local lines = { "CCOS SYSTEM REPORT", ccos.date("%Y-%m-%d ")..ccos.clock(false), "" }
  for _, row in ipairs(ccos.sysinfo()) do lines[#lines + 1] = row[1] .. ": " .. row[2] end
  return table.concat(lines, "\n")
end

local function testPage()
  local lines = { "PRINTER TEST PAGE", "" }
  lines[#lines + 1] = ("1234567890"):rep(3):sub(1, 25)
  lines[#lines + 1] = ("-"):rep(25)
  lines[#lines + 1] = "The quick brown fox jumps over the lazy dog."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Printed by ccOS " .. ccos.version
  return table.concat(lines, "\n")
end

function app:draw(g)
  local w, h = g.w, g.h
  local touch = ui.touch()
  local bh = touch and 3 or 1
  local p = printer()
  g:fill(1, 1, w, 1, T.surface)
  g:text(2, 1, "\20 Print Center", T.text, T.surface)
  local y = 3
  if not p then
    g:text(2, y, "No printer attached.", T.warn, T.bg)
    g:text(2, y + 1, "Place one next to the computer or on a wired modem.", T.muted, T.bg)
  else
    g:kv(2, y, w - 3, "Printer", p.name)
    g:text(2, y + 1, "Paper", T.muted, T.bg)
    g:hbar(16, y + 1, 20, (p.paper or 0) / 64, (p.paper or 0) < 4 and T.warn or T.ok, T.surface)
    g:text(38, y + 1, tostring(p.paper or 0) .. " sheets", T.text, T.bg)
    g:text(2, y + 2, "Ink", T.muted, T.bg)
    g:hbar(16, y + 2, 20, (p.ink or 0) / 64, (p.ink or 0) < 4 and T.warn or T.accent, T.surface)
    g:text(38, y + 2, tostring(p.ink or 0) .. " dye", T.text, T.bg)
  end
  y = y + 4
  g:header(2, y, w - 3, "Print")
  y = y + 1
  local acts = {
    { "A file", function()
      local path = ccos.prompt("Print a file", "Path of the file", "")
      if not path or path == "" then return end
      if path:sub(1, 1) ~= "/" then path = "/" .. path end
      local f = fs.open(path, "r")
      if not f then self:job(path, false, "can't read it"); return end
      local text = f.readAll()
      f.close()
      self:run(fs.getName(path), function() return ccos.printText(fs.getName(path), text) end)
    end },
    { "A note", function()
      local text = ccos.prompt("Print a note", "What should it say?", "")
      if text and text ~= "" then self:run("Note", function() return ccos.printText("Note", text) end) end
    end },
    { "A banner", function()
      local text = ccos.prompt("Print a banner", "Big letters, one per page", "HELLO")
      if text and text ~= "" then self:run("Banner " .. text, function() return ccos.printBanner(text) end) end
    end },
    { "System report", function() self:run("System report", function() return ccos.printText("Report", report()) end) end },
    { "Test page", function() self:run("Test page", function() return ccos.printText("Test page", testPage()) end) end },
  }
  local x = 2
  for _, a in ipairs(acts) do
    if x + #a[1] + 2 > w then x = 2; y = y + bh + 1 end
    x = g:button(x, y, a[1], p and a[2] or nil, { h = bh, disabled = not p }) + 1
  end
  y = y + bh + 1
  if self.busy then g:text(2, y, "Printing " .. self.busy .. "...", T.accent, T.bg) end
  y = y + 1
  g:header(2, y, w - 3, "Recent jobs")
  for i, j in ipairs(self.jobs) do
    if y + i > h then break end
    g:text(2, y + i, j.t, T.muted, T.bg)
    g:text(8, y + i, ui.trunc(j.name, w - 30), T.text, T.bg)
    g:text(w - 20, y + i, ui.trunc(j.info, 19), j.ok and T.ok or T.danger, T.bg)
  end
  if #self.jobs == 0 then g:text(2, y + 1, "Nothing printed yet", T.muted, T.bg) end
end

ui.run(app)
