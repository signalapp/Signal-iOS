#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapWhitelistBlacklist.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * A "proxy" connection is a trade-off in terms of the ACID guarantees of the database.
 * 
 * Under normal operations, you must execute a read-write transaction in order to modify the datatbase.
 * If the transaction completes, then all data from the transaction has been written to the database.
 * And further, the transaction is durable even in the event of an application or system crash.
 * In other words, you're guaranteed the data will be there when the app re-launches.
 *
 * A proxy connection allows you to relax these constraints,
 * which may be useful for certain subsets of your data.
 * 
 * Here's how it works:
 * - you write collection/key/value rows to a proxy connection instance
 * - the value(s) are immediately readable via the proxy connection instance
 * - the proxy will attempt to write the changes (in batches) at some point in the near future
 * 
 * Thus you can read & write values as if the proxy is an in-memory dictionary.
 * However, the proxy will transparently write the changes to the database (but without any guarantees).
 * 
 * ** When should I use a proxy ?
 * 
 * You can use a proxy when:
 * - it's not important that you manage an individual transaction
 * - it's not important if the values don't make it to disk
 *
 * Example #1 : A download manager
 * 
 *   Applications sometimes have download logic encapsulated in a "manager" class.
 *   The manager class typically handles things such as:
 *   - downloaing resources on demand
 *   - parsing the results
 *   - providing getter methods to fetch particular items
 *   - automatically checking expiration dates & refreshing items as needed
 *   - automatically deleting unused expired items
 * 
 *   You'll notice the manager class is the ONLY class that handles reading/writing certain values in the database.
 *   And it doesn't matter if a value doesn't get written to disk, as it can simply be re-downloaed.
 * 
 * Example #2 : NSUserDefaults replacement
 *
 *   NSUserDefaults works similarly to a connection proxy.
 *   From the documentation for NSUserDefaults:
 *
 *   > The synchronize method, which is automatically invoked at periodic intervals,
 *   > keeps the in-memory cache in sync with a user’s defaults database.
 *  
 *   So NSUserDefaults will "eventually" write changes to disk.
 *   Unless you invoke the synchronize method, which involves waiting for disk IO to complete.
 * 
 *   Thus a connection proxy can easily replace your NSUserDefaults system.
 *   It's worth pointing out that a proxy connection doesn't have the equivalent of a synchronize method because
 *   you don't need one. A connection proxy always begins an asyncReadWrite transaction once it becomes "dirty".
 * 
 *   In case you're wondering, "Why would I use YapDatabase over NSUserDefaults ?"
 *   
 *   1. NSUserDefaults is not encrypted. And you can easily encrypt a YapDatabase.
 *   2. NSUserDefaults writes ALL values to disk everytime because it uses a plist to store the values on disk.
 *      YapDatabase uses a database, so only changed values need to be re-written.
 *      Thus, YapDatabase has the potential to be faster and involve less disk IO.
 *   3. YapDatabase has a notification system that tells you exactly which key/value pairs were changed.
 *   4. YapDatabase makes it easier to sync your data using a wide variety of cloud services.
 * 
 * ** Caveats
 *
 * A connection proxy instance expects to "own" a subset of the database.
 * That is, it expects to be the only thing reading & writing a subset of rows in the database.
 * If you violate this, you may get unexpected results.
 * 
 * Example #1 :
 * 
 *   - You write a value using a proxy.
 *   - You then attempt to read that value using a regular database connection.
 *   - If the proxy hasn't written the value to disk yet,
 *     then the regualar database connection won't see the proper value.
 * 
 * Example #2 :
 *   
 *   - You write a value using the proxy.
 *   - You write a different value (for the same collection/key) using the regular database connection.
 *   - The proxy later performs a readWrite, and writes its value for the collection/key,
 *     overwriting the regular database connection.
**/
@interface YapDatabaseConnectionProxy : NSObject

/**
 * Initializes a new connction proxy by creating both the readOnlyConnection & readWriteConnection
 * via [database newConnection]. Both connection's receive the default configuration for the database.
**/
- (instancetype)initWithDatabase:(YapDatabase *)database;

/**
 * Initializes a new connection proxy using the (optional) given connections.
 *
 * @param database
 *   The underlying database to use.
 *
 * @param readOnlyConnection
 *   You may pass a readOnlyConnection if you want to share a read-only connection amongst multiple classes.
 *   However, you must be sure to NEVER perform a write on the read-only connection.
 * 
 * @param readWriteConnection
 *   You may pass a readWriteConnection if you want to share a read-write connection amongst multiple classes.
**/
- (instancetype)initWithDatabase:(YapDatabase *)database
              readOnlyConnection:(nullable YapDatabaseConnection *)readOnlyConnection
             readWriteConnection:(nullable YapDatabaseConnection *)readWriteConnection;

@property (nonatomic, strong, readonly) YapDatabaseConnection *readOnlyConnection;
@property (nonatomic, strong, readonly) YapDatabaseConnection *readWriteConnection;

/**
 * Returns the proxy's value for the given collection/key tuple.
 * 
 * If this proxy instance has recently had a value set for the given collection/key,
 * then that value is returned, even if the value has not been written to the database yet.
**/
- (id)objectForKey:(NSString *)key inCollection:(nullable NSString *)collection;
- (id)metadataForKey:(NSString *)key inCollection:(nullable NSString *)collection;

- (BOOL)getObject:(__nullable id * __nullable)objectPtr
         metadata:(__nullable id * __nullable)metadataPtr
           forKey:(NSString *)key
     inCollection:(nullable NSString *)collection;

/**
 * Sets a value for the given collection/key tuple.
 * 
 * The proxy will attempt to write the value to the database at some point in the near future.
 * If the application is terminated before the write completes, then the value may not make it to the database.
 * However, the proxy will immediately begin to return the new value when queried for the same collection/key tuple.
 *
 * This is the trade-off you make when using a proxy.
 * The values written to a proxy are not guaranteed to be written to the database.
 * However, the values are immediately available (from this proxy instance) without waiting for the database disk IO.
 *
 * @param object
 *   The value for the collection/key tuple.
 *   If nil, this is equivalent to invoking removeObjectForKey:inCollection:
**/
- (void)setObject:(nullable id)object forKey:(NSString *)key inCollection:(nullable NSString *)collection;
- (void)setObject:(nullable id)object
           forKey:(NSString *)key
     inCollection:(nullable NSString *)collection
     withMetadata:(nullable id)metadata;

/**
 * The replace methods allows you to modify the object, without modifying the metadata for the row.
 * Or vice-versa, you can modify the metadata, without modifying the object for the row.
 * 
 * If there is no row in the database for the given key/collection then this method does nothing.
 *
 * The proxy will attempt to write the value to the database at some point in the near future.
 * If the application is terminated before the write completes, then the value may not make it to the database.
 * However, the proxy will immediately begin to return the new value when queried for the same collection/key tuple.
 *
 * This is the trade-off you make when using a proxy.
 * The values written to a proxy are not guaranteed to be written to the database.
 * However, the values are immediately available (from this proxy instance) without waiting for the database disk IO.
**/
- (void)replaceObject:(nullable id)object forKey:(NSString *)key inCollection:(nullable NSString *)collection;
- (void)replaceMetadata:(nullable id)metadata forKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * Removes any set value for the given collection/key tuple.
 * 
 * The proxy will attempt to remove the value from the database at some point in the near future.
 * If the application is terminated before the write completes, then the update may not make it to the database.
 * However, the proxy will immediately begin to return nil when queried for the same collection/key tuple.
 *
 * This is the trade-off you make when using a proxy.
 * The values written to a proxy are not guaranteed to be written to the database.
 * However, the values are immediately available (from this proxy instance) without waiting for the database disk IO.
**/
- (void)removeObjectForKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * Removes any set value(s) for the given collection/key tuple(s).
 * 
 * The proxy will attempt to remove the value(s) from the database at some point in the near future.
 * If the application is terminated before the write completes, then the update may not make it to the database.
 * However, the proxy will immediately begin to return nil when queried for the same collection/key tuple.
 *
 * This is the trade-off you make when using a proxy.
 * The values written to a proxy are not guaranteed to be written to the database.
 * However, the values are immediately available (from this proxy instance) without waiting for the database disk IO.
**/
- (void)removeObjectsForKeys:(NSArray<NSString *> *)keys inCollection:(nullable NSString *)collection;

/**
 * Immediately discards all changes that were queued to be written to the database.
 * Thus any pending changes are not written to the database,
 * and any currently queued readWriteTransaction is aborted.
 *
 * This method is typically used if you intend to clear the database.
 * For example:
 *
 * // blacklist everything - act as if db is empty
 * YapWhitelistBlacklist *whitelist = [[YapWhitelistBlacklist alloc] initWithWhitelist:nil];
 * [connectionProxy abortAndReset:whitelist];
 * 
 * // Then actually clear the db - but asynchronously
 * [connectionProxy.readWriteConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
 * 
 *     [transaction removeAllObjectsInAllCollections];
 *
 * } completionBlock:^{
 *     
 *     // allow the connectionProxy to start reading from the db again
 *     connectionProxy.fetchedCollectionsFilter = nil;
 * }];
 * 
 * @param fetchedCollectionsFilter
 *   This parameter allows you to instruct the connectionProxy to act as if
 *   the readOnlyConnection doesn't see any objects within certain collections.
 *
 * @see fetchedCollectionsFilter
**/
- (void)abortAndReset:(nullable YapWhitelistBlacklist *)fetchedCollectionsFilter;

/**
 * The fetchedCollectionsFilter is useful when you need to delete one or more collections from the database.
 * For example:
 * - you're going to ASYNCHRONOUSLY delete the "foobar" collection from the database
 * - you want to instruct the connectionProxy to act as if it's readOnlyConnection doesn't see
 *   any objects in this collection (even before the ASYNC cleanup transaction completes).
 * - when the cleanup transaction does complete, you instruct the connectionProxy to return to normal.
 *
 * NSSet *set = [NSSet setWithObject:@"foobar"];
 * YapWhitelistBlacklist *blacklist = [[YapWhitelistBlacklist alloc] initWithBlacklist:set];
 * connectionProxy.fetchedCollectionsFilter = blacklist;
 * 
 * [connectionProxy.readWriteConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
 *
 *     [transaction removeAllObjectsInCollection:@"foobar"];
 *
 * } completionBlock:^{
 *
 *     // allow the connectionProxy to start reading the "foobar" collection again
 *     connectionProxy.fetchedCollectionsFilter = nil;
 * }];
 * 
 * Keep in mind that the fetchedCollectionsFilter only applies to how the proxy interacts with the readOnlyConnection.
 * That is, it still allows the proxy to write values to any collection.
**/
@property (atomic, strong, readwrite, nullable) YapWhitelistBlacklist *fetchedCollectionsFilter;

@end

NS_ASSUME_NONNULL_END
