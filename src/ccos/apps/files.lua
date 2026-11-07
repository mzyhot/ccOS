-- Files: a folder tree, the folder's contents and what you can do with them.
local ui = ccos.ui
local T = ui.T
local floor, max, min = math.floor, math.max, math.min
local args = { ... }

local KIND = {
  lua = { "L", T.info, "Lua program" }, txt = { "\21", T.text, "Text" }, md = { "\21", T.text, "Text" },
  cfg = { "\21", T.muted, "Settings" }, log = { "\21", T.muted, "Log" }, json = { "\21", T.text, "JSON" },
  dfpwm = { "\14", T.accent2, "Audio" }, wav = { "\14", T.accent2, "Audio" }, nfp = { "\4", T.hot, "Image" },
}

local function ext(name) return (name:match("%.(%w+)$") or ""):lower() end
local function kindOf(path, name)
  if fs.isDir(path) then
    if fs.getDrive(path) and fs.getDrive(path) ~= "hdd" and fs.getDir(path) == "" then
      return { "\8", T.warn, fs.getDrive(path) == "rom" and "ROM" or "Disk" }
    end
    return { "\7", T.warn, "Folder" }
  end
  return KIND[ext(name)] or { "\183", T.muted, "File" }
end

local app = { title = "Files", tree = { scroll = 0 }, list = { scroll = 0 }, open = { [""] = true } }

local function norm(p)
  p = fs.combine(p or "", "")
  return p
end

function app:go(path)
  path = norm(path)
  if not fs.isDir("/" .. path) then return end
  if self.cwd ~= path then
    self.back = self.back or {}
    if self.cwd then self.back[#self.back + 1] = self.cwd end
  end
  self.cwd = path
  self.sel, self.list.scroll = nil, 0
  -- open every folder down to here in the tree
  local p = path
  while p ~= "" do
    self.open[p] = true
    p = fs.getDir(p)
  end
  self.open[""] = true
  self:refresh()
  ccos.setTitle("Files - /" .. path)
end

function app:refresh()
  local entries = {}
  local ok, names = pcall(fs.list, "/" .. self.cwd)
  if not ok then names = {} end
  for _, name in ipairs(names) do
    if self.hidden or name:sub(1, 1) ~= "." then
      local p = "/" .. fs.combine(self.cwd, name)
      local dir = fs.isDir(p)
      entries[#entries + 1] = { name = name, path = p, dir = dir, size = dir and 0 or fs.getSize(p), kind = kindOf(p, name) }
    end
  end
  table.sort(entries, function(a, b)
    if a.dir ~= b.dir then return a.dir end
    return a.name:lower() < b.name:lower()
  end)
  self.entries = entries
  self.freeSpace = select(2, pcall(fs.getFreeSpace, "/" .. self.cwd))
end

-- The folder tree as indented rows.
function app:treeRows()
  local rows = {}
  local function walk(path, depth)
    local ok, names = pcall(fs.list, "/" .. path)
    if not ok then return end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    for _, name in ipairs(names) do
      local p = fs.combine(path, name)
      if fs.isDir("/" .. p) and (self.hidden or name:sub(1, 1) ~= ".") then
        rows[#rows + 1] = { path = p, name = name, depth = depth }
        if self.open[p] then walk(p, depth + 1) end
      end
    end
  end
  rows[1] = { path = "", name = "Computer", depth = 0 }
  walk("", 1)
  return rows
end

function app:selected() return self.sel and self.entries[self.sel] end

local function readOnly(path) return fs.isReadOnly(path) end

local function freeName(dir, name)
  local p = "/" .. fs.combine(dir, name)
  if not fs.exists(p) then return p end
  local base, e = name:match("^(.-)(%.[^.]*)$")
  base, e = base or name, e or ""
  for i = 2, 99 do
    p = "/" .. fs.combine(dir, base .. " " .. i .. e)
    if not fs.exists(p) then return p end
  end
end

function app:status(msg, color) self.msg, self.msgColor, self.msgAt = msg, color, os.epoch("utc") end

function app:openEntry(e)
  if e.dir then
    self:go(e.path)
  else
    ccos.openFile(e.path)
  end
end

function app:actions(e)
  local acts = {}
  local add = function(label, fn, color) acts[#acts + 1] = { label, fn, { fg = color } } end
  if e then
    add("Open", function() self:openEntry(e) end)
    if not e.dir then
      local x = ext(e.name)
      if x == "lua" then add("Run", function() ccos.runFile(e.path) end, T.ok) end
      if x == "dfpwm" or x == "wav" then add("Play", function() ccos.audio.play(e.path) end, T.accent2) end
      if x ~= "dfpwm" and x ~= "wav" then add("Edit", function() ccos.open("edit", e.path) end) end
      if x ~= "dfpwm" and x ~= "wav" then
        add("Print", function()
          local h = fs.open(e.path, "r")
          if not h then return end
          local text = h.readAll()
          h.close()
          local ok, err = ccos.printText(e.name, text)
          self:status(ok and ("Printed " .. err .. " page(s)") or err, ok and T.ok or T.danger)
        end)
      end
    else
      local list = {}
      local ok, names = pcall(fs.list, e.path)
      for _, n in ipairs(ok and names or {}) do
        if (ext(n) == "dfpwm" or ext(n) == "wav") and not n:match("%.r%.dfpwm$") then
          list[#list + 1] = ccos.audio.item("/" .. fs.combine(e.path, n))
        end
      end
      if #list > 0 then
        add("Play all", function() ccos.audio.play(list, 1) end, T.accent2)
      end
    end
    add("Copy", function() self.clip = { path = e.path, cut = false }; self:status("Copied " .. e.name) end)
    if not readOnly(e.path) then
      add("Cut", function() self.clip = { path = e.path, cut = true }; self:status("Cut " .. e.name) end)
      add("Rename", function()
        local name = ccos.prompt("Rename", "New name for " .. e.name, e.name)
        if name and name ~= "" and name ~= e.name then
          local ok, err = pcall(fs.move, e.path, "/" .. fs.combine(fs.getDir(e.path), name))
          self:status(ok and "Renamed" or err, ok and T.ok or T.danger)
          self:refresh()
        end
      end)
      add("Delete", function()
        if ccos.confirm("Delete " .. e.name .. "?", e.dir and "The folder and everything in it will be gone." or "This can't be undone.", "Delete") then
          local ok, err = pcall(fs.delete, e.path)
          self:status(ok and ("Deleted " .. e.name) or err, ok and T.ok or T.danger)
          self.sel = nil
          self:refresh()
        end
      end, T.danger)
    end
    local disks = {}
    for _, name in ipairs(fs.list("/")) do
      if fs.isDir("/" .. name) and fs.getDrive("/" .. name) ~= "hdd" and fs.getDrive("/" .. name) ~= "rom"
        and not e.path:find("^/" .. name .. "/") then
        disks[#disks + 1] = name
      end
    end
    if disks[1] then
      add("To " .. disks[1], function()
        local dest = freeName(disks[1], e.name)
        local ok, err = pcall(fs.copy, e.path, dest)
        self:status(ok and ("Copied to " .. dest) or err, ok and T.ok or T.danger)
      end)
    end
  end
  return acts
end

function app:paste()
  local c = self.clip
  if not c or not fs.exists(c.path) then return self:status("Nothing to paste", T.warn) end
  local dest = freeName(self.cwd, fs.getName(c.path))
  local ok, err = pcall(c.cut and fs.move or fs.copy, c.path, dest)
  if ok and c.cut then self.clip = nil end
  self:status(ok and ("Pasted " .. fs.getName(dest)) or err, ok and T.ok or T.danger)
  self:refresh()
end

function app:newItem(folder)
  local name = ccos.prompt(folder and "New folder" or "New file", "Name", folder and "folder" or "notes.txt")
  if not name or name == "" then return end
  local p = "/" .. fs.combine(self.cwd, name)
  if fs.exists(p) then return self:status(name .. " already exists", T.warn) end
  local ok, err = pcall(function()
    if folder then fs.makeDir(p) else local h = fs.open(p, "w"); h.close() end
  end)
  self:status(ok and ("Made " .. name) or err, ok and T.ok or T.danger)
  self:refresh()
end

function app:init()
  self:go(args[1] or "")
end

function app:draw(g)
  local w, h = g.w, g.h
  local touch = ui.touch()
  local barH = touch and 3 or 1
  -- Toolbar: back, up, path, then actions on the right.
  g:fill(1, 1, w, 1, T.surface)
  local x = g:button(1, 1, "\27", function()
    local b = self.back and table.remove(self.back)
    if b then self.cwd = nil; self:go(b) end
  end, { bg = T.surface })
  x = g:button(x, 1, "\24", function() self:go(fs.getDir(self.cwd)) end, { bg = T.surface })
  local right = {
    { "+File", function() self:newItem(false) end },
    { "+Folder", function() self:newItem(true) end },
    { "Paste", function() self:paste() end, { disabled = not self.clip } },
    { self.hidden and "Hide dots" or "Dots", function() self.hidden = not self.hidden; self:refresh() end },
  }
  local rw = 0
  for _, it in ipairs(right) do rw = rw + #it[1] + 3 end
  local showRight = w - rw > 30
  -- breadcrumb
  local crumbs = { { "/", "" } }
  local acc = ""
  for part in self.cwd:gmatch("[^/]+") do
    acc = fs.combine(acc, part)
    crumbs[#crumbs + 1] = { part, acc }
  end
  local cx = x + 1
  local limit = showRight and (w - rw) or w
  for i, c in ipairs(crumbs) do
    local label = (i > 2 and "\16" or "") .. c[1]
    if cx + #label > limit then break end
    local target = c[2]
    g:text(cx, 1, label, i == #crumbs and T.accent or T.text, T.surface)
    g:hit(cx, 1, cx + #label - 1, 1, function() self:go(target) end)
    cx = cx + #label + 1
  end
  if showRight then g:buttons(w - rw + 1, 1, right, 1) end

  local treeW = w >= 62 and 22 or 0
  local top, bottom = 2, h - barH - 1
  -- Tree
  if treeW > 0 then
    g:fill(1, top, treeW, bottom - top + 1, T.surface)
    local rows = self:treeRows()
    g:list(self.tree, 1, top, treeW, bottom - top + 1, rows, function(r, _, rx, ry, rw2)
      local here = r.path == self.cwd
      local bg = here and T.raised or T.surface
      g:fill(rx, ry, rw2, 1, bg)
      local arrow = r.depth == 0 and "" or (self.open[r.path] and "\31 " or "\16 ")
      local label = (" "):rep(r.depth) .. arrow .. r.name
      g:text(rx, ry, ui.pad(label, rw2), here and T.accent or T.text, bg)
    end, function(r)
      if r.path == self.cwd and r.path ~= "" then self.open[r.path] = not self.open[r.path] end
      self:go(r.path)
    end)
  end
  -- File list
  local lx, lw = treeW + 1 + (treeW > 0 and 1 or 0), w - treeW - (treeW > 0 and 1 or 0)
  local sizeW, typeW = 9, lw >= 50 and 12 or 0
  g:text(lx, top, ui.pad("  Name", lw - sizeW - typeW), T.muted, T.bg)
  g:text(lx + lw - sizeW - typeW, top, ui.padL("Size", sizeW - 1) .. " ", T.muted, T.bg)
  if typeW > 0 then g:text(lx + lw - typeW, top, ui.pad("Type", typeW), T.muted, T.bg) end
  local rowH = touch and 2 or 1
  if #self.entries == 0 then
    g:text(lx + 2, top + 2, "This folder is empty", T.muted, T.bg)
  end
  g:list(self.list, lx, top + 1, lw, bottom - top, self.entries, function(e, i, rx, ry, rw2)
    local sel = i == self.sel
    local bg = sel and T.select or T.bg
    g:fill(rx, ry, rw2, rowH, bg)
    local k = e.kind
    g:text(rx + 1, ry, k[1], k[2], bg)
    g:text(rx + 3, ry, ui.trunc(e.name .. (e.dir and "/" or ""), rw2 - sizeW - typeW - 4), T.text, bg)
    g:text(rx + rw2 - sizeW - typeW, ry, ui.padL(e.dir and "" or ui.bytes(e.size), sizeW - 1), T.muted, bg)
    if typeW > 0 then g:text(rx + rw2 - typeW + 1, ry, ui.trunc(k[3], typeW - 1), sel and T.text or T.muted, bg) end
  end, function(e, i)
    local t = os.epoch("utc")
    if self.sel == i and (touch or ccos.touchInput() or t - (self.clickAt or 0) < 500) then
      self:openEntry(e)
    else
      self.sel = i
    end
    self.clickAt = t
  end, rowH)
  -- Action bar
  local e = self:selected()
  local ay = h - barH
  g:fill(1, ay, w, barH, T.surface)
  local acts = self:actions(e)
  if #acts == 0 then
    g:text(2, ay + floor((barH - 1) / 2), touch and "Tap a file to choose it, tap again to open" or "Click to choose, double-click to open", T.muted, T.surface)
  else
    local bx = 2
    for _, a in ipairs(acts) do
      if bx + #a[1] + 2 > w then break end
      bx = g:button(bx, ay, a[1], a[2], { h = barH, bg = T.raised, fg = a[3].fg }) + 1
    end
  end
  -- Status line
  local status
  if self.msg and os.epoch("utc") - self.msgAt < 6000 then
    status = { self.msg, self.msgColor or T.text }
  else
    local info = #self.entries .. " items"
    if e then info = info .. "  \183  " .. e.name .. (e.dir and "" or ("  " .. ui.bytes(e.size))) end
    if type(self.freeSpace) == "number" then info = info .. "  \183  " .. ui.bytes(self.freeSpace) .. " free" end
    if self.clip then info = info .. "  \183  clipboard: " .. fs.getName(self.clip.path) end
    status = { info, T.muted }
  end
  g:fill(1, h, w, 1, T.bg)
  g:text(2, h, ui.trunc(status[1], w - 2), status[2], T.bg)
end

function app:onKey(k)
  local n = #self.entries
  if k == keys.down then self.sel = math.min(n, (self.sel or 0) + 1)
  elseif k == keys.up then self.sel = math.max(1, (self.sel or 2) - 1)
  elseif k == keys.enter then local e = self:selected(); if e then self:openEntry(e) end
  elseif k == keys.backspace then self:go(fs.getDir(self.cwd))
  elseif k == keys.delete then
    local e = self:selected()
    if e and not readOnly(e.path) and ccos.confirm("Delete " .. e.name .. "?", "This can't be undone.", "Delete") then
      pcall(fs.delete, e.path)
      self.sel = nil
      self:refresh()
    end
  elseif k == keys.f5 then self:refresh()
  else return false end
  if self.sel then
    local visible = (self.g.h - 4)
    if self.sel <= self.list.scroll then self.list.scroll = self.sel - 1 end
    if self.sel > self.list.scroll + visible then self.list.scroll = self.sel - visible end
  end
end

function app:onEvent(ev)
  if ev[1] == "disk" or ev[1] == "disk_eject" then
    if not fs.isDir("/" .. self.cwd) then self.cwd = nil; self:go("") else self:refresh() end
    return true
  end
end

ui.run(app)
