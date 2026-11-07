-- Hallmark: Windows 8.1-inspired Start; native ccOS palette and typography.
-- Pre-emit critique: P5 H5 E4 S5 R4 V5. Grouped flat tiles, no text composer.
return function(K,gfx,T)
  local S={};local floor,min,max=math.floor,math.min,math.max
  local tileColors={Files=T.orange,Time=T.info,Media=T.accent2,Math=T.accent,Text=T.green,Developer=T.select,System=T.green,Games=T.hot,AI=T.accent}
  function S.layout(cards,W,H)
    local cols=max(2,min(5,floor((W-3)/14)));local rows=max(1,floor((H-7)/5))
    local cw=floor((W-3-(cols-1))/cols);local th=max(3,min(5,floor((H-7-(rows-1))/rows)))
    local pages={{}};local col,row=0,0
    for _,a in ipairs(cards)do
      local span=W>=60 and(a.id=="desktop"or a.id=="music"or a.id=="clock")and 2 or 1
      span=min(cols,max(span,math.ceil((#a.name+2)/cw)))
      if col+span>cols then col=0;row=row+1 end
      if row>=rows then pages[#pages+1]={};col,row=0,0 end
      local page=pages[#pages];page[#page+1]={app=a,x=2+col*(cw+1),y=6+row*(th+1),w=cw*span+span-1,h=th}
      col=col+span
    end
    return pages
  end
  function S.draw(s,go)
    local b,W,H=s.buf,s.w,s.h;local v=s.picture;local bg=T.select
    local function text(x,y,t,fg,back)
      if y<1 or y>H or x>W then return end
      b.setCursorPos(x,y);b.setTextColor(fg or T.text);b.setBackgroundColor(back or bg);b.write(tostring(t):sub(1,max(0,W-x+1)))
    end
    local function fill(x,y,w,h,c)for yy=y,min(H,y+h-1)do text(x,yy,(" "):rep(w),c,c)end end
    local function hit(x,y,w,h,fn)s.hits[#s.hits+1]={x1=x,y1=y,x2=x+w-1,y2=y+h-1,fn=function()fn();K.markAll()end}end
    local function button(x,y,label,fn)text(x,y,label,T.text,bg);hit(x,y,#label,1,fn)end
    fill(1,1,W,H,bg)
    if H>=15 then gfx.drawCells(b,2,1,gfx.pixelText("Start",1,"0",gfx.HEX[bg]))else text(2,1,"Start",T.text)end
    local user=tostring(K.cfg.user):sub(1,max(1,min(16,W-28)))
    text(W-#user-10,2,user,T.text);button(W-8,2,"Power",function()go("power")end)
    local categories={"Favorites","All"};for _,name in ipairs(K.catalog.categories)do if name~="Favorites"then categories[#categories+1]=name end end
    local index=1;for i,name in ipairs(categories)do if name==v.category then index=i end end
    button(2,4,"< Cat",function()v.category=categories[(index-2)%#categories+1];v.page=1 end)
    text(10,4,(v.category or "Favorites"):sub(1,max(1,W-19)),T.text)
    button(W-7,4,"Cat >",function()v.category=categories[index%#categories+1];v.page=1 end)
    local byId={};for _,a in ipairs(K.APPS)do byId[a.id]=a end
    local cards={}
    if v.category=="Favorites"then
      cards[#cards+1]={id="desktop",name="Desktop",category="System"}
      local seen={};local order={"files","music","clock","agent","settings"}
      for _,id in ipairs(K.cfg.monitorFavorites)do order[#order+1]=id end
      for _,id in ipairs(order)do if byId[id]and not seen[id]then cards[#cards+1]=byId[id];seen[id]=true end end
    else
      for _,a in ipairs(K.APPS)do if not a.hidden and(v.category=="All"or a.category==v.category)then cards[#cards+1]=a end end
    end
    local pages=S.layout(cards,W,H);v.page=max(1,min(v.page or 1,#pages))
    local info=K.audio.info()
    for _,tile in ipairs(pages[v.page])do
      local a,x,y,w,h=tile.app,tile.x,tile.y,tile.w,tile.h
      local color=tileColors[a.category]or T.accent
      if a.id=="desktop"then color=T.accent2 end
      fill(x,y,w,h,color)
      if a.id=="clock"and w>=19 then
        text(x+1,y+1,K.clockText(false):sub(1,w-2),T.text,color)
        if h>=5 then text(x+1,y+2,K.clock.date(K.cfg,"%a %d %b"),T.text,color)end
      elseif a.id=="music"and w>=19 then
        text(x+1,y+1,(info.title or info.discTitle or "Your music"):sub(1,w-2),T.text,color)
        if h>=5 then text(x+1,y+2,info.state=="playing"and "Now playing"or "Tap to browse",T.text,color)end
      elseif a.id=="desktop"then text(x+1,y+1,"Full Sync",T.text,color)
      else
        local source=gfx.ICONS[a.id]or gfx.ICONS.about
        local blank=source[1]:sub(1,1);local rows={}
        for i,line in ipairs(source)do rows[i]=line:gsub(".",function(c)return c==blank and gfx.HEX[color]or gfx.HEX[T.text]end)end
        gfx.drawCells(b,x+floor((w-4)/2),y+max(0,floor((h-3)/2)),gfx.cells(rows,gfx.HEX[color]))
      end
      text(x+1,y+h-1,a.name:sub(1,w-2),T.text,color)
      hit(x,y,w,h,function()if a.id=="desktop"then K.setFullSync(true)else go(a.id)end end)
    end
    button(2,H-1,"< Prev",function()v.page=max(1,v.page-1)end)
    local page=v.page.." / "..#pages;text(floor((W-#page)/2)+1,H-1,page,T.text)
    button(W-7,H-1,"Next >",function()v.page=min(#pages,v.page+1)end)
    button(2,H,v.category=="All"and "Favorites"or "All apps",function()v.category=v.category=="All"and "Favorites"or "All";v.page=1 end)
    text(floor(W/2)-1,H,"ccOS",T.text)
    local status=K.clockText(false);text(W-#status,H,status,T.text)
  end
  return S
end
