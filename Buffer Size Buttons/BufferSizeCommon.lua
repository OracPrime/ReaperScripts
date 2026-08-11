-- @noindex

local BufferSize = {}

local EXT_STATE_SECTION = "BufferSizeScripts"
local DISABLED_FX_KEY = "DisabledFX"
local MONITOR_FX_OFFSET = 0x1000000

function BufferSize.require_js_reascript_api()
  if reaper.JS_Window_Find then
    return true
  end

  reaper.ShowMessageBox(
    "This script needs js_ReaScriptAPI to be installed.\nYou can download it from ReaPack in the next window",
    "Missing dependency", 0)
  reaper.ReaPack_BrowsePackages("js_ReaScriptAPI")
  return false
end

function BufferSize.get_fx_pdc(track, fx_index)
  local retval, buffer = reaper.TrackFX_GetNamedConfigParm(track, fx_index, "pdc")
  return retval and (tonumber(buffer) or 0) or 0
end

function BufferSize.save_disabled_fx(disabled_fx)
  local lines = {}
  for _, fx_info in ipairs(disabled_fx) do
    table.insert(lines, string.format("%d|%d|%s|%s|%s|%s|%s",
      fx_info.track_index,
      fx_info.fx_index,
      fx_info.guid,
      fx_info.track_name:gsub("|", ""),
      fx_info.fx_name:gsub("|", ""),
      fx_info.is_master and "1" or "0",
      fx_info.is_monitor and "1" or "0"))
  end
  reaper.SetProjExtState(0, EXT_STATE_SECTION, DISABLED_FX_KEY, table.concat(lines, "\n"))
end

function BufferSize.load_disabled_fx()
  local retval, data = reaper.GetProjExtState(0, EXT_STATE_SECTION, DISABLED_FX_KEY)
  if retval == 0 or data == "" then
    return {}
  end

  local disabled_fx = {}
  for line in data:gmatch("[^\n]+") do
    local track_index, fx_index, guid, track_name, fx_name, is_master, is_monitor =
      line:match("(-?%d+)|(%d+)|([^|]+)|([^|]+)|([^|]+)|([01])|([01])")
    if track_index then
      table.insert(disabled_fx, {
        track_index = tonumber(track_index),
        fx_index = tonumber(fx_index),
        guid = guid,
        track_name = track_name,
        fx_name = fx_name,
        is_master = is_master == "1",
        is_monitor = is_monitor == "1"
      })
    end
  end
  return disabled_fx
end

function BufferSize.disable_fx_list(disabled_fx)
  local all_disabled_fx = BufferSize.load_disabled_fx()
  local stored_guids = {}
  for _, fx_info in ipairs(all_disabled_fx) do
    stored_guids[fx_info.guid] = true
  end

  for _, fx_info in ipairs(disabled_fx) do
    local offset = fx_info.is_monitor and MONITOR_FX_OFFSET or 0
    reaper.TrackFX_SetOffline(fx_info.track, offset + fx_info.fx_index, true)
    if not stored_guids[fx_info.guid] then
      table.insert(all_disabled_fx, fx_info)
      stored_guids[fx_info.guid] = true
    end
  end
  BufferSize.save_disabled_fx(all_disabled_fx)
end

function BufferSize.clear_disabled_fx()
  reaper.SetProjExtState(0, EXT_STATE_SECTION, DISABLED_FX_KEY, "")
end

function BufferSize.reenable_fx_list(disabled_fx)
  local reenabled_count = 0
  local master_track = reaper.GetMasterTrack(0)

  for _, fx_info in ipairs(disabled_fx) do
    local track
    if fx_info.is_master or fx_info.is_monitor then
      track = master_track
    else
      track = reaper.GetTrack(0, fx_info.track_index)
    end
    local offset = fx_info.is_monitor and MONITOR_FX_OFFSET or 0
    local fx_index = offset + fx_info.fx_index

    if track and reaper.TrackFX_GetFXGUID(track, fx_index) == fx_info.guid then
      reaper.TrackFX_SetOffline(track, fx_index, false)
      reenabled_count = reenabled_count + 1
    end
  end

  BufferSize.clear_disabled_fx()
  return reenabled_count
end

function BufferSize.update_toolbar_state(mode)
  local _, _, section, command_id = reaper.get_action_context()
  local current_key = "cmd_" .. mode
  local other_key = mode == "128" and "cmd_1024" or "cmd_128"

  reaper.SetToggleCommandState(section, command_id, 1)
  reaper.RefreshToolbar2(section, command_id)
  reaper.SetExtState(EXT_STATE_SECTION, current_key, tostring(command_id), true)

  local other_command_id = tonumber(reaper.GetExtState(EXT_STATE_SECTION, other_key))
  if other_command_id then
    reaper.SetToggleCommandState(section, other_command_id, 0)
    reaper.RefreshToolbar2(section, other_command_id)
  end
end

function BufferSize.set_buffer_size(selected_size)
  reaper.Main_OnCommand(1016, 0)
  reaper.Main_OnCommand(40099, 0)

  local preferences_title = reaper.LocalizeString("REAPER Preferences", "DLG_101", 0)
  local window = reaper.JS_Window_Find(preferences_title, true)
  if not window then
    reaper.ShowMessageBox(
      "Could not find the REAPER Preferences window.\n\nCheck the ReaScript console for details.",
      "Error", 0)
    reaper.ShowConsoleMsg("ERROR: JS_Window_Find failed to locate preferences window\n")
    return false
  end

  local debug_log = ""
  local asio_control
  local other_control
  local use_asio = true
  local child_windows = reaper.new_array({}, 255)
  reaper.JS_Window_ArrayAllChild(window, child_windows)

  for _, address in ipairs(child_windows.table()) do
    local child = reaper.JS_Window_HandleFromAddress(address)
    local id = reaper.JS_Window_GetLong(child, "ID")
    if id == 1008 then
      asio_control = child
    elseif id == 1009 then
      other_control = child
    elseif id == 1000 then
      local protocol = reaper.JS_Window_GetTitle(child)
      if protocol == "WaveOut" or protocol == "DirectSound" or protocol == "Dummy Audio"
        or protocol:find("WDM Kernel Streaming") or protocol:find("WASAPI")
        or protocol:find("Core Audio") or protocol:find("ALSA") or protocol:find("JACK") then
        use_asio = false
      end
      debug_log = debug_log .. string.format("Audio protocol: %s\n", protocol)
    elseif id == 1043 or id == 1045 then
      reaper.JS_WindowMessage_Send(child, "BM_SETCHECK", 0x1, 0, 0, 0)
    end
  end

  local control = use_asio and asio_control or other_control
  if not control then
    local control_name = use_asio and "ASIO buffer size" or "buffer size"
    reaper.ShowMessageBox(
      "Could not find the " .. control_name .. " control.\n\nDebug information has been written to the ReaScript console.",
      "Error", 0)
    reaper.ShowConsoleMsg("ERROR: Buffer size control not found\n" .. debug_log)
    reaper.JS_Window_Destroy(window)
    return false
  end

  reaper.JS_Window_SetTitle(control, selected_size)
  local control_id = reaper.JS_Window_GetLong(control, "ID")
  local control_address = tonumber(reaper.JS_Window_AddressFromHandle(control))
  reaper.JS_WindowMessage_Send(window, "WM_COMMAND", control_id | (0x0300 << 16), control_address, 0, 0)
  reaper.JS_WindowMessage_Send(window, "WM_COMMAND", 1144, 0, 0, 0)
  reaper.JS_Window_Destroy(window)

  if debug_log:find("Core Audio") or debug_log:find("ALSA") or debug_log:find("JACK") then
    reaper.ShowConsoleMsg("=== Buffer Size Script Debug Log ===\n" .. debug_log)
  end
  return true
end

return BufferSize