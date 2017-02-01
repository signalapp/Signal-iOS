//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSError.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSSignalServiceKitErrorDomain = @"OWSSignalServiceKitErrorDomain";

NSError *OWSErrorWithCodeDescription(OWSErrorCode code, NSString *description)
{
    return [NSError errorWithDomain:OWSSignalServiceKitErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: description }];
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
    return OWSErrorWithCodeDescription(OWSErrorCodeFailedToSendOutgoingMessage,
        NSLocalizedString(
            @"ERROR_DESCRIPTION_UNREGISTERED_RECIPIENT", @"Error message when attempting to send message"));
}

NSError *OWSErrorMakeAssertionError()
{
    return OWSErrorWithCodeDescription(OWSErrorCodeFailedToSendOutgoingMessage,
                                       NSLocalizedString(@"ERROR_DESCRIPTION_UNKNOWN_ERROR", @"Worst case generic error message"));
}

NSError *OWSErrorMakeWebRTCMissingDataChannelError()
{
    return OWSErrorWithCodeDescription(OWSErrorCodeWebRTCMissingDataChannel,
                                       NSLocalizedString(@"ERROR_DESCRIPTION_WEBRTC_MISSING_DATA_CHANNEL", @"Missing data channel while trying to sending message"));
}

NS_ASSUME_NONNULL_END
