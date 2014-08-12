#import <Foundation/Foundation.h>
#import "YapDatabaseViewConnection.h"

@class YapDatabaseSearchResultsView;


@interface YapDatabaseSearchResultsViewConnection : YapDatabaseViewConnection

// Returns properly typed parent instance
@property (nonatomic, strong, readonly) YapDatabaseSearchResultsView *searchResultsView;

@end
