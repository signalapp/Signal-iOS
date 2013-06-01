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
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
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
