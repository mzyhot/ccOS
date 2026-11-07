-- ccOS graphics: pixel art drawn with teletext characters, big text,
-- app icons and the Metro face.
--
-- A teletext character (codes 128-159) is a 2x3 grid of pixels in two
-- colours, so pixel art here is a list of strings of blit colour digits
-- ("0"-"f", "." for transparent) that gfx.cells turns into text, foreground
-- and background strings ready for term.blit.

local gfx = {}
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local HEX, COLOR = {}, {}
for i = 0, 15 do
  local c, h = floor(2 ^ i), ("0123456789abcdef"):sub(i + 1, i + 1)
  HEX[c], COLOR[h] = h, c
end
gfx.HEX, gfx.COLOR = HEX, COLOR

------------------------------------------------------------------------
-- Pixels to cells
------------------------------------------------------------------------

-- rows: pixel rows; bg: blit digit shown through transparent pixels.
-- Returns {{text, fg, bg}, ...}, one entry per character row.
function gfx.cells(rows, bg)
  local out = {}
  local pw = 0
  for _, r in ipairs(rows) do if #r > pw then pw = #r end end
  local cw, ch = ceil(pw / 2), ceil(#rows / 3)
  local px, count, order = {}, {}, {}
  for cy = 0, ch - 1 do
    local T, F, B = {}, {}, {}
    local r1, r2, r3 = rows[cy * 3 + 1] or "", rows[cy * 3 + 2] or "", rows[cy * 3 + 3] or ""
    for cx = 0, cw - 1 do
      local a = cx * 2 + 1
      px[1], px[2] = r1:sub(a, a), r1:sub(a + 1, a + 1)
      px[3], px[4] = r2:sub(a, a), r2:sub(a + 1, a + 1)
      px[5], px[6] = r3:sub(a, a), r3:sub(a + 1, a + 1)
      for k in pairs(count) do count[k] = nil end
      local n = 0
      for i = 1, 6 do
        local c = px[i]
        if c == "" or c == "." or c == " " then c = bg; px[i] = c end
        if not count[c] then
          count[c] = 0
          n = n + 1
          order[n] = c
        end
        count[c] = count[c] + 1
      end
      -- The two commonest colours win; a third snaps to the background.
      local back, fore = order[1], nil
      for i = 2, n do
        local c = order[i]
        if count[c] > count[back] or (count[c] == count[back] and c == bg) then back = c end
      end
      for i = 1, n do
        local c = order[i]
        if c ~= back and (not fore or count[c] > count[fore]) then fore = c end
      end
      fore = fore or back
      local code = 0
      if fore ~= back then
        local bit = 1
        for i = 1, 5 do
          if px[i] == fore then code = code + bit end
          bit = bit * 2
        end
        -- The bottom-right pixel is always the background colour.
        if px[6] == fore then code, fore, back = 31 - code, back, fore end
      end
      T[cx + 1], F[cx + 1], B[cx + 1] = string.char(128 + code), fore, back
    end
    out[cy + 1] = { table.concat(T), table.concat(F), table.concat(B) }
  end
  return out
end

function gfx.drawCells(t, x, y, cells)
  for i, c in ipairs(cells) do
    t.setCursorPos(x, y + i - 1)
    t.blit(c[1], c[2], c[3])
  end
end

-- A pixel canvas: set(x, y, digit), then rows() for gfx.cells.
function gfx.canvas(w, h, fill)
  local cv = { w = w, h = h, px = {} }
  for i = 1, w * h do cv.px[i] = fill end
  function cv.set(x, y, c)
    if x >= 1 and y >= 1 and x <= w and y <= h then cv.px[(y - 1) * w + x] = c end
  end
  function cv.get(x, y) return cv.px[(y - 1) * w + x] end
  function cv.rows()
    local rows = {}
    for y = 1, h do rows[y] = table.concat(cv.px, "", (y - 1) * w + 1, y * w) end
    return rows
  end
  return cv
end

-- Park-Miller: exact in doubles, so CC and desktop Lua agree.
local function rng(seed)
  local s = seed % 2147483646 + 1
  return function(n)
    s = (s * 16807) % 2147483647
    return s % n
  end
end
gfx.rng = rng

------------------------------------------------------------------------
-- A 3x5 font, for clocks, banners and the logo
------------------------------------------------------------------------

local FONT = {
  A = { "010", "101", "111", "101", "101" }, B = { "110", "101", "110", "101", "110" },
  C = { "011", "100", "100", "100", "011" }, D = { "110", "101", "101", "101", "110" },
  E = { "111", "100", "110", "100", "111" }, F = { "111", "100", "110", "100", "100" },
  G = { "011", "100", "101", "101", "011" }, H = { "101", "101", "111", "101", "101" },
  I = { "111", "010", "010", "010", "111" }, J = { "001", "001", "001", "101", "010" },
  K = { "101", "101", "110", "101", "101" }, L = { "100", "100", "100", "100", "111" },
  M = { "10001", "11011", "10101", "10001", "10001" }, N = { "10001", "11001", "10101", "10011", "10001" },
  O = { "010", "101", "101", "101", "010" }, P = { "110", "101", "110", "100", "100" },
  Q = { "010", "101", "101", "110", "011" }, R = { "110", "101", "110", "101", "101" },
  S = { "011", "100", "010", "001", "110" }, T = { "111", "010", "010", "010", "010" },
  U = { "101", "101", "101", "101", "111" }, V = { "101", "101", "101", "101", "010" },
  W = { "10001", "10001", "10101", "11011", "10001" }, X = { "101", "101", "010", "101", "101" },
  Y = { "101", "101", "010", "010", "010" }, Z = { "111", "001", "010", "100", "111" },
  ["0"] = { "111", "101", "101", "101", "111" }, ["1"] = { "110", "010", "010", "010", "111" },
  ["2"] = { "111", "001", "111", "100", "111" }, ["3"] = { "111", "001", "011", "001", "111" },
  ["4"] = { "101", "101", "111", "001", "001" }, ["5"] = { "111", "100", "111", "001", "111" },
  ["6"] = { "111", "100", "111", "101", "111" }, ["7"] = { "111", "001", "001", "001", "001" },
  ["8"] = { "111", "101", "111", "101", "111" }, ["9"] = { "111", "101", "111", "001", "111" },
  [":"] = { "0", "1", "0", "1", "0" }, ["."] = { "0", "0", "0", "0", "1" },
  ["-"] = { "000", "000", "111", "000", "000" }, ["/"] = { "001", "001", "010", "100", "100" },
  ["!"] = { "1", "1", "1", "0", "1" }, ["?"] = { "111", "001", "010", "000", "010" },
  ["'"] = { "1", "1", "0", "0", "0" }, [" "] = { "00", "00", "00", "00", "00" },
  ["%"] = { "101", "001", "010", "100", "101" }, ["+"] = { "000", "010", "111", "010", "000" },
}
gfx.FONT = FONT

local function glyph(ch) return FONT[ch:upper()] or FONT["?"] end

-- Width in cells of text drawn by gfx.bigText.
function gfx.bigWidth(text, px)
  px = px or 1
  local w = 0
  for i = 1, #text do w = w + #glyph(text:sub(i, i))[1] * px + (i > 1 and 1 or 0) end
  return w
end

-- Text from filled cells, each font pixel px cells wide and py tall.
function gfx.bigText(t, x, y, text, color, px, py)
  px, py = px or 1, py or 1
  local fillRow = (" "):rep(px)
  t.setBackgroundColor(color)
  for i = 1, #text do
    local g = glyph(text:sub(i, i))
    for r = 1, 5 do
      for c = 1, #g[r] do
        if g[r]:sub(c, c) == "1" then
          for k = 0, py - 1 do
            t.setCursorPos(x + (c - 1) * px, y + (r - 1) * py + k)
            t.write(fillRow)
          end
        end
      end
    end
    x = x + #g[1] * px + 1
  end
end

-- Text as smooth teletext pixels: each font pixel becomes scale x scale
-- pixels. colors: one blit digit, or a list cycled per character.
function gfx.pixelText(text, scale, colors, bg)
  scale = scale or 2
  if type(colors) ~= "table" then colors = { colors or "0" } end
  local W = 0
  for i = 1, #text do W = W + #glyph(text:sub(i, i))[1] * scale + (i > 1 and scale or 0) end
  -- Keep each glyph on whole cells so colours never share a cell.
  local cv = gfx.canvas(W + 2, 5 * scale + (3 - (5 * scale) % 3) % 3, ".")
  local x = 1
  for i = 1, #text do
    local g = glyph(text:sub(i, i))
    local col = colors[(i - 1) % #colors + 1]
    for r = 1, 5 do
      for c = 1, #g[r] do
        if g[r]:sub(c, c) == "1" then
          for dy = 0, scale - 1 do
            for dx = 0, scale - 1 do cv.set(x + (c - 1) * scale + dx, (r - 1) * scale + dy + 1, col) end
          end
        end
      end
    end
    x = x + #g[1] * scale + scale
  end
  return gfx.cells(cv.rows(), bg or "f")
end

function gfx.cellsWidth(cells) return cells[1] and #cells[1][1] or 0 end

------------------------------------------------------------------------
-- App icons: 8x6 pixels, four cells by two
------------------------------------------------------------------------

gfx.ICONS = {
  agent={"c999999c","99099099","99099099","99cccc99","c900009c","cc9999cc"},
  files = { "cccccccc", "c44ccccc", "c444444c", "c444444c", "c444444c", "cccccccc" },
  terminal = { "bbbbbbbb", "ffffffff", "ffffffff", "f5ffffff", "ff5fffff", "f5ff555f" },
  music = { "aaaaaaaa", "aaaa000a", "aaaa0aaa", "aaaa0aaa", "aa000aaa", "aa00aaaa" },
  piano = { "0f0f00f0", "0f0f00f0", "0f0f00f0", "07070707", "07070707", "07070707" },
  settings = { "cc0cc0cc", "cc0000cc", "c00cc00c", "c00cc00c", "cc0000cc", "cc0cc0cc" },
  clock = { "c000000c", "0cc0ccc0", "0cc0ccc0", "0cc000c0", "0cccccc0", "c000000c" },
  calc = { "33333333", "33333333", "77777777", "07070707", "77777777", "07070707" },
  print = { "cc0000cc", "cc0000cc", "88888888", "88888888", "87777778", "88888888" },
  tasks = { "cccccccc", "cccccc5c", "cccc5c5c", "cc5c5c5c", "cc5c5c5c", "cccccccc" },
  about = { "bbb00bbb", "bbbbbbbb", "bbb00bbb", "bbb00bbb", "bbb00bbb", "bbbbbbbb" },
  viewer = { "c000000c", "c077770c", "c000000c", "c077770c", "c000000c", "c077700c" },
  worm = { "dddddddd", "d55555dd", "dddd5ddd", "dd5555dd", "dd5ddddd", "dd5555ed" },
  paint = { "eeaa55bb", "eeaa55bb", "eeaa55bb", "cccccccc", "c000000c", "cccccccc" },
  lua = { "bbbbbbbb", "bb0000bb", "b000bbbb", "b000bbbb", "bb0000bb", "bbbbbbbb" },
  disk = { "77888877", "77888877", "77777777", "70000007", "70000007", "77777777" },
  edit = { "c000000c", "c077770c", "c000000c", "c07770ec", "c0000e4c", "c00000cc" },
}

-- Short glyphs for title bars and the taskbar: {character, colour}.
gfx.GLYPHS = {
  agent={"*",colors.cyan},
  files = { "\4", colors.yellow }, terminal = { ">", colors.lime }, music = { "\14", colors.purple },
  piano = { "\14", colors.white }, settings = { "*", colors.lightGray }, clock = { "\7", colors.cyan },
  calc = { "=", colors.lightBlue }, print = { "\20", colors.white }, tasks = { "\18", colors.lime },
  about = { "i", colors.blue }, viewer = { "\21", colors.white }, worm = { "~", colors.lime },
  paint = { "\4", colors.pink }, lua = { "L", colors.blue }, disk = { "\8", colors.lightGray },
  edit = { "\21", colors.orange },
}

local iconCache = {}
-- scale 2 doubles every pixel: eight cells by four.
function gfx.icon(t, x, y, name, scale)
  scale = scale or 1
  local key = name .. "@" .. scale
  local cells = iconCache[key]
  if not cells then
    local art = gfx.ICONS[name] or gfx.ICONS.about
    if scale > 1 then
      local big = {}
      for _, row in ipairs(art) do
        local wide = row:gsub(".", function(c) return c:rep(scale) end)
        for _ = 1, scale do big[#big + 1] = wide end
      end
      art = big
    end
    cells = gfx.cells(art, "c")
    iconCache[key] = cells
  end
  gfx.drawCells(t, x, y, cells)
end

-- The splash logo: a small ccos over the word mark.
function gfx.logo(scale)
  return gfx.pixelText("CCOS", scale or 2, { "9", "5", "9", "a", "6", "a" }, "f")
end

------------------------------------------------------------------------
-- Metro: a thin proportional heading face, monochrome tile glyphs and
-- sub-cell geometry for the Big Picture Start screen. Everything here is
-- drawn in teletext pixels (2x3 per cell, each 3x3 screen pixels square),
-- so tile gaps, glyph centring and headings land on exact pixels.
------------------------------------------------------------------------

local metro = {}
gfx.metro = metro

local function unpackRows(spec, height)
  local rows = {}
  for row in spec:gmatch("%S+") do rows[#rows + 1] = row end
  local w = #(rows[1] or "")
  while #rows < (height or #rows) do rows[#rows + 1] = ("."):rep(w) end
  return rows
end

-- Rows 1-7: capitals and ascenders; 3-7: x-height; 8-9: descenders.
local FACE = {
  A = "..#.. .#.#. .#.#. #...# ##### #...# #...#", B = "###. #..# #..# ###. #..# #..# ###.",
  C = ".### #... #... #... #... #... .###", D = "###.. #..#. #...# #...# #...# #..#. ###..",
  E = "#### #... #... ###. #... #... ####", F = "#### #... #... ###. #... #... #...",
  G = ".#### #.... #.... #..## #...# #...# .####", H = "#...# #...# #...# ##### #...# #...# #...#",
  I = "# # # # # # #", J = "..# ..# ..# ..# ..# ..# ##.",
  K = "#...# #..#. #.#.. ##... #.#.. #..#. #...#", L = "#... #... #... #... #... #... ####",
  M = "#.....# ##...## #.#.#.# #..#..# #.....# #.....# #.....#", N = "#...# ##..# ##..# #.#.# #..## #..## #...#",
  O = ".####. #....# #....# #....# #....# #....# .####.", P = "###. #..# #..# ###. #... #... #...",
  Q = ".####. #....# #....# #....# #..#.# #...#. .###.#", R = "###. #..# #..# ###. #.#. #..# #..#",
  S = ".### #... #... .##. ...# ...# ###.", T = "##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
  U = "#...# #...# #...# #...# #...# #...# .###.", V = "#...# #...# #...# .#.#. .#.#. .#.#. ..#..",
  W = "#.....# #.....# #..#..# #..#..# #.#.#.# #.#.#.# .#...#.", X = "#...# .#.#. .#.#. ..#.. .#.#. .#.#. #...#",
  Y = "#...# .#.#. .#.#. ..#.. ..#.. ..#.. ..#..", Z = "##### ....# ...#. ..#.. .#... #.... #####",
  a = ".... .... .##. ...# .### #..# .###", b = "#... #... ###. #..# #..# #..# ###.",
  c = "... ... .## #.. #.. #.. .##", d = "...# ...# .### #..# #..# #..# .###",
  e = ".... .... .##. #..# #### #... .###", f = ".## #.. ### #.. #.. #.. #..",
  g = ".... .... .### #..# #..# #..# .### ...# ###.", h = "#... #... ###. #..# #..# #..# #..#",
  i = "# . # # # # #", j = ".# .. .# .# .# .# .# .# #.",
  k = "#... #... #..# #.#. ##.. #.#. #..#", l = "# # # # # # #",
  m = "....... ....... ###.##. #..#..# #..#..# #..#..# #..#..#", n = ".... .... ###. #..# #..# #..# #..#",
  o = ".... .... .##. #..# #..# #..# .##.", p = ".... .... ###. #..# #..# #..# ###. #... #...",
  q = ".... .... .### #..# #..# #..# .### ...# ...#", r = ".... .... #.## ##.. #... #... #...",
  s = "... ... .## #.. .#. ..# ##.", t = "... .#. ### .#. .#. .#. ..#",
  u = ".... .... #..# #..# #..# #..# .###", v = "..... ..... #...# #...# .#.#. .#.#. ..#..",
  w = "..... ..... #...# #...# #.#.# #.#.# .#.#.", x = "..... ..... #...# .#.#. ..#.. .#.#. #...#",
  y = ".... .... #..# #..# #..# #..# .### ...# ###.", z = ".... .... #### ..#. .#.. #... ####",
  ["0"] = ".##. #..# #..# #..# #..# #..# .##.", ["1"] = "..#. .##. ..#. ..#. ..#. ..#. ..#.",
  ["2"] = ".##. #..# ...# ..#. .#.. #... ####", ["3"] = "###. ...# ...# .##. ...# ...# ###.",
  ["4"] = "...# ..## .#.# #..# #### ...# ...#", ["5"] = "#### #... #... ###. ...# ...# ###.",
  ["6"] = ".##. #... #... ###. #..# #..# .##.", ["7"] = "#### ...# ..#. ..#. .#.. .#.. .#..",
  ["8"] = ".##. #..# #..# .##. #..# #..# .##.", ["9"] = ".##. #..# #..# .### ...# ...# .##.",
  [" "] = "... ... ... ... ... ... ...", [":"] = ". . # . . # .", ["."] = ". . . . . . #",
  [","] = ". . . . . . # #", ["-"] = "... ... ... ### ... ... ...", ["'"] = "# # . . . . .",
  ["!"] = "# # # # # . #", ["?"] = ".##. #..# ...# ..#. .#.. .... .#..",
  ["/"] = "...# ...# ..#. ..#. .#.. .#.. #...", ["("] = ".# #. #. #. #. #. .#", [")"] = "#. .# .# .# .# .# #.",
  ["&"] = ".##.. #..#. .##.. .#... #.#.# #..#. .##.#", ["+"] = "... ... .#. ### .#. ... ...",
  ["_"] = ".... .... .... .... .... .... .... ####",
}
for ch, spec in pairs(FACE) do FACE[ch] = unpackRows(spec, 9) end
metro.FACE = FACE

local function faceGlyph(ch) return FACE[ch] or FACE[ch:upper()] or FACE["?"] end

-- Width in teletext pixels of text in the heading face.
function metro.textWidth(text, scale)
  scale = scale or 1
  local w = 0
  for i = 1, #text do w = w + #faceGlyph(text:sub(i, i))[1] * scale + (i > 1 and scale or 0) end
  return w
end

-- Draw text into a canvas at pixel (x, y), top of capitals. Returns end x.
function metro.drawText(cv, x, y, text, color, scale)
  scale = scale or 1
  for i = 1, #text do
    local g = faceGlyph(text:sub(i, i))
    for r = 1, #g do
      local row = g[r]
      for c = 1, #row do
        if row:sub(c, c) == "#" then
          for dy = 0, scale - 1 do
            for dx = 0, scale - 1 do cv.set(x + (c - 1) * scale + dx, y + (r - 1) * scale + dy, color) end
          end
        end
      end
    end
    x = x + (#g[1] + 1) * scale
  end
  return x
end

-- Stamp a '#'/'.' bitmap into a canvas.
function metro.stamp(cv, x, y, rows, color)
  for r = 1, #rows do
    local row = rows[r]
    for c = 1, #row do
      if row:sub(c, c) == "#" then cv.set(x + c - 1, y + r - 1, color) end
    end
  end
end

function metro.rect(cv, x, y, w, h, color)
  for yy = y, y + h - 1 do for xx = x, x + w - 1 do cv.set(xx, yy, color) end end
end

-- Eight-by-eight white glyphs in the flat Metro idiom.
local GLYPH = {
  files = "###..... #..##### #......# #......# #......# #......# ########",
  viewer = "#####... #...##.. #....#.. #.###.#. #......# #.####.# #......# ########",
  notes = "######## #......# #.####.# #......# #.###..# #.....## #....##. ######..",
  journal = ".######. ##.....# ##.##..# ##.....# ##.###.# ##.....# ##.....# .#######",
  checklist = ".......# ......## .....##. #...##.. ##.##... .###.... ..#.....",
  bookmarks = ".######. .######. .######. .######. .######. .######. .##..##. .#....#.",
  music = "..###### ..###### ..#....# ..#....# ..#....# ###..### ###..### .#....#.",
  piano = "######## #.#.#..# #.#.#..# #.#.#..# #.#.#..# ########",
  clock = "..####.. .#....#. #..#...# #..#...# #..###.# #......# .#....#. ..####..",
  worldclock = "..####.. .#.##.#. #..##..# ######## ######## #..##..# .#.##.#. ..####..",
  calendar = ".#....#. ######## ######## #......# #.#.#.## #......# #.#.#..# ########",
  focus = "..####.. .#....#. #..##..# #.#..#.# #.#..#.# #..##..# .#....#. ..####..",
  stopwatch = "..###... ...#.... .#####.. #..#..#. #..#..#. #.....#. #.....#. .#####..",
  timer = "######## .#....#. ..#..#.. ...##... ..#..#.. .#.##.#. ########",
  calc = ".#...... ###.###. .#...... ........ #.#.###. .#...... #.#.###.",
  units = "######## #.#.#.## #.#.#..# #......# ########",
  percentage = "##....#. ##...#.. ....#... ...#.... ..#..... .#...##. #....##.",
  base = ".#..###. ##..#.#. .#..#.#. .#..#.#. ###.###.",
  random = "######## #......# #.#....# #..##..# #..##..# #....#.# #......# ########",
  dice = ".######. #.####.# ######## ###..### ###..### ######## #.####.# .######.",
  coin = "..####.. .######. ##....## ##.##.## ##.##.## ##....## .######. ..####..",
  tally = ".#...#.. ###.##.. .#...#.. .....#.. ....###.",
  textstats = "####### #...... .#..... ..#.... .#..... #...... #######",
  textcase = ".#...... #.#..... #.#..##. ###....# #.#..### #.#.#..# .....###",
  lines = "######## ........ ######.. ........ ####.... ........ ##......",
  replace = ".####... #....#.. #....#.. #....#.. #....#.. .####... .....##. ......##",
  urlencode = ".....##. ....#..# ....#..# ..##.##. .##.##.. #..#.... #..#.... .##.....",
  base64 = "###.#.#. #...#.#. ###.###. #.#...#. ###...#.",
  json = ".##..##. .#....#. .#....#. #......# .#....#. .#....#. .##..##.",
  http = "...###.. ..#...#. .##....# #......# #......# .######.",
  network = ".######. #......# ..####.. .#....#. ...##... ...##...",
  terminal = "######## ######## #......# #.#....# #..#...# #.#.##.# #......# ########",
  edit = "......## .....### ....###. ...###.. ..###... .###.... .##..... #.......",
  lua = "..####.. .##..#.. ##...... ##...... ##...... .##...#. ..####..",
  paint = "......## .....### ....###. ...###.. .##.#... ####.... ###..... .#......",
  redstone = "....##.. ...##... ..##.... .######. ....##.. ...##... ..##....",
  analog = ".##..... #..#.... #..#...# ....#..# .....##.",
  bundled = "##.##.## ##.##.## ........ ##.##.## ##.##.## ........ ##.##.## ##.##.##",
  peripherals = ".#..#... .#..#... ######.. ######.. .####... ..##.... ..##....",
  inventory = "######## #......# ######## #..##..# #......# #......# ########",
  energy = "#######. #.....#. #.###.## #.###.## #.....#. #######.",
  fluids = "...#.... ..###... ..###... .#####.. #######. #######. .#####.. ..###...",
  disks = "######## #.####.# #.####.# #......# #.####.# #.#..#.# #.####.# ########",
  disk = "######## #.####.# #.####.# #......# #.####.# #.#..#.# #.####.# ########",
  storage = "..####.. .###..#. ####...# ####...# ######## .######. ..####..",
  backup = "...##... ..####.. .######. ...##... ...##... #..##..# #......# ########",
  logs = "#.###### ........ #.###### ........ #.####.. ........ #.######",
  sysinfo = "..#..#.. .######. ##....## .#....#. ##....## .######. ..#..#..",
  display = "######## #......# #......# #......# ######## ...##... .######.",
  palette = "..####.. .#....#. #.#..#.# #......# #.#...#. .#...#.. ..###...",
  soundtest = "...#..#. ..##...# ####.#.# ####.#.# ..##...# ...#..#.",
  metronome = "...##... ...##... ..#..#.. ..#.##.. .#.#..#. .##....# .#.....# ########",
  lights = "..####.. .#....#. .#....#. .#....#. ..#..#.. ..####.. ..####..",
  memory = "####.... #..#.... #..##### ####...# ...#...# ...#...# ...#####",
  tictactoe = "..#..#.. ..#..#.. ######## ..#..#.. ..#..#.. ######## ..#..#.. ..#..#..",
  guess = ".####. #....# .....# ...##. ..#... ...... ..#...",
  print = "..####.. ..#..#.. ######## #......# #.####.# #.#..#.# ..####..",
  tasks = "......#. ....#.#. ..#.#.#. ..#.#.#. #.#.#.#. #.#.#.#. ########",
  settings = "...##... .#.##.#. ..####.. ###..### ###..### ..####.. .#.##.#. ...##...",
  about = "..####.. .######. ###..### ######## ###..### ###..### .##..##. ..####..",
  worm = "####.... #..#.... #..####. #.....#. ####..#. ...####.",
  agent = "...#.... ...#.... ..###... #######. ..###... ...#..#. ...#.### ......#.",
  notifications = "...##... ..####.. .######. .######. .######. ######## ...##...",
  devices = ".#..#... .#..#... ######.. ######.. .####... ..##.... ..##....",
  desktop = "######## #......# #......# #......# ######## ...##... .######.",
}
for id, spec in pairs(GLYPH) do GLYPH[id] = unpackRows(spec) end
metro.GLYPH = GLYPH

-- Interface marks. Circles are odd-sized so arrows sit on the exact centre.
metro.MARKS = {
  power = unpackRows("...#... .#.#.#. #..#..# #..#..# #.....# .#...#. ..###.."),
  search = "...####. ..#....# ..#....# ..#....# ..#....# ...####. ..#..... .#...... #.......",
  avatar = "......... ...###... ..#####.. ..#####.. ..#####.. ...###... ......... ..#####.. .#######.",
  down = "...###... .##...##. .#..#..#. #...#...# #.#.#.#.# #..###..# .#..#..#. .##...##. ...###...",
  up = "...###... .##...##. .#..#..#. #..###..# #.#.#.#.# #...#...# .#..#..#. .##...##. ...###...",
  back = "...###... .##...##. .#..#..#. #..#....# #.#####.# #..#....# .#..#..#. .##...##. ...###...",
  downSmall = "...##... ...##... ...##... .######. ..####.. ...##...",
  upSmall = "...##... ..####.. .######. ...##... ...##... ...##...",
  backSmall = ".#####. #..#..# #.#...# #..#..# #.....# .#####.",
}
for k, spec in pairs(metro.MARKS) do if type(spec) == "string" then metro.MARKS[k] = unpackRows(spec) end end

function metro.glyph(id) return GLYPH[id] or GLYPH.about end

-- Cells for a monochrome bitmap: fg digit on bg digit, offset by whole
-- teletext pixels (ox in 0..1, oy in 0..2) inside its cell grid.
local markCache = {}
function metro.markCells(rows, fg, bg, ox, oy)
  ox, oy = ox or 0, oy or 0
  local key = tostring(rows) .. fg .. bg .. ox .. oy
  local cached = markCache[key]
  if cached then return cached end
  local w, h = #rows[1] + ox, #rows + oy
  local cv = gfx.canvas(w + w % 2, h + (3 - h % 3) % 3, bg)
  metro.stamp(cv, 1 + ox, 1 + oy, rows, fg)
  cached = gfx.cells(cv.rows(), bg)
  markCache[key] = cached
  return cached
end

-- A flat tile filling pw x ph cells with a one-pixel gap on its right and
-- bottom edges (3 screen pixels each way, matching the 10px Start gutter).
-- Returns a canvas the caller can draw on, and the visible pixel size.
function metro.tileCanvas(pw, ph, color, gap)
  local cv = gfx.canvas(pw * 2, ph * 3, color)
  for y = 1, ph * 3 do cv.set(pw * 2, y, gap) end
  for x = 1, pw * 2 do cv.set(x, ph * 3, gap) end
  return cv, pw * 2 - 1, ph * 3 - 1
end

-- Centre a glyph inside a tile canvas above its label row.
function metro.placeGlyph(cv, rows, pw, ph, color, label)
  local vw, vh = pw * 2 - 1, ph * 3 - 1
  local gw, gh = #rows[1], #rows
  local x = floor((vw - gw) / 2) + 1
  local y = floor((vh - gh) / 2) + 1
  if label then y = min(y, (ph - 2) * 3 - gh - 1) end
  metro.stamp(cv, x, max(2, y), rows, color)
end

-- Bitmap of text in the heading face, ready for markCells.
local textCache, textCount = {}, 0
function metro.textRows(text, scale)
  scale = scale or 1
  local key = scale .. ":" .. text
  if textCache[key] then return textCache[key] end
  if textCount > 64 then textCache, textCount = {}, 0; markCache = {} end
  local w = max(1, metro.textWidth(text, scale))
  local cv = gfx.canvas(w, 9 * scale, ".")
  metro.drawText(cv, 1, 1, text, "#", scale)
  local rows = cv.rows()
  textCache[key], textCount = rows, textCount + 1
  return rows
end

return gfx
