//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSUserProfile.h"
#import "NSString+OWS.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/Cryptography.h>
#import <SignalServiceKit/NSData+hexString.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
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
@property (atomic, nullable) NSDate *lastUpdateDate;

@end

#pragma mark -

@implementation OWSUserProfile

+ (NSString *)collection
{
    // Legacy class name.
    return @"UserProfile";
}

+ (OWSUserProfile *)getOrBuildUserProfileForRecipientId:(NSString *)recipientId
                                           dbConnection:(YapDatabaseConnection *)dbConnection
{
    OWSAssert(recipientId.length > 0);

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

    OWSAssert(userProfile);

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

    OWSAssert(recipientId.length > 0);
    _recipientId = recipientId;

    return self;
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
    NSDictionary *beforeSnapshot = self.dictionaryValue;
    
    changeBlock(self);

    __block BOOL didChangeSignificantly = NO;
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSString *collection = [[self class] collection];
        OWSUserProfile *latestInstance = [transaction objectForKey:self.uniqueId inCollection:collection];
        if (!latestInstance) {
            didChangeSignificantly = YES;
            [self saveWithTransaction:transaction];
        } else {
            changeBlock(latestInstance);

            BOOL needsSave = NO;
            NSDictionary *afterSnapshot = latestInstance.dictionaryValue;
            if (![beforeSnapshot.allKeys isEqual:afterSnapshot.allKeys]) {
                needsSave = YES;
                didChangeSignificantly = YES;
            } else {
                for (id key in beforeSnapshot) {
                    id beforeValue = beforeSnapshot[key];
                    id afterValue = afterSnapshot[key];
                    if (![beforeValue isEqual:afterValue]) {
                        if ([key isEqual:@"lastUpdateDate"]) {
                            // lastUpdatedDate changes all the time to debounce when we poll the
                            // service, but it's not a significant change that should affect the user.
                            needsSave = YES;
                            
                            // Continue looking for any significant changes
                            continue;
                        }
                        
                        // Otherwise we should notify the system.
                        didChangeSignificantly = YES;
                        break;
                    }
                }
            }
            
            if (needsSave) {
                DDLogVerbose(@"%@ Saving changed profile in %s: %@", self.logTag, functionName, self.debugDescription);
                [latestInstance saveWithTransaction:transaction];
            }
        }
    }];

    if (completion) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), completion);
    }

    if (!didChangeSignificantly) {
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
        [userProfile setAvatarUrlPath:avatarUrlPath];
        [userProfile setAvatarFileName:avatarFileName];
    }
          functionName:__PRETTY_FUNCTION__
          dbConnection:dbConnection
            completion:completion];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               avatarFileName:(nullable NSString *)avatarFileName
               lastUpdateDate:(nullable NSDate *)lastUpdateDate
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [self applyChanges:^(OWSUserProfile *userProfile) {
        [userProfile setProfileName:[profileName ows_stripped]];
        [userProfile setAvatarUrlPath:avatarUrlPath];
        [userProfile setAvatarFileName:avatarFileName];
        [userProfile setLastUpdateDate:lastUpdateDate];
    }
          functionName:__PRETTY_FUNCTION__
          dbConnection:dbConnection
            completion:completion];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               lastUpdateDate:(nullable NSDate *)lastUpdateDate
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [self applyChanges:^(OWSUserProfile *userProfile) {
        [userProfile setProfileName:[profileName ows_stripped]];
        [userProfile setAvatarUrlPath:avatarUrlPath];
        [userProfile setLastUpdateDate:lastUpdateDate];
    }
          functionName:__PRETTY_FUNCTION__
          dbConnection:dbConnection
            completion:completion];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                   profileKey:(OWSAES256Key *)profileKey
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               avatarFileName:(nullable NSString *)avatarFileName
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [self applyChanges:^(OWSUserProfile *userProfile) {
        [userProfile setProfileName:[profileName ows_stripped]];
        [userProfile setProfileKey:profileKey];
        [userProfile setAvatarUrlPath:avatarUrlPath];
        [userProfile setAvatarFileName:avatarFileName];
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

- (void)updateWithLastUpdateDate:(nullable NSDate *)lastUpdateDate
                    dbConnection:(YapDatabaseConnection *)dbConnection
                      completion:(nullable OWSUserProfileCompletion)completion
{
    [self applyChanges:^(OWSUserProfile *userProfile) {
        [userProfile setLastUpdateDate:lastUpdateDate];
    }
          functionName:__PRETTY_FUNCTION__
          dbConnection:dbConnection
            completion:completion];
}

- (void)clearWithProfileKey:(OWSAES256Key *)profileKey
               dbConnection:(YapDatabaseConnection *)dbConnection
                 completion:(nullable OWSUserProfileCompletion)completion;
{
    [self applyChanges:^(OWSUserProfile *userProfile) {
        [userProfile setProfileKey:profileKey];
        [userProfile setProfileName:nil];
        [userProfile setAvatarUrlPath:nil];
        [userProfile setAvatarFileName:nil];
        [userProfile setLastUpdateDate:nil];
    }
          functionName:__PRETTY_FUNCTION__
          dbConnection:dbConnection
            completion:completion];
}

- (void)updateWithProfileKey:(OWSAES256Key *)profileKey
                dbConnection:(YapDatabaseConnection *)dbConnection
                  completion:(nullable OWSUserProfileCompletion)completion;
{
    OWSAssert(profileKey);

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
    OWSFail(@"%@ UserProfile should always use OWSProfileManager's database connection.", self.logTag);

    return TSYapDatabaseObject.dbReadConnection;
}

+ (YapDatabaseConnection *)dbReadConnection
{
    OWSFail(@"%@ UserProfile should always use OWSProfileManager's database connection.", self.logTag);

    return TSYapDatabaseObject.dbReadConnection;
}

- (YapDatabaseConnection *)dbReadWriteConnection
{
    OWSFail(@"%@ UserProfile should always use OWSProfileManager's database connection.", self.logTag);

    return TSYapDatabaseObject.dbReadWriteConnection;
}

+ (YapDatabaseConnection *)dbReadWriteConnection
{
    OWSFail(@"%@ UserProfile should always use OWSProfileManager's database connection.", self.logTag);

    return TSYapDatabaseObject.dbReadWriteConnection;
}

// This should only be used in verbose, developer-only logs.
- (NSString *)debugDescription
{
    return [NSString stringWithFormat:@"%@ %p %@ %zd %@ %@ %@ %f",
                     self.logTag,
                     self,
                     self.recipientId,
                     self.profileKey.keyData.length,
                     self.profileName,
                     self.avatarUrlPath,
                     self.avatarFileName,
                     self.lastUpdateDate.timeIntervalSinceNow];
}

@end

NS_ASSUME_NONNULL_END
