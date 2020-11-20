//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

extern NSString *const OWSSignalServiceKitErrorDomain;

typedef NS_ENUM(NSInteger, OWSErrorCode) {
    OWSErrorCodeInvalidMethodParameters = 11,
    OWSErrorCodeUnableToProcessServerResponse = 12,
    OWSErrorCodeFailedToDecodeJson = 13,
    OWSErrorCodeFailedToEncodeJson = 14,
    OWSErrorCodeFailedToDecodeQR = 15,
    OWSErrorCodePrivacyVerificationFailure = 20,
    OWSErrorCodeUntrustedIdentity = 777427,
    OWSErrorCodeFailedToSendOutgoingMessage = 30,
    OWSErrorCodeAssertionFailure = 31,
    OWSErrorCodeGenericFailure = 32,
    OWSErrorCodeFailedToDecryptMessage = 100,
    OWSErrorCodeFailedToDecryptUDMessage = 101,
    OWSErrorCodeFailedToEncryptMessage = 110,
    OWSErrorCodeFailedToEncryptUDMessage = 111,
    OWSErrorCodeSignalServiceFailure = 1001,
    OWSErrorCodeSignalServiceRateLimited = 1010,
    OWSErrorCodeUserError = 2001,
    OWSErrorCodeNoSuchSignalRecipient = 777404,
    OWSErrorCodeMessageSendDisabledDueToPreKeyUpdateFailures = 777405,
    OWSErrorCodeMessageSendFailedToBlockList = 777406,
    OWSErrorCodeMessageSendNoValidRecipients = 777407,
    OWSErrorCodeCouldNotWriteAttachmentData = 777409,
    OWSErrorCodeMessageDeletedBeforeSent = 777410,
    OWSErrorCodeDatabaseConversionFatalError = 777411,
    OWSErrorCodeMoveFileToSharedDataContainerError = 777412,
    OWSErrorCodeRegistrationMissing2FAPIN = 777413,
    OWSErrorCodeDebugLogUploadFailed = 777414,
    // A non-recoverable error occured while exporting a backup.
    OWSErrorCodeExportBackupFailed = 777415,
    // A possibly recoverable error occured while exporting a backup.
    OWSErrorCodeExportBackupError = 777416,
    // A non-recoverable error occured while importing a backup.
    OWSErrorCodeImportBackupFailed = 777417,
    // A possibly recoverable error occured while importing a backup.
    OWSErrorCodeImportBackupError = 777418,
    // A non-recoverable while importing or exporting a backup.
    OWSErrorCodeBackupFailure = 777419,
    OWSErrorCodeLocalAuthenticationError = 777420,
    OWSErrorCodeMessageRequestFailed = 777421,
    OWSErrorCodeMessageResponseFailed = 777422,
    OWSErrorCodeInvalidMessage = 777423,
    OWSErrorCodeProfileUpdateFailed = 777424,
    OWSErrorCodeAvatarWriteFailed = 777425,
    OWSErrorCodeAvatarUploadFailed = 777426,
    OWSErrorCodeNoSessionForTransientMessage,
    OWSErrorCodeUploadFailed,
    OWSErrorCodeInvalidStickerData,
    OWSErrorCodeAttachmentDownloadFailed,
    OWSErrorCodeAppExpired,
    OWSErrorCodeMissingLocalThread,
    OWSErrorCodeContactSyncFailed,
    OWSErrorCodeAppDeregistered,
    OWSErrorCodeRegistrationTransferAvailable,
    OWSErrorCodeFailedToDecryptDuplicateMessage
};

extern NSString *const OWSErrorRecipientAddressKey;

extern NSError *OWSErrorWithCodeDescription(OWSErrorCode code, NSString *description);
extern NSError *OWSErrorWithUserInfo(OWSErrorCode code, NSDictionary *userInfo);
extern NSError *OWSErrorMakeUntrustedIdentityError(NSString *description, SignalServiceAddress *address);
extern NSError *OWSErrorMakeUnableToProcessServerResponseError(void);
extern NSError *OWSErrorMakeFailedToSendOutgoingMessageError(void);
extern NSError *OWSErrorMakeNoSuchSignalRecipientError(void);
extern NSError *OWSErrorMakeAssertionError(NSString *descriptionFormat, ...);
extern NSError *OWSErrorMakeGenericError(NSString *descriptionFormat, ...);
extern NSError *OWSErrorMakeMessageSendDisabledDueToPreKeyUpdateFailuresError(void);
extern NSError *OWSErrorMakeMessageSendFailedDueToBlockListError(void);

NS_ASSUME_NONNULL_END
