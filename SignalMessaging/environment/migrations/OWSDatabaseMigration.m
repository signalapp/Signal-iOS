//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSDatabaseMigration.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDatabaseMigration

- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidInsertWithTransaction:transaction];

    OWSLogInfo(@"marking migration as complete: %@.", [self class]);
}

- (instancetype)init
{
    self = [super initWithUniqueId:[self.class migrationId]];
    if (!self) {
        return self;
    }

    return self;
}

+ (NSString *)migrationId
{
    OWSAbstractMethod();

    return @"";
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
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [self anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop
}

- (BOOL)isCompleteWithSneakyTransaction
{
    OWSAbstractMethod();

    return NO;
}

@end

#pragma mark -

@implementation YDBDatabaseMigration

#pragma mark - Dependencies

- (OWSPrimaryStorage *)primaryStorage
{
    OWSAssertDebug(SSKEnvironment.shared.primaryStorage);

    return SSKEnvironment.shared.primaryStorage;
}

+ (MTLPropertyStorage)storageBehaviorForPropertyWithKey:(NSString *)propertyKey
{
    if ([propertyKey isEqualToString:@"primaryStorage"]) {
        return MTLPropertyStorageNone;
    } else {
        return [super storageBehaviorForPropertyWithKey:propertyKey];
    }
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
            OWSLogInfo(@"Completed migration %@", self.uniqueId);

            [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                [self markAsCompleteWithTransaction:transaction.asAnyWrite];
            }];

            completion();
        }];
}

- (BOOL)isCompleteWithSneakyTransaction
{
    __block BOOL result;
    [self.ydbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        result = [YDBDatabaseMigration ydb_fetchObjectWithUniqueID:self.uniqueId transaction:transaction] != nil;
    }];
    return result;
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
