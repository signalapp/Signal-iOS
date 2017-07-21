//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OperationFailed.h"

@implementation OperationFailed
+(OperationFailed*) new:(NSString*)reason {
    return [[OperationFailed alloc] initWithName:@"Operation failed" reason:reason userInfo:nil];
}
+(void)raise:(NSString *)message {
    [OperationFailed raise:@"Operation failed" format:@"%@", message];
}
@end
