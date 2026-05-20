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
   - The intake and exhaust diagrams have bugs:
        - They do not scale with the number of pistons selected correctly (always 4)
        - The diagrams for both the intake and exhasut suck (disconnected parts that make no sense. everythign needs to be intentional in the diagram and needs to make sense and be realistic. currenlty its just some shapes slapped there)
        - redo these graphics
        
    - The engine sizing diagram has bugs where adjusting an unrelated parameter adjusts unrelated things in the diagram. For example, adjusting the rod length makes the bore difference as the whoel view resizes. you need to take all the size differences into account and view behaviour to ensure that the model behaves correctly

    - The firing order ui is not good, it takes a long time to give the order you want and the UI is just uninspiring overall, it could be more interesting

    - The vehicle UI is very bad, it mentions front cross section but shows the tires as if you were viewing them from the side, it makes no sense

    - I am confused as setting the rev limit is presented in multiple locations, and additionally it seems to have to do with spark advance which we can't even adjust as much as we want? should we auto gen spark advance based off the rev limit? we need to have one source of truth for rev limit and reconsile it with the advance in a way which makes sense

    - The cam lobe UI is confusing, IDK what is going on, either explain it or desin a better UI (I probably just dont understand it)