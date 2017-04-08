//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWS102MoveLoggingPreferenceToUserDefaults.h"
#import "DebugLogger.h"
#import "Environment.h"
#import "PropertyListPreferences.h"

// Increment a similar constant for every future DBMigration
static NSString *const OWS102MoveLoggingPreferenceToUserDefaultsMigrationId = @"102";

@implementation OWS102MoveLoggingPreferenceToUserDefaults

+ (NSString *)migrationId
{
    return OWS102MoveLoggingPreferenceToUserDefaultsMigrationId;
}

- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    DDLogWarn(@"[OWS102MoveLoggingPreferenceToUserDefaultsMigrationId] copying existing logging preference to "
              @"NSUserDefaults");

    NSNumber *existingValue = [transaction objectForKey:PropertyListPreferencesKeyEnableDebugLog
                                           inCollection:PropertyListPreferencesSignalDatabaseCollection];

    if (existingValue) {
        DDLogInfo(@"%@ assigning existing value: %@", self.tag, existingValue);
        [PropertyListPreferences setLoggingEnabled:[existingValue boolValue]];

        if (![existingValue boolValue]) {
            DDLogInfo(@"%@ Disabling file logger after one-time log settings migration.", self.tag);
            // Since we're migrating, we didn't have the appropriate value on startup, and incorrectly started logging.
            [DebugLogger.sharedLogger disableFileLogging];
        } else {
            DDLogInfo(@"%@ Continuing to log after one-time log settings migration.", self.tag);
        }
    } else {
        DDLogInfo(@"%@ not assigning any value, since no previous value was stored.", self.tag);
    }
}


#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
