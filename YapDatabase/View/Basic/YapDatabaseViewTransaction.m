#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseViewPrivate.h"
#import "YapAbstractDatabaseViewPrivate.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapCache.h"
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


@implementation YapDatabaseViewTransaction

- (BOOL)open
{
	NSString *tableName = [abstractViewConnection->abstractView tableName];
	sqlite3 *db = databaseTransaction->abstractConnection->db;
	
	NSString *selectStatement = [NSString stringWithFormat:
	    @"SELECT \"key\", \"metadata\" FROM \"%@\";", tableName];
	
	sqlite3_stmt *enumerateStatement;
	
	int status = sqlite3_prepare_v2(db, [selectStatement UTF8String], -1, &enumerateStatement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error creating 'enumerateAllStatement': %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	// Enumerate over the metadata in the database, and populate our data structures.
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	NSMutableDictionary *hashPagesDict = [[NSMutableDictionary alloc] init];
	NSMutableDictionary *hashPagesOrder = [[NSMutableDictionary alloc] init];
	
//	NSMutableDictionary *keyPagesSetup = [[NSMutableDictionary alloc] init];
	
	while (sqlite3_step(enumerateStatement) == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(enumerateStatement, 0);
		int textSize = sqlite3_column_bytes(enumerateStatement, 0);
		
		const void *mBlob = sqlite3_column_blob(enumerateStatement, 1);
		int mBlobSize = sqlite3_column_bytes(enumerateStatement, 1);
		
		NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		NSData *mData = [[NSData alloc] initWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
		id metadata = viewConnection->deserializer(mData);
		
		if ([metadata isKindOfClass:[YapDatabaseViewHashPage class]])
		{
			YapDatabaseViewHashPage *hashPage = (YapDatabaseViewHashPage *)metadata;
			hashPage->key = key;
			
			[hashPagesDict setObject:hashPage forKey:key];
			
			if (hashPage->nextKey)
				[hashPagesOrder setObject:hashPage->nextKey forKey:hashPage->key];
			else
				[hashPagesOrder setObject:[NSNull null] forKey:hashPage->key];
		}
	}
	
	BOOL error = (status != SQLITE_DONE);
	
	if (!error)
	{
		// Initialize ivars in viewConnection.
		// We try not to do this before we know the table exists.
		
		viewConnection->hashPages = [[NSMutableArray alloc] init];
		viewConnection->keyPagesDict = [[NSMutableDictionary alloc] init];
	}
	
	if (!error)
	{
		// Stitch together the hash pages.
		
		NSString *key = [hashPagesOrder objectForKey:[NSNull null]];
		while (key)
		{
			YapDatabaseViewHashPage *hashPage = [hashPagesDict objectForKey:key];
			
			[viewConnection->hashPages insertObject:hashPage atIndex:0];
			
			key = [hashPagesOrder objectForKey:key];
		}
		
		// Validate data
		
		if ([viewConnection->hashPages count] < [hashPagesDict count])
		{
			YDBLogError(@"%@: Error opening view: Missing hash page(s)", THIS_FILE);
			
			error = YES;
		}
	}
	
	if (!error)
	{
		// Stitch together the 
	}
	
	// Validate data
	
	if (error)
	{
		viewConnection->hashPages = nil;
		viewConnection->keyPagesDict = nil;
	}
	
	sqlite3_finalize(enumerateStatement);
	return !error;
}

- (BOOL)createTable
{
	NSAssert(databaseTransaction->isReadWriteTransaction, @"Attempt to create a view outside a readwrite transaction");
	
	NSString *tableName = [abstractViewConnection->abstractView tableName];
	sqlite3 *db = databaseTransaction->abstractConnection->db;
	
	NSString *statement = [NSString stringWithFormat:
	    @"CREATE TABLE IF NOT EXISTS \"%@\""
	    @" (\"key\" CHAR PRIMARY KEY NOT NULL, "
	    @"  \"data\" BLOB, "
	    @"  \"metadata\" BLOB"
	    @" );", tableName];
	
	int status = sqlite3_exec(db, [statement UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Failed creating table for view(%@): %d %s",
		            [abstractViewConnection->abstractView registeredName], status, sqlite3_errmsg(db));
		return NO;
	}
	
	return YES;
}

- (BOOL)createOrOpen
{
	NSAssert(databaseTransaction->isReadWriteTransaction, @"Attempt to create a view outside a readwrite transaction");
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection =
	    (YapDatabaseViewConnection *)abstractViewConnection;
	
	if ([viewConnection isOpen])
	{
		return YES;
	}
	else
	{
		if (![self createTable]) return NO;
		if (![self open]) return NO;
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)databaseTableExists
{
	BOOL result = NO;
	
	NSString *tableName = [abstractViewConnection->abstractView tableName];
	
	NSString *query = [NSString stringWithFormat:
					   @"SELECT COUNT(*) AS NumberOfRows FROM sqlite_master"
					   @" WHERE type='table' AND name='%@'", tableName];
	
	sqlite3 *db = databaseTransaction->abstractConnection->db;
	sqlite3_stmt *statement;
	int status;
	
	status = sqlite3_prepare_v2(db, [query UTF8String], -1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error creating query statement! %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = (sqlite3_column_int64(statement, 0) > 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing statement: %d %s", status, sqlite3_errmsg(db));
	}
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapAbstractDatabaseViewKeyValueTransaction
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)handleInsertKey:(NSString *)key withObject:(id)object metadata:(id)metadata
{
	// Todo
}

- (void)handleUpdateKey:(NSString *)key withObject:(id)object metadata:(id)metadata
{
	// Todo
}

- (void)handleUpdateKey:(NSString *)key withMetadata:(id)metadata
{
	// Todo
}

- (void)handleRemoveKey:(NSString *)key
{
	// Todo
}

- (void)handleRemoveAllKeys
{
	// Todo
}

- (void)commitTransaction
{
	// Todo
	
	[super commitTransaction];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)numberOfSections
{
	// Todo
	return 0;
}

- (NSUInteger)numberOfKeysInSection:(NSUInteger)section
{
	// Todo
	return 0;
}

- (NSUInteger)numberOfKeysInAllSections
{
	// Todo
	return 0;
}

- (NSString *)keyAtIndex:(NSUInteger)keyIndex inSection:(NSUInteger)sectionIndex
{
	// Todo
	return nil;
}

- (NSString *)keyAtIndexPath:(NSIndexPath *)indexPath
{
	// Todo
	return nil;
}

- (id)objectAtIndex:(NSUInteger)keyIndex inSection:(NSUInteger)sectionIndex
{
	// Todo
	return nil;
}

- (id)objectAtIndexPath:(NSIndexPath *)indexPath
{
	// Todo
	return nil;
}

- (NSIndexPath *)indexPathForKey:(NSString *)key
{
	// Todo...
	return nil;
}

- (void)getIndex:(NSUInteger *)indexPtr section:(NSUInteger *)sectionIndex forKey:(NSString *)key
{
	// Todo
}

@end
