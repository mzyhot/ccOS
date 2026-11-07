-- Explicit boundary between UTF-8 network text and CC's one-byte terminal font.
-- Keep JSON/tool/file data in UTF-8; convert only text presented to the user.
local E={}
local floor=math.floor
local function utf8char(n)
  if n<128 then return string.char(n)
  elseif n<2048 then return string.char(192+floor(n/64),128+n%64)
  elseif n<65536 then return string.char(224+floor(n/4096),128+floor(n/64)%64,128+n%64)
  else return string.char(240+floor(n/262144),128+floor(n/4096)%64,128+floor(n/64)%64,128+n%64)end
end
local function nextCode(s,i)
  local b=s:byte(i)
  if b<128 then return b,i+1 end
  local count,minimum,n
  if b>=194 and b<=223 then count,minimum,n=2,128,b-192
  elseif b>=224 and b<=239 then count,minimum,n=3,2048,b-224
  elseif b>=240 and b<=244 then count,minimum,n=4,65536,b-240
  else return nil,i+1 end
  for j=i+1,i+count-1 do
    local c=s:byte(j);if not c or c<128 or c>191 then return nil,i+1 end
    n=n*64+c-128
  end
  if n<minimum or n>1114111 or(n>=55296 and n<=57343)then return nil,i+1 end
  return n,i+count
end
-- Readable replacements for punctuation and symbols outside CC's font.
local replacements={
  [0x2010]="-",[0x2011]="-",[0x2012]="-",[0x2013]="-",[0x2014]="--",[0x2212]="-",
  [0x2018]="'",[0x2019]="'",[0x201A]="'",[0x201B]="'",[0x2032]="'",
  [0x201C]='"',[0x201D]='"',[0x201E]='"',[0x201F]='"',[0x2033]='"',
  [0x2026]="...",[0x2022]="*",[0x25CF]="*",[0x25E6]="*",[0x00A0]=" ",
  [0x2028]="\n",[0x2029]="\n",[0x202F]=" ",[0x205F]=" ",[0x3000]=" ",
  [0x2190]="<-",[0x2192]="->",[0x2194]="<->",[0x21D2]="=>",
  [0x2260]="!=",[0x2264]="<=",[0x2265]=">=",[0x2248]="~",[0x221E]="infinity",
  [0x2713]="[OK]",[0x2714]="[OK]",[0x2705]="[OK]",[0x2717]="[X]",[0x274C]="[X]",[0x26A0]="[!]",
  [0x20AC]="EUR",[0x2122]="(TM)",[0x0152]="OE",[0x0153]="oe",[0x0160]="S",[0x0161]="s",[0x0178]="Y",[0x017D]="Z",[0x017E]="z",
  [0x200B]="",[0x200C]="",[0x200D]="",[0x2060]="",[0xFEFF]="",[0x00AD]="",
}
function E.toTerminal(value)
  local s=tostring(value or "");local out,i={},1
  while i<=#s do
    local n,j=nextCode(s,i)
    local v
    if not n then
      -- Collapse malformed sequences instead of printing their continuation bytes.
      while j<=#s and s:byte(j)>=128 and s:byte(j)<=191 do j=j+1 end
      v="?"
    elseif replacements[n]~=nil then v=replacements[n]
    elseif n==13 then v=s:byte(j)==10 and ""or "\n"
    elseif n==9 then v="    "
    elseif n==10 or(n>=32 and n<=126)or(n>=160 and n<=255)then v=string.char(n)
    elseif(n>=0x0300 and n<=0x036F)or(n>=0xFE00 and n<=0xFE0F)or(n>=0x202A and n<=0x202E)or(n>=0x2066 and n<=0x2069)then v=""
    elseif n>=0x2000 and n<=0x200A then v=" "
    elseif n<32 or(n>=127 and n<160)then v=""
    else v="?"end
    out[#out+1]=v;i=j
  end
  return table.concat(out)
end
-- CC's non-Latin1 input glyphs (from its Unicode-to-terminal character map).
local glyphs={
  [1]=0x263A,[2]=0x263B,[3]=0x2665,[4]=0x2666,[5]=0x2663,[6]=0x2660,[7]=0x2022,[8]=0x25D8,
  [11]=0x2642,[12]=0x2640,[14]=0x266A,[15]=0x266B,[16]=0x25BA,[17]=0x25C4,[18]=0x2195,[19]=0x203C,
  [22]=0x25AC,[23]=0x21A8,[24]=0x2191,[25]=0x2193,[26]=0x2192,[27]=0x2190,[28]=0x221F,[29]=0x2194,[30]=0x25B2,[31]=0x25BC,
  [127]=0x1FB99,[149]=0x258C,
}
local function terminalCode(b)
  if glyphs[b]then return glyphs[b]end
  if b>=129 and b<=148 then return b+(0x1FB00-129)end
  if b>=150 and b<=159 then return b+(0x1FB14-150)end
  return b
end
function E.fromTerminal(s)
  return(tostring(s):gsub("[\0-\255]",function(c)return utf8char(terminalCode(c:byte()))end))
end
-- Accept existing UTF-8 losslessly, and encode legacy single-byte file/output text.
function E.toUTF8(s)
  local out,i={},1
  while i<=#s do
    local n,j=nextCode(s,i)
    if n then out[#out+1]=s:sub(i,j-1)
    else out[#out+1]=utf8char(terminalCode(s:byte(i)))end
    i=j
  end
  return table.concat(out)
end
return E
