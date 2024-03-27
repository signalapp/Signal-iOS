//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

extern NSString *const OWSSignalServiceKitErrorDomain;

// TODO: These error codes are sometimes persisted, so we should
//       explicitly assign a value to every case in this enum.
typedef NS_ENUM(NSInteger, OWSErrorCode) {
    OWSErrorCodeInvalidMethodParameters = 11,
    OWSErrorCodeObsolete12 = 12,
    OWSErrorCodeFailedToDecodeJson = 13,
    OWSErrorCodeFailedToEncodeJson = 14,
    OWSErrorCodeFailedToDecodeQR = 15,
    OWSErrorCodePrivacyVerificationFailure = 20,
    OWSErrorCodeUntrustedIdentity = 777427,
    OWSErrorCodeInvalidKeySignature = 777428,
    OWSErrorCodeObsolete30 = 30,
    OWSErrorCodeAssertionFailure = 31,
    OWSErrorCodeGenericFailure = 32,
    OWSErrorCodeFailedToDecryptMessage = 100,
    OWSErrorCodeFailedToDecryptUDMessage = 101,
    OWSErrorCodeFailedToEncryptMessage = 110,
    OWSErrorCodeFailedToEncryptUDMessage = 111,
    OWSErrorCodeMessageSendUnauthorized = 1001,
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
    OWSErrorCodeDebugLogUploadFailed = 777414,
    // A non-recoverable error occurred while exporting a backup.
    OWSErrorCodeExportBackupFailed = 777415,
    // A possibly recoverable error occurred while exporting a backup.
    OWSErrorCodeExportBackupError = 777416,
    // A non-recoverable error occurred while importing a backup.
    OWSErrorCodeImportBackupFailed = 777417,
    // A possibly recoverable error occurred while importing a backup.
    OWSErrorCodeImportBackupError = 777418,
    // A non-recoverable while importing or exporting a backup.
    OWSErrorCodeBackupFailure = 777419,
    OWSErrorCodeLocalAuthenticationError = 777420,
    OWSErrorCodeObsolete777421 = 777421,
    OWSErrorCodeObsolete777422 = 777422,
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
    OWSErrorCodeFailedToDecryptDuplicateMessage,
    OWSErrorCodeServerRejectedSuspectedSpam,
    OWSErrorCodeSenderKeyEphemeralFailure,
    OWSErrorCodeSenderKeyUnavailable,
    OWSErrorCodeMessageSendEncryptionFailure
};

extern NSError *OWSErrorMakeAssertionError(NSString *descriptionFormat, ...);
extern NSError *OWSErrorMakeGenericError(NSString *descriptionFormat, ...);

NS_ASSUME_NONNULL_END
