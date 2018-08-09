#import <Foundation/Foundation.h>
#import "ArrayUtil.h"
#import "DataUtil.h"
#import "DictionaryUtil.h"
#import "StringUtil.h"

@interface NumberUtil : NSObject

+ (int16_t)congruentDifferenceMod2ToThe16From:(uint16_t)s1 to:(uint16_t)s2;

+ (int8_t)signOfInt32:(int32_t)value;

+ (int8_t)signOfDouble:(double)value;

+ (NSUInteger)largestIntegerThatIsAtMost:(NSUInteger)value andIsAMultipleOf:(NSUInteger)multiple;

+ (NSUInteger)smallestIntegerThatIsAtLeast:(NSUInteger)value andIsAMultipleOf:(NSUInteger)multiple;

+ (double)clamp:(double)value toMin:(double)min andMax:(double)max;

+ (NSUInteger)from:(NSUInteger)value subtractWithSaturationAtZero:(NSUInteger)minusDelta;

+ (uint8_t)uint8FromLowUInt4:(uint8_t)low4UInt4 andHighUInt4:(uint8_t)highUInt4;

+ (uint8_t)lowUInt4OfUint8:(uint8_t)value;

+ (uint8_t)highUInt4OfUint8:(uint8_t)value;

+ (NSUInteger)assertConvertIntToNSUInteger:(int)value;

+ (NSInteger)assertConvertUnsignedIntToNSInteger:(unsigned int)value;

+ (int)assertConvertNSUIntegerToInt:(NSUInteger)value;

@end

@interface NSNumber (NumberUtil)

- (bool)hasUnsignedIntegerValue;
- (bool)hasUnsignedLongLongValue;
- (bool)hasLongLongValue;

@end
