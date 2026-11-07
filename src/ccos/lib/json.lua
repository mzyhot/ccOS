-- Small bundled JSON codec; no downloads or external Lua packages required.
local J = { null = {} }
local arrayMT = { __json_array = true }
function J.array(t) return setmetatable(t or {}, arrayMT) end
local function quote(s)
  return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
    return ({ ['"']='\\"', ['\\']='\\\\', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t', ['\b']='\\b', ['\f']='\\f' })[c] or ('\\u%04x'):format(c:byte())
  end) .. '"'
end
function J.encode(value)
  local seen = {}
  local function enc(v)
    if v == J.null or v == nil then return "null" end
    local ty = type(v)
    if ty == "string" then return quote(v) end
    if ty == "boolean" then return tostring(v) end
    if ty == "number" then assert(v == v and math.abs(v) ~= math.huge, "Non-finite JSON number"); return tostring(v) end
    assert(ty == "table", "Unsupported JSON value")
    assert(not seen[v], "JSON cycle"); seen[v] = true
    local arr = getmetatable(v) == arrayMT or #v > 0
    local parts = {}
    if arr then for i=1,#v do parts[#parts+1]=enc(v[i]) end
    else
      local keys = {}; for k in pairs(v) do assert(type(k)=="string", "JSON object keys must be strings"); keys[#keys+1]=k end
      table.sort(keys); for _,k in ipairs(keys) do parts[#parts+1]=quote(k)..":"..enc(v[k]) end
    end
    seen[v]=nil
    return (arr and "[" or "{") .. table.concat(parts, ",") .. (arr and "]" or "}")
  end
  return enc(value)
end
local function utf8char(n)
  if n < 128 then return string.char(n)
  elseif n < 2048 then return string.char(192+math.floor(n/64),128+n%64)
  elseif n < 65536 then return string.char(224+math.floor(n/4096),128+math.floor(n/64)%64,128+n%64)
  else return string.char(240+math.floor(n/262144),128+math.floor(n/4096)%64,128+math.floor(n/64)%64,128+n%64) end
end
function J.decode(src)
  assert(type(src)=="string", "JSON text required")
  local i, depth = 1, 0
  local function ws() local _,e=src:find("^[ \t\r\n]*",i); i=(e or i-1)+1 end
  local parse
  local function str()
    assert(src:sub(i,i)=='"', "Expected JSON string"); i=i+1
    local out={}
    while i<=#src do
      local c=src:sub(i,i); i=i+1
      if c=='"' then return table.concat(out) end
      if c=='\\' then
        local e=src:sub(i,i); i=i+1
        local escapes={ ['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t' }
        if e=='u' then
          local hex=src:sub(i,i+3); assert(hex:match('^%x%x%x%x$'),"Bad Unicode escape"); i=i+4
          local n=tonumber(hex,16)
          if n>=0xD800 and n<=0xDBFF then
            assert(src:sub(i,i+1)=='\\u',"Missing Unicode surrogate"); i=i+2
            local lo=tonumber(src:sub(i,i+3),16); assert(lo and lo>=0xDC00 and lo<=0xDFFF,"Bad Unicode surrogate"); i=i+4
            n=65536+(n-0xD800)*1024+lo-0xDC00
          else assert(n<0xDC00 or n>0xDFFF,"Unexpected Unicode surrogate") end
          out[#out+1]=utf8char(n)
        else assert(escapes[e],"Bad JSON escape"); out[#out+1]=escapes[e] end
      else assert(c:byte()>=32,"Control in JSON string"); out[#out+1]=c end
    end
    error("Unterminated JSON string")
  end
  parse=function()
    ws(); depth=depth+1; assert(depth<=64,"JSON nesting too deep")
    local c=src:sub(i,i); local result
    if c=='"' then result=str()
    elseif c=='{' or c=='[' then
      local arr=c=='['; local close=arr and ']' or '}'
      result=arr and J.array() or {}; i=i+1; ws()
      if src:sub(i,i)~=close then
        while true do
          local key
          if not arr then ws(); key=str(); ws(); assert(src:sub(i,i)==':',"Expected colon"); i=i+1 end
          local v=parse(); if arr then result[#result+1]=v else result[key]=v end
          ws(); local ch=src:sub(i,i); if ch==close then break end
          assert(ch==',',"Expected comma"); i=i+1
        end
      end
      i=i+1
    elseif src:sub(i,i+3)=='true' then result=true; i=i+4
    elseif src:sub(i,i+4)=='false' then result=false; i=i+5
    elseif src:sub(i,i+3)=='null' then result=J.null; i=i+4
    else
      local token=src:match('^-?%d+%.?%d*[eE][+-]?%d+',i) or src:match('^-?%d+%.%d+',i) or src:match('^-?%d+',i)
      assert(token and not token:match('^-?0%d'),"Invalid JSON value at "..i)
      result=assert(tonumber(token));assert(result==result and math.abs(result)~=math.huge,"JSON number is out of range"); i=i+#token
    end
    depth=depth-1; return result
  end
  local v=parse(); ws(); assert(i>#src,"Trailing JSON data"); return v
end
return J
