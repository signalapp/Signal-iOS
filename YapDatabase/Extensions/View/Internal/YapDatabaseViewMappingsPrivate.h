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
 * Returns a copy of the dependencies dictionary, where:
 * key = group
 * value = NSSet of cellDrawingDependency offsets
**/
- (NSDictionary *)dependencies;

@end
