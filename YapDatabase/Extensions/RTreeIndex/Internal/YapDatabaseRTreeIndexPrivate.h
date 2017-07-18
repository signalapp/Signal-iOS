#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseRTreeIndex.h"
#import "YapDatabaseRTreeIndexSetup.h"
#import "YapDatabaseRTreeIndexHandler.h"
#import "YapDatabaseRTreeIndexConnection.h"
#import "YapDatabaseRTreeIndexTransaction.h"

#import "YapCache.h"
#import "YapMutationStack.h"

#import "sqlite3.h"

/**
 * This version number is stored in the yap2 table.
 * If there is a major re-write to this class, then the version number will be incremented,
 * and the class can automatically rebuild the table as needed.
**/
#define YAP_DATABASE_RTREE_INDEX_CLASS_VERSION 1

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRTreeIndexHandler () {
@public
	
	YapDatabaseRTreeIndexBlock block;
	YapDatabaseBlockType       blockType;
	YapDatabaseBlockInvoke     blockInvokeOptions;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRTreeIndexSetup ()

/**
 * This method compares its setup to a current table structure.
 *
 * @param columns
 *   Dictionary of column names and affinity.
 *
 * @see YapDatabase columnNamesAndAffinityForTable:using:
**/
- (BOOL)matchesExistingColumnNamesAndAffinity:(NSDictionary *)columns;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRTreeIndex () {
@public

	YapDatabaseRTreeIndexHandler *handler;
	YapDatabaseRTreeIndexSetup *setup;
	YapDatabaseRTreeIndexOptions *options;

	NSString *versionTag;

	id columnNamesSharedKeySet;
}

- (NSString *)tableName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRTreeIndexConnection () {
@public

	__strong YapDatabaseRTreeIndex *parent;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;

	NSMutableDictionary *blockDict;

	YapCache *queryCache;
	NSUInteger queryCacheLimit;
	
	YapMutationStack_Bool *mutationStack;
}

- (id)initWithParent:(YapDatabaseRTreeIndex *)parent databaseConnection:(YapDatabaseConnection *)databaseConnection;

- (void)postCommitCleanup;
- (void)postRollbackCleanup;

- (sqlite3_stmt *)insertStatement;
- (sqlite3_stmt *)updateStatement;
- (sqlite3_stmt *)removeStatement;
- (sqlite3_stmt *)removeAllStatement;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRTreeIndexTransaction () {
@private

	__unsafe_unretained YapDatabaseRTreeIndexConnection *parentConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;
}

- (id)initWithParentConnection:(YapDatabaseRTreeIndexConnection *)parentConnection
           databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

@end
