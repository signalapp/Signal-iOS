#import <Foundation/Foundation.h>


/**
 * A YapDatabaseQuery is used to pass SQL style queries into various extension classes.
 * The query that you pass represents everything after the SELECT clause of a query.
 * 
 * For example:
 * query = [YapDatabaseQuery queryWithFormat:@"WHERE department = ? AND salary >= ?", deptStr, @(minSalary)];
 * [secondaryIndex enumerateKeysAndObjectsMatchingQuery:query
 *                                           usingBlock:^(NSString *collection, NSString *key, id object, BOOL *stop){
 *     ...
 * }];
 *
 * Methods that take YapDatabaseQuery parameters will automatically prefix your query string with
 * the proper 'SELECT' clause. So it may get expanded to something like this:
 *
 * @"SELECT rowid FROM 'database' WHERE department = ? AND salary >= ?"
 *
 * YapDatabaseQuery supports the following types as query parameters:
 * - NSNumber
 * - NSDate    (automatically converted to double via timeIntervalSinceReferenceDate)
 * - NSString
 * - NSArray   (of any regular type above)
 * 
 * Example 2:
 * 
 * NSArray *departments = [self engineeringDepartments];
 * query = [YapDatabaseQuery queryWithFormat:@"WHERE title = ? AND department IN (?)", @"manager", departments];
**/
@interface YapDatabaseQuery : NSObject

/**
 * A YapDatabaseQuery is everything after the SELECT clause of a query.
 * Thus they generally start with "WHERE ...".
 * 
 * Please note that you can ONLY pass objects as parameters.
 * Primitive types such as int, float, double, etc are NOT supported.
 * You MUST wrap these using NSNumber.
**/
+ (instancetype)queryWithFormat:(NSString *)format, ...;

/**
 * Alternative initializer if you have a prepared va_list.
 * 
 * Swift note:
 * You may prefer to use 'queryWithString:(NSString *)queryString parameters:(NSArray *)queryParameters' instead.
 *
 * Alternatively, define the following somewhere in your Swift code:
 *
 * extension YapDatabaseQuery {
 *     class func queryWithFormat(format: String, _ arguments: CVarArgType...) -> YapDatabaseQuery? {
 *         return withVaList(arguments, { YapDatabaseQuery(format: format, arguments: $0) })
 *     }
 * }
**/
+ (instancetype)queryWithFormat:(NSString *)format arguments:(va_list)arguments;

/**
 * Alternative initializer - generally preferred for Swift code.
**/
+ (instancetype)queryWithString:(NSString *)queryString parameters:(NSArray *)queryParameters;

/**
 * Shorthand for a query with no 'WHERE' clause.
 * Equivalent to [YapDatabaseQuery queryWithFormat:@""].
**/
+ (instancetype)queryMatchingAll;

@property (nonatomic, strong, readonly) NSString *queryString;
@property (nonatomic, strong, readonly) NSArray *queryParameters;

@end
