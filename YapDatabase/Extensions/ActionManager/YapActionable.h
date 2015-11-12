#import <Foundation/Foundation.h>
#import "YapActionItem.h"


@protocol YapActionable <NSObject>
@required

/**
 * Returns an array of YapActionItem instances for the object.
 * Or nil if there are none.
**/
- (NSArray<YapActionItem*> *)yapActionItems;

@optional

/**
 * Returns whether or not there are any actionItems available.
 *
 * Shortcut for: [[obj yapActionItems] count] == 0
 * 
 * This optional method provides the opportunity to skip creating the temporary YapActionItem instances.
 * This method is used by the underlying YapDatabaseView's groupingBlock.
**/
- (BOOL)hasYapActionItems;

/**
 * Returns the earliest YapActionItem.date.
 * 
 * Shortcut for: [[[[obj actionItems] sortedArrayUsingSelector:@selector(compare:)] firstObject] date]
 * 
 * This optional method provides the opportunity to skip creating the temporary YapActionItem instances.
 * This method is used by the underlying YapDatabaseView's sortingBlock.
 * 
 * Note: If a YapActionItem doesn't have a future date (should execute immediately/ASAP),
 * it is automatically assigned a date of [NSDate dateWithTimeIntervalSinceReferenceDate:0.0].
**/
- (NSDate *)earliestYapActionItemDate;

@end
