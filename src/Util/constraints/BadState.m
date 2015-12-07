#import "Constraints.h"

@implementation BadState
+(void)raise:(NSString *)message {
    [BadState raise:@"Invalid State" format:@"%@", message];
}
@end
