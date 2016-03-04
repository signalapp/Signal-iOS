#import <Foundation/Foundation.h>
#import "YapActionItem.h"

NS_ASSUME_NONNULL_BEGIN

@protocol YapActionable <NSObject>
@required

/**
 * Returns an array of YapActionItem instances for the object.
 * Or nil if there are none.
**/
- (nullable NSArray<YapActionItem*> *)yapActionItems;

@end

NS_ASSUME_NONNULL_END
