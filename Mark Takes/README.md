# Mark Takes — Annotate your performance so you know what to re-do

A REAPER script that provides a floating GUI for grading takes in real time during playback (or recording). Click and hold on a button to mark a section as good or bad for pitch, timing, or expression — a coloured take marker spanning the held duration is added to the currently audible take.

## What It Does

While playing back a multi-take recording using REAPER's Fixed Item Lanes, the script lets you annotate sections without stopping:

| Button | Marker Name | Colour |
| -------- | ----------- | ------ |
| **Pitch +** | Pitch Good | Green |
| **Pitch -** | Pitch Bad | Red |
| **Time +** | Timing Good | Cyan |
| **Time -** | Timing Bad | Magenta |
| **Expr +** | Expression Good | Yellow |
| **Expr -** | Expression Bad | Orange |

Each marker has a duration matching how long the button was held, with timing adjustments to account for human reaction time (see below).

### Reaction Time and Quick Clicks

The script compensates for the delay between hearing something and clicking:

- **Reaction time offset (0.5s)** — every marker's start position is backdated by half a second, so the marker begins closer to where the issue actually was rather than where you reacted to it.
- **Minimum marker length (1.0s)** — a quick click produces a 1-second marker rather than a tiny sliver. If you hold the button longer than 1 second, the actual held duration is used instead.

Both values are constants at the top of the script (`REACTION_TIME` and `DEFAULT_LENGTH`) and can be adjusted to taste.

### Rewind Buttons

Two rewind buttons sit above the grade buttons:

- **<< 2s** — jumps playback back two seconds
- **< 1s** — jumps playback back one second

These only move the playback position; the edit cursor stays where it is. Handy for re-listening to a section you want to re-grade.

### Source Lane Awareness

By default, markers are placed on the **source lane** that is feeding the comp at the current play position (determined by REAPER's LINKEDLANE comp data). A checkbox lets you switch to marking the comp output lane directly instead.

When you re-comp your lanes, REAPER automatically mirrors source lane markers to the comp output.

### Review List

A panel on the right side of the window shows all markers created during the session, colour-coded to match their grade type. When the script opens, it automatically loads any existing markers from the selected track.

- **Left-click** an entry to navigate the edit cursor to that marker's position.
- **Right-click** an entry to rename or delete it. Renaming updates the take marker on the track; deleting removes it entirely.

The list updates automatically after using any of the cleanup tools.

### Cleanup Tools

- **Clear Markers in Time Selection** — removes all take markers within the current time selection on the selected track.
- **Clear Markers in Selected Items** — removes all take markers from currently selected items (useful with right-click drag selection).
- **Remove Markers From Areas Not Used In Comp** — intelligently removes markers whose time range is no longer part of the active comp. Checks each marker individually against the comp data, so a marker that spans into a region where the comp switched to a different lane will be purged.

### Other Features

- Spacebar is forwarded to REAPER's Play/Stop transport, so you can start/stop playback even when the addin window has focus.
- Buttons use large text (36px) for easy targeting during playback.
- All destructive cleanup operations are wrapped in undo blocks.

### Punch-In and Time Selection Tools

For fast punch-in recording and review, the review list offers two right-click options on each marker:

- **Select marker length** — Sets the time selection to exactly match the marker's duration.
- **Select with buffer** — Sets the time selection to the marker's range, but with extra time before and after (default: 1 second each side, adjustable via the `PUNCH_BUFFER` constant at the top of the script).

This makes it easy to line up for auto-punch recording or to rehearse a section with a little lead-in and tail. To use:

1. Right-click a marker in the review list.
2. Choose **Select with buffer** (or **Select marker length** for an exact fit).
3. Arm your track and enable auto-punch (time selection) in REAPER.
4. Hit record — REAPER will punch in for just the selected section, with the buffer for a natural lead-in/out.

You can adjust the buffer by editing the `PUNCH_BUFFER` value in the script (default is 1.0 second).

## Requirements

- **REAPER** v6.73 or later (for Fixed Item Lanes support)
- **ReaImGui** extension (provides the GUI framework)

## Installation

1. **Install ReaImGui** (if not already installed):
   - In REAPER, go to **Extensions → ReaPack → Browse packages**
   - Search for **ReaImGui**
   - Right-click → **Install**
   - Restart REAPER when prompted

2. **Add the script to REAPER**:
   - Go to **Actions → Show action list**
   - Click **New action → Load ReaScript...**
   - Navigate to this folder and select **Mark Takes.lua**
   - Click **OK**

3. **Run the script**:
   - Find "Mark Takes" in the action list and click **Run**
   - Optionally, assign a keyboard shortcut or add it to a toolbar for quick access

## Usage

1. Select the track containing your takes in Fixed Item Lanes
2. Start playback
3. Hold a grade button for the duration of the section you want to mark
4. Release the button — a coloured take marker spanning that duration appears on the source lane
5. Use the cleanup buttons to tidy up after re-comping
