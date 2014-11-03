#import "Zid.h"
#import "Constraints.h"

@interface Zid ()

@property (strong, nonatomic, readwrite) NSData* data;

@end

@implementation Zid

- (instancetype)initWithData:(NSData*)zidData {
    if (self = [super init]) {
        require(zidData != nil);
        require(zidData.length == 12);
        self.data = zidData;
    }
    
    return self;
}

@end
