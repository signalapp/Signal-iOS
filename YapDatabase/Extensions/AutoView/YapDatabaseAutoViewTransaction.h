#import <Foundation/Foundation.h>

#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseViewTypes.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase
 *
 * If you're new to the project you may want to check out the wiki
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * YapDatabaseView is an extension designed to work with YapDatabase.
 * It gives you a persistent sorted "view" of a configurable subset of your data.
 *
 * For more information, please see the wiki article about Views:
 * https://github.com/yapstudios/YapDatabase/wiki/Views
 *
 * You may also wish to consult the documentation in YapDatabaseView.h for information on setting up a view.
 *
 * You access this class within a regular transaction.
 * For example:
 *
 * [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
 *
 *     topUsaSale = [[transaction ext:@"myView"] objectAtIndex:0 inGroup:@"usa"]
 * }];
 *
 * Keep in mind that the YapDatabaseViewTransaction object is linked to the YapDatabaseReadTransaction object.
 * So don't try to use it outside the transaction block (cause it won't work).
**/
@interface YapDatabaseAutoViewTransaction : YapDatabaseViewTransaction

#pragma mark Finding

/**
 * This method uses a binary search algorithm to find a range of items within the view that match the given criteria.
 * For example:
 * 
 * You have a view which sorts items by timestamp (oldest to newest)
 * You could then use this method to quickly find all items whose timestamp falls on a certain day.
 * Or, more generally, within a certain timespan.
 * 
 * NSDate *beginningOfMonday = ...   // Monday at 12:00 AM
 * NSDate *beginningOfTuesday =  ... // Tuesday at 12:00 AM
 *
 * YapDatabaseViewFindWithObjectBlock block = ^(NSString *collection, NSString *key, id object){
 *
 *     Purchase *purchase = (Purchase *)object;
 *
 *     if ([purchase.timestamp compare:beginningOfMonday] == NSOrderedAscending) // earlier than start range
 *         return NSOrderedAscending;
 * 
 *     if ([purchase.timestamp compare:beginningOfTuesday] == NSOrderedAscending) // earlier than end range
 *         return NSOrderedSame;
 * 
 *     return NSOrderedDescending; // greater than end range (or exactly midnight on tuesday)
 * };
 * 
 * The return values from the YapDatabaseViewFindBlock have the following meaning:
 * 
 * - NSOrderedAscending : The given row (block parameters) is less than the range I'm looking for.
 *                        That is, the row would have a smaller index within the view than would the range I seek.
 * 
 * - NSOrderedDecending : The given row (block parameters) is greater than the range I'm looking for.
 *                        That is, the row would have a greater index within the view than would the range I seek.
 * 
 * - NSOrderedSame : The given row (block parameters) is within the range I'm looking for.
 * 
 * Keep in mind 2 things:
 * 
 * #1 : This method can only be used if you need to find items according to their sort order.
 *      That is, according to how the items are sorted via the view's sortingBlock.
 *      Attempting to use this method in any other manner makes no sense.
 *
 * #2 : The findBlock that you pass needs to be setup in the same manner as the view's sortingBlock.
 *      That is, the following rules must be followed, or the results will be incorrect:
 *      
 *      For example, say you have a view like this, looking for the following range of 3 items:
 *      myView = @[ A, B, C, D, E, F, G ]
 *                     ^^^^^^^
 *      sortingBlock(A, B) => NSOrderedAscending
 *      findBlock(A)       => NSOrderedAscending
 *      
 *      sortingBlock(E, D) => NSOrderedDescending
 *      findBlock(E)       => NSOrderedDescending
 * 
 *      findBlock(B) => NSOrderedSame
 *      findBlock(C) => NSOrderedSame
 *      findBlock(D) => NSOrderedSame
 * 
 * In other words, you can't sort one way in the sortingBlock, and "sort" another way in the findBlock.
 * Another way to think about it is in terms of how the Apple docs define the NSOrdered enums:
 * 
 * NSOrderedAscending  : The left operand is smaller than the right operand.
 * NSOrderedDescending : The left operand is greater than the right operand.
 * 
 * For the findBlock, the "left operand" is the row that is passed,
 * and the "right operand" is the desired range.
 * 
 * And NSOrderedSame means: "the passed row is within the range I'm looking for".
 * 
 * Implementation Note:
 * This method uses a binary search to find an item for which the block returns NSOrderedSame.
 * It then uses information from the first binary search (known min/max) to perform two subsequent binary searches.
 * One to find the start of the range, and another to find the end of the range.
 * Thus:
 * - the implementation is efficient
 * - the block won't be invoked for every item within the range
 *
 * @param group
 *     The group within the view to search.
 * 
 * @param find
 *     Instance of YapDatabaseViewFind. (See YapDatabaseViewTypes.h)
 * 
 * @return
 *     If found, the range that matches the items within the desired range.
 *     That is, is these items were passed to the given block, the block would return NSOrderedSame.
 *     If not found, returns NSMakeRange(NSNotFound, 0).
**/
- (NSRange)findRangeInGroup:(NSString *)group using:(YapDatabaseViewFind *)find;

/**
 * This method uses a binary search algorithm to find an item within the view that matches the given criteria.
 * 
 * It works similarly to findRangeInGroup:using:, but immediately returns once a single match has been found.
 * This makes it more efficient when you only care about the existence of a match,
 * or you know there will never be more than a single match.
 *
 * See the documentation for findRangeInGroup:using: for more information.
 * @see findRangeInGroup:using:
 *
 * @return
 *   If found, the index of the first match discovered.
 *   That is, an item where the find block returned NSOrderedSame.
 *   If not found, returns NSNotFound.
**/
- (NSUInteger)findFirstMatchInGroup:(NSString *)group using:(YapDatabaseViewFind *)find;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The methods in this ReadWrite category are only available from within a ReadWriteTransaction.
 * Invoking them from within a ReadOnlyTransaction does nothing (except log a warning).
**/
@interface YapDatabaseAutoViewTransaction (ReadWrite)

/**
 * This method allows you to change the grouping and/or sorting on-the-fly.
 * 
 * Note: You must pass a different versionTag, or this method does nothing.
 * If needed, you can fetch the current versionTag via the [viewTransaction versionTag] method.
**/
- (void)setGrouping:(YapDatabaseViewGrouping *)grouping
            sorting:(YapDatabaseViewSorting *)sorting
         versionTag:(nullable NSString *)versionTag;

@end

NS_ASSUME_NONNULL_END
