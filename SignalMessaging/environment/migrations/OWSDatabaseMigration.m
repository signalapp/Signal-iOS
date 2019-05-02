//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseMigration.h"
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/SSKEnvironment.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDatabaseMigration

#pragma mark - Dependencies

- (OWSPrimaryStorage *)primaryStorage
{
    OWSAssertDebug(SSKEnvironment.shared.primaryStorage);

    return SSKEnvironment.shared.primaryStorage;
}

#pragma mark -

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSLogInfo(@"marking migration as complete.");

    [super saveWithTransaction:transaction];
}

- (instancetype)init
{
    self = [super initWithUniqueId:[self.class migrationId]];
    if (!self) {
        return self;
    }

    return self;
}

+ (MTLPropertyStorage)storageBehaviorForPropertyWithKey:(NSString *)propertyKey
{
    if ([propertyKey isEqualToString:@"primaryStorage"]) {
        return MTLPropertyStorageNone;
    } else {
        return [super storageBehaviorForPropertyWithKey:propertyKey];
    }
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
            [self save];

            completion();
        }];
}

#pragma mark - Database Connections

#ifdef DEBUG
+ (YapDatabaseConnection *)dbReadConnection
{
    return self.dbReadWriteConnection;
}

+ (YapDatabaseConnection *)dbReadWriteConnection
{
    return SSKEnvironment.shared.migrationDBConnection;
}

- (YapDatabaseConnection *)dbReadConnection
{
    return OWSDatabaseMigration.dbReadConnection;
}

- (YapDatabaseConnection *)dbReadWriteConnection
{
    return OWSDatabaseMigration.dbReadWriteConnection;
}
#endif

@end

NS_ASSUME_NONNULL_END
