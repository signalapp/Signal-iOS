#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseSecondaryIndex.h"
#import "YapDatabaseSecondaryIndexConnection.h"
#import "YapDatabaseSecondaryIndexTransaction.h"

#import "YapDatabaseSecondaryIndexSetup.h"
#import "YapCache.h"

#import "sqlite3.h"

@interface YapDatabaseSecondaryIndex () {
@public
	
	YapDatabaseSecondaryIndexSetup *setup;
	
	YapDatabaseSecondaryIndexBlock block;
	YapDatabaseSecondaryIndexBlockType blockType;
	
	int version;
	
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
