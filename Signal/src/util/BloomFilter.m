#import "BloomFilter.h"
#import "Constraints.h"
#import "Util.h"
#import "CryptoTools.h"
#import "Conversions.h"

@implementation BloomFilter

@synthesize hashCount, data;

+(BloomFilter*) bloomFilterWithNothing {
    return [BloomFilter bloomFilterWithHashCount:1 andData:[NSMutableData dataWithLength:1]];
}

+(BloomFilter*) bloomFilterWithEverything {
    NSMutableData* data = [NSMutableData dataWithLength:1];
    [data setUint8At:0 to:0xFF];
    return [BloomFilter bloomFilterWithHashCount:1 andData:data];
}

+(BloomFilter*) bloomFilterWithHashCount:(NSUInteger)hashCount
                                 andData:(NSData*)data {
    require(hashCount > 0);
    require(data != nil);
    
    BloomFilter* result = [BloomFilter new];
    result->hashCount = hashCount;
    result->data = data;
    return result;
}

-(uint32_t) hash:(NSData*)value index:(NSUInteger)index {
    NSData* key = [[[NSNumber numberWithUnsignedInteger:index] stringValue] encodedAsAscii];
    NSData* hash = [value hmacWithSha1WithKey:key];
    return [hash bigEndianUInt32At:0] % ([data length] * 8);
}

-(bool) isBitSetAt:(uint32_t)bitIndex {
    uint32_t byteIndex = bitIndex / 8;
    uint8_t bitMask = (uint8_t)(1 << (bitIndex % 8));
    return ([data uint8At:byteIndex] & bitMask) != 0;
}

-(bool) contains:(NSString*)entity {
    require(entity != nil);
    NSData* value = [entity encodedAsUtf8];
    for (NSUInteger i = 0; i < hashCount; i++) {
        uint32_t bitIndex = [self hash:value index:i];
        if (![self isBitSetAt:bitIndex]) {
            return false;
        }
    }
    return true;
}

-(NSString*) description {
    if (data.length == 1 && [data uint8At:0] == 0xFF) {
        return @"Everything (degenerate bloom filter)";
    }
    if (data.length == 1 && [data uint8At:0] == 0) {
        return @"Nothing (degenerate bloom filter)";
    }
    return [super description];
}

@end
