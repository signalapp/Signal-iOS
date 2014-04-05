#import <Foundation/Foundation.h>

#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseSearchQueue.h"


@interface YapDatabaseSearchResultsViewTransaction : YapDatabaseViewTransaction

// This class extends YapDatabaseViewTransaction.
//
// Please see YapDatabaseViewTransaction.h

@end

@interface YapDatabaseSearchResultsViewTransaction (ReadWrite)

/**
 * Represents the most recent search query that is providing the search results.
**/
- (NSString *)query;

- (void)performSearchFor:(NSString *)query;

- (void)performSearchWithQueue:(YapDatabaseSearchQueue *)queue;

@end
