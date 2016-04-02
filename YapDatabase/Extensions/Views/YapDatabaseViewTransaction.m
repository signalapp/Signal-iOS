#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseViewPrivate.h"
#import "YapDatabaseViewPage.h"
#import "YapDatabaseViewPageMetadata.h"
#import "YapDatabaseViewChange.h"
#import "YapDatabaseViewChangePrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapCache.h"
#import "YapCollectionKey.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

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

/**
 * The view is tasked with storing ordered arrays of keys.
 * In doing so, it splits the array into "pages" of keys,
 * and stores the pages in the database.
 * This reduces disk IO, as only the contents of a single page are written for a single change.
 * And only the contents of a single page need be read to fetch a single key.
**/
#define YAP_DATABASE_VIEW_MAX_PAGE_SIZE 50


@implementation YapDatabaseViewTransaction

- (id)initWithViewConnection:(YapDatabaseViewConnection *)inViewConnection
         databaseTransaction:(YapDatabaseReadTransaction *)inDatabaseTransaction
{
	YDBLogAutoTrace();
	
	if ((self = [super init]))
	{
		viewConnection = inViewConnection;
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
		
		if (!viewConnection->view->options.skipInitialViewPopulation)
		{
			if (![self populateView]) return NO;
		}
		
		// Store initial versionTag in prefs table
		
		NSString *versionTag = [viewConnection->view versionTag]; // MUST get init value from view
		
		[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:NO];
		
		// If there was a previously registered persistent view with this name,
		// then we should drop those tables from the database.
		
		BOOL dropPersistentTables = [self getIntValue:NULL forExtensionKey:ext_key_classVersion persistent:YES];
		if (dropPersistentTables)
		{
			[[viewConnection->view class]
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
		
		NSString *versionTag = [viewConnection->view versionTag]; // MUST get init value from view
		
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
			needsPopulateView = !viewConnection->view->options.skipInitialViewPopulation;
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
	
	if (viewConnection->state)
	{
		// Already prepared
		return YES;
	}
	
	// Can we use the latest processed changeset in YapDatabaseView?
	
	YapDatabaseViewState *state = nil;
	
	BOOL shortcut = [viewConnection->view getState:&state forConnection:viewConnection];
	if (shortcut && state)
	{
		if (databaseTransaction->isReadWriteTransaction)
			viewConnection->state = [state mutableCopy];
		else
			viewConnection->state = [state copy];
		
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
		
		viewConnection->state = [[YapDatabaseViewState alloc] init];
		
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
			
			[viewConnection->state createGroup:group withCapacity:expectedPageCount];
			
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
				
				[viewConnection->state addPageMetadata:pageMetadata toGroup:group];
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
		
		viewConnection->state = nil;
	}
	else
	{
		YDBLogVerbose(@"viewConnection->state: %@", viewConnection->state);
	}
	
	return !error;
}

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

- (BOOL)populateView
{
	YDBLogAutoTrace();
	
	// Remove everything from the database
	
	[self removeAllRowids];
	
	// Initialize ivars
	
	if (viewConnection->state == nil)
		viewConnection->state = [[YapDatabaseViewState alloc] init];
	
	// Enumerate the existing rows in the database and populate the view
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting  *sorting  = nil;
	
	[viewConnection getGrouping:&grouping
	                    sorting:&sorting];
	
	BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
	BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
	
	BOOL groupingNeedsMetadata = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
	BOOL sortingNeedsMetadata  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
	
	BOOL needsObject = groupingNeedsObject || sortingNeedsObject;
	BOOL needsMetadata = groupingNeedsMetadata || sortingNeedsMetadata;
	
	NSString *(^getGroup)(NSString *collection, NSString *key, id object, id metadata);
	
	if (grouping->blockType == YapDatabaseBlockTypeWithKey)
	{
		getGroup = ^(NSString *collection, NSString *key, id __unused object, id __unused metadata){
			
			__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
		        (YapDatabaseViewGroupingWithKeyBlock)grouping->block;
			
			NSString *group = groupingBlock(databaseTransaction, collection, key);
			return [group copy]; // mutable string protection
		};
	}
	else if (grouping->blockType == YapDatabaseBlockTypeWithObject)
	{
		getGroup = ^(NSString *collection, NSString *key, id object, id __unused metadata){
			
			__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
		        (YapDatabaseViewGroupingWithObjectBlock)grouping->block;
			
			NSString *group = groupingBlock(databaseTransaction, collection, key, object);
			return [group copy]; // mutable string protection
		};
	}
	else if (grouping->blockType == YapDatabaseBlockTypeWithMetadata)
	{
		getGroup = ^(NSString *collection, NSString *key, id __unused object, id metadata){
			
			__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
		        (YapDatabaseViewGroupingWithMetadataBlock)grouping->block;
			
			NSString *group = groupingBlock(databaseTransaction, collection, key, metadata);
			return [group copy]; // mutable string protection
		};
	}
	else
	{
		getGroup = ^(NSString *collection, NSString *key, id object, id metadata){
			
			__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
		        (YapDatabaseViewGroupingWithRowBlock)grouping->block;
			
			NSString *group = groupingBlock(databaseTransaction, collection, key, object, metadata);
			return [group copy]; // mutable string protection
		};
	}
	
	YapDatabaseViewChangesBitMask flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
	
	if (needsObject && needsMetadata)
	{
		if (groupingNeedsObject || groupingNeedsMetadata)
		{
			void (^block)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop);
			block = ^(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL __unused *stop){
				
				NSString *group = getGroup(collection, key, object, metadata);
				if (group)
				{
					YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
					[self insertRowid:rowid
					    collectionKey:collectionKey
					           object:object
					         metadata:metadata
					          inGroup:group withChanges:flags isNew:YES];
				}
			};
			
			YapWhitelistBlacklist *allowedCollections = viewConnection->view->options.allowedCollections;
			if (allowedCollections)
			{
				[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL *__unused outerStop) {
					
					if ([allowedCollections isAllowed:collection]) {
						[databaseTransaction _enumerateRowsInCollections:@[ collection ] usingBlock:block];
					}
				}];
			}
			else // if (!allowedCollections)
			{
				[databaseTransaction _enumerateRowsInAllCollectionsUsingBlock:block];
			}
		}
		else
		{
			// Optimization: Grouping doesn't require the object or metadata.
			// So we can skip the deserialization step for any rows not in the view.
			
			__block NSString *group = nil;
			
			BOOL (^filter)(int64_t rowid, NSString *collection, NSString *key);
			filter = ^BOOL(int64_t __unused rowid, NSString *collection, NSString *key) {
				
				group = getGroup(collection, key, nil, nil);
				return (group != nil);
			};
			
			void (^block)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop);
			block = ^(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL __unused *stop){
				
				YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
				[self insertRowid:rowid
				    collectionKey:collectionKey
				           object:object
				         metadata:metadata
				          inGroup:group withChanges:flags isNew:YES];
			};
			
			YapWhitelistBlacklist *allowedCollections = viewConnection->view->options.allowedCollections;
			if (allowedCollections)
			{
				[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
					
					if ([allowedCollections isAllowed:collection])
					{
						[databaseTransaction _enumerateRowsInCollections:@[ collection ]
						                                      usingBlock:block
						                                      withFilter:filter];
					}
				}];
			}
			else // if (!allowedCollections)
			{
				[databaseTransaction _enumerateRowsInAllCollectionsUsingBlock:block withFilter:filter];
			}
		}
	}
	else if (needsObject && !needsMetadata)
	{
		if (groupingNeedsObject)
		{
			void (^block)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop);
			block = ^(int64_t rowid, NSString *collection, NSString *key, id object, BOOL __unused *stop){
				
				NSString *group = getGroup(collection, key, object, nil);
				if (group)
				{
					YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
					[self insertRowid:rowid
					    collectionKey:collectionKey
					           object:object
					          metadata:nil
					           inGroup:group withChanges:flags isNew:YES];
				}
			};
			
			YapWhitelistBlacklist *allowedCollections = viewConnection->view->options.allowedCollections;
			if (allowedCollections)
			{
				[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
					
					if ([allowedCollections isAllowed:collection])
					{
						[databaseTransaction _enumerateKeysAndObjectsInCollections:@[ collection ]
						                                                usingBlock:block];
					}
				}];
			}
			else // if (!allowedCollections)
			{
				[databaseTransaction _enumerateKeysAndObjectsInAllCollectionsUsingBlock:block];
			}
		}
		else
		{
			// Optimization: Grouping doesn't require the object.
			// So we can skip the deserialization step for any rows not in the view.
			
			__block NSString *group = nil;
			
			BOOL (^filter)(int64_t rowid, NSString *collection, NSString *key);
			filter = ^BOOL(int64_t __unused rowid, NSString *collection, NSString *key) {
				
				group = getGroup(collection, key, nil, nil);
				return (group != nil);
			};
			
			void (^block)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop);
			block = ^(int64_t rowid, NSString *collection, NSString *key, id object, BOOL __unused *stop){
				
				YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				[self insertRowid:rowid
				    collectionKey:collectionKey
				           object:object
				          metadata:nil
				        inGroup:group withChanges:flags isNew:YES];
			};
			
			YapWhitelistBlacklist *allowedCollections = viewConnection->view->options.allowedCollections;
			if (allowedCollections)
			{
				[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
					
					if ([allowedCollections isAllowed:collection])
					{
						[databaseTransaction _enumerateKeysAndObjectsInCollections:@[ collection ]
						                                                usingBlock:block
						                                                withFilter:filter];
					}
				}];
			}
			else // if (!allowedCollections)
			{
				[databaseTransaction _enumerateKeysAndObjectsInAllCollectionsUsingBlock:block withFilter:filter];
			}
		}
	}
	else if (!needsObject && needsMetadata)
	{
		if (groupingNeedsMetadata)
		{
			void (^block)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop);
			block = ^(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL __unused *stop){
				
				NSString *group = getGroup(collection, key, nil, metadata);
				if (group)
				{
					YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
					[self insertRowid:rowid
					    collectionKey:collectionKey
					           object:nil
					         metadata:metadata
					          inGroup:group withChanges:flags isNew:YES];
				}
			};
			
			
			YapWhitelistBlacklist *allowedCollections = viewConnection->view->options.allowedCollections;
			if (allowedCollections)
			{
				[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
					
					if ([allowedCollections isAllowed:collection])
					{
						[databaseTransaction _enumerateKeysAndMetadataInCollections:@[ collection ]
						                                                 usingBlock:block];
					}
				}];
			}
			else  // if (!allowedCollections)
			{
				[databaseTransaction _enumerateKeysAndMetadataInAllCollectionsUsingBlock:block];
			}
		}
		else
		{
			// Optimization: Grouping doesn't require the metadata.
			// So we can skip the deserialization step for any rows not in the view.
			
			__block NSString *group = nil;
			
			BOOL (^filter)(int64_t rowid, NSString *collection, NSString *key);
			filter = ^BOOL(int64_t __unused rowid, NSString *collection, NSString *key){
				
				group = getGroup(collection, key, nil, nil);
				return (group != nil);
			};
			
			void (^block)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop);
			block = ^(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL __unused *stop){
				
				YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				[self insertRowid:rowid
				    collectionKey:collectionKey
				           object:nil
				         metadata:metadata
				          inGroup:group withChanges:flags isNew:YES];
			};
			
			YapWhitelistBlacklist *allowedCollections = viewConnection->view->options.allowedCollections;
			if (allowedCollections)
			{
				[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
					
					if ([allowedCollections isAllowed:collection])
					{
						[databaseTransaction _enumerateKeysAndMetadataInCollections:@[ collection ]
						                                                 usingBlock:block
						                                                 withFilter:filter];
					}
				}];
			}
			else  // if (!allowedCollections)
			{
				[databaseTransaction _enumerateKeysAndMetadataInAllCollectionsUsingBlock:block withFilter:filter];
			}
		}
	}
	else // if (!needsObject && !needsMetadata)
	{
		void (^block)(int64_t rowid, NSString *collection, NSString *key, BOOL *stop);
		block = ^(int64_t rowid, NSString *collection, NSString *key, BOOL __unused *stop){
			
			NSString *group = getGroup(collection, key, nil, nil);
			if (group)
			{
				YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				[self insertRowid:rowid
				    collectionKey:collectionKey
				           object:nil
				         metadata:nil
				          inGroup:group withChanges:flags isNew:YES];
			}
		};
		
		YapWhitelistBlacklist *allowedCollections = viewConnection->view->options.allowedCollections;
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
				
				if ([allowedCollections isAllowed:collection])
				{
					[databaseTransaction _enumerateKeysInCollections:@[ collection ] usingBlock:block];
				}
			}];
		}
		else  // if (!allowedCollections)
		{
			[databaseTransaction _enumerateKeysInAllCollectionsUsingBlock:block];
		}
	}
	
	return YES;
}

- (void)repopulateView
{
	YDBLogAutoTrace();
	
	// Code overview:
	//
	// We could simply run the usual algorithm.
	// That is, enumerate over every item in the database, and run pretty much the same code as
	// in the handleUpdateObject:forCollectionKey:withMetadata:rowid:.
	// However, this causes a potential issue where the sortingBlock will be invoked with items that
	// no longer exist in the given group.
	//
	// Instead we're going to find a way around this.
	// That way the sortingBlock works in a manner we're used to.
	//
	// Here's the algorithm overview:
	//
	// - Insert remove ops for every row & group
	// - Remove all items from the database tables
	// - Flush the group_pagesMetadata_dict (and related ivars)
	// - Set the reset flag (for internal notification creation)
	// - And then run the normal populate routine, with one exceptione handled by the isRepopulate flag.
	//
	// The changeset mechanism will automatically consolidate all changes to the minimum.
	
	[viewConnection->state enumerateGroupsWithBlock:^(NSString *group, BOOL __unused *outerStop) {
		
		// We must add the changes in reverse order.
		// Either that, or the change index of each item would have to be zero,
		// because a YapDatabaseViewRowChange records the index at the moment the change happens.
		
		[self enumerateRowidsInGroup:group
		                 withOptions:NSEnumerationReverse
		                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL __unused *innerStop)
		{
			YapCollectionKey *collectionKey = [databaseTransaction collectionKeyForRowid:rowid];
			
			[viewConnection->changes addObject:
			  [YapDatabaseViewRowChange deleteCollectionKey:collectionKey inGroup:group atIndex:index]];
		}];
		
		[viewConnection->changes addObject:[YapDatabaseViewSectionChange deleteGroup:group]];
	}];
	
	isRepopulate = YES;
	[self populateView];
	isRepopulate = NO;
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
	return viewConnection;
}

- (NSString *)registeredName
{
	return [viewConnection->view registeredName];
}

- (NSString *)mapTableName
{
	return [viewConnection->view mapTableName];
}

- (NSString *)pageTableName
{
	return [viewConnection->view pageTableName];
}

- (NSString *)pageMetadataTableName
{
	return [viewConnection->view pageMetadataTableName];
}

- (BOOL)isPersistentView
{
	return viewConnection->view->options.isPersistent;
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
	
	pageKey = [viewConnection->dirtyMaps objectForKey:rowidNumber];
	if (pageKey)
	{
		if ((id)pageKey == (id)[NSNull null])
			return nil;
		else
			return pageKey;
	}
	
	pageKey = [viewConnection->mapCache objectForKey:rowidNumber];
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
		sqlite3_stmt *statement = [viewConnection mapTable_getPageKeyForRowidStatement];
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
		[viewConnection->mapCache setObject:pageKey forKey:rowidNumber];
	else
		[viewConnection->mapCache setObject:[NSNull null] forKey:rowidNumber];
	
	return pageKey;
}

/**
 * This method looks up a whole bunch of pageKeys using only a few queries.
 *
 * @param rowids
 *     On input, includes all the rowids to lookup.
 *     On output, includes all the valid rowids. That is, those rowids that are in the view.
 * 
 * @param keyMappings
 *     A dictionary of the form: @{
 *         @(rowid) = collectionKey, ...
 *     }
 * 
 * @return A dictionary of the form: @{
 *         pageKey = @{ @(rowid) = collectionKey, ... }
 *     }
**/
- (NSDictionary *)pageKeysForRowids:(NSArray **)rowidsPtr withKeyMappings:(NSDictionary *)keyMappings
{
	if ([*rowidsPtr count] == 0)
	{
		*rowidsPtr = [NSArray array];
		return [NSDictionary dictionary];
	}
	
	NSMutableArray *inRowids =  [*rowidsPtr mutableCopy];
	NSMutableArray *outRowids = [NSMutableArray arrayWithCapacity:[inRowids count]];
	
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[inRowids count]];
	
	// Step 1 of 2:
	//
	// Check for any (rowid, pageKey) information we already have in memory.
	//
	// This is actually a requirement if the information is in dirtyMaps.
	// If the info is in mapCache, then its just an optimization.
	
	for (NSUInteger iPlusOne = [inRowids count]; iPlusOne > 0; iPlusOne--)
	{
		NSUInteger i = iPlusOne - 1;
		NSNumber *rowidNumber = [inRowids objectAtIndex:i];
		
		NSString *pageKey = nil;
		
		pageKey = [viewConnection->dirtyMaps objectForKey:rowidNumber];
		if (pageKey == nil)
		{
			pageKey = [viewConnection->mapCache objectForKey:rowidNumber];
		}
		
		if (pageKey)
		{
			if ((id)pageKey == (id)[NSNull null])
			{
				// This rowid has already been removed from the view,
				// and is marked for deletion from the mapTable.
				//
				// However, it has not been deleted yet, as that will occur during flushPendingChangesToExtensionTables.
				// So we need to remove it from inRowids, as the mapTable will still contain the rowid.
				
				[inRowids removeObjectAtIndex:i];
			}
			else
			{
				// Add to result dictionary
				
				NSMutableDictionary *subKeyMappings = [result objectForKey:pageKey];
				if (subKeyMappings == nil)
				{
					subKeyMappings = [NSMutableDictionary dictionaryWithCapacity:1];
					[result setObject:subKeyMappings forKey:pageKey];
				}
				
				YapCollectionKey *collectionKey = [keyMappings objectForKey:rowidNumber];
				[subKeyMappings setObject:collectionKey forKey:rowidNumber];
				
				// Add to outRowids
				
				[outRowids addObject:rowidNumber];
				
				// Remove from inRowids
				
				[inRowids removeObjectAtIndex:i];
			}
		}
		
	}
	
	// Step 2 of 2:
	//
	// Fetch any pageKey information we're still missing from the database.
	
	NSUInteger count = [inRowids count];
	if (count > 0)
	{
		if ([self isPersistentView])
		{
			sqlite3 *db = databaseTransaction->connection->db;
			
			// Note:
			// The handleRemoveObjectsForKeys:inCollection:withRowids: has the following guarantee:
			//     count <= (SQLITE_LIMIT_VARIABLE_NUMBER - 1)
			//
			// So we don't have to worry about sqlite's upper bound on host parameters.
			
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
				
				*rowidsPtr = nil;
				return nil;
			}
			
			for (NSUInteger i = 0; i < count; i++)
			{
				int64_t rowid = [[inRowids objectAtIndex:i] longLongValue];
				
				sqlite3_bind_int64(statement, (int)(SQLITE_BIND_START + i), rowid);
			}
			
			while ((status = sqlite3_step(statement)) == SQLITE_ROW)
			{
				// Extract rowid & pageKey from row
				
				int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
				
				const unsigned char *text = sqlite3_column_text(statement, column_idx_pageKey);
				int textSize = sqlite3_column_bytes(statement, column_idx_pageKey);
				
				NSNumber *rowidNumber = @(rowid);
				NSString *pageKey = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				
				// Add to result dictionary
				
				NSMutableDictionary *subKeyMappings = [result objectForKey:pageKey];
				if (subKeyMappings == nil)
				{
					subKeyMappings = [NSMutableDictionary dictionaryWithCapacity:1];
					[result setObject:subKeyMappings forKey:pageKey];
				}
				
				YapCollectionKey *collectionKey = [keyMappings objectForKey:rowidNumber];
				[subKeyMappings setObject:collectionKey forKey:rowidNumber];
				
				// Add to outRowids
				
				[outRowids addObject:rowidNumber];
			}
			
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"%@ (%@): Error executing statement: %d %s",
				            THIS_METHOD, [self registeredName], status, sqlite3_errmsg(db));
			}
		
			sqlite3_finalize(statement);
			
		}
		else // if (isNonPersistentView)
		{
			[mapTableTransaction accessWithBlock:^{ @autoreleasepool {
				
				for (NSNumber *rowidNumber in inRowids)
				{
					NSString *pageKey = [mapTableTransaction objectForKey:rowidNumber];
					if (pageKey)
					{
						// Add to result dictionary
						
						NSMutableDictionary *subKeyMappings = [result objectForKey:pageKey];
						if (subKeyMappings == nil)
						{
							subKeyMappings = [NSMutableDictionary dictionaryWithCapacity:1];
							[result setObject:subKeyMappings forKey:pageKey];
						}
						
						NSString *key = [keyMappings objectForKey:rowidNumber];
						[subKeyMappings setObject:key forKey:rowidNumber];
						
						// Add to outRowids
						
						[outRowids addObject:rowidNumber];
					}
				}
			}}];
		}
	}
	
	*rowidsPtr = outRowids;
	return result;
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
	
	page = [viewConnection->dirtyPages objectForKey:pageKey];
	if (page) return page;
	
	page = [viewConnection->pageCache objectForKey:pageKey];
	if (page) return page;
	
	// Otherwise pull from the database
	
	if ([self isPersistentView])
	{
		sqlite3_stmt *statement = [viewConnection pageTable_getDataForPageKeyStatement];
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
		[viewConnection->pageCache setObject:page forKey:pageKey];
	
	return page;
}

- (NSUInteger)indexForRowid:(int64_t)rowid inGroup:(NSString *)group withPageKey:(NSString *)pageKey
{
	// Calculate the offset of the corresponding page within the group.
	
	NSUInteger pageOffset = 0;
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	
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

- (BOOL)getRowid:(int64_t *)rowidPtr atIndex:(NSUInteger)index inGroup:(NSString *)group
{
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
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
	
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	
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

- (BOOL)containsRowid:(int64_t)rowid
{
	return ([self pageKeyForRowid:rowid] != nil);
}

- (NSString *)groupForRowid:(int64_t)rowid
{
	return [viewConnection->state groupForPageKey:[self pageKeyForRowid:rowid]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Creates a new group and inserts the given row.
 * Important: The group MUST NOT already exist.
**/
- (void)insertRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey inNewGroup:(NSString *)group
{
	YDBLogAutoTrace();
	
	NSParameterAssert(collectionKey != nil);
	NSParameterAssert(group != nil);
	
	// First object added to group.
	
	NSString *pageKey = [self generatePageKey];
	
	YDBLogVerbose(@"Inserting key(%@) collection(%@) in new group(%@) with page(%@)",
				  collectionKey.key, collectionKey.collection, group, pageKey);
	
	// Create page
	
	YapDatabaseViewPage *page =
	  [[YapDatabaseViewPage alloc] initWithCapacity:YAP_DATABASE_VIEW_MAX_PAGE_SIZE];
	[page addRowid:rowid];
	
	// Create pageMetadata
	
	YapDatabaseViewPageMetadata *pageMetadata = [[YapDatabaseViewPageMetadata alloc] init];
	pageMetadata->pageKey = pageKey;
	pageMetadata->prevPageKey = nil;
	pageMetadata->group = group;
	pageMetadata->count = 1;
	pageMetadata->isNew = YES;
	
	// Add pageMetadata to state
	
	[viewConnection->state createGroup:group withCapacity:1];
	[viewConnection->state addPageMetadata:pageMetadata toGroup:group];
	
	// Mark page as dirty
	
	[viewConnection->dirtyPages setObject:page forKey:pageKey];
	[viewConnection->pageCache setObject:page forKey:pageKey];
	
	// Mark rowid for insertion
	
	[viewConnection->dirtyMaps setObject:pageKey forKey:@(rowid)];
	[viewConnection->mapCache setObject:pageKey forKey:@(rowid)];
	
	// Add change to log
	
	[viewConnection->changes addObject:
	  [YapDatabaseViewSectionChange insertGroup:group]];
	
	[viewConnection->changes addObject:
	  [YapDatabaseViewRowChange insertCollectionKey:collectionKey inGroup:group atIndex:0]];
	
	[viewConnection->mutatedGroups addObject:group];
	
	// Subclass hook
	
	[self didInsertRowid:rowid collectionKey:collectionKey];
}

/**
 * Inserts the given rowid into an existing group.
 * Important: The group MUST already exist.
**/
- (void)insertRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
                                         inGroup:(NSString *)group
                                         atIndex:(NSUInteger)index
                             withExistingPageKey:(NSString *)existingPageKey
{
	YDBLogAutoTrace();
	
	NSParameterAssert(collectionKey != nil);
	NSParameterAssert(group != nil);
	
	// Find pageMetadata, pageKey and page
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	
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
	
	[viewConnection->dirtyPages setObject:page forKey:pageKey];
	[viewConnection->pageCache setObject:page forKey:pageKey];
	
	// Mark key for insertion (if needed - may have already been in group)
	
	if (![pageKey isEqualToString:existingPageKey])
	{
		[viewConnection->dirtyMaps setObject:pageKey forKey:@(rowid)];
		[viewConnection->mapCache setObject:pageKey forKey:@(rowid)];
	}
	
	// Add change to log
	
	[viewConnection->changes addObject:
	  [YapDatabaseViewRowChange insertCollectionKey:collectionKey inGroup:group atIndex:index]];
	
	[viewConnection->mutatedGroups addObject:group];
	
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
	
	// Subclass hook
	
	[self didInsertRowid:rowid collectionKey:collectionKey];
}

/**
 * Use this method after it has been determined that the key should be inserted into the given group.
 * The object and metadata parameters must be properly set (if needed by the sorting block).
 * 
 * This method will use the configured sorting block to find the proper index for the key.
 * It will attempt to optimize this operation as best as possible using a variety of techniques.
**/
- (void)insertRowid:(int64_t)rowid
      collectionKey:(YapCollectionKey *)collectionKey
			 object:(id)object
           metadata:(id)metadata
            inGroup:(NSString *)group
        withChanges:(YapDatabaseViewChangesBitMask)flags
              isNew:(BOOL)isGuaranteedNew
{
	YDBLogAutoTrace();
	
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getSorting:&sorting];
	
	// Is the key already in the group?
	// If so:
	// - its index within the group may or may not have changed.
	// - we can use its existing position as an optimization during sorting.
	
	BOOL tryExistingIndexInGroup = NO;
	NSUInteger existingIndexInGroup = NSNotFound;
	
	NSString *existingPageKey = isGuaranteedNew ? nil : [self pageKeyForRowid:rowid];
	if (existingPageKey)
	{
		// The key is already in the view.
		// Has it changed groups?
		
		NSString *existingGroup = [viewConnection->state groupForPageKey:existingPageKey];
		
		if ([group isEqualToString:existingGroup])
		{
			// The key is already in the group.
			//
			// Possible optimization:
			// Object or metadata was updated, but doesn't affect the position of the row within the view.
			
			existingIndexInGroup = [self indexForRowid:rowid inGroup:group withPageKey:existingPageKey];
			tryExistingIndexInGroup = YES;
		}
		else
		{
			// The item has changed groups.
			// Remove it from previous group.
			
			[self removeRowid:rowid collectionKey:collectionKey
			                          withPageKey:existingPageKey
			                              inGroup:existingGroup
			                     skipSubclassHook:YES]; // will be re-adding (in new group)
			
			// Don't forget to reset the existingPageKey ivar!
			// Or else 'insertKey:inGroup:atIndex:withExistingPageKey:' will be given an invalid existingPageKey.
			existingPageKey = nil;
		}
	}
	
	// Fetch the pages associated with the group.
	
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	
	// Is this a new group ?
	
	if (pagesMetadataForGroup == nil)
	{
		// First object added to group.
		
		[self insertRowid:rowid collectionKey:collectionKey inNewGroup:group];
		return;
	}
	
	// Need to determine the location within the existing group.

	// Calculate how many keys are in the group.
	
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
		
		int64_t anotherRowid = 0;
		
		NSUInteger pageOffset = 0;
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
		{
			if ((index < (pageOffset + pageMetadata->count)) && (pageMetadata->count > 0))
			{
				YapDatabaseViewPage *page = [self pageForPageKey:pageMetadata->pageKey];
				
				anotherRowid = [page rowidAtIndex:(index - pageOffset)];
				break;
			}
			else
			{
				pageOffset += pageMetadata->count;
			}
		}
		
		if (sorting->blockType == YapDatabaseBlockTypeWithKey)
		{
			__unsafe_unretained YapDatabaseViewSortingWithKeyBlock sortingBlock =
			    (YapDatabaseViewSortingWithKeyBlock)sorting->block;
			
			YapCollectionKey *another = [databaseTransaction collectionKeyForRowid:anotherRowid];
			
			return sortingBlock(databaseTransaction, group,
			                      collectionKey.collection, collectionKey.key,
			                            another.collection,       another.key);
		}
		else if (sorting->blockType == YapDatabaseBlockTypeWithObject)
		{
			__unsafe_unretained YapDatabaseViewSortingWithObjectBlock sortingBlock =
			    (YapDatabaseViewSortingWithObjectBlock)sorting->block;
			
			YapCollectionKey *another = nil;
			id anotherObject = nil;
			[databaseTransaction getCollectionKey:&another
			                               object:&anotherObject
			                             forRowid:anotherRowid];
			
			return sortingBlock(databaseTransaction, group,
			                      collectionKey.collection, collectionKey.key,        object,
			                            another.collection,       another.key, anotherObject);
		}
		else if (sorting->blockType == YapDatabaseBlockTypeWithMetadata)
		{
			__unsafe_unretained YapDatabaseViewSortingWithMetadataBlock sortingBlock =
			    (YapDatabaseViewSortingWithMetadataBlock)sorting->block;
			
			YapCollectionKey *another = nil;
			id anotherMetadata = nil;
			[databaseTransaction getCollectionKey:&another
			                             metadata:&anotherMetadata
			                             forRowid:anotherRowid];
			
			return sortingBlock(databaseTransaction, group,
			                      collectionKey.collection, collectionKey.key,        metadata,
			                            another.collection,       another.key, anotherMetadata);
		}
		else
		{
			__unsafe_unretained YapDatabaseViewSortingWithRowBlock sortingBlock =
			    (YapDatabaseViewSortingWithRowBlock)sorting->block;
			
			YapCollectionKey *another = nil;
			id anotherObject = nil;
			id anotherMetadata = nil;
			[databaseTransaction getCollectionKey:&another
			                               object:&anotherObject
			                             metadata:&anotherMetadata
			                             forRowid:anotherRowid];
			
			return sortingBlock(databaseTransaction, group,
			                      collectionKey.collection, collectionKey.key,        object,        metadata,
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
		// Edge case: existing key is the only key in the group
		//
		// (existingIndex == 0) && (count == 1)
		
		BOOL useExistingIndexInGroup = YES;
		
		if (existingIndexInGroup > 0)
		{
			cmp = compare(existingIndexInGroup - 1); // compare vs prev
			
			useExistingIndexInGroup = (cmp != NSOrderedAscending); // object >= prev
		}
		
		if ((existingIndexInGroup + 1) < count && useExistingIndexInGroup)
		{
			cmp = compare(existingIndexInGroup + 1); // compare vs next
			
			useExistingIndexInGroup = (cmp != NSOrderedDescending); // object <= next
		}
		
		if (useExistingIndexInGroup)
		{
			// The key doesn't change position.
			
			YDBLogVerbose(@"Updated key(%@) in group(%@) maintains current index", collectionKey.key, group);
			
			[viewConnection->changes addObject:
			  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
			                                        inGroup:group
			                                        atIndex:existingIndexInGroup
			                                    withChanges:flags]];
			return;
		}
		else
		{
			// The item has changed position within its group.
			// Remove it from previous position (and don't forget to decrement count).
			
			[self removeRowid:rowid collectionKey:collectionKey
			                          withPageKey:existingPageKey
			                              inGroup:group
			                     skipSubclassHook:YES]; // will be re-adding (in new index)
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
			
			[self insertRowid:rowid collectionKey:collectionKey
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
			
			[self insertRowid:rowid collectionKey:collectionKey
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
	
	[self insertRowid:rowid collectionKey:collectionKey
	                              inGroup:group
	                              atIndex:min
	                  withExistingPageKey:existingPageKey];
	
	viewConnection->lastInsertWasAtFirstIndex = (min == 0);
	viewConnection->lastInsertWasAtLastIndex  = (min == count);
}

/**
 * Use this method when the index (within the group) is already known.
**/
- (void)removeRowid:(int64_t)rowid
      collectionKey:(YapCollectionKey *)collectionKey
            atIndex:(NSUInteger)index
            inGroup:(NSString *)group
{
	YDBLogAutoTrace();
	
	NSParameterAssert(collectionKey != nil);
	NSParameterAssert(group != nil);
	
	// Fetch page
	
	YapDatabaseViewPage *page = nil;
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	
	NSUInteger pageOffset = 0;
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	
	for (YapDatabaseViewPageMetadata *pm in pagesMetadataForGroup)
	{
		if ((index < (pageOffset + pm->count)) && (pm->count > 0))
		{
			pageMetadata = pm;
			page = [self pageForPageKey:pm->pageKey];
			
			break;
		}
		else
		{
			pageOffset += pm->count;
		}
	}
	
	if (page == nil)
	{
		YDBLogError(@"%@ (%@): Unable to remove rowid at groupIndex(%lu) in group(%@)",
		            THIS_METHOD, [self registeredName], (unsigned long)index, group);
		return;
	}
	
	// Verify specified rowid matches specified index
	
	NSUInteger indexWithinPage = index - pageOffset;
	
	NSAssert(rowid == [page rowidAtIndex:indexWithinPage], @"Rowid mismatch");
	
	YDBLogVerbose(@"Removing collection(%@) key(%@) from page(%@) at pageIndex(%lu)",
	              collectionKey.collection, collectionKey.key, page, (unsigned long)indexWithinPage);
	
	// Add change to log
	
	[viewConnection->changes addObject:
	  [YapDatabaseViewRowChange deleteCollectionKey:collectionKey inGroup:group atIndex:index]];
	
	[viewConnection->mutatedGroups addObject:group];
	
	// Update page (by removing rowid from array)
	
	[page removeRowidAtIndex:indexWithinPage];
	
	// Update page metadata (by decrementing count)
	
	pageMetadata->count = [page count];
	
	// Mark page as dirty
	
	YDBLogVerbose(@"Dirty page(%@)", pageMetadata->pageKey);
	
	[viewConnection->dirtyPages setObject:page forKey:pageMetadata->pageKey];
	[viewConnection->pageCache setObject:page forKey:pageMetadata->pageKey];
	
	// Mark key for deletion
	
	[viewConnection->dirtyMaps setObject:[NSNull null] forKey:@(rowid)];
	[viewConnection->mapCache removeObjectForKey:@(rowid)];
	
	// Subclass hook
	
	[self didRemoveRowid:rowid collectionKey:collectionKey];
}

/**
 * Use this method (instead of removeKey:) when the pageKey and group are already known.
**/
- (void)removeRowid:(int64_t)rowid
      collectionKey:(YapCollectionKey *)collectionKey
        withPageKey:(NSString *)pageKey
            inGroup:(NSString *)group
   skipSubclassHook:(BOOL)skipSubclassHook
{
	YDBLogAutoTrace();
	
	NSParameterAssert(collectionKey != nil);
	NSParameterAssert(pageKey != nil);
	NSParameterAssert(group != nil);
	
	// Fetch page & pageMetadata
	
	YapDatabaseViewPage *page = [self pageForPageKey:pageKey];
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	NSUInteger pageOffset = 0;
	
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	
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
	
	[viewConnection->changes addObject:
	  [YapDatabaseViewRowChange deleteCollectionKey:collectionKey inGroup:group atIndex:indexWithinGroup]];
	
	[viewConnection->mutatedGroups addObject:group];
	
	// Update page (by removing key from array)
	
	[page removeRowidAtIndex:indexWithinPage];
	
	// Update page metadata (by decrementing count)
	
	pageMetadata->count = [page count];
	
	// Mark page as dirty
	
	YDBLogVerbose(@"Dirty page(%@)", pageKey);
	
	[viewConnection->dirtyPages setObject:page forKey:pageKey];
	[viewConnection->pageCache setObject:page forKey:pageKey];
	
	// Mark key for deletion
	
	[viewConnection->dirtyMaps setObject:[NSNull null] forKey:@(rowid)];
	[viewConnection->mapCache removeObjectForKey:@(rowid)];
	
	// Subclass hook
	
	if (!skipSubclassHook) {
		[self didRemoveRowid:rowid collectionKey:collectionKey];
	}
}

/**
 * Use this method when you don't know if the collection/key exists in the view.
**/
- (void)removeRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
{
	YDBLogAutoTrace();
	
	// Find out if collection/key is in view
	
	NSString *pageKey = [self pageKeyForRowid:rowid];
	if (pageKey)
	{
		[self removeRowid:rowid collectionKey:collectionKey
		                          withPageKey:pageKey
		                              inGroup:[viewConnection->state groupForPageKey:pageKey]
		                     skipSubclassHook:NO];
	}
}

/**
 * Use this method to remove 1 or more keys from a given pageKey & group.
 *
 * The dictionary is to be of the form:
 * @{
 *     @(rowid) = collectionKey,
 * }
**/
- (void)removeRowidsWithKeyMappings:(NSDictionary *)keyMappings pageKey:(NSString *)pageKey inGroup:(NSString *)group
{
	YDBLogAutoTrace();
	
	NSUInteger count = [keyMappings count];
	
	if (count == 0) return;
	if (count == 1)
	{
		for (NSNumber *rowidNumber in keyMappings)
		{
			int64_t rowid = [rowidNumber longLongValue];
			YapCollectionKey *collectionKey = [keyMappings objectForKey:rowidNumber];
			
			[self removeRowid:rowid collectionKey:collectionKey
			                          withPageKey:pageKey
			                              inGroup:group
			                     skipSubclassHook:YES]; // The handleRemoveObjectsForKeys::: does it
		}
		return;
	}
	
	NSParameterAssert(pageKey != nil);
	NSParameterAssert(group != nil);
	
	// Fetch page & pageMetadata
	
	YapDatabaseViewPage *page = [self pageForPageKey:pageKey];
	
	YapDatabaseViewPageMetadata *pageMetadata = nil;
	NSUInteger pageOffset = 0;
	
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	
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
	
	// Find matching indexes within page.
	// And add changes to log.
	// Notes:
	//
	// - We must add the changes in reverse order,
	//     just as if we were deleting them from the array one-at-a-time.
	
	NSUInteger numRemoved = 0;
	
	for (NSUInteger iPlusOne = [page count]; iPlusOne > 0; iPlusOne--)
	{
		NSUInteger i = iPlusOne - 1;
		int64_t rowid = [page rowidAtIndex:i];
		
		YapCollectionKey *collectionKey = [keyMappings objectForKey:@(rowid)];
		if (collectionKey)
		{
			[page removeRowidAtIndex:i];
			numRemoved++;
			
			[viewConnection->changes addObject:
			  [YapDatabaseViewRowChange deleteCollectionKey:collectionKey inGroup:group atIndex:(pageOffset + i)]];
		}
	}
	
	[viewConnection->mutatedGroups addObject:group];
	
	YDBLogVerbose(@"Removed %lu key(s) from page(%@)", (unsigned long)numRemoved, page);
	
	if (numRemoved != count)
	{
		YDBLogWarn(@"%@ (%@): Expected to remove %lu, but only found %lu in page(%@)",
		           THIS_METHOD, [self registeredName], (unsigned long)count, (unsigned long)numRemoved, pageKey);
	}
	
	// Update page metadata (by decrementing count)
	
	pageMetadata->count = [page count];
	
	// Mark page as dirty
	
	YDBLogVerbose(@"Dirty page(%@)", pageKey);
	
	[viewConnection->dirtyPages setObject:page forKey:pageKey];
	[viewConnection->pageCache setObject:page forKey:pageKey];
	
	// Mark rowid mappings for deletion
	
	for (NSNumber *rowidNumber in keyMappings)
	{
		[viewConnection->dirtyMaps setObject:[NSNull null] forKey:rowidNumber];
		[viewConnection->mapCache removeObjectForKey:rowidNumber];
	}
}

/**
 * This method is used by subclasses.
**/
- (void)removeAllRowidsInGroup:(NSString *)group
{
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	NSMutableArray *removedRowids = [NSMutableArray array];
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		YapDatabaseViewPage *page = [self pageForPageKey:pageMetadata->pageKey];
		
		// Mark all rowids for deletion
		
		[page enumerateRowidsUsingBlock:^(int64_t rowid, NSUInteger __unused idx, BOOL __unused *stop) {
			
			[removedRowids addObject:@(rowid)];
			
			[viewConnection->dirtyMaps setObject:[NSNull null] forKey:@(rowid)];
			[viewConnection->mapCache removeObjectForKey:@(rowid)];
		}];
		
		// Update page (by removing all rowids from array)
		
		[page removeAllRowids];
		
		// Update page metadata (by clearing count)
		
		pageMetadata->count = 0;
		
		// Mark page as dirty
		
		YDBLogVerbose(@"Dirty page(%@)", pageMetadata->pageKey);
		
		[viewConnection->dirtyPages setObject:page forKey:pageMetadata->pageKey];
		[viewConnection->pageCache setObject:page forKey:pageMetadata->pageKey];
	}
	
	[viewConnection->changes addObject:[YapDatabaseViewSectionChange resetGroup:group]];
	[viewConnection->mutatedGroups addObject:group];
	
	// Subclass hook
	
	[self didRemoveRowids:removedRowids collectionKeys:nil];
}

- (void)removeAllRowids
{
	YDBLogAutoTrace();
	
	if ([self isPersistentView])
	{
		sqlite3_stmt *mapStatement = [viewConnection mapTable_removeAllStatement];
		sqlite3_stmt *pageStatement = [viewConnection pageTable_removeAllStatement];
		
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
	
	[viewConnection->state enumerateGroupsWithBlock:^(NSString *group, BOOL __unused *stop) {
		
		if (!isRepopulate) {
			[viewConnection->changes addObject:[YapDatabaseViewSectionChange resetGroup:group]];
		}
		[viewConnection->mutatedGroups addObject:group];
	}];
	
	[viewConnection->state removeAllGroups];
	
	[viewConnection->mapCache removeAllObjects];
	[viewConnection->pageCache removeAllObjects];
	
	[viewConnection->dirtyMaps removeAllObjects];
	[viewConnection->dirtyPages removeAllObjects];
	[viewConnection->dirtyLinks removeAllObjects];
	
	viewConnection->reset = YES;
	
	// Subclass hook
	
	[self didRemoveAllRowids];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cleanup & Commit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)splitOversizedPage:(YapDatabaseViewPage *)page withPageKey:(NSString *)pageKey toSize:(NSUInteger)maxPageSize
{
	YDBLogAutoTrace();
	
	// Find associated pageMetadata
	
	NSString *group = [viewConnection->state groupForPageKey:pageKey];
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	
	YapDatabaseViewPageMetadata *pageMetadata;
	for (YapDatabaseViewPageMetadata *pm in pagesMetadataForGroup)
	{
		if ([pm->pageKey isEqualToString:pageKey])
		{
			pageMetadata = pm;
			break;
		}
	}
	
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
				
				[viewConnection->dirtyPages setObject:prevPage forKey:prevPageMetadata->pageKey];
				[viewConnection->pageCache setObject:prevPage forKey:prevPageMetadata->pageKey];
				
				// Mark rowid mappings as dirty
				
				[prevPage enumerateRowidsWithOptions:0
				                               range:prevPageRange
				                          usingBlock:^(int64_t rowid, NSUInteger __unused index, BOOL __unused *stop) {
					
					NSNumber *number = @(rowid);
					
					[viewConnection->dirtyMaps setObject:prevPageMetadata->pageKey forKey:number];
					[viewConnection->mapCache setObject:prevPageMetadata->pageKey forKey:number];
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
				
				[viewConnection->dirtyPages setObject:nextPage forKey:nextPageMetadata->pageKey];
				[viewConnection->pageCache setObject:nextPage forKey:nextPageMetadata->pageKey];
				
				// Mark rowid mappings as dirty
				
				[nextPage enumerateRowidsWithOptions:0
				                               range:nextPageRange
				                          usingBlock:^(int64_t rowid, NSUInteger __unused index, BOOL __unused *stop) {
					
					NSNumber *number = @(rowid);
					
					[viewConnection->dirtyMaps setObject:nextPageMetadata->pageKey forKey:number];
					[viewConnection->mapCache setObject:nextPageMetadata->pageKey forKey:number];
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
		
		pagesMetadataForGroup = [viewConnection->state insertPageMetadata:newPageMetadata
		                                                          atIndex:(pageIndex + 1)
		                                                          inGroup:group];
		
		// Update linked-list (if needed)
		
		if ((pageIndex + 2) < [pagesMetadataForGroup count])
		{
			YapDatabaseViewPageMetadata *nextPageMetadata = [pagesMetadataForGroup objectAtIndex:(pageIndex + 2)];
			nextPageMetadata->prevPageKey = newPageKey;
			
			[viewConnection->dirtyLinks setObject:nextPageMetadata forKey:nextPageMetadata->pageKey];
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
		
		[viewConnection->dirtyPages setObject:newPage forKey:newPageKey];
		[viewConnection->pageCache setObject:newPage forKey:newPageKey];
		
		// Mark rowid mappings as dirty
		
		[newPage enumerateRowidsUsingBlock:^(int64_t rowid, NSUInteger __unused idx, BOOL __unused *stop) {
			
			NSNumber *number = @(rowid);
			
			[viewConnection->dirtyMaps setObject:newPageKey forKey:number];
			[viewConnection->mapCache setObject:newPageKey forKey:number];
		}];
		
	} // end while (pageMetadata->count > maxPageSize)
}

- (void)dropEmptyPage:(YapDatabaseViewPage __unused *)page withPageKey:(NSString *)pageKey
{
	YDBLogAutoTrace();
	
	// Find associated pageMetadata
	
	NSString *group = [viewConnection->state groupForPageKey:pageKey];
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	
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
		
		[viewConnection->dirtyLinks setObject:nextPageMetadata forKey:nextPageMetadata->pageKey];
	}
	
	// Drop pageMetada (from in-memory state)
	
	pagesMetadataForGroup = [viewConnection->state removePageMetadataAtIndex:pageIndex inGroup:group];
	
	// Mark page as dropped
	
	[viewConnection->dirtyPages setObject:[NSNull null] forKey:pageMetadata->pageKey];
	[viewConnection->pageCache removeObjectForKey:pageMetadata->pageKey];
	
	[viewConnection->dirtyLinks removeObjectForKey:pageMetadata->pageKey];
	
	// Maybe drop group
	
	if ([pagesMetadataForGroup count] == 0)
	{
		YDBLogVerbose(@"Dropping empty group(%@)", pageMetadata->group);
		
		[viewConnection->changes addObject:
		    [YapDatabaseViewSectionChange deleteGroup:pageMetadata->group]];
		
		[viewConnection->state removeGroup:group];
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
	
	NSArray *pageKeys = [viewConnection->dirtyPages allKeys];
	
	// Step 1 is to "expand" the oversized pages.
	//
	// This means either splitting them in 2,
	// or allowing items to spill over into a neighboring page (that has room).
	
	for (NSString *pageKey in pageKeys)
	{
		YapDatabaseViewPage *page = [viewConnection->dirtyPages objectForKey:pageKey];
		
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
		YapDatabaseViewPage *page = [viewConnection->dirtyPages objectForKey:pageKey];
		
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
	
	YDBLogVerbose(@"viewConnection->dirtyPages: %@", viewConnection->dirtyPages);
	YDBLogVerbose(@"viewConnection->dirtyLinks: %@", viewConnection->dirtyLinks);
	YDBLogVerbose(@"viewConnection->dirtyMaps: %@", viewConnection->dirtyMaps);
	
	if ([self isPersistentView])
	{
		// Persistent View: Step 1 of 3
		//
		// Write dirty pages to table (along with associated dirty metadata)
	
		[viewConnection->dirtyPages enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop) {
			
			__unsafe_unretained NSString *pageKey = (NSString *)key;
			__unsafe_unretained YapDatabaseViewPage *page = (YapDatabaseViewPage *)obj;
			
			BOOL needsInsert = NO;
			BOOL hasDirtyLink = NO;
			
			YapDatabaseViewPageMetadata *pageMetadata = nil;
			
			pageMetadata = [viewConnection->dirtyLinks objectForKey:pageKey];
			if (pageMetadata)
			{
				hasDirtyLink = YES;
			}
			else
			{
				NSString *group = [viewConnection->state groupForPageKey:pageKey];
				NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
				
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
				sqlite3_stmt *statement = [viewConnection pageTable_removeForPageKeyStatement];
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
				sqlite3_stmt *statement = [viewConnection pageTable_insertForPageKeyStatement];
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
				sqlite3_stmt *statement = [viewConnection pageTable_updateAllForPageKeyStatement];
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
				sqlite3_stmt *statement = [viewConnection pageTable_updatePageForPageKeyStatement];
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
		
		[viewConnection->dirtyLinks enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			
			NSString *pageKey = (NSString *)key;
			YapDatabaseViewPageMetadata *pageMetadata = (YapDatabaseViewPageMetadata *)obj;
			
			if ([viewConnection->dirtyPages objectForKey:pageKey])
			{
				// Both the page and metadata were dirty, so we wrote them both to disk at the same time.
				// No need to write the metadata again.
				
				return;//continue;
			}
			
			sqlite3_stmt *statement = [viewConnection pageTable_updateLinkForPageKeyStatement];
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
		
		[viewConnection->dirtyMaps enumerateKeysAndObjectsUsingBlock:^(id rowIdObj, id pageKeyObj, BOOL *stop) {
			
			int64_t rowid = [(NSNumber *)rowIdObj longLongValue];
			__unsafe_unretained NSString *pageKey = (NSString *)pageKeyObj;
			
			if ((id)pageKey == (id)[NSNull null])
			{
				sqlite3_stmt *statement = [viewConnection mapTable_removeForRowidStatement];
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
				sqlite3_stmt *statement = [viewConnection mapTable_setPageKeyForRowidStatement];
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
		
		BOOL hasDirtyPages = ([viewConnection->dirtyPages count] > 0);
		BOOL hasDirtyLinks = ([viewConnection->dirtyLinks count] > 0);
		BOOL hasDirtyMaps  = ([viewConnection->dirtyMaps  count] > 0);
		
		if (hasDirtyPages)
		{
			[pageTableTransaction modifyWithBlock:^{ @autoreleasepool {
				
				[viewConnection->dirtyPages enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop) {
					
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
				
				[viewConnection->dirtyPages enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop) {
					
					__unsafe_unretained NSString *pageKey = (NSString *)key;
					__unsafe_unretained YapDatabaseViewPage *page = (YapDatabaseViewPage *)obj;
					
					if ((id)page == (id)[NSNull null])
					{
						[pageMetadataTableTransaction removeObjectForKey:pageKey];
					}
					else
					{
						YapDatabaseViewPageMetadata *pageMetadata = nil;
						
						pageMetadata = [viewConnection->dirtyLinks objectForKey:pageKey];
						if (pageMetadata == nil)
						{
							NSString *group = [viewConnection->state groupForPageKey:pageKey];
							NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
							
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
				
				[viewConnection->dirtyLinks enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop) {
					
					__unsafe_unretained NSString *pageKey = (NSString *)key;
					__unsafe_unretained YapDatabaseViewPageMetadata *pageMetadata = (YapDatabaseViewPageMetadata *)obj;
					
					if ([viewConnection->dirtyPages objectForKey:pageKey])
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
				
				[viewConnection->dirtyMaps enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop) {
					
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
	
	[viewConnection postCommitCleanup];
	
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	viewConnection = nil;      // Do not remove !
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
	
	[viewConnection postRollbackCleanup];
	
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	viewConnection = nil;      // Do not remove !
	databaseTransaction = nil; // Do not remove !
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)_handleChangeWithRowid:(int64_t)rowid
                 collectionKey:(YapCollectionKey *)collectionKey
                        object:(id)object
                      metadata:(id)metadata
                      grouping:(YapDatabaseViewGrouping *)grouping
                       sorting:(YapDatabaseViewSorting *)sorting
            blockInvokeBitMask:(YapDatabaseBlockInvoke)blockInvokeBitMask
                changesBitMask:(YapDatabaseViewChangesBitMask)changesBitMask
                      isInsert:(BOOL)isInsert
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseView *view = viewConnection->view;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	// Should we ignore the row based on the allowedCollections ?
	
	YapWhitelistBlacklist *allowedCollections = view->options.allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Determine if the grouping or sorting may have changed
	
	BOOL groupingMayHaveChanged;
	BOOL sortingMayHaveChanged;
	
	if (isInsert)
	{
		groupingMayHaveChanged = YES;
		sortingMayHaveChanged  = YES;
	}
	else
	{
		groupingMayHaveChanged = (grouping->blockInvokeOptions & blockInvokeBitMask);
		sortingMayHaveChanged  = (sorting->blockInvokeOptions & blockInvokeBitMask);
	}
	
	NSString *group = nil;
	
	if (!groupingMayHaveChanged && !sortingMayHaveChanged)
	{
		// Nothing left to do.
		// Neither the groupingBlock or sortingBlock need to be run.
		
		NSString *pageKey = [self pageKeyForRowid:rowid];
		group = [viewConnection->state groupForPageKey:pageKey];
		
		if (group)
		{
			NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
			
			[viewConnection->changes addObject:
			  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
			                                        inGroup:group
			                                        atIndex:existingIndex
			                                    withChanges:changesBitMask]];
		}
		
		return;
	}
	
	// Invoke the grouping block to find out if the row should be included in the view.
	
	if (groupingMayHaveChanged)
	{
		if (grouping->blockType == YapDatabaseBlockTypeWithKey)
		{
			__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
			    (YapDatabaseViewGroupingWithKeyBlock)grouping->block;
			
			group = groupingBlock(databaseTransaction, collection, key);
			group = [group copy]; // mutable string protection
		}
		else if (grouping->blockType == YapDatabaseBlockTypeWithObject)
		{
			__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			    (YapDatabaseViewGroupingWithObjectBlock)grouping->block;
			
			group = groupingBlock(databaseTransaction, collection, key, object);
			group = [group copy]; // mutable string protection
		}
		else if (grouping->blockType == YapDatabaseBlockTypeWithMetadata)
		{
			__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			    (YapDatabaseViewGroupingWithMetadataBlock)grouping->block;
			
			group = groupingBlock(databaseTransaction, collection, key, metadata);
			group = [group copy]; // mutable string protection
		}
		else
		{
			__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			    (YapDatabaseViewGroupingWithRowBlock)grouping->block;
			
			group = groupingBlock(databaseTransaction, collection, key, object, metadata);
			group = [group copy]; // mutable string protection
		}
		
		if (group == nil)
		{
			// Remove row from view (if needed).
			
			if (!isInsert)
			{
				[self removeRowid:rowid collectionKey:collectionKey];
			}
			
			return;
		}
		
		if (!sortingMayHaveChanged)
		{
			NSString *pageKey = [self pageKeyForRowid:rowid];
			NSString *existingGroup = [viewConnection->state groupForPageKey:pageKey];
			
			if ([group isEqualToString:existingGroup])
			{
				NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
				
				[viewConnection->changes addObject:
				  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
				                                        inGroup:group
				                                        atIndex:existingIndex
				                                    withChanges:changesBitMask]];
				
				return;
			}
		}
	}
	else
	{
		// Grouping hasn't changed.
		// Fetch the current group.
		
		NSString *pageKey = [self pageKeyForRowid:rowid];
		group = [viewConnection->state groupForPageKey:pageKey];
		
		if (group == nil)
		{
			// Nothing to do.
			// The row wasn't previously in the view, and still isn't in the view.
			
			return;
		}
	}
	
	// Add row to the view or update its position.
	// This was an update operation, so the row may have previously been in the view.
	
	[self insertRowid:rowid
	    collectionKey:collectionKey
	           object:object
	         metadata:metadata
	          inGroup:group
	      withChanges:changesBitMask
	            isNew:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleInsertObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeOnInsertOnly;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:YES];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleUpdateObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectModified |
	                                            YapDatabaseBlockInvokeIfMetadataModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	BOOL groupingMayHaveChanged = (grouping->blockInvokeOptions & blockInvokeBitMask);
	BOOL sortingMayHaveChanged  = (sorting->blockInvokeOptions  & blockInvokeBitMask);
	
	BOOL groupingNeedsMetadata = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
	BOOL sortingNeedsMetadata  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
	
	id metadata = nil;
	if ((groupingMayHaveChanged && groupingNeedsMetadata) || (sortingMayHaveChanged && sortingNeedsMetadata))
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfMetadataModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	BOOL groupingMayHaveChanged = (grouping->blockInvokeOptions & blockInvokeBitMask);
	BOOL sortingMayHaveChanged  = (sorting->blockInvokeOptions  & blockInvokeBitMask);
	
	BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
	BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
	
	id object = nil;
	if ((groupingMayHaveChanged && groupingNeedsObject) || (sortingMayHaveChanged && sortingNeedsObject))
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchObjectForKey:inCollection:collection:
**/
- (void)handleTouchObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	BOOL groupingMayHaveChanged = (grouping->blockInvokeOptions & blockInvokeBitMask);
	BOOL sortingMayHaveChanged  = (sorting->blockInvokeOptions  & blockInvokeBitMask);
	
	BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
	BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
	
	BOOL groupingNeedsMetadata = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
	BOOL sortingNeedsMetadata  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
	
	id object = nil;
	if ((groupingMayHaveChanged && groupingNeedsObject) || (sortingMayHaveChanged && sortingNeedsObject))
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if ((groupingMayHaveChanged && groupingNeedsMetadata) || (sortingMayHaveChanged && sortingNeedsMetadata))
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchMetadataForKey:inCollection:
**/
- (void)handleTouchMetadataForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfMetadataTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	BOOL groupingMayHaveChanged = (grouping->blockInvokeOptions & blockInvokeBitMask);
	BOOL sortingMayHaveChanged  = (sorting->blockInvokeOptions  & blockInvokeBitMask);
	
	BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
	BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
	
	BOOL groupingNeedsMetadata = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
	BOOL sortingNeedsMetadata  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
	
	id object = nil;
	if ((groupingMayHaveChanged && groupingNeedsObject) || (sortingMayHaveChanged && sortingNeedsObject))
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if ((groupingMayHaveChanged && groupingNeedsMetadata) || (sortingMayHaveChanged && sortingNeedsMetadata))
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchRowForKey:inCollection:
**/
- (void)handleTouchRowForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	YapDatabaseBlockInvoke blockInvokeBitMask =
	  YapDatabaseBlockInvokeIfObjectTouched | YapDatabaseBlockInvokeIfMetadataTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	BOOL groupingMayHaveChanged = (grouping->blockInvokeOptions & blockInvokeBitMask);
	BOOL sortingMayHaveChanged  = (sorting->blockInvokeOptions  & blockInvokeBitMask);
	
	BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
	BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
	
	BOOL groupingNeedsMetadata = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
	BOOL sortingNeedsMetadata  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
	
	id object = nil;
	if ((groupingMayHaveChanged && groupingNeedsObject) || (sortingMayHaveChanged && sortingNeedsObject))
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if ((groupingMayHaveChanged && groupingNeedsMetadata) || (sortingMayHaveChanged && sortingNeedsMetadata))
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	[self removeRowid:rowid collectionKey:collectionKey];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	YDBLogAutoTrace();
	
	NSUInteger count = [keys count];
	NSMutableDictionary *keyMappings = [NSMutableDictionary dictionaryWithCapacity:count];
	
	for (NSUInteger i = 0; i < count; i++)
	{
		NSNumber *rowid = [rowids objectAtIndex:i];
		NSString *key = [keys objectAtIndex:i];
		
		YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		[keyMappings setObject:collectionKey forKey:rowid];
	}
	
	NSArray *validRowids = rowids;
	NSDictionary *output = [self pageKeysForRowids:&validRowids withKeyMappings:keyMappings];
	
	// output.key = pageKey
	// output.value = NSDictionary with keyMappings for page
	
	[output enumerateKeysAndObjectsUsingBlock:^(id pageKeyObj, id dictObj, BOOL __unused *stop) {
		
		__unsafe_unretained NSString *pageKey = (NSString *)pageKeyObj;
		__unsafe_unretained NSDictionary *keyMappingsForPage = (NSDictionary *)dictObj;
		
		NSString *group = [viewConnection->state groupForPageKey:pageKey];
		NSAssert(group != nil, @"Unknown group for pageKey: %@", pageKey);
		
		[self removeRowidsWithKeyMappings:keyMappingsForPage pageKey:pageKey inGroup:group];
	}];
	
	// Subclass hook
	
	NSMutableArray *validCollectionKeys = [NSMutableArray arrayWithCapacity:[validRowids count]];
	for (NSNumber *rowid in validRowids)
	{
		[validCollectionKeys addObject:[keyMappings objectForKey:rowid]];
	}
	
	[self didRemoveRowids:validRowids collectionKeys:validCollectionKeys];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveAllObjectsInAllCollections
{
	YDBLogAutoTrace();
	
	[self removeAllRowids];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API - Groups
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)numberOfGroups
{
	// Note: We don't remove pages or groups until flushPendingChangesToExtensionTables.
	// This allows us to recycle pages whenever possible, which reduces disk IO during the commit.
	
	__block NSUInteger count = 0;
	
	[viewConnection->state enumerateWithBlock:^(NSString __unused *group, NSArray *pagesMetadataForGroup, BOOL __unused *stop) {
		
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
	
	NSMutableArray *allGroups = [NSMutableArray arrayWithCapacity:[viewConnection->state numberOfGroups]];
	
	[viewConnection->state enumerateWithBlock:^(NSString *group, NSArray *pagesMetadataForGroup, BOOL __unused *stop) {
		
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
	
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	
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
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
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
	
	[viewConnection->state enumerateWithBlock:^(NSString __unused *group, NSArray *pagesMetadataForGroup, BOOL __unused *stop) {
		
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
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	
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
	
	[viewConnection->state enumerateWithBlock:^(NSString __unused *group, NSArray *pagesMetadataForGroup, BOOL *stop) {
		
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
		return [viewConnection->state groupForPageKey:[self pageKeyForRowid:rowid]];
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
			
			group = [viewConnection->state groupForPageKey:pageKey];
		
			// Calculate the offset of the corresponding page within the group.
			
			NSUInteger pageOffset = 0;
			NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
			
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
#pragma mark Public API - Finding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for extensive documentation for this method.
**/
- (NSRange)findRangeInGroup:(NSString *)group using:(YapDatabaseViewFind *)find quitAfterOne:(BOOL)quitAfterOne
{
	if (group == nil || find == NULL)
	{
		return NSMakeRange(NSNotFound, 0);
	}
	
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	NSUInteger count = 0;
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		count += pageMetadata->count;
	}
	
	if (count == 0)
	{
		return NSMakeRange(NSNotFound, 0);
	}
	
	// Helper block:
	//
	// Finds the rowid for a given index (within the view.group).
	
	int64_t (^findRowid)(NSUInteger) = ^int64_t (NSUInteger index){
		
		NSUInteger pageOffset = 0;
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
		{
			if ((index < (pageOffset + pageMetadata->count)) && (pageMetadata->count > 0))
			{
				YapDatabaseViewPage *page = [self pageForPageKey:pageMetadata->pageKey];
				
				return [page rowidAtIndex:(index - pageOffset)];
			}
			else
			{
				pageOffset += pageMetadata->count;
			}
		}
		
		NSAssert(NO, @"index(%lu) not found !!!", (unsigned long)index);
		return (int64_t)0;
	};
	
	// Helper block:
	//
	// Executes the findBlock against the row represented by the given index (within the view.group).
	
	NSComparisonResult (^compare)(NSUInteger);
		
	switch (find.findBlockType)
	{
		case YapDatabaseBlockTypeWithKey :
		{
			__unsafe_unretained YapDatabaseViewFindWithKeyBlock findBlock =
			  (YapDatabaseViewFindWithKeyBlock)find.findBlock;
			
			compare = ^NSComparisonResult (NSUInteger index){
				
				int64_t rowid = findRowid(index);
				
				YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
				
				return findBlock(ck.collection, ck.key);
			};
			
			break;
		}
		case YapDatabaseBlockTypeWithObject :
		{
			__unsafe_unretained YapDatabaseViewFindWithObjectBlock findBlock =
			    (YapDatabaseViewFindWithObjectBlock)find.findBlock;
			
			compare = ^NSComparisonResult (NSUInteger index){
				
				int64_t rowid = findRowid(index);
				
				YapCollectionKey *ck = nil;
				id object = nil;
				[databaseTransaction getCollectionKey:&ck object:&object forRowid:rowid];
				
				return findBlock(ck.collection, ck.key, object);
			};
			
			break;
		}
		case YapDatabaseBlockTypeWithMetadata :
		{
			__unsafe_unretained YapDatabaseViewFindWithMetadataBlock findBlock =
			    (YapDatabaseViewFindWithMetadataBlock)find.findBlock;
			
			compare = ^NSComparisonResult (NSUInteger index){
				
				int64_t rowid = findRowid(index);
				
				YapCollectionKey *ck = nil;
				id metadata = nil;
				[databaseTransaction getCollectionKey:&ck metadata:&metadata forRowid:rowid];
				
				return findBlock(ck.collection, ck.key, metadata);
			};
			
			break;
		}
		default :
		{
			__unsafe_unretained YapDatabaseViewFindWithRowBlock findBlock =
			    (YapDatabaseViewFindWithRowBlock)find.findBlock;
			
			compare = ^NSComparisonResult (NSUInteger index){
				
				int64_t rowid = findRowid(index);
				
				YapCollectionKey *ck = nil;
				id object = nil;
				id metadata = nil;
				[databaseTransaction getCollectionKey:&ck object:&object metadata:&metadata forRowid:rowid];
				
				return findBlock(ck.collection, ck.key, object, metadata);
			};
		}
		
	} // end switch (blockType)
		
	
	NSUInteger loopCount = 0;
	
	// Find first match (first to return NSOrderedSame)
	
	NSUInteger mMin = 0;
	NSUInteger mMax = count;
	NSUInteger mMid = 0;
	
	BOOL found = NO;
	
	while (mMin < mMax && !found)
	{
		mMid = (mMin + mMax) / 2;
		
		NSComparisonResult cmp = compare(mMid);
		
		if (cmp == NSOrderedDescending)      // Descending => value is greater than desired range
			mMax = mMid;
		else if (cmp == NSOrderedAscending)  // Ascending => value is less than desired range
			mMin = mMid + 1;
		else
			found = YES;
		
		loopCount++;
	}
	
	if (!found)
	{
		return NSMakeRange(NSNotFound, 0);
	}
	
	if (quitAfterOne)
	{
		return NSMakeRange(mMid, 1);
	}
	
	// Find start of range
	
	NSUInteger sMin = mMin;
	NSUInteger sMax = mMid;
	NSUInteger sMid;
	
	while (sMin < sMax)
	{
		sMid = (sMin + sMax) / 2;
		
		NSComparisonResult cmp = compare(sMid);
		
		if (cmp == NSOrderedAscending) // Ascending => value is less than desired range
			sMin = sMid + 1;
		else
			sMax = sMid;
		
		loopCount++;
	}
	
	// Find end of range
	
	NSUInteger eMin = mMid;
	NSUInteger eMax = mMax;
	NSUInteger eMid;
	
	while (eMin < eMax)
	{
		eMid = (eMin + eMax) / 2;
		
		NSComparisonResult cmp = compare(eMid);
		
		if (cmp == NSOrderedDescending) // Descending => value is greater than desired range
			eMax = eMid;
		else
			eMin = eMid + 1;
		
		loopCount++;
	}
	
	YDBLogVerbose(@"Find range in group(%@) took %lu comparisons", group, (unsigned long)loopCount);
	
	return NSMakeRange(sMin, (eMax - sMin));
}

/**
 * See header file for extensive documentation for this method.
**/
- (NSRange)findRangeInGroup:(NSString *)group using:(YapDatabaseViewFind *)find
{
	return [self findRangeInGroup:group using:find quitAfterOne:NO];
}

/**
 * This method uses a binary search algorithm to find an item within the view that matches the given criteria.
 * 
 * It works similarly to findRangeInGroup:using:, but immediately returns once a single match has been found.
 * This makes it more efficient when you only care about the existence of a match,
 * or you know there will never be more than a single match.
 *
 * See the documentation for findRangeInGroup:using: for more information.
 * @see findRangeInGroup:using:
 *
 * @return
 *   If found, the index of the first match discovered.
 *   That is, an item where the find block returned NSOrderedSame.
 *   If not found, returns NSNotFound.
**/
- (NSUInteger)findFirstMatchInGroup:(NSString *)group using:(YapDatabaseViewFind *)find
{
	NSRange range = [self findRangeInGroup:group using:find quitAfterOne:YES];
	
	return range.location;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API - Enumerating
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)enumerateGroupsUsingBlock:(void (^)(NSString *group, BOOL *stop))block
{
	if (block == NULL) return;
	
	[viewConnection->mutatedGroups removeAllObjects]; // mutation during enumeration protection
	
	__block BOOL stop = NO;
	
	[viewConnection->state enumerateGroupsWithBlock:^(NSString *group, BOOL *innerStop) {
		
		block(group, &stop);
		
		if (stop || [viewConnection->mutatedGroups count] > 0) *innerStop = YES;
	}];
	
	if (!stop && [viewConnection->mutatedGroups count] > 0)
	{
		NSString *anyMutatedGroup = [viewConnection->mutatedGroups anyObject];
		
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
	
	[viewConnection->mutatedGroups removeObject:group]; // mutation during enumeration protection
	
	__block BOOL stop = NO;
	
	NSUInteger pageOffset = 0;
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	
	for (YapDatabaseViewPageMetadata *pageMetadata in pagesMetadataForGroup)
	{
		YapDatabaseViewPage *page = [self pageForPageKey:pageMetadata->pageKey];
		
		[page enumerateRowidsUsingBlock:^(int64_t rowid, NSUInteger idx, BOOL *innerStop) {
			
			block(rowid, pageOffset+idx, &stop);
			
			if (stop || [viewConnection->mutatedGroups containsObject:group]) *innerStop = YES;
		}];
		
		if (stop || [viewConnection->mutatedGroups containsObject:group]) break;
		
		pageOffset += pageMetadata->count;
	}
	
	if (!stop && [viewConnection->mutatedGroups containsObject:group])
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
	
	[viewConnection->mutatedGroups removeObject:group]; // mutation during enumeration protection
	
	__block BOOL stop = NO;
	__block NSUInteger index;
	
	if (forwardEnumeration)
		index = 0;
	else
		index = [self numberOfItemsInGroup:group] - 1;
	
	NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
	
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
			
			if (stop || [viewConnection->mutatedGroups containsObject:group]) *innerStop = YES;
		}];
		
		if (stop || [viewConnection->mutatedGroups containsObject:group]) *outerStop = YES;
	}];
	
	if (!stop && [viewConnection->mutatedGroups containsObject:group])
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
	
	[viewConnection->mutatedGroups removeObject:group]; // mutation during enumeration protection
	
	__block BOOL stop = NO;
	__block NSUInteger keysLeft = range.length;
	
	if ((options & NSEnumerationReverse) == 0)
	{
		// Forward enumeration (optimized)
		
		NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
		
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
					
					if (stop || [viewConnection->mutatedGroups containsObject:group]) *innerStop = YES;
				}];
				
				if (stop || [viewConnection->mutatedGroups containsObject:group]) break;
				
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
		
		NSArray *pagesMetadataForGroup = [viewConnection->state pagesMetadataForGroup:group];
		
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
					
					if (stop || [viewConnection->mutatedGroups containsObject:group]) *innerStop = YES;
				}];
				
				if (stop || [viewConnection->mutatedGroups containsObject:group]) *outerStop = YES;
				
				keysLeft -= enumRange.length;
			}
			else if (startedRange && (pageRange.length > 0))
			{
				// We've completed the range
				*outerStop = YES;
			}
			
		}];
	}
	
	if (!stop && [viewConnection->mutatedGroups containsObject:group])
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
#pragma mark Subclass Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses may override these methods as an easy hook for concrete changes.
 *
 * That is, the handleX methods are hooks from the main database,
 * but they don't necessarily reflect changes to this view.
 * For example, handleRemoveObjectForCollectionKey:: notifies us that something from the main database was removed,
 * but that item may or may not have been in our view. In contrast, these hook methods are only invoked
 * when something is added or removed from our view.
**/

/**
 * Invoked when an item is added to the view.
**/
- (void)didInsertRowid:(int64_t __unused)rowid collectionKey:(YapCollectionKey __unused *)collectionKey
{
	// Subclasses may override me.
	// Default implementation does nothing.
}

/**
 * Invoked when an item is removed from the view.
 *
 * This method is only invoked for "single remove" operations.
 * That is, when an individual item is removed from the view as a single operation.
 * For larger (non-single) remove operations, the other hook methods are used.
**/
- (void)didRemoveRowid:(int64_t __unused)rowid collectionKey:(YapCollectionKey __unused *)collectionKey
{
	// Subclasses may override me.
	// Default implementation does nothing.
}

/**
 * Invoked when a number of items are removed from the view in a single operation.
 * 
 * Important #1:
 *   The collectionKeys parameter is not always available.
 *   If the collectionKeys parameter is non-nil, then it is correct.
 *   Otherwise it will be nil because the opertion didn't have access to the information, and didn't need it.
 *   Thus, if needed, you'll need to manually fetch the corresponding list of collectionKeys.
 * 
 * Important #2:
 *   The given rowids array is unbounded.
 *   That is, normally hook methods are limited by SQLITE_LIMIT_VARIABLE_NUMBER.
 *   But that is ** NOT ** the case here.
 *   So you'll be required to check for this, and split your queries accordingly.
**/
- (void)didRemoveRowids:(NSArray __unused *)rowids collectionKeys:(NSArray __unused *)collectionKeys
{
	// Subclasses may override me.
	// Default implementation does nothing.
}

/**
 * Invoked when the view is cleared.
**/
- (void)didRemoveAllRowids
{
	// Subclasses may override me.
	// Default implementation does nothing.
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
		
		[self handleTouchObjectForCollectionKey:collectionKey withRowid:rowid];
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
		
		[self handleTouchMetadataForCollectionKey:collectionKey withRowid:rowid];
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
		
		[self handleTouchRowForCollectionKey:collectionKey withRowid:rowid];
	}
}

/**
 * This method allows you to change the grouping and/or sorting on-the-fly.
 * 
 * Note: You must pass a different versionTag, or this method does nothing.
**/
- (void)setGrouping:(YapDatabaseViewGrouping *)grouping
            sorting:(YapDatabaseViewSorting *)sorting
         versionTag:(NSString *)inVersionTag
{
	YDBLogAutoTrace();
	
	NSAssert(grouping != nil, @"Invalid parameter: grouping == nil");
	NSAssert(sorting != nil, @"Invalid parameter: sorting == nil");
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	NSString *newVersionTag = inVersionTag ? [inVersionTag copy] : @"";
	
	if ([[self versionTag] isEqualToString:newVersionTag])
	{
		YDBLogWarn(@"%@ - versionTag didn't change, so not updating view", THIS_METHOD);
		return;
	}
	
	[viewConnection setGrouping:grouping
	                    sorting:sorting
	                 versionTag:newVersionTag];
	
	[self repopulateView];
	
	[self setStringValue:newVersionTag
	     forExtensionKey:ext_key_versionTag
	          persistent:[self isPersistentView]];
	
	// Notify any extensions dependent upon this one that we repopulated.
	
	NSString *registeredName = [self registeredName];
	NSDictionary *extensionDependencies = databaseTransaction->connection->extensionDependencies;
	
	[extensionDependencies enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop){
		
		__unsafe_unretained NSString *extName = (NSString *)key;
		__unsafe_unretained NSSet *extDependencies = (NSSet *)obj;
		
		if ([extDependencies containsObject:registeredName])
		{
			YapDatabaseExtensionTransaction *extTransaction = [databaseTransaction ext:extName];
			
			if ([extTransaction respondsToSelector:@selector(view:didRepopulateWithFlags:)])
			{
				int flags = YDB_GroupingBlockChanged | YDB_SortingBlockChanged;
				[(id <YapDatabaseViewDependency>)extTransaction view:registeredName didRepopulateWithFlags:flags];
			}
		}
	}];
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
	
#if TARGET_OS_IPHONE
	NSUInteger section = indexPath.section;
	NSUInteger row = indexPath.row;
#else
	NSUInteger section = [indexPath indexAtPosition:0];
	NSUInteger row = [indexPath indexAtPosition:1];
#endif
	
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
	
#if TARGET_OS_IPHONE
	NSUInteger section = indexPath.section;
	NSUInteger row = indexPath.row;
#else
	NSUInteger section = [indexPath indexAtPosition:0];
	NSUInteger row = [indexPath indexAtPosition:1];
#endif
	
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
	
#if TARGET_OS_IPHONE
	NSUInteger section = indexPath.section;
	NSUInteger row = indexPath.row;
#else
	NSUInteger section = [indexPath indexAtPosition:0];
	NSUInteger row = [indexPath indexAtPosition:1];
#endif
	
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
