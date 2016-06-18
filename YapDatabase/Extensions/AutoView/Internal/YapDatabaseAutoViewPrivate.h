#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseAutoView.h"
#import "YapDatabaseAutoViewConnection.h"
#import "YapDatabaseAutoViewTransaction.h"

#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabaseViewPrivate.h"

#import "YapMemoryTable.h"

#import "sqlite3.h"

@class YapCache;
@class YapCollectionKey;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewGrouping () {
@public
	
	YapDatabaseViewGroupingBlock block;
	YapDatabaseBlockType         blockType;
	YapDatabaseBlockInvoke       blockInvokeOptions;
}

@end

@interface YapDatabaseViewSorting () {
@public
	
	YapDatabaseViewSortingBlock block;
	YapDatabaseBlockType        blockType;
	YapDatabaseBlockInvoke      blockInvokeOptions;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseAutoView () {
@protected
	
	YapDatabaseViewGrouping *grouping;
	YapDatabaseViewSorting  *sorting;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseAutoViewConnection () {
@protected
	
	YapDatabaseViewGrouping *grouping;
	YapDatabaseViewSorting  *sorting;
	
	BOOL groupingChanged;
	BOOL sortingChanged;
	
@public
	
	BOOL lastInsertWasAtFirstIndex;
	BOOL lastInsertWasAtLastIndex;
}

- (void)getGrouping:(YapDatabaseViewGrouping **)groupingPtr
            sorting:(YapDatabaseViewSorting **)sortingPtr;

- (void)setGrouping:(YapDatabaseViewGrouping *)newGrouping
            sorting:(YapDatabaseViewSorting *)newSorting
         versionTag:(NSString *)newVersionTag;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewTransaction ()

// The following are declared for YDBAutoView subclasses (such as YapDatabaseSearchResultsView)

- (void)insertRowid:(int64_t)rowid
      collectionKey:(YapCollectionKey *)collectionKey
             object:(id)object
           metadata:(id)metadata
            inGroup:(NSString *)group
        withChanges:(YapDatabaseViewChangesBitMask)flags
              isNew:(BOOL)isGuaranteedNew;

@end
