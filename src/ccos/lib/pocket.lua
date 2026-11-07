-- Hallmark: compact native pocket shell, flat tiles and keyboard focus.
-- Pre-emit critique: P5 H5 E4 S5 R5 V4. Uses ccOS tokens, no desktop scaling.
return function(K,T)
  local P={category=1,selected=1,page=1,view="home"};local floor,min,max=math.floor,math.min,math.max
  local function screen()for _,s in ipairs(K.screens)do if s.kind=="term"then return s end end end
  function P.home(view)local s=screen();s.pocketHome=true;P.view=view or "home";P.selected=1;P.page=1;K.markAll()end
  local function invoke(fn)K.spawn(fn,{title="Pocket action"});K.markAll()end
  local function toggle(key)K.api.config(key,not K.cfg[key])end
  function P.items()
    if P.view=="settings"then
      local function on(key)return K.cfg[key]and "On"or "Off"end
      return {
        {name="Time zone: "..K.cfg.timezone,fn=function()local i=1;for n,z in ipairs(K.clock.zones)do if z==K.cfg.timezone then i=n end end;K.api.config("timezone",K.clock.zones[i%#K.clock.zones+1])end},
        {name="24-hour: "..on("clock24"),fn=function()toggle("clock24")end},
        {name="Zero padding: "..on("leadingZero"),fn=function()toggle("leadingZero")end},
        {name="UTC offset: "..K.cfg.utcOffset,fn=function()local v=K.api.prompt("UTC minutes","-720 to 840",tostring(K.cfg.utcOffset));local n=tonumber(v);if n then K.api.config("timezone","fixed");K.api.config("utcOffset",max(-720,min(840,floor(n))))end end},
        {name="Auto updates: "..on("autoUpdates"),fn=function()toggle("autoUpdates")end},
        {name="Check updates",fn=function()K.updates.check(true)end},
        {name="Open AI Agent",fn=function()K.launch("agent",{},{screen=screen()})end},
        {name="Set OpenRouter key",fn=function()K.agent.configure()end},
        {name="Model: "..K.cfg.agentModel,fn=function()local v=K.api.prompt("OpenRouter model","Tool-capable model id",K.cfg.agentModel);if v then local ok,err=K.agent.selectModel(v);if not ok then K.api.alert("Model",err)end end end},
        {name="Review AI: "..on("agentConfirm"),fn=function()toggle("agentConfirm")end},
        {name="Name: "..K.cfg.user,fn=function()local v=K.api.prompt("Your name","",K.cfg.user);if v and v~=""then K.api.config("user",v:sub(1,40))end end},
        {name="Restart",fn=function()K.confirmPower(screen(),"reboot")end},
        {name="Shut down",fn=function()K.confirmPower(screen(),"shutdown")end},
        {name="Exit to CraftOS",fn=function()K.confirmPower(screen(),"exit")end},
      }
    end
    local category=K.catalog.categories[P.category];local favorites={files=true,terminal=true,agent=true,notes=true,calc=true,clock=true,settings=true,checklist=true}
    local list={}
    for _,a in ipairs(K.APPS)do if not a.hidden and((category=="Favorites"and favorites[a.id])or a.category==category)then
      list[#list+1]={name=a.name,id=a.id,fn=function()if a.id=="settings"then P.home("settings")else K.launch(a.id,{},{screen=screen()})end end}
    end end
    return list
  end
  function P.keyboard(ev)
    local s=screen();if ev[1]=="key"and ev[2]==keys.f2 then P.home();return true end
    if not s.pocketHome then return false end
    if ev[1]~="key"then return true end
    local k=ev[2];local items=P.items();local cols=P.view=="home"and 2 or 1
    if k==keys.tab then P.category=P.category%#K.catalog.categories+1;P.view="home";P.selected=1
    elseif k==keys.right then P.selected=min(#items,P.selected+1)
    elseif k==keys.left then P.selected=max(1,P.selected-1)
    elseif k==keys.down then P.selected=min(#items,P.selected+cols)
    elseif k==keys.up then P.selected=max(1,P.selected-cols)
    elseif k==keys.pageDown then P.selected=min(#items,P.selected+8)
    elseif k==keys.pageUp then P.selected=max(1,P.selected-8)
    elseif k==keys.enter then local item=items[P.selected];if item then invoke(item.fn)end
    elseif k==keys.escape then P.home()
    end
    K.markAll();return true
  end
  function P.draw(s)
    local b,W,H=s.buf,s.w,s.h
    local function text(x,y,t,fg,bg)
      if y<1 or y>H then return end
      b.setCursorPos(x,y);b.setTextColor(fg or T.text);b.setBackgroundColor(bg or T.bg);b.write(tostring(t or ""):sub(1,max(0,W-x+1)))
    end
    local function fill(y,h,color)for yy=y,min(H,y+h-1)do text(1,yy,(" "):rep(W),color,color)end end
    local function hit(x,y,w,h,fn)s.hits[#s.hits+1]={x1=x,y1=y,x2=x+w-1,y2=y+h-1,fn=fn}end
    local function button(x,y,label,fn)text(x,y,label,T.text,T.surface);hit(x,y,#label,1,fn)end
    fill(1,H,T.bg);fill(1,1,T.surface)
    local win=K.focus
    if not s.pocketHome and win and win.screen==s and not win.proc.dead and win.state~="min"then
      button(1,1,"< Start",function()P.home()end);text(9,1,win.title:sub(1,max(0,W-12)),T.accent,T.surface)
      button(W-2,1," x ",function()K.closeWindow(win);P.home()end)
      for row=1,win.h do local t,f,bg=win.buf.getLine(row);b.setCursorPos(1,row+1);b.blit(t,f,bg)end
      s.hits[#s.hits+1]={x1=1,y1=2,x2=W,y2=H-1,content=win}
    else
      s.pocketHome=true
      text(2,1,P.view=="settings"and "Pocket settings"or "ccOS Pocket",T.text,T.surface)
      local time=K.clockText(false);text(2,3,time,T.accent)
      local items=P.items();P.selected=max(1,min(P.selected,max(1,#items)))
      local cols=P.view=="home"and 2 or 1;local cellH=P.view=="home"and 3 or 1
      local count=max(1,floor((H-(cellH==1 and 9 or 8))/cellH))*cols
      local page=floor((P.selected-1)/count);local total=max(1,math.ceil(#items/count))
      if P.view=="home"then
        local label=K.catalog.categories[P.category]
        button(1,5,"<",function()P.category=(P.category-2)%#K.catalog.categories+1;P.selected=1;K.markAll()end)
        text(3,5,label:sub(1,W-4),T.muted)
        button(W,5,">",function()P.category=P.category%#K.catalog.categories+1;P.selected=1;K.markAll()end)
      end
      local cw=floor((W-3)/cols)
      for i=1,count do local index=page*count+i;local item=items[index];if not item then break end
        local x=2+((i-1)%cols)*(cw+1);local y=7+floor((i-1)/cols)*cellH
        local selected=index==P.selected;local bg=selected and T.accent or T.surface
        for yy=y,y+cellH-2 do text(x,yy,(" "):rep(cw),bg,bg)end
        text(x,y,item.name:sub(1,cw),selected and T.bg or T.text,bg)
        if cellH>1 then text(x,y+1,(index.." "):sub(1,cw),selected and T.bg or T.muted,bg)end
        hit(x,y,cw,max(1,cellH-1),function()P.selected=index;invoke(item.fn)end)
      end
      button(2,H-2,"< Prev",function()P.selected=max(1,P.selected-count);K.markAll()end)
      text(floor(W/2),H-2,(page+1).."/"..total,T.muted)
      button(W-6,H-2,"Next >",function()P.selected=min(#items,P.selected+count);K.markAll()end)
      text(2,H-1,"Arrows + Enter | Tab",T.muted)
    end
    fill(H,1,T.surface)
    button(1,H,"F2 Home",function()P.home()end)
    button(9,H,"Settings",function()P.home("settings")end)
    if K.agent and K.agent.pending then
      text(9,H,"F3 Yes | F4 No",T.accent,T.surface)
    else button(W-5,H,"Power",function()P.home("settings");P.selected=12;K.markAll()end)end
  end
  return P
end
