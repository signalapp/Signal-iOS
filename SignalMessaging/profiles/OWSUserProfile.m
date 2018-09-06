//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSUserProfile.h"
#import "NSString+OWS.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/Cryptography.h>
#import <SignalServiceKit/NSData+OWS.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSNotificationName_LocalProfileDidChange = @"kNSNotificationName_LocalProfileDidChange";
NSString *const kNSNotificationName_OtherUsersProfileWillChange = @"kNSNotificationName_OtherUsersProfileWillChange";
NSString *const kNSNotificationName_OtherUsersProfileDidChange = @"kNSNotificationName_OtherUsersProfileDidChange";

NSString *const kNSNotificationKey_ProfileRecipientId = @"kNSNotificationKey_ProfileRecipientId";
NSString *const kNSNotificationKey_ProfileGroupId = @"kNSNotificationKey_ProfileGroupId";

NSString *const kLocalProfileUniqueId = @"kLocalProfileUniqueId";

@interface OWSUserProfile ()

@property (atomic, nullable) OWSAES256Key *profileKey;
@property (atomic, nullable) NSString *profileName;
@property (atomic, nullable) NSString *avatarUrlPath;
@property (atomic, nullable) NSString *avatarFileName;

@end

#pragma mark -

@implementation OWSUserProfile

@synthesize avatarUrlPath = _avatarUrlPath;
@synthesize avatarFileName = _avatarFileName;
@synthesize profileName = _profileName;

+ (NSString *)collection
{
    // Legacy class name.
    return @"UserProfile";
}

+ (OWSUserProfile *)getOrBuildUserProfileForRecipientId:(NSString *)recipientId
                                           dbConnection:(YapDatabaseConnection *)dbConnection
{
    OWSAssertDebug(recipientId.length > 0);

    __block OWSUserProfile *userProfile;
    [dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        userProfile = [OWSUserProfile fetchObjectWithUniqueID:recipientId transaction:transaction];
    }];

    if (!userProfile) {
        userProfile = [[OWSUserProfile alloc] initWithRecipientId:recipientId];

        if ([recipientId isEqualToString:kLocalProfileUniqueId]) {
            [userProfile updateWithProfileKey:[OWSAES256Key generateRandomKey]
                                 dbConnection:dbConnection
                                   completion:nil];
        }
    }

    OWSAssertDebug(userProfile);

    return userProfile;
}

+ (BOOL)localUserProfileExists:(YapDatabaseConnection *)dbConnection
{
    __block BOOL result = NO;
    [dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        result = [OWSUserProfile fetchObjectWithUniqueID:kLocalProfileUniqueId transaction:transaction] != nil;
    }];

    return result;
}

- (instancetype)initWithRecipientId:(NSString *)recipientId
{
    self = [super initWithUniqueId:recipientId];

    if (!self) {
        return self;
    }

    OWSAssertDebug(recipientId.length > 0);
    _recipientId = recipientId;

    return self;
}

- (nullable NSString *)avatarUrlPath
{
    @synchronized(self)
    {
        return _avatarUrlPath;
    }
}

- (void)setAvatarUrlPath:(nullable NSString *)avatarUrlPath
{
    @synchronized(self)
    {
        BOOL didChange = ![NSObject isNullableObject:_avatarUrlPath equalTo:avatarUrlPath];

        _avatarUrlPath = avatarUrlPath;

        if (didChange) {
            // If the avatarURL changed, the avatarFileName can't be valid.
            // Clear it.

            self.avatarFileName = nil;
        }
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

// Similar in spirit to [TSYapDatabaseObject applyChangeToSelfAndLatestCopy],
// but with significant differences.
//
// * We save if this entity is not in the database.
// * We skip redundant saves by diffing.
// * We kick off multi-device synchronization.
// * We fire "did change" notifications.
- (void)applyChanges:(void (^)(id))changeBlock
        functionName:(const char *)functionName
        dbConnection:(YapDatabaseConnection *)dbConnection
          completion:(nullable OWSUserProfileCompletion)completion
{
    // self might be the latest instance, so take a "before" snapshot
    // before any changes have been made.
    __block NSDictionary *beforeSnapshot = [self.dictionaryValue copy];

    changeBlock(self);

    __block BOOL didChange = YES;
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSString *collection = [[self class] collection];
        OWSUserProfile *_Nullable latestInstance = [transaction objectForKey:self.uniqueId inCollection:collection];
        if (latestInstance) {
            // If self is NOT the latest instance, take a new "before" snapshot
            // before updating.
            if (self != latestInstance) {
                beforeSnapshot = [latestInstance.dictionaryValue copy];
            }

            changeBlock(latestInstance);

            NSDictionary *afterSnapshot = [latestInstance.dictionaryValue copy];

            if ([beforeSnapshot isEqual:afterSnapshot]) {
                OWSLogVerbose(@"Ignoring redundant update in %s: %@", functionName, self.debugDescription);
                didChange = NO;
            } else {
                [latestInstance saveWithTransaction:transaction];
            }
        } else {
            [self saveWithTransaction:transaction];
        }
    }];

    if (completion) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), completion);
    }

    if (!didChange) {
        return;
    }

    BOOL isLocalUserProfile = [self.recipientId isEqualToString:kLocalProfileUniqueId];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (isLocalUserProfile) {
            // We populate an initial (empty) profile on launch of a new install, but until
            // we have a registered account, syncing will fail (and there could not be any
            // linked device to sync to at this point anyway).
            if ([TSAccountManager isRegistered]) {
                [CurrentAppContext() doMultiDeviceUpdateWithProfileKey:self.profileKey];
            }

            [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kNSNotificationName_LocalProfileDidChange
                                                                     object:nil
                                                                   userInfo:nil];
        } else {
            [[NSNotificationCenter defaultCenter]
                postNotificationNameAsync:kNSNotificationName_OtherUsersProfileWillChange
                                   object:nil
                                 userInfo:@{
                                     kNSNotificationKey_ProfileRecipientId : self.recipientId,
                                 }];
            [[NSNotificationCenter defaultCenter]
                postNotificationNameAsync:kNSNotificationName_OtherUsersProfileDidChange
                                   object:nil
                                 userInfo:@{
                                     kNSNotificationKey_ProfileRecipientId : self.recipientId,
                                 }];
        }
    });
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               avatarFileName:(nullable NSString *)avatarFileName
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [self applyChanges:^(OWSUserProfile *userProfile) {
        [userProfile setProfileName:[profileName ows_stripped]];
        // Always setAvatarUrlPath: before you setAvatarFileName: since
        // setAvatarUrlPath: may clear the avatar filename.
        [userProfile setAvatarUrlPath:avatarUrlPath];
        [userProfile setAvatarFileName:avatarFileName];
    }
          functionName:__PRETTY_FUNCTION__
          dbConnection:dbConnection
            completion:completion];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                avatarUrlPath:(nullable NSString *)avatarUrlPath
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [self applyChanges:^(OWSUserProfile *userProfile) {
        [userProfile setProfileName:[profileName ows_stripped]];
        [userProfile setAvatarUrlPath:avatarUrlPath];
    }
          functionName:__PRETTY_FUNCTION__
          dbConnection:dbConnection
            completion:completion];
}

- (void)updateWithAvatarUrlPath:(nullable NSString *)avatarUrlPath
                 avatarFileName:(nullable NSString *)avatarFileName
                   dbConnection:(YapDatabaseConnection *)dbConnection
                     completion:(nullable OWSUserProfileCompletion)completion
{
    [self applyChanges:^(OWSUserProfile *userProfile) {
        // Always setAvatarUrlPath: before you setAvatarFileName: since
        // setAvatarUrlPath: may clear the avatar filename.
        [userProfile setAvatarUrlPath:avatarUrlPath];
        [userProfile setAvatarFileName:avatarFileName];
    }
          functionName:__PRETTY_FUNCTION__
          dbConnection:dbConnection
            completion:completion];
}

- (void)updateWithAvatarFileName:(nullable NSString *)avatarFileName
                    dbConnection:(YapDatabaseConnection *)dbConnection
                      completion:(nullable OWSUserProfileCompletion)completion
{
    [self applyChanges:^(OWSUserProfile *userProfile) {
        [userProfile setAvatarFileName:avatarFileName];
    }
          functionName:__PRETTY_FUNCTION__
          dbConnection:dbConnection
            completion:completion];
}

- (void)clearWithProfileKey:(OWSAES256Key *)profileKey
               dbConnection:(YapDatabaseConnection *)dbConnection
                 completion:(nullable OWSUserProfileCompletion)completion
{
    [self applyChanges:^(OWSUserProfile *userProfile) {
        [userProfile setProfileKey:profileKey];
        [userProfile setProfileName:nil];
        // Always setAvatarUrlPath: before you setAvatarFileName: since
        // setAvatarUrlPath: may clear the avatar filename.
        [userProfile setAvatarUrlPath:nil];
        [userProfile setAvatarFileName:nil];
    }
          functionName:__PRETTY_FUNCTION__
          dbConnection:dbConnection
            completion:completion];
}

- (void)updateWithProfileKey:(OWSAES256Key *)profileKey
                dbConnection:(YapDatabaseConnection *)dbConnection
                  completion:(nullable OWSUserProfileCompletion)completion
{
    OWSAssertDebug(profileKey);

    [self applyChanges:^(OWSUserProfile *userProfile) {
        [userProfile setProfileKey:profileKey];
    }
          functionName:__PRETTY_FUNCTION__
          dbConnection:dbConnection
            completion:completion];
}

#pragma mark - Database Connection Accessors

- (YapDatabaseConnection *)dbReadConnection
{
    OWSFailDebug(@"UserProfile should always use OWSProfileManager's database connection.");

    return TSYapDatabaseObject.dbReadConnection;
}

+ (YapDatabaseConnection *)dbReadConnection
{
    OWSFailDebug(@"UserProfile should always use OWSProfileManager's database connection.");

    return TSYapDatabaseObject.dbReadConnection;
}

- (YapDatabaseConnection *)dbReadWriteConnection
{
    OWSFailDebug(@"UserProfile should always use OWSProfileManager's database connection.");

    return TSYapDatabaseObject.dbReadWriteConnection;
}

+ (YapDatabaseConnection *)dbReadWriteConnection
{
    OWSFailDebug(@"UserProfile should always use OWSProfileManager's database connection.");

    return TSYapDatabaseObject.dbReadWriteConnection;
}

// This should only be used in verbose, developer-only logs.
- (NSString *)debugDescription
{
    return [NSString stringWithFormat:@"%@ %p %@ %lu %@ %@ %@",
                     self.logTag,
                     self,
                     self.recipientId,
                     (unsigned long)self.profileKey.keyData.length,
                     self.profileName,
                     self.avatarUrlPath,
                     self.avatarFileName];
}

- (nullable NSString *)profileName
{
    @synchronized(self)
    {
        return _profileName.filterStringForDisplay;
    }
}

- (void)setProfileName:(nullable NSString *)profileName
{
    @synchronized(self)
    {
        _profileName = profileName.filterStringForDisplay;
    }
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

+ (nullable NSError *)migrateToSharedData
{
    OWSLogInfo(@"");

    return [OWSFileSystem moveAppFilePath:self.legacyProfileAvatarsDirPath
                       sharedDataFilePath:self.sharedDataProfileAvatarsDirPath];
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

+ (NSSet<NSString *> *)allProfileAvatarFilePaths
{
    NSString *profileAvatarsDirPath = self.profileAvatarsDirPath;
    NSMutableSet<NSString *> *profileAvatarFilePaths = [NSMutableSet new];

    [OWSPrimaryStorage.sharedManager.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [OWSUserProfile
            enumerateCollectionObjectsWithTransaction:transaction
                                           usingBlock:^(id object, BOOL *stop) {
                                               if (![object isKindOfClass:[OWSUserProfile class]]) {
                                                   OWSFailDebug(
                                                       @"unexpected object in user profiles: %@", [object class]);
                                                   return;
                                               }
                                               OWSUserProfile *userProfile = object;
                                               if (!userProfile.avatarFileName) {
                                                   return;
                                               }
                                               NSString *filePath = [profileAvatarsDirPath
                                                   stringByAppendingPathComponent:userProfile.avatarFileName];
                                               [profileAvatarFilePaths addObject:filePath];
                                           }];
    }];
    return [profileAvatarFilePaths copy];
}

@end

NS_ASSUME_NONNULL_END
