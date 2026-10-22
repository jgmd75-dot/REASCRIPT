-- @description GFX - new track
-- @author JGWizrad / Garden FX (GFX)
-- @version 1.0
-- @about
--   Adds a new track at the bottom of the project, recolours every track in order from the GFX palette and closes
--   any floating FX windows. Needs nothing but REAPER (no SWS).

local PALETTE = { 0xC0504D, 0xD9844A, 0xD8B44A, 0x9BBB59, 0x4BACA6, 0x4F81BD, 0x7B6AB0, 0xB0609A,
                  0x8C6D4F, 0x6E8C5A, 0x5A7C8C, 0x8C5A6E }

local function recolour_all()
  for i = 0, reaper.CountTracks(0) - 1 do
    local c = PALETTE[i % #PALETTE + 1]
    reaper.SetTrackColor(reaper.GetTrack(0, i), reaper.ColorToNative(c >> 16 & 255, c >> 8 & 255, c & 255))
  end
end

local function close_fx_windows()
  local function shut(tr)
    for fx = 0, reaper.TrackFX_GetCount(tr) - 1 do reaper.TrackFX_Show(tr, fx, 2) end
  end
  shut(reaper.GetMasterTrack(0))
  for i = 0, reaper.CountTracks(0) - 1 do shut(reaper.GetTrack(0, i)) end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local n = reaper.CountTracks(0)
reaper.InsertTrackAtIndex(n, true)
local tr = reaper.GetTrack(0, n)
reaper.SetOnlyTrackSelected(tr)
recolour_all()
close_fx_windows()
reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.Undo_EndBlock("GFX - new track", -1)
