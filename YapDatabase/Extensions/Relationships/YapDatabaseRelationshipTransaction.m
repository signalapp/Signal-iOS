#import "YapDatabaseRelationshipTransaction.h"
#import "YapDatabaseRelationshipPrivate.h"
#import "YapDatabaseRelationshipEdgePrivate.h"
#import "YapDatabasePrivate.h"
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

/**
 * Declare that this class implements YapDatabaseExtensionTransaction_Hooks protocol.
 * This is done privately, as the protocol is internal.
**/
@interface YapDatabaseRelationshipTransaction () <YapDatabaseExtensionTransaction_Hooks>
@end


@implementation YapDatabaseRelationshipTransaction

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
		
		if (givenEdges)
		{
			NSMutableArray *edges = [NSMutableArray arrayWithCapacity:[givenEdges count]];
			
			for (YapDatabaseRelationshipEdge *edge in givenEdges)
			{
				[edges addObject:[edge copyWithSourceKey:key collection:collection rowid:rowid]];
			}
			
			[relationshipConnection->changes setObject:edges forKey:@(rowid)];
		}
	}];
	
//	[self flush]; // Todo...
	
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
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSMutableArray *)fetchExistingEdgesWithSource:(int64_t)srcRowid
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [relationshipConnection enumerateForSrcStatement];
	if (statement == NULL)
		return nil;
	
	NSMutableArray *edges = nil;
	
	// SELECT "rowid", "name", "dst", "rules" FROM "tableName" WHERE "src" = ?;
	
	sqlite3_bind_int64(statement, 1, srcRowid);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		edges = [NSMutableArray array];
		
		do
		{
			int64_t edgeRowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text = sqlite3_column_text(statement, 1);
			int textSize = sqlite3_column_bytes(statement, 1);
			
			NSString *name = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			int64_t dstRowid = sqlite3_column_int64(statement, 2);
			
			int rules = sqlite3_column_int(statement, 3);
			
			YapDatabaseRelationshipEdge *edge =
			  [[YapDatabaseRelationshipEdge alloc] initWithRowid:edgeRowid
			                                                name:name
			                                                 src:srcRowid
			                                                 dst:dstRowid
			                                               rules:rules];
			
			[edges addObject:edge];
			
		} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ (%@): Error executing statement: %d %s",
					THIS_METHOD, [self registeredName],
					status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	return edges;
}

/**
 * This method merges a new set of edges with an old set.
 * 
 * That is, it is given a set of edges from an object that was recently inserted or updated in the database.
 * And now we need to compare this set to what already exists.
 * If there are changes, then we need to mark any edges that need to be inserted/updated/deleted.
 * 
 * @param newEdges
 *   This array comes from an object that was inserted/updated in the database.
 *   So each edge will only contain public ivars,
 *   and will be missing private ivars such as destinationRowid.
 *
 * @param srcRowid
 *   The sourceRowid of every edge in the given array.
 *   Note that the given array may be empty or nil.
**/
- (void)mergeEdges:(NSMutableArray *)newEdges forSrc:(int64_t)srcRowid
{
	NSNumber *srcNumber = @(srcRowid);
	
	NSMutableArray *oldEdges = [relationshipConnection->changes objectForKey:srcNumber];
	if (oldEdges == nil)
	{
		oldEdges = [self fetchExistingEdgesWithSource:srcRowid];
	}
	
	if ([oldEdges count] == 0)
	{
		// No merge necessary
		
		[relationshipConnection->changes setObject:newEdges forKey:srcNumber];
		return;
	}
	
	// Step 1 :
	//
	// Enumerate the new edges, and check to see if they match an existing edge.
	// If so the mark the edgeAction as none (meaning doesn't need to be written to database).
	// Otherwise mark the edgeAction as insert.
	
	for (YapDatabaseRelationshipEdge *newEdge in newEdges)
	{
		YapDatabaseRelationshipEdge *matchingOldEdge = nil;
		
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *oldEdge in oldEdges)
		{
			// Do they match
			
			BOOL match = NO;
			
			if ([newEdge->name isEqualToString:oldEdge->name])
			{
				// The newEdge will only have dstKey & dstCollection.
				// The newEdge will be missing dstRowid.
				// However...
				// The oldEdge may only have dstRowid.
				// The oldEdge may be missing dstKey & dstCollection.
				
				if (oldEdge->destinationKey == nil && (oldEdge->nodeAction & YDB_NodeActionDestinationDeleted) == 0)
				{
					NSString *dstKey = nil;
					NSString *dstCollection = nil;
					
					BOOL found = [databaseTransaction getKey:&dstKey
					                              collection:&dstCollection
					                                forRowid:oldEdge->destinationRowid];
					
					if (found)
					{
						oldEdge->destinationKey = dstKey;
						oldEdge->destinationCollection = dstCollection;
					}
					else
					{
						// The destination node has been deleted from database.
						// Mark as such so we don't attempt collection/key lookup again.
						oldEdge->nodeAction |= YDB_NodeActionDestinationDeleted;
					}
				}
				
				match = [newEdge->destinationKey isEqualToString:oldEdge->destinationKey] &&
				        [newEdge->destinationCollection isEqualToString:oldEdge->destinationCollection];
			}
			
			if (match)
			{
				matchingOldEdge = oldEdge;
				
				[oldEdges removeObjectAtIndex:i];
				break;
			}
			else
			{
				i++;
			}
		}
		
		if (matchingOldEdge == nil)
		{
			// This is a NEW edge.
			// It needs to be inserted into the database.
			
			newEdge->edgeAction = YDB_EdgeActionInsert;
			newEdge->nodeAction = YDB_NodeActionNone;
		}
		else
		{
			// This new edges matches an existing one.
			// More precisely, it matches an existing that either:
			//
			// - existed in the database
			// - or was scheduled to be inserted/updated/deleted in the database
			//
			// Check closely to s
			
			newEdge->edgeRowid = matchingOldEdge->edgeRowid;
			newEdge->destinationRowid = matchingOldEdge->destinationRowid;
			
			if (matchingOldEdge->nodeAction == YDB_EdgeActionNone)
			{
				if (newEdge->nodeDeleteRules != matchingOldEdge->nodeDeleteRules)
				{
					// The nodeDeleteRules changed
					newEdge->nodeAction = YDB_EdgeActionUpdate;
				}
				else
				{
					// Nothing changed
					newEdge->nodeAction = YDB_EdgeActionNone;
				}
			}
			else // if (matchingOldEdge->nodeAction == YDB_EdgeActionInsert ||
			     //     matchingOldEdge->nodeAction == YDB_EdgeActionUpdate ||
			     //     matchingOldEdge->nodeAction == YDB_EdgeActionDelete)
			{
				newEdge->nodeAction = YDB_EdgeActionInsert;
			}
		}
	}
	
	// Step 2 :
	//
	// If there's anything remaining in the old edges array,
	// then these edges have been removed from the node.
	// So we need to mark all these edges for removal from the database.
	
	for (YapDatabaseRelationshipEdge *oldEdge in oldEdges)
	{
		oldEdge->edgeAction = YDB_EdgeActionDelete;
		oldEdge->nodeAction = YDB_NodeActionSourceDeleted;
		
		[newEdges addObject:oldEdge];
	}
	
	// Step 3 :
	//
	// Store merged list in changes dictionary.
	
	[relationshipConnection->changes setObject:newEdges forKey:srcNumber];
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
	
	[relationshipConnection->cache removeAllObjects];
	
	[relationshipConnection->changes removeAllObjects];
	[relationshipConnection->deletedRowids removeAllObjects];
}

- (void)flush
{
	
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
	
	// Step 1:
	//
	// Enumerate the pending dictionary.
	// For every edge, we need to fill in any missing dstRowid.
	// Ultimately we'll figure out the following:
	// - srcDeleted (based on deletedRowids set)
	// - dstDeleted (based on deletedRowids set)
	// - dstMissing (based on failed lookup)
	//
	// Every edge has the following properties
	// - edgeAction (insert, delete, update, none)
	// - nodeAction (srcDeleted, dstDeleted, dstMissing)
	//
	// On the first pass we don't process deletes.
	// We only insert or update edges.
	//
	// Step 2:
	//
	// As for deletes, there two scenarios:
	// - Edge was deleted (src object updated, and specified new set of edges)
	// - Node was deleted (src or dst)
	//
	// If an edge is deleted, this is treated the same as the src being deleted.
	// Since it was the src that manually deleted the edge by returning a different set of edges.
	//
	// Note: Since this extension alters the database, we may need to run this extension before any others.
	//
	// 
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseExtensionTransaction_Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleInsertObject:(id)object
                    forKey:(NSString *)key
              inCollection:(NSString *)collection
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Request edges from object
	
	NSArray *givenEdges = nil;
	
	if ([object conformsToProtocol:@protocol(YapDatabaseRelationshipNode)])
	{
		givenEdges = [object yapDatabaseRelationshipEdges];
	}
	
	// Make copies, and fill in missing src information
	
	NSMutableArray *edges = nil;
	
	if (givenEdges)
	{
		edges = [NSMutableArray arrayWithCapacity:[givenEdges count]];
		
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
	// So to be safe, we'll check the deletedRowids set.
	
	NSNumber *rowidNumber = @(rowid);
	
	if ([relationshipConnection->deletedRowids containsObject:rowidNumber])
	{
		[relationshipConnection->deletedRowids removeObject:rowidNumber];
		[self mergeEdges:edges forSrc:rowid];
	}
	else if (edges)
	{
		[relationshipConnection->changes setObject:edges forKey:rowidNumber];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleUpdateObject:(id)object
                    forKey:(NSString *)key
              inCollection:(NSString *)collection
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Pseudocode
	//
	// - Request edges.
	// - Then we need to compare the new set of edges to the old edges.
	// - So first we fetch all existing edges where src matches given rowid.
	// - Before going to the database, we may need to check pending orphans/inserts.
	// - Then we compare the two sets using a double for loop.
	// - Note: May need to consider how to handle duplicates in a single array.
	//
	// - If a new edge matches an existing edge, we can ignore it
	// - If an edge is new, add to pending orphans/inserts.
	// - If an edge is updated (nodeDeleteRules changed), then add to pending updates.
	//
	// - We should have removed anything from the mutable existing array of edges that was a match.
	// - These remaining edges represent edges that need to be removed.
	// - So add them to the pending deletes array.
	//
	// Thoughts:
	//
	// Rather than having seperate insert/delete/updates, we may want to use some other kind of flag to indicate
	// the action that needs to be taken. This could be integrated into YapDatabaseRelationshipEdge object (private).
	//
	// Also, we may store all these pending edges in a dictionary, with the YapCollectionKey as the key.
	// Or, we use NSNumber as the key. Which would be faster in 64-bit architecture.
	
	NSArray *givenEdges = nil;
	
	if ([object conformsToProtocol:@protocol(YapDatabaseRelationshipNode)])
	{
		givenEdges = [object yapDatabaseRelationshipEdges];
	}
	
	NSMutableArray *edges = nil;
	
	if (givenEdges)
	{
		edges = [NSMutableArray arrayWithCapacity:[givenEdges count]];
		
		for (YapDatabaseRelationshipEdge *edge in givenEdges)
		{
			[edges addObject:[edge copyWithSourceKey:key collection:collection rowid:rowid]];
		}
	}
	
	[self mergeEdges:edges forSrc:rowid];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleUpdateMetadata:(id)metadata
                      forKey:(NSString *)key
                inCollection:(NSString *)collection
                   withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Nothing to do in this extension for metadata
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleTouchObjectForKey:(NSString *)key inCollection:(NSString *)collection withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Nothing to do in this extension for touches
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleTouchMetadataForKey:(NSString *)key inCollection:(NSString *)collection withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Nothing to do in this extension for touches
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectForKey:(NSString *)key inCollection:(NSString *)collection withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	NSNumber *srcNumber = @(rowid);
	
	[relationshipConnection->changes removeObjectForKey:srcNumber];
	[relationshipConnection->deletedRowids addObject:srcNumber];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	YDBLogAutoTrace();
	
	for (NSNumber *srcNumber in rowids)
	{
		[relationshipConnection->changes removeObjectForKey:srcNumber];
		[relationshipConnection->deletedRowids addObject:srcNumber];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveAllObjectsInAllCollections
{
	YDBLogAutoTrace();
	
	[self removeAllEdges];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API - Groups
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)enumerateEdgesWithName:(NSString *)name
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	// Todo...
}

- (void)enumerateEdgesWithName:(NSString *)name
                     sourceKey:(NSString *)dstKey
                    collection:(NSString *)dstCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	// Todo...
}

- (void)enumerateEdgesWithName:(NSString *)name
                destinationKey:(NSString *)dstKey
                    collection:(NSString *)dstCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	// Todo...
}

- (void)enumerateEdgesWithName:(NSString *)name
                     sourceKey:(NSString *)dstKey
                    collection:(NSString *)dstCollection
                destinationKey:(NSString *)srcKey
                    collection:(NSString *)srcCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	// Todo...
}

@end
