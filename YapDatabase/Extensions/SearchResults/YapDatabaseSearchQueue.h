#import <Foundation/Foundation.h>

/**
 *
**/
@interface YapDatabaseSearchQueue : NSObject

- (id)init;

- (void)enqueueQuery:(NSString *)query;

- (void)abortSearchInProgressAndRollback:(BOOL)shouldRollback;

- (NSArray *)enqueuedQueries;
- (NSUInteger)enqueuedQueryCount;

@end
