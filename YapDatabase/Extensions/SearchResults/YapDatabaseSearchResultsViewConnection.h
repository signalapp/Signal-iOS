#import <Foundation/Foundation.h>
#import "YapDatabaseViewConnection.h"

@class YapDatabaseSearchResultsView;


@interface YapDatabaseSearchResultsViewConnection : YapDatabaseViewConnection

// Returns properly typed parent instance
@property (nonatomic, strong, readonly) YapDatabaseSearchResultsView *searchResultsView;

// Returns the query that corresponds to the connection's commit / snapshot.
@property (atomic, copy, readonly) NSString *query;

@end
