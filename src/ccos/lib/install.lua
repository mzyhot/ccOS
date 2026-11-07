-- Shared transactional installer, used by setup and the updater.
local M={}
function M.allowed(path)
  return type(path)=="string"and(path=="update.lua"or path=="ccos/kernel.lua"or path=="ccos/setup.lua"or path=="ccos/update.lua"or path:match("^ccos/apps/[%w_%-]+%.lua$")or path:match("^ccos/lib/[%w_%-]+%.lua$"))and fs.combine(path,"")==path
end
function M.apply(files,options)
  options=options or {};local changes,seen={},{}
  local needed=8192
  for _,file in ipairs(files)do
    local path,body=file[1],file[2]
    assert(M.allowed(path),"Update attempted an unowned path: "..tostring(path))
    assert(not seen[path],"Duplicate update path");seen[path]=true
    assert(type(body)=="string"and #body<=524288,"Invalid source file")
    assert(load(body,"@"..path,"t",{}),"Invalid Lua in "..path)
    local dest="/"..path
    assert(not fs.isDir(dest),"A directory conflicts with "..dest)
    local h=fs.open(dest,"r");local old=h and h.readAll()or nil;if h then h.close()end
    if old~=body then changes[#changes+1]=file;needed=needed+#body end
  end
  local free=fs.getFreeSpace("/")
  assert(type(free)~="number"or free>=needed,("Need %d KB free; available %d KB"):format(math.ceil(needed/1024),type(free)=="number"and math.floor(free/1024)or 0))
  local stage="/.ccos-stage-"..os.epoch("utc");local previous=stage.."-previous"
  assert(not fs.exists(stage)and not fs.exists(previous),"Another installation is in progress")
  local installed,moved={},{}
  local ok,err=pcall(function()
    for i,file in ipairs(changes)do
      local path=stage.."/"..file[1];fs.makeDir(fs.getDir(path))
      local h=assert(fs.open(path,"w"));h.write(file[2]);h.close()
      h=assert(fs.open(path,"r"));local actual=h.readAll();h.close();assert(actual==file[2],"Verification failed: "..file[1])
      if options.progress then options.progress(i,#changes,file[1])end
    end
    -- Commit without yielding. Runtime data, credentials and startup are untouched.
    for _,file in ipairs(changes)do
      local rel,dest=file[1],"/"..file[1]
      if fs.exists(dest)then fs.makeDir(fs.getDir(previous.."/"..rel));fs.move(dest,previous.."/"..rel);moved[#moved+1]=rel end
      fs.makeDir(fs.getDir(dest));fs.move(stage.."/"..rel,dest);installed[#installed+1]=rel
    end
  end)
  if not ok then
    for i=#installed,1,-1 do local p="/"..installed[i];if fs.exists(p)then fs.delete(p)end end
    for _,rel in ipairs(moved)do fs.move(previous.."/"..rel,"/"..rel)end
  end
  if fs.exists(stage)then fs.delete(stage)end;if fs.exists(previous)then fs.delete(previous)end
  if not ok then error("Installation rolled back: "..tostring(err),0)end
  return #changes
end
return M
