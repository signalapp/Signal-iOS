#import <Foundation/Foundation.h>
#import "YapDatabase.h"
#import "sqlite3.h"

@protocol YapOrderReadTransaction;
@protocol YapOrderReadWriteTransaction;

/**
 * YapDatabaseOrder provides the logic for storing explicit ordering information for keys.
 *
 * That is, if a group of keys/objects is to be given a persistent order, this class provides various
 * methods to persist the order to disk, and to later retrieve the order.
 * 
 * Here's how it works:
 *
 * Conceptually it simply maintains an ordered array of keys. However, internally it paginates the array,
 * and stores multiple pages (of keys) to the database. This means adding and removing keys generally only
 * affects a single page, thereby reducing the amount of information written to disk.
 * 
 * Furthermore the maximum page size is fully configurable, as is the number of pages the class will keep in memory.
 * This allows the memory footprint to be configurable.
 * 
 * This class also provides the scaffolding necessary to maintain multiple instances that
 * snapshot from a "master", and sync changes back to the "master".
**/
@interface YapDatabaseOrder : NSObject

/**
 * Creates a new instance.
 * You must invoke prepare before attempting to use the instance.
**/
- (id)init;
- (id)initWithUserInfo:(id)userInfo;

/**
 * Prepares the instance for use.
 *
 * This method should be called before you start to use it.
 * You may also call this method at any time in order to reset & re-prepare it.
 *
 * When this method is invoked, it will invoke dataForKey:order: in order to read the page metadata.
 * That is, it will read in the metadata that details the number of pages, the size of each, and their respective order.
 * No pages are pulled into memory at this time.
 *
 * If you rely on the userInfo property from within YapOrderTransaction protocol methods,
 * you must set the userInfo before invoking this method.
 *
 * Note: If you know this is the first creation of the order, you can pass NULL.
 * This will effectively skip the attempt to read previously stored page metadata.
**/
- (void)prepare:(id <YapOrderReadTransaction>)transaction;

/**
 * Whether or not the order object is prepared.
 * The result will be YES if:
 * - the prepare method has been invoked
 * - the mergeChangeset method has been invoked (which prepared the object from data from another order)
**/
- (BOOL)isPrepared;

/**
 * Clears page metadata and cached pages.
 * 
 * After invoking this method, the isPrepared method will return NO.
 * Before using this instance again, you'll need to invoke the prepare method.
 * 
 * Note: This method does not clear non-persistent configuration information (userInfo, maxPagesInMemory).
 * Persistent configuration information (maxPageSize) will be re-read from disk during prepare.
**/
- (void)reset;

#pragma mark Transaction

/**
 * This method should be invoked within a read-write block's commit stage.
 * It allows this class to perform any needed disk writes.
 * 
 * The general flow of a YapDatabaseOrder instance is:
 * 1. An instance is created via init and then prepared (once).
 * 2. From within a transaction, various methods are used to manage the key order.
 * 3. Whenever a read-write transaction is completed, the instance's commitTransaction method is invoked.
 * 4. Repeat steps 2 & 3 as needed.
**/
- (void)commitTransaction:(id <YapOrderReadWriteTransaction>)transaction;

#pragma mark Snapshot

/**
 * Returns whether or not the order has been modified since the last time commitTransaction was called.
**/
- (BOOL)isModified;

/**
 * Fetches a changeset that encapsulates information about changes since the last time commitTransaction was called.
 * This dictionary may be passed to another instance running on another connection in order to keep them synced.
**/
- (NSDictionary *)changeset;

/**
 * Merges changes from a sibling instance.
**/
- (void)mergeChangeset:(NSDictionary *)changeset;

#pragma mark Configuration

/**
 * Can be used to associate any information with this instance that may be needed externally.
 * 
 * The userInfo property is not used by the YapDatabaseOrder object in any way.
 * It is used by YapOrderedCollectionsDatabase to store the associated collection name.
**/
@property (nonatomic, strong, readwrite) id userInfo;

/**
 * Specifies the maximum number of (non dirty) pages to keep in memory.
 * 
 * This value (along with maxPageSize) allows you to control the memory footprint of the instance.
 * If you have a very big database, you may wish to enable this feature.
 *
 * The default value is 0 (disabled, all pages kept in memory for max speed).
 * This value is appropriate for most small databases.
 *
 * You can change the maxPagesInMemory at any time.
 * When changed the instance may fault some of its pages of keys.
**/
- (NSUInteger)maxPagesInMemory;
- (void)setMaxPagesInMemory:(NSUInteger)maxPagesInMemory;

#pragma mark Persistent Configuration

/**
 * Specifies the maximum number of keys to keep in a single page.
 *
 * This value affects performance in the following manner:
 * 
 * - Adding & removing keys generally only changes a single page,
 *   but obviously requires the page to get rewritten to disk.
 *   If the pageSize is too big, the resulting page rewrite will take more time.
 *
 * - The instance can optionally keep a maximum number of pages in memory.
 *   If your database is very large, this can help reduce memory.
 *
 * The default maxPageSize is 100.
 *
 * You can change the maxPageSize at any time.
 * When changed the instance will restructure its pages of keys.
 * 
 * This configuration value is persisted to disk.
 * It is automatically loaded via the prepare method.
**/
- (NSUInteger)maxPageSize;
- (void)setMaxPageSize:(NSUInteger)maxPageSize transaction:(id <YapOrderReadWriteTransaction>)transaction;

#pragma mark Pages

/**
 * Primitive methods.
 * For advanced users, provides direct access to the underlying pages.
 *
 * Most of the time you'll use numberOfKeys and/or keyForIndex:: instead.
 * However, if you need to enumerate all the keys in the database,
 * enumerating the individual pages is likely a bit faster.
**/
- (NSUInteger)numberOfPages;
- (NSArray *)pageForIndex:(NSUInteger)index transaction:(id <YapOrderReadTransaction>)transaction;

#pragma mark Keys

/**
 * Core methods.
 * Most use cases use these to fetch keys on demand.
**/
- (NSUInteger)numberOfKeys;
- (BOOL)hasZeroKeys;
- (NSString *)keyAtIndex:(NSUInteger)index transaction:(id <YapOrderReadTransaction>)transaction;

/**
 * Group fetching.
 * Use these methods to fetch groups of keys in a single fetch.
 * Using these methods is faster than looping and fetching one key at a time.
**/
- (NSArray *)allKeys:(id <YapOrderReadTransaction>)transaction;
- (NSArray *)keysInRange:(NSRange)range transaction:(id <YapOrderReadTransaction>)transaction;

#pragma mark Add

/**
 * Allows you to specify ordering information for a given key.
 * 
 * Append  == Add key to end of array
 * Prepend == Add key to beginning of array
 * Insert  == Add key to specific index in array
**/
- (void)appendKey:(NSString *)key transaction:(id <YapOrderReadWriteTransaction>)transaction;
- (void)prependKey:(NSString *)key transaction:(id <YapOrderReadWriteTransaction>)transaction;

- (void)insertKey:(NSString *)key atIndex:(NSUInteger)index transaction:(id <YapOrderReadWriteTransaction>)transaction;

#pragma mark Remove

/**
 * Removes the key(s) at the given index(es).
 * These methods are faster than removeKey: or removeKeys: as they don't require searching for the key.
 * 
 * The removed key(s) are returned. This may be used to optimize database access.
 * In other words, invoke this method first to remove the keys AND simulatneously fetch them.
 * Then turn around and invoke removeKey: or removeKeys: on the actual YapDatabase.
**/
- (NSString *)removeKeyAtIndex:(NSUInteger)index transaction:(id <YapOrderReadWriteTransaction>)transaction;
- (NSArray *)removeKeysInRange:(NSRange)range transaction:(id <YapOrderReadWriteTransaction>)transaction;

/**
 * Removes the given key/keys.
 * 
 * Only use this method if you don't already know the index of the key.
 * Otherwise, it is far faster to use the removeKeyAtIndex: method, as this method must search for the key.
**/
- (void)removeKey:(NSString *)key transaction:(id <YapOrderReadWriteTransaction>)transaction;
- (void)removeKeys:(NSArray *)keys transaction:(id <YapOrderReadWriteTransaction>)transaction;

/**
 * Removes all keys.
**/
- (void)removeAllKeys:(id <YapOrderReadWriteTransaction>)transaction;

#pragma mark Enumerate

/**
 * Enumerates the keys.
 * You can enumerate all keys, or a given range.
 *
 * Reverse enumeration is supported by passing NSEnumerationReverse. (No other enumeration options are supported.)
**/
- (void)enumerateKeysUsingBlock:(void (^)(NSUInteger idx, NSString *key, BOOL *stop))block
                    transaction:(id <YapOrderReadTransaction>)transaction;

- (void)enumerateKeysWithOptions:(NSEnumerationOptions)options
                      usingBlock:(void (^)(NSUInteger idx, NSString *key, BOOL *stop))block
                     transaction:(id <YapOrderReadTransaction>)transaction;

- (void)enumerateKeysInRange:(NSRange)range
                 withOptions:(NSEnumerationOptions)options
                  usingBlock:(void (^)(NSUInteger idx, NSString *key, BOOL *stop))block
                 transaction:(id <YapOrderReadTransaction>)transaction;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The external transaction (always passed as a parameter in the above methods)
 * is in charge of persisting and retrieving order data from disk.
 *
 * A YapDatabaseOrder instance will automatically invoke the methods below as needed.
**/
@protocol YapOrderReadTransaction
@required

/**
 * The order instance is requesting the data for the given key.
 * You should fetch and return the opaque blob.
**/
- (NSData *)dataForKey:(NSString *)key order:(YapDatabaseOrder *)sender;

@end

@protocol YapOrderReadWriteTransaction <YapOrderReadTransaction>
@required

/**
 * The order instance needs to persist data for the given key.
 * You should store the opaque blob to the database.
**/
- (void)setData:(NSData *)data forKey:(NSString *)key order:(YapDatabaseOrder *)sender;

/**
 * The order instance is deleting the data associated with the given key.
 * You should remove the associated row from the database.
**/
- (void)removeDataForKey:(NSString *)key order:(YapDatabaseOrder *)sender;

/**
 * The order instance is deleting all data.
 * You should remove all associated rows from the database.
**/
- (void)removeAllDataForOrder:(YapDatabaseOrder *)sender;

@end
