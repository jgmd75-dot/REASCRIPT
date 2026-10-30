-- @description GFX - set selected tracks' input to all MIDI
-- @author GardenFX
-- by JGWizrad / Garden FX (GFX)
-- @version 1.1
-- @changelog
--   A window in the GFX calculator style, with a MONITOR key and KEY for a shortcut.
-- @about
--   Sets the record input of every selected track to MIDI: all inputs, all channels, so a GFX instrument on the
--   track plays from your keyboard straight away. It opens a small window: SET MIDI INPUT does it, MONITOR (lit)
--   also turns record monitoring on. KEY makes SET MIDI INPUT an action of its own for a shortcut: it sets the
--   selected tracks with the window's settings, without opening the window. Needs nothing but REAPER.

local SECTION = "GFX_input_midi"
local opt = { monitor = reaper.GetExtState(SECTION, "monitor") ~= "0" }
local function opt_flip(k) opt[k] = not opt[k]; reaper.SetExtState(SECTION, k, opt[k] and "1" or "0", true) end

local function set_input()
  local n = reaper.CountSelectedTracks(0)
  if n == 0 then return 0 end
  reaper.Undo_BeginBlock()
  for i = 0, n - 1 do
    local tr = reaper.GetSelectedTrack(0, i)
    reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", 4096 | (63 << 5))   -- MIDI, all devices, all channels
    if opt.monitor then reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 1) end
  end
  reaper.Undo_EndBlock("GFX - set input to all MIDI", -1)
  return n
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

-- ORCHD's rubber key: shadow, darker skirt, top (lighter on hover), legend, a small status LED top right.
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
  if K.remote == id then K.remote = nil; return true end         -- pressed by a shortcut made with KEY
  local hit = K.released and K.held == id and hov
  if hit and K.pick and id ~= 'gfx_key' then K.pick = false; K.make(id, label); return false end
  return hit
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

-- KEY, then any key: that key becomes an action of its own (a small script in "GFX shortcuts" beside this one), so a
-- keyboard shortcut or toolbar button does what the key does without opening this window. The Action List opens
-- on the new action: Add... under Shortcuts sets its key. Press KEY again (it reads PICK) to cancel. A script with
-- one main job sets K.key_default: KEY then makes that job's action straight away (using the window's settings).
local KEY_NAME, KEY_EXT = 'GFX MIDI input', SECTION
local KEY_FILE = GFX_MAIN or select(2, reaper.get_action_context())   -- GFX_MAIN: set when a shortcut runs this
local key_session = false
local function key_poll()           -- end the Action List session once it is closed or an action is picked
  if key_session and reaper.PromptForAction(0, 0, 0) ~= 0 then
    reaper.PromptForAction(-1, 0, 0); key_session = false
  end
end
function K.make(id, label)
  local dir = KEY_FILE:match('^(.*)[/\\]') .. '/GFX shortcuts'
  reaper.RecursiveCreateDirectory(dir, 0)
  local nice = ((K.names and K.names[id]) or label):gsub('#', 'sharp'):gsub('=', 'equals'):gsub('/', '-')
  nice = nice:gsub('[^%w%+%- ]', '')
  local path = dir .. '/' .. KEY_NAME .. ' - ' .. nice .. '.lua'
  local f = io.open(path, 'w')
  if not f then return end
  f:write(string.format('-- %s: the %s key, made with its KEY button\nGFX_MAIN = %q\n'
    .. 'reaper.SetExtState(%q, "remote", %q, false)\ndofile(GFX_MAIN)\n', KEY_NAME, nice, KEY_FILE, KEY_EXT, id))
  f:close()
  local cmd = reaper.AddRemoveReaScript(true, 0, path, true)
  if cmd ~= 0 and reaper.PromptForAction then
    if key_session then reaper.PromptForAction(-1, 0, 0) end
    reaper.PromptForAction(1, cmd, 0); key_session = true
  else
    reaper.Main_OnCommand(40605, 0)   -- older REAPER: just show the Action List
  end
end
-- A shortcut runs this script with its key waiting: hand the key to the open window, or do it here without one
-- (headless[id]); a key with no quiet version opens the window and is pressed there. True when nothing is left to do.
function K.remote_start(headless)
  local id = reaper.GetExtState(KEY_EXT, 'remote')
  if id == '' then return false end
  reaper.SetExtState(KEY_EXT, 'remote', '', false)
  if reaper.GetExtState(KEY_EXT, 'running') == '1' then reaper.SetExtState(KEY_EXT, 'press', id, false); return true end
  if headless[id] then headless[id](); return true end
  K.remote = id
  return false
end
function K.remote_poll()            -- in the window's loop: a key sent by a shortcut while the window is open
  local id = reaper.GetExtState(KEY_EXT, 'press')
  if id ~= '' then reaper.SetExtState(KEY_EXT, 'press', '', false); K.remote = id end
end

-- the cream case, a darker edge bottom and right, and the brand strip with its solar cell
-- each GFX script has its own pastel case (this one pale sand)
local FACE = 0xE9DFD0
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
  if key('gfx_key', K.pick and 'PICK' or 'KEY', sx - 60, 11, 52, 32, 0x6F6F76, 0xF4F1E8, K.pick) then
    if K.key_default then K.make(K.key_default, K.key_default) else K.pick = not K.pick end
  end
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
local DW, DH = 440, 322
local status = "READY"
K.names = { set = 'SET MIDI INPUT' }
K.key_default = 'set'      -- KEY makes the set-input action at once

local function do_set()
  local n = set_input()
  status = n == 0 and 'SELECT TRACKS' or string.format('SET %d', n)
end

local function draw()
  case(DW, DH, 'MIDI INPUT', 'ALL CHANNELS')
  local x0, w0 = 16, DW - 32
  local ly, lh = 56, 114
  lcd(x0, ly, w0, lh)
  local n, midi = reaper.CountSelectedTracks(0), 0
  for i = 0, n - 1 do
    if reaper.GetMediaTrackInfo_Value(reaper.GetSelectedTrack(0, i), "I_RECINPUT") & 4096 ~= 0 then midi = midi + 1 end
  end
  lcd_text(6, x0 + 18, ly + 12, string.format('%d SELECTED', n), 14)
  lcd_text(7, x0 + 18, ly + 54, n == 0 and 'SELECT SOME TRACKS' or string.format('%d ON MIDI INPUT', midi), 26)
  gfx.setfont(8)
  text(x0 + 18, ly + 84, opt.monitor and 'MONITOR ON' or 'INPUT ONLY', 0x1C2416)
  text(x0 + w0 - 18, ly + 84, status, 0x1C2416, 2)

  local y, kh, gap = ly + lh + 16, 44, 8
  if key('set', 'SET MIDI INPUT', x0, y, w0, kh, 0xE48A2A, 0x1E1E1E) then do_set() end
  y = y + kh + 10
  local u = (w0 - gap) / 2
  if key('monitor', 'MONITOR', x0, y, u, kh, 0x6F6F76, 0xF4F1E8, opt.monitor) then opt_flip('monitor') end
  gfx.setfont(4)
  text(x0, y + kh + 12, 'KEY: a shortcut that sets the input with these settings.', mul(FACE, 0.58))
end

-- a shortcut made with KEY: each key works without the window
if K.remote_start({
  set = function()
    if set_input() == 0 then reaper.MB("Select the tracks first.", "GFX - input to all MIDI", 0) end
  end,
  monitor = function() opt_flip('monitor') end }) then return end

local _, _, sec, cmd = reaper.get_action_context()
reaper.SetExtState(SECTION, "running", "1", false)
reaper.SetToggleCommandState(sec, cmd, 1); reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(function()
  reaper.SetExtState(SECTION, "running", "0", false)
  reaper.SetToggleCommandState(sec, cmd, 0); reaper.RefreshToolbar2(sec, cmd)
end)

gfx.ext_retina = 1
gfx.init("GFX MIDI input", DW, DH, tonumber(reaper.GetExtState(SECTION, "dock")) or 0)

local function loop()
  local c = gfx.getchar()
  if c < 0 or c == 27 then   -- closed, or Esc
    reaper.SetExtState(SECTION, "dock", tostring(gfx.dock(-1)), true)
    gfx.quit()
    return
  end
  K.remote_poll()
  mouse_frame()
  draw()
  gfx.update()
  reaper.defer(loop)
end
loop()
