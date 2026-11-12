-- @description GFX Drum Sampler scan (sample folders for Drum Sampler Mini)
-- @author GardenFX
-- by JGWizrad / Garden FX (GFX)
-- @version 1.0

local MAXFILES = 16384
local EXT = { wav = true, aif = true, aiff = true, flac = true, ogg = true, mp3 = true, wv = true }
local sep = package.config:sub(1, 1)

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\\/]+$", "")) end

local function split(s)
  local list = {}
  for part in s:gmatch("[^;]+") do
    local f = trim(part)
    if f ~= "" then list[#list + 1] = f end
  end
  return list
end

local function browse()
  if reaper.JS_Dialog_BrowseForFolder then
    local ok, folder = reaper.JS_Dialog_BrowseForFolder("GFX Drum Sampler: add a sample folder", "")
    if ok == 1 and folder ~= "" then return trim(folder) end
    return nil
  end
  local ok, folder = reaper.GetUserInputs("GFX Drum Sampler: add a sample folder", 1, "Folder:,extrawidth=420", "")
  if ok and trim(folder) ~= "" then return trim(folder) end
  return nil
end

local function ask_folders()
  local saved = reaper.GetExtState("gfx_drum_sampler", "folders")
  if saved == "" then saved = reaper.GetExtState("gfx_smart_sampler", "folders") end
  local list = split(saved)
  if #list == 0 then
    local folder = browse()
    if not folder then return nil end
    list = { folder }
  else
    local answer = reaper.MB("Your sample folders:\n\n" .. table.concat(list, "\n") ..
      "\n\nYes: add another folder.\nNo: change the list (to take a folder out, or just press OK to look through them again).",
      "GFX Drum Sampler", 3)
    if answer == 6 then
      local folder = browse()
      if not folder then return nil end
      list[#list + 1] = folder
    elseif answer == 7 then
      local ok, text = reaper.GetUserInputs("GFX Drum Sampler: sample folders", 1,
        "Folders (separate with ;):,extrawidth=420", table.concat(list, ";"))
      if not ok then return nil end
      list = split(text)
    else
      return nil
    end
  end
  reaper.SetExtState("gfx_drum_sampler", "folders", table.concat(list, ";"), true)
  return list
end

local function walk(dir, out)
  if #out >= MAXFILES then return end
  reaper.EnumerateFiles(dir, -1)
  local files, i = {}, 0
  while true do
    local name = reaper.EnumerateFiles(dir, i)
    if not name then break end
    local ext = name:match("%.([^%.]+)$")
    if ext and EXT[ext:lower()] and name:sub(1, 2) ~= "._" then files[#files + 1] = name end
    i = i + 1
  end
  table.sort(files, function(a, b) return a:lower() < b:lower() end)
  for _, name in ipairs(files) do
    if #out >= MAXFILES then return end
    out[#out + 1] = dir .. sep .. name
  end
  local subs = {}
  i = 0
  while true do
    local name = reaper.EnumerateSubdirectories(dir, i)
    if not name then break end
    if name:sub(1, 1) ~= "." then subs[#subs + 1] = name end
    i = i + 1
  end
  table.sort(subs, function(a, b) return a:lower() < b:lower() end)
  for _, name in ipairs(subs) do walk(dir .. sep .. name, out) end
end

local folders = ask_folders()
if not folders or #folders == 0 then return end

local lines, total, missing = { "Drum Sampler Mini library" }, 0, {}
for _, folder in ipairs(folders) do
  local root = trim(folder)
  if reaper.EnumerateFiles(root, 0) == nil and reaper.EnumerateSubdirectories(root, 0) == nil then
    missing[#missing + 1] = root
  else
    local files = {}
    walk(root, files)
    if #files > MAXFILES - total then
      for k = #files, MAXFILES - total + 1, -1 do files[k] = nil end
    end
    lines[#lines + 1] = "#root " .. root
    for _, f in ipairs(files) do lines[#lines + 1] = f end
    total = total + #files
  end
end

local dir = reaper.GetResourcePath() .. sep .. "Data" .. sep .. "gfx-drum-sampler"
reaper.RecursiveCreateDirectory(dir, 0)
local fh = io.open(dir .. sep .. "library.txt", "w")
if not fh then
  reaper.MB("Could not write " .. dir .. sep .. "library.txt", "GFX Drum Sampler", 0)
  return
end
fh:write(table.concat(lines, "\n"), "\n")
fh:close()

local msg = string.format("Found %d sound files.", total)
if total >= MAXFILES then msg = msg .. string.format(" (Drum Sampler Mini takes the first %d.)", MAXFILES) end
if #missing > 0 then msg = msg .. "\n\nThese folders could not be found:\n" .. table.concat(missing, "\n") end
msg = msg .. "\n\nOn Drum Sampler, click the display at the top and choose Read the library again."
reaper.MB(msg, "GFX Drum Sampler", 0)
