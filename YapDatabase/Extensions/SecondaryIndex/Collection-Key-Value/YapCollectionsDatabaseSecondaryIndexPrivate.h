#import "YapCollectionsDatabase.h"
#import "YapCollectionsDatabaseConnection.h"
#import "YapCollectionsDatabaseTransaction.h"

#import "YapCollectionsDatabaseSecondaryIndex.h"
#import "YapCollectionsDatabaseSecondaryIndexConnection.h"
#import "YapCollectionsDatabaseSecondaryIndexTransaction.h"

#import "YapDatabaseSecondaryIndexSetup.h"
#import "YapCache.h"

#import "sqlite3.h"

@interface YapCollectionsDatabaseSecondaryIndex () {
@public
	
	YapDatabaseSecondaryIndexSetup *setup;
	
	YapCollectionsDatabaseSecondaryIndexBlock block;
	YapCollectionsDatabaseSecondaryIndexBlockType blockType;
	
	int version;
	
	id columnNamesSharedKeySet;
}

- (NSString *)tableName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapCollectionsDatabaseSecondaryIndexConnection () {
@public
	
	__strong YapCollectionsDatabaseSecondaryIndex *secondaryIndex;
	__unsafe_unretained YapCollectionsDatabaseConnection *databaseConnection;
	
	NSMutableDictionary *blockDict;
	
	YapCache *queryCache;
	NSUInteger queryCacheLimit;
}

- (id)initWithSecondaryIndex:(YapCollectionsDatabaseSecondaryIndex *)secondaryIndex
          databaseConnection:(YapCollectionsDatabaseConnection *)databaseConnection;

- (sqlite3_stmt *)insertStatement;
- (sqlite3_stmt *)updateStatement;
- (sqlite3_stmt *)removeStatement;
- (sqlite3_stmt *)removeAllStatement;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapCollectionsDatabaseSecondaryIndexTransaction () {
@private
	
	__unsafe_unretained YapCollectionsDatabaseSecondaryIndexConnection *secondaryIndexConnection;
	__unsafe_unretained YapCollectionsDatabaseReadTransaction *databaseTransaction;
	
	BOOL isMutated;
}

- (id)initWithSecondaryIndexConnection:(YapCollectionsDatabaseSecondaryIndexConnection *)secondaryIndexConnection
                   databaseTransaction:(YapCollectionsDatabaseReadTransaction *)databaseTransaction;

@end
