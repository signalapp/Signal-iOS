//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@class AnyPromise;
@class AuthedAccount;
@class BadgeStore;
@class ModelReadCacheSizeLease;
@class OWSAES256Key;
@class OWSUserProfile;
@class OWSUserProfileBadgeInfo;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;

@protocol SSKMaybeString;

@class SignalServiceAddress;
@class TSThread;

NS_ASSUME_NONNULL_BEGIN

// This enum is serialized.
typedef NS_ENUM(NSUInteger, UserProfileWriter) {
    UserProfileWriter_LocalUser = 0,
    UserProfileWriter_ProfileFetch,
    UserProfileWriter_StorageService,
    UserProfileWriter_SyncMessage,
    UserProfileWriter_Registration,
    UserProfileWriter_Linking,
    UserProfileWriter_GroupState,
    UserProfileWriter_Reupload,
    UserProfileWriter_AvatarDownload,
    UserProfileWriter_MetadataUpdate,
    UserProfileWriter_Debugging,
    UserProfileWriter_Tests,
    UserProfileWriter_Unknown,
    UserProfileWriter_SystemContactsFetch,
    UserProfileWriter_ChangePhoneNumber,
};

#pragma mark -

@protocol ProfileManagerProtocol <NSObject>

@property (nonatomic, readonly) BadgeStore *badgeStore;

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

- (nullable NSString *)fullNameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction;
- (NSArray<id<SSKMaybeString>> *)fullNamesForAddresses:(NSArray<SignalServiceAddress *> *)addresses
                                           transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSPersonNameComponents *)nameComponentsForProfileWithAddress:(SignalServiceAddress *)address
                                                             transaction:(SDSAnyReadTransaction *)transaction;

- (nullable OWSUserProfile *)getUserProfileForAddress:(SignalServiceAddress *)addressParam
                                          transaction:(SDSAnyReadTransaction *)transaction;
- (NSDictionary<SignalServiceAddress *, OWSUserProfile *> *)
    getUserProfilesForAddresses:(NSArray<SignalServiceAddress *> *)addresses
                    transaction:(SDSAnyReadTransaction *)transaction;
- (nullable NSData *)profileKeyDataForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction;
- (nullable OWSAES256Key *)profileKeyForAddress:(SignalServiceAddress *)address
                                    transaction:(SDSAnyReadTransaction *)transaction;
- (void)setProfileKeyData:(NSData *)profileKeyData
               forAddress:(SignalServiceAddress *)address
        userProfileWriter:(UserProfileWriter)userProfileWriter
            authedAccount:(AuthedAccount *)authedAccount
              transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)hasProfileAvatarData:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;
- (nullable NSData *)profileAvatarDataForAddress:(SignalServiceAddress *)address
                                     transaction:(SDSAnyReadTransaction *)transaction;
- (nullable NSString *)profileAvatarURLPathForAddress:(SignalServiceAddress *)address
                                    downloadIfMissing:(BOOL)downloadIfMissing
                                        authedAccount:(AuthedAccount *)authedAccount
                                          transaction:(SDSAnyReadTransaction *)transaction;
- (nullable NSURL *)writeAvatarDataToFile:(NSData *)avatarData NS_SWIFT_NAME(writeAvatarDataToFile(_:));

- (void)fillInMissingProfileKeys:(NSDictionary<SignalServiceAddress *, NSData *> *)profileKeys
               userProfileWriter:(UserProfileWriter)userProfileWriter
                   authedAccount:(AuthedAccount *)authedAccount
    NS_SWIFT_NAME(fillInMissingProfileKeys(_:userProfileWriter:authedAccount:));

- (void)setProfileGivenName:(nullable NSString *)firstName
                 familyName:(nullable NSString *)lastName
                 forAddress:(SignalServiceAddress *)address
          userProfileWriter:(UserProfileWriter)userProfileWriter
              authedAccount:(AuthedAccount *)authedAccount
                transaction:(SDSAnyWriteTransaction *)transaction;

- (void)setProfileGivenName:(nullable NSString *)firstName
                 familyName:(nullable NSString *)lastName
              avatarUrlPath:(nullable NSString *)avatarUrlPath
                 forAddress:(SignalServiceAddress *)address
          userProfileWriter:(UserProfileWriter)userProfileWriter
              authedAccount:(AuthedAccount *)authedAccount
                transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isUserInProfileWhitelist:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;

- (void)addThreadToProfileWhitelist:(TSThread *)thread authedAccount:(AuthedAccount *)authedAccount;
- (void)addThreadToProfileWhitelist:(TSThread *)thread
                      authedAccount:(AuthedAccount *)authedAccount
                        transaction:(SDSAnyWriteTransaction *)transaction;

- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address authedAccount:(AuthedAccount *)authedAccount;
- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address
                userProfileWriter:(UserProfileWriter)userProfileWriter
                    authedAccount:(AuthedAccount *)authedAccount
                      transaction:(SDSAnyWriteTransaction *)transaction;

- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses
                     authedAccount:(AuthedAccount *)authedAccount;
- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses
                 userProfileWriter:(UserProfileWriter)userProfileWriter
                     authedAccount:(AuthedAccount *)authedAccount
                       transaction:(SDSAnyWriteTransaction *)transaction;

- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address authedAccount:(AuthedAccount *)authedAccount;
- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address
                     userProfileWriter:(UserProfileWriter)userProfileWriter
                         authedAccount:(AuthedAccount *)authedAccount
                           transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isGroupIdInProfileWhitelist:(NSData *)groupId transaction:(SDSAnyReadTransaction *)transaction;
- (void)addGroupIdToProfileWhitelist:(NSData *)groupId;
- (void)addGroupIdToProfileWhitelist:(NSData *)groupId
                   userProfileWriter:(UserProfileWriter)userProfileWriter
                         transaction:(SDSAnyWriteTransaction *)transaction;
- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId;
- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId
                        userProfileWriter:(UserProfileWriter)userProfileWriter
                              transaction:(SDSAnyWriteTransaction *)transaction;

- (void)fetchLocalUsersProfileWithAuthedAccount:(AuthedAccount *)authedAccount
    NS_SWIFT_NAME(fetchLocalUsersProfile(authedAccount:));

- (AnyPromise *)fetchLocalUsersProfilePromiseWithAuthedAccount:(AuthedAccount *)authedAccount
    NS_SWIFT_NAME(fetchLocalUsersProfilePromise(authedAccount:));

- (void)fetchProfileForAddress:(SignalServiceAddress *)address authedAccount:(AuthedAccount *)authedAccount;

// Profile fetches will make a best effort
// to download and decrypt avatar data,
// but optionalAvatarFileUrl may
// not be populated due to network failures,
// decryption errors, service issues, etc.
- (void)updateProfileForAddress:(SignalServiceAddress *)address
                      givenName:(nullable NSString *)givenName
                     familyName:(nullable NSString *)familyName
                            bio:(nullable NSString *)bio
                       bioEmoji:(nullable NSString *)bioEmoji
               isStoriesCapable:(BOOL)isStoriesCapable
                  avatarUrlPath:(nullable NSString *)avatarUrlPath
          optionalAvatarFileUrl:(nullable NSURL *)optionalAvatarFileUrl
                  profileBadges:(nullable NSArray<OWSUserProfileBadgeInfo *> *)profileBadges
           canReceiveGiftBadges:(BOOL)canReceiveGiftBadges
                  lastFetchDate:(NSDate *)lastFetchDate
              userProfileWriter:(UserProfileWriter)userProfileWriter
                  authedAccount:(AuthedAccount *)authedAccount
                    transaction:(SDSAnyWriteTransaction *)writeTx;

- (BOOL)recipientAddressIsStoriesCapable:(SignalServiceAddress *)address
                             transaction:(SDSAnyReadTransaction *)transaction;

- (void)warmCaches;

@property (nonatomic, readonly) BOOL hasProfileName;

// This is an internal implementation detail and should only be used by OWSUserProfile.
- (void)localProfileWasUpdated:(OWSUserProfile *)localUserProfile;

- (AnyPromise *)downloadAndDecryptProfileAvatarForProfileAddress:(SignalServiceAddress *)profileAddress
                                                   avatarUrlPath:(NSString *)avatarUrlPath
                                                      profileKey:(OWSAES256Key *)profileKey;

- (void)didSendOrReceiveMessageFromAddress:(SignalServiceAddress *)address
                             authedAccount:(AuthedAccount *)authedAccount
                               transaction:(SDSAnyWriteTransaction *)transaction;

- (void)reuploadLocalProfileWithAuthedAccount:(AuthedAccount *)authedAccount
    NS_SWIFT_NAME(reuploadLocalProfile(authedAccount:));

- (nullable ModelReadCacheSizeLease *)leaseCacheSize:(NSInteger)size;

- (NSArray<SignalServiceAddress *> *)allWhitelistedRegisteredAddressesWithTransaction:
    (SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
