-- @description GFX ORCHD - write MIDI
-- @author JGWizrad / Garden FX (GFX)
-- @version 1.1
-- @about
--   Companion script for the GFX Lab ORCHD chord calculator (JSFX).
--   JSFX plugins cannot write MIDI items, so with ORCHD's WRITE key lit, = and MR hand their chords to this script
--   through shared memory (gmem "GFX_ORCHD"), and it writes them into a MIDI item at the edit cursor, then moves
--   the cursor to the end of what it wrote - the way the CC-80 script did:
--     into the take open in the MIDI editor if there is one, else into the MIDI item on the selected track that
--     the cursor is in (or that ends no more than two bars before it), else into a new item on the selected track.
--   The chords keep ORCHD's voicing, leading note, octave and lengths (at the project tempo). It works with the
--   transport stopped (ORCHD's panel sends the chords itself); ORCHD's LCD says START SCRIPT if this isn't running.
--
-- Use: Actions > Load ReaScript, pick this file, run it. It keeps running in the background (its toolbar
-- button lights) and writes every time ORCHD sends chords. Run it again to stop it.

local GMEM = "GFX_ORCHD"
reaper.gmem_attach(GMEM)

-- the take that receives the notes, extended to cover t0 .. t1 (seconds); nil + message if there is none
local function get_take(t0, t1)
  local take
  local me = reaper.MIDIEditor_GetActive()
  if me then take = reaper.MIDIEditor_GetTake(me) end
  if take and not reaper.ValidatePtr(take, "MediaItem_Take*") then take = nil end

  if not take then
    local tr = reaper.GetSelectedTrack(0, 0)
    if not tr then return nil, "Select a track for ORCHD's chords first." end
    local best_end, gap_t = -math.huge, reaper.TimeMap2_QNToTime(0, reaper.TimeMap2_timeToQN(0, t0) - 8)
    for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local tk = reaper.GetActiveTake(it)
      if tk and reaper.TakeIsMIDI(tk) and p <= t0 + 0.000001 and e > best_end then best_end = e; take = tk end
    end
    if take and best_end < gap_t - 0.000001 then take = nil end
    if not take then
      local it = reaper.CreateNewMIDIItemInProj(tr, t0, t1, false)
      if not it then return nil, "Couldn't make a MIDI item." end
      take = reaper.GetActiveTake(it)
    end
  end
  if not take or not reaper.TakeIsMIDI(take) then return nil, "The take isn't MIDI." end

  local it = reaper.GetMediaItemTake_Item(take)
  local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local l = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  if t0 < p - 0.000001 or t1 > p + l + 0.000001 then
    reaper.MIDI_SetItemExtents(it, reaper.TimeMap2_timeToQN(0, math.min(p, t0)),
                                   reaper.TimeMap2_timeToQN(0, math.max(p + l, t1)))
  end
  return take
end

local function write()
  local n = math.floor(reaper.gmem_read(1) + 0.5)
  local total = reaper.gmem_read(2)
  local chan = math.floor(reaper.gmem_read(3) + 0.5)
  if total <= 0 then return end
  local cur = reaper.GetCursorPosition()
  local qn0 = reaper.TimeMap2_timeToQN(0, cur)
  local t1 = reaper.TimeMap2_QNToTime(0, qn0 + total)

  reaper.Undo_BeginBlock()
  if n > 0 then
    local take, err = get_take(cur, t1)
    if not take then
      reaper.Undo_EndBlock("GFX ORCHD: write chords", -1)
      reaper.MB(err, "GFX ORCHD - write MIDI", 0)
      return
    end
    for i = 0, n - 1 do
      local b = 16 + i * 4
      local q, len = reaper.gmem_read(b), reaper.gmem_read(b + 1)
      local pitch, vel = math.floor(reaper.gmem_read(b + 2) + 0.5), math.floor(reaper.gmem_read(b + 3) + 0.5)
      if pitch >= 0 and pitch <= 127 then
        local p1 = reaper.MIDI_GetPPQPosFromProjQN(take, qn0 + q)
        local p2 = reaper.MIDI_GetPPQPosFromProjQN(take, qn0 + q + len)
        reaper.MIDI_InsertNote(take, false, false, p1, p2, chan, pitch, math.max(1, math.min(127, vel)), true)
      end
    end
    reaper.MIDI_Sort(take)
  end
  reaper.SetEditCurPos(t1, true, false)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("GFX ORCHD: write chords", -1)
end

-- background loop: write whenever ORCHD bumps the request counter
local _, _, sec, cmd = reaper.get_action_context()
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(function()
  reaper.SetToggleCommandState(sec, cmd, 0)
  reaper.RefreshToolbar2(sec, cmd)
end)

local last = reaper.gmem_read(0)            -- requests sent before the script started are not written
local beat = 0
local function loop()
  beat = beat + 1
  reaper.gmem_write(4, beat)                 -- heartbeat: ORCHD's panel shows START SCRIPT when this stops moving
  local c = reaper.gmem_read(0)
  if c ~= last then
    last = c
    write()
  end
  reaper.defer(loop)
end
loop()
