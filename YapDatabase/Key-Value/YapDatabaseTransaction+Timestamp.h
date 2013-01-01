#import "YapDatabase.h"
#import "YapDatabaseTransaction.h"


/**
 * A common use case for metadata is to store timestamps.
 *
 * These categories provide a a number of enhancements including:
 *
 * - methods that strongly type the metadata as a date, making compiler type-checks possible
 * - methods for enumerating and cleaning the database.
 * 
 * Note: See YapAbstractDatabase.h for a faster serializer/deserializer when using timestamps.
**/

@interface YapDatabaseReadTransaction (Timestamp)

/**
 * This method invokes metadataForKey: and checks the result.
 * If the resulting metadata is of class NSDate, it is returned.
 * Otherwise it returns nil.
**/
- (NSDate *)timestampForKey:(NSString *)key;

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
- (NSArray *)allKeysOrdered:(NSComparisonResult)NSOrderedAscendingOrDescending;

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
                (void (^)(NSUInteger idx, NSString *key, NSDate *timestamp, BOOL *stop))block;

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
- (void)enumerateKeysAndObjectsOrdered:(NSComparisonResult)NSOrderedAscendingOrDescending
                            usingBlock:
                (void (^)(NSUInteger idx, NSString *key, id object, NSDate *timestamp, BOOL *stop))block;

@end


@interface YapDatabaseReadWriteTransaction (Timestamp)

/**
 * This methods simply invokes setObject:forKey:withMetadata:, but provides stronger type safety for the compiler.
**/
- (void)setObject:(id)object forKey:(NSString *)key withTimestamp:(NSDate *)timestamp;

/**
 * This methods simply invokes setMetadata:forKey:, but provides stronger type safety for the compiler.
**/
- (void)setTimestamp:(NSDate *)timestamp forKey:(NSString *)key;

/**
 * Removes any objects that have a metadata timestamp,
 * and whose timestamp is earlier/later than the given date.
 * 
 * @return An array of keys that were removed.
**/
- (NSArray *)removeObjectsEarlierThan:(NSDate *)date;
- (NSArray *)removeObjectsLaterThan:(NSDate *)date;

/**
 * Removes any objects that have a metadata timestamp,
 * and whose timestamp is earlier/later or equal to the given data.
 * 
 * @return An array of keys that were removed.
**/
- (NSArray *)removeObjectsEarlierThanOrEqualTo:(NSDate *)date;
- (NSArray *)removeObjectsLaterThanOrEqualTo:(NSDate *)date;

/**
 * Removes any objects that lie within the given time range (inclusive).
 *
 * That is, if an object has a metadata timestamp, then the object is removed if:
 * startDate >= timestamp <= endDate
 * 
 * You may optionally pass nil for one of the dates.
 * For example, if you passed nil for the endDate,
 * then all objects with timestamp later than or equal to the given startDate would be removed.
 * 
 * @return An array of keys that were removed.
**/
- (NSArray *)removeObjectsFrom:(NSDate *)startDate to:(NSDate *)endDate;

@end
