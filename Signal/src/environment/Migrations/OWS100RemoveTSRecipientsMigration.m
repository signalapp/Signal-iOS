//  Created by Michael Kirk on 9/28/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWS100RemoveTSRecipientsMigration.h"
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

// Increment a similar constant for every future DBMigration
static NSString *const OWS100RemoveTSRecipientsMigrationId = @"100";

@implementation OWS100RemoveTSRecipientsMigration

+ (NSString *)migrationId
{
    return OWS100RemoveTSRecipientsMigrationId;
}

- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSUInteger legacyRecipientCount = [transaction numberOfKeysInCollection:@"TSRecipient"];
    DDLogWarn(@"Removing %lu objects from TSRecipient collection", (unsigned long)legacyRecipientCount);
    [transaction removeAllObjectsInCollection:@"TSRecipient"];
}

@end

NS_ASSUME_NONNULL_END
