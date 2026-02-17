--@author OracPrime based in part on souk21 script
--@description Set block/buffer size to 1024
--@version 0.1
--@changelog
--@metapackage
--@provides
--   [main] . > Set Tracking Mode

local selected_size = "1024"

if reaper.JS_Window_Find == nil then
  reaper.ShowMessageBox(
    "This script needs js_ReaScriptAPI to be installed.\nYou can download it from ReaPack in the next window",
    "Missing dependency", 0)
  reaper.ReaPack_BrowsePackages("js_ReaScriptAPI")
  return
end

-- Function to load disabled FX info from project extended state
function load_disabled_fx()
  local retval, data_str = reaper.GetProjExtState(0, "BufferSizeScripts", "DisabledFX")
  
  if retval == 0 or data_str == "" then
    return {}
  end
  
  local disabled_fx = {}
  for line in data_str:gmatch("[^\n]+") do
    local track_idx, fx_idx, guid, track_name, fx_name, is_master, is_monitor = 
      line:match("(%d+)|(%d+)|([^|]+)|([^|]+)|([^|]+)|([01])|([01])")
    if track_idx then
      table.insert(disabled_fx, {
        track_index = tonumber(track_idx),
        fx_index = tonumber(fx_idx),
        fx_guid = guid,
        track_name = track_name,
        fx_name = fx_name,
        is_master = is_master == "1",
        is_monitor = is_monitor == "1"
      })
    end
  end
  
  return disabled_fx
end

-- Function to show re-enable dialog
function show_reenable_dialog(disabled_fx)
  local message = "The following FX were previously disabled for low latency:\n\n"
  
  for i, fx_info in ipairs(disabled_fx) do
    message = message .. string.format("[%d] %s / %s\n", 
      i, fx_info.track_name, fx_info.fx_name)
  end
  
  message = message .. "\nWould you like to re-enable these FX?"
  
  local result = reaper.ShowMessageBox(message, "Re-enable Disabled FX?", 3)
  -- Result: 6 = Yes, 7 = No, 2 = Cancel
  
  return result
end

-- Function to re-enable FX and verify by GUID
function reenable_fx_list(disabled_fx)
  local reenabled_count = 0
  local master_track = reaper.GetMasterTrack(0)
  
  for i, fx_info in ipairs(disabled_fx) do
    local track
    local fx_index_offset = 0
    
    if fx_info.is_monitor then
      -- Monitor FX
      track = master_track
      fx_index_offset = 0x1000000
    elseif fx_info.is_master then
      -- Master track
      track = master_track
    else
      -- Regular track
      track = reaper.GetTrack(0, fx_info.track_index)
    end
    
    if track then
      -- Verify the FX is still at the same position by checking GUID
      local current_guid = reaper.TrackFX_GetFXGUID(track, fx_index_offset + fx_info.fx_index)
      if current_guid == fx_info.fx_guid then
        reaper.TrackFX_SetEnabled(track, fx_index_offset + fx_info.fx_index, true)
        reenabled_count = reenabled_count + 1
      end
    end
  end
  
  -- Clear the stored disabled FX list
  reaper.SetProjExtState(0, "BufferSizeScripts", "DisabledFX", "")
  
  return reenabled_count
end

-- Check for previously disabled FX
local disabled_fx = load_disabled_fx()
local fx_reenabled_count = 0

-- Check if Shift key is held
local shift_held = reaper.JS_Mouse_GetState(8) == 8  -- 8 = Shift key mask

if #disabled_fx > 0 then
  if shift_held then
    -- Shift-click: auto-enable without dialog
    reaper.Undo_BeginBlock()
    fx_reenabled_count = reenable_fx_list(disabled_fx)
    reaper.Undo_EndBlock("Re-enable previously disabled FX", -1)
  else
    -- Normal click: show dialog
    local result = show_reenable_dialog(disabled_fx)
    
    if result == 2 then -- Cancel
      return
    elseif result == 6 then -- Yes - re-enable FX
      reaper.Undo_BeginBlock()
      fx_reenabled_count = reenable_fx_list(disabled_fx)
      reaper.Undo_EndBlock("Re-enable previously disabled FX", -1)
    else
      -- User chose No, clear the list anyway
      reaper.SetProjExtState(0, "BufferSizeScripts", "DisabledFX", "")
    end
  end
end

-- Set this action to ON state
local _, _, section, cmdID = reaper.get_action_context()
reaper.SetToggleCommandState(section, cmdID, 1)
reaper.RefreshToolbar2(section, cmdID)

-- Save this script's command ID for the other script to find
reaper.SetExtState("BufferSizeScripts", "cmd_1024", tostring(cmdID), true)

-- Find and turn OFF the 128 action (if it has been run before)
local cmd_128_str = reaper.GetExtState("BufferSizeScripts", "cmd_128")
if cmd_128_str ~= "" then
  local cmd_128 = tonumber(cmd_128_str)
  if cmd_128 then
    reaper.SetToggleCommandState(section, cmd_128, 0)
    reaper.RefreshToolbar2(section, cmd_128)
  end
end

reaper.Main_OnCommand(1016, 0)  -- Transport: Stop
reaper.Main_OnCommand(40099, 0) -- Open audio device preferences
local preferences_title = reaper.LocalizeString("REAPER Preferences", "DLG_128", 0)
local window = reaper.JS_Window_Find(preferences_title, true)

if window == nil then
  reaper.ShowMessageBox("Could not find REAPER Preferences window.\n\nThis may indicate:\n- The preferences window failed to open\n- js_ReaScriptAPI compatibility issue on your platform\n\nPlease check the ReaScript console for details.", "Error", 0)
  reaper.ShowConsoleMsg("ERROR: JS_Window_Find failed to locate preferences window\n")
  reaper.ShowConsoleMsg("Preferences title searched: " .. preferences_title .. "\n")
  return
end

-- Debug logging - only shown if window was found but other issues occur
local debug_log = ""

local hwnd_asio
local hwnd_other
local use_asio = true
local arr = reaper.new_array({}, 255)
reaper.JS_Window_ArrayAllChild(window, arr)
local addresses = arr.table()

debug_log = debug_log .. string.format("Found %d child windows\n", #addresses)

for i = 1, #addresses do
  local hwnd = reaper.JS_Window_HandleFromAddress(addresses[i])
  local id = reaper.JS_Window_GetLong(hwnd, "ID")
  if id == 1008 then
    hwnd_asio = hwnd
    debug_log = debug_log .. "Found ASIO buffer control (ID 1008)\n"
  elseif id == 1009 then
    hwnd_other = hwnd
    debug_log = debug_log .. "Found non-ASIO buffer control (ID 1009)\n"
  elseif id == 1000 then
    local protocol = reaper.JS_Window_GetTitle(hwnd)
    debug_log = debug_log .. string.format("Found audio protocol: %s\n", protocol)
    if protocol == "WaveOut"
        or protocol == "DirectSound"
        or protocol:find("WDM Kernel Streaming")
        or protocol:find("WASAPI")
        or protocol == "Dummy Audio" then
      use_asio = false
    elseif protocol:find("Core Audio") or protocol:find("ALSA") or protocol:find("JACK") then
      -- Mac/Linux audio systems
      use_asio = false
      debug_log = debug_log .. "Detected Mac/Linux audio system\n"
    end
  elseif id == 1043 or id == 1045 then -- "Request block size" checkbox (1043 is osx, 1045 is win)
    reaper.JS_WindowMessage_Send(hwnd, "BM_SETCHECK", 0x1, 0, 0, 0)
    debug_log = debug_log .. string.format("Checked 'Request block size' checkbox (ID %d)\n", id)
  end
end

if use_asio then
  if hwnd_asio then
    reaper.JS_Window_SetTitle(hwnd_asio, selected_size)
    debug_log = debug_log .. string.format("Set ASIO buffer to %s\n", selected_size)
  else
    reaper.ShowMessageBox("Could not find ASIO buffer size control.\n\nThis may indicate:\n- Unexpected preferences window layout\n- Platform-specific UI differences\n\nDebug info has been written to the ReaScript console.", "Error", 0)
    reaper.ShowConsoleMsg("ERROR: ASIO buffer control not found\n")
    reaper.ShowConsoleMsg(debug_log)
    reaper.JS_Window_Destroy(window)
    return
  end
else
  if hwnd_other then
    reaper.JS_Window_SetTitle(hwnd_other, selected_size)
    debug_log = debug_log .. string.format("Set non-ASIO buffer to %s\n", selected_size)
  else
    reaper.ShowMessageBox("Could not find buffer size control.\n\nThis may indicate:\n- Unexpected preferences window layout\n- Platform-specific UI differences\n\nDebug info has been written to the ReaScript console.", "Error", 0)
    reaper.ShowConsoleMsg("ERROR: Buffer control (ID 1009) not found\n")
    reaper.ShowConsoleMsg(debug_log)
    reaper.JS_Window_Destroy(window)
    return
  end
end

reaper.JS_WindowMessage_Send(window, "WM_COMMAND", 1144, 0, 0, 0) -- Apply
debug_log = debug_log .. "Applied settings\n"
reaper.JS_Window_Destroy(window)

-- Show status message in the status bar
local status_msg = "Buffer size set to " .. selected_size
if fx_reenabled_count > 0 then
  status_msg = status_msg .. " (" .. fx_reenabled_count .. " FX re-enabled)"
end
reaper.Undo_OnStateChange(status_msg)

-- Only output debug log if something went wrong (for Mac/Linux troubleshooting)
-- Check if we detected a non-Windows platform
if debug_log:find("Core Audio") or debug_log:find("ALSA") or debug_log:find("JACK") then
  reaper.ShowConsoleMsg("=== Buffer Size Script Debug Log ===\n")
  reaper.ShowConsoleMsg(debug_log)
  reaper.ShowConsoleMsg("=====================================\n")
end
