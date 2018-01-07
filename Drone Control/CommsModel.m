//
//  CommsModel.m
//  Drone Control
//
//  Created by Ludger Heide on 18.10.15.
//  Copyright © 2015 Ludger Heide. All rights reserved.
//

#define POLLING_INTERVAL 0.05 //20hz
#define RSSI_INTERVAL 1.1 //1hz

#define INSTRUMENTTIMEOUT 2

#import "CommsModel.h"
#import "XBeeMessage.h"
#import "CommunicationProtocol.pbobjc.h"
#import "XboxModel.h"
#import <Cocoa/Cocoa.h>

@implementation CommsModel
{
    ORSSerialPort* myPort;
    
    NSMutableData* receivedData;
    
    XboxModel* controllerModel;
    
    NSTimer* instrumentTimeoutTimer;
    NSTimer* controllerPollTimer;
    NSTimer* rssiPollTimer;
}

@synthesize attitudeDelegate;
@synthesize positionDelegate;
@synthesize controllerDelegate;
@synthesize batteryDelegate;


- (CommsModel*) init {
    self = [super init];
    
    if(self) {
        myPort = [ORSSerialPort serialPortWithPath: @"/dev/tty.usbserial-DA017KGT"];
        myPort.baudRate = [NSNumber numberWithInteger: 115200];
        myPort.delegate = self;
        [myPort open];
        
        receivedData = [[NSMutableData alloc] init];
        
        if(![myPort isOpen]) {
            NSLog(@"failed to open serial port!");
            return nil;
        }
        
        //Now, the controller
        controllerModel = [[XboxModel alloc] init];
        
        if(controllerModel) {
            //Schedule the repeating timer for the controller
            controllerPollTimer = [NSTimer scheduledTimerWithTimeInterval: POLLING_INTERVAL target: self selector: @selector(sendControllerSample:) userInfo:nil repeats: YES];
        } else {
            
        }

        //Schedule the repeating timer for polling RSSI
        rssiPollTimer = [NSTimer scheduledTimerWithTimeInterval: RSSI_INTERVAL target: self selector: @selector(fetchRssi:) userInfo:nil repeats: YES];
    }
    return self;
}

-(void) sendSeaLevelPressure: (NSNumber*) thePressure {
    if(thePressure.doubleValue <= 1100 && thePressure.doubleValue >= 850) {
        //We have a valid pressure, create a message containing it
        //Create a protobuf with this stuff and send it
        DroneMessage* msg = [[DroneMessage alloc] init];
        msg.seaLevelPressure = thePressure.doubleValue;
        
        XBeeMessage* xBeeMsg = [[XBeeMessage alloc] initWithPayload: msg.data];
        
        xBeeMsg.shouldAck = true;
        xBeeMsg.frameID = 0xFE;
        
        [myPort sendData: xBeeMsg.encodeMessage];
    }
}

//This method invalidates the Attitude and map view when the timeout is exceeded
- (void) timeOutExceeded:(NSTimer*) theTimer {
    //Send a nil attitude to the delegates
    [attitudeDelegate attituteChangedToCourse: nil
                                        pitch: nil
                                         roll: nil];
    [positionDelegate positionChangedToLatitude: nil longitude: nil];
    [positionDelegate airspeedChangedTo: nil];
    [positionDelegate altitudeChanged: nil];
}

//This method collects a sample from the XBox controller and sends it to the drine
- (void) sendControllerSample: (NSTimer*) theTimer {
    commandSet cs = [controllerModel getValues];
    
    if(controllerDelegate) {
        NSNumber* pitch = [NSNumber numberWithDouble: cs.elevator];
        NSNumber* yaw = [NSNumber numberWithDouble: cs.rudder];
        NSNumber* thrust = [NSNumber numberWithDouble: cs.thrust];
        
        [controllerDelegate controllerChangedWithPitch: pitch yaw: yaw thrust: thrust];
    }
    
    //Create a protobuf with this stuff and send it
    DroneMessage* msg = [[DroneMessage alloc] init];
    
     //TODO: Code here ;)
    
    XBeeMessage* xBeeMsg = [[XBeeMessage alloc] initWithPayload: msg.data];
    
    xBeeMsg.shouldAck = false;
    xBeeMsg.frameID = 0x00;
    
    [myPort sendData: xBeeMsg.encodeMessage];
}

//This method gets RSSI from the local and remite stations and sends them to the delgate
-(void) fetchRssi: (NSTimer*) theTimer {
    //Create the payload for a message querying remote RSSI
    NSString* command = @"DB";
    NSData* remoteRssiMessage = [XBeeMessage encodeRemoteAtCommand: command Value: nil FrameID: 0xA0 applyChanges: NO];
    [myPort sendData: remoteRssiMessage];

    //Create the payload for querying the local RSSI
    NSData* localRssiMessage = [XBeeMessage encodeLocalAtCommand: command Value: nil FrameID: 0xA0 applyChanges: NO];
    [myPort sendData: localRssiMessage];

    //Create the payload for querying the local duty cycle
    command = @"DC";
    NSData* localDcMessage = [XBeeMessage encodeLocalAtCommand: command Value: nil FrameID: 0xA0 applyChanges: NO];
    [myPort sendData: localDcMessage];
}

//Methods to implement ORSerialDelegate
- (void)serialPort:(ORSSerialPort *)serialPort didReceiveData:(NSData *)data {
    //append the new data
    [receivedData appendData: data];
    
    //Discard the front until it is 0x7e
    uint8_t firstByte = 0x00;
    [receivedData getBytes: &firstByte length: 1];
    while (firstByte != 0x7e && receivedData.length > 1) {
        const uint8_t* receivedBytes = receivedData.bytes;
        NSMutableData* newData = [NSMutableData dataWithBytes: (receivedBytes + 1) length: receivedData.length - 1];
        receivedData = newData;
        [receivedData getBytes: &firstByte length: 1];
    }
    if(receivedData.length < 3) {
        return;
    }
    
    //Now the first byte is definately 0x7e. Check the size, if we have the complete message process it and remove it form the buffer
    uint8_t recSizeLSB;
    uint8_t recSizeMSB;
    [receivedData getBytes: &recSizeMSB range: NSMakeRange(1, 1)];
    [receivedData getBytes: &recSizeLSB range: NSMakeRange(2, 1)];
    
    uint16_t recSize = (recSizeMSB << 8) | recSizeLSB;
    
    if(receivedData.length > recSize + 4) { //Three bytes header + one byte checksum
        NSData* packet = [NSData dataWithBytes: receivedData.bytes length: recSize + 4];
        
        NSMutableData* newData = [NSMutableData dataWithBytes: (receivedData.bytes + recSize + 4) length: receivedData.length - (recSize + 4)];
        receivedData = newData;
        
        XBeeMessage* myMsg = [[XBeeMessage alloc] initWithRawMessage: packet];
        if(myMsg.payloadData != nil) {
            NSError* myError;
            DroneMessage* myDecodedMsg = [DroneMessage parseFromData: myMsg.payloadData error: &myError];
            
            if(myDecodedMsg.hasCurrentAttitude) {
                double heading = myDecodedMsg.currentAttitude.courseMagnetic/64.0;
                double pitch = myDecodedMsg.currentAttitude.pitch/64.0;
                double roll = myDecodedMsg.currentAttitude.roll/64.0;
                if(attitudeDelegate) {
                    [attitudeDelegate attituteChangedToCourse: [NSNumber numberWithDouble: heading]
                                                        pitch: [NSNumber numberWithDouble: pitch]
                                                         roll: [NSNumber numberWithDouble: roll]];
                    
                    //Dlete the old timeout timer and start a new one
                    if(instrumentTimeoutTimer) {
                        [instrumentTimeoutTimer invalidate];
                    }
                    instrumentTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval: INSTRUMENTTIMEOUT target: self selector: @selector(timeOutExceeded:) userInfo: nil repeats: NO];
                    instrumentTimeoutTimer.tolerance = 0.5;
                }
            } else {
                NSLog(@"Invalid message (no attitude)");
            }
            
            if(myDecodedMsg.hasCurrentPosition) {
                double latitude = myDecodedMsg.currentPosition.latitude;
                double longitude = myDecodedMsg.currentPosition.longitude;
                if(positionDelegate) {
                    [positionDelegate positionChangedToLatitude: [NSNumber numberWithDouble: latitude]
                                                      longitude: [NSNumber numberWithDouble: longitude]];
                }
            }


            if(myDecodedMsg.hasCurrentAirspeed) {
                double speed = 3.6 * (myDecodedMsg.currentAirspeed.speed / (100)); //Hopefully cm/s to km/h
                if(positionDelegate) {
                    [positionDelegate airspeedChangedTo: [NSNumber numberWithDouble: speed]];
                }
            }
            
            if(myDecodedMsg.hasCurrentAltitude) {
                double altitude = myDecodedMsg.currentAltitude.altitude / 100.0;
                if(positionDelegate) {
                    [positionDelegate altitudeChanged: [NSNumber numberWithDouble: altitude]];
                }
            }
            
            if(myDecodedMsg.hasCurrentBatteryData) {
                double voltage = myDecodedMsg.currentBatteryData.voltage / 1000.0;
                double current = myDecodedMsg.currentBatteryData.current / 1000.0;
                
                if(batteryDelegate) {
                    [batteryDelegate batteryChangedToVoltage: [NSNumber numberWithDouble: voltage]
                                                     current: [NSNumber numberWithDouble: current]];
                }
            }
        } else if (myMsg.remoteRssi != nil) {
            [batteryDelegate rssiChangedToRemote: myMsg.remoteRssi];
        } else if (myMsg.localRssi != nil) {
            [batteryDelegate rssiChangedToLocal: myMsg.localRssi];
        } else if (myMsg.dutyCycle != nil) {
            [batteryDelegate dutyCycleChangedTo: myMsg.dutyCycle];
        }
        
        //If we still have a valid message, recurse
        if(receivedData.length >= 3) {
            uint8_t recSizeLSB;
            uint8_t recSizeMSB;
            [receivedData getBytes: &recSizeMSB range: NSMakeRange(1, 1)];
            [receivedData getBytes: &recSizeLSB range: NSMakeRange(2, 1)];
            
            uint16_t recSize = (recSizeMSB << 8) | recSizeLSB;
            
            if(receivedData.length > recSize + 4) {
                [self serialPort: serialPort didReceiveData: [NSData dataWithBytes: NULL length: 0]];
            }
        }
    }
}

+(float) mapfloat: (float)x fromMin: (float)in_min fromMax:(float)in_max toMin:(float) out_min toMax:(float) out_max {
    float out = (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
    if(out < out_min) {
        out = out_min;
    } else if(out > out_max) {
        out = out_max;
    }
    return out;
}

-(void) serialPortWasRemovedFromSystem:(ORSSerialPort *)serialPort {
    NSAlert* serialPortAlert = [[NSAlert alloc] init];
    serialPortAlert.messageText = @"Serial port removed!";
    [serialPortAlert beginSheetModalForWindow: [[NSApp windows] firstObject] completionHandler: nil];
}

@end
