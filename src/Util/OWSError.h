//  Copyright © 2016 Open Whisper Systems. All rights reserved.

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
    OWSErrorCodeSignalServiceFailure = 1001,
    OWSErrorCodeUserError = 2001,
};

extern NSError *OWSErrorWithCodeDescription(OWSErrorCode code, NSString *description);
extern NSError *OWSErrorMakeUnableToProcessServerResponseError();
extern NSError *OWSErrorMakeFailedToSendOutgoingMessageError();
extern NSError *OWSErrorMakeNoSuchSignalRecipientError();

NS_ASSUME_NONNULL_END
