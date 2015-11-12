#import "YapActionItem.h"


@interface YapActionItem ()

/**
 * For use by YapDatabaseActionManager ONLY.
**/
@property (nonatomic, assign, readwrite) BOOL isStarted;
@property (nonatomic, assign, readwrite) BOOL isPendingInternet;
@property (nonatomic, strong, readwrite) NSDate *nextRetry;

@end
