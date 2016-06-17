#import <Foundation/Foundation.h>

#import "YapDatabaseAutoViewTransaction.h"
#import "YapDatabaseSearchQueue.h"

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseSearchResultsViewTransaction : YapDatabaseAutoViewTransaction

/**
 * Returns the snippet for the given collection/key tuple.
 *
 * Note: snippets must be enabled via YapDatabaseSearchResultsViewOptions.
**/
- (NSString *)snippetForKey:(NSString *)key inCollection:(nullable NSString *)collection;

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
 * @see performSearchWithQueue:
**/
- (void)performSearchFor:(NSString *)query;

/**
 * This method works similar to performSearchFor:,
 * but allows you to use a special search "queue" that gives you more control over how the search progresses.
 * 
 * With a search queue, the transaction will skip intermediate queries,
 * and always perform the most recent query in the queue.
 *
 * A search queue can also be used to abort an in-progress search.
**/
- (void)performSearchWithQueue:(YapDatabaseSearchQueue *)queue;

@end

NS_ASSUME_NONNULL_END
