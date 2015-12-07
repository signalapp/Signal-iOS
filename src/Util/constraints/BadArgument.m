#import "BadArgument.h"

@implementation BadArgument
+(BadArgument*) new:(NSString*)reason {
    return [[BadArgument alloc] initWithName:@"Invalid Argument" reason:reason userInfo:nil];
}
+(void)raise:(NSString *)message {
    [BadArgument raise:@"Invalid Argument" format:@"%@", message];
}
@end
