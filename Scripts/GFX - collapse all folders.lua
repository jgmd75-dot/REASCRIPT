-- @description GFX - collapse / expand all folders
-- @author GardenFX
-- by JGWizrad / Garden FX (GFX)
-- @version 1.0.3
-- @changelog
--   KEY, then a key: that key becomes its own action (for a shortcut), working without the window.
--   SHOW ALL switches on the mixer's "show tracks in folders" option if it is off.
--   COLLAPSE and EXPAND are now one toggle key (COLLAPSE / SHOW ALL).
--   The mixer now hides the folders' children (collapsing there had no effect).
-- @about
--   Collapses every folder in the arrange view and the mixer together, so only the folder tracks and loose tracks
--   show, then opens them all again. It opens a small window: one key (or SPACE) toggles - it reads COLLAPSE while
--   the folders are open and SHOW ALL while they are collapsed - and three keys choose what else COLLAPSE does:
--   COLOUR gives each folder its own colour from the GFX palette (in track order) and its children and their items
--   the same colour, HEIGHTS shrinks the tracks (folders a little taller than loose tracks), ZOOM fits all the
--   items in view. SHOW ALL opens every folder, shows every child (also any hidden by hand in the arrange view or
--   mixer; it switches on the mixer's own "show tracks in folders" option if it is off) and puts each track back
--   to the height it had. KEY makes the toggle an action of its own, for a shortcut such as J: it toggles with the window's settings,
--   without opening the window.
--   In the arrange view each folder keeps its own collapse button, so you can still open one by hand; in the mixer
--   the children are hidden. The LCD shows the state and counts the folders. The three keys are remembered; your
--   track selection is kept. Needs nothing but REAPER (no SWS).

local SECTION = "GFX_folders"
local FOLDER_H, TRACK_H = 40, 24   -- track heights while collapsed (pixels)
local PALETTE = { 0xC0504D, 0xD9844A, 0xD8B44A, 0x9BBB59, 0x4BACA6, 0x4F81BD, 0x7B6AB0, 0xB0609A,
                  0x8C6D4F, 0x6E8C5A, 0x5A7C8C, 0x8C5A6E }

local function tracks()
  local t = {}
  for i = 0, reaper.CountTracks(0) - 1 do t[#t + 1] = reaper.GetTrack(0, i) end
  return t
end
local function is_folder(tr) return reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1 end

-- folders in the project, and how many of them are collapsed
local function count()
  local all, shut, n = 0, 0, reaper.CountTracks(0)
  for _, tr in ipairs(tracks()) do
    if is_folder(tr) then
      all = all + 1
      if reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT") == 2 then shut = shut + 1 end
    end
  end
  return all, shut, n
end

local function zoom_to_items()
  local t0, t1 = math.huge, -math.huge
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    t0 = math.min(t0, p)
    t1 = math.max(t1, p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH"))
  end
  if t1 > t0 then
    local pad = (t1 - t0) * 0.02
    reaper.GetSet_ArrangeView2(0, true, 0, 0, math.max(0, t0 - pad), t1 + pad)
  end
  reaper.CSurf_OnScroll(0, -100000)   -- back to the top track
end

local function finish(name)
  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(name, -1)
end

local function collapse(opt)
  local all = tracks()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  -- remember each track's height for SHOW ALL (not again while still collapsed, or it would keep the small ones)
  if opt.heights and select(2, reaper.GetProjExtState(0, SECTION, "heights")) == "" then
    local saved = {}
    for _, tr in ipairs(all) do
      saved[#saved + 1] = reaper.GetTrackGUID(tr) .. "=" .. reaper.GetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE")
    end
    reaper.SetProjExtState(0, SECTION, "heights", table.concat(saved, ";"))
  end
  -- folders: next palette colour; other tracks: their nearest folder's colour (loose tracks keep theirs)
  local stack, n = {}, 0
  for _, tr in ipairs(all) do
    local fd = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    if fd == 1 then
      local c = PALETTE[n % #PALETTE + 1]
      n = n + 1
      local cn = reaper.ColorToNative(c >> 16 & 255, c >> 8 & 255, c & 255) | 0x1000000
      if opt.colour then reaper.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", cn) end
      reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT", 2)
      if opt.heights then reaper.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", FOLDER_H) end
      stack[#stack + 1] = cn
    end
    -- in the mixer a folder's children are hidden (the mixer's own folder collapse can't be set from a script)
    if reaper.GetTrackDepth(tr) > 0 then reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 0) end
    if fd ~= 1 then
      if opt.colour and stack[#stack] then reaper.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", stack[#stack]) end
      if opt.heights then reaper.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", TRACK_H) end
      if fd < 0 then for _ = 1, -fd do stack[#stack] = nil end end
    end
    if opt.colour then   -- every item on the track takes the track's colour
      local tc = reaper.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR")
      for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
        reaper.SetMediaItemInfo_Value(reaper.GetTrackMediaItem(tr, j), "I_CUSTOMCOLOR", tc)
      end
    end
  end
  finish("GFX - collapse all folders")
  if opt.zoom then zoom_to_items() end
end

-- the mixer's own "Mixer: Toggle show tracks in folders in mixer" option: while it is off no child shows there, so
-- SHOW ALL switches it on. Found by its name (once, then remembered), not by a number that could change.
local function mixer_folders_on()
  local NAME = "Mixer: Toggle show tracks in folders in mixer"
  local id = tonumber(reaper.GetExtState(SECTION, "mcp_cmd"))
  if not id or reaper.kbd_getTextFromCmd(id, 0) ~= NAME then
    id = nil
    for c = 40000, 42999 do
      if reaper.kbd_getTextFromCmd(c, 0) == NAME then id = c; break end
    end
    if not id then return end
    reaper.SetExtState(SECTION, "mcp_cmd", tostring(id), true)
  end
  if reaper.GetToggleCommandState(id) == 0 then reaper.Main_OnCommand(id, 0) end
end

local function expand(opt)
  local _, s = reaper.GetProjExtState(0, SECTION, "heights")
  local heights = {}
  for g, h in s:gmatch("([^=;]+)=([%d%.]+)") do heights[g] = tonumber(h) end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for _, tr in ipairs(tracks()) do
    if is_folder(tr) then
      reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT", 0)
    end
    reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 1)
    reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 1)
    local h = heights[reaper.GetTrackGUID(tr)]
    if h then reaper.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", h) end
  end
  reaper.SetProjExtState(0, SECTION, "heights", "")
  mixer_folders_on()
  finish("GFX - expand all folders")
  if opt.zoom then zoom_to_items() end
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
local KEY_NAME, KEY_EXT = 'GFX Folders', SECTION
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
-- each GFX script has its own pastel case (this one powder blue)
local FACE = 0xD3E3F1
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
local function opt_get(k) return reaper.GetExtState(SECTION, k) ~= "0" end   -- all three lit unless switched off
local opt = { colour = opt_get("colour"), heights = opt_get("heights"), zoom = opt_get("zoom") }
local status = "READY"
local n_all, n_shut, n_tr = 0, 0, 0

local function do_collapse()
  if n_all == 0 then status = 'NO FOLDERS'; return end
  collapse(opt); status = 'COLLAPSED'
end
local function do_expand()
  if n_all == 0 then status = 'NO FOLDERS'; return end
  expand(opt); status = 'ALL OPEN'
end

local function opt_flip(k) opt[k] = not opt[k]; reaper.SetExtState(SECTION, k, opt[k] and "1" or "0", true) end
local function toggle()
  n_all, n_shut, n_tr = count()
  if n_all > 0 and n_shut == n_all then do_expand() else do_collapse() end
end
K.names = { toggle = 'TOGGLE' }
K.key_default = 'toggle'   -- KEY makes the toggle action at once (e.g. for J)

local function draw()
  case(DW, DH, 'FOLDERS', 'COLLAPSE / SHOW ALL')
  local x0, w0 = 16, DW - 32
  local ly, lh = 56, 114
  lcd(x0, ly, w0, lh)
  lcd_text(6, x0 + 18, ly + 12, n_all == 0 and 'NO FOLDERS' or n_shut == n_all and 'COLLAPSED'
           or n_shut == 0 and 'ALL OPEN' or string.format('%d OPEN', n_all - n_shut), 14)
  lcd_text(7, x0 + 18, ly + 54, string.format('%d FOLDER%s, %d TRACKS', n_all, n_all == 1 and '' or 'S', n_tr), 26)
  gfx.setfont(8)
  local on = {}
  if opt.colour then on[#on + 1] = 'COLOUR' end
  if opt.heights then on[#on + 1] = 'HEIGHTS' end
  if opt.zoom then on[#on + 1] = 'ZOOM' end
  text(x0 + 18, ly + 84, #on > 0 and table.concat(on, ' ') or 'COLLAPSE ONLY', 0x1C2416)
  text(x0 + w0 - 18, ly + 84, status, 0x1C2416, 2)

  local y, kh, gap = ly + lh + 16, 44, 8
  local shut = n_all > 0 and n_shut == n_all
  -- one toggle key: its legend says what a press does, its light is lit while the folders are collapsed
  if key('toggle', shut and 'SHOW ALL' or 'COLLAPSE', x0, y, w0, kh, 0xE48A2A, 0x1E1E1E, shut) then toggle() end

  y = y + kh + 10
  local u = (w0 - gap * 2) / 3
  for i, k in ipairs({ { 'colour', 'COLOUR' }, { 'heights', 'HEIGHTS' }, { 'zoom', 'ZOOM' } }) do
    if key(k[1], k[2], x0 + (u + gap) * (i - 1), y, u, kh, 0x6F6F76, 0xF4F1E8, opt[k[1]]) then
      opt_flip(k[1])
    end
  end
  gfx.setfont(4)
  text(x0, y + kh + 12, 'KEY: a shortcut that toggles with these settings.', mul(FACE, 0.58))
end

-- a shortcut made with KEY: each key works without the window
if K.remote_start({ toggle = toggle, colour = function() opt_flip('colour') end,
                    heights = function() opt_flip('heights') end, zoom = function() opt_flip('zoom') end }) then return end

local _, _, sec, cmd = reaper.get_action_context()
reaper.SetExtState(SECTION, "running", "1", false)
reaper.SetToggleCommandState(sec, cmd, 1); reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(function()
  reaper.SetExtState(SECTION, "running", "0", false)
  reaper.SetToggleCommandState(sec, cmd, 0); reaper.RefreshToolbar2(sec, cmd)
end)

gfx.ext_retina = 1
gfx.init("GFX folders", DW, DH, tonumber(reaper.GetExtState(SECTION, "dock")) or 0)

local last_state = -1
local function loop()
  local st = reaper.GetProjectStateChangeCount(0)
  if st ~= last_state then last_state = st; n_all, n_shut, n_tr = count() end
  local c = gfx.getchar()
  if c < 0 or c == 27 then   -- closed, or Esc
    reaper.SetExtState(SECTION, "dock", tostring(gfx.dock(-1)), true)
    gfx.quit()
    return
  end
  if c == 32 then toggle() end
  K.remote_poll()
  mouse_frame()
  draw()
  gfx.update()
  reaper.defer(loop)
end
loop()
