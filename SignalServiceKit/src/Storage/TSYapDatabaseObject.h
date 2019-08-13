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

- (instancetype)init NS_DESIGNATED_INITIALIZER;

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

/**
 * Get the number of keys in the models collection. Be aware that if there
 * are multiple object types in this collection that the count will include
 * the count of other objects in the same collection.
 *
 * @return The number of keys in the classes collection.
 */
+ (NSUInteger)numberOfKeysInCollectionWithTransaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Enumerates all objects in collection.
 */
+ (void)enumerateCollectionObjectsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                       usingBlock:(void (^)(id object, BOOL *stop))block;

@property (nonatomic, readonly) SDSDatabaseStorage *databaseStorage;
@property (class, nonatomic, readonly) SDSDatabaseStorage *databaseStorage;

/**
 *  Fetches the object with the provided identifier
 *
 *  @param uniqueID    Unique identifier of the entry in a collection
 *  @param transaction Transaction used for fetching the object
 *
 *  @return Instance of the object or nil if non-existent
 */
+ (nullable instancetype)fetchObjectWithUniqueID:(NSString *)uniqueID
                                     transaction:(YapDatabaseReadTransaction *)transaction
    NS_SWIFT_NAME(fetch(uniqueId:transaction:));

/**
 * Assign the latest persisted values from the database.
 */
- (void)reloadWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (void)reloadWithTransaction:(YapDatabaseReadTransaction *)transaction ignoreMissing:(BOOL)ignoreMissing;

/**
 *  Saves the object with the provided transaction
 *
 *  @param transaction Database transaction
 */
- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 *  The unique identifier of the stored object
 */
@property (nonatomic, readonly) NSString *uniqueId;

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark - Write Hooks

// GRDB TODO: As a perf optimization, we could only call these
//            methods for certain kinds of models which we could
//            detect at compile time.
@property (nonatomic, readonly) BOOL shouldBeSaved;

- (void)anyWillInsertWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyWillUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyDidUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyWillRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyDidRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - YDB Deprecation

// GRDB TODO: Ensure these ydb_ methods are only be used before
// and during the ydb-to-grdb migration.
+ (NSUInteger)ydb_numberOfKeysInCollectionWithTransaction:(YapDatabaseReadTransaction *)transaction;
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
