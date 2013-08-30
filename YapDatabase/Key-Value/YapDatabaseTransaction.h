#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseTransaction.h"
#import "YapAbstractDatabaseExtensionTransaction.h"

@class YapDatabaseConnection;

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yaptv/YapDatabase/wiki
 * 
 * Transactions represent atomic access to a database.
 * There are two types of transactions:
 * - Read-Only transactions
 * - Read-Write transactions
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
 * 
 * Concurrency is straight-forward. Here are the rules:
 * 
 * - You can have multiple connections.
 * - Every connection is thread-safe.
 * - You can have multiple read-only transactions simultaneously without blocking.
 *   (Each simultaneous transaction would be going through a separate connection.)
 * - You can have multiple read-only transactions and a single read-write transaction simultaneously without blocking.
 *   (Each simultaneous transaction would be going through a separate connection.)
 * - There can only be a single transaction per connection at a time.
 *   (Transactions go through a per-connection serial queue.)
 * - There can only be a single read-write transaction at a time.
 *   (Read-write transactions go through a per-database serial queue.)
**/

/**
 * A YapDatabaseReadTransaction encompasses a single read-only database transaction.
 * You can execute multiple operations within a single transaction.
 * 
 * A transaction allows you to safely access the database as needed in a thread-safe and optimized manner.
**/
@interface YapDatabaseReadTransaction : YapAbstractDatabaseTransaction

/**
 * Transactions are light-weight objects created by connections.
 *
 * Connections are the parent objects of transactions.
 * Connections own the transaction objects.
 *
 * Transactions store nearly all their state in the parent connection object.
 * This reduces the memory requirements for transactions objects,
 * and reduces the overhead associated in creating them.
**/
@property (nonatomic, unsafe_unretained, readonly) YapDatabaseConnection *connection;

#pragma mark Count

/**
 * Returns the number of rows in the database.
**/
- (NSUInteger)numberOfKeys;

#pragma mark List

/**
 * Returns a list of all keys in the database.
 * 
 * Note: This method pulls all keys into memory !
 * 
 * This is a convenience method designed only for SMALL databases.
 * If your database has the potential to grow to a large size, then this method should never be used.
**/
- (NSArray *)allKeys;

#pragma mark Primitive

/**
 * Primitive access (for edge cases).
 * Most of the time you should be using objectForKey, etc.
 *
 * These methods are available in-case you need to store irregular data
 * that shouldn't go through the configured serializer/deserializer.
 *
 * @see objectForKey:
 * @see metadataForKey:
 * @see getObject:metadata:forKey:
**/
- (NSData *)primitiveDataForKey:(NSString *)key;
- (NSData *)primitiveMetadataForKey:(NSString *)key;
- (BOOL)getPrimitiveData:(NSData **)dataPtr primitiveMetadata:(NSData **)metadataPtr forKey:(NSString *)key;

#pragma mark Object & Metadata

/**
 * Object access.
 * Objects are automatically deserialized using database's configured objectDeserializer.
**/
- (id)objectForKey:(NSString *)key;

/**
 * Returns whether or not the given key exists in the database.
**/
- (BOOL)hasObjectForKey:(NSString *)key;

/**
 * Provides access to both object and metadata in a single call.
 * 
 * @return YES if the key exists in the database.
 *         NO otherwise, in which case both object and metadata will be nil.
**/
- (BOOL)getObject:(id *)objectPtr metadata:(id *)metadataPtr forKey:(NSString *)key;

/**
 * Provides access to the metadata.
 * Metadata is automatically deserialized using database's configured metadataDeserializer.
**/
- (id)metadataForKey:(NSString *)key;

#pragma mark Enumerate

/**
 * Fast enumeration over all keys in the database.
 *
 * This uses a "SELECT key FROM database" operation, and then steps over the results
 * and invoking the given block handler.
**/
- (void)enumerateKeysUsingBlock:(void (^)(NSString *key, BOOL *stop))block;

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
                                withFilter:(BOOL (^)(NSString *key))filter;

/**
 * Fast enumeration over all keys and objects in the database.
 * 
 * This uses a "SELECT key, object FROM database" operation, and then steps over the results,
 * deserializing each object (if not cached), and then invoking the given block handler.
 * 
 * If you only need to enumerate over certain objects (e.g. keys with a particular prefix),
 * consider using the alternative version below which provide a filter,
 * allowing you to skip the serialization steps for those rows you're not interested in.
**/
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSString *key, id object, BOOL *stop))block;

/**
 * Fast enumeration over objects in the database for which you're interested in.
 * The filter block allows you to specify which rows you're interested in,
 * allowing you to skip the deserialization step for ignored rows.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given row.
 * If the filter block returns NO, then the block handler is skipped for the given row,
 * which avoids the cost associated with deserialization process.
**/
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSString *key, id object, BOOL *stop))block
                               withFilter:(BOOL (^)(NSString *key))filter;

/**
 * Fast enumeration over all objects in the database.
 *
 * This uses a "SELECT * FROM database" operation, and then steps over the results,
 * deserializing each object and metadata (if not cached), and then invoking the given block handler.
 *
 * If you only need to enumerate over certain objects (e.g. keys with a particular prefix),
 * consider using the alternative version below which provide a filter,
 * allowing you to skip the serialization steps for those rows you're not interested in.
**/
- (void)enumerateRowsUsingBlock:(void (^)(NSString *key, id object, id metadata, BOOL *stop))block;

/**
 * Fast enumeration over rows in the database for which you're interested in.
 * The filter block allows you to specify which rows you're interested in,
 * allowing you to skip the deserialization step for ignored rows.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given row.
 * If the filter block returns NO, then the block handler is skipped for the given row,
 * which avoids the cost associated with deserialization process.
**/
- (void)enumerateRowsUsingBlock:(void (^)(NSString *key, id object, id metadata, BOOL *stop))block
                     withFilter:(BOOL (^)(NSString *key))filter;

/**
 * Enumerates over the given list of keys (unordered), and fetches the associated metadata.
 * 
 * This method is faster than metadataForKey when fetching multiple items, as it optimizes cache access.
 * That is, it will first enumerate over cached items and then fetch items from the database,
 * thus optimizing the cache and reducing the query size.
 *
 * If any keys are missing from the database, the 'metadata' parameter will be nil.
 *
 * IMPORTANT:
 * Due to various optimizations, the items may not be enumerated in the same order as the 'keys' parameter.
**/
- (void)enumerateMetadataForKeys:(NSArray *)keys
             unorderedUsingBlock:(void (^)(NSUInteger keyIndex, id metadata, BOOL *stop))block;

/**
 * Enumerates over the given list of keys (unordered), and fetches the associated objects.
 *
 * This method is faster than objectForKey when fetching multiple items, as it optimizes cache access.
 * That is, it will first enumerate over cached items and then fetch items from the database,
 * thus optimizing the cache and reducing the query size.
 *
 * If any keys are missing from the database, the 'object' parameter will be nil.
 * 
 * IMPORTANT:
 * Due to various optimizations, the items may not be enumerated in the same order as the 'keys' parameter.
**/
- (void)enumerateObjectsForKeys:(NSArray *)keys
            unorderedUsingBlock:(void (^)(NSUInteger keyIndex, id object, BOOL *stop))block;

/**
 * Enumerates over the given list of keys (unordered), and fetches the associated rows.
 *
 * This method is faster than fetching items one-by-one as it optimizes cache access.
 * That is, it will first enumerate over cached items and then fetch items from the database,
 * thus optimizing the cache and reducing the query size.
 *
 * If any keys are missing from the database, the 'object' parameter will be nil.
 * 
 * IMPORTANT:
 * Due to various optimizations, the items may not be enumerated in the same order as the 'keys' parameter.
**/
- (void)enumerateRowsForKeys:(NSArray *)keys
         unorderedUsingBlock:(void (^)(NSUInteger keyIndex, id object, id metadata, BOOL *stop))block;

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
- (void)setPrimitiveData:(NSData *)data forKey:(NSString *)key withPrimitiveMetadata:(NSData *)pMetadata;

#pragma mark Object & Metadata

/**
 * Sets the object for the given key.
 * Objects are automatically serialized using the database's configured serializer.
 * 
 * You may optionally pass metadata about the object.
 * The metadata is also written to the database for persistent storage, and thus persists between sessions.
 * Metadata is serialized/deserialized to/from disk just like the object.
**/
- (void)setObject:(id)object forKey:(NSString *)key;
- (void)setObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata;

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

@end
