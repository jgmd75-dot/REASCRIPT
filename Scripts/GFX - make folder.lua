-- @description GFX - make folder from selected tracks
-- @author JGWizrad / Garden FX (GFX)
-- @version 1.0
-- @about
--   Puts the selected tracks into a new folder: asks for the folder's name, adds the folder track above the first
--   selected track, moves the selected tracks into it (they don't have to be next to each other), gives the folder
--   the next colour from the GFX palette and closes any floating FX windows. Your selection is kept.
--   Needs nothing but REAPER (no SWS).

local PALETTE = { 0xC0504D, 0xD9844A, 0xD8B44A, 0x9BBB59, 0x4BACA6, 0x4F81BD, 0x7B6AB0, 0xB0609A,
                  0x8C6D4F, 0x6E8C5A, 0x5A7C8C, 0x8C5A6E }

local function close_fx_windows()
  local function shut(tr)
    for fx = 0, reaper.TrackFX_GetCount(tr) - 1 do reaper.TrackFX_Show(tr, fx, 2) end
  end
  shut(reaper.GetMasterTrack(0))
  for i = 0, reaper.CountTracks(0) - 1 do shut(reaper.GetTrack(0, i)) end
end

-- the palette colour after the one the previous track wears (or the first one)
local function next_colour(idx)
  local k = 0
  if idx > 0 then
    local r, g, b = reaper.ColorFromNative(reaper.GetTrackColor(reaper.GetTrack(0, idx - 1)) & 0xFFFFFF)
    local c = r << 16 | g << 8 | b
    for i, p in ipairs(PALETTE) do if p == c then k = i end end
  end
  local c = PALETTE[k % #PALETTE + 1]
  return reaper.ColorToNative(c >> 16 & 255, c >> 8 & 255, c & 255) | 0x1000000
end

local first = reaper.GetSelectedTrack(0, 0)
if not first then
  reaper.MB("Select the tracks to put in the folder first.", "GFX - make folder", 0)
  return
end
local ok, name = reaper.GetUserInputs("GFX - make folder", 1, "Folder name:,extrawidth=120", "Folder")
if not ok then return end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local idx = math.floor(reaper.GetMediaTrackInfo_Value(first, "IP_TRACKNUMBER")) - 1
reaper.InsertTrackAtIndex(idx, true)
local folder = reaper.GetTrack(0, idx)
reaper.GetSetMediaTrackInfo_String(folder, "P_NAME", name, true)
reaper.SetMediaTrackInfo_Value(folder, "I_CUSTOMCOLOR", next_colour(idx))
reaper.ReorderSelectedTracks(idx + 1, 1)            -- 1 = make them children of the track before (the folder)
close_fx_windows()
reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.Undo_EndBlock("GFX - make folder", -1)
