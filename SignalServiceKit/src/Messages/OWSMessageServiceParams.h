//  Created by Frederic Jacobs on 18/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSConstants.h"
#import <Mantle/Mantle.h>

/**
 * Contstructs the per-device-message parameters used when submitting a message to
 * the Signal Web Service.
 */
@interface OWSMessageServiceParams : MTLModel <MTLJSONSerializing>

@property (nonatomic, readonly) int type;
@property (nonatomic, readonly) NSString *destination;
@property (nonatomic, readonly) int destinationDeviceId;
@property (nonatomic, readonly) int destinationRegistrationId;
@property (nonatomic, readonly) NSString *content;

- (instancetype)initWithType:(TSWhisperMessageType)type
                 recipientId:(NSString *)destination
                      device:(int)deviceId
                     content:(NSData *)content
              registrationId:(int)registrationId;

@end
