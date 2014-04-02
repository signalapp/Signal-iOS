#import <Foundation/Foundation.h>
#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseSearchQueue.h"


@interface YapDatabaseSearchResultsTransaction : YapDatabaseViewTransaction

// This class extends YapDatabaseViewTransaction.
//
// Please see YapDatabaseViewTransaction.h

@end

@interface YapDatabaseSearchResultsTransaction (ReadWrite)

/**
 * Represents the most recent search query that is providing the search results.
**/
- (NSString *)query;

- (void)performSearchFor:(NSString *)query;

- (void)performSearchWithQueue:(YapDatabaseSearchQueue *)queue;

@end
