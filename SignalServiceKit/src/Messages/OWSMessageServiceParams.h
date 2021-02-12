//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import <Mantle/Mantle.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

/**
 * Contstructs the per-device-message parameters used when submitting a message to
 * the Signal Web Service.
 *
 * See:
 * https://github.com/signalapp/libsignal-service-java/blob/master/java/src/main/java/org/whispersystems/signalservice/internal/push/OutgoingPushMessage.java
 */
@interface OWSMessageServiceParams : MTLModel <MTLJSONSerializing>

@property (nonatomic, readonly) int type;
@property (nonatomic, readonly) NSString *destination;
@property (nonatomic, readonly) int destinationDeviceId;
@property (nonatomic, readonly) int destinationRegistrationId;
@property (nonatomic, readonly) NSString *content;
@property (nonatomic, readonly) BOOL silent;

- (instancetype)initWithType:(TSWhisperMessageType)type
                     address:(SignalServiceAddress *)address
                      device:(int)deviceId
                     content:(NSData *)content
                    isSilent:(BOOL)isSilent
              registrationId:(int)registrationId;

@end

NS_ASSUME_NONNULL_END
