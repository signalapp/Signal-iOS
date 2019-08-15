//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel+NSCoding.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class SDSAnyWriteTransaction;
@class SDSDatabaseStorage;
@class YapDatabaseConnection;
@class YapDatabaseReadTransaction;
@class YapDatabaseReadWriteTransaction;

@interface TSYapDatabaseObject : MTLModel

/**
 *  The unique identifier of the stored object
 */
@property (nonatomic, readonly) NSString *uniqueId;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) SDSDatabaseStorage *databaseStorage;
@property (class, nonatomic, readonly) SDSDatabaseStorage *databaseStorage;

/**
 *  Initializes a new database object with a unique identifier
 *
 *  @param uniqueId Key used for the key-value store
 *
 *  @return Initialized object
 */
- (instancetype)initWithUniqueId:(NSString *)uniqueId NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

/**
 *  Returns the collection to which the object belongs.
 *
 *  @return Key (string) identifying the collection
 */
+ (NSString *)collection;

#pragma mark - Write Hooks

// GRDB TODO: As a perf optimization, we could only call these
//            methods for certain kinds of models which we could
//            detect at compile time.
@property (nonatomic, readonly) BOOL shouldBeSaved;

#pragma mark - Data Store Write Hooks

- (void)anyWillInsertWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyWillUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyDidUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyWillRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyDidRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - YDB Deprecation

// These ydb_ methods should only be used before
// and during the ydb-to-grdb migration.
+ (void)ydb_enumerateCollectionObjectsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                           usingBlock:(void (^)(id object, BOOL *stop))block;
+ (nullable instancetype)ydb_fetchObjectWithUniqueID:(NSString *)uniqueID
                                         transaction:(YapDatabaseReadTransaction *)transaction
    NS_SWIFT_NAME(ydb_fetch(uniqueId:transaction:));
- (void)ydb_reloadWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (void)ydb_reloadWithTransaction:(YapDatabaseReadTransaction *)transaction ignoreMissing:(BOOL)ignoreMissing;
- (void)ydb_saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)ydb_removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
