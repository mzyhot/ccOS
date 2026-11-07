-- The computer as Big Picture's keyboard. While the main monitor runs Big
-- Picture, the computer shows what the keyboard is typing into: a prompt's
-- text, an AI Agent message, the app in front, or search on Start.
return function(K,T)
  local I={draft="",error=nil}
  local max,min,floor=math.max,math.min,math.floor
  local function fieldDialog()
    for _,s in ipairs(K.screens)do
      local d=s.dialogs and s.dialogs[1]
      if d and d.field then return d end
    end
  end
  -- Agent chat typed here goes to the monitor's AI Agent. Returns true when
  -- the key was used.
  function I.keyboard(ev,monitor)
    if not(K.agent and not K.agent.busy)then return false end
    local e=ev[1]
    if e=="char"or e=="paste"then I.draft=(I.draft..ev[2]):sub(1,12000);I.error=nil
    elseif e=="key"and ev[2]==keys.backspace then I.draft=I.draft:sub(1,-2)
    elseif e=="key"and(ev[2]==keys.enter or ev[2]==keys.numPadEnter)then
      local ok,why=K.agent.start(I.draft,"terminal");if ok then I.draft=""else I.error=why end
    else return false end
    K.markAll();return true
  end
  local function nameOf(id)
    for _,a in ipairs(K.APPS)do if a.id==id then return a.name end end
    local builtin={home="Start",apps="Apps",music="Music",files="Files",reader="Reader",devices="Devices",settings="PC settings",notifications="Notifications",power="Power"}
    return builtin[id]or id
  end
  function I.draw(s,monitor)
    local b,W,H=s.buf,s.w,s.h
    local function text(x,y,t,fg,bg)
      if y<1 or y>H or x>W then return end
      t=tostring(t or ""):sub(1,max(0,W-x+1));b.setCursorPos(x,y);b.setTextColor(fg or T.text);b.setBackgroundColor(bg or T.bg);b.write(t)
    end
    local function fill(y,h,bg)for yy=y,min(H,y+h-1)do text(1,yy,(" "):rep(W),bg,bg)end end
    local function hit(x,y,w,fn)s.hits[#s.hits+1]={x1=x,y1=y,x2=x+w-1,y2=y,fn=fn}end
    local function button(x,y,label,fn,primary)
      local w=#label+2
      text(x,y," "..label.." ",T.text,primary and T.accent or T.raised);hit(x,y,w,fn)
      return x+w+1
    end
    local v=monitor.picture or {}
    local function go(view)monitor.picture=monitor.picture or {};local p=monitor.picture;p.view,p.flyout,p.appPid,p.page=view,nil,nil,1;K.markAll()end
    -- Top bar on the Start colour: where the keyboard is going.
    fill(1,H,T.bg);fill(1,1,T.select)
    text(2,1,"ccOS keyboard",T.text,T.select)
    local clock=K.clockText(false)
    text(W-#clock,1,clock,T.text,T.select)
    local d=fieldDialog()
    local app=K.pictureApp(monitor)
    local agent=v.view=="agent"and not d
    local title,body,secret,hint
    if d then title,body,secret=d.title,d.field.text,d.field.secret
      hint=secret and "Hidden. Enter saves, Esc cancels."or "Enter submits, Esc cancels."
    elseif agent and K.agent and not K.agent.busy then title,body,hint="Message AI Agent",I.draft,"Enter sends your message to the monitor."end
    if title then
      text(2,3,title,T.text)
      text(2,4,hint,T.muted)
      local shown=secret and("*"):rep(#body)or body
      local width=max(1,W-4);local room=max(1,H-9)
      local chunks={}
      for i=1,#shown,width do chunks[#chunks+1]=(shown:sub(i,i+width-1):gsub("\n"," "))end
      if #chunks==0 or #chunks[#chunks]==width then chunks[#chunks+1]=""end
      local first=max(1,#chunks-room+1)
      for yy=6,5+room do text(2,yy,(" "):rep(W-2),T.text,T.surface)end
      for i=first,#chunks do text(3,6+i-first,chunks[i],T.text,T.surface)end
      local line=chunks[#chunks]
      s.cursor={x=min(W-1,3+#line),y=min(5+room,6+#chunks-first),color=T.accent}
      if I.error and not d then text(2,H-2,I.error:sub(1,W-2),T.warn)end
      if d then
        local okLabel=d.buttons[#d.buttons]or "OK"
        button(W-#okLabel-2,H-1,okLabel,function()K.answerDialog(d.screen,d,#d.buttons)end,true)
        button(W-#okLabel-13,H-1,"Cancel",function()K.answerDialog(d.screen,d,1)end)
      else
        button(W-7,H-1,"Send",function()I.keyboard({"key",keys.enter},monitor)end,true)
        button(W-17,H-1,"Clear",function()I.draft="";I.error=nil;K.markAll()end)
      end
      return
    end
    -- Nothing to type into: show what the monitor shows and how to type.
    local where=app and nameOf(app.app and app.app.id or "")or nameOf(v.view or "home")
    text(2,3,"Big Picture is on "..monitor.name,T.text)
    text(2,4,"Showing: "..where,T.accent)
    local lines
    if app then lines={"Keys you press here go to "..where..".","F2 returns the monitor to Start."}
    elseif v.view=="agent"and K.agent and K.agent.busy then lines={"AI Agent: "..tostring(K.agent.status),"F2 returns the monitor to Start."}
    else lines={"Tap tiles on the monitor to open apps.","Type here to search apps on Start.","F1 opens AI Agent; F2 returns to Start."}end
    for i,l in ipairs(lines)do text(2,5+i,l,T.muted)end
    if v.search and v.search~=""then text(2,6+#lines+1,"Search: "..v.search,T.text)end
    if K.updates and K.updates.available then button(2,H-3,"Update available",function()K.updates.prompt()end,true)end
    -- The bottom bar mirrors the monitor's main places.
    fill(H-1,2,T.surface)
    local x=2
    x=button(x,H-1,"Start",function()go("home")end,v.view=="home"and not app)
    x=button(x,H-1,"Apps",function()go("apps")end,v.view=="apps")
    x=button(x,H-1,"AI Agent",function()K.launch("agent",{},{screen=monitor})end,v.view=="agent")
    if x+14<=W then button(x,H-1,"PC settings",function()go("settings")end,v.view=="settings")end
  end
  return I
end
