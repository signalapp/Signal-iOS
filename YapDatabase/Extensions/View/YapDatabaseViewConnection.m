#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewPrivate.h"

#import "YapCollectionKey.h"
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
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)


@implementation YapDatabaseViewConnection {
@private
	
	sqlite3_stmt *mapTable_getPageKeyForRowidStatement;
	sqlite3_stmt *mapTable_setPageKeyForRowidStatement;
	sqlite3_stmt *mapTable_removeForRowidStatement;
	sqlite3_stmt *mapTable_removeAllStatement;
	
	sqlite3_stmt *pageTable_getDataForPageKeyStatement;
	sqlite3_stmt *pageTable_insertForPageKeyStatement;
	sqlite3_stmt *pageTable_updateAllForPageKeyStatement;
	sqlite3_stmt *pageTable_updatePageForPageKeyStatement;
	sqlite3_stmt *pageTable_updateLinkForPageKeyStatement;
	sqlite3_stmt *pageTable_removeForPageKeyStatement;
	sqlite3_stmt *pageTable_removeAllStatement;
}

@synthesize parent = parent;

- (id)initWithParent:(YapDatabaseView *)inParent databaseConnection:(YapDatabaseConnection *)inDbC
{
	if ((self = [super init]))
	{
		parent = inParent;
		databaseConnection = inDbC;
		
		mapCache = [[YapCache alloc] initWithCountLimit:100];
		mapCache.allowedKeyClasses = [NSSet setWithObject:[NSNumber class]];
		mapCache.allowedObjectClasses = [NSSet setWithObjects:[NSString class], [NSNull class], nil];
		
		pageCache = [[YapCache alloc] initWithCountLimit:40];
		pageCache.allowedKeyClasses = [NSSet setWithObject:[NSString class]];
		pageCache.allowedObjectClasses = [NSSet setWithObject:[YapDatabaseViewPage class]];
		
		sharedKeySetForInternalChangeset = [NSDictionary sharedKeySetForKeys:[self internalChangesetKeys]];
		sharedKeySetForExternalChangeset = [NSDictionary sharedKeySetForKeys:[self externalChangesetKeys]];
	}
	return self;
}

- (void)dealloc
{
	[self _flushStatements];
}

- (void)_flushStatements
{
	sqlite_finalize_null(&mapTable_getPageKeyForRowidStatement);
	sqlite_finalize_null(&mapTable_setPageKeyForRowidStatement);
	sqlite_finalize_null(&mapTable_removeForRowidStatement);
	sqlite_finalize_null(&mapTable_removeAllStatement);
	
	sqlite_finalize_null(&pageTable_getDataForPageKeyStatement);
	sqlite_finalize_null(&pageTable_insertForPageKeyStatement);
	sqlite_finalize_null(&pageTable_updateAllForPageKeyStatement);
	sqlite_finalize_null(&pageTable_updatePageForPageKeyStatement);
	sqlite_finalize_null(&pageTable_updateLinkForPageKeyStatement);
	sqlite_finalize_null(&pageTable_removeForPageKeyStatement);
	sqlite_finalize_null(&pageTable_removeAllStatement);
}

/**
 * Required override method from YapDatabaseExtensionConnection
**/
- (void)_flushMemoryWithFlags:(YapDatabaseConnectionFlushMemoryFlags)flags
{
	if (flags & YapDatabaseConnectionFlushMemoryFlags_Caches)
	{
		[mapCache removeAllObjects];
		[pageCache removeAllObjects];
	}
	
	if (flags & YapDatabaseConnectionFlushMemoryFlags_Statements)
	{
		[self _flushStatements];
	}
	
	if (flags & YapDatabaseConnectionFlushMemoryFlags_Extension_State)
	{
		state = nil;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (YapDatabaseExtension *)extension
{
	return parent;
}

- (BOOL)isPersistentView
{
	return parent->options.isPersistent;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)sanitizeDirtyPages
{
	NSNull *nsnull = [NSNull null];
	
	for (NSString *pageKey in [dirtyPages allKeys])
	{
		YapDatabaseViewPage *page = [dirtyPages objectForKey:pageKey];
		
		if ((id)page != nsnull)
		{
			[dirtyPages setObject:[page copy] forKey:pageKey];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset Architecture
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Initializes any ivars that a read-write transaction may need.
**/
- (void)prepareForReadWriteTransaction
{
	YDBLogAutoTrace();
	
	if (dirtyMaps == nil)
		dirtyMaps = [[YapDirtyDictionary alloc] init];
	if (dirtyPages == nil)
		dirtyPages = [[NSMutableDictionary alloc] init];
	if (dirtyLinks == nil)
		dirtyLinks = [[NSMutableDictionary alloc] init];
	if (changes == nil)
		changes = [[NSMutableArray alloc] init];
	if (mutatedGroups == nil)
		mutatedGroups = [[NSMutableSet alloc] init];
	
	if (state.isImmutable)
		state = [state mutableCopy];
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the commitTransaction method.
**/
- (void)postCommitCleanup
{
	YDBLogAutoTrace();
	
	// This code is best understood alongside the getExternalChangeset:internalChangeset: method (below).
	
	// Both dirtyKeys & dirtyPages are sent in the internalChangeset.
	// So we need completely new versions of them.
	
	if ([dirtyMaps count] > 0)
		dirtyMaps = nil;
	
	if ([dirtyPages count] > 0)
		dirtyPages = nil;
	
	// dirtyLinks isn't part of the changeset.
	// So it's safe to simply reset.
	
	[dirtyLinks removeAllObjects];
	
	// The changes log is copied into the external changeset.
	// So it's safe to simply reset.
	
	[changes removeAllObjects];
	[mutatedGroups removeAllObjects];
	
	reset = NO;
	
	// Don't keep cached configuration in memory.
	// These are loaded on-demand within readwrite transactions.
	
	versionTag = nil;
	versionTagChanged = NO;
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the rollbackTransaction method.
**/
- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	
	YapDatabaseViewState *previousState = nil;
	
	BOOL shortcut = [parent getState:&previousState forConnection:self];
	if (shortcut && previousState) {
		state = [previousState copy];
	}
	else {
		state = nil;
	}
	
	[mapCache removeAllObjects];
	[pageCache removeAllObjects];
	
	[dirtyMaps removeAllObjects];
	[dirtyPages removeAllObjects];
	[dirtyLinks removeAllObjects];
	reset = NO;
	
	[changes removeAllObjects];
	
	// Don't keep cached configuration in memory.
	// These are loaded on-demand within readwrite transactions.
	
	versionTag = nil;
	versionTagChanged = NO;
}

- (NSArray *)internalChangesetKeys
{
	return @[ changeset_key_state,
	          changeset_key_dirtyMaps,
	          changeset_key_dirtyPages,
	          changeset_key_reset,
	          changeset_key_grouping,
	          changeset_key_sorting,
	          changeset_key_versionTag ];
}

- (NSArray *)externalChangesetKeys
{
	return @[ changeset_key_changes ];
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr
{
	YDBLogAutoTrace();
	
	NSMutableDictionary *internalChangeset = nil;
	NSMutableDictionary *externalChangeset = nil;
	BOOL hasDiskChanges = NO;
	
	if ([dirtyMaps count]  > 0 ||
	    [dirtyPages count] > 0 ||
	    [dirtyLinks count] > 0 || reset)
	{
		internalChangeset = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySetForInternalChangeset];
		
		if ([dirtyMaps count] > 0) {
			[dirtyMaps removeCleanObjects];
			internalChangeset[changeset_key_dirtyMaps] = dirtyMaps;
		}
		
		if ([dirtyPages count] > 0) {
			[self sanitizeDirtyPages];
			internalChangeset[changeset_key_dirtyPages] = dirtyPages;
		}
		
		if (reset) {
			internalChangeset[changeset_key_reset] = @(reset);
		}
		
		internalChangeset[changeset_key_state] = [state copy]; // immutable copy
		
		hasDiskChanges = [self isPersistentView];
	}
	
	if (versionTagChanged)
	{
		if (internalChangeset == nil)
			internalChangeset = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySetForInternalChangeset];
		
		internalChangeset[changeset_key_versionTag] = versionTag;
			
		hasDiskChanges = hasDiskChanges || [self isPersistentView];
	}
	
	if ([changes count] > 0)
	{
		externalChangeset = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySetForExternalChangeset];
		
		externalChangeset[changeset_key_changes] = [changes copy]; // immutable copy
	}
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
	*hasDiskChangesPtr = hasDiskChanges;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	YDBLogAutoTrace();
	
	YapDatabaseViewState *changeset_state = changeset[changeset_key_state];
	
	YapDirtyDictionary *changeset_dirtyMaps  = changeset[changeset_key_dirtyMaps];
	NSDictionary       *changeset_dirtyPages = changeset[changeset_key_dirtyPages];
	
	BOOL changeset_reset = [changeset[changeset_key_reset] boolValue];
	
	// Store new state
	
	if (changeset_state)
		state = [changeset_state copy];
	
	// Update mapCache
	
	if (changeset_reset && ([changeset_dirtyMaps count] == 0))
	{
		[mapCache removeAllObjects];
	}
	else if ([changeset_dirtyMaps count] > 0)
	{
		NSUInteger removeCapacity = changeset_reset ? [mapCache count] : 0;
		NSUInteger updateCapacity = MIN([mapCache count], [changeset_dirtyMaps count]);
		
		NSMutableArray *keysToRemove = changeset_reset ? [NSMutableArray arrayWithCapacity:removeCapacity] : nil;
		NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
		
		[mapCache enumerateKeysWithBlock:^(id key, BOOL __unused *stop) {
			
			// Order matters.
			// Consider the following database change:
			//
			// [transaction removeAllObjects];
			// [transaction setObject:obj forKey:key];
			
			if ([changeset_dirtyMaps objectForKey:key])
				[keysToUpdate addObject:key];
			else if (changeset_reset)
				[keysToRemove addObject:key];
		}];
		
		[mapCache removeObjectsForKeys:keysToRemove];
		
		NSNull *nsnull = [NSNull null];
		
		for (NSString *key in keysToUpdate)
		{
			NSString *pageKey = [changeset_dirtyMaps objectForKey:key];
			
			if ((id)pageKey == nsnull)
				[mapCache removeObjectForKey:key];
			else
				[mapCache setObject:pageKey forKey:key];
		}
	}
	
	// Update pageCache
	
	if (changeset_reset && ([changeset_dirtyPages count] == 0))
	{
		[pageCache removeAllObjects];
	}
	else if ([changeset_dirtyPages count])
	{
		NSUInteger removeCapacity = changeset_reset ? [pageCache count] : 0;
		NSUInteger updateCapacity = MIN([pageCache count], [changeset_dirtyPages count]);
		
		NSMutableArray *keysToRemove = changeset_reset ? [NSMutableArray arrayWithCapacity:removeCapacity] : nil;
		NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
		
		[pageCache enumerateKeysWithBlock:^(id key, BOOL __unused *stop) {
			
			// Order matters.
			// Consider the following database change:
			//
			// [transaction removeAllObjects];
			// [transaction setObject:obj forKey:key];
			
			if ([changeset_dirtyPages objectForKey:key])
				[keysToUpdate addObject:key];
			else if (changeset_reset)
				[keysToRemove addObject:key];
		}];
		
		[pageCache removeObjectsForKeys:keysToRemove];
		
		NSNull *nsnull = [NSNull null];
		
		for (NSString *pageKey in keysToUpdate)
		{
			YapDatabaseViewPage *page = [changeset_dirtyPages objectForKey:pageKey];
			
			// Each viewConnection needs its own independent mutable copy of the page.
			// Mutable pages cannot be shared between multiple view connections.
			
			if ((id)page == nsnull)
				[pageCache removeObjectForKey:pageKey];
			else
				[pageCache setObject:[page copy] forKey:pageKey];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)prepareStatement:(sqlite3_stmt **)statement withString:(NSString *)stmtString caller:(SEL)caller_cmd
{
	sqlite3 *db = databaseConnection->db;
	YapDatabaseString stmt; MakeYapDatabaseString(&stmt, stmtString);
	
	int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating prepared statement: %d %s",
					NSStringFromSelector(caller_cmd), status, sqlite3_errmsg(db));
	}
	
	FreeYapDatabaseString(&stmt);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - MapTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)mapTable_getPageKeyForRowidStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");
	
	sqlite3_stmt **statement = &mapTable_getPageKeyForRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"SELECT \"pageKey\" FROM \"%@\" WHERE \"rowid\" = ?;", [parent mapTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)mapTable_setPageKeyForRowidStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");

	sqlite3_stmt **statement = &mapTable_setPageKeyForRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"INSERT OR REPLACE INTO \"%@\" (\"rowid\", \"pageKey\") VALUES (?, ?);", [parent mapTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)mapTable_removeForRowidStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");

	sqlite3_stmt **statement = &mapTable_removeForRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\" WHERE \"rowid\" = ?;", [parent mapTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)mapTable_removeAllStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");

	sqlite3_stmt **statement = &mapTable_removeAllStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\";", [parent mapTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - PageTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)pageTable_getDataForPageKeyStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");

	sqlite3_stmt **statement = &pageTable_getDataForPageKeyStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"SELECT \"data\" FROM \"%@\" WHERE \"pageKey\" = ?;", [parent pageTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)pageTable_insertForPageKeyStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");

	sqlite3_stmt **statement = &pageTable_insertForPageKeyStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
			@"INSERT INTO \"%@\""
			@" (\"pageKey\", \"group\", \"prevPageKey\", \"count\", \"data\") VALUES (?, ?, ?, ?, ?);",
			[parent pageTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)pageTable_updateAllForPageKeyStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");

	sqlite3_stmt **statement = &pageTable_updateAllForPageKeyStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
			@"UPDATE \"%@\" SET \"prevPageKey\" = ?, \"count\" = ?, \"data\" = ? WHERE \"pageKey\" = ?;",
			[parent pageTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)pageTable_updatePageForPageKeyStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");

	sqlite3_stmt **statement = &pageTable_updatePageForPageKeyStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
			@"UPDATE \"%@\" SET \"count\" = ?, \"data\" = ? WHERE \"pageKey\" = ?;", [parent pageTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)pageTable_updateLinkForPageKeyStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");

	sqlite3_stmt **statement = &pageTable_updateLinkForPageKeyStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
			@"UPDATE \"%@\" SET \"prevPageKey\" = ? WHERE \"pageKey\" = ?;", [parent pageTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)pageTable_removeForPageKeyStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");

	sqlite3_stmt **statement = &pageTable_removeForPageKeyStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\" WHERE \"pageKey\" = ?;", [parent pageTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)pageTable_removeAllStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");

	sqlite3_stmt **statement = &pageTable_removeAllStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\";", [parent pageTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

@end
