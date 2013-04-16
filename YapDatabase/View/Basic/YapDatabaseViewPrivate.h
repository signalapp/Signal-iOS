#import <Foundation/Foundation.h>

#import "YapDatabaseView.h"
#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewTransaction.h"

#import "sqlite3.h"

@class YapCache;


@interface YapDatabaseView () {
@public
	YapDatabaseViewFilterBlock filterBlock;
	YapDatabaseViewSortBlock sortBlock;
	
	YapDatabaseViewBlockType filterBlockType;
	YapDatabaseViewBlockType sortBlockType;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewConnection () {
@private
	sqlite3_stmt *getDataForKeyStatement;
	sqlite3_stmt *setMetadataForKeyStatement;
	sqlite3_stmt *setAllForKeyStatement;
	sqlite3_stmt *removeForKeyStatement;
	sqlite3_stmt *removeAllStatement;
	sqlite3_stmt *enumerateMetadataStatement;
	
@public
	
	NSMutableDictionary *sectionPagesDict; // section -> @[ pageMetadata, ... ]
	
	NSMutableDictionary *dirtyKeys;
	NSMutableDictionary *dirtyPages;
	
	YapCache *keyCache;
	YapCache *pageCache;
}

- (BOOL)isOpen;

- (sqlite3_stmt *)getDataForKeyStatement;
//- (sqlite3_stmt *)setMetadataForKeyStatement;
//- (sqlite3_stmt *)setAllForKeyStatement;
//- (sqlite3_stmt *)removeForKeyStatement;
//- (sqlite3_stmt *)removeAllStatement;
//- (sqlite3_stmt *)enumerateMetadataStatement;

@end
