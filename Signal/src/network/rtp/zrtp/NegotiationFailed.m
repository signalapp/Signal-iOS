#import "NegotiationFailed.h"

@interface NegotiationFailed ()

@property (strong, readwrite, nonatomic) NSString* reason;

@end

@implementation NegotiationFailed

- (instancetype)initWithReason:(NSString*)reason {
    self = [super init];
	
    if (self) {
        self.reason = reason;
    }
    
    return self;
}

- (NSString*)description {
    return [NSString stringWithFormat:@"Negotation failed: %@", self.reason];
}

@end
