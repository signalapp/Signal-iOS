//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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
    OWSErrorCodeUntrustedIdentity = 25,
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
    OWSErrorCodeContactsUpdaterRateLimit = 777408,
    OWSErrorCodeCouldNotWriteAttachmentData = 777409,
    OWSErrorCodeMessageDeletedBeforeSent = 777410,
    OWSErrorCodeDatabaseConversionFatalError = 777411
};

extern NSString *const OWSErrorRecipientIdentifierKey;

extern NSError *OWSErrorWithCodeDescription(OWSErrorCode code, NSString *description);
extern NSError *OWSErrorMakeUntrustedIdentityError(NSString *description, NSString *recipientId);
extern NSError *OWSErrorMakeUnableToProcessServerResponseError(void);
extern NSError *OWSErrorMakeFailedToSendOutgoingMessageError(void);
extern NSError *OWSErrorMakeNoSuchSignalRecipientError(void);
extern NSError *OWSErrorMakeAssertionError(void);
extern NSError *OWSErrorMakeMessageSendDisabledDueToPreKeyUpdateFailuresError(void);
extern NSError *OWSErrorMakeMessageSendFailedToBlockListError(void);
extern NSError *OWSErrorMakeWriteAttachmentDataError(void);

NS_ASSUME_NONNULL_END
