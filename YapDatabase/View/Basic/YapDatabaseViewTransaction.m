#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseViewPrivate.h"
#import "YapDatabaseViewInternal.h"
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

#define YDB_VIEW_TYPE_KEY  0
#define YDB_VIEW_TYPE_PAGE 1

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
 * Furthermore, sections are supported, which means there may be multiple ordered arrays of keys, one per section.
 * 
 * Conceptually this is a very simple concept.
 * But obviously there are memory and performance requirements the add complexity.
 * 
 * One possibility is to use a database table with fields for 'section', 'key', and 'index'.
 * However, this is a performance nightmare.
 * Inserting a key into the beginning of the order causes every other row in the section to be
 * updated in order to increment the 'index' value.
 * 
 * Instead we take the array and split it into pages.
**/
@implementation YapDatabaseViewTransaction

- (BOOL)open
{
	NSString *tableName = [abstractViewConnection->abstractView tableName];
	sqlite3 *db = databaseTransaction->abstractConnection->db;
	
	NSString *selectStatement = [NSString stringWithFormat:
	    @"SELECT \"key\", \"metadata\" FROM \"%@\" WHERE type = %d;", tableName, YDB_VIEW_TYPE_PAGE];
	
	sqlite3_stmt *enumerateStatement;
	
	int status = sqlite3_prepare_v2(db, [selectStatement UTF8String], -1, &enumerateStatement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error creating 'enumerateAllStatement': %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	// Enumerate over the page rows in the database, and populate our data structure.
	// Each row gives us the following fields:
	//
	// - section
	// - key
	// - nextKey
	//
	// From this information we need to piece together the keyPagesDict:
	// - key = section
	// - value = ordered array of YapDatabaseViewKeyPageMetadata objects
	//
	// In order to stitch everything together we make a temporary dictionary with the reverse link.
	// For example:
	//
	// pageA.nextPage = pageB  =>      B ->A
	// pageB.nextPage = pageC  =>      C -> B
	// pageC.nextPage = nil    => NSNull -> C
	//
	// After the enumeration is complete, we can easily stitch together the order by
	// working backwards from the last page.
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	NSMutableDictionary *sectionKeyPageDict = [[NSMutableDictionary alloc] init];
	NSMutableDictionary *sectionKeyOrderDict = [[NSMutableDictionary alloc] init];
	
	while (sqlite3_step(enumerateStatement) == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(enumerateStatement, 0);
		int textSize = sqlite3_column_bytes(enumerateStatement, 0);
		
		const void *blob = sqlite3_column_blob(enumerateStatement, 1);
		int blobSize = sqlite3_column_bytes(enumerateStatement, 1);
		
		NSString *pageKey = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
		
		id metadata = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		
		if ([metadata isKindOfClass:[YapDatabaseViewPageMetadata class]])
		{
			YapDatabaseViewPageMetadata *pageMetadata = (YapDatabaseViewPageMetadata *)metadata;
			pageMetadata->pageKey = pageKey;
			
			NSNumber *section = @(pageMetadata->section);
			
			NSMutableDictionary *keyPageDict = [sectionKeyPageDict objectForKey:section];
			if (keyPageDict == nil)
			{
				keyPageDict = [[NSMutableDictionary alloc] init];
				[sectionKeyPageDict setObject:keyPageDict forKey:section];
			}
			
			NSMutableDictionary *keyOrderDict = [sectionKeyOrderDict objectForKey:section];
			if (keyOrderDict == nil)
			{
				keyOrderDict = [[NSMutableDictionary alloc] init];
				[sectionKeyOrderDict setObject:keyOrderDict forKey:section];
			}
			
			[keyPageDict setObject:pageMetadata forKey:pageKey];
			
			if (pageMetadata->nextPageKey)
				[keyOrderDict setObject:pageMetadata->pageKey forKey:pageMetadata->nextPageKey];
			else
				[keyOrderDict setObject:pageMetadata->pageKey forKey:[NSNull null]];
		}
		else
		{
			YDBLogWarn(@"%@: While opening view(%@) encountered unknown metadata class: %@",
					   THIS_FILE, [self registeredViewName], [metadata class]);
		}
	}
	
	__block BOOL error = (status != SQLITE_DONE);
	
	if (!error)
	{
		// Initialize ivars in viewConnection.
		// We try not to do this before we know the table exists.
		
		viewConnection->sectionPagesDict = [[NSMutableDictionary alloc] init];
		
		viewConnection->dirtyKeys = [[NSMutableDictionary alloc] init];
		viewConnection->dirtyPages = [[NSMutableDictionary alloc] init];
		
		// Enumerate over each section
		
		[sectionKeyOrderDict enumerateKeysAndObjectsUsingBlock:^(id _section, id _keyOrderDict, BOOL *stop) {
			
			NSNumber *section = (NSNumber *)_section;
			NSMutableDictionary *keyOrderDict = (NSMutableDictionary *)_keyOrderDict;
			
			NSMutableDictionary *keyPageDict = [sectionKeyPageDict objectForKey:section];
			
			NSMutableArray *pagesForSection = [[NSMutableArray alloc] initWithCapacity:[keyPageDict count]];
			[viewConnection->sectionPagesDict setObject:pagesForSection forKey:section];
			
			// Work backwards to stitch together the pages for this section.
			//
			// NSNull -> lastPageKey
			// lastPageKey -> secondToLastPageKey
			// ...
			// secondPageKey -> firstPageKey
			//
			// And from the keys, we can get the actual page using the keyPageDict.
			
			NSString *key = [keyOrderDict objectForKey:[NSNull null]];
			while (key)
			{
				YapDatabaseViewPageMetadata *pageMetadata = [keyPageDict objectForKey:key];
				
				[pagesForSection insertObject:pageMetadata atIndex:0];
				
				key = [keyOrderDict objectForKey:key];
			}
			
			// Validate data for this section
			
			if ([pagesForSection count] < [keyOrderDict count])
			{
				YDBLogError(@"%@: Error opening view(%@): Missing key page(s) in section(%lu)",
				            THIS_FILE, [self registeredViewName], (unsigned long)section);
				
				error = YES;
			}
		}];
	}
	
	// Validate data
	
	if (error)
	{
		// The isOpen method of YapDatabaseViewConnection inspects sectionPagesDict.
		// So if there was an error opening the view, we need to reset this variable to nil.
		
		viewConnection->sectionPagesDict = nil;
		
		viewConnection->dirtyKeys = nil;
		viewConnection->dirtyPages = nil;
	}
	
	sqlite3_finalize(enumerateStatement);
	return !error;
}

- (BOOL)createTable
{
	NSAssert(databaseTransaction->isReadWriteTransaction, @"Attempt to create a view outside a readwrite transaction");
	
	NSString *tableName = [abstractViewConnection->abstractView tableName];
	sqlite3 *db = databaseTransaction->abstractConnection->db;
	
	NSString *statement = [NSString stringWithFormat:
	    @"CREATE TABLE IF NOT EXISTS \"%@\""
	    @" (\"type\" INTEGER NOT NULL, "
	    @"  \"key\" CHAR NOT NULL, "
	    @"  \"data\" BLOB, "
	    @"  \"metadata\" BLOB, "
	    @"  PRIMARY KEY (\"type\", \"key\")"
	    @" );", tableName];
	
	int status = sqlite3_exec(db, [statement UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Failed creating table for view(%@): %d %s",
		            [abstractViewConnection->abstractView registeredName], status, sqlite3_errmsg(db));
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

- (NSString *)pageKeyForKey:(NSString *)key
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	NSString *pageKey = nil;
	
	// Check dirty cache & clean cache
	
	pageKey = [viewConnection->dirtyKeys objectForKey:key];
	if (pageKey) return pageKey;
	
	pageKey = [viewConnection->keyCache objectForKey:key];
	if (pageKey) return pageKey;
	
	// Otherwise pull from the database
	
	sqlite3_stmt *statement = [viewConnection getDataForKeyStatement];
	if (statement == NULL)
		return nil;
	
	// SELECT data FROM 'tablename' WHERE type = ? AND key = ? ;
	
	sqlite3_bind_int(statement, 1, YDB_VIEW_TYPE_KEY);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
		
		id obj = [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil];
		
		if ([obj isKindOfClass:[NSString class]])
		{
			pageKey = (NSString *)obj;
		}
		else
		{
			YDBLogError(@"%@: Found invalid pageKey data with class: %@", THIS_FILE, [obj class]);
		}
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getDataForKeyStatement': %d %s, key(%@)",
					status, sqlite3_errmsg(databaseTransaction->abstractConnection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	// Store in cache if found
	if (pageKey)
		[viewConnection->keyCache setObject:pageKey forKey:key];
	
	return pageKey;
}

- (NSMutableArray *)pageForPageKey:(NSString *)key
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	NSMutableArray *page = nil;
	
	// Check dirty cache & clean cache
	
	page = [viewConnection->dirtyPages objectForKey:key];
	if (page) return page;
	
	page = [viewConnection->pageCache objectForKey:key];
	if (page) return page;
	
	// Otherwise pull from the database
	
	sqlite3_stmt *statement = [viewConnection getDataForKeyStatement];
	if (statement == NULL)
		return nil;
	
	// SELECT data FROM 'database' WHERE type = ? AND key = ? ;
	
	sqlite3_bind_int(statement, 1, YDB_VIEW_TYPE_PAGE);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
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
			YDBLogError(@"%@: Found invalid page data with class: %@", THIS_FILE, [obj class]);
		}
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getDataForKeyStatement': %d %s, key(%@)",
					status, sqlite3_errmsg(databaseTransaction->abstractConnection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	// Store in cache if found
	if (page)
		[viewConnection->pageCache setObject:page forKey:key];
	
	return page;
}

- (void)removeKey:(NSString *)key
{
	NSString *pageKey = [self pageKeyForKey:key];
	if (pageKey == nil) return;
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	[viewConnection->sectionPagesDict enumerateKeysAndObjectsUsingBlock:^(id _key, id _object, BOOL *stop) {
		
		NSNumber *section = (NSNumber *)_key;
		NSMutableArray *pagesInSection = (NSMutableArray *)_object;
		
		for (YapDatabaseViewPageMetadata *pageMetadata in pagesInSection)
		{
			if ([pageMetadata->pageKey isEqualToString:pageKey])
			{
				// Found it
			}
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapAbstractDatabaseViewKeyValueTransaction
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)handleSetObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	__unsafe_unretained YapDatabaseView *view = (YapDatabaseView *)(viewConnection->abstractView);
	
	// Invoke the filter block and find out if the object should be included in the view.
	// And if so, what section is it in?
	
	NSUInteger section = 0;
	BOOL isInView;
	
	if (view->filterBlockType == YapDatabaseViewBlockTypeWithObject)
	{
		YapDatabaseViewFilterWithObjectBlock filterBlock = (YapDatabaseViewFilterWithObjectBlock)view->filterBlock;
		isInView = filterBlock(key, object, &section);
	}
	else if (view->filterBlockType == YapDatabaseViewBlockTypeWithMetadata)
	{
		YapDatabaseViewFilterWithMetadataBlock filterBlock = (YapDatabaseViewFilterWithMetadataBlock)view->filterBlock;
		isInView = filterBlock(key, metadata, &section);
	}
	else
	{
		YapDatabaseViewFilterWithBothBlock filterBlock = (YapDatabaseViewFilterWithBothBlock)view->filterBlock;
		isInView = filterBlock(key, object, metadata, &section);
	}
	
	// Figure out where the key is currently located within the view (if at all).
	
	if (!isInView)
	{
		// Remove the key from its current location.
		
		[self removeKey:key];
	}
	else if (isInView)
	{
		
		
		NSUInteger existingSection = 0;
		NSUInteger existingIndex = 0;
		
		BOOL isAlreadyInView = [self getIndex:&existingIndex section:&existingSection forKey:key];
	}
}

- (void)handleSetMetadata:(id)metadata forKey:(NSString *)key
{
	
}

- (void)handleRemoveObjectForKey:(NSString *)key
{
}

- (void)handleRemoveObjectsForKeys:(NSArray *)keys
{
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

- (NSUInteger)numberOfSections
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	return [viewConnection->keyPagesDict count];
}

- (NSUInteger)numberOfKeysInSection:(NSUInteger)sectionIndex
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	NSMutableArray *keyPagesForSection = [viewConnection->keyPagesDict objectForKey:@(sectionIndex)];
	if (keyPagesForSection == nil) {
		return 0;
	}
	
	NSUInteger count = 0;
	
	for (YapDatabaseViewKeyPageMetadata *keyPageMetadata in keyPagesForSection)
	{
		count += keyPageMetadata->count;
	}
	
	return count;
}

- (NSUInteger)numberOfKeysInAllSections
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	NSUInteger count = 0;
	
	for (NSMutableArray *keyPagesForSection in [viewConnection->keyPagesDict objectEnumerator])
	{
		for (YapDatabaseViewKeyPageMetadata *keyPageMetadata in keyPagesForSection)
		{
			count += keyPageMetadata->count;
		}
	}
	
	return count;
}

- (NSString *)keyAtIndex:(NSUInteger)keyIndex inSection:(NSUInteger)sectionIndex
{
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	NSMutableArray *keyPagesForSection = [viewConnection->keyPagesDict objectForKey:@(sectionIndex)];
	
	NSUInteger offset = 0;
	for (YapDatabaseViewKeyPageMetadata *keyPageMetadata in keyPagesForSection)
	{
		if (keyIndex < (offset + keyPageMetadata->count))
		{
			NSMutableArray *keyPage = [self keyPageForKey:keyPageMetadata->key];
			NSUInteger keyPageIndex = keyIndex - offset;
			
			if (keyPageIndex < [keyPage count])
			{
				return [keyPage objectAtIndex:keyPageIndex];
			}
			else
			{
				YDBLogWarn(@"%@: keyPage(%@) count doesn't match metadata info!", THIS_FILE, keyPageMetadata->key);
			}
		}
		else
		{
			offset += keyPageMetadata->count;
		}
	}
	
	return nil;
}

- (NSString *)keyAtIndexPath:(NSIndexPath *)indexPath
{
	return [self keyAtIndex:indexPath.row inSection:indexPath.section];
}

- (id)objectAtIndex:(NSUInteger)keyIndex inSection:(NSUInteger)sectionIndex
{
	NSString *key = [self keyAtIndex:keyIndex inSection:sectionIndex];
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

- (id)objectAtIndexPath:(NSIndexPath *)indexPath
{
	return [self objectAtIndex:indexPath.row inSection:indexPath.section];
}

- (BOOL)getIndex:(NSUInteger *)indexPtr section:(NSUInteger *)sectionPtr forKey:(NSString *)key
{
	NSUInteger keyHash = [key hash];
	
	BOOL found = 0;
	NSUInteger index = 0;
	NSUInteger section = 0;
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	for (YapDatabaseViewHashPageMetadata *hashPageMetadata in viewConnection->hashPages)
	{
		if (keyHash > hashPageMetadata->lastHash)
		{
			// The key wouldn't be in this page.
			// It would be in a later page.
			
			continue;
		}
		else if ((keyHash >= hashPageMetadata->firstHash) && (keyHash <= hashPageMetadata->lastHash))
		{
			// The key could possibly be in this page.
			
			NSMutableArray *hashPage = [self pageForKey:hashPageMetadata->key];
			if (hashPage)
			{
				index = [hashPage->keys indexOfObject:key];
				if (index != NSNotFound)
				{
					section = [[hashPage->sections objectAtIndex:index] unsignedIntegerValue];
					found = YES;
					break;
				}
			}
		}
		else
		{
			// The key wouldn't be in this page.
			// It would have been in an earlier page.
			// Thus, the key doesn't exist in the hashPages.
			
			break;
		}
	}
	
	if (found)
	{
		if (indexPtr) *indexPtr = index;
		if (sectionPtr) *sectionPtr = section;
		return YES;
	}
	else
	{
		if (indexPtr) *indexPtr = 0;
		if (sectionPtr) *sectionPtr = 0;
		return NO;
	}
}

- (NSIndexPath *)indexPathForKey:(NSString *)key
{
	NSUInteger index = 0;
	NSUInteger section = 0;
	
	if ([self getIndex:&index section:&section forKey:key]) {
		return [NSIndexPath indexPathForRow:index inSection:section];
	}
	else {
		return nil;
	}
}

@end
