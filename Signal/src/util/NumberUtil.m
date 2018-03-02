//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NumberUtil.h"

@implementation NumberUtil

+ (int16_t)congruentDifferenceMod2ToThe16From:(uint16_t)s1 to:(uint16_t)s2 {
    int32_t d = (int32_t)(s2 - s1);
    if (d > INT16_MAX)
        d -= 1 << 16;
    return (int16_t)d;
}

+ (int8_t)signOfInt32:(int32_t)value {
    if (value < 0)
        return -1;
    if (value > 0)
        return +1;
    return 0;
}

+ (int8_t)signOfDouble:(double)value {
    if (value < 0)
        return -1;
    if (value > 0)
        return +1;
    return 0;
}

+ (NSUInteger)largestIntegerThatIsAtMost:(NSUInteger)value andIsAMultipleOf:(NSUInteger)multiple {
    OWSAssert(multiple != 0);
    NSUInteger d = value / multiple;
    d *= multiple;
    if (d > value)
        d -= multiple;
    return d;
}

+ (NSUInteger)smallestIntegerThatIsAtLeast:(NSUInteger)value andIsAMultipleOf:(NSUInteger)multiple {
    OWSAssert(multiple != 0);
    NSUInteger d = value / multiple;
    d *= multiple;
    if (d < value)
        d += multiple;
    return d;
}

+ (double)clamp:(double)value toMin:(double)min andMax:(double)max {
    OWSAssert(min <= max);
    if (isnan(value)) {
        return max;
    }

    if (value < min) {
        return min;
    }

    if (value > max) {
        return max;
    }

    return value;
}

+ (NSUInteger)from:(NSUInteger)value subtractWithSaturationAtZero:(NSUInteger)minusDelta {
    return value - MIN(value, minusDelta);
}

+ (uint8_t)uint8FromLowUInt4:(uint8_t)low4UInt4 andHighUInt4:(uint8_t)highUInt4 {
    OWSAssert(low4UInt4 < 0x10);
    OWSAssert(highUInt4 < 0x10);
    return low4UInt4 | (uint8_t)(highUInt4 << 4);
}

+ (uint8_t)lowUInt4OfUint8:(uint8_t)value {
    return value & 0xF;
}

+ (uint8_t)highUInt4OfUint8:(uint8_t)value {
    return value >> 4;
}

+ (NSUInteger)assertConvertIntToNSUInteger:(int)value {
    OWSAssert(0 <= value);
    return (NSUInteger)value;
}

+ (NSInteger)assertConvertUnsignedIntToNSInteger:(unsigned int)value {
    // uint is a subset of NSInteger(long) bounds check is always true
    return (NSInteger)value;
}

+ (int)assertConvertNSUIntegerToInt:(NSUInteger)value {
    OWSAssert(value <= INT32_MAX);
    return (int)value;
}


@end

@implementation NSNumber (NumberUtil)

- (bool)hasUnsignedIntegerValue {
    return [self isEqual:@([self unsignedIntegerValue])];
}
- (bool)hasUnsignedLongLongValue {
    return [self isEqual:@([self unsignedLongLongValue])];
}
- (bool)hasLongLongValue {
    return [self isEqual:@([self longLongValue])];
}

@end
