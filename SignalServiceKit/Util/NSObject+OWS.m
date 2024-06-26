//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "NSObject+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSObject (OWS)

#pragma mark - Logging

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

+ (BOOL)isNullableObject:(nullable NSObject *)left equalTo:(nullable NSObject *)right
{
    if (!left && !right) {
        return YES;
    } else if (!left || !right) {
        return NO;
    } else {
        return [left isEqual:right];
    }
}

@end

NS_ASSUME_NONNULL_END
