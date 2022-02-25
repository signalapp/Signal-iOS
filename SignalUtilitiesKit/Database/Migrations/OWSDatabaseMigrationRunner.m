//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseMigrationRunner.h"
#import "OWSDatabaseMigration.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SessionUtilitiesKit/AppContext.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDatabaseMigrationRunner

#pragma mark - Dependencies

- (OWSPrimaryStorage *)primaryStorage
{
    OWSAssertDebug(SSKEnvironment.shared.primaryStorage);

    return SSKEnvironment.shared.primaryStorage;
}

#pragma mark -

// This should all migrations which do NOT qualify as safeBlockingMigrations:
- (NSArray<OWSDatabaseMigration *> *)allMigrations
{
    return @[
        [SNMessageRequestsMigration new],
        [SNContactsMigration new]
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
    [self removeUnknownMigrations];

    [self runMigrations:[self.allMigrations mutableCopy] completion:completion];
}

// Some users (especially internal users) will move back and forth between
// app versions.  Whenever they move "forward" in the version history, we
// want them to re-run any new migrations. Therefore, when they move "backward"
// in the version history, we cull any unknown migrations.
- (void)removeUnknownMigrations
{
    NSMutableSet<NSString *> *knownMigrationIds = [NSMutableSet new];
    for (OWSDatabaseMigration *migration in self.allMigrations) {
        [knownMigrationIds addObject:migration.uniqueId];
    }

    [OWSPrimaryStorage.sharedManager.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSArray<NSString *> *savedMigrationIds = [transaction allKeysInCollection:OWSDatabaseMigration.collection];

        NSMutableSet<NSString *> *unknownMigrationIds = [NSMutableSet new];
        [unknownMigrationIds addObjectsFromArray:savedMigrationIds];
        [unknownMigrationIds minusSet:knownMigrationIds];

        for (NSString *unknownMigrationId in unknownMigrationIds) {
            OWSLogInfo(@"Culling unknown migration: %@", unknownMigrationId);
            [transaction removeObjectForKey:unknownMigrationId inCollection:OWSDatabaseMigration.collection];
        }
    }];
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
