#import "Zid.h"
#import "Constraints.h"

@implementation Zid
+(Zid*) zidWithData:(NSData*)zidData {
    require(zidData != nil);
    require(zidData.length == 12);
    Zid* s = [Zid new];
    s->data = zidData;
    return s;
}
-(NSData*) getData {
    return data;
}
@end
