#import "IgnoredPacketFailure.h"

@interface IgnoredPacketFailure ()

@property (strong, nonatomic) NSString* reason;

@end

@implementation IgnoredPacketFailure

- (instancetype)initWithReason:(NSString*)reason {
    self = [super init];
	
    if (self) {
        self.reason = reason;
    }
    
    return self;
}

- (NSString*)description {
    return [NSString stringWithFormat:@"Ignored: %@", self.reason];
}
@end
