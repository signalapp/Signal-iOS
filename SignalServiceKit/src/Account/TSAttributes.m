//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSAttributes.h"
#import "TSAccountManager.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSAttributes

+ (NSDictionary *)attributesFromStorageWithManualMessageFetching:(BOOL)isEnabled pin:(nullable NSString *)pin
{
    return [self attributesWithSignalingKey:TSAccountManager.signalingKey
                            serverAuthToken:TSAccountManager.serverAuthToken
                      manualMessageFetching:isEnabled
                                        pin:pin];
}

+ (NSDictionary *)attributesWithSignalingKey:(NSString *)signalingKey
                             serverAuthToken:(NSString *)authToken
                       manualMessageFetching:(BOOL)isEnabled
                                         pin:(nullable NSString *)pin
{
    OWSAssertDebug(signalingKey.length > 0);
    OWSAssertDebug(authToken.length > 0);

    NSMutableDictionary *result = [@{
        @"signalingKey" : signalingKey,
        @"AuthKey" : authToken,
        @"voice" : @(YES), // all Signal-iOS clients support voice
        @"video" : @(YES), // all Signal-iOS clients support WebRTC-based voice and video calls.
        @"fetchesMessages" :
            @(isEnabled), // devices that don't support push must tell the server they fetch messages manually
        @"registrationId" : [NSString stringWithFormat:@"%i", [TSAccountManager getOrGenerateRegistrationId]]
    } mutableCopy];
    if (pin.length > 0) {
        result[@"pin"] = pin;
    }
    return [result copy];
}

@end

NS_ASSUME_NONNULL_END
