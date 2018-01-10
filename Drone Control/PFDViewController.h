//
//  PFDViewController.h
//  Drone Control
//
//  Created by Ludger Heide on 13.10.15.
//  Copyright © 2015 Ludger Heide. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CommsModel.h"
#import "XboxModel.h"

@interface PFDViewController : NSViewController <controllerDelegate, batteryDelegate>;

@property (nonatomic) NSNumber* speed;
@property (nonatomic) NSNumber* altitude;
@property (nonatomic) NSNumber* pitch;
@property (nonatomic) NSNumber* roll;
@property (nonatomic) NSNumber* heading;

@property (nonatomic) ThrustMode myThrustMode;
@property (nonatomic) NSNumber* targetSpeed;

@property (nonatomic) HorizontalMode hnavMode;
@property (nonatomic) NSNumber* targetHeading;

@property (nonatomic) VerticalMode vnavMode;
@property (nonatomic) NSNumber* targetAltitude;
@property (nonatomic) NSNumber* targetRateOfClimb;

- (void) updateHorizon;

@end
