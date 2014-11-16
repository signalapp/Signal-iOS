#import "UnrecognizedRequestFailure.h"

@interface UnrecognizedRequestFailure ()

@property (strong, nonatomic) NSString* reason;

@end

@implementation UnrecognizedRequestFailure

- (instancetype)initWithReason:(NSString*)reason {
    if (self = [super init]) {
        self.reason = reason;
    }
    
    return self;
}

- (NSString*)description {
    return [NSString stringWithFormat:@"Unrecognized request: %@", self.reason];
}
@end
