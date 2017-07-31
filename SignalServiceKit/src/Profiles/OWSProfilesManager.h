//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kNSNotificationName_LocalProfileDidChange;

// This class can be safely accessed and used from any thread.
@interface OWSProfilesManager : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (nullable NSString *)localProfileName;

- (nullable UIImage *)localProfileAvatarImage;

@end

NS_ASSUME_NONNULL_END
