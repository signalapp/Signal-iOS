//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSUserProfile.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/ProfileManagerProtocol.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const kNSNotificationNameProfileWhitelistDidChange = @"kNSNotificationNameProfileWhitelistDidChange";
NSNotificationName const kNSNotificationNameLocalProfileDidChange = @"kNSNotificationNameLocalProfileDidChange";
NSNotificationName const kNSNotificationNameLocalProfileKeyDidChange = @"kNSNotificationNameLocalProfileKeyDidChange";

NSNotificationName const kNSNotificationNameOtherUsersProfileWillChange
    = @"kNSNotificationNameOtherUsersProfileWillChange";
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
            return NO;
        case UserProfileWriter_AvatarDownload:
            return NO;
        case UserProfileWriter_MetadataUpdate:
            return NO;
        case UserProfileWriter_Debugging:
            return NO;
        case UserProfileWriter_Tests:
            return NO;
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
@property (atomic, nullable) NSString *username;
@property (atomic) BOOL isUuidCapable;
@property (atomic, nullable) NSString *avatarUrlPath;
@property (atomic, nullable) NSString *avatarFileName;
@property (atomic, nullable) NSDate *lastFetchDate;
@property (atomic, nullable) NSDate *lastMessagingDate;

@property (atomic, readonly) NSUInteger userProfileSchemaVersion;
@property (atomic, nullable, readonly) NSString *recipientPhoneNumber;
@property (atomic, nullable, readonly) NSString *recipientUUID;

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
                    familyName:(nullable NSString *)familyName
                 isUuidCapable:(BOOL)isUuidCapable
                 lastFetchDate:(nullable NSDate *)lastFetchDate
             lastMessagingDate:(nullable NSDate *)lastMessagingDate
                    profileKey:(nullable OWSAES256Key *)profileKey
                   profileName:(nullable NSString *)profileName
          recipientPhoneNumber:(nullable NSString *)recipientPhoneNumber
                 recipientUUID:(nullable NSString *)recipientUUID
                      username:(nullable NSString *)username
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
    _familyName = familyName;
    _isUuidCapable = isUuidCapable;
    _lastFetchDate = lastFetchDate;
    _lastMessagingDate = lastMessagingDate;
    _profileKey = profileKey;
    _profileName = profileName;
    _recipientPhoneNumber = recipientPhoneNumber;
    _recipientUUID = recipientUUID;
    _username = username;
    
    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

+ (NSString *)collection
{
    // Legacy class name.
    return @"UserProfile";
}

+ (AnyUserProfileFinder *)userProfileFinder
{
    return [AnyUserProfileFinder new];
}

+ (SignalServiceAddress *)localProfileAddress
{
    return [[SignalServiceAddress alloc] initWithPhoneNumber:kLocalProfileInvariantPhoneNumber];
}

+ (BOOL)isLocalProfileAddress:(SignalServiceAddress *)address
{
    if ([address.phoneNumber isEqualToString:kLocalProfileInvariantPhoneNumber]) {
        return YES;
    }
    return address.isLocalAddress;
}

+ (SignalServiceAddress *)resolveUserProfileAddress:(SignalServiceAddress *)address
{
    return ([self isLocalProfileAddress:address] ? self.localProfileAddress : address);
}

+ (SignalServiceAddress *)publicAddressForAddress:(SignalServiceAddress *)address
{
    if ([self isLocalProfileAddress:address]) {
        SignalServiceAddress *_Nullable localAddress = self.tsAccountManager.localAddress;
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

+ (OWSUserProfile *)getOrBuildUserProfileForAddress:(SignalServiceAddress *)addressParam
                                        transaction:(SDSAnyWriteTransaction *)transaction
{
    SignalServiceAddress *address = [self resolveUserProfileAddress:addressParam];
    OWSAssertDebug(address.isValid);
    OWSUserProfile *_Nullable userProfile = [self.userProfileFinder userProfileForAddress:address
                                                                              transaction:transaction];

    if (!userProfile) {
        userProfile = [[OWSUserProfile alloc] initWithAddress:address];

        if ([address.phoneNumber isEqualToString:kLocalProfileInvariantPhoneNumber]) {
            [userProfile updateWithProfileKey:[OWSAES256Key generateRandomKey]
                            userProfileWriter:UserProfileWriter_LocalUser
                                  transaction:transaction
                                   completion:nil];
        }
    }

    OWSAssertDebug(userProfile);

    return userProfile;
}

+ (nullable OWSUserProfile *)userProfileForUsername:(NSString *)username
                                        transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(username.length > 0);

    return [self.userProfileFinder userProfileForUsername:username transaction:transaction];
}

+ (BOOL)localUserProfileExistsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.userProfileFinder userProfileForAddress:self.localProfileAddress transaction:transaction] != nil;
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
    _recipientUUID = address.uuidString;
    _userProfileSchemaVersion = kUserProfileSchemaVersion;

    return self;
}

#pragma mark -

- (SignalServiceAddress *)address
{
    return [[SignalServiceAddress alloc] initWithUuidString:self.recipientUUID phoneNumber:self.recipientPhoneNumber];
}

// When possible, update the avatar properties in lockstep.
- (void)setAvatarUrlPath:(nullable NSString *)avatarUrlPath avatarFileName:(nullable NSString *)avatarFileName
{
    @synchronized(self) {
        BOOL urlPathDidChange = ![NSObject isNullableObject:_avatarUrlPath equalTo:avatarUrlPath];
        BOOL fileNameDidChange = ![NSObject isNullableObject:_avatarFileName equalTo:avatarFileName];
        BOOL didChange = urlPathDidChange || fileNameDidChange;

        if (!didChange) {
            return;
        }

        if (fileNameDidChange && _avatarFileName.length > 0) {
            NSString *oldAvatarFilePath = [OWSUserProfile profileAvatarFilepathWithFilename:_avatarFileName];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [OWSFileSystem deleteFileIfExists:oldAvatarFilePath];
            });
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

- (void)setAvatarUrlPath:(nullable NSString *)avatarUrlPath
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
            self.avatarFileName = nil;
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

- (void)setAvatarFileName:(nullable NSString *)avatarFileName
{
    @synchronized(self) {
        BOOL didChange = ![NSObject isNullableObject:_avatarFileName equalTo:avatarFileName];
        if (!didChange) {
            return;
        }

        if (_avatarFileName) {
            NSString *oldAvatarFilePath = [OWSUserProfile profileAvatarFilepathWithFilename:_avatarFileName];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [OWSFileSystem deleteFileIfExists:oldAvatarFilePath];
            });
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
    BOOL canModifyStorageServiceProperties;
    if ([OWSUserProfile isLocalProfileAddress:profile.address]) {
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
                OWSFailDebug(@"Group state should not write to user profiles.");
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
    if (changes.username != nil) {
        profile.username = changes.username.value;
    }
    if (changes.isUuidCapable != nil) {
        profile.isUuidCapable = changes.isUuidCapable.value;
    }

    // Update the avatar properties in lockstep.
    if (changes.avatarUrlPath != nil && changes.avatarFileName != nil && canModifyStorageServiceProperties) {
        [profile setAvatarUrlPath:changes.avatarUrlPath.value avatarFileName:changes.avatarFileName.value];
    } else if (changes.avatarUrlPath != nil && canModifyStorageServiceProperties) {
        // The "avatar url path" (but not the "avatar file name") is stored in the storage service.
        profile.avatarUrlPath = changes.avatarUrlPath.value;
    } else if (changes.avatarFileName != nil) {
        profile.avatarFileName = changes.avatarFileName.value;
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
          transaction:(SDSAnyWriteTransaction *)transaction
           completion:(nullable OWSUserProfileCompletion)completion
{
    OWSAssertDebug(transaction);
    BOOL isLocalUserProfile = [OWSUserProfile isLocalProfileAddress:self.address];
    // We should never be writing to or updating the "local address" profile;
    // we should be using the "kLocalProfileInvariantPhoneNumber" profile instead.
    OWSAssertDebug(!self.address.isLocalAddress);

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
    __block OWSUserProfile *_Nullable updatedInstance;
    if (latestInstance != nil) {
        [self
            anyUpdateWithTransaction:transaction
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
                                               = ![NSObject isNullableObject:changes.givenName.value
                                                                     equalTo:profile.givenName];
                                           BOOL familyNameDoesNotMatch
                                               = ![NSObject isNullableObject:changes.familyName.value
                                                                     equalTo:profile.familyName];
                                           BOOL avatarUrlPathDoesNotMatch
                                               = ![NSObject isNullableObject:changes.avatarUrlPath.value
                                                                     equalTo:profile.avatarUrlPath];
                                           if (givenNameDoesNotMatch || familyNameDoesNotMatch
                                               || avatarUrlPathDoesNotMatch) {
                                               OWSLogWarn(@"Updating profile to reflect profile state: %@, %@.",
                                                   changes.updateMethodName,
                                                   NSStringForUserProfileWriter(userProfileWriter));
                                               shouldReupload = YES;
                                           }
                                       }

                                       if (shouldReupload && self.tsAccountManager.isPrimaryDevice) {
                                           // shouldReuploadProtectedProfileName has side effects,
                                           // so only invoke it if shouldReupload is true.
                                           if (OWSUserProfile.shouldReuploadProtectedProfileName) {
                                               [transaction addAsyncCompletionOffMain:^{
                                                   [self.profileManager reuploadLocalProfile];
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
                                       || avatarUrlPathDidChange) {
                                       OWSLogInfo(@"address: %@ (isLocal: %d), profileKeyDidChange: %d (%d -> %d) %@, "
                                                  @"givenNameDidChange: %d (%d -> %d), familyNameDidChange: %d (%d -> "
                                                  @"%d), avatarUrlPathDidChange: %d (%d -> %d), %@, %@.",
                                           profile.address,
                                           profile.address.isLocalAddress,
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

    if (completion) {
        [transaction addAsyncCompletionWithQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                                           block:completion];
    }

    if (!didChange) {
        return;
    }

    if (isLocalUserProfile) {
        [self.profileManager localProfileWasUpdated:self];
    }

    // Insert a profile change update in conversations, if necessary
    if (latestInstance && updatedInstance) {
        [TSInfoMessage insertProfileChangeMessagesIfNecessaryWithOldProfile:latestInstance
                                                                 newProfile:updatedInstance
                                                                transaction:transaction];
    }

    // Profile changes, record updates with storage service. We don't store avatar information on the service except for
    // the local user.
    if (self.tsAccountManager.isRegisteredAndReady && shouldUpdateStorageServiceForUserProfileWriter(userProfileWriter)
        && (!onlyAvatarChanged || isLocalUserProfile)) {
        [self.storageServiceManager
            recordPendingUpdatesWithUpdatedAddresses:@[ isLocalUserProfile ? self.tsAccountManager.localAddress
                                                                           : self.address ]];
    }

    [transaction
        addAsyncCompletionWithQueue:dispatch_get_main_queue()
                              block:^{
                                  if (isLocalUserProfile) {
                                      // We populate an initial (empty) profile on launch of a new install, but
                                      // until we have a registered account, syncing will fail (and there could not
                                      // be any linked device to sync to at this point anyway).
                                      if (self.tsAccountManager.isRegisteredPrimaryDevice
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
                                          postNotificationNameAsync:kNSNotificationNameOtherUsersProfileWillChange
                                                             object:nil
                                                           userInfo:@ {
                                                               kNSNotificationKey_ProfileAddress : self.address,
                                                           }];
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
    return [NSString stringWithFormat:@"%@ %p %@ %lu %@ %@ %@ %@",
                     self.logTag,
                     self,
                     self.address,
                     (unsigned long)self.profileKey.keyData.length,
                     self.givenName,
                     self.familyName,
                     self.avatarUrlPath,
                     self.avatarFileName];
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

    return [[NSPersonNameComponentsFormatter localizedStringFromPersonNameComponents:self.nameComponents
                                                                               style:0
                                                                             options:0] filterStringForDisplay];
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

    [self reindexAssociatedModels:transaction];

    [self.modelReadCaches.userProfileReadCache didInsertOrUpdateUserProfile:self transaction:transaction];
}

- (void)anyDidUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidUpdateWithTransaction:transaction];

    [self reindexAssociatedModels:transaction];

    [self.modelReadCaches.userProfileReadCache didInsertOrUpdateUserProfile:self transaction:transaction];
}

- (void)anyDidRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidRemoveWithTransaction:transaction];

    [self.modelReadCaches.userProfileReadCache didRemoveUserProfile:self transaction:transaction];
}

- (void)reindexAssociatedModels:(SDSAnyWriteTransaction *)transaction
{
    // The profile can affect how accounts, recipients and contact threads are indexed, so we
    // need to re-index them whenever the profile changes.
    FullTextSearchFinder *fullTextSearchFinder = [FullTextSearchFinder new];

    AnySignalAccountFinder *accountFinder = [AnySignalAccountFinder new];
    SignalAccount *_Nullable signalAccount = [accountFinder signalAccountForAddress:self.address
                                                                        transaction:transaction];
    if (signalAccount != nil) {
        [fullTextSearchFinder modelWasUpdatedObjcWithModel:signalAccount transaction:transaction];
    }

    AnySignalRecipientFinder *signalRecipientFinder = [AnySignalRecipientFinder new];
    SignalRecipient *_Nullable signalRecipient = [signalRecipientFinder signalRecipientForAddress:self.address
                                                                                      transaction:transaction];
    if (signalRecipient != nil) {
        [fullTextSearchFinder modelWasUpdatedObjcWithModel:signalRecipient transaction:transaction];
    }

    TSContactThread *_Nullable contactThread = [TSContactThread getThreadWithContactAddress:self.address
                                                                                transaction:transaction];
    if (contactThread != nil) {
        [fullTextSearchFinder modelWasUpdatedObjcWithModel:contactThread transaction:transaction];
    }
}

+ (void)mergeUserProfilesIfNecessaryForAddress:(SignalServiceAddress *)address
                                   transaction:(SDSAnyWriteTransaction *)transaction
{
    if (address.uuid == nil || address.phoneNumber == nil) {
        OWSFailDebug(@"Address missing UUID or phone number.");
        return;
    }

    OWSUserProfile *_Nullable userProfileForUuid = [self.userProfileFinder userProfileForUUID:address.uuid
                                                                                  transaction:transaction];
    OWSUserProfile *_Nullable userProfileForPhoneNumber =
        [self.userProfileFinder userProfileForPhoneNumber:address.phoneNumber transaction:transaction];

    // AnyUserProfileFinder prefers UUID profiles, so we try to fill in
    // missing profile keys on UUID profiles from phone number profiles.
    if (userProfileForUuid != nil && userProfileForUuid.profileKey == nil
        && userProfileForPhoneNumber.profileKey != nil) {
        OWSLogInfo(@"Merging user profiles for: %@, %@.", address.uuid, address.phoneNumber);

        [userProfileForUuid updateWithProfileKey:userProfileForPhoneNumber.profileKey
                               userProfileWriter:UserProfileWriter_LocalUser
                                     transaction:transaction
                                      completion:^{ [self.profileManager fetchProfileForAddress:address]; }];
    }
}

- (OWSUserProfile *)shallowCopy
{
    return (OWSUserProfile *)[self copyWithZone:nil];
}

@end

NS_ASSUME_NONNULL_END
