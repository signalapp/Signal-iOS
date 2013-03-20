#import "YapOrderedCollectionsDatabase.h"
#import "YapOrderedCollectionsDatabasePrivate.h"

#import "YapCollectionsDatabasePrivate.h"
#import "YapAbstractDatabasePrivate.h"

#import "YapDatabaseString.h"
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
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapOrderedCollectionsDatabase

/**
 * Override hook.
 * Create any needed database tables.
**/
- (BOOL)createTables
{
	// Create the normal tables
	
	if (![super createTables]) return NO;
	
	// Create the 'order' table
	
	char *createOrderStatement =
	    "CREATE TABLE IF NOT EXISTS \"order\""
	    " (\"collection\" CHAR NOT NULL,"
	    " \"key\" CHAR NOT NULL,"
	    " \"data\" BLOB,"
	    " PRIMARY KEY (\"collection\", \"key\"));";
	
	int status = sqlite3_exec(db, createOrderStatement, NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Failed creating order table: %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	return YES;
}

/**
 * Override hook.
 * We use it to create instances of YapOrderedCollectionsDatabaseConnection instead of YapCollectionsDatabaseConnection.
**/
- (YapOrderedCollectionsDatabaseConnection *)newConnection
{
	YapOrderedCollectionsDatabaseConnection *connection =
	    [[YapOrderedCollectionsDatabaseConnection alloc] initWithDatabase:self];
	
	[self addConnection:connection];
	return connection;
}

@end
