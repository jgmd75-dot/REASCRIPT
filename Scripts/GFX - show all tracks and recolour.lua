-- @description GFX - show all tracks and recolour
-- @author JGWizrad / Garden FX (GFX)
-- @version 1.0
-- @about
--   Shows every track again in both the arrange view and the mixer (hidden ones, and folder children hidden by
--   "GFX - hide / show folder children in mixer"), opens every folder, then recolours every track in order from
--   the GFX palette. Your selection is kept. Needs nothing but REAPER (no SWS).

local PALETTE = { 0xC0504D, 0xD9844A, 0xD8B44A, 0x9BBB59, 0x4BACA6, 0x4F81BD, 0x7B6AB0, 0xB0609A,
                  0x8C6D4F, 0x6E8C5A, 0x5A7C8C, 0x8C5A6E }

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
for i = 0, reaper.CountTracks(0) - 1 do
  local tr = reaper.GetTrack(0, i)
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 1)
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 1)
  if reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1 then
    reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT", 0)
  end
  local c = PALETTE[i % #PALETTE + 1]
  reaper.SetTrackColor(tr, reaper.ColorToNative(c >> 16 & 255, c >> 8 & 255, c & 255))
end
reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.Undo_EndBlock("GFX - show all tracks and recolour", -1)
