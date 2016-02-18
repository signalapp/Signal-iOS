#import <Foundation/Foundation.h>
#import "YapActionItem.h"


@protocol YapActionable <NSObject>
@required

/**
 * Returns an array of YapActionItem instances for the object.
 * Or nil if there are none.
**/
- (NSArray<YapActionItem*> *)yapActionItems;

@end
