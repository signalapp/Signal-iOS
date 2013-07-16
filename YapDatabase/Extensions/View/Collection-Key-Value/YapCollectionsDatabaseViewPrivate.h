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

- (NSString *)keyTableName;
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
	
	YapCache *keyCache;
	YapCache *pageCache;
	
	NSMutableDictionary *dirtyKeys;
	NSMutableDictionary *dirtyPages;
	NSMutableDictionary *dirtyMetadata;
	BOOL reset;
	
	BOOL lastInsertWasAtFirstIndex;
	BOOL lastInsertWasAtLastIndex;
	
	NSMutableArray *changes;
}

- (id)initWithView:(YapCollectionsDatabaseView *)view databaseConnection:(YapCollectionsDatabaseConnection *)dbc;

- (void)postCommitCleanup;

- (sqlite3_stmt *)keyTable_getPageKeyForCollectionKeyStatement;
- (sqlite3_stmt *)keyTable_setPageKeyForCollectionKeyStatement;
- (sqlite3_stmt *)keyTable_enumerateForCollectionStatement;
- (sqlite3_stmt *)keyTable_removeForCollectionKeyStatement;
- (sqlite3_stmt *)keyTable_removeForCollectionStatement;
- (sqlite3_stmt *)keyTable_removeAllStatement;

- (sqlite3_stmt *)pageTable_getDataForPageKeyStatement;
- (sqlite3_stmt *)pageTable_setAllForPageKeyStatement;
- (sqlite3_stmt *)pageTable_setMetadataForPageKeyStatement;
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
