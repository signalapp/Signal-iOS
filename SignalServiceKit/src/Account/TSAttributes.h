//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface TSAttributes : NSObject

+ (NSDictionary *)attributesFromStorageWithVoiceSupport;

+ (NSDictionary *)attributesWithSignalingKey:(NSString *)signalingKey
                             serverAuthToken:(NSString *)authToken;

@end
