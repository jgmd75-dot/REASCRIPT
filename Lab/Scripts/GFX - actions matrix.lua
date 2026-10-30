-- @description GFX - actions matrix
-- @author GardenFX
-- by JGWizrad / Garden FX (GFX)
-- @version 2.0
-- @about
--   One window for all your actions: eight coloured groups (TRACKS, FOLDERS, MIDI / CHORDS, NAMES, SHOW / HIDE,
--   PLACEMENT, BOUNCING, EDIT) of keys, in four models picked with the A B C D keys beside KEY: A yellow scientific, B silver
--   with a black top, C wide pocket computer (a column per group), D dark graphic calculator. It comes with the GFX track
--   tools and JG's own actions on keys; the rest are empty. Click an empty key ("+") and REAPER's Action List opens -
--   pick any action (REAPER, SWS, your custom actions or scripts) and it lands on that key, named after the action.
--   The last key of a group reads "+ ROW": filling it adds a row of empty keys (in C, to every column) and the window
--   grows to fit (up to 12 keys a group). Click a key to run it. Right-click a key to rename it, change its action,
--   clear it, move it up / down or to another column; right-click a column's name to rename the column. KEY, then any
--   key, makes that key an action of its own for a shortcut (it runs without the window). The GFX keys use each
--   tool's own window settings and need those scripts installed beside this one (ReaPack does that). A custom action
--   only works on the computer where it was made: JG's own come built in (their steps run from here, rewritten so
--   they need nothing but REAPER), and any other missing one shows dimmed. Everything is remembered.
--   Needs nothing but REAPER (no SWS; SWS actions work if you have it).

local SECTION = "GFX_actions"
local NG, MAXK, MINK = 8, 12, 4        -- columns, keys a column at most, keys a column at least
local MY_DIR = (GFX_MAIN or select(2, reaper.get_action_context())):match('^(.*)[/\\]') or ''

-- the columns: name, then the keys they start with - a GFX tool { name, script file, its ExtState section, its key id }
-- or an action { name, command ID }
local DEFAULTS = {
  { 'TRACKS', {
    { 'NEW TRACK', 'GFX - new track.lua', 'GFX_new_track', 'bottom' },
    { 'AT TOP',    'GFX - new track.lua', 'GFX_new_track', 'top' },
    { 'NEW TRACK AT 01', '_00c9ecf693c24424b2945eb4f6961bc9' } } },
  { 'FOLDERS', {
    { 'MAKE FOLDER', 'GFX - make folder.lua', 'GFX_make_folder', 'make' } } },
  { 'MIDI / CHORDS', {
    { 'MIDI INPUT', 'GFX - input to all MIDI.lua', 'GFX_input_midi', 'set' },
    { 'ORCHD',      'GFX_ORCHD.lua', '', '' } } },
  { 'NAMES', {
    { 'TIDY FX', 'GFX - tidy FX names.lua', 'GFX_tidy_names', 'tidy' } } },
  { 'SHOW / HIDE', {
    { 'FOLDERS', 'GFX - collapse all folders.lua', 'GFX_folders', 'toggle' },
    { 'SHOW ALL TRACKS',   '_04d3935480a94a28ae80b7a0de99754c' },
    { 'SHOW SEL CHILDREN', '_4a9e9d07bf304dc893e346561021ed15' },
    { 'UNCOLLAPSE ALL',    '_a39433292195444e81cbd807fe66cba3' },
    { 'ZOOM ALL',          '_3ab5ce2ff6f641698e1187290369d3a5' },
    { 'ZOOM FOLDERS',      '_19da43adac8641daaaf8a621b634c3bf' },
    { 'ZOOM MINIMAL',      '_5409a0868b3e483383fcd5daaae7f54f' } } },
  { 'PLACEMENT', {
    { 'MASTERING PLACE', '_ce77e62c025842ed83fa1107d9653913' },
    { 'SPLIT AND MUTE',  '_fcf3962a462d0d47a0cf0bb9660236c5' } } },
  { 'BOUNCING', {
    { 'RENDER CHILDREN', '_0ddd8a0ccd068e44a3a4b3e02cc85e18' },
    { 'RENDER + REMOVE', '_64a7c26d2412e441bc068528e49a347f' },
    { 'SAVE AND CLEAN',  '_f1646a0a24b424469c96c4b6e21bd3dc' } } },
  { 'EDIT', {
    { 'NEXT TRANSIENT',   '_84a30a3f9e034e9d942cce9054b39778' },
    { 'RECORD FROM END',  '_479943799ae242c78fc13f3ea6f2a170' },
    { 'AUTO SCROLL',      '_70ff512dc0d34087a499b2baa1a3a90e' },
    { 'ENV POINTS EDGES', '_3c673cf056af4400803707008dbc8126' },
    { 'VOL AT REGIONS',   '_977795d8cce5474f8c9ac00605de3750' } } },
}

-- JG's custom actions, built in: a key holding one of these IDs runs the custom action itself where it exists
-- (his REAPER), and elsewhere runs the same steps from here, in order, as one undo step where the original was one.
-- Steps are REAPER's own action IDs, or Lua below that does what the SWS / X-Raym steps did - nothing else to install.
local B = {}
local function tracks()                  -- every track, top to bottom
  local t = {}
  for i = 0, reaper.CountTracks(0) - 1 do t[#t + 1] = reaper.GetTrack(0, i) end
  return t
end
local function is_folder(tr) return reaper.GetMediaTrackInfo_Value(tr, 'I_FOLDERDEPTH') == 1 end
local function select_only(list)
  for _, tr in ipairs(tracks()) do reaper.SetTrackSelected(tr, false) end
  for _, tr in ipairs(list) do reaper.SetTrackSelected(tr, true) end
end
local function selected()
  local t = {}
  for _, tr in ipairs(tracks()) do if reaper.IsTrackSelected(tr) then t[#t + 1] = tr end end
  return t
end
local function children(parent)          -- every track inside a folder, at any depth
  local t, all = {}, tracks()
  local i = reaper.GetMediaTrackInfo_Value(parent, 'IP_TRACKNUMBER')    -- 1-based: the next track's index
  local d = reaper.GetTrackDepth(parent)
  while all[i + 1] and reaper.GetTrackDepth(all[i + 1]) > d do t[#t + 1] = all[i + 1]; i = i + 1 end
  return t
end
local function sel_items()
  local t = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do t[#t + 1] = reaper.GetSelectedMediaItem(0, i) end
  return t
end

-- track selection kept between keys (as SWS's save / restore does), by track GUID
function B.savesel()
  local g = {}
  for _, tr in ipairs(selected()) do g[#g + 1] = reaper.GetTrackGUID(tr) end
  reaper.SetExtState(SECTION, 'savesel', table.concat(g, ' '), false)
end
function B.restoresel()
  local want = {}
  for g in reaper.GetExtState(SECTION, 'savesel'):gmatch('%S+') do want[g] = true end
  for _, tr in ipairs(tracks()) do reaper.SetTrackSelected(tr, want[reaper.GetTrackGUID(tr)] == true) end
end
function B.insert_above()                -- a new track above the first selected one (at the top when none), selected
  local first = selected()[1]
  local idx = first and reaper.GetMediaTrackInfo_Value(first, 'IP_TRACKNUMBER') - 1 or 0
  reaper.InsertTrackAtIndex(idx, true)
  reaper.TrackList_AdjustWindows(false)
  select_only({ reaper.GetTrack(0, idx) })
end
function B.sel_not_folder()              -- every track that isn't a folder
  local t = {}
  for _, tr in ipairs(tracks()) do if not is_folder(tr) then t[#t + 1] = tr end end
  select_only(t)
end
function B.sel_all_parents()             -- only the folder tracks
  local t = {}
  for _, tr in ipairs(tracks()) do if is_folder(tr) then t[#t + 1] = tr end end
  select_only(t)
end
function B.sel_children_add()            -- the selected folders' children as well
  for _, p in ipairs(selected()) do
    if is_folder(p) then for _, c in ipairs(children(p)) do reaper.SetTrackSelected(c, true) end end
  end
end
function B.sel_children_only()           -- only the selected folders' children
  local t = {}
  for _, p in ipairs(selected()) do if is_folder(p) then for _, c in ipairs(children(p)) do t[#t + 1] = c end end end
  select_only(t)
end
function B.unsel_parents()
  for _, tr in ipairs(selected()) do if is_folder(tr) then reaper.SetTrackSelected(tr, false) end end
end
function B.show_all_tcp() for _, tr in ipairs(tracks()) do reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINTCP', 1) end; reaper.TrackList_AdjustWindows(false) end
function B.show_all_mcp() for _, tr in ipairs(tracks()) do reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINMIXER', 1) end; reaper.TrackList_AdjustWindows(false) end
function B.mcp_only_selected()           -- the mixer shows the selected tracks, hides the rest
  for _, tr in ipairs(tracks()) do reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINMIXER', reaper.IsTrackSelected(tr) and 1 or 0) end
  reaper.TrackList_AdjustWindows(false)
end
local function fold(state)               -- selected folders: 0 open, 1 small, 2 collapsed
  for _, tr in ipairs(selected()) do
    if is_folder(tr) then reaper.SetMediaTrackInfo_Value(tr, 'I_FOLDERCOMPACT', state) end
  end
  reaper.TrackList_AdjustWindows(false)
end
function B.uncollapse() fold(0) end
function B.fold_small() fold(1) end
function B.collapse() fold(2) end
function B.focus_arrange() reaper.SetCursorContext(1, nil) end
function B.focus_tracks() reaper.SetCursorContext(0, nil) end
function B.hzoom_items()                 -- the view spans the selected items
  local a, b
  for _, it in ipairs(sel_items()) do
    local p = reaper.GetMediaItemInfo_Value(it, 'D_POSITION')
    local e = p + reaper.GetMediaItemInfo_Value(it, 'D_LENGTH')
    a, b = math.min(a or p, p), math.max(b or e, e)
  end
  if a and b > a then reaper.GetSet_ArrangeView2(0, true, 0, 0, a, b) end
end
local EXPAND = '40723'                   -- View: Expand selected track height, minimize others
function B.vzoom_sel_tracks() reaper.Main_OnCommand(tonumber(EXPAND), 0) end
function B.vzoom_items()                 -- the tracks holding the selected items fill the view
  local keep, t, seen = selected(), {}, {}
  for _, it in ipairs(sel_items()) do
    local tr = reaper.GetMediaItem_Track(it)
    if not seen[tr] then seen[tr] = true; t[#t + 1] = tr end
  end
  if #t == 0 then return end
  select_only(t)
  reaper.Main_OnCommand(tonumber(EXPAND), 0)
  select_only(keep)
end
function B.items_track_colour()          -- selected items take their track's colour
  for _, it in ipairs(sel_items()) do
    local c = reaper.GetMediaTrackInfo_Value(reaper.GetMediaItem_Track(it), 'I_CUSTOMCOLOR')
    reaper.SetMediaItemInfo_Value(it, 'I_CUSTOMCOLOR', c)
  end
  reaper.UpdateArrange()
end
function B.regions_from_items()          -- a region over each selected item, named after its take
  for _, it in ipairs(sel_items()) do
    local p = reaper.GetMediaItemInfo_Value(it, 'D_POSITION')
    local tk = reaper.GetActiveTake(it)
    local name = tk and reaper.GetTakeName(tk) or ''
    reaper.AddProjectMarker(0, true, p, p + reaper.GetMediaItemInfo_Value(it, 'D_LENGTH'), name, -1)
  end
end
function B.unset_repeat() reaper.GetSetRepeat(0) end
function B.marker_at_play()              -- a marker at the play position (the edit cursor when stopped)
  local pos = (reaper.GetPlayState() & 1 == 1) and reaper.GetPlayPosition() or reaper.GetCursorPosition()
  reaper.AddProjectMarker(0, false, pos, 0, '', -1)
end
function B.scroll_play_50()              -- scroll so the play position sits in the middle of the view
  local a, b = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  local pos = (reaper.GetPlayState() & 1 == 1) and reaper.GetPlayPosition() or reaper.GetCursorPosition()
  local h = (b - a) / 2
  if pos - h < 0 then reaper.GetSet_ArrangeView2(0, true, 0, 0, 0, b - a)
  else reaper.GetSet_ArrangeView2(0, true, 0, 0, pos - h, pos + h) end
end
-- REAPER's own render-to-stem action, found by its name (its number differs between versions)
local stem_cmd
function B.render_stereo_stems()
  if not stem_cmd and reaper.kbd_enumerateActions then
    local sec = reaper.SectionFromUniqueID(0)
    local i = 0
    while true do
      local c, name = reaper.kbd_enumerateActions(sec, i)
      if not c or c <= 0 then break end
      if name == 'Track: Render tracks to stereo stem tracks (and mute originals)' then stem_cmd = c; break end
      i = i + 1
    end
  end
  if stem_cmd then reaper.Main_OnCommand(stem_cmd, 0); return true end
  return false, 'NEEDS NEWER REAPER'
end
-- envelopes the X-Raym steps work on: the selected one, or every shown and armed one on the selected tracks
local function envelopes()
  local e = reaper.GetSelectedEnvelope(0)
  if e then return { e } end
  local t = {}
  for _, tr in ipairs(selected()) do
    for j = 0, reaper.CountTrackEnvelopes(tr) - 1 do
      local env = reaper.GetTrackEnvelope(tr, j)
      local _, ch = reaper.GetEnvelopeStateChunk(env, '', false)
      if ch:match('\nVIS 1') and ch:match('\nARM 1') then t[#t + 1] = env end
    end
  end
  return t
end
function B.points_edges()                -- a point before and after each selected point, at the envelope's value there
  local d = reaper.GetExtState(SECTION, 'edges')
  if d == '' then d = '1,1' end
  local ok, v = reaper.GetUserInputs('Set points times', 2, 'Time before (s),Time after (s)', d)
  if not ok then return true end
  local pre, post = v:match('([^,]+),([^,]+)')
  pre, post = math.abs(tonumber(pre) or 1), math.abs(tonumber(post) or 1)
  reaper.SetExtState(SECTION, 'edges', pre .. ',' .. post, true)
  for _, env in ipairs(envelopes()) do
    local add = {}
    for k = 0, reaper.CountEnvelopePoints(env) - 1 do
      local _, pos, _, _, _, sel = reaper.GetEnvelopePoint(env, k)
      if sel then
        if pre ~= 0 and pos - pre ~= 0 then
          local _, val = reaper.Envelope_Evaluate(env, pos - pre, 0, 0); add[#add + 1] = { pos - pre, val }
        end
        if post ~= 0 then
          local _, val = reaper.Envelope_Evaluate(env, pos + post, 0, 0); add[#add + 1] = { pos + post, val }
        end
        reaper.SetEnvelopePoint(env, k, nil, nil, nil, nil, false, true)
      end
    end
    for _, p in ipairs(add) do reaper.InsertEnvelopePoint(env, p[1], p[2], 0, 0, true, true) end
    reaper.Envelope_SortPoints(env)
  end
  reaper.UpdateArrange()
  return true
end
function B.points_regions()              -- points at every region's start and end (selected), the rest unselected
  for _, env in ipairs(envelopes()) do
    for k = 0, reaper.CountEnvelopePoints(env) - 1 do reaper.SetEnvelopePoint(env, k, nil, nil, nil, nil, false, true) end
    local add, i = {}, 0
    while true do
      local r, isrgn, a, b = reaper.EnumProjectMarkers2(0, i)
      if r == 0 then break end
      if isrgn then
        local _, va = reaper.Envelope_Evaluate(env, a, 0, 0); add[#add + 1] = { a, va }
        local _, vb = reaper.Envelope_Evaluate(env, b, 0, 0); add[#add + 1] = { b, vb }
      end
      i = i + 1
    end
    for _, p in ipairs(add) do reaper.InsertEnvelopePoint(env, p[1], p[2], 0, 0, true, true) end
    reaper.Envelope_SortPoints(env)
  end
  reaper.UpdateArrange()
end

-- each: { name, one undo step?, steps }
local BUILTIN = {
  _00c9ecf693c24424b2945eb4f6961bc9 = { 'NEW TRACK AT 01', true, { '40296', B.insert_above, '40939' } },
  _04d3935480a94a28ae80b7a0de99754c = { 'SHOW ALL TRACKS', true,
    { B.sel_not_folder, B.show_all_tcp, B.show_all_mcp, '40199', '40112', '1011', B.restoresel } },
  _4a9e9d07bf304dc893e346561021ed15 = { 'SHOW CHILDREN OF ONLY SELECTED TRACK', true,
    { B.savesel, B.sel_children_add, '7', '40745', B.mcp_only_selected, B.restoresel } },
  _a39433292195444e81cbd807fe66cba3 = { 'UNCOLLAPSE ALL TRACKS', true,
    { B.savesel, B.sel_all_parents, B.uncollapse, '40727', '40295', '40112', '40939', B.restoresel } },
  _3ab5ce2ff6f641698e1187290369d3a5 = { 'ZOOM ALL Z LOGICALLY', true,
    { B.savesel, B.focus_arrange, '40182', B.hzoom_items, B.vzoom_items, B.restoresel, B.focus_tracks, '40285', '40289' } },
  _19da43adac8641daaaf8a621b634c3bf = { 'Zoom to Folders or Items Logically and Toggle TCP L/R', true,
    { B.savesel, B.sel_all_parents, B.vzoom_sel_tracks, '40939', B.focus_arrange, '42373', '40389', '40182',
      B.items_track_colour, B.hzoom_items, B.vzoom_items, B.restoresel, '40289' } },
  _5409a0868b3e483383fcd5daaae7f54f = { 'ZOOM TO MINIMAL STATE', true,
    { B.savesel, '40727', B.sel_all_parents, B.fold_small, B.collapse, '40295', B.restoresel } },
  _ce77e62c025842ed83fa1107d9653913 = { 'MASTER ITEM PLACEMENT', true,
    { B.regions_from_items, '40290', '40319', '40285', '40421', '41205', B.regions_from_items } },
  _fcf3962a462d0d47a0cf0bb9660236c5 = { 'JG SPLIT AND MUTE', false, { '40061', '40183' } },
  _0ddd8a0ccd068e44a3a4b3e02cc85e18 = { 'JG Render All Children', true,
    { B.sel_children_only, B.savesel, '40635', B.render_stereo_stems, '40718', '40760', B.restoresel, '40005' } },
  _64a7c26d2412e441bc068528e49a347f = { 'Render and Remove', true,
    { B.savesel, B.render_stereo_stems, B.restoresel, '40005' } },
  _f1646a0a24b424469c96c4b6e21bd3dc = { 'SAVE AND CLEAN', true,
    { B.savesel, '41895', '40098', B.restoresel, B.focus_tracks } },
  _84a30a3f9e034e9d942cce9054b39778 = { 'NEXT TRANSIENT STRETCH MARKER', true, { '40375', '41842' } },
  _479943799ae242c78fc13f3ea6f2a170 = { 'RECORD FROM END OF PROJECT (2)', true,
    { '40043', B.marker_at_play, '40020', B.unset_repeat, B.unsel_parents, '1013' } },
  _70ff512dc0d34087a499b2baa1a3a90e = { 'TOGGLE AUTO SCROLL', true,
    { B.focus_arrange, '40434', B.scroll_play_50, '41817' } },
  _3c673cf056af4400803707008dbc8126 = { 'ADD POINTS BEFORE AND AFTER AND UNSELECT', true,
    { B.points_edges, '40332', '40331', '40020', B.unset_repeat } },
  _977795d8cce5474f8c9ac00605de3750 = { 'ADD VOLUME POINTS AT REGIONS', true,
    { '41866', B.points_regions, B.points_edges, '40331', '40723', '40401', '40891' } },
}

-- each column's colour: yellow, red, blue, green, then a cycle of pastels
local GCOL = { 0xE8C13A, 0xD7443A, 0x3F6FC0, 0x3FA08E }
local PASTEL = { 0xF2B8A6, 0xB9D9A6, 0xB6C8EE, 0xE4C2E6, 0xF4DE9E, 0xA8DCD8 }
local function gcol(g) return GCOL[g] or PASTEL[(g - #GCOL - 1) % #PASTEL + 1] end
local function ink(c)                  -- dark or light legend for a key colour
  local l = 0.3 * ((c >> 16) & 255) + 0.59 * ((c >> 8) & 255) + 0.11 * (c & 255)
  return l > 150 and 0x1E1E1E or 0xF6F4EE
end

-- a key: { kind = 'gfx', file, ext, id, name } or { kind = 'act', cmd = '40296' or '_SWS_SAVESEL', name }
-- keys[g][i], i = 1 .. MAXK, holes allowed; gname[g] = the column's name
local keys, gname = {}, {}
local function enc(s)
  if not s then return '' end
  if s.kind == 'gfx' then return table.concat({ 'gfx', s.file, s.ext, s.id, s.name }, '\t') end
  return table.concat({ 'act', s.cmd, s.name }, '\t')
end
local function dec(v)
  local f = {}
  for p in (v .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = p end
  if f[1] == 'gfx' and #f >= 5 then return { kind = 'gfx', file = f[2], ext = f[3], id = f[4], name = f[5] } end
  if f[1] == 'act' and #f >= 3 then return { kind = 'act', cmd = f[2], name = f[3] } end
end
local function save(g, i) reaper.SetExtState(SECTION, 'g' .. g .. 's' .. i, enc(keys[g][i]), true) end
local function load()
  if reaper.GetExtState(SECTION, 'init2') ~= '1' then   -- first run: the columns as they come
    for g, d in ipairs(DEFAULTS) do
      reaper.SetExtState(SECTION, 'g' .. g .. 'name', d[1], true)
      keys[g] = {}
      for i = 1, MAXK do
        local k = d[2][i]
        if k and k[3] then keys[g][i] = { kind = 'gfx', name = k[1], file = k[2], ext = k[3], id = k[4] }
        elseif k then keys[g][i] = { kind = 'act', name = k[1], cmd = k[2] } end
        save(g, i)
      end
    end
    reaper.SetExtState(SECTION, 'init2', '1', true)
  end
  for g = 1, NG do
    gname[g] = reaper.GetExtState(SECTION, 'g' .. g .. 'name')
    if gname[g] == '' then gname[g] = DEFAULTS[g][1] end
    keys[g] = {}
    for i = 1, MAXK do keys[g][i] = dec(reaper.GetExtState(SECTION, 'g' .. g .. 's' .. i)) end
  end
end

-- keys a column shows: one more than the lowest filled key in any column (that spare one reads "+ ROW"), 4 .. 12
local function rows()
  local n = 0
  for g = 1, NG do for i = 1, MAXK do if keys[g][i] then n = math.max(n, i) end end end
  return math.max(MINK, math.min(MAXK, n + 1))
end
local function count()
  local n = 0
  for g = 1, NG do for i = 1, MAXK do if keys[g][i] then n = n + 1 end end end
  return n
end

-- where a GFX tool lives: beside this script, or where ReaPack put the GFX scripts, or anywhere under Scripts
local found = {}
local function find_script(file)
  if found[file] ~= nil then return found[file] or nil end
  local scripts = reaper.GetResourcePath() .. '/Scripts'
  local try = { reaper.GetExtState(SECTION, 'gfx_dir'), MY_DIR, scripts .. '/GFX/Scripts', scripts }
  local function look(dir, depth)            -- a few folders deep, no further
    if reaper.file_exists(dir .. '/' .. file) then return dir .. '/' .. file end
    if depth == 0 then return end
    local i = 0
    while true do
      local sub = reaper.EnumerateSubdirectories(dir, i)
      if not sub or sub == '' then return end
      local p = look(dir .. '/' .. sub, depth - 1)
      if p then return p end
      i = i + 1
    end
  end
  local p
  for _, d in ipairs(try) do
    if d ~= '' and reaper.file_exists(d .. '/' .. file) then p = d .. '/' .. file; break end
  end
  p = p or look(scripts, 3)
  -- Windows: one kind of slash, so REAPER knows the script it already has (no second copy in the Action List)
  if p and reaper.GetOS():match('^Win') then p = p:gsub('/', '\\') end
  found[file] = p or false
  return p
end

-- the command a key runs (0 = missing)
local K_SHIFT = false
local function command_of(s)
  if s.kind == 'act' then
    local c = tonumber(s.cmd) or reaper.NamedCommandLookup(s.cmd)
    if (not c or c == 0 or K_SHIFT) and BUILTIN[s.cmd] then return -1 end   -- -1: run the built-in steps (Shift: always)
    return c
  end
  local path = find_script(s.file)
  if not path then return 0 end
  return reaper.AddRemoveReaScript(true, 0, path, true)   -- already in the Action List: just its number
end
local function missing(s)               -- looked up once per key (file checks are slow for a whole grid)
  if s.miss == nil then
    local c = command_of(s)
    s.miss = not c or c == 0
  end
  return s.miss
end

-- a GFX tool that can't be found: ask once where the GFX scripts are, and remember that folder
local function locate(file)
  if reaper.MB("Can't find the GFX script \"" .. file .. "\".\n\nShow me where your GFX scripts are?",
               'GFX actions', 4) ~= 6 then return false end
  local ok, path = reaper.GetUserFileNameForRead(reaper.GetResourcePath() .. '/Scripts/', 'Pick ' .. file, '.lua')
  if not ok then return false end
  local dir = path:match('^(.*)[/\\]')
  if not dir or not reaper.file_exists(dir .. '/' .. file) then
    reaper.MB("\"" .. file .. "\" isn't in that folder.", 'GFX actions', 0)
    return false
  end
  reaper.SetExtState(SECTION, 'gfx_dir', dir, true)
  found = {}                                    -- look again for every GFX key
  for g = 1, NG do for i = 1, MAXK do if keys[g][i] then keys[g][i].miss = nil end end end
  return true
end

local function run(g, i, shift)
  local s = keys[g][i]
  if not s then return 'EMPTY' end
  K_SHIFT = shift                               -- Shift-click: a built-in runs from here even where the custom action exists
  local c = command_of(s)
  K_SHIFT = false
  if (not c or c == 0) and s.kind == 'gfx' and locate(s.file) then c = command_of(s) end
  if not c or c == 0 then return s.kind == 'gfx' and 'SCRIPT MISSING' or 'ACTION MISSING' end
  if c == -1 then                               -- a built-in: all its steps, in order
    local b, why = BUILTIN[s.cmd], nil
    if b[2] then reaper.Undo_BeginBlock() end
    for _, st in ipairs(b[3]) do
      if type(st) == 'function' then
        local ok, w = st()
        if ok == false then why = w; break end
      else
        reaper.Main_OnCommand(tonumber(st), 0)
      end
    end
    reaper.UpdateArrange()
    if b[2] then reaper.Undo_EndBlock(b[1], -1) end
    return why or 'RAN'
  end
  -- a GFX tool runs its key without its window: hand the key over as a shortcut made with its KEY would
  if s.kind == 'gfx' and s.ext ~= '' and s.id ~= '' then reaper.SetExtState(s.ext, 'remote', s.id, false) end
  reaper.Main_OnCommand(c, 0)
  return 'RAN'
end

-- the action's own name, tidied for a key: no "Script: " / "Custom: " / "SWS: " prefix, no ".lua"
local function short_name(cmd)
  local t = reaper.kbd_getTextFromCmd(cmd, 0) or ''
  t = t:gsub('^%a+:%s*', ''):gsub('^SWS/%w+:%s*', ''):gsub('%.lua$', ''):gsub('%.eel$', ''):gsub('%.py$', '')
  if t == '' then t = tostring(cmd) end
  return t
end
local function full_name(s)
  if not s then return '' end
  if s.kind == 'gfx' then return 'GFX: ' .. s.file:gsub('%.lua$', '') end
  local c = command_of(s)
  if c == -1 then
    return 'GFX built-in: ' .. BUILTIN[s.cmd][1]
  end
  return (c and c ~= 0) and reaper.kbd_getTextFromCmd(c, 0) or ('missing: ' .. s.cmd)
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
local function mix(c, d, t)         -- c towards d by t
  local function ch(s) return math.floor(((c >> s) & 255) * (1 - t) + ((d >> s) & 255) * t + 0.5) end
  return (ch(16) << 16) | (ch(8) << 8) | ch(0)
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
-- vignette: darker towards the bottom and right edges, nested L shapes so each pixel is drawn once
local function vig(x, y, w, h, d, a)
  x, y = math.floor(X(x) + 0.5), math.floor(Y(y) + 0.5)
  w, h = math.floor(S(w) + 0.5), math.floor(S(h) + 0.5)
  d = math.max(2, math.floor(S(d or 6) + 0.5)); a = a or 0.24
  for i = 0, d - 1 do
    local t = 1 - i / d
    gfx.set(0, 0, 0, a * t * t)
    gfx.rect(x + i, y + h - 1 - i, w - 2 * i, 1, 1)          -- bottom row of this L
    gfx.rect(x + w - 1 - i, y + i, 1, h - 1 - 2 * i, 1)       -- right column, above that row
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
  if hit and K.pick and id:sub(1, 4) ~= 'gfx_' then K.pick = false; K.make(id, label); return false end
  return hit
end

local function fonts()
  if K.fs == K.s then return end
  K.fs = K.s
  font(2, FONT, 15, true)          -- key legends
  font(3, FONT, 13, true)          -- column names
  font(4, FONT, 13, true)          -- brand / small print, long legends
  font(5, FONT, 19, true)          -- title
  font(6, MONO, 34, true)          -- LCD: big
  font(7, MONO, 19, true)          -- LCD: big on the narrow models
  font(8, MONO, 14, true)          -- LCD: status row
end

-- KEY, then any key: that key becomes an action of its own (a small script in "GFX shortcuts" beside this one), so a
-- keyboard shortcut or toolbar button does what the key does without opening this window. The Action List opens
-- on the new action: Add... under Shortcuts sets its key. Press KEY again (it reads PICK) to cancel.
local KEY_NAME, KEY_EXT = 'GFX Actions', SECTION
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

-- a key's legend: one line at the usual size, or smaller on two lines when the name is long
local function legend(x, y, w, h, s, fg)
  gfx.setfont(2)
  local t = s:upper()
  if gfx.measurestr(t) / K.s <= w - 12 then
    local _, th = gfx.measurestr(t)
    text(x + w / 2, y + (h - 4) / 2 - th / K.s / 2, t, fg, 1)
    return
  end
  gfx.setfont(4)
  local a, b = t, ''
  local best
  for p in t:gmatch('() ') do   -- split at the space nearest the middle
    if not best or math.abs(p - #t / 2) < math.abs(best - #t / 2) then best = p end
  end
  if best then a, b = t:sub(1, best - 1), t:sub(best + 1) end
  local function fit(u)
    if gfx.measurestr(u) / K.s <= w - 10 then return u end
    while #u > 1 and gfx.measurestr(u .. '.') / K.s > w - 10 do u = u:sub(1, -2) end
    return u .. '.'
  end
  a, b = fit(a), fit(b)
  local _, th = gfx.measurestr('A')
  th = th / K.s
  if b == '' then text(x + w / 2, y + (h - 4) / 2 - th / 2, a, fg, 1)
  else
    text(x + w / 2, y + (h - 4) / 2 - th, a, fg, 1)
    text(x + w / 2, y + (h - 4) / 2, b, fg, 1)
  end
end

-- =====================================================================
-- The window, in four models (the A B C D keys beside KEY pick one): A yellow scientific, B silver with a black top,
-- C wide pocket computer (a column per group), D dark graphic calculator
-- =====================================================================
local MODELS = { 'A', 'B', 'C', 'D' }
local model = reaper.GetExtState(SECTION, 'model')
if model ~= 'A' and model ~= 'B' and model ~= 'C' and model ~= 'D' then model = 'C' end
local TOP, KH, KP = 214, 46, 56           -- C: first key row, key height, row pitch
local status, hover, hover_g, last = 'READY', nil, nil, nil
local assigning = nil                     -- { g, i } waiting for an action from the Action List
K.names = {}

-- A, B, D: each group a block of rows of four, one more row once its last key is filled (12 keys at most)
local function grows(g)
  local n = 0
  for i = 1, MAXK do if keys[g][i] then n = i end end
  return math.max(1, math.ceil(math.min(MAXK, n + 1) / 4))
end
local function all_rows() local r = 0; for g = 1, NG do r = r + grows(g) end; return r end

-- B: each group opens / closes from its name (in the table or over its keys), so the window is only as big as needed
local open_g = reaper.GetExtState(SECTION, 'bopen')
if #open_g ~= NG then open_g = string.rep('1', NG) end
local function is_open(g) return open_g:sub(g, g) == '1' end
local function set_open(g, on) open_g = open_g:sub(1, g - 1) .. (on and '1' or '0') .. open_g:sub(g + 1) end
local function save_open() reaper.SetExtState(SECTION, 'bopen', open_g, true) end
local function open_rows() local r = 0; for g = 1, NG do if is_open(g) then r = r + grows(g) end end; return r end

-- the design size of the current model
local function dims()
  if model == 'A' then return 470, 196 + NG * 34 + all_rows() * 46 + 34 end
  if model == 'B' then return 490, 248 + NG * 30 + open_rows() * 46 + 40 end
  if model == 'D' then return 500, 292 + NG * 28 + all_rows() * 46 + 52 end
  return 1100, TOP + rows() * KP + 40
end

-- the Action List as a picker: the chosen action lands on the key
local function assign(g, i)
  if not reaper.PromptForAction then status = 'NEEDS REAPER 7'; return end
  reaper.PromptForAction(-1, 0, 0)
  reaper.PromptForAction(1, 0, 0)
  assigning = { g, i }
  status = 'PICK AN ACTION'
end
local function assign_poll()
  if not assigning then return end
  local c = reaper.PromptForAction(0, 0, 0)
  if c == 0 then return end
  reaper.PromptForAction(-1, 0, 0)
  local g, i = assigning[1], assigning[2]
  if c > 0 then
    local named = reaper.ReverseNamedCommandLookup(c)
    named = type(named) == 'string' and named ~= '' and ('_' .. named) or tostring(c)  -- SWS / custom / scripts by name
    keys[g][i] = { kind = 'act', cmd = named, name = short_name(c) }
    save(g, i)
    status = 'SET'; last = keys[g][i].name
  else
    status = 'READY'
  end
  assigning = nil
end

local function key_menu(g, i)
  local s = keys[g][i]
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  if not s then
    if gfx.showmenu('Choose action...') == 1 then assign(g, i) end
    return
  end
  local others = {}
  for h = 1, NG do if h ~= g then others[#others + 1] = h end end
  local sub = {}
  for n, h in ipairs(others) do sub[#sub + 1] = (n == #others and '<' or '') .. gname[h] end
  local m = gfx.showmenu('Rename...|Change action...|Clear||' .. (i > 1 and '' or '#') .. 'Move up|'
                         .. (i < MAXK and '' or '#') .. 'Move down|>Move to column|' .. table.concat(sub, '|'))
  if m == 1 then
    local ok, n = reaper.GetUserInputs('GFX actions', 1, 'Name on the key:,extrawidth=80', s.name)
    if ok and n:match('%S') then s.name = n; save(g, i) end
  elseif m == 2 then assign(g, i)
  elseif m == 3 then keys[g][i] = nil; save(g, i); status = 'CLEARED'
  elseif m == 4 or m == 5 then
    local j = m == 4 and i - 1 or i + 1
    keys[g][i], keys[g][j] = keys[g][j], keys[g][i]; save(g, i); save(g, j)
  elseif m >= 6 then                      -- into the first empty key of that column
    local h = others[m - 5]
    for j = 1, MAXK do
      if not keys[h][j] then
        keys[h][j], keys[g][i] = s, nil; save(h, j); save(g, i); status = 'MOVED'
        return
      end
    end
    status = 'COLUMN FULL'
  end
end
local function column_menu(g)
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  if gfx.showmenu('Rename column...') == 1 then
    local ok, n = reaper.GetUserInputs('GFX actions', 1, 'Column name:,extrawidth=60', gname[g])
    if ok and n:match('%S') then
      gname[g] = n:upper(); reaper.SetExtState(SECTION, 'g' .. g .. 'name', gname[g], true)
    end
  end
end


-- KEY (lit = the next key clicked becomes a shortcut action), then four red function keys A B C D (the model;
-- the chosen one lit), in the spirit of an 80s school micro's function keys
local function top_keys(x, y, h, bg, fg)
  if key('gfx_key', K.pick and 'PICK' or 'KEY', x, y, 60, h, bg, fg, K.pick) then K.pick = not K.pick end
  for j, m in ipairs(MODELS) do
    local on = m == model
    if key('gfx_m' .. m, m, x + 68 + (j - 1) * 32, y, 28, h, on and 0xF0652E or 0xA8321E, on and 0xFFFFFF or 0xF2C2B0) then
      model = m; reaper.SetExtState(SECTION, 'model', model, true)
    end
  end
  key_poll()
end

local function cell(x, y, w, h)          -- the solar cell
  rr(x, y, w, h, 3, 0x3A2A1E)
  col(0x5A4636); for i = 1, 3 do gfx.rect(X(x + i * w / 4), Y(y + 2), math.max(1, S(1)), S(h - 4), 1) end
end

-- what the LCD says: the key under the mouse (or the last one used), its group, its action
local function lcd_lines(n)
  local hv, hg = K.lh, K.lg
  local hs = hv and keys[hg][hv]
  local big, where, act
  if hv then
    if n == 0 then n = grows(hg) * 4 end
    big = hs and hs.name or (hv == n and n < MAXK and '+ ROW' or 'EMPTY')
    where = gname[hg] .. '  KEY ' .. hv
    act = hs and full_name(hs) or 'CLICK TO CHOOSE'
  else
    big = last or 'GFX ACTIONS'
    where = count() .. ' KEYS IN ' .. NG .. ' GROUPS'
    act = ''
  end
  return big:upper(), where:upper(), act:upper()
end
local function clip(s, w)                -- cut a line to w design px in the current font
  while #s > 1 and gfx.measurestr(s) / K.s > w do s = s:sub(1, -2) end
  return s
end

-- one key of a group: draws it, notes the hover, runs / assigns on a click
local function one_key(g, i, n, x, y, w, h, ebg, efg)
  local s = keys[g][i]
  if over(x, y, w, h) then hover, hover_g = i, g end
  local id = 'g' .. g .. 's' .. i
  K.names[id] = s and s.name or nil      -- what KEY calls the action it makes
  local bg, fg = ebg, efg
  if s then
    local c = gcol(g)
    bg = missing(s) and mix(c, ebg, 0.6) or c
    fg = ink(bg)
  end
  local pick = assigning and assigning[1] == g and assigning[2] == i
  if key(id, '', x, y, w, h, bg, fg, pick or nil) then
    if s then status = run(g, i, gfx.mouse_cap & 8 == 8); last = s.name else assign(g, i) end
  end
  legend(x, y, w, h, s and s.name or (i == n and n < MAXK and '+ ROW' or '+'), fg)
end
-- a group as rows of four (A, B, D); returns its rows
local function block(g, x, y, u, kh, gx, gy, ebg, efg)
  local r = grows(g)
  for i = 1, r * 4 do
    local c, rw = (i - 1) % 4, (i - 1) // 4
    one_key(g, i, r * 4, x + c * (u + gx), y + rw * (kh + gy), u, kh, ebg, efg)
  end
  return r
end

local function fit(DW, DH, bg)
  col(bg); gfx.rect(0, 0, gfx.w, gfx.h, 1)
  K.s = math.max(0.5, math.min(gfx.w / DW, gfx.h / DH))     -- fit the design into the window, centred
  K.ox, K.oy = math.floor((gfx.w - DW * K.s) / 2), math.floor((gfx.h - DH * K.s) / 2)
  fonts()
  K.lh, K.lg = hover, hover_g            -- the LCD shows last frame's hover; this frame finds it again
  hover, hover_g, K.band = nil, nil, nil
end
local function edge(d, a)                -- the case's own edge: a soft shadow bottom and right of the window
  vig(-K.ox / K.s, -K.oy / K.s, gfx.w / K.s, gfx.h / K.s, d or 10, a or 0.28)
end
local function hint_text()
  return K.pick and 'Now click the key to make into its own action.' or 'Click + to add. The last + in a group adds a row.'
end

-- ---------- A: yellow case, dark top plate ----------
local function model_a(DW, DH)
  fit(DW, DH, 0xF0A52E); edge()
  rr(14, 12, DW - 28, 168, 12, 0x2A2A2D); vig(14, 12, DW - 28, 168, 6, 0.3)
  gfx.setfont(4); text(30, 24, 'GFX', 0xE8E2D2)
  gfx.setfont(5); text(30, 40, 'ACTIONS', 0xF4C063)
  top_keys(DW - 30 - 84 - 202, 26, 30, 0x55565C, 0xF4F1E8)
  cell(DW - 30 - 84, 26, 84, 30)
  rr(28, 70, DW - 56, 96, 6, 0x1A1A1C); rr(36, 78, DW - 72, 80, 3, 0x9FAE8C); vig(36, 78, DW - 72, 80, 6, 0.2)
  local big, where = lcd_lines(0)
  gfx.setfont(7); text(48, 90, clip(big, DW - 100), 0x1C2416)
  gfx.setfont(8); text(DW - 48, 128, status:sub(1, 16), 0x1C2416, 2)
  text(48, 128, clip(where, DW - 100 - gfx.measurestr(status:sub(1, 16)) / K.s - 12), 0x1C2416)
  local x0, w0, y = 22, DW - 44, 192
  local u = (w0 - 30) / 4
  for g = 1, NG do
    rr(x0, y, 10, 14, 2, gcol(g))
    gfx.setfont(4); text(x0 + 16, y, gname[g], 0x3B2405)
    if over(x0, y - 2, w0, 20) then K.band = g end
    col(0x3B2405, 0.35); gfx.rect(X(x0 + 2), Y(y + 19), S(w0 - 4), math.max(1, S(1)), 1)
    local r = block(g, x0, y + 26, u, 38, 10, 8, 0x6E6A62, 0xD8D2C4)
    y = y + 34 + r * 46
  end
  gfx.setfont(4); text(x0, y + 6, hint_text(), 0x3B2405)
end

-- ---------- B: black top with a group table, ruled silver body ----------
local function zone(id, x, y, w, h)       -- a clickable area that isn't a key: true when clicked
  local hov = over(x, y, w, h)
  if hov and K.pressed then K.held = id end
  return K.released and K.held == id and hov
end
local function arrow(x, y, on, c)          -- drawn, not a font symbol: pointing down when open, right when closed
  col(c)
  if on then gfx.triangle(X(x), Y(y + 2), X(x + 10), Y(y + 2), X(x + 5), Y(y + 8))
  else gfx.triangle(X(x + 2), Y(y), X(x + 8), Y(y + 5), X(x + 2), Y(y + 10)) end
end
local function model_b(DW, DH)
  fit(DW, DH, 0xC9CBCE)
  rr(-K.ox / K.s, -K.oy / K.s, gfx.w / K.s, 232 + K.oy / K.s, 0, 0x1C1D20)
  edge()
  gfx.setfont(5); text(22, 18, 'GFX', 0xF2F2F2)
  gfx.setfont(4); text(72, 24, 'ACTIONS', 0xF2F2F2)
  local all = true
  for g = 1, NG do if not is_open(g) then all = false end end
  if key('gfx_all', 'ALL', DW - 22 - 84 - 202 - 46, 14, 40, 30, all and 0x6F7178 or 0x3A3B40, 0xF4F1E8) then
    for g = 1, NG do set_open(g, not all) end
    save_open()
  end
  top_keys(DW - 22 - 84 - 202, 14, 30, 0x55565C, 0xF4F1E8)
  cell(DW - 22 - 84, 14, 84, 30)
  rr(18, 56, DW - 36, 92, 6, 0x0E0E10); rr(26, 64, DW - 52, 76, 3, 0xA9B39A); vig(26, 64, DW - 52, 76, 6, 0.2)
  local big, where = lcd_lines(0)
  gfx.setfont(7); text(40, 76, clip(big, DW - 80), 0x1C2416)
  gfx.setfont(8); text(DW - 40, 112, status:sub(1, 16), 0x1C2416, 2)
  text(40, 112, clip(where, DW - 80 - gfx.measurestr(status:sub(1, 16)) / K.s - 12), 0x1C2416)
  -- the table: lit = open; click opens / closes that group
  local tx, tw, ty = 18, DW - 36, 160
  local cw = tw / 4
  for g = 1, NG do
    local c, r = (g - 1) % 4, (g - 1) // 4
    local x, y = tx + c * cw, ty + r * 30
    local on = is_open(g)
    col(on and 0x4A4C52 or 0x2A2B2F); gfx.rect(X(x), Y(y), S(cw - 2), S(28), 1)
    col(gcol(g)); gfx.rect(X(x), Y(y), S(6), S(28), 1)
    gfx.setfont(4); text(x + 14, y + 7, clip(g .. '  ' .. gname[g], cw - 20), on and 0xF4F4F4 or 0x8A8C90)
    if over(x, y, cw - 2, 28) then K.band = g end
    if zone('tab' .. g, x, y, cw - 2, 28) then set_open(g, not on); save_open() end
  end
  -- the groups: a ruled name bar (click it to open / close), then the keys while open
  local x0, w0, y = 18, DW - 36, 248
  local u = (w0 - 30 - 16) / 4
  for g = 1, NG do
    local on = is_open(g)
    col(0x4A4C50); gfx.rect(X(x0), Y(y), S(w0), math.max(1, S(1)), 1)
    col(gcol(g)); gfx.rect(X(x0), Y(y + 1), S(6), S(22), 1)
    arrow(x0 + 14, y + 7, on, 0x2A2B2E)
    gfx.setfont(4); text(x0 + 30, y + 5, g .. '  ' .. gname[g], on and 0x2A2B2E or 0x5A5C60)
    if over(x0, y, w0, 24) then K.band = g end
    if zone('bar' .. g, x0, y, w0, 24) then set_open(g, not on); save_open() end
    local r = on and block(g, x0 + 8, y + 26, u, 38, 10, 8, 0x8E9094, 0xE6E6E6) or 0
    y = y + 30 + r * 46
  end
  col(0x4A4C50); gfx.rect(X(x0), Y(y), S(w0), math.max(1, S(1)), 1)
  gfx.setfont(4); text(x0, y + 10, K.pick and hint_text() or 'Click a group name to open or close it. ALL opens / closes them all.', 0x4A4C50)
end

-- ---------- C: wide pocket computer - LCD and brand panel on top, a coloured name band, a column per group ----------
local function model_c(DW, DH)
  local n = rows()
  fit(DW, DH, 0xCBCDCF); edge()
  rr(18, 18, 780, 120, 6, 0x9A9DA1); vig(18, 18, 780, 120, 6)
  rr(28, 28, 760, 100, 4, 0x2A2B2E)
  rr(38, 38, 740, 80, 3, 0xA9B39A); vig(38, 38, 740, 80, 6, 0.2)
  local big, where, act = lcd_lines(n)
  if #big > 34 then big = big:sub(1, 33) .. '.' end
  gfx.setfont(6); text(56, 48, big .. ((not K.lh and last) and '_' or ''), 0x1C2416)
  gfx.setfont(8)
  local st = status:sub(1, 16)
  local small = clip(where .. (act ~= '' and ('  ' .. act) or ''), 700 - gfx.measurestr(st) / K.s)
  text(56, 96, small, 0x1C2416); text(764, 96, st, 0x1C2416, 2)
  rr(816, 18, DW - 834, 120, 6, 0x4A4C52); vig(816, 18, DW - 834, 120, 6, 0.3)
  gfx.setfont(5); text(836, 34, 'GFX', 0xF2F2F2)
  gfx.setfont(4); text(888, 40, 'ACTIONS', 0xE8E8E8)
  cell(988, 34, 76, 22)
  top_keys(836, 80, 34, 0x6A6C72, 0xF4F1E8)
  local x0, w0, gap = 18, DW - 36, 10
  local cw = (w0 - gap * (NG - 1)) / NG
  rr(x0, 154, w0, 44, 4, 0x2A2B2E)
  for g = 1, NG do
    local x = x0 + (g - 1) * (cw + gap)
    col(gcol(g)); gfx.rect(X(x), Y(154), S(cw + (g < NG and gap or 0)), S(8), 1)
    gfx.setfont(3); text(x + cw / 2, 172, gname[g], 0xF2F2F2, 1)
    if g > 1 then col(0x55575C); gfx.rect(X(x - gap / 2), Y(166), math.max(1, S(1)), S(28), 1) end
    if over(x, 162, cw, 36) then K.band = g end
    for i = 1, n do one_key(g, i, n, x, TOP + (i - 1) * KP, cw, KH, 0x8E9094, 0xE6E6E6) end
  end
  gfx.setfont(4)
  text(x0, DH - 30, K.pick and 'Now click the key to make into an action of its own (for a shortcut). KEY again cancels.'
    or 'Click + to add an action. The bottom + adds a row to every column (up to 12). Right-click a key or a column name for more.', 0x4A4C50)
end

-- ---------- D: dark graphic calculator, every group a block of labelled keys ----------
local function model_d(DW, DH)
  fit(DW, DH, 0x1E1F22)
  rr(6, 6, DW - 12, DH - 12, 26, 0x2E3034); edge(8, 0.3)
  for _, p in ipairs({ { 30, 30 }, { DW - 30, 30 }, { 30, 274 }, { DW - 30, 274 } }) do
    col(0x18191B); gfx.circle(X(p[1]), Y(p[2]), S(8), 1, 1)
    col(0x45484D); gfx.circle(X(p[1]), Y(p[2]), S(5), 1, 1)
  end
  gfx.setfont(5); text(60, 20, 'GFX', 0xD8DADC)
  top_keys(112, 16, 30, 0xE2B13C, 0x1E1E1E)
  rr(DW - 138, 18, 72, 28, 4, 0xC9A04A); rr(DW - 136, 20, 68, 24, 3, 0x1E1F22)
  gfx.setfont(4); text(DW - 102, 25, 'ACTIONS', 0xC9A04A, 1)
  rr(44, 60, DW - 88, 196, 8, 0x15161A); rr(58, 74, DW - 116, 168, 4, 0xC6C9A0); vig(58, 74, DW - 116, 168, 6, 0.2)
  local big, where, act = lcd_lines(0)
  gfx.setfont(7); text(76, 90, clip(big, DW - 152), 0x1C2416)
  gfx.setfont(8)
  text(76, 124, clip(where, DW - 152), 0x1C2416)
  text(76, 146, clip(act, DW - 152), 0x1C2416)
  text(DW - 76, 212, status:sub(1, 16), 0x1C2416, 2)
  local x0, w0, y = 30, DW - 60, 276
  local u = (w0 - 3 * 8) / 4
  for g = 1, NG do
    gfx.setfont(4); text(x0 + 2, y, gname[g], gcol(g))
    if over(x0, y - 2, w0, 18) then K.band = g end
    local r = block(g, x0, y + 20, u, 38, 8, 8, 0x4A4D52, 0x9A9EA4)
    y = y + 28 + r * 46
  end
  gfx.setfont(4); text(DW / 2, y + 8, hint_text(), 0xC9A04A, 1)
end

local DRAW = { A = model_a, B = model_b, C = model_c, D = model_d }
local function draw() local w, h = dims(); DRAW[model](w, h) end

load()
local headless = setmetatable({}, { __index = function(_, id)
  local g, i = id:match('^g(%d+)s(%d+)$')
  g, i = tonumber(g), tonumber(i)
  if g and keys[g] and keys[g][i] then return function() run(g, i) end end
end })
if K.remote_start(headless) then return end

local _, _, sec, cmd = reaper.get_action_context()
reaper.SetExtState(SECTION, "running", "1", false)
reaper.SetToggleCommandState(sec, cmd, 1); reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(function()
  if assigning then reaper.PromptForAction(-1, 0, 0) end
  reaper.SetExtState(SECTION, "running", "0", false)
  reaper.SetToggleCommandState(sec, cmd, 0); reaper.RefreshToolbar2(sec, cmd)
end)

local pw, ph = dims()
local sc = tonumber(reaper.GetExtState(SECTION, "scale")) or 1
gfx.ext_retina = 1
gfx.init("GFX actions", math.floor(pw * sc + 0.5), math.floor(ph * sc + 0.5), tonumber(reaper.GetExtState(SECTION, "dock")) or 0)

local rwas = false
local function loop()
  local c = gfx.getchar()
  if c < 0 or c == 27 then   -- closed, or Esc
    reaper.SetExtState(SECTION, "dock", tostring(gfx.dock(-1)), true)
    if gfx.dock(-1) & 1 == 0 then reaper.SetExtState(SECTION, "scale", tostring(K.s / (gfx.ext_retina or 1)), true) end
    gfx.quit()
    return
  end
  K.remote_poll()
  assign_poll()
  -- another model, or a group that grew / shrank a row: the window takes the new size at the same scale
  local w, h = dims()
  if w ~= pw or h ~= ph then
    if gfx.dock(-1) & 1 == 0 then
      local r = gfx.ext_retina or 1
      gfx.init('', math.floor(w * K.s / r + 0.5), math.floor(h * K.s / r + 0.5))
    end
    pw, ph = w, h
  end
  mouse_frame()
  draw()
  local rdown = (gfx.mouse_cap & 2) == 2      -- right-click a key or a group's name: its menu
  if rwas and not rdown then
    if hover then key_menu(hover_g, hover) elseif K.band then column_menu(K.band) end
  end
  rwas = rdown
  gfx.update()
  reaper.defer(loop)
end
loop()
