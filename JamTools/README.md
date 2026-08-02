## New Jam Project

I jam with some guys a few times a month.  We have the same set of instruments plugged in, and some standard MIDI drums tracks.  So I have that setup saved as a project template.  When we start a new song in the jam, this script instantiates a new copy of the project and saves it in a well known place (so the projects for a given jam can be found).  The other tweak as that because we may have set volumes on mic'd amps differently, or have different placement, I assume the levels for the tracks in the currently open project should be replicated on the same-named tracks in the new project.  It's a bit of a niche requirement, but maybe it will help someone else too!

You need to edit two bits to match your configuration, both in CONFIGURATION at the top of the file

- New projects will be put in <LIVE_PROJECTS_ROOT>\<date>\<songname>  (we prompt for songname when you run the script).  This will kept the projects independent, but all the ones for the same jam together
- The location of your new project template file

The additional tweak the script does is that some of my (UAD) plugins when used in a project template cause the new project to be marked as modified, even when you haven't changed anything.  To avoid this false positive, I reset the project dirty state just after loading.