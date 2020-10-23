//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

@class AnyPromise;
@class OWSAES256Key;
@class OWSUserProfile;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SignalServiceAddress;
@class TSThread;

NS_ASSUME_NONNULL_BEGIN

@protocol ProfileManagerProtocol <NSObject>

- (OWSAES256Key *)localProfileKey;
// localUserProfileExists is true if there is _ANY_ local profile.
- (BOOL)localProfileExistsWithTransaction:(SDSAnyReadTransaction *)transaction;
// hasLocalProfile is true if there is a local profile with a name or avatar.
- (BOOL)hasLocalProfile;
- (nullable NSString *)localGivenName;
- (nullable NSString *)localFamilyName;
- (nullable NSString *)localFullName;
- (nullable NSString *)localUsername;
- (nullable UIImage *)localProfileAvatarImage;
- (nullable NSData *)localProfileAvatarData;

- (nullable NSString *)fullNameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSData *)profileKeyDataForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction;
- (nullable OWSAES256Key *)profileKeyForAddress:(SignalServiceAddress *)address
                                    transaction:(SDSAnyReadTransaction *)transaction;
- (void)setProfileKeyData:(NSData *)profileKeyData
               forAddress:(SignalServiceAddress *)address
      wasLocallyInitiated:(BOOL)wasLocallyInitiated
              transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)hasProfileAvatarData:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;
- (nullable NSData *)profileAvatarDataForAddress:(SignalServiceAddress *)address
                                     transaction:(SDSAnyReadTransaction *)transaction;
- (nullable NSString *)profileAvatarURLPathForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction;

- (void)fillInMissingProfileKeys:(NSDictionary<SignalServiceAddress *, NSData *> *)profileKeys
    NS_SWIFT_NAME(fillInMissingProfileKeys(_:));

- (void)setProfileGivenName:(nullable NSString *)firstName
                 familyName:(nullable NSString *)lastName
                 forAddress:(SignalServiceAddress *)address
        wasLocallyInitiated:(BOOL)wasLocallyInitiated
                transaction:(SDSAnyWriteTransaction *)transaction;

- (void)setProfileGivenName:(nullable NSString *)firstName
                 familyName:(nullable NSString *)lastName
              avatarUrlPath:(nullable NSString *)avatarUrlPath
                 forAddress:(SignalServiceAddress *)address
        wasLocallyInitiated:(BOOL)wasLocallyInitiated
                transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isUserInProfileWhitelist:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;

- (void)addThreadToProfileWhitelist:(TSThread *)thread;
- (void)addThreadToProfileWhitelist:(TSThread *)thread transaction:(SDSAnyWriteTransaction *)transaction;

- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address;
- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address
              wasLocallyInitiated:(BOOL)wasLocallyInitiated
                      transaction:(SDSAnyWriteTransaction *)transaction;

- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses;

- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address;
- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address
                   wasLocallyInitiated:(BOOL)wasLocallyInitiated
                           transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isGroupIdInProfileWhitelist:(NSData *)groupId transaction:(SDSAnyReadTransaction *)transaction;
- (void)addGroupIdToProfileWhitelist:(NSData *)groupId;
- (void)addGroupIdToProfileWhitelist:(NSData *)groupId
                 wasLocallyInitiated:(BOOL)wasLocallyInitiated
                         transaction:(SDSAnyWriteTransaction *)transaction;
- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId;
- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId
                      wasLocallyInitiated:(BOOL)wasLocallyInitiated
                              transaction:(SDSAnyWriteTransaction *)transaction;

- (void)fetchLocalUsersProfile;

- (AnyPromise *)fetchLocalUsersProfilePromise;

- (void)fetchProfileForAddress:(SignalServiceAddress *)address;

- (AnyPromise *)fetchProfileForAddressPromise:(SignalServiceAddress *)address;
- (AnyPromise *)fetchProfileForAddressPromise:(SignalServiceAddress *)address
                                  mainAppOnly:(BOOL)mainAppOnly
                             ignoreThrottling:(BOOL)ignoreThrottling;

// Profile fetches will make a best effort
// to download and decrypt avatar data,
// but optionalDecryptedAvatarData may
// not be populated due to network failures,
// decryption errors, service issues, etc.
- (void)updateProfileForAddress:(SignalServiceAddress *)address
                      givenName:(nullable NSString *)givenName
                     familyName:(nullable NSString *)familyName
                       username:(nullable NSString *)username
                  isUuidCapable:(BOOL)isUuidCapable
                  avatarUrlPath:(nullable NSString *)avatarUrlPath
    optionalDecryptedAvatarData:(nullable NSData *)optionalDecryptedAvatarData
                  lastFetchDate:(NSDate *)lastFetchDate;

- (BOOL)recipientAddressIsUuidCapable:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (void)warmCaches;

@property (nonatomic, readonly) BOOL hasProfileName;

// This is an internal implementation detail and should only be used by OWSUserProfile.
- (void)localProfileWasUpdated:(OWSUserProfile *)localUserProfile;

- (AnyPromise *)downloadAndDecryptProfileAvatarForProfileAddress:(SignalServiceAddress *)profileAddress
                                                   avatarUrlPath:(NSString *)avatarUrlPath
                                                      profileKey:(OWSAES256Key *)profileKey;

- (void)didSendOrReceiveMessageFromAddress:(SignalServiceAddress *)address
                               transaction:(SDSAnyWriteTransaction *)transaction;

- (void)reuploadLocalProfile;

@end

NS_ASSUME_NONNULL_END
