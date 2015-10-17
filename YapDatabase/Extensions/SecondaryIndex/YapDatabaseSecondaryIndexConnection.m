#import "YapDatabaseSecondaryIndexConnection.h"
#import "YapDatabaseSecondaryIndexPrivate.h"
#import "YapDatabaseStatement.h"

#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"

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


@implementation YapDatabaseSecondaryIndexConnection
{
	sqlite3_stmt *insertStatement;
	sqlite3_stmt *updateStatement;
	sqlite3_stmt *removeStatement;
	sqlite3_stmt *removeAllStatement;
}

@synthesize secondaryIndex = parent;

- (id)initWithParent:(YapDatabaseSecondaryIndex *)inParent
  databaseConnection:(YapDatabaseConnection *)inDatabaseConnection
{
	if ((self = [super init]))
	{
		parent = inParent;
		databaseConnection = inDatabaseConnection;
		
		queryCacheLimit = 10;
		queryCache = [[YapCache alloc] initWithCountLimit:queryCacheLimit];
		queryCache.allowedKeyClasses = [NSSet setWithObject:[NSString class]];
		queryCache.allowedObjectClasses = [NSSet setWithObject:[YapDatabaseStatement class]];
	}
	return self;
}

- (void)dealloc
{
	[queryCache removeAllObjects];
	[self _flushStatements];
}

- (void)_flushStatements
{
	sqlite_finalize_null(&insertStatement);
	sqlite_finalize_null(&updateStatement);
	sqlite_finalize_null(&removeStatement);
	sqlite_finalize_null(&removeAllStatement);
}

/**
 * Required override method from YapDatabaseExtensionConnection
**/
- (void)_flushMemoryWithFlags:(YapDatabaseConnectionFlushMemoryFlags)flags
{
	if (flags & YapDatabaseConnectionFlushMemoryFlags_Caches)
	{
		[queryCache removeAllObjects];
	}
	
	if (flags & YapDatabaseConnectionFlushMemoryFlags_Statements)
	{
		[self _flushStatements];
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)queryCacheEnabled
{
	__block BOOL result = NO;
	
	dispatch_block_t block = ^{
		
		result = (queryCache == nil) ? NO : YES;
	};
	
	if (dispatch_get_specific(databaseConnection->IsOnConnectionQueueKey))
		block();
	else
		dispatch_sync(databaseConnection->connectionQueue, block);
	
	return result;
}

- (void)setQueryCacheEnabled:(BOOL)queryCacheEnabled
{
	dispatch_block_t block = ^{
		
		if (queryCacheEnabled)
		{
			if (queryCache == nil)
			{
				queryCache = [[YapCache alloc] initWithCountLimit:queryCacheLimit];
				queryCache.allowedKeyClasses = [NSSet setWithObject:[NSString class]];
				queryCache.allowedObjectClasses = [NSSet setWithObject:[YapDatabaseStatement class]];
			}
		}
		else
		{
			queryCache = nil;
		}
	};
	
	if (dispatch_get_specific(databaseConnection->IsOnConnectionQueueKey))
		block();
	else
		dispatch_async(databaseConnection->connectionQueue, block);
}

- (NSUInteger)queryCacheLimit
{
	__block NSUInteger result = 0;
	
	dispatch_block_t block = ^{
		
		result = queryCacheLimit;
	};
	
	if (dispatch_get_specific(databaseConnection->IsOnConnectionQueueKey))
		block();
	else
		dispatch_sync(databaseConnection->connectionQueue, block);
	
	return result;
}

- (void)setQueryCacheLimit:(NSUInteger)newQueryCacheLimit
{
	dispatch_block_t block = ^{
		
		queryCacheLimit = newQueryCacheLimit;
		queryCache.countLimit = queryCacheLimit;
	};
	
	if (dispatch_get_specific(databaseConnection->IsOnConnectionQueueKey))
		block();
	else
		dispatch_async(databaseConnection->connectionQueue, block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YapDatabaseSecondaryIndexTransaction *transaction =
	    [[YapDatabaseSecondaryIndexTransaction alloc] initWithParentConnection:self
	                                                       databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseSecondaryIndexTransaction *transaction =
	    [[YapDatabaseSecondaryIndexTransaction alloc] initWithParentConnection:self
	                                                       databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return transaction;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Initializes any ivars that a read-write transaction may need.
**/
- (void)prepareForReadWriteTransaction
{
	if (blockDict == nil)
		blockDict = [NSMutableDictionary dictionaryWithSharedKeySet:parent->columnNamesSharedKeySet];
	
	if (mutationStack == nil)
		mutationStack = [[YapMutationStack_Bool alloc] init];
}

- (void)postCommitCleanup
{
	[mutationStack clear];
}

- (void)postRollbackCleanup
{
	[mutationStack clear];
}

/**
 * Required override method from YapDatabaseExtension
**/
- (void)getInternalChangeset:(NSMutableDictionary __unused **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary __unused **)externalChangesetPtr
              hasDiskChanges:(BOOL __unused *)hasDiskChangesPtr
{
	// Nothing to do for this particular extension.
	//
	// YapDatabaseExtension throws a "not implemented" exception
	// to ensure extensions have implementations of all required methods.
}

/**
 * Required override method from YapDatabaseExtension
**/
- (void)processChangeset:(NSDictionary __unused *)changeset
{
	// Nothing to do for this particular extension.
	//
	// YapDatabaseExtension throws a "not implemented" exception
	// to ensure extensions have implementations of all required methods.
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
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

- (sqlite3_stmt *)insertStatement
{
	sqlite3_stmt **statement = &insertStatement;
	if (*statement == NULL)
	{
		NSMutableString *string = [NSMutableString stringWithCapacity:100];
		[string appendFormat:@"INSERT INTO \"%@\" (\"rowid\"", [parent tableName]];
		
		for (YapDatabaseSecondaryIndexColumn *column in parent->setup)
		{
			[string appendFormat:@", \"%@\"", column.name];
		}
		
		[string appendString:@") VALUES (?"];
		
		NSUInteger count = [parent->setup count];
		NSUInteger i;
		for (i = 0; i < count; i++)
		{
			[string appendString:@", ?"];
		}
		
		[string appendString:@");"];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)updateStatement
{
	sqlite3_stmt **statement = &updateStatement;
	if (*statement == NULL)
	{
		NSMutableString *string = [NSMutableString stringWithCapacity:100];
		[string appendFormat:@"INSERT OR REPLACE INTO \"%@\" (\"rowid\"", [parent tableName]];
		
		for (YapDatabaseSecondaryIndexColumn *column in parent->setup)
		{
			[string appendFormat:@", \"%@\"", column.name];
		}
		
		[string appendString:@") VALUES (?"];
		
		NSUInteger count = [parent->setup count];
		NSUInteger i;
		for (i = 0; i < count; i++)
		{
			[string appendString:@", ?"];
		}
		
		[string appendString:@");"];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)removeStatement
{
	sqlite3_stmt **statement = &removeStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"rowid\" = ?;", [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)removeAllStatement
{
	sqlite3_stmt **statement = &removeAllStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\";", [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

@end
