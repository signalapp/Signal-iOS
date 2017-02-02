//
//  TSAttributes.m
//  Signal
//
//  Created by Frederic Jacobs on 22/08/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSAttributes.h"

#import "TSAccountManager.h"
#import "TSStorageHeaders.h"

@implementation TSAttributes

+ (NSDictionary *)attributesFromStorage:(BOOL)isWebRTCEnabled {
    return [self attributesWithSignalingKey:[TSStorageManager signalingKey]
                            serverAuthToken:[TSStorageManager serverAuthToken]
                            isWebRTCEnabled:isWebRTCEnabled];
}

+ (NSDictionary *)attributesWithSignalingKey:(NSString *)signalingKey
                             serverAuthToken:(NSString *)authToken
                             isWebRTCEnabled:(BOOL)isWebRTCEnabled
{
    return @{
        @"signalingKey" : signalingKey,
        @"AuthKey" : authToken,
        @"voice" : @(YES), // all Signal-iOS clients support voice
        @"video" : @(isWebRTCEnabled),
        @"registrationId" : [NSString stringWithFormat:@"%i", [TSAccountManager getOrGenerateRegistrationId]]
    };
}

@end
