#import "YapDatabaseTransaction.h"
#import "YapDatabasePrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"
#import "YapCache.h"
#import "YapNull.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapDatabaseReadTransaction {
	
/* As defined in YapAbstractDatabasePrivate.h :
 
@public

	__unsafe_unretained YapAbstractDatabaseConnection *abstractConnection;

	BOOL isReadWriteTransaction;
*/
}

#pragma mark Count

- (NSUInteger)numberOfKeys
{
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	sqlite3_stmt *statement = [connection getCountStatement];
	if (statement == NULL) return 0;
	
	NSUInteger result = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (!connection->hasMarkedSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		result = (NSUInteger)sqlite3_column_int64(statement, 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getDataForKeyStatement': %d %s",
		                                                    status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
	
	return result;
}

#pragma mark List

- (NSArray *)allKeys
{
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	sqlite3_stmt *statement = [connection enumerateKeysStatement];
	if (statement == NULL) return nil;
	
	// SELECT "key" FROM "database";
	
	__block NSMutableArray *keys = [[NSMutableArray alloc] init];
	
	while (sqlite3_step(statement) == SQLITE_ROW)
	{
		if (!connection->hasMarkedSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const unsigned char *text = sqlite3_column_text(statement, 0);
		int textSize = sqlite3_column_bytes(statement, 0);
		
		NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		[keys addObject:key];
	}
	
	sqlite3_reset(statement);
	
	return keys;
}

#pragma mark Primitive

- (NSData *)primitiveDataForKey:(NSString *)key
{
	if (key == nil) return nil;
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	sqlite3_stmt *statement = [connection getDataForKeyStatement];
	if (statement == NULL) return nil;
	
	// SELECT "data" FROM "database" WHERE "key" = ? ;
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
	
	NSData *result = nil;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (!connection->hasMarkedSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		result = [[NSData alloc] initWithBytes:blob length:blobSize];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getDataForKeyStatement': %d %s, key(%@)",
				   status, sqlite3_errmsg(connection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	return result;
}

#pragma mark Object

- (id)objectForKey:(NSString *)key
{
	if (key == nil) return nil;
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	id object = [connection->objectCache objectForKey:key];
	if (object)
		return object;
	
	sqlite3_stmt *statement = [connection getDataForKeyStatement];
	if (statement == NULL) return nil;
	
	// SELECT data FROM 'database' WHERE key = ? ;
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
	
	NSData *objectData = nil;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (!connection->hasMarkedSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		// Performance tuning:
		//
		// Use initWithBytesNoCopy to avoid an extra allocation and memcpy.
		// But be sure not to call sqlite3_reset until we're done with the data.
		
		objectData = [[NSData alloc] initWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getDataForKeyStatement': %d %s, key(%@)",
				   status, sqlite3_errmsg(connection->db), key);
	}
	
	object = objectData ? connection.database.objectDeserializer(objectData) : nil;
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	if (object)
		[connection->objectCache setObject:object forKey:key];
	
	return object;
}

- (BOOL)hasObjectForKey:(NSString *)key
{
	if (key == nil) return NO;
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	// Shortcut:
	// We may not need to query the database if we have the key in any of our caches.
	
	if ([connection->metadataCache objectForKey:key]) return YES;
	if ([connection->objectCache objectForKey:key]) return YES;
	
	// The normal SQL way
	
	sqlite3_stmt *statement = [connection getCountForKeyStatement];
	if (statement == NULL) return NO;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "database" WHERE "key" = ?;
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
	
	BOOL result = NO;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (!connection->hasMarkedSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		result = (sqlite3_column_int64(statement, 0) > 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getCountForKeyStatement': %d %s, key(%@)",
		                                                     status, sqlite3_errmsg(connection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	return result;
}

- (BOOL)getObject:(id *)objectPtr metadata:(id *)metadataPtr forKey:(NSString *)key
{
	if (key == nil)
	{
		if (objectPtr) *objectPtr = nil;
		if (metadataPtr) *metadataPtr = nil;
		
		return NO;
	}
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	id object = [connection->objectCache objectForKey:key];
	id metadata = [connection->metadataCache objectForKey:key];
	
	if (object && metadata)
	{
		// Both object and metadata were in cache.
		// Just need to check for empty metadata placeholder from cache.
		if (metadata == [YapNull null])
			metadata = nil;
	}
	else if (!object && metadata)
	{
		// Metadata was in cache.
		// Missing object. Fetch individually.
		object = [self objectForKey:key];
		
		// And check for empty metadata placeholder from cache.
		if (metadata == [YapNull null])
			metadata = nil;
	}
	else if (object && !metadata)
	{
		// Object was in cache.
		// Missing metadata. Fetch individually.
		metadata = [self metadataForKey:key];
	}
	else // (!object && !metadata)
	{
		// Both object and metadata are missing.
		// Fetch via query.
		
		sqlite3_stmt *statement = [connection getAllForKeyStatement];
		if (statement)
		{
			// SELECT "data", "metadata" FROM "database" WHERE "key" = ? ;
			
			YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
			sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
			
			NSData *objectData = nil;
			NSData *metadataData = nil;
			
			int status = sqlite3_step(statement);
			if (status == SQLITE_ROW)
			{
				if (!connection->hasMarkedSqlLevelSharedReadLock)
					[connection markSqlLevelSharedReadLockAcquired];
				
				const void *oBlob = sqlite3_column_blob(statement, 0);
				int oBlobSize = sqlite3_column_bytes(statement, 0);
				
				if (oBlobSize > 0)
					objectData = [[NSData alloc] initWithBytesNoCopy:(void *)oBlob
					                                          length:oBlobSize
					                                    freeWhenDone:NO];
				
				const void *mBlob = sqlite3_column_blob(statement, 1);
				int mBlobSize = sqlite3_column_bytes(statement, 1);
				
				if (mBlobSize > 0)
					metadataData = [[NSData alloc] initWithBytesNoCopy:(void *)mBlob
					                                            length:mBlobSize
					                                      freeWhenDone:NO];
			}
			else if (status == SQLITE_ERROR)
			{
				YDBLogError(@"Error executing 'getAllForKeyStatement': %d %s",
				                                                   status, sqlite3_errmsg(connection->db));
			}
			
			if (objectData)
				object = connection.database.objectDeserializer(objectData);
			
			if (object)
				[connection->objectCache setObject:object forKey:key];
			
			if (metadataData)
				metadata = connection.database.metadataDeserializer(metadataData);
				
			if (metadata)
				[connection->metadataCache setObject:metadata forKey:key];
			else if (object)
				[connection->metadataCache setObject:[YapNull null] forKey:key];
				
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
			FreeYapDatabaseString(&_key);
		}
	}
	
	if (objectPtr) *objectPtr = object;
	if (metadataPtr) *metadataPtr = metadata;
	
	return (object != nil || metadata != nil);
}

#pragma mark Metadata

- (id)metadataForKey:(NSString *)key
{
	if (key == nil) return nil;
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	id metadata = [connection->metadataCache objectForKey:key];
	if (metadata)
	{
		if (metadata == [YapNull null])
			return nil;
		else
			return metadata;
	}
	
	sqlite3_stmt *statement = [connection getMetadataForKeyStatement];
	if (statement == NULL) return nil;
	
	// SELECT "metadata" FROM "database" WHERE "key" = ? ;
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
	
	BOOL found = NO;
	NSData *metadataData = nil;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (!connection->hasMarkedSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		found = YES;
		
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		// Performance tuning:
		//
		// Use initWithBytesNoCopy to avoid an extra allocation and memcpy.
		// But be sure not to call sqlite3_reset until we're done with the data.
		
		if (blobSize > 0)
			metadataData = [[NSData alloc] initWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getMetadataForKeyStatement': %d %s",
		                                                        status, sqlite3_errmsg(connection->db));
	}
	
	if (found)
	{
		if (metadataData)
			metadata = connection.database.metadataDeserializer(metadataData);
		
		if (metadata)
			[connection->metadataCache setObject:metadata forKey:key];
		else
			[connection->metadataCache setObject:[YapNull null] forKey:key];
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	return metadata;
}

#pragma mark Enumerate

/**
 * Fast enumeration over all keys in the database.
 *
 * This uses a "SELECT key FROM database" operation, and then steps over the results
 * and invoking the given block handler.
**/
- (void)enumerateKeys:(void (^)(NSString *key, BOOL *stop))block
{
	if (block == NULL) return;
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	sqlite3_stmt *statement = [connection enumerateKeysStatement];
	if (statement == NULL) return;
	
	// SELECT "key" FROM "database";
	
	while (sqlite3_step(statement) == SQLITE_ROW)
	{
		if (!connection->hasMarkedSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const unsigned char *text = sqlite3_column_text(statement, 0);
		int textSize = sqlite3_column_bytes(statement, 0);
		
		NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		BOOL stop = NO;
		
		block(key, &stop);
		
		if (stop) break;
	}
	
	sqlite3_reset(statement);
}

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
                 forKeys:(NSArray *)keys
{
	if ([keys count] == 0) return;
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	NSMutableArray *missingIndexes = [NSMutableArray arrayWithCapacity:[keys count]];
	BOOL stop = NO;
	
	// Check the cache first (to optimize cache)
	
	NSUInteger keyIndex = 0;
	
	for (NSString *key in keys)
	{
		id object = [connection->objectCache objectForKey:key];
		if (object)
		{
			block(keyIndex, object, &stop);
			
			if (stop) break;
		}
		else
		{
			[missingIndexes addObject:@(keyIndex)];
		}
				  
		keyIndex++;
	}
	
	if (stop || [missingIndexes count] == 0) return;
	
	// Go to database for any missing keys (if needed)
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(connection->db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	do
	{
		NSUInteger numHostParams = MIN([missingIndexes count], maxHostParams);
		
		// SELECT "key", "data" FROM "database" WHERE key IN (?, ?, ...);
		
		NSUInteger capacity = 80 + (numHostParams * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendString:@"SELECT \"key\", \"data\" FROM \"database\" WHERE \"key\" IN ("];
		
		NSUInteger i;
		for (i = 0; i < numHostParams; i++)
		{
			if (i == 0)
				[query appendFormat:@"?"];
			else
				[query appendFormat:@", ?"];
		}
		
		[query appendString:@");"];
		
		sqlite3_stmt *statement;
		
		int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'objectsForKeys' statement: %d %s",
						status, sqlite3_errmsg(connection->db));
			return;
		}
		
		NSMutableDictionary *keyIndexDict = [NSMutableDictionary dictionaryWithCapacity:numHostParams];
		
		for (i = 0; i < numHostParams; i++)
		{
			NSNumber *keyIndexNumber = [missingIndexes objectAtIndex:i];
			NSString *key = [keys objectAtIndex:[keyIndexNumber unsignedIntegerValue]];
			
			[keyIndexDict setObject:keyIndexNumber forKey:key];
			
			sqlite3_bind_text(statement, (int)(i + 1), [key UTF8String], -1, SQLITE_TRANSIENT);
		}
		
		while (sqlite3_step(statement) == SQLITE_ROW && !stop)
		{
			if (!connection->hasMarkedSqlLevelSharedReadLock)
				[connection markSqlLevelSharedReadLockAcquired];
			
			const unsigned char *text = sqlite3_column_text(statement, 0);
			int textSize = sqlite3_column_bytes(statement, 0);
			
			const void *blob = sqlite3_column_blob(statement, 1);
			int blobSize = sqlite3_column_bytes(statement, 1);
			
			NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			NSUInteger keyIndex = [[keyIndexDict objectForKey:key] unsignedIntegerValue];
			
			NSData *objectData = [[NSData alloc] initWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			
			id object = objectData ? connection.database.objectDeserializer(objectData) : nil;
			
			if (object) {
				[connection->objectCache setObject:object forKey:key];
			}
			
			block(keyIndex, object, &stop);
			
			[keyIndexDict removeObjectForKey:key];
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
		
		if (stop) return;
		
		// If there are any remaining items in the keyIndexDict,
		// then those items didn't exist in the database.
		
		for (NSNumber *keyIndexNumber in [keyIndexDict objectEnumerator])
		{
			block([keyIndexNumber unsignedIntegerValue], nil, &stop);
			
			if (stop) break;
		}
		
		[missingIndexes removeObjectsInRange:NSMakeRange(0, numHostParams)];
		
	} while ([missingIndexes count] > 0);
}

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
- (void)enumerateKeysAndMetadataUsingBlock:(void (^)(NSString *key, id metadata, BOOL *stop))block
{
	return [self enumerateKeysAndMetadataUsingBlock:block withKeyFilter:NULL];
}

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
                             withKeyFilter:(BOOL (^)(NSString *key))filter
{
	if (block == NULL) return;
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	sqlite3_stmt *statement = [connection enumerateMetadataStatement];
	if (statement == NULL) return;
	
	// SELECT "key", "metadata" FROM "database";
	//
	// Performance tuning:
	// Use initWithBytesNoCopy to avoid an extra allocation and memcpy.
	//
	// Cache considerations:
	// Do we want to add the objects/metadata to the cache here?
	// If the cache is unlimited then we should.
	// Otherwise we should only add to the cache if its not full.
	// The cache should generally be reserved for items that are explicitly fetched,
	// and we don't want to crowd them out during enumerations.
	
	BOOL stop = NO;
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);
	
	while (sqlite3_step(statement) == SQLITE_ROW)
	{
		if (!connection->hasMarkedSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const unsigned char *text = sqlite3_column_text(statement, 0);
		int textSize = sqlite3_column_bytes(statement, 0);
		
		NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		BOOL invokeBlock = filter == NULL ? YES : filter(key);
		if (invokeBlock)
		{
			id metadata = [connection->metadataCache objectForKey:key];
			if (metadata)
			{
				if (metadata == [YapNull null])
					metadata = nil;
			}
			else
			{
				const void *mBlob = sqlite3_column_blob(statement, 1);
				int mBlobSize = sqlite3_column_bytes(statement, 1);
				
				if (mBlobSize > 0)
				{
					NSData *mData = [[NSData alloc] initWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
					metadata = connection.database.metadataDeserializer(mData);
				}
				
				if (unlimitedMetadataCacheLimit || [connection->metadataCache count] < connection->metadataCacheLimit)
				{
					if (metadata)
						[connection->metadataCache setObject:metadata forKey:key];
					else
						[connection->metadataCache setObject:[YapNull null] forKey:key];
				}
			}
			
			block(key, metadata, &stop);
			
			if (stop) break;
		}
	}
	
	sqlite3_reset(statement);
}

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
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSString *key, id object, id metadata, BOOL *stop))block
{
	[self enumerateKeysAndObjectsUsingBlock:block withKeyFilter:NULL];
}

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
                            withKeyFilter:(BOOL (^)(NSString *key))filter
{
	if (block == NULL) return;
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	sqlite3_stmt *statement = [connection enumerateAllStatement];
	if (statement == NULL) return;
	
	// SELECT "key", "data", "metadata" FROM "database";
	//
	// Performance tuning:
	// Use initWithBytesNoCopy to avoid an extra allocation and memcpy.
	//
	// Cache considerations:
	// Do we want to add the objects/metadata to the cache here?
	// If the cache is unlimited then we should.
	// Otherwise we should only add to the cache if its not full.
	// The cache should generally be reserved for items that are explicitly fetched,
	// and we don't want to crowd them out during enumerations.
	
	BOOL stop = NO;
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);

	while (sqlite3_step(statement) == SQLITE_ROW)
	{
		if (!connection->hasMarkedSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const unsigned char *text = sqlite3_column_text(statement, 0);
		int textSize = sqlite3_column_bytes(statement, 0);
		
		NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		BOOL invokeBlock = filter == NULL ? YES : filter(key);
		if (invokeBlock)
		{
			id metadata = [connection->metadataCache objectForKey:key];
			if (metadata)
			{
				if (metadata == [YapNull null])
					metadata = nil;
			}
			else
			{
				const void *mBlob = sqlite3_column_blob(statement, 2);
				int mBlobSize = sqlite3_column_bytes(statement, 2);
				
				if (mBlobSize > 0)
				{
					NSData *mData = [[NSData alloc] initWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
					metadata = connection.database.metadataDeserializer(mData);
				}
				
				if (unlimitedMetadataCacheLimit || [connection->metadataCache count] < connection->metadataCacheLimit)
				{
					if (metadata)
						[connection->metadataCache setObject:metadata forKey:key];
					else
						[connection->metadataCache setObject:[YapNull null] forKey:key];
				}
			}
			
			id object = [connection->objectCache objectForKey:key];
			if (object == nil)
			{
				const void *oBlob = sqlite3_column_blob(statement, 1);
				int oBlobSize = sqlite3_column_bytes(statement, 1);

				NSData *oData = [[NSData alloc] initWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
				object = connection.database.objectDeserializer(oData);
				
				if (unlimitedObjectCacheLimit || [connection->objectCache count] < connection->objectCacheLimit)
				{
					[connection->objectCache setObject:object forKey:key];
				}
			}
			
			block(key, object, metadata, &stop);
			
			if (stop) break;
		}
	}
	
	sqlite3_reset(statement);
}

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
                       withMetadataFilter:(BOOL (^)(NSString *key, id metadata))filter
{
	if (block == NULL) return;
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	sqlite3_stmt *statement = [connection enumerateAllStatement];
	if (statement == NULL) return;
	
	// SELECT "key", "data", "metadata" FROM "database";
	//
	// Performance tuning:
	// Use initWithBytesNoCopy to avoid an extra allocation and memcpy.
	//
	// Cache considerations:
	// Do we want to add the objects/metadata to the cache here?
	// If the cache is unlimited then we should.
	// Otherwise we should only add to the cache if its not full.
	// The cache should generally be reserved for items that are explicitly fetched,
	// and we don't want to crowd them out during enumerations.
	
	BOOL stop = NO;
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);

	while (sqlite3_step(statement) == SQLITE_ROW)
	{
		if (!connection->hasMarkedSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const unsigned char *text = sqlite3_column_text(statement, 0);
		int textSize = sqlite3_column_bytes(statement, 0);
		
		NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		id metadata = [connection->metadataCache objectForKey:key];
		if (metadata)
		{
			if (metadata == [YapNull null])
				metadata = nil;
		}
		else
		{
			const void *mBlob = sqlite3_column_blob(statement, 2);
			int mBlobSize = sqlite3_column_bytes(statement, 2);
			
			if (mBlobSize > 0)
			{
				NSData *mData = [[NSData alloc] initWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
				metadata = connection.database.metadataDeserializer(mData);
			}
			
			if (unlimitedMetadataCacheLimit || [connection->metadataCache count] < connection->metadataCacheLimit)
			{
				if (metadata)
					[connection->metadataCache setObject:metadata forKey:key];
				else
					[connection->metadataCache setObject:[YapNull null] forKey:key];
			}
		}
		
		BOOL invokeBlock = filter == NULL ? YES : filter(key, metadata);
		if (invokeBlock)
		{
			id object = [connection->objectCache objectForKey:key];
			if (object == nil)
			{
				const void *oBlob = sqlite3_column_blob(statement, 1);
				int oBlobSize = sqlite3_column_bytes(statement, 1);

				NSData *oData = [[NSData alloc] initWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
				object = connection.database.objectDeserializer(oData);
				
				if (unlimitedObjectCacheLimit || [connection->objectCache count] < connection->objectCacheLimit)
				{
					[connection->objectCache setObject:object forKey:key];
				}
			}
			
			block(key, object, metadata, &stop);
			
			if (stop) break;
		}
	}
	
	sqlite3_reset(statement);
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseReadWriteTransaction

#pragma mark Primitive

- (void)setPrimitiveData:(NSData *)data forKey:(NSString *)key
{
	[self setPrimitiveData:data forKey:key withMetadata:nil];
}

- (void)setPrimitiveData:(NSData *)data forKey:(NSString *)key withMetadata:(id)metadata
{
	if (data == nil)
	{
		[self removeObjectForKey:key];
		return;
	}
	
	if (key == nil) return;
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	sqlite3_stmt *statement = [connection setAllForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "database" ("key", "data", "metadata") VALUES (?, ?, ?);
	//
	// To use SQLITE_STATIC on our data blob, we use the objc_precise_lifetime attribute.
	// This ensures the data isn't released until it goes out of scope.
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
	
	sqlite3_bind_blob(statement, 2, data.bytes, data.length, SQLITE_STATIC);
	
	__attribute__((objc_precise_lifetime)) NSData *rawMeta = connection.database.metadataSerializer(metadata);
	sqlite3_bind_blob(statement, 3, rawMeta.bytes, rawMeta.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'setAllForKeyStatement': %d %s, key(%@)",
		                                                   status, sqlite3_errmsg(connection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	[connection->objectCache removeObjectForKey:key];
	[connection->objectChanges setObject:[YapNull null] forKey:key];
	
	if (metadata) {
		[connection->metadataCache setObject:metadata forKey:key];
		[connection->metadataChanges setObject:metadata forKey:key];
	}
	else {
		[connection->metadataCache setObject:[YapNull null] forKey:key];
		[connection->metadataChanges setObject:[YapNull null] forKey:key];
	}
	
	// Todo: How best to handle for extension?
}

#pragma mark Object

- (void)setObject:(id)object forKey:(NSString *)key
{
	[self setObject:object forKey:key withMetadata:nil];
}

- (void)setObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata
{
	if (object == nil)
	{
		[self removeObjectForKey:key];
		return;
	}
	
	if (key == nil) return;
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	sqlite3_stmt *statement = [connection setAllForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "database" ("key", "data", "metadata") VALUES (?, ?, ?);
	//
	// To use SQLITE_STATIC on our data blob, we use the objc_precise_lifetime attribute.
	// This ensures the data isn't released until it goes out of scope.
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
	
	__attribute__((objc_precise_lifetime)) NSData *rawData = connection.database.objectSerializer(object);
	sqlite3_bind_blob(statement, 2, rawData.bytes, rawData.length, SQLITE_STATIC);
	
	__attribute__((objc_precise_lifetime)) NSData *rawMeta = connection.database.metadataSerializer(metadata);
	sqlite3_bind_blob(statement, 3, rawMeta.bytes, rawMeta.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'setAllForKeyStatement': %d %s, key(%@)",
		                                                   status, sqlite3_errmsg(connection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	[connection->objectCache setObject:object forKey:key];
	[connection->objectChanges setObject:object forKey:key];
	
	if (metadata) {
		[connection->metadataCache setObject:metadata forKey:key];
		[connection->metadataChanges setObject:metadata forKey:key];
	}
	else {
		[connection->metadataCache setObject:[YapNull null] forKey:key];
		[connection->metadataChanges setObject:[YapNull null] forKey:key];
	}
	
	[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_KeyValue> extTransaction = extTransactionObj;
		
		[extTransaction handleSetObject:object forKey:key withMetadata:metadata];
	}];
}

#pragma mark Metadata

- (void)setMetadata:(id)metadata forKey:(NSString *)key
{
	if (![self hasObjectForKey:key]) return;
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	sqlite3_stmt *statement = [connection setMetadataForKeyStatement];
	if (statement == NULL) return;
	
	// UPDATE "database" SET "metadata" = ? WHERE "key" = ?;
	// 
	// To use SQLITE_STATIC on our data blob, we use the objc_precise_lifetime attribute.
	// This ensures the data isn't released until it goes out of scope.
	
	__attribute__((objc_precise_lifetime)) NSData *rawMeta = connection.database.metadataSerializer(metadata);
	sqlite3_bind_blob(statement, 1, rawMeta.bytes, rawMeta.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	BOOL updated = YES;
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'setMetaForKeyStatement': %d %s, key(%@)",
		                                                    status, sqlite3_errmsg(connection->db), key);
		updated = NO;
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	if (!updated) return;
	
	if (metadata) {
		[connection->metadataCache setObject:metadata forKey:key];
		[connection->metadataChanges setObject:metadata forKey:key];
	}
	else {
		[connection->metadataCache setObject:[YapNull null] forKey:key];
		[connection->metadataChanges setObject:[YapNull null] forKey:key];
	}
	
	[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_KeyValue> extTransaction = extTransactionObj;
		
		[extTransaction handleSetMetadata:metadata forKey:key];
	}];
}

#pragma mark Remove

- (void)removeObjectForKey:(NSString *)key
{
	if (key == nil) return;
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	sqlite3_stmt *statement = [connection removeForKeyStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "database" WHERE "key" = ?;
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
	
	BOOL removed = YES;
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeForKeyStatement': %d %s, key(%@)",
		                                                   status, sqlite3_errmsg(connection->db), key);
		removed = NO;
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	if (!removed) return;
	
	[connection->objectCache removeObjectForKey:key];
	[connection->metadataCache removeObjectForKey:key];
	
	[connection->objectChanges removeObjectForKey:key];
	[connection->metadataChanges removeObjectForKey:key];
	[connection->removedKeys addObject:key];
	
	[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_KeyValue> extTransaction = extTransactionObj;
		
		[extTransaction handleRemoveObjectForKey:key];
	}];
}

- (void)removeObjectsForKeys:(NSArray *)keys
{
	if ([keys count] == 0) return;
	
	if ([keys count] == 1)
	{
		[self removeObjectForKey:[keys objectAtIndex:0]];
		return;
	}
	
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(connection->db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	NSUInteger keysIndex = 0;
	NSUInteger keysCount = [keys count];
	
	do
	{
		NSUInteger keysLeft = keysCount - keysIndex;
		NSUInteger numHostParams = MIN(keysLeft, maxHostParams);
		
		// DELETE FROM "database" WHERE "key" in (?, ?, ...);
		
		NSUInteger capacity = 50 + (numHostParams * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendString:@"DELETE FROM \"database\" WHERE \"key\" IN ("];
		
		NSUInteger i;
		for (i = 0; i < numHostParams; i++)
		{
			if (i == 0)
				[query appendFormat:@"?"];
			else
				[query appendFormat:@", ?"];
		}
	
		[query appendString:@");"];
	
		sqlite3_stmt *statement;
		
		int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'removeObjectForKeys' statement: %d %s",
			                                                          status, sqlite3_errmsg(connection->db));
			return;
		}
		
		for (i = 0; i < numHostParams; i++)
		{
			NSString *key = [keys objectAtIndex:(keysIndex + i)];
			
			sqlite3_bind_text(statement, (int)(i + 1), [key UTF8String], -1, SQLITE_TRANSIENT);
		}
		
		status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"Error executing 'removeObjectForKeys' statement: %d %s",
			                                                           status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
		
		keysIndex += numHostParams;
		
	} while (keysIndex < keysCount);
	
	[connection->objectCache removeObjectsForKeys:keys];
	[connection->metadataCache removeObjectsForKeys:keys];
	
	[connection->objectChanges removeObjectsForKeys:keys];
	[connection->metadataChanges removeObjectsForKeys:keys];
	[connection->removedKeys addObjectsFromArray:keys];
	
	[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_KeyValue> extTransaction = extTransactionObj;
		
		[extTransaction handleRemoveObjectsForKeys:keys];
	}];
}

- (void)removeAllObjects
{
	__unsafe_unretained YapDatabaseConnection *connection = (YapDatabaseConnection *)abstractConnection;
	
	sqlite3_stmt *statement = [connection removeAllStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "database";
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeAllStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
	
	[connection->objectCache removeAllObjects];
	[connection->metadataCache removeAllObjects];
	
	[connection->objectChanges removeAllObjects];
	[connection->metadataChanges removeAllObjects];
	[connection->removedKeys removeAllObjects];
	connection->allKeysRemoved = YES;
	
	[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_KeyValue> extTransaction = extTransactionObj;
		
		[extTransaction handleRemoveAllObjects];
	}];
}

#pragma mark Extensions

- (void)dropExtension:(NSString *)extensionName
{
	// Todo...
}

@end
