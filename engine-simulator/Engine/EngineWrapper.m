//
//  EngineWrapper.m
//  engine-simulator
//
//  Created by Saad Ata on 12/30/25.
//

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#if TARGET_OS_IOS
#import <AVFoundation/AVFoundation.h>
#endif
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
#include <vector>
#include <atomic>
#include <cmath>

// --- Dynamometer tuning constants ---
static const double kDynoTorqueThresholdFtLb = 1.0;  // ft-lb of torque required for the dyno to keep accelerating
static const double kDynoRampRateRpm = 500.0;        // rpm/sec the dyno speed climbs while loaded
static const double kFrameTimestep = 1.0 / 30.0;     // seconds per simulation frame
static const double kDynoMinThrottle = 0.05;         // throttle threshold that marks a run started / ends it

// The C++ ignition module stores both the timing-curve output and m_ignitionOffset
// in radians (the curve is built with units.deg). The Swift side talks in degrees,
// so we convert at this boundary in both directions.
static inline double kDegToRad(double deg) { return deg * (M_PI / 180.0); }
static inline double kRadToDeg(double rad) { return rad * (180.0 / M_PI); }

@interface EngineWrapper ()
@property (atomic, strong) EngineState *latestState;
@property (nonatomic, assign) BOOL loadSucceeded;
@end

@implementation ScopePoint
@end

@implementation ScopeData
@end

@implementation CylinderHealthState
@end

@implementation EngineWideHealthState
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
    BOOL _dynoRunStarted; // becomes YES once the throttle opens past the min during a sweep
    double _dynoSpeed;   // current dyno rotation speed (rad/s)
    double _throttle;    // last commanded throttle position (0-1)
    
    // Threading
    std::thread* _simThread;
    std::atomic<bool> _running;

    // Scope Filtering State
    double _updateTimer;

    // Cylinder-pressure peak detector. Raw chamber pressure swings from
    // ~atm to ~600+ psi every combustion cycle; reporting the instantaneous
    // value makes the needle and readout text flicker uselessly. Track the
    // peak with a slow exponential decay so the gauge surfaces "peak
    // combustion pressure", which is the number tuners actually care about.
    double _cylinderPressurePeakPsi;

    // Money-shift crash haptic latch. The sim loop builds many EngineState
    // objects per frame and keeps only the last, so a one-shot popped mid-loop
    // would be lost. Latch the onset + severity here and hand them to Swift in
    // pollState, which clears the latch once consumed.
    BOOL _moneyshiftPendingHaptic;
    double _moneyshiftPendingSeverity;
}

// Per-frame multiplicative decay applied to the cylinder-pressure peak.
// ~0.985 per simulation tick decays the peak by ~e^-1 over roughly 1.5s of
// sim time at the default frequency, so a drop in combustion pressure is
// reflected on the gauge within ~2 seconds.
static const double kCylinderPressurePeakDecay = 0.985;

- (instancetype)init {
    return [self initWithMRPath:nil];
}

- (instancetype)initWithMRPath:(NSString *)mrPath {
    self = [super init];
    if (self) {
        _updateTimer = 0.0;
        _targetGear = -1;
        _dynoSweepRequested = NO;
        _dynoRunStarted = NO;
        _dynoSpeed = 0.0;
        _throttle = 0.0;
        _running = false;
        _simThread = nullptr;
        [self setupEngineWithMRPath:mrPath];
    }
    return self;
}

- (NSString *)writeLoaderWrapperFor:(NSString *)engineMRPath {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *supportDir = [[fm URLsForDirectory:NSApplicationSupportDirectory
                                    inDomains:NSUserDomainMask] firstObject];
    if (supportDir == nil) supportDir = [NSURL fileURLWithPath:NSTemporaryDirectory()];

    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"engine-simulator";
    NSURL *cacheDir = [[supportDir URLByAppendingPathComponent:bundleID isDirectory:YES]
                                    URLByAppendingPathComponent:@"LoaderCache" isDirectory:YES];
    [fm createDirectoryAtURL:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSURL *loaderURL = [cacheDir URLByAppendingPathComponent:@"current_loader.mr"];
    NSString *contents = [NSString stringWithFormat:@"import \"%@\"\nmain()\n", engineMRPath];
    NSError *err = nil;
    BOOL ok = [contents writeToURL:loaderURL atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (!ok) {
        NSLog(@"writeLoaderWrapperFor: failed to write loader (%@)", err);
        return nil;
    }
    return loaderURL.path;
}

- (void)setupEngineWithMRPath:(NSString *)mrPath {
    NSString *assetsPath =
    [[[NSBundle mainBundle] resourcePath]
        stringByAppendingPathComponent:@"assets"];

    int rc = chdir([assetsPath UTF8String]);
    if (rc != 0) {
        NSLog(@"%@", assetsPath);
        perror("chdir failed");
    }

    NSString *targetEngineMR = mrPath;
    if (targetEngineMR == nil) {
        // No explicit path: default to the bundle main.mr (which already wires set_engine).
        NSString *bundleMain = [[NSBundle mainBundle] pathForResource:@"main"
                                                               ofType:@"mr"
                                                          inDirectory:@"assets"];
        if (bundleMain == nil) {
            NSLog(@"CRITICAL ERROR: 'main.mr' was not found in the App Bundle.");
            return;
        }
        targetEngineMR = bundleMain;
    }

    // Engine .mr files define a `main` node but don't invoke it at top level —
    // the bundle's `assets/main.mr` is what does that. Write a tiny loader
    // wrapper that imports the chosen engine and calls main().
    NSString *path = [self writeLoaderWrapperFor:targetEngineMR];
    if (path == nil) {
        NSLog(@"CRITICAL ERROR: failed to write loader wrapper for %@", targetEngineMR);
        return;
    }
        
    es_script::Compiler compiler;
    compiler.initialize();
    const bool compiledOk = compiler.compile([path UTF8String]);
    auto output = compiler.execute();

    NSLog(@"  Engine Address:       %p", output.engine);
    NSLog(@"  Vehicle Address:      %p", output.vehicle);
    NSLog(@"  Transmission Address: %p", output.transmission);

    _engine = output.engine;
    _vehicle = output.vehicle;
    _transmission = output.transmission;
    compiler.destroy();

    // If any of these came back null, dereferencing them later turns into a
    // hard crash with a useless EXC_BAD_ACCESS at some vtable offset. Bail
    // out cleanly instead so the app stays alive and the sidebar can show
    // an error / let the user pick another engine.
    if (!compiledOk || _engine == nullptr || _vehicle == nullptr || _transmission == nullptr) {
        NSLog(@"CRITICAL ERROR: failed to compile or execute %@ — engine=%p vehicle=%p transmission=%p compiledOk=%d",
              targetEngineMR, _engine, _vehicle, _transmission, compiledOk);
        _engine = nullptr;
        _vehicle = nullptr;
        _transmission = nullptr;
        return;
    }

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

#if TARGET_OS_IOS
    // On iOS the AudioUnit won't actually deliver audio unless the app has an
    // active AVAudioSession with a playback-friendly category. Configure once
    // per engine load (idempotent: setting the same category and reactivating
    // is fine).
    {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        NSError *configError = nil;
        [session setCategory:AVAudioSessionCategoryPlayback
                        mode:AVAudioSessionModeDefault
                     options:0
                       error:&configError];
        if (configError) {
            NSLog(@"engine-sim: AVAudioSession setCategory failed: %@", configError);
        }
        NSError *activationError = nil;
        [session setActive:YES error:&activationError];
        if (activationError) {
            NSLog(@"engine-sim: AVAudioSession setActive failed: %@", activationError);
        }
    }
#endif

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
                // This loop runs ~333 substeps per frame (10 kHz sim / 30 fps),
                // each allocating an EngineState and several NSMutableArrays.
                // The sim runs on a bare std::thread with no run loop, so without
                // a local pool every autoreleased temporary leaks permanently and
                // the process is OOM-killed within minutes. Drain per substep.
                @autoreleasepool {

                // --- GATHER DATA (ScopePoint Implementation) ---
                EngineState *state = [[EngineState alloc] init];
                Engine *engine = _sim->getEngine();

                // 1. Basic Stats
                state.rpm = _rpm;
                state.gear = _gear;
                // Native getSpeed() returns m/s; the speedometer gauge labels its
                // value "mph", so convert at the boundary.
                state.vehicleSpeed = units::convert(_vehicle->getSpeed(), units::mile / units::hour);
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

                // Cylinder pressure: track the running peak so the gauge
                // reflects PEAK combustion pressure (the meaningful tuning
                // number) rather than the raw chamber pressure that swings
                // 14→600+ PSI every cycle.
                if (engine->getCylinderCount() > 0) {
                    const double instantPsi = units::convert(
                        engine->getChamber(0)->m_system.pressure(),
                        units::psi
                    );
                    _cylinderPressurePeakPsi *= kCylinderPressurePeakDecay;
                    if (instantPsi > _cylinderPressurePeakPsi) {
                        _cylinderPressurePeakPsi = instantPsi;
                    }
                    state.cylinderPressure = _cylinderPressurePeakPsi;
                } else {
                    _cylinderPressurePeakPsi = 0.0;
                    state.cylinderPressure = 0.0;
                }

                // Air-Fuel Ratio
                state.intakeAFR = engine->getIntakeAfr();

                // Exhaust O2 percentage (multiply by 100 to get percentage)
                state.exhaustO2 = engine->getExhaustO2() * 100.0;
                
                // --- ECU Tuning Map Retrieval ---
                // Both getIgnitionOffset() and getTimingAdvanceForRpm() return
                // radians; convert to degrees so the Swift UI can display + edit
                // them in the units real tuners use.
                state.ignitionOffset = kRadToDeg(engine->getIgnitionOffset());
                state.fuelTrim = engine->getFuelTrim();

                // Sample the ignition map (20 points from 0 to redline).
                NSMutableArray *mapPoints = [NSMutableArray array];
                double maxRpm = [self getEngineRedline];
                for (int i = 0; i <= 20; ++i) {
                    double sampleRpm = (maxRpm / 20.0) * i;
                    double advanceRad = engine->getIgnitionOffset() +
                                        engine->getTimingAdvanceForRpm(sampleRpm);

                    ScopePoint *p = [[ScopePoint alloc] init];
                    p.x = sampleRpm;
                    p.y = kRadToDeg(advanceRad);
                    [mapPoints addObject:p];
                }
                state.ignitionMap = mapPoints;

                // --- Thermal + damage state ---
                state.coolantTempC = _sim->getCoolantTempC();
                state.oilTempC = _sim->getOilTempC();
                state.oilPressurePsi = _sim->getOilPressurePsi();
                state.coolantPumpOn = _sim->isCoolantPumpEnabled() ? YES : NO;
                state.oilPumpOn = _sim->isOilPumpEnabled() ? YES : NO;
                state.topEndHealth = _sim->getTopEndHealth();
                state.midHealth = _sim->getMidHealth();
                state.bottomEndHealth = _sim->getBottomEndHealth();
                state.rodKnocking = NO;

                ThermalSystem *thermal = engine->getThermalSystem();

                // Latch a damaging over-rev catastrophe for the crash haptic.
                // Consumed (and cleared) by Swift in pollState.
                if (thermal->popMoneyshiftEvent()) {
                    _moneyshiftPendingHaptic = YES;
                    _moneyshiftPendingSeverity = thermal->lastMoneyshiftSeverity();
                }

                const int cylCount = engine->getCylinderCount();
                NSMutableArray *cylinderHealths =
                    [NSMutableArray arrayWithCapacity:cylCount];
                for (int ci = 0; ci < cylCount; ++ci) {
                    auto comp = thermal->getCylinderComponents(ci);
                    CylinderHealthState *ch = [[CylinderHealthState alloc] init];
                    ch.headGasket = comp.headGasket;
                    ch.pistonRings = comp.pistonRings;
                    ch.piston = comp.piston;
                    ch.rod = comp.rod;
                    ch.rodBearing = comp.rodBearing;
                    ch.intakeValve = comp.intakeValve;
                    ch.exhaustValve = comp.exhaustValve;
                    ch.wallTempC = thermal->getCylinderWallTempC(ci);
                    ch.seized = thermal->isCylinderSeized(ci) ? YES : NO;
                    [cylinderHealths addObject:ch];
                }
                state.cylinderHealths = cylinderHealths;

                IgnitionModule *ignition = engine->getIgnitionModule();
                NSMutableArray *ignitionEnabled =
                    [NSMutableArray arrayWithCapacity:cylCount];
                for (int ci = 0; ci < cylCount; ++ci) {
                    [ignitionEnabled addObject:@(ignition->isPlugEnabled(ci))];
                }
                state.cylinderIgnitionEnabled = ignitionEnabled;

                auto wide = thermal->getEngineWideComponents();
                EngineWideHealthState *engineWide = [[EngineWideHealthState alloc] init];
                engineWide.cylinderHead = wide.cylinderHead;
                engineWide.camshaft = wide.camshaft;
                engineWide.crankshaft = wide.crankshaft;
                engineWide.mainBearing = wide.mainBearing;
                engineWide.waterPump = wide.waterPump;
                engineWide.oilPump = wide.oilPump;
                state.engineWideHealth = engineWide;

                // Update C++ Oscilloscopes
                _oscilloscopeCluster->sample();
                
                // Assigning to the strong property retains `state` past the
                // pool drain below, so the kept frame survives while every
                // per-substep temporary is freed immediately.
                self.latestState = state;

                } // @autoreleasepool
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

    // We made it all the way through compile + simulator + audio + thread —
    // mark the wrapper as healthy so the Swift side stops showing the
    // "engine failed to load" alert.
    self.loadSucceeded = YES;
}

- (EngineState *)pollState {
    EngineState *state = self.latestState;
    if (state) {
        // Hand over the latched crash onset (one-shot), then clear it so the
        // haptic fires exactly once per catastrophe.
        state.moneyshiftJustFired = _moneyshiftPendingHaptic;
        state.moneyshiftSeverity = _moneyshiftPendingSeverity;
        _moneyshiftPendingHaptic = NO;
        // Live crash-audio envelope + per-window peak, read fresh so the haptic
        // tracks the sound. getCatastrophePeak() also RESETS the peak, so call
        // it exactly once per poll.
        if (_sim) {
            state.catastropheHapticLevel = _sim->synthesizer().getCatastropheEnvelope();
            state.catastropheHapticPeak = _sim->synthesizer().getCatastrophePeak();
        } else {
            state.catastropheHapticLevel = 0.0;
            state.catastropheHapticPeak = 0.0;
        }
    }
    return state;
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
    if (!_sim) return;
    bool state = !_sim->getEngine()->getIgnitionModule()->m_enabled;
    _sim->getEngine()->getIgnitionModule()->m_enabled = state;
}

- (void)toggleStarter {
    if (!_sim) return;
    bool state = !_sim->m_starterMotor.m_enabled;
    _sim->m_starterMotor.m_enabled = state;
}

- (void)setThrottle:(double)val {
    _throttle = val;
    if (_engine) _engine->setSpeedControl(val);
}

- (void)shiftUp { _targetGear = _gear + 1; }
- (void)shiftDown { _targetGear = _gear - 1; }
- (void)setGear:(int)targetGear { _targetGear = targetGear; }

- (void)toggleClutch {
    if (!_sim) return;
    double current = _sim->getTransmission()->getClutchPressure();
    _sim->getTransmission()->setClutchPressure(current > 0.5 ? 0.0 : 1.0);
}

- (void)setClutchPressure:(double)pressure {
    if (!_sim) return;
    double clamped = pressure < 0.0 ? 0.0 : (pressure > 1.0 ? 1.0 : pressure);
    _sim->getTransmission()->setClutchPressure(clamped);
}

- (void)setIgnitionOffset:(double)offsetDegrees {
    if (_engine) {
        // C++ side expects radians (added directly into the radian-valued
        // base timing curve). Convert from the degrees the UI deals in.
        _engine->setIgnitionOffset(kDegToRad(offsetDegrees));
    }
}

- (void)setIgnitionTimingMapRpm:(NSArray<NSNumber *> *)rpmBins
                           load:(NSArray<NSNumber *> *)loadBins
                    advancesDeg:(NSArray<NSNumber *> *)advancesDeg {
    if (!_engine) return;
    const int nRpm = (int)rpmBins.count;
    const int nLoad = (int)loadBins.count;
    if (nRpm <= 0 || nLoad <= 0) return;
    if ((int)advancesDeg.count != nRpm * nLoad) return;

    // Convert to the engine's internal units: rpm → rad/s, degrees → radians.
    // Load stays in kPa to match the live load fed via setIgnitionLoadKpa.
    std::vector<double> w(nRpm), load(nLoad), adv(nRpm * nLoad);
    for (int i = 0; i < nRpm; ++i)  w[i]    = units::rpm(rpmBins[i].doubleValue);
    for (int j = 0; j < nLoad; ++j) load[j] = loadBins[j].doubleValue;
    for (int k = 0; k < nRpm * nLoad; ++k) adv[k] = kDegToRad(advancesDeg[k].doubleValue);

    _engine->setIgnitionTimingMap(w.data(), nRpm, load.data(), nLoad, adv.data());
}

- (void)setIgnitionLoadKpa:(double)loadKpa {
    if (_engine) _engine->setIgnitionLoad(loadKpa);
}

- (void)setFuelTrim:(double)trim {
    if (_engine) {
        _engine->setFuelTrim(trim);
    }
}

- (double)getBaseTimingAdvanceForRpm:(double)rpm {
    if (!_engine) return 0.0;
    return kRadToDeg(_engine->getTimingAdvanceForRpm(rpm));
}

- (void)setDynoEnabled:(BOOL)enabled {
    _dynoSweepRequested = enabled;
    _dynoRunStarted = NO;
}
- (BOOL)isDynoEnabled { return _dynoSweepRequested; }

// Drives the dyno sweep each frame: loads the engine and accelerates it,
// disabling once the redline is reached.
- (void)updateDynoForFrame:(double)dt {
    if (!_sim) return;
    Dynamometer &dyno = _sim->m_dyno;

    if (_dynoSweepRequested) {
        dyno.m_enabled = true;
        dyno.m_hold = false;

        // The user "starts" a run by opening the throttle past the min. After
        // that point, dropping back below ends the sweep — no rpm gate, so
        // even a brief blip captures the whole curve.
        if (_throttle >= kDynoMinThrottle) {
            _dynoRunStarted = YES;
        }

        const double torqueThreshold = units::torque(kDynoTorqueThresholdFtLb, units::ft_lb);
        if (_sim->getFilteredDynoTorque() > torqueThreshold) {
            _dynoSpeed += units::rpm(kDynoRampRateRpm) * dt;
        } else {
            _dynoSpeed *= 1.0 / (1.0 + dt);
        }

        const bool reachedRedline = _dynoSpeed > _engine->getRedline();
        const bool throttleReleased = _dynoRunStarted && _throttle < kDynoMinThrottle;

        if (reachedRedline || throttleReleased) {
            _dynoSweepRequested = NO;
            _dynoRunStarted = NO;
            dyno.m_enabled = false;
            _dynoSpeed = 0.0;
        }
    } else {
        dyno.m_enabled = false;
        dyno.m_hold = false;
        _dynoSpeed = 0.0;
        _dynoRunStarted = NO;
    }

    const double minSpeed = _engine->getDynoMinSpeed();
    const double maxSpeed = _engine->getDynoMaxSpeed();
    _dynoSpeed = std::fmax(minSpeed, std::fmin(_dynoSpeed, maxSpeed));
    dyno.m_rotationSpeed = _dynoSpeed;
}

// --- Getters ---

- (double)getRPM { return _rpm; }
- (int)getGear { return _gear; }
- (bool)isIgnitionOn { return _sim ? _sim->getEngine()->getIgnitionModule()->m_enabled : false; }
- (bool)isStarterOn { return _sim ? _sim->m_starterMotor.m_enabled : false; }
- (double)getVehicleSpeed { return _vehicle ? units::convert(_vehicle->getSpeed(), units::mile / units::hour) : 0.0; }
- (double)getTravelledDistance { return _vehicle ? _vehicle->getTravelledDistance() : 0.0; }
- (void)resetTravelledDistance { if (_vehicle) _vehicle->resetTravelledDistance(); }
- (double)getEngineRedline { return _engine ? units::toRpm(_engine->getRedline()) : 0.0; }
- (double)getTotalVolumeFuelConsumed { return _engine ? _engine->getTotalVolumeFuelConsumed() : 0.0; }
- (void)resetFuelConsumption { if (_engine) _engine->resetFuelConsumption(); }
- (double)getTimestep { return _sim ? 1.0 / _sim->getTimestep() : 0.0; }
- (double)getTotalExhaustFlow { return _sim ? _sim->getTotalExhaustFlow() : 0.0; }

// --- Thermal + damage controls ---
- (void)setCoolantPumpEnabled:(BOOL)enabled {
    if (_sim) _sim->setCoolantPumpEnabled(enabled ? true : false);
}
- (void)setOilPumpEnabled:(BOOL)enabled {
    if (_sim) _sim->setOilPumpEnabled(enabled ? true : false);
}
- (void)repairEngine {
    if (_sim) _sim->repairThermalAndDamage();
}

- (void)setDamageEnabled:(BOOL)enabled {
    if (_sim) _sim->setDamageEnabled(enabled ? true : false);
}

- (void)setCylinderIgnitionEnabled:(int)cylinder enabled:(BOOL)enabled {
    if (!_engine) return;
    _engine->getIgnitionModule()->setPlugEnabled(cylinder, enabled ? true : false);
}

- (void)shutdown {
    if (_running) {
        _running = false;
        if (_simThread && _simThread->joinable()) _simThread->join();
        if (_simThread) {
            delete _simThread;
            _simThread = nullptr;
        }
    }

    if (_audioAdapter) {
        _audioAdapter->Stop();
        delete _audioAdapter;
        _audioAdapter = nullptr;
    }

    if (_oscilloscopeCluster) {
        delete _oscilloscopeCluster;
        _oscilloscopeCluster = nullptr;
    }

    if (_sim) {
        _sim->destroy();
        _sim = nullptr;
    }
}

- (void)dealloc {
    [self shutdown];
}

@end
