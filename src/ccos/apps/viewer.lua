-- Viewer: read a text file, with Lua highlighting, line numbers and
-- buttons to edit, run or print it.
local ui = ccos.ui
local T = ui.T
local floor, max, min = math.floor, math.max, math.min
local path = ...

local KEYWORDS = {}
for w in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%S+") do
  KEYWORDS[w] = true
end

-- Colour runs for one line of Lua: {{text, colour}, ...}.
local function highlight(line, state)
  local out = {}
  local i, n = 1, #line
  local function push(s, c) out[#out + 1] = { s, c } end
  if state.long then
    local e = line:find("]]", 1, true)
    if not e then push(line, T.muted); return out end
    push(line:sub(1, e + 1), state.long)
    state.long = nil
    i = e + 2
  end
  while i <= n do
    local c = line:sub(i, i)
    local rest = line:sub(i)
    if rest:sub(1, 4) == "--[[" then
      local e = line:find("]]", i + 4, true)
      if e then push(line:sub(i, e + 1), T.muted); i = e + 2 else push(rest, T.muted); state.long = T.muted; break end
    elseif rest:sub(1, 2) == "--" then
      push(rest, T.muted); break
    elseif rest:sub(1, 2) == "[[" then
      local e = line:find("]]", i + 2, true)
      if e then push(line:sub(i, e + 1), T.ok); i = e + 2 else push(rest, T.ok); state.long = T.ok; break end
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local d = line:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == c then break
        else j = j + 1 end
      end
      push(line:sub(i, j), T.ok)
      i = j + 1
    elseif c:match("%d") then
      local s = rest:match("^0[xX]%x+") or rest:match("^%d+%.?%d*[eE]?[-+]?%d*")
      push(s, T.orange)
      i = i + #s
    elseif c:match("[%a_]") then
      local word = rest:match("^[%w_]+")
      local col = KEYWORDS[word] and T.accent2 or ((word == "self" or word == "_G") and T.hot or T.text)
      if not KEYWORDS[word] and line:sub(i + #word):match("^%s*%(") then col = T.info end
      push(word, col)
      i = i + #word
    else
      local s = rest:match("^[^%w_\"'%-%[]+") or c
      push(s, T.accent)
      i = i + #s
    end
  end
  return out
end

local app = { title = "Viewer", scroll = 0, hscroll = 0 }

function app:load()
  self.lines, self.err = {}, nil
  local h = path and fs.open(path, "r")
  if not h then
    self.err = path and ("Can't open " .. path) or "No file given"
    return
  end
  local text = h.readAll() or ""
  h.close()
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    self.lines[#self.lines + 1] = (line:gsub("\t", "  "):gsub("\r", ""))
  end
  if #self.lines > 1 and self.lines[#self.lines] == "" then self.lines[#self.lines] = nil end
  self.size = fs.getSize(path)
  self.lua = path:match("%.lua$") ~= nil
  -- highlight once, carrying long strings and comments across lines
  self.runs = {}
  local state = {}
  for i, l in ipairs(self.lines) do
    self.runs[i] = self.lua and highlight(l, state) or { { l, T.text } }
  end
end

function app:init()
  self:load()
  if path then ccos.setTitle("Viewer - " .. fs.getName(path)) end
end

-- Rows on screen: each source line, wrapped if asked.
function app:rows(width)
  local rows = {}
  for i, runs in ipairs(self.runs or {}) do
    if not self.wrap then
      rows[#rows + 1] = { n = i, runs = runs, from = 1 }
    else
      local len = #self.lines[i]
      local from = 1
      repeat
        rows[#rows + 1] = { n = from == 1 and i or nil, runs = runs, from = from, to = from + width - 1 }
        from = from + width
      until from > len
    end
  end
  return rows
end

function app:draw(g)
  local w, h = g.w, g.h
  local touch = ui.touch()
  local barH = touch and 3 or 1
  g:fill(1, 1, w, barH, T.surface)
  local name = path and fs.getName(path) or "Viewer"
  local by = 1 + floor((barH - 1) / 2)
  g:text(2, by, ui.trunc(name, 24), T.text, T.surface)
  local acts = {
    { "Edit", function() ccos.open("edit", path) end },
    { self.wrap and "No wrap" or "Wrap", function() self.wrap = not self.wrap; self.scroll = 0 end },
    { "Print", function()
      local hnd = fs.open(path, "r")
      local text = hnd and hnd.readAll() or ""
      if hnd then hnd.close() end
      local ok, err = ccos.printText(name, text)
      self.msg = ok and ("Printed " .. err .. " page(s)") or err
    end },
  }
  if self.lua then table.insert(acts, 1, { "Run", function() ccos.runFile(path) end, { fg = T.ok } }) end
  local total = 0
  for _, a in ipairs(acts) do total = total + #a[1] + 3 end
  if not self.err then g:buttons(w - total + 1, 1, acts, 1, barH) end
  if self.err then
    g:text(2, barH + 2, self.err, T.danger, T.bg)
    return
  end
  local gutter = #tostring(#self.lines) + 2
  local textW = w - gutter - 1
  local rows = self:rows(textW)
  local view = h - barH - 1
  self.view, self.total = view, #rows
  self.scroll = ui.clamp(self.scroll, 0, max(0, #rows - view))
  for r = 1, view do
    local row = rows[self.scroll + r]
    if not row then break end
    local y = barH + r
    if row.n then g:text(1, y, ui.padL(tostring(row.n), gutter - 1) .. " ", T.muted, T.surface)
    else g:fill(1, y, gutter, 1, T.surface) end
    -- draw runs from column row.from (plus horizontal scroll when not wrapping)
    local start = row.from + (self.wrap and 0 or self.hscroll)
    local stop = row.to or (start + textW - 1)
    local col, x = 1, gutter + 2
    for _, run in ipairs(row.runs) do
      local s, c = run[1], run[2]
      local a, b = col, col + #s - 1
      local from, to = math.max(a, start), math.min(b, stop)
      if from <= to then
        g:text(x, y, s:sub(from - a + 1, to - a + 1), c, T.bg)
        x = x + (to - from + 1)
      end
      col = b + 1
    end
  end
  -- scroll bar and status
  g:fill(1, h, w, 1, T.surface)
  local info = ("%d lines  \183  %s"):format(#self.lines, ui.bytes(self.size or 0))
  if self.msg then info = self.msg end
  g:text(2, h, ui.trunc(info, w - 22), T.muted, T.surface)
  local pct = #rows > view and floor(self.scroll / (#rows - view) * 100 + 0.5) .. "%" or "All"
  local bx = w - 18
  bx = g:button(bx, h, "\30", function() self.scroll = self.scroll - max(1, view - 1) end, { bg = T.surface })
  bx = g:button(bx, h, "\31", function() self.scroll = self.scroll + max(1, view - 1) end, { bg = T.surface })
  g:text(bx + 1, h, ui.padL(pct, 5), T.text, T.surface)
  g:onScroll(1, barH + 1, w, h - 1, function(d) self.scroll = self.scroll + d * 3 end)
end

function app:onKey(k)
  local view = self.view or 10
  if k == keys.down then self.scroll = self.scroll + 1
  elseif k == keys.up then self.scroll = self.scroll - 1
  elseif k == keys.pageDown or k == keys.space then self.scroll = self.scroll + view - 1
  elseif k == keys.pageUp then self.scroll = self.scroll - view + 1
  elseif k == keys.home then self.scroll = 0
  elseif k == keys["end"] then self.scroll = self.total or 0
  elseif k == keys.right and not self.wrap then self.hscroll = self.hscroll + 4
  elseif k == keys.left and not self.wrap then self.hscroll = math.max(0, self.hscroll - 4)
  elseif k == keys.f5 then self:load()
  else return false end
end

ui.run(app)
