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

- (void)finalizeWithCompletion:(nullable OWSUserProfileCompletion)externalCompletion didChange:(BOOL)didChange
{
    if (externalCompletion) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), externalCompletion);
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
    __block BOOL didChange = NO;
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     didChange |= [self didStringChange:userProfile.profileName
                                                               newValue:[profileName ows_stripped]];
                                     didChange |=
                                         [self didStringChange:userProfile.avatarUrlPath newValue:avatarUrlPath];
                                     didChange |=
                                         [self didStringChange:userProfile.avatarFileName newValue:avatarFileName];

                                     [userProfile setProfileName:[profileName ows_stripped]];
                                     [userProfile setAvatarUrlPath:avatarUrlPath];
                                     [userProfile setAvatarFileName:avatarFileName];
                                 }
                               saveIfMissing:YES];
    }];
    [self finalizeWithCompletion:completion didChange:didChange];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               avatarFileName:(nullable NSString *)avatarFileName
               lastUpdateDate:(nullable NSDate *)lastUpdateDate
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    __block BOOL didChange = NO;
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self
            applyChangeToSelfAndLatestCopy:transaction
                               changeBlock:^(OWSUserProfile *userProfile) {
                                   didChange |= [self didStringChange:userProfile.profileName
                                                             newValue:[profileName ows_stripped]];
                                   didChange |= [self didStringChange:userProfile.avatarUrlPath newValue:avatarUrlPath];
                                   didChange |=
                                       [self didStringChange:userProfile.avatarFileName newValue:avatarFileName];
                                   didChange |= [self didDateChange:userProfile.lastUpdateDate newValue:lastUpdateDate];

                                   [userProfile setProfileName:[profileName ows_stripped]];
                                   [userProfile setAvatarUrlPath:avatarUrlPath];
                                   [userProfile setAvatarFileName:avatarFileName];
                                   [userProfile setLastUpdateDate:lastUpdateDate];
                               }
                             saveIfMissing:YES];
    }];
    [self finalizeWithCompletion:completion didChange:didChange];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               lastUpdateDate:(nullable NSDate *)lastUpdateDate
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    __block BOOL didChange = NO;
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self
            applyChangeToSelfAndLatestCopy:transaction
                               changeBlock:^(OWSUserProfile *userProfile) {
                                   didChange |= [self didStringChange:userProfile.profileName
                                                             newValue:[profileName ows_stripped]];
                                   didChange |= [self didStringChange:userProfile.avatarUrlPath newValue:avatarUrlPath];
                                   didChange |= [self didDateChange:userProfile.lastUpdateDate newValue:lastUpdateDate];

                                   [userProfile setProfileName:[profileName ows_stripped]];
                                   [userProfile setAvatarUrlPath:avatarUrlPath];
                                   [userProfile setLastUpdateDate:lastUpdateDate];
                               }
                             saveIfMissing:YES];
    }];
    [self finalizeWithCompletion:completion didChange:didChange];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                   profileKey:(OWSAES256Key *)profileKey
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               avatarFileName:(nullable NSString *)avatarFileName
                 dbConnection:(YapDatabaseConnection *)dbConnection
                   completion:(nullable OWSUserProfileCompletion)completion
{
    __block BOOL didChange = NO;
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     didChange |= [self didStringChange:userProfile.profileName
                                                               newValue:[profileName ows_stripped]];
                                     didChange |= [self didKeyChange:userProfile.profileKey newValue:profileKey];
                                     didChange |=
                                         [self didStringChange:userProfile.avatarUrlPath newValue:avatarUrlPath];
                                     didChange |=
                                         [self didStringChange:userProfile.avatarFileName newValue:avatarFileName];

                                     [userProfile setProfileName:[profileName ows_stripped]];
                                     [userProfile setProfileKey:profileKey];
                                     [userProfile setAvatarUrlPath:avatarUrlPath];
                                     [userProfile setAvatarFileName:avatarFileName];
                                 }
                               saveIfMissing:YES];
    }];
    [self finalizeWithCompletion:completion didChange:didChange];
}

- (void)updateWithAvatarUrlPath:(nullable NSString *)avatarUrlPath
                 avatarFileName:(nullable NSString *)avatarFileName
                   dbConnection:(YapDatabaseConnection *)dbConnection
                     completion:(nullable OWSUserProfileCompletion)completion
{
    __block BOOL didChange = NO;
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     didChange |=
                                         [self didStringChange:userProfile.avatarUrlPath newValue:avatarUrlPath];
                                     didChange |=
                                         [self didStringChange:userProfile.avatarFileName newValue:avatarFileName];

                                     [userProfile setAvatarUrlPath:avatarUrlPath];
                                     [userProfile setAvatarFileName:avatarFileName];
                                 }
                               saveIfMissing:YES];
    }];
    [self finalizeWithCompletion:completion didChange:didChange];
}

- (void)updateWithAvatarFileName:(nullable NSString *)avatarFileName
                    dbConnection:(YapDatabaseConnection *)dbConnection
                      completion:(nullable OWSUserProfileCompletion)completion
{
    __block BOOL didChange = NO;
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     didChange |=
                                         [self didStringChange:userProfile.avatarFileName newValue:avatarFileName];

                                     [userProfile setAvatarFileName:avatarFileName];
                                 }
                               saveIfMissing:YES];
    }];
    [self finalizeWithCompletion:completion didChange:didChange];
}

- (void)updateWithLastUpdateDate:(nullable NSDate *)lastUpdateDate
                    dbConnection:(YapDatabaseConnection *)dbConnection
                      completion:(nullable OWSUserProfileCompletion)completion
{
    __block BOOL didChange = NO;
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     didChange |=
                                         [self didDateChange:userProfile.lastUpdateDate newValue:lastUpdateDate];

                                     [userProfile setLastUpdateDate:lastUpdateDate];
                                 }
                               saveIfMissing:YES];
    }];
    [self finalizeWithCompletion:completion didChange:didChange];
}

- (void)clearWithProfileKey:(OWSAES256Key *)profileKey
               dbConnection:(YapDatabaseConnection *)dbConnection
                 completion:(nullable OWSUserProfileCompletion)completion;
{
    OWSAssert(profileKey);

    __block BOOL didChange = NO;
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     didChange |= [self didKeyChange:userProfile.profileKey newValue:profileKey];
                                     didChange |= [self didStringChange:userProfile.profileName newValue:nil];
                                     didChange |= [self didStringChange:userProfile.avatarUrlPath newValue:nil];
                                     didChange |= [self didStringChange:userProfile.avatarFileName newValue:nil];
                                     didChange |= [self didDateChange:userProfile.lastUpdateDate newValue:nil];

                                     [userProfile setProfileKey:profileKey];
                                     [userProfile setProfileName:nil];
                                     [userProfile setAvatarUrlPath:nil];
                                     [userProfile setAvatarFileName:nil];
                                     [userProfile setLastUpdateDate:nil];
                                 }
                               saveIfMissing:YES];
    }];
    [self finalizeWithCompletion:completion didChange:didChange];
}

- (void)updateWithProfileKey:(OWSAES256Key *)profileKey
                dbConnection:(YapDatabaseConnection *)dbConnection
                  completion:(nullable OWSUserProfileCompletion)completion;
{
    OWSAssert(profileKey);

    self.profileKey = profileKey;

    __block BOOL didChange = NO;
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(OWSUserProfile *userProfile) {
                                     didChange |= [self didKeyChange:userProfile.profileKey newValue:profileKey];

                                     [userProfile setProfileKey:profileKey];
                                 }
                               saveIfMissing:YES];
    }];
    [self finalizeWithCompletion:completion didChange:didChange];
}

- (BOOL)didStringChange:(NSString *_Nullable)oldValue newValue:(NSString *_Nullable)newValue
{
    if (!oldValue && !newValue) {
        return NO;
    } else if (!oldValue || !newValue) {
        return YES;
    } else {
        return ![oldValue isEqualToString:newValue];
    }
}

- (BOOL)didDateChange:(NSDate *_Nullable)oldValue newValue:(NSDate *_Nullable)newValue
{
    if (!oldValue && !newValue) {
        return NO;
    } else if (!oldValue || !newValue) {
        return YES;
    } else {
        return ![oldValue isEqualToDate:newValue];
    }
}

- (BOOL)didKeyChange:(OWSAES256Key *_Nullable)oldValue newValue:(OWSAES256Key *_Nullable)newValue
{
    if (!oldValue && !newValue) {
        return NO;
    } else if (!oldValue || !newValue) {
        return YES;
    } else {
        return ![oldValue.keyData isEqualToData:newValue.keyData];
    }
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
