-- @description Ensure that all selected tracks have the "VU Meter (ZenoMod)" plugin in their Input FX chain, and set it to "Summed" mode. If the plugin is missing, it will be added automatically.  ZenoMod VU available from ReaPack
-- @author OracPrime
-- @version 0.1

-- Get the first selected track
local track = reaper.GetSelectedTrack(0, 0)

if track then
    -- Normalize our target to lowercase to guarantee a match
    local target_name = "vu meter (zenomod)"
    local fx_index = -1
    
    -- 1. Scan the Input FX chain manually using the validated math
    local num_input_fx = reaper.TrackFX_GetRecCount(track)
    for i = 0, num_input_fx - 1 do
        local current_fx_idx = 0x1000000 + i
        local _, current_name = reaper.TrackFX_GetFXName(track, current_fx_idx, "")
        
        -- Force the retrieved name to lowercase to eliminate case mismatching
        if current_name:lower():find(target_name, 1, true) then
            fx_index = current_fx_idx
            break
        end
    end
    
    -- 2. If the plugin is missing, append it to the end of the Input FX chain
    if fx_index == -1 then
        fx_index = reaper.TrackFX_AddByName(track, "JS: VU Meter (ZenoMod)", true, 0x1000000 + num_input_fx)
    end
    
    -- 3. Set the mode to "Summed" (Slider 0, Value 1)
    if fx_index and fx_index >= 0 then
        reaper.TrackFX_SetParam(track, fx_index, 0, 1)
    else
        reaper.MB("Error: Could not target or add the plugin.", "Error", 0)
    end
else
    reaper.MB("Please select a track first.", "Error", 0)
end
