#import "YapDatabaseTransaction+Timestamp.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

@implementation YapDatabaseReadTransaction (Timestamp)

/**
 * This method invokes metadataForKey: and checks the result.
 * If the resulting metadata is of class NSDate, it is returned.
 * Otherwise it returns nil.
**/
- (NSDate *)timestampForKey:(NSString *)key
{
	id metadata = [self metadataForKey:key];
	
	if ([metadata isKindOfClass:[NSDate class]])
		return (NSDate *)metadata;
	else
		return nil;
}

/**
 * Returns the list of keys, ordered by metadata timestamp.
 *
 * What do I pass for the 'ordered' parameter? Use:
 * - To enumerate from oldest to newest timestamp (1990,2004,2012): NSOrderedAscending
 * - To enumerate from newest to oldest timestamp (2012,2004,1990): NSOrderedDescending
 *
 * Keys without an associated metadata timestamp are not included in the list.
 *
 * If you don't pass a proper value for the ordered parameter (either NSOrderedAscending or NSOrderedDescending),
 * then the default value of NSOrderedAscending is used.
**/
- (NSArray *)allKeysOrdered:(NSComparisonResult)NSOrderedAscendingOrDescending
{
	// Extract the key/timestamp pairs (those that have a metadata timestamp).
	
	NSMutableDictionary *subMetadataDict = [NSMutableArray array];
	
	Class NSDateClass = [NSDate class];
	[self enumerateKeysAndMetadataUsingBlock:^(NSString *key, id metadata, BOOL *stop){
		
		if ([metadata isKindOfClass:NSDateClass])
		{
			[subMetadataDict setObject:metadata forKey:key];
		}
	}];
	
	// Check desired sorting order.
	// Default (if passed inappropriate value) is NSOrderedAscending.
	BOOL enumerateAscending = (NSOrderedAscendingOrDescending != NSOrderedDescending);
	
	// Sort keys according to desired sort order.
	
	return [subMetadataDict keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2) {
		
		__unsafe_unretained NSDate *date1 = (NSDate *)obj1;
		__unsafe_unretained NSDate *date2 = (NSDate *)obj2;
		
		NSComparisonResult result = [date1 compare:date2];
		
		if (enumerateAscending)
		{
			// normal sort ordering
			return result;
		}
		else
		{
			// reverse sort ordering
			if (result == NSOrderedAscending)  return NSOrderedDescending;
			if (result == NSOrderedDescending) return NSOrderedAscending;
			else return result;
		}
	}];
}

/**
 * Allows you to enumerate the keys based on their metadata timestamp.
 * 
 * What do I pass for the 'ordered' parameter? Use:
 * - To enumerate from oldest to newest timestamp (1990,2004,2012): NSOrderedAscending
 * - To enumerate from newest to oldest timestamp (2012,2004,1990): NSOrderedDescending
 *
 * Keys without a metadata timestamp are not included in the enumeration.
 *
 * If you don't pass a proper value for the ordered parameter (either NSOrderedAscending or NSOrderedDescending),
 * then the default value of NSOrderedAscending is used.
**/
- (void)enumerateKeysAndMetadataOrdered:(NSComparisonResult)NSOrderedAscendingOrDescending
                             usingBlock:
                (void (^)(NSUInteger idx, NSString *key, NSDate *timestamp, BOOL *stop))block
{
	if (!block) return;
	
	// Extract the key/timestamp pairs (those that have a metadata timestamp).
	
	NSMutableDictionary *subMetadataDict = [NSMutableArray array];
	
	Class NSDateClass = [NSDate class];
	[self enumerateKeysAndMetadataUsingBlock:^(NSString *key, id metadata, BOOL *stop){
		
		if ([metadata isKindOfClass:NSDateClass])
		{
			[subMetadataDict setObject:metadata forKey:key];
		}
	}];
	
	// Check desired sorting order.
	// Default (if passed inappropriate value) is NSOrderedAscending.
	BOOL enumerateAscending = (NSOrderedAscendingOrDescending != NSOrderedDescending);
	
	// Sort keys according to desired sort order.
	
	NSArray *orderedKeys = [subMetadataDict keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2) {
		
		__unsafe_unretained NSDate *date1 = (NSDate *)obj1;
		__unsafe_unretained NSDate *date2 = (NSDate *)obj2;
		
		NSComparisonResult result = [date1 compare:date2];
		
		if (enumerateAscending)
		{
			// normal sort ordering
			return result;
		}
		else
		{
			// reverse sort ordering
			if (result == NSOrderedAscending)  return NSOrderedDescending;
			if (result == NSOrderedDescending) return NSOrderedAscending;
			else return result;
		}
	}];
	
	// Perform enumeration
	
	[orderedKeys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop){
		
		__unsafe_unretained NSString *key = (NSString *)obj;
		
		NSDate *timestamp = (NSDate *)[self metadataForKey:key];
		
		block(idx, key, timestamp, stop);
	}];
}

/**
 * Allows you to enumerate the objects based on their metadata timestamp.
 *
 * What do I pass for the 'ordered' parameter? Use:
 * - To enumerate from oldest to newest timestamp: NSOrderedAscending
 * - To enumerate from newest to oldest timestamp: NSOrderedDescending
 *
 * Objects without a metadata timestamp are not included in the enumeration.
 * 
 * If you don't pass a proper value for the ordered parameter (either NSOrderedAscending or NSOrderedDescending),
 * then the default value of NSOrderedAscending is used.
**/
- (void)enumerateKeysAndObjectsOrdered:(NSComparisonResult)NSOrderedAscendingOrDescending usingBlock:
                (void (^)(NSUInteger idx, NSString *key, id object, NSDate *timestamp, BOOL *stop))block
{
	if (!block) return;
	
	// Extract the key/timestamp pairs (those that have a metadata timestamp).
	
	NSMutableDictionary *subMetadataDict = [NSMutableArray array];
	
	Class NSDateClass = [NSDate class];
	[self enumerateKeysAndMetadataUsingBlock:^(NSString *key, id metadata, BOOL *stop){
		
		if ([metadata isKindOfClass:NSDateClass])
		{
			[subMetadataDict setObject:metadata forKey:key];
		}
	}];
	
	// Check desired sorting order.
	// Default (if passed inappropriate value) is NSOrderedAscending.
	BOOL enumerateAscending = (NSOrderedAscendingOrDescending != NSOrderedDescending);
	
	// Sort keys according to desired sort order.
	
	NSArray *orderedKeys = [subMetadataDict keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2) {
		
		__unsafe_unretained NSDate *date1 = (NSDate *)obj1;
		__unsafe_unretained NSDate *date2 = (NSDate *)obj2;
		
		NSComparisonResult result = [date1 compare:date2];
		
		if (enumerateAscending)
		{
			// normal sort ordering
			return result;
		}
		else
		{
			// reverse sort ordering
			if (result == NSOrderedAscending)  return NSOrderedDescending;
			if (result == NSOrderedDescending) return NSOrderedAscending;
			else return result;
		}
	}];
	
	// Perform enumeration
	
	[orderedKeys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop){
		
		__unsafe_unretained NSString *key = (NSString *)obj;
		
		id object = nil;
		id metadata = nil;
		
		[self getObject:&object metadata:&metadata forKey:key];
		
		block(idx, key, object, (NSDate *)metadata, stop);
	}];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseReadWriteTransaction (Timestamp)

/**
 * This methods simply invokes setObject:forKey:withMetadata:, but provides stronger type safety for the compiler.
**/
- (void)setObject:(id)object forKey:(NSString *)key withTimestamp:(NSDate *)timestamp
{
	[self setObject:object forKey:key withMetadata:timestamp];
}

/**
 * This methods simply invokes setMetadata:forKey:, but provides stronger type safety for the compiler.
**/
- (void)setTimestamp:(NSDate *)timestamp forKey:(NSString *)key
{
	[self setMetadata:timestamp forKey:key];
}

/**
 * Removes any objects that have a metadata timestamp,
 * and whose timestamp is earlier than the given date.
**/
- (NSArray *)removeObjectsEarlierThan:(NSDate *)date
{
	if (date == nil) return nil;
	
	NSMutableArray *keysToRemove = [NSMutableArray array];
	
	Class NSDateClass = [NSDate class];
	[self enumerateKeysAndMetadataUsingBlock:^(NSString *key, id metadata, BOOL *stop){
		
		if ([metadata isKindOfClass:NSDateClass])
		{
			if (metadata == [date earlierDate:(NSDate *)metadata]) // date must be receiver in case of equality
			{
				[keysToRemove addObject:key];
			}
		}
	}];
	
	[self removeObjectsForKeys:keysToRemove];
	return keysToRemove;
}

/**
 * Removes any objects that have a metadata timestamp,
 * and whose timestamp is later than the given date.
**/
- (NSArray *)removeObjectsLaterThan:(NSDate *)date
{
	if (date == nil) return nil;
	
	NSMutableArray *keysToRemove = [NSMutableArray array];
	
	Class NSDateClass = [NSDate class];
	[self enumerateKeysAndMetadataUsingBlock:^(NSString *key, id metadata, BOOL *stop){
		
		if ([metadata isKindOfClass:NSDateClass])
		{
			if (metadata == [date laterDate:(NSDate *)metadata]) // date must be receiver in case of equality
			{
				[keysToRemove addObject:key];
			}
		}
	}];
	
	[self removeObjectsForKeys:keysToRemove];
	return keysToRemove;
}

/**
 * Removes any objects that have a metadata timestamp,
 * and whose timestamp is earlier or equal to the given data.
**/
- (NSArray *)removeObjectsEarlierThanOrEqualTo:(NSDate *)date
{
	return [self removeObjectsFrom:nil to:date];
}

/**
 * Removes any objects that have a metadata timestamp,
 * and whose timestamp is later or equal to the given data.
**/
- (NSArray *)removeObjectsLaterThanOrEqualTo:(NSDate *)date
{
	return [self removeObjectsFrom:date to:nil];
}

/**
 * Removes any objects that lie within the given time range (inclusive).
 *
 * That is, if an object has a metadata timestamp, then the object is removed if:
 * startDate >= timestamp <= endDate
 *
 * You may optionally pass nil for one of the dates.
 * For example, if you passed nil for the endDate,
 * then all objects with timestamp later than or equal to the given startDate would be removed.
**/
- (NSArray *)removeObjectsFrom:(NSDate *)startDate to:(NSDate *)endDate
{
	if ((startDate == nil) && (endDate == nil)) return nil;
	
	NSMutableArray *keysToRemove = [NSMutableArray array];
	
	Class NSDateClass = [NSDate class];
	[self enumerateKeysAndMetadataUsingBlock:^(NSString *key, id metadata, BOOL *stop){
		
		if ([metadata isKindOfClass:NSDateClass])
		{
			NSDate *timestamp = (NSDate *)metadata;
			BOOL remove = YES;
			
			if (startDate && (timestamp != [timestamp laterDate:startDate]))
			{
				remove = NO;
			}
			if (endDate && (timestamp != [timestamp earlierDate:endDate]))
			{
				remove = NO;
			}
			
			if (remove)
				[keysToRemove addObject:key];
		}
	}];
	
	[self removeObjectsForKeys:keysToRemove];
	return keysToRemove;
}

@end
