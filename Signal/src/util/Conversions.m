#import "Conversions.h"
#import "Util.h"

@implementation NSData (Conversions)

- (uint16_t)bigEndianUInt16At:(NSUInteger)offset {
    ows_require(offset <= self.length - sizeof(uint16_t));
    return (uint16_t)[self uint8At:1 + offset] | (uint16_t)((uint16_t)[self uint8At:0 + offset] << 8);
}
- (uint32_t)bigEndianUInt32At:(NSUInteger)offset {
    ows_require(offset <= self.length - sizeof(uint32_t));
    return ((uint32_t)[self uint8At:3 + offset] << 0) | ((uint32_t)[self uint8At:2 + offset] << 8) |
           ((uint32_t)[self uint8At:1 + offset] << 16) | ((uint32_t)[self uint8At:0 + offset] << 24);
}

+ (NSData *)dataWithBigEndianBytesOfUInt16:(uint16_t)value {
    uint8_t d[sizeof(uint16_t)];
    d[1] = (uint8_t)((value >> 0) & 0xFF);
    d[0] = (uint8_t)((value >> 8) & 0xFF);
    return [NSData dataWithBytes:d length:sizeof(uint16_t)];
}
+ (NSData *)dataWithBigEndianBytesOfUInt32:(uint32_t)value {
    uint8_t d[sizeof(uint32_t)];
    d[3] = (uint8_t)((value >> 0) & 0xFF);
    d[2] = (uint8_t)((value >> 8) & 0xFF);
    d[1] = (uint8_t)((value >> 16) & 0xFF);
    d[0] = (uint8_t)((value >> 24) & 0xFF);
    return [NSData dataWithBytes:d length:sizeof(uint32_t)];
}
+ (NSData *)switchEndiannessOfData:(NSData *)data {
    const void *bytes                 = [data bytes];
    NSMutableData *switchedEndianData = [NSMutableData new];
    for (NSUInteger i = data.length; i > 0; --i) {
        uint8_t byte = *(((uint8_t *)(bytes)) + ((i - 1) * sizeof(uint8_t)));
        [switchedEndianData appendData:[NSData dataWithBytes:&byte length:sizeof(byte)]];
    }
    return switchedEndianData;
}

@end
