#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseViewPrivate.h"

#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabasePrivate.h"

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
#pragma unused(ydbLogLevel)

@implementation YapDatabaseViewTransaction

- (id)initWithParentConnection:(YapDatabaseViewConnection *)inParentConnection
           databaseTransaction:(YapDatabaseReadTransaction *)inDatabaseTransaction
{
	YDBLogAutoTrace();
	
	if ((self = [super init]))
	{
		parentConnection = inParentConnection;
		databaseTransaction = inDatabaseTransaction;
		
		if (![self isPersistentView])
		{
			mapTableTransaction = [databaseTransaction memoryTableTransaction:[self mapTableName]];
			pageTableTransaction = [databaseTransaction memoryTableTransaction:[self pageTableName]];
			pageMetadataTableTransaction = [databaseTransaction memoryTableTransaction:[self pageMetadataTableName]];
		}
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extension Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is called to create any necessary tables,
 * as well as populate the view by enumerating over the existing rows in the database.
 * 
 * Return YES if completed successfully, or if already prepared.
 * Return NO if some kind of error occured.
**/
- (BOOL)createIfNeeded
{
	YDBLogAutoTrace();
	
	if (![self isPersistentView])
	{
		// We're registering an In-Memory-Only View (non-persistent) (not stored in the database).
		// So we can skip all the checks because we know we need to create the memory tables.
		
		if (![self createTables]) return NO;
		
		if (parentConnection->state == nil)
			parentConnection->state = [[YapDatabaseViewState alloc] init];
		
		if (!parentConnection->parent->options.skipInitialViewPopulation)
		{
			if (![self populateView]) return NO;
		}
		
		// Store initial versionTag in prefs table
		
		NSString *versionTag = [parentConnection->parent versionTag]; // MUST get init value from view
		
		[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:NO];
		
		// If there was a previously registered persistent view with this name,
		// then we should drop those tables from the database.
		
		BOOL dropPersistentTables = [self getIntValue:NULL forExtensionKey:ext_key_classVersion persistent:YES];
		if (dropPersistentTables)
		{
			[[parentConnection->parent class]
			  dropTablesForRegisteredName:[self registeredName]
			              withTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
			                wasPersistent:YES];
		}
		
		return YES;
	}
	else
	{
		// We're registering a Peristent View (stored in the database).
	
		int classVersion = YAP_DATABASE_VIEW_CLASS_VERSION;
		
		NSString *versionTag = [parentConnection->parent versionTag]; // MUST get init value from view
		
		// Figure out what steps we need to take in order to register the view
		
		BOOL needsCreateTables = NO;
		BOOL needsPopulateView = NO;
		
		// Check classVersion (the internal version number of YapDatabaseView implementation)
		
		int oldClassVersion = 0;
		BOOL hasOldClassVersion = [self getIntValue:&oldClassVersion
		                            forExtensionKey:ext_key_classVersion persistent:YES];
		
		if (!hasOldClassVersion)
		{
			// First time registration
			
			needsCreateTables = YES;
			needsPopulateView = !parentConnection->parent->options.skipInitialViewPopulation;
		}
		else if (oldClassVersion != classVersion)
		{
			// Upgrading from older codebase
			
			[self dropTablesForOldClassVersion:oldClassVersion];
			needsCreateTables = YES;
			needsPopulateView = YES; // Not initialViewPopulation, but rather codebase upgrade.
		}
	
		// Create the database tables (if needed)
		
		if (needsCreateTables)
		{
			if (![self createTables]) return NO;
		}
		
		// Check other variables (if needed)
		
		NSString *oldVersionTag = nil;
		BOOL hasOldVersion_deprecated = NO;
		
		if (!hasOldClassVersion)
		{
			// If there wasn't a classVersion in the table,
			// then there won't be other values either.
		}
		else
		{
			// Check user-supplied config version.
			// We may need to re-populate the database if the groupingBlock or sortingBlock changed.
			
			oldVersionTag = [self stringValueForExtensionKey:ext_key_versionTag persistent:YES];
			
			if (oldVersionTag == nil)
			{
				int oldVersion_deprecated = 0;
				hasOldVersion_deprecated = [self getIntValue:&oldVersion_deprecated
				                             forExtensionKey:ext_key_version_deprecated persistent:YES];
				
				if (hasOldVersion_deprecated)
				{
					oldVersionTag = [NSString stringWithFormat:@"%d", oldVersion_deprecated];
				}
			}
			
			if (![oldVersionTag isEqualToString:versionTag])
			{
				needsPopulateView = YES; // Not initialViewPopulation, but rather versionTag upgrade.
			}
		}
		
		// Repopulate table (if needed)
		
		if (needsPopulateView)
		{
			if (parentConnection->state == nil)
				parentConnection->state = [[YapDatabaseViewState alloc] init];
			
			if (![self populateView]) return NO;
		}
		
		// Update yap2 table values (if needed)
		
		if (!hasOldClassVersion || (oldClassVersion != classVersion)) {
			[self setIntValue:classVersion forExtensionKey:ext_key_classVersion persistent:YES];
		}
		
		if (hasOldVersion_deprecated)
		{
			[self removeValueForExtensionKey:ext_key_version_deprecated persistent:YES];
			[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:YES];
		}
		else if (![oldVersionTag isEqualToString:versionTag])
		{
			[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:YES];
		}
		
		return YES;
	}
}

/**
 * This method is called to prepare the transaction for use.
 *
 * Remember, an extension transaction is a very short lived object.
 * Thus it stores the majority of its state within the extension connection (the parent).
 *
 * Return YES if completed successfully, or if already prepared.
 * Return NO if some kind of error occured.
**/
- (BOOL)prepareIfNeeded
{
	YDBLogAutoTrace();
	
	if (parentConnection->state)
	{
		// Already prepared
		return YES;
	}
	
	// Can we use the latest processed changeset in YapDatabaseView?
	
	YapDatabaseViewState *state = nil;
	
	BOOL shortcut = [parentConnection->parent getState:&state forConnection:parentConnection];
	if (shortcut && state)
	{
		if (databaseTransaction->isReadWriteTransaction)
			parentConnection->state = [state mutableCopy];
		else
			parentConnection->state = [state copy];
		
		return YES;
	}
	
	// Enumerate over the page rows in the database, and populate our data structure.
	// Each row has the following information:
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
	
	NSMutableDictionary<NSString *, NSMutableDictionary *> *groupPageDict  = [[NSMutableDictionary alloc] init];
	NSMutableDictionary<NSString *, NSMutableDictionary *> *groupOrderDict = [[NSMutableDictionary alloc] init];
	
	__block BOOL error = NO;

	if ([self isPersistentView])
	{
		sqlite3 *db = databaseTransaction->connection->db;
		
		NSString *string = [NSString stringWithFormat:
			@"SELECT \"pageKey\", \"group\", \"prevPageKey\", \"count\" FROM \"%@\";", [self pageTableName]];
		
		int const column_idx_pageKey     = SQLITE_COLUMN_START + 0;
		int const column_idx_group       = SQLITE_COLUMN_START + 1;
		int const column_idx_prevPageKey = SQLITE_COLUMN_START + 2;
		int const column_idx_count       = SQLITE_COLUMN_START + 3;
		
		sqlite3_stmt *statement = NULL;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ (%@): Cannot create 'enumerate_stmt': %d %s",
						THIS_METHOD, [self registeredName], status, sqlite3_errmsg(db));
			return NO;
		}
		
		unsigned int stepCount = 0;
		
		while (sqlite3_step(statement) == SQLITE_ROW)
		{
			stepCount++;
			
			const unsigned char *text0 = sqlite3_column_text(statement, column_idx_pageKey);
			int textSize0 = sqlite3_column_bytes(statement, column_idx_pageKey);
			
			NSString *pageKey = [[NSString alloc] initWithBytes:text0 length:textSize0 encoding:NSUTF8StringEncoding];
			
			const unsigned char *text1 = sqlite3_column_text(statement, column_idx_group);
			int textSize1 = sqlite3_column_bytes(statement, column_idx_group);
			
			NSString *group = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
			
			const unsigned char *text2 = sqlite3_column_text(statement, column_idx_prevPageKey);
			int textSize2 = sqlite3_column_bytes(statement, column_idx_prevPageKey);
			
			NSString *prevPageKey = nil;
			if (textSize2 > 0)
				prevPageKey = [[NSString alloc] initWithBytes:text2 length:textSize2 encoding:NSUTF8StringEncoding];
			
			int count = sqlite3_column_int(statement, column_idx_count);
			
			if (count >= 0)
			{
				YapDatabaseViewPageMetadata *pageMetadata = [[YapDatabaseViewPageMetadata alloc] init];
				pageMetadata->pageKey = pageKey;
				pageMetadata->group = group;
				pageMetadata->prevPageKey = prevPageKey;
				pageMetadata->count = (NSUInteger)count;
				
				NSMutableDictionary *pageDict = groupPageDict[group];
				if (pageDict == nil)
				{
					pageDict = [[NSMutableDictionary alloc] init];
					groupPageDict[group] = pageDict;
				}
				
				NSMutableDictionary *orderDict = groupOrderDict[group];
				if (orderDict == nil)
				{
					orderDict = [[NSMutableDictionary alloc] init];
					groupOrderDict[group] = orderDict;
				}
			
				[pageDict setObject:pageMetadata forKey:pageKey];
				
				if (prevPageKey)
					[orderDict setObject:pageKey forKey:prevPageKey];
				else
					[orderDict setObject:pageKey forKey:[NSNull null]];
			}
			else
			{
				YDBLogWarn(@"%@ (%@): Encountered invalid count: %d", THIS_METHOD, [self registeredName], count);
			}
		}
	
		YDBLogVerbose(@"Processing %u items from %@...", stepCount, [self pageTableName]);
		
		YDBLogVerbose(@"groupPageDict: %@", groupPageDict);
		YDBLogVerbose(@"groupOrderDict: %@", groupOrderDict);
		
		if ((status != SQLITE_OK) && (status != SQLITE_DONE))
		{
			error = YES;
			YDBLogError(@"%@ (%@): Error enumerating page table: %d %s",
			            THIS_METHOD, [self registeredName], status, sqlite3_errmsg(db));
		}
		
		sqlite3_finalize(statement);
	}
	else // if (isNonPersistentView)
	{
		[pageMetadataTableTransaction enumerateKeysAndObjectsWithBlock:^(id __unused key, id obj, BOOL __unused *stop) {
			
			YapDatabaseViewPageMetadata *pageMetadata = [(YapDatabaseViewPageMetadata *)obj copy];
			
			NSMutableDictionary *pageDict = [groupPageDict objectForKey:pageMetadata->group];
			if (pageDict == nil)
			{
				pageDict = [[NSMutableDictionary alloc] init];
				[groupPageDict setObject:pageDict forKey:pageMetadata->group];
			}
			
			NSMutableDictionary *orderDict = [groupOrderDict objectForKey:pageMetadata->group];
			if (orderDict == nil)
			{
				orderDict = [[NSMutableDictionary alloc] init];
				[groupOrderDict setObject:orderDict forKey:pageMetadata->group];
			}
			
			[pageDict setObject:pageMetadata forKey:pageMetadata->pageKey];
			
			if (pageMetadata->prevPageKey)
				[orderDict setObject:pageMetadata->pageKey forKey:pageMetadata->prevPageKey];
			else
				[orderDict setObject:pageMetadata->pageKey forKey:[NSNull null]];
		}];
	}
	
	// Now that we have all the metadata about each page,
	// it's time to piece them together in the proper order.

	if (!error)
	{
		// Initialize ivars in viewConnection.
		// We try not to do this before we know the table exists.
		
		parentConnection->state = [[YapDatabaseViewState alloc] init];
		
		// Enumerate over each group
		
		[groupOrderDict enumerateKeysAndObjectsUsingBlock:
		    ^(NSString *group, NSMutableDictionary *orderDict, BOOL __unused *stop)
		{
			NSMutableDictionary *pageDict = [groupPageDict objectForKey:group];
			
			// Walk the linked-list to stitch together the pages for this section.
			//
			// NSNull -> firstPageKey
			// firstPageKey -> secondPageKey
			// ...
			// secondToLastPageKey -> lastPageKey
			//
			// And from the keys, we can get the actual pageMetadata using the pageDict.
			
			NSUInteger pageCount = 0;
			NSUInteger expectedPageCount = [orderDict count];
			
			[parentConnection->state createGroup:group withCapacity:expectedPageCount];
			
			NSString *pageKey = [orderDict objectForKey:[NSNull null]];
			while (pageKey)
			{
				YapDatabaseViewPageMetadata *pageMetadata = [pageDict objectForKey:pageKey];
				if (pageMetadata == nil)
				{
					YDBLogError(@"%@ (%@): Invalid key ordering detected in group(%@)",
					            THIS_METHOD, [self registeredName], group);
					
					error = YES;
					break;
				}
				
				[parentConnection->state addPageMetadata:pageMetadata toGroup:group];
				pageCount++;
				
				// get the next pageKey in the linked list
				pageKey = [orderDict objectForKey:pageKey];
				
				// sanity check for circular linked list
				if (pageCount > expectedPageCount)
				{
					YDBLogError(@"%@ (%@): Circular key ordering detected in group(%@)",
					            THIS_METHOD, [self registeredName], group);
					
					error = YES;
					break;
				}
			}
			
			// Validate data for this section
			
			if (!error && (pageCount != expectedPageCount))
			{
				YDBLogError(@"%@ (%@): Missing key page(s) in group(%@)",
				            THIS_METHOD, [self registeredName], group);
				
				error = YES;
			}
		}];
	}
	
	// Validate data
	
	if (error)
	{
		// If there was an error opening the view, we need to reset the ivars to nil.
		// These are checked at the beginning of this method as a shortcut.
		
		parentConnection->state = nil;
	}
	else
	{
		YDBLogVerbose(@"parentConnection->state: %@", parentConnection->state);
	}
	
	return !error;
}

/**
 * Codebase upgrade helper.
**/
- (void)dropTablesForOldClassVersion:(int)oldClassVersion
{
	YDBLogAutoTrace();
	
	if (oldClassVersion == 1)
	{
		// In version 2, we switched from 'view_name_key' to 'view_name_map'.
		// The old table stored key->pageKey mappings.
		// The new table stores rowid->pageKey mappings.
		//
		// So we can drop the old table.
		
		sqlite3 *db = databaseTransaction->connection->db;
		
		NSString *keyTableName = [NSString stringWithFormat:@"view_%@_key", [self registeredName]];
		
		NSString *dropKeyTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", keyTableName];
		
		int status = sqlite3_exec(db, [dropKeyTable UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ - Failed dropping key table (%@): %d %s",
						THIS_METHOD, keyTableName, status, sqlite3_errmsg(db));
		}
	}
	
	if (oldClassVersion == 1 || oldClassVersion == 2)
	{
		// In version 3, we changed the columns of the 'view_name_page' table.
		// The old table stored all metadata in a blob.
		// The new table stores each metadata item in its own column.
		//
		// This new layout reduces the amount of data we have to write to the table.
		
		sqlite3 *db = databaseTransaction->connection->db;
		
		NSString *dropPageTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", [self pageTableName]];
		
		int status = sqlite3_exec(db, [dropPageTable UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ - Failed dropping old page table (%@): %d %s",
						THIS_METHOD, dropPageTable, status, sqlite3_errmsg(db));
		}
	}
}

/**
 * Subclasses can easily override this method to create their own tables.
 * If overriden, don't forget to invoke [super createTables].
**/
- (BOOL)createTables
{
	YDBLogAutoTrace();
	
	if ([self isPersistentView])
	{
		sqlite3 *db = databaseTransaction->connection->db;
		
		NSString *mapTableName = [self mapTableName];
		NSString *pageTableName = [self pageTableName];
		
		YDBLogVerbose(@"Creating view tables for registeredName(%@): %@, %@",
		              [self registeredName], mapTableName, pageTableName);
		
		NSString *createMapTable = [NSString stringWithFormat:
		    @"CREATE TABLE IF NOT EXISTS \"%@\""
		    @" (\"rowid\" INTEGER PRIMARY KEY,"
		    @"  \"pageKey\" CHAR NOT NULL"
		    @" );", mapTableName];
		
		NSString *createPageTable = [NSString stringWithFormat:
		    @"CREATE TABLE IF NOT EXISTS \"%@\""
		    @" (\"pageKey\" CHAR NOT NULL PRIMARY KEY,"
		    @"  \"group\" CHAR NOT NULL,"
		    @"  \"prevPageKey\" CHAR,"
		    @"  \"count\" INTEGER,"
		    @"  \"data\" BLOB"
		    @" );", pageTableName];
		
		int status;
		
		status = sqlite3_exec(db, [createMapTable UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ - Failed creating map table (%@): %d %s",
			            THIS_METHOD, mapTableName, status, sqlite3_errmsg(db));
			return NO;
		}
		
		status = sqlite3_exec(db, [createPageTable UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ - Failed creating page table (%@): %d %s",
			            THIS_METHOD, pageTableName, status, sqlite3_errmsg(db));
			return NO;
		}
		
		return YES;
	}
	else // if (isNonPersistentView)
	{
		NSString *mapTableName = [self mapTableName];
		NSString *pageTableName = [self pageTableName];
		NSString *pageMetadataTableName = [self pageMetadataTableName];
		
		YapMemoryTable *mapTable = [[YapMemoryTable alloc] initWithKeyClass:[NSNumber class]];
		YapMemoryTable *pageTable = [[YapMemoryTable alloc] initWithKeyClass:[NSString class]];
		YapMemoryTable *pageMetadataTable = [[YapMemoryTable alloc] initWithKeyClass:[NSString class]];
		
		if (![databaseTransaction->connection registerMemoryTable:mapTable withName:mapTableName])
		{
			YDBLogError(@"%@ - Failed registering map table", THIS_METHOD);
			return NO;
		}
		
		if (![databaseTransaction->connection registerMemoryTable:pageTable withName:pageTableName])
		{
			YDBLogError(@"%@ - Failed registering page table", THIS_METHOD);
			return NO;
		}
		
		if (![databaseTransaction->connection registerMemoryTable:pageMetadataTable withName:pageMetadataTableName])
		{
			YDBLogError(@"%@ - Failed registering pageMetadata table", THIS_METHOD);
			return NO;
		}
		
		mapTableTransaction = [databaseTransaction memoryTableTransaction:mapTableName];
		pageTableTransaction = [databaseTransaction memoryTableTransaction:pageTableName];
		pageMetadataTableTransaction = [databaseTransaction memoryTableTransaction:pageMetadataTableName];
		
		return YES;
	}
}

/**
 * Method designed for subclasses to override.
**/
- (BOOL)populateView
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionTransaction.
**/
- (YapDatabaseReadTransaction *)databaseTransaction
{
	return databaseTransaction;
}

/**
 * Required override method from YapDatabaseExtensionTransaction.
**/
- (YapDatabaseExtensionConnection *)extensionConnection
{
	return parentConnection;
}

- (NSString *)registeredName
{
	return [parentConnection->parent registeredName];
}

- (NSString *)mapTableName
{
	return [parentConnection->parent mapTableName];
}

- (NSString *)pageTableName
{
	return [parentConnection->parent pageTableName];
}

- (NSString *)pageMetadataTableName
{
	return [parentConnection->parent pageMetadataTableName];
}

- (BOOL)isPersistentView
{
	return parentConnection->parent->options.isPersistent;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Serialization & Deserialization
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSData *)serializePage:(YapDatabaseViewPage *)page
{
	return [page serialize];
}

- (YapDatabaseViewPage *)deserializePage:(NSData *)data
{
	YapDatabaseViewPage *page = [[YapDatabaseViewPage alloc] init];
	[page deserialize:data];
	
	return page;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)generatePageKey
{
	return [[NSUUID UUID] UUIDString];
}

/**
 * If the given rowid is in the view, returns the associated pageKey.
 *
 * This method will use the cache(s) if possible.
 * Otherwise it will lookup the value in the map table.
**/
- (NSString *)pageKeyForRowid:(int64_t)rowid
{
	NSString *pageKey = nil;
	NSNumber *rowidNumber = @(rowid);
	
	// Check dirty cache & clean cache
	
	pageKey = [parentConnection->dirtyMaps objectForKey:rowidNumber];
	if (pageKey)
	{
		if ((id)pageKey == (id)[NSNull null])
			return nil;
		else
			return pageKey;
	}
	
	pageKey = [parentConnection->mapCache objectForKey:rowidNumber];
	if (pageKey)
	{
		if ((id)pageKey == (id)[NSNull null])
			return nil;
		else
			return pageKey;
	}
	
	// Otherwise pull from the database
	
	if ([self isPersistentView])
	{
		sqlite3_stmt *statement = [parentConnection mapTable_getPageKeyForRowidStatement];
		if (statement == NULL)
			return nil;
		
		// SELECT "pageKey" FROM "mapTableName" WHERE "rowid" = ? ;
		
		int const column_idx_pageKey = SQLITE_COLUMN_START;
		int const bind_idx_rowid     = SQLITE_BIND_START;
		
		sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			const unsigned char *text = sqlite3_column_text(statement, column_idx_pageKey);
			int textSize = sqlite3_column_bytes(statement, column_idx_pageKey);
			
			pageKey = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"%@ (%@): Error executing statement: %d %s",
			            THIS_METHOD, [self registeredName],
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	else // if (isNonPersistentView)
	{
		pageKey = [mapTableTransaction objectForKey:rowidNumber];
	}
	
	if (pageKey)
		[parentConnection->mapCache setObject:pageKey forKey:rowidNumber];
	else
		[parentConnection->mapCache setObject:[NSNull null] forKey:rowidNumber];
	
	return pageKey;
}

/**
 * Fetches the page for the given pageKey.
 * 
 * This method will use the cache(s) if possible.
 * Otherwise it will load the data from the page table and deserialize it.
**/
- (YapDatabaseViewPage *)pageForPageKey:(NSString *)pageKey
{
	YapDatabaseViewPage *page = nil;
	
	// Check dirty cache & clean cache
	
	page = [parentConnection->dirtyPages objectForKey:pageKey];
	if (page) return page;
	
	page = [parentConnection->pageCache objectForKey:pageKey];
	if (page) return page;
	
	// Otherwise pull from the database
	
	if ([self isPersistentView])
	{
		sqlite3_stmt *statement = [parentConnection pageTable_getDataForPageKeyStatement];
		if (statement == NULL)
			return nil;
		
		// SELECT "data" FROM 'pageTableName' WHERE pageKey = ? ;
		
		int const column_idx_data  = SQLITE_COLUMN_START;
		int const bind_idx_pageKey = SQLITE_BIND_START;
		
		YapDatabaseString _pageKey; MakeYapDatabaseString(&_pageKey, pageKey);
		sqlite3_bind_text(statement, bind_idx_pageKey, _pageKey.str, _pageKey.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			const void *blob = sqlite3_column_blob(statement, column_idx_data);
			int blobSize = sqlite3_column_bytes(statement, column_idx_data);
			
			NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			
			page = [self deserializePage:data];
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"%@ (%@): Error executing statement: %d %s",
			            THIS_METHOD, [self registeredName],
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_pageKey);
	}
	else // if (isNonPersistentView)
	{
		page = [[pageTableTransaction objectForKey:pageKey] copy];
	}
	
	// Store in cache if found
	if (page)
		[parentConnection->pageCache setObject:page forKey:pageKey];
	
	return page;
}

- (NSUInteger)indexForRowid:(int64_t)rowid inGroup:(NSString *)group withPageKey:(NSString *)pageKey
{
	// Calculate the offset of the corresponding page within the group.
	
	NSUInteger pageOffset = 0;
	NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		if ([pageMetadata->pageKey isEqualToString:pageKey])
		{
			break;
		}
		
		pageOffset += pageMetadata->count;
	}
	
	// Fetch the actual page (ordered array of rowid's)
	
	YapDatabaseViewPage *page = [self pageForPageKey:pageKey];
	
	// Find the exact index of the rowid within the page
	
	NSUInteger indexWithinPage = 0;
	BOOL found = [page getIndex:&indexWithinPage ofRowid:rowid];
	
	#pragma unused(found)
	NSAssert(found, @"Missing rowid in page");
	
	// Return the full index of the rowid within the group
	
	return pageOffset + indexWithinPage;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logic - ReadOnly
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)containsRowid:(int64_t)rowid
{
	return ([self pageKeyForRowid:rowid] != nil);
}

- (NSString *)groupForRowid:(int64_t)rowid
{
	return [parentConnection->state groupForPageKey:[self pageKeyForRowid:rowid]];
}

- (YapDatabaseViewLocator *)locatorForRowid:(int64_t)rowid
{
	YapDatabaseViewLocator *locator = nil;
	
	NSString *pageKey = [self pageKeyForRowid:rowid];
	if (pageKey)
	{
		NSString *group = [parentConnection->state groupForPageKey:pageKey];
		if (group)
		{
			NSUInteger index = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
			
			locator = [[YapDatabaseViewLocator alloc] initWithGroup:group index:index pageKey:pageKey];
		}
	}
	
	return locator;
}

/**
 * This method looks up a whole bunch of locators using a minimal number of SQL queries.
 *
 * @param rowids
 *     All the rowids to lookup.
 * 
 * @return
 *     A dictionary of the form: @{
 *       @(rowid) = YapDatabaseViewLocator, ... }
 *     }
 *     If a rowid isn't in the view, it won't be represented in the dictionary.
**/
- (NSDictionary *)locatorsForRowids:(NSArray *)rowids
{
	if (rowids.count == 0)
	{
		return [NSDictionary dictionary];
	}
	if (rowids.count == 1)
	{
		int64_t rowid = [[rowids firstObject] longLongValue];
		YapDatabaseViewLocator *locator = [self locatorForRowid:rowid];
		
		if (locator)
			return @{ @(rowid) : locator };
		else
			return [NSDictionary dictionary];
	}
	
	NSMutableDictionary *pageKeys = [NSMutableDictionary dictionaryWithCapacity:rowids.count];
	NSMutableArray *remainingRowids = [NSMutableArray arrayWithCapacity:rowids.count];
	
	// Step 1 of 3:
	//
	// Check for any (rowid -> pageKey) information we already have in memory.
	//
	// This is actually a requirement if the information is in dirtyMaps.
	// If the info is in mapCache, then its just an optimization.
	
	for (NSNumber *rowidNumber in rowids)
	{
		NSString *pageKey = nil;
		
		pageKey = [parentConnection->dirtyMaps objectForKey:rowidNumber];
		if (pageKey == nil)
		{
			pageKey = [parentConnection->mapCache objectForKey:rowidNumber];
		}
		
		if (pageKey)
		{
			if ((id)pageKey == (id)[NSNull null])
			{
				// This rowid has already been removed from the view,
				// and is marked for deletion from the mapTable.
			}
			else
			{
				pageKeys[rowidNumber] = pageKey;
			}
		}
		else
		{
			[remainingRowids addObject:rowidNumber];
		}
		
	}
	
	// Step 2 of 3:
	//
	// Fetch any pageKey information we're still missing from the database.
	
	if ([self isPersistentView])
	{
		sqlite3 *db = databaseTransaction->connection->db;
		
		while (remainingRowids.count > 0)
		{
			// Don't forget about sqlite's upper bound on host parameters.
			
			NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
			
			NSUInteger count = MIN(remainingRowids.count, maxHostParams);
			
			// SELECT "rowid", "pageKey" FROM "mapTableName" WHERE "rowid" IN (?, ?, ...);
			
			int const column_idx_rowid   = SQLITE_COLUMN_START + 0;
			int const column_idx_pageKey = SQLITE_COLUMN_START + 1;
			
			NSUInteger capacity = 50 + (count * 3);
			NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
			
			[query appendFormat:@"SELECT \"rowid\", \"pageKey\" FROM \"%@\" WHERE \"rowid\" IN (", [self mapTableName]];
			
			for (NSUInteger i = 0; i < count; i++)
			{
				if (i == 0)
					[query appendString:@"?"];
				else
					[query appendString:@", ?"];
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
				            THIS_METHOD, [self registeredName], status, sqlite3_errmsg(db), query);
				
				return nil;
			}
			
			for (NSUInteger i = 0; i < count; i++)
			{
				int64_t rowid = [[remainingRowids objectAtIndex:i] longLongValue];
				
				sqlite3_bind_int64(statement, (int)(SQLITE_BIND_START + i), rowid);
			}
			
			while ((status = sqlite3_step(statement)) == SQLITE_ROW)
			{
				// Extract rowid & pageKey from row
				
				int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
				
				const unsigned char *text = sqlite3_column_text(statement, column_idx_pageKey);
				int textSize = sqlite3_column_bytes(statement, column_idx_pageKey);
				
				NSString *pageKey = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				
				// Add to result dictionary
				
				pageKeys[@(rowid)] = pageKey;
			}
			
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"%@ (%@): Error executing statement: %d %s",
				            THIS_METHOD, [self registeredName], status, sqlite3_errmsg(db));
			}
		
			sqlite3_finalize(statement);
			
			[remainingRowids removeObjectsInRange:NSMakeRange(0, count)];
			
		} // end while (remainingRowids.count > 0)
	}
	else // if (isNonPersistentView)
	{
		if (remainingRowids.count > 0)
		{
			[mapTableTransaction accessWithBlock:^{ @autoreleasepool {
				
				for (NSNumber *rowidNumber in remainingRowids)
				{
					NSString *pageKey = [mapTableTransaction objectForKey:rowidNumber];
					if (pageKey)
					{
						// Add to result dictionary
						
						pageKeys[rowidNumber] = pageKey;
					}
				}
			}}];
		}
	}
	
	// Step 3 of 3
	//
	// Use the pageKey mappings to create the locators.
	//
	// In order to do this, we'll need to fetch the page for each rowid.
	// And since many of the rowids may share the same page,
	// we'll optimize the IO by sorting rowids by pageKey first.
	
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:pageKeys.count];
	
	NSArray *sortedRowids = [pageKeys keysSortedByValueUsingSelector:@selector(compare:)];
	for (NSNumber *rowidNumber in sortedRowids)
	{
		NSString *pageKey = pageKeys[rowidNumber];
		
		NSString *group = [parentConnection->state groupForPageKey:pageKey];
		if (group)
		{
			int64_t rowid = [rowidNumber longLongValue];
			NSUInteger index = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
			
			YapDatabaseViewLocator *locator =
			  [[YapDatabaseViewLocator alloc] initWithGroup:group index:index pageKey:pageKey];
			
			result[rowidNumber] = locator;
		}
	}
	
	return result;
}

- (BOOL)getRowid:(int64_t *)rowidPtr atIndex:(NSUInteger)index inGroup:(NSString *)group
{
	NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
	NSUInteger pageOffset = 0;
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		if ((index < (pageOffset + pageMetadata->count)) && (pageMetadata->count > 0))
		{
			YapDatabaseViewPage *page = [self pageForPageKey:pageMetadata->pageKey];
			
			int64_t rowid = [page rowidAtIndex:(index - pageOffset)];
			
			if (rowidPtr) *rowidPtr = rowid;
			return YES;
		}
		else
		{
			pageOffset += pageMetadata->count;
		}
	}
	
	if (rowidPtr) *rowidPtr = 0;
	return NO;
}

- (BOOL)getLastRowid:(int64_t *)rowidPtr inGroup:(NSString *)group
{
	// We can actually do something a little faster than this:
	//
	// NSUInteger count = [self numberOfItemsInGroup:group];
	// if (count > 0)
	//     return [self getRowid:rowidPtr atIndex:(count-1) inGroup:group];
	// else
	//     return nil;
	
	NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
	
	__block int64_t rowid = 0;
	__block BOOL found = NO;
	
	[pagesMetadataForGroup enumerateObjectsWithOptions:NSEnumerationReverse
	                                        usingBlock:^(id obj, NSUInteger __unused idx, BOOL *stop) {
												
		__unsafe_unretained YapDatabaseViewPageMetadata *pageMetadata = (YapDatabaseViewPageMetadata *)obj;
		
		if (pageMetadata->count > 0)
		{
			YapDatabaseViewPage *lastPage = [self pageForPageKey:pageMetadata->pageKey];
			
			rowid = [lastPage rowidAtIndex:(pageMetadata->count - 1)];
			found = YES;
			*stop = YES;
		}
	}];
	
	if (rowidPtr) *rowidPtr = rowid;
	return found;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logic - ReadWrite
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This is an internal method that modifies the underlying structures that hold the arrays of rowids.
 * These structures are meant to be private, and knowledge of how they work shouldn't be required by subclasses.
 * Subclasses should always use these internal methods,
 * and should never attempt to modify the internal structures themselves.
 *
 * Remember:
 * The internal structure may change in future versions.
 * When this happens, subclasses that disobey this rule will break.
**/
- (void)insertRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
                                         inGroup:(NSString *)group
                                         atIndex:(NSUInteger)index
{
	YDBLogAutoTrace();
	
	NSParameterAssert(collectionKey != nil);
	NSParameterAssert(group != nil);
	
	// Find pageMetadata, pageKey and page
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	
	NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
	
	if (pagesMetadataForGroup == nil)
	{
		// First object added to group.
		
		NSString *pageKey = [self generatePageKey];
		
		YDBLogVerbose(@"Inserting key(%@) collection(%@) in new group(%@) with page(%@)",
					  collectionKey.key, collectionKey.collection, group, pageKey);
		
		// Create page
		
		YapDatabaseViewPage *page =
		  [[YapDatabaseViewPage alloc] initWithCapacity:YAP_DATABASE_VIEW_MAX_PAGE_SIZE];
		[page addRowid:rowid];
		
		// Create pageMetadata
		
		pageMetadata = [[YapDatabaseViewPageMetadata alloc] init];
		pageMetadata->pageKey = pageKey;
		pageMetadata->prevPageKey = nil;
		pageMetadata->group = group;
		pageMetadata->count = 1;
		pageMetadata->isNew = YES;
		
		// Add pageMetadata to state
		
		[parentConnection->state createGroup:group withCapacity:1];
		[parentConnection->state addPageMetadata:pageMetadata toGroup:group];
		
		// Mark page as dirty
		
		[parentConnection->dirtyPages setObject:page forKey:pageKey];
		[parentConnection->pageCache setObject:page forKey:pageKey];
		
		// Mark map as dirty
		
		[parentConnection->dirtyMaps setObject:pageKey forKey:@(rowid) withPreviousValue:nil];
		[parentConnection->mapCache setObject:pageKey forKey:@(rowid)];
		
		// Add change to log
		
		[parentConnection->changes addObject:
		  [YapDatabaseViewSectionChange insertGroup:group]];
		
		[parentConnection->changes addObject:
		  [YapDatabaseViewRowChange insertCollectionKey:collectionKey inGroup:group atIndex:0]];
		
		[parentConnection->mutatedGroups addObject:group];
	}
	else
	{
		NSUInteger pageOffset = 0;
		NSUInteger pageIndex = 0;
		
		NSUInteger lastPageIndex = [pagesMetadataForGroup count] - 1;
		
		for (YapDatabaseViewPageMetadata *pm in pagesMetadataForGroup)
		{
			// Edge case: key is being inserted at the very end
			
			if ((index < (pageOffset + pm->count)) || (pageIndex == lastPageIndex))
			{
				pageMetadata = pm;
				break;
			}
			else if (index == (pageOffset + pm->count))
			{
				// Optimization:
				// The insertion index is in-between two pages.
				// So it could go at the end of this page, or the beginning of the next page.
				//
				// We always place the key in the next page, unless:
				// - this page has room AND
				// - the next page is already full
				//
				// Related method: splitOversizedPage:
				
				NSUInteger maxPageSize = YAP_DATABASE_VIEW_MAX_PAGE_SIZE;
				
				if (pm->count < maxPageSize)
				{
					YapDatabaseViewPageMetadata *nextpm = [pagesMetadataForGroup objectAtIndex:(pageIndex+1)];
					if (nextpm->count >= maxPageSize)
					{
						pageMetadata = pm;
						break;
					}
				}
			}
			
			pageIndex++;
			pageOffset += pm->count;
		}
		
		NSAssert(pageMetadata != nil, @"Missing pageMetadata in group(%@)", group);
		
		NSString *pageKey = pageMetadata->pageKey;
		YapDatabaseViewPage *page = [self pageForPageKey:pageKey];
		
		YDBLogVerbose(@"Inserting key(%@) collection(%@) in group(%@) at index(%lu) with page(%@) pageOffset(%lu)",
		              collectionKey.key, collectionKey.collection, group,
		              (unsigned long)index, pageKey, (unsigned long)(index - pageOffset));
		
		// Update page (insert rowid)
		
		[page insertRowid:rowid atIndex:(index - pageOffset)];
		
		// Update pageMetadata (increment count)
		
		pageMetadata->count = [page count];
		
		// Mark page as dirty
		
		[parentConnection->dirtyPages setObject:page forKey:pageKey];
		[parentConnection->pageCache setObject:page forKey:pageKey];
		
		// Mark map as dirty
		
		[parentConnection->dirtyMaps setObject:pageKey forKey:@(rowid)  withPreviousValue:nil];
		[parentConnection->mapCache setObject:pageKey forKey:@(rowid)];
		
		// Add change to log
		
		[parentConnection->changes addObject:
		  [YapDatabaseViewRowChange insertCollectionKey:collectionKey inGroup:group atIndex:index]];
		
		[parentConnection->mutatedGroups addObject:group];
		
		// During a transaction we allow pages to grow in size beyond the max page size.
		// This increases efficiency, as we can allow multiple changes to occur,
		// but perform the cleanup task only once (of splitting oversized pages ).
		//
		// However, we do want to avoid allowing a single page to grow infinitely large.
		// So we use triggers to ensure pages don't get too big.
		
		NSUInteger trigger = YAP_DATABASE_VIEW_MAX_PAGE_SIZE * 32;
		NSUInteger target = YAP_DATABASE_VIEW_MAX_PAGE_SIZE * 16;
		
		if ([page count] > trigger)
		{
			[self splitOversizedPage:page withPageKey:pageKey toSize:target];
		}
	}
}

/**
 * This is an internal method that modifies the underlying structures that hold the arrays of rowids.
 * These structures are meant to be private, and knowledge of how they work shouldn't be required by subclasses.
 * Subclasses should always use these internal methods,
 * and should never attempt to modify the internal structures themselves.
 *
 * Remember:
 * The internal structure may change in future versions.
 * When this happens, subclasses that disobey this rule will break.
**/
- (void)removeRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
{
	YDBLogAutoTrace();
	
	// Find out if collection/key is in view
	
	YapDatabaseViewLocator *locator = [self locatorForRowid:rowid];
	if (locator)
	{
		[self removeRowid:rowid collectionKey:collectionKey withLocator:locator];
	}
}

/**
 * This is an internal method that modifies the underlying structures that hold the arrays of rowids.
 * These structures are meant to be private, and knowledge of how they work shouldn't be required by subclasses.
 * Subclasses should always use these internal methods,
 * and should never attempt to modify the internal structures themselves.
 *
 * Remember:
 * The internal structure may change in future versions.
 * When this happens, subclasses that disobey this rule will break.
**/
- (void)removeRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
                                         atIndex:(NSUInteger)index
                                         inGroup:(NSString *)group
{
	[self removeRowid:rowid
	    collectionKey:collectionKey
	          atIndex:index
	          inGroup:group
	      withPageKey:nil];
}

/**
 * This is an internal method that modifies the underlying structures that hold the arrays of rowids.
 * These structures are meant to be private, and knowledge of how they work shouldn't be required by subclasses.
 * Subclasses should always use these internal methods,
 * and should never attempt to modify the internal structures themselves.
 *
 * Remember:
 * The internal structure may change in future versions.
 * When this happens, subclasses that disobey this rule will break.
**/
- (void)removeRowid:(int64_t)rowid
      collectionKey:(YapCollectionKey *)collectionKey
        withLocator:(YapDatabaseViewLocator *)locator
{
	[self removeRowid:rowid
	    collectionKey:collectionKey
	          atIndex:locator.index
	          inGroup:locator.group
	      withPageKey:locator.pageKey];
}

/**
 * This is an internal method that modifies the underlying structures that hold the arrays of rowids.
 * These structures are meant to be private, and knowledge of how they work shouldn't be required by subclasses.
 * Subclasses should always use these internal methods,
 * and should never attempt to modify the internal structures themselves.
 *
 * Remember:
 * The internal structure may change in future versions.
 * When this happens, subclasses that disobey this rule will break.
**/
- (void)removeRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
                                         atIndex:(NSUInteger)index
                                         inGroup:(NSString *)group
                                     withPageKey:(NSString *)pageKey
{
	YDBLogAutoTrace();
	
	NSParameterAssert(collectionKey != nil);
	NSParameterAssert(group != nil);
	
	// Fetch pageKey (if unknown)
	
	if (pageKey == nil)
		pageKey = [self pageKeyForRowid:rowid];
	
	NSAssert(pageKey != nil, @"Missing pageKey for rowid(%lld) in group(%@)", rowid, group);
	
	// Fetch page & pageMetadata
	
	YapDatabaseViewPage *page = [self pageForPageKey:pageKey];
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	NSUInteger pageOffset = 0;
	
	NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
	
	for (YapDatabaseViewPageMetadata *pm in pagesMetadataForGroup)
	{
		if ([pm->pageKey isEqualToString:pageKey])
		{
			pageMetadata = pm;
			break;
		}
		
		pageOffset += pm->count;
	}
	
	NSAssert(pageMetadata != nil, @"Missing pageMetadata in group(%@) withPageKey(%@)", group, pageKey);
	
	// Find index within page
	
	NSUInteger indexWithinPage = 0;
	BOOL found = [page getIndex:&indexWithinPage ofRowid:rowid];
	
	if (!found)
	{
		YDBLogError(@"%@ (%@): collection(%@) key(%@) expected to be in page(%@), but is missing",
		            THIS_METHOD, [self registeredName], collectionKey.collection, collectionKey.key, pageKey);
		return;
	}
	
	YDBLogVerbose(@"Removing collection(%@) key(%@) from page(%@) at index(%lu)",
	              collectionKey.collection, collectionKey.key, page, (unsigned long)indexWithinPage);
	
	// Add change to log
	
	NSUInteger indexWithinGroup = pageOffset + indexWithinPage;
	
	[parentConnection->changes addObject:
	  [YapDatabaseViewRowChange deleteCollectionKey:collectionKey inGroup:group atIndex:indexWithinGroup]];
	
	[parentConnection->mutatedGroups addObject:group];
	
	// Update page (by removing key from array)
	
	[page removeRowidAtIndex:indexWithinPage];
	
	// Update page metadata (by decrementing count)
	
	pageMetadata->count = [page count];
	
	// Mark page as dirty
	
	YDBLogVerbose(@"Dirty page(%@)", pageKey);
	
	[parentConnection->dirtyPages setObject:page forKey:pageKey];
	[parentConnection->pageCache setObject:page forKey:pageKey];
	
	// Mark map as dirty
	
	[parentConnection->dirtyMaps setObject:[NSNull null] forKey:@(rowid) withPreviousValue:pageKey];
	[parentConnection->mapCache removeObjectForKey:@(rowid)];
}

/**
 * This is an internal method that modifies the underlying structures that hold the arrays of rowids.
 * These structures are meant to be private, and knowledge of how they work shouldn't be required by subclasses.
 * Subclasses should always use these internal methods,
 * and should never attempt to modify the internal structures themselves.
 *
 * Remember:
 * The internal structure may change in future versions.
 * When this happens, subclasses that disobey this rule will break.
**/
- (void)removeRowidsWithCollectionKeys:(NSDictionary<NSNumber *, YapCollectionKey *> *)collectionKeys
                              locators:(NSDictionary<NSNumber *, YapDatabaseViewLocator *> *)locators
{
	// Let's optimize IO by enumerating the items by pageKey.
	// That is, group our changes by page.
	
	NSArray *sortedRowids = [locators keysSortedByValueUsingComparator:
		^NSComparisonResult(YapDatabaseViewLocator *locator1, YapDatabaseViewLocator *locator2)
	{
		__unsafe_unretained NSString *pageKey1 = locator1.pageKey;
		__unsafe_unretained NSString *pageKey2 = locator2.pageKey;
		
		if (pageKey1)
		{
			if (pageKey2)
				return [pageKey1 compare:pageKey2];
			else
				return NSOrderedAscending;
		}
		else if (pageKey2)
		{
			return NSOrderedDescending;
		}
		else
		{
			return NSOrderedSame;
		}
	}];
	
	for (NSNumber *rowidNumber in sortedRowids)
	{
		int64_t rowid = [rowidNumber longLongValue];
		
		YapCollectionKey *collectionKey = collectionKeys[rowidNumber];
		YapDatabaseViewLocator *locator = locators[rowidNumber];
		
		NSAssert(collectionKey != nil, @"Missing collectionKey for rowid !");
		
		[self removeRowid:rowid collectionKey:collectionKey withLocator:locator];
	}
}

/**
 * This is an internal method that modifies the underlying structures that hold the arrays of rowids.
 * These structures are meant to be private, and knowledge of how they work shouldn't be required by subclasses.
 * Subclasses should always use these internal methods,
 * and should never attempt to modify the internal structures themselves.
 *
 * Remember:
 * The internal structure may change in future versions.
 * When this happens, subclasses that disobey this rule will break.
**/
- (void)removeAllRowidsInGroup:(NSString *)group
{
	NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
	NSMutableArray *removedRowids = [NSMutableArray array];
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		YapDatabaseViewPage *page = [self pageForPageKey:pageMetadata->pageKey];
		
		// Mark all rowids for deletion
		
		[page enumerateRowidsUsingBlock:^(int64_t rowid, NSUInteger __unused idx, BOOL __unused *stop) {
			
			[removedRowids addObject:@(rowid)];
			
			[parentConnection->dirtyMaps setObject:[NSNull null] forKey:@(rowid) withPreviousValue:pageMetadata->pageKey];
			[parentConnection->mapCache removeObjectForKey:@(rowid)];
		}];
		
		// Update page (by removing all rowids from array)
		
		[page removeAllRowids];
		
		// Update page metadata (by clearing count)
		
		pageMetadata->count = 0;
		
		// Mark page as dirty
		
		YDBLogVerbose(@"Dirty page(%@)", pageMetadata->pageKey);
		
		[parentConnection->dirtyPages setObject:page forKey:pageMetadata->pageKey];
		[parentConnection->pageCache setObject:page forKey:pageMetadata->pageKey];
	}
	
	[parentConnection->changes addObject:[YapDatabaseViewSectionChange resetGroup:group]];
	[parentConnection->mutatedGroups addObject:group];
}

/**
 * This is an internal method that modifies the underlying structures that hold the arrays of rowids.
 * These structures are meant to be private, and knowledge of how they work shouldn't be required by subclasses.
 * Subclasses should always use these internal methods,
 * and should never attempt to modify the internal structures themselves.
 *
 * Remember:
 * The internal structure may change in future versions.
 * When this happens, subclasses that disobey this rule will break.
**/
- (void)removeAllRowids
{
	YDBLogAutoTrace();
	
	if ([self isPersistentView])
	{
		sqlite3_stmt *mapStatement = [parentConnection mapTable_removeAllStatement];
		sqlite3_stmt *pageStatement = [parentConnection pageTable_removeAllStatement];
		
		if (mapStatement == NULL || pageStatement == NULL)
			return;
		
		int status;
		
		// DELETE FROM "mapTableName";
		
		YDBLogVerbose(@"DELETE FROM '%@';", [self mapTableName]);
		
		status = sqlite3_step(mapStatement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ (%@): Error in mapStatement: %d %s",
			            THIS_METHOD, [self registeredName],
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		// DELETE FROM 'pageTableName';
		
		YDBLogVerbose(@"DELETE FROM '%@';", [self pageTableName]);
		
		status = sqlite3_step(pageStatement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ (%@): Error in pageStatement: %d %s",
			            THIS_METHOD, [self registeredName],
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite3_reset(mapStatement);
		sqlite3_reset(pageStatement);
	}
	else // if (isNonPersistentView)
	{
		[mapTableTransaction removeAllObjects];
		[pageTableTransaction removeAllObjects];
		[pageMetadataTableTransaction removeAllObjects];
	}
	
	[parentConnection->state enumerateGroupsWithBlock:^(NSString *group, BOOL __unused *stop) {
		
		if (!isRepopulate) {
			[parentConnection->changes addObject:[YapDatabaseViewSectionChange resetGroup:group]];
		}
		[parentConnection->mutatedGroups addObject:group];
	}];
	
	[parentConnection->state removeAllGroups];
	
	[parentConnection->mapCache removeAllObjects];
	[parentConnection->pageCache removeAllObjects];
	
	[parentConnection->dirtyMaps removeAllObjects];
	[parentConnection->dirtyPages removeAllObjects];
	[parentConnection->dirtyLinks removeAllObjects];
	
	parentConnection->reset = YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cleanup & Commit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)splitOversizedPage:(YapDatabaseViewPage *)page withPageKey:(NSString *)pageKey toSize:(NSUInteger)maxPageSize
{
	YDBLogAutoTrace();
	
	// Find associated pageMetadata
	
	NSString *group = [parentConnection->state groupForPageKey:pageKey];
	NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
	
	YapDatabaseViewPageMetadata *pageMetadata;
	for (YapDatabaseViewPageMetadata *pm in pagesMetadataForGroup)
	{
		if ([pm->pageKey isEqualToString:pageKey])
		{
			pageMetadata = pm;
			break;
		}
	}
	
	NSAssert(pageMetadata != nil, @"Missing pageMetadata in group(%@) withPageKey(%@)", group, pageKey);
	
	// Split the page as many times as needed to make it fit the designated maxPageSize
	
	while (pageMetadata && pageMetadata->count > maxPageSize)
	{
		// Get the current pageIndex.
		// This may change during iterations of the while loop.
		
		NSUInteger pageIndex = [pagesMetadataForGroup indexOfObjectIdenticalTo:pageMetadata];
		
		// Check to see if there's room in the previous page
		
		if (pageIndex > 0)
		{
			YapDatabaseViewPageMetadata *prevPageMetadata = [pagesMetadataForGroup objectAtIndex:(pageIndex - 1)];
			
			if (prevPageMetadata->count < maxPageSize)
			{
				// Move objects from beginning of page to end of previous page
				
				YapDatabaseViewPage *prevPage = [self pageForPageKey:prevPageMetadata->pageKey];
				
				NSUInteger excessInPage = pageMetadata->count - maxPageSize;
				NSUInteger spaceInPrevPage = maxPageSize - prevPageMetadata->count;
				
				NSUInteger numToMove = MIN(excessInPage, spaceInPrevPage);
				
				NSRange pageRange = NSMakeRange(0, numToMove);                    // beginning range
				NSRange prevPageRange = NSMakeRange([prevPage count], numToMove); // end range
				
				[prevPage appendRange:pageRange ofPage:page];
				[page removeRange:pageRange];
				
				// Update counts
				
				pageMetadata->count = [page count];
				prevPageMetadata->count = [prevPage count];
				
				// Mark prevPage as dirty.
				// The page is already marked as dirty.
				
				[parentConnection->dirtyPages setObject:prevPage forKey:prevPageMetadata->pageKey];
				[parentConnection->pageCache setObject:prevPage forKey:prevPageMetadata->pageKey];
				
				// Mark rowid mappings as dirty
				
				[prevPage enumerateRowidsWithOptions:0
				                               range:prevPageRange
				                          usingBlock:^(int64_t rowid, NSUInteger __unused index, BOOL __unused *stop) {
					
					[parentConnection->dirtyMaps setObject:prevPageMetadata->pageKey forKey:@(rowid) withPreviousValue:pageMetadata->pageKey];
					[parentConnection->mapCache setObject:prevPageMetadata->pageKey forKey:@(rowid)];
				}];
				
				continue;
			}
		}
		
		// Check to see if there's room in the next page
		
		if ((pageIndex + 1) < [pagesMetadataForGroup count])
		{
			YapDatabaseViewPageMetadata *nextPageMetadata = [pagesMetadataForGroup objectAtIndex:(pageIndex + 1)];
			
			if (nextPageMetadata->count < maxPageSize)
			{
				// Move objects from end of page to beginning of next page
				
				YapDatabaseViewPage *nextPage = [self pageForPageKey:nextPageMetadata->pageKey];
				
				NSUInteger excessInPage = pageMetadata->count - maxPageSize;
				NSUInteger spaceInNextPage = maxPageSize - nextPageMetadata->count;
				
				NSUInteger numToMove = MIN(excessInPage, spaceInNextPage);
				
				NSRange pageRange = NSMakeRange([page count] - numToMove, numToMove); // end range
				NSRange nextPageRange = NSMakeRange(0, numToMove);                    // beginning range
				
				[nextPage prependRange:pageRange ofPage:page];
				[page removeRange:pageRange];
				
				// Update counts
				
				pageMetadata->count = [page count];
				nextPageMetadata->count = [nextPage count];
				
				// Mark nextPage as dirty.
				// The page is already marked as dirty.
				
				[parentConnection->dirtyPages setObject:nextPage forKey:nextPageMetadata->pageKey];
				[parentConnection->pageCache setObject:nextPage forKey:nextPageMetadata->pageKey];
				
				// Mark rowid mappings as dirty
				
				[nextPage enumerateRowidsWithOptions:0
				                               range:nextPageRange
				                          usingBlock:^(int64_t rowid, NSUInteger __unused index, BOOL __unused *stop) {
					
					[parentConnection->dirtyMaps setObject:nextPageMetadata->pageKey forKey:@(rowid) withPreviousValue:pageMetadata->pageKey];
					[parentConnection->mapCache setObject:nextPageMetadata->pageKey forKey:@(rowid)];
				}];
				
				continue;
			}
		}
	
		// Create new page and pageMetadata.
		// Insert into array.
		
		NSUInteger excessInPage = pageMetadata->count - maxPageSize;
		NSUInteger numToMove = MIN(excessInPage, maxPageSize);
		
		NSString *newPageKey = [self generatePageKey];
		YapDatabaseViewPage *newPage = [[YapDatabaseViewPage alloc] initWithCapacity:numToMove];
		
		// Create new pageMetadata
		
		YapDatabaseViewPageMetadata *newPageMetadata = [[YapDatabaseViewPageMetadata alloc] init];
		newPageMetadata->pageKey = newPageKey;
		newPageMetadata->prevPageKey = pageMetadata->pageKey;
		newPageMetadata->group = pageMetadata->group;
		newPageMetadata->isNew = YES;
		
		// Insert new pageMetadata into array
		
		pagesMetadataForGroup = [parentConnection->state insertPageMetadata:newPageMetadata
		                                                          atIndex:(pageIndex + 1)
		                                                          inGroup:group];
		
		// Update linked-list (if needed)
		
		if ((pageIndex + 2) < [pagesMetadataForGroup count])
		{
			YapDatabaseViewPageMetadata *nextPageMetadata = [pagesMetadataForGroup objectAtIndex:(pageIndex + 2)];
			nextPageMetadata->prevPageKey = newPageKey;
			
			[parentConnection->dirtyLinks setObject:nextPageMetadata forKey:nextPageMetadata->pageKey];
		}
		
		// Move objects from end of page to beginning of new page
		
		NSRange pageRange = NSMakeRange([page count] - numToMove, numToMove); // end range
		
		[newPage appendRange:pageRange ofPage:page];
		[page removeRange:pageRange];
		
		// Update counts
		
		pageMetadata->count = [page count];
		newPageMetadata->count = [newPage count];
		
		// Mark newPage as dirty.
		// The page is already marked as dirty.
		
		[parentConnection->dirtyPages setObject:newPage forKey:newPageKey];
		[parentConnection->pageCache setObject:newPage forKey:newPageKey];
		
		// Mark rowid mappings as dirty
		
		[newPage enumerateRowidsUsingBlock:^(int64_t rowid, NSUInteger __unused idx, BOOL __unused *stop) {
			
			[parentConnection->dirtyMaps setObject:newPageKey forKey:@(rowid) withPreviousValue:pageMetadata->pageKey];
			[parentConnection->mapCache setObject:newPageKey forKey:@(rowid)];
		}];
		
	} // end while (pageMetadata->count > maxPageSize)
}

- (void)dropEmptyPage:(YapDatabaseViewPage __unused *)page withPageKey:(NSString *)pageKey
{
	YDBLogAutoTrace();
	
	// Find associated pageMetadata
	
	NSString *group = [parentConnection->state groupForPageKey:pageKey];
	NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	NSUInteger pageIndex = 0;
	
	for (YapDatabaseViewPageMetadata *pm in pagesMetadataForGroup)
	{
		if ([pm->pageKey isEqualToString:pageKey])
		{
			pageMetadata = pm;
			break;
		}
		
		pageIndex++;
	}
	
	NSAssert(pageMetadata != nil, @"Missing pageMetadata in group(%@)", group);
	
	// Update linked list (if needed)
	
	if ((pageIndex + 1) < [pagesMetadataForGroup count])
	{
		YapDatabaseViewPageMetadata *nextPageMetadata = [pagesMetadataForGroup objectAtIndex:(pageIndex + 1)];
		nextPageMetadata->prevPageKey = pageMetadata->prevPageKey;
		
		[parentConnection->dirtyLinks setObject:nextPageMetadata forKey:nextPageMetadata->pageKey];
	}
	
	// Drop pageMetada (from in-memory state)
	
	pagesMetadataForGroup = [parentConnection->state removePageMetadataAtIndex:pageIndex inGroup:group];
	
	// Mark page as dropped
	
	[parentConnection->dirtyPages setObject:[NSNull null] forKey:pageMetadata->pageKey];
	[parentConnection->pageCache removeObjectForKey:pageMetadata->pageKey];
	
	[parentConnection->dirtyLinks removeObjectForKey:pageMetadata->pageKey];
	
	// Maybe drop group
	
	if ([pagesMetadataForGroup count] == 0)
	{
		YDBLogVerbose(@"Dropping empty group(%@)", pageMetadata->group);
		
		[parentConnection->changes addObject:
		    [YapDatabaseViewSectionChange deleteGroup:pageMetadata->group]];
		
		[parentConnection->state removeGroup:group];
	}
}

/**
 * This method performs the appropriate actions in order to keep the pages of an appropriate size.
 * Specifically it does the following:
 * 
 * - Splits oversized pages to hit our target max_page_size
 * - Drops empty pages to reduce disk usage
**/
- (void)cleanupPages
{
	YDBLogAutoTrace();
	
	// During the readwrite transaction we do nothing to enforce the pageSize restriction.
	// Multiple modifications during a transaction make it non worthwhile.
	//
	// Instead we wait til the transaction has completed
	// and then we can perform all such cleanup in a single step.
	
	NSUInteger maxPageSize = YAP_DATABASE_VIEW_MAX_PAGE_SIZE;
	
	// Get all the dirty pageMetadata objects.
	// We snapshot the items so we can make modifications as we enumerate.
	
	NSArray *pageKeys = [parentConnection->dirtyPages allKeys];
	
	// Step 1 is to "expand" the oversized pages.
	//
	// This means either splitting them in 2,
	// or allowing items to spill over into a neighboring page (that has room).
	
	for (NSString *pageKey in pageKeys)
	{
		YapDatabaseViewPage *page = [parentConnection->dirtyPages objectForKey:pageKey];
		
		if ([page count] > maxPageSize)
		{
			[self splitOversizedPage:page withPageKey:pageKey toSize:maxPageSize];
		}
	}
	
	// Step 2 is to "collapse" undersized pages.
	//
	// This means dropping empty pages,
	// and maybe combining a page with a neighboring page (that has room).
	//
	// Note: We do this after "expansion" to allow undersized pages to first accomodate overflow.
	
	for (NSString *pageKey in pageKeys)
	{
		YapDatabaseViewPage *page = [parentConnection->dirtyPages objectForKey:pageKey];
		
		if ([page count] == 0)
		{
			[self dropEmptyPage:page withPageKey:pageKey];
		}
	}
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * This method is only called if within a readwrite transaction.
 *
 * Subclasses should write any last changes to their database table(s) if needed,
 * and should perform any needed cleanup before the changeset is requested.
 *
 * Remember, the changeset is requested immediately after this method is invoked.
**/
- (void)flushPendingChangesToExtensionTables
{
	YDBLogAutoTrace();
	
	// Cleanup pages (as needed)
	
	[self cleanupPages];
	
	// During the transaction we stored all changes in the "dirty" dictionaries.
	// This allows the view to make multiple changes to a page, yet only write it once.
	
	YDBLogVerbose(@"parentConnection->dirtyPages: %@", parentConnection->dirtyPages);
	YDBLogVerbose(@"parentConnection->dirtyLinks: %@", parentConnection->dirtyLinks);
	YDBLogVerbose(@"parentConnection->dirtyMaps: %@", parentConnection->dirtyMaps);
	
	if ([self isPersistentView])
	{
		// Persistent View: Step 1 of 3
		//
		// Write dirty pages to table (along with associated dirty metadata)
	
		[parentConnection->dirtyPages enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop) {
			
			__unsafe_unretained NSString *pageKey = (NSString *)key;
			__unsafe_unretained YapDatabaseViewPage *page = (YapDatabaseViewPage *)obj;
			
			BOOL needsInsert = NO;
			BOOL hasDirtyLink = NO;
			
			YapDatabaseViewPageMetadata *pageMetadata = nil;
			
			pageMetadata = [parentConnection->dirtyLinks objectForKey:pageKey];
			if (pageMetadata)
			{
				hasDirtyLink = YES;
			}
			else
			{
				NSString *group = [parentConnection->state groupForPageKey:pageKey];
				NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
				
				for (YapDatabaseViewPageMetadata *pm in pagesMetadataForGroup)
				{
					if ([pm->pageKey isEqualToString:pageKey])
					{
						pageMetadata = pm;
						break;
					}
				}
			}
		
			if (pageMetadata && pageMetadata->isNew)
			{
				needsInsert = YES;
				pageMetadata->isNew = NO; // Clear flag
			}
			
			if ((id)page == (id)[NSNull null])
			{
				sqlite3_stmt *statement = [parentConnection pageTable_removeForPageKeyStatement];
				if (statement == NULL)
				{
					NSAssert(NO, @"Cannot get proper statement! View will become corrupt!");
					return;//from block
				}
				
				// DELETE FROM "pageTableName" WHERE "pageKey" = ?;
				
				int const bind_idx_pageKey = SQLITE_BIND_START;
				
				YDBLogVerbose(@"DELETE FROM '%@' WHERE 'pageKey' = ?;\n"
				              @" - pageKey: %@", [self pageTableName], pageKey);
				
				YapDatabaseString _pageKey; MakeYapDatabaseString(&_pageKey, pageKey);
				sqlite3_bind_text(statement, bind_idx_pageKey, _pageKey.str, _pageKey.length, SQLITE_STATIC);
				
				int status = sqlite3_step(statement);
				if (status != SQLITE_DONE)
				{
					YDBLogError(@"%@ (%@): Error executing statement[1a]: %d %s",
					            THIS_METHOD, [self registeredName],
					            status, sqlite3_errmsg(databaseTransaction->connection->db));
				}
				
				sqlite3_clear_bindings(statement);
				sqlite3_reset(statement);
				FreeYapDatabaseString(&_pageKey);
			}
			else if (needsInsert)
			{
				sqlite3_stmt *statement = [parentConnection pageTable_insertForPageKeyStatement];
				if (statement == NULL)
				{
					NSAssert(NO, @"Cannot get proper statement! View will become corrupt!");
					return;//from block
				}
				
				// INSERT INTO "pageTableName"
				//   ("pageKey", "group", "prevPageKey", "count", "data") VALUES (?, ?, ?, ?, ?);
				
				int const bind_idx_pageKey     = SQLITE_BIND_START + 0;
				int const bind_idx_group       = SQLITE_BIND_START + 1;
				int const bind_idx_prevPageKey = SQLITE_BIND_START + 2;
				int const bind_idx_count       = SQLITE_BIND_START + 3;
				int const bind_idx_data        = SQLITE_BIND_START + 4;
				
				YDBLogVerbose(@"INSERT INTO '%@'"
				              @" ('pageKey', 'group', 'prevPageKey', 'count', 'data') VALUES (?,?,?,?,?);\n"
				              @" - pageKey   : %@\n"
				              @" - group     : %@\n"
				              @" - prePageKey: %@\n"
				              @" - count     : %d", [self pageTableName], pageKey,
				              pageMetadata->group, pageMetadata->prevPageKey, (int)pageMetadata->count);
				
				YapDatabaseString _pageKey; MakeYapDatabaseString(&_pageKey, pageKey);
				sqlite3_bind_text(statement, bind_idx_pageKey, _pageKey.str, _pageKey.length, SQLITE_STATIC);
				
				YapDatabaseString _group; MakeYapDatabaseString(&_group, pageMetadata->group);
				sqlite3_bind_text(statement, bind_idx_group, _group.str, _group.length, SQLITE_STATIC);
				
				YapDatabaseString _prevPageKey; MakeYapDatabaseString(&_prevPageKey, pageMetadata->prevPageKey);
				if (pageMetadata->prevPageKey) {
					sqlite3_bind_text(statement, bind_idx_prevPageKey,
					                  _prevPageKey.str, _prevPageKey.length, SQLITE_STATIC);
				}
				
				sqlite3_bind_int(statement, bind_idx_count, (int)(pageMetadata->count));
				
				__attribute__((objc_precise_lifetime)) NSData *rawData = [self serializePage:page];
				sqlite3_bind_blob(statement, bind_idx_data, rawData.bytes, (int)rawData.length, SQLITE_STATIC);
				
				int status = sqlite3_step(statement);
				if (status != SQLITE_DONE)
				{
					YDBLogError(@"%@ (%@): Error executing statement[1b]: %d %s",
					            THIS_METHOD, [self registeredName],
					            status, sqlite3_errmsg(databaseTransaction->connection->db));
				}
				
				sqlite3_clear_bindings(statement);
				sqlite3_reset(statement);
				FreeYapDatabaseString(&_prevPageKey);
				FreeYapDatabaseString(&_group);
				FreeYapDatabaseString(&_pageKey);
			}
			else if (hasDirtyLink)
			{
				sqlite3_stmt *statement = [parentConnection pageTable_updateAllForPageKeyStatement];
				if (statement == NULL)
				{
					NSAssert(NO, @"Cannot get proper statement! View will become corrupt!");
					return;//from block
				}
				
				// UPDATE "pageTableName" SET "prevPageKey" = ?, "count" = ?, "data" = ? WHERE "pageKey" = ?;
				
				int const bind_idx_prevPageKey = SQLITE_BIND_START + 0;
				int const bind_idx_count       = SQLITE_BIND_START + 1;
				int const bind_idx_data        = SQLITE_BIND_START + 2;
				int const bind_idx_pageKey     = SQLITE_BIND_START + 3;
				
				YDBLogVerbose(@"UPDATE '%@' SET 'prevPageKey' = ?, 'count' = ?, 'data' = ? WHERE 'pageKey' = ?;\n"
				              @" - pageKey    : %@\n"
				              @" - prevPageKey: %@\n"
				              @" - count      : %d", [self pageTableName], pageKey,
				              pageMetadata->prevPageKey, (int)pageMetadata->count);
				
				YapDatabaseString _prevPageKey; MakeYapDatabaseString(&_prevPageKey, pageMetadata->prevPageKey);
				if (pageMetadata->prevPageKey) {
					sqlite3_bind_text(statement, bind_idx_prevPageKey,
					                  _prevPageKey.str, _prevPageKey.length, SQLITE_STATIC);
				}
				
				sqlite3_bind_int(statement, bind_idx_count, (int)(pageMetadata->count));
				
				__attribute__((objc_precise_lifetime)) NSData *rawData = [self serializePage:page];
				sqlite3_bind_blob(statement, bind_idx_data, rawData.bytes, (int)rawData.length, SQLITE_STATIC);
				
				YapDatabaseString _pageKey; MakeYapDatabaseString(&_pageKey, pageKey);
				sqlite3_bind_text(statement, bind_idx_pageKey, _pageKey.str, _pageKey.length, SQLITE_STATIC);
				
				int status = sqlite3_step(statement);
				if (status != SQLITE_DONE)
				{
					YDBLogError(@"%@ (%@): Error executing statement[1c]: %d %s",
					            THIS_METHOD, [self registeredName],
					            status, sqlite3_errmsg(databaseTransaction->connection->db));
				}
				
				sqlite3_clear_bindings(statement);
				sqlite3_reset(statement);
				FreeYapDatabaseString(&_prevPageKey);
				FreeYapDatabaseString(&_pageKey);
			}
			else
			{
				sqlite3_stmt *statement = [parentConnection pageTable_updatePageForPageKeyStatement];
				if (statement == NULL)
				{
					NSAssert(NO, @"Cannot get proper statement! View will become corrupt!");
					return;//from block
				}
			
				// UPDATE "pageTableName" SET "count" = ?, "data" = ? WHERE "pageKey" = ?;
				
				int const bind_idx_count   = SQLITE_BIND_START + 0;
				int const bind_idx_data    = SQLITE_BIND_START + 1;
				int const bind_idx_pageKey = SQLITE_BIND_START + 2;
				
				YDBLogVerbose(@"UPDATE '%@' SET 'count' = ?, 'data' = ? WHERE 'pageKey' = ?;\n"
				              @" - pageKey: %@\n"
				              @" - count  : %d", [self pageTableName], pageKey, (int)(pageMetadata->count));
				
				sqlite3_bind_int(statement, bind_idx_count, (int)[page count]);
				
				__attribute__((objc_precise_lifetime)) NSData *rawData = [self serializePage:page];
				sqlite3_bind_blob(statement, bind_idx_data, rawData.bytes, (int)rawData.length, SQLITE_STATIC);
				
				YapDatabaseString _pageKey; MakeYapDatabaseString(&_pageKey, pageKey);
				sqlite3_bind_text(statement, bind_idx_pageKey, _pageKey.str, _pageKey.length, SQLITE_STATIC);
				
				int status = sqlite3_step(statement);
				if (status != SQLITE_DONE)
				{
					YDBLogError(@"%@ (%@): Error executing statement[1d]: %d %s",
					            THIS_METHOD, [self registeredName],
					            status, sqlite3_errmsg(databaseTransaction->connection->db));
				}
				
				sqlite3_clear_bindings(statement);
				sqlite3_reset(statement);
				FreeYapDatabaseString(&_pageKey);
			}
		}];
		
		// Persistent View: Step 2 of 3
		//
		// Write dirty prevPageKey values to table (those not also associated with dirty pages).
		// This happens when only the prevPageKey pointer is changed.
		
		[parentConnection->dirtyLinks enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			
			NSString *pageKey = (NSString *)key;
			YapDatabaseViewPageMetadata *pageMetadata = (YapDatabaseViewPageMetadata *)obj;
			
			if ([parentConnection->dirtyPages objectForKey:pageKey])
			{
				// Both the page and metadata were dirty, so we wrote them both to disk at the same time.
				// No need to write the metadata again.
				
				return;//continue;
			}
			
			sqlite3_stmt *statement = [parentConnection pageTable_updateLinkForPageKeyStatement];
			if (statement == NULL) {
				*stop = YES;
				return;//from block
			}
				
			// UPDATE "pageTableName" SET "prevPageKey" = ? WHERE "pageKey" = ?;
			
			int const bind_idx_prevPageKey = SQLITE_BIND_START + 0;
			int const bind_idx_pageKey     = SQLITE_BIND_START + 1;
			
			YDBLogVerbose(@"UPDATE '%@' SET 'prevPageKey' = ? WHERE 'pageKey' = ?;\n"
			              @" - pageKey    : %@\n"
			              @" - prevPageKey: %@", [self pageTableName], pageKey, pageMetadata->prevPageKey);
			
			YapDatabaseString _prevPageKey; MakeYapDatabaseString(&_prevPageKey, pageMetadata->prevPageKey);
			if (pageMetadata->prevPageKey) {
				sqlite3_bind_text(statement, bind_idx_prevPageKey,
				                  _prevPageKey.str, _prevPageKey.length, SQLITE_STATIC);
			}
			
			YapDatabaseString _pageKey; MakeYapDatabaseString(&_pageKey, pageKey);
			sqlite3_bind_text(statement, bind_idx_pageKey, _pageKey.str, _pageKey.length, SQLITE_STATIC);
			
			int status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"%@ (%@): Error executing statement[2]: %d %s",
				            THIS_METHOD, [self registeredName],
				            status, sqlite3_errmsg(databaseTransaction->connection->db));
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
			FreeYapDatabaseString(&_prevPageKey);
			FreeYapDatabaseString(&_pageKey);
		}];
		
		// Persistent View: Step 3 of 3
		//
		// Update the dirty rowid -> pageKey mappings.
		
		[parentConnection->dirtyMaps enumerateKeysAndObjectsUsingBlock:^(id rowIdObj, id pageKeyObj, BOOL *stop) {
			
			int64_t rowid = [(NSNumber *)rowIdObj longLongValue];
			__unsafe_unretained NSString *pageKey = (NSString *)pageKeyObj;
			
			if ((id)pageKey == (id)[NSNull null])
			{
				sqlite3_stmt *statement = [parentConnection mapTable_removeForRowidStatement];
				if (statement == NULL)
				{
					*stop = YES;
					return;//continue;
				}
				
				// DELETE FROM "mapTableName" WHERE "rowid" = ?;
				
				int const bind_idx_rowid = SQLITE_BIND_START;
				
				YDBLogVerbose(@"DELETE FROM '%@' WHERE 'rowid' = ?;\n"
				              @" - rowid : %lld\n", [self mapTableName], rowid);
				
				sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
				
				int status = sqlite3_step(statement);
				if (status != SQLITE_DONE)
				{
						YDBLogError(@"%@ (%@): Error executing statement[3a]: %d %s",
					            THIS_METHOD, [self registeredName],
					            status, sqlite3_errmsg(databaseTransaction->connection->db));
				}
				
				sqlite3_clear_bindings(statement);
				sqlite3_reset(statement);
			}
			else
			{
				sqlite3_stmt *statement = [parentConnection mapTable_setPageKeyForRowidStatement];
				if (statement == NULL)
				{
					*stop = YES;
					return;//continue;
				}
				
				// INSERT OR REPLACE INTO "mapTableName" ("rowid", "pageKey") VALUES (?, ?);
				
				int const bind_idx_rowid   = SQLITE_BIND_START + 0;
				int const bind_idx_pageKey = SQLITE_BIND_START + 1;
				
				YDBLogVerbose(@"INSERT OR REPLACE INTO '%@' ('rowid', 'pageKey') VALUES (?, ?);\n"
				              @" - rowid  : %lld\n"
				              @" - pageKey: %@", [self mapTableName], rowid, pageKey);
				
				sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
				
				YapDatabaseString _pageKey; MakeYapDatabaseString(&_pageKey, pageKey);
				sqlite3_bind_text(statement, bind_idx_pageKey, _pageKey.str, _pageKey.length, SQLITE_STATIC);
				
				int status = sqlite3_step(statement);
				if (status != SQLITE_DONE)
				{
					YDBLogError(@"%@ (%@): Error executing statement[3b]: %d %s",
					            THIS_METHOD, [self registeredName],
					            status, sqlite3_errmsg(databaseTransaction->connection->db));
				}
				
				sqlite3_clear_bindings(statement);
				sqlite3_reset(statement);
				FreeYapDatabaseString(&_pageKey);
			}
		}];
	}
	else // if (isNonPersistentView)
	{
		// Memory View: Step 1 of 3
		//
		// Write dirty pages to table
		
		BOOL hasDirtyPages = ([parentConnection->dirtyPages count] > 0);
		BOOL hasDirtyLinks = ([parentConnection->dirtyLinks count] > 0);
		BOOL hasDirtyMaps  = ([parentConnection->dirtyMaps  count] > 0);
		
		if (hasDirtyPages)
		{
			[pageTableTransaction modifyWithBlock:^{ @autoreleasepool {
				
				[parentConnection->dirtyPages enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop) {
					
					__unsafe_unretained NSString *pageKey = (NSString *)key;
					__unsafe_unretained YapDatabaseViewPage *page = (YapDatabaseViewPage *)obj;
					
					if ((id)page == (id)[NSNull null])
					{
						[pageTableTransaction removeObjectForKey:pageKey];
					}
					else
					{
						[pageTableTransaction setObject:[page copy] forKey:pageKey];
					}
				}];
			}}];
		}
		// Memory View: Step 2 of 3
		//
		// Write dirty pageMetadata to table.
		// This includes anything referenced by dirtyPages or dirtyLinks.
		
		if (hasDirtyPages || hasDirtyLinks)
		{
			[pageMetadataTableTransaction modifyWithBlock:^{ @autoreleasepool {
				
				[parentConnection->dirtyPages enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop) {
					
					__unsafe_unretained NSString *pageKey = (NSString *)key;
					__unsafe_unretained YapDatabaseViewPage *page = (YapDatabaseViewPage *)obj;
					
					if ((id)page == (id)[NSNull null])
					{
						[pageMetadataTableTransaction removeObjectForKey:pageKey];
					}
					else
					{
						YapDatabaseViewPageMetadata *pageMetadata = nil;
						
						pageMetadata = [parentConnection->dirtyLinks objectForKey:pageKey];
						if (pageMetadata == nil)
						{
							NSString *group = [parentConnection->state groupForPageKey:pageKey];
							NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
							
							for (YapDatabaseViewPageMetadata *pm in pagesMetadataForGroup)
							{
								if ([pm->pageKey isEqualToString:pageKey])
								{
									pageMetadata = pm;
									break;
								}
							}
						}
						
						if (pageMetadata)
						{
							if (pageMetadata->isNew)
								pageMetadata->isNew = NO; // Clear flag
							
							[pageMetadataTableTransaction setObject:[pageMetadata copy] forKey:pageKey];
						}
					}
				}];
				
				[parentConnection->dirtyLinks enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop) {
					
					__unsafe_unretained NSString *pageKey = (NSString *)key;
					__unsafe_unretained YapDatabaseViewPageMetadata *pageMetadata = (YapDatabaseViewPageMetadata *)obj;
					
					if ([parentConnection->dirtyPages objectForKey:pageKey])
					{
						// Both the page and metadata were dirty, so we wrote them both to disk at the same time.
						// No need to write the metadata again.
						
						return;//continue;
					}
					
					[pageMetadataTableTransaction setObject:[pageMetadata copy] forKey:pageKey];
				}];
			}}];
		}
		
		// Memory View: Step 3 of 3
		//
		// Update the dirty rowid -> pageKey mappings.
		
		if (hasDirtyMaps)
		{
			[mapTableTransaction modifyWithBlock:^{ @autoreleasepool {
				
				[parentConnection->dirtyMaps enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop) {
					
					__unsafe_unretained NSNumber *rowidNumber = (NSNumber *)key;
					__unsafe_unretained NSString *pageKey = (NSString *)obj;
					
					if ((id)pageKey == (id)[NSNull null])
					{
						[mapTableTransaction removeObjectForKey:rowidNumber];
					}
					else
					{
						[mapTableTransaction setObject:pageKey forKey:rowidNumber];
					}
				}];
			}}];
		}
		
		[mapTableTransaction commit];
		[pageTableTransaction commit];
		[pageMetadataTableTransaction commit];
	}
}

- (void)didCommitTransaction
{
	YDBLogAutoTrace();
	
	// Commit is complete.
	// Forward to connection for further cleanup.
	
	[parentConnection postCommitCleanup];
	
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	parentConnection = nil;    // Do not remove !
	databaseTransaction = nil; // Do not remove !
}

- (void)didRollbackTransaction
{
	YDBLogAutoTrace();
	
	if (![self isPersistentView])
	{
		[mapTableTransaction rollback];
		[pageTableTransaction rollback];
		[pageMetadataTableTransaction rollback];
	}
	
	// Rollback is complete.
	// Forward to connection for further cleanup.
	
	[parentConnection postRollbackCleanup];
	
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	parentConnection = nil;    // Do not remove !
	databaseTransaction = nil; // Do not remove !
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API - Groups
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)numberOfGroups
{
	// Note: We don't remove pages or groups until flushPendingChangesToExtensionTables.
	// This allows us to recycle pages whenever possible, which reduces disk IO during the commit.
	
	__block NSUInteger count = 0;
	
	[parentConnection->state enumerateWithBlock:^(NSString __unused *group, NSArray *pagesMetadataForGroup, BOOL __unused *stop) {
		
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
		{
			if (pageMetadata->count > 0)
			{
				count++;
				break;
			}
		}
	}];
	
	return count;
}

- (NSArray *)allGroups
{
	// Note: We don't remove pages or groups until flushPendingChangesToExtensionTables.
	// This allows us to recycle pages whenever possible, which reduces disk IO during the commit.
	
	NSMutableArray *allGroups = [NSMutableArray arrayWithCapacity:[parentConnection->state numberOfGroups]];
	
	[parentConnection->state enumerateWithBlock:^(NSString *group, NSArray *pagesMetadataForGroup, BOOL __unused *stop) {
		
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
		{
			if (pageMetadata->count > 0)
			{
				[allGroups addObject:group];
				break;
			}
		}
	}];
	
	return [allGroups copy];
}

/**
 * Returns YES if there are any keys in the given group.
 * This is equivalent to ([viewTransaction numberOfItemsInGroup:group] > 0)
**/
- (BOOL)hasGroup:(NSString *)group
{
	// Note: We don't remove pages or groups until flushPendingChangesToExtensionTables.
	// This allows us to recycle pages whenever possible, which reduces disk IO during the commit.
	
	NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		if (pageMetadata->count > 0)
			return YES;
	}
	
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API - Counts
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)numberOfItemsInGroup:(NSString *)group
{
	NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
	NSUInteger count = 0;
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		count += pageMetadata->count;
	}
	
	return count;
}

- (NSUInteger)numberOfItemsInAllGroups
{
	__block NSUInteger count = 0;
	
	[parentConnection->state enumerateWithBlock:
	  ^(NSString __unused *group, NSArray *pagesMetadataForGroup, BOOL __unused *stop)
	{
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
		{
			count += pageMetadata->count;
		}
	}];
	
	return count;
}

/**
 * Returns YES if the group is empty (has zero items).
 * Shorthand for: [[transaction ext:viewName] numberOfItemsInGroup:group] == 0
**/
- (BOOL)isEmptyGroup:(NSString *)group
{
	NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		if (pageMetadata->count > 0) {
			return NO;
		}
	}
	
	return YES;
}

/**
 * Returns YES if the view is empty (has zero groups).
 * Shorthand for: [[transaction ext:viewName] numberOfItemsInAllGroups] == 0
**/
- (BOOL)isEmpty
{
	__block BOOL result = YES;
	
	[parentConnection->state enumerateWithBlock:^(NSString __unused *group, NSArray *pagesMetadataForGroup, BOOL *stop) {
		
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
		{
			if (pageMetadata->count > 0)
			{
				result = NO;
				
				*stop = YES;
				break;
			}
		}
	}];
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API - Fetching
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)getKey:(NSString **)keyPtr
    collection:(NSString **)collectionPtr
       atIndex:(NSUInteger)index
       inGroup:(NSString *)group
{
	int64_t rowid = 0;
	if ([self getRowid:&rowid atIndex:index inGroup:group])
	{
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		if (ck)
		{
			if (collectionPtr) *collectionPtr = ck.collection;
			if (keyPtr) *keyPtr = ck.key;
			return YES;
		}
	}
	
	if (collectionPtr) *collectionPtr = nil;
	if (keyPtr) *keyPtr = nil;
	return NO;
}

- (BOOL)getFirstKey:(NSString **)keyPtr collection:(NSString **)collectionPtr inGroup:(NSString *)group
{
	return [self getKey:keyPtr collection:collectionPtr atIndex:0 inGroup:group];
}

- (BOOL)getLastKey:(NSString **)keyPtr collection:(NSString **)collectionPtr inGroup:(NSString *)group
{
	int64_t rowid = 0;
	if ([self getLastRowid:&rowid inGroup:group])
	{
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		if (ck)
		{
			if (collectionPtr) *collectionPtr = ck.collection;
			if (keyPtr) *keyPtr = ck.key;
			return YES;
		}
	}
	
	if (collectionPtr) *collectionPtr = nil;
	if (keyPtr) *keyPtr = nil;
	return NO;
}

- (NSString *)collectionAtIndex:(NSUInteger)index inGroup:(NSString *)group
{
	NSString *collection = nil;
	[self getKey:NULL collection:&collection atIndex:index inGroup:group];
	
	return collection;
}

- (NSString *)keyAtIndex:(NSUInteger)index inGroup:(NSString *)group
{
	NSString *key = nil;
	[self getKey:&key collection:NULL atIndex:index inGroup:group];
	
	return key;
}

- (NSString *)groupForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil)
		return nil;
	
	if (collection == nil)
		collection = @"";
	
	int64_t rowid;
	if ([databaseTransaction getRowid:&rowid forKey:key inCollection:collection])
	{
		return [parentConnection->state groupForPageKey:[self pageKeyForRowid:rowid]];
	}
	
	return nil;
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
	
	BOOL found = NO;
	NSString *group = nil;
	NSUInteger index = 0;
	
	int64_t rowid = 0;
	if ([databaseTransaction getRowid:&rowid forKey:key inCollection:collection])
	{
		// Query the database to see if the given key is in the view.
		// If it is, the query will return the corresponding page the key is in.
		
		NSString *pageKey = [self pageKeyForRowid:rowid];
		if (pageKey)
		{
			// Now that we have the pageKey, fetch the corresponding group.
			// This is done using an in-memory cache.
			
			group = [parentConnection->state groupForPageKey:pageKey];
		
			// Calculate the offset of the corresponding page within the group.
			
			NSUInteger pageOffset = 0;
			NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
			
			for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
			{
				if ([pageMetadata->pageKey isEqualToString:pageKey])
				{
					break;
				}
				
				pageOffset += pageMetadata->count;
			}
			
			// Fetch the actual page (ordered array of keys)
			
			YapDatabaseViewPage *page = [self pageForPageKey:pageKey];
			
			// And find the exact index of the key within the page
			
			NSUInteger indexWithinPage = 0;
			if ([page getIndex:&indexWithinPage ofRowid:rowid])
			{
				index = pageOffset + indexWithinPage;
				found = YES;
			}
		}
	}
	
	if (groupPtr) *groupPtr = group;
	if (indexPtr) *indexPtr = index;
	
	return found;
}

/**
 * Returns the versionTag in effect for this transaction.
 *
 * Because this transaction may be one or more commits behind the most recent commit,
 * this method is the best way to determine the versionTag associated with what the transaction actually sees.
 *
 * Put another way:
 * - [YapDatabaseView versionTag]            = versionTag of most recent commit
 * - [YapDatabaseViewTransaction versionTag] = versionTag of this commit
**/
- (NSString *)versionTag
{
	return [self stringValueForExtensionKey:ext_key_versionTag persistent:[self isPersistentView]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API - Enumerating
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)enumerateGroupsUsingBlock:(void (^)(NSString *group, BOOL *stop))block
{
	if (block == NULL) return;
	
	[parentConnection->mutatedGroups removeAllObjects]; // mutation during enumeration protection
	
	__block BOOL stop = NO;
	
	[parentConnection->state enumerateGroupsWithBlock:^(NSString *group, BOOL *innerStop) {
		
		block(group, &stop);
		
		if (stop || [parentConnection->mutatedGroups count] > 0) *innerStop = YES;
	}];
	
	if (!stop && [parentConnection->mutatedGroups count] > 0)
	{
		NSString *anyMutatedGroup = [parentConnection->mutatedGroups anyObject];
		
		@throw [self mutationDuringEnumerationException:anyMutatedGroup];
	}
}

- (void)enumerateKeysInGroup:(NSString *)group
                  usingBlock:(void (^)(NSString *collection, NSString *key, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop) {
		
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		block(ck.collection, ck.key, index, stop);
	}];
}

- (void)enumerateKeysInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                  usingBlock:(void (^)(NSString *collection, NSString *key, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group withOptions:options usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop) {
		
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		block(ck.collection, ck.key, index, stop);
	}];
}

- (void)enumerateKeysInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                       range:(NSRange)range
                  usingBlock:(void (^)(NSString *collection, NSString *key, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group
	                 withOptions:options
	                       range:range
	                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop)
	{
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		block(ck.collection, ck.key, index, stop);
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)enumerateRowidsInGroup:(NSString *)group
                    usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[parentConnection->mutatedGroups removeObject:group]; // mutation during enumeration protection
	
	__block BOOL stop = NO;
	
	NSUInteger pageOffset = 0;
	NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		YapDatabaseViewPage *page = [self pageForPageKey:pageMetadata->pageKey];
		
		[page enumerateRowidsUsingBlock:^(int64_t rowid, NSUInteger idx, BOOL *innerStop) {
			
			block(rowid, pageOffset+idx, &stop);
			
			if (stop || [parentConnection->mutatedGroups containsObject:group]) *innerStop = YES;
		}];
		
		if (stop || [parentConnection->mutatedGroups containsObject:group]) break;
		
		pageOffset += pageMetadata->count;
	}
	
	if (!stop && [parentConnection->mutatedGroups containsObject:group])
	{
		@throw [self mutationDuringEnumerationException:group];
	}
}

- (void)enumerateRowidsInGroup:(NSString *)group
                   withOptions:(NSEnumerationOptions)inOptions
                    usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	NSEnumerationOptions options = (inOptions & NSEnumerationReverse); // We only support NSEnumerationReverse
	BOOL forwardEnumeration = (options != NSEnumerationReverse);
	
	[parentConnection->mutatedGroups removeObject:group]; // mutation during enumeration protection
	
	__block BOOL stop = NO;
	__block NSUInteger index;
	
	if (forwardEnumeration)
		index = 0;
	else
		index = [self numberOfItemsInGroup:group] - 1;
	
	NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
	
	[pagesMetadataForGroup enumerateObjectsWithOptions:options
	                                        usingBlock:^(id pageMetadataObj, NSUInteger __unused outerIdx, BOOL *outerStop)
	{
		__unsafe_unretained YapDatabaseViewPageMetadata *pageMetadata =
		    (YapDatabaseViewPageMetadata *)pageMetadataObj;
		
		YapDatabaseViewPage *page = [self pageForPageKey:pageMetadata->pageKey];
		
		[page enumerateRowidsWithOptions:options usingBlock:^(int64_t rowid, NSUInteger __unused innerIdx, BOOL *innerStop) {
			
			block(rowid, index, &stop);
			
			if (forwardEnumeration)
				index++;
			else
				index--;
			
			if (stop || [parentConnection->mutatedGroups containsObject:group]) *innerStop = YES;
		}];
		
		if (stop || [parentConnection->mutatedGroups containsObject:group]) *outerStop = YES;
	}];
	
	if (!stop && [parentConnection->mutatedGroups containsObject:group])
	{
		@throw [self mutationDuringEnumerationException:group];
	}
}

- (void)enumerateRowidsInGroup:(NSString *)group
                   withOptions:(NSEnumerationOptions)inOptions
                         range:(NSRange)range
                    usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	NSEnumerationOptions options = (inOptions & NSEnumerationReverse); // We only support NSEnumerationReverse
	
	[parentConnection->mutatedGroups removeObject:group]; // mutation during enumeration protection
	
	__block BOOL stop = NO;
	__block NSUInteger keysLeft = range.length;
	
	if ((options & NSEnumerationReverse) == 0)
	{
		// Forward enumeration (optimized)
		
		NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
		
		NSUInteger pageOffset = 0;
		BOOL startedRange = NO;
		
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
		{
			NSRange pageRange = NSMakeRange(pageOffset, pageMetadata->count);
			NSRange intersection = NSIntersectionRange(pageRange, range);
			
			if (intersection.length > 0)
			{
				startedRange = YES;
				YapDatabaseViewPage *page = [self pageForPageKey:pageMetadata->pageKey];
				
				// Enumerate the subset
				
				NSRange enumRange = NSMakeRange(intersection.location - pageOffset, intersection.length);
				
				[page enumerateRowidsWithOptions:options
				                           range:enumRange
				                      usingBlock:^(int64_t rowid, NSUInteger idx, BOOL *innerStop)
				{
					block(rowid, pageOffset+idx, &stop);
					
					if (stop || [parentConnection->mutatedGroups containsObject:group]) *innerStop = YES;
				}];
				
				if (stop || [parentConnection->mutatedGroups containsObject:group]) break;
				
				keysLeft -= enumRange.length;
			}
			else if (startedRange && (pageRange.length > 0))
			{
				// We've completed the range
				break;
			}
			
			pageOffset += pageMetadata->count;
		}
	}
	else
	{
		// Reverse enumeration
		
		NSArray *pagesMetadataForGroup = [parentConnection->state pagesMetadataForGroup:group];
		
		__block NSUInteger pageOffset = [self numberOfItemsInGroup:group];
		__block BOOL startedRange = NO;
		
		[pagesMetadataForGroup enumerateObjectsWithOptions:options
		                                        usingBlock:^(id pageMetadataObj, NSUInteger __unused pageIndex, BOOL *outerStop)
		{
			__unsafe_unretained YapDatabaseViewPageMetadata *pageMetadata =
			    (YapDatabaseViewPageMetadata *)pageMetadataObj;
			
			pageOffset -= pageMetadata->count;
			
			NSRange pageRange = NSMakeRange(pageOffset, pageMetadata->count);
			NSRange intersection = NSIntersectionRange(pageRange, range);
			
			if (intersection.length > 0)
			{
				startedRange = YES;
				YapDatabaseViewPage *page = [self pageForPageKey:pageMetadata->pageKey];
				
				// Enumerate the subset
				
				NSRange enumRange = NSMakeRange(intersection.location - pageOffset, intersection.length);
				
				[page enumerateRowidsWithOptions:options
				                           range:enumRange
				                      usingBlock:^(int64_t rowid, NSUInteger idx, BOOL *innerStop) {
					
					block(rowid, pageOffset+idx, &stop);
					
					if (stop || [parentConnection->mutatedGroups containsObject:group]) *innerStop = YES;
				}];
				
				if (stop || [parentConnection->mutatedGroups containsObject:group]) *outerStop = YES;
				
				keysLeft -= enumRange.length;
			}
			else if (startedRange && (pageRange.length > 0))
			{
				// We've completed the range
				*outerStop = YES;
			}
			
		}];
	}
	
	if (!stop && [parentConnection->mutatedGroups containsObject:group])
	{
		@throw [self mutationDuringEnumerationException:group];
	}
	
	if (!stop && keysLeft > 0)
	{
		YDBLogWarn(@"%@: Range out of bounds: range(%lu, %lu) >= numberOfKeys(%lu) in group %@", THIS_METHOD,
		    (unsigned long)range.location, (unsigned long)range.length,
		    (unsigned long)[self numberOfItemsInGroup:group], group);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Exceptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSException *)mutationDuringEnumerationException:(NSString *)group
{
	NSString *reason = [NSString stringWithFormat:
	  @"View <RegisteredName=%@, Group=%@> was mutated while being enumerated.", [self registeredName], group];
	
	NSDictionary *userInfo = @{ NSLocalizedRecoverySuggestionErrorKey:
	  @"If you modify the database during enumeration you must either"
	  @" (A) ensure you don't mutate the group you're enumerating OR"
	  @" (B) set the 'stop' parameter of the enumeration block to YES (*stop = YES;). "
	  @"If you're enumerating in order to remove items from the database,"
	  @" and you're enumerating in order (forwards or backwards)"
	  @" then you may also consider looping and using firstKeyInGroup / lastKeyInGroup."};
	
	return [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseViewTransaction (ReadWrite)

/**
 * "Touching" a object allows you to mark an item in the view as "updated",
 * even if the object itself wasn't directly updated.
 *
 * This is most often useful when a view is being used by a tableView,
 * but the tableView cells are also dependent upon another object in the database.
 *
 * For example:
 *
 *   You have a view which includes the departments in the company, sorted by name.
 *   But as part of the cell that's displayed for the department,
 *   you also display the number of employees in the department.
 *   The employee count comes from elsewhere.
 *   That is, the employee count isn't a property of the department object itself.
 *   Perhaps you get the count from another view,
 *   or perhaps the count is simply the number of keys in a particular collection.
 *   Either way, when you add or remove an employee, you want to ensure that the view marks the
 *   affected department as updated so that the corresponding cell will properly redraw itself.
 *
 * So the idea is to mark certain items as updated so that the changeset
 * for the view will properly reflect a change to the corresponding index.
 *
 * "Touching" an item has very minimal overhead.
 * It doesn't cause the groupingBlock or sortingBlock to be invoked,
 * and it doesn't cause any writes to the database.
 *
 * You can touch
 * - just the object
 * - just the metadata
 * - or both object and metadata (the row)
 *
 * If you mark just the object as changed,
 * and neither the groupingBlock nor sortingBlock depend upon the object,
 * then the view doesn't reflect any change.
 *
 * If you mark just the metadata as changed,
 * and neither the groupingBlock nor sortingBlock depend upon the metadata,
 * then the view doesn't relect any change.
 *
 * In all other cases, the view will properly reflect a corresponding change in the notification that's posted.
**/

- (void)touchObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	int64_t rowid = 0;
	if ([databaseTransaction getRowid:&rowid forKey:key inCollection:collection])
	{
		YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		[self didTouchObjectForCollectionKey:collectionKey withRowid:rowid];
	}
}

- (void)touchMetadataForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	int64_t rowid = 0;
	if ([databaseTransaction getRowid:&rowid forKey:key inCollection:collection])
	{
		YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		[self didTouchMetadataForCollectionKey:collectionKey withRowid:rowid];
	}
}

- (void)touchRowForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	int64_t rowid = 0;
	if ([databaseTransaction getRowid:&rowid forKey:key inCollection:collection])
	{
		YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		[self didTouchRowForCollectionKey:collectionKey withRowid:rowid];
	}
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseViewTransaction (Convenience)

- (id)metadataAtIndex:(NSUInteger)index inGroup:(NSString *)group
{
	int64_t rowid = 0;
	if ([self getRowid:&rowid atIndex:index inGroup:group])
	{
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		return [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
	}
	else
	{
		return nil;
	}
}

- (id)objectAtIndex:(NSUInteger)index inGroup:(NSString *)group
{
	int64_t rowid = 0;
	if ([self getRowid:&rowid atIndex:index inGroup:group])
	{
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		return [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
	}
	
	return nil;
}

- (id)firstObjectInGroup:(NSString *)group
{
	return [self objectAtIndex:0 inGroup:group];
}

- (id)lastObjectInGroup:(NSString *)group
{
	int64_t rowid = 0;
	if ([self getLastRowid:&rowid inGroup:group])
	{
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		return [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
	}
	
	return nil;
}

/**
 * The following methods are similar to invoking the enumerateKeysInGroup:... methods,
 * and then fetching the metadata within your own block.
**/

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                             usingBlock:
                    (void (^)(NSString *collection, NSString *key, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop) {
		
		YapCollectionKey *ck = nil;
		id metadata = nil;
		[databaseTransaction getCollectionKey:&ck metadata:&metadata forRowid:rowid];
		
		block(ck.collection, ck.key, metadata, index, stop);
	}];
}

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                            withOptions:(NSEnumerationOptions)options
                             usingBlock:
                    (void (^)(NSString *collection, NSString *key, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group
	                 withOptions:options
	                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop)
	{
		YapCollectionKey *ck = nil;
		id metadata = nil;
		[databaseTransaction getCollectionKey:&ck metadata:&metadata forRowid:rowid];
						  
		block(ck.collection, ck.key, metadata, index, stop);
	}];
}

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                            withOptions:(NSEnumerationOptions)options
                                  range:(NSRange)range
                             usingBlock:
                    (void (^)(NSString *collection, NSString *key, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group
	                 withOptions:options
	                       range:range
	                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop)
	{
		YapCollectionKey *ck = nil;
		id metadata = nil;
		[databaseTransaction getCollectionKey:&ck metadata:&metadata forRowid:rowid];
		
		block(ck.collection, ck.key, metadata, index, stop);
	}];
}

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                            withOptions:(NSEnumerationOptions)options
                                  range:(NSRange)range
                                 filter:
                    (BOOL (^)(NSString *collection, NSString *key))filter
                             usingBlock:
                    (void (^)(NSString *collection, NSString *key, id metadata, NSUInteger index, BOOL *stop))block
{
	if (filter == NULL) {
		[self enumerateKeysAndMetadataInGroup:group withOptions:options range:range usingBlock:block];
		return;
	}
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group
	                 withOptions:options
	                       range:range
	                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop)
	{
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		if (filter(ck.collection, ck.key))
		{
			id metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
		
			block(ck.collection, ck.key, metadata, index, stop);
		}
	}];
}

/**
 * The following methods are similar to invoking the enumerateKeysInGroup:... methods,
 * and then fetching the object within your own block.
**/

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                            usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop) {
		
		YapCollectionKey *ck = nil;
		id object = nil;
		[databaseTransaction getCollectionKey:&ck object:&object forRowid:rowid];
		
		block(ck.collection, ck.key, object, index, stop);
	}];
}

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                            usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group
	                 withOptions:options
	                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop)
	{
		YapCollectionKey *ck = nil;
		id object = nil;
		[databaseTransaction getCollectionKey:&ck object:&object forRowid:rowid];
		
		block(ck.collection, ck.key, object, index, stop);
	}];
}

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                                 range:(NSRange)range
                            usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group
	                 withOptions:options
	                       range:range
	                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop)
	{
		YapCollectionKey *ck = nil;
		id object = nil;
		[databaseTransaction getCollectionKey:&ck object:&object forRowid:rowid];
		
		block(ck.collection, ck.key, object, index, stop);
	}];
}

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                                 range:(NSRange)range
                                filter:
            (BOOL (^)(NSString *collection, NSString *key))filter
                            usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop))block
{
	if (filter == NULL) {
		[self enumerateKeysAndObjectsInGroup:group withOptions:options range:range usingBlock:block];
		return;
	}
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group
	                 withOptions:options
	                       range:range
	                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop)
	{
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		if (filter(ck.collection, ck.key))
		{
			id object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
			
			block(ck.collection, ck.key, object, index, stop);
		}
	}];
}

/**
 * The following methods are similar to invoking the enumerateKeysInGroup:... methods,
 * and then fetching the object and metadata within your own block.
**/

- (void)enumerateRowsInGroup:(NSString *)group
                  usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop) {
		
		YapCollectionKey *ck = nil;
		id object = nil;
		id metadata = nil;
		[databaseTransaction getCollectionKey:&ck object:&object metadata:&metadata forRowid:rowid];
		
		block(ck.collection, ck.key, object, metadata, index, stop);
	}];
}

- (void)enumerateRowsInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                  usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group
	                 withOptions:options
	                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop)
	{
		YapCollectionKey *ck = nil;
		id object = nil;
		id metadata = nil;
		[databaseTransaction getCollectionKey:&ck object:&object metadata:&metadata forRowid:rowid];
		
		block(ck.collection, ck.key, object, metadata, index, stop);
	}];
}

- (void)enumerateRowsInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                       range:(NSRange)range
                  usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group
	                 withOptions:options
	                       range:range
	                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop)
	{
		YapCollectionKey *ck = nil;
		id object = nil;
		id metadata = nil;
		[databaseTransaction getCollectionKey:&ck object:&object metadata:&metadata forRowid:rowid];
		
		block(ck.collection, ck.key, object, metadata, index, stop);
	}];
}

- (void)enumerateRowsInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                       range:(NSRange)range
                      filter:
            (BOOL (^)(NSString *collection, NSString *key))filter
                  usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block
{
	if (filter == NULL) {
		[self enumerateRowsInGroup:group withOptions:options range:range usingBlock:block];
		return;
	}
	if (block == NULL) return;
	
	[self enumerateRowidsInGroup:group
	                 withOptions:options
	                       range:range
	                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop)
	{
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		if (filter(ck.collection, ck.key))
		{
			id object = nil;
			id metadata = nil;
			[databaseTransaction getObject:&object metadata:&metadata forCollectionKey:ck withRowid:rowid];
			
			block(ck.collection, ck.key, object, metadata, index, stop);
		}
	}];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * ***** ALWAYS USE THESE METHODS WHEN USING MAPPINGS *****
 *
 * When using advanced features of YapDatabaseViewMappings, things can get confusing rather quickly.
 * For example, one can configure mappings in such a way that it:
 * - only displays a subset (range) of the original YapDatabaseView
 * - presents the YapDatabaseView in reverse order
 *
 * If you used only the core API of YapDatabaseView, you'd be forced to constantly use a 2-step lookup process:
 * 1.) Use mappings to convert from the tableView's indexPath, to the group & index of the view.
 * 2.) Use the resulting group & index to fetch what you need.
 *
 * The annoyance of an extra step is one thing.
 * But an extra step that's easy to forget, and which would likely cause bugs, is another.
 *
 * Thus it is recommended that you ***** ALWAYS USE THESE METHODS WHEN USING MAPPINGS ***** !!!!!
 *
 * One other word of encouragement:
 *
 * Often times developers start by using straight mappings without any advanced features.
 * This means there's a 1-to-1 mapping between what's in the tableView, and what's in the yapView.
 * In these situations you're still highly encouraged to use these methods.
 * Because if/when you do turn on some advanced features, these methods will continue to work perfectly.
 * Whereas the alternative would force you to find every instance where you weren't using these methods,
 * and convert that code to use these methods.
 *
 * So it's advised you save yourself the hassle (and the mental overhead),
 * and simply always use these methds when using mappings.
**/
@implementation YapDatabaseViewTransaction (Mappings)

/**
 * Performance boost.
 * If the item isn't in the cache, having the rowid makes for a faster fetch from sqlite.
**/
- (BOOL)getRowid:(int64_t *)rowidPtr
   collectionKey:(YapCollectionKey **)collectionKeyPtr
          forRow:(NSUInteger)row
       inSection:(NSUInteger)section
    withMappings:(YapDatabaseViewMappings *)mappings
{
	if (mappings)
	{
		NSString *group = nil;
		NSUInteger index = 0;
		
		if ([mappings getGroup:&group index:&index forRow:row inSection:section])
		{
			int64_t rowid = 0;
			if ([self getRowid:&rowid atIndex:index inGroup:group])
			{
				if (collectionKeyPtr)
				{
					YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
					*collectionKeyPtr = ck;
				}
				
				if (rowidPtr) *rowidPtr = rowid;
				return YES;
			}
		}
	}
	
	if (rowidPtr) *rowidPtr = 0;
	if (collectionKeyPtr) *collectionKeyPtr = nil;
	return NO;
}

/**
 * Gets the key & collection at the given indexPath, assuming the given mappings are being used.
 * Returns NO if the indexPath is invalid, or the mappings aren't initialized.
 * Otherwise returns YES, and sets the key & collection ptr (both optional).
**/
- (BOOL)getKey:(NSString **)keyPtr
    collection:(NSString **)collectionPtr
   atIndexPath:(NSIndexPath *)indexPath
  withMappings:(YapDatabaseViewMappings *)mappings
{
	if (indexPath == nil)
	{
		if (keyPtr) *keyPtr = nil;
		if (collectionPtr) *collectionPtr = nil;
		
		return NO;
	}
	
	NSUInteger section = [indexPath indexAtPosition:0];
	NSUInteger row = [indexPath indexAtPosition:1];
	
	YapCollectionKey *ck = nil;
	BOOL result = [self getRowid:NULL
	               collectionKey:&ck
	                      forRow:row
	                   inSection:section
	                withMappings:mappings];
	
	if (keyPtr) *keyPtr = ck.key;
	if (collectionPtr) *collectionPtr = ck.collection;
	
	return result;
}

/**
 * Gets the key & collection at the given row & section, assuming the given mappings are being used.
 * Returns NO if the row or section is invalid, or the mappings aren't initialized.
 * Otherwise returns YES, and sets the key & collection ptr (both optional).
**/
- (BOOL)getKey:(NSString **)keyPtr
    collection:(NSString **)collectionPtr
        forRow:(NSUInteger)row
     inSection:(NSUInteger)section
  withMappings:(YapDatabaseViewMappings *)mappings
{
	YapCollectionKey *ck = nil;
	BOOL result = [self getRowid:NULL
	               collectionKey:&ck
	                      forRow:row
	                   inSection:section
	                withMappings:mappings];
	
	if (keyPtr) *keyPtr = ck.key;
	if (collectionPtr) *collectionPtr = ck.collection;
	
	return result;
}

/**
 * Fetches the indexPath for the given {collection, key} tuple, assuming the given mappings are being used.
 * Returns nil if the {collection, key} tuple isn't included in the view + mappings.
**/
- (NSIndexPath *)indexPathForKey:(NSString *)key
                    inCollection:(NSString *)collection
                    withMappings:(YapDatabaseViewMappings *)mappings
{
	NSString *group = nil;
	NSUInteger index = 0;
	
	if ([self getGroup:&group index:&index forKey:key inCollection:collection])
	{
		return [mappings indexPathForIndex:index inGroup:group];
	}
	
	return nil;
}

/**
 * Fetches the row & section for the given {collection, key} tuple, assuming the given mappings are being used.
 * Returns NO if the {collection, key} tuple isn't included in the view + mappings.
 * Otherwise returns YES, and sets the row & section (both optional).
**/
- (BOOL)getRow:(NSUInteger *)rowPtr
       section:(NSUInteger *)sectionPtr
        forKey:(NSString *)key
  inCollection:(NSString *)collection
  withMappings:(YapDatabaseViewMappings *)mappings
{
	NSString *group = nil;
	NSUInteger index = 0;
	
	if ([self getGroup:&group index:&index forKey:key inCollection:collection])
	{
		return [mappings getRow:rowPtr section:sectionPtr forIndex:index inGroup:group];
	}
	
	if (rowPtr) *rowPtr = 0;
	if (sectionPtr) *sectionPtr = 0;
	return NO;
}

/**
 * Gets the object at the given indexPath, assuming the given mappings are being used.
 * 
 * Equivalent to invoking:
 *
 * NSString *collection, *key;
 * if ([[transaction ext:@"myView"] getKey:&key collection:&collection atIndexPath:indexPath withMappings:mappings]) {
 *     object = [transaction objectForKey:key inCollection:collection];
 * }
**/
- (id)objectAtIndexPath:(NSIndexPath *)indexPath withMappings:(YapDatabaseViewMappings *)mappings
{
	if (indexPath == nil)
	{
		return nil;
	}
	
	NSUInteger section = [indexPath indexAtPosition:0];
	NSUInteger row = [indexPath indexAtPosition:1];
	
	id object = nil;
	
	int64_t rowid = 0;
	YapCollectionKey *ck = nil;
	
	if ([self getRowid:&rowid collectionKey:&ck forRow:row inSection:section withMappings:mappings])
	{
		object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
	}
	
	return object;
}

/**
 * Gets the object at the given indexPath, assuming the given mappings are being used.
 *
 * Equivalent to invoking:
 *
 * NSString *collection, *key;
 * if ([[transaction ext:@"view"] getKey:&key
 *                            collection:&collection
 *                                forRow:row
 *                             inSection:section
 *                          withMappings:mappings]) {
 *     object = [transaction objectForKey:key inCollection:collection];
 * }
**/
- (id)objectAtRow:(NSUInteger)row inSection:(NSUInteger)section withMappings:(YapDatabaseViewMappings *)mappings
{
	id object = nil;
	
	int64_t rowid = 0;
	YapCollectionKey *ck = nil;
	
	if ([self getRowid:&rowid collectionKey:&ck forRow:row inSection:section withMappings:mappings])
	{
		object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
	}
	
	return object;
}

/**
 * Gets the metadata at the given indexPath, assuming the given mappings are being used.
 *
 * Equivalent to invoking:
 *
 * NSString *collection, *key;
 * if ([[transaction ext:@"myView"] getKey:&key collection:&collection atIndexPath:indexPath withMappings:mappings]) {
 *     metadata = [transaction metadataForKey:key inCollection:collection];
 * }
**/
- (id)metadataAtIndexPath:(NSIndexPath *)indexPath withMappings:(YapDatabaseViewMappings *)mappings
{
	if (indexPath == nil)
	{
		return nil;
	}
	
	NSUInteger section = [indexPath indexAtPosition:0];
	NSUInteger row = [indexPath indexAtPosition:1];
	
	id metadata = nil;
	
	int64_t rowid = 0;
	YapCollectionKey *ck = nil;
	
	if ([self getRowid:&rowid collectionKey:&ck forRow:row inSection:section withMappings:mappings])
	{
		metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
	}
	
	return metadata;
}

/**
 * Gets the object at the given indexPath, assuming the given mappings are being used.
 *
 * Equivalent to invoking:
 *
 * NSString *collection, *key;
 * if ([[transaction ext:@"myView"] getKey:&key
 *                              collection:&collection
 *                                  forRow:row
 *                               inSection:section
 *                            withMappings:mappings]) {
 *     metadata = [transaction metadataForKey:key inCollection:collection];
 * }
**/
- (id)metadataAtRow:(NSUInteger)row inSection:(NSUInteger)section withMappings:(YapDatabaseViewMappings *)mappings
{
	id metadata = nil;
	
	int64_t rowid = 0;
	YapCollectionKey *ck = nil;
	
	if ([self getRowid:&rowid collectionKey:&ck forRow:row inSection:section withMappings:mappings])
	{
		metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
	}
	
	return metadata;
}

@end
