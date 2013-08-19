#import "YapDatabaseViewMappings.h"

/**
 * This header file is PRIVATE, and is only to be used by the YapDatabaseView classes.
**/

@interface YapDatabaseViewMappings ()

/**
 * For UNIT TESTING only.
**/
- (void)updateWithCounts:(NSDictionary *)counts;

/**
 * Returns a mutable copy of the count dictionary, where:
 * key = group
 * value = NSNumber of count of items
**/
- (NSMutableDictionary *)counts;

/**
 * fullCountForGroup    => Count from view.group (excluding rangeOptions)
 * visibleCountForGroup => Subset count          (including rangeOptions)
**/
- (NSUInteger)fullCountForGroup:(NSString *)group;
- (NSUInteger)visibleCountForGroup:(NSString *)group;

/**
 * Returns a copy of the rangeOptions dictionary, where:
 * key = group
 * value = YapDatabaseViewMappingsRangeOptions
**/
- (NSDictionary *)rangeOptions;

/**
 * This method is used by YapDatabaseViewChange.
 * 
 * After processing changeset(s), the length and/or offset may change.
 * The new length and/or offsets are properly calculated,
 * and then this method is used to avoid duplicating the calculations.
**/
- (void)updateRangeOptionsForGroup:(NSString *)group
                     withNewLength:(NSUInteger)newLength
                         newOffset:(NSUInteger)newOffset;

/**
 * Returns a copy of the dependencies dictionary, where:
 * key = group
 * value = NSSet of cellDrawingDependency offsets
**/
- (NSDictionary *)dependencies;

/**
 * Returns a copy of the reverse set, which contains groups that are to be reversed.
**/
- (NSSet *)reverse;

@end
