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
#import "OWS109OutgoingMessageState.h"
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
        [[OWS108CallLoggingPreference alloc] initWithPrimaryStorage:primaryStorage],
        [[OWS109OutgoingMessageState alloc] initWithPrimaryStorage:primaryStorage]
    ];
}

- (void)assumeAllExistingMigrationsRun
{
    for (OWSDatabaseMigration *migration in self.allMigrations) {
        OWSLogInfo(@"Skipping migration on new install: %@", migration);
        [migration save];
    }
}

- (void)runAllOutstandingWithCompletion:(OWSDatabaseMigrationCompletion)completion
{
    [self runMigrations:[self.allMigrations mutableCopy] completion:completion];
}

// Run migrations serially to:
//
// * Ensure predictable ordering.
// * Prevent them from interfering with each other (e.g. deadlock).
- (void)runMigrations:(NSMutableArray<OWSDatabaseMigration *> *)migrations
           completion:(OWSDatabaseMigrationCompletion)completion
{
    OWSAssertDebug(migrations);
    OWSAssertDebug(completion);

    // If there are no more migrations to run, complete.
    if (migrations.count < 1) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
        return;
    }

    // Pop next migration from front of queue.
    OWSDatabaseMigration *migration = migrations.firstObject;
    [migrations removeObjectAtIndex:0];

    // If migration has already been run, skip it.
    if ([OWSDatabaseMigration fetchObjectWithUniqueID:migration.uniqueId] != nil) {
        [self runMigrations:migrations completion:completion];
        return;
    }

    OWSLogInfo(@"Running migration: %@", migration);
    [migration runUpWithCompletion:^{
        OWSLogInfo(@"Migration complete: %@", migration);
        [self runMigrations:migrations completion:completion];
    }];
}

@end

NS_ASSUME_NONNULL_END
