#import "UnrecognizedRequestFailure.h"

@implementation UnrecognizedRequestFailure

+(UnrecognizedRequestFailure*) new:(NSString*)reason {
    UnrecognizedRequestFailure* instance = [UnrecognizedRequestFailure new];
    instance->reason = reason;
    return instance;
}

-(NSString *)description {
    return [NSString stringWithFormat:@"Unrecognized request: %@", reason];
}
@end
