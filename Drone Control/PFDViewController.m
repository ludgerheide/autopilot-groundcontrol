//
//  PFDViewController.m
//  Drone Control
//
//  Created by Ludger Heide on 13.10.15.
//  Copyright © 2015 Ludger Heide. All rights reserved.
//

#import "PFDViewController.h"
#import <CoreImage/CoreImage.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import "CommunicationProtocol.pbobjc.h"

#define MIN_SPEED 0
#define MAX_SPEED 100.0

#define MIN_ALTITUDE 0
#define MAX_ALTITUDE 500.0

#define PITCH_AT_END 110.0

@interface PFDViewController ()
{
    __weak IBOutlet NSImageView* view_speedTape;
    __weak IBOutlet NSTextField *label_Speed;
    __weak IBOutlet NSImageView* view_altitudeTape;
    __weak IBOutlet NSTextFieldCell *label_Altitude;
    __weak IBOutlet NSTextField *label_heading;
    __weak IBOutlet NSTextField *label_hnavStatus;
    __weak IBOutlet NSTextField *label_vnavStatus;
    __weak IBOutlet NSTextField *label_thrustStatus;
    __weak IBOutlet NSImageView *view_horizon;

    IBOutlet NSTextField* label_controller;
    NSNumber* pitch;
    NSNumber* yaw;
    NSNumber* thrust;

    IBOutlet NSTextField* label_battery;
    NSNumber* voltage;
    NSNumber* current;

    NSImage* img_speedTape;
    NSImage* img_altituteTape;
    NSImage* img_invalid;

    CIContext* context;

    CIImage* ci_invalid;
    CIImage* ci_horizon;
    CIImage* ci_mask;

    NSNumber* localRssi, *remoteRssi, *dutyCycle;
    NSString* controllerStrings[3];
}

@end

@implementation PFDViewController

@synthesize speed;

-(void) setSpeed: (NSNumber*) theSpeed {
    speed = theSpeed;
    [self updateSpeedTape];
}

@synthesize altitude;

-(void) setAltitude: (NSNumber*) theAltitude {
    altitude = theAltitude;
    [self updateAltitudeTape];
}

@synthesize pitch;
@synthesize roll;

@synthesize heading;
-(void) setHeading: (NSNumber*) theHeading {
    heading = theHeading;
    [self updateHeading];
}

@synthesize myThrustMode;
-(void)setMyThrustMode:(ThrustMode) theThrustMode {
    myThrustMode = theThrustMode;
    [self updateThrustLabel];
}

@synthesize targetSpeed;
-(void)setTargetSpeed:(NSNumber *)theTargetSpeed {
    targetSpeed = theTargetSpeed;
    [self updateThrustLabel];
}

@synthesize hnavMode;
-(void)setHnavMode:(HorizontalMode)theHnavMode {
    hnavMode = theHnavMode;
    [self updateHnavLabel];
}

@synthesize targetHeading;
- (void)setTargetHeading:(NSNumber *)theTargetHeading {
    targetHeading = theTargetHeading;
    [self updateHnavLabel];
}

@synthesize vnavMode;
- (void)setVnavMode:(VerticalMode)theVnavMode {
    vnavMode = theVnavMode;
    [self updateVnavLabel];
}

@synthesize targetAltitude;
- (void)setTargetAltitude:(NSNumber *)theAltitude {
    targetAltitude = theAltitude;
    [self updateVnavLabel];
}

@synthesize targetRateOfClimb;
- (void)setTargetRateOfClimb:(NSNumber *)theTargetRateOfClimb {
    targetRateOfClimb = theTargetRateOfClimb;
    [self updateVnavLabel];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.

    //Create NSImages for the software rendered stuff
    img_speedTape = [NSImage imageNamed: @"Speed Tape"];
    img_altituteTape = [NSImage imageNamed: @"Altitude Tape"];
    img_invalid = [NSImage imageNamed: @"Invalid"];

    //Create the CI context
    context = [CIContext contextWithCGContext: [[NSGraphicsContext currentContext] graphicsPort]
                                      options: nil];

    //Create CIIimages for the hardware rendered stuff
    NSImage* img_mask = [NSImage imageNamed: @"Mask"];
    NSImage* img_horizon = [NSImage imageNamed: @"Horizon"];
    //Create CIImage for X, Horizon and overlay
    NSData* tiffData;
    NSBitmapImageRep* bitmap;
    //X
    tiffData = [img_invalid TIFFRepresentation];
    bitmap = [NSBitmapImageRep imageRepWithData:tiffData];
    ci_invalid = [[CIImage alloc] initWithBitmapImageRep:bitmap];

    //Horizon
    tiffData = [img_horizon TIFFRepresentation];
    bitmap = [NSBitmapImageRep imageRepWithData:tiffData];
    ci_horizon = [[CIImage alloc] initWithBitmapImageRep:bitmap];

    //Overlay
    tiffData = [img_mask TIFFRepresentation];
    bitmap = [NSBitmapImageRep imageRepWithData:tiffData];
    ci_mask = [[CIImage alloc] initWithBitmapImageRep:bitmap];

    //Initialize the control input modes to sane values
    myThrustMode = PASSTHROUGH_THRUST;
    targetSpeed = [NSNumber numberWithInteger: -1];

    hnavMode = PASSTHROUGH_HORIZONTAL;
    targetHeading = [NSNumber numberWithInteger: -1];

    vnavMode = PASSTHROUGH_VERTICAL;
    targetAltitude = [NSNumber numberWithInteger: -1];
    targetRateOfClimb = [NSNumber numberWithInteger: -1];

    controllerStrings[0] = @"INOP";
    controllerStrings[1] = @"INOP";
    controllerStrings[2] = @"INOP";
}

- (void) updateSpeedTape {
    NSImage* rendered_speedTape = [[NSImage alloc] initWithSize: view_speedTape.bounds.size];

    if(speed && ![self.view inLiveResize]) {
        //Copy a portion (or the whole) from the source image so that the middle is at the correct speed
        NSRect destRect = NSMakeRect(0, 0, rendered_speedTape.size.width, rendered_speedTape.size.height);

        //Get the y-location of the actual speed on the speed tape
        CGFloat scalingFactor = rendered_speedTape.size.width / img_speedTape.size.width;

        CGFloat requiredOffsetFromBottom = (img_speedTape.size.height/MAX_SPEED) * speed.doubleValue;

        //Now get the top and bottom location y-values for the source Image
        //The destination height divided by the scaling factor is the total source height we want
        CGFloat sourceHeight = rendered_speedTape.size.height / scalingFactor;

        //We need to go sourceheight/2 to the top and bottom
        CGFloat sourceBottom = requiredOffsetFromBottom - sourceHeight/2;

        NSRect sourceRect = NSMakeRect(0, sourceBottom, img_speedTape.size.width, sourceHeight);

        [rendered_speedTape lockFocus];
        [img_speedTape drawInRect: destRect
                         fromRect: sourceRect
                        operation: NSCompositingOperationCopy
                         fraction: 1.0];
        [rendered_speedTape unlockFocus];
    } else {
        //Copy the X
        NSRect destRect = NSMakeRect(0, 0, rendered_speedTape.size.width, rendered_speedTape.size.height);
        NSRect sourceRect = NSMakeRect(0, 0, img_invalid.size.width, img_invalid.size.height);

        [rendered_speedTape lockFocus];
        [img_invalid drawInRect: destRect
                       fromRect: sourceRect
                      operation: NSCompositingOperationCopy
                       fraction: 1.0];
        [rendered_speedTape unlockFocus];
    }

    view_speedTape.image = rendered_speedTape;

    NSString* speedString;
    if(![self.view inLiveResize]) {
        if(speed) {
            double roundedSpeed = round(speed.doubleValue);
            speedString = [NSString stringWithFormat: @"%3.0f", roundedSpeed];
            label_Speed.textColor = [NSColor blackColor];
        } else {
            speedString = @" X ";
            label_Speed.textColor = [NSColor redColor];
        }
        label_Speed.stringValue = speedString;
        CGFloat fontSize = view_speedTape.bounds.size.width / 3;
        NSFont* theFont = [NSFont fontWithDescriptor: [NSFontDescriptor fontDescriptorWithName: @"Monaco" size: fontSize] size: fontSize];
        label_Speed.font = theFont;
    }
}

- (void) updateAltitudeTape {
    NSImage* rendered_altituteTape = [[NSImage alloc] initWithSize: view_altitudeTape.bounds.size];

    if(altitude && ![self.view inLiveResize]) {
        //Copy a portion (or the whole) from the source image so that the middle is at the correct speed
        NSRect destRect = NSMakeRect(0, 0, rendered_altituteTape.size.width, rendered_altituteTape.size.height);

        //Get the y-location of the target speed on the speed tape
        CGFloat scalingFactor = rendered_altituteTape.size.width / img_altituteTape.size.width;

        CGFloat requiredOffsetFromBottom = (img_altituteTape.size.height/MAX_ALTITUDE) * altitude.doubleValue;

        //Now get the top and bottom location y-values for the source Image
        //The destination height divided by the scaling factor is the total source height we want
        CGFloat sourceHeight = rendered_altituteTape.size.height / scalingFactor;

        //We need to go sourceheight/2 to the top and bottom
        CGFloat sourceBottom = requiredOffsetFromBottom - sourceHeight/2;

        NSRect sourceRect = NSMakeRect(0, sourceBottom, img_altituteTape.size.width, sourceHeight);

        [rendered_altituteTape lockFocus];
        [img_altituteTape drawInRect: destRect
                            fromRect: sourceRect
                           operation: NSCompositingOperationCopy
                            fraction: 1.0];
        [rendered_altituteTape unlockFocus];
    } else {
        //Copy the X
        NSRect destRect = NSMakeRect(0, 0, rendered_altituteTape.size.width, rendered_altituteTape.size.height);
        NSRect sourceRect = NSMakeRect(0, 0, img_invalid.size.width, img_invalid.size.height);

        [rendered_altituteTape lockFocus];
        [img_invalid drawInRect: destRect
                       fromRect: sourceRect
                      operation: NSCompositingOperationCopy
                       fraction: 1.0];
        [rendered_altituteTape unlockFocus];
    }

    view_altitudeTape.image = rendered_altituteTape;
    if(![self.view inLiveResize]) {
        NSString* altitudeString;
        if(altitude && ![self.view inLiveResize]) {
            double roundedAltitude = round(altitude.doubleValue);
            altitudeString = [NSString stringWithFormat: @"%3.0f", roundedAltitude];
            label_Altitude.textColor = [NSColor blackColor];
        } else {
            altitudeString = @" X ";
            label_Altitude.textColor = [NSColor redColor];
        }
        label_Altitude.stringValue = altitudeString;
        CGFloat fontSize = view_speedTape.bounds.size.width / 3;
        NSFont* theFont = [NSFont fontWithDescriptor: [NSFontDescriptor fontDescriptorWithName: @"Monaco" size: fontSize] size: fontSize];
        label_Altitude.font = theFont;
    }
}

-(void) updateHorizon {

    const CGFloat horizon_height = 4400;
    const CGFloat horizon_width = 1000;

    NSImage* new_horizon;
    if(pitch && roll && ![self.view inLiveResize]) {

        [[NSSound soundNamed:@"Morse"] play];
        //Do the pitch transform
        CIFilter *cropFilter = [CIFilter filterWithName: @"CICrop"];
        CIVector* cropRect = [CIVector vectorWithCGRect: CGRectMake(0, ((horizon_height/(2.0*PITCH_AT_END)) * (pitch.doubleValue + PITCH_AT_END) - horizon_width/2), horizon_width, horizon_width)];
        [cropFilter setValue: ci_horizon forKey: @"inputImage"];
        [cropFilter setValue: cropRect forKey: @"inputRectangle"];

        //TODO: Do the roll transformation
        CIFilter *rollFilter = [CIFilter filterWithName: @"CIAffineTransform"];
        NSAffineTransform* transform = [NSAffineTransform transform];
        [transform translateXBy: +horizon_width/2
                            yBy: +horizon_width/2];
        [transform rotateByDegrees: roll.doubleValue];
        [transform translateXBy: -horizon_width/2
                            yBy: -(horizon_height/(2.0*PITCH_AT_END)) * (pitch.doubleValue + PITCH_AT_END)];
        [rollFilter setValue: cropFilter.outputImage forKey: @"inputImage"];
        [rollFilter setValue: transform forKey: @"inputTransform"];

        //Overlay the mask
        CIFilter* maskFilter = [CIFilter filterWithName: @"CISourceOverCompositing"];
        [maskFilter setValue: rollFilter.outputImage forKey: @"inputBackgroundImage"];
        [maskFilter setValue: ci_mask forKey: @"inputImage"];

        //Crop back to a square shape
        CIFilter *cropFilter2 = [CIFilter filterWithName: @"CICrop"];
        CIVector* cropRect2 = [CIVector vectorWithCGRect: CGRectMake(0, 0, horizon_width, horizon_width)];
        [cropFilter2 setValue: maskFilter.outputImage forKey: @"inputImage"];
        [cropFilter2 setValue: cropRect2 forKey: @"inputRectangle"];

        //Output the image
        NSCIImageRep *rep = [NSCIImageRep imageRepWithCIImage: cropFilter2.outputImage];
        new_horizon = [[NSImage alloc] initWithSize:rep.size];
        [new_horizon addRepresentation:rep];
    } else {
        CIFilter* maskFilter = [CIFilter filterWithName: @"CISourceOverCompositing"];
        [maskFilter setValue: ci_invalid forKey: @"inputBackgroundImage"];
        [maskFilter setValue: ci_mask forKey: @"inputImage"];

        //Output the image
        NSCIImageRep *rep = [NSCIImageRep imageRepWithCIImage: maskFilter.outputImage];
        new_horizon = [[NSImage alloc] initWithSize:rep.size];
        [new_horizon addRepresentation:rep];
    }

    view_horizon.image = new_horizon;
}

-(void) updateHeading {
    if(![self.view inLiveResize]) {
        NSString* headingString;
        if(heading && ![self.view inLiveResize]) {
            double roundedHeadng = round(heading.doubleValue);
            headingString = [NSString stringWithFormat: @"%03.0f", roundedHeadng];
            label_heading.textColor = [NSColor whiteColor];
        } else {
            headingString = @" X ";
            label_heading.textColor = [NSColor redColor];
        }
        label_heading.stringValue = headingString;
        CGFloat fontSize = view_speedTape.bounds.size.width / 3;
        NSFont* theFont = [NSFont fontWithDescriptor: [NSFontDescriptor fontDescriptorWithName: @"Monaco" size: fontSize] size: fontSize];
        label_heading.font = theFont;
    }
}

//Method for ControllerDelegate
-(void) controllerChangeToHnav: (HorizontalMode) hnav rateOfTurn: (NSNumber*) rateOfTurn heading: (NSNumber*) theHeading {
    [self setHnavMode: hnav];
    [self setTargetHeading: theHeading];
    if(hnavMode == HEADING) {
        controllerStrings[0] = [NSString stringWithFormat: @"HDG: %3.0f ", self.heading.doubleValue];
    } else if (hnavMode == RATE_OF_TURN) {
        controllerStrings[0]  = [NSString stringWithFormat: @"TRN: %3.0f ", 100.0 * rateOfTurn.doubleValue];
    } else {
        controllerStrings[0] = @"INVALID";
    }
    [self updateControllerStrings];
}

-(void) controllerChangedToVnav: (VerticalMode) vnav pitch: (NSNumber*) thePitch climbRate: (NSNumber*) climbRate altitude: (NSNumber*) theAltitude {
    [self setVnavMode: vnav];
    [self setTargetRateOfClimb: climbRate];
    [self setTargetAltitude: theAltitude];

    if(vnavMode == ALTITUDE) {
        controllerStrings[1] = [NSString stringWithFormat: @"ALT: %3.0f ", self.targetAltitude.doubleValue];
    } else if (vnavMode == RATE_OF_CLIMB) {
        controllerStrings[1] = [NSString stringWithFormat: @"V/S: %2.1f ", self.targetRateOfClimb.doubleValue];
    } else if (vnavMode == PITCH_ANGLE) {
        controllerStrings[1] = [NSString stringWithFormat: @"PIT: %3.0f ", 100.0 * thePitch.doubleValue];
    } else {
        controllerStrings[1] = @"INVALID";
    }
    [self updateControllerStrings];
}

-(void) controllerChangedToThrust: (ThrustMode) myUpdateThrustMode thrustSetting: (NSNumber*) myThrust speed: (NSNumber*) newTargetSpeed {
    [self setMyThrustMode: myUpdateThrustMode];
    [self setTargetSpeed: newTargetSpeed];

    if(myThrustMode == PASSTHROUGH_THRUST) {
        controllerStrings[2] = [NSString stringWithFormat: @"THR: %3.0f ", 100.0 * myThrust.doubleValue];
    } else if (myThrustMode == SPEED) {
        controllerStrings[2] = [NSString stringWithFormat: @"SPD: %3.0f ", self.targetSpeed.doubleValue];
    } else {
        controllerStrings[2] = @"INVALID";
    }
    [self updateControllerStrings];
}

- (void)updateControllerStrings {
    if(![self.view inLiveResize]) {
        NSString* controllerString = [NSString stringWithFormat: @"%@ %@ %@", controllerStrings[0], controllerStrings[1], controllerStrings[2]];
        label_controller.stringValue = controllerString;
        CGFloat fontSize = view_speedTape.bounds.size.width / 6;
        NSFont* theFont = [NSFont fontWithDescriptor: [NSFontDescriptor fontDescriptorWithName: @"Monaco" size: fontSize] size: fontSize];
        label_controller.font = theFont;
    }
}

-(void) updateVnavLabel {
    if(![self.view inLiveResize]) {
        NSString *firstLine, *secondLine;
        NSColor* color;
        switch (vnavMode) {
            case PITCH_ANGLE:
            case PASSTHROUGH_VERTICAL:
                firstLine = @"ALT";
                secondLine = [NSString stringWithFormat: @"%3.0f", targetAltitude.doubleValue];
                color = [NSColor cyanColor];
                break;

            case ALTITUDE:
                firstLine = @"ALT";
                secondLine = [NSString stringWithFormat: @"%3.0f", targetAltitude.doubleValue];
                color = [NSColor greenColor];
                break;

            case RATE_OF_CLIMB:
                firstLine = @"V/S";
                secondLine = [NSString stringWithFormat: @"%2.1f", targetRateOfClimb.doubleValue];
                color = [NSColor greenColor];
                break;

            default:
                break;
        }
        label_vnavStatus.stringValue = [NSString stringWithFormat: @"%@\n%@", firstLine, secondLine];
        label_vnavStatus.textColor = color;
        CGFloat fontSize = view_speedTape.bounds.size.width / 3;
        NSFont* theFont = [NSFont fontWithDescriptor: [NSFontDescriptor fontDescriptorWithName: @"Monaco" size: fontSize] size: fontSize];
        label_vnavStatus.font = theFont;
    }
}

-(void) updateHnavLabel {
    if(![self.view inLiveResize]) {
        NSString *firstLine, *secondLine;
        NSColor* color;
        switch (hnavMode) {
            case PASSTHROUGH_HORIZONTAL:
            case RATE_OF_TURN:
                firstLine = @"HDG";
                secondLine = [NSString stringWithFormat: @"%.0f", targetHeading.doubleValue];
                color = [NSColor cyanColor];
                break;

            case HEADING:
                firstLine = @"HDG";
                secondLine = [NSString stringWithFormat: @"%.0f", targetHeading.doubleValue];
                color = [NSColor greenColor];
                break;

            default:
                break;
        }
        label_hnavStatus.stringValue = [NSString stringWithFormat: @"%@ | %@", firstLine, secondLine];
        label_hnavStatus.textColor = color;
        CGFloat fontSize = view_speedTape.bounds.size.width / 3;
        NSFont* theFont = [NSFont fontWithDescriptor: [NSFontDescriptor fontDescriptorWithName: @"Monaco" size: fontSize] size: fontSize];
        label_hnavStatus.font = theFont;
    }
}

-(void) updateThrustLabel {
    if(![self.view inLiveResize]) {
        NSString *firstLine, *secondLine;
        NSColor* color;
        switch (myThrustMode) {
            case PASSTHROUGH_THRUST:
                firstLine = @"A/T";
                secondLine = [NSString stringWithFormat: @"%.0f", targetSpeed.doubleValue];
                color = [NSColor cyanColor];
                break;

            case SPEED:
                firstLine = @"A/T";
                secondLine = [NSString stringWithFormat: @"%.0f", targetSpeed.doubleValue];
                color = [NSColor greenColor];
                break;

            default:
                break;
        }
        label_thrustStatus.stringValue = [NSString stringWithFormat: @"%@\n%@", firstLine, secondLine];
        label_thrustStatus.textColor = color;
        CGFloat fontSize = view_speedTape.bounds.size.width / 3;
        NSFont* theFont = [NSFont fontWithDescriptor: [NSFontDescriptor fontDescriptorWithName: @"Monaco" size: fontSize] size: fontSize];
        label_thrustStatus.font = theFont;
    }
}

//Method for batteryDelegate
- (void) batteryChangedToVoltage: (NSNumber*) theVoltage current: (NSNumber*) theCurrent {
    voltage = theVoltage;
    current = theCurrent;
    [self updateBatteryText];
}

-(void) rssiChangedToLocal: (NSNumber*) rssi {
    localRssi = rssi;
    [self updateBatteryText];
}

-(void) rssiChangedToRemote: (NSNumber*) rssi {
    remoteRssi = rssi;
    [self updateBatteryText];
}

-(void) dutyCycleChangedTo: (NSNumber*) theDutyCycle {
    dutyCycle = theDutyCycle;
    [self updateBatteryText];
}

-(void) updateBatteryText {
    if(![self.view inLiveResize]) {
        NSString* batteryString;
        if(voltage && current) {
            batteryString = [NSString stringWithFormat: @"%3.1f V, %3.1f A", [voltage doubleValue], [current doubleValue]];
            if([voltage doubleValue] > 6.75) {
                label_battery.textColor = [NSColor whiteColor];
            } else {
                [[NSSound soundNamed:@"Ping"] play];
                label_battery.textColor = [NSColor redColor];
            }
        } else {
            batteryString = @"No Battery Data!";
            label_controller.textColor = [NSColor redColor];
        }

        NSString* radioString;
        if(remoteRssi && dutyCycle) {
            radioString = [NSString stringWithFormat: @"\n%4li dBm, %3li %% DC", [remoteRssi integerValue], (long)[dutyCycle integerValue]];
            if([remoteRssi integerValue] < -80 || [dutyCycle integerValue] > 75) {
                [[NSSound soundNamed:@"Glass"] play];
            }
        } else {
            radioString = @"\nNo radio data!";
        }
        
        label_battery.stringValue = [batteryString stringByAppendingString:radioString];
        CGFloat fontSize = view_speedTape.bounds.size.width / 6;
        NSFont* theFont = [NSFont fontWithDescriptor: [NSFontDescriptor fontDescriptorWithName: @"Monaco" size: fontSize] size: fontSize];
        label_battery.font = theFont;
    }
}

- (void) viewDidLayout {
    if(![self.view inLiveResize]) {
        [self updateSpeedTape];
        [self updateAltitudeTape];
        [self updateHorizon];
        [self updateHeading];
        [self updateBatteryText];
        
        [self updateHnavLabel];
        [self updateVnavLabel];
        [self updateThrustLabel];
    }
}
@end
