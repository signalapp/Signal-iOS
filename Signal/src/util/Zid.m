#import "Constraints.h"
#import "Zid.h"

@implementation Zid
+ (Zid *)zidWithData:(NSData *)zidData {
    ows_require(zidData != nil);
    ows_require(zidData.length == 12);
    Zid *s  = [Zid new];
    s->data = zidData;
    return s;
}

+ (instancetype)nullZid {
    NSMutableData *data = [NSMutableData dataWithLength:12];
    return [self zidWithData:data];
}

- (NSData *)getData {
    return data;
}
@end
