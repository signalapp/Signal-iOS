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
@interface YapCollectionsDatabaseViewTransaction : YapAbstractDatabaseExtensionTransaction

/**
 * Returns the number of groups the view manages.
 * Each group has one or more keys in it.
**/
- (NSUInteger)numberOfGroups;

/**
 * Returns the names of all groups in an unsorted array.
 * Each group has one or more keys in it.
 *
 * @see YapCollectionsDatabaseView - groupingBlock
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
 * Returns the key & collection at the given index within the given group.
 * Returns nil if the group doesn't exist, or if the index is out of bounds.
**/
- (BOOL)getKey:(NSString **)keyPtr
    collection:(NSString **)collectionPtr
       atIndex:(NSUInteger)index
       inGroup:(NSString *)group;

/**
 * Shortcut for: [view getKey:&key collection:&collection atIndex:0 inGroup:group]
**/
- (BOOL)getFirstKey:(NSString **)keyPtr collection:(NSString **)collectionPtr inGroup:(NSString *)group;

/**
 * Shortcut for: [view getKey:&key collection:&collection atIndex:(numberOfKeysInGroup-1) inGroup:group]
**/
- (BOOL)getLastKey:(NSString **)keyPtr collection:(NSString **)collectionPtr inGroup:(NSString *)group;

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
- (NSString *)groupForKey:(NSString *)key inCollection:(NSString *)collection;

/**
 * Fetches both the group and the index within the group for the given {collection, key}.
 *
 * Returns YES if the {collection, key} is included in the view.
 * Otherwise returns NO, and sets the parameters to nil & zero.
**/
- (BOOL)getGroup:(NSString **)groupPtr
           index:(NSUInteger *)indexPtr
          forKey:(NSString *)key
    inCollection:(NSString *)collection;


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
 * YapCollectionsDatabaseView deals with ordered arrays of collection/key tuples.
 * So, strictly speaking, it only knows about collection/key tuples, groups, and indexes.
 * 
 * But it's really convenient to have methods that put it all together to fetch an object in a single method.
**/
@interface YapCollectionsDatabaseViewTransaction (Convenience)

/**
 * Equivalent to invoking:
 *
 * NSString *collection = nil;
 * NSString *key = nil;
 * [[transaction ext:@"myView"] getKey:&key collection:&collection atIndex:index inGroup:group];
 * [transaction objectForKey:key inCollection:collection];
**/
- (id)objectAtIndex:(NSUInteger)keyIndex inGroup:(NSString *)group;

/**
 * Equivalent to invoking:
 *
 * NSString *collection = nil;
 * NSString *key = nil;
 * [[transaction ext:@"myView"] getFirstKey:&key collection:&collection inGroup:group];
 * [transaction objectForKey:key inCollection:collection];
**/
- (id)firstObjectInGroup:(NSString *)group;

/**
 * Equivalent to invoking:
 *
 * NSString *collection = nil;
 * NSString *key = nil;
 * [[transaction ext:@"myView"] getLastKey:&key collection:&collection inGroup:group];
 * [transaction objectForKey:key inCollection:collection];
**/
- (id)lastObjectInGroup:(NSString *)group;

/**
 * The following methods are equivalent to invoking the enumerateKeysInGroup:... methods,
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

/**
 * The following methods are equivalent to invoking the enumerateKeysInGroup:... methods,
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

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The following methods have to do with the configuration of the internal workings of the view.
**/
@interface YapCollectionsDatabaseViewTransaction (Configuration)

/**
 * The view is tasked with storing ordered arrays of keys.
 * In doing so, it splits the array into "pages" of keys,
 * and stores the pages in the database.
 * This reduces disk IO, as only the contents of a single page are written for a single change.
 * And only the contents of a single page need be read to fetch a single key.
 *
 * The default pageSize if 50.
 * That is, the view will split up arrays into groups of up to 50 keys,
 * and store each as a separate page.
**/
- (NSUInteger)pageSize;

/**
 * Allows you to configure the pageSize.
 *
 * Note: Changing the pageSize for an active view may cause some IO as
 *       the view may need to restructure its existing pages.
 *
 * This method only works from within a readwrite transaction.
 * Invoking this method from within a readonly transaction does nothing.
**/
- (void)setPageSize:(NSUInteger)pageSize;

@end