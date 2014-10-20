#import "YapDatabaseSecondaryIndexTransaction.h"
#import "YapDatabaseSecondaryIndexPrivate.h"
#import "YapDatabaseStatement.h"

#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"

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

static NSString *const ExtKey_classVersion       = @"classVersion";
static NSString *const ExtKey_versionTag         = @"versionTag";
static NSString *const ExtKey_version_deprecated = @"version";


@implementation YapDatabaseSecondaryIndexTransaction

- (id)initWithSecondaryIndexConnection:(YapDatabaseSecondaryIndexConnection *)inSecondaryIndexConnection
                   databaseTransaction:(YapDatabaseReadTransaction *)inDatabaseTransaction
{
	if ((self = [super init]))
	{
		secondaryIndexConnection = inSecondaryIndexConnection;
		databaseTransaction = inDatabaseTransaction;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extension Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionTransaction.
 *
 * This method is called to create any necessary tables (if needed),
 * as well as populate the view (if needed) by enumerating over the existing rows in the database.
**/
- (BOOL)createIfNeeded
{
	int oldClassVersion = 0;
	BOOL hasOldClassVersion = [self getIntValue:&oldClassVersion forExtensionKey:ExtKey_classVersion persistent:YES];
	
	int classVersion = YAP_DATABASE_SECONDARY_INDEX_CLASS_VERSION;
	
	if (oldClassVersion != classVersion)
	{
		// First time registration (or at least for this version)
		
		if (hasOldClassVersion) {
			if (![self dropTable]) return NO;
		}
		
		if (![self createTable]) return NO;
		if (![self populate]) return NO;
		
		[self setIntValue:classVersion forExtensionKey:ExtKey_classVersion persistent:YES];
		
		NSString *versionTag = secondaryIndexConnection->secondaryIndex->versionTag;
		[self setStringValue:versionTag forExtensionKey:ExtKey_versionTag persistent:YES];
	}
	else
	{
		// Check user-supplied versionTag.
		// We may need to re-populate the database if it changed.
		
		NSString *versionTag = secondaryIndexConnection->secondaryIndex->versionTag;
		
		NSString *oldVersionTag = [self stringValueForExtensionKey:ExtKey_versionTag persistent:YES];
		
		BOOL hasOldVersion_deprecated = NO;
		if (oldVersionTag == nil)
		{
			int oldVersion_deprecated = 0;
			hasOldVersion_deprecated = [self getIntValue:&oldVersion_deprecated
			                             forExtensionKey:ExtKey_version_deprecated persistent:YES];
			
			if (hasOldVersion_deprecated)
			{
				oldVersionTag = [NSString stringWithFormat:@"%d", oldVersion_deprecated];
			}
		}
		
		if (![oldVersionTag isEqualToString:versionTag])
		{
			if (![self dropTable]) return NO;
			if (![self createTable]) return NO;
			if (![self populate]) return NO;
			
			[self setStringValue:versionTag forExtensionKey:ExtKey_versionTag persistent:YES];
			
			if (hasOldVersion_deprecated)
				[self removeValueForExtensionKey:ExtKey_version_deprecated persistent:YES];
		}
		else if (hasOldVersion_deprecated)
		{
			[self removeValueForExtensionKey:ExtKey_version_deprecated persistent:YES];
			[self setStringValue:versionTag forExtensionKey:ExtKey_versionTag persistent:YES];
		}
		
		// The following code is designed to assist developers in understanding extension changes.
		// The rules are straight-forward and easy to remember:
		//
		// - If you make ANY changes to the configuration of the extension then you MUST change the version.
		//
		// For this extension, that means you MUST change the version if ANY of the following are true:
		//
		// - you changed the setup
		// - you changed the block in any meaningful way (which would result in different values for any existing row)
		//
		// Note: The code below detects only changes to the setup.
		// It could theoretically handle such changes, and automatically force a repopulation.
		// This is a bad idea for two reasons:
		//
		// - First, it complicates the rules. The rules, as stated above, are simple. They follow the KISS principle.
		//   Changing these rules would pose a complication that increases cognitive overhead.
		//   It may be easy to remember now, but 6 months from now the nuance has become hazy.
		//   Additionally, the rest of the database system follows the same set of rules.
		//   So adding a complication for just a particular extension is even more confusing.
		//
		// - Second, it adds overhead to the registration process.
		//   This sanity check doesn't come for free.
		//   And the overhead is only helpful during the development lifecycle.
		//   It's certainly not something you want in a shipped version.
		//
		#if DEBUG
		if ([oldVersionTag isEqualToString:versionTag])
		{
			sqlite3 *db = databaseTransaction->connection->db;
			
			NSDictionary *columns = [YapDatabase columnNamesAndAffinityForTable:[self tableName] using:db];
			
			YapDatabaseSecondaryIndexSetup *setup = secondaryIndexConnection->secondaryIndex->setup;
			
			if (![setup matchesExistingColumnNamesAndAffinity:columns])
			{
				YDBLogError(@"Error creating secondary index extension (%@):"
				            @" The given setup doesn't match the previously registered setup."
				            @" If you change the setup, or you change the block in any meaningful way,"
				            @" then you MUST change the versionTag as well.",
				            THIS_METHOD);
				return NO;
			}
		}
		#endif
	}
	
	return YES;
}

/**
 * Required override method from YapDatabaseExtensionTransaction.
 *
 * This method is called to prepare the transaction for use.
 *
 * Remember, an extension transaction is a very short lived object.
 * Thus it stores the majority of its state within the extension connection (the parent).
 *
 * Return YES if completed successfully, or if already prepared.
 * Return NO if some kind of error occured.
**/
- (BOOL)prepareIfNeeded
{
	return YES;
}

/**
 * Internal method.
 *
 * This method is called, if needed, to drop the old table.
**/
- (BOOL)dropTable
{
	sqlite3 *db = databaseTransaction->connection->db;
	
	NSString *tableName = [self tableName];
	NSString *dropTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", tableName];
	
	int status = sqlite3_exec(db, [dropTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed dropping secondary index table (%@): %d %s",
		            THIS_METHOD, dropTable, status, sqlite3_errmsg(db));
		return NO;
	}
	
	return YES;
}

/**
 * Internal method.
 *
 * This method is called, if needed, to create the tables for the view.
**/
- (BOOL)createTable
{
	sqlite3 *db = databaseTransaction->connection->db;
	
	NSString *tableName = [self tableName];
	YapDatabaseSecondaryIndexSetup *setup = secondaryIndexConnection->secondaryIndex->setup;
	
	YDBLogVerbose(@"Creating secondary index table for registeredName(%@): %@", [self registeredName], tableName);
	
	// CREATE TABLE  IF NOT EXISTS "tableName" ("rowid" INTEGER PRIMARY KEY, index1, index2...);
	
	NSMutableString *createTable = [NSMutableString stringWithCapacity:100];
	[createTable appendFormat:@"CREATE TABLE IF NOT EXISTS \"%@\" (\"rowid\" INTEGER PRIMARY KEY", tableName];
	
	for (YapDatabaseSecondaryIndexColumn *column in setup)
	{
		if (column.type == YapDatabaseSecondaryIndexTypeInteger)
		{
			[createTable appendFormat:@", \"%@\" INTEGER", column.name];
		}
		else if (column.type == YapDatabaseSecondaryIndexTypeReal)
		{
			[createTable appendFormat:@", \"%@\" REAL", column.name];
		}
		else if (column.type == YapDatabaseSecondaryIndexTypeText)
		{
			[createTable appendFormat:@", \"%@\" TEXT", column.name];
		}
	}
	
	[createTable appendString:@");"];
	
	int status = sqlite3_exec(db, [createTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating secondary index table (%@): %d %s",
		            THIS_METHOD, tableName, status, sqlite3_errmsg(db));
		return NO;
	}
	
	for (YapDatabaseSecondaryIndexColumn *column in setup)
	{
		NSString *createIndex =
		    [NSString stringWithFormat:@"CREATE INDEX IF NOT EXISTS \"%@\" ON \"%@\" (\"%@\");",
		        column.name, tableName, column.name];
		
		status = sqlite3_exec(db, [createIndex UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Failed creating index on '%@': %d %s", column.name, status, sqlite3_errmsg(db));
			return NO;
		}
	}
	
	return YES;
}

/**
 * Internal method.
 *
 * This method is called, if needed, to populate the FTS indexes.
 * It does so by enumerating the rows in the database, and invoking the usual blocks and insertion methods.
**/
- (BOOL)populate
{
	// Remove everything from the database
	
	[self removeAllRowids];
	
	// Enumerate the existing rows in the database and populate the indexes
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = secondaryIndexConnection->secondaryIndex;
	
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = secondaryIndex->options.allowedCollections;
	
	if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithKeyBlock secondaryIndexBlock =
		    (YapDatabaseSecondaryIndexWithKeyBlock)secondaryIndex->block;
		
		void (^enumBlock)(int64_t rowid, NSString *collection, NSString *key, BOOL *stop);
		enumBlock = ^(int64_t rowid, NSString *collection, NSString *key, BOOL *stop) {
			
			secondaryIndexBlock(secondaryIndexConnection->blockDict, collection, key);
			
			if ([secondaryIndexConnection->blockDict count] > 0)
			{
				[self addRowid:rowid isNew:YES];
				[secondaryIndexConnection->blockDict removeAllObjects];
			}
		};
		
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL *stop) {
				
				if ([allowedCollections isAllowed:collection])
				{
					[databaseTransaction _enumerateKeysInCollections:@[ collection ] usingBlock:enumBlock];
				}
			}];
		}
		else // if (!allowedCollections)
		{
			[databaseTransaction _enumerateKeysInAllCollectionsUsingBlock:enumBlock];
		}
	}
	else if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithObjectBlock secondaryIndexBlock =
		    (YapDatabaseSecondaryIndexWithObjectBlock)secondaryIndex->block;
		
		void (^enumBlock)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop);
		enumBlock = ^(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop) {
			
			secondaryIndexBlock(secondaryIndexConnection->blockDict, collection, key, object);
			
			if ([secondaryIndexConnection->blockDict count] > 0)
			{
				[self addRowid:rowid isNew:YES];
				[secondaryIndexConnection->blockDict removeAllObjects];
			}
		};
		
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL *stop) {
				
				if ([allowedCollections isAllowed:collection])
				{
					[databaseTransaction _enumerateKeysAndObjectsInCollections:@[ collection ]
					                                                usingBlock:enumBlock];
				}
			}];
		}
		else // if (!allowedCollections)
		{
			[databaseTransaction _enumerateKeysAndObjectsInAllCollectionsUsingBlock:enumBlock];
		}
	}
	else if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithMetadataBlock secondaryIndexBlock =
		    (YapDatabaseSecondaryIndexWithMetadataBlock)secondaryIndex->block;
		
		void (^enumBlock)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop);
		enumBlock = ^(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop) {
			
			secondaryIndexBlock(secondaryIndexConnection->blockDict, collection, key, metadata);
			
			if ([secondaryIndexConnection->blockDict count] > 0)
			{
				[self addRowid:rowid isNew:YES];
				[secondaryIndexConnection->blockDict removeAllObjects];
			}
		};
		
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL *stop) {
				
				if ([allowedCollections isAllowed:collection])
				{
					[databaseTransaction _enumerateKeysAndMetadataInCollections:@[ collection ]
					                                                 usingBlock:enumBlock];
				}
			}];
		}
		else // if (!allowedCollections)
		{
			[databaseTransaction _enumerateKeysAndMetadataInAllCollectionsUsingBlock:enumBlock];
		}
	}
	else // if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithRow)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithRowBlock secondaryIndexBlock =
		    (YapDatabaseSecondaryIndexWithRowBlock)secondaryIndex->block;
		
		void (^enumBlock)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop);
		enumBlock = ^(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop) {
			
			secondaryIndexBlock(secondaryIndexConnection->blockDict, collection, key, object, metadata);
			
			if ([secondaryIndexConnection->blockDict count] > 0)
			{
				[self addRowid:rowid isNew:YES];
				[secondaryIndexConnection->blockDict removeAllObjects];
			}
		};
		
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL *stop) {
				
				if ([allowedCollections isAllowed:collection])
				{
					[databaseTransaction _enumerateRowsInCollections:@[ collection ] usingBlock:enumBlock];
				}
			}];
		}
		else // if (!allowedCollections)
		{
			[databaseTransaction _enumerateRowsInAllCollectionsUsingBlock:enumBlock];
		}
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionTransaction.
**/
- (YapDatabaseReadTransaction *)databaseTransaction
{
	return databaseTransaction;
}

/**
 * Required override method from YapDatabaseExtensionTransaction.
**/
- (YapDatabaseExtensionConnection *)extensionConnection
{
	return secondaryIndexConnection;
}

- (NSString *)registeredName
{
	return [secondaryIndexConnection->secondaryIndex registeredName];
}

- (NSString *)tableName
{
	return [secondaryIndexConnection->secondaryIndex tableName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Adds a row to the table, using the given rowid along with the values in the 'blockDict' ivar.
**/
- (void)addRowid:(int64_t)rowid isNew:(BOOL)isNew
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = NULL;
	if (isNew)
		statement = [secondaryIndexConnection insertStatement];
	else
		statement = [secondaryIndexConnection updateStatement];
	
	if (statement == NULL)
		return;
	
	//  isNew : INSERT            INTO "tableName" ("rowid", "column1", "column2", ...) VALUES (?, ?, ? ...);
	// !isNew : INSERT OR REPLACE INTO "tableName" ("rowid", "column1", "column2", ...) VALUES (?, ?, ? ...);
	
	int i = 1;
	
	sqlite3_bind_int64(statement, i, rowid);
	i++;
	
	for (YapDatabaseSecondaryIndexColumn *column in secondaryIndexConnection->secondaryIndex->setup)
	{
		id columnValue = [secondaryIndexConnection->blockDict objectForKey:column.name];
		if (columnValue && columnValue != [NSNull null])
		{
			if (column.type == YapDatabaseSecondaryIndexTypeInteger)
			{
				if ([columnValue isKindOfClass:[NSNumber class]])
				{
					__unsafe_unretained NSNumber *cast = (NSNumber *)columnValue;
					
					int64_t num = [cast longLongValue];
					sqlite3_bind_int64(statement, i, (sqlite3_int64)num);
				}
				else
				{
					YDBLogWarn(@"Unable to bind value for column(name=%@, type=integer) with unsupported class: %@."
					           @" Column requires NSNumber.",
					           column.name, NSStringFromClass([columnValue class]));
				}
			}
			else if (column.type == YapDatabaseSecondaryIndexTypeReal)
			{
				if ([columnValue isKindOfClass:[NSNumber class]])
				{
					__unsafe_unretained NSNumber *cast = (NSNumber *)columnValue;
					
					double num = [cast doubleValue];
					sqlite3_bind_double(statement, i, num);
				}
				else if ([columnValue isKindOfClass:[NSDate class]])
				{
					__unsafe_unretained NSDate *cast = (NSDate *)columnValue;
					
					double num = [cast timeIntervalSinceReferenceDate];
					sqlite3_bind_double(statement, i, num);
				}
				else
				{
					YDBLogWarn(@"Unable to bind value for column(name=%@, type=real) with unsupported class: %@."
					           @" Column requires NSNumber or NSDate.",
					           column.name, NSStringFromClass([columnValue class]));
				}
			}
			else // if (column.type == YapDatabaseSecondaryIndexTypeText)
			{
				if ([columnValue isKindOfClass:[NSString class]])
				{
					__unsafe_unretained NSString *cast = (NSString *)columnValue;
					
					sqlite3_bind_text(statement, i, [cast UTF8String], -1, SQLITE_TRANSIENT);
				}
				else
				{
					YDBLogWarn(@"Unable to bind value for column(name=%@, type=text) with unsupported class: %@."
					           @" Column requires NSString.",
					           column.name, NSStringFromClass([columnValue class]));
				}
			}
		}
		
		i++;
	}
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing '%s': %d %s",
		            isNew ? "insertStatement" : "updateStatement",
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	isMutated = YES;
}

- (void)removeRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [secondaryIndexConnection removeStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "tableName" WHERE "rowid" = ?;
	
	sqlite3_bind_int64(statement, 1, rowid);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeStatement': %d %s",
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	isMutated = YES;
}

- (void)removeRowids:(NSArray *)rowids
{
	YDBLogAutoTrace();
	
	NSUInteger count = [rowids count];
	
	if (count == 0) return;
	if (count == 1)
	{
		int64_t rowid = [[rowids objectAtIndex:0] longLongValue];
		
		[self removeRowid:rowid];
		return;
	}
	
	// DELETE FROM "tableName" WHERE "rowid" in (?, ?, ...);
	//
	// Note: We don't have to worry sqlite's max number of host parameters.
	// YapDatabase gives us the rowids in batches where each batch is already capped at this number.
	
	NSUInteger capacity = 50 + (count * 3);
	NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
	
	[query appendFormat:@"DELETE FROM \"%@\" WHERE \"rowid\" IN (", [self tableName]];
	
	NSUInteger i;
	for (i = 0; i < count; i++)
	{
		if (i == 0)
			[query appendFormat:@"?"];
		else
			[query appendFormat:@", ?"];
	}
	
	[query appendString:@");"];
	
	sqlite3_stmt *statement;
	
	int status = sqlite3_prepare_v2(databaseTransaction->connection->db, [query UTF8String], -1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error creating 'removeRowids' statement: %d %s",
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
		return;
	}
	
	for (i = 0; i < count; i++)
	{
		int64_t rowid = [[rowids objectAtIndex:i] longLongValue];
		
		sqlite3_bind_int64(statement, (int)(i + 1), rowid);
	}
	
	status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeRowids' statement: %d %s",
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_finalize(statement);
	
	isMutated = YES;
}

- (void)removeAllRowids
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [secondaryIndexConnection removeAllStatement];
	if (statement == NULL)
		return;
	
	int status;
	
	// DELETE FROM "tableName";
	
	YDBLogVerbose(@"DELETE FROM '%@';", [self tableName]);
	
	status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ (%@): Error in removeAllStatement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
	
	isMutated = YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cleanup & Commit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtension
**/
- (void)didCommitTransaction
{
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	secondaryIndexConnection = nil; // Do not remove !
	databaseTransaction = nil;      // Do not remove !
}

/**
 * Required override method from YapDatabaseExtension
**/
- (void)didRollbackTransaction
{
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	secondaryIndexConnection = nil; // Do not remove !
	databaseTransaction = nil;      // Do not remove !
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleInsertObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = secondaryIndexConnection->secondaryIndex;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = secondaryIndex->options.allowedCollections;
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Invoke the block to find out if the object should be included in the index.
	
	if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithKeyBlock block =
		    (YapDatabaseSecondaryIndexWithKeyBlock)secondaryIndex->block;
		
		block(secondaryIndexConnection->blockDict, collection, key);
	}
	else if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithObjectBlock block =
		    (YapDatabaseSecondaryIndexWithObjectBlock)secondaryIndex->block;
		
		block(secondaryIndexConnection->blockDict, collection, key, object);
	}
	else if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithMetadataBlock block =
		    (YapDatabaseSecondaryIndexWithMetadataBlock)secondaryIndex->block;
		
		block(secondaryIndexConnection->blockDict, collection, key, metadata);
	}
	else
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithRowBlock block =
		    (YapDatabaseSecondaryIndexWithRowBlock)secondaryIndex->block;
		
		block(secondaryIndexConnection->blockDict, collection, key, object, metadata);
	}
	
	if ([secondaryIndexConnection->blockDict count] == 0)
	{
		// This was an insert operation, so we don't have to worry about removing anything.
	}
	else
	{
		// Add values to index.
		// This was an insert operation, so we know we can insert rather than update.
		
		[self addRowid:rowid isNew:YES];
		[secondaryIndexConnection->blockDict removeAllObjects];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleUpdateObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = secondaryIndexConnection->secondaryIndex;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = secondaryIndex->options.allowedCollections;
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Invoke the block to find out if the object should be included in the index.
	
	if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithKeyBlock block =
		    (YapDatabaseSecondaryIndexWithKeyBlock)secondaryIndex->block;
		
		block(secondaryIndexConnection->blockDict, collection, key);
	}
	else if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithObjectBlock block =
		    (YapDatabaseSecondaryIndexWithObjectBlock)secondaryIndex->block;
		
		block(secondaryIndexConnection->blockDict, collection, key, object);
	}
	else if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithMetadataBlock block =
		    (YapDatabaseSecondaryIndexWithMetadataBlock)secondaryIndex->block;
		
		block(secondaryIndexConnection->blockDict, collection, key, metadata);
	}
	else
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithRowBlock block =
		    (YapDatabaseSecondaryIndexWithRowBlock)secondaryIndex->block;
		
		block(secondaryIndexConnection->blockDict, collection, key, object, metadata);
	}
	
	if ([secondaryIndexConnection->blockDict count] == 0)
	{
		// Remove associated values from index (if needed).
		// This was an update operation, so the rowid may have previously had values in the index.
		
		[self removeRowid:rowid];
	}
	else
	{
		// Add values to index (or update them).
		// This was an update operation, so we need to insert or update.
		
		[self addRowid:rowid isNew:NO];
		[secondaryIndexConnection->blockDict removeAllObjects];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = secondaryIndexConnection->secondaryIndex;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = secondaryIndex->options.allowedCollections;
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Invoke the block to find out if the object should be included in the index.
	
	id metadata = nil;
	
	if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithKey ||
	    secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithMetadata)
	{
		// Index values are based on the key or object.
		// Neither have changed, and thus the values haven't changed.
		
		return;
	}
	else
	{
		// Index values are based on object or row (object+metadata).
		// Invoke block to see what the new values are.
		
		if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithObject)
		{
			__unsafe_unretained YapDatabaseSecondaryIndexWithObjectBlock block =
			  (YapDatabaseSecondaryIndexWithObjectBlock)secondaryIndex->block;
			
			block(secondaryIndexConnection->blockDict, collection, key, object);
		}
		else
		{
			__unsafe_unretained YapDatabaseSecondaryIndexWithRowBlock block =
			  (YapDatabaseSecondaryIndexWithRowBlock)secondaryIndex->block;
			
			metadata = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
			block(secondaryIndexConnection->blockDict, collection, key, object, metadata);
		}
		
		if ([secondaryIndexConnection->blockDict count] == 0)
		{
			// Remove associated values from index (if needed).
			// This was an update operation, so the rowid may have previously had values in the index.
			
			[self removeRowid:rowid];
		}
		else
		{
			// Add values to index (or update them).
			// This was an update operation, so we need to insert or update.
			
			[self addRowid:rowid isNew:NO];
			[secondaryIndexConnection->blockDict removeAllObjects];
		}
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = secondaryIndexConnection->secondaryIndex;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = secondaryIndex->options.allowedCollections;
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Invoke the block to find out if the object should be included in the index.
	
	id object = nil;
	
	if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithKey ||
	    secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithObject)
	{
		// Index values are based on the key or object.
		// Neither have changed, and thus the values haven't changed.
		
		return;
	}
	else
	{
		// Index values are based on metadata or objectAndMetadata.
		// Invoke block to see what the new values are.
		
		if (secondaryIndex->blockType == YapDatabaseSecondaryIndexBlockTypeWithMetadata)
		{
			__unsafe_unretained YapDatabaseSecondaryIndexWithMetadataBlock block =
		        (YapDatabaseSecondaryIndexWithMetadataBlock)secondaryIndex->block;
			
			block(secondaryIndexConnection->blockDict, collection, key, metadata);
		}
		else
		{
			__unsafe_unretained YapDatabaseSecondaryIndexWithRowBlock block =
		        (YapDatabaseSecondaryIndexWithRowBlock)secondaryIndex->block;
			
			object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
			block(secondaryIndexConnection->blockDict, collection, key, object, metadata);
		}
		
		if ([secondaryIndexConnection->blockDict count] == 0)
		{
			// Remove associated values from index (if needed).
			// This was an update operation, so the rowid may have previously had values in the index.
			
			[self removeRowid:rowid];
		}
		else
		{
			// Add values to index (or update them).
			// This was an update operation, so we need to insert or update.
			
			[self addRowid:rowid isNew:NO];
			[secondaryIndexConnection->blockDict removeAllObjects];
		}
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleTouchObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	// Nothing to do for this extension
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleTouchMetadataForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	// Nothing to do for this extension
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = secondaryIndexConnection->secondaryIndex;
	
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = secondaryIndex->options.allowedCollections;
	if (allowedCollections && ![allowedCollections isAllowed:collectionKey.collection])
	{
		return;
	}
	
	[self removeRowid:rowid];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = secondaryIndexConnection->secondaryIndex;
	
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = secondaryIndex->options.allowedCollections;
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	[self removeRowids:rowids];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveAllObjectsInAllCollections
{
	YDBLogAutoTrace();
	
	[self removeAllRowids];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Enumerate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)_enumerateRowidsMatchingQuery:(YapDatabaseQuery *)query
                           usingBlock:(void (^)(int64_t rowid, BOOL *stop))block
{
	// Create full query using given filtering clause(s)
	
	NSString *fullQueryString =
	    [NSString stringWithFormat:@"SELECT \"rowid\" FROM \"%@\" %@;", [self tableName], query.queryString];
	
	// Turn query into compiled sqlite statement.
	// Use cache if possible.
	
	sqlite3_stmt *statement = NULL;
	
	YapDatabaseStatement *wrapper = [secondaryIndexConnection->queryCache objectForKey:fullQueryString];
	if (wrapper)
	{
		statement = wrapper.stmt;
	}
	else
	{
		sqlite3 *db = databaseTransaction->connection->db;
		
		int status = sqlite3_prepare_v2(db, [fullQueryString UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating query:\n query: '%@'\n error: %d %s",
						THIS_METHOD, fullQueryString, status, sqlite3_errmsg(db));
			
			return NO;
		}
		
		if (secondaryIndexConnection->queryCache)
		{
			wrapper = [[YapDatabaseStatement alloc] initWithStatement:statement];
			[secondaryIndexConnection->queryCache setObject:wrapper forKey:fullQueryString];
		}
	}
	
	// Bind query parameters appropriately.
	
	int i = 1;
	for (id value in query.queryParameters)
	{
		if ([value isKindOfClass:[NSNumber class]])
		{
			__unsafe_unretained NSNumber *cast = (NSNumber *)value;
			
			CFNumberType numType = CFNumberGetType((__bridge CFNumberRef)cast);
			
			if (numType == kCFNumberFloatType   ||
			    numType == kCFNumberFloat32Type ||
			    numType == kCFNumberFloat64Type ||
			    numType == kCFNumberDoubleType  ||
			    numType == kCFNumberCGFloatType  )
			{
				double num = [cast doubleValue];
				sqlite3_bind_double(statement, i, num);
			}
			else
			{
				int64_t num = [cast longLongValue];
				sqlite3_bind_int64(statement, i, (sqlite3_int64)num);
			}
		}
		else if ([value isKindOfClass:[NSDate class]])
		{
			__unsafe_unretained NSDate *cast = (NSDate *)value;
			
			double num = [cast timeIntervalSinceReferenceDate];
			sqlite3_bind_double(statement, i, num);
		}
		else if ([value isKindOfClass:[NSString class]])
		{
			__unsafe_unretained NSString *cast = (NSString *)value;
			
			sqlite3_bind_text(statement, i, [cast UTF8String], -1, SQLITE_TRANSIENT);
		}
		else
		{
			YDBLogWarn(@"Unable to bind value for with unsupported class: %@", NSStringFromClass([value class]));
		}
		
		i++;
	}
	
	// Enumerate query results
	
	BOOL stop = NO;
	isMutated = NO; // mutation during enumeration protection
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (databaseTransaction->connection->needsMarkSqlLevelSharedReadLock)
			[databaseTransaction->connection markSqlLevelSharedReadLockAcquired];
		
		do
		{
			int64_t rowid = sqlite3_column_int64(statement, 0);
			
			block(rowid, &stop);
			
			if (stop || isMutated) break;
			
		} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
	}
	
	if ((status != SQLITE_DONE) && !stop && !isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (isMutated && !stop)
	{
		@throw [self mutationDuringEnumerationException];
	}
	
	return (status == SQLITE_DONE);
}

- (BOOL)enumerateKeysMatchingQuery:(YapDatabaseQuery *)query
                        usingBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block
{
	if (query == nil) return NO;
	if (block == nil) return NO;
	
	BOOL result = [self _enumerateRowidsMatchingQuery:query usingBlock:^(int64_t rowid, BOOL *stop) {
		
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		block(ck.collection, ck.key, stop);
	}];
	
	return result;
}

- (BOOL)enumerateKeysAndMetadataMatchingQuery:(YapDatabaseQuery *)query
                                   usingBlock:
                            (void (^)(NSString *collection, NSString *key, id metadata, BOOL *stop))block
{
	if (query == nil) return NO;
	if (block == nil) return NO;
	
	BOOL result = [self _enumerateRowidsMatchingQuery:query usingBlock:^(int64_t rowid, BOOL *stop) {
		
		YapCollectionKey *ck = nil;
		id metadata = nil;
		[databaseTransaction getCollectionKey:&ck metadata:&metadata forRowid:rowid];
		
		block(ck.collection, ck.key, metadata, stop);
	}];
	
	return result;
}

- (BOOL)enumerateKeysAndObjectsMatchingQuery:(YapDatabaseQuery *)query
                                  usingBlock:
                            (void (^)(NSString *collection, NSString *key, id object, BOOL *stop))block
{
	if (query == nil) return NO;
	if (block == nil) return NO;
	
	BOOL result = [self _enumerateRowidsMatchingQuery:query usingBlock:^(int64_t rowid, BOOL *stop) {
		
		YapCollectionKey *ck = nil;
		id object = nil;
		[databaseTransaction getCollectionKey:&ck object:&object forRowid:rowid];
		
		block(ck.collection, ck.key, object, stop);
	}];
	
	return result;
}

- (BOOL)enumerateRowsMatchingQuery:(YapDatabaseQuery *)query
                        usingBlock:
                            (void (^)(NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
{
	if (query == nil) return NO;
	if (block == nil) return NO;
	
	BOOL result = [self _enumerateRowidsMatchingQuery:query usingBlock:^(int64_t rowid, BOOL *stop) {
		
		YapCollectionKey *ck = nil;
		id object = nil;
		id metadata = nil;
		[databaseTransaction getCollectionKey:&ck object:&object metadata:&metadata forRowid:rowid];
		
		block(ck.collection, ck.key, object, metadata, stop);
	}];
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Count
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)getNumberOfRows:(NSUInteger *)countPtr matchingQuery:(YapDatabaseQuery *)query
{
	// Create full query using given filtering clause(s)
	
	NSString *fullQueryString =
	    [NSString stringWithFormat:@"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" %@;",
	                                                           [self tableName], query.queryString];
	
	// Turn query into compiled sqlite statement.
	// Use cache if possible.
	
	sqlite3_stmt *statement = NULL;
	
	YapDatabaseStatement *wrapper = [secondaryIndexConnection->queryCache objectForKey:fullQueryString];
	if (wrapper)
	{
		statement = wrapper.stmt;
	}
	else
	{
		sqlite3 *db = databaseTransaction->connection->db;
		
		int status = sqlite3_prepare_v2(db, [fullQueryString UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating query:\n query: '%@'\n error: %d %s",
						THIS_METHOD, fullQueryString, status, sqlite3_errmsg(db));
			
			return NO;
		}
		
		if (secondaryIndexConnection->queryCache)
		{
			wrapper = [[YapDatabaseStatement alloc] initWithStatement:statement];
			[secondaryIndexConnection->queryCache setObject:wrapper forKey:fullQueryString];
		}
	}
	
	// Bind query parameters appropriately.
	
	int i = 1;
	for (id value in query.queryParameters)
	{
		if ([value isKindOfClass:[NSNumber class]])
		{
			__unsafe_unretained NSNumber *cast = (NSNumber *)value;
			
			CFNumberType numType = CFNumberGetType((__bridge CFNumberRef)cast);
			
			if (numType == kCFNumberFloatType   ||
			    numType == kCFNumberFloat32Type ||
			    numType == kCFNumberFloat64Type ||
			    numType == kCFNumberDoubleType  ||
			    numType == kCFNumberCGFloatType  )
			{
				double num = [cast doubleValue];
				sqlite3_bind_double(statement, i, num);
			}
			else
			{
				int64_t num = [cast longLongValue];
				sqlite3_bind_int64(statement, i, (sqlite3_int64)num);
			}
		}
		else if ([value isKindOfClass:[NSDate class]])
		{
			__unsafe_unretained NSDate *cast = (NSDate *)value;
			
			double num = [cast timeIntervalSinceReferenceDate];
			sqlite3_bind_double(statement, i, num);
		}
		else if ([value isKindOfClass:[NSString class]])
		{
			__unsafe_unretained NSString *cast = (NSString *)value;
			
			sqlite3_bind_text(statement, i, [cast UTF8String], -1, SQLITE_TRANSIENT);
		}
		else
		{
			YDBLogWarn(@"Unable to bind value for with unsupported class: %@", NSStringFromClass([value class]));
		}
		
		i++;
	}
	
	// Execute query
	
	BOOL result = YES;
	NSUInteger count = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (databaseTransaction->connection->needsMarkSqlLevelSharedReadLock)
			[databaseTransaction->connection markSqlLevelSharedReadLockAcquired];
		
		count = (NSUInteger)sqlite3_column_int64(statement, 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
		result = NO;
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (countPtr) *countPtr = count;
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Exceptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSException *)mutationDuringEnumerationException
{
	NSString *reason = [NSString stringWithFormat:
	    @"SecondaryIndex <RegisteredName=%@> was mutated while being enumerated.", [self registeredName]];

	NSDictionary *userInfo = @{ NSLocalizedRecoverySuggestionErrorKey:
	    @"In general, you cannot modify the database while enumerating it."
		@" This is similar in concept to an NSMutableArray."
		@" If you only need to make a single modification, you may do so but you MUST set the 'stop' parameter"
		@" of the enumeration block to YES (*stop = YES;) immediately after making the modification."};

	return [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
}

@end
