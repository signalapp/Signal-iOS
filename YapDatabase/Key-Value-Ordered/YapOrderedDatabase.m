#import "YapOrderedDatabase.h"
#import "YapOrderedDatabasePrivate.h"
#import "YapOrderedDatabaseConnection.h"
#import "YapOrderedDatabaseTransaction.h"

#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"
#import "YapDatabasePrivate.h"

#import "sqlite3.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#if DEBUG
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapOrderedDatabase

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
	    " (\"key\" CHAR PRIMARY KEY NOT NULL, \"data\" BLOB);";
	
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
 * We use it to create instances of YapOrderedDatabaseConnection instead of YapDatabaseConnection.
**/
- (YapOrderedDatabaseConnection *)newConnection
{
	YapOrderedDatabaseConnection *connection = [[YapOrderedDatabaseConnection alloc] initWithDatabase:self];
	
	[self addConnection:connection];
	return connection;
}

@end
