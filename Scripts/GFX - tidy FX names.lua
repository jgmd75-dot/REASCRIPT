-- GFX - tidy FX names.lua
-- author: JGWizrad / Garden FX (GFX)
--
-- Keeps "GFX ..." names in REAPER's FX browser (so the range stays grouped there) but shows tidy names on the
-- tracks: "GFX Drive81 [preamp]" becomes "Drive81 [preamp]", and the instrument "G" goes too ("GFX G Moon [Arcana
-- synth]" becomes "Moon [Arcana synth]"); Lab plug-ins lose "GFX Lab " too ("GFX Lab C2M [compressor]" becomes
-- "C2M [compressor]", "GFX Lab G Salem [synth]" becomes "Salem [synth]"). It sets each instance's own name, the same as right-clicking an FX and
-- choosing Rename, so it never touches an FX you have renamed yourself, and you can rename any of them afterwards.
--
-- Run it once to tidy the current project, or leave it running: while it runs it tidies every GFX plug-in as soon
-- as it is inserted (track FX, take FX, the master and the monitoring chain). Run it again to stop it. To have it
-- start with REAPER, add it to your startup actions (SWS "Startup action", or a __startup.lua that calls it).
-- Needs REAPER 6.37 or later.

local SECTION = "GFX_tidy_names"

local function tidy(name)
  -- name is the plug-in's own name, e.g. "JS: GFX G Moon [Arcana synth]" or "GFX Drive81 [preamp]"
  local core = name:gsub("^%w+:%s*", "")                 -- drop a "JS: " style prefix if present
  if core:sub(1, 4) ~= "GFX " then return nil end
  core = core:sub(5)                                      -- drop "GFX "
  core = core:gsub("^Lab ", "")                           -- drop "Lab " (GFX Lab plug-ins)
  core = core:gsub("^G ", "")                             -- drop the instrument "G "
  return core
end

local function fix_track_fx(tr)
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
    local _, renamed = reaper.TrackFX_GetNamedConfigParm(tr, i, "renamed_name")
    if renamed == "" then
      local _, orig = reaper.TrackFX_GetNamedConfigParm(tr, i, "fx_name")
      local t = tidy(orig)
      if t then reaper.TrackFX_SetNamedConfigParm(tr, i, "renamed_name", t) end
    end
  end
  -- the monitoring / input FX chain (record-input FX) uses indices from 0x1000000
  for i = 0, reaper.TrackFX_GetRecCount(tr) - 1 do
    local idx = 0x1000000 + i
    local _, renamed = reaper.TrackFX_GetNamedConfigParm(tr, idx, "renamed_name")
    if renamed == "" then
      local _, orig = reaper.TrackFX_GetNamedConfigParm(tr, idx, "fx_name")
      local t = tidy(orig)
      if t then reaper.TrackFX_SetNamedConfigParm(tr, idx, "renamed_name", t) end
    end
  end
end

local function fix_take_fx(take)
  for i = 0, reaper.TakeFX_GetCount(take) - 1 do
    local _, renamed = reaper.TakeFX_GetNamedConfigParm(take, i, "renamed_name")
    if renamed == "" then
      local _, orig = reaper.TakeFX_GetNamedConfigParm(take, i, "fx_name")
      local t = tidy(orig)
      if t then reaper.TakeFX_SetNamedConfigParm(take, i, "renamed_name", t) end
    end
  end
end

local function pass()
  fix_track_fx(reaper.GetMasterTrack(0))
  for t = 0, reaper.CountTracks(0) - 1 do fix_track_fx(reaper.GetTrack(0, t)) end
  for it = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, it)
    for k = 0, reaper.CountTakes(item) - 1 do
      local take = reaper.GetTake(item, k)
      if take then fix_take_fx(take) end
    end
  end
end

-- Run / stop toggle: a second launch while running stops it.
local _, _, sec, cmd = reaper.get_action_context()
if reaper.GetExtState(SECTION, "running") == "1" then
  reaper.SetExtState(SECTION, "running", "0", false)     -- the running copy sees this and stops
  return
end
reaper.SetExtState(SECTION, "running", "1", false)
reaper.SetToggleCommandState(sec, cmd, 1); reaper.RefreshToolbar2(sec, cmd)

local last_state, last_t = -1, 0
local function loop()
  if reaper.GetExtState(SECTION, "running") ~= "1" then
    reaper.SetToggleCommandState(sec, cmd, 0); reaper.RefreshToolbar2(sec, cmd)
    return
  end
  local now = reaper.time_precise()
  local st = reaper.GetProjectStateChangeCount(0)
  if st ~= last_state and now - last_t > 0.5 then        -- only after something changed, at most twice a second
    last_state, last_t = st, now
    pass()
  end
  reaper.defer(loop)
end

reaper.atexit(function()
  reaper.SetExtState(SECTION, "running", "0", false)
  reaper.SetToggleCommandState(sec, cmd, 0); reaper.RefreshToolbar2(sec, cmd)
end)

pass()
loop()
