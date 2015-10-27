#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseSecondaryIndex.h"
#import "YapDatabaseSecondaryIndexSetup.h"
#import "YapDatabaseSecondaryIndexHandler.h"
#import "YapDatabaseSecondaryIndexConnection.h"
#import "YapDatabaseSecondaryIndexTransaction.h"

#import "YapCache.h"
#import "YapMutationStack.h"
#import "YapDatabaseStatement.h"

#import "sqlite3.h"

/**
 * This version number is stored in the yap2 table.
 * If there is a major re-write to this class, then the version number will be incremented,
 * and the class can automatically rebuild the table as needed.
**/
#define YAP_DATABASE_SECONDARY_INDEX_CLASS_VERSION 1

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseSecondaryIndexHandler () {
@public
	
	YapDatabaseSecondaryIndexBlock block;
	YapDatabaseBlockType           blockType;
	YapDatabaseBlockInvoke         blockInvokeOptions;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseSecondaryIndexSetup ()

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

@interface YapDatabaseSecondaryIndex () {
@public
	
	YapDatabaseSecondaryIndexSetup *setup;
	YapDatabaseSecondaryIndexOptions *options;
	
	YapDatabaseSecondaryIndexHandler *handler;
	
	NSString *versionTag;
	
	id columnNamesSharedKeySet;
}

- (NSString *)tableName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseSecondaryIndexConnection () {
@public
	
	__strong YapDatabaseSecondaryIndex *parent;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;
	
	NSMutableDictionary *blockDict;
	
	YapCache<NSString *, YapDatabaseStatement *> *queryCache;
	NSUInteger queryCacheLimit;
	
	YapMutationStack_Bool *mutationStack;
}

- (id)initWithParent:(YapDatabaseSecondaryIndex *)parent
  databaseConnection:(YapDatabaseConnection *)databaseConnection;

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

@interface YapDatabaseSecondaryIndexTransaction () {
@private
	
	__unsafe_unretained YapDatabaseSecondaryIndexConnection *parentConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;
}

- (id)initWithParentConnection:(YapDatabaseSecondaryIndexConnection *)parentConnection
           databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

@end
