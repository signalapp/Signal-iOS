#import "YapDatabaseRelationshipConnection.h"
#import "YapDatabaseRelationshipPrivate.h"
#import "YapCollectionKey.h"
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


@implementation YapDatabaseRelationshipConnection

@synthesize relationship = relationship;

- (id)initWithRelationship:(YapDatabaseRelationship *)inRelationship databaseConnection:(YapDatabaseConnection *)inDbC
{
	if ((self = [super init]))
	{
		relationship = inRelationship;
		databaseConnection = inDbC;
		
		cache = [[YapCache alloc] initWithKeyClass:[YapCollectionKey class]];
	}
	return self;
}

- (void)dealloc
{
//	sqlite_finalize_null(&...);
}

/**
 * Required override method from YapDatabaseExtensionConnection
**/
- (void)_flushMemoryWithLevel:(int)level
{
	if (level >= YapDatabaseConnectionFlushMemoryLevelMild)
	{
		[cache removeAllObjects];
	}
	
	if (level >= YapDatabaseConnectionFlushMemoryLevelModerate)
	{
	//	sqlite_finalize_null(&...);
	}
	
	if (level >= YapDatabaseConnectionFlushMemoryLevelFull)
	{
	//	sqlite_finalize_null(&...);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (YapDatabaseExtension *)extension
{
	return relationship;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YapDatabaseRelationshipTransaction *transaction =
	    [[YapDatabaseRelationshipTransaction alloc] initWithRelationshipConnection:self
	                                                           databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseRelationshipTransaction *transaction =
	    [[YapDatabaseRelationshipTransaction alloc] initWithRelationshipConnection:self
	                                                           databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return transaction;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Initializes any ivars that a read-write transaction may need.
**/
- (void)prepareForReadWriteTransaction
{
	if (pendingInserts == nil)
		pendingInserts = [[NSMutableDictionary alloc] init];
	if (pendingDeletes == nil)
		pendingDeletes = [[NSMutableDictionary alloc] init];
	if (pendingUpdates == nil)
		pendingUpdates = [[NSMutableDictionary alloc] init];
	if (pendingOrphans == nil)
		pendingOrphans = [[NSMutableDictionary alloc] init];
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the rollbackTransaction method.
**/
- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	
	[cache removeAllObjects];
	
	[pendingInserts removeAllObjects];
	[pendingDeletes removeAllObjects];
	[pendingUpdates removeAllObjects];
	[pendingOrphans removeAllObjects];
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the commitTransaction method.
**/
- (void)postCommitCleanup
{
	[pendingInserts removeAllObjects];
	[pendingDeletes removeAllObjects];
	[pendingUpdates removeAllObjects];
	[pendingOrphans removeAllObjects];
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr
{
	YDBLogAutoTrace();
	
	NSMutableDictionary *internalChangeset = nil;
	NSMutableDictionary *externalChangeset = nil;
	BOOL hasDiskChanges = NO;
	
	// Todo... ?
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
	*hasDiskChangesPtr = hasDiskChanges;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	// Todo... ?
}



@end
