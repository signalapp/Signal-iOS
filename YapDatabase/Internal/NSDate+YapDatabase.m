#import "NSDate+YapDatabase.h"


@implementation NSDate (YapDatabase)

- (BOOL)isBefore:(NSDate *)date
{
	return ([self compare:date] == NSOrderedAscending);
}

- (BOOL)isAfter:(NSDate *)date
{
	return ([self compare:date] == NSOrderedDescending);
}

- (BOOL)isBeforeOrEqual:(NSDate *)date
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

- (BOOL)isAfterOrEqual:(NSDate *)date
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
