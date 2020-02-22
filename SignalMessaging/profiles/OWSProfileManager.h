//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/ProfileManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const kNSNotificationNameProfileKeyDidChange;

extern const NSUInteger kOWSProfileManager_NameDataLength;
extern const NSUInteger kOWSProfileManager_MaxAvatarDiameter;
extern const NSString *kNSNotificationKey_WasLocallyInitiated;

@class OWSAES256Key;
@class OWSMessageSender;
@class OWSUserProfile;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSDatabaseStorage;
@class SDSKeyValueStore;
@class SignalServiceAddress;
@class TSNetworkManager;
@class TSThread;

typedef void (^ProfileManagerFailureBlock)(NSError *error);

// This class can be safely accessed and used from any thread.
@interface OWSProfileManager : NSObject <ProfileManagerProtocol>

@property (nonatomic, readonly) SDSKeyValueStore *whitelistedPhoneNumbersStore;
@property (nonatomic, readonly) SDSKeyValueStore *whitelistedUUIDsStore;
@property (nonatomic, readonly) SDSKeyValueStore *whitelistedGroupsStore;

// This property is used by the Swift extension to ensure that
// only one profile update is in flight at a time.  It should
// only be accessed on the main thread.
@property (nonatomic) BOOL isUpdatingProfileOnService;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDatabaseStorage:(SDSDatabaseStorage *)databaseStorage NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

#pragma mark - Local Profile

// These two methods should only be called from the main thread.
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

- (void)updateLocalUsername:(nullable NSString *)username transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isProfileNameTooLong:(nullable NSString *)profileName;

+ (NSData *)avatarDataForAvatarImage:(UIImage *)image;

- (void)fetchAndUpdateLocalUsersProfile;

// The completions are invoked on the main thread.
- (void)fetchAndUpdateProfileForUsername:(NSString *)username
                                 success:(void (^)(SignalServiceAddress *))successHandler
                                notFound:(void (^)(void))notFoundHandler
                                 failure:(void (^)(NSError *))failureHandler;

#pragma mark - Local Profile Updates

- (void)writeAvatarToDiskWithData:(NSData *)avatarData
                          success:(void (^)(NSString *fileName))successBlock
                          failure:(ProfileManagerFailureBlock)failureBlock;

// OWSUserProfile is a private implementation detail of the profile manager.
//
// Only use this method in profile manager methods on the swift extension.
- (OWSUserProfile *)localUserProfile;

// If avatarData is nil, we are clearing the avatar.
- (void)updateServiceWithUnversionedProfileAvatarData:(nullable NSData *)avatarData
                                              success:(void (^)(NSString *_Nullable avatarUrlPath))successBlock
                                              failure:(ProfileManagerFailureBlock)failureBlock
    NS_SWIFT_NAME(updateService(unversionedProfileAvatarData:success:failure:));

// If profileName is nil, we are clearing the profileName.
- (void)updateServiceWithUnversionedGivenName:(nullable NSString *)givenName
                                   familyName:(nullable NSString *)familyName
                                      success:(void (^)(void))successBlock
                                      failure:(ProfileManagerFailureBlock)failureBlock
    NS_SWIFT_NAME(updateService(unversionedGivenName:familyName:success:failure:));

#pragma mark - Profile Whitelist

// These methods are for debugging.
- (void)clearProfileWhitelist;
- (void)removeThreadFromProfileWhitelist:(TSThread *)thread;
- (void)logProfileWhitelist;
- (void)debug_regenerateLocalProfileWithSneakyTransaction;
- (void)setLocalProfileKey:(OWSAES256Key *)key
       wasLocallyInitiated:(BOOL)wasLocallyInitiated
               transaction:(SDSAnyWriteTransaction *)transaction;

- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses;

- (void)setContactAddresses:(NSArray<SignalServiceAddress *> *)contactAddresses;

#pragma mark - Other User's Profiles

// This method is for debugging.
- (void)logUserProfiles;

- (nullable OWSAES256Key *)profileKeyForAddress:(SignalServiceAddress *)address
                                    transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)givenNameForAddress:(SignalServiceAddress *)address
                               transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)familyNameForAddress:(SignalServiceAddress *)address
                                transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSPersonNameComponents *)nameComponentsForAddress:(SignalServiceAddress *)address
                                                  transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)fullNameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction;

- (nullable UIImage *)profileAvatarForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction;
- (nullable NSData *)profileAvatarDataForAddress:(SignalServiceAddress *)address
                                     transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)usernameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction;

- (void)updateProfileForAddress:(SignalServiceAddress *)address
           profileNameEncrypted:(nullable NSData *)profileNameEncrypted
                       username:(nullable NSString *)username
                  avatarUrlPath:(nullable NSString *)avatarUrlPath;

#pragma mark - Clean Up

+ (NSSet<NSString *> *)allProfileAvatarFilePathsWithTransaction:(SDSAnyReadTransaction *)transaction;

#pragma mark - User Interface

- (void)presentAddThreadToProfileWhitelist:(TSThread *)thread
                        fromViewController:(UIViewController *)fromViewController
                                   success:(void (^)(void))successHandler;

@end

NS_ASSUME_NONNULL_END
