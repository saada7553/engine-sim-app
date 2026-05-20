# Project Overview
This engine simulator is an application that simulates piston eninges. It consists of a GUI application with keyboard controls. 
The simulator uses rigid body physics to produce an accurate simulation. The original simulator was written for x86 Windows. 

In this cloned copy, the goal is to port this x86 Windows version to run on Apple Silicon with MacOS. The new GUI is being built
seperately as a native MacOS application. The goal of this codebase is to produce importable libraries that will power the MacOS app. 
These libraries, which are outputted to the respective build folders, will include: 
    - libengine-sim.a
    - libengine-sim-script-interpreter.a
    - libcsv-io.a
    - libpiranha.a

With these libraries, the MacOS frontend will call specific functions, mainly exposed through the simulator.h in order to power
the UI. 

The original engine simulator on Window used src/engine_sim_application.cpp to orchestrate the simulation and GUI. This file
is no longer being used, and a stripped down version in src/main.cpp is being used to validate the functionality of the simulator
library. 

# BASH Commands/mo
1) First, cd into ./build or ./build-debug (production VS debug builds)
2) Run cmake --build . && ./engine-sim-cli to build and run the binary

## IMPORTANT: Sound Notification

After finishing responding to my request or running a command, run this command 3 times to notify me by sound:

```bash
afplay /System/Library/Sounds/Funk.aiff
```

You should also play this noise if you need my permission to do something / are waiting for my input.

# Rules to follow
1) You MUST write clean modular code. This means avoiding unnecessary / large levels of indentation in the codebase.
2) Do not use magic numbers. You must name all the numbers at the top of the file.
3) Do not duplicate code. Reuse & refactor to reuse code where needed.
4) Avoid over commenting. You are allowed to add comments as needed, but you must not add redundant comments if the code is clear in what is happenign. 
5) Do not redefine exsiting colors, read the color file and you should reuse the existing ones, if you need a new color that does not exist and is radically different from the exisitng ones, then you can add it.

# Current TODOs:
1) The very first thing you need to do is request to play the sound notification so I can grant you permission for it.
2) The c++ simulator reads engine information from .mr files. The docs/mr_config_report.md file outlines the configurations this file allows. 
    - I want the user to be able to create new engines
    - When the user clicks the + icon on the engines, a new build ui should pop up instead of the layout
    - lets just focus on the engine for now. The user should be able to control every single engine related tunable parameter tha the mr file supports
    - The UI should not be a generic macos UI, it needs to fit in with the theme of the app. Avoid making it look "AI generated" (too many icons / emojis / gradients)
    - The UI should be inspiring, i.e a cool experience to select the number of pistons, layout, etc
    - When the user selects all the configurables and presses save, a new entry should populate in the engines section, and the user should be able to select that new entry (it should just auto select by default)
    - when the user selects that new entry, the simulation should restart witht that new engine. lets just use a standard transmission / vehicle specs that are currently being used, just like a placeholder. note that yohu will have to save the user defined stuff in some new MR file that will be read.