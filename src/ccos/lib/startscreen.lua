-- Windows 8.1-style Start for Big Picture. Tiles sit on the 70/150/310 grid:
-- a small tile is sw x sh cells (square on screen), medium 2x2 units, wide
-- 4x2, and every tile leaves a one-teletext-pixel gutter on its right and
-- bottom edge (3 screen pixels each way). Groups flow in column blocks four
-- units wide, like the real Start, and pages pan by whole blocks.
return function(K,gfx,T)
  local S={}
  local floor,min,max=math.floor,math.min,math.max
  local M=gfx.metro
  local function hx(c)return gfx.HEX[c]or"f"end

  local CAT={Files=T.warn,Time=T.info,Media=T.orange,Math=T.ok,Text=T.accent2,Developer=T.surface,System=T.magenta,Games=T.green,AI=T.accent}
  local COLOR={
    files=T.warn,viewer=T.info,print=T.green,notes=T.magenta,checklist=T.ok,journal=T.accent2,bookmarks=T.danger,
    disks=T.info,storage=T.orange,backup=T.accent,clock=T.info,calendar=T.accent2,worldclock=T.accent,focus=T.danger,stopwatch=T.orange,
    timer=T.green,music=T.orange,piano=T.hot,paint=T.magenta,soundtest=T.info,metronome=T.accent2,calc=T.green,units=T.ok,
    percentage=T.info,base=T.accent2,random=T.orange,tally=T.accent,textstats=T.accent2,textcase=T.info,lines=T.ok,replace=T.orange,
    urlencode=T.accent,base64=T.magenta,terminal=T.surface,edit=T.info,lua=T.accent2,json=T.orange,http=T.accent,network=T.green,
    logs=T.raised,settings=T.accent2,tasks=T.green,about=T.info,devices=T.orange,notifications=T.danger,redstone=T.danger,
    analog=T.orange,bundled=T.magenta,peripherals=T.accent,inventory=T.warn,energy=T.ok,fluids=T.info,sysinfo=T.accent2,
    display=T.info,palette=T.hot,worm=T.ok,dice=T.danger,coin=T.warn,lights=T.orange,memory=T.accent2,tictactoe=T.info,
    guess=T.magenta,agent=T.accent,
  }
  -- Shorter tile names, used only when the full name does not fit.
  local SHORT={calc="Calc",print="Print",notifications="Alerts",units="Units",percentage="Percent",base="Bases",random="Random",
    textstats="Text stats",textcase="Case",replace="Replace",urlencode="URL encode",peripherals="Peripheral",analog="Analog",
    bundled="Bundled",inventory="Inventory",energy="Energy",fluids="Fluids",disks="Disks",storage="Storage",backup="Backups",
    sysinfo="System",display="Displays",palette="Colours",soundtest="Speakers",metronome="Metronome",lights="Lights Out",
    memory="Memory",tictactoe="Tic-tac",worldclock="World time",timer="Countdown",network="Network",http="HTTP",json="JSON",
    logs="Logs",guess="Guess",coin="Coin flip",tally="Counter"}
  -- Eight-character names for the smallest medium tiles.
  local TINY={checklist="To-do",bookmarks="Links",stopwatch="Watch",timer="Timer",metronome="Tempo",inventory="Items",
    peripherals="Hardware",textstats="Stats",urlencode="URL",lights="Lights",worldclock="World",calendar="Calendar",
    percentage="Percent",textcase="Case",backup="Backups",network="Network",storage="Storage"}
  S.SHORT,S.TINY=SHORT,TINY
  function S.color(a)return COLOR[a.id]or CAT[a.category]or T.accent end
  function S.label(a,room)
    if #a.name<=room then return a.name end
    local short=SHORT[a.id]
    if short and #short<=room then return short end
    local tiny=TINY[a.id]
    if tiny and #tiny<=room then return tiny end
    local first=a.name:match("^(%S+)")
    if first and #first<=room and #first>=3 then return first end
    return a.name:sub(1,room)
  end

  local SIZE={small={1,1},medium={2,2},wide={4,2},large={4,4}}
  local SW={[2]=3,[3]=5,[4]=6,[5]=8}

  -- Every position on the Start screen, in cells, for a W x H monitor.
  function S.metrics(W,H)
    local m={W=W,H=H}
    m.big=H>=17 and W>=48
    m.L=max(2,floor(W*0.055+0.5))
    if m.big then
      m.headTop=max(1,floor(H*0.05+0.5))
      m.groupRow=m.headTop+4
      m.tilesTop=m.groupRow+(H>=30 and 2 or 1)
      m.arrowH=H>=24 and 3 or 2
      m.arrowTop=H>=30 and H-3 or H-m.arrowH+1
      m.tilesBottom=m.arrowTop-(H>=30 and 2 or 1)
    else
      m.headTop,m.groupRow,m.tilesTop=1,2,3
      m.arrowH,m.arrowTop=1,H
      m.tilesBottom=H-2
    end
    m.contentTop,m.contentBottom=m.groupRow,m.tilesBottom
    local R=m.tilesBottom-m.tilesTop+1
    for _,want in ipairs({6,4,2})do
      for _,c in ipairs({5,4,3,2})do
        if not m.sh and 2*floor(R/(2*c))>=want and(want<6 or c>=3)then m.sh=c end
      end
      if m.sh then break end
    end
    m.sh=m.sh or 2;m.sw=SW[m.sh]
    m.Rs=max(2,2*floor(R/(2*m.sh)))
    local shift=floor(max(0,R-m.Rs*m.sh)/2)
    m.groupRow,m.tilesTop=m.groupRow+shift,m.tilesTop+shift
    m.avail=W-m.L
    m.blockUnits=8*m.sw<=m.avail and 4 or 2
    m.groupGap=max(2,m.sw)
    m.scrollRow=H
    return m
  end

  -- First-fit tiles into column blocks; a group always starts a new block.
  function S.place(groups,m)
    local blocks={}
    for _,g in ipairs(groups)do
      local block
      local function new()block={group=g,first=block==nil,tiles={},grid={}};blocks[#blocks+1]=block end
      new()
      for _,tile in ipairs(g.tiles)do
        local size=tile.size or "medium";local d=SIZE[size]
        if d[1]>m.blockUnits or d[2]>m.Rs then size="medium";d=SIZE.medium end
        local function free(c,r)
          for y=r,r+d[2]-1 do for x=c,c+d[1]-1 do if block.grid[y*8+x]then return false end end end
          return true
        end
        local function find()
          for r=0,m.Rs-d[2],d[2]>=2 and 2 or 1 do
            for c=0,m.blockUnits-d[1],d[1]>=2 and 2 or 1 do if free(c,r)then return c,r end end
          end
        end
        local c,r=find()
        if not c then new();c,r=find()end
        for y=r,r+d[2]-1 do for x=c,c+d[1]-1 do block.grid[y*8+x]=true end end
        block.tiles[#block.tiles+1]={app=tile.app,size=size,c=c,r=r,uw=d[1],uh=d[2]}
      end
    end
    return blocks
  end

  function S.paginate(blocks,m)
    local bw=m.blockUnits*m.sw
    local pages,page,x={},nil,0
    for _,b in ipairs(blocks)do
      local gap=(page and #page.blocks>0 and b.first)and m.groupGap or 0
      if not page or x+gap+bw>m.avail then page={blocks={}};pages[#pages+1]=page;x,gap=0,0 end
      b.x=x+gap;page.blocks[#page.blocks+1]=b;x=b.x+bw
    end
    if #pages==0 then pages[1]={blocks={}}end
    return pages
  end

  function S.pageTiles(page,m)
    local list={}
    for _,b in ipairs(page.blocks)do
      for _,t in ipairs(b.tiles)do
        list[#list+1]={app=t.app,size=t.size,block=b,x=m.L+b.x+t.c*m.sw,y=m.tilesTop+t.r*m.sh,w=t.uw*m.sw,h=t.uh*m.sh}
      end
    end
    return list
  end

  -- Flat card list to pages of positioned tiles (used by layout checks).
  function S.layout(cards,W,H)
    local m=S.metrics(W,H)
    local g={tiles={}}
    for _,a in ipairs(cards)do g.tiles[#g.tiles+1]={app=a,size=(a.id=="music"or a.id=="clock")and "wide"or "medium"}end
    local out={}
    for i,p in ipairs(S.paginate(S.place({g},m),m))do out[i]=S.pageTiles(p,m)end
    return out,m
  end

  -- Pinned group first, then one group per category for everything else.
  function S.groups()
    local byId,seen={}, {}
    for _,a in ipairs(K.APPS)do byId[a.id]=a end
    local pinned={tiles={}}
    local function pin(a,size)if a and not seen[a.id]then pinned.tiles[#pinned.tiles+1]={app=a,size=size};seen[a.id]=true end end
    pin(byId.clock,"wide");pin(byId.music,"wide")
    for _,id in ipairs({"files","agent","settings","terminal","calendar"})do pin(byId[id],"medium")end
    for _,id in ipairs(K.cfg.monitorFavorites or {})do pin(byId[id],"medium")end
    local groups={pinned}
    for _,cat in ipairs(K.catalog.categories)do
      if cat~="Favorites"then
        local g={name=cat,tiles={}}
        for _,a in ipairs(K.APPS)do
          if not a.hidden and a.category==cat and not seen[a.id]then g.tiles[#g.tiles+1]={app=a,size="medium"}end
        end
        if #g.tiles>0 then groups[#groups+1]=g end
      end
    end
    return groups
  end

  ----------------------------------------------------------------------
  -- Drawing
  ----------------------------------------------------------------------
  local cache,cached={},0
  local function remember(key,build)
    local v=cache[key]
    if not v then
      if cached>160 then cache,cached={},0 end
      v=build();cache[key]=v;cached=cached+1
    end
    return v
  end

  local function painter(s)
    local b,W,H=s.buf,s.w,s.h
    local P={}
    function P.text(x,y,t,fg,back)
      t=tostring(t or "")
      if y<1 or y>H or x>W or t==""then return end
      if x<1 then t=t:sub(2-x);x=1 end
      b.setCursorPos(x,y);b.setTextColor(fg or T.text);b.setBackgroundColor(back or T.select);b.write(t:sub(1,max(0,W-x+1)))
    end
    function P.fill(x,y,w,h,c)if w>0 then for yy=max(1,y),min(H,y+h-1)do P.text(x,yy,(" "):rep(w),c,c)end end end
    function P.cells(x,y,cells)
      for i,c in ipairs(cells)do
        local yy=y+i-1
        if yy>=1 and yy<=H then
          local t,f,bk=c[1],c[2],c[3]
          if x<1 then t,f,bk=t:sub(2-x),f:sub(2-x),bk:sub(2-x)end
          local room=W-max(1,x)+1
          if room>0 then b.setCursorPos(max(1,x),yy);b.blit(t:sub(1,room),f:sub(1,room),bk:sub(1,room))end
        end
      end
    end
    function P.hit(x,y,w,h,fn)s.hits[#s.hits+1]={x1=max(1,x),y1=max(1,y),x2=min(W,x+w-1),y2=min(H,y+h-1),fn=function(...)fn(...);K.markAll()end}end
    return P
  end
  S.painter=painter

  -- Heading-face text as cells, its capitals one pixel below the cell top.
  function S.headingCells(text,fg,bg)
    return remember("h"..text..fg..bg,function()return M.markCells(M.textRows(text),fg,bg,0,1)end)
  end

  S.remember=remember
  local function dateText(fmt)
    local ok,v=pcall(K.clock.date,K.cfg,fmt)
    return ok and v or ""
  end

  -- One tile, including live content. Returns nothing; registers its hit.
  local function drawTile(P,t,bg,go)
    local a,x,y,pw,ph=t.app,t.x,t.y,t.w,t.h
    local color=S.color(a);local c,g=hx(color),hx(bg)
    local room=pw-2
    local label=S.label(a,room)
    local live
    if a.id=="clock"then
      local now=K.clockText(false)
      local digits,suffix=now:match("^(.-)%s*([AP]M)$")
      digits=digits or now
      local top=ph>=8 and 4 or 1
      local date=dateText("%A %d %B")
      if #date>room then date=dateText("%a %d %b")end
      if #date>room then date=dateText("%a %d")end
      -- Light digits when they fit inside the tile; plain text otherwise.
      if 2+M.textWidth(digits)+(suffix and 6 or 0)<=pw*2-2 then
        local cells=remember("clock"..now..pw..ph..c..g,function()
          local cv=M.tileCanvas(pw,ph,c,g)
          M.drawText(cv,3,top+1,digits,"0",1)
          return gfx.cells(cv.rows(),c)
        end)
        P.cells(x,y,cells)
        if suffix then
          local tx=x+floor((3+M.textWidth(digits))/2)+1
          P.text(tx,y+floor((top+6)/3),suffix,T.text,color)
        end
        local dateY=y+floor((top+6)/3)+1
        P.text(x+1,dateY,date:sub(1,room),T.text,color)
        -- The time speaks for itself when the name would crowd the date.
        if y+ph-2-dateY<2 then label=nil end
      else
        P.cells(x,y,remember("plain"..pw..ph..c..g,function()return gfx.cells(M.tileCanvas(pw,ph,c,g).rows(),c)end))
        P.text(x+1,y+1,now:sub(1,room),T.text,color)
        P.text(x+1,y+2,date:sub(1,room),T.text,color)
      end
      live=true
    elseif a.id=="calendar"then
      local day=tostring(tonumber(dateText("%d"))or dateText("%d"))
      local scale=ph*3-1>=22 and 2 or 1
      local cells=remember("cal"..day..pw..ph..c..g..scale,function()
        local cv=M.tileCanvas(pw,ph,c,g)
        local w=M.textWidth(day,scale)
        local top=scale==2 and 3 or max(2,floor(((ph-2)*3-7)/2)+1)
        M.drawText(cv,floor((pw*2-1-w)/2)+1,top,day,"0",scale)
        return gfx.cells(cv.rows(),c)
      end)
      P.cells(x,y,cells)
      local wd=dateText("%A");label=#wd<=room and wd or wd:sub(1,3)
      live=true
    elseif a.id=="music"and t.size=="wide"then
      local info=K.audio.info()
      local title=info.discTitle or info.title
      local playing=info.state=="playing"
      local cells=remember("music"..pw..ph..c..g..tostring(title~=nil),function()
        local cv=M.tileCanvas(pw,ph,c,g)
        local rows=M.glyph("music")
        if title then M.stamp(cv,pw*2-1-#rows[1]-3,4,rows,"0")else M.placeGlyph(cv,rows,pw,ph,"0",true)end
        return gfx.cells(cv.rows(),c)
      end)
      P.cells(x,y,cells)
      if title then
        local tw=room-6
        P.text(x+1,y+1,tostring(title):sub(1,tw),T.text,color)
        if ph>=5 then P.text(x+1,y+2,(playing and "Now playing"or "Paused"):sub(1,tw),T.text,color)end
      end
      live=true
    end
    if not live then
      local cells=remember("t"..a.id..pw..ph..c..g,function()
        local cv=M.tileCanvas(pw,ph,c,g)
        M.placeGlyph(cv,M.glyph(a.id),pw,ph,"0",true)
        return gfx.cells(cv.rows(),c)
      end)
      P.cells(x,y,cells)
    end
    if label then P.text(x+1,y+ph-2,label,T.text,color)end
    if a.id=="notifications"and(K.unread or 0)>0 then
      local n=tostring(min(99,K.unread));P.text(x+pw-2-#n,y+ph-2,n,T.text,color)
    end
    P.hit(x,y,pw,ph,function()go(a.id)end)
  end

  local function arrow(P,m,x,kind,fn)
    local small=m.arrowH<3
    -- Too short for the circled mark: the font's own crisp arrow, on the
    -- scrollbar row.
    if not m.big or small then
      local mark=kind=="down"and "\25"or "\24"
      local y=m.big and m.scrollRow or m.arrowTop
      P.text(x,y,mark,T.text,T.select);P.hit(x-1,y-(m.big and 1 or 0),3,m.big and 2 or 1,fn);return 1
    end
    local rows=M.MARKS[kind..(small and "Small"or "")]
    local cells=remember("a"..kind..tostring(small)..hx(T.select),function()return M.markCells(rows,hx(T.text),hx(T.select),0,0)end)
    P.cells(x,m.arrowTop,cells);P.hit(x,m.arrowTop,#cells[1][1],#cells,fn)
    return #cells[1][1]
  end

  local function scrollbar(P,m,x1,page,pages,set,bg,x2,y)
    if pages<2 then return end
    bg=bg or T.select;x2=x2 or m.W-1;y=y or m.scrollRow
    if x2-x1<8 then return end
    P.text(x1,y,"\17",T.text,bg);P.text(x2,y,"\16",T.text,bg)
    P.hit(x1-1,y,2,1,function()set(page-1)end);P.hit(x2,y,2,1,function()set(page+1)end)
    local tx,tw=x1+2,x2-x1-3
    local thumb=max(2,floor(tw/pages));local at=tx+floor((page-1)*(tw-thumb)/max(1,pages-1)+0.5)
    local line=string.char(140)
    P.cells(tx,y,{{line:rep(tw),hx(T.raised):rep(tw),hx(bg):rep(tw)}})
    P.cells(at,y,{{line:rep(thumb),hx(T.muted):rep(thumb),hx(bg):rep(thumb)}})
    if at>tx then P.hit(tx,y,at-tx,1,function()set(page-1)end)end
    if at+thumb<=tx+tw-1 then P.hit(at+thumb,y,tx+tw-at-thumb,1,function()set(page+1)end)end
  end

  -- User name, account picture, power and search, right-aligned.
  local function header(P,s,m,title,go,v)
    local W=s.w;local bg=hx(T.select)
    if not m.big then
      P.text(m.L,1,title,T.text)
      local px=W-6;P.text(px,1,"Power",T.text);P.hit(px,1,5,1,function()v.flyout="power"end)
      return px
    end
    P.cells(m.L,m.headTop,S.headingCells(title,hx(T.text),bg))
    local right=W-max(1,floor(m.L/2))
    local sx=right-3
    local search=remember("search"..bg,function()return M.markCells(M.MARKS.search,hx(T.text),bg,0,0)end)
    P.cells(sx,m.headTop,search);P.hit(sx,m.headTop,4,3,function()v.view="apps";v.flyout=nil end)
    local px=sx-6
    local power=remember("power"..bg,function()return M.markCells(M.MARKS.power,hx(T.text),bg,0,1)end)
    P.cells(px,m.headTop,power);P.hit(px,m.headTop,4,3,function()v.flyout=v.flyout~="power"and "power"or nil end)
    local ax=px-7
    local avatar=remember("avatar"..bg,function()
      local cv=gfx.canvas(10,9,bg);M.rect(cv,1,1,9,9,hx(T.raised));M.stamp(cv,1,1,M.MARKS.avatar,hx(T.muted))
      return gfx.cells(cv.rows(),bg)
    end)
    P.cells(ax,m.headTop,avatar)
    local user=tostring(K.cfg.user or "")
    local nx=max(m.L+floor(M.textWidth(title)/2)+3,ax-2-#user)
    user=user:sub(1,max(0,ax-2-nx))
    P.text(ax-2-#user,m.headTop+1,user,T.text)
    P.hit(ax-2-#user,m.headTop,#user+7,3,function()go("settings")end)
    return px
  end

  local function flyout(P,s,m,px,v)
    if v.flyout~="power"then return end
    local items={{"Shut down","shutdown"},{"Restart","reboot"},{"Exit to CraftOS","exit"}}
    local w=19
    local x=min(s.w-w,px+4-w);local y=m.big and m.headTop+3 or 2
    P.hit(1,1,s.w,s.h,function()v.flyout=nil end)
    P.fill(x,y,w,#items+2,T.text)
    for i,it in ipairs(items)do
      P.text(x+2,y+i,it[1],T.bg,T.text)
      P.hit(x,y+i,w,1,function()v.flyout=nil;K.power=it[2];K.running=false end)
    end
  end

  S.scrollbar=scrollbar
  local function toast(P,s,m,v)
    if not v.message then return end
    local w=min(s.w-4,max(24,#v.message+4));local x=s.w-w-1;local y=m.big and m.groupRow or 2
    P.fill(x,y,w,3,T.surface);P.fill(x,y,1,3,T.accent)
    P.text(x+2,y+1,v.message:sub(1,w-4),T.text,T.surface)
    P.hit(x,y,w,3,function()v.message=nil end)
  end
  S.toast=toast

  function S.draw(s,go)
    local P=painter(s);local v=s.picture;local W,H=s.w,s.h
    local m=S.metrics(W,H)
    P.fill(1,1,W,H,T.select)
    local pages=S.paginate(S.place(S.groups(),m),m)
    v.startPage=max(1,min(v.startPage or 1,#pages))
    local px=header(P,s,m,"Start",go,v)
    local page=pages[v.startPage]
    for _,b in ipairs(page.blocks)do
      if b.first and b.group.name then P.text(m.L+b.x,m.groupRow,b.group.name:sub(1,m.blockUnits*m.sw-1),T.text)end
    end
    for _,t in ipairs(S.pageTiles(page,m))do drawTile(P,t,T.select,go)end
    local aw=arrow(P,m,m.L,"down",function()v.view="apps";v.appsPage=1;v.flyout=nil end)
    scrollbar(P,m,(m.arrowTop+m.arrowH-1>=m.scrollRow)and m.L+aw+2 or m.L,v.startPage,#pages,function(p)v.startPage=max(1,min(#pages,p))end)
    toast(P,s,m,v)
    flyout(P,s,m,px,v)
  end

  ----------------------------------------------------------------------
  -- Apps by category, or search results while typing
  ----------------------------------------------------------------------
  -- Visible apps whose name, id or description contains the query.
  function S.search(query)
    local q=tostring(query or ""):lower()
    local starts,contains={},{}
    for _,a in ipairs(K.APPS)do
      if not a.hidden then
        local name=a.name:lower()
        if name:sub(1,#q)==q then starts[#starts+1]=a
        elseif name:find(q,1,true)or a.id:find(q,1,true)or(a.desc or ""):lower():find(q,1,true)then contains[#contains+1]=a end
      end
    end
    for _,a in ipairs(contains)do starts[#starts+1]=a end
    return starts
  end

  function S.appColumns(m,query)
    local colW=min(24,max(16,m.avail))
    local cols=max(1,floor((m.avail+2)/(colW+2)))
    local rows=max(3,m.contentBottom-m.contentTop+1)
    local columns,col={},nil
    local function put(item)
      if not col or #col>=rows then col={};columns[#columns+1]=col end
      col[#col+1]=item
    end
    if query and query~=""then
      local found=S.search(query)
      put({header=#found==1 and "1 app"or(#found.." apps")})
      for _,a in ipairs(found)do put({app=a})end
      return columns,cols,colW,rows,found
    end
    for _,cat in ipairs(K.catalog.categories)do
      if cat~="Favorites"then
        local list={}
        for _,a in ipairs(K.APPS)do if not a.hidden and a.category==cat then list[#list+1]=a end end
        if #list>0 then
          if col and #col>0 and #col<rows then put(false)end
          if col and #col>=rows-1 then col=nil end
          put({header=cat})
          for _,a in ipairs(list)do put({app=a})end
        end
      end
    end
    return columns,cols,colW,rows
  end

  -- The 8.1 Apps search box: white field, query or hint, magnifier mark.
  local function searchBox(P,s,m,v,px)
    local W=s.w
    local right=W-max(1,floor(m.L/2))
    local w=min(28,max(14,floor(W*0.22)))
    local x=right-w+1
    local y=m.big and m.headTop+1 or 1
    local q=v.search or ""
    P.fill(x,y,w,1,T.text)
    local shown=q~=""and q:sub(-(w-4))or "Search apps"
    P.text(x+1,y,shown,q~=""and T.bg or T.muted,T.text)
    if q~=""then P.text(x+w-2,y,"\215",T.bg,T.text);P.hit(x+w-3,y,3,1,function()v.search=nil;v.appsPage=1 end)end
    P.hit(x,y,w-(q~=""and 3 or 0),1,function()
      K.spawn(function()
        local text=K.api.prompt("Search apps","Type part of an app's name.",v.search or "")
        if text then v.search=text~=""and text:sub(1,30)or nil;v.appsPage=1;K.markAll()end
      end,{title="Search"})
    end)
    return x
  end

  function S.drawApps(s,go)
    local P=painter(s);local v=s.picture;local W,H=s.w,s.h
    local m=S.metrics(W,H)
    P.fill(1,1,W,H,T.select)
    local q=v.search
    local title=q and "Search"or "Apps"
    local px
    if m.big then
      P.cells(m.L,m.headTop,S.headingCells(title,hx(T.text),hx(T.select)))
      local bx=searchBox(P,s,m,v)
      local sx=m.L+floor(M.textWidth(title)/2)+3
      local room=max(0,bx-sx-2)
      local sub=q and("Results for \""..q.."\"")or "by category"
      if q and #sub>room then sub="\""..q.."\""end
      P.text(sx,m.headTop+2,sub:sub(1,room),T.muted)
      px=bx
    else
      P.text(m.L,1,title,T.text)
      local bx=searchBox(P,s,m,v)
      P.text(m.L+#title+1,1,(q and "results"or "by category"):sub(1,max(0,bx-m.L-#title-2)),T.muted)
      px=bx
    end
    local columns,cols,colW,_,found=S.appColumns(m,q)
    local pages=math.max(1,math.ceil(#columns/cols))
    v.appsPage=max(1,min(v.appsPage or 1,pages))
    local first=(v.appsPage-1)*cols
    -- A 6px square sitting on the text baseline, 3px apart from the next.
    local chip=string.char(131)
    for i=1,cols do
      local col=columns[first+i]
      if not col then break end
      local x=m.L+(i-1)*(colW+2)
      for r,item in ipairs(col)do
        local y=m.contentTop+r-1
        if item and item.header then
          P.text(x,y,item.header:sub(1,colW),q and T.muted or T.text)
        elseif item then
          local a=item.app;local c=S.color(a)
          local top=found and found[1]==a
          if top then P.fill(x,y,colW,1,T.raised)end
          P.cells(x,y,{{chip,hx(top and T.raised or T.select),hx(c)}})
          P.text(x+2,y,a.name:sub(1,colW-2),T.text,top and T.raised or T.select)
          P.hit(x,y,colW,1,function()v.search=nil;go(a.id)end)
        end
      end
    end
    if found and #found==0 then P.text(m.L,m.contentTop+1,"No apps match. Backspace edits the search.",T.muted)end
    local aw=arrow(P,m,m.L,"up",function()v.view="home";v.search=nil;v.flyout=nil end)
    scrollbar(P,m,(m.arrowTop+m.arrowH-1>=m.scrollRow)and m.L+aw+2 or m.L,v.appsPage,pages,function(p)v.appsPage=max(1,min(pages,p))end)
    toast(P,s,m,v)
    flyout(P,s,m,px,v)
  end

  return S
end
