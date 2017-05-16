#import <Foundation/Foundation.h>

#import "YapDatabaseView.h"
#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseViewOptions.h"

#import "YapDatabaseViewLocator.h"
#import "YapDatabaseViewPage.h"
#import "YapDatabaseViewPageMetadata.h"
#import "YapDatabaseViewState.h"

#import "YapDatabaseViewChangePrivate.h"
#import "YapDatabaseViewMappingsPrivate.h"
#import "YapDatabaseViewRangeOptionsPrivate.h"

#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabasePrivate.h"

#import "YapDirtyDictionary.h"

/**
 * This version number is stored in the yap2 table.
 * If there is a major re-write to this class, then the version number will be incremented,
 * and the class can automatically rebuild the tables as needed.
**/
#define YAP_DATABASE_VIEW_CLASS_VERSION 3

/**
 * The view is tasked with storing ordered arrays of rowids.
 * In doing so, it splits the array into "pages" of rowids, and stores the pages in the database.
 * This reduces disk IO, as only the contents of a single page are written for a single change.
 * And only the contents of a single page need be read to fetch a single rowid.
**/
#define YAP_DATABASE_VIEW_MAX_PAGE_SIZE 50

/**
 * Keys for yap2 extension configuration table.
**/

static NSString *const ext_key_classVersion       = @"classVersion";
static NSString *const ext_key_versionTag         = @"versionTag";
static NSString *const ext_key_version_deprecated = @"version";     // used by old versions of YapDatabaseView
static NSString *const ext_key_tag_deprecated     = @"tag";         // used by old versions of YapDatabaseFilteredView

/**
 * Keys for changeset dictionary.
**/

static NSString *const changeset_key_state      = @"state";
static NSString *const changeset_key_dirtyMaps  = @"dirtyMaps";
static NSString *const changeset_key_dirtyPages = @"dirtyPages";
static NSString *const changeset_key_reset      = @"reset";

static NSString *const changeset_key_grouping   = @"grouping";
static NSString *const changeset_key_sorting    = @"sorting";
static NSString *const changeset_key_versionTag = @"versionTag";

static NSString *const changeset_key_changes    = @"changes";


@interface YapDatabaseView () {
@protected
	
	NSString *versionTag;
	
	YapDatabaseViewState *latestState;
	
@public
	
	YapDatabaseViewOptions *options;
}

- (instancetype)initWithVersionTag:(NSString *)versionTag
                           options:(YapDatabaseViewOptions *)options;

- (NSString *)mapTableName;
- (NSString *)pageTableName;
- (NSString *)pageMetadataTableName;

- (BOOL)getState:(YapDatabaseViewState **)statePtr
   forConnection:(YapDatabaseViewConnection *)connection;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewConnection () {
@protected
	
	id sharedKeySetForInternalChangeset;
	id sharedKeySetForExternalChangeset;
	
	NSString *versionTag;
	
	BOOL versionTagChanged;
	
@public
	
	__strong YapDatabaseView *parent;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;
	
	YapDatabaseViewState *state;
	
	YapCache *mapCache;
	YapCache *pageCache;
	
	YapDirtyDictionary  *dirtyMaps;
	NSMutableDictionary *dirtyPages;
	NSMutableDictionary *dirtyLinks;
	BOOL reset;
	
	NSMutableArray *changes;
	NSMutableSet *mutatedGroups;
}

- (instancetype)initWithParent:(YapDatabaseView *)parent databaseConnection:(YapDatabaseConnection *)dbc;
- (void)_flushStatements;

- (BOOL)isPersistentView;

- (void)prepareForReadWriteTransaction;
- (void)postCommitCleanup;
- (void)postRollbackCleanup;

- (NSArray *)internalChangesetKeys;
- (NSArray *)externalChangesetKeys;

- (void)prepareStatement:(sqlite3_stmt **)statement withString:(NSString *)stmtString caller:(SEL)caller_cmd;

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
	
	__unsafe_unretained YapDatabaseViewConnection *parentConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;
	
	BOOL isRepopulate;
}

- (instancetype)initWithParentConnection:(YapDatabaseViewConnection *)parentConnection
                     databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

- (void)dropTablesForOldClassVersion:(int)oldClassVersion;

- (BOOL)createTables;
- (BOOL)populateView;

- (NSString *)registeredName;
- (BOOL)isPersistentView;

- (NSString *)mapTableName;
- (NSString *)pageTableName;
- (NSString *)pageMetadataTableName;

- (void)enumerateRowidsInGroup:(NSString *)group
                    usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block;
- (void)enumerateRowidsInGroup:(NSString *)group
                   withOptions:(NSEnumerationOptions)inOptions
                    usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block;
- (void)enumerateRowidsInGroup:(NSString *)group
                   withOptions:(NSEnumerationOptions)inOptions
                         range:(NSRange)range
                    usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block;

// Logic - ReadOnly

- (BOOL)containsRowid:(int64_t)rowid;
- (NSString *)groupForRowid:(int64_t)rowid;

- (YapDatabaseViewLocator *)locatorForRowid:(int64_t)rowid;
- (NSDictionary *)locatorsForRowids:(NSArray *)rowids;

- (BOOL)getRowid:(int64_t *)rowidPtr atIndex:(NSUInteger)index inGroup:(NSString *)group;

// Logic - ReadWrite

- (void)insertRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
                                         inGroup:(NSString *)group
                                         atIndex:(NSUInteger)index;

- (void)removeRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey;

- (void)removeRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
                                         atIndex:(NSUInteger)index
                                         inGroup:(NSString *)group;

- (void)removeRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
                                     withLocator:(YapDatabaseViewLocator *)locator;

- (void)removeRowidsWithCollectionKeys:(NSDictionary<NSNumber *, YapCollectionKey *> *)collectionKeys
                              locators:(NSDictionary<NSNumber *, YapDatabaseViewLocator *> *)locators;

- (void)removeAllRowidsInGroup:(NSString *)group;
- (void)removeAllRowids;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

enum {
	YDB_GroupingMayHaveChanged  = 1 << 0,
	YDB_SortingMayHaveChanged   = 1 << 1,
	YDB_FilteringMayHaveChanged = 1 << 2
};

@protocol YapDatabaseViewDependency <NSObject>
@optional

- (void)view:(NSString *)registeredName didRepopulateWithFlags:(int)flags;

@end
