#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseRTreeIndex.h"
#import "YapDatabaseRTreeIndexSetup.h"
#import "YapDatabaseRTreeIndexHandler.h"
#import "YapDatabaseRTreeIndexConnection.h"
#import "YapDatabaseRTreeIndexTransaction.h"

#import "YapCache.h"

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

@interface YapDatabaseRTreeIndexSetup ()

/**
 * This method compares its setup to a current table structure.
 *
 * @param columns
 *
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

	YapDatabaseRTreeIndexSetup *setup;
	YapDatabaseRTreeIndexOptions *options;

	YapDatabaseRTreeIndexBlock block;
	YapDatabaseRTreeIndexBlockType blockType;

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

	__strong YapDatabaseRTreeIndex *rTreeIndex;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;

	NSMutableDictionary *blockDict;

	YapCache *queryCache;
	NSUInteger queryCacheLimit;
}

- (id)initWithRTreeIndex:(YapDatabaseRTreeIndex *)rTreeIndex
          databaseConnection:(YapDatabaseConnection *)databaseConnection;

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

	__unsafe_unretained YapDatabaseRTreeIndexConnection *rTreeIndexConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;

	BOOL isMutated;
}

- (id)initWithRTreeIndexConnection:(YapDatabaseRTreeIndexConnection *)rTreeIndexConnection
                   databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

@end
