//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel+NSCoding.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyWriteTransaction;
@class SDSDatabaseStorage;
@class YapDatabaseReadTransaction;
@class YapDatabaseReadWriteTransaction;

@protocol SDSRecordDelegate

- (void)updateRowId:(int64_t)rowId;

@end

#pragma mark -


@interface TSYapDatabaseObject : MTLModel <SDSRecordDelegate>

/**
 *  The unique identifier of the stored object
 */
@property (nonatomic, readonly) NSString *uniqueId;

// This property should only ever be accesssed within a GRDB write transaction.
@property (atomic, readonly, nullable) NSNumber *grdbId;

@property (nonatomic, readonly) SDSDatabaseStorage *databaseStorage;
@property (class, nonatomic, readonly) SDSDatabaseStorage *databaseStorage;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

/**
 *  Initializes a new database object with a unique identifier
 *
 *  @param uniqueId Key used for the key-value store
 *
 *  @return Initialized object
 */
- (instancetype)initWithUniqueId:(NSString *)uniqueId NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithGrdbId:(int64_t)grdbId uniqueId:(NSString *)uniqueId NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

/**
 *  Returns the collection to which the object belongs.
 *
 *  @return Key (string) identifying the collection
 */
+ (NSString *)collection;

// This method should only ever be called within a GRDB write transaction.
- (void)clearRowId;

@property (nonatomic, readonly) NSString *transactionFinalizationKey;

#pragma mark -

// GRDB TODO: As a perf optimization, we could only call these
//            methods for certain kinds of models which we could
//            detect at compile time.
@property (nonatomic, readonly) BOOL shouldBeSaved;

@property (class, nonatomic, readonly) BOOL shouldBeIndexedForFTS;

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
