-- @description GFX - set selected tracks' input to all MIDI
-- @author JGWizrad / Garden FX (GFX)
-- @version 1.0
-- @about
--   Sets the record input of every selected track to MIDI: all inputs, all channels, and turns record monitoring
--   on, so a GFX instrument on the track plays from your keyboard straight away. Needs nothing but REAPER.

local n = reaper.CountSelectedTracks(0)
if n == 0 then
  reaper.MB("Select the tracks first.", "GFX - input to all MIDI", 0)
  return
end
reaper.Undo_BeginBlock()
for i = 0, n - 1 do
  local tr = reaper.GetSelectedTrack(0, i)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", 4096 | (63 << 5))   -- MIDI, all devices, all channels
  reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 1)
end
reaper.Undo_EndBlock("GFX - set input to all MIDI", -1)
