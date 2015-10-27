#import <Foundation/Foundation.h>
#import "YapDatabaseViewConnection.h"

@class YapDatabaseSearchResultsView;

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseSearchResultsViewConnection : YapDatabaseViewConnection

// Returns properly typed parent instance
@property (nonatomic, strong, readonly) YapDatabaseSearchResultsView *searchResultsView;

@end

NS_ASSUME_NONNULL_END
