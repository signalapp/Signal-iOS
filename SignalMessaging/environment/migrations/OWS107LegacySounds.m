//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWS107LegacySounds.h"
#import "OWSSounds.h"
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

// Increment a similar constant for every future DBMigration
static NSString *const OWS107LegacySoundsMigrationId = @"107";

@implementation OWS107LegacySounds

+ (NSString *)migrationId
{
    return OWS107LegacySoundsMigrationId;
}

- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    [OWSSounds setGlobalNotificationSound:OWSSound_SignalClassic transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
