//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
#import <SignalServiceKit/NSData+Image.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSProfileKeyMessage.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/OWSUploadV2.h>
#import <SignalServiceKit/OWSUserProfile.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/UIImage+OWS.h>

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const kNSNotificationNameProfileKeyDidChange = @"kNSNotificationNameProfileKeyDidChange";

// The max bytes for a user's profile name, encoded in UTF8.
// Before encrypting and submitting we NULL pad the name data to this length.
const NSUInteger kOWSProfileManager_NameDataLength = 26;
const NSUInteger kOWSProfileManager_MaxAvatarDiameter = 640;
const NSString *kNSNotificationKey_WasLocallyInitiated = @"kNSNotificationKey_WasLocallyInitiated";

@interface OWSProfileManager ()

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) OWSUserProfile *localUserProfile;

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) NSCache<NSString *, UIImage *> *profileAvatarImageCache;

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) NSMutableSet<SignalServiceAddress *> *currentAvatarDownloads;

@end

#pragma mark -

// Access to most state should happen while synchronized on the profile manager.
// Writes should happen off the main thread, wherever possible.
@implementation OWSProfileManager

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

@synthesize localUserProfile = _localUserProfile;
@synthesize userProfileReadCache = _userProfileReadCache;

+ (instancetype)sharedManager
{
    return SSKEnvironment.shared.profileManager;
}

- (instancetype)initWithDatabaseStorage:(SDSDatabaseStorage *)databaseStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertIsOnMainThread();
    OWSAssertDebug(databaseStorage);

    _whitelistedPhoneNumbersStore =
        [[SDSKeyValueStore alloc] initWithCollection:@"kOWSProfileManager_UserWhitelistCollection"];
    _whitelistedUUIDsStore =
        [[SDSKeyValueStore alloc] initWithCollection:@"kOWSProfileManager_UserUUIDWhitelistCollection"];
    _whitelistedGroupsStore =
        [[SDSKeyValueStore alloc] initWithCollection:@"kOWSProfileManager_GroupWhitelistCollection"];

    _profileAvatarImageCache = [NSCache new];
    _currentAvatarDownloads = [NSMutableSet new];
    _userProfileReadCache = [UserProfileReadCache new];

    OWSSingletonAssert();

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        if (TSAccountManager.sharedInstance.isRegistered) {
            [self rotateLocalProfileKeyIfNecessary];
            [OWSProfileManager updateProfileOnServiceIfNecessaryObjc];
        }
    }];

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
                                                 name:kReachabilityChangedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockListDidChange:)
                                                 name:kNSNotificationName_BlockListDidChange
                                               object:nil];
}

#pragma mark - Dependencies

- (TSAccountManager *)tsAccountManager
{
    return TSAccountManager.sharedInstance;
}

- (AFHTTPSessionManager *)avatarHTTPManager
{
    return [OWSSignalService sharedInstance].CDNSessionManager;
}

- (OWSIdentityManager *)identityManager
{
    return SSKEnvironment.shared.identityManager;
}

- (MessageSenderJobQueue *)messageSenderJobQueue
{
    return SSKEnvironment.shared.messageSenderJobQueue;
}

- (TSNetworkManager *)networkManager
{
    return SSKEnvironment.shared.networkManager;
}

- (OWSBlockingManager *)blockingManager
{
    return SSKEnvironment.shared.blockingManager;
}

- (id<SyncManagerProtocol>)syncManager
{
    return SSKEnvironment.shared.syncManager;
}

- (id<OWSUDManager>)udManager
{
    OWSAssertDebug(SSKEnvironment.shared.udManager);

    return SSKEnvironment.shared.udManager;
}

#pragma mark - User Profile Accessor

- (void)warmCaches
{
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

            return _localUserProfile;
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
        return localUserProfile;
    }

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        localUserProfile =
            [OWSUserProfile getOrBuildUserProfileForAddress:OWSUserProfile.localProfileAddress transaction:transaction];
    }];

    @synchronized(self) {
        _localUserProfile = localUserProfile;
    }

    OWSAssertDebug(_localUserProfile.profileKey);

    return _localUserProfile;
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
    return [self loadProfileDataWithFilename:filename];
}

- (nullable NSString *)localUsername
{
    return self.localUserProfile.username;
}

- (void)updateLocalUsername:(nullable NSString *)username transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(username == nil || username.length > 0);

    OWSUserProfile *userProfile = self.localUserProfile;
    OWSAssertDebug(self.localUserProfile);

    [userProfile updateWithUsername:username transaction:transaction];
}

- (void)writeAvatarToDiskWithData:(NSData *)avatarData
                          success:(void (^)(NSString *fileName))successBlock
                          failure:(ProfileManagerFailureBlock)failureBlock
{
    OWSAssertDebug(avatarData);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *fileName = [self generateAvatarFilename];
        NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:fileName];
        BOOL success = [avatarData writeToFile:filePath atomically:YES];
        OWSAssertDebug(success);
        if (success) {
            return successBlock(fileName);
        }
        failureBlock(OWSErrorWithCodeDescription(OWSErrorCodeAvatarWriteFailed, @"Avatar write failed."));
    });
}

+ (NSData *)avatarDataForAvatarImage:(UIImage *)image
{
    NSUInteger kMaxAvatarBytes = 5 * 1000 * 1000;

    if (image.size.width != kOWSProfileManager_MaxAvatarDiameter
        || image.size.height != kOWSProfileManager_MaxAvatarDiameter) {
        // To help ensure the user is being shown the same cropping of their avatar as
        // everyone else will see, we want to be sure that the image was resized before this point.
        OWSFailDebug(@"Avatar image should have been resized before trying to upload");
        image = [image resizedImageToFillPixelSize:CGSizeMake(kOWSProfileManager_MaxAvatarDiameter,
                                                       kOWSProfileManager_MaxAvatarDiameter)];
    }

    NSData *_Nullable data = UIImageJPEGRepresentation(image, 0.95f);
    if (data.length > kMaxAvatarBytes) {
        // Our avatar dimensions are so small that it's incredibly unlikely we wouldn't be able to fit our profile
        // photo. e.g. generating pure noise at our resolution compresses to ~200k.
        OWSFailDebug(@"Suprised to find profile avatar was too large. Was it scaled properly? image: %@", image);
    }

    return data;
}

// If avatarData is nil, we are clearing the avatar.
- (void)updateServiceWithUnversionedProfileAvatarData:(nullable NSData *)avatarData
                                              success:(void (^)(NSString *_Nullable avatarUrlPath))successBlock
                                              failure:(ProfileManagerFailureBlock)failureBlock
{
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);
    OWSAssertDebug(avatarData == nil || avatarData.length > 0);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *_Nullable encryptedAvatarData;
        if (avatarData) {
            encryptedAvatarData = [self encryptLocalProfileData:avatarData];
            OWSAssertDebug(encryptedAvatarData.length > 0);
        }

        OWSAvatarUploadV2 *upload = [OWSAvatarUploadV2 new];
        [[upload uploadAvatarToService:encryptedAvatarData
                         progressBlock:^(NSProgress *progress){
                             // Do nothing.
                         }]
                .thenInBackground(^{
                    OWSLogVerbose(@"Upload complete.");

                    successBlock(upload.urlPath);
                })
                .catchInBackground(^(NSError *error) {
                    OWSLogError(@"Failed: %@", error);

                    failureBlock(error);
                }) retainUntilComplete];
    });
}

// If profileName is nil, we are clearing the profileName.
- (void)updateServiceWithUnversionedGivenName:(nullable NSString *)givenName
                                   familyName:(nullable NSString *)familyName
                                      success:(void (^)(void))successBlock
                                      failure:(ProfileManagerFailureBlock)failureBlock
{
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSPersonNameComponents *nameComponents = [NSPersonNameComponents new];
        nameComponents.givenName = givenName;
        nameComponents.familyName = familyName;
        NSData *_Nullable encryptedPaddedName = [self encryptLocalProfileNameComponents:nameComponents];
        if (encryptedPaddedName == nil) {
            failureBlock(OWSErrorMakeAssertionError(@"encryptedPaddedName was unexpectedly nil"));
        }

        TSRequest *request = [OWSRequestFactory profileNameSetRequestWithEncryptedPaddedName:encryptedPaddedName];
        [self.networkManager makeRequest:request
            success:^(NSURLSessionDataTask *task, id responseObject) {
                successBlock();
            }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
                OWSLogError(@"Failed to update profile with error: %@", error);
                failureBlock(error);
            }];
    });
}

- (void)fetchAndUpdateLocalUsersProfile
{
    SignalServiceAddress *_Nullable localAddress = self.tsAccountManager.localAddress;
    if (!localAddress.isValid) {
        return;
    }
    [self updateProfileForAddress:localAddress];
}

- (void)updateProfileForAddress:(SignalServiceAddress *)address
{
    [ProfileFetcherJob fetchAndUpdateProfileWithAddress:address ignoreThrottling:YES];
}

- (void)fetchAndUpdateProfileForUsername:(NSString *)username
                                 success:(void (^)(SignalServiceAddress *))success
                                notFound:(void (^)(void))notFound
                                 failure:(void (^)(NSError *))failure
{
    OWSAssertDebug(username.length > 0);

    // Check if we have a cached profile for this username, if so avoid fetching it from the service
    // since we are limited to 100 username lookups per day.

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block OWSUserProfile *_Nullable userProfile;
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            userProfile = [OWSUserProfile userProfileForUsername:username transaction:transaction];
        }];

        if (userProfile) {
            success(userProfile.address);
            return;
        }

        [ProfileFetcherJob fetchAndUpdateProfileWithUsername:username
                                                     success:success
                                                    notFound:notFound
                                                     failure:failure];
    });
}

#pragma mark - Profile Key Rotation

- (nullable NSString *)groupKeyForGroupId:(NSData *)groupId {
    NSString *groupIdKey = [groupId hexadecimalString];
    return groupIdKey;
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

    [self
        rotateLocalProfileKeyIfNecessaryWithSuccess:^{
        }
                                            failure:^(NSError *error) {
                                            }];
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

                // Note we don't add `group.recipientIds` to the `whitelistedRecipientIds`.
                //
                // Whenever we message a contact, be it in a 1:1 thread or in a group thread,
                // we add them to the contact whitelist, so there's no reason to redundnatly
                // add them here.
                //
                // Furthermore, doing so would cause the following problem:
                // - Alice is in group Book Club
                // - Add Book Club to your profile white list
                // - Message Book Club, which also adds Alice to your profile whitelist.
                // - Block Alice, but not Book Club
                //
                // Now, at this point we'd want to rotate our profile key once, since Alice has
                // it via BookClub.
                //
                // However, after we did. The next time we check if we should rotate our profile
                // key, adding all `group.recipientIds` to `whitelistedRecipientIds` here, would
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
            if (SSKFeatureFlags.allowUUIDOnlyContacts) {
                OWSFailDebug(@"Missing localUUID");
            }
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
                                      intersectingGroupIds:intersectingGroupIds
                                                   success:success
                                                   failure:failure];
    });
}

- (void)rotateProfileKeyWithIntersectingPhoneNumbers:(NSSet<NSString *> *)intersectingPhoneNumbers
                                   intersectingUUIDs:(NSSet<NSString *> *)intersectingUUIDs
                                intersectingGroupIds:(NSSet<NSData *> *)intersectingGroupIds
                                             success:(dispatch_block_t)success
                                             failure:(ProfileManagerFailureBlock)failure
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Rotate the profile key
        OWSLogInfo(@"Rotating the profile key.");

        // Make copies of the current local profile state.
        OWSUserProfile *localUserProfile = self.localUserProfile;
        NSString *_Nullable oldGivenName = localUserProfile.givenName;
        NSString *_Nullable oldFamilyName = localUserProfile.familyName;
        __block NSData *_Nullable oldAvatarData;

        // Rotate the stored profile key.
        AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
            [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
                SignalServiceAddress *_Nullable localAddress =
                    [self.tsAccountManager localAddressWithTransaction:transaction];
                oldAvatarData = [self profileAvatarDataForAddress:localAddress transaction:transaction];

                [self.localUserProfile updateWithProfileKey:[OWSAES256Key generateRandomKey]
                                        wasLocallyInitiated:YES
                                                transaction:transaction
                                                 completion:^{
                                                     // The value doesn't matter, we just need any non-NSError value.
                                                     resolve(@(1));
                                                 }];
            }];
        }];

        // Try to re-upload our profile name and avatar, if any.
        //
        // This may fail.
        promise = promise.thenInBackground(^(id value) {
            if (oldGivenName.length < 1) {
                return [AnyPromise promiseWithValue:@(1)];
            }
            return [OWSProfileManager updateLocalProfilePromiseObjWithProfileGivenName:oldGivenName
                                                                     profileFamilyName:oldFamilyName
                                                                     profileAvatarData:oldAvatarData];
        });

        promise = promise.thenInBackground(^(id value) {
            // Remove blocked users and groups from profile whitelist.
            //
            // This will always succeed.
            [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                [self.whitelistedPhoneNumbersStore removeValuesForKeys:intersectingPhoneNumbers.allObjects
                                                           transaction:transaction];
                [self.whitelistedUUIDsStore removeValuesForKeys:intersectingUUIDs.allObjects transaction:transaction];
                for (NSData *groupId in intersectingGroupIds) {
                    NSString *groupIdKey = [self groupKeyForGroupId:groupId];
                    [self.whitelistedGroupsStore removeValueForKey:groupIdKey transaction:transaction];
                }
            }];
            return @(1);
        });

        // Update account attributes.
        //
        // This may fail.
        promise = promise.thenInBackground(^(id value) {
            return [self.tsAccountManager updateAccountAttributes];
        });

        // Fetch local profile.
        promise = promise.then(^(id value) {
            [self fetchAndUpdateLocalUsersProfile];

            return @(1);
        });

        // Sync local profile key.
        if (self.tsAccountManager.isRegisteredPrimaryDevice) {
            promise = promise.thenInBackground(^(id value) {
                return [self.syncManager syncLocalContact];
            });
        }

        promise = promise.thenInBackground(^(id value) {
            [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kNSNotificationNameProfileKeyDidChange
                                                                     object:nil
                                                                   userInfo:nil];

            success();
        });
        promise = promise.catch(^(NSError *error) {
            if ([error isKindOfClass:[NSError class]]) {
                failure(error);
            } else {
                failure(OWSErrorMakeAssertionError(@"Profile key rotation failure missing error."));
            }
        });
        [promise retainUntilComplete];
    });
}

#pragma mark - Profile Whitelist

- (void)clearProfileWhitelist
{
    OWSLogWarn(@"Clearing the profile whitelist.");

    [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.whitelistedPhoneNumbersStore removeAllWithTransaction:transaction];
        [self.whitelistedUUIDsStore removeAllWithTransaction:transaction];
        [self.whitelistedGroupsStore removeAllWithTransaction:transaction];

        OWSAssertDebug(0 == [self.whitelistedPhoneNumbersStore numberOfKeysWithTransaction:transaction]);
        OWSAssertDebug(0 == [self.whitelistedUUIDsStore numberOfKeysWithTransaction:transaction]);
        OWSAssertDebug(0 == [self.whitelistedGroupsStore numberOfKeysWithTransaction:transaction]);
    }];
}

- (void)removeThreadFromProfileWhitelist:(TSThread *)thread
{
    OWSLogWarn(@"Removing thread from profile whitelist: %@", thread);
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        if ([thread isKindOfClass:TSContactThread.class]) {
            TSContactThread *contactThread = (TSContactThread *)thread;
            NSString *_Nullable phoneNumber = contactThread.contactAddress.phoneNumber;
            if (phoneNumber != nil) {
                [self.whitelistedPhoneNumbersStore removeValueForKey:phoneNumber transaction:transaction];
            }

            NSString *_Nullable uuidString = contactThread.contactAddress.uuidString;
            if (uuidString != nil) {
                [self.whitelistedUUIDsStore removeValueForKey:uuidString transaction:transaction];
            }
        } else {
            TSGroupThread *groupThread = (TSGroupThread *)thread;
            NSString *groupKey = [self groupKeyForGroupId:groupThread.groupModel.groupId];
            [self.whitelistedGroupsStore removeValueForKey:groupKey transaction:transaction];
        }
    }];
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
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [userProfile clearWithProfileKey:[OWSAES256Key generateRandomKey]
                     wasLocallyInitiated:YES
                             transaction:transaction
                              completion:nil];
    }];
    [[self.tsAccountManager updateAccountAttributes] retainUntilComplete];
}

- (void)setLocalProfileKey:(OWSAES256Key *)key
       wasLocallyInitiated:(BOOL)wasLocallyInitiated
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

            _localUserProfile = [OWSUserProfile getOrBuildUserProfileForAddress:OWSUserProfile.localProfileAddress transaction:transaction];
        }
        localUserProfile = _localUserProfile;
    }

    [localUserProfile updateWithProfileKey:key
                       wasLocallyInitiated:wasLocallyInitiated
                               transaction:transaction
                                completion:nil];
}

- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    [self addUsersToProfileWhitelist:@[ address ]];
}

- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses
{
    OWSAssertDebug(addresses);

    // Try to avoid opening a write transaction.
    [self.databaseStorage asyncReadWithBlock:^(SDSAnyReadTransaction *readTransaction) {
        NSSet<SignalServiceAddress *> *addressesToAdd = [self addressesNotBlockedOrInWhitelist:addresses
                                                                                   transaction:readTransaction];

        if (addressesToAdd.count < 1) {
            return;
        }

        [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *writeTransaction) {
            [self addConfirmedUnwhitelistedAddresses:addressesToAdd
                                 wasLocallyInitiated:YES
                                         transaction:writeTransaction];
        }];
    }];
}

- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address
              wasLocallyInitiated:(BOOL)wasLocallyInitiated
                      transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    NSSet *addressesToAdd = [self addressesNotBlockedOrInWhitelist:@[ address ] transaction:transaction];
    [self addConfirmedUnwhitelistedAddresses:addressesToAdd
                         wasLocallyInitiated:wasLocallyInitiated
                                 transaction:transaction];
}

- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses
               wasLocallyInitiated:(BOOL)wasLocallyInitiated
                       transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(addresses);
    OWSAssertDebug(transaction);

    NSSet<SignalServiceAddress *> *addressesToAdd = [self addressesNotBlockedOrInWhitelist:addresses
                                                                               transaction:transaction];

    if (addressesToAdd.count < 1) {
        return;
    }

    [self addConfirmedUnwhitelistedAddresses:addressesToAdd wasLocallyInitiated:YES transaction:transaction];
}

- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    [self removeUsersFromProfileWhitelist:@[ address ]];
}

- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address
                   wasLocallyInitiated:(BOOL)wasLocallyInitiated
                           transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    NSSet *addressesToRemove = [self addressesInWhitelist:@[ address ] transaction:transaction];
    [self removeConfirmedWhitelistedAddresses:addressesToRemove
                          wasLocallyInitiated:wasLocallyInitiated
                                  transaction:transaction];
}

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

        [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *writeTransaction) {
            [self removeConfirmedWhitelistedAddresses:addressesToRemove
                                  wasLocallyInitiated:YES
                                          transaction:writeTransaction];
        }];
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
                        wasLocallyInitiated:(BOOL)wasLocallyInitiated
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
    }

    [transaction addSyncCompletion:^{
        // Mark the removed whitelisted addresses for update
        if (wasLocallyInitiated) {
            [OWSStorageServiceManager.shared recordPendingUpdatesWithUpdatedAddresses:addressesToRemove.allObjects];
        }

        for (SignalServiceAddress *address in addressesToRemove) {
            [[NSNotificationCenter defaultCenter]
                postNotificationNameAsync:kNSNotificationNameProfileWhitelistDidChange
                                   object:nil
                                 userInfo:@{
                                     kNSNotificationKey_ProfileAddress : address,
                                     kNSNotificationKey_WasLocallyInitiated : @(wasLocallyInitiated),
                                 }];
        }
    }];
}

- (void)addConfirmedUnwhitelistedAddresses:(NSSet<SignalServiceAddress *> *)addressesToAdd
                       wasLocallyInitiated:(BOOL)wasLocallyInitiated
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
    }

    [transaction addSyncCompletion:^{
        // Mark the new whitelisted addresses for update
        if (wasLocallyInitiated) {
            [OWSStorageServiceManager.shared recordPendingUpdatesWithUpdatedAddresses:addressesToAdd.allObjects];
        }

        for (SignalServiceAddress *address in addressesToAdd) {
            [[NSNotificationCenter defaultCenter]
                postNotificationNameAsync:kNSNotificationNameProfileWhitelistDidChange
                                   object:nil
                                 userInfo:@{
                                     kNSNotificationKey_ProfileAddress : address,
                                     kNSNotificationKey_WasLocallyInitiated : @(wasLocallyInitiated),
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
        [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *writeTransaction) {
            [self addConfirmedUnwhitelistedGroupId:groupId wasLocallyInitiated:YES transaction:writeTransaction];
        }];
    }];
}

- (void)addGroupIdToProfileWhitelist:(NSData *)groupId
                 wasLocallyInitiated:(BOOL)wasLocallyInitiated
                         transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    NSString *groupIdKey = [self groupKeyForGroupId:groupId];

    if (![self.whitelistedGroupsStore hasValueForKey:groupIdKey transaction:transaction]) {
        [self addConfirmedUnwhitelistedGroupId:groupId wasLocallyInitiated:wasLocallyInitiated transaction:transaction];
    }
}

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
        [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *writeTransaction) {
            [self removeConfirmedWhitelistedGroupId:groupId wasLocallyInitiated:YES transaction:writeTransaction];
        }];
    }];
}

- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId
                      wasLocallyInitiated:(BOOL)wasLocallyInitiated
                              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    NSString *groupIdKey = [self groupKeyForGroupId:groupId];

    if ([self.whitelistedGroupsStore hasValueForKey:groupIdKey transaction:transaction]) {
        [self removeConfirmedWhitelistedGroupId:groupId
                            wasLocallyInitiated:wasLocallyInitiated
                                    transaction:transaction];
    }
}

- (void)removeConfirmedWhitelistedGroupId:(NSData *)groupId
                      wasLocallyInitiated:(BOOL)wasLocallyInitiated
                              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    NSString *groupIdKey = [self groupKeyForGroupId:groupId];

    [self.whitelistedGroupsStore removeValueForKey:groupIdKey transaction:transaction];

    [transaction addSyncCompletion:^{
        // Mark the group for update
        if (wasLocallyInitiated) {
            [OWSStorageServiceManager.shared recordPendingUpdatesWithUpdatedGroupIds:@[ groupId ]];
        }

        [[NSNotificationCenter defaultCenter]
            postNotificationNameAsync:kNSNotificationNameProfileWhitelistDidChange
                               object:nil
                             userInfo:@{
                                 kNSNotificationKey_ProfileGroupId : groupId,
                                 kNSNotificationKey_WasLocallyInitiated : @(wasLocallyInitiated),
                             }];
    }];
}

- (void)addConfirmedUnwhitelistedGroupId:(NSData *)groupId
                     wasLocallyInitiated:(BOOL)wasLocallyInitiated
                             transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    NSString *groupIdKey = [self groupKeyForGroupId:groupId];

    [self.whitelistedGroupsStore setBool:YES key:groupIdKey transaction:transaction];

    [transaction addSyncCompletion:^{
        // Mark the group for update
        if (wasLocallyInitiated) {
            [OWSStorageServiceManager.shared recordPendingUpdatesWithUpdatedGroupIds:@[ groupId ]];
        }

        [[NSNotificationCenter defaultCenter]
            postNotificationNameAsync:kNSNotificationNameProfileWhitelistDidChange
                               object:nil
                             userInfo:@{
                                 kNSNotificationKey_ProfileGroupId : groupId,
                                 kNSNotificationKey_WasLocallyInitiated : @(wasLocallyInitiated),
                             }];
    }];
}

- (void)addThreadToProfileWhitelist:(TSThread *)thread
{
    OWSAssertDebug(thread);

    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        NSData *groupId = groupThread.groupModel.groupId;
        [self addGroupIdToProfileWhitelist:groupId];

        // When we add a group to the profile whitelist, we might as well
        // also add all current members to the profile whitelist
        // individually as well just in case delivery of the profile key
        // fails.
        [self addUsersToProfileWhitelist:groupThread.recipientAddresses];
    } else {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self addUserToProfileWhitelist:contactThread.contactAddress];
    }
}

- (void)addThreadToProfileWhitelist:(TSThread *)thread transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(thread);

    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        NSData *groupId = groupThread.groupModel.groupId;
        [self addGroupIdToProfileWhitelist:groupId wasLocallyInitiated:YES transaction:transaction];

        // When we add a group to the profile whitelist, we might as well
        // also add all current members to the profile whitelist
        // individually as well just in case delivery of the profile key
        // fails.
        [self addUsersToProfileWhitelist:groupThread.recipientAddresses
                     wasLocallyInitiated:YES
                             transaction:transaction];
    } else {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self addUserToProfileWhitelist:contactThread.contactAddress wasLocallyInitiated:YES transaction:transaction];
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
                                          userProfile.address,
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
      wasLocallyInitiated:(BOOL)wasLocallyInitiated
              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAES256Key *_Nullable profileKey = [OWSAES256Key keyWithData:profileKeyData];
    if (profileKey == nil) {
        OWSFailDebug(@"Failed to make profile key for key data");
        return;
    }

    // We also keep track of our local profile key under a special hard coded address,
    // update it accordingly. This should generally only happen if we're restoring
    // our profile data from the storage service.
    if (address.isLocalAddress) {
        [self setLocalProfileKey:profileKey wasLocallyInitiated:wasLocallyInitiated transaction:transaction];
    }

    OWSUserProfile *userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address transaction:transaction];

    OWSAssertDebug(userProfile);
    if (userProfile.profileKey && [userProfile.profileKey.keyData isEqual:profileKey.keyData]) {
        // Ignore redundant update.
        return;
    }

    // Whenever a user's profile key changes, we need to fetch a new
    // profile key credential for them.
    [VersionedProfiles clearProfileKeyCredentialForAddress:address transaction:transaction];

    [userProfile
        clearWithProfileKey:profileKey
        wasLocallyInitiated:wasLocallyInitiated
                transaction:transaction
                 completion:^{
                     dispatch_async(dispatch_get_main_queue(), ^{
                         [self.udManager setUnidentifiedAccessMode:UnidentifiedAccessModeUnknown address:address];
                         [self updateProfileForAddress:address];
                     });
                 }];
}

- (void)setProfileGivenName:(nullable NSString *)givenName
                 familyName:(nullable NSString *)familyName
                 forAddress:(SignalServiceAddress *)address
        wasLocallyInitiated:(BOOL)wasLocallyInitiated
                transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address transaction:transaction];
    [userProfile updateWithGivenName:givenName
                          familyName:familyName
                 wasLocallyInitiated:wasLocallyInitiated
                         transaction:transaction
                          completion:nil];

    if (address.isLocalAddress) {
        [self.localUserProfile updateWithGivenName:givenName
                                        familyName:familyName
                               wasLocallyInitiated:wasLocallyInitiated
                                       transaction:transaction
                                        completion:nil];
    }
}

- (nullable NSData *)profileKeyDataForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    return [self profileKeyForAddress:address transaction:transaction].keyData;
}

- (nullable OWSAES256Key *)profileKeyForAddress:(SignalServiceAddress *)address
                                    transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.profileKey;
}

- (nullable NSString *)givenNameForAddress:(SignalServiceAddress *)address
                               transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.givenName;
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
        [self downloadAvatarForUserProfile:userProfile];
    }

    return nil;
}

- (nullable NSData *)profileAvatarDataForAddress:(SignalServiceAddress *)address
                                     transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    if (userProfile.avatarFileName.length > 0) {
        return [self loadProfileDataWithFilename:userProfile.avatarFileName];
    }

    return nil;
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

- (nullable OWSUserProfile *)getUserProfileForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    // For "local reads", use the local user profile.
    if (address.isLocalAddress) {
        return self.localUserProfile;
    }

    return [self.userProfileReadCache getUserProfileWithAddress:address transaction:transaction];
}

- (NSString *)generateAvatarFilename
{
    return [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"jpg"];
}

- (void)downloadAvatarForUserProfile:(OWSUserProfile *)userProfile
{
    OWSAssertDebug(userProfile);

    __block OWSBackgroundTask *backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (userProfile.avatarUrlPath.length < 1) {
            OWSFailDebug(@"Malformed avatar URL: %@", userProfile.avatarUrlPath);
            return;
        }
        NSString *_Nullable avatarUrlPathAtStart = userProfile.avatarUrlPath;

        if (userProfile.profileKey.keyData.length < 1 || userProfile.avatarUrlPath.length < 1) {
            return;
        }

        OWSAES256Key *profileKeyAtStart = userProfile.profileKey;

        NSString *fileName = [self generateAvatarFilename];
        NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:fileName];

        @synchronized(self.currentAvatarDownloads)
        {
            if ([self.currentAvatarDownloads containsObject:userProfile.address]) {
                // Download already in flight; ignore.
                return;
            }
            [self.currentAvatarDownloads addObject:userProfile.address];
        }

        OWSLogVerbose(@"downloading profile avatar: %@", userProfile.uniqueId);

        NSString *tempDirectory = OWSTemporaryDirectory();
        NSString *tempFilePath = [tempDirectory stringByAppendingPathComponent:fileName];

        void (^completionHandler)(NSURLResponse *_Nonnull, NSURL *_Nullable, NSError *_Nullable) = ^(
            NSURLResponse *_Nonnull response, NSURL *_Nullable filePathParam, NSError *_Nullable error) {
            // Ensure disk IO and decryption occurs off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *_Nullable encryptedData = (error ? nil : [NSData dataWithContentsOfFile:tempFilePath]);
                NSData *_Nullable decryptedData
                    = (!encryptedData ? nil : [self decryptProfileData:encryptedData profileKey:profileKeyAtStart]);
                UIImage *_Nullable image = nil;
                if (decryptedData) {
                    BOOL success = [decryptedData writeToFile:filePath atomically:YES];
                    if (success) {
                        image = [UIImage imageWithContentsOfFile:filePath];
                    }
                }

                @synchronized(self.currentAvatarDownloads)
                {
                    [self.currentAvatarDownloads removeObject:userProfile.address];
                }

                __block OWSUserProfile *latestUserProfile;
                [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                    latestUserProfile =
                        [OWSUserProfile getOrBuildUserProfileForAddress:userProfile.address transaction:transaction];
                }];

                if (latestUserProfile.profileKey.keyData.length < 1
                    || ![latestUserProfile.profileKey isEqual:userProfile.profileKey]) {
                    OWSLogWarn(@"Ignoring avatar download for obsolete user profile.");
                } else if (![avatarUrlPathAtStart isEqualToString:latestUserProfile.avatarUrlPath]) {
                    OWSLogInfo(@"avatar url has changed during download");
                    if (latestUserProfile.avatarUrlPath.length > 0) {
                        [self downloadAvatarForUserProfile:latestUserProfile];
                    }
                } else if (error) {
                    if ([response isKindOfClass:NSHTTPURLResponse.class]
                        && ((NSHTTPURLResponse *)response).statusCode == 403) {
                        OWSLogInfo(@"no avatar for: %@", userProfile.address);
                    } else {
                        OWSLogError(@"avatar download for %@ failed with error: %@", userProfile.address, error);
                    }
                } else if (!encryptedData) {
                    OWSLogError(@"avatar encrypted data for %@ could not be read.", userProfile.address);
                } else if (!decryptedData) {
                    OWSLogError(@"avatar data for %@ could not be decrypted.", userProfile.address);
                } else if (!image) {
                    OWSLogError(@"avatar image for %@ could not be loaded with error: %@", userProfile.address, error);
                } else {
                    [self updateProfileAvatarCache:image filename:fileName];

                    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                        [latestUserProfile updateWithAvatarFileName:fileName transaction:transaction];

                        // If we're updating the profile that corresponds to our local number,
                        // update the local profile as well.
                        if (userProfile.address.isLocalAddress) {
                            OWSUserProfile *localUserProfile = self.localUserProfile;
                            OWSAssertDebug(localUserProfile);

                            [localUserProfile updateWithAvatarFileName:fileName transaction:transaction];
                        }
                    }];
                }

                OWSAssertDebug(backgroundTask);
                backgroundTask = nil;
            });
        };

        NSURL *avatarUrl = [NSURL URLWithString:userProfile.avatarUrlPath relativeToURL:self.avatarHTTPManager.baseURL];
        NSError *serializationError;
        NSMutableURLRequest *request =
            [self.avatarHTTPManager.requestSerializer requestWithMethod:@"GET"
                                                              URLString:avatarUrl.absoluteString
                                                             parameters:nil
                                                                  error:&serializationError];
        if (serializationError) {
            OWSFailDebug(@"serializationError: %@", serializationError);
            return;
        }

        __block NSURLSessionDownloadTask *downloadTask = [self.avatarHTTPManager downloadTaskWithRequest:request
            progress:^(NSProgress *_Nonnull downloadProgress) {
                OWSLogVerbose(@"Downloading avatar for %@ %f", userProfile.address, downloadProgress.fractionCompleted);
            }
            destination:^NSURL *_Nonnull(NSURL *_Nonnull targetPath, NSURLResponse *_Nonnull response) {
                return [NSURL fileURLWithPath:tempFilePath];
            }
            completionHandler:completionHandler];
        [downloadTask resume];
    });
}

- (void)updateProfileForAddress:(SignalServiceAddress *)address
           profileNameEncrypted:(nullable NSData *)profileNameEncrypted
                       username:(nullable NSString *)username
                  avatarUrlPath:(nullable NSString *)avatarUrlPath
{
    OWSAssertDebug(address.isValid);

    OWSLogDebug(@"update profile for: %@ name: %@ avatar: %@", address, profileNameEncrypted, avatarUrlPath);

    // Ensure decryption, etc. off main thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OWSUserProfile *localUserProfile = self.localUserProfile;
        OWSAssertDebug(localUserProfile);

        __block OWSUserProfile *userProfile;
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address transaction:transaction];

            // If we're updating the profile that corresponds to our local number,
            // make sure we're using the latest key.
            if (address.isLocalAddress) {
                [userProfile updateWithProfileKey:self.localUserProfile.profileKey
                              wasLocallyInitiated:YES
                                      transaction:transaction
                                       completion:nil];
            }

            if (!userProfile.profileKey) {
                [userProfile updateWithUsername:username transaction:transaction];
                return;
            }

            NSPersonNameComponents *_Nullable profileNameComponents = nil;

            if (profileNameEncrypted.length > 0) {
                // Decryption is slightly expensive to do inside this write transaction.
                profileNameComponents = [self decryptProfileNameData:profileNameEncrypted
                                                          profileKey:userProfile.profileKey];
            }

            [userProfile updateWithGivenName:profileNameComponents.givenName
                                  familyName:profileNameComponents.familyName
                                    username:username
                               avatarUrlPath:avatarUrlPath
                                 transaction:transaction
                                  completion:nil];

            if (userProfile.avatarFileName.length > 0) {
                NSString *path = [OWSUserProfile profileAvatarFilepathWithFilename:userProfile.avatarFileName];
                if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
                    OWSLogError(@"downloaded file is missing for profile: %@", userProfile.address);
                    [userProfile updateWithAvatarFileName:nil transaction:transaction];
                }
            }

            // If we're updating the profile that corresponds to our local number,
            // update the local profile as well.
            if (address.isLocalAddress) {
                [localUserProfile updateWithGivenName:profileNameComponents.givenName
                                           familyName:profileNameComponents.familyName
                                             username:username
                                        avatarUrlPath:avatarUrlPath
                                          transaction:transaction
                                           completion:nil];

                if (![NSObject isNullableObject:userProfile.avatarFileName equalTo:localUserProfile.avatarFileName]) {
                    OWSLogError(@"Converging out-of-sync local profile avatar.");
                    [localUserProfile updateWithAvatarFileName:userProfile.avatarFileName transaction:transaction];
                }
            }
        }];

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

    NSData *nameData = [profileName dataUsingEncoding:NSUTF8StringEncoding];
    return nameData.length > kOWSProfileManager_NameDataLength;
}

#pragma mark - Avatar Disk Cache

- (nullable NSData *)loadProfileDataWithFilename:(NSString *)filename
{
    OWSAssertDebug(filename.length > 0);

    NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:filename];
    return [NSData dataWithContentsOfFile:filePath];
}

- (nullable UIImage *)loadProfileAvatarWithFilename:(NSString *)filename
{
    if (filename.length == 0) {
        return nil;
    }

    UIImage *_Nullable image = nil;
    @synchronized(self.profileAvatarImageCache)
    {
        image = [self.profileAvatarImageCache objectForKey:filename];
    }
    if (image) {
        return image;
    }

    NSData *data = [self loadProfileDataWithFilename:filename];
    if (![data ows_isValidImage]) {
        return nil;
    }
    image = [UIImage imageWithData:data];
    [self updateProfileAvatarCache:image filename:filename];
    return image;
}

- (void)updateProfileAvatarCache:(nullable UIImage *)image filename:(NSString *)filename
{
    OWSAssertDebug(filename.length > 0);

    @synchronized(self.profileAvatarImageCache)
    {
        if (image) {
            [self.profileAvatarImageCache setObject:image forKey:filename];
        } else {
            [self.profileAvatarImageCache removeObjectForKey:filename];
        }
    }
}

#pragma mark - User Interface

- (void)presentAddThreadToProfileWhitelist:(TSThread *)thread
                        fromViewController:(UIViewController *)fromViewController
                                   success:(void (^)(void))successHandler
{
    OWSAssertIsOnMainThread();

    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:nil message:nil];

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
        [OWSProfileManager.sharedManager addThreadToProfileWhitelist:thread];
        return;
    }

    // MJK TODO - should be safe to remove this senderTimestamp
    OWSProfileKeyMessage *message = [[OWSProfileKeyMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                           inThread:thread];
    [OWSProfileManager.sharedManager addThreadToProfileWhitelist:thread];

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
    }];
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    // TODO: Sync if necessary.

    [OWSProfileManager updateProfileOnServiceIfNecessaryObjc];
}

- (void)reachabilityChanged:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [OWSProfileManager updateProfileOnServiceIfNecessaryObjc];
}

- (void)blockListDidChange:(NSNotification *)notification {
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [self rotateLocalProfileKeyIfNecessary];
    }];
}

#pragma mark - Clean Up

+ (NSSet<NSString *> *)allProfileAvatarFilePathsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [OWSUserProfile allProfileAvatarFilePathsWithTransaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
