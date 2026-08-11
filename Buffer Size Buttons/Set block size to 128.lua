--@author OracPrime based in part on souk21 script
--@description Set block/buffer size to 128
--@version 0.2
--@changelog Refactor shared buffer-switching logic into a ReaPack companion file.
-- @provides
--   Set block size to 1024.lua
--   BufferSizeCommon.lua

local selected_size = "128"
local PDC_THRESHOLD = 128  -- Maximum acceptable PDC in samples

local _, script_path = reaper.get_action_context()
local script_dir = script_path:match("^(.+[\\/])")
local BufferSize = dofile(script_dir .. "BufferSizeCommon.lua")

if not BufferSize.require_js_reascript_api() then return end

-- Function to scan all tracks for high PDC FX
local function scan_high_pdc_fx()
  local high_pdc_fx = {}
  local track_count = reaper.CountTracks(0)
  
  -- Scan regular tracks
  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if track_name == "" then
      track_name = "Track " .. (i + 1)
    end
    
    local fx_count = reaper.TrackFX_GetCount(track)
    for j = 0, fx_count - 1 do
      local _, fx_name = reaper.TrackFX_GetFXName(track, j, "")
      local is_enabled = reaper.TrackFX_GetEnabled(track, j)
      local is_offline = reaper.TrackFX_GetOffline(track, j)
      local pdc = BufferSize.get_fx_pdc(track, j)

      if is_enabled and not is_offline and pdc > PDC_THRESHOLD then
        table.insert(high_pdc_fx, {
          track = track,
          track_index = i,
          track_name = track_name,
          fx_index = j,
          fx_name = fx_name,
          pdc = pdc,
          guid = reaper.TrackFX_GetFXGUID(track, j),
          is_master = false,
          is_monitor = false
        })
      end
    end
  end
  
  -- Scan Master track
  local master_track = reaper.GetMasterTrack(0)
  if master_track then
    local fx_count = reaper.TrackFX_GetCount(master_track)
    for j = 0, fx_count - 1 do
      local _, fx_name = reaper.TrackFX_GetFXName(master_track, j, "")
      local is_enabled = reaper.TrackFX_GetEnabled(master_track, j)
      local is_offline = reaper.TrackFX_GetOffline(master_track, j)
      local pdc = BufferSize.get_fx_pdc(master_track, j)
      
      if is_enabled and not is_offline and pdc > PDC_THRESHOLD then
        table.insert(high_pdc_fx, {
          track = master_track,
          track_index = -1,  -- Master track identifier
          track_name = "Master",
          fx_index = j,
          fx_name = fx_name,
          pdc = pdc,
          guid = reaper.TrackFX_GetFXGUID(master_track, j),
          is_master = true,
          is_monitor = false
        })
      end
    end
  end
  
  -- Scan Monitor FX
  local monitor_fx_count = reaper.TrackFX_GetRecCount(master_track)
  for j = 0, monitor_fx_count - 1 do
    local _, fx_name = reaper.TrackFX_GetFXName(master_track, 0x1000000 + j, "")
    local is_enabled = reaper.TrackFX_GetEnabled(master_track, 0x1000000 + j)
    local is_offline = reaper.TrackFX_GetOffline(master_track, 0x1000000 + j)
    local pdc = BufferSize.get_fx_pdc(master_track, 0x1000000 + j)
    
    if is_enabled and not is_offline and pdc > PDC_THRESHOLD then
      table.insert(high_pdc_fx, {
        track = master_track,
        track_index = -2,  -- Monitor FX identifier
        track_name = "Monitor FX",
        fx_index = j,
        fx_name = fx_name,
        pdc = pdc,
        guid = reaper.TrackFX_GetFXGUID(master_track, 0x1000000 + j),
        is_master = false,
        is_monitor = true
      })
    end
  end
  
  return high_pdc_fx
end

local function show_pdc_dialog(high_pdc_fx)
  local message = "The following FX have PDC > " .. PDC_THRESHOLD .. " samples:\n\n"
  
  for i, fx_info in ipairs(high_pdc_fx) do
    message = message .. string.format("[%d] %s / %s (PDC: %d)\n", 
      i, fx_info.track_name, fx_info.fx_name, fx_info.pdc)
  end
  
  message = message .. "\nOfflining high-PDC FX removes their delay compensation for low-latency monitoring.\n"
  message = message .. "They can be brought back online when switching to 1024 buffer.\n"
  message = message .. "\nTake these FX offline and set buffer to 128?"
  
  local result = reaper.ShowMessageBox(message, "High PDC FX Detected", 3)
  -- Result: 6 = Yes (offline FX and set buffer), 7 = No (just set buffer), 2 = Cancel
  
  return result
end

local shift_held = reaper.JS_Mouse_GetState(8) == 8  -- 8 = Shift key mask

-- Scan for high PDC FX
local high_pdc_fx = scan_high_pdc_fx()

local fx_disabled_count = 0

if #high_pdc_fx > 0 then
  if shift_held then
    -- Shift-click: take FX offline without a dialog
    reaper.Undo_BeginBlock()
    BufferSize.disable_fx_list(high_pdc_fx)
    fx_disabled_count = #high_pdc_fx
    reaper.Undo_EndBlock("Take high PDC FX offline", -1)
  else
    -- Normal click: show dialog
    local result = show_pdc_dialog(high_pdc_fx)
    
    if result == 2 then -- Cancel
      return
    elseif result == 6 then -- Yes - take FX offline and set buffer
      reaper.Undo_BeginBlock()
      BufferSize.disable_fx_list(high_pdc_fx)
      fx_disabled_count = #high_pdc_fx
      reaper.Undo_EndBlock("Take high PDC FX offline", -1)
    end
    -- If result == 7 (No), just continue to set buffer without disabling FX
  end
end

BufferSize.update_toolbar_state(selected_size)
if not BufferSize.set_buffer_size(selected_size) then return end

-- Show status message in the status bar
local status_msg = "Buffer size set to " .. selected_size
if fx_disabled_count > 0 then
  status_msg = status_msg .. " (" .. fx_disabled_count .. " FX offlined)"
end
reaper.Undo_OnStateChange(status_msg)
