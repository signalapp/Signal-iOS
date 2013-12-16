#import <Foundation/Foundation.h>

#import "YapDatabaseExtensionTransaction.h"
#import "YapDatabaseQuery.h"


@interface YapDatabaseSecondaryIndexTransaction : YapDatabaseExtensionTransaction

/**
 * These methods allow you to enumerates matches from the secondary index(es) using a given query.
 *
 * The query that you input is an SQL style query (appropriate for SQLite semantics),
 * excluding the "SELECT ... FROM 'tableName'" component.
 * 
 * For example:
 * 
 * query = [YapDatabaseQuery queryWithFormat:@"WHERE age >= 62"];
 * [[transaction ext:@"idx"] enumerateKeysMatchingQuery:query usingBlock:^(NSString *key, BOOL *stop) {
 * 
 *     // ...
 * }];
 *
 * You can also pass parameters to the query using the standard SQLite placeholder:
 * 
 * query = [YapDatabaseQuery queryWithFormat:@"WHERE age >= ? AND state == ?", @(age), state];
 * [[transaction ext:@"idx"] enumerateKeysMatchingQuery:query usingBlock:^(NSString *key, BOOL *stop) {
 *
 *     // ...
 * }];
 *
 * For more information, and more examples, please see YapDatabaseQuery.
 * 
 * @return NO if there was a problem with the given query. YES otherwise.
 * 
 * @see YapDatabaseQuery
**/

- (BOOL)enumerateKeysMatchingQuery:(YapDatabaseQuery *)query
                        usingBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block;

- (BOOL)enumerateKeysAndMetadataMatchingQuery:(YapDatabaseQuery *)query
                                   usingBlock:
                            (void (^)(NSString *collection, NSString *key, id metadata, BOOL *stop))block;

- (BOOL)enumerateKeysAndObjectsMatchingQuery:(YapDatabaseQuery *)query
                                  usingBlock:
                            (void (^)(NSString *collection, NSString *key, id object, BOOL *stop))block;

- (BOOL)enumerateRowsMatchingQuery:(YapDatabaseQuery *)query
                        usingBlock:
                            (void (^)(NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block;
/**
 * Skips the enumeration process, and just gives you the count of matching rows.
**/

- (BOOL)getNumberOfRows:(NSUInteger *)count matchingQuery:(YapDatabaseQuery *)query;

@end
