-- Symmetrical Monitor Controller
local master = reaper.GetMasterTrack(0)
local count = reaper.TrackFX_GetRecCount(master)
local _, _, section, current_cmdID = reaper.get_action_context()

-- 1. DEFINE MAPPINGS (Fill these in once)
local layout = {
    [reaper.NamedCommandLookup("_RS46939d41c7d21869788ff30b8649381112d13820")] = "Monitor34",
    [reaper.NamedCommandLookup("_RS57f1c610fb9593a3cfaab07c480f7a85f2f4d139")] = "Monitor56",
    [reaper.NamedCommandLookup("_RS9183dbb753fd9e9ba1d76e67e462722dc5aefaac")] = "Monitor78"
}

-- 2. CHECK MODIFIER (Ctrl key)
local is_ctrl = (reaper.JS_Mouse_GetState(4) & 4) == 4

-- 3. THE LOGIC
for cmdID, fx_name in pairs(layout) do
    -- Find the FX index for this specific map entry
    local target_idx = -1
    for i = 0, count - 1 do
        local idx = i + 0x1000000
        local _, name = reaper.TrackFX_GetFXName(master, idx, "")
        if name:find(fx_name) then target_idx = idx break end
    end

    if target_idx ~= -1 then
        if is_ctrl then
            -- Independent Toggle: Only affect the button that was actually clicked
            if cmdID == current_cmdID then
                local is_offline = reaper.TrackFX_GetOffline(master, target_idx)
                local new_state = not is_offline -- Flip current
                reaper.TrackFX_SetOffline(master, target_idx, new_state)
                reaper.SetToggleCommandState(section, cmdID, new_state and 0 or 1)
            end
        else
            -- Solo Mode: Turn clicked ON, turn others OFF
            local should_be_online = (cmdID == current_cmdID)
            reaper.TrackFX_SetOffline(master, target_idx, not should_be_online)
            reaper.SetToggleCommandState(section, cmdID, should_be_online and 1 or 0)
        end
    end
end

reaper.RefreshToolbar2(section, 0)
