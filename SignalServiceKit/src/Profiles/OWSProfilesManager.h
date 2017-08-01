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

// This method is used to update the "local profile" state on the client
// and the service.  Client state is only updated if service state is
// successfully updated.
- (void)setLocalProfileName:(nullable NSString *)localProfileName
    localProfileAvatarImage:(nullable UIImage *)localProfileAvatarImage
                    success:(void (^)())successBlock
                    failure:(void (^)())failureBlock;

@end

NS_ASSUME_NONNULL_END
