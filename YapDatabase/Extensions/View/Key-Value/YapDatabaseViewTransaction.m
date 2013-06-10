#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseViewPrivate.h"
#import "YapDatabaseViewPageMetadata.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapDatabaseTransaction.h"
#import "YapCache.h"
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
 * - data     (blob)                : an array of keys (the page)
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
@implementation YapDatabaseViewTransaction

- (BOOL)prepareIfNeeded
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
	if (viewConnection->group_pagesMetadata_dict && viewConnection->pageKey_group_dict)
	{
		// Already prepared
		return YES;
	}
	
	__unsafe_unretained YapDatabaseView *view = (YapDatabaseView *)(extensionConnection->extension);
	
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
		
		id metadata = [self deserializeMetadata:data];
		
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
			
			__unsafe_unretained NSString *group = (NSString *)_group;
			__unsafe_unretained NSMutableDictionary *orderDict = (NSMutableDictionary *)_orderDict;
			
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
				
				[pagesForGroup addObject:pageMetadata];
				
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
#pragma mark YapDatabaseTransaction
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)registeredViewName
{
	return [extensionConnection->extension registeredName];
}

- (NSString *)keyTableName
{
	return [(YapDatabaseView *)(extensionConnection->extension) keyTableName];
}

- (NSString *)pageTableName
{
	return [(YapDatabaseView *)(extensionConnection->extension) pageTableName];
}

- (NSData *)serializePage:(NSMutableArray *)page
{
	return [NSPropertyListSerialization dataWithPropertyList:page
	                                                  format:NSPropertyListBinaryFormat_v1_0
	                                                 options:NSPropertyListMutableContainers
	                                                   error:NULL];
}

- (NSMutableArray *)deserializePage:(NSData *)data
{
	return [NSPropertyListSerialization propertyListWithData:data
	                                                 options:NSPropertyListMutableContainers
	                                                  format:nil
	                                                   error:nil];
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
 * If the given key is in the view, returns the associated pageKey.
 *
 * This method will use the cache(s) if possible.
 * Otherwise it will lookup the value in the key table.
**/
- (NSString *)pageKeyForKey:(NSString *)key
{
	if (key == nil) return nil;
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
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
	
	// SELECT "pageKey" FROM "keyTableName" WHERE key = ? ;
	
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
		YDBLogError(@"%@ (%@): Error executing statement: %d %s, key(%@)",
		            THIS_METHOD, [self registeredViewName],
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
 * It returns a dictionary where the keys are pageKeys, and the value is an NSSet
 * of keys within the associated page.
**/
- (NSDictionary *)pageKeysForKeys:(NSArray *)keys
{
	if ([keys count] == 0)
	{
		return [NSDictionary dictionary];
	}
	
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[keys count]];
	
	__unsafe_unretained YapDatabaseView *view = (YapDatabaseView *)(extensionConnection->extension);
	
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
		
		// SELECT "key", "pageKey" FROM "keyTableName" WHERE "key" IN (?, ?, ...);
		
		NSUInteger capacity = 50 + (numHostParams * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendFormat:@"SELECT \"key\", \"pageKey\" FROM \"%@\" WHERE \"key\" IN (", [view keyTableName]];
		
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
			YDBLogError(@"%@ (%@): Error creating statement\n"
			            @" - status(%d), errmsg: %s\n"
			            @" - query: %@",
			            THIS_METHOD, [self registeredViewName], status, sqlite3_errmsg(db), query);
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
			return nil;
		}
		
		
		keysIndex += numHostParams;
	}
	while (keysIndex < keysCount);
	
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
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
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
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
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
- (void)insertKey:(NSString *)key inGroup:(NSString *)group
                                  atIndex:(NSUInteger)index
                      withExistingPageKey:(NSString *)existingPageKey
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
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
	
	YDBLogVerbose(@"Inserting key(%@) in group(%@) at index(%lu) with page(%@) pageOffset(%lu)",
	              key, group, (unsigned long)index, pageKey, (unsigned long)(index - pageOffset));
	
	// Update page
	
	[page insertObject:key atIndex:(index - pageOffset)];
	
	[viewConnection->dirtyPages setObject:page forKey:pageKey];
	[viewConnection->pageCache removeObjectForKey:pageKey];
	
	// Update page metadata (by incrementing count)
	
	pageMetadata->count = [page count]; // number of keys in page
	[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
	
	// Mark key for insertion
	
	if (![pageKey isEqualToString:existingPageKey])
	{
		[viewConnection->dirtyKeys setObject:pageKey forKey:key];
		[viewConnection->keyCache removeObjectForKey:key];
	}
}

/**
 * Use this method after it has been determined that the key should be inserted into the given group.
 * The object and metadata parameters must be properly set (if needed by the sorting block).
 * 
 * This method will use the configured sorting block to find the proper index for the key.
 * It will attempt to optimize this operation as best as possible using a variety of techniques.
**/
- (void)insertObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata inGroup:(NSString *)group
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseView *view = (YapDatabaseView *)(extensionConnection->extension);
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
	// Is the key already in the group?
	// If so:
	// - its index within the group may or may not have changed.
	// - we can use its existing position as an optimization during sorting.
	
	BOOL tryExistingIndexInGroup = NO;
	
	NSString *existingPageKey = [self pageKeyForKey:key];
	if (existingPageKey)
	{
		// The key is already in the view.
		// Has it changed groups?
		
		NSString *existingGroup = [self groupForPageKey:existingPageKey];
		
		if ([group isEqualToString:existingGroup])
		{
			// The key is already in the group.
			
			if (view->sortingBlockType == YapDatabaseViewBlockTypeWithKey)
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
			[self removeKey:key withPageKey:existingPageKey group:existingGroup];
			
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
		
		YDBLogVerbose(@"Inserting key(%@) in new group(%@) with page(%@)", key, group, pageKey);
		
		YapDatabaseViewPageMetadata *pageMetadata = [[YapDatabaseViewPageMetadata alloc] init];
		pageMetadata->pageKey = pageKey;
		pageMetadata->prevPageKey = nil;
		pageMetadata->nextPageKey = nil;
		pageMetadata->group = group;
		pageMetadata->count = 1;
		
		pagesMetadataForGroup = [[NSMutableArray alloc] initWithCapacity:1];
		[pagesMetadataForGroup addObject:pageMetadata];
		
		NSMutableArray *page = [[NSMutableArray alloc] initWithCapacity:1];
		[page addObject:key];
		
		[viewConnection->group_pagesMetadata_dict setObject:pagesMetadataForGroup forKey:group];
		[viewConnection->pageKey_group_dict setObject:group forKey:pageKey];
		
		[viewConnection->dirtyPages setObject:page forKey:pageKey];
		[viewConnection->pageCache removeObjectForKey:pageKey];
		
		[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
		
		[viewConnection->dirtyKeys setObject:pageKey forKey:key];
		[viewConnection->keyCache removeObjectForKey:key];
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
			
			NSString *anotherKey = nil;
			
			NSUInteger pageOffset = 0;
			for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
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
			
			if (view->sortingBlockType == YapDatabaseViewBlockTypeWithKey)
			{
				__unsafe_unretained YapDatabaseViewSortingWithKeyBlock sortingBlock =
				    (YapDatabaseViewSortingWithKeyBlock)view->sortingBlock;
				
				return sortingBlock(group, key, anotherKey);
			}
			else if (view->sortingBlockType == YapDatabaseViewBlockTypeWithObject)
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
				__unsafe_unretained YapDatabaseViewSortingWithObjectAndMetadataBlock sortingBlock =
				    (YapDatabaseViewSortingWithObjectAndMetadataBlock)view->sortingBlock;
				
				id anotherObject = nil;
				id anotherMetadata = nil;
				
				[self getObject:&anotherObject metadata:&anotherMetadata forKey:anotherKey];
				
				return sortingBlock(group, key, object, metadata, anotherKey, anotherObject, anotherMetadata);
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
			
			NSUInteger existingIndex = existingPageOffset + [existingPage indexOfObject:key];
			
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
				
				YDBLogVerbose(@"Updated key(%@) in group(%@) maintains current index", key, group);
				return;
			}
			else
			{
				// The key has changed position.
				// Remove it from previous position (and don't forget to decrement count).
				
				[self removeKey:key withPageKey:existingPageKey group:group];
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
				YDBLogVerbose(@"Insert key(%@) in group(%@) at beginning (lastInsertWasAtFirstIndex optimization)",
				              key, group);
				
				[self insertKey:key inGroup:group atIndex:0 withExistingPageKey:existingPageKey];
				return;
			}
		}
		
		if (viewConnection->lastInsertWasAtLastIndex && (count > 1))
		{
			cmp = compare(count - 1);
			
			if (cmp != NSOrderedAscending) // object >= last
			{
				YDBLogVerbose(@"Insert key(%@) in group(%@) at end (lastInsertWasAtLastIndex optimization)",
				              key, group);
				
				[self insertKey:key inGroup:group atIndex:count withExistingPageKey:existingPageKey];
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
		
		YDBLogVerbose(@"Insert key(%@) in group(%@) took %lu comparisons", key, group, (unsigned long)loopCount);
		
		[self insertKey:key inGroup:group atIndex:min withExistingPageKey:existingPageKey];
		
		viewConnection->lastInsertWasAtFirstIndex = (min == 0);
		viewConnection->lastInsertWasAtLastIndex  = (min == count);
	}
}

/**
 * Use this method (instead of removeKey:) when the pageKey and group are already known.
**/
- (void)removeKey:(NSString *)key withPageKey:(NSString *)pageKey group:(NSString *)group
{
	YDBLogAutoTrace();
	
	if (key == nil) return;
	
	NSParameterAssert(pageKey != nil);
	NSParameterAssert(group != nil);
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
	// Update page (by removing key from array)
	
	NSMutableArray *page = [self pageForPageKey:pageKey];
	
	NSUInteger keyIndex = [page indexOfObject:key];
	if (keyIndex == NSNotFound)
	{
		YDBLogError(@"%@ (%@): Key(%@) expected to be in page(%@), but is missing",
		            THIS_METHOD, [self registeredViewName], key, pageKey);
		return;
	}
	
	YDBLogVerbose(@"Removing key(%@) from page(%@) at index(%lu)", key, page, (unsigned long)keyIndex);
	
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
	
	// Mark page as dirty
	
	YDBLogVerbose(@"Dirty page(%@)", pageKey);
	
	[viewConnection->dirtyPages setObject:page forKey:pageKey];
	[viewConnection->pageCache removeObjectForKey:pageKey];
	
	// Mark page metadata as dirty
	
	[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
	
	// Mark key for deletion
	
	[viewConnection->dirtyKeys setObject:[NSNull null] forKey:key];
	[viewConnection->keyCache removeObjectForKey:key];
}

/**
 * Use this method to remove a set of 1 or more keys from a given pageKey & group.
**/
- (void)removeKeys:(NSSet *)keys withPageKey:(NSString *)pageKey group:(NSString *)group
{
	YDBLogAutoTrace();
	
	if ([keys count] == 0) return;
	if ([keys count] == 1)
	{
		[self removeKey:[keys anyObject] withPageKey:pageKey group:group];
		return;
	}
	
	NSParameterAssert(pageKey != nil);
	NSParameterAssert(group != nil);
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
	// Update page (by removing keys from array)
	
	NSMutableArray *page = [self pageForPageKey:pageKey];
	
	NSMutableIndexSet *keyIndexSet = [NSMutableIndexSet indexSet];
	NSUInteger keyIndex = 0;
	
	for (NSString *key in page)
	{
		if ([keys containsObject:key])
		{
			[keyIndexSet addIndex:keyIndex];
		}
		
		keyIndex++;
	}
	
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
	
	// Mark page as dirty
	
	YDBLogVerbose(@"Dirty page(%@)", pageKey);
	
	[viewConnection->dirtyPages setObject:page forKey:pageKey];
	[viewConnection->pageCache removeObjectForKey:pageKey];
	
	// Mark page metadata as dirty
	
	[viewConnection->dirtyMetadata setObject:pageMetadata forKey:pageKey];
	
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
	YDBLogAutoTrace();
	
	// Find out if key is in view
	
	NSString *pageKey = [self pageKeyForKey:key];
	if (pageKey)
	{
		[self removeKey:key withPageKey:pageKey group:[self groupForPageKey:pageKey]];
	}
}

- (void)removeAllKeys
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
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

- (void)splitOversizedPage:(YapDatabaseViewPageMetadata *)pageMetadata
{
	int maxPageSize = 50; // Todo...
	
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
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
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
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
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapAbstractDatabaseExtensionTransaction_KeyValue
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleSetObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseView *view = (YapDatabaseView *)(extensionConnection->extension);
	
	// Invoke the grouping block to find out if the object should be included in the view.
	
	NSString *group;
	
	if (view->groupingBlockType == YapDatabaseViewBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
		    (YapDatabaseViewGroupingWithKeyBlock)view->groupingBlock;
		
		group = groupingBlock(key);
	}
	else if (view->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
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
		__unsafe_unretained YapDatabaseViewGroupingWithObjectAndMetadataBlock groupingBlock =
		    (YapDatabaseViewGroupingWithObjectAndMetadataBlock)view->groupingBlock;
		
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
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleSetMetadata:(id)metadata forKey:(NSString *)key
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseView *view = (YapDatabaseView *)(extensionConnection->extension);
	
	// Invoke the grouping block to find out if the object should be included in the view.
	
	id object = nil;
	NSString *group;
	
	if (view->groupingBlockType == YapDatabaseViewBlockTypeWithKey ||
	    view->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
	{
		// Grouping is based on the key or object.
		// Neither have changed, and thus the group hasn't changed.
		
		if (view->sortingBlockType == YapDatabaseViewBlockTypeWithKey ||
		    view->sortingBlockType == YapDatabaseViewBlockTypeWithObject)
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
			group = [self groupForPageKey:[self pageKeyForKey:key]];
			
			if (group == nil)
			{
				// Nothing to do.
				// The key wasn't previously in the view (and still isn't in the view).
			}
			else
			{
				// From previous if statement (above) we know:
				// sortingBlockType is metadata or objectAndMetadata
				
				if (view->sortingBlockType == YapDatabaseViewBlockTypeWithObjectAndMetadata)
				{
					// Need the object for the sorting block
					object = [self objectForKey:key];
				}
				
				[self insertObject:object forKey:key withMetadata:metadata inGroup:group];
			}
		}
	}
	else
	{
		// Grouping is based on metadata or objectAndMetadata.
		// Invoke groupingBlock to see what the new group is.
		
		if (view->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata)
		{
			__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
		        (YapDatabaseViewGroupingWithMetadataBlock)view->groupingBlock;
			
			group = groupingBlock(key, metadata);
		}
		else
		{
			__unsafe_unretained YapDatabaseViewGroupingWithObjectAndMetadataBlock groupingBlock =
		        (YapDatabaseViewGroupingWithObjectAndMetadataBlock)view->groupingBlock;
			
			object = [self objectForKey:key];
			group = groupingBlock(key, object, metadata);
		}
		
		if (group == nil)
		{
			// The key is not included in the view.
			// Remove key from view (if needed).
			
			[self removeKey:key];
		}
		else
		{
			if (view->sortingBlockType == YapDatabaseViewBlockTypeWithKey ||
			    view->sortingBlockType == YapDatabaseViewBlockTypeWithObject)
			{
				// Sorting is based on the key or object, neither of which has changed.
				// So if the group hasn't changed, then the sort order hasn't changed.
				
				NSString *existingGroup = [self groupForPageKey:[self pageKeyForKey:key]];
				if ([group isEqualToString:existingGroup])
				{
					// Nothing left to do.
					// The group didn't change, and the sort order cannot change (because the object didn't change).
					return;
				}
			}
			
			if (object == nil && (view->sortingBlockType == YapDatabaseViewBlockTypeWithObject ||
			                      view->sortingBlockType == YapDatabaseViewBlockTypeWithObjectAndMetadata))
			{
				// Need the object for the sorting block
				object = [self objectForKey:key];
			}
			
			[self insertObject:object forKey:key withMetadata:metadata inGroup:group];
		}
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectForKey:(NSString *)key
{
	YDBLogAutoTrace();
	
	[self removeKey:key];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectsForKeys:(NSArray *)keys
{
	YDBLogAutoTrace();
	
	NSDictionary *dict = [self pageKeysForKeys:keys];
	
	// dict.key = pageKey
	// dict.value = NSSet of keys within the page that are to be removed
	
	[dict enumerateKeysAndObjectsUsingBlock:^(id pageKeyObj, id keysInPageObj, BOOL *stop) {
		
		__unsafe_unretained NSString *pageKey = (NSString *)pageKeyObj;
		__unsafe_unretained NSSet *keysInPage = (NSSet *)keysInPageObj;
		
		[self removeKeys:keysInPage withPageKey:pageKey group:[self groupForPageKey:pageKey]];
	}];
	
	// Todo: page consolidation in modified groups
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveAllObjects
{
	YDBLogAutoTrace();
	
	[self removeAllKeys];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)commitTransaction
{
	YDBLogAutoTrace();
	
	// During the transaction we stored all changes in the "dirty" dictionaries.
	// This allows the view to make multiple changes to a page, yet only write it once.
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
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
	
	[viewConnection->dirtyKeys enumerateKeysAndObjectsUsingBlock:^(id theKey, id obj, BOOL *stop) {
		
		NSString *key = (NSString *)theKey;
		NSString *pageKey = (NSString *)obj;
		
		if ((id)pageKey == (id)[NSNull null])
		{
			sqlite3_stmt *statement = [viewConnection keyTable_removeForKeyStatement];
			if (statement == NULL)
			{
				*stop = YES;
				return;//continue;
			}
			
			// DELETE FROM "keyTableName" WHERE "key" = ?;
			
			YDBLogVerbose(@"DELETE FROM '%@' WHERE 'key' = ?;\n"
			              @" - key : %@", [self keyTableName], key);
			
			YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
			sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
			
			int status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"%@ (%@): Error executing statement[3a]: %d %s",
				            THIS_METHOD, [self registeredViewName],
				            status, sqlite3_errmsg(databaseTransaction->abstractConnection->db));
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
			FreeYapDatabaseString(&_key);
		}
		else
		{
			sqlite3_stmt *statement = [viewConnection keyTable_setPageKeyForKeyStatement];
			if (statement == NULL)
			{
				*stop = YES;
				return;//continue;
			}
			
			// INSERT OR REPLACE INTO "keyTableName" ("key", "pageKey") VALUES (?, ?);
			
			YDBLogVerbose(@"INSERT OR REPLACE INTO '%@' ('key', 'pageKey') VALUES (?, ?);\n"
			              @" - key    : %@\n"
			              @" - pageKey: %@", [self keyTableName], key, pageKey);
			
			YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
			sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
			
			YapDatabaseString _pageKey; MakeYapDatabaseString(&_pageKey, pageKey);
			sqlite3_bind_text(statement, 2, _pageKey.str, _pageKey.length, SQLITE_STATIC);
			
			int status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"%@ (%@): Error executing statement[3b]: %d %s",
				            THIS_METHOD, [self registeredViewName],
				            status, sqlite3_errmsg(databaseTransaction->abstractConnection->db));
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
			FreeYapDatabaseString(&_key);
		}
	}];
	
	[viewConnection->dirtyPages removeAllObjects];
	[viewConnection->dirtyMetadata removeAllObjects];
	[viewConnection->dirtyKeys removeAllObjects];
	
	[super commitTransaction];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)numberOfGroups
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
	return [viewConnection->group_pagesMetadata_dict count];
}

- (NSArray *)allGroups
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
	return [viewConnection->group_pagesMetadata_dict allKeys];
}

- (NSUInteger)numberOfKeysInGroup:(NSString *)group
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
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
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
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

- (NSString *)keyAtIndex:(NSUInteger)index inGroup:(NSString *)group
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
	NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:group];
	NSUInteger pageOffset = 0;
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
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

- (NSString *)groupForKey:(NSString *)key
{
	key = [key copy]; // mutable string protection (public method)
	
	return [self groupForPageKey:[self pageKeyForKey:key]];
}

- (BOOL)getGroup:(NSString **)groupPtr index:(NSUInteger *)indexPtr forKey:(NSString *)key
{
	key = [key copy]; // mutable string protection (public method)
	
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
	        (YapDatabaseViewConnection *)extensionConnection;
		
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

- (NSArray *)keysInRange:(NSRange)range group:(NSString *)group
{
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:range.length];

	// Todo: Optimize cache access.

	[self enumerateKeysInGroup:group
	               withOptions:0
	                     range:range
	                usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
		
		[result addObject:key];
	}];

	return result;
}

- (void)enumerateKeysInGroup:(NSString *)group
                  usingBlock:(void (^)(NSString *key, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
	BOOL stop = NO;
	
	NSUInteger pageOffset = 0;
	NSMutableArray *pagesMetadataForGroup = [viewConnection->group_pagesMetadata_dict objectForKey:group];
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		NSMutableArray *page = [self pageForPageKey:pageMetadata->pageKey];
		
		NSUInteger index = pageOffset;
		for (NSString *key in page)
		{
			block(key, index, &stop);
			
			index++;
			if (stop) break;
		}
		
		if (stop) break;
		
		pageOffset += pageMetadata->count;
	}
}

- (void)enumerateKeysInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)inOptions
                  usingBlock:(void (^)(NSString *key, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
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
		
		[page enumerateObjectsWithOptions:options usingBlock:^(id keyObj, NSUInteger idx, BOOL *innerStop){
			
			block((NSString *)keyObj, keyIndex, &stop);
			
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
                  usingBlock:(void (^)(NSString *key, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection = (YapDatabaseViewConnection *)extensionConnection;
	
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
			                     usingBlock:^(id keyObj, NSUInteger idx, BOOL *innerStop){
				
				block((NSString *)keyObj, pageOffset+idx, &stop);
				
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

@implementation YapDatabaseViewTransaction (Convenience)

- (id)objectAtIndex:(NSUInteger)index inGroup:(NSString *)group
{
	return [self objectForKey:[self keyAtIndex:index inGroup:group]];
}

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                             usingBlock:(void (^)(NSString *key, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateKeysInGroup:group usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
		
		block(key, [self metadataForKey:key], index, stop);
	}];
}

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                            withOptions:(NSEnumerationOptions)options
                             usingBlock:(void (^)(NSString *key, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateKeysInGroup:group withOptions:options usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
		
		block(key, [self metadataForKey:key], index, stop);
	}];
}

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                            withOptions:(NSEnumerationOptions)options
                                  range:(NSRange)range
                             usingBlock:(void (^)(NSString *key, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateKeysInGroup:group
	               withOptions:options
	                     range:range
	                usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
		
		block(key, [self metadataForKey:key], index, stop);
	}];
}

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                            usingBlock:
                                 (void (^)(NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateKeysInGroup:group usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
		
		id object = nil;
		id metadata = nil;
		[self getObject:&object metadata:&metadata forKey:key];
		
		block(key, object, metadata, index, stop);
	}];
}

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                            usingBlock:
                                 (void (^)(NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateKeysInGroup:group withOptions:options usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
		
		id object = nil;
		id metadata = nil;
		[self getObject:&object metadata:&metadata forKey:key];
		
		block(key, object, metadata, index, stop);
	}];
}

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                                 range:(NSRange)range
                            usingBlock:
                                 (void (^)(NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateKeysInGroup:group
	               withOptions:options
	                     range:range
	                usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
		
		id object = nil;
		id metadata = nil;
		[self getObject:&object metadata:&metadata forKey:key];
		
		block(key, object, metadata, index, stop);
	}];
}

@end
