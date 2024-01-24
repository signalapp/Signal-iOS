//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSProfileManager.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/HTTPUtils.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/NSData+Image.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/OWSProfileKeyMessage.h>
#import <SignalServiceKit/OWSUpload.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/UIImage+OWS.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kOWSProfileManager_MaxAvatarDiameterPixels = 1024;
NSString *const kNSNotificationKey_UserProfileWriter = @"kNSNotificationKey_UserProfileWriter";

@interface OWSProfileManager ()

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) OWSUserProfile *localUserProfile;

@property (nonatomic, readonly) id<RecipientHidingManager> recipientHidingManager;

@end

#pragma mark -

@implementation OWSProfileSnapshot

- (instancetype)initWithGivenName:(nullable NSString *)givenName
                       familyName:(nullable NSString *)familyName
                         fullName:(nullable NSString *)fullName
                              bio:(nullable NSString *)bio
                         bioEmoji:(nullable NSString *)bioEmoji
                       avatarData:(nullable NSData *)avatarData
                 profileBadgeInfo:(nullable NSArray<OWSUserProfileBadgeInfo *> *)badgeArray
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
    _avatarData = avatarData;
    _profileBadgeInfo = [badgeArray copy];

    return self;
}

@end

#pragma mark -

// Access to most state should happen while synchronized on the profile manager.
// Writes should happen off the main thread, wherever possible.
@implementation OWSProfileManager

@synthesize localUserProfile = _localUserProfile;

- (instancetype)initWithDatabaseStorage:(SDSDatabaseStorage *)databaseStorage
                            swiftValues:(OWSProfileManagerSwiftValues *)swiftValues
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertIsOnMainThread();
    OWSAssertDebug(databaseStorage);

    _whitelistedPhoneNumbersStore =
        [[SDSKeyValueStore alloc] initWithCollection:@"kOWSProfileManager_UserWhitelistCollection"];
    _whitelistedServiceIdsStore =
        [[SDSKeyValueStore alloc] initWithCollection:@"kOWSProfileManager_UserUUIDWhitelistCollection"];
    _whitelistedGroupsStore =
        [[SDSKeyValueStore alloc] initWithCollection:@"kOWSProfileManager_GroupWhitelistCollection"];
    _settingsStore = [[SDSKeyValueStore alloc] initWithCollection:@"kOWSProfileManager_SettingsStore"];
    _metadataStore = [[SDSKeyValueStore alloc] initWithCollection:@"kOWSProfileManager_Metadata"];
    _badgeStore = [[BadgeStore alloc] init];
    _swiftValues = swiftValues;

    OWSSingletonAssert();

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        if (CurrentAppContext().isMainApp && [TSAccountManagerObjcBridge isRegisteredWithMaybeTransaction]) {
            [self logLocalAvatarStatus];
        }
    });

    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{
        if ([TSAccountManagerObjcBridge isRegisteredPrimaryDeviceWithMaybeTransaction]) {
            [self rotateLocalProfileKeyIfNecessary];
        }

        [self updateProfileOnServiceIfNecessaryWithAuthedAccount:AuthedAccount.implicit];
        [OWSProfileManager updateStorageServiceIfNecessary];
    });

    [self observeNotifications];

    return self;
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
                                                 name:BlockingManager.blockListDidChange
                                               object:nil];
}

#pragma mark -

- (void)logLocalAvatarStatus
{
    OWSAssertDebug(CurrentAppContext().isMainApp);
    OWSAssertDebug(!CurrentAppContext().isRunningTests);
    OWSAssertDebug([TSAccountManagerObjcBridge isRegisteredWithMaybeTransaction]);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self logLocalAvatarStatus:self.localUserProfile label:@"cached copy"];

        __block OWSUserProfile *_Nullable localUserProfile;
        [self.databaseStorage
            readWithBlock:^(SDSAnyReadTransaction *transaction) {
                localUserProfile = [OWSUserProfile getUserProfileFor:OWSUserProfile.localProfileAddress
                                                         transaction:transaction];
            }
                     file:__FILE__
                 function:__FUNCTION__
                     line:__LINE__];
        [self logLocalAvatarStatus:localUserProfile label:@"database copy"];
    });
}

- (void)logLocalAvatarStatus:(OWSUserProfile *_Nullable)localUserProfile label:(NSString *)label
{
    if (localUserProfile == nil) {
        OWSFailDebug(@"Missing local user profile: %@.", label);
        return;
    }
    BOOL hasAvatarFileOnDisk = NO;
    if (localUserProfile.avatarFileName.length > 0) {
        NSString *filePath = [OWSUserProfile profileAvatarFilePathFor:localUserProfile.avatarFileName];
        hasAvatarFileOnDisk = [OWSFileSystem fileOrFolderExistsAtPath:filePath];
    }

    if (SSKDebugFlags.internalLogging) {
        OWSLogInfo(
            @"Local user profile (%@). address: %@, avatarUrlPath: %@, avatarFileName: %@, hasAvatarFileOnDisk: %d",
            label,
            localUserProfile.internalAddress,
            localUserProfile.avatarUrlPath,
            localUserProfile.avatarFileName,
            hasAvatarFileOnDisk);
    } else {
        OWSLogInfo(
            @"Local user profile (%@). address: %@, avatarUrlPath: %d, avatarFileName: %d, hasAvatarFileOnDisk: %d",
            label,
            localUserProfile.internalAddress,
            localUserProfile.avatarUrlPath.length > 0,
            localUserProfile.avatarFileName.length > 0,
            hasAvatarFileOnDisk);
    }
}

#pragma mark - User Profile Accessor

- (void)warmCaches
{
    OWSAssertDebug(GRDBSchemaMigrator.areMigrationsComplete);

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
    __unused OWSUserProfile *profile = [self localUserProfileWithAuthedAccount:AuthedAccount.implicit];
}

#pragma mark - Local Profile

- (OWSUserProfile *)localUserProfileWithAuthedAccount:(AuthedAccount *)authedAccount
{
    OWSAssertDebug(GRDBSchemaMigrator.areMigrationsComplete);
    @synchronized(self) {
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
        localUserProfile = [self getLocalUserProfileWithTransaction:transaction];
    } file:__FILE__ function:__FUNCTION__ line:__LINE__];
    if (localUserProfile != nil) {
        return [localUserProfile shallowCopy];
    }

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        localUserProfile = [OWSUserProfile getOrBuildUserProfileForAddress:OWSUserProfile.localProfileAddress
                                                             authedAccount:authedAccount
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
    BOOL migrationsAreComplete = GRDBSchemaMigrator.areMigrationsComplete;
    @synchronized(self) {
        if (_localUserProfile && migrationsAreComplete) {
            OWSAssertDebug(_localUserProfile.profileKey);
            return [_localUserProfile shallowCopy];
        }
    }

    OWSUserProfile *_Nullable localUserProfile = [OWSUserProfile getUserProfileFor:OWSUserProfile.localProfileAddress
                                                                       transaction:transaction];

    if (migrationsAreComplete) {
        @synchronized(self) {
            _localUserProfile = localUserProfile;
        }
    }
    return [localUserProfile shallowCopy];
}

- (void)localProfileWasUpdated:(OWSUserProfile *)localUserProfile
{
    OWSAssertDebug(GRDBSchemaMigrator.areMigrationsComplete);

    @synchronized(self) {
        _localUserProfile = [localUserProfile shallowCopy];
    }
}

- (BOOL)localProfileExistsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [OWSUserProfile doesLocalProfileExistWithTransaction:transaction];
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
    return self.localUserProfile.filteredGivenName;
}

- (nullable NSString *)localFamilyName
{
    return self.localUserProfile.filteredFamilyName;
}

- (nullable NSString *)localFullName
{
    return self.localUserProfile.filteredFullName;
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

- (nullable NSArray<OWSUserProfileBadgeInfo *> *)localProfileBadgeInfo
{
    return self.localUserProfile.badges;
}

- (BOOL)localProfileIsPniCapable
{
    return self.localUserProfile.isPniCapable;
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
    return [[OWSProfileSnapshot alloc] initWithGivenName:userProfile.filteredGivenName
                                              familyName:userProfile.filteredFamilyName
                                                fullName:userProfile.filteredFullName
                                                     bio:userProfile.bio
                                                bioEmoji:userProfile.bioEmoji
                                              avatarData:avatarData
                                        profileBadgeInfo:userProfile.badges];
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

- (void)fetchProfileForAddress:(SignalServiceAddress *)address authedAccount:(AuthedAccount *)authedAccount
{
    [ProfileFetcherJob fetchProfileWithAddress:address ignoreThrottling:YES authedAccount:authedAccount];
}

- (void)reuploadLocalProfileWithAuthedAccount:(AuthedAccount *)authedAccount
{
    [self reuploadLocalProfileWithSneakyTransactionWithAuthedAccount:authedAccount]
        .done(^(id value) { OWSLogInfo(@"Done."); })
        .catch(^(NSError *error) { OWSFailDebugUnlessNetworkFailure(error); });
}

#pragma mark - Profile Key Rotation

- (NSString *)groupKeyForGroupId:(NSData *)groupId
{
    return [groupId hexadecimalString];
}

- (void)forceRotateLocalProfileKeyForGroupDepartureWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [self forceRotateLocalProfileKeyForGroupDepartureObjcWithTx:transaction];
}

#pragma mark - Profile Whitelist

- (void)clearProfileWhitelist
{
    OWSLogWarn(@"Clearing the profile whitelist.");

    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.whitelistedPhoneNumbersStore removeAllWithTransaction:transaction];
        [self.whitelistedServiceIdsStore removeAllWithTransaction:transaction];
        [self.whitelistedGroupsStore removeAllWithTransaction:transaction];
        
        OWSAssertDebug(0 == [self.whitelistedPhoneNumbersStore numberOfKeysWithTransaction:transaction]);
        OWSAssertDebug(0 == [self.whitelistedServiceIdsStore numberOfKeysWithTransaction:transaction]);
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
            self.whitelistedServiceIdsStore.collection,
            (unsigned long)[self.whitelistedServiceIdsStore numberOfKeysWithTransaction:transaction]);
        for (NSString *key in [self.whitelistedServiceIdsStore allKeysWithTransaction:transaction]) {
            OWSLogError(@"\t profile whitelist user service id: %@", key);
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
        [userProfile clearProfileWithProfileKey:[OWSAES256Key generateRandomKey]
                              userProfileWriter:UserProfileWriter_Debugging
                                  authedAccount:AuthedAccount.implicit
                                    transaction:transaction
                                     completion:nil];
    });
    [AccountAttributesUpdaterObjcBridge updateAccountAttributes].catch(
        ^(NSError *error) { OWSLogError(@"Error: %@.", error); });
}

- (void)setLocalProfileKey:(OWSAES256Key *)key
         userProfileWriter:(UserProfileWriter)userProfileWriter
             authedAccount:(AuthedAccount *)authedAccount
               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(GRDBSchemaMigrator.areMigrationsComplete);

    OWSUserProfile *localUserProfile;
    
    @synchronized(self)
    {
        // If it didn't exist, create it in a safe way as accessing the property
        // will do a sneaky transaction.
        if (!_localUserProfile) {
            // We assert on the ivar directly here, as we want this to be cached already
            // by the time this method is called. If it's not, we've changed our caching
            // logic and should re-evaluate this method.
            OWSFailDebug(@"Missing local profile when setting key.");

            localUserProfile = [OWSUserProfile getOrBuildUserProfileForAddress:OWSUserProfile.localProfileAddress
                                                                 authedAccount:authedAccount
                                                                   transaction:transaction];

            _localUserProfile = localUserProfile;
        } else {
            localUserProfile = _localUserProfile;
        }
    }

    [localUserProfile updateWithProfileKey:key
                         userProfileWriter:userProfileWriter
                             authedAccount:authedAccount
                               transaction:transaction
                                completion:nil];
}

- (void)normalizeRecipientInProfileWhitelist:(SignalRecipient *)recipient tx:(SDSAnyWriteTransaction *)tx
{
    [self swift_normalizeRecipientInProfileWhitelist:recipient tx:tx];
}

- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address
                userProfileWriter:(UserProfileWriter)userProfileWriter
                      transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    [self addUsersToProfileWhitelist:@[ address ] userProfileWriter:userProfileWriter transaction:transaction];
}

- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses
                 userProfileWriter:(UserProfileWriter)userProfileWriter
                       transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(addresses);
    OWSAssertDebug(transaction);

    NSSet<SignalServiceAddress *> *addressesToAdd = [self addressesNotBlockedOrInWhitelist:addresses
                                                                               transaction:transaction];
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
                                                        transaction:(SDSAnyReadTransaction *)tx
{
    OWSAssertDebug(addresses);

    NSMutableSet<SignalServiceAddress *> *notBlockedOrInWhitelist = [NSMutableSet new];

    for (SignalServiceAddress *address in addresses) {
        // If the address is blocked, we don't want to include it
        if ([self.blockingManager isAddressBlocked:address transaction:tx] ||
            [RecipientHidingManagerObjcBridge isHiddenAddress:address tx:tx]) {
            continue;
        }

        if (![self isAddressInWhitelist:address tx:tx]) {
            [notBlockedOrInWhitelist addObject:address];
        }
    }

    return [notBlockedOrInWhitelist copy];
}

- (NSSet<SignalServiceAddress *> *)addressesInWhitelist:(NSArray<SignalServiceAddress *> *)addresses
                                            transaction:(SDSAnyReadTransaction *)tx
{
    OWSAssertDebug(addresses);

    NSMutableSet<SignalServiceAddress *> *whitelistedAddresses = [NSMutableSet new];

    for (SignalServiceAddress *address in addresses) {
        if ([self isAddressInWhitelist:address tx:tx]) {
            [whitelistedAddresses addObject:address];
        }
    }

    return [whitelistedAddresses copy];
}

- (BOOL)isAddressInWhitelist:(SignalServiceAddress *)address tx:(SDSAnyReadTransaction *)tx
{
    if (address.serviceIdUppercaseString) {
        if ([self.whitelistedServiceIdsStore hasValueForKey:address.serviceIdUppercaseString transaction:tx]) {
            return YES;
        }
    }

    if (address.phoneNumber) {
        if ([self.whitelistedPhoneNumbersStore hasValueForKey:address.phoneNumber transaction:tx]) {
            return YES;
        }
    }

    return NO;
}

- (void)removeConfirmedWhitelistedAddresses:(NSSet<SignalServiceAddress *> *)addressesToRemove
                          userProfileWriter:(UserProfileWriter)userProfileWriter
                                transaction:(SDSAnyWriteTransaction *)tx
{
    if (addressesToRemove.count == 0) {
        // Do nothing.
        return;
    }

    for (SignalServiceAddress *address in addressesToRemove) {
        // Historically we put both the ACI and phone number into their respective
        // stores. We currently save only the best identifier, but we should still
        // try and remove both to handle these historical cases.
        if (address.serviceIdUppercaseString) {
            [self.whitelistedServiceIdsStore removeValueForKey:address.serviceIdUppercaseString transaction:tx];
        }
        if (address.phoneNumber) {
            [self.whitelistedPhoneNumbersStore removeValueForKey:address.phoneNumber transaction:tx];
        }

        TSThread *_Nullable thread = [TSContactThread getThreadWithContactAddress:address transaction:tx];
        if (thread) {
            [self.databaseStorage touchThread:thread shouldReindex:NO transaction:tx];
        }
    }

    [tx addSyncCompletion:^{
        // Mark the removed whitelisted addresses for update
        if ([OWSUserProfile shouldUpdateStorageServiceForUserProfileWriter:userProfileWriter]) {
            [self.storageServiceManagerObjc recordPendingUpdatesWithUpdatedAddresses:addressesToRemove.allObjects];
        }

        for (SignalServiceAddress *address in addressesToRemove) {
            [[NSNotificationCenter defaultCenter]
                postNotificationNameAsync:UserProfileNotifications.profileWhitelistDidChange
                                   object:nil
                                 userInfo:@{
                                     UserProfileNotifications.profileAddressKey : address,
                                     kNSNotificationKey_UserProfileWriter : @(userProfileWriter),
                                 }];
        }
    }];
}

- (void)addConfirmedUnwhitelistedAddresses:(NSSet<SignalServiceAddress *> *)addressesToAdd
                         userProfileWriter:(UserProfileWriter)userProfileWriter
                               transaction:(SDSAnyWriteTransaction *)tx
{
    if (addressesToAdd.count == 0) {
        // Do nothing.
        return;
    }

    for (SignalServiceAddress *address in addressesToAdd) {
        ServiceIdObjC *serviceId = address.serviceIdObjC;

        if ([serviceId isKindOfClass:[AciObjC class]]) {
            [self.whitelistedServiceIdsStore setBool:YES key:serviceId.serviceIdUppercaseString transaction:tx];
        } else if (address.phoneNumber) {
            [self.whitelistedPhoneNumbersStore setBool:YES key:address.phoneNumber transaction:tx];
        } else if ([serviceId isKindOfClass:[PniObjC class]]) {
            [self.whitelistedServiceIdsStore setBool:YES key:serviceId.serviceIdUppercaseString transaction:tx];
        }

        TSThread *_Nullable thread = [TSContactThread getThreadWithContactAddress:address transaction:tx];
        if (thread) {
            [self.databaseStorage touchThread:thread shouldReindex:NO transaction:tx];
        }
    }

    [tx addSyncCompletion:^{
        // Mark the new whitelisted addresses for update
        if ([OWSUserProfile shouldUpdateStorageServiceForUserProfileWriter:userProfileWriter]) {
            [self.storageServiceManagerObjc recordPendingUpdatesWithUpdatedAddresses:addressesToAdd.allObjects];
        }

        for (SignalServiceAddress *address in addressesToAdd) {
            [[NSNotificationCenter defaultCenter]
                postNotificationNameAsync:UserProfileNotifications.profileWhitelistDidChange
                                   object:nil
                                 userInfo:@{
                                     UserProfileNotifications.profileAddressKey : address,
                                     kNSNotificationKey_UserProfileWriter : @(userProfileWriter),
                                 }];
        }
    }];
}

- (BOOL)isUserInProfileWhitelist:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)tx
{
    OWSAssertDebug(address.isValid);

    if ([self.blockingManager isAddressBlocked:address transaction:tx]
        || ([RecipientHidingManagerObjcBridge isHiddenAddress:address tx:tx])) {
        return NO;
    }

    return [self isAddressInWhitelist:address tx:tx];
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
        if ([OWSUserProfile shouldUpdateStorageServiceForUserProfileWriter:userProfileWriter]) {
            [self recordPendingUpdatesForStorageServiceWithGroupId:groupId];
        }

        [[NSNotificationCenter defaultCenter]
            postNotificationNameAsync:UserProfileNotifications.profileWhitelistDidChange
                               object:nil
                             userInfo:@{
                                 UserProfileNotifications.profileGroupIdKey : groupId,
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
        if ([OWSUserProfile shouldUpdateStorageServiceForUserProfileWriter:userProfileWriter]) {
            [self recordPendingUpdatesForStorageServiceWithGroupId:groupId];
        }

        [[NSNotificationCenter defaultCenter]
            postNotificationNameAsync:UserProfileNotifications.profileWhitelistDidChange
                               object:nil
                             userInfo:@{
                                 UserProfileNotifications.profileGroupIdKey : groupId,
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

        [self.storageServiceManagerObjc recordPendingUpdatesWithGroupModel:groupThread.groupModel];
    }];
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
    } else if ([thread isKindOfClass:[TSContactThread class]]) {
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
    if ([self.blockingManager isGroupIdBlocked:groupId transaction:transaction]) {
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
    } else if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        return [self isUserInProfileWhitelist:contactThread.contactAddress transaction:transaction];
    } else {
        return NO;
    }
}

#pragma mark - Other User's Profiles

- (void)setProfileKeyData:(NSData *)profileKeyData
               forAddress:(SignalServiceAddress *)address
        userProfileWriter:(UserProfileWriter)userProfileWriter
            authedAccount:(AuthedAccount *)authedAccount
              transaction:(SDSAnyWriteTransaction *)transaction
{
    [self setProfileKeyData:profileKeyData
                 forAddress:address
        onlyFillInIfMissing:NO
          userProfileWriter:userProfileWriter
              authedAccount:authedAccount
                transaction:transaction];
}

- (void)fillInProfileKeysForAllProfileKeys:(NSDictionary<SignalServiceAddress *, NSData *> *)allProfileKeys
                  authoritativeProfileKeys:(NSDictionary<SignalServiceAddress *, NSData *> *)authoritativeProfileKeys
                         userProfileWriter:(UserProfileWriter)userProfileWriter
                             authedAccount:(AuthedAccount *)authedAccount
{
    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        for (SignalServiceAddress *address in authoritativeProfileKeys) {
            NSData *_Nullable profileKeyData = allProfileKeys[address];
            if (profileKeyData == nil) {
                OWSFailDebug(@"Missing profileKeyData.");
                continue;
            }
            [self setProfileKeyData:profileKeyData
                         forAddress:address
                onlyFillInIfMissing:NO
                  userProfileWriter:userProfileWriter
                      authedAccount:authedAccount
                        transaction:transaction];
        }

        for (SignalServiceAddress *address in allProfileKeys) {
            if (authoritativeProfileKeys[address] != nil) {
                // We already stored this profile key as an
                // authoritative one.
                continue;
            }
            NSData *_Nullable profileKeyData = allProfileKeys[address];
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
                      authedAccount:authedAccount
                        transaction:transaction];
        }
    });
}

- (void)setProfileGivenName:(nullable NSString *)givenName
                 familyName:(nullable NSString *)familyName
                 forAddress:(SignalServiceAddress *)addressParam
          userProfileWriter:(UserProfileWriter)userProfileWriter
              authedAccount:(AuthedAccount *)authedAccount
                transaction:(SDSAnyWriteTransaction *)transaction
{
    SignalServiceAddress *address = [OWSUserProfile internalAddressFor:addressParam];
    if ([authedAccount isAddressForLocalUser:address]) {
        address = [OWSUserProfile localProfileAddress];
    }
    OWSAssertDebug(address.isValid);

    OWSUserProfile *userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address
                                                                    authedAccount:authedAccount
                                                                      transaction:transaction];
    [userProfile updateWithGivenName:givenName
                          familyName:familyName
                   userProfileWriter:userProfileWriter
                       authedAccount:authedAccount
                         transaction:transaction
                          completion:nil];
}

- (void)setProfileGivenName:(nullable NSString *)givenName
                 familyName:(nullable NSString *)familyName
              avatarUrlPath:(nullable NSString *)avatarUrlPath
                 forAddress:(SignalServiceAddress *)addressParam
          userProfileWriter:(UserProfileWriter)userProfileWriter
              authedAccount:(AuthedAccount *)authedAccount
                transaction:(SDSAnyWriteTransaction *)transaction
{
    SignalServiceAddress *address = [OWSUserProfile internalAddressFor:addressParam];
    if ([authedAccount isAddressForLocalUser:address]) {
        address = [OWSUserProfile localProfileAddress];
    }
    OWSAssertDebug(address.isValid);

    OWSUserProfile *userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address
                                                                    authedAccount:authedAccount
                                                                      transaction:transaction];
    [userProfile updateWithGivenName:givenName
                          familyName:familyName
                       avatarUrlPath:avatarUrlPath
                   userProfileWriter:userProfileWriter
                       authedAccount:authedAccount
                         transaction:transaction
                          completion:nil];

    if (userProfile.avatarUrlPath.length > 0 && userProfile.avatarFileName.length < 1) {
        [self downloadAndDecryptAvatarIfNeededObjCWithUserProfile:userProfile authedAccount:authedAccount];
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

- (nullable NSString *)unfilteredGivenNameForAddress:(SignalServiceAddress *)address
                                         transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.givenName;
}

- (nullable NSString *)givenNameForAddress:(SignalServiceAddress *)address
                               transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.filteredGivenName;
}

- (nullable NSString *)unfilteredFamilyNameForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.familyName;
}


- (nullable NSString *)familyNameForAddress:(SignalServiceAddress *)address
                                transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.filteredFamilyName;
}

- (nullable NSPersonNameComponents *)nameComponentsForProfileWithAddress:(SignalServiceAddress *)address
                                                             transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.filteredNameComponents;
}

- (nullable NSString *)fullNameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.filteredFullName;
}

- (nullable UIImage *)profileAvatarForAddress:(SignalServiceAddress *)address
                            downloadIfMissing:(BOOL)downloadIfMissing
                                authedAccount:(AuthedAccount *)authedAccount
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    if (userProfile.avatarFileName.length > 0) {
        return [self loadProfileAvatarWithFilename:userProfile.avatarFileName];
    }

    if (downloadIfMissing && (userProfile.avatarUrlPath.length > 0)) {
        // Try to fill in missing avatar.
        [self downloadAndDecryptAvatarIfNeededObjCWithUserProfile:userProfile authedAccount:authedAccount];
    }

    return nil;
}

- (BOOL)hasProfileAvatarData:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];
    if (userProfile.avatarFileName.length < 1) {
        return NO;
    } else {
        NSString *filePath = [OWSUserProfile profileAvatarFilePathFor:userProfile.avatarFileName];
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
    } else {
        OWSLogWarn(@"Failed to get user profile to generate avatar data for %@. Has profile? %i. Has filename? %i",
            address,
            userProfile != nil,
            userProfile.avatarFileName != nil);
    }

    return nil;
}

- (nullable NSString *)profileAvatarURLPathForAddress:(SignalServiceAddress *)address
                                    downloadIfMissing:(BOOL)downloadIfMissing
                                        authedAccount:(AuthedAccount *)authedAccount
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    if (downloadIfMissing && userProfile.avatarUrlPath.length > 0 && userProfile.avatarFileName.length == 0) {
        // Try to fill in missing avatar.
        [self downloadAndDecryptAvatarIfNeededObjCWithUserProfile:userProfile authedAccount:authedAccount];
    }

    return userProfile.avatarUrlPath;
}

- (NSArray<SignalServiceAddress *> *)allWhitelistedRegisteredAddressesWithTx:(SDSAnyReadTransaction *)tx
{
    return [self objc_allWhitelistedRegisteredAddressesWithTx:tx];
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
    SignalServiceAddress *address = [OWSUserProfile internalAddressFor:addressParam];
    OWSAssertDebug(address.isValid);

    // For "local reads", use the local user profile.
    if ([OWSUserProfile isLocalProfileAddress:address]) {
        return [self getLocalUserProfileWithTransaction:transaction];
    }

    return [self.modelReadCaches.userProfileReadCache getUserProfileWithAddress:address transaction:transaction];
}

- (nullable NSURL *)writeAvatarDataToFile:(NSData *)avatarData
{
    OWSAssertDebug(avatarData.length > 0);
    if (![avatarData ows_isValidImage]) {
        OWSFailDebug(@"Invalid avatar format");
        return nil;
    }

    NSString *filename = [self generateAvatarFilename];
    NSString *avatarPath = [OWSUserProfile profileAvatarFilePathFor:filename];
    NSURL *avatarUrl = [NSURL fileURLWithPath:avatarPath];
    if (!avatarUrl) {
        OWSFailDebug(@"Invalid URL for avatarPath %@", avatarPath);
        return nil;
    }

    NSError *error = nil;
    BOOL success = [avatarData writeToURL:avatarUrl options:NSDataWritingAtomic error:&error];
    if (!success || error) {
        OWSFailDebug(@"Failed write to url %@: %@", avatarUrl, error);
        return nil;
    }

    // We were double checking that a UIImage could be instantiated from this file before recording the
    // avatar to the profile. That behavior is preserved here:
    UIImage *_Nullable avatarImage = [UIImage imageWithContentsOfFile:avatarUrl.path];
    if (avatarImage) {
        return avatarUrl;
    } else {
        OWSFailDebug(@"Failed to open avatar image written to disk");
        return nil;
    }
}

- (NSString *)generateAvatarFilename
{
    return [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"jpg"];
}

- (void)updateProfileForAddress:(SignalServiceAddress *)addressParam
                      givenName:(nullable NSString *)givenName
                     familyName:(nullable NSString *)familyName
                            bio:(nullable NSString *)bio
                       bioEmoji:(nullable NSString *)bioEmoji
                  avatarUrlPath:(nullable NSString *)avatarUrlPath
          optionalAvatarFileUrl:(nullable NSURL *)optionalAvatarFileUrl
                  profileBadges:(nullable NSArray<OWSUserProfileBadgeInfo *> *)profileBadges
                  lastFetchDate:(NSDate *)lastFetchDate
                   isPniCapable:(BOOL)isPniCapable
              userProfileWriter:(UserProfileWriter)userProfileWriter
                  authedAccount:(AuthedAccount *)authedAccount
                    transaction:(SDSAnyWriteTransaction *)writeTx
{
    SignalServiceAddress *address = [OWSUserProfile internalAddressFor:addressParam];
    if ([authedAccount isAddressForLocalUser:address]) {
        address = [OWSUserProfile localProfileAddress];
    }
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(NSThread.isMainThread == NO);

    OWSUserProfile *userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address
                                                                    authedAccount:authedAccount
                                                                      transaction:writeTx];
    if (!userProfile.profileKey) {
        [userProfile updateWithLastFetchDate:lastFetchDate
                                isPniCapable:isPniCapable
                           userProfileWriter:userProfileWriter
                               authedAccount:authedAccount
                                 transaction:writeTx];
    } else if (optionalAvatarFileUrl.lastPathComponent) {
        [userProfile updateWithGivenName:givenName
                              familyName:familyName
                                     bio:bio
                                bioEmoji:bioEmoji
                                  badges:profileBadges
                           avatarUrlPath:avatarUrlPath
                          avatarFileName:optionalAvatarFileUrl.lastPathComponent
                           lastFetchDate:lastFetchDate
                            isPniCapable:isPniCapable
                       userProfileWriter:userProfileWriter
                           authedAccount:authedAccount
                             transaction:writeTx
                              completion:nil];
    } else {
        [userProfile updateWithGivenName:givenName
                              familyName:familyName
                                     bio:bio
                                bioEmoji:bioEmoji
                                  badges:profileBadges
                           avatarUrlPath:avatarUrlPath
                           lastFetchDate:lastFetchDate
                            isPniCapable:isPniCapable
                       userProfileWriter:userProfileWriter
                           authedAccount:authedAccount
                             transaction:writeTx
                              completion:nil];
    }
}

#pragma mark - Avatar Disk Cache

- (nullable NSData *)loadProfileAvatarDataWithFilename:(NSString *)filename
{
    OWSAssertDebug(filename.length > 0);

    NSString *filePath = [OWSUserProfile profileAvatarFilePathFor:filename];
    NSData *_Nullable avatarData = [NSData dataWithContentsOfFile:filePath];

    if (![avatarData ows_isValidImage]) {
        OWSLogWarn(@"Failed to get valid avatar data");
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

    UIImage *_Nullable image = [UIImage imageWithData:data];
    if (image) {
        return image;
    } else {
        OWSLogWarn(@"Could not load profile avatar.");
        return nil;
    }
}

- (nullable ModelReadCacheSizeLease *)leaseCacheSize:(NSInteger)size {
    return [self.modelReadCaches.userProfileReadCache leaseCacheSize:size];
}

#pragma mark - Messaging History

- (void)didSendOrReceiveMessageFromAddress:(SignalServiceAddress *)addressParam
                             authedAccount:(AuthedAccount *)authedAccount
                               transaction:(SDSAnyWriteTransaction *)transaction
{
    if (addressParam.isLocalAddress || [authedAccount isAddressForLocalUser:addressParam]) {
        return;
    }

    SignalServiceAddress *address = [OWSUserProfile internalAddressFor:addressParam];
    OWSAssertDebug(address.isValid);

    OWSUserProfile *userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address
                                                                    authedAccount:authedAccount
                                                                      transaction:transaction];

    if (userProfile.lastMessagingDate != nil) {
        // lastMessagingDate is coarse; we don't need to track every single message
        // sent or received. It is sufficient to update it only when the value
        // changes by more than an hour.
        NSTimeInterval lastMessagingInterval = fabs(userProfile.lastMessagingDate.timeIntervalSinceNow);
        const NSTimeInterval lastMessagingResolution = 1 * kHourInterval;
        if (lastMessagingInterval < lastMessagingResolution) {
            return;
        }
    }

    [userProfile updateWithLastMessagingDate:[NSDate new]
                           userProfileWriter:UserProfileWriter_MetadataUpdate
                               authedAccount:authedAccount
                                 transaction:transaction];
}

- (void)rotateProfileKeyUponRecipientHideWithTx:(nonnull SDSAnyWriteTransaction *)tx
{
    [self rotateProfileKeyUponRecipientHideObjCWithTx:tx];
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    // TODO: Sync if necessary.

    [self updateProfileOnServiceIfNecessaryWithAuthedAccount:AuthedAccount.implicit];
}

- (void)reachabilityChanged:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateProfileOnServiceIfNecessaryWithAuthedAccount:AuthedAccount.implicit];
}

- (void)blockListDidChange:(NSNotification *)notification {
    OWSAssertIsOnMainThread();

    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{ [self rotateLocalProfileKeyIfNecessary]; });
}

#pragma mark - Clean Up

+ (NSSet<NSString *> *)allProfileAvatarFilePathsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [OWSUserProfile allProfileAvatarFilePathsWithTx:transaction];
}

@end

NS_ASSUME_NONNULL_END
