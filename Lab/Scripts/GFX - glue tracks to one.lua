-- @description GFX - glue tracks to one
-- @author GardenFX
-- by JGWizrad / Garden FX (GFX)
-- @version 1.1.0

local SECTION = "GFX_glue"
local LEVELS = { 0, -0.3, -1, -3, -6, -12 }

local function tracks()
  local t = {}
  for i = 0, reaper.CountTracks(0) - 1 do t[#t + 1] = reaper.GetTrack(0, i) end
  return t
end
local function sel_tracks()
  local t = {}
  for _, tr in ipairs(tracks()) do if reaper.IsTrackSelected(tr) then t[#t + 1] = tr end end
  return t
end
local function items_of(list)
  local t = {}
  for _, tr in ipairs(list) do
    for j = 0, reaper.CountTrackMediaItems(tr) - 1 do t[#t + 1] = reaper.GetTrackMediaItem(tr, j) end
  end
  return t
end
local function project_end()
  local e, i = reaper.GetProjectLength(0), 0
  while true do
    local r, isrgn, pos, rend = reaper.EnumProjectMarkers(i)
    if r == 0 then break end
    e = math.max(e, isrgn and rend or pos)
    i = i + 1
  end
  return e
end

local function glue(opt)
  local src = sel_tracks()
  if #src == 0 then return 'NO TRACKS' end
  local items = items_of(src)
  if #items == 0 then return 'NO ITEMS' end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local ts0, ts1 = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  reaper.GetSet_LoopTimeRange(true, false, 0, project_end(), false)
  reaper.Main_OnCommand(40289, 0)
  for _, it in ipairs(items) do reaper.SetMediaItemSelected(it, true) end
  if opt.norm then
    reaper.Main_OnCommand(40108, 0)
    local g = 10 ^ (opt.level / 20)
    for _, it in ipairs(items) do
      local tk = reaper.GetActiveTake(it)
      if tk and not reaper.TakeIsMIDI(tk) then
        reaper.SetMediaItemTakeInfo_Value(tk, "D_VOL", reaper.GetMediaItemTakeInfo_Value(tk, "D_VOL") * g)
      end
    end
  end
  local n = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(n, true)
  local dst = reaper.GetTrack(0, n)
  reaper.GetSetMediaTrackInfo_String(dst, "P_NAME", "GLUED", true)
  for _, it in ipairs(items) do reaper.MoveMediaItemToTrack(it, dst) end
  for _, tr in ipairs(tracks()) do reaper.SetTrackSelected(tr, tr == dst) end
  reaper.Main_OnCommand(40606, 0)
  reaper.GetSet_LoopTimeRange(true, false, ts0, ts1, false)
  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("GFX - glue tracks to one", -1)
  return 'GLUED'
end

local K = { s = 1, ox = 0, oy = 0, down = false, was = false, clicked = false, held = nil }

local function col(c, a)
  gfx.set(((c >> 16) & 255) / 255, ((c >> 8) & 255) / 255, (c & 255) / 255, a or 1)
end
local function mul(c, f)
  local r = math.min(255, math.floor(((c >> 16) & 255) * f))
  local g = math.min(255, math.floor(((c >> 8) & 255) * f))
  local b = math.min(255, math.floor((c & 255) * f))
  return (r << 16) | (g << 8) | b
end
local function X(v) return K.ox + v * K.s end
local function Y(v) return K.oy + v * K.s end
local function S(v) return v * K.s end

local function rr(x, y, w, h, r, c, a)
  col(c, a)
  x, y, w, h, r = X(x), Y(y), S(w), S(h), math.max(1, S(r))
  r = math.min(r, w / 2, h / 2)
  local yy = math.floor(y)
  local y1, y2 = math.floor(y + h + 0.5), math.floor(y + r)
  while yy < y1 do
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
local function text(x, y, s, c, align, a)
  col(c, a)
  local w = gfx.measurestr(s)
  gfx.x = X(x) - (align == 1 and w / 2 or align == 2 and w or 0); gfx.y = Y(y)
  gfx.drawstr(s)
end
local function text_h() local _, h = gfx.measurestr('Ag'); return h / K.s end

local function mouse_frame()
  K.mx, K.my = (gfx.mouse_x - K.ox) / K.s, (gfx.mouse_y - K.oy) / K.s
  K.was, K.down = K.down, (gfx.mouse_cap & 1) == 1
  K.pressed = K.down and not K.was
  K.released = K.was and not K.down
  if not K.down and not K.released then K.held = nil end
end
local function over(x, y, w, h) return K.mx >= x and K.mx < x + w and K.my >= y and K.my < y + h end

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
  if K.remote == id then K.remote = nil; return true end
  local hit = K.released and K.held == id and hov
  if hit and K.pick and id ~= 'gfx_key' then K.pick = false; K.make(id, label); return false end
  return hit
end

local function fonts()
  if K.fs == K.s then return end
  K.fs = K.s
  font(2, FONT, 15, true)
  font(4, FONT, 13, true)
  font(5, FONT, 19, true)
  font(6, MONO, 34, true)
  font(7, MONO, 19, true)
  font(8, MONO, 14, true)
end

local KEY_NAME, KEY_EXT = 'GFX Glue', SECTION
local KEY_FILE = GFX_MAIN or select(2, reaper.get_action_context())
local key_session = false
local function key_poll()
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
    .. 'if not reaper.file_exists(GFX_MAIN) then\n'
    .. '  local want = GFX_MAIN:match("([^/\\\\]+)$")\n'
    .. '  local function look(d, n)\n'
    .. '    if reaper.file_exists(d .. "/" .. want) then return d .. "/" .. want end\n'
    .. '    if n == 0 then return end\n'
    .. '    local i = 0\n'
    .. '    while true do\n'
    .. '      local s = reaper.EnumerateSubdirectories(d, i)\n'
    .. '      if not s or s == "" then return end\n'
    .. '      local p = look(d .. "/" .. s, n - 1)\n'
    .. '      if p then return p end\n'
    .. '      i = i + 1\n'
    .. '    end\n'
    .. '  end\n'
    .. '  GFX_MAIN = look(reaper.GetResourcePath() .. "/Scripts", 4) or GFX_MAIN\n'
    .. 'end\n'
    .. 'reaper.SetExtState(%q, "remote", %q, false)\ndofile(GFX_MAIN)\n', KEY_NAME, nice, KEY_FILE, KEY_EXT, id))
  f:close()
  local cmd = reaper.AddRemoveReaScript(true, 0, path, true)
  if cmd ~= 0 and reaper.PromptForAction then
    if key_session then reaper.PromptForAction(-1, 0, 0) end
    reaper.PromptForAction(1, cmd, 0); key_session = true
  else
    reaper.Main_OnCommand(40605, 0)
  end
end

function K.remote_start(headless)
  local id = reaper.GetExtState(KEY_EXT, 'remote')
  if id == '' then return false end
  reaper.SetExtState(KEY_EXT, 'remote', '', false)
  if reaper.GetExtState(KEY_EXT, 'running') == '1' then reaper.SetExtState(KEY_EXT, 'press', id, false); return true end
  if headless[id] then headless[id](); return true end
  K.remote = id
  return false
end
function K.remote_poll()
  local id = reaper.GetExtState(KEY_EXT, 'press')
  if id ~= '' then reaper.SetExtState(KEY_EXT, 'press', '', false); K.remote = id end
end

local FACE = 0xD2EBE6
local function case(DW, DH, title, sub)
  col(FACE); gfx.rect(0, 0, gfx.w, gfx.h, 1)

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

local function lcd(x, y, w, h)
  rr(x, y, w, h, 8, 0x2A2A2C)
  rr(x + 8, y + 8, w - 16, h - 16, 3, 0x9FAE8C)
end
local function lcd_text(slot, x, y, s, cells)
  gfx.setfont(slot)
  text(x, y, string.rep('8', cells), 0x1C2416, 0, 0.06)
  text(x, y, s, 0x1C2416)
end

local DW, DH = 440, 322
local opt = { norm = reaper.GetExtState(SECTION, "norm") ~= "0",
              level = tonumber(reaper.GetExtState(SECTION, "level")) or -1 }
local status = "READY"
local n_tr, n_it = 0, 0

local function count()
  local s = sel_tracks()
  return #s, #items_of(s)
end
local function lvl_txt(v) return (v == 0 and '0' or string.format('%g', v)) .. ' dB' end
local function do_glue() status = glue(opt) end
local function norm_flip() opt.norm = not opt.norm; reaper.SetExtState(SECTION, "norm", opt.norm and "1" or "0", true) end
local function level_menu()
  local m = {}
  for i, v in ipairs(LEVELS) do m[i] = (v == opt.level and '!' or '') .. lvl_txt(v) end
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local c = gfx.showmenu(table.concat(m, '|'))
  if c > 0 then opt.level = LEVELS[c]; reaper.SetExtState(SECTION, "level", tostring(opt.level), true) end
end
K.names = { glue = 'GLUE' }
K.key_default = 'glue'

local function draw()
  case(DW, DH, 'GLUE', 'TRACKS TO ONE')
  local x0, w0 = 16, DW - 32
  local ly, lh = 56, 114
  lcd(x0, ly, w0, lh)
  lcd_text(6, x0 + 18, ly + 12, n_tr == 0 and 'NO TRACKS' or string.format('%d TRACK%s', n_tr, n_tr == 1 and '' or 'S'), 14)
  lcd_text(7, x0 + 18, ly + 54, string.format('%d ITEM%s TO GLUE', n_it, n_it == 1 and '' or 'S'), 26)
  gfx.setfont(8)
  text(x0 + 18, ly + 84, opt.norm and ('NORMALISE ' .. lvl_txt(opt.level)) or 'NO NORMALISE', 0x1C2416)
  text(x0 + w0 - 18, ly + 84, status, 0x1C2416, 2)

  local y, kh, gap = ly + lh + 16, 44, 8
  if key('glue', 'GLUE', x0, y, w0, kh, 0xE48A2A, 0x1E1E1E) then do_glue() end
  y = y + kh + 10
  local u = (w0 - gap) / 2
  if key('norm', 'NORMALISE', x0, y, u, kh, 0x6F6F76, 0xF4F1E8, opt.norm) then norm_flip() end
  if key('level', 'LEVEL ' .. lvl_txt(opt.level), x0 + u + gap, y, u, kh, 0x6F6F76, 0xF4F1E8) then level_menu() end
  gfx.setfont(4)
  text(x0, y + kh + 12, 'Glues the selected tracks into one new track.', mul(FACE, 0.58))
end

if K.remote_start({ glue = function() glue(opt) end, norm = norm_flip }) then return end

local _, _, sec, cmd = reaper.get_action_context()
reaper.SetExtState(SECTION, "running", "1", false)
reaper.SetToggleCommandState(sec, cmd, 1); reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(function()
  reaper.SetExtState(SECTION, "running", "0", false)
  reaper.SetToggleCommandState(sec, cmd, 0); reaper.RefreshToolbar2(sec, cmd)
end)

gfx.ext_retina = 1
gfx.init("GFX glue", DW, DH, tonumber(reaper.GetExtState(SECTION, "dock")) or 0)

local last_state = -1
local function loop()
  local st = reaper.GetProjectStateChangeCount(0)
  if st ~= last_state then last_state = st; n_tr, n_it = count() end
  local c = gfx.getchar()
  if c < 0 or c == 27 then
    reaper.SetExtState(SECTION, "dock", tostring(gfx.dock(-1)), true)
    gfx.quit()
    return
  end
  if c == 13 then do_glue() end
  K.remote_poll()
  mouse_frame()
  draw()
  gfx.update()
  reaper.defer(loop)
end
loop()
