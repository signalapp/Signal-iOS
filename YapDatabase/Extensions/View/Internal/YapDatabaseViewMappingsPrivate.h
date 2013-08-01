#import "YapDatabaseViewMappings.h"

@class YapDatabaseViewMappingsRangeOptions;

/**
 * This header file is PRIVATE, and is only to be used by the YapDatabaseView classes.
**/

@interface YapDatabaseViewMappings ()

/**
 * For UNIT TESTING only.
**/
- (void)updateWithCounts:(NSDictionary *)counts;

/**
 * Returns a copy of the rangeOptions dictionary, where:
 * 
 * key = group
 * value = YapDatabaseViewMappingsRangeOptions
**/
- (NSDictionary *)rangeOptions;

/**
 * Allows the changeset processing methods to update the range(s) as needed.
 * E.g. when a soft range expands due to inserted objects within the range.
 * 
 * @see YapDatabaseViewChange postProcessAndFilterRowChanges:withOriginalMappings:finalMappings:
**/
- (void)setRangeOptions:(YapDatabaseViewMappingsRangeOptions *)rangeOpts forGroup:(NSString *)group;

@end


/**
 * This class is just a simple object wrapper used to store the range options within a dictionary.
**/
@interface YapDatabaseViewMappingsRangeOptions : NSObject

- (id)initWithRange:(NSRange)range hard:(BOOL)isHardRange pin:(YapDatabaseViewPin)pin;

@property (nonatomic, assign, readonly) NSRange range;
@property (nonatomic, assign, readonly) BOOL isHardRange;
@property (nonatomic, assign, readonly) YapDatabaseViewPin pin;

@end
