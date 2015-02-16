#import <Foundation/Foundation.h>


/**
 * A YapDatabaseQuery is used to pass SQL style queries into various extension classes.
 * The query that you pass represents everything after the SELECT clause of a query.
**/
@interface YapDatabaseQuery : NSObject

/**
 * A YapDatabaseQuery is everything after the SELECT clause of a query.
 * Methods that take YapDatabaseQuery parameters will prefix your query string similarly to:
 * 
 * fullQuery = @"SELECT rowid FROM 'database' " + [yapDatabaseQuery queryString];
 * 
 * Example 1:
 * 
 * query = [YapDatabaseQuery queryWithFormat:@"WHERE jid = ?", message.jid];
 * [secondaryIndex enumerateKeysAndObjectsMatchingQuery:query
 *                                           usingBlock:^(NSString *key, id object, BOOL *stop){
 *     ...
 * }];
 * 
 * Please note that you can ONLY pass objective-c objects as parameters.
 * Primitive types such as int, float, double, etc are NOT supported.
 * You MUST wrap these using NSNumber.
 * 
 * Example 2:
 *
 * query = [YapDatabaseQuery queryWithFormat:@"WHERE department = ? AND salary >= ?", dept, @(minSalary)];
 * [secondaryIndex enumerateKeysAndObjectsMatchingQuery:query
 *                                           usingBlock:^(NSString *key, id object, BOOL *stop){
 *     ...
 * }];
**/
+ (instancetype)queryWithFormat:(NSString *)format, ...;

/**
 * Shim that allows YapDatabaseQuery to be used from Swift.
 *
 * Define the following somewhere in your Swift code:
 *
 * extension YapDatabaseQuery {
 *     class func queryWithFormat(format: String, _ arguments: CVarArgType...) -> YapDatabaseQuery? {
 *         return withVaList(arguments, { YapDatabaseQuery(format: format, arguments: $0) })
 *     }
 * }
 **/
+ (instancetype)queryWithFormat:(NSString *)format arguments:(va_list)arguments;

/**
 * Shorthand for a query with no 'WHERE' clause.
 * Equivalent to [YapDatabaseQuery queryWithFormat:@""].
**/
+ (instancetype)queryMatchingAll;

@property (nonatomic, strong, readonly) NSString *queryString;
@property (nonatomic, strong, readonly) NSArray *queryParameters;

@end
