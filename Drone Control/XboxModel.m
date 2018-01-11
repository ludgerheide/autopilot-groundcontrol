//
//  XboxModel.m
//  Drone Control
//
//  Created by Ludger Heide on 28.10.15.
//  Copyright © 2015 Ludger Heide. All rights reserved.
//

#import "XboxModel.h"
#import "Xbox360ControllerManager/Xbox360ControllerManager.h"
#import "Xbox360ControllerManager/Xbox360Controller.h"
#import <math.h>

//STick settings for passthrough/flybywire
#define MAX_ELEVATOR 1.0
#define STEP_ELEVATOR_TRIM 0.1

#define MAX_RUDDER 1.0
#define STEP_RUDDER_TRIM 0.1

#define DEADZONE_SIZE 0.1

#define TRIM_RANGE 0.5

#define MAX_VIBRATION_DURATION 0.33
#define VNAV_HNAV_UPDATE_INTERVAL 0.05 //20Hz

//VNAV ranges
const double minTargetRateOfClimb = -5; //m/s
const double maxTargetRateOfClimb = 5; //m/s

const double minTargetAltitude = -418; //m
const double maxTargetAltitude = 10000; //m
const double defaultTargetAltitude = 100; //m

//Thrust ranges
const double minTargetSpeed = 10; //km/h
const double maxTargetSpeed = 100; //km/h
const double defaultTargetSpeed = 30; //km/h

@implementation XboxModel
{
    Xbox360Controller* theController;
    double elevatorTrim;
    double rudderTrim;

    NSTimer *shutOffTimer;
    NSTimer *vnavHnavPollTimer;

    double lastLeftShoulderTime, lastRightShoulderTime;
    int leftShoulderScale, rightShoulderScale;
}

@synthesize controllerDelegate;

@synthesize vnavMode;
@synthesize targetRateOfClimb;
@synthesize targetAltitude;

@synthesize hnavMode;
@synthesize targetHeading;

@synthesize myThrustMode;
@synthesize targetSpeed;

-(id) init {
    self = [super init];
    if(self) {
        Xbox360ControllerManager* sharedManager = [Xbox360ControllerManager sharedInstance];
        [sharedManager updateControllers];

        if(sharedManager.controllerCount == 0) {
            NSLog(@"Connecting to controller failed!");
            return nil;
        }

        theController = [sharedManager getController: 0];
        theController.delegate = self;

        hnavMode = RATE_OF_TURN;
        vnavMode = PITCH_ANGLE;
        myThrustMode = PASSTHROUGH_THRUST;

        targetSpeed = defaultTargetSpeed;
        targetAltitude = defaultTargetAltitude;
        targetRateOfClimb = 0;

        vnavHnavPollTimer = [NSTimer scheduledTimerWithTimeInterval: VNAV_HNAV_UPDATE_INTERVAL target: self selector: @selector(updateVnavHnavFromRightStick) userInfo:nil repeats: YES];
    }
    return self;
}

-(void) updateVnavHnavFromRightStick {
    //Increment/decrement the vnav and hnav in accordance with the right analog stick
    const double rightAnalogStickDeadzone = 0.2;
    const double rightAnalogstickGain = 10;
    if(fabs(theController.rightStickX) >= rightAnalogStickDeadzone) {
        targetHeading += rightAnalogstickGain * theController.rightStickX * fabs(theController.rightStickX);
        targetHeading = fmod(targetHeading, 360);
        if(targetHeading < 0) {
            targetHeading += 360;
        }
    }

    if(fabs(theController.rightStickY) >= rightAnalogStickDeadzone) {
        switch (vnavMode) {
            case PASSTHROUGH_VERTICAL:
            case PITCH_ANGLE:
            case ALTITUDE:
                targetAltitude += -0.33 * rightAnalogstickGain * theController.rightStickY*fabs(theController.rightStickY);
                if(targetAltitude > maxTargetAltitude) {
                    targetAltitude = maxTargetAltitude;
                } else if (targetAltitude < minTargetAltitude) {
                    targetAltitude = minTargetAltitude;
                }
                break;

            case RATE_OF_CLIMB:
                targetRateOfClimb += -0.05 * rightAnalogstickGain * theController.rightStickY*fabs(theController.rightStickY);
                if(targetRateOfClimb > maxTargetRateOfClimb) {
                    targetRateOfClimb = maxTargetRateOfClimb;
                } else if (targetRateOfClimb < minTargetRateOfClimb) {
                    targetRateOfClimb = minTargetRateOfClimb;
                }
                break;

            default:
                break;
        }
    }
}

-(DroneMessage_CommandUpdate*) getValues {
    DroneMessage_CommandUpdate* retVal = [[DroneMessage_CommandUpdate alloc] init];
    //First, get the sampled from the sticks
    double targetRateOfTurn = theController.leftStickX;
    if(fabs(targetRateOfTurn) <= DEADZONE_SIZE) {
        targetRateOfTurn = 0;
    }

    targetRateOfTurn += (TRIM_RANGE * rudderTrim);

    if(targetRateOfTurn > MAX_RUDDER) {
        targetRateOfTurn = MAX_RUDDER;
    } else if (targetRateOfTurn < -MAX_RUDDER) {
        targetRateOfTurn = -MAX_RUDDER;
    }

    double targetPitch = theController.leftStickY;
    if(fabs(targetPitch) <= DEADZONE_SIZE) {
        targetPitch = 0;
    }

    targetPitch += (TRIM_RANGE * elevatorTrim);

    if(targetPitch > MAX_ELEVATOR) {
        targetPitch = MAX_ELEVATOR;
    } else if (targetPitch < -MAX_ELEVATOR) {
        targetPitch = -MAX_ELEVATOR;
    }

    double thrust = theController.rightTrigger;
    if(thrust > 1.0) {
        thrust = 1.0;
    } else if (thrust < -0.0) {
        thrust = 0.0;
    }

    //Then, create the DroneMessage
    //Yaw
    switch (hnavMode) {
        case RATE_OF_TURN:
        {

            retVal.rateOfTurn = 127*targetRateOfTurn;
        }
            break;

        case HEADING:
        {
            retVal.heading = round(64*targetHeading);
        }
            break;

        default:
            break;
    }

    //Pitch
    switch (vnavMode)  {
        case PITCH_ANGLE:
        {

            retVal.pitchAngle = 127*targetPitch;
        }
            break;

        case RATE_OF_CLIMB:
        {
            retVal.rateOfClimb = round(100*targetRateOfClimb);
        }
            break;

        case ALTITUDE:
        {
            retVal.altitude = round(100*targetAltitude);
        }
            break;

        default:
            break;
    }

    //Thrust
    switch (myThrustMode) {
        case PASSTHROUGH_THRUST:
        {
            retVal.throttle = round(255*thrust);
        }
            break;

        case SPEED:
        {
            retVal.speed = 27.77777777 * targetSpeed;
        }
            break;

        default:
            break;
    }

    if(controllerDelegate != nil) {
        [controllerDelegate controllerChangeToHnav: hnavMode rateOfTurn: [NSNumber numberWithDouble: targetRateOfTurn]  heading: [NSNumber numberWithDouble: targetHeading]];
        [controllerDelegate controllerChangedToVnav: vnavMode pitch: [NSNumber numberWithDouble: targetPitch] climbRate: [NSNumber numberWithDouble: targetRateOfClimb] altitude: [NSNumber numberWithDouble: targetAltitude]];
        [controllerDelegate controllerChangedToThrust: myThrustMode thrustSetting: [NSNumber numberWithDouble:thrust] speed: [NSNumber numberWithDouble: targetSpeed]];
    }

    return retVal;
}

//Delegate methods
// Digipad up button events
-(void)buttonUpPressed {
    if(elevatorTrim - STEP_ELEVATOR_TRIM > -MAX_ELEVATOR) {
        elevatorTrim -= STEP_ELEVATOR_TRIM;
    }
}

// Digipad down button events
//The down button corresponds to pushing the trim "UP"
-(void)buttonDownPressed {
    if(elevatorTrim + STEP_ELEVATOR_TRIM < MAX_ELEVATOR) {
        elevatorTrim += STEP_ELEVATOR_TRIM;
    }
}

// Digipad left button events
-(void)buttonLeftPressed {
    if(rudderTrim - STEP_RUDDER_TRIM > -MAX_RUDDER) {
        rudderTrim -= STEP_RUDDER_TRIM;
    }
}

// Digipad right button events
-(void)buttonRightPressed {
    if(rudderTrim + STEP_RUDDER_TRIM < MAX_RUDDER) {
        rudderTrim += STEP_RUDDER_TRIM;
    }
}

// A-button events
-(void)buttonAPressed {
    //This resets everything to flybywire
    vnavMode = PITCH_ANGLE;
    hnavMode = RATE_OF_TURN;
    myThrustMode = PASSTHROUGH_THRUST;

    [theController runMotorsLarge: 0 Small: 100];
    shutOffTimer = [NSTimer scheduledTimerWithTimeInterval: MAX_VIBRATION_DURATION target: self selector: @selector(stopMotors:) userInfo: nil repeats:NO];
}

// B-button events
-(void)buttonBPressed {
    //This toogles the HNAV mode
    switch (vnavMode) {
        case PITCH_ANGLE:
            vnavMode = ALTITUDE;
            break;
        case ALTITUDE:
            vnavMode = RATE_OF_CLIMB;
            break;
        case RATE_OF_CLIMB:
            vnavMode = PITCH_ANGLE;
            break;
        default:
            break;
    }

    [theController runMotorsLarge: 0 Small: 100];
    shutOffTimer = [NSTimer scheduledTimerWithTimeInterval: MAX_VIBRATION_DURATION target: self selector: @selector(stopMotors:) userInfo: nil repeats:NO];
}

// X-button events
-(void)buttonXPressed {
    //This toggles the speed mode
    switch (myThrustMode) {
        case PASSTHROUGH_THRUST:
            myThrustMode = SPEED;
            break;
        case SPEED:
            myThrustMode = PASSTHROUGH_THRUST;
            break;

        default:
            break;
    }

    [theController runMotorsLarge: 0 Small: 100];
    shutOffTimer = [NSTimer scheduledTimerWithTimeInterval: MAX_VIBRATION_DURATION target: self selector: @selector(stopMotors:) userInfo: nil repeats:NO];
}

// Y-button events
-(void)buttonYPressed {
    //This toogles the HNAV mode
    switch (hnavMode) {
        case RATE_OF_TURN:
            hnavMode = HEADING;
            break;
        case HEADING:
            hnavMode = RATE_OF_TURN;
            break;
        default:
            break;
    }

    [theController runMotorsLarge: 0 Small: 100];
    shutOffTimer = [NSTimer scheduledTimerWithTimeInterval: MAX_VIBRATION_DURATION target: self selector: @selector(stopMotors:) userInfo: nil repeats:NO];
}

// Left shoulder button events
-(void)buttonLeftShoulderPressed {
    //Do it faster if we pressed the button a lot in the last second
    double now = [[NSDate date] timeIntervalSince1970];

    if(now - lastLeftShoulderTime < 0.5) {
        leftShoulderScale = leftShoulderScale*2;
    } else {
        leftShoulderScale = 1;
    }
    lastLeftShoulderTime = now;

    targetSpeed -= leftShoulderScale;
    if(targetSpeed < minTargetSpeed) {
        targetSpeed = minTargetSpeed;
    }
}

// Right shoulder button events
-(void)buttonRightShoulderPressed {
    //Do it faster if we pressed the button a lot in the last second
    double now = [[NSDate date] timeIntervalSince1970];

    if(now -lastRightShoulderTime < 0.5) {
        rightShoulderScale = rightShoulderScale*2;
    } else {
        rightShoulderScale = 1;
    }
    lastRightShoulderTime = now;

    targetSpeed += rightShoulderScale;
    if(targetSpeed > maxTargetSpeed) {
        targetSpeed = maxTargetSpeed;
    }
}

//Timer callback to stop motors
-(void) stopMotors: (NSTimer*) timer {
    [theController runMotorsLarge: 0 Small: 0];
}

@end
