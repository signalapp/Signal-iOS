#import <Foundation/Foundation.h>
#import "YapCollectionsDatabaseViewConnection.h"

@class YapCollectionsDatabaseFilteredView;


@interface YapCollectionsDatabaseFilteredViewConnection : YapCollectionsDatabaseViewConnection

// Returns properly typed parent view instance
@property (nonatomic, strong, readonly) YapCollectionsDatabaseFilteredView *filteredView;

@end
