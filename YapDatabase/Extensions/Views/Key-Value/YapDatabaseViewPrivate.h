#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseView.h"
#import "YapDatabaseViewOptions.h"
#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewTransaction.h"

#import "YapMemoryTable.h"

#import "sqlite3.h"

@class YapCache;


@interface YapDatabaseView () {
@public
	YapDatabaseViewGroupingBlock groupingBlock;
	YapDatabaseViewSortingBlock sortingBlock;
	
	YapDatabaseViewBlockType groupingBlockType;
	YapDatabaseViewBlockType sortingBlockType;
	
	int version;
	YapDatabaseViewOptions *options;
}

- (NSString *)mapTableName;
- (NSString *)pageTableName;
- (NSString *)pageMetadataTableName;

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

- (id)initWithView:(YapDatabaseView *)view databaseConnection:(YapDatabaseConnection *)databaseConnection;

- (void)prepareForReadWriteTransaction;
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

@interface YapDatabaseViewTransaction () {
@private
	
	YapMemoryTableTransaction *mapTableTransaction;
	YapMemoryTableTransaction *pageTableTransaction;
	YapMemoryTableTransaction *pageMetadataTableTransaction;
	
@protected
	
	__unsafe_unretained YapDatabaseViewConnection *viewConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;
	
	NSString *lastHandledGroup;
}

- (id)initWithViewConnection:(YapDatabaseViewConnection *)viewConnection
         databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

// The following are declared for view subclasses (such as YapDatabaseFilteredView)

- (NSString *)pageKeyForRowid:(int64_t)rowid;
- (NSUInteger)indexForRowid:(int64_t)rowid inGroup:(NSString *)group withPageKey:(NSString *)pageKey;

- (void)insertRowid:(int64_t)rowid key:(NSString *)key inNewGroup:(NSString *)group;
- (void)insertRowid:(int64_t)rowid key:(NSString *)key
                               inGroup:(NSString *)group
                               atIndex:(NSUInteger)index
                   withExistingPageKey:(NSString *)existingPageKey;

- (void)insertRowid:(int64_t)rowid
                key:(NSString *)key
             object:(id)object
           metadata:(id)metadata
            inGroup:(NSString *)group
        withChanges:(int)flags
              isNew:(BOOL)isGuaranteedNew;

- (void)removeRowid:(int64_t)rowid key:(NSString *)key;
- (void)removeAllRowids;

- (void)enumerateRowidsInGroup:(NSString *)group
                    usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block;

@end
