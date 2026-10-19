-- @description GFX CC-80 - pocket-calculator chord generator
-- @author JGWizrad / Garden FX (GFX)
-- @version 1.0
-- @about
--   An 80s pocket-calculator style chord scratchpad. Build a chord from a root (A-G, flat/sharp),
--   a quality (maj/min/dim/aug/sus4) and an extension (7/M7/m7/9/11/13), pick a duration and
--   press = to write it into the active MIDI take at the edit cursor. Voice leading keeps each
--   new chord close to the last. REST skips time. M+ stores chords, MR writes the stored
--   sequence, MC clears it. DRIFT humanises velocity and timing.
--   Requires ReaImGui (ReaPack > ReaTeam Extensions > ReaImGui).

-- =====================================================================
-- Configuration
-- =====================================================================
local SCRIPT_NAME  = 'GFX CC-80'
local EXT_SECTION  = 'GFX_CC80'
local BASE_VEL     = 100            -- note velocity before humanising
local REG_LO, REG_HI = 40, 84       -- voicing register limits (MIDI notes)
local CENTRE       = 62             -- voicings gravitate towards this pitch
local ERR_TIME     = 1.4            -- seconds an ERR message stays on the LCD

-- =====================================================================
-- Music theory
-- =====================================================================
local LETTERS   = { 'C', 'D', 'E', 'F', 'G', 'A', 'B' }
local LETTER_PC = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
local LETTER_IX = { C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6 }

local DURATIONS = {                 -- key, quarter notes, LCD name
  { key = '1/1', qn = 4,   name = 'WHOLE'   },
  { key = '1/2', qn = 2,   name = 'MINIM'   },
  { key = '1/4', qn = 1,   name = 'CROTCHET'},
  { key = '1/8', qn = 0.5, name = 'QUAVER'  },
}
local DRIFT_STEPS = { 0, 25, 50, 75, 100 }

-- Triads: { semitones, scale degree }
local TRIADS = {
  maj  = { {0,1}, {4,3}, {7,5} },
  min  = { {0,1}, {3,3}, {7,5} },
  dim  = { {0,1}, {3,3}, {6,5} },
  aug  = { {0,1}, {4,3}, {8,5} },
  sus4 = { {0,1}, {5,4}, {7,5} },
}

-- Accidental text for a semitone offset
local function acc_text(a)
  if a == 0 then return '' elseif a == 1 then return '#' elseif a == 2 then return 'x'
  elseif a == -1 then return 'b' elseif a == -2 then return 'bb' end
  return '?'
end

-- Build a chord from the input state.
-- in: { root = 'C', acc = -1/0/1, quality = nil|'maj'|..., seventh = nil|'7'|'M7'|'m7', ext = nil|9|11|13 }
-- out: chord table { pcs, name, spelling, iv } or nil, error text
local function build_chord(inp)
  if not inp.root then return nil, 'NO ROOT' end
  local q, sev, ext = inp.quality, inp.seventh, inp.ext

  -- 'm7' is the minor-seventh chord key: it implies a minor triad (or half-diminished with dim)
  if sev == 'm7' then
    if q == nil then q = 'min'
    elseif q ~= 'min' and q ~= 'dim' then return nil, 'm7 CLASH' end
  end
  local triad = q or 'maj'
  if q == 'dim' and ext then return nil, 'DIM EXT' end
  if (q == 'sus4' or q == 'aug') and ext == 11 then return nil, q:upper() .. ' 11' end

  local iv = {}
  for _, t in ipairs(TRIADS[triad]) do iv[#iv + 1] = { t[1], t[2] } end

  -- seventh: explicit key, or implied by an extension
  local s7 = nil
  if sev == '7' then
    s7 = (q == 'maj') and 11 or (q == 'dim') and 9 or 10    -- maj+7 = maj7, dim+7 = dim7
  elseif sev == 'M7' then s7 = 11
  elseif sev == 'm7' then s7 = 10
  elseif ext then s7 = (q == 'maj') and 11 or 10
  end
  if s7 then iv[#iv + 1] = { s7, 7 } end

  -- extensions (11ths drop the major 3rd to avoid the b9 clash; 13ths skip the 11th)
  if ext then
    iv[#iv + 1] = { 14, 9 }
    if ext == 11 then
      iv[#iv + 1] = { 17, 11 }
      if triad == 'maj' then table.remove(iv, 2) end
    elseif ext == 13 then
      iv[#iv + 1] = { 21, 13 }
    end
  end

  -- name
  local n = ext and tostring(ext) or '7'
  local suffix
  if not s7 then
    suffix = (triad == 'maj') and '' or (triad == 'min') and 'm' or triad
  elseif triad == 'dim' then
    suffix = (s7 == 9) and 'dim7' or (s7 == 10) and 'm7b5' or 'dim(maj7)'
  elseif s7 == 11 then
    suffix = (triad == 'maj') and ('maj' .. n) or (triad == 'min') and ('m(maj' .. n .. ')')
          or (triad == 'aug') and ('aug(maj' .. n .. ')') or ('maj' .. n .. 'sus4')
  else -- flat 7
    suffix = (triad == 'maj') and n or (triad == 'min') and ('m' .. n)
          or (triad == 'aug') and ('aug' .. n) or (n .. 'sus4')
  end
  local rootname = inp.root .. acc_text(inp.acc or 0)

  -- spelling by letter (so Cdim7 = C Eb Gb Bbb) and pitch classes
  local rpc = (LETTER_PC[inp.root] + (inp.acc or 0)) % 12
  local spelled, pcs = {}, {}
  for i, v in ipairs(iv) do
    local semi, deg = v[1], v[2]
    local letter = LETTERS[(LETTER_IX[inp.root] + (deg - 1)) % 7 + 1]
    local target = (rpc + semi) % 12
    local a = (target - LETTER_PC[letter]) % 12
    if a > 6 then a = a - 12 end
    spelled[i] = letter .. acc_text(a)
    pcs[i] = target
  end

  return { pcs = pcs, iv = iv, name = rootname .. suffix, spelling = table.concat(spelled, ' - ') }
end

-- =====================================================================
-- Voice leading: pick the inversion / octave closest to the previous voicing
-- =====================================================================
local function voicings(pcs)
  local out = {}
  local n = #pcs
  for inv = 0, n - 1 do
    for base = REG_LO, REG_LO + 30 do
      if base % 12 == pcs[inv + 1] then
        local v, p = { base }, base
        for k = 1, n - 1 do
          local pc = pcs[(inv + k) % n + 1]
          repeat p = p + 1 until p % 12 == pc
          v[#v + 1] = p
        end
        if v[#v] <= REG_HI then out[#out + 1] = { notes = v, inv = inv } end
      end
    end
  end
  return out
end

local function mean(t) local s = 0; for _, x in ipairs(t) do s = s + x end; return s / #t end

local function voice_cost(cand, prev)
  local c = 0
  -- low-register mud: close intervals below E3
  for k = 2, #cand.notes do
    if cand.notes[k - 1] < 52 and cand.notes[k] - cand.notes[k - 1] < 3 then c = c + 4 end
  end
  if not prev then
    return c + math.abs(mean(cand.notes) - CENTRE) + (cand.inv > 0 and 3 or 0)
  end
  -- bidirectional nearest-note movement: rewards common tones and small steps
  for _, a in ipairs(cand.notes) do
    local m = 99; for _, b in ipairs(prev) do m = math.min(m, math.abs(a - b)) end; c = c + m
  end
  for _, b in ipairs(prev) do
    local m = 99; for _, a in ipairs(cand.notes) do m = math.min(m, math.abs(a - b)) end; c = c + m
  end
  return c + 0.3 * math.abs(mean(cand.notes) - CENTRE)    -- gentle pull back to the centre
end

local function voice_lead(pcs, prev)
  local best, bc = nil, math.huge
  for _, cand in ipairs(voicings(pcs)) do
    local c = voice_cost(cand, prev)
    if c < bc then best, bc = cand, c end
  end
  return best and best.notes or nil
end

-- =====================================================================
-- State
-- =====================================================================
local st = {
  root = nil, acc = 0, quality = nil, seventh = nil, ext = nil,
  dur = 3,               -- index into DURATIONS (1/4)
  drift = 1,             -- index into DRIFT_STEPS
  memory = {},           -- { {root, acc, quality, seventh, ext, dur}, ... }
  prev = nil,            -- last voicing written (for voice leading)
  status = 'READY',
  err = nil, err_t = 0,
}

local function clear_input()
  st.root, st.acc, st.quality, st.seventh, st.ext = nil, 0, nil, nil, nil
end

local function flash_err(msg) st.err = msg; st.err_t = reaper.time_precise() end

local function snapshot()
  return { root = st.root, acc = st.acc, quality = st.quality, seventh = st.seventh, ext = st.ext, dur = st.dur }
end

-- =====================================================================
-- Persistence (duration, drift, memory)
-- =====================================================================
local function save_state()
  reaper.SetExtState(EXT_SECTION, 'dur', tostring(st.dur), true)
  reaper.SetExtState(EXT_SECTION, 'drift', tostring(st.drift), true)
  local lines = {}
  for _, m in ipairs(st.memory) do
    lines[#lines + 1] = table.concat({ m.root, m.acc, m.quality or '-', m.seventh or '-', m.ext or '-', m.dur }, ',')
  end
  reaper.SetExtState(EXT_SECTION, 'memory', table.concat(lines, ';'), true)
end

local function load_state()
  st.dur = tonumber(reaper.GetExtState(EXT_SECTION, 'dur')) or st.dur
  st.drift = tonumber(reaper.GetExtState(EXT_SECTION, 'drift')) or st.drift
  local mem = reaper.GetExtState(EXT_SECTION, 'memory')
  for entry in mem:gmatch('[^;]+') do
    local f = {}
    for x in entry:gmatch('[^,]+') do f[#f + 1] = x end
    if #f == 6 then
      local function opt(x) return x ~= '-' and x or nil end
      st.memory[#st.memory + 1] = { root = f[1], acc = tonumber(f[2]), quality = opt(f[3]),
        seventh = opt(f[4]), ext = tonumber(opt(f[5]) or ''), dur = tonumber(f[6]) }
    end
  end
end

-- =====================================================================
-- REAPER: find or create the MIDI take that will receive the notes
-- =====================================================================
-- Returns take, or nil + error text. t0/t1 = time range the events will occupy.
local function get_take(t0, t1)
  local take
  local me = reaper.MIDIEditor_GetActive()
  if me then take = reaper.MIDIEditor_GetTake(me) end
  if take and not reaper.ValidatePtr(take, 'MediaItem_Take*') then take = nil end

  if not take then
    local tr = reaper.GetSelectedTrack(0, 0)
    if not tr then return nil, 'NO TRACK' end
    -- reuse the latest MIDI item on that track that starts before the cursor and contains it,
    -- or ends no more than 8 quarter notes before it (so rests stay inside one item)
    local best_end, gap_t = -math.huge, reaper.TimeMap2_QNToTime(0, reaper.TimeMap2_timeToQN(0, t0) - 8)
    for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      local p = reaper.GetMediaItemInfo_Value(it, 'D_POSITION')
      local e = p + reaper.GetMediaItemInfo_Value(it, 'D_LENGTH')
      local tk = reaper.GetActiveTake(it)
      if tk and reaper.TakeIsMIDI(tk) and p <= t0 + 1e-9 and e > best_end then best_end = e; take = tk end
    end
    if take and best_end < gap_t - 1e-9 then take = nil end
    if not take then
      local it = reaper.CreateNewMIDIItemInProj(tr, t0, t1, false)
      if not it then return nil, 'NO ITEM' end
      take = reaper.GetActiveTake(it)
    end
  end
  if not take or not reaper.TakeIsMIDI(take) then return nil, 'NOT MIDI' end

  -- extend the item if the new events fall outside it (notes keep their positions)
  local it = reaper.GetMediaItemTake_Item(take)
  local p = reaper.GetMediaItemInfo_Value(it, 'D_POSITION')
  local l = reaper.GetMediaItemInfo_Value(it, 'D_LENGTH')
  if t0 < p - 1e-9 or t1 > p + l + 1e-9 then
    reaper.MIDI_SetItemExtents(it, reaper.TimeMap2_timeToQN(0, math.min(p, t0)),
                                   reaper.TimeMap2_timeToQN(0, math.max(p + l, t1)))
  end
  return take
end

-- =====================================================================
-- Insert a list of events at the edit cursor. ev = { chord = pcs|nil (rest), dur = index }
-- =====================================================================
local function insert_events(events, undo_name)
  local cur = reaper.GetCursorPosition()
  local qn0 = reaper.TimeMap2_timeToQN(0, cur)
  local total = 0
  for _, e in ipairs(events) do total = total + DURATIONS[e.dur].qn end
  local t1 = reaper.TimeMap2_QNToTime(0, qn0 + total)

  local has_notes = false
  for _, e in ipairs(events) do if e.chord then has_notes = true end end

  local take
  if has_notes then
    local err; take, err = get_take(cur, t1)
    if not take then flash_err(err); return false end
  end

  reaper.Undo_BeginBlock()
  local d = DRIFT_STEPS[st.drift] / 100
  local qn = qn0
  for _, e in ipairs(events) do
    local qe = qn + DURATIONS[e.dur].qn
    if e.chord then
      local notes = voice_lead(e.chord, st.prev)
      if notes then
        local ts, te = reaper.TimeMap2_QNToTime(0, qn), reaper.TimeMap2_QNToTime(0, qe)
        local ppq_e = reaper.MIDI_GetPPQPosFromProjTime(take, te)
        for _, pitch in ipairs(notes) do
          -- humanise: velocity up to +/-25, timing up to +/-12 ms at 100% drift
          local vel = math.floor(math.max(1, math.min(127, BASE_VEL + (math.random() * 2 - 1) * 25 * d)) + 0.5)
          local off = (math.random() * 2 - 1) * 0.012 * d
          local ppq_s = reaper.MIDI_GetPPQPosFromProjTime(take, ts + off)
          if ppq_s >= ppq_e - 1 then ppq_s = ppq_e - 2 end
          reaper.MIDI_InsertNote(take, false, false, ppq_s, ppq_e, 0, pitch, vel, true)
        end
        st.prev = notes
      end
    end
    qn = qe
  end
  if take then reaper.MIDI_Sort(take) end
  reaper.SetEditCurPos(t1, true, false)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(SCRIPT_NAME .. ': ' .. undo_name, -1)
  return true
end

-- =====================================================================
-- Key actions
-- =====================================================================
local function current_chord() return build_chord(st) end

local function press(key)
  -- roots
  if LETTER_PC[key] then
    clear_input(); st.root = key; st.status = 'READY'; return
  end
  if key == 'b' or key == '#' then
    if not st.root then flash_err('NO ROOT'); return end
    local a = (key == 'b') and -1 or 1
    st.acc = (st.acc == a) and 0 or a                -- press again to cancel
    return
  end
  -- qualities
  if TRIADS[key] then
    if not st.root then flash_err('NO ROOT'); return end
    if st.quality and st.quality ~= key then flash_err('2 QUALITIES'); return end
    st.quality = key
    local ok, e = current_chord(); if not ok then st.quality = nil; flash_err(e) end
    return
  end
  -- sevenths
  if key == '7' or key == 'M7' or key == 'm7' then
    if not st.root then flash_err('NO ROOT'); return end
    if st.seventh and st.seventh ~= key then flash_err('2 SEVENTHS'); return end
    st.seventh = key
    local ok, e = current_chord(); if not ok then st.seventh = nil; flash_err(e) end
    return
  end
  -- extensions (highest wins)
  if key == '9' or key == '11' or key == '13' then
    if not st.root then flash_err('NO ROOT'); return end
    local old = st.ext
    st.ext = tonumber(key)
    local ok, e = current_chord(); if not ok then st.ext = old; flash_err(e) end
    return
  end
  -- durations
  for i, d in ipairs(DURATIONS) do
    if key == d.key then st.dur = i; save_state(); return end
  end

  if key == 'CLEAR' then
    if not st.root then st.prev = nil; st.status = 'VOICE RESET'   -- second press resets voice leading
    else clear_input(); st.status = 'READY' end
    st.err = nil
  elseif key == 'REST' then
    if insert_events({ { chord = nil, dur = st.dur } }, 'rest') then st.status = 'REST ' .. DURATIONS[st.dur].key end
  elseif key == '=' then
    local ch, e = current_chord()
    if not ch then flash_err(e == 'NO ROOT' and 'NO CHORD' or e); return end
    if insert_events({ { chord = ch.pcs, dur = st.dur } }, ch.name) then st.status = 'INS ' .. ch.name end
  elseif key == 'M+' then
    local ch, e = current_chord()
    if not ch then flash_err(e == 'NO ROOT' and 'NO CHORD' or e); return end
    st.memory[#st.memory + 1] = snapshot(); save_state()
    st.status = 'M+ ' .. #st.memory .. ' STORED'
  elseif key == 'MR' then
    if #st.memory == 0 then flash_err('MEM EMPTY'); return end
    local evs = {}
    for _, m in ipairs(st.memory) do
      local ch = build_chord(m)
      if ch then evs[#evs + 1] = { chord = ch.pcs, dur = m.dur } end
    end
    if insert_events(evs, 'memory recall') then st.status = 'MR ' .. #evs .. ' CHORDS' end
  elseif key == 'MC' then
    st.memory = {}; save_state(); st.status = 'MEM CLEAR'
  elseif key == 'DRIFT' then
    st.drift = st.drift % #DRIFT_STEPS + 1; save_state()
    st.status = 'DRIFT ' .. DRIFT_STEPS[st.drift] .. '%'
  end
end

-- Test hook: expose the logic without opening the UI
if CC80_TEST then
  return { build_chord = build_chord, voice_lead = voice_lead, press = press, st = st,
           insert_events = insert_events, DURATIONS = DURATIONS }
end

-- =====================================================================
-- UI (ReaImGui)
-- =====================================================================
if not reaper.ImGui_GetBuiltinPath then
  reaper.MB('GFX CC-80 needs ReaImGui 0.9 or newer.\nInstall it from ReaPack: Extensions > ReaImGui.', SCRIPT_NAME, 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'

local ctx = ImGui.CreateContext(SCRIPT_NAME)
local F_BIG   = ImGui.CreateFont('monospace', 30, ImGui.FontFlags_Bold)
local F_MID   = ImGui.CreateFont('monospace', 17, ImGui.FontFlags_Bold)
local F_SMALL = ImGui.CreateFont('monospace', 13, ImGui.FontFlags_Bold)
local F_KEY   = ImGui.CreateFont('sans-serif', 15, ImGui.FontFlags_Bold)
local F_BRAND = ImGui.CreateFont('sans-serif', 12, ImGui.FontFlags_Bold)
for _, f in ipairs({ F_BIG, F_MID, F_SMALL, F_KEY, F_BRAND }) do ImGui.Attach(ctx, f) end

-- Colours (0xRRGGBBAA)
local C = {
  case      = 0xE6DECAFF, case_edge = 0xB8AE96FF, case_dark = 0x8E8570FF,
  bezel     = 0x2A2A2CFF, lcd = 0x9FAE8CFF, lcd_ink = 0x1C2416FF, lcd_ghost = 0x1C24160F,
  solar     = 0x3A2A1EFF, solar_line = 0x5A4636FF,
  brand     = 0x3B3B3FFF, brand_hi = 0xC0392BFF,
  k_root    = 0x2E2E32FF, k_root_t = 0xF4F1E8FF,
  k_func    = 0x6F6F76FF, k_func_t = 0xF4F1E8FF,
  k_mod     = 0xF1ECDDFF, k_mod_t = 0x2A2A2CFF,
  k_dur     = 0x5D7088FF, k_dur_t = 0xF4F1E8FF,
  k_clear   = 0xC8452EFF, k_eq = 0xE48A2AFF, k_eq_t = 0x1E1E1EFF,
  led       = 0xFF5A2AFF, led_off = 0x00000033, shadow = 0x00000055,
}

local function shade(col, f)        -- darken/lighten an 0xRRGGBBAA colour
  local r = math.min(255, math.floor(((col >> 24) & 255) * f))
  local g = math.min(255, math.floor(((col >> 16) & 255) * f))
  local b = math.min(255, math.floor(((col >> 8) & 255) * f))
  return (r << 24) | (g << 16) | (b << 8) | (col & 255)
end

-- One rubber key. Returns true when clicked.
local function key(dl, id, label, x, y, w, h, bg, fg, lit)
  ImGui.SetCursorScreenPos(ctx, x, y)
  local clicked = ImGui.InvisibleButton(ctx, id, w, h)
  local held, hover = ImGui.IsItemActive(ctx), ImGui.IsItemHovered(ctx)
  local dy = held and 2 or 0
  ImGui.DrawList_AddRectFilled(dl, x + 1, y + 3, x + w + 1, y + h + 3, C.shadow, 7)     -- shadow
  ImGui.DrawList_AddRectFilled(dl, x, y + dy, x + w, y + h + dy, shade(bg, 0.72), 7)   -- skirt
  ImGui.DrawList_AddRectFilled(dl, x + 2, y + dy + 1, x + w - 2, y + h + dy - 4,
                               hover and shade(bg, 1.08) or bg, 6)                     -- top
  ImGui.PushFont(ctx, F_KEY)
  local tw, th = ImGui.CalcTextSize(ctx, label)
  ImGui.DrawList_AddText(dl, x + (w - tw) / 2, y + dy + (h - 4 - th) / 2, fg, label)
  ImGui.PopFont(ctx)
  if lit ~= nil then                                                                     -- status LED
    ImGui.DrawList_AddCircleFilled(dl, x + w - 8, y + dy + 7, 3, lit and C.led or C.led_off)
  end
  return clicked
end

-- LCD text with faint "ghost" segments behind it
local function lcd_text(dl, font, x, y, text, cells)
  ImGui.PushFont(ctx, font)
  ImGui.DrawList_AddText(dl, x, y, C.lcd_ghost, string.rep('8', cells))
  ImGui.DrawList_AddText(dl, x, y, C.lcd_ink, text)
  ImGui.PopFont(ctx)
end

local function draw(dl, x0, y0, W)
  local pad = 16
  local x, w = x0 + pad, W - pad * 2
  local y = y0 + 10

  -- brand strip + solar cell
  ImGui.PushFont(ctx, F_BRAND)
  ImGui.DrawList_AddText(dl, x, y + 4, C.brand, 'GARDEN FX')
  ImGui.DrawList_AddText(dl, x, y + 20, C.brand_hi, 'CC-80')
  ImGui.DrawList_AddText(dl, x + 46, y + 20, C.brand, 'CHORD CALCULATOR')
  ImGui.PopFont(ctx)
  local sx = x + w - 112
  ImGui.DrawList_AddRectFilled(dl, sx, y, sx + 112, y + 34, C.solar, 3)
  for i = 1, 3 do ImGui.DrawList_AddLine(dl, sx + i * 28, y + 2, sx + i * 28, y + 32, C.solar_line, 1) end
  y = y + 46

  -- LCD (recessed)
  local lh = 104
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + lh, C.bezel, 8)
  ImGui.DrawList_AddRectFilled(dl, x + 8, y + 8, x + w - 8, y + lh - 8, C.lcd, 3)
  local err = st.err and (reaper.time_precise() - st.err_t) < ERR_TIME
  local ch, cerr = current_chord()
  local l1, l2
  if err then l1, l2 = 'ERR', st.err
  elseif ch then l1, l2 = ch.name, ch.spelling
  else l1, l2 = '--', '' end
  lcd_text(dl, F_BIG, x + 18, y + 12, l1, 14)
  lcd_text(dl, F_MID, x + 18, y + 48, l2, 26)
  local dur = DURATIONS[st.dur]
  local left = dur.key .. ' ' .. dur.name
  local right = err and 'ERR' or st.status
  ImGui.PushFont(ctx, F_SMALL)
  ImGui.DrawList_AddText(dl, x + 18, y + 76, C.lcd_ink, left)
  local rw = ImGui.CalcTextSize(ctx, right)
  ImGui.DrawList_AddText(dl, x + w - 18 - rw, y + 76, C.lcd_ink, right)
  local mid = (#st.memory > 0 and ('M' .. #st.memory) or '') .. (st.drift > 1 and ('  D' .. DRIFT_STEPS[st.drift]) or '')
  local mw = ImGui.CalcTextSize(ctx, mid)
  ImGui.DrawList_AddText(dl, x + w * 0.5 - mw * 0.5 + 10, y + 76, C.lcd_ink, mid)
  ImGui.PopFont(ctx)
  y = y + lh + 16

  -- keypad rows: each row shares the width evenly (span = key width in units)
  local gap, kh = 8, 42
  local rows = {
    { { 'CLEAR', C.k_clear, C.k_func_t }, { 'M+', C.k_func, C.k_func_t }, { 'MR', C.k_func, C.k_func_t },
      { 'MC', C.k_func, C.k_func_t }, { 'DRIFT', C.k_func, C.k_func_t } },
    { { '1/1', C.k_dur, C.k_dur_t }, { '1/2', C.k_dur, C.k_dur_t }, { '1/4', C.k_dur, C.k_dur_t },
      { '1/8', C.k_dur, C.k_dur_t }, { 'REST', C.k_func, C.k_func_t } },
    { { 'maj', C.k_mod, C.k_mod_t }, { 'min', C.k_mod, C.k_mod_t }, { 'dim', C.k_mod, C.k_mod_t },
      { 'aug', C.k_mod, C.k_mod_t }, { 'sus4', C.k_mod, C.k_mod_t } },
    { { '7', C.k_mod, C.k_mod_t }, { 'M7', C.k_mod, C.k_mod_t }, { 'm7', C.k_mod, C.k_mod_t },
      { '9', C.k_mod, C.k_mod_t }, { '11', C.k_mod, C.k_mod_t }, { '13', C.k_mod, C.k_mod_t } },
    { { 'C', C.k_root, C.k_root_t }, { 'D', C.k_root, C.k_root_t }, { 'E', C.k_root, C.k_root_t },
      { 'F', C.k_root, C.k_root_t }, { 'G', C.k_root, C.k_root_t }, { 'A', C.k_root, C.k_root_t },
      { 'B', C.k_root, C.k_root_t } },
    { { 'b', C.k_root, C.k_root_t }, { '#', C.k_root, C.k_root_t },
      { '=', C.k_eq, C.k_eq_t, span = 3 } },
  }
  for r, row in ipairs(rows) do
    local units = 0
    for _, k in ipairs(row) do units = units + (k.span or 1) end
    local uw = (w - gap * (units - 1)) / units
    local kx = x
    for _, k in ipairs(row) do
      local id, bg, fg = k[1], k[2], k[3]
      local kw = uw * (k.span or 1) + gap * ((k.span or 1) - 1)
      -- status LEDs on keys that hold state
      local lit = nil
      for i, d in ipairs(DURATIONS) do if id == d.key then lit = (st.dur == i) end end
      if TRIADS[id] then lit = (st.quality == id) end
      if id == '7' or id == 'M7' or id == 'm7' then lit = (st.seventh == id) end
      if id == '9' or id == '11' or id == '13' then lit = (st.ext == tonumber(id)) end
      if LETTER_PC[id] then lit = (st.root == id) end
      if id == 'b' then lit = (st.acc == -1) elseif id == '#' then lit = (st.acc == 1) end
      if id == 'DRIFT' then lit = (st.drift > 1) end
      if id == 'MR' then lit = (#st.memory > 0) end
      if key(dl, 'k' .. r .. '_' .. id, k.label or id, kx, y, kw, kh, bg, fg, lit) then press(id) end
      kx = kx + kw + gap
    end
    y = y + kh + gap
    if r == 1 or r == 2 or r == 4 then y = y + 6 end            -- breathing space between groups
  end

  -- footer
  ImGui.PushFont(ctx, F_BRAND)
  ImGui.DrawList_AddText(dl, x, y + 4, C.case_dark, 'KEYS  A-G ROOT  ENTER =  SPACE REST  BKSP CLR  1248 DUR')
  ImGui.PopFont(ctx)
  return y + 24 - y0
end

-- Keyboard shortcuts while the window has focus
local KEYS = {
  { ImGui.Key_A, 'A' }, { ImGui.Key_B, 'B' }, { ImGui.Key_C, 'C' }, { ImGui.Key_D, 'D' },
  { ImGui.Key_E, 'E' }, { ImGui.Key_F, 'F' }, { ImGui.Key_G, 'G' },
  { ImGui.Key_Enter, '=' }, { ImGui.Key_KeypadEnter, '=' }, { ImGui.Key_Space, 'REST' },
  { ImGui.Key_Backspace, 'CLEAR' }, { ImGui.Key_1, '1/1' }, { ImGui.Key_2, '1/2' },
  { ImGui.Key_4, '1/4' }, { ImGui.Key_8, '1/8' },
}

local function loop()
  ImGui.SetNextWindowSize(ctx, 420, 560, ImGui.Cond_FirstUseEver)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, C.case)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 0, 0)
  local visible, open = ImGui.Begin(ctx, SCRIPT_NAME, true, ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  ImGui.PopStyleVar(ctx)
  ImGui.PopStyleColor(ctx)
  if visible then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x0, y0 = ImGui.GetCursorScreenPos(ctx)
    local W = ImGui.GetContentRegionAvail(ctx)
    local h = draw(dl, x0, y0, math.max(320, W))
    ImGui.SetCursorScreenPos(ctx, x0, y0)
    ImGui.Dummy(ctx, math.max(320, W), h)
    if ImGui.IsWindowFocused(ctx) then
      for _, k in ipairs(KEYS) do
        if ImGui.IsKeyPressed(ctx, k[1], false) then press(k[2]) end
      end
    end
    ImGui.End(ctx)
  end
  if open then reaper.defer(loop) end
end

load_state()
math.randomseed(math.floor(reaper.time_precise() * 1000))
reaper.defer(loop)
