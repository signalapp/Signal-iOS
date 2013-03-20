#import "YapDatabase.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"
#import "YapDatabaseManager.h"

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

/**
 * YapDatabase provides concurrent thread-safe access to a key-value database backed by sqlite.
 *
 * A vast majority of the implementation is in YapAbstractDatabase.
 * The YapAbstractDatabase implementation is shared between YapDatabase and YapCollectionsDatabase.
**/
@implementation YapDatabase

/**
 * Required override method from YapAbstractDatabase.
 * 
 * The abstract version creates the 'yap' table, which is used internally.
 * Our version creates the 'database' table, which holds the key/object/metadata rows.
**/
- (BOOL)createTables
{
	char *createDatabaseTableStatement =
	    "CREATE TABLE IF NOT EXISTS \"database\""
	    " (\"key\" CHAR PRIMARY KEY NOT NULL, "
	    "  \"data\" BLOB, "
	    "  \"metadata\" BLOB"
	    " );";
	
	int status = sqlite3_exec(db, createDatabaseTableStatement, NULL, NULL, NULL);
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
	return [NSString class];
}

/**
 * Upgrade mechanism hook.
 * The upgrade checks and logic exists in YapAbstractDatabase.
 * 
 * Upgrades the database from version 0 to 1.
**/
- (BOOL)upgradeTable_0_1
{
	// Version 0 didn't fully support abstract metadata. It only supported timestamps.
	// It kept these timestamps in memory as a dictionary,
	// and saved them (via dictionary archive) to disk under the key "__indexes".
	
	NSDictionary *timestamps = nil;
	
	int status;
	sqlite3_stmt *statement;
	char *query;
	int queryLength;
	
	__block BOOL error = NO;
	
	// Step 1 of 6:
	// Add 'metadata' column to the table
	
	YDBLogInfo(@"Adding new metadata column...");
	
	status = sqlite3_exec(db, "ALTER TABLE \"database\" ADD COLUMN \"metadata\" BLOB", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error adding metadata column: %d %s",
		              NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		return NO;
	}
	
	// Step 2 of 6:
	// Begin transaction
	
	status = sqlite3_exec(db, "BEGIN TRANSACTION;", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error starting transaction: %d %s",
		              NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		return NO;
	}
	
	// Step 3 of 6:
	// Read the "__indexes" field from the database
	
	query = "SELECT \"data\" FROM \"database\" WHERE \"key\" = __indexes;";
	queryLength = strlen(query);
	
	status = sqlite3_prepare_v2(db, query, queryLength+1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating select statement: %d %s",
		              NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		error = YES;
	}
	else if (sqlite3_step(statement) == SQLITE_ROW)
	{
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		if (blobSize > 0)
		{
			NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			
			@try
			{
				id obj = [NSKeyedUnarchiver unarchiveObjectWithData:data];
				if ([obj isKindOfClass:[NSDictionary class]])
				{
					timestamps = (NSDictionary *)obj;
				}
			}
			@catch (NSException *exception)
			{
				YDBLogWarn(@"%@: Exception unarchiving indexes: %@", NSStringFromSelector(_cmd), exception);
				error = YES;
			}
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
	}
	
	// Step 4 of 6:
	// Write the timestamps into their metadata field
	
	if ([timestamps count] > 0)
	{
		query = "UPDATE \"database\" SET \"metadata\" = ? WHERE \"key\" = ?;";
		queryLength = strlen(query);
		
		status = sqlite3_prepare_v2(db, query, queryLength+1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating update statement: %d %s",
						  NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
			error = YES;
		}
		else
		{
			YDBLogInfo(@"Migrating %lu timestamps to new metadata format...", (unsigned long)[timestamps count]);
			
			[timestamps enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
				
				if ([obj isKindOfClass:[NSDate date]])
				{
					YapDatabaseString _key; MakeYapDatabaseString(&_key, (NSString *)key);
					
					__attribute__((objc_precise_lifetime)) NSData *rawMeta = self.metadataSerializer(obj);
					
					sqlite3_bind_blob(statement, 1, rawMeta.bytes, rawMeta.length, SQLITE_STATIC);
					sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
					
					int status = sqlite3_step(statement);
					if (status != SQLITE_DONE)
					{
						YDBLogError(@"%@: Error executing update statement: %d %s",
						              NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
						error = YES;
					}
					
					sqlite3_clear_bindings(statement);
					sqlite3_reset(statement);
					FreeYapDatabaseString(&_key);
				}
			}];
			
			sqlite3_finalize(statement);
			statement = NULL;
		}
	}
	
	// Step 5 of 6:
	// Remove the "__indexes" field from the database
	
	if (!error)
	{
		status = sqlite3_exec(db, "DELETE FROM \"database\" WHERE \"key\" = __indexes;", NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error deleting '__indexes' row: %d %s",
						  NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
			error = YES;
		}
	}
	
	// Step 6 of 6:
	// Commit transaction
	
	status = sqlite3_exec(db, "COMMIT TRANSACTION;", NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error committing transaction: %d %s",
		              NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		error = YES;
	}
	
	if (error)
		return NO;
	else
		return YES;
}

/**
 * This is a public method called to create a new connection.
 * 
 * All the details of managing connections, and managing connection state, is handled by YapAbstractDatabase.
**/
- (YapDatabaseConnection *)newConnection
{
	YapDatabaseConnection *connection = [[YapDatabaseConnection alloc] initWithDatabase:self];
	
	[self addConnection:connection];
	return connection;
}

@end
