//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWS101ExistingUsersBlockOnIdentityChange.h"
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

// Increment a similar constant for every future DBMigration
static NSString *const OWS101ExistingUsersBlockOnIdentityChangeMigrationId = @"101";

/**
 * This migration is no longer necessary, but deleting a class is complicated in Yap
 * and involves writing another migration to remove the previous. It seemed like the
 * simplest/safest thing to do would be to just leave it.
 */
@implementation OWS101ExistingUsersBlockOnIdentityChange

+ (NSString *)migrationId
{
    return OWS101ExistingUsersBlockOnIdentityChangeMigrationId;
}

- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    OWSFailDebug(@"[OWS101ExistingUsersBlockOnIdentityChange] has been obviated.");
}

@end

NS_ASSUME_NONNULL_END
