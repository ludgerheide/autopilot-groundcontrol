//
//  XboxModel.h
//  Drone Control
//
//  Created by Ludger Heide on 28.10.15.
//  Copyright © 2015 Ludger Heide. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Xbox360ControllerManager/Xbox360ControllerDelegate.h"
#import "CommunicationProtocol.pbobjc.h"

typedef enum {
    PASSTHROUGH_VERTICAL,
    PITCH_ANGLE,
    RATE_OF_CLIMB,
    ALTITUDE
} VerticalMode;

typedef enum {
    PASSTHROUGH_HORIZONTAL,
    RATE_OF_TURN,
    HEADING
} HorizontalMode;

typedef enum {
    PASSTHROUGH_THRUST,
    SPEED
} ThrustMode;

@protocol controllerDelegate <NSObject>
@required
-(void) controllerChangedToVnav: (VerticalMode) vnav pitch: (NSNumber*) pitch climbRate: (NSNumber*) climbRate altitude: (NSNumber*) altitude;
-(void) controllerChangeToHnav: (HorizontalMode) hnav rateOfTurn: (NSNumber*) rateOfTurn heading: (NSNumber*) heading;
-(void) controllerChangedToThrust: (ThrustMode) myThrustMode thrustSetting: (NSNumber*) myThrust speed: (NSNumber*) speed;
@end

@interface XboxModel : NSObject <Xbox360ControllerDelegate>

@property (weak) id<controllerDelegate> controllerDelegate;

@property VerticalMode vnavMode;
@property double targetRateOfClimb;
@property double targetAltitude;

@property HorizontalMode hnavMode;
@property double targetHeading;

@property ThrustMode myThrustMode;
@property double targetSpeed;

-(DroneMessage_CommandUpdate*) getValues;
-(void) updateVnavHnavFromRightStick;

//Delegate methods
// Digipad up button events
-(void)buttonUpPressed;

// Digipad down button events
-(void)buttonDownPressed;

// Digipad left button events
-(void)buttonLeftPressed;

// Digipad right button events
-(void)buttonRightPressed;

// A-button events
-(void)buttonAPressed;

// B-button events
-(void)buttonBPressed;

// X-button events
-(void)buttonXPressed;

// Y-button events
-(void)buttonYPressed;

// Left shoulder button events
-(void)buttonLeftShoulderPressed;

// Right shoulder button events
-(void)buttonRightShoulderPressed;


@end
