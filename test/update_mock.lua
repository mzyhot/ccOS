-- Release transport fixture: pinned commits, manifests, corruption and failures.
return function(ctx)
  local h={};local pinned=("a"):rep(40);local calls={}
  local function response(url,body)
    ctx.after(1,function()ctx.push("http_success",url,{read=function(n)return body:sub(1,n or #body)end,close=function()end,getResponseCode=function()return 200 end})end)
  end
  function h.request(opts)
    local url=opts.url;calls[#calls+1]=url
    if ctx.mode=="offline"then return false,"Network unavailable"end
    if url:find("api.github.com",1,true)then response(url,ccos.json.encode({object={sha=pinned}}));return true end
    local path=url:match("https://raw%.githubusercontent%.com/mzyhot/ccOS/[^/]+/(.+)$")
    assert(path,"Unexpected update URL")
    if path=="version.json"then
      local list={}
      for _,rel in ipairs(ctx.files)do
        local body=ctx.read(rel)
        if rel=="ccos/kernel.lua"then body=body:gsub('local VERSION = "3.0"','local VERSION = "3.1"')end
        list[#list+1]={path=rel,source=rel=="update.lua"and rel or("src/"..rel),bytes=#body,sha256=ctx.sha.digest(body)}
      end
      if ctx.mode=="corrupt"then list[1].sha256=("0"):rep(64)end
      response(url,ccos.json.encode({version=ctx.mode=="same"and "3.0"or "3.1",files=ccos.json.array(list)}));return true
    end
    assert(url:find(pinned,1,true),"Downloads were not pinned to checked commit")
    local rel=path=="update.lua"and path or path:gsub("^src/","")
    local body=ctx.read(rel)
    if rel=="ccos/kernel.lua"then body=body:gsub('local VERSION = "3.0"','local VERSION = "3.1"')end
    response(url,body);return true
  end
  function h.calls()return calls end
  return h
end
