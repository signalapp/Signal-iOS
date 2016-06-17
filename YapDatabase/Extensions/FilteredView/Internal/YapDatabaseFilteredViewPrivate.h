#import "YapDatabaseFilteredView.h"
#import "YapDatabaseFilteredViewConnection.h"
#import "YapDatabaseFilteredViewTransaction.h"

#import "YapDatabaseViewPrivate.h"


/**
 * Keys for yap2 extension configuration table.
**/

// Defined in YapDatabaseViewPrivate.h
//
//static NSString *const ext_key_classVersion = @"classVersion";
//static NSString *const ext_key_versionTag   = @"versionTag";

static NSString *const ext_key_parentViewName = @"parentViewName";

/**
 * Changeset keys (for changeset notification dictionary)
**/
static NSString *const changeset_key_filtering = @"filtering";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewFiltering () {
@public
	
	YapDatabaseViewFilteringBlock block;
	YapDatabaseBlockType          blockType;
	YapDatabaseBlockInvoke        blockInvokeOptions;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseFilteredView () {
@private
	
	YapDatabaseViewFiltering *filtering;
	
@public
	
	NSString *parentViewName;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseFilteredViewConnection () {
@protected
	
	YapDatabaseViewFiltering *filtering;
	BOOL filteringChanged;
}

- (void)getFiltering:(YapDatabaseViewFiltering **)filteringPtr;

- (void)setFiltering:(YapDatabaseViewFiltering *)newFiltering
          versionTag:(NSString *)newVersionTag;

@end
