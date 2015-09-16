#import "YapDatabaseSearchResultsView.h"
#import "YapDatabaseSearchResultsViewOptions.h"
#import "YapDatabaseSearchResultsViewConnection.h"
#import "YapDatabaseSearchResultsViewTransaction.h"

#import "YapDatabaseViewPrivate.h"

/**
 * This version number is stored in the yap2 table.
 * If there is a major re-write to this class, then the version number will be incremented,
 * and the class can automatically rebuild the tables as needed.
**/
#define YAP_DATABASE_SEARCH_RESULTS_VIEW_CLASS_VERSION 1

/**
 * Changeset keys (for changeset notification dictionary)
**/
static NSString *const changeset_key_query = @"query";

@interface YapDatabaseSearchResultsViewOptions ()

@property (nonatomic, strong, readonly) YapDatabaseFullTextSearchSnippetOptions *snippetOptions_NoCopy;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseSearchResultsView () {
@public
	
	NSString *parentViewName;
	NSString *fullTextSearchName;
}

- (NSString *)snippetTableName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseSearchResultsViewConnection () {
@private
	
	NSString *query;
	BOOL queryChanged;
}

- (NSString *)query;
- (void)setQuery:(NSString *)newQuery isChange:(BOOL)isChange;
- (void)getQuery:(NSString **)queryPtr wasChanged:(BOOL *)wasChangedPtr;

- (sqlite3_stmt *)snippetTable_getForRowidStatement;
- (sqlite3_stmt *)snippetTable_setForRowidStatement;
- (sqlite3_stmt *)snippetTable_removeForRowidStatement;
- (sqlite3_stmt *)snippetTable_removeAllStatement;

- (void)setGrouping:(YapDatabaseViewGrouping *)newGrouping
            sorting:(YapDatabaseViewSorting *)newSorting;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseSearchResultsViewTransaction () {
@private
	
	YapMemoryTableTransaction *snippetTableTransaction;
}

@end
