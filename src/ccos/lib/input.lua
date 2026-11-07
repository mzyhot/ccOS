-- Computer keyboard bridge for Big Picture. Never renders the desktop.
return function(K,T)
  local I={draft="",error=nil}
  local function fieldDialog(monitor)
    for _,s in ipairs(K.screens)do
      local d=s.dialogs and s.dialogs[1]
      if d and d.field then return d end
    end
  end
  function I.keyboard(ev,monitor)
    local e=ev[1]
    local d=fieldDialog(monitor)
    if d then
      if e=="char"or e=="paste"then d.field.text=(d.field.text..ev[2]):sub(1,d.field.secret and 1024 or 12000)
      elseif e=="key"and ev[2]==keys.backspace then d.field.text=d.field.text:sub(1,-2)
      elseif e=="key"and ev[2]==keys.enter then K.answerDialog(d.screen,d,#d.buttons)
      elseif e=="key"and ev[2]==keys.escape then K.answerDialog(d.screen,d,1)end
      K.markAll();return
    end
    local agent=monitor.picture and monitor.picture.view=="agent"
    if agent and K.agent and not K.agent.busy then
      if e=="char"or e=="paste"then I.draft=(I.draft..ev[2]):sub(1,12000);I.error=nil
      elseif e=="key"and ev[2]==keys.backspace then I.draft=I.draft:sub(1,-2)
      elseif e=="key"and ev[2]==keys.enter then local ok,why=K.agent.start(I.draft,"terminal");if ok then I.draft=""else I.error=why end end
      K.markAll()
    end
  end
  function I.draw(s,monitor)
    local b,W,H=s.buf,s.w,s.h
    local function text(x,y,t,fg,bg)
      if y<1 or y>H then return end
      t=tostring(t or ""):sub(1,math.max(0,W-x+1));b.setCursorPos(x,y);b.setTextColor(fg or T.text);b.setBackgroundColor(bg or T.bg);b.write(t)
    end
    local function fill(y,h,bg)for yy=y,math.min(H,y+h-1)do text(1,yy,(" "):rep(W),bg,bg)end end
    local function button(x,y,label,fn)
      text(x,y," "..label.." ",T.text,T.raised)
      s.hits[#s.hits+1]={x1=x,y1=y,x2=x+#label+1,y2=y,fn=fn}
    end
    fill(1,H,T.bg);fill(1,1,T.surface)
    text(2,1,"ccOS  |  Monitor input",T.accent,T.surface)
    button(2,H,"AI Agent",function()K.launch("agent",{},{screen=monitor})end)
    button(13,H,"Settings",function()monitor.picture=monitor.picture or {};monitor.picture.view="settings";K.markAll()end)
    button(W-12,H,"Full Sync",function()K.setFullSync(true)end)
    local d=fieldDialog(monitor)
    local agent=monitor.picture and monitor.picture.view=="agent"
    local body,title,secret
    if d then title,body,secret=d.title,d.field.text,d.field.secret
    elseif agent and not K.agent.busy then title,body="Message AI Agent",I.draft
    else
      text(2,4,"Big Picture is on "..monitor.name,T.text)
      text(2,6,"Tap a tool or prompt on the monitor.",T.muted)
      text(2,7,"Type here when it asks for text.",T.muted)
      if agent and K.agent.busy then text(2,9,"AI Agent: "..K.agent.status,T.accent)end
      if K.updates and K.updates.available then
        button(2,H-3,"Update available",function()K.updates.prompt()end)
      end
      return
    end
    text(2,3,title,T.text)
    text(2,5,secret and "Hidden input. Enter to save; Esc to cancel."or "Enter to submit. Esc cancels a prompt.",T.muted)
    local shown=secret and("*"):rep(#body)or body
    local width=math.max(1,W-4);local room=math.max(1,H-10)
    local chunks={};if shown==""then chunks[1]=""end
    for i=1,#shown,width do chunks[#chunks+1]=shown:sub(i,i+width-1):gsub("\n"," ")end
    local first=math.max(1,#chunks-room+1)
    fill(7,room,T.surface)
    for i=first,#chunks do text(3,7+i-first,chunks[i],T.text,T.surface)end
    local line=chunks[#chunks]or ""
    s.cursor={x=math.min(W-1,3+#line),y=math.min(H-4,7+#chunks-first),color=T.accent}
    if d then
      button(2,H-2,"Cancel",function()K.answerDialog(d.screen,d,1)end)
      button(W-11,H-2,d.buttons[#d.buttons]or "Submit",function()K.answerDialog(d.screen,d,#d.buttons)end)
    else
      button(2,H-2,"Clear",function()I.draft="";K.markAll()end)
      button(W-8,H-2,"Send",function()I.keyboard({"key",keys.enter},monitor)end)
    end
    if I.error then text(2,H-3,I.error,T.warn)end
  end
  return I
end
