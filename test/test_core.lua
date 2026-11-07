-- Pure module regressions: JSON, DST boundaries, clock policy and catalog.
local source=arg[1]or "../src"
local J=assert(loadfile(source.."/ccos/lib/json.lua"))()
local clock=assert(loadfile(source.."/ccos/lib/time.lua"))()
local catalog=assert(loadfile(source.."/ccos/lib/catalog.lua"))()
local checks=0
local function equal(actual,expected,label)checks=checks+1;assert(actual==expected,(label or "check")..": "..tostring(actual).." ~= "..tostring(expected))end
local function rejects(fn,label)checks=checks+1;local ok=pcall(fn);assert(not ok,label)end
local sample={a=J.array({1,true,false,J.null,"\n\t\\\""}),object={},empty=J.array(),value=-1.25e3}
local encoded=J.encode(sample);local decoded=J.decode(encoded)
equal(J.encode(decoded),encoded,"JSON round trip")
equal(J.encode(J.array()),"[]","empty array")
equal(J.encode({}),"{}","empty object")
equal(J.decode('"\\u0041\\u03A9\\uD83D\\uDE00"'),"A\206\169\240\159\152\128","Unicode")
for _,bad in ipairs({'{"x":}', '[1,]', '{"a":1}x', '01', '1e999', '"\\q"','"\\uDC00"','[true false]'})do rejects(function()J.decode(bad)end,"Malformed JSON accepted: "..bad)end
local function epoch(y,m,d,h,n)return clock.days(y,m,d)*86400+(h or 0)*3600+(n or 0)*60 end
local cfg={timezone="UTC",clock24=false,leadingZero=false}
equal(clock.format(cfg,false,epoch(2026,11,6,1)),"1:00 AM","12-hour no leading zero")
equal(clock.format(cfg,false,epoch(2026,11,6,13)),"1:00 PM","PM")
equal(clock.format(cfg,false,epoch(2026,11,6,0)),"12:00 AM","midnight")
cfg.clock24=true
equal(clock.format(cfg,false,epoch(2026,11,6,1)),"1:00","24-hour no leading zero")
cfg.leadingZero=true
equal(clock.format(cfg,false,epoch(2026,11,6,1)),"01:00","optional zero padding")
cfg.timezone="America/Chicago"
equal(clock.offset(cfg,epoch(2026,3,8,7,59)),-360,"Chicago pre-DST")
equal(clock.offset(cfg,epoch(2026,3,8,8)),-300,"Chicago DST starts")
equal(clock.offset(cfg,epoch(2026,11,1,6,59)),-300,"Chicago before DST ends")
equal(clock.offset(cfg,epoch(2026,11,1,7)),-360,"Chicago DST ends")
cfg.timezone="Europe/London"
equal(clock.offset(cfg,epoch(2026,3,29,0,59)),0,"London before summer time")
equal(clock.offset(cfg,epoch(2026,3,29,1)),60,"London summer time")
cfg.timezone="Australia/Sydney"
equal(clock.offset(cfg,epoch(2026,1,1)),660,"Sydney summer")
equal(clock.offset(cfg,epoch(2026,7,1)),600,"Sydney winter")
cfg.timezone="Australia/Sydney"
equal(clock.offset(cfg,epoch(2026,4,4,15,59)),660,"Sydney before DST ends")
equal(clock.offset(cfg,epoch(2026,4,4,16)),600,"Sydney DST ends")
equal(clock.offset(cfg,epoch(2026,10,3,16)),660,"Sydney DST begins")
cfg.timezone="Asia/Kolkata"
equal(clock.offset(cfg,epoch(2026,1,1)),330,"half-hour time zone")
cfg.timezone="fixed";cfg.utcOffset=345
equal(clock.date(cfg,"%Y-%m-%d %H:%M",epoch(2026,11,6,23)),"2026-11-07 04:45","offset/date rollover")
local seen={};for _,app in ipairs(catalog.apps())do assert(not seen[app.id],"Duplicate tool");seen[app.id]=true;assert(app.category and app.tool and app.path=="tools")end
assert(#catalog.apps()>=40,"Expected at least forty new tools")
local sha=assert(loadfile((arg[1]or "../src").."/ccos/lib/sha256.lua"))()
equal(sha.digest(""),"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","SHA256 empty")
equal(sha.digest("abc"),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","SHA256 abc")
local E=assert(loadfile(source.."/ccos/lib/encoding.lua"))()
equal(E.toTerminal("ASCII 1:00\nnext"),"ASCII 1:00\nnext","ASCII display unchanged")
equal(E.toTerminal("I’m ready — “café”… → ✅"),"I'm ready -- \"caf"..string.char(233).."\"... -> [OK]","UTF-8 punctuation and Latin1 display")
equal(E.toTerminal(J.decode('"\\u201cCaf\\u00e9\\u201d"')),E.toTerminal("“Café”"),"Escaped and literal Unicode render alike")
equal(E.toTerminal(J.decode('"\\ud83d\\ude80"')),"?","Unsupported emoji uses one placeholder")
equal(E.toTerminal("中文"),"??","Unsupported scripts do not leak UTF-8 bytes")
equal(E.toTerminal("a\r\nb\rc\td"),"a\nb\nc    d","Line breaks and tabs")
equal(E.toTerminal("é\239\184\143"),"e","Combining and variation marks do not become garbage")
equal(E.toTerminal("\240\159"),"?","Truncated UTF-8")
equal(E.toTerminal("\192\175"),"?","Overlong UTF-8")
equal(E.toTerminal("\237\160\128"),"?","Invalid UTF-8 surrogate")
equal(E.toTerminal("\244\144\128\128"),"?","Out-of-range UTF-8")
equal(E.fromTerminal("caf"..string.char(233)),"café","Terminal input encodes UTF-8")
equal(E.fromTerminal(string.char(7,26)),"•→","Native input symbols encode Unicode")
equal(E.toUTF8("café — 🚀"),"café — 🚀","Valid transport text stays byte-for-byte intact")
equal(E.toUTF8("caf"..string.char(233)),"café","Legacy byte text gets valid transport encoding")
equal(J.decode(E.toUTF8(J.encode({text="caf"..string.char(233)}))).text,"café","Legacy bytes produce valid JSON Unicode")
local updates=assert(loadfile(source.."/ccos/lib/updater.lua"))()({},J,sha,{})
equal(updates.newer("2.1.1","2.1"),true,"Patch release triggers update")
equal(updates.newer("2.1","2.1.1"),false,"Older release never replaces patch")
equal(updates.newer("2.1.1","2.1.1"),false,"Same patch does not prompt")
local mirror=assert(loadfile(source.."/ccos/lib/mirror.lua"))()
local buf={getLine=function(y)return y==1 and "AB"or "CD","01",y==1 and "ef"or "ab"end}
local rows=mirror.rows(buf,2,2,6,4)
equal(#rows,4,"Stretch fills monitor height")
equal(rows[1][3],"eeefff","Stretch fills left and right edges")
equal(rows[4][3],"aaabbb","Stretch fills bottom corners")
equal(rows[1][1]," A  B ","Text has one centred glyph per expanded cell")
equal(rows[2][1],"      ","Stretched rows preserve spacing")
equal(rows[3][1]," C  D ","Vertical glyph placement")
local x,y=mirror.source(6,4,2,2,6,4);equal(x,2,"Right edge maps to desktop right");equal(y,2,"Bottom edge maps to desktop bottom")
local xx,yy=mirror.target(2,2,2,2,6,4);equal(xx,5,"Cursor and touch share horizontal transform");equal(yy,3,"Cursor and touch share vertical transform")
equal(mirror.source(0,1,2,2,6,4),nil,"Out-of-bounds touch ignored")
local gfx=assert(loadfile(source.."/ccos/lib/gfx.lua","t",setmetatable({colors=setmetatable({},{__index=function()return 1 end})},{__index=_G})))()
equal(gfx.FONT.M[3],"10101","Clock M has a clear middle stem")
equal(#gfx.FONT.M[1],5,"Clock M uses enough columns for distinct shoulders")
print(checks.." core assertions passed; "..#catalog.apps().." implemented utilities in catalog")
