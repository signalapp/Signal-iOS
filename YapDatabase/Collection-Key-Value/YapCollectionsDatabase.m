#import "YapCollectionsDatabase.h"
#import "YapCollectionsDatabasePrivate.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapCacheCollectionKey.h"
#import "YapDatabaseLogging.h"

#import "sqlite3.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file.
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG && robbie_hanson
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_VERBOSE;
#elif DEBUG
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif


/**
 * YapDatabase provides concurrent thread-safe access to a key-value database backed by sqlite.
 *
 * A vast majority of the implementation is in YapAbstractDatabase.
 * The YapAbstractDatabase implementation is shared between YapDatabase and YapCollectionsDatabase.
**/
@implementation YapCollectionsDatabase

/**
 * Required override method from YapAbstractDatabase.
 *
 * The abstract version creates the 'yap' table, which is used internally.
 * Our version creates the 'database' table, which holds the key/object/metadata rows.
**/
- (BOOL)createTables
{
	char *createDatabaseStatement =
	    "CREATE TABLE IF NOT EXISTS \"database\""
	    " (\"collection\" CHAR NOT NULL, "
	    "  \"key\" CHAR NOT NULL, "
	    "  \"data\" BLOB, "
	    "  \"metadata\" BLOB, "
	    "  PRIMARY KEY (\"collection\", \"key\")"
	    " );";
	
	int status = sqlite3_exec(db, createDatabaseStatement, NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Failed creating 'database' table: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	return [super createTables];
}

/**
 * Required override method from YapAbstractDatabase.
 * 
 * This method is used when creating the YapSharedCache, and provides the type of key's we'll be using for the cache.
**/
- (Class)cacheKeyClass
{
	return [YapCacheCollectionKey class];
}

/**
 * Required override method from YapAbstractDatabase.
 *
 * This method is used to generate the changeset block used with YapSharedCache & YapSharedCacheConnection.
 * The given changeset comes directly from a readwrite transaction.
 *
 * The output block should return one of the following:
 *
 *  0 if the changeset indicates the key/value pair was unchanged.
 * -1 if the changeset indicates the key/value pair was deleted.
 * +1 if the changeset indicates the key/value pair was modified.
**/
- (int (^)(id key))cacheChangesetBlockFromChanges:(NSDictionary *)changeset
{
	NSSet *changeset_changedKeys = [changeset objectForKey:@"changedKeys"];
	NSSet *changeset_resetCollections = [changeset objectForKey:@"resetCollections"];
	BOOL changeset_allKeysRemoved = [[changeset objectForKey:@"allKeysRemoved"] boolValue];
	
	int (^changeset_block)(id key) = ^(id key){
		
		YapCacheCollectionKey *cacheKey = (YapCacheCollectionKey *)key;
		
		// Order matters.
		// Imagine the following scenario:
		//
		// A database transaction removes all items from the database.
		// Then it adds a single key/value pair.
		//
		// In this case, the proper return value for the single added key is 1 (modified).
		// The proper return value for all other keys is -1 (deleted).
		
		if ([changeset_changedKeys containsObject:cacheKey])
		{
			return 1; // Collection/Key/value pair was modified
		}
		if ([changeset_resetCollections containsObject:cacheKey.collection])
		{
			return -1; // Collection/Key/value pair was deleted
		}
		if (changeset_allKeysRemoved)
		{
			return -1; // Collection/Key/value pair was deleted
		}
		
		return 0; // Collection/Key/value pair wasn't modified
	};
	
	return changeset_block;
}

/**
 * This is a public method called to create a new connection.
 *
 * All the details of managing connections, and managing connection state, is handled by YapAbstractDatabase.
**/
- (YapCollectionsDatabaseConnection *)newConnection
{
	YapCollectionsDatabaseConnection *connection = [[YapCollectionsDatabaseConnection alloc] initWithDatabase:self];
	
	[self addConnection:connection];
	return connection;
}

@end
