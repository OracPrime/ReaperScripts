# Buffer Size Toggle Scripts for Reaper

Two toolbar scripts that make it easy to switch between low-latency recording (128 samples) and high-quality mixing (1024 samples) buffer sizes in Reaper.
I have them added to my main toolbar with text buttons saying REC for the 128 script and MIX for the 1024 script.

## Purpose

When recording with virtual instruments or monitoring through plugins, you need low buffer sizes (128 samples or less) to minimize latency. However, when mixing or processing, higher buffer sizes (1024 samples) provide better CPU efficiency and stability.

These scripts automate the buffer size switching and intelligently manage high-latency plugins to optimize your workflow:

- **Set block size to 128**: Switches to low-latency mode for recording

  - Automatically scans for plugins with high PDC (Plugin Delay Compensation)
  - Offers to temporarily disable laggy plugins
  - Ignores muted tracks by default (Ctrl+click to include them)
  - Shift+click to auto-disable high-latency plugins without confirmation

- **Set block size to 1024**: Switches to mixing/processing mode
  - Automatically offers to re-enable previously disabled plugins
  - Provides better CPU efficiency for complex processing

## Features

- ✅ Mutually exclusive toolbar buttons (one highlighted at a time)
- ✅ Smart plugin latency detection (scans regular tracks, Master track, and Monitor FX)
- ✅ Ignores bypassed plugins and muted tracks
- ✅ Remembers which plugins were disabled for easy re-enabling
- ✅ Keyboard modifiers for power users (Ctrl/Shift)
- ✅ Configurable PDC threshold
- ✅ Status bar feedback

## Installation

See [SETUP_INSTRUCTIONS.txt](SETUP_INSTRUCTIONS.txt) for complete installation and configuration instructions.

## Requirements

- **Reaper** (Digital Audio Workstation)
- **js_ReaScriptAPI** extension (available via ReaPack)
- **SWS extension** (https://www.sws-extension.org/)

## Quick Start

1. Install the required extensions (js_ReaScriptAPI and SWS)
2. Load both scripts into Reaper's Actions list
3. Add both scripts to your toolbar
4. Click each button once to register them
5. They will now automatically toggle each other!

## Mac Users

Initial users have reported issues on Mac. For now debug logging is turned on on Mac. Please bear with us

## Usage Tips

- **Normal click**: Shows dialog when high-PDC plugins are found (128) or when re-enabling plugins (1024)
- **Shift+click**: Auto-disable/re-enable plugins without asking (works for both 128 and 1024)
- **Ctrl+click (128 only)**: Include muted tracks in the scan
- **Shift+Ctrl+click (128 only)**: Include muted tracks AND auto-disable without confirmation
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
