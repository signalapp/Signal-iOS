//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSProfileManager.h"
#import "Environment.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/NSData+Image.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/OWSProfileKeyMessage.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/OWSUpload.h>
#import <SignalServiceKit/OWSUserProfile.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/UIImage+OWS.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kOWSProfileManager_MaxAvatarDiameterPixels = 1024;
const NSString *kNSNotificationKey_UserProfileWriter = @"kNSNotificationKey_UserProfileWriter";

@interface OWSProfileManager ()

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) OWSUserProfile *localUserProfile;

@property (nonatomic, readonly) AtomicUInt *profileAvatarDataLoadCounter;
@property (nonatomic, readonly) AtomicUInt *profileAvatarImageLoadCounter;

@end

#pragma mark -

@implementation OWSProfileSnapshot

- (instancetype)initWithGivenName:(nullable NSString *)givenName
                       familyName:(nullable NSString *)familyName
                         fullName:(nullable NSString *)fullName
                              bio:(nullable NSString *)bio
                         bioEmoji:(nullable NSString *)bioEmoji
                         username:(nullable NSString *)username
                       avatarData:(nullable NSData *)avatarData
{

    self = [super init];
    if (!self) {
        return self;
    }

    _givenName = givenName;
    _familyName = familyName;
    _fullName = fullName;
    _bio = bio;
    _bioEmoji = bioEmoji;
    _username = username;
    _avatarData = avatarData;

    return self;
}

@end

#pragma mark -

// Access to most state should happen while synchronized on the profile manager.
// Writes should happen off the main thread, wherever possible.
@implementation OWSProfileManager

@synthesize localUserProfile = _localUserProfile;

- (instancetype)initWithDatabaseStorage:(SDSDatabaseStorage *)databaseStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertIsOnMainThread();
    OWSAssertDebug(databaseStorage);

    _profileAvatarDataLoadCounter = [[AtomicUInt alloc] init:0];
    _profileAvatarImageLoadCounter = [[AtomicUInt alloc] init:0];

    _whitelistedPhoneNumbersStore =
        [[SDSKeyValueStore alloc] initWithCollection:@"kOWSProfileManager_UserWhitelistCollection"];
    _whitelistedUUIDsStore =
        [[SDSKeyValueStore alloc] initWithCollection:@"kOWSProfileManager_UserUUIDWhitelistCollection"];
    _whitelistedGroupsStore =
        [[SDSKeyValueStore alloc] initWithCollection:@"kOWSProfileManager_GroupWhitelistCollection"];

    OWSSingletonAssert();

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        if (CurrentAppContext().isMainApp && !CurrentAppContext().isRunningTests
            && TSAccountManager.shared.isRegistered) {
            [self fetchLocalUsersProfile];
        }
    });

    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{
        if (TSAccountManager.shared.isRegistered) {
            [self rotateLocalProfileKeyIfNecessary];
            [OWSProfileManager updateProfileOnServiceIfNecessary];
        }
    });

    [self observeNotifications];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged:)
                                                 name:SSKReachability.owsReachabilityDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockListDidChange:)
                                                 name:kNSNotificationNameBlockListDidChange
                                               object:nil];
}

#pragma mark - User Profile Accessor

- (void)warmCaches
{
    // Clear out so we re-initialize if we ever re-run the "on launch" logic,
    // such as after a completed database transfer.
    @synchronized(self) {
        _localUserProfile = nil;
    }

    [self ensureLocalProfileCached];
}

- (void)ensureLocalProfileCached
{
    // Since localUserProfile can create a transaction, we want to make sure it's not called for the first
    // time unexpectedly (e.g. in a nested transaction.)
    __unused OWSUserProfile *profile = [self localUserProfile];
}

#pragma mark - Local Profile

- (OWSUserProfile *)localUserProfile
{
    @synchronized(self)
    {
        if (_localUserProfile) {
            OWSAssertDebug(_localUserProfile.profileKey);

            return [_localUserProfile shallowCopy];
        }
    }

    // We create the profile outside the @synchronized block
    // to avoid any risk of deadlock.  Thanks to ensureLocalProfileCached,
    // there should be no risk of races.  And races should be harmless
    // since: a) getOrBuildUserProfileForAddress is idempotent and b) we use
    // the "update with..." pattern.
    //
    // We first try using a read block to avoid opening a write block.
    __block OWSUserProfile *_Nullable localUserProfile;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        localUserProfile = [OWSUserProfile getUserProfileForAddress:OWSUserProfile.localProfileAddress
                                                        transaction:transaction];
    }];

    if (localUserProfile != nil) {
        @synchronized(self) {
            _localUserProfile = localUserProfile;
        }
        return [localUserProfile shallowCopy];
    }

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        localUserProfile = [OWSUserProfile getOrBuildUserProfileForAddress:OWSUserProfile.localProfileAddress
                                                               transaction:transaction];
    });

    @synchronized(self) {
        _localUserProfile = localUserProfile;
    }

    OWSAssertDebug(_localUserProfile.profileKey);

    return [localUserProfile shallowCopy];
}

- (nullable OWSUserProfile *)getLocalUserProfileWithTransaction:(SDSAnyReadTransaction *)transaction
{
    @synchronized(self) {
        if (_localUserProfile) {
            OWSAssertDebug(_localUserProfile.profileKey);

            return [_localUserProfile shallowCopy];
        }
    }

    OWSUserProfile *_Nullable localUserProfile =
        [OWSUserProfile getUserProfileForAddress:OWSUserProfile.localProfileAddress transaction:transaction];

    if (localUserProfile != nil) {
        @synchronized(self) {
            _localUserProfile = localUserProfile;
        }
        return [localUserProfile shallowCopy];
    }

    OWSFailDebug(@"We're trying to fetch the local user profile before it exists. This shouldn't happen.");
    return nil;
}

- (void)localProfileWasUpdated:(OWSUserProfile *)localUserProfile
{
    @synchronized(self) {
        _localUserProfile = [localUserProfile shallowCopy];
    }
}

- (BOOL)localProfileExistsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [OWSUserProfile localUserProfileExistsWithTransaction:transaction];
}

- (OWSAES256Key *)localProfileKey
{
    OWSAssertDebug(self.localUserProfile.profileKey.keyData.length == kAES256_KeyByteLength);

    return self.localUserProfile.profileKey;
}

- (BOOL)hasLocalProfile
{
    return (self.localGivenName.length > 0 || self.localProfileAvatarImage != nil);
}

- (BOOL)hasProfileName
{
    return self.localGivenName.length > 0;
}

- (nullable NSString *)localGivenName
{
    return self.localUserProfile.givenName;
}

- (nullable NSString *)localFamilyName
{
    return self.localUserProfile.familyName;
}

- (nullable NSString *)localFullName
{
    return self.localUserProfile.fullName;
}

- (nullable UIImage *)localProfileAvatarImage
{
    return [self loadProfileAvatarWithFilename:self.localUserProfile.avatarFileName];
}

- (nullable NSData *)localProfileAvatarData
{
    NSString *_Nullable filename = self.localUserProfile.avatarFileName;
    if (filename.length < 1) {
        return nil;
    }
    return [self loadProfileAvatarDataWithFilename:filename];
}

- (nullable NSString *)localUsername
{
    return self.localUserProfile.username;
}

- (OWSProfileSnapshot *)localProfileSnapshotWithShouldIncludeAvatar:(BOOL)shouldIncludeAvatar
{
    return [self profileSnapshotForUserProfile:self.localUserProfile shouldIncludeAvatar:shouldIncludeAvatar];
}

- (OWSProfileSnapshot *)profileSnapshotForUserProfile:(OWSUserProfile *)userProfile
                                  shouldIncludeAvatar:(BOOL)shouldIncludeAvatar
{
    NSData *_Nullable avatarData = nil;
    if (shouldIncludeAvatar && userProfile.avatarFileName.length > 0) {
        avatarData = [self loadProfileAvatarDataWithFilename:userProfile.avatarFileName];
    }
    return [[OWSProfileSnapshot alloc] initWithGivenName:userProfile.givenName
                                              familyName:userProfile.familyName
                                                fullName:userProfile.fullName
                                                     bio:userProfile.bio
                                                bioEmoji:userProfile.bioEmoji
                                                username:userProfile.username
                                              avatarData:avatarData];
}

- (void)updateLocalUsername:(nullable NSString *)username
          userProfileWriter:(UserProfileWriter)userProfileWriter
                transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(username == nil || username.length > 0);

    OWSUserProfile *userProfile = self.localUserProfile;
    OWSAssertDebug(self.localUserProfile);

    [userProfile updateWithUsername:username
                      isUuidCapable:YES
                  userProfileWriter:userProfileWriter
                        transaction:transaction];
}

- (void)writeAvatarToDiskWithData:(NSData *)avatarData
                          success:(void (^)(NSString *fileName))successBlock
                          failure:(ProfileManagerFailureBlock)failureBlock
{
    OWSAssertDebug(avatarData);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *filename = [self generateAvatarFilename];
        NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:filename];
        BOOL success = [avatarData writeToFile:filePath atomically:YES];
        OWSAssertDebug(success);
        if (success) {
            return successBlock(filename);
        }
        failureBlock(OWSErrorWithCodeDescription(OWSErrorCodeAvatarWriteFailed, @"Avatar write failed."));
    });
}

+ (NSData *)avatarDataForAvatarImage:(UIImage *)image
{
    NSUInteger kMaxAvatarBytes = 5 * 1000 * 1000;

    if (image.pixelWidth != kOWSProfileManager_MaxAvatarDiameterPixels
        || image.pixelHeight != kOWSProfileManager_MaxAvatarDiameterPixels) {
        // To help ensure the user is being shown the same cropping of their avatar as
        // everyone else will see, we want to be sure that the image was resized before this point.
        OWSFailDebug(@"Avatar image should have been resized before trying to upload");
        image = [image resizedImageToFillPixelSize:CGSizeMake(kOWSProfileManager_MaxAvatarDiameterPixels,
                                                       kOWSProfileManager_MaxAvatarDiameterPixels)];
    }

    NSData *_Nullable data = UIImageJPEGRepresentation(image, 0.95f);
    if (data.length > kMaxAvatarBytes) {
        // Our avatar dimensions are so small that it's incredibly unlikely we wouldn't be able to fit our profile
        // photo. e.g. generating pure noise at our resolution compresses to ~200k.
        OWSFailDebug(@"Surprised to find profile avatar was too large. Was it scaled properly? image: %@", image);
    }

    return data;
}

- (void)fetchLocalUsersProfile
{
    SignalServiceAddress *_Nullable localAddress = self.tsAccountManager.localAddress;
    if (!localAddress.isValid) {
        return;
    }
    [self fetchProfileForAddress:localAddress];
}

- (void)fetchProfileForAddress:(SignalServiceAddress *)address
{
    [ProfileFetcherJob fetchProfileWithAddress:address ignoreThrottling:YES];
}

- (AnyPromise *)fetchLocalUsersProfilePromise
{
    SignalServiceAddress *_Nullable localAddress = self.tsAccountManager.localAddress;
    if (!localAddress.isValid) {
        return [AnyPromise promiseWithValue:OWSErrorMakeAssertionError(@"Missing local address.")];
    }
    return [ProfileFetcherJob fetchProfilePromiseObjcWithAddress:localAddress mainAppOnly:NO ignoreThrottling:YES];
}

- (AnyPromise *)fetchProfileForAddressPromise:(SignalServiceAddress *)address
{
    return [ProfileFetcherJob fetchProfilePromiseObjcWithAddress:address mainAppOnly:NO ignoreThrottling:YES];
}

- (AnyPromise *)fetchProfileForAddressPromise:(SignalServiceAddress *)address
                                  mainAppOnly:(BOOL)mainAppOnly
                             ignoreThrottling:(BOOL)ignoreThrottling
{
    return [ProfileFetcherJob fetchProfilePromiseObjcWithAddress:address
                                                     mainAppOnly:mainAppOnly
                                                ignoreThrottling:ignoreThrottling];
}

- (void)fetchProfileForUsername:(NSString *)username
                        success:(void (^)(SignalServiceAddress *))success
                       notFound:(void (^)(void))notFound
                        failure:(void (^)(NSError *))failure
{
    OWSAssertDebug(username.length > 0);

    // Check if we have a cached profile for this username, if so avoid fetching it from the service
    // since we are limited to 100 username lookups per day.

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block OWSUserProfile *_Nullable userProfile;
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            userProfile = [OWSUserProfile userProfileForUsername:username transaction:transaction];
        });
        
        if (userProfile) {
            success(userProfile.publicAddress);
            return;
        }
        
        [ProfileFetcherJob fetchProfileWithUsername:username success:success notFound:notFound failure:failure];
    });
}

- (void)reuploadLocalProfile
{
    [self reuploadLocalProfilePromise].then(^{ OWSLogInfo(@"Done."); }).catch(^(NSError *error) {
        OWSFailDebugUnlessNetworkFailure(error);
    });
}

#pragma mark - Profile Key Rotation

- (NSString *)groupKeyForGroupId:(NSData *)groupId
{
    return [groupId hexadecimalString];
}

- (nullable NSData *)groupIdForGroupKey:(NSString *)groupKey {
    NSData *_Nullable groupId = [NSData dataFromHexString:groupKey];
    // Make sure that the group id is a valid v1 or v2 group id.
    if (![GroupManager isValidGroupIdOfAnyKind:groupId]) {
        OWSFailDebug(@"Parsed group id has unexpected length: %@ (%lu)",
            groupId.hexadecimalString,
            (unsigned long)groupId.length);
        return nil;
    }
    return [groupId copy];
}

- (void)rotateLocalProfileKeyIfNecessary {
    if (!self.tsAccountManager.isRegisteredPrimaryDevice) {
        OWSAssertDebug(self.tsAccountManager.isRegistered);
        OWSLogVerbose(@"Not rotating profile key on non-primary device");
        return;
    }

    [self rotateLocalProfileKeyIfNecessaryWithSuccess:^{} failure:^(NSError *error) {}];
}

- (void)rotateLocalProfileKeyIfNecessaryWithSuccess:(dispatch_block_t)success
                                            failure:(ProfileManagerFailureBlock)failure {
    OWSAssertDebug(AppReadiness.isAppReady);

    if (!self.tsAccountManager.isRegistered) {
        OWSFailDebug(@"tsAccountManager.isRegistered was unexpectely false");
        success();
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableSet<NSString *> *whitelistedPhoneNumbers = [NSMutableSet new];
        NSMutableSet<NSString *> *whitelistedUUIDS = [NSMutableSet new];
        NSMutableSet<NSData *> *whitelistedGroupIds = [NSMutableSet new];
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            [whitelistedPhoneNumbers
                addObjectsFromArray:[self.whitelistedPhoneNumbersStore allKeysWithTransaction:transaction]];
            [whitelistedUUIDS addObjectsFromArray:[self.whitelistedUUIDsStore allKeysWithTransaction:transaction]];
            NSArray<NSString *> *whitelistedGroupKeys =
                [self.whitelistedGroupsStore allKeysWithTransaction:transaction];

            for (NSString *groupKey in whitelistedGroupKeys) {
                NSData *_Nullable groupId = [self groupIdForGroupKey:groupKey];
                if (!groupId) {
                    OWSFailDebug(@"Couldn't parse group key: %@.", groupKey);
                    continue;
                }

                [whitelistedGroupIds addObject:groupId];

                // Note: We don't add the group member's ids to whitelistedUUIDS
                // and whitelistedPhoneNumbers.
                //
                // Whenever we message a contact, be it in a 1:1 thread or in a group thread,
                // we add them to the contact whitelist, so there's no reason to redundantly
                // add them here.
                //
                // Furthermore, doing so would cause the following problem:
                //
                // - Alice is in group Book Club
                // - Add Book Club to your profile white list
                // - Message Book Club, which also adds Alice to your profile whitelist.
                // - Block Alice, but not Book Club
                //
                // Now, at this point we'd want to rotate our profile key once, since Alice has
                // it via BookClub.
                //
                // The next time we checked whether we should rotate our profile key, adding all
                // group members to whitelistedUUIDS and whitelistedPhoneNumbers would
                // include Alice, and we'd rotate our profile key every time this method is called.
            }
        }];

        SignalServiceAddress *_Nullable localAddress = [self.tsAccountManager localAddress];
        NSString *_Nullable localNumber = localAddress.phoneNumber;
        if (localNumber) {
            [whitelistedPhoneNumbers removeObject:localNumber];
        } else {
            OWSFailDebug(@"Missing localNumber");
        }

        NSString *_Nullable localUUID = localAddress.uuidString;
        if (localUUID) {
            [whitelistedUUIDS removeObject:localUUID];
        } else {
            OWSFailDebug(@"Missing localUUID");
        }

        NSSet<NSString *> *blockedPhoneNumbers = [NSSet setWithArray:self.blockingManager.blockedPhoneNumbers];
        NSSet<NSString *> *blockedUUIDs = [NSSet setWithArray:self.blockingManager.blockedUUIDs];
        NSSet<NSData *> *blockedGroupIds = [NSSet setWithArray:self.blockingManager.blockedGroupIds];

        // Find the users and groups which are both a) blocked b) may have our current profile key.
        NSMutableSet<NSString *> *intersectingPhoneNumbers = [blockedPhoneNumbers mutableCopy];
        [intersectingPhoneNumbers intersectSet:whitelistedPhoneNumbers];
        NSMutableSet<NSString *> *intersectingUUIDS = [blockedUUIDs mutableCopy];
        [intersectingUUIDS intersectSet:whitelistedUUIDS];
        NSMutableSet<NSData *> *intersectingGroupIds = [blockedGroupIds mutableCopy];
        [intersectingGroupIds intersectSet:whitelistedGroupIds];

        BOOL isProfileKeySharedWithBlocked
            = (intersectingPhoneNumbers.count > 0 || intersectingUUIDS.count > 0 || intersectingGroupIds.count > 0);
        if (!isProfileKeySharedWithBlocked) {
            // No need to rotate the profile key.
            return success();
        }

        [self rotateProfileKeyWithIntersectingPhoneNumbers:intersectingPhoneNumbers
                                         intersectingUUIDs:intersectingUUIDS
                                      intersectingGroupIds:intersectingGroupIds]
            .then(^{ success(); })
            .catch(^(NSError *error) { failure(error); });
    });
}

#pragma mark - Profile Whitelist

- (void)clearProfileWhitelist
{
    OWSLogWarn(@"Clearing the profile whitelist.");

    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.whitelistedPhoneNumbersStore removeAllWithTransaction:transaction];
        [self.whitelistedUUIDsStore removeAllWithTransaction:transaction];
        [self.whitelistedGroupsStore removeAllWithTransaction:transaction];
        
        OWSAssertDebug(0 == [self.whitelistedPhoneNumbersStore numberOfKeysWithTransaction:transaction]);
        OWSAssertDebug(0 == [self.whitelistedUUIDsStore numberOfKeysWithTransaction:transaction]);
        OWSAssertDebug(0 == [self.whitelistedGroupsStore numberOfKeysWithTransaction:transaction]);
    });
}

// TODO: We could add a userProfileWriter parameter.
- (void)removeThreadFromProfileWhitelist:(TSThread *)thread
{
    OWSLogWarn(@"Removing thread from profile whitelist: %@", thread);
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        if ([thread isKindOfClass:TSContactThread.class]) {
            TSContactThread *contactThread = (TSContactThread *)thread;
            [self removeUserFromProfileWhitelist:contactThread.contactAddress
                               userProfileWriter:UserProfileWriter_LocalUser
                                     transaction:transaction];
        } else {
            TSGroupThread *groupThread = (TSGroupThread *)thread;
            [self removeGroupIdFromProfileWhitelist:groupThread.groupModel.groupId
                                  userProfileWriter:UserProfileWriter_LocalUser
                                        transaction:transaction];
        }
    });
}

- (void)logProfileWhitelist
{
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        OWSLogError(@"%@: %lu",
            self.whitelistedPhoneNumbersStore.collection,
            (unsigned long)[self.whitelistedPhoneNumbersStore numberOfKeysWithTransaction:transaction]);
        for (NSString *key in [self.whitelistedPhoneNumbersStore allKeysWithTransaction:transaction]) {
            OWSLogError(@"\t profile whitelist user phone number: %@", key);
        }
        OWSLogError(@"%@: %lu",
            self.whitelistedUUIDsStore.collection,
            (unsigned long)[self.whitelistedUUIDsStore numberOfKeysWithTransaction:transaction]);
        for (NSString *key in [self.whitelistedUUIDsStore allKeysWithTransaction:transaction]) {
            OWSLogError(@"\t profile whitelist user uuid: %@", key);
        }
        OWSLogError(@"%@: %lu",
            self.whitelistedGroupsStore.collection,
            (unsigned long)[self.whitelistedGroupsStore numberOfKeysWithTransaction:transaction]);
        for (NSString *key in [self.whitelistedGroupsStore allKeysWithTransaction:transaction]) {
            OWSLogError(@"\t profile whitelist group: %@", key);
        }
    }];
}

- (void)debug_regenerateLocalProfileWithSneakyTransaction
{
    OWSUserProfile *userProfile = self.localUserProfile;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [userProfile clearWithProfileKey:[OWSAES256Key generateRandomKey]
                       userProfileWriter:UserProfileWriter_Debugging
                             transaction:transaction
                              completion:nil];
    });
    [self.tsAccountManager updateAccountAttributes].catch(^(NSError *error) {
        OWSLogError(@"Error: %@.", error);
    });
}

- (void)setLocalProfileKey:(OWSAES256Key *)key
         userProfileWriter:(UserProfileWriter)userProfileWriter
               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSUserProfile *localUserProfile;
    
    @synchronized(self)
    {
        // If it didn't exist, create it in a safe way as accessing the property
        // will do a sneaky transaction.
        if (!_localUserProfile) {
            // We assert on the ivar directly here, as we want this to be cached already
            // by the time this method is called. If it's not, we've changed our caching
            // logic and should re-evalulate this method.
            OWSFailDebug(@"Missing local profile when setting key.");

            localUserProfile = [OWSUserProfile getOrBuildUserProfileForAddress:OWSUserProfile.localProfileAddress
                                                                   transaction:transaction];

            _localUserProfile = localUserProfile;
        } else {
            localUserProfile = _localUserProfile;
        }
    }

    [localUserProfile updateWithProfileKey:key
                         userProfileWriter:userProfileWriter
                               transaction:transaction
                                completion:nil];
}

- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    [self addUsersToProfileWhitelist:@[ address ]];
}

// TODO: We could add a userProfileWriter parameter.
- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses
{
    OWSAssertDebug(addresses);

    // Try to avoid opening a write transaction.
    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{
        [self.databaseStorage asyncReadWithBlock:^(SDSAnyReadTransaction *readTransaction) {
            NSSet<SignalServiceAddress *> *addressesToAdd = [self addressesNotBlockedOrInWhitelist:addresses
                                                                                       transaction:readTransaction];

            if (addressesToAdd.count < 1) {
                return;
            }

            DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *writeTransaction) {
                [self addConfirmedUnwhitelistedAddresses:addressesToAdd
                                       userProfileWriter:UserProfileWriter_LocalUser
                                             transaction:writeTransaction];
            });
        }];
    });
}

- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address
                userProfileWriter:(UserProfileWriter)userProfileWriter
                      transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    NSSet *addressesToAdd = [self addressesNotBlockedOrInWhitelist:@[ address ] transaction:transaction];
    [self addConfirmedUnwhitelistedAddresses:addressesToAdd
                           userProfileWriter:userProfileWriter
                                 transaction:transaction];
}

- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses
                 userProfileWriter:(UserProfileWriter)userProfileWriter
                       transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(addresses);
    OWSAssertDebug(transaction);

    NSSet<SignalServiceAddress *> *addressesToAdd = [self addressesNotBlockedOrInWhitelist:addresses
                                                                               transaction:transaction];

    if (addressesToAdd.count < 1) {
        return;
    }

    [self addConfirmedUnwhitelistedAddresses:addressesToAdd
                           userProfileWriter:userProfileWriter
                                 transaction:transaction];
}

- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    [self removeUsersFromProfileWhitelist:@[ address ]];
}

- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address
                     userProfileWriter:(UserProfileWriter)userProfileWriter
                           transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    NSSet *addressesToRemove = [self addressesInWhitelist:@[ address ] transaction:transaction];
    [self removeConfirmedWhitelistedAddresses:addressesToRemove
                            userProfileWriter:userProfileWriter
                                  transaction:transaction];
}

// TODO: We could add a userProfileWriter parameter.
- (void)removeUsersFromProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses
{
    OWSAssertDebug(addresses);

    // Try to avoid opening a write transaction.
    [self.databaseStorage asyncReadWithBlock:^(SDSAnyReadTransaction *readTransaction) {
        NSSet<SignalServiceAddress *> *addressesToRemove = [self addressesInWhitelist:addresses
                                                                          transaction:readTransaction];

        if (addressesToRemove.count < 1) {
            return;
        }

        DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *writeTransaction) {
            [self removeConfirmedWhitelistedAddresses:addressesToRemove
                                    userProfileWriter:UserProfileWriter_LocalUser
                                          transaction:writeTransaction];
        });
    }];
}

- (NSSet<SignalServiceAddress *> *)addressesNotBlockedOrInWhitelist:(NSArray<SignalServiceAddress *> *)addresses
                                                        transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(addresses);

    NSMutableSet<SignalServiceAddress *> *notBlockedOrInWhitelist = [NSMutableSet new];

    for (SignalServiceAddress *address in addresses) {

        // If the address is blocked, we don't want to include it
        if ([self.blockingManager isAddressBlocked:address]) {
            continue;
        }

        // We want to include both the UUID and the phone number in the white list.
        // It's possible we white listed one but not both, so we check each.

        BOOL notInWhitelist = NO;
        if (address.uuidString) {
            BOOL currentlyWhitelisted = [self.whitelistedUUIDsStore hasValueForKey:address.uuidString
                                                                       transaction:transaction];
            if (!currentlyWhitelisted) {
                notInWhitelist = YES;
            }
        }

        if (address.phoneNumber) {
            BOOL currentlyWhitelisted = [self.whitelistedPhoneNumbersStore hasValueForKey:address.phoneNumber
                                                                              transaction:transaction];
            if (!currentlyWhitelisted) {
                notInWhitelist = YES;
            }
        }

        if (notInWhitelist) {
            [notBlockedOrInWhitelist addObject:address];
        }
    }

    return [notBlockedOrInWhitelist copy];
}

- (NSSet<SignalServiceAddress *> *)addressesInWhitelist:(NSArray<SignalServiceAddress *> *)addresses
                                            transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(addresses);

    NSMutableSet<SignalServiceAddress *> *whitelistedAddresses = [NSMutableSet new];

    for (SignalServiceAddress *address in addresses) {

        // We only consider an address whitelisted if either the UUID and phone
        // number are represented. It's possible we white listed one but not both,
        // so we check each.

        BOOL isInWhitelist = NO;
        if (address.uuidString) {
            BOOL currentlyWhitelisted = [self.whitelistedUUIDsStore hasValueForKey:address.uuidString
                                                                       transaction:transaction];
            if (currentlyWhitelisted) {
                isInWhitelist = YES;
            }
        }

        if (address.phoneNumber) {
            BOOL currentlyWhitelisted = [self.whitelistedPhoneNumbersStore hasValueForKey:address.phoneNumber
                                                                              transaction:transaction];
            if (currentlyWhitelisted) {
                isInWhitelist = YES;
            }
        }

        if (isInWhitelist) {
            [whitelistedAddresses addObject:address];
        }
    }

    return [whitelistedAddresses copy];
}

- (void)removeConfirmedWhitelistedAddresses:(NSSet<SignalServiceAddress *> *)addressesToRemove
                          userProfileWriter:(UserProfileWriter)userProfileWriter
                                transaction:(SDSAnyWriteTransaction *)transaction
{
    if (addressesToRemove.count == 0) {
        // Do nothing.
        return;
    }

    for (SignalServiceAddress *address in addressesToRemove) {
        if (address.uuidString) {
            [self.whitelistedUUIDsStore removeValueForKey:address.uuidString transaction:transaction];
        }

        if (address.phoneNumber) {
            [self.whitelistedPhoneNumbersStore removeValueForKey:address.phoneNumber transaction:transaction];
        }

        TSThread *_Nullable thread = [TSContactThread getThreadWithContactAddress:address transaction:transaction];
        if (thread) {
            [self.databaseStorage touchThread:thread shouldReindex:NO transaction:transaction];
        }
    }

    [transaction addSyncCompletion:^{
        // Mark the removed whitelisted addresses for update
        if (shouldUpdateStorageServiceForUserProfileWriter(userProfileWriter)) {
            [self.storageServiceManager recordPendingUpdatesWithUpdatedAddresses:addressesToRemove.allObjects];
        }

        for (SignalServiceAddress *address in addressesToRemove) {
            [[NSNotificationCenter defaultCenter]
                postNotificationNameAsync:kNSNotificationNameProfileWhitelistDidChange
                                   object:nil
                                 userInfo:@{
                                     kNSNotificationKey_ProfileAddress : address,
                                     kNSNotificationKey_UserProfileWriter : @(userProfileWriter),
                                 }];
        }
    }];
}

- (void)addConfirmedUnwhitelistedAddresses:(NSSet<SignalServiceAddress *> *)addressesToAdd
                         userProfileWriter:(UserProfileWriter)userProfileWriter
                               transaction:(SDSAnyWriteTransaction *)transaction
{
    if (addressesToAdd.count == 0) {
        // Do nothing.
        return;
    }

    for (SignalServiceAddress *address in addressesToAdd) {
        if (address.uuidString) {
            [self.whitelistedUUIDsStore setBool:YES key:address.uuidString transaction:transaction];
        }

        if (address.phoneNumber) {
            [self.whitelistedPhoneNumbersStore setBool:YES key:address.phoneNumber transaction:transaction];
        }

        TSThread *_Nullable thread = [TSContactThread getThreadWithContactAddress:address transaction:transaction];
        if (thread) {
            [self.databaseStorage touchThread:thread shouldReindex:NO transaction:transaction];
        }
    }

    [transaction addSyncCompletion:^{
        // Mark the new whitelisted addresses for update
        if (shouldUpdateStorageServiceForUserProfileWriter(userProfileWriter)) {
            [self.storageServiceManager recordPendingUpdatesWithUpdatedAddresses:addressesToAdd.allObjects];
        }

        for (SignalServiceAddress *address in addressesToAdd) {
            [[NSNotificationCenter defaultCenter]
                postNotificationNameAsync:kNSNotificationNameProfileWhitelistDidChange
                                   object:nil
                                 userInfo:@{
                                     kNSNotificationKey_ProfileAddress : address,
                                     kNSNotificationKey_UserProfileWriter : @(userProfileWriter),
                                 }];
        }
    }];
}

- (BOOL)isUserInProfileWhitelist:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    // isAddressBlocked can open a sneaky transaction in
    // BlockingManager.ensureLazyInitialization(), but we avoid this
    // by ensuring that BlockingManager.warmCaches() is always
    // called first, immediately after registering the database views.
    if ([self.blockingManager isAddressBlocked:address]) {
        return NO;
    }

    BOOL result = NO;
    if (address.uuidString) {
        result = [self.whitelistedUUIDsStore hasValueForKey:address.uuidString transaction:transaction];
    }

    if (!result && address.phoneNumber) {
        result = [self.whitelistedPhoneNumbersStore hasValueForKey:address.phoneNumber transaction:transaction];
    }
    return result;
}

// TODO: We could add a userProfileWriter parameter.
- (void)addGroupIdToProfileWhitelist:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    NSString *groupIdKey = [self groupKeyForGroupId:groupId];

    // Try to avoid opening a write transaction.
    [self.databaseStorage asyncReadWithBlock:^(SDSAnyReadTransaction *readTransaction) {
        if ([self.whitelistedGroupsStore hasValueForKey:groupIdKey transaction:readTransaction]) {
            // Do nothing.
            return;
        }
        DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *writeTransaction) {
            [self addConfirmedUnwhitelistedGroupId:groupId
                                 userProfileWriter:UserProfileWriter_LocalUser
                                       transaction:writeTransaction];
        });
    }];
}

- (void)addGroupIdToProfileWhitelist:(NSData *)groupId
                   userProfileWriter:(UserProfileWriter)userProfileWriter
                         transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    NSString *groupIdKey = [self groupKeyForGroupId:groupId];

    if (![self.whitelistedGroupsStore hasValueForKey:groupIdKey transaction:transaction]) {
        [self addConfirmedUnwhitelistedGroupId:groupId userProfileWriter:userProfileWriter transaction:transaction];
    }
}

// TODO: We could add a userProfileWriter parameter.
- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    NSString *groupIdKey = [self groupKeyForGroupId:groupId];

    // Try to avoid opening a write transaction.
    [self.databaseStorage asyncReadWithBlock:^(SDSAnyReadTransaction *readTransaction) {
        if (![self.whitelistedGroupsStore hasValueForKey:groupIdKey transaction:readTransaction]) {
            // Do nothing.
            return;
        }
        DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *writeTransaction) {
            [self removeConfirmedWhitelistedGroupId:groupId
                                  userProfileWriter:UserProfileWriter_LocalUser
                                        transaction:writeTransaction];
        });
    }];
}

- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId
                        userProfileWriter:(UserProfileWriter)userProfileWriter
                              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    NSString *groupIdKey = [self groupKeyForGroupId:groupId];

    if ([self.whitelistedGroupsStore hasValueForKey:groupIdKey transaction:transaction]) {
        [self removeConfirmedWhitelistedGroupId:groupId userProfileWriter:userProfileWriter transaction:transaction];
    }
}

- (void)removeConfirmedWhitelistedGroupId:(NSData *)groupId
                        userProfileWriter:(UserProfileWriter)userProfileWriter
                              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    NSString *groupIdKey = [self groupKeyForGroupId:groupId];

    [self.whitelistedGroupsStore removeValueForKey:groupIdKey transaction:transaction];

    [TSGroupThread ensureGroupIdMappingForGroupId:groupId transaction:transaction];
    TSThread *_Nullable groupThread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
    if (groupThread) {
        [self.databaseStorage touchThread:groupThread shouldReindex:NO transaction:transaction];
    }

    [transaction addSyncCompletion:^{
        // Mark the group for update
        if (shouldUpdateStorageServiceForUserProfileWriter(userProfileWriter)) {
            [self recordPendingUpdatesForStorageServiceWithGroupId:groupId];
        }

        [[NSNotificationCenter defaultCenter]
            postNotificationNameAsync:kNSNotificationNameProfileWhitelistDidChange
                               object:nil
                             userInfo:@{
                                 kNSNotificationKey_ProfileGroupId : groupId,
                                 kNSNotificationKey_UserProfileWriter : @(userProfileWriter),
                             }];
    }];
}

- (void)addConfirmedUnwhitelistedGroupId:(NSData *)groupId
                       userProfileWriter:(UserProfileWriter)userProfileWriter
                             transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    NSString *groupIdKey = [self groupKeyForGroupId:groupId];

    [self.whitelistedGroupsStore setBool:YES key:groupIdKey transaction:transaction];

    [TSGroupThread ensureGroupIdMappingForGroupId:groupId transaction:transaction];
    TSThread *_Nullable groupThread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
    if (groupThread) {
        [self.databaseStorage touchThread:groupThread shouldReindex:NO transaction:transaction];
    }

    [transaction addSyncCompletion:^{
        // Mark the group for update
        if (shouldUpdateStorageServiceForUserProfileWriter(userProfileWriter)) {
            [self recordPendingUpdatesForStorageServiceWithGroupId:groupId];
        }

        [[NSNotificationCenter defaultCenter]
            postNotificationNameAsync:kNSNotificationNameProfileWhitelistDidChange
                               object:nil
                             userInfo:@{
                                 kNSNotificationKey_ProfileGroupId : groupId,
                                 kNSNotificationKey_UserProfileWriter : @(userProfileWriter),
                             }];
    }];
}

- (void)recordPendingUpdatesForStorageServiceWithGroupId:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    [self.databaseStorage asyncReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        TSGroupThread *_Nullable groupThread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
        if (groupThread == nil) {
            OWSFailDebug(@"Missing groupThread.");
            return;
        }
        
        [self.storageServiceManager recordPendingUpdatesWithGroupModel:groupThread.groupModel];
    }];
}

- (void)addThreadToProfileWhitelist:(TSThread *)thread
{
    OWSAssertDebug(thread);

    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        NSData *groupId = groupThread.groupModel.groupId;
        [self addGroupIdToProfileWhitelist:groupId];
    } else {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self addUserToProfileWhitelist:contactThread.contactAddress];
    }
}

// TODO: We could add a userProfileWriter parameter.
- (void)addThreadToProfileWhitelist:(TSThread *)thread transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(thread);

    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        NSData *groupId = groupThread.groupModel.groupId;
        [self addGroupIdToProfileWhitelist:groupId
                         userProfileWriter:UserProfileWriter_LocalUser
                               transaction:transaction];
    } else {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self addUserToProfileWhitelist:contactThread.contactAddress
                      userProfileWriter:UserProfileWriter_LocalUser
                            transaction:transaction];
    }
}

- (BOOL)isGroupIdInProfileWhitelist:(NSData *)groupId transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    // isGroupIdBlocked can open a sneaky transaction in
    // BlockingManager.ensureLazyInitialization(), but we avoid this
    // by ensuring that BlockingManager.warmCaches() is always
    // called first.  I've added asserts within BlockingManager around
    // this.
    if ([self.blockingManager isGroupIdBlocked:groupId]) {
        return NO;
    }

    NSString *groupIdKey = [self groupKeyForGroupId:groupId];

    return [self.whitelistedGroupsStore hasValueForKey:groupIdKey transaction:transaction];
}

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread);

    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        NSData *groupId = groupThread.groupModel.groupId;
        return [self isGroupIdInProfileWhitelist:groupId transaction:transaction];
    } else {
        TSContactThread *contactThread = (TSContactThread *)thread;
        return [self isUserInProfileWhitelist:contactThread.contactAddress transaction:transaction];
    }
}

- (void)setContactAddresses:(NSArray<SignalServiceAddress *> *)contactAddresses
{
    OWSAssertDebug(contactAddresses);

    [self addUsersToProfileWhitelist:contactAddresses];
}

#pragma mark - Other User's Profiles

- (void)logUserProfiles
{
    [self.databaseStorage asyncReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        OWSLogError(@"logUserProfiles: %ld", (unsigned long)[OWSUserProfile anyCountWithTransaction:transaction]);

        [OWSUserProfile
            anyEnumerateWithTransaction:transaction
                                batched:YES
                                  block:^(OWSUserProfile *userProfile, BOOL *stop) {
                                      OWSLogError(@"\t [%@]: has profile key: %d, has avatar URL: %d, has "
                                                  @"avatar file: %d, given name: %@, family name: %@, username: %@",
                                          userProfile.publicAddress,
                                          userProfile.profileKey != nil,
                                          userProfile.avatarUrlPath != nil,
                                          userProfile.avatarFileName != nil,
                                          userProfile.givenName,
                                          userProfile.familyName,
                                          userProfile.username);
                                  }];
    }];
}

- (void)setProfileKeyData:(NSData *)profileKeyData
               forAddress:(SignalServiceAddress *)address
        userProfileWriter:(UserProfileWriter)userProfileWriter
              transaction:(SDSAnyWriteTransaction *)transaction
{
    [self setProfileKeyData:profileKeyData
                 forAddress:address
        onlyFillInIfMissing:NO
          userProfileWriter:userProfileWriter
                transaction:transaction];
}

- (void)setProfileKeyData:(NSData *)profileKeyData
               forAddress:(SignalServiceAddress *)addressParam
      onlyFillInIfMissing:(BOOL)onlyFillInIfMissing
        userProfileWriter:(UserProfileWriter)userProfileWriter
              transaction:(SDSAnyWriteTransaction *)transaction
{
    SignalServiceAddress *address = [OWSUserProfile resolveUserProfileAddress:addressParam];

    OWSAES256Key *_Nullable profileKey = [OWSAES256Key keyWithData:profileKeyData];
    if (profileKey == nil) {
        OWSFailDebug(@"Failed to make profile key for key data");
        return;
    }

    OWSUserProfile *userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address transaction:transaction];
    OWSAssertDebug(userProfile);

    if (onlyFillInIfMissing && userProfile.profileKey != nil) {
        return;
    }

    if (userProfile.profileKey && [userProfile.profileKey.keyData isEqual:profileKey.keyData]) {
        // Ignore redundant update.
        return;
    }

    // Whenever a user's profile key changes, we need to fetch a new
    // profile key credential for them.
    [self.versionedProfiles clearProfileKeyCredentialForAddress:address transaction:transaction];

    [userProfile updateWithProfileKey:profileKey
                    userProfileWriter:userProfileWriter
                          transaction:transaction
                           completion:^{
                               dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                                   // If this is the profile for the local user, we always want to defer to local state
                                   // so skip the update profile for address call.
                                   if ([OWSUserProfile isLocalProfileAddress:address]) {
                                       return;
                                   }

                                   [self.udManager setUnidentifiedAccessMode:UnidentifiedAccessModeUnknown
                                                                     address:address];
                                   [self fetchProfileForAddress:address];
                               });
                           }];
}

- (void)fillInMissingProfileKeys:(NSDictionary<SignalServiceAddress *, NSData *> *)profileKeys
               userProfileWriter:(UserProfileWriter)userProfileWriter
{
    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        for (SignalServiceAddress *address in profileKeys) {
            NSData *_Nullable profileKeyData = profileKeys[address];
            if (profileKeyData == nil) {
                OWSFailDebug(@"Missing profileKeyData.");
                continue;
            }
            OWSAES256Key *_Nullable key = [OWSAES256Key keyWithData:profileKeyData];
            if (key == nil) {
                OWSFailDebug(@"Invalid profileKeyData.");
                continue;
            }
            NSData *_Nullable existingProfileKeyData = [self profileKeyDataForAddress:address transaction:transaction];
            if ([NSObject isNullableObject:existingProfileKeyData equalTo:profileKeyData]) {
                // Redundant profileKeyData; no need to update.
                continue;
            }
            OWSLogInfo(@"Filling in missing profile key for: %@", address);
            [self setProfileKeyData:profileKeyData
                         forAddress:address
                onlyFillInIfMissing:YES
                  userProfileWriter:userProfileWriter
                        transaction:transaction];
        }
    });
}

- (void)setProfileGivenName:(nullable NSString *)givenName
                 familyName:(nullable NSString *)familyName
                 forAddress:(SignalServiceAddress *)addressParam
          userProfileWriter:(UserProfileWriter)userProfileWriter
                transaction:(SDSAnyWriteTransaction *)transaction
{
    SignalServiceAddress *address = [OWSUserProfile resolveUserProfileAddress:addressParam];
    OWSAssertDebug(address.isValid);

    OWSUserProfile *userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address transaction:transaction];
    [userProfile updateWithGivenName:givenName
                          familyName:familyName
                   userProfileWriter:userProfileWriter
                         transaction:transaction
                          completion:nil];
}

- (void)setProfileGivenName:(nullable NSString *)givenName
                 familyName:(nullable NSString *)familyName
              avatarUrlPath:(nullable NSString *)avatarUrlPath
                 forAddress:(SignalServiceAddress *)addressParam
          userProfileWriter:(UserProfileWriter)userProfileWriter
                transaction:(SDSAnyWriteTransaction *)transaction
{
    SignalServiceAddress *address = [OWSUserProfile resolveUserProfileAddress:addressParam];
    OWSAssertDebug(address.isValid);

    OWSUserProfile *userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address transaction:transaction];
    [userProfile updateWithGivenName:givenName
                          familyName:familyName
                       avatarUrlPath:avatarUrlPath
                   userProfileWriter:userProfileWriter
                         transaction:transaction
                          completion:nil];

    if (userProfile.avatarUrlPath.length > 0 && userProfile.avatarFileName.length < 1) {
        [self downloadAvatarForUserProfile:userProfile];
    }
}

- (nullable NSData *)profileKeyDataForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    return [self profileKeyForAddress:address transaction:transaction].keyData;
}

- (BOOL)recipientAddressIsUuidCapable:(nonnull SignalServiceAddress *)address
                          transaction:(nonnull SDSAnyReadTransaction *)transaction
{
    OWSUserProfile *_Nullable userProfile = [OWSUserProfile getUserProfileForAddress:address transaction:transaction];
    if (userProfile == nil) {
        return NO;
    } else {
        return userProfile.isUuidCapable;
    }
}

- (nullable OWSAES256Key *)profileKeyForAddress:(SignalServiceAddress *)address
                                    transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.profileKey;
}

- (nullable NSString *)unfilteredGivenNameForAddress:(SignalServiceAddress *)address
                                         transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.unfilteredGivenName;
}

- (nullable NSString *)givenNameForAddress:(SignalServiceAddress *)address
                               transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.givenName;
}

- (nullable NSString *)unfilteredFamilyNameForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.unfilteredFamilyName;
}


- (nullable NSString *)familyNameForAddress:(SignalServiceAddress *)address
                                transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.familyName;
}

- (nullable NSPersonNameComponents *)nameComponentsForAddress:(SignalServiceAddress *)address
                                                  transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.nameComponents;
}

- (nullable NSString *)fullNameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.fullName;
}

- (nullable UIImage *)profileAvatarForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    if (userProfile.avatarFileName.length > 0) {
        return [self loadProfileAvatarWithFilename:userProfile.avatarFileName];
    }

    if (userProfile.avatarUrlPath.length > 0) {
        // Try to fill in missing avatar.
        [self downloadAvatarForUserProfile:userProfile];
    }

    return nil;
}

- (BOOL)hasProfileAvatarData:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];
    if (userProfile.avatarFileName.length < 1) {
        return NO;
    } else {
        NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:userProfile.avatarFileName];
        return [OWSFileSystem fileOrFolderExistsAtPath:filePath];
    }
}

- (nullable NSData *)profileAvatarDataForAddress:(SignalServiceAddress *)address
                                     transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    if (userProfile.avatarFileName.length > 0) {
        return [self loadProfileAvatarDataWithFilename:userProfile.avatarFileName];
    }

    return nil;
}

- (nullable NSString *)profileAvatarURLPathForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    if (userProfile.avatarUrlPath.length > 0 && userProfile.avatarFileName.length == 0) {
        // Try to fill in missing avatar.
        [self downloadAvatarForUserProfile:userProfile];
    }

    return userProfile.avatarUrlPath;
}

- (nullable NSString *)usernameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction
{
    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    if (userProfile.username.length > 0) {
        return userProfile.username;
    }

    return nil;
}

- (nullable NSString *)profileBioForDisplayForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return [OWSUserProfile bioForDisplayWithBio:userProfile.bio bioEmoji:userProfile.bioEmoji];
}

- (nullable OWSUserProfile *)getUserProfileForAddress:(SignalServiceAddress *)addressParam
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    SignalServiceAddress *address = [OWSUserProfile resolveUserProfileAddress:addressParam];
    OWSAssertDebug(address.isValid);

    // For "local reads", use the local user profile.
    if ([OWSUserProfile isLocalProfileAddress:address]) {
        return [self getLocalUserProfileWithTransaction:transaction];
    }

    return [self.modelReadCaches.userProfileReadCache getUserProfileWithAddress:address transaction:transaction];
}

- (NSString *)generateAvatarFilename
{
    return [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"jpg"];
}

// We may know a profile's avatar URL (avatarUrlPath != nil) but not
// have downloaded the avatar data yet (avatarFileName == nil).
// We use this method to fill in these missing avatars.
- (void)downloadAvatarForUserProfile:(OWSUserProfile *)userProfile
{
    OWSAssertDebug(userProfile);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block OWSBackgroundTask *backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

        // Record the avatarUrlPath and profileKey; if they change
        // during the avatar download, we don't want to update the profile.
        __block NSString *_Nullable avatarUrlPathAtStart;
        __block OWSAES256Key *_Nullable profileKeyAtStart;
        __block BOOL shouldDownload;
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            OWSUserProfile *_Nullable currentUserProfile = [OWSUserProfile getUserProfileForAddress:userProfile.address
                                                                                        transaction:transaction];
            if (currentUserProfile == nil) {
                OWSFailDebug(@"Aborting; currentUserProfile cannot be found.");
                shouldDownload = NO;
                return;
            }
            avatarUrlPathAtStart = currentUserProfile.avatarUrlPath;
            profileKeyAtStart = currentUserProfile.profileKey;
            if (profileKeyAtStart.keyData.length < 1 || avatarUrlPathAtStart.length < 1) {
                OWSLogVerbose(@"Aborting; avatarUrlPath or profileKey are not known.");
                shouldDownload = NO;
                return;
            }
            if (currentUserProfile.avatarFileName.length > 0) {
                OWSLogVerbose(@"Aborting; avatar already present.");
                shouldDownload = NO;
                return;
            }
            shouldDownload = YES;
        }];
        if (!shouldDownload) {
            return;
        }

        NSString *filename = [self generateAvatarFilename];
        NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:filename];

        // downloadAndDecryptProfileAvatarForProfileAddress:... ensures that
        // only one download is in flight at a time for a given avatar.
        [self downloadAndDecryptProfileAvatarForProfileAddress:userProfile.address
                                                 avatarUrlPath:avatarUrlPathAtStart
                                                    profileKey:profileKeyAtStart]
            .thenInBackground(^(id value) {
                if (![value isKindOfClass:[NSData class]]) {
                    OWSFailDebug(@"Invalid value.");
                    return;
                }
                NSData *decryptedData = value;
                BOOL success = [decryptedData writeToFile:filePath atomically:YES];
                if (!success) {
                    OWSFailDebug(@"Could not write avatar to disk.");
                    return;
                }

                UIImage *_Nullable image = [UIImage imageWithContentsOfFile:filePath];
                if (image == nil) {
                    OWSLogError(@"Could not read avatar image.");
                    return;
                }

                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                    OWSUserProfile *currentUserProfile =
                        [OWSUserProfile getOrBuildUserProfileForAddress:userProfile.address transaction:transaction];

                    if (currentUserProfile.avatarFileName.length > 0) {
                        OWSLogVerbose(@"Aborting; avatar already present.");
                        return;
                    }

                    if (![NSObject isNullableObject:currentUserProfile.profileKey.keyData equalTo:profileKeyAtStart]
                        || ![NSObject isNullableObject:currentUserProfile.avatarUrlPath equalTo:avatarUrlPathAtStart]) {
                        OWSLogVerbose(@"Aborting; profileKey or avatarUrlPath has changed.");
                        // If the profileKey or avatarUrlPath has changed,
                        // abort and kick off a new download if necessary.
                        if (currentUserProfile.avatarFileName == nil) {
                            [transaction
                                addAsyncCompletionOffMain:^{ [self downloadAvatarForUserProfile:currentUserProfile]; }];
                        }
                    }

                    [currentUserProfile updateWithAvatarFileName:filename
                                               userProfileWriter:UserProfileWriter_AvatarDownload
                                                     transaction:transaction];
                });

                OWSAssertDebug(backgroundTask);
                backgroundTask = nil;
            });
    });
}

- (void)updateProfileForAddress:(SignalServiceAddress *)addressParam
                      givenName:(nullable NSString *)givenName
                     familyName:(nullable NSString *)familyName
                            bio:(nullable NSString *)bio
                       bioEmoji:(nullable NSString *)bioEmoji
                       username:(nullable NSString *)username
                  isUuidCapable:(BOOL)isUuidCapable
                  avatarUrlPath:(nullable NSString *)avatarUrlPath
    optionalDecryptedAvatarData:(nullable NSData *)optionalDecryptedAvatarData
                  lastFetchDate:(NSDate *)lastFetchDate
              userProfileWriter:(UserProfileWriter)userProfileWriter
{
    SignalServiceAddress *address = [OWSUserProfile resolveUserProfileAddress:addressParam];
    OWSAssertDebug(address.isValid);

    OWSLogDebug(@"update profile for: %@ -> %@, givenName: %@, familyName: %@, bio: %@, bioEmoji: %@, avatar: %@, "
                @"avatarData: %d",
        addressParam,
        address,
        givenName,
        familyName,
        bio,
        bioEmoji,
        avatarUrlPath,
        optionalDecryptedAvatarData.length > 0);

    // Ensure decryption, etc. off main thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // If the optional avatar data is present, prepare for
        // its possible usage by trying to write it to disk
        // and verifying that it can be read.
        NSString *_Nullable avatarFileName;
        UIImage *_Nullable avatarImage = nil;
        // The avatar won't always be pre-downloaded.
        // We may have to fill in it below.
        if (optionalDecryptedAvatarData.length > 0) {
            OWSAssertDebug(avatarUrlPath.length > 0);
            
            NSString *newAvatarFileName = [self generateAvatarFilename];
            NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:newAvatarFileName];
            BOOL success = [optionalDecryptedAvatarData writeToFile:filePath atomically:YES];
            if (!success) {
                OWSFailDebug(@"Could not write avatar to disk.");
            } else {
                avatarFileName = newAvatarFileName;
                avatarImage = [UIImage imageWithContentsOfFile:filePath];
            }
        }
        
        __block OWSUserProfile *userProfile;
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address transaction:transaction];
            
            if (!userProfile.profileKey) {
                [userProfile updateWithUsername:username
                                  isUuidCapable:isUuidCapable
                                  lastFetchDate:lastFetchDate
                              userProfileWriter:userProfileWriter
                                    transaction:transaction];
                return;
            }
            
            if (avatarImage != nil) {
                [userProfile updateWithGivenName:givenName
                                      familyName:familyName
                                             bio:bio
                                        bioEmoji:bioEmoji
                                        username:username
                                   isUuidCapable:isUuidCapable
                                   avatarUrlPath:avatarUrlPath
                                  avatarFileName:avatarFileName
                                   lastFetchDate:lastFetchDate
                               userProfileWriter:userProfileWriter
                                     transaction:transaction
                                      completion:nil];
            } else {
                [userProfile updateWithGivenName:givenName
                                      familyName:familyName
                                             bio:bio
                                        bioEmoji:bioEmoji
                                        username:username
                                   isUuidCapable:isUuidCapable
                                   avatarUrlPath:avatarUrlPath
                                   lastFetchDate:lastFetchDate
                               userProfileWriter:userProfileWriter
                                     transaction:transaction
                                      completion:nil];
            }
            
            if (userProfile.avatarFileName.length > 0) {
                NSString *path = [OWSUserProfile profileAvatarFilepathWithFilename:userProfile.avatarFileName];
                if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
                    OWSLogError(@"downloaded file is missing for profile: %@", userProfile.address);
                    [userProfile updateWithAvatarFileName:nil
                                        userProfileWriter:userProfileWriter
                                              transaction:transaction];
                }
            }
        });
        
        // Whenever we change avatarUrlPath, OWSUserProfile clears avatarFileName.
        // So if avatarUrlPath is set and avatarFileName is not set, we should to
        // download this avatar. downloadAvatarForUserProfile will de-bounce
        // downloads.
        if (userProfile.avatarUrlPath.length > 0 && userProfile.avatarFileName.length < 1) {
            [self downloadAvatarForUserProfile:userProfile];
        }
    });
}

- (BOOL)isNullableDataEqual:(NSData *_Nullable)left toData:(NSData *_Nullable)right
{
    if (left == nil && right == nil) {
        return YES;
    } else if (left == nil || right == nil) {
        return YES;
    } else {
        return [left isEqual:right];
    }
}

- (BOOL)isNullableStringEqual:(NSString *_Nullable)left toString:(NSString *_Nullable)right
{
    if (left == nil && right == nil) {
        return YES;
    } else if (left == nil || right == nil) {
        return YES;
    } else {
        return [left isEqualToString:right];
    }
}

#pragma mark - Profile Encryption

- (BOOL)isProfileNameTooLong:(nullable NSString *)profileName
{
    OWSAssertIsOnMainThread();

    if (profileName.glyphCount > OWSUserProfile.maxNameLengthGlyphs) {
        return YES;
    }
    NSData *nameData = [profileName dataUsingEncoding:NSUTF8StringEncoding];
    return nameData.length > (NSUInteger)OWSUserProfile.maxNameLengthBytes;
}

#pragma mark - Avatar Disk Cache

- (nullable NSData *)loadProfileAvatarDataWithFilename:(NSString *)filename
{
    OWSAssertDebug(filename.length > 0);

    NSUInteger loadCount = [self.profileAvatarDataLoadCounter increment];

    OWSLogVerbose(@"---- loading profile avatar data: %lu.", loadCount);

    NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:filename];
    NSData *_Nullable avatarData = [NSData dataWithContentsOfFile:filePath];

    if (![avatarData ows_isValidImage]) {
        return nil;
    }

    if (nil != avatarData) {
        return avatarData;
    }

    OWSLogWarn(@"Could not load profile avatar data.");
    return nil;
}

- (nullable UIImage *)loadProfileAvatarWithFilename:(NSString *)filename
{
    if (filename.length == 0) {
        return nil;
    }

    NSData *_Nullable data = [self loadProfileAvatarDataWithFilename:filename];
    if (nil == data) {
        return nil;
    }
    NSUInteger loadCount = [self.profileAvatarImageLoadCounter increment];
    OWSLogVerbose(@"---- loading profile avatar image: %lu.", loadCount);
    UIImage *_Nullable image = [UIImage imageWithData:data];
    if (image) {
        return image;
    } else {
        OWSLogWarn(@"Could not load profile avatar.");
        return nil;
    }
}

- (AnyPromise *)downloadAndDecryptProfileAvatarForProfileAddress:(SignalServiceAddress *)profileAddress
                                                   avatarUrlPath:(NSString *)avatarUrlPath
                                                      profileKey:(OWSAES256Key *)profileKey
{
    return [OWSProfileManager avatarDownloadAndDecryptPromiseObjcWithProfileAddress:profileAddress
                                                                      avatarUrlPath:avatarUrlPath
                                                                         profileKey:profileKey];
}

#pragma mark - Messaging History

- (void)didSendOrReceiveMessageFromAddress:(SignalServiceAddress *)addressParam
                               transaction:(SDSAnyWriteTransaction *)transaction
{
    SignalServiceAddress *address = [OWSUserProfile resolveUserProfileAddress:addressParam];
    OWSAssertDebug(address.isValid);

    if (address.isLocalAddress) {
        return;
    }

    OWSUserProfile *userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address transaction:transaction];

    if (userProfile.lastMessagingDate != nil) {
        // lastMessagingDate is coarse; we don't need to track
        // every single message sent or received.  It is sufficient
        // to update it only when the value changes by more than
        // an hour.
        NSTimeInterval lastMessagingInterval = fabs(userProfile.lastMessagingDate.timeIntervalSinceNow);
        const NSTimeInterval lastMessagingResolution = 1 * kHourInterval;
        if (lastMessagingInterval < lastMessagingResolution) {
            return;
        }
    }

    [userProfile updateWithLastMessagingDate:[NSDate new]
                           userProfileWriter:UserProfileWriter_MetadataUpdate
                                 transaction:transaction];
}

#pragma mark - User Interface

- (void)presentAddThreadToProfileWhitelist:(TSThread *)thread
                        fromViewController:(UIViewController *)fromViewController
                                   success:(void (^)(void))successHandler
{
    OWSAssertIsOnMainThread();

    ActionSheetController *actionSheet = [[ActionSheetController alloc] init];

    NSString *shareTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_VIEW_SHARE_PROFILE",
        @"Button to confirm that user wants to share their profile with a user or group.");
    [actionSheet
        addAction:[[ActionSheetAction alloc] initWithTitle:shareTitle
                                   accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"share_profile")
                                                     style:ActionSheetActionStyleDefault
                                                   handler:^(ActionSheetAction *_Nonnull action) {
                                                       [self userAddedThreadToProfileWhitelist:thread];
                                                       successHandler();
                                                   }]];
    [actionSheet addAction:[OWSActionSheets cancelAction]];

    [fromViewController presentActionSheet:actionSheet];
}

- (void)userAddedThreadToProfileWhitelist:(TSThread *)thread
{
    OWSAssertIsOnMainThread();

    BOOL isFeatureEnabled = NO;
    if (!isFeatureEnabled) {
        OWSLogWarn(@"skipping sending profile-key message because the feature is not yet fully available.");
        [OWSProfileManager.shared addThreadToProfileWhitelist:thread];
        return;
    }

    OWSProfileKeyMessage *message = [[OWSProfileKeyMessage alloc] initWithThread:thread];
    [OWSProfileManager.shared addThreadToProfileWhitelist:thread];

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
    });
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    // TODO: Sync if necessary.

    [OWSProfileManager updateProfileOnServiceIfNecessary];
}

- (void)reachabilityChanged:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [OWSProfileManager updateProfileOnServiceIfNecessary];
}

- (void)blockListDidChange:(NSNotification *)notification {
    OWSAssertIsOnMainThread();

    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{ [self rotateLocalProfileKeyIfNecessary]; });
}

#ifdef DEBUG
+ (void)discardAllProfileKeysWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    NSArray<OWSUserProfile *> *userProfiles = [OWSUserProfile anyFetchAllWithTransaction:transaction];
    for (OWSUserProfile *userProfile in userProfiles) {
        if ([OWSUserProfile isLocalProfileAddress:userProfile.address]) {
            continue;
        }
        if (userProfile.profileKey == nil) {
            continue;
        }
        [userProfile discardProfileKeyWithUserProfileWriter:UserProfileWriter_Debugging transaction:transaction];
    }
}
#endif

#pragma mark - Clean Up

+ (NSSet<NSString *> *)allProfileAvatarFilePathsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [OWSUserProfile allProfileAvatarFilePathsWithTransaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
