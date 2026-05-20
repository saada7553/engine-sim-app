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
- (void)toggleClutch;

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

// Other
- (void)resetTravelledDistance;
- (void)resetFuelConsumption; 

@end

#endif /* EngineWrapper_h */
