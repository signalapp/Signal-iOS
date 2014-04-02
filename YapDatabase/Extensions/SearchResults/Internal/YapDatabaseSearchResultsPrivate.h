#import "YapDatabaseSearchResults.h"
#import "YapDatabaseSearchResultsConnection.h"
#import "YapDatabaseSearchResultsTransaction.h"

#import "YapDatabaseViewPrivate.h"


@interface YapDatabaseSearchResults () {
@public
	
	NSString *parentViewName;
	NSString *fullTextSearchName;
}

@end
