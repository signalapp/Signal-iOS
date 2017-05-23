//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel+NSCoding.h>

@class TSStorageManager;
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
- (instancetype)initWithUniqueId:(NSString *)uniqueId NS_DESIGNATED_INITIALIZER;

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
 * @return A shared database connection.
 */
- (YapDatabaseConnection *)dbConnection;
+ (YapDatabaseConnection *)dbConnection;

- (TSStorageManager *)storageManager;
+ (TSStorageManager *)storageManager;

/**
 *  Fetches the object with the provided identifier
 *
 *  @param uniqueID    Unique identifier of the entry in a collection
 *  @param transaction Transaction used for fetching the object
 *
 *  @return Instance of the object or nil if non-existent
 */
+ (instancetype)fetchObjectWithUniqueID:(NSString *)uniqueID transaction:(YapDatabaseReadTransaction *)transaction NS_SWIFT_NAME(fetch(uniqueId:transaction:));
+ (instancetype)fetchObjectWithUniqueID:(NSString *)uniqueID NS_SWIFT_NAME(fetch(uniqueId:));

/**
 *  Saves the object with a new YapDatabaseConnection
 */
- (void)save;

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
@property (nonatomic) NSString *uniqueId;

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)remove;

@end
