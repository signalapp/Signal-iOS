#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseExtension.h"

#import "YapDatabaseHooksConnection.h"
#import "YapDatabaseHooksTransaction.h"

#import "YapProxyObject.h"
#import "YapWhitelistBlacklist.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, YapDatabaseHooksBitMask) {
	
	/**
	 * When a row is inserted into the databaase (new collection/key tuple),
	 * then the YapDatabaseHooksInsertedRow flag will be set.
	 * 
	 * When a row is modified in the database (existing collection/key tuple),
	 * then the YapDatabaseHooksUpdatedRow flag will be set.
	 * 
	 * When a row is explicitly touched in the database (e.g. touchObjectForKey:inCollection:)
	 * then neither YapDatabaseHooksInsertedRow nor YapDatabaseHooksUpdatedRow will be set.
	**/
	
	// An insert means that the collection/key tuple does not currently exist in the database.
	// So the object & metadata items are getting inserted / added.
	YapDatabaseHooksInsertedRow     = 1 << 0, // 0000001
	
	// An update means that the collection/key tuple currently exists in the database.
	// So the object and/or metadata items are getting changed / updated.
	YapDatabaseHooksUpdatedRow      = 1 << 1, // 0000010
	
	/**
	 * When a row is inserted, modified or touched,
	 * both the object & metadata flags will be set appropriately.
	 * 
	 * Either the object was changed (had it's value set) or was simply touched (value didn't change).
	 * So either YapDatabaseHooksChangedObject or YapDatabaseHooksTouchedObject will be set. But not both.
	 * 
	 * Either the metadata was changed (had it's value set) or was simply touched (value didn't change).
	 * So either YapDatabaseHooksChangedMetadata or YapDatabaseHooksTouchedMetadata will be set. But not both.
	**/
	
	// The object is being modified.
	// This will always be set if the InsertedRow flag is also set.
	YapDatabaseHooksChangedObject   = 1 << 2, // 0000100
	
	// The metadata is being modified.
	// This will always be set if the InsertedRow flag is also set.
	YapDatabaseHooksChangedMetadata = 1 << 3, // 0001000
	
	// The object is being explicitly touched.
	YapDatabaseHooksTouchedObject   = 1 << 4, // 0010000
	
	// The object is being explicitly touched.
	YapDatabaseHooksTouchedMetadata = 1 << 5, // 0100000
};

/**
 * WillModify & DidModify
 * 
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - setObject:forKey:inCollection:
 * - setObject:forKey:inCollection:withMetadata:
 * - setObject:forKey:inCollection:withMetadata:serializedObject:serializedMetadata:
 * - replaceObject:forKey:inCollection:
 * - replaceObject:forKey:inCollection:withSerializedObject:
 * - replaceMetadata:forKey:inCollection:
 * - replaceMetadata:forKey:inCollection:withSerializedMetadata:
 * 
 * The WillModifyRow & DidModifyRow allow you to listen for inserts & updates to rows in the database.
 * 
 * Why is a proxy used to pass the object & metadata parameters?
 * If the setObject:forKey:inCollection: family of methods is used, then the object & key are directly available,
 * and the proxy acts as simply a wrapper for the object or key.
 * That is, proxy.isRealObjectLoaded will be YES.
 * However, if the replaceObject:forKey:inCollection: family of methods are used,
 * then the object is immediately available, but the metadata isn't.
 * Thus the proxy is used to lazily load the metadata, if needed.
 * This allows a common API to support all scenarios.
**/

typedef void (^YDBHooks_WillModifyRow)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key,
   YapProxyObject *proxyObject, YapProxyObject *proxyMetadata, YapDatabaseHooksBitMask flags);

typedef void (^YDBHooks_DidModifyRow)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key,
   YapProxyObject *proxyObject, YapProxyObject *proxyMetadata, YapDatabaseHooksBitMask flags);

/**
 * WillRemoveRow & DidRemoveRow
 * 
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeObjectForKey:inCollection:
 * - removeObjectsForKeys:inCollection:
 * - removeAllObjectsInCollection:
 * 
 * Note: This method is NOT invoked if the entire database is cleared.
 * That is, if removeAllObjectsInAllCollections is invoked.
**/

typedef void (^YDBHooks_WillRemoveRow)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key);

typedef void (^YDBHooks_DidRemoveRow)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key);

/**
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeAllObjectsInAllCollections
**/

typedef void (^YDBHooks_WillRemoveAllRows)
  (YapDatabaseReadWriteTransaction *transaction);

typedef void (^YDBHooks_DidRemoveAllRows)
  (YapDatabaseReadWriteTransaction *transaction);




@interface YapDatabaseHooks : YapDatabaseExtension

- (instancetype)init;

@property (atomic, strong, readwrite, nullable) YapWhitelistBlacklist *allowedCollections;

@property (atomic, strong, readwrite, nullable) YDBHooks_WillModifyRow willModifyRow;
@property (atomic, strong, readwrite, nullable) YDBHooks_DidModifyRow   didModifyRow;

@property (atomic, strong, readwrite, nullable) YDBHooks_WillRemoveRow willRemoveRow;
@property (atomic, strong, readwrite, nullable) YDBHooks_DidRemoveRow   didRemoveRow;

@property (atomic, strong, readwrite, nullable) YDBHooks_WillRemoveAllRows willRemoveAllRows;
@property (atomic, strong, readwrite, nullable) YDBHooks_DidRemoveAllRows didRemoveAllRows;

@end

NS_ASSUME_NONNULL_END
