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
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)

/**
 * This method is used to merge internal info between two matching edges.
 * For example:
 *
 * - edge1 is an edge found during enumeration of the database.
 *   As such, it only contains rowids, and is missing public facing collectionKey info.
 * 
 * - edge2 is an edge the user gave us (a changedEdge scheduled to be written to disk).
 *   As such, it only contains public facing collectionKey info, and is missing internal rowid info.
 *
 * This method merges the info between the two, so both edges have all possible information.
**/
static void MergeInfoBetweenMatchingEdges(YapDatabaseRelationshipEdge *edge1, YapDatabaseRelationshipEdge *edge2)
{
	// edgeRowid
	
	if (edge1->state & YDB_EdgeState_HasEdgeRowid)
	{
		if (!(edge2->state & YDB_EdgeState_HasEdgeRowid))
		{
			edge2->edgeRowid = edge1->edgeRowid;
			edge2->state |= YDB_EdgeState_HasEdgeRowid;
		}
	}
	else if (edge2->state & YDB_EdgeState_HasEdgeRowid)
	{
		edge1->edgeRowid = edge2->edgeRowid;
		edge1->state |= YDB_EdgeState_HasEdgeRowid;
	}
	
	// sourceKey & sourceCollection
	
	if (edge1->sourceKey)
	{
		if (!(edge2->sourceKey))
		{
			edge2->sourceKey        = edge1->sourceKey;
			edge2->sourceCollection = edge1->sourceCollection;
		}
	}
	else if (edge2->sourceKey)
	{
		edge1->sourceKey        = edge2->sourceKey;
		edge1->sourceCollection = edge2->sourceCollection;
	}
	
	// sourceRowid
	
	if (edge1->state & YDB_EdgeState_HasSourceRowid)
	{
		if (!(edge2->state & YDB_EdgeState_HasSourceRowid))
		{
			edge2->sourceRowid = edge1->sourceRowid;
			edge2->state |= YDB_EdgeState_HasSourceRowid;
		}
	}
	else if (edge2->state & YDB_EdgeState_HasSourceRowid)
	{
		edge1->sourceRowid = edge2->sourceRowid;
		edge1->state |= YDB_EdgeState_HasSourceRowid;
	}
	
	// destinationKey & destinationCollection
	
	if (edge1->destinationKey)
	{
		if (!(edge2->destinationKey))
		{
			edge2->destinationKey        = edge1->destinationKey;
			edge2->destinationCollection = edge1->destinationCollection;
		}
	}
	else if (edge2->destinationKey)
	{
		edge1->destinationKey        = edge2->destinationKey;
		edge1->destinationCollection = edge2->destinationCollection;
	}
	
	// destinationRowid
	
	if (edge1->state & YDB_EdgeState_HasDestinationRowid)
	{
		if (!(edge2->state & YDB_EdgeState_HasDestinationRowid))
		{
			edge2->destinationRowid = edge1->destinationRowid;
			edge2->state |= YDB_EdgeState_HasDestinationRowid;
		}
	}
	else if (edge2->state & YDB_EdgeState_HasDestinationRowid)
	{
		edge1->destinationRowid = edge2->destinationRowid;
		edge1->state |= YDB_EdgeState_HasDestinationRowid;
	}
}

NS_INLINE BOOL URLMatchesURL(NSURL *url1, NSURL *url2)
{
	NSString *str1 = [url1 absoluteString];
	NSString *str2 = [url2 absoluteString];
	
	if (!str1 || !str2) return NO;
	
	if ([str1 isEqualToString:str2])
	{
		// Common case
		return YES;
	}
	
	NSError *error = nil;
	id iNode1 = nil;
	id iNode2 = nil;
 
	[url1 getResourceValue:&iNode1 forKey:NSURLFileResourceIdentifierKey error:&error];
	[url2 getResourceValue:&iNode2 forKey:NSURLFileResourceIdentifierKey error:&error];
 
	return [iNode1 isEqual:iNode2];
}

@implementation YapDatabaseRelationshipTransaction
{
	BOOL isFlushing;
}

- (id)initWithParentConnection:(YapDatabaseRelationshipConnection *)inParentConnection
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
 * This method is called to create any necessary tables (if needed),
 * as well as populate the table by enumerating over the existing rows in the database.
 * 
 * Return YES if completed successfully, or if already prepared.
 * Return NO if some kind of error occured.
**/
- (BOOL)createIfNeeded
{
	// Check classVersion (the internal version number of the extension implementation)
	
	int oldClassVersion = 0;
	BOOL hasOldClassVersion = [self getIntValue:&oldClassVersion forExtensionKey:ext_key_classVersion persistent:YES];
	
	int classVersion = YAP_DATABASE_RELATIONSHIP_CLASS_VERSION;
	
	// Create or migrate as needed
	
	if (oldClassVersion == 3)
	{
		[self migrateTable_3_4];
		
		[self setIntValue:classVersion forExtensionKey:ext_key_classVersion persistent:YES];
		
		// continue like normal after migrating
	}
	else if (oldClassVersion != classVersion)
	{
		// First time registration (or at least for this version)
		
		if (hasOldClassVersion) {
			
			// In version 2 we added the 'manual' column to support manual edge management.
			// In version 3 we changed the column affinity of the 'dst' column.
			// In version 4 we switched to NSURL-based destinations.
			
			if (![self dropTable]) return NO;
		}
		
		if (![self createTable]) return NO;
		if (![self populateTable]) return NO;
		
		[self setIntValue:classVersion forExtensionKey:ext_key_classVersion persistent:YES];
		
		NSString *versionTag = parentConnection->parent->versionTag;
		[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:YES];
		
		return YES;
	}
	
	// Check user-supplied config version.
	// If the version gets changed, this indicates that YapDatabaseRelationshipNode objects changed.
	// In other words, their yapDatabaseRelationshipEdges methods were channged.
	// So we'll need to re-populate the database (at least the protocol portion of it).
	
	NSString *versionTag = parentConnection->parent->versionTag;
	
	NSString *oldVersionTag = [self stringValueForExtensionKey:ext_key_versionTag persistent:YES];
	
	BOOL hasOldVersion_deprecated = NO;
	if (oldVersionTag == nil)
	{
		int oldVersion_deprecated = 0;
		hasOldVersion_deprecated = [self getIntValue:&oldVersion_deprecated
		                             forExtensionKey:ext_key_version_deprecated
		                                  persistent:YES];
		
		if (hasOldVersion_deprecated)
		{
			oldVersionTag = [NSString stringWithFormat:@"%d", oldVersion_deprecated];
		}
	}
	
	if (![oldVersionTag isEqualToString:versionTag])
	{
		if (![self populateTable]) return NO;
		
		[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:YES];
		
		if (hasOldVersion_deprecated)
			[self removeValueForExtensionKey:ext_key_version_deprecated persistent:YES];
	}
	else if (hasOldVersion_deprecated)
	{
		[self removeValueForExtensionKey:ext_key_version_deprecated persistent:YES];
		[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:YES];
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
		YDBLogError(@"%@ - Failed dropping relationship table (%@): %d %s",
		            THIS_METHOD, dropTable, status, sqlite3_errmsg(db));
		return NO;
	}
	
	return YES;
}

/**
 * Migrate table from v3 to v4
**/
- (BOOL)migrateTable_3_4
{
	sqlite3 *db = databaseTransaction->connection->db;
	YapDatabaseRelationshipMigration migration = parentConnection->parent->options.migration;
	
	NSString *tableName = [self tableName];
	NSMutableArray *replacements = [NSMutableArray array];
	
	{ // Scan the table for rows where the dst column is non-integer (text or blob)
	
		sqlite3_stmt *statement = NULL;
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\", \"src\", \"dst\", \"rules\", \"manual\""
		  @" FROM \"%@\" WHERE \"dst\" > %lld;", tableName, INT64_MAX];
		
		const int column_idx_rowid  = SQLITE_COLUMN_START + 0;
		const int column_idx_name   = SQLITE_COLUMN_START + 1;
		const int column_idx_src    = SQLITE_COLUMN_START + 2;
		const int column_idx_dst    = SQLITE_COLUMN_START + 3;
		const int column_idx_rules  = SQLITE_COLUMN_START + 4;
		const int column_idx_manual = SQLITE_COLUMN_START + 5;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			return NO;
		}
		
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			const unsigned char *_name = sqlite3_column_text(statement, column_idx_name);
			int _nameSize = sqlite3_column_bytes(statement, column_idx_name);
			
			NSString *name = [[NSString alloc] initWithBytes:_name length:_nameSize encoding:NSUTF8StringEncoding];
			
			int64_t srcRowid = sqlite3_column_int64(statement, column_idx_src);
			
			NSString *dstFilePath = nil;
			NSData *dstFilePathData = nil;
			
			int column_type = sqlite3_column_type(statement, column_idx_dst);
			if (column_type == SQLITE_TEXT)
			{
				const unsigned char *dst = sqlite3_column_text(statement, column_idx_dst);
				int dstSize = sqlite3_column_bytes(statement, column_idx_dst);
				
				dstFilePath = [[NSString alloc] initWithBytes:dst length:dstSize encoding:NSUTF8StringEncoding];
			}
			else if (column_type == SQLITE_BLOB)
			{
				const void *dst = sqlite3_column_blob(statement, column_idx_dst);
				int dstSize = sqlite3_column_bytes(statement, column_idx_dst);
				
				dstFilePathData = [NSData dataWithBytesNoCopy:(void *)dst length:dstSize freeWhenDone:NO];
			}
			
			int rules = sqlite3_column_int(statement, column_idx_rules);
			BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
			
			YapDatabaseRelationshipEdge *edge =
			  [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
			                                                    name:name
			                                                srcRowid:srcRowid
			                                                dstRowid:0
			                                                 dstData:nil
			                                                   rules:rules
			                                                  manual:manual];
			
			NSURL *url = migration(dstFilePath, dstFilePathData);
			
			edge->destinationFileURL = url;
			
			edge->state |= YDB_EdgeState_DestinationFileURL;
			edge->state |= YDB_EdgeState_HasDestinationRowid;
			edge->state |= YDB_EdgeState_HasDestinationFileURL;
			
			[replacements addObject:edge];
		}
		
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ - Error executing enum statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		sqlite3_finalize(statement);
	}
	
	// Modify the table with replacements
	
	if (replacements.count > 0)
	{
		sqlite3_stmt *statement = NULL;
		NSString *string = [NSString stringWithFormat:
		  @"UPDATE \"%@\" SET \"dst\" = ? WHERE \"rowid\" = ?;", tableName];
		
		int bind_idx_dst   = SQLITE_BIND_START + 0;
		int bind_idx_rowid = SQLITE_BIND_START + 1;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			return NO;
		}
		
		YapDatabaseRelationshipFileURLSerializer fileURLSerializer =
		  parentConnection->parent->options.fileURLSerializer;
		
		for (YapDatabaseRelationshipEdge *edge in replacements)
		{
			__attribute__((objc_precise_lifetime)) NSData *dstBlob = nil;
			
			if (edge->destinationFileURL) {
				dstBlob = fileURLSerializer(edge);
			}
			
			sqlite3_bind_blob(statement, bind_idx_dst, dstBlob.bytes, (int)dstBlob.length, SQLITE_STATIC);
			sqlite3_bind_int64(statement, bind_idx_rowid, edge->edgeRowid);
			
			status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"%@ - Error executing modify statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
		}
		
		sqlite3_finalize(statement);
	}
	
	return YES;
}

/**
 * Runs the sqlite instructions to create the proper table & indexes.
**/
- (BOOL)createTable
{
	sqlite3 *db = databaseTransaction->connection->db;
	NSString *tableName = [self tableName];
	
	YDBLogVerbose(@"Creating relationship table for registeredName(%@): %@", [self registeredName], tableName);
	
	NSString *createTable = [NSString stringWithFormat:
	  @"CREATE TABLE IF NOT EXISTS \"%@\""
	  @" (\"rowid\" INTEGER PRIMARY KEY,"
	  @"  \"name\" CHAR NOT NULL,"
	  @"  \"src\" INTEGER NOT NULL,"
	  @"  \"dst\" BLOB NOT NULL," // affinity==NONE (to better support rowid's or filepath's without type casting)
	  @"  \"rules\" INTEGER,"
	  @"  \"manual\" INTEGER"
	  @" );", tableName];
	
	// Discussion on index optimizations:
	//
	// https://github.com/yapstudios/YapDatabase/pull/224
	
	NSString *createSrcNameIndex = [NSString stringWithFormat:
	  @"CREATE INDEX IF NOT EXISTS \"src_name\" ON \"%@\" (\"src\", \"name\");", tableName];
	
	NSString *createDstNameIndex = [NSString stringWithFormat:
	  @"CREATE INDEX IF NOT EXISTS \"dst_name\" ON \"%@\" (\"dst\", \"name\");", tableName];
	
	int status;
	
	status = sqlite3_exec(db, [createTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating table (%@): %d %s",
		            THIS_METHOD, createTable, status, sqlite3_errmsg(db));
		return NO;
	}
	
	status = sqlite3_exec(db, [createSrcNameIndex UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating src_name index (%@): %d %s",
		            THIS_METHOD, createSrcNameIndex, status, sqlite3_errmsg(db));
		return NO;
	}
	
	status = sqlite3_exec(db, [createDstNameIndex UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating dst_name index (%@): %d %s",
		            THIS_METHOD, createDstNameIndex, status, sqlite3_errmsg(db));
		return NO;
	}
	
	return YES;
}

/**
 * Enumerates the rows in the database and look for objects implementing the YapDatabaseRelationshipNode protocol.
 * Query these objects, and populate the table accordingly.
**/
- (BOOL)populateTable
{
	// Remove all protocol edges from the database
	
	[self removeAllProtocolEdges];
	
	// Skip enumeration step if YapDatabaseRelationshipNode protocol is disabled
	
	if (parentConnection->parent->options->disableYapDatabaseRelationshipNodeProtocol)
	{
		return YES;
	}
	
	// Enumerate the existing rows in the database and populate the view
	
	void (^ProcessRow)(int64_t rowid, NSString *collection, NSString *key, id object);
	ProcessRow = ^(int64_t rowid, NSString *collection, NSString *key, id object){
		
		NSArray *givenEdges = nil;
		
	//	if ([object conformsToProtocol:@protocol(YapDatabaseRelationshipNode)])
		if ([object respondsToSelector:@selector(yapDatabaseRelationshipEdges)])
		{
			givenEdges = [object yapDatabaseRelationshipEdges];
		}
		
		if ([givenEdges count] > 0)
		{
			NSMutableArray *edges = [NSMutableArray arrayWithCapacity:[givenEdges count]];
			
			for (YapDatabaseRelationshipEdge *edge in givenEdges)
			{
				YapDatabaseRelationshipEdge *cleanEdge = [edge copyWithSourceKey:key collection:collection rowid:rowid];
				cleanEdge->isManualEdge = NO; // Force proper value
				
				[edges addObject:cleanEdge];
			}
			
			[parentConnection->protocolChanges setObject:edges forKey:@(rowid)];
		}
	};
	
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections =
	    parentConnection->parent->options->allowedCollections;
	
	if (allowedCollections)
	{
		[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *outerStop) {
			
			if ([allowedCollections isAllowed:collection])
			{
				[databaseTransaction _enumerateKeysAndObjectsInCollection:collection usingBlock:
				    ^(int64_t rowid, NSString *key, id object, BOOL __unused *innerStop)
				{
					ProcessRow(rowid, collection, key, object);
				}];
			}
		}];
	}
	else
	{
		[databaseTransaction _enumerateKeysAndObjectsInAllCollectionsUsingBlock:
		   	^(int64_t rowid, NSString *collection, NSString *key, id object, BOOL __unused *stop)
		{
			ProcessRow(rowid, collection, key, object);
		}];
	}
	
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
#pragma mark Edge Lookup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Because edges can be in so many different states,
 * it's important to always use these designated lookup routines to fetch edge information &
 * update the edge state flags properly.
**/

- (BOOL)lookupEdgeSourceCollectionKey:(YapDatabaseRelationshipEdge *)edge
{
	NSParameterAssert(edge != nil);
	
	BOOL found = YES;
	
	if (edge->sourceKey == nil)
	{
		YapCollectionKey *src = [databaseTransaction collectionKeyForRowid:edge->sourceRowid];
		if (src)
		{
			edge->sourceKey = src.key;
			edge->sourceCollection = src.collection;
		}
		else
		{
			src = [parentConnection->deletedInfo objectForKey:@(edge->sourceRowid)];
			if (src)
			{
				edge->sourceKey = src.key;
				edge->sourceCollection = src.collection;
			}
			else
			{
				found = NO;
			}
		}
	}
	
	return found;
}

- (BOOL)lookupEdgeDestinationCollectionKey:(YapDatabaseRelationshipEdge *)edge
{
	NSParameterAssert(edge != nil);
	
	BOOL found = YES;
	
	if (edge->destinationKey == nil)
	{
		YapCollectionKey *dst = [databaseTransaction collectionKeyForRowid:edge->destinationRowid];
		if (dst)
		{
			edge->destinationKey = dst.key;
			edge->destinationCollection = dst.collection;
		}
		else
		{
			dst = [parentConnection->deletedInfo objectForKey:@(edge->destinationRowid)];
			if (dst)
			{
				edge->destinationKey = dst.key;
				edge->destinationCollection = dst.collection;
			}
			else
			{
				found = NO;
			}
		}
	}
	
	return found;
}

- (BOOL)lookupEdgeSourceRowid:(YapDatabaseRelationshipEdge *)edge isDeleted:(BOOL *)isDeletedPtr
{
	NSParameterAssert(edge != nil);
	
	BOOL found = YES;
	BOOL isDeleted = NO;
	
	if (!(edge->state & YDB_EdgeState_HasSourceRowid))
	{
		int64_t srcRowid = 0;
		
		found = [databaseTransaction getRowid:&srcRowid
		                               forKey:edge->sourceKey
		                         inCollection:edge->sourceCollection];
		
		if (found)
		{
			edge->sourceRowid = srcRowid;
			edge->state |= YDB_EdgeState_HasSourceRowid;
		}
		else
		{
			NSNumber *srcRowidNumber = [self rowidNumberForDeletedKey:edge->sourceKey
			                                             inCollection:edge->sourceCollection];
			
			if (srcRowidNumber)
			{
				edge->sourceRowid = srcRowidNumber.longLongValue;
				edge->state |= YDB_EdgeState_HasSourceRowid;
				
				found = YES; // getRowid line had set to NO
				isDeleted = YES;
			}
		}
	}
	else if (isDeletedPtr)
	{
		isDeleted = [parentConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)];
	}
	
	if (isDeletedPtr) *isDeletedPtr = isDeleted;
	return found;
}

- (BOOL)lookupEdgeDestinationRowid:(YapDatabaseRelationshipEdge *)edge isDeleted:(BOOL *)isDeletedPtr
{
	NSParameterAssert(edge != nil);
	
	BOOL found = YES;
	BOOL isDeleted = NO;
	
	if (!(edge->state & YDB_EdgeState_DestinationFileURL))
	{
		if (!(edge->state & YDB_EdgeState_HasDestinationRowid))
		{
			int64_t dstRowid = 0;
			
			found = [databaseTransaction getRowid:&dstRowid
			                               forKey:edge->destinationKey
			                         inCollection:edge->destinationCollection];
			
			if (found)
			{
				edge->destinationRowid = dstRowid;
				edge->state |= YDB_EdgeState_HasDestinationRowid;
			}
			else
			{
				NSNumber *dstRowidNumber = [self rowidNumberForDeletedKey:edge->destinationKey
				                                             inCollection:edge->destinationCollection];
				
				if (dstRowidNumber)
				{
					edge->destinationRowid = dstRowidNumber.longLongValue;
					edge->state |= YDB_EdgeState_HasDestinationRowid;
					
					found = YES; // getRowid line had set to NO
					isDeleted = YES;
				}
			}
		}
		else if (isDeletedPtr)
		{
			isDeleted = [parentConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)];
		}
	}
	
	if (isDeletedPtr) *isDeletedPtr = isDeleted;
	return found;
}

- (BOOL)lookupEdgeDestinationFileURL:(YapDatabaseRelationshipEdge *)edge
{
	NSParameterAssert(edge != nil);
	
	if ((edge->state & YDB_EdgeState_DestinationFileURL) &&
	   !(edge->state & YDB_EdgeState_HasDestinationFileURL))
	{
		NSURL *dstFileURL = nil;
		
		if (edge->destinationFileURLData) {
			dstFileURL = parentConnection->parent->options.fileURLDeserializer(edge, edge->destinationFileURLData);
		}
		
		edge->destinationFileURL = dstFileURL;
		edge->destinationFileURLData = nil;
		edge->state |= YDB_EdgeState_HasDestinationFileURL;
	}
	
	return (edge->destinationFileURL != nil);
}

- (BOOL)isEdgeSourceDeleted:(YapDatabaseRelationshipEdge *)edge
{
	NSParameterAssert(edge != nil);
	
	if (edge->state & YDB_EdgeState_HasSourceRowid)
	{
		return [parentConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)];
	}
	else
	{
		BOOL srcDeleted = NO;
		[self lookupEdgeSourceRowid:edge isDeleted:&srcDeleted];
		
		return srcDeleted;
	}
}

- (BOOL)isEdgeDestinationDeleted:(YapDatabaseRelationshipEdge *)edge
{
	NSParameterAssert(edge != nil);
	
	if (edge->state & YDB_EdgeState_DestinationFileURL)
	{
		return NO;
	}
	
	if (edge->state & YDB_EdgeState_HasDestinationRowid)
	{
		return [parentConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)];
	}
	else
	{
		BOOL dstDeleted = NO;
		[self lookupEdgeDestinationRowid:edge isDeleted:&dstDeleted];
		
		return dstDeleted;
	}
}

/**
 * Ensures the edge has both sourceRowid & sourceKey/sourceCollection
**/
- (void)lookupEdgeSource:(YapDatabaseRelationshipEdge *)edge
{
	if (edge->sourceKey)
	{
		if (!(edge->state & YDB_EdgeState_HasSourceRowid))
		{
			[self lookupEdgeSourceRowid:edge isDeleted:NULL];
		}
	}
	else
	{
		[self lookupEdgeSourceCollectionKey:edge];
	}
}

/**
 * Ensures the edge has both destinationRowid & destinationKey/destinationCollection
**/
- (void)lookupEdgeDestination:(YapDatabaseRelationshipEdge *)edge
{
	if (edge->destinationKey)
	{
		if (!(edge->state & YDB_EdgeState_HasDestinationRowid))
		{
			[self lookupEdgeDestinationRowid:edge isDeleted:NULL];
		}
	}
	else
	{
		[self lookupEdgeDestinationCollectionKey:edge];
	}
}

- (void)lookupEdgePublicProperties:(YapDatabaseRelationshipEdge *)edge
{
	// Prepare node for presentation to the user
	
	if (edge->sourceKey == nil)
		[self lookupEdgeSourceCollectionKey:edge];
	
	if (edge->state & YDB_EdgeState_DestinationFileURL)
		[self lookupEdgeDestinationFileURL:edge];
	else
		[self lookupEdgeDestinationCollectionKey:edge];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Edge Comparison
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Compares the two edges to see if they have the same destination.
 * This method will only perform database lookups if needed.
**/
- (BOOL)edge:(YapDatabaseRelationshipEdge *)edge1 matchesSource:(YapDatabaseRelationshipEdge *)edge2
{
	NSParameterAssert(edge1 != nil);
	NSParameterAssert(edge2 != nil);
	
	// Pass 1 :
	// Try to use whatever information is available so we can avoid hitting the database when possible.
	
	if (edge1->state & YDB_EdgeState_HasSourceRowid)
	{
		if (edge2->state & YDB_EdgeState_HasSourceRowid)
		{
			return (edge1->sourceRowid == edge2->sourceRowid);
		}
	}
	
	if (edge1->sourceKey)
	{
		if (edge2->sourceKey)
		{
			return [edge1->sourceKey isEqualToString:edge2->sourceKey] &&
			       [edge1->sourceCollection isEqualToString:edge2->sourceCollection];
		}
	}
	
	// Optimization failed - fallback to database lookup(s)
	//
	// Looking up the rowid for an edge is generally more useful.
	// If an edge doesn't have a rowid, then it's likely a newly inserted/modified edge,
	// and the rowid lookup will be required in the near future anyway.
	
	if (!(edge1->state & YDB_EdgeState_HasSourceRowid))
	{
		[self lookupEdgeSourceRowid:edge1 isDeleted:NULL];
	}
	else if (!(edge2->state & YDB_EdgeState_HasSourceRowid))
	{
		[self lookupEdgeSourceRowid:edge2 isDeleted:NULL];
	}
	else if (edge1->sourceKey == nil)
	{
		[self lookupEdgeSourceCollectionKey:edge1];
	}
	else if (edge2->sourceKey == nil)
	{
		[self lookupEdgeSourceCollectionKey:edge2];
	}
	
	// Pass 2:
	
	if (edge1->state & YDB_EdgeState_HasSourceRowid)
	{
		if (edge2->state & YDB_EdgeState_HasSourceRowid)
		{
			return (edge1->sourceRowid == edge2->sourceRowid);
		}
	}
	
	if (edge1->sourceKey)
	{
		if (edge2->sourceKey)
		{
			return [edge1->sourceKey isEqualToString:edge2->sourceKey] &&
			       [edge1->sourceCollection isEqualToString:edge2->sourceCollection];
		}
	}
	
	return NO; // Looks like at least one of the edges is bad
}

/**
 * Compares the two edges to see if they have the same destination.
 * This method will only perform database lookups if needed.
**/
- (BOOL)edge:(YapDatabaseRelationshipEdge *)edge1 matchesDestination:(YapDatabaseRelationshipEdge *)edge2
{
	NSParameterAssert(edge1 != nil);
	NSParameterAssert(edge2 != nil);
	
	if (edge1->state & YDB_EdgeState_DestinationFileURL)
	{
		if (!(edge2->state & YDB_EdgeState_DestinationFileURL))
		{
			return NO;
		}
		
		if (!(edge1->state & YDB_EdgeState_HasDestinationFileURL))
			[self lookupEdgeDestinationFileURL:edge1];
		
		if (edge1->destinationFileURL == nil)
			return NO;
		
		if (!(edge2->state & YDB_EdgeState_HasDestinationFileURL))
			[self lookupEdgeDestinationFileURL:edge2];
		
		return URLMatchesURL(edge1->destinationFileURL, edge2->destinationFileURL);
	}
	else
	{
		if (edge2->state & YDB_EdgeState_DestinationFileURL)
		{
			return NO;
		}
		
		// Pass 1 :
		// Try to use whatever information is available so we can avoid hitting the database when possible.
		
		if (edge1->state & YDB_EdgeState_HasDestinationRowid)
		{
			if (edge2->state & YDB_EdgeState_HasDestinationRowid)
			{
				return (edge1->destinationRowid == edge2->destinationRowid);
			}
		}
		
		if (edge1->destinationKey)
		{
			if (edge2->destinationKey)
			{
				return [edge1->destinationKey isEqualToString:edge2->destinationKey] &&
				       [edge1->destinationCollection isEqualToString:edge2->destinationCollection];
			}
		}
		
		// Optimization failed - fallback to database lookup(s)
		//
		// Looking up the rowid for an edge is generally more useful.
		// If an edge doesn't have a rowid, then it's likely a newly inserted/modified edge,
		// and the rowid lookup will be required in the near future anyway.
		
		if (!(edge1->state & YDB_EdgeState_HasDestinationRowid))
		{
			[self lookupEdgeDestinationRowid:edge1 isDeleted:NULL];
		}
		else if (!(edge2->state & YDB_EdgeState_HasDestinationRowid))
		{
			[self lookupEdgeDestinationRowid:edge2 isDeleted:NULL];
		}
		else if (edge1->destinationKey == nil)
		{
			[self lookupEdgeDestinationCollectionKey:edge1];
		}
		else if (edge2->destinationKey == nil)
		{
			[self lookupEdgeDestinationCollectionKey:edge2];
		}
		
		// Pass 2:
		
		if (edge1->state & YDB_EdgeState_HasDestinationRowid)
		{
			if (edge2->state & YDB_EdgeState_HasDestinationRowid)
			{
				return (edge1->destinationRowid == edge2->destinationRowid);
			}
		}
		
		if (edge1->destinationKey)
		{
			if (edge2->destinationKey)
			{
				return [edge1->destinationKey isEqualToString:edge2->destinationKey] &&
				       [edge1->destinationCollection isEqualToString:edge2->destinationCollection];
			}
		}
		
		return NO; // Looks like at least one of the edges is bad
	}
}

- (BOOL)edge:(YapDatabaseRelationshipEdge *)edge1 matchesManualEdge:(YapDatabaseRelationshipEdge *)edge2
{
	NSParameterAssert(edge1 != nil);
	NSParameterAssert(edge2 != nil);
	
	if (!edge1->isManualEdge) return NO;
	if (!edge2->isManualEdge) return NO;
	
	if (![edge1->name isEqualToString:edge2->name]) return NO;
	
	if (![self edge:edge1 matchesSource:edge2]) return NO;
	if (![self edge:edge1 matchesDestination:edge2]) return NO;
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities - Changes
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Extracts edges from the in-memory changes that match the given options.
 * These edges need to replace whatever is on disk.
**/
- (NSMutableArray *)findChangesMatchingName:(NSString *)name
{
	if (name == nil)
		return nil;
	
	if (!databaseTransaction->isReadWriteTransaction)
		return nil;
	
	__block NSMutableArray *changes = nil;
	
	// Find matching protocol edges
	
	[parentConnection->protocolChanges enumerateKeysAndObjectsUsingBlock:
	    ^(id __unused dictKey, id dictObj, BOOL __unused *stop)
	{
		
	//	__unsafe_unretained NSString *srcRowidNumber = (NSNumber *)dictKey;
		__unsafe_unretained NSArray *changedEdgesForSrc = (NSArray *)dictObj;
		
		for (YapDatabaseRelationshipEdge *edge in changedEdgesForSrc)
		{
			if (![name isEqualToString:edge->name])
			{
				continue;
			}
			
			if (changes == nil)
				changes = [NSMutableArray array];
			
			[changes addObject:edge];
		}
	}];
	
	// Find matching manual edges
	
	NSArray *manualChangesMatchingName = [parentConnection->manualChanges objectForKey:name];
	if (manualChangesMatchingName)
	{
		if (changes == nil)
			changes = [NSMutableArray array];
		
		[changes addObjectsFromArray:manualChangesMatchingName];
	}
	
	// Now lookup the sourceRowid & destinationRowid for each edge (if missing).
	// We're going to need these. If not immediately, then during the next flush.
	
	for (YapDatabaseRelationshipEdge *edge in changes)
	{
		if (!(edge->state & YDB_EdgeState_HasSourceRowid))
		{
			[self lookupEdgeSourceRowid:edge isDeleted:NULL];
		}
		
		if (!(edge->state & YDB_EdgeState_HasDestinationRowid))
		{
			[self lookupEdgeDestinationRowid:edge isDeleted:NULL];
		}
	}
	
	return changes;
}

/**
 * Extracts edges from the in-memory changes that match the given options.
 * These edges need to replace whatever is on disk.
**/
- (NSMutableArray *)findChangesMatchingName:(NSString *)name
                                  sourceKey:(NSString *)srcKey
                                 collection:(NSString *)srcCollection
                                      rowid:(NSNumber *)srcRowid // <- may be nil if unknown
{
	if (srcKey == nil)
		return [self findChangesMatchingName:name];
	
	if (!databaseTransaction->isReadWriteTransaction)
		return nil;
	
	if (srcCollection == nil)
		srcCollection = @"";
	
	__block NSMutableArray *changes = nil;
	
	// Find matching protocol edges
	
	NSMutableArray *changedProtocolEdges = [parentConnection->protocolChanges objectForKey:srcRowid];
	for (YapDatabaseRelationshipEdge *edge in changedProtocolEdges)
	{
		if (name && ![name isEqualToString:edge->name])
		{
			continue;
		}
		
		if (changes == nil)
			changes = [NSMutableArray array];
		
		[changes addObject:edge];
	}
	
	// Find matching manual edges
	
	void (^FindMatchingManualEdges)(NSArray*) = ^(NSArray *manualChangesMatchingName){
		
		for (YapDatabaseRelationshipEdge *edge in manualChangesMatchingName)
		{
			if ((edge->state & YDB_EdgeState_HasSourceRowid) && srcRowid)
			{
				if (edge->sourceRowid != srcRowid.unsignedLongLongValue)
				{
					continue;
				}
			}
			else
			{
				if (![edge->sourceKey isEqualToString:srcKey] ||
				    ![edge->sourceCollection isEqualToString:srcCollection])
				{
					continue;
				}
			}
			
			if (changes == nil)
				changes = [NSMutableArray array];
			
			[changes addObject:edge];
		}
	};
	
	if (name)
	{
		NSArray *manualChangesMatchingName = [parentConnection->manualChanges objectForKey:name];
		FindMatchingManualEdges(manualChangesMatchingName);
	}
	else
	{
		[parentConnection->manualChanges enumerateKeysAndObjectsUsingBlock:
		    ^(id __unused key, id obj, BOOL __unused *stop)
		{
		//	__unsafe_unretained NSString *edgeName = (NSString *)key;
			__unsafe_unretained NSArray *manualChangesMatchingName = (NSArray *)obj;
			
			FindMatchingManualEdges(manualChangesMatchingName);
		}];
	}
	
	// Now lookup the sourceRowid & destinationRowid for each edge (if needed).
	// We're going to need these. If not immediately, then during the next flush.
	
	for (YapDatabaseRelationshipEdge *edge in changes)
	{
		// Note: Zero is a valid rowid.
		// So we use flags to properly mark whether a valid rowid has been set.
		
		if (!(edge->state & YDB_EdgeState_HasSourceRowid))
		{
			if (srcRowid)
			{
				// Shortcut:
				// We already know the sourceRowid. It was given to us as a parameter.
				
				edge->sourceRowid = srcRowid.unsignedLongLongValue;
				edge->flags |= YDB_EdgeState_HasSourceRowid;
			}
			else
			{
				[self lookupEdgeSourceRowid:edge isDeleted:NULL];
			}
		}
		
		if (!(edge->state & YDB_EdgeState_HasDestinationRowid))
		{
			[self lookupEdgeDestinationRowid:edge isDeleted:NULL];
		}
	}
	
	return changes;
}

/**
 * Extracts edges from the in-memory changes that match the given options.
 * These edges need to replace whatever is on disk.
**/
- (NSMutableArray *)findChangesMatchingName:(NSString *)name
                             destinationKey:(NSString *)dstKey
                                 collection:(NSString *)dstCollection
                                      rowid:(NSNumber *)dstRowid // <- may be nil if unknown
{
	if (dstKey == nil)
		return [self findChangesMatchingName:name];
	
	if (!databaseTransaction->isReadWriteTransaction)
		return nil;
	
	if (dstCollection == nil)
		dstCollection = @"";
	
	__block NSMutableArray *changes = nil;
	
	// Find matching protocol edges
	
	[parentConnection->protocolChanges enumerateKeysAndObjectsUsingBlock:^(id __unused dictKey, id dictObj, BOOL __unused *stop){
		
	//	__unsafe_unretained NSString *srcRowidNumber = (NSNumber *)dictKey;
		__unsafe_unretained NSArray *changedEdgesForSrc = (NSArray *)dictObj;
		
		for (YapDatabaseRelationshipEdge *edge in changedEdgesForSrc)
		{
			if (name && ![name isEqualToString:edge->name])
			{
				continue;
			}
			
			if (edge->state & YDB_EdgeState_DestinationFileURL)
			{
				continue;
			}
			else if ((edge->state & YDB_EdgeState_HasDestinationRowid) && dstRowid)
			{
				if (edge->destinationRowid != dstRowid.unsignedLongLongValue)
				{
					continue;
				}
			}
			else
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
	
	// Find matching manual edges
	
	void (^FindMatchingManualEdges)(NSArray*) = ^(NSArray *manualChangesMatchingName){
		
		for (YapDatabaseRelationshipEdge *edge in manualChangesMatchingName)
		{
			if (edge->state & YDB_EdgeState_DestinationFileURL)
			{
				continue;
			}
			else if ((edge->state & YDB_EdgeState_HasDestinationRowid) && dstRowid)
			{
				if (edge->destinationRowid != dstRowid.unsignedLongLongValue)
				{
					continue;
				}
			}
			else
			{
				if (![edge->destinationKey isEqualToString:dstKey] ||
				    ![edge->destinationCollection isEqualToString:dstCollection])
				{
					continue;
				}
			}
			
			if (changes == nil)
				changes = [NSMutableArray array];
			
			[changes addObject:edge];
		}
	};
	
	if (name)
	{
		NSArray *manualChangesMatchingName = [parentConnection->manualChanges objectForKey:name];
		FindMatchingManualEdges(manualChangesMatchingName);
	}
	else
	{
		[parentConnection->manualChanges enumerateKeysAndObjectsUsingBlock:^(id __unused key, id obj, BOOL __unused *stop){
			
		//	__unsafe_unretained NSString *edgeName = (NSString *)key;
			__unsafe_unretained NSArray *manualChangesMatchingName = (NSArray *)obj;
			
			FindMatchingManualEdges(manualChangesMatchingName);
		}];
	}
	
	// Now lookup the sourceRowid & destinationRowid for each edge (if needed).
	// We're going to need these. If not immediately, then during the next flush.
	
	for (YapDatabaseRelationshipEdge *edge in changes)
	{
		// Note: Zero is a valid rowid.
		// So we use flags to properly mark whether a valid rowid has been set.
		
		if (!(edge->state & YDB_EdgeState_HasSourceRowid))
		{
			[self lookupEdgeSourceRowid:edge isDeleted:NULL];
		}
		
		if (!(edge->state & YDB_EdgeState_HasDestinationRowid))
		{
			if (dstRowid)
			{
				// Shortcut:
				// We already know the sourceRowid. It was given to us as a parameter.
				
				edge->destinationRowid = dstRowid.unsignedLongLongValue;
				edge->state |= YDB_EdgeState_HasDestinationRowid;
			}
			else
			{
				[self lookupEdgeDestinationRowid:edge isDeleted:NULL];
			}
		}
	}
	
	return changes;
}

/**
 * Extracts edges from the in-memory changes that match the given options.
 * These edges need to replace whatever is on disk.
**/
- (NSMutableArray *)findChangesMatchingName:(NSString *)name
                         destinationFileURL:(NSURL *)dstFileURL
{
	if (dstFileURL == nil)
		return [self findChangesMatchingName:name];
	
	if (!databaseTransaction->isReadWriteTransaction)
		return nil;
	
	__block NSMutableArray *changes = nil;
	
	// Find matching protocol edges
	
	[parentConnection->protocolChanges enumerateKeysAndObjectsUsingBlock:^(id __unused dictKey, id dictObj, BOOL __unused *stop){
		
	//	__unsafe_unretained NSString *srcRowidNumber = (NSNumber *)dictKey;
		__unsafe_unretained NSArray *changedEdgesForSrc = (NSArray *)dictObj;
		
		for (YapDatabaseRelationshipEdge *edge in changedEdgesForSrc)
		{
			if (name && ![name isEqualToString:edge->name])
			{
				continue;
			}
			
			if (!URLMatchesURL(edge->destinationFileURL, dstFileURL))
			{
				continue;
			}
			
			if (changes == nil)
				changes = [NSMutableArray array];
			
			[changes addObject:edge];
		}
	}];
	
	// Find matching manual edges
	
	void (^FindMatchingManualEdges)(NSArray*) = ^(NSArray *manualChangesMatchingName){
		
		for (YapDatabaseRelationshipEdge *edge in manualChangesMatchingName)
		{
			if (!URLMatchesURL(edge->destinationFileURL, dstFileURL))
			{
				continue;
			}
			
			if (changes == nil)
				changes = [NSMutableArray array];
			
			[changes addObject:edge];
		}
	};
	
	if (name)
	{
		NSArray *manualChangesMatchingName = [parentConnection->manualChanges objectForKey:name];
		FindMatchingManualEdges(manualChangesMatchingName);
	}
	else
	{
		[parentConnection->manualChanges enumerateKeysAndObjectsUsingBlock:^(id __unused key, id obj, BOOL __unused *stop){
			
		//	__unsafe_unretained NSString *edgeName = (NSString *)key;
			__unsafe_unretained NSArray *manualChangesMatchingName = (NSArray *)obj;
			
			FindMatchingManualEdges(manualChangesMatchingName);
		}];
	}
	
	// Now lookup the sourceRowid & destinationRowid for each edge (if needed).
	// We're going to need these. If not immediately, then during the next flush.
	
	for (YapDatabaseRelationshipEdge *edge in changes)
	{
		// Note: Zero is a valid rowid.
		// So we use flags to properly mark whether a valid rowid has been set.
		
		if (!(edge->state & YDB_EdgeState_HasSourceRowid))
		{
			[self lookupEdgeSourceRowid:edge isDeleted:NULL];
		}
		
		// No need to attempt destinationRowid lookup on edges with destinationFilePath
	}
	
	return changes;
}

/**
 * Extracts edges from the in-memory changes that match the given options.
 * These edges need to replace whatever is on disk.
**/
- (NSMutableArray *)findChangesMatchingName:(NSString *)name
                                  sourceKey:(NSString *)srcKey
                                 collection:(NSString *)srcCollection
                                      rowid:(NSNumber *)srcRowid // <- may be nil if unknown
                             destinationKey:(NSString *)dstKey
                                 collection:(NSString *)dstCollection
                                      rowid:(NSNumber *)dstRowid // <- may be nil if unknown
{
	if (srcKey == nil)
	{
		if (dstKey == nil)
			return [self findChangesMatchingName:name];
		else
			return [self findChangesMatchingName:name destinationKey:dstKey collection:dstCollection rowid:dstRowid];
	}
	if (dstKey == nil)
	{
		return [self findChangesMatchingName:name sourceKey:srcKey collection:srcCollection rowid:srcRowid];
	}
	
	if (!databaseTransaction->isReadWriteTransaction)
		return nil;
	
	if (srcCollection == nil)
		srcCollection = @"";
	
	if (dstCollection == nil)
		dstCollection = @"";
	
	__block NSMutableArray *changes = nil;
	
	// Find matching protocol edges
	
	NSMutableArray *changedProtocolEdges = [parentConnection->protocolChanges objectForKey:srcRowid];
	for (YapDatabaseRelationshipEdge *edge in changedProtocolEdges)
	{
		if (name && ![name isEqualToString:edge->name])
		{
			continue;
		}
		
		if (edge->state & YDB_EdgeState_DestinationFileURL)
		{
			continue;
		}
		else if ((edge->state & YDB_EdgeState_HasDestinationRowid) && dstRowid)
		{
			if (edge->destinationRowid != dstRowid.unsignedLongLongValue)
			{
				continue;
			}
		}
		else
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
	
	// Find matching manual edges
	
	void (^FindMatchingManualEdges)(NSArray*) = ^(NSArray *manualChangesMatchingName){
		
		for (YapDatabaseRelationshipEdge *edge in manualChangesMatchingName)
		{
			if ((edge->state & YDB_EdgeState_HasSourceRowid) && srcRowid)
			{
				if (edge->sourceRowid != srcRowid.unsignedLongLongValue)
				{
					continue;
				}
			}
			else
			{
				if (![edge->sourceKey isEqualToString:srcKey] ||
				    ![edge->sourceCollection isEqualToString:srcCollection])
				{
					continue;
				}
			}
			
			if (edge->state & YDB_EdgeState_DestinationFileURL)
			{
				continue;
			}
			else if ((edge->state & YDB_EdgeState_HasDestinationRowid) && dstRowid)
			{
				if (edge->destinationRowid != dstRowid.unsignedLongLongValue)
				{
					continue;
				}
			}
			else
			{
				if (![edge->destinationKey isEqualToString:dstKey] ||
				    ![edge->destinationCollection isEqualToString:dstCollection])
				{
					continue;
				}
			}
			
			if (changes == nil)
				changes = [NSMutableArray array];
			
			[changes addObject:edge];
		}
	};
	
	if (name)
	{
		NSArray *manualChangesMatchingName = [parentConnection->manualChanges objectForKey:name];
		FindMatchingManualEdges(manualChangesMatchingName);
	}
	else
	{
		[parentConnection->manualChanges enumerateKeysAndObjectsUsingBlock:^(id __unused key, id obj, BOOL __unused *stop) {
			
		//	__unsafe_unretained NSString *edgeName = (NSString *)key;
			__unsafe_unretained NSArray *manualChangesMatchingName = (NSArray *)obj;
			
			FindMatchingManualEdges(manualChangesMatchingName);
		}];
	}
	
	// Now lookup the sourceRowid & destinationRowid for each edge (if missing).
	// We're going to need these. If not immediately, then during the next flush.
	
	for (YapDatabaseRelationshipEdge *edge in changes)
	{
		// Note: Zero is a valid rowid.
		// So we use flags to properly mark whether a valid rowid has been set.
		
		if (!(edge->state & YDB_EdgeState_HasSourceRowid))
		{
			if (srcRowid)
			{
				// Shortcut:
				// We already know the sourceRowid. It was given to us as a parameter.
				
				edge->sourceRowid = srcRowid.unsignedLongLongValue;
				edge->state |= YDB_EdgeState_HasSourceRowid;
			}
			else
			{
				[self lookupEdgeSourceRowid:edge isDeleted:NULL];
			}
		}
		
		if (!(edge->state & YDB_EdgeState_HasDestinationRowid))
		{
			if (dstRowid)
			{
				// Shortcut:
				// We already know the destinationRowid. It was given to us as a parameter.
				
				edge->destinationRowid = dstRowid.unsignedLongLongValue;
				edge->state |= YDB_EdgeState_HasDestinationRowid;
			}
			else
			{
				[self lookupEdgeDestinationRowid:edge isDeleted:NULL];
			}
		}
	}
	
	return changes;
}

/**
 * Extracts edges from the in-memory changes that match the given options.
 * These edges need to replace whatever is on disk.
**/
- (NSMutableArray *)findChangesMatchingName:(NSString *)name
                                  sourceKey:(NSString *)srcKey
                                 collection:(NSString *)srcCollection
                                      rowid:(NSNumber *)srcRowid // <- may be nil if unknown
                         destinationFileURL:(NSURL *)dstFileURL
{
	if (srcCollection == nil)
		srcCollection = @"";

	if (srcKey == nil)
	{
		if (dstFileURL == nil)
			return [self findChangesMatchingName:name];
		else
			return [self findChangesMatchingName:name destinationFileURL:dstFileURL];
	}
	if (dstFileURL == nil)
	{
		return [self findChangesMatchingName:name sourceKey:srcKey collection:srcCollection rowid:srcRowid];
	}
	
	if (!databaseTransaction->isReadWriteTransaction)
		return nil;
	
	__block NSMutableArray *changes = nil;
	
	// Find matching protocol edges
	
	NSMutableArray *changedProtocolEdges = [parentConnection->protocolChanges objectForKey:srcRowid];
	for (YapDatabaseRelationshipEdge *edge in changedProtocolEdges)
	{
		if (name && ![name isEqualToString:edge->name])
		{
			continue;
		}
		
		if (!URLMatchesURL(edge->destinationFileURL, dstFileURL))
		{
			continue;
		}
		
		if (changes == nil)
			changes = [NSMutableArray array];
		
		[changes addObject:edge];
	}
	
	// Find matching manual edges
	
	void (^FindMatchingManualEdges)(NSArray*) = ^(NSArray *manualChangesMatchingName){
		
		for (YapDatabaseRelationshipEdge *edge in manualChangesMatchingName)
		{
			if ((edge->state & YDB_EdgeState_HasSourceRowid) && srcRowid)
			{
				if (edge->sourceRowid != srcRowid.unsignedLongLongValue)
				{
					continue;
				}
			}
			else
			{
				if (![edge->sourceKey isEqualToString:srcKey] ||
				    ![edge->sourceCollection isEqualToString:srcCollection])
				{
					continue;
				}
			}
			
			if (!URLMatchesURL(edge->destinationFileURL, dstFileURL))
			{
				continue;
			}
			
			if (changes == nil)
				changes = [NSMutableArray array];
			
			[changes addObject:edge];
		}
	};
	
	if (name)
	{
		NSArray *manualChangesMatchingName = [parentConnection->manualChanges objectForKey:name];
		FindMatchingManualEdges(manualChangesMatchingName);
	}
	else
	{
		[parentConnection->manualChanges enumerateKeysAndObjectsUsingBlock:^(id __unused key, id obj, BOOL __unused *stop) {
			
		//	__unsafe_unretained NSString *edgeName = (NSString *)key;
			__unsafe_unretained NSArray *manualChangesMatchingName = (NSArray *)obj;
			
			FindMatchingManualEdges(manualChangesMatchingName);
		}];
	}
	
	// Now lookup the sourceRowid & destinationRowid for each edge (if missing).
	// We're going to need these. If not immediately, then during the next flush.
	
	for (YapDatabaseRelationshipEdge *edge in changes)
	{
		// Note: Zero is a valid rowid.
		// So we use flags to properly mark whether a valid rowid has been set.
		
		if (!(edge->state & YDB_EdgeState_HasSourceRowid))
		{
			if (srcRowid)
			{
				// Shortcut:
				// We already know the sourceRowid. It was given to us as a parameter.
				
				edge->sourceRowid = srcRowid.unsignedLongLongValue;
				edge->state |= YDB_EdgeState_HasSourceRowid;
			}
			else
			{
				[self lookupEdgeSourceRowid:edge isDeleted:NULL];
			}
		}
		
		// No need to attempt destinationRowid lookup on edges with destinationFilePath
	}
	
	return changes;
}

/**
 * Searches the deletedInfo ivar to retrieve the associated rowid for a node that doesn't appear in the database.
 * If the node was deleted, we'll find it.
 * Otherwise the edge was bad (node never existed).
**/
- (NSNumber *)rowidNumberForDeletedKey:(NSString *)inKey inCollection:(NSString *)inCollection
{
	__block NSNumber *result = nil;
	
	[parentConnection->deletedInfo enumerateKeysAndObjectsUsingBlock:^(id enumKey, id enumObj, BOOL *stop){
		
		__unsafe_unretained NSNumber *rowidNumber = (NSNumber *)enumKey;
		__unsafe_unretained YapCollectionKey *collectionKey = (YapCollectionKey *)enumObj;
		
		if ([collectionKey.key isEqualToString:inKey] && [collectionKey.collection isEqualToString:inCollection])
		{
			result = rowidNumber;
			*stop = YES;
		}
	}];
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities - Disk
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Simple enumeration of existing data in database, via a SELECT query.
 * Does not take into account anything in memory (parentConnection->changes dictionary).
**/
- (void)enumerateExistingEdgesWithSource:(int64_t)srcRowid
                              usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge))block
{
	BOOL needsFinalize;
	sqlite3_stmt *statement = [parentConnection enumerateForSrcStatement:&needsFinalize];
	if (statement == NULL) return;
	
	// SELECT "rowid", "name", "dst", "rules", "manual" FROM "tableName" WHERE "src" = ?;
	
	int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
	int const column_idx_name   = SQLITE_COLUMN_START + 1;
	int const column_idx_dst    = SQLITE_COLUMN_START + 2;
	int const column_idx_rules  = SQLITE_COLUMN_START + 3;
	int const column_idx_manual = SQLITE_COLUMN_START + 4;
	
	int const bind_idx_src      = SQLITE_BIND_START;
	
	sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		YapDatabaseRelationshipEdge *edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
		if (edge)
		{
			edge->sourceRowid = srcRowid;
			edge->state |= YDB_EdgeState_HasSourceRowid;
			
			if (sqlite3_column_type(statement, column_idx_dst) == SQLITE_INTEGER)
			{
				edge->destinationRowid = sqlite3_column_int64(statement, column_idx_dst);
				edge->state |= YDB_EdgeState_HasDestinationRowid;
			}
		}
		else
		{
			const unsigned char *text = sqlite3_column_text(statement, column_idx_name);
			int textSize = sqlite3_column_bytes(statement, column_idx_name);
			
			NSString *name = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			int64_t dstRowid = 0;
			NSData *dstFileURLData = nil;
			
			int column_type = sqlite3_column_type(statement, column_idx_dst);
			if (column_type == SQLITE_INTEGER)
			{
				dstRowid = sqlite3_column_int64(statement, column_idx_dst);
			}
			else if (column_type == SQLITE_BLOB)
			{
				const void *blob = sqlite3_column_blob(statement, column_idx_dst);
				int blobSize = sqlite3_column_bytes(statement, column_idx_dst);
				
				dstFileURLData = [NSData dataWithBytes:(void *)blob length:blobSize];
			}
			
			int rules = sqlite3_column_int(statement, column_idx_rules);
			BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
		
			edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
			                                                         name:name
			                                                     srcRowid:srcRowid
			                                                     dstRowid:dstRowid
			                                                      dstData:dstFileURLData
			                                                        rules:rules
			                                                       manual:manual];
			
			[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
		}
		
		block(edge);
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
}

/**
 * Simple enumeration of existing data in database, via a SELECT query.
 * Does not take into account anything in memory (parentConnection->changes dictionary).
**/
- (void)enumerateExistingEdgesWithDestination:(int64_t)dstRowid
                                   usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge))block
{
	BOOL needsFinalize;
	sqlite3_stmt *statement = [parentConnection enumerateForDstStatement:&needsFinalize];
	if (statement == NULL) return;
	
	// SELECT "rowid", "name", "src", "rules", "manual" FROM "tableName" WHERE "dst" = ?;
	
	int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
	int const column_idx_name   = SQLITE_COLUMN_START + 1;
	int const column_idx_src    = SQLITE_COLUMN_START + 2;
	int const column_idx_rules  = SQLITE_COLUMN_START + 3;
	int const column_idx_manual = SQLITE_COLUMN_START + 4;
	int const bind_idx_dst      = SQLITE_BIND_START;
	
	sqlite3_bind_int64(statement, bind_idx_dst, dstRowid);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		YapDatabaseRelationshipEdge *edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
		if (edge)
		{
			edge->sourceRowid = sqlite3_column_int64(statement, column_idx_src);
			edge->state |= YDB_EdgeState_HasSourceRowid;
			
			edge->destinationRowid = dstRowid;
			edge->state |= YDB_EdgeState_HasDestinationRowid;
		}
		else
		{
			const unsigned char *text = sqlite3_column_text(statement, column_idx_name);
			int textSize = sqlite3_column_bytes(statement, column_idx_name);
			
			NSString *name = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			int64_t srcRowid = sqlite3_column_int64(statement, column_idx_src);
			
			int rules = sqlite3_column_int(statement, column_idx_rules);
			BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
			
			edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
			                                                         name:name
			                                                     srcRowid:srcRowid
			                                                     dstRowid:dstRowid
			                                                      dstData:nil
			                                                        rules:rules
			                                                       manual:manual];
			
			[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
		}
		
		block(edge);
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
}

/**
 * Queries the database for the number of edges matching the given source and name.
 * This method only queries the database, and doesn't inspect anything in memory.
**/
- (int64_t)edgeCountWithSource:(int64_t)srcRowid name:(NSString *)name excludingDestination:(int64_t)dstRowid
{
	sqlite3_stmt *statement = [parentConnection countForSrcNameExcludingDstStatement];
	if (statement == NULL) return 0;
	
	int64_t count = 0;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "src" = ? AND "dst" != ? AND "name" = ?;
	
	int const column_idx_count = SQLITE_COLUMN_START;
	int const bind_idx_src     = SQLITE_BIND_START + 0;
	int const bind_idx_dst     = SQLITE_BIND_START + 1;
	int const bind_idx_name    = SQLITE_BIND_START + 2;
	
	sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
	sqlite3_bind_int64(statement, bind_idx_dst, dstRowid);
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, name);
	sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, column_idx_count);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
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
	NSAssert(name != nil, @"Internal logic error");
	
	sqlite3_stmt *statement = [parentConnection countForDstNameExcludingSrcStatement];
	if (statement == NULL) return 0;
	
	int64_t count = 0;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "dst" = ? AND "src" != ? AND "name" = ?;
	
	int const column_idx_count = SQLITE_COLUMN_START;
	int const bind_idx_dst     = SQLITE_BIND_START + 0;
	int const bind_idx_src     = SQLITE_BIND_START + 1;
	int const bind_idx_name    = SQLITE_BIND_START + 2;
	
	sqlite3_bind_int64(statement, bind_idx_dst, dstRowid);
	sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, name);
	sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, column_idx_count);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
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
- (int64_t)edgeCountWithDestinationFileURL:(NSURL *)dstFileURL
                                      name:(NSString *)name
                           excludingSource:(int64_t)srcRowid
{
	NSAssert(dstFileURL != nil, @"Internal logic error");
	NSAssert(name != nil, @"Internal logic error");
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [parentConnection enumerateDstFileURLWithNameExcludingSrcStatement:&needsFinalize];
	if (statement == NULL) return 0;
	
	int64_t count = 0;
	
	// SELECT "rowid", "src", "dst", "rules", "manual" FROM "tableName"
	//  WHERE "dst" > INT64_MAX AND "src" != ? AND "name" = ?;
	//
	// AKA: typeof(dst) IS BLOB
	
	int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
	int const column_idx_src    = SQLITE_COLUMN_START + 2;
	int const column_idx_dst    = SQLITE_COLUMN_START + 3;
	int const column_idx_rules  = SQLITE_COLUMN_START + 4;
	int const column_idx_manual = SQLITE_COLUMN_START + 5;
	
	int const bind_idx_src = SQLITE_BIND_START + 0;
	int const bind_idx_name = SQLITE_BIND_START + 1;
	
	sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, name);
	sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		YapDatabaseRelationshipEdge *edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
		if (edge)
		{
			edge->sourceRowid = sqlite3_column_int64(statement, column_idx_src);
			edge->state |= YDB_EdgeState_HasSourceRowid;
		}
		else
		{
			int64_t srcRowid = sqlite3_column_int64(statement, column_idx_src);
			
			int64_t dstRowid = 0;
			NSData *dstFileURLData = nil;
			
			int column_type = sqlite3_column_type(statement, column_idx_dst);
			if (column_type == SQLITE_INTEGER)
			{
				dstRowid = sqlite3_column_int64(statement, column_idx_dst);
			}
			else if (column_type == SQLITE_BLOB)
			{
				const void *blob = sqlite3_column_blob(statement, column_idx_dst);
				int blobSize = sqlite3_column_bytes(statement, column_idx_dst);
				
				dstFileURLData = [NSData dataWithBytes:(void *)blob length:blobSize];
			}
			
			int rules = sqlite3_column_int(statement, column_idx_rules);
			BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
		
			edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
			                                                         name:name
			                                                     srcRowid:srcRowid
			                                                     dstRowid:dstRowid
			                                                      dstData:dstFileURLData
			                                                        rules:rules
			                                                       manual:manual];
			
			[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
		}
		
		[self lookupEdgeDestinationFileURL:edge];
		
		if (URLMatchesURL(dstFileURL, edge->destinationFileURL))
		{
			count++;
		}
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_name);
	
	return count;
}

- (YapDatabaseRelationshipEdge *)findExistingManualEdgeMatching:(YapDatabaseRelationshipEdge *)inEdge
{
	// Lookup the sourceRowid and destinationRowid for the given edge (if missing).
	//
	// Note: Zero is a valid rowid.
	// So we use flags to properly handle this edge case.
	
	BOOL missingSrc = NO;
	if (![self lookupEdgeSourceRowid:inEdge isDeleted:NULL])
		missingSrc = YES;
	
	if (missingSrc) {
		return nil;
	}
	
	BOOL missingDst = NO;
	if (inEdge->state & YDB_EdgeState_DestinationFileURL)
	{
		[self lookupEdgeDestinationFileURL:inEdge];
	}
	else
	{
		if (![self lookupEdgeDestinationRowid:inEdge isDeleted:NULL])
			missingDst = YES;
	}
	
	if (missingDst) {
		return nil;
	}
	
	if (inEdge->state & YDB_EdgeState_DestinationFileURL)
	{
		sqlite3_stmt *statement = [parentConnection findManualEdgeWithDstFileURLStatement];
		if (statement == NULL) return nil;
		
		// SELECT "rowid", "rules" FROM "tableName"
		//   WHERE "src" = ? AND "name" = ? AND "dst" > INT64_MAX AND "manual" = 1;
		//
		// AKA: typeof(dst) IS BLOB
		
		int const column_idx_rowid = SQLITE_COLUMN_START + 0;
		int const column_idx_dst   = SQLITE_COLUMN_START + 1;
		int const column_idx_rules = SQLITE_COLUMN_START + 2;
		
		int const bind_idx_src     = SQLITE_BIND_START + 0;
		int const bind_idx_name    = SQLITE_BIND_START + 1;
		
		sqlite3_bind_int64(statement, bind_idx_src, inEdge->sourceRowid);
		
		YapDatabaseString _name; MakeYapDatabaseString(&_name, inEdge->name);
		sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
		
		YapDatabaseRelationshipEdge *matchingEdge = nil;
		
		int status;
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			YapDatabaseRelationshipEdge *rowEdge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
			if (rowEdge == nil)
			{
				int64_t dstRowid = 0;
				NSData *dstFileURLData = nil;
				
				int column_type = sqlite3_column_type(statement, column_idx_dst);
				if (column_type == SQLITE_INTEGER)
				{
					dstRowid = sqlite3_column_int64(statement, column_idx_dst);
				}
				else if (column_type == SQLITE_BLOB)
				{
					const void *blob = sqlite3_column_blob(statement, column_idx_dst);
					int blobSize = sqlite3_column_bytes(statement, column_idx_dst);
					
					dstFileURLData = [NSData dataWithBytes:(void *)blob length:blobSize];
				}
				
				int rules = sqlite3_column_int(statement, column_idx_rules);
				
				rowEdge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
				                                                            name:inEdge->name
				                                                        srcRowid:inEdge->sourceRowid
				                                                        dstRowid:dstRowid
				                                                         dstData:dstFileURLData
				                                                           rules:rules
				                                                          manual:YES];
				
				[parentConnection->edgeCache setObject:rowEdge forKey:@(edgeRowid)];
			}
			
			[self lookupEdgeDestinationFileURL:rowEdge];
			
			if (URLMatchesURL(inEdge->destinationFileURL, rowEdge->destinationFileURL))
			{
				matchingEdge = rowEdge;
				break;
			}
		}
		
		if (status == SQLITE_ERROR)
		{
			YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_name);
		
		return matchingEdge;
	}
	else
	{
		sqlite3_stmt *statement = [parentConnection findManualEdgeWithDstStatement];
		if (statement == NULL) return nil;
		
		// SELECT "rowid", "rules" FROM "tableName"
		//   WHERE "src" = ? AND "dst" = ? AND "name" = ? AND "manual" = 1 LIMIT 1;
		
		int const column_idx_rowid = SQLITE_COLUMN_START + 0;
		int const column_idx_rules = SQLITE_COLUMN_START + 1;
		int const bind_idx_src     = SQLITE_BIND_START + 0;
		int const bind_idx_dst     = SQLITE_BIND_START + 1;
		int const bind_idx_name    = SQLITE_BIND_START + 2;
		
		sqlite3_bind_int64(statement, bind_idx_src, inEdge->sourceRowid);
		sqlite3_bind_int64(statement, bind_idx_dst, inEdge->destinationRowid);
	
		YapDatabaseString _name; MakeYapDatabaseString(&_name, inEdge->name);
		sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
		
		YapDatabaseRelationshipEdge *matchingEdge = nil;
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
			int rules = sqlite3_column_int(statement, column_idx_rules);
			
			matchingEdge = [inEdge copy];
			
			matchingEdge->edgeRowid = edgeRowid;
			matchingEdge->state |= YDB_EdgeState_HasEdgeRowid;
			
			matchingEdge->nodeDeleteRules = (unsigned short)rules;
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_name);
		
		return matchingEdge;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flush Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method enumerates over the given sets of edges, and sets the following properties to their appropriate value:
 *
 * edge->action
 * edge->flags
 *
 * The source node of each edge must be new (inserted during this transaction).
**/
- (void)preprocessProtocolEdges:(NSMutableArray *)protocolEdges forInsertedSource:(int64_t)srcRowid
{
	// Get common info
	
	BOOL srcDeleted = [parentConnection->deletedInfo ydb_containsKey:@(srcRowid)];
	
	// Process each edge.
	//
	// Since we know the source node is new (inserted during this transaction),
	// we can skip doing any kind of merging with existing edges on disk.
	
	for (YapDatabaseRelationshipEdge *edge in protocolEdges)
	{
		if (srcDeleted)
		{
			edge->action = YDB_EdgeAction_Delete;
			edge->flags |= YDB_EdgeFlags_SourceDeleted;
			edge->flags |= YDB_EdgeFlags_EdgeNotInDatabase; // no need to delete edge from database
		}
		
		if (edge->state & YDB_EdgeState_DestinationFileURL)
		{
			if (!srcDeleted)
			{
				edge->action = YDB_EdgeAction_Insert;
			}
			continue;
		}
		
		// Lookup destinationRowid (if needed)
		
		if (!(edge->state & YDB_EdgeState_HasDestinationRowid))
		{
			BOOL dstDeleted = NO;
			BOOL found = [self lookupEdgeDestinationRowid:edge isDeleted:&dstDeleted];
			
			if (!found)
			{
				// Bad edge (destination node never existed).
				// Treat as if destination node was deleted.
				
				edge->action = YDB_EdgeAction_Delete;
				edge->flags |= YDB_EdgeFlags_DestinationDeleted;
				edge->flags |= YDB_EdgeFlags_BadDestination;
				edge->flags |= YDB_EdgeFlags_EdgeNotInDatabase; // no need to delete edge from database
				
				continue;
			}
			else if (dstDeleted)
			{
				edge->action = YDB_EdgeAction_Delete;
				edge->flags |= YDB_EdgeFlags_DestinationDeleted;
				edge->flags |= YDB_EdgeFlags_EdgeNotInDatabase; // no need to delete edge from database
				
				continue;
			}
		}
		
		if ([parentConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
		{
			edge->action = YDB_EdgeAction_Delete;
			edge->flags |= YDB_EdgeFlags_DestinationDeleted;
			edge->flags |= YDB_EdgeFlags_EdgeNotInDatabase; // no need to delete edge from database
		}
		else if (!srcDeleted)
		{
			edge->action = YDB_EdgeAction_Insert;
		}
	}
}

/**
 * This method merges the given set of edges with the corresponding edges that already exist on disk.
 * It will update the given edges list, adding any edges that have been manually removed from the list.
 *
 * edge->edgeRowid
 * edge->edgeAction
 * edge->flags
 * 
 * The source node of each edge is non-new (updated, not inserted, during transaction).
**/
- (void)preprocessProtocolEdges:(NSMutableArray *)protocolEdges forUpdatedSource:(int64_t)srcRowid
{
	BOOL srcDeleted = [parentConnection->deletedInfo ydb_containsKey:@(srcRowid)];
	
	// Step 1 :
	//
	// Pre-process the updated edges.
	// This involves looking up the destinationRowid for each edge.
	//
	// Implementation details:
	//
	// We use the offset & protocolEdgesCount to mark the range of unprocessed edges in the array:
	// - All nodes at index < offset have already been processed.
	// - All nodes at index >= protocolEdgesCount were added to the array and should be ignored.
	//
	// These added nodes represent existing edges in the database that were
	// implicitly deleted by removing from edge list.
	
	__block NSUInteger offset = 0;
	NSUInteger protocolEdgesCount = [protocolEdges count];
	
	for (NSUInteger i = 0; i < protocolEdgesCount; i++)
	{
		YapDatabaseRelationshipEdge *edge = [protocolEdges objectAtIndex:i];
		
		if (edge->state & YDB_EdgeState_DestinationFileURL)
		{
			continue;
		}
		
		// Note: Zero is a valid rowid.
		// So we use flags to properly mark whether a valid rowid has been set.
		
		if (!(edge->state & YDB_EdgeState_HasDestinationRowid))
		{
			BOOL dstDeleted = NO;
			BOOL found = [self lookupEdgeDestinationRowid:edge isDeleted:&dstDeleted];
			
			if (!found)
			{
				// Bad edge (destination node never existed).
				// Treat as if destination node was deleted.
				
				edge->action = YDB_EdgeAction_Delete;
				edge->flags |= YDB_EdgeFlags_DestinationDeleted;
				edge->flags |= YDB_EdgeFlags_BadDestination;
				
				[protocolEdges exchangeObjectAtIndex:i withObjectAtIndex:offset];
				offset++;
			}
			else if (dstDeleted)
			{
				edge->action = YDB_EdgeAction_Delete;
				edge->flags |= YDB_EdgeFlags_DestinationDeleted;
			}
		}
	}
	
	// Step 2 :
	//
	// Enumerate the existing edges in the database, and try to match them up with edges from the new set.
	
	[self enumerateExistingEdgesWithSource:srcRowid usingBlock:^(YapDatabaseRelationshipEdge *existingEdge) {
		
		// Ignore manually created edges
		if (existingEdge->isManualEdge) return; // continue (next matching row)
		
		YapDatabaseRelationshipEdge *matchingProtocolEdge = nil;
		
		NSUInteger i = offset;
		while (i < protocolEdgesCount)
		{
			YapDatabaseRelationshipEdge *protocolEdge = [protocolEdges objectAtIndex:i];
			
			if ([protocolEdge->name isEqualToString:existingEdge->name] &&
			    [self edge:protocolEdge matchesDestination:existingEdge])
			{
				matchingProtocolEdge = protocolEdge;
				
				matchingProtocolEdge->edgeRowid = existingEdge->edgeRowid;
				matchingProtocolEdge->state |= YDB_EdgeState_HasEdgeRowid;
				
				matchingProtocolEdge->destinationRowid = existingEdge->destinationRowid;
				matchingProtocolEdge->state |= YDB_EdgeState_HasDestinationRowid;
				
				break;
			}
			
			i++;
		}
		
		if (matchingProtocolEdge)
		{
			// This edges matches an existing edge already in the database.
			// Check to see if it changed at all.
			
			if (matchingProtocolEdge->nodeDeleteRules != existingEdge->nodeDeleteRules)
			{
				// The nodeDeleteRules changed. Mark for update.
				
				matchingProtocolEdge->action = YDB_EdgeAction_Update;
			}
			else
			{
				// Nothing changed
				
				matchingProtocolEdge->action = YDB_EdgeAction_None;
			}
			
			// Was source and/or destination deleted?
			
			if (srcDeleted)
			{
				matchingProtocolEdge->action = YDB_EdgeAction_Delete;
				matchingProtocolEdge->flags |= YDB_EdgeFlags_SourceDeleted;
			}
			
			if (!(matchingProtocolEdge->state & YDB_EdgeState_DestinationFileURL) &&
				 [parentConnection->deletedInfo ydb_containsKey:@(matchingProtocolEdge->destinationRowid)])
			{
				matchingProtocolEdge->action = YDB_EdgeAction_Delete;
				matchingProtocolEdge->flags |= YDB_EdgeFlags_DestinationDeleted;
			}
			
			[protocolEdges exchangeObjectAtIndex:i withObjectAtIndex:offset];
			offset++;
		}
		else
		{
			// The existing edge in the database has no match in the new protocolEdges list.
			// Thus an existing edge was removed from the list of edges,
			// and so it needs to be deleted from the database.
			
			YapDatabaseRelationshipEdge *edge = [existingEdge copy];
			
			edge->action = YDB_EdgeAction_Delete;
			edge->flags |= YDB_EdgeFlags_SourceDeleted;
			
			if (!(edge->state & YDB_EdgeState_DestinationFileURL) &&
				 [parentConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
			{
				edge->flags |= YDB_EdgeFlags_DestinationDeleted;
			}
			
			[protocolEdges addObject:edge];
			// Note: Do NOT increment protocolEdgesCount.
		}
	}];
	
	// Step 3 :
	//
	// Process any protocolEdges that didn't match an existing edge in the database.
	
	for (NSUInteger i = offset; i < protocolEdgesCount; i++)
	{
		YapDatabaseRelationshipEdge *edge = [protocolEdges objectAtIndex:i];
		
		edge->action = YDB_EdgeAction_Insert;
		
		if (srcDeleted)
		{
			edge->action = YDB_EdgeAction_Delete;
			edge->flags |= YDB_EdgeFlags_SourceDeleted;
			edge->flags |= YDB_EdgeFlags_EdgeNotInDatabase;
		}
		
		if (!(edge->state & YDB_EdgeState_DestinationFileURL) &&
		     [parentConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
		{
			edge->action = YDB_EdgeAction_Delete;
			edge->flags |= YDB_EdgeFlags_DestinationDeleted;
			edge->flags |= YDB_EdgeFlags_EdgeNotInDatabase;
		}
	}
}

/**
 * This method enumerates over the given sets of edges, and sets the following properties to their appropriate value:
 *
 * edge->action
 * edge->flags
**/
- (void)preprocessManualEdges:(NSMutableArray *)manualEdges
{
	for (YapDatabaseRelationshipEdge *edge in manualEdges)
	{
		// Lookup sourceRowid (if needed).
		// And then check to see if source node was deleted.
		
		if (!(edge->state & YDB_EdgeState_HasSourceRowid))
		{
			BOOL srcDeleted = NO;
			BOOL found = [self lookupEdgeSourceRowid:edge isDeleted:&srcDeleted];
			
			if (!found)
			{
				// Bad edge (source node never existed).
				// Treat as if source node was deleted.
				
				edge->action = YDB_EdgeAction_Delete;
				edge->flags |= YDB_EdgeFlags_SourceDeleted;
				edge->flags |= YDB_EdgeFlags_BadSource;
			}
			else if (srcDeleted)
			{
				edge->action = YDB_EdgeAction_Delete;
				edge->flags |= YDB_EdgeFlags_SourceDeleted;
			}
		}
		else if ([parentConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
		{
			edge->action = YDB_EdgeAction_Delete;
			edge->flags |= YDB_EdgeFlags_SourceDeleted;
		}
		
		
		// Lookup destinationRowid (if needed).
		// And then check to see if destination node was deleted.
		
		if (edge->state & YDB_EdgeState_DestinationFileURL)
		{
			// Not using destination in database
		}
		else if (!(edge->state & YDB_EdgeState_HasDestinationRowid))
		{
			BOOL dstDeleted = NO;
			BOOL found = [self lookupEdgeDestinationRowid:edge isDeleted:&dstDeleted];
			
			if (!found)
			{
				// Bad edge (destination node never existed).
				// Treat as if destination node was deleted.
				
				edge->action = YDB_EdgeAction_Delete;
				edge->flags |= YDB_EdgeFlags_DestinationDeleted;
				edge->flags |= YDB_EdgeFlags_BadDestination;
			}
			else if (dstDeleted)
			{
				edge->action = YDB_EdgeAction_Delete;
				edge->flags |= YDB_EdgeFlags_DestinationDeleted;
			}
		}
		else if ([parentConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
		{
			edge->action = YDB_EdgeAction_Delete;
			edge->flags |= YDB_EdgeFlags_DestinationDeleted;
		}
	}
}

/**
 * Helper method for executing the sqlite statement to insert an edge into the database.
**/
- (void)insertEdge:(YapDatabaseRelationshipEdge *)edge
{
	NSAssert((edge->state & YDB_EdgeState_HasSourceRowid),      @"Logic error - edge->sourceRowid not set");
	NSAssert((edge->state & YDB_EdgeState_HasDestinationRowid), @"Logic error - edge destination info missing");
	
	sqlite3_stmt *statement = [parentConnection insertEdgeStatement];
	if (statement == NULL) return;
	
	__attribute__((objc_precise_lifetime)) NSData *dstBlob = nil;
	
	// INSERT INTO "tableName" ("name", "src", "dst", "rules", "manual") VALUES (?, ?, ?, ?, ?);
	
	int const bind_idx_name   = SQLITE_BIND_START + 0;
	int const bind_idx_src    = SQLITE_BIND_START + 1;
	int const bind_idx_dst    = SQLITE_BIND_START + 2;
	int const bind_idx_rules  = SQLITE_BIND_START + 3;
	int const bind_idx_manual = SQLITE_BIND_START + 4;
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, edge->name);
	sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
	
	sqlite3_bind_int64(statement, bind_idx_src, edge->sourceRowid);
	
	if (edge->state & YDB_EdgeState_DestinationFileURL)
	{
		if (edge->destinationFileURL)
		{
			dstBlob = parentConnection->parent->options.fileURLSerializer(edge);
		}
		
		sqlite3_bind_blob(statement, bind_idx_dst, dstBlob.bytes, (int)dstBlob.length, SQLITE_STATIC);
	}
	else
	{
		sqlite3_bind_int64(statement, bind_idx_dst, edge->destinationRowid);
	}
	
	sqlite3_bind_int(statement, bind_idx_rules, edge->nodeDeleteRules);
	sqlite3_bind_int(statement, bind_idx_manual, (edge->isManualEdge ? 1 : 0));
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		edge->edgeRowid = sqlite3_last_insert_rowid(databaseTransaction->connection->db);
		edge->state |= YDB_EdgeState_HasEdgeRowid;
		
		edge->action = YDB_EdgeAction_None;
		edge->flags = 0;
		
		[parentConnection->edgeCache setObject:edge forKey:@(edge->edgeRowid)];
	}
	else
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_name);
}

/**
 * Helper method for executing the sqlite statement to update an edge in the database.
**/
- (void)updateEdge:(YapDatabaseRelationshipEdge *)edge
{
	NSAssert((edge->state & YDB_EdgeState_HasEdgeRowid), @"Logic error - edgeRowid not set");
	
	sqlite3_stmt *statement = [parentConnection updateEdgeStatement];
	if (statement == NULL) return;
	
	// UPDATE "tableName" SET "rules" = ? WHERE "rowid" = ?;
	
	int const bind_idx_rules = SQLITE_BIND_START + 0;
	int const bind_idx_rowid = SQLITE_BIND_START + 1;
	
	sqlite3_bind_int(statement, bind_idx_rules, edge->nodeDeleteRules);
	sqlite3_bind_int64(statement, bind_idx_rowid, edge->edgeRowid);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		edge->action = YDB_EdgeAction_None;
		edge->flags = 0;
		
		[parentConnection->edgeCache setObject:edge forKey:@(edge->edgeRowid)];
		
		[parentConnection->modifiedEdges setObject:[edge copy] forKey:@(edge->edgeRowid)];
		[parentConnection->deletedEdges removeObject:@(edge->edgeRowid)];
	}
	else
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
}

/**
 * Helper method for executing the sqlite statement to delete an edge from the database.
**/
- (void)deleteEdge:(YapDatabaseRelationshipEdge *)edge
{
	NSAssert((edge->state & YDB_EdgeState_HasEdgeRowid), @"Logic error - edgeRowid not set");
	
	sqlite3_stmt *statement = [parentConnection deleteEdgeStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "tableName" WHERE "rowid" = ?;
	
	int const bind_idx_rowid = SQLITE_BIND_START + 0;
	
	sqlite3_bind_int64(statement, bind_idx_rowid, edge->edgeRowid);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		[parentConnection->edgeCache removeObjectForKey:@(edge->edgeRowid)];
		
		[parentConnection->deletedEdges addObject:@(edge->edgeRowid)];
		[parentConnection->modifiedEdges removeObjectForKey:@(edge->edgeRowid)];
	}
	else
	{
		YDBLogError(@"%@ - Error executing statement (B): %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
}

/**
 * Helper method for executing the sqlite statement to delete all edges touching the given rowid.
**/
- (void)deleteEdgesWithSourceOrDestination:(int64_t)rowid
{
	// Step 1:
	// First record the edges that are getting deleted
	{
		sqlite3_stmt *statement = [parentConnection findEdgesWithNodeStatement];
		if (statement == NULL) return;
		
		// SELECT "rowid" FROM "tableName" WHERE "src" = ? OR "dst" = ?;
		
		int const column_idx_rowid = SQLITE_COLUMN_START;
		
		int const bind_idx_src = SQLITE_BIND_START + 0;
		int const bind_idx_dst = SQLITE_BIND_START + 1;
		
		sqlite3_bind_int64(statement, bind_idx_src, rowid);
		sqlite3_bind_int64(statement, bind_idx_dst, rowid);
		
		int status;
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			[parentConnection->deletedEdges addObject:@(edgeRowid)];
		}
		
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD,
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	
	// Step 2:
	// Then actually go ahead and delete the edges
	{
		sqlite3_stmt *statement = [parentConnection deleteEdgesWithNodeStatement];
		if (statement == NULL) return;
		
		// DELETE FROM "tableName" WHERE "src" = ? OR "dst" = ?;
		
		int const bind_idx_src = SQLITE_BIND_START + 0;
		int const bind_idx_dst = SQLITE_BIND_START + 1;
		
		sqlite3_bind_int64(statement, bind_idx_src, rowid);
		sqlite3_bind_int64(statement, bind_idx_dst, rowid);
		
		int status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
						status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
}

/**
 * Helper method for executing the sqlite statement to delete all protocol edges from the database.
 *
 * This means all edges that were created via the YapDatabaseRelationshipNode protocol.
 * So every edge in the database where the 'manual' column in set to zero.
**/
- (void)removeAllProtocolEdges
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [parentConnection removeAllProtocolStatement];
	if (statement == NULL)
		return;
	
	// DELETE FROM "tableName" WHERE "manual" = 0;
	
	YDBLogVerbose(@"Removing all protocol edges");
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
	
	[parentConnection->protocolChanges removeAllObjects];
}

/**
 * This method is called from handleRemoveAllObjectsInAllCollections.
 * 
 * It first finds all referenced destinationFilePaths, and add them to our filesToDelete set.
 * Then it removes all edges, both protocol & manual edges.
**/
- (void)removeAllEdges
{
	YDBLogAutoTrace();
	
	// This method is different from removeAllProtocolEdges.
	// This method is ONLY called when the user is removing all objects in the database.
	
	// Step 1: Find any files we may need to delete upon commiting the transaction
	{
		YDBLogVerbose(@"Looking for files to delete...");
		
		BOOL needsFinalize;
		sqlite3_stmt *statement = [parentConnection enumerateAllDstFileURLStatement:&needsFinalize];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "name", "src", "dst", "rules", "manual" FROM "tableName" WHERE "dst" > INT64_MAX;
		//
		// AKA: typeof(dst) IS BLOB
		
		int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
		int const column_idx_name   = SQLITE_COLUMN_START + 1;
		int const column_idx_src    = SQLITE_COLUMN_START + 2;
		int const column_idx_dst    = SQLITE_COLUMN_START + 3;
		int const column_idx_rules  = SQLITE_COLUMN_START + 4;
		int const column_idx_manual = SQLITE_COLUMN_START + 5;
		
		int status;
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			YapDatabaseRelationshipEdge *edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
			if (edge == nil)
			{
				const unsigned char *text = sqlite3_column_text(statement, column_idx_name);
				int textSize = sqlite3_column_bytes(statement, column_idx_name);
				
				NSString *name = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				
				int64_t srcRowid = sqlite3_column_int64(statement, column_idx_src);
				
				int64_t dstRowid = 0;
				NSData *dstFileURLData = nil;
				
				int column_type = sqlite3_column_type(statement, column_idx_dst);
				if (column_type == SQLITE_INTEGER)
				{
					dstRowid = sqlite3_column_int64(statement, column_idx_dst);
				}
				else if (column_type == SQLITE_BLOB)
				{
					const void *blob = sqlite3_column_blob(statement, column_idx_dst);
					int blobSize = sqlite3_column_bytes(statement, column_idx_dst);
					
					dstFileURLData = [NSData dataWithBytes:(void *)blob length:blobSize];
				}
				
				int rules = sqlite3_column_int(statement, column_idx_rules);
				BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
				
				edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
				                                                    name:name
				                                                srcRowid:srcRowid
				                                                dstRowid:dstRowid
				                                                 dstData:dstFileURLData
				                                                   rules:rules
				                                                  manual:manual];
			}
			
			[self lookupEdgeDestinationFileURL:edge];
			
			if (edge->destinationFileURL) {
				[parentConnection->filesToDelete addObject:edge->destinationFileURL];
			}
		}
		
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD,
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite_enum_reset(statement, needsFinalize);
	}
	
	// Step 2: Remove all edges from our database table
	{
		YDBLogVerbose(@"Removing all edges");
		
		sqlite3_stmt *statement = [parentConnection removeAllStatement];
		if (statement == NULL)
			return;
		
		// DELETE FROM "tableName";
		
		int status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
			
		sqlite3_reset(statement);
	}
	
	// Step 3: Flush pending change lists
	
	[parentConnection->edgeCache removeAllObjects];
	
	[parentConnection->protocolChanges removeAllObjects];
	[parentConnection->manualChanges removeAllObjects];
	[parentConnection->inserted removeAllObjects];
	[parentConnection->deletedOrder removeAllObjects];
	[parentConnection->deletedInfo removeAllObjects];
	
	[parentConnection->modifiedEdges removeAllObjects];
	[parentConnection->deletedEdges removeAllObjects];
	
	parentConnection->reset = YES;
}

- (void)flush
{
	YDBLogAutoTrace();
	
	if (!databaseTransaction->isReadWriteTransaction) return;
	
	isFlushing = YES;
	
	__block NSMutableArray *unprocessedEdges = nil;
	
	// STEP 0:
	//
	// Setup block to process a given array of edges.
	// The array must be preprocessed using one of the proper preprocess methods.
	// The preprocess methods will properly set the edgeAction and flags for each edge.
	// So this block need only look at the edgeAction and flags to decide how to process each edge.
	
	void (^ProcessEdges)(NSArray *edges) = ^(NSArray *edges){ @autoreleasepool{
		
		for (YapDatabaseRelationshipEdge *edge in edges)
		{
			if (edge->action == YDB_EdgeAction_None)
			{
				// No edge processing required.
				// Edge previously existed and didn't change.
			}
			else if (edge->action == YDB_EdgeAction_Insert)
			{
				// New edge added.
				// Insert into database.
				
				[self insertEdge:edge];
			}
			else if (edge->action == YDB_EdgeAction_Update)
			{
				// Edge modified (nodeDeleteRules changed)
				// Update row in database.
				
				[self updateEdge:edge];
			}
			else if (edge->action == YDB_EdgeAction_Delete)
			{
				// The edge is marked for deletion for one of the following reasons
				//
				// - Both source and destination deleted
				// - Only source was deleted
				// - Only destination was deleted
				// - Bad edge (invalid source or destination node)
				// - Edge manually deleted via source object (same as source deleted)
				
				BOOL edgeProcessed = YES;
				
				BOOL srcDeleted = (edge->flags & (YDB_EdgeFlags_SourceDeleted      | YDB_EdgeFlags_BadSource));
				BOOL dstDeleted = (edge->flags & (YDB_EdgeFlags_DestinationDeleted | YDB_EdgeFlags_BadDestination));
				BOOL dstFileURL = (edge->state & YDB_EdgeState_DestinationFileURL);
				
				if (dstFileURL) {
					[self lookupEdgeDestinationFileURL:edge];
				}
				
				if (srcDeleted && dstFileURL)
				{
					// The source node was deleted.
					//
					// Process the destination file according to nodeDeleteRules.
					
					if (edge->nodeDeleteRules & YDB_DeleteDestinationIfAllSourcesDeleted)
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
					else if (edge->nodeDeleteRules & YDB_DeleteDestinationIfSourceDeleted)
					{
						// Mark the file for deletion
						
						if (edge->destinationFileURL) {
							[parentConnection->filesToDelete addObject:edge->destinationFileURL];
						}
					}
				}
				else if (srcDeleted && !dstDeleted && !dstFileURL)
				{
					// The source node was deleted.
					// The destination node was not deleted.
					//
					// Process the destination node according to nodeDeleteRules.
					
					if (edge->nodeDeleteRules & YDB_DeleteDestinationIfAllSourcesDeleted)
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
					else if (edge->nodeDeleteRules & YDB_DeleteDestinationIfSourceDeleted)
					{
						// Delete the destination node
						
						YDBLogVerbose(@"Deleting destination node: key(%@) collection(%@)",
						              edge->destinationKey, edge->destinationCollection);
						
						__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
						  (YapDatabaseReadWriteTransaction *)databaseTransaction;
						
						[self lookupEdgeDestinationCollectionKey:edge];
						[databaseRwTransaction removeObjectForKey:edge->destinationKey
						                             inCollection:edge->destinationCollection
						                                withRowid:edge->destinationRowid];
					}
					else if (edge->nodeDeleteRules & YDB_NotifyIfSourceDeleted)
					{
						// Notify the destination node
						
						[self lookupEdgeDestinationCollectionKey:edge];
						id destinationNode = [databaseTransaction objectForKey:edge->destinationKey
						                                          inCollection:edge->destinationCollection
						                                             withRowid:edge->destinationRowid];
						
						SEL selector = @selector(yapDatabaseRelationshipEdgeDeleted:withReason:);
						if ([destinationNode respondsToSelector:selector])
						{
							id updatedDestinationNode =
							  [destinationNode yapDatabaseRelationshipEdgeDeleted:edge
							                                           withReason:YDB_SourceNodeDeleted];
							
							if (updatedDestinationNode)
							{
								__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
								  (YapDatabaseReadWriteTransaction *)databaseTransaction;
								
								[databaseRwTransaction replaceObject:updatedDestinationNode
								                              forKey:edge->destinationKey
								                        inCollection:edge->destinationCollection
								                           withRowid:edge->destinationRowid
								                    serializedObject:nil];
							}
						}
					}
				}
				else if (!srcDeleted && dstDeleted && !dstFileURL)
				{
					// Only destination node was deleted
					
					if (edge->nodeDeleteRules & YDB_DeleteSourceIfAllDestinationsDeleted)
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
					else if (edge->nodeDeleteRules & YDB_DeleteSourceIfDestinationDeleted)
					{
						// Delete the source node
						
						YDBLogVerbose(@"Deleting source node: key(%@) collection(%@)",
						              edge->sourceKey, edge->sourceCollection);
						
						__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
						  (YapDatabaseReadWriteTransaction *)databaseTransaction;
						
						[self lookupEdgeSourceCollectionKey:edge];
						[databaseRwTransaction removeObjectForKey:edge->sourceKey
						                             inCollection:edge->sourceCollection
						                                withRowid:edge->sourceRowid];
					}
					else if (edge->nodeDeleteRules & YDB_NotifyIfDestinationDeleted)
					{
						// Notify the source node
						
						[self lookupEdgeSourceCollectionKey:edge];
						id sourceNode = [databaseTransaction objectForKey:edge->sourceKey
						                                     inCollection:edge->sourceCollection
						                                        withRowid:edge->sourceRowid];
						
						SEL selector = @selector(yapDatabaseRelationshipEdgeDeleted:withReason:);
						if ([sourceNode respondsToSelector:selector])
						{
							id updatedSourceNode =
							  [sourceNode yapDatabaseRelationshipEdgeDeleted:edge
							                                      withReason:YDB_DestinationNodeDeleted];
							
							if (updatedSourceNode)
							{
								__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
								  (YapDatabaseReadWriteTransaction *)databaseTransaction;
								
								[databaseRwTransaction replaceObject:updatedSourceNode
								                              forKey:edge->sourceKey
								                        inCollection:edge->sourceCollection
								                           withRowid:edge->sourceRowid
								                    serializedObject:nil];
							}
						}
					}
				}
				
				if (edge->flags & YDB_EdgeFlags_EdgeNotInDatabase)
				{
					// The edge was added and deleted within the same transaction.
					// This might happen in some situations,
					// or if we're testing the extension,
					// or if a bad edge was created (source or destination node don't exist).
					//
					// Whatever the case, we don't need to attempt to delete the edge from the database.
					// In fact, we must not run the code because the edge->edgeRowid is invalid.
				}
				else
				{
					// Remove the edge from disk.
					
					[self deleteEdge:edge];
				}
				
				// If we couldn't process the edge, then add to pendingEdges array.
				// We'll come back later and process the edge after normal processing has completed.
				
				if (!edgeProcessed)
				{
					if (unprocessedEdges == nil)
						unprocessedEdges = [NSMutableArray array];
					
					[unprocessedEdges addObject:edge];
				}
				
			} // end else if (edge->edgeAction == YDB_EdgeAction_Delete)
			
		} // end for (YapDatabaseRelationshipEdge *edge in edges)
		
	}}; // end block ProcessEdges(NSMutableArray *edges)
	
	
	// STEP 1:
	//
	// Process all protocol edges that have been set during the transaction.
	// This includes:
	// - merging new edge lists with existing edge lists
	// - writing new edges to the database
	// - writing modified edges to the database (changed nodeDeleteRules)
	// - deleting edges that were manually removed from the list
	
	[parentConnection->protocolChanges enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop){
		
		__unsafe_unretained NSNumber *srcRowidNumber = (NSNumber *)key;
		__unsafe_unretained NSMutableArray *protocolEdges = (NSMutableArray *)obj;
		
		if ([parentConnection->inserted containsObject:srcRowidNumber])
		{
			// The src node is new, so all the edges are new.
			// Thus no need to merge the edges with a previous set of edges.
			//
			// So just enumerate over the edges, and attempt to fill in all the destinationRowid values.
			// If either of the edge's nodes were deleted, mark accordingly.
			
			[self preprocessProtocolEdges:protocolEdges forInsertedSource:[srcRowidNumber longLongValue]];
		}
		else
		{
			// The src node was updated, so the edges may have changed.
			//
			// We need to merge the new list with the existing list of edges in the database.
			
			[self preprocessProtocolEdges:protocolEdges forUpdatedSource:[srcRowidNumber longLongValue]];
		}
		
		// The edges list has now been preprocessed,
		// and all the various flags for each edge have been set.
		//
		// We're ready for normal edge processing.
		
		ProcessEdges(protocolEdges);
	}];
	
	[parentConnection->protocolChanges removeAllObjects];
	
	// STEP 2:
	//
	// Process all manual edges that have been set during the transaction.
	
	[parentConnection->manualChanges enumerateKeysAndObjectsUsingBlock:^(id __unused key, id obj, BOOL __unused *stop) {
		
	//	__unsafe_unretained NSString *edgeName = (NSString *)key;
		__unsafe_unretained NSMutableArray *manualEdges = (NSMutableArray *)obj;
		
		[self preprocessManualEdges:manualEdges];
		
		// The edges list has now been preprocessed,
		// and all the various flags for each edge have been set.
		//
		// We're ready for normal edge processing.
		
		ProcessEdges(manualEdges);
	}];
	
	[parentConnection->manualChanges removeAllObjects];
	
	// STEP 3:
	//
	// Revisit the unprocessed edges from steps 1 & 2.
	// That is, those edges that were deleted, but had nodeDeleteRules of either
	// - YDB_DeleteDestinationIfAllSourcesDeleted
	// - YDB_DeleteSourceIfAllDestinationsDeleted
	//
	// We were unable to fetch the remaining edge count earlier.
	// But we're ready to do so now.
	
	for (YapDatabaseRelationshipEdge *edge in unprocessedEdges)
	{
		if (edge->state & YDB_EdgeState_DestinationFileURL)
		{
			if (edge->nodeDeleteRules & YDB_DeleteDestinationIfAllSourcesDeleted)
			{
				// Delete destination node IF there are no other edges pointing to it with the same name
				
				int64_t count = [self edgeCountWithDestinationFileURL:edge->destinationFileURL
				                                                 name:edge->name
				                                      excludingSource:edge->sourceRowid];
				if (count == 0)
				{
					// Mark the file for deletion
					
					if (edge->destinationFileURL) {
						[parentConnection->filesToDelete addObject:edge->destinationFileURL];
					}
				}
			}
		}
		else // if (!(edge->state & YDB_EdgeState_DestinationFileURL))
		{
			if (edge->nodeDeleteRules & YDB_DeleteDestinationIfAllSourcesDeleted)
			{
				if ([parentConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
				{
					// Destination node already deleted
				}
				else
				{
					// Delete destination node IF there are no other edges pointing to it with the same name
					
					int64_t count = [self edgeCountWithDestination:edge->destinationRowid
					                                          name:edge->name
					                               excludingSource:edge->sourceRowid];
					if (count == 0)
					{
						YDBLogVerbose(@"Deleting destination node: key(%@) collection(%@)",
						              edge->destinationKey, edge->destinationCollection);
						
						__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
						  (YapDatabaseReadWriteTransaction *)databaseTransaction;
						
						[self lookupEdgeDestinationCollectionKey:edge];
						[databaseRwTransaction removeObjectForKey:edge->destinationKey
						                             inCollection:edge->destinationCollection
						                                withRowid:edge->destinationRowid];
					}
				}
			}
			else if (edge->nodeDeleteRules & YDB_DeleteSourceIfAllDestinationsDeleted)
			{
				if ([parentConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
				{
					// Source node already deleted
				}
				else
				{
					// Delete source node IF there are no other edges pointing from it with the same name
					
					int64_t count = [self edgeCountWithSource:edge->sourceRowid
					                                     name:edge->name
					                     excludingDestination:edge->destinationRowid];
					if (count == 0)
					{
						YDBLogVerbose(@"Deleting source node: key(%@) collection(%@)",
						              edge->sourceKey, edge->sourceCollection);
						
						__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
						  (YapDatabaseReadWriteTransaction *)databaseTransaction;
						
						[self lookupEdgeSourceCollectionKey:edge];
						[databaseRwTransaction removeObjectForKey:edge->sourceKey
						                             inCollection:edge->sourceCollection
						                                withRowid:edge->sourceRowid];
					}
				}
			}
		}
	}
	
	unprocessedEdges = nil;
	
	// STEP 4:
	//
	// Process all the deleted nodes.
	// For each deleted node we're going to enumerate all connected edges.
	// First the edges where the deleted node is the source.
	// Then the edges where the deleted node is the destination.
	//
	// Note that at this point, the database is up-to-date (we've written all changes).
	// So we can simply enumerate and query the database without any fuss.
	
	NSUInteger i = 0;
	while (i < [parentConnection->deletedOrder count])
	{
		NSNumber *deletedRowidNumber = [parentConnection->deletedOrder objectAtIndex:i];
		int64_t deletedRowid = deletedRowidNumber.longLongValue;
		
		YapCollectionKey *deletedCollectionKey = [parentConnection->deletedInfo objectForKey:deletedRowidNumber];
		
		{ // Enumerate all edges where source node is the deleted node
	
			int64_t srcRowid = deletedRowid;
			YapCollectionKey *src = deletedCollectionKey;
			
			[self enumerateExistingEdgesWithSource:srcRowid usingBlock:^(YapDatabaseRelationshipEdge *edge) {
				
				// Reminder:
				//
				// When using the enumerateExistingEdges...:: method,
				// the 'edges' parameter is only guaranteed to contain the information that's in the database row.
				//
				// To be more specific, they'll have the rowid's but the following values may be nil:
				// - sourceKey/sourceCollection
				// - destinationKey/destinationCollection
				// - destinationFileURL
				
				if (edge->state & YDB_EdgeState_DestinationFileURL)
				{
					if (edge->nodeDeleteRules & YDB_DeleteDestinationIfAllSourcesDeleted)
					{
						// Delete the destination node IF there are no other edges pointing to it with the same name
						
						if (!(edge->state & YDB_EdgeState_HasDestinationFileURL))
						{
							[self lookupEdgeDestinationFileURL:edge];
						}
						
						if (edge->destinationFileURL)
						{
							int64_t count = [self edgeCountWithDestinationFileURL:edge->destinationFileURL
							                                                 name:edge->name
							                                      excludingSource:srcRowid];
							if (count == 0)
							{
								// Mark the file for deletion
								
								[parentConnection->filesToDelete addObject:edge->destinationFileURL];
							}
						}
					}
					else if (edge->nodeDeleteRules & YDB_DeleteDestinationIfSourceDeleted)
					{
						// Mark the file for deletion
						
						if (!(edge->state & YDB_EdgeState_HasDestinationFileURL))
						{
							[self lookupEdgeDestinationFileURL:edge];
						}
						
						if (edge->destinationFileURL) {
							[parentConnection->filesToDelete addObject:edge->destinationFileURL];
						}
					}
				}
				else // if (!(edge->state & YDB_EdgeState_DestinationFileURL))
				{
					if ([parentConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
					{
						// Both source and destination node have been deleted
					}
					else
					{
						if (edge->nodeDeleteRules & YDB_DeleteDestinationIfAllSourcesDeleted)
						{
							// Delete the destination node IF there are no other edges pointing to it with the same name
							
							int64_t count = [self edgeCountWithDestination:edge->destinationRowid
							                                          name:edge->name
							                               excludingSource:srcRowid];
							if (count == 0)
							{
								YapCollectionKey *dst = nil;
								
								if (edge->destinationKey == nil)
								{
									dst = [databaseTransaction collectionKeyForRowid:edge->destinationRowid];
									
									edge->destinationKey = dst.key;
									edge->destinationCollection = dst.collection;
								}
								
								YDBLogVerbose(@"Deleting destination node: key(%@) collection(%@)",
								              edge->destinationKey, edge->destinationCollection);
								
								__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
								  (YapDatabaseReadWriteTransaction *)databaseTransaction;
								
								if (dst)
									[databaseRwTransaction removeObjectForCollectionKey:dst
									                                          withRowid:edge->destinationRowid];
								else
									[databaseRwTransaction removeObjectForKey:edge->destinationKey
									                             inCollection:edge->destinationCollection
									                                withRowid:edge->destinationRowid];
							}
						}
						else if (edge->nodeDeleteRules & YDB_DeleteDestinationIfSourceDeleted)
						{
							// Delete the destination node
							
							YapCollectionKey *dst = nil;
							
							if (edge->destinationKey == nil)
							{
								dst = [databaseTransaction collectionKeyForRowid:edge->destinationRowid];
								
								edge->destinationKey = dst.key;
								edge->destinationCollection = dst.collection;
							}
							
							YDBLogVerbose(@"Deleting destination node: key(%@) collection(%@)",
							              edge->destinationKey, edge->destinationCollection);
							
							__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
							  (YapDatabaseReadWriteTransaction *)databaseTransaction;
							
							if (dst)
								[databaseRwTransaction removeObjectForCollectionKey:dst
								                                          withRowid:edge->destinationRowid];
							else
								[databaseRwTransaction removeObjectForKey:edge->destinationKey
								                             inCollection:edge->destinationCollection
								                                withRowid:edge->destinationRowid];
						}
						else if (edge->nodeDeleteRules & YDB_NotifyIfSourceDeleted)
						{
							// Notify the destination node
							
							if (edge->sourceKey == nil)
							{
								edge->destinationKey = src.key;
								edge->destinationCollection = src.collection;
							}
							
							YapCollectionKey *dst = nil;
							
							if (edge->destinationKey == nil)
							{
								dst = [databaseTransaction collectionKeyForRowid:edge->destinationRowid];
								
								edge->destinationKey = dst.key;
								edge->destinationCollection = dst.collection;
							}
							
							id dstNode = nil;
							
							if (dst)
								dstNode = [databaseTransaction objectForCollectionKey:dst
								                                            withRowid:edge->destinationRowid];
							else
								dstNode = [databaseTransaction objectForKey:edge->destinationKey
								                               inCollection:edge->destinationCollection
								                                  withRowid:edge->destinationRowid];
							
							SEL selector = @selector(yapDatabaseRelationshipEdgeDeleted:withReason:);
							if ([dstNode respondsToSelector:selector])
							{
								id updatedDstNode =
								  [dstNode yapDatabaseRelationshipEdgeDeleted:edge withReason:YDB_SourceNodeDeleted];
								
								if (updatedDstNode)
								{
									__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
									  (YapDatabaseReadWriteTransaction *)databaseTransaction;
									
									[databaseRwTransaction replaceObject:updatedDstNode
									                              forKey:edge->destinationKey
									                        inCollection:edge->destinationCollection
									                           withRowid:edge->destinationRowid
									                    serializedObject:nil];
								}
							}
						}
					}
				} // end else if (!dstFilePath)
			}]; // end enumerateExistingRowsWithSrc:usingBlock:
		
		} // end "Enumerate all edges where source node is the deleted node"
		
		
		{ // Enumerate all edges where destination node is the deleted node

			int64_t dstRowid = deletedRowid;
			YapCollectionKey *dst = deletedCollectionKey;
			
			[self enumerateExistingEdgesWithDestination:dstRowid usingBlock:^(YapDatabaseRelationshipEdge *edge) {
				
				// Reminder:
				//
				// When using the enumerateExistingEdges...:: method,
				// the 'edges' parameter is only guaranteed to contain the information that's in the database row.
				//
				// To be more specific, they'll have the rowid's but the following values may be nil:
				// - sourceKey/sourceCollection
				// - destinationKey/destinationCollection
				// - destinationFileURL
				
				if ([parentConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
				{
					// Both source and destination node have been deleted
				}
				else
				{
					if (edge->nodeDeleteRules & YDB_DeleteSourceIfAllDestinationsDeleted)
					{
						// Delete the source node IF there are no other edges pointing from it with the same name
						
						int64_t count = [self edgeCountWithSource:edge->sourceRowid
						                                     name:edge->name
						                     excludingDestination:dstRowid];
						if (count == 0)
						{
							YapCollectionKey *src = nil;
							
							if (edge->sourceKey == nil)
							{
								src = [databaseTransaction collectionKeyForRowid:edge->sourceRowid];
								
								edge->sourceKey = src.key;
								edge->sourceCollection = src.collection;
							}
							
							YDBLogVerbose(@"Deleting source node: key(%@) collection(%@)",
							              edge->sourceKey, edge->sourceCollection);
							
							__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
							  (YapDatabaseReadWriteTransaction *)databaseTransaction;
							
							if (src)
								[databaseRwTransaction removeObjectForCollectionKey:src
								                                          withRowid:edge->sourceRowid];
							else
								[databaseRwTransaction removeObjectForKey:edge->sourceKey
								                             inCollection:edge->sourceCollection
								                                withRowid:edge->sourceRowid];
						}
					}
					else if (edge->nodeDeleteRules & YDB_DeleteSourceIfDestinationDeleted)
					{
						// Delete the source node
						
						YapCollectionKey *src = nil;
						
						if (edge->sourceKey == nil)
						{
							src = [databaseTransaction collectionKeyForRowid:edge->sourceRowid];
							
							edge->sourceKey = src.key;
							edge->sourceCollection = src.collection;
						}
						
						YDBLogVerbose(@"Deleting source node: key(%@) collection(%@)",
						              edge->sourceKey, edge->sourceCollection);
						
						__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
						  (YapDatabaseReadWriteTransaction *)databaseTransaction;
						
						if (src)
							[databaseRwTransaction removeObjectForCollectionKey:src
							                                          withRowid:edge->sourceRowid];
						else
							[databaseRwTransaction removeObjectForKey:edge->sourceKey
							                             inCollection:edge->sourceCollection
							                                withRowid:edge->sourceRowid];
					}
					else if (edge->nodeDeleteRules & YDB_NotifyIfDestinationDeleted)
					{
						// Notify the source node
						
						if (edge->destinationKey == nil)
						{
							edge->destinationKey = dst.key;
							edge->destinationCollection = dst.collection;
						}
						
						YapCollectionKey *src = nil;
						
						if (edge->sourceKey == nil)
						{
							src = [databaseTransaction collectionKeyForRowid:edge->sourceRowid];
							
							edge->sourceKey = src.key;
							edge->sourceCollection = src.collection;
						}
						
						id srcNode = nil;
						
						if (src)
							srcNode = [databaseTransaction objectForCollectionKey:src withRowid:edge->sourceRowid];
						else
							srcNode = [databaseTransaction objectForKey:edge->sourceKey
						                                   inCollection:edge->sourceCollection
						                                      withRowid:edge->sourceRowid];
						
						SEL selector = @selector(yapDatabaseRelationshipEdgeDeleted:withReason:);
						if ([srcNode respondsToSelector:selector])
						{
							id updatedSrcNode =
							  [srcNode yapDatabaseRelationshipEdgeDeleted:edge withReason:YDB_DestinationNodeDeleted];
							
							if (updatedSrcNode)
							{
								__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
								  (YapDatabaseReadWriteTransaction *)databaseTransaction;
								
								[databaseRwTransaction replaceObject:updatedSrcNode
								                              forKey:edge->sourceKey
								                        inCollection:edge->sourceCollection
								                           withRowid:edge->sourceRowid
								                    serializedObject:nil];
							}
						}
					}
				}
				
			}]; // end enumerateExistingRowsWithDst:usingBlock:
		
		} // end "Enumerate all edges where destination node is the deleted node"
		
		// Delete all the edges from the database where src or dst is the deleted node
		[self deleteEdgesWithSourceOrDestination:deletedRowid];
		
		i++;
	}
	
	[parentConnection->inserted removeAllObjects];
	[parentConnection->deletedInfo removeAllObjects];
	[parentConnection->deletedOrder removeAllObjects];
	
	// DONE !
	
	isFlushing = NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cleanup & Commit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses may OPTIONALLY implement this method.
 * This method is only called if within a readwrite transaction.
 *
 * Subclasses should ONLY implement this method if they need to make changes to the 'database' table.
 * That is, the main collection/key/value table that directly stores the user's objects.
 *
 * Return NO if the extension does not directly modify the main database table.
 * Return YES if the extension does modify the main database table,
 * regardless of whether it made changes during this invocation.
 * 
 * This method may be invoked several times in a row.
**/
- (BOOL)flushPendingChangesToMainDatabaseTable
{
	YDBLogAutoTrace();
	
	// Flush any pending changes
	
	if ([parentConnection->protocolChanges count] > 0 ||
		[parentConnection->manualChanges   count] > 0 ||
		[parentConnection->deletedInfo     count] > 0 ||
		[parentConnection->deletedOrder    count] > 0  )
	{
		[self flush];
	}
	
	return YES;
}

/**
 * This method is only called if within a readwrite transaction.
**/
- (void)didCommitTransaction
{
	YDBLogAutoTrace();
	
	// Run file deletion routine (if needed)
	
	if ([parentConnection->filesToDelete count] > 0)
	{
		// Note: No need to make a copy.
		// We will set parentConnection->filesToDelete to nil instead.
		//
		// See: [parentConnection postCommitCleanup];
		
		NSSet *filesToDelete = parentConnection->filesToDelete;
		
		dispatch_queue_t fileManagerQueue = [parentConnection->parent fileManagerQueue];
		dispatch_async(fileManagerQueue, ^{ @autoreleasepool {
			
			NSFileManager *fileManager = [NSFileManager defaultManager];
			
			for (NSURL *fileURL in filesToDelete)
			{
				NSError *error = nil;
				if (![fileManager removeItemAtURL:fileURL error:&error])
				{
					YDBLogWarn(@"Error removing file (%@): %@", [fileURL path], error);
				}
			}
		}});
	}
	
	// Commit is complete.
	// Cleanup time.
	
	[parentConnection postCommitCleanup];
	
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	parentConnection = nil;    // Do not remove !
	databaseTransaction = nil; // Do not remove !
}

/**
 * This method is only called if within a readwrite transaction.
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
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleInsertObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id __unused)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	if (isFlushing)
	{
		YDBLogError(@"Unable to handle insert hook during flush processing");
		return;
	}
	
	__unsafe_unretained YapDatabaseRelationshipOptions *options = parentConnection->parent->options;
	if (options->disableYapDatabaseRelationshipNodeProtocol) {
		return;
	}
	if (options->allowedCollections && ![options->allowedCollections isAllowed:collectionKey.collection]) {
		return;
	}
	
	NSNumber *rowidNumber = @(rowid);
	
	// Request edges from object
	
	NSArray *givenEdges = nil;
	
//	if ([object conformsToProtocol:@protocol(YapDatabaseRelationshipNode)])
	if ([object respondsToSelector:@selector(yapDatabaseRelationshipEdges)])
	{
		givenEdges = [object yapDatabaseRelationshipEdges];
	}
	
	// Make copies, and fill in missing src information
	
	NSMutableArray *edges = nil;
	
	if (givenEdges.count > 0)
	{
		edges = [NSMutableArray arrayWithCapacity:[givenEdges count]];
		
		__unsafe_unretained NSString *collection = collectionKey.collection;
		__unsafe_unretained NSString *key = collectionKey.key;
		
		for (YapDatabaseRelationshipEdge *edge in givenEdges)
		{
			YapDatabaseRelationshipEdge *cleanEdge = [edge copyWithSourceKey:key collection:collection rowid:rowid];
			cleanEdge->isManualEdge = NO; // Force proper value
			
			[edges addObject:cleanEdge];
		}
	}
	
	// We know this is an insert, so item is new.
	
	if (edges.count > 0)
	{
		// We store the fact that this item was inserted.
		// That way we can later skip the step where we query the database for existing edges.
		
		[parentConnection->protocolChanges setObject:edges forKey:rowidNumber];
		[parentConnection->inserted addObject:rowidNumber];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleUpdateObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id __unused)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	if (isFlushing)
	{
		YDBLogError(@"Unable to handle update hook during flush processing");
		return;
	}
	
	__unsafe_unretained YapDatabaseRelationshipOptions *options = parentConnection->parent->options;
	if (options->disableYapDatabaseRelationshipNodeProtocol) {
		return;
	}
	if (options->allowedCollections && ![options->allowedCollections isAllowed:collectionKey.collection]) {
		return;
	}
	
	// Request edges from object
	
	NSArray *givenEdges = nil;
	
//	if ([object conformsToProtocol:@protocol(YapDatabaseRelationshipNode)])
	if ([object respondsToSelector:@selector(yapDatabaseRelationshipEdges)])
	{
		givenEdges = [object yapDatabaseRelationshipEdges];
	}
	
	NSMutableArray *edges = nil;
	
	if (givenEdges.count > 0)
	{
		edges = [NSMutableArray arrayWithCapacity:[givenEdges count]];
		
		__unsafe_unretained NSString *collection = collectionKey.collection;
		__unsafe_unretained NSString *key = collectionKey.key;
		
		for (YapDatabaseRelationshipEdge *edge in givenEdges)
		{
			YapDatabaseRelationshipEdge *cleanEdge = [edge copyWithSourceKey:key collection:collection rowid:rowid];
			cleanEdge->isManualEdge = NO; // Force proper value
			
			[edges addObject:cleanEdge];
		}
	}
	else
	{
		edges = [NSMutableArray arrayWithCapacity:0];
	}
	
	[parentConnection->protocolChanges setObject:edges forKey:@(rowid)];
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
	
	__unsafe_unretained YapDatabaseRelationshipOptions *options = parentConnection->parent->options;
	if (options->disableYapDatabaseRelationshipNodeProtocol) {
		return;
	}
	if (options->allowedCollections && ![options->allowedCollections isAllowed:collectionKey.collection]) {
		return;
	}
	
	NSArray *givenEdges = nil;
	
//	if ([object conformsToProtocol:@protocol(YapDatabaseRelationshipNode)])
	if ([object respondsToSelector:@selector(yapDatabaseRelationshipEdges)])
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
			YapDatabaseRelationshipEdge *cleanEdge = [edge copyWithSourceKey:key collection:collection rowid:rowid];
			cleanEdge->isManualEdge = NO; // Force proper value
			
			[edges addObject:cleanEdge];
		}
	}
	else
	{
		edges = [NSMutableArray arrayWithCapacity:0];
	}
	
	[parentConnection->protocolChanges setObject:edges forKey:@(rowid)];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleReplaceMetadata:(id __unused)metadata
             forCollectionKey:(YapCollectionKey __unused *)collectionKey
                    withRowid:(int64_t __unused)rowid
{
	YDBLogAutoTrace();
	
	// Nothing to do in this extension for metadata
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleTouchObjectForCollectionKey:(YapCollectionKey __unused *)collectionKey withRowid:(int64_t __unused)rowid
{
	YDBLogAutoTrace();
	
	// Nothing to do in this extension for touches.
	// We may change this in the future if this decision proves misguided.
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleTouchMetadataForCollectionKey:(YapCollectionKey __unused *)collectionKey withRowid:(int64_t __unused)rowid
{
	YDBLogAutoTrace();
	
	// Nothing to do in this extension for touches.
	// We may change this in the future if this decision proves misguided.
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleTouchRowForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Nothing to do in this extension for touches.
	// We may change this in the future if this decision proves misguided.
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Note: This method may be called during flush processing due to an edge's nodeDeleteRules.
	
	NSNumber *srcRowidNumber = @(rowid);
	
	[parentConnection->deletedOrder addObject:srcRowidNumber];
	[parentConnection->deletedInfo setObject:collectionKey forKey:srcRowidNumber];
	
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
		YDBLogError(@"Unable to handle multi-remove hook during flush processing");
		return;
	}
	
	NSUInteger i = 0;
	for (NSNumber *srcRowidNumber in rowids)
	{
		NSString *key = [keys objectAtIndex:i];
		YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		[parentConnection->deletedOrder addObject:srcRowidNumber];
		[parentConnection->deletedInfo setObject:collectionKey forKey:srcRowidNumber];
		
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
		YDBLogError(@"Unable to handle remove-all hook during flush processing");
		return;
	}
	
	[self removeAllEdges];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API - Fetch
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Shortcut for fetching the source object for the given edge.
 * Equivalent to:
 *
 * [transaction objectForKey:edge.sourceKey inCollection:edge.sourceCollection];
**/
- (id)sourceNodeForEdge:(YapDatabaseRelationshipEdge *)edge
{
	if (edge == nil) return nil;
	
	if ((edge->state & YDB_EdgeState_HasSourceRowid))
	{
		return [databaseTransaction objectForKey:edge->sourceKey
		                            inCollection:edge->sourceCollection
		                               withRowid:edge->sourceRowid];
	}
	else
	{
		return [databaseTransaction objectForKey:edge->sourceKey inCollection:edge->sourceCollection];
	}
}

/**
 * Shortcut for fetching the destination object for the given edge.
 * Equivalent to:
 *
 * [transaction objectForKey:edge.destinationKey inCollection:edge.destinationCollection];
**/
- (id)destinationNodeForEdge:(YapDatabaseRelationshipEdge *)edge
{
	if (edge == nil) return nil;
	if (edge->state & YDB_EdgeState_DestinationFileURL) return nil;
	
	if ((edge->state & YDB_EdgeState_HasDestinationRowid))
	{
		return [databaseTransaction objectForKey:edge->destinationKey
		                            inCollection:edge->destinationCollection
		                               withRowid:edge->destinationRowid];
	}
	else
	{
		return [databaseTransaction objectForKey:edge->destinationKey inCollection:edge->destinationCollection];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private API - Enumerate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Enumerates every edge in the graph with the given name.
 *
 * @param name
 *   The name of the edge (case sensitive).
 * 
 * IMPORTANT:
 * This internal method does NOT prep the edge for the public (e.g. srcKey/dstKey/dstFileURL may be nil).
**/
- (void)_enumerateEdgesWithName:(NSString *)name
                     usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	if (name == nil) return;
	if (block == NULL) return;
	
	BOOL stop = NO;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	//
	// Note: The findChangesMatchingXXX API ensures that the returned edges have
	// their srcRowid, dstRowid & dstFileURL set (if needed).
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name];
	
	// Enumerate the items already in the database
	
	BOOL needsFinalize;
	sqlite3_stmt *statement = [parentConnection enumerateForNameStatement:&needsFinalize];
	if (statement == NULL)
		return;
	
	// SELECT "rowid", "src", "dst", "rules", "manual" FROM "tableName" WHERE "name" = ?;
	
	int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
	int const column_idx_src    = SQLITE_COLUMN_START + 1;
	int const column_idx_dst    = SQLITE_COLUMN_START + 2;
	int const column_idx_rules  = SQLITE_COLUMN_START + 3;
	int const column_idx_manual = SQLITE_COLUMN_START + 4;
	int const bind_idx_name     = SQLITE_BIND_START;
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, name);
	sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		YapDatabaseRelationshipEdge *edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
		if (edge)
		{
			// Make sure cached edge has srcRowid & dstRowid
			
			edge->sourceRowid = sqlite3_column_int64(statement, column_idx_src);
			edge->state |= YDB_EdgeState_HasSourceRowid;
			
			if (sqlite3_column_type(statement, column_idx_dst) == SQLITE_INTEGER)
			{
				edge->destinationRowid = sqlite3_column_int64(statement, column_idx_dst);
				edge->state |= YDB_EdgeState_HasDestinationRowid;
			}
		}
		else
		{
			int64_t srcRowid = sqlite3_column_int64(statement, column_idx_src);
			
			int64_t dstRowid = 0;
			NSData *dstFileURLData = nil;
			
			int column_type = sqlite3_column_type(statement, column_idx_dst);
			if (column_type == SQLITE_INTEGER)
			{
				dstRowid = sqlite3_column_int64(statement, column_idx_dst);
			}
			else if (column_type == SQLITE_BLOB)
			{
				const void *blob = sqlite3_column_blob(statement, column_idx_dst);
				int blobSize = sqlite3_column_bytes(statement, column_idx_dst);
				
				dstFileURLData = [NSData dataWithBytes:(void *)blob length:blobSize];
			}
			
			int rules = sqlite3_column_int(statement, column_idx_rules);
			BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
			
			edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
			                                                         name:name
			                                                     srcRowid:srcRowid
			                                                     dstRowid:dstRowid
			                                                      dstData:dstFileURLData
			                                                        rules:rules
			                                                       manual:manual];
			
			[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
		}
		
		// Does the edge on disk have a corresponding edge in memory that overrides it?
		
		BOOL isChangedEdge = NO;
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			if ((changedEdge->isManualEdge == edge->isManualEdge) &&
			    [self edge:changedEdge matchesSource:edge]  &&
			    [self edge:changedEdge matchesDestination:edge])
			{
				// Merge info between matching edges
				MergeInfoBetweenMatchingEdges(edge, changedEdge);
				if (edge->isManualEdge)
					edge->action = changedEdge->action;
				
				isChangedEdge = YES;
				[changedEdges removeObjectAtIndex:i];
				break;
			}
			
			i++;
		}
		
		// Check to see if the edge is broken (src or dst node has been deleted)
		
		if (edge->isManualEdge)
		{
			// Manual edges have explicitly declared actions (from the user)
			if (edge->action == YDB_EdgeAction_Delete)
			{
				// edge is marked for deletion
				continue;
			}
		}
		else if (!isChangedEdge)
		{
			// Protocol edges are replaced all at once (per source node)
			if ([parentConnection->protocolChanges ydb_containsKey:@(edge->sourceRowid)])
			{
				// all protocol edges on disk with this srcRowid have been overriden
				continue;
			}
		}
		
		if ([self isEdgeSourceDeleted:edge] ||
			[self isEdgeDestinationDeleted:edge])
		{
			continue;
		}
		
		block(edge, &stop);
		if (stop) break;
	}
	
	if (status != SQLITE_DONE && !stop)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
	FreeYapDatabaseString(&_name);
	
	if (stop) return;
	
	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	for (YapDatabaseRelationshipEdge *edge in changedEdges)
	{
		if (edge->isManualEdge && (edge->action == YDB_EdgeAction_Delete))
		{
			// manual edge marked for deletion
			continue;
		}
		
		if ([self isEdgeSourceDeleted:edge] ||
			[self isEdgeDestinationDeleted:edge])
		{
			// source and/or destination node was deleted
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
 * 
 * IMPORTANT:
 * This internal method does NOT prep the edge for the public (e.g. srcKey/dstKey/dstFileURL may be nil).
**/
- (void)_enumerateEdgesWithName:(NSString *)name
                      sourceKey:(NSString *)srcKey
                     collection:(NSString *)srcCollection
                     usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	if (srcKey == nil) {
		[self enumerateEdgesWithName:name usingBlock:block];
		return;
	}
	if (block == NULL) return;
	
	if (srcCollection == nil)
		srcCollection = @"";
	
	int64_t srcRowid = 0;
	BOOL hasSrcRowid = [databaseTransaction getRowid:&srcRowid forKey:srcKey inCollection:srcCollection];
	
	BOOL stop = NO;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name
	                                                   sourceKey:srcKey
	                                                  collection:srcCollection
	                                                       rowid:(hasSrcRowid ? @(srcRowid) : nil)];
	
	// Enumerate the items already in the database
	if (hasSrcRowid)
	{
		BOOL needsFinalize;
		sqlite3_stmt *statement;
		YapDatabaseString _name;
		
		if (name)
		{
			statement = [parentConnection enumerateForSrcNameStatement:&needsFinalize];
			if (statement == NULL)
				return;
			
			// SELECT "rowid", "dst", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "name" = ?;",
			
			int const bind_idx_src   = SQLITE_BIND_START + 0;
			int const bind_idx_name  = SQLITE_BIND_START + 1;
			
			sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
			
			MakeYapDatabaseString(&_name, name);
			sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
		}
		else
		{
			statement = [parentConnection enumerateForSrcStatement:&needsFinalize];
			if (statement == NULL)
				return;
			
			// SELECT "rowid", "name", "dst", "rules", "manual" FROM "tableName" WHERE "src" = ?;
			
			int const bind_idx_src = SQLITE_BIND_START;
			
			sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
		}
		
		int status;
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			YapDatabaseRelationshipEdge *edge = nil;
			
			if (name)
			{
				// SELECT "rowid", "dst", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "name" = ?;",
				
				int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
				int const column_idx_dst    = SQLITE_COLUMN_START + 1;
				int const column_idx_rules  = SQLITE_COLUMN_START + 2;
				int const column_idx_manual = SQLITE_COLUMN_START + 3;
				
				int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
				
				edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
				if (edge)
				{
					// Make sure cached edge has srcRowid & dstRowid
					
					edge->sourceRowid = srcRowid;
					edge->state |= YDB_EdgeState_HasSourceRowid;
					
					if (sqlite3_column_type(statement, column_idx_dst) == SQLITE_INTEGER)
					{
						edge->destinationRowid = sqlite3_column_int64(statement, column_idx_dst);
						edge->state |= YDB_EdgeState_HasDestinationRowid;
					}
				}
				else
				{
					int64_t dstRowid = 0;
					NSData *dstFileURLData = nil;
					
					int column_type = sqlite3_column_type(statement, column_idx_dst);
					if (column_type == SQLITE_INTEGER)
					{
						dstRowid = sqlite3_column_int64(statement, column_idx_dst);
					}
					else if (column_type == SQLITE_BLOB)
					{
						const void *blob = sqlite3_column_blob(statement, column_idx_dst);
						int blobSize = sqlite3_column_bytes(statement, column_idx_dst);
						
						dstFileURLData = [NSData dataWithBytes:(void *)blob length:blobSize];
					}
					
					int rules = sqlite3_column_int(statement, column_idx_rules);
					BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
					
					edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
					                                                         name:name
					                                                     srcRowid:srcRowid
					                                                     dstRowid:dstRowid
					                                                      dstData:dstFileURLData
					                                                        rules:rules
					                                                       manual:manual];
					
					[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
				}
			}
			else // if (name == nil)
			{
				// SELECT "rowid", "name", "dst", "rules", "manual" FROM "tableName" WHERE "src" = ?;
				
				int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
				int const column_idx_name   = SQLITE_COLUMN_START + 1;
				int const column_idx_dst    = SQLITE_COLUMN_START + 2;
				int const column_idx_rules  = SQLITE_COLUMN_START + 3;
				int const column_idx_manual = SQLITE_COLUMN_START + 4;
				
				int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
				
				edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
				if (edge)
				{
					// Make sure cached edge has srcRowid & dstRowid
					
					edge->sourceRowid = srcRowid;
					edge->state |= YDB_EdgeState_HasSourceRowid;
					
					if (sqlite3_column_type(statement, column_idx_dst) == SQLITE_INTEGER)
					{
						edge->destinationRowid = sqlite3_column_int64(statement, column_idx_dst);
						edge->state |= YDB_EdgeState_HasDestinationRowid;
					}
				}
				else
				{
					const unsigned char *text = sqlite3_column_text(statement, column_idx_name);
					int textSize = sqlite3_column_bytes(statement, column_idx_name);
					
					NSString *edgeName =
					  [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
					
					int64_t dstRowid = 0;
					NSData *dstFileURLData = nil;
					
					int column_type = sqlite3_column_type(statement, column_idx_dst);
					if (column_type == SQLITE_INTEGER)
					{
						dstRowid = sqlite3_column_int64(statement, column_idx_dst);
					}
					else if (column_type == SQLITE_BLOB)
					{
						const void *blob = sqlite3_column_blob(statement, column_idx_dst);
						int blobSize = sqlite3_column_bytes(statement, column_idx_dst);
						
						dstFileURLData = [NSData dataWithBytes:(void *)blob length:blobSize];
					}
					
					int rules = sqlite3_column_int(statement, column_idx_rules);
					BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
					
					edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
					                                                         name:edgeName
					                                                     srcRowid:srcRowid
					                                                     dstRowid:dstRowid
					                                                      dstData:dstFileURLData
					                                                        rules:rules
					                                                       manual:manual];
					
					[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
				}
			}
			
			// Fill out known edge information (if missing)
			
			if (edge->sourceKey == nil)
			{
				edge->sourceKey = srcKey;
				edge->sourceCollection = srcCollection;
			}
			
			// Does the edge on disk have a corresponding edge in memory that overrides it?
			
			BOOL isChangedEdge = NO;
			NSUInteger i = 0;
			for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
			{
				// Note: we already know the source matches
				
				if ((changedEdge->isManualEdge == edge->isManualEdge) &&
				    [self edge:changedEdge matchesDestination:edge])
				{
					// Merge info between matching edges
					MergeInfoBetweenMatchingEdges(edge, changedEdge);
					if (edge->isManualEdge)
						edge->action = changedEdge->action;
					
					isChangedEdge = YES;
					[changedEdges removeObjectAtIndex:i];
					break;
				}
				
				i++;
			}
			
			// Check to see if the edge is broken (src or dst node has been deleted)
			
			if (edge->isManualEdge)
			{
				// Manual edges have explicitly declared actions (from the user)
				if (edge->action == YDB_EdgeAction_Delete)
				{
					// edge is marked for deletion
					continue;
				}
			}
			else if (!isChangedEdge)
			{
				// Protocol edges are replaced all at once (per source node)
				if ([parentConnection->protocolChanges ydb_containsKey:@(edge->sourceRowid)])
				{
					// all protocol edges on disk with this srcRowid have been overriden
					continue;
				}
			}
			
			if ([self isEdgeDestinationDeleted:edge])
			{
				continue;
			}
			
			block(edge, &stop);
			if (stop) break;
		}
		
		if (status != SQLITE_DONE && !stop)
		{
			YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite_enum_reset(statement,needsFinalize);
		if (name) {
			FreeYapDatabaseString(&_name);
		}
		
		if (stop) return;
		
	} // end if (hasSrcRowid)

	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	BOOL srcDeleted = hasSrcRowid ? NO : ([self rowidNumberForDeletedKey:srcKey inCollection:srcCollection] != nil);
	
	if (!srcDeleted)
	{
		for (YapDatabaseRelationshipEdge *edge in changedEdges)
		{
			if (edge->isManualEdge && (edge->action == YDB_EdgeAction_Delete))
			{
				// edge marked for deletion
				continue;
			}
			
			if ([self isEdgeDestinationDeleted:edge])
			{
				// broken edge (destination node deleted)
				continue;
			}
			
			block(edge, &stop);
			if (stop) break;
		}
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
 * 
 * IMPORTANT:
 * This internal method does NOT prep the edge for the public (e.g. srcKey/dstKey/dstFileURL may be nil).
**/
- (void)_enumerateEdgesWithName:(NSString *)name
                 destinationKey:(NSString *)dstKey
                     collection:(NSString *)dstCollection
                     usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	if (dstKey == nil) {
		[self enumerateEdgesWithName:name usingBlock:block];
		return;
	}
	if (block == NULL) return;
	
	if (dstCollection == nil)
		dstCollection = @"";
	
	int64_t dstRowid = 0;
	BOOL hasDstRowid = [databaseTransaction getRowid:&dstRowid forKey:dstKey inCollection:dstCollection];
	
	BOOL stop = NO;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name
	                                              destinationKey:dstKey
	                                                  collection:dstCollection
	                                                       rowid:(hasDstRowid ? @(dstRowid) : nil)];
	
	// Enumerate the items already in the database
	if (hasDstRowid)
	{
		BOOL needsFinalize;
		sqlite3_stmt *statement;
		YapDatabaseString _name;
		
		if (name)
		{
			statement = [parentConnection enumerateForDstNameStatement:&needsFinalize];
			if (statement == NULL)
				return;
			
			// SELECT "rowid", "src", "rules", "manual" FROM "tableName" WHERE "dst" = ? AND "name" = ?;
			
			int const bind_idx_dst  = SQLITE_BIND_START + 0;
			int const bind_idx_name = SQLITE_BIND_START + 1;
			
			sqlite3_bind_int64(statement, bind_idx_dst, dstRowid);
			
			MakeYapDatabaseString(&_name, name);
			sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
		}
		else
		{
			statement = [parentConnection enumerateForDstStatement:&needsFinalize];
			if (statement == NULL)
				return;
			
			// SELECT "rowid", "name", "src", "rules", "manual" FROM "tableName" WHERE "dst" = ?;
			
			int const bind_idx_dst = SQLITE_BIND_START;
			
			sqlite3_bind_int64(statement, bind_idx_dst, dstRowid);
		}
		
		int status;
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			YapDatabaseRelationshipEdge *edge = nil;
			
			if (name)
			{
				// SELECT "rowid", "src", "rules", "manual" FROM "tableName" WHERE "dst" = ? AND "name" = ?;
				
				int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
				int const column_idx_src    = SQLITE_COLUMN_START + 1;
				int const column_idx_rules  = SQLITE_COLUMN_START + 2;
				int const column_idx_manual = SQLITE_COLUMN_START + 3;
				
				int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
				
				edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
				if (edge)
				{
					edge->sourceRowid = sqlite3_column_int64(statement, column_idx_src);
					edge->state |= YDB_EdgeState_HasSourceRowid;
					
					edge->destinationRowid = dstRowid;
					edge->state |= YDB_EdgeState_HasDestinationRowid;
				}
				else
				{
					int64_t srcRowid = sqlite3_column_int64(statement, column_idx_src);
					
					int rules = sqlite3_column_int(statement, column_idx_rules);
					BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
					
					edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
					                                                         name:name
					                                                     srcRowid:srcRowid
					                                                     dstRowid:dstRowid
					                                                      dstData:nil
					                                                        rules:rules
					                                                       manual:manual];
					
					[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
				}
			}
			else
			{
				// SELECT "rowid", "name", "src", "rules", "manual" FROM "tableName" WHERE "dst" = ?;
				
				int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
				int const column_idx_name   = SQLITE_COLUMN_START + 1;
				int const column_idx_src    = SQLITE_COLUMN_START + 2;
				int const column_idx_rules  = SQLITE_COLUMN_START + 3;
				int const column_idx_manual = SQLITE_COLUMN_START + 4;
				
				int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
				
				edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
				if (edge)
				{
					edge->sourceRowid = sqlite3_column_int64(statement, column_idx_src);
					edge->state |= YDB_EdgeState_HasSourceRowid;
					
					edge->destinationRowid = dstRowid;
					edge->state |= YDB_EdgeState_HasDestinationRowid;
				}
				else
				{
					const unsigned char *text = sqlite3_column_text(statement, column_idx_name);
					int textSize = sqlite3_column_bytes(statement, column_idx_name);
					
					NSString *edgeName =
					  [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
					
					int64_t srcRowid = sqlite3_column_int64(statement, column_idx_src);
					
					int rules = sqlite3_column_int(statement, column_idx_rules);
					BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
					
					edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
					                                                         name:edgeName
					                                                     srcRowid:srcRowid
					                                                     dstRowid:dstRowid
					                                                      dstData:nil
					                                                        rules:rules
					                                                       manual:manual];
					
					[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
				}
			}
			
			// Fill out known edge information (if missing)
			
			if (edge->destinationKey == nil)
			{
				edge->destinationKey = dstKey;
				edge->destinationCollection = dstCollection;
			}
			
			// Does the edge on disk have a corresponding edge in memory that overrides it?
			
			BOOL isChangedEdge = NO;
			NSUInteger i = 0;
			for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
			{
				// Note: we already know the destination matches
				
				if ((changedEdge->isManualEdge == edge->isManualEdge) &&
					[self edge:changedEdge matchesSource:edge])
				{
					// Merge info between matching edges
					MergeInfoBetweenMatchingEdges(edge, changedEdge);
					if (edge->isManualEdge)
						edge->action = changedEdge->action;
					
					isChangedEdge = YES;
					[changedEdges removeObjectAtIndex:i];
					break;
				}
				
				i++;
			}
			
			// Check to see if the edge is broken (src or dst node has been deleted)
			
			if (edge->isManualEdge)
			{
				// Manual edges have explicitly declared actions (from the user)
				if (edge->action == YDB_EdgeAction_Delete)
				{
					// edge is marked for deletion
					continue;
				}
			}
			else if (!isChangedEdge)
			{
				// Protocol edges are replaced all at once (per source node)
				if ([parentConnection->protocolChanges ydb_containsKey:@(edge->sourceRowid)])
				{
					// all protocol edges on disk with this srcRowid have been overriden
					continue;
				}
			}
			
			if ([self isEdgeSourceDeleted:edge])
			{
				continue;
			}
			
			block(edge, &stop);
			if (stop) break;
		}
		
		if (status != SQLITE_DONE && !stop)
		{
			YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite_enum_reset(statement, needsFinalize);
		if (name) {
			FreeYapDatabaseString(&_name);
		}
		
		if (stop) return;
		
	} // end if (hasDstRowid)
	
	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	BOOL dstDeleted = hasDstRowid ? NO : ([self rowidNumberForDeletedKey:dstKey inCollection:dstCollection] != nil);
	
	if (!dstDeleted)
	{
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			if (changedEdge->isManualEdge && changedEdge->action == YDB_EdgeAction_Delete)
			{
				// edge marked for deletion
				continue;
			}
			
			if ([self isEdgeSourceDeleted:changedEdge])
			{
				// broken edge (source node deleted)
				continue;
			}
			
			block(changedEdge, &stop);
			if (stop) break;
		}
	}
}

/**
 * Enumerates every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - destinationFilePath
 * - name + destinationFilePath
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param destinationFilePath (optional)
 *   The edge.destinationFilePath to match.
 * 
 * IMPORTANT:
 * This internal method does NOT prep the edge for the public (e.g. srcKey/dstKey/dstFileURL may be nil).
**/
- (void)_enumerateEdgesWithName:(NSString *)name
             destinationFileURL:(NSURL *)dstFileURL
                     usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	if (dstFileURL == nil) {
		[self enumerateEdgesWithName:name usingBlock:block];
		return;
	}
	if (block == NULL) return;
	
	BOOL stop = NO;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name destinationFileURL:dstFileURL];
	
	// Enumerate the items already in the database
	
	BOOL needsFinalize;
	sqlite3_stmt *statement;
	YapDatabaseString _name;
	
	if (name)
	{
		statement = [parentConnection enumerateDstFileURLWithNameStatement:&needsFinalize];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "src", "dst", "rules", "manual" FROM "tableName" WHERE "dst" > INT64_MAX AND "name" = ?;
		//
		// AKA: typeof(dst) IS BLOB
		
		int const bind_idx_name = SQLITE_BIND_START;
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [parentConnection enumerateAllDstFileURLStatement:&needsFinalize];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "name", "src", "dst", "rules", "manual" FROM "tableName" WHERE "dst" > INT64_MAX;
		//
		// AKA: typeof(dst) IS BLOB
	}
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		YapDatabaseRelationshipEdge *edge = nil;
		
		if (name)
		{
			// SELECT "rowid", "src", "dst", "rules", "manual" FROM "tableName" WHERE "dst" > INT64_MAX AND "name" = ?;
			
			int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
			int const column_idx_src    = SQLITE_COLUMN_START + 1;
			int const column_idx_dst    = SQLITE_COLUMN_START + 2;
			int const column_idx_rules  = SQLITE_COLUMN_START + 3;
			int const column_idx_manual = SQLITE_COLUMN_START + 4;
			
			int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
			if (edge)
			{
				edge->sourceRowid = sqlite3_column_int64(statement, column_idx_src);
				edge->state |= YDB_EdgeState_HasSourceRowid;
			}
			else
			{
				int64_t srcRowid = sqlite3_column_int64(statement, column_idx_src);
				
				int64_t dstRowid = 0;
				NSData *dstFileURLData = nil;
				
				int column_type = sqlite3_column_type(statement, column_idx_dst);
				if (column_type == SQLITE_INTEGER)
				{
					dstRowid = sqlite3_column_int64(statement, column_idx_dst);
				}
				else if (column_type == SQLITE_BLOB)
				{
					const void *blob = sqlite3_column_blob(statement, column_idx_dst);
					int blobSize = sqlite3_column_bytes(statement, column_idx_dst);
					
					dstFileURLData = [NSData dataWithBytes:(void *)blob length:blobSize];
				}
				
				int rules = sqlite3_column_int(statement, column_idx_rules);
				BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
				
				edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
				                                                         name:name
				                                                     srcRowid:srcRowid
				                                                     dstRowid:dstRowid
				                                                      dstData:dstFileURLData
				                                                        rules:rules
				                                                       manual:manual];
				
				[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
			}
		}
		else
		{
			// SELECT "rowid", "name", "src", "dst", "rules", "manual" FROM "tableName" WHERE "dst" > INT64_MAX;
			
			int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
			int const column_idx_name   = SQLITE_COLUMN_START + 1;
			int const column_idx_src    = SQLITE_COLUMN_START + 2;
			int const column_idx_dst    = SQLITE_COLUMN_START + 3;
			int const column_idx_rules  = SQLITE_COLUMN_START + 4;
			int const column_idx_manual = SQLITE_COLUMN_START + 5;
			
			int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
			if (edge)
			{
				edge->sourceRowid = sqlite3_column_int64(statement, column_idx_src);
				edge->state |= YDB_EdgeState_HasSourceRowid;
			}
			else
			{
				const unsigned char *text = sqlite3_column_text(statement, column_idx_name);
				int textSize = sqlite3_column_bytes(statement, column_idx_name);
				
				NSString *edgeName =
				  [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				
				int64_t srcRowid = sqlite3_column_int64(statement, column_idx_src);
				
				int64_t dstRowid = 0;
				NSData *dstFileURLData = nil;
				
				int column_type = sqlite3_column_type(statement, column_idx_dst);
				if (column_type == SQLITE_INTEGER)
				{
					dstRowid = sqlite3_column_int64(statement, column_idx_dst);
				}
				else if (column_type == SQLITE_BLOB)
				{
					const void *blob = sqlite3_column_blob(statement, column_idx_dst);
					int blobSize = sqlite3_column_bytes(statement, column_idx_dst);
					
					dstFileURLData = [NSData dataWithBytes:(void *)blob length:blobSize];
				}
				
				int rules = sqlite3_column_int(statement, column_idx_rules);
				BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
				
				edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
				                                                         name:edgeName
				                                                     srcRowid:srcRowid
				                                                     dstRowid:dstRowid
				                                                      dstData:dstFileURLData
				                                                        rules:rules
				                                                       manual:manual];
				
				[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
			}
		}
		
		[self lookupEdgeDestinationFileURL:edge];
		
		if (!URLMatchesURL(dstFileURL, edge->destinationFileURL))
		{
			// doesn't match parameter
			continue;
		}
		
		// Does the edge on disk have a corresponding edge in memory that overrides it?
		
		BOOL isChangedEdge = NO;
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			// Note: we already know the destination matches
			
			if ((changedEdge->isManualEdge == edge->isManualEdge) &&
			    [self edge:changedEdge matchesSource:edge])
			{
				// Merge info between matching edges
				MergeInfoBetweenMatchingEdges(edge, changedEdge);
				if (edge->isManualEdge)
					edge->action = changedEdge->action;
				
				isChangedEdge = YES;
				[changedEdges removeObjectAtIndex:i];
				break;
			}
			
			i++;
		}
		
		// Check to see if the edge is broken (src or dst node has been deleted)
		
		if (edge->isManualEdge)
		{
			// Manual edges have explicitly declared actions (from the user)
			if (edge->action == YDB_EdgeAction_Delete)
			{
				// edge is marked for deletion
				continue;
			}
		}
		else if (!isChangedEdge)
		{
			// Protocol edges are replaced all at once (per source node)
			if ([parentConnection->protocolChanges ydb_containsKey:@(edge->sourceRowid)])
			{
				// all protocol edges on disk with this srcRowid have been overriden
				continue;
			}
		}
		
		if ([self isEdgeSourceDeleted:edge])
		{
			continue;
		}
		
		block(edge, &stop);
		if (stop) break;
	}
	
	if (status != SQLITE_DONE && !stop)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite_enum_reset(statement, needsFinalize);
	if (name) {
		FreeYapDatabaseString(&_name);
	}
	
	if (stop) return;
	
	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	BOOL dstDeleted = NO; // dstFileURL
	
	if (!dstDeleted)
	{
		for (YapDatabaseRelationshipEdge *edge in changedEdges)
		{
			if (edge->isManualEdge && edge->action == YDB_EdgeAction_Delete)
			{
				// edge marked for deletion
				continue;
			}
			
			if ([self isEdgeSourceDeleted:edge])
			{
				// broken edge (source node deleted)
				continue;
			}
			
			block(edge, &stop);
			if (stop) break;
		}
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
 * 
 * IMPORTANT:
 * This internal method does NOT prep the edge for the public (e.g. srcKey/dstKey/dstFileURL may be nil).
**/
- (void)_enumerateEdgesWithName:(NSString *)name
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
	
	int64_t srcRowid = 0;
	BOOL hasSrcRowid = [databaseTransaction getRowid:&srcRowid forKey:srcKey inCollection:srcCollection];
	
	int64_t dstRowid = 0;
	BOOL hasDstRowid = [databaseTransaction getRowid:&dstRowid forKey:dstKey inCollection:dstCollection];
	
	BOOL stop = NO;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name
	                                                   sourceKey:srcKey
	                                                  collection:srcCollection
	                                                       rowid:(hasSrcRowid ? @(srcRowid) : nil)
	                                              destinationKey:dstKey
	                                                  collection:dstCollection
	                                                       rowid:(hasDstRowid ? @(dstRowid) : nil)];
	
	// Enumerate the items already in the database
	if (hasSrcRowid && hasDstRowid)
	{
		BOOL needsFinalize;
		sqlite3_stmt *statement;
		YapDatabaseString _name;
		
		if (name)
		{
			statement = [parentConnection enumerateForSrcDstNameStatement:&needsFinalize];
			if (statement == NULL)
				return;
			
			// SELECT "rowid", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "dst" = ? AND "name" = ?;
			
			int const bind_idx_src  = SQLITE_BIND_START + 0;
			int const bind_idx_dst  = SQLITE_BIND_START + 1;
			int const bind_idx_name = SQLITE_BIND_START + 2;
			
			sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
			sqlite3_bind_int64(statement, bind_idx_dst, dstRowid);
			
			MakeYapDatabaseString(&_name, name);
			sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
		}
		else
		{
			statement = [parentConnection enumerateForSrcDstStatement:&needsFinalize];
			if (statement == NULL)
				return;
			
			// SELECT "rowid", "name", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "dst" = ?;
			
			int const bind_idx_src = SQLITE_BIND_START + 0;
			int const bind_idx_dst = SQLITE_BIND_START + 1;
			
			sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
			sqlite3_bind_int64(statement, bind_idx_dst, dstRowid);
		}
		
		int status;
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			YapDatabaseRelationshipEdge *edge = nil;
			
			if (name)
			{
				// SELECT "rowid", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "dst" = ? AND "name" = ?;
				
				int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
				int const column_idx_rules  = SQLITE_COLUMN_START + 1;
				int const column_idx_manual = SQLITE_COLUMN_START + 2;
				
				int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
				
				edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
				if (edge)
				{
					edge->sourceRowid = srcRowid;
					edge->state |= YDB_EdgeState_HasSourceRowid;
					
					edge->destinationRowid = dstRowid;
					edge->state |= YDB_EdgeState_HasDestinationRowid;
				}
				else
				{
					int rules = sqlite3_column_int(statement, column_idx_rules);
					BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
					
					edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
					                                                         name:name
					                                                     srcRowid:srcRowid
					                                                     dstRowid:dstRowid
					                                                      dstData:nil
					                                                        rules:rules
					                                                       manual:manual];
					
					[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
				}
			}
			else
			{
				// SELECT "rowid", "name", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "dst" = ?;
				
				int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
				int const column_idx_name   = SQLITE_COLUMN_START + 1;
				int const column_idx_rules  = SQLITE_COLUMN_START + 2;
				int const column_idx_manual = SQLITE_COLUMN_START + 3;
				
				int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
				
				if (edge)
				{
					edge->sourceRowid = srcRowid;
					edge->state |= YDB_EdgeState_HasSourceRowid;
					
					edge->destinationRowid = dstRowid;
					edge->state |= YDB_EdgeState_HasDestinationRowid;
				}
				else
				{
					const unsigned char *text = sqlite3_column_text(statement, column_idx_name);
					int textSize = sqlite3_column_bytes(statement, column_idx_name);
					
					NSString *edgeName =
					  [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
					
					int rules = sqlite3_column_int(statement, column_idx_rules);
					BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
					
					edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
					                                                         name:edgeName
					                                                     srcRowid:srcRowid
					                                                     dstRowid:dstRowid
					                                                      dstData:nil
					                                                        rules:rules
					                                                       manual:manual];
					
					[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
				}
			}
			
			// Fill out known edge information (if missing)
			
			if (edge->sourceKey == nil)
			{
				edge->sourceKey = srcKey;
				edge->sourceCollection = srcCollection;
			}
			
			if (edge->destinationKey == nil)
			{
				edge->destinationKey = dstKey;
				edge->destinationCollection = dstCollection;
			}
			
			// Does the edge on disk have a corresponding edge in memory that overrides it?
			
			BOOL isChangedEdge = NO;
			NSUInteger i = 0;
			for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
			{
				// Note: we already know the source & destination matches
				
				if (changedEdge->isManualEdge == edge->isManualEdge)
				{
					// Merge info between matching edges
					MergeInfoBetweenMatchingEdges(edge, changedEdge);
					if (edge->isManualEdge)
						edge->action = changedEdge->action;
					
					isChangedEdge = YES;
					[changedEdges removeObjectAtIndex:i];
					break;
				}
				
				i++;
			}
			
			// Check to see if the edge is broken (src or dst node has been deleted)
			
			if (edge->isManualEdge)
			{
				// Manual edges have explicitly declared actions (from the user)
				if (edge->action == YDB_EdgeAction_Delete)
				{
					// edge is marked for deletion
					continue;
				}
			}
			else if (!isChangedEdge)
			{
				// Protocol edges are replaced all at once (per source node)
				if ([parentConnection->protocolChanges ydb_containsKey:@(edge->sourceRowid)])
				{
					// all protocol edges on disk with this srcRowid have been overriden
					continue;
				}
			}
			
			block(edge, &stop);
			if (stop) break;
		}
		
		if (status != SQLITE_DONE && !stop)
		{
			YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite_enum_reset(statement, needsFinalize);
		if (name) {
			FreeYapDatabaseString(&_name);
		}
		
		if (stop) return;
	
	} // end if (hasSrcRowid && hasDstRowid)
	
	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	BOOL srcDeleted = hasSrcRowid ? NO : ([self rowidNumberForDeletedKey:srcKey inCollection:srcCollection] != nil);
	BOOL dstDeleted = hasDstRowid ? NO : ([self rowidNumberForDeletedKey:dstKey inCollection:dstCollection] != nil);
	
	if (!srcDeleted && !dstDeleted)
	{
		for (YapDatabaseRelationshipEdge *edge in changedEdges)
		{
			if (edge->isManualEdge && edge->action == YDB_EdgeAction_Delete)
			{
				// edge marked for deletion
				continue;
			}
			
			block(edge, &stop);
			if (stop) break;
		}
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
 * @param destinationFilePath (optional)
 *   The edge.destinationFilePath to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
 * 
 * IMPORTANT:
 * This internal method does NOT prep the edge for the public (e.g. srcKey/dstKey/dstFileURL may be nil).
**/
- (void)_enumerateEdgesWithName:(NSString *)name
                      sourceKey:(NSString *)srcKey
                     collection:(NSString *)srcCollection
             destinationFileURL:(NSURL *)dstFileURL
                     usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	if (srcKey == nil)
	{
		if (dstFileURL == nil)
			[self enumerateEdgesWithName:name usingBlock:block];
		else
			[self enumerateEdgesWithName:name destinationFileURL:dstFileURL usingBlock:block];
		
		return;
	}
	if (dstFileURL == nil)
	{
		[self enumerateEdgesWithName:name sourceKey:srcKey collection:srcCollection usingBlock:block];
		return;
	}
	
	if (block == NULL) return;
	
	if (srcCollection == nil)
		srcCollection = @"";
	
	int64_t srcRowid = 0;
	BOOL hasSrcRowid = [databaseTransaction getRowid:&srcRowid forKey:srcKey inCollection:srcCollection];
	
	BOOL stop = NO;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name
	                                                   sourceKey:srcKey
	                                                  collection:srcCollection
	                                                       rowid:(hasSrcRowid ? @(srcRowid) : nil)
	                                          destinationFileURL:dstFileURL];
	
	// Enumerate the items already in the database
	if (hasSrcRowid)
	{
		BOOL needsFinalize;
		sqlite3_stmt *statement;
		YapDatabaseString _name;
		
		if (name)
		{
			statement = [parentConnection enumerateDstFileURLWithSrcNameStatement:&needsFinalize];
			if (statement == NULL)
				return;
			
			// SELECT "rowid", "dst", "rules", "manual" FROM "tableName"
			//   WHERE "dst" > INT64_MAX AND "src" = ? AND "name" = ?;
			//
			// AKA: typeof(dst) IS BLOB
			
			int const bind_idx_src  = SQLITE_BIND_START + 0;
			int const bind_idx_name = SQLITE_BIND_START + 1;
			
			sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
			
			MakeYapDatabaseString(&_name, name);
			sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
		}
		else
		{
			statement = [parentConnection enumerateDstFileURLWithSrcStatement:&needsFinalize];
			if (statement == NULL)
				return;
			
			// SELECT "rowid", "name", "dst", "rules", "manual" FROM "tableName"
			//   WHERE "dst" > INT64_MAX AND "src" = ?;
			//
			// AKA: typeof(dst) IS BLOB
			
			int const bind_idx_src = SQLITE_BIND_START + 0;
			
			sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
		}
		
		int status;
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			YapDatabaseRelationshipEdge *edge = nil;
			
			if (name)
			{
				// SELECT "rowid", "dst", "rules", "manual" FROM "tableName"
				//   WHERE "dst" > INT64_MAX AND "src" = ? AND "name" = ?;
				
				int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
				int const column_idx_dst    = SQLITE_COLUMN_START + 1;
				int const column_idx_rules  = SQLITE_COLUMN_START + 2;
				int const column_idx_manual = SQLITE_COLUMN_START + 3;
				
				int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
				
				edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
				if (edge == nil)
				{
					int64_t dstRowid = 0;
					NSData *dstFileURLData = nil;
					
					int column_type = sqlite3_column_type(statement, column_idx_dst);
					if (column_type == SQLITE_INTEGER)
					{
						dstRowid = sqlite3_column_int64(statement, column_idx_dst);
					}
					else if (column_type == SQLITE_BLOB)
					{
						const void *blob = sqlite3_column_blob(statement, column_idx_dst);
						int blobSize = sqlite3_column_bytes(statement, column_idx_dst);
						
						dstFileURLData = [NSData dataWithBytes:(void *)blob length:blobSize];
					}
					
					int rules = sqlite3_column_int(statement, column_idx_rules);
					BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
					
					edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
					                                                         name:name
					                                                     srcRowid:srcRowid
					                                                     dstRowid:dstRowid
					                                                      dstData:dstFileURLData
					                                                        rules:rules
					                                                       manual:manual];
					
					[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
				}
			}
			else
			{
				// SELECT "rowid", "name", "dst", "rules", "manual" FROM "tableName"
				//   WHERE "dst" > INT64_MAX AND "src" = ?;
				
				int const column_idx_rowid  = SQLITE_COLUMN_START + 0;
				int const column_idx_name   = SQLITE_COLUMN_START + 1;
				int const column_idx_dst    = SQLITE_COLUMN_START + 2;
				int const column_idx_rules  = SQLITE_COLUMN_START + 3;
				int const column_idx_manual = SQLITE_COLUMN_START + 4;
				
				int64_t edgeRowid = sqlite3_column_int64(statement, column_idx_rowid);
				
				edge = [parentConnection->edgeCache objectForKey:@(edgeRowid)];
				if (edge)
				{
					edge->sourceRowid = srcRowid;
					edge->state |= YDB_EdgeState_HasSourceRowid;
				}
				else
				{
					const unsigned char *text = sqlite3_column_text(statement, column_idx_name);
					int textSize = sqlite3_column_bytes(statement, column_idx_name);
					
					NSString *edgeName =
					  [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
					
					int64_t dstRowid = 0;
					NSData *dstFileURLData = nil;
					
					int column_type = sqlite3_column_type(statement, column_idx_dst);
					if (column_type == SQLITE_INTEGER)
					{
						dstRowid = sqlite3_column_int64(statement, column_idx_dst);
					}
					else if (column_type == SQLITE_BLOB)
					{
						const void *blob = sqlite3_column_blob(statement, column_idx_dst);
						int blobSize = sqlite3_column_bytes(statement, column_idx_dst);
						
						dstFileURLData = [NSData dataWithBytes:(void *)blob length:blobSize];
					}
					
					int rules = sqlite3_column_int(statement, column_idx_rules);
					BOOL manual = (BOOL)sqlite3_column_int(statement, column_idx_manual);
					
					edge = [[YapDatabaseRelationshipEdge alloc] initWithEdgeRowid:edgeRowid
					                                                         name:edgeName
					                                                     srcRowid:srcRowid
					                                                     dstRowid:dstRowid
					                                                      dstData:dstFileURLData
					                                                        rules:rules
					                                                       manual:manual];
					
					[parentConnection->edgeCache setObject:edge forKey:@(edgeRowid)];
				}
			}
			
			[self lookupEdgeDestinationFileURL:edge];
			
			if (!URLMatchesURL(dstFileURL, edge->destinationFileURL))
			{
				// doesn't match parameter
				continue;
			}
			
			// Fill out known edge information (if missing)
			
			if (edge->sourceKey == nil)
			{
				edge->sourceKey = srcKey;
				edge->sourceCollection = srcCollection;
			}
			
			// Does the edge on disk have a corresponding edge in memory that overrides it?
			
			BOOL isChangedEdge = NO;
			NSUInteger i = 0;
			for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
			{
				// Note: we already know the source & destination matches
				
				if (changedEdge->isManualEdge == edge->isManualEdge)
				{
					// Merge info between matching edges
					MergeInfoBetweenMatchingEdges(edge, changedEdge);
					if (edge->isManualEdge)
						edge->action = changedEdge->action;
					
					isChangedEdge = YES;
					[changedEdges removeObjectAtIndex:i];
					break;
				}
				
				i++;
			}
			
			// Check to see if the edge is broken (src or dst node has been deleted)
			
			if (edge->isManualEdge)
			{
				// Manual edges have explicitly declared actions (from the user)
				if (edge->action == YDB_EdgeAction_Delete)
				{
					// edge is marked for deletion
					continue;
				}
			}
			else if (!isChangedEdge)
			{
				// Protocol edges are replaced all at once (per source node)
				if ([parentConnection->protocolChanges ydb_containsKey:@(edge->sourceRowid)])
				{
					// all protocol edges on disk with this srcRowid have been overriden
					continue;
				}
			}
			
			block(edge, &stop);
			if (stop) break;
		}
		
		if (status != SQLITE_DONE && !stop)
		{
			YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite_enum_reset(statement, needsFinalize);
		if (name) {
			FreeYapDatabaseString(&_name);
		}
		
		if (stop) return;
	
	} // end if (hasSrcRowid)
	
	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	BOOL srcDeleted = hasSrcRowid ? NO : ([self rowidNumberForDeletedKey:srcKey inCollection:srcCollection] != nil);
	BOOL dstDeleted = NO; // dstFileURL
	
	if (!srcDeleted && !dstDeleted)
	{
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			if (changedEdge->isManualEdge && (changedEdge->action == YDB_EdgeAction_Delete))
			{
				// edge marked for deletion
				continue;
			}
			
			block(changedEdge, &stop);
			if (stop) break;
		}
	}
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
	[self _enumerateEdgesWithName:name usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
		
		[self lookupEdgePublicProperties:edge];
		block(edge, stop);
	}];
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
	[self _enumerateEdgesWithName:name
	                    sourceKey:srcKey
	                   collection:srcCollection
	                   usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
	{
		[self lookupEdgePublicProperties:edge];
		block(edge, stop);
	}];
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
	[self _enumerateEdgesWithName:name
	               destinationKey:dstKey
	                   collection:dstCollection
	                   usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
	{
		[self lookupEdgePublicProperties:edge];
		block(edge, stop);
	}];
}

/**
 * Enumerates every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - destinationFilePath
 * - name + destinationFilePath
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param destinationFilePath (optional)
 *   The edge.destinationFilePath to match.
**/
- (void)enumerateEdgesWithName:(NSString *)name
            destinationFileURL:(NSURL *)dstFileURL
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	[self _enumerateEdgesWithName:name
	           destinationFileURL:dstFileURL
	                   usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
	{
		[self lookupEdgePublicProperties:edge];
		block(edge, stop);
	}];
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
	[self _enumerateEdgesWithName:name
	                    sourceKey:srcKey
	                   collection:srcCollection
	               destinationKey:dstKey
	                   collection:dstCollection
	                   usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
	{
		[self lookupEdgePublicProperties:edge];
		block(edge, stop);
	}];
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
 * @param destinationFilePath (optional)
 *   The edge.destinationFilePath to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (void)enumerateEdgesWithName:(NSString *)name
                     sourceKey:(NSString *)srcKey
                    collection:(NSString *)srcCollection
            destinationFileURL:(NSURL *)dstFileURL
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	[self _enumerateEdgesWithName:name
	                    sourceKey:srcKey
	                   collection:srcCollection
	           destinationFileURL:dstFileURL
	                   usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
	{
		[self lookupEdgePublicProperties:edge];
		block(edge, stop);
	}];
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
	if (name == nil)
		return 0;
	
	if (databaseTransaction->isReadWriteTransaction)
	{
		__block NSUInteger count = 0;
		[self _enumerateEdgesWithName:name
		                   usingBlock:^(YapDatabaseRelationshipEdge __unused *edge, BOOL __unused *stop)
		{
			count++;
		}];
		
		return count;
	}
	
	sqlite3_stmt *statement = [parentConnection countForNameStatement];
	if (statement == NULL) return 0;
	
	int64_t count = 0;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "name" = ?;
	
	int const column_idx_count = SQLITE_COLUMN_START;
	int const bind_idx_name    = SQLITE_BIND_START;
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, name);
	sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, column_idx_count);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_name);
	
	return (NSUInteger)count;
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
	if (srcKey == nil) {
		return [self edgeCountWithName:name];
	}
	
	if (databaseTransaction->isReadWriteTransaction)
	{
		__block NSUInteger count = 0;
		[self _enumerateEdgesWithName:name
		                    sourceKey:srcKey
		                   collection:srcCollection
		                   usingBlock:^(YapDatabaseRelationshipEdge __unused *edge, BOOL __unused *stop)
		{
			count++;
		}];
		
		return count;
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
	
	sqlite3_stmt *statement = NULL;
	YapDatabaseString _name;
	
	if (name)
	{
		statement = [parentConnection countForSrcNameStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "src" = ? AND "name" = ?;
		
		int const bind_idx_src  = SQLITE_BIND_START + 0;
		int const bind_idx_name = SQLITE_BIND_START + 1;
		
		sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [parentConnection countForSrcStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "src" = ?;
		
		int const bind_idx_src = SQLITE_BIND_START;
		
		sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
	}
	
	int64_t count = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, SQLITE_COLUMN_START);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	if (name) {
		FreeYapDatabaseString(&_name);
	}
	
	return (NSUInteger)count;
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
	if (dstKey == nil) {
		return [self edgeCountWithName:name];
	}
	
	if (databaseTransaction->isReadWriteTransaction)
	{
		__block NSUInteger count = 0;
		[self _enumerateEdgesWithName:name
		               destinationKey:dstKey
		                   collection:dstCollection
		                   usingBlock:^(YapDatabaseRelationshipEdge __unused *edge, BOOL __unused *stop)
		{
			count++;
		}];
		
		return count;
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
	
	sqlite3_stmt *statement = NULL;
	YapDatabaseString _name;
	
	if (name)
	{
		statement = [parentConnection countForDstNameStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "dst" = ? AND "name" = ?;
		
		int const bind_idx_dst  = SQLITE_BIND_START + 0;
		int const bind_idx_name = SQLITE_BIND_START + 1;
		
		sqlite3_bind_int64(statement, bind_idx_dst, dstRowid);
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [parentConnection countForDstStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "dst" = ?;
		
		int const bind_idx_dst = SQLITE_BIND_START;
		
		sqlite3_bind_int64(statement, bind_idx_dst, dstRowid);
	}
	
	int64_t count = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, SQLITE_COLUMN_START);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	if (name) {
		FreeYapDatabaseString(&_name);
	}
	
	return (NSUInteger)count;
}

/**
 * Returns a count of every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - destinationFilePath
 * - name + destinationFilePath
 *
 * @param name (optional)
 *   The name of the edge (case sensitive).
 *
 * @param destinationFilePath (optional)
 *   The edge.destinationFilePath to match.
**/
- (NSUInteger)edgeCountWithName:(NSString *)name
             destinationFileURL:(NSURL *)dstFileURL
{
	if (dstFileURL == nil) {
		return [self edgeCountWithName:name];
	}
	
	__block NSUInteger count = 0;
	[self _enumerateEdgesWithName:name
	           destinationFileURL:dstFileURL
	                   usingBlock:^(YapDatabaseRelationshipEdge __unused *edge, BOOL __unused *stop)
	{
		count++;
	}];
	
	return count;
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
	
	if (databaseTransaction->isReadWriteTransaction)
	{
		__block NSUInteger count = 0;
		[self _enumerateEdgesWithName:name
		                    sourceKey:srcKey
		                   collection:srcCollection
		               destinationKey:dstKey
		                   collection:dstCollection
		                   usingBlock:^(YapDatabaseRelationshipEdge __unused *edge, BOOL __unused *stop)
		{
			count++;
		}];
		
		return count;
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
		// The item doesn't exist in the database.
		return 0;
	}
	
	int64_t dstRowid = 0;
	found = [databaseTransaction getRowid:&dstRowid forKey:dstKey inCollection:dstCollection];
	if (!found)
	{
		// The item doesn't exist in the database.
		return 0;
	}
	
	sqlite3_stmt *statement = NULL;
	YapDatabaseString _name;
	
	if (name)
	{
		statement = [parentConnection countForSrcDstNameStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "src" = ? AND "dst" = ? AND "name" = ?;
		
		int const bind_idx_src  = SQLITE_BIND_START + 0;
		int const bind_idx_dst  = SQLITE_BIND_START + 1;
		int const bind_idx_name = SQLITE_BIND_START + 2;
		
		sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
		sqlite3_bind_int64(statement, bind_idx_dst, dstRowid);
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, bind_idx_name, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [parentConnection countForSrcDstStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "src" = ? AND "dst" = ?;
		
		int const bind_idx_src = SQLITE_BIND_START + 0;
		int const bind_idx_dst = SQLITE_BIND_START + 1;
		
		sqlite3_bind_int64(statement, bind_idx_src, srcRowid);
		sqlite3_bind_int64(statement, bind_idx_dst, dstRowid);
	}
	
	int64_t count = 0;
	
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, SQLITE_COLUMN_START);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	if (name) {
		FreeYapDatabaseString(&_name);
	}
	
	return (NSUInteger)count;
}

/**
 * Returns a count of every edge that matches any parameters you specify.
 * You can specify any combination of the following:
 *
 * - name only
 * - sourceKey & sourceCollection only
 * - destinationFilePath
 * - name + sourceKey & sourceCollection
 * - name + destinationFilePath
 * - name + sourceKey & sourceCollection + destinationFilePath
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
 * @param destinationFilePath (optional)
 *   The edge.destinationFilePath to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (NSUInteger)edgeCountWithName:(NSString *)name
                      sourceKey:(NSString *)srcKey
                     collection:(NSString *)srcCollection
             destinationFileURL:(NSURL *)dstFileURL
{
	if (srcKey == nil)
	{
		if (dstFileURL == nil)
			return [self edgeCountWithName:name];
		else
			return [self edgeCountWithName:name destinationFileURL:dstFileURL];
	}
	if (dstFileURL == nil)
	{
		return [self edgeCountWithName:name sourceKey:srcKey collection:srcCollection];
	}
	
	__block NSUInteger count = 0;
	[self _enumerateEdgesWithName:name
	                    sourceKey:srcKey
	                   collection:srcCollection
	           destinationFileURL:dstFileURL
	                   usingBlock:^(YapDatabaseRelationshipEdge __unused *edge, BOOL __unused *stop)
	{
		count++;
	}];
	
	return count;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API - Manual Edge Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)addEdge:(YapDatabaseRelationshipEdge *)edge
{
	if (edge == nil) return;
	if (edge->sourceKey == nil)
	{
		YDBLogWarn(@"%@ - Cannot add edge. You must pass a fully specified edge, including sourceKey/collection.",
		           THIS_METHOD);
		return;
	}
	
	// Create a clean copy
	edge = [edge copy];
	edge->isManualEdge = YES;
	edge->action = YDB_EdgeAction_Insert;
	
	// Add to manualChanges
	
	NSMutableArray *edges = [parentConnection->manualChanges objectForKey:edge->name];
	if (edges == nil)
	{
		edges = [[NSMutableArray alloc] initWithCapacity:1];
		[parentConnection->manualChanges setObject:edges forKey:edge->name];
	}
	else
	{
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *pendingEdge in edges)
		{
			if ([self edge:pendingEdge matchesManualEdge:edge])
			{
				// This edge replaces previous pendingEdge
				
				if (pendingEdge->state & YDB_EdgeState_HasEdgeRowid)
				{
					edge->edgeRowid = pendingEdge->edgeRowid;
					edge->state |= YDB_EdgeState_HasEdgeRowid;
					edge->action = YDB_EdgeAction_Update;
				}
				else
				{
					edge->flags |= YDB_EdgeFlags_EdgeNotInDatabase;
				}
				
				[edges replaceObjectAtIndex:i withObject:edge];
				return;
			}
			
			i++;
		}
	}
	
	YapDatabaseRelationshipEdge *matchingOnDiskEdge = [self findExistingManualEdgeMatching:edge];
	if (matchingOnDiskEdge)
	{
		if (edge->nodeDeleteRules == matchingOnDiskEdge->nodeDeleteRules)
		{
			// Nothing changed
			return;
		}
		
		edge->edgeRowid = matchingOnDiskEdge->edgeRowid;
		edge->state |= YDB_EdgeState_HasEdgeRowid;
		edge->action = YDB_EdgeAction_Update;
	}
	else
	{
		edge->flags |= YDB_EdgeFlags_EdgeNotInDatabase;
	}
	
	[edges addObject:edge];
}

- (void)removeEdgeWithName:(NSString *)edgeName
                 sourceKey:(NSString *)sourceKey
                collection:(NSString *)sourceCollection
            destinationKey:(NSString *)destinationKey
                collection:(NSString *)destinationCollection
            withProcessing:(YDB_NotifyReason)reason
{
	YapDatabaseRelationshipEdge *edge =
	  [YapDatabaseRelationshipEdge edgeWithName:edgeName
	                                  sourceKey:sourceKey
	                                 collection:sourceCollection
	                             destinationKey:destinationKey
	                                 collection:destinationCollection
	                            nodeDeleteRules:0];
	
	[self removeEdge:edge withProcessing:reason];
}

- (void)removeEdge:(YapDatabaseRelationshipEdge *)edge withProcessing:(YDB_NotifyReason)reason
{
	if (edge == nil) return;
	if (edge->sourceKey == nil)
	{
		YDBLogWarn(@"%@ - Cannot remove edge. You must pass a fully specified edge, including sourceKey/collection.",
		           THIS_METHOD);
		return;
	}
	
	// Create a clean copy
	edge = [edge copy];
	edge->isManualEdge = YES;
	edge->action = YDB_EdgeAction_Delete;
	
	if (reason == YDB_SourceNodeDeleted) {
		edge->flags |= YDB_EdgeFlags_SourceDeleted;
	}
	else if (reason == YDB_DestinationNodeDeleted) {
		edge->flags |= YDB_EdgeFlags_DestinationDeleted;
	}
	
	// Add to manualChanges
	
	NSMutableArray *edges = [parentConnection->manualChanges objectForKey:edge->name];
	if (edges == nil)
	{
		edges = [[NSMutableArray alloc] initWithCapacity:1];
		[parentConnection->manualChanges setObject:edges forKey:edge->name];
	}
	else
	{
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *pendingEdge in edges)
		{
			if ([self edge:pendingEdge matchesManualEdge:edge])
			{
				// This edge replaces previous pending edge
				
				edge->nodeDeleteRules = pendingEdge->nodeDeleteRules;
				
				if (pendingEdge->state & YDB_EdgeState_HasEdgeRowid)
				{
					edge->edgeRowid = pendingEdge->edgeRowid;
					edge->state |= YDB_EdgeState_HasEdgeRowid;
				}
				
				[edges replaceObjectAtIndex:i withObject:edge];
				return;
			}
			
			i++;
		}
	}
	
	YapDatabaseRelationshipEdge *matchingOnDiskEdge = [self findExistingManualEdgeMatching:edge];
	if (matchingOnDiskEdge)
	{
		edge->nodeDeleteRules = matchingOnDiskEdge->nodeDeleteRules;
		edge->edgeRowid = matchingOnDiskEdge->edgeRowid;
		edge->state |= YDB_EdgeState_HasEdgeRowid;
		
		[edges addObject:edge];
	}
	else
	{
		// Do nothing.
		// The edge doesn't exist, so no need to remove it.
	}
}

@end
