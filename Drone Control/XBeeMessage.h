//
//  XBeeMessage.h
//  test
//
//  Created by Ludger Heide on 18.10.15.
//  Copyright © 2015 Ludger Heide. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum atCommandStatus {
    OK = 0,
    ERROR = 1,
    Invalid_command = 2,
    Invalid_parameter = 4
} atCommandStatus;

@protocol XBeeDelegate <NSObject>
@required
-(void) didReceiveTransmitStatusWithFrameID: (uint8_t) frameID retryCount: (uint8_t) retryCount txStatus: (uint8_t) txStatus;
@end

@interface XBeeMessage : NSObject

@property (nonatomic, weak, nullable) id<XBeeDelegate> delegate;

@property (nonatomic) BOOL shouldAck;
@property (nonatomic) uint8_t frameID;
@property (nonatomic, readonly) NSNumber* _Nullable remoteRssi;
@property (nonatomic, readonly) NSNumber* _Nullable localRssi;
@property (nonatomic, readonly) NSNumber* _Nullable dutyCycle;
@property NSData* _Nullable payloadData;

-(XBeeMessage * _Nonnull) initWithPayload: (NSData* _Nonnull) payload;
-(XBeeMessage* _Nullable) initWithRawMessage: (NSData* _Nonnull) rawMessage;

-(void) decodeMessage: (NSData* _Nonnull) rawMessage;
-(NSData*  _Nullable) encodeMessage;
+(NSData*  _Nullable)  encodeRemoteAtCommand: (NSString* _Nonnull) command Value: (NSNumber* _Nullable) value FrameID: (uint8_t) theFrameId applyChanges: (Boolean) applyChanges;
+(NSData*  _Nullable)  encodeLocalAtCommand: (NSString* _Nonnull) command Value: (NSNumber* _Nullable) value FrameID: (uint8_t) theFrameId applyChanges: (Boolean) applyChanges;

@end
