#import <Foundation/Foundation.h>

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
@class YapCollectionKey;

/**
 * This version number is stored in the yap2 table.
 * If there is a major re-write to this class, then the version number will be incremented,
 * and the class can automatically rebuild the tables as needed.
**/
#define YAP_DATABASE_VIEW_CLASS_VERSION 3

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseView () {
@public
	YapDatabaseViewGroupingBlock groupingBlock;
	YapDatabaseViewSortingBlock sortingBlock;
	
	YapDatabaseViewBlockType groupingBlockType;
	YapDatabaseViewBlockType sortingBlockType;
	
	NSString *versionTag;
	
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

- (id)initWithView:(YapDatabaseView *)view databaseConnection:(YapDatabaseConnection *)dbc;

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
	
	BOOL isRepopulate;
}

- (id)initWithViewConnection:(YapDatabaseViewConnection *)viewConnection
         databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

// The following are declared for view subclasses (such as YapDatabaseFilteredView)

- (void)dropTablesForOldClassVersion:(int)oldClassVersion;
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
- (void)removeAllRowidsInGroup:(NSString *)group;
- (void)removeAllRowids;

- (void)enumerateRowidsInGroup:(NSString *)group
                    usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block;
- (void)enumerateRowidsInGroup:(NSString *)group
                   withOptions:(NSEnumerationOptions)inOptions
                    usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block;

- (BOOL)containsRowid:(int64_t)rowid;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

enum {
	YDB_GroupingBlockChanged  = 1 << 0,
	YDB_SortingBlockChanged   = 1 << 1,
	YDB_FilteringBlockChanged = 1 << 2
};

@protocol YapDatabaseViewDependency <NSObject>
@optional

- (void)view:(NSString *)registeredName didRepopulateWithFlags:(int)flags;

@end
