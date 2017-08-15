//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/ProfileManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kNSNotificationName_LocalProfileDidChange;
extern NSString *const kNSNotificationName_OtherUsersProfileDidChange;

@class TSThread;
@class OWSAES128Key;

// This class can be safely accessed and used from any thread.
@interface OWSProfileManager : NSObject <ProfileManagerProtocol>

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (void)resetProfileStorage;

#pragma mark - Local Profile

// These two methods should only be called from the main thread.
- (OWSAES128Key *)localProfileKey;
- (BOOL)hasLocalProfile;
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

#pragma mark - Profile Whitelist

- (void)addThreadToProfileWhitelist:(TSThread *)thread;

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread;

- (BOOL)isUserInProfileWhitelist:(NSString *)recipientId;

- (void)setContactRecipientIds:(NSArray<NSString *> *)contactRecipientIds;

#pragma mark - Other User's Profiles

- (nullable OWSAES128Key *)profileKeyForRecipientId:(NSString *)recipientId;

- (nullable NSString *)profileNameForRecipientId:(NSString *)recipientId;

- (nullable UIImage *)profileAvatarForRecipientId:(NSString *)recipientId;

// Reads raw avatar data from disk if available. Uncached, so shouldn't be used frequently,
// but useful to get the raw image data for populating cnContact.imageData without lossily re-encoding.
- (nullable NSData *)profileAvatarDataForRecipientId:(NSString *)recipientId;

- (void)refreshProfileForRecipientId:(NSString *)recipientId;

- (void)updateProfileForRecipientId:(NSString *)recipientId
               profileNameEncrypted:(nullable NSData *)profileNameEncrypted
                      avatarUrlPath:(nullable NSString *)avatarUrlPath;

@end

NS_ASSUME_NONNULL_END
