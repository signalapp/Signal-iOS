//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWS102MoveLoggingPreferenceToUserDefaults.h"
#import "DebugLogger.h"
#import "Environment.h"
#import "OWSPreferences.h"
#import <YapDatabase/YapDatabase.h>

// Increment a similar constant for every future DBMigration
static NSString *const OWS102MoveLoggingPreferenceToUserDefaultsMigrationId = @"102";

@implementation OWS102MoveLoggingPreferenceToUserDefaults

+ (NSString *)migrationId
{
    return OWS102MoveLoggingPreferenceToUserDefaultsMigrationId;
}

- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);

    DDLogWarn(@"[OWS102MoveLoggingPreferenceToUserDefaultsMigrationId] copying existing logging preference to "
              @"NSUserDefaults");

    NSNumber *existingValue =
        [transaction objectForKey:OWSPreferencesKeyEnableDebugLog inCollection:OWSPreferencesSignalDatabaseCollection];

    if (existingValue) {
        DDLogInfo(@"%@ assigning existing value: %@", self.logTag, existingValue);
        [OWSPreferences setIsLoggingEnabled:[existingValue boolValue]];

        if (![existingValue boolValue]) {
            DDLogInfo(@"%@ Disabling file logger after one-time log settings migration.", self.logTag);
            // Since we're migrating, we didn't have the appropriate value on startup, and incorrectly started logging.
            [DebugLogger.sharedLogger disableFileLogging];
        } else {
            DDLogInfo(@"%@ Continuing to log after one-time log settings migration.", self.logTag);
        }
    } else {
        DDLogInfo(@"%@ not assigning any value, since no previous value was stored.", self.logTag);
    }
}

@end
