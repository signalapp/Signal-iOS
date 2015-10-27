#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A YapDatabaseQuery is used to pass SQL style queries into various extension classes.
 * The query is generally a subset of a full SQL query, as the system can handle various details automatically.
 * 
 * For example:
 *
 * query = [YapDatabaseQuery queryWithFormat:@"WHERE department = ? AND salary >= ?", deptStr, @(minSalary)];
 * [secondaryIndex enumerateKeysAndObjectsMatchingQuery:query
 *                                           usingBlock:^(NSString *collection, NSString *key, id object, BOOL *stop){
 *     ...
 * }];
 *
 * YapDatabaseQuery supports the following types as query parameters:
 * - NSNumber
 * - NSDate    (automatically converted to double via timeIntervalSinceReferenceDate)
 * - NSString
 * - NSData
 * - NSArray   (of any regular type above)
 * 
 * Array example:
 * 
 * NSArray *departments = [self engineeringDepartments];
 * query = [YapDatabaseQuery queryWithFormat:@"WHERE title = ? AND department IN (?)", @"manager", departments];
**/
@interface YapDatabaseQuery : NSObject

#pragma mark Standard Queries

/**
 * A "standard" YapDatabaseQuery is everything after the SELECT clause of a query.
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

#pragma mark Aggregate Queries

/**
 * Aggregate Queries (avg, max, min, sum, ...)
 * 
 * For example:
 *
 * // Figure out how much the "dev" department costs the business via salaries.
 * // We do this by asking the database to sum the salary column(s) matching the given query.
 *
 * YapDatabaseQuery *query = [YapDatabaseQuery queryWithAggregateFunction:@"SUM(salary)"
 *                                                                 format:@"WHERE department = ?", @"dev"];
 *
 * For more inforation, see the sqlite docs on "Aggregate Functions":
 * https://www.sqlite.org/lang_aggfunc.html
**/
+ (instancetype)queryWithAggregateFunction:(NSString *)aggregateFunction format:(NSString *)format, ...;

+ (instancetype)queryWithAggregateFunction:(NSString *)aggregateFunction
                                    format:(NSString *)format
                                 arguments:(va_list)arguments;

+ (instancetype)queryWithAggregateFunction:(NSString *)aggregateFunction
                                    string:(NSString *)queryString
                                parameters:(NSArray *)queryParameters;


#pragma mark Properties

@property (nonatomic, copy, readonly) NSString *aggregateFunction;
@property (nonatomic, copy, readonly) NSString *queryString;
@property (nonatomic, copy, readonly) NSArray *queryParameters;

@property (nonatomic, readonly) BOOL isAggregateQuery;

@end

NS_ASSUME_NONNULL_END
