#import "UnrecognizedRequestFailure.h"

@interface UnrecognizedRequestFailure ()

@property (strong, nonatomic) NSString* reason;

@end

@implementation UnrecognizedRequestFailure

- (instancetype)initWithReason:(NSString*)reason {
    self = [super init];
	
    if (self) {
        self.reason = reason;
    }
    
    return self;
}

- (NSString*)description {
    return [NSString stringWithFormat:@"Unrecognized request: %@", self.reason];
}
@end
