-- @description Apply previously copied split times from the clipboard to the selected items, splitting them accordingly
-- @author OracPrime
-- @version 0.1

-- Function to print debug messages
function Msg(str)
    reaper.ShowConsoleMsg(tostring(str) .. "\n")
end

-- Function to get text from clipboard
function getFromClipboard()
    return reaper.CF_GetClipboard()
end

function splitString(input, delimiter)
    local result = {}
    for match in (input .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

function splitItem(item,starts,ends)
  --Msg("TrySplit "..reaper.GetMediaItemInfo_Value(item,"D_POSITION").."+"..reaper.GetMediaItemInfo_Value(item,"D_LENGTH"))
  for i=1,#starts do
    local s=starts[i]
    local e=ends[i]
    local itemStart=reaper.GetMediaItemInfo_Value(item,"D_POSITION")
    local itemEnd = itemStart+reaper.GetMediaItemInfo_Value(item,"D_LENGTH")
    -- e<is => finish
    -- s>ie => next
    -- e<ie => split at e, discard second item.
    -- s>is => split at s
    -- Msg("s "..s.." e "..e.." iS "..itemStart.." iE "..itemEnd)
    if e<itemStart then
       return
    end
    if e<itemEnd then
      local todiscard=reaper.SplitMediaItem(item,e)
      if todiscard then
        reaper.DeleteTrackMediaItem(reaper.GetMediaItemTrack(todiscard), todiscard)
      end
    end
    if s>itemStart then
      reaper.SplitMediaItem(item,s)
    end
  end
  local itemStart=reaper.GetMediaItemInfo_Value(item,"D_POSITION")
  if itemStart<starts[#starts] then
 local tokeep=reaper.SplitMediaItem(item,starts[#starts])
      reaper.DeleteTrackMediaItem(reaper.GetMediaItemTrack(item),item)
  end
end

-- Main function to apply item positions to a new track
function main()
    -- Get positions data from clipboard
    local clipboard_text = getFromClipboard()
    if not clipboard_text then
        Msg("Clipboard is empty or not accessible.")
        return
    end
    
    local lines=splitString(clipboard_text,"\n")

    if #lines<1 or lines[1]~="splits" then
      Msg("Bad clipboard format "..type(lines).." "..lines[1])
      return
    end

    if #lines==1 then
      return
    end

    local starts={}
    local ends={}
    
    for i,str in ipairs(lines) do
      if i>1 then
        local str1, str2 = str:match("^(.-)%s(.*)$")
        table.insert(starts,tonumber(str1))
        table.insert(ends,tonumber(str2))
      end
    end

    -- reverse sort starts and ends
    table.sort(starts, function(a, b) return a > b end)
    table.sort(ends, function(a, b) return a > b end)

    local item_count = reaper.CountSelectedMediaItems(0)
    if item_count == 0 then
        Msg("No items selected.")
        return
    end
    
    local dest_items={}
    for i = 0, item_count - 1 do
        table.insert(dest_items, reaper.GetSelectedMediaItem(0, i))
    end
    
    for i,it in ipairs(dest_items) do
      splitItem(it,starts,ends)
    end
    
    
    
    -- Create a new track
    -- reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
    --     local new_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    -- 
    --     for _, pos in ipairs(positions) do
    --         -- Create a new item on the new track with the specified positions
    --         local item = reaper.AddMediaItemToTrack(new_track)
    --         reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos.start)
    --         reaper.SetMediaItemInfo_Value(item, "D_LENGTH", pos.end_pos - pos.start)
    --         Msg(string.format("Created item from %.10f to %.10f", pos.start, pos.end_pos))
    --     end
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Apply item positions to new track", -1)
reaper.UpdateArrange()  -- Refresh the arrangement view

