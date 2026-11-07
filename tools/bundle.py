#!/usr/bin/env python3
"""Build a self-contained setup.lua with every ccOS source and dependency."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
files=[(str(p.relative_to(ROOT/'src')),p.read_text()) for p in sorted((ROOT/'src'/'ccos').rglob('*.lua'))]
version=re.search(r'local VERSION = "([^"]+)"',dict(files)['ccos/kernel.lua']).group(1)
level=1
while any(']'+('='*level)+']' in body for _,body in files):level+=1
eq='='*level
parts=[f'''-- ccOS {version} setup. Drop onto an advanced CC: Tweaked computer, run setup.
-- Self-contained: installs all Lua modules and dependencies, then opens setup.
local VERSION = "{version}"
local FILES = {{
''']
for path,body in files:parts.append(f'  {{ "{path}", [{eq}[\n{body}]{eq}] }},\n')
parts.append('''}
local function writeFile(path, body)
  fs.makeDir(fs.getDir(path))
  local h=assert(fs.open(path,"w"),"Cannot write "..path);h.write(body);h.close()
  local r=assert(fs.open(path,"r"));local actual=r.readAll();r.close()
  assert(actual==body,"Verification failed: "..path)
end
term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear();term.setCursorPos(1,1)
print("ccOS "..VERSION.." installer")
if not term.isColor() then printError("ccOS needs an advanced computer.");return end
local needed,CHANGES=8192,{}
for _,f in ipairs(FILES)do
  local path="/"..f[1]
  if fs.exists(path)and fs.isDir(path)then printError("A directory conflicts with "..path);return end
  local h=fs.open(path,"r");local old=h and h.readAll()or nil;if h then h.close()end
  if old~=f[2]then CHANGES[#CHANGES+1]=f;needed=needed+#f[2]end
end
local free=fs.getFreeSpace("/")
if type(free)=="number"and free<needed then printError(("Need %d KB free; available %d KB."):format(math.ceil(needed/1024),math.floor(free/1024)));return end
local stage="/.ccos-stage-"..os.epoch("utc")
local previous=stage.."-previous"
assert(not fs.exists(stage)and not fs.exists(previous),"A setup is already in progress")
local installed,moved={},{}
local ok,err=pcall(function()
  for i,f in ipairs(CHANGES)do
    writeFile(stage.."/"..f[1],f[2])
    print(("Checking %d/%d: %s"):format(i,#CHANGES,f[1]))
  end
  -- Move only bundled code, leaving all existing data/configuration intact.
  for _,f in ipairs(CHANGES)do
    local dest="/"..f[1]
    if fs.exists(dest)then fs.makeDir(fs.getDir(previous.."/"..f[1]));fs.move(dest,previous.."/"..f[1]);moved[#moved+1]=f[1]end
    fs.makeDir(fs.getDir(dest));fs.move(stage.."/"..f[1],dest);installed[#installed+1]=f[1]
  end
end)
if not ok then
  for i=#installed,1,-1 do local p="/"..installed[i];if fs.exists(p)then fs.delete(p)end end
  for _,rel in ipairs(moved)do fs.move(previous.."/"..rel,"/"..rel)end
  if fs.exists(stage)then fs.delete(stage)end
  if fs.exists(previous)then fs.delete(previous)end
  printError("Installation rolled back: "..tostring(err));return
end
if fs.exists(stage)then fs.delete(stage)end
if fs.exists(previous)then fs.delete(previous)end
-- Import legacy preferences without deleting the old installation or user files.
if not fs.exists("/ccos/config.cfg")and fs.exists("/aurora/config.cfg")then fs.copy("/aurora/config.cfg","/ccos/config.cfg")end
if not fs.exists("/ccos/data")and fs.exists("/aurora/data")then fs.copy("/aurora/data","/ccos/data")end
print("All "..#FILES.." files verified. Opening setup...")
shell.run("/ccos/setup.lua")
''')
body=''.join(parts)
(ROOT/'dist').mkdir(exist_ok=True)
for p in [ROOT/'setup.lua',ROOT/'dist'/'setup.lua',ROOT/'dist'/'install.lua']:p.write_text(body)
print(f'Built ccOS {version}: {len(files)} bundled files, {len(body.encode())//1024} KB; root setup.lua + dist/setup.lua')
