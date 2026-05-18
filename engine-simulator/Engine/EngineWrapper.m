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
#include "engine.h"
#include "units.h"
#include "constants.h"
#include "scripting/include/compiler.h"
#include "macOS_audio_unit.h"
#include "s_audio_file.h"
#include "oscilloscope_cluster.h"
#include <thread>
#include <atomic>
#include <cmath>

// --- Dynamometer tuning constants ---
static const double kDynoTorqueThresholdFtLb = 1.0;  // ft-lb of torque required for the dyno to keep accelerating
static const double kDynoRampRateRpm = 500.0;        // rpm/sec the dyno speed climbs while loaded
static const double kFrameTimestep = 1.0 / 30.0;     // seconds per simulation frame
static const double kDynoMinThrottle = 0.05;         // a run aborts if the throttle drops below this
static const double kDynoRunStartedRpm = 500.0;      // dyno speed past which a run counts as underway

@interface EngineWrapper ()
@property (atomic, strong) EngineState *latestState;
@end

@implementation ScopePoint
@end

@implementation ScopeData
@end

@implementation EngineState
@end

@implementation EngineWrapper {
    // C++ Objects stored as instance variables
    Simulator* _sim;
    Engine* _engine;
    Vehicle* _vehicle;
    Transmission* _transmission;
    MacOSAudioAdapter* _audioAdapter;
    OscilloscopeCluster* _oscilloscopeCluster; 
    
    int _rpm;
    int _gear;
    int _targetGear;

    // Dynamometer sweep state.
    BOOL _dynoSweepRequested;
    double _dynoSpeed;   // current dyno rotation speed (rad/s)
    double _throttle;    // last commanded throttle position (0-1)
    
    // Threading
    std::thread* _simThread;
    std::atomic<bool> _running;

    // Scope Filtering State
    double _updateTimer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _updateTimer = 0.0;
        [self setupEngine];
    }
    _targetGear = -1;
    _dynoSweepRequested = NO;
    _dynoSpeed = 0.0;
    _throttle = 0.0;
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

    _oscilloscopeCluster = new OscilloscopeCluster();
    _oscilloscopeCluster->initialize();
    _oscilloscopeCluster->setSimulator(_sim);
    
    // 4. Start Physics Loop in Background Thread
    _running = true;
    _simThread = new std::thread([self](){
        while(_running) {
            const double targetFrameRate = 30.0;
            const auto targetFrameTime = std::chrono::microseconds(static_cast<int>(1000000.0 / targetFrameRate));
            auto frameStart = std::chrono::steady_clock::now();
            
            if (_gear != _targetGear)
                _sim->getTransmission()->changeGear(_targetGear);

            [self updateDynoForFrame:kFrameTimestep];

            _sim->startFrame(1.0 / 30.0);
            while (_sim->simulateStep()) {

                // --- GATHER DATA (ScopePoint Implementation) ---
                EngineState *state = [[EngineState alloc] init];
                Engine *engine = _sim->getEngine();

                // 1. Basic Stats
                state.rpm = _rpm;
                state.gear = _gear;
                state.vehicleSpeed = _vehicle->getSpeed();
                state.clutchPressure = _sim->getTransmission()->getClutchPressure();
                state.isIgnitionOn = engine->getIgnitionModule()->m_enabled;
                state.isStarterOn = _sim->m_starterMotor.m_enabled;
                state.fuelConsumed = engine->getTotalVolumeFuelConsumed();
                state.distanceTravelled = _vehicle->getTravelledDistance();
                state.dynoEnabled = _dynoSweepRequested;

                // 2. Gauge Data
                // Manifold pressure (convert to inHg gauge pressure relative to atmosphere)
                double ambientPressure = units::pressure(1.0, units::atm);
                double ambientTemperature = units::celcius(25.0);
                double manifoldPressurePa = engine->getManifoldPressure();
                double gaugePressure = std::fmin(manifoldPressurePa - ambientPressure, 0.0);
                state.manifoldPressure = units::convert(gaugePressure, units::inHg);

                // Intake flow rate (SCFM - Standard Cubic Feet per Minute)
                double actualAirPerSecond = engine->getIntakeFlowRate();
                state.intakeFlowRate = units::convert(actualAirPerSecond, units::scfm);

                // Volumetric Efficiency calculation (same as C++ right_gauge_cluster.cpp)
                // VE = (actual air flow) / (theoretical air flow) * 100
                // Theoretical = 0.5 * (P * V) / (R * T) * (RPM / 60)
                double rpm = std::fmax(engine->getRpm(), 0.0);
                double theoreticalAirPerRevolution = 0.5 * (ambientPressure * engine->getDisplacement())
                    / (constants::R * ambientTemperature);
                double theoreticalAirPerSecond = theoreticalAirPerRevolution * rpm / 60.0;
                double volumetricEfficiency = (std::abs(theoreticalAirPerSecond) < 1E-3)
                    ? 0.0
                    : (actualAirPerSecond / theoreticalAirPerSecond);
                state.volumetricEfficiency = 100.0 * volumetricEfficiency;

                // Cylinder pressure for first cylinder (PSI)
                if (engine->getCylinderCount() > 0) {
                    state.cylinderPressure = units::convert(
                        engine->getChamber(0)->m_system.pressure(),
                        units::psi
                    );
                } else {
                    state.cylinderPressure = 0.0;
                }

                // Air-Fuel Ratio
                state.intakeAFR = engine->getIntakeAfr();

                // Exhaust O2 percentage (multiply by 100 to get percentage)
                state.exhaustO2 = engine->getExhaustO2() * 100.0;
                
                // Update C++ Oscilloscopes
                _oscilloscopeCluster->sample();
                
                self.latestState = state;
                
            }
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

- (EngineState *)pollState {
    return self.latestState;
}

- (ScopeData *)getScopeData:(EngineScopeType)type {
    if (!_oscilloscopeCluster) return nil;
    
    Oscilloscope *scope = nullptr;
    switch (type) {
        case EngineScopeTypeTorque: scope = _oscilloscopeCluster->getTorqueScope(); break;
        case EngineScopeTypePower: scope = _oscilloscopeCluster->getPowerScope(); break;
        case EngineScopeTypeTotalExhaustFlow: scope = _oscilloscopeCluster->getTotalExhaustFlowOscilloscope(); break;
        case EngineScopeTypeIntakeFlow: scope = _oscilloscopeCluster->getIntakeFlowOscilloscope(); break;
        case EngineScopeTypeExhaustFlow: scope = _oscilloscopeCluster->getExhaustFlowOscilloscope(); break;
        case EngineScopeTypeIntakeValveLift: scope = _oscilloscopeCluster->getIntakeValveLiftOscilloscope(); break;
        case EngineScopeTypeExhaustValveLift: scope = _oscilloscopeCluster->getExhaustValveLiftOscilloscope(); break;
        case EngineScopeTypeCylinderPressure: scope = _oscilloscopeCluster->getCylinderPressureScope(); break;
        case EngineScopeTypeCylinderMolecules: scope = _oscilloscopeCluster->getCylinderMoleculesScope(); break;
        case EngineScopeTypeSparkAdvance: scope = _oscilloscopeCluster->getSparkAdvanceScope(); break;
        case EngineScopeTypePV: scope = _oscilloscopeCluster->getPvScope(); break;
    }
    
    if (!scope) return nil;
    
    ScopeData *data = [[ScopeData alloc] init];
    data.xMin = scope->m_xMin;
    data.xMax = scope->m_xMax;
    data.yMin = scope->m_yMin;
    data.yMax = scope->m_yMax;
    
    NSMutableArray<ScopePoint *> *points = [NSMutableArray array];
    
    // The C++ oscilloscope uses a circular buffer.
    // We need to reconstruct the linear order from the circular buffer.
    // Logic matches C++ render loop: start = (m_writeIndex - m_pointCount + m_bufferSize) % m_bufferSize
    
    int bufferSize = scope->getBufferSize();
    int pointCount = scope->getPointCount();
    int writeIndex = scope->getWriteIndex();
    Oscilloscope::DataPoint *rawPoints = scope->getDataPoints();
    
    if (pointCount > 0 && rawPoints != nullptr) {
        int start = (writeIndex - pointCount + bufferSize) % bufferSize;
        
        for (int i = 0; i < pointCount; ++i) {
            int idx = (start + i) % bufferSize;
            Oscilloscope::DataPoint p = rawPoints[idx];
            ScopePoint *sp = [[ScopePoint alloc] init];
            sp.x = p.x;
            sp.y = p.y;
            [points addObject:sp];
        }
    }
    
    data.points = points;
    return data;
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
    _throttle = val;
    _engine->setSpeedControl(val);
}

- (void)shiftUp { _targetGear = _gear + 1; }
- (void)shiftDown { _targetGear = _gear - 1; }
- (void)setGear:(int)targetGear { _targetGear = targetGear; }

- (void)toggleClutch {
    // Simple toggle logic
    double current = _sim->getTransmission()->getClutchPressure();
    _sim->getTransmission()->setClutchPressure(current > 0.5 ? 0.0 : 1.0);
}

- (void)setDynoEnabled:(BOOL)enabled { _dynoSweepRequested = enabled; }
- (BOOL)isDynoEnabled { return _dynoSweepRequested; }

// Drives the dyno sweep each frame: loads the engine and accelerates it,
// disabling once the redline is reached.
- (void)updateDynoForFrame:(double)dt {
    Dynamometer &dyno = _sim->m_dyno;

    if (_dynoSweepRequested) {
        dyno.m_enabled = true;
        dyno.m_hold = false;

        const double torqueThreshold = units::torque(kDynoTorqueThresholdFtLb, units::ft_lb);
        if (_sim->getFilteredDynoTorque() > torqueThreshold) {
            _dynoSpeed += units::rpm(kDynoRampRateRpm) * dt;
        } else {
            _dynoSpeed *= 1.0 / (1.0 + dt);
        }

        // A run ends at the redline, or early if the driver lifts off the
        // throttle once the sweep is underway.
        const bool reachedRedline = _dynoSpeed > _engine->getRedline();
        const bool throttleReleased =
            _dynoSpeed > units::rpm(kDynoRunStartedRpm) && _throttle < kDynoMinThrottle;

        if (reachedRedline || throttleReleased) {
            _dynoSweepRequested = NO;
            dyno.m_enabled = false;
            _dynoSpeed = 0.0;
        }
    } else {
        dyno.m_enabled = false;
        dyno.m_hold = false;
        _dynoSpeed = 0.0;
    }

    const double minSpeed = _engine->getDynoMinSpeed();
    const double maxSpeed = _engine->getDynoMaxSpeed();
    _dynoSpeed = std::fmax(minSpeed, std::fmin(_dynoSpeed, maxSpeed));
    dyno.m_rotationSpeed = _dynoSpeed;
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
- (double)getTimestep { return 1.0 / _sim->getTimestep(); }
- (double)getTotalExhaustFlow { return _sim->getTotalExhaustFlow(); }

- (void)dealloc {
    _running = false;
    if (_simThread->joinable()) _simThread->join();
    delete _simThread;
    
    _audioAdapter->Stop();
    delete _audioAdapter;
    _sim->destroy();
}

@end
