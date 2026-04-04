-- @description Take Marking Tool
-- @author David Christensen
-- @version 1.2

-- Check for ReaImGui API
if not reaper.ImGui_CreateContext then
    reaper.MB("ReaImGui is not installed or out of date. Please install it via ReaPack.", "Error", 0)
    return
end

local ctx = reaper.ImGui_CreateContext('Mark Takes')
local main_font = reaper.ImGui_CreateFont('sans-serif', 0)
reaper.ImGui_Attach(ctx, main_font)

local buttons = {
    { label = "Pitch +", color = 0x66FF66FF, name = "Pitch Good" },
    { label = "Pitch -", color = 0xFF5555FF, name = "Pitch Bad" },
    { label = "Time +",  color = 0x66FFFFFF, name = "Timing Good" },
    { label = "Time -",  color = 0xFF66FFFF, name = "Timing Bad" },
    { label = "Expr +",  color = 0xFFFF66FF, name = "Expression Good" },
    { label = "Expr -",  color = 0xFFBB44FF, name = "Expression Bad" }
}

local active_markers = {} 
local target_source_lane = true
local marker_counter = 0
local marker_log = {}  -- { { tag, color, take, srcpos, item } ... }
local rename_idx = nil
local rename_buf = ''

-- Populate review list from existing take markers on the selected track
local function LoadExistingMarkers()
    marker_log = {}
    marker_counter = 0
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then return end
    -- Build lookups: button name -> ImGui color, native color -> ImGui color
    local name_to_color = {}
    local native_to_imgui = {}
    for _, btn in ipairs(buttons) do
        name_to_color[btn.name] = btn.color
        local r = (btn.color >> 24) & 0xFF
        local g = (btn.color >> 16) & 0xFF
        local b = (btn.color >> 8) & 0xFF
        local nc = reaper.ColorToNative(r, g, b) | 0x1000000
        native_to_imgui[nc] = btn.color
    end
    local max_counter = 0
    local seen = {}  -- deduplicate by tag name
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local take = reaper.GetActiveTake(item)
        if take then
            for j = 0, reaper.GetNumTakeMarkers(take) - 1 do
                local srcpos, name, marker_color = reaper.GetTakeMarker(take, j)
                if not seen[name] then
                    -- Try name pattern first
                    local base, num = name:match("^(.+) #(%d+)$")
                    local imgui_color
                    if base and name_to_color[base] then
                        imgui_color = name_to_color[base]
                        local n = tonumber(num)
                        if n > max_counter then max_counter = n end
                    elseif native_to_imgui[marker_color] then
                        -- Renamed marker — match by color
                        imgui_color = native_to_imgui[marker_color]
                    end
                    if imgui_color then
                        seen[name] = true
                        table.insert(marker_log, {
                            tag = name, color = imgui_color,
                            take = take, srcpos = srcpos, item = item
                        })
                    end
                end
            end
        end
    end
    marker_counter = max_counter
    -- Sort by source position so list is in chronological order
    table.sort(marker_log, function(a, b) return a.srcpos < b.srcpos end)
end
LoadExistingMarkers()

-- Timing constants (seconds)
local REACTION_TIME = 0.5   -- backdate marker start to compensate for human reaction time
local DEFAULT_LENGTH = 1.0  -- minimum marker length for a quick click

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

function GetSourceTake()
    local play_pos = reaper.GetPlayPosition2()
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then return nil end
    
    -- Parse LINKEDLANE entries from track chunk to find comp source lane at play position
    local _, chunk = reaper.GetTrackStateChunk(track, "", false)
    local source_lane = nil
    local comp_seg_start = nil
    for line in chunk:gmatch("[^\n]+") do
        local ll_start, ll_end, ll_lane = line:match("LINKEDLANE (%S+) (%S+) (%S+)")
        if ll_start then
            ll_start, ll_end, ll_lane = tonumber(ll_start), tonumber(ll_end), tonumber(ll_lane)
            if play_pos >= ll_start and play_pos <= ll_end then
                source_lane = ll_lane
                comp_seg_start = ll_start
                break
            end
        end
    end
    if not source_lane then return nil end
    
    -- Find the item on the source lane at the play position
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local i_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local i_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if play_pos >= i_start and play_pos <= (i_start + i_len) then
            local item_lane = reaper.GetMediaItemInfo_Value(item, "I_FIXEDLANE")
            if item_lane == source_lane then
                return reaper.GetActiveTake(item), i_start, comp_seg_start
            end
        end
    end
    return nil, nil
end

function IsTransportActive()
    local state = reaper.GetPlayState()
    return (state & 1 ~= 0) or (state & 4 ~= 0) -- playing or recording
end

function SeekPlayback(time)
    local cur = reaper.GetCursorPosition()
    reaper.SetEditCurPos(time, false, true)
    reaper.SetEditCurPos(cur, false, false)
end

-- Helper: create a take marker and capture its chunk position string
local function CreateMarkerOnTake(take, srcpos, tag, native_color)
    local idx = reaper.SetTakeMarker(take, -1, tag, srcpos, native_color)
    local item = reaper.GetMediaItemTake_Item(take)
    local _, chunk = reaper.GetItemStateChunk(item, "", false)
    local chunk_pos_str
    local escaped_tag = tag:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
    for line in chunk:gmatch("[^\n]+") do
        local pos_str = line:match('TKM (%S+) "' .. escaped_tag .. '" ' .. native_color)
        if pos_str then chunk_pos_str = pos_str end
    end
    reaper.UpdateItemInProject(item)
    return idx, chunk_pos_str
end

-- Helper: update a marker's duration via chunk editing
local function UpdateMarkerDuration(take, chunk_pos, tag, native_color, duration)
    if not chunk_pos then return end
    local item = reaper.GetMediaItemTake_Item(take)
    local _, chunk = reaper.GetItemStateChunk(item, "", false)
    local escaped_name = tag:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
    local pattern = 'TKM ' .. chunk_pos .. ' "' .. escaped_name .. '" ' .. native_color .. ' %S+'
    local replacement = string.format('TKM %s "%s" %d %s',
        chunk_pos, tag, native_color, string.format("%.14g", duration))
    local new_chunk, count = chunk:gsub(pattern, replacement)
    if count > 0 then
        reaper.SetItemStateChunk(item, new_chunk, false)
    end
    reaper.UpdateItemInProject(item)
    -- Poke the marker system to trigger Region/Marker Manager refresh
    local temp = reaper.SetTakeMarker(take, -1, "__refresh__", 0, 0)
    if temp >= 0 then reaper.DeleteTakeMarker(take, temp) end
end

function MarkArea(btn_idx)
    if not IsTransportActive() then return end
    local take, item_start, comp_start
    if target_source_lane then
        take, item_start, comp_start = GetSourceTake()
    else
        take, item_start = GetTargetTake()
    end
    if not take then return end
    
    local play_pos = reaper.GetPlayPosition2()
    local src_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    local srcpos = (play_pos - item_start) + src_offset
    local btn = buttons[btn_idx]

    if not active_markers[btn_idx] then
        -- Convert ImGui RGBA color to native REAPER color
        local r = (btn.color >> 24) & 0xFF
        local g = (btn.color >> 16) & 0xFF
        local b = (btn.color >> 8) & 0xFF
        local native_color = reaper.ColorToNative(r, g, b) | 0x1000000
        marker_counter = marker_counter + 1
        local tag = string.format("%s #%d", btn.name, marker_counter)
        
        -- Backdate start position: don't go before item start or comp segment start
        local earliest = src_offset
        if comp_start then
            local comp_src = (comp_start - item_start) + src_offset
            if comp_src > earliest then earliest = comp_src end
        end
        local backdated = math.max(earliest, srcpos - REACTION_TIME)
        
        -- Create marker on primary take (REAPER's comp system mirrors to output lane automatically)
        local idx, chunk_pos_str = CreateMarkerOnTake(take, backdated, tag, native_color)
        
        active_markers[btn_idx] = { take = take, idx = idx, start = backdated, btn = btn,
            native_color = native_color, chunk_pos = chunk_pos_str, tag = tag }
        -- Log for the review list
        local item = reaper.GetMediaItemTake_Item(take)
        table.insert(marker_log, {
            tag = tag, color = btn.color, take = take,
            srcpos = backdated, item = item
        })
    else
        -- Update existing marker duration
        local m = active_markers[btn_idx]
        if m.take == take and m.chunk_pos then
            local duration = srcpos - m.start
            UpdateMarkerDuration(m.take, m.chunk_pos, m.tag, m.native_color, duration)
        end
    end
    reaper.MarkProjectDirty(0)
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
            local src_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
            for j = reaper.GetNumTakeMarkers(take) - 1, 0, -1 do
                local m_srcpos = reaper.GetTakeMarker(take, j)
                local m_timeline = i_pos + (m_srcpos - src_offset)
                if m_timeline >= start_ts and m_timeline <= end_ts then
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
    
    -- Get playing lanes (comp output lanes)
    local num_lanes = reaper.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES")
    local playing_lanes = {}
    for lane = 0, num_lanes - 1 do
        if reaper.GetMediaTrackInfo_Value(track, "C_LANEPLAYS:" .. lane) == 1 then
            playing_lanes[lane] = true
        end
    end
    
    -- Parse LINKEDLANE entries (comp overrides) from track chunk
    local _, tchunk = reaper.GetTrackStateChunk(track, "", false)
    local linked_lanes = {}
    for line in tchunk:gmatch("[^\n]+") do
        local ll_start, ll_end, ll_lane = line:match("LINKEDLANE (%S+) (%S+) (%S+)")
        if ll_start then
            table.insert(linked_lanes, {
                s = tonumber(ll_start), e = tonumber(ll_end), lane = tonumber(ll_lane)
            })
        end
    end
    
    -- Check if a lane is active in the comp for an entire time range
    local function lane_active_for_range(item_lane, range_start, range_end)
        -- Collect all LINKEDLANE overrides within this range
        for _, ll in ipairs(linked_lanes) do
            if ll.s < range_end and ll.e > range_start then
                -- An override exists in this range
                if ll.lane ~= item_lane then
                    -- Override points to a different lane — this lane is NOT active here
                    return false
                end
            end
        end
        -- No conflicting overrides; check if the base playing lane matches
        return playing_lanes[item_lane] == true
    end
    
    reaper.Undo_BeginBlock()
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local item_lane = reaper.GetMediaItemInfo_Value(item, "I_FIXEDLANE")
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local take = reaper.GetActiveTake(item)
        if take then
            local src_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
            -- Parse TKM entries from chunk to get durations
            local _, ichunk = reaper.GetItemStateChunk(item, "", false)
            local tkm_list = {}
            for line in ichunk:gmatch("[^\n]+") do
                local pos, name, color, dur = line:match('TKM (%S+) "(.-)" (%S+) (%S+)')
                if pos then
                    table.insert(tkm_list, {
                        srcpos = tonumber(pos),
                        duration = tonumber(dur) or 0
                    })
                end
            end
            
            -- Delete markers whose time range is not fully in the comp
            for j = reaper.GetNumTakeMarkers(take) - 1, 0, -1 do
                local m_srcpos = reaper.GetTakeMarker(take, j)
                local m_timeline_start = item_start + (m_srcpos - src_offset)
                
                -- Find matching TKM entry for duration
                local m_duration = 0
                for _, tkm in ipairs(tkm_list) do
                    if math.abs(tkm.srcpos - m_srcpos) < 0.0001 then
                        m_duration = tkm.duration
                        break
                    end
                end
                
                local m_timeline_end = m_timeline_start + m_duration
                if m_duration <= 0 then m_timeline_end = m_timeline_start + 0.001 end
                
                if not lane_active_for_range(item_lane, m_timeline_start, m_timeline_end) then
                    reaper.DeleteTakeMarker(take, j)
                end
            end
        end
    end
    reaper.Undo_EndBlock("Purge non-comp lane markers", -1)
    reaper.UpdateArrange()
end

function ClearSelectedItems()
    local count = reaper.CountSelectedMediaItems(0)
    if count == 0 then return end
    reaper.Undo_BeginBlock()
    for i = 0, count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        if take then
            for j = reaper.GetNumTakeMarkers(take) - 1, 0, -1 do
                reaper.DeleteTakeMarker(take, j)
            end
        end
    end
    reaper.Undo_EndBlock("Clear take markers from selected items", -1)
    reaper.UpdateArrange()
end

function loop()
    reaper.ImGui_PushFont(ctx, main_font, 16)
    -- Set window to stay on top
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 0.8)
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 550, 0, math.huge, math.huge)
    local visible, open = reaper.ImGui_Begin(ctx, 'Mark Takes', true,
        reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoNavInputs())
    
    if visible then
        -- Forward spacebar to REAPER transport (Play/Stop), but not while typing in a popup
        if not rename_idx and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
            reaper.Main_OnCommand(40044, 0) -- Transport: Play/Stop
        end
        
        -- Two-column layout: controls left, review list right
        if reaper.ImGui_BeginTable(ctx, 'main_layout', 2, reaper.ImGui_TableFlags_SizingStretchProp()) then
        reaper.ImGui_TableSetupColumn(ctx, 'controls', reaper.ImGui_TableColumnFlags_WidthFixed(), 340)
        reaper.ImGui_TableSetupColumn(ctx, 'review', reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_TableNextColumn(ctx)
        
        -- Rewind buttons
        reaper.ImGui_PushFont(ctx, main_font, 36)
        local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
        if reaper.ImGui_Button(ctx, '<< 2s', avail_w * 0.5 - 4, 0) then
            SeekPlayback(math.max(0, reaper.GetPlayPosition2() - 2))
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, '< 1s', -0.0001, 0) then
            SeekPlayback(math.max(0, reaper.GetPlayPosition2() - 1))
        end
        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_Spacing(ctx)
        
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
            reaper.ImGui_PushFont(ctx, main_font, 36)
            local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
            local btn_w = (i % 2 == 1) and (avail_w * 0.5 - 4) or -0.0001
            reaper.ImGui_Button(ctx, btn.label, btn_w, 0)
            
            if reaper.ImGui_IsItemActive(ctx) then
                MarkArea(i)
            elseif reaper.ImGui_IsItemDeactivated(ctx) then
                -- On release, enforce minimum marker length for quick clicks
                local m = active_markers[i]
                if m and m.chunk_pos then
                    local play_pos = reaper.GetPlayPosition2()
                    local item = reaper.GetMediaItemTake_Item(m.take)
                    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local src_offset = reaper.GetMediaItemTakeInfo_Value(m.take, "D_STARTOFFS")
                    local srcpos = (play_pos - item_start) + src_offset
                    local held_duration = srcpos - m.start
                    if held_duration < DEFAULT_LENGTH then
                        UpdateMarkerDuration(m.take, m.chunk_pos, m.tag, m.native_color, DEFAULT_LENGTH)
                    end
                end
                active_markers[i] = nil
            end
            reaper.ImGui_PopFont(ctx)
            
            reaper.ImGui_PopStyleColor(ctx, 4)
            if i % 2 == 0 then reaper.ImGui_Spacing(ctx) else reaper.ImGui_SameLine(ctx) end
        end
        
        -- Right column: Review list
        reaper.ImGui_TableNextColumn(ctx)
        reaper.ImGui_Text(ctx, 'Review (' .. #marker_log .. ')')
        reaper.ImGui_Spacing(ctx)
        if #marker_log > 0 then
            if reaper.ImGui_BeginChild(ctx, 'marker_list', -1, 300) then
                local delete_idx
                for li = 1, #marker_log do
                    local entry = marker_log[li]
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), entry.color)
                    if reaper.ImGui_Selectable(ctx, entry.tag .. '##' .. li) then
                        -- Navigate to marker position on timeline
                        local item = entry.item
                        if reaper.ValidatePtr(item, 'MediaItem*') then
                            local i_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
                            local src_offset = 0
                            if reaper.ValidatePtr(entry.take, 'MediaItem_Take*') then
                                src_offset = reaper.GetMediaItemTakeInfo_Value(entry.take, 'D_STARTOFFS')
                            end
                            local timeline_pos = i_pos + (entry.srcpos - src_offset)
                            reaper.SetEditCurPos(timeline_pos, true, true)
                        end
                    end
                    -- Right-click context menu
                    if reaper.ImGui_BeginPopupContextItem(ctx) then
                        if reaper.ImGui_MenuItem(ctx, 'Rename marker') then
                            rename_idx = li
                            rename_buf = entry.tag
                        end
                        if reaper.ImGui_MenuItem(ctx, 'Delete marker') then
                            delete_idx = li
                        end
                        reaper.ImGui_EndPopup(ctx)
                    end
                    reaper.ImGui_PopStyleColor(ctx)
                end
                reaper.ImGui_EndChild(ctx)
                -- Rename popup
                if rename_idx then
                    reaper.ImGui_OpenPopup(ctx, 'Rename Marker')
                end
                if reaper.ImGui_BeginPopupModal(ctx, 'Rename Marker', true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
                    local changed, val = reaper.ImGui_InputText(ctx, '##rename', rename_buf)
                    if changed then rename_buf = val end
                    -- Auto-focus the input on first frame
                    if reaper.ImGui_IsWindowAppearing(ctx) then
                        reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
                    end
                    if reaper.ImGui_Button(ctx, 'OK', 120, 0) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
                        local new_name = rename_buf:match('^%s*(.-)%s*$')
                        if new_name and #new_name > 0 and rename_idx then
                            local entry = marker_log[rename_idx]
                            local old_tag = entry.tag
                            if reaper.ValidatePtr(entry.take, 'MediaItem_Take*') then
                                local item = reaper.GetMediaItemTake_Item(entry.take)
                                local track = reaper.GetMediaItemTrack(item)
                                local escaped_old = old_tag:gsub('([%(%)%.%%%+%-%*%?%[%^%$])', '%%%1')
                                for i = 0, reaper.CountTrackMediaItems(track) - 1 do
                                    local it = reaper.GetTrackMediaItem(track, i)
                                    local _, chunk = reaper.GetItemStateChunk(it, '', false)
                                    local new_chunk = chunk:gsub('(TKM %S+ ")' .. escaped_old .. '(" %S+)', '%1' .. new_name .. '%2')
                                    if new_chunk ~= chunk then
                                        reaper.SetItemStateChunk(it, new_chunk, false)
                                        reaper.UpdateItemInProject(it)
                                    end
                                end
                                reaper.UpdateArrange()
                            end
                            entry.tag = new_name
                        end
                        rename_idx = nil
                        reaper.ImGui_CloseCurrentPopup(ctx)
                    end
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, 'Cancel', 120, 0) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
                        rename_idx = nil
                        reaper.ImGui_CloseCurrentPopup(ctx)
                    end
                    reaper.ImGui_EndPopup(ctx)
                end
                -- Process deletion outside the loop
                if delete_idx then
                    local entry = marker_log[delete_idx]
                    -- Delete take marker by name from ALL items on the track (source + comp mirror)
                    if reaper.ValidatePtr(entry.take, 'MediaItem_Take*') then
                        local item = reaper.GetMediaItemTake_Item(entry.take)
                        local track = reaper.GetMediaItemTrack(item)
                        local escaped_tag = entry.tag:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
                        for i = 0, reaper.CountTrackMediaItems(track) - 1 do
                            local it = reaper.GetTrackMediaItem(track, i)
                            local _, chunk = reaper.GetItemStateChunk(it, "", false)
                            -- Remove any TKM line matching this tag
                            local new_chunk = chunk:gsub('TKM %S+ "' .. escaped_tag .. '" %S+[^\n]*\n', '')
                            if new_chunk ~= chunk then
                                reaper.SetItemStateChunk(it, new_chunk, false)
                                reaper.UpdateItemInProject(it)
                            end
                        end
                        reaper.UpdateArrange()
                    end
                    table.remove(marker_log, delete_idx)
                end
            end
        else
            reaper.ImGui_TextDisabled(ctx, 'No markers yet')
        end
        
        reaper.ImGui_EndTable(ctx)
        end -- BeginTable
        
        reaper.ImGui_SeparatorText(ctx, 'Options')
        local changed, val = reaper.ImGui_Checkbox(ctx, 'Mark only comp output lane', not target_source_lane)
        if changed then target_source_lane = not val end
        reaper.ImGui_SeparatorText(ctx, 'Cleanup')
        if reaper.ImGui_Button(ctx, 'Clear Markers in Time Selection', -1, 35) then ClearTimeSelection(); LoadExistingMarkers() end
        if reaper.ImGui_Button(ctx, 'Clear Markers in Selected Items', -1, 35) then ClearSelectedItems(); LoadExistingMarkers() end
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x880000FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xAA0000FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x660000FF)
        if reaper.ImGui_Button(ctx, 'Remove Markers From Areas Not Used In Comp', -1, 35) then PurgeGhostMarkers(); LoadExistingMarkers() end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopFont(ctx)
    if open then
        reaper.defer(loop)
    end
end

reaper.defer(loop)