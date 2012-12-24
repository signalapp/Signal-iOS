#import "YapCollectionsDatabase+Timestamp.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

@implementation YapCollectionsDatabaseReadTransaction (Timestamp)

/**
 * This method invokes metadataForKey:inCollection: and checks the result.
 * If the resulting metadata is of class NSDate, it is returned.
 * Otherwise it returns nil.
**/
- (NSDate *)timestampForKey:(NSString *)key inCollection:(NSString *)collection
{
	id metadata = [self metadataForKey:key inCollection:collection];
	
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
- (NSArray *)allKeysOrdered:(NSComparisonResult)NSOrderedAscendingOrDescending inCollection:(NSString *)collection
{
	// Extract the key/timestamp pairs (those that have a metadata timestamp).
	
	NSMutableDictionary *subMetadataDict = [NSMutableArray array];
	
	Class NSDateClass = [NSDate class];
	[self enumerateKeysAndMetadataInCollection:collection usingBlock:^(NSString *key, id metadata, BOOL *stop){
		
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
 * Objects without a metadata timestamp are not included in the enumeration.
 * 
 * If you don't pass a proper value for the ordered parameter (either NSOrderedAscending or NSOrderedDescending),
 * then the default value of NSOrderedAscending is used.
**/
- (void)enumerateKeysAndMetadataInCollection:(NSString *)collection
                                     ordered:(NSComparisonResult)NSOrderedAscendingOrDescending
                                  usingBlock:
                (void (^)(NSUInteger idx, NSString *key, NSDate *timestamp, BOOL *stop))block
{
	if (!block) return;
	
	// Extract the key/timestamp pairs (those that have a metadata timestamp).
	
	NSMutableDictionary *subMetadataDict = [NSMutableArray array];
	
	Class NSDateClass = [NSDate class];
	[self enumerateKeysAndMetadataInCollection:collection usingBlock:^(NSString *key, id metadata, BOOL *stop){
		
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
		
		NSDate *timestamp = (NSDate *)[self metadataForKey:key inCollection:collection];
		
		block(idx, key, timestamp, stop);
	}];
}

/**
 * Allows you to enumerate the objects based on their metadata timestamp.
 *
 * What do I pass for the 'ordered' parameter? Use:
 * - To enumerate from oldest to newest timestamp (1990,2004,2012): NSOrderedAscending
 * - To enumerate from newest to oldest timestamp (2012,2004,1990): NSOrderedDescending
 * 
 * Objects without a metadata timestamp are not included in the enumeration.
 * 
 * If you don't pass a proper value for the ordered parameter (either NSOrderedAscending or NSOrderedDescending),
 * then the default value of NSOrderedAscending is used.
**/
- (void)enumerateKeysAndObjectsInCollection:(NSString *)collection
                                    ordered:(NSComparisonResult)NSOrderedAscendingOrDescending
                                 usingBlock:
                (void (^)(NSUInteger idx, NSString *key, id object, NSDate *timestamp, BOOL *stop))block
{
	if (!block) return;
	
	// Extract the key/timestamp pairs (those that have a metadata timestamp).
	
	NSMutableDictionary *subMetadataDict = [NSMutableArray array];
	
	Class NSDateClass = [NSDate class];
	[self enumerateKeysAndMetadataInCollection:collection usingBlock:^(NSString *key, id metadata, BOOL *stop){
		
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
		
		[self getObject:&object metadata:&metadata forKey:key inCollection:collection];
		
		block(idx, key, object, (NSDate *)metadata, stop);
	}];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapCollectionsDatabaseReadWriteTransaction (Timestamp)

/**
 * This methods simply invokes setObject:forKey:inCollection:withMetadata:,
 * but provides stronger type safety for the compiler.
**/
- (void)setObject:(id)object
           forKey:(NSString *)key
     inCollection:(NSString *)collection
    withTimestamp:(NSDate *)timestamp
{
	[self setObject:object forKey:key inCollection:collection withMetadata:timestamp];
}

/**
 * This methods simply invokes setMetadata:forKey:inCollection, but provides stronger type safety for the compiler.
**/
- (void)setTimestamp:(NSDate *)timestamp forKey:(NSString *)key inCollection:(NSString *)collection
{
	[self setMetadata:timestamp forKey:key inCollection:collection];
}

/**
 * Removes any objects, in the given collection, that have a metadata timestamp
 * and whose timestamp is earlier than the given date.
**/
- (void)removeObjectsEarlierThan:(NSDate *)date inCollection:(NSString *)collection
{
	if (date == nil) return;
	
	NSMutableArray *keysToRemove = [NSMutableArray array];
	
	Class NSDateClass = [NSDate class];
	[self enumerateKeysAndMetadataInCollection:collection usingBlock:^(NSString *key, id metadata, BOOL *stop){
		
		if ([metadata isKindOfClass:NSDateClass])
		{
			if (metadata == [date earlierDate:(NSDate *)metadata]) // date must be receiver in case of equality
			{
				[keysToRemove addObject:key];
			}
		}
	}];
	
	[self removeObjectsForKeys:keysToRemove inCollection:collection];
}

/**
 * Removes any objects, in the given collection, that have a metadata timestamp
 * and whose timestamp is later than the given date.
**/
- (void)removeObjectsLaterThan:(NSDate *)date inCollection:(NSString *)collection
{
	if (date == nil) return;
	
	NSMutableArray *keysToRemove = [NSMutableArray array];
	
	Class NSDateClass = [NSDate class];
	[self enumerateKeysAndMetadataInCollection:collection usingBlock:^(NSString *key, id metadata, BOOL *stop){
		
		if ([metadata isKindOfClass:NSDateClass])
		{
			if (metadata == [date laterDate:(NSDate *)metadata]) // date must be receiver in case of equality
			{
				[keysToRemove addObject:key];
			}
		}
	}];
	
	[self removeObjectsForKeys:keysToRemove inCollection:collection];
}

/**
 * Removes any objects, in the given collection, that have a metadata timestamp
 * and whose timestamp is earlier or equal to the given data.
**/
- (void)removeObjectsEarlierThanOrEqualTo:(NSDate *)date inCollection:(NSString *)collection
{
	[self removeObjectsFrom:nil to:date inCollection:collection];
}

/**
 * Removes any objects, in the given collection, that have a metadata timestamp
 * and whose timestamp is later or equal to the given data.
**/
- (void)removeObjectsLaterThanOrEqualTo:(NSDate *)date inCollection:(NSString *)collection
{
	[self removeObjectsFrom:date to:nil inCollection:collection];
}

/**
 * Removes any objects, in the given collection, that lie within the given time range (inclusive).
 *
 * That is, if an object has a metadata timestamp, then the object is removed if:
 * startDate >= timestamp <= endDate
 *
 * You may optionally pass nil for one of the dates.
 * For example, if you passed nil for the endDate,
 * then all objects with timestamp later than or equal to the given startDate would be removed.
**/
- (void)removeObjectsFrom:(NSDate *)startDate to:(NSDate *)endDate inCollection:(NSString *)collection
{
	if ((startDate == nil) && (endDate == nil)) return;
	
	NSMutableArray *keysToRemove = [NSMutableArray array];
	
	Class NSDateClass = [NSDate class];
	[self enumerateKeysAndMetadataInCollection:collection usingBlock:^(NSString *key, id metadata, BOOL *stop){
		
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
	
	[self removeObjectsForKeys:keysToRemove inCollection:collection];
}

/**
 * Removes any objects, in any collection, that lie within the given time range (inclusive).
 * 
 * @see removeObjectsFrom:to:inCollection:
**/
- (void)removeObjectsInAllCollectionsFrom:(NSDate *)startDate to:(NSDate *)endDate
{
	for (NSString *collection in [self allCollections])
	{
		[self removeObjectsFrom:startDate to:endDate inCollection:collection];
	}
}

@end
