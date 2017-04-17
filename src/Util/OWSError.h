//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSSignalServiceKitErrorDomain;

typedef NS_ENUM(NSInteger, OWSErrorCode) {
    OWSErrorCodeInvalidMethodParameters = 11,
    OWSErrorCodeUnableToProcessServerResponse = 12,
    OWSErrorCodeFailedToDecodeJson = 13,
    OWSErrorCodeFailedToEncodeJson = 14,
    OWSErrorCodeFailedToDecodeQR = 15,
    OWSErrorCodePrivacyVerificationFailure = 20,
    OWSErrorCodeUntrustedIdentityKey = 25,
    OWSErrorCodeFailedToSendOutgoingMessage = 30,
    OWSErrorCodeFailedToDecryptMessage = 100,
    OWSErrorCodeFailedToEncryptMessage = 110,
    OWSErrorCodeSignalServiceFailure = 1001,
    OWSErrorCodeSignalServiceRateLimited = 1010,
    OWSErrorCodeUserError = 2001,
    OWSErrorCodeNoSuchSignalRecipient = 777404,
    OWSErrorCodeMessageSendDisabledDueToPreKeyUpdateFailures = 777405,
    OWSErrorCodeMessageSendFailedToBlockList = 777406,
    OWSErrorCodeMessageSendNoValidRecipients = 777407,
    OWSErrorCodeContactsUpdaterRateLimit = 777407,
};

extern NSError *OWSErrorWithCodeDescription(OWSErrorCode code, NSString *description);
extern NSError *OWSErrorMakeUnableToProcessServerResponseError();
extern NSError *OWSErrorMakeFailedToSendOutgoingMessageError();
extern NSError *OWSErrorMakeNoSuchSignalRecipientError();
extern NSError *OWSErrorMakeAssertionError();
extern NSError *OWSErrorMakeMessageSendDisabledDueToPreKeyUpdateFailuresError();
extern NSError *OWSErrorMakeMessageSendFailedToBlockListError();

NS_ASSUME_NONNULL_END
