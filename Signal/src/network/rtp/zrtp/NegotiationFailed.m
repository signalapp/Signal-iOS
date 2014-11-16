#import "NegotiationFailed.h"

@interface NegotiationFailed ()

@property (strong, readwrite, nonatomic) NSString* reason;

@end

@implementation NegotiationFailed

- (instancetype)initWithReason:(NSString*)reason {
    if (self = [super init]) {
        self.reason = reason;
    }
    
    return self;
}

- (NSString*)description {
    return [NSString stringWithFormat:@"Negotation failed: %@", self.reason];
}

@end
