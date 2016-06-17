#import <Foundation/Foundation.h>
#import "YapDatabaseViewConnection.h"

@class YapDatabaseFilteredView;

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseFilteredViewConnection : YapDatabaseViewConnection

// Returns properly typed parent view instance
@property (nonatomic, strong, readonly) YapDatabaseFilteredView *filteredView;

@end

NS_ASSUME_NONNULL_END
