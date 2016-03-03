#import "YapDatabaseSearchQueue.h"

/**
 * This header file is PRIVATE, and is only to be used by the YapDatabaseSearchResultsTransaction class.
**/

@interface YapDatabaseSearchQueue ()

- (NSString *)flushQueue;

- (BOOL)shouldAbortSearchInProgressAndRollback:(BOOL *)shouldRollbackPtr;

@end
