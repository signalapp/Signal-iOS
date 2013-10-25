#import "YapAbstractDatabase.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"

#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"
#import "YapDatabaseManager.h"

#import "sqlite3.h"

#import <libkern/OSAtomic.h>

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif

NSString *const YapDatabaseModifiedNotification = @"YapDatabaseModifiedNotification";

NSString *const YapDatabaseSnapshotKey   = @"snapshot";
NSString *const YapDatabaseConnectionKey = @"connection";
NSString *const YapDatabaseExtensionsKey = @"extensions";
NSString *const YapDatabaseCustomKey     = @"custom";

NSString *const YapDatabaseRegisteredExtensionsKey = @"registeredExtensions";
NSString *const YapDatabaseNotificationKey         = @"notification";

/**
 * The database version is stored (via pragma user_version) to sqlite.
 * It is used to represent the version of the userlying architecture of YapDatabase.
 * In the event of future changes to the sqlite underpinnings of YapDatabase,
 * the version can be consulted to allow for proper on-the-fly upgrades.
 * For more information, see the upgradeTable method.
**/
#define YAP_DATABASE_CURRENT_VERION 3

/**
 * Default values
**/
#define DEFAULT_MAX_CONNECTION_POOL_COUNT 5    // connections
#define DEFAULT_CONNECTION_POOL_LIFETIME  90.0 // seconds


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapAbstractDatabase

@synthesize databasePath;

- (id)initWithPath:(NSString *)inPath
{
	// First, standardize path.
	// This allows clients to be lazy when passing paths.
	NSString *path = [inPath stringByStandardizingPath];
	
	// Ensure there is only a single database instance per file.
	// However, clients may create as many connections as desired.
	if (![YapDatabaseManager registerDatabaseForPath:path])
	{
		YDBLogError(@"Only a single database instance is allowed per file. "
		            @"For concurrency you create multiple connections from a single database instance.");
		return nil;
	}
	
	if ((self = [super init]))
	{
		databasePath = path;
		
		BOOL(^openConfigCreate)(void) = ^BOOL (void) { @autoreleasepool {
		
			BOOL result = YES;
			
			if (result) result = [self openDatabase];
			if (result) result = [self configureDatabase];
			if (result) result = [self createTables];
			
			if (!result && db)
			{
				sqlite3_close(db);
				db = NULL;
			}
			
			return result;
		}};
		
		BOOL result = openConfigCreate();
		if (!result)
		{
			// There are a few reasons why the database might not open.
			// One possibility is if the database file gets corrupt.
			// In the event of a problem, we simply delete the database file.
			// This isn't a big deal since we can just redownload the data.
			
			// Delete the (possibly corrupt) database file.
			[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
			
			// Then try opening a database again.
			
			result = openConfigCreate();
			
			if (result) {
				YDBLogInfo(@"Database corruption resolved (name=%@)", [path lastPathComponent]);
			}
			else {
				YDBLogError(@"Database corruption unresolved (name=%@)", [path lastPathComponent]);
			}
		}
		if (!result)
		{
			return nil;
		}
		
		internalQueue   = dispatch_queue_create("YapDatabase-Internal", NULL);
		checkpointQueue = dispatch_queue_create("YapDatabase-Checkpoint", NULL);
		snapshotQueue   = dispatch_queue_create("YapDatabase-Snapshot", NULL);
		writeQueue      = dispatch_queue_create("YapDatabase-Write", NULL);
		
		changesets = [[NSMutableArray alloc] init];
		connectionStates = [[NSMutableArray alloc] init];
		
		defaults = [[YapAbstractDatabaseDefaults alloc] init];
		
		registeredExtensions = [[NSDictionary alloc] init];
		
		maxConnectionPoolCount = DEFAULT_MAX_CONNECTION_POOL_COUNT;
		connectionPoolLifetime = DEFAULT_CONNECTION_POOL_LIFETIME;
		
		// Mark the queues so we can identify them.
		// There are several methods whose use is restricted to within a certain queue.
		
		IsOnSnapshotQueueKey = &IsOnSnapshotQueueKey;
		dispatch_queue_set_specific(snapshotQueue, IsOnSnapshotQueueKey, IsOnSnapshotQueueKey, NULL);
		
		IsOnWriteQueueKey = &IsOnWriteQueueKey;
		dispatch_queue_set_specific(writeQueue, IsOnWriteQueueKey, IsOnWriteQueueKey, NULL);
		
		// Complete database setup in the background
		dispatch_async(snapshotQueue, ^{ @autoreleasepool {
	
			[self upgradeTable];
			[self prepare];
		}});
	}
	return self;
}

- (void)dealloc
{
	YDBLogVerbose(@"Dealloc <%@ %p: databaseName=%@>", [self class], self, [databasePath lastPathComponent]);
	
	while ([connectionPoolValues count] > 0)
	{
		sqlite3 *aDb = (sqlite3 *)[[connectionPoolValues objectAtIndex:0] pointerValue];
		
		int status = sqlite3_close(aDb);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error in sqlite_close: %d %s", status, sqlite3_errmsg(aDb));
		}
		
		[connectionPoolValues removeObjectAtIndex:0];
		[connectionPoolDates removeObjectAtIndex:0];
	}
	
	if (connectionPoolTimer)
		dispatch_source_cancel(connectionPoolTimer);
	
	if (db) {
		sqlite3_close(db);
		db = NULL;
	}
	
	[YapDatabaseManager deregisterDatabaseForPath:databasePath];
	
#if !OS_OBJECT_USE_OBJC
	if (internalQueue)
		dispatch_release(internalQueue);
	if (snapshotQueue)
		dispatch_release(snapshotQueue);
	if (writeQueue)
		dispatch_release(writeQueue);
	if (checkpointQueue)
		dispatch_release(checkpointQueue);
#endif
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Attempts to open (or create & open) the database connection.
**/
- (BOOL)openDatabase
{
	// Open the database connection.
	//
	// We use SQLITE_OPEN_NOMUTEX to use the multi-thread threading mode,
	// as we will be serializing access to the connection externally.
	
	int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_PRIVATECACHE;
	
	int status = sqlite3_open_v2([databasePath UTF8String], &db, flags, NULL);
	if (status != SQLITE_OK)
	{
		// There are a few reasons why the database might not open.
		// One possibility is if the database file gets corrupt.
		// In the event of a problem, we simply delete the database file.
		// This isn't a big deal since we can just redownload the data.
		
		// Sometimes the open function returns a db to allow us to query it for the error message
		if (db) {
			YDBLogWarn(@"Error opening database: %d %s", status, sqlite3_errmsg(db));
		}
		else {
			YDBLogError(@"Error opening database: %d", status);
		}
		
		return NO;
	}
	
	return YES;
}

/**
 * Configures the database connection.
 * This mainly means enabling WAL mode, and configuring the auto-checkpoint.
**/
- (BOOL)configureDatabase
{
	int status;
	
	status = sqlite3_exec(db, "PRAGMA legacy_file_format = 0;", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error setting legacy_file_format: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	status = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error setting journal_mode: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	// Disable autocheckpointing.
	//
	// YapDatabase has its own optimized checkpointing algorithm built-in.
	// It knows the state of every active connection for the database,
	// so it can invoke the checkpoint methods at the precise time in which a checkpoint can be most effective.
	
	sqlite3_wal_autocheckpoint(db, 0);
	
	return YES;
}

/**
 * REQUIRED OVERRIDE HOOK.
 * 
 * Don't forget to invoke [super createTables] so this method can create its tables too.
**/
- (BOOL)createTables
{
	char *createYapTableStatement =
	    "CREATE TABLE IF NOT EXISTS \"yap2\""
	    " (\"extension\" CHAR NOT NULL, "
	    "  \"key\" CHAR NOT NULL, "
	    "  \"data\" BLOB, "
	    "  PRIMARY KEY (\"extension\", \"key\")"
	    " );";
	
	int status = sqlite3_exec(db, createYapTableStatement, NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Failed creating 'yap2' table: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	return YES;
}

/**
 * REQUIRED OVERRIDE HOOK.
 * 
 * Subclasses must implement this method and return the proper class to use for the cache.
**/
- (Class)cacheKeyClass
{
	NSAssert(NO, @"Missing required override method in subclass");
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns whether or not the given table exists.
**/
- (BOOL)tableExists:(NSString *)tableName using:(sqlite3 *)aDb
{
	if (tableName == nil) return NO;
	
	sqlite3_stmt *statement;
	char *stmt = "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = ?";
	
	int status = sqlite3_prepare_v2(aDb, stmt, (int)strlen(stmt)+1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating statement! %d %s", THIS_METHOD, status, sqlite3_errmsg(aDb));
		return NO;
	}
	
	BOOL result = NO;
	
	sqlite3_bind_text(statement, 1, [tableName UTF8String], -1, SQLITE_TRANSIENT);
	
	status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		int count = sqlite3_column_int(statement, 1);
		
		result = (count > 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@: Error executing statement! %d %s", THIS_METHOD, status, sqlite3_errmsg(aDb));
	}
	
	sqlite3_finalize(statement);
	statement = NULL;
	
	return result;
}

/**
 * Extracts and returns column names of our database.
**/
- (NSArray *)columnNamesForTable:(NSString *)tableName using:(sqlite3 *)aDb
{
	if (tableName == nil) return nil;
	
	sqlite3_stmt *statement;
	char *stmt = "PRAGMA table_info(?);";
	
	int status = sqlite3_prepare_v2(aDb, stmt, (int)strlen(stmt)+1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating statement! %d %s", THIS_METHOD, status, sqlite3_errmsg(aDb));
		return nil;
	}
	
	NSMutableArray *tableColumnNames = [NSMutableArray array];
	
	sqlite3_bind_text(statement, 1, [tableName UTF8String], -1, SQLITE_TRANSIENT);
	
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(statement, 1);
		int textSize = sqlite3_column_bytes(statement, 1);
		
		NSString *columnName = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		if (columnName)
		{
			[tableColumnNames addObject:columnName];
		}
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@: Error executing statement! %d %s", THIS_METHOD, status, sqlite3_errmsg(aDb));
	}
	
	sqlite3_finalize(statement);
	statement = NULL;
	
	return tableColumnNames;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Upgrade
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Gets the version of the table.
 * This is used to perform the various upgrade paths.
**/
- (BOOL)get_user_version:(int *)user_version_ptr
{
	sqlite3_stmt *pragmaStatement;
	int status;
	int user_version;
	
	char *stmt = "PRAGMA user_version;";
	
	status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &pragmaStatement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error creating pragma user_version statement! %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	status = sqlite3_step(pragmaStatement);
	if (status == SQLITE_ROW)
	{
		user_version = sqlite3_column_int(pragmaStatement, 0);
	}
	else
	{
		YDBLogError(@"Error fetching user_version: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	sqlite3_finalize(pragmaStatement);
	pragmaStatement = NULL;
	
	// If user_version is zero, then this is a new database
	
	if (user_version == 0)
	{
		user_version = YAP_DATABASE_CURRENT_VERION;
		[self set_user_version:user_version];
	}
	
	if (user_version_ptr)
		*user_version_ptr = user_version;
	return YES;
}

/**
 * Sets the version of the table.
 * The version is used to check and perform upgrade logic if needed.
**/
- (BOOL)set_user_version:(int)user_version
{
	NSString *query = [NSString stringWithFormat:@"PRAGMA user_version = %d;", user_version];
	
	int status = sqlite3_exec(db, [query UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error setting user_version: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	return YES;
}

- (BOOL)upgradeTable_2_3
{
	// In version 3, we altered the tables to use INTEGER PRIMARY KEY's so we could pass rowid's to extensions.
	//
	// This method is implemented in YapDatabase & YapCollectionsDatabase.
	// It migrates 'database' to 'database2'.
	
	return YES;
}

- (BOOL)upgradeTable_1_2
{
	// In version 1, we used a table named "yap" which had {key, data}.
	// In version 2, we use a table named "yap2" which has {extension, key, data}
	
	int status = sqlite3_exec(db, "DROP TABLE IF EXISTS \"yap\"", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Failed dropping 'yap' table: %d %s", status, sqlite3_errmsg(db));
	}
	
	return YES;
}

/**
 * Performs upgrade checks, and implements the upgrade "plumbing" by invoking the appropriate upgrade methods.
 * 
 * To add custom upgrade logic, implement a method named "upgradeTable_X_Y",
 * where X is the previous version, and Y is the new version.
 * For example:
 * 
 * - (BOOL)upgradeTable_1_2 {
 *     // Upgrades from version 1 to version 2 of YapDatabase.
 *     // Return YES if successful.
 * }
 * 
 * IMPORTANT:
 * This is for upgrades of the database schema, and low-level operations of YapDatabase.
 * This is NOT for upgrading data within the database (i.e. objects, metadata, or keys).
 * Such data upgrades should be performed client side.
 *
 * This method is run asynchronously on the queue.
**/
- (void)upgradeTable
{
	int user_version = 0;
	if (![self get_user_version:&user_version]) return;
	
	while (user_version < YAP_DATABASE_CURRENT_VERION)
	{
		// Invoke method upgradeTable_X_Y
		// where X == current_version, and Y == current_version+1.
		//
		// Do this until we're up-to-date.
		
		int new_user_version = user_version + 1;
		
		NSString *selName = [NSString stringWithFormat:@"upgradeTable_%d_%d", user_version, new_user_version];
		SEL sel = NSSelectorFromString(selName);
		
		if ([self respondsToSelector:sel])
		{
			YDBLogInfo(@"Upgrading database (%@) from version %d to %d...",
			          [databasePath lastPathComponent], user_version, new_user_version);
			
			#pragma clang diagnostic push
			#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
			if ([self performSelector:sel])
			#pragma clang diagnostic pop
			{
				[self set_user_version:new_user_version];
			}
			else
			{
				YDBLogError(@"Error upgrading database (%@)", [databasePath lastPathComponent]);
				break;
			}
		}
		else
		{
			YDBLogWarn(@"Missing upgrade method: %@", selName);
		}
		
		user_version = new_user_version;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Prepare
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Optional override hook.
 * Don't forget to invoke [super prepare] so super can prepare too.
 *
 * This method is run asynchronously on the snapshotQueue.
**/
- (void)prepare
{
	// Initialize snapshot
	
	snapshot = 0;
	
	// Write it to disk (replacing any previous value from last app run)
	
	[self beginTransaction];
	[self writeSnapshot];
	[self fetchPreviouslyRegisteredExtensionNames];
	[self commitTransaction];
}

- (void)beginTransaction
{
	int status = status = sqlite3_exec(db, "BEGIN TRANSACTION;", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error in '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
	}
}

- (void)commitTransaction
{
	int status = status = sqlite3_exec(db, "COMMIT TRANSACTION;", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error in '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
	}
}

- (void)writeSnapshot
{
	int status;
	sqlite3_stmt *statement;
	
	char *stmt = "INSERT OR REPLACE INTO \"yap2\" (\"extension\", \"key\", \"data\") VALUES (?, ?, ?);";
	
	status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating statement: %d %s",
		              NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
	}
	else
	{
		char *extension = "";
		sqlite3_bind_text(statement, 1, extension, (int)strlen(extension), SQLITE_STATIC);
		
		char *key = "snapshot";
		sqlite3_bind_text(statement, 2, key, (int)strlen(key), SQLITE_STATIC);
		
		sqlite3_bind_int64(statement, 3, (sqlite3_int64)snapshot);
		
		status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@: Error in statement: %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
		
		sqlite3_finalize(statement);
	}
}

- (void)fetchPreviouslyRegisteredExtensionNames
{
	int status;
	sqlite3_stmt *statement;
	
	char *stmt = "SELECT DISTINCT \"extension\" FROM \"yap2\";";
	
	NSMutableArray *extensionNames = [NSMutableArray array];
	
	status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating statement: %d %s",
					NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
	}
	else
	{
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			const unsigned char *text = sqlite3_column_text(statement, 0);
			int textSize = sqlite3_column_bytes(statement, 0);
			
			NSString *extensionName =
			    [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			if ([extensionName length] > 0)
			{
				[extensionNames addObject:extensionName];
			}
		}
		
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@: Error in statement: %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
		
		sqlite3_finalize(statement);
	}
	
	previouslyRegisteredExtensionNames = extensionNames;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Defaults
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapAbstractDatabaseDefaults *)defaults
{
	__block YapAbstractDatabaseDefaults *result = nil;
	
	dispatch_sync(internalQueue, ^{
		
		result = [defaults copy];
	});
	
	return result;
}

- (BOOL)defaultObjectCacheEnabled
{
	__block BOOL result = NO;
	
	dispatch_sync(internalQueue, ^{
		
		result = defaults.objectCacheEnabled;
	});
	
	return result;
}

- (void)setDefaultObjectCacheEnabled:(BOOL)defaultObjectCacheEnabled
{
	dispatch_sync(internalQueue, ^{
		
		defaults.objectCacheEnabled = defaultObjectCacheEnabled;
	});
}

- (NSUInteger)defaultObjectCacheLimit
{
	__block NSUInteger result = NO;
	
	dispatch_sync(internalQueue, ^{
		
		result = defaults.objectCacheLimit;
	});
	
	return result;
}

- (void)setDefaultObjectCacheLimit:(NSUInteger)defaultObjectCacheLimit
{
	dispatch_sync(internalQueue, ^{
		
		defaults.objectCacheLimit = defaultObjectCacheLimit;
	});
}

- (BOOL)defaultMetadataCacheEnabled
{
	__block BOOL result = NO;
	
	dispatch_sync(internalQueue, ^{
		
		result = defaults.metadataCacheEnabled;
	});
	
	return result;
}

- (void)setDefaultMetadataCacheEnabled:(BOOL)defaultMetadataCacheEnabled
{
	dispatch_sync(internalQueue, ^{
		
		defaults.metadataCacheEnabled = defaultMetadataCacheEnabled;
	});
}

- (NSUInteger)defaultMetadataCacheLimit
{
	__block NSUInteger result = 0;
	
	dispatch_sync(internalQueue, ^{
		
		result = defaults.metadataCacheLimit;
	});
	
	return result;
}

- (void)setDefaultMetadataCacheLimit:(NSUInteger)defaultMetadataCacheLimit
{
	dispatch_sync(internalQueue, ^{
		
		defaults.metadataCacheLimit = defaultMetadataCacheLimit;
	});
}

- (YapDatabasePolicy)defaultObjectPolicy
{
	__block YapDatabasePolicy result = YapDatabasePolicyShare;
	
	dispatch_sync(internalQueue, ^{
		
		result = defaults.objectPolicy;
	});
	
	return result;
}

- (void)setDefaultObjectPolicy:(YapDatabasePolicy)defaultObjectPolicy
{
	dispatch_sync(internalQueue, ^{
		
		defaults.objectPolicy = defaultObjectPolicy;
	});
}

- (YapDatabasePolicy)defaultMetadataPolicy
{
	__block YapDatabasePolicy result = YapDatabasePolicyShare;
	
	dispatch_sync(internalQueue, ^{
		
		result = defaults.metadataPolicy;
	});
	
	return result;
}

- (void)setDefaultMetadataPolicy:(YapDatabasePolicy)defaultMetadataPolicy
{
	dispatch_sync(internalQueue, ^{
		
		defaults.metadataPolicy = defaultMetadataPolicy;
	});
}

#if TARGET_OS_IPHONE

- (int)defaultAutoFlushMemoryLevel
{
	__block int result = YapDatabaseConnectionFlushMemoryLevelNone;
	
	dispatch_sync(internalQueue, ^{
		
		result = defaults.autoFlushMemoryLevel;
	});
	
	return result;
}

- (void)setDefaultAutoFlushMemoryLevel:(int)defaultAutoFlushMemoryLevel
{
	dispatch_sync(internalQueue, ^{
		
		defaults.autoFlushMemoryLevel = defaultAutoFlushMemoryLevel;
	});
}

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connections
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapAbstractDatabaseConnection *)newConnection
{
	// This method is overriden by subclasses
	return nil;
}

/**
 * This method is called from newConnection, either above or from a subclass.
**/
- (void)addConnection:(YapAbstractDatabaseConnection *)connection
{
	// We can asynchronously add the connection to the state table.
	// This is safe as the connection itself must go through the same queue in order to do anything.
	//
	// The primary motivation in adding the asynchronous functionality is due to the following common use case:
	//
	// YapDatabase *database = [[YapDatabase alloc] initWithPath:path];
	// YapDatabaseConnection *databaseConnection = [database newConnection];
	//
	// The YapDatabase init method is asynchronously preparing itself through the snapshot queue.
	// We'd like to avoid blocking the very next line of code and allow the asynchronous prepare to continue.
	
	dispatch_async(connection.connectionQueue, ^{
		
		dispatch_sync(snapshotQueue, ^{ @autoreleasepool {
			
			// Add the connection to the state table
			
			YapDatabaseConnectionState *state = [[YapDatabaseConnectionState alloc] initWithConnection:connection];
			[connectionStates addObject:state];
			
			YDBLogVerbose(@"Created new connection(%p) for <%@ %p: databaseName=%@, connectionCount=%lu>",
						  connection,
						  [self class], self, [databasePath lastPathComponent], (unsigned long)[connectionStates count]);
			
			// Invoke the one-time prepare method, so the connection can perform any needed initialization.
			// Be sure to do this within the snapshotQueue, as the prepare method depends on this.
			
			[connection prepare];
		}});
	});
}

/**
 * This method is called from YapDatabaseConnection's dealloc method.
**/
- (void)removeConnection:(YapAbstractDatabaseConnection *)connection
{
	dispatch_block_t block = ^{ @autoreleasepool {
		
		NSUInteger index = 0;
		for (YapDatabaseConnectionState *state in connectionStates)
		{
			if (state->connection == connection)
			{
				[connectionStates removeObjectAtIndex:index];
				break;
			}
			
			index++;
		}
		
		YDBLogVerbose(@"Removed connection(%p) from <%@ %p: databaseName=%@, connectionCount=%lu>",
		              connection,
		              [self class], self, [databasePath lastPathComponent], (unsigned long)[connectionStates count]);
	}};
	
	// We prefer to invoke this method synchronously.
	//
	// The connection may be the last object retaining the database.
	// It's easier to trace object deallocations when they happen in a predictable order.
	
	if (dispatch_get_specific(IsOnSnapshotQueueKey))
		block();
	else
		dispatch_sync(snapshotQueue, block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pooling
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)maxConnectionPoolCount
{
	__block NSUInteger count = 0;
	
	dispatch_sync(internalQueue, ^{
		
		count = maxConnectionPoolCount;
	});
	
	return count;
}

- (void)setMaxConnectionPoolCount:(NSUInteger)count
{
	dispatch_sync(internalQueue, ^{
		
		// Update ivar
		maxConnectionPoolCount = count;
		
		// Immediately drop any excess connections
		if ([connectionPoolValues count] > maxConnectionPoolCount)
		{
			do
			{
				sqlite3 *aDb = (sqlite3 *)[[connectionPoolValues objectAtIndex:0] pointerValue];
				
				int status = sqlite3_close(aDb);
				if (status != SQLITE_OK)
				{
					YDBLogError(@"Error in sqlite_close: %d %s", status, sqlite3_errmsg(aDb));
				}
				
				[connectionPoolValues removeObjectAtIndex:0];
				[connectionPoolDates removeObjectAtIndex:0];
				
			} while ([connectionPoolValues count] > maxConnectionPoolCount);
			
			[self resetConnectionPoolTimer];
		}
	});
}

- (NSTimeInterval)connectionPoolLifetime
{
	__block NSTimeInterval lifetime = 0;
	
	dispatch_sync(internalQueue, ^{
		
		lifetime = connectionPoolLifetime;
	});
	
	return lifetime;
}

- (void)setConnectionPoolLifetime:(NSTimeInterval)lifetime
{
	dispatch_sync(internalQueue, ^{
		
		// Update ivar
		connectionPoolLifetime = lifetime;
		
		// Update timer (if needed)
		[self resetConnectionPoolTimer];
	});
}

/**
 * Adds the given connection to the connection pool if possible.
 * 
 * Returns YES if the instance was added to the pool.
 * If so, the YapAbstractDatabase must not close the instance.
 * 
 * Returns NO if the instance was not added to the pool.
 * If so, the YapAbstractDatabaseConnection must close the instance.
**/
- (BOOL)connectionPoolEnqueue:(sqlite3 *)aDb
{
	__block BOOL result = NO;
	
	dispatch_sync(internalQueue, ^{
		
		if ([connectionPoolValues count] < maxConnectionPoolCount)
		{
			if (connectionPoolValues == nil)
			{
				connectionPoolValues = [[NSMutableArray alloc] init];
				connectionPoolDates = [[NSMutableArray alloc] init];
			}
			
			YDBLogVerbose(@"Enqueuing connection to pool: %p", aDb);
			
			[connectionPoolValues addObject:[NSValue valueWithPointer:(const void *)aDb]];
			[connectionPoolDates addObject:[NSDate date]];
			
			result = YES;
			
			if ([connectionPoolValues count] == 1)
			{
				[self resetConnectionPoolTimer];
			}
		}
	});
	
	return result;
}

/**
 * Retrieves a connection from the connection pool if available.
 * Returns NULL if no connections are available.
**/
- (sqlite3 *)connectionPoolDequeue
{
	__block sqlite3 *aDb = NULL;
	
	dispatch_sync(internalQueue, ^{
		
		if ([connectionPoolValues count] > 0)
		{
			aDb = (sqlite3 *)[[connectionPoolValues objectAtIndex:0] pointerValue];
			
			YDBLogVerbose(@"Dequeuing connection from pool: %p", aDb);
			
			[connectionPoolValues removeObjectAtIndex:0];
			[connectionPoolDates removeObjectAtIndex:0];
			
			[self resetConnectionPoolTimer];
		}
	});
	
	return aDb;
}

/**
 * Internal utility method to handle setting/resetting the timer.
**/
- (void)resetConnectionPoolTimer
{
	YDBLogAutoTrace();
	
	if (connectionPoolLifetime <= 0.0 || [connectionPoolValues count] == 0)
	{
		if (connectionPoolTimer)
		{
			dispatch_source_cancel(connectionPoolTimer);
			connectionPoolTimer = NULL;
		}
		
		return;
	}
	
	BOOL isNewTimer = NO;
	
	if (connectionPoolTimer == NULL)
	{
		connectionPoolTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, internalQueue);
		
		__weak YapAbstractDatabase *weakSelf = self;
		dispatch_source_set_event_handler(connectionPoolTimer, ^{ @autoreleasepool {
			
			__strong YapAbstractDatabase *strongSelf = weakSelf;
			if (strongSelf)
			{
				[strongSelf handleConnectionPoolTimerFire];
			}
		}});
		
		#if !OS_OBJECT_USE_OBJC
		dispatch_source_t timer = connectionPoolTimer;
		dispatch_source_set_cancel_handler(connectionPoolTimer, ^{
			dispatch_release(timer);
		});
		#endif
		
		isNewTimer = YES;
	}
	
	NSDate *date = [connectionPoolDates objectAtIndex:0];
	NSTimeInterval interval = [date timeIntervalSinceNow] + connectionPoolLifetime;
	
	dispatch_time_t tt = dispatch_time(DISPATCH_TIME_NOW, (interval * NSEC_PER_SEC));
	dispatch_source_set_timer(connectionPoolTimer, tt, DISPATCH_TIME_FOREVER, 0);
	
	if (isNewTimer) {
		dispatch_resume(connectionPoolTimer);
	}
}

/**
 * Internal method to handle removing stale connections from the connection pool.
**/
- (void)handleConnectionPoolTimerFire
{
	YDBLogAutoTrace();
	
	NSDate *now = [NSDate date];
	
	BOOL done = NO;
	while ([connectionPoolValues count] > 0 && !done)
	{
		NSTimeInterval interval = [[connectionPoolDates objectAtIndex:0] timeIntervalSinceDate:now] * -1.0;
		
		if ((interval >= connectionPoolLifetime) || (interval < 0))
		{
			sqlite3 *aDb = (sqlite3 *)[[connectionPoolValues objectAtIndex:0] pointerValue];
			
			YDBLogVerbose(@"Closing connection from pool: %p", aDb);
			
			int status = sqlite3_close(aDb);
			if (status != SQLITE_OK)
			{
				YDBLogError(@"Error in sqlite_close: %d %s", status, sqlite3_errmsg(aDb));
			}
			
			[connectionPoolValues removeObjectAtIndex:0];
			[connectionPoolDates removeObjectAtIndex:0];
		}
		else
		{
			done = YES;
		}
	}
	
	[self resetConnectionPoolTimer];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extensions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Registers the extension with the database using the given name.
 * After registration everything works automatically using just the extension name.
 * 
 * The registration process is equivalent to a readwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 *
 * @return
 *     YES if the extension was properly registered.
 *     NO if an error occurred, such as the extensionName is already registered.
 * 
 * @see asyncRegisterExtension:withName:completionBlock:
 * @see asyncRegisterExtension:withName:completionBlock:completionQueue:
**/
- (BOOL)registerExtension:(YapAbstractDatabaseExtension *)extension withName:(NSString *)extensionName
{
	__block BOOL ready = NO;
	
	dispatch_sync(writeQueue, ^{ @autoreleasepool {
		
		ready = [self _registerExtension:extension withName:extensionName];
	}});
	
	return ready;
}

/**
 * Asynchronoulsy starts the extension registration process.
 * After registration everything works automatically using just the extension name.
 * 
 * The registration process is equivalent to a readwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * An optional completion block may be used.
 * If the extension registration was successful then the ready parameter will be YES.
 *
 * The completionBlock will be invoked on the main thread (dispatch_get_main_queue()).
**/
- (void)asyncRegisterExtension:(YapAbstractDatabaseExtension *)extension
                      withName:(NSString *)extensionName
               completionBlock:(void(^)(BOOL ready))completionBlock
{
	[self asyncRegisterExtension:extension
	                    withName:extensionName
	             completionBlock:completionBlock
	             completionQueue:NULL];
}

/**
 * Asynchronoulsy starts the extension registration process.
 * After registration everything works automatically using just the extension name.
 *
 * The registration process is equivalent to a readwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * An optional completion block may be used.
 * If the extension registration was successful then the ready parameter will be YES.
 * 
 * Additionally the dispatch_queue to invoke the completion block may also be specified.
 * If NULL, dispatch_get_main_queue() is automatically used.
**/
- (void)asyncRegisterExtension:(YapAbstractDatabaseExtension *)extension
                      withName:(NSString *)extensionName
               completionBlock:(void(^)(BOOL ready))completionBlock
               completionQueue:(dispatch_queue_t)completionQueue
{
	if (completionQueue == NULL && completionBlock != NULL)
		completionQueue = dispatch_get_main_queue();
	
	dispatch_async(writeQueue, ^{ @autoreleasepool {
		
		BOOL ready = [self _registerExtension:extension withName:extensionName];
		
		if (completionBlock)
		{
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				
				completionBlock(ready);
			}});
		}
	}});
}

/**
 *
**/
- (void)unregisterExtension:(NSString *)extensionName
{
	dispatch_sync(writeQueue, ^{ @autoreleasepool {
		
		[self _unregisterExtension:extensionName];
	}});
}

- (void)asyncUnregisterExtension:(NSString *)extensionName
                 completionBlock:(dispatch_block_t)completionBlock
{
	[self asyncUnregisterExtension:extensionName
	               completionBlock:completionBlock
	               completionQueue:NULL];
}

- (void)asyncUnregisterExtension:(NSString *)extensionName
                 completionBlock:(dispatch_block_t)completionBlock
                 completionQueue:(dispatch_queue_t)completionQueue
{
	if (completionQueue == NULL && completionBlock != NULL)
		completionQueue = dispatch_get_main_queue();
	
	dispatch_async(writeQueue, ^{ @autoreleasepool {
		
		[self _unregisterExtension:extensionName];
		
		if (completionBlock)
		{
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				
				completionBlock();
			}});
		}
	}});
}

/**
 * Internal utility method.
 * Handles lazy creation and destruction of short-lived registrationConnection instance.
 * 
 * @see _registerExtension:withName:
 * @see _unregisterExtension:
**/
- (YapAbstractDatabaseConnection *)registrationConnection
{
	if (registrationConnection == nil)
	{
		registrationConnection = [self newConnection];
		registrationConnection.name = @"YapAbstractDatabase_extensionRegistrationConnection";
		
		NSTimeInterval delayInSeconds = 10.0;
		dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
		dispatch_after(popTime, writeQueue, ^(void){
			
			registrationConnection = nil;
		});
	}
	
	return registrationConnection;
}

/**
 * Internal method that handles extension registration.
 * This method must be invoked on the writeQueue.
**/
- (BOOL)_registerExtension:(YapAbstractDatabaseExtension *)extension withName:(NSString *)extensionName
{
	NSAssert(dispatch_get_specific(IsOnWriteQueueKey), @"Must go through writeQueue.");
	
	if (extension == nil)
	{
		YDBLogError(@"Error registering extension: extension parameter is nil");
		return NO;
	}
	if ([extensionName length] == 0)
	{
		YDBLogError(@"Error registering extension: extensionName parameter is nil or empty string");
		return NO;
	}
	if (![extension supportsDatabase:self])
	{
		YDBLogError(@"Error registering extension: extension doesn't support this type of database");
		return NO;
	}
	if (extension.registeredName != nil)
	{
		YDBLogError(@"Error registering extension: extension is already registered");
		return NO;
	}
	if ([self registeredExtension:extensionName] != nil)
	{
		YDBLogError(@"Error registering extension: extensionName(%@) already registered", extensionName);
		return NO;
	}
	
	extension.registeredName = extensionName;
	
	BOOL result = [[self registrationConnection] registerExtension:extension withName:extensionName];
	if (!result)
	{
		extension.registeredName = nil;
	}
	
	return result;
}

/**
 * Internal method that handles extension unregistration.
 * This method must be invoked on the writeQueue.
**/
- (void)_unregisterExtension:(NSString *)extensionName
{
	NSAssert(dispatch_get_specific(IsOnWriteQueueKey), @"Must go through writeQueue.");
	
	if ([extensionName length] == 0)
	{
		YDBLogError(@"Error unregistering extension: extensionName parameter is nil or empty string");
		return;
	}
	
	YapAbstractDatabaseExtension *extension = [self registeredExtension:extensionName];
	
	[[self registrationConnection] unregisterExtension:extensionName];
	
	extension.registeredName = nil;
}

/**
 * Returns the registered extension with the given name.
**/
- (id)registeredExtension:(NSString *)extensionName
{
	// This method is public
	
	__block YapAbstractDatabaseExtension *result = nil;
	
	dispatch_block_t block = ^{
		
		result = [registeredExtensions objectForKey:extensionName];
	};
	
	if (dispatch_get_specific(IsOnSnapshotQueueKey))
		block();
	else
		dispatch_sync(snapshotQueue, block);
	
	return result;
}

/**
 * Returns all currently registered extensions as a dictionary.
 * The key is the registed name (NSString), and the value is the extension (YapAbstractDatabaseExtension subclass).
**/
- (NSDictionary *)registeredExtensions
{
	// This method is public
	
	__block NSDictionary *extensionsCopy = nil;
	
	dispatch_block_t block = ^{
		
		extensionsCopy = registeredExtensions;
	};
	
	if (dispatch_get_specific(IsOnSnapshotQueueKey))
		block();
	else
		dispatch_sync(snapshotQueue, block);
	
	return extensionsCopy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Snapshot Architecture
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is only accessible from within the snapshotQueue.
 *
 * The snapshot represents when the database was last modified by a read-write transaction.
 * This information isn persisted to the 'yap' database, and is separately held in memory.
 * It serves multiple purposes.
 *
 * First is assists in validation of a connection's cache.
 * When a connection begins a new transaction, it may have items sitting in the cache.
 * However the connection doesn't know if the items are still valid because another connection may have made changes.
 *
 * The snapshot also assists in correcting for a race condition.
 * It order to minimize blocking we allow read-write transactions to commit outside the context
 * of the snapshotQueue. This is because the commit may be a time consuming operation, and we
 * don't want to block read-only transactions during this period. The race condition occurs if a read-only
 * transactions starts in the midst of a read-write commit, and the read-only transaction gets
 * a "yap-level" snapshot that's out of sync with the "sql-level" snapshot. This is easily correctable if caught.
 * Thus we maintain the snapshot in memory, and fetchable via a select query.
 * One represents the "yap-level" snapshot, and the other represents the "sql-level" snapshot.
 *
 * The snapshot is simply a 64-bit integer.
 * It is reset when the YapDatabase instance is initialized,
 * and incremented by each read-write transaction (if changes are actually made).
**/
- (uint64_t)snapshot
{
	if (dispatch_get_specific(IsOnSnapshotQueueKey))
	{
		// Very common case.
		// This method is called on just about every transaction.
		return snapshot;
	}
	else
	{
		// Non-common case.
		// Public access implementation.
		__block uint64_t result = 0;
		
		dispatch_sync(snapshotQueue, ^{
			result = snapshot;
		});
		
		return result;
	}
}

/**
 * This method is only accessible from within the snapshotQueue.
 * 
 * Prior to starting the sqlite commit, the connection must report its changeset to the database.
 * The database will store the changeset, and provide it to other connections if needed (due to a race condition).
 * 
 * The following MUST be in the dictionary:
 *
 * - snapshot : NSNumber with the changeset's snapshot
**/
- (void)notePendingChanges:(NSDictionary *)pendingChangeset fromConnection:(YapAbstractDatabaseConnection *)sender
{
	NSAssert(dispatch_get_specific(IsOnSnapshotQueueKey), @"Must go through snapshotQueue for atomic access.");
	NSAssert([pendingChangeset objectForKey:YapDatabaseSnapshotKey], @"Missing required change key: snapshot");
	
	// The sender is preparing to start the sqlite commit.
	// We save the changeset in advance to handle possible edge cases.
	
	[changesets addObject:pendingChangeset];
	
	YDBLogVerbose(@"Adding pending changeset %@ for database: %@",
	              [[changesets lastObject] objectForKey:YapDatabaseSnapshotKey], self);
}

/**
 * This method is only accessible from within the snapshotQueue.
 *
 * This method is used if a transaction finds itself in a race condition.
 * It should retrieve the database's pending and/or committed changes,
 * and then process them via [connection noteCommittedChanges:].
**/
- (NSArray *)pendingAndCommittedChangesSince:(uint64_t)connectionSnapshot until:(uint64_t)maxSnapshot
{
	NSAssert(dispatch_get_specific(IsOnSnapshotQueueKey), @"Must go through snapshotQueue for atomic access.");
	
	NSMutableArray *relevantChangesets = [NSMutableArray arrayWithCapacity:[changesets count]];
	
	for (NSDictionary *changeset in changesets)
	{
		uint64_t changesetSnapshot = [[changeset objectForKey:YapDatabaseSnapshotKey] unsignedLongLongValue];
		
		if ((changesetSnapshot > connectionSnapshot) && (changesetSnapshot <= maxSnapshot))
		{
			[relevantChangesets addObject:changeset];
		}
	}
	
	return relevantChangesets;
}

/**
 * This method is only accessible from within the snapshotQueue.
 *
 * Upon completion of a readwrite transaction, the connection should report it's changeset to the database.
 * The database will then forward the changes to all other connection's.
 *
 * The following MUST be in the dictionary:
 *
 * - snapshot : NSNumber with the changeset's snapshot
**/
- (void)noteCommittedChanges:(NSDictionary *)changeset fromConnection:(YapAbstractDatabaseConnection *)sender
{
	NSAssert(dispatch_get_specific(IsOnSnapshotQueueKey), @"Must go through snapshotQueue for atomic access.");
	NSAssert([changeset objectForKey:YapDatabaseSnapshotKey], @"Missing required change key: snapshot");
	
	// The sender has finished the sqlite commit, and all data is now written to disk.
	
	// Update the in-memory snapshot,
	// which represents the most recent snapshot of the last committed readwrite transaction.
	
	snapshot = [[changeset objectForKey:YapDatabaseSnapshotKey] unsignedLongLongValue];
	
	// Update registeredExtensions, if changed.
	
	NSDictionary *newRegisteredExtensions = [changeset objectForKey:YapDatabaseRegisteredExtensionsKey];
	if (newRegisteredExtensions)
	{
		registeredExtensions = newRegisteredExtensions;
	}
	
	// Forward the changeset to all other connections so they can perform any needed updates.
	// Generally this means updating the in-memory components such as the cache.
	
	dispatch_group_t group = NULL;
	
	for (YapDatabaseConnectionState *state in connectionStates)
	{
		if (state->connection != sender)
		{
			// Create strong reference (state->connection is weak)
			__strong YapAbstractDatabaseConnection *connection = state->connection;
			
			if (connection)
			{
				if (group == NULL)
					group = dispatch_group_create();
				
				dispatch_group_async(group, connection.connectionQueue, ^{ @autoreleasepool {
					
					[connection noteCommittedChanges:changeset];
				}});
			}
		}
	}
	
	// Schedule block to be executed once all connections have processed the changes.
	
	BOOL isInternalChangeset = (sender == nil);

	dispatch_block_t block = ^{
		
		// All connections have now processed the changes.
		// So we no longer need to retain the changeset in memory.
		
		if (isInternalChangeset)
		{
			YDBLogVerbose(@"Completed internal changeset %@ for database: %@",
			              [changeset objectForKey:YapDatabaseSnapshotKey], self);
		}
		else
		{
			YDBLogVerbose(@"Dropping processed changeset %@ for database: %@",
			              [changeset objectForKey:YapDatabaseSnapshotKey], self);
			
			[changesets removeObjectAtIndex:0];
		}
		
		#if !OS_OBJECT_USE_OBJC
		if (group)
			dispatch_release(group);
		#endif
	};
	
	if (group)
		dispatch_group_notify(group, snapshotQueue, block);
	else
		block();
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Manual Checkpointing
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method should be called whenever the maximum checkpointable snapshot is incremented.
 * That is, the state of every connection is known to the system.
 * And a snaphot cannot be checkpointed until every connection is at or past that snapshot.
 * Thus, we can know the point at which a snapshot becomes checkpointable,
 * and we can thus optimize the checkpoint invocations such that
 * each invocation is able to checkpoint one or more commits.
**/
- (void)asyncCheckpoint:(uint64_t)maxCheckpointableSnapshot
{
	__weak YapAbstractDatabase *weakSelf = self;
	
	dispatch_async(checkpointQueue, ^{ @autoreleasepool {
		
		__strong YapAbstractDatabase *strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		YDBLogVerbose(@"Checkpointing up to snapshot %llu", maxCheckpointableSnapshot);
		
		// We're ready to checkpoint more frames.
		//
		// So we're going to execute a passive checkpoint.
		// That is, without disrupting any connections, we're going to write pages from the WAL into the database.
		// The checkpoint can only write pages from snapshots if all connections are at or beyond the snapshot.
		// Thus, this method is only called by a connection that moves the min snapshot forward.
		
		int frameCount = 0;
		int checkpointCount = 0;
		
		int result = sqlite3_wal_checkpoint_v2(strongSelf->db, "main",
		                                       SQLITE_CHECKPOINT_PASSIVE, &frameCount, &checkpointCount);
		
		// frameCount      = total number of frames in the log file
		// checkpointCount = total number of checkpointed frames
		//                  (including any that were already checkpointed before the function was called)
		
		if (result != SQLITE_OK)
		{
			if (result == SQLITE_BUSY) {
				YDBLogVerbose(@"sqlite3_wal_checkpoint_v2 returned SQLITE_BUSY");
			}
			else {
				YDBLogWarn(@"sqlite3_wal_checkpoint_v2 returned error code: %d", result);
			}
			
			return;// from_block
		}
		
		YDBLogVerbose(@"Post-checkpoint (%llu): frames(%d) checkpointed(%d)",
		              maxCheckpointableSnapshot, frameCount, checkpointCount);
		
		// Have we checkpointed the entire WAL yet?
		
		if (frameCount == checkpointCount)
		{
			// We've checkpointed every single frame.
			// This means the next read-write transaction will reset the WAL (instead of appending to it).
			//
			// However, this will get spoiled if there are active read-only transactions that
			// were started before our checkpoint finished, and continue to exist during the next read-write.
			// It's not a big deal if the occasional read-only transaction happens to spoil the WAL reset.
			// In those cases, the WAL generally gets reset shortly thereafter.
			// Long-lived read transactions are a different case entirely.
			// These transactions spoil it every single time, and could potentially cause the WAL to grow indefinitely.
			// 
			// The solution is to notify active long-lived connections, and tell them to re-begin their transaction
			// on the same snapshot. But this time the sqlite machinery will read directly from the database,
			// and thus unlock the WAL so it can be reset.
			
			dispatch_async(snapshotQueue, ^{
				
				for (YapDatabaseConnectionState *state in connectionStates)
				{
					if (state->yapLevelSharedReadLock &&
					    state->longLivedReadTransaction &&
					    state->lastKnownSnapshot == snapshot)
					{
						[state->connection maybeResetLongLivedReadTransaction];
					}
				}
			});
		}
	}});
}

@end
