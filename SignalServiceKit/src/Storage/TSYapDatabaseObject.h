//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel+NSCoding.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class YapDatabaseConnection;
@class YapDatabaseReadTransaction;
@class YapDatabaseReadWriteTransaction;

@interface TSYapDatabaseObject : MTLModel

/**
 *  Initializes a new database object with a unique identifier
 *
 *  @param uniqueId Key used for the key-value store
 *
 *  @return Initialized object
 */
- (instancetype)initWithUniqueId:(NSString *_Nullable)uniqueId NS_DESIGNATED_INITIALIZER;
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
+ (NSUInteger)numberOfKeysInCollection;
+ (NSUInteger)numberOfKeysInCollectionWithTransaction:(YapDatabaseReadTransaction *)transaction;

/**
 * Removes all objects in the classes collection.
 */
+ (void)removeAllObjectsInCollection;

/**
 * A memory intesive method to get all objects in the collection. You should prefer using enumeration over this method
 * whenever feasible. See `enumerateObjectsInCollectionUsingBlock`
 *
 * @return All objects in the classes collection.
 */
+ (NSArray *)allObjectsInCollection;

/**
 * Enumerates all objects in collection.
 */
+ (void)enumerateCollectionObjectsUsingBlock:(void (^)(id obj, BOOL *stop))block;
+ (void)enumerateCollectionObjectsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                       usingBlock:(void (^)(id object, BOOL *stop))block;

/**
 * @return Shared database connections for reading and writing.
 */
- (YapDatabaseConnection *)dbReadConnection;
+ (YapDatabaseConnection *)dbReadConnection;
- (YapDatabaseConnection *)dbReadWriteConnection;
+ (YapDatabaseConnection *)dbReadWriteConnection;

- (OWSPrimaryStorage *)primaryStorage;
+ (OWSPrimaryStorage *)primaryStorage;

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
+ (nullable instancetype)fetchObjectWithUniqueID:(NSString *)uniqueID NS_SWIFT_NAME(fetch(uniqueId:));

/**
 * Saves the object with the shared readWrite connection.
 *
 * This method will block if another readWrite transaction is open.
 */
- (void)save;

/**
 * Assign the latest persisted values from the database.
 */
- (void)reloadWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (void)reload;

/**
 * Saves the object with the shared readWrite connection - does not block.
 *
 * Be mindful that this method may clobber other changes persisted
 * while waiting to open the readWrite transaction.
 *
 * @param completionBlock is called on the main thread
 */
- (void)saveAsyncWithCompletionBlock:(void (^_Nullable)(void))completionBlock;

/**
 *  Saves the object with the provided transaction
 *
 *  @param transaction Database transaction
 */
- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 * `touch` is a cheap way to fire a YapDatabaseModified notification to redraw anythign depending on the model.
 */
- (void)touch;
- (void)touchWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 *  The unique identifier of the stored object
 */
@property (nonatomic, nullable) NSString *uniqueId;

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)remove;

#pragma mark Update With...

// This method is used by "updateWith..." methods.
//
// This model may be updated from many threads. We don't want to save
// our local copy (this instance) since it may be out of date.  We also
// want to avoid re-saving a model that has been deleted.  Therefore, we
// use "updateWith..." methods to:
//
// a) Update a property of this instance.
// b) If a copy of this model exists in the database, load an up-to-date copy,
//    and update and save that copy.
// b) If a copy of this model _DOES NOT_ exist in the database, do _NOT_ save
//    this local instance.
//
// After "updateWith...":
//
// a) Any copy of this model in the database will have been updated.
// b) The local property on this instance will always have been updated.
// c) Other properties on this instance may be out of date.
//
// All mutable properties of this class have been made read-only to
// prevent accidentally modifying them directly.
//
// This isn't a perfect arrangement, but in practice this will prevent
// data loss and will resolve all known issues.
- (void)applyChangeToSelfAndLatestCopy:(YapDatabaseReadWriteTransaction *)transaction
                           changeBlock:(void (^)(id))changeBlock;

@end

NS_ASSUME_NONNULL_END
