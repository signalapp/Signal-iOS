//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSMessageServiceParams.h"

NS_ASSUME_NONNULL_BEGIN
/**
 * Contstructs the per-device-message parameters used when submitting a message to
 * the Signal Web Service. Using a legacy parameter format. Cannot be used for Sync messages.
 */
@interface OWSLegacyMessageServiceParams : OWSMessageServiceParams

- (instancetype)initWithType:(TSWhisperMessageType)type
                 recipientId:(NSString *)destination
                      device:(int)deviceId
                        body:(NSData *)body
              registrationId:(int)registrationId;

@end

NS_ASSUME_NONNULL_END
