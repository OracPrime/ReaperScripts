-- @description Snapshot Volumes, Fast-Copy Template, Apply, and Save
-- @author Gemini

-------------------
-- CONFIGURATION --
-------------------
local LIVE_PROJECTS_ROOT = "f:\\ReaperMusic\\Live"
local TEMPLATE_PATH = "C:\\Users\\dc\\AppData\\Roaming\\REAPER\\ProjectTemplates\\JamProject.rpp"

-- 1. Gather current track volumes and store them in a table for later application
local current_volumes = {}
local num_tracks = reaper.CountTracks(0)

for i = 0, num_tracks - 1 do
  local track = reaper.GetTrack(0, i)
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  local vol = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
  if name ~= "" then
    current_volumes[name] = vol
  end
end

-- Grab Master track volume as well
local master_track = reaper.GetMasterTrack(0)
local master_vol = reaper.GetMediaTrackInfo_Value(master_track, "D_VOL")

-- 2. Generate default inputs based on current date and time
local current_date_str = os.date("%d%b%y"):lower() -- e.g., 20jul26
local default_song_name = os.date("%H%M%S")      

local retval, retvals_csv = reaper.GetUserInputs("New Live Track Setup", 1, "Song/Folder Name:", default_song_name)

if not retval or retvals_csv == "" then return end

-- Clean input for path usage and construct paths
local song_name = retvals_csv:gsub("[\\/:*?\"<>|]", "")
local target_dir = LIVE_PROJECTS_ROOT .. "\\" .. current_date_str .. "\\" .. song_name .. "\\"
local target_file = target_dir .. song_name .. ".rpp"

reaper.Undo_BeginBlock()

-- 3. Create the target folder structure
reaper.RecursiveCreateDirectory(target_dir, 0)

-- 4. FAST COPY: Read the template file and write it directly to the new location
local infile = io.open(TEMPLATE_PATH, "rb")
if not infile then
  reaper.ShowMessageBox("Could not read template file at:\n" .. TEMPLATE_PATH, "File Error", 0)
  return
end
local content = infile:read("*a")
infile:close()

local outfile = io.open(target_file, "wb")
if not outfile then
  reaper.ShowMessageBox("Could not write to target file at:\n" .. target_file, "File Error", 0)
  return
end
outfile:write(content)
outfile:close()

-- 5. Open a new tab and load our newly minted project (Only ONE load time!)
reaper.Main_OnCommand(40859, 0) -- File: New project tab
reaper.Main_openProject(target_file)

-- 6. Apply volumes to matching tracks in the new project
local new_num_tracks = reaper.CountTracks(0)
for i = 0, new_num_tracks - 1 do
  local track = reaper.GetTrack(0, i)
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  if current_volumes[name] then
    reaper.SetMediaTrackInfo_Value(track, "D_VOL", current_volumes[name])
  end
end

-- Apply Master volume
local new_master = reaper.GetMasterTrack(0)
reaper.SetMediaTrackInfo_Value(new_master, "D_VOL", master_vol)

-- 7. Save the active project normally to bake in the volume changes
reaper.Main_SaveProject(0, false) 

reaper.TrackCtl_SetToolTip("Ready: " .. song_name, 0, 0, true)
reaper.Undo_EndBlock("Setup New Live Track", -1)

-- 8. DEFERRED UADx CLEANUP: Wait 1.2 seconds for UADx plugins to finish initializing, then clear the dirty flag
local start_time = reaper.time_precise()
local function ClearUADxDirtyState()
  if reaper.time_precise() - start_time >= 1.2 then
    -- Clear project dirty flag (Project 0, "DIRTY", value = 0 [clean], set = true)
    reaper.GetSetProjectInfo(0, "DIRTY", 0, true)
    
    reaper.TrackCtl_SetToolTip("Ready: " .. song_name, 0, 0, true)
  else
    reaper.defer(ClearUADxDirtyState)
  end
end

reaper.defer(ClearUADxDirtyState)
