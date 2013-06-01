#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewPrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapCache.h"
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


@implementation YapDatabaseViewConnection
{
	sqlite3_stmt *keyTable_getPageKeyForKeyStatement;
	sqlite3_stmt *keyTable_setPageKeyForKeyStatement;
	sqlite3_stmt *keyTable_removeForKeyStatement;
	sqlite3_stmt *keyTable_removeAllStatement;
	
	sqlite3_stmt *pageTable_getDataForPageKeyStatement;
	sqlite3_stmt *pageTable_setAllForPageKeyStatement;
	sqlite3_stmt *pageTable_setMetadataForPageKeyStatement;
	sqlite3_stmt *pageTable_removeForPageKeyStatement;
	sqlite3_stmt *pageTable_removeAllStatement;
}

- (id)initWithExtension:(YapAbstractDatabaseExtension *)inExtension
     databaseConnection:(YapAbstractDatabaseConnection *)inDatabaseConnection
{
	if ((self = [super initWithExtension:inExtension databaseConnection:inDatabaseConnection]))
	{
		keyCache = [[YapCache alloc] init];
		pageCache = [[YapCache alloc] init];
	}
	return self;
}

- (YapDatabaseView *)view
{
	return (YapDatabaseView *)extension;
}

/**
 * Required override method from YapAbstractDatabaseExtensionConnection.
**/
- (id)newTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	return [[YapDatabaseViewTransaction alloc] initWithExtensionConnection:self
	                                                   databaseTransaction:databaseTransaction];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)keyTableName
{
	return [(YapDatabaseView *)extension keyTableName];
}

- (NSString *)pageTableName
{
	return [(YapDatabaseView *)extension pageTableName];
}

- (NSMutableDictionary *)groupPagesDictDeepCopy:(NSDictionary *)inGroupPagesDict
{
	NSMutableDictionary *deepCopy = [NSMutableDictionary dictionaryWithCapacity:[inGroupPagesDict count]];
	
	[inGroupPagesDict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained NSString *group = (NSString *)key;
		__unsafe_unretained NSMutableArray *pages = (NSMutableArray *)obj;
		
		// We need a mutable copy of the pages array,
		// and we need a copy of each YapDatabaseViewPageMetadata object within the pages array.
		
		NSMutableArray *pagesDeepCopy = [[NSMutableArray alloc] initWithArray:pages copyItems:YES];
		
		[deepCopy setObject:pagesDeepCopy forKey:group];
	}];
	
	return deepCopy;
}

- (NSMutableDictionary *)dirtyPagesDeepCopy:(NSDictionary *)inDirtyPages
{
	NSMutableDictionary *deepCopy = [NSMutableDictionary dictionaryWithCapacity:[inDirtyPages count]];
	
	[inDirtyPages enumerateKeysAndObjectsUsingBlock:^(id pageKeyObj, id pageObj, BOOL *stop) {
		
		__unsafe_unretained NSString *pageKey = (NSString *)pageKeyObj;
		__unsafe_unretained NSMutableArray *page = (NSMutableArray *)pageObj;
		
		// We need a mutable copy of the page array,
		// but we don't have to copy all the immutable keys within the page.
		
		NSMutableArray *pageDeepCopy = [[NSMutableArray alloc] initWithArray:page copyItems:NO];
		
		[deepCopy setObject:pageDeepCopy forKey:pageKey];
	}];
	
	return deepCopy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	
	groupPagesDict = nil;
	pageKeyGroupDict = nil;
	
	[keyCache removeAllObjects];
	[pageCache removeAllObjects];
	
	[dirtyKeys removeAllObjects];
	[dirtyPages removeAllObjects];
	[dirtyMetadata removeAllObjects];
	reset = NO;
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
{
	YDBLogAutoTrace();
	
	NSMutableDictionary *internalChangeset = nil;
	NSMutableDictionary *externalChangeset = nil;
	
	if ([dirtyKeys count] || [dirtyPages count] || [dirtyMetadata count] || reset)
	{
		internalChangeset = [NSMutableDictionary dictionaryWithCapacity:5];
		
		if ([dirtyKeys count] > 0)
		{
			[internalChangeset setObject:[dirtyKeys copy] forKey:@"dirtyKeys"];
		}
		if ([dirtyPages count] > 0)
		{
			[internalChangeset setObject:[self dirtyPagesDeepCopy:dirtyPages] forKey:@"dirtyPages"];
		}
		
		if (reset)
		{
			[internalChangeset setObject:@(reset) forKey:@"reset"];
		}
		
		[internalChangeset setObject:[self groupPagesDictDeepCopy:groupPagesDict] forKey:@"groupPagesDict"];
		[internalChangeset setObject:[pageKeyGroupDict mutableCopy] forKey:@"pageKeyGroupDict"];
	}
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	YDBLogAutoTrace();
	
	NSMutableDictionary *changeset_groupPagesDict = [changeset objectForKey:@"groupPagesDict"];
	NSMutableDictionary *changeset_pageKeyGroupDict = [changeset objectForKey:@"pageKeyGroupDict"];
	
	NSDictionary *changeset_dirtyKeys = [changeset objectForKey:@"dirtyKeys"];
	NSDictionary *changeset_dirtyPages = [changeset objectForKey:@"dirtyPages"];
	
	BOOL changeset_reset = [[changeset objectForKey:@"reset"] boolValue];
	
	// Process new top level objects
	
	groupPagesDict = [self groupPagesDictDeepCopy:changeset_groupPagesDict];
	pageKeyGroupDict = [changeset_pageKeyGroupDict mutableCopy];
	
	// Update caches
	
	if (changeset_reset)
	{
		if (changeset_dirtyKeys == nil)
		{
			[keyCache removeAllObjects];
		}
		else
		{
			NSUInteger removeCapacity = [keyCache count];
			NSUInteger updateCapacity = MIN([keyCache count], [changeset_dirtyKeys count]);
			
			NSMutableArray *keysToRemove = [NSMutableArray arrayWithCapacity:removeCapacity];
			NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
			
			[keyCache enumerateKeysWithBlock:^(id key, BOOL *stop) {
				
				// Order matters.
				// Consider the following database change:
				//
				// [transaction removeAllObjects];
				// [transaction setObject:obj forKey:key];
				
				if ([changeset_dirtyKeys objectForKey:key] != [NSNull null])
					[keysToUpdate addObject:key];
				else
					[keysToRemove addObject:key];
			}];
			
			[keyCache removeObjectsForKeys:keysToRemove];
			
			for (NSString *key in keysToUpdate)
			{
				NSString *pageKey = [changeset_dirtyKeys objectForKey:key];
				
				[keyCache setObject:pageKey forKey:key];
			}
		}
		
		if (changeset_dirtyPages == nil)
		{
			[pageCache removeAllObjects];
		}
		else
		{
			NSUInteger removeCapacity = [pageCache count];
			NSUInteger updateCapacity = MIN([pageCache count], [changeset_dirtyPages count]);
			
			NSMutableArray *keysToRemove = [NSMutableArray arrayWithCapacity:removeCapacity];
			NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
			
			[pageCache enumerateKeysWithBlock:^(id key, BOOL *stop) {
				
				// Order matters.
				// Consider the following database change:
				//
				// [transaction removeAllObjects];
				// [transaction setObject:obj forKey:key];
				
				if ([changeset_dirtyPages objectForKey:key] != [NSNull null])
					[keysToUpdate addObject:key];
				else
					[keysToRemove addObject:key];
			}];
			
			[pageCache removeObjectsForKeys:keysToRemove];
			
			for (NSString *pageKey in keysToUpdate)
			{
				NSMutableArray *page = [changeset_dirtyPages objectForKey:pageKey];
				
				// Each viewConnection needs its own independent mutable copy of the page.
				// Mutable pages cannot be shared between multiple view connections.
				
				[pageCache setObject:[page mutableCopy] forKey:pageKey];
			}
		}
	}
	else
	{
		// The database wasn't reset.
		// So we only have to worry about the changes in dirtyKeys & dirtyPages.
		
		[changeset_dirtyKeys enumerateKeysAndObjectsUsingBlock:^(id keyObj, id pageKeyObj, BOOL *stop) {
			
			__unsafe_unretained NSString *key = (NSString *)keyObj;
			__unsafe_unretained NSString *pageKey = (NSString *)pageKeyObj;
			
			if ([keyCache objectForKey:key] != nil)
			{
				if ((id)pageKey == (id)[NSNull null])
				{
					[keyCache removeObjectForKey:key];
				}
				else
				{
					[keyCache setObject:pageKey forKey:key];
				}
			}
		}];
		
		[changeset_dirtyPages enumerateKeysAndObjectsUsingBlock:^(id pageKeyObj, id pageObj, BOOL *stop) {
			
			__unsafe_unretained NSString *pageKey = (NSString *)pageKeyObj;
			__unsafe_unretained NSMutableArray *page = (NSMutableArray *)pageObj;
			
			if ([pageCache objectForKey:pageKey] != nil)
			{
				if ((id)page == (id)[NSNull null])
				{
					[pageCache removeObjectForKey:pageKey];
				}
				else
				{
					// Each viewConnection needs its own independent mutable copy of the page.
					// Mutable pages cannot be shared between multiple view connections.
					
					[pageCache setObject:[page mutableCopy] forKey:pageKey];
				}
			}
		}];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)keyTable_getPageKeyForKeyStatement
{
	if (keyTable_getPageKeyForKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"SELECT \"pageKey\" FROM \"%@\" WHERE \"key\" = ? ;", [self keyTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_getPageKeyForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_getPageKeyForKeyStatement;
}

- (sqlite3_stmt *)keyTable_setPageKeyForKeyStatement
{
	if (keyTable_setPageKeyForKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"INSERT OR REPLACE INTO \"%@\" (\"key\", \"pageKey\") VALUES (?, ?);", [self keyTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_setPageKeyForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_setPageKeyForKeyStatement;
}

- (sqlite3_stmt *)keyTable_removeForKeyStatement
{
	if (keyTable_removeForKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\" WHERE \"key\" = ?;", [self keyTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_removeForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_removeForKeyStatement;
}

- (sqlite3_stmt *)keyTable_removeAllStatement
{
	if (keyTable_removeAllStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\";", [self keyTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_removeAllStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_removeAllStatement;
}

- (sqlite3_stmt *)pageTable_getDataForPageKeyStatement
{
	if (pageTable_getDataForPageKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"SELECT \"data\" FROM \"%@\" WHERE \"pageKey\" = ? ;", [self pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_getDataForPageKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return pageTable_getDataForPageKeyStatement;
}

- (sqlite3_stmt *)pageTable_setAllForPageKeyStatement
{
	if (pageTable_setAllForPageKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"INSERT OR REPLACE INTO \"%@\" (\"pageKey\", \"data\", \"metadata\") VALUES (?, ?, ?);",
		    [self pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_setAllForPageKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return pageTable_setAllForPageKeyStatement;
}

- (sqlite3_stmt *)pageTable_setMetadataForPageKeyStatement
{
	if (pageTable_setMetadataForPageKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"UPDATE \"%@\" SET \"metadata\" = ? WHERE \"pageKey\" = ?;", [self pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_getDataForPageKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return pageTable_setMetadataForPageKeyStatement;
}

- (sqlite3_stmt *)pageTable_removeForPageKeyStatement
{
	if (pageTable_removeForPageKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\" WHERE \"pageKey\" = ?;", [self pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_removeForPageKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}

	}
	
	return pageTable_removeForPageKeyStatement;
}

- (sqlite3_stmt *)pageTable_removeAllStatement
{
	if (pageTable_removeAllStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\";", [self pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_removeAllStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return pageTable_removeAllStatement;
}

@end
