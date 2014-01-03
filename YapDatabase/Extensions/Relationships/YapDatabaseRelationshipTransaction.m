#import "YapDatabaseRelationshipTransaction.h"
#import "YapDatabaseRelationshipPrivate.h"
#import "YapDatabaseRelationshipEdgePrivate.h"
#import "YapDatabasePrivate.h"
#import "YapCollectionKey.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"
#import "NSDictionary+YapDatabase.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_VERBOSE;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif

/**
 * Declare that this class implements YapDatabaseExtensionTransaction_Hooks protocol.
 * This is done privately, as the protocol is internal.
**/
@interface YapDatabaseRelationshipTransaction () <YapDatabaseExtensionTransaction_Hooks>
@end


@implementation YapDatabaseRelationshipTransaction
{
	BOOL isFlushing;
}

- (id)initWithRelationshipConnection:(YapDatabaseRelationshipConnection *)inRelationshipConnection
                 databaseTransaction:(YapDatabaseReadTransaction *)inDatabaseTransaction
{
	if ((self = [super init]))
	{
		relationshipConnection = inRelationshipConnection;
		databaseTransaction = inDatabaseTransaction;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extension Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is called to create any necessary tables,
 * as well as populate the view by enumerating over the existing rows in the database.
**/
- (BOOL)createIfNeeded
{
	BOOL needsCreateTables = NO;
	
	// Check classVersion (the internal version number of YapDatabaseView implementation)
	
	int oldClassVersion = [self intValueForExtensionKey:@"classVersion"];
	int classVersion = YAP_DATABASE_RELATIONSHIP_CLASS_VERSION;
	
	if (oldClassVersion != classVersion)
		needsCreateTables = YES;
	
	// Create or re-populate if needed
	
	if (needsCreateTables)
	{
		// First time registration
		
		if (![self createTables]) return NO;
		if (![self populateTables]) return NO;
		
		[self setIntValue:classVersion forExtensionKey:@"classVersion"];
		
		int userSuppliedConfigVersion = relationshipConnection->relationship->version;
		[self setIntValue:userSuppliedConfigVersion forExtensionKey:@"version"];
	}
	else
	{
		// Check user-supplied config version.
		// We may need to re-populate the database if the groupingBlock or sortingBlock changed.
		
		int oldVersion = [self intValueForExtensionKey:@"version"];
		int newVersion = relationshipConnection->relationship->version;
		
		if (oldVersion != newVersion)
		{
			if (![self populateTables]) return NO;
			
			[self setIntValue:newVersion forExtensionKey:@"version"];
		}
	}
	
	return YES;
}

/**
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

- (BOOL)createTables
{
	sqlite3 *db = databaseTransaction->connection->db;
	
	NSString *tableName = [self tableName];
	
	YDBLogVerbose(@"Creating relationship table for registeredName(%@): %@", [self registeredName], tableName);
	
	NSString *createTable = [NSString stringWithFormat:
	  @"CREATE TABLE IF NOT EXISTS \"%@\""
	  @" (\"rowid\" INTEGER PRIMARY KEY,"
	  @"  \"name\" CHAR NOT NULL,"
	  @"  \"src\" INTEGER,"
	  @"  \"dst\" INTEGER,"
	  @"  \"rules\" INTEGER"
	  @" );", tableName];
	
	NSString *createNameIndex = [NSString stringWithFormat:
	  @"CREATE INDEX IF NOT EXISTS \"name\" ON \"%@\" (\"name\");", tableName];
	
	NSString *createSrcIndex = [NSString stringWithFormat:
	  @"CREATE INDEX IF NOT EXISTS \"src\" ON \"%@\" (\"src\");", tableName];
	
	NSString *createDstIndex = [NSString stringWithFormat:
	  @"CREATE INDEX IF NOT EXISTS \"dst\" ON \"%@\" (\"dst\");", tableName];
	
	int status;
	
	status = sqlite3_exec(db, [createTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating table (%@): %d %s",
		            THIS_METHOD, createTable, status, sqlite3_errmsg(db));
		return NO;
	}
	
	status = sqlite3_exec(db, [createNameIndex UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating name index (%@): %d %s",
		            THIS_METHOD, createNameIndex, status, sqlite3_errmsg(db));
		return NO;
	}
	
	status = sqlite3_exec(db, [createSrcIndex UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating src index (%@): %d %s",
		            THIS_METHOD, createSrcIndex, status, sqlite3_errmsg(db));
		return NO;
	}
	
	status = sqlite3_exec(db, [createDstIndex UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating dst index (%@): %d %s",
		            THIS_METHOD, createDstIndex, status, sqlite3_errmsg(db));
		return NO;
	}
		
	return YES;
}

- (BOOL)populateTables
{
	// Remove everything from the database
	
	[self removeAllEdges];
	
	// Enumerate the existing rows in the database and populate the view
	
	[databaseTransaction _enumerateKeysAndObjectsInAllCollectionsUsingBlock:
	    ^(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop){
		
		NSArray *givenEdges = nil;
		
		if ([object conformsToProtocol:@protocol(YapDatabaseRelationshipNode)])
		{
			givenEdges = [object yapDatabaseRelationshipEdges];
		}
		
		if ([givenEdges count] > 0)
		{
			NSMutableArray *edges = [NSMutableArray arrayWithCapacity:[givenEdges count]];
			
			for (YapDatabaseRelationshipEdge *givenEdge in givenEdges)
			{
				[edges addObject:[givenEdge copyWithSourceKey:key collection:collection rowid:rowid]];
			}
			
			[relationshipConnection->changes setObject:edges forKey:@(rowid)];
		}
	}];
	
	[self flush];
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
	return relationshipConnection;
}

- (NSString *)registeredName
{
	return [relationshipConnection->relationship registeredName];
}

- (NSString *)tableName
{
	return [relationshipConnection->relationship tableName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Extracts edges from the in-memory changes that match the given options.
 * These edges need to replace whatever is on disk.
**/
- (NSMutableArray *)findChangesMatchingName:(NSString *)name
                             destinationKey:(NSString *)dstKey
                                 collection:(NSString *)dstCollection
{
	if (!databaseTransaction->isReadWriteTransaction)
		return nil;
	
	if (dstCollection == nil)
		dstCollection = @"";
	
	__block NSMutableArray *changes = nil;
	
	[relationshipConnection->changes enumerateKeysAndObjectsUsingBlock:^(id dictKey, id dictObj, BOOL *stop) {
		
	//	__unsafe_unretained NSString *srcRowidNumber = (NSNumber *)dictKey;
		__unsafe_unretained NSArray *changedEdgesForSrc = (NSArray *)dictObj;
		
		for (YapDatabaseRelationshipEdge *edge in changedEdgesForSrc)
		{
			if (name && ![name isEqualToString:edge->name])
			{
				continue;
			}
			
			if (dstKey)
			{
				if (![dstKey isEqualToString:edge->destinationKey] ||
				    ![dstCollection isEqualToString:edge->destinationCollection])
				{
					continue;
				}
			}
			
			if (changes == nil)
				changes = [NSMutableArray array];
			
			[changes addObject:edge];
		}
	}];
	
	// Now lookup the destinationRowid for each edge (if missing).
	// We're going to have to do this anyways at some point.
	// If not during the enumeration shortly,
	// then later during the preCommit stage.
	
	for (YapDatabaseRelationshipEdge *edge in changes)
	{
		// Note: Zero is a valid rowid.
		// So we use flags to handle this edge case.
		
		if (edge->destinationRowid == 0 && edge->flags != 2)
		{
			int64_t dstRowid = 0;
			
			BOOL found = [databaseTransaction getRowid:&dstRowid
												forKey:edge->destinationKey
										  inCollection:edge->destinationCollection];
			
			if (found)
			{
				edge->destinationRowid = dstRowid;
				edge->flags = 2;
			}
			else
			{
				edge->flags = 1;
			}
		}
	}
	
	return changes;
}

/**
 * Simple enumeration of existing data in database, via a SELECT query.
 * Does not take into account anything in memory (relationshipConnection->changes dictionary).
**/
- (void)enumerateExistingEdgesWithSrc:(int64_t)srcRowid
                           usingBlock:(void (^)(int64_t edgeRowid, NSString *name, int64_t dstRowid, int rules))block
{
	sqlite3_stmt *statement = [relationshipConnection enumerateForSrcStatement];
	if (statement == NULL) return;
	
	// SELECT "rowid", "name", "dst", "rules" FROM "tableName" WHERE "src" = ?;
	
	sqlite3_bind_int64(statement, 1, srcRowid);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t edgeRowid = sqlite3_column_int64(statement, 0);
		
		const unsigned char *text = sqlite3_column_text(statement, 1);
		int textSize = sqlite3_column_bytes(statement, 1);
		
		NSString *name = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		int64_t dstRowid = sqlite3_column_int64(statement, 2);
		int rules = sqlite3_column_int(statement, 3);
		
		block(edgeRowid, name, dstRowid, rules);
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ (%@): Error executing statement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
}

/**
 * Simple enumeration of existing data in database, via a SELECT query.
 * Does not take into account anything in memory (relationshipConnection->changes dictionary).
**/
- (void)enumerateExistingEdgesWithDst:(int64_t)dstRowid
                           usingBlock:(void (^)(int64_t edgeRowid, NSString *name, int64_t srcRowid, int rules))block
{
	sqlite3_stmt *statement = [relationshipConnection enumerateForDstStatement];
	if (statement == NULL) return;
	
	// SELECT "rowid", "name", "src", "rules" FROM "tableName" WHERE "dst" = ?;
	
	sqlite3_bind_int64(statement, 1, dstRowid);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t edgeRowid = sqlite3_column_int64(statement, 0);
		
		const unsigned char *text = sqlite3_column_text(statement, 1);
		int textSize = sqlite3_column_bytes(statement, 1);
		
		NSString *name = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		int64_t srcRowid = sqlite3_column_int64(statement, 2);
		int rules = sqlite3_column_int(statement, 3);
		
		block(edgeRowid, name, srcRowid, rules);
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ (%@): Error executing statement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
}

/**
 * Searches the deletedInfo ivar to retrieve the associated rowid for a node that doesn't appear in the database.
 * If the node was deleted, we'll find it.
 * Otherwise the edge was bad (node never existed).
**/
- (NSNumber *)rowidNumberForDeletedKey:(NSString *)key inCollection:(NSString *)collection
{
	__block NSNumber *result = nil;
	
	[relationshipConnection->deletedInfo enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained NSNumber *rowidNumber = (NSNumber *)key;
		__unsafe_unretained YapCollectionKey *collectionKey = (YapCollectionKey *)obj;
		
		if ([collectionKey.key isEqualToString:key] && [collectionKey.collection isEqualToString:collection])
		{
			result = rowidNumber;
			*stop = YES;
		}
	}];
	
	return result;
}

/**
 * Queries the database for the number of edges matching the given source and name.
 * This method only queries the database, and doesn't inspect anything in memory.
**/
- (int64_t)edgeCountWithSource:(int64_t)srcRowid name:(NSString *)name excludingDestination:(int64_t)dstRowid
{
	sqlite3_stmt *statement = [relationshipConnection countForSrcNameExcludingDstStatement];
	if (statement == NULL) return 0;
	
	int64_t count = 0;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "src" = ? AND "dst" != ? AND "name" = ?;
	
	sqlite3_bind_int64(statement, 1, srcRowid);
	sqlite3_bind_int64(statement, 2, dstRowid);
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, name);
	sqlite3_bind_text(statement, 3, _name.str, _name.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ (%@): Error in statement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_name);
	
	return count;
}

/**
 * Queries the database for the number of edges matching the given destination and name.
 * This method only queries the database, and doesn't inspect anything in memory.
**/
- (int64_t)edgeCountWithDestination:(int64_t)dstRowid name:(NSString *)name excludingSource:(int64_t)srcRowid
{
	sqlite3_stmt *statement = [relationshipConnection countForDstNameExcludingSrcStatement];
	if (statement == NULL) return 0;
	
	int64_t count = 0;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "dst" = ? AND "src" != ? AND "name" = ?;
	
	sqlite3_bind_int64(statement, 1, dstRowid);
	sqlite3_bind_int64(statement, 2, srcRowid);
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, name);
	sqlite3_bind_text(statement, 3, _name.str, _name.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ (%@): Error in statement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_name);
	
	return count;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method enumerates over the given set of edges, and sets the following properties to their appropriate value:
 * 
 * edge->edgeAction
 * edge->nodeAction
 * edge->notInDatabase
 * edge->badDestination
**/
- (void)processInsertedEdges:(NSMutableArray *)edges sourceDeleted:(BOOL)sourceDeleted
{
	for (YapDatabaseRelationshipEdge *edge in edges)
	{
		if (sourceDeleted)
		{
			edge->edgeAction = YDB_EdgeActionDelete;
			edge->notInDatabase = YES;
			edge->nodeAction = YDB_NodeActionSourceDeleted;
		}
			
		if (edge->destinationRowid == 0)
		{
			int64_t dstRowid = 0;
			
			BOOL found = [databaseTransaction getRowid:&dstRowid
			                                    forKey:edge->destinationKey
			                              inCollection:edge->destinationCollection];
			
			if (found)
			{
				edge->destinationRowid = dstRowid;
				
				if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
				{
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->notInDatabase = YES;
					edge->nodeAction |= YDB_NodeActionDestinationDeleted;
				}
				else if (!sourceDeleted)
				{
					edge->edgeAction = YDB_EdgeActionInsert;
				}
			}
			else
			{
				NSNumber *dstRowidNumber = [self rowidNumberForDeletedKey:edge->destinationKey
				                                             inCollection:edge->destinationCollection];
				
				if (dstRowidNumber)
				{
					edge->destinationRowid = [dstRowidNumber longLongValue];
					
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->notInDatabase = YES;
					edge->nodeAction |= YDB_NodeActionDestinationDeleted;
				}
				else
				{
					// Bad edge (destination node never existed).
					// Treat same as if destination node was deleted.
					
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->notInDatabase = YES;
					edge->badDestination = YES;
					edge->nodeAction |= YDB_NodeActionDestinationDeleted;
				}
			}
		}
		else if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
		{
			edge->edgeAction = YDB_EdgeActionDelete;
			edge->notInDatabase = YES;
			edge->nodeAction |= YDB_NodeActionDestinationDeleted;
		}
		else if (!sourceDeleted)
		{
			edge->edgeAction = YDB_EdgeActionInsert;
		}
	}
}

/**
 * This method merges the given set of edges with the corresponding edges that already exist on disk.
 * It will update the newEdges list, adding any edges that have been manually removed from the list.
 *
 * Sets the following properties to their appropriate value:
 * 
 * edge->edgeRowid
 * edge->edgeAction
 * edge->nodeAction
 * edge->notInDatabase
 * edge->badDestination
**/
- (void)processUpdatedEdges:(NSMutableArray *)newEdges
                  forSource:(NSNumber *)srcRowidNumber
              sourceDeleted:(BOOL)sourceDeleted
{
	int64_t srcRowid = [srcRowidNumber longLongValue];
	
	// Step 1 :
	//
	// Pre-process the updated edges.
	// This involves looking up the destinationRowid for each edge.
	
	__block NSUInteger offset = 0;
	NSUInteger newEdgesCount = [newEdges count];
	
	for (NSUInteger i = 0; i < newEdgesCount; i++)
	{
		YapDatabaseRelationshipEdge *newEdge = [newEdges objectAtIndex:i];
		
		// Note: Zero is a valid rowid.
		// But if newEdge->destinationRowid is zero, then its far far more likely
		// that we haven't looked up the destinationRowid yet.
		
		if (newEdge->destinationRowid == 0)
		{
			int64_t dstRowid = 0;
			BOOL found = [databaseTransaction getRowid:&dstRowid
			                                    forKey:newEdge->destinationKey
			                              inCollection:newEdge->destinationCollection];
			
			if (found)
			{
				newEdge->destinationRowid = dstRowid;
			}
			else
			{
				NSNumber *dstRowidNumber = [self rowidNumberForDeletedKey:newEdge->destinationKey
				                                             inCollection:newEdge->destinationCollection];
				
				if (dstRowidNumber)
				{
					newEdge->destinationRowid = [dstRowidNumber longLongValue];
					
					newEdge->edgeAction = YDB_EdgeActionDelete;
					newEdge->nodeAction = YDB_NodeActionDestinationDeleted;
				}
				else
				{
					// Bad edge (destination node never existed).
					// Treat same as if destination node was deleted.
					
					newEdge->edgeAction = YDB_EdgeActionDelete;
					newEdge->notInDatabase = YES;
					newEdge->badDestination = YES;
					newEdge->nodeAction = YDB_NodeActionDestinationDeleted;
					
					[newEdges exchangeObjectAtIndex:i withObjectAtIndex:offset];
					offset++;
				}
			}
		}
	}
	
	// Step 2 :
	//
	// Enumerate the existing edges, and check to see if they match a new edge.
	
	[self enumerateExistingEdgesWithSrc:srcRowid
							 usingBlock:^(int64_t edgeRowid, NSString *name, int64_t dstRowid, int nodeDeleteRules)
	{
		YapDatabaseRelationshipEdge *matchingNewEdge = nil;
		
		NSUInteger i = offset;
		while (i < newEdgesCount)
		{
			YapDatabaseRelationshipEdge *newEdge = [newEdges objectAtIndex:i];
			
			if (newEdge->destinationRowid == dstRowid && [newEdge->name isEqualToString:name])
			{
				matchingNewEdge = newEdge;
				break;
			}
			else
			{
				i++;
			}
		}
		
		if (matchingNewEdge)
		{
			// This new edges matches an existing one already in the database.
			
			matchingNewEdge->edgeRowid = edgeRowid;
			
			// Check to see if it changed at all.
			
			if (matchingNewEdge->nodeDeleteRules != nodeDeleteRules)
			{
				// The nodeDeleteRules changed. Mark for update.
				
				matchingNewEdge->edgeAction = YDB_EdgeActionUpdate;
			}
			else
			{
				// Nothing changed
				
				matchingNewEdge->edgeAction = YDB_EdgeActionNone;
			}
			
			// Was source and/or destination deleted?
			
			if (sourceDeleted)
			{
				matchingNewEdge->edgeAction = YDB_EdgeActionDelete;
				matchingNewEdge->nodeAction = YDB_NodeActionSourceDeleted;
			}
			
			if ([relationshipConnection->deletedInfo ydb_containsKey:@(matchingNewEdge->destinationRowid)])
			{
				matchingNewEdge->edgeAction = YDB_EdgeActionDelete;
				matchingNewEdge->nodeAction |= YDB_NodeActionDestinationDeleted;
			}
			
			[newEdges exchangeObjectAtIndex:i withObjectAtIndex:offset];
			offset++;
		}
		else
		{
			// The existing edge has no match in the new edges list.
			// Thus an existing edge was removed.
			// It needs to be deleted from the database.
			
			YapDatabaseRelationshipEdge *edge =
			  [[YapDatabaseRelationshipEdge alloc] initWithRowid:edgeRowid
			                                                name:name
			                                                 src:srcRowid
			                                                 dst:dstRowid
			                                               rules:nodeDeleteRules];
			
			edge->edgeAction = YDB_EdgeActionDelete;
			edge->nodeAction = YDB_NodeActionSourceDeleted;
			
			if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
			{
				edge->nodeAction |= YDB_NodeActionDestinationDeleted;
			}
			
			[newEdges addObject:edge];
			// Note: Do NOT increment newEdgesCount.
		}
	}];
	
	// Step 3 :
	//
	// Process any newEdges that didn't have a matching existing edge in the database.
	
	for (NSUInteger i = offset; i < newEdgesCount; i++)
	{
		YapDatabaseRelationshipEdge *newEdge = [newEdges objectAtIndex:i];
		
		if (sourceDeleted)
		{
			newEdge->edgeAction = YDB_EdgeActionDelete;
			newEdge->notInDatabase = YES;
		}
		else
		{
			newEdge->edgeAction = YDB_EdgeActionInsert;
		}
	}
}

- (void)insertEdge:(YapDatabaseRelationshipEdge *)edge
{
	sqlite3_stmt *statement = [relationshipConnection insertEdgeStatement];
	if (statement == NULL) return;
	
	// INSERT INTO "tableName" ("name", "src", "dst", "rules") VALUES (?, ?, ?, ?);
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, edge->name);
	sqlite3_bind_text(statement, 1, _name.str, _name.length, SQLITE_STATIC);
	
	sqlite3_bind_int64(statement, 2, edge->sourceRowid);
	sqlite3_bind_int64(statement, 3, edge->destinationRowid);
	sqlite3_bind_int(statement, 4, edge->nodeDeleteRules);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		edge->edgeRowid = sqlite3_last_insert_rowid(databaseTransaction->connection->db);
	}
	else
	{
		YDBLogError(@"Error executing 'insertEdgeStatement': %d %s",
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_name);
}

- (void)updateEdge:(YapDatabaseRelationshipEdge *)edge
{
	sqlite3_stmt *statement = [relationshipConnection updateEdgeStatement];
	if (statement == NULL) return;
	
	// UPDATE "tableName" SET "rules" = ? WHERE "rowid" = ?;
	
	sqlite3_bind_int(statement, 1, edge->nodeDeleteRules);
	sqlite3_bind_int64(statement, 2, edge->edgeRowid);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'updateEdgeStatement': %d %s",
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
}

- (void)deleteEdge:(YapDatabaseRelationshipEdge *)edge
{
	sqlite3_stmt *statement = [relationshipConnection deleteEdgeStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "tableName" WHERE "rowid" = ?;
	
	sqlite3_bind_int64(statement, 1, edge->edgeRowid);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'deleteEdgeStatement': %d %s",
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
}

- (void)deleteEdgesWithSourceOrDestination:(int64_t)rowid
{
	sqlite3_stmt *statement = [relationshipConnection deleteEdgesWithNodeStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "tableName" WHERE "src" = ? OR "dst" = ?;
	
	sqlite3_bind_int64(statement, 1, rowid);
	sqlite3_bind_int64(statement, 2, rowid);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'deleteEdgesWithNodeStatement': %d %s",
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
}

- (void)removeAllEdges
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [relationshipConnection removeAllStatement];
	if (statement == NULL)
		return;
	
	int status;

	// DELETE FROM "tableName";
	
	YDBLogVerbose(@"DELETE FROM '%@';", [self tableName]);
	
	status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ (%@): Error in statement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
		
	sqlite3_reset(statement);
	
	[relationshipConnection->changes removeAllObjects];
	[relationshipConnection->inserted removeAllObjects];
	[relationshipConnection->deletedOrder removeAllObjects];
	[relationshipConnection->deletedInfo removeAllObjects];
}

- (void)flush
{
	YDBLogAutoTrace();
	
	isFlushing = YES;
	
	// STEP 1:
	//
	// Process all edges that have been set during the transaction.
	// This includes:
	// - merging new edge lists with existing edge lists
	// - writing new edges to the database
	// - writing modified edges to the database (changed nodeDeleteRules)
	// - deleting edges that were manually removed from the list
	
	[relationshipConnection->changes enumerateKeysAndObjectsUsingBlock:^(id dictKey, id dictObj, BOOL *stop) {
		
		__unsafe_unretained NSNumber *srcRowidNumber = (NSNumber *)dictKey;
		__unsafe_unretained NSMutableArray *edges = (NSMutableArray *)dictObj;
		
		BOOL sourceDeleted = [relationshipConnection->deletedInfo ydb_containsKey:srcRowidNumber];
		
		if ([relationshipConnection->inserted containsObject:srcRowidNumber])
		{
			// The src node is new, so all the edges are new.
			// Thus no need to merge the edges with a previous set of edges.
			//
			// So just enumerate over the edges, and attempt to fill in all the destinationRowid values.
			// If either of the edge's nodes were deleted, mark accordingly.
			
			[self processInsertedEdges:edges sourceDeleted:sourceDeleted];
		}
		else
		{
			// The src node was updated, so the edges may have changed.
			//
			// We need to merge the new list with the existing list of edges in the database.
			
			[self processUpdatedEdges:edges forSource:srcRowidNumber sourceDeleted:sourceDeleted];
		}
		
		// The edges list has now been processed,
		// and all the various flags for each edge have been set.
		
		NSUInteger i = 0;
		while (i < [edges count])
		{
			YapDatabaseRelationshipEdge *edge = [edges objectAtIndex:i];
			BOOL edgeProcessed = YES;
			
			if (edge->edgeAction == YDB_EdgeActionNone)
			{
				// No edge processing required.
				// Edge previously existed and didn't change.
			}
			else if (edge->edgeAction == YDB_EdgeActionInsert)
			{
				// New edge added.
				// Insert into database.
				
				[self insertEdge:edge];
			}
			else if (edge->edgeAction == YDB_EdgeActionUpdate)
			{
				// Edge modified (nodeDeleteRules changed)
				// Update row in database.
				
				[self updateEdge:edge];
			}
			else if (edge->edgeAction == YDB_EdgeActionDelete)
			{
				// The edge is marked for deletion for one of the following reasons
				//
				// - Both source and destination deleted
				// - Only source was deleted
				// - Only destination was deleted
				// - Edge manually deleted via source object (same as source deleted)
				
				if (edge->nodeAction == YDB_NodeActionSourceDeleted)
				{
					// Only source was deleted
					
					if (edge->nodeDeleteRules & YDB_DeleteDestinationIfSourceDeleted)
					{
						// Delete the destination node
						
						YDBLogVerbose(@"Deleting destination node: key(%@) collection(%@)",
						              edge->destinationKey, edge->destinationCollection);
						
						__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
						  (YapDatabaseReadWriteTransaction *)databaseTransaction;
						
						[databaseRwTransaction removeObjectForKey:edge->destinationKey
						                             inCollection:edge->destinationCollection
						                                withRowid:edge->destinationRowid];
					}
					else if (edge->nodeDeleteRules & YDB_DeleteDestinationIfAllSourcesDeleted)
					{
						// We need to count the number of remaining edges.
						// That is, how many edges with the same name and same source.
						//
						// The problem is that we are still processing changed edges.
						// So there may be edges that we'll add shortly that increment this count.
						// Or possibly edges that were manually deleted which would decrement this count.
						//
						// So we're going to come back to this after we've finished adding all edges.
						
						edgeProcessed = NO;
					}
					else if (edge->nodeDeleteRules & YDB_NotifyIfSourceDeleted)
					{
						// Notify the destination node
						
						id destinationNode = [databaseTransaction objectForKey:edge->destinationKey
						                                          inCollection:edge->destinationCollection
						                                             withRowid:edge->destinationRowid];
						
						SEL selector = @selector(yapDatabaseRelationshipEdgeDeleted:withReason:);
						if ([destinationNode respondsToSelector:selector])
						{
							id updatedDestinationNode =
							  [destinationNode yapDatabaseRelationshipEdgeDeleted:edge
							                                           withReason:YDB_NotifyIfSourceDeleted];
							
							if (updatedDestinationNode)
							{
								__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
								  (YapDatabaseReadWriteTransaction *)databaseTransaction;
								
								[databaseRwTransaction replaceObject:updatedDestinationNode
								                              forKey:edge->destinationKey
								                        inCollection:edge->destinationCollection
								                           withRowid:edge->destinationRowid];
							}
						}
					}
				}
				else if (edge->nodeAction == YDB_NodeActionDestinationDeleted)
				{
					// Only destination was deleted
					
					if (edge->nodeDeleteRules & YDB_DeleteSourceIfDestinationDeleted)
					{
						// Delete the source node
						
						YDBLogVerbose(@"Deleting source node: key(%@) collection(%@)",
						              edge->sourceKey, edge->sourceCollection);
						
						__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
						  (YapDatabaseReadWriteTransaction *)databaseTransaction;
						
						[databaseRwTransaction removeObjectForKey:edge->sourceKey
						                             inCollection:edge->sourceCollection
						                                withRowid:edge->sourceRowid];
					}
					else if (edge->nodeDeleteRules & YDB_DeleteSourceIfAllDestinationsDeleted)
					{
						// We need to count the number of remaining edges.
						// That is, how many edges with the same name and same source.
						//
						// The problem is that we are still processing changed edges.
						// So there may be edges that we'll add shortly that increment this count.
						// Or possibly edges that were manually deleted which would decrement this count.
						//
						// So we're going to come back to this after we've finished adding all edges.
						
						edgeProcessed = NO;
					}
					else if (edge->nodeDeleteRules & YDB_NotifyIfDestinationDeleted)
					{
						// Notify the source node
						
						id sourceNode = [databaseTransaction objectForKey:edge->sourceKey
						                                     inCollection:edge->sourceCollection
						                                        withRowid:edge->sourceRowid];
						
						SEL selector = @selector(yapDatabaseRelationshipEdgeDeleted:withReason:);
						if ([sourceNode respondsToSelector:selector])
						{
							id updatedSourceNode =
							  [sourceNode yapDatabaseRelationshipEdgeDeleted:edge
							                                      withReason:YDB_NotifyIfDestinationDeleted];
							
							if (updatedSourceNode)
							{
								__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
								  (YapDatabaseReadWriteTransaction *)databaseTransaction;
								
								[databaseRwTransaction replaceObject:updatedSourceNode
								                              forKey:edge->sourceKey
								                        inCollection:edge->sourceCollection
								                           withRowid:edge->sourceRowid];
							}
						}
					}
				}
				
				if (edge->notInDatabase)
				{
					// The edge was added and deleted within the same transaction.
					// This might happen if we're testing the extension,
					// or if a bad edge was created (destination node doesn't exist).
					//
					// Whatever the case, we don't need to attempt to delete the edge from the database.
					// In fact, we must not run the code because the edge->edgeRowid is invalid.
				}
				else
				{
					// Remove the edge from disk.
					
					[self deleteEdge:edge];
				}
				
			} // end else if (edge->edgeAction == YDB_EdgeActionDelete)
			
			
			// If we processed the edge, then we can remove it from the array.
			// Otherwise, we leave it in the array so we can come back and process it later.
			
			if (edgeProcessed)
				[edges removeObjectAtIndex:i];
			else
				i++;
		}
	}];
	
	// STEP 2:
	//
	// Revisit the unprocessed edges from step 1.
	// That is, those edges that were deleted, but had nodeDeleteRules of either
	// - YDB_DeleteDestinationIfAllSourcesDeleted
	// - YDB_DeleteSourceIfAllDestinationsDeleted
	//
	// We were unable to fetch the remaining edge count earlier.
	// But we can do so now.
	
	[relationshipConnection->changes enumerateKeysAndObjectsUsingBlock:^(id dictKey, id dictObj, BOOL *stop) {
		
		__unsafe_unretained NSMutableArray *edges = (NSMutableArray *)dictObj;
		
		for (YapDatabaseRelationshipEdge *edge in edges)
		{
			if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
			{
				// Both source and destination deleted
			}
			else
			{
				if (edge->nodeAction == YDB_NodeActionSourceDeleted &&
				    edge->nodeDeleteRules == YDB_DeleteDestinationIfAllSourcesDeleted)
				{
					// Delete the destination node IF there are no other edges pointing to it with the same name
					
					int64_t count = [self edgeCountWithDestination:edge->destinationRowid
					                                          name:edge->name
					                               excludingSource:edge->sourceRowid];
					if (count == 0)
					{
						YDBLogVerbose(@"Deleting destination node: key(%@) collection(%@)",
						              edge->destinationKey, edge->destinationCollection);
						
						__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
						  (YapDatabaseReadWriteTransaction *)databaseTransaction;
						
						[databaseRwTransaction removeObjectForKey:edge->destinationKey
						                             inCollection:edge->destinationCollection
						                                withRowid:edge->destinationRowid];
					}
				}
				else if (edge->nodeAction == YDB_NodeActionDestinationDeleted &&
				         edge->nodeDeleteRules & YDB_DeleteSourceIfAllDestinationsDeleted)
				{
					// Delete the source node IF there are no other edges pointing from it with the same name
					
					int64_t count = [self edgeCountWithSource:edge->sourceRowid
					                                     name:edge->name
					                     excludingDestination:edge->destinationRowid];
					if (count == 0)
					{
						YDBLogVerbose(@"Deleting source node: key(%@) collection(%@)",
						              edge->sourceKey, edge->sourceCollection);
						
						__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
						  (YapDatabaseReadWriteTransaction *)databaseTransaction;
						
						[databaseRwTransaction removeObjectForKey:edge->sourceKey
						                             inCollection:edge->sourceCollection
						                                withRowid:edge->sourceRowid];
					}
				}
			}
		}
	}];
	
	// STEP 3:
	//
	// Process all the deleted nodes.
	// For each deleted node we're going to enumerate all connected edges.
	// First the edges where the deleted node is the source.
	// Then the edges where the deleted node is the destination.
	//
	// Note that at this point, the database is up-to-date (we've written all changes).
	// So we can simply enumerate and query the database without any fuss.
	
	NSUInteger i = 0;
	while (i < [relationshipConnection->deletedOrder count])
	{
		NSNumber *rowidNumber = [relationshipConnection->deletedOrder objectAtIndex:i];
		int64_t rowid = [rowidNumber longLongValue];
		
		YapCollectionKey *collectionKey = [relationshipConnection->deletedInfo objectForKey:rowidNumber];
		
		// Enumerate all edges where source node is this deleted node.
		[self enumerateExistingEdgesWithSrc:rowid
		                         usingBlock:^(int64_t edgeRowid, NSString *name, int64_t dstRowid, int nodeDeleteRules)
		{
			if ([relationshipConnection->deletedInfo ydb_containsKey:@(dstRowid)])
			{
				// Both source and destination node have been deleted
			}
			else
			{
				if (nodeDeleteRules & YDB_DeleteDestinationIfSourceDeleted)
				{
					// Delete the destination node
					
					NSString *dstKey = nil;
					NSString *dstCollection = nil;
					[databaseTransaction getKey:&dstKey collection:&dstCollection forRowid:dstRowid];
					
					YDBLogVerbose(@"Deleting destination node: key(%@) collection(%@)", dstKey, dstCollection);
					
					__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
					  (YapDatabaseReadWriteTransaction *)databaseTransaction;
					
					[databaseRwTransaction removeObjectForKey:dstKey inCollection:dstCollection withRowid:dstRowid];
				}
				else if (nodeDeleteRules & YDB_DeleteDestinationIfAllSourcesDeleted)
				{
					// Delete the destination node IF there are no other edges pointing to it with the same name
					
					int64_t count = [self edgeCountWithDestination:dstRowid name:name excludingSource:rowid];
					if (count == 0)
					{
						NSString *dstKey = nil;
						NSString *dstCollection = nil;
						[databaseTransaction getKey:&dstKey collection:&dstCollection forRowid:dstRowid];
						
						YDBLogVerbose(@"Deleting destination node: key(%@) collection(%@)", dstKey, dstCollection);
						
						__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
						  (YapDatabaseReadWriteTransaction *)databaseTransaction;
						
						[databaseRwTransaction removeObjectForKey:dstKey inCollection:dstCollection withRowid:dstRowid];
					}
				}
				else if (nodeDeleteRules & YDB_NotifyIfSourceDeleted)
				{
					// Notify the destination node
					
					NSString *dstKey = nil;
					NSString *dstCollection = nil;
					id dstNode = nil;
					
					[databaseTransaction getKey:&dstKey collection:&dstCollection object:&dstNode forRowid:dstRowid];
					
					SEL selector = @selector(yapDatabaseRelationshipEdgeDeleted:withReason:);
					if ([dstNode respondsToSelector:selector])
					{
						YapDatabaseRelationshipEdge *edge = [[YapDatabaseRelationshipEdge alloc] init];
						edge->name = name;
						edge->sourceKey = collectionKey.key;
						edge->sourceCollection = collectionKey.collection;
						edge->sourceRowid = rowid;
						edge->destinationKey = dstKey;
						edge->destinationCollection = dstCollection;
						edge->destinationRowid = dstRowid;
						edge->nodeDeleteRules = nodeDeleteRules;
						
						id updatedDstNode =
						  [dstNode yapDatabaseRelationshipEdgeDeleted:edge withReason:YDB_NotifyIfSourceDeleted];
						
						if (updatedDstNode)
						{
							__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
							  (YapDatabaseReadWriteTransaction *)databaseTransaction;
							
							[databaseRwTransaction replaceObject:updatedDstNode
							                              forKey:edge->destinationKey
							                        inCollection:edge->destinationCollection
							                           withRowid:edge->destinationRowid];
						}
					}
				}
			}
		}]; // end enumerateExistingRowsWithSrc:usingBlock:
		
		
		// Enumerate all edges where destination node is this deleted node.
		[self enumerateExistingEdgesWithDst:rowid
		                         usingBlock:^(int64_t edgeRowid, NSString *name, int64_t srcRowid, int nodeDeleteRules)
		{
			if ([relationshipConnection->deletedInfo ydb_containsKey:@(srcRowid)])
			{
				// Both source and destination node have been deleted
			}
			else
			{
				if (nodeDeleteRules & YDB_DeleteSourceIfDestinationDeleted)
				{
					// Delete the source node
					
					NSString *srcKey = nil;
					NSString *srcCollection = nil;
					[databaseTransaction getKey:&srcKey collection:&srcCollection forRowid:srcRowid];
					
					YDBLogVerbose(@"Deleting source node: key(%@) collection(%@)", srcKey, srcCollection);
					
					__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
					  (YapDatabaseReadWriteTransaction *)databaseTransaction;
					
					[databaseRwTransaction removeObjectForKey:srcKey inCollection:srcCollection withRowid:srcRowid];
				}
				else if (nodeDeleteRules & YDB_DeleteSourceIfAllDestinationsDeleted)
				{
					// Delete the source node IF there are no other edges pointing from it with the same name
					
					int64_t count = [self edgeCountWithSource:srcRowid name:name excludingDestination:rowid];
					if (count == 0)
					{
						NSString *srcKey = nil;
						NSString *srcCollection = nil;
						[databaseTransaction getKey:&srcKey collection:&srcCollection forRowid:srcRowid];
						
						YDBLogVerbose(@"Deleting source node: key(%@) collection(%@)", srcKey, srcCollection);
						
						__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
						(YapDatabaseReadWriteTransaction *)databaseTransaction;
						
						[databaseRwTransaction removeObjectForKey:srcKey inCollection:srcCollection withRowid:srcRowid];
					}
				}
				else if (nodeDeleteRules & YDB_NotifyIfDestinationDeleted)
				{
					// Notify the source node
					
					NSString *srcKey = nil;
					NSString *srcCollection = nil;
					id srcNode = nil;
					
					[databaseTransaction getKey:&srcKey collection:&srcCollection object:&srcNode forRowid:srcRowid];
					
					SEL selector = @selector(yapDatabaseRelationshipEdgeDeleted:withReason:);
					if ([srcNode respondsToSelector:selector])
					{
						YapDatabaseRelationshipEdge *edge = [[YapDatabaseRelationshipEdge alloc] init];
						edge->name = name;
						edge->sourceKey = srcKey;
						edge->sourceCollection = srcCollection;
						edge->sourceRowid = srcRowid;
						edge->destinationKey = collectionKey.key;
						edge->destinationCollection = collectionKey.collection;
						edge->destinationRowid = rowid;
						edge->nodeDeleteRules = nodeDeleteRules;
						
						id updatedSrcNode =
						  [srcNode yapDatabaseRelationshipEdgeDeleted:edge withReason:YDB_NotifyIfDestinationDeleted];
						
						if (updatedSrcNode)
						{
							__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
							  (YapDatabaseReadWriteTransaction *)databaseTransaction;
							
							[databaseRwTransaction replaceObject:updatedSrcNode
							                              forKey:edge->sourceKey
							                        inCollection:edge->sourceCollection
							                           withRowid:edge->sourceRowid];
						}
					}
				}
			}
			
		}]; // end enumerateExistingRowsWithDst:usingBlock:
		
		// Delete all the edges where source or destination is this deleted node.
		[self deleteEdgesWithSourceOrDestination:rowid];
		
		i++;
	}
	
	// DONE !
	//
	// Clear ivars we've processed.
	
	[relationshipConnection->changes removeAllObjects];
	[relationshipConnection->inserted removeAllObjects];
	[relationshipConnection->deletedInfo removeAllObjects];
	[relationshipConnection->deletedOrder removeAllObjects];
	
	isFlushing = NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cleanup & Commit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is only called if within a readwrite transaction.
 *
 * Extensions may implement it to perform any "cleanup" before the changeset is requested.
 * Remember, the changeset is requested before the commitTransaction method is invoked.
**/
- (void)preCommitReadWriteTransaction
{
	YDBLogAutoTrace();
	
	[self flush];
}

/**
 * This method is only called if within a readwrite transaction.
**/
- (void)commitTransaction
{
	YDBLogAutoTrace();
	
	relationshipConnection = nil;
	databaseTransaction = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseExtensionTransaction_Hooks
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
	
	if (isFlushing)
	{
		YDBLogWarn(@"Unable to handle insert hook during flush processing");
		return;
	}
	
	NSNumber *rowidNumber = @(rowid);
	
	// Request edges from object
	
	NSArray *givenEdges = nil;
	
	if ([object conformsToProtocol:@protocol(YapDatabaseRelationshipNode)])
	{
		givenEdges = [object yapDatabaseRelationshipEdges];
	}
	
	// Make copies, and fill in missing src information
	
	NSMutableArray *edges = nil;
	
	if ([givenEdges count] > 0)
	{
		edges = [NSMutableArray arrayWithCapacity:[givenEdges count]];
		
		__unsafe_unretained NSString *collection = collectionKey.collection;
		__unsafe_unretained NSString *key = collectionKey.key;
		
		for (YapDatabaseRelationshipEdge *edge in givenEdges)
		{
			[edges addObject:[edge copyWithSourceKey:key collection:collection rowid:rowid]];
		}
	}
	
	// We know this is an insert, so the database thinks its a new item.
	// But this could be due to a delete, followed by a set.
	// For example:
	//
	// [transaction removeObjectForKey:@"key" inCollection:@"collection"];
	// [transaction setObject:object forKey:@"key" inCollection:@"collection"]; <- marked as insert
	//
	// So to be safe, we'll check the deletedInfo and remove the item from the deleted list if needed.
	
	if ([relationshipConnection->deletedInfo ydb_containsKey:rowidNumber])
	{
		NSUInteger index = [relationshipConnection->deletedOrder indexOfObject:rowidNumber];
		
		[relationshipConnection->deletedOrder removeObjectAtIndex:index];
		[relationshipConnection->deletedInfo removeObjectForKey:rowidNumber];
		
		// Not really an insert.
		// More like a two-step replace.
		//
		// Note: If the user wants the delete to cause cascading deletes, they should invoke the flush method.
		
		if (edges == nil)
			edges = [NSMutableArray arrayWithCapacity:0];
		
		[relationshipConnection->changes setObject:edges forKey:rowidNumber];
	}
	else if (edges)
	{
		// We store the fact that this item was inserted.
		// That way we can later skip the step where we query the database for existing edges.
		
		[relationshipConnection->changes setObject:edges forKey:rowidNumber];
		[relationshipConnection->inserted addObject:rowidNumber];
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
	
	if (isFlushing)
	{
		YDBLogWarn(@"Unable to handle update hook during flush processing");
		return;
	}
	
	// Request edges from object
	
	NSArray *givenEdges = nil;
	
	if ([object conformsToProtocol:@protocol(YapDatabaseRelationshipNode)])
	{
		givenEdges = [object yapDatabaseRelationshipEdges];
	}
	
	NSMutableArray *edges = nil;
	
	if (givenEdges)
	{
		edges = [NSMutableArray arrayWithCapacity:[givenEdges count]];
		
		__unsafe_unretained NSString *collection = collectionKey.collection;
		__unsafe_unretained NSString *key = collectionKey.key;
		
		for (YapDatabaseRelationshipEdge *edge in givenEdges)
		{
			[edges addObject:[edge copyWithSourceKey:key collection:collection rowid:rowid]];
		}
	}
	else
	{
		edges = [NSMutableArray arrayWithCapacity:0];
	}
	
	[relationshipConnection->changes setObject:edges forKey:@(rowid)];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// This method may be called during flush processing due to an edge's nodeDeleteRules.
	if (isFlushing)
	{
		// Ignore: This method is called due to edge notify rules.
		return;
	}
	
	NSArray *givenEdges = nil;
	
	if ([object conformsToProtocol:@protocol(YapDatabaseRelationshipNode)])
	{
		givenEdges = [object yapDatabaseRelationshipEdges];
	}
	
	NSMutableArray *edges = nil;
	
	if (givenEdges)
	{
		edges = [NSMutableArray arrayWithCapacity:[givenEdges count]];
		
		__unsafe_unretained NSString *collection = collectionKey.collection;
		__unsafe_unretained NSString *key = collectionKey.key;
		
		for (YapDatabaseRelationshipEdge *edge in givenEdges)
		{
			[edges addObject:[edge copyWithSourceKey:key collection:collection rowid:rowid]];
		}
	}
	else
	{
		edges = [NSMutableArray arrayWithCapacity:0];
	}
	
	[relationshipConnection->changes setObject:edges forKey:@(rowid)];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Nothing to do in this extension for metadata
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleTouchObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Nothing to do in this extension for touches
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleTouchMetadataForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Nothing to do in this extension for touches
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Note: This method may be called during flush processing due to an edge's nodeDeleteRules.
	
	NSNumber *srcNumber = @(rowid);
	
	[relationshipConnection->deletedOrder addObject:srcNumber];
	[relationshipConnection->deletedInfo setObject:collectionKey forKey:srcNumber];
	
	// Note: This method may be called during flush processing due to an edge's nodeDeleteRules.
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	YDBLogAutoTrace();
	
	if (isFlushing)
	{
		YDBLogWarn(@"Unable to handle multi-remove hook during flush processing");
		return;
	}
	
	NSUInteger i = 0;
	for (NSNumber *srcNumber in rowids)
	{
		NSString *key = [keys objectAtIndex:i];
		YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		[relationshipConnection->deletedOrder addObject:srcNumber];
		[relationshipConnection->deletedInfo setObject:collectionKey forKey:srcNumber];
		
		i++;
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveAllObjectsInAllCollections
{
	YDBLogAutoTrace();
	
	if (isFlushing)
	{
		YDBLogWarn(@"Unable to handle remove-all hook during flush processing");
		return;
	}
	
	[self removeAllEdges];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API - Enumerate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Enumerates every edge in the graph with the given name.
 *
 * @param name
 *   The name of the edge (case sensitive).
**/
- (void)enumerateEdgesWithName:(NSString *)name
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	if (name == nil) return;
	if (block == NULL) return;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name
												  destinationKey:nil
													  collection:nil];
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement = [relationshipConnection enumerateForNameStatement];
	if (statement == NULL)
		return;
	
	BOOL stop = NO;

	// SELECT "rowid", "src", "dst", "rules" FROM "tableName" WHERE "name" = ?;
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, name);
	sqlite3_bind_text(statement, 1, _name.str, _name.length, SQLITE_STATIC);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t edgeRowid = sqlite3_column_int64(statement, 0);
		int64_t srcRowid = sqlite3_column_int64(statement, 1);
		int64_t dstRowid = sqlite3_column_int64(statement, 2);
		
		int rules = sqlite3_column_int(statement, 3);
		
		YapDatabaseRelationshipEdge *edge = nil;
		
		// Does the edge on disk have a corresponding edge in memory that overrides it?
		
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			if (changedEdge->sourceRowid == srcRowid)
			{
				if (changedEdge->destinationRowid != 0 || changedEdge->flags == 2)
				{
					if (changedEdge->destinationRowid == dstRowid)
					{
						edge = changedEdge;
						
						[changedEdges removeObjectAtIndex:i];
						break;
					}
				}
			}
			
			i++;
		}
		
		// Check to see if the edge is broken (one or more nodes have been deleted).
		
		BOOL edgeBroken = [relationshipConnection->deletedInfo ydb_containsKey:@(srcRowid)] ||
		                  [relationshipConnection->deletedInfo ydb_containsKey:@(dstRowid)];
		
		if (!edgeBroken)
		{
			// If we don't have an updated version of the edge in memory (pending update on disk),
			// then create an edge instance from the data.
			
			if (edge == nil)
			{
				edge = [[YapDatabaseRelationshipEdge alloc] initWithRowid:edgeRowid
			                                                         name:name
			                                                          src:srcRowid
			                                                          dst:dstRowid
			                                                        rules:rules];
				
				NSString *srcKey = nil;
				NSString *srcCollection = nil;
				[databaseTransaction getKey:&srcKey collection:&srcCollection forRowid:srcRowid];
				
				edge->sourceKey = srcKey;
				edge->sourceCollection = srcCollection;
				
				NSString *dstKey = nil;
				NSString *dstCollection = nil;
				[databaseTransaction getKey:&dstKey collection:&dstCollection forRowid:dstRowid];
				
				edge->destinationKey = dstKey;
				edge->destinationCollection = dstCollection;
			}
			
			block(edge, &stop);
			if (stop) break;
		}
	}
	
	if (status != SQLITE_DONE && !stop)
	{
		YDBLogError(@"%@ (%@): Error in statement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
		
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_name);
	
	if (stop) return;
	
	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	for (YapDatabaseRelationshipEdge *edge in changedEdges)
	{
		if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
		{
			// broken edge (source node deleted)
			continue;
		}
		
		if (edge->destinationRowid != 0 || edge->flags == 2)
		{
			if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
			{
				// broken edge (destination node deleted)
				continue;
			}
		}
		
		block(edge, &stop);
		if (stop) break;
	}
}

/**
 * Enumerates every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - sourceKey & sourceCollection only
 * - name + sourceKey & sourceCollection
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param sourceKey (optional)
 *   The edge.sourceKey to match.
 *
 * @param sourceCollection (optional)
 *   The edge.sourceCollection to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (void)enumerateEdgesWithName:(NSString *)name
                     sourceKey:(NSString *)srcKey
                    collection:(NSString *)srcCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	if (srcKey == nil)
	{
		[self enumerateEdgesWithName:name usingBlock:block];
		return;
	}
	
	if (block == NULL) return;
	
	if (srcCollection == nil)
		srcCollection = @"";
	
	int64_t srcRowid = 0;
	BOOL found = [databaseTransaction getRowid:&srcRowid forKey:srcKey inCollection:srcCollection];
	
	if (!found)
	{
		// The item doesn't exist in the database.
		return;
	}
	
	BOOL stop = NO;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	//
	// Note: This specific case is easy, because we can do a direct lookup using the srcRowid.
	//       And if there's an in-memory list, then this is the complete list.
	
	NSMutableArray *changedEdges = [relationshipConnection->changes objectForKey:@(srcRowid)];
	if (changedEdges)
	{
		for (YapDatabaseRelationshipEdge *edge in changedEdges)
		{
			if (name && ![name isEqualToString:edge->name])
			{
				continue;
			}
			
			block(edge, &stop);
			if (stop) break;
		}
		
		return;
	}
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement;
	YapDatabaseString _name;
	
	if (name)
	{
		statement = [relationshipConnection enumerateForSrcNameStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "dst", "rules" FROM "tableName" WHERE "src" = ? AND "name" = ?;",
		
		sqlite3_bind_int64(statement, 1, srcRowid);
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 2, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection enumerateForSrcStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "name", "dst", "rules" FROM "tableName" WHERE "src" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
	}
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		NSString *edgeName = nil;
		int64_t edgeRowid;
		int64_t dstRowid;
		int rules;
		
		if (name)
		{
			edgeRowid = sqlite3_column_int64(statement, 0);
			dstRowid = sqlite3_column_int64(statement, 1);
			rules = sqlite3_column_int(statement, 2);
		}
		else
		{
			edgeRowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text = sqlite3_column_text(statement, 1);
			int textSize = sqlite3_column_bytes(statement, 1);
			
			dstRowid = sqlite3_column_int64(statement, 2);
			rules = sqlite3_column_int(statement, 3);
			
			edgeName = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		
		// Check to see if the edge is broken (one or more nodes have been deleted).
		
		BOOL edgeBroken = [relationshipConnection->deletedInfo ydb_containsKey:@(dstRowid)];
		
		if (!edgeBroken)
		{
			YapDatabaseRelationshipEdge *edge =
			  [[YapDatabaseRelationshipEdge alloc] initWithRowid:edgeRowid
			                                                name:name ? name : edgeName
			                                                 src:srcRowid
			                                                 dst:dstRowid
			                                               rules:rules];
			
			edge->sourceKey = srcKey;
			edge->sourceCollection = srcCollection;
			
			NSString *dstKey = nil;
			NSString *dstCollection = nil;
			[databaseTransaction getKey:&dstKey collection:&dstCollection forRowid:dstRowid];
			
			edge->destinationKey = dstKey;
			edge->destinationCollection = dstCollection;
			
			block(edge, &stop);
			if (stop) break;
		}
	}
	
	if (status != SQLITE_DONE && !stop)
	{
		YDBLogError(@"%@ (%@): Error in statement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
	if (name) {
		FreeYapDatabaseString(&_name);
	}
}

/**
 * Enumerates every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - destinationKey & destinationCollection only
 * - name + destinationKey & destinationCollection
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param destinationKey (optional)
 *   The edge.destinationKey to match.
 *
 * @param destinationCollection (optional)
 *   The edge.destinationCollection to match.
 *
 * If you pass a non-nil destinationKey, and destinationCollection is nil,
 * then the destinationCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (void)enumerateEdgesWithName:(NSString *)name
                destinationKey:(NSString *)dstKey
                    collection:(NSString *)dstCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	if (dstKey == nil)
	{
		[self enumerateEdgesWithName:name usingBlock:block];
		return;
	}
	
	if (block == NULL) return;
	
	if (dstCollection == nil)
		dstCollection = @"";
	
	int64_t dstRowid = 0;
	BOOL found = [databaseTransaction getRowid:&dstRowid forKey:dstKey inCollection:dstCollection];
	
	if (!found)
	{
		// The item doesn't exist in the database.
		return;
	}
	
	BOOL stop = NO;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name
	                                              destinationKey:dstKey
													  collection:dstCollection];
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement;
	YapDatabaseString _name;
	
	if (name)
	{
		statement = [relationshipConnection enumerateForDstNameStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "src", "rules" FROM "tableName" WHERE "dst" = ? AND "name" = ?;
		
		sqlite3_bind_int64(statement, 1, dstRowid);
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 2, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection enumerateForDstStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "name", "src", "rules" FROM "tableName" WHERE "dst" = ?;
		
		sqlite3_bind_int64(statement, 1, dstRowid);
	}
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		NSString *edgeName = nil;
		int64_t edgeRowid;
		int64_t srcRowid;
		int rules;
		
		if (name)
		{
			edgeRowid = sqlite3_column_int64(statement, 0);
			srcRowid = sqlite3_column_int64(statement, 1);
			rules = sqlite3_column_int(statement, 2);
		}
		else
		{
			edgeRowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text = sqlite3_column_text(statement, 1);
			int textSize = sqlite3_column_bytes(statement, 1);
			
			srcRowid = sqlite3_column_int64(statement, 2);
			rules = sqlite3_column_int(statement, 3);
			
			edgeName = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		
		YapDatabaseRelationshipEdge *edge = nil;
		
		// Does the edge on disk have a corresponding edge in memory that overrides it?
		
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			if (changedEdge->sourceRowid == srcRowid)
			{
				if (changedEdge->destinationRowid != 0 || changedEdge->flags == 2)
				{
					if (changedEdge->destinationRowid == dstRowid)
					{
						edge = changedEdge;
						
						[changedEdges removeObjectAtIndex:i];
						break;
					}
				}
			}
			
			i++;
		}
		
		// Check to see if the edge is broken (one or more nodes have been deleted).
		
		BOOL edgeBroken = [relationshipConnection->deletedInfo ydb_containsKey:@(srcRowid)];
		
		if (!edgeBroken)
		{
			// If we don't have an updated version of the edge in memory (pending update on disk),
			// then create an edge instance from the data.
			
			if (edge == nil)
			{
				edge = [[YapDatabaseRelationshipEdge alloc] initWithRowid:edgeRowid
			                                                         name:name ? name : edgeName
			                                                          src:srcRowid
			                                                          dst:dstRowid
			                                                        rules:rules];
				
				NSString *srcKey = nil;
				NSString *srcCollection = nil;
				[databaseTransaction getKey:&srcKey collection:&srcCollection forRowid:srcRowid];
				
				edge->sourceKey = srcKey;
				edge->sourceCollection = srcCollection;
				
				edge->destinationKey = dstKey;
				edge->destinationCollection = dstCollection;
			}
			
			block(edge, &stop);
			if (stop) break;
		}
	}
	
	if (status != SQLITE_DONE && !stop)
	{
		YDBLogError(@"%@ (%@): Error in statement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
	if (name) {
		FreeYapDatabaseString(&_name);
	}
	
	if (stop) return;
	
	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	for (YapDatabaseRelationshipEdge *edge in changedEdges)
	{
		if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
		{
			// broken edge (source node deleted)
			continue;
		}
		
		block(edge, &stop);
		if (stop) break;
	}
}

/**
 * Enumerates every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - sourceKey & sourceCollection only
 * - destinationKey & destinationCollection only
 * - name + sourceKey & sourceCollection
 * - name + destinationKey & destinationCollection
 * - name + sourceKey & sourceCollection + destinationKey & destinationCollection
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param sourceKey (optional)
 *   The edge.sourceKey to match.
 *
 * @param sourceCollection (optional)
 *   The edge.sourceCollection to match.
 *
 * @param destinationKey (optional)
 *   The edge.destinationKey to match.
 *
 * @param destinationCollection (optional)
 *   The edge.destinationCollection to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
 *
 * If you pass a non-nil destinationKey, and destinationCollection is nil,
 * then the destinationCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (void)enumerateEdgesWithName:(NSString *)name
                     sourceKey:(NSString *)srcKey
                    collection:(NSString *)srcCollection
                destinationKey:(NSString *)dstKey
                    collection:(NSString *)dstCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	if (srcKey == nil)
	{
		if (dstKey == nil)
			[self enumerateEdgesWithName:name usingBlock:block];
		else
			[self enumerateEdgesWithName:name destinationKey:dstKey collection:dstCollection usingBlock:block];
		
		return;
	}
	if (dstKey == nil)
	{
		[self enumerateEdgesWithName:name sourceKey:srcKey collection:srcCollection usingBlock:block];
		return;
	}
	
	if (block == NULL) return;
	
	if (srcCollection == nil)
		srcCollection = @"";
	
	if (dstCollection == nil)
		dstCollection = @"";
	
	BOOL found;
	
	int64_t srcRowid = 0;
	found = [databaseTransaction getRowid:&srcRowid forKey:srcKey inCollection:srcCollection];
	if (!found)
	{
		// The source node doesn't exist in the database.
		return;
	}
	
	int64_t dstRowid = 0;
	found = [databaseTransaction getRowid:&dstRowid forKey:dstKey inCollection:dstCollection];
	if (!found)
	{
		// The destination node doesn't exist in the database.
		return;
	}
	
	BOOL stop = NO;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	//
	// Note: This specific case is easy, because we can do a direct lookup using the srcRowid.
	//       And if there's an in-memory list, then this is the complete list.
	
	NSMutableArray *changedEdges = [relationshipConnection->changes objectForKey:@(srcRowid)];
	if (changedEdges)
	{
		for (YapDatabaseRelationshipEdge *edge in changedEdges)
		{
			if (name && ![name isEqualToString:edge->name])
			{
				continue;
			}
			
			if (![dstKey isEqualToString:edge->destinationKey] ||
			    ![dstCollection isEqualToString:edge->destinationCollection])
			{
				continue;
			}
			
			block(edge, &stop);
			if (stop) break;
		}
		
		return;
	}
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement;
	YapDatabaseString _name;
	
	if (name)
	{
		statement = [relationshipConnection enumerateForSrcDstNameStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "rules" FROM "tableName" WHERE "src" = ? AND "dst" = ? AND "name" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
		sqlite3_bind_int64(statement, 2, dstRowid);
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 3, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection enumerateForSrcDstStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "name", "rules" FROM "tableName" WHERE "src" = ? AND "dst" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
		sqlite3_bind_int64(statement, 2, dstRowid);
	}
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		NSString *edgeName = nil;
		int64_t edgeRowid;
		int rules;
		
		if (name)
		{
			edgeRowid = sqlite3_column_int64(statement, 0);
			rules = sqlite3_column_int(statement, 1);
		}
		else
		{
			edgeRowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text = sqlite3_column_text(statement, 1);
			int textSize = sqlite3_column_bytes(statement, 1);
			
			rules = sqlite3_column_int(statement, 2);
			
			edgeName = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		
		YapDatabaseRelationshipEdge *edge =
		  [[YapDatabaseRelationshipEdge alloc] initWithRowid:edgeRowid
		                                                name:name ? name : edgeName
		                                                 src:srcRowid
		                                                 dst:dstRowid
		                                               rules:rules];
		
		edge->sourceKey = srcKey;
		edge->sourceCollection = srcCollection;
		
		edge->destinationKey = dstKey;
		edge->destinationCollection = dstCollection;
		
		block(edge, &stop);
		if (stop) break;
	}
	
	if (status != SQLITE_DONE && !stop)
	{
		YDBLogError(@"%@ (%@): Error in statement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
	if (name) {
		FreeYapDatabaseString(&_name);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API - Count
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns a count of every edge in the graph with the given name.
 *
 * @param name
 *   The name of the edge (case sensitive).
**/
- (NSUInteger)edgeCountWithName:(NSString *)name
{
	if (name == nil) return 0;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name
	                                              destinationKey:nil
	                                                  collection:nil];
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement = [relationshipConnection enumerateForNameStatement];
	if (statement == NULL) return 0;

	NSUInteger edgeCount = 0;
	
	// SELECT "rowid", "src", "dst", "rules" FROM "tableName" WHERE "name" = ?;
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, name);
	sqlite3_bind_text(statement, 1, _name.str, _name.length, SQLITE_STATIC);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
	//	int64_t edgeRowid = sqlite3_column_int64(statement, 0);
		int64_t srcRowid = sqlite3_column_int64(statement, 1);
		int64_t dstRowid = sqlite3_column_int64(statement, 2);
		
	//	int rules = sqlite3_column_int(statement, 3);
		
		YapDatabaseRelationshipEdge *edge = nil;
		
		// Does the edge on disk have a corresponding edge in memory that overrides it?
		
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			if (changedEdge->sourceRowid == srcRowid)
			{
				if (changedEdge->destinationRowid != 0 || changedEdge->flags == 2)
				{
					if (changedEdge->destinationRowid == dstRowid)
					{
						edge = changedEdge;
						
						[changedEdges removeObjectAtIndex:i];
						break;
					}
				}
			}
			
			i++;
		}
		
		// Check to see if the edge is broken (one or more nodes have been deleted).
		
		BOOL edgeBroken = [relationshipConnection->deletedInfo ydb_containsKey:@(srcRowid)] ||
		                  [relationshipConnection->deletedInfo ydb_containsKey:@(dstRowid)];
		
		if (!edgeBroken)
		{
			edgeCount++;
		}
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ (%@): Error in statement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
		
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_name);
	
	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	for (YapDatabaseRelationshipEdge *edge in changedEdges)
	{
		if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
		{
			// broken edge (source node deleted)
			continue;
		}
		
		if (edge->destinationRowid != 0 || edge->flags == 2)
		{
			if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
			{
				// broken edge (destination node deleted)
				continue;
			}
		}
		
		edgeCount++;
	}
	
	return edgeCount;
}

/**
 * Returns a count of every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - sourceKey & sourceCollection only
 * - name + sourceKey & sourceCollection
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param sourceKey (optional)
 *   The edge.sourceKey to match.
 *
 * @param sourceCollection (optional)
 *   The edge.sourceCollection to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (NSUInteger)edgeCountWithName:(NSString *)name
                      sourceKey:(NSString *)srcKey
                     collection:(NSString *)srcCollection
{
	if (srcKey == nil)
	{
		return [self edgeCountWithName:name];
	}
	
	if (srcCollection == nil)
		srcCollection = @"";
	
	int64_t srcRowid = 0;
	BOOL found = [databaseTransaction getRowid:&srcRowid forKey:srcKey inCollection:srcCollection];
	
	if (!found)
	{
		// The item doesn't exist in the database.
		return 0;
	}
	
	NSUInteger edgeCount = 0;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	//
	// Note: This specific case is easy, because we can do a direct lookup using the srcRowid.
	//       And if there's an in-memory list, then this is the complete list.
	
	NSMutableArray *changedEdges = [relationshipConnection->changes objectForKey:@(srcRowid)];
	if (changedEdges)
	{
		for (YapDatabaseRelationshipEdge *edge in changedEdges)
		{
			if (name && ![name isEqualToString:edge->name])
			{
				continue;
			}
			
			edgeCount++;
		}
		
		return edgeCount;
	}
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement;
	YapDatabaseString _name;
	
	if (name)
	{
		statement = [relationshipConnection enumerateForSrcNameStatement];
		if (statement == NULL) return 0;
		
		// SELECT "rowid", "dst", "rules" FROM "tableName" WHERE "src" = ? AND "name" = ?;",
		
		sqlite3_bind_int64(statement, 1, srcRowid);
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 2, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection enumerateForSrcStatement];
		if (statement == NULL) return 0;
		
		// SELECT "rowid", "name", "dst", "rules" FROM "tableName" WHERE "src" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
	}
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
	//	NSString *edgeName = nil;
	//	int64_t edgeRowid;
		int64_t dstRowid;
	//	int rules;
		
		if (name)
		{
		//	edgeRowid = sqlite3_column_int64(statement, 0);
			dstRowid = sqlite3_column_int64(statement, 1);
		//	rules = sqlite3_column_int(statement, 2);
		}
		else
		{
		//	edgeRowid = sqlite3_column_int64(statement, 0);
			
		//	const unsigned char *text = sqlite3_column_text(statement, 1);
		//	int textSize = sqlite3_column_bytes(statement, 1);
			
			dstRowid = sqlite3_column_int64(statement, 2);
		//	rules = sqlite3_column_int(statement, 3);
			
		//	edgeName = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		
		// Check to see if the edge is broken (one or more nodes have been deleted).
		
		BOOL edgeBroken = [relationshipConnection->deletedInfo ydb_containsKey:@(dstRowid)];
		
		if (!edgeBroken)
		{
			edgeCount++;
		}
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ (%@): Error in statement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
	if (name) {
		FreeYapDatabaseString(&_name);
	}
	
	return edgeCount;
}

/**
 * Returns a count of every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - destinationKey & destinationCollection only
 * - name + destinationKey & destinationCollection
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param destinationKey (optional)
 *   The edge.destinationKey to match.
 *
 * @param destinationCollection (optional)
 *   The edge.destinationCollection to match.
 *
 * If you pass a non-nil destinationKey, and destinationCollection is nil,
 * then the destinationCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (NSUInteger)edgeCountWithName:(NSString *)name
                 destinationKey:(NSString *)dstKey
                     collection:(NSString *)dstCollection
{
	if (dstKey == nil)
	{
		return [self edgeCountWithName:name];
	}
	
	if (dstCollection == nil)
		dstCollection = @"";
	
	int64_t dstRowid = 0;
	BOOL found = [databaseTransaction getRowid:&dstRowid forKey:dstKey inCollection:dstCollection];
	
	if (!found)
	{
		// The item doesn't exist in the database.
		return 0;
	}
	
	NSUInteger edgeCount = 0;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name
	                                              destinationKey:dstKey
													  collection:dstCollection];
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement;
	YapDatabaseString _name;
	
	if (name)
	{
		statement = [relationshipConnection enumerateForDstNameStatement];
		if (statement == NULL) return 0;
		
		// SELECT "rowid", "src", "rules" FROM "tableName" WHERE "dst" = ? AND "name" = ?;
		
		sqlite3_bind_int64(statement, 1, dstRowid);
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 2, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection enumerateForDstStatement];
		if (statement == NULL) return 0;
		
		// SELECT "rowid", "name", "src", "rules" FROM "tableName" WHERE "dst" = ?;
		
		sqlite3_bind_int64(statement, 1, dstRowid);
	}
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
	//	NSString *edgeName = nil;
	//	int64_t edgeRowid;
		int64_t srcRowid;
	//	int rules;
		
		if (name)
		{
		//	edgeRowid = sqlite3_column_int64(statement, 0);
			srcRowid = sqlite3_column_int64(statement, 1);
		//	rules = sqlite3_column_int(statement, 2);
		}
		else
		{
		//	edgeRowid = sqlite3_column_int64(statement, 0);
			
		//	const unsigned char *text = sqlite3_column_text(statement, 1);
		//	int textSize = sqlite3_column_bytes(statement, 1);
			
			srcRowid = sqlite3_column_int64(statement, 2);
		//	rules = sqlite3_column_int(statement, 3);
			
		//	edgeName = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		
		YapDatabaseRelationshipEdge *edge = nil;
		
		// Does the edge on disk have a corresponding edge in memory that overrides it?
		
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			if (changedEdge->sourceRowid == srcRowid)
			{
				if (changedEdge->destinationRowid != 0 || changedEdge->flags == 2)
				{
					if (changedEdge->destinationRowid == dstRowid)
					{
						edge = changedEdge;
						
						[changedEdges removeObjectAtIndex:i];
						break;
					}
				}
			}
			
			i++;
		}
		
		// Check to see if the edge is broken (one or more nodes have been deleted).
		
		BOOL edgeBroken = [relationshipConnection->deletedInfo ydb_containsKey:@(srcRowid)];
		
		if (!edgeBroken)
		{
			edgeCount++;
		}
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ (%@): Error in statement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
	if (name) {
		FreeYapDatabaseString(&_name);
	}
	
	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	for (YapDatabaseRelationshipEdge *edge in changedEdges)
	{
		if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
		{
			// broken edge (source node deleted)
			continue;
		}
		
		edgeCount++;
	}
	
	return edgeCount;
}

/**
 * Returns a count of every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - sourceKey & sourceCollection only
 * - destinationKey & destinationCollection only
 * - name + sourceKey & sourceCollection
 * - name + destinationKey & destinationCollection
 * - name + sourceKey & sourceCollection + destinationKey & destinationCollection
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param sourceKey (optional)
 *   The edge.sourceKey to match.
 *
 * @param sourceCollection (optional)
 *   The edge.sourceCollection to match.
 *
 * @param destinationKey (optional)
 *   The edge.destinationKey to match.
 *
 * @param destinationCollection (optional)
 *   The edge.destinationCollection to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
 *
 * If you pass a non-nil destinationKey, and destinationCollection is nil,
 * then the destinationCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (NSUInteger)edgeCountWithName:(NSString *)name
                      sourceKey:(NSString *)srcKey
                     collection:(NSString *)srcCollection
                 destinationKey:(NSString *)dstKey
                     collection:(NSString *)dstCollection
{
	if (srcKey == nil)
	{
		if (dstKey == nil)
			return [self edgeCountWithName:name];
		else
			return [self edgeCountWithName:name destinationKey:dstKey collection:dstCollection];
	}
	if (dstKey == nil)
	{
		return [self edgeCountWithName:name sourceKey:srcKey collection:srcCollection];
	}
	
	if (srcCollection == nil)
		srcCollection = @"";
	
	if (dstCollection == nil)
		dstCollection = @"";
	
	BOOL found;
	
	int64_t srcRowid = 0;
	found = [databaseTransaction getRowid:&srcRowid forKey:srcKey inCollection:srcCollection];
	if (!found)
	{
		// The source node doesn't exist in the database.
		return 0;
	}
	
	int64_t dstRowid = 0;
	found = [databaseTransaction getRowid:&dstRowid forKey:dstKey inCollection:dstCollection];
	if (!found)
	{
		// The destination node doesn't exist in the database.
		return 0;
	}
	
	NSUInteger edgeCount = 0;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	//
	// Note: This specific case is easy, because we can do a direct lookup using the srcRowid.
	//       And if there's an in-memory list, then this is the complete list.
	
	NSMutableArray *changedEdges = [relationshipConnection->changes objectForKey:@(srcRowid)];
	if (changedEdges)
	{
		for (YapDatabaseRelationshipEdge *edge in changedEdges)
		{
			if (name && ![name isEqualToString:edge->name])
			{
				continue;
			}
			
			if (![dstKey isEqualToString:edge->destinationKey] ||
			    ![dstCollection isEqualToString:edge->destinationCollection])
			{
				continue;
			}
			
			edgeCount++;
		}
		
		return edgeCount;
	}
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement;
	YapDatabaseString _name;
	
	if (name)
	{
		statement = [relationshipConnection countForSrcDstNameStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "src" = ? AND "dst" = ? AND "name" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
		sqlite3_bind_int64(statement, 2, dstRowid);
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 3, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection countForSrcDstStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "src" = ? AND "dst" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
		sqlite3_bind_int64(statement, 2, dstRowid);
	}
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		edgeCount = (NSUInteger)sqlite3_column_int64(statement, 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ (%@): Error in statement: %d %s",
		            THIS_METHOD, [self registeredName],
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
	if (name) {
		FreeYapDatabaseString(&_name);
	}
	
	return edgeCount;
}

@end
