//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSAnalyticsEvents : NSObject

- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Code Generation Marker

+ (NSString *)accountsErrorRegisterPushTokensFailed;

+ (NSString *)accountsErrorUnregisterAccountRequestFailed;

+ (NSString *)accountsErrorVerificationCodeRequestFailed;

+ (NSString *)accountsErrorVerifyAccountRequestFailed;

+ (NSString *)appDelegateErrorFailedToRegisterForRemoteNotifications;

+ (NSString *)appLaunch;

+ (NSString *)appLaunchComplete;

+ (NSString *)callServiceCallAlreadySet;

+ (NSString *)callServiceCallIdMismatch;

+ (NSString *)callServiceCallMismatch;

+ (NSString *)callServiceCallMissing;

+ (NSString *)callServiceCallUnexpectedlyIdle;

+ (NSString *)callServiceCouldNotCreatePeerConnectionClientPromise;

+ (NSString *)callServiceCouldNotCreateReadyToSendIceUpdatesPromise;

+ (NSString *)callServiceMissingFulfillReadyToSendIceUpdatesPromise;

+ (NSString *)callServicePeerConnectionAlreadySet;

+ (NSString *)callServicePeerConnectionMissing;

+ (NSString *)contactsErrorContactsIntersectionFailed;

+ (NSString *)errorAttachmentRequestFailed;

+ (NSString *)errorEnableVideoCallingRequestFailed;

+ (NSString *)errorGetDevicesFailed;

+ (NSString *)errorPrekeysAvailablePrekeysRequestFailed;

+ (NSString *)errorPrekeysCurrentSignedPrekeyRequestFailed;

+ (NSString *)errorPrekeysUpdateFailedJustSigned;

+ (NSString *)errorPrekeysUpdateFailedSignedAndOnetime;

+ (NSString *)errorProvisioningCodeRequestFailed;

+ (NSString *)errorProvisioningRequestFailed;

+ (NSString *)errorUnlinkDeviceFailed;

+ (NSString *)errorUpdateAttributesRequestFailed;

+ (NSString *)messageManagerErrorCouldNotHandlePrekeyBundle;

+ (NSString *)messageManagerErrorCouldNotHandleSecureMessage;

+ (NSString *)messageManagerErrorEnvelopeTypeKeyExchange;

+ (NSString *)messageManagerErrorEnvelopeTypeOther;

+ (NSString *)messageManagerErrorEnvelopeTypeUnknown;

+ (NSString *)messageManagerErrorInvalidProtocolMessage;

+ (NSString *)messageManagerErrorMessageEnvelopeHasNoContent;

+ (NSString *)messageManagerErrorOversizeMessage;

+ (NSString *)messageManagerErrorPrekeyBundleEnvelopeHasNoContent;

+ (NSString *)messageSendErrorCouldNotSerializeMessageJson;

+ (NSString *)messageSendErrorFailedDueToPrekeyUpdateFailures;

+ (NSString *)messageSendErrorFailedDueToUntrustedKey;

+ (NSString *)messageSenderErrorCouldNotFindContacts1;

+ (NSString *)messageSenderErrorCouldNotFindContacts2;

+ (NSString *)messageSenderErrorCouldNotFindContacts3;

+ (NSString *)messageSenderErrorCouldNotLoadAttachment;

+ (NSString *)messageSenderErrorCouldNotParseMismatchedDevicesJson;

+ (NSString *)messageSenderErrorCouldNotWriteAttachment;

+ (NSString *)messageSenderErrorGenericSendFailure;

+ (NSString *)messageSenderErrorInvalidIdentityKeyLength;

+ (NSString *)messageSenderErrorInvalidIdentityKeyType;

+ (NSString *)messageSenderErrorNoMissingOrExtraDevices;

+ (NSString *)messageSenderErrorRecipientPrekeyRequestFailed;

+ (NSString *)messageSenderErrorSendOperationDidNotComplete;

+ (NSString *)messageSenderErrorUnexpectedKeyBundle;

+ (NSString *)prekeysDeletedOldSignedPrekey;

+ (NSString *)storageErrorCouldNotDecodeClass;

+ (NSString *)storageErrorCouldNotLoadDatabase;

+ (NSString *)storageErrorCouldNotLoadDatabaseSecondAttempt;

+ (NSString *)storageErrorCouldNotStoreDatabasePassword;

+ (NSString *)storageErrorDeserialization;

+ (NSString *)storageErrorFileProtection;

#pragma mark - Code Generation Marker

@end

NS_ASSUME_NONNULL_END
