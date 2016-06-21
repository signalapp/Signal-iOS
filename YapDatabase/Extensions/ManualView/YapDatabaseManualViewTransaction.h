#import <Foundation/Foundation.h>

#import "YapDatabaseViewTransaction.h"

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
@interface YapDatabaseManualViewTransaction : YapDatabaseViewTransaction

/**
 * Adds the <collection, key> tuple to the end of the group (greatest index possible).
 * 
 * The operation will fail if the <collection, key> already exists in the view,
 * regardless of whether it's in the given group, or another group.
 * 
 * @return
 *   YES if the operation was successful. NO otherwise.
**/
- (BOOL)addKey:(NSString *)key inCollection:(nullable NSString *)collection toGroup:(NSString *)group;

/**
 * Inserts the <collection, key> tuple in the group, placing it at the given index.
 * 
 * The operation will fail if the <collection, key> already exists in the view,
 * regardless of whether it's in the given group, or another group.
 * 
 * @return
 *   YES if the operation was successful. NO otherwise.
**/
- (BOOL)insertKey:(NSString *)key
     inCollection:(nullable NSString *)collection
          atIndex:(NSUInteger)index
          inGroup:(NSString *)group;

/**
 * Removes the item currently located at the index in the given group.
 *
 * @return
 *   YES if the operation was successful (the group + index was valid). NO otherwise.
**/
- (BOOL)removeItemAtIndex:(NSUInteger)index inGroup:(NSString *)group;

/**
 * Removes the <collection, key> tuple from its index within the given group.
 * 
 * The operation will fail if the <collection, key> isn't currently a member of the group.
 *
 * @return
 *   YES if the operation was successful. NO otherwise.
**/
- (BOOL)removeKey:(NSString *)key inCollection:(nullable NSString *)collection fromGroup:(NSString *)group;

/**
 * Removes all <collection, key> tuples from the given group.
**/
- (void)removeAllItemsInGroup:(NSString *)group;

@end

NS_ASSUME_NONNULL_END
