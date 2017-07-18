#import "NSDate+YapDatabase.h"


@implementation NSDate (YapDatabase)

- (BOOL)ydb_isBefore:(NSDate *)date
{
	return ([self compare:date] == NSOrderedAscending);
}

- (BOOL)ydb_isAfter:(NSDate *)date
{
	return ([self compare:date] == NSOrderedDescending);
}

- (BOOL)ydb_isBeforeOrEqual:(NSDate *)date
{
	// [dateA compare:dateB]
	//
	// NSOrderedSame       : dateA & dateB are the same
	// NSOrderedDescending : dateA is later in time than dateB
	// NSOrderedAscending  : dateA is earlier in time than dateB
	
	NSComparisonResult result = [self compare:date];
	return (result == NSOrderedAscending ||
	        result == NSOrderedSame);
}

- (BOOL)ydb_isAfterOrEqual:(NSDate *)date
{
	// [dateA compare:dateB]
	//
	// NSOrderedSame       : dateA & dateB are the same
	// NSOrderedDescending : dateA is later in time than dateB
	// NSOrderedAscending  : dateA is earlier in time than dateB
	
	NSComparisonResult result = [self compare:date];
	return (result == NSOrderedDescending ||
	        result == NSOrderedSame);
}

@end
