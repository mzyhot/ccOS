-- Full Sync stretches terminal cells to the complete monitor area. Colours and
-- teletext artwork fill their scaled rectangles; text has one centred glyph.
local M={}
local floor,ceil=math.floor,math.ceil
function M.source(x,y,sw,sh,dw,dh)
  if x<1 or y<1 or x>dw or y>dh then return end
  return floor((x-1)*sw/dw)+1,floor((y-1)*sh/dh)+1
end
function M.target(x,y,sw,sh,dw,dh)
  local a,b=ceil((x-1)*dw/sw)+1,ceil(x*dw/sw)
  local c,d=ceil((y-1)*dh/sh)+1,ceil(y*dh/sh)
  return floor((a+b)/2),floor((c+d)/2)
end
function M.rows(buf,sw,sh,dw,dh)
  local rows,xmap,xcenter={}, {},{}
  for x=1,dw do
    local sx=floor((x-1)*sw/dw)+1
    xmap[x]=sx;xcenter[x]=M.target(sx,1,sw,sh,dw,dh)
  end
  local previous,st,sf,sb
  for y=1,dh do
    local sy=floor((y-1)*sh/dh)+1
    if sy~=previous then st,sf,sb=buf.getLine(sy);previous=sy end
    local _,cy=M.target(1,sy,sw,sh,dw,dh)
    local t,f,b={},{},{}
    for x=1,dw do
      local sx=xmap[x];local code=st:byte(sx)
      local art=code>=128 and code<=159
      t[x]=(art or(x==xcenter[x]and y==cy))and string.char(code)or " "
      f[x],b[x]=sf:sub(sx,sx),sb:sub(sx,sx)
    end
    rows[y]={table.concat(t),table.concat(f),table.concat(b)}
  end
  return rows
end
return M
