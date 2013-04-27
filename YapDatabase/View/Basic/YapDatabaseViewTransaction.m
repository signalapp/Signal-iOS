#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseViewPrivate.h"
#import "YapDatabaseViewPageMetadata.h"
#import "YapAbstractDatabaseViewPrivate.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapDatabaseTransaction.h"
#import "YapCache.h"
#import "YapCacheMultiKey.h"
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
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif

/**
 * ARCHITECTURE OVERVIEW:
 * 
 * A YapDatabaseView allows one to store a ordered array of keys.
 * Furthermore, groups are supported, which means there may be multiple ordered arrays of keys, one per group.
 * 
 * Conceptually this is a very simple concept.
 * But obviously there are memory and performance requirements that add complexity.
 * 
 * The view creates two database tables:
 * 
 * view_name_key:
 * - key     (string, primary key) : a key from the database table
 * - pageKey (string)              : the primary key in the page table
 * 
 * view_name_page:
 * - pageKey  (string, primary key) : a uuid
 * - data     (blob)                : an NSArray of keys (the page)
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
 * - groupPagesDict   (NSMutableDictionary) : key(group), value(array of YapDatabaseViewPageMetadata objects)
 * - pageKeyGroupDict (NSMutableDictionary) : key(pageKey), value(group)
 * 
 * Using the groupPagesDict we can quickly find the 
**/
@implementation YapDatabaseViewTransaction
{
	BOOL lastInsertWasAtFirstIndex;
	BOOL lastInsertWasAtLastIndex;
}

- (BOOL)open
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	__unsafe_unretained YapDatabaseView *view =
	    (YapDatabaseView *)(abstractViewConnection->abstractView);
	
	sqlite3 *db = databaseTransaction->abstractConnection->db;
	
	NSString *string = [NSString stringWithFormat:
	    @"SELECT \"pagKey\", \"metadata\" FROM \"%@\" ;", [view pageTableName]];
	
	sqlite3_stmt *statement;
	
	int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: %@ (%@): Cannot create 'enumerate_stmt': %d %s",
		            THIS_FILE, THIS_METHOD, [self registeredViewName], status, sqlite3_errmsg(db));
		return NO;
	}
	
	// Enumerate over the page rows in the database, and populate our data structure.
	// Each row gives us the following fields:
	//
	// - group
	// - pageKey
	// - nextPageKey
	//
	// From this information we need to piece together the groupPagesDict:
	// - dict.key = group
	// - dict.value = properly ordered array of YapDatabaseViewKeyPageMetadata objects
	//
	// To piece together the proper page order we make a temporary dictionary with each link (in linked-list) reversed.
	// For example:
	//
	// pageA.nextPage = pageB  =>      B ->A
	// pageB.nextPage = pageC  =>      C -> B
	// pageC.nextPage = nil    => NSNull -> C
	//
	// After the enumeration of all rows is complete, we can walk the linked list backwards from the last page.
	
	NSMutableDictionary *groupPageDict = [[NSMutableDictionary alloc] init];
	NSMutableDictionary *groupOrderDict = [[NSMutableDictionary alloc] init];
	
	while (sqlite3_step(statement) == SQLITE_ROW)
	{
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
			
			if (pageMetadata->nextPageKey)
				[orderDict setObject:pageMetadata->pageKey forKey:pageMetadata->nextPageKey];
			else
				[orderDict setObject:pageMetadata->pageKey forKey:[NSNull null]];
		}
		else
		{
			YDBLogWarn(@"%@: %@ (%@): Encountered unknown metadata class: %@",
					   THIS_FILE, THIS_METHOD, [self registeredViewName], [metadata class]);
		}
	}
	
	__block BOOL error = (status != SQLITE_DONE);
	
	if (!error)
	{
		// Initialize ivars in viewConnection.
		// We try not to do this before we know the table exists.
		
		viewConnection->groupPagesDict = [[NSMutableDictionary alloc] init];
		viewConnection->pageKeyGroupDict = [[NSMutableDictionary alloc] init];
		
		// Enumerate over each group
		
		[groupOrderDict enumerateKeysAndObjectsUsingBlock:^(id _group, id _orderDict, BOOL *stop) {
			
			NSString *group = (NSString *)_group;
			NSMutableDictionary *orderDict = (NSMutableDictionary *)_orderDict;
			
			NSMutableDictionary *pageDict = [groupPageDict objectForKey:group];
			
			// Work backwards to stitch together the pages for this section.
			//
			// NSNull -> lastPageKey
			// lastPageKey -> secondToLastPageKey
			// ...
			// secondPageKey -> firstPageKey
			//
			// And from the keys, we can get the actual pageMetadata using the pageDict.
			
			NSMutableArray *pagesForGroup = [[NSMutableArray alloc] initWithCapacity:[pageDict count]];
			[viewConnection->groupPagesDict setObject:pagesForGroup forKey:group];
			
			NSString *pageKey = [orderDict objectForKey:[NSNull null]];
			while (pageKey)
			{
				[viewConnection->pageKeyGroupDict setObject:group forKey:pageKey];
				
				YapDatabaseViewPageMetadata *pageMetadata = [pageDict objectForKey:pageKey];
				[pagesForGroup insertObject:pageMetadata atIndex:0];
				
				pageKey = [orderDict objectForKey:pageKey];
				
				if ([pagesForGroup count] > [orderDict count])
				{
					YDBLogError(@"%@: %@ (%@): Circular key ordering detected in group(%@)",
					            THIS_FILE, THIS_METHOD, [self registeredViewName], group);
					
					error = YES;
					break;
				}
			}
			
			// Validate data for this section
			
			if (!error && ([pagesForGroup count] != [orderDict count]))
			{
				YDBLogError(@"%@: %@ (%@): Missing key page(s) in group(%@)",
				            THIS_FILE, THIS_METHOD, [self registeredViewName], group);
				
				error = YES;
			}
		}];
	}
	
	// Validate data
	
	if (error)
	{
		// The isOpen method of YapDatabaseViewConnection inspects sectionPagesDict.
		// So if there was an error opening the view, we need to reset this variable to nil.
		
		viewConnection->groupPagesDict = nil;
		viewConnection->pageKeyGroupDict = nil;
	}
	else
	{
		viewConnection->dirtyKeys = [[NSMutableDictionary alloc] init];
		viewConnection->dirtyPages = [[NSMutableDictionary alloc] init];
		viewConnection->dirtyMetadata = [[NSMutableDictionary alloc] init];
	}
	
	sqlite3_finalize(statement);
	return !error;
}

- (BOOL)createTable
{
	NSAssert(databaseTransaction->isReadWriteTransaction, @"Attempt to create a view outside a readwrite transaction");
	
	__unsafe_unretained YapDatabaseView *view =
	    (YapDatabaseView *)(abstractViewConnection->abstractView);
	
	NSString *keyTableName = [view keyTableName];
	NSString *pageTableName = [view pageTableName];
	
	sqlite3 *db = databaseTransaction->abstractConnection->db;
	
	NSString *createKeyTable = [NSString stringWithFormat:
	    @"CREATE TABLE IF NOT EXISTS \"%@\""
	    @" (\"key\" CHAR NOT NULL PRIMARY KEY,"
	    @"  \"pageKey\" CHAR NOT NULL"
	    @" );", keyTableName];
	
	NSString *createPageTable = [NSString stringWithFormat:
	    @"CREATE TABLE IF NOT EXISTS \"%@\""
	    @" (\"pageKey\" CHAR NOT NULL PRIMARY KEY,"
	    @"  \"data\" BLOB,"
		@"  \"metadata\" BLOB"
	    @" );", pageTableName];
	
	int status;
	
	status = sqlite3_exec(db, [createKeyTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: %@ (%@): Failed creating key table: %d %s",
		            THIS_FILE, THIS_METHOD, [self registeredViewName], status, sqlite3_errmsg(db));
		return NO;
	}
	
	status = sqlite3_exec(db, [createPageTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: %@ (%@): Failed creating page table: %d %s",
		            THIS_FILE, THIS_METHOD, [self registeredViewName], status, sqlite3_errmsg(db));
		return NO;
	}
	
	return YES;
}

- (BOOL)createOrOpen
{
	NSAssert(databaseTransaction->isReadWriteTransaction, @"Attempt to create a view outside a readwrite transaction");
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	if ([viewConnection isOpen])
	{
		return YES;
	}
	else
	{
		if (![self createTable]) return NO;
		if (![self open]) return NO;
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)registeredViewName
{
	YapAbstractDatabaseView *view = abstractViewConnection->abstractView;
	return view.registeredName;
}

- (id)objectForKey:(NSString *)key
{
	__unsafe_unretained YapDatabaseReadTransaction *transaction =
	    (YapDatabaseReadTransaction *)databaseTransaction;
	
	return [transaction objectForKey:key];
}

- (id)metadataForKey:(NSString *)key
{
	__unsafe_unretained YapDatabaseReadTransaction *transaction =
	    (YapDatabaseReadTransaction *)databaseTransaction;
	
	return [transaction metadataForKey:key];
}

- (BOOL)getObject:(id *)objectPtr metadata:(id *)metadataPtr forKey:(NSString *)key
{
	__unsafe_unretained YapDatabaseReadTransaction *transaction =
	    (YapDatabaseReadTransaction *)databaseTransaction;
	
	return [transaction getObject:objectPtr metadata:metadataPtr forKey:key];
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
 * If the given key is in the view, returns the associated pageKey.
 *
 * This method will use the cache(s) if possible.
 * Otherwise it will lookup the value in the key table.
**/
- (NSString *)pageKeyForKey:(NSString *)key
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	NSString *pageKey = nil;
	
	// Check dirty cache & clean cache
	
	pageKey = [viewConnection->dirtyKeys objectForKey:key];
	if (pageKey)
	{
		if ((__bridge void *)pageKey == (__bridge void *)[NSNull null])
			return nil;
		else
			return pageKey;
	}
	
	pageKey = [viewConnection->keyCache objectForKey:key];
	if (pageKey)
	{
		if ((__bridge void *)pageKey == (__bridge void *)[NSNull null])
			return nil;
		else
			return pageKey;
	}
	
	// Otherwise pull from the database
	
	sqlite3_stmt *statement = [viewConnection keyTable_getPageKeyForKeyStatement];
	if (statement == NULL)
		return nil;
	
	// SELECT pageKey FROM 'keyTableName' WHERE key = ? ;
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(statement, 0);
		int textSize = sqlite3_column_bytes(statement, 0);
		
		pageKey = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@: %@ (%@): Error executing statement: %d %s, key(%@)",
		            THIS_FILE, THIS_METHOD, [self registeredViewName],
		            status, sqlite3_errmsg(databaseTransaction->abstractConnection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	if (pageKey)
		[viewConnection->keyCache setObject:pageKey forKey:key];
	else
		[viewConnection->keyCache setObject:[NSNull null] forKey:key];
	
	return pageKey;
}

/**
 * This method looks up a whole bunch of keys using only a few queries.
 *
 * It returns an array of the same size as the given keys parameter,
 * where keys[0] corresponds to pageKeys[0].
 * 
 * If any keys are missing, they will be represented by NSNull in the resulting array.
**/
- (NSArray *)pageKeysForKeys:(NSArray *)keys
{
	if ([keys count] == 0)
	{
		return [NSArray array];
	}
	
	NSMutableDictionary *pageKeysDict = [NSMutableDictionary dictionaryWithCapacity:[keys count]];
	
	__unsafe_unretained YapDatabaseView *view =
	    (YapDatabaseView *)(abstractViewConnection->abstractView);
	
	sqlite3 *db = databaseTransaction->abstractConnection->db;
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	NSUInteger keysIndex = 0;
	NSUInteger keysCount = [keys count];
	
	do
	{
		NSUInteger keysLeft = keysCount - keysIndex;
		NSUInteger numHostParams = MIN(keysLeft, maxHostParams);
		
		// SELECT \"key\", "pageKey" FROM "keyTableName" WHERE "key" IN (?, ?, ...);
		
		NSUInteger capacity = 50 + (numHostParams * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendFormat:@"SELECT \"key\", \"pagKey\", FROM \"%@\" WHERE \"key\" IN (", [view pageTableName]];
		
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
		int status;
		
		status = sqlite3_prepare_v2(db, [query UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: %@ (%@): Error creating statement: %d %s",
			            THIS_FILE, THIS_METHOD, [self registeredViewName], status, sqlite3_errmsg(db));
			return nil;
		}
		
		for (i = 0; i < numHostParams; i++)
		{
			NSString *key = [keys objectAtIndex:(keysIndex + i)];
			
			sqlite3_bind_text(statement, (int)(i + 1), [key UTF8String], -1, SQLITE_TRANSIENT);
		}
		
		status = sqlite3_step(statement);
		while (status == SQLITE_ROW)
		{
			const unsigned char *text0 = sqlite3_column_text(statement, 0);
			int textSize0 = sqlite3_column_bytes(statement, 0);
			
			const unsigned char *text1 = sqlite3_column_text(statement, 1);
			int textSize1 = sqlite3_column_bytes(statement, 1);
			
			NSString *key = [[NSString alloc] initWithBytes:text0 length:textSize0 encoding:NSUTF8StringEncoding];
			NSString *pageKey = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
			
			[pageKeysDict setObject:pageKey forKey:key];
			
			status = sqlite3_step(statement);
		}
		
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@: %@ (%@): Error executing statement: %d %s",
			            THIS_FILE, THIS_METHOD, [self registeredViewName], status, sqlite3_errmsg(db));
			return nil;
		}
		
		
		keysIndex += numHostParams;
	}
	while (keysIndex < keysCount);
	
	NSMutableArray *pageKeys = [NSMutableArray arrayWithCapacity:[pageKeysDict count]];
	
	for (NSString *key in keys)
	{
		NSString *pageKey = [pageKeysDict objectForKey:key];
		if (pageKey)
			[pageKeys addObject:pageKey];
		else
			[pageKeys addObject:[NSNull null]];
	}
	
	return pageKeys;
}

/**
 * Fetches the page data for the given pageKey.
 * 
 * This method will use the cache(s) if possible.
 * Otherwise it will load the data from the page table and deserialize it.
**/
- (NSMutableArray *)pageForPageKey:(NSString *)pageKey
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
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
		
		id obj = [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil];
		
		if ([obj isKindOfClass:[NSMutableArray class]])
		{
			page = (NSMutableArray *)obj;
		}
		else
		{
			YDBLogError(@"%@: %@ (%@): Found invalid page data with class(%@) for pageKey(%@)",
			            THIS_FILE, THIS_METHOD, [self registeredViewName], [obj class], pageKey);
		}
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@: %@ (%@): Error executing statement: %d %s",
		            THIS_FILE, THIS_METHOD, [self registeredViewName],
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
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	return [viewConnection->pageKeyGroupDict objectForKey:pageKey];
}

/**
 * Use this method (instead of removeKey:) when the pageKey and group are already known.
**/
- (void)removeKey:(NSString *)key withPageKey:(NSString *)pageKey group:(NSString *)group
{
	if (key == nil) return;
	
	NSParameterAssert(pageKey != nil);
	NSParameterAssert(group != nil);
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	// Update page (by removing key from array)
	
	NSMutableArray *page = [self pageForPageKey:pageKey];
	
	NSUInteger index = [page indexOfObject:key];
	if (index == NSNotFound)
	{
		YDBLogError(@"%@: %@ (%@): Key(%@) expected to be in page(%@), but is missing",
		            THIS_FILE, THIS_METHOD, [self registeredViewName], key, pageKey);
		return;
	}
	
	[page removeObjectAtIndex:index];
	NSUInteger pageCount = [page count];
	
	if (pageCount > 0)
	{
		// Mark page as dirty
		
		[viewConnection->dirtyPages setObject:page forKey:pageKey];
		[viewConnection->pageCache removeObjectForKey:pageKey];
	}
	else
	{
		// Drop page
		
		[viewConnection->dirtyPages setObject:[NSNull null] forKey:pageKey];
		[viewConnection->pageCache removeObjectForKey:pageKey];
	}
	
	// Update page metadata (by decrementing count)
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	NSUInteger pageMetadataIndex = 0;
	
	NSMutableArray *pages = [viewConnection->groupPagesDict objectForKey:group];
	
	for (YapDatabaseViewPageMetadata *pm in pages)
	{
		if ([pm->pageKey isEqualToString:pageKey])
		{
			pageMetadata = pm;
			break;
		}
		
		pageMetadataIndex++;
	}
	
	pageMetadata->count = pageCount;
	
	if (pageCount > 0)
	{
		// Mark page metadata as dirty
		
		[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
	}
	else
	{
		// Drop page metadata
		
		[pages removeObjectAtIndex:pageMetadataIndex];
		[viewConnection->dirtyMetadata setObject:[NSNull null] forKey:pageKey];
		
		if (pageMetadataIndex > 0)
		{
			// Update linked-list pointers. E.g.:
			//
			// link->prev->next = link->next (except we only use next pointers)
			
			YapDatabaseViewPageMetadata *prevPageMetadata = [pages objectAtIndex:(pageMetadataIndex - 1)];
			prevPageMetadata->nextPageKey = pageMetadata->nextPageKey;
			
			[viewConnection->dirtyMetadata setObject:prevPageMetadata forKey:prevPageMetadata->pageKey];
		}
	}
	
	// Mark key for deletion
	
	[viewConnection->dirtyKeys setObject:[NSNull null] forKey:key];
	[viewConnection->keyCache removeObjectForKey:key];
}

/**
 * Use this method to remove a set of 1 or more keys from a given pageKey & group.
**/
- (void)removeKeys:(NSSet *)keys withPageKey:(NSString *)pageKey group:(NSString *)group
{
	if ([keys count] < 2)
	{
		[self removeKey:[keys anyObject] withPageKey:pageKey group:group];
		return;
	}
	
	NSParameterAssert(pageKey != nil);
	NSParameterAssert(group != nil);
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	// Update page (by removing keys from array)
	
	NSMutableArray *page = [self pageForPageKey:pageKey];
	
	NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
	NSUInteger index = 0;
	
	for (NSString *key in page)
	{
		if ([keys containsObject:key])
		{
			[indexSet addIndex:index];
		}
		
		index++;
	}
	
	if ([indexSet count] != [keys count])
	{
		YDBLogWarn(@"%@: %@ (%@): Keys expected to be in page(%@), but are missing",
		           THIS_FILE, THIS_METHOD, [self registeredViewName], pageKey);
	}
	
	[page removeObjectsAtIndexes:indexSet];
	NSUInteger pageCount = [page count];
	
	if (pageCount > 0)
	{
		// Mark page as dirty
		
		[viewConnection->dirtyPages setObject:page forKey:pageKey];
		[viewConnection->pageCache removeObjectForKey:pageKey];
	}
	else
	{
		// Drop page
		
		[viewConnection->dirtyPages setObject:[NSNull null] forKey:pageKey];
		[viewConnection->pageCache removeObjectForKey:pageKey];
	}
	
	// Update page metadata (by decrementing count)
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	NSUInteger pageMetadataIndex = 0;
	
	NSMutableArray *pages = [viewConnection->groupPagesDict objectForKey:group];
	
	for (YapDatabaseViewPageMetadata *currentPageMetadata in pages)
	{
		if ([currentPageMetadata->pageKey isEqualToString:pageKey])
		{
			pageMetadata = currentPageMetadata;
			break;
		}
		
		pageMetadataIndex++;
	}
	
	pageMetadata->count = pageCount;
	
	if (pageCount > 0)
	{
		// Mark page metadata as dirty
		
		[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
	}
	else
	{
		// Drop page metadata
		
		[pages removeObjectAtIndex:pageMetadataIndex];
		if ([pages count] == 0)
		{
			[viewConnection->groupPagesDict removeObjectForKey:group];
		}
		
		[viewConnection->dirtyMetadata setObject:[NSNull null] forKey:pageKey];
		
		if (pageMetadataIndex > 0)
		{
			// Update linked-list pointers. E.g.:
			//
			// link->prev->next = link->next (except we only use next pointers)
			
			YapDatabaseViewPageMetadata *prevPageMetadata = [pages objectAtIndex:(pageMetadataIndex - 1)];
			prevPageMetadata->nextPageKey = pageMetadata->nextPageKey;
			
			[viewConnection->dirtyMetadata setObject:prevPageMetadata forKey:prevPageMetadata->pageKey];
		}
	}
	
	// Mark keys for deletion
	
	for (NSString *key in keys)
	{
		[viewConnection->dirtyKeys setObject:[NSNull null] forKey:key];
		[viewConnection->keyCache removeObjectForKey:key];
	}
}

/**
 * Use this method when you don't know if the key exists in the view.
**/
- (void)removeKey:(NSString *)key
{
	// Find out if key is in view
	
	NSString *pageKey = [self pageKeyForKey:key];
	if (pageKey)
	{
		[self removeKey:key withPageKey:pageKey group:[self groupForPageKey:pageKey]];
	}
}

- (void)insertKey:(NSString *)key inGroup:(NSString *)group atIndex:(NSUInteger)index
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	NSString *pageKey = nil;
	
	// Find page
	
	NSMutableArray *pages = [viewConnection->groupPagesDict objectForKey:group];
	
	NSUInteger pageOffset = 0;
	for (YapDatabaseViewPageMetadata *currentPageMetadata in pages)
	{
		if (index < (pageOffset + pageMetadata->count))
		{
			pageMetadata = currentPageMetadata;
			pageKey = pageMetadata->pageKey;
			break;
		}
		
		pageOffset += pageMetadata->count;
	}
	
	// Update page
	
	NSMutableArray *page = [self pageForPageKey:pageKey];
	
	[page insertObject:key atIndex:(index - pageOffset)];
	NSUInteger pageCount = [page count];
	
	[viewConnection->dirtyPages setObject:page forKey:pageKey];
	[viewConnection->pageCache removeObjectForKey:pageKey];
	
	// Update page metadata (by incrementing count)
	
	pageMetadata->count = pageCount;
	[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
	
	// Mark key for insertion
	
	[viewConnection->dirtyKeys setObject:pageKey forKey:key];
}

/**
 * Use this method after it has been determined that the key should be inserted into the given group.
 * The object and metadata parameters must be properly set (if needed by the sorting block).
 * 
 * This method will use the configured sorting block to find the proper index for the key.
 * 
**/
- (void)insertObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata inGroup:(NSString *)group
{
	// Is the key already in the view?
	// If so:
	// - we may need to change its group and/or update its position.
	// - if the group hasn't changed, we can use its existing position as an optimization during sorting.
	
	BOOL tryExistingIndexInGroup = NO;
	
	NSString *existingPageKey = [self pageKeyForKey:key];
	if (existingPageKey)
	{
		NSString *existingGroup = [self groupForPageKey:existingPageKey];
		
		if ([group isEqualToString:existingGroup])
		{
			tryExistingIndexInGroup = YES;
		}
		else
		{
			[self removeKey:key withPageKey:existingPageKey group:existingGroup];
		}
	}
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	NSMutableArray *pagesMetadataInGroup = [viewConnection->groupPagesDict objectForKey:group];
	
	if (pagesMetadataInGroup == nil)
	{
		// First object added to group.
		
		NSString *pageKey = [self generatePageKey];
		
		YapDatabaseViewPageMetadata *pageMetadata = [[YapDatabaseViewPageMetadata alloc] init];
		pageMetadata->pageKey = pageKey;
		pageMetadata->nextPageKey = nil;
		pageMetadata->group = group;
		pageMetadata->count = 1;
		
		pagesMetadataInGroup = [[NSMutableArray alloc] initWithCapacity:1];
		[pagesMetadataInGroup addObject:pageMetadata];
		
		NSMutableArray *page = [[NSMutableArray alloc] initWithCapacity:1];
		[page addObject:key];
		
		[viewConnection->groupPagesDict setObject:pagesMetadataInGroup forKey:group];
		
		[viewConnection->dirtyPages setObject:page forKey:pageKey];
		[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
		
		[viewConnection->dirtyKeys setObject:pageKey forKey:key];
	}
	else
	{
		// Calculate out how many keys are in the group.
		
		NSUInteger count = 0;
		
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataInGroup)
		{
			count += pageMetadata->count;
		}
		
		__unsafe_unretained YapDatabaseView *view = (YapDatabaseView *)(viewConnection->abstractView);
		
		NSComparisonResult (^compare)(NSUInteger) = ^NSComparisonResult (NSUInteger index){
			
			NSString *anotherKey = nil;
			
			NSUInteger pageOffset = 0;
			for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataInGroup)
			{
				if (index < (pageOffset + pageMetadata->count))
				{
					NSMutableArray *page = [self pageForPageKey:pageMetadata->pageKey];
					
					anotherKey = [page objectAtIndex:(index - pageOffset)];
					break;
				}
				else
				{
					pageOffset += pageMetadata->count;
				}
			}
			
			if (view->sortingBlockType == YapDatabaseViewBlockTypeWithObject)
			{
				__unsafe_unretained YapDatabaseViewSortingWithObjectBlock sortingBlock =
				    (YapDatabaseViewSortingWithObjectBlock)view->sortingBlock;
				
				id anotherObject = [self objectForKey:anotherKey];
				
				return sortingBlock(group, key, object, anotherKey, anotherObject);
			}
			else if (view->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata)
			{
				__unsafe_unretained YapDatabaseViewSortingWithMetadataBlock sortingBlock =
				    (YapDatabaseViewSortingWithMetadataBlock)view->sortingBlock;
				
				id anotherMetadata = [self metadataForKey:anotherKey];
				
				return sortingBlock(group, key, metadata, anotherKey, anotherMetadata);
			}
			else
			{
				__unsafe_unretained YapDatabaseViewSortingWithBothBlock sortingBlock =
				    (YapDatabaseViewSortingWithBothBlock)view->sortingBlock;
				
				id anotherObject = nil;
				id anotherMetadata = nil;
				
				[self getObject:&anotherObject metadata:&anotherMetadata forKey:anotherKey];
				
				return sortingBlock(group, key, object, metadata, anotherKey, anotherObject, anotherMetadata);
			}
		};
		
		NSComparisonResult cmp;
		
		// Optimization 1:
		//
		// If key is already in group, check to see if its index is the same as before.
		
		if (tryExistingIndexInGroup)
		{
			NSMutableArray *existingPage = [self pageForPageKey:existingPageKey];
			NSUInteger existingIndex = [existingPage indexOfObject:key];
			
			BOOL useExistingIndexInGroup = NO;
			
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
				
				return;
			}
			else
			{
				// The key has changed position.
				// Remove it from previous position (and don't forget to decrement count).
				
				[self removeKey:key withPageKey:existingPageKey group:group];
				count--;
			}
		}
		
		// Optimization 2:
		//
		// A very common operation is to insert objects at the beginning or end of the array.
		// We attempt to notice this trend and optimize around it.
		
		if (lastInsertWasAtFirstIndex && (count > 1))
		{
			cmp = compare(0);
			
			if (cmp == NSOrderedAscending) // object < first
			{
				[self insertKey:key inGroup:group atIndex:count];
				return;
			}
		}
		
		if (lastInsertWasAtLastIndex && (count > 1))
		{
			cmp = compare(count - 1);
			
			if (cmp != NSOrderedAscending) // object >= last
			{
				[self insertKey:key inGroup:group atIndex:count];
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
		}
		
		[self insertKey:key inGroup:group atIndex:min];
		
		if (min == 0)
			lastInsertWasAtFirstIndex = YES;
		else
			lastInsertWasAtFirstIndex = NO;
		
		if (min == count)
			lastInsertWasAtLastIndex = YES;
		else
			lastInsertWasAtLastIndex = NO;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapAbstractDatabaseViewKeyValueTransaction
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabase view hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleSetObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	__unsafe_unretained YapDatabaseView *view = (YapDatabaseView *)(viewConnection->abstractView);
	
	// Invoke the grouping block to find out if the object should be included in the view.
	
	NSString *group;
	
	if (view->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
		    (YapDatabaseViewGroupingWithObjectBlock)view->groupingBlock;
		
		group = groupingBlock(key, object);
	}
	else if (view->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
		    (YapDatabaseViewGroupingWithMetadataBlock)view->groupingBlock;
		
		group = groupingBlock(key, metadata);
	}
	else
	{
		__unsafe_unretained YapDatabaseViewGroupingWithBothBlock groupingBlock =
		    (YapDatabaseViewGroupingWithBothBlock)view->groupingBlock;
		
		group = groupingBlock(key, object, metadata);
	}
	
	if (group == nil)
	{
		// Remove key from view (if needed)
		
		[self removeKey:key];
	}
	else
	{
		// Add key to view (or update position)
		
		[self insertObject:object forKey:key withMetadata:metadata inGroup:group];
	}
}

/**
 * YapDatabase view hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleSetMetadata:(id)metadata forKey:(NSString *)key
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	__unsafe_unretained YapDatabaseView *view =
	    (YapDatabaseView *)(viewConnection->abstractView);
	
	// Can a metadata change affect the order?
	
	if (view->groupingBlockType == YapDatabaseViewBlockTypeWithObject &&
	    view->sortingBlockType != YapDatabaseViewBlockTypeWithObject)
	{
		// Grouping and sorting are based entirely on objects,
		// and don't take into account metadata changes.
		return;
	}
	
	// Invoke the grouping block to find out if the object should be included in the view.
	
	id object = nil;
	NSString *group;
	
	if (view->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
	{
		// The object has not changed, and thus the group hasn't changed.
		
		group = [self groupForPageKey:[self pageKeyForKey:key]];
		if (group == nil)
		{
			// Shortcut: No need to remove key as we know object wasn't previously in view.
			return;
		}
	}
	else if (view->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
		    (YapDatabaseViewGroupingWithMetadataBlock)view->groupingBlock;
		
		group = groupingBlock(key, metadata);
		if (group == nil)
		{
			// Remove key from view (if needed)
			[self removeKey:key];
			return;
		}
	}
	else
	{
		__unsafe_unretained YapDatabaseViewGroupingWithBothBlock groupingBlock =
		    (YapDatabaseViewGroupingWithBothBlock)view->groupingBlock;
		
		object = [self objectForKey:key];
		
		group = groupingBlock(key, object, metadata);
		if (group == nil)
		{
			// Remove key from view (if needed)
			[self removeKey:key];
			return;
		}
	}
	
	// Add key to view (or update position)
	
	if (object == nil && (view->sortingBlockType != YapDatabaseViewBlockTypeWithMetadata))
	{
		object = [self objectForKey:key];
	}
	
	[self insertObject:object forKey:key withMetadata:metadata inGroup:group];
}

/**
 * YapDatabase view hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectForKey:(NSString *)key
{
	[self removeKey:key];
}

/**
 * YapDatabase view hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectsForKeys:(NSArray *)keys
{
	// We could loop over each key and simply invoke [self removeKey:key]...
	// 
	// However, we can do better than that by optimizing cache access.
	// That is, if we arrange the keys by associated pageKey,
	// then we can simply enumerate over each pageKey,
	// and remove all keys within that page in a single operation.
	
	NSUInteger count = [keys count];
	NSArray *pageKeys = [self pageKeysForKeys:keys];
	
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	
	for (NSUInteger i = 0; i < count; i++)
	{
		NSString *pageKey = [pageKeys objectAtIndex:i];
		
		if ((id)pageKey == (id)[NSNull null])
		{
			// This key doesn't exist in the view
			continue;
		}
		
		NSString *key = [keys objectAtIndex:i];
		
		NSMutableSet *keysSet = [dict objectForKey:pageKey];
		if (keysSet == nil)
		{
			keysSet = [NSMutableSet setWithCapacity:1];
			[dict setObject:keysSet forKey:pageKey];
		}
		
		[keysSet addObject:key];
	}
	
	// dict.key = pageKey
	// dict.value = NSSet of keys within the page that are to be removed
	
	[dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		NSString *pageKey = (NSString *)key;
		NSSet *keysSet = (NSSet *)obj;
		
		[self removeKeys:keysSet withPageKey:pageKey group:[self groupForPageKey:pageKey]];
	}];
}

- (void)handleRemoveAllObjects
{
	
}

- (void)commitTransaction
{
	// Todo
	
	[super commitTransaction];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)numberOfGroups
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	return [viewConnection->groupPagesDict count];
}

- (NSArray *)allGroups
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	return [viewConnection->groupPagesDict allKeys];
}

- (NSUInteger)numberOfKeysInGroup:(NSString *)group
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	NSMutableArray *pagesForGroup = [viewConnection->groupPagesDict objectForKey:group];
	if (pagesForGroup == nil) {
		return 0;
	}
	
	NSUInteger count = 0;
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesForGroup)
	{
		count += pageMetadata->count;
	}
	
	return count;
}

- (NSUInteger)numberOfKeysInAllGroups
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
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

- (NSString *)keyAtIndex:(NSUInteger)index inGroup:(NSString *)group
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	NSMutableArray *pagesForGroup = [viewConnection->groupPagesDict objectForKey:group];
	
	NSUInteger pageOffset = 0;
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesForGroup)
	{
		if (index < (pageOffset + pageMetadata->count))
		{
			NSMutableArray *page = [self pageForPageKey:pageMetadata->pageKey];
			
			return [page objectAtIndex:(index - pageOffset)];
		}
		else
		{
			pageOffset += pageMetadata->count;
		}
	}
	
	return nil;
}

- (id)objectAtIndex:(NSUInteger)keyIndex inGroup:(NSString *)group
{
	NSString *key = [self keyAtIndex:keyIndex inGroup:group];
	if (key)
	{
		__unsafe_unretained YapDatabaseReadTransaction *transaction =
		    (YapDatabaseReadTransaction *)databaseTransaction;
		
		return [transaction objectForKey:key];
	}
	else
	{
		return nil;
	}
}

- (NSString *)groupForKey:(NSString *)key
{
	return [self groupForPageKey:[self pageKeyForKey:key]];
}

- (BOOL)getGroup:(NSString **)groupPtr index:(NSUInteger *)indexPtr forKey:(NSString *)key
{
	BOOL found = NO;
	NSString *group = nil;
	NSUInteger index = 0;
	
	// Query the database to see if the given key is in the view.
	// If it is, the query will return the corresponding page the key is in.
	
	NSString *pageKey = [self pageKeyForKey:key];
	if (pageKey)
	{
		// Now that we have the pageKey, fetch the corresponding group.
		// This is done using an in-memory cache.
		
		group = [self groupForPageKey:pageKey];
		
		// Calculate the offset of the corresponding page within the group.
		
		__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	        (YapDatabaseViewConnection *)abstractViewConnection;
		
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
		
		NSMutableArray *page = [self pageForPageKey:pageKey];
		
		// And find the exact index of the key within the page
		
		NSUInteger keyIndexWithinPage = [page indexOfObject:key];
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
