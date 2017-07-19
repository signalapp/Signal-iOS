#import <Foundation/Foundation.h>

@class YapDatabaseConnection;
@class YapDatabaseExtensionTransaction;

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yapstudios/YapDatabase/wiki
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

/**
 * The userInfo property allows arbitrary info to be associated with the transaction.
 * This propery is not used by YapDatabaseTransaction in any way.
 * 
 * Keep in mind that transactions are short lived objects.
 * Each transaction is a new/different transaction object.
**/
@property (nonatomic, strong, readwrite, nullable) id userInfo;

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
- (NSUInteger)numberOfKeysInCollection:(nullable NSString *)collection;

/**
 * Returns the total number of key/object pairs in the entire database (including all collections).
**/
- (NSUInteger)numberOfKeysInAllCollections;

#pragma mark List

/**
 * Returns a list of all collection names.
 * 
 * If the list of collections is really big, it may be more efficient to enumerate them instead.
 * @see enumerateCollectionsUsingBlock:
**/
- (NSArray<NSString *> *)allCollections;

/**
 * Returns a list of all keys in the given collection.
 * 
 * If the list of keys is really big, it may be more efficient to enumerate them instead.
 * @see enumerateKeysInCollection:usingBlock:
**/
- (NSArray<NSString *> *)allKeysInCollection:(nullable NSString *)collection;

#pragma mark Object & Metadata

/**
 * Object access.
 * Objects are automatically deserialized using database's configured deserializer.
**/
- (nullable id)objectForKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * Returns whether or not the given key/collection exists in the database.
**/
- (BOOL)hasObjectForKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * Provides access to both object and metadata in a single call.
 *
 * @return YES if the key exists in the database. NO otherwise, in which case both object and metadata will be nil.
**/
- (BOOL)getObject:(__nullable id * __nullable)objectPtr
         metadata:(__nullable id * __nullable)metadataPtr
           forKey:(NSString *)key
     inCollection:(nullable NSString *)collection;

/**
 * Provides access to the metadata.
 * This fetches directly from the metadata dictionary stored in memory, and thus never hits the disk.
**/
- (nullable id)metadataForKey:(NSString *)key inCollection:(nullable NSString *)collection;

#pragma mark Primitive

/**
 * Primitive access.
 * This method is available in-case you have a need to fetch the raw serializedObject from the database.
 * 
 * This method is slower than objectForKey:inCollection:, since that method makes use of the objectCache.
 * In contrast, this method always fetches the raw data from disk.
 * 
 * @see objectForKey:inCollection:
**/
- (nullable NSData *)serializedObjectForKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * Primitive access.
 * This method is available in-case you have a need to fetch the raw serializedMetadata from the database.
 * 
 * This method is slower than metadataForKey:inCollection:, since that method makes use of the metadataCache.
 * In contrast, this method always fetches the raw data from disk.
 *
 * @see metadataForKey:inCollection:
**/
- (nullable NSData *)serializedMetadataForKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * Primitive access.
 * This method is available in-case you have a need to fetch the raw serialized forms from the database.
 *
 * This method is slower than getObject:metadata:forKey:inCollection:, since that method makes use of the caches.
 * In contrast, this method always fetches the raw data from disk.
 *
 * @see getObject:metadata:forKey:inCollection:
**/
- (BOOL)getSerializedObject:(NSData * __nullable * __nullable)serializedObjectPtr
         serializedMetadata:(NSData * __nullable * __nullable)serializedMetadataPtr
                     forKey:(NSString *)key
               inCollection:(nullable NSString *)collection;

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
- (void)enumerateKeysInCollection:(nullable NSString *)collection
                       usingBlock:(void (^)(NSString *key, BOOL *stop))block;

/**
 * Fast enumeration over all keys in the given collection.
 *
 * This uses a "SELECT collection, key FROM database" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)enumerateKeysInAllCollectionsUsingBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block;

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
- (void)enumerateKeysAndObjectsInCollection:(nullable NSString *)collection
                                 usingBlock:(void (^)(NSString *key, id object, BOOL *stop))block;

/**
 * Fast enumeration over objects in the database for which you're interested in.
 * The filter block allows you to decide which objects you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
**/
- (void)enumerateKeysAndObjectsInCollection:(nullable NSString *)collection
                                 usingBlock:(void (^)(NSString *key, id object, BOOL *stop))block
                                 withFilter:(nullable BOOL (^)(NSString *key))filter;

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
                                 withFilter:(nullable BOOL (^)(NSString *collection, NSString *key))filter;

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
- (void)enumerateKeysAndMetadataInCollection:(nullable NSString *)collection
                                  usingBlock:(void (^)(NSString *key, __nullable id metadata, BOOL *stop))block;

/**
 * Fast enumeration over all keys and associated metadata in the given collection.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
 * 
 * Keep in mind that you cannot modify the collection mid-enumeration (just like any other kind of enumeration).
**/
- (void)enumerateKeysAndMetadataInCollection:(nullable NSString *)collection
                                  usingBlock:(void (^)(NSString *key, __nullable id metadata, BOOL *stop))block
                                  withFilter:(nullable BOOL (^)(NSString *key))filter;



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
                            (void (^)(NSString *collection, NSString *key, __nullable id metadata, BOOL *stop))block;

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
                            (void (^)(NSString *collection, NSString *key, __nullable id metadata, BOOL *stop))block
                 withFilter:(nullable BOOL (^)(NSString *collection, NSString *key))filter;

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
- (void)enumerateRowsInCollection:(nullable NSString *)collection
                       usingBlock:(void (^)(NSString *key, id object, __nullable id metadata, BOOL *stop))block;

/**
 * Fast enumeration over rows in the database for which you're interested in.
 * The filter block allows you to decide which rows you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object & metadata.
**/
- (void)enumerateRowsInCollection:(nullable NSString *)collection
                       usingBlock:(void (^)(NSString *key, id object, __nullable id metadata, BOOL *stop))block
                       withFilter:(nullable BOOL (^)(NSString *key))filter;

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
                    (void (^)(NSString *collection, NSString *key, id object, __nullable id metadata, BOOL *stop))block;

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
                    (void (^)(NSString *collection, NSString *key, id object, __nullable id metadata, BOOL *stop))block
         withFilter:(nullable BOOL (^)(NSString *collection, NSString *key))filter;

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
- (void)enumerateObjectsForKeys:(NSArray<NSString *> *)keys
                   inCollection:(nullable NSString *)collection
            unorderedUsingBlock:(void (^)(NSUInteger keyIndex, id __nullable object, BOOL *stop))block;

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
- (void)enumerateMetadataForKeys:(NSArray<NSString *> *)keys
                    inCollection:(nullable NSString *)collection
             unorderedUsingBlock:(void (^)(NSUInteger keyIndex, __nullable id metadata, BOOL *stop))block;

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
- (void)enumerateRowsForKeys:(NSArray<NSString *> *)keys
                inCollection:(nullable NSString *)collection
         unorderedUsingBlock:(void (^)(NSUInteger keyIndex, __nullable id object, __nullable id metadata, BOOL *stop))block;

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
- (nullable __kindof YapDatabaseExtensionTransaction *)extension:(NSString *)extensionName;
- (nullable __kindof YapDatabaseExtensionTransaction *)ext:(NSString *)extensionName; // <-- Shorthand (same as extension: method)

NS_ASSUME_NONNULL_END
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseReadWriteTransaction : YapDatabaseReadTransaction
NS_ASSUME_NONNULL_BEGIN

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
 * https://github.com/yapstudios/YapDatabase/wiki/YapDatabaseModifiedNotification
**/
@property (nonatomic, strong, readwrite, nullable) id yapDatabaseModifiedNotificationCustomObject;

#pragma mark Object & Metadata

/**
 * Sets the object for the given key/collection.
 * The object is automatically serialized using the database's configured objectSerializer.
 *
 * If you pass nil for the object, then this method will remove the row from the database (if it exists).
 * This method implicitly sets the associated metadata to nil.
 * 
 * @param object
 *   The object to store in the database.
 *   This object is automatically serialized using the database's configured objectSerializer.
 * 
 * @param key
 *   The lookup key.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   This value should not be nil. If a nil key is passed, then this method does nothing.
 * 
 * @param collection
 *   The lookup collection.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   If a nil collection is passed, then the collection is implicitly the empty string (@"").
**/
- (void)setObject:(nullable id)object forKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * Sets the object & metadata for the given key/collection.
 *
 * If you pass nil for the object, then this method will remove the row from the database (if it exists).
 * 
 * @param object
 *   The object to store in the database.
 *   This object is automatically serialized using the database's configured objectSerializer.
 * 
 * @param key
 *   The lookup key.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   This value should not be nil. If a nil key is passed, then this method does nothing.
 * 
 * @param collection
 *   The lookup collection.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   If a nil collection is passed, then the collection is implicitly the empty string (@"").
 * 
 * @param metadata
 *   The metadata to store in the database.
 *   This metadata is automatically serialized using the database's configured metadataSerializer.
 *   The metadata is optional. You can pass nil for the metadata is unneeded.
 *   If non-nil then the metadata is also written to the database (metadata is also persistent).
**/
- (void)setObject:(nullable id)object
           forKey:(NSString *)key
     inCollection:(nullable NSString *)collection
     withMetadata:(nullable id)metadata;

/**
 * Sets the object & metadata for the given key/collection.
 * 
 * If you pass nil for the object, then this method will remove the row from the database (if it exists).
 *
 * This method allows for a bit of optimization if you happen to already have a serialized version of
 * the object and/or metadata. For example, if you downloaded an object in serialized form,
 * and you still have the raw serialized NSData, then you can use this method to skip the serialization step
 * when storing the object to the database.
 *
 * @param object
 *   The object to store in the database.
 *   This object is automatically serialized using the database's configured objectSerializer.
 *
 * @param key
 *   The lookup key.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   This value should not be nil. If a nil key is passed, then this method does nothing.
 *
 * @param collection
 *   The lookup collection.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   If a nil collection is passed, then the collection is implicitly the empty string (@"").
 *
 * @param metadata
 *   The metadata to store in the database.
 *   This metadata is automatically serialized using the database's configured metadataSerializer.
 *   The metadata is optional. You can pass nil for the metadata is unneeded.
 *   If non-nil then the metadata is also written to the database (metadata is also persistent).
 * 
 * @param preSerializedObject
 *   This value is optional.
 *   If non-nil then the object serialization step is skipped, and this value is used instead.
 *   It is assumed that preSerializedObject is equal to what we would get if we ran the object through
 *   the database's configured objectSerializer.
 * 
 * @param preSerializedMetadata
 *   This value is optional.
 *   If non-nil then the metadata serialization step is skipped, and this value is used instead.
 *   It is assumed that preSerializedMetadata is equal to what we would get if we ran the metadata through
 *   the database's configured metadataSerializer.
 *
 * The preSerializedObject is only used if object is non-nil.
 * The preSerializedMetadata is only used if metadata is non-nil.
**/
- (void)setObject:(nullable id)object forKey:(NSString *)key
                                inCollection:(nullable NSString *)collection
                                withMetadata:(nullable id)metadata
                            serializedObject:(nullable NSData *)preSerializedObject
                          serializedMetadata:(nullable NSData *)preSerializedMetadata;

/**
 * If a row with the given key/collection exists, then replaces the object for that row with the new value.
 * 
 * It only replaces the object. The metadata for the row doesn't change.
 * If there is no row in the database for the given key/collection then this method does nothing.
 * 
 * If you pass nil for the object, then this method will remove the row from the database (if it exists).
 * 
 * @param object
 *   The object to store in the database.
 *   This object is automatically serialized using the database's configured objectSerializer.
 * 
 * @param key
 *   The lookup key.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   This value should not be nil. If a nil key is passed, then this method does nothing.
 * 
 * @param collection
 *   The lookup collection.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   If a nil collection is passed, then the collection is implicitly the empty string (@"").
**/
- (void)replaceObject:(nullable id)object forKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * If a row with the given key/collection exists, then replaces the object for that row with the new value.
 *
 * It only replaces the object. The metadata for the row doesn't change.
 * If there is no row in the database for the given key/collection then this method does nothing.
 *
 * If you pass nil for the object, then this method will remove the row from the database (if it exists).
 * 
 * This method allows for a bit of optimization if you happen to already have a serialized version of
 * the object and/or metadata. For example, if you downloaded an object in serialized form,
 * and you still have the raw serialized NSData, then you can use this method to skip the serialization step
 * when storing the object to the database.
 *
 * @param object
 *   The object to store in the database.
 *   This object is automatically serialized using the database's configured objectSerializer.
 *
 * @param key
 *   The lookup key.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   This value should not be nil. If a nil key is passed, then this method does nothing.
 *
 * @param collection
 *   The lookup collection.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   If a nil collection is passed, then the collection is implicitly the empty string (@"").
 *
 * @param preSerializedObject
 *   This value is optional.
 *   If non-nil then the object serialization step is skipped, and this value is used instead.
 *   It is assumed that preSerializedObject is equal to what we would get if we ran the object through
 *   the database's configured objectSerializer.
**/
- (void)replaceObject:(nullable id)object
               forKey:(NSString *)key
         inCollection:(nullable NSString *)collection
 withSerializedObject:(nullable NSData *)preSerializedObject;

/**
 * If a row with the given key/collection exists, then replaces the metadata for that row with the new value.
 * 
 * It only replaces the metadata. The object for the row doesn't change.
 * If there is no row in the database for the given key/collection then this method does nothing.
 * 
 * If you pass nil for the metadata, any metadata previously associated with the key/collection is removed.
 * 
 * @param metadata
 *   The metadata to store in the database.
 *   This metadata is automatically serialized using the database's configured metadataSerializer.
 *
 * @param key
 *   The lookup key.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   This value should not be nil. If a nil key is passed, then this method does nothing.
 * 
 * @param collection
 *   The lookup collection.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   If a nil collection is passed, then the collection is implicitly the empty string (@"").
**/
- (void)replaceMetadata:(nullable id)metadata forKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * If a row with the given key/collection exists, then replaces the metadata for that row with the new value.
 *
 * It only replaces the metadata. The object for the row doesn't change.
 * If there is no row in the database for the given key/collection then this method does nothing.
 *
 * If you pass nil for the metadata, any metadata previously associated with the key/collection is removed.
 *
 * This method allows for a bit of optimization if you happen to already have a serialized version of
 * the object and/or metadata. For example, if you downloaded an object in serialized form,
 * and you still have the raw serialized NSData, then you can use this method to skip the serialization step
 * when storing the object to the database.
 * 
 * @param metadata
 *   The metadata to store in the database.
 *   This metadata is automatically serialized using the database's configured metadataSerializer.
 *
 * @param key
 *   The lookup key.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   This value should not be nil. If a nil key is passed, then this method does nothing.
 *
 * @param collection
 *   The lookup collection.
 *   The <collection, key> tuple is used to uniquely identify the row in the database.
 *   If a nil collection is passed, then the collection is implicitly the empty string (@"").
 * 
 * @param preSerializedMetadata
 *   This value is optional.
 *   If non-nil then the metadata serialization step is skipped, and this value is used instead.
 *   It is assumed that preSerializedMetadata is equal to what we would get if we ran the metadata through
 *   the database's configured metadataSerializer.
**/
- (void)replaceMetadata:(nullable id)metadata
                 forKey:(NSString *)key
           inCollection:(nullable NSString *)collection
 withSerializedMetadata:(nullable NSData *)preSerializedMetadata;

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
 * - touchObjectForKey:inCollection:
 *   Similar to calling replaceObject:forKey:inCollection: and passing the object that already exists.
 *   But without the overhead of fetching the object, or re-writing it to disk.
 *
 * - touchMetadataForKey:inCollection:
 *   Similar to calling replaceMetadata:forKey:inCollection: and passing the metadata that already exists.
 *   But without the overhead of fetching the metadata, or re-writing it to disk.
 * 
 * - touchRowForKey:inCollection:
 *   Similar to calling setObject:forKey:inCollection:withMetadata: and passing the object & metadata the already exist.
 *   But without the overhead of fetching the items, or re-writing them to disk.
 *
 * Note: It is safe to touch items during enumeration.
 * Normally, altering the database while enumerating it will result in an exception (just like altering an array
 * while enumerating it). However, it's safe to touch items during enumeration.
**/
- (void)touchObjectForKey:(NSString *)key inCollection:(nullable NSString *)collection;
- (void)touchMetadataForKey:(NSString *)key inCollection:(nullable NSString *)collection;
- (void)touchRowForKey:(NSString *)key inCollection:(nullable NSString *)collection;

#pragma mark Remove

/**
 * Deletes the database row with the given key/collection.
 *
 * This method is automatically called if you invoke
 * setObject:forKey:collection: and pass a nil object.
**/
- (void)removeObjectForKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * Deletes the database rows with the given keys in the given collection.
**/
- (void)removeObjectsForKeys:(NSArray<NSString *> *)keys inCollection:(nullable NSString *)collection;

/**
 * Deletes every key/object pair from the given collection.
 * No trace of the collection will remain afterwards.
**/
- (void)removeAllObjectsInCollection:(nullable NSString *)collection;

/**
 * Removes every key/object pair in the entire database (from all collections).
**/
- (void)removeAllObjectsInAllCollections;

#pragma mark Completion

/**
 * It's often useful to compose code into various reusable functions which take a
 * YapDatabaseReadWriteTransaction as a parameter. However, the ability to compose code
 * in this manner is often prevented by the need to perform a task after the commit has finished.
 * 
 * The end result is that programmers either end up copy-pasting code,
 * or hack together a solution that involves functions returning completion blocks.
 *
 * This method solves the dilemma by allowing encapsulated code to register its own commit completionBlock.
**/
- (void)addCompletionQueue:(nullable dispatch_queue_t)completionQueue
           completionBlock:(dispatch_block_t)completionBlock;

@end

NS_ASSUME_NONNULL_END
