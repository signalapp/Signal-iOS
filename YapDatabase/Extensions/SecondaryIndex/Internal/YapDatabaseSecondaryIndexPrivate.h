#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseSecondaryIndex.h"
#import "YapDatabaseSecondaryIndexSetup.h"
#import "YapDatabaseSecondaryIndexHandler.h"
#import "YapDatabaseSecondaryIndexConnection.h"
#import "YapDatabaseSecondaryIndexTransaction.h"

#import "YapCache.h"

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

@interface YapDatabaseSecondaryIndexHandler ()

+ (instancetype)withBlock:(YapDatabaseSecondaryIndexBlock)block blockType:(YapDatabaseSecondaryIndexBlockType)blockType;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseSecondaryIndex () {
@public
	
	YapDatabaseSecondaryIndexSetup *setup;
	YapDatabaseSecondaryIndexOptions *options;
	
	YapDatabaseSecondaryIndexBlock block;
	YapDatabaseSecondaryIndexBlockType blockType;
	
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
	
	__strong YapDatabaseSecondaryIndex *secondaryIndex;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;
	
	NSMutableDictionary *blockDict;
	
	YapCache *queryCache;
	NSUInteger queryCacheLimit;
}

- (id)initWithSecondaryIndex:(YapDatabaseSecondaryIndex *)secondaryIndex
          databaseConnection:(YapDatabaseConnection *)databaseConnection;

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
	
	__unsafe_unretained YapDatabaseSecondaryIndexConnection *secondaryIndexConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;
	
	BOOL isMutated;
}

- (id)initWithSecondaryIndexConnection:(YapDatabaseSecondaryIndexConnection *)secondaryIndexConnection
                   databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

@end
