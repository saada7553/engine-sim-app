//
//  EngineWrapper.h
//  engine-simulator
//
//  Created by Saad Ata on 12/30/25.
//

#ifndef EngineWrapper_h
#define EngineWrapper_h

#import <Foundation/Foundation.h>

@interface ScopePoint : NSObject
@property (nonatomic, assign) double x;
@property (nonatomic, assign) double y;
@end

/// Per-cylinder component health (0=destroyed, 1=pristine) plus wall temp.
/// Mirrors ThermalSystem::CylinderComponents in C++.
@interface CylinderHealthState : NSObject
@property (nonatomic, assign) double headGasket;
@property (nonatomic, assign) double pistonRings;
@property (nonatomic, assign) double piston;
@property (nonatomic, assign) double rod;
@property (nonatomic, assign) double rodBearing;
@property (nonatomic, assign) double intakeValve;
@property (nonatomic, assign) double exhaustValve;
@property (nonatomic, assign) double wallTempC;
@property (nonatomic, assign) BOOL seized;
@end

/// Engine-wide component health. Mirrors ThermalSystem::EngineWideComponents.
@interface EngineWideHealthState : NSObject
@property (nonatomic, assign) double cylinderHead;
@property (nonatomic, assign) double camshaft;
@property (nonatomic, assign) double crankshaft;
@property (nonatomic, assign) double mainBearing;
@property (nonatomic, assign) double waterPump;
@property (nonatomic, assign) double oilPump;
@end

@interface EngineState : NSObject
@property (nonatomic, assign) double rpm;
@property (nonatomic, assign) int gear;
@property (nonatomic, assign) double vehicleSpeed;
@property (nonatomic, assign) double clutchPressure;
@property (nonatomic, assign) BOOL isIgnitionOn;
@property (nonatomic, assign) BOOL isStarterOn;
@property (nonatomic, assign) double fuelConsumed;
@property (nonatomic, assign) double distanceTravelled;

// Gauge data properties
@property (nonatomic, assign) double manifoldPressure;       // inHg (gauge pressure)
@property (nonatomic, assign) double intakeFlowRate;         // SCFM
@property (nonatomic, assign) double volumetricEfficiency;   // Percentage
@property (nonatomic, assign) double cylinderPressure;       // PSI (cylinder 0)
@property (nonatomic, assign) double intakeAFR;              // Air-Fuel Ratio
@property (nonatomic, assign) double exhaustO2;              // O2 percentage

// Dynamometer state
@property (nonatomic, assign) BOOL dynoEnabled;

// ECU Tuning State
@property (nonatomic, assign) double ignitionOffset;    // degrees
@property (nonatomic, assign) double fuelTrim;          // multiplier (1.0 = base)
@property (nonatomic, strong) NSArray<ScopePoint *> *ignitionMap; // Live 2D map data

// Thermal + damage state
@property (nonatomic, assign) double coolantTempC;
@property (nonatomic, assign) double oilTempC;
@property (nonatomic, assign) double oilPressurePsi;
@property (nonatomic, assign) BOOL coolantPumpOn;
@property (nonatomic, assign) BOOL oilPumpOn;
@property (nonatomic, assign) double topEndHealth;
@property (nonatomic, assign) double midHealth;
@property (nonatomic, assign) double bottomEndHealth;
@property (nonatomic, strong) NSArray<CylinderHealthState *> *cylinderHealths;
@property (nonatomic, strong) EngineWideHealthState *engineWideHealth;
@property (nonatomic, assign) BOOL rodKnocking;

// Money-shift crash haptics. `moneyshiftJustFired` is a one-shot YES on the
// poll where a damaging over-rev catastrophe fires; `moneyshiftSeverity`
// (~0..N over-redline excess) scales the initial kick. `catastropheHapticLevel`
// is the live peak-follower envelope (~0..1) of the crash audio, so the UI can
// drive haptics that track the boom/clank in real time.
@property (nonatomic, assign) BOOL moneyshiftJustFired;
@property (nonatomic, assign) double moneyshiftSeverity;
@property (nonatomic, assign) double catastropheHapticLevel;
// Loudest crash-audio impact since the previous poll (~0..1). Drives the sharp
// per-impact haptic punches that follow the random boom/clank pattern.
@property (nonatomic, assign) double catastropheHapticPeak;

// Per-cylinder spark state. Index i is YES when cylinder i's spark plug is
// firing, NO when the user has cut ignition to that cylinder.
@property (nonatomic, strong) NSArray<NSNumber *> *cylinderIgnitionEnabled;

@end

typedef NS_ENUM(NSInteger, EngineScopeType) {
    EngineScopeTypeTorque,
    EngineScopeTypePower,
    EngineScopeTypeTotalExhaustFlow,
    EngineScopeTypeIntakeFlow,
    EngineScopeTypeExhaustFlow,
    EngineScopeTypeIntakeValveLift,
    EngineScopeTypeExhaustValveLift,
    EngineScopeTypeCylinderPressure,
    EngineScopeTypeCylinderMolecules,
    EngineScopeTypeSparkAdvance,
    EngineScopeTypePV
};

@interface ScopeData : NSObject
@property (nonatomic, strong) NSArray<ScopePoint *> *points;
@property (nonatomic, assign) double xMin;
@property (nonatomic, assign) double xMax;
@property (nonatomic, assign) double yMin;
@property (nonatomic, assign) double yMax;
@end

@interface EngineWrapper : NSObject

// Initializer
- (instancetype)init;

/// Initialize the simulator with an explicit absolute path to a .mr file.
/// The C++ compiler still has its search paths anchored at the bundle's
/// assets directory, so files outside the bundle can `import "engine_sim.mr"`.
- (instancetype)initWithMRPath:(NSString *)mrPath;

/// Stop the sim thread + audio synchronously so the wrapper can be replaced
/// without waiting on ARC dealloc.
- (void)shutdown;

// Polling
- (EngineState *)pollState;

// Data Access
- (ScopeData *)getScopeData:(EngineScopeType)type;

// Controls
- (void)toggleIgnition;
- (void)toggleStarter;
- (void)setThrottle:(double)val;
- (void)shiftUp;
- (void)shiftDown;
- (void)setGear:(int)targetGear;
/// `YES` once the .mr file was compiled and the simulator initialized; `NO`
/// if anything along that path failed (and the wrapper bailed out). Read by
/// EngineViewModel after init to drive a user-facing error alert.
@property (nonatomic, readonly) BOOL loadSucceeded;

- (void)toggleClutch;

/// Drives the transmission's clutch pressure directly (0.0 = fully disengaged,
/// 1.0 = fully engaged). Used by the continuous clutch slider in the UI; the
/// keyboard shortcut still goes through toggleClutch.
- (void)setClutchPressure:(double)pressure;

// Dynamometer controls
- (void)setDynoEnabled:(BOOL)enabled;
- (BOOL)isDynoEnabled;

// Data Getters
- (double)getRPM;
- (int)getGear;
- (bool)isIgnitionOn;
- (bool)isStarterOn;
- (double)getVehicleSpeed;
- (double)getTravelledDistance;
- (double)getEngineRedline;
- (double)getTotalVolumeFuelConsumed; 

// Tuning Setters
- (void)setIgnitionOffset:(double)offset;
- (void)setFuelTrim:(double)trim;

/// Push the full 2D ignition tune into the engine. `rpmBins` (rpm) and
/// `loadBins` (kPa absolute) are the axes; `advancesDeg` holds the per-cell
/// spark advance in degrees, row-major as [load][rpm] (loadBins.count *
/// rpmBins.count entries). Once set, the engine's spark timing follows the
/// map's shape across both rpm and load instead of a single scalar offset.
- (void)setIgnitionTimingMapRpm:(NSArray<NSNumber *> *)rpmBins
                           load:(NSArray<NSNumber *> *)loadBins
                    advancesDeg:(NSArray<NSNumber *> *)advancesDeg;

/// Feed the live manifold load (kPa absolute) so the 2D map lookup tracks the
/// current operating point. Cheap; call every tick.
- (void)setIgnitionLoadKpa:(double)loadKpa;

/// Sample the engine's base timing curve (in degrees BTDC) at an arbitrary
/// rpm. The curve is built into the engine when the .mr file loads, so this
/// gives the ECU map a single source of truth to populate itself from.
- (double)getBaseTimingAdvanceForRpm:(double)rpm;

// Thermal + damage controls
- (void)setCoolantPumpEnabled:(BOOL)enabled;
- (void)setOilPumpEnabled:(BOOL)enabled;
- (void)repairEngine;
/// Master damage switch. When NO, the engine can't be damaged (money-shift,
/// over-rev, wear are all suppressed and existing damage heals) — "drive
/// freely" mode.
- (void)setDamageEnabled:(BOOL)enabled;

// Per-cylinder spark control. Cutting ignition stops that cylinder's plug
// from firing; the charge is drawn in and pumped out unburnt.
- (void)setCylinderIgnitionEnabled:(int)cylinder enabled:(BOOL)enabled;

// Other
- (void)resetTravelledDistance;
- (void)resetFuelConsumption;

@end

#endif /* EngineWrapper_h */
