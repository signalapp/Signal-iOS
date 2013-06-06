#import "YapCollectionsDatabaseViewTransaction.h"
#import "YapCollectionsDatabaseViewPrivate.h"
#import "YapCollectionsDatabaseViewPage.h"
#import "YapDatabaseViewPageMetadata.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapCollectionsDatabaseTransaction.h"
#import "YapCache.h"
#import "YapCacheCollectionKey.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_VERBOSE | YDB_LOG_FLAG_TRACE;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapCollectionsDatabaseViewTransaction

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapCollectionsDatabaseTransaction
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)objectForKey:(NSString *)key inCollection:(NSString *)collection
{
	__unsafe_unretained YapCollectionsDatabaseReadTransaction *transaction =
	    (YapCollectionsDatabaseReadTransaction *)databaseTransaction;
	
	return [transaction objectForKey:key inCollection:collection];
}

- (id)metadataForKey:(NSString *)key inCollection:(NSString *)collection
{
	__unsafe_unretained YapCollectionsDatabaseReadTransaction *transaction =
	    (YapCollectionsDatabaseReadTransaction *)databaseTransaction;
	
	return [transaction metadataForKey:key inCollection:collection];
}

- (BOOL)getObject:(id *)objectPtr metadata:(id *)metadataPtr forKey:(NSString *)key inCollection:(NSString *)collection
{
	__unsafe_unretained YapCollectionsDatabaseReadTransaction *transaction =
	    (YapCollectionsDatabaseReadTransaction *)databaseTransaction;
	
	return [transaction getObject:objectPtr metadata:metadataPtr forKey:key inCollection:collection];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)registeredViewName
{
	return [extensionConnection->extension registeredName];
}

- (NSString *)keyTableName
{
	return [(YapCollectionsDatabaseView *)(extensionConnection->extension) keyTableName];
}

- (NSString *)pageTableName
{
	return [(YapCollectionsDatabaseView *)(extensionConnection->extension) pageTableName];
}

- (NSData *)serializePage:(YapCollectionsDatabaseViewPage *)page
{
	return [NSKeyedArchiver archivedDataWithRootObject:page];
}

- (YapCollectionsDatabaseViewPage *)deserializePage:(NSData *)data
{
	return [NSKeyedUnarchiver unarchiveObjectWithData:data];
}

- (NSData *)serializeMetadata:(YapDatabaseViewPageMetadata *)metadata
{
	return [NSKeyedArchiver archivedDataWithRootObject:metadata];
}

- (YapDatabaseViewPageMetadata *)deserializeMetadata:(NSData *)data
{
	return [NSKeyedUnarchiver unarchiveObjectWithData:data];
}

- (NSString *)generatePageKey
{
	NSString *key = nil;
	
	CFUUIDRef uuid = CFUUIDCreate(NULL);
	if (uuid)
	{
		key = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
		CFRelease(uuid);
	}
	
	return key;
}

/**
 * If the given collection/key is in the view, returns the associated pageKey.
 *
 * This method will use the cache(s) if possible.
 * Otherwise it will lookup the value in the key table.
**/
- (NSString *)pageKeyForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil)
		return nil;
	
	if (collection == nil)
		collection = @"";
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	NSString *pageKey = nil;
	
	// Check dirty cache & clean cache
	
	YapCacheCollectionKey *cacheKey = [[YapCacheCollectionKey alloc] initWithCollection:collection key:key];
	
	pageKey = [viewConnection->dirtyKeys objectForKey:cacheKey];
	if (pageKey)
	{
		if ((__bridge void *)pageKey == (__bridge void *)[NSNull null])
			return nil;
		else
			return pageKey;
	}
	
	pageKey = [viewConnection->keyCache objectForKey:cacheKey];
	if (pageKey)
	{
		if ((__bridge void *)pageKey == (__bridge void *)[NSNull null])
			return nil;
		else
			return pageKey;
	}
	
	// Otherwise pull from the database
	
	sqlite3_stmt *statement = [viewConnection keyTable_getPageKeyForCollectionKeyStatement];
	if (statement == NULL)
		return nil;
	
	// SELECT "pageKey" FROM "keyTableName" WHERE collection = ? AND key = ? ;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(statement, 0);
		int textSize = sqlite3_column_bytes(statement, 0);
		
		pageKey = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ (%@): Error executing statement: %d %s, key(%@)",
		            THIS_METHOD, [self registeredViewName],
		            status, sqlite3_errmsg(databaseTransaction->abstractConnection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);
	
	if (pageKey)
		[viewConnection->keyCache setObject:pageKey forKey:cacheKey];
	else
		[viewConnection->keyCache setObject:[NSNull null] forKey:cacheKey];
	
	return pageKey;
}

/**
 * Given a collection, and subset of keys, this method searches the 'keys' table to find all associated pageKeys.
 * 
 * The result is a dictionary, where the key is a pageKey, and the value is an NSSet
 * of all keys within that pageKey that belong to the given collection and within the given array of keys.
**/
- (NSDictionary *)pageKeysForKeys:(NSArray *)keys inCollection:(NSString *)collection
{
	if ([keys count] == 0)
	{
		return [NSDictionary dictionary];
	}
	
	if (collection == nil)
		collection = @"";
	
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[keys count]];
	
	__unsafe_unretained YapCollectionsDatabaseView *view =
	    (YapCollectionsDatabaseView *)(extensionConnection->extension);
	
	sqlite3 *db = databaseTransaction->abstractConnection->db;
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	NSUInteger keysIndex = 0;
	NSUInteger keysCount = [keys count];
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	
	do
	{
		NSUInteger keysLeft = keysCount - keysIndex;
		NSUInteger numKeyParams = MIN(keysLeft, (maxHostParams - 1)); // minus 1 for collection param
		
		// SELECT "key", "pageKey" FROM "keyTableName" WHERE collection = ? AND "key" IN (?, ?, ...);
		
		NSUInteger capacity = 50 + (numKeyParams * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendFormat:
		    @"SELECT \"key\", \"pageKey\" FROM \"%@\" WHERE \"collection\" = ? AND \"key\" IN (", [view keyTableName]];
		
		NSUInteger i;
		for (i = 0; i < numKeyParams; i++)
		{
			if (i == 0)
				[query appendFormat:@"?"];
			else
				[query appendFormat:@", ?"];
		}
		
		[query appendString:@");"];
		
		sqlite3_stmt *statement;
		int status;
		
		status = sqlite3_prepare_v2(db, [query UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ (%@): Error creating statement\n"
			            @" - status(%d), errmsg: %s\n"
			            @" - query: %@",
			            THIS_METHOD, [self registeredViewName], status, sqlite3_errmsg(db), query);
			
			break; // Break from do/while. Still need to free _collection.
		}
		
		sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		
		for (i = 0; i < numKeyParams; i++)
		{
			NSString *key = [keys objectAtIndex:(keysIndex + i)];
			
			sqlite3_bind_text(statement, (int)(i + 2), [key UTF8String], -1, SQLITE_TRANSIENT);
		}
		
		status = sqlite3_step(statement);
		while (status == SQLITE_ROW)
		{
			// Extract key & pageKey from row
			
			const unsigned char *text0 = sqlite3_column_text(statement, 0);
			int textSize0 = sqlite3_column_bytes(statement, 0);
			
			const unsigned char *text1 = sqlite3_column_text(statement, 1);
			int textSize1 = sqlite3_column_bytes(statement, 1);
			
			NSString *key = [[NSString alloc] initWithBytes:text0 length:textSize0 encoding:NSUTF8StringEncoding];
			NSString *pageKey = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
			
			// Add to result dictionary
			
			NSMutableSet *keysInPage = [result objectForKey:pageKey];
			if (keysInPage == nil)
			{
				keysInPage = [NSMutableSet setWithCapacity:1];
				[result setObject:keysInPage forKey:pageKey];
			}
			
			[keysInPage addObject:key];
			
			// Step to next row
			
			status = sqlite3_step(statement);
		}
		
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ (%@): Error executing statement: %d %s",
			            THIS_METHOD, [self registeredViewName], status, sqlite3_errmsg(db));
			
			break; // Break from do/while. Still need to free _collection.
		}
		
		keysIndex += numKeyParams;
	}
	while (keysIndex < keysCount);
	
	FreeYapDatabaseString(&_collection);
	
	return result;
}

/**
 * Given a collection, this method searches the 'keys' table to find all the associated keys and pageKeys.
 * 
 * The result is a dictionary, where the key is a pageKey, and the value is an NSSet
 * of all keys within that pageKey that belong to the given collection.
**/
- (NSDictionary *)pageKeysAndKeysForCollection:(NSString *)collection
{
	if (collection == nil)
		collection = @"";
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	sqlite3 *db = databaseTransaction->abstractConnection->db;
	
	sqlite3_stmt *statement = [viewConnection keyTable_enumerateForCollectionStatement];
	if (statement == NULL)
		return nil;
	
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	
	// SELECT "key", "pageKey" FROM "keyTableName" WHERE "collection" = ?;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	while (status == SQLITE_ROW)
	{
		// Extract key & pageKey from row
		
		const unsigned char *_key = sqlite3_column_text(statement, 0);
		int _keySize = sqlite3_column_bytes(statement, 0);
		
		const unsigned char *_pageKey = sqlite3_column_text(statement, 1);
		int _pageKeySize = sqlite3_column_bytes(statement, 1);
		
		NSString *key = [[NSString alloc] initWithBytes:_key length:_keySize encoding:NSUTF8StringEncoding];
		NSString *pageKey = [[NSString alloc] initWithBytes:_pageKey length:_pageKeySize encoding:NSUTF8StringEncoding];
		
		// Add to result dictionary
		
		NSMutableSet *keysInPage = [result objectForKey:pageKey];
		if (keysInPage == nil)
		{
			keysInPage = [NSMutableSet setWithCapacity:1];
			[result setObject:keysInPage forKey:pageKey];
		}
		
		[keysInPage addObject:key];
		
		// Step to next row
		
		status = sqlite3_step(statement);
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ (%@): Error executing statement: %d %s",
					THIS_METHOD, [self registeredViewName], status, sqlite3_errmsg(db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	
	return result;
}

/**
 * Fetches the page for the given pageKey.
 * 
 * This method will use the cache(s) if possible.
 * Otherwise it will load the data from the page table and deserialize it.
**/
- (YapCollectionsDatabaseViewPage *)pageForPageKey:(NSString *)pageKey
{
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	YapCollectionsDatabaseViewPage *page = nil;
	
	// Check dirty cache & clean cache
	
	page = [viewConnection->dirtyPages objectForKey:pageKey];
	if (page) return page;
	
	page = [viewConnection->pageCache objectForKey:pageKey];
	if (page) return page;
	
	// Otherwise pull from the database
	
	sqlite3_stmt *statement = [viewConnection pageTable_getDataForPageKeyStatement];
	if (statement == NULL)
		return nil;
	
	// SELECT data FROM 'pageTableName' WHERE pageKey = ? ;
	
	YapDatabaseString _pageKey; MakeYapDatabaseString(&_pageKey, pageKey);
	sqlite3_bind_text(statement, 1, _pageKey.str, _pageKey.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
		
		page = [self deserializePage:data];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ (%@): Error executing statement: %d %s",
		            THIS_METHOD, [self registeredViewName],
		            status, sqlite3_errmsg(databaseTransaction->abstractConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_pageKey);
	
	// Store in cache if found
	if (page)
		[viewConnection->pageCache setObject:page forKey:pageKey];
	
	return page;
}

- (NSString *)groupForPageKey:(NSString *)pageKey
{
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	return [viewConnection->pageKeyGroupDict objectForKey:pageKey];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Use this method (instead of removeKey:) when the pageKey and group are already known.
**/
- (void)removeKey:(NSString *)key
     inCollection:(NSString *)collection
      withPageKey:(NSString *)pageKey
            group:(NSString *)group
{
	YDBLogAutoTrace();
	
	if (key == nil) return;
	if (collection == nil)
		collection = @"";
	
	NSParameterAssert(pageKey != nil);
	NSParameterAssert(group != nil);
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	// Update page (by removing key from array)
	
	YapCollectionsDatabaseViewPage *page = [self pageForPageKey:pageKey];
	
	NSUInteger keyIndex = [page indexOfCollection:collection key:key];
	if (keyIndex == NSNotFound)
	{
		YDBLogError(@"%@ (%@): Collection(%@) Key(%@) expected to be in page(%@), but is missing",
		            THIS_METHOD, [self registeredViewName], collection, key, pageKey);
		return;
	}
	
	YDBLogVerbose(@"Removing key(%@) from page(%@) at index(%lu)", key, page, (unsigned long)keyIndex);
	
	[page removeObjectsAtIndex:keyIndex];
	NSUInteger pageCount = [page count];
	
	// Update page metadata (by decrementing count)
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	NSUInteger pageIndex = 0;
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->groupPagesDict objectForKey:group];
	
	for (YapDatabaseViewPageMetadata *pm in pagesMetadataForGroup)
	{
		if ([pm->pageKey isEqualToString:pageKey])
		{
			pageMetadata = pm;
			break;
		}
		
		pageIndex++;
	}
	
	pageMetadata->count = pageCount;
	
	// Mark page as dirty, or drop page
	
	if (pageCount > 0)
	{
		YDBLogVerbose(@"Dirty page(%@)", pageKey);
		
		// Mark page as dirty
		
		[viewConnection->dirtyPages setObject:page forKey:pageKey];
		[viewConnection->pageCache removeObjectForKey:pageKey];
		
		// Mark page metadata as dirty
		
		[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
	}
	else
	{
		YDBLogVerbose(@"Dropping empty page(%@)", pageKey);
		
		// Drop page
		
		[pagesMetadataForGroup removeObjectAtIndex:pageIndex];
		[viewConnection->pageKeyGroupDict removeObjectForKey:pageKey];
		
		// Mark page as dropped
		
		[viewConnection->dirtyPages setObject:[NSNull null] forKey:pageKey];
		[viewConnection->pageCache removeObjectForKey:pageKey];
		
		// Mark page metadata as dropped
		
		[viewConnection->dirtyMetadata setObject:[NSNull null] forKey:pageKey];
		
		// Update page metadata linked-list pointers
		
		if (pageIndex > 0)
		{
			// In pseudo-code:
			//
			// link->prev->next = link->next (except we only use next pointers)
			
			YapDatabaseViewPageMetadata *prevPageMetadata = [pagesMetadataForGroup objectAtIndex:(pageIndex - 1)];
			prevPageMetadata->nextPageKey = pageMetadata->nextPageKey;
			
			[viewConnection->dirtyMetadata setObject:prevPageMetadata forKey:prevPageMetadata->pageKey];
		}
		
		// Maybe drop group
		
		if ([pagesMetadataForGroup count] == 0)
		{
			YDBLogVerbose(@"Dropping empty group(%@)", group);
			
			[viewConnection->groupPagesDict removeObjectForKey:group];
		}
	}
	
	// Mark key for deletion
	
	YapCacheCollectionKey *cacheKey = [[YapCacheCollectionKey alloc] initWithCollection:collection key:key];
	
	[viewConnection->dirtyKeys setObject:[NSNull null] forKey:cacheKey];
	[viewConnection->keyCache removeObjectForKey:cacheKey];
	
	// Cleanup
	
	if (pageCount > 0)
	{
		[self maybeConsolidatePage:page atIndex:pageIndex inGroup:group withMetadata:pageMetadata];
	}
}

/**
 * Use this method to remove a set of 1 or more keys (in a single collection) from a given pageKey & group.
**/
- (void)removeKeys:(NSSet *)keys
      inCollection:(NSString *)collection
       withPageKey:(NSString *)pageKey
             group:(NSString *)group
{
	YDBLogAutoTrace();
	
	if ([keys count] < 2) // 0 or 1
	{
		[self removeKey:[keys anyObject] inCollection:collection withPageKey:pageKey group:group];
		return;
	}
	
	if (collection == nil)
		collection = @"";
	
	NSParameterAssert(pageKey != nil);
	NSParameterAssert(group != nil);
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	// Update page (by removing keys from array)
	
	YapCollectionsDatabaseViewPage *page = [self pageForPageKey:pageKey];
	
	NSMutableIndexSet *keyIndexSet = [NSMutableIndexSet indexSet];
	
	[page enumerateWithBlock:^(NSString *aCollection, NSString *aKey, NSUInteger idx, BOOL *stop) {
		
		if ([collection isEqualToString:aCollection])
		{
			if ([keys containsObject:aKey])
			{
				[keyIndexSet addIndex:idx];
			}
		}
	}];
	
	if ([keyIndexSet count] != [keys count])
	{
		YDBLogWarn(@"%@ (%@): Keys expected to be in page(%@), but are missing",
		           THIS_METHOD, [self registeredViewName], pageKey);
	}
	
	YDBLogVerbose(@"Removing %lu key(s) from page(%@)", (unsigned long)[keyIndexSet count], page);
	
	[page removeObjectsAtIndexes:keyIndexSet];
	NSUInteger pageCount = [page count];
	
	// Update page metadata (by decrementing count)
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	NSUInteger pageIndex = 0;
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->groupPagesDict objectForKey:group];
	
	for (YapDatabaseViewPageMetadata *pm in pagesMetadataForGroup)
	{
		if ([pm->pageKey isEqualToString:pageKey])
		{
			pageMetadata = pm;
			break;
		}
		
		pageIndex++;
	}
	
	pageMetadata->count = pageCount;
	
	// Mark page as dirty, or drop page
	
	if (pageCount > 0)
	{
		YDBLogVerbose(@"Dirty page(%@)", pageKey);
		
		// Mark page as dirty
		
		[viewConnection->dirtyPages setObject:page forKey:pageKey];
		[viewConnection->pageCache removeObjectForKey:pageKey];
		
		// Mark page metadata as dirty
		
		[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
	}
	else
	{
		YDBLogVerbose(@"Dropping empty page(%@)", pageKey);
		
		// Drop page
		
		[pagesMetadataForGroup removeObjectAtIndex:pageIndex];
		[viewConnection->pageKeyGroupDict removeObjectForKey:pageKey];
		
		// Mark page as dropped
		
		[viewConnection->dirtyPages setObject:[NSNull null] forKey:pageKey];
		[viewConnection->pageCache removeObjectForKey:pageKey];
		
		// Mark page metadata as dropped
		
		[viewConnection->dirtyMetadata setObject:[NSNull null] forKey:pageKey];
		
		// Update page metadata linked-list pointers
		
		if (pageIndex > 0)
		{
			// In pseudo-code:
			//
			// link->prev->next = link->next (except we only use next pointers)
			
			YapDatabaseViewPageMetadata *prevPageMetadata = [pagesMetadataForGroup objectAtIndex:(pageIndex - 1)];
			prevPageMetadata->nextPageKey = pageMetadata->nextPageKey;
			
			[viewConnection->dirtyMetadata setObject:prevPageMetadata forKey:prevPageMetadata->pageKey];
		}
		
		// Maybe drop group
		
		if ([pagesMetadataForGroup count] == 0)
		{
			YDBLogVerbose(@"Dropping empty group(%@)", group);
			
			[viewConnection->groupPagesDict removeObjectForKey:group];
		}
	}
	
	// Mark keys for deletion
	
	for (NSString *key in keys)
	{
		YapCacheCollectionKey *cacheKey = [[YapCacheCollectionKey alloc] initWithCollection:collection key:key];
		
		[viewConnection->dirtyKeys setObject:[NSNull null] forKey:cacheKey];
		[viewConnection->keyCache removeObjectForKey:cacheKey];
	}
}

/**
 * Use this method when you don't know if the collection/key exists in the view.
**/
- (void)removeKey:(NSString *)key inCollection:(NSString *)collection
{
	YDBLogAutoTrace();
	
	// Find out if collection/key is in view
	
	NSString *pageKey = [self pageKeyForKey:key inCollection:collection];
	if (pageKey)
	{
		[self removeKey:key inCollection:collection withPageKey:pageKey group:[self groupForPageKey:pageKey]];
	}
}

- (void)removeAllKeysInAllCollections
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	sqlite3_stmt *keyStatement = [viewConnection keyTable_removeAllStatement];
	sqlite3_stmt *pageStatement = [viewConnection pageTable_removeAllStatement];
	
	if (keyStatement == NULL || pageStatement == NULL)
		return;
	
	int status;
	
	// DELETE FROM "keyTableName";
	
	YDBLogVerbose(@"DELETE FROM '%@';", [self keyTableName]);
	
	status = sqlite3_step(keyStatement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ (%@): Error in keyStatement: %d %s",
		            THIS_METHOD, [self registeredViewName],
		            status, sqlite3_errmsg(databaseTransaction->abstractConnection->db));
	}
	
	// DELETE FROM 'pageTableName';
	
	YDBLogVerbose(@"DELETE FROM '%@';", [self pageTableName]);
	
	status = sqlite3_step(pageStatement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ (%@): Error in pageStatement: %d %s",
		            THIS_METHOD, [self registeredViewName],
		            status, sqlite3_errmsg(databaseTransaction->abstractConnection->db));
	}
	
	sqlite3_reset(keyStatement);
	sqlite3_reset(pageStatement);
	
	[viewConnection->groupPagesDict removeAllObjects];
	[viewConnection->pageKeyGroupDict removeAllObjects];
	
	[viewConnection->keyCache removeAllObjects];
	[viewConnection->pageCache removeAllObjects];
	
	[viewConnection->dirtyKeys removeAllObjects];
	[viewConnection->dirtyPages removeAllObjects];
	[viewConnection->dirtyMetadata removeAllObjects];
	
	viewConnection->reset = YES;
}

- (void)maybeConsolidatePage:(YapCollectionsDatabaseViewPage *)page
                     atIndex:(NSUInteger)pageIndex
                     inGroup:(NSString *)group
                withMetadata:(YapDatabaseViewPageMetadata *)metadata
{
	// Todo...
}

- (void)maybeExpandPage:(YapCollectionsDatabaseViewPage *)page
                atIndex:(NSUInteger)pageIndex
                inGroup:(NSString *)group
           withMetadata:(YapDatabaseViewPageMetadata *)metadata
{
	// Todo...
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapAbstractDatabaseExtensionTransaction_CollectionKeyValue
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleSetObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata inCollection:(NSString *)collection
{
	// Todo...
}

/**
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleSetMetadata:(id)metadata forKey:(NSString *)key inCollection:(NSString *)collection
{
	// Todo...
}

/**
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
	YDBLogAutoTrace();
	
	[self removeKey:key inCollection:collection];
}

/**
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection
{
	YDBLogAutoTrace();
	
	NSDictionary *dict = [self pageKeysForKeys:keys inCollection:collection];
	
	// dict.key = pageKey
	// dict.value = NSSet of keys within page (that match given keys & collection)
	
	[dict enumerateKeysAndObjectsUsingBlock:^(id pageKeyObj, id keysInPageObj, BOOL *stop) {
		
		__unsafe_unretained NSString *pageKey = (NSString *)pageKeyObj;
		__unsafe_unretained NSSet *keysInPage = (NSSet *)keysInPageObj;
		
		[self removeKeys:keysInPage inCollection:collection withPageKey:pageKey group:[self groupForPageKey:pageKey]];
	}];
	
	// Todo: page consolidation in modified groups
}

/**
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveAllObjectsInCollection:(NSString *)collection
{
	YDBLogAutoTrace();
	
	NSDictionary *dict = [self pageKeysAndKeysForCollection:collection];
	
	// dict.key = pageKey
	// dict.value = NSSet of keys within page (that match given collection)
	
	[dict enumerateKeysAndObjectsUsingBlock:^(id pageKeyObj, id keysInPageObj, BOOL *stop) {
		
		__unsafe_unretained NSString *pageKey = (NSString *)pageKeyObj;
		__unsafe_unretained NSSet *keysInPage = (NSSet *)keysInPageObj;
		
		[self removeKeys:keysInPage inCollection:collection withPageKey:pageKey group:[self groupForPageKey:pageKey]];
	}];
	
	// Todo: page consolidation in modified groups
}

/**
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveAllObjectsInAllCollections
{
	YDBLogAutoTrace();
	
	[self removeAllKeysInAllCollections];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)numberOfGroups
{
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	return [viewConnection->groupPagesDict count];
}

- (NSArray *)allGroups
{
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	return [viewConnection->groupPagesDict allKeys];
}

- (NSUInteger)numberOfKeysInGroup:(NSString *)group
{
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->groupPagesDict objectForKey:group];
	NSUInteger count = 0;
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		count += pageMetadata->count;
	}
	
	return count;
}

- (NSUInteger)numberOfKeysInAllGroups
{
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	NSUInteger count = 0;
	
	for (NSMutableArray *pagesForSection in [viewConnection->groupPagesDict objectEnumerator])
	{
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesForSection)
		{
			count += pageMetadata->count;
		}
	}
	
	return count;
}

- (BOOL)getKey:(NSString **)keyPtr
    collection:(NSString **)collectionPtr
       atIndex:(NSUInteger)index
       inGroup:(NSString *)group
{
	NSString *collection = nil;
	NSString *key = nil;
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->groupPagesDict objectForKey:group];
	NSUInteger pageOffset = 0;
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		if (index < (pageOffset + pageMetadata->count))
		{
			YapCollectionsDatabaseViewPage *page = [self pageForPageKey:pageMetadata->pageKey];
			
			[page getCollection:&collection key:&key atIndex:(index - pageOffset)];
		}
		else
		{
			pageOffset += pageMetadata->count;
		}
	}
	
	if (collectionPtr) *collectionPtr = collection;
	if (keyPtr) *keyPtr = key;
	
	return (collection && key);
}

- (NSString *)groupForKey:(NSString *)key inCollection:(NSString *)collection
{
	return [self groupForPageKey:[self pageKeyForKey:key inCollection:collection]];
}

- (BOOL)getGroup:(NSString **)groupPtr
           index:(NSUInteger *)indexPtr
          forKey:(NSString *)key
	inCollection:(NSString *)collection
{
	BOOL found = NO;
	NSString *group = nil;
	NSUInteger index = 0;
	
	// Query the database to see if the given key is in the view.
	// If it is, the query will return the corresponding page the key is in.
	
	NSString *pageKey = [self pageKeyForKey:key inCollection:collection];
	if (pageKey)
	{
		// Now that we have the pageKey, fetch the corresponding group.
		// This is done using an in-memory cache.
		
		group = [self groupForPageKey:pageKey];
		
		// Calculate the offset of the corresponding page within the group.
		
		__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	        (YapCollectionsDatabaseViewConnection *)extensionConnection;
		
		NSUInteger pageOffset = 0;
		NSMutableArray *pagesMetadataForGroup = [viewConnection->groupPagesDict objectForKey:group];
		
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
		{
			if ([pageMetadata->pageKey isEqualToString:pageKey])
			{
				break;
			}
			
			pageOffset += pageMetadata->count;
		}
		
		// Fetch the actual page (ordered array of keys)
		
		YapCollectionsDatabaseViewPage *page = [self pageForPageKey:pageKey];
		
		// And find the exact index of the key within the page
		
		NSUInteger keyIndexWithinPage = [page indexOfCollection:collection key:key];
		if (keyIndexWithinPage != NSNotFound)
		{
			index = pageOffset + keyIndexWithinPage;
			found = YES;
		}
	}
	
	if (groupPtr) *groupPtr = group;
	if (indexPtr) *indexPtr = index;
	
	return found;
}

@end
