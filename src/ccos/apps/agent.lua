local ui,T,A=ccos.ui,ccos.ui.T,ccos.agent
local floor,max,min=math.floor,math.max,math.min
local initial=...
local app={title="AI Agent",tab=initial=="settings"and 3 or 1,input="",scroll={scroll=0},reviewScroll={scroll=0},seen=0}
local function act(g,y,items)
  local x,bh=2,ui.touch()and g.h>=18 and 2 or 1
  for _,it in ipairs(items)do
    if x+#it[1]+2>g.w then x=2;y=y+bh+1 end
    x=g:button(x,y,it[1],it[2],{h=bh,active=it[3],disabled=it[4]})+1
  end
  return y+bh+1
end
function app:send(text)
  local ok,err=A.start(text,"terminal")
  if ok then self.input=""else self.error=err end
end
function app:draw(g)
  local touch=ui.touch()
  local tabs={{"Chat",function()self.tab=1 end,self.tab==1},{g.w<40 and "Log"or "Activity",function()self.tab=2 end,self.tab==2}}
  if not(ccos.isPocket and ccos.isPocket())then tabs[#tabs+1]={g.h<12 and "Setup"or "Settings",function()self.tab=3 end,self.tab==3}end
  tabs[#tabs+1]={A.busy and "Stop"or(g.w<40 and "New"or "New chat"),function()if A.busy then A.cancel()else A.clear()end end}
  local y=act(g,1,tabs)
  g:text(2,y,ui.trunc(A.status.."  |  "..ccos.config("agentModel"),g.w-2),A.busy and T.accent or T.muted);y=y+2
  if A.pending then
    g:fill(2,y,g.w-2,1,T.raised);g:text(3,y,"Review: "..ui.trunc(A.pending.name,g.w-12),T.warn,T.raised)
    local details=ui.wrap(A.display(A.redact(ccos.json.encode(A.pending.arguments))),g.w-4)
    local count=min(#details,max(1,floor((g.h-y-5)/2)))
    if self.reviewIdentity~=A.pending then self.reviewIdentity=A.pending;self.reviewScroll.scroll=0 end
    g:list(self.reviewScroll,3,y+1,g.w-4,count,details,function(line,_,x,yy,w)g:text(x,yy,ui.trunc(line,w),T.text)end)
    y=act(g,y+count+1,{{"Allow action",function()A.approve(true)end,true},{"Deny action",function()A.approve(false)end},{"Stop task",A.cancel}})
  end
  if self.tab==3 then
    local lines={"OpenRouter: "..(A.configured()and "key saved"or "not configured"),"Review changes: "..(ccos.config("agentConfirm")and "On"or "Off (autonomous)"),"Step limit: "..ccos.config("agentMaxSteps"),"Output tokens / request: "..ccos.config("agentMaxTokens")}
    for _,line in ipairs(lines)do if y<g.h-2 then g:text(2,y,ui.trunc(line,g.w-2),T.text);y=y+1 end end
    do
      y=act(g,y+1,{{"API key",A.configure},{"Models",function()self.tab=4;A.refreshModels()end},{"Model ID",function()
        local model=ccos.prompt("OpenRouter model","A model id with tool calling",ccos.config("agentModel"))
        if model then local ok,why=A.selectModel(model);if not ok then self.error=why end end
      end},{"Review "..(ccos.config("agentConfirm")and "On"or "Off"),function()ccos.config("agentConfirm",not ccos.config("agentConfirm"))end}})
      y=act(g,y,{{"Steps -",function()ccos.config("agentMaxSteps",max(1,ccos.config("agentMaxSteps")-1))end},{"Steps +",function()ccos.config("agentMaxSteps",min(40,ccos.config("agentMaxSteps")+1))end},{"Remove key",function()if ccos.confirm("Remove API key?","The AI agent will be disconnected.","Remove")then A.setKey("")end end}})
      y=act(g,y,{{"Tokens -",function()ccos.config("agentMaxTokens",max(256,ccos.config("agentMaxTokens")-256))end},{"Tokens +",function()ccos.config("agentMaxTokens",min(8192,ccos.config("agentMaxTokens")+256))end}})

    end
  elseif self.tab==4 then
    y=act(g,y,{{"Refresh",A.refreshModels},{self.showPaid and "Show free only"or "Include paid",function()self.showPaid=not self.showPaid end}})
    g:text(2,y,ui.trunc(A.display(A.modelStatus or "Refresh to load models"),g.w-2),T.muted);y=y+2
    local models={};for _,m in ipairs(A.models or {})do if self.showPaid or m.free then models[#models+1]=m end end
    g:list(self.scroll,2,y,g.w-2,max(1,g.h-y),models,function(m,_,x,yy,w)g:text(x,yy,ui.trunc((m.free and "Free: "or "Paid: ")..m.id,w),T.text)end,function(m)local ok,why=A.selectModel(m.id);if ok then self.tab=3 else self.error=why end end)
  elseif self.tab==2 then
    local lines={}
    for _,e in ipairs(A.activity)do
      lines[#lines+1]=(e.ok and "OK "or "ERROR ")..e.name
      for _,line in ipairs(ui.wrap(A.display(e.text),g.w-5))do lines[#lines+1]="  "..line end
    end
    if #lines==0 then lines={"Actions will appear here as the agent uses tools."}end
    g:list(self.scroll,2,y,g.w-2,max(1,g.h-y),lines,function(line,_,x,yy,w)g:text(x,yy,ui.trunc(line,w),T.text)end)
  else
    local composerRows=touch and 0 or 3
    if touch and not A.busy and g.h>=12 then
      y=act(g,y,{{"Write task",function()local text=ccos.prompt("Message AI Agent","Type on the computer","");if text and text~=""then self:send(text)end end},{"Inspect system",function()self:send("Inspect ccOS, attached devices, screens and current settings. Summarize what is available. Do not change anything.")end},{"Find errors",function()self:send("Inspect the OS and agent logs for errors, then explain likely fixes. Do not change files yet.")end},{"Summarize files",function()self:send("List the root folders and notes. Summarize the files available without reading private credentials.")end}})
    end
    local lines={}
    for _,m in ipairs(A.messages)do
      lines[#lines+1]=(m.role=="user"and "You"or(m.role=="assistant"and "Agent"or "System"))..":"
      for _,line in ipairs(ui.wrap(A.display(m.text),g.w-5))do lines[#lines+1]=" "..line end
      lines[#lines+1]=""
    end
    if #lines==0 then lines={"ccOS Agent", "", "Read, edit and create files; run programs;", "inspect output; control settings, screens,", "audio, printers and attached peripherals.", "", A.configured()and(touch and "Type a message on the computer, or choose a task."or "Type a task below and press Enter.")or "Add your OpenRouter key in Settings."}end
    local available=max(1,g.h-y-composerRows)
    if self.seen~=#A.messages then self.scroll.scroll=max(0,#lines-available);self.seen=#A.messages end
    g:list(self.scroll,2,y,g.w-2,available,lines,function(line,_,x,yy,w)g:text(x,yy,ui.trunc(line,w),T.text)end)
    if not touch then
      local cy=g.h-1;g:fill(1,cy,g.w,2,T.surface)
      local prefix=A.busy and "Task running..."or(self.input==""and "Ask ccOS..."or self.input)
      g:text(2,cy,ui.trunc(prefix:sub(-max(1,g.w-12)),g.w-12),self.input==""and T.muted or T.text,T.surface)
      g:button(g.w-8,cy,"Send",function()self:send(self.input)end,{w=8,active=true,disabled=A.busy})
      if self.error then g:text(2,g.h,ui.trunc(A.display(self.error),g.w-2),T.warn,T.surface)end
      if not A.busy then term.setCursorPos(2+min(#self.input,max(1,g.w-12)),cy);term.setCursorBlink(true)end
    end
  end
end
function app:onChar(ch)if not ui.touch()and self.tab==1 and not A.busy and #self.input<12000 then self.input=self.input..ch;self.error=nil;return true end;return false end
function app:onPaste(text)return self:onChar(text)end
function app:onKey(k)
  if ui.touch()or self.tab~=1 then return false end
  if k==keys.enter and not A.busy then self:send(self.input)
  elseif k==keys.backspace and not A.busy then self.input=self.input:sub(1,-2)
  else return false end
end
function app:onEvent(ev)return ev[1]=="ccos_agent"end
ui.run(app)
