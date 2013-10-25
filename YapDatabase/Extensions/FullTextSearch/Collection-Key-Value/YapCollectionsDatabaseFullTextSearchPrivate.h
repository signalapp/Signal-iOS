#import "YapCollectionsDatabaseFullTextSearch.h"
#import "YapCollectionsDatabaseFullTextSearchConnection.h"
#import "YapCollectionsDatabaseFullTextSearchTransaction.h"

#import "YapCollectionsDatabase.h"
#import "YapCollectionsDatabaseConnection.h"
#import "YapCollectionsDatabaseTransaction.h"

#import "sqlite3.h"

@interface YapCollectionsDatabaseFullTextSearch () {
@public
	
	YapCollectionsDatabaseFullTextSearchBlock block;
	YapCollectionsDatabaseFullTextSearchBlockType blockType;
	
	NSOrderedSet *columnNames;
	NSDictionary *options;
	int version;
	
	id columnNamesSharedKeySet;
}

- (NSString *)tableName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapCollectionsDatabaseFullTextSearchConnection () {
@public
	
	__strong YapCollectionsDatabaseFullTextSearch *fts;
	__unsafe_unretained YapCollectionsDatabaseConnection *databaseConnection;
	
	NSMutableDictionary *blockDict;
}

- (id)initWithFTS:(YapCollectionsDatabaseFullTextSearch *)fts
   databaseConnection:(YapCollectionsDatabaseConnection *)databaseConnection;

- (sqlite3_stmt *)insertRowidStatement;
- (sqlite3_stmt *)setRowidStatement;
- (sqlite3_stmt *)removeRowidStatement;
- (sqlite3_stmt *)removeAllStatement;
- (sqlite3_stmt *)queryStatement;
- (sqlite3_stmt *)querySnippetStatement;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapCollectionsDatabaseFullTextSearchTransaction () {
@private
	
	__unsafe_unretained YapCollectionsDatabaseFullTextSearchConnection *ftsConnection;
	__unsafe_unretained YapCollectionsDatabaseReadTransaction *databaseTransaction;
	
	BOOL isMutated;
}

- (id)initWithFTSConnection:(YapCollectionsDatabaseFullTextSearchConnection *)ftsConnection
        databaseTransaction:(YapCollectionsDatabaseReadTransaction *)databaseTransaction;

@end