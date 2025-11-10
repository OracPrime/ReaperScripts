--@author OracPrime based in part on souk21 script
--@description Set block/buffer size to 128
--@version 0.1
--@changelog
--@metapackage
--@provides
--   [main] . > Set Tracking Mode

local selected_size = "128"
local PDC_THRESHOLD = 128  -- Maximum acceptable PDC in samples

if reaper.JS_Window_Find == nil then
  reaper.ShowMessageBox(
    "This script needs js_ReaScriptAPI to be installed.\nYou can download it from ReaPack in the next window",
    "Missing dependency", 0)
  reaper.ReaPack_BrowsePackages("js_ReaScriptAPI")
  return
end

-- Check for SWS extension (required for TrackFX_GetPDC)
if not reaper.APIExists("BR_GetSetTrackSendInfo") then
  reaper.ShowMessageBox(
    "This script needs the SWS extension to be installed.\nPlease install SWS from https://www.sws-extension.org/",
    "Missing dependency", 0)
  return
end

-- Function to get FX PDC (Plugin Delay Compensation)
function get_fx_pdc(track, fx_index)
  -- Get the reported latency from the FX
  -- This uses the native Reaper API (v6.20+)
  local pdc_samples = reaper.TrackFX_GetPinMappings and ({reaper.TrackFX_GetPinMappings(track, fx_index, 0, 0)})[2] or 0
  
  -- Alternative: Use the track's media item offset which includes all FX latency
  -- We need to check the FX-specific latency
  local retval, buf = reaper.TrackFX_GetNamedConfigParm(track, fx_index, "pdc")
  if retval then
    pdc_samples = tonumber(buf) or 0
  end
  
  return pdc_samples
end

-- Function to scan all tracks for high PDC FX
function scan_high_pdc_fx(include_muted_tracks)
  local high_pdc_fx = {}
  local track_count = reaper.CountTracks(0)
  
  -- Scan regular tracks
  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if track_name == "" then
      track_name = "Track " .. (i + 1)
    end
    
    -- Check if track is muted
    local is_muted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
    
    -- Skip muted tracks unless include_muted_tracks is true
    if not is_muted or include_muted_tracks then
      local fx_count = reaper.TrackFX_GetCount(track)
      for j = 0, fx_count - 1 do
        local _, fx_name = reaper.TrackFX_GetFXName(track, j, "")
        local is_enabled = reaper.TrackFX_GetEnabled(track, j)
        local pdc = get_fx_pdc(track, j)
        
        if is_enabled and pdc > PDC_THRESHOLD then
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
  end
  
  -- Scan Master track
  local master_track = reaper.GetMasterTrack(0)
  if master_track then
    local fx_count = reaper.TrackFX_GetCount(master_track)
    for j = 0, fx_count - 1 do
      local _, fx_name = reaper.TrackFX_GetFXName(master_track, j, "")
      local is_enabled = reaper.TrackFX_GetEnabled(master_track, j)
      local pdc = get_fx_pdc(master_track, j)
      
      if is_enabled and pdc > PDC_THRESHOLD then
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
    local pdc = get_fx_pdc(master_track, 0x1000000 + j)
    
    if is_enabled and pdc > PDC_THRESHOLD then
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

-- Function to show dialog with high PDC FX
function show_pdc_dialog(high_pdc_fx, message_suffix)
  local message = "The following FX have PDC > " .. PDC_THRESHOLD .. " samples:\n\n"
  
  for i, fx_info in ipairs(high_pdc_fx) do
    message = message .. string.format("[%d] %s / %s (PDC: %d)\n", 
      i, fx_info.track_name, fx_info.fx_name, fx_info.pdc)
  end
  
  message = message .. "\nDisabling high PDC FX will improve low-latency performance.\n"
  message = message .. "They can be re-enabled when switching to 1024 buffer.\n"
  if message_suffix then
    message = message .. message_suffix .. "\n"
  end
  message = message .. "\nDisable these FX and set buffer to 128?"
  
  local result = reaper.ShowMessageBox(message, "High PDC FX Detected", 3)
  -- Result: 6 = Yes (disable FX and set buffer), 7 = No (just set buffer), 2 = Cancel
  
  return result
end

-- Function to save disabled FX info to project extended state
function save_disabled_fx(high_pdc_fx)
  local disabled_data = {}
  
  for i, fx_info in ipairs(high_pdc_fx) do
    table.insert(disabled_data, {
      track_index = fx_info.track_index,
      fx_index = fx_info.fx_index,
      fx_guid = fx_info.guid,
      track_name = fx_info.track_name,
      fx_name = fx_info.fx_name,
      is_master = fx_info.is_master,
      is_monitor = fx_info.is_monitor
    })
  end
  
  -- Convert to string for storage
  local data_str = ""
  for i, item in ipairs(disabled_data) do
    data_str = data_str .. string.format("%d|%d|%s|%s|%s|%s|%s\n",
      item.track_index, item.fx_index, item.fx_guid, 
      item.track_name:gsub("|", ""), item.fx_name:gsub("|", ""),
      item.is_master and "1" or "0", item.is_monitor and "1" or "0")
  end
  
  reaper.SetProjExtState(0, "BufferSizeScripts", "DisabledFX", data_str)
end

-- Function to disable FX
function disable_fx_list(high_pdc_fx)
  for i, fx_info in ipairs(high_pdc_fx) do
    if fx_info.is_monitor then
      -- Monitor FX uses special index offset
      reaper.TrackFX_SetEnabled(fx_info.track, 0x1000000 + fx_info.fx_index, false)
    else
      reaper.TrackFX_SetEnabled(fx_info.track, fx_info.fx_index, false)
    end
  end
  save_disabled_fx(high_pdc_fx)
end

-- Check if Ctrl key is held (detects modifier keys when script is run)
local ctrl_held = reaper.JS_Mouse_GetState(4) == 4  -- 4 = Ctrl key mask
local shift_held = reaper.JS_Mouse_GetState(8) == 8  -- 8 = Shift key mask

-- Scan for high PDC FX
local high_pdc_fx = scan_high_pdc_fx(ctrl_held)

local fx_disabled_count = 0

if #high_pdc_fx > 0 then
  if shift_held then
    -- Shift-click: auto-disable without dialog
    reaper.Undo_BeginBlock()
    disable_fx_list(high_pdc_fx)
    fx_disabled_count = #high_pdc_fx
    reaper.Undo_EndBlock("Disable high PDC FX", -1)
  else
    -- Normal click: show dialog
    local message_suffix = ctrl_held and "\n(Including muted tracks)" or "\n(Muted tracks ignored - Ctrl+click to include)"
    local result = show_pdc_dialog(high_pdc_fx, message_suffix)
    
    if result == 2 then -- Cancel
      return
    elseif result == 6 then -- Yes - disable FX and set buffer
      reaper.Undo_BeginBlock()
      disable_fx_list(high_pdc_fx)
      fx_disabled_count = #high_pdc_fx
      reaper.Undo_EndBlock("Disable high PDC FX", -1)
    end
    -- If result == 7 (No), just continue to set buffer without disabling FX
  end
end

-- Set this action to ON state
local _, _, section, cmdID = reaper.get_action_context()
reaper.SetToggleCommandState(section, cmdID, 1)
reaper.RefreshToolbar2(section, cmdID)

-- Save this script's command ID for the other script to find
reaper.SetExtState("BufferSizeScripts", "cmd_128", tostring(cmdID), true)

-- Find and turn OFF the 1024 action (if it has been run before)
local cmd_1024_str = reaper.GetExtState("BufferSizeScripts", "cmd_1024")
if cmd_1024_str ~= "" then
  local cmd_1024 = tonumber(cmd_1024_str)
  if cmd_1024 then
    reaper.SetToggleCommandState(section, cmd_1024, 0)
    reaper.RefreshToolbar2(section, cmd_1024)
  end
end

reaper.Main_OnCommand(1016, 0)  -- Transport: Stop
reaper.Main_OnCommand(40099, 0) -- Open audio device preferences
local preferences_title = reaper.LocalizeString("REAPER Preferences", "DLG_128", 0)
local window = reaper.JS_Window_Find(preferences_title, true)

if window == nil then
  reaper.ShowMessageBox("Could not find REAPER Preferences window", "Error", 0)
  return
end

local hwnd_asio
local hwnd_other
local use_asio = true
local arr = reaper.new_array({}, 255)
reaper.JS_Window_ArrayAllChild(window, arr)
local addresses = arr.table()

for i = 1, #addresses do
  local hwnd = reaper.JS_Window_HandleFromAddress(addresses[i])
  local id = reaper.JS_Window_GetLong(hwnd, "ID")
  if id == 1008 then
    hwnd_asio = hwnd
  elseif id == 1009 then
    hwnd_other = hwnd
  elseif id == 1000 then
    local protocol = reaper.JS_Window_GetTitle(hwnd)
    if protocol == "WaveOut"
        or protocol == "DirectSound"
        or protocol:find("WDM Kernel Streaming")
        or protocol:find("WASAPI")
        or protocol == "Dummy Audio" then
      use_asio = false
    end
  elseif id == 1043 or id == 1045 then -- "Request block size" checkbox (1043 is osx, 1045 is win)
    reaper.JS_WindowMessage_Send(hwnd, "BM_SETCHECK", 0x1, 0, 0, 0)
  end
end

if use_asio then
  if hwnd_asio then
    reaper.JS_Window_SetTitle(hwnd_asio, selected_size)
  else
    reaper.ShowMessageBox("Could not find ASIO buffer size control", "Error", 0)
    reaper.JS_Window_Destroy(window)
    return
  end
else
  if hwnd_other then
    reaper.JS_Window_SetTitle(hwnd_other, selected_size)
  else
    reaper.ShowMessageBox("Could not find buffer size control", "Error", 0)
    reaper.JS_Window_Destroy(window)
    return
  end
end

reaper.JS_WindowMessage_Send(window, "WM_COMMAND", 1144, 0, 0, 0) -- Apply
reaper.JS_Window_Destroy(window)

-- Show status message in the status bar
local status_msg = "Buffer size set to " .. selected_size
if fx_disabled_count > 0 then
  status_msg = status_msg .. " (" .. fx_disabled_count .. " FX bypassed)"
end
reaper.Undo_OnStateChange(status_msg)
