#import <Foundation/Foundation.h>

#import "YapCollectionsDatabase.h"
#import "YapCollectionsDatabaseConnection.h"
#import "YapCollectionsDatabaseTransaction.h"

#import "YapCollectionsDatabaseView.h"
#import "YapCollectionsDatabaseViewConnection.h"
#import "YapCollectionsDatabaseViewTransaction.h"

#import "sqlite3.h"

@class YapCache;

@interface YapCollectionsDatabaseView () {
@public
	YapCollectionsDatabaseViewGroupingBlock groupingBlock;
	YapCollectionsDatabaseViewSortingBlock sortingBlock;
	
	YapCollectionsDatabaseViewBlockType groupingBlockType;
	YapCollectionsDatabaseViewBlockType sortingBlockType;
	
	int version;
}

- (NSString *)mapTableName;
- (NSString *)pageTableName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapCollectionsDatabaseViewConnection () {
@public
	
	__strong YapCollectionsDatabaseView *view;
	__unsafe_unretained YapCollectionsDatabaseConnection *databaseConnection;
	
	NSMutableDictionary *group_pagesMetadata_dict; // group -> @[ YapDatabaseViewPageMetadata, ... ]
	NSMutableDictionary *pageKey_group_dict;       // pageKey -> group
	
	YapCache *mapCache;
	YapCache *pageCache;
	
	NSMutableDictionary *dirtyMaps;
	NSMutableDictionary *dirtyPages;
	NSMutableDictionary *dirtyLinks;
	BOOL reset;
	
	BOOL lastInsertWasAtFirstIndex;
	BOOL lastInsertWasAtLastIndex;
	
	NSMutableArray *changes;
	NSMutableSet *mutatedGroups;
}

- (id)initWithView:(YapCollectionsDatabaseView *)view databaseConnection:(YapCollectionsDatabaseConnection *)dbc;

- (void)postRollbackCleanup;
- (void)postCommitCleanup;

- (sqlite3_stmt *)mapTable_getPageKeyForRowidStatement;
- (sqlite3_stmt *)mapTable_setPageKeyForRowidStatement;
- (sqlite3_stmt *)mapTable_removeForRowidStatement;
- (sqlite3_stmt *)mapTable_removeAllStatement;

- (sqlite3_stmt *)pageTable_getDataForPageKeyStatement;
- (sqlite3_stmt *)pageTable_insertForPageKeyStatement;
- (sqlite3_stmt *)pageTable_updateAllForPageKeyStatement;
- (sqlite3_stmt *)pageTable_updatePageForPageKeyStatement;
- (sqlite3_stmt *)pageTable_updateLinkForPageKeyStatement;
- (sqlite3_stmt *)pageTable_removeForPageKeyStatement;
- (sqlite3_stmt *)pageTable_removeAllStatement;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapCollectionsDatabaseViewTransaction () {
@private
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection;
	__unsafe_unretained YapCollectionsDatabaseReadTransaction *databaseTransaction;
}

- (id)initWithViewConnection:(YapCollectionsDatabaseViewConnection *)viewConnection
         databaseTransaction:(YapCollectionsDatabaseReadTransaction *)databaseTransaction;

@end
