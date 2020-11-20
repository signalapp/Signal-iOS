//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSError.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSSignalServiceKitErrorDomain = @"OWSSignalServiceKitErrorDomain";
NSString *const OWSErrorRecipientAddressKey = @"OWSErrorRecipientAddress";

NSError *OWSErrorWithCodeDescription(OWSErrorCode code, NSString *description)
{
    return OWSErrorWithUserInfo(code, @{ NSLocalizedDescriptionKey: description });
}

NSError *OWSErrorWithUserInfo(OWSErrorCode code, NSDictionary *userInfo)
{
    return [NSError errorWithDomain:OWSSignalServiceKitErrorDomain
                               code:code
                           userInfo:userInfo];
}

NSError *OWSErrorMakeUnableToProcessServerResponseError()
{
    return OWSErrorWithCodeDescription(OWSErrorCodeUnableToProcessServerResponse,
        NSLocalizedString(@"ERROR_DESCRIPTION_SERVER_FAILURE", @"Generic server error"));
}

NSError *OWSErrorMakeFailedToSendOutgoingMessageError()
{
    return OWSErrorWithCodeDescription(OWSErrorCodeFailedToSendOutgoingMessage,
        NSLocalizedString(@"ERROR_DESCRIPTION_CLIENT_SENDING_FAILURE", @"Generic notice when message failed to send."));
}

NSError *OWSErrorMakeNoSuchSignalRecipientError()
{
    return OWSErrorWithCodeDescription(OWSErrorCodeNoSuchSignalRecipient,
        NSLocalizedString(
            @"ERROR_DESCRIPTION_UNREGISTERED_RECIPIENT", @"Error message when attempting to send message"));
}

NSError *OWSErrorMakeAssertionError(NSString *descriptionFormat, ...)
{
    va_list args;
    va_start(args, descriptionFormat);
    NSString *description = [[NSString alloc] initWithFormat:descriptionFormat arguments:args];
    va_end(args);
    OWSCFailDebug(@"Assertion failed: %@", description);
    return OWSErrorWithCodeDescription(OWSErrorCodeAssertionFailure,
        NSLocalizedString(@"ERROR_DESCRIPTION_UNKNOWN_ERROR", @"Worst case generic error message"));
}

NSError *OWSErrorMakeGenericError(NSString *descriptionFormat, ...)
{
    va_list args;
    va_start(args, descriptionFormat);
    NSString *description = [[NSString alloc] initWithFormat:descriptionFormat arguments:args];
    va_end(args);
    OWSLogWarn(@"%@", description);
    return OWSErrorWithCodeDescription(OWSErrorCodeGenericFailure,
        NSLocalizedString(@"ERROR_DESCRIPTION_UNKNOWN_ERROR", @"Worst case generic error message"));
}

NSError *OWSErrorMakeUntrustedIdentityError(NSString *description, SignalServiceAddress *address)
{
    return [NSError
        errorWithDomain:OWSSignalServiceKitErrorDomain
                   code:OWSErrorCodeUntrustedIdentity
               userInfo:@{ NSLocalizedDescriptionKey : description, OWSErrorRecipientAddressKey : address }];
}

NSError *OWSErrorMakeMessageSendDisabledDueToPreKeyUpdateFailuresError()
{
    return OWSErrorWithCodeDescription(OWSErrorCodeMessageSendDisabledDueToPreKeyUpdateFailures,
        NSLocalizedString(@"ERROR_DESCRIPTION_MESSAGE_SEND_DISABLED_PREKEY_UPDATE_FAILURES",
            @"Error message indicating that message send is disabled due to prekey update failures"));
}

NSError *OWSErrorMakeMessageSendFailedDueToBlockListError()
{
    return OWSErrorWithCodeDescription(OWSErrorCodeMessageSendFailedToBlockList,
        NSLocalizedString(@"ERROR_DESCRIPTION_MESSAGE_SEND_FAILED_DUE_TO_BLOCK_LIST",
            @"Error message indicating that message send failed due to block list"));
}

NS_ASSUME_NONNULL_END
