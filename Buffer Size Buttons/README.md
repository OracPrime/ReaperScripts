# Buffer Size Toggle Scripts for Reaper

Two toolbar scripts that make it easy to switch between low-latency recording (128 samples) and high-quality mixing (1024 samples) buffer sizes in Reaper.
I have them added to my main toolbar with text buttons saying REC for the 128 script and MIX for the 1024 script.

## Purpose

When recording with virtual instruments or monitoring through plugins, you need low buffer sizes (128 samples or less) to minimize latency. However, when mixing or processing, higher buffer sizes (1024 samples) provide better CPU efficiency and stability.

These scripts automate the buffer size switching and intelligently manage high-latency plugins to optimize your workflow:

- **Set block size to 128**: Switches to low-latency mode for recording

  - Automatically scans for plugins with high PDC (Plugin Delay Compensation)
  - Offers to temporarily take high-latency plugins offline, removing their PDC
  - Includes muted tracks so their PDC cannot add monitoring delay
  - Shift+click to take high-latency plugins offline without confirmation

- **Set block size to 1024**: Switches to mixing/processing mode
  - Automatically offers to bring previously offlined plugins back online
  - Provides better CPU efficiency for complex processing

## Features

- ✅ Mutually exclusive toolbar buttons (one highlighted at a time)
- ✅ Smart plugin latency detection (scans regular tracks, Master track, and Monitor FX)
- ✅ Includes muted tracks and ignores already-offline plugins
- ✅ Remembers which plugins were taken offline for easy restoration
- ✅ Shift-click shortcut for offline/online switching without confirmation
- ✅ Configurable PDC threshold
- ✅ Status bar feedback

## Installation

Install the single **Buffer Size Buttons** package through ReaPack. It includes both toolbar actions and the private `BufferSizeCommon.lua` helper. See [SETUP_INSTRUCTIONS.txt](SETUP_INSTRUCTIONS.txt) for complete setup instructions.

## Requirements

- **Reaper** (Digital Audio Workstation)
- **js_ReaScriptAPI** extension (available via ReaPack)

## Quick Start

1. Install the required js_ReaScriptAPI extension
2. Install the **Buffer Size Buttons** package through ReaPack
3. Load both provided action scripts into Reaper's Actions list
4. Add both scripts to your toolbar
5. Click each button once to register them
6. They will now automatically toggle each other!

## Mac Users

Initial users have reported issues on Mac. For now debug logging is turned on on Mac. Please bear with us

## Usage Tips

- **Normal click**: Shows a dialog when high-PDC plugins are found (128) or when restoring offlined plugins (1024)
- **Shift+click**: Take high-latency plugins offline or bring them back online without asking
- Check the status bar for confirmation of buffer size and plugin count

## Customization

The PDC threshold can be adjusted in `Set block size to 128.lua` (line 10):

```lua
local PDC_THRESHOLD = 128  -- Maximum acceptable PDC in samples
```

## License

Based in part on souk21's buffer size script.

## Author

OracPrime
