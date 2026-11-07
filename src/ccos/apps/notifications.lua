local ui,T=ccos.ui,ccos.ui.T
local app={title="Notifications",scroll={scroll=0}}
function app:draw(g)
  ccos.markNotificationsRead()
  local items=ccos.notifications()
  if #items==0 then g:center(2,"No notifications",T.muted);return end
  local rh=ui.touch()and 3 or 2
  g:list(self.scroll,2,1,g.w-2,g.h,items,function(n,_,x,y,w)
    g:text(x,y,ui.trunc(n.title,w),T.accent)
    g:text(x,y+1,ui.trunc(n.text,w),T.text)
  end,function(n)if n.action then n.action()end end,rh)
end
function app:onEvent(ev)return ev[1]=="ccos_agent"end
ui.run(app)
