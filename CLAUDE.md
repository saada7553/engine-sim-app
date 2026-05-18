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

# Rules to follow
1) You MUST write clean modular code. This means avoiding unnecessary / large levels of indentation in the codebase.
2) Do not use magic numbers. You must name all the numbers at the top of the file.
3) Do not duplicate code. Reuse & refactor to reuse code where needed.
4) Avoid over commenting. You are allowed to add comments as needed, but you must not add redundant comments if the code is clear in what is happenign. 
5) Do not redefine exsiting colors, read the color file and you should reuse the existing ones, if you need a new color that does not exist and is radically different from the exisitng ones, then you can add it.

# Current TODOs:
1) The hold now works, but there are some issues:
    - when I press hold, the RPMs stay steady and the hold UI light is illuminated. However the UI throttle input and manifold go back to idle, there needs to be one source of truth of what the throttle is. 
    - Hold should turn off when the user presses the spacebar for throttle
2) The dyno oscilliscope has problems
    - When the dino is off and you hold and rev slightly, there is a blip / waste data they shows up for a moment on the graph and stays there. 
    - The dyno grapg should reset / clear when you start a new dyno run
    - The axis make no sense on the oscilliscope, we are plotting two things, so we should have two labeled Y axis. currently there is only 1 which is confusing and I dont even know what the data is. When the dyno mode is turned off, There should be an annotation highlighting the peak power and torque and the RPM at which this happened. 
3) The keyboard controls work, but there are clicking noises (the macos clicks when you press the wrong / invalid buttons) as you interact with the keyboard. 