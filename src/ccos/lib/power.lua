-- Windows 8.1-style progress ring: five dots chase round a circle on the
-- Start colour, slowing as they gather at the top and spreading as they
-- sweep the bottom. Used while booting and for the power transition. A
-- plain status line; no fabricated progress.
return function(K,gfx,T)
  local P={duration=1.6,frameTime=0.06}
  local floor,max,min=math.floor,math.max,math.min
  local TAU=math.pi*2
  -- The ring as teletext cells for a screen of W x H; r scales with it.
  function P.ring(W,H,frame,bg,fg,limit)
    local r=max(4,min(limit or 11,floor(min(W*2,H*3)/8)))
    local dot=r>=8 and 2 or 1
    local size=2*r+dot+2
    local cw,ch=size+size%2,size+(3-size%3)%3
    local cv=gfx.canvas(cw,ch,bg)
    local c=(size+1)/2
    local t=frame*P.frameTime
    for i=0,4 do
      local u=(t/1.25-i*0.09)%1
      local a=u-0.11*math.sin(TAU*u)
      local x=floor(c+math.sin(TAU*a)*r-(dot-1)/2+0.5)
      local y=floor(c-math.cos(TAU*a)*r-(dot-1)/2+0.5)
      for dy=0,dot-1 do for dx=0,dot-1 do cv.set(x+dx,y+dy,fg)end end
    end
    return gfx.cells(cv.rows(),bg),cw/2
  end
  -- A light heading line when the screen is big enough, else plain text.
  function P.label(target,W,y,text,bg,fg)
    local M=gfx.metro
    if M and W>=60 and M.textWidth(text)/2<=W-4 then
      local lc=M.markCells(M.textRows(text),gfx.HEX[fg],gfx.HEX[bg],0,1)
      gfx.drawCells(target,max(1,floor((W-#lc[1][1])/2)+1),y,lc)
      return 3
    end
    target.setBackgroundColor(bg);target.setTextColor(fg)
    target.setCursorPos(max(1,floor((W-#text)/2)+1),y);target.write(text:sub(1,W))
    return 1
  end
  function P.draw(target,W,H,frame,kind)
    target.setCursorBlink(false);target.setBackgroundColor(T.select);target.setTextColor(T.text);target.clear()
    local bg,fg=gfx.HEX[T.select],gfx.HEX[T.text]
    local cells,cw=P.ring(W,H,frame,bg,fg)
    local label=kind=="shutdown"and "Shutting down"or "Restarting"
    local labelRows=(W>=60 and H>=24)and 3 or 1
    local top=max(1,floor((H-#cells-1-labelRows)/2)+1)
    gfx.drawCells(target,floor((W-cw)/2)+1,top,cells)
    local ly=min(H,top+#cells+1)
    if labelRows==3 then P.label(target,W,ly,label,T.select,T.text)
    else target.setCursorPos(max(1,floor((W-#label)/2)+1),ly);target.write(label:sub(1,W))end
  end
  function P.play(kind)
    for frame=1,math.ceil(P.duration/P.frameTime)do
      for _,s in ipairs(K.screens)do if s.role~="off"then pcall(P.draw,s.target,s.w,s.h,frame,kind)end end
      local timer=os.startTimer(P.frameTime)
      repeat local e,id=os.pullEventRaw()until e=="timer"and id==timer
    end
  end
  return P
end
