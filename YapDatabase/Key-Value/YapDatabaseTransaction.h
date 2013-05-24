#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseTransaction.h"
#import "YapAbstractDatabaseExtensionTransaction.h"

/**
 * Transactions represent atomic access to a database.
 * There are two types of transactions:
 * - Read-Only transactions
 * - Read-Write transactions
 *
 * Multiple read-only transactions may occur in parallel,
 * and may also occur simulataneously with a single read-write transaction.
 * However, there may be only a single read-write transaction per database.
 * 
 * Once a transaction is started, all data access within the transaction from that point forward until completion
 * represents an atomic "snapshot" of the current state of the database. For example, if a read-write operation
 * occurs in parallel with a read-only transaction, the read-only transaction won't see the changes made by
 * the read-write operation. But once the read-write operation completes, all transactions started from that point
 * forward will see the changes.
 * 
 * You first create and configure a YapDatabase instance.
 * Then you can spawn one or more connections to the database file.
 * Each connection allows you to execute transactions in a serial fashion.
 * For concurrent access, you can create multiple connections,
 * and execute transactions on each connection simulataneously.
**/

/**
 * A YapDatabaseReadTransaction encompasses a single read-only database transaction.
 * You can execute multiple operations within a single transaction.
 * 
 * A transaction allows you to safely access the database as needed in a thread-safe manner.
**/
@interface YapDatabaseReadTransaction : YapAbstractDatabaseTransaction

#pragma mark Count

/**
 * Returns the number of rows in the database.
 * This information is kept in memory, and thus doesn't hit the disk.
**/
- (NSUInteger)numberOfKeys;

#pragma mark List

/**
 * Returns a list of all keys in the database.
 * This information is kept in memory, and thus doesn't hit the disk.
**/
- (NSArray *)allKeys;

#pragma mark Primitive

/**
 * Primitive access.
 *
 * These are available in-case you store irregular data
 * that shouldn't go through configured serializer/deserializer.
 *
 * @see objectForKey
 **/
- (NSData *)primitiveDataForKey:(NSString *)key;

#pragma mark Object

/**
 * Object access.
 * Objects are automatically deserialized using database's configured deserializer.
**/
- (id)objectForKey:(NSString *)key;

/**
 * Returns whether or not the given key exists in the database.
 * This information is kept in memory, and thus doesn't hit the disk.
**/
- (BOOL)hasObjectForKey:(NSString *)key;

/**
 * Provides access to both object and metadata in a single call.
 * 
 * @return YES if the key exists in the database. NO otherwise, in which case both object and metadata will be nil.
**/
- (BOOL)getObject:(id *)objectPtr metadata:(id *)metadataPtr forKey:(NSString *)key;

#pragma mark Metadata

/**
 * Provides access to the metadata.
 * This fetches directly from the metadata dictionary stored in memory, and thus never hits the disk.
**/
- (id)metadataForKey:(NSString *)key;

#pragma mark Enumerate

/**
 * Fast enumeration over all keys in the database.
 *
 * This uses a "SELECT key FROM database" operation, and then steps over the results
 * and invoking the given block handler.
**/
- (void)enumerateKeys:(void (^)(NSString *key, BOOL *stop))block;

/**
 * Enumerates over the given list of keys (unordered).
 *
 * This method is faster than objectForKey when fetching multiple objects, as it optimizes cache access.
 * That is, it will first enumerate over cached objects, and then fetch objects from the database,
 * thus optimizing the available cache.
 *
 * If any keys are missing from the database, the 'object' parameter will be nil.
 * 
 * IMPORTANT:
 *     Due to cache optimizations, the objects may not be enumerated in the same order as the 'keys' parameter.
 *     That is, objects that are cached will be enumerated over first, before fetching objects from the database.
**/
- (void)enumerateObjects:(void (^)(NSUInteger keyIndex, id object, BOOL *stop))block
                 forKeys:(NSArray *)keys;
/**
 * Fast enumeration over all keys and metadata in the database.
 * 
 * This uses a "SELECT key, metadata FROM database" operation, and then steps over the results,
 * deserializing each metadata (if not cached), and invoking the given block handler.
 * 
 * If you only need to enumerate over certain metadata rows (e.g. keys with a particular prefix),
 * consider using the alternative version below which provide a filter,
 * allowing you to skip the deserialization step for those rows you're not interested in.
**/
- (void)enumerateKeysAndMetadataUsingBlock:(void (^)(NSString *key, id metadata, BOOL *stop))block;

/**
 * Fast enumeration over all keys and metadata in the database for which you're interested in.
 * The filter block allows you to decide which rows you're interested in,
 * allowing you to skip the deserialization step for ignored rows.
 * 
 * From the filter block, simply return YES if you'd like the block handler to be invoked for given row.
 * If the filter block returns NO, then the block handler is skipped for the given row,
 * which avoids the cost associated with deserialization process.
**/
- (void)enumerateKeysAndMetadataUsingBlock:(void (^)(NSString *key, id metadata, BOOL *stop))block
                             withKeyFilter:(BOOL (^)(NSString *key))filter;

/**
 * Fast enumeration over all objects in the database.
 * 
 * This uses a "SELECT * FROM database" operation, and then steps over the results,
 * deserializing each object and metadata (if not cached), and then invoking the given block handler.
 * 
 * If you only need to enumerate over certain objects (e.g. keys with a particular prefix),
 * consider using the alternative versions below which provide a filter,
 * allowing you to skip the serialization steps for those rows you're not interested in.
**/
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSString *key, id object, id metadata, BOOL *stop))block;

/**
 * Fast enumeration over objects in the database for which you're interested in.
 * The filter block allows you to specify which objects you're interested in,
 * allowing you to skip the deserialization step for ignored rows.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given row.
 * If the filter block returns NO, then the block handler is skipped for the given row,
 * which avoids the cost associated with deserialization process.
**/
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSString *key, id object, id metadata, BOOL *stop))block
                            withKeyFilter:(BOOL (^)(NSString *key))filter;

/**
 * Fast enumeration over objects in the database for which you're interested in.
 * The filter block allows you to specify which objects you're interested in,
 * allowing you to skip the deserialization step for ignored rows.
 * 
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given row.
 * If the filter block returns NO, then the block handler is skipped for the given row,
 * which avoids the cost associated with deserialization process.
**/
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSString *key, id object, id metadata, BOOL *stop))block
                       withMetadataFilter:(BOOL (^)(NSString *key, id metadata))filter;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * A YapDatabaseReadWriteTransaction encompasses a single read-write database transaction.
 * You can execute multiple operations within a single transaction.
 * 
 * A transaction allows you to safely access the database as needed in a thread-safe manner.
**/
@interface YapDatabaseReadWriteTransaction : YapDatabaseReadTransaction

/* Inherited from YapAbstractDatabaseTransaction

- (void)rollback;

*/

#pragma mark Primitive

/**
 * Primitive access.
 *
 * These are available in-case you store irregular data
 * that shouldn't go through configured serializer.
 *
 * @see setObject:forKey:
**/
- (void)setPrimitiveData:(NSData *)data forKey:(NSString *)key;
- (void)setPrimitiveData:(NSData *)data forKey:(NSString *)key withMetadata:(id)metadata;

#pragma mark Object

/**
 * Sets the object for the given key.
 * Objects are automatically serialized using the database's configured serializer.
 * 
 * You may optionally pass metadata about the object.
 * The metadata is kept in memory, within a mutable dictionary, and can be accessed very quickly.
 * The metadata is also written to the database for persistent storage, and thus persists between sessions.
 * Metadata is serialized/deserialized to/from disk just like the object.
**/
- (void)setObject:(id)object forKey:(NSString *)key;
- (void)setObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata;

#pragma mark Metadata

/**
 * Updates the metadata, and only the metadata, for the given key.
 * The object for the key doesn't change.
 * 
 * Note: If there is no given object for the given key, this method does nothing.
 * If you pass nil for the metadata, any given metadata associated with the key is removed.
**/
- (void)setMetadata:(id)metadata forKey:(NSString *)key;

#pragma mark Remove

/**
 * Deletes the database row with the given key.
 * This method is automatically called if you invoke setObject:forKey: or setData:forKey: and pass nil object/data.
**/
- (void)removeObjectForKey:(NSString *)key;

/**
 * Deletes the database rows with the given keys.
**/
- (void)removeObjectsForKeys:(NSArray *)keys;

/**
 * Deletes every row from the database.
**/
- (void)removeAllObjects;

#pragma mark Extensions

/**
 * 
**/
- (void)dropExtension:(NSString *)extensionName;

@end
