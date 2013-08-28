#import <Foundation/Foundation.h>

#import "YapAbstractDatabasePrivate.h"

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "sqlite3.h"


@interface YapDatabaseConnection () {
@private
	sqlite3_stmt *getCountStatement;
	sqlite3_stmt *getCountForKeyStatement;
	sqlite3_stmt *getCountForRowidStatement;
	sqlite3_stmt *getRowidForKeyStatement;
	sqlite3_stmt *getKeyForRowidStatement;
	sqlite3_stmt *getDataForRowidStatement;
	sqlite3_stmt *getMetadataForRowidStatement;
	sqlite3_stmt *getAllForRowidStatement;
	sqlite3_stmt *getDataForKeyStatement;
	sqlite3_stmt *getMetadataForKeyStatement;
	sqlite3_stmt *getAllForKeyStatement;
	sqlite3_stmt *insertForRowidStatement;
	sqlite3_stmt *updateAllForRowidStatement;
	sqlite3_stmt *updateMetadataForRowidStatement;
	sqlite3_stmt *removeForRowidStatement;
	sqlite3_stmt *removeAllStatement;
	sqlite3_stmt *enumerateKeysStatement;
	sqlite3_stmt *enumerateKeysAndMetadataStatement;
	sqlite3_stmt *enumerateKeysAndObjectsStatement;
	sqlite3_stmt *enumerateRowsStatement;
	
@public
	NSMutableDictionary *objectChanges;
	NSMutableDictionary *metadataChanges;
	NSMutableSet *removedKeys;
	BOOL allKeysRemoved;
	
/* Inherited from YapAbstractDatabaseConnection (see YapAbstractDatabasePrivate.h):
	
@protected
	dispatch_queue_t connectionQueue;
	void *IsOnConnectionQueueKey;
	
	YapAbstractDatabase *database;
	
@public
	sqlite3 *db;
	
	YapCache *objectCache;
	YapCache *metadataCache;
	
	NSUInteger objectCacheLimit;          // Read-only by transaction. Use as consideration of whether to add to cache.
	NSUInteger metadataCacheLimit;        // Read-only by transaction. Use as consideration of whether to add to cache.
	
	BOOL needsMarkSqlLevelSharedReadLock; // Read-only by transaction. Use as consideration of whether to invoke method.
	
*/
}

- (sqlite3_stmt *)getCountStatement;
- (sqlite3_stmt *)getCountForKeyStatement;
- (sqlite3_stmt *)getCountForRowidStatement;
- (sqlite3_stmt *)getRowidForKeyStatement;
- (sqlite3_stmt *)getKeyForRowidStatement;
- (sqlite3_stmt *)getDataForRowidStatement;
- (sqlite3_stmt *)getMetadataForRowidStatement;
- (sqlite3_stmt *)getAllForRowidStatement;
- (sqlite3_stmt *)getDataForKeyStatement;
- (sqlite3_stmt *)getMetadataForKeyStatement;
- (sqlite3_stmt *)getAllForKeyStatement;
- (sqlite3_stmt *)insertForRowidStatement;
- (sqlite3_stmt *)updateAllForRowidStatement;
- (sqlite3_stmt *)updateMetadataForRowidStatement;
- (sqlite3_stmt *)removeForRowidStatement;
- (sqlite3_stmt *)removeAllStatement;
- (sqlite3_stmt *)enumerateKeysStatement;
- (sqlite3_stmt *)enumerateKeysAndMetadataStatement;
- (sqlite3_stmt *)enumerateKeysAndObjectsStatement;
- (sqlite3_stmt *)enumerateRowsStatement;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseReadTransaction () {
@public
	__unsafe_unretained YapDatabaseConnection *connection;
}

- (BOOL)getRowid:(int64_t *)rowidPtr forKey:(NSString *)key;

- (BOOL)getKey:(NSString **)keyPtr forRowid:(int64_t)rowid;
- (BOOL)getKey:(NSString **)keyPtr object:(id *)objectPtr forRowid:(int64_t)rowid;
- (BOOL)getKey:(NSString **)keyPtr metadata:(id *)metadataPtr forRowid:(int64_t)rowid;
- (BOOL)getKey:(NSString **)keyPtr object:(id *)objectPtr metadata:(id *)metadataPtr forRowid:(int64_t)rowid;

- (BOOL)hasRowForRowid:(int64_t)rowid;

- (void)_enumerateKeysUsingBlock:(void (^)(int64_t rowid, NSString *key, BOOL *stop))block;

- (void)_enumerateKeysAndMetadataUsingBlock:(void (^)(int64_t rowid, NSString *key, id metadata, BOOL *stop))block;
- (void)_enumerateKeysAndMetadataUsingBlock:(void (^)(int64_t rowid, NSString *key, id metadata, BOOL *stop))block
                                 withFilter:(BOOL (^)(int64_t rowid, NSString *key))filter;

- (void)_enumerateKeysAndObjectsUsingBlock:(void (^)(int64_t rowid, NSString *key, id object, BOOL *stop))block;
- (void)_enumerateKeysAndObjectsUsingBlock:(void (^)(int64_t rowid, NSString *key, id object, BOOL *stop))block
                                withFilter:(BOOL (^)(int64_t rowid, NSString *key))filter;

- (void)_enumerateRowsUsingBlock:(void (^)(int64_t rowid, NSString *key, id object, id metadata, BOOL *stop))block;
- (void)_enumerateRowsUsingBlock:(void (^)(int64_t rowid, NSString *key, id object, id metadata, BOOL *stop))block
                      withFilter:(BOOL (^)(int64_t rowid, NSString *key))filter;

@end

