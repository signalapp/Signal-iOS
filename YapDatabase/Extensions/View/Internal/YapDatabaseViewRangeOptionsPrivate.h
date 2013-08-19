#import "YapDatabaseViewRangeOptions.h"

/**
 * This header file is PRIVATE, and is only to be used by the YapDatabaseView classes.
**/

@interface YapDatabaseViewRangeOptions ()

/**
 * This method returns a copy with the pin value switched.
 *
 * That is, if the range was pinned to the beginning, the returned copy will be pinned to the end.
 * And vice versa.
**/
- (id)copyAndReverse;

@end
