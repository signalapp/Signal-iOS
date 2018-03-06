//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseMigrationRunner.h"
#import "OWS100RemoveTSRecipientsMigration.h"
#import "OWS102MoveLoggingPreferenceToUserDefaults.h"
#import "OWS103EnableVideoCalling.h"
#import "OWS104CreateRecipientIdentities.h"
#import "OWS105AttachmentFilePaths.h"
#import "OWS107LegacySounds.h"
#import "OWS108CallLoggingPreference.h"
#import "OWSDatabaseMigration.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppContext.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDatabaseMigrationRunner

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];
    if (!self) {
        return self;
    }

    _primaryStorage = primaryStorage;

    return self;
}

// This should all migrations which do NOT qualify as safeBlockingMigrations:
- (NSArray<OWSDatabaseMigration *> *)allMigrations
{
    OWSPrimaryStorage *primaryStorage = OWSPrimaryStorage.sharedManager;
    return @[
        [[OWS100RemoveTSRecipientsMigration alloc] initWithPrimaryStorage:primaryStorage],
        [[OWS102MoveLoggingPreferenceToUserDefaults alloc] initWithPrimaryStorage:primaryStorage],
        [[OWS103EnableVideoCalling alloc] initWithPrimaryStorage:primaryStorage],
        [[OWS104CreateRecipientIdentities alloc] initWithPrimaryStorage:primaryStorage],
        [[OWS105AttachmentFilePaths alloc] initWithPrimaryStorage:primaryStorage],
        [[OWS106EnsureProfileComplete alloc] initWithPrimaryStorage:primaryStorage],
        [[OWS107LegacySounds alloc] initWithPrimaryStorage:primaryStorage],
        [[OWS108CallLoggingPreference alloc] initWithPrimaryStorage:primaryStorage]
    ];
}

- (void)assumeAllExistingMigrationsRun
{
    for (OWSDatabaseMigration *migration in self.allMigrations) {
        DDLogInfo(@"%@ Skipping migration on new install: %@", self.logTag, migration);
        [migration save];
    }
}

- (void)runAllOutstandingWithCompletion:(OWSDatabaseMigrationCompletion)completion
{
    [self runMigrations:self.allMigrations completion:completion];
}

- (void)runMigrations:(NSArray<OWSDatabaseMigration *> *)migrations
           completion:(OWSDatabaseMigrationCompletion)completion
{
    OWSAssert(migrations);
    OWSAssert(completion);

    NSMutableArray<OWSDatabaseMigration *> *migrationsToRun = [NSMutableArray new];
    for (OWSDatabaseMigration *migration in migrations) {
        if ([OWSDatabaseMigration fetchObjectWithUniqueID:migration.uniqueId] == nil) {
            [migrationsToRun addObject:migration];
        }
    }

    if (migrationsToRun.count < 1) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
        return;
    }

    NSUInteger totalMigrationCount = migrationsToRun.count;
    __block NSUInteger completedMigrationCount = 0;
    // Call the completion exactly once, when the last migration completes.
    void (^checkMigrationCompletion)(void) = ^{
        @synchronized(self)
        {
            completedMigrationCount++;
            if (completedMigrationCount == totalMigrationCount) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion();
                });
            }
        }
    };

    for (OWSDatabaseMigration *migration in migrationsToRun) {
        if ([OWSDatabaseMigration fetchObjectWithUniqueID:migration.uniqueId]) {
            DDLogDebug(@"%@ Skipping previously run migration: %@", self.logTag, migration);
        } else {
            DDLogWarn(@"%@ Running migration: %@", self.logTag, migration);
            [migration runUpWithCompletion:checkMigrationCompletion];
        }
    }
}

@end

NS_ASSUME_NONNULL_END
