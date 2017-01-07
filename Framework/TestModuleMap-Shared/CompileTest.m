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
@import YapDatabase.YapDatabaseActionManager;
#if !TARGET_OS_WATCH
@import YapDatabase.YapDatabaseCloudKit;
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
	YapDatabaseActionManager *actionManager;
#if !TARGET_OS_WATCH
	YapDatabaseCloudKit *cloudKit;
#endif
	
#pragma clang diagnostic pop
}

@end
