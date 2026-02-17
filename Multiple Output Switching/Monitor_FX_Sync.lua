local master = reaper.GetMasterTrack(0)
local count = reaper.TrackFX_GetRecCount(master)

-- STEP 1: Get the actual Command IDs from your Action List
-- To find these: Open Action List, right-click your script, 
-- and select "Copy selected action command ID"
local cmdID_34 = reaper.NamedCommandLookup("_RS46939d41c7d21869788ff30b8649381112d13820")
local cmdID_56 = reaper.NamedCommandLookup("_RS57f1c610fb9593a3cfaab07c480f7a85f2f4d139")
local cmdID_78 = reaper.NamedCommandLookup("_RS9183dbb753fd9e9ba1d76e67e462722dc5aefaac") 

-- STEP 2: Logic to check and sync
for i = 0, count - 1 do
    local monitor_index = i + 0x1000000
    local _, name = reaper.TrackFX_GetFXName(master, monitor_index, "")
    local is_offline = reaper.TrackFX_GetOffline(master, monitor_index)
    local button_state = is_offline and 0 or 1
    
    if name:find("Monitor34") then
        reaper.SetToggleCommandState(0, cmdID_34, button_state)
        reaper.RefreshToolbar2(0, cmdID_34)
    elseif name:find("Monitor56") then
        reaper.SetToggleCommandState(0, cmdID_56, button_state)
        reaper.RefreshToolbar2(0, cmdID_56)
    elseif name:find("Monitor78") then
        reaper.SetToggleCommandState(0, cmdID_78, button_state)
        reaper.RefreshToolbar2(0, cmdID_78)
    end
end
