-- Hallmark · genre: atmospheric · structure: compact tool workbench · palette: ccOS tokens
-- Pre-emit critique: Philosophy 5, Hierarchy 4, Execution 4, Specificity 5, Restraint 5, Variety 4
-- Touch-only presentation. Shares the kernel's audio, files and hardware;
-- routes prompt entry through the dedicated computer input console.
return function(K, gfx, T)
  local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
  local P = {}
  local startScreen=assert(loadfile(K.root.."/lib/startscreen.lua"))()(K,gfx,T)
  local function clip(text, w)
    text = tostring(text or "")
    return w > 0 and text:sub(1, w) or ""
  end
  local function audioFile(path)
    local n = path:lower()
    return n:match("%.wav$") or (n:match("%.dfpwm$") and not n:match("%.r%.dfpwm$"))
  end
  function P.draw(s)
    local B, A = s.buf, K.audio
    s.picture = s.picture or { view = "home", page = 1, path = "/", category="Favorites" }
    local v = s.picture
    local W, H = s.w, s.h
    local compact = true
    local top, bottom = 2, H - 1
    local left, width = 2, W - 2
    local function text(x, y, t, fg, bg)
      if y < 1 or y > H then return end
      t = tostring(t or "")
      if x < 1 then t = t:sub(2 - x); x = 1 end
      t = clip(t, W - x + 1)
      B.setCursorPos(x, y); B.setTextColor(fg or T.text); B.setBackgroundColor(bg or T.bg); B.write(t)
    end
    local function fill(x, y, w, h, bg)
      x, w = max(1, x), min(w, W - x + 1)
      if w <= 0 then return end
      for yy = max(1, y), min(H, y + h - 1) do text(x, yy, (" "):rep(w), bg, bg) end
    end
    local function hit(x, y, w, h, fn)
      if w <= 0 or h <= 0 then return end
      s.hits[#s.hits + 1] = { x1 = max(1, x), y1 = max(1, y), x2 = min(W, x + w - 1), y2 = min(H, y + h - 1), fn = fn }
    end
    local function center(x, y, w, label, fg, bg)
      label = clip(label, w)
      text(x + floor((w - #label) / 2), y, label, fg, bg)
    end
    local function button(x, y, w, h, label, fn, active, disabled)
      local bg = active and T.accent or T.raised
      fill(x, y, w, h, bg)
      center(x, y + floor((h - 1) / 2), w, label, disabled and T.muted or (active and T.bg or T.text), bg)
      if not disabled then hit(x, y, w, h, fn) end
    end
    local function go(view)
      local found
      for _, a in ipairs(K.APPS) do if a.id == view then found = a end end
      local builtin = ({home=true,music=true,files=true,reader=true,devices=true,settings=true,notifications=true,power=true})[view]
      if found and not K.canTouchApp(found,s) and not builtin then
        K.launch(view, {}, {screen=s}); v.message="Full Sync needed: "..found.name; K.markDirty(s); return
      end
      v.view, v.page, v.message, v.appPid = view, 1, nil, nil
      K.markAll()
    end
    local function run(fn, title)
      K.spawn(function()
        local ok, result = pcall(fn)
        v.message = ok and (result or "Done") or tostring(result)
        K.markDirty(s)
      end, { title = title or "ccOS" })
    end
    local function pager(count, rows, y)
      local pages = max(1, ceil(count / max(1, rows)))
      v.page = max(1, min(v.page, pages))
      local bw = min(10, floor((width - 9) / 2))
      button(left, y, bw, compact and 1 or 2, "< Prev", function() v.page = v.page - 1 end, false, v.page == 1)
      button(W - bw, y, bw, compact and 1 or 2, "Next >", function() v.page = v.page + 1 end, false, v.page == pages)
      center(left + bw, y, width - bw * 2, v.page .. " / " .. pages, T.muted)
      return (v.page - 1) * rows
    end
    local function list(items, y, endY, pick)
      local rowH = compact and 1 or 3
      local cols = W >= 72 and 2 or 1
      local cw = floor((width - (cols - 1) * 2) / cols)
      local pageY = endY - (compact and 0 or 1)
      local visible = max(1, floor((pageY - y) / rowH)) * cols
      local off = pager(#items, visible, pageY)
      for i = 1, visible do
        local item = items[off + i]
        if not item then break end
        local yy = y + floor((i - 1) / cols) * rowH
        local xx = left + ((i - 1) % cols) * (cw + 2)
        fill(xx, yy, cw, rowH - (compact and 0 or 1), T.surface)
        text(xx + 1, yy, clip(item.label, cw - 3), item.color or T.text, T.surface)
        if item.detail and rowH == 3 then text(xx + 1, yy + 1, clip(item.detail, cw - 3), T.muted, T.surface) end
        if item.fn or pick then hit(xx, yy, cw, rowH - (compact and 0 or 1), function() (item.fn or pick)(item) end) end
      end
      if #items == 0 then center(left, y, width, "Nothing here yet", T.muted) end
    end
    local function controls(items, y, h)
      local n, gap = #items, 1
      local available = width - gap * (n - 1)
      for i, it in ipairs(items) do
        local x = left + floor((i - 1) * available / n) + (i - 1) * gap
        local w = floor(i * available / n) - floor((i - 1) * available / n)
        button(x, y, w, h or 3, it[1], it[2], it[3], it[4])
      end
    end
    fill(1, 1, W, H, T.bg)
    if W < 32 or H < 10 then
      center(1, 1, W, "ccOS", T.accent)
      if H >= 3 then button(1, 3, W, min(3, H - 2), "Auto scale", function() K.api.setScreen(s.name, nil, "auto") end, true) end
      return
    end
    if v.view=="home"then startScreen.draw(s,go);return end
    -- One-row chrome reserves almost all monitor cells for useful content.
    fill(1, 1, W, 1, T.surface)
    button(1, 1, 8, 1, v.view == "home" and "ccOS" or "< Tools", function() go("home") end, v.view == "home")
    local titles = { home=v.category or "Favorites", music="Music", files="Files", reader="Reader", devices="Devices",settings="Settings",notifications="Notifications",power="Power" }
    local nativeApp, appDef
    for _,a in ipairs(K.APPS) do if a.id == v.view then appDef=a end end
    if appDef and not titles[v.view] then nativeApp=appDef.touch end
    local title=titles[v.view] or (appDef and appDef.name) or "ccOS"
    local ct=K.clockText(K.cfg.seconds)
    text(10,1,clip(title,max(0,W-#ct-18)),T.text,T.surface)
    text(W-#ct,1,ct,T.muted,T.surface)
    local info = A.info()
    if nativeApp then
      local win
      for _, w in ipairs(K.wins) do if w.screen == s and w.app and w.app.id == v.view and not w.proc.dead then win = w end end
      if not win and not v.appPid then
        local p = K.launch(v.view, {}, { screen = s })
        win = p and p.win
      elseif not win then
        v.view,v.appPid="home",nil;K.markDirty(s)
      end
      if win then v.appPid=win.id end
      if win then
        button(W-#ct-5,1,3,1,"x",function()K.closeWindow(win);go("home")end)
        for row = 1, win.h do
          local t, f, b = win.buf.getLine(row)
          B.setCursorPos(win.x, win.y + row); B.blit(t, f, b)
        end
        s.hits[#s.hits + 1] = { x1 = win.x, y1 = win.y + 1, x2 = win.x + win.w - 1, y2 = win.y + win.h, content = win }
      end
    elseif v.view == "music" then
      local cy = top
      if not compact then
        text(left, cy, clip(info.discTitle or info.title or "Choose a track", width), T.accent)
        cy = cy + 2
      end
      controls({ { "Previous", A.prev }, { info.state == "playing" and "Pause" or "Play", A.toggle, true },
        { "Next", A.next }, { "Stop", function() if info.disc then A.stopDisc() else A.stop() end end } }, cy, compact and 1 or 3)
      cy = cy + (compact and 1 or 4)
      local tracks, items = {}, {}
      local function scan(dir, depth)
        if depth > 3 then return end
        local ok, names = pcall(fs.list, dir)
        if not ok then return end
        table.sort(names)
        for _, name in ipairs(names) do
          local path = fs.combine(dir, name)
          if fs.isDir(path) then
            if name ~= "rom" and name ~= "ccos" then scan(path, depth + 1) end
          elseif audioFile(path) then tracks[#tracks + 1] = A.item("/" .. path) end
        end
      end
      -- Scan on entry or explicit refresh, never on each playback frame.
      if not v.library then scan("", 0); v.library = tracks end
      tracks = v.library
      for i, item in ipairs(tracks) do
        items[#items + 1] = { label = item.title, detail = item.path, fn = function() A.play(tracks, i) end }
      end
      if bottom - cy >= 1 then list(items, cy, bottom, nil)
      else
        button(left, cy, width, 2, "Play library", function() if #tracks > 0 then A.play(tracks, 1) end end, false, #tracks == 0)
      end
    elseif v.view == "files" then
      local upW = min(10, floor(width / 3))
      button(left, top, upW, compact and 1 or 2, "< Up", function() v.path = "/" .. fs.getDir(v.path); v.page = 1 end, false, v.path == "/")
      button(W - 11, top, 11, compact and 1 or 2, "Refresh", function() v.message = nil end)
      text(left + upW + 1, top + (compact and 0 or 1), clip(v.path, width - upW - 13), T.accent)
      local ok, names = pcall(fs.list, v.path)
      local items = {}
      if ok then
        table.sort(names, function(a, b)
          local ad, bd = fs.isDir(fs.combine(v.path, a)), fs.isDir(fs.combine(v.path, b))
          if ad ~= bd then return ad end
          return a:lower() < b:lower()
        end)
        for _, n in ipairs(names) do
          local path = fs.combine(v.path, n)
          local dir = fs.isDir(path)
          if "/"..path ~= "/ccos/private" then
          items[#items + 1] = { label = (dir and "+ " or "  ") .. n .. (dir and "/" or ""), detail = dir and "Tap to open folder" or "Tap to read or play", fn = function()
            if dir then v.path = "/" .. path; v.page = 1
            elseif audioFile(path) then A.play("/" .. path); go("music")
            else
              local handle = fs.open(path, "r")
              if handle then
                -- Bounded reader: never execute programs or load an entire disk.
                local raw = handle.read(32768) or ""; handle.close()
                if raw:find("[%z\1-\8\11\12\14-\31]") then v.message = "This file cannot be previewed"
                else v.readText, v.readName = raw, n; go("reader") end
              else v.message = "File is unavailable" end
            end
          end }
          end
        end
      end
      if v.message then text(left + upW + 1, top + 1, clip(v.message, width - upW - 13), T.warn) end
      list(items, top + (compact and 1 or 3), bottom)
    elseif v.view == "reader" then
      button(left, top, 12, compact and 1 or 2, "< Files", function() go("files") end)
      button(W - 12, top, 12, compact and 1 or 2, "Print file", function()
        run(function() local ok, result = K.api.printText(v.readName, v.readText); return ok and "Printed" or result end, "Print file")
      end)
      local lines = {}
      for found in ((v.readText or "") .. "\n"):gmatch("([^\n]*)\n") do
        local line = found:gsub("\t", "    ")
        if #line == 0 then lines[#lines + 1] = "" end
        while #line > 0 do lines[#lines + 1] = line:sub(1, width); line = line:sub(width + 1) end
      end
      local pageY = bottom - (compact and 0 or 1)
      local readY = top + (compact and 1 or 3)
      local n = max(1, pageY - readY)
      local off = pager(#lines, n, pageY)
      for i = 1, n do text(left, readY + i - 1, lines[off + i] or "", T.text) end
      if v.message then text(left + 13, top, clip(v.message, width - 26), T.accent) end
    elseif v.view == "devices" then
      local items = {}
      for _, d in ipairs(K.hw.drives or {}) do
        items[#items + 1] = { label = d.name .. ": " .. (d.label or d.audio or (d.present and "Disk" or "Empty")),
          detail = d.audio and "Tap to play disc" or (d.mount and "Tap to browse disk" or "No data disk"), fn = function()
            if d.audio then A.playDisc(d.name); go("music")
            elseif d.mount then v.path = "/" .. d.mount; go("files") end
          end }
      end
      for _, p in ipairs(K.hw.printers or {}) do items[#items + 1] = { label = p.name, detail = (p.paper or 0) .. " paper / " .. (p.ink or 0) .. " ink" } end
      items[#items + 1] = { label = "Test left speaker", detail = info.speakers .. " speakers connected", fn = function() A.note("bell", 12, -1, 1.5) end }
      items[#items + 1] = { label = "Test right speaker", fn = function() A.note("bell", 12, 1, 1.5) end }
      list(items, top, bottom)
    elseif v.view == "settings" then
      local function toggle(key) K.api.config(key, not K.cfg[key]) end
      local items = {
        {label="Full Sync with desktop",fn=function()K.setFullSync(true)end},
        {label="Auto update checks: "..(K.cfg.autoUpdates and "On"or "Off"),fn=function()toggle("autoUpdates")end},
        {label="Check for updates",fn=function()K.updates.check(true)end},
        {label=K.updates and K.updates.status or "Updates",fn=function()if K.updates.available then K.updates.prompt()end end},
        { label = "Theme: " .. K.cfg.theme, detail = "Tap for next theme", fn = function()
          local i = 1; for j, id in ipairs(K.THEME_ORDER) do if id == K.cfg.theme then i = j end end
          K.api.config("theme", K.THEME_ORDER[i % #K.THEME_ORDER + 1])
        end },
        { label = "Volume down", detail = floor(K.cfg.musicVolume * 100 + 0.5) .. "%", fn = function() A.setVolume(K.cfg.musicVolume - 0.1) end },
        { label = "Volume up", detail = floor(K.cfg.musicVolume * 100 + 0.5) .. "%", fn = function() A.setVolume(K.cfg.musicVolume + 0.1) end },
        { label = "System sounds: " .. (K.cfg.sounds and "On" or "Off"), fn = function() toggle("sounds") end },
        { label = "Time zone: " .. K.cfg.timezone, fn = function()
          local index=1;for i,z in ipairs(K.clock.zones)do if z==K.cfg.timezone then index=i end end
          K.api.config("timezone",K.clock.zones[index%#K.clock.zones+1])
        end },
        { label = "UTC -15m ("..K.cfg.utcOffset.."m)", detail=tostring(K.cfg.utcOffset).." minutes",fn=function()K.api.config("timezone","fixed");K.api.config("utcOffset",math.max(-720,K.cfg.utcOffset-15))end },
        { label = "UTC +15m ("..K.cfg.utcOffset.."m)", detail=tostring(K.cfg.utcOffset).." minutes",fn=function()K.api.config("timezone","fixed");K.api.config("utcOffset",math.min(840,K.cfg.utcOffset+15))end },
        { label = "Pad hour with zero: "..(K.cfg.leadingZero and "On"or "Off"),fn=function()toggle("leadingZero")end },
        { label = "24-hour clock: " .. (K.cfg.clock24 and "On" or "Off"), fn = function() toggle("clock24") end },
        { label = "Swap stereo speakers: " .. (K.cfg.swapSpeakers and "On" or "Off"), fn = function() toggle("swapSpeakers") end },
        { label = "Refresh music library", fn = function() v.library = nil; go("music") end },
        { label = "AI Agent",fn=function()go("agent")end },
        { label = "Auto display scale", detail = "Fit touch controls to this monitor", fn = function() K.api.setScreen(s.name, nil, "auto") end },
      }
      list(items, top, bottom)
    elseif v.view == "notifications" then
      local items = {}
      for _, n in ipairs(K.notifs) do items[#items + 1] = { label = n.title, detail = n.text } end
      if K.unread > 0 then K.unread = 0; K.markAll() end
      list(items, top, bottom)
    elseif v.view == "power" then
      if v.confirm then
        center(left, top, width, v.confirm == "reboot" and "Restart the computer?" or "Shut down the computer?", T.warn)
        controls({ { "Cancel", function() v.confirm = nil end }, { "Confirm", function() K.power = v.confirm; K.running = false end, true } }, top + (compact and 1 or 2), compact and 1 or 3)
      else
        controls({ { "Restart", function() v.confirm = "reboot" end }, { "Shut down", function() v.confirm = "shutdown" end } }, top + (compact and 0 or 1), compact and 1 or 3)
      end
    end
    -- Playback is shared with the computer and remains accessible everywhere.
    local fy = H
    fill(1, fy, W, 1, T.surface)
    local name = info.discTitle or info.title or "Music library"
    local bw = W >= 48 and 9 or 5
    local powerX = W - 7
    local nextX, playX = powerX - bw - 1, powerX - 2 * bw - 2
    local labelW = playX - 3
    text(2, fy, clip(v.message or name, labelW), T.accent, T.surface)
    hit(1, fy, labelW + 2, 1, function() go("music") end)
    button(playX, fy, bw, 1, info.state == "playing" and "Pause" or "Play", A.toggle, true)
    button(nextX, fy, bw, 1, "Next", A.next)
    button(powerX, fy, 8, 1, "Power", function() v.confirm = nil; go("power") end)
  end
  return P
end
