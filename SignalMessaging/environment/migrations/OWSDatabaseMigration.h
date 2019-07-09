//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/BaseModel.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^OWSDatabaseMigrationCompletion)(void);

@class OWSPrimaryStorage;
@class SDSAnyWriteTransaction;
@class YapDatabaseReadWriteTransaction;

@interface OWSDatabaseMigration : BaseModel

// Prefer nonblocking (async) migrations by overriding `runUpWithTransaction:` in a subclass.
// Blocking migrations running too long will crash the app, effectively bricking install
// because the user will never get past it.
// If you must write a launch-blocking migration, override runUp.
- (void)runUpWithCompletion:(OWSDatabaseMigrationCompletion)completion;

- (void)markAsCompleteWithTransaction:(SDSAnyWriteTransaction *)transaction;

// We use a sneaky transaction since YDBDatabaseMigration will
// want to consult YDB and GRDBDatabaseMigration will want to
// consult GRDB.
- (BOOL)isCompleteWithSneakyTransaction;

@end

#pragma mark -

@interface YDBDatabaseMigration : OWSDatabaseMigration

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;

// Subclasses should override this convenience method or runUpWithCompletion.
- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark - Database Connections

@property (nonatomic, readonly) YapDatabaseConnection *ydbReadWriteConnection;

@end

NS_ASSUME_NONNULL_END
