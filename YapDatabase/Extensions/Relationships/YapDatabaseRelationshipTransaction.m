#import "YapDatabaseRelationshipTransaction.h"
#import "YapDatabaseRelationshipPrivate.h"
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
	
	return NO;
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
	// Todo...
	
	return NO;
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
	// Todo...
	
	return NO;
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
	
	// Pseudocode:
	//
	// - Request edges.
	// - Make mutable copy (copying each edge node).
	// - Add to pending dictionary.
	// - Add to rowidCache.
	// - Remove rowid from deleted rowid's set.
	//
	// Questions:
	//
	// Perhaps there is a better way to enumerate objects in memory, for the purpose of filling in the missing rowid.
	// We could, instead, keep a seperate hashtable?
	//
	// Remember that we're trying to store answers, and questions.
	// Could use a YapCollectionKey as the key, and an array of edges as the value.
	
	NSArray *edges = nil;
	
	if ([object conformsToProtocol:@protocol(YapDatabaseRelationshipNode)])
	{
		edges = [object yapDatabaseRelationshipEdges];
	}
	
	if (edges)
	{
		
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
	
	NSArray *edges = nil;
	
	if ([object conformsToProtocol:@protocol(YapDatabaseRelationshipNode)])
	{
		edges = [object yapDatabaseRelationshipEdges];
	}
	
	// ...
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
	
	// Pseudocode
	//
	// - Add to set of deleted rowid's
	//
	// We'll process this set in the preCommit hook.
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	YDBLogAutoTrace();
	
	NSParameterAssert(collection != nil);
	
	// Todo...
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveAllObjectsInAllCollections
{
	YDBLogAutoTrace();
	
	// Dump the entire relationships table.
	// Dump all pending pools.
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API - Groups
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)enumerateEdgesWithName:(NSString *)name
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
//	[self enumerateEdgesWithName:name
//	              destinationKey:nil
//	                  collection:nil
//	                   sourceKey:nil
//	                  collection:nil
//	                  usingBlock:block];
}

- (void)enumerateEdgesWithName:(NSString *)name
                destinationKey:(NSString *)dstKey
                    collection:(NSString *)dstCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
//	[self enumerateEdgesWithName:name
//	              destinationKey:dstKey
//	                  collection:dstCollection
//	                   sourceKey:nil
//	                  collection:nil
//	                  usingBlock:block];
}

- (void)enumerateEdgesWithName:(NSString *)name
                destinationKey:(NSString *)dstKey
                    collection:(NSString *)dstCollection
                     sourceKey:(NSString *)srcKey
                    collection:(NSString *)srcCollection
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	// Todo...
}

@end
