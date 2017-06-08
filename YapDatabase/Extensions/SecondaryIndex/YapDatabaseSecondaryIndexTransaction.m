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
#pragma unused(ydbLogLevel)

static NSString *const ext_key_classVersion       = @"classVersion";
static NSString *const ext_key_versionTag         = @"versionTag";
static NSString *const ext_key_version_deprecated = @"version";


@implementation YapDatabaseSecondaryIndexTransaction

- (id)initWithParentConnection:(YapDatabaseSecondaryIndexConnection *)inParentConnection
           databaseTransaction:(YapDatabaseReadTransaction *)inDatabaseTransaction
{
	if ((self = [super init]))
	{
		parentConnection = inParentConnection;
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
	BOOL hasOldClassVersion = [self getIntValue:&oldClassVersion forExtensionKey:ext_key_classVersion persistent:YES];
	
	int classVersion = YAP_DATABASE_SECONDARY_INDEX_CLASS_VERSION;
	
	if (oldClassVersion != classVersion)
	{
		// First time registration (or at least for this version)
		
		if (hasOldClassVersion) {
			if (![self dropTable]) return NO;
		}
		
		if (![self createTable]) return NO;
		if (![self populate]) return NO;
		
		[self setIntValue:classVersion forExtensionKey:ext_key_classVersion persistent:YES];
		
		NSString *versionTag = parentConnection->parent->versionTag;
		[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:YES];
	}
	else
	{
		// Check user-supplied versionTag.
		// We may need to re-populate the database if it changed.
		
		NSString *versionTag = parentConnection->parent->versionTag;
		
		NSString *oldVersionTag = [self stringValueForExtensionKey:ext_key_versionTag persistent:YES];
		
		BOOL hasOldVersion_deprecated = NO;
		if (oldVersionTag == nil)
		{
			int oldVersion_deprecated = 0;
			hasOldVersion_deprecated = [self getIntValue:&oldVersion_deprecated
			                             forExtensionKey:ext_key_version_deprecated persistent:YES];
			
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
			
			[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:YES];
			
			if (hasOldVersion_deprecated)
				[self removeValueForExtensionKey:ext_key_version_deprecated persistent:YES];
		}
		else if (hasOldVersion_deprecated)
		{
			[self removeValueForExtensionKey:ext_key_version_deprecated persistent:YES];
			[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:YES];
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
			
			YapDatabaseSecondaryIndexSetup *setup = parentConnection->parent->setup;
			
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
	YapDatabaseSecondaryIndexSetup *setup = parentConnection->parent->setup;
	
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
		else if (column.type == YapDatabaseSecondaryIndexTypeNumeric)
		{
			[createTable appendFormat:@", \"%@\" NUMERIC", column.name];
		}
		else if (column.type == YapDatabaseSecondaryIndexTypeText)
		{
			[createTable appendFormat:@", \"%@\" TEXT", column.name];
		}
		else if (column.type == YapDatabaseSecondaryIndexTypeBlob)
		{
			[createTable appendFormat:@", \"%@\" BLOB", column.name];
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
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = parentConnection->parent;
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = secondaryIndex->options.allowedCollections;
	
	YapDatabaseSecondaryIndexHandler *handler = secondaryIndex->handler;
	YapDatabaseBlockType blockType = handler->blockType;
	
	if (blockType == YapDatabaseBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithKeyBlock secondaryIndexBlock =
		    (YapDatabaseSecondaryIndexWithKeyBlock)handler->block;
		
		void (^enumBlock)(int64_t rowid, NSString *collection, NSString *key, BOOL *stop);
		enumBlock = ^(int64_t rowid, NSString *collection, NSString *key, BOOL __unused *stop) {
			
			secondaryIndexBlock(databaseTransaction, parentConnection->blockDict, collection, key);
			
			if ([parentConnection->blockDict count] > 0)
			{
				[self addRowid:rowid isNew:YES];
				[parentConnection->blockDict removeAllObjects];
			}
		};
		
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
				
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
	else if (blockType == YapDatabaseBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithObjectBlock secondaryIndexBlock =
		    (YapDatabaseSecondaryIndexWithObjectBlock)handler->block;
		
		void (^enumBlock)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop);
		enumBlock = ^(int64_t rowid, NSString *collection, NSString *key, id object, BOOL __unused *stop) {
			
			secondaryIndexBlock(databaseTransaction, parentConnection->blockDict, collection, key, object);
			
			if ([parentConnection->blockDict count] > 0)
			{
				[self addRowid:rowid isNew:YES];
				[parentConnection->blockDict removeAllObjects];
			}
		};
		
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
				
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
	else if (blockType == YapDatabaseBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithMetadataBlock secondaryIndexBlock =
		    (YapDatabaseSecondaryIndexWithMetadataBlock)handler->block;
		
		void (^enumBlock)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop);
		enumBlock = ^(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL __unused *stop) {
			
			secondaryIndexBlock(databaseTransaction, parentConnection->blockDict, collection, key, metadata);
			
			if ([parentConnection->blockDict count] > 0)
			{
				[self addRowid:rowid isNew:YES];
				[parentConnection->blockDict removeAllObjects];
			}
		};
		
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
				
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
	else // if (blockType == YapDatabaseBlockTypeWithRow)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithRowBlock secondaryIndexBlock =
		    (YapDatabaseSecondaryIndexWithRowBlock)handler->block;
		
		void (^enumBlock)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop);
		enumBlock = ^(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL __unused *stop) {
			
			secondaryIndexBlock(databaseTransaction, parentConnection->blockDict, collection, key, object, metadata);
			
			if ([parentConnection->blockDict count] > 0)
			{
				[self addRowid:rowid isNew:YES];
				[parentConnection->blockDict removeAllObjects];
			}
		};
		
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
				
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
	return parentConnection;
}

- (NSString *)registeredName
{
	return [parentConnection->parent registeredName];
}

- (NSString *)tableName
{
	return [parentConnection->parent tableName];
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
		statement = [parentConnection insertStatement];
	else
		statement = [parentConnection updateStatement];
	
	if (statement == NULL)
		return;
	
	//  isNew : INSERT            INTO "tableName" ("rowid", "column1", "column2", ...) VALUES (?, ?, ? ...);
	// !isNew : INSERT OR REPLACE INTO "tableName" ("rowid", "column1", "column2", ...) VALUES (?, ?, ? ...);
	
	int bind_idx = SQLITE_BIND_START;
	
	sqlite3_bind_int64(statement, bind_idx, rowid);
	bind_idx++;
	
	for (YapDatabaseSecondaryIndexColumn *column in parentConnection->parent->setup)
	{
		id columnValue = [parentConnection->blockDict objectForKey:column.name];
		if (columnValue && columnValue != [NSNull null])
		{
			if (column.type == YapDatabaseSecondaryIndexTypeInteger ||
			    column.type == YapDatabaseSecondaryIndexTypeReal    ||
			    column.type == YapDatabaseSecondaryIndexTypeNumeric  )
			{
				if ([columnValue isKindOfClass:[NSNumber class]])
				{
					__unsafe_unretained NSNumber *number = (NSNumber *)columnValue;
					
					CFNumberType numberType = CFNumberGetType((CFNumberRef)number);
					
					if (numberType == kCFNumberFloat32Type ||
						numberType == kCFNumberFloat64Type ||
						numberType == kCFNumberFloatType   ||
						numberType == kCFNumberDoubleType  ||
						numberType == kCFNumberCGFloatType  )
					{
						double num = [number doubleValue];
						sqlite3_bind_double(statement, bind_idx, num);
					}
					else
					{
						int64_t num = [number longLongValue];
						sqlite3_bind_int64(statement, bind_idx, (sqlite3_int64)num);
					}
				}
				else if ([columnValue isKindOfClass:[NSDate class]])
				{
					__unsafe_unretained NSDate *date = (NSDate *)columnValue;
					
					double num = [date timeIntervalSinceReferenceDate];
					sqlite3_bind_double(statement, bind_idx, num);
				}
				else
				{
					YDBLogWarn(@"Unable to bind value for column(name=%@, type=%@) with unsupported class: %@."
					           @" Column requires NSNumber or NSDate.",
					           column.name,
					           NSStringFromYapDatabaseSecondaryIndexType(column.type),
					           NSStringFromClass([columnValue class]));
				}
			}
			else if (column.type == YapDatabaseSecondaryIndexTypeText)
			{
				if ([columnValue isKindOfClass:[NSString class]])
				{
					__unsafe_unretained NSString *string = (NSString *)columnValue;
					
					sqlite3_bind_text(statement, bind_idx, [string UTF8String], -1, SQLITE_TRANSIENT);
				}
				else
				{
					YDBLogWarn(@"Unable to bind value for column(name=%@, type=text) with unsupported class: %@."
					           @" Column requires NSString.",
					           column.name, NSStringFromClass([columnValue class]));
				}
			}
			else if (column.type == YapDatabaseSecondaryIndexTypeBlob)
			{
				if ([columnValue isKindOfClass:[NSData class]])
				{
					__unsafe_unretained NSData *data = (NSData *)columnValue;
					
					sqlite3_bind_blob(statement, bind_idx, [data bytes], (int)[data length], SQLITE_STATIC);
				}
				else
				{
					YDBLogWarn(@"Unable to bind value for column(name=%@, type=text) with unsupported class: %@."
					           @" Column requires NSData.",
					           column.name, NSStringFromClass([columnValue class]));
				}
			}
		}
		
		bind_idx++;
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
	
	[parentConnection->mutationStack markAsMutated];
}

- (void)removeRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [parentConnection removeStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "tableName" WHERE "rowid" = ?;
	
	int const bind_idx_rowid = SQLITE_BIND_START;
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeStatement': %d %s",
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	[parentConnection->mutationStack markAsMutated];
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
			[query appendString:@"?"];
		else
			[query appendString:@", ?"];
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
		
		sqlite3_bind_int64(statement, (int)(SQLITE_BIND_START + i), rowid);
	}
	
	status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeRowids' statement: %d %s",
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_finalize(statement);
	
	[parentConnection->mutationStack markAsMutated];
}

- (void)removeAllRowids
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [parentConnection removeAllStatement];
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
	
	[parentConnection->mutationStack markAsMutated];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cleanup & Commit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtension
**/
- (void)didCommitTransaction
{
	YDBLogAutoTrace();
	
	[parentConnection postCommitCleanup];
	
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	parentConnection = nil;    // Do not remove !
	databaseTransaction = nil; // Do not remove !
}

/**
 * Required override method from YapDatabaseExtension
**/
- (void)didRollbackTransaction
{
	YDBLogAutoTrace();
	
	[parentConnection postRollbackCleanup];
	
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	parentConnection = nil;    // Do not remove !
	databaseTransaction = nil; // Do not remove !
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Private helper method for other handleXXX hook methods.
**/
- (void)_handleChangeWithRowid:(int64_t)rowid
                 collectionKey:(YapCollectionKey *)collectionKey
                        object:(id)object
                      metadata:(id)metadata
                      isInsert:(BOOL)isInsert
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = parentConnection->parent;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = secondaryIndex->options.allowedCollections;
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Invoke the block to find out if the object should be included in the index.
	
	YapDatabaseSecondaryIndexHandler *handler = secondaryIndex->handler;
	YapDatabaseBlockType blockType = handler->blockType;
	
	if (blockType == YapDatabaseBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithKeyBlock block =
		    (YapDatabaseSecondaryIndexWithKeyBlock)handler->block;
		
		block(databaseTransaction, parentConnection->blockDict, collection, key);
	}
	else if (blockType == YapDatabaseBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithObjectBlock block =
		    (YapDatabaseSecondaryIndexWithObjectBlock)handler->block;
		
		block(databaseTransaction, parentConnection->blockDict, collection, key, object);
	}
	else if (blockType == YapDatabaseBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithMetadataBlock block =
		    (YapDatabaseSecondaryIndexWithMetadataBlock)handler->block;
		
		block(databaseTransaction, parentConnection->blockDict, collection, key, metadata);
	}
	else
	{
		__unsafe_unretained YapDatabaseSecondaryIndexWithRowBlock block =
		    (YapDatabaseSecondaryIndexWithRowBlock)handler->block;
		
		block(databaseTransaction, parentConnection->blockDict, collection, key, object, metadata);
	}
	
	if ([parentConnection->blockDict count] == 0)
	{
		// Remove associated values from index (if needed).
		
		if (!isInsert)
		{
			[self removeRowid:rowid];
		}
	}
	else
	{
		// Add values to index (or update them).
		// This was an update operation, so we need to insert or update.
		
		[self addRowid:rowid isNew:isInsert];
		[parentConnection->blockDict removeAllObjects];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didInsertObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    isInsert:YES];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didUpdateObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = parentConnection->parent;
	__unsafe_unretained YapDatabaseSecondaryIndexHandler *handler = secondaryIndex->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectModified |
	                                            YapDatabaseBlockInvokeIfMetadataModified;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitMask))
	{
		return;
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    isInsert:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = parentConnection->parent;
	__unsafe_unretained YapDatabaseSecondaryIndexHandler *handler = secondaryIndex->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectModified;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitMask))
	{
		return;
	}
	
	id metadata = nil;
	if (handler->blockType & YapDatabaseBlockType_MetadataFlag)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    isInsert:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = parentConnection->parent;
	__unsafe_unretained YapDatabaseSecondaryIndexHandler *handler = secondaryIndex->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfMetadataModified;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitMask))
	{
		return;
	}
	
	id object = nil;
	if (handler->blockType & YapDatabaseBlockType_ObjectFlag)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    isInsert:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didTouchObjectForCollectionKey:(YapCollectionKey __unused *)collectionKey withRowid:(int64_t __unused)rowid
{
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = parentConnection->parent;
	__unsafe_unretained YapDatabaseSecondaryIndexHandler *handler = secondaryIndex->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectTouched;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitMask))
	{
		return;
	}
	
	id object = nil;
	if (handler->blockType & YapDatabaseBlockType_ObjectFlag)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if (handler->blockType & YapDatabaseBlockType_MetadataFlag)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    isInsert:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didTouchMetadataForCollectionKey:(YapCollectionKey __unused *)collectionKey withRowid:(int64_t __unused)rowid
{
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = parentConnection->parent;
	__unsafe_unretained YapDatabaseSecondaryIndexHandler *handler = secondaryIndex->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfMetadataTouched;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitMask))
	{
		return;
	}
	
	id object = nil;
	if (handler->blockType & YapDatabaseBlockType_ObjectFlag)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if (handler->blockType & YapDatabaseBlockType_MetadataFlag)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    isInsert:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didTouchRowForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = parentConnection->parent;
	__unsafe_unretained YapDatabaseSecondaryIndexHandler *handler = secondaryIndex->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectTouched |
	                                            YapDatabaseBlockInvokeIfMetadataTouched;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitMask))
	{
		return;
	}
	
	id object = nil;
	if (handler->blockType & YapDatabaseBlockType_ObjectFlag)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if (handler->blockType & YapDatabaseBlockType_MetadataFlag)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    isInsert:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didRemoveObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = parentConnection->parent;
	
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
- (void)didRemoveObjectsForKeys:(NSArray __unused *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSecondaryIndex *secondaryIndex = parentConnection->parent;
	
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
- (void)didRemoveAllObjectsInAllCollections
{
	YDBLogAutoTrace();
	
	[self removeAllRowids];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)prepareQueryString:(NSString *)fullQueryString
{
	sqlite3_stmt *statement = NULL;
	
	YapDatabaseStatement *wrapper = [parentConnection->queryCache objectForKey:fullQueryString];
	if (wrapper)
	{
		statement = wrapper.stmt;
	}
	else
	{
		sqlite3 *db = databaseTransaction->connection->db;
		
		int status = sqlite3_prepare_v2(db, [fullQueryString UTF8String], -1, &statement, NULL);
		if (status == SQLITE_OK)
		{
			if (parentConnection->queryCache)
			{
				wrapper = [[YapDatabaseStatement alloc] initWithStatement:statement];
				[parentConnection->queryCache setObject:wrapper forKey:fullQueryString];
			}
		}
		else
		{
			YDBLogError(@"%@: Error creating query:\n query: '%@'\n error: %d %s",
						THIS_METHOD, fullQueryString, status, sqlite3_errmsg(db));
			
			return NULL;
		}
	}
	
	return statement;
}

- (void)bindQueryParameters:(NSArray *)queryParams forStatement:(sqlite3_stmt *)statement withOffset:(int)bind_idx_start
{
	int bind_idx = bind_idx_start;
	
	for (id value in queryParams)
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
				sqlite3_bind_double(statement, bind_idx, num);
			}
			else
			{
				int64_t num = [cast longLongValue];
				sqlite3_bind_int64(statement, bind_idx, (sqlite3_int64)num);
			}
		}
		else if ([value isKindOfClass:[NSDate class]])
		{
			__unsafe_unretained NSDate *cast = (NSDate *)value;
			
			double num = [cast timeIntervalSinceReferenceDate];
			sqlite3_bind_double(statement, bind_idx, num);
		}
		else if ([value isKindOfClass:[NSString class]])
		{
			__unsafe_unretained NSString *cast = (NSString *)value;
			
			sqlite3_bind_text(statement, bind_idx, [cast UTF8String], -1, SQLITE_TRANSIENT);
		}
		else
		{
			YDBLogWarn(@"Unable to bind value for with unsupported class: %@", NSStringFromClass([value class]));
		}
		
		bind_idx++;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Standard Query - Enumerate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)_enumerateRowidsMatchingQuery:(YapDatabaseQuery *)query
                           usingBlock:(void (^)(int64_t rowid, BOOL *stop))block
{
	if (query == nil) return NO;
	if (query.isAggregateQuery) return NO;
	
	// Create full query using given filtering clause(s)
	
	NSString *fullQueryString =
	    [NSString stringWithFormat:@"SELECT \"rowid\" FROM \"%@\" %@;", [self tableName], query.queryString];
	
	// Turn query into compiled sqlite statement (using cache if possible)
	
	sqlite3_stmt *statement = [self prepareQueryString:fullQueryString];
	if (statement == NULL)
	{
		return NO;
	}
	
	// Bind query parameters appropriately.
	
	[self bindQueryParameters:query.queryParameters forStatement:statement withOffset:SQLITE_BIND_START];
	
	// Enumerate query results
	
	BOOL stop = NO;
	YapMutationStackItem_Bool *mutation = [parentConnection->mutationStack push]; // mutation during enum protection
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t rowid = sqlite3_column_int64(statement, SQLITE_COLUMN_START);
		
		block(rowid, &stop);
			
		if (stop || mutation.isMutated) break;
	}
	
	if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (!stop && mutation.isMutated)
	{
		@throw [self mutationDuringEnumerationException];
	}
	
	return (status == SQLITE_DONE);
}

- (BOOL)enumerateKeysMatchingQuery:(YapDatabaseQuery *)query
                        usingBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block
{
	BOOL result = [self _enumerateRowidsMatchingQuery:query usingBlock:^(int64_t rowid, BOOL *stop) {
		
		if (block == NULL) // Query test : caller still wants BOOL result
		{
			*stop = YES;
			return; // from block
		}
		
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		block(ck.collection, ck.key, stop);
	}];
	
	return result;
}

- (BOOL)enumerateKeysAndMetadataMatchingQuery:(YapDatabaseQuery *)query
                                   usingBlock:
                            (void (^)(NSString *collection, NSString *key, id metadata, BOOL *stop))block
{
	BOOL result = [self _enumerateRowidsMatchingQuery:query usingBlock:^(int64_t rowid, BOOL *stop) {
		
		if (block == NULL) // Query test : caller still wants BOOL result
		{
			*stop = YES;
			return; // from block
		}
		
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
	BOOL result = [self _enumerateRowidsMatchingQuery:query usingBlock:^(int64_t rowid, BOOL *stop) {
		
		if (block == NULL) // Query test : caller still wants BOOL result
		{
			*stop = YES;
			return; // from block
		}
		
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
	BOOL result = [self _enumerateRowidsMatchingQuery:query usingBlock:^(int64_t rowid, BOOL *stop) {
		
		if (block == NULL) // Query test : caller still wants BOOL result
		{
			*stop = YES;
			return; // from block
		}
		
		YapCollectionKey *ck = nil;
		id object = nil;
		id metadata = nil;
		[databaseTransaction getCollectionKey:&ck object:&object metadata:&metadata forRowid:rowid];
		
		block(ck.collection, ck.key, object, metadata, stop);
	}];
	
	return result;
}

- (BOOL)_enumerateIndexedValuesInColumn:(NSString *)column
                          matchingQuery:(YapDatabaseQuery *)query
                             usingBlock:(void (^)(id indexedValue, BOOL *stop))block
{
	if (column == nil) return NO;
	if (query == nil) return NO;
	if (query.isAggregateQuery) return NO;

	// Create full query using given filtering clause(s)

	NSString *fullQueryString =
	  [NSString stringWithFormat:@"SELECT \"%@\" AS IndexedValue FROM \"%@\" %@;",
	  column, [self tableName], query.queryString];

	// Turn query into compiled sqlite statement (using cache if possible)

	sqlite3_stmt *statement = [self prepareQueryString:fullQueryString];
	if (statement == NULL)
	{
		return NO;
	}

	// Bind query parameters appropriately.

	[self bindQueryParameters:query.queryParameters forStatement:statement withOffset:SQLITE_BIND_START];

	// Enumerate query results

	BOOL stop = NO;
	YapMutationStackItem_Bool *mutation = [parentConnection->mutationStack push]; // mutation during enum protection

	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int columnType = sqlite3_column_type(statement, SQLITE_COLUMN_START);
		id indexedValue = nil;

		switch(columnType) {
			case SQLITE_INTEGER:
			{
				int64_t value = sqlite3_column_int64(statement, SQLITE_COLUMN_START);
				indexedValue = @(value);
				break;
			}
			
			case SQLITE_FLOAT:
			{
				double value = sqlite3_column_double(statement, SQLITE_COLUMN_START);
				indexedValue = @(value);
				break;
			}

			case SQLITE_TEXT:
			{
				const unsigned char *text = sqlite3_column_text(statement, SQLITE_COLUMN_START);
				int textSize = sqlite3_column_bytes(statement, SQLITE_COLUMN_START);
				indexedValue = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				break;
			}

			case SQLITE_BLOB:
			{
				const void *value = sqlite3_column_blob(statement, SQLITE_COLUMN_START);
				int valueSize = sqlite3_column_bytes(statement, SQLITE_COLUMN_START);
				indexedValue = [[NSData alloc] initWithBytes:value length:valueSize];
				break;
			}
		}
		
		block(indexedValue, &stop);

		if (stop || mutation.isMutated) break;
	}

	if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD,
					status, sqlite3_errmsg(databaseTransaction->connection->db));
	}

	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);

	if (!stop && mutation.isMutated)
	{
		@throw [self mutationDuringEnumerationException];
	}

	return (status == SQLITE_DONE);
}

- (BOOL)enumerateIndexedValuesInColumn:(NSString *)column
                         matchingQuery:(YapDatabaseQuery *)query
                            usingBlock:(void(^)(id indexedValue, BOOL *stop))block
{
	BOOL result = [self _enumerateIndexedValuesInColumn:column
	                                      matchingQuery:query
	                                         usingBlock:^(id indexedValue, BOOL *stop)
	{
		if (block == NULL) // Query test : caller still wants BOOL result
		{
			*stop = YES;
			return; // from block
		}

		block(indexedValue, stop);
	}];

	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Standard Query - Count
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)getNumberOfRows:(NSUInteger *)countPtr matchingQuery:(YapDatabaseQuery *)query
{
	// Create full query using given filtering clause(s)
	
	NSString *fullQueryString =
	    [NSString stringWithFormat:@"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" %@;",
	                                                           [self tableName], query.queryString];
	
	// Turn query into compiled sqlite statement (using cache if possible)
	
	sqlite3_stmt *statement = [self prepareQueryString:fullQueryString];
	if (statement == NULL)
	{
		return NO;
	}
	
	// Bind query parameters appropriately
	
	[self bindQueryParameters:query.queryParameters forStatement:statement withOffset:SQLITE_BIND_START];
	
	// Execute query
	
	BOOL result = YES;
	NSUInteger count = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = (NSUInteger)sqlite3_column_int64(statement, SQLITE_COLUMN_START);
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
#pragma mark Aggregate Query
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)performAggregateQuery:(YapDatabaseQuery *)query
{
	if (query == nil) return nil;
	if (query.isAggregateQuery == NO) return nil;
	
	NSString *fullQueryString =
	    [NSString stringWithFormat:@"SELECT %@ AS Result FROM \"%@\" %@;",
	                                        query.aggregateFunction, [self tableName], query.queryString];
	
	// Turn query into compiled sqlite statement (using cache if possible)
	
	sqlite3_stmt *statement = [self prepareQueryString:fullQueryString];
	if (statement == NULL)
	{
		return nil;
	}
	
	// Bind query parameters appropriately
	
	[self bindQueryParameters:query.queryParameters forStatement:statement withOffset:SQLITE_BIND_START];
	
	// Execute query
	
	id result = nil;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		int column_idx = SQLITE_COLUMN_START;
		int column_type = sqlite3_column_type(statement, column_idx);
		
		if (column_type == SQLITE_INTEGER)
		{
			int64_t num = sqlite3_column_int64(statement, column_idx);
			result = @(num);
		}
		else if (column_type == SQLITE_FLOAT)
		{
			double num = sqlite3_column_double(statement, column_idx);
			result = @(num);
		}
		else if (column_type == SQLITE_TEXT)
		{
			const unsigned char *text = sqlite3_column_text(statement, column_idx);
			int textSize = sqlite3_column_bytes(statement, column_idx);
			
			result = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		else if (column_type == SQLITE_BLOB)
		{
			const void *blob = sqlite3_column_blob(statement, column_idx);
			int blobSize = sqlite3_column_bytes(statement, column_idx);
			
			result = [[NSData alloc] initWithBytes:blob length:blobSize];
		}
		else if (column_type == SQLITE_NULL)
		{
			result = [NSNull null];
		}
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Query Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method assists in performing a query over a subset of rows,
 * where the subset is a known set of keys.
 * 
 * For example:
 * 
 * Say you have a bunch of tracks & playlist objects in the database.
 * And you've added a secondary index on track.duration.
 * Now you want to quickly figure out the duration of an entire playlist.
 * 
 * NSArray *keys = [self trackKeysInPlaylist:playlist];
 * NSArray *rowids = [[[transaction ext:@"idx"] rowidsForKeys:keys inCollection:@"tracks"] allValues];
 *
 * YapDatabaseQuery *query =
 *   [YapDatabaseQuery queryWithAggregateFunction:@"SUM(duration)" format:@"WHERE rowid IN (?)", rowids];
**/
- (NSDictionary<NSString*, NSNumber*> *)rowidsForKeys:(NSArray<NSString *> *)keys
                                         inCollection:(nullable NSString *)collection
{
	NSMutableDictionary<NSString*, NSNumber*> *results = [NSMutableDictionary dictionaryWithCapacity:keys.count];
	
	[databaseTransaction _enumerateRowidsForKeys:keys
	                                inCollection:collection
	                         unorderedUsingBlock:^(NSUInteger keyIndex, int64_t rowid, BOOL *stop)
	{
		NSString *key = keys[keyIndex];
		results[key] = @(rowid);
	}];
	
	return results;
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
