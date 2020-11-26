//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSUserProfile.h"
#import <PromiseKit/AnyPromise.h>
#import <SessionMessagingKit/OWSPrimaryStorage.h>
#import <SessionMessagingKit/SSKEnvironment.h>
#import <SessionMessagingKit/TSAccountManager.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSObject+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
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
    __block OWSUserProfile *userProfile;

    [dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        userProfile = [OWSUserProfile fetchObjectWithUniqueID:recipientId transaction:transaction];
    }];

    if (userProfile != nil) {
        return userProfile;
    }

    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        userProfile = [OWSUserProfile getOrBuildUserProfileForRecipientId:recipientId transaction:transaction];
    }];

    return userProfile;
}

+ (OWSUserProfile *)getOrBuildUserProfileForRecipientId:(NSString *)recipientId transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSUserProfile *userProfile = [OWSUserProfile fetchObjectWithUniqueID:recipientId transaction:transaction];

    if (!userProfile) {
        userProfile = [[OWSUserProfile alloc] initWithRecipientId:recipientId];

        if ([recipientId isEqualToString:kLocalProfileUniqueId]) {
            [userProfile updateWithProfileKey:[OWSAES256Key generateRandomKey]
                                  transaction:transaction
                                   completion:nil];
        }
    }

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

    _recipientId = recipientId;

    return self;
}

#pragma mark - Dependencies

- (TSAccountManager *)tsAccountManager
{
    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark -

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
        [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [self applyChanges:changeBlock functionName:functionName transaction:transaction completion:completion];
        }];
}
    
- (void)applyChanges:(void (^)(id))changeBlock
        functionName:(const char *)functionName
        transaction:(YapDatabaseReadWriteTransaction *)transaction
          completion:(nullable OWSUserProfileCompletion)completion
    {
    // self might be the latest instance, so take a "before" snapshot
    // before any changes have been made.
    __block NSDictionary *beforeSnapshot = [self.dictionaryValue copy];

    changeBlock(self);

    BOOL didChange = YES;
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
            didChange = NO;
        } else {
            [latestInstance saveWithTransaction:transaction];
        }
    } else {
        [self saveWithTransaction:transaction];
    }

    if (completion) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), completion);
    }

    if (!didChange) {
        return;
    }
    
    NSString *masterDeviceHexEncodedPublicKey = [NSUserDefaults.standardUserDefaults stringForKey:@"masterDeviceHexEncodedPublicKey"];
    BOOL isLocalUserProfile = [self.recipientId isEqualToString:kLocalProfileUniqueId] || (masterDeviceHexEncodedPublicKey != nil && [self.recipientId isEqualToString:masterDeviceHexEncodedPublicKey]);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (isLocalUserProfile) {
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
                 transaction:(YapDatabaseReadWriteTransaction *)transaction
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
          transaction:transaction
            completion:completion];
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
        // [userProfile setProfileName:nil]; - Loki disabled until we include profile name inside the encrypted profile from the url
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
    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self updateWithProfileKey:profileKey transaction:transaction completion:completion];
    }];
}

- (void)updateWithProfileKey:(OWSAES256Key *)profileKey
                transaction:(YapDatabaseReadWriteTransaction *)transaction
                  completion:(nullable OWSUserProfileCompletion)completion
{
    [self applyChanges:^(OWSUserProfile *userProfile) {
        [userProfile setProfileKey:profileKey];
    }
          functionName:__PRETTY_FUNCTION__
           transaction:transaction
            completion:completion];
}

#pragma mark - Database Connection Accessors

- (YapDatabaseConnection *)dbReadConnection
{
    return TSYapDatabaseObject.dbReadConnection;
}

+ (YapDatabaseConnection *)dbReadConnection
{
    return TSYapDatabaseObject.dbReadConnection;
}

- (YapDatabaseConnection *)dbReadWriteConnection
{
    return TSYapDatabaseObject.dbReadWriteConnection;
}

+ (YapDatabaseConnection *)dbReadWriteConnection
{
    return TSYapDatabaseObject.dbReadWriteConnection;
}

// This should only be used in verbose, developer-only logs.
- (NSString *)debugDescription
{
    return [NSString stringWithFormat:@"%@ %p %@ %lu %@ %@ %@",
                     @"OWSUserProfile",
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
    if (filename.length <= 0) { return @""; };

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
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:[self profileAvatarsDirPath] error:&error];
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
