//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/ProfileManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kOWSProfileManager_MaxAvatarDiameterPixels;
extern NSString *const kNSNotificationKey_UserProfileWriter;

@protocol RecipientHidingManager;

@class MessageSender;
@class OWSAES256Key;
@class OWSUserProfile;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSDatabaseStorage;
@class SDSKeyValueStore;
@class SignalServiceAddress;
@class TSThread;

typedef void (^ProfileManagerFailureBlock)(NSError *error);

@interface OWSProfileSnapshot : NSObject

@property (nonatomic, readonly, nullable) NSString *givenName;
@property (nonatomic, readonly, nullable) NSString *familyName;
@property (nonatomic, readonly, nullable) NSString *fullName;
@property (nonatomic, readonly, nullable) NSString *bio;
@property (nonatomic, readonly, nullable) NSString *bioEmoji;

@property (nonatomic, readonly, nullable) NSData *avatarData;
@property (nonatomic, readonly, nullable) NSArray<OWSUserProfileBadgeInfo *> *profileBadgeInfo;

@end

#pragma mark -

// This class can be safely accessed and used from any thread.
@interface OWSProfileManager : NSObject <ProfileManagerProtocol>

@property (nonatomic, readonly) SDSKeyValueStore *whitelistedPhoneNumbersStore;
@property (nonatomic, readonly) SDSKeyValueStore *whitelistedUUIDsStore;
@property (nonatomic, readonly) SDSKeyValueStore *whitelistedGroupsStore;
@property (nonatomic, readonly) BadgeStore *badgeStore;

// This property is used by the Swift extension to ensure that
// only one profile update is in flight at a time.  It should
// only be accessed on the main thread.
@property (nonatomic) BOOL isUpdatingProfileOnService;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDatabaseStorage:(SDSDatabaseStorage *)databaseStorage
                 recipientHidingManager:(id<RecipientHidingManager>)recipientHidingManager NS_DESIGNATED_INITIALIZER;

#pragma mark - Local Profile

- (nullable OWSUserProfile *)getLocalUserProfileWithTransaction:(SDSAnyReadTransaction *)transaction;

// These two methods should only be called from the main thread.
- (OWSAES256Key *)localProfileKey;
// localUserProfileExists is true if there is _ANY_ local profile.
- (BOOL)localProfileExistsWithTransaction:(SDSAnyReadTransaction *)transaction;
// hasLocalProfile is true if there is a local profile with a name or avatar.
- (BOOL)hasLocalProfile;
- (nullable NSString *)localGivenName;
- (nullable NSString *)localFamilyName;
- (nullable NSString *)localFullName;
- (nullable UIImage *)localProfileAvatarImage;
- (nullable NSData *)localProfileAvatarData;
- (nullable NSArray<OWSUserProfileBadgeInfo *> *)localProfileBadgeInfo;

- (OWSProfileSnapshot *)localProfileSnapshotWithShouldIncludeAvatar:(BOOL)shouldIncludeAvatar
    NS_SWIFT_NAME(localProfileSnapshot(shouldIncludeAvatar:));

- (BOOL)isProfileNameTooLong:(nullable NSString *)profileName;

+ (NSData *)avatarDataForAvatarImage:(UIImage *)image;

- (void)fetchLocalUsersProfileWithAuthedAccount:(AuthedAccount *)authedAccount;

#pragma mark - Local Profile Updates

- (void)writeAvatarToDiskWithData:(NSData *)avatarData
                          success:(void (^)(NSString *fileName))successBlock
                          failure:(ProfileManagerFailureBlock)failureBlock;

// OWSUserProfile is a private implementation detail of the profile manager.
//
// Only use this method in profile manager methods on the swift extension.
- (OWSUserProfile *)localUserProfile;

#pragma mark - Profile Whitelist

// These methods are for debugging.
- (void)clearProfileWhitelist;
- (void)removeThreadFromProfileWhitelist:(TSThread *)thread;
- (void)logProfileWhitelist;
- (void)debug_regenerateLocalProfileWithSneakyTransaction;
- (void)setLocalProfileKey:(OWSAES256Key *)key
         userProfileWriter:(UserProfileWriter)userProfileWriter
             authedAccount:(AuthedAccount *)authedAccount
               transaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Other User's Profiles

// This method is for debugging.
- (void)logUserProfiles;

- (nullable NSString *)unfilteredGivenNameForAddress:(SignalServiceAddress *)address
                                         transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)givenNameForAddress:(SignalServiceAddress *)address
                               transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)unfilteredFamilyNameForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)familyNameForAddress:(SignalServiceAddress *)address
                                transaction:(SDSAnyReadTransaction *)transaction;

- (nullable UIImage *)profileAvatarForAddress:(SignalServiceAddress *)address
                            downloadIfMissing:(BOOL)downloadIfMissing
                                authedAccount:(AuthedAccount *)authedAccount
                                  transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)profileBioForDisplayForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction;

#pragma mark - Clean Up

+ (NSSet<NSString *> *)allProfileAvatarFilePathsWithTransaction:(SDSAnyReadTransaction *)transaction;

#pragma mark -

// This method is only exposed for usage by the Swift extensions.
- (NSString *)generateAvatarFilename;

- (NSString *)groupKeyForGroupId:(NSData *)groupId;

#ifdef USE_DEBUG_UI
+ (void)discardAllProfileKeysWithTransaction:(SDSAnyWriteTransaction *)transaction;

- (void)logLocalProfile;
#endif

@end

NS_ASSUME_NONNULL_END
