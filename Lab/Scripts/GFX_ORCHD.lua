-- @description GFX ORCHD - pocket-calculator chord generator (was CC-80)
-- @author JGWizrad / Garden FX (GFX)
-- @version 1.3
-- @changelog
--   Renamed ORCHD (was CC-80). Same keys, sound and memory; the calculator says ORCHD.
--   1.2: drawn in REAPER's own window (no ReaImGui needed), resizable and dockable.
-- @about
--   An 80s pocket-calculator style chord scratchpad. Build a chord from a root (A-G, flat/sharp),
--   a quality (maj/min/dim/aug/sus4) and an extension (7/M7/m7/9/11/13), pick a duration and
--   press = to write it into the active MIDI take at the edit cursor. Voice leading keeps each
--   new chord close to the last. REST skips time. M+ stores chords, MR writes the stored
--   sequence, MC clears it. OCT- / OCT+ move the chords down or up an octave (two each way).
--   DRIFT humanises velocity and timing. Needs nothing but REAPER.

-- =====================================================================
-- Configuration
-- =====================================================================
local SCRIPT_NAME  = 'GFX ORCHD'
local EXT_SECTION  = 'GFX_CC80'            -- (kept from CC-80, so its memory and settings carry over)
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
  oct = 0,               -- octave shift of the written notes, -2 .. +2
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
  reaper.SetExtState(EXT_SECTION, 'oct', tostring(st.oct), true)
  local lines = {}
  for _, m in ipairs(st.memory) do
    lines[#lines + 1] = table.concat({ m.root, m.acc, m.quality or '-', m.seventh or '-', m.ext or '-', m.dur }, ',')
  end
  reaper.SetExtState(EXT_SECTION, 'memory', table.concat(lines, ';'), true)
end

local function load_state()
  st.dur = tonumber(reaper.GetExtState(EXT_SECTION, 'dur')) or st.dur
  st.drift = tonumber(reaper.GetExtState(EXT_SECTION, 'drift')) or st.drift
  st.oct = math.max(-2, math.min(2, tonumber(reaper.GetExtState(EXT_SECTION, 'oct')) or st.oct))
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
          -- voice leading works on the unshifted voicing; OCT- / OCT+ move the written notes
          local p = math.max(0, math.min(127, pitch + 12 * st.oct))
          reaper.MIDI_InsertNote(take, false, false, ppq_s, ppq_e, 0, p, vel, true)
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
  elseif key == 'OCT-' or key == 'OCT+' then
    st.oct = math.max(-2, math.min(2, st.oct + (key == 'OCT+' and 1 or -1))); save_state()
    st.status = 'OCTAVE ' .. string.format('%+d', st.oct)
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
local KEY_NAME, KEY_EXT = 'GFX ORCHD', EXT_SECTION
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
-- each GFX script has its own pastel case (this one mint)
local FACE = 0xCDE8D8
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
-- Panel: ORCHD's pocket calculator, drawn in REAPER's own graphics window
-- =====================================================================
local DW, DH = 440, 560

local KC = {
  root = { 0x2E2E32, 0xF4F1E8 }, func = { 0x6F6F76, 0xF4F1E8 }, mod = { 0xF1ECDD, 0x2A2A2C },
  dur = { 0x5D7088, 0xF4F1E8 }, clear = { 0xC8452E, 0xF4F1E8 }, eq = { 0xE48A2A, 0x1E1E1E },
}
local ROWS = {
  { { 'CLEAR', KC.clear }, { 'M+', KC.func }, { 'MR', KC.func }, { 'MC', KC.func }, { 'DRIFT', KC.func } },
  { { '1/1', KC.dur }, { '1/2', KC.dur }, { '1/4', KC.dur }, { '1/8', KC.dur }, { 'REST', KC.func } },
  { { 'maj', KC.mod }, { 'min', KC.mod }, { 'dim', KC.mod }, { 'aug', KC.mod }, { 'sus4', KC.mod } },
  { { '7', KC.mod }, { 'M7', KC.mod }, { 'm7', KC.mod }, { '9', KC.mod }, { '11', KC.mod }, { '13', KC.mod } },
  { { 'C', KC.root }, { 'D', KC.root }, { 'E', KC.root }, { 'F', KC.root }, { 'G', KC.root }, { 'A', KC.root },
    { 'B', KC.root } },
  { { 'b', KC.root }, { '#', KC.root }, { 'OCT-', KC.func }, { 'OCT+', KC.func }, { '=', KC.eq, span = 3 } },
}

-- the LED on a key that holds a setting (nil = no LED)
local function key_lit(id)
  for i, d in ipairs(DURATIONS) do if id == d.key then return st.dur == i end end
  if TRIADS[id] then return st.quality == id end
  if id == '7' or id == 'M7' or id == 'm7' then return st.seventh == id end
  if id == '9' or id == '11' or id == '13' then return st.ext == tonumber(id) end
  if LETTER_PC[id] then return st.root == id end
  if id == 'b' then return st.acc == -1 elseif id == '#' then return st.acc == 1 end
  if id == 'DRIFT' then return st.drift > 1 end
  if id == 'OCT-' then return st.oct < 0 elseif id == 'OCT+' then return st.oct > 0 end
  if id == 'MR' then return #st.memory > 0 end
  return nil
end

local function draw()
  case(DW, DH, 'ORCHD', 'CHORD CALCULATOR')
  local x0, w0 = 16, DW - 32

  -- LCD
  local ly, lh = 56, 114
  lcd(x0, ly, w0, lh)
  local err = st.err and (reaper.time_precise() - st.err_t) < ERR_TIME
  local ch = current_chord()
  local l1, l2
  if err then l1, l2 = 'ERR', st.err
  elseif ch then l1, l2 = ch.name, ch.spelling
  else l1, l2 = '--', '' end
  lcd_text(6, x0 + 18, ly + 12, l1, 14)
  lcd_text(7, x0 + 18, ly + 54, l2, 26)
  gfx.setfont(8)
  local dur = DURATIONS[st.dur]
  text(x0 + 18, ly + 84, dur.key .. ' ' .. dur.name, 0x1C2416)
  local mid = (#st.memory > 0 and ('M' .. #st.memory) or '') .. (st.drift > 1 and ('  D' .. DRIFT_STEPS[st.drift]) or '')
           .. (st.oct ~= 0 and string.format('  OCT%+d', st.oct) or '')
  text(x0 + w0 * 0.5 + 18, ly + 84, mid, 0x1C2416, 1)
  text(x0 + w0 - 18, ly + 84, err and 'ERR' or st.status, 0x1C2416, 2)

  -- keypad: each row shares the width evenly
  local y, kh, gap = ly + lh + 16, 44, 8
  for r, row in ipairs(ROWS) do
    local units = 0
    for _, k in ipairs(row) do units = units + (k.span or 1) end
    local u = (w0 - gap * (units - 1)) / units
    local kx = x0
    for _, k in ipairs(row) do
      local kw = u * (k.span or 1) + gap * ((k.span or 1) - 1)
      if key(k[1], k[1], kx, y, kw, kh, k[2][1], k[2][2], key_lit(k[1])) then press(k[1]) end
      kx = kx + kw + gap
    end
    y = y + kh + gap
    if r == 1 or r == 2 or r == 4 then y = y + 6 end            -- breathing space between groups
  end

  -- footer: computer keys
  gfx.setfont(4)
  text(x0, y + 4, 'KEYS   A-G ROOT   ENTER =   SPACE REST   BKSP CLEAR', mul(FACE, 0.58))
  text(x0, y + 22, '1 2 4 8 LENGTH   - + OCTAVE', mul(FACE, 0.58))
end

-- computer keys while the window has focus
local CHARS = { [13] = '=', [32] = 'REST', [8] = 'CLEAR', [49] = '1/1', [50] = '1/2', [52] = '1/4', [56] = '1/8',
                [45] = 'OCT-', [43] = 'OCT+', [61] = 'OCT+' }

local function loop()
  local c = gfx.getchar()
  if c < 0 then
    reaper.SetExtState(EXT_SECTION, 'dock', tostring(gfx.dock(-1)), true)
    gfx.quit(); return
  end
  while c > 0 do
    if c >= 97 and c <= 103 then c = c - 32 end
    if c >= 65 and c <= 71 then press(string.char(c))
    elseif CHARS[c] then press(CHARS[c]) end
    c = gfx.getchar()
  end
  K.remote_poll()
  mouse_frame()
  draw()
  gfx.update()
  reaper.defer(loop)
end

-- a shortcut made with KEY: ORCHD's keys build chords in the window, so it opens (if it isn't) and presses the key
if K.remote_start({}) then return end

load_state()
math.randomseed(math.floor(reaper.time_precise() * 1000))
reaper.SetExtState(EXT_SECTION, 'running', '1', false)
reaper.atexit(function() reaper.SetExtState(EXT_SECTION, 'running', '0', false) end)
gfx.ext_retina = 1
gfx.init(SCRIPT_NAME, DW, DH, tonumber(reaper.GetExtState(EXT_SECTION, 'dock')) or 0)
reaper.defer(loop)
