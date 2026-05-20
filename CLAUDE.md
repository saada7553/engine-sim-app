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
There are multiple agents running, only touch the portions of the code I specifically tell you to touch
1) There is a bug with the clutch UI. Sometimes when I spawn a new engine, the clutch gets out of sync and it is engaged / disengaged in the wrong position
2) The engine controls UI needs to be redone.
    - I still want the same core components, but now in the engine builder, we can have a variable number of gears and the UI needs to be generated accordingly in the correct H pattern (4 gears if user selects, 4, 8 if the user selects more (limit to 8 gears max))
    - I dont like the look of the paddles, lets have a redesign here this is more interesting / better
    - The h shifter has this bug where when you shift gears with the mouse (physically drag the shifter), when you let go it it in a new notch, the shifter snaps to the middle for a split swcond before getting into the gear you selected
3) The clutch assembly drawing and the intake manifold visualization both suck, you need to edit them so that the geometries lign up as you would expect, the aspect ratio stays normal, and just a more interesting better UI overall.