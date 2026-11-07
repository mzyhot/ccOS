-- Hallmark: quiet Windows 8.1-inspired power transition; ccOS tokens only.
-- Pre-emit critique: P5 H5 E4 S5 R5 V4. No fabricated progress messages.
return function(K,gfx,T)
  local P={duration=1.6,frameTime=0.08}
  function P.draw(target,W,H,frame,kind)
    target.setCursorBlink(false);target.setBackgroundColor(T.select);target.setTextColor(T.text);target.clear()
    local size=math.min(18,W-2);local cv=gfx.canvas(size,15,gfx.HEX[T.select])
    for i=0,4 do
      local angle=(frame-i)*math.pi/6
      local x=math.floor(size/2+math.cos(angle)*5+0.5)+1
      local y=math.floor(7+math.sin(angle)*5+0.5)+1
      cv.set(x,y,gfx.HEX[i<3 and T.text or T.muted])
    end
    local cells=gfx.cells(cv.rows(),gfx.HEX[T.select]);local top=math.max(1,math.floor(H/2)-4)
    gfx.drawCells(target,math.floor((W-gfx.cellsWidth(cells))/2)+1,top,cells)
    local label=kind=="shutdown"and "Shutting down"or "Restarting"
    target.setCursorPos(math.max(1,math.floor((W-#label)/2)+1),math.min(H,top+#cells+1));target.write(label:sub(1,W))
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
