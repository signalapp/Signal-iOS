#import <Foundation/Foundation.h>

#import "YapDatabaseExtensionTransaction.h"
#import "YapDatabaseQuery.h"

NS_ASSUME_NONNULL_BEGIN

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

- (BOOL)enumerateIndexedValuesInColumn:(NSString *)column matchingQuery:(YapDatabaseQuery *)query usingBlock:(void(^)(id indexedValue, BOOL *stop))block;

/**
 * Skips the enumeration process, and just gives you the count of matching rows.
**/
- (BOOL)getNumberOfRows:(NSUInteger *)count matchingQuery:(YapDatabaseQuery *)query;

/**
 * Aggregate Queries.
 * 
 * E.g.: avg, max, min, sum
 * 
 * For more inforation, see the sqlite docs on "Aggregate Functions":
 * https://www.sqlite.org/lang_aggfunc.html
**/
- (id)performAggregateQuery:(YapDatabaseQuery *)query;

/**
 * This method assists in performing a query over a subset of rows,
 * where the subset is a known set of keys.
 * 
 * For example:
 * 
 * Say you have a bunch of tracks & playlist objects in the database.
 * And you've added a secondary index on track.duration.
 * Now you want to quickly figure out the duration of an entire playlist.
 * 
 * NSArray *keys = [self trackKeysInPlaylist:playlist];
 * NSArray *rowids = [[[transaction ext:@"idx"] rowidsForKeys:keys inCollection:@"tracks"] allValues];
 *
 * YapDatabaseQuery *query =
 *   [YapDatabaseQuery queryWithAggregateFunction:@"SUM(duration)" format:@"WHERE rowid IN (?)", rowids];
**/
- (NSDictionary<NSString*, NSNumber*> *)rowidsForKeys:(NSArray<NSString *> *)keys
                                         inCollection:(nullable NSString *)collection;

@end

NS_ASSUME_NONNULL_END
