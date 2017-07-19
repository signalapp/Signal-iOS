#import "YapDatabaseTransaction.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"
#import "YapCache.h"
#import "YapCollectionKey.h"
#import "YapTouch.h"
#import "YapNull.h"

#import <objc/runtime.h>

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)


@implementation YapDatabaseReadTransaction

+ (void)load
{
	static BOOL loaded = NO;
	if (!loaded)
	{
		// Method swizzle:
		// Both extension: and ext: are designed to be the same method (with ext: shorthand for extension:).
		// So swap out the ext: method to point to extension:.
		
		Method extMethod = class_getInstanceMethod([self class], @selector(ext:));
		IMP extensionIMP = class_getMethodImplementation([self class], @selector(extension:));
		
		method_setImplementation(extMethod, extensionIMP);
		loaded = YES;
	}
}

- (id)initWithConnection:(YapDatabaseConnection *)aConnection isReadWriteTransaction:(BOOL)flag
{
	if ((self = [super init]))
	{
		connection = aConnection;
		isReadWriteTransaction = flag;
	}
	return self;
}

@synthesize connection = connection;
@synthesize userInfo = _external_userInfo;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction States
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)beginTransaction
{
	sqlite3_stmt *statement = [connection beginTransactionStatement];
	if (statement == NULL) return;
	
	// BEGIN TRANSACTION;
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Couldn't begin transaction: %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
}

- (void)beginImmediateTransaction
{
    sqlite3_stmt *statement = [connection beginImmediateTransactionStatement];
    if (statement == NULL) return;
    
    // BEGIN IMMEDIATE TRANSACTION;
    
    int status = sqlite3_step(statement);
    if (status != SQLITE_DONE)
    {
        YDBLogError(@"Couldn't begin immediate transaction: %d %s", status, sqlite3_errmsg(connection->db));
    }
    
    sqlite3_reset(statement);
}

- (void)preCommitReadWriteTransaction
{
	// Step 1:
	//
	// Allow extensions to flush changes to the main database table.
	// This is different from flushing changes to their own private tables.
	// We're referring here to the main collection/key/value table (database2) that's public.
	
	__block BOOL restart;
	__block BOOL prevExtModifiesMainDatabaseTable;
	do
	{
		YapMutationStackItem_Bool *mutation = [connection->mutationStack push];
		
		restart = NO;
		prevExtModifiesMainDatabaseTable = NO;
		
		[extensions enumerateKeysAndObjectsUsingBlock:^(id __unused extNameObj, id extTransactionObj, BOOL *stop) {
			
			BOOL extModifiesMainDatabaseTable =
			  [(YapDatabaseExtensionTransaction *)extTransactionObj flushPendingChangesToMainDatabaseTable];
			
			if (extModifiesMainDatabaseTable)
			{
				if (!mutation.isMutated)
				{
					prevExtModifiesMainDatabaseTable = YES;
				}
				else
				{
					if (prevExtModifiesMainDatabaseTable)
					{
						restart = YES;
						*stop = YES;
					}
					else
					{
						prevExtModifiesMainDatabaseTable = YES;
					}
				}
			}
		}];
	
	} while (restart);
	
	// Step 2:
	//
	// Allow extensions to flush changes to their own tables,
	// and perform any needed "cleanup" code needed before the changeset is requested.
	
	[extensions enumerateKeysAndObjectsUsingBlock:^(id __unused extNameObj, id extTransactionObj, BOOL __unused *stop) {
		
		[(YapDatabaseExtensionTransaction *)extTransactionObj flushPendingChangesToExtensionTables];
	}];
	
	[yapMemoryTableTransaction commit];
}

- (void)commitTransaction
{
	sqlite3_stmt *statement = [connection commitTransactionStatement];
	if (statement)
	{
		// COMMIT TRANSACTION;
		
		int status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"Couldn't commit transaction: %d %s", status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_reset(statement);
	}
	
	if (isReadWriteTransaction)
	{
		[extensions enumerateKeysAndObjectsUsingBlock:^(id __unused extNameObj, id extTransactionObj, BOOL __unused *stop) {
			
			[(YapDatabaseExtensionTransaction *)extTransactionObj didCommitTransaction];
		}];
	}
}

- (void)rollbackTransaction
{
	sqlite3_stmt *statement = [connection rollbackTransactionStatement];
	if (statement)
	{
		// ROLLBACK TRANSACTION;
		
		int status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"Couldn't rollback transaction: %d %s", status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_reset(statement);
	}
	
	[extensions enumerateKeysAndObjectsUsingBlock:^(id __unused extNameObj, id extTransactionObj, BOOL __unused *stop) {
		
		[(YapDatabaseExtensionTransaction *)extTransactionObj didRollbackTransaction];
	}];
	
	[yapMemoryTableTransaction rollback];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Count
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)numberOfCollections
{
	sqlite3_stmt *statement = [connection getCollectionCountStatement];
	if (statement == NULL) return 0;
	
	// SELECT COUNT(DISTINCT collection) AS NumberOfRows FROM "database2";
	
	NSUInteger result = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = (NSUInteger)sqlite3_column_int64(statement, SQLITE_COLUMN_START);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getCollectionCountStatement': %d %s",
		            status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
	
	return result;
}

- (NSUInteger)numberOfKeysInCollection:(NSString *)collection
{
	if (collection == nil) collection = @"";
	
	sqlite3_stmt *statement = [connection getKeyCountForCollectionStatement];
	if (statement == NULL) return 0;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "database2" WHERE "collection" = ?;
	
	int const column_idx_result   = SQLITE_COLUMN_START;
	int const bind_idx_collection = SQLITE_BIND_START;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
	
	NSUInteger result = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = (NSUInteger)sqlite3_column_int64(statement, column_idx_result);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getKeyCountForCollectionStatement': %d %s",
		            status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	
	return result;
}

- (NSUInteger)numberOfKeysInAllCollections
{
	sqlite3_stmt *statement = [connection getKeyCountForAllStatement];
	if (statement == NULL) return 0;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "database2";
	
	NSUInteger result = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = (NSUInteger)sqlite3_column_int64(statement, SQLITE_COLUMN_START);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getKeyCountForAllStatement': %d %s",
		            status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark List
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSArray *)allCollections
{
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateCollectionsStatement:&needsFinalize];
	if (statement == NULL) return nil;
	
	// SELECT DISTINCT "collection" FROM "database2";";
	
	NSMutableArray *result = [NSMutableArray array];
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(statement, SQLITE_COLUMN_START);
		int textSize = sqlite3_column_bytes(statement, SQLITE_COLUMN_START);
		
		NSString *collection = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		[result addObject:collection];
	}
	
	if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'enumerateCollectionsStatement': %d %s",
		            status, sqlite3_errmsg(connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
	
	return result;
}

- (NSArray *)allKeysInCollection:(NSString *)collection
{
	NSUInteger count = [self numberOfKeysInCollection:collection];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
	
	[self _enumerateKeysInCollection:collection usingBlock:^(int64_t __unused rowid, NSString *key, BOOL __unused *stop) {
		
		[result addObject:key];
	}];
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal (using rowid)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)getRowid:(int64_t *)rowidPtr forCollectionKey:(YapCollectionKey *)cacheKey
{
	if (cacheKey == nil) {
		if (rowidPtr) *rowidPtr = 0;
		return NO;
	}
	
	NSNumber *cachedRowid = [connection->keyCache keyForObject:cacheKey];
	if (cachedRowid)
	{
		if (rowidPtr) *rowidPtr = [cachedRowid longLongValue];
		return YES;
	}
	
	sqlite3_stmt *statement = [connection getRowidForKeyStatement];
	if (statement == NULL) {
		if (rowidPtr) *rowidPtr = 0;
		return NO;
	}
	
	// SELECT "rowid" FROM "database2" WHERE "collection" = ? AND "key" = ?;
	
	int const column_idx_result   = SQLITE_COLUMN_START;
	int const bind_idx_collection = SQLITE_BIND_START + 0;
	int const bind_idx_key        = SQLITE_BIND_START + 1;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, cacheKey.collection);
	sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, cacheKey.key);
	sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length,  SQLITE_STATIC);
	
	int64_t rowid = 0;
	BOOL result = NO;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		rowid = sqlite3_column_int64(statement, column_idx_result);
		result = YES;
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getRowidForKeyStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);
	
	if (result) {
		[connection->keyCache setObject:cacheKey forKey:@(rowid)];
	}
	
	if (rowidPtr) *rowidPtr = rowid;
	return result;
}

- (BOOL)getRowid:(int64_t *)rowidPtr forKey:(NSString *)key inCollection:(NSString *)collection
{
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	return [self getRowid:rowidPtr forCollectionKey:cacheKey];
}

- (YapCollectionKey *)collectionKeyForRowid:(int64_t)rowid
{
	NSNumber *rowidNumber = @(rowid);
	
	YapCollectionKey *collectionKey = [connection->keyCache objectForKey:rowidNumber];
	if (collectionKey)
	{
		return collectionKey;
	}
	
	sqlite3_stmt *statement = [connection getKeyForRowidStatement];
	if (statement == NULL) {
		return nil;
	}
	
	// SELECT "collection", "key" FROM "database2" WHERE "rowid" = ?;
	
	int const column_idx_collection = SQLITE_COLUMN_START + 0;
	int const column_idx_key        = SQLITE_COLUMN_START + 1;
	int const bind_idx_rowid        = SQLITE_BIND_START;
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const unsigned char *text0 = sqlite3_column_text(statement, column_idx_collection);
		int textSize0 = sqlite3_column_bytes(statement, column_idx_collection);
		
		const unsigned char *text1 = sqlite3_column_text(statement, column_idx_key);
		int textSize1 = sqlite3_column_bytes(statement, column_idx_key);
		
		NSString *collection = [[NSString alloc] initWithBytes:text0 length:textSize0 encoding:NSUTF8StringEncoding];
		NSString *key        = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
		
		collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		[connection->keyCache setObject:collectionKey forKey:rowidNumber];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getKeyForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	return collectionKey;
}

- (BOOL)getCollectionKey:(YapCollectionKey **)collectionKeyPtr object:(id *)objectPtr forRowid:(int64_t)rowid
{
	YapCollectionKey *collectionKey = [self collectionKeyForRowid:rowid];
	if (collectionKey)
	{
		id object = [self objectForCollectionKey:collectionKey withRowid:rowid];
	
		if (collectionKeyPtr) *collectionKeyPtr = collectionKey;
		if (objectPtr) *objectPtr = object;
		return YES;
	}
	else
	{
		if (collectionKeyPtr) *collectionKeyPtr = nil;
		if (objectPtr) *objectPtr = nil;
		return NO;
	}
}

- (BOOL)getCollectionKey:(YapCollectionKey **)collectionKeyPtr metadata:(id *)metadataPtr forRowid:(int64_t)rowid
{
	YapCollectionKey *collectionKey = [self collectionKeyForRowid:rowid];
	if (collectionKey)
	{
		id metadata = [self metadataForCollectionKey:collectionKey withRowid:rowid];
		
		if (collectionKeyPtr) *collectionKeyPtr = collectionKey;
		if (metadataPtr) *metadataPtr = metadata;
		return YES;
	}
	else
	{
		if (collectionKeyPtr) *collectionKeyPtr = nil;
		if (metadataPtr) *metadataPtr = nil;
		return NO;
	}
}

- (BOOL)getCollectionKey:(YapCollectionKey **)collectionKeyPtr
                  object:(id *)objectPtr
                metadata:(id *)metadataPtr
                forRowid:(int64_t)rowid
{
	YapCollectionKey *collectionKey = [self collectionKeyForRowid:rowid];
	if (collectionKey == nil)
	{
		if (collectionKeyPtr) *collectionKeyPtr = nil;
		if (objectPtr) *objectPtr = nil;
		if (metadataPtr) *metadataPtr = nil;
		return NO;
	}
	
	if ([self getObject:objectPtr metadata:metadataPtr forCollectionKey:collectionKey withRowid:rowid])
	{
		if (collectionKeyPtr) *collectionKeyPtr = collectionKey;
		return YES;
	}
	else
	{
		if (collectionKeyPtr) *collectionKeyPtr = nil;
		return NO;
	}
}

- (BOOL)hasRowid:(int64_t)rowid
{
	if ([connection->keyCache containsKey:@(rowid)])
		return YES;
	
	sqlite3_stmt *statement = [connection getCountForRowidStatement];
	if (statement == NULL) return NO;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "database2" WHERE "rowid" = ?;
	
	int const column_idx_result = SQLITE_COLUMN_START;
	int const bind_idx_rowid    = SQLITE_BIND_START;
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	BOOL result = NO;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = (sqlite3_column_int64(statement, column_idx_result) > 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getCountForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	return result;
}

- (id)objectForKey:(NSString *)key inCollection:(NSString *)collection withRowid:(int64_t)rowid
{
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	return [self objectForCollectionKey:cacheKey withRowid:rowid];
}

- (id)objectForCollectionKey:(YapCollectionKey *)cacheKey withRowid:(int64_t)rowid
{
	if (cacheKey == nil) return nil;
	
	id object = [connection->objectCache objectForKey:cacheKey];
	if (object)
		return object;
	
	sqlite3_stmt *statement = [connection getDataForRowidStatement];
	if (statement == NULL) return nil;
	
	// SELECT "data" FROM "database2" WHERE "rowid" = ?;
	
	int const column_idx_data = SQLITE_COLUMN_START;
	int const bind_idx_rowid  = SQLITE_BIND_START;
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const void *blob = sqlite3_column_blob(statement, column_idx_data);
		int blobSize = sqlite3_column_bytes(statement, column_idx_data);
		
		// Performance tuning:
		// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
		
		NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
		object = connection->database->objectDeserializer(cacheKey.collection, cacheKey.key, data);
		
		if (object)
			[connection->objectCache setObject:object forKey:cacheKey];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getDataForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	return object;
}

- (id)metadataForKey:(NSString *)key inCollection:(NSString *)collection withRowid:(int64_t)rowid
{
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	return [self metadataForCollectionKey:cacheKey withRowid:rowid];
}

- (id)metadataForCollectionKey:(YapCollectionKey *)cacheKey withRowid:(int64_t)rowid
{
	if (cacheKey == nil) return nil;
	
	id metadata = [connection->metadataCache objectForKey:cacheKey];
	if (metadata)
	{
		if (metadata == [YapNull null])
			return nil;
		else
			return metadata;
	}
	
	sqlite3_stmt *statement = [connection getMetadataForRowidStatement];
	if (statement == NULL) return nil;
	
	// SELECT "metadata" FROM "database2" WHERE "rowid" = ?;
	
	int const column_idx_metadata = SQLITE_COLUMN_START;
	int const bind_idx_rowid      = SQLITE_BIND_START;
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const void *blob = sqlite3_column_blob(statement, column_idx_metadata);
		int blobSize = sqlite3_column_bytes(statement, column_idx_metadata);
		
		if (blobSize > 0)
		{
			// Performance tuning:
			// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
			
			NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			metadata = connection->database->metadataDeserializer(cacheKey.collection, cacheKey.key, data);
		}
		
		if (metadata)
			[connection->metadataCache setObject:metadata forKey:cacheKey];
		else
			[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getMetadataForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	return metadata;
}

- (BOOL)getObject:(id *)objectPtr
         metadata:(id *)metadataPtr
           forKey:(NSString *)key
     inCollection:(NSString *)collection
        withRowid:(int64_t)rowid
{
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	return [self getObject:objectPtr metadata:metadataPtr forCollectionKey:cacheKey withRowid:rowid];
}

- (BOOL)getObject:(id *)objectPtr
         metadata:(id *)metadataPtr
 forCollectionKey:(YapCollectionKey *)cacheKey
        withRowid:(int64_t)rowid
{
	BOOL found = NO;
	
	id object = [connection->objectCache objectForKey:cacheKey];
	id metadata = [connection->metadataCache objectForKey:cacheKey];
	
	if (object || metadata)
	{
		if (objectPtr && !object)
		{
			object = [self objectForCollectionKey:cacheKey withRowid:rowid];
		}
		
		if (metadataPtr && !metadata)
		{
			metadata = [self metadataForCollectionKey:cacheKey withRowid:rowid];
		}
		
		if (metadata == [YapNull null])
			metadata = nil;
		
		found = YES;
	}
	else
	{
		sqlite3_stmt *statement = [connection getAllForRowidStatement];
		if (statement == NULL) {
			if (objectPtr) *objectPtr = nil;
			if (metadataPtr) *metadataPtr = nil;
			return NO;
		}
		
		// SELECT "data", "metadata" FROM "database2" WHERE "rowid" = ?;
		
		int const column_idx_data     = SQLITE_COLUMN_START + 0;
		int const column_idx_metadata = SQLITE_COLUMN_START + 1;
		int const bind_idx_rowid      = SQLITE_BIND_START;
		
		sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			if (objectPtr)
			{
				const void *oBlob = sqlite3_column_blob(statement, column_idx_data);
				int oBlobSize = sqlite3_column_bytes(statement, column_idx_data);
				
				// Performance tuning:
				// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
				
				NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
				object = connection->database->objectDeserializer(cacheKey.collection, cacheKey.key, oData);
				
				if (object)
					[connection->objectCache setObject:object forKey:cacheKey];
			}
			
			if (metadataPtr)
			{
				const void *mBlob = sqlite3_column_blob(statement, column_idx_metadata);
				int mBlobSize = sqlite3_column_bytes(statement, column_idx_metadata);
				
				if (mBlobSize > 0)
				{
					// Performance tuning:
					// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
					
					NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
					metadata = connection->database->metadataDeserializer(cacheKey.collection, cacheKey.key, mData);
				}
				
				if (metadata)
					[connection->metadataCache setObject:metadata forKey:cacheKey];
				else
					[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
			}
			
			found = YES;
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'getAllForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	
	if (objectPtr) *objectPtr = object;
	if (metadataPtr) *metadataPtr = metadata;
		
	return found;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Object & Metadata
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)hasObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return NO;
	if (collection == nil) collection = @"";
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	// Shortcut:
	// We may not need to query the database if we have the key in any of our caches.
	
	if ([connection->objectCache containsKey:cacheKey]) return YES;
	if ([connection->metadataCache containsKey:cacheKey]) return YES;
	
	// The normal way (checks keyCache first, and then falls back to SQL query)
	
	return [self getRowid:NULL forCollectionKey:cacheKey];
}

- (id)objectForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return nil;
	if (collection == nil) collection = @"";
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	id object = [connection->objectCache objectForKey:cacheKey];
	if (object)
		return object;
	
	NSNumber *cachedRowid = [connection->keyCache keyForObject:cacheKey];
	if (cachedRowid)
	{
		int64_t rowid = [cachedRowid longLongValue];
		
		sqlite3_stmt *statement = [connection getDataForRowidStatement];
		if (statement == NULL) return nil;
		
		// SELECT "data" FROM "database2" WHERE "rowid" = ?;
		
		int const column_idx_data = SQLITE_COLUMN_START;
		int const bind_idx_rowid  = SQLITE_BIND_START;
		
		sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			const void *blob = sqlite3_column_blob(statement, column_idx_data);
			int blobSize = sqlite3_column_bytes(statement, column_idx_data);
			
			// Performance tuning:
			// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
			
			NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			object = connection->database->objectDeserializer(cacheKey.collection, cacheKey.key, data);
			
			if (object)
				[connection->objectCache setObject:object forKey:cacheKey];
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'getDataForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	else
	{
		sqlite3_stmt *statement = [connection getDataForKeyStatement];
		if (statement == NULL) return nil;
		
		// SELECT "rowid", "data" FROM "database2" WHERE "collection" = ? AND "key" = ?;
		
		int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
		int const column_idx_data     = SQLITE_COLUMN_START + 1;
		int const bind_idx_collection = SQLITE_BIND_START + 0;
		int const bind_idx_key        = SQLITE_BIND_START + 1;
		
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
		
		YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
		sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			const void *blob = sqlite3_column_blob(statement, column_idx_data);
			int blobSize = sqlite3_column_bytes(statement, column_idx_data);
			
			// Performance tuning:
			// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
			
			NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			object = connection->database->objectDeserializer(collection, key, data);
			
			// Update caches
			
			[connection->keyCache setObject:cacheKey forKey:@(rowid)];
			
			if (object) {
				[connection->objectCache setObject:object forKey:cacheKey];
			}
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'getDataForKeyStatement': %d %s, key(%@)",
			                                                    status, sqlite3_errmsg(connection->db), key);
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_collection);
		FreeYapDatabaseString(&_key);
	}
	
	return object;
}

- (id)metadataForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return nil;
	if (collection == nil) collection = @"";
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	id metadata = [connection->metadataCache objectForKey:cacheKey];
	if (metadata)
	{
		if (metadata == [YapNull null])
			return nil;
		else
			return metadata;
	}
	
	NSNumber *cachedRowid = [connection->keyCache keyForObject:cacheKey];
	if (cachedRowid)
	{
		int64_t rowid = [cachedRowid longLongValue];
		
		sqlite3_stmt *statement = [connection getMetadataForRowidStatement];
		if (statement == NULL) return nil;
		
		// SELECT "metadata" FROM "database2" WHERE "rowid" = ?;
		
		int const column_idx_metadata = SQLITE_COLUMN_START;
		int const bind_idx_rowid      = SQLITE_BIND_START;
		
		sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			const void *blob = sqlite3_column_blob(statement, column_idx_metadata);
			int blobSize = sqlite3_column_bytes(statement, column_idx_metadata);
			
			if (blobSize > 0)
			{
				// Performance tuning:
				// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
				
				NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
				metadata = connection->database->metadataDeserializer(cacheKey.collection, cacheKey.key, data);
			}
			
			// Update cache
			
			if (metadata)
				[connection->metadataCache setObject:metadata forKey:cacheKey];
			else
				[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'getMetadataForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	else
	{
		sqlite3_stmt *statement = [connection getMetadataForKeyStatement];
		if (statement == NULL) return nil;
		
		// SELECT "rowid", "metadata" FROM "database2" WHERE "collection" = ? AND "key" = ? ;
		
		int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
		int const column_idx_metadata = SQLITE_COLUMN_START + 1;
		int const bind_idx_collection = SQLITE_BIND_START + 0;
		int const bind_idx_key        = SQLITE_BIND_START + 1;
		
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
		
		YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
		sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			const void *blob = sqlite3_column_blob(statement, column_idx_metadata);
			int blobSize = sqlite3_column_bytes(statement, column_idx_metadata);
			
			if (blobSize > 0)
			{
				// Performance tuning:
				// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
				
				NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
				metadata = connection->database->metadataDeserializer(collection, key, data);
			}
			
			// Update caches
			
			[connection->keyCache setObject:cacheKey forKey:@(rowid)];
			
			if (metadata)
				[connection->metadataCache setObject:metadata forKey:cacheKey];
			else
				[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'getMetadataForKeyStatement': %d %s",
			                                                        status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_collection);
		FreeYapDatabaseString(&_key);
	}
	
	return metadata;
}

- (BOOL)getObject:(id *)objectPtr metadata:(id *)metadataPtr forKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil)
	{
		if (objectPtr) *objectPtr = nil;
		if (metadataPtr) *metadataPtr = nil;
		
		return NO;
	}
	if (collection == nil) collection = @"";
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	id object = [connection->objectCache objectForKey:cacheKey];
	id metadata = [connection->metadataCache objectForKey:cacheKey];
	
	BOOL found = NO;
	
	if (object || metadata)
	{
		if (objectPtr && !object)
		{
			object = [self objectForKey:key inCollection:collection];
		}
		
		if (metadataPtr && !metadata)
		{
			metadata = [self metadataForKey:key inCollection:collection];
		}
		
		if (metadata == [YapNull null])
			metadata = nil;
		
		found = YES;
	}
	else // (!object && !metadata)
	{
		// Both object and metadata are missing.
		// Fetch via query.
		
		NSNumber *cachedRowid = [connection->keyCache keyForObject:cacheKey];
		if (cachedRowid)
		{
			int64_t rowid = [cachedRowid longLongValue];
			
			sqlite3_stmt *statement = [connection getAllForRowidStatement];
			if (statement == NULL) {
				if (objectPtr) *objectPtr = nil;
				if (metadataPtr) *metadataPtr = nil;
				return NO;
			}
			
			// SELECT "data", "metadata" FROM "database2" WHERE "rowid" = ?;
			
			int const column_idx_data     = SQLITE_COLUMN_START + 0;
			int const column_idx_metadata = SQLITE_COLUMN_START + 1;
			int const bind_idx_rowid      = SQLITE_BIND_START;
			
			sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
			
			int status = sqlite3_step(statement);
			if (status == SQLITE_ROW)
			{
				if (objectPtr)
				{
					const void *oBlob = sqlite3_column_blob(statement, column_idx_data);
					int oBlobSize = sqlite3_column_bytes(statement, column_idx_data);
					
					// Performance tuning:
					// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
					
					NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
					object = connection->database->objectDeserializer(cacheKey.collection, cacheKey.key, oData);
					
					if (object)
						[connection->objectCache setObject:object forKey:cacheKey];
				}
				
				if (metadataPtr)
				{
					const void *mBlob = sqlite3_column_blob(statement, column_idx_metadata);
					int mBlobSize = sqlite3_column_bytes(statement, column_idx_metadata);
					
					if (mBlobSize > 0)
					{
						// Performance tuning:
						// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
						
						NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
						metadata = connection->database->metadataDeserializer(cacheKey.collection, cacheKey.key, mData);
					}
					
					if (metadata)
						[connection->metadataCache setObject:metadata forKey:cacheKey];
					else
						[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
				}
				
				found = YES;
			}
			else if (status == SQLITE_ERROR)
			{
				YDBLogError(@"Error executing 'getAllForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
		}
		else
		{
			sqlite3_stmt *statement = [connection getAllForKeyStatement];
			if (statement == NULL) {
				if (objectPtr) *objectPtr = object;
				if (metadataPtr) *metadataPtr = metadata;
				return NO;
			}
			
			// SELECT "rowid", "data", "metadata" FROM "database2" WHERE "collection" = ? AND "key" = ? ;
			
			int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
			int const column_idx_data     = SQLITE_COLUMN_START + 1;
			int const column_idx_metadata = SQLITE_COLUMN_START + 2;
			int const bind_idx_collection = SQLITE_BIND_START + 0;
			int const bind_idx_key        = SQLITE_BIND_START + 1;
			
			YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
			sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
			
			YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
			sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
			
			int status = sqlite3_step(statement);
			if (status == SQLITE_ROW)
			{
				int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
				
				[connection->keyCache setObject:cacheKey forKey:@(rowid)];
				
				if (objectPtr)
				{
					const void *oBlob = sqlite3_column_blob(statement, column_idx_data);
					int oBlobSize = sqlite3_column_bytes(statement, column_idx_data);
				
					NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
					object = connection->database->objectDeserializer(collection, key, oData);
					
					if (object)
						[connection->objectCache setObject:object forKey:cacheKey];
				}
				
				if (metadataPtr)
				{
					const void *mBlob = sqlite3_column_blob(statement, column_idx_metadata);
					int mBlobSize = sqlite3_column_bytes(statement, column_idx_metadata);
				
					if (mBlobSize > 0)
					{
						NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
						metadata = connection->database->metadataDeserializer(collection, key, mData);
					}
					
					if (metadata)
						[connection->metadataCache setObject:metadata forKey:cacheKey];
					else
						[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
				}
				
				found = YES;
			}
			else if (status == SQLITE_ERROR)
			{
				YDBLogError(@"Error executing 'getAllForKeyStatement': %d %s",
				                                                   status, sqlite3_errmsg(connection->db));
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
			FreeYapDatabaseString(&_collection);
			FreeYapDatabaseString(&_key);
		}
	}
	
	if (objectPtr) *objectPtr = object;
	if (metadataPtr) *metadataPtr = metadata;
	
	return found;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Primitive
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Primitive access.
 * This method is available in-case you have a need to fetch the raw serializedObject from the database.
 *
 * This method is slower than objectForKey:inCollection:, since that method makes use of the objectCache.
 * In contrast, this method always fetches the raw data from disk.
 *
 * @see objectForKey:inCollection:
**/
- (NSData *)serializedObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return nil;
	if (collection == nil) collection = @"";
	
	NSData *result = nil;
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	NSNumber *cachedRowid = [connection->keyCache keyForObject:cacheKey];
	if (cachedRowid)
	{
		int64_t rowid = [cachedRowid longLongValue];
		
		sqlite3_stmt *statement = [connection getDataForRowidStatement];
		if (statement == NULL) return nil;
		
		// SELECT "data" FROM "database2" WHERE "rowid" = ?;
		
		int const column_idx_data = SQLITE_COLUMN_START;
		int const bind_idx_rowid  = SQLITE_BIND_START;
		
		sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			const void *blob = sqlite3_column_blob(statement, column_idx_data);
			int blobSize = sqlite3_column_bytes(statement, column_idx_data);
			
			result = [[NSData alloc] initWithBytes:blob length:blobSize];
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'getDataForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	else
	{
		sqlite3_stmt *statement = [connection getDataForKeyStatement];
		if (statement == NULL) return nil;
		
		// SELECT "rowid", "data" FROM "database2" WHERE "collection" = ? AND "key" = ?;
		
		int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
		int const column_idx_data     = SQLITE_COLUMN_START + 1;
		int const bind_idx_collection = SQLITE_BIND_START + 0;
		int const bind_idx_key        = SQLITE_BIND_START + 1;
		
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
		
		YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
		sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length,  SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			const void *blob = sqlite3_column_blob(statement, column_idx_data);
			int blobSize = sqlite3_column_bytes(statement, column_idx_data);
			
			result = [[NSData alloc] initWithBytes:blob length:blobSize];
			
			// Update cache
			
			[connection->keyCache setObject:cacheKey forKey:@(rowid)];
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'getDataForKeyStatement': %d %s, key(%@)",
			                                                    status, sqlite3_errmsg(connection->db), key);
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_collection);
		FreeYapDatabaseString(&_key);
	}
	
	return result;
}

/**
 * Primitive access.
 * This method is available in-case you have a need to fetch the raw serializedMetadata from the database.
 *
 * This method is slower than metadataForKey:inCollection:, since that method makes use of the metadataCache.
 * In contrast, this method always fetches the raw data from disk.
 *
 * @see metadataForKey:inCollection:
**/
- (NSData *)serializedMetadataForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return nil;
	if (collection == nil) collection = @"";
	
	NSData *result = nil;
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	NSNumber *cachedRowid = [connection->keyCache keyForObject:cacheKey];
	if (cachedRowid)
	{
		int64_t rowid = [cachedRowid longLongValue];
		
		sqlite3_stmt *statement = [connection getMetadataForRowidStatement];
		if (statement == NULL) return nil;
		
		// SELECT "metadata" FROM "database2" WHERE "rowid" = ?;
		
		int const column_idx_metadata = SQLITE_COLUMN_START;
		int const bind_idx_rowid      = SQLITE_BIND_START;
		
		sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			const void *blob = sqlite3_column_blob(statement, column_idx_metadata);
			int blobSize = sqlite3_column_bytes(statement, column_idx_metadata);
			
			result = [[NSData alloc] initWithBytes:blob length:blobSize];
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'getMetadataForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	else
	{
		sqlite3_stmt *statement = [connection getMetadataForKeyStatement];
		if (statement == NULL) return nil;
		
		// SELECT "rowid", "metadata" FROM "database2" WHERE "collection" = ? AND "key" = ? ;
		
		int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
		int const column_idx_metadata = SQLITE_COLUMN_START + 1;
		int const bind_idx_collection = SQLITE_BIND_START + 0;
		int const bind_idx_key        = SQLITE_BIND_START + 1;
		
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
		
		YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
		sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			const void *blob = sqlite3_column_blob(statement, column_idx_metadata);
			int blobSize = sqlite3_column_bytes(statement, column_idx_metadata);
			
			result = [[NSData alloc] initWithBytes:blob length:blobSize];
			
			// Update cache
			
			[connection->keyCache setObject:cacheKey forKey:@(rowid)];
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'getMetadataForKeyStatement': %d %s, key(%@)",
						status, sqlite3_errmsg(connection->db), key);
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_collection);
		FreeYapDatabaseString(&_key);
	}
	
	return result;
}

/**
 * Primitive access.
 * This method is available in-case you have a need to fetch the raw serialized forms from the database.
 *
 * This method is slower than getObject:metadata:forKey:inCollection:, since that method makes use of the caches.
 * In contrast, this method always fetches the raw data from disk.
 *
 * @see getObject:metadata:forKey:inCollection:
**/
- (BOOL)getSerializedObject:(NSData **)serializedObjectPtr
         serializedMetadata:(NSData **)serializedMetadataPtr
                     forKey:(NSString *)key
               inCollection:(NSString *)collection
{
	if (key == nil) {
		if (serializedObjectPtr) *serializedObjectPtr = nil;
		if (serializedMetadataPtr) *serializedMetadataPtr = nil;
		return NO;
	}
	if (collection == nil) collection = @"";
	
	NSData *serializedObject = nil;
	NSData *serializedMetadata = nil;
	
	BOOL found = NO;
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	NSNumber *cachedRowid = [connection->keyCache keyForObject:cacheKey];
	if (cachedRowid)
	{
		int64_t rowid = [cachedRowid longLongValue];
		
		sqlite3_stmt *statement = [connection getAllForRowidStatement];
		if (statement == NULL) {
			if (serializedObjectPtr) *serializedObjectPtr = nil;
			if (serializedMetadataPtr) *serializedMetadataPtr = nil;
			return NO;
		}
		
		// SELECT "data", "metadata" FROM "database2" WHERE "rowid" = ?;
		
		int const column_idx_data     = SQLITE_COLUMN_START + 0;
		int const column_idx_metadata = SQLITE_COLUMN_START + 1;
		int const bind_idx_rowid      = SQLITE_BIND_START;
		
		sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			if (serializedObjectPtr)
			{
				const void *oBlob = sqlite3_column_blob(statement, column_idx_data);
				int oBlobSize = sqlite3_column_bytes(statement, column_idx_data);
				
				serializedObject = [NSData dataWithBytes:(void *)oBlob length:oBlobSize];
			}
			
			if (serializedMetadataPtr)
			{
				const void *mBlob = sqlite3_column_blob(statement, column_idx_metadata);
				int mBlobSize = sqlite3_column_bytes(statement, column_idx_metadata);
				
				serializedMetadata = [NSData dataWithBytes:(void *)mBlob length:mBlobSize];
			}
			
			found = YES;
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'getAllForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	else
	{
		sqlite3_stmt *statement = [connection getAllForKeyStatement];
		if (statement == NULL) {
			if (serializedObjectPtr) *serializedObjectPtr = nil;
			if (serializedMetadataPtr) *serializedMetadataPtr = nil;
			return NO;
		}
		
		// SELECT "rowid", "data", "metadata" FROM "database2" WHERE "collection" = ? AND "key" = ? ;
		
		int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
		int const column_idx_data     = SQLITE_COLUMN_START + 1;
		int const column_idx_metadata = SQLITE_COLUMN_START + 2;
		int const bind_idx_collection = SQLITE_BIND_START + 0;
		int const bind_idx_key        = SQLITE_BIND_START + 1;
		
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
		
		YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
		sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			if (serializedObjectPtr)
			{
				const void *oBlob = sqlite3_column_blob(statement, column_idx_data);
				int oBlobSize = sqlite3_column_bytes(statement, column_idx_data);
				
				serializedObject = [NSData dataWithBytes:(void *)oBlob length:oBlobSize];
			}
			
			if (serializedMetadataPtr)
			{
				const void *mBlob = sqlite3_column_blob(statement, column_idx_metadata);
				int mBlobSize = sqlite3_column_bytes(statement, column_idx_metadata);
				
				serializedMetadata = [NSData dataWithBytes:(void *)mBlob length:mBlobSize];
			}
			
			found = YES;
			
			// Update cache
			
			[connection->keyCache setObject:cacheKey forKey:@(rowid)];
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'getAllForKeyStatement': %d %s",
			                                                   status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_collection);
		FreeYapDatabaseString(&_key);
	}
	
	if (serializedObjectPtr) *serializedObjectPtr = serializedObject;
	if (serializedMetadataPtr) *serializedMetadataPtr = serializedMetadata;
	
	return found;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Enumerate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Fast enumeration over all the collections in the database.
 * 
 * This uses a "SELECT collection FROM database" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)enumerateCollectionsUsingBlock:(void (^)(NSString *collection, BOOL *stop))block
{
	if (block == NULL) return;
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateCollectionsStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT DISTINCT "collection" FROM "database2";
	
	int const column_idx_collection = SQLITE_COLUMN_START;
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(statement, column_idx_collection);
		int textSize = sqlite3_column_bytes(statement, column_idx_collection);
		
		NSString *collection = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		block(collection, &stop);
		
		if (stop || mutation.isMutated) break;
	}
	
	if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
	
	if (!stop && mutation.isMutated)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * This method is rarely needed, but may be helpful in certain situations.
 * 
 * This method may be used if you have the key, but not the collection for a particular item.
 * Please note that this is not the ideal situation.
 * 
 * Since there may be numerous collections for a given key, this method enumerates all possible collections.
**/
- (void)enumerateCollectionsForKey:(NSString *)key usingBlock:(void (^)(NSString *collection, BOOL *stop))block
{
	if (key == nil) return;
	if (block == NULL) return;
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateCollectionsForKeyStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "collection" FROM "database2" WHERE "key" = ?;
	
	int const column_idx_collection = SQLITE_COLUMN_START;
	int const bind_idx_key          = SQLITE_BIND_START;
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(statement, column_idx_collection);
		int textSize = sqlite3_column_bytes(statement, column_idx_collection);
		
		NSString *collection = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		block(collection, &stop);
		
		if (stop || mutation.isMutated) break;
	}
	
	if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
	FreeYapDatabaseString(&_key);
	
	if (!stop && mutation.isMutated)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fast enumeration over all keys in the given collection.
 *
 * This uses a "SELECT key FROM database WHERE collection = ?" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)enumerateKeysInCollection:(NSString *)collection
                       usingBlock:(void (^)(NSString *key, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self _enumerateKeysInCollection:collection usingBlock:^(int64_t __unused rowid, NSString *key, BOOL *stop) {
		
		block(key, stop);
	}];
}

/**
 * Fast enumeration over all keys in the given collection.
 *
 * This uses a "SELECT collection, key FROM database" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)enumerateKeysInAllCollectionsUsingBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self _enumerateKeysInAllCollectionsUsingBlock:^(int64_t __unused rowid, NSString *collection, NSString *key, BOOL *stop) {
		
		block(collection, key, stop);
	}];
}

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
                                 usingBlock:(void (^)(NSString *key, id object, BOOL *stop))block
{
	[self enumerateKeysAndObjectsInCollection:collection usingBlock:block withFilter:NULL];
}

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
                                 withFilter:(BOOL (^)(NSString *key))filter
{
	if (block == NULL) return;
	
	if (filter)
	{
		[self _enumerateKeysAndObjectsInCollection:collection
		                                usingBlock:^(int64_t __unused rowid, NSString *key, id object, BOOL *stop) {
			
			block(key, object, stop);
			
		} withFilter:^BOOL(int64_t __unused rowid, NSString *key) {
			
			return filter(key);
		}];
	}
	else
	{
		[self _enumerateKeysAndObjectsInCollection:collection
		                                usingBlock:^(int64_t __unused rowid, NSString *key, id object, BOOL *stop) {
			
			block(key, object, stop);
			
		} withFilter:NULL];
	}
}

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
                            (void (^)(NSString *collection, NSString *key, id object, BOOL *stop))block
{
	[self enumerateKeysAndObjectsInAllCollectionsUsingBlock:block withFilter:NULL];
}

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
                 withFilter:(BOOL (^)(NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	
	if (filter)
	{
		[self _enumerateKeysAndObjectsInAllCollectionsUsingBlock:
		    ^(int64_t __unused rowid, NSString *collection, NSString *key, id object, BOOL *stop) {
			
			block(collection, key, object, stop);
			
		} withFilter:^BOOL(int64_t __unused rowid, NSString *collection, NSString *key) {
			
			return filter(collection, key);
		}];
	}
	else
	{
		[self _enumerateKeysAndObjectsInAllCollectionsUsingBlock:
		    ^(int64_t __unused rowid, NSString *collection, NSString *key, id object, BOOL *stop) {
			
			block(collection, key, object, stop);
			
		} withFilter:NULL];
	}
}

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
                                  usingBlock:(void (^)(NSString *key, id metadata, BOOL *stop))block
{
	[self enumerateKeysAndMetadataInCollection:collection usingBlock:block withFilter:NULL];
}

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
                                  withFilter:(BOOL (^)(NSString *key))filter
{
	if (block == NULL) return;
	
	if (filter)
	{
		[self _enumerateKeysAndMetadataInCollection:collection
		                                 usingBlock:^(int64_t __unused rowid, NSString *key, id metadata, BOOL *stop) {
		
			block(key, metadata, stop);
			
		} withFilter:^BOOL(int64_t __unused rowid, NSString *key) {
			
			return filter(key);
		}];
	}
	else
	{
		[self _enumerateKeysAndMetadataInCollection:collection
		                                 usingBlock:^(int64_t __unused rowid, NSString *key, id metadata, BOOL *stop) {
		
			block(key, metadata, stop);
			
		} withFilter:NULL];
	}
}

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
                                        (void (^)(NSString *collection, NSString *key, id metadata, BOOL *stop))block
{
	[self enumerateKeysAndMetadataInAllCollectionsUsingBlock:block withFilter:NULL];
}

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
                             withFilter:(BOOL (^)(NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	
	if (filter)
	{
		[self _enumerateKeysAndMetadataInAllCollectionsUsingBlock:
		    ^(int64_t __unused rowid, NSString *collection, NSString *key, id metadata, BOOL *stop) {
			
			block(collection, key, metadata, stop);
			
		} withFilter:^BOOL(int64_t __unused rowid, NSString *collection, NSString *key) {
			
			return filter(collection, key);
		}];
	}
	else
	{
		[self _enumerateKeysAndMetadataInAllCollectionsUsingBlock:
		    ^(int64_t __unused rowid, NSString *collection, NSString *key, id metadata, BOOL *stop) {
			
			block(collection, key, metadata, stop);
			
		} withFilter:NULL];
	}
}

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
                       usingBlock:(void (^)(NSString *key, id object, id metadata, BOOL *stop))block
{
	[self enumerateRowsInCollection:collection usingBlock:block withFilter:NULL];
}

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
                       withFilter:(BOOL (^)(NSString *key))filter
{
	if (block == NULL) return;
	
	if (filter)
	{
		[self _enumerateRowsInCollection:collection
		                      usingBlock:^(int64_t __unused rowid, NSString *key, id object, id metadata, BOOL *stop) {
			
			block(key, object, metadata, stop);
			
		} withFilter:^BOOL(int64_t __unused rowid, NSString *key) {
			
			return filter(key);
		}];
	}
	else
	{
		[self _enumerateRowsInCollection:collection
		                      usingBlock:^(int64_t __unused rowid, NSString *key, id object, id metadata, BOOL *stop) {
			
			block(key, object, metadata, stop);
			
		} withFilter:NULL];
	}
}

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
                            (void (^)(NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
{
	[self enumerateRowsInAllCollectionsUsingBlock:block withFilter:NULL];
}

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
                 withFilter:(BOOL (^)(NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	
	if (filter)
	{
		[self _enumerateRowsInAllCollectionsUsingBlock:
		    ^(int64_t __unused rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop) {
			
			block(collection, key, object, metadata, stop);
			
		} withFilter:^BOOL(int64_t __unused rowid, NSString *collection, NSString *key) {
			
			return filter(collection, key);
		}];
	}
	else
	{
		[self _enumerateRowsInAllCollectionsUsingBlock:
		    ^(int64_t __unused rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop) {
			
			block(collection, key, object, metadata, stop);
			
		} withFilter:NULL];
	}
}

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
            unorderedUsingBlock:(void (^)(NSUInteger keyIndex, id object, BOOL *stop))block
{
	if (block == NULL) return;
	if ([keys count] == 0) return;
	if (collection == nil) collection = @"";
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	// Check the cache first (to optimize cache)
	
	NSMutableArray *missingIndexes = [NSMutableArray arrayWithCapacity:[keys count]];
	NSUInteger keyIndex = 0;
	
	for (NSString *key in keys)
	{
		YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		id object = [connection->objectCache objectForKey:cacheKey];
		if (object)
		{
			block(keyIndex, object, &stop);
			
			if (stop || mutation.isMutated) break;
		}
		else
		{
			[missingIndexes addObject:@(keyIndex)];
		}
		
		keyIndex++;
	}
	
	if (stop) {
		return;
	}
	if (mutation.isMutated) {
		@throw [self mutationDuringEnumerationException];
		return;
	}
	if ([missingIndexes count] == 0) {
		return;
	}
	
	// Go to database for any missing keys (if needed)
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	
	NSMutableDictionary *keyIndexDict = nil;
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(connection->db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	do
	{
		// Determine how many parameters to use in the query
		
		NSUInteger numKeyParams = MIN([missingIndexes count], (maxHostParams-1)); // minus 1 for collection param
		
		// Create the SQL query:
		//
		// SELECT "key", "data" FROM "database2" WHERE "collection" = ? AND key IN (?, ?, ...);
		
		int const column_idx_key  = SQLITE_COLUMN_START + 0;
		int const column_idx_data = SQLITE_COLUMN_START + 1;
		
		NSUInteger capacity = 80 + (numKeyParams * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendString:@"SELECT \"key\", \"data\" FROM \"database2\""];
		[query appendString:@" WHERE \"collection\" = ? AND \"key\" IN ("];
		
		NSUInteger i;
		for (i = 0; i < numKeyParams; i++)
		{
			if (i == 0)
				[query appendString:@"?"];
			else
				[query appendString:@", ?"];
		}
		
		[query appendString:@");"];
		
		sqlite3_stmt *statement;
		
		int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'objectsForKeys' statement: %d %s",
						status, sqlite3_errmsg(connection->db));
			break; // Break from do/while. Still need to free _collection.
		}
		
		// Bind parameters.
		// And move objects from the missingIndexes array into keyIndexDict.
		
		if (keyIndexDict == nil)
			keyIndexDict = [NSMutableDictionary dictionaryWithCapacity:numKeyParams];
		else
			[keyIndexDict removeAllObjects];
		
		sqlite3_bind_text(statement, SQLITE_BIND_START, _collection.str, _collection.length, SQLITE_STATIC);
		
		for (i = 0; i < numKeyParams; i++)
		{
			NSNumber *keyIndexNumber = [missingIndexes objectAtIndex:i];
			NSString *key = [keys objectAtIndex:[keyIndexNumber unsignedIntegerValue]];
			
			[keyIndexDict setObject:keyIndexNumber forKey:key];
			
			sqlite3_bind_text(statement, (int)(SQLITE_BIND_START + 1 + i), [key UTF8String], -1, SQLITE_TRANSIENT);
		}
		
		[missingIndexes removeObjectsInRange:NSMakeRange(0, numKeyParams)];
		
		// Execute the query and step over the results
		
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
			int textSize = sqlite3_column_bytes(statement, column_idx_key);
			
			NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			keyIndex = [[keyIndexDict objectForKey:key] unsignedIntegerValue];
			
			// Note: We already checked the cache (above),
			// so we already know this item is not in the cache.
			
			const void *blob = sqlite3_column_blob(statement, column_idx_data);
			int blobSize = sqlite3_column_bytes(statement, column_idx_data);
			
			NSData *objectData = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			id object = connection->database->objectDeserializer(collection, key, objectData);
			
			if (object)
			{
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				[connection->objectCache setObject:object forKey:cacheKey];
			}
			
			block(keyIndex, object, &stop);
			
			[keyIndexDict removeObjectForKey:key];
			
			if (stop || mutation.isMutated) break;
		}
		
		if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
		
		if (stop) {
			FreeYapDatabaseString(&_collection);
			return;
		}
		if (mutation.isMutated) {
			FreeYapDatabaseString(&_collection);
			@throw [self mutationDuringEnumerationException];
			return;
		}
		
		// If there are any remaining items in the keyIndexDict,
		// then those items didn't exist in the database.
		
		for (NSNumber *keyIndexNumber in [keyIndexDict objectEnumerator])
		{
			block([keyIndexNumber unsignedIntegerValue], nil, &stop);
			
			// Do NOT add keys to the cache that don't exist in the database.
			
			if (stop || mutation.isMutated) break;
		}
		
		if (stop) {
			FreeYapDatabaseString(&_collection);
			return;
		}
		if (mutation.isMutated) {
			FreeYapDatabaseString(&_collection);
			@throw [self mutationDuringEnumerationException];
			return;
		}
		
		
	} while ([missingIndexes count] > 0);
	
	FreeYapDatabaseString(&_collection);
}

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
             unorderedUsingBlock:(void (^)(NSUInteger keyIndex, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	if ([keys count] == 0) return;
	if (collection == nil) collection = @"";
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	// Check the cache first (to optimize cache)
	
	NSMutableArray *missingIndexes = [NSMutableArray arrayWithCapacity:[keys count]];
	NSUInteger keyIndex = 0;
	
	for (NSString *key in keys)
	{
		YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		id metadata = [connection->metadataCache objectForKey:cacheKey];
		if (metadata)
		{
			if (metadata == [YapNull null])
				block(keyIndex, nil, &stop);
			else
				block(keyIndex, metadata, &stop);
			
			if (stop || mutation.isMutated) break;
		}
		else
		{
			[missingIndexes addObject:@(keyIndex)];
		}
		
		keyIndex++;
	}
	
	if (stop) {
		return;
	}
	if (mutation.isMutated) {
		@throw [self mutationDuringEnumerationException];
		return;
	}
	if ([missingIndexes count] == 0) {
		return;
	}
	
	// Go to database for any missing keys (if needed)
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	
	NSMutableDictionary *keyIndexDict = nil;
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(connection->db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	do
	{
		// Determine how many parameters to use in the query
		
		NSUInteger numKeyParams = MIN([missingIndexes count], (maxHostParams-1)); // minus 1 for collection param
		
		// Create the SQL query:
		//
		// SELECT "key", "metadata" FROM "database2" WHERE "collection" = ? AND key IN (?, ?, ...);
		
		int const column_idx_key      = SQLITE_COLUMN_START + 0;
		int const column_idx_metadata = SQLITE_COLUMN_START + 1;
		
		NSUInteger capacity = 80 + (numKeyParams * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendString:@"SELECT \"key\", \"metadata\" FROM \"database2\""];
		[query appendString:@" WHERE \"collection\" = ? AND \"key\" IN ("];
		
		NSUInteger i;
		for (i = 0; i < numKeyParams; i++)
		{
			if (i == 0)
				[query appendString:@"?"];
			else
				[query appendString:@", ?"];
		}
		
		[query appendString:@");"];
		
		sqlite3_stmt *statement;
		
		int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'metadataForKeys' statement: %d %s",
						status, sqlite3_errmsg(connection->db));
			break; // Break from do/while. Still need to free _collection.
		}
		
		// Bind parameters.
		// And move objects from the missingIndexes array into keyIndexDict.
		
		if (keyIndexDict == nil)
			keyIndexDict = [NSMutableDictionary dictionaryWithCapacity:numKeyParams];
		else
			[keyIndexDict removeAllObjects];
		
		sqlite3_bind_text(statement, SQLITE_BIND_START, _collection.str, _collection.length, SQLITE_STATIC);
		
		for (i = 0; i < numKeyParams; i++)
		{
			NSNumber *keyIndexNumber = [missingIndexes objectAtIndex:i];
			NSString *key = [keys objectAtIndex:[keyIndexNumber unsignedIntegerValue]];
			
			[keyIndexDict setObject:keyIndexNumber forKey:key];
			
			sqlite3_bind_text(statement, (int)(SQLITE_BIND_START + 1 + i), [key UTF8String], -1, SQLITE_TRANSIENT);
		}
		
		[missingIndexes removeObjectsInRange:NSMakeRange(0, numKeyParams)];
		
		// Execute the query and step over the results
		
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
			int textSize = sqlite3_column_bytes(statement, column_idx_key);
			
			const void *blob = sqlite3_column_blob(statement, column_idx_metadata);
			int blobSize = sqlite3_column_bytes(statement, column_idx_metadata);
			
			NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			keyIndex = [[keyIndexDict objectForKey:key] unsignedIntegerValue];
			
			NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			
			id metadata = data ? connection->database->metadataDeserializer(collection, key, data) : nil;
			
			if (metadata)
			{
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				[connection->metadataCache setObject:metadata forKey:cacheKey];
			}
			
			block(keyIndex, metadata, &stop);
			
			[keyIndexDict removeObjectForKey:key];
			
			if (stop || mutation.isMutated) break;
		}
		
		if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
		
		if (stop) {
			FreeYapDatabaseString(&_collection);
			return;
		}
		if (mutation.isMutated) {
			FreeYapDatabaseString(&_collection);
			@throw [self mutationDuringEnumerationException];
			return;
		}
		
		// If there are any remaining items in the keyIndexDict,
		// then those items didn't exist in the database.
		
		for (NSNumber *keyIndexNumber in [keyIndexDict objectEnumerator])
		{
			block([keyIndexNumber unsignedIntegerValue], nil, &stop);
			
			// Do NOT add keys to the cache that don't exist in the database.
			
			if (stop || mutation.isMutated) break;
		}
		
		if (stop) {
			FreeYapDatabaseString(&_collection);
			return;
		}
		if (mutation.isMutated) {
			FreeYapDatabaseString(&_collection);
			@throw [self mutationDuringEnumerationException];
			return;
		}
		
		
	} while ([missingIndexes count] > 0);
	
	FreeYapDatabaseString(&_collection);
}

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
- (void)enumerateRowsForKeys:(NSArray *)keys
                inCollection:(NSString *)collection
         unorderedUsingBlock:(void (^)(NSUInteger keyIndex, id object, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	if ([keys count] == 0) return;
	if (collection == nil) collection = @"";
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	__block BOOL stop = NO;
	
	// Check the cache first (to optimize cache)
	
	NSMutableArray *missingIndexes = [NSMutableArray arrayWithCapacity:[keys count]];
	NSUInteger keyIndex = 0;
	
	for (NSString *key in keys)
	{
		YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		id object = [connection->objectCache objectForKey:cacheKey];
		if (object)
		{
			id metadata = [connection->metadataCache objectForKey:cacheKey];
			if (metadata)
			{
				if (metadata == [YapNull null])
					block(keyIndex, object, nil, &stop);
				else
					block(keyIndex, object, metadata, &stop);
				
				if (stop || mutation.isMutated) break;
			}
			else
			{
				[missingIndexes addObject:@(keyIndex)];
			}
		}
		else
		{
			[missingIndexes addObject:@(keyIndex)];
		}
		
		keyIndex++;
	}
	
	if (stop) {
		return;
	}
	if (mutation.isMutated) {
		@throw [self mutationDuringEnumerationException];
		return;
	}
	if ([missingIndexes count] == 0) {
		return;
	}
	
	// Go to database for any missing keys (if needed)
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	
	NSMutableDictionary *keyIndexDict = nil;
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(connection->db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	do
	{
		// Determine how many parameters to use in the query
		
		NSUInteger numKeyParams = MIN([missingIndexes count], (maxHostParams-1)); // minus 1 for collection param
		
		// Create the SQL query:
		//
		// SELECT "key", "data", "metadata" FROM "database2" WHERE "collection" = ? AND key IN (?, ?, ...);
		
		int const column_idx_key      = SQLITE_COLUMN_START + 0;
		int const column_idx_data     = SQLITE_COLUMN_START + 1;
		int const column_idx_metadata = SQLITE_COLUMN_START + 2;
		
		NSUInteger capacity = 80 + (numKeyParams * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendString:@"SELECT \"key\", \"data\", \"metadata\" FROM \"database2\""];
		[query appendString:@" WHERE \"collection\" = ? AND \"key\" IN ("];
		
		NSUInteger i;
		for (i = 0; i < numKeyParams; i++)
		{
			if (i == 0)
				[query appendString:@"?"];
			else
				[query appendString:@", ?"];
		}
		
		[query appendString:@");"];
		
		sqlite3_stmt *statement;
		
		int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'objectsAndMetadataForKeys' statement: %d %s",
						status, sqlite3_errmsg(connection->db));
			break; // Break from do/while. Still need to free _collection.
		}
		
		// Bind parameters.
		// And move objects from the missingIndexes array into keyIndexDict.
		
		if (keyIndexDict == nil)
			keyIndexDict = [NSMutableDictionary dictionaryWithCapacity:numKeyParams];
		else
			[keyIndexDict removeAllObjects];
		
		sqlite3_bind_text(statement, SQLITE_BIND_START, _collection.str, _collection.length, SQLITE_STATIC);
		
		for (i = 0; i < numKeyParams; i++)
		{
			NSNumber *keyIndexNumber = [missingIndexes objectAtIndex:i];
			NSString *key = [keys objectAtIndex:[keyIndexNumber unsignedIntegerValue]];
			
			[keyIndexDict setObject:keyIndexNumber forKey:key];
			
			sqlite3_bind_text(statement, (int)(SQLITE_BIND_START + 1 + i), [key UTF8String], -1, SQLITE_TRANSIENT);
		}
		
		[missingIndexes removeObjectsInRange:NSMakeRange(0, numKeyParams)];
		
		// Execute the query and step over the results
		
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
			int textSize = sqlite3_column_bytes(statement, column_idx_key);
			
			NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			keyIndex = [[keyIndexDict objectForKey:key] unsignedIntegerValue];
			
			// Note: When we checked the caches (above),
			// we could only process the item if the object & metadata were both cached.
			// So it's worthwhile to check each individual cache here.
			
			YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
			
			id object = [connection->objectCache objectForKey:cacheKey];
			if (object == nil)
			{
				const void *oBlob = sqlite3_column_blob(statement, column_idx_data);
				int oBlobSize = sqlite3_column_bytes(statement, column_idx_data);
				
				NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
				object = connection->database->objectDeserializer(collection, key, oData);
				
				if (object)
					[connection->objectCache setObject:object forKey:cacheKey];
			}
			
			id metadata = [connection->metadataCache objectForKey:cacheKey];
			if (metadata)
			{
				if (metadata == [YapNull null])
					metadata = nil;
			}
			else
			{
				const void *mBlob = sqlite3_column_blob(statement, column_idx_metadata);
				int mBlobSize = sqlite3_column_bytes(statement, column_idx_metadata);
				
				if (mBlobSize > 0)
				{
					NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
					metadata = connection->database->metadataDeserializer(collection, key, mData);
				}
				
				if (metadata)
					[connection->metadataCache setObject:metadata forKey:cacheKey];
				else
					[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
			}
			
			block(keyIndex, object, metadata, &stop);
			
			[keyIndexDict removeObjectForKey:key];
			
			if (stop || mutation.isMutated) break;
		}
		
		if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
		
		if (stop) {
			FreeYapDatabaseString(&_collection);
			return;
		}
		if (mutation.isMutated) {
			FreeYapDatabaseString(&_collection);
			@throw [self mutationDuringEnumerationException];
			return;
		}
		
		// If there are any remaining items in the keyIndexDict,
		// then those items didn't exist in the database.
		
		for (NSNumber *keyIndexNumber in [keyIndexDict objectEnumerator])
		{
			block([keyIndexNumber unsignedIntegerValue], nil, nil, &stop);
			
			// Do NOT add keys to the cache that don't exist in the database.
			
			if (stop || mutation.isMutated) break;
		}
		
		if (stop) {
			FreeYapDatabaseString(&_collection);
			return;
		}
		if (mutation.isMutated) {
			FreeYapDatabaseString(&_collection);
			@throw [self mutationDuringEnumerationException];
			return;
		}
		
		
	} while ([missingIndexes count] > 0);
	
	FreeYapDatabaseString(&_collection);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal Enumerate (using rowid)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Fast enumeration over all keys in the given collection.
 *
 * This uses a "SELECT key FROM database WHERE collection = ?" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)_enumerateKeysInCollection:(NSString *)collection
                        usingBlock:(void (^)(int64_t rowid, NSString *key, BOOL *stop))block
{
	if (block == NULL) return;
	if (collection == nil) collection = @"";
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateKeysInCollectionStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "key" FROM "database2" WHERE collection = ?;
	
	int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
	int const column_idx_key      = SQLITE_COLUMN_START + 1;
	int const bind_idx_collection = SQLITE_BIND_START;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
		int textSize = sqlite3_column_bytes(statement, column_idx_key);
		
		NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		block(rowid, key, &stop);
		
		if (stop || mutation.isMutated) break;
	}
	
	if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
	FreeYapDatabaseString(&_collection);
	
	if (!stop && mutation.isMutated)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fast enumeration over all keys in select collections.
 *
 * This uses a "SELECT key FROM database WHERE collection = ?" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)_enumerateKeysInCollections:(NSArray *)collections
                         usingBlock:(void (^)(int64_t rowid, NSString *collection, NSString *key, BOOL *stop))block
{
	if (block == NULL) return;
	if ([collections count] == 0) return;
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateKeysInCollectionStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "key" FROM "database2" WHERE collection = ?;
	
	int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
	int const column_idx_key      = SQLITE_COLUMN_START + 1;
	int const bind_idx_collection = SQLITE_BIND_START;
	
	for (NSString *collection in collections)
	{
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
		
		int status;
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
			int textSize = sqlite3_column_bytes(statement, column_idx_key);
			
			NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			block(rowid, collection, key, &stop);
			
			if (stop || mutation.isMutated) break;
		}
		
		if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite_enum_reset(statement, needsFinalize);
		FreeYapDatabaseString(&_collection);
		
		if (!stop && mutation.isMutated)
		{
			@throw [self mutationDuringEnumerationException];
		}
			
		if (stop)
		{
			break;
		}
		
	} // end for (NSString *collection in collections)
}

/**
 * Fast enumeration over all keys in the given collection.
 *
 * This uses a "SELECT collection, key FROM database" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)_enumerateKeysInAllCollectionsUsingBlock:
                            (void (^)(int64_t rowid, NSString *collection, NSString *key, BOOL *stop))block
{
	if (block == NULL) return;
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateKeysInAllCollectionsStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "collection", "key" FROM "database2";
	
	int const column_idx_rowid      = SQLITE_COLUMN_START + 0;
	int const column_idx_collection = SQLITE_COLUMN_START + 1;
	int const column_idx_key        = SQLITE_COLUMN_START + 2;
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		const unsigned char *text1 = sqlite3_column_text(statement, column_idx_collection);
		int textSize1 = sqlite3_column_bytes(statement, column_idx_collection);
		
		const unsigned char *text2 = sqlite3_column_text(statement, column_idx_key);
		int textSize2 = sqlite3_column_bytes(statement, column_idx_key);
		
		NSString *collection, *key;
		
		collection = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
		key        = [[NSString alloc] initWithBytes:text2 length:textSize2 encoding:NSUTF8StringEncoding];
		
		block(rowid, collection, key, &stop);
		
		if (stop || mutation.isMutated) break;
	}
	
	if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
	
	if (!stop && mutation.isMutated)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

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
- (void)_enumerateKeysAndObjectsInCollection:(NSString *)collection
                                  usingBlock:(void (^)(int64_t rowid, NSString *key, id object, BOOL *stop))block
{
	[self _enumerateKeysAndObjectsInCollection:collection usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over objects in the database for which you're interested in.
 * The filter block allows you to decide which objects you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
**/
- (void)_enumerateKeysAndObjectsInCollection:(NSString *)collection
                                  usingBlock:(void (^)(int64_t rowid, NSString *key, id object, BOOL *stop))block
                                  withFilter:(BOOL (^)(int64_t rowid, NSString *key))filter
{
	if (block == NULL) return;
	if (collection == nil) collection = @"";
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateKeysAndObjectsInCollectionStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "key", "data", FROM "database2" WHERE "collection" = ?;
	
	int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
	int const column_idx_key      = SQLITE_COLUMN_START + 1;
	int const column_idx_data     = SQLITE_COLUMN_START + 2;
	int const bind_idx_collection = SQLITE_BIND_START;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
	
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
		int textSize = sqlite3_column_bytes(statement, column_idx_key);
		
		NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, key);
		if (invokeBlock)
		{
			YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
			
			id object = [connection->objectCache objectForKey:cacheKey];
			if (object == nil)
			{
				const void *oBlob = sqlite3_column_blob(statement, column_idx_data);
				int oBlobSize = sqlite3_column_bytes(statement, column_idx_data);
				
				// Performance tuning:
				// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
				
				NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
				object = connection->database->objectDeserializer(collection, key, oData);
				
				// Cache considerations:
				// Do we want to add the objects/metadata to the cache here?
				// If the cache is unlimited then we should.
				// Otherwise we should only add to the cache if it's not full.
				// The cache should generally be reserved for items that are explicitly fetched,
				// and we don't want to crowd them out during enumerations.
				
				if (unlimitedObjectCacheLimit || [connection->objectCache count] < connection->objectCacheLimit)
				{
					if (object)
						[connection->objectCache setObject:object forKey:cacheKey];
				}
			}
			
			block(rowid, key, object, &stop);
			
			if (stop || mutation.isMutated) break;
		}
	}
	
	if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
	FreeYapDatabaseString(&_collection);
	
	if (!stop && mutation.isMutated)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fast enumeration over selected objects in the database.
 *
 * This uses a "SELECT key, object from database WHERE collection = ?" operation, and then steps over the results,
 * deserializing each object, and then invoking the given block handler.
 *
 * If you only need to enumerate over certain objects (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those objects you're not interested in.
**/
- (void)_enumerateKeysAndObjectsInCollections:(NSArray *)collections usingBlock:
                            (void (^)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop))block
{
	[self _enumerateKeysAndObjectsInCollections:collections usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over objects in the database for which you're interested in.
 * The filter block allows you to decide which objects you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
**/
- (void)_enumerateKeysAndObjectsInCollections:(NSArray *)collections
                 usingBlock:(void (^)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop))block
                 withFilter:(BOOL (^)(int64_t rowid, NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	if ([collections count] == 0) return;
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateKeysAndObjectsInCollectionStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	
	// SELECT "rowid", "key", "data", FROM "database2" WHERE "collection" = ?;
	
	int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
	int const column_idx_key      = SQLITE_COLUMN_START + 1;
	int const column_idx_data     = SQLITE_COLUMN_START + 2;
	int const bind_idx_collection = SQLITE_BIND_START;
	
	for (NSString *collection in collections)
	{
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
		
		int status;
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
			int textSize = sqlite3_column_bytes(statement, column_idx_key);
			
			NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, collection, key);
			if (invokeBlock)
			{
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				id object = [connection->objectCache objectForKey:cacheKey];
				if (object == nil)
				{
					const void *oBlob = sqlite3_column_blob(statement, column_idx_data);
					int oBlobSize = sqlite3_column_bytes(statement, column_idx_data);
					
					// Performance tuning:
					// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
					
					NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
					object = connection->database->objectDeserializer(collection, key, oData);
					
					// Cache considerations:
					// Do we want to add the objects/metadata to the cache here?
					// If the cache is unlimited then we should.
					// Otherwise we should only add to the cache if it's not full.
					// The cache should generally be reserved for items that are explicitly fetched,
					// and we don't want to crowd them out during enumerations.
					
					if (unlimitedObjectCacheLimit ||
					    [connection->objectCache count] < connection->objectCacheLimit)
					{
						if (object)
							[connection->objectCache setObject:object forKey:cacheKey];
					}
				}
				
				block(rowid, collection, key, object, &stop);
				
				if (stop || mutation.isMutated) break;
			}
		}
		
		if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement); // ok: within loop
		sqlite3_reset(statement);          // ok: within loop
		FreeYapDatabaseString(&_collection);
		
		if (!stop && mutation.isMutated)
		{
			@throw [self mutationDuringEnumerationException];
		}
		
		if (stop)
		{
			break;
		}
		
	} // end for (NSString *collection in collections)
	
	sqlite_enum_reset(statement, needsFinalize);
}

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
- (void)_enumerateKeysAndObjectsInAllCollectionsUsingBlock:
                            (void (^)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop))block
{
	[self _enumerateKeysAndObjectsInAllCollectionsUsingBlock:block withFilter:NULL];
}

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
- (void)_enumerateKeysAndObjectsInAllCollectionsUsingBlock:
                            (void (^)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop))block
                 withFilter:(BOOL (^)(int64_t rowid, NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateKeysAndObjectsInAllCollectionsStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "collection", "key", "data" FROM "database2" ORDER BY \"collection\" ASC;";
	
	int const column_idx_rowid      = SQLITE_COLUMN_START + 0;
	int const column_idx_collection = SQLITE_COLUMN_START + 1;
	int const column_idx_key        = SQLITE_COLUMN_START + 2;
	int const column_idx_data       = SQLITE_COLUMN_START + 3;
	
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		const unsigned char *text1 = sqlite3_column_text(statement, column_idx_collection);
		int textSize1 = sqlite3_column_bytes(statement, column_idx_collection);
		
		const unsigned char *text2 = sqlite3_column_text(statement, column_idx_key);
		int textSize2 = sqlite3_column_bytes(statement, column_idx_key);
		
		NSString *collection, *key;
		
		collection = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
		key        = [[NSString alloc] initWithBytes:text2 length:textSize2 encoding:NSUTF8StringEncoding];
		
		BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, collection, key);
		if (invokeBlock)
		{
			YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
			
			id object = [connection->objectCache objectForKey:cacheKey];
			if (object == nil)
			{
				const void *oBlob = sqlite3_column_blob(statement, column_idx_data);
				int oBlobSize = sqlite3_column_bytes(statement, column_idx_data);
				
				NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
				object = connection->database->objectDeserializer(collection, key, oData);
				
				if (unlimitedObjectCacheLimit || [connection->objectCache count] < connection->objectCacheLimit)
				{
					if (object)
						[connection->objectCache setObject:object forKey:cacheKey];
				}
			}
			
			block(rowid, collection, key, object, &stop);
			
			if (stop || mutation.isMutated) break;
		}
	}
	
	if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
	
	if (!stop && mutation.isMutated)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

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
- (void)_enumerateKeysAndMetadataInCollection:(NSString *)collection
                                   usingBlock:(void (^)(int64_t rowid, NSString *key, id metadata, BOOL *stop))block
{
	[self _enumerateKeysAndMetadataInCollection:collection usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over all keys and associated metadata in the given collection.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
 * 
 * Keep in mind that you cannot modify the collection mid-enumeration (just like any other kind of enumeration).
**/
- (void)_enumerateKeysAndMetadataInCollection:(NSString *)collection
                                   usingBlock:(void (^)(int64_t rowid, NSString *key, id metadata, BOOL *stop))block
                                   withFilter:(BOOL (^)(int64_t rowid, NSString *key))filter
{
	if (block == NULL) return;
	if (collection == nil) collection = @"";
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateKeysAndMetadataInCollectionStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "key", "metadata" FROM "database2" WHERE "collection" = ?;
	
	int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
	int const column_idx_key      = SQLITE_COLUMN_START + 1;
	int const column_idx_metadata = SQLITE_COLUMN_START + 2;
	int const bind_idx_collection = SQLITE_BIND_START;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
	
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
		int textSize = sqlite3_column_bytes(statement, column_idx_key);
		
		NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, key);
		if (invokeBlock)
		{
			YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
			id metadata = [connection->metadataCache objectForKey:cacheKey];
			if (metadata)
			{
				if (metadata == [YapNull null])
					metadata = nil;
			}
			else
			{
				const void *mBlob = sqlite3_column_blob(statement, column_idx_metadata);
				int mBlobSize = sqlite3_column_bytes(statement, column_idx_metadata);
				
				if (mBlobSize > 0)
				{
					// Performance tuning:
					// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
					
					NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
					metadata = connection->database->metadataDeserializer(collection, key, mData);
				}
				
				// Cache considerations:
				// Do we want to add the objects/metadata to the cache here?
				// If the cache is unlimited then we should.
				// Otherwise we should only add to the cache if it's not full.
				// The cache should generally be reserved for items that are explicitly fetched,
				// and we don't want to crowd them out during enumerations.
				
				if (unlimitedMetadataCacheLimit ||
				    [connection->metadataCache count] < connection->metadataCacheLimit)
				{
					if (metadata)
						[connection->metadataCache setObject:metadata forKey:cacheKey];
					else
						[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
				}
			}
			
			block(rowid, key, metadata, &stop);
			
			if (stop || mutation.isMutated) break;
		}
	}
	
	if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
	FreeYapDatabaseString(&_collection);
	
	if (!stop && mutation.isMutated)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fast enumeration over select keys and associated metadata in the given collection.
 * 
 * This uses a "SELECT key, metadata FROM database WHERE collection = ?" operation and steps over the results.
 * 
 * If you only need to enumerate over certain items (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the deserialization step for those items you're not interested in.
 * 
 * Keep in mind that you cannot modify the collection mid-enumeration (just like any other kind of enumeration).
**/
- (void)_enumerateKeysAndMetadataInCollections:(NSArray *)collections
                usingBlock:(void (^)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop))block
{
	[self _enumerateKeysAndMetadataInCollections:collections usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over selected keys and associated metadata in the given collection.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
 * 
 * Keep in mind that you cannot modify the collection mid-enumeration (just like any other kind of enumeration).
**/
- (void)_enumerateKeysAndMetadataInCollections:(NSArray *)collections
                usingBlock:(void (^)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop))block
                withFilter:(BOOL (^)(int64_t rowid, NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	if ([collections count] == 0) return;
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateKeysAndMetadataInCollectionStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);
	
	// SELECT "rowid", "key", "metadata" FROM "database2" WHERE "collection" = ?;
	
	int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
	int const column_idx_key      = SQLITE_COLUMN_START + 1;
	int const column_idx_metadata = SQLITE_COLUMN_START + 2;
	int const bind_idx_collection = SQLITE_BIND_START;
	
	for (NSString *collection in collections)
	{
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
		
		int status;
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
			int textSize = sqlite3_column_bytes(statement, column_idx_key);
			
			NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, collection, key);
			if (invokeBlock)
			{
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
			
				id metadata = [connection->metadataCache objectForKey:cacheKey];
				if (metadata)
				{
					if (metadata == [YapNull null])
						metadata = nil;
				}
				else
				{
					const void *mBlob = sqlite3_column_blob(statement, column_idx_metadata);
					int mBlobSize = sqlite3_column_bytes(statement, column_idx_metadata);
					
					if (mBlobSize > 0)
					{
						// Performance tuning:
						// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
						
						NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
						metadata = connection->database->metadataDeserializer(collection, key, mData);
					}
					
					// Cache considerations:
					// Do we want to add the objects/metadata to the cache here?
					// If the cache is unlimited then we should.
					// Otherwise we should only add to the cache if it's not full.
					// The cache should generally be reserved for items that are explicitly fetched,
					// and we don't want to crowd them out during enumerations.
					
					if (unlimitedMetadataCacheLimit ||
					    [connection->metadataCache count] < connection->metadataCacheLimit)
					{
						if (metadata)
							[connection->metadataCache setObject:metadata forKey:cacheKey];
						else
							[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
					}
				}
				
				block(rowid, collection, key, metadata, &stop);
				
				if (stop || mutation.isMutated) break;
			}
		}
		
		if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement); // ok: within loop
		sqlite3_reset(statement);          // ok: within loop
		FreeYapDatabaseString(&_collection);
		
		if (!stop && mutation.isMutated)
		{
			@throw [self mutationDuringEnumerationException];
		}
		
		if (stop)
		{
			break;
		}
		
	} // end for (NSString *collection in collections)
	
	sqlite_enum_reset(statement, needsFinalize);
}

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
- (void)_enumerateKeysAndMetadataInAllCollectionsUsingBlock:
                        (void (^)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop))block
{
	[self _enumerateKeysAndMetadataInAllCollectionsUsingBlock:block withFilter:NULL];
}

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
- (void)_enumerateKeysAndMetadataInAllCollectionsUsingBlock:
                        (void (^)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop))block
             withFilter:(BOOL (^)(int64_t rowid, NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateKeysAndMetadataInAllCollectionsStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "collection", "key", "metadata" FROM "database2" ORDER BY "collection" ASC;
	
	int const column_idx_rowid      = SQLITE_COLUMN_START + 0;
	int const column_idx_collection = SQLITE_COLUMN_START + 1;
	int const column_idx_key        = SQLITE_COLUMN_START + 2;
	int const column_idx_metadata   = SQLITE_COLUMN_START + 3;
	
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		const unsigned char *text1 = sqlite3_column_text(statement, column_idx_collection);
		int textSize1 = sqlite3_column_bytes(statement, column_idx_collection);
		
		const unsigned char *text2 = sqlite3_column_text(statement, column_idx_key);
		int textSize2 = sqlite3_column_bytes(statement, column_idx_key);
		
		NSString *collection, *key;
		
		collection = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
		key        = [[NSString alloc] initWithBytes:text2 length:textSize2 encoding:NSUTF8StringEncoding];
		
		BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, collection, key);
		if (invokeBlock)
		{
			YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
			
			id metadata = [connection->metadataCache objectForKey:cacheKey];
			if (metadata)
			{
				if (metadata == [YapNull null])
					metadata = nil;
			}
			else
			{
				const void *mBlob = sqlite3_column_blob(statement, column_idx_metadata);
				int mBlobSize = sqlite3_column_bytes(statement, column_idx_metadata);
				
				if (mBlobSize > 0)
				{
					// Performance tuning:
					// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
					
					NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
					metadata = connection->database->metadataDeserializer(collection, key, mData);
				}
				
				// Cache considerations:
				// Do we want to add the objects/metadata to the cache here?
				// If the cache is unlimited then we should.
				// Otherwise we should only add to the cache if it's not full.
				// The cache should generally be reserved for items that are explicitly fetched,
				// and we don't want to crowd them out during enumerations.
				
				if (unlimitedMetadataCacheLimit ||
				    [connection->metadataCache count] < connection->metadataCacheLimit)
				{
					if (metadata)
						[connection->metadataCache setObject:metadata forKey:cacheKey];
					else
						[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
				}
			}
			
			block(rowid, collection, key, metadata, &stop);
			
			if (stop || mutation.isMutated) break;
		}
	}
	
	if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
	
	if (!stop && mutation.isMutated)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

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
- (void)_enumerateRowsInCollection:(NSString *)collection
                        usingBlock:(void (^)(int64_t rowid, NSString *key, id object, id metadata, BOOL *stop))block
{
	[self _enumerateRowsInCollection:collection usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over rows in the database for which you're interested in.
 * The filter block allows you to decide which rows you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object & metadata.
**/
- (void)_enumerateRowsInCollection:(NSString *)collection
                        usingBlock:(void (^)(int64_t rowid, NSString *key, id object, id metadata, BOOL *stop))block
                        withFilter:(BOOL (^)(int64_t rowid, NSString *key))filter
{
	if (block == NULL) return;
	if (collection == nil) collection = @"";
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateRowsInCollectionStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "key", "data", "metadata" FROM "database2" WHERE "collection" = ?;
	
	int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
	int const column_idx_key      = SQLITE_COLUMN_START + 1;
	int const column_idx_data     = SQLITE_COLUMN_START + 2;
	int const column_idx_metadata = SQLITE_COLUMN_START + 3;
	int const bind_idx_collection = SQLITE_BIND_START;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
	
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
		int textSize = sqlite3_column_bytes(statement, column_idx_key);
		
		NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, key);
		if (invokeBlock)
		{
			YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
			
			id object = [connection->objectCache objectForKey:cacheKey];
			if (object == nil)
			{
				const void *oBlob = sqlite3_column_blob(statement, column_idx_data);
				int oBlobSize = sqlite3_column_bytes(statement, column_idx_data);
				
				// Performance tuning:
				// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
				
				NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
				object = connection->database->objectDeserializer(collection, key, oData);
				
				// Cache considerations:
				// Do we want to add the objects/metadata to the cache here?
				// If the cache is unlimited then we should.
				// Otherwise we should only add to the cache if it's not full.
				// The cache should generally be reserved for items that are explicitly fetched,
				// and we don't want to crowd them out during enumerations.
				
				if (unlimitedObjectCacheLimit || [connection->objectCache count] < connection->objectCacheLimit)
				{
					if (object)
						[connection->objectCache setObject:object forKey:cacheKey];
				}
			}
			
			id metadata = [connection->metadataCache objectForKey:cacheKey];
			if (metadata)
			{
				if (metadata == [YapNull null])
					metadata = nil;
			}
			else
			{
				const void *mBlob = sqlite3_column_blob(statement, column_idx_metadata);
				int mBlobSize = sqlite3_column_bytes(statement, column_idx_metadata);
				
				if (mBlobSize > 0)
				{
					// Performance tuning:
					// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
					
					NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
					metadata = connection->database->metadataDeserializer(collection, key, mData);
				}
				
				// Cache considerations:
				// Do we want to add the objects/metadata to the cache here?
				// If the cache is unlimited then we should.
				// Otherwise we should only add to the cache if it's not full.
				// The cache should generally be reserved for items that are explicitly fetched,
				// and we don't want to crowd them out during enumerations.
				
				if (unlimitedMetadataCacheLimit ||
				    [connection->metadataCache count] < connection->metadataCacheLimit)
				{
					if (metadata)
						[connection->metadataCache setObject:metadata forKey:cacheKey];
					else
						[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
				}
			}
			
			block(rowid, key, object, metadata, &stop);
			
			if (stop || mutation.isMutated) break;
		}
	}
	
	if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
	FreeYapDatabaseString(&_collection);
	
	if (!stop && mutation.isMutated)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fast enumeration over select rows in the database.
 *
 * This uses a "SELECT key, data, metadata from database WHERE collection = ?" operation,
 * and then steps over the results, deserializing each object & metadata, and then invoking the given block handler.
 *
 * If you only need to enumerate over certain rows (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those rows you're not interested in.
**/
- (void)_enumerateRowsInCollections:(NSArray *)collections usingBlock:
                (void (^)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
{
	[self _enumerateRowsInCollections:collections usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over rows in the database for which you're interested in.
 * The filter block allows you to decide which rows you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object & metadata.
**/
- (void)_enumerateRowsInCollections:(NSArray *)collections
     usingBlock:(void (^)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
     withFilter:(BOOL (^)(int64_t rowid, NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	if ([collections count] == 0) return;
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateRowsInCollectionStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);
	
	// SELECT "rowid", "key", "data", "metadata" FROM "database2" WHERE "collection" = ?;
	
	int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
	int const column_idx_key      = SQLITE_COLUMN_START + 1;
	int const column_idx_data     = SQLITE_COLUMN_START + 2;
	int const column_idx_metadata = SQLITE_COLUMN_START + 3;
	int const bind_idx_collection = SQLITE_BIND_START;
	
	for (NSString *collection in collections)
	{
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
		
		int status;
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
			int textSize = sqlite3_column_bytes(statement, column_idx_key);
			
			NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, collection, key);
			if (invokeBlock)
			{
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				id object = [connection->objectCache objectForKey:cacheKey];
				if (object == nil)
				{
					const void *oBlob = sqlite3_column_blob(statement, column_idx_data);
					int oBlobSize = sqlite3_column_bytes(statement, column_idx_data);
					
					// Performance tuning:
					// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
					
					NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
					object = connection->database->objectDeserializer(collection, key, oData);
					
					// Cache considerations:
					// Do we want to add the objects/metadata to the cache here?
					// If the cache is unlimited then we should.
					// Otherwise we should only add to the cache if it's not full.
					// The cache should generally be reserved for items that are explicitly fetched,
					// and we don't want to crowd them out during enumerations.
					
					if (unlimitedObjectCacheLimit ||
					    [connection->objectCache count] < connection->objectCacheLimit)
					{
						if (object)
							[connection->objectCache setObject:object forKey:cacheKey];
					}
				}
				
				id metadata = [connection->metadataCache objectForKey:cacheKey];
				if (metadata)
				{
					if (metadata == [YapNull null])
						metadata = nil;
				}
				else
				{
					const void *mBlob = sqlite3_column_blob(statement, column_idx_metadata);
					int mBlobSize = sqlite3_column_bytes(statement, column_idx_metadata);
					
					if (mBlobSize > 0)
					{
						// Performance tuning:
						// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
						
						NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
						metadata = connection->database->metadataDeserializer(collection, key, mData);
					}
					
					// Cache considerations:
					// Do we want to add the objects/metadata to the cache here?
					// If the cache is unlimited then we should.
					// Otherwise we should only add to the cache if it's not full.
					// The cache should generally be reserved for items that are explicitly fetched,
					// and we don't want to crowd them out during enumerations.
					
					if (unlimitedMetadataCacheLimit ||
					    [connection->metadataCache count] < connection->metadataCacheLimit)
					{
						if (metadata)
							[connection->metadataCache setObject:metadata forKey:cacheKey];
						else
							[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
					}
				}
				
				block(rowid, collection, key, object, metadata, &stop);
				
				if (stop || mutation.isMutated) break;
			}
		}
		
		if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement); // ok: within loop
		sqlite3_reset(statement);          // ok: within loop
		FreeYapDatabaseString(&_collection);
		
		if (!stop && mutation.isMutated)
		{
			@throw [self mutationDuringEnumerationException];
		}
		
		if (stop)
		{
			break;
		}
	
	} // end for (NSString *collection in collections)
	
	sqlite_enum_reset(statement, needsFinalize);
}

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
- (void)_enumerateRowsInAllCollectionsUsingBlock:
                (void (^)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
{
	[self _enumerateRowsInAllCollectionsUsingBlock:block withFilter:NULL];
}

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
- (void)_enumerateRowsInAllCollectionsUsingBlock:
                (void (^)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
     withFilter:(BOOL (^)(int64_t rowid, NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [connection enumerateRowsInAllCollectionsStatement:&needsFinalize];
	if (statement == NULL) return;
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "collection", "key", "data", "metadata" FROM "database2" ORDER BY \"collection\" ASC;";
	
	int const column_idx_rowid      = SQLITE_COLUMN_START + 0;
	int const column_idx_collection = SQLITE_COLUMN_START + 1;
	int const column_idx_key        = SQLITE_COLUMN_START + 2;
	int const column_idx_data       = SQLITE_COLUMN_START + 3;
	int const column_idx_metadata   = SQLITE_COLUMN_START + 4;
	
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		const unsigned char *text1 = sqlite3_column_text(statement, column_idx_collection);
		int textSize1 = sqlite3_column_bytes(statement, column_idx_collection);
		
		const unsigned char *text2 = sqlite3_column_text(statement, column_idx_key);
		int textSize2 = sqlite3_column_bytes(statement, column_idx_key);
		
		NSString *collection, *key;
		
		collection = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
		key        = [[NSString alloc] initWithBytes:text2 length:textSize2 encoding:NSUTF8StringEncoding];
		
		BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, collection, key);
		if (invokeBlock)
		{
			YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
			
			id object = [connection->objectCache objectForKey:cacheKey];
			if (object == nil)
			{
				const void *oBlob = sqlite3_column_blob(statement, column_idx_data);
				int oBlobSize = sqlite3_column_bytes(statement, column_idx_data);
				
				NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
				object = connection->database->objectDeserializer(collection, key, oData);
				
				if (unlimitedObjectCacheLimit || [connection->objectCache count] < connection->objectCacheLimit)
				{
					if (object)
						[connection->objectCache setObject:object forKey:cacheKey];
				}
			}
			
			id metadata = [connection->metadataCache objectForKey:cacheKey];
			if (metadata)
			{
				if (metadata == [YapNull null])
					metadata = nil;
			}
			else
			{
				const void *mBlob = sqlite3_column_blob(statement, column_idx_metadata);
				int mBlobSize = sqlite3_column_bytes(statement, column_idx_metadata);
				
				if (mBlobSize > 0)
				{
					NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
					metadata = connection->database->metadataDeserializer(collection, key, mData);
				}
				
				if (unlimitedMetadataCacheLimit ||
				    [connection->metadataCache count] < connection->metadataCacheLimit)
				{
					if (metadata)
						[connection->metadataCache setObject:metadata forKey:cacheKey];
					else
						[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
				}
			}
			
			block(rowid, collection, key, object, metadata, &stop);
			
			if (stop || mutation.isMutated) break;
		}
	}
	
	if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
	
	if (!stop && mutation.isMutated)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fetches the rowid for each given key.
 *
 * The rowids are delivered unordered, which is why the block has a keyIndex parameter.
 * If a key doesn't exist in the database, the block is never invoked for its keyIndex.
**/
- (void)_enumerateRowidsForKeys:(NSArray *)keys
                   inCollection:(NSString *)collection
            unorderedUsingBlock:(void (^)(NSUInteger keyIndex, int64_t rowid, BOOL *stop))block
{
	if (block == NULL) return;
	if (keys.count == 0) return;
	if (collection == nil) collection = @"";
	
	if (keys.count == 1)
	{
		int64_t rowid = 0;
		if ([self getRowid:&rowid forKey:[keys firstObject] inCollection:collection])
		{
			BOOL stop = NO;
			block(0, rowid, &stop);
		}
		
		return;
	}
	
	YapMutationStackItem_Bool *mutation = [connection->mutationStack push]; // mutation during enumeration protection
	BOOL stop = NO;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	
	NSMutableDictionary *keyIndexDict = nil;
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(connection->db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	NSUInteger offset = 0;
	
	do
	{
		// Determine how many parameters to use in the query
		
		NSUInteger left = keys.count - offset;
		NSUInteger numKeyParams = MIN(left, (maxHostParams-1)); // minus 1 for collection param
		
		// Create the SQL query:
		//
		// SELECT "rowid", "key" FROM "database2" WHERE "collection" = ? AND key IN (?, ?, ...);
		
		int const column_idx_rowid = SQLITE_COLUMN_START + 0;
		int const column_idx_key   = SQLITE_COLUMN_START + 1;
		
		NSUInteger capacity = 80 + (numKeyParams * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendString:@"SELECT \"rowid\", \"key\" FROM \"database2\""];
		[query appendString:@" WHERE \"collection\" = ? AND \"key\" IN ("];
		
		NSUInteger i;
		for (i = 0; i < numKeyParams; i++)
		{
			if (i == 0)
				[query appendString:@"?"];
			else
				[query appendString:@", ?"];
		}
		
		[query appendString:@");"];
		
		sqlite3_stmt *statement;
		
		int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'objectsForKeys' statement: %d %s",
						status, sqlite3_errmsg(connection->db));
			break; // Break from do/while. Still need to free _collection.
		}
		
		// Bind parameters.
		// And move objects from the missingIndexes array into keyIndexDict.
		
		if (keyIndexDict)
			keyIndexDict = [NSMutableDictionary dictionaryWithCapacity:numKeyParams];
		else
			[keyIndexDict removeAllObjects];
		
		sqlite3_bind_text(statement, SQLITE_BIND_START, _collection.str, _collection.length, SQLITE_STATIC);
		
		for (i = 0; i < numKeyParams; i++)
		{
			NSUInteger keyIndex = i + offset;
			NSString *key = keys[keyIndex];
			
			[keyIndexDict setObject:@(keyIndex) forKey:key];
			
			sqlite3_bind_text(statement, (int)(SQLITE_BIND_START + 1 + i), [key UTF8String], -1, SQLITE_TRANSIENT);
		}
		
		// Execute the query and step over the results
		
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
			int textSize = sqlite3_column_bytes(statement, column_idx_key);
			
			NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			NSUInteger keyIndex = [[keyIndexDict objectForKey:key] unsignedIntegerValue];
			
			// Note: We already checked the cache (above),
			// so we already know this item is not in the cache.
			
			block(keyIndex, rowid, &stop);
			
			if (stop || mutation.isMutated) break;
		}
		
		if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
		
		if (stop) {
			FreeYapDatabaseString(&_collection);
			return;
		}
		if (mutation.isMutated) {
			FreeYapDatabaseString(&_collection);
			@throw [self mutationDuringEnumerationException];
			return;
		}
		
		offset += numKeyParams;
		
	} while (offset < keys.count);
	
	FreeYapDatabaseString(&_collection);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extensions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns an extension transaction corresponding to the extension type registered under the given name.
 * If the extension has not yet been prepared, it is done so automatically.
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
- (id)extension:(NSString *)extensionName
{
	// This method is PUBLIC
	
	if (extensionsReady)
		return [extensions objectForKey:extensionName];
	
	if (extensions == nil)
		extensions = [[NSMutableDictionary alloc] init];
	
	YapDatabaseExtensionTransaction *extTransaction = [extensions objectForKey:extensionName];
	if (extTransaction == nil)
	{
		YapDatabaseExtensionConnection *extConnection = [connection extension:extensionName];
		if (extConnection)
		{
			if (isReadWriteTransaction)
				extTransaction = [extConnection newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)self];
			else
				extTransaction = [extConnection newReadTransaction:self];
			
			if ([extTransaction prepareIfNeeded])
			{
				[extensions setObject:extTransaction forKey:extensionName];
			}
			else
			{
				extTransaction = nil;
			}
		}
	}
	
	return extTransaction;
}

- (id)ext:(NSString *)extensionName
{
	// This method is PUBLIC
	
	// The "+ (void)load" method swizzles the implementation of this class
	// to point to the implementation of the extension: method.
	//
	// So the two methods are literally the same thing.
	
	return [self extension:extensionName]; // This method is swizzled !
}

- (void)prepareExtensions
{
	if (extensions == nil)
		extensions = [[NSMutableDictionary alloc] init];
	
	NSDictionary *extConnections = [connection extensions];
	
	[extConnections enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop) {
		
		__unsafe_unretained NSString *extName = key;
		__unsafe_unretained YapDatabaseExtensionConnection *extConnection = obj;
		
		YapDatabaseExtensionTransaction *extTransaction = [extensions objectForKey:extName];
		if (extTransaction == nil)
		{
			if (isReadWriteTransaction)
				extTransaction = [extConnection newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)self];
			else
				extTransaction = [extConnection newReadTransaction:self];
			
			if ([extTransaction prepareIfNeeded])
			{
				[extensions setObject:extTransaction forKey:extName];
			}
		}
	}];
	
	if (orderedExtensions == nil)
		orderedExtensions = [[NSMutableArray alloc] initWithCapacity:[extensions count]];
	
	for (NSString *extName in connection->extensionsOrder)
	{
		YapDatabaseExtensionTransaction *extTransaction = [extensions objectForKey:extName];
		if (extTransaction)
		{
			[orderedExtensions addObject:extTransaction];
		}
	}
	
	extensionsReady = YES;
}

- (NSDictionary *)extensions
{
	// This method is INTERNAL
	
	if (!extensionsReady)
	{
		[self prepareExtensions];
	}
	
	return extensions;
}

- (NSArray *)orderedExtensions
{
	// This method is INTERNAL
	
	if (!extensionsReady)
	{
		[self prepareExtensions];
	}
	
	return orderedExtensions;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Memory Tables
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapMemoryTableTransaction *)memoryTableTransaction:(NSString *)tableName
{
	BOOL isYap = [tableName isEqualToString:@"yap"];
	if (isYap && yapMemoryTableTransaction)
		return yapMemoryTableTransaction;
	
	YapMemoryTableTransaction *memoryTableTransaction = nil;
		
	YapMemoryTable *table = [[connection registeredMemoryTables] objectForKey:tableName];
	if (table)
	{
		uint64_t snapshot = [connection snapshot];
		
		if (isReadWriteTransaction)
			memoryTableTransaction = [table newReadWriteTransactionWithSnapshot:(snapshot + 1)];
		else
			memoryTableTransaction = [table newReadTransactionWithSnapshot:snapshot];
	}
	
	if (isYap) {
		yapMemoryTableTransaction = memoryTableTransaction;
	}
	return memoryTableTransaction;
}

/**
 * The system automatically creates a special YapMemoryTable that's available for any extension.
 * This memoryTable is registered under the reserved name @"yap".
 *
 * The yapMemoryTableTransaction uses a keyClass of [YapCollectionKey class].
 * Thus, when using it, you must pass a YapCollectionKey, where collectionKey.collection == extensionName.
 * 
 * This memory table is an in-memory alternative to using the yap sqlite table.
**/
- (YapMemoryTableTransaction *)yapMemoryTableTransaction
{
	return [self memoryTableTransaction:@"yap"];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Yap2 Table
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)getBoolValue:(BOOL *)valuePtr forKey:(NSString *)key extension:(NSString *)extensionName
{
	int intValue = 0;
	BOOL result = [self getIntValue:&intValue forKey:key extension:extensionName];
	
	if (valuePtr) *valuePtr = (intValue == 0) ? NO : YES;
	return result;
}

- (BOOL)getIntValue:(int *)valuePtr forKey:(NSString *)key extension:(NSString *)extensionName
{
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [connection yapGetDataForKeyStatement];
	if (statement == NULL) {
		if (valuePtr) *valuePtr = 0;
		return NO;
	}
	
	BOOL result = NO;
	int value = 0;
	
	// SELECT "data" FROM "yap2" WHERE "extension" = ? AND "key" = ? ;
	
	int const column_idx_data    = SQLITE_COLUMN_START;
	int const bind_idx_extension = SQLITE_BIND_START + 0;
	int const bind_idx_key       = SQLITE_BIND_START + 1;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, bind_idx_extension, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = YES;
		value = sqlite3_column_int(statement, column_idx_data);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'yapGetDataForKeyStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	
	if (valuePtr) *valuePtr = value;
	return result;
}

- (BOOL)getDoubleValue:(double *)valuePtr forKey:(NSString *)key extension:(NSString *)extensionName
{
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [connection yapGetDataForKeyStatement];
	if (statement == NULL) {
		if (valuePtr) *valuePtr = 0.0;
		return NO;
	}
	
	BOOL result = NO;
	double value = 0.0;
	
	// SELECT "data" FROM "yap2" WHERE "extension" = ? AND "key" = ? ;
	
	int const column_idx_data    = SQLITE_COLUMN_START;
	int const bind_idx_extension = SQLITE_BIND_START + 0;
	int const bind_idx_key       = SQLITE_BIND_START + 1;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, bind_idx_extension, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = YES;
		value = sqlite3_column_double(statement, column_idx_data);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'yapGetDataForKeyStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	
	if (valuePtr) *valuePtr = value;
	return result;
}

- (NSString *)stringValueForKey:(NSString *)key extension:(NSString *)extensionName
{
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [connection yapGetDataForKeyStatement];
	if (statement == NULL) return nil;
	
	NSString *value = nil;
	
	// SELECT "data" FROM "yap2" WHERE "extension" = ? AND "key" = ? ;
	
	int const column_idx_data    = SQLITE_COLUMN_START;
	int const bind_idx_extension = SQLITE_BIND_START + 0;
	int const bind_idx_key       = SQLITE_BIND_START + 1;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, bind_idx_extension, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(statement, column_idx_data);
		int textSize = sqlite3_column_bytes(statement, column_idx_data);
		
		value = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'yapGetDataForKeyStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	
	return value;
}

- (NSData *)dataValueForKey:(NSString *)key extension:(NSString *)extensionName
{
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [connection yapGetDataForKeyStatement];
	if (statement == NULL) return nil;
	
	NSData *value = nil;
	
	// SELECT "data" FROM "yap2" WHERE "extension" = ? AND "key" = ? ;
	
	int const column_idx_data    = SQLITE_COLUMN_START;
	int const bind_idx_extension = SQLITE_BIND_START + 0;
	int const bind_idx_key       = SQLITE_BIND_START + 1;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, bind_idx_extension, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const void *blob = sqlite3_column_blob(statement, column_idx_data);
		int blobSize = sqlite3_column_bytes(statement, column_idx_data);
		
		value = [[NSData alloc] initWithBytes:(void *)blob length:blobSize];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'yapGetDataForKeyStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	
	return value;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Exceptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSException *)mutationDuringEnumerationException
{
	NSString *reason = [NSString stringWithFormat:
	    @"Database <%@: %p> was mutated while being enumerated.", NSStringFromClass([self class]), self];
	
	NSDictionary *userInfo = @{ NSLocalizedRecoverySuggestionErrorKey:
	    @"If you modify the database during enumeration"
		@" you MUST set the 'stop' parameter of the enumeration block to YES (*stop = YES;)."};
	
	return [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseReadWriteTransaction

#pragma mark Transaction Control

/**
 * Under normal circumstances, when a read-write transaction block completes,
 * the changes are automatically committed. If, however, something goes wrong and
 * you'd like to abort and discard all changes made within the transaction,
 * then invoke this method.
 *
 * You should generally return (exit the transaction block) after invoking this method.
 * Any changes made within the the transaction before and after invoking this method will be discarded.
 *
 * Invoking this method from within a read-only transaction does nothing.
**/
- (void)rollback
{
	rollback = YES;
}

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
@synthesize yapDatabaseModifiedNotificationCustomObject = customObjectForNotification;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Object & Metadata
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
{
	[self setObject:object forKey:key inCollection:collection withMetadata:nil
                                                          serializedObject:nil
	                                                    serializedMetadata:nil];
}

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
- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection withMetadata:(id)metadata
{
	[self setObject:object forKey:key inCollection:collection withMetadata:metadata
                                                          serializedObject:nil
	                                                    serializedMetadata:nil];
}

/**
 * Sets the object & metadata for the given key/collection.
 * 
 * This method allows for a bit of optimization if you happen to already have a serialized version of
 * the object and/or metadata. For example, if you downloaded an object in serialized form,
 * and you still have the raw NSData, then you can use this method to skip the serialization step
 * when storing the object to the database.
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
- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
                                                    withMetadata:(id)metadata
                                                serializedObject:(NSData *)preSerializedObject
                                              serializedMetadata:(NSData *)preSerializedMetadata
{
	if (object == nil)
	{
		[self removeObjectForKey:key inCollection:collection];
		return;
	}
	
	if (key == nil) return;
	if (collection == nil) collection = @"";
	
	if (connection->database->objectPreSanitizer)
	{
		object = connection->database->objectPreSanitizer(collection, key, object);
		if (object == nil)
		{
			YDBLogWarn(@"The objectPreSanitizer returned nil for collection(%@) key(%@)", collection, key);
			
			[self removeObjectForKey:key inCollection:collection];
			return;
		}
	}
	if (metadata && connection->database->metadataPreSanitizer)
	{
		metadata = connection->database->metadataPreSanitizer(collection, key, metadata);
		if (metadata == nil)
		{
			YDBLogWarn(@"The metadataPresanitizer returned nil for collection(%@) key(%@)", collection, key);
		}
	}
	
	// To use SQLITE_STATIC on our data, we use the objc_precise_lifetime attribute.
	// This ensures the data isn't released until it goes out of scope.
	
	__attribute__((objc_precise_lifetime)) NSData *serializedObject = nil;
	if (preSerializedObject)
		serializedObject = preSerializedObject;
	else
		serializedObject = connection->database->objectSerializer(collection, key, object);
	
	__attribute__((objc_precise_lifetime)) NSData *serializedMetadata = nil;
	if (metadata)
	{
		if (preSerializedMetadata)
			serializedMetadata = preSerializedMetadata;
		else
			serializedMetadata = connection->database->metadataSerializer(collection, key, metadata);
	}
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	// Fetch rowid for <collection, key> tuple
	
	int64_t rowid = 0;
	BOOL found = [self getRowid:&rowid forCollectionKey:cacheKey];
    
	for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
	{
		if (found)
			[extTransaction willUpdateObject:object
			                forCollectionKey:cacheKey
			                    withMetadata:metadata
			                           rowid:rowid];
		else
			[extTransaction willInsertObject:object
			                forCollectionKey:cacheKey
			                    withMetadata:metadata];
	}
	
	BOOL set = YES;
	
	if (found) // update data for key
	{
		sqlite3_stmt *statement = [connection updateAllForRowidStatement];
		if (statement == NULL) {
			return;
		}
		
		// UPDATE "database2" SET "data" = ?, "metadata" = ? WHERE "rowid" = ?;
		
		int const bind_idx_data     = SQLITE_BIND_START + 0;
		int const bind_idx_metadata = SQLITE_BIND_START + 1;
		int const bind_idx_rowid    = SQLITE_BIND_START + 2;
		
		sqlite3_bind_blob(statement, bind_idx_data,
		                  serializedObject.bytes, (int)serializedObject.length, SQLITE_STATIC);
		
		sqlite3_bind_blob(statement, bind_idx_metadata,
		                  serializedMetadata.bytes, (int)serializedMetadata.length, SQLITE_STATIC);
		
		sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
		
		int status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"Error executing 'updateAllForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
			set = NO;
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	else // insert data for key
	{
		sqlite3_stmt *statement = [connection insertForRowidStatement];
		if (statement == NULL) {
			return;
		}
		
		// INSERT INTO "database2" ("collection", "key", "data", "metadata") VALUES (?, ?, ?, ?);
		
		int const bind_idx_collection = SQLITE_BIND_START + 0;
		int const bind_idx_key        = SQLITE_BIND_START + 1;
		int const bind_idx_data       = SQLITE_BIND_START + 2;
		int const bind_idx_metadata   = SQLITE_BIND_START + 3;
		
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
		
		YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
		sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
		
		sqlite3_bind_blob(statement, bind_idx_data,
		                  serializedObject.bytes, (int)serializedObject.length, SQLITE_STATIC);
		
		sqlite3_bind_blob(statement, bind_idx_metadata,
		                  serializedMetadata.bytes, (int)serializedMetadata.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_DONE)
		{
			rowid = sqlite3_last_insert_rowid(connection->db);
			
			[connection->keyCache setObject:cacheKey forKey:@(rowid)];
		}
		else
		{
			YDBLogError(@"Error executing 'insertForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
			set = NO;
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_collection);
		FreeYapDatabaseString(&_key);
	}
	
	if (!set) return;
	
	connection->hasDiskChanges = YES;
	[connection->mutationStack markAsMutated];  // mutation during enumeration protection
	
	id _object = nil;
	if (connection->objectPolicy == YapDatabasePolicyContainment) {
		_object = [YapNull null];
	}
	else if (connection->objectPolicy == YapDatabasePolicyShare) {
		_object = object;
	}
	else // if (connection->objectPolicy == YapDatabasePolicyCopy)
	{
		if ([object conformsToProtocol:@protocol(NSCopying)])
			_object = [object copy];
		else
			_object = [YapNull null];
	}
	
	[connection->objectCache setObject:object forKey:cacheKey];
	[connection->objectChanges setObject:_object forKey:cacheKey];
	
	if (metadata)
	{
		id _metadata = nil;
		if (connection->metadataPolicy == YapDatabasePolicyContainment) {
			_metadata = [YapNull null];
		}
		else if (connection->metadataPolicy == YapDatabasePolicyShare) {
			_metadata = metadata;
		}
		else // if (connection->metadataPolicy = YapDatabasePolicyCopy)
		{
			if ([metadata conformsToProtocol:@protocol(NSCopying)])
				_metadata = [metadata copy];
			else
				_metadata = [YapNull null];
		}
		
		[connection->metadataCache setObject:metadata forKey:cacheKey];
		[connection->metadataChanges setObject:_metadata forKey:cacheKey];
	}
	else
	{
		[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
		[connection->metadataChanges setObject:[YapNull null] forKey:cacheKey];
	}
	
	for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
	{
		if (found)
			[extTransaction didUpdateObject:object
			               forCollectionKey:cacheKey
			                   withMetadata:metadata
			                          rowid:rowid];
		else
			[extTransaction didInsertObject:object
			               forCollectionKey:cacheKey
			                   withMetadata:metadata
			                          rowid:rowid];
	}
	
	if (connection->database->objectPostSanitizer)
	{
		connection->database->objectPostSanitizer(collection, key, object);
	}
	if (metadata && connection->database->metadataPostSanitizer)
	{
		connection->database->metadataPostSanitizer(collection, key, metadata);
	}
}

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
- (void)replaceObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
{
	int64_t rowid = 0;
	if ([self getRowid:&rowid forKey:key inCollection:collection])
	{
		[self replaceObject:object forKey:key inCollection:collection withRowid:rowid serializedObject:nil];
	}
}

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
- (void)replaceObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
                                                withSerializedObject:(NSData *)preSerializedObject
{
	int64_t rowid = 0;
	if ([self getRowid:&rowid forKey:key inCollection:collection])
	{
		[self replaceObject:object
		             forKey:key
		       inCollection:collection
		          withRowid:rowid
		   serializedObject:preSerializedObject];
	}
}

/**
 * Internal replaceObject method that takes a rowid.
**/
- (void)replaceObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
                                                           withRowid:(int64_t)rowid
                                                    serializedObject:(NSData *)preSerializedObject
{
	if (object == nil)
	{
		[self removeObjectForKey:key inCollection:collection withRowid:rowid];
		return;
	}
	
	NSAssert(key != nil, @"Internal error");
	if (collection == nil) collection = @"";
	
	if (connection->database->objectPreSanitizer)
	{
		object = connection->database->objectPreSanitizer(collection, key, object);
		if (object == nil)
		{
			YDBLogWarn(@"The objectPreSanitizer returned nil for collection(%@) key(%@)", collection, key);
			
			[self removeObjectForKey:key inCollection:collection withRowid:rowid];
			return;
		}
	}
	
	// To use SQLITE_STATIC on our data blob, we use the objc_precise_lifetime attribute.
	// This ensures the data isn't released until it goes out of scope.
	
	__attribute__((objc_precise_lifetime)) NSData *serializedObject = nil;
	if (preSerializedObject)
		serializedObject = preSerializedObject;
	else
		serializedObject = connection->database->objectSerializer(collection, key, object);
	
	sqlite3_stmt *statement = [connection updateObjectForRowidStatement];
	if (statement == NULL) return;
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	// Be sure to execute pre-hook BEFORE we bind query parameters.
	
	for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
	{
		[extTransaction willReplaceObject:object forCollectionKey:cacheKey withRowid:rowid];
	}
	
	// UPDATE "database2" SET "data" = ? WHERE "rowid" = ?;
	
	int const bind_idx_data  = SQLITE_BIND_START + 0;
	int const bind_idx_rowid = SQLITE_BIND_START + 1;
	
	sqlite3_bind_blob(statement, bind_idx_data, serializedObject.bytes, (int)serializedObject.length, SQLITE_STATIC);
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	BOOL updated = YES;
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'updateObjectForRowidStatement': %d %s",
		                                                    status, sqlite3_errmsg(connection->db));
		updated = NO;
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (!updated) return;
	
	connection->hasDiskChanges = YES;
	[connection->mutationStack markAsMutated];  // mutation during enumeration protection
	
	id _object = nil;
	if (connection->objectPolicy == YapDatabasePolicyContainment) {
		_object = [YapNull null];
	}
	else if (connection->objectPolicy == YapDatabasePolicyShare) {
		_object = object;
	}
	else // if (connection->objectPolicy = YapDatabasePolicyCopy)
	{
		if ([object conformsToProtocol:@protocol(NSCopying)])
			_object = [object copy];
		else
			_object = [YapNull null];
	}
	
	[connection->objectCache setObject:object forKey:cacheKey];
	[connection->objectChanges setObject:_object forKey:cacheKey];
	
	for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
	{
		[extTransaction didReplaceObject:object forCollectionKey:cacheKey withRowid:rowid];
	}
	
	if (connection->database->objectPostSanitizer)
	{
		connection->database->objectPostSanitizer(collection, key, object);
	}
}

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
- (void)replaceMetadata:(id)metadata forKey:(NSString *)key inCollection:(NSString *)collection
{
	int64_t rowid = 0;
	if ([self getRowid:&rowid forKey:key inCollection:collection])
	{
		[self replaceMetadata:metadata forKey:key inCollection:collection withRowid:rowid serializedMetadata:nil];
	}
}

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
- (void)replaceMetadata:(id)metadata forKey:(NSString *)key inCollection:(NSString *)collection
                                                  withSerializedMetadata:(NSData *)preSerializedMetadata
{
	int64_t rowid = 0;
	if ([self getRowid:&rowid forKey:key inCollection:collection])
	{
		[self replaceMetadata:metadata
		               forKey:key
		         inCollection:collection
		            withRowid:rowid
		   serializedMetadata:preSerializedMetadata];
	}
}

/**
 * Internal replaceMetadata method that takes a rowid.
**/
- (void)replaceMetadata:(id)metadata
                 forKey:(NSString *)key
           inCollection:(NSString *)collection
              withRowid:(int64_t)rowid
     serializedMetadata:(NSData *)preSerializedMetadata
{
	NSAssert(key != nil, @"Internal error");
	if (collection == nil) collection = @"";
	
	if (metadata && connection->database->metadataPreSanitizer)
	{
		metadata = connection->database->metadataPreSanitizer(collection, key, metadata);
		if (metadata == nil)
		{
			YDBLogWarn(@"The metadataPreSanitizer returned nil for collection(%@) key(%@)", collection, key);
		}
	}
	
	// To use SQLITE_STATIC on our data blob, we use the objc_precise_lifetime attribute.
	// This ensures the data isn't released until it goes out of scope.
	
	__attribute__((objc_precise_lifetime)) NSData *serializedMetadata = nil;
	if (metadata)
	{
		if (preSerializedMetadata)
			serializedMetadata = preSerializedMetadata;
		else
			serializedMetadata = connection->database->metadataSerializer(collection, key, metadata);
	}
	
	sqlite3_stmt *statement = [connection updateMetadataForRowidStatement];
	if (statement == NULL) return;
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	// Be sure to execute pre-hook BEFORE we bind query parameters.
	
	for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
	{
		[extTransaction willReplaceMetadata:metadata forCollectionKey:cacheKey withRowid:rowid];
	}
	
	// UPDATE "database2" SET "metadata" = ? WHERE "rowid" = ?;
	
	int const bind_idx_metadata = SQLITE_BIND_START + 0;
	int const bind_idx_rowid    = SQLITE_BIND_START + 1;
	
	sqlite3_bind_blob(statement, bind_idx_metadata,
	                  serializedMetadata.bytes, (int)serializedMetadata.length, SQLITE_STATIC);
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	BOOL updated = YES;

	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'updateMetadataForRowidStatement': %d %s",
		                                                    status, sqlite3_errmsg(connection->db));
		updated = NO;
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (!updated) return;
	
	connection->hasDiskChanges = YES;
	[connection->mutationStack markAsMutated];  // mutation during enumeration protection
	
	if (metadata)
	{
		id _metadata = nil;
		if (connection->metadataPolicy == YapDatabasePolicyContainment) {
			_metadata = [YapNull null];
		}
		else if (connection->metadataPolicy == YapDatabasePolicyShare) {
			_metadata = metadata;
		}
		else // if (connection->metadataPolicy = YapDatabasePolicyCopy)
		{
			if ([metadata conformsToProtocol:@protocol(NSCopying)])
				_metadata = [metadata copy];
			else
				_metadata = [YapNull null];
		}
		
		[connection->metadataCache setObject:metadata forKey:cacheKey];
		[connection->metadataChanges setObject:_metadata forKey:cacheKey];
	}
	else
	{
		[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
		[connection->metadataChanges setObject:[YapNull null] forKey:cacheKey];
	}
	
	for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
	{
		[extTransaction didReplaceMetadata:metadata forCollectionKey:cacheKey withRowid:rowid];
	}
	
	if (metadata && connection->database->metadataPostSanitizer)
	{
		connection->database->metadataPostSanitizer(collection, key, metadata);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Touch
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)touchObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (collection == nil) collection = @"";
	
	int64_t rowid = 0;
	if (![self getRowid:&rowid forKey:key inCollection:collection]) return;
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	if ([connection->objectChanges objectForKey:cacheKey] == nil)
		[connection->objectChanges setObject:[YapTouch touch] forKey:cacheKey];
	
	for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
	{
		[extTransaction didTouchObjectForCollectionKey:cacheKey withRowid:rowid];
	}
}

- (void)touchMetadataForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (collection == nil) collection = @"";
	
	int64_t rowid = 0;
	if (![self getRowid:&rowid forKey:key inCollection:collection]) return;
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	if ([connection->metadataChanges objectForKey:cacheKey] == nil)
		[connection->metadataChanges setObject:[YapTouch touch] forKey:cacheKey];
	
	for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
	{
		[extTransaction didTouchMetadataForCollectionKey:cacheKey withRowid:rowid];
	}
}

- (void)touchRowForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (collection == nil) collection = @"";
	
	int64_t rowid = 0;
	if (![self getRowid:&rowid forKey:key inCollection:collection]) return;
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	if ([connection->objectChanges objectForKey:cacheKey] == nil)
		[connection->objectChanges setObject:[YapTouch touch] forKey:cacheKey];
	
	if ([connection->metadataChanges objectForKey:cacheKey] == nil)
		[connection->metadataChanges setObject:[YapTouch touch] forKey:cacheKey];
	
	for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
	{
		[extTransaction didTouchRowForCollectionKey:cacheKey withRowid:rowid];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Remove
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)removeObjectForCollectionKey:(YapCollectionKey *)cacheKey withRowid:(int64_t)rowid;
{
	if (cacheKey == nil) return;
	
	sqlite3_stmt *statement = [connection removeForRowidStatement];
	if (statement == NULL) return;
	
	// Issue #215
	//
	// Be sure to execute pre-hook BEFORE we bind query parameters.
	// Because if the pre-hook deletes any rows in the database, this method would be called again,
	// and our binding would get erased.
	
	for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
	{
		[extTransaction willRemoveObjectForCollectionKey:cacheKey withRowid:rowid];
	}
	
	// DELETE FROM "database" WHERE "rowid" = ?;
	
	int const bind_idx_rowid = SQLITE_BIND_START;
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	BOOL removed = YES;

	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
		removed = NO;
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (!removed) return;
	
	connection->hasDiskChanges = YES;
	[connection->mutationStack markAsMutated];  // mutation during enumeration protection
	
	[connection->keyCache removeObjectForKey:@(rowid)];
	[connection->objectCache removeObjectForKey:cacheKey];
	[connection->metadataCache removeObjectForKey:cacheKey];
	
	[connection->objectChanges removeObjectForKey:cacheKey];
	[connection->metadataChanges removeObjectForKey:cacheKey];
	[connection->removedKeys addObject:cacheKey];
	[connection->removedRowids addObject:@(rowid)];
	
	for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
	{
		[extTransaction didRemoveObjectForCollectionKey:cacheKey withRowid:rowid];
	}
}

- (void)removeObjectForKey:(NSString *)key inCollection:(NSString *)collection withRowid:(int64_t)rowid
{
	YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	[self removeObjectForCollectionKey:ck withRowid:rowid];
}

- (void)removeObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
	int64_t rowid = 0;
	if ([self getRowid:&rowid forKey:key inCollection:collection])
	{
		YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		[self removeObjectForCollectionKey:ck withRowid:rowid];
	}
}

- (void)removeObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection
{
	NSUInteger keysCount = [keys count];
	
	if (keysCount == 0) return;
	if (keysCount == 1) {
		[self removeObjectForKey:[keys objectAtIndex:0] inCollection:collection];
		return;
	}
	
	if (collection == nil)
		collection = @"";
	else
		collection = [collection copy]; // mutable string protection
	
	NSMutableArray *foundKeys = nil;
	NSMutableArray *foundRowids = nil;
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(connection->db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	// Loop over the keys, and remove them in big batches.
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	
	NSUInteger keysIndex = 0;
	do
	{
		NSUInteger left = keysCount - keysIndex;
		NSUInteger numKeyParams = MIN(left, (maxHostParams-1)); // minus 1 for collectionParam
		
		if (foundKeys == nil)
		{
			foundKeys   = [NSMutableArray arrayWithCapacity:numKeyParams];
			foundRowids = [NSMutableArray arrayWithCapacity:numKeyParams];
		}
		else
		{
			[foundKeys removeAllObjects];
			[foundRowids removeAllObjects];
		}
		
		// Find rowids for keys
		
		if (YES)
		{
			// SELECT "rowid", "key" FROM "database2" WHERE "collection" = ? AND "key" IN (?, ?, ...);
			
			int const column_idx_rowid = SQLITE_COLUMN_START + 0;
			int const column_idx_key   = SQLITE_COLUMN_START + 1;
			
			NSUInteger capacity = 100 + (numKeyParams * 3);
			NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
			
			[query appendString:
			    @"SELECT \"rowid\", \"key\" FROM \"database2\" WHERE \"collection\" = ? AND \"key\" IN ("];
			
			NSUInteger i;
			for (i = 0; i < numKeyParams; i++)
			{
				if (i == 0)
					[query appendString:@"?"];
				else
					[query appendString:@", ?"];
			}
			
			[query appendString:@");"];
			
			sqlite3_stmt *statement;
			
			int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
			if (status != SQLITE_OK)
			{
				YDBLogError(@"Error creating 'removeKeys:inCollection:' statement (A): %d %s",
				                                                              status, sqlite3_errmsg(connection->db));
				FreeYapDatabaseString(&_collection);
				return;
			}
			
			sqlite3_bind_text(statement, SQLITE_BIND_START, _collection.str, _collection.length, SQLITE_STATIC);
			
			for (i = 0; i < numKeyParams; i++)
			{
				NSString *key = [keys objectAtIndex:(keysIndex + i)];
				sqlite3_bind_text(statement, (int)(SQLITE_BIND_START + 1 + i), [key UTF8String], -1, SQLITE_TRANSIENT);
			}
			
			while ((status = sqlite3_step(statement)) == SQLITE_ROW)
			{
				int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
				
				const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
				int textSize = sqlite3_column_bytes(statement, column_idx_key);
				
				NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				
				[foundKeys addObject:key];
				[foundRowids addObject:@(rowid)];
			}
			
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"Error executing 'removeKeys:inCollection:' statement (A): %d %s",
				                                                               status, sqlite3_errmsg(connection->db));
			}
			
			sqlite3_finalize(statement);
			statement = NULL;
		}
		
		// Now remove all the matching rows
		
		NSUInteger foundCount = [foundRowids count];
		
		if (foundCount > 0)
		{
			// DELETE FROM "database2" WHERE "rowid" in (?, ?, ...);
			
			NSUInteger capacity = 50 + (foundCount * 3);
			NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
			
			[query appendString:@"DELETE FROM \"database2\" WHERE \"rowid\" IN ("];
			
			NSUInteger i;
			for (i = 0; i < foundCount; i++)
			{
				if (i == 0)
					[query appendString:@"?"];
				else
					[query appendString:@", ?"];
			}
			
			[query appendString:@");"];
			
			sqlite3_stmt *statement;
			
			int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
			if (status != SQLITE_OK)
			{
				YDBLogError(@"Error creating 'removeKeys:inCollection:' statement (B): %d %s",
							status, sqlite3_errmsg(connection->db));
				return;
			}
			
            for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
            {
                [extTransaction willRemoveObjectsForKeys:foundKeys
                                            inCollection:collection
                                              withRowids:foundRowids];
            }
			
			for (i = 0; i < foundCount; i++)
			{
				int64_t rowid = [[foundRowids objectAtIndex:i] longLongValue];
				
				sqlite3_bind_int64(statement, (int)(SQLITE_BIND_START + i), rowid);
			}
            
			status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"Error executing 'removeKeys:inCollection:' statement (B): %d %s",
							status, sqlite3_errmsg(connection->db));
			}
			
			sqlite3_finalize(statement);
			statement = NULL;
			
			connection->hasDiskChanges = YES;
			[connection->mutationStack markAsMutated];  // mutation during enumeration protection
			
			[connection->keyCache removeObjectsForKeys:foundRowids];
			[connection->removedRowids addObjectsFromArray:foundRowids];
			
			for (NSString *key in foundKeys)
			{
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				[connection->objectCache removeObjectForKey:cacheKey];
				[connection->metadataCache removeObjectForKey:cacheKey];
				
				[connection->objectChanges removeObjectForKey:cacheKey];
				[connection->metadataChanges removeObjectForKey:cacheKey];
				[connection->removedKeys addObject:cacheKey];
			}
			
			for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
			{
				[extTransaction didRemoveObjectsForKeys:foundKeys
				                           inCollection:collection
				                             withRowids:foundRowids];
			}
			
		}
		
		// Move on to the next batch (if there's more)
		
		keysIndex += numKeyParams;
		
	} while (keysIndex < keysCount);
	
	
	FreeYapDatabaseString(&_collection);
}

- (void)removeAllObjectsInCollection:(NSString *)collection
{
	if (collection == nil)
		collection  = @"";
	else
		collection = [collection copy]; // mutable string protection
	
	// Purge the caches and changesets
	
	NSMutableArray *toRemove = [NSMutableArray array];
	
	{ // keyCache
		
		[connection->keyCache enumerateKeysAndObjectsWithBlock:^(id key, id obj, BOOL __unused *stop) {
			
			__unsafe_unretained NSNumber *rowidNumber = (NSNumber *)key;
			__unsafe_unretained YapCollectionKey *collectionKey = (YapCollectionKey *)obj;
			if ([collectionKey.collection isEqualToString:collection])
			{
				[toRemove addObject:rowidNumber];
			}
		}];
		
		[connection->keyCache removeObjectsForKeys:toRemove];
		[toRemove removeAllObjects];
	}
	
	{ // objectCache
		
		[connection->objectCache enumerateKeysWithBlock:^(id key, BOOL __unused *stop) {
			
			__unsafe_unretained YapCollectionKey *cacheKey = (YapCollectionKey *)key;
			if ([cacheKey.collection isEqualToString:collection])
			{
				[toRemove addObject:cacheKey];
			}
		}];
		
		[connection->objectCache removeObjectsForKeys:toRemove];
		[toRemove removeAllObjects];
	}
	
	{ // objectChanges
		
		for (id key in [connection->objectChanges keyEnumerator])
		{
			__unsafe_unretained YapCollectionKey *cacheKey = (YapCollectionKey *)key;
			if ([cacheKey.collection isEqualToString:collection])
			{
				[toRemove addObject:cacheKey];
			}
		}
		
		[connection->objectChanges removeObjectsForKeys:toRemove];
		[toRemove removeAllObjects];
	}
	
	{ // metadataCache
		
		[connection->metadataCache enumerateKeysWithBlock:^(id key, BOOL __unused *stop) {
			
			__unsafe_unretained YapCollectionKey *cacheKey = (YapCollectionKey *)key;
			if ([cacheKey.collection isEqualToString:collection])
			{
				[toRemove addObject:cacheKey];
			}
		}];
		
		[connection->metadataCache removeObjectsForKeys:toRemove];
		[toRemove removeAllObjects];
	}
	
	{ // metadataChanges
		
		for (id key in [connection->metadataChanges keyEnumerator])
		{
			__unsafe_unretained YapCollectionKey *cacheKey = (YapCollectionKey *)key;
			if ([cacheKey.collection isEqualToString:collection])
			{
				[toRemove addObject:cacheKey];
			}
		}
		
		[connection->metadataChanges removeObjectsForKeys:toRemove];
	}
	
	[connection->removedCollections addObject:collection];
	
	// If there are no active extensions we can take a shortcut
	
	if ([[self extensions] count] == 0)
	{
		sqlite3_stmt *statement = [connection removeCollectionStatement];
		if (statement == NULL) return;
	
		// DELETE FROM "database2" WHERE "collection" = ?;
		
		int const bind_idx_collection = SQLITE_BIND_START;
		
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"Error executing 'removeCollectionStatement': %d %s, collection(%@)",
			                                                       status, sqlite3_errmsg(connection->db), collection);
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_collection);
		
		connection->hasDiskChanges = YES;
		[connection->mutationStack markAsMutated];  // mutation during enumeration protection
		
		return;
	} // end shortcut
	
	
	NSUInteger left = [self numberOfKeysInCollection:collection];
	
	NSMutableArray *foundKeys = nil;
	NSMutableArray *foundRowids = nil;
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(connection->db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	// Loop over the keys, and remove them in big batches.
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	
	do
	{
		NSUInteger numKeyParams = MIN(left, maxHostParams-1); // minus 1 for collectionParam
		
		if (foundKeys == nil)
		{
			foundKeys   = [NSMutableArray arrayWithCapacity:numKeyParams];
			foundRowids = [NSMutableArray arrayWithCapacity:numKeyParams];
		}
		else
		{
			[foundKeys removeAllObjects];
			[foundRowids removeAllObjects];
		}
		
		NSUInteger foundCount = 0;
		
		// Find rowids for keys
		
		if (YES)
		{
			BOOL needsFinalize;
			sqlite3_stmt *statement = [connection enumerateKeysInCollectionStatement:&needsFinalize];
			if (statement == NULL) {
				FreeYapDatabaseString(&_collection);
				return;
			}
			
			// SELECT "rowid", "key" FROM "database2" WHERE "collection" = ?;
			
			int const column_idx_rowid    = SQLITE_COLUMN_START + 0;
			int const column_idx_key      = SQLITE_COLUMN_START + 1;
			int const bind_idx_collection = SQLITE_BIND_START;
			
			sqlite3_bind_text(statement, bind_idx_collection, _collection.str, _collection.length, SQLITE_STATIC);
			
			int status;
			while ((status = sqlite3_step(statement)) == SQLITE_ROW)
			{
				int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
				
				const unsigned char *text = sqlite3_column_text(statement, column_idx_key);
				int textSize = sqlite3_column_bytes(statement, column_idx_key);
				
				NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				
				[foundKeys addObject:key];
				[foundRowids addObject:@(rowid)];
				
				if (++foundCount >= numKeyParams)
				{
					break;
				}
			}
			
			if ((foundCount < numKeyParams) && (status != SQLITE_DONE))
			{
				YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
			}
			
			sqlite_enum_reset(statement, needsFinalize);
		}
		
		// Now remove all the matching rows
		
		if (foundCount > 0)
		{
			// DELETE FROM "database2" WHERE "rowid" in (?, ?, ...);
			
			NSUInteger capacity = 50 + (foundCount * 3);
			NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
			
			[query appendString:@"DELETE FROM \"database2\" WHERE \"rowid\" IN ("];
			
			NSUInteger i;
			for (i = 0; i < foundCount; i++)
			{
				if (i == 0)
					[query appendString:@"?"];
				else
					[query appendString:@", ?"];
			}
			
			[query appendString:@");"];
			
			sqlite3_stmt *statement;
			
			int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
			if (status != SQLITE_OK)
			{
				YDBLogError(@"Error creating 'removeAllObjectsInCollection:' statement: %d %s",
				            status, sqlite3_errmsg(connection->db));
				
				FreeYapDatabaseString(&_collection);
				return;
			}
            
			for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
			{
				[extTransaction willRemoveObjectsForKeys:foundKeys
				                            inCollection:collection
				                              withRowids:foundRowids];
			}
			
			for (i = 0; i < foundCount; i++)
			{
				int64_t rowid = [[foundRowids objectAtIndex:i] longLongValue];
				
				sqlite3_bind_int64(statement, (int)(SQLITE_BIND_START + i), rowid);
			}
			
			status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"Error executing 'removeAllObjectsInCollection:' statement: %d %s",
				            status, sqlite3_errmsg(connection->db));
			}
			
			sqlite3_finalize(statement);
			statement = NULL;
			
			connection->hasDiskChanges = YES;
			[connection->mutationStack markAsMutated];  // mutation during enumeration protection
			
			[connection->removedRowids addObjectsFromArray:foundRowids];
			
			for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
			{
				[extTransaction didRemoveObjectsForKeys:foundKeys
				                           inCollection:collection
				                             withRowids:foundRowids];
			}
		}
		
		// Move on to the next batch (if there's more)
		
		left -= foundCount;
		
	} while((left > 0) && ([foundKeys count] > 0));
	
	
	FreeYapDatabaseString(&_collection);
}

- (void)removeAllObjectsInAllCollections
{
	sqlite3_stmt *statement = [connection removeAllStatement];
	if (statement == NULL) return;

    for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
    {
        [extTransaction willRemoveAllObjectsInAllCollections];
    }
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeAllStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
	
	connection->hasDiskChanges = YES;
	[connection->mutationStack markAsMutated];  // mutation during enumeration protection
	
	[connection->keyCache removeAllObjects];
	[connection->objectCache removeAllObjects];
	[connection->metadataCache removeAllObjects];
	
	[connection->objectChanges removeAllObjects];
	[connection->metadataChanges removeAllObjects];
	[connection->removedKeys removeAllObjects];
	[connection->removedCollections removeAllObjects];
	[connection->removedRowids removeAllObjects];
	connection->allKeysRemoved = YES;
	
	for (YapDatabaseExtensionTransaction *extTransaction in [self orderedExtensions])
	{
		[extTransaction didRemoveAllObjectsInAllCollections];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Completion
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
- (void)addCompletionQueue:(dispatch_queue_t)completionQueue
           completionBlock:(dispatch_block_t)completionBlock
{
	if (completionBlock == nil)
		return;
	
	if (completionQueue == nil)
		completionQueue = dispatch_get_main_queue();
	
	if (completionQueueStack == nil)
		completionQueueStack = [[NSMutableArray alloc] initWithCapacity:1];
	
	if (completionBlockStack == nil)
		completionBlockStack = [[NSMutableArray alloc] initWithCapacity:1];
	
	[completionQueueStack addObject:completionQueue];
	[completionBlockStack addObject:completionBlock];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extensions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)addRegisteredExtensionTransaction:(YapDatabaseExtensionTransaction *)extTransaction withName:(NSString *)extName
{
	// This method is INTERNAL
	
	if (extensions == nil)
		extensions = [[NSMutableDictionary alloc] init];
	
	[extensions setObject:extTransaction forKey:extName];
}

- (void)removeRegisteredExtensionTransactionWithName:(NSString *)extName
{
	// This method is INTERNAL
	
	[extensions removeObjectForKey:extName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Yap2 Table
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setBoolValue:(BOOL)value forKey:(NSString *)key extension:(NSString *)extensionName
{
	[self setIntValue:(value ? 1 : 0) forKey:key extension:extensionName];
}

- (void)setIntValue:(int)value forKey:(NSString *)key extension:(NSString *)extensionName
{
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [connection yapSetDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "yap2" ("extension", "key", "data") VALUES (?, ?, ?);
	
	int const bind_idx_extension = SQLITE_BIND_START + 0;
	int const bind_idx_key       = SQLITE_BIND_START + 1;
	int const bind_idx_data      = SQLITE_BIND_START + 2;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, bind_idx_extension, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
	
	sqlite3_bind_int(statement, bind_idx_data, value);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		connection->hasDiskChanges = YES;
	}
	else
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
}

- (void)setDoubleValue:(double)value forKey:(NSString *)key extension:(NSString *)extensionName
{
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [connection yapSetDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "yap2" ("extension", "key", "data") VALUES (?, ?, ?);
	
	int const bind_idx_extension = SQLITE_BIND_START + 0;
	int const bind_idx_key       = SQLITE_BIND_START + 1;
	int const bind_idx_data      = SQLITE_BIND_START + 2;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, bind_idx_extension, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
	
	sqlite3_bind_double(statement, bind_idx_data, value);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		connection->hasDiskChanges = YES;
	}
	else
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
}

- (void)setStringValue:(NSString *)value forKey:(NSString *)key extension:(NSString *)extensionName
{
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [connection yapSetDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "yap2" ("extension", "key", "data") VALUES (?, ?, ?);
	
	int const bind_idx_extension = SQLITE_BIND_START + 0;
	int const bind_idx_key       = SQLITE_BIND_START + 1;
	int const bind_idx_data      = SQLITE_BIND_START + 2;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, bind_idx_extension, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
	
	YapDatabaseString _value; MakeYapDatabaseString(&_value, value);
	sqlite3_bind_text(statement, bind_idx_data, _value.str, _value.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		connection->hasDiskChanges = YES;
	}
	else
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	FreeYapDatabaseString(&_value);
}

- (void)setDataValue:(NSData *)value forKey:(NSString *)key extension:(NSString *)extensionName
{
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [connection yapSetDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "yap2" ("extension", "key", "data") VALUES (?, ?, ?);
	
	int const bind_idx_extension = SQLITE_BIND_START + 0;
	int const bind_idx_key       = SQLITE_BIND_START + 1;
	int const bind_idx_data      = SQLITE_BIND_START + 2;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, bind_idx_extension, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
	
	__attribute__((objc_precise_lifetime)) NSData *data = value;
	sqlite3_bind_blob(statement, bind_idx_data, data.bytes, (int)data.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		connection->hasDiskChanges = YES;
	}
	else
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
}

- (void)removeValueForKey:(NSString *)key extension:(NSString *)extensionName
{
	// Be careful with this statement.
	//
	// The snapshot value is in the yap table, and uses an empty string for the extensionName.
	// The snapshot value is critical to the underlying architecture of the system.
	// Removing it could cripple the system.
	
	NSAssert(key != nil, @"Invalid key!");
	NSAssert(extensionName != nil, @"Invalid extensionName!");
	
	sqlite3_stmt *statement = [connection yapRemoveForKeyStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "yap2" WHERE "extension" = ? AND "key" = ?;
	
	int const bind_idx_extension = SQLITE_BIND_START + 0;
	int const bind_idx_key       = SQLITE_BIND_START + 1;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, bind_idx_extension, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, bind_idx_key, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		connection->hasDiskChanges = YES;
	}
	else
	{
		YDBLogError(@"Error executing 'yapRemoveForKeyStatement': %d %s, extension(%@)",
					status, sqlite3_errmsg(connection->db), extensionName);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
}

- (void)removeAllValuesForExtension:(NSString *)extensionName
{
	// Be careful with this statement.
	//
	// The snapshot value is in the yap table, and uses an empty string for the extensionName.
	// The snapshot value is critical to the underlying architecture of the system.
	// Removing it could cripple the system.
	
	NSAssert(extensionName != nil, @"Invalid extensionName!");
	
	sqlite3_stmt *statement = [connection yapRemoveExtensionStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "yap2" WHERE "extension" = ?;
	
	int const bind_idx_extension = SQLITE_BIND_START;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, bind_idx_extension, _extension.str, _extension.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		connection->hasDiskChanges = YES;
	}
	else
	{
		YDBLogError(@"Error executing 'yapRemoveExtensionStatement': %d %s, extension(%@)",
					status, sqlite3_errmsg(connection->db), extensionName);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
}

@end
