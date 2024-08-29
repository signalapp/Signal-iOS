//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSProfileManager.h"
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/NSData+OWS.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/NSString+OWS.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/OWSProfileKeyMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kOWSProfileManager_MaxAvatarDiameterPixels = 1024;
NSString *const kNSNotificationKey_UserProfileWriter = @"kNSNotificationKey_UserProfileWriter";

@interface OWSProfileManager ()

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) OWSUserProfile *localUserProfile;

@property (nonatomic, readonly) id<RecipientHidingManager> recipientHidingManager;

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
                                                 name:AppContextObjCBridge.owsApplicationDidBecomeActiveNotification
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
    __unused OWSUserProfile *profile = [self localUserProfile];
}

#pragma mark - Local Profile

- (OWSUserProfile *)localUserProfile
{
    OWSAssertDebug(GRDBSchemaMigrator.areMigrationsComplete);
    @synchronized(self) {
        if (_localUserProfile) {
            OWSAssertDebug(_localUserProfile.profileKey);
            return [_localUserProfile shallowCopy];
        }
    }

    // We create the profile outside the @synchronized block to avoid any risk
    // of deadlock. Thanks to ensureLocalProfileCached, there should be no risk
    // of races. And races should be harmless since: a)
    // getOrBuildUserProfileForInternalAddress is idempotent and b) we use the
    // "update with..." pattern.
    //
    // We first try using a read block to avoid opening a write block.
    __block OWSUserProfile *_Nullable localUserProfile;
    [self.databaseStorage
        readWithBlock:^(SDSAnyReadTransaction *transaction) {
            localUserProfile = [self getLocalUserProfileWithTransaction:transaction];
        }
                 file:__FILE__
             function:__FUNCTION__
                 line:__LINE__];
    if (localUserProfile != nil) {
        return [localUserProfile shallowCopy];
    }

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        localUserProfile =
            [OWSUserProfile getOrBuildUserProfileForLocalUserWithUserProfileWriter:UserProfileWriter_LocalUser
                                                                                tx:transaction];
        OWSAssertDebug(localUserProfile.profileKey);
    });

    @synchronized(self) {
        _localUserProfile = localUserProfile;
        return [localUserProfile shallowCopy];
    }
}

- (nullable OWSUserProfile *)getLocalUserProfileWithTransaction:(SDSAnyReadTransaction *)tx
{
    BOOL migrationsAreComplete = GRDBSchemaMigrator.areMigrationsComplete;

    if (migrationsAreComplete) {
        @synchronized(self) {
            if (_localUserProfile) {
                OWSAssertDebug(_localUserProfile.profileKey);
                return [_localUserProfile shallowCopy];
            }
        }
    }

    OWSUserProfile *localUserProfile = [OWSUserProfile getUserProfileForLocalUserWithTx:tx];

    if (migrationsAreComplete) {
        @synchronized(self) {
            _localUserProfile = localUserProfile;
            return [localUserProfile shallowCopy];
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
    OWSAssertDebug(self.localUserProfile.profileKey.keyData.length == OWSAES256Key.keyByteLength);

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

#ifdef USE_DEBUG_UI

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
                                    transaction:transaction
                                     completion:nil];
    });
    [AccountAttributesUpdaterObjcBridge updateAccountAttributes].catch(
        ^(NSError *error) { OWSLogError(@"Error: %@.", error); });
}

#endif

- (void)setLocalProfileKey:(OWSAES256Key *)key
         userProfileWriter:(UserProfileWriter)userProfileWriter
               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(GRDBSchemaMigrator.areMigrationsComplete);

    OWSUserProfile *localUserProfile;

    @synchronized(self) {
        // If it didn't exist, create it in a safe way as accessing the property
        // will do a sneaky transaction.
        if (!_localUserProfile) {
            // We assert on the ivar directly here, as we want this to be cached already
            // by the time this method is called. If it's not, we've changed our caching
            // logic and should re-evaluate this method.
            OWSFailDebug(@"Missing local profile when setting key.");
            localUserProfile =
                [OWSUserProfile getOrBuildUserProfileForLocalUserWithUserProfileWriter:UserProfileWriter_LocalUser
                                                                                    tx:transaction];

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

- (void)addThreadToProfileWhitelist:(TSThread *)thread
                  userProfileWriter:(UserProfileWriter)userProfileWriter
                        transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(thread);

    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        NSData *groupId = groupThread.groupModel.groupId;
        [self addGroupIdToProfileWhitelist:groupId userProfileWriter:userProfileWriter transaction:transaction];
    } else if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self addUserToProfileWhitelist:contactThread.contactAddress
                      userProfileWriter:userProfileWriter
                            transaction:transaction];
    }
}

- (BOOL)isGroupIdInProfileWhitelist:(NSData *)groupId transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

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

- (nullable NSString *)fullNameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.filteredFullName;
}

- (nullable UIImage *)profileAvatarForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    if (userProfile.avatarFileName.length > 0) {
        return [self loadProfileAvatarWithFilename:userProfile.avatarFileName];
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

    if (userProfile.avatarFileName.length == 0) {
        return nil;
    }

    return [self loadProfileAvatarDataWithFilename:userProfile.avatarFileName];
}

- (nullable NSString *)profileAvatarURLPathForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.avatarUrlPath;
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
    return [self _getUserProfileFor:addressParam tx:transaction];
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

- (nullable ModelReadCacheSizeLease *)leaseCacheSize:(NSInteger)size
{
    return [self.modelReadCaches.userProfileReadCache leaseCacheSize:size];
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

- (void)blockListDidChange:(NSNotification *)notification
{
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
