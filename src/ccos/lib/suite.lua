-- ccOS tool workbench. One responsive toolkit, independent working tools.
return function(id, initial)
  local ui,T,J=ccos.ui,ccos.ui.T,ccos.json
  local floor,min,max=math.floor,math.min,math.max
  local def;for _,a in ipairs(ccos.apps())do if a.id==id then def=a end end
  local app={title=def and def.name or id,tick=id=="metronome"and 0.05 or 0.5,page=1,scroll={scroll=0},data={},text="",result="",value=100,other=15,mode=1}
  local DATA="/ccos/data/"..id..".cfg"
  local sides={"left","right","top","bottom","front","back"}
  local textTools={textstats=true,textcase=true,lines=true,replace=true,urlencode=true,base64=true,json=true}
  local function now()return os.epoch("utc")end
  local function readFile(p,limit)
    local h=fs.open(p,"r");if not h then return nil,"Cannot open file"end
    local t=h.read(limit or 65536)or "";h.close();return t
  end
  local function writeFile(p,text)
    fs.makeDir(fs.getDir(p));local h=assert(fs.open(p,"w"),"Cannot save file");h.write(text);h.close()
  end
  local function status(msg)app.message=tostring(msg);app.messageAt=now()end
  local function save()fs.makeDir("/ccos/data");writeFile(DATA,textutils.serialize(app.data))end
  local function prompt(title,default)
    if ui.touch()then status("Enter text on the computer or ask the AI Agent");return nil end
    return ccos.prompt(title,"",default or "")
  end
  local function safe(fn)
    local ok,result=pcall(fn);status(ok and (result or "Done")or result)
  end
  local function label(g,y,s,color)g:text(2,y,ui.trunc(tostring(s),g.w-2),color or T.text)end
  local function actions(g,y,items)
    local bh=ui.touch()and g.h>=18 and 2 or 1
    local x=2
    for _,it in ipairs(items)do
      local bw=#it[1]+2
      if x+bw>g.w then y=y+bh+1;x=2 end
      x=g:button(x,y,it[1],it[2],{h=bh,active=it[3],disabled=it[4]})+1
    end
    return y+bh+1
  end
  local function paged(g,items,y,pick,row)
    local rh=ui.touch()and g.h>=18 and 2 or 1
    local count=max(1,floor((g.h-y-2)/rh))
    local pages=max(1,math.ceil(#items/count));app.page=ui.clamp(app.page,1,pages)
    local start=(app.page-1)*count
    for i=1,count do
      local item=items[start+i];if not item then break end
      local yy=y+(i-1)*rh
      g:fill(2,yy,g.w-2,rh,T.surface)
      if row then row(item,start+i,2,yy,g.w-2)
      else g:text(3,yy,ui.trunc(type(item)=="table"and(item.label or item.name)or tostring(item),g.w-4),T.text,T.surface)end
      if pick then g:hit(2,yy,g.w-1,yy+rh-1,function()pick(item,start+i)end)end
    end
    g:button(2,g.h-2,"< Prev",function()app.page=app.page-1 end,{disabled=app.page==1})
    g:center(g.h-2,app.page.." / "..pages,T.muted)
    g:button(g.w-8,g.h-2,"Next >",function()app.page=app.page+1 end,{disabled=app.page==pages})
    if #items==0 then g:center(y+1,"Nothing here yet",T.muted)end
  end
  local function output(g,y,text)
    local lines=ui.wrap(tostring(text or ""),g.w-4)
    g:list(app.scroll,2,y,g.w-2,max(1,g.h-y-1),lines,function(line,_,x,yy,w)g:text(x,yy,ui.trunc(line,w),T.text)end)
  end
  local function numeric(g,y)
    label(g,y,"Value: "..("%.8g"):format(app.value),T.accent)
    local items={{"-10",function()app.value=app.value-10 end},{"-1",function()app.value=app.value-1 end},{"+1",function()app.value=app.value+1 end},{"+10",function()app.value=app.value+10 end},{"/10",function()app.value=app.value/10 end},{"x10",function()app.value=app.value*10 end}}
    if not ui.touch()then items[#items+1]={"Set",function()local n=prompt("Value",tostring(app.value));if tonumber(n)then app.value=tonumber(n)end end}end
    return actions(g,y+1,items)
  end
  local function chooseFile()
    app.browser=true;app.browsePath="/";app.page=1
  end
  local function loadText(p)
    local raw,err=readFile(p);if raw then app.text,app.result,app.source=raw,raw,p;app.browser=false;app.page=1;app.scroll.scroll=0;status("Loaded "..p)else status(err)end
  end
  local function browser(g,y)
    label(g,y,app.browsePath,T.accent)
    y=actions(g,y+1,{{"< Up",function()app.browsePath="/"..fs.getDir(app.browsePath);app.page=1 end},{"Cancel",function()app.browser=false end}})
    local entries={};local ok,names=pcall(fs.list,app.browsePath)
    if ok then table.sort(names);for _,n in ipairs(names)do local p="/"..fs.combine(app.browsePath,n)
      if p~="/ccos/private"then entries[#entries+1]={label=(fs.isDir(p)and "+ "or "  ")..n,path=p}end
    end end
    paged(g,entries,y,function(e)if fs.isDir(e.path)then app.browsePath=e.path;app.page=1 else loadText(e.path)end end)
  end
  local function textActions(g,y)
    local buttons={{"Load file",chooseFile},{"Save result",function()
      local path=ui.touch()and("/notes/"..id.."-"..now()..".txt")or prompt("Save result","/notes/"..id..".txt")
      if path and path~=""then safe(function()writeFile(path,app.result~=""and app.result or app.text);return "Saved "..path end)end
    end}}
    if not ui.touch()then buttons[#buttons+1]={"Enter text",function()local text=prompt("Text",app.text);if text then app.text,app.result=text,text end end}end
    return actions(g,y,buttons)
  end
  local function b64encode(text)
    local chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";local out={}
    for i=1,#text,3 do local a,b,c=text:byte(i,i+2);local n=a*65536+(b or 0)*256+(c or 0)
      out[#out+1]=chars:sub(floor(n/262144)%64+1,floor(n/262144)%64+1)..chars:sub(floor(n/4096)%64+1,floor(n/4096)%64+1)..(b and chars:sub(floor(n/64)%64+1,floor(n/64)%64+1)or "=")..(c and chars:sub(n%64+1,n%64+1)or "=")
    end;return table.concat(out)
  end
  local function b64decode(text)
    text=text:gsub("%s","");assert(#text%4==0,"Invalid Base64 length")
    local chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";local out={}
    for i=1,#text,4 do local n=0;local padding=0
      for j=0,3 do local c=text:sub(i+j,i+j);local at=chars:find(c,1,true);if c=="="then padding=padding+1;assert(i+3==#text and j>=2,"Invalid Base64 padding")else assert(at and padding==0,"Invalid Base64 character")end;n=n*64+(at and at-1 or 0)end
      out[#out+1]=string.char(floor(n/65536)%256)..(padding<2 and string.char(floor(n/256)%256)or "")..(padding==0 and string.char(n%256)or "")
    end;return table.concat(out)
  end
  local function prettyJson(value)
    local raw=J.encode(value);local indent,quoted,escape=0,false,false;local out={}
    for i=1,#raw do local c=raw:sub(i,i)
      if quoted then out[#out+1]=c;if escape then escape=false elseif c=="\\"then escape=true elseif c=='"'then quoted=false end
      elseif c=='"'then quoted=true;out[#out+1]=c
      elseif c=='{'or c=='['then indent=indent+1;out[#out+1]=c.."\n"..("  "):rep(indent)
      elseif c=='}'or c==']'then indent=indent-1;out[#out+1]="\n"..("  "):rep(indent)..c
      elseif c==','then out[#out+1]=",\n"..("  "):rep(indent)
      elseif c==':'then out[#out+1]=": "else out[#out+1]=c end
    end;return table.concat(out)
  end
  local function fmtDuration(sec)local n=max(0,math.ceil(sec));return ("%d:%02d"):format(floor(n/60),n%60)end
  local function big(g,y,text,color)
    local cells
    for scale=5,1,-1 do cells=ccos.gfx.pixelText(tostring(text),scale,{ccos.gfx.HEX[color or T.accent]},"f");if ccos.gfx.cellsWidth(cells)<=g.w-4 and #cells<=max(2,g.h-y-5)then break end end
    ccos.gfx.drawCells(term,floor((g.w-ccos.gfx.cellsWidth(cells))/2)+1,y,cells)
    return y+#cells+1
  end
  local function noteList()
    local out={};if fs.exists("/notes")then for _,n in ipairs(fs.list("/notes"))do if not fs.isDir("/notes/"..n)then out[#out+1]={label=n,path="/notes/"..n}end end end;table.sort(out,function(a,b)return a.label<b.label end);return out
  end
  local function sideRead(method,side,default)
    if not redstone or not redstone[method]then return default end
    local ok,val=pcall(redstone[method],side);return ok and val or default
  end
  local function peripheralList(kind)
    local list={}
    for _,name in ipairs(peripheral.getNames())do
      local matches=not kind
      if kind then
        local ok,v=pcall(function()return peripheral.hasType and peripheral.hasType(name,kind)or peripheral.getType(name)==kind end);matches=ok and v
        if not matches and peripheral.getMethods then local method=({inventory="list",energy_storage="getEnergy",fluid_storage="tanks"})[kind];if method then for _,m in ipairs(peripheral.getMethods(name))do if m==method then matches=true end end end end
      end
      if matches then list[#list+1]={name=name,label=name.."  ["..tostring(peripheral.getType(name)).."]"}end
    end
    return list
  end
  function app:init()
    if fs.exists(DATA)then local h=fs.open(DATA,"r");local saved=h and textutils.unserialize(h.readAll());if h then h.close()end;if type(saved)=="table"then self.data=saved end end
    self.data.items=self.data.items or {};self.data.count=self.data.count or 0
    if id=="http"and initial and initial:match("^https://")then self.url=initial
    elseif initial and fs.exists(initial)and not fs.isDir(initial)then loadText(initial)end
    local d=ccos.date("*t");self.year,self.month=d.year,d.month
    self.lo,self.hi,self.rolls,self.bpm=1,100,1,100
    self.duration,self.remaining=300,300;self.acc=0;self.focusWork=25;self.focusBreak=5;self.focusPhase="Work"
    self.board={};self.turn="X";self.hidden=math.random(1,100);self.guessValue=50
    if id=="lights"then for i=1,16 do self.board[i]=math.random(0,1)==1 end
    elseif id=="memory"then self.cards={};for i=1,8 do self.cards[#self.cards+1]=i;self.cards[#self.cards+1]=i end;for i=16,2,-1 do local j=math.random(i);self.cards[i],self.cards[j]=self.cards[j],self.cards[i]end;self.matched={};self.revealed={}end
  end
  function app:draw(g)
    if not ui.touch()then label(g,1,self.title,T.accent)end
    local y=ui.touch()and 1 or 3
    if not ui.touch()and g.h<12 then y=2 end
    if self.browser then browser(g,y)
    elseif id=="notes"or id=="journal"then
      local buttons={{"Browse notes",function()self.source=nil;self.text=""end}}
      if not ui.touch()then
        buttons[#buttons+1]={"New",function()
          local name=id=="journal"and ccos.date("%Y-%m-%d")..".txt"or prompt("Note name","note.txt")
          if name and name~=""then local body=prompt("Note text","");if body then local p="/notes/"..fs.getName(name);writeFile(p,body);loadText(p)end end
        end}
        buttons[#buttons+1]={"Editor",function()if self.source then ccos.open("edit",self.source)end end}
        buttons[#buttons+1]={"Edit",function()if self.source then local body=prompt("Edit note",self.text);if body then writeFile(self.source,body);loadText(self.source)end end end}
      end
      y=actions(g,y,buttons)
      if self.source then label(g,y,self.source,T.muted);output(g,y+1,self.text)
      else paged(g,noteList(),y,function(e)loadText(e.path)end)end
    elseif id=="checklist"then
      local buttons={{"Clear done",function()local keep={};for _,it in ipairs(self.data.items)do if not it.done then keep[#keep+1]=it end end;self.data.items=keep;save()end}}
      if not ui.touch()then buttons[#buttons+1]={"Add task",function()local text=prompt("New task","");if text and text~=""then self.data.items[#self.data.items+1]={text=text,done=false};save()end end}end
      y=actions(g,y,buttons)
      local items={};for i,it in ipairs(self.data.items)do items[#items+1]={label=(it.done and "[x] "or "[ ] ")..it.text,index=i}end
      paged(g,items,y,function(e)local item=self.data.items[e.index];item.done=not item.done;save()end)
    elseif id=="bookmarks"then
      local buttons={};if not ui.touch()then buttons={{"Add",function()local name=prompt("Bookmark name","");if name then local p=prompt("Path or URL","");if p then self.data.items[#self.data.items+1]={label=name,path=p};save()end end end}}end
      y=actions(g,y,buttons);paged(g,self.data.items,y,function(e)
        if e.path:match("^https?://")then ccos.open("http",e.path)elseif fs.exists(e.path)then ccos.openFile(e.path)else status("Path is unavailable")end
      end)
    elseif id=="calendar"then
      y=actions(g,y,{{"< Month",function()self.month=self.month-1;if self.month==0 then self.month=12;self.year=self.year-1 end end},{"Today",function()local d=ccos.date("*t");self.year,self.month=d.year,d.month end},{"Month >",function()self.month=self.month+1;if self.month==13 then self.month=1;self.year=self.year+1 end end}})
      local names={"January","February","March","April","May","June","July","August","September","October","November","December"}
      g:center(y,names[self.month].." "..self.year,T.text);y=y+2
      local cw=floor((g.w-2)/7);local day0=(ccos.time.days(self.year,self.month,1)+4)%7
      local ny,nm=self.year,self.month+1;if nm==13 then ny,nm=ny+1,1 end
      local days=ccos.time.days(ny,nm,1)-ccos.time.days(self.year,self.month,1)
      for i,n in ipairs({"Su","Mo","Tu","We","Th","Fr","Sa"})do g:center(y,n,T.muted,T.bg,2+(i-1)*cw,cw)end
      local rh=g.h-y>=12 and 2 or 1
      for d=1,days do local pos=day0+d-1;local xx,yy=2+(pos%7)*cw,y+1+floor(pos/7)*rh
        local today=ccos.date("*t");g:button(xx,yy,tostring(d),function()status(("%04d-%02d-%02d"):format(self.year,self.month,d))end,{w=cw-1,h=max(1,rh-1),active=today.year==self.year and today.month==self.month and today.day==d})
      end
    elseif id=="worldclock"then
      local items={};for _,zone in ipairs(ccos.time.zones)do if zone~="fixed"then items[#items+1]={label=zone.."  "..ccos.time.format({timezone=zone,clock24=ccos.config("clock24"),leadingZero=ccos.config("leadingZero")},true)}end end;paged(g,items,y)
    elseif id=="timer"or id=="focus"or id=="stopwatch"then
      local running=self.ends~=nil
      local sec=id=="stopwatch"and(self.acc+(self.started and(now()-self.started)/1000 or 0))or(running and max(0,(self.ends-now())/1000)or self.remaining)
      if id=="focus"then label(g,y,self.focusPhase.."  "..self.focusWork.."m / "..self.focusBreak.."m",T.muted);y=y+1 end
      y=big(g,y,fmtDuration(sec))
      local buttons={}
      if id=="stopwatch"then
        buttons={{self.started and "Stop"or "Start",function()if self.started then self.acc=self.acc+(now()-self.started)/1000;self.started=nil else self.started=now()end end,true},{"Lap",function()table.insert(self.data.items,1,fmtDuration(sec));save()end},{"Reset",function()self.acc,self.started,self.data.items=0,nil,{};save()end}}
      else
        buttons={{running and "Pause"or "Start",function()if self.ends then self.remaining=max(0,(self.ends-now())/1000);self.ends=nil else if id=="focus"and self.remaining==300 then self.remaining=self.focusWork*60 end;self.ends=now()+self.remaining*1000 end end,true},{"-1m",function()if not self.ends then self.remaining=max(1,self.remaining-60)end end},{"+1m",function()if not self.ends then self.remaining=self.remaining+60 end end},{"Reset",function()self.ends=nil;self.remaining=id=="focus"and self.focusWork*60 or 300 end}}
      end
      y=actions(g,y,buttons)
      if id=="stopwatch"and g.h-y>3 then for i=1,min(#self.data.items,g.h-y-1)do label(g,y+i-1,"Lap "..(#self.data.items-i+1)..": "..self.data.items[i],T.muted)end end
    elseif id=="units"then
      y=numeric(g,y)
      local groups={ {name="Length",units={{"m",1},{"cm",0.01},{"km",1000},{"in",0.0254},{"ft",0.3048},{"mi",1609.344}}},
        {name="Mass",units={{"kg",1},{"g",0.001},{"lb",0.45359237},{"oz",0.028349523125}}},
        {name="Temperature",units={{"C",1},{"F",1},{"K",1}}}, {name="Data",units={{"B",1},{"KiB",1024},{"MiB",1048576},{"GiB",1073741824}}} }
      self.group,self.from,self.to=self.group or 1,self.from or 1,self.to or 2
      local group=groups[self.group];local units=group.units
      y=actions(g,y,{{group.name,function()self.group=self.group%#groups+1;self.from,self.to=1,2 end},{"From "..units[self.from][1],function()self.from=self.from%#units+1 end},{"To "..units[self.to][1],function()self.to=self.to%#units+1 end}})
      local result=self.value*units[self.from][2]/units[self.to][2]
      if self.group==3 then local c=self.from==2 and(self.value-32)*5/9 or(self.from==3 and self.value-273.15 or self.value);result=self.to==2 and(c*9/5+32)or(self.to==3 and(c+273.15)or c)end
      output(g,y,("%.10g %s = %.10g %s"):format(self.value,units[self.from][1],result,units[self.to][1]))
    elseif id=="percentage"then
      y=numeric(g,y);label(g,y,"Percent / comparison: "..self.other,T.muted)
      y=actions(g,y+1,{{"B -1",function()self.other=self.other-1 end},{"B +1",function()self.other=self.other+1 end},{"B +10",function()self.other=self.other+10 end}})
      output(g,y,("%g%% of %g = %g\n%g is %s%% of %g\nChange from %g to %g: %s%%"):format(self.other,self.value,self.value*self.other/100,self.other,self.value~=0 and("%.5g"):format(self.other/self.value*100)or "undefined",self.value,self.value,self.other,self.value~=0 and("%.5g"):format((self.other-self.value)/math.abs(self.value)*100)or "undefined"))
    elseif id=="base"then
      y=numeric(g,y);local n=floor(math.abs(self.value));n=min(n,2147483647);local bits={};repeat table.insert(bits,1,tostring(n%2));n=floor(n/2)until n==0
      output(g,y,"Decimal: "..floor(self.value).."\nBinary: "..(self.value<0 and "-"or "")..table.concat(bits).."\nHex: "..(self.value<0 and "-"or "")..("%X"):format(min(2147483647,floor(math.abs(self.value)))))
    elseif id=="random"or id=="dice"or id=="coin"or id=="tally"then
      local display=self.result~=""and self.result or(id=="tally"and tostring(self.data.count)or "Ready")
      y=big(g,y,display)
      local buttons
      if id=="tally"then buttons={{"-10",function()self.data.count=self.data.count-10;save()end},{"-1",function()self.data.count=self.data.count-1;save()end},{"+1",function()self.data.count=self.data.count+1;save()end,true},{"+10",function()self.data.count=self.data.count+10;save()end},{"Reset",function()self.data.count=0;save()end}}
      elseif id=="coin"then buttons={{"Flip",function()local heads=math.random(2)==1;self.result=heads and "Heads"or "Tails";self.data.heads=(self.data.heads or 0)+(heads and 1 or 0);self.data.tails=(self.data.tails or 0)+(heads and 0 or 1);save()end,true},{"Reset",function()self.result="";self.data.heads,self.data.tails=0,0;save()end}}
      elseif id=="dice"then buttons={{"Dice "..self.rolls,function()self.rolls=self.rolls%6+1 end},{"Roll",function()local total,rolls=0,{};for _=1,self.rolls do local n=math.random(6);total=total+n;rolls[#rolls+1]=n end;self.result=tostring(total);status(table.concat(rolls," + "))end,true}}
      else buttons={{"Min "..self.lo,function()self.lo=self.lo>=self.hi and 0 or self.lo+1 end},{"Max "..self.hi,function()self.hi=self.hi>=1000 and max(self.lo,10)or self.hi+10 end},{"Draw",function()self.result=tostring(math.random(self.lo,self.hi))end,true}}end
      y=actions(g,y,buttons)
      if id=="coin"then label(g,y,"Heads "..(self.data.heads or 0).."  Tails "..(self.data.tails or 0),T.muted)end
    elseif textTools[id]then
      y=textActions(g,y)
      if id=="textstats"then
        local words=0;for _ in self.text:gmatch("%S+")do words=words+1 end
        local _,breaks=self.text:gsub("\n","");self.result=("Words: %d\nLines: %d\nBytes: %d\nCharacters (UTF-8): %d"):format(words,self.text==""and 0 or breaks+1,#self.text,select(2,self.text:gsub("[^\128-\191]","")))
      elseif id=="textcase"then y=actions(g,y,{{"UPPER",function()self.result=self.text:upper()end},{"lower",function()self.result=self.text:lower()end},{"Title Case",function()self.result=self.text:lower():gsub("(%a)([%w']*)",function(a,b)return a:upper()..b end)end}})
      elseif id=="lines"then y=actions(g,y,{{"Sort",function()local t={};for line in(self.text.."\n"):gmatch("([^\n]*)\n")do t[#t+1]=line end;table.sort(t);self.result=table.concat(t,"\n")end},{"Unique",function()local t,seen={},{};for line in(self.text.."\n"):gmatch("([^\n]*)\n")do if not seen[line]then seen[line]=true;t[#t+1]=line end end;self.result=table.concat(t,"\n")end},{"Reverse",function()local t={};for line in(self.text.."\n"):gmatch("([^\n]*)\n")do table.insert(t,1,line)end;self.result=table.concat(t,"\n")end}})
      elseif id=="replace"then y=actions(g,y,{{"Find",function()self.find=prompt("Find literal text",self.find)end},{"Replacement",function()self.replacement=prompt("Replacement",self.replacement)end},{"Replace all",function()
        if not self.find or self.find==""then status("Set text to find first");return end
        local out,pos,count={},1,0;while true do local a,b=self.text:find(self.find,pos,true);if not a then out[#out+1]=self.text:sub(pos);break end;out[#out+1]=self.text:sub(pos,a-1)..(self.replacement or "");pos=b+1;count=count+1 end;self.result=table.concat(out);status(count.." replacements")end}})
      elseif id=="urlencode"then y=actions(g,y,{{"Encode",function()self.result=(self.result~=""and self.result or self.text):gsub("([^%w%-%._~])",function(c)return("%%%02X"):format(c:byte())end)end},{"Decode",function()self.result=(self.result~=""and self.result or self.text):gsub("%+"," "):gsub("%%(%x%x)",function(n)return string.char(tonumber(n,16))end)end}})
      elseif id=="base64"then y=actions(g,y,{{"Encode",function()self.result=b64encode(self.result~=""and self.result or self.text)end},{"Decode",function()safe(function()self.result=b64decode(self.result~=""and self.result or self.text);return "Decoded"end)end}})
      elseif id=="json"then y=actions(g,y,{{"Validate",function()safe(function()J.decode(self.text);return "Valid JSON"end)end},{"Format",function()safe(function()self.result=prettyJson(J.decode(self.text));return "Formatted JSON"end)end},{"Compact",function()safe(function()self.result=J.encode(J.decode(self.text));return "Compacted JSON"end)end}})end
      output(g,y,self.result~=""and self.result or self.text)
    elseif id=="redstone"or id=="analog"or id=="bundled"then
      if not redstone then output(g,y,"Redstone API unavailable")else
        if id=="bundled"then
          self.side=self.side or 1;y=actions(g,y,{{"Side: "..sides[self.side],function()self.side=self.side%#sides+1 end}})
          local value=sideRead("getBundledOutput",sides[self.side],0)
          local names={"White","Orange","Magenta","Light blue","Yellow","Lime","Pink","Gray","Light gray","Cyan","Purple","Blue","Brown","Green","Red","Black"}
          local items={};for i=1,16 do local bit=2^(i-1);items[#items+1]={label=(floor(value/bit)%2==1 and "[x] "or "[ ] ")..names[i],bit=bit}end
          paged(g,items,y,function(e)local v=sideRead("getBundledOutput",sides[self.side],0);local on=floor(v/e.bit)%2==1;redstone.setBundledOutput(sides[self.side],v+(on and -e.bit or e.bit))end)
        else
          local rh=max(1,min(ui.touch()and 3 or 2,floor((g.h-y-1)/6)))
          for i,side in ipairs(sides)do local yy=y+(i-1)*rh;local input=sideRead("getAnalogInput",side,0);local out=sideRead("getAnalogOutput",side,0)
            g:text(2,yy,ui.pad(side,7).."in "..input.."  out "..out,T.text)
            if id=="redstone"then g:button(g.w-10,yy,out>0 and "Turn off"or "Turn on",function()redstone.setOutput(side,out==0)end,{w=10,h=rh,active=out>0})
            else g:button(g.w-8,yy,"-",function()redstone.setAnalogOutput(side,max(0,out-1))end,{h=rh});g:button(g.w-4,yy,"+",function()redstone.setAnalogOutput(side,min(15,out+1))end,{h=rh})end
          end
        end
      end
    elseif id=="peripherals"or id=="inventory"or id=="energy"or id=="fluids"or id=="network"then
      local kinds={inventory="inventory",energy="energy_storage",fluids="fluid_storage",network="modem"}
      if self.device then
        y=actions(g,y,{{"< Devices",function()self.device=nil end}})
        if id=="network"then
          self.channel=self.channel or 1
          y=actions(g,y,{{"Ch -",function()self.channel=max(0,self.channel-1)end},{"Ch +",function()self.channel=min(65535,self.channel+1)end},{"Open",function()peripheral.call(self.device,"open",self.channel)end},{"Close",function()peripheral.call(self.device,"close",self.channel)end}})
        end
        local lines={"Device: "..self.device}
        local ok,result=pcall(function()
          if id=="inventory"then return peripheral.call(self.device,"list")elseif id=="energy"then return {stored=peripheral.call(self.device,"getEnergy"),capacity=peripheral.call(self.device,"getEnergyCapacity")}
          elseif id=="fluids"then return peripheral.call(self.device,"tanks")elseif id=="network"then return {wireless=peripheral.call(self.device,"isWireless"),channel=self.channel or 1,open=peripheral.call(self.device,"isOpen",self.channel or 1),messages=self.data.items}else return peripheral.getMethods(self.device)end
        end)
        output(g,y,table.concat(lines,"\n").."\n"..(ok and textutils.serialize(result)or tostring(result)))
      else paged(g,peripheralList(kinds[id]),y,function(e)self.device=e.name end)end
    elseif id=="storage"then
      y=actions(g,y,{{"Scan root",function()
        local items,visited={},0
        local function size(p,depth)
          if visited>=2000 or depth>12 then return 0 end;visited=visited+1
          if not fs.isDir(p)then return fs.getSize(p)end
          local total=0;for _,n in ipairs(fs.list(p))do total=total+size(fs.combine(p,n),depth+1)end;return total
        end
        for _,n in ipairs(fs.list("/"))do items[#items+1]={label=ui.pad(n,20)..ui.bytes(size("/"..n,0))}end
        self.storageItems=items;status(visited>=2000 and "Scan limited to 2000 entries"or "Scan complete")
      end}})
      label(g,y,"Free: "..ui.bytes(fs.getFreeSpace("/")),T.accent);paged(g,self.storageItems or {},y+2)
    elseif id=="backup"then
      y=actions(g,y,{{"Back up data",function()safe(function()
        local dest="/ccos/backups/user/"..now();fs.makeDir(dest)
        for _,dir in ipairs({"/notes","/ccos/data"})do if fs.exists(dir)then fs.copy(dir,dest.."/"..fs.getName(dir))end end
        return "Saved "..dest
      end)end}})
      local items={};if fs.exists("/ccos/backups/user")then for _,n in ipairs(fs.list("/ccos/backups/user"))do items[#items+1]={label=n,path="/ccos/backups/user/"..n}end end
      paged(g,items,y,function(e)
        if ccos.confirm("Restore backup?","Current notes and tool data are saved before restoring.","Restore")then safe(function()
          local saved="/ccos/backups/before-restore/"..now();fs.makeDir(saved)
          for _,pair in ipairs({{"notes","/notes"},{"data","/ccos/data"}})do local source=e.path.."/"..pair[1];if fs.exists(source)then
            if fs.exists(pair[2])then fs.move(pair[2],saved.."/"..pair[1])end;fs.copy(source,pair[2])end end;return "Restored "..e.label.."; reopen tools to reload data"
        end)end
      end)
    elseif id=="logs"then
      local buttons={{"OS log",function()self.logPath="/ccos/crash.log"end},{"Agent log",function()self.logPath="/ccos/logs/agent.log"end}}
      y=actions(g,y,buttons);output(g,y,readFile(self.logPath or "/ccos/crash.log")or "No log entries")
    elseif id=="sysinfo"then
      local lines={};for _,r in ipairs(ccos.sysinfo())do lines[#lines+1]=r[1]..": "..tostring(r[2])end;output(g,y,table.concat(lines,"\n"))
    elseif id=="display"then
      local items={};for _,s in ipairs(ccos.screens())do items[#items+1]={label=s.name.."  "..s.role.."  "..s.w.."x"..s.h,screen=s}end
      paged(g,items,y,function(e)
        if e.screen.kind=="term"then status("The computer remains a desktop")else
          local roles={picture="mirror",mirror="desktop",desktop="panel",panel="off",off="picture"};ccos.setScreen(e.screen.name,roles[e.screen.role]);status("Changed "..e.screen.name)
        end
      end)
    elseif id=="palette"then
      local order,themes=ccos.themes();local items={};for _,name in ipairs(order)do items[#items+1]={label=(ccos.config("theme")==name and "* "or "  ")..themes[name].name,name=name}end
      paged(g,items,y,function(e)ccos.config("theme",e.name)end)
    elseif id=="soundtest"then
      local instruments={"harp","bell","chime","flute","guitar","pling","bass","snare"};self.instrument=self.instrument or 1
      y=actions(g,y,{{instruments[self.instrument],function()self.instrument=self.instrument%#instruments+1 end},{"Left",function()ccos.audio.note(instruments[self.instrument],12,-1,1.5)end},{"Center",function()ccos.audio.note(instruments[self.instrument],12,0,1.5)end},{"Right",function()ccos.audio.note(instruments[self.instrument],12,1,1.5)end}})
      output(g,y,"Speakers: "..ccos.audio.info().speakers.."\nUse the channel buttons to check stereo placement.")
    elseif id=="metronome"then
      y=big(g,y,self.bpm.." BPM")
      y=actions(g,y,{{"-5",function()self.bpm=max(20,self.bpm-5)end},{self.beating and "Stop"or "Start",function()self.beating=not self.beating;self.nextBeat=now()end,true},{"+5",function()self.bpm=min(300,self.bpm+5)end}})
      label(g,y,"Beat "..(self.beats or 0),T.muted)
    elseif id=="disks"then
      local items={};for _,d in ipairs(ccos.hw().drives or {})do items[#items+1]={label=d.name..": "..(d.label or d.audio or(d.present and "Disk"or "Empty")),drive=d}end
      if self.drive then
        local d=self.drive;y=actions(g,y,{{"< Drives",function()self.drive=nil end},{"Browse",function()if d.mount then ccos.open("files","/"..d.mount)end end},{"Eject",function()peripheral.call(d.name,"ejectDisk");self.drive=nil end}})
        if not ui.touch()then y=actions(g,y,{{"Label",function()local name=prompt("Disk label",d.label or "");if name then peripheral.call(d.name,"setDiskLabel",name);os.queueEvent("ccos_hw")end end}})end
        output(g,y,textutils.serialize(d))
      else paged(g,items,y,function(e)self.drive=e.drive end)end
    elseif id=="http"then
      y=actions(g,y,{{"URL",function()self.url=prompt("HTTPS URL",self.url or "https://example.com")end},{"GET",function()
        if not self.url or not self.url:match("^https://")then status("Enter an HTTPS URL first");return end
        if not http then status("HTTP is disabled");return end
        local handle,err=http.get({url=self.url,timeout=20});if not handle then status(err);return end
        self.result="HTTP "..tostring(handle.getResponseCode()).."\n"..textutils.serialize(handle.getResponseHeaders()).."\n\n"..(handle.read(32768)or "");handle.close()
      end}});output(g,y,self.result)
    elseif id=="lights"or id=="memory"or id=="tictactoe"then
      local n=id=="tictactoe"and 3 or 4
      y=actions(g,y,{{"New game",function()
        if id=="lights"then for i=1,16 do self.board[i]=math.random(0,1)==1 end
        elseif id=="memory"then self.matched,self.revealed={},{};self.hideAt=nil
        else self.board={};self.turn="X";self.winner=nil end
      end}})
      local rh=max(1,min(4,floor((g.h-y-2)/n)));local cw=min(12,floor((g.w-4)/n));local x0=floor((g.w-cw*n)/2)+1
      for r=1,n do for c=1,n do local index=(r-1)*n+c;local shown=""
        if id=="lights"then shown=self.board[index]and "ON"or "."
        elseif id=="memory"then shown=(self.matched[index]or self.revealed[index])and tostring(self.cards[index])or "?"
        else shown=self.board[index]or " "end
        g:button(x0+(c-1)*cw,y+(r-1)*rh,shown,function()
          if id=="lights"then
            for _,delta in ipairs({{0,0},{-1,0},{1,0},{0,-1},{0,1}})do local rr,cc=r+delta[1],c+delta[2];if rr>=1 and rr<=n and cc>=1 and cc<=n then local k=(rr-1)*n+cc;self.board[k]=not self.board[k]end end
            local won=true;for i=1,16 do if self.board[i]then won=false end end;if won then status("All lights cleared!")end
          elseif id=="memory"then
            if self.hideAt or self.matched[index]or self.revealed[index]then return end
            self.revealed[index]=true;local first
            for k in pairs(self.revealed)do if k~=index then first=k end end
            if first then if self.cards[first]==self.cards[index]then self.matched[first],self.matched[index]=true,true;self.revealed={}else self.hideAt=now()+900 end end
          elseif not self.board[index]and not self.winner then
            self.board[index]=self.turn
            for _,line in ipairs({{1,2,3},{4,5,6},{7,8,9},{1,4,7},{2,5,8},{3,6,9},{1,5,9},{3,5,7}})do if self.board[line[1]]and self.board[line[1]]==self.board[line[2]]and self.board[line[2]]==self.board[line[3]]then self.winner=self.turn end end
            if self.winner then status(self.winner.." wins")else self.turn=self.turn=="X"and "O"or "X";status(self.turn.." to play")end
          end
        end,{w=cw-1,h=max(1,rh-1),active=id=="lights"and self.board[index]or id=="memory"and self.matched[index]})
      end end
    elseif id=="guess"then
      y=big(g,y,self.guessValue)
      y=actions(g,y,{{"-10",function()self.guessValue=max(1,self.guessValue-10)end},{"-1",function()self.guessValue=max(1,self.guessValue-1)end},{"Guess",function()status(self.guessValue==self.hidden and "Correct!"or(self.guessValue<self.hidden and "Try higher"or "Try lower"))end,true},{"+1",function()self.guessValue=min(100,self.guessValue+1)end},{"+10",function()self.guessValue=min(100,self.guessValue+10)end},{"New",function()self.hidden=math.random(1,100);status("New number between 1 and 100")end}})
    else output(g,y,"Tool unavailable: "..id)end
    if self.message then g:fill(1,g.h,g.w,1,T.surface);g:text(2,g.h,ui.trunc(self.message,g.w-2),T.muted,T.surface)end
  end
  function app:onTick()
    local t=now()
    if self.ends and t>=self.ends then
      self.ends=nil;self.remaining=0;ccos.sfx("alarm");ccos.notify(self.title,"Time is up",{quiet=true})
      if id=="focus"then self.focusPhase=self.focusPhase=="Work"and "Break"or "Work";self.remaining=(self.focusPhase=="Work"and self.focusWork or self.focusBreak)*60 end
    end
    if self.beating and t>=(self.nextBeat or 0)then self.beats=(self.beats or 0)+1;ccos.audio.note("hat",self.beats%4==1 and 12 or 8,0,0.7);self.nextBeat=t+60000/self.bpm end
    if self.hideAt and t>=self.hideAt then self.revealed={};self.hideAt=nil end
    return self.ends~=nil or self.started~=nil or self.beating or id=="worldclock"or id=="redstone"or id=="analog"or id=="energy"or id=="fluids"or id=="memory"
  end
  function app:onEvent(ev)
    if id=="network"and ev[1]=="modem_message"then table.insert(self.data.items,1,{side=ev[2],channel=ev[3],reply=ev[4],message=tostring(ev[5]):sub(1,512)});while #self.data.items>20 do table.remove(self.data.items)end;return true end
    return ev[1]=="peripheral"or ev[1]=="peripheral_detach"or ev[1]=="ccos_hw"or ev[1]=="disk"or ev[1]=="disk_eject"
  end
  return app
end
