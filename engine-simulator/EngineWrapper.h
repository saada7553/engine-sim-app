//
//  EngineWrapper.h
//  engine-simulator
//
//  Created by Saad Ata on 12/30/25.
//

#ifndef EngineWrapper_h
#define EngineWrapper_h

#import <Foundation/Foundation.h>

@interface EngineWrapper : NSObject

// Initializer
- (instancetype)init;

// Controls
- (void)toggleIgnition;
- (void)toggleStarter;
- (void)setThrottle:(double)val;
- (void)shiftUp;
- (void)shiftDown;
- (void)toggleClutch;

// Data Getters
- (double)getRPM;
- (int)getGear;
- (bool)isIgnitionOn;
- (bool)isStarterOn;
- (double)getVehicleSpeed;
- (double)getTravelledDistance;
- (double)getEngineRedline;
- (double)getTotalVolumeFuelConsumed; 

// Other
- (void)resetTravelledDistance;
- (void)resetFuelConsumption; 

@end

#endif /* EngineWrapper_h */
