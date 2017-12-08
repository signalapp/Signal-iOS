//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSUserProfile.h"
#import "NSString+OWS.h"
#import <SignalServiceKit/Cryptography.h>
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

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

- (void)updateWithProfileName:(nullable NSString *)profileName
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               avatarFileName:(nullable NSString *)avatarFileName
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setProfileName:[profileName ows_stripped]];
                                     [userProfile setAvatarUrlPath:avatarUrlPath];
                                     [userProfile setAvatarFileName:avatarFileName];
                                 }];
    }
                          completionBlock:completion];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               avatarFileName:(nullable NSString *)avatarFileName
               lastUpdateDate:(nullable NSDate *)lastUpdateDate
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setProfileName:[profileName ows_stripped]];
                                     [userProfile setAvatarUrlPath:avatarUrlPath];
                                     [userProfile setAvatarFileName:avatarFileName];
                                     [userProfile setLastUpdateDate:lastUpdateDate];
                                 }];
    }
                          completionBlock:completion];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               lastUpdateDate:(nullable NSDate *)lastUpdateDate
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setProfileName:[profileName ows_stripped]];
                                     [userProfile setAvatarUrlPath:avatarUrlPath];
                                     [userProfile setLastUpdateDate:lastUpdateDate];
                                 }];
    }
                          completionBlock:completion];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                   profileKey:(OWSAES256Key *)profileKey
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               avatarFileName:(nullable NSString *)avatarFileName
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setProfileName:[profileName ows_stripped]];
                                     [userProfile setProfileKey:profileKey];
                                     [userProfile setAvatarUrlPath:avatarUrlPath];
                                     [userProfile setAvatarFileName:avatarFileName];
                                 }];
    }
                          completionBlock:completion];
}

- (void)updateWithAvatarUrlPath:(nullable NSString *)avatarUrlPath
                 avatarFileName:(nullable NSString *)avatarFileName
                   dbConnection:(YapDatabaseConnection *)dbConnection
                     completion:(nullable OWSUserProfileCompletion)completion
{
    [dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setAvatarUrlPath:avatarUrlPath];
                                     [userProfile setAvatarFileName:avatarFileName];
                                 }];
    }
                          completionBlock:completion];
}

- (void)updateWithAvatarFileName:(nullable NSString *)avatarFileName
                    dbConnection:(YapDatabaseConnection *)dbConnection
                      completion:(nullable OWSUserProfileCompletion)completion
{
    [dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setAvatarFileName:avatarFileName];
                                 }];
    }
                          completionBlock:completion];
}

- (void)updateWithLastUpdateDate:(nullable NSDate *)lastUpdateDate
                    dbConnection:(YapDatabaseConnection *)dbConnection
                      completion:(nullable OWSUserProfileCompletion)completion
{
    [dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setLastUpdateDate:lastUpdateDate];
                                 }];
    }
                          completionBlock:completion];
}

- (void)clearWithProfileKey:(OWSAES256Key *)profileKey
               dbConnection:(YapDatabaseConnection *)dbConnection
                 completion:(nullable OWSUserProfileCompletion)completion;
{
    OWSAssert(profileKey);

    [dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setProfileKey:profileKey];
                                     [userProfile setProfileName:nil];
                                     [userProfile setAvatarUrlPath:nil];
                                     [userProfile setAvatarFileName:nil];
                                     [userProfile setLastUpdateDate:nil];
                                 }];
    }
                          completionBlock:completion];
}

- (void)updateImmediatelyWithProfileKey:(OWSAES256Key *)profileKey
                           dbConnection:(YapDatabaseConnection *)dbConnection
                             completion:(nullable OWSUserProfileCompletion)completion;
{
    OWSAssert(profileKey);

    self.profileKey = profileKey;

    [dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     [userProfile setProfileKey:profileKey];
                                 }];
    }
                          completionBlock:completion];
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
