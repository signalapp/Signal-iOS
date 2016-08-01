//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import <Mantle/MTLModel+NSCoding.h>

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

/**
 *  Fetches the object with the provided identifier
 *
 *  @param uniqueID    Unique identifier of the entry in a collection
 *  @param transaction Transaction used for fetching the object
 *
 *  @return Instance of the object or nil if non-existent
 */
+ (instancetype)fetchObjectWithUniqueID:(NSString *)uniqueID transaction:(YapDatabaseReadTransaction *)transaction;
+ (instancetype)fetchObjectWithUniqueID:(NSString *)uniqueID;

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
 *  The unique identifier of the stored object
 */
@property (nonatomic) NSString *uniqueId;

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)remove;

@end
