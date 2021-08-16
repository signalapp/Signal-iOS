//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSSignalServiceKitErrorDomain = @"OWSSignalServiceKitErrorDomain";

NSError *OWSErrorMakeUnableToProcessServerResponseError()
{
    // TODO: Audit all of the places this is called and replace with more specific errors.
    return [OWSError withError:OWSErrorCodeUnableToProcessServerResponse
                   description:NSLocalizedString(@"ERROR_DESCRIPTION_SERVER_FAILURE", @"Generic server error")
                   isRetryable:YES];
}

NSError *OWSErrorMakeAssertionError(NSString *descriptionFormat, ...)
{
    va_list args;
    va_start(args, descriptionFormat);
    NSString *description = [[NSString alloc] initWithFormat:descriptionFormat arguments:args];
    va_end(args);
    OWSCFailDebug(@"Assertion failed: %@", description);
    return
        [OWSError withError:OWSErrorCodeAssertionFailure
                description:NSLocalizedString(@"ERROR_DESCRIPTION_UNKNOWN_ERROR", @"Worst case generic error message")
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
                description:NSLocalizedString(@"ERROR_DESCRIPTION_UNKNOWN_ERROR", @"Worst case generic error message")
                isRetryable:NO];
}

NS_ASSUME_NONNULL_END
