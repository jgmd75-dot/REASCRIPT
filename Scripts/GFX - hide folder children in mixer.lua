-- @description GFX - hide / show folder children in mixer
-- @author JGWizrad / Garden FX (GFX)
-- @version 1.0
-- @about
--   A toggle for the mixer: hides every track that sits inside a folder, so only the folder tracks and loose tracks
--   show; run it again to show them all. The tracks stay visible in the arrange view. Put it on a toolbar - its
--   button lights while the children are hidden. Needs nothing but REAPER (no SWS).

local _, _, sec, cmd = reaper.get_action_context()

local children, shown = {}, false
for i = 0, reaper.CountTracks(0) - 1 do
  local tr = reaper.GetTrack(0, i)
  if reaper.GetTrackDepth(tr) > 0 then
    children[#children + 1] = tr
    if reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER") == 1 then shown = true end
  end
end
if #children == 0 then return end

reaper.Undo_BeginBlock()
for _, tr in ipairs(children) do reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", shown and 0 or 1) end
reaper.TrackList_AdjustWindows(false)
reaper.SetToggleCommandState(sec, cmd, shown and 1 or 0)
reaper.RefreshToolbar2(sec, cmd)
reaper.Undo_EndBlock(shown and "GFX - hide folder children in mixer" or "GFX - show folder children in mixer", -1)
