-- SHA-256 for release integrity. Uses CC's bit32 or native Lua bit operations.
local b=bit32
if not b then
  local native=load([[return {
    band=function(a,c)return(a&c)&0xffffffff end,
    bnot=function(a)return(~a)&0xffffffff end,
    bxor=function(a,c,d)local x=a~c;if d then x=x~d end;return x&0xffffffff end,
    rshift=function(a,n)return(a>>n)&0xffffffff end,
    rrotate=function(a,n)return((a>>n)|(a<<(32-n)))&0xffffffff end
  }]])
  assert(native,"SHA-256 needs bit32");b=native()
end
local band,bnot,bxor,shr,ror=b.band,b.bnot,b.bxor,b.rshift,b.rrotate
local floor=math.floor
local MOD=4294967296
local constants={
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
local function be(n)return string.char(floor(n/16777216)%256,floor(n/65536)%256,floor(n/256)%256,n%256)end
local M={}
function M.digest(text,yieldFn)
  local len=#text
  text=text.."\128"..("\0"):rep((55-len)%64)..be(floor(len/536870912))..be((len*8)%MOD)
  local h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  local w={}
  for start=1,#text,64 do
    for i=0,15 do local a,c,d,e=text:byte(start+i*4,start+i*4+3);w[i]=a*16777216+c*65536+d*256+e end
    for i=16,63 do
      local x,y=w[i-15],w[i-2]
      w[i]=(w[i-16]+bxor(ror(x,7),ror(x,18),shr(x,3))+w[i-7]+bxor(ror(y,17),ror(y,19),shr(y,10)))%MOD
    end
    local a,c,d,e,f,g,j,k=table.unpack(h)
    for i=0,63 do
      local t1=(k+bxor(ror(f,6),ror(f,11),ror(f,25))+bxor(band(f,g),band(bnot(f),j))+constants[i+1]+w[i])%MOD
      local t2=(bxor(ror(a,2),ror(a,13),ror(a,22))+bxor(band(a,c),band(a,d),band(c,d)))%MOD
      k,j,g,f,e,d,c,a=j,g,f,(e+t1)%MOD,d,c,a,(t1+t2)%MOD
    end
    local values={a,c,d,e,f,g,j,k};for i=1,8 do h[i]=(h[i]+values[i])%MOD end
    if yieldFn and floor((start-1)/64)%64==63 then yieldFn()end
  end
  local out={};for i=1,8 do out[i]=("%08x"):format(h[i])end;return table.concat(out)
end
return M
