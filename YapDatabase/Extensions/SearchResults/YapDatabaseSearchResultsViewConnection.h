#import <Foundation/Foundation.h>
#import "YapDatabaseAutoViewConnection.h"

@class YapDatabaseSearchResultsView;

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseSearchResultsViewConnection : YapDatabaseAutoViewConnection

// Returns properly typed parent instance
@property (nonatomic, strong, readonly) YapDatabaseSearchResultsView *searchResultsView;

@end

NS_ASSUME_NONNULL_END
