//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface TSAttributes : NSObject

+ (NSDictionary *)attributesFromStorageWithManualMessageFetching:(BOOL)isEnabled;

+ (NSDictionary *)attributesWithSignalingKey:(NSString *)signalingKey
                             serverAuthToken:(NSString *)authToken
                       manualMessageFetching:(BOOL)isEnabled;

@end

NS_ASSUME_NONNULL_END
