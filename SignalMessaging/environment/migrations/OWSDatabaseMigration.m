//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSDatabaseMigration.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/StorageCoordinator.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDatabaseMigration

// This key-value store is used to persist completion of migrations.
// Note that it uses the YDB collection previously used to persist migration models.
// Since we just check "has key", this is backwards-compatible.
+ (SDSKeyValueStore *)keyValueStore
{
    static SDSKeyValueStore *keyValueStore = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keyValueStore = [[SDSKeyValueStore alloc] initWithCollection:OWSDatabaseMigration.collection];
    });
    return keyValueStore;
}

- (instancetype)init
{
    return [super initWithUniqueId:[self.class migrationId]];
}

#pragma mark - Dependencies

- (StorageCoordinator *)storageCoordinator
{
    return SSKEnvironment.shared.storageCoordinator;
}

#pragma mark -

+ (NSString *)migrationId
{
    OWSAbstractMethod();

    return @"";
}

- (NSString *)migrationId
{
    return self.class.migrationId;
}

+ (NSString *)collection
{
    // We want all subclasses in the same collection
    return @"OWSDatabaseMigration";
}

- (void)runUpWithCompletion:(OWSDatabaseMigrationCompletion)completion
{
    OWSAbstractMethod();
}

- (void)markAsCompleteWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    if (!self.shouldBeSaved) {
        OWSLogInfo(@"NOT Marking migration as incomplete: %@ %@", [self class], self.migrationId);
        return;
    }

    [OWSDatabaseMigration markMigrationIdAsComplete:self.migrationId transaction:transaction];
}

+ (void)markMigrationIdAsComplete:(NSString *)migrationId transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"Marking migration as complete: %@", migrationId);

    [self.keyValueStore setBool:YES key:migrationId transaction:transaction];
}

+ (void)markMigrationIdAsIncomplete:(NSString *)migrationId transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"Marking migration as incomplete: %@", migrationId);

    [self.keyValueStore removeValueForKey:migrationId transaction:transaction];
}

- (void)markAsCompleteWithSneakyTransaction
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self markAsCompleteWithTransaction:transaction];
    });
}

- (BOOL)isCompleteWithSneakyTransaction
{
    __block BOOL result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self isCompleteWithTransaction:transaction];
    }];
    return result;
}

- (BOOL)isCompleteWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [OWSDatabaseMigration.keyValueStore hasValueForKey:self.migrationId transaction:transaction];
}

+ (NSArray<NSString *> *)allCompleteMigrationIdsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyValueStore allKeysWithTransaction:transaction];
}

@end

#pragma mark -

@implementation YDBDatabaseMigration

#pragma mark - Dependencies

- (nullable OWSPrimaryStorage *)primaryStorage
{
    OWSAssertDebug(SSKEnvironment.shared.primaryStorage);

    return SSKEnvironment.shared.primaryStorage;
}

#pragma mark -

- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAbstractMethod();
}

- (void)runUpWithCompletion:(OWSDatabaseMigrationCompletion)completion
{
    OWSAssertDebug(completion);

    OWSDatabaseConnection *dbConnection = (OWSDatabaseConnection *)self.primaryStorage.newDatabaseConnection;

    [dbConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            [self runUpWithTransaction:transaction];
        }
        completionBlock:^{
            [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                [self markAsCompleteWithTransaction:transaction.asAnyWrite];
            }];

            completion();
        }];
}

#pragma mark - Database Connections

+ (YapDatabaseConnection *)ydbReadConnection
{
    return self.ydbReadWriteConnection;
}

+ (YapDatabaseConnection *)ydbReadWriteConnection
{
    return SSKEnvironment.shared.migrationDBConnection;
}

- (YapDatabaseConnection *)ydbReadConnection
{
    return YDBDatabaseMigration.ydbReadConnection;
}

- (YapDatabaseConnection *)ydbReadWriteConnection
{
    return YDBDatabaseMigration.ydbReadWriteConnection;
}

@end

NS_ASSUME_NONNULL_END
