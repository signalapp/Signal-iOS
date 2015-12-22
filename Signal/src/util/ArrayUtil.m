#import "ArrayUtil.h"
#import "Constraints.h"

@implementation NSArray (Util)

- (NSData *)ows_toUint8Data {
    NSUInteger n = self.count;
    uint8_t x[n];
    for (NSUInteger i = 0; i < n; i++) {
        x[i] = [(NSNumber *)self[i] unsignedCharValue];
    }
    return [NSData dataWithBytes:x length:n];
}
- (NSData *)ows_concatDatas {
    NSUInteger t = 0;
    for (id d in self) {
        ows_require([d isKindOfClass:NSData.class]);
        t += [(NSData *)d length];
    }

    NSMutableData *result = [NSMutableData dataWithLength:t];
    uint8_t *dst          = [result mutableBytes];
    for (NSData *d in self) {
        memcpy(dst, [d bytes], d.length);
        dst += d.length;
    }
    return result;
}
- (NSArray *)ows_concatArrays {
    NSMutableArray *r = [NSMutableArray array];
    for (id e in self) {
        ows_require([e isKindOfClass:NSArray.class]);
        [r addObjectsFromArray:e];
    }
    return r;
}

@end
