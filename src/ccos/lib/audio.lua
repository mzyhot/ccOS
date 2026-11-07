-- ccOS audio: two speakers as a stereo pair.
--
-- Everything that touches a speaker runs in the audio service coroutine,
-- so the kernel never waits on a peripheral. Other code calls the
-- functions here, which change state and wake the service.
--
-- Music: .dfpwm (mono, played on both sides), stereo pairs named
-- song.l.dfpwm / song.r.dfpwm, .wav (8 or 16-bit PCM, mono or stereo,
-- any sample rate), http(s) URLs to either, and music discs in a drive.

return function(K)
local A = {}
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local RATE = 48000
local CHUNK = 4096                 -- DFPWM bytes a chunk: 32768 samples, ~0.68 s
local SAMPLES = CHUNK * 8
local function now() return os.epoch("utc") end

A.state = "stopped"                -- stopped | playing | paused
A.queue, A.index = {}, 0
A.track = nil                      -- {path, title, kind, len}
A.pos = 0                          -- seconds into the track
A.levels = { l = 0, r = 0 }
A.chunks = {}                      -- recently queued chunks, for the visualiser
A.shuffle, A.loop = false, "all"   -- loop: off | all | one
A.spk = { l = nil, r = nil }
A.disc = nil                       -- drive playing a record
A.message = nil                    -- last error, for the music app

local fx, wakeups = {}, {}
local src, pending

local function cfg() return K.cfg end
local function wake() os.queueEvent("ccos_audio") end

function A.detect()
  local names = {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "speaker" then names[#names + 1] = n end
  end
  table.sort(names)
  local l, r
  for _, n in ipairs(names) do
    if n == "left" then l = n elseif n == "right" then r = n end
  end
  if not (l and r) then l, r = names[1], names[2] end
  if cfg().swapSpeakers and r then l, r = r, l end
  A.spk.l, A.spk.r = l, r or l
  A.count = #names
end

local function call(name, method, ...)
  local ok, res = pcall(peripheral.call, name, method, ...)
  return ok and res
end

-- Volumes for each side from a base volume and the balance setting.
local function sides(v)
  local b = cfg().balance or 0
  return v * min(1, 1 - b), v * min(1, 1 + b)
end

------------------------------------------------------------------------
-- Notes and sound effects
------------------------------------------------------------------------

local function noteNow(inst, pitch, pan, vol)
  local l, r = A.spk.l, A.spk.r
  if not l then return end
  if l == r then
    call(l, "playNote", inst, min(3, vol), pitch)
    return
  end
  pan = pan or 0
  local vl, vr = sides(vol)
  vl, vr = vl * min(1, 1 - pan), vr * min(1, 1 + pan)
  if vl > 0.03 then call(l, "playNote", inst, min(3, vl), pitch) end
  if vr > 0.03 then call(r, "playNote", inst, min(3, vr), pitch) end
end

-- Play a note: pan -1 (left) to 1 (right), volume 0-3.
function A.note(inst, pitch, pan, vol)
  fx[#fx + 1] = { at = 0, fn = function() noteNow(inst, pitch, pan, vol or 1) end }
  wake()
end

local function seq(steps)
  local t = now()
  for _, s in ipairs(steps) do
    fx[#fx + 1] = { at = t + s[1], fn = function() noteNow(s[2], s[3], s[4], s[5]) end }
  end
  wake()
end

local SFX = {
  click = function(v) seq({ { 0, "hat", 20, 0, 0.18 * v } }) end,
  open = function(v) seq({ { 0, "chime", 13, -0.5, 0.45 * v }, { 70, "chime", 18, 0.5, 0.45 * v } }) end,
  close = function(v) seq({ { 0, "chime", 18, 0.5, 0.4 * v }, { 70, "chime", 13, -0.5, 0.4 * v } }) end,
  notify = function(v)
    seq({ { 0, "bell", 13, -0.7, 0.7 * v }, { 110, "bell", 17, 0, 0.7 * v }, { 220, "bell", 20, 0.7, 0.7 * v } })
  end,
  error = function(v) seq({ { 0, "bass", 8, -0.3, 1.2 * v }, { 150, "bass", 4, 0.3, 1.2 * v } }) end,
  disk = function(v) seq({ { 0, "pling", 8, -0.6, 0.5 * v }, { 90, "pling", 15, 0.6, 0.5 * v } }) end,
  alarm = function(v)
    local s = {}
    for i = 0, 5 do
      s[#s + 1] = { i * 260, "bell", 18, -0.8, v }
      s[#s + 1] = { i * 260 + 130, "bell", 22, 0.8, v }
    end
    seq(s)
  end,
}

function A.sfx(name)
  if not cfg().sounds then return end
  local f = SFX[name]
  if f then f((cfg().uiVolume or 0.6) * 2) end
end

-- The boot chime: a stereo chord synthesised as PCM, rising left to right.
local function chimePCM()
  local n = floor(RATE * 1.3)
  local L, R = {}, {}
  local SIN = {}
  for i = 0, 1023 do SIN[i] = math.sin(i / 1024 * 2 * math.pi) end
  local voices = {}
  for k, f in ipairs({ 392.00, 493.88, 587.33, 783.99, 987.77 }) do
    voices[k] = { step = f * 1024 / RATE, start = floor((k - 1) * 0.09 * RATE), pan = (k - 1) / 4, ph = 0, ph2 = 0 }
  end
  for i = 1, n, 2 do
    local l, r = 0, 0
    for _, v in ipairs(voices) do
      if i > v.start then
        local t = (i - v.start) / RATE
        local env = min(1, t * 60) * math.exp(-t * 2.6)
        v.ph = (v.ph + v.step * 2) % 1024
        v.ph2 = (v.ph2 + v.step * 4) % 1024
        local s = (SIN[floor(v.ph)] + 0.25 * SIN[floor(v.ph2)]) * env
        l, r = l + s * (1 - v.pan * 0.75), r + s * (0.25 + v.pan * 0.75)
      end
    end
    local sl, sr = max(-128, min(127, floor(l * 26))), max(-128, min(127, floor(r * 26)))
    L[i], L[i + 1], R[i], R[i + 1] = sl, sl, sr, sr
  end
  return L, R
end

------------------------------------------------------------------------
-- Sources
------------------------------------------------------------------------

local function ext(path) return (path:match("%.([%w]+)$") or ""):lower() end

local function u16(s, i) local a, b = s:byte(i, i + 1); return a + b * 256 end
local function u32(s, i) local a, b, c, d = s:byte(i, i + 3); return a + b * 256 + c * 65536 + d * 16777216 end

-- A reader over a file handle or a downloaded string.
local function reader(item)
  if item.kind == "url" then
    if not http then return nil, "HTTP is disabled on this server" end
    local h, err = http.get(item.path, nil, true)
    if not h then return nil, err or "download failed" end
    local data = h.readAll() or ""
    h.close()
    local at = 1
    return {
      read = function(n)
        if at > #data then return nil end
        local s = data:sub(at, at + n - 1)
        at = at + n
        return s
      end,
      seek = function(_, off) at = off + 1 end,
      size = #data,
      close = function() end,
    }
  end
  local h = fs.open(item.path, "rb")
  if not h then return nil, "can't open " .. item.path end
  return { read = h.read, seek = h.seek, size = fs.getSize(item.path), close = h.close }
end

local function openDfpwm(item, path)
  local r, err = reader({ kind = item.kind, path = path })
  if not r then return nil, err end
  return r
end

local function openSource(item)
  local dfpwm = K.require("cc.audio.dfpwm")
  local format = item.format or ext(item.path)
  if item.kind == "stereo" then
    local hl, err = openDfpwm(item, item.left)
    if not hl then return nil, err end
    local hr = openDfpwm(item, item.right)
    local dl, dr = dfpwm.make_decoder(), dfpwm.make_decoder()
    return {
      len = hl.size * 8 / RATE,
      read = function()
        local a = hl.read(CHUNK)
        if not a then return nil end
        local b = hr and hr.read(CHUNK)
        local L = dl(a)
        return L, b and dr(b) or L
      end,
      seek = function(sec)
        local off = floor(sec * RATE / 8)
        hl.seek("set", off)
        if hr then hr.seek("set", off) end
        dl, dr = dfpwm.make_decoder(), dfpwm.make_decoder()
      end,
      close = function() hl.close(); if hr then hr.close() end end,
    }
  end
  local r, err = reader(item)
  if not r then return nil, err end
  if format == "wav" then
    local head = r.read(12)
    if not head or head:sub(1, 4) ~= "RIFF" or head:sub(9, 12) ~= "WAVE" then
      r.close()
      return nil, "not a WAV file"
    end
    local channels, rate, bits, dataStart, dataSize
    local offset = 12
    while true do
      local id, sz = r.read(4), r.read(4)
      if not id or not sz or #sz < 4 then break end
      local size = u32(sz, 1)
      offset = offset + 8
      if id == "fmt " then
        local f = r.read(size)
        if u16(f, 1) ~= 1 then r.close(); return nil, "only PCM WAV files play" end
        channels, rate, bits = u16(f, 3), u32(f, 5), u16(f, 15)
      elseif id == "data" then
        dataStart, dataSize = offset, size
        break
      else
        r.read(size + size % 2)
      end
      offset = offset + size + size % 2
    end
    if not dataStart or not channels or (bits ~= 8 and bits ~= 16) then
      r.close()
      return nil, "unsupported WAV (8 or 16-bit PCM only)"
    end
    local frame = channels * bits / 8
    local step = rate / RATE
    local want = floor(SAMPLES * step) * frame
    local played = 0
    return {
      len = dataSize / frame / rate,
      read = function()
        if played >= dataSize then return nil end
        local data = r.read(min(want, dataSize - played))
        if not data or #data < frame then return nil end
        played = played + #data
        local frames = floor(#data / frame)
        local L, R = {}, {}
        local n = floor(frames / step)
        for i = 1, n do
          local base = floor((i - 1) * step) * frame + 1
          local l, rr
          if bits == 8 then
            l = data:byte(base) - 128
            rr = channels > 1 and data:byte(base + 1) - 128 or l
          else
            l = data:byte(base + 1)
            if l >= 128 then l = l - 256 end
            if channels > 1 then
              rr = data:byte(base + 3)
              if rr >= 128 then rr = rr - 256 end
            else
              rr = l
            end
          end
          L[i], R[i] = l, rr
        end
        return L, R
      end,
      seek = function(sec)
        played = floor(sec * rate) * frame
        r.seek("set", dataStart + played)
      end,
      close = r.close,
    }
  end
  local dec = dfpwm.make_decoder()
  return {
    len = r.size * 8 / RATE,
    read = function()
      local data = r.read(CHUNK)
      if not data then return nil end
      local s = dec(data)
      return s, s
    end,
    seek = function(sec)
      r.seek("set", floor(sec * RATE / 8))
      dec = dfpwm.make_decoder()
    end,
    close = r.close,
  }
end

------------------------------------------------------------------------
-- Playback control (called from anywhere)
------------------------------------------------------------------------

local function title(path)
  local name = fs.getName(path):gsub("%.[lr]%.dfpwm$", ""):gsub("%.[%w]+$", ""):gsub("[_%-]", " ")
  return name
end
A.titleOf = title

-- An entry for a path or URL.
function A.item(path)
  if path:match("^https?://") then
    return { kind = "url", path = path, title = title(path:match("[^/]+$") or path) }
  end
  local base = path:match("^(.-)%.[lr]%.dfpwm$")
  if base then
    return { kind = "stereo", path = path, left = base .. ".l.dfpwm", right = base .. ".r.dfpwm", title = title(base) }
  end
  return { kind = "file", path = path, title = title(path) }
end

local function closeSource()
  if src then pcall(src.close) end
  src, pending = nil, nil
end

local function stopSpeakers()
  if A.spk.l then call(A.spk.l, "stop") end
  if A.spk.r and A.spk.r ~= A.spk.l then call(A.spk.r, "stop") end
end

local cmd = nil
local function command(c)
  cmd = c
  wake()
end

-- Play a list of items (or a single path), starting at index i.
function A.play(list, i)
  if type(list) == "string" then list = { A.item(list) } end
  A.queue, A.index = list, i or 1
  command("start")
end
function A.enqueue(item)
  A.queue[#A.queue + 1] = type(item) == "string" and A.item(item) or item
  if A.state == "stopped" then A.index = #A.queue; command("start") end
end
function A.pause() if A.state == "playing" then command("pause") end end
function A.resume() if A.state == "paused" then command("resume") elseif A.state == "stopped" and #A.queue > 0 then command("start") end end
function A.toggle() if A.state == "playing" then A.pause() else A.resume() end end
function A.stop() command("stop") end
function A.next() command("next") end
function A.prev() command("prev") end
function A.seek(frac) A.seekTo = frac; command("seek") end
function A.setVolume(v) cfg().musicVolume = max(0, min(1, v)); K.saveConfig() end
function A.setBalance(b) cfg().balance = max(-1, min(1, b)); K.saveConfig() end
function A.playDisc(drive) A.discWant = drive; command("disc") end
function A.stopDisc() command("discstop") end
function A.boot() fx[#fx + 1] = { at = 0, boot = true }; wake() end

-- What's playing, for the apps and the panel.
function A.info()
  local t = A.track
  return {
    state = A.state, title = t and t.title, kind = t and t.kind, pos = A.pos, len = A.len,
    index = A.index, count = #A.queue, levels = A.levels, disc = A.disc, discTitle = A.discTitle,
    speakers = A.count or 0, message = A.message,
  }
end

-- Level of each side right now, from the chunk that should be playing.
function A.levelsNow()
  local t = now()
  for i = #A.chunks, 1, -1 do
    local c = A.chunks[i]
    if t >= c.start then
      if t > c.stop + 300 then return 0, 0 end
      local k = min(#c.l, max(1, floor((t - c.start) / max(1, c.stop - c.start) * #c.l) + 1))
      return c.l[k], c.r[k]
    end
  end
  return 0, 0
end

-- Recent levels, newest last, for drawing bars: {{l, r}, ...}.
function A.history(n)
  local out, t = {}, now()
  for i = #A.chunks, 1, -1 do
    local c = A.chunks[i]
    if c.start <= t then
      local upto = min(#c.l, floor((t - c.start) / max(1, c.stop - c.start) * #c.l) + 1)
      for k = upto, 1, -1 do
        table.insert(out, 1, { c.l[k], c.r[k] })
        if #out >= n then return out end
      end
    end
  end
  return out
end

------------------------------------------------------------------------
-- The service
------------------------------------------------------------------------

local function analyse(L, R, n)
  local blocks = 24
  local size = max(1, floor(n / blocks))
  local bl, br = {}, {}
  for b = 0, blocks - 1 do
    local sl, sr, c = 0, 0, 0
    for i = b * size + 1, min(n, (b + 1) * size), 6 do
      local a, d = L[i], R[i]
      sl, sr, c = sl + (a < 0 and -a or a), sr + (d < 0 and -d or d), c + 1
    end
    bl[b + 1] = min(1, sl / max(1, c) / 48)
    br[b + 1] = min(1, sr / max(1, c) / 48)
  end
  return bl, br
end

local playClock = 0               -- when the queued audio runs out (epoch ms)

-- cut: stop what's still buffered (a skip) rather than letting it finish
-- (a track ending on its own).
local function startTrack(cut)
  closeSource()
  if cut then
    stopSpeakers()
    A.chunks, playClock = {}, 0
  end
  local item = A.queue[A.index]
  if not item then A.state = "stopped"; A.track = nil; return end
  local s, err = openSource(item)
  if not s then
    A.message = (item.title or "?") .. ": " .. tostring(err)
    K.notify("Can't play", A.message, { icon = "music", color = colors.red })
    A.state = "stopped"
    A.track = nil
    return
  end
  src, A.track, A.len, A.pos, A.message = s, item, s.len, 0, nil
  A.state = "playing"
  K.notify("Now playing", item.title, { icon = "music", quiet = true, silent = not cut })
  K.changed("audio")
end

local function advance(dir, cut)
  local n = #A.queue
  if n == 0 then A.state = "stopped"; return end
  if A.loop == "one" and dir == 0 then
    -- replay the same track
  elseif A.shuffle and n > 1 then
    local i = A.index
    while i == A.index do i = math.random(1, n) end
    A.index = i
  else
    A.index = A.index + (dir == -1 and -1 or 1)
    if A.index > n then
      if A.loop == "all" then A.index = 1 else A.index = n; A.state = "stopped"; closeSource(); A.track = nil; return end
    elseif A.index < 1 then
      A.index = A.loop == "all" and n or 1
    end
  end
  startTrack(cut)
end

local function handleCommand()
  local c = cmd
  cmd = nil
  if not c then return end
  if c == "start" then startTrack(true)
  elseif c == "pause" then
    A.pos = A.elapsed()
    A.state = "paused"
    stopSpeakers()
    pending, A.chunks = nil, {}
  elseif c == "resume" then
    if src then A.state = "playing"; playClock = 0; if A.pos then src.seek(A.pos) end else startTrack(true) end
  elseif c == "stop" then closeSource(); stopSpeakers(); A.state = "stopped"; A.track = nil; A.chunks = {}
  elseif c == "next" then advance(1, true)
  elseif c == "prev" then
    if A.pos > 3 and src then src.seek(0); A.pos = 0; stopSpeakers(); pending = nil; A.chunks = {}; playClock = 0
    else advance(-1, true) end
  elseif c == "seek" and src and A.len then
    A.pos = max(0, min(A.len - 0.5, (A.seekTo or 0) * A.len))
    src.seek(A.pos)
    stopSpeakers()
    pending, A.chunks, playClock = nil, {}, 0
  elseif c == "disc" then
    if A.disc then call(A.disc, "stopAudio") end
    A.disc = A.discWant
    A.discTitle = call(A.disc, "getAudioTitle") or "Record"
    call(A.disc, "playAudio")
    K.notify("Playing record", A.discTitle, { icon = "disk", quiet = true })
  elseif c == "discstop" then
    if A.disc then call(A.disc, "stopAudio") end
    A.disc, A.discTitle = nil, nil
  end
  K.changed("audio")
end

local function runFx()
  local t = now()
  local keep = {}
  local soonest
  for _, f in ipairs(fx) do
    if f.at <= t then
      if f.boot then
        if A.state ~= "playing" and A.spk.l and cfg().sounds then
          local L, R = chimePCM()
          local v = (cfg().uiVolume or 0.6) * 1.6
          local vl, vr = sides(v)
          if A.spk.l == A.spk.r then
            for i = 1, #L do L[i] = floor((L[i] + R[i]) / 2) end
            call(A.spk.l, "playAudio", L, v)
          else
            call(A.spk.l, "playAudio", L, vl)
            call(A.spk.r, "playAudio", R, vr)
          end
        end
      else
        pcall(f.fn)
      end
    else
      keep[#keep + 1] = f
      if not soonest or f.at < soonest then soonest = f.at end
    end
  end
  fx = keep
  return soonest
end

-- Send the pending chunk to whichever speakers still need it.
local function feed()
  local l, r = A.spk.l, A.spk.r
  local vol = (cfg().musicVolume or 1) * 2
  local vl, vr = sides(vol)
  if l == r then
    if not pending.mono then
      local M = {}
      for i = 1, pending.n do M[i] = floor((pending.L[i] + pending.R[i]) / 2) end
      pending.mono = M
    end
    if not pending.sentL then pending.sentL = call(l, "playAudio", pending.mono, vol) end
    pending.sentR = pending.sentL
  else
    if not pending.sentL then pending.sentL = call(l, "playAudio", pending.L, vl) end
    if not pending.sentR then pending.sentR = call(r, "playAudio", pending.R, vr) end
  end
  return pending.sentL and pending.sentR
end

function A.service()
  A.detect()
  local timer
  while true do
    handleCommand()
    local soonest = runFx()
    local busy = false
    if A.state == "playing" and src and A.spk.l then
      if not pending then
        local ok, L, R = pcall(src.read)
        if not ok then
          A.message = tostring(L)
          L = nil
        end
        if L then
          pending = { L = L, R = R or L, n = #L }
        else
          advance(0)
          busy = A.state == "playing"
        end
      end
      if pending and feed() then
        local dur = pending.n / RATE * 1000
        local start = max(now(), playClock)
        playClock = start + dur
        local bl, br = analyse(pending.L, pending.R, pending.n)
        A.chunks[#A.chunks + 1] = { start = start, stop = start + dur, l = bl, r = br, pos = A.pos, track = A.track }
        if #A.chunks > 8 then table.remove(A.chunks, 1) end
        A.pos = A.pos + pending.n / RATE
        pending = nil
        busy = true
      end
    elseif A.state == "playing" and not A.spk.l then
      A.message = "No speakers attached"
      A.state = "paused"
    end
    if not busy then
      if timer then os.cancelTimer(timer) end
      timer = os.startTimer(soonest and max(0.05, (soonest - now()) / 1000) or 1)
      while true do
        local e, p = os.pullEvent()
        if e == "ccos_audio" or e == "speaker_audio_empty" or (e == "timer" and p == timer) then break end
        if e == "peripheral" or e == "peripheral_detach" then A.detect(); break end
      end
    end
  end
end

-- Smoothed levels for meters, updated by whoever draws them.
function A.meter()
  local l, r = A.levelsNow()
  if A.state ~= "playing" then l, r = 0, 0 end
  A.levels.l = max(l, A.levels.l * 0.7)
  A.levels.r = max(r, A.levels.r * 0.7)
  return A.levels.l, A.levels.r
end

-- Elapsed seconds, following what's audible rather than what's queued.
function A.elapsed()
  local t = now()
  local any = false
  for i = #A.chunks, 1, -1 do
    local c = A.chunks[i]
    if c.track == A.track then
      any = true
      if t >= c.start then return min(A.len or 0, c.pos + min(t, c.stop) / 1000 - c.start / 1000) end
    end
  end
  return any and 0 or A.pos
end

return A
end
