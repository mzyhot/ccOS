-- One clock policy for the desktop, monitors, apps, notifications and agent.
local M = {}
local floor = math.floor
M.zones = { "local", "UTC", "America/Chicago", "America/New_York", "America/Denver", "America/Los_Angeles",
  "Europe/London", "Europe/Berlin", "Asia/Kolkata", "Asia/Tokyo", "Australia/Sydney", "fixed" }
local zones = {
  UTC = { 0 }, ["America/Chicago"] = { -360, "us" }, ["America/New_York"] = { -300, "us" },
  ["America/Denver"] = { -420, "us" }, ["America/Los_Angeles"] = { -480, "us" },
  ["Europe/London"] = { 0, "eu" }, ["Europe/Berlin"] = { 60, "eu" },
  ["Asia/Kolkata"] = { 330 }, ["Asia/Tokyo"] = { 540 }, ["Australia/Sydney"] = { 600, "au" },
}
-- Gregorian civil date -> days since 1970-01-01, independent of host timezone.
function M.days(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = floor(y / 400)
  local yo = y - era * 400
  local mp = m + (m > 2 and -3 or 9)
  local doy = floor((153 * mp + 2) / 5) + d - 1
  return era * 146097 + yo * 365 + floor(yo / 4) - floor(yo / 100) + doy - 719468
end
local function sunday(y, m, n)
  local weekday = (M.days(y, m, 1) + 4) % 7
  return 1 + (7 - weekday) % 7 + (n - 1) * 7
end
local function lastSunday(y, m)
  local last = M.days(y, m + 1, 1) - M.days(y, m, 1)
  return last - (M.days(y, m, last) + 4) % 7
end
function M.offset(cfg, at)
  at = at or floor(os.epoch("utc") / 1000)
  local zone = cfg.timezone or "local"
  if zone == "local" then return floor((os.epoch("local") - os.epoch("utc")) / 60000 + 0.5) end
  if zone == "fixed" then return math.max(-720, math.min(840, tonumber(cfg.utcOffset) or 0)) end
  local z = zones[zone] or zones.UTC
  local offset, rule = z[1], z[2]
  if rule then
    local y = os.date("!*t", at).year
    local start, finish
    if rule == "us" then
      start = M.days(y, 3, sunday(y, 3, 2)) * 86400 + 7200 - offset * 60
      finish = M.days(y, 11, sunday(y, 11, 1)) * 86400 + 7200 - (offset + 60) * 60
    elseif rule == "eu" then
      start = M.days(y, 3, lastSunday(y, 3)) * 86400 + 3600
      finish = M.days(y, 10, lastSunday(y, 10)) * 86400 + 3600
    else
      start = M.days(y, 10, sunday(y, 10, 1)) * 86400 + 7200 - offset * 60
      finish = M.days(y, 4, sunday(y, 4, 1)) * 86400 + 10800 - (offset + 60) * 60
    end
    local dst = rule == "au" and (at >= start or at < finish) or (rule ~= "au" and at >= start and at < finish)
    if dst then offset = offset + 60 end
  end
  return offset
end
function M.date(cfg, fmt, at)
  at = at or floor(os.epoch("utc") / 1000)
  return os.date("!" .. (fmt or "%c"):gsub("^!", ""), at + M.offset(cfg, at) * 60)
end
function M.format(cfg, seconds, at)
  local d = M.date(cfg, "*t", at)
  local h = cfg.clock24 and d.hour or ((d.hour + 11) % 12 + 1)
  local hour = cfg.leadingZero and ("%02d"):format(h) or tostring(h)
  return hour .. (":%02d"):format(d.min) .. (seconds and (":%02d"):format(d.sec) or "")
    .. (cfg.clock24 and "" or (d.hour < 12 and " AM" or " PM"))
end
function M.label(cfg)
  local n = M.offset(cfg)
  return (cfg.timezone == "fixed" and "UTC" or (cfg.timezone or "local")) .. (" (UTC%s%d:%02d)"):format(n < 0 and "-" or "+", floor(math.abs(n) / 60), math.abs(n) % 60)
end
function M.valid(zone) return zone == "local" or zone == "fixed" or zones[zone] ~= nil end
return M
