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
-- Use: Actions > Load ReaScript, pick this file, run it. It keeps running in the background (its toolbar
-- button lights) and exports every time you press EXPORT MIDI. Run it again to stop it.
-- If you pressed EXPORT MIDI before starting the script, it exports that pattern straight away.

local GMEM = "GFX_GDeep"
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

local function export()
  local steps = math.floor(reaper.gmem_read(2) + 0.5)
  if steps ~= 16 then return end                    -- nothing written yet
  local bars = math.max(1, math.floor(reaper.gmem_read(1) + 0.5))
  local swing = reaper.gmem_read(3)                 -- fraction of a 16th that the off-beat 16ths arrive late
  local rows = math.floor(reaper.gmem_read(5) + 0.5)
  if rows < 3 or rows > 6 then rows = 3 end         -- (the first G-Deep had three rows)
  local track = target_track()
  if not track then
    reaper.MB("Add a track (with GFX G-Deep 16 on it) first.", "GFX G-Deep export", 0)
    return
  end

  reaper.Undo_BeginBlock()
  local pos = reaper.GetCursorPosition()
  local qn0 = reaper.TimeMap2_timeToQN(0, pos)
  local item = reaper.CreateNewMIDIItemInProj(track, pos, reaper.TimeMap2_QNToTime(0, qn0 + bars * 4), false)
  local take = reaper.GetActiveTake(item)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "G-Deep pattern", true)

  for bar = 0, bars - 1 do
    for row = 0, rows - 1 do
      for s = 0, 15 do
        local v = math.floor(reaper.gmem_read(10 + row * 16 + s) + 0.5)
        if v > 0 then
          local q = qn0 + bar * 4 + s * 0.25 + ((s % 2 == 1) and swing * 0.25 or 0)
          local p1 = reaper.MIDI_GetPPQPosFromProjQN(take, q)
          local p2 = reaper.MIDI_GetPPQPosFromProjQN(take, q + 0.125)
          reaper.MIDI_InsertNote(take, false, false, p1, p2, CHAN, NOTES[row + 1], v == 2 and 127 or 100, true)
        end
      end
    end
  end
  reaper.MIDI_Sort(take)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("GFX G-Deep: export MIDI pattern", -1)
end

-- background loop: export whenever the plugin flags a pending request
local _, _, sec, cmd = reaper.get_action_context()
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(function()
  reaper.SetToggleCommandState(sec, cmd, 0)
  reaper.RefreshToolbar2(sec, cmd)
end)

local function loop()
  if reaper.gmem_read(4) == 1 then
    reaper.gmem_write(4, 0)
    export()
  end
  reaper.defer(loop)
end
loop()
