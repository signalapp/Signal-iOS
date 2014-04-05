#import "YapDatabaseSearchResultsView.h"
#import "YapDatabaseSearchResultsViewConnection.h"
#import "YapDatabaseSearchResultsViewTransaction.h"

#import "YapDatabaseViewPrivate.h"


@interface YapDatabaseSearchResultsView () {
@public
	
	NSString *parentViewName;
	NSString *fullTextSearchName;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseSearchResultsViewConnection () {
@public
	
	NSString *query;
}

@end
