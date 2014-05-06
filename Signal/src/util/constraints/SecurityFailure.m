#import "SecurityFailure.h"

@implementation SecurityFailure
+(SecurityFailure*) new:(NSString*)reason {
    return [[SecurityFailure alloc] initWithName:@"Insecure" reason:reason userInfo:nil];
}
+(void)raise:(NSString *)message {
    [SecurityFailure raise:@"Insecure" format:@"%@", message];
}
@end
