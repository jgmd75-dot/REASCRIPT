-- GFX - tidy FX names.lua
-- author: JGWizrad / Garden FX (GFX)
--
-- Keeps "GFX ..." names in REAPER's FX browser (so the range stays grouped there) but shows tidy names on the
-- tracks: "GFX Drive81 [preamp]" becomes "Drive81 [preamp]", and the instrument "G" goes too ("GFX G Moon [Arcana
-- synth]" becomes "Moon [Arcana synth]"); Lab plug-ins lose "GFX Lab " too ("GFX Lab C2M [compressor]" becomes
-- "C2M [compressor]", "GFX Lab G Salem [synth]" becomes "Salem [synth]"). It sets each instance's own name, the same as right-clicking an FX and
-- choosing Rename, so it never touches an FX you have renamed yourself, and you can rename any of them afterwards.
--
-- It opens a small window: TIDY NOW tidies the project (track FX, take FX, the master and the monitoring chain),
-- RESTORE puts the full names back on the ones it tidied, and AUTO (lit) keeps tidying every GFX plug-in as soon as
-- it is inserted. The LCD counts the GFX plug-ins in the project. With AUTO lit the script keeps working after you
-- close the window (its toolbar button stays lit); run it again to bring the window back. With AUTO dark, closing
-- the window ends it. AUTO is remembered.
-- Needs REAPER 6.37 or later.

local SECTION = "GFX_tidy_names"

local function tidy(name)
  -- name is the plug-in's own name, e.g. "JS: GFX G Moon [Arcana synth]" or "GFX Drive81 [preamp]"
  local core = name:gsub("^%w+:%s*", "")                 -- drop a "JS: " style prefix if present
  if core:sub(1, 4) ~= "GFX " then return nil end
  core = core:sub(5)                                      -- drop "GFX "
  core = core:gsub("^Lab ", "")                           -- drop "Lab " (GFX Lab plug-ins)
  core = core:gsub("^G ", "")                             -- drop the instrument "G "
  return core
end

-- every FX in the project: fn(get, set) with get(key) / set(key, value) on its named config
local function each_fx(fn)
  local function track(tr)
    local function one(idx)
      fn(function(k) local _, v = reaper.TrackFX_GetNamedConfigParm(tr, idx, k); return v or "" end,
         function(k, v) reaper.TrackFX_SetNamedConfigParm(tr, idx, k, v) end)
    end
    for i = 0, reaper.TrackFX_GetCount(tr) - 1 do one(i) end
    -- the monitoring / input FX chain (record-input FX) uses indices from 0x1000000
    for i = 0, reaper.TrackFX_GetRecCount(tr) - 1 do one(0x1000000 + i) end
  end
  track(reaper.GetMasterTrack(0))
  for t = 0, reaper.CountTracks(0) - 1 do track(reaper.GetTrack(0, t)) end
  for it = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, it)
    for k = 0, reaper.CountTakes(item) - 1 do
      local take = reaper.GetTake(item, k)
      if take then
        for i = 0, reaper.TakeFX_GetCount(take) - 1 do
          fn(function(key) local _, v = reaper.TakeFX_GetNamedConfigParm(take, i, key); return v or "" end,
             function(key, v) reaper.TakeFX_SetNamedConfigParm(take, i, key, v) end)
        end
      end
    end
  end
end

-- tidy the GFX plug-ins nobody has renamed; returns how many
local function pass()
  local n = 0
  each_fx(function(get, set)
    if get("renamed_name") == "" then
      local t = tidy(get("fx_name"))
      if t then set("renamed_name", t); n = n + 1 end
    end
  end)
  return n
end

-- put the full names back on the ones this script tidied (a name you typed yourself stays); returns how many
local function restore()
  local n = 0
  each_fx(function(get, set)
    local t = tidy(get("fx_name"))
    if t and get("renamed_name") == t then set("renamed_name", ""); n = n + 1 end
  end)
  return n
end

-- GFX plug-ins in the project: all, tidy, still showing the full name
local function count()
  local all, tidied, long = 0, 0, 0
  each_fx(function(get)
    local t = tidy(get("fx_name"))
    if t then
      all = all + 1
      local r = get("renamed_name")
      if r == t then tidied = tidied + 1 elseif r == "" then long = long + 1 end
    end
  end)
  return all, tidied, long
end

-- =====================================================================
-- Drawing kit: REAPER's own graphics window (no extensions needed), in design units scaled to the window
-- =====================================================================
local K = { s = 1, ox = 0, oy = 0, down = false, was = false, clicked = false, held = nil }

local function col(c, a)            -- 0xRRGGBB, alpha 0..1
  gfx.set(((c >> 16) & 255) / 255, ((c >> 8) & 255) / 255, (c & 255) / 255, a or 1)
end
local function mul(c, f)            -- darken / lighten a colour
  local r = math.min(255, math.floor(((c >> 16) & 255) * f))
  local g = math.min(255, math.floor(((c >> 8) & 255) * f))
  local b = math.min(255, math.floor((c & 255) * f))
  return (r << 16) | (g << 8) | b
end
local function X(v) return K.ox + v * K.s end
local function Y(v) return K.oy + v * K.s end
local function S(v) return v * K.s end

-- filled rounded rectangle (each pixel drawn once, so translucent shadows stay even)
local function rr(x, y, w, h, r, c, a)
  col(c, a)
  x, y, w, h, r = X(x), Y(y), S(w), S(h), math.max(1, S(r))
  r = math.min(r, w / 2, h / 2)
  local yy = math.floor(y)
  local y1, y2 = math.floor(y + h + 0.5), math.floor(y + r)
  while yy < y1 do                               -- scanlines: rounded corners top and bottom
    local d = 0
    local cy = yy + 0.5
    if cy < y + r then local t = y + r - cy; d = r - math.sqrt(math.max(0, r * r - t * t))
    elseif cy > y + h - r then local t = cy - (y + h - r); d = r - math.sqrt(math.max(0, r * r - t * t)) end
    gfx.rect(math.floor(x + d + 0.5), yy, math.floor(w - 2 * d + 0.5), 1, 1)
    yy = yy + 1
  end
end

local FONT = 'Trebuchet MS'
local MONO = 'Courier New'
local function font(slot, face, size, bold) gfx.setfont(slot, face, math.max(6, math.floor(S(size) + 0.5)), bold and string.byte('b') or 0) end
local function text(x, y, s, c, align, a)    -- align: 0 left, 1 centre, 2 right (x is that edge / centre)
  col(c, a)
  local w = gfx.measurestr(s)
  gfx.x = X(x) - (align == 1 and w / 2 or align == 2 and w or 0); gfx.y = Y(y)
  gfx.drawstr(s)
end
local function text_h() local _, h = gfx.measurestr('Ag'); return h / K.s end

-- the mouse in design units, and a click = button released over the key it was pressed on
local function mouse_frame()
  K.mx, K.my = (gfx.mouse_x - K.ox) / K.s, (gfx.mouse_y - K.oy) / K.s
  K.was, K.down = K.down, (gfx.mouse_cap & 1) == 1
  K.pressed = K.down and not K.was
  K.released = K.was and not K.down
  if not K.down and not K.released then K.held = nil end
end
local function over(x, y, w, h) return K.mx >= x and K.mx < x + w and K.my >= y and K.my < y + h end

-- CC-80's rubber key: shadow, darker skirt, top (lighter on hover), legend, a small status LED top right.
-- The cap sinks 2 px while held. Returns true when clicked.
local function key(id, label, x, y, w, h, bg, fg, lit)
  local hov = over(x, y, w, h)
  if hov and K.pressed then K.held = id end
  local dn = K.held == id and K.down and hov
  local dy = dn and 2 or 0
  rr(x + 1, y + 3, w, h, 7, 0x000000, 0.33)
  rr(x, y + dy, w, h, 7, mul(bg, 0.72))
  rr(x + 2, y + dy + 1, w - 4, h - 5, 6, hov and mul(bg, 1.08) or bg)
  gfx.setfont(2)
  local _, th = gfx.measurestr(label)
  text(x + w / 2, y + dy + (h - 4) / 2 - th / K.s / 2, label, fg, 1)
  if lit ~= nil then
    if lit then col(0xFF5A2A) else col(0x000000, 0.2) end
    gfx.circle(X(x + w - 8), Y(y + dy + 7), S(3), 1, 1)
  end
  return K.released and K.held == id and hov
end

local function fonts()
  if K.fs == K.s then return end
  K.fs = K.s
  font(2, FONT, 15, true)          -- key legends
  font(4, FONT, 13, true)          -- brand / small print
  font(5, FONT, 19, true)          -- title
  font(6, MONO, 34, true)          -- LCD: big
  font(7, MONO, 19, true)          -- LCD: middle
  font(8, MONO, 14, true)          -- LCD: status row
end

-- KEY opens REAPER's Action List with this script selected, so a shortcut can be added there (Add... under Shortcuts)
local KEY_SEC, KEY_CMD = select(3, reaper.get_action_context())
local key_session = false
local function key_open()
  if reaper.PromptForAction then
    if key_session then reaper.PromptForAction(-1, 0, KEY_SEC) end
    reaper.PromptForAction(1, KEY_CMD, KEY_SEC); key_session = true
  else
    reaper.Main_OnCommand(40605, 0)   -- older REAPER: just show the Action List
  end
end
local function key_poll()           -- end the Action List session once it is closed or an action is picked
  if key_session and reaper.PromptForAction(0, 0, KEY_SEC) ~= 0 then
    reaper.PromptForAction(-1, 0, KEY_SEC); key_session = false
  end
end

-- the cream case, a darker edge bottom and right, and the brand strip with its solar cell
-- each GFX script has its own pastel case (this one lavender)
local FACE = 0xDDD5EE
local function case(DW, DH, title, sub)
  col(FACE); gfx.rect(0, 0, gfx.w, gfx.h, 1)
  -- fit the design into the window, centred
  K.s = math.max(0.5, math.min(gfx.w / DW, gfx.h / DH))
  K.ox, K.oy = math.floor((gfx.w - DW * K.s) / 2), math.floor((gfx.h - DH * K.s) / 2)
  fonts()
  col(mul(FACE, 0.8)); gfx.rect(0, gfx.h - S(3), gfx.w, S(3), 1); gfx.rect(gfx.w - S(3), 0, S(3), gfx.h - S(3), 1)
  local x0, w0 = 16, DW - 32
  gfx.setfont(4); text(x0, 12, 'GFX', 0x3B3B3F)
  gfx.setfont(5); text(x0, 28, title, 0xC0392B)
  local tw = gfx.measurestr(title) / K.s
  gfx.setfont(4); text(x0 + tw + 10, 33, sub, 0x3B3B3F)
  local sx = x0 + w0 - 84
  rr(sx, 10, 84, 34, 3, 0x3A2A1E)
  col(0x5A4636); for i = 1, 2 do gfx.rect(X(sx + i * 28), Y(12), math.max(1, S(1)), S(30), 1) end
  if key('gfx_key', 'KEY', sx - 60, 11, 52, 32, 0x6F6F76, 0xF4F1E8) then key_open() end
  key_poll()
end

-- the recessed green LCD
local function lcd(x, y, w, h)
  rr(x, y, w, h, 8, 0x2A2A2C)
  rr(x + 8, y + 8, w - 16, h - 16, 3, 0x9FAE8C)
end
local function lcd_text(slot, x, y, s, cells)
  gfx.setfont(slot)
  text(x, y, string.rep('8', cells), 0x1C2416, 0, 0.06)
  text(x, y, s, 0x1C2416)
end


-- =====================================================================
-- The window
-- =====================================================================
local DW, DH = 440, 300
local auto = reaper.GetExtState(SECTION, "auto") ~= "0"            -- AUTO is lit unless you switched it off
local status = "READY"
local n_all, n_tidy, n_long = 0, 0, 0
local shown = false

local function draw()
  case(DW, DH, 'TIDY FX', 'NAMES ON YOUR TRACKS')
  local x0, w0 = 16, DW - 32
  local ly, lh = 56, 114
  lcd(x0, ly, w0, lh)
  lcd_text(6, x0 + 18, ly + 12, n_all == 0 and 'NO GFX' or string.format('%d GFX', n_all), 14)
  lcd_text(7, x0 + 18, ly + 54, n_all == 0 and 'NONE IN THIS PROJECT'
           or n_long == 0 and (n_tidy == n_all and 'ALL TIDY' or string.format('%d TIDY, %d YOURS', n_tidy, n_all - n_tidy))
           or string.format('%d TIDY, %d LONG', n_tidy, n_long), 26)
  gfx.setfont(8)
  text(x0 + 18, ly + 84, auto and 'AUTO ON' or 'AUTO OFF', 0x1C2416)
  text(x0 + w0 - 18, ly + 84, status, 0x1C2416, 2)

  local y, kh, gap = ly + lh + 16, 44, 8
  local u = (w0 - gap * 2) / 3
  if key('tidy', 'TIDY NOW', x0, y, u, kh, 0xE48A2A, 0x1E1E1E) then
    reaper.Undo_BeginBlock(); local n = pass(); reaper.Undo_EndBlock("GFX: tidy FX names", -1)
    status = n == 0 and 'NOTHING TO DO' or string.format('TIDIED %d', n)
  end
  if key('restore', 'RESTORE', x0 + u + gap, y, u, kh, 0x6F6F76, 0xF4F1E8) then
    reaper.Undo_BeginBlock(); local n = restore(); reaper.Undo_EndBlock("GFX: restore FX names", -1)
    if n > 0 and auto then auto = false; reaper.SetExtState(SECTION, "auto", "0", true) end   -- or AUTO would undo it
    status = n == 0 and 'NOTHING TO DO' or string.format('RESTORED %d', n)
  end
  if key('auto', 'AUTO', x0 + (u + gap) * 2, y, u, kh, 0x6F6F76, 0xF4F1E8, auto) then
    auto = not auto; reaper.SetExtState(SECTION, "auto", auto and "1" or "0", true)
    status = auto and 'AUTO ON' or 'AUTO OFF'
  end
  gfx.setfont(4)
  text(x0, y + kh + 14, 'AUTO tidies new GFX plug-ins as you add them, even with', mul(FACE, 0.58))
  text(x0, y + kh + 32, 'this window closed. Names you typed yourself are kept.', mul(FACE, 0.58))
end

local function open_window()
  gfx.ext_retina = 1
  gfx.init("GFX tidy FX names", DW, DH, tonumber(reaper.GetExtState(SECTION, "dock")) or 0)
  shown = true
end

-- Run / show: a second launch while it runs brings the window back.
local _, _, sec, cmd = reaper.get_action_context()
if reaper.GetExtState(SECTION, "running") == "1" then
  reaper.SetExtState(SECTION, "show", "1", false)        -- the running copy sees this and opens its window
  return
end
reaper.SetExtState(SECTION, "running", "1", false)
reaper.SetToggleCommandState(sec, cmd, 1); reaper.RefreshToolbar2(sec, cmd)

local last_state, last_t = -1, 0
local function loop()
  local now = reaper.time_precise()
  local st = reaper.GetProjectStateChangeCount(0)
  if st ~= last_state and now - last_t > 0.5 then        -- only after something changed, at most twice a second
    last_state, last_t = st, now
    if auto then pass() end
    if shown then n_all, n_tidy, n_long = count() end
  end
  if reaper.GetExtState(SECTION, "show") == "1" then
    reaper.SetExtState(SECTION, "show", "0", false)
    if not shown then open_window(); last_state = -1 end
  end
  if shown then
    local c = gfx.getchar()
    if c < 0 then
      reaper.SetExtState(SECTION, "dock", tostring(gfx.dock(-1)), true)
      gfx.quit(); shown = false
    else
      mouse_frame()
      draw()
      gfx.update()
    end
  end
  if not shown and not auto then return end              -- window closed with AUTO dark: done
  reaper.defer(loop)
end

reaper.atexit(function()
  reaper.SetExtState(SECTION, "running", "0", false)
  reaper.SetToggleCommandState(sec, cmd, 0); reaper.RefreshToolbar2(sec, cmd)
end)

open_window()
loop()
