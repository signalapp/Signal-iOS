//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kNSNotificationName_LocalProfileDidChange;
extern NSString *const kNSNotificationName_OtherUsersProfileDidChange;

@class TSThread;

// This class can be safely accessed and used from any thread.
@interface OWSProfilesManager : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

#pragma mark - Local Profile

// These two methods should only be called from the main thread.
- (NSData *)localProfileKey;
- (nullable NSString *)localProfileName;
- (nullable UIImage *)localProfileAvatarImage;

// This method is used to update the "local profile" state on the client
// and the service.  Client state is only updated if service state is
// successfully updated.
//
// This method should only be called from the main thread.
- (void)updateLocalProfileName:(nullable NSString *)profileName
                   avatarImage:(nullable UIImage *)avatarImage
                       success:(void (^)())successBlock
                       failure:(void (^)())failureBlock;

// This method should only be called from the main thread.
- (void)appLaunchDidBegin;

#pragma mark - Profile Whitelist

- (void)addUserToProfileWhitelist:(NSString *)recipientId;

- (BOOL)isUserInProfileWhitelist:(NSString *)recipientId;

- (void)addGroupIdToProfileWhitelist:(NSData *)groupId;

- (void)setContactRecipientIds:(NSArray<NSString *> *)contactRecipientIds;

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread;

#pragma mark - Other User's Profiles

+ (void)setProfileKey:(NSData *)profileKey forRecipientId:(NSString *)recipientId;

- (nullable NSData *)profileKeyForRecipientId:(NSString *)recipientId;

- (nullable NSString *)profileNameForRecipientId:(NSString *)recipientId;

- (nullable UIImage *)profileAvatarForRecipientId:(NSString *)recipientId;

- (void)refreshProfileForRecipientId:(NSString *)recipientId;

@end

NS_ASSUME_NONNULL_END
