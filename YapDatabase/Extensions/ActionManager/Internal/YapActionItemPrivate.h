#import "YapActionItem.h"


/**
 * Private access for use by YapDatabaseActionManager ONLY.
**/
@interface YapActionItem ()

@property (nonatomic, assign, readwrite) BOOL isStarted;
@property (nonatomic, assign, readwrite) BOOL isPendingInternet;
@property (nonatomic, strong, readwrite, nullable) NSDate *nextRetry;

/**
 * Compares self.nextRetry with the atDate parameter.
 *
 * @param atDate
 *   The date to compare with.
 *   If nil, the current date is automatically used.
 *
 * @return
 *   Returns NO if self.nextRetry is after atDate (comparitively in the future).
 *   Returns YES otherwise (comparitively in the past or present).
**/
- (BOOL)isReadyToRetryAtDate:(nullable NSDate *)atDate;

@end
