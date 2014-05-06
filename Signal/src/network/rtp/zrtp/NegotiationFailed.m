#import "NegotiationFailed.h"

@implementation NegotiationFailed

@synthesize reason;

+(NegotiationFailed*) negotiationFailedWithReason:(NSString*)reason {
    NegotiationFailed* instance = [NegotiationFailed new];
    instance->reason = reason;
    return instance;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Negotation failed: %@", reason];
}

@end
