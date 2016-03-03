#import <Foundation/Foundation.h>

#import "YapDatabaseExtensionTransaction.h"
#import "YapDatabaseViewTypes.h"
#import "YapDatabaseViewMappings.h"

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

@interface YapDatabaseViewTransaction : YapDatabaseExtensionTransaction

#pragma mark Groups

/**
 * Returns the number of groups the view manages.
 * Each group has one or more keys in it.
**/
- (NSUInteger)numberOfGroups;

/**
 * Returns the names of all groups in an unsorted array.
 * Each group has one or more keys in it.
 *
 * @see YapDatabaseView - groupingBlock
**/
- (NSArray<NSString *> *)allGroups;

/**
 * Returns YES if there are any keys in the given group.
 * This is equivalent to ([viewTransaction numberOfItemsInGroup:group] > 0)
**/
- (BOOL)hasGroup:(NSString *)group;

#pragma mark Counts

/**
 * Returns the total number of keys in the given group.
 * If the group doesn't exist, returns zero.
**/
- (NSUInteger)numberOfItemsInGroup:(NSString *)group;

/**
 * Returns the total number of keys in every single group.
**/
- (NSUInteger)numberOfItemsInAllGroups;

/**
 * Returns YES if the group is empty (has zero items).
 * Shorthand for: [[transaction ext:viewName] numberOfItemsInGroup:group] == 0
**/
- (BOOL)isEmptyGroup:(NSString *)group;

/**
 * Returns YES if the view is empty (has zero groups).
 * Shorthand for: [[transaction ext:viewName] numberOfItemsInAllGroups] == 0
**/
- (BOOL)isEmpty;

#pragma mark Fetching

/**
 * Returns the key & collection at the given index within the given group.
 * Returns nil if the group doesn't exist, or if the index is out of bounds.
**/
- (BOOL)getKey:(NSString * _Nullable * _Nullable)keyPtr
    collection:(NSString * _Nullable * _Nullable)collectionPtr
       atIndex:(NSUInteger)index
       inGroup:(NSString *)group;

/**
 * Shortcut for: [view getKey:&key collection:&collection atIndex:0 inGroup:group]
**/
- (BOOL)getFirstKey:(NSString * _Nonnull * _Nullable)keyPtr collection:(NSString * _Nonnull * _Nullable)collectionPtr inGroup:(NSString *)group;

/**
 * Shortcut for: [view getKey:&key collection:&collection atIndex:(numberOfItemsInGroup-1) inGroup:group]
**/
- (BOOL)getLastKey:(NSString * _Nonnull * _Nullable)keyPtr collection:(NSString * _Nonnull * _Nullable)collectionPtr inGroup:(NSString *)group;

/**
 * Shortcut for fetching just the collection at the given index.
**/
- (NSString *)collectionAtIndex:(NSUInteger)index inGroup:(NSString *)group;

/**
 * Shortcut for fetching just the key at the given index.
 * Convenient if you already know what collection the key is in.
**/
- (NSString *)keyAtIndex:(NSUInteger)index inGroup:(NSString *)group;

/**
 * If the given {collection, key} are included in the view, then returns the associated group.
 * If the {collection, key} isn't in the view, then returns nil.
**/
- (NSString *)groupForKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * Fetches both the group and the index within the group for the given {collection, key}.
 *
 * Returns YES if the {collection, key} is included in the view.
 * Otherwise returns NO, and sets the parameters to nil & zero.
**/
- (BOOL)getGroup:(NSString * _Nonnull * _Nullable)groupPtr
           index:(nullable NSUInteger *)indexPtr
          forKey:(NSString *)key
    inCollection:(nullable NSString *)collection;

/**
 * Returns the versionTag in effect for this transaction.
 * 
 * Because this transaction may be one or more commits behind the most recent commit,
 * this method is the best way to determine the versionTag associated with what the transaction actually sees.
 * 
 * Put another way:
 * - [YapDatabaseView versionTag]            = versionTag of most recent commit
 * - [YapDatabaseViewTransaction versionTag] = versionTag of this commit
**/
- (NSString *)versionTag;

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

#pragma mark Enumerating

/**
 * Enumerates the groups in the view.
**/
- (void)enumerateGroupsUsingBlock:(void (^)(NSString *group, BOOL *stop))block;

/**
 * Enumerates the keys in the given group.
**/
- (void)enumerateKeysInGroup:(NSString *)group
                  usingBlock:(void (^)(NSString *collection, NSString *key, NSUInteger index, BOOL *stop))block;

/**
 * Enumerates the keys in the given group.
 * Reverse enumeration is supported by passing NSEnumerationReverse. (No other enumeration options are supported.)
**/
- (void)enumerateKeysInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                  usingBlock:(void (^)(NSString *collection, NSString *key, NSUInteger index, BOOL *stop))block;

/**
 * Enumerates the keys in the range of the given group.
 * Reverse enumeration is supported by passing NSEnumerationReverse. (No other enumeration options are supported.)
**/
- (void)enumerateKeysInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                       range:(NSRange)range
                  usingBlock:(void (^)(NSString *collection, NSString *key, NSUInteger index, BOOL *stop))block;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The methods in this ReadWrite category are only available from within a ReadWriteTransaction.
 * Invoking them from within a ReadOnlyTransaction does nothing (except log a warning).
**/
@interface YapDatabaseViewTransaction (ReadWrite)

/**
 * "Touching" an object allows you to mark an item in the view as "updated",
 * even if the object itself wasn't directly updated.
 *
 * This is most often useful when a view is being used by a tableView,
 * but the tableView cells are also dependent upon another object in the database.
 *
 * For example:
 *
 *   You have a view which includes the departments in the company, sorted by name.
 *   But as part of the cell that's displayed for the department,
 *   you also display the number of employees in the department.
 *   The employee count comes from elsewhere.
 *   That is, the employee count isn't a property of the department object itself.
 *   Perhaps you get the count from another view,
 *   or perhaps the count is simply the number of keys in a particular collection.
 *   Either way, when you add or remove an employee, you want to ensure that the view marks the
 *   affected department as updated so that the corresponding cell will properly redraw itself.
 *
 * So the idea is to mark certain items as "updated" (in terms of this view) so that
 * the changeset for the view will properly reflect a change to the corresponding index.
 * But you don't actually need to update the item on disk.
 * This is exactly what "touch" does.
 *
 * Touching an item has very minimal overhead.
 * It doesn't cause the groupingBlock or sortingBlock to be invoked,
 * and it doesn't cause any writes to the database.
 *
 * You can touch
 * - just the object
 * - just the metadata
 * - or both object and metadata (the row)
 * 
 * If you mark just the object as changed,
 * and neither the groupingBlock nor sortingBlock depend upon the object,
 * then the view doesn't reflect any change.
 * 
 * If you mark just the metadata as changed,
 * and neither the groupingBlock nor sortingBlock depend upon the metadata,
 * then the view doesn't relect any change.
 * 
 * In all other cases, the view will properly reflect a corresponding change in the notification that's posted.
**/

- (void)touchRowForKey:(NSString *)key inCollection:(nullable NSString *)collection;
- (void)touchObjectForKey:(NSString *)key inCollection:(nullable NSString *)collection;
- (void)touchMetadataForKey:(NSString *)key inCollection:(nullable NSString *)collection;

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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabaseView deals with ordered arrays (of rowid values).
 * So, conceptually speaking, it only knows about collection/key tuples, groups, and indexes.
 * 
 * But it's really convenient to have methods that put it all together to fetch an object in a single method.
**/
@interface YapDatabaseViewTransaction (Convenience)

/**
 * Equivalent to invoking:
 *
 * NSString *collection, *key;
 * if ([[transaction ext:@"myView"] getKey:&key collection:&collection atIndex:index inGroup:group]) {
 *     metadata = [transaction metadataForKey:key inCollection:collection];
 * }
**/
- (nullable id)metadataAtIndex:(NSUInteger)index inGroup:(NSString *)group;

/**
 * Equivalent to invoking:
 *
 * NSString *collection, *key;
 * if ([[transaction ext:@"myView"] getKey:&key collection:&collection atIndex:index inGroup:group]) {
 *     object = [transaction objectForKey:key inCollection:collection];
 * }
**/
- (nullable id)objectAtIndex:(NSUInteger)keyIndex inGroup:(NSString *)group;

/**
 * Equivalent to invoking:
 *
 * NSString *collection, *key;
 * if ([[transaction ext:@"myView"] getFirstKey:&key collection:&collection inGroup:group]) {
 *     object = [transaction objectForKey:key inCollection:collection];
 * }
**/
- (nullable id)firstObjectInGroup:(NSString *)group;

/**
 * Equivalent to invoking:
 *
 * NSString *collection, *key;
 * if ([[transaction ext:@"myView"] getLastKey:&key collection:&collection inGroup:group]) {
 *     object = [transaction objectForKey:key inCollection:collection];
 * }
**/
- (nullable id)lastObjectInGroup:(NSString *)group;

/**
 * The following methods are similar to invoking the enumerateKeysInGroup:... methods,
 * and then fetching the metadata within your own block.
**/

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                             usingBlock:
                    (void (^)(NSString *collection, NSString *key, id metadata, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                            withOptions:(NSEnumerationOptions)options
                             usingBlock:
                    (void (^)(NSString *collection, NSString *key, id metadata, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                            withOptions:(NSEnumerationOptions)options
                                  range:(NSRange)range
                             usingBlock:
                    (void (^)(NSString *collection, NSString *key, id metadata, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                            withOptions:(NSEnumerationOptions)options
                                  range:(NSRange)range
                                 filter:
                    (BOOL (^)(NSString *collection, NSString *key))filter
                             usingBlock:
                    (void (^)(NSString *collection, NSString *key, id metadata, NSUInteger index, BOOL *stop))block;

/**
 * The following methods are similar to invoking the enumerateKeysInGroup:... methods,
 * and then fetching the object within your own block.
**/

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                            usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                            usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                                 range:(NSRange)range
                            usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                                 range:(NSRange)range
                                filter:
            (BOOL (^)(NSString *collection, NSString *key))filter
                            usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop))block;

/**
 * The following methods are similar to invoking the enumerateKeysInGroup:... methods,
 * and then fetching the object and metadata within your own block.
**/

- (void)enumerateRowsInGroup:(NSString *)group
                  usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block;

- (void)enumerateRowsInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                  usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block;

- (void)enumerateRowsInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                       range:(NSRange)range
                  usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block;

- (void)enumerateRowsInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                       range:(NSRange)range
                      filter:
            (BOOL (^)(NSString *collection, NSString *key))filter
                  usingBlock:
            (void (^)(NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * ***** ALWAYS USE THESE METHODS WHEN USING MAPPINGS *****
 *
 * When using advanced features of YapDatabaseViewMappings, things can get confusing rather quickly.
 * For example, one can configure mappings in such a way that it:
 * - only displays a subset (range) of the original YapDatabaseView
 * - presents the YapDatabaseView in reverse order
 * 
 * If you used only the core API of YapDatabaseView, you'd be forced to constantly use a 2-step lookup process:
 * 1.) Use mappings to convert from the tableView's indexPath, to the group & index of the view.
 * 2.) Use the resulting group & index to fetch what you need.
 * 
 * The annoyance of an extra step is one thing.
 * But an extra step that's easy to forget, and which would likely cause bugs, is another.
 * 
 * Thus it is recommended that you ***** ALWAYS USE THESE METHODS WHEN USING MAPPINGS ***** !!!!!
 * 
 * One other word of encouragement:
 *
 * Often times developers start by using straight mappings without any advanced features.
 * This means there's a 1-to-1 mapping between what's in the tableView, and what's in the yapView.
 * In these situations you're still highly encouraged to use these methods.
 * Because if/when you do turn on some advanced features, these methods will continue to work perfectly.
 * Whereas the alternative would force you to find every instance where you weren't using these methods,
 * and convert that code to use these methods.
 * 
 * So it's advised you save yourself the hassle (and the mental overhead),
 * and simply always use these methds when using mappings.
**/
@interface YapDatabaseViewTransaction (Mappings)

/**
 * Gets the key & collection at the given indexPath, assuming the given mappings are being used.
 * Returns NO if the indexPath is invalid, or the mappings aren't initialized.
 * Otherwise returns YES, and sets the key & collection ptr (both optional).
**/
- (BOOL)getKey:(NSString * _Nonnull * _Nullable)keyPtr
    collection:(NSString * _Nonnull * _Nullable)collectionPtr
   atIndexPath:(NSIndexPath *)indexPath
  withMappings:(YapDatabaseViewMappings *)mappings;

/**
 * Gets the key & collection at the given row & section, assuming the given mappings are being used.
 * Returns NO if the row or section is invalid, or the mappings aren't initialized.
 * Otherwise returns YES, and sets the key & collection ptr (both optional).
**/
- (BOOL)getKey:(NSString * _Nonnull * _Nullable)keyPtr
    collection:(NSString * _Nonnull * _Nullable)collectionPtr
        forRow:(NSUInteger)row
     inSection:(NSUInteger)section
  withMappings:(YapDatabaseViewMappings *)mappings;

/**
 * Fetches the indexPath for the given {collection, key} tuple, assuming the given mappings are being used.
 * Returns nil if the {collection, key} tuple isn't included in the view + mappings.
**/
- (NSIndexPath *)indexPathForKey:(NSString *)key
                    inCollection:(nullable NSString *)collection
                    withMappings:(YapDatabaseViewMappings *)mappings;

/**
 * Fetches the row & section for the given {collection, key} tuple, assuming the given mappings are being used.
 * Returns NO if the {collection, key} tuple isn't included in the view + mappings.
 * Otherwise returns YES, and sets the row & section (both optional).
**/
- (BOOL)getRow:(nullable NSUInteger *)rowPtr
       section:(nullable NSUInteger *)sectionPtr
        forKey:(NSString *)key
  inCollection:(nullable NSString *)collection
  withMappings:(YapDatabaseViewMappings *)mappings;

/**
 * Gets the object at the given indexPath, assuming the given mappings are being used.
 * 
 * Equivalent to invoking:
 *
 * NSString *collection, *key;
 * if ([[transaction ext:@"myView"] getKey:&key collection:&collection atIndexPath:indexPath withMappings:mappings]) {
 *     object = [transaction objectForKey:key inCollection:collection];
 * }
**/
- (nullable id)objectAtIndexPath:(NSIndexPath *)indexPath withMappings:(YapDatabaseViewMappings *)mappings;

/**
 * Gets the object at the given indexPath, assuming the given mappings are being used.
 *
 * Equivalent to invoking:
 *
 * NSString *collection, *key;
 * if ([[transaction ext:@"myView"] getKey:&key
 *                              collection:&collection
 *                                  forRow:row
 *                               inSection:section
 *                            withMappings:mappings]) {
 *     object = [transaction objectForKey:key inCollection:collection];
 * }
**/
- (nullable id)objectAtRow:(NSUInteger)row inSection:(NSUInteger)section withMappings:(YapDatabaseViewMappings *)mappings;

/**
 * Gets the metadata at the given indexPath, assuming the given mappings are being used.
 *
 * Equivalent to invoking:
 *
 * NSString *collection, *key;
 * if ([[transaction ext:@"myView"] getKey:&key collection:&collection atIndexPath:indexPath withMappings:mappings]) {
 *     metadata = [transaction metadataForKey:key inCollection:collection];
 * }
**/
- (nullable id)metadataAtIndexPath:(NSIndexPath *)indexPath withMappings:(YapDatabaseViewMappings *)mappings;

/**
 * Gets the object at the given indexPath, assuming the given mappings are being used.
 *
 * Equivalent to invoking:
 *
 * NSString *collection, *key;
 * if ([[transaction ext:@"myView"] getKey:&key
 *                              collection:&collection
 *                                  forRow:row
 *                               inSection:section
 *                            withMappings:mappings]) {
 *     metadata = [transaction metadataForKey:key inCollection:collection];
 * }
**/
- (nullable id)metadataAtRow:(NSUInteger)row inSection:(NSUInteger)section withMappings:(YapDatabaseViewMappings *)mappings;

@end

NS_ASSUME_NONNULL_END
