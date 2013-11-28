#import <Foundation/Foundation.h>

#import "YapCollectionsDatabase.h"
#import "YapCollectionsDatabaseConnection.h"
#import "YapCollectionsDatabaseTransaction.h"

#import "YapCollectionsDatabaseView.h"
#import "YapCollectionsDatabaseViewOptions.h"
#import "YapCollectionsDatabaseViewConnection.h"
#import "YapCollectionsDatabaseViewTransaction.h"

#import "YapMemoryTable.h"

#import "sqlite3.h"

@class YapCache;
@class YapCollectionKey;

/**
 * This version number is stored in the yap2 table.
 * If there is a major re-write to this class, then the version number will be incremented,
 * and the class can automatically rebuild the tables as needed.
**/
#define YAP_COLLECTIONS_DATABASE_VIEW_CLASS_VERSION 3


@interface YapCollectionsDatabaseView () {
@public
	YapCollectionsDatabaseViewGroupingBlock groupingBlock;
	YapCollectionsDatabaseViewSortingBlock sortingBlock;
	
	YapCollectionsDatabaseViewBlockType groupingBlockType;
	YapCollectionsDatabaseViewBlockType sortingBlockType;
	
	int version;
	
	YapCollectionsDatabaseViewOptions *options;
}

- (NSString *)mapTableName;
- (NSString *)pageTableName;
- (NSString *)pageMetadataTableName;

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

@interface YapCollectionsDatabaseViewTransaction () {
@private
	
	YapMemoryTableTransaction *mapTableTransaction;
	YapMemoryTableTransaction *pageTableTransaction;
	YapMemoryTableTransaction *pageMetadataTableTransaction;
	
@protected
	
	__unsafe_unretained YapCollectionsDatabaseViewConnection *viewConnection;
	__unsafe_unretained YapCollectionsDatabaseReadTransaction *databaseTransaction;
	
	NSString *lastHandledGroup;
}

- (id)initWithViewConnection:(YapCollectionsDatabaseViewConnection *)viewConnection
         databaseTransaction:(YapCollectionsDatabaseReadTransaction *)databaseTransaction;

// The following are declared for view subclasses (such as YapCollectionsDatabaseFilteredView)

- (BOOL)createTables;

- (NSString *)registeredName;
- (BOOL)isPersistentView;

- (NSString *)pageKeyForRowid:(int64_t)rowid;
- (NSUInteger)indexForRowid:(int64_t)rowid inGroup:(NSString *)group withPageKey:(NSString *)pageKey;
- (BOOL)getRowid:(int64_t *)rowidPtr atIndex:(NSUInteger)index inGroup:(NSString *)group;

- (void)insertRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey inNewGroup:(NSString *)group;
- (void)insertRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
                                         inGroup:(NSString *)group
                                         atIndex:(NSUInteger)index
                             withExistingPageKey:(NSString *)existingPageKey;

- (void)insertRowid:(int64_t)rowid
      collectionKey:(YapCollectionKey *)collectionKey
			 object:(id)object
           metadata:(id)metadata
            inGroup:(NSString *)group
        withChanges:(int)flags
              isNew:(BOOL)isGuaranteedNew;

- (void)removeRowid:(int64_t)rowid
      collectionKey:(YapCollectionKey *)collectionKey
            atIndex:(NSUInteger)index
            inGroup:(NSString *)group;

- (void)removeRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey;
- (void)removeAllRowids;

- (void)enumerateRowidsInGroup:(NSString *)group
                    usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block;

@end
