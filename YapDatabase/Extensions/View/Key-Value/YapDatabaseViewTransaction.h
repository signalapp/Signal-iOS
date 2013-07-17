#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseExtensionTransaction.h"

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase
 *
 * If you're new to the project you may want to check out the wiki
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * YapDatabaseView is an extension designed to work with YapDatabase.
 * It gives you a persistent sorted "view" of a configurable subset of your data.
 *
 * For more information, please see the wiki article about Views:
 * https://github.com/yaptv/YapDatabase/wiki/Views
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
@interface YapDatabaseViewTransaction : YapAbstractDatabaseExtensionTransaction

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
- (NSArray *)allGroups;

/**
 * Returns the total number of keys in the given group.
 * If the group doesn't exist, returns zero.
**/
- (NSUInteger)numberOfKeysInGroup:(NSString *)group;

/**
 * Returns the total number of keys in every single group.
**/
- (NSUInteger)numberOfKeysInAllGroups;

/**
 * Returns the key at the given index within the given group.
 * Returns nil if the group doesn't exist, or if the index is out of bounds.
**/
- (NSString *)keyAtIndex:(NSUInteger)index inGroup:(NSString *)group;

/**
 * Shortcut for: [view keyAtIndex:0 inGroup:group]
**/
- (NSString *)firstKeyInGroup:(NSString *)group;

/**
 * Shortcut for: [view keyAtIndex:(numberOfKeysInGroup-1) inGroup:group]
**/
- (NSString *)lastKeyInGroup:(NSString *)group;

/**
 * If the given key is included in the view, then returns the associated group.
 * If the key isn't in the view, then returns nil.
**/
- (NSString *)groupForKey:(NSString *)key;

/**
 * Fetches both the group and the index within the group for the given key.
 *
 * Returns YES if the key is included in the view.
 * Otherwise returns NO, and sets the parameters to nil & zero.
**/
- (BOOL)getGroup:(NSString **)groupPtr index:(NSUInteger *)indexPtr forKey:(NSString *)key;

/**
 * Fetches a range of keys in a given group.
 * If the range is out-of-bounds, then the returned array may be truncated in size.
**/
- (NSArray *)keysInRange:(NSRange)range group:(NSString *)group;

/**
 * Enumerates the keys in the given group.
**/
- (void)enumerateKeysInGroup:(NSString *)group
                  usingBlock:(void (^)(NSString *key, NSUInteger index, BOOL *stop))block;

/**
 * Enumerates the keys in the given group.
 * Reverse enumeration is supported by passing NSEnumerationReverse. (No other enumeration options are supported.)
**/
- (void)enumerateKeysInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                  usingBlock:(void (^)(NSString *key, NSUInteger index, BOOL *stop))block;

/**
 * Enumerates the keys in the range of the given group.
 * Reverse enumeration is supported by passing NSEnumerationReverse. (No other enumeration options are supported.)
**/
- (void)enumerateKeysInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                       range:(NSRange)range
                  usingBlock:(void (^)(NSString *key, NSUInteger index, BOOL *stop))block;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewTransaction (ReadWrite)

/**
 * "Touching" a object allows you to mark an item in the view as "updated",
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
 * So the idea is to mark certain items as updated so that the changeset
 * for the view will properly reflect a change to the corresponding index.
 *
 * "Touching" an item has very minimal overhead.
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

- (void)touchRowForKey:(NSString *)key;
- (void)touchObjectForKey:(NSString *)key;
- (void)touchMetadataForKey:(NSString *)key;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabaseView deals with ordered arrays of keys.
 * So, strictly speaking, it only knows about keys, groups, and indexes.
 * 
 * But it's really convenient to have methods that put it all together to fetch an object in a single method.
**/
@interface YapDatabaseViewTransaction (Convenience)

/**
 * Equivalent to invoking:
 *
 * [transaction objectForKey:[[transaction ext:@"myView"] keyAtIndex:index inGroup:group]];
**/
- (id)objectAtIndex:(NSUInteger)index inGroup:(NSString *)group;

/**
 * Equivalent to invoking:
 * 
 * [transaction objectForKey:[[transaction ext:@"myView"] firstKeyInGroup:group]];
**/
- (id)firstObjectInGroup:(NSString *)group;

/**
 * Equivalent to invoking:
 * 
 * [transaction objectForKey:[[transaction ext:@"myView"] lastKeyInGroup:group]];
**/
- (id)lastObjectInGroup:(NSString *)group;

/**
 * The following methods are equivalent to invoking the enumerateKeysInGroup:... methods,
 * and then fetching the metadata within your own block.
**/

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                             usingBlock:(void (^)(NSString *key, id metadata, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                            withOptions:(NSEnumerationOptions)options
                             usingBlock:(void (^)(NSString *key, id metadata, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysAndMetadataInGroup:(NSString *)group
                            withOptions:(NSEnumerationOptions)options
                                  range:(NSRange)range
                             usingBlock:(void (^)(NSString *key, id metadata, NSUInteger index, BOOL *stop))block;

/**
 * The following methods are equivalent to invoking the enumerateKeysInGroup:... methods,
 * and then fetching the object within your own block.
**/

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                            usingBlock:
                                 (void (^)(NSString *key, id object, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                            usingBlock:
                                 (void (^)(NSString *key, id object, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                                 range:(NSRange)range
                            usingBlock:
                                 (void (^)(NSString *key, id object, NSUInteger index, BOOL *stop))block;

/**
 * The following methods are equivalent to invoking the enumerateKeysInGroup:... methods,
 * and then fetching the object and metadata within your own block.
**/

- (void)enumerateRowsInGroup:(NSString *)group
                  usingBlock:(void (^)(NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block;

- (void)enumerateRowsInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                  usingBlock:(void (^)(NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block;

- (void)enumerateRowsInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                       range:(NSRange)range
                  usingBlock:(void (^)(NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block;

@end
