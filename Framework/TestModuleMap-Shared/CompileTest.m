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
@import YapDatabase.YapDatabaseCloudKit;
@import YapDatabase.YapDatabaseRTreeIndex;
@import YapDatabase.YapDatabaseConnectionProxy;

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
	YapDatabaseCloudKit *cloudKit;
	YapDatabaseRTreeIndex *rTreeIndex;
	YapDatabaseConnectionProxy *connectionProxy;
	
#pragma clang diagnostic pop
}

@end
