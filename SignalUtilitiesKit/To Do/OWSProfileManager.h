//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SessionMessagingKit/ProfileManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kNSNotificationName_ProfileWhitelistDidChange;
extern NSString *const kNSNotificationName_ProfileKeyDidChange;

extern const NSUInteger kOWSProfileManager_NameDataLength;
extern const NSUInteger kOWSProfileManager_MaxAvatarDiameter;

@class OWSAES256Key;
@class OWSMessageSender;
@class OWSPrimaryStorage;
@class TSNetworkManager;
@class TSThread;
@class YapDatabaseReadWriteTransaction;

// This class can be safely accessed and used from any thread.
@interface OWSProfileManager : NSObject <ProfileManagerProtocol>

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage;

+ (instancetype)sharedManager;

#pragma mark - Local Profile

// localUserProfileExists is true if there is _ANY_ local profile.
- (BOOL)localProfileExists;
// hasLocalProfile is true if there is a local profile with a name or avatar.
- (BOOL)hasLocalProfile;

// This method is used to update the "local profile" state on the client
// and the service.  Client state is only updated if service state is
// successfully updated.
//
// This method should only be called from the main thread.
- (void)updateLocalProfileName:(nullable NSString *)profileName
                   avatarImage:(nullable UIImage *)avatarImage
                       success:(void (^)(void))successBlock
                       failure:(void (^)(NSError *))failureBlock
                  requiresSync:(BOOL)requiresSync;

- (BOOL)isProfileNameTooLong:(nullable NSString *)profileName;

- (void)regenerateLocalProfile;

#pragma mark - Other Users' Profiles

- (nullable UIImage *)profileAvatarForRecipientId:(NSString *)recipientId;
- (nullable NSData *)profileAvatarDataForRecipientId:(NSString *)recipientId;

- (void)updateProfileForRecipientId:(NSString *)recipientId
               profileNameEncrypted:(nullable NSData *)profileNameEncrypted
                      avatarUrlPath:(nullable NSString *)avatarUrlPath;

#pragma mark - Other

- (void)downloadAvatarForUserProfile:(SNContact *)contact;

@end

NS_ASSUME_NONNULL_END
