//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseMigrationRunner.h"
#import "OWS100RemoveTSRecipientsMigration.h"
#import "OWS102MoveLoggingPreferenceToUserDefaults.h"
#import "OWS103EnableVideoCalling.h"
#import "OWS104CreateRecipientIdentities.h"
#import "OWS105AttachmentFilePaths.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDatabaseMigrationRunner

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _storageManager = storageManager;

    return self;
}

- (NSArray<OWSDatabaseMigration *> *)allMigrations
{
    return @[
        [[OWS100RemoveTSRecipientsMigration alloc] initWithStorageManager:self.storageManager],
        [[OWS102MoveLoggingPreferenceToUserDefaults alloc] initWithStorageManager:self.storageManager],
        [[OWS103EnableVideoCalling alloc] initWithStorageManager:self.storageManager],
        // OWS104CreateRecipientIdentities is run separately. See runSafeBlockingMigrations.
        [[OWS105AttachmentFilePaths alloc] initWithStorageManager:self.storageManager],
        [[OWS106EnsureProfileComplete alloc] initWithStorageManager:self.storageManager]
    ];
}

- (void)assumeAllExistingMigrationsRun
{
    for (OWSDatabaseMigration *migration in self.allMigrations) {
        DDLogInfo(@"%@ Skipping migration on new install: %@", self.tag, migration);
        [migration save];
    }
}

- (void)runSafeBlockingMigrations
{
    // This should only include migrations which:
    //
    // a) Do read/write database transactions and therefore would block on the async database
    //    view registration.
    // b) Will not affect any of the data used by the async database views.
    [self runMigrations:@[
        [[OWS104CreateRecipientIdentities alloc] initWithStorageManager:self.storageManager],
    ]];
}

- (void)runAllOutstanding
{
    [self runMigrations:self.allMigrations];
}

- (void)runMigrations:(NSArray<OWSDatabaseMigration *> *)migrations
{
    OWSAssert(migrations);

    for (OWSDatabaseMigration *migration in migrations) {
        if ([OWSDatabaseMigration fetchObjectWithUniqueID:migration.uniqueId]) {
            DDLogDebug(@"%@ Skipping previously run migration: %@", self.tag, migration);
        } else {
            DDLogWarn(@"%@ Running migration: %@", self.tag, migration);
            [migration runUp];
        }
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

NS_ASSUME_NONNULL_END
