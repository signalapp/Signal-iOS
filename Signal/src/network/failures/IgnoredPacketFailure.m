#import "IgnoredPacketFailure.h"

@implementation IgnoredPacketFailure

+(IgnoredPacketFailure*) new:(NSString*)reason {
    IgnoredPacketFailure* instance = [IgnoredPacketFailure new];
    instance->reason = reason;
    return instance;
}

-(NSString *)description {
    return [NSString stringWithFormat:@"Ignored: %@", reason];
}
@end
