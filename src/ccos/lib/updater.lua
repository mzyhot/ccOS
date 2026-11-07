-- Opt-in installation after a version prompt. Checks are quiet while unchanged.
return function(K,J,SHA,installer)
  local U={status="Not checked",busy=false,available=nil,latest=nil}
  local ROOT="https://raw.githubusercontent.com/mzyhot/ccOS/"
  local HEAD="https://api.github.com/repos/mzyhot/ccOS/git/ref/heads/main"
  local function changed()K.markAll();os.queueEvent("ccos_updates")end
  local function yieldFrame()
    local timer=os.startTimer(0)
    repeat local e,id=os.pullEvent("timer")until id==timer
  end
  function U.newer(a,b)
    local aa,bb={},{};for n in tostring(a):gmatch("%d+")do aa[#aa+1]=tonumber(n)end;for n in tostring(b):gmatch("%d+")do bb[#bb+1]=tonumber(n)end
    for i=1,math.max(#aa,#bb)do if(aa[i]or 0)~=(bb[i]or 0)then return(aa[i]or 0)>(bb[i]or 0)end end;return false
  end
  local function get(url,limit)
    assert(http and http.request,"HTTP is disabled")
    local ok,why=http.request({url=url,method="GET",headers={Accept="application/json",["User-Agent"]="ccOS-Updater"},redirect=true,timeout=25})
    assert(ok~=false,why or "Request rejected")
    local timer=os.startTimer(30)
    while true do
      local e,which,response,failed=os.pullEvent()
      if which==url and(e=="http_success"or e=="http_failure")then
        os.cancelTimer(timer);local h=e=="http_success"and response or failed
        local code=h and h.getResponseCode and h.getResponseCode()or(e=="http_success"and 200 or 0)
        local body=""
        if h then local yes,raw=pcall(h.read,limit+1);pcall(h.close);assert(yes,raw);body=raw or ""end
        assert(e=="http_success"and code>=200 and code<300,"Update HTTP "..code..": "..tostring(e=="http_failure"and response or "request failed"))
        assert(#body<=limit,"Update response exceeds size limit")
        return body
      elseif e=="timer"and which==timer then error("Update request timed out",0)end
    end
  end
  local function release()
    local ref="main"
    local ok,head=pcall(function()return J.decode(get(HEAD,16384))end)
    if ok and head.object and type(head.object.sha)=="string"and head.object.sha:match("^%x+$")and #head.object.sha==40 then ref=head.object.sha end
    local manifest=J.decode(get(ROOT..ref.."/version.json",131072))
    assert(type(manifest.version)=="string"and manifest.version:match("^%d+%.%d+%.?%d*$"),"Invalid release version")
    assert(type(manifest.files)=="table"and #manifest.files>0 and #manifest.files<=100,"Invalid release manifest")
    local seen,total={},0
    for _,f in ipairs(manifest.files)do
      assert(installer.allowed(f.path)and not seen[f.path],"Invalid release file path");seen[f.path]=true
      assert(type(f.source)=="string"and(f.source=="update.lua"or f.source=="src/"..f.path),"Invalid release source")
      assert(type(f.bytes)=="number"and f.bytes>=0 and f.bytes<=524288,"Invalid file size")
      assert(type(f.sha256)=="string"and #f.sha256==64 and f.sha256:match("^%x+$"),"Invalid file checksum")
      total=total+f.bytes
    end
    assert(total<=2097152 and seen["ccos/kernel.lua"]and seen["update.lua"],"Incomplete or oversized release")
    manifest.ref=ref;return manifest
  end
  function U.prompt()
    if not U.available or U.busy or U.promptOpen then return end
    for _,s in ipairs(K.screens)do if s.dialogs and #s.dialogs>0 then U.pendingPrompt=true;return end end
    U.pendingPrompt=false;U.promptOpen=true
    local version=U.available.version
    U.prompted=version
    K.dialog({detached=true,screen=K.pictureScreen and K.pictureScreen()or K.homeScreen(),title="ccOS "..version.." available",text="Install update and restart? Your settings, files and API key are kept. Open windows will close.",buttons={"Later","Update & restart"},enterChoice=1,cb=function(i)U.promptOpen=false;if i==2 then U.install()end end})
  end
  function U.maybePrompt()if U.pendingPrompt and U.available then U.prompt()end end
  function U.check(manual)
    if U.busy then return false,"An update operation is already running"end
    U.busy=true;U.status="Checking for updates";changed()
    K.spawn(function()
      local ok,result=pcall(release)
      U.busy=false
      if ok then
        U.latest=result.version
        U.available=U.newer(result.version,K.version)and result or nil
        U.status=U.available and("Update "..result.version.." available")or "Up to date"
        if U.available and(manual or(K.cfg.autoUpdates and U.prompted~=result.version))then U.prompt()
        elseif manual and not U.available then K.notify("ccOS updates","You are up to date",{quiet=true})end
      else U.status=tostring(result);if manual then K.notify("Update check failed",U.status,{quiet=true})end end
      changed()
    end,{title="Update check",service=true})
    return true
  end
  function U.install()
    if U.busy then return false,"An update operation is already running"end
    U.busy=true;U.status="Preparing update";changed()
    K.spawn(function()
      local ok,err=pcall(function()
        local m=U.available or release()
        if not U.newer(m.version,K.version)then U.status="Up to date";return end
        local files={}
        for i,f in ipairs(m.files)do
          U.status="Downloading "..i.."/"..#m.files..": "..f.path;changed()
          local body=get(ROOT..m.ref.."/"..f.source,524288)
          assert(#body==f.bytes and SHA.digest(body,yieldFrame)==f.sha256:lower(),"Checksum mismatch: "..f.path..". No code was changed.")
          files[#files+1]={f.path,body}
        end
        if K.agent and K.agent.busy then K.agent.cancel()end
        U.status="Installing verified update";changed()
        installer.apply(files,{progress=function(i,n,path)U.status="Staging "..i.."/"..n..": "..path;changed();yieldFrame()end})
        U.status="Restarting into ccOS "..m.version;changed();K.power="reboot";K.running=false
      end)
      U.busy=false
      if not ok then U.status=tostring(err);K.notify("Update failed",U.status,{quiet=true});K.dialog({detached=true,screen=K.pictureScreen and K.pictureScreen()or K.homeScreen(),title="Update failed",text=U.status,buttons={"OK"}})end
      changed()
    end,{title="ccOS updater",service=true})
    return true
  end
  function U.service()
    local first=true
    while true do
      local timer=os.startTimer(first and 8 or 21600);first=false
      repeat local e,id=os.pullEvent()until e=="timer"and id==timer
      if K.cfg.autoUpdates then U.check(false)end
    end
  end
  return U
end
