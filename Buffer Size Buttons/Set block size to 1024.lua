--@author OracPrime based in part on souk21 script
--@description Set block/buffer size to 1024
--@version 0.2
--@changelog Refactor shared buffer-switching logic into a ReaPack companion file.

local selected_size = "1024"

local _, script_path = reaper.get_action_context()
local script_dir = script_path:match("^(.+[\\/])")
local BufferSize = dofile(script_dir .. "BufferSizeCommon.lua")

if not BufferSize.require_js_reascript_api() then return end

-- Function to show re-enable dialog
local function show_reenable_dialog(disabled_fx)
  local message = "The following FX were previously taken offline for low latency:\n\n"
  
  for i, fx_info in ipairs(disabled_fx) do
    message = message .. string.format("[%d] %s / %s\n", 
      i, fx_info.track_name, fx_info.fx_name)
  end
  
  message = message .. "\nWould you like to bring these FX back online?"
  
  local result = reaper.ShowMessageBox(message, "Re-enable Disabled FX?", 3)
  -- Result: 6 = Yes, 7 = No, 2 = Cancel
  
  return result
end

-- Check for previously disabled FX
local disabled_fx = BufferSize.load_disabled_fx()
local fx_reenabled_count = 0

-- Check if Shift key is held
local shift_held = reaper.JS_Mouse_GetState(8) == 8  -- 8 = Shift key mask

if #disabled_fx > 0 then
  if shift_held then
    -- Shift-click: bring FX online without a dialog
    reaper.Undo_BeginBlock()
    fx_reenabled_count = BufferSize.reenable_fx_list(disabled_fx)
    reaper.Undo_EndBlock("Bring previously offlined FX online", -1)
  else
    -- Normal click: show dialog
    local result = show_reenable_dialog(disabled_fx)
    
    if result == 2 then -- Cancel
      return
    elseif result == 6 then -- Yes - bring FX online
      reaper.Undo_BeginBlock()
      fx_reenabled_count = BufferSize.reenable_fx_list(disabled_fx)
      reaper.Undo_EndBlock("Bring previously offlined FX online", -1)
    else
      -- User chose No, clear the list anyway
      BufferSize.clear_disabled_fx()
    end
  end
end

BufferSize.update_toolbar_state(selected_size)
if not BufferSize.set_buffer_size(selected_size) then return end

-- Show status message in the status bar
local status_msg = "Buffer size set to " .. selected_size
if fx_reenabled_count > 0 then
  status_msg = status_msg .. " (" .. fx_reenabled_count .. " FX online)"
end
reaper.Undo_OnStateChange(status_msg)
