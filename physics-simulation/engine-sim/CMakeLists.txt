cmake_minimum_required(VERSION 3.10)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

add_compile_definitions(ATG_ENGINE_SIM_PIRANHA_ENABLED)

# Enable group projects in folders
set_property(GLOBAL PROPERTY USE_FOLDERS ON)
set_property(GLOBAL PROPERTY PREDEFINED_TARGETS_FOLDER "cmake")

project(engine-sim)

set(CMAKE_CXX_STANDARD 17)

# Optimization flags for Release builds
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Release")
    set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG -ffast-math -march=native")
endif()

# Apple Silicon specific optimizations
if(APPLE AND CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
    add_compile_options(-mcpu=apple-m1 -fvectorize -fslp-vectorize)
endif()
find_library(AUDIOTOOLBOX_LIBRARY AudioToolbox)
find_library(COREFOUNDATION_LIBRARY CoreFoundation)
find_library(ACCELERATE_LIBRARY Accelerate)

add_library(engine-sim STATIC
    # Source files
    src/audio_buffer.cpp
    src/camshaft.cpp
    src/crankshaft.cpp
    src/combustion_chamber.cpp
    src/connecting_rod.cpp
    src/convolution_filter.cpp
    src/cylinder_bank.cpp
    src/cylinder_head.cpp
    src/delay_filter.cpp
    src/derivative_filter.cpp
    src/direct_throttle_linkage.cpp
    src/dynamometer.cpp
    src/engine.cpp
    src/exhaust_system.cpp
    src/feedback_comb_filter.cpp
    src/filter.cpp
    src/fuel.cpp
    src/function.cpp
    src/gas_system.cpp
    src/gaussian_filter.cpp
    src/governor.cpp
    src/ignition_module.cpp
    src/impulse_response.cpp
    src/intake.cpp
    src/jitter_filter.cpp
    src/leveling_filter.cpp
    src/low_pass_filter.cpp
    src/macOS_audio_unit.cpp
    src/oscilloscope.cpp
    src/oscilloscope_cluster.cpp
    src/part.cpp
    src/piston.cpp
    src/piston_engine_simulator.cpp
    src/s_audio_file.cpp
    src/simulator.cpp
    src/standard_valvetrain.cpp
    src/starter_motor.cpp
    src/synthesizer.cpp
    src/throttle.cpp
    src/transmission.cpp
    src/utilities.cpp
    src/valvetrain.cpp
    src/vehicle.cpp
    src/vehicle_drag_constraint.cpp
    src/vtec_valvetrain.cpp

    # Include files
    include/audio_buffer.h
    include/application_settings.h
    include/camshaft.h
    include/crankshaft.h
    include/combustion_chamber.h
    include/connecting_rod.h
    include/convolution_filter.h
    include/cylinder_bank.h
    include/cylinder_head.h
    include/delay_filter.h
    include/derivative_filter.h
    include/direct_throttle_linkage.h
    include/dynamometer.h
    include/engine.h
    include/exhaust_system.h
    include/feedback_comb_filter.h
    include/filter.h
    include/fuel.h
    include/function.h
    include/gas_system.h
    include/gaussian_filter.h
    include/governor.h
    include/ignition_module.h
    include/impulse_response.h
    include/intake.h
    include/jitter_filter.h
    include/leveling_filter.h
    include/low_pass_filter.h
    include/macOS_audio_unit.h
    include/oscilloscope.h
    include/oscilloscope_cluster.h
    include/part.h
    include/piston.h
    include/piston_engine_simulator.h
    include/s_audio_file.h
    include/simulator.h
    include/standard_valvetrain.h
    include/starter_motor.h
    include/synthesizer.h
    include/throttle.h
    include/transmission.h
    include/units.h
    include/utilities.h
    include/valvetrain.h
    include/vehicle.h
    include/vehicle_drag_constraint.h
    include/vtec_valvetrain.h
)

target_link_libraries(engine-sim
    simple-2d-constraint-solver
    csv-io
    ${AUDIOTOOLBOX_LIBRARY}
    ${COREFOUNDATION_LIBRARY}
    ${ACCELERATE_LIBRARY}
)

target_include_directories(engine-sim
    PUBLIC dependencies/submodules)

add_library(engine-sim-script-interpreter STATIC
    # Source files
    scripting/src/channel_types.cpp
    scripting/src/compiler.cpp
    scripting/src/engine_context.cpp
    scripting/src/language_rules.cpp

    # Include files
    scripting/include/actions.h
    scripting/include/camshaft_node.h
    scripting/include/channel_types.h
    scripting/include/compiler.h
    scripting/include/connecting_rod_node.h
    scripting/include/crankshaft_node.h
    scripting/include/cylinder_bank_node.h
    scripting/include/cylinder_head_node.h
    scripting/include/engine_context.h
    scripting/include/engine_node.h
    scripting/include/engine_sim.h
    scripting/include/exhaust_system_node.h
    scripting/include/intake_node.h
    scripting/include/function_node.h
    scripting/include/ignition_module_node.h
    scripting/include/ignition_wire_node.h
    scripting/include/impulse_response_node.h
    scripting/include/intake_node.h
    scripting/include/language_rules.h
    scripting/include/node.h
    scripting/include/object_reference_node.h
    scripting/include/object_reference_node_output.h
    scripting/include/piranha.h
    scripting/include/piston_node.h
    scripting/include/rod_journal_node.h
    scripting/include/standard_valvetrain_node.h
    scripting/include/transmission_node.h
    scripting/include/valvetrain_node.h
    scripting/include/vtec_valvetrain_node.h
    scripting/include/vehicle_node.h
)

target_include_directories(engine-sim-script-interpreter
    PUBLIC dependencies/submodules)

target_link_libraries(engine-sim-script-interpreter
    csv-io
    piranha)

add_executable(engine-sim-cli
    src/main.cpp
)
target_link_libraries(engine-sim-cli 
    engine-sim
    engine-sim-script-interpreter
)

add_subdirectory(dependencies/submodules/csv-io)
add_subdirectory(dependencies/submodules/simple-2d-constraint-solver)
add_subdirectory(dependencies/submodules/piranha) 

set(ENGINE_SIM_ALL_LIB
    ${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/libengine-sim-all.a
)

add_custom_command(
    OUTPUT ${ENGINE_SIM_ALL_LIB}
    COMMAND /usr/bin/libtool -static
            $<TARGET_FILE:engine-sim>
            $<TARGET_FILE:engine-sim-script-interpreter>
            $<TARGET_FILE:csv-io>
            $<TARGET_FILE:simple-2d-constraint-solver>
            $<TARGET_FILE:piranha>
            -o ${ENGINE_SIM_ALL_LIB}
    DEPENDS
        engine-sim
        engine-sim-script-interpreter
        csv-io
        simple-2d-constraint-solver
        piranha
    COMMENT "Merging all engine-sim static libraries into libengine-sim-all.a"
    VERBATIM
)

add_custom_target(engine-sim-all
    ALL
    DEPENDS ${ENGINE_SIM_ALL_LIB}
)