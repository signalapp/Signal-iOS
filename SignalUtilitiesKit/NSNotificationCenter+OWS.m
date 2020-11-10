//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NSNotificationCenter+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSNotificationCenter (OWS)

- (void)postNotificationNameAsync:(NSNotificationName)name object:(nullable id)object
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self postNotificationName:name object:object];
    });
}

- (void)postNotificationNameAsync:(NSNotificationName)name
                           object:(nullable id)object
                         userInfo:(nullable NSDictionary *)userInfo
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self postNotificationName:name object:object userInfo:userInfo];
    });
}

@end

NS_ASSUME_NONNULL_END
