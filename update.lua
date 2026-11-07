-- Standalone updater, including a bridge for ccOS 2.0 installations.
if ccos and ccos.updates then
  local ok,why=ccos.updates.install()
  if not ok then printError(why)else print("ccOS updater started. The computer will restart when installation finishes.")end
  return
end
if not fs.exists("/ccos/kernel.lua")or not fs.exists("/ccos/config.cfg")then printError("Install ccOS with setup.lua first.");return end
if not http then printError("Enable the HTTP API to update ccOS.");return end
local url="https://raw.githubusercontent.com/mzyhot/ccOS/main/setup.lua"
print("Downloading the ccOS updater...")
local h,why=http.get({url=url,timeout=45})
if not h then printError("Update download failed: "..tostring(why));return end
local source=h.read(1048577)or "";h.close()
if #source>1048576 then printError("Installer exceeds size limit");return end
local fn,err=load(source,"@ccOS-update","t",_ENV)
if not fn then printError("Invalid updater: "..tostring(err));return end
fn("--update")
