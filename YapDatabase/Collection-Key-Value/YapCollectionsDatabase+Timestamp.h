#import "YapCollectionsDatabaseTransaction.h"


/**
 * A common use case for metadata is to store timestamps.
 *
 * This category provides a few simple methods that make the metadata type more explicit,
 * and thereby provide a strongly typed version more easily checkable by the compiler.
 *
 * Additionally, the category provides a few convenience methods for enumerating and cleaning the database.
**/
@interface YapCollectionsDatabaseReadTransaction (Timestamp)

/**
 * This method invokes metadataForKey:inCollection: and checks the result.
 * If the resulting metadata is of class NSDate, it is returned.
 * Otherwise it returns nil.
**/
- (NSDate *)timestampForKey:(NSString *)key inCollection:(NSString *)collection;

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
- (NSArray *)allKeysOrdered:(NSComparisonResult)NSOrderedAscendingOrDescending inCollection:(NSString *)collection;

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
- (void)enumerateKeysAndObjectsInCollection:(NSString *)collection
                                    ordered:(NSComparisonResult)NSOrderedAscendingOrDescending
                                 usingBlock:
                (void (^)(NSUInteger idx, NSString *key, id object, NSDate *timestamp, BOOL *stop))block;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapCollectionsDatabaseReadWriteTransaction (Timestamp)

/**
 * This methods simply invokes setObject:forKey:inCollection:withMetadata:,
 * but provides stronger type safety for the compiler.
**/
- (void)setObject:(id)object
           forKey:(NSString *)key
     inCollection:(NSString *)collection
    withTimestamp:(NSDate *)timestamp;

/**
 * This methods simply invokes setMetadata:forKey:inCollection, but provides stronger type safety for the compiler.
**/
- (void)setTimestamp:(NSDate *)timestamp forKey:(NSString *)key inCollection:(NSString *)collection;

/**
 * Removes any objects that have a metadata timestamp,
 * and whose timestamp is earlier/later than the given date.
**/
- (void)removeObjectsEarlierThan:(NSDate *)date inCollection:(NSString *)collection;
- (void)removeObjectsLaterThan:(NSDate *)date inCollection:(NSString *)collection;

/**
 * Removes any objects that have a metadata timestamp,
 * and whose timestamp is earlier/later or equal to the given data.
**/
- (void)removeObjectsEarlierThanOrEqualTo:(NSDate *)date inCollection:(NSString *)collection;
- (void)removeObjectsLaterThanOrEqualTo:(NSDate *)date inCollection:(NSString *)collection;

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
- (void)removeObjectsFrom:(NSDate *)startDate to:(NSDate *)endDate inCollection:(NSString *)collection;

@end
