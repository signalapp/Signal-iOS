//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSAsserts.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

void SwiftExit(NSString *message, const char *file, const char *function, int line)
{
    NSString *_file = [NSString stringWithFormat:@"%s", file];
    NSString *_function = [NSString stringWithFormat:@"%s", function];
    [OWSSwiftUtils owsFailObjC:message file:_file function:_function line:line];
}

NS_ASSUME_NONNULL_END
