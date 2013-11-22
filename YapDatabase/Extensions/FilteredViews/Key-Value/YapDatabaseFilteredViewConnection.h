#import <Foundation/Foundation.h>
#import "YapDatabaseViewConnection.h"

@class YapDatabaseFilteredView;


@interface YapDatabaseFilteredViewConnection : YapDatabaseViewConnection

// Returns properly typed parent view instance
@property (nonatomic, strong, readonly) YapDatabaseFilteredView *filteredView;

@end
