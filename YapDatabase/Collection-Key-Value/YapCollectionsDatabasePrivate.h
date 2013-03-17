#import <Foundation/Foundation.h>

#import "YapAbstractDatabasePrivate.h"

#import "YapCollectionsDatabase.h"
#import "YapCollectionsDatabaseConnection.h"
#import "YapCollectionsDatabaseTransaction.h"

#import "sqlite3.h"


@interface YapCollectionsDatabaseConnection () {
@private
	sqlite3_stmt *getCollectionCountStatement;
	sqlite3_stmt *getKeyCountForCollectionStatement;
	sqlite3_stmt *getKeyCountForAllStatement;
	sqlite3_stmt *getCountForKeyStatement;
	sqlite3_stmt *getDataForKeyStatement;
	sqlite3_stmt *getMetadataForKeyStatement;
	sqlite3_stmt *getAllForKeyStatement;
	sqlite3_stmt *setAllForKeyStatement;
	sqlite3_stmt *setMetaForKeyStatement;
	sqlite3_stmt *removeForKeyStatement;
	sqlite3_stmt *removeCollectionStatement;
	sqlite3_stmt *removeAllStatement;
	sqlite3_stmt *enumerateCollectionsStatement;
	sqlite3_stmt *enumerateKeysInCollectionStatement;
	sqlite3_stmt *enumerateMetadataInCollectionStatement;
	sqlite3_stmt *enumerateMetadataInAllCollectionsStatement;
	sqlite3_stmt *enumerateAllInCollectionStatement;
	sqlite3_stmt *enumerateAllInAllCollectionsStatement;
	
@public
	
	NSMutableSet *changedKeys;
	NSMutableSet *resetCollections;
	BOOL allKeysRemoved;

/* Inherited from YapAbstractDatabaseConnection (see YapAbstractDatabasePrivate.h):
	
@protected
	dispatch_queue_t connectionQueue;
	void *IsOnConnectionQueueKey;
	
	YapAbstractDatabase *database;
	
	uint64_t cacheSnapshot;
	
@public
	sqlite3 *db;
	
	YapSharedCacheConnection *objectCache;
	YapSharedCacheConnection *metadataCache;
	
	NSUInteger objectCacheLimit;          // Read-only by transaction. Use as consideration of whether to add to cache.
	NSUInteger metadataCacheLimit;        // Read-only by transaction. Use as consideration of whether to add to cache.
	
	BOOL hasMarkedSqlLevelSharedReadLock; // Read-only by transaction. Use as consideration of whether to invoke method.
	
*/
}

- (sqlite3_stmt *)getCollectionCountStatement;
- (sqlite3_stmt *)getKeyCountForCollectionStatement;
- (sqlite3_stmt *)getKeyCountForAllStatement;
- (sqlite3_stmt *)getCountForKeyStatement;
- (sqlite3_stmt *)getDataForKeyStatement;
- (sqlite3_stmt *)getMetadataForKeyStatement;
- (sqlite3_stmt *)getAllForKeyStatement;
- (sqlite3_stmt *)setAllForKeyStatement;
- (sqlite3_stmt *)setMetaForKeyStatement;
- (sqlite3_stmt *)removeForKeyStatement;
- (sqlite3_stmt *)removeCollectionStatement;
- (sqlite3_stmt *)removeAllStatement;
- (sqlite3_stmt *)enumerateCollectionsStatement;
- (sqlite3_stmt *)enumerateKeysInCollectionStatement;
- (sqlite3_stmt *)enumerateMetadataInCollectionStatement;
- (sqlite3_stmt *)enumerateMetadataInAllCollectionsStatement;
- (sqlite3_stmt *)enumerateAllInCollectionStatement;
- (sqlite3_stmt *)enumerateAllInAllCollectionsStatement;

@end
