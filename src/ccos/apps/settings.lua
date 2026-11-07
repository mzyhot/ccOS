-- Settings: look, sound, screens, clock and desktop.
local ui = ccos.ui
local T = ui.T
local floor, max, min = math.floor, math.max, math.min

local SECTIONS = { "Appearance", "Sound", "Screens", "Clock & panel", "Desktop", "AI Agent", "System" }
local IDLE = { 0, 60, 300, 600, 1800 }

local app = { title = "Settings", section = 1, scroll = { scroll = 0 } }

local function cfg(k) return ccos.config(k) end
local function set(k, v) ccos.config(k, v) end

local function onOff(v) return v and "On" or "Off" end

function app:rows()
  local rows = {}
  local function head(text) rows[#rows + 1] = { head = text } end
  local function row(label, value, actions, note) rows[#rows + 1] = { label = label, value = value, actions = actions, note = note } end
  local function toggle(label, key, note)
    row(label, onOff(cfg(key)), { { cfg(key) and "Turn off" or "Turn on", function() set(key, not cfg(key)) end } }, note)
  end
  local s = SECTIONS[self.section]
  if s == "Appearance" then
    head("Theme")
    local order, themes = ccos.themes()
    for _, id in ipairs(order) do
      local on = cfg("theme") == id
      row(themes[id].name, on and "In use" or "", on and {} or { { "Use", function() set("theme", id) end } })
    end
    head("Wallpaper")
    for _, wp in ipairs(ccos.wallpapers()) do
      local on = cfg("wallpaper") == wp
      row(wp:sub(1, 1):upper() .. wp:sub(2), on and "In use" or "", on and {} or { { "Use", function() set("wallpaper", wp) end } })
    end
    head("Windows")
    toggle("Shadows", "shadows")
  elseif s == "Sound" then
    head("Speakers")
    local info = ccos.audio.info()
    local spk = ccos.audio.spk
    row("Found", info.speakers >= 2 and "Two: stereo" or (info.speakers == 1 and "One: mono" or "None"), {})
    if info.speakers >= 1 then
      row("Left", tostring(spk.l), { { "Test", function() ccos.audio.note("bell", 12, -1, 1.5) end } })
      row("Right", tostring(spk.r), { { "Test", function() ccos.audio.note("bell", 12, 1, 1.5) end } })
    end
    toggle("Swap left and right", "swapSpeakers", "If the test sounds come from the wrong side")
    head("Volume")
    local mv = floor((cfg("musicVolume") or 0) * 100 + 0.5)
    row("Music", mv .. "%", { { "-", function() ccos.audio.setVolume(cfg("musicVolume") - 0.1) end },
      { "+", function() ccos.audio.setVolume(cfg("musicVolume") + 0.1) end } })
    local b = floor((cfg("balance") or 0) * 100 + 0.5)
    row("Balance", b == 0 and "Centre" or (b < 0 and (-b .. "% left") or (b .. "% right")), {
      { "L", function() ccos.audio.setBalance(cfg("balance") - 0.1) end },
      { "Centre", function() ccos.audio.setBalance(0) end },
      { "R", function() ccos.audio.setBalance(cfg("balance") + 0.1) end } })
    local uv = floor((cfg("uiVolume") or 0) * 100 + 0.5)
    row("System sounds", uv .. "%", { { "-", function() set("uiVolume", math.max(0, cfg("uiVolume") - 0.1)); ccos.sfx("notify") end },
      { "+", function() set("uiVolume", math.min(1, cfg("uiVolume") + 0.1)); ccos.sfx("notify") end } })
    toggle("Play system sounds", "sounds")
    toggle("Click on touch", "touchSounds")
  elseif s == "Screens" then
    head("Displays")
    for _, sc in ipairs(ccos.screens()) do
      if sc.kind == "term" then
        row("Computer", ("%dx%d, desktop"):format(sc.w or 0, sc.h or 0), {})
      else
        local roles = { picture = "mirror", mirror = "desktop", desktop = "panel", panel = "off", off = "picture" }
        row(sc.name, ("%s, %dx%d, scale %s"):format(sc.role, sc.w or 0, sc.h or 0, tostring(sc.scale or "-")), {
          { "Role", function() ccos.setScreen(sc.name, roles[sc.role]) end },
          { "Scale -", function()
            local cur = type(sc.scaleCfg) == "number" and sc.scaleCfg or (sc.scale or 1)
            ccos.setScreen(sc.name, nil, math.max(0.5, cur - 0.5))
          end },
          { "Scale +", function()
            local cur = type(sc.scaleCfg) == "number" and sc.scaleCfg or (sc.scale or 1)
            ccos.setScreen(sc.name, nil, math.min(5, cur + 0.5))
          end },
          { "Auto", function() ccos.setScreen(sc.name, nil, "auto") end },
        })
      end
    end
    rows[#rows + 1] = { note = "Picture is the compact touch tools interface. No keyboard needed." }
    rows[#rows + 1] = { note = "Mirror shows the computer's screen, and taps on it act there." }
    rows[#rows + 1] = { note = "Desktop is a widescreen desktop of its own. Panel shows the time, music and devices." }
  elseif s == "Clock & panel" then
    head("Clock")
    row("Time zone", cfg("timezone"), {{"Next zone", function()
      local zones=ccos.time.zones;local i=1;for n,z in ipairs(zones)do if z==cfg("timezone")then i=n end end;set("timezone",zones[i%#zones+1])
    end}})
    local offset=cfg("utcOffset")or 0
    row("Fixed UTC offset", offset.." min", {{"-15m",function()set("timezone","fixed");set("utcOffset",math.max(-720,offset-15))end},{"+15m",function()set("timezone","fixed");set("utcOffset",math.min(840,offset+15))end}})
    toggle("24-hour clock", "clock24")
    toggle("Pad hour with zero", "leadingZero", "Off displays 1:00 instead of 01:00")
    toggle("Show seconds", "seconds")
    head("Panel")
    local r = cfg("panelRotate") or 12
    row("Change page every", r .. "s", { { "-", function() set("panelRotate", math.max(4, r - 2)) end }, { "+", function() set("panelRotate", r + 2) end } })
    head("Screen saver")
    local idle = cfg("idle") or 0
    local label = idle == 0 and "Off" or (idle < 60 and (idle .. "s") or (floor(idle / 60) .. " min"))
    row("Start after", label, { { "Change", function()
      local i = 1
      for k, v in ipairs(IDLE) do if v == idle then i = k end end
      set("idle", IDLE[i % #IDLE + 1])
    end } })
  elseif s == "Desktop" then
    head("Icons on the desktop")
    local on = {}
    for _, id in ipairs(cfg("desktop")) do on[id] = true end
    for _, a in ipairs(ccos.apps()) do
      if not a.hidden then
        row(a.name, on[a.id] and "Shown" or "Hidden", { { on[a.id] and "Hide" or "Show", function()
          local list = {}
          for _, id in ipairs(cfg("desktop")) do if id ~= a.id then list[#list + 1] = id end end
          if not on[a.id] then list[#list + 1] = a.id end
          set("desktop", list)
        end } })
      end
    end
  elseif s == "AI Agent" then
    head("OpenRouter")
    row("API key", ccos.agent.configured() and "Saved" or "Not configured", {{"Configure", ccos.agent.configure}})
    row("Model",cfg("agentModel"),{{"Change",function()
      local model=ccos.prompt("OpenRouter model","Model id with tool support",cfg("agentModel"))
      if model and model:match("^[%w%._:/%-]+$")and #model<=160 then set("agentModel",model)end
    end}})
    toggle("Review agent changes","agentConfirm")
    row("Step limit",tostring(cfg("agentMaxSteps")),{{"-",function()set("agentMaxSteps",math.max(1,cfg("agentMaxSteps")-1))end},{"+",function()set("agentMaxSteps",math.min(40,cfg("agentMaxSteps")+1))end}})
    row("Agent", "", {{"Open",function()ccos.open("agent")end}})
  else
    head("You")
    row("Name", cfg("user"), { { "Change", function()
      local name = ccos.prompt("Your name", "What should ccOS call you?", cfg("user"))
      if name and name ~= "" then set("user", name) end
    end } })
    head("Starting up")
    local boots = fs.exists("/startup.lua")
    local mine = false
    if boots then
      local h = fs.open("/startup.lua", "r")
      mine = h and (h.readAll() or ""):find("ccos/kernel.lua", 1, true) ~= nil
      if h then h.close() end
    end
    row("Start ccOS on boot", mine and "On" or (boots and "Another startup.lua" or "Off"), {
      mine and { "Turn off", function() fs.delete("/startup.lua") end }
        or { "Turn on", function()
          if fs.exists("/startup.lua") then fs.move("/startup.lua", "/startup.old.lua") end
          local h = fs.open("/startup.lua", "w")
          h.write('shell.run("/ccos/kernel.lua")\n')
          h.close()
        end },
    }, boots and not mine and "Turning it on keeps the old file as startup.old.lua" or nil)
    head("Power")
    row("Leave", "", { { "Exit to CraftOS", function() if ccos.confirm("Exit ccOS?", "Open windows will close.", "Exit") then ccos.exit() end end },
      { "Restart", function() if ccos.confirm("Restart?", "Open windows will close.", "Restart") then ccos.reboot() end end },
      { "Shut down", function() if ccos.confirm("Shut down?", "Open windows will close.", "Shut down") then ccos.shutdown() end end, T.danger } })
    if fs.exists("/ccos/crash.log") then
      row("Crash log", ui.bytes(fs.getSize("/ccos/crash.log")), { { "View", function() ccos.openFile("/ccos/crash.log") end },
        { "Clear", function() fs.delete("/ccos/crash.log") end } })
    end
  end
  return rows
end

function app:draw(g)
  local w, h = g.w, g.h
  local touch = ui.touch()
  local navW = w >= 60 and 18 or 0
  local narrow = navW == 0
  local rowH = narrow and (touch and 4 or 2) or (touch and 2 or 1)
  if navW > 0 then
    g:fill(1, 1, navW, h, T.surface)
    g:text(2, 1, "* Settings", T.accent, T.surface)
    for i, name in ipairs(SECTIONS) do
      local y = 2 + i * (touch and 2 or 1)
      local on = i == self.section
      g:fill(1, y, navW, touch and 2 or 1, on and T.raised or T.surface)
      g:text(2, y, ui.trunc(name, navW - 2), on and T.accent or T.text, on and T.raised or T.surface)
      g:hit(1, y, navW, y + (touch and 1 or 0), function() self.section = i; self.scroll.scroll = 0 end)
    end
  else
    g:fill(1, 1, w, 1, T.surface)
    g:button(1, 1, "\17", function() self.section = (self.section - 2) % #SECTIONS + 1 end, { bg = T.surface })
    g:center(1, SECTIONS[self.section], T.accent, T.surface)
    g:button(w - 2, 1, "\16", function() self.section = self.section % #SECTIONS + 1 end, { bg = T.surface })
  end
  local x = navW + 2
  local cw = w - x
  local top = navW > 0 and 1 or 3
  if navW > 0 then g:text(x, 1, SECTIONS[self.section], T.text, T.bg) end
  local rows = self:rows()
  g:list(self.scroll, x, top + 1, cw, h - top - 1, rows, function(r, _, rx, ry, rw)
    if r.head then
      g:header(rx, ry + rowH - 1, rw, r.head)
      return
    end
    if r.note and not r.label then
      g:text(rx, ry, ui.trunc(r.note, rw), T.muted, T.bg)
      return
    end
    local lw = min(22, floor(rw * 0.3))
    g:text(rx, ry, ui.trunc(r.label, lw - 1), T.text, T.bg)
    if narrow then
      g:text(rx + lw, ry, ui.trunc(r.value or "", rw - lw), T.accent, T.bg)
      local bx = rx
      for _, a in ipairs(r.actions or {}) do
        bx = g:button(bx, ry + 1, a[1], a[2], { h = touch and 3 or 1, fg = a[3] }) + 1
      end
      return
    end
    -- buttons from the right first, then the value in the room left
    local bx = rx + rw
    for i = #(r.actions or {}), 1, -1 do
      local a = r.actions[i]
      local bw = #a[1] + 2
      if bx - bw < rx + lw + 8 then break end
      bx = bx - bw
      g:button(bx, ry, a[1], a[2], { h = rowH, fg = a[3] })
      bx = bx - 1
    end
    g:text(rx + lw, ry, ui.trunc(r.value or "", bx - rx - lw - 1), T.accent, T.bg)
    if r.note and rowH > 1 then g:text(rx, ry + 1, ui.trunc(r.note, lw + 20), T.muted, T.bg) end
  end, nil, rowH)
end

function app:onKey(k)
  if k == keys.down then self.section = self.section % #SECTIONS + 1
  elseif k == keys.up then self.section = (self.section - 2) % #SECTIONS + 1
  else return false end
  self.scroll.scroll = 0
end

ui.run(app)
