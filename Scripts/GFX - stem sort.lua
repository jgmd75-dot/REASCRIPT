-- @description GFX - stem sort (a folder of stems to a sorted, coloured session)
-- @author JGWizrad / Garden FX (GFX)
-- @version 1.0
-- @changelog
--   First release: a folder of stems to a sorted, coloured session (folders, tempo, pans, mutes, wet / dry,
--   tidy names, STRIP that keeps tails, silent-stem check, KEY action).
-- @about
--   Turns a folder of stems into a sorted session. Open the folder (or drop the stems or the folder on the window):
--   every stem is named by what it is and put in its own coloured folder, always in the same order - VOX (with
--   VOX FX and VOX DRY folders inside it), DRUMS, BASS, GUITARS, MUSIC, FX - then NEEDS REVIEW for anything it can't
--   name for certain (it never guesses) and REFERENCE for rough mixes, masters and instrumentals (muted). Inside each
--   folder the stems come in a fixed order too (kick, snare, toms, hats, overheads, rooms, percussion ...).
--   The list in the window shows the session before it is made: right-click a stem to move it to another folder.
--   MAKE SESSION builds it: every stem starts at bar 1, the tempo comes from the file names (or TEMPO), group prints
--   (Drum Bus, All Gtrs, Vox Print, an a cappella) come in muted at the end of their folder, L / R pairs (OH L and
--   OH R) are panned hard left and right, and when a vocal comes both wet and dry the wet one plays and the dry one
--   waits in the muted VOX DRY folder. Keys: NEW TAB (a new project tab, else the stems go below your tracks),
--   TIDY (tidy names: Song_120bpm_gtr_dbl_R_final -> Gtr Dbl R; dark = the file names as they are), PAN (L / R pairs),
--   STRIP (dark at first: cuts out the silence between parts, keeping every reverb and delay tail down to -66 dBFS;
--   gaps under 1.5 s stay, each cut gets a short fade). While the window is open it listens to every stem: a stem
--   with nothing on it (never above -70 dBFS) comes in muted, marked SILENT. KEY makes MAKE SESSION an action of its
--   own: a shortcut then asks for the folder and makes the session with the window's settings, no window needed.
--   Your stem files are only read: never moved, renamed or changed.
--   Needs nothing but REAPER (no SWS, no js extension).

local SECTION = "GFX_stem_sort"

-- =====================================================================
-- The folders, in session order, and their colours
-- =====================================================================
local GROUPS = {
  { id = 'VOX',     name = 'VOX',          col = 0xC0504D },
  { id = 'VOXFX',   name = 'VOX FX',       col = 0xD27A6E, parent = 'VOX' },
  { id = 'VOXDRY',  name = 'VOX DRY',      col = 0xA8706A, parent = 'VOX', mute = true },
  { id = 'DRUMS',   name = 'DRUMS',        col = 0xD9844A },
  { id = 'BASS',    name = 'BASS',         col = 0x8C6D4F },
  { id = 'GUITARS', name = 'GUITARS',      col = 0x6E9C45 },
  { id = 'MUSIC',   name = 'MUSIC',        col = 0x4F81BD },
  { id = 'FX',      name = 'FX',           col = 0x7B6AB0 },
  { id = 'REVIEW',  name = 'NEEDS REVIEW', col = 0x9A8A8A },
  { id = 'REF',     name = 'REFERENCE',    col = 0x5A7C8C, mute = true },
}
local GI = {}
for i, g in ipairs(GROUPS) do GI[g.id] = i; g.idx = i end

-- =====================================================================
-- Naming: words in the file name -> what the stem is.
-- Each word gives a folder, a place inside it (rank: lower comes first) and a strength: 3 = says what it is,
-- 2 = usually does, 1 = only a hint (never enough alone). Two folders tied at the top = NEEDS REVIEW.
-- =====================================================================
local WORDS = {}
local function words(grp, rank, w, list)
  for s in list:gmatch('%S+') do WORDS[s] = { grp = grp, rank = rank, w = w } end
end
-- vocals
words('VOX', 10, 3, 'vox vocal vocals voc vox1 vocs vx lv leadvox')
words('VOX', 20, 1, 'dbl double doubles doubled dub')
words('VOX', 30, 3, 'harm harms harmony harmonies hrm')
words('VOX', 40, 3, 'bv bvs bgv bgvs bgvox backing backings backs bkg bkgd bg bgs choir chorus_vox oohs aahs ooh aah gang chant chants')
words('VOX', 50, 3, 'adlib adlibs adl')
words('VOX', 60, 3, 'rap speech spoken talk')
words('VOX', 15, 1, 'lead ld main')
-- drums
words('DRUMS', 10, 3, 'kick kik kck kicks bd bassdrum')
words('DRUMS', 20, 3, 'snare snr sn sd snares')
words('DRUMS', 25, 3, 'rim rimshot xstick clap claps snap snaps')
words('DRUMS', 30, 3, 'tom toms tm hitom midtom lotom floortom rack ft')
words('DRUMS', 40, 3, 'hat hats hh hihat hihats')
words('DRUMS', 50, 3, 'oh ohs overhead overheads ovh ovhd cymbal cymbals cym crash ride china splash')
words('DRUMS', 60, 3, 'room rooms rm amb')
words('DRUMS', 70, 3, 'drum drums drm drms kit')
words('DRUMS', 75, 2, 'loop loops break breaks breakbeat toploop')
words('DRUMS', 80, 3, 'perc percs percussion shaker shakers tamb tambourine conga congas bongo bongos cowbell clave claves cabasa guiro timbale timbales triangle woodblock djembe cajon tabla')
-- bass
words('BASS', 10, 3, 'bass bs bas basses')
words('BASS', 30, 2, 'sub subs 808 808s')
words('BASS', 40, 3, 'upright contrabass')
-- guitars
words('GUITARS', 10, 3, 'acoustic acc agtr ag')
words('GUITARS', 20, 3, 'gtr gtrs guitar guitars git gtar egtr eg')
words('GUITARS', 40, 3, 'banjo mandolin mando ukulele uke dobro steel pedalsteel')
words('GUITARS', 30, 1, 'rhythm rhy strum riff amp')
-- music: keys, synths, strings, brass, the rest
words('MUSIC', 10, 3, 'keys key piano pno pianos rhodes wurli wurlitzer ep epiano clav clavinet')
words('MUSIC', 20, 3, 'organ organs b3 hammond')
words('MUSIC', 30, 3, 'synth synths syn pad pads pluck plucks arp arps lead_synth poly mono_synth')
words('MUSIC', 40, 3, 'strings string str violin violins vln vlns viola violas vla cello cellos vc orch orchestra ensemble ens')
words('MUSIC', 50, 3, 'brass horn horns hrns trumpet trumpets tpt trombone trombones tbn sax saxes saxophone tenor alto bari')
words('MUSIC', 60, 3, 'flute flutes fl clarinet clar woodwind woodwinds oboe bassoon')
words('MUSIC', 70, 3, 'harp bells bell glock glockenspiel vibes vibraphone marimba xylophone celeste celesta mellotron accordion harmonica sitar kalimba')
words('MUSIC', 80, 2, 'chord chords stab stabs')
-- effects and transitions
words('FX', 10, 3, 'fx sfx riser risers rise uplifter downlifter impact impacts sweep sweeps whoosh whooshes swoosh noise braam foley vinyl crackle zap laser siren transition transitions atmos atmosphere texture textures drone')
words('FX', 20, 2, 'reverse hit hits boom swell')

-- words that only name the folder: a more telling word in the same name sets the place inside it
local GENERIC = {}
for s in ('vox vocal vocals voc vocs vx drum drums drm drms kit bass bs bas gtr gtrs guitar guitars git gtar'):gmatch('%S+') do GENERIC[s] = true end

-- whole phrases first (each says what it is, whatever the single words say)
local PHRASES = {
  { 'bass drum', 'DRUMS', 10 }, { 'kick drum', 'DRUMS', 10 }, { 'kick in', 'DRUMS', 10 }, { 'kick out', 'DRUMS', 11 },
  { 'kick sub', 'DRUMS', 12 }, { 'sub kick', 'DRUMS', 12 }, { '808 kick', 'DRUMS', 12 }, { 'kick 808', 'DRUMS', 12 },
  { 'snare top', 'DRUMS', 20 }, { 'snare bottom', 'DRUMS', 21 }, { 'snare bot', 'DRUMS', 21 },
  { 'hi hat', 'DRUMS', 40 }, { 'high hat', 'DRUMS', 40 }, { 'floor tom', 'DRUMS', 32 }, { 'rack tom', 'DRUMS', 31 },
  { 'drum loop', 'DRUMS', 75 }, { 'top loop', 'DRUMS', 75 }, { 'perc loop', 'DRUMS', 80 },
  { 'bass gtr', 'BASS', 10 }, { 'bass guitar', 'BASS', 10 }, { 'bass di', 'BASS', 10 }, { 'bass amp', 'BASS', 11 },
  { 'synth bass', 'BASS', 20 }, { 'syn bass', 'BASS', 20 }, { 'sub bass', 'BASS', 20 }, { 'moog bass', 'BASS', 20 },
  { 'double bass', 'BASS', 40 }, { 'string bass', 'BASS', 40 }, { 'bass synth', 'BASS', 20 }, { '808 bass', 'BASS', 20 },
  { 'lead gtr', 'GUITARS', 30 }, { 'lead guitar', 'GUITARS', 30 }, { 'electric guitar', 'GUITARS', 20 },
  { 'elec gtr', 'GUITARS', 20 }, { 'ac gtr', 'GUITARS', 10 }, { 'acoustic guitar', 'GUITARS', 10 },
  { 'lead synth', 'MUSIC', 30 }, { 'synth lead', 'MUSIC', 30 }, { 'electric piano', 'MUSIC', 10 },
  { 'sub drop', 'FX', 10 }, { 'tape stop', 'FX', 10 }, { 'white noise', 'FX', 10 }, { 'reverse cymbal', 'FX', 10 },
  { 'lead vox', 'VOX', 10 }, { 'lead vocal', 'VOX', 10 }, { 'main vox', 'VOX', 10 }, { 'ld vox', 'VOX', 10 },
  { 'back vox', 'VOX', 40 }, { 'bg vox', 'VOX', 40 }, { 'ad lib', 'VOX', 50 }, { 'ad libs', 'VOX', 50 },
}

-- vocal effect returns (with a vocal word): VOX FX
local VFX = {}
for s in ('verb reverb rvb delay dly delays echo echoes throw throws fx efx plate hall slap'):gmatch('%S+') do VFX[s] = true end
-- wet / dry versions of one vocal
local WET = { wet = true, proc = true, processed = true, prc = true, mixed = true }
local DRY = { dry = true, raw = true, unprocessed = true, unproc = true, clean = true }
-- group prints (muted, last in their folder) and references (REFERENCE folder, muted)
local PRINT = {}
for s in ('print prints printed bus buss busses sum summed submix sub_mix grp group all stem_print'):gmatch('%S+') do PRINT[s] = true end
local ACAP = { acapella = true, acappella = true, acap = true, accapella = true, cappella = true }
local REF = {}
for s in ('mix mixdown rough roughmix ref reference master mastered premaster instrumental inst tvtrack tv playback demo fullmix'):gmatch('%S+') do REF[s] = true end
-- a plain group name ("Drums", "Guitars") is a print when the folder also has its parts
local PLAIN = { drums = 'DRUMS', drum = 'DRUMS', guitars = 'GUITARS', gtrs = 'GUITARS', music = 'MUSIC', fx = 'FX', keys = 'MUSIC', vocals = 'VOX', bvs = 'VOX', bgvs = 'VOX' }
-- left / right
local LEFT = { l = true, left = true, lft = true, lt = true }
local RIGHT = { r = true, right = true, rgt = true, rt = true }
-- left out of tidy names
local JUNK = {}
for s in ('final finals fnl export exported bounce bounced consolidated consol cons edit edited comp comped stereo st mono mx wav aif aiff copy new'):gmatch('%S+') do JUNK[s] = true end
-- written in capitals in tidy names
local CAPS = {}
for s in ('oh ohs bv bvs bgv bgvs bg di fx sfx hh bd sd vx lv ep l r ms b3 808 909 tr'):gmatch('%S+') do CAPS[s] = true end

local AUDIO = {}
for s in ('wav aif aiff flac mp3 ogg wv w64 caf rf64 bwf opus m4a'):gmatch('%S+') do AUDIO[s] = true end

-- split a file name into lower-case words: "BG2_finalVox-L" -> bg 2 final vox l
local function tokens(name)
  local s = name:gsub('%.[%w]+$', '')
  s = s:gsub('(%l)(%u)', '%1 %2'):gsub('(%a)(%d)', '%1 %2'):gsub('(%d)(%a)', '%1 %2')
  s = s:lower():gsub('808 s', '808s'):gsub('%f[%w]b 3%f[%W]', 'b3')
  local t = {}
  for w in s:gmatch('[%w#]+') do t[#t + 1] = w end
  -- numbers glued to letters are split above; put back the ones that name things
  local out, i = {}, 1
  while i <= #t do
    local w, n = t[i], t[i + 1]
    if n and ((w == 'tr' and (n == '808' or n == '909'))) then out[#out + 1] = w .. n; i = i + 2
    else out[#out + 1] = w; i = i + 1 end
  end
  return out
end

-- what one stem is, from its words: group id, rank inside it, and flags
local function classify(tk)
  local st = { grp = nil, rank = 99, print = false, ref = false, wet = false, dry = false, side = nil, bpm = nil }
  local line = ' ' .. table.concat(tk, ' ') .. ' '
  local score, rank, place = {}, {}, {}
  local function hit(g, r, w, generic)
    if (score[g] or 0) < w then score[g] = w end
    if not generic then place[g] = math.max(place[g] or 0, r) end
    rank[g] = math.min(rank[g] or 99, r)
  end
  -- phrases: strength 5, and they hide their own words from the single-word pass
  local masked = line
  for _, p in ipairs(PHRASES) do
    local pat = ' ' .. p[1]:gsub('%p', '%%%0') .. ' '
    if masked:find(pat) then hit(p[2], p[3], 5); masked = masked:gsub(pat, ' # ') end
  end
  local vocal, vfx = false, false
  for w in masked:gmatch('%S+') do
    local d = WORDS[w]
    if d then hit(d.grp, d.rank, d.w, GENERIC[w]); if d.grp == 'VOX' and d.w >= 3 then vocal = true end end
    if VFX[w] then vfx = true end
  end
  for _, w in ipairs(tk) do
    if WET[w] then st.wet = true end
    if DRY[w] then st.dry = true end
    if PRINT[w] then st.print = true end
    if REF[w] then st.ref = true end
    if ACAP[w] then st.grp = 'VOX'; st.print = true; st.rank = 90 end
    if LEFT[w] then st.side = 'L' elseif RIGHT[w] then st.side = 'R' end
  end
  if line:find(' lead vox ') or line:find(' lead vocal ') or line:find(' main vox ') then vocal = true end
  if st.grp then return st end
  -- the strongest folder wins; a tie at the top between two folders, or only hints, = NEEDS REVIEW
  local best, bw, tie = nil, 0, false
  for g, w in pairs(score) do
    if w > bw then best, bw, tie = g, w, false elseif w == bw and g ~= best then tie = true end
  end
  if best and tie then
    -- a drum part beats the bass hints (sub, 808); a vocal beats a guitar or music hint at the same strength
    if score.DRUMS == bw and (score.BASS or 0) == bw and rank.BASS >= 30 then best, tie = 'DRUMS', false
    elseif score.BASS == bw and (score.FX or 0) == bw then tie = true end
  end
  -- a vocal effect return: a vocal word with reverb / delay / throw ... (FX with a vocal word too)
  if vocal and vfx then st.grp = 'VOXFX'; st.rank = 10; return st end
  if st.ref and not best then st.grp = 'REF'; st.rank = 10; return st end
  if not best or tie or bw < 2 then st.grp = 'REVIEW'; st.rank = 50; return st end
  st.grp, st.rank = best, place[best] or rank[best]
  if st.ref then st.print = true end          -- "Drum Mix", "Vox Master" = a print of that folder
  return st
end

-- the leading words every file shares (a song title, a date): left out when naming and sorting
local function common_head(list)
  if #list < 3 then return 0 end
  local n = 0
  while true do
    local w = list[1].tk[n + 1]
    if not w then return n end
    for i = 2, #list do if list[i].tk[n + 1] ~= w then return n end end
    -- keep at least one word in every name
    for i = 1, #list do if #list[i].tk <= n + 1 then return n end end
    n = n + 1
  end
end

-- a tempo in the names: "120bpm" / "bpm120", or one number from 60 to 200 most files share
local function find_bpm(list)
  local votes, labelled = {}, nil
  for _, s in ipairs(list) do
    local raw = s.file:lower()
    local b = raw:match('(%d+%.?%d*)%s*bpm') or raw:match('bpm%s*[_%- ]?%s*(%d+%.?%d*)')
    if b then labelled = tonumber(b) end
    local seen = {}
    for _, w in ipairs(s.tk) do
      local v = tonumber(w)
      if v and w:match('^%d+$') and v >= 60 and v <= 200 and not seen[v] then seen[v] = true; votes[v] = (votes[v] or 0) + 1 end
    end
  end
  if labelled and labelled >= 30 and labelled <= 300 then return labelled, 'NAMES' end
  local bv, bn = nil, 0
  for v, n in pairs(votes) do if n > bn then bv, bn = v, n end end
  if bv and #list >= 3 and bn >= #list * 0.6 then return bv, 'NAMES' end
  return nil
end

local function tidy_name(s, head, bpm)
  local out = {}
  for i = head + 1, #s.tk do
    local w = s.tk[i]
    local skip = JUNK[w] or w == 'bpm' or (bpm and tonumber(w) == bpm and w:match('^%d+$'))
             or w:match('^v%d+$') or w:match('^take%d*$')
    if not skip then
      if CAPS[w] then w = w:upper() else w = w:sub(1, 1):upper() .. w:sub(2) end
      out[#out + 1] = w
    end
  end
  -- leading track numbers ("01 Kick") go; numbers that tell stems apart ("BV 2") stay
  while #out > 1 and out[1]:match('^%d+$') do table.remove(out, 1) end
  local n = table.concat(out, ' ')
  if n == '' then n = s.file:gsub('%.[%w]+$', '') end
  return n
end

-- natural order: "Tom 2" before "Tom 10"
local function natkey(s)
  return (s:lower():gsub('%d+', function(d) return string.format('%08d', tonumber(d)) end))
end

-- sort a list of files ({ path, file }) into session order; fills s.grp, s.rank, s.name, s.mute, s.pan
local function sort_stems(list, opt)
  for _, s in ipairs(list) do s.tk = tokens(s.file) end
  local head = common_head(list)
  local bpm, bpm_from = find_bpm(list)
  for _, s in ipairs(list) do
    local tk = {}
    for i = head + 1, #s.tk do tk[#tk + 1] = s.tk[i] end
    s.c = classify(tk)
    if not s.moved then s.grp = s.c.grp end
    s.rank = s.c.rank
    s.tidy = tidy_name(s, head, bpm)
    s.orig = s.file:gsub('%.[%w]+$', '')
    s.name = opt.tidy and s.tidy or s.orig
    s.mute, s.pan, s.print = false, 0, s.c.print
  end
  -- a plain "Drums" / "Guitars" is that folder's print when the folder has other stems
  local count = {}
  for _, s in ipairs(list) do count[s.grp] = (count[s.grp] or 0) + 1 end
  for _, s in ipairs(list) do
    local tk = {}
    for i = head + 1, #s.tk do if not s.tk[i]:match('^%d+$') and not JUNK[s.tk[i]] then tk[#tk + 1] = s.tk[i] end end
    if #tk == 1 and PLAIN[tk[1]] == s.grp and count[s.grp] >= 3 then s.print = true end
  end
  -- wet / dry vocals: same words once wet / dry are taken out. The dry one goes to VOX DRY.
  local function base(s, drop)
    local t = {}
    for i = head + 1, #s.tk do
      local w = s.tk[i]
      local lead_no = #t == 0 and w:match('^%d+$')                -- a track number in front ("13 Keys L")
      if not (drop[w] or WET[w] or DRY[w] or JUNK[w] or lead_no) then t[#t + 1] = w end
    end
    return table.concat(t, ' ')
  end
  local vox = {}
  for _, s in ipairs(list) do
    if (s.grp == 'VOX' or s.grp == 'VOXDRY') and not s.moved then
      local b = base(s, {})
      vox[b] = vox[b] or {}
      table.insert(vox[b], s)
    end
  end
  for _, g in pairs(vox) do
    if #g == 2 then
      local a, b = g[1], g[2]
      local dry = (a.c.dry and not b.c.dry) and a or (b.c.dry and not a.c.dry) and b
              or (b.c.wet and not a.c.wet) and a or (a.c.wet and not b.c.wet) and b
      if dry then dry.grp = 'VOXDRY' end
    end
  end
  -- L / R pairs: same words once the side is taken out; both found = panned hard
  local sides = {}
  for _, s in ipairs(list) do
    if s.c.side then
      local b = s.grp .. '|' .. base(s, { l = true, r = true, left = true, right = true, lft = true, rgt = true, lt = true, rt = true })
      sides[b] = sides[b] or {}
      sides[b][s.c.side] = s
    end
  end
  for _, p in pairs(sides) do
    if p.L and p.R then p.L.pair, p.R.pair = 'L', 'R' end
  end
  for _, s in ipairs(list) do
    s.pan = (opt.pan and s.pair == 'L') and -1 or (opt.pan and s.pair == 'R') and 1 or 0
    s.mute = s.print or s.silent or false
  end
  table.sort(list, function(a, b)
    if a.grp ~= b.grp then return GI[a.grp] < GI[b.grp] end
    local la, lb = a.print or a.silent or false, b.print or b.silent or false
    if la ~= lb then return not la end
    if a.rank ~= b.rank then return a.rank < b.rank end
    local ka, kb = natkey(a.tidy), natkey(b.tidy)
    if ka ~= kb then return ka < kb end
    return a.file < b.file
  end)
  return bpm, bpm_from
end

-- the session as rows: folders and stems with their nesting level (for the list and for building)
local function session_rows(list)
  local rows, have = {}, {}
  for _, s in ipairs(list) do have[s.grp] = true end
  for _, g in ipairs(GROUPS) do if g.parent and have[g.id] then have[g.parent] = true end end
  for _, g in ipairs(GROUPS) do
    if have[g.id] then
      local lv = g.parent and 1 or 0
      local n = 0
      for _, s in ipairs(list) do if s.grp == g.id then n = n + 1 end end
      local frow = { folder = g, level = lv, n = n }
      -- VOX FX / VOX DRY go after VOX's own stems but before its prints
      if g.parent then
        local at = #rows + 1
        while at > 1 and rows[at - 1].stem and rows[at - 1].stem.print and rows[at - 1].stem.grp == g.parent do at = at - 1 end
        local add = { frow }
        for _, s in ipairs(list) do if s.grp == g.id then add[#add + 1] = { stem = s, level = lv + 1 } end end
        for k, r in ipairs(add) do table.insert(rows, at + k - 1, r) end
      else
        rows[#rows + 1] = frow
        for _, s in ipairs(list) do if s.grp == g.id then rows[#rows + 1] = { stem = s, level = lv + 1 } end end
      end
    end
  end
  return rows
end

-- the files in a folder (and the folders inside it, two deep)
local function scan(dir, list, depth)
  list = list or {}
  local i = 0
  while true do
    local f = reaper.EnumerateFiles(dir, i)
    if not f then break end
    local ext = (f:match('%.(%w+)$') or ''):lower()
    if AUDIO[ext] and f:sub(1, 1) ~= '.' then list[#list + 1] = { path = dir .. '/' .. f, file = f } end
    i = i + 1
  end
  if (depth or 0) < 2 then
    i = 0
    while true do
      local d = reaper.EnumerateSubdirectories(dir, i)
      if not d then break end
      if d:sub(1, 1) ~= '.' and not d:lower():match('peaks') then scan(dir .. '/' .. d, list, (depth or 0) + 1) end
      i = i + 1
    end
  end
  return list
end

-- =====================================================================
-- Listening: each stem's level every 10 ms (from REAPER's peak data), for the silent-stem check and STRIP
-- =====================================================================
local ENV_RATE = 100                       -- level readings per second
local SILENT_DB = -70                      -- a stem that never reaches this is silent
local OPEN_DB, TAIL_DB = -50, -66          -- sound starts above OPEN; a tail lasts while above TAIL
local PRE, HOLD, POST, BRIDGE = 0.02, 0.6, 0.15, 1.5   -- seconds: before a start, tail hold, after a tail, gaps kept
local function dbv(db) return 10 ^ (db / 20) end

-- the parts of a stem to keep: sound and its whole tail. Gaps shorter than BRIDGE stay (no choppy cuts).
-- env = levels (1-based, one per 1 / ENV_RATE s); returns { {t0, t1}, ... } in seconds
local function keep_regions(env, len)
  local open, tail = dbv(OPEN_DB), dbv(TAIL_DB)
  local regs, cur, last = {}, nil, nil
  for i = 1, #env do
    local v = env[i]
    if cur then
      if v > tail then last = i end
      if (i - last) / ENV_RATE > HOLD and v <= open then
        cur[2] = last / ENV_RATE + POST; regs[#regs + 1] = cur; cur = nil
      end
    elseif v > open then
      cur = { math.max(0, (i - 1) / ENV_RATE - PRE), nil }; last = i
    end
  end
  if cur then cur[2] = len; regs[#regs + 1] = cur end
  local out = {}
  for _, r in ipairs(regs) do
    r[2] = math.min(r[2], len)
    local p = out[#out]
    if p and r[1] - p[2] < BRIDGE then p[2] = r[2] else out[#out + 1] = r end
  end
  return out
end

-- a stem's job: build its peaks (a little each call) then read them. Returns true when done.
local function listen_step(s)
  if s.heard then return true end
  if not s.src then
    s.src = reaper.PCM_Source_CreateFromFile(s.path)
    if not s.src then s.heard = true; return true end
    s.building = reaper.PCM_Source_BuildPeaks(s.src, 0) ~= 0
  end
  if s.building then
    if reaper.PCM_Source_BuildPeaks(s.src, 1) ~= 0 then return false end
    reaper.PCM_Source_BuildPeaks(s.src, 2); s.building = false
  end
  local len = reaper.GetMediaSourceLength(s.src)
  local nch = math.max(1, reaper.GetMediaSourceNumChannels(s.src))
  local env, peak = {}, 0
  local total = math.floor(len * ENV_RATE + 0.5)
  local chunk = 4096
  local buf = reaper.new_array(chunk * nch * 2)
  local at = 0
  while at < total do
    local n = math.min(chunk, total - at)
    buf.clear()
    local got = reaper.PCM_Source_GetPeaks(s.src, ENV_RATE, at / ENV_RATE, nch, n, 0, buf) & 0xFFFFF
    if got == 0 then break end
    local t = buf.table()
    for i = 0, got - 1 do
      local m = 0
      for c = 1, nch do
        local hi, lo = math.abs(t[i * nch + c] or 0), math.abs(t[got * nch + i * nch + c] or 0)
        if hi > m then m = hi end
        if lo > m then m = lo end
      end
      env[at + i + 1] = m
      if m > peak then peak = m end
    end
    at = at + got
  end
  reaper.PCM_Source_Destroy(s.src); s.src = nil
  s.heard, s.len = true, len
  s.silent = #env > 0 and peak < dbv(SILENT_DB)
  s.keep = (#env > 0 and not s.silent) and keep_regions(env, len) or nil
  return true
end

-- =====================================================================
-- Building the session (reads the stems; never writes to them)
-- =====================================================================
local function native(c) return reaper.ColorToNative(c >> 16 & 255, c >> 8 & 255, c & 255) | 0x1000000 end
local function lighten(c, f)
  local function ch(v) return math.floor(v + (255 - v) * f + 0.5) end
  return ch(c >> 16 & 255) << 16 | ch(c >> 8 & 255) << 8 | ch(c & 255)
end

-- STRIP: cut the item into the parts to keep (whole tails included), short fades on each cut
local function strip_item(item, start, keep, len)
  if #keep == 1 and keep[1][1] <= 0.001 and keep[1][2] >= len - 0.001 then return end
  local cuts = {}
  for _, r in ipairs(keep) do
    if r[1] > 0.001 then cuts[#cuts + 1] = r[1] end
    if r[2] < len - 0.001 then cuts[#cuts + 1] = r[2] end
  end
  local pieces, cur = { item }, item
  for _, c in ipairs(cuts) do
    local right = reaper.SplitMediaItem(cur, start + c)
    if right then pieces[#pieces + 1] = right; cur = right end
  end
  local tr = reaper.GetMediaItem_Track(item)
  for _, it in ipairs(pieces) do
    local p0 = reaper.GetMediaItemInfo_Value(it, 'D_POSITION') - start
    local mid = p0 + reaper.GetMediaItemInfo_Value(it, 'D_LENGTH') / 2
    local inside = false
    for _, r in ipairs(keep) do if mid > r[1] and mid < r[2] then inside = true end end
    if inside then
      reaper.SetMediaItemInfo_Value(it, 'D_FADEINLEN', p0 > 0.001 and 0.01 or 0)
      reaper.SetMediaItemInfo_Value(it, 'D_FADEOUTLEN', 0.05)
    else
      reaper.DeleteTrackMediaItem(tr, it)
    end
  end
end

local function build(list, opt, bpm)
  local rows = session_rows(list)
  if #rows == 0 then return 0 end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  if opt.newtab then reaper.Main_OnCommand(40859, 0) end            -- New project tab
  if bpm then
    if reaper.CountTempoTimeSigMarkers(0) > 0 then
      local _, tpos, mpos, bpos, _, num, den, lin = reaper.GetTempoTimeSigMarker(0, 0)
      reaper.SetTempoTimeSigMarker(0, 0, tpos, mpos, bpos, bpm, num, den, lin)
    else
      reaper.SetCurrentBPM(0, bpm, true)
    end
    reaper.UpdateTimeline()
  end
  local start = reaper.TimeMap2_beatsToTime(0, 0, 0)               -- bar 1
  local base = reaper.CountTracks(0)
  -- a folder that was left open by the last track of the project: close it so the stems sit at the top level
  if base > 0 then
    local last = reaper.GetTrack(0, base - 1)
    local d = reaper.GetMediaTrackInfo_Value(last, 'I_FOLDERDEPTH')
    if d > 0 then reaper.SetMediaTrackInfo_Value(last, 'I_FOLDERDEPTH', 0) end
    local lvl = 0
    for i = 0, base - 1 do lvl = lvl + reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, i), 'I_FOLDERDEPTH') end
    if lvl > 0 then reaper.SetMediaTrackInfo_Value(last, 'I_FOLDERDEPTH', reaper.GetMediaTrackInfo_Value(last, 'I_FOLDERDEPTH') - lvl) end
  end
  local made = 0
  for k, r in ipairs(rows) do
    local idx = base + k - 1
    reaper.InsertTrackAtIndex(idx, false)
    local tr = reaper.GetTrack(0, idx)
    local nxt = rows[k + 1] and rows[k + 1].level or 0
    reaper.SetMediaTrackInfo_Value(tr, 'I_FOLDERDEPTH', nxt - r.level)
    if r.folder then
      local g = r.folder
      reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', g.name, true)
      reaper.SetMediaTrackInfo_Value(tr, 'I_CUSTOMCOLOR', native(g.col))
      if g.mute then reaper.SetMediaTrackInfo_Value(tr, 'B_MUTE', 1) end
    else
      local s = r.stem
      local g = GROUPS[GI[s.grp]]
      reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', s.name, true)
      reaper.SetMediaTrackInfo_Value(tr, 'I_CUSTOMCOLOR', native(lighten(g.col, 0.25)))
      if s.mute then reaper.SetMediaTrackInfo_Value(tr, 'B_MUTE', 1) end
      if s.pan ~= 0 then reaper.SetMediaTrackInfo_Value(tr, 'D_PAN', s.pan) end
      local src = reaper.PCM_Source_CreateFromFile(s.path)
      if src then
        local item = reaper.AddMediaItemToTrack(tr)
        local take = reaper.AddTakeToMediaItem(item)
        reaper.SetMediaItemTake_Source(take, src)
        reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME', s.file, true)
        local len = reaper.GetMediaSourceLength(src)
        reaper.SetMediaItemInfo_Value(item, 'D_POSITION', start)
        reaper.SetMediaItemInfo_Value(item, 'D_LENGTH', len)
        if opt.strip and s.keep then strip_item(item, start, s.keep, len) end
        made = made + 1
      end
    end
  end
  reaper.Main_OnCommand(40047, 0)                                   -- build any missing peaks
  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock('GFX - stem sort', -1)
  return made
end

if GFX_STEMSORT_TEST then
  return { keep_regions = keep_regions, tokens = tokens, classify = classify, sort_stems = sort_stems, session_rows = session_rows, GROUPS = GROUPS }
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
  local y1 = math.floor(y + h + 0.5)
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

-- the mouse in design units, and a click = button released over the key it was pressed on
local function mouse_frame()
  K.mx, K.my = (gfx.mouse_x - K.ox) / K.s, (gfx.mouse_y - K.oy) / K.s
  K.was, K.down = K.down, (gfx.mouse_cap & 1) == 1
  K.pressed = K.down and not K.was
  K.released = K.was and not K.down
  K.rwas, K.rdown = K.rdown, (gfx.mouse_cap & 2) == 2
  K.rpressed = K.rdown and not K.rwas
  K.wheel = gfx.mouse_wheel; gfx.mouse_wheel = 0
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
  return K.released and K.held == id and hov
end

local function fonts()
  if K.fs == K.s then return end
  K.fs = K.s
  font(2, FONT, 15, true)          -- key legends
  font(3, FONT, 15, true)          -- list: stem names
  font(4, FONT, 13, true)          -- brand / small print
  font(5, FONT, 19, true)          -- title
  font(6, MONO, 34, true)          -- LCD: big
  font(7, MONO, 19, true)          -- LCD: middle
  font(8, MONO, 14, true)          -- LCD: status row
end

-- each GFX script has its own pastel case (this one pale sage)
local FACE = 0xDDE3D3
-- KEY makes this script's main job (MAKE SESSION) an action of its own (a small script in "GFX shortcuts" beside
-- this one), so a keyboard shortcut or toolbar button asks for the folder and makes the session with the window's
-- settings, without opening the window. The Action List opens on the new action: Add... under Shortcuts sets its key.
local KEY_NAME, KEY_EXT = 'GFX Stem sort', SECTION
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
  local nice = ((K.names and K.names[id]) or label):gsub('[^%w%+%- ]', '')
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
-- (headless[id]). True when nothing is left to do.
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
  if key('gfx_key', 'KEY', sx - 60, 11, 52, 32, 0x6F6F76, 0xF4F1E8) then K.make(K.key_default, K.key_default) end
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
local DW, DH = 520, 704
local function opt_get(k) return reaper.GetExtState(SECTION, k) ~= "0" end   -- all lit unless switched off
local opt = { newtab = opt_get("newtab"), tidy = opt_get("tidy"), pan = opt_get("pan"),
              strip = reaper.GetExtState(SECTION, "strip") == "1" }          -- STRIP starts dark
local stems, dir, bpm, bpm_from = {}, nil, nil, nil
local status, scroll = 'OPEN A FOLDER', 0
local heard = 0                     -- stems listened to so far (silent check, STRIP)

local function resort()
  if #stems == 0 then return end
  bpm, bpm_from = sort_stems(stems, opt)
  if K.bpm_set then bpm, bpm_from = K.bpm_set, 'TYPED' end
end

local function load(path_dir, files)
  stems = files or scan(path_dir)
  dir = path_dir
  K.bpm_set = nil
  scroll, heard = 0, 0
  if #stems == 0 then status = 'NO AUDIO FILES'; return end
  resort()
  status = 'READY'
end

local function open_folder()
  local ok, f = reaper.GetUserFileNameForRead('', 'GFX stem sort: pick any stem in the folder', '')
  if ok and f ~= '' then load(f:match('^(.*)[/\\]')) end
end

local function dropped()
  local files, folder = {}, nil
  local i = 0
  while true do
    local ok, f = gfx.getdropfile(i)
    if ok == 0 or not f then break end
    local ext = (f:match('%.(%w+)$') or ''):lower()
    if AUDIO[ext] then files[#files + 1] = { path = f, file = f:match('[^/\\]+$') }; folder = folder or f:match('^(.*)[/\\]')
    elseif reaper.EnumerateFiles(f, 0) or reaper.EnumerateSubdirectories(f, 0) then load(f) end
    i = i + 1
  end
  gfx.getdropfile(-1)
  if #files > 0 then load(folder, files) end
end

local function set_tempo()
  local ok, v = reaper.GetUserInputs('GFX stem sort', 1, 'Tempo (BPM, empty = from the names):', K.bpm_set and tostring(K.bpm_set) or '')
  if not ok then return end
  K.bpm_set = tonumber(v)
  resort()
end

-- listen a little each frame so the window stays live; all = finish now
local function listen(all)
  local t0 = reaper.time_precise()
  while heard < #stems do
    if listen_step(stems[heard + 1]) then
      heard = heard + 1
      if heard == #stems then resort() end
    end
    if not all and reaper.time_precise() - t0 > 0.03 then break end
  end
end

local function make()
  if #stems == 0 then status = 'OPEN A FOLDER'; return end
  listen(true)
  local n = build(stems, opt, bpm)
  status = string.format('MADE %d TRACKS', n)
end

local function opt_flip(k) opt[k] = not opt[k]; reaper.SetExtState(SECTION, k, opt[k] and "1" or "0", true); resort() end

local function move_menu(s)
  local items, ids = {}, {}
  for _, g in ipairs(GROUPS) do
    items[#items + 1] = (s.grp == g.id and '!' or '') .. (g.parent and '    ' or '') .. g.name
    ids[#ids + 1] = g.id
  end
  items[#items + 1] = '|' .. (s.print and '!' or '') .. 'Print (muted, last in its folder)'
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local c = gfx.showmenu(table.concat(items, '|'))
  if c >= 1 and c <= #ids then s.grp = ids[c]; s.moved = true; resort()
  elseif c == #ids + 1 then s.print = not s.print; s.c.print = s.print; resort() end
end

local function count(id) local n = 0; for _, s in ipairs(stems) do if s.grp == id then n = n + 1 end end; return n end

-- the list: the session as it will be made, folders in their colours, stems indented under them
local function list_view(x, y, w, h)
  rr(x, y, w, h, 8, 0x2A2A2C)
  rr(x + 6, y + 6, w - 12, h - 12, 3, 0xF4F3EC)
  local rows = session_rows(stems)
  local rh = 22
  local vis = math.floor((h - 16) / rh)
  local maxs = math.max(0, #rows - vis)
  if over(x, y, w, h) and K.wheel ~= 0 then scroll = scroll - (K.wheel > 0 and 3 or -3) end
  scroll = math.max(0, math.min(maxs, scroll))
  if #rows == 0 then
    gfx.setfont(3)
    text(x + w / 2, y + h / 2 - 20, 'Drop a folder of stems here,', mul(FACE, 0.5), 1)
    text(x + w / 2, y + h / 2 + 2, 'or press OPEN.', mul(FACE, 0.5), 1)
    return
  end
  for i = 1, vis do
    local r = rows[i + scroll]
    if not r then break end
    local ry = y + 8 + (i - 1) * rh
    if r.folder then
      local g = r.folder
      local ix = x + 12 + r.level * 18
      rr(ix, ry + 2, w - 24 - r.level * 18, rh - 3, 3, g.col)
      gfx.setfont(2)
      text(ix + 8, ry + 4, g.name, 0xFFFFFF)
      gfx.setfont(4)
      text(x + w - 20, ry + 5, (g.mute and 'MUTED  ' or '') .. r.n, 0xFFFFFF, 2)
    else
      local s = r.stem
      local g = GROUPS[GI[s.grp]]
      local ix = x + 12 + r.level * 18
      if over(x + 6, ry, w - 12, rh) then
        rr(x + 8, ry + 1, w - 16, rh - 1, 3, 0x000000, 0.06)
        if K.rpressed then move_menu(s) end
      end
      rr(ix - 12, ry + 6, 6, 10, 2, lighten(g.col, 0.25))
      gfx.setfont(3)
      local ink = (s.mute or g.mute) and 0x8A8A86 or 0x26262A
      text(ix, ry + 3, s.name, ink)
      local tags = {}
      if s.pair then tags[#tags + 1] = s.pan ~= 0 and (s.pair == 'L' and 'PAN L' or 'PAN R') or s.pair end
      if s.print then tags[#tags + 1] = 'PRINT' end
      if s.silent then tags[#tags + 1] = 'SILENT' end
      if s.mute or g.mute then tags[#tags + 1] = 'MUTED' end
      if s.moved then tags[#tags + 1] = 'MOVED' end
      if opt.tidy and s.name ~= s.orig then
        gfx.setfont(4)
        local nw = gfx.measurestr(s.name .. '  ') / K.s
        gfx.setfont(3); nw = gfx.measurestr(s.name .. '  ') / K.s
        gfx.setfont(4)
        local o = s.orig
        local room = w - 40 - (ix - x) - nw - 70
        while #o > 3 and gfx.measurestr(o) / K.s > room do o = o:sub(1, -2) end
        if o ~= s.orig then o = o:sub(1, -2) .. '..' end
        if room > 40 then text(ix + nw, ry + 5, o, 0x9A9A94) end
      end
      gfx.setfont(4)
      text(x + w - 20, ry + 5, table.concat(tags, ' '), 0x7A6A5A, 2)
    end
  end
  if maxs > 0 then                                               -- scroll bar
    local th = math.max(20, (h - 16) * vis / #rows)
    local ty = y + 8 + (h - 16 - th) * scroll / maxs
    rr(x + w - 11, ty, 4, th, 2, 0x000000, 0.25)
  end
end

local function draw()
  case(DW, DH, 'STEM SORT', 'STEMS TO SESSION')
  local x0, w0 = 16, DW - 32
  local ly, lh = 56, 114
  lcd(x0, ly, w0, lh)
  if #stems > 0 then
    lcd_text(6, x0 + 18, ly + 12, string.format('%d STEMS', #stems), 20)
    local nm = (dir or ''):match('([^/\\]+)$') or ''
    lcd_text(7, x0 + 18, ly + 54, nm:upper():sub(1, 32), 32)
    gfx.setfont(8)
    text(x0 + 18, ly + 84, bpm and string.format('TEMPO %g (%s)', bpm, bpm_from) or 'TEMPO AS PROJECT', 0x1C2416)
    local nr, ns = count('REVIEW'), 0
    for _, st in ipairs(stems) do if st.silent then ns = ns + 1 end end
    local right = {}
    if heard < #stems then right[1] = string.format('LISTENING %d/%d', heard, #stems)
    else
      if nr > 0 then right[#right + 1] = nr .. ' TO REVIEW' end
      if ns > 0 then right[#right + 1] = ns .. ' SILENT' end
    end
    text(x0 + w0 - 18, ly + 84, #right > 0 and table.concat(right, ', ') or status, 0x1C2416, 2)
  else
    lcd_text(6, x0 + 18, ly + 12, 'NO STEMS', 20)
    lcd_text(7, x0 + 18, ly + 54, 'DROP A FOLDER HERE', 32)
    gfx.setfont(8); text(x0 + w0 - 18, ly + 84, status, 0x1C2416, 2)
  end

  local listy, listh = ly + lh + 14, 330
  list_view(x0, listy, w0, listh)

  local y, kh, gap = listy + listh + 16, 44, 8
  local u = (w0 - gap * 3) / 4
  if key('open', 'OPEN', x0, y, u, kh, 0x6F6F76, 0xF4F1E8) then open_folder() end
  if key('tempo', 'TEMPO', x0 + u + gap, y, u, kh, 0x5B7393, 0xF4F1E8) then set_tempo() end
  if key('make', 'MAKE SESSION', x0 + (u + gap) * 2, y, u * 2 + gap, kh, 0xE48A2A, 0x1E1E1E) then make() end
  y = y + kh + 10
  local u4 = (w0 - gap * 3) / 4
  for i, k in ipairs({ { 'newtab', 'NEW TAB' }, { 'tidy', 'TIDY' }, { 'pan', 'PAN L / R' }, { 'strip', 'STRIP' } }) do
    if key(k[1], k[2], x0 + (u4 + gap) * (i - 1), y, u4, kh, 0x6F6F76, 0xF4F1E8, opt[k[1]]) then opt_flip(k[1]) end
  end
  gfx.setfont(4)
  text(x0, y + kh + 12, 'STRIP cuts out the silence, keeping every reverb tail. Right-click a', mul(FACE, 0.5))
  text(x0, y + kh + 28, 'stem to move it. Your files are only read, never changed.', mul(FACE, 0.5))
end

K.names = { make = 'MAKE SESSION' }
K.key_default = 'make'     -- KEY makes the make-session action at once (it asks for the folder)

if GFX_STEMSORT_SHOT then
  return { draw = draw, load = load, K = K, mouse_frame = mouse_frame, opt = opt, DW = DW, DH = DH,
           scroll_to = function(n) scroll = n end, set_heard = function(n) heard = n end }
end

-- a shortcut made with KEY: ask for the folder and make the session with the window's settings
if K.remote_start({
  make = function()
    local ok, f = reaper.GetUserFileNameForRead('', 'GFX stem sort: pick any stem in the folder', '')
    if not ok or f == '' then return end
    load(f:match('^(.*)[/\\]'))
    if #stems == 0 then reaper.MB('No audio files in that folder.', 'GFX - stem sort', 0); return end
    make()
  end }) then return end

local _, _, sec, cmd = reaper.get_action_context()
reaper.SetExtState(SECTION, "running", "1", false)
reaper.SetToggleCommandState(sec, cmd, 1); reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(function()
  reaper.SetExtState(SECTION, "running", "0", false)
  reaper.SetToggleCommandState(sec, cmd, 0); reaper.RefreshToolbar2(sec, cmd)
end)

gfx.ext_retina = 1
gfx.init("GFX stem sort", DW, DH, tonumber(reaper.GetExtState(SECTION, "dock")) or 0)

local function loop()
  local c = gfx.getchar()
  if c < 0 or c == 27 then   -- closed, or Esc
    reaper.SetExtState(SECTION, "dock", tostring(gfx.dock(-1)), true)
    gfx.quit()
    return
  end
  while c > 0 do
    if c == 13 then make() end
    c = gfx.getchar()
    if c < 0 then break end
  end
  dropped()
  listen(false)
  K.remote_poll()
  mouse_frame()
  draw()
  gfx.update()
  reaper.defer(loop)
end
loop()
