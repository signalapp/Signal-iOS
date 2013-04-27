#import <Foundation/Foundation.h>

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
}

- (NSString *)keyTableName;
- (NSString *)pageTableName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewConnection () {
@public
	
	NSMutableDictionary *groupPagesDict;   // section -> @[ YapDatabaseViewPageMetadata, ... ]
	NSMutableDictionary *pageKeyGroupDict; // pageKey -> group
	
	NSMutableDictionary *dirtyKeys;
	NSMutableDictionary *dirtyPages;
	NSMutableDictionary *dirtyMetadata;
	
	YapCache *keyCache;
	YapCache *pageCache;
}

- (BOOL)isOpen;

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
