#import "YapDatabase.h"
#import "YapDatabaseAtomic.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapCollectionKey.h"
#import "YapDatabaseManager.h"
#import "YapDatabaseConnectionState.h"
#import "YapDatabaseLogging.h"
#import "YapDatabaseString.h"

#import "sqlite3.h"

#import <mach/mach_time.h>
#import <stdatomic.h>

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if robbie_hanson
  static const int ydbLogLevel = YDB_LOG_LEVEL_INFO;
#elif DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)

/**
 * YapDatabaseClosedNotification & corresponding keys.
**/

NSString *const YapDatabaseClosedNotification = @"YapDatabaseClosedNotification";

NSString *const YapDatabasePathKey    = @"databasePath";
NSString *const YapDatabasePathWalKey = @"databasePath_wal";
NSString *const YapDatabasePathShmKey = @"databasePath_shm";

/**
 * YapDatabaseModifiedNotification & corresponding keys.
**/

NSString *const YapDatabaseModifiedNotification = @"YapDatabaseModifiedNotification";
NSString *const YapDatabaseModifiedExternallyNotification = @"YapDatabaseModifiedExternallyNotification";

NSString *const YapDatabaseSnapshotKey   = @"snapshot";
NSString *const YapDatabaseConnectionKey = @"connection";
NSString *const YapDatabaseExtensionsKey = @"extensions";
NSString *const YapDatabaseCustomKey     = @"custom";

NSString *const YapDatabaseObjectChangesKey      = @"objectChanges";
NSString *const YapDatabaseMetadataChangesKey    = @"metadataChanges";
NSString *const YapDatabaseRemovedKeysKey        = @"removedKeys";
NSString *const YapDatabaseRemovedCollectionsKey = @"removedCollections";
NSString *const YapDatabaseRemovedRowidsKey      = @"removedRowids";
NSString *const YapDatabaseAllKeysRemovedKey     = @"allKeysRemoved";
NSString *const YapDatabaseModifiedExternallyKey = @"modifiedExternally";

NSString *const YapDatabaseRegisteredExtensionsKey   = @"registeredExtensions";
NSString *const YapDatabaseRegisteredMemoryTablesKey = @"registeredMemoryTables";
NSString *const YapDatabaseExtensionsOrderKey        = @"extensionsOrder";
NSString *const YapDatabaseExtensionDependenciesKey  = @"extensionDependencies";
NSString *const YapDatabaseNotificationKey           = @"notification";

/**
 * ConnectionPool value dictionary keys.
**/

static NSString *const YDBConnectionPoolValueKey_db        = @"db";
static NSString *const YDBConnectionPoolValueKey_main_file = @"main_file";
static NSString *const YDBConnectionPoolValueKey_wal_file  = @"wal_file";

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


static int connectionBusyHandler(void *ptr, int count) {
    YapDatabase* currentDatabase = (__bridge YapDatabase*)ptr;
    
    usleep(50*1000); // sleep 50ms
    
    if (count % 4 == 1) { // log every 4th attempt but not the first one
        YDBLogWarn(@"Cannot obtain busy lock on SQLite from database (%p), is another process locking the database? Retrying in 50ms...", currentDatabase);
    }
    
    return 1;
}

@implementation YapDatabase {
@private
	
	YapDatabaseOptions *options;
	
	sqlite3 *db; // Used for setup & checkpoints
	
	NSMutableArray *changesets;
	uint64_t snapshot;
	
	dispatch_queue_t internalQueue;
	dispatch_queue_t checkpointQueue;
	
	YapDatabaseConnectionConfig *connectionDefaults;
	
	NSDictionary *registeredExtensions;
	NSDictionary *registeredMemoryTables;
	
	NSArray *extensionsOrder;
	NSDictionary *extensionDependencies;
	
	YapDatabaseConnection *registrationConnection;
	
	NSUInteger maxConnectionPoolCount;
	NSTimeInterval connectionPoolLifetime;
	dispatch_source_t connectionPoolTimer;
	NSMutableArray *connectionPoolValues;
	NSMutableArray *connectionPoolDates;
	
	NSString *sqliteVersion;
	uint64_t pageSize;
	
	atomic_flag pendingPassiveCheckpoint;
	atomic_flag pendingAggressiveCheckpoint;
	atomic_bool aggressiveCheckpointEnabled;
}

/**
 * The default serializer & deserializer use NSCoding (NSKeyedArchiver & NSKeyedUnarchiver).
 * Thus the objects need only support the NSCoding protocol.
**/
+ (YapDatabaseSerializer)defaultSerializer
{
	return ^ NSData* (NSString __unused *collection, NSString __unused *key, id object){
		return [NSKeyedArchiver archivedDataWithRootObject:object];
	};
}

/**
 * The default serializer & deserializer use NSCoding (NSKeyedArchiver & NSKeyedUnarchiver).
 * Thus the objects need only support the NSCoding protocol.
**/
+ (YapDatabaseDeserializer)defaultDeserializer
{
	return ^ id (NSString __unused *collection, NSString __unused *key, NSData *data){
		return data && data.length > 0 ? [NSKeyedUnarchiver unarchiveObjectWithData:data] : nil;
	};
}

/**
 * Property lists ONLY support the following: NSData, NSString, NSArray, NSDictionary, NSDate, and NSNumber.
 * Property lists are highly optimized and are used extensively by Apple.
 *
 * Property lists make a good fit when your existing code already uses them,
 * such as replacing NSUserDefaults with a database.
**/
+ (YapDatabaseSerializer)propertyListSerializer
{
	return ^ NSData* (NSString __unused *collection, NSString __unused *key, id object){
		return [NSPropertyListSerialization dataWithPropertyList:object
		                                                  format:NSPropertyListBinaryFormat_v1_0
		                                                 options:NSPropertyListImmutable
		                                                   error:NULL];
	};
}

/**
 * Property lists ONLY support the following: NSData, NSString, NSArray, NSDictionary, NSDate, and NSNumber.
 * Property lists are highly optimized and are used extensively by Apple.
 *
 * Property lists make a good fit when your existing code already uses them,
 * such as replacing NSUserDefaults with a database.
**/
+ (YapDatabaseDeserializer)propertyListDeserializer
{
	return ^ id (NSString __unused *collection, NSString __unused *key, NSData *data){
		return [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
	};
}

/**
 * A FASTER serializer than the default, if serializing ONLY a NSDate object.
 * You may want to use timestampSerializer & timestampDeserializer if your metadata is simply an NSDate.
**/
+ (YapDatabaseSerializer)timestampSerializer
{
	return ^ NSData* (NSString __unused *collection, NSString __unused *key, id object) {
		
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
}

/**
 * A FASTER deserializer than the default, if deserializing data from timestampSerializer.
 * You may want to use timestampSerializer & timestampDeserializer if your metadata is simply an NSDate.
**/
+ (YapDatabaseDeserializer)timestampDeserializer
{
	return ^ id (NSString __unused *collection, NSString __unused *key, NSData *data) {
		
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
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize databasePath = databasePath;
@dynamic databasePath_wal;
@dynamic databasePath_shm;

@synthesize objectSerializer = objectSerializer;
@synthesize objectDeserializer = objectDeserializer;

@synthesize metadataSerializer = metadataSerializer;
@synthesize metadataDeserializer = metadataDeserializer;

@synthesize objectPreSanitizer = objectPreSanitizer;
@synthesize objectPostSanitizer = objectPostSanitizer;

@synthesize metadataPreSanitizer = metadataPreSanitizer;
@synthesize metadataPostSanitizer = metadataPostSanitizer;

@dynamic options;
@dynamic sqliteVersion;

- (NSString *)databasePath_wal
{
	return [databasePath stringByAppendingString:@"-wal"];
}

- (NSString *)databasePath_shm
{
	return [databasePath stringByAppendingString:@"-shm"];
}

- (YapDatabaseOptions *)options
{
	return [options copy];
}

- (NSString *)sqliteVersion
{
	__block NSString *result = nil;
	
	dispatch_sync(snapshotQueue, ^{
		result = sqliteVersion;
	});
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)initWithPath:(NSString *)inPath
{
	return [self initWithPath:inPath
	         objectSerializer:NULL
	       objectDeserializer:NULL
	       metadataSerializer:NULL
	     metadataDeserializer:NULL
	       objectPreSanitizer:NULL
	      objectPostSanitizer:NULL
	     metadataPreSanitizer:NULL
	    metadataPostSanitizer:NULL
	                  options:nil];
}

- (id)initWithPath:(NSString *)inPath
           options:(nullable YapDatabaseOptions *)inOptions
{
	return [self initWithPath:inPath
	         objectSerializer:NULL
	       objectDeserializer:NULL
	       metadataSerializer:NULL
	     metadataDeserializer:NULL
	       objectPreSanitizer:NULL
	      objectPostSanitizer:NULL
	     metadataPreSanitizer:NULL
	    metadataPostSanitizer:NULL
	                  options:inOptions];
}

- (id)initWithPath:(NSString *)inPath
        serializer:(YapDatabaseSerializer)inSerializer
      deserializer:(YapDatabaseDeserializer)inDeserializer
{
	return [self initWithPath:inPath
	         objectSerializer:inSerializer
	       objectDeserializer:inDeserializer
	       metadataSerializer:inSerializer
	     metadataDeserializer:inDeserializer
	       objectPreSanitizer:NULL
	      objectPostSanitizer:NULL
	     metadataPreSanitizer:NULL
	    metadataPostSanitizer:NULL
	                  options:nil];
}

- (id)initWithPath:(NSString *)inPath
        serializer:(YapDatabaseSerializer)inSerializer
      deserializer:(YapDatabaseDeserializer)inDeserializer
           options:(YapDatabaseOptions *)inOptions
{
	return [self initWithPath:inPath
	         objectSerializer:inSerializer
	       objectDeserializer:inDeserializer
	       metadataSerializer:inSerializer
	     metadataDeserializer:inDeserializer
	       objectPreSanitizer:NULL
	      objectPostSanitizer:NULL
	     metadataPreSanitizer:NULL
	    metadataPostSanitizer:NULL
	                  options:inOptions];
}

- (id)initWithPath:(NSString *)inPath
        serializer:(YapDatabaseSerializer)inSerializer
      deserializer:(YapDatabaseDeserializer)inDeserializer
      preSanitizer:(YapDatabasePreSanitizer)inPreSanitizer
     postSanitizer:(YapDatabasePostSanitizer)inPostSanitizer
           options:(YapDatabaseOptions *)inOptions
{
	return [self initWithPath:inPath
	         objectSerializer:inSerializer
	       objectDeserializer:inDeserializer
	       metadataSerializer:inSerializer
	     metadataDeserializer:inDeserializer
	       objectPreSanitizer:inPreSanitizer
	      objectPostSanitizer:inPostSanitizer
	     metadataPreSanitizer:inPreSanitizer
	    metadataPostSanitizer:inPostSanitizer
	                  options:inOptions];
}

- (id)initWithPath:(NSString *)inPath objectSerializer:(YapDatabaseSerializer)inObjectSerializer
                                    objectDeserializer:(YapDatabaseDeserializer)inObjectDeserializer
                                    metadataSerializer:(YapDatabaseSerializer)inMetadataSerializer
                                  metadataDeserializer:(YapDatabaseDeserializer)inMetadataDeserializer
{
	return [self initWithPath:inPath
	         objectSerializer:inObjectSerializer
	       objectDeserializer:inObjectDeserializer
	       metadataSerializer:inMetadataSerializer
	     metadataDeserializer:inMetadataDeserializer
	       objectPreSanitizer:NULL
	      objectPostSanitizer:NULL
	     metadataPreSanitizer:NULL
	    metadataPostSanitizer:NULL
	                  options:nil];
}

- (id)initWithPath:(NSString *)inPath objectSerializer:(YapDatabaseSerializer)inObjectSerializer
                                    objectDeserializer:(YapDatabaseDeserializer)inObjectDeserializer
                                    metadataSerializer:(YapDatabaseSerializer)inMetadataSerializer
                                  metadataDeserializer:(YapDatabaseDeserializer)inMetadataDeserializer
                                               options:(YapDatabaseOptions *)inOptions
{
	return [self initWithPath:inPath
	         objectSerializer:inObjectSerializer
	       objectDeserializer:inObjectDeserializer
	       metadataSerializer:inMetadataSerializer
	     metadataDeserializer:inMetadataDeserializer
	       objectPreSanitizer:NULL
	      objectPostSanitizer:NULL
	     metadataPreSanitizer:NULL
	    metadataPostSanitizer:NULL
	                  options:inOptions];
}

- (id)initWithPath:(NSString *)inPath objectSerializer:(YapDatabaseSerializer)inObjectSerializer
                                    objectDeserializer:(YapDatabaseDeserializer)inObjectDeserializer
                                    metadataSerializer:(YapDatabaseSerializer)inMetadataSerializer
                                  metadataDeserializer:(YapDatabaseDeserializer)inMetadataDeserializer
                                    objectPreSanitizer:(YapDatabasePreSanitizer)inObjectPreSanitizer
                                   objectPostSanitizer:(YapDatabasePostSanitizer)inObjectPostSanitizer
                                  metadataPreSanitizer:(YapDatabasePreSanitizer)inMetadataPreSanitizer
                                 metadataPostSanitizer:(YapDatabasePostSanitizer)inMetadataPostSanitizer
                                               options:(YapDatabaseOptions *)inOptions
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
		options = inOptions ? [inOptions copy] : [[YapDatabaseOptions alloc] init];
		
		__block BOOL isNewDatabaseFile = ![[NSFileManager defaultManager] fileExistsAtPath:databasePath];
		
		BOOL(^openConfigCreate)(void) = ^BOOL (void) { @autoreleasepool {
		
			BOOL result = YES;
			
			if (result) result = [self openDatabase];
#ifdef SQLITE_HAS_CODEC
            if (result) result = [self configureEncryptionForDatabase:db];
#endif
			if (result) result = [self configureDatabase:isNewDatabaseFile];
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
			// One possibility is if the database file has become corrupt.
			
			if (options.corruptAction == YapDatabaseCorruptAction_Fail)
			{
				// Fail - do not try to resolve
			}
			else if (options.corruptAction == YapDatabaseCorruptAction_Rename)
			{
				// Try to rename the corrupt database file.
				
				BOOL renamed = NO;
				BOOL failed = NO;
				
				NSString *newDatabasePath = nil;
				int i = 0;
				
				do
				{
					NSString *extension = [NSString stringWithFormat:@"%d.corrupt", i];
					newDatabasePath = [databasePath stringByAppendingPathExtension:extension];
					
					if ([[NSFileManager defaultManager] fileExistsAtPath:newDatabasePath])
					{
						i++;
					}
					else
					{
						NSError *error = nil;
						renamed = [[NSFileManager defaultManager] moveItemAtPath:databasePath
						                                                  toPath:newDatabasePath
						                                                   error:&error];
						if (!renamed)
						{
							failed = YES;
							YDBLogError(@"Error renaming corrupt database file: (%@ -> %@) %@",
							            [databasePath lastPathComponent], [newDatabasePath lastPathComponent], error);
						}
					}
					
				} while (i < INT_MAX && !renamed && !failed);
				
				if (renamed)
				{
					isNewDatabaseFile = YES;
					result = openConfigCreate();
					if (result) {
						YDBLogInfo(@"Database corruption resolved. Renamed corrupt file. (newDB=%@) (corruptDB=%@)",
						           [databasePath lastPathComponent], [newDatabasePath lastPathComponent]);
					}
					else {
						YDBLogError(@"Database corruption unresolved. (name=%@)", [databasePath lastPathComponent]);
					}
				}
				
			}
			else // if (options.corruptAction == YapDatabaseCorruptAction_Delete)
			{
				// Try to delete the corrupt database file.
				
				NSError *error = nil;
				BOOL deleted = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
				
				if (deleted)
				{
					isNewDatabaseFile = YES;
					result = openConfigCreate();
					if (result) {
						YDBLogInfo(@"Database corruption resolved. Deleted corrupt file. (name=%@)",
						                                                          [databasePath lastPathComponent]);
					}
					else {
						YDBLogError(@"Database corruption unresolved. (name=%@)", [databasePath lastPathComponent]);
					}
				}
				else
				{
					YDBLogError(@"Error deleting corrupt database file: %@", error);
				}
			}
		}
		if (!result)
		{
			return nil;
		}
		
		// Configure VFS shim (for database connections).
		
		yap_vfs_shim_name = [NSString stringWithFormat:@"yap_vfs_shim_%@", [[NSUUID UUID] UUIDString]];
		yap_vfs_shim_register([yap_vfs_shim_name UTF8String], NULL, &yap_vfs_shim);
		
		// Initialize variables
		
		internalQueue   = dispatch_queue_create("YapDatabase-Internal", NULL);
		checkpointQueue = dispatch_queue_create("YapDatabase-Checkpoint", NULL);
		snapshotQueue   = dispatch_queue_create("YapDatabase-Snapshot", NULL);
		writeQueue      = dispatch_queue_create("YapDatabase-Write", NULL);
		
		changesets = [[NSMutableArray alloc] init];
		connectionStates = [[NSMutableArray alloc] init];
		
		connectionDefaults = [[YapDatabaseConnectionConfig alloc] init];
		
		registeredExtensions = [[NSDictionary alloc] init];
		registeredMemoryTables = [[NSDictionary alloc] init];
		
		extensionDependencies = [[NSDictionary alloc] init];
		extensionsOrder = [[NSArray alloc] init];
		
		maxConnectionPoolCount = DEFAULT_MAX_CONNECTION_POOL_COUNT;
		connectionPoolLifetime = DEFAULT_CONNECTION_POOL_LIFETIME;
		
		YapDatabaseSerializer defaultSerializer     = nil;
		YapDatabaseDeserializer defaultDeserializer = nil;
		
		if (!inObjectSerializer || !inMetadataSerializer)
			defaultSerializer = [[self class] defaultSerializer];
		
		if (!inObjectDeserializer || !inMetadataDeserializer)
			defaultDeserializer = [[self class] defaultDeserializer];
		
		objectSerializer = (YapDatabaseSerializer)[inObjectSerializer copy] ?: defaultSerializer;
		objectDeserializer = (YapDatabaseDeserializer)[inObjectDeserializer copy] ?: defaultDeserializer;
		
		metadataSerializer = (YapDatabaseSerializer)[inMetadataSerializer copy] ?: defaultSerializer;
		metadataDeserializer = (YapDatabaseDeserializer)[inMetadataDeserializer copy] ?: defaultDeserializer;
		
		objectPreSanitizer = (YapDatabasePreSanitizer)[inObjectPreSanitizer copy];
		objectPostSanitizer = (YapDatabasePostSanitizer)[inObjectPostSanitizer copy];
		
		metadataPreSanitizer = (YapDatabasePreSanitizer)[inMetadataPreSanitizer copy];
		metadataPostSanitizer = (YapDatabasePostSanitizer)[inMetadataPostSanitizer copy];
		
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
	
	NSDictionary *userInfo = @{
		YapDatabasePathKey    : self.databasePath     ?: @"",
		YapDatabasePathWalKey : self.databasePath_wal ?: @"",
		YapDatabasePathShmKey : self.databasePath_shm ?: @""
	};
	NSNotification *notification =
	  [NSNotification notificationWithName:YapDatabaseClosedNotification
	                                object:nil // Cannot retain self within dealloc method
	                              userInfo:userInfo];
	
	while ([connectionPoolValues count] > 0)
	{
		NSDictionary *value = [connectionPoolValues objectAtIndex:0];
		
		sqlite3 *aDb = (sqlite3 *)[[value objectForKey:YDBConnectionPoolValueKey_db] pointerValue];
		
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
	if (yap_vfs_shim) {
		yap_vfs_shim_unregister(&yap_vfs_shim);
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
	
	dispatch_async(dispatch_get_main_queue(), ^{
		
		[[NSNotificationCenter defaultCenter] postNotification:notification];
	});
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
		// One possibility is if the database file has become corrupt.
		
		// Sometimes the open function returns a db to allow us to query it for the error message.
		// The openConfigCreate block will close it for us.
		if (db) {
			YDBLogError(@"Error opening database: %d %s", status, sqlite3_errmsg(db));
		}
		else {
			YDBLogError(@"Error opening database: %d", status);
		}
		
		return NO;
	}
    // Add a busy handler if we are in multiprocess mode
    if (options.enableMultiProcessSupport) {
        sqlite3_busy_handler(db, connectionBusyHandler, (__bridge void *)(self));
    }
	
	return YES;
}

/**
 * Configures the database connection.
 * This mainly means enabling WAL mode, and configuring the auto-checkpoint.
**/
- (BOOL)configureDatabase:(BOOL)isNewDatabaseFile
{
	int status;
	
	// Set mandatory pragmas
	
	if (isNewDatabaseFile && (options.pragmaPageSize > 0))
	{
		NSString *pragma_page_size =
		  [NSString stringWithFormat:@"PRAGMA page_size = %ld;", (long)options.pragmaPageSize];
		
		status = sqlite3_exec(db, [pragma_page_size UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error setting PRAGMA page_size: %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	status = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error setting PRAGMA journal_mode: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	if (isNewDatabaseFile)
	{
		status = sqlite3_exec(db, "PRAGMA auto_vacuum = FULL; VACUUM;", NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error setting PRAGMA auto_vacuum: %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	// Set synchronous to normal for THIS sqlite instance.
	//
	// This does NOT affect normal connections.
	// That is, this does NOT affect YapDatabaseConnection instances.
	// The sqlite connections of normal YapDatabaseConnection instances will follow the set pragmaSynchronous value.
	//
	// The reason we hardcode normal for this sqlite instance is because
	// it's only used to write the initial snapshot value.
	// And this doesn't need to be durable, as it is initialized to zero everytime.
	//
	// (This sqlite db is also used to perform checkpoints.
	//  But a normal value won't affect these operations,
	//  as they will perform sync operations whether the connection is normal or full.)
	
	status = sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error setting PRAGMA synchronous: %d %s", status, sqlite3_errmsg(db));
		// This isn't critical, so we can continue.
	}
	
	// Set journal_size_imit.
	//
	// We only need to do set this pragma for THIS connection,
	// because it is the only connection that performs checkpoints.
	
	NSString *pragma_journal_size_limit =
	  [NSString stringWithFormat:@"PRAGMA journal_size_limit = %ld;", (long)options.pragmaJournalSizeLimit];
	
	status = sqlite3_exec(db, [pragma_journal_size_limit UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error setting PRAGMA journal_size_limit: %d %s", status, sqlite3_errmsg(db));
		// This isn't critical, so we can continue.
	}
	
	// Set mmap_size (if needed).
	//
	// This configures memory mapped I/O.
	
	if (options.pragmaMMapSize > 0)
	{
		NSString *pragma_mmap_size =
		  [NSString stringWithFormat:@"PRAGMA mmap_size = %ld;", (long)options.pragmaMMapSize];
		
		status = sqlite3_exec(db, [pragma_mmap_size UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error setting PRAGMA mmap_size: %d %s", status, sqlite3_errmsg(db));
			// This isn't critical, so we can continue.
		}
	}
	
	// Disable autocheckpointing.
	//
	// YapDatabase has its own optimized checkpointing algorithm built-in.
	// It knows the state of every active connection for the database,
	// so it can invoke the checkpoint methods at the precise time in which a checkpoint can be most effective.
	
	sqlite3_wal_autocheckpoint(db, 0);
	
	return YES;
}


#ifdef SQLITE_HAS_CODEC
/**
 * Configures database encryption via SQLCipher.
**/
- (BOOL)configureEncryptionForDatabase:(sqlite3 *)sqlite
{
    if (options.cipherKeyBlock)
	{
		NSData *keyData = options.cipherKeyBlock();
		
		if (keyData == nil)
		{
			NSAssert(NO, @"YapDatabaseOptions.cipherKeyBlock cannot return nil!");
			return NO;
		}
		
        //Setting the PBKDF2 default iteration number (this will have effect next time database is opened)
        if (options.cipherDefaultkdfIterNumber > 0) {
            char *errorMsg;
            NSString *pragmaCommand = [NSString stringWithFormat:@"PRAGMA cipher_default_kdf_iter = %lu", (unsigned long)options.cipherDefaultkdfIterNumber];
            if (sqlite3_exec(sqlite, [pragmaCommand UTF8String], NULL, NULL, &errorMsg) != SQLITE_OK)
            {
                YDBLogError(@"failed to set database cipher_default_kdf_iter: %s", errorMsg);
                return NO;
            }
        }
        
        //Setting the PBKDF2 iteration number
        if (options.kdfIterNumber > 0) {
            char *errorMsg;
            NSString *pragmaCommand = [NSString stringWithFormat:@"PRAGMA kdf_iter = %lu", (unsigned long)options.kdfIterNumber];
            if (sqlite3_exec(sqlite, [pragmaCommand UTF8String], NULL, NULL, &errorMsg) != SQLITE_OK)
            {
                YDBLogError(@"failed to set database kdf_iter: %s", errorMsg);
                return NO;
            }
        }
        
        //Setting the encrypted database page size
        if (options.cipherPageSize > 0) {
            char *errorMsg;
            NSString *pragmaCommand = [NSString stringWithFormat:@"PRAGMA cipher_page_size = %lu", (unsigned long)options.cipherPageSize];
            if (sqlite3_exec(sqlite, [pragmaCommand UTF8String], NULL, NULL, &errorMsg) != SQLITE_OK)
            {
                YDBLogError(@"failed to set database cipher_page_size: %s", errorMsg);
                return NO;
            }
        }
        
		int status = sqlite3_key(sqlite, [keyData bytes], (int)[keyData length]);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error setting SQLCipher key: %d %s", status, sqlite3_errmsg(sqlite));
			return NO;
		}
	}
	
	return YES;
}
#endif

/**
 * Creates the database tables we need:
 * 
 * - yap2      : stores snapshot and metadata for extensions
 * - database2 : stores collection/key/value/metadata rows
**/
- (BOOL)createTables
{
	int status;
	
	char *createYapTableStatement =
	    "CREATE TABLE IF NOT EXISTS \"yap2\""
	    " (\"extension\" CHAR NOT NULL, "
	    "  \"key\" CHAR NOT NULL, "
	    "  \"data\" BLOB, "
	    "  PRIMARY KEY (\"extension\", \"key\")"
	    " );";
	
	status = sqlite3_exec(db, createYapTableStatement, NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Failed creating 'yap2' table: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	char *createDatabaseTableStatement =
	    "CREATE TABLE IF NOT EXISTS \"database2\""
	    " (\"rowid\" INTEGER PRIMARY KEY,"
	    "  \"collection\" CHAR NOT NULL,"
	    "  \"key\" CHAR NOT NULL,"
	    "  \"data\" BLOB,"
	    "  \"metadata\" BLOB"
	    " );";
	
	status = sqlite3_exec(db, createDatabaseTableStatement, NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Failed creating 'database2' table: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	char *createIndexStatement =
	    "CREATE UNIQUE INDEX IF NOT EXISTS \"true_primary_key\" ON \"database2\" ( \"collection\", \"key\" );";
	
	status = sqlite3_exec(db, createIndexStatement, NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Failed creating index on 'database2' table: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSString *)sqliteVersionUsing:(sqlite3 *)aDb
{
	sqlite3_stmt *statement;
	
	int status = sqlite3_prepare_v2(aDb, "SELECT sqlite_version();", -1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating statement! %d %s", THIS_METHOD, status, sqlite3_errmsg(aDb));
		return nil;
	}
	
	NSString *version = nil;
	
	status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(statement, SQLITE_COLUMN_START);
		int textSize = sqlite3_column_bytes(statement, SQLITE_COLUMN_START);
		
		version = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
	}
	else
	{
		YDBLogError(@"%@: Error executing statement! %d %s", THIS_METHOD, status, sqlite3_errmsg(aDb));
	}
	
	sqlite3_finalize(statement);
	statement = NULL;
	
	return version;
}

+ (int64_t)pragma:(NSString *)pragmaSetting using:(sqlite3 *)aDb
{
	if (pragmaSetting == nil) return -1;
	
	sqlite3_stmt *statement;
	NSString *pragma = [NSString stringWithFormat:@"PRAGMA %@;", pragmaSetting];
	
	int status = sqlite3_prepare_v2(aDb, [pragma UTF8String], -1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating statement! %d %s", THIS_METHOD, status, sqlite3_errmsg(aDb));
		return NO;
	}
	
	int64_t result = -1;
	
	status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = sqlite3_column_int64(statement, SQLITE_COLUMN_START);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@: Error executing statement! %d %s", THIS_METHOD, status, sqlite3_errmsg(aDb));
	}
	
	sqlite3_finalize(statement);
	statement = NULL;
	
	return result;
}

+ (NSString *)pragmaValueForSynchronous:(int64_t)synchronous
{
	switch(synchronous)
	{
		case 0 : return @"OFF";
		case 1 : return @"NORMAL";
		case 2 : return @"FULL";
		default: return @"UNKNOWN";
	}
}

+ (NSString *)pragmaValueForAutoVacuum:(int64_t)auto_vacuum
{
	switch(auto_vacuum)
	{
		case 0 : return @"NONE";
		case 1 : return @"FULL";
		case 2 : return @"INCREMENTAL";
		default: return @"UNKNOWN";
	}
}

/**
 * Returns whether or not the given table exists.
**/
+ (BOOL)tableExists:(NSString *)tableName using:(sqlite3 *)aDb
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
	
	sqlite3_bind_text(statement, SQLITE_BIND_START, [tableName UTF8String], -1, SQLITE_TRANSIENT);
	
	status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		int count = sqlite3_column_int(statement, SQLITE_COLUMN_START);
		
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

+ (NSArray *)tableNamesUsing:(sqlite3 *)aDb
{
	sqlite3_stmt *statement;
	char *stmt = "SELECT name FROM sqlite_master WHERE type = 'table';";
	
	int status = sqlite3_prepare_v2(aDb, stmt, (int)strlen(stmt)+1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating statement! %d %s", THIS_METHOD, status, sqlite3_errmsg(aDb));
		return nil;
	}
	
	NSMutableArray *tableNames = [NSMutableArray array];
	
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(statement, SQLITE_COLUMN_START);
		int textSize = sqlite3_column_bytes(statement, SQLITE_COLUMN_START);
		
		NSString *tableName = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		if (tableName) {
			[tableNames addObject:tableName];
		}
		
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@: Error executing statement! %d %s", THIS_METHOD, status, sqlite3_errmsg(aDb));
	}
	
	sqlite3_finalize(statement);
	statement = NULL;
	
	return tableNames;
}

/**
 * Extracts and returns column names from the given table in the database.
**/
+ (NSArray *)columnNamesForTable:(NSString *)tableName using:(sqlite3 *)aDb
{
	if (tableName == nil) return nil;
	
	sqlite3_stmt *statement;
	NSString *pragma = [NSString stringWithFormat:@"PRAGMA table_info('%@');", tableName];
	
	int status = sqlite3_prepare_v2(aDb, [pragma UTF8String], -1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating statement! %d %s", THIS_METHOD, status, sqlite3_errmsg(aDb));
		return nil;
	}
	
	NSMutableArray *tableColumnNames = [NSMutableArray array];
	
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		// cid|name|type|notnull|dflt|value|pk
		// 0  |1   |2   |3      |4   |5    |6
		
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

/**
 * Extracts and returns column names & affinity for the given table in the database.
 * The dictionary format is:
 *
 * key:(NSString *)columnName -> value:(NSString *)affinity
**/
+ (NSDictionary *)columnNamesAndAffinityForTable:(NSString *)tableName using:(sqlite3 *)aDb
{
	if (tableName == nil) return nil;
	
	sqlite3_stmt *statement;
	NSString *pragma = [NSString stringWithFormat:@"PRAGMA table_info('%@');", tableName];
	
	int status = sqlite3_prepare_v2(aDb, [pragma UTF8String], -1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating statement! %d %s", THIS_METHOD, status, sqlite3_errmsg(aDb));
		return nil;
	}
	
	NSMutableDictionary *columns = [NSMutableDictionary dictionary];
	
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		// cid|name|type|notnull|dflt|value|pk
		// 0  |1   |2   |3      |4   |5    |6
		
		const unsigned char *_name = sqlite3_column_text(statement, 1);
		int _nameSize = sqlite3_column_bytes(statement, 1);
		
		const unsigned char *_type = sqlite3_column_text(statement, 2);
		int _typeSize = sqlite3_column_bytes(statement, 2);
		
		NSString *name     = [[NSString alloc] initWithBytes:_name length:_nameSize encoding:NSUTF8StringEncoding];
		NSString *affinity = [[NSString alloc] initWithBytes:_type length:_typeSize encoding:NSUTF8StringEncoding];
		
		if (name && affinity)
		{
			[columns setObject:affinity forKey:name];
		}
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@: Error executing statement! %d %s", THIS_METHOD, status, sqlite3_errmsg(aDb));
	}
	
	sqlite3_finalize(statement);
	statement = NULL;
	
	return columns;
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
		user_version = sqlite3_column_int(pragmaStatement, SQLITE_COLUMN_START);
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
 * In version 3 (more commonly known as version 2.1),
 * we altered the tables to use INTEGER PRIMARY KEY's so we could pass rowid's to extensions.
 * 
 * This method migrates 'database' to 'database2'.
**/
- (BOOL)upgradeTable_2_3
{
	int status;
	
	char *stmt = "INSERT INTO \"database2\" (\"collection\", \"key\", \"data\", \"metadata\")"
	             " SELECT \"collection\", \"key\", \"data\", \"metadata\" FROM \"database\";";
	
	status = sqlite3_exec(db, stmt, NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error migrating 'database' to 'database2': %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	status = sqlite3_exec(db, "DROP TABLE IF EXISTS \"database\"", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Failed dropping 'database' table: %d %s", status, sqlite3_errmsg(db));
		return NO;
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
 * This method is run asynchronously on the snapshotQueue.
**/
- (void)prepare
{
	// Write it to disk (replacing any previous value from last app run)
	
	[self beginTransaction];
	{
		snapshot = [self readSnapshot];
        
		sqliteVersion = [YapDatabase sqliteVersionUsing:db];
		YDBLogVerbose(@"sqlite version = %@", sqliteVersion);
		
		pageSize = (uint64_t)[YapDatabase pragma:@"page_size" using:db];
		
		[self fetchPreviouslyRegisteredExtensionNames];
	}
	[self commitTransaction];
	[self asyncCheckpoint:snapshot];
}

- (void)beginTransaction
{
	int status = status = sqlite3_exec(db, "BEGIN TRANSACTION;", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error in '%@': %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
	}
}

- (void)commitTransaction
{
	int status = status = sqlite3_exec(db, "COMMIT TRANSACTION;", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error in '%@': %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
	}
}

- (uint64_t)readSnapshot
{
    int status;
    sqlite3_stmt *statement;
    
    const char *stmt = "SELECT \"data\" FROM \"yap2\" WHERE \"extension\" = ? AND \"key\" = ?;";
	
    int const column_idx_data    = SQLITE_COLUMN_START;
    int const bind_idx_extension = SQLITE_BIND_START + 0;
    int const bind_idx_key       = SQLITE_BIND_START + 1;
    
    uint64_t result = 0;
    
    status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &statement, NULL);
    if (status != SQLITE_OK)
    {
        YDBLogError(@"%@: Error creating statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
    }
    else
    {
        const char *extension = "";
        sqlite3_bind_text(statement, bind_idx_extension, extension, (int)strlen(extension), SQLITE_STATIC);
        
        const char *key = "snapshot";
        sqlite3_bind_text(statement, bind_idx_key, key, (int)strlen(key), SQLITE_STATIC);
        
        status = sqlite3_step(statement);
        if (status == SQLITE_ROW)
        {
            result = (uint64_t)sqlite3_column_int64(statement, column_idx_data);
        }
        else if (status == SQLITE_ERROR)
        {
            YDBLogError(@"Error executing 'readSnapshot': %d %s",
                        status, sqlite3_errmsg(db));
        }
        
        sqlite3_finalize(statement);
    }
    
    return result;
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
		YDBLogError(@"%@: Error creating statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
	}
	else
	{
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			const unsigned char *text = sqlite3_column_text(statement, SQLITE_COLUMN_START);
			int textSize = sqlite3_column_bytes(statement, SQLITE_COLUMN_START);
			
			NSString *extensionName =
			    [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			if ([extensionName length] > 0)
			{
				[extensionNames addObject:extensionName];
			}
		}
		
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@: Error in statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		sqlite3_finalize(statement);
	}
	
	previouslyRegisteredExtensionNames = extensionNames;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Defaults
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseConnectionConfig *)connectionDefaults
{
	__block YapDatabaseConnectionConfig *result = nil;
	
	dispatch_sync(internalQueue, ^{
		
		result = [connectionDefaults copy];
	});
	
	return result;
}

- (BOOL)defaultObjectCacheEnabled
{
	__block BOOL result = NO;
	
	dispatch_sync(internalQueue, ^{
		
		result = connectionDefaults.objectCacheEnabled;
	});
	
	return result;
}

- (void)setDefaultObjectCacheEnabled:(BOOL)defaultObjectCacheEnabled
{
	dispatch_sync(internalQueue, ^{
		
		connectionDefaults.objectCacheEnabled = defaultObjectCacheEnabled;
	});
}

- (NSUInteger)defaultObjectCacheLimit
{
	__block NSUInteger result = NO;
	
	dispatch_sync(internalQueue, ^{
		
		result = connectionDefaults.objectCacheLimit;
	});
	
	return result;
}

- (void)setDefaultObjectCacheLimit:(NSUInteger)defaultObjectCacheLimit
{
	dispatch_sync(internalQueue, ^{
		
		connectionDefaults.objectCacheLimit = defaultObjectCacheLimit;
	});
}

- (BOOL)defaultMetadataCacheEnabled
{
	__block BOOL result = NO;
	
	dispatch_sync(internalQueue, ^{
		
		result = connectionDefaults.metadataCacheEnabled;
	});
	
	return result;
}

- (void)setDefaultMetadataCacheEnabled:(BOOL)defaultMetadataCacheEnabled
{
	dispatch_sync(internalQueue, ^{
		
		connectionDefaults.metadataCacheEnabled = defaultMetadataCacheEnabled;
	});
}

- (NSUInteger)defaultMetadataCacheLimit
{
	__block NSUInteger result = 0;
	
	dispatch_sync(internalQueue, ^{
		
		result = connectionDefaults.metadataCacheLimit;
	});
	
	return result;
}

- (void)setDefaultMetadataCacheLimit:(NSUInteger)defaultMetadataCacheLimit
{
	dispatch_sync(internalQueue, ^{
		
		connectionDefaults.metadataCacheLimit = defaultMetadataCacheLimit;
	});
}

- (YapDatabasePolicy)defaultObjectPolicy
{
	__block YapDatabasePolicy result = YapDatabasePolicyShare;
	
	dispatch_sync(internalQueue, ^{
		
		result = connectionDefaults.objectPolicy;
	});
	
	return result;
}

- (void)setDefaultObjectPolicy:(YapDatabasePolicy)defaultObjectPolicy
{
	dispatch_sync(internalQueue, ^{
		
		connectionDefaults.objectPolicy = defaultObjectPolicy;
	});
}

- (YapDatabasePolicy)defaultMetadataPolicy
{
	__block YapDatabasePolicy result = YapDatabasePolicyShare;
	
	dispatch_sync(internalQueue, ^{
		
		result = connectionDefaults.metadataPolicy;
	});
	
	return result;
}

- (void)setDefaultMetadataPolicy:(YapDatabasePolicy)defaultMetadataPolicy
{
	dispatch_sync(internalQueue, ^{
		
		connectionDefaults.metadataPolicy = defaultMetadataPolicy;
	});
}

#if TARGET_OS_IOS || TARGET_OS_TV

- (YapDatabaseConnectionFlushMemoryFlags)defaultAutoFlushMemoryFlags
{
	__block YapDatabaseConnectionFlushMemoryFlags result = YapDatabaseConnectionFlushMemoryFlags_None;
	
	dispatch_sync(internalQueue, ^{
		
		result = connectionDefaults.autoFlushMemoryFlags;
	});
	
	return result;
}

- (void)setDefaultAutoFlushMemoryFlags:(YapDatabaseConnectionFlushMemoryFlags)defaultAutoFlushMemoryFlags
{
	dispatch_sync(internalQueue, ^{
		
		connectionDefaults.autoFlushMemoryFlags = defaultAutoFlushMemoryFlags;
	});
}

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connections
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is called from [self newConnection].
**/
- (void)addConnection:(YapDatabaseConnection *)connection
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
	
	dispatch_async(connection->connectionQueue, ^{
		
		dispatch_sync(snapshotQueue, ^{ @autoreleasepool {
			
			// Add the connection to the state table
			
			YapDatabaseConnectionState *state = [[YapDatabaseConnectionState alloc] initWithConnection:connection];
			[connectionStates addObject:state];
			
			YDBLogVerbose(@"Created new connection(%p) for <%@ %p: databaseName=%@, connectionCount=%lu>",
			              connection, [self class], self, [databasePath lastPathComponent],
			              (unsigned long)[connectionStates count]);
			
			// Invoke the one-time prepare method, so the connection can perform any needed initialization.
			// Be sure to do this within the snapshotQueue, as the prepare method depends on this.
			
			[connection prepare];
		}});
	});
}

/**
 * This method is called from YapDatabaseConnection's dealloc method.
**/
- (void)removeConnection:(YapDatabaseConnection *)connection
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
		              connection, [self class], self, [databasePath lastPathComponent],
		              (unsigned long)[connectionStates count]);
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

/**
 * This is a public method called to create a new connection.
**/
- (YapDatabaseConnection *)newConnection
{
	YapDatabaseConnection *connection = [[YapDatabaseConnection alloc] initWithDatabase:self];
	
	[self addConnection:connection];
	return connection;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extensions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Registers the extension with the database using the given name.
 * After registration everything works automatically using just the extension name.
 * 
 * The registration process is equivalent to a (synchronous) readwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 *
 * @param extension
 *     The YapDatabaseExtension subclass instance you wish to register.
 *     For example, this might be a YapDatabaseView instance.
 * 
 * @param extensionName
 *     This is an arbitrary string you assign to the extension.
 *     Once registered, you will generally access the extension instance via this name.
 *     For example: [[transaction ext:@"myView"] numberOfGroups];
 *
 * @return
 *     YES if the extension was properly registered.
 *     NO if an error occurred, such as the extensionName is already registered.
 * 
 * @see asyncRegisterExtension:withName:completionBlock:
 * @see asyncRegisterExtension:withName:completionQueue:completionBlock:
**/
- (BOOL)registerExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName
{
	return [self registerExtension:extension withName:extensionName config:nil];
}

/**
 * Registers the extension with the database using the given name.
 * After registration everything works automatically using just the extension name.
 *
 * The registration process is equivalent to a (synchronous) readwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * @param extension (required)
 *     The YapDatabaseExtension subclass instance you wish to register.
 *     For example, this might be a YapDatabaseView instance.
 *
 * @param extensionName (required)
 *     This is an arbitrary string you assign to the extension.
 *     Once registered, you will generally access the extension instance via this name.
 *     For example: [[transaction ext:@"myView"] numberOfGroups];
 * 
 * @param config (optional)
 *     You may optionally pass a config for the internal databaseConnection used to perform
 *     the extension registration process. This allows you to control things such as the
 *     cache size, which is sometimes important for performance tuning.
 * 
 * @see asyncRegisterExtension:withName:completionBlock:
 * @see asyncRegisterExtension:withName:completionQueue:completionBlock:
**/
- (BOOL)registerExtension:(YapDatabaseExtension *)extension
                 withName:(NSString *)extensionName
                   config:(YapDatabaseConnectionConfig *)config
{
	__block BOOL ready = NO;
	dispatch_sync(writeQueue, ^{ @autoreleasepool {
		
		ready = [self _registerExtension:extension withName:extensionName config:config];
	}});
	
	return ready;
}

/**
 * Asynchronoulsy starts the extension registration process.
 * After registration everything works automatically using just the extension name.
 * 
 * The registration process is equivalent to an asyncReadwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * @param extension (required)
 *     The YapDatabaseExtension subclass instance you wish to register.
 *     For example, this might be a YapDatabaseView instance.
 *
 * @param extensionName (required)
 *     This is an arbitrary string you assign to the extension.
 *     Once registered, you will generally access the extension instance via this name.
 *     For example: [[transaction ext:@"myView"] numberOfGroups];
 *
 * @param completionBlock (optional)
 *     An optional completion block may be used.
 *     If the extension registration was successful then the ready parameter will be YES.
 *     The completionBlock will be invoked on the main thread (dispatch_get_main_queue()).
**/
- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
               completionBlock:(void(^)(BOOL ready))completionBlock
{
	[self asyncRegisterExtension:extension
	                    withName:extensionName
	                      config:nil
	             completionQueue:NULL
	             completionBlock:completionBlock];
}

/**
 * Asynchronoulsy starts the extension registration process.
 * After registration everything works automatically using just the extension name.
 *
 * The registration process is equivalent to an asyncReadwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * @param extension (required)
 *     The YapDatabaseExtension subclass instance you wish to register.
 *     For example, this might be a YapDatabaseView instance.
 *
 * @param extensionName (required)
 *     This is an arbitrary string you assign to the extension.
 *     Once registered, you will generally access the extension instance via this name.
 *     For example: [[transaction ext:@"myView"] numberOfGroups];
 *
 * @param completionQueue (optional)
 *     The dispatch_queue to invoke the completion block may optionally be specified.
 *     If NULL, dispatch_get_main_queue() is automatically used.
 *
 * @param completionBlock (optional)
 *     An optional completion block may be used.
 *     If the extension registration was successful then the ready parameter will be YES.
**/
- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
               completionQueue:(dispatch_queue_t)completionQueue
               completionBlock:(void(^)(BOOL ready))completionBlock
{
	[self asyncRegisterExtension:extension
	                    withName:extensionName
	                      config:nil
	             completionQueue:completionQueue
	             completionBlock:completionBlock];
}

/**
 * Asynchronoulsy starts the extension registration process.
 * After registration everything works automatically using just the extension name.
 *
 * The registration process is equivalent to an asyncReadwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * @param extension (required)
 *     The YapDatabaseExtension subclass instance you wish to register.
 *     For example, this might be a YapDatabaseView instance.
 *
 * @param extensionName (required)
 *     This is an arbitrary string you assign to the extension.
 *     Once registered, you will generally access the extension instance via this name.
 *     For example: [[transaction ext:@"myView"] numberOfGroups];
 * 
 * @param config (optional)
 *     You may optionally pass a config for the internal databaseConnection used to perform
 *     the extension registration process. This allows you to control things such as the
 *     cache size, which is sometimes important for performance tuning.
 *
 * @param completionBlock (optional)
 *     An optional completion block may be used.
 *     If the extension registration was successful then the ready parameter will be YES.
 *     The completionBlock will be invoked on the main thread (dispatch_get_main_queue()).
**/
- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
                        config:(YapDatabaseConnectionConfig *)config
               completionBlock:(void(^)(BOOL ready))completionBlock
{
	[self asyncRegisterExtension:extension
	                    withName:extensionName
	                      config:config
	             completionQueue:NULL
	             completionBlock:completionBlock];
}

/**
 * Asynchronoulsy starts the extension registration process.
 * After registration everything works automatically using just the extension name.
 *
 * The registration process is equivalent to an asyncReadwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * @param extension (required)
 *     The YapDatabaseExtension subclass instance you wish to register.
 *     For example, this might be a YapDatabaseView instance.
 *
 * @param extensionName (required)
 *     This is an arbitrary string you assign to the extension.
 *     Once registered, you will generally access the extension instance via this name.
 *     For example: [[transaction ext:@"myView"] numberOfGroups];
 * 
 * @param config (optional)
 *     You may optionally pass a config for the internal databaseConnection used to perform
 *     the extension registration process. This allows you to control things such as the
 *     cache size, which is sometimes important for performance tuning.
 *
 * @param completionQueue (optional)
 *     The dispatch_queue to invoke the completion block may optionally be specified.
 *     If NULL, dispatch_get_main_queue() is automatically used.
 *
 * @param completionBlock (optional)
 *     An optional completion block may be used.
 *     If the extension registration was successful then the ready parameter will be YES.
**/
- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
                        config:(YapDatabaseConnectionConfig *)config
               completionQueue:(dispatch_queue_t)completionQueue
               completionBlock:(void(^)(BOOL ready))completionBlock
{
	if (completionQueue == NULL && completionBlock != NULL)
		completionQueue = dispatch_get_main_queue();
	
	if (config)
		config = [config copy];
	
	dispatch_async(writeQueue, ^{ @autoreleasepool {
		
		BOOL ready = [self _registerExtension:extension withName:extensionName config:config];
		
		if (completionBlock)
		{
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				
				completionBlock(ready);
			}});
		}
	}});
}

/**
 * This method unregisters an extension with the given name.
 * The associated underlying tables will be dropped from the database.
 * 
 * The unregistration process is equivalent to a (synchronous) readwrite transaction.
 * It involves deleting various information about the extension from the database,
 * as well as possibly dropping related tables the extension may have been using.
 *
 * @param extensionName (required)
 *     This is the arbitrary string you assigned to the extension when you registered it.
 *
 * Note 1:
 *   You don't need to re-register an extension in order to unregister it. For example,
 *   you've previously registered an extension (in previous app launches), but you no longer need the extension.
 *   You don't have to bother creating and registering the unneeded extension,
 *   just so you can unregister it and have the associated tables dropped.
 *   The database persists information about registered extensions, including the associated class of an extension.
 *   So you can simply pass the name of the extension, and the database system will use the associated class to
 *   drop the appropriate tables.
 *
 * Note 2:
 *   In fact, you don't even have to worry about unregistering extensions that you no longer need.
 *   That database system will automatically handle it for you.
 *   That is, upon completion of the first readWrite transaction (that makes changes), the database system will
 *   check to see if there are any "orphaned" extensions. That is, previously registered extensions that are
 *   no longer in use (and are now out-of-date because they didn't process the recent change(s) to the db).
 *   And it will automatically unregister these orhpaned extensions for you.
 *       
 * @see asyncUnregisterExtensionWithName:completionBlock:
 * @see asyncUnregisterExtensionWithName:completionQueue:completionBlock:
**/
- (void)unregisterExtensionWithName:(NSString *)extensionName
{
	dispatch_sync(writeQueue, ^{ @autoreleasepool {
		
		[self _unregisterExtensionWithName:extensionName];
	}});
}

/**
 * Asynchronoulsy starts the extension unregistration process.
 *
 * The unregistration process is equivalent to an asyncReadwrite transaction.
 * It involves deleting various information about the extension from the database,
 * as well as possibly dropping related tables the extension may have been using.
 *
 * @param extensionName (required)
 *     This is the arbitrary string you assigned to the extension when you registered it.
 *
 * @param completionBlock (optional)
 *     An optional completion block may be used.
 *     The completionBlock will be invoked on the main thread (dispatch_get_main_queue()).
**/
- (void)asyncUnregisterExtensionWithName:(NSString *)extensionName
                         completionBlock:(dispatch_block_t)completionBlock
{
	[self asyncUnregisterExtensionWithName:extensionName
	                       completionQueue:NULL
	                       completionBlock:completionBlock];
}

/**
 * Asynchronoulsy starts the extension unregistration process.
 *
 * The unregistration process is equivalent to an asyncReadwrite transaction.
 * It involves deleting various information about the extension from the database,
 * as well as possibly dropping related tables the extension may have been using.
 *
 * @param extensionName (required)
 *     This is the arbitrary string you assigned to the extension when you registered it.
 *
 * @param completionQueue (optional)
 *     The dispatch_queue to invoke the completion block may optionally be specified.
 *     If NULL, dispatch_get_main_queue() is automatically used.
 *
 * @param completionBlock (optional)
 *     An optional completion block may be used.
**/
- (void)asyncUnregisterExtensionWithName:(NSString *)extensionName
                         completionQueue:(dispatch_queue_t)completionQueue
                         completionBlock:(dispatch_block_t)completionBlock
{
	if (completionQueue == NULL && completionBlock != NULL)
		completionQueue = dispatch_get_main_queue();
	
	dispatch_async(writeQueue, ^{ @autoreleasepool {
		
		[self _unregisterExtensionWithName:extensionName];
		
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
 * @see _unregisterExtensionWithName:
**/
- (YapDatabaseConnection *)registrationConnection
{
	if (registrationConnection == nil)
	{
		registrationConnection = [self newConnection];
		registrationConnection.name = @"YapDatabase_extensionRegistrationConnection";
		
		NSTimeInterval delayInSeconds = 5.0;
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
- (BOOL)_registerExtension:(YapDatabaseExtension *)extension
                  withName:(NSString *)extensionName
                    config:(YapDatabaseConnectionConfig *)config
{
	NSAssert(dispatch_get_specific(IsOnWriteQueueKey), @"Must go through writeQueue.");
	
	// Validate parameters
	
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
	
	// Check to ensure extension isn't already registered,
	// or that the extensionName isn't already taken.
	
	NSDictionary *_registeredExtensions = [self registeredExtensions];
	
	if (extension.registeredName != nil)
	{
		YDBLogError(@"Error registering extension: extension is already registered");
		return NO;
	}
	if ([_registeredExtensions objectForKey:extensionName] != nil)
	{
		YDBLogError(@"Error registering extension: extensionName(%@) already registered", extensionName);
		return NO;
	}
	
	// Attempt registration
	
	extension.registeredName = extensionName;
	extension.registeredDatabase = self;
	
	BOOL result = [extension supportsDatabaseWithRegisteredExtensions:_registeredExtensions];
	if (!result)
	{
		YDBLogError(@"Error registering extension: extension doesn't support database configuration");
	}
	else
	{
		YapDatabaseConnection *connection = [self registrationConnection];
		
		YapDatabaseConnectionConfig *originalConfig = nil;
		if (config)
		{
			originalConfig = [connection copyConfig];
			[connection applyConfig:config];
		}
		
		result = [connection registerExtension:extension withName:extensionName];
		
		if (config)
		{
			[connection applyConfig:originalConfig];
		}
	}
	
	if (result)
	{
		[extension didRegisterExtension];
	}
	else
	{
		extension.registeredName = nil;
		extension.registeredDatabase = nil;
	}
	
	
	return result;
}

/**
 * Internal method that handles extension unregistration.
 * This method must be invoked on the writeQueue.
**/
- (void)_unregisterExtensionWithName:(NSString *)extensionName
{
	NSAssert(dispatch_get_specific(IsOnWriteQueueKey), @"Must go through writeQueue.");
	
	// Validate parameters
	
	if ([extensionName length] == 0)
	{
		YDBLogError(@"Error unregistering extension: extensionName parameter is nil or empty string");
		return;
	}
	
	// Perform unregistration
	
	YapDatabaseConnection *connection = [self registrationConnection];
	
	[connection unregisterExtensionWithName:extensionName];
}

/**
 * Returns the registered extension with the given name.
**/
- (id)registeredExtension:(NSString *)extensionName
{
	// This method is public
	
	__block YapDatabaseExtension *result = nil;
	
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
 * The key is the registed name (NSString), and the value is the extension (YapDatabaseExtension subclass).
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

/**
 * This method is only accessible from within the snapshotQueue.
 * Used by [YapDatabaseConnection prepare].
**/
- (NSArray *)extensionsOrder
{
	NSAssert(dispatch_get_specific(IsOnSnapshotQueueKey), @"Must go through snapshotQueue for atomic access.");
	
	return extensionsOrder;
}

/**
 * This method is only accessible from within the snapshotQueue.
 * Used by [YapDatabaseConnection prepare].
**/
- (NSDictionary *)extensionDependencies
{
	NSAssert(dispatch_get_specific(IsOnSnapshotQueueKey), @"Must go through snapshotQueue for atomic access.");
	
	return extensionDependencies;
}

/**
 * Allows you to fetch the registered extension names from the last time the database was run.
 * Typically this means from the last time the app was run.
 *
 * This may be used to assist in various tasks, such as cleanup or upgrade tasks.
 *
 * If you need this information, you should fetch it early on because YapDatabase only maintains this information
 * until it sees you are done registering all your initial extensions. That is, after one initializes the database
 * they then immediately register any needed initial extensions before they begin to use the database. Once a
 * readWriteTransaction modifies the database, YapDatabase will take this opportunity to look for orphaned extensions.
 * These are extensions that were registered at the end of the last database session,
 * but which are no longer registered. YapDatabase will automatically cleanup these orphaned extensions,
 * and also clear the previouslyRegisteredExtensionNames information at this point.
**/
- (NSArray *)previouslyRegisteredExtensionNames
{
	__block NSArray *result = nil;
	
	dispatch_block_t block = ^{
		
		result = [previouslyRegisteredExtensionNames copy];
	};
	
	if (dispatch_get_specific(IsOnSnapshotQueueKey))
		block();
	else
		dispatch_sync(snapshotQueue, block);
	
	return result;
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
 * If so, the YapDatabaseConnection must not close the instance.
 * 
 * Returns NO if the instance was not added to the pool.
 * If so, the YapDatabaseConnection must close the instance.
**/
- (BOOL)connectionPoolEnqueue:(sqlite3 *)aDb main_file:(yap_file *)main_file wal_file:(yap_file *)wal_file
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
			
			NSDictionary *value = @{
			  YDBConnectionPoolValueKey_db        : [NSValue valueWithPointer:(const void *)aDb],
			  YDBConnectionPoolValueKey_main_file : [NSValue valueWithPointer:(const void *)main_file],
			  YDBConnectionPoolValueKey_wal_file  : [NSValue valueWithPointer:(const void *)wal_file],
			};
			
			[connectionPoolValues addObject:value];
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
- (BOOL)connectionPoolDequeue:(sqlite3 **)pDb main_file:(yap_file **)pMainFile wal_file:(yap_file **)pWalFile
{
	NSParameterAssert(pDb != NULL);
	NSParameterAssert(pMainFile != NULL);
	NSParameterAssert(pWalFile != NULL);
	
	__block sqlite3 *aDb = NULL;
	__block yap_file *main_file = NULL;
	__block yap_file *wal_file = NULL;
	
	dispatch_sync(internalQueue, ^{
		
		if ([connectionPoolValues count] > 0)
		{
			NSDictionary *value = [connectionPoolValues objectAtIndex:0];
			
			aDb       = (sqlite3 *)[[value objectForKey:YDBConnectionPoolValueKey_db] pointerValue];
			main_file = (yap_file *)[[value objectForKey:YDBConnectionPoolValueKey_main_file] pointerValue];
			wal_file  = (yap_file *)[[value objectForKey:YDBConnectionPoolValueKey_wal_file] pointerValue];
			
			YDBLogVerbose(@"Dequeuing connection from pool: %p", aDb);
			
			[connectionPoolValues removeObjectAtIndex:0];
			[connectionPoolDates removeObjectAtIndex:0];
			
			[self resetConnectionPoolTimer];
		}
	});
	
	*pDb = aDb;
	*pMainFile = main_file;
	*pWalFile = wal_file;
	
	return (aDb != NULL);
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
		
		__weak YapDatabase *weakSelf = self;
		dispatch_source_set_event_handler(connectionPoolTimer, ^{ @autoreleasepool {
			
			__strong YapDatabase *strongSelf = weakSelf;
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
	
	dispatch_time_t tt = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC));
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
			NSDictionary *value = [connectionPoolValues objectAtIndex:0];
			
			sqlite3 *aDb = (sqlite3 *)[[value objectForKey:YDBConnectionPoolValueKey_db] pointerValue];
			
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
#pragma mark Memory Tables
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is only accessible from within the snapshotQueue.
 * Used by [YapDatabaseConnection prepare].
**/
- (NSDictionary *)registeredMemoryTables
{
	NSAssert(dispatch_get_specific(IsOnSnapshotQueueKey), @"Must go through snapshotQueue for atomic access.");
	
	return registeredMemoryTables;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Snapshot Architecture
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
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
- (void)notePendingChangeset:(NSDictionary *)pendingChangeset fromConnection:(YapDatabaseConnection __unused *)sender
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
 * That is, the transaction started before it was able to process changesets from sibling connections.
 *
 * It should fetch the changesets needed and then process them via [connection noteCommittedChangeset:].
 *
 * Returns `nil` if the number of changesets found is not the expected one, that is, one for each snapshot increase from `connectionSnapshot` to `maxSnapshot`.
 * This can only happen in multiprocess mode, if another process has updated the database.
 * In this case the changesets are invalid, and we need to clear connection and extension caches.
**/
- (NSArray *)pendingAndCommittedChangesetsSince:(uint64_t)connectionSnapshot until:(uint64_t)maxSnapshot
{
	NSAssert(dispatch_get_specific(IsOnSnapshotQueueKey), @"Must go through snapshotQueue for atomic access.");
	
	NSUInteger capacity = (NSUInteger)(maxSnapshot - connectionSnapshot);
	NSMutableArray *relevantChangesets = [NSMutableArray arrayWithCapacity:capacity];
    
	for (NSDictionary *changeset in changesets)
	{
		uint64_t changesetSnapshot = [[changeset objectForKey:YapDatabaseSnapshotKey] unsignedLongLongValue];
		
		if ((changesetSnapshot > connectionSnapshot) && (changesetSnapshot <= maxSnapshot))
		{
			[relevantChangesets addObject:changeset];
		}
	}
    
	if (options.enableMultiProcessSupport)
	{
		const uint64_t expectedSnapshotsCount = maxSnapshot - connectionSnapshot;
		if (expectedSnapshotsCount != relevantChangesets.count)
		{
			YDBLogVerbose(@"Expected snapshot count not found: expected(%llu) != found(%llu)."
			              @" Database seems to have been modified from another process. Discarding changeset.",
			              expectedSnapshotsCount, (uint64_t)relevantChangesets.count);
			return nil;
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
- (void)noteCommittedChangeset:(NSDictionary *)changeset fromConnection:(YapDatabaseConnection *)sender
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
		extensionsOrder = [changeset objectForKey:YapDatabaseExtensionsOrderKey];
		extensionDependencies = [changeset objectForKey:YapDatabaseExtensionDependenciesKey];
	}
	
	// Update registeredMemoryTables, if changed.
	
	NSDictionary *newRegisteredMemoryTables = [changeset objectForKey:YapDatabaseRegisteredMemoryTablesKey];
	if (newRegisteredMemoryTables)
	{
		registeredMemoryTables = newRegisteredMemoryTables;
	}
	
	// Forward the changeset to all extensions.
	
	[registeredExtensions enumerateKeysAndObjectsUsingBlock:
	    ^(NSString *extName, YapDatabaseExtension *ext, BOOL __unused *stop)
	{
		[ext noteCommittedChangeset:changeset registeredName:extName];
	}];
	
	// Forward the changeset to all other connections so they can perform any needed updates.
	// Generally this means updating the in-memory components such as the cache.
	
	dispatch_group_t group = NULL;
	
	for (YapDatabaseConnectionState *state in connectionStates)
	{
		if (state->connection != sender)
		{
			// Create strong reference (state->connection is weak)
			__strong YapDatabaseConnection *connection = state->connection;
			
			if (connection)
			{
				if (group == NULL)
					group = dispatch_group_create();
				
				dispatch_group_async(group, connection->connectionQueue, ^{ @autoreleasepool {
					
					[connection noteCommittedChangeset:changeset];
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
	if (maxCheckpointableSnapshot > 0) {
		YDBLogVerbose(@"Checkpoint possible up to snapshot %llu", maxCheckpointableSnapshot);
	}
	
	bool aggressive = atomic_load(&aggressiveCheckpointEnabled);
	if (aggressive)
	{
		[self asyncAggressiveCheckpoint];
	}
	else
	{
		[self asyncPassiveCheckpoint];
	}
}

- (void)asyncPassiveCheckpoint
{
	bool hasPendingCheckpoint = atomic_flag_test_and_set(&pendingPassiveCheckpoint);
	if (hasPendingCheckpoint) {
		return;
	}
	
	__weak YapDatabase *weakSelf = self;
	
	dispatch_async(checkpointQueue, ^{ @autoreleasepool {
#pragma clang diagnostic push
#pragma clang diagnostic warning "-Wimplicit-retain-self"
		
		__strong YapDatabase *strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		atomic_flag_clear(&strongSelf->pendingPassiveCheckpoint);
		
		if (atomic_load(&strongSelf->aggressiveCheckpointEnabled)) {
			return;
		}
		
		[strongSelf passiveCheckpoint];
		
#pragma clang diagnostic pop
	}});
}

- (void)asyncAggressiveCheckpoint
{
	bool hasPendingCheckpoint = atomic_flag_test_and_set(&pendingAggressiveCheckpoint);
	if (hasPendingCheckpoint) {
		return;
	}
	
	__weak YapDatabase *weakSelf = self;
	
	dispatch_async(writeQueue, ^{
	#pragma clang diagnostic push
	#pragma clang diagnostic warning "-Wimplicit-retain-self"
		
		__strong YapDatabase *strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		atomic_flag_clear(&strongSelf->pendingAggressiveCheckpoint);
		
		if (!atomic_load(&strongSelf->aggressiveCheckpointEnabled)) {
			return;
		}
		
		[strongSelf aggressiveCheckpoint];
		
	#pragma clang diagnostic pop
	});
}

- (void)passiveCheckpoint
{
	int checkpointResult = 0;
	int totalFrameCount = 0;
	int checkpointedFrameCount = 0;
	
	// We're going to execute a passive checkpoint.
	// That is, without disrupting any connections, we're going to write pages from the WAL into the database.
	// The checkpoint can only write pages from snapshots if all connections are at or beyond the snapshot.
	// Thus, this method is only called by a connection that moves the min snapshot forward.
	
	checkpointResult = sqlite3_wal_checkpoint_v2(db, "main", SQLITE_CHECKPOINT_PASSIVE,
	                                             &totalFrameCount, &checkpointedFrameCount);
	
	// totalFrameCount        = total number of frames in the WAL file
	// checkpointedFrameCount = total number of checkpointed frames (those copied into db file)
	//                          (including any that were already checkpointed before the function was called)
	
	YDBLogVerbose(@"Post-checkpoint: src(a) mode(passive) result(%d) frames(%d) checkpointed(%d)",
	              checkpointResult, totalFrameCount, checkpointedFrameCount);
	
	if (checkpointResult != SQLITE_OK)
	{
		if (checkpointResult == SQLITE_BUSY) {
			YDBLogVerbose(@"sqlite3_wal_checkpoint_v2 returned SQLITE_BUSY");
		}
		else {
			YDBLogWarn(@"sqlite3_wal_checkpoint_v2 returned error code: %d", checkpointResult);
		}
		
		return;// from_block
	}
	
	// Did we checkpoint the entire WAL file ?
	
	BOOL didCheckpointEntireWAL = (totalFrameCount == checkpointedFrameCount);
	
	if (didCheckpointEntireWAL)
	{
		// We've checkpointed every single frame in the WAL.
		// This means the next read-write transaction may be able to reset the WAL (instead of appending to it).
		//
		// However, the WAL reset will get spoiled if there are active read-only transactions that
		// were started before our checkpoint finished, and continue to exist during the next read-write.
		// It's not a big deal if the occasional read-only transaction happens to spoil the WAL reset.
		// In those cases, the WAL generally gets reset shortly thereafter (on a subsequent write).
		// Long-lived read transactions are a different case entirely.
		// These transactions spoil it every single time, and could potentially cause the WAL to grow indefinitely.
		//
		// The solution is to notify active long-lived connections, and tell them to re-begin their transaction
		// on the same snapshot. But this time the sqlite machinery will read directly from the database,
		// and thus unlock the WAL so it can be reset.
		
		__weak YapDatabase *weakSelf = self;
		
		dispatch_async(writeQueue, ^{ @autoreleasepool {
		#pragma clang diagnostic push
		#pragma clang diagnostic warning "-Wimplicit-retain-self"
			
			__strong YapDatabase *strongSelf = weakSelf;
			if (strongSelf == nil) return;
			
			[strongSelf tryResetLongLivedReadTransactions];
			
		#pragma clang diagnostic pop
		}});
	}
	
	// Is the WAL file getting too big ?
	
	uint64_t walApproximateFileSize = totalFrameCount * pageSize;
	BOOL needsAggressiveCheckpoint = (walApproximateFileSize >= options.aggressiveWALTruncationSize);
	
	if (needsAggressiveCheckpoint)
	{
		atomic_store(&aggressiveCheckpointEnabled, true);
		
		[self asyncAggressiveCheckpoint];
	}
}

- (void)aggressiveCheckpoint
{
	int checkpointResult = 0;
	int totalFrameCount = 0;
	int checkpointedFrameCount = 0;
	
	// First we set an adequate busy timeout on our database connection.
	// We're going to run a non-passive checkpoint.
	// Which may cause it to busy-wait while waiting on read transactions to complete.
	
	sqlite3_busy_timeout(db, 50); // milliseconds
	
	// Step 1 of 3:
	//
	// Perform FULL checkpoint.
	//
	// This will checkpoint as many frames as possible,
	// and busy-wait until all readers are on the latest commit.
	
	checkpointResult = sqlite3_wal_checkpoint_v2(db, "main", SQLITE_CHECKPOINT_FULL,
	                                             &totalFrameCount, &checkpointedFrameCount);
	
	YDBLogInfo(@"Post-checkpoint: src(b) mode(full) result(%d) frames(%d) checkpointed(%d)",
	           checkpointResult, totalFrameCount, checkpointedFrameCount);
	
	if (totalFrameCount != checkpointedFrameCount)
	{
		return;
	}
	
	// STEP 2 of 3:
	//
	// Check for longLivedReadTransactions, and attempt to silently move them to reading directly from the database.
	// (As oppossed to reading from the latest commit in the WAL.)
	
	if (![self tryResetLongLivedReadTransactions])
	{
		YDBLogInfo(@"Aggressive checkpoint spoiled: longLivedReadTransaction is blocking");
		return;
	}
	
	// STEP 3 of 3:
	//
	// Perform TRUNCATE checkpoint.
	//
	// At this point, we've checkpointed every single frame.
	// And every connection should be reading directly from the database.
	// So we should be able to truncate the WAL file now.
	
	// Can we use SQLITE_CHECKPOINT_TRUNCATE ?
	//
	// This feature was added in sqlite v3.8.8.
	// But it was buggy until v3.8.8.2 when the following fix was added:
	//
	//   "Enhance sqlite3_wal_checkpoint_v2(TRUNCATE) interface so that it truncates the
	//    WAL file even if there is no checkpoint work to be done."
	//
	//   http://www.sqlite.org/changes.html
	//
	// It is often the case, when we call checkpoint here, that there is no checkpoint work to be done.
	// So we really can't depend on it until 3.8.8.2
	
	int checkpointMode = SQLITE_CHECKPOINT_RESTART;
	
	// Remember: The compiler defines (SQLITE_VERSION, SQLITE_VERSION_NUMBER) only tell us
	// what version we're compiling against. But we may encounter an earlier sqlite version at runtime.
	
#ifndef SQLITE_VERSION_NUMBER_3_8_8
#define SQLITE_VERSION_NUMBER_3_8_8 3008008
#endif
	
#if SQLITE_VERSION_NUMBER > SQLITE_VERSION_NUMBER_3_8_8
	
	checkpointMode = SQLITE_CHECKPOINT_TRUNCATE;
	
#elif SQLITE_VERSION_NUMBER == SQLITE_VERSION_NUMBER_3_8_8
	
	NSComparisonResult cmp = [strongSelf->sqliteVersion compare:@"3.8.8.2" options:NSNumericSearch];
	if (cmp != NSOrderedAscending)
	{
		checkpointMode = SQLITE_CHECKPOINT_TRUNCATE;
	}
	
#endif
	
	checkpointResult = sqlite3_wal_checkpoint_v2(db, "main", checkpointMode,
	                                             &totalFrameCount, &checkpointedFrameCount);
	
	YDBLogInfo(@"Post-checkpoint: src(c) mode(%@) result(%d) frames(%d) checkpointed(%d)",
	           (checkpointMode == SQLITE_CHECKPOINT_RESTART ? @"restart" : @"truncate"),
	           checkpointResult, totalFrameCount, checkpointedFrameCount);
	
	if (checkpointResult == SQLITE_OK)
	{
		if (checkpointMode == SQLITE_CHECKPOINT_RESTART)
		{
			// Write something to the database to force restart the WAL.
			// We're just going to set a random value in the yap2 table.
			
			NSString *uuid = [[NSUUID UUID] UUIDString];
			
			[self beginTransaction];
			
			int status;
			sqlite3_stmt *statement;
			
			char *stmt = "INSERT OR REPLACE INTO \"yap2\" (\"extension\", \"key\", \"data\") VALUES (?, ?, ?);";
			
			int const bind_extension = SQLITE_BIND_START + 0;
			int const bind_key       = SQLITE_BIND_START + 1;
			int const bind_data      = SQLITE_BIND_START + 2;
			
			status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &statement, NULL);
			if (status != SQLITE_OK)
			{
				YDBLogError(@"%@: Error creating statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
			}
			else
			{
				char *extension = "";
				sqlite3_bind_text(statement, bind_extension, extension, (int)strlen(extension), SQLITE_STATIC);
				
				char *key = "random";
				sqlite3_bind_text(statement, bind_key, key, (int)strlen(key), SQLITE_STATIC);
				
				YapDatabaseString _uuid; MakeYapDatabaseString(&_uuid, uuid);
				sqlite3_bind_text(statement, bind_data, _uuid.str, _uuid.length, SQLITE_STATIC);
				
				status = sqlite3_step(statement);
				if (status != SQLITE_DONE)
				{
					YDBLogError(@"%@: Error in statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
				}
				
				sqlite3_finalize(statement);
				FreeYapDatabaseString(&_uuid);
			}
			
			[self commitTransaction];
		}
		
		atomic_store(&aggressiveCheckpointEnabled, false);
	}
}

- (BOOL)tryResetLongLivedReadTransactions
{
	NSAssert(dispatch_get_specific(IsOnWriteQueueKey), @"Must go through writeQueue.");
	
	dispatch_group_t group = dispatch_group_create();
	
	__block YAPUnfairLock spinLock = YAP_UNFAIR_LOCK_INIT;
	__block atomic_bool hasWriteQueue = true;
	
	dispatch_sync(snapshotQueue, ^{ @autoreleasepool {
		
		for (YapDatabaseConnectionState *state in connectionStates)
		{
			if (state->activeReadTransaction && state->longLivedReadTransaction)
			{
				__strong YapDatabaseConnection *connection = state->connection;
				if (connection)
				{
					dispatch_group_async(group, connection->connectionQueue, ^{
						
						YAPUnfairLockLock(&spinLock);
						{
							if (atomic_load(&hasWriteQueue))
							{
								[connection resetLongLivedReadTransaction];
							}
						}
						YAPUnfairLockUnlock(&spinLock);
					});
				}
			}
		}
	}});
	
	long ready = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)));
	
	if (ready != 0)
	{
		YAPUnfairLockLock(&spinLock);
		{
			atomic_store(&hasWriteQueue, false);
		}
		YAPUnfairLockUnlock(&spinLock);
		
		return NO;
	}
	else
	{
		return YES;
	}
}

/**
 * Consulted by YapDatabaseConnection after performing a read-write transaction.
 *
 * When aggressive checkpointing is triggered,
 * the connections will perform a checkpoint after every read-write transaction.
**/
- (BOOL)aggressiveCheckpointEnabled
{
	return atomic_load(&aggressiveCheckpointEnabled);
}

- (void)noteCheckpointWithTotalFrames:(int)totalFrameCount checkpointedFrames:(int)checkpointedFrameCount
{
	uint64_t walApproximateFileSize = totalFrameCount * pageSize;
	
	if (walApproximateFileSize < options.aggressiveWALTruncationSize)
	{
		atomic_store(&aggressiveCheckpointEnabled, false);
	}
}

@end
