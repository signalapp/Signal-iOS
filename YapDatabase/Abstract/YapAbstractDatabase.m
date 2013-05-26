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
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif

/**
 * The database version is stored (via pragma user_version) to sqlite.
 * It is used to represent the version of the userlying architecture of YapDatabase.
 * In the event of future changes to the sqlite underpinnings of YapDatabase,
 * the version can be consulted to allow for proper on-the-fly upgrades.
 * For more information, see the upgradeTable method.
**/
#define YAP_DATABASE_CURRENT_VERION 1

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapAbstractDatabase

/**
 * The default serializer & deserializer use NSCoding (NSKeyedArchiver & NSKeyedUnarchiver).
 * Thus the objects need only support the NSCoding protocol.
**/
+ (NSData *(^)(id object))defaultSerializer
{
	NSData *(^serializer)(id) = ^(id object){
		return [NSKeyedArchiver archivedDataWithRootObject:object];
	};
	
	return serializer;
}

/**
 * The default serializer & deserializer use NSCoding (NSKeyedArchiver & NSKeyedUnarchiver).
 * Thus the objects need only support the NSCoding protocol.
**/
+ (id (^)(NSData *))defaultDeserializer
{
	id (^deserializer)(NSData *) = ^(NSData *data){
		return [NSKeyedUnarchiver unarchiveObjectWithData:data];
	};
	
	return deserializer;
}

/**
 * Property lists ONLY support the following: NSData, NSString, NSArray, NSDictionary, NSDate, and NSNumber.
 * Property lists are highly optimized and are used extensively Apple.
 *
 * Property lists make a good fit when your existing code already uses them,
 * such as replacing NSUserDefaults with a database.
**/
+ (NSData *(^)(id object))propertyListSerializer
{
	NSData *(^serializer)(id) = ^(id object){
		return [NSPropertyListSerialization dataWithPropertyList:object
		                                                  format:NSPropertyListBinaryFormat_v1_0
		                                                 options:NSPropertyListImmutable
		                                                   error:NULL];
	};
	
	return serializer;
}

/**
 * Property lists ONLY support the following: NSData, NSString, NSArray, NSDictionary, NSDate, and NSNumber.
 * Property lists are highly optimized and are used extensively Apple.
 *
 * Property lists make a good fit when your existing code already uses them,
 * such as replacing NSUserDefaults with a database.
**/
+ (id (^)(NSData *))propertyListDeserializer
{
	id (^deserializer)(NSData *) = ^(NSData *data){
		return [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
	};
	
	return deserializer;
}

/**
 * A FASTER serializer than the default, if serializing ONLY a NSDate object.
 * You may want to use timestampSerializer & timestampDeserializer if your metadata is simply an NSDate.
**/
+ (NSData *(^)(id object))timestampSerializer
{
	NSData *(^serializer)(id) = ^NSData *(id object) {
		
		if ([object isKindOfClass:[NSDate class]])
		{
			NSTimeInterval timestamp = [(NSDate *)object timeIntervalSinceReferenceDate];
			
			return [[NSData alloc] initWithBytes:(void *)&timestamp length:sizeof(NSTimeInterval)];
		}
		else
		{
			return [NSKeyedArchiver archivedDataWithRootObject:object];
		}
	};
	
	return serializer;
}

/**
 * A FASTER deserializer than the default, if deserializing data from timestampSerializer.
 * You may want to use timestampSerializer & timestampDeserializer if your metadata is simply an NSDate.
**/
+ (id (^)(NSData *))timestampDeserializer
{
	id (^deserializer)(NSData *) = ^id (NSData *data) {
		
		if ([data length] == sizeof(NSTimeInterval))
		{
			NSTimeInterval timestamp;
			memcpy((void *)&timestamp, [data bytes], sizeof(NSTimeInterval));
			
			return [[NSDate alloc] initWithTimeIntervalSinceReferenceDate:timestamp];
		}
		else
		{
			return [NSKeyedUnarchiver unarchiveObjectWithData:data];
		}
	};
	
	return deserializer;
}

@synthesize databasePath;
@synthesize objectSerializer;
@synthesize objectDeserializer;
@synthesize metadataSerializer;
@synthesize metadataDeserializer;

- (id)initWithPath:(NSString *)inPath
{
	return [self initWithPath:inPath
	         objectSerializer:NULL
	       objectDeserializer:NULL
	       metadataSerializer:NULL
	     metadataDeserializer:NULL];
}

- (id)initWithPath:(NSString *)inPath
        serializer:(NSData *(^)(id object))aSerializer
      deserializer:(id (^)(NSData *))aDeserializer
{
	return [self initWithPath:inPath
	         objectSerializer:aSerializer
	       objectDeserializer:aDeserializer
	       metadataSerializer:aSerializer
	     metadataDeserializer:aDeserializer];
}

- (id)initWithPath:(NSString *)inPath objectSerializer:(NSData *(^)(id object))aObjectSerializer
                                    objectDeserializer:(id (^)(NSData *))aObjectDeserializer
                                    metadataSerializer:(NSData *(^)(id object))aMetadataSerializer
                                  metadataDeserializer:(id (^)(NSData *))aMetadataDeserializer
{
	// First, standardize path.
	// This allows clients to be lazy when passing paths.
	NSString *path = [inPath stringByStandardizingPath];
	
	// Ensure there is only a single database instance per file.
	// However, clients may create as many connections as desired.
	if (![YapDatabaseManager registerDatabaseForPath:path])
	{
		YDBLogError(@"Only a single database instance is allowed per file. "
		            @"However, you may create multiple connections from a single database instance.");
		return nil;
	}
	
	NSData *(^defaultSerializer)(id)    = [[self class] defaultSerializer];
	id (^defaultDeserializer)(NSData *) = [[self class] defaultDeserializer];
	
	if ((self = [super init]))
	{
		databasePath = path;
		
		objectSerializer = aObjectSerializer ? aObjectSerializer : defaultSerializer;
		objectDeserializer = aObjectDeserializer ? aObjectDeserializer : defaultDeserializer;
		
		metadataSerializer = aMetadataSerializer ? aMetadataSerializer : defaultSerializer;
		metadataDeserializer = aMetadataDeserializer ? aMetadataDeserializer : defaultDeserializer;
		
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
			
			if (result)
				YDBLogInfo(@"Database corruption resolved (name=%@)", [path lastPathComponent]);
			else
				YDBLogError(@"Database corruption unresolved (name=%@)", [path lastPathComponent]);
		}
		if (!result)
		{
			return nil;
		}
		
		snapshotQueue = dispatch_queue_create("YapDatabase-Snapshot", NULL);
		writeQueue    = dispatch_queue_create("YapDatabase-Write", NULL);
		
		changesets = [[NSMutableArray alloc] init];
		connectionStates = [[NSMutableArray alloc] init];
		
		extensions = [[NSMutableDictionary alloc] init];
		
		// Mark the snapshotQueue so we can identify it.
		// There are several methods whose use is restricted to within the snapshotQueue.
		
		IsOnSnapshotQueueKey = &IsOnSnapshotQueueKey;
		dispatch_queue_set_specific(snapshotQueue, IsOnSnapshotQueueKey, IsOnSnapshotQueueKey, NULL);
		
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
	
	if (db) {
		sqlite3_close(db);
		db = NULL;
	}
	
	[YapDatabaseManager deregisterDatabaseForPath:databasePath];
	
#if !OS_OBJECT_USE_OBJC
	if (snapshotQueue)
		dispatch_release(snapshotQueue);
	if (writeQueue)
		dispatch_release(writeQueue);
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
	
	int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX;
	
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
	
	// Configure autocheckpointing.
	// Decrease size of WAL from default 1,000 pages to something more mobile friendly.
	sqlite3_wal_autocheckpoint(db, 100);
	
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
	    "CREATE TABLE IF NOT EXISTS \"yap\""
	    " (\"key\" CHAR PRIMARY KEY NOT NULL, "
	    "  \"data\" BLOB"
	    " );";
	
	int status = sqlite3_exec(db, createYapTableStatement, NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Failed creating 'yap' table: %d %s", status, sqlite3_errmsg(db));
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
#pragma mark Upgrade
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Extracts and returns column names of our database.
**/
- (NSArray *)tableColumnNames
{
	sqlite3_stmt *pragmaStatement;
	
	char *stmt = "PRAGMA table_info(database);";
	
	int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &pragmaStatement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error creating pragma table_info statement! %d %s", status, sqlite3_errmsg(db));
		return nil;
	}
	
	NSMutableArray *tableColumnNames = [NSMutableArray array];
	
	while (sqlite3_step(pragmaStatement) == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(pragmaStatement, 1);
		int textSize = sqlite3_column_bytes(pragmaStatement, 1);
		
		NSString *columnName = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		if (columnName)
		{
			[tableColumnNames addObject:columnName];
		}
	}
	
	sqlite3_finalize(pragmaStatement);
	pragmaStatement = NULL;
	
	return tableColumnNames;
}

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
	
	// If user_version is zero, then either:
	// - this is actually version zero
	// - this is version 1 before we started supporting upgrades
	//
	// We can figure it out quite easily by checking the table schema.
	
	if (user_version == 0)
	{
		if ([[self tableColumnNames] containsObject:@"metadata"])
		{
			user_version = 1;
			[self set_user_version:user_version];
		}
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

/**
 * Performs upgrade checks, and implements the upgrade "plumbing" by invoking the appropriate upgrade methods.
 * 
 * To add custom upgrade logic, implement a method named "upgradeTable_X_Y",
 * where X is the previous version, and Y is the new version.
 * For example, upgradeTable_1_2 would be for upgrades from version 1 to version 2 of YapDatabase.
 * 
 * Important: This is for upgrades of the database schema, and low-level operations of YapDatabase.
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
	
	[self writeSnapshotToDatabase];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)writeSnapshotToDatabase
{
	int status;
	sqlite3_stmt *statement;
	
	char *stmt = "INSERT OR REPLACE INTO \"yap\" (\"key\", \"data\") VALUES (?, ?);";
	
	status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating update snapshot statement: %d %s",
		              NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
	}
	else
	{
		NSNumber *number = [NSNumber numberWithUnsignedLongLong:snapshot];
		
		char *key = "snapshot";
		sqlite3_bind_text(statement, 1, key, (int)strlen(key), SQLITE_STATIC);
		
		__attribute__((objc_precise_lifetime)) NSData *data = [NSKeyedArchiver archivedDataWithRootObject:number];
		sqlite3_bind_blob(statement, 2, data.bytes, (int)data.length, SQLITE_STATIC);
		
		status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@: Error executing update snapshot statement': %d %s",
			              NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connections
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is called from newConnection, either above or from a subclass.
**/
- (void)addConnection:(YapAbstractDatabaseConnection *)connection
{
	dispatch_block_t block = ^{ @autoreleasepool {
		
		// Add the connection to the state table
		YapDatabaseConnectionState *state = [[YapDatabaseConnectionState alloc] initWithConnection:connection];
		[connectionStates addObject:state];
		
		YDBLogVerbose(@"Created new connection(%p) for <%@ %p: databaseName=%@, connectionCount=%lu>",
		              connection,
		              [self class], self, [databasePath lastPathComponent], (unsigned long)[connectionStates count]);
	}};
	
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
	
	if (dispatch_get_specific(IsOnSnapshotQueueKey))
		block();
	else
		dispatch_async(snapshotQueue, block);
	
	// Invoke the one-time prepare method, so the connection can perform any needed initialization.
	
	dispatch_async(connection.connectionQueue, ^{ @autoreleasepool {
		
		[connection prepare];
	}});
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
				break;
			else
				index++;
		}
		
		if (index < [connectionStates count])
			[connectionStates removeObjectAtIndex:index];
		
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
#pragma mark Extensions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Registers the extension with the database using the given name.
 * After registration everything works automatically using just the extension name.
 *
 * @return
 *     YES if the extension was properly registered.
 *     NO if an error occurred, such as the extensionName is already registered.
**/
- (BOOL)registerExtension:(YapAbstractDatabaseExtension *)extension withName:(NSString *)extensionName
{
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
	
	__block BOOL result = YES;
	
	dispatch_sync(writeQueue, ^{
		
		// Check to make sure the extensionName is available
		
		dispatch_sync(snapshotQueue, ^{
			
			if ([extensions objectForKey:extensionName] != nil)
			{
				result = NO;
			}
		});
		
		if (!result)
		{
			YDBLogError(@"Error registering extension: The extensionName is already registered.");
			return;
		}
		
		// Prepare the extension (create the table(s) for it and/or any other needed tasks)
		
		result = [[extension class] createTablesForRegisteredName:extensionName database:self sqlite:db error:NULL];
		
		if (!result)
		{
			YDBLogError(@"Error registering extension: Extension reported errors during setup process.");
			return;
		}
		
		// Register the extension
		
		dispatch_sync(snapshotQueue, ^{
			
			[extensions setObject:extension forKey:extensionName];
			[extension setRegisteredName:extensionName];
			
			snapshot++;
			[self writeSnapshotToDatabase];
			
			NSDictionary *changeset = @{
				@"snapshot" : @(snapshot),
				@"registeredExtensions" : [extensions copy]
			};
			
			[self noteCommittedChanges:changeset fromConnection:nil];
		});
	});
	
	return result;
}

/**
 * Returns the registered extension with the given name.
**/
- (id)registeredExtension:(NSString *)extensionName
{
	// This method is public
	
	__block YapAbstractDatabaseExtension *result = nil;
	
	dispatch_block_t block = ^{
		
		result = [extensions objectForKey:extensionName];
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
		
		extensionsCopy = [extensions copy];
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
	NSAssert(dispatch_get_specific(IsOnSnapshotQueueKey), @"Must go through snapshotQueue for atomic access.");
	
	return snapshot;
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
	NSAssert([pendingChangeset objectForKey:@"snapshot"], @"Missing required change key: snapshot");
	
	// The sender is preparing to start the sqlite commit.
	// We save the changeset in advance to handle possible edge cases.
	
	[changesets addObject:pendingChangeset];
	
	YDBLogVerbose(@"Adding pending changeset %@ for database: %@",
	              [[changesets lastObject] objectForKey:@"snapshot"], self);
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
		uint64_t changesetSnapshot = [[changeset objectForKey:@"snapshot"] unsignedLongLongValue];
		
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
	NSAssert([changeset objectForKey:@"snapshot"], @"Missing required change key: snapshot");
	
	// The sender has finished the sqlite commit, and all data is now written to disk.
	
	// Update the in-memory snapshot,
	// which represents the most recent snapshot of the last committed readwrite transaction.
	
	snapshot = [[changeset objectForKey:@"snapshot"] unsignedLongLongValue];
	
	// Forward the changeset to all other connections so they can perform any needed updates.
	// Generally this means updating the in-memory components such as the cache.
	
	dispatch_group_t group = NULL;
	
	for (YapDatabaseConnectionState *state in connectionStates)
	{
		if (state->connection != sender)
		{
			YapAbstractDatabaseConnection *connection = state->connection;
			
			if (group == NULL)
				group = dispatch_group_create();
			
			dispatch_group_async(group, connection.connectionQueue, ^{ @autoreleasepool {
				
				[connection noteCommittedChanges:changeset];
			}});
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
			              [changeset objectForKey:@"snapshot"], self);
		}
		else
		{
			YDBLogVerbose(@"Dropping processed changeset %@ for database: %@",
			              [changeset objectForKey:@"snapshot"], self);
			
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

@end
