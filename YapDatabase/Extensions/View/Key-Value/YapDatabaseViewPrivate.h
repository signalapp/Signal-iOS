#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseView.h"
#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewTransaction.h"

#import "sqlite3.h"

@class YapCache;


@interface YapDatabaseView () {
@public
	YapDatabaseViewGroupingBlock groupingBlock;
	YapDatabaseViewSortingBlock sortingBlock;
	
	YapDatabaseViewBlockType groupingBlockType;
	YapDatabaseViewBlockType sortingBlockType;
	
	int version;
}

- (NSString *)keyTableName;
- (NSString *)pageTableName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewConnection () {
@public
	
	__strong YapDatabaseView *view;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;
	
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
	NSMutableSet *mutatedGroups;
}

- (id)initWithView:(YapDatabaseView *)view databaseConnection:(YapDatabaseConnection *)databaseConnection;

- (void)postCommitCleanup;

- (sqlite3_stmt *)keyTable_getPageKeyForKeyStatement;
- (sqlite3_stmt *)keyTable_setPageKeyForKeyStatement;
- (sqlite3_stmt *)keyTable_removeForKeyStatement;
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

@interface YapDatabaseViewTransaction () {
@private
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;
}

- (id)initWithViewConnection:(YapDatabaseViewConnection *)viewConnection
         databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

@end
