#import <Foundation/Foundation.h>

#import "YapDatabaseExtensionTransaction.h"
#import "YapDatabaseQuery.h"

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseRTreeIndexTransaction : YapDatabaseExtensionTransaction

/**
 * These methods allow you to enumerates matches from the rtree index using a given query.
 *
 * The query that you input is an SQL style query (appropriate for SQLite semantics),
 * excluding the "SELECT ... FROM 'tableName'" component.
 *
 * For example:
 *
 * query = [YapDatabaseQuery queryWithFormat:@"WHERE minLon > 0 and maxLat <= 10"];
 * [[transaction ext:@"idx"] enumerateKeysMatchingQuery:query usingBlock:^(NSString *key, BOOL *stop) {
 *
 *     // ...
 * }];
 *
 * You can also pass parameters to the query using the standard SQLite placeholder:
 *
 * query = [YapDatabaseQuery queryWithFormat:@"WHERE minLon > ? AND maxLat <= ?", @(minLon), @(maxLat)];
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
                            (void (^)(NSString *collection, NSString *key, _Nullable id metadata, BOOL *stop))block;

- (BOOL)enumerateKeysAndObjectsMatchingQuery:(YapDatabaseQuery *)query
                                  usingBlock:
                            (void (^)(NSString *collection, NSString *key, id object, BOOL *stop))block;

- (BOOL)enumerateRowsMatchingQuery:(YapDatabaseQuery *)query
                        usingBlock:
                            (void (^)(NSString *collection, NSString *key, id object, _Nullable id metadata, BOOL *stop))block;
/**
 * Skips the enumeration process, and just gives you the count of matching rows.
**/
- (BOOL)getNumberOfRows:(NSUInteger *)count matchingQuery:(YapDatabaseQuery *)query;

/**
 * This method assists in performing a query over a subset of rows,
 * where the subset is a known set of keys.
 *
 * For example:
 *
 * Say you have a known set of items, and you want to figure out which of these items fit in the rectangle.
 *
 * NSArray *keys = [self itemKeys];
 * NSArray *rowids = [[[transaction ext:@"idx"] rowidsForKeys:keys inCollection:@"tracks"] allValues];
 *
 * YapDatabaseQuery *query =
 *   [YapDatabaseQuery queryWithFormat:@"WHERE minLon > 0 AND maxLat <= 10 AND rowid IN (?)", rowids];
 **/
- (NSDictionary<NSString*, NSNumber*> *)rowidsForKeys:(NSArray<NSString *> *)keys
										 inCollection:(nullable NSString *)collection;

@end

NS_ASSUME_NONNULL_END
