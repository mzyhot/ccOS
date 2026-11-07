-- ccOS first-run setup. Runs after the self-contained root setup.lua installer.
local ROOT="/ccos"
local function loadModule(name)return assert(loadfile(ROOT.."/lib/"..name..".lua"))()end
local time=loadModule("time")
local cfg={}
if fs.exists(ROOT.."/config.cfg")then local h=fs.open(ROOT.."/config.cfg","r");local old=h and textutils.unserialize(h.readAll());if h then h.close()end;if type(old)=="table"then cfg=old end end
local function page(title,step)
  term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear();term.setCursorPos(1,1)
  term.setTextColor(colors.cyan);print("ccOS setup  "..step.." / 5");term.setTextColor(colors.white);print(title);print()
end
local function field(label,default,secret)
  term.setTextColor(colors.lightGray);print(label..(default and default~=""and(" ["..default.."]")or ""));term.setTextColor(colors.white);write("> ")
  local answer=read(secret and "*"or nil)or "";return answer==""and(default or "")or answer
end
local function yes(label,default)
  local a=field(label,default and "Y"or "N"):lower();return a:sub(1,1)=="y"
end
local function saveFile(path,text)
  fs.makeDir(fs.getDir(path));local h=assert(fs.open(path,"w"),"Cannot write "..path);h.write(text);h.close()
end
local function unused(path)
  local n=0;local dest=path;while fs.exists(dest)do n=n+1;dest=path.."."..n end;return dest
end
page("Welcome. Set up your computer and monitor tools.",1)
cfg.user=field("Your name",cfg.user or os.getComputerLabel()or "Home"):sub(1,40)
if cfg.user==""then cfg.user="Home"end
page("Time zone",2)
local default=1
for i,zone in ipairs(time.zones)do print(i..". "..zone);if zone==cfg.timezone then default=i end end
local selected=tonumber(field("Choose a number",tostring(default)))or default
cfg.timezone=time.zones[selected]or time.zones[default]
if cfg.timezone=="fixed"then
  local offset=tonumber(field("UTC offset in minutes (-720 to 840)",tostring(cfg.utcOffset or 0)))or 0
  cfg.utcOffset=math.max(-720,math.min(840,math.floor(offset)))
end
page("Clock and appearance",3)
cfg.clock24=field("Hour format: 12 or 24",cfg.clock24==true and "24"or "12")=="24"
cfg.leadingZero=yes("Pad hours with a zero? (01:00 instead of 1:00)",cfg.leadingZero==true)
local theme=field("Theme: ccos, midnight, sunset, forest, ocean, classic",cfg.theme=="aurora"and "ccos"or(cfg.theme or "ccos"))
if not({ccos=true,midnight=true,sunset=true,forest=true,ocean=true,classic=true})[theme]then theme="ccos"end
cfg.theme=theme
if cfg.wallpaper=="aurora"then cfg.wallpaper="ccos"end
cfg.wallpaper=cfg.wallpaper or "ccos"
page("AI Agent (optional)",4)
print("The agent uses OpenRouter with your own API key.")
print("You can add or change it later in AI Agent > Settings.")
local newKey
local existing=fs.exists(ROOT.."/private/openrouter.cfg")
if yes(existing and "Replace your saved API key?"or "Connect OpenRouter now?",false)then
  newKey=field("Paste OpenRouter API key (hidden)",nil,true):gsub("%s+","")
  if #newKey>1024 then error("API key is too long")end
end
cfg.agentModel=field("OpenRouter model id (must support tools)",cfg.agentModel or "openrouter/auto")
if not cfg.agentModel:match("^[%w%._:/%-]+$")then cfg.agentModel="openrouter/auto"end
cfg.agentConfirm=yes("Review agent changes before they run?",cfg.agentConfirm~=false)
page("Ready to finish",5)
print("User: "..cfg.user)
print("Time zone: "..time.label(cfg))
print("Clock: "..time.format(cfg,false))
print("Monitor: compact categorized tools")
local connected=(newKey and newKey~="")or existing
print("AI: "..(connected and "connected"or "configure later"))
print()
if not yes("Finish setup and restart into ccOS?",true)then
  print("Setup saved no changes. Run /ccos/setup.lua to finish.");return
end
cfg.setupComplete=true
cfg.screenLayout=cfg.screenLayout or 0
fs.makeDir(ROOT.."/private");fs.makeDir(ROOT.."/data");fs.makeDir(ROOT.."/logs");fs.makeDir("/notes");fs.makeDir("/music")
local encoded=textutils.serialize(cfg)
assert(type(textutils.unserialize(encoded))=="table","Configuration serialization failed")
saveFile(ROOT.."/config.new.cfg",encoded)
if fs.exists(ROOT.."/config.cfg")then fs.move(ROOT.."/config.cfg",unused(ROOT.."/config.previous.cfg"))end
fs.move(ROOT.."/config.new.cfg",ROOT.."/config.cfg")
if newKey and newKey~=""then saveFile(ROOT.."/private/openrouter.cfg",newKey)end
local startup='shell.run("/ccos/kernel.lua")\n'
if fs.exists("/startup.lua")then
  local h=fs.open("/startup.lua","r");local body=h and h.readAll()or "";if h then h.close()end
  if body~=startup then fs.move("/startup.lua",unused("/startup.before-ccos.lua"))else fs.delete("/startup.lua")end
end
saveFile("/startup.lua",startup)
print("Setup complete. Restarting into ccOS...")
sleep(0.5)
os.reboot()
