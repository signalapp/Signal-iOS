//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWS107LegacySounds.h"
#import "OWSSounds.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
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

    [OWSSounds setGlobalNotificationSound:OWSStandardSound_SignalClassic transaction:transaction.asAnyWrite];
}

@end

NS_ASSUME_NONNULL_END
