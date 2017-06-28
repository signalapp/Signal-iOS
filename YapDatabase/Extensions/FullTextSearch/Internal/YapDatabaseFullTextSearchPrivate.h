#import "YapDatabaseFullTextSearch.h"
#import "YapDatabaseFullTextSearchHandler.h"
#import "YapDatabaseFullTextSearchConnection.h"
#import "YapDatabaseFullTextSearchTransaction.h"

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapMutationStack.h"

#import "sqlite3.h"

/**
 * This version number is stored in the yap2 table.
 * If there is a major re-write to this class, then the version number will be incremented,
 * and the class can automatically rebuild the tables as needed.
**/
#define YAP_DATABASE_FTS_CLASS_VERSION 1

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseFullTextSearchHandler () {
@public
	
	YapDatabaseFullTextSearchBlock block;
	YapDatabaseBlockType           blockType;
	YapDatabaseBlockInvoke         blockInvokeOptions;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseFullTextSearch () {
@public
	
	YapDatabaseFullTextSearchHandler *handler;
	
	NSOrderedSet *columnNames;
	NSDictionary *options;
	NSString *ftsVersion;
	NSString *versionTag;
	
	id columnNamesSharedKeySet;
}

- (NSString *)tableName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseFullTextSearchConnection () {
@public
	
	__strong YapDatabaseFullTextSearch *parent;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;
	
	NSMutableDictionary *blockDict;
	
	YapMutationStack_Bool *mutationStack;
}

- (id)initWithParent:(YapDatabaseFullTextSearch *)parent databaseConnection:(YapDatabaseConnection *)databaseConnection;

- (void)postCommitCleanup;
- (void)postRollbackCleanup;

- (sqlite3_stmt *)insertRowidStatement;
- (sqlite3_stmt *)setRowidStatement;
- (sqlite3_stmt *)removeRowidStatement;
- (sqlite3_stmt *)removeAllStatement;
- (sqlite3_stmt *)queryStatement;
- (sqlite3_stmt *)bm25QueryStatement;
- (sqlite3_stmt *)bm25QueryStatementWithWeights:(NSArray<NSNumber *> *)weights;
- (sqlite3_stmt *)querySnippetStatement;
- (sqlite3_stmt *)rowidQueryStatement;
- (sqlite3_stmt *)rowidQuerySnippetStatement;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseFullTextSearchTransaction () {
@private
	
	__unsafe_unretained YapDatabaseFullTextSearchConnection *parentConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;
}

- (id)initWithParentConnection:(YapDatabaseFullTextSearchConnection *)parentConnection
           databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

- (void)enumerateRowidsMatching:(NSString *)query
                     usingBlock:(void (^)(int64_t rowid, BOOL *stop))block;

- (void)enumerateRowidsMatching:(NSString *)query
             withSnippetOptions:(YapDatabaseFullTextSearchSnippetOptions *)inOptions
                     usingBlock:
            (void (^)(NSString *snippet, int64_t rowid, BOOL *stop))block;

- (BOOL)rowid:(int64_t)rowid matches:(NSString *)query;
- (NSString *)rowid:(int64_t)rowid matches:(NSString *)query
                        withSnippetOptions:(YapDatabaseFullTextSearchSnippetOptions *)options;

@end
