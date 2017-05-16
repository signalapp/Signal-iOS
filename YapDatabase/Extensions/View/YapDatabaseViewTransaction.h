#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionTransaction.h"

#import "YapDatabaseViewMappings.h"

NS_ASSUME_NONNULL_BEGIN

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
- (BOOL)getFirstKey:(NSString * _Nullable * _Nullable)keyPtr
         collection:(NSString * _Nullable * _Nullable)collectionPtr
            inGroup:(NSString *)group;

/**
 * Shortcut for: [view getKey:&key collection:&collection atIndex:(numberOfItemsInGroup-1) inGroup:group]
**/
- (BOOL)getLastKey:(NSString * _Nullable * _Nullable)keyPtr
        collection:(NSString * _Nullable * _Nullable)collectionPtr
           inGroup:(NSString *)group;

/**
 * Shortcut for fetching just the collection at the given index.
**/
- (nullable NSString *)collectionAtIndex:(NSUInteger)index inGroup:(NSString *)group;

/**
 * Shortcut for fetching just the key at the given index.
 * Convenient if you already know what collection the key is in.
**/
- (nullable NSString *)keyAtIndex:(NSUInteger)index inGroup:(NSString *)group;

/**
 * If the given {collection, key} are included in the view, then returns the associated group.
 * If the {collection, key} isn't in the view, then returns nil.
**/
- (nullable NSString *)groupForKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * Fetches both the group and the index within the group for the given {collection, key}.
 *
 * Returns YES if the {collection, key} is included in the view.
 * Otherwise returns NO, and sets the parameters to nil & zero.
**/
- (BOOL)getGroup:(NSString * _Nullable * _Nullable)groupPtr
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
- (nullable NSString *)versionTag;

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
- (BOOL)getKey:(NSString * _Nullable * _Nullable)keyPtr
    collection:(NSString * _Nullable * _Nullable)collectionPtr
   atIndexPath:(NSIndexPath *)indexPath
  withMappings:(YapDatabaseViewMappings *)mappings;

/**
 * Gets the key & collection at the given row & section, assuming the given mappings are being used.
 * Returns NO if the row or section is invalid, or the mappings aren't initialized.
 * Otherwise returns YES, and sets the key & collection ptr (both optional).
**/
- (BOOL)getKey:(NSString * _Nullable * _Nullable)keyPtr
    collection:(NSString * _Nullable * _Nullable)collectionPtr
        forRow:(NSUInteger)row
     inSection:(NSUInteger)section
  withMappings:(YapDatabaseViewMappings *)mappings;

/**
 * Fetches the indexPath for the given {collection, key} tuple, assuming the given mappings are being used.
 * Returns nil if the {collection, key} tuple isn't included in the view + mappings.
**/
- (nullable NSIndexPath *)indexPathForKey:(NSString *)key
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
- (nullable id)objectAtIndexPath:(NSIndexPath *)indexPath
                    withMappings:(YapDatabaseViewMappings *)mappings;

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
- (nullable id)objectAtRow:(NSUInteger)row
                 inSection:(NSUInteger)section
              withMappings:(YapDatabaseViewMappings *)mappings;

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
- (nullable id)metadataAtIndexPath:(NSIndexPath *)indexPath
                      withMappings:(YapDatabaseViewMappings *)mappings;

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
- (nullable id)metadataAtRow:(NSUInteger)row
                   inSection:(NSUInteger)section
                withMappings:(YapDatabaseViewMappings *)mappings;

@end

NS_ASSUME_NONNULL_END
