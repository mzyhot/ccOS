-- Hardware detection is based on the pocket API, never just screen size.
local D={}
function D.detect(pocketAPI,target)
  local w,h=target.getSize();local color=target.isColor()
  return {kind=pocketAPI and "pocket"or "desktop",pocket=pocketAPI~=nil and pocketAPI~=false,color=color,touch=color,w=w,h=h}
end
return D
