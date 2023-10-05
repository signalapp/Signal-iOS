//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSUserProfile.h"
#import "AppContext.h"
#import "OWSFileSystem.h"
#import "ProfileManagerProtocol.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const kNSNotificationNameProfileWhitelistDidChange = @"kNSNotificationNameProfileWhitelistDidChange";
NSNotificationName const kNSNotificationNameLocalProfileDidChange = @"kNSNotificationNameLocalProfileDidChange";
NSNotificationName const kNSNotificationNameLocalProfileKeyDidChange = @"kNSNotificationNameLocalProfileKeyDidChange";
NSNotificationName const kNSNotificationNameOtherUsersProfileDidChange
    = @"kNSNotificationNameOtherUsersProfileDidChange";

NSString *const kNSNotificationKey_ProfileAddress = @"kNSNotificationKey_ProfileAddress";
NSString *const kNSNotificationKey_ProfileGroupId = @"kNSNotificationKey_ProfileGroupId";

NSString *const kLocalProfileInvariantPhoneNumber = @"kLocalProfileUniqueId";

NSUInteger const kUserProfileSchemaVersion = 1;

BOOL shouldUpdateStorageServiceForUserProfileWriter(UserProfileWriter userProfileWriter)
{
    switch (userProfileWriter) {
        case UserProfileWriter_LocalUser:
            return YES;
        case UserProfileWriter_ProfileFetch:
            return YES;
        case UserProfileWriter_StorageService:
            return NO;
        case UserProfileWriter_SyncMessage:
            return NO;
        case UserProfileWriter_Registration:
            return YES;
        case UserProfileWriter_Linking:
            return NO;
        case UserProfileWriter_GroupState:
            return YES;
        case UserProfileWriter_Reupload:
            return YES;
        case UserProfileWriter_AvatarDownload:
            return NO;
        case UserProfileWriter_MetadataUpdate:
            return NO;
        case UserProfileWriter_Debugging:
            return NO;
        case UserProfileWriter_Tests:
            return NO;
        case UserProfileWriter_SystemContactsFetch:
            return YES;
        case UserProfileWriter_ChangePhoneNumber:
            return YES;
        case UserProfileWriter_Unknown:
            OWSCFailDebug(@"Invalid UserProfileWriter.");
            return NO;
        default:
            OWSCFailDebug(@"Invalid UserProfileWriter.");
            return NO;
    }
}

NSString *NSStringForUserProfileWriter(UserProfileWriter userProfileWriter)
{
    switch (userProfileWriter) {
        case UserProfileWriter_LocalUser:
            return @"LocalUser";
        case UserProfileWriter_ProfileFetch:
            return @"ProfileFetch";
        case UserProfileWriter_StorageService:
            return @"StorageService";
        case UserProfileWriter_SyncMessage:
            return @"SyncMessage";
        case UserProfileWriter_Registration:
            return @"Registration";
        case UserProfileWriter_Linking:
            return @"Linking";
        case UserProfileWriter_GroupState:
            return @"GroupState";
        case UserProfileWriter_Reupload:
            return @"Reupload";
        case UserProfileWriter_AvatarDownload:
            return @"AvatarDownload";
        case UserProfileWriter_MetadataUpdate:
            return @"MetadataUpdate";
        case UserProfileWriter_Debugging:
            return @"Debugging";
        case UserProfileWriter_Tests:
            return @"Tests";
        case UserProfileWriter_SystemContactsFetch:
            return @"SystemContactsFetch";
        case UserProfileWriter_ChangePhoneNumber:
            return @"ChangePhoneNumber";
        case UserProfileWriter_Unknown:
            OWSCFailDebug(@"Invalid UserProfileWriter.");
            return @"Unknown";
        default:
            OWSCFailDebug(@"Invalid UserProfileWriter.");
            return @"default";
    }
}

#pragma mark -

@interface OWSUserProfile ()

@property (atomic, nullable) OWSAES256Key *profileKey;
// Ultimately used as an alias of givenName, but sqlite doesn't support renaming columns
@property (atomic, nullable) NSString *profileName;
@property (atomic, nullable) NSString *familyName;
@property (atomic, nullable) NSString *bio;
@property (atomic, nullable) NSString *bioEmoji;
@property (atomic, nullable) NSArray<OWSUserProfileBadgeInfo *> *profileBadgeInfo;
@property (atomic, nullable) NSDate *lastFetchDate;
@property (atomic, nullable) NSDate *lastMessagingDate;

@property (atomic) BOOL isStoriesCapable;
@property (atomic) BOOL canReceiveGiftBadges;
@property (atomic) BOOL isPniCapable;

@property (atomic, readonly) NSUInteger userProfileSchemaVersion;

@end

#pragma mark -

@implementation OWSUserProfile

@synthesize avatarUrlPath = _avatarUrlPath;
@synthesize avatarFileName = _avatarFileName;
@synthesize profileName = _profileName;
@synthesize familyName = _familyName;

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
                  avatarFileName:(nullable NSString *)avatarFileName
                   avatarUrlPath:(nullable NSString *)avatarUrlPath
                             bio:(nullable NSString *)bio
                        bioEmoji:(nullable NSString *)bioEmoji
            canReceiveGiftBadges:(BOOL)canReceiveGiftBadges
                      familyName:(nullable NSString *)familyName
                    isPniCapable:(BOOL)isPniCapable
                isStoriesCapable:(BOOL)isStoriesCapable
                   lastFetchDate:(nullable NSDate *)lastFetchDate
               lastMessagingDate:(nullable NSDate *)lastMessagingDate
                profileBadgeInfo:(nullable NSArray<OWSUserProfileBadgeInfo *> *)profileBadgeInfo
                      profileKey:(nullable OWSAES256Key *)profileKey
                     profileName:(nullable NSString *)profileName
            recipientPhoneNumber:(nullable NSString *)recipientPhoneNumber
                   recipientUUID:(nullable NSString *)recipientUUID
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _avatarFileName = avatarFileName;
    _avatarUrlPath = avatarUrlPath;
    _bio = bio;
    _bioEmoji = bioEmoji;
    _canReceiveGiftBadges = canReceiveGiftBadges;
    _familyName = familyName;
    _isPniCapable = isPniCapable;
    _isStoriesCapable = isStoriesCapable;
    _lastFetchDate = lastFetchDate;
    _lastMessagingDate = lastMessagingDate;
    _profileBadgeInfo = profileBadgeInfo;
    _profileKey = profileKey;
    _profileName = profileName;
    _recipientPhoneNumber = recipientPhoneNumber;
    _recipientUUID = recipientUUID;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

+ (NSString *)collection
{
    // Legacy class name.
    return @"UserProfile";
}

+ (UserProfileFinder *)userProfileFinder
{
    return [UserProfileFinder new];
}

+ (SignalServiceAddress *)localProfileAddress
{
    return [[SignalServiceAddress alloc] initWithPhoneNumber:kLocalProfileInvariantPhoneNumber];
}

+ (BOOL)isLocalProfileAddress:(SignalServiceAddress *)address
{
    if ([address.phoneNumber isEqualToString:kLocalProfileInvariantPhoneNumber]) {
        return YES;
    } else {
        return address.isLocalAddress;
    }
}

+ (SignalServiceAddress *)resolveUserProfileAddress:(SignalServiceAddress *)address
{
    return ([self isLocalProfileAddress:address] ? self.localProfileAddress : address);
}

+ (SignalServiceAddress *)publicAddressForAddress:(SignalServiceAddress *)address
{
    if ([self isLocalProfileAddress:address]) {
        SignalServiceAddress *_Nullable localAddress = [TSAccountManagerObjcBridge localAciAddressWithMaybeTransaction];
        if (localAddress == nil) {
            OWSFailDebug(@"Missing localAddress.");
        } else {
            return localAddress;
        }
    }
    return address;
}

- (SignalServiceAddress *)publicAddress
{
    return [OWSUserProfile publicAddressForAddress:self.address];
}

+ (nullable OWSUserProfile *)getUserProfileForAddress:(SignalServiceAddress *)addressParam
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    SignalServiceAddress *address = [self resolveUserProfileAddress:addressParam];
    OWSAssertDebug(address.isValid);
    return [self.userProfileFinder userProfileForAddress:address transaction:transaction];
}

+ (BOOL)localUserProfileExistsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.userProfileFinder userProfileForAddress:self.localProfileAddress transaction:transaction] != nil;
}

- (void)loadBadgeContentWithTransaction:(SDSAnyReadTransaction *)transaction
{
    for (OWSUserProfileBadgeInfo *badgeInfo in self.profileBadgeInfo) {
        [badgeInfo loadBadgeWithTransaction:transaction];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super initWithCoder:coder]) {
        if (_userProfileSchemaVersion < 1) {
            _recipientPhoneNumber = [coder decodeObjectForKey:@"recipientId"];
            OWSAssertDebug(_recipientPhoneNumber);
        }

        _userProfileSchemaVersion = kUserProfileSchemaVersion;
    }

    return self;
}

- (instancetype)initWithAddress:(SignalServiceAddress *)address
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertDebug(address.isValid);
    OWSAssertDebug(!address.isLocalAddress);
    _recipientPhoneNumber = address.phoneNumber;
    _recipientUUID = address.serviceIdUppercaseString;
    _userProfileSchemaVersion = kUserProfileSchemaVersion;

    return self;
}

#pragma mark -

- (SignalServiceAddress *)address
{
    return [[SignalServiceAddress alloc] initWithServiceIdString:self.recipientUUID
                                                     phoneNumber:self.recipientPhoneNumber];
}

// When possible, update the avatar properties in lockstep.
- (void)updateAvatarUrlPath:(nullable NSString *)avatarUrlPath
             avatarFileName:(nullable NSString *)avatarFileName
          userProfileWriter:(UserProfileWriter)userProfileWriter
{
    @synchronized(self) {
        BOOL urlPathDidChange = ![NSObject isNullableObject:_avatarUrlPath equalTo:avatarUrlPath];
        BOOL fileNameDidChange = ![NSObject isNullableObject:_avatarFileName equalTo:avatarFileName];
        BOOL didChange = urlPathDidChange || fileNameDidChange;

        if (!didChange) {
            return;
        }

        BOOL isLocalUserProfile = [OWSUserProfile isLocalProfileAddress:self.address];

        if (fileNameDidChange && _avatarFileName.length > 0) {
            NSString *oldAvatarFilePath = [OWSUserProfile profileAvatarFilepathWithFilename:_avatarFileName];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                if (isLocalUserProfile) {
                    OWSLogInfo(@"Deleting local avatarFileName (%@)", NSStringForUserProfileWriter(userProfileWriter));
                }
                [OWSFileSystem deleteFileIfExists:oldAvatarFilePath];
            });
        }

        if (isLocalUserProfile) {
            OWSLogInfo(@"local avatarUrlPath (%@): %d -> %d (%d)",
                NSStringForUserProfileWriter(userProfileWriter),
                _avatarUrlPath.length > 0,
                avatarUrlPath.length > 0,
                urlPathDidChange);
            OWSLogInfo(@"local avatarFileName (%@): %d -> %d (%d)",
                NSStringForUserProfileWriter(userProfileWriter),
                _avatarFileName.length > 0,
                avatarFileName.length > 0,
                fileNameDidChange);
        }

        _avatarUrlPath = avatarUrlPath;
        _avatarFileName = avatarFileName;
    }
}

- (nullable NSString *)avatarUrlPath
{
    @synchronized(self) {
        return _avatarUrlPath;
    }
}

- (void)updateAvatarUrlPath:(nullable NSString *)avatarUrlPath userProfileWriter:(UserProfileWriter)userProfileWriter
{
    @synchronized(self) {
        if (_avatarUrlPath != nil && ![_avatarUrlPath isEqual:avatarUrlPath]) {
            // If the avatarURL was previously set and it changed, the old avatarFileName
            // can't still be valid. Clear it.
            // NOTE: `_avatarUrlPath` will momentarily be nil during initWithCoder -
            // which is why we verify it's non-nil before inadvertently "cleaning up" the
            // avatarFileName during initialization. If it were *actually* nil, as opposed
            // to just transiently nil during `initWithCoder` , there'd be no avatarFileName
            // to clean up anyway.
            [self updateAvatarFileName:nil userProfileWriter:userProfileWriter];
        }

        BOOL isLocalUserProfile = [OWSUserProfile isLocalProfileAddress:self.address];
        if (isLocalUserProfile) {
            OWSLogInfo(@"local avatarUrlPath (%@): %d -> %d",
                NSStringForUserProfileWriter(userProfileWriter),
                _avatarUrlPath.length > 0,
                avatarUrlPath.length > 0);
        }

        _avatarUrlPath = avatarUrlPath;
    }
}

- (nullable NSString *)avatarFileName
{
    @synchronized(self) {
        return _avatarFileName;
    }
}

- (void)updateAvatarFileName:(nullable NSString *)avatarFileName userProfileWriter:(UserProfileWriter)userProfileWriter
{
    @synchronized(self) {
        BOOL didChange = ![NSObject isNullableObject:_avatarFileName equalTo:avatarFileName];
        if (!didChange) {
            return;
        }

        BOOL isLocalUserProfile = [OWSUserProfile isLocalProfileAddress:self.address];

        if (_avatarFileName) {
            NSString *oldAvatarFilePath = [OWSUserProfile profileAvatarFilepathWithFilename:_avatarFileName];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                if (isLocalUserProfile) {
                    OWSLogInfo(@"Deleting local avatarFileName (%@)", NSStringForUserProfileWriter(userProfileWriter));
                }
                [OWSFileSystem deleteFileIfExists:oldAvatarFilePath];
            });
        }

        if (isLocalUserProfile) {
            OWSLogInfo(@"local avatarFileName (%@): %d -> %d",
                NSStringForUserProfileWriter(userProfileWriter),
                _avatarFileName.length > 0,
                avatarFileName.length > 0);
        }

        _avatarFileName = avatarFileName;
    }
}

#pragma mark - Update With... Methods

+ (BOOL)shouldReuploadProtectedProfileName
{
    // Only re-upload once per launch.
    //
    // This value will only be accessed within write transactions,
    // so it is thread-safe.
    static BOOL hasReuploaded = NO;
    BOOL canReupload = !hasReuploaded;
    hasReuploaded = YES;
    return canReupload;
}

// Similar in spirit to anyUpdateWithTransaction,
// but with significant differences.
//
// * We save if this entity is not in the database.
// * We skip redundant saves by diffing.
// * We kick off multi-device synchronization.
// * We fire "did change" notifications.
+ (void)applyChanges:(UserProfileChanges *)changes
              profile:(OWSUserProfile *)profile
    userProfileWriter:(UserProfileWriter)userProfileWriter
{
    BOOL isLocalProfile = [OWSUserProfile isLocalProfileAddress:profile.address];
    BOOL canModifyStorageServiceProperties;
    if (isLocalProfile) {
        // Any properties stored in the storage service can only
        // by modified by the local user or the storage service.
        // In particular, they should _not_ be modified by profile
        // fetches.
        switch (userProfileWriter) {
            case UserProfileWriter_LocalUser:
                canModifyStorageServiceProperties = YES;
                break;
            case UserProfileWriter_ProfileFetch:
                canModifyStorageServiceProperties = NO;
                break;
            case UserProfileWriter_StorageService:
                canModifyStorageServiceProperties = YES;
                break;
            case UserProfileWriter_SyncMessage:
                canModifyStorageServiceProperties = NO;
                break;
            case UserProfileWriter_Registration:
                canModifyStorageServiceProperties = YES;
                break;
            case UserProfileWriter_Linking:
                canModifyStorageServiceProperties = NO;
                break;
            case UserProfileWriter_GroupState:
                canModifyStorageServiceProperties = NO;
                break;
            case UserProfileWriter_Reupload:
                canModifyStorageServiceProperties = NO;
                break;
            case UserProfileWriter_AvatarDownload:
                canModifyStorageServiceProperties = NO;
                break;
            case UserProfileWriter_MetadataUpdate:
                canModifyStorageServiceProperties = NO;
                break;
            case UserProfileWriter_Debugging:
                canModifyStorageServiceProperties = YES;
                break;
            case UserProfileWriter_Tests:
                canModifyStorageServiceProperties = YES;
                break;
            case UserProfileWriter_SystemContactsFetch:
                OWSFailDebug(@"Invalid UserProfileWriter.");
                canModifyStorageServiceProperties = NO;
                break;
            case UserProfileWriter_ChangePhoneNumber:
                OWSFailDebug(@"Invalid UserProfileWriter.");
                canModifyStorageServiceProperties = NO;
                break;
            case UserProfileWriter_Unknown:
                OWSFailDebug(@"Invalid UserProfileWriter.");
                canModifyStorageServiceProperties = NO;
                break;
            default:
                OWSFailDebug(@"Invalid UserProfileWriter.");
                canModifyStorageServiceProperties = NO;
                break;
        }
    } else {
        canModifyStorageServiceProperties = YES;
    }

    if (changes.givenName != nil && canModifyStorageServiceProperties) {
        // The "profile name" aka "given name" is stored in the storage service.
        profile.givenName = changes.givenName.value;
    }
    if (changes.familyName != nil && canModifyStorageServiceProperties) {
        // The "family name" is stored in the storage service.
        profile.familyName = changes.familyName.value;
    }
    if (changes.bio != nil) {
        profile.bio = changes.bio.value;
    }
    if (changes.bioEmoji != nil) {
        profile.bioEmoji = changes.bioEmoji.value;
    }
    if (changes.badges != nil) {
        profile.profileBadgeInfo = changes.badges;
    }

    if (changes.isStoriesCapable != nil) {
        profile.isStoriesCapable = changes.isStoriesCapable.value;
    }
    if (changes.canReceiveGiftBadges != nil) {
        profile.canReceiveGiftBadges = changes.canReceiveGiftBadges.value;
    }
    if (changes.isPniCapable != nil) {
        profile.isPniCapable = changes.isPniCapable.value;
    }

    BOOL canUpdateAvatarUrlPath
        = (canModifyStorageServiceProperties || userProfileWriter == UserProfileWriter_Reupload);
    BOOL canUpdateAvatarFileName = (canUpdateAvatarUrlPath || userProfileWriter == UserProfileWriter_AvatarDownload);

    if (SSKDebugFlags.internalLogging && isLocalProfile) {
        OWSLogInfo(@"Updating profile: %@, writer: %@, address: %@, "
                   @"isLocalUserProfile: %d, canModifyStorageServiceProperties: %d, canUpdateAvatarUrlPath: %d, "
                   @"canUpdateAvatarFileName: %d, avatarUrlPath: (old: %d, changes: %d, new: %d), avatarFileName: "
                   @"(old: %d, changes: %d, new: %d).",
            changes.updateMethodName,
            NSStringForUserProfileWriter(userProfileWriter),
            profile.address,
            isLocalProfile,
            canModifyStorageServiceProperties,
            canUpdateAvatarUrlPath,
            canUpdateAvatarFileName,
            profile.avatarUrlPath != nil,
            changes.avatarUrlPath != nil,
            changes.avatarUrlPath.value.ows_nilIfEmpty != nil,
            profile.avatarFileName != nil,
            changes.avatarFileName != nil,
            changes.avatarFileName.value.ows_nilIfEmpty != nil);
    }

    // Update the avatar properties in lockstep.
    if (changes.avatarUrlPath != nil && changes.avatarFileName != nil && canUpdateAvatarUrlPath) {
        [profile updateAvatarUrlPath:changes.avatarUrlPath.value
                      avatarFileName:changes.avatarFileName.value
                   userProfileWriter:userProfileWriter];
    } else if (changes.avatarUrlPath != nil && canUpdateAvatarUrlPath) {
        // The "avatar url path" (but not the "avatar file name") is stored in the storage service.
        [profile updateAvatarUrlPath:changes.avatarUrlPath.value userProfileWriter:userProfileWriter];
    } else if (changes.avatarFileName != nil && canUpdateAvatarFileName) {
        // The local user should be able to "filling in" their profile avatar
        // by downloading a profile avatar url.
        [profile updateAvatarFileName:changes.avatarFileName.value userProfileWriter:userProfileWriter];
    }

    if (changes.lastFetchDate != nil) {
        profile.lastFetchDate = changes.lastFetchDate.value;
    }
    if (changes.lastMessagingDate != nil) {
        profile.lastMessagingDate = changes.lastMessagingDate.value;
    }
    if (changes.profileKey != nil) {
        profile.profileKey = changes.profileKey.value;
    }
}

// Similar in spirit to anyUpdateWithTransaction,
// but with significant differences.
//
// * We save if this entity is not in the database.
// * We skip redundant saves by diffing.
// * We kick off multi-device synchronization.
// * We fire "did change" notifications.
- (void)applyChanges:(UserProfileChanges *)changes
    userProfileWriter:(UserProfileWriter)userProfileWriter
        authedAccount:(AuthedAccount *)authedAccount
          transaction:(SDSAnyWriteTransaction *)transaction
           completion:(nullable OWSUserProfileCompletion)completion
{
    OWSAssertDebug(transaction);
    BOOL isLocalUserProfile = [OWSUserProfile isLocalProfileAddress:self.address];
    if (isLocalUserProfile) {
        // We should never be writing to or updating the "local address" profile;
        // we should be using the "kLocalProfileInvariantPhoneNumber" profile instead.
        OWSAssertDebug([self.address.phoneNumber isEqualToString:kLocalProfileInvariantPhoneNumber]);
    }

    // This should be set to true if:
    //
    // * This profile has just been inserted.
    // * Updating the profile updated this instance.
    // * Updating the profile updated the "latest" instance.
    __block BOOL didChange = NO;
    __block BOOL onlyAvatarChanged = NO;
    __block BOOL profileKeyDidChange = NO;

    OWSUserProfile *_Nullable latestInstance = [OWSUserProfile anyFetchWithUniqueId:self.uniqueId
                                                                        transaction:transaction];
    [latestInstance loadBadgeContentWithTransaction:transaction];

    __block OWSUserProfile *_Nullable updatedInstance;
    __block BOOL shouldReindex = (changes.givenName != nil || changes.familyName != nil);
    if (latestInstance != nil) {
        [self anyUpdateWithTransaction:transaction
                                 block:^(OWSUserProfile *profile) {
            NSArray *avatarKeys = @[ @"avatarFileName", @"avatarUrlPath" ];

            // self might be the latest instance, so take a "before" snapshot
            // before any changes have been made.
            NSDictionary *beforeSnapshot = [profile.dictionaryValue
                                            mtl_dictionaryByRemovingValuesForKeys:@[ @"lastFetchDate" ]];
            NSDictionary *beforeSnapshotWithoutAvatar =
            [beforeSnapshot mtl_dictionaryByRemovingValuesForKeys:avatarKeys];

            OWSAES256Key *_Nullable profileKeyBefore = profile.profileKey;
            NSString *_Nullable givenNameBefore = profile.givenName;
            NSString *_Nullable familyNameBefore = profile.familyName;
            NSString *_Nullable avatarUrlPathBefore = profile.avatarUrlPath;
            NSString *_Nullable avatarFileNameBefore = profile.avatarFileName;

            [OWSUserProfile applyChanges:changes
                                 profile:profile
                       userProfileWriter:userProfileWriter];

            profileKeyDidChange = ![NSObject isNullableObject:profileKeyBefore.keyData
                                                      equalTo:profile.profileKey.keyData];
            BOOL givenNameDidChange = ![NSObject isNullableObject:givenNameBefore
                                                          equalTo:profile.givenName];
            BOOL familyNameDidChange = ![NSObject isNullableObject:familyNameBefore
                                                           equalTo:profile.familyName];
            BOOL avatarUrlPathDidChange = ![NSObject isNullableObject:avatarUrlPathBefore
                                                              equalTo:profile.avatarUrlPath];
            BOOL avatarFileNameDidChange = ![NSObject isNullableObject:avatarFileNameBefore
                                                               equalTo:profile.avatarFileName];
            if (!givenNameDidChange && !familyNameDidChange) {
                shouldReindex = NO;
            }

            if (isLocalUserProfile) {
                BOOL shouldReupload = NO;

                BOOL hasValidProfileNameBefore = givenNameBefore.length > 0;
                BOOL hasValidProfileNameAfter = profile.givenName.length > 0;
                if (hasValidProfileNameBefore && !hasValidProfileNameAfter) {
                    OWSFailDebug(@"Restoring local profile name: %@, %@.",
                                 changes.updateMethodName,
                                 NSStringForUserProfileWriter(userProfileWriter));
                    // Profile names are required; never clear the profile
                    // name for the local user.
                    profile.givenName = givenNameBefore;
                    shouldReupload = YES;
                }

                // If db state that is "owned" by storage service doesn't
                // match profile fetch state, re-upload.
                if (userProfileWriter == UserProfileWriter_ProfileFetch) {
                    BOOL givenNameDoesNotMatch
                    = ![NSObject isNullableObject:[changes.givenName.value ows_nilIfEmpty]
                                          equalTo:[profile.givenName ows_nilIfEmpty]];
                    BOOL familyNameDoesNotMatch
                    = ![NSObject isNullableObject:[changes.familyName.value ows_nilIfEmpty]
                                          equalTo:[profile.familyName ows_nilIfEmpty]];
                    BOOL avatarUrlPathDoesNotMatch = ![NSObject
                                                       isNullableObject:[changes.avatarUrlPath.value ows_nilIfEmpty]
                                                       equalTo:[profile.avatarUrlPath ows_nilIfEmpty]];
                    BOOL avatarFileNameDoesNotMatch = ![NSObject
                                                        isNullableObject:[changes.avatarFileName.value ows_nilIfEmpty]
                                                        equalTo:[profile.avatarFileName ows_nilIfEmpty]];
                    if (givenNameDoesNotMatch || familyNameDoesNotMatch
                        || avatarUrlPathDoesNotMatch) {
                        OWSLogWarn(@"Local profile state from database and profile fetch "
                                   @"differ: %@, %@, "
                                   @"isLocalUserProfile: %d, givenName: %d -> %d (%d), "
                                   @"familyName: %d -> %d (%d), avatarUrlPath: %d -> %d (%d), "
                                   @"avatarFileName: %d -> %d (%d).",
                                   changes.updateMethodName,
                                   NSStringForUserProfileWriter(userProfileWriter),
                                   isLocalUserProfile,
                                   profile.givenName.length > 0,
                                   changes.givenName.value.length > 0,
                                   givenNameDoesNotMatch,
                                   profile.familyName.length > 0,
                                   changes.familyName.value.length > 0,
                                   familyNameDoesNotMatch,
                                   profile.avatarUrlPath.length > 0,
                                   changes.avatarUrlPath.value.length > 0,
                                   avatarUrlPathDoesNotMatch,
                                   profile.avatarFileName.length > 0,
                                   changes.avatarFileName.value.length > 0,
                                   avatarFileNameDoesNotMatch);
                        shouldReupload = YES;
                    }
                }

                BOOL isUpdatingDatabaseInstance = self != profile;
                if (shouldReupload && [TSAccountManagerObjcBridge isPrimaryDeviceWith:transaction]
                    && CurrentAppContext().isMainApp && isUpdatingDatabaseInstance) {
                    // shouldReuploadProtectedProfileName has side effects,
                    // so only invoke it if shouldReupload is true.
                    if (!OWSUserProfile.shouldReuploadProtectedProfileName) {
                        OWSLogVerbose(@"Skipping re-upload.");
                    } else if (profile.avatarUrlPath != nil && profile.avatarFileName == nil) {
                        OWSLogWarn(@"Skipping re-upload; profile avatar not downloaded.");
                    } else {
                        OWSLogInfo(@"Re-uploading local profile to update profile credential.");
                        [transaction addAsyncCompletionOffMain:^{
                            [self.profileManager reuploadLocalProfileWithAuthedAccount:authedAccount];
                        }];
                    }
                }
            }

            NSString *profileKeyDescription;
            if (profile.profileKey.keyData != nil) {
                if (SSKDebugFlags.internalLogging) {
                    profileKeyDescription = profile.profileKey.keyData.hexadecimalString;
                } else {
                    profileKeyDescription = @"[XXXX]";
                }
            } else {
                profileKeyDescription = @"None";
            }

            if (profileKeyDidChange || givenNameDidChange || familyNameDidChange
                || avatarUrlPathDidChange || avatarFileNameDidChange) {
                OWSLogInfo(@"address: %@ (isLocal: %d), profileKeyDidChange: %d (%d -> %d) %@, "
                           @"givenNameDidChange: %d (%d -> %d), familyNameDidChange: %d (%d -> "
                           @"%d), avatarUrlPathDidChange: %d (%d -> %d), "
                           @"avatarFileNameDidChange: %d (%d -> %d), %@, %@.",
                           profile.address,
                           [OWSUserProfile isLocalProfileAddress:profile.address],
                           profileKeyDidChange,
                           profileKeyBefore != nil,
                           profile.profileKey != nil,
                           profileKeyDescription,
                           givenNameDidChange,
                           givenNameBefore != nil,
                           profile.givenName != nil,
                           familyNameDidChange,
                           familyNameBefore != nil,
                           profile.familyName != nil,
                           avatarUrlPathDidChange,
                           avatarUrlPathBefore != nil,
                           profile.avatarUrlPath != nil,
                           avatarFileNameDidChange,
                           avatarFileNameBefore != nil,
                           profile.avatarFileName != nil,
                           changes.updateMethodName,
                           NSStringForUserProfileWriter(userProfileWriter));
            }

            NSDictionary *afterSnapshot = [profile.dictionaryValue
                                           mtl_dictionaryByRemovingValuesForKeys:@[ @"lastFetchDate" ]];
            NSDictionary *afterSnapshotWithoutAvatar =
            [afterSnapshot mtl_dictionaryByRemovingValuesForKeys:avatarKeys];

            if (![beforeSnapshot isEqual:afterSnapshot]) {
                didChange = YES;
            }

            if (didChange && [beforeSnapshotWithoutAvatar isEqual:afterSnapshotWithoutAvatar]) {
                onlyAvatarChanged = YES;
            }

            updatedInstance = profile;
        }];
    } else {
        [OWSUserProfile applyChanges:changes profile:self userProfileWriter:userProfileWriter];
        [self anyInsertWithTransaction:transaction];
        didChange = YES;
    }

    [self loadBadgeContentWithTransaction:transaction];
    [updatedInstance loadBadgeContentWithTransaction:transaction];

    if (completion) {
        [transaction addAsyncCompletionOffMain:completion];
    }

    if (!didChange) {
        return;
    }

    if (isLocalUserProfile) {
        [self.profileManager localProfileWasUpdated:self];
        [self.subscriptionManager reconcileBadgeStatesWithTransaction:transaction];
    }

    if (shouldReindex) {
        OWSLogInfo(@"Reindexing because of profile change.");
        [self reindexAssociatedModelsWithTransaction:transaction];
    }

    // Insert a profile change update in conversations, if necessary
    if (latestInstance && updatedInstance) {
        [TSInfoMessage insertProfileChangeMessagesIfNecessaryWithOldProfile:latestInstance
                                                                 newProfile:updatedInstance
                                                                transaction:transaction];
    }

    // Profile changes, record updates with storage service. We don't store avatar information on the service except for
    // the local user.
    BOOL shouldUpdateStorageService = shouldUpdateStorageServiceForUserProfileWriter(userProfileWriter);
    if (isLocalUserProfile && userProfileWriter == UserProfileWriter_ProfileFetch) {
        // Never update local profile on storage service to reflect profile fetches.
        shouldUpdateStorageService = NO;
    }

    if ([TSAccountManagerObjcBridge isRegisteredWith:transaction] && shouldUpdateStorageService
        && (!onlyAvatarChanged || isLocalUserProfile)) {
        [transaction addAsyncCompletionOffMain:^{
            if (isLocalUserProfile) {
                // If isLocalUserProfile is true, the address we have is actually a placeholder
                // (its not even our real local address!)
                // Replace it with the real deal, from either auth or tsAccountManager.
                SignalServiceAddress *localAddress = [authedAccount localUserAddress];
                if (localAddress == nil) {
                    localAddress = [TSAccountManagerObjcBridge localAciAddressWith:transaction];
                }
                [self.storageServiceManagerObjc recordPendingUpdatesWithUpdatedAddresses:@[ localAddress ]];
            } else {
                [self.storageServiceManagerObjc recordPendingUpdatesWithUpdatedAddresses:@[ self.address ]];
            }
        }];
    }

    [transaction
        addAsyncCompletionWithQueue:dispatch_get_main_queue()
                              block:^{
                                  if (isLocalUserProfile) {
                                      // We populate an initial (empty) profile on launch of a new install, but
                                      // until we have a registered account, syncing will fail (and there could not
                                      // be any linked device to sync to at this point anyway).
                                      if ([TSAccountManagerObjcBridge isRegisteredPrimaryDeviceWithMaybeTransaction]
                                          && CurrentAppContext().isMainApp) {
                                          [self.syncManager syncLocalContact].catchInBackground(
                                              ^(NSError *error) { OWSLogError(@"Error: %@", error); });
                                      }

                                      if (profileKeyDidChange) {
                                          [[NSNotificationCenter defaultCenter]
                                              postNotificationNameAsync:kNSNotificationNameLocalProfileKeyDidChange
                                                                 object:nil
                                                               userInfo:nil];
                                      }

                                      [[NSNotificationCenter defaultCenter]
                                          postNotificationNameAsync:kNSNotificationNameLocalProfileDidChange
                                                             object:nil
                                                           userInfo:nil];
                                  } else {
                                      [[NSNotificationCenter defaultCenter]
                                          postNotificationNameAsync:kNSNotificationNameOtherUsersProfileDidChange
                                                             object:nil
                                                           userInfo:@ {
                                                               kNSNotificationKey_ProfileAddress : self.address,
                                                           }];
                                  }
                              }];
}

// This should only be used in verbose, developer-only logs.
- (NSString *)debugDescription
{
    return [NSString stringWithFormat:@"%@ %p %@ %@", self.logTag, self, self.recipientUUID, self.recipientPhoneNumber];
}

- (nullable NSString *)unfilteredProfileName
{
    @synchronized(self) {
        return _profileName;
    }
}

- (nullable NSString *)profileName
{
    return self.unfilteredProfileName.filterStringForDisplay;
}

- (void)setProfileName:(nullable NSString *)profileName
{
    @synchronized(self) {
        _profileName = profileName;
    }
}

- (nullable NSString *)unfilteredGivenName
{
    return self.unfilteredProfileName;
}

- (nullable NSString *)givenName
{
    return self.profileName;
}

- (void)setGivenName:(nullable NSString *)givenName
{
    [self setProfileName:givenName];
}

- (nullable NSString *)unfilteredFamilyName
{
    @synchronized(self) {
        return _familyName;
    }
}

- (nullable NSString *)familyName
{
    return self.unfilteredFamilyName.filterStringForDisplay;
}

- (void)setFamilyName:(nullable NSString *)familyName
{
    @synchronized(self) {
        _familyName = familyName;
    }
}

- (nullable NSPersonNameComponents *)nameComponents
{
    if (self.givenName.length <= 0) {
        return nil;
    }

    NSPersonNameComponents *nameComponents = [NSPersonNameComponents new];
    nameComponents.givenName = self.givenName;
    nameComponents.familyName = self.familyName;
    return nameComponents;
}

- (nullable NSString *)fullName
{
    if (self.givenName.length <= 0) {
        return nil;
    }

    return [[OWSFormat formatNameComponents:self.nameComponents] filterStringForDisplay];
}

- (nullable OWSUserProfileBadgeInfo *)primaryBadge
{
    return self.visibleBadges.firstObject;
}

#pragma mark - Profile Avatars Directory

+ (NSString *)profileAvatarFilepathWithFilename:(NSString *)filename
{
    OWSAssertDebug(filename.length > 0);

    return [self.profileAvatarsDirPath stringByAppendingPathComponent:filename];
}

+ (NSString *)legacyProfileAvatarsDirPath
{
    return [[OWSFileSystem appDocumentDirectoryPath] stringByAppendingPathComponent:@"ProfileAvatars"];
}

+ (NSString *)sharedDataProfileAvatarsDirPath
{
    return [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"ProfileAvatars"];
}

+ (NSString *)profileAvatarsDirPath
{
    static NSString *profileAvatarsDirPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        profileAvatarsDirPath = self.sharedDataProfileAvatarsDirPath;
        
        [OWSFileSystem ensureDirectoryExists:profileAvatarsDirPath];
    });
    return profileAvatarsDirPath;
}

// TODO: We may want to clean up this directory in the "orphan cleanup" logic.

+ (void)resetProfileStorage
{
    OWSAssertIsOnMainThread();

    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:[self profileAvatarsDirPath] error:&error];
    if (error) {
        OWSLogError(@"Failed to delete database: %@", error.description);
    }
}

+ (NSSet<NSString *> *)allProfileAvatarFilePathsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSString *profileAvatarsDirPath = self.profileAvatarsDirPath;
    NSMutableSet<NSString *> *profileAvatarFilePaths = [NSMutableSet new];
    [OWSUserProfile anyEnumerateWithTransaction:transaction
                                        batched:YES
                                          block:^(OWSUserProfile *userProfile, BOOL *stop) {
                                              if (!userProfile.avatarFileName) {
                                                  return;
                                              }
                                              NSString *filePath = [profileAvatarsDirPath
                                                  stringByAppendingPathComponent:userProfile.avatarFileName];
                                              [profileAvatarFilePaths addObject:filePath];
                                          }];
    return [profileAvatarFilePaths copy];
}

- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidInsertWithTransaction:transaction];

    [self reindexAssociatedModelsWithTransaction:transaction];

    [self.modelReadCaches.userProfileReadCache didInsertOrUpdateUserProfile:self transaction:transaction];
}

- (void)anyDidUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidUpdateWithTransaction:transaction];

    [self.modelReadCaches.userProfileReadCache didInsertOrUpdateUserProfile:self transaction:transaction];
}

- (void)anyDidRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidRemoveWithTransaction:transaction];

    [self.modelReadCaches.userProfileReadCache didRemoveUserProfile:self transaction:transaction];
}

- (OWSUserProfile *)shallowCopy
{
    return (OWSUserProfile *)[self copyWithZone:nil];
}

#pragma mark - OWSMaybeUserProfile

- (OWSUserProfile *_Nullable)userProfileOrNil
{
    return self;
}

@end

@implementation NSNull (OWSMaybeUserProfile)

- (OWSUserProfile *_Nullable)userProfileOrNil
{
    return nil;
}

@end

NS_ASSUME_NONNULL_END
