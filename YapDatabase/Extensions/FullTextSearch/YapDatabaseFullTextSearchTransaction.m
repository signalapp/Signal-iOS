#import "YapDatabaseFullTextSearchTransaction.h"
#import "YapDatabaseFullTextSearchPrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseString.h"
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

static NSString *const ext_key__classVersion       = @"classVersion";
static NSString *const ext_key__versionTag         = @"versionTag";
static NSString *const ext_key__ftsVersion         = @"ftsVersion";
static NSString *const ext_key__version_deprecated = @"version";


@implementation YapDatabaseFullTextSearchTransaction

- (id)initWithParentConnection:(YapDatabaseFullTextSearchConnection *)inParentConnection
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
	BOOL hasOldClassVersion = [self getIntValue:&oldClassVersion forExtensionKey:ext_key__classVersion persistent:YES];
	int classVersion = YAP_DATABASE_FTS_CLASS_VERSION;
	
	if (oldClassVersion != classVersion)
	{
		// First time registration (or at least for this version)
		
		if (hasOldClassVersion) {
			if (![self dropTable]) return NO;
		}
		
		if (![self createTable]) return NO;
		if (![self populate]) return NO;
		
		[self setIntValue:classVersion forExtensionKey:ext_key__classVersion persistent:YES];
		
		NSString *versionTag = parentConnection->parent->versionTag;
		[self setStringValue:versionTag forExtensionKey:ext_key__versionTag persistent:YES];
        
        NSString *ftsVersion = parentConnection->parent->ftsVersion;
        [self setStringValue:ftsVersion forExtensionKey:ext_key__ftsVersion persistent:YES];
	}
	else
	{
		// Check user-supplied config version.
		// We may need to re-populate the database if the groupingBlock, sortingBlock or fts version changed.
		
		NSString *versionTag = parentConnection->parent->versionTag;
		
		NSString *oldVersionTag = [self stringValueForExtensionKey:ext_key__versionTag persistent:YES];
        
        NSString *ftsVersion = parentConnection->parent->ftsVersion;
        
        NSString *oldFtsVesrion = [self stringValueForExtensionKey:ext_key__ftsVersion persistent:YES];
		
		BOOL hasOldVersion_deprecated = NO;
		if (oldVersionTag == nil)
		{
			int oldVersion_deprecated = 0;
			hasOldVersion_deprecated = [self getIntValue:&oldVersion_deprecated
			                             forExtensionKey:ext_key__version_deprecated
			                                  persistent:YES];
			
			if (hasOldVersion_deprecated)
			{
				oldVersionTag = [NSString stringWithFormat:@"%d", oldVersion_deprecated];
			}
		}
		
		if (![oldVersionTag isEqualToString:versionTag] || ![oldFtsVesrion isEqualToString:ftsVersion])
		{
			if (![self dropTable]) return NO;
			if (![self createTable]) return NO;
			if (![self populate]) return NO;
			
			[self setStringValue:versionTag forExtensionKey:ext_key__versionTag persistent:YES];
			
			if (hasOldVersion_deprecated)
				[self removeValueForExtensionKey:ext_key__version_deprecated persistent:YES];
		}
		else if (hasOldVersion_deprecated)
		{
			[self removeValueForExtensionKey:ext_key__version_deprecated persistent:YES];
			[self setStringValue:versionTag forExtensionKey:ext_key__versionTag persistent:YES];
		}
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
		YDBLogError(@"%@ - Failed dropping FTS table (%@): %d %s",
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
	
	YDBLogVerbose(@"Creating FTS table for registeredName(%@): %@", [self registeredName], tableName);
	
	// CREATE VIRTUAL TABLE pages USING fts4(column1, column2, column3) or fts5(column1, column2, column3);
    
    NSString *ftsVersion = parentConnection->parent->ftsVersion;
	
	NSMutableString *createTable = [NSMutableString stringWithCapacity:100];
	[createTable appendFormat:@"CREATE VIRTUAL TABLE IF NOT EXISTS \"%@\" USING %@(", tableName, ftsVersion];
	
	__block NSUInteger i = 0;
	
	NSOrderedSet *columnNames = parentConnection->parent->columnNames;
	for (NSString *columnName in columnNames)
	{
		if (i == 0)
			[createTable appendFormat:@"\"%@\"", columnName];
		else
			[createTable appendFormat:@", \"%@\"", columnName];
		
		i++;
	}
	
	NSDictionary *options = parentConnection->parent->options;
	[options enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop) {
		
		NSString *option = (NSString *)key;
		NSString *value = (NSString *)obj;
		
		if (i == 0)
			[createTable appendFormat:@"%@=%@", option, value];
		else
			[createTable appendFormat:@", %@=%@", option, value];
		
		i++;
	}];
	
	[createTable appendString:@");"];
	
	int status = sqlite3_exec(db, [createTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating FTS table (%@): %d %s",
		            THIS_METHOD, tableName, status, sqlite3_errmsg(db));
		return NO;
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
	
	__unsafe_unretained YapDatabaseFullTextSearchHandler *handler = parentConnection->parent->handler;
	
	if (handler->blockType == YapDatabaseBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseFullTextSearchWithKeyBlock block =
		    (YapDatabaseFullTextSearchWithKeyBlock)handler->block;
		
		[databaseTransaction _enumerateKeysInAllCollectionsUsingBlock:
		    ^(int64_t rowid, NSString *collection, NSString *key, BOOL __unused *stop) {
			
			block(parentConnection->blockDict, collection, key);
			
			if ([parentConnection->blockDict count] > 0)
			{
				[self addRowid:rowid isNew:YES];
				[parentConnection->blockDict removeAllObjects];
			}
		}];
	}
	else if (handler->blockType == YapDatabaseBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseFullTextSearchWithObjectBlock block =
		    (YapDatabaseFullTextSearchWithObjectBlock)handler->block;
		
		[databaseTransaction _enumerateKeysAndObjectsInAllCollectionsUsingBlock:
		    ^(int64_t rowid, NSString *collection, NSString *key, id object, BOOL __unused *stop) {
			
			block(parentConnection->blockDict, collection, key, object);
			
			if ([parentConnection->blockDict count] > 0)
			{
				[self addRowid:rowid isNew:YES];
				[parentConnection->blockDict removeAllObjects];
			}
		}];
	}
	else if (handler->blockType == YapDatabaseBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseFullTextSearchWithMetadataBlock block =
		    (YapDatabaseFullTextSearchWithMetadataBlock)handler->block;
		
		[databaseTransaction _enumerateKeysAndMetadataInAllCollectionsUsingBlock:
		    ^(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL __unused *stop) {
			
			block(parentConnection->blockDict, collection, key, metadata);
			
			if ([parentConnection->blockDict count] > 0)
			{
				[self addRowid:rowid isNew:YES];
				[parentConnection->blockDict removeAllObjects];
			}
		}];
	}
	else // if (handler->blockType == YapDatabaseBlockTypeWithRow)
	{
		__unsafe_unretained YapDatabaseFullTextSearchWithRowBlock block =
		    (YapDatabaseFullTextSearchWithRowBlock)handler->block;
		
		[databaseTransaction _enumerateRowsInAllCollectionsUsingBlock:
		    ^(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL __unused *stop) {
			
			block(parentConnection->blockDict, collection, key, object, metadata);
			
			if ([parentConnection->blockDict count] > 0)
			{
				[self addRowid:rowid isNew:YES];
				[parentConnection->blockDict removeAllObjects];
			}
		}];
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

- (void)addRowid:(int64_t)rowid isNew:(BOOL)isNew
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = NULL;
	if (isNew)
		statement = [parentConnection insertRowidStatement];
	else
		statement = [parentConnection setRowidStatement];
	
	if (statement == NULL)
		return;
	
	//  isNew : INSERT INTO "tableName" ("rowid", "column1", "column2", ...) VALUES (?, ?, ? ...)
	// !isNew : INSERT OR REPLACE INTO "tableName" ("rowid", "column1", "column2", ...) VALUES (?, ?, ? ...)
	
	sqlite3_bind_int64(statement, SQLITE_BIND_START, rowid);
	
	int i = SQLITE_BIND_START + 1;
	for (NSString *columnName in parentConnection->parent->columnNames)
	{
		NSString *columnValue = [parentConnection->blockDict objectForKey:columnName];
		if (columnValue)
		{
			sqlite3_bind_text(statement, i, [columnValue UTF8String], -1, SQLITE_TRANSIENT);
		}
		
		i++;
	}
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing '%s': %d %s",
		            isNew ? "insertRowidStatement" : "setRowidStatement",
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	[parentConnection->mutationStack markAsMutated];
}

- (void)removeRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [parentConnection removeRowidStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "tableName" WHERE "rowid" = ?;
	
	int const bind_idx_rowid = SQLITE_BIND_START;
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeRowidStatement': %d %s",
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
	
	parentConnection = nil;       // Do not remove !
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
	
	parentConnection = nil;       // Do not remove !
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
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	// Invoke the block to find out if the object should be included in the index.
	
	__unsafe_unretained YapDatabaseFullTextSearchHandler *handler = parentConnection->parent->handler;
	
	if (handler->blockType == YapDatabaseBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseFullTextSearchWithKeyBlock block =
		    (YapDatabaseFullTextSearchWithKeyBlock)handler->block;
		
		block(parentConnection->blockDict, collection, key);
	}
	else if (handler->blockType == YapDatabaseBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseFullTextSearchWithObjectBlock block =
		    (YapDatabaseFullTextSearchWithObjectBlock)handler->block;
		
		block(parentConnection->blockDict, collection, key, object);
	}
	else if (handler->blockType == YapDatabaseBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseFullTextSearchWithMetadataBlock block =
		    (YapDatabaseFullTextSearchWithMetadataBlock)handler->block;
		
		block(parentConnection->blockDict, collection, key, metadata);
	}
	else
	{
		__unsafe_unretained YapDatabaseFullTextSearchWithRowBlock block =
		    (YapDatabaseFullTextSearchWithRowBlock)handler->block;
		
		block(parentConnection->blockDict, collection, key, object, metadata);
	}
	
	if ([parentConnection->blockDict count] == 0)
	{
		// This was an insert operation, so we don't have to worry about removing anything.
	}
	else
	{
		// Add values to index.
		// This was an insert operation, so we know we can insert rather than update.
		
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
	
	__unsafe_unretained YapDatabaseFullTextSearchHandler *handler = parentConnection->parent->handler;
	
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
	
	__unsafe_unretained YapDatabaseFullTextSearchHandler *handler = parentConnection->parent->handler;
	
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
	
	__unsafe_unretained YapDatabaseFullTextSearchHandler *handler = parentConnection->parent->handler;
	
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
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFullTextSearchHandler *handler = parentConnection->parent->handler;
	
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
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFullTextSearchHandler *handler = parentConnection->parent->handler;
	
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
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFullTextSearchHandler *handler = parentConnection->parent->handler;
	
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
- (void)didRemoveObjectForCollectionKey:(YapCollectionKey __unused *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	[self removeRowid:rowid];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didRemoveObjectsForKeys:(NSArray __unused *)keys inCollection:(NSString __unused *)collection withRowids:(NSArray *)rowids
{
	YDBLogAutoTrace();
	
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
#pragma mark Queries
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)enumerateRowidsMatching:(NSString *)query
                     usingBlock:(void (^)(int64_t rowid, BOOL *stop))block
{
	if (block == nil) return;
	if ([query length] == 0) return;
	
	sqlite3_stmt *statement = [parentConnection queryStatement];
	if (statement == NULL) return;

	BOOL stop = NO;
	YapMutationStackItem_Bool *mutation = [parentConnection->mutationStack push]; // mutation during enum protection
	
	// SELECT "rowid" FROM "tableName" WHERE "tableName" MATCH ?;
	
	int const column_idx_rowid = SQLITE_COLUMN_START;
	int const bind_idx_query   = SQLITE_BIND_START;
	
	YapDatabaseString _query; MakeYapDatabaseString(&_query, query);
	sqlite3_bind_text(statement, bind_idx_query, _query.str, _query.length, SQLITE_STATIC);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
		
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
	FreeYapDatabaseString(&_query);
	
	if (!stop && mutation.isMutated)
	{
		@throw [databaseTransaction mutationDuringEnumerationException];
	}
}

- (void)enumerateKeysMatching:(NSString *)query
                   usingBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block
{
	[self enumerateRowidsMatching:query usingBlock:^(int64_t rowid, BOOL *stop) {
		
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		block(ck.collection, ck.key, stop);
	}];
}

- (void)enumerateKeysAndMetadataMatching:(NSString *)query
                              usingBlock:(void (^)(NSString *collection, NSString *key, id metadata, BOOL *stop))block
{
	[self enumerateRowidsMatching:query usingBlock:^(int64_t rowid, BOOL *stop) {
		
		YapCollectionKey *ck = nil;
		id metadata = nil;
		[databaseTransaction getCollectionKey:&ck metadata:&metadata forRowid:rowid];
		
		block(ck.collection, ck.key, metadata, stop);
	}];
}

- (void)enumerateKeysAndObjectsMatching:(NSString *)query
                             usingBlock:(void (^)(NSString *collection, NSString *key, id object, BOOL *stop))block
{
	[self enumerateRowidsMatching:query usingBlock:^(int64_t rowid, BOOL *stop) {
		
		YapCollectionKey *ck = nil;
		id object = nil;
		[databaseTransaction getCollectionKey:&ck object:&object forRowid:rowid];
		
		block(ck.collection, ck.key, object, stop);
	}];
}

- (void)enumerateRowsMatching:(NSString *)query
                   usingBlock:(void (^)(NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
{
	[self enumerateRowidsMatching:query usingBlock:^(int64_t rowid, BOOL *stop) {
		
		YapCollectionKey *ck = nil;
		id object = nil;
		id metadata = nil;
		[databaseTransaction getCollectionKey:&ck object:&object metadata:&metadata forRowid:rowid];
		
		block(ck.collection, ck.key, object, metadata, stop);
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark bm25  Queries
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)enumerateBm25OrderedRowidsMatching:(NSString *)query
                               withWeights:(nullable NSArray<NSNumber *> *)weights
                                usingBlock:(void (^)(int64_t rowid, BOOL *stop))block
{
    if (![parentConnection->parent.ftsVersion isEqualToString:YapDatabaseFullTextSearchFTS5Version]) {
        NSString *reason = [NSString stringWithFormat:
                            @"bm25 ordering used on non fts5 extension %@", parentConnection->parent.registeredName];
        
        NSDictionary *userInfo = @{ NSLocalizedRecoverySuggestionErrorKey:
                                    @"You may want to initialize that extension with YapDatabaseFullTextSearchFTS5Version" };
        
        @throw [NSException exceptionWithName:@"YapDatabaseFullTextSearch" reason:reason userInfo:userInfo];
        return;
    }
    
    if (block == nil) return;
    if ([query length] == 0) return;
    
    sqlite3_stmt *statement = [parentConnection bm25QueryStatementWithWeights:weights];
    if (statement == NULL) return;
    
    BOOL stop = NO;
    YapMutationStackItem_Bool *mutation = [parentConnection->mutationStack push]; // mutation during enum protection
    
    // SELECT "rowid" FROM "tableName" WHERE "tableName" MATCH ? bm25("tableName", weights[0], weights[1], ...);
    
    int const column_idx_rowid = SQLITE_COLUMN_START;
    int const bind_idx_query   = SQLITE_BIND_START;
    
    YapDatabaseString _query; MakeYapDatabaseString(&_query, query);
    sqlite3_bind_text(statement, bind_idx_query, _query.str, _query.length, SQLITE_STATIC);
    
    int status;
    while ((status = sqlite3_step(statement)) == SQLITE_ROW)
    {
        int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
        
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
    FreeYapDatabaseString(&_query);
    
    if (!stop && mutation.isMutated)
    {
        @throw [databaseTransaction mutationDuringEnumerationException];
    }
}

- (void)enumerateBm25OrderedKeysMatching:(NSString *)query
                             withWeights:(nullable NSArray<NSNumber *> *)weights
                              usingBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block {
    [self enumerateBm25OrderedRowidsMatching:query withWeights:weights usingBlock:^(int64_t rowid, BOOL *stop) {
        
        YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
        
        block(ck.collection, ck.key, stop);
    }];
}

- (void)enumerateBm25OrderedKeysAndMetadataMatching:(NSString *)query
                                        withWeights:(nullable NSArray<NSNumber *> *)weights
                                         usingBlock:(void (^)(NSString *collection, NSString *key, id metadata, BOOL *stop))block {
    [self enumerateBm25OrderedRowidsMatching:query withWeights:weights usingBlock:^(int64_t rowid, BOOL *stop) {
        
        YapCollectionKey *ck = nil;
        id metadata = nil;
        [databaseTransaction getCollectionKey:&ck metadata:&metadata forRowid:rowid];
        
        block(ck.collection, ck.key, metadata, stop);
    }];
}

- (void)enumerateBm25OrderedKeysAndObjectsMatching:(NSString *)query
                                       withWeights:(nullable NSArray<NSNumber *> *)weights
                                        usingBlock:(void (^)(NSString *collection, NSString *key, id object, BOOL *stop))block {
    [self enumerateBm25OrderedRowidsMatching:query withWeights:weights usingBlock:^(int64_t rowid, BOOL *stop) {
        
        YapCollectionKey *ck = nil;
        id object = nil;
        [databaseTransaction getCollectionKey:&ck object:&object forRowid:rowid];
        
        block(ck.collection, ck.key, object, stop);
    }];
}

- (void)enumerateBm25OrderedRowsMatching:(NSString *)query
                             withWeights:(nullable NSArray<NSNumber *> *)weights
                              usingBlock:(void (^)(NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block {
    [self enumerateBm25OrderedRowidsMatching:query withWeights:weights usingBlock:^(int64_t rowid, BOOL *stop) {
        
        YapCollectionKey *ck = nil;
        id object = nil;
        id metadata = nil;
        [databaseTransaction getCollectionKey:&ck object:&object metadata:&metadata forRowid:rowid];
        
        block(ck.collection, ck.key, object, metadata, stop);
    }];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Queries with Snippets
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)enumerateRowidsMatching:(NSString *)query
             withSnippetOptions:(YapDatabaseFullTextSearchSnippetOptions *)inOptions
                     usingBlock:
            (void (^)(NSString *snippet, int64_t rowid, BOOL *stop))block
{
	if (block == nil) return;
	if ([query length] == 0) return;
	
	sqlite3_stmt *statement = [parentConnection querySnippetStatement];
	if (statement == NULL) return;
	
	YapDatabaseFullTextSearchSnippetOptions *options;
	if (inOptions)
		options = [inOptions copy];
	else
		options = [[YapDatabaseFullTextSearchSnippetOptions alloc] init]; // default snippet options
	
	BOOL stop = NO;
	YapMutationStackItem_Bool *mutation = [parentConnection->mutationStack push]; // mutation during enum protection
	
	// SELECT "rowid", snippet("tableName", ?, ?, ?, ?, ?) FROM "tableName" WHERE "tableName" MATCH ?;
	
	int const column_idx_rowid        = SQLITE_COLUMN_START + 0;
	int const column_idx_snippet      = SQLITE_COLUMN_START + 1;
	
	int const bind_idx_startMatchText = SQLITE_BIND_START + 0;
	int const bind_idx_endMatchText   = SQLITE_BIND_START + 1;
	int const bind_idx_ellipsesText   = SQLITE_BIND_START + 2;
	int const bind_idx_columnIndex    = SQLITE_BIND_START + 3;
	int const bind_idx_numTokens      = SQLITE_BIND_START + 4;
	int const bind_idx_query          = SQLITE_BIND_START + 5;
	
	YapDatabaseString _startMatchText; MakeYapDatabaseString(&_startMatchText, options.startMatchText);
	sqlite3_bind_text(statement, bind_idx_startMatchText, _startMatchText.str, _startMatchText.length, SQLITE_STATIC);
	
	YapDatabaseString _endMatchText; MakeYapDatabaseString(&_endMatchText, options.endMatchText);
	sqlite3_bind_text(statement, bind_idx_endMatchText, _endMatchText.str, _endMatchText.length, SQLITE_STATIC);
	
	YapDatabaseString _ellipsesText; MakeYapDatabaseString(&_ellipsesText, options.ellipsesText);
	sqlite3_bind_text(statement, bind_idx_ellipsesText, _ellipsesText.str, _ellipsesText.length, SQLITE_STATIC);

	int columnIndex = -1;
	if (options.columnName)
	{
		NSUInteger index = [parentConnection->parent->columnNames indexOfObject:options.columnName];
		if (index == NSNotFound)
		{
			YDBLogWarn(@"Invalid snippet option: columnName(%@) not found", options.columnName);
		}
		else
		{
			columnIndex = (int)index;
		}
	}
	sqlite3_bind_int(statement, bind_idx_columnIndex, columnIndex);
	sqlite3_bind_int(statement, bind_idx_numTokens, options.numberOfTokens);
	
	YapDatabaseString _query; MakeYapDatabaseString(&_query, query);
	sqlite3_bind_text(statement, bind_idx_query, _query.str, _query.length, SQLITE_STATIC);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		const unsigned char *text = sqlite3_column_text(statement, column_idx_snippet);
		int textSize = sqlite3_column_bytes(statement, column_idx_snippet);
		
		NSString *snippet = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		block(snippet, rowid, &stop);
		
		if (stop || mutation.isMutated) break;
	}
	
	if ((status != SQLITE_DONE) && !stop && !mutation.isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	FreeYapDatabaseString(&_startMatchText);
	FreeYapDatabaseString(&_endMatchText);
	FreeYapDatabaseString(&_ellipsesText);
	FreeYapDatabaseString(&_query);
	
	if (!stop && mutation.isMutated)
	{
		@throw [databaseTransaction mutationDuringEnumerationException];
	}
}

- (void)enumerateKeysMatching:(NSString *)query
           withSnippetOptions:(YapDatabaseFullTextSearchSnippetOptions *)options
                   usingBlock:
            (void (^)(NSString *snippet, NSString *collection, NSString *key, BOOL *stop))block
{
	[self enumerateRowidsMatching:query
	           withSnippetOptions:options
	                   usingBlock:^(NSString *snippet, int64_t rowid, BOOL *stop)
	{
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		block(snippet, ck.collection, ck.key, stop);
	}];
}

- (void)enumerateKeysAndMetadataMatching:(NSString *)query
                      withSnippetOptions:(YapDatabaseFullTextSearchSnippetOptions *)options
                              usingBlock:
            (void (^)(NSString *snippet, NSString *collection, NSString *key, id metadata, BOOL *stop))block
{
	[self enumerateRowidsMatching:query
	           withSnippetOptions:options
	                   usingBlock:^(NSString *snippet, int64_t rowid, BOOL *stop)
	{
		YapCollectionKey *ck = nil;
		id metadata = nil;
		[databaseTransaction getCollectionKey:&ck metadata:&metadata forRowid:rowid];
		
		block(snippet, ck.collection, ck.key, metadata, stop);
	}];
}

- (void)enumerateKeysAndObjectsMatching:(NSString *)query
                     withSnippetOptions:(YapDatabaseFullTextSearchSnippetOptions *)options
                             usingBlock:
            (void (^)(NSString *snippet, NSString *collection, NSString *key, id object, BOOL *stop))block
{
	[self enumerateRowidsMatching:query
	           withSnippetOptions:options
	                   usingBlock:^(NSString *snippet, int64_t rowid, BOOL *stop)
	{
		YapCollectionKey *ck = nil;
		id object = nil;
		[databaseTransaction getCollectionKey:&ck object:&object forRowid:rowid];
		
		block(snippet, ck.collection, ck.key, object, stop);
	}];
}

- (void)enumerateRowsMatching:(NSString *)query
           withSnippetOptions:(YapDatabaseFullTextSearchSnippetOptions *)options
                   usingBlock:
            (void (^)(NSString *snippet, NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
{
	[self enumerateRowidsMatching:query
	           withSnippetOptions:options
	                   usingBlock:^(NSString *snippet, int64_t rowid, BOOL *stop)
	{
		YapCollectionKey *ck = nil;
		id object = nil;
		id metadata = nil;
		[databaseTransaction getCollectionKey:&ck object:&object metadata:&metadata forRowid:rowid];
		
		block(snippet, ck.collection, ck.key, object, metadata, stop);
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Individual Query
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)rowid:(int64_t)rowid matches:(NSString *)query
{
	if ([query length] == 0) return NO;
	
	sqlite3_stmt *statement = [parentConnection rowidQueryStatement];
	if (statement == NULL) return NO;
	
	// SELECT "rowid" FROM "tableName" WHERE "rowid" = ? AND "tableName" MATCH ?;
	
	int const bind_idx_rowid = SQLITE_BIND_START + 0;
	int const bind_idx_query = SQLITE_BIND_START + 1;
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	YapDatabaseString _query; MakeYapDatabaseString(&_query, query);
	sqlite3_bind_text(statement, bind_idx_query, _query.str, _query.length, SQLITE_STATIC);
	
	BOOL result = NO;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = YES;
	}
	else if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_query);
	
	return result;
}

- (NSString *)rowid:(int64_t)rowid matches:(NSString *)query
                        withSnippetOptions:(YapDatabaseFullTextSearchSnippetOptions *)inOptions
{
	if ([query length] == 0) return nil;
	
	sqlite3_stmt *statement = [parentConnection rowidQuerySnippetStatement];
	if (statement == NULL) return nil;
	
	YapDatabaseFullTextSearchSnippetOptions *options;
	if (inOptions)
		options = [inOptions copy];
	else
		options = [[YapDatabaseFullTextSearchSnippetOptions alloc] init]; // default snippet options
	
	// SELECT "rowid", snippet("tableName", ?, ?, ?, ?, ?) FROM "tableName" WHERE "rowid" = ? AND "tableName" MATCH ?;
	
//	int const column_idx_rowid        = SQLITE_COLUMN_START + 0;
	int const column_idx_snippet      = SQLITE_COLUMN_START + 1;
	
	int const bind_idx_startMatchText = SQLITE_BIND_START + 0;
	int const bind_idx_endMatchText   = SQLITE_BIND_START + 1;
	int const bind_idx_ellipsesText   = SQLITE_BIND_START + 2;
	int const bind_idx_columnIndex    = SQLITE_BIND_START + 3;
	int const bind_idx_numTokens      = SQLITE_BIND_START + 4;
	int const bind_idx_rowid          = SQLITE_BIND_START + 5;
	int const bind_idx_query          = SQLITE_BIND_START + 6;
	
	YapDatabaseString _startMatchText; MakeYapDatabaseString(&_startMatchText, options.startMatchText);
	sqlite3_bind_text(statement, bind_idx_startMatchText, _startMatchText.str, _startMatchText.length, SQLITE_STATIC);
	
	YapDatabaseString _endMatchText; MakeYapDatabaseString(&_endMatchText, options.endMatchText);
	sqlite3_bind_text(statement, bind_idx_endMatchText, _endMatchText.str, _endMatchText.length, SQLITE_STATIC);
	
	YapDatabaseString _ellipsesText; MakeYapDatabaseString(&_ellipsesText, options.ellipsesText);
	sqlite3_bind_text(statement, bind_idx_ellipsesText, _ellipsesText.str, _ellipsesText.length, SQLITE_STATIC);

	int columnIndex = -1;
	if (options.columnName)
	{
		NSUInteger index = [parentConnection->parent->columnNames indexOfObject:options.columnName];
		if (index == NSNotFound)
		{
			YDBLogWarn(@"Invalid snippet option: columnName(%@) not found", options.columnName);
		}
		else
		{
			columnIndex = (int)index;
		}
	}
	sqlite3_bind_int(statement, bind_idx_columnIndex, columnIndex);
	sqlite3_bind_int(statement, bind_idx_numTokens, options.numberOfTokens);
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	YapDatabaseString _query; MakeYapDatabaseString(&_query, query);
	sqlite3_bind_text(statement, bind_idx_query, _query.str, _query.length, SQLITE_STATIC);
	
	NSString *snippet = nil;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
	//	int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
			
		const unsigned char *text = sqlite3_column_text(statement, column_idx_snippet);
		int textSize = sqlite3_column_bytes(statement, column_idx_snippet);
		
		snippet = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
	}
	else if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_startMatchText);
	FreeYapDatabaseString(&_endMatchText);
	FreeYapDatabaseString(&_ellipsesText);
	FreeYapDatabaseString(&_query);
	
	return snippet;
}

@end
