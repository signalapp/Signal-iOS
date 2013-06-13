#import "YapCollectionsDatabaseViewTransaction.h"
#import "YapCollectionsDatabaseViewPrivate.h"
#import "YapDatabaseViewPageMetadata.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapCollectionsDatabaseTransaction.h"
#import "YapCache.h"
#import "YapCollectionKey.h"
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
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif


/**
 * ARCHITECTURE OVERVIEW:
 *
 * A YapCollectionsDatabaseView allows one to store a ordered array of collection/key tuples.
 * Furthermore, groups are supported, which means there may be multiple ordered arrays of tuples, one per group.
 *
 * Conceptually this is a very simple concept.
 * But obviously there are memory and performance requirements that add complexity.
 *
 * The view creates two database tables:
 *
 * view_name_key:
 * - collection (string) : from the database table
 * - key        (string) : from the database table
 * - pageKey    (string) : the primary key in the page table
 *
 * view_name_page:
 * - pageKey  (string, primary key) : a uuid
 * - data     (blob)                : an array of collection/key tuples (the page)
 * - metadata (blob)                : a YapDatabaseViewPageMetadata object
 *
 * For both tables "name" is replaced by the registered name of the view.
 *
 * Thus, given a key, we can quickly identify if the key exists in the view (via the key table).
 * And if so we can use the associated pageKey to figure out the group and index of the key.
 *
 * When we open the view, we read all the metadata objects from the page table into memory.
 * We use the metadata to create the two primary data structures:
 *
 * - group_pagesMetadata_dict (NSMutableDictionary) : key(group), value(array of YapDatabaseViewPageMetadata objects)
 * - pageKey_group_dict       (NSMutableDictionary) : key(pageKey), value(group)
 *
 * Given a group, we can use the group_pages_dict to find the associated array of pages (and metadata for each page).
 * Given a pageKey, we can use the pageKey_group_dict to quickly find the associated group.
**/
@implementation YapCollectionsDatabaseViewTransaction

- (BOOL)prepareIfNeeded
{
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	if (viewConnection->group_pagesMetadata_dict && viewConnection->pageKey_group_dict)
	{
		// Already prepared
		return YES;
	}
	
	__unsafe_unretained YapCollectionsDatabaseView *view =
	    (YapCollectionsDatabaseView *)(extensionConnection->extension);
	
	sqlite3 *db = databaseTransaction->abstractConnection->db;
	
	NSString *string = [NSString stringWithFormat:
	    @"SELECT \"pageKey\", \"metadata\" FROM \"%@\" ;", [view pageTableName]];
	
	sqlite3_stmt *statement;
	
	int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ (%@): Cannot create 'enumerate_stmt': %d %s",
		            THIS_METHOD, [self registeredViewName], status, sqlite3_errmsg(db));
		return NO;
	}
	
	// Enumerate over the page rows in the database, and populate our data structure.
	// Each row gives us the following fields:
	//
	// - group
	// - pageKey
	// - prevPageKey
	//
	// From this information we need to piece together the group_pagesMetadata_dict:
	// - dict.key = group
	// - dict.value = properly ordered array of YapDatabaseViewKeyPageMetadata objects
	//
	// To piece together the proper page order we make a temporary dictionary with each link in the linked-list.
	// For example:
	//
	// pageC.prevPage = pageB  =>      B -> C
	// pageB.prevPage = pageA  =>      A -> B
	// pageA.prevPage = nil    => NSNull -> A
	//
	// After the enumeration of all rows is complete, we can simply walk the linked list from the first page.
	
	NSMutableDictionary *groupPageDict = [[NSMutableDictionary alloc] init];
	NSMutableDictionary *groupOrderDict = [[NSMutableDictionary alloc] init];
	
	unsigned int stepCount = 0;
	
	while (sqlite3_step(statement) == SQLITE_ROW)
	{
		stepCount++;
		
		const unsigned char *text = sqlite3_column_text(statement, 0);
		int textSize = sqlite3_column_bytes(statement, 0);
		
		const void *blob = sqlite3_column_blob(statement, 1);
		int blobSize = sqlite3_column_bytes(statement, 1);
		
		NSString *pageKey = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
		
		id metadata = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		
		if ([metadata isKindOfClass:[YapDatabaseViewPageMetadata class]])
		{
			YapDatabaseViewPageMetadata *pageMetadata = (YapDatabaseViewPageMetadata *)metadata;
			pageMetadata->pageKey = pageKey;
			
			NSString *group = pageMetadata->group;
			
			NSMutableDictionary *pageDict = [groupPageDict objectForKey:group];
			if (pageDict == nil)
			{
				pageDict = [[NSMutableDictionary alloc] init];
				[groupPageDict setObject:pageDict forKey:group];
			}
			
			NSMutableDictionary *orderDict = [groupOrderDict objectForKey:group];
			if (orderDict == nil)
			{
				orderDict = [[NSMutableDictionary alloc] init];
				[groupOrderDict setObject:orderDict forKey:group];
			}
			
			[pageDict setObject:pageMetadata forKey:pageKey];
			
			if (pageMetadata->prevPageKey)
				[orderDict setObject:pageMetadata->pageKey forKey:pageMetadata->prevPageKey];
			else
				[orderDict setObject:pageMetadata->pageKey forKey:[NSNull null]];
		}
		else
		{
			YDBLogWarn(@"%@ (%@): Encountered unknown metadata class: %@",
					   THIS_METHOD, [self registeredViewName], [metadata class]);
		}
	}
	
	YDBLogVerbose(@"Processing %u items from %@...", stepCount, [view pageTableName]);
	
	YDBLogVerbose(@"groupPageDict: %@", groupPageDict);
	YDBLogVerbose(@"groupOrderDict: %@", groupOrderDict);
	
	__block BOOL error = ((status != SQLITE_OK) && (status != SQLITE_DONE));
	
	if (error)
	{
		YDBLogError(@"%@ (%@): Error enumerating page table: %d %s",
		            THIS_METHOD, [self registeredViewName], status, sqlite3_errmsg(db));
	}
	else
	{
		// Initialize ivars in viewConnection.
		// We try not to do this before we know the table exists.
		
		viewConnection->group_pagesMetadata_dict = [[NSMutableDictionary alloc] init];
		viewConnection->pageKey_group_dict = [[NSMutableDictionary alloc] init];
		
		// Enumerate over each group
		
		[groupOrderDict enumerateKeysAndObjectsUsingBlock:^(id _group, id _orderDict, BOOL *stop) {
			
			NSString *group = (NSString *)_group;
			NSMutableDictionary *orderDict = (NSMutableDictionary *)_orderDict;
			
			NSMutableDictionary *pageDict = [groupPageDict objectForKey:group];
			
			// Walk the linked-list to stitch together the pages for this section.
			//
			// NSNull -> firstPageKey
			// firstPageKey -> secondPageKey
			// ...
			// secondToLastPageKey -> lastPageKey
			//
			// And from the keys, we can get the actual pageMetadata using the pageDict.
			
			NSMutableArray *pagesForGroup = [[NSMutableArray alloc] initWithCapacity:[pageDict count]];
			[viewConnection->group_pagesMetadata_dict setObject:pagesForGroup forKey:group];
			
			YapDatabaseViewPageMetadata *prevPageMetadata = nil;
			
			NSString *pageKey = [orderDict objectForKey:[NSNull null]];
			while (pageKey)
			{
				[viewConnection->pageKey_group_dict setObject:group forKey:pageKey];
				
				YapDatabaseViewPageMetadata *pageMetadata = [pageDict objectForKey:pageKey];
				if (pageMetadata == nil)
				{
					YDBLogError(@"%@ (%@): Invalid key ordering detected in group(%@)",
					            THIS_METHOD, [self registeredViewName], group);
					
					error = YES;
					break;
				}
				
				[pagesForGroup insertObject:pageMetadata atIndex:0];
				
				if (prevPageMetadata)
					prevPageMetadata->nextPageKey = pageKey;
				
				prevPageMetadata = pageMetadata;
				pageKey = [orderDict objectForKey:pageKey];
				
				if ([pagesForGroup count] > [orderDict count])
				{
					YDBLogError(@"%@ (%@): Circular key ordering detected in group(%@)",
					            THIS_METHOD, [self registeredViewName], group);
					
					error = YES;
					break;
				}
			}
			
			// Validate data for this section
			
			if (!error && ([pagesForGroup count] != [orderDict count]))
			{
				YDBLogError(@"%@ (%@): Missing key page(s) in group(%@)",
				            THIS_METHOD, [self registeredViewName], group);
				
				error = YES;
			}
		}];
	}
	
	// Validate data
	
	if (error)
	{
		// If there was an error opening the view, we need to reset the ivars to nil.
		// These are checked at the beginning of this method as a shortcut.
		
		viewConnection->group_pagesMetadata_dict = nil;
		viewConnection->pageKey_group_dict = nil;
	}
	else
	{
		YDBLogVerbose(@"viewConnection->group_pagesMetadata_dict: %@", viewConnection->group_pagesMetadata_dict);
		YDBLogVerbose(@"viewConnection->pageKey_group_dict: %@", viewConnection->pageKey_group_dict);
		
		viewConnection->dirtyKeys = [[NSMutableDictionary alloc] init];
		viewConnection->dirtyPages = [[NSMutableDictionary alloc] init];
		viewConnection->dirtyMetadata = [[NSMutableDictionary alloc] init];
	}
	
	sqlite3_finalize(statement);
	return !error;
}

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
#pragma mark YapCollectionsDatabaseView
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSData *)serializePage:(NSMutableArray *)page
{
	return [NSKeyedArchiver archivedDataWithRootObject:page];
}

- (NSMutableArray *)deserializePage:(NSData *)data
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
- (NSString *)pageKeyForCollectionKey:(YapCollectionKey *)collectionKey
{
	NSParameterAssert(collectionKey != nil);
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	NSString *pageKey = nil;
	
	// Check dirty cache & clean cache
	
	pageKey = [viewConnection->dirtyKeys objectForKey:collectionKey];
	if (pageKey)
	{
		if ((__bridge void *)pageKey == (__bridge void *)[NSNull null])
			return nil;
		else
			return pageKey;
	}
	
	pageKey = [viewConnection->keyCache objectForKey:collectionKey];
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
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collectionKey.collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, collectionKey.key);
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
		YDBLogError(@"%@ (%@): Error executing statement: %d %s, collection(%@) key(%@)",
		            THIS_METHOD, [self registeredViewName],
		            status, sqlite3_errmsg(databaseTransaction->abstractConnection->db),
		            collectionKey.collection, collectionKey.key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);
	
	if (pageKey)
		[viewConnection->keyCache setObject:pageKey forKey:collectionKey];
	else
		[viewConnection->keyCache setObject:[NSNull null] forKey:collectionKey];
	
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
	NSParameterAssert(collection != nil);
	
	if ([keys count] == 0)
	{
		return [NSDictionary dictionary];
	}
	
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
	NSParameterAssert(collection != nil);
	
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
- (NSMutableArray *)pageForPageKey:(NSString *)pageKey
{
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	NSMutableArray *page = nil;
	
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
	
	return [viewConnection->pageKey_group_dict objectForKey:pageKey];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Use this method once the insertion index of a key is known.
 * 
 * Note: This method assumes the group already exists.
**/
- (void)insertCollectionKey:(YapCollectionKey *)collectionKey
                    inGroup:(NSString *)group
                    atIndex:(NSUInteger)index
        withExistingPageKey:(NSString *)existingPageKey
{
	YDBLogAutoTrace();
	
	NSParameterAssert(collectionKey != nil);
	NSParameterAssert(group != nil);
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	// Find pageMetadata, pageKey and page
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:group];
	
	NSUInteger pagesCount = [pagesMetadataForGroup count];
	NSUInteger lastPageIndex = (pagesCount > 0) ? (pagesCount - 1) : 0;
	
	NSUInteger pageOffset = 0;
	NSUInteger pageIndex = 0;
	
	for (YapDatabaseViewPageMetadata *pm in pagesMetadataForGroup)
	{
		// Edge case: key is being inserted at the very end.
		//
		// index == numberOfKeysInTheEntireGroup
		
		if ((index < (pageOffset + pm->count)) || (pageIndex == lastPageIndex))
		{
			pageMetadata = pm;
			break;
		}
		
		pageIndex++;
		pageOffset += pm->count;
	}
	
	NSString *pageKey = pageMetadata->pageKey;
	NSMutableArray *page = [self pageForPageKey:pageKey];
	
	YDBLogVerbose(@"Inserting key(%@) collection(%@) in group(%@) at index(%lu) with page(%@) pageOffset(%lu)",
	              collectionKey.key, collectionKey.collection, group,
	              (unsigned long)index, pageKey, (unsigned long)(index - pageOffset));
	
	// Update page
	
	[page insertObject:collectionKey atIndex:(index - pageOffset)];
	
	[viewConnection->dirtyPages setObject:page forKey:pageKey];
	[viewConnection->pageCache removeObjectForKey:pageKey];
	
	// Update page metadata (by incrementing count)
	
	pageMetadata->count = [page count]; // number of keys in page
	[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
	
	// Mark key for insertion
	
	if (![pageKey isEqualToString:existingPageKey])
	{
		[viewConnection->dirtyKeys setObject:pageKey forKey:collectionKey];
		[viewConnection->keyCache removeObjectForKey:collectionKey];
	}
}

/**
 * Use this method after it has been determined that the key should be inserted into the given group.
 * The object and metadata parameters must be properly set (if needed by the sorting block).
 * 
 * This method will use the configured sorting block to find the proper index for the key.
 * It will attempt to optimize this operation as best as possible using a variety of techniques.
**/
- (void)insertCollectionKey:(YapCollectionKey *)collectionKey
                 withObject:(id)object
                   metadata:(id)metadata
                    inGroup:(NSString *)group
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapCollectionsDatabaseView *view =
	    (YapCollectionsDatabaseView *)(extensionConnection->extension);
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	// Is the key already in the group?
	// If so:
	// - its index within the group may or may not have changed.
	// - we can use its existing position as an optimization during sorting.
	
	BOOL tryExistingIndexInGroup = NO;
	
	NSString *existingPageKey = [self pageKeyForCollectionKey:collectionKey];
	if (existingPageKey)
	{
		// The key is already in the view.
		// Has it changed groups?
		
		NSString *existingGroup = [self groupForPageKey:existingPageKey];
		
		if ([group isEqualToString:existingGroup])
		{
			// The key is already in the group.
			
			if (view->sortingBlockType == YapCollectionsDatabaseViewBlockTypeWithKey)
			{
				// Sorting is based entirely on the key, which hasn't changed.
				// Thus the position within the view hasn't changed.
				return;
			}
			else
			{
				// Possible optimization:
				// Object or metadata was updated, but doesn't affect the position of the row within the view.
				tryExistingIndexInGroup = YES;
			}
		}
		else
		{
			[self removeCollectionKey:collectionKey withPageKey:existingPageKey group:existingGroup];
			
			// Don't forget to reset the existingPageKey ivar!
			// Or else 'insertKey:inGroup:atIndex:withExistingPageKey:' will be given an invalid existingPageKey.
			existingPageKey = nil;
		}
	}
	
	// Fetch the pages associated with the group.
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:group];
	
	if (pagesMetadataForGroup == nil)
	{
		// First object added to group.
		
		NSString *pageKey = [self generatePageKey];
		
		YDBLogVerbose(@"Inserting key(%@) collection(%@) in new group(%@) with page(%@)",
		              collectionKey.key, collectionKey.collection, group, pageKey);
		
		YapDatabaseViewPageMetadata *pageMetadata = [[YapDatabaseViewPageMetadata alloc] init];
		pageMetadata->pageKey = pageKey;
		pageMetadata->nextPageKey = nil;
		pageMetadata->group = group;
		pageMetadata->count = 1;
		
		pagesMetadataForGroup = [[NSMutableArray alloc] initWithCapacity:1];
		[pagesMetadataForGroup addObject:pageMetadata];
		
		NSMutableArray *page = [NSMutableArray arrayWithCapacity:1];
		[page addObject:collectionKey];
		
		[viewConnection->group_pagesMetadata_dict setObject:pagesMetadataForGroup forKey:group];
		[viewConnection->pageKey_group_dict setObject:group forKey:pageKey];
		
		[viewConnection->dirtyPages setObject:page forKey:pageKey];
		[viewConnection->pageCache removeObjectForKey:pageKey];
		
		[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
		
		[viewConnection->dirtyKeys setObject:pageKey forKey:collectionKey];
		[viewConnection->keyCache removeObjectForKey:collectionKey];
	}
	else
	{
		// Calculate out how many keys are in the group.
		
		NSUInteger count = 0;
		
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
		{
			count += pageMetadata->count;
		}
		
		// Create a block to do a single sorting comparison between the object to be inserted,
		// and some other object within the group at a given index.
		// 
		// This block will be invoked repeatedly as we calculate the insertion index.
		
		NSComparisonResult (^compare)(NSUInteger) = ^NSComparisonResult (NSUInteger index){
			
			YapCollectionKey *another = nil;
			
			NSUInteger pageOffset = 0;
			for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
			{
				if (index < (pageOffset + pageMetadata->count))
				{
					NSMutableArray *page = [self pageForPageKey:pageMetadata->pageKey];
					
					another = [page objectAtIndex:(index - pageOffset)];
					break;
				}
				else
				{
					pageOffset += pageMetadata->count;
				}
			}
			
			if (view->sortingBlockType == YapCollectionsDatabaseViewBlockTypeWithKey)
			{
				__unsafe_unretained YapCollectionsDatabaseViewSortingWithKeyBlock sortingBlock =
				    (YapCollectionsDatabaseViewSortingWithKeyBlock)view->sortingBlock;
				
				return sortingBlock(group, collectionKey.collection, collectionKey.key,
				                                 another.collection,       another.key);
			}
			else if (view->sortingBlockType == YapCollectionsDatabaseViewBlockTypeWithObject)
			{
				__unsafe_unretained YapCollectionsDatabaseViewSortingWithObjectBlock sortingBlock =
				    (YapCollectionsDatabaseViewSortingWithObjectBlock)view->sortingBlock;
				
				id anotherObject = [self objectForKey:another.key inCollection:another.collection];
				
				return sortingBlock(group, collectionKey.collection, collectionKey.key,        object,
				                                 another.collection,       another.key, anotherObject);
			}
			else if (view->sortingBlockType == YapCollectionsDatabaseViewBlockTypeWithMetadata)
			{
				__unsafe_unretained YapCollectionsDatabaseViewSortingWithMetadataBlock sortingBlock =
				    (YapCollectionsDatabaseViewSortingWithMetadataBlock)view->sortingBlock;
				
				id anotherMetadata = [self metadataForKey:another.key inCollection:another.collection];;
				
				return sortingBlock(group, collectionKey.collection, collectionKey.key,        metadata,
				                                 another.collection,       another.key, anotherMetadata);
			}
			else
			{
				__unsafe_unretained YapCollectionsDatabaseViewSortingWithObjectAndMetadataBlock sortingBlock =
				    (YapCollectionsDatabaseViewSortingWithObjectAndMetadataBlock)view->sortingBlock;
				
				id anotherObject = nil;
				id anotherMetadata = nil;
				
				[self getObject:&anotherObject
				       metadata:&anotherMetadata
				         forKey:another.key
				   inCollection:another.collection];
				
				return sortingBlock(group, collectionKey.collection, collectionKey.key,        object,        metadata,
				                                 another.collection,       another.key, anotherObject, anotherMetadata);
			}
		};
		
		NSComparisonResult cmp;
		
		// Optimization 1:
		//
		// If the key is already in the group, check to see if its index is the same as before.
		// This handles the common case where an object is updated without changing its position within the view.
		
		if (tryExistingIndexInGroup)
		{
			NSMutableArray *existingPage = [self pageForPageKey:existingPageKey];
			
			NSUInteger existingPageOffset = 0;
			for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
			{
				if ([pageMetadata->pageKey isEqualToString:existingPageKey])
					break;
				else
					existingPageOffset += pageMetadata->count;
			}
			
			NSUInteger existingIndex = existingPageOffset + [existingPage indexOfObject:collectionKey];
			
			// Edge case: existing key is the only key in the group
			//
			// (existingIndex == 0) && (count == 1)
			
			BOOL useExistingIndexInGroup = YES;
			
			if (existingIndex > 0)
			{
				cmp = compare(existingIndex - 1); // compare vs prev
				
				useExistingIndexInGroup = (cmp != NSOrderedAscending); // object >= prev
			}
			
			if ((existingIndex + 1) < count && useExistingIndexInGroup)
			{
				cmp = compare(existingIndex + 1); // compare vs next
				
				useExistingIndexInGroup = (cmp != NSOrderedDescending); // object <= next
			}
			
			if (useExistingIndexInGroup)
			{
				// The key doesn't change position.
				
				YDBLogVerbose(@"Updated key(%@) in group(%@) maintains current index", collectionKey.key, group);
				return;
			}
			else
			{
				// The key has changed position.
				// Remove it from previous position (and don't forget to decrement count).
				
				[self removeCollectionKey:collectionKey withPageKey:existingPageKey group:group];
				count--;
				
				// Don't forget to reset the existingPageKey ivar!
				// Or else 'insertKey:inGroup:atIndex:withExistingPageKey:' will be given an invalid existingPageKey.
				existingPageKey = nil;
			}
		}
		
		// Optimization 2:
		//
		// A very common operation is to insert objects at the beginning or end of the array.
		// We attempt to notice this trend and optimize around it.
		
		if (viewConnection->lastInsertWasAtFirstIndex && (count > 1))
		{
			cmp = compare(0);
			
			if (cmp == NSOrderedAscending) // object < first
			{
				YDBLogVerbose(@"Insert key(%@) collection(%@) in group(%@) at beginning (optimization)",
				              collectionKey.key, collectionKey.collection, group);
				
				[self insertCollectionKey:collectionKey
				                  inGroup:group
				                  atIndex:0
				      withExistingPageKey:existingPageKey];
				return;
			}
		}
		
		if (viewConnection->lastInsertWasAtLastIndex && (count > 1))
		{
			cmp = compare(count - 1);
			
			if (cmp != NSOrderedAscending) // object >= last
			{
				YDBLogVerbose(@"Insert key(%@) collection(%@) in group(%@) at end (optimization)",
				              collectionKey.key, collectionKey.collection, group);
				
				[self insertCollectionKey:collectionKey
				                  inGroup:group
				                  atIndex:count
				      withExistingPageKey:existingPageKey];
				return;
			}
		}
		
		// Otherwise:
		//
		// Binary search operation.
		//
		// This particular algorithm accounts for cases where the objects are not unique.
		// That is, if some objects are NSOrderedSame, then the algorithm returns the largest index possible
		// (within the region where elements are "equal").
		
		NSUInteger loopCount = 0;
		
		NSUInteger min = 0;
		NSUInteger max = count;
		
		while (min < max)
		{
			NSUInteger mid = (min + max) / 2;
			
			cmp = compare(mid);
			
			if (cmp == NSOrderedAscending)
				max = mid;
			else
				min = mid + 1;
			
			loopCount++;
		}
		
		YDBLogVerbose(@"Insert key(%@) collection(%@) in group(%@) took %lu comparisons",
		              collectionKey.key, collectionKey.collection, group, (unsigned long)loopCount);
		
		[self insertCollectionKey:collectionKey inGroup:group atIndex:min withExistingPageKey:existingPageKey];
		
		viewConnection->lastInsertWasAtFirstIndex = (min == 0);
		viewConnection->lastInsertWasAtLastIndex  = (min == count);
	}
}

/**
 * Use this method (instead of removeKey:) when the pageKey and group are already known.
**/
- (void)removeCollectionKey:(YapCollectionKey *)collectionKey
                withPageKey:(NSString *)pageKey
                      group:(NSString *)group
{
	YDBLogAutoTrace();
	
	NSParameterAssert(collectionKey != nil);
	NSParameterAssert(pageKey != nil);
	NSParameterAssert(group != nil);
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	// Update page (by removing key from array)
	
	NSMutableArray *page = [self pageForPageKey:pageKey];
	
	NSUInteger keyIndex = [page indexOfObject:collectionKey];
	if (keyIndex == NSNotFound)
	{
		YDBLogError(@"%@ (%@): Collection(%@) Key(%@) expected to be in page(%@), but is missing",
		            THIS_METHOD, [self registeredViewName], collectionKey.collection, collectionKey.key, pageKey);
		return;
	}
	
	YDBLogVerbose(@"Removing collection(%@) key(%@) from page(%@) at index(%lu)",
	              collectionKey.collection, collectionKey.key, page, (unsigned long)keyIndex);
	
	[page removeObjectAtIndex:keyIndex];
	NSUInteger pageCount = [page count];
	
	// Update page metadata (by decrementing count)
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	NSUInteger pageIndex = 0;
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:group];
	
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
	
	YDBLogVerbose(@"Dirty page(%@)", pageKey);
	
	// Mark page as dirty
	
	[viewConnection->dirtyPages setObject:page forKey:pageKey];
	[viewConnection->pageCache removeObjectForKey:pageKey];
	
	// Mark page metadata as dirty
	
	[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
	
	// Mark key for deletion
	
	[viewConnection->dirtyKeys setObject:[NSNull null] forKey:collectionKey];
	[viewConnection->keyCache removeObjectForKey:collectionKey];
}

/**
 * Use this method when you don't know if the collection/key exists in the view.
**/
- (void)removeCollectionKey:(YapCollectionKey *)collectionKey
{
	YDBLogAutoTrace();
	
	// Find out if collection/key is in view
	
	NSString *pageKey = [self pageKeyForCollectionKey:collectionKey];
	if (pageKey)
	{
		[self removeCollectionKey:collectionKey withPageKey:pageKey group:[self groupForPageKey:pageKey]];
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
	
	if ([keys count] == 0) return;
	if ([keys count] == 1)
	{
		NSString *key = [keys anyObject];
		YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		[self removeCollectionKey:collectionKey withPageKey:pageKey group:group];
		return;
	}
	
	NSParameterAssert(collection != nil);
	NSParameterAssert(pageKey != nil);
	NSParameterAssert(group != nil);
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	// Update page (by removing keys from array)
	
	NSMutableArray *page = [self pageForPageKey:pageKey];
	
	NSIndexSet *indexesToRemove = [page indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
		
		__unsafe_unretained YapCollectionKey *collectionKey = (YapCollectionKey *)obj;
		
		if ([collection isEqualToString:collectionKey.collection])
		{
			if ([keys containsObject:collectionKey.key])
			{
				return YES;
			}
		}
		
		return NO;
	}];
	
	if ([indexesToRemove count] != [keys count])
	{
		YDBLogWarn(@"%@ (%@): Keys expected to be in page(%@), but are missing",
		           THIS_METHOD, [self registeredViewName], pageKey);
	}
	
	YDBLogVerbose(@"Removing %lu key(s) from page(%@)", (unsigned long)[indexesToRemove count], page);
	
	[page removeObjectsAtIndexes:indexesToRemove];
	NSUInteger pageCount = [page count];
	
	// Update page metadata (by decrementing count)
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	NSUInteger pageIndex = 0;
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:group];
	
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
	
	YDBLogVerbose(@"Dirty page(%@)", pageKey);
	
	// Mark page as dirty
	
	[viewConnection->dirtyPages setObject:page forKey:pageKey];
	[viewConnection->pageCache removeObjectForKey:pageKey];
	
	// Mark page metadata as dirty
	
	[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
	
	// Mark keys for deletion
	
	for (NSString *key in keys)
	{
		YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		[viewConnection->dirtyKeys setObject:[NSNull null] forKey:collectionKey];
		[viewConnection->keyCache removeObjectForKey:collectionKey];
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
	
	[viewConnection->group_pagesMetadata_dict removeAllObjects];
	[viewConnection->pageKey_group_dict removeAllObjects];
	
	[viewConnection->keyCache removeAllObjects];
	[viewConnection->pageCache removeAllObjects];
	
	[viewConnection->dirtyKeys removeAllObjects];
	[viewConnection->dirtyPages removeAllObjects];
	[viewConnection->dirtyMetadata removeAllObjects];
	
	viewConnection->reset = YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cleanup & Commit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)splitOversizedPage:(YapDatabaseViewPageMetadata *)pageMetadata
{
	int maxPageSize = 50; // Todo...
	
	YDBLogAutoTrace();
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	NSUInteger overflow = pageMetadata->count - maxPageSize;
	
	// Find page
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:pageMetadata->group];
	
	NSUInteger pageIndex = [pagesMetadataForGroup indexOfObject:pageMetadata];
	
	// Check to see if there's room in the previous page
	
	if (pageIndex > 0)
	{
		YapDatabaseViewPageMetadata *prevPageMetadata = [pagesMetadataForGroup objectAtIndex:(pageIndex - 1)];
		
		if (prevPageMetadata->count + overflow <= maxPageSize)
		{
			// Move objects from beginning of page to end of previous page
			
			NSMutableArray *page = [self pageForPageKey:pageMetadata->pageKey];
			NSMutableArray *prevPage = [self pageForPageKey:prevPageMetadata->pageKey];
			
			NSRange pageRange = NSMakeRange(0, overflow);                    // beginning range
			NSRange prevPageRange = NSMakeRange([prevPage count], overflow); // end range
			
			NSArray *subset = [page subarrayWithRange:pageRange];
			
			[page removeObjectsInRange:pageRange];
			[prevPage insertObjects:subset atIndexes:[NSIndexSet indexSetWithIndexesInRange:prevPageRange]];
			
			// Update counts
			
			pageMetadata->count = [page count];
			prevPageMetadata->count = [prevPage count];
			
			// Mark page & pageMetadata as dirty
			
			[viewConnection->dirtyPages setObject:prevPage forKey:prevPageMetadata->pageKey];
			[viewConnection->pageCache removeObjectForKey:prevPageMetadata->pageKey];
			
			[viewConnection->dirtyMetadata setObject:prevPageMetadata forKey:prevPageMetadata->pageKey];
			
			// Mark keys as dirty
			
			for (NSString *key in subset)
			{
				[viewConnection->dirtyKeys setObject:prevPageMetadata->pageKey forKey:key];
				[viewConnection->keyCache removeObjectForKey:key];
			}
			
			return;
		}
	}
	
	// Check to see if there's room in the next page
	
	if ((pageIndex + 1) < [pagesMetadataForGroup count])
	{
		YapDatabaseViewPageMetadata *nextPageMetadata = [pagesMetadataForGroup objectAtIndex:(pageIndex + 1)];
		
		if (nextPageMetadata->count + overflow <= maxPageSize)
		{
			// Move objects from end of page to beginning of next page
			
			NSMutableArray *page = [self pageForPageKey:pageMetadata->pageKey];
			NSMutableArray *nextPage = [self pageForPageKey:nextPageMetadata->pageKey];
			
			NSRange pageRange = NSMakeRange(maxPageSize, overflow); // end range
			NSRange nextPageRange = NSMakeRange(0, overflow);       // beginning range
			
			NSArray *subset = [page subarrayWithRange:pageRange];
			
			[page removeObjectsInRange:pageRange];
			[nextPage insertObjects:subset atIndexes:[NSIndexSet indexSetWithIndexesInRange:nextPageRange]];
			
			// Update counts
			
			pageMetadata->count = [page count];
			nextPageMetadata->count = [nextPage count];
			
			// Mark page & pageMetadata as dirty
			
			[viewConnection->dirtyPages setObject:nextPage forKey:nextPageMetadata->pageKey];
			[viewConnection->pageCache removeObjectForKey:nextPageMetadata->pageKey];
			
			[viewConnection->dirtyMetadata setObject:nextPageMetadata forKey:nextPageMetadata->pageKey];
			
			// Mark keys as dirty
			
			for (NSString *key in subset)
			{
				[viewConnection->dirtyKeys setObject:nextPageMetadata->pageKey forKey:key];
				[viewConnection->keyCache removeObjectForKey:key];
			}
			
			return;
		}
	}
	
	// Create new page and pageMetadata.
	// Insert into array.
	
	NSString *newPageKey = [self generatePageKey];
	NSMutableArray *newPage = [[NSMutableArray alloc] initWithCapacity:overflow];
	
	// Create new pageMetadata
	
	YapDatabaseViewPageMetadata *newPageMetadata = [[YapDatabaseViewPageMetadata alloc] init];
	newPageMetadata->pageKey = newPageKey;
	newPageMetadata->group = pageMetadata->group;
	
	// Insert new pageMetadata into array & update linked-list
	
	[pagesMetadataForGroup insertObject:newPageMetadata atIndex:(pageIndex + 1)];
	
	[viewConnection->pageKey_group_dict setObject:newPageMetadata->group
	                                       forKey:newPageMetadata->pageKey];
	
	newPageMetadata->prevPageKey = pageMetadata->pageKey;
	pageMetadata->nextPageKey = newPageKey;
	
	if ((pageIndex + 2) < [pagesMetadataForGroup count])
	{
		YapDatabaseViewPageMetadata *nextPageMetadata = [pagesMetadataForGroup objectAtIndex:(pageIndex + 2)];
		
		newPageMetadata->nextPageKey = nextPageMetadata->pageKey;
		nextPageMetadata->prevPageKey = newPageKey;
	}
	
	// Move objects from end of page to beginning of new page
	
	NSMutableArray *page = [self pageForPageKey:pageMetadata->pageKey];
	
	NSRange pageRange = NSMakeRange(maxPageSize, overflow); // end range
	
	NSArray *subset = [page subarrayWithRange:pageRange];
	
	[page removeObjectsInRange:pageRange];
	[newPage addObjectsFromArray:subset];
	
	// Update counts
	
	pageMetadata->count = [page count];
	newPageMetadata->count = [newPage count];
	
	// Mark page & pageMetadata as dirty
	
	[viewConnection->dirtyPages setObject:newPage forKey:newPageKey];
	[viewConnection->dirtyMetadata setObject:newPageMetadata forKey:newPageKey];
	
	// Mark keys as dirty
	
	for (NSString *key in subset)
	{
		[viewConnection->dirtyKeys setObject:newPageKey forKey:key];
		[viewConnection->keyCache removeObjectForKey:key];
	}
}

- (void)dropEmptyPage:(YapDatabaseViewPageMetadata *)pageMetadata
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	// Find page
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:pageMetadata->group];
	
	NSUInteger pageIndex = [pagesMetadataForGroup indexOfObject:pageMetadata];
	
	// Update surrounding pages
	
	if (pageIndex > 0)
	{
		YapDatabaseViewPageMetadata *prevPageMetadata = [pagesMetadataForGroup objectAtIndex:(pageIndex - 1)];
		prevPageMetadata->nextPageKey = pageMetadata->nextPageKey;
		
		// The nextPageKey property is transient (not saved to disk).
		// So this change doesn't affect on-disk representation.
	}
	
	if ((pageIndex + 1) < [pagesMetadataForGroup count])
	{
		YapDatabaseViewPageMetadata *nextPageMetadata = [pagesMetadataForGroup objectAtIndex:(pageIndex + 1)];
		nextPageMetadata->prevPageKey = pageMetadata->prevPageKey;
		
		// The prevPageKey property is persistent (saved to disk).
		// So this change affects the on-disk representation.
		
		[viewConnection->dirtyMetadata setObject:nextPageMetadata forKey:nextPageMetadata->pageKey];
	}
	
	// Drop page
	
	[pagesMetadataForGroup removeObjectAtIndex:pageIndex];
	[viewConnection->pageKey_group_dict removeObjectForKey:pageMetadata->pageKey];
	
	// Mark page as dropped
	
	[viewConnection->dirtyPages setObject:[NSNull null] forKey:pageMetadata->pageKey];
	[viewConnection->pageCache removeObjectForKey:pageMetadata->pageKey];
	
	// Mark page metadata as dropped
	
	[viewConnection->dirtyMetadata setObject:[NSNull null] forKey:pageMetadata->pageKey];
	
	// Maybe drop group
	
	if ([pagesMetadataForGroup count] == 0)
	{
		YDBLogVerbose(@"Dropping empty group(%@)", pageMetadata->group);
		
		[viewConnection->group_pagesMetadata_dict removeObjectForKey:pageMetadata->group];
	}
}

- (void)maybeConsolidateOrExpandDirtyPages
{
	int maxPageSize = 50; // Todo...
	
	YDBLogAutoTrace();
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	// Get all the dirty pageMetadata objects.
	// We snapshot the items so we can make modifications as we enumerate.
	
	NSArray *allDirtyPageMetadata = [viewConnection->dirtyMetadata allValues];
	
	// Step 1 is to "expand" the oversized pages.
	//
	// This means either splitting them in 2,
	// or allowing items to spill over into a neighboring page (that has room).
	
	for (YapDatabaseViewPageMetadata *pageMetadata in allDirtyPageMetadata)
	{
		if (pageMetadata->count > maxPageSize)
		{
			[self splitOversizedPage:pageMetadata];
		}
	}
	
	// Step 2 is to "collapse" undersized pages.
	//
	// This means dropping empty pages,
	// and maybe combining a page with a neighboring page (that has room).
	//
	// Note: We do this after "expansion" to allow undersized pages to first accomodate overflow.
	
	for (YapDatabaseViewPageMetadata *pageMetadata in allDirtyPageMetadata)
	{
		if (pageMetadata->count == 0)
		{
			[self dropEmptyPage:pageMetadata];
		}
	}
}

- (void)commitTransaction
{
	YDBLogAutoTrace();
	
	// During the transaction we stored all changes in the "dirty" dictionaries.
	// This allows the view to make multiple changes to a page, yet only write it once.
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	[self maybeConsolidateOrExpandDirtyPages];
	
	YDBLogVerbose(@"viewConnection->dirtyPages: %@", viewConnection->dirtyPages);
	YDBLogVerbose(@"viewConnection->dirtyMetadata: %@", viewConnection->dirtyMetadata);
	YDBLogVerbose(@"viewConnection->dirtyKeys: %@", viewConnection->dirtyKeys);
	
	// Write dirty pages to table (along with associated dirty metadata)
	
	[viewConnection->dirtyPages enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		NSString *pageKey = (NSString *)key;
		NSMutableArray *page = (NSMutableArray *)obj;
		
		YapDatabaseViewPageMetadata *pageMetadata = [viewConnection->dirtyMetadata objectForKey:pageKey];
		if (pageMetadata == nil)
		{
			YDBLogError(@"%@ (%@): Missing metadata for dirty page with pageKey: %@",
			            THIS_METHOD, [self registeredViewName], pageKey);
			return;//continue;
		}
		
		if ((id)page == (id)[NSNull null])
		{
			sqlite3_stmt *statement = [viewConnection pageTable_removeForPageKeyStatement];
			if (statement == NULL)
			{
				*stop = YES;
				return;//continue;
			}
			
			// DELETE FROM "pageTableName" WHERE "pageKey" = ?;
			
			YDBLogVerbose(@"DELETE FROM '%@' WHERE 'pageKey' = ?;\n"
			              @" - pageKey: %@", [self pageTableName], pageKey);
			
			YapDatabaseString _pageKey; MakeYapDatabaseString(&_pageKey, pageKey);
			sqlite3_bind_text(statement, 1, _pageKey.str, _pageKey.length, SQLITE_STATIC);
			
			int status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"%@ (%@): Error executing statement[1a]: %d %s",
				            THIS_METHOD, [self registeredViewName],
				            status, sqlite3_errmsg(databaseTransaction->abstractConnection->db));
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
			FreeYapDatabaseString(&_pageKey);
		}
		else
		{
			sqlite3_stmt *statement = [viewConnection pageTable_setAllForPageKeyStatement];
			if (statement == NULL)
			{
				*stop = YES;
				return;//continue;
			}
			
			// INSERT OR REPLACE INTO "pageTableName" ("pageKey", "data", "metadata") VALUES (?, ?, ?);
			
			YDBLogVerbose(@"INSERT OR REPLACE INTO '%@' ('pageKey', 'data', 'metadata) VALUES (?, ?, ?);\n"
			              @" - pageKey : %@\n"
			              @" - data    : %@\n"
			              @" - metadata: %@", [self pageTableName], pageKey, page, pageMetadata);
			
			YapDatabaseString _pageKey; MakeYapDatabaseString(&_pageKey, pageKey);
			sqlite3_bind_text(statement, 1, _pageKey.str, _pageKey.length, SQLITE_STATIC);
			
			__attribute__((objc_precise_lifetime)) NSData *rawData = [self serializePage:page];
			sqlite3_bind_blob(statement, 2, rawData.bytes, (int)rawData.length, SQLITE_STATIC);
			
			__attribute__((objc_precise_lifetime)) NSData *rawMeta = [self serializeMetadata:pageMetadata];
			sqlite3_bind_blob(statement, 3, rawMeta.bytes, (int)rawMeta.length, SQLITE_STATIC);
			
			int status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"%@ (%@): Error executing statement[1b]: %d %s",
				            THIS_METHOD, [self registeredViewName],
				            status, sqlite3_errmsg(databaseTransaction->abstractConnection->db));
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
			FreeYapDatabaseString(&_pageKey);
		}
	}];
	
	// Write dirty page metadata to table (those not associated with dirty pages).
	// This happens when the nextPageKey pointer is changed.
	
	[viewConnection->dirtyMetadata enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		NSString *pageKey = (NSString *)key;
		YapDatabaseViewPageMetadata *pageMetadata = (YapDatabaseViewPageMetadata *)obj;
		
		if ([viewConnection->dirtyPages objectForKey:pageKey])
		{
			// Both the page and metadata were dirty, so we wrote them both to disk at the same time.
			// No need to write the metadata again.
			
			return;//continue;
		}
		
		if ((id)pageMetadata == (id)[NSNull null])
		{
			// This shouldn't happen
			
			YDBLogWarn(@"%@ (%@): NULL metadata without matching dirty page with pageKey: %@",
			           THIS_METHOD, [self registeredViewName], pageKey);
		}
		else
		{
			sqlite3_stmt *statement = [viewConnection pageTable_setMetadataForPageKeyStatement];
			if (statement == NULL)
			{
				*stop = YES;
				return;//continue;
			}
			
			// UPDATE "pageTableName" SET "metadata" = ? WHERE "pageKey" = ?;
			
			YDBLogVerbose(@"UPDATE '%@' SET 'metadata' = ? WHERE 'pageKey' = ?;\n"
			              @" - metadata: %@\n"
			              @" - pageKey : %@", [self pageTableName], pageMetadata, pageKey);
			
			__attribute__((objc_precise_lifetime)) NSData *rawMeta = [self serializeMetadata:pageMetadata];
			sqlite3_bind_blob(statement, 1, rawMeta.bytes, (int)rawMeta.length, SQLITE_STATIC);
			
			YapDatabaseString _pageKey; MakeYapDatabaseString(&_pageKey, pageKey);
			sqlite3_bind_text(statement, 2, _pageKey.str, _pageKey.length, SQLITE_STATIC);
			
			int status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"%@ (%@): Error executing statement[2]: %d %s",
				            THIS_METHOD, [self registeredViewName],
				            status, sqlite3_errmsg(databaseTransaction->abstractConnection->db));
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
			FreeYapDatabaseString(&_pageKey);
		}
	}];
	
	// Update the dirty key -> pageKey mappings.
	// We do this at the end because keys may get moved around from
	// page to page during processing, and page consolidation/expansion.
	
	[viewConnection->dirtyKeys enumerateKeysAndObjectsUsingBlock:^(id collectionKeyObj, id pageKeyObj, BOOL *stop) {
		
		__unsafe_unretained YapCollectionKey *collectionKey = (YapCollectionKey *)collectionKeyObj;
		__unsafe_unretained NSString *pageKey = (NSString *)pageKeyObj;
		
		if ((id)pageKey == (id)[NSNull null])
		{
			sqlite3_stmt *statement = [viewConnection keyTable_removeForCollectionKeyStatement];
			if (statement == NULL)
			{
				*stop = YES;
				return;//continue;
			}
			
			// DELETE FROM "keyTableName" WHERE "collection" = ? AND "key" = ?;
			
			YDBLogVerbose(@"DELETE FROM '%@' WHERE 'collection' = ? AND'key' = ?;\n"
			              @" - collection : %@\n"
						  @" - key : %@", [self keyTableName], collectionKey.collection, collectionKey.key);
			
			YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collectionKey.collection);
			sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
			
			YapDatabaseString _key; MakeYapDatabaseString(&_key, collectionKey.key);
			sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
			
			int status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"%@ (%@): Error executing statement[3a]: %d %s",
				            THIS_METHOD, [self registeredViewName],
				            status, sqlite3_errmsg(databaseTransaction->abstractConnection->db));
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
			FreeYapDatabaseString(&_collection);
			FreeYapDatabaseString(&_key);
		}
		else
		{
			sqlite3_stmt *statement = [viewConnection keyTable_setPageKeyForCollectionKeyStatement];
			if (statement == NULL)
			{
				*stop = YES;
				return;//continue;
			}
			
			// INSERT OR REPLACE INTO "keyTableName" ("collection", "key", "pageKey") VALUES (?, ?, ?);
			
			YDBLogVerbose(@"INSERT OR REPLACE INTO '%@' ('collection', 'key', 'pageKey') VALUES (?, ?);\n"
			              @" - collection: %@\n"
			              @" - key       : %@\n"
			              @" - pageKey   : %@",
			              [self keyTableName], collectionKey.collection, collectionKey.key, pageKey);
			
			YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collectionKey.collection);
			sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
			
			YapDatabaseString _key; MakeYapDatabaseString(&_key, collectionKey.key);
			sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
			
			YapDatabaseString _pageKey; MakeYapDatabaseString(&_pageKey, pageKey);
			sqlite3_bind_text(statement, 3, _pageKey.str, _pageKey.length, SQLITE_STATIC);
			
			int status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"%@ (%@): Error executing statement[3b]: %d %s",
				            THIS_METHOD, [self registeredViewName],
				            status, sqlite3_errmsg(databaseTransaction->abstractConnection->db));
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
			FreeYapDatabaseString(&_collection);
			FreeYapDatabaseString(&_key);
		}
	}];
	
	[viewConnection->dirtyPages removeAllObjects];
	[viewConnection->dirtyMetadata removeAllObjects];
	[viewConnection->dirtyKeys removeAllObjects];
	
	[super commitTransaction];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapAbstractDatabaseExtensionTransaction_CollectionKeyValue
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleSetObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection withMetadata:(id)metadata
{
	YDBLogAutoTrace();
	
	NSParameterAssert(key != nil);
	NSParameterAssert(collection != nil);
	
	__unsafe_unretained YapCollectionsDatabaseView *view =
	    (YapCollectionsDatabaseView *)(extensionConnection->extension);
	
	// Invoke the grouping block to find out if the object should be included in the view.
	
	NSString *group;
	
	if (view->groupingBlockType == YapCollectionsDatabaseViewBlockTypeWithKey)
	{
		__unsafe_unretained YapCollectionsDatabaseViewGroupingWithKeyBlock groupingBlock =
		    (YapCollectionsDatabaseViewGroupingWithKeyBlock)view->groupingBlock;
		
		group = groupingBlock(collection, key);
	}
	else if (view->groupingBlockType == YapCollectionsDatabaseViewBlockTypeWithObject)
	{
		__unsafe_unretained YapCollectionsDatabaseViewGroupingWithObjectBlock groupingBlock =
		    (YapCollectionsDatabaseViewGroupingWithObjectBlock)view->groupingBlock;
		
		group = groupingBlock(collection, key, object);
	}
	else if (view->groupingBlockType == YapCollectionsDatabaseViewBlockTypeWithMetadata)
	{
		__unsafe_unretained YapCollectionsDatabaseViewGroupingWithMetadataBlock groupingBlock =
		    (YapCollectionsDatabaseViewGroupingWithMetadataBlock)view->groupingBlock;
		
		group = groupingBlock(collection, key, metadata);
	}
	else
	{
		__unsafe_unretained YapCollectionsDatabaseViewGroupingWithObjectAndMetadataBlock groupingBlock =
		    (YapCollectionsDatabaseViewGroupingWithObjectAndMetadataBlock)view->groupingBlock;
		
		group = groupingBlock(collection, key, object, metadata);
	}
	
	YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	if (group == nil)
	{
		// Remove key from view (if needed)
		
		[self removeCollectionKey:collectionKey];
	}
	else
	{
		// Add key to view (or update position)
		
		[self insertCollectionKey:collectionKey withObject:object metadata:metadata inGroup:group];
	}
}

/**
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleSetMetadata:(id)metadata forKey:(NSString *)key inCollection:(NSString *)collection
{
	YDBLogAutoTrace();
	
	NSParameterAssert(key != nil);
	NSParameterAssert(collection != nil);
	
	__unsafe_unretained YapCollectionsDatabaseView *view =
	    (YapCollectionsDatabaseView *)(extensionConnection->extension);
	
	YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	// Invoke the grouping block to find out if the object should be included in the view.
	
	id object = nil;
	NSString *group;
	
	if (view->groupingBlockType == YapCollectionsDatabaseViewBlockTypeWithKey ||
	    view->groupingBlockType == YapCollectionsDatabaseViewBlockTypeWithObject)
	{
		// Grouping is based on the key or object.
		// Neither have changed, and thus the group hasn't changed.
		
		if (view->sortingBlockType == YapCollectionsDatabaseViewBlockTypeWithKey ||
		    view->sortingBlockType == YapCollectionsDatabaseViewBlockTypeWithObject)
		{
			// Nothing to do.
			// Nothing has changed that relates to sorting either.
		}
		else
		{
			// Sorting is based on the metadata, which has changed.
			// So the sort order may possibly have changed.
			//
			// Fetch existing group
			group = [self groupForPageKey:[self pageKeyForCollectionKey:collectionKey]];
			
			if (group == nil)
			{
				// Nothing to do.
				// The key wasn't previously in the view (and still isn't in the view).
			}
			else
			{
				// From previous if statement (above) we know:
				// sortingBlockType is metadata or objectAndMetadata
				
				if (view->sortingBlockType == YapCollectionsDatabaseViewBlockTypeWithObjectAndMetadata)
				{
					// Need the object for the sorting block
					object = [self objectForKey:key inCollection:collection];
				}
				
				[self insertCollectionKey:collectionKey withObject:object metadata:metadata inGroup:group];
			}
		}
	}
	else
	{
		// Grouping is based on metadata or objectAndMetadata.
		// Invoke groupingBlock to see what the new group is.
		
		if (view->groupingBlockType == YapCollectionsDatabaseViewBlockTypeWithMetadata)
		{
			__unsafe_unretained YapCollectionsDatabaseViewGroupingWithMetadataBlock groupingBlock =
		        (YapCollectionsDatabaseViewGroupingWithMetadataBlock)view->groupingBlock;
			
			group = groupingBlock(collection, key, metadata);
		}
		else
		{
			__unsafe_unretained YapCollectionsDatabaseViewGroupingWithObjectAndMetadataBlock groupingBlock =
		        (YapCollectionsDatabaseViewGroupingWithObjectAndMetadataBlock)view->groupingBlock;
			
			object = [self objectForKey:key inCollection:collection];
			group = groupingBlock(collection, key, object, metadata);
		}
		
		if (group == nil)
		{
			// The key is not included in the view.
			// Remove key from view (if needed).
			
			[self removeCollectionKey:collectionKey];
		}
		else
		{
			if (view->sortingBlockType == YapCollectionsDatabaseViewBlockTypeWithKey ||
			    view->sortingBlockType == YapCollectionsDatabaseViewBlockTypeWithObject)
			{
				// Sorting is based on the key or object, neither of which has changed.
				// So if the group hasn't changed, then the sort order hasn't changed.
				
				NSString *existingGroup = [self groupForPageKey:[self pageKeyForCollectionKey:collectionKey]];
				if ([group isEqualToString:existingGroup])
				{
					// Nothing left to do.
					// The group didn't change, and the sort order cannot change (because the object didn't change).
					return;
				}
			}
			
			if (object == nil && (view->sortingBlockType == YapCollectionsDatabaseViewBlockTypeWithObject ||
			                      view->sortingBlockType == YapCollectionsDatabaseViewBlockTypeWithObjectAndMetadata))
			{
				// Need the object for the sorting block
				object = [self objectForKey:key inCollection:collection];
			}
			
			[self insertCollectionKey:collectionKey withObject:object metadata:metadata inGroup:group];
		}
	}
}

/**
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
	YDBLogAutoTrace();
	
	NSParameterAssert(key != nil);
	NSParameterAssert(collection != nil);
	
	YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	[self removeCollectionKey:collectionKey];
}

/**
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection
{
	YDBLogAutoTrace();
	
	NSParameterAssert(collection != nil);
	
	NSDictionary *dict = [self pageKeysForKeys:keys inCollection:collection];
	
	// dict.key = pageKey
	// dict.value = NSSet of keys within page (that match given keys & collection)
	
	[dict enumerateKeysAndObjectsUsingBlock:^(id pageKeyObj, id keysInPageObj, BOOL *stop) {
		
		__unsafe_unretained NSString *pageKey = (NSString *)pageKeyObj;
		__unsafe_unretained NSSet *keysInPage = (NSSet *)keysInPageObj;
		
		[self removeKeys:keysInPage inCollection:collection withPageKey:pageKey group:[self groupForPageKey:pageKey]];
	}];
}

/**
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveAllObjectsInCollection:(NSString *)collection
{
	YDBLogAutoTrace();
	
	NSParameterAssert(collection != nil);
	
	NSDictionary *dict = [self pageKeysAndKeysForCollection:collection];
	
	// dict.key = pageKey
	// dict.value = NSSet of keys within page (that match given collection)
	
	[dict enumerateKeysAndObjectsUsingBlock:^(id pageKeyObj, id keysInPageObj, BOOL *stop) {
		
		__unsafe_unretained NSString *pageKey = (NSString *)pageKeyObj;
		__unsafe_unretained NSSet *keysInPage = (NSSet *)keysInPageObj;
		
		[self removeKeys:keysInPage inCollection:collection withPageKey:pageKey group:[self groupForPageKey:pageKey]];
	}];
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
	
	return [viewConnection->group_pagesMetadata_dict count];
}

- (NSArray *)allGroups
{
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	return [viewConnection->group_pagesMetadata_dict allKeys];
}

- (NSUInteger)numberOfKeysInGroup:(NSString *)group
{
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:group];
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
	
	for (NSMutableArray *pagesForSection in [viewConnection->group_pagesMetadata_dict objectEnumerator])
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
	YapCollectionKey *collectionKey = nil;
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:group];
	NSUInteger pageOffset = 0;
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		if (index < (pageOffset + pageMetadata->count))
		{
			NSMutableArray *page = [self pageForPageKey:pageMetadata->pageKey];
			
			collectionKey = [page objectAtIndex:(index - pageOffset)];
		}
		else
		{
			pageOffset += pageMetadata->count;
		}
	}
	
	if (collectionPtr) *collectionPtr = collectionKey.collection;
	if (keyPtr) *keyPtr = collectionKey.key;
	
	return (collectionKey != nil);
}

- (NSString *)groupForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil)
		return nil;
	
	if (collection == nil)
		collection = @"";
	
	YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	return [self groupForPageKey:[self pageKeyForCollectionKey:collectionKey]];
}

- (BOOL)getGroup:(NSString **)groupPtr
           index:(NSUInteger *)indexPtr
          forKey:(NSString *)key
	inCollection:(NSString *)collection
{
	if (key == nil)
	{
		if (groupPtr) *groupPtr = nil;
		if (indexPtr) *indexPtr = 0;
		
		return NO;
	}
	
	if (collection == nil)
		collection = @"";
	
	YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	BOOL found = NO;
	NSString *group = nil;
	NSUInteger index = 0;
	
	// Query the database to see if the given key is in the view.
	// If it is, the query will return the corresponding page the key is in.
	
	NSString *pageKey = [self pageKeyForCollectionKey:collectionKey];
	if (pageKey)
	{
		// Now that we have the pageKey, fetch the corresponding group.
		// This is done using an in-memory cache.
		
		group = [self groupForPageKey:pageKey];
		
		// Calculate the offset of the corresponding page within the group.
		
		__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	        (YapCollectionsDatabaseViewConnection *)extensionConnection;
		
		NSUInteger pageOffset = 0;
		NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:group];
		
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
		{
			if ([pageMetadata->pageKey isEqualToString:pageKey])
			{
				break;
			}
			
			pageOffset += pageMetadata->count;
		}
		
		// Fetch the actual page (ordered array of keys)
		
		NSMutableArray *page = [self pageForPageKey:pageKey];
		
		// And find the exact index of the key within the page
		
		NSUInteger keyIndexWithinPage = [page indexOfObject:collectionKey];
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

- (void)enumerateKeysInGroup:(NSString *)group
                  usingBlock:(void (^)(NSString *collection, NSString *key, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	BOOL stop = NO;
	
	NSUInteger pageOffset = 0;
	NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:group];
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		NSMutableArray *page = [self pageForPageKey:pageMetadata->pageKey];
		
		[page enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			
			__unsafe_unretained YapCollectionKey *collectionKey = (YapCollectionKey *)obj;
			
			block(collectionKey.collection, collectionKey.key, (pageOffset + idx), stop);
		}];
		
		if (stop) break;
		pageOffset += pageMetadata->count;
	}
}

- (void)enumerateKeysInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)inOptions
                  usingBlock:(void (^)(NSString *collection, NSString *key, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	NSEnumerationOptions options = (inOptions & NSEnumerationReverse); // We only support NSEnumerationReverse
	BOOL forwardEnumeration = (options != NSEnumerationReverse);
	
	__block BOOL stop = NO;
	__block NSUInteger keyIndex;
	
	if (forwardEnumeration)
		keyIndex = 0;
	else
		keyIndex = [self numberOfKeysInGroup:group] - 1;
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:group];
	
	[pagesMetadataForGroup enumerateObjectsWithOptions:options
	                                        usingBlock:^(id pageMetadataObj, NSUInteger pageIdx, BOOL *outerStop){
		
		__unsafe_unretained YapDatabaseViewPageMetadata *pageMetadata =
		    (YapDatabaseViewPageMetadata *)pageMetadataObj;
		
		NSMutableArray *page = [self pageForPageKey:pageMetadata->pageKey];
		
		[page enumerateObjectsWithOptions:options usingBlock:^(id obj, NSUInteger idx, BOOL *innerStop) {
			
			__unsafe_unretained YapCollectionKey *collectionKey = (YapCollectionKey *)obj;
			
			block(collectionKey.collection, collectionKey.key, keyIndex, &stop);
			
			if (forwardEnumeration)
				keyIndex++;
			else
				keyIndex--;
			
			if (stop) *innerStop = YES;
		}];
		
		if (stop) *outerStop = YES;
	}];
}

- (void)enumerateKeysInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)inOptions
                       range:(NSRange)range
                  usingBlock:(void (^)(NSString *collection, NSString *key, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection =
	    (YapCollectionsDatabaseViewConnection *)extensionConnection;
	
	NSEnumerationOptions options = (inOptions & NSEnumerationReverse); // We only support NSEnumerationReverse
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:group];
	
	// Helper block to fetch the pageOffset for some page.
	
	NSUInteger (^pageOffsetForPageMetadata)(YapDatabaseViewPageMetadata *inPageMetadata);
	pageOffsetForPageMetadata = ^ NSUInteger (YapDatabaseViewPageMetadata *inPageMetadata){
		
		NSUInteger pageOffset = 0;
		
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
		{
			if (pageMetadata == inPageMetadata)
				return pageOffset;
			else
				pageOffset += pageMetadata->count;
		}
		
		return pageOffset;
	};
	
	__block BOOL stop = NO;
	__block BOOL startedRange = NO;
	__block NSUInteger keysLeft = range.length;
	
	[pagesMetadataForGroup enumerateObjectsWithOptions:options
	                                        usingBlock:^(id pageMetadataObj, NSUInteger pageIndex, BOOL *outerStop){
	
		__unsafe_unretained YapDatabaseViewPageMetadata *pageMetadata =
		    (YapDatabaseViewPageMetadata *)pageMetadataObj;
		
		NSUInteger pageOffset = pageOffsetForPageMetadata(pageMetadata);
		NSRange pageRange = NSMakeRange(pageOffset, pageMetadata->count);
		NSRange keysRange = NSIntersectionRange(pageRange, range);
		
		if (keysRange.length > 0)
		{
			startedRange = YES;
			NSMutableArray *page = [self pageForPageKey:pageMetadata->pageKey];
			
			// Enumerate the subset
			
			NSRange subsetRange = NSMakeRange(keysRange.location-pageOffset, keysRange.length);
			NSIndexSet *subset = [NSIndexSet indexSetWithIndexesInRange:subsetRange];
			
			[page enumerateObjectsAtIndexes:subset
			                        options:options
			                     usingBlock:^(id obj, NSUInteger idx, BOOL *innerStop) {
				
				__unsafe_unretained YapCollectionKey *collectionKey = (YapCollectionKey *)obj;
				
				block(collectionKey.collection, collectionKey.key, pageOffset+idx, &stop);
				
				if (stop) *innerStop = YES;
			}];
			
			keysLeft -= keysRange.length;
			
			if (stop) *outerStop = YES;
		}
		else if (startedRange)
		{
			// We've completed the range
			*outerStop = YES;
		}
		
	}];
	
	if (!stop && keysLeft > 0)
	{
		YDBLogWarn(@"%@: Range out of bounds: range(%lu, %lu) >= numberOfKeys(%lu) in group %@", THIS_METHOD,
		    (unsigned long)range.location, (unsigned long)range.length,
		    (unsigned long)[self numberOfKeysInGroup:group], group);
	}
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapCollectionsDatabaseViewTransaction (Convenience)

/**
 * Equivalent to invoking:
 *
 * NSString *collection = nil;
 * NSString *key = nil;
 * [[transaction ext:@"myView"] getKey:&key collection:&collection atIndex:index inGroup:group];
 * [transaction objectForKey:key inColleciton:collection];
**/
- (id)objectAtIndex:(NSUInteger)index inGroup:(NSString *)group
{
	NSString *collection = nil;
	NSString *key = nil;
	
	if ([self getKey:&key collection:&collection atIndex:index inGroup:group])
		return [self objectForKey:key inCollection:collection];
	else
		return nil;
}

/**
 * The following methods are equivalent to invoking the enumerateKeysInGroup:... methods,
 * and then fetching the metadata within your own block.
**/

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                             usingBlock:
                    (void (^)(NSString *collection, NSString *key, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateKeysInGroup:group usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
		
		block(collection, key, [self metadataForKey:key inCollection:collection], index, stop);
	}];
}

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                            withOptions:(NSEnumerationOptions)options
                             usingBlock:
                    (void (^)(NSString *collection, NSString *key, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateKeysInGroup:group
	               withOptions:options
	                usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
		
		block(collection, key, [self metadataForKey:key inCollection:collection], index, stop);
	}];
}

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                            withOptions:(NSEnumerationOptions)options
                                  range:(NSRange)range
                             usingBlock:
                    (void (^)(NSString *collection, NSString *key, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateKeysInGroup:group
	               withOptions:options
	                     range:range
	                usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
		
		block(collection, key, [self metadataForKey:key inCollection:collection], index, stop);
	}];
}

/**
 * The following methods are equivalent to invoking the enumerateKeysInGroup:... methods,
 * and then fetching the object and metadata within your own block.
**/

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                            usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateKeysInGroup:group usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
		
		id object = nil;
		id metadata = nil;
		[self getObject:&object metadata:&metadata forKey:key inCollection:collection];
		
		block(collection, key, object, metadata, index, stop);
	}];
}

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                            usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateKeysInGroup:group
	               withOptions:options
	                usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
		
		id object = nil;
		id metadata = nil;
		[self getObject:&object metadata:&metadata forKey:key inCollection:collection];
		
		block(collection, key, object, metadata, index, stop);
	}];
}

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                                 range:(NSRange)range
                            usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateKeysInGroup:group
	               withOptions:options
	                     range:range
	                usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
		
		id object = nil;
		id metadata = nil;
		[self getObject:&object metadata:&metadata forKey:key inCollection:collection];
		
		block(collection, key, object, metadata, index, stop);
	}];
}

@end
