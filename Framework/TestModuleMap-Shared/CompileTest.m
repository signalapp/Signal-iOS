#import "CompileTest.h"

@import YapDatabase;

// Automatically included with: @import YapDatabase;
// May be explicitly @import'ed if only utility classes are needed.
//
//@import YapDatabase.Utilities;

@import YapDatabase.YapDatabaseView;
@import YapDatabase.YapDatabaseFilteredView;
@import YapDatabase.YapDatabaseRelationship;
@import YapDatabase.YapDatabaseSecondaryIndex;
@import YapDatabase.YapDatabaseFullTextSearch;
@import YapDatabase.YapDatabaseSearchResultsView;
@import YapDatabase.YapDatabaseHooks;
@import YapDatabase.YapDatabaseRTreeIndex;
@import YapDatabase.YapDatabaseConnectionProxy;
#if !TARGET_OS_WATCH
@import YapDatabase.YapDatabaseCloudKit;
#endif
#if !TARGET_OS_TV && !TARGET_OS_WATCH
@import YapDatabase.YapDatabaseActionManager;
#endif

@implementation CompileTest

- (void)willItCompile
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused"
	
	YapDatabase *database;
	
	YapCache *cache;
	YapCollectionKey *collectionKey;
	YapDatabaseQuery *query;
	YapWhitelistBlacklist *whitelist;
	
	YapDatabaseView *view;
//	YapDatabaseViewPageMetadata *_should_NOT_compile; // private header
	
	YapDatabaseFilteredView *filteredView;
	YapDatabaseRelationship *relationship;
	YapDatabaseSecondaryIndex *secondaryIndex;
	YapDatabaseFullTextSearch *fullTextSearch;
	YapDatabaseSearchResultsView *searchResultsView;
	YapDatabaseHooks *hooks;
	YapDatabaseRTreeIndex *rTreeIndex;
	YapDatabaseConnectionProxy *connectionProxy;
#if !TARGET_OS_WATCH
	YapDatabaseCloudKit *cloudKit;
#endif
#if !TARGET_OS_TV && !TARGET_OS_WATCH
	YapDatabaseActionManager *actionManager;
#endif
	
#pragma clang diagnostic pop
}

@end
