//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSError.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSSignalServiceKitErrorDomain = @"OWSSignalServiceKitErrorDomain";

NSError *OWSErrorMakeAssertionError(NSString *descriptionFormat, ...)
{
    va_list args;
    va_start(args, descriptionFormat);
    NSString *description = [[NSString alloc] initWithFormat:descriptionFormat arguments:args];
    va_end(args);
    OWSCFailDebug(@"Assertion failed: %@", description);
    return
        [OWSError withError:OWSErrorCodeAssertionFailure
                description:OWSLocalizedString(@"ERROR_DESCRIPTION_UNKNOWN_ERROR", @"Worst case generic error message")
                isRetryable:NO];
}

NSError *OWSErrorMakeGenericError(NSString *descriptionFormat, ...)
{
    va_list args;
    va_start(args, descriptionFormat);
    NSString *description = [[NSString alloc] initWithFormat:descriptionFormat arguments:args];
    va_end(args);
    OWSLogWarn(@"%@", description);
    return
        [OWSError withError:OWSErrorCodeGenericFailure
                description:OWSLocalizedString(@"ERROR_DESCRIPTION_UNKNOWN_ERROR", @"Worst case generic error message")
                isRetryable:NO];
}

NS_ASSUME_NONNULL_END
