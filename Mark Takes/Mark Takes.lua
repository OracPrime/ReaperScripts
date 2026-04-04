-- @description Vocal Grading Console
-- @author Gemini
-- @version 1.2

-- Check for ReaImGui API
if not reaper.ImGui_CreateContext then
    reaper.MB("ReaImGui is not installed or out of date. Please install it via ReaPack.", "Error", 0)
    return
end

local ctx = reaper.ImGui_CreateContext('Vocal Grader')
local sans_serif = reaper.ImGui_CreateFont('sans-serif', 15)
reaper.ImGui_Attach(ctx, sans_serif)

local buttons = {
    { label = "Pitch +", color = 0x00FF00FF, name = "Pitch Good" },
    { label = "Pitch -", color = 0xFF0000FF, name = "Pitch Bad" },
    { label = "Time +",  color = 0x00FFFFFF, name = "Timing Good" },
    { label = "Time -",  color = 0xFF00FFFF, name = "Timing Bad" },
    { label = "Tone +",  color = 0xFFFF00FF, name = "Tone Good" },
    { label = "Tone -",  color = 0xFFA500FF, name = "Tone Bad" }
}

local active_markers = {} 

function GetTargetTake()
    local play_pos = reaper.GetPlayPosition2()
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then return nil end
    
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local i_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local i_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        
        if play_pos >= i_start and play_pos <= (i_start + i_len) then
            -- Logic: Target the audible (unmuted) item in Fixed Lanes
            if reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 0 then
                return reaper.GetActiveTake(item), i_start
            end
        end
    end
    return nil, nil
end

function MarkArea(btn_idx)
    local take, item_start = GetTargetTake()
    if not take then return end
    
    local play_pos = reaper.GetPlayPosition2()
    local relative_pos = play_pos - item_start
    local btn = buttons[btn_idx]

    if not active_markers[btn_idx] then
        -- Create new marker
        local idx = reaper.SetTakeMarker(take, -1, btn.name, relative_pos, btn.color)
        active_markers[btn_idx] = { take = take, idx = idx, start = relative_pos, btn = btn }
    else
        -- Update existing marker duration
        local m = active_markers[btn_idx]
        if m.take == take then -- Ensure we haven't crossed into a new item
            reaper.SetTakeMarker(m.take, m.idx, m.btn.name, m.start, m.btn.color, relative_pos - m.start)
        end
    end
end

function ClearTimeSelection()
    local start_ts, end_ts = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if start_ts == end_ts then return end
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then return end
    
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local take = reaper.GetActiveTake(item)
        local i_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        if take then
            for j = reaper.GetNumTakeMarkers(take) - 1, 0, -1 do
                local m_pos = reaper.GetTakeMarker(take, j)
                if (i_pos + m_pos) >= start_ts and (i_pos + m_pos) <= end_ts then
                    reaper.DeleteTakeMarker(take, j)
                end
            end
        end
    end
end

function PurgeGhostMarkers()
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then return end
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        -- In Fixed Lanes, we purge items that are muted (not in the current comp)
        if reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 1 then
            local take = reaper.GetActiveTake(item)
            if take then
                for j = reaper.GetNumTakeMarkers(take) - 1, 0, -1 do
                    reaper.DeleteTakeMarker(take, j)
                end
            end
        end
    end
end

function loop()
    reaper.ImGui_PushFont(ctx, sans_serif)
    -- Set window to stay on top
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 0.8)
    local visible, open = reaper.ImGui_Begin(ctx, 'Vocal Grader', true, reaper.ImGui_WindowFlags_AlwaysAutoResize())
    
    if visible then
        reaper.ImGui_Text(ctx, "Hold button to mark duration:")
        for i, btn in ipairs(buttons) do
            -- Convert hex to RGBA for ImGui style
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), btn.color)
            reaper.ImGui_Button(ctx, btn.label, 120, 60)
            
            if reaper.ImGui_IsItemActive(ctx) then
                MarkArea(i)
            elseif reaper.ImGui_IsItemDeactivated(ctx) then
                active_markers[i] = nil
            end
            
            reaper.ImGui_PopStyleColor(ctx)
            if i % 2 == 0 then reaper.ImGui_Spacing(ctx) else reaper.ImGui_SameLine(ctx) end
        end
        
        reaper.ImGui_SeparatorText(ctx, 'Cleanup')
        if reaper.ImGui_Button(ctx, 'Clear Time Selection', -1, 35) then ClearTimeSelection() end
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x880000FF)
        if reaper.ImGui_Button(ctx, 'Purge Muted Lane Markers', -1, 35) then PurgeGhostMarkers() end
        reaper.ImGui_PopStyleColor(ctx)
        
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopFont(ctx)
    if open then reaper.defer(loop) end
end

reaper.defer(loop)