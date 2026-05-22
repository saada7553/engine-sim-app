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

2) Hitting the repair button should clear any OBD2 codes
5) Fuel turning on the ecu needs work
    - Currently, the entire map says 1s. What do these 1s mean? aren't they supposed to be seperate values? 
    - Lets brainstorm what they should be, what does the 1 represent, etc.
6) When they user changes ecu settings, they can throw the AFR / other engine parameters out of whack, if this happens, the OBD2 scanner should report warining / errors relating to these changes to let the user know there is a problem with their tune
7) I need to add vehicle breaking to this so the car vehicle speed can slowly come down
    - On macos, this should be a slider on the control pannel, think about the best way to incorporate this in 
8) Coolant & Oil problems
    - When driving hard, the coolant cools down instead of heating up
    - Turning the pumps on / off seems to have very little effect on the engine, think about how the cooland / oil should change the engine, think aobut what happens in a real engine. The pump state has what effect on the temps? think about all this and make the required changes.