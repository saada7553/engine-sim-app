//
//  EngineWrapper.m
//  engine-simulator
//
//  Created by Saad Ata on 12/30/25.
//

#import <Foundation/Foundation.h>
#import "EngineWrapper.h"

// C++ Includes
#include "transmission.h"
#include "simulator.h"
#include "scripting/include/compiler.h"
#include "macOS_audio_unit.h"
#include "s_audio_file.h"
#include <thread>
#include <atomic>

@implementation EngineWrapper {
    // C++ Objects stored as instance variables
    Simulator* _sim;
    Engine* _engine;
    Vehicle* _vehicle;
    Transmission* _transmission;
    MacOSAudioAdapter* _audioAdapter;
    
    int _rpm;
    int _gear;
    int _targetGear;
    
    // Threading
    std::thread* _simThread;
    std::atomic<bool> _running;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupEngine];
    }
    _targetGear = -1;
    return self;
}

- (void)setupEngine {
    // 1. Compile Script (Hardcoded path for bundle resource later)
    // Note: In a real app, you get the path from NSBundle
    NSString *path = [[NSBundle mainBundle] pathForResource:@"main"
                                                     ofType:@"mr"
                                                inDirectory:@"assets"];
    
    NSString *assetsPath =
    [[[NSBundle mainBundle] resourcePath]
        stringByAppendingPathComponent:@"assets"];
    
    int rc = chdir([assetsPath UTF8String]);
    if (rc != 0) {
        NSLog(assetsPath);
        perror("chdir failed");
    }
    
    if (path == nil) {
        NSLog(@"CRITICAL ERROR: 'main.mr' was not found in the App Bundle.");
        NSLog(@"Fix: Go to Build Phases -> Copy Bundle Resources and add main.mr");
        return;
    }
    
//    physics_simulation sim{};
//    sim.HelloWorld("is this working? ");
        
    es_script::Compiler compiler;
    compiler.initialize();
    compiler.compile([path UTF8String]); // Use Bundle path
    auto output = compiler.execute();
    
    NSLog(@"  Engine Address:       %p", output.engine);
    NSLog(@"  Vehicle Address:      %p", output.vehicle);
    NSLog(@"  Transmission Address: %p", output.transmission);
    
    _engine = output.engine;
    _vehicle = output.vehicle;
    _transmission = output.transmission;
    compiler.destroy();
    
    // 2. Setup Simulator
    _sim = _engine->createSimulator(_vehicle, _transmission);
    _engine->calculateDisplacement();
    _sim->setSimulationFrequency(_engine->getSimulationFrequency());
    _sim->setSimulationSpeed(1.0);
    
    // 3. Setup Audio (Shortened for brevity - copy your setup logic here)
    Synthesizer::AudioParameters audioParams = _sim->synthesizer().getAudioParameters();
    audioParams.inputSampleNoise = static_cast<float>(_engine->getInitialJitter());
    audioParams.airNoise = static_cast<float>(_engine->getInitialNoise());
    audioParams.dF_F_mix = static_cast<float>(_engine->getInitialHighFrequencyGain());
    _sim->synthesizer().setAudioParameters(audioParams);

    // 4. Load Impulse Response (Exhaust Audio)
    for (int i = 0; i < _engine->getExhaustSystemCount(); ++i) {
        ImpulseResponse *response = _engine->getExhaustSystem(i)->getImpulseResponse();

        sAudioFile waveFile;
        sAudioFile::Error err = waveFile.OpenFile(response->getFilename().c_str());
        if (err != sAudioFile::Error::None) {
            std::cout << "WARNING: Could not load audio file: " << response->getFilename() << std::endl;
            continue;
        }

        waveFile.InitializeInternalBuffer(waveFile.GetSampleCount());
        waveFile.FillBuffer(0);
        waveFile.CloseFile();

       _sim->synthesizer().initializeImpulseResponse(
           reinterpret_cast<const int16_t *>(waveFile.GetBuffer()),
           waveFile.GetSampleCount(),
           response->getVolume(),
           i
       );

       waveFile.DestroyInternalBuffer();
   }
    _sim->startAudioRenderingThread();
    
    _audioAdapter = new MacOSAudioAdapter();
    _audioAdapter->Initialize(&_sim->synthesizer());
    _audioAdapter->Start();
    
    // 4. Start Physics Loop in Background Thread
    _running = true;
    _simThread = new std::thread([self](){
        while(_running) {
            const double targetFrameRate = 30.0;
            const auto targetFrameTime = std::chrono::microseconds(static_cast<int>(1000000.0 / targetFrameRate));
            auto frameStart = std::chrono::steady_clock::now();
            
            
//            _engine->setSpeedControl();
//            _sim->getTransmission()->setClutchPressure();
            if (_gear != _targetGear)
                _sim->getTransmission()->changeGear(_targetGear); 
            
            _sim->startFrame(1.0 / 30.0);
            while (_sim->simulateStep()) { }
            _sim->endFrame();
            
            _rpm = _engine->getRpm();
            _gear = _sim->getTransmission()->getGear();
            
            auto frameEnd = std::chrono::steady_clock::now();
            auto frameDuration = frameEnd - frameStart;
            if (frameDuration < targetFrameTime) {
                auto sleepTime = targetFrameTime - frameDuration;
                usleep(static_cast<useconds_t>(
                    std::chrono::duration_cast<std::chrono::microseconds>(sleepTime).count()));
            }
        }
    });
}

// --- Controls Exposed to Swift ---

- (void)toggleIgnition {
    bool state = !_sim->getEngine()->getIgnitionModule()->m_enabled;
    _sim->getEngine()->getIgnitionModule()->m_enabled = state;
}

- (void)toggleStarter {
    bool state = !_sim->m_starterMotor.m_enabled;
    _sim->m_starterMotor.m_enabled = state;
}

- (void)setThrottle:(double)val {
    _engine->setSpeedControl(val);
}

- (void)shiftUp { _targetGear = _gear + 1; }
- (void)shiftDown { _targetGear = _gear - 1; }

- (void)toggleClutch {
    // Simple toggle logic
    double current = _sim->getTransmission()->getClutchPressure();
    _sim->getTransmission()->setClutchPressure(current > 0.5 ? 0.0 : 1.0);
}

// --- Getters ---

- (double)getRPM { return _rpm; }
- (int)getGear { return _gear; }
- (bool)isIgnitionOn { return _sim->getEngine()->getIgnitionModule()->m_enabled; }
- (bool)isStarterOn { return _sim->m_starterMotor.m_enabled; }
- (double)getVehicleSpeed { return _vehicle->getSpeed(); }
- (double)getTravelledDistance { return _vehicle->getTravelledDistance(); }
- (void)resetTravelledDistance { _vehicle->resetTravelledDistance(); }
- (double)getEngineRedline { return units::toRpm(_engine->getRedline()); }
- (double)getTotalVolumeFuelConsumed { return _engine->getTotalVolumeFuelConsumed(); }
- (void)resetFuelConsumption { _engine->resetFuelConsumption(); }

- (void)dealloc {
    _running = false;
    if (_simThread->joinable()) _simThread->join();
    delete _simThread;
    
    _audioAdapter->Stop();
    delete _audioAdapter;
    _sim->destroy();
}

@end
