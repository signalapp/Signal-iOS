//
//  TSAttributes.h
//  Signal
//
//  Created by Frederic Jacobs on 22/08/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TSAttributes : NSObject

+ (NSDictionary *)attributesFromStorageWithVoiceSupport;

+ (NSDictionary *)attributesWithSignalingKey:(NSString *)signalingKey
                             serverAuthToken:(NSString *)authToken;

@end
