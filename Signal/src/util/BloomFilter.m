#import "BloomFilter.h"
#import "Constraints.h"
#import "Util.h"
#import "CryptoTools.h"
#import "NSData+CryptoTools.h"
#import "NSData+Conversions.h"

@interface BloomFilter ()

@property (nonatomic, readwrite) NSUInteger hashCount;
@property (nonatomic, readwrite) NSData* data;

@end

@implementation BloomFilter

- (instancetype)initWithHashCount:(NSUInteger)hashCount
                          andData:(NSData*)data {
    if (self = [super init]) {
        require(hashCount > 0);
        require(data != nil);
        
        self.hashCount = hashCount;
        self.data = data;
    }
    
    return self;
}

- (instancetype)initWithNothing {
    return [self initWithHashCount:1 andData:[NSMutableData dataWithLength:1]];
}

- (instancetype)initWithEverything {
    NSMutableData* data = [NSMutableData dataWithLength:1];
    [data setUint8At:0 to:0xFF];
    return [self initWithHashCount:1 andData:data];
}

- (uint32_t)hash:(NSData*)value
           index:(NSUInteger)index {
    NSData* key = [[@(index) stringValue] encodedAsAscii];
    NSData* hash = [value hmacWithSHA1WithKey:key];
    return [hash bigEndianUInt32At:0] % (self.data.length * 8);
}

- (bool)isBitSetAt:(uint32_t)bitIndex {
    uint32_t byteIndex = bitIndex / 8;
    uint8_t bitMask = (uint8_t)(1 << (bitIndex % 8));
    return ([self.data uint8At:byteIndex] & bitMask) != 0;
}

- (bool)contains:(NSString*)entity {
    require(entity != nil);
    NSData* value = entity.encodedAsUtf8;
    for (NSUInteger i = 0; i < self.hashCount; i++) {
        uint32_t bitIndex = [self hash:value index:i];
        if (![self isBitSetAt:bitIndex]) {
            return false;
        }
    }
    return true;
}

- (NSString*)description {
    if (self.data.length == 1 && [self.data uint8At:0] == 0xFF) {
        return @"Everything (degenerate bloom filter)";
    }
    if (self.data.length == 1 && [self.data uint8At:0] == 0) {
        return @"Nothing (degenerate bloom filter)";
    }
    return [super description];
}

@end
