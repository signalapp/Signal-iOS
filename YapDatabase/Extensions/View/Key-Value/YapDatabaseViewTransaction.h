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
 *
 * What is an extension?
 * https://github.com/yaptv/YapDatabase/wiki/Extensions
 * 
 * See the documentation in YapDatabaseView for information on initializing a view object.
 *
 * You access this class within a regular transaction.
 * For example:
 * 
 * [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
 *     
 *     topUsaSale = [[transaction ext:@"myView"] objectAtIndex:0 inGroup:@"usa"]
 * }];
 * 
 * Keep in mind that the YapDatabaseViewTransaction object is linked
 * to the YapDatabaseReadTransaction from which it was fetched.
 * So don't try to save it to an ivar or use it outside the transaction block.
**/
@interface YapDatabaseViewTransaction : YapAbstractDatabaseExtensionTransaction

- (NSUInteger)numberOfGroups;
- (NSArray *)allGroups;

- (NSUInteger)numberOfKeysInGroup:(NSString *)group;
- (NSUInteger)numberOfKeysInAllGroups;

- (NSString *)keyAtIndex:(NSUInteger)index inGroup:(NSString *)group;
- (NSString *)groupForKey:(NSString *)key;

- (BOOL)getGroup:(NSString **)groupPtr index:(NSUInteger *)indexPtr forKey:(NSString *)key;

- (NSArray *)keysInRange:(NSRange)range group:(NSString *)group;

- (void)enumerateKeysInGroup:(NSString *)group
                  usingBlock:(void (^)(NSString *key, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                  usingBlock:(void (^)(NSString *key, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysInGroup:(NSString *)group
                 withOptions:(NSEnumerationOptions)options
                       range:(NSRange)range
                  usingBlock:(void (^)(NSString *key, NSUInteger index, BOOL *stop))block;

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
 * and then fetching the object and metadata within your own block.
**/

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                            usingBlock:
                                 (void (^)(NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                            usingBlock:
                                 (void (^)(NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block;

- (void)enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                                 range:(NSRange)range
                            usingBlock:
                                 (void (^)(NSString *key, id object, id metadata, NSUInteger index, BOOL *stop))block;

@end
