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

+ (NSDictionary *)attributesFromStorageWithVoiceSupport:(BOOL)voice {
    return [self attributesWithSignalingKey:[TSStorageManager signalingKey]
                            serverAuthToken:[TSStorageManager serverAuthToken]
                              supportsVoice:voice];
}

+ (NSDictionary *)attributesWithSignalingKey:(NSString *)signalingKey
                             serverAuthToken:(NSString *)authToken
                               supportsVoice:(BOOL)voice

{
    return @{
        @"signalingKey" : signalingKey,
        @"AuthKey" : authToken,
        @"voice" : [NSNumber numberWithBool:voice],
        @"registrationId" : [NSString stringWithFormat:@"%i", [TSAccountManager getOrGenerateRegistrationId]]
    };
}

@end
