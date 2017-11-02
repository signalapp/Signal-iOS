//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSAttributes.h"
#import "TSAccountManager.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSAttributes

+ (NSDictionary *)attributesFromStorageWithManualMessageFetching:(BOOL)isEnabled
{
    return [self attributesWithSignalingKey:TSAccountManager.signalingKey
                            serverAuthToken:TSAccountManager.serverAuthToken
                      manualMessageFetching:isEnabled];
}

+ (NSDictionary *)attributesWithSignalingKey:(NSString *)signalingKey
                             serverAuthToken:(NSString *)authToken
                       manualMessageFetching:(BOOL)isEnabled
{
    return @{
        @"signalingKey" : signalingKey,
        @"AuthKey" : authToken,
        @"voice" : @(YES), // all Signal-iOS clients support voice
        @"video" : @(YES), // all Signal-iOS clients support WebRTC-based voice and video calls.
        @"fetchesMessages" : @(isEnabled), // devices that don't support push must tell the server they fetch messages manually
        @"registrationId" : [NSString stringWithFormat:@"%i", [TSAccountManager getOrGenerateRegistrationId]]
    };
}

@end

NS_ASSUME_NONNULL_END
