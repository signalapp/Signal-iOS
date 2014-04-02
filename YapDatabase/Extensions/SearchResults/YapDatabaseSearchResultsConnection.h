#import <Foundation/Foundation.h>
#import "YapDatabaseViewConnection.h"

@class YapDatabaseSearchResults;


@interface YapDatabaseSearchResultsConnection : YapDatabaseViewConnection

// Returns properly typed parent instance
@property (nonatomic, strong, readonly) YapDatabaseSearchResults *searchResults;

@end
