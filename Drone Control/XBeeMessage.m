//
//  XBeeMessage.m
//  test
//
//  Created by Ludger Heide on 18.10.15.
//  Copyright © 2015 Ludger Heide. All rights reserved.
//

#import "XBeeMessage.h"

#define NONDATA_SIZE 14
#define NONDATA_SIZE_INCLUDING_HEADER 18
#define REMOTE_AT_COMMAND_SIZE_WITHOUT_VALUE 19
#define LOCAL_AT_COMMAND_SIZE_WITHOUT_VALUE 8

#define FRAME_ID_INDEX 4

#define ACKFLAG_INDEX 16
#define ACKFLAG_YES 0b00000000
#define ACKFLAG_NO 0b00000001

//Private vars

@implementation XBeeMessage

//Setters/getters
@synthesize payloadData;
@synthesize shouldAck;
@synthesize frameID;
@synthesize delegate;

@synthesize remoteRssi;
@synthesize localRssi;
@synthesize dutyCycle;

//Initializers
-(XBeeMessage*) initWithPayload: (NSData*) payload {
    //We only support a payload lower than 100 bytea
    if(payload.length >= 100) {
        return nil;
    }
    
    self = [super init];
    
    if(self) {
        shouldAck = NO;
        frameID = 0;
        payloadData = payload;
    }
    return self;
}

-(XBeeMessage*) initWithRawMessage: (NSData*) rawMessage {
    self = [super init];
    
    if(self) {
        uint8_t firstThreeBytes[3];
        [rawMessage getBytes: &firstThreeBytes length: 3];
        
        uint16_t length = 0;
        if(firstThreeBytes[0] == 0x7E) {
            length = firstThreeBytes[1];
            length |= firstThreeBytes[2];
        }
        
        if(length == rawMessage.length - 4) {
            [self decodeMessage: rawMessage];
            if(!payloadData && !remoteRssi && !localRssi && !dutyCycle) {
                return nil;
            }
        } else {
            return nil;
        }
    }
    return self;
}

-(void) decodeMessage:(NSData *)rawMessage {
    const unsigned char* msgBytes = rawMessage.bytes;
    
#define XBEE_MSGTYPE_TXSTATUS 0x8B
#define XBEE_MSGTYPE_RECEIVE 0x90
#define XBEE_MSGTYPE_REMOTE_AT_COMMAND_RESPONSE 0x97
#define XBEE_MSGTYPE_LOCAL_AT_COMMAND_RESPONSE 0x88
    NSString* tempdir = @"/tmp";
    NSString* timestamp = @([[NSDate date] timeIntervalSince1970]).stringValue;

    switch (msgBytes[3]) {
        case XBEE_MSGTYPE_RECEIVE:
        {
            char* protoBufMessage = (char*)&msgBytes[15];
            uint8_t protoBufSize = rawMessage.length - 16;
            payloadData = [NSData dataWithBytes: protoBufMessage length: protoBufSize];

            //Now write it out to the log file
            NSString* protobufFile = [NSString stringWithFormat: @"%@/protobufs.csv", tempdir];
            NSString* base64String = [payloadData base64EncodedStringWithOptions:0];
            NSString* stringToWrite = [NSString stringWithFormat:@"%@, %@\n", timestamp, base64String];

            NSFileHandle *myHandle = [NSFileHandle fileHandleForUpdatingAtPath: protobufFile];
            if(myHandle == nil) {
                [[NSFileManager defaultManager] createFileAtPath:protobufFile contents:nil attributes:nil];
                myHandle = [NSFileHandle fileHandleForWritingAtPath:protobufFile];
            }
            [myHandle seekToEndOfFile];
            [myHandle writeData:  [stringToWrite dataUsingEncoding:NSUTF8StringEncoding]];
            [myHandle closeFile];
            break;
        }
        case XBEE_MSGTYPE_TXSTATUS:
        {
            NSLog(@"Ack receeved for frame ID %02x, retryCount %02x, txSTatus %02x", msgBytes[4], msgBytes[7], msgBytes[8]);
            if(delegate) {

                [delegate didReceiveTransmitStatusWithFrameID: msgBytes[4] retryCount: msgBytes[7] txStatus: msgBytes[8]];
            }
            //Now write it out to the log file
            NSString* ackFile = [NSString stringWithFormat: @"%@/acks.csv", tempdir];
            NSString* stringToWrite = [NSString stringWithFormat:@"%@, %02x, %02x, %02x\n", timestamp, msgBytes[4], msgBytes[7], msgBytes[8]];
            NSFileHandle *myHandle = [NSFileHandle fileHandleForUpdatingAtPath: ackFile];
            if(myHandle == nil) {
                [[NSFileManager defaultManager] createFileAtPath:ackFile contents:nil attributes:nil];
                myHandle = [NSFileHandle fileHandleForWritingAtPath:ackFile];
            }
            [myHandle seekToEndOfFile];
            [myHandle writeData:  [stringToWrite dataUsingEncoding:NSUTF8StringEncoding]];
            [myHandle closeFile];
            break;
        }
        case XBEE_MSGTYPE_REMOTE_AT_COMMAND_RESPONSE:
        {
            //Read out the response
            uint8_t frameId = msgBytes[4];
            char command[3];
            command[0] = (char)msgBytes[15];
            command[1] = (char)msgBytes[16];
            command[2] = '\0'; //Now, we haca a proper null-terminated c string
            atCommandStatus status = (atCommandStatus)msgBytes[17];

            NSData* payload = nil;
            uint8_t payloadLength = rawMessage.length - 19;
            if(payloadLength != 0) {
                uint8_t* rawPayload = malloc(payloadLength);
                for(uint8_t i = 0; i < payloadLength; i++) {
                    rawPayload[i] = msgBytes[18+i];
                }
                payload = [NSData dataWithBytes: rawPayload length: payloadLength];
                free(rawPayload);
            }
            if (strcmp(command, "DB")==0) {
                remoteRssi = [NSNumber numberWithInteger: (-1 * msgBytes[18])];
            }
            //Now write it out to the log file
            NSString* remoteCommandResponsesFile = [NSString stringWithFormat: @"%@/remoteResponse.csv", tempdir];
            NSString* stringToWrite = [NSString stringWithFormat:@"%@, %s, %i\n", timestamp, command, msgBytes[18]];
            NSFileHandle *myHandle = [NSFileHandle fileHandleForUpdatingAtPath: remoteCommandResponsesFile];
            if(myHandle == nil) {
                [[NSFileManager defaultManager] createFileAtPath:remoteCommandResponsesFile contents:nil attributes:nil];
                myHandle = [NSFileHandle fileHandleForWritingAtPath:remoteCommandResponsesFile];
            }
            [myHandle seekToEndOfFile];
            [myHandle writeData:  [stringToWrite dataUsingEncoding:NSUTF8StringEncoding]];
            [myHandle closeFile];
            break;
        }
        case XBEE_MSGTYPE_LOCAL_AT_COMMAND_RESPONSE:
        {
            //Read out the response
            uint8_t frameId = msgBytes[4];
            char command[3];
            command[0] = (char)msgBytes[5];
            command[1] = (char)msgBytes[6];
            command[2] = '\0'; //Now, we haca a proper null-terminated c string
            atCommandStatus status = (atCommandStatus)msgBytes[7];

            NSData* payload = nil;
            uint8_t payloadLength = rawMessage.length - 9;
            if(payloadLength != 0) {
                uint8_t* rawPayload = malloc(payloadLength);
                for(uint8_t i = 0; i < payloadLength; i++) {
                    rawPayload[i] = msgBytes[8+i];
                }
                payload = [NSData dataWithBytes: rawPayload length: payloadLength];
                free(rawPayload);
            }
            if (strcmp(command, "DB")==0) {
                localRssi = [NSNumber numberWithInteger: (-1 * msgBytes[8])];
            } else if (strcmp(command, "DC")==0) {
                dutyCycle = [NSNumber numberWithInteger: msgBytes[8]];
            }
            //Now write it out to the log file
            NSString* localCommandResponsesFile = [NSString stringWithFormat: @"%@/localResponse.csv", tempdir];
            NSString* stringToWrite = [NSString stringWithFormat:@"%@, %s, %i\n", timestamp, command, msgBytes[8]];
            NSFileHandle *myHandle = [NSFileHandle fileHandleForUpdatingAtPath: localCommandResponsesFile];
            if(myHandle == nil) {
                [[NSFileManager defaultManager] createFileAtPath:localCommandResponsesFile contents:nil attributes:nil];
                myHandle = [NSFileHandle fileHandleForWritingAtPath:localCommandResponsesFile];
            }
            [myHandle seekToEndOfFile];
            [myHandle writeData:  [stringToWrite dataUsingEncoding:NSUTF8StringEncoding]];
            [myHandle closeFile];
            break;
        }
            
        default:
#ifdef COMMS_DEBUG
            printf("Other packet type received!");
#endif
            break;
    }
}

-(NSData*) encodeMessage {
    uint8_t* rawBytes = malloc(payloadData.length + NONDATA_SIZE_INCLUDING_HEADER);
    if(rawBytes == NULL) {
        return nil;
    }
    
    //Set the first byte of the buffer to 0x7E, the magic start number
    rawBytes[0] = 0x7E;
    
    //Add the size of address etc for the size we send to the xbee
    uint16_t sizeForMessage = payloadData.length + NONDATA_SIZE;
    
    rawBytes[1] = sizeForMessage << 8; //MSB goes here
    rawBytes[2] = sizeForMessage; //LSB goes here
    
    //Now set the frame type to 0x10
    rawBytes[3] = 0x10;
    
    //Now the frame ID. If it is 0, no ACK will be sent
    rawBytes[4] = frameID;
    
    //Now the destination address
    const char destinationAddress[8] = {0x00, 0x13, 0xA2, 0x00, 0x40, 0xA3, 0x23, 0x9D};
    //If we swap modules, thsi will bve the destination address
    //const char destinationAddress[8] = {0x00, 0x13, 0xA2, 0x00, 0x40, 0xA3, 0x23, 0x82};
    for(uint8_t i = 0; i < 8; i++) {
        rawBytes[5+i] = destinationAddress[i];
    };
    
    // reserved (0xFFFE=
    rawBytes[13] = 0xFF;
    rawBytes[14] = 0xFE;
    
    //Broadcast radius
    rawBytes[15] = 0x00;
    
    //Transmit options, bit 0 indicates if the remote station should ACK
    if(shouldAck) {
        rawBytes[16] = ACKFLAG_YES;
    } else {
        rawBytes[16] = ACKFLAG_NO;
    }
    
    //Now the RF payload
    const char* payloadBytes = [payloadData bytes];
    
    for (uint8_t i = 0; i < payloadData.length; i++) {
        rawBytes[17 + i] = payloadBytes[i];
    }
    
    rawBytes[17 + payloadData.length] = [XBeeMessage calculateChecksum: &rawBytes[3] forSize: (NONDATA_SIZE + payloadData.length)];
    
    //Now the C stuff is done and we go back into an objective-C Object
    NSData* rawData = [NSData dataWithBytes: rawBytes length: payloadData.length + NONDATA_SIZE_INCLUDING_HEADER];
    free(rawBytes);
    return rawData;
}

+(NSData*  _Nullable)  encodeRemoteAtCommand: (NSString* _Nonnull) command Value: (NSNumber* _Nullable) value FrameID: (uint8_t) theFrameId applyChanges: (Boolean) applyChanges {
    uint16_t bufferLength;
    if(value != nil) {
        bufferLength = REMOTE_AT_COMMAND_SIZE_WITHOUT_VALUE + 1;
    } else {
        bufferLength = REMOTE_AT_COMMAND_SIZE_WITHOUT_VALUE;
    }

    uint8_t* rawBytes = malloc(bufferLength);

    //Now, create the message
    //Set the first byte of the buffer to 0x7E, the magic start number
    rawBytes[0] = 0x7E;

    //Set the length
    rawBytes[1] = (bufferLength-4) << 8; //MSB goes here
    rawBytes[2] = bufferLength-4; //LSB goes here

    //Now set the frame type to 0x17 for remote AT command
    rawBytes[3] = 0x17;

    //Now the frame ID. If it is 0, no ACK will be sent
    rawBytes[4] = theFrameId;

    //Now the destination address
    const char destinationAddress[8] = {0x00, 0x13, 0xA2, 0x00, 0x40, 0xA3, 0x23, 0x9D};
    //If we swap modules, thsi will bve the destination address
    //const char destinationAddress[8] = {0x00, 0x13, 0xA2, 0x00, 0x40, 0xA3, 0x23, 0x82};
    for(uint8_t i = 0; i < 8; i++) {
        rawBytes[5+i] = destinationAddress[i];
    };

    // reserved (0xFFFE)
    rawBytes[13] = 0xFF;
    rawBytes[14] = 0xFE;

    //Appy the remote command
    if(applyChanges) {
        rawBytes[15] = 0x02;
    } else {
        rawBytes[15] = 0x00;
    }

    //Now, the payoad string
    if ([command length] != 2) {
        //The string must be of length 2 to be a valid AT command
        free(rawBytes);
        return nil;
    }
    const char* atCommandString = [command cStringUsingEncoding: NSASCIIStringEncoding];
    rawBytes[16] = atCommandString[0];
    rawBytes[17] = atCommandString[1];

    //The value (if it exists)
    if(value != nil) {
        rawBytes[18] = [value unsignedCharValue];
        rawBytes[19] = [XBeeMessage calculateChecksum: &rawBytes[3] forSize: bufferLength - 4];
    } else {
        rawBytes[18] = [XBeeMessage calculateChecksum: &rawBytes[3] forSize: bufferLength - 4];
    }

    //Now the C stuff is done and we go back into an objective-C Object
    NSData* rawData = [NSData dataWithBytes: rawBytes length: bufferLength];
    free(rawBytes);
    return rawData;
}

+(NSData*  _Nullable)  encodeLocalAtCommand: (NSString* _Nonnull) command Value: (NSNumber* _Nullable) value FrameID: (uint8_t) theFrameId applyChanges: (Boolean) applyChanges {
    uint16_t bufferLength;
    if(value != nil) {
        bufferLength = LOCAL_AT_COMMAND_SIZE_WITHOUT_VALUE + 1;
    } else {
        bufferLength = LOCAL_AT_COMMAND_SIZE_WITHOUT_VALUE;
    }

    uint8_t* rawBytes = malloc(bufferLength);

    //Now, create the message
    //Set the first byte of the buffer to 0x7E, the magic start number
    rawBytes[0] = 0x7E;

    //Set the length
    rawBytes[1] = (bufferLength-4) << 8; //MSB goes here
    rawBytes[2] = bufferLength-4; //LSB goes here

    //Now set the frame type to 0x17 for remote AT command
    rawBytes[3] = 0x08;

    //Now the frame ID. If it is 0, no ACK will be sent
    rawBytes[4] = theFrameId;

    //Now, the payoad string
    if ([command length] != 2) {
        //The string must be of length 2 to be a valid AT command
        free(rawBytes);
        return nil;
    }
    const char* atCommandString = [command cStringUsingEncoding: NSASCIIStringEncoding];
    rawBytes[5] = atCommandString[0];
    rawBytes[6] = atCommandString[1];

    //The value (if it exists)
    if(value != nil) {
        rawBytes[7] = [value unsignedCharValue];
        rawBytes[8] = [XBeeMessage calculateChecksum: &rawBytes[3] forSize: bufferLength - 4];
    } else {
        rawBytes[7] = [XBeeMessage calculateChecksum: &rawBytes[3] forSize: bufferLength - 4];
    }

    //Now the C stuff is done and we go back into an objective-C Object
    NSData* rawData = [NSData dataWithBytes: rawBytes length: bufferLength];
    free(rawBytes);
    return rawData;
}

+(uint8_t) calculateChecksum: (uint8_t*) msg forSize: (uint8_t) size {
    uint8_t checksum = 0x00;
    for(uint8_t i = 0; i < size; i++) {
        checksum += *(msg + i);
    }
    return 0xFF - checksum;
}

@end
