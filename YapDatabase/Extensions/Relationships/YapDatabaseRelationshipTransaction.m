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

static NSString *const ExtKey_classVersion       = @"classVersion";
static NSString *const ExtKey_versionTag         = @"versionTag";
static NSString *const ExtKey_version_deprecated = @"version";


NS_INLINE BOOL EdgeMatchesType(YapDatabaseRelationshipEdge *edge, BOOL isManualEdge)
{
	return (edge->isManualEdge == isManualEdge);
}

NS_INLINE BOOL EdgeMatchesName(YapDatabaseRelationshipEdge *edge, NSString *name)
{
	return [edge->name isEqualToString:name];
}

NS_INLINE BOOL EdgeMatchesSource(YapDatabaseRelationshipEdge *edge, int64_t srcRowid)
{
	if ((edge->flags & YDB_FlagsHasSourceRowid)) {
		return (edge->sourceRowid == srcRowid);
	}
	else {
		return NO;
	}
}

NS_INLINE BOOL EdgeMatchesDestination(YapDatabaseRelationshipEdge *edge, int64_t dstRowid, NSString *dstFilePath)
{
	if (dstFilePath) {
		return [edge->destinationFilePath isEqualToString:dstFilePath];
	}
	else if ((edge->flags & YDB_FlagsHasDestinationRowid)) {
		return (edge->destinationRowid == dstRowid);
	}
	else {
		return NO;
	}
}


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
	BOOL hasOldClassVersion = [self getIntValue:&oldClassVersion forExtensionKey:ExtKey_classVersion persistent:YES];
	
	int classVersion = YAP_DATABASE_RELATIONSHIP_CLASS_VERSION;
	
	// Create or re-populate if needed
	
	if (oldClassVersion != classVersion)
	{
		// First time registration (or at least for this version)
		
		if (hasOldClassVersion) {
			
			// In version 2 we added the 'manual' column to support manual edge management.
			// In version 3 we changed the column affinity of the 'dst' column.
			
			if (![self dropTable]) return NO;
		}
		
		if (![self createTables]) return NO;
		if (![self populateTables]) return NO;
		
		[self setIntValue:classVersion forExtensionKey:ExtKey_classVersion persistent:YES];
		
		NSString *versionTag = relationshipConnection->relationship->versionTag;
		[self setStringValue:versionTag forExtensionKey:ExtKey_versionTag persistent:YES];
	}
	else
	{
		// Check user-supplied config version.
		// If the version gets changed, this indicates that YapDatabaseRelationshipNode objects changed.
		// In other words, their yapDatabaseRelationshipEdges methods were channged.
		// So we'll need to re-populate the database (at least the protocol portion of it).
		
		NSString *versionTag = relationshipConnection->relationship->versionTag;
		
		NSString *oldVersionTag = [self stringValueForExtensionKey:ExtKey_versionTag persistent:YES];
		
		BOOL hasOldVersion_deprecated = NO;
		if (oldVersionTag == nil)
		{
			int oldVersion_deprecated = 0;
			hasOldVersion_deprecated = [self getIntValue:&oldVersion_deprecated
			                             forExtensionKey:ExtKey_version_deprecated
			                                  persistent:YES];
			
			if (hasOldVersion_deprecated)
			{
				oldVersionTag = [NSString stringWithFormat:@"%d", oldVersion_deprecated];
			}
		}
		
		if (![oldVersionTag isEqualToString:versionTag])
		{
			if (![self populateTables]) return NO;
			
			[self setStringValue:versionTag forExtensionKey:ExtKey_versionTag persistent:YES];
			
			if (hasOldVersion_deprecated)
				[self removeValueForExtensionKey:ExtKey_version_deprecated persistent:YES];
		}
		else if (hasOldVersion_deprecated)
		{
			[self removeValueForExtensionKey:ExtKey_version_deprecated persistent:YES];
			[self setStringValue:versionTag forExtensionKey:ExtKey_versionTag persistent:YES];
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
 * Runs the sqlite instructions to create the proper table & indexes.
**/
- (BOOL)createTables
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

/**
 * Enumerates the rows in the database and look for objects implementing the YapDatabaseRelationshipNode protocol.
 * Query these objects, and populate the table accordingly.
**/
- (BOOL)populateTables
{
	// Remove all protocol edges from the database
	
	[self removeAllProtocolEdges];
	
	// Skip enumeration step if YapDatabaseRelationshipNode protocol is disabled
	
	if (relationshipConnection->relationship->options->disableYapDatabaseRelationshipNodeProtocol)
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
				cleanEdge->isManualEdge = NO;
				
				[edges addObject:cleanEdge];
			}
			
			[relationshipConnection->protocolChanges setObject:edges forKey:@(rowid)];
		}
	};
	
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections =
	    relationshipConnection->relationship->options->allowedCollections;
	
	if (allowedCollections)
	{
		[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL *outerStop) {
			
			if ([allowedCollections isAllowed:collection])
			{
				[databaseTransaction _enumerateKeysAndObjectsInCollection:collection usingBlock:
				    ^(int64_t rowid, NSString *key, id object, BOOL *innerStop)
				{
					ProcessRow(rowid, collection, key, object);
				}];
			}
		}];
	}
	else
	{
		[databaseTransaction _enumerateKeysAndObjectsInAllCollectionsUsingBlock:
		   	^(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop)
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
{
	if (name == nil)
		return nil;
	
	if (!databaseTransaction->isReadWriteTransaction)
		return nil;
	
	__block NSMutableArray *changes = nil;
	
	// Find matching protocol edges
	
	[relationshipConnection->protocolChanges enumerateKeysAndObjectsUsingBlock:^(id dictKey, id dictObj, BOOL *stop){
		
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
	
	NSArray *manualChangesMatchingName = [relationshipConnection->manualChanges objectForKey:name];
	if (manualChangesMatchingName)
	{
		if (changes == nil)
			changes = [NSMutableArray array];
		
		[changes addObjectsFromArray:manualChangesMatchingName];
	}
	
	// Now lookup the destinationRowid for each edge (if missing).
	// We're going to need these. If not immediately, then during the next flush.
	
	for (YapDatabaseRelationshipEdge *edge in changes)
	{
		// Note: Zero is a valid rowid.
		// So we use flags to properly mark whether a valid rowid has been set.
		
		if (!(edge->flags & YDB_FlagsHasSourceRowid))
		{
			int64_t srcRowid = 0;
			
			BOOL found = [databaseTransaction getRowid:&srcRowid
			                                    forKey:edge->sourceKey
			                              inCollection:edge->sourceCollection];
			if (found)
			{
				edge->sourceRowid = srcRowid;
				edge->flags |= YDB_FlagsHasSourceRowid;
			}
		}
		
		if (!(edge->flags & YDB_FlagsHasDestinationRowid))
		{
			int64_t dstRowid = 0;
			
			BOOL found = [databaseTransaction getRowid:&dstRowid
												forKey:edge->destinationKey
										  inCollection:edge->destinationCollection];
			if (found)
			{
				edge->destinationRowid = dstRowid;
				edge->flags |= YDB_FlagsHasDestinationRowid;
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
                                      rowid:(int64_t)srcRowid
{
	if (srcKey == nil)
		return [self findChangesMatchingName:name];
	
	if (!databaseTransaction->isReadWriteTransaction)
		return nil;
	
	if (srcCollection == nil)
		srcCollection = @"";
	
	__block NSMutableArray *changes = nil;
	
	// Find matching protocol edges
	
	NSMutableArray *changedProtocolEdges = [relationshipConnection->protocolChanges objectForKey:@(srcRowid)];
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
			if ((edge->flags & YDB_FlagsHasSourceRowid))
			{
				if (edge->sourceRowid != srcRowid)
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
		NSArray *manualChangesMatchingName = [relationshipConnection->manualChanges objectForKey:name];
		FindMatchingManualEdges(manualChangesMatchingName);
	}
	else
	{
		[relationshipConnection->manualChanges enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			
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
		
		if (!(edge->flags & YDB_FlagsHasSourceRowid))
		{
			// Shortcut:
			// We already know the sourceRowid. It was given to us as a parameter.
			
			edge->sourceRowid = srcRowid;
			edge->flags |= YDB_FlagsHasSourceRowid;
		}
		
		if (!(edge->flags & YDB_FlagsHasDestinationRowid))
		{
			int64_t dstRowid = 0;
			
			BOOL found = [databaseTransaction getRowid:&dstRowid
												forKey:edge->destinationKey
										  inCollection:edge->destinationCollection];
			if (found)
			{
				edge->destinationRowid = dstRowid;
				edge->flags |= YDB_FlagsHasDestinationRowid;
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
                             destinationKey:(NSString *)dstKey
                                 collection:(NSString *)dstCollection
                                      rowid:(int64_t)dstRowid
{
	if (dstKey == nil)
		return [self findChangesMatchingName:name];
	
	if (!databaseTransaction->isReadWriteTransaction)
		return nil;
	
	if (dstCollection == nil)
		dstCollection = @"";
	
	__block NSMutableArray *changes = nil;
	
	// Find matching protocol edges
	
	[relationshipConnection->protocolChanges enumerateKeysAndObjectsUsingBlock:^(id dictKey, id dictObj, BOOL *stop){
		
	//	__unsafe_unretained NSString *srcRowidNumber = (NSNumber *)dictKey;
		__unsafe_unretained NSArray *changedEdgesForSrc = (NSArray *)dictObj;
		
		for (YapDatabaseRelationshipEdge *edge in changedEdgesForSrc)
		{
			if (name && ![name isEqualToString:edge->name])
			{
				continue;
			}
			
			if (edge->destinationFilePath)
			{
				continue;
			}
			else if ((edge->flags & YDB_FlagsHasDestinationRowid))
			{
				if (edge->destinationRowid != dstRowid)
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
			if (edge->destinationFilePath)
			{
				continue;
			}
			else if ((edge->flags & YDB_FlagsHasDestinationRowid))
			{
				if (edge->destinationRowid != dstRowid)
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
		NSArray *manualChangesMatchingName = [relationshipConnection->manualChanges objectForKey:name];
		FindMatchingManualEdges(manualChangesMatchingName);
	}
	else
	{
		[relationshipConnection->manualChanges enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
			
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
		
		if (!(edge->flags & YDB_FlagsHasSourceRowid))
		{
			int64_t srcRowid = 0;
			
			BOOL found = [databaseTransaction getRowid:&srcRowid
			                                    forKey:edge->sourceKey
			                              inCollection:edge->sourceCollection];
			if (found)
			{
				edge->sourceRowid = srcRowid;
				edge->flags |= YDB_FlagsHasSourceRowid;
			}
		}
		
		if (!(edge->flags & YDB_FlagsHasDestinationRowid))
		{
			// Shortcut:
			// We already know the sourceRowid. It was given to us as a parameter.
			
			edge->destinationRowid = dstRowid;
			edge->flags |= YDB_FlagsHasDestinationRowid;
		}
	}
	
	return changes;
}

/**
 * Extracts edges from the in-memory changes that match the given options.
 * These edges need to replace whatever is on disk.
**/
- (NSMutableArray *)findChangesMatchingName:(NSString *)name
                        destinationFilePath:(NSString *)dstFilePath
{
	if (dstFilePath == nil)
		return [self findChangesMatchingName:name];
	
	if (!databaseTransaction->isReadWriteTransaction)
		return nil;
	
	__block NSMutableArray *changes = nil;
	
	// Find matching protocol edges
	
	[relationshipConnection->protocolChanges enumerateKeysAndObjectsUsingBlock:^(id dictKey, id dictObj, BOOL *stop){
		
	//	__unsafe_unretained NSString *srcRowidNumber = (NSNumber *)dictKey;
		__unsafe_unretained NSArray *changedEdgesForSrc = (NSArray *)dictObj;
		
		for (YapDatabaseRelationshipEdge *edge in changedEdgesForSrc)
		{
			if (name && ![name isEqualToString:edge->name])
			{
				continue;
			}
			
			if (![edge->destinationFilePath isEqualToString:dstFilePath])
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
			if (![edge->destinationFilePath isEqualToString:dstFilePath])
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
		NSArray *manualChangesMatchingName = [relationshipConnection->manualChanges objectForKey:name];
		FindMatchingManualEdges(manualChangesMatchingName);
	}
	else
	{
		[relationshipConnection->manualChanges enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
			
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
		
		if (!(edge->flags & YDB_FlagsHasSourceRowid))
		{
			int64_t srcRowid = 0;
			
			BOOL found = [databaseTransaction getRowid:&srcRowid
			                                    forKey:edge->sourceKey
			                              inCollection:edge->sourceCollection];
			if (found)
			{
				edge->sourceRowid = srcRowid;
				edge->flags |= YDB_FlagsHasSourceRowid;
			}
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
                                      rowid:(int64_t)srcRowid
                             destinationKey:(NSString *)dstKey
                                 collection:(NSString *)dstCollection
                                      rowid:(int64_t)dstRowid
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
	
	NSMutableArray *changedProtocolEdges = [relationshipConnection->protocolChanges objectForKey:@(srcRowid)];
	for (YapDatabaseRelationshipEdge *edge in changedProtocolEdges)
	{
		if (name && ![name isEqualToString:edge->name])
		{
			continue;
		}
		
		if (edge->destinationFilePath)
		{
			continue;
		}
		else if ((edge->flags & YDB_FlagsHasDestinationRowid))
		{
			if (edge->destinationRowid != dstRowid)
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
			if ((edge->flags & YDB_FlagsHasSourceRowid))
			{
				if (edge->sourceRowid != srcRowid)
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
			
			if (edge->destinationFilePath)
			{
				continue;
			}
			else if ((edge->flags & YDB_FlagsHasDestinationRowid))
			{
				if (edge->destinationRowid != dstRowid)
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
		NSArray *manualChangesMatchingName = [relationshipConnection->manualChanges objectForKey:name];
		FindMatchingManualEdges(manualChangesMatchingName);
	}
	else
	{
		[relationshipConnection->manualChanges enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			
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
		
		if (!(edge->flags & YDB_FlagsHasSourceRowid))
		{
			// Shortcut:
			// We already know the sourceRowid. It was given to us as a parameter.
			
			edge->sourceRowid = srcRowid;
			edge->flags |= YDB_FlagsHasSourceRowid;
		}
		
		if (!(edge->flags & YDB_FlagsHasDestinationRowid))
		{
			// Shortcut:
			// We already know the sourceRowid. It was given to us as a parameter.
			
			edge->destinationRowid = dstRowid;
			edge->flags |= YDB_FlagsHasDestinationRowid;
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
                                      rowid:(int64_t)srcRowid
                        destinationFilePath:(NSString *)dstFilePath
{
	if (srcCollection == nil)
		srcCollection = @"";

	if (srcKey == nil)
	{
		if (dstFilePath == nil)
			return [self findChangesMatchingName:name];
		else
			return [self findChangesMatchingName:name destinationFilePath:dstFilePath];
	}
	if (dstFilePath == nil)
	{
		return [self findChangesMatchingName:name sourceKey:srcKey collection:srcCollection rowid:srcRowid];
	}
	
	if (!databaseTransaction->isReadWriteTransaction)
		return nil;
	
	__block NSMutableArray *changes = nil;
	
	// Find matching protocol edges
	
	NSMutableArray *changedProtocolEdges = [relationshipConnection->protocolChanges objectForKey:@(srcRowid)];
	for (YapDatabaseRelationshipEdge *edge in changedProtocolEdges)
	{
		if (![edge->destinationFilePath isEqualToString:dstFilePath])
		{
			continue;
		}
		
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
			if ((edge->flags & YDB_FlagsHasSourceRowid))
			{
				if (edge->sourceRowid != srcRowid)
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
			
			if (![edge->destinationFilePath isEqualToString:dstFilePath])
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
		NSArray *manualChangesMatchingName = [relationshipConnection->manualChanges objectForKey:name];
		FindMatchingManualEdges(manualChangesMatchingName);
	}
	else
	{
		[relationshipConnection->manualChanges enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			
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
		
		if (!(edge->flags & YDB_FlagsHasSourceRowid))
		{
			// Shortcut:
			// We already know the sourceRowid. It was given to us as a parameter.
			
			edge->sourceRowid = srcRowid;
			edge->flags |= YDB_FlagsHasSourceRowid;
		}
		
		// No need to attempt destinationRowid lookup on edges with destinationFilePath
	}
	
	return changes;
}

/**
 * Simple enumeration of existing data in database, via a SELECT query.
 * Does not take into account anything in memory (relationshipConnection->changes dictionary).
**/
- (void)enumerateExistingEdgesWithSource:(int64_t)srcRowid usingBlock:
    (void (^)(int64_t edgeRowid, NSString *name, int64_t dstRowid, NSString *dstFilePath, int rules, BOOL manual))block
{
	sqlite3_stmt *statement = [relationshipConnection enumerateForSrcStatement];
	if (statement == NULL) return;
	
	YapDatabaseRelationshipFilePathDecryptor dstFilePathDecryptor =
	  relationshipConnection->relationship->options.destinationFilePathDecryptor;
	
	// SELECT "rowid", "name", "dst", "rules", "manual" FROM "tableName" WHERE "src" = ?;
	
	sqlite3_bind_int64(statement, 1, srcRowid);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t edgeRowid = sqlite3_column_int64(statement, 0);
		
		const unsigned char *text = sqlite3_column_text(statement, 1);
		int textSize = sqlite3_column_bytes(statement, 1);
		
		NSString *name = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		
		int64_t dstRowid = 0;
		NSString *dstFilePath = nil;
		
		int column_type = sqlite3_column_type(statement, 2);
		if (column_type == SQLITE_INTEGER)
		{
			dstRowid = sqlite3_column_int64(statement, 2);
		}
		else if (column_type == SQLITE_TEXT)
		{
			text = sqlite3_column_text(statement, 2);
			textSize = sqlite3_column_bytes(statement, 2);
			
			dstFilePath = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		else if (column_type == SQLITE_BLOB && dstFilePathDecryptor)
		{
			const void *blob = sqlite3_column_blob(statement, 2);
			int blobSize = sqlite3_column_bytes(statement, 2);
			
			// Performance tuning:
			// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
			
			NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			
			dstFilePath = dstFilePathDecryptor(data);
		}
		
		int rules = sqlite3_column_int(statement, 3);
		BOOL manual = (BOOL)sqlite3_column_int(statement, 4);
		
		block(edgeRowid, name, dstRowid, dstFilePath, rules, manual);
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
}

/**
 * Simple enumeration of existing data in database, via a SELECT query.
 * Does not take into account anything in memory (relationshipConnection->changes dictionary).
**/
- (void)enumerateExistingEdgesWithDestination:(int64_t)dstRowid usingBlock:
                        (void (^)(int64_t edgeRowid, NSString *name, int64_t srcRowid, int rules, BOOL manual))block
{
	sqlite3_stmt *statement = [relationshipConnection enumerateForDstStatement];
	if (statement == NULL) return;
	
	// SELECT "rowid", "name", "src", "rules", "manual" FROM "tableName" WHERE "dst" = ?;
	
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
		
		BOOL manual = (BOOL)sqlite3_column_int(statement, 4);
		
		block(edgeRowid, name, srcRowid, rules, manual);
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
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
- (NSNumber *)rowidNumberForDeletedKey:(NSString *)inKey inCollection:(NSString *)inCollection
{
	__block NSNumber *result = nil;
	
	[relationshipConnection->deletedInfo enumerateKeysAndObjectsUsingBlock:^(id enumKey, id enumObj, BOOL *stop){
		
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
- (int64_t)edgeCountWithDestinationFilePath:(NSString *)dstFilePath
                                       name:(NSString *)name
                            excludingSource:(int64_t)srcRowid
{
	NSAssert(dstFilePath != nil, @"Internal logic error");
	NSAssert(name != nil, @"Internal logic error");
	
	sqlite3_stmt *statement = [relationshipConnection countForDstNameExcludingSrcStatement];
	if (statement == NULL) return 0;
	
	YapDatabaseRelationshipFilePathEncryptor dstFilePathEncryptor =
	  relationshipConnection->relationship->options.destinationFilePathEncryptor;
	
	int64_t count = 0;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "dst" = ? AND "src" != ? AND "name" = ?;
	
	YapDatabaseString _dstFilePath; MakeYapDatabaseString(&_dstFilePath, nil);
	__attribute__((objc_precise_lifetime)) NSData *dstBlob = nil;
	
	if (dstFilePathEncryptor) {
		dstBlob = dstFilePathEncryptor(dstFilePath);
	}
	
	if (dstBlob)
	{
		sqlite3_bind_blob(statement, 1, dstBlob.bytes, (int)dstBlob.length, SQLITE_STATIC);
	}
	else
	{
		MakeYapDatabaseString(&_dstFilePath, dstFilePath);
		sqlite3_bind_text(statement, 1, _dstFilePath.str, _dstFilePath.length, SQLITE_STATIC);
	}
	
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
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_dstFilePath);
	FreeYapDatabaseString(&_name);
	
	return count;
}

- (YapDatabaseRelationshipEdge *)findManualEdgeMatching:(YapDatabaseRelationshipEdge *)edge
{
	// Lookup the sourceRowid and destinationRowid for the given edge (if missing).
	//
	// Note: Zero is a valid rowid.
	// So we use flags to properly handle this edge case.
	
	BOOL missingSrc = NO;
	BOOL missingDst = NO;
	
	if (!(edge->flags & YDB_FlagsHasSourceRowid))
	{
		int64_t srcRowid = 0;
		
		BOOL found = [databaseTransaction getRowid:&srcRowid
		                                    forKey:edge->sourceKey
		                              inCollection:edge->sourceCollection];
		if (found)
		{
			edge->sourceRowid = srcRowid;
			edge->flags |= YDB_FlagsHasSourceRowid;
		}
		else
		{
			NSNumber *srcRowidNumber = [self rowidNumberForDeletedKey:edge->sourceKey
			                                             inCollection:edge->sourceCollection];
			
			if (srcRowidNumber)
			{
				edge->sourceRowid = [srcRowidNumber longLongValue];
				edge->flags |= YDB_FlagsHasSourceRowid;
			}
			else
			{
				missingSrc = YES;
			}
		}
	}
	
	if (!(edge->flags & YDB_FlagsHasDestinationRowid))
	{
		int64_t dstRowid = 0;
		
		BOOL found = [databaseTransaction getRowid:&dstRowid
											forKey:edge->destinationKey
									  inCollection:edge->destinationCollection];
		if (found)
		{
			edge->destinationRowid = dstRowid;
			edge->flags |= YDB_FlagsHasDestinationRowid;
		}
		else
		{
			NSNumber *dstRowidNumber = [self rowidNumberForDeletedKey:edge->destinationKey
			                                             inCollection:edge->destinationCollection];
			
			if (dstRowidNumber)
			{
				edge->destinationRowid = [dstRowidNumber longLongValue];
				edge->flags |= YDB_FlagsHasDestinationRowid;
			}
			else
			{
				missingDst = YES;
			}
		}
	}
	
	if (missingSrc || missingDst)
	{
		return nil;
	}
	
	sqlite3_stmt *statement = [relationshipConnection findManualEdgeStatement];
	if (statement == NULL) return nil;
	
	YapDatabaseRelationshipFilePathEncryptor dstFilePathEncryptor =
	  relationshipConnection->relationship->options.destinationFilePathEncryptor;
	
	// SELECT "rowid", "rules" FROM "tableName" WHERE "src" = ? AND "dst" = ? AND "name" = ? AND "manual" = 1 LIMIT 1;
	
	sqlite3_bind_int64(statement, 1, edge->sourceRowid);
	
	YapDatabaseString _dstFilePath; MakeYapDatabaseString(&_dstFilePath, nil);
	__attribute__((objc_precise_lifetime)) NSData *dstBlob = nil;
	
	if (edge->destinationFilePath)
	{
		if (dstFilePathEncryptor) {
			dstBlob = dstFilePathEncryptor(edge->destinationFilePath);
		}
		
		if (dstBlob)
		{
			sqlite3_bind_blob(statement, 2, dstBlob.bytes, (int)dstBlob.length, SQLITE_STATIC);
		}
		else
		{
			MakeYapDatabaseString(&_dstFilePath, edge->destinationFilePath);
			sqlite3_bind_text(statement, 2, _dstFilePath.str, _dstFilePath.length, SQLITE_STATIC);
		}
	}
	else
	{
		sqlite3_bind_int64(statement, 2, edge->destinationRowid);
	}
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, edge->name);
	sqlite3_bind_text(statement, 3, _name.str, _name.length, SQLITE_STATIC);
	
	YapDatabaseRelationshipEdge *matchingEdge = nil;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		int64_t edgeRowid = sqlite3_column_int64(statement, 0);
		int rules = sqlite3_column_int(statement, 1);
		
		matchingEdge = [edge copy];
		matchingEdge->edgeRowid = edgeRowid;
		matchingEdge->nodeDeleteRules = rules;
		
		matchingEdge->flags |= YDB_FlagsHasEdgeRowid;
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_dstFilePath);
	FreeYapDatabaseString(&_name);
	
	return matchingEdge;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method enumerates over the given sets of edges, and sets the following properties to their appropriate value:
 *
 * edge->edgeAction
 * edge->flags
 *
 * The source node of each edge must be new (inserted during this transaction).
**/
- (void)preprocessProtocolEdges:(NSMutableArray *)protocolEdges forInsertedSource:(NSNumber *)srcRowidNumber
{
	// Get common info
	
	BOOL sourceDeleted = [relationshipConnection->deletedInfo ydb_containsKey:srcRowidNumber];
	
	// Process each edge.
	//
	// Since we know the source node is new (inserted during this transaction),
	// we can skip doing any kind of merging with existing edges on disk.
	
	for (YapDatabaseRelationshipEdge *edge in protocolEdges)
	{
		if (sourceDeleted)
		{
			edge->edgeAction = YDB_EdgeActionDelete;
			edge->flags |= YDB_FlagsSourceDeleted;
			edge->flags |= YDB_FlagsNotInDatabase; // no need to delete edge from database
		}
		
		if (!(edge->flags & YDB_FlagsHasDestinationRowid))
		{
			int64_t dstRowid = 0;
			
			BOOL found = [databaseTransaction getRowid:&dstRowid
			                                    forKey:edge->destinationKey
			                              inCollection:edge->destinationCollection];
			
			if (found)
			{
				edge->destinationRowid = dstRowid;
				edge->flags |= YDB_FlagsHasDestinationRowid;
				
				if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
				{
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->flags |= YDB_FlagsDestinationDeleted;
					edge->flags |= YDB_FlagsNotInDatabase; // no need to delete edge from database
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
					edge->flags |= YDB_FlagsHasDestinationRowid;
					
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->flags |= YDB_FlagsDestinationDeleted;
					edge->flags |= YDB_FlagsNotInDatabase; // no need to delete edge from database
				}
				else
				{
					// Bad edge (destination node never existed).
					// Treat same as if destination node was deleted.
					
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->flags |= YDB_FlagsDestinationDeleted;
					edge->flags |= YDB_FlagsBadDestination;
					edge->flags |= YDB_FlagsNotInDatabase; // no need to delete edge from database
				}
			}
		}
		else if (edge->destinationFilePath == nil &&
		         [relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
		{
			edge->edgeAction = YDB_EdgeActionDelete;
			edge->flags |= YDB_FlagsDestinationDeleted;
			edge->flags |= YDB_FlagsNotInDatabase; // no need to delete edge from database
		}
		else if (!sourceDeleted)
		{
			edge->edgeAction = YDB_EdgeActionInsert;
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
- (void)preprocessProtocolEdges:(NSMutableArray *)protocolEdges forUpdatedSource:(NSNumber *)srcRowidNumber
{
	BOOL sourceDeleted = [relationshipConnection->deletedInfo ydb_containsKey:srcRowidNumber];
	int64_t srcRowid = [srcRowidNumber longLongValue];
	
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
		
		// Note: Zero is a valid rowid.
		// So we use flags to properly mark whether a valid rowid has been set.
		
		if (!(edge->flags & YDB_FlagsHasDestinationRowid))
		{
			int64_t dstRowid = 0;
			BOOL found = [databaseTransaction getRowid:&dstRowid
			                                    forKey:edge->destinationKey
			                              inCollection:edge->destinationCollection];
			
			if (found)
			{
				edge->destinationRowid = dstRowid;
				edge->flags |= YDB_FlagsHasDestinationRowid;
				
				// Note: We check to see if the destination was deleted later
			}
			else
			{
				// Node not found in database.
				// Is this because it was deleted during this transaction?
				
				NSNumber *dstRowidNumber = [self rowidNumberForDeletedKey:edge->destinationKey
				                                             inCollection:edge->destinationCollection];
				
				if (dstRowidNumber)
				{
					edge->destinationRowid = [dstRowidNumber longLongValue];
					edge->flags |= YDB_FlagsHasDestinationRowid;
					
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->flags |= YDB_FlagsDestinationDeleted;
				}
				else
				{
					// Bad edge (destination node never existed).
					// Treat same as if destination node was deleted.
					
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->flags |= YDB_FlagsDestinationDeleted;
					edge->flags |= YDB_FlagsBadDestination;
					edge->flags |= YDB_FlagsNotInDatabase;
					
					[protocolEdges exchangeObjectAtIndex:i withObjectAtIndex:offset];
					offset++;
				}
			}
		}
	}
	
	// Step 2 :
	//
	// Enumerate the existing edges in the database, and try to match them up with edges from the new set.
	
	[self enumerateExistingEdgesWithSource:srcRowid usingBlock:
	    ^(int64_t edgeRowid, NSString *name, int64_t dstRowid, NSString *dstFilePath, int nodeDeleteRules, BOOL manual)
	{
		// Ignore manually created edges
		if (manual) return; // continue (next matching row)
		
		YapDatabaseRelationshipEdge *matchingEdge = nil;
		
		NSUInteger i = offset;
		while (i < protocolEdgesCount)
		{
			YapDatabaseRelationshipEdge *edge = [protocolEdges objectAtIndex:i];
			
			if (EdgeMatchesName(edge, name) && EdgeMatchesDestination(edge, dstRowid, dstFilePath))
			{
				matchingEdge = edge;
				break;
			}
			
			i++;
		}
		
		if (matchingEdge)
		{
			// This edges matches an existing edge already in the database.
			
			matchingEdge->edgeRowid = edgeRowid;
			matchingEdge->flags |= YDB_FlagsHasEdgeRowid;
			
			// Check to see if it changed at all.
			
			if (matchingEdge->nodeDeleteRules != nodeDeleteRules)
			{
				// The nodeDeleteRules changed. Mark for update.
				
				matchingEdge->edgeAction = YDB_EdgeActionUpdate;
			}
			else
			{
				// Nothing changed
				
				matchingEdge->edgeAction = YDB_EdgeActionNone;
			}
			
			// Was source and/or destination deleted?
			
			if (sourceDeleted)
			{
				matchingEdge->edgeAction = YDB_EdgeActionDelete;
				matchingEdge->flags |= YDB_FlagsSourceDeleted;
			}
			
			if (matchingEdge->destinationFilePath == nil &&
			    [relationshipConnection->deletedInfo ydb_containsKey:@(matchingEdge->destinationRowid)])
			{
				matchingEdge->edgeAction = YDB_EdgeActionDelete;
				matchingEdge->flags |= YDB_FlagsDestinationDeleted;
			}
			
			[protocolEdges exchangeObjectAtIndex:i withObjectAtIndex:offset];
			offset++;
		}
		else
		{
			// The existing edge in the database has no match in the new protocolEdges list.
			// Thus an existing edge was removed from the list of edges,
			// and so it needs to be deleted from the database.
			
			YapDatabaseRelationshipEdge *edge =
			  [[YapDatabaseRelationshipEdge alloc] initWithRowid:edgeRowid
			                                                name:name
			                                                 src:srcRowid
			                                                 dst:dstRowid
			                                         dstFilePath:dstFilePath
			                                               rules:nodeDeleteRules
			                                              manual:manual];
			
			edge->edgeAction = YDB_EdgeActionDelete;
			edge->flags |= YDB_FlagsSourceDeleted;
			
			if (dstFilePath == nil)
			{
				if ([relationshipConnection->deletedInfo ydb_containsKey:@(dstRowid)])
				{
					edge->flags |= YDB_FlagsDestinationDeleted;
				}
				else
				{
					YapCollectionKey *dst = [databaseTransaction collectionKeyForRowid:dstRowid];
					if (dst)
					{
						edge->destinationKey = dst.key;
						edge->destinationCollection = dst.collection;
					}
				}
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
		
		edge->edgeAction = YDB_EdgeActionInsert;
		
		if (sourceDeleted)
		{
			edge->edgeAction = YDB_EdgeActionDelete;
			edge->flags |= YDB_FlagsSourceDeleted;
			edge->flags |= YDB_FlagsNotInDatabase;
		}
		
		if (edge->destinationFilePath == nil &&
		    [relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
		{
			edge->edgeAction = YDB_EdgeActionDelete;
			edge->flags |= YDB_FlagsDestinationDeleted;
			edge->flags |= YDB_FlagsNotInDatabase;
		}
	}
}

/**
 * This method enumerates over the given sets of edges, and sets the following properties to their appropriate value:
 *
 * edge->edgeAction
 * edge->flags
**/
- (void)preprocessManualEdges:(NSMutableArray *)manualEdges
{
	for (YapDatabaseRelationshipEdge *edge in manualEdges)
	{
		// Lookup sourceRowid if needed.
		// Otherwise check to see if source node was deleted.
		
		if (!(edge->flags & YDB_FlagsHasSourceRowid))
		{
			int64_t srcRowid = 0;
			
			BOOL found = [databaseTransaction getRowid:&srcRowid
			                                    forKey:edge->sourceKey
			                              inCollection:edge->sourceCollection];
			
			if (found)
			{
				edge->sourceRowid = srcRowid;
				edge->flags |= YDB_FlagsHasSourceRowid;
				
				if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
				{
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->flags |= YDB_FlagsSourceDeleted;
				}
			}
			else
			{
				// Node not found in database.
				// Is this because it was deleted during this transaction?
				
				NSNumber *srcRowidNumber = [self rowidNumberForDeletedKey:edge->sourceKey
				                                             inCollection:edge->sourceCollection];
				
				if (srcRowidNumber)
				{
					edge->sourceRowid = [srcRowidNumber longLongValue];
					edge->flags |= YDB_FlagsHasSourceRowid;
					
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->flags |= YDB_FlagsSourceDeleted;
				}
				else
				{
					// Bad edge (source node never existed).
					// Treat same as if source node was deleted.
					
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->flags |= YDB_FlagsSourceDeleted;
					edge->flags |= YDB_FlagsBadSource;
					edge->flags |= YDB_FlagsNotInDatabase;
				}
			}
		}
		else if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
		{
			edge->edgeAction = YDB_EdgeActionDelete;
			edge->flags |= YDB_FlagsSourceDeleted;
		}
		
		
		// Lookup destinationRowid if needed.
		// Otherwise check to see if destination node was deleted.
		
		if (!(edge->flags & YDB_FlagsHasDestinationRowid))
		{
			int64_t dstRowid = 0;
			
			BOOL found = [databaseTransaction getRowid:&dstRowid
			                                    forKey:edge->destinationKey
			                              inCollection:edge->destinationCollection];
			
			if (found)
			{
				edge->destinationRowid = dstRowid;
				edge->flags |= YDB_FlagsHasDestinationRowid;
				
				if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
				{
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->flags |= YDB_FlagsDestinationDeleted;
				}
			}
			else
			{
				// Node not found in database.
				// Is this because it was deleted during this transaction?
				
				NSNumber *dstRowidNumber = [self rowidNumberForDeletedKey:edge->destinationKey
				                                             inCollection:edge->destinationCollection];
				
				if (dstRowidNumber)
				{
					edge->destinationRowid = [dstRowidNumber longLongValue];
					edge->flags |= YDB_FlagsHasDestinationRowid;
					
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->flags |= YDB_FlagsDestinationDeleted;
				}
				else
				{
					// Bad edge (destination node never existed).
					// Treat same as if destination node was deleted.
					
					edge->edgeAction = YDB_EdgeActionDelete;
					edge->flags |= YDB_FlagsDestinationDeleted;
					edge->flags |= YDB_FlagsBadDestination;
					edge->flags |= YDB_FlagsNotInDatabase;
				}
			}
		}
		else if (edge->destinationFilePath == nil &&
		         [relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
		{
			edge->edgeAction = YDB_EdgeActionDelete;
			edge->flags |= YDB_FlagsDestinationDeleted;
		}
	}
}

/**
 * Helper method for executing the sqlite statement to insert an edge into the database.
**/
- (void)insertEdge:(YapDatabaseRelationshipEdge *)edge
{
	sqlite3_stmt *statement = [relationshipConnection insertEdgeStatement];
	if (statement == NULL) return;
	
	YapDatabaseRelationshipFilePathEncryptor dstFilePathEncryptor =
	  relationshipConnection->relationship->options.destinationFilePathEncryptor;
	
	// INSERT INTO "tableName" ("name", "src", "dst", "rules", "manual") VALUES (?, ?, ?, ?, ?);
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, edge->name);
	sqlite3_bind_text(statement, 1, _name.str, _name.length, SQLITE_STATIC);
	
	sqlite3_bind_int64(statement, 2, edge->sourceRowid);
	
	YapDatabaseString _dstFilePath; MakeYapDatabaseString(&_dstFilePath, nil);
	__attribute__((objc_precise_lifetime)) NSData *dstBlob = nil;
	
	if (edge->destinationFilePath)
	{
		if (dstFilePathEncryptor) {
			dstBlob = dstFilePathEncryptor(edge->destinationFilePath);
		}
		
		if (dstBlob)
		{
			sqlite3_bind_blob(statement, 3, dstBlob.bytes, (int)dstBlob.length, SQLITE_STATIC);
		}
		else
		{
			MakeYapDatabaseString(&_dstFilePath, edge->destinationFilePath);
			sqlite3_bind_text(statement, 3, _dstFilePath.str, _dstFilePath.length, SQLITE_STATIC);
		}
	}
	else
	{
		sqlite3_bind_int64(statement, 3, edge->destinationRowid);
	}
	
	sqlite3_bind_int(statement, 4, edge->nodeDeleteRules);
	
	if (edge->isManualEdge)
		sqlite3_bind_int(statement, 5, 1);
	else
		sqlite3_bind_int(statement, 5, 0);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		edge->edgeRowid = sqlite3_last_insert_rowid(databaseTransaction->connection->db);
		edge->flags |= YDB_FlagsHasEdgeRowid;
	}
	else
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_name);
	FreeYapDatabaseString(&_dstFilePath);
}

/**
 * Helper method for executing the sqlite statement to update an edge in the database.
**/
- (void)updateEdge:(YapDatabaseRelationshipEdge *)edge
{
	NSAssert((edge->flags & YDB_FlagsHasEdgeRowid), @"Logic error - edgeRowid not set");
	
	sqlite3_stmt *statement = [relationshipConnection updateEdgeStatement];
	if (statement == NULL) return;
	
	// UPDATE "tableName" SET "rules" = ? WHERE "rowid" = ?;
	
	sqlite3_bind_int(statement, 1, edge->nodeDeleteRules);
	sqlite3_bind_int64(statement, 2, edge->edgeRowid);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
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
	NSAssert((edge->flags & YDB_FlagsHasEdgeRowid), @"Logic error - edgeRowid not set");
	
	sqlite3_stmt *statement = [relationshipConnection deleteEdgeStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "tableName" WHERE "rowid" = ?;
	
	sqlite3_bind_int64(statement, 1, edge->edgeRowid);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
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
	sqlite3_stmt *statement = [relationshipConnection deleteEdgesWithNodeStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "tableName" WHERE "src" = ? OR "dst" = ?;
	
	sqlite3_bind_int64(statement, 1, rowid);
	sqlite3_bind_int64(statement, 2, rowid);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
					status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
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
	
	sqlite3_stmt *statement = [relationshipConnection removeAllProtocolStatement];
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
	
	[relationshipConnection->protocolChanges removeAllObjects];
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
		sqlite3_stmt *statement = [relationshipConnection enumerateAllDstFilePathStatement];
		if (statement == NULL)
			return;
		
		// SELECT "dst" FROM "tableName" WHERE "dst" > INT64_MAX;"
		//
		// AKA: SELECT "dst" FROM "tableName" WHERE typeof(dst) IS "text" || typeof(dst) IS "blob"
		// but faster because it uses the dst column index.
		
		YDBLogVerbose(@"Looking for files to delete...");
		
		YapDatabaseRelationshipFilePathDecryptor dstFilePathDecryptor =
		  relationshipConnection->relationship->options.destinationFilePathDecryptor;
		
		int status;
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			NSString *dstFilePath = nil;
			
			int column_type = sqlite3_column_type(statement, 0);
			if (column_type == SQLITE_TEXT)
			{
				const unsigned char *text = sqlite3_column_text(statement, 0);
				int textSize = sqlite3_column_bytes(statement, 0);
			
				dstFilePath = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			}
			else if (column_type == SQLITE_BLOB && dstFilePathDecryptor)
			{
				const void *blob = sqlite3_column_blob(statement, 0);
				int blobSize = sqlite3_column_bytes(statement, 0);
				
				// Performance tuning:
				// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
				
				NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
				
				dstFilePath = dstFilePathDecryptor(data);
			}
			
			if (dstFilePath) {
				[relationshipConnection->filesToDelete addObject:dstFilePath];
			}
		}
		
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD,
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite3_reset(statement);
	}
	
	// Step 2: Remove all edges from our database table
	{
		sqlite3_stmt *statement = [relationshipConnection removeAllStatement];
		if (statement == NULL)
			return;
		
		// DELETE FROM "tableName";
		
		YDBLogVerbose(@"Removing all edges");
		
		int status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
			
		sqlite3_reset(statement);
	}
	
	// Step 3: Flush pending change lists
	
	[relationshipConnection->protocolChanges removeAllObjects];
	[relationshipConnection->manualChanges removeAllObjects];
	[relationshipConnection->inserted removeAllObjects];
	[relationshipConnection->deletedOrder removeAllObjects];
	[relationshipConnection->deletedInfo removeAllObjects];
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
				// - Bad edge (invalid source or destination node)
				// - Edge manually deleted via source object (same as source deleted)
				
				BOOL edgeProcessed = YES;
				
				BOOL sourceDeleted      = (edge->flags & (YDB_FlagsSourceDeleted      | YDB_FlagsBadSource));
				BOOL destinationDeleted = (edge->flags & (YDB_FlagsDestinationDeleted | YDB_FlagsBadDestination));
				
				if (edge->destinationFilePath && sourceDeleted)
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
						
						[relationshipConnection->filesToDelete addObject:edge->destinationFilePath];
					}
				}
				else if (!edge->destinationFilePath && sourceDeleted && !destinationDeleted)
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
						
						[databaseRwTransaction removeObjectForKey:edge->destinationKey
						                             inCollection:edge->destinationCollection
						                                withRowid:edge->destinationRowid];
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
				else if (!edge->destinationFilePath && destinationDeleted && !sourceDeleted)
				{
					// Only destination was deleted
					
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
						
						[databaseRwTransaction removeObjectForKey:edge->sourceKey
						                             inCollection:edge->sourceCollection
						                                withRowid:edge->sourceRowid];
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
				
				if (edge->flags & YDB_FlagsNotInDatabase)
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
				
			} // end else if (edge->edgeAction == YDB_EdgeActionDelete)
		
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
	
	[relationshipConnection->protocolChanges enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
		
		__unsafe_unretained NSNumber *srcRowidNumber = (NSNumber *)key;
		__unsafe_unretained NSMutableArray *protocolEdges = (NSMutableArray *)obj;
		
		if ([relationshipConnection->inserted containsObject:srcRowidNumber])
		{
			// The src node is new, so all the edges are new.
			// Thus no need to merge the edges with a previous set of edges.
			//
			// So just enumerate over the edges, and attempt to fill in all the destinationRowid values.
			// If either of the edge's nodes were deleted, mark accordingly.
			
			[self preprocessProtocolEdges:protocolEdges forInsertedSource:srcRowidNumber];
		}
		else
		{
			// The src node was updated, so the edges may have changed.
			//
			// We need to merge the new list with the existing list of edges in the database.
			
			[self preprocessProtocolEdges:protocolEdges forUpdatedSource:srcRowidNumber];
		}
		
		// The edges list has now been preprocessed,
		// and all the various flags for each edge have been set.
		//
		// We're ready for normal edge processing.
		
		ProcessEdges(protocolEdges);
	}];
	
	[relationshipConnection->protocolChanges removeAllObjects];
	
	// STEP 2:
	//
	// Process all manual edges that have been set during the transaction.
	
	[relationshipConnection->manualChanges enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
	//	__unsafe_unretained NSString *edgeName = (NSString *)key;
		__unsafe_unretained NSMutableArray *manualEdges = (NSMutableArray *)obj;
		
		[self preprocessManualEdges:manualEdges];
		
		// The edges list has now been preprocessed,
		// and all the various flags for each edge have been set.
		//
		// We're ready for normal edge processing.
		
		ProcessEdges(manualEdges);
	}];
	
	[relationshipConnection->manualChanges removeAllObjects];
	
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
		if (edge->destinationFilePath)
		{
			if (edge->nodeDeleteRules & YDB_DeleteDestinationIfAllSourcesDeleted)
			{
				// Delete destination node IF there are no other edges pointing to it with the same name
				
				int64_t count = [self edgeCountWithDestinationFilePath:edge->destinationFilePath
				                                                  name:edge->name
				                                       excludingSource:edge->sourceRowid];
				if (count == 0)
				{
					// Mark the file for deletion
					
					[relationshipConnection->filesToDelete addObject:edge->destinationFilePath];
				}
			}
		}
		else // if (!edge->destinationFilePath)
		{
			if (edge->nodeDeleteRules & YDB_DeleteDestinationIfAllSourcesDeleted)
			{
				if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
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
						
						[databaseRwTransaction removeObjectForKey:edge->destinationKey
						                             inCollection:edge->destinationCollection
						                                withRowid:edge->destinationRowid];
					}
				}
			}
			else if (edge->nodeDeleteRules & YDB_DeleteSourceIfAllDestinationsDeleted)
			{
				if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
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
	while (i < [relationshipConnection->deletedOrder count])
	{
		NSNumber *rowidNumber = [relationshipConnection->deletedOrder objectAtIndex:i];
		int64_t rowid = [rowidNumber longLongValue];
		
		YapCollectionKey *collectionKey = [relationshipConnection->deletedInfo objectForKey:rowidNumber];
		
		// Enumerate all edges where source node is this deleted node.
		[self enumerateExistingEdgesWithSource:rowid usingBlock:
		^(int64_t edgeRowid, NSString *name, int64_t dstRowid, NSString *dstFilePath, int nodeDeleteRules, BOOL manual)
		{
			if (dstFilePath)
			{
				if (nodeDeleteRules & YDB_DeleteDestinationIfAllSourcesDeleted)
				{
					// Delete the destination node IF there are no other edges pointing to it with the same name
					
					int64_t count = [self edgeCountWithDestinationFilePath:dstFilePath name:name excludingSource:rowid];
					if (count == 0)
					{
						// Mark the file for deletion
						
						[relationshipConnection->filesToDelete addObject:dstFilePath];
					}
				}
				else if (nodeDeleteRules & YDB_DeleteDestinationIfSourceDeleted)
				{
					// Mark the file for deletion
					
					[relationshipConnection->filesToDelete addObject:dstFilePath];
				}
			}
			else // if (!dstFilePath)
			{
				if ([relationshipConnection->deletedInfo ydb_containsKey:@(dstRowid)])
				{
					// Both source and destination node have been deleted
				}
				else
				{
					if (nodeDeleteRules & YDB_DeleteDestinationIfAllSourcesDeleted)
					{
						// Delete the destination node IF there are no other edges pointing to it with the same name
						
						int64_t count = [self edgeCountWithDestination:dstRowid name:name excludingSource:rowid];
						if (count == 0)
						{
							YapCollectionKey *dst = [databaseTransaction collectionKeyForRowid:dstRowid];
							
							YDBLogVerbose(@"Deleting destination node: key(%@) collection(%@)",
							              dst.key, dst.collection);
							
							__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
							  (YapDatabaseReadWriteTransaction *)databaseTransaction;
							
							[databaseRwTransaction removeObjectForKey:dst.key
							                             inCollection:dst.collection
							                                withRowid:dstRowid];
						}
					}
					else if (nodeDeleteRules & YDB_DeleteDestinationIfSourceDeleted)
					{
						// Delete the destination node
						
						YapCollectionKey *dst = [databaseTransaction collectionKeyForRowid:dstRowid];
						
						YDBLogVerbose(@"Deleting destination node: key(%@) collection(%@)", dst.key, dst.collection);
						
						__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
						  (YapDatabaseReadWriteTransaction *)databaseTransaction;
						
						[databaseRwTransaction removeObjectForKey:dst.key
						                             inCollection:dst.collection
						                                withRowid:dstRowid];
					}
					else if (nodeDeleteRules & YDB_NotifyIfSourceDeleted)
					{
						// Notify the destination node
						
						YapCollectionKey *dst = nil;
						id dstNode = nil;
						
						[databaseTransaction getCollectionKey:&dst
						                               object:&dstNode
						                             forRowid:dstRowid];
						
						SEL selector = @selector(yapDatabaseRelationshipEdgeDeleted:withReason:);
						if ([dstNode respondsToSelector:selector])
						{
							YapDatabaseRelationshipEdge *edge = [[YapDatabaseRelationshipEdge alloc] init];
							edge->name = name;
							edge->sourceKey = collectionKey.key;
							edge->sourceCollection = collectionKey.collection;
							edge->sourceRowid = rowid;
							edge->destinationKey = dst.key;
							edge->destinationCollection = dst.collection;
							edge->destinationRowid = dstRowid;
							edge->nodeDeleteRules = nodeDeleteRules;
							
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
		
		
		// Enumerate all edges where destination node is this deleted node.
		[self enumerateExistingEdgesWithDestination:rowid usingBlock:
		    ^(int64_t edgeRowid, NSString *name, int64_t srcRowid, int nodeDeleteRules, BOOL manual)
		{
			if ([relationshipConnection->deletedInfo ydb_containsKey:@(srcRowid)])
			{
				// Both source and destination node have been deleted
			}
			else
			{
				if (nodeDeleteRules & YDB_DeleteSourceIfAllDestinationsDeleted)
				{
					// Delete the source node IF there are no other edges pointing from it with the same name
					
					int64_t count = [self edgeCountWithSource:srcRowid name:name excludingDestination:rowid];
					if (count == 0)
					{
						YapCollectionKey *src = [databaseTransaction collectionKeyForRowid:srcRowid];
						
						YDBLogVerbose(@"Deleting source node: key(%@) collection(%@)", src.key, src.collection);
						
						__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
						  (YapDatabaseReadWriteTransaction *)databaseTransaction;
						
						[databaseRwTransaction removeObjectForKey:src.key
						                             inCollection:src.collection
						                                withRowid:srcRowid];
					}
				}
				else if (nodeDeleteRules & YDB_DeleteSourceIfDestinationDeleted)
				{
					// Delete the source node
					
					YapCollectionKey *src = [databaseTransaction collectionKeyForRowid:srcRowid];
					
					YDBLogVerbose(@"Deleting source node: key(%@) collection(%@)", src.key, src.collection);
					
					__unsafe_unretained YapDatabaseReadWriteTransaction *databaseRwTransaction =
					  (YapDatabaseReadWriteTransaction *)databaseTransaction;
					
					[databaseRwTransaction removeObjectForKey:src.key
					                             inCollection:src.collection
					                                withRowid:srcRowid];
				}
				else if (nodeDeleteRules & YDB_NotifyIfDestinationDeleted)
				{
					// Notify the source node
					
					YapCollectionKey *src = nil;
					id srcNode = nil;
					
					[databaseTransaction getCollectionKey:&src object:&srcNode forRowid:srcRowid];
					
					SEL selector = @selector(yapDatabaseRelationshipEdgeDeleted:withReason:);
					if ([srcNode respondsToSelector:selector])
					{
						YapDatabaseRelationshipEdge *edge = [[YapDatabaseRelationshipEdge alloc] init];
						edge->name = name;
						edge->sourceKey = src.key;
						edge->sourceCollection = src.collection;
						edge->sourceRowid = srcRowid;
						edge->destinationKey = collectionKey.key;
						edge->destinationCollection = collectionKey.collection;
						edge->destinationRowid = rowid;
						edge->nodeDeleteRules = nodeDeleteRules;
						
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
		
		// Delete all the edges where source or destination is this deleted node.
		[self deleteEdgesWithSourceOrDestination:rowid];
		
		i++;
	}
	
	[relationshipConnection->inserted removeAllObjects];
	[relationshipConnection->deletedInfo removeAllObjects];
	[relationshipConnection->deletedOrder removeAllObjects];
	
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
	
	if ([relationshipConnection->protocolChanges count] > 0 ||
		[relationshipConnection->manualChanges   count] > 0 ||
		[relationshipConnection->deletedInfo     count] > 0 ||
		[relationshipConnection->deletedOrder    count] > 0  )
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
	
	if ([relationshipConnection->filesToDelete count] > 0)
	{
		// Note: No need to make a copy.
		// We will set relationshipConnection->filesToDelete to nil instead.
		//
		// See: [relationshipConnection postCommitCleanup];
		
		NSSet *filesToDelete = relationshipConnection->filesToDelete;
		
		dispatch_queue_t fileManagerQueue = [relationshipConnection->relationship fileManagerQueue];
		dispatch_async(fileManagerQueue, ^{ @autoreleasepool {
			
			NSFileManager *fileManager = [NSFileManager defaultManager];
			
			for (NSString *filePath in filesToDelete)
			{
				NSError *error = nil;
				if (![fileManager removeItemAtPath:filePath error:&error])
				{
					YDBLogWarn(@"Error removing file at path(filePath): %@", error);
				}
			}
		}});
	}
	
	// Commit is complete.
	// Cleanup time.
	
	[relationshipConnection postCommitCleanup];
	
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	relationshipConnection = nil; // Do not remove !
	databaseTransaction = nil;    // Do not remove !
}

/**
 * This method is only called if within a readwrite transaction.
**/
- (void)didRollbackTransaction
{
	YDBLogAutoTrace();
	
	[relationshipConnection postRollbackCleanup];
	
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	relationshipConnection = nil; // Do not remove !
	databaseTransaction = nil;    // Do not remove !
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
	
	if (isFlushing)
	{
		YDBLogError(@"Unable to handle insert hook during flush processing");
		return;
	}
	
	__unsafe_unretained YapDatabaseRelationshipOptions *options = relationshipConnection->relationship->options;
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
	
	if ([givenEdges count] > 0)
	{
		edges = [NSMutableArray arrayWithCapacity:[givenEdges count]];
		
		__unsafe_unretained NSString *collection = collectionKey.collection;
		__unsafe_unretained NSString *key = collectionKey.key;
		
		for (YapDatabaseRelationshipEdge *edge in givenEdges)
		{
			YapDatabaseRelationshipEdge *cleanEdge = [edge copyWithSourceKey:key collection:collection rowid:rowid];
			cleanEdge->isManualEdge = NO;
			
			[edges addObject:cleanEdge];
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
		// More like a two-step replace (in the same transaction)
		//
		//   1. removeObjectForKey:@"sameKey" inCollection:@"sameCollection"
		//   2. setObjectForKey:@"sameKey" inCollection:@"sameCollection"
		//
		// If your intention is to have the first delete cause cascading deletes,
		// then you must invoke the flush method before re-adding an object with the same key/collection.
		//
		// For example:
		//
		// [transaction removeObjectForKey:@"sameKey" inCollection:@"sameCollection"];
		// [[transaction ext:@"relationship"] flush];
		// [transaction setObject:newObject forKey:@"sameKey" inCollection:@"sameCollection"];
		
		if (edges == nil)
			edges = [NSMutableArray arrayWithCapacity:0];
		
		[relationshipConnection->protocolChanges setObject:edges forKey:rowidNumber];
	}
	else if (edges)
	{
		// We store the fact that this item was inserted.
		// That way we can later skip the step where we query the database for existing edges.
		
		[relationshipConnection->protocolChanges setObject:edges forKey:rowidNumber];
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
		YDBLogError(@"Unable to handle update hook during flush processing");
		return;
	}
	
	__unsafe_unretained YapDatabaseRelationshipOptions *options = relationshipConnection->relationship->options;
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
	
	if (givenEdges)
	{
		edges = [NSMutableArray arrayWithCapacity:[givenEdges count]];
		
		__unsafe_unretained NSString *collection = collectionKey.collection;
		__unsafe_unretained NSString *key = collectionKey.key;
		
		for (YapDatabaseRelationshipEdge *edge in givenEdges)
		{
			YapDatabaseRelationshipEdge *cleanEdge = [edge copyWithSourceKey:key collection:collection rowid:rowid];
			cleanEdge->isManualEdge = NO;
			
			[edges addObject:cleanEdge];
		}
	}
	else
	{
		edges = [NSMutableArray arrayWithCapacity:0];
	}
	
	[relationshipConnection->protocolChanges setObject:edges forKey:@(rowid)];
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
	
	__unsafe_unretained YapDatabaseRelationshipOptions *options = relationshipConnection->relationship->options;
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
			cleanEdge->isManualEdge = NO;
			
			[edges addObject:cleanEdge];
		}
	}
	else
	{
		edges = [NSMutableArray arrayWithCapacity:0];
	}
	
	[relationshipConnection->protocolChanges setObject:edges forKey:@(rowid)];
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
		YDBLogError(@"Unable to handle multi-remove hook during flush processing");
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
	
	if ((edge->flags & YDB_FlagsHasSourceRowid))
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
	if (edge->destinationFilePath) return nil;
	
	if ((edge->flags & YDB_FlagsHasDestinationRowid))
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
	
	BOOL stop = NO;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name];
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement = [relationshipConnection enumerateForNameStatement];
	if (statement == NULL)
		return;

	YapDatabaseRelationshipFilePathDecryptor dstFilePathDecryptor =
	  relationshipConnection->relationship->options.destinationFilePathDecryptor;
	
	// SELECT "rowid", "src", "dst", "rules", "manual" FROM "tableName" WHERE "name" = ?;
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, name);
	sqlite3_bind_text(statement, 1, _name.str, _name.length, SQLITE_STATIC);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t edgeRowid = sqlite3_column_int64(statement, 0);
		int64_t srcRowid = sqlite3_column_int64(statement, 1);
		
		int64_t dstRowid = 0;
		NSString *dstFilePath = nil;
		
		int column_type = sqlite3_column_type(statement, 2);
		if (column_type == SQLITE_INTEGER)
		{
			dstRowid = sqlite3_column_int64(statement, 2);
		}
		else if (column_type == SQLITE_TEXT)
		{
			const unsigned char *text = sqlite3_column_text(statement, 2);
			int textSize = sqlite3_column_bytes(statement, 2);
			
			dstFilePath = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		else if (column_type == SQLITE_BLOB && dstFilePathDecryptor)
		{
			const void *blob = sqlite3_column_blob(statement, 2);
			int blobSize = sqlite3_column_bytes(statement, 2);
			
			// Performance tuning:
			// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
			
			NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			
			dstFilePath = dstFilePathDecryptor(data);
		}
		
		int rules = sqlite3_column_int(statement, 3);
		
		BOOL manual = (BOOL)sqlite3_column_int(statement, 4);
		
		YapDatabaseRelationshipEdge *edge = nil;
		
		// Does the edge on disk have a corresponding edge in memory that overrides it?
		
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			BOOL typeMatches = EdgeMatchesType(changedEdge, manual);
			
			BOOL srcMatches = EdgeMatchesSource(changedEdge, srcRowid);
			BOOL dstMatches = EdgeMatchesDestination(changedEdge, dstRowid, dstFilePath);
			
			if (typeMatches && srcMatches && dstMatches)
			{
				edge = changedEdge;
				
				[changedEdges removeObjectAtIndex:i];
				break;
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
				BOOL hasProtocolChanges = [relationshipConnection->protocolChanges ydb_containsKey:@(srcRowid)];
				
				if (!manual && hasProtocolChanges)
				{
					// all protocol edges on disk with this srcRowid have been overriden
					continue;
				}
				
				edge = [[YapDatabaseRelationshipEdge alloc] initWithRowid:edgeRowid
				                                                     name:name
				                                                      src:srcRowid
				                                                      dst:dstRowid
				                                              dstFilePath:dstFilePath
				                                                    rules:rules
				                                                   manual:manual];
				
				YapCollectionKey *src = [databaseTransaction collectionKeyForRowid:srcRowid];
				
				edge->sourceKey = src.key;
				edge->sourceCollection = src.collection;
				
				if (dstFilePath == nil)
				{
					YapCollectionKey *dst = [databaseTransaction collectionKeyForRowid:dstRowid];
					
					edge->destinationKey = dst.key;
					edge->destinationCollection = dst.collection;
				}
			}
			else if (edge->isManualEdge && edge->edgeAction == YDB_EdgeActionDelete)
			{
				// edge is marked for deletion
				continue;
			}
			
			block(edge, &stop);
			if (stop) break;
		}
	}
	
	if (status != SQLITE_DONE && !stop)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
		
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_name);
	
	if (stop) return;
	
	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	for (YapDatabaseRelationshipEdge *edge in changedEdges)
	{
		if (edge->isManualEdge)
		{
			if (edge->edgeAction == YDB_EdgeActionDelete)
			{
				// edge marked for deletion
				continue;
			}
			if ((edge->flags & YDB_FlagsHasSourceRowid))
			{
				if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
				{
					// broken edge (source node deleted)
					continue;
				}
			}
		}
		else
		{
			if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
			{
				// broken edge (source node deleted)
				continue;
			}
		}
		
		if ((edge->flags & YDB_FlagsHasDestinationRowid))
		{
			if (edge->destinationFilePath == nil &&
			    [relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
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
	if (srcKey == nil) {
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
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name
	                                                   sourceKey:srcKey
	                                                  collection:srcCollection
	                                                       rowid:srcRowid];
	
	BOOL hasProtocolChanges = [relationshipConnection->protocolChanges ydb_containsKey:@(srcRowid)];
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement;
	YapDatabaseString _name;
	
	if (name)
	{
		statement = [relationshipConnection enumerateForSrcNameStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "dst", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "name" = ?;",
		
		sqlite3_bind_int64(statement, 1, srcRowid);
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 2, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection enumerateForSrcStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "name", "dst", "rules", "manual" FROM "tableName" WHERE "src" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
	}
	
	YapDatabaseRelationshipFilePathDecryptor dstFilePathDecryptor =
	  relationshipConnection->relationship->options.destinationFilePathDecryptor;
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		NSString *edgeName = nil;
		int64_t edgeRowid;
		int64_t dstRowid = 0;
		NSString *dstFilePath = nil;
		int rules;
		BOOL manual;
		
		if (name)
		{
			// SELECT "rowid", "dst", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "name" = ?;",
			
			edgeRowid = sqlite3_column_int64(statement, 0);
			
			int column_type = sqlite3_column_type(statement, 1);
			if (column_type == SQLITE_INTEGER)
			{
				dstRowid = sqlite3_column_int64(statement, 1);
			}
			else if (column_type == SQLITE_TEXT)
			{
				const unsigned char *text = sqlite3_column_text(statement, 1);
				int textSize = sqlite3_column_bytes(statement, 1);
				
				dstFilePath = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			}
			else if (column_type == SQLITE_BLOB && dstFilePathDecryptor)
			{
				const void *blob = sqlite3_column_blob(statement, 1);
				int blobSize = sqlite3_column_bytes(statement, 1);
				
				// Performance tuning:
				// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
				
				NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
				
				dstFilePath = dstFilePathDecryptor(data);
			}
			
			rules = sqlite3_column_int(statement, 2);
			manual = (BOOL)sqlite3_column_int(statement, 3);
		}
		else
		{
			// SELECT "rowid", "name", "dst", "rules", "manual" FROM "tableName" WHERE "src" = ?;
			
			edgeRowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text = sqlite3_column_text(statement, 1);
			int textSize = sqlite3_column_bytes(statement, 1);
			
			edgeName = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			int column_type = sqlite3_column_type(statement, 2);
			if (column_type == SQLITE_INTEGER)
			{
				dstRowid = sqlite3_column_int64(statement, 2);
			}
			else if (column_type == SQLITE_TEXT)
			{
				text = sqlite3_column_text(statement, 2);
				textSize = sqlite3_column_bytes(statement, 2);
				
				dstFilePath = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			}
			else if (column_type == SQLITE_BLOB && dstFilePathDecryptor)
			{
				const void *blob = sqlite3_column_blob(statement, 2);
				int blobSize = sqlite3_column_bytes(statement, 2);
				
				// Performance tuning:
				// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
				
				NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
				
				dstFilePath = dstFilePathDecryptor(data);
			}
			
			rules = sqlite3_column_int(statement, 3);
			manual = (BOOL)sqlite3_column_int(statement, 4);
		}
		
		YapDatabaseRelationshipEdge *edge = nil;
		
		// Does the edge on disk have a corresponding edge in memory that overrides it?
		
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			BOOL typeMatches = EdgeMatchesType(changedEdge, manual);
			
			BOOL srcMatches = YES; // We already checked this
			BOOL dstMatches = EdgeMatchesDestination(changedEdge, dstRowid, dstFilePath);
			
			if (typeMatches && srcMatches && dstMatches)
			{
				edge = changedEdge;
				
				[changedEdges removeObjectAtIndex:i];
				break;
			}
			
			i++;
		}
		
		// Check to see if the edge is broken (one or more nodes have been deleted).
		
		BOOL edgeBroken = [relationshipConnection->deletedInfo ydb_containsKey:@(dstRowid)];
		
		if (!edgeBroken)
		{
			// If we don't have an updated version of the edge in memory (pending update on disk),
			// then create an edge instance from the data.
			
			if (edge == nil)
			{
				if (!manual && hasProtocolChanges)
				{
					// all protocol edges on disk with this srcRowid have been overriden
					continue;
				}
				
				edge = [[YapDatabaseRelationshipEdge alloc] initWithRowid:edgeRowid
				                                                     name:name ? name : edgeName
				                                                      src:srcRowid
				                                                      dst:dstRowid
				                                              dstFilePath:dstFilePath
				                                                    rules:rules
				                                                   manual:manual];
				
				edge->sourceKey = srcKey;
				edge->sourceCollection = srcCollection;
				
				if (dstFilePath == nil)
				{
					YapCollectionKey *dst = [databaseTransaction collectionKeyForRowid:dstRowid];
					
					edge->destinationKey = dst.key;
					edge->destinationCollection = dst.collection;
				}
			}
			else if (edge->isManualEdge && edge->edgeAction == YDB_EdgeActionDelete)
			{
				// edge is marked for deletion
				continue;
			}
			
			block(edge, &stop);
			if (stop) break;
		}
	}
	
	if (status != SQLITE_DONE && !stop)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
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
		if (edge->isManualEdge)
		{
			if (edge->edgeAction == YDB_EdgeActionDelete)
			{
				// edge marked for deletion
				continue;
			}
		}
		
		if ((edge->flags & YDB_FlagsHasDestinationRowid))
		{
			if (edge->destinationFilePath == nil &&
			    [relationshipConnection->deletedInfo ydb_containsKey:@(edge->destinationRowid)])
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
	if (dstKey == nil) {
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
	                                                  collection:dstCollection
	                                                       rowid:dstRowid];
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement;
	YapDatabaseString _name;
	
	if (name)
	{
		statement = [relationshipConnection enumerateForDstNameStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "src", "rules", "manual" FROM "tableName" WHERE "dst" = ? AND "name" = ?;
		
		sqlite3_bind_int64(statement, 1, dstRowid);
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 2, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection enumerateForDstStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "name", "src", "rules", "manual" FROM "tableName" WHERE "dst" = ?;
		
		sqlite3_bind_int64(statement, 1, dstRowid);
	}
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		NSString *edgeName = nil;
		int64_t edgeRowid;
		int64_t srcRowid;
		int rules;
		BOOL manual;
		
		if (name)
		{
			// SELECT "rowid", "src", "rules", "manual" FROM "tableName" WHERE "dst" = ? AND "name" = ?;
			
			edgeRowid = sqlite3_column_int64(statement, 0);
			srcRowid = sqlite3_column_int64(statement, 1);
			rules = sqlite3_column_int(statement, 2);
			manual = (BOOL)sqlite3_column_int(statement, 3);
		}
		else
		{
			// SELECT "rowid", "name", "src", "rules", "manual" FROM "tableName" WHERE "dst" = ?;
			
			edgeRowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text = sqlite3_column_text(statement, 1);
			int textSize = sqlite3_column_bytes(statement, 1);
			
			srcRowid = sqlite3_column_int64(statement, 2);
			rules = sqlite3_column_int(statement, 3);
			manual = (BOOL)sqlite3_column_int(statement, 4);
			
			edgeName = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		
		YapDatabaseRelationshipEdge *edge = nil;
		
		// Does the edge on disk have a corresponding edge in memory that overrides it?
		
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			BOOL typeMatches = EdgeMatchesType(changedEdge, manual);
			
			BOOL srcMatches = EdgeMatchesSource(changedEdge, srcRowid);
			BOOL dstMatches = YES; // We already checked this
			
			if (typeMatches && srcMatches && dstMatches)
			{
				edge = changedEdge;
				
				[changedEdges removeObjectAtIndex:i];
				break;
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
				BOOL hasProtocolChanges = [relationshipConnection->protocolChanges ydb_containsKey:@(srcRowid)];
				
				if (!manual && hasProtocolChanges)
				{
					// all protocol edges on disk with this srcRowid have been overriden
					continue;
				}
				
				edge = [[YapDatabaseRelationshipEdge alloc] initWithRowid:edgeRowid
			                                                         name:name ? name : edgeName
			                                                          src:srcRowid
			                                                          dst:dstRowid
				                                              dstFilePath:nil
			                                                        rules:rules
				                                                   manual:manual];
				
				YapCollectionKey *src = [databaseTransaction collectionKeyForRowid:srcRowid];
				
				edge->sourceKey = src.key;
				edge->sourceCollection = src.collection;
				
				edge->destinationKey = dstKey;
				edge->destinationCollection = dstCollection;
			}
			else if (edge->isManualEdge && edge->edgeAction == YDB_EdgeActionDelete)
			{
				// edge is marked for deletion
				continue;
			}
			
			block(edge, &stop);
			if (stop) break;
		}
	}
	
	if (status != SQLITE_DONE && !stop)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
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
		if (edge->isManualEdge)
		{
			if (edge->edgeAction == YDB_EdgeActionDelete)
			{
				// edge marked for deletion
				continue;
			}
			if ((edge->flags & YDB_FlagsHasSourceRowid))
			{
				if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
				{
					// broken edge (source node deleted)
					continue;
				}
			}
		}
		else
		{
			if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
			{
				// broken edge (source node deleted)
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
           destinationFilePath:(NSString *)dstFilePath
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	if (dstFilePath == nil) {
		[self enumerateEdgesWithName:name usingBlock:block];
		return;
	}
	if (block == NULL) return;
	
	BOOL stop = NO;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name destinationFilePath:dstFilePath];
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement;
	YapDatabaseString _name;
	YapDatabaseString _dstFilePath;
	__attribute__((objc_precise_lifetime)) NSData *dstBlob = nil;
	
	YapDatabaseRelationshipFilePathEncryptor dstFilePathEncryptor =
	  relationshipConnection->relationship->options.destinationFilePathEncryptor;
	
	if (name)
	{
		statement = [relationshipConnection enumerateForDstNameStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "src", "rules", "manual" FROM "tableName" WHERE "dst" = ? AND "name" = ?;
		
		if (dstFilePathEncryptor)
		{
			dstBlob = dstFilePathEncryptor(dstFilePath);
		}
		
		if (dstBlob)
		{
			sqlite3_bind_blob(statement, 1, dstBlob.bytes, (int)dstBlob.length, SQLITE_STATIC);
		}
		else
		{
			MakeYapDatabaseString(&_dstFilePath, dstFilePath);
			sqlite3_bind_text(statement, 1, _dstFilePath.str, _dstFilePath.length, SQLITE_STATIC);
		}
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 2, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection enumerateForDstStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "name", "src", "rules", "manual" FROM "tableName" WHERE "dst" = ?;
		
		if (dstFilePathEncryptor) {
			dstBlob = dstFilePathEncryptor(dstFilePath);
		}
		
		if (dstBlob)
		{
			sqlite3_bind_blob(statement, 1, dstBlob.bytes, (int)dstBlob.length, SQLITE_STATIC);
		}
		else
		{
			MakeYapDatabaseString(&_dstFilePath, dstFilePath);
			sqlite3_bind_text(statement, 1, _dstFilePath.str, _dstFilePath.length, SQLITE_STATIC);
		}
	}
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		NSString *edgeName = nil;
		int64_t edgeRowid;
		int64_t srcRowid;
		int rules;
		BOOL manual;
		
		if (name)
		{
			edgeRowid = sqlite3_column_int64(statement, 0);
			srcRowid = sqlite3_column_int64(statement, 1);
			rules = sqlite3_column_int(statement, 2);
			manual = (BOOL)sqlite3_column_int(statement, 3);
		}
		else
		{
			edgeRowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text = sqlite3_column_text(statement, 1);
			int textSize = sqlite3_column_bytes(statement, 1);
			
			srcRowid = sqlite3_column_int64(statement, 2);
			rules = sqlite3_column_int(statement, 3);
			manual = (BOOL)sqlite3_column_int(statement, 4);
			
			edgeName = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		
		YapDatabaseRelationshipEdge *edge = nil;
		
		// Does the edge on disk have a corresponding edge in memory that overrides it?
		
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			BOOL typeMatches = EdgeMatchesType(changedEdge, manual);
			
			BOOL srcMatches = EdgeMatchesSource(changedEdge, srcRowid);
			BOOL dstMatches = YES; // We already checked this
			
			if (typeMatches && srcMatches && dstMatches)
			{
				edge = changedEdge;
				
				[changedEdges removeObjectAtIndex:i];
				break;
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
				BOOL hasProtocolChanges = [relationshipConnection->protocolChanges ydb_containsKey:@(srcRowid)];
				
				if (!manual && hasProtocolChanges)
				{
					// all protocol edges on disk with this srcRowid have been overriden
					continue;
				}
				
				edge = [[YapDatabaseRelationshipEdge alloc] initWithRowid:edgeRowid
			                                                         name:name ? name : edgeName
			                                                          src:srcRowid
				                                                      dst:0
			                                                  dstFilePath:dstFilePath
			                                                        rules:rules
				                                                   manual:manual];
				
				YapCollectionKey *src = [databaseTransaction collectionKeyForRowid:srcRowid];
				
				edge->sourceKey = src.key;
				edge->sourceCollection = src.collection;
			}
			else if (edge->isManualEdge && edge->edgeAction == YDB_EdgeActionDelete)
			{
				// edge is marked for deletion
				continue;
			}
			
			block(edge, &stop);
			if (stop) break;
		}
	}
	
	if (status != SQLITE_DONE && !stop)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
	if (name) {
		FreeYapDatabaseString(&_name);
	}
	if (!dstBlob) {
		FreeYapDatabaseString(&_dstFilePath);
	}
	
	if (stop) return;
	
	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	for (YapDatabaseRelationshipEdge *edge in changedEdges)
	{
		if (edge->isManualEdge)
		{
			if (edge->edgeAction == YDB_EdgeActionDelete)
			{
				// edge marked for deletion
				continue;
			}
			if ((edge->flags & YDB_FlagsHasSourceRowid))
			{
				if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
				{
					// broken edge (source node deleted)
					continue;
				}
			}
		}
		else
		{
			if ([relationshipConnection->deletedInfo ydb_containsKey:@(edge->sourceRowid)])
			{
				// broken edge (source node deleted)
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
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name
	                                                   sourceKey:srcKey
	                                                  collection:srcCollection
	                                                       rowid:srcRowid
	                                              destinationKey:dstKey
	                                                  collection:dstCollection
	                                                       rowid:dstRowid];
	
	BOOL hasProtocolChanges = [relationshipConnection->protocolChanges ydb_containsKey:@(srcRowid)];
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement;
	YapDatabaseString _name;
	
	if (name)
	{
		statement = [relationshipConnection enumerateForSrcDstNameStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "dst" = ? AND "name" = ?;
		
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
		
		// SELECT "rowid", "name", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "dst" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
		sqlite3_bind_int64(statement, 2, dstRowid);
	}
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		NSString *edgeName = nil;
		int64_t edgeRowid;
		int rules;
		BOOL manual;
		
		if (name)
		{
			edgeRowid = sqlite3_column_int64(statement, 0);
			rules = sqlite3_column_int(statement, 1);
			manual = (BOOL)sqlite3_column_int(statement, 2);
		}
		else
		{
			edgeRowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text = sqlite3_column_text(statement, 1);
			int textSize = sqlite3_column_bytes(statement, 1);
			
			rules = sqlite3_column_int(statement, 2);
			manual = (BOOL)sqlite3_column_int(statement, 3);
			
			edgeName = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		
		YapDatabaseRelationshipEdge *edge = nil;
		
		// Does the edge on disk have a corresponding edge in memory that overrides it?
		
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			BOOL typeMatches = EdgeMatchesType(changedEdge, manual);
			
			BOOL srcMatches = YES; // We already checked this
			BOOL dstMatches = YES; // We already checked this
			
			if (typeMatches && srcMatches && dstMatches)
			{
				edge = changedEdge;
				
				[changedEdges removeObjectAtIndex:i];
				break;
			}
			
			i++;
		}
		
		if (edge == nil)
		{
			if (!manual && hasProtocolChanges)
			{
				// all protocol edges on disk with this srcRowid have been overriden
				continue;
			}
			
			edge = [[YapDatabaseRelationshipEdge alloc] initWithRowid:edgeRowid
			                                                name:name ? name : edgeName
			                                                 src:srcRowid
			                                                 dst:dstRowid
			                                         dstFilePath:nil
			                                               rules:rules
			                                              manual:manual];
			
			edge->sourceKey = srcKey;
			edge->sourceCollection = srcCollection;
			
			edge->destinationKey = dstKey;
			edge->destinationCollection = dstCollection;
		}
		else if (edge->isManualEdge && edge->edgeAction == YDB_EdgeActionDelete)
		{
			// edge is marked for deletion
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
	
	sqlite3_reset(statement);
	if (name) {
		FreeYapDatabaseString(&_name);
	}
	
	if (stop) return;
	
	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	for (YapDatabaseRelationshipEdge *edge in changedEdges)
	{
		if (edge->isManualEdge && edge->edgeAction == YDB_EdgeActionDelete)
		{
			// edge marked for deletion
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
 * @param destinationFilePath (optional)
 *   The edge.destinationFilePath to match.
 *
 * If you pass a non-nil sourceKey, and sourceCollection is nil,
 * then the sourceCollection is treated as the empty string, just like the rest of the YapDatabase framework.
**/
- (void)enumerateEdgesWithName:(NSString *)name
                     sourceKey:(NSString *)srcKey
                    collection:(NSString *)srcCollection
           destinationFilePath:(NSString *)dstFilePath
                    usingBlock:(void (^)(YapDatabaseRelationshipEdge *edge, BOOL *stop))block
{
	if (srcKey == nil)
	{
		if (dstFilePath == nil)
			[self enumerateEdgesWithName:name usingBlock:block];
		else
			[self enumerateEdgesWithName:name destinationFilePath:dstFilePath usingBlock:block];
		
		return;
	}
	if (dstFilePath == nil)
	{
		[self enumerateEdgesWithName:name sourceKey:srcKey collection:srcCollection usingBlock:block];
		return;
	}
	
	if (block == NULL) return;
	
	if (srcCollection == nil)
		srcCollection = @"";
	
	BOOL found;
	
	int64_t srcRowid = 0;
	found = [databaseTransaction getRowid:&srcRowid forKey:srcKey inCollection:srcCollection];
	if (!found)
	{
		// The source node doesn't exist in the database.
		return;
	}
	
	BOOL stop = NO;
	
	// There may be edges in memory that haven't yet been written to disk.
	// We need to find these edges, and ensure they override their corresponding counterparts from disk.
	
	NSMutableArray *changedEdges = [self findChangesMatchingName:name
	                                                   sourceKey:srcKey
	                                                  collection:srcCollection
	                                                       rowid:srcRowid
	                                         destinationFilePath:dstFilePath];
	
	BOOL hasProtocolChanges = [relationshipConnection->protocolChanges ydb_containsKey:@(srcRowid)];
	
	// Enumerate the items already in the database
	
	sqlite3_stmt *statement;
	YapDatabaseString _name;
	YapDatabaseString _dstFilePath;
	__attribute__((objc_precise_lifetime)) NSData *dstBlob = nil;
	
	YapDatabaseRelationshipFilePathEncryptor dstFilePathEncryptor =
	  relationshipConnection->relationship->options.destinationFilePathEncryptor;
	
	if (name)
	{
		statement = [relationshipConnection enumerateForSrcDstNameStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "dst" = ? AND "name" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
		
		if (dstFilePathEncryptor) {
			dstBlob = dstFilePathEncryptor(dstFilePath);
		}
		
		if (dstBlob)
		{
			sqlite3_bind_blob(statement, 2, dstBlob.bytes, (int)dstBlob.length, SQLITE_STATIC);
		}
		else
		{
			MakeYapDatabaseString(&_dstFilePath, dstFilePath);
			sqlite3_bind_text(statement, 2, _dstFilePath.str, _dstFilePath.length, SQLITE_STATIC);
		}
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 3, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection enumerateForSrcDstStatement];
		if (statement == NULL)
			return;
		
		// SELECT "rowid", "name", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "dst" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
		
		if (dstFilePathEncryptor) {
			dstBlob = dstFilePathEncryptor(dstFilePath);
		}
		
		if (dstBlob)
		{
			sqlite3_bind_blob(statement, 2, dstBlob.bytes, (int)dstBlob.length, SQLITE_STATIC);
		}
		else
		{
			MakeYapDatabaseString(&_dstFilePath, dstFilePath);
			sqlite3_bind_text(statement, 2, _dstFilePath.str, _dstFilePath.length, SQLITE_STATIC);
		}
	}
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		NSString *edgeName = nil;
		int64_t edgeRowid;
		int rules;
		BOOL manual;
		
		if (name)
		{
			// SELECT "rowid", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "dst" = ? AND "name" = ?;
			
			edgeRowid = sqlite3_column_int64(statement, 0);
			rules = sqlite3_column_int(statement, 1);
			manual = (BOOL)sqlite3_column_int(statement, 2);
		}
		else
		{
			// SELECT "rowid", "name", "rules", "manual" FROM "tableName" WHERE "src" = ? AND "dst" = ?;
			
			edgeRowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text = sqlite3_column_text(statement, 1);
			int textSize = sqlite3_column_bytes(statement, 1);
			
			rules = sqlite3_column_int(statement, 2);
			manual = (BOOL)sqlite3_column_int(statement, 3);
			
			edgeName = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		
		YapDatabaseRelationshipEdge *edge = nil;
		
		// Does the edge on disk have a corresponding edge in memory that overrides it?
		
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *changedEdge in changedEdges)
		{
			BOOL typeMatches = EdgeMatchesType(changedEdge, manual);
			
			BOOL srcMatches = YES; // We already checked this
			BOOL dstMatches = YES; // We already checked this
			
			if (typeMatches && srcMatches && dstMatches)
			{
				edge = changedEdge;
				
				[changedEdges removeObjectAtIndex:i];
				break;
			}
			
			i++;
		}
		
		if (edge == nil)
		{
			if (!manual && hasProtocolChanges)
			{
				// all protocol edges on disk with this srcRowid have been overriden
				continue;
			}
			
			edge = [[YapDatabaseRelationshipEdge alloc] initWithRowid:edgeRowid
			                                                     name:name ? name : edgeName
			                                                      src:srcRowid
			                                                      dst:0
			                                              dstFilePath:dstFilePath
			                                                    rules:rules
			                                                   manual:manual];
			
			edge->sourceKey = srcKey;
			edge->sourceCollection = srcCollection;
		}
		else if (edge->isManualEdge && edge->edgeAction == YDB_EdgeActionDelete)
		{
			// edge is marked for deletion
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
	
	sqlite3_reset(statement);
	if (name) {
		FreeYapDatabaseString(&_name);
	}
	if (!dstBlob) {
		FreeYapDatabaseString(&_dstFilePath);
	}
	
	if (stop) return;
	
	// Any edges left sitting in the changedEdges array haven't been processed yet.
	// So we need to enumerate them.
	
	for (YapDatabaseRelationshipEdge *edge in changedEdges)
	{
		if (edge->isManualEdge && edge->edgeAction == YDB_EdgeActionDelete)
		{
			// edge marked for deletion
			continue;
		}
		
		block(edge, &stop);
		if (stop) break;
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
	if (name == nil)
		return 0;
	
	if (databaseTransaction->isReadWriteTransaction)
	{
		__block NSUInteger count = 0;
		[self enumerateEdgesWithName:name usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
			
			count++;
		}];
		
		return count;
	}
	
	sqlite3_stmt *statement = [relationshipConnection countForNameStatement];
	if (statement == NULL) return 0;
	
	int64_t count = 0;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "name" = ?;
	
	YapDatabaseString _name; MakeYapDatabaseString(&_name, name);
	sqlite3_bind_text(statement, 1, _name.str, _name.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, 0);
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
		[self enumerateEdgesWithName:name
		                   sourceKey:srcKey
		                  collection:srcCollection
		                  usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
			
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
		statement = [relationshipConnection countForSrcNameStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "src" = ? AND "name" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 2, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection countForSrcStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "src" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
	}
	
	int64_t count = 0;
	
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, 0);
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
		[self enumerateEdgesWithName:name
		              destinationKey:dstKey
		                  collection:dstCollection
		                  usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
			
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
		statement = [relationshipConnection countForDstNameStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "dst" = ? AND "name" = ?;
		
		sqlite3_bind_int64(statement, 1, dstRowid);
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 2, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection countForDstStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "dst" = ?;
		
		sqlite3_bind_int64(statement, 1, dstRowid);
	}
	
	int64_t count = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, 0);
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
            destinationFilePath:(NSString *)dstFilePath
{
	if (dstFilePath == nil) {
		return [self edgeCountWithName:name];
	}
	
	if (databaseTransaction->isReadWriteTransaction)
	{
		__block NSUInteger count = 0;
		[self enumerateEdgesWithName:name
		         destinationFilePath:dstFilePath
		                  usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
			
			count++;
		}];
		
		return count;
	}
	
	sqlite3_stmt *statement = NULL;
	YapDatabaseString _name;
	YapDatabaseString _dstFilePath;
	__attribute__((objc_precise_lifetime)) NSData *dstBlob = nil;
	
	YapDatabaseRelationshipFilePathEncryptor dstFilePathEncryptor =
	  relationshipConnection->relationship->options.destinationFilePathEncryptor;
	
	if (name)
	{
		statement = [relationshipConnection countForDstNameStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "dst" = ? AND "name" = ?;
		
		if (dstFilePathEncryptor) {
			dstBlob = dstFilePathEncryptor(dstFilePath);
		}
		
		if (dstBlob)
		{
			sqlite3_bind_blob(statement, 1, dstBlob.bytes, (int)dstBlob.length, SQLITE_STATIC);
		}
		else
		{
			MakeYapDatabaseString(&_dstFilePath, dstFilePath);
			sqlite3_bind_text(statement, 1, _dstFilePath.str, _dstFilePath.length, SQLITE_STATIC);
		}
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 2, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection countForDstStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "dst" = ?;
		
		if (dstFilePathEncryptor) {
			dstBlob = dstFilePathEncryptor(dstFilePath);
		}
		
		if (dstBlob)
		{
			sqlite3_bind_blob(statement, 1, dstBlob.bytes, (int)dstBlob.length, SQLITE_STATIC);
		}
		else
		{
			MakeYapDatabaseString(&_dstFilePath, dstFilePath);
			sqlite3_bind_text(statement, 1, _dstFilePath.str, _dstFilePath.length, SQLITE_STATIC);
		}
	}
	
	int64_t count = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, 0);
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
	if (!dstBlob) {
		FreeYapDatabaseString(&_dstFilePath);
	}
	
	return (NSUInteger)count;
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
		[self enumerateEdgesWithName:name
		                   sourceKey:srcKey
		                  collection:srcCollection
		              destinationKey:dstKey
		                  collection:dstCollection
		                  usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
			
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
	
	int64_t count = 0;
	
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, 0);
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
            destinationFilePath:(NSString *)dstFilePath
{
	if (srcKey == nil)
	{
		if (dstFilePath == nil)
			return [self edgeCountWithName:name];
		else
			return [self edgeCountWithName:name destinationFilePath:dstFilePath];
	}
	if (dstFilePath == nil)
	{
		return [self edgeCountWithName:name sourceKey:srcKey collection:srcCollection];
	}
	
	if (databaseTransaction->isReadWriteTransaction)
	{
		__block NSUInteger count = 0;
		[self enumerateEdgesWithName:name
		                   sourceKey:srcKey
		                  collection:srcCollection
		         destinationFilePath:dstFilePath
		                  usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
			
			count++;
		}];
		
		return count;
	}
	
	if (srcCollection == nil)
		srcCollection = @"";
	
	BOOL found;
	
	int64_t srcRowid = 0;
	found = [databaseTransaction getRowid:&srcRowid forKey:srcKey inCollection:srcCollection];
	if (!found)
	{
		// The item doesn't exist in the database.
		return 0;
	}
	
	sqlite3_stmt *statement = NULL;
	YapDatabaseString _name;
	YapDatabaseString _dstFilePath;
	__attribute__((objc_precise_lifetime)) NSData *dstBlob = nil;
	
	YapDatabaseRelationshipFilePathEncryptor dstFilePathEncryptor =
	  relationshipConnection->relationship->options.destinationFilePathEncryptor;
	
	if (name)
	{
		statement = [relationshipConnection countForSrcDstNameStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "src" = ? AND "dst" = ? AND "name" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
		
		if (dstFilePathEncryptor) {
			dstBlob = dstFilePathEncryptor(dstFilePath);
		}
		
		if (dstBlob)
		{
			sqlite3_bind_blob(statement, 2, dstBlob.bytes, (int)dstBlob.length, SQLITE_STATIC);
		}
		else
		{
			MakeYapDatabaseString(&_dstFilePath, dstFilePath);
			sqlite3_bind_text(statement, 2, _dstFilePath.str, _dstFilePath.length, SQLITE_STATIC);
		}
		
		MakeYapDatabaseString(&_name, name);
		sqlite3_bind_text(statement, 3, _name.str, _name.length, SQLITE_STATIC);
	}
	else
	{
		statement = [relationshipConnection countForSrcDstStatement];
		if (statement == NULL) return 0;
		
		// SELECT COUNT(*) AS NumberOfRows FROM "tableName" WHERE "src" = ? AND "dst" = ?;
		
		sqlite3_bind_int64(statement, 1, srcRowid);
		
		if (dstFilePathEncryptor) {
			dstBlob = dstFilePathEncryptor(dstFilePath);
		}
		
		if (dstBlob)
		{
			sqlite3_bind_blob(statement, 2, dstBlob.bytes, (int)dstBlob.length, SQLITE_STATIC);
		}
		else
		{
			MakeYapDatabaseString(&_dstFilePath, dstFilePath);
			sqlite3_bind_text(statement, 2, _dstFilePath.str, _dstFilePath.length, SQLITE_STATIC);
		}
	}
	
	int64_t count = 0;
	
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, 0);
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
	if (!dstBlob) {
		FreeYapDatabaseString(&_dstFilePath);
	}
	
	return (NSUInteger)count;
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
	edge->edgeAction = YDB_EdgeActionInsert;
	
	// Add to manualChanges
	
	NSMutableArray *edges = [relationshipConnection->manualChanges objectForKey:edge->name];
	if (edges == nil)
	{
		edges = [[NSMutableArray alloc] initWithCapacity:1];
		[relationshipConnection->manualChanges setObject:edges forKey:edge->name];
	}
	else
	{
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *pendingEdge in edges)
		{
			if ([pendingEdge matchesManualEdge:edge])
			{
				// This edge replaces previous pending edge
				[edges replaceObjectAtIndex:i withObject:edge];
				return;
			}
			
			i++;
		}
	}
	
	YapDatabaseRelationshipEdge *matchingOnDiskEdge = [self findManualEdgeMatching:edge];
	if (matchingOnDiskEdge)
	{
		if (edge->nodeDeleteRules == matchingOnDiskEdge->nodeDeleteRules)
		{
			// Nothing changed
			return;
		}
		
		edge->edgeRowid = matchingOnDiskEdge->edgeRowid;
		edge->flags |= YDB_FlagsHasEdgeRowid;
		edge->edgeAction = YDB_EdgeActionUpdate;
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
	edge->edgeAction = YDB_EdgeActionDelete;
	
	if (reason == YDB_SourceNodeDeleted) {
		edge->flags |= YDB_FlagsSourceDeleted;
	}
	else if (reason == YDB_DestinationNodeDeleted) {
		edge->flags |= YDB_FlagsDestinationDeleted;
	}
	
	// Add to manualChanges
	
	NSMutableArray *edges = [relationshipConnection->manualChanges objectForKey:edge->name];
	if (edges == nil)
	{
		edges = [[NSMutableArray alloc] initWithCapacity:1];
		[relationshipConnection->manualChanges setObject:edges forKey:edge->name];
	}
	else
	{
		NSUInteger i = 0;
		for (YapDatabaseRelationshipEdge *pendingEdge in edges)
		{
			if ([pendingEdge matchesManualEdge:edge])
			{
				// This edge replaces previous pending edge
				
				edge->nodeDeleteRules = pendingEdge->nodeDeleteRules;
				
				if (pendingEdge->flags & YDB_FlagsHasEdgeRowid)
				{
					edge->edgeRowid = pendingEdge->edgeRowid;
					edge->flags |= YDB_FlagsHasEdgeRowid;
				}
				
				[edges replaceObjectAtIndex:i withObject:edge];
				return;
			}
			
			i++;
		}
	}
	
	YapDatabaseRelationshipEdge *matchingOnDiskEdge = [self findManualEdgeMatching:edge];
	if (matchingOnDiskEdge)
	{
		edge->nodeDeleteRules = matchingOnDiskEdge->nodeDeleteRules;
		edge->edgeRowid = matchingOnDiskEdge->edgeRowid;
		edge->flags |= YDB_FlagsHasEdgeRowid;
		
		[edges addObject:edge];
	}
	else
	{
		// Do nothing.
		// The edge doesn't exist, so no need to remove it.
	}
}

@end
