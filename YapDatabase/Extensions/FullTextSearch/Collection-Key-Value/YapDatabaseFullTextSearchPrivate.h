#import "YapDatabaseFullTextSearch.h"
#import "YapDatabaseFullTextSearchConnection.h"
#import "YapDatabaseFullTextSearchTransaction.h"

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "sqlite3.h"

@interface YapDatabaseFullTextSearch () {
@public
	
	YapDatabaseFullTextSearchBlock block;
	YapDatabaseFullTextSearchBlockType blockType;
	
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

@interface YapDatabaseFullTextSearchConnection () {
@public
	
	__strong YapDatabaseFullTextSearch *fts;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;
	
	NSMutableDictionary *blockDict;
}

- (id)initWithFTS:(YapDatabaseFullTextSearch *)fts
   databaseConnection:(YapDatabaseConnection *)databaseConnection;

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

@interface YapDatabaseFullTextSearchTransaction () {
@private
	
	__unsafe_unretained YapDatabaseFullTextSearchConnection *ftsConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;
	
	BOOL isMutated;
}

- (id)initWithFTSConnection:(YapDatabaseFullTextSearchConnection *)ftsConnection
        databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

@end