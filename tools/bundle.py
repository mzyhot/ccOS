#!/usr/bin/env python3
"""Build self-contained setup/update entry points and a checksummed release manifest."""
from pathlib import Path
import re,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
files=[(str(p.relative_to(ROOT/'src')),p.read_text())for p in sorted((ROOT/'src/ccos').rglob('*.lua'))]
frontend=(ROOT/'src/ccos/update.lua').read_text()
files.append(('update.lua',frontend));files.sort()
version=re.search(r'local VERSION = "([^"]+)"',dict(files)['ccos/kernel.lua']).group(1)
helper=(ROOT/'src/ccos/lib/install.lua').read_text()
level=1
while any(']'+('='*level)+']'in body for _,body in files):level+=1
eq='='*level
parts=[f'''-- ccOS {version} setup. Run setup, or use --update to preserve setup preferences.
local VERSION = "{version}"
local updateMode = ... == "--update"
local FILES = {{
''']
for path,body in files:parts.append(f'  {{"{path}",[{eq}[\n{body}]{eq}]}},\n')
parts.append('}\n')
parts.append(f'local installer=assert(load([{eq}[\n{helper}]{eq}],"@ccos-installer","t",_ENV))()\n')
parts.append('''term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear();term.setCursorPos(1,1)
print("ccOS "..VERSION..(updateMode and " updater"or " installer"))
local isPocket=pocket~=nil and pocket~=false
if isPocket then print("Pocket computer detected: portable layout")end
if not term.isColor()and not isPocket then printError("Use an advanced computer or a pocket computer.");return false end
if updateMode and not fs.exists("/ccos/config.cfg")then printError("Run setup first to configure ccOS.");return false end
local ok,why=pcall(installer.apply,FILES,{progress=function(i,n,path)print(("Checking %d/%d: %s"):format(i,n,path))end})
if not ok then printError(why);return false end
if updateMode then
  print("ccOS updated. Your settings and files were kept. Restarting...")
  if ccos and ccos.reboot then ccos.reboot()else os.reboot()end
  return true
end
if not fs.exists("/ccos/config.cfg")and fs.exists("/aurora/config.cfg")then fs.copy("/aurora/config.cfg","/ccos/config.cfg")end
if not fs.exists("/ccos/data")and fs.exists("/aurora/data")then fs.copy("/aurora/data","/ccos/data")end
print("All files verified. Opening setup...")
shell.run("/ccos/setup.lua")
''')
(ROOT/'dist').mkdir(exist_ok=True)
body=''.join(parts)
for path in [ROOT/'setup.lua',ROOT/'dist/setup.lua',ROOT/'dist/install.lua']:path.write_text(body)
for path in [ROOT/'update.lua',ROOT/'dist/update.lua']:path.write_text(frontend)
manifest={'version':version,'files':[{'path':path,'source':'update.lua'if path=='update.lua'else'src/'+path,'bytes':len(text.encode()),'sha256':hashlib.sha256(text.encode()).hexdigest()}for path,text in files]}
(ROOT/'version.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'Built ccOS {version}: {len(files)} runtime files, {len(body.encode())//1024} KB setup, update.lua and version.json')
