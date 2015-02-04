#import "YapDatabaseQuery.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapDatabaseQuery
{
	NSString *queryString;
	NSArray *queryParameters;
}

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
+ (instancetype)queryWithFormat:(NSString *)format, ...
{
    va_list arguments;
    va_start(arguments, format);
    id query = [self queryWithFormat:format arguments:arguments];
    va_end(arguments);
    return query;
}

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
+ (instancetype)queryWithFormat:(NSString *)format arguments:(va_list)args
{
	if (format == nil) return nil;
	
	NSUInteger paramCount = 0;
	NSUInteger formatLength = [format length];
	
	NSRange searchRange = NSMakeRange(0, formatLength);
	NSRange paramRange = [format rangeOfString:@"?" options:0 range:searchRange];
	
	NSMutableArray *paramLocations = [NSMutableArray array];
	
	while (paramRange.location != NSNotFound)
	{
		paramCount++;
		
		[paramLocations addObject:@(paramRange.location)];
		
		searchRange.location = paramRange.location + 1;
		searchRange.length = formatLength - searchRange.location;
		
		paramRange = [format rangeOfString:@"?" options:0 range:searchRange];
	}
	
	// Please note that you can ONLY pass objective-c objects as parameters.
	// Primitive types such as int, float, double, etc are NOT supported.
	// You MUST wrap these using NSNumber.
	
	NSMutableArray *queryParameters = [NSMutableArray arrayWithCapacity:paramCount];
	
	@try
	{
		NSMutableDictionary *paramIndexToElementCountMap = [NSMutableDictionary dictionary];
		for (NSUInteger i = 0; i < paramCount; i++)
		{
			id param = va_arg(args, id);
			if ([param isKindOfClass:[NSArray class]])
			{
				paramIndexToElementCountMap[@(i)] = @([param count]);
				[queryParameters addObjectsFromArray:param];
			}
			else
			{
				[queryParameters addObject:param];
			}
		}
		
		if (paramIndexToElementCountMap.count > 0)
		{
			NSUInteger unpackingOffset = 0;
			NSString *queryString = [format copy];
			NSRange range;
			for (NSNumber *index in paramIndexToElementCountMap)
			{
				NSInteger elementCount = [paramIndexToElementCountMap[index] intValue];
				NSMutableArray *unpackedParams = [NSMutableArray array];
				for (NSUInteger i = 0; i < elementCount; i++)
				{
					[unpackedParams addObject:@"?"];
				}
				NSString *unpackedParamsStr = [unpackedParams componentsJoinedByString:@","];
				range = NSMakeRange([paramLocations[[index intValue]] intValue] + unpackingOffset, 1);
				queryString = [queryString stringByReplacingCharactersInRange:range
																													 withString:unpackedParamsStr];
			}
			
			format = [queryString copy];
		}
	}
	@catch (NSException *exception)
	{
		YDBLogError(@"Error processing query. Expected %lu parameters. All parameters must be objects. %@",
		            (unsigned long)paramCount, exception);
		
		queryParameters = nil;
	}
	
	if (queryParameters || (paramCount == 0))
	{
		return [[YapDatabaseQuery alloc] initWithQueryString:format queryParameters:queryParameters];
	}
	else
	{
		return nil;
	}
}

/**
 * Shorthand for a query with no 'WHERE' clause.
 * Equivalent to [YapDatabaseQuery queryWithFormat:@""].
 **/
+ (instancetype)queryMatchingAll
{
	return [[YapDatabaseQuery alloc] initWithQueryString:@"" queryParameters:nil];
}

- (id)initWithQueryString:(NSString *)inQueryString queryParameters:(NSArray *)inQueryParameters
{
	if ((self = [super init]))
	{
		queryString = [inQueryString copy];
		queryParameters = [inQueryParameters copy];
	}
	return self;
}

@synthesize queryString;
@synthesize queryParameters;

@end
