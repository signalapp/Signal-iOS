//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/BaseModel.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^OWSDatabaseMigrationCompletion)(void);

@class OWSPrimaryStorage;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;
@class YapDatabaseReadWriteTransaction;

// Although OWSDatabaseMigration is still a TSYapDatabaseObject
// to enable deserialization of legacy values, OWSDatabaseMigration
// now uses a key-value store to persist migration completion.
@interface OWSDatabaseMigration : TSYapDatabaseObject

+ (SDSKeyValueStore *)keyValueStore;

@property (class, nonatomic, readonly) NSString *migrationId;
@property (nonatomic, readonly) NSString *migrationId;

// Prefer nonblocking (async) migrations by overriding `runUpWithTransaction:` in a subclass.
// Blocking migrations running too long will crash the app, effectively bricking install
// because the user will never get past it.
// If you must write a launch-blocking migration, override runUp.
- (void)runUpWithCompletion:(OWSDatabaseMigrationCompletion)completion;

// NOTE: We'll often want to use markAsCompleteWithSneakyTransaction.
- (void)markAsCompleteWithTransaction:(SDSAnyWriteTransaction *)transaction;

// We use a sneaky transaction since which database we should
// update will depend on whether or not we're pre- or post-
// the YDB-to-GRDB migration.
- (void)markAsCompleteWithSneakyTransaction;

+ (void)markMigrationIdAsComplete:(NSString *)migrationId transaction:(SDSAnyWriteTransaction *)transaction;

+ (void)markMigrationIdAsIncomplete:(NSString *)migrationId transaction:(SDSAnyWriteTransaction *)transaction;

// We use a sneaky transaction since YDBDatabaseMigration will
// want to consult YDB and GRDBDatabaseMigration will want to
// consult GRDB.
- (BOOL)isCompleteWithSneakyTransaction;

+ (NSArray<NSString *> *)allCompleteMigrationIdsWithTransaction:(SDSAnyReadTransaction *)transaction;

@end

#pragma mark -

// A base class for migrations run before the YDB-to-GRDB migration.
@interface YDBDatabaseMigration : OWSDatabaseMigration

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;

// Subclasses should override this convenience method or runUpWithCompletion.
- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark - Database Connections

@property (nonatomic, readonly) YapDatabaseConnection *ydbReadWriteConnection;

@end

NS_ASSUME_NONNULL_END
