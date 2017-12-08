//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSUserProfile.h"
#import "NSString+OWS.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/Cryptography.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <YapDatabase/YapDatabaseConnection.h>

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
            [userProfile updateImmediatelyWithProfileKey:[OWSAES256Key generateRandomKey]
                                            dbConnection:dbConnection
                                              completion:nil];
        }
    }

    OWSAssert(userProfile);

    return userProfile;
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

- (void)finalizeWithCompletion:(nullable OWSUserProfileCompletion)externalCompletion
{
    if (externalCompletion) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), externalCompletion);
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
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setProfileName:[profileName ows_stripped]];
                                     [userProfile setAvatarUrlPath:avatarUrlPath];
                                     [userProfile setAvatarFileName:avatarFileName];
                                 }];
    }];
    [self finalizeWithCompletion:completion];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               avatarFileName:(nullable NSString *)avatarFileName
               lastUpdateDate:(nullable NSDate *)lastUpdateDate
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setProfileName:[profileName ows_stripped]];
                                     [userProfile setAvatarUrlPath:avatarUrlPath];
                                     [userProfile setAvatarFileName:avatarFileName];
                                     [userProfile setLastUpdateDate:lastUpdateDate];
                                 }];
    }];
    [self finalizeWithCompletion:completion];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               lastUpdateDate:(nullable NSDate *)lastUpdateDate
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setProfileName:[profileName ows_stripped]];
                                     [userProfile setAvatarUrlPath:avatarUrlPath];
                                     [userProfile setLastUpdateDate:lastUpdateDate];
                                 }];
    }];
    [self finalizeWithCompletion:completion];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                   profileKey:(OWSAES256Key *)profileKey
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               avatarFileName:(nullable NSString *)avatarFileName
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setProfileName:[profileName ows_stripped]];
                                     [userProfile setProfileKey:profileKey];
                                     [userProfile setAvatarUrlPath:avatarUrlPath];
                                     [userProfile setAvatarFileName:avatarFileName];
                                 }];
    }];
    [self finalizeWithCompletion:completion];
}

- (void)updateWithAvatarUrlPath:(nullable NSString *)avatarUrlPath
                 avatarFileName:(nullable NSString *)avatarFileName
                   dbConnection:(YapDatabaseConnection *)dbConnection
                     completion:(nullable OWSUserProfileCompletion)completion
{
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setAvatarUrlPath:avatarUrlPath];
                                     [userProfile setAvatarFileName:avatarFileName];
                                 }];
    }];
    [self finalizeWithCompletion:completion];
}

- (void)updateWithAvatarFileName:(nullable NSString *)avatarFileName
                    dbConnection:(YapDatabaseConnection *)dbConnection
                      completion:(nullable OWSUserProfileCompletion)completion
{
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setAvatarFileName:avatarFileName];
                                 }];
    }];
    [self finalizeWithCompletion:completion];
}

- (void)updateWithLastUpdateDate:(nullable NSDate *)lastUpdateDate
                    dbConnection:(YapDatabaseConnection *)dbConnection
                      completion:(nullable OWSUserProfileCompletion)completion
{
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setLastUpdateDate:lastUpdateDate];
                                 }];
    }];
    [self finalizeWithCompletion:completion];
}

- (void)clearWithProfileKey:(OWSAES256Key *)profileKey
               dbConnection:(YapDatabaseConnection *)dbConnection
                 completion:(nullable OWSUserProfileCompletion)completion;
{
    OWSAssert(profileKey);

    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setProfileKey:profileKey];
                                     [userProfile setProfileName:nil];
                                     [userProfile setAvatarUrlPath:nil];
                                     [userProfile setAvatarFileName:nil];
                                     [userProfile setLastUpdateDate:nil];
                                 }];
    }];
    [self finalizeWithCompletion:completion];
}

- (void)updateImmediatelyWithProfileKey:(OWSAES256Key *)profileKey
                           dbConnection:(YapDatabaseConnection *)dbConnection
                             completion:(nullable OWSUserProfileCompletion)completion;
{
    OWSAssert(profileKey);

    self.profileKey = profileKey;

    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setProfileKey:profileKey];
                                 }];
    }];
    [self finalizeWithCompletion:completion];
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

@end

NS_ASSUME_NONNULL_END
