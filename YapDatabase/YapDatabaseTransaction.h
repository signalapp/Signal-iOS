#import <Foundation/Foundation.h>

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
@interface YapDatabaseReadTransaction : NSObject

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
 * Returns the total number of collections.
 * Each collection may have 1 or more key/object pairs.
**/
- (NSUInteger)numberOfCollections;

/**
 * Returns the total number of keys in the given collection.
 * Returns zero if the collection doesn't exist (or all key/object pairs from the collection have been removed).
**/
- (NSUInteger)numberOfKeysInCollection:(NSString *)collection;

/**
 * Returns the total number of key/object pairs in the entire database (including all collections).
**/
- (NSUInteger)numberOfKeysInAllCollections;

#pragma mark List

/**
 * Returns a list of all collection names.
**/
- (NSArray *)allCollections;

/**
 * Returns a list of all keys in the given collection.
**/
- (NSArray *)allKeysInCollection:(NSString *)collection;

#pragma mark Primitive

/**
 * Primitive access.
 *
 * These are available for in-case you store irregular data
 * that shouldn't go through configured serializer/deserializer.
 *
 * @see objectForKey:inCollection:
 * @see metadataForKey:inCollection:
**/
- (NSData *)primitiveDataForKey:(NSString *)key inCollection:(NSString *)collection;
- (NSData *)primitiveMetadataForKey:(NSString *)key inCollection:(NSString *)collection;
- (BOOL)getPrimitiveData:(NSData **)dataPtr
       primitiveMetadata:(NSData **)primitiveMetadataPtr
                  forKey:(NSString *)key
            inCollection:(NSString *)collection;

#pragma mark Object & Metadata

/**
 * Object access.
 * Objects are automatically deserialized using database's configured deserializer.
**/
- (id)objectForKey:(NSString *)key inCollection:(NSString *)collection;

/**
 * Returns whether or not the given key/collection exists in the database.
**/
- (BOOL)hasObjectForKey:(NSString *)key inCollection:(NSString *)collection;

/**
 * Provides access to both object and metadata in a single call.
 *
 * @return YES if the key exists in the database. NO otherwise, in which case both object and metadata will be nil.
**/
- (BOOL)getObject:(id *)objectPtr metadata:(id *)metadataPtr forKey:(NSString *)key inCollection:(NSString *)collection;

/**
 * Provides access to the metadata.
 * This fetches directly from the metadata dictionary stored in memory, and thus never hits the disk.
**/
- (id)metadataForKey:(NSString *)key inCollection:(NSString *)collection;

#pragma mark Enumerate

/**
 * Fast enumeration over all the collections in the database.
 * 
 * This uses a "SELECT collection FROM database" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)enumerateCollectionsUsingBlock:(void (^)(NSString *collection, BOOL *stop))block;

/**
 * This method is rarely needed, but may be helpful in certain situations.
 * 
 * This method may be used if you have the key, but not the collection for a particular item.
 * Please note that this is not the ideal situation.
 * 
 * Since there may be numerous collections for a given key, this method enumerates all possible collections.
**/
- (void)enumerateCollectionsForKey:(NSString *)key usingBlock:(void (^)(NSString *collection, BOOL *stop))block;

/**
 * Fast enumeration over all keys in the given collection.
 *
 * This uses a "SELECT key FROM database WHERE collection = ?" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)enumerateKeysInCollection:(NSString *)collection
                       usingBlock:(void (^)(NSString *key, BOOL *stop))block;

/**
 * Fast enumeration over all keys in the given collection.
 *
 * This uses a "SELECT collection, key FROM database" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)enumerateKeysInAllCollectionsUsingBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block;

/**
 * Fast enumeration over all keys and associated metadata in the given collection.
 * 
 * This uses a "SELECT key, metadata FROM database WHERE collection = ?" operation and steps over the results.
 * 
 * If you only need to enumerate over certain items (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the deserialization step for those items you're not interested in.
 * 
 * Keep in mind that you cannot modify the collection mid-enumeration (just like any other kind of enumeration).
**/
- (void)enumerateKeysAndMetadataInCollection:(NSString *)collection
                                  usingBlock:(void (^)(NSString *key, id metadata, BOOL *stop))block;

/**
 * Fast enumeration over all keys and associated metadata in the given collection.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
 * 
 * Keep in mind that you cannot modify the collection mid-enumeration (just like any other kind of enumeration).
**/
- (void)enumerateKeysAndMetadataInCollection:(NSString *)collection
                                  usingBlock:(void (^)(NSString *key, id metadata, BOOL *stop))block
                                  withFilter:(BOOL (^)(NSString *key))filter;



/**
 * Fast enumeration over all key/metadata pairs in all collections.
 * 
 * This uses a "SELECT metadata FROM database ORDER BY collection ASC" operation, and steps over the results.
 * 
 * If you only need to enumerate over certain objects (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the deserialization step for those objects you're not interested in.
 * 
 * Keep in mind that you cannot modify the database mid-enumeration (just like any other kind of enumeration).
**/
- (void)enumerateKeysAndMetadataInAllCollectionsUsingBlock:
                                        (void (^)(NSString *collection, NSString *key, id metadata, BOOL *stop))block;

/**
 * Fast enumeration over all key/metadata pairs in all collections.
 *
 * This uses a "SELECT metadata FROM database ORDER BY collection ASC" operation and steps over the results.
 * 
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
 *
 * Keep in mind that you cannot modify the database mid-enumeration (just like any other kind of enumeration).
 **/
- (void)enumerateKeysAndMetadataInAllCollectionsUsingBlock:
                                        (void (^)(NSString *collection, NSString *key, id metadata, BOOL *stop))block
                             withFilter:(BOOL (^)(NSString *collection, NSString *key))filter;

/**
 * Fast enumeration over all objects in the database.
 *
 * This uses a "SELECT key, object from database WHERE collection = ?" operation, and then steps over the results,
 * deserializing each object, and then invoking the given block handler.
 *
 * If you only need to enumerate over certain objects (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those objects you're not interested in.
**/
- (void)enumerateKeysAndObjectsInCollection:(NSString *)collection
                                 usingBlock:(void (^)(NSString *key, id object, BOOL *stop))block;

/**
 * Fast enumeration over objects in the database for which you're interested in.
 * The filter block allows you to decide which objects you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
**/
- (void)enumerateKeysAndObjectsInCollection:(NSString *)collection
                                 usingBlock:(void (^)(NSString *key, id object, BOOL *stop))block
                                 withFilter:(BOOL (^)(NSString *key))filter;

/**
 * Enumerates all key/object pairs in all collections.
 * 
 * The enumeration is sorted by collection. That is, it will enumerate fully over a single collection
 * before moving onto another collection.
 * 
 * If you only need to enumerate over certain objects (e.g. subset of collections, or keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those objects you're not interested in.
**/
- (void)enumerateKeysAndObjectsInAllCollectionsUsingBlock:
                                            (void (^)(NSString *collection, NSString *key, id object, BOOL *stop))block;

/**
 * Enumerates all key/object pairs in all collections.
 * The filter block allows you to decide which objects you're interested in.
 *
 * The enumeration is sorted by collection. That is, it will enumerate fully over a single collection
 * before moving onto another collection.
 * 
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given
 * collection/key pair. If the filter block returns NO, then the block handler is skipped for the given pair,
 * which avoids the cost associated with deserializing the object.
**/
- (void)enumerateKeysAndObjectsInAllCollectionsUsingBlock:
                                            (void (^)(NSString *collection, NSString *key, id object, BOOL *stop))block
                                 withFilter:(BOOL (^)(NSString *collection, NSString *key))filter;

/**
 * Fast enumeration over all rows in the database.
 *
 * This uses a "SELECT key, data, metadata from database WHERE collection = ?" operation,
 * and then steps over the results, deserializing each object & metadata, and then invoking the given block handler.
 *
 * If you only need to enumerate over certain rows (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those rows you're not interested in.
**/
- (void)enumerateRowsInCollection:(NSString *)collection
                       usingBlock:(void (^)(NSString *key, id object, id metadata, BOOL *stop))block;

/**
 * Fast enumeration over rows in the database for which you're interested in.
 * The filter block allows you to decide which rows you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object & metadata.
**/
- (void)enumerateRowsInCollection:(NSString *)collection
                       usingBlock:(void (^)(NSString *key, id object, id metadata, BOOL *stop))block
                       withFilter:(BOOL (^)(NSString *key))filter;

/**
 * Enumerates all rows in all collections.
 * 
 * The enumeration is sorted by collection. That is, it will enumerate fully over a single collection
 * before moving onto another collection.
 * 
 * If you only need to enumerate over certain rows (e.g. subset of collections, or keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those objects you're not interested in.
**/
- (void)enumerateRowsInAllCollectionsUsingBlock:
                            (void (^)(NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block;

/**
 * Enumerates all rows in all collections.
 * The filter block allows you to decide which objects you're interested in.
 *
 * The enumeration is sorted by collection. That is, it will enumerate fully over a single collection
 * before moving onto another collection.
 * 
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given
 * collection/key pair. If the filter block returns NO, then the block handler is skipped for the given pair,
 * which avoids the cost associated with deserializing the object.
**/
- (void)enumerateRowsInAllCollectionsUsingBlock:
                            (void (^)(NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
                 withFilter:(BOOL (^)(NSString *collection, NSString *key))filter;

/**
 * Enumerates over the given list of keys (unordered).
 *
 * This method is faster than fetching individual items as it optimizes cache access.
 * That is, it will first enumerate over items in the cache and then fetch items from the database,
 * thus optimizing the cache and reducing query size.
 *
 * If any keys are missing from the database, the 'metadata' parameter will be nil.
 *
 * IMPORTANT:
 * Due to cache optimizations, the items may not be enumerated in the same order as the 'keys' parameter.
**/
- (void)enumerateMetadataForKeys:(NSArray *)keys
                    inCollection:(NSString *)collection
             unorderedUsingBlock:(void (^)(NSUInteger keyIndex, id metadata, BOOL *stop))block;

/**
 * Enumerates over the given list of keys (unordered).
 *
 * This method is faster than fetching individual items as it optimizes cache access.
 * That is, it will first enumerate over items in the cache and then fetch items from the database,
 * thus optimizing the cache and reducing query size.
 *
 * If any keys are missing from the database, the 'object' parameter will be nil.
 *
 * IMPORTANT:
 * Due to cache optimizations, the items may not be enumerated in the same order as the 'keys' parameter.
**/
- (void)enumerateObjectsForKeys:(NSArray *)keys
                   inCollection:(NSString *)collection
            unorderedUsingBlock:(void (^)(NSUInteger keyIndex, id object, BOOL *stop))block;

/**
 * Enumerates over the given list of keys (unordered).
 *
 * This method is faster than fetching individual items as it optimizes cache access.
 * That is, it will first enumerate over items in the cache and then fetch items from the database,
 * thus optimizing the cache and reducing query size.
 *
 * If any keys are missing from the database, the 'object' and 'metadata' parameter will be nil.
 *
 * IMPORTANT:
 * Due to cache optimizations, the items may not be enumerated in the same order as the 'keys' parameter.
**/
- (void)enumerateRowsForKeys:(NSArray *)keys
                inCollection:(NSString *)collection
         unorderedUsingBlock:(void (^)(NSUInteger keyIndex, id object, id metadata, BOOL *stop))block;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extensions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns an extension transaction corresponding to the extension type registered under the given name.
 * If the extension has not yet been opened, it is done so automatically.
 *
 * @return
 *     A subclass of YapDatabaseExtensionTransaction,
 *     according to the type of extension registered under the given name.
 * 
 * One must register an extension with the database before it can be accessed from within connections or transactions.
 * After registration everything works automatically using just the registered extension name.
 *
 * @see [YapDatabase registerExtension:withName:]
**/
- (id)extension:(NSString *)extensionName;
- (id)ext:(NSString *)extensionName; // <-- Shorthand (same as extension: method)

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseReadWriteTransaction : YapDatabaseReadTransaction

/**
 * Under normal circumstances, when a read-write transaction block completes,
 * the changes are automatically committed. If, however, something goes wrong and
 * you'd like to abort and discard all changes made within the transaction,
 * then invoke this method.
 * 
 * You should generally return (exit the transaction block) after invoking this method.
 * Any changes made within the the transaction before and after invoking this method will be discarded.
**/
- (void)rollback;

/**
 * The YapDatabaseModifiedNotification is posted following a readwrite transaction which made changes.
 * 
 * These notifications are used in a variety of ways:
 * - They may be used as a general notification mechanism to detect changes to the database.
 * - They may be used by extensions to post change information.
 *   For example, YapDatabaseView will post the index changes, which can easily be used to animate a tableView.
 * - They are integrated into the architecture of long-lived transactions in order to maintain a steady state.
 *
 * Thus it is recommended you integrate your own notification information into this existing notification,
 * as opposed to broadcasting your own separate notification.
 * 
 * For more information, and code samples, please see the wiki article:
 * https://github.com/yaptv/YapDatabase/wiki/YapDatabaseModifiedNotification
**/
@property (nonatomic, strong, readwrite) id yapDatabaseModifiedNotificationCustomObject;

#pragma mark Primitive

/**
 * Primitive access.
 * This method is available in case you need to store irregular data that
 * shouldn't go through the configured serializer/deserializer.
 *
 * Primitive data is stored into the database, but doesn't get routed through any of the extensions.
 *
 * Remember that if you place primitive data into the database via this method,
 * you are responsible for accessing it via the appropriate primitive accessor (such as
 * primitiveDataForKey:inCollection:). If you attempt to access it via the object accessor
 * (objectForKey:inCollection), then the system will attempt to deserialize the primitive data via the
 * configured deserializer, which may or may not work depending on the primitive data you're storing.
 * 
 * This method is the primitive version of setObject:forKey:inCollection:.
 * For more information see the documentation for setObject:forKey:inCollection:.
 *
 * @see setObject:forKey:inCollection:
 * @see primitiveDataForKey:inCollection:
**/
- (void)setPrimitiveData:(NSData *)primitiveData forKey:(NSString *)key inCollection:(NSString *)collection;

/**
 * Primitive access.
 * This method is available in case you need to store irregular data that
 * shouldn't go through the configured serializer/deserializer.
 *
 * Primitive data is stored into the database, but doesn't get routed through any of the extensions.
 *
 * Remember that if you place primitive data into the database via this method,
 * you are responsible for accessing it via the appropriate primitive accessor (such as
 * primitiveDataForKey:inCollection:). If you attempt to access it via the object accessor
 * (objectForKey:inCollection), then the system will attempt to deserialize the primitive data via the
 * configured deserializer, which may or may not work depending on the primitive data you're storing.
 * 
 * This method is the primitive version of setObject:forKey:inCollection:withMetadata:.
 * For more information see the documentation for setObject:forKey:inCollection:withMetadata:.
 *
 * @see setObject:forKey:inCollection:withMetadata:
 * @see primitiveDataForKey:inCollection:
 * @see primitiveMetadataForKey:inCollection:
**/
- (void)setPrimitiveData:(NSData *)primitiveData
                  forKey:(NSString *)key
            inCollection:(NSString *)collection
   withPrimitiveMetadata:(NSData *)primitiveMetadata;

/**
 * Primitive access.
 * This method is available in case you need to store irregular data that
 * shouldn't go through the configured serializer/deserializer.
 *
 * Primitive data is stored into the database, but doesn't get routed through any of the extensions.
 *
 * Remember that if you place primitive data into the database via this method,
 * you are responsible for accessing it via the appropriate primitive accessor (such as
 * primitiveDataForKey:inCollection:). If you attempt to access it via the object accessor
 * (objectForKey:inCollection), then the system will attempt to deserialize the primitive data via the
 * configured deserializer, which may or may not work depending on the primitive data you're storing.
 *
 * This method is the primitive version of replaceObject:forKey:inCollection:.
 * For more information see the documentation for replaceObject:forKey:inCollection:.
 *
 * @see replaceObject:forKey:inCollection:
 * @see primitiveDataForKey:inCollection:
**/
- (void)replacePrimitiveData:(NSData *)primitiveData forKey:(NSString *)key inCollection:(NSString *)collection;

/**
 * Primitive access.
 * This method is available in case you need to store irregular data that
 * shouldn't go through the configured serializer/deserializer.
 * 
 * Primitive data is stored into the database, but doesn't get routed through any of the extensions.
 * 
 * Remember that if you place primitive data into the database via this method,
 * you are responsible for accessing it via the appropriate primitive accessor (such as
 * primitiveMetadataForKey:inCollection:). If you attempt to access it via the object accessor
 * (metadataForKey:inCollection), then the system will attempt to deserialize the primitive data via the
 * configured deserializer, which may or may not work depending on the primitive data you're storing.
 *
 * This method is the primitive version of replaceMetadata:forKey:inCollection:.
 * For more information see the documentation for replaceMetadata:forKey:inCollection:.
 *
 * @see replaceMetadata:forKey:inCollection:
 * @see primitiveMetadataForKey:inCollection:
**/
- (void)replacePrimitiveMetadata:(NSData *)primitiveMetadata forKey:(NSString *)key inCollection:(NSString *)collection;

/**
 * DEPRECATED: Use replacePrimitiveMetadata:forKey:inCollection: instead.
**/
- (void)setPrimitiveMetadata:(NSData *)primitiveMetadata forKey:(NSString *)key inCollection:(NSString *)collection
__attribute((deprecated("Use method replacePrimitiveMetadata:forKey:inCollection: instead")));

#pragma mark Object & Metadata

/**
 * Sets the object for the given key/collection.
 * The object is automatically serialized using the database's configured objectSerializer.
 * 
 * If you pass nil for the object, then this method will remove the row from the database (if it exists).
 *
 * This method implicitly sets the associated metadata to nil.
**/
- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection;

/**
 * Sets the object & metadata for the given key/collection.
 * 
 * The object is automatically serialized using the database's configured objectSerializer.
 * The metadata is automatically serialized using the database's configured metadataSerializer.
 * 
 * The metadata is optional. You can pass nil for the metadata is unneeded.
 * If non-nil then the metadata is also written to the database (metadata is also persistent).
 *
 * If you pass nil for the object, then this method will remove the row from the database (if it exists).
**/
- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection withMetadata:(id)metadata;

/**
 * If a row with the given key/collection exists, then replaces the object for that row with the new value.
 * It only replaces the object. The metadata for the row doesn't change.
 * 
 * If there is no row in the database for the given key/collection then this method does nothing.
 * 
 * If you pass nil for the object, then this method will remove
**/
- (void)replaceObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection;

/**
 * If a row with the given key/collection exists, then replaces the metadata for that row with the new value.
 * It only replaces the metadata. The object for the row doesn't change.
 *
 * If there is no row in the database for the given key/collection then this method does nothing.
 * 
 * If you pass nil for the metadata, any metadata previously associated with the key/collection is removed.
**/
- (void)replaceMetadata:(id)metadata forKey:(NSString *)key inCollection:(NSString *)collection;

/**
 * DEPRECATED: Use replaceMetadata:forKey:inCollection: instead.
**/
- (void)setMetadata:(id)metadata forKey:(NSString *)key inCollection:(NSString *)collection
__attribute((deprecated("Use method replaceMetadata:forKey:inCollection: instead")));

#pragma mark Touch

/**
 * You can touch an object if you want to mark it as updated without actually writing any changes to disk.
 *
 * For example:
 *
 *   You have a BNBook object in your database.
 *   One of the properties of the book object is a URL pointing to an image for the front cover of the book.
 *   This image gets changed on the server. Thus the UI representation of the book needs to be updated
 *   to reflect the updated image on the server. You realize that all your views are already listening for
 *   YapDatabaseModified notifications, so if you update the object in the database then all your views are
 *   already wired to update the UI appropriately. However, the actual object itself didn't change. So while
 *   there technically isn't any reason to update the object on disk, doing so would be the easiest way to
 *   keep the UI up-to-date. So what you really want is a way to "mark" the object as updated, without actually
 *   incurring the overhead of rewriting it to disk.
 *
 * And this is exactly what the touch methods were designed for.
 * It won't actually cause the object to get rewritten to disk.
 * However, it will mark the object as "updated" within the YapDatabaseModified notification,
 * so any UI components listening for changes will see this object as updated, and can update as appropriate.
 *
 * The touchObjectForKey:inCollection: method is similar to calling setObject:forKey:inCollection:withMetadata:,
 * and passing the object & metadata that already exists for the key. But without the overhead of fetching the items,
 * or re-writing the items to disk.
 *
 * The touchMetadataForKey: method is similar to calling replaceMetadata:forKey:,
 * and passing the metadata that already exists for the key. But without the overhead of fetching the metadata,
 * or re-writing the metadata to disk.
 * 
 * Note: It is safe to touch objects during enumeration.
 * Normally, altering the database while enumerating it will result in an exception (just like altering an array
 * while enumerating it). However, it's safe to touch objects during enumeration.
**/
- (void)touchObjectForKey:(NSString *)key inCollection:(NSString *)collection;
- (void)touchMetadataForKey:(NSString *)key inCollection:(NSString *)collection;

#pragma mark Remove

/**
 * Deletes the database row with the given key/collection.
 * This method is automatically called if you invoke
 * setObject:forKey:collection: or setPrimitiveData:forKey:collection: and pass nil object/data.
**/
- (void)removeObjectForKey:(NSString *)key inCollection:(NSString *)collection;

/**
 * Deletes the database rows with the given keys in the given collection.
**/
- (void)removeObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection;

/**
 * Deletes every key/object pair from the given collection.
 * No trace of the collection will remain afterwards.
**/
- (void)removeAllObjectsInCollection:(NSString *)collection;

/**
 * Removes every key/object pair in the entire database (from all collections).
**/
- (void)removeAllObjectsInAllCollections;

@end
