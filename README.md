# Various Reaper Scripts

This repo is a collection of scripts I personally have found useful whilst recording and mixing with [Reaper](https://www.reaper.fm/) Digital Audio Workstation in my home studio.  They are largely entirely written by me (with some AI assistance), although the Buffer Size scripts are based on work by souk21.

The three projects in subfolders are independent.  Each folder has its own readme and/or instructions

## Buffer Size Buttons

These allow for one-click changing between low latency record mode (128 samples, long latency FX disabled) and higher polish mixing mode (1024 samples, re-enables slow FX).

## Copy and Paste Splits

If you have multiple takes of a song, it is often helpful to split items into lines.  If you've done this on one take, copy and paste splits will split another item at the same time points.

## Multiple Output Switching

I have mixing headphones, tracking headphones, and monitor speakers, all connected to an interface with multiple headphone and speaker outputs.  These scripts let you set up toolbar buttons (or shortcuts) to instantly switch between outputs, muting the others.  A how-to document and a youTube video are in production to explain the process.

## Mark Takes When Reviewing

When reviewing a performance, it is good to be able to annotate the takes with good and bad sections, making it easy to go back and punch in retakes.  This script provides a UI which allows you to tag playback sections as good or bad for pitch, timing or expression.  Simply click the relevant button for the duration of the section and a take marker of the relevant length will get added to the currently audible take/lane in your performance.

## Add a ZenoMod VU meter as InputFX to selected track(s)

When setting input levels on external hardware it is good to be able to see the recording levels in Reaper.  This script, which I attach to a main toolbar button, ensures that there is an instance of ZenoMod's excellent VU Meter on the selected tracks, and it is set to summed (Mono) mode.

## Harmonica Scope

A tool to monitor a channel that you are playing harmonica on. Aimed at students it tries to measure which hole or holes you are drawing or blowing.  Excellent for helping you acquire single note as well as chord technique.  Doesn't cope with bends.... yet.

## New Jam Project

I jam with some guys a few times a month.  We have the same set of instruments plugged in, and some standard MIDI drums tracks.  So I have that setup saved as a project template.  When we start a new song in the jam, this script instantiates a new copy of the project and saves it in a well known place (so the projects for a given jam can be found).  The other tweak as that because we may have set volumes on mic'd amps differently, or have different placement, I assume the levels for the tracks in the currently open project should be replicated on the same-named tracks in the new project.  It's a bit of a niche requirement, but maybe it will help someone else too!