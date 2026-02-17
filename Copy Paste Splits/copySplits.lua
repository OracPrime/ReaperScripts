-- Function to print debug messages
function Msg(str)
    reaper.ShowConsoleMsg(tostring(str) .. "\n")
end

-- Function to copy text to clipboard
function copyToClipboard(text)
    -- This function is specific to Reaper's internal clipboard
    reaper.CF_SetClipboard(text)
end

-- Main function to collect item positions and copy them to clipboard
function main()
    local item_count = reaper.CountSelectedMediaItems(0)
    if item_count == 0 then
        Msg("No items selected.")
        return
    end

    local clipstring="splits\n"
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = pos + length
        clipstring=clipstring..string.format("%.17g\t%.17g\n",pos,item_end)
    end

    -- Copy to clipboard
    copyToClipboard(clipstring)
    Msg("Item positions copied to clipboard\n"..clipstring)
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Copy item positions to clipboard", -1)
reaper.UpdateArrange()  -- Refresh the arrangement view

