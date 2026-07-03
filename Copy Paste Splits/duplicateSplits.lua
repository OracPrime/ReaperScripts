-- @description #desc
-- @author OracPrime
-- @version 0.1
-- @noindex

-- Function to print debug messages
function Msg(str)
    reaper.ShowConsoleMsg(tostring(str) .. "\n")
end

-- Main function to copy splits from source track to destination track
function main()
    -- Get the selected tracks
    local src_track = reaper.GetSelectedTrack(0, 0)
    local dest_track = reaper.GetSelectedTrack(0, 1)
    if not src_track or not dest_track then
        Msg("Source or destination track not selected.")
        return
    end

    -- Get the items on the source track
    local item_count = reaper.CountTrackMediaItems(src_track)
    local split_positions = {}

    for i = 0, item_count - 1 do
        local item = reaper.GetTrackMediaItem(src_track, i)
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        table.insert(split_positions, {start = pos, end_pos = pos + length})
        Msg("src "..pos.." + "..length.." = "..pos+length)
    end

    Msg("Split positions collected: " .. #split_positions)

    -- Sort split positions in reverse order for splitting
    table.sort(split_positions, function(a, b) return a.start > b.start end)

    -- Split the destination track at the split positions in reverse order
    local dest_item_count = reaper.CountTrackMediaItems(dest_track)
    for i = dest_item_count - 1, 0, -1 do
        local item = reaper.GetTrackMediaItem(dest_track, i)
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = pos + length-1

        for _, split_range in ipairs(split_positions) do
            if split_range.start > pos and split_range.start < item_end then
                reaper.SplitMediaItem(item, split_range.start)
                Msg("Splitting item at position: " .. split_range.start)
            end
            if split_range.end_pos > pos and split_range.end_pos < item_end then
                reaper.SplitMediaItem(item, split_range.end_pos)
                Msg("Splitting item at position: " .. split_range.end_pos)
            end
        end
    end

    -- Remove items in the destination track that do not correspond to the original track's items
    local to_delete = {}
    dest_item_count = reaper.CountTrackMediaItems(dest_track)
    for i = 0, dest_item_count - 1 do
        local item = reaper.GetTrackMediaItem(dest_track, i)
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = pos + length-1
        Msg("dst "..pos.." + "..length.." = "..pos+length)

        local found = false
        for _, split_range in ipairs(split_positions) do
            if pos >= split_range.start and item_end <= split_range.end_pos then
                found = true
                break
            end
        end

        if not found then
            table.insert(to_delete, item)
        end
    end

    for _, item in ipairs(to_delete) do
        reaper.DeleteTrackMediaItem(dest_track, item)
    end
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Copy splits from one track to another", -1)
reaper.UpdateArrange()  -- Refresh the arrangement view to see the splits

