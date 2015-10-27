#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The YapDatabaseSearchQueue class assists in UI based searches,
 * where the database is tasked in keeping up with the user's typing.
 * 
 * Here's how it works:
 * - The user enters a new character in the search field.
 * - You enqueue the proper query, and asynchronously start the search using performSearchWithQueue.
 * - Rather than performing every single search (for every single enqueued query),
 *   the database can flush the queue, and perform the most recent query.
 *
 * When the search overhead is low, the database will keep up with the user's typing.
 * But when the search overhead is higher, this allows for optimizations that help better meet UI expectations.
 * 
 * This class is thread-safe.
**/
@interface YapDatabaseSearchQueue : NSObject

- (id)init;

/**
 * Use this method to enqueue the proper query.
 * This is generally done when the search field changes (due to user interaction).
**/
- (void)enqueueQuery:(NSString *)query;

/**
 * These methods allow you to inspect the queue.
 * This is generally done to see how backed up the queue is.
 * 
 * If the enqueuedQueryCount is positive, then there are queries pending.
 * Otherwise the searchResultsView is processing, or has processed, the most recent query.
**/
- (NSArray<NSString *> *)enqueuedQueries;
- (NSUInteger)enqueuedQueryCount;

/**
 * This method allows you to abort an in-progress search.
 *
 * The searchResultsView, while performing a search, periodically checks to see if this method has been invoked.
 * And if so, it will abort its search as soon as possible.
 * 
 * If you set the shouldRollback parameter to YES, then when the searchResultsView aborts its search,
 * it will also rollback its readWriteTransaction. Then end result is as that all progress for the search is discarded,
 * and nothing is committed.
 * 
 * If you choose to abort a search and set the shouldRollback parameter to NO,
 * then when the searchResultsView aborts its search it will simply commit whatever progress it made so far.
 * The end result is partial search results being reflected in the view.
 * 
 * The most common scenario is to abort the search and rollback the commit.
 * However, there are scenarios where partial search results are desireable.
 * For example, if a user cancels a time consuming search operation, the partial results may be very helpful.
 * 
 * In terms of operation, this method works in concert with the queue.
 * That is, when you invoke this method, then all queries in the queue prior to invoking this method
 * are marked for abortion. Meaning that you can invoke this method,
 * and then enqueue a new query in order to abort any prior searches, and start processing the newest query ASAP.
 *
 * This technique is commonly used when the user clears the search field.
 * Thus you would invoke this method, and then enqueue a query for an empty string (no search results).
**/
- (void)abortSearchInProgressAndRollback:(BOOL)shouldRollback;

@end

NS_ASSUME_NONNULL_END
