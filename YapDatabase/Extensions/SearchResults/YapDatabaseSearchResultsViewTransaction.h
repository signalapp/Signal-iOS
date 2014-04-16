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

/**
 * Updates the view to include search results for the given query.
 *
 * This method will run the given query on the parent FTS extension,
 * and then properly pipe the results into the view.
 * 
 * @see performSearchWithQueue
**/
- (void)performSearchFor:(NSString *)query;

/**
 * This method works similar to performSearchFor:,
 * but allows you to use a special search "queue" that gives you more control over how the search progresses.
 * 
 * With a search queue, the transaction will skip intermediate queries,
 * and always perform the most recent query in the queue.
 * 
 * Need a decent example here...
**/
- (void)performSearchWithQueue:(YapDatabaseSearchQueue *)queue;

@end
