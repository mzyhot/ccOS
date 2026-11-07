-- Exercise real tool button handlers and persistence against the virtual CC APIs.
return function(ctx)
  local previous=term.current()
  local target=ctx.makeTerm(80,25)
  term.redirect(target)
  local count=0
  local function check(ok,label)count=count+1;assert(ok,label)end
  local app,g
  local function draw()g=ccos.ui.context();g:reset();term.setBackgroundColor(colors.black);term.clear();app:draw(g)end
  local function open(id)
    local p="/ccos/data/"..id..".cfg";if fs.exists(p)then fs.delete(p)end
    app=ccos.suite(id);app:init();draw();return app
  end
  local function clickAt(x,y)local hit=g:hitAt(x,y);assert(hit,"No control at "..x..","..y);hit.fn(x,y,1);draw()end
  local function click(label)
    for y,line in ipairs(target._t.text)do local start=1;while true do local x=line:find(label,start,true);if not x then break end;if g:hitAt(x,y)then clickAt(x,y);return end;start=x+1 end end
    error("No control: "..label)
  end
  local function screenContains(text)for _,line in ipairs(target._t.text)do if line:find(text,1,true)then return true end end;return false end
  open("textcase");app.text="Hello ccOS";draw();click("UPPER");check(app.result=="HELLO CCOS","uppercase");click("lower");check(app.result=="hello ccos","lowercase")
  open("lines");app.text="b\na\nb";draw();click("Sort");check(app.result=="a\nb\nb","line sorting");click("Unique");check(app.result=="b\na","deduplicate")
  open("replace");app.text="a+b a+b";app.find="a+b";app.replacement="c%";draw();click("Replace all");check(app.result=="c% c%","literal replacement")
  open("textstats");app.text="one two\nthree";draw();check(app.result:find("Words: 3",1,true)~=nil,"word count");check(app.result:find("Lines: 2",1,true)~=nil,"line count")
  open("urlencode");app.text="a b+&";draw();click("Encode");check(app.result=="a%20b%2B%26","URL encode");click("Decode");check(app.result=="a b+&","URL round trip")
  open("base64");app.text="hello";draw();click("Encode");check(app.result=="aGVsbG8=","Base64 encode");click("Decode");check(app.result=="hello","Base64 round trip")
  open("json");app.text='{"answer":42,"items":[]}';draw();click("Format");check(app.result:find('"answer": 42',1,true)~=nil,"JSON formatting");click("Compact");check(app.result=='{"answer":42,"items":[]}',"JSON compact")
  open("units");check(screenContains("10000 cm"),"unit conversion");click("+1");check(app.value==101,"touch number control")
  open("percentage");check(screenContains("15% of 100 = 15"),"percentage arithmetic");click("B +1");check(app.other==16,"percentage adjustment")
  open("base");app.value=255;draw();check(screenContains("11111111")and screenContains("FF"),"base conversion")
  open("tally");click("+1");check(app.data.count==1,"counter increment");local h=fs.open("/ccos/data/tally.cfg","r");local saved=textutils.unserialize(h.readAll());h.close();check(saved.count==1,"counter persistence");click("Reset");check(app.data.count==0,"counter reset")
  open("dice");app.rolls=3;draw();click("Roll");check(tonumber(app.result)>=3 and tonumber(app.result)<=18,"dice range")
  open("coin");click("Flip");check((app.data.heads or 0)+(app.data.tails or 0)==1,"coin statistics")
  open("random");click("Draw");check(tonumber(app.result)>=app.lo and tonumber(app.result)<=app.hi,"random bounds")
  open("timer");click("Start");check(app.ends~=nil,"timer start");click("Pause");check(app.ends==nil and app.remaining>0,"timer pause")
  open("focus");click("Start");app.ends=0;app:onTick();check(app.focusPhase=="Break"and app.remaining==300,"focus timer phase change")
  open("stopwatch");click("Start");app.started=os.epoch("utc")-1234;draw();click("Lap");check(#app.data.items==1,"stopwatch lap")
  open("metronome");click("Start");app:onTick();check(app.beats==1,"metronome tick");draw();click("Stop");check(app.beating==false,"metronome stop")
  redstone.setOutput("left",false);open("redstone");click("Turn on");check(redstone.getOutput("left"),"redstone toggle")
  redstone.setAnalogOutput("left",0);open("analog");click("+");check(redstone.getAnalogOutput("left")==1,"analog output")
  open("bundled");click("[ ] White");check(redstone.getBundledOutput("left")==1,"bundled output")
  open("lights");for i=1,16 do app.board[i]=false end;draw();clickAt(18,5);check(app.board[1]and app.board[2]and app.board[5]and not app.board[6],"Lights Out neighbors")
  open("memory");app.cards[1],app.cards[2]=1,1;draw();clickAt(18,5);clickAt(30,5);check(app.matched[1]and app.matched[2],"memory matching")
  open("tictactoe");clickAt(24,5);clickAt(24,9);clickAt(36,5);clickAt(36,9);clickAt(48,5);check(app.winner=="X","tic-tac-toe win")
  open("guess");app.hidden=app.guessValue;draw();click("Guess");check(app.message=="Correct!","guessing feedback")
  open("calendar");local month=app.month;click("Month >");check(app.month==month%12+1,"calendar navigation")
  open("backup");click("Back up data");check(app.message:find("Saved /ccos/backups/user/",1,true)~=nil,"data backup")
  local dest=app.message:match("Saved (.+)");check(fs.exists(dest.."/notes/todo.txt"),"backup contains real files")
  local state={scroll=0}
  local function singleRow()
    g=ccos.ui.context();g:reset()
    g:list(state,2,2,20,1,{"first","second","third"},function(item,_,x,y)g:text(x,y,item)end)
  end
  singleRow();g:hitAt(21,2).fn();singleRow();check(state.scroll==1,"one-row list scroll down")
  g:hitAt(20,2).fn();singleRow();check(state.scroll==0,"one-row list scroll up")
  term.redirect(previous)
  return count
end
