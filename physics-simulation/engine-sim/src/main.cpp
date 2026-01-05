// #include "../include/transmission.h"
// #include "../scripting/include/compiler.h"
// #include "../include/s_audio_file.h"
// #include "../include/macOS_audio_unit.h"

// #include <iostream>

// int main() {
//     std::cout << "hello world" << std::endl; 

//     Vehicle *vehicle = nullptr; 
//     Transmission *transmission = nullptr;
//     Engine *engine = nullptr; 

//     es_script::Compiler compiler;
//     compiler.initialize();
//     const bool compiled = compiler.compile("../assets/main.mr");
//     if (compiled) {
//         const es_script::Compiler::Output output = compiler.execute();

//         engine = output.engine;
//         vehicle = output.vehicle;
//         transmission = output.transmission;
//     }
//     else {
//         std::cout << "failed compilation" << std::endl; 
//     }
//     compiler.destroy(); 

//     std::cout << engine->getName() << std::endl; 

//     ImpulseResponse *response = engine->getExhaustSystem(0)->getImpulseResponse();
//     std::cout << response->getFilename() << std::endl; 

//     Simulator* sim = engine->createSimulator(vehicle, transmission); 
//     sim->getEngine()->getIgnitionModule()->m_enabled = true; 
//     engine->setSpeedControl(0.02); 
//     sim->setSimulationSpeed(1.0); 
//     sim->m_starterMotor.m_enabled = true;

//     engine->calculateDisplacement();
//     sim->setSimulationFrequency(engine->getSimulationFrequency());

//     Synthesizer::AudioParameters audioParams = sim->synthesizer().getAudioParameters();
//     audioParams.inputSampleNoise = static_cast<float>(engine->getInitialJitter());
//     audioParams.airNoise = static_cast<float>(engine->getInitialNoise());
//     audioParams.dF_F_mix = static_cast<float>(engine->getInitialHighFrequencyGain());
//     sim->synthesizer().setAudioParameters(audioParams);

//     for (int i = 0; i < engine->getExhaustSystemCount(); ++i) {
//         ImpulseResponse *response = engine->getExhaustSystem(i)->getImpulseResponse();

//         sAudioFile waveFile;
//         waveFile.OpenFile(response->getFilename().c_str());
//         waveFile.InitializeInternalBuffer(waveFile.GetSampleCount());
//         waveFile.FillBuffer(0);
//         waveFile.CloseFile();

//         sim->synthesizer().initializeImpulseResponse(
//             reinterpret_cast<const int16_t *>(waveFile.GetBuffer()),
//             waveFile.GetSampleCount(),
//             response->getVolume(),
//             i
//         );

//         waveFile.DestroyInternalBuffer();
//     }
//     sim->startAudioRenderingThread();

//     MacOSAudioAdapter adapter{};

//     if (adapter.Initialize(&sim->synthesizer())) {
//         adapter.Start();
//     }

//     size_t cnt = 0; 
//     size_t iteration = 0; 

//     while(1) {
//         double rpm = engine->getRpm();
//         std::cout 
//                 << "\rITERATION: " 
//                 << iteration << " RPM: " 
//                 << rpm << "    "  
//                 << std::flush;

//         sim->startFrame(1.0 / 120.0);

//         const int iterationCount = sim->getFrameIterationCount();
//         while (sim->simulateStep()) { }

//         sim->endFrame(); 
//         iteration++; 
//     }

//     std::cout << "made sim" << std::endl; 
//     return 0; 
// }

#include "../include/transmission.h"
#include "../scripting/include/compiler.h"
#include "../include/s_audio_file.h"
#include "../include/macOS_audio_unit.h"
#include "../include/governor.h"

#include <iostream>
#include <iomanip>
#include <termios.h>
#include <unistd.h>
#include <sys/select.h>
#include <fcntl.h>
#include <algorithm> // For std::clamp
#include <chrono>

// ==========================================
// UNIX NON-BLOCKING INPUT HELPER FUNCTIONS
// ==========================================
struct termios orig_termios;

void reset_terminal_mode() {
    tcsetattr(0, TCSANOW, &orig_termios);
}

void set_conio_terminal_mode() {
    struct termios new_termios;

    /* take two copies - one for now, one for later */
    tcgetattr(0, &orig_termios);
    memcpy(&new_termios, &orig_termios, sizeof(new_termios));

    /* register cleanup handler, and set the new terminal mode */
    atexit(reset_terminal_mode);
    cfmakeraw(&new_termios);
    new_termios.c_oflag |= OPOST; // Keep output processing (newlines work)
    tcsetattr(0, TCSANOW, &new_termios);
}

int kbhit() {
    struct timeval tv = { 0L, 0L };
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(0, &fds);
    return select(1, &fds, NULL, NULL, &tv);
}

int getch() {
    int r;
    unsigned char c;
    if ((r = read(0, &c, sizeof(c))) < 0) {
        return r;
    } else {
        return c;
    }
}

// ==========================================
// MAIN APPLICATION
// ==========================================

int main() {
    std::cout << "Initializing Engine Simulator (MacOS Port)..." << std::endl; 

    Vehicle *vehicle = nullptr; 
    Transmission *transmission = nullptr;
    Engine *engine = nullptr; 

    // 1. Compile and Load the Engine Script
    es_script::Compiler compiler;
    compiler.initialize();
    const bool compiled = compiler.compile("../assets/main.mr");
    
    if (compiled) {
        const es_script::Compiler::Output output = compiler.execute();
        engine = output.engine;
        vehicle = output.vehicle;
        transmission = output.transmission;
    } else {
        std::cout << "Failed to compile main.mr" << std::endl; 
        return 1;
    }
    compiler.destroy(); 

    if (!engine) {
        std::cout << "Engine was not generated via script." << std::endl;
        return 1;
    }

    std::cout << "Loaded Engine: " << engine->getName() << std::endl; 

    if (vehicle == nullptr) {
        Vehicle::Parameters vehParams;
        vehParams.mass = units::mass(1597, units::kg);
        vehParams.diffRatio = 3.42;
        vehParams.tireRadius = units::distance(10, units::inch);
        vehParams.dragCoefficient = 0.25;
        vehParams.crossSectionArea = units::distance(6.0, units::foot) * units::distance(6.0, units::foot);
        vehParams.rollingResistance = 2000.0;
        vehicle = new Vehicle;
        vehicle->initialize(vehParams);
    }

    // if (transmission == nullptr) {
    //     const double gearRatios[] = { 2.97, 2.07, 1.43, 1.00, 0.84, 0.56 };
    //     Transmission::Parameters tParams;
    //     tParams.GearCount = 6;
    //     tParams.GearRatios = gearRatios;
    //     tParams.MaxClutchTorque = units::torque(1000.0, units::ft_lb);
    //     transmission = new Transmission;
    //     transmission->initialize(tParams);
    // }

    // 2. Setup Simulator
    Simulator* sim = engine->createSimulator(vehicle, transmission); 
    
    // Default States
    sim->getEngine()->getIgnitionModule()->m_enabled = true; 
    sim->m_starterMotor.m_enabled = true;
    sim->m_dyno.m_enabled = false;
    
    engine->calculateDisplacement();
    sim->setSimulationSpeed(1.0); 
    sim->setSimulationFrequency(engine->getSimulationFrequency());

    // 3. Audio Parameters Setup
    Synthesizer::AudioParameters audioParams = sim->synthesizer().getAudioParameters();
    audioParams.inputSampleNoise = static_cast<float>(engine->getInitialJitter());
    audioParams.airNoise = static_cast<float>(engine->getInitialNoise());
    audioParams.dF_F_mix = static_cast<float>(engine->getInitialHighFrequencyGain());
    sim->synthesizer().setAudioParameters(audioParams);

    // 4. Load Impulse Response (Exhaust Audio)
    for (int i = 0; i < engine->getExhaustSystemCount(); ++i) {
        ImpulseResponse *response = engine->getExhaustSystem(i)->getImpulseResponse();

        sAudioFile waveFile;
        sAudioFile::Error err = waveFile.OpenFile(response->getFilename().c_str());
        if (err != sAudioFile::Error::None) {
             std::cout << "WARNING: Could not load audio file: " << response->getFilename() << std::endl;
             continue;
        }

        waveFile.InitializeInternalBuffer(waveFile.GetSampleCount());
        waveFile.FillBuffer(0);
        waveFile.CloseFile();

        sim->synthesizer().initializeImpulseResponse(
            reinterpret_cast<const int16_t *>(waveFile.GetBuffer()),
            waveFile.GetSampleCount(),
            response->getVolume(),
            i
        );

        waveFile.DestroyInternalBuffer();
    }

    // 5. Start Audio Threads
    sim->startAudioRenderingThread();

    MacOSAudioAdapter adapter{};
    if (adapter.Initialize(&sim->synthesizer())) {
        std::cout << "Audio Adapter Initialized." << std::endl;
        adapter.Start();
    } else {
        std::cout << "FAILED to Initialize Audio Adapter." << std::endl;
    }

    // 6. Setup Controls
    double targetThrottle = 0.0;
    double currentThrottle = 0.0;
    double clutchPressure = 1.0;
    
    // Prepare Terminal for Non-Blocking Input
    set_conio_terminal_mode();

    std::cout << "\n\r================ CONTROLS ================\n\r";
    std::cout << " [S] Starter       [A] Ignition\n\r";
    std::cout << " [K] Clutch Toggle (Engage/Disengage)\n\r";
    std::cout << " [Q] 0% Throttle   [W] 1% Throttle\n\r";
    std::cout << " [E] 10% Throttle  [R] 100% Throttle\n\r";
    std::cout << " [D] Dyno Toggle   [H] Dyno Hold\n\r";
    std::cout << " [U] Upshift       [J] Downshift\n\r";
    std::cout << " --- AUDIO (Lower=Decr / UPPER=Incr) ---\n\r";
    std::cout << " [z/Z] Volume      [x/X] Convolution\n\r";
    std::cout << " [c/C] HF Gain     [v/V] LF Noise\n\r";
    std::cout << " [b/B] HF Noise    [n/N] Sim Freq\n\r";
    std::cout << " [ESC] Quit\n\r";
    std::cout << "==========================================\n\r";

    size_t iteration = 0;
    bool running = true;
    std::string lastMessage = "";

    // Frame timing for consistent simulation speed
    const double targetFrameRate = 30.0;
    const auto targetFrameTime = std::chrono::microseconds(static_cast<int>(1000000.0 / targetFrameRate));
    auto lastFrameTime = std::chrono::steady_clock::now();

    while(running) {
        auto frameStart = std::chrono::steady_clock::now();
        // --- INPUT HANDLING ---
        if (kbhit()) {
            int c = getch();
            if (c == 27) { running = false; } 

            // Audio Param Helper: Grab current params to modify
            Synthesizer::AudioParameters ap = sim->synthesizer().getAudioParameters();
            bool updateAudio = false;

            // Normalize for switch case
            int upperC = (c >= 'a' && c <= 'z') ? c - 32 : c;

            switch (upperC) {
                // Engine Controls
                case 'S': // Starter
                    sim->m_starterMotor.m_enabled = !sim->m_starterMotor.m_enabled;
                    break;
                case 'A': // Ignition
                    sim->getEngine()->getIgnitionModule()->m_enabled = !sim->getEngine()->getIgnitionModule()->m_enabled;
                    break;
                case 'K': 
                    clutchPressure = (clutchPressure > 0.5) ? 0.0 : 1.0; 
                    lastMessage = (clutchPressure > 0.5) ? "Clutch ENGAGED" : "Clutch DISENGAGED";
                    break;
                case 'D': // Dyno
                    sim->m_dyno.m_enabled = !sim->m_dyno.m_enabled;
                    break;
                case 'H': // Dyno Hold
                    sim->m_dyno.m_hold = !sim->m_dyno.m_hold;
                    break;
                case 'Q': targetThrottle = 0.00; break;
                case 'W': targetThrottle = 0.10; break;
                case 'E': targetThrottle = 0.50; break;
                case 'R': targetThrottle = 1.00; break;
                case ' ': targetThrottle = 0.00; break; 
                case 'U': 
                    sim->getTransmission()->changeGear(sim->getTransmission()->getGear() + 1);
                    break;
                case 'J': 
                    sim->getTransmission()->changeGear(sim->getTransmission()->getGear() - 1);
                    break;

                // Audio Controls (z/Z, x/X, etc.)
                // Lowercase decreases, Uppercase increases
                
                // Volume
                case 'Z': 
                    ap.volume = std::clamp(ap.volume + (c == 'Z' ? 0.1f : -0.1f), 0.0f, 10.0f);
                    updateAudio = true;
                    lastMessage = "Volume: " + std::to_string(ap.volume);
                    break;

                // Convolution
                case 'X': 
                    ap.convolution = std::clamp(ap.convolution + (c == 'X' ? 0.1f : -0.1f), 0.0f, 2.0f);
                    updateAudio = true;
                    lastMessage = "Convolution: " + std::to_string(ap.convolution);
                    break;

                // High Freq Gain (dF_F_mix)
                case 'C': 
                    ap.dF_F_mix = std::clamp(ap.dF_F_mix + (c == 'C' ? 0.01f : -0.01f), 0.0f, 1.0f);
                    updateAudio = true;
                    lastMessage = "HF Gain: " + std::to_string(ap.dF_F_mix);
                    break;

                // Low Freq Noise (airNoise)
                case 'V': 
                    ap.airNoise = std::clamp(ap.airNoise + (c == 'V' ? 0.1f : -0.1f), 0.0f, 4.0f);
                    updateAudio = true;
                    lastMessage = "LF Noise: " + std::to_string(ap.airNoise);
                    break;

                // High Freq Noise (inputSampleNoise)
                case 'B': 
                    ap.inputSampleNoise = std::clamp(ap.inputSampleNoise + (c == 'B' ? 0.1f : -0.1f), 0.0f, 4.0f);
                    updateAudio = true;
                    lastMessage = "HF Noise: " + std::to_string(ap.inputSampleNoise);
                    break;

                // Simulation Frequency
                case 'N': 
                    {
                        double freq = sim->getSimulationFrequency();
                        freq += (c == 'N' ? 1000.0 : -1000.0);
                        freq = std::clamp(freq, 400.0, 400000.0);
                        sim->setSimulationFrequency(freq);
                        lastMessage = "Sim Freq: " + std::to_string(freq);
                    }
                    break;
            }

            if (updateAudio) {
                sim->synthesizer().setAudioParameters(ap);
            }
        }

        // --- SIMULATION LOGIC ---
        
        currentThrottle = currentThrottle * 0.9 + targetThrottle * 0.1;
        engine->setSpeedControl(currentThrottle);
        sim->getTransmission()->setClutchPressure(clutchPressure);

        // Dyno Logic
        if (sim->m_dyno.m_enabled && !sim->m_dyno.m_hold) {
            if (sim->getFilteredDynoTorque() > units::torque(1.0, units::ft_lb)) {
                sim->m_dyno.m_rotationSpeed += units::rpm(500) * (1.0/120.0);
            } else {
                sim->m_dyno.m_rotationSpeed *= (1 / (1 + (1.0/120.0)));
            }
            if (sim->m_dyno.m_rotationSpeed > engine->getRedline()) {
                sim->m_dyno.m_enabled = false;
                sim->m_dyno.m_rotationSpeed = 0;
            }
        }
        
        sim->startFrame(1.0 / 30.0);
        while (sim->simulateStep()) { }
        sim->endFrame(); 

        // --- CONSOLE OUTPUT ---
        double rpm = engine->getRpm();
        int gear = sim->getTransmission()->getGear();

        // Calculate frame time for diagnostics
        auto simEnd = std::chrono::steady_clock::now();
        double frameMs = std::chrono::duration<double, std::milli>(simEnd - frameStart).count();
        double targetMs = 1000.0 / targetFrameRate;

        // Clear line using spaces padding at end
        std::cout << "\r"
                    << "RPM: " << std::fixed << std::setprecision(0) << std::setw(5) << rpm << " | "
                    << "THR: " << std::fixed << std::setprecision(2) << currentThrottle << " | "
                    << "FREQ: " << std::setprecision(0) << std::setw(5) << sim->getSimulationFrequency() << " | "
                    << "MS: " << std::setprecision(1) << std::setw(5) << frameMs << "/" << std::setprecision(1) << targetMs << " | "
                    << "Gear: " << std::setprecision(0) << std::setw(2) << gear << " | "
                    << (sim->m_starterMotor.m_enabled ? "[S]" : "   ")
                    << (sim->getEngine()->getIgnitionModule()->m_enabled ? "[I]" : "   ")
                    << "                    "
                    << std::flush;

        iteration++;

        // Proper frame timing - sleep only for remaining time to hit target frame rate
        auto frameEnd = std::chrono::steady_clock::now();
        auto frameDuration = frameEnd - frameStart;
        if (frameDuration < targetFrameTime) {
            auto sleepTime = targetFrameTime - frameDuration;
            usleep(static_cast<useconds_t>(
                std::chrono::duration_cast<std::chrono::microseconds>(sleepTime).count()));
        }
        // If simulation took longer than target, we skip sleeping (simulation is behind)
    }

    std::cout << "\n\rExiting..." << std::endl;
    
    adapter.Stop();
    sim->endAudioRenderingThread();
    reset_terminal_mode();
    
    return 0; 
}