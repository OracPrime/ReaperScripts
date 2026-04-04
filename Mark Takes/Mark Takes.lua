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
    { label = "Expr +",  color = 0xFFFF00FF, name = "Expression Good" },
    { label = "Expr -",  color = 0xFFA500FF, name = "Expression Bad" }
}

local active_markers = {} 

function GetTargetTake()
    local play_pos = reaper.GetPlayPosition2()
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then return nil end
    
    -- Determine which lane(s) are set to play
    local num_lanes = reaper.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES")
    local playing_lanes = {}
    for lane = 0, num_lanes - 1 do
        local plays = reaper.GetMediaTrackInfo_Value(track, "C_LANEPLAYS:" .. lane)
        if plays == 1 then
            playing_lanes[lane] = true
        end
    end
    
    local item_count = reaper.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local i_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local i_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        
        if play_pos >= i_start and play_pos <= (i_start + i_len) then
            local item_lane = reaper.GetMediaItemInfo_Value(item, "I_FIXEDLANE")
            if playing_lanes[item_lane] then
                local take = reaper.GetActiveTake(item)
                return take, i_start
            end
        end
    end
    return nil, nil
end

function IsTransportActive()
    local state = reaper.GetPlayState()
    return (state & 1 ~= 0) or (state & 4 ~= 0) -- playing or recording
end

function MarkArea(btn_idx)
    if not IsTransportActive() then return end
    local take, item_start = GetTargetTake()
    if not take then return end
    
    local play_pos = reaper.GetPlayPosition2()
    local src_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    local srcpos = (play_pos - item_start) + src_offset
    local btn = buttons[btn_idx]

    if not active_markers[btn_idx] then
        -- Create new marker (convert ImGui RGBA color to native REAPER color)
        local r = (btn.color >> 24) & 0xFF
        local g = (btn.color >> 16) & 0xFF
        local b = (btn.color >> 8) & 0xFF
        local native_color = reaper.ColorToNative(r, g, b) | 0x1000000
        local idx = reaper.SetTakeMarker(take, -1, btn.name, srcpos, native_color)
        -- Read back the chunk to capture REAPER's exact position string for later matching
        local item = reaper.GetMediaItemTake_Item(take)
        local _, chunk = reaper.GetItemStateChunk(item, "", false)
        local chunk_pos_str
        for line in chunk:gmatch("[^\n]+") do
            local pos_str = line:match('TKM (%S+) "' .. btn.name .. '" ' .. native_color)
            if pos_str then chunk_pos_str = pos_str end -- last match = most recently added
        end
        active_markers[btn_idx] = { take = take, idx = idx, start = srcpos, btn = btn, native_color = native_color, chunk_pos = chunk_pos_str }
    else
        -- Update existing marker duration via state chunk (SetTakeMarker ignores 6th arg)
        local m = active_markers[btn_idx]
        if m.take == take and m.chunk_pos then
            local duration = srcpos - m.start
            local item = reaper.GetMediaItemTake_Item(m.take)
            local _, chunk = reaper.GetItemStateChunk(item, "", false)
            -- Use the exact position string captured from REAPER's chunk
            local escaped_name = m.btn.name:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
            local pattern = 'TKM ' .. m.chunk_pos .. ' "' .. escaped_name .. '" ' .. m.native_color .. ' %S+'
            local replacement = string.format('TKM %s "%s" %d %s',
                m.chunk_pos, m.btn.name, m.native_color,
                string.format("%.14g", duration))
            local new_chunk, count = chunk:gsub(pattern, replacement)
            if count > 0 then
                reaper.SetItemStateChunk(item, new_chunk, false)
            end
        end
    end
    reaper.UpdateArrange()
    reaper.UpdateTimeline()
end

function ClearTimeSelection()
    local start_ts, end_ts = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if start_ts == end_ts then return end
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then return end
    
    reaper.Undo_BeginBlock()
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
    reaper.Undo_EndBlock("Clear take markers in time selection", -1)
    reaper.UpdateArrange()
end

function PurgeGhostMarkers()
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then return end
    reaper.Undo_BeginBlock()
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
    reaper.Undo_EndBlock("Purge muted lane markers", -1)
    reaper.UpdateArrange()
end

function loop()
    reaper.ImGui_PushFont(ctx, sans_serif, 0)
    -- Set window to stay on top
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 0.8)
    local visible, open = reaper.ImGui_Begin(ctx, 'Vocal Grader', true,
        reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoNavInputs())
    
    if visible then
        -- Forward spacebar to REAPER transport (Play/Stop)
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
            reaper.Main_OnCommand(40044, 0) -- Transport: Play/Stop
        end
        reaper.ImGui_Text(ctx, "Hold button to mark duration:")
        for i, btn in ipairs(buttons) do
            -- Style button with darkened hover/active variants and dark text for contrast
            local r = (btn.color >> 24) & 0xFF
            local g = (btn.color >> 16) & 0xFF
            local b = (btn.color >> 8) & 0xFF
            local a = btn.color & 0xFF
            local hovered = (math.floor(r*0.8) << 24) | (math.floor(g*0.8) << 16) | (math.floor(b*0.8) << 8) | a
            local active  = (math.floor(r*0.6) << 24) | (math.floor(g*0.6) << 16) | (math.floor(b*0.6) << 8) | a
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), btn.color)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), hovered)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), active)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x000000FF)
            reaper.ImGui_Button(ctx, btn.label, 120, 60)
            
            if reaper.ImGui_IsItemActive(ctx) then
                MarkArea(i)
            elseif reaper.ImGui_IsItemDeactivated(ctx) then
                active_markers[i] = nil
            end
            
            reaper.ImGui_PopStyleColor(ctx, 4)
            if i % 2 == 0 then reaper.ImGui_Spacing(ctx) else reaper.ImGui_SameLine(ctx) end
        end
        
        reaper.ImGui_SeparatorText(ctx, 'Cleanup')
        if reaper.ImGui_Button(ctx, 'Clear Time Selection', -1, 35) then ClearTimeSelection() end
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x880000FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xAA0000FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x660000FF)
        if reaper.ImGui_Button(ctx, 'Purge Muted Lane Markers', -1, 35) then PurgeGhostMarkers() end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopFont(ctx)
    if open then reaper.defer(loop) end
end

reaper.defer(loop)