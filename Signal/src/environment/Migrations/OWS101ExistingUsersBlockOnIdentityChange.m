//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWS101ExistingUsersBlockOnIdentityChange.h"
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

// Increment a similar constant for every future DBMigration
static NSString *const OWS101ExistingUsersBlockOnIdentityChangeMigrationId = @"101";

@implementation OWS101ExistingUsersBlockOnIdentityChange

+ (NSString *)migrationId
{
    return OWS101ExistingUsersBlockOnIdentityChangeMigrationId;
}

- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    DDLogWarn(@"[OWS101ExistingUsersBlockOnIdentityChange] has been obviated.");
    //    DDLogWarn(@"[OWS101ExistingUsersBlockOnIdentityChange] Opting existing user into 'blocking' on identity
    //    changes."); TSPrivacyPreferences *preferences = [TSPrivacyPreferences sharedInstance];
    //    preferences.shouldBlockOnIdentityChange = YES;
    //    [preferences saveWithTransaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
