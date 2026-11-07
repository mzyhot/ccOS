-- Calculator: tap or type a sum; ans holds the last answer.
local ui = ccos.ui
local T = ui.T
local floor, max = math.floor, math.max

local ENV = { ans = 0 }
for k, v in pairs(math) do ENV[k] = v end
ENV.pi, ENV.e = math.pi, math.exp(1)
ENV.ln, ENV.log = math.log, function(x, b) return math.log(x, b or 10) end

local KEYS = {
  { "C", "(", ")", "\27" },
  { "7", "8", "9", "/" },
  { "4", "5", "6", "*" },
  { "1", "2", "3", "-" },
  { "0", ".", "^", "+" },
  { "sqrt", "pi", "ans", "=" },
}

local app = { title = "Calculator", expr = "", history = {} }

local function format(v)
  if type(v) ~= "number" then return tostring(v) end
  if v ~= v then return "not a number" end
  if v == math.huge or v == -math.huge then return v > 0 and "infinity" or "-infinity" end
  if v == floor(v) and math.abs(v) < 1e15 then return ("%d"):format(v) end
  return (("%.10g"):format(v))
end

function app:evaluate()
  if self.expr == "" then return end
  local fn, err = load("return " .. self.expr, "sum", "t", ENV)
  if not fn then self.result, self.err = nil, "Check the sum"; return end
  local ok, v = pcall(fn)
  if not ok or type(v) ~= "number" then self.result, self.err = nil, "Can't work that out"; return end
  ENV.ans = v
  table.insert(self.history, 1, { self.expr, format(v) })
  while #self.history > 30 do table.remove(self.history) end
  self.result, self.err = format(v), nil
  self.expr = ""
end

function app:press(k)
  if k == "C" then self.expr, self.result, self.err = "", nil, nil
  elseif k == "\27" then self.expr = self.expr:sub(1, -2)
  elseif k == "=" then self:evaluate()
  elseif k == "sqrt" then self.expr = self.expr .. "sqrt("
  else
    if self.expr == "" and self.result and k:match("^[%+%-%*/%^]$") then self.expr = "ans" end
    self.expr = self.expr .. k
  end
end

function app:draw(g)
  local w, h = g.w, g.h
  local histW = w >= 52 and 20 or 0
  local cw = w - histW
  -- display
  g:fill(1, 1, cw, 4, T.surface)
  g:text(2, 1, ui.padL(ui.trunc(self.expr, cw - 3), cw - 3), T.muted, T.surface)
  local shown = self.err or self.result or (self.expr == "" and "0" or "")
  g:text(2, 3, ui.padL(ui.trunc(shown, cw - 3), cw - 3), self.err and T.danger or T.text, T.surface)
  -- keypad
  local rows = #KEYS
  local kh = max(1, floor((h - 5) / rows))
  local kw = floor((cw - 1) / 4)
  for r, row in ipairs(KEYS) do
    for c, k in ipairs(row) do
      local x, y = 1 + (c - 1) * kw + 1, 5 + (r - 1) * kh + 1
      local isOp = k:match("^[%+%-%*/%^=]$")
      local bg = (k == "=") and T.accent or (isOp and T.raised or T.surface)
      local fg = (k == "=") and T.bg or (k == "C" and T.danger or T.text)
      g:button(x, y, k, function() self:press(k) end, { w = kw - 1, h = max(1, kh - 1), bg = bg, fg = fg })
    end
  end
  -- history
  if histW > 0 then
    local hx = cw + 2
    g:header(hx, 1, histW - 2, "History")
    for i, item in ipairs(self.history) do
      local y = 1 + i * 2
      if y + 1 > h then break end
      g:text(hx, y, ui.trunc(item[1], histW - 2), T.muted, T.bg)
      g:text(hx, y + 1, ui.trunc("= " .. item[2], histW - 2), T.text, T.bg)
      g:hit(hx, y, w, y + 1, function() self.expr = self.expr .. item[2] end)
    end
  end
end

function app:onChar(ch)
  if ch:match("[%d%.%+%-%*/%^%(%)%%a-z,]") then self.expr = self.expr .. ch
  elseif ch == "=" then self:evaluate()
  else return false end
end

function app:onKey(k)
  if k == keys.enter or k == keys.numPadEnter then self:evaluate()
  elseif k == keys.backspace then self.expr = self.expr:sub(1, -2)
  elseif k == keys.delete then self.expr, self.result, self.err = "", nil, nil
  else return false end
end

ui.run(app)
