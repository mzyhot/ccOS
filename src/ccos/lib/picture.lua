-- Big Picture views in the Windows 8.1 idiom: a back circle and light page
-- title, flat lists with colour chips, an AppBar for media, two-pane PC
-- settings, toasts and an 8.1 Update title bar over full-screen apps.
-- On a monitor, text entry is typed on the computer's keyboard console.
return function(K, gfx, T)
  local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
  local P = {}
  local startScreen=assert(loadfile(K.root.."/lib/startscreen.lua"))()(K,gfx,T)
  P.start=startScreen
  local M=gfx.metro
  local function hx(c)return gfx.HEX[c]or"f"end
  local function clip(text, w)
    text = tostring(text or "")
    return w > 0 and text:sub(1, w) or ""
  end
  local function audioFile(path)
    local n = path:lower()
    return n:match("%.wav$") or (n:match("%.dfpwm$") and not n:match("%.r%.dfpwm$"))
  end
  local function rows(spec)local r={};for row in spec:gmatch("%S+")do r[#r+1]=row end;return r end
  local CIRCLE=rows("....###.... ..##...##.. .#.......#. .#.......#. #.........# #.........# #.........# .#.......#. .#.......#. ..##...##.. ....###....")
  local MEDIA={
    prev=rows("#...# #..## #.### #..## #...#"),next=rows("#...# ##..# ###.# ##..# #...#"),
    play=rows(".#... .##.. .###. .##.. .#..."),pause=rows("##.## ##.## ##.## ##.## ##.##"),stop=rows("##### ##### ##### ##### #####"),
  }
  local function circleButton(kind,bg)
    return startScreen.remember("circle"..kind..hx(bg),function()
      local cv=gfx.canvas(12,12,hx(bg))
      M.stamp(cv,1,1,CIRCLE,hx(T.text));M.stamp(cv,4,4,MEDIA[kind],hx(T.text))
      return gfx.cells(cv.rows(),hx(bg))
    end)
  end
  local CHIP=string.char(149)
  local BUILTIN={home=true,apps=true,music=true,files=true,reader=true,devices=true,settings=true,notifications=true,power=true}

  function P.draw(s)
    local A = K.audio
    s.picture = s.picture or { view = "home", page = 1, path = "/" }
    local v = s.picture
    local W, H = s.w, s.h
    local m=startScreen.metrics(W,H)
    local Pn=startScreen.painter(s)
    local function text(x, y, t, fg, bg) Pn.text(x,y,t,fg,bg or T.bg) end
    local function fill(x, y, w, h, bg) x,w=max(1,x),min(w,W-max(1,x)+1);Pn.fill(x,y,w,h,bg) end
    local function hit(x, y, w, h, fn) if w>0 and h>0 then Pn.hit(x,y,w,h,fn)end end
    local function center(x, y, w, label, fg, bg)
      label = clip(label, w)
      text(x + floor((w - #label) / 2), y, label, fg, bg)
    end
    -- A flat Metro button: filled, label centred, accent when primary.
    local function button(x, y, w, label, fn, primary, disabled, h)
      h=h or 1
      local bg = primary and T.accent or T.raised
      fill(x, y, w, h, bg)
      center(x, y + floor((h - 1) / 2), w, label, disabled and T.muted or T.text, bg)
      if not disabled then hit(x, y, w, h, fn) end
    end
    local function go(view)
      local found
      for _, a in ipairs(K.APPS) do if a.id == view then found = a end end
      v.page, v.message, v.confirm, v.flyout = 1, nil, nil, nil
      if view ~= "apps" then v.search = nil end
      if found and not BUILTIN[view] then
        -- Apps open full screen (or come back if already running).
        local p, why = K.launch(view, {}, { screen = s })
        if not p then v.message = why end
      else
        v.view, v.appPid = view, nil
      end
      K.markAll()
    end
    P.go=go
    local function run(fn, title)
      K.spawn(function()
        local ok, result = pcall(fn)
        v.message = ok and (result or "Done") or tostring(result)
        K.markDirty(s)
      end, { title = title or "ccOS" })
    end

    fill(1, 1, W, H, T.bg)
    if W < 32 or H < 10 then
      center(1, 1, W, "ccOS", T.accent)
      if H >= 3 then button(1, 3, W, "Auto scale", function() K.api.setScreen(s.name, nil, "auto") end, true, false, min(3, H - 2)) end
      return
    end
    if v.view=="home"then startScreen.draw(s,go);return end
    if v.view=="apps"then startScreen.drawApps(s,go);return end

    local titles = { music="Music", files="Files", reader=v.readName or "Reader", devices="Devices",settings="PC settings",notifications="Notifications",power="Power" }
    local appDef
    for _,a in ipairs(K.APPS) do if a.id == v.view then appDef=a end end
    local info = A.info()

    -- Full-screen app: the 8.1 Update title bar, then the app itself.
    if appDef and not titles[v.view] then
      local win = K.pictureApp(s)
      if not win then
        for _, w in ipairs(K.wins) do if w.screen == s and w.app and w.app.id == v.view and not w.proc.dead then win = w end end
        if win then v.appPid = win.id
        else
          local p, why = K.launch(v.view, {}, { screen = s })
          win = p and p.win
          if not win then v.view, v.appPid, v.message = "home", nil, why; K.markDirty(s); return end
        end
      end
      fill(1, 1, W, 1, T.surface)
      text(1,1," \27 ",T.text,T.surface);hit(1,1,3,1,function()go("home")end)
      local c=startScreen.color(appDef)
      if c==T.surface or c==T.bg then c=T.raised end
      Pn.cells(5,1,{{" "..CHIP,"0"..hx(c),hx(c)..hx(T.surface)}})
      local ct=K.clockText(false)
      local name=win and win.title or appDef.name
      text(8,1,clip(name,max(0,W-#ct-18)),T.text,T.surface)
      text(W-#ct-8,1,ct,T.muted,T.surface)
      text(W-5,1," - ",T.text,T.surface);hit(W-5,1,3,1,function()go("home")end)
      if win then
        text(W-2,1," \215 ",T.text,T.surface);hit(W-2,1,3,1,function()K.closeWindow(win);go("home")end)
        for row = 1, win.h do
          local t, f, b = win.buf.getLine(row)
          s.buf.setCursorPos(win.x, win.y + row); s.buf.blit(t, f, b)
        end
        s.hits[#s.hits + 1] = { x1 = win.x, y1 = win.y + 1, x2 = win.x + win.w - 1, y2 = win.y + win.h, content = win }
      end
      if v.message then startScreen.toast(Pn,s,m,v)end
      return
    end

    -- Page header: back circle, light title, optional subtitle and actions.
    local actionX=W-max(1,floor(m.L/2))
    local headY,top,left
    local function header(title,subtitle)
      if m.big then
        local bx=max(1,m.L-6)
        left=max(m.L,bx+6)
        Pn.cells(bx,m.headTop,startScreen.remember("back"..hx(T.bg),function()return M.markCells(M.MARKS.back,hx(T.text),hx(T.bg),0,0)end))
        hit(bx,m.headTop,5,3,function()go("home")end)
        local room=actionX-left-24
        if M.textWidth(title)/2<=room then
          Pn.cells(left,m.headTop,startScreen.headingCells(title,hx(T.text),hx(T.bg)))
          if subtitle then text(left+floor(M.textWidth(title)/2)+3,m.headTop+2,clip(subtitle,actionX-left-floor(M.textWidth(title)/2)-26),T.muted)end
        else
          text(left,m.headTop+1,clip(title,actionX-left-24),T.text)
          if subtitle then text(left,m.headTop+2,clip(subtitle,actionX-left-24),T.muted)end
        end
        headY,top=m.headTop+1,m.headTop+4
      else
        fill(1,1,W,1,T.surface)
        text(1,1," \27 ",T.text,T.surface);hit(1,1,3,1,function()go("home")end)
        text(5,1,clip(title,W-28),T.text,T.surface)
        if subtitle then text(6+#title,1,clip(subtitle,W-34-#title),T.muted,T.surface)end
        headY,top,left=1,3,2
      end
    end
    -- Header commands, laid out from the right edge.
    local function action(label,fn,disabled)
      local w=#label+4;actionX=actionX-w
      button(actionX,headY,w,label,fn,false,disabled);actionX=actionX-2
    end
    local right=W-max(1,floor(m.L/2))

    -- A paged list: colour chip, name, and a second muted line when room.
    local function list(items, y, endY, opts)
      opts=opts or {}
      local width=right-left+1
      local cols=width>=110 and 3 or(width>=64 and 2 or 1)
      local colW=floor((width-(cols-1)*3)/cols)
      local detail=false;for _,it in ipairs(items)do if it.detail then detail=true end end
      local rowH=(detail and m.big and endY-y>=9)and 3 or 1
      local perCol=max(1,floor((endY-y+1)/rowH))
      if #items>perCol*cols then perCol=max(1,floor((endY-y)/rowH))end
      local per=perCol*cols
      local pages=max(1,ceil(#items/per))
      v.page=max(1,min(v.page or 1,pages))
      local off=(v.page-1)*per
      for i=1,per do
        local item=items[off+i];if not item then break end
        local col=floor((i-1)/perCol)
        local r=(i-1)%perCol
        local xx,yy=left+col*(colW+3),y+r*rowH
        local tx=xx
        if item.color and rowH>1 then
          -- Two-line rows get an 18px square, like 8.1 list icons.
          Pn.fill(xx,yy,3,2,item.color);tx=xx+4
        elseif item.color then
          Pn.cells(xx,yy,{{string.char(131),hx(T.bg),hx(item.color)}});tx=xx+2
        end
        text(tx,yy,clip(item.label,colW-(tx-xx)),item.fg or T.text)
        if rowH>1 and item.detail then text(tx,yy+1,clip(item.detail,colW-(tx-xx)),T.muted)end
        if item.fn then hit(xx,yy,colW,max(1,rowH-1),item.fn)end
      end
      if #items==0 then text(left,y,opts.empty or "Nothing here yet",T.muted)end
      startScreen.scrollbar(Pn,m,left,v.page,pages,function(p)v.page=max(1,min(pages,p))end,T.bg,right,endY)
    end

    local bottom=H
    if v.view == "music" then
      local title=info.discTitle or info.title
      header("Music",title and(info.state=="playing"and "Now playing"or "Paused")or nil)
      -- AppBar: now-playing text on the left, transport commands on the right.
      local rings=m.big and H>=30
      local barH=rings and 6 or 1
      local barY=H-barH+1
      fill(1,barY,W,barH,T.surface)
      local controls={{"prev","Previous",A.prev},{info.state=="playing"and "pause"or "play",info.state=="playing"and "Pause"or "Play",A.toggle},
        {"next","Next",A.next},{"stop","Stop",function()if info.disc then A.stopDisc()else A.stop()end end}}
      if rings then
        local x=right-#controls*11+3
        for i,c in ipairs(controls)do
          local bx=x+(i-1)*11
          Pn.cells(bx,barY+1,circleButton(c[1],T.surface))
          center(bx-2,barY+5,10,c[2],T.text,T.surface)
          hit(bx-2,barY+1,10,5,c[3])
        end
        text(left,barY+1,clip(title or "Nothing playing",x-left-3),T.text,T.surface)
        text(left,barY+2,clip(title and(info.state=="playing"and "Playing"or "Paused")or "Choose a song below",x-left-3),T.muted,T.surface)
      else
        local x=right+1
        for i=#controls,1,-1 do local c=controls[i];x=x-#c[2]-3;button(x,barY,#c[2]+2,c[2],c[3],i==2,false,1)end
        if x-left-1>=6 then text(left,barY,clip(title or "Music",x-left-1),T.text,T.surface)end
      end
      local tracks,items={},{}
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
        local current=title==item.title
        items[#items + 1] = { label = item.title, detail = item.path, color=current and T.accent or T.orange, fn = function() A.play(tracks, i) end }
      end
      list(items,top,barY-(rings and 2 or 1),{empty="No songs found. Put .dfpwm or .wav files on this computer."})
    elseif v.view == "files" then
      header("Files",v.path)
      action("Refresh",function()v.message=nil end)
      action("Up",function()v.path="/"..fs.getDir(v.path);v.page=1 end,v.path=="/")
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
            local size=not dir and(pcall(fs.getSize,path)and fs.getSize(path))
            items[#items + 1] = { label = n, color=dir and T.warn or(audioFile(path)and T.orange or T.info),
              detail = dir and "File folder" or ((size and(size<1024 and size.." bytes"or floor(size/102.4)/10 .." KB")or "File")..(audioFile(path)and " - tap to play"or "")),
              fn = function()
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
      list(items, top, bottom, {empty="This folder is empty"})
    elseif v.view == "reader" then
      header(v.readName or "Reader","Text preview")
      action("Print",function()
        run(function() local ok, result = K.api.printText(v.readName, v.readText); return ok and "Printed" or result end, "Print file")
      end)
      action("Files",function()go("files")end)
      local width=right-left+1
      local lines = {}
      for found in ((v.readText or "") .. "\n"):gmatch("([^\n]*)\n") do
        local line = found:gsub("\t", "    ")
        if #line == 0 then lines[#lines + 1] = "" end
        while #line > 0 do lines[#lines + 1] = line:sub(1, width); line = line:sub(width + 1) end
      end
      local n = max(1, bottom - top)
      local pages=max(1,ceil(#lines/n))
      v.page=max(1,min(v.page or 1,pages))
      local off=(v.page-1)*n
      for i = 1, n do text(left, top + i - 1, lines[off + i] or "", T.text) end
      startScreen.scrollbar(Pn,m,left,v.page,pages,function(p)v.page=max(1,min(pages,p))end,T.bg,right,bottom)
    elseif v.view == "devices" then
      header("Devices",info.speakers.." speakers")
      local items = {}
      for _, d in ipairs(K.hw.drives or {}) do
        items[#items + 1] = { label = d.name .. ": " .. (d.label or d.audio or (d.present and "Disk" or "Empty")), color=T.info,
          detail = d.audio and "Tap to play disc" or (d.mount and "Tap to browse disk" or "No data disk"), fn = function()
            if d.audio then A.playDisc(d.name); go("music")
            elseif d.mount then v.path = "/" .. d.mount; go("files") end
          end }
      end
      for _, p in ipairs(K.hw.printers or {}) do items[#items + 1] = { label = p.name, color=T.green, detail = (p.paper or 0) .. " paper / " .. (p.ink or 0) .. " ink" } end
      items[#items + 1] = { label = "Test left speaker", color=T.orange, detail = info.speakers .. " speakers connected", fn = function() A.note("bell", 12, -1, 1.5) end }
      items[#items + 1] = { label = "Test right speaker", color=T.orange, detail="Plays a bell on the right channel", fn = function() A.note("bell", 12, 1, 1.5) end }
      list(items, top, bottom)
    elseif v.view == "settings" then
      P.settings(s,v,m,Pn,{text=text,fill=fill,hit=hit,button=button,go=go,center=center})
    elseif v.view == "notifications" then
      header("Notifications",K.unread>0 and(K.unread.." new")or nil)
      local items = {}
      for _, n in ipairs(K.notifs) do items[#items + 1] = { label = n.title, detail = n.text, color=n.color or T.accent } end
      if K.unread > 0 then K.unread = 0; K.markAll() end
      list(items, top, bottom, {empty="You're all caught up"})
    elseif v.view == "power" then
      header("Power")
      local items={{"Restart","reboot",T.accent2},{"Shut down","shutdown",T.danger},{"Exit to CraftOS","exit",T.raised,"Exit"}}
      local w=min(24,floor((right-left-#items+1)/#items));local h=m.big and min(8,bottom-top-1)or 3
      for i,it in ipairs(items)do
        local x=left+(i-1)*(w+1)
        local tile=startScreen.remember("pw"..it[2]..w..h..hx(it[3]),function()
          local cv=M.tileCanvas(w,h,hx(it[3]),hx(T.bg))
          if h>=5 then M.placeGlyph(cv,M.MARKS.power,w,h,"0",true)end
          return gfx.cells(cv.rows(),hx(it[3]))
        end)
        Pn.cells(x,top,tile)
        text(x+1,top+h-2,clip((#it[1]>w-2 and it[4])or it[1],w-2),T.text,it[3])
        hit(x,top,w,h,function()v.confirm=it[2]end)
      end
      if v.confirm then
        local q={reboot={"Restart this computer?","Restart"},shutdown={"Shut down this computer?","Shut down"},exit={"Exit to CraftOS?","Exit"}}
        local c=q[v.confirm]or q.shutdown
        P.band(s,c[1],v.confirm=="exit"and "Open apps close and the CraftOS shell opens. Run /ccos/kernel.lua to come back."or "Open apps close and unsaved work is lost.",
          {{"Cancel",function()v.confirm=nil end},{c[2],function()K.power=v.confirm;K.running=false end}},Pn)
      end
    else
      go("home")
    end
    if v.message then startScreen.toast(Pn,s,m,v)end
  end

  -- F2 and the console's Start button: back to Start from anywhere.
  function P.home(s)
    s.picture=s.picture or {}
    local v=s.picture
    v.view,v.flyout,v.appPid,v.page,v.search,v.confirm,v.message="home",nil,nil,1,nil,nil,nil
    K.markAll()
  end

  -- Keys while Start or a built-in page is in front (apps get their own).
  -- Typing on Start searches apps, like the 8.1 Start screen.
  function P.keyboard(s,ev)
    s.picture=s.picture or {view="home",page=1,path="/"}
    local v=s.picture
    local e,k=ev[1],ev[2]
    local function pageBy(d)
      if v.view=="home"then v.startPage=(v.startPage or 1)+d
      elseif v.view=="apps"then v.appsPage=(v.appsPage or 1)+d
      else v.page=max(1,(v.page or 1)+d)end
    end
    if e=="char"or e=="paste"then
      if v.view=="home"or v.view=="apps"then
        local add=tostring(k):gsub("[%c]","")
        if v.view=="home"and add:match("^%s*$")then return end
        v.search=((v.search or "")..add):sub(1,30);v.view="apps";v.appsPage=1;v.flyout=nil
        K.markAll()
      end
      return
    end
    if e~="key"then return end
    if k==keys.backspace then
      if v.search then v.search=v.search:sub(1,-2);if v.search==""then v.search=nil end;v.appsPage=1
      elseif v.view=="files"and v.path and v.path~="/"then v.path="/"..fs.getDir(v.path);v.page=1
      elseif v.view=="reader"then v.view,v.page="files",1
      elseif v.view~="home"then P.home(s);return end
    elseif k==keys.escape then
      if v.flyout then v.flyout=nil
      elseif v.confirm then v.confirm=nil
      elseif v.search then v.search=nil;v.appsPage=1
      elseif v.view~="home"then P.home(s);return end
    elseif(k==keys.enter or k==keys.numPadEnter)and v.view=="apps"and v.search then
      local first=startScreen.search(v.search)[1]
      if first then v.search=nil;if P.go then P.go(first.id)end end
    elseif k==keys.left or k==keys.pageUp or k==keys.up then pageBy(-1)
    elseif k==keys.right or k==keys.pageDown or k==keys.down then pageBy(1)
    elseif k==keys.home then P.home(s);return
    else return end
    K.markAll()
  end

  -- 8.1 toasts: the newest notification in a dark box at the top right,
  -- with a colour strip for its app. Tap to act on it; x dismisses.
  function P.toasts(s)
    local t=K.toasts[1]
    if not t or s.w<40 then return end
    local n=t.n
    local Pn=startScreen.painter(s)
    local W=s.w
    local w=min(W-4,max(30,min(44,floor(W*0.3))))
    local x=W-w-1
    local y=(s.picture and s.picture.view~="home"and s.picture.view~="apps")and 2 or 1
    local lines={}
    for word in tostring(n.text or ""):gmatch("%S+")do
      if #lines==0 or #lines[#lines]+#word+1>w-5 then lines[#lines+1]=word else lines[#lines]=lines[#lines].." "..word end
    end
    while #lines>2 do table.remove(lines)end
    local h=3+#lines
    Pn.fill(x,y,w,h,T.surface)
    Pn.fill(x,y,2,h,n.color or T.accent)
    Pn.text(x+3,y+1,clip(n.title,w-7),T.text,T.surface)
    for i,l in ipairs(lines)do Pn.text(x+3,y+1+i,clip(l,w-5),T.muted,T.surface)end
    Pn.text(x+w-2,y+1,"\215",T.muted,T.surface)
    local toast=t
    local function dismiss()for i,o in ipairs(K.toasts)do if o==toast then table.remove(K.toasts,i);break end end end
    Pn.hit(x,y,w-3,h,function()dismiss();if n.action then n.action()end end)
    Pn.hit(x+w-3,y,3,h,dismiss)
  end

  -- An 8.1 message band: full width, centred column, buttons on the right.
  function P.band(s,title,body,buttons,Pn,opts)
    Pn=Pn or startScreen.painter(s)
    local W,H=s.w,s.h
    local cw=min(W-4,max(40,floor(W*0.55)))
    local x=floor((W-cw)/2)+1
    local lines={}
    for word in tostring(body or ""):gmatch("%S+")do
      if #lines==0 or #lines[#lines]+#word+1>cw then lines[#lines+1]=word else lines[#lines]=lines[#lines].." "..word end
    end
    opts=opts or {}
    local big=H>=24 and M.textWidth(title)/2<=cw
    local titleH=big and 3 or 1
    local h=3+titleH+#lines+(#lines>0 and 1 or 0)+(opts.field and 2 or 0)+1
    local y=max(1,floor((H-h)/2)+1)
    Pn.hit(1,1,W,H,function()end)
    Pn.fill(1,y,W,h,T.surface)
    if big then Pn.cells(x,y+1,startScreen.headingCells(title,hx(T.text),hx(T.surface)))
    else Pn.text(x,y+1,title:sub(1,cw),T.text,T.surface)end
    local yy=y+1+titleH+1
    for i,l in ipairs(lines)do Pn.text(x,yy+i-1,l,T.text,T.surface)end
    yy=yy+#lines+(#lines>0 and 1 or 0)
    if opts.field then
      local shown=opts.field.secret and ("*"):rep(#opts.field.text)or opts.field.text
      if #shown>cw-2 then shown=shown:sub(-(cw-2))end
      Pn.fill(x,yy,cw,1,T.bg)
      Pn.text(x+1,yy,shown~=""and shown or "Type on the computer",shown~=""and T.text or T.muted,T.bg)
      yy=yy+2
    end
    local bx=x+cw
    for i=#buttons,1,-1 do
      local b=buttons[i];local w=max(10,#b[1]+4);bx=bx-w
      local primary=i==(opts.primary or #buttons)
      Pn.fill(bx,yy,w,1,primary and T.accent or T.raised)
      Pn.text(bx+floor((w-#b[1])/2),yy,b[1],T.text,primary and T.accent or T.raised)
      Pn.hit(bx,yy,w,1,b[2]);bx=bx-2
    end
  end

  ----------------------------------------------------------------------
  -- PC settings: category pane on the Start colour, controls on the right.
  ----------------------------------------------------------------------
  local function fmtOffset(n)local sign=n<0 and "-"or "+";n=math.abs(n);return ("UTC%s%d:%02d"):format(sign,floor(n/60),n%60)end
  local function cycle(list,current,key)
    local index=1;for i,x in ipairs(list)do if (key and x[key] or x)==current then index=i end end
    local nxt=list[index%#list+1];return key and nxt[key]or nxt
  end
  local ROLE_NAMES={picture="Big Picture",panel="Info panel",off="Off"}
  local ROLE_NEXT={picture="panel",panel="off",off="picture"}
  local IDLE={0,60,300,600,1800}
  local function idleName(n)return n==0 and "Never"or(n<60 and n.." seconds"or floor(n/60)..(n<120 and " minute"or " minutes"))end
  local function prompt(title,body,default,apply)
    K.spawn(function()local text=K.api.prompt(title,body,default);if text then apply(text)end;K.markAll()end,{title=title})
  end
  function P.settingsPages()
    local cfg=K.cfg;local A=K.audio
    local function toggle(label,key)return{kind="toggle",label=label,on=cfg[key]==true,fn=function()K.api.config(key,not cfg[key])end}end
    local function nameIn(list,id)for _,c in ipairs(list or {})do if c.id==id then return c.name end end;return id end
    local display={}
    for _,sc in ipairs(K.screens)do
      if sc.kind=="monitor"then
        local cur=type(sc.scaleCfg)=="number"and sc.scaleCfg or(sc.target.getTextScale and sc.target.getTextScale()or 1)
        display[#display+1]={kind="choice",label=sc.name.." shows",value=ROLE_NAMES[sc.role]or sc.role,fn=function()K.api.setScreen(sc.name,ROLE_NEXT[sc.role]or "picture")end}
        if sc.role~="off"then
          display[#display+1]={kind="stepper",label=sc.name.." text size",value=(sc.scaleCfg=="auto"and "Auto "or "")..cur,
            down=function()K.api.setScreen(sc.name,nil,max(0.5,cur-0.5))end,up=function()K.api.setScreen(sc.name,nil,min(5,cur+0.5))end}
          if sc.scaleCfg~="auto"then display[#display+1]={kind="button",label=sc.name.." automatic size",value="Auto",fn=function()K.api.setScreen(sc.name,nil,"auto")end}end
        end
      end
    end
    if #display==0 then display[1]={kind="info",label="Monitors",value="None connected"}end
    display[#display+1]={kind="info",label="Computer",value=(K.screens[1]and K.screens[1].role=="console")and "Keyboard for Big Picture"or "Big Picture"}
    display[#display+1]={kind="stepper",label="Panel pages every",value=(cfg.panelRotate or 12).." s",
      down=function()K.api.config("panelRotate",max(4,(cfg.panelRotate or 12)-2))end,up=function()K.api.config("panelRotate",min(3600,(cfg.panelRotate or 12)+2))end}
    local idleNext=IDLE[1];for i,n in ipairs(IDLE)do if n==cfg.idle then idleNext=IDLE[i%#IDLE+1]end end
    local agent=K.agent
    return {
      {name="Personalize",items={
        {kind="choice",label="Start colour",value=nameIn(K.START_COLORS,cfg.startColor),fn=function()K.api.config("startColor",cycle(K.START_COLORS,cfg.startColor,"id"))end},
        {kind="choice",label="Accent colour",value=nameIn(K.ACCENT_COLORS,cfg.accentColor),fn=function()K.api.config("accentColor",cycle(K.ACCENT_COLORS,cfg.accentColor,"id"))end},
        {kind="button",label="Your name",value=tostring(cfg.user),fn=function()prompt("Your name","What should ccOS call you?",cfg.user,function(t)if t~=""then K.api.config("user",t:sub(1,40))end end)end},
        {kind="choice",label="Screen saver after",value=idleName(cfg.idle or 0),fn=function()K.api.config("idle",idleNext)end},
      }},
      {name="Time and language",items={
        {kind="choice",label="Time zone",value=cfg.timezone,fn=function()K.api.config("timezone",cycle(K.clock.zones,cfg.timezone))end},
        {kind="stepper",label="UTC offset",value=fmtOffset(cfg.utcOffset),
          down=function()K.api.config("timezone","fixed");K.api.config("utcOffset",max(-720,cfg.utcOffset-15))end,
          up=function()K.api.config("timezone","fixed");K.api.config("utcOffset",min(840,cfg.utcOffset+15))end},
        toggle("24-hour clock","clock24"),toggle("Pad hour with zero","leadingZero"),toggle("Show seconds","seconds"),
      }},
      {name="Sound",items={
        {kind="slider",label="Music volume",value=cfg.musicVolume,fn=function(f)A.setVolume(f)end},
        {kind="slider",label="Balance",value=((cfg.balance or 0)+1)/2,shown=(cfg.balance or 0)==0 and "Centre"or(cfg.balance<0 and floor(-cfg.balance*100+0.5).."% L"or floor(cfg.balance*100+0.5).."% R"),fn=function(f)A.setBalance(floor((f*2-1)*20+0.5)/20)end},
        {kind="slider",label="System sound volume",value=cfg.uiVolume or 0.6,fn=function(f)K.api.config("uiVolume",floor(f*20+0.5)/20);K.sfx("notify")end},
        toggle("System sounds","sounds"),toggle("Touch sounds","touchSounds"),toggle("Swap stereo speakers","swapSpeakers"),
        {kind="button",label="Test speakers",value="Left",fn=function()A.note("bell",12,-1,1.5)end,second={"Right",function()A.note("bell",12,1,1.5)end}},
      }},
      {name="Display",items=display},
      {name="AI Agent",items={
        {kind="button",label="Assistant",value="Open AI Agent",fn=function()P.go("agent")end},
        {kind="button",label="OpenRouter key",value=agent and agent.configured()and "Change"or "Add key",fn=function()if agent then agent.configure()end end},
        {kind="button",label="Model",value=tostring(cfg.agentModel),fn=function()prompt("OpenRouter model","A model id with tool calling.",cfg.agentModel,function(t)if agent and t~=""then local ok,why=agent.selectModel(t);if not ok then K.notify("Model",why,{quiet=true})end end end)end},
        toggle("Review changes first","agentConfirm"),
        {kind="stepper",label="Step limit",value=tostring(cfg.agentMaxSteps),down=function()K.api.config("agentMaxSteps",max(1,cfg.agentMaxSteps-1))end,up=function()K.api.config("agentMaxSteps",min(40,cfg.agentMaxSteps+1))end},
      }},
      {name="Update and recovery",items={
        {kind="info",label="Version",value="ccOS "..tostring(K.version or "")},
        toggle("Automatic update checks","autoUpdates"),
        {kind="button",label=K.updates and K.updates.status or "Updates",value=(K.updates and K.updates.available)and "Install"or "Check now",
          fn=function()if not K.updates then return end;if K.updates.available then K.updates.prompt()else K.updates.check(true)end end},
        {kind="button",label="Recovery",value="Exit to CraftOS",fn=function()K.confirmPower(K.pictureScreen()or K.homeScreen(),"exit")end},
      }},
    }
  end

  local function drawControl(o,it,x,y,w,ui)
    local text,fill,hit,button=ui.text,ui.fill,ui.hit,ui.button
    if it.kind=="toggle"then
      if it.on then fill(x,y,3,1,T.accent);fill(x+3,y,1,1,T.text)else fill(x,y,1,1,T.text);fill(x+1,y,3,1,T.raised)end
      text(x+5,y,it.on and "On"or "Off",T.text)
      hit(x,y,8,1,it.fn)
    elseif it.kind=="choice"then
      local bw=min(w,24)
      fill(x,y,bw,1,T.raised);text(x+1,y,clip(it.value,bw-4),T.text,T.raised);text(x+bw-2,y,"\31",T.text,T.raised)
      hit(x,y,bw,1,it.fn)
    elseif it.kind=="stepper"then
      button(x,y,3,"-",it.down);text(x+4,y,it.value,T.text);button(x+5+#it.value,y,3,"+",it.up)
    elseif it.kind=="slider"then
      local bw=min(w-6,24);local at=floor(it.value*(bw-1)+0.5)
      local line=string.char(140)
      o.cells(x,y,{{line:rep(bw),hx(T.accent):rep(at)..hx(T.raised):rep(bw-at),hx(T.bg):rep(bw)}})
      fill(x+at,y,1,1,T.text)
      text(x+bw+2,y,it.shown or(floor(it.value*100+0.5).."%"),T.text)
      hit(x,y,bw,1,function(tx)it.fn(max(0,min(1,((tx or x)-x)/(bw-1))))end)
    elseif it.kind=="button"then
      local label=clip(it.value,max(1,w-4))
      button(x,y,#label+4,label,it.fn,true)
      if it.second then button(x+#label+5,y,#it.second[1]+4,it.second[1],it.second[2],true)end
    elseif it.kind=="info"then
      text(x,y,clip(it.value,w),T.muted)
    end
  end

  function P.settings(s,v,m,o,ui)
    local W,H=s.w,s.h
    local pages=P.settingsPages()
    v.settingsPage=max(1,min(v.settingsPage or 1,#pages))
    local page=pages[v.settingsPage]
    local text,fill,hit=ui.text,ui.fill,ui.hit
    local two=W>=64
    local paneW,left,top
    if m.big then
      local bx=max(1,m.L-6);left=max(m.L,bx+6)
      paneW=two and min(floor(W/2),max(floor(W*0.3),left+floor(M.textWidth("PC settings")/2)+3))or W
      fill(1,1,paneW,H,T.select)
      o.cells(bx,m.headTop,startScreen.remember("back"..hx(T.select),function()return M.markCells(M.MARKS.back,hx(T.text),hx(T.select),0,0)end))
      hit(bx,m.headTop,5,3,function()if not two and v.settingsOpen then v.settingsOpen=nil else ui.go("home")end end)
      o.cells(left,m.headTop,startScreen.headingCells("PC settings",hx(T.text),hx(T.select)))
      top=m.headTop+4
    else
      paneW=two and 24 or W
      fill(1,1,paneW,H,T.select)
      text(1,1," \27 ",T.text,T.select);hit(1,1,3,1,function()if not two and v.settingsOpen then v.settingsOpen=nil else ui.go("home")end end)
      text(5,1,"PC settings",T.text,T.select)
      left,top=2,3
    end
    local showList=two or not v.settingsOpen
    if showList then
      local step=(m.big and H-top>=#pages*2)and 2 or 1
      for i,pg in ipairs(pages)do
        local y=top+(i-1)*step
        local sel=two and i==v.settingsPage
        if sel then fill(left-1,y,paneW-left,1,T.accent)end
        text(left,y,clip(pg.name,paneW-left-2),T.text,sel and T.accent or T.select)
        hit(1,y,paneW,1,function()v.settingsPage=i;v.settingsOpen=true;v.settingsScroll=1 end)
      end
    end
    if two or v.settingsOpen then
      local rx=two and paneW+max(3,m.L) or left
      local rw=W-rx-max(1,floor(m.L/2))
      local y
      if m.big then
        if two and M.textWidth(page.name)/2>rw then text(rx,m.headTop+1,clip(page.name,rw),T.text)
        elseif two then o.cells(rx,m.headTop,startScreen.headingCells(page.name,hx(T.text),hx(T.bg)))
        else fill(1,1,W,H,T.bg);o.cells(left,m.headTop,startScreen.headingCells(page.name,hx(T.text),hx(T.bg)))
          o.cells(max(1,m.L-6),m.headTop,startScreen.remember("back"..hx(T.bg),function()return M.markCells(M.MARKS.back,hx(T.text),hx(T.bg),0,0)end)) end
        y=m.headTop+4
      else
        if not two then fill(1,1,W,H,T.bg);fill(1,1,W,1,T.surface);text(1,1," \27 ",T.text,T.surface);text(5,1,page.name,T.text,T.surface)
        else text(rx,1,clip(page.name,rw),T.text)end
        y=3
      end
      local n=#page.items;local room=H-y+1
      local stacked=room>=n*3 or(room>=n*2 and rw<40)
      local step=room>=n*3 and 3 or(room>=n*2 and 2 or 1)
      -- Long pages scroll a page of rows at a time.
      local per=n
      if n*step>room then per=max(1,room-1) end
      local pages=max(1,ceil(n/per))
      v.settingsScroll=max(1,min(v.settingsScroll or 1,pages))
      local first=(v.settingsScroll-1)*per
      for i=first+1,min(n,first+per)do
        local it=page.items[i]
        if stacked and step>=2 then
          text(rx,y,clip(it.label,rw),T.text);drawControl(o,it,rx,y+1,rw,ui)
        else
          local lw=min(floor(rw/2),26)
          text(rx,y,clip(it.label,lw-1),T.text);drawControl(o,it,rx+lw,y,rw-lw,ui)
        end
        if it.fn and it.kind~="slider"then hit(rx,y,min(rw,#it.label),1,it.fn)end
        y=y+step
      end
      if pages>1 then startScreen.scrollbar(o,m,rx,v.settingsScroll,pages,function(p)v.settingsScroll=max(1,min(pages,p))end,T.bg,rx+rw-1,H)end
    end
  end
  return P
end
