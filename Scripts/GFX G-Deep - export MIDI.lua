-- GFX G-Deep - export MIDI
-- author: JGWizrad / Garden FX (GFX)
--
-- Companion script for the GFX G-Deep 16 drum machine (JSFX).
-- JSFX plugins cannot write files, so G-Deep's EXPORT MIDI button puts its step pattern into shared memory
-- (gmem "GFX_GDeep"). This script turns that pattern into a MIDI item at the edit cursor:
--   kick 36, snare 38, clap 40, closed hat 42, open hat 46, rim 37 (channel 10); hit = velocity 100,
--   accent = 127; swing kept;
--   the pattern repeated for the BARS chosen in the plugin (1 / 2 / 4 / 8).
-- The item goes on the selected track if it holds G-Deep, else on the first track that holds G-Deep,
-- else on the selected track.
--
-- Use: Actions > Load ReaScript, pick this file, run it. Its window shows that it is listening, and what it last
-- exported (bars, hits, the track). It exports every time you press EXPORT MIDI; EXPORT AGAIN writes the last
-- pattern once more at the edit cursor. Close the window and it keeps listening in the background (its toolbar
-- button stays lit); run it again to bring the window back. STOP ends it.
-- If you pressed EXPORT MIDI before starting the script, it exports that pattern straight away.

local GMEM = "GFX_GDeep"
local SECTION = "GFX_GDeep_export"
local NOTES = { 36, 38, 40, 42, 46, 37 }
local CHAN = 9                  -- MIDI channel 10 (0-based)

reaper.gmem_attach(GMEM)

local function has_gdeep(track)
  for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
    local _, name = reaper.TrackFX_GetFXName(track, fx, "")
    if name:find("GFX G Deep 16", 1, true) or name:find("G-Deep", 1, true) then return true end
  end
  return false
end

local function target_track()
  local sel = reaper.GetSelectedTrack(0, 0)
  if sel and has_gdeep(sel) then return sel end
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if has_gdeep(tr) then return tr end
  end
  return sel
end

local last = { msg = "WAITING", bars = 0, hits = 0, track = "" }

local function export()
  local steps = math.floor(reaper.gmem_read(2) + 0.5)
  if steps ~= 16 then last.msg = "NO PATTERN YET"; return end      -- nothing written yet
  local bars = math.max(1, math.floor(reaper.gmem_read(1) + 0.5))
  local swing = reaper.gmem_read(3)                 -- fraction of a 16th that the off-beat 16ths arrive late
  local rows = math.floor(reaper.gmem_read(5) + 0.5)
  if rows < 3 or rows > 6 then rows = 3 end         -- (the first G-Deep had three rows)
  local track = target_track()
  if not track then
    last.msg = "ADD A TRACK"
    return
  end

  reaper.Undo_BeginBlock()
  local pos = reaper.GetCursorPosition()
  local qn0 = reaper.TimeMap2_timeToQN(0, pos)
  local item = reaper.CreateNewMIDIItemInProj(track, pos, reaper.TimeMap2_QNToTime(0, qn0 + bars * 4), false)
  local take = reaper.GetActiveTake(item)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "G-Deep pattern", true)

  local hits = 0
  for bar = 0, bars - 1 do
    for row = 0, rows - 1 do
      for s = 0, 15 do
        local v = math.floor(reaper.gmem_read(10 + row * 16 + s) + 0.5)
        if v > 0 then
          local q = qn0 + bar * 4 + s * 0.25 + ((s % 2 == 1) and swing * 0.25 or 0)
          local p1 = reaper.MIDI_GetPPQPosFromProjQN(take, q)
          local p2 = reaper.MIDI_GetPPQPosFromProjQN(take, q + 0.125)
          reaper.MIDI_InsertNote(take, false, false, p1, p2, CHAN, NOTES[row + 1], v == 2 and 127 or 100, true)
          hits = hits + 1
        end
      end
    end
  end
  reaper.MIDI_Sort(take)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("GFX G-Deep: export MIDI pattern", -1)
  local _, tn = reaper.GetTrackName(track)
  last.msg, last.bars, last.hits, last.track = "EXPORTED", bars, hits, tn
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
-- on the new action: Add... under Shortcuts sets its key. Press KEY again (it reads PICK) to cancel.
local KEY_NAME, KEY_EXT = 'GFX Deep 16', SECTION
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
-- each GFX script has its own pastel case (this one peach)
local FACE = 0xF5DCC8
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
  if key('gfx_key', K.pick and 'PICK' or 'KEY', sx - 60, 11, 52, 32, 0x6F6F76, 0xF4F1E8, K.pick) then K.pick = not K.pick end
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
local shown, running = false, true

local function draw()
  case(DW, DH, 'DEEP 16', 'MIDI EXPORT')
  local x0, w0 = 16, DW - 32
  local ly, lh = 56, 114
  lcd(x0, ly, w0, lh)
  if last.bars > 0 then
    lcd_text(6, x0 + 18, ly + 12, string.format('%d BAR%s', last.bars, last.bars > 1 and 'S' or ''), 14)
    local tn = last.track:upper()
    if #tn > 16 then tn = tn:sub(1, 15) .. '.' end
    lcd_text(7, x0 + 18, ly + 54, string.format('%d HITS ON %s', last.hits, tn), 26)
  else
    lcd_text(6, x0 + 18, ly + 12, 'READY', 14)
    lcd_text(7, x0 + 18, ly + 54, 'PRESS EXPORT MIDI', 26)
  end
  gfx.setfont(8)
  text(x0 + 18, ly + 84, 'LISTENING', 0x1C2416)
  text(x0 + w0 - 18, ly + 84, last.msg, 0x1C2416, 2)
  -- the listening lamp: blinks slowly while the script waits
  local on = math.floor(reaper.time_precise() * 1.5) % 2 == 0
  col(on and 0xC0392B or 0x1C2416, on and 1 or 0.15)
  gfx.circle(X(x0 + 112), Y(ly + 91), S(4), 1, 1)

  local y, kh, gap = ly + lh + 16, 44, 8
  local u = (w0 - gap) / 2
  if key('again', 'EXPORT AGAIN', x0, y, u, kh, 0xE48A2A, 0x1E1E1E) then export() end
  if key('stop', 'STOP', x0 + u + gap, y, u, kh, 0xC8452E, 0xF4F1E8) then running = false end
  gfx.setfont(4)
  text(x0, y + kh + 14, 'Close this window and it keeps listening; run the', mul(FACE, 0.58))
  text(x0, y + kh + 32, 'script again to bring it back. STOP ends it.', mul(FACE, 0.58))
end

local function open_window()
  gfx.ext_retina = 1
  gfx.init("GFX Deep 16 - export MIDI", DW, DH, tonumber(reaper.GetExtState(SECTION, "dock")) or 0)
  shown = true
end

-- a shortcut made with KEY: EXPORT AGAIN works without the window (STOP has nothing to stop)
if K.remote_start({ again = function() export() end, stop = function() end }) then return end

-- a second launch while it runs brings the window back
if reaper.GetExtState(SECTION, "running") == "1" then
  reaper.SetExtState(SECTION, "show", "1", false)
  return
end
reaper.SetExtState(SECTION, "running", "1", false)

-- background loop: export whenever the plugin flags a pending request
local _, _, sec, cmd = reaper.get_action_context()
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(function()
  if shown then reaper.SetExtState(SECTION, "dock", tostring(gfx.dock(-1)), true); gfx.quit() end
  reaper.SetExtState(SECTION, "running", "0", false)
  reaper.SetToggleCommandState(sec, cmd, 0)
  reaper.RefreshToolbar2(sec, cmd)
end)

local function loop()
  if reaper.gmem_read(4) == 1 then
    reaper.gmem_write(4, 0)
    export()
  end
  K.remote_poll()
  if reaper.GetExtState(SECTION, "show") == "1" or (K.remote and not shown) then
    reaper.SetExtState(SECTION, "show", "0", false)
    if not shown then open_window() end
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
  if running then reaper.defer(loop) end
end
open_window()
loop()
