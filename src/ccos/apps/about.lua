-- About: the logo, what this computer is, and the shortcuts.
local ui = ccos.ui
local T = ui.T
local gfx = ccos.gfx
local floor = math.floor

local SHORTCUTS = {
  { "F2", "Back to Start" }, { "F1 / Alt+A", "AI Agent" }, { "Type on Start", "Search apps" },
  { "Esc / Backspace", "Back out of a page" }, { "Left / Right", "Pan Start and lists" },
  { "Enter", "Open the top search result" }, { "Ctrl+T", "Stop the app in front" },
}

local app = { title = "About", list = { scroll = 0 } }

function app:draw(g)
  local w, h = g.w, g.h
  local logo
  for k = 4, 1, -1 do
    logo = gfx.logo(k)
    if gfx.cellsWidth(logo) <= w - 4 and #logo <= floor(h / 3) then break end
  end
  gfx.drawCells(term, floor((w - gfx.cellsWidth(logo)) / 2) + 1, 1, logo)
  local y = #logo + 1
  g:center(y, "ccOS " .. ccos.version .. "  \183  Big Picture for CC: Tweaked", T.muted, T.bg)
  local rows = {}
  rows[#rows + 1] = { head = "This computer" }
  for _, r in ipairs(ccos.sysinfo()) do rows[#rows + 1] = r end
  rows[#rows + 1] = { head = "Shortcuts" }
  for _, s in ipairs(SHORTCUTS) do rows[#rows + 1] = s end
  rows[#rows + 1] = { head = "In a terminal" }
  rows[#rows + 1] = { "help", "every ccOS command" }
  rows[#rows + 1] = { "open music", "open an app by name" }
  rows[#rows + 1] = { "play /music", "play a folder in stereo" }
  g:list(self.list, 3, y + 2, w - 4, h - y - 2, rows, function(r, _, x, ry, rw)
    if r.head then g:header(x, ry, rw, r.head) return end
    g:text(x, ry, ui.pad(r[1], 18), T.accent, T.bg)
    g:text(x + 18, ry, ui.trunc(r[2], rw - 18), T.text, T.bg)
  end)
end

ui.run(app)
