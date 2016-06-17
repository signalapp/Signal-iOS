#import "YapDatabaseViewRangeOptions.h"


@implementation YapDatabaseViewRangeOptions

@synthesize length = length;
@synthesize offset = offset;
@synthesize pin = pin;

@synthesize isFixedRange = isFixedRange;
@dynamic isFlexibleRange;

@synthesize maxLength = maxLength;
@synthesize minLength = minLength;

@synthesize growOptions = growOptions;

+ (YapDatabaseViewRangeOptions *)fixedRangeWithLength:(NSUInteger)length
                                               offset:(NSUInteger)offset
                                                 from:(YapDatabaseViewPin)pin
{
	if (length == 0)
		return nil;
	
	// Validate pin
	if (pin > YapDatabaseViewEnd)
		pin = YapDatabaseViewEnd;
	
	YapDatabaseViewRangeOptions *rangeOpts = [[YapDatabaseViewRangeOptions alloc] init];
	rangeOpts->length = length;
	rangeOpts->offset = offset;
	rangeOpts->pin = pin;
	rangeOpts->isFixedRange = YES;
	rangeOpts->maxLength = length;
	rangeOpts->minLength = 0;
	rangeOpts->growOptions = YapDatabaseViewGrowPinSide;
	
	return rangeOpts;
}

+ (YapDatabaseViewRangeOptions *)flexibleRangeWithLength:(NSUInteger)length
                                                  offset:(NSUInteger)offset
                                                    from:(YapDatabaseViewPin)pin
{
	if (length == 0)
		return nil;
	
	// Validate pin
	if (pin > YapDatabaseViewEnd)
		pin = YapDatabaseViewEnd;
	
	YapDatabaseViewRangeOptions *rangeOpts = [[YapDatabaseViewRangeOptions alloc] init];
	rangeOpts->length = length;
	rangeOpts->offset = offset;
	rangeOpts->pin = pin;
	rangeOpts->isFixedRange = NO;
	rangeOpts->maxLength = NSUIntegerMax;
	rangeOpts->minLength = 0;
	rangeOpts->growOptions = YapDatabaseViewGrowPinSide;
	
	return rangeOpts;
}

- (BOOL)isFlexibleRange
{
	return !isFixedRange;
}

- (void)setMaxLength:(NSUInteger)newMaxLength
{
	maxLength = MAX(newMaxLength, minLength);
}

- (void)setMinLength:(NSUInteger)newMinLength
{
	minLength = MIN(newMinLength, maxLength);
}

- (void)setGrowOptions:(YapDatabaseViewGrowOptions)newGrowOptions
{
	// validate growOptions
	
	if (growOptions > YapDatabaseViewGrowOnBothSides)
		growOptions = YapDatabaseViewGrowPinSide; // Default
	else
		growOptions = newGrowOptions;
}

#pragma mark Copy

- (id)copyWithZone:(NSZone __unused *)zone
{
	YapDatabaseViewRangeOptions *copy = [[YapDatabaseViewRangeOptions alloc] init];
	copy->length = length;
	copy->offset = offset;
	copy->pin = pin;
	copy->isFixedRange = isFixedRange;
	copy->maxLength = maxLength;
	copy->minLength = minLength;
	copy->growOptions = growOptions;
	
	return copy;
}

- (id)copyWithNewLength:(NSUInteger)newLength
{
	YapDatabaseViewRangeOptions *copy = [self copy];
	copy->length = newLength;
	
	return copy;
}

- (id)copyWithNewOffset:(NSUInteger)newOffset
{
	YapDatabaseViewRangeOptions *copy = [self copy];
	copy->offset = newOffset;
	
	return copy;
}

- (id)copyWithNewLength:(NSUInteger)newLength newOffset:(NSUInteger)newOffset
{
	YapDatabaseViewRangeOptions *copy = [self copy];
	copy->length = newLength;
	copy->offset = newOffset;
	
	return copy;
}

- (id)copyAndReverse
{
	YapDatabaseViewRangeOptions *copy = [self copy];
	if (copy->pin == YapDatabaseViewBeginning)
		copy->pin = YapDatabaseViewEnd;
	else
		copy->pin = YapDatabaseViewBeginning;
	
	return copy;
}

@end
