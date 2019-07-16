//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/ProfileManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kNSNotificationName_ProfileWhitelistDidChange;
extern NSString *const kNSNotificationName_ProfileKeyDidChange;

extern const NSUInteger kOWSProfileManager_NameDataLength;
extern const NSUInteger kOWSProfileManager_MaxAvatarDiameter;

@class OWSAES256Key;
@class OWSMessageSender;
@class SDSDatabaseStorage;
@class SDSKeyValueStore;
@class SignalServiceAddress;
@class TSNetworkManager;
@class TSThread;

// This class can be safely accessed and used from any thread.
@interface OWSProfileManager : NSObject <ProfileManagerProtocol>

@property (nonatomic, readonly) SDSKeyValueStore *whitelistedPhoneNumbersStore;
@property (nonatomic, readonly) SDSKeyValueStore *whitelistedUUIDsStore;
@property (nonatomic, readonly) SDSKeyValueStore *whitelistedGroupsStore;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDatabaseStorage:(SDSDatabaseStorage *)databaseStorage NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

#pragma mark - Local Profile

// These two methods should only be called from the main thread.
- (OWSAES256Key *)localProfileKey;
// localUserProfileExists is true if there is _ANY_ local profile.
- (BOOL)localProfileExists;
// hasLocalProfile is true if there is a local profile with a name or avatar.
- (BOOL)hasLocalProfile;
- (nullable NSString *)localProfileName;
- (nullable UIImage *)localProfileAvatarImage;
- (nullable NSData *)localProfileAvatarData;
- (void)ensureLocalProfileCached;

// This method is used to update the "local profile" state on the client
// and the service.  Client state is only updated if service state is
// successfully updated.
//
// This method should only be called from the main thread.
- (void)updateLocalProfileName:(nullable NSString *)profileName
                   avatarImage:(nullable UIImage *)avatarImage
                       success:(void (^)(void))successBlock
                       failure:(void (^)(void))failureBlock;

- (BOOL)isProfileNameTooLong:(nullable NSString *)profileName;

- (void)fetchLocalUsersProfile;

#pragma mark - Profile Whitelist

// These methods are for debugging.
- (void)clearProfileWhitelist;
- (void)logProfileWhitelist;
- (void)regenerateLocalProfile;

- (void)addThreadToProfileWhitelist:(TSThread *)thread;

- (void)setContactAddresses:(NSArray<SignalServiceAddress *> *)contactAddresses;

#pragma mark - Other User's Profiles

// This method is for debugging.
- (void)logUserProfiles;

- (nullable OWSAES256Key *)profileKeyForAddress:(SignalServiceAddress *)address;

- (nullable NSString *)profileNameForAddress:(SignalServiceAddress *)address;

- (nullable UIImage *)profileAvatarForAddress:(SignalServiceAddress *)address;
- (nullable NSData *)profileAvatarDataForAddress:(SignalServiceAddress *)address;

- (void)updateProfileForAddress:(SignalServiceAddress *)address
           profileNameEncrypted:(nullable NSData *)profileNameEncrypted
                  avatarUrlPath:(nullable NSString *)avatarUrlPath;

#pragma mark - User Interface

- (void)presentAddThreadToProfileWhitelist:(TSThread *)thread
                        fromViewController:(UIViewController *)fromViewController
                                   success:(void (^)(void))successHandler;

#pragma mark - Clean Up

- (NSSet<NSString *> *)allProfileAvatarFilePaths;

@end

NS_ASSUME_NONNULL_END
