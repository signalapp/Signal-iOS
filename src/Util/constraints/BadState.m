//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "BadState.h"

@implementation BadState
+(void)raise:(NSString *)message {
    [BadState raise:@"Invalid State" format:@"%@", message];
}
@end
