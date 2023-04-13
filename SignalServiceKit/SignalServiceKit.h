//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

#ifndef signalservicekitprefix
#define signalservicekitprefix
#import <Availability.h>

#ifdef __OBJC__
#import <CocoaLumberjack/CocoaLumberjack.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#ifdef DEBUG
static const NSUInteger ddLogLevel = DDLogLevelAll;
#else
static const NSUInteger ddLogLevel = DDLogLevelInfo;
#endif
#import <SignalCoreKit/NSObject+OWS.h>
#import <SignalCoreKit/OWSAsserts.h>
#import <SignalServiceKit/OWSAnalytics.h>
#import <SignalServiceKit/SSKAsserts.h>

#endif
#endif

//! Project version number for SignalServiceKit.
FOUNDATION_EXPORT double SignalServiceKitVersionNumber;

//! Project version string for SignalServiceKit.
FOUNDATION_EXPORT const unsigned char SignalServiceKitVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import
// <SignalServiceKit/PublicHeader.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/AxolotlExceptions.h>
#import <SignalServiceKit/BaseModel.h>
#import <SignalServiceKit/ByteParser.h>
#import <SignalServiceKit/CallKitIdStore.h>
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/ContactsManagerProtocol.h>
#import <SignalServiceKit/DarwinNotificationCenter.h>
#import <SignalServiceKit/DataSource.h>
#import <SignalServiceKit/FunctionalUtil.h>
#import <SignalServiceKit/HTTPUtils.h>
#import <SignalServiceKit/IncomingGroupsV2MessageJob.h>
#import <SignalServiceKit/InstalledSticker.h>
#import <SignalServiceKit/KnownStickerPack.h>
#import <SignalServiceKit/LegacyChainKey.h>
#import <SignalServiceKit/LegacyMessageKeys.h>
#import <SignalServiceKit/LegacyReceivingChain.h>
#import <SignalServiceKit/LegacyRootKey.h>
#import <SignalServiceKit/LegacySendingChain.h>
#import <SignalServiceKit/LegacySessionRecord.h>
#import <SignalServiceKit/LegacySessionState.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/NSData+Image.h>
#import <SignalServiceKit/NSData+keyVersionByte.h>
#import <SignalServiceKit/NSString+SSK.h>
#import <SignalServiceKit/NSTimer+OWS.h>
#import <SignalServiceKit/NSUserDefaults+OWS.h>
#import <SignalServiceKit/NotificationsProtocol.h>
#import <SignalServiceKit/OWS2FAManager.h>
#import <SignalServiceKit/OWSAddToContactsOfferMessage.h>
#import <SignalServiceKit/OWSAddToProfileWhitelistOfferMessage.h>
#import <SignalServiceKit/OWSAnalytics.h>
#import <SignalServiceKit/OWSAnalyticsEvents.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSBackupFragment.h>
#import <SignalServiceKit/OWSBlockedPhoneNumbersMessage.h>
#import <SignalServiceKit/OWSCallMessageHandler.h>
#import <SignalServiceKit/OWSCensorshipConfiguration.h>
#import <SignalServiceKit/OWSChunkedOutputStream.h>
#import <SignalServiceKit/OWSContact+Private.h>
#import <SignalServiceKit/OWSContact.h>
#import <SignalServiceKit/OWSContactsOutputStream.h>
#import <SignalServiceKit/OWSCountryMetadata.h>
#import <SignalServiceKit/OWSDevice.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfigurationMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSDynamicOutgoingMessage.h>
#import <SignalServiceKit/OWSEndSessionMessage.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSFakeProfileManager.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/OWSFingerprint.h>
#import <SignalServiceKit/OWSFingerprintBuilder.h>
#import <SignalServiceKit/OWSGroupCallMessage.h>
#import <SignalServiceKit/OWSGroupInfoRequestMessage.h>
#import <SignalServiceKit/OWSGroupsOutputStream.h>
#import <SignalServiceKit/OWSHTTPSecurityPolicy.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSIncomingSentMessageTranscript.h>
#import <SignalServiceKit/OWSLinkedDeviceReadReceipt.h>
#import <SignalServiceKit/OWSMath.h>
#import <SignalServiceKit/OWSMessageContentJob.h>
#import <SignalServiceKit/OWSMessageHandler.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSMultipart.h>
#import <SignalServiceKit/OWSOperation.h>
#import <SignalServiceKit/OWSOutgoingCallMessage.h>
#import <SignalServiceKit/OWSOutgoingGroupCallMessage.h>
#import <SignalServiceKit/OWSOutgoingNullMessage.h>
#import <SignalServiceKit/OWSOutgoingPaymentMessage.h>
#import <SignalServiceKit/OWSOutgoingReactionMessage.h>
#import <SignalServiceKit/OWSOutgoingReceiptManager.h>
#import <SignalServiceKit/OWSOutgoingResendRequest.h>
#import <SignalServiceKit/OWSOutgoingResendResponse.h>
#import <SignalServiceKit/OWSOutgoingSenderKeyDistributionMessage.h>
#import <SignalServiceKit/OWSOutgoingSentMessageTranscript.h>
#import <SignalServiceKit/OWSOutgoingSyncMessage.h>
#import <SignalServiceKit/OWSProfileKeyMessage.h>
#import <SignalServiceKit/OWSQueues.h>
#import <SignalServiceKit/OWSReadReceiptsForLinkedDevicesMessage.h>
#import <SignalServiceKit/OWSReadTracking.h>
#import <SignalServiceKit/OWSReceiptManager.h>
#import <SignalServiceKit/OWSReceiptsForSenderMessage.h>
#import <SignalServiceKit/OWSRecipientIdentity.h>
#import <SignalServiceKit/OWSRecordTranscriptJob.h>
#import <SignalServiceKit/OWSRecoverableDecryptionPlaceholder.h>
#import <SignalServiceKit/OWSRequestFactory.h>
#import <SignalServiceKit/OWSStaticOutgoingMessage.h>
#import <SignalServiceKit/OWSStickerPackSyncMessage.h>
#import <SignalServiceKit/OWSSyncConfigurationMessage.h>
#import <SignalServiceKit/OWSSyncContactsMessage.h>
#import <SignalServiceKit/OWSSyncFetchLatestMessage.h>
#import <SignalServiceKit/OWSSyncGroupsMessage.h>
#import <SignalServiceKit/OWSSyncKeysMessage.h>
#import <SignalServiceKit/OWSSyncMessageRequestResponseMessage.h>
#import <SignalServiceKit/OWSSyncRequestMessage.h>
#import <SignalServiceKit/OWSUnknownContactBlockOfferMessage.h>
#import <SignalServiceKit/OWSUnknownProtocolVersionMessage.h>
#import <SignalServiceKit/OWSUpload.h>
#import <SignalServiceKit/OWSUploadOperation.h>
#import <SignalServiceKit/OWSUserProfile.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/OWSVerificationStateSyncMessage.h>
#import <SignalServiceKit/OWSViewOnceMessageReadSyncMessage.h>
#import <SignalServiceKit/OWSViewedReceiptsForLinkedDevicesMessage.h>
#import <SignalServiceKit/OutgoingCallEventSyncMessage.h>
#import <SignalServiceKit/OutgoingPaymentSyncMessage.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/PhoneNumberUtil.h>
#import <SignalServiceKit/PreKeyBundle+jsonDict.h>
#import <SignalServiceKit/PreKeyBundle.h>
#import <SignalServiceKit/PreKeyRecord.h>
#import <SignalServiceKit/ProfileManagerProtocol.h>
#import <SignalServiceKit/ProtoUtils.h>
#import <SignalServiceKit/RESTNetworkManager.h>
#import <SignalServiceKit/RemoteAttestationQuote.h>
#import <SignalServiceKit/SDSCrossProcess.h>
#import <SignalServiceKit/SDSDatabaseStorage+Objc.h>
#import <SignalServiceKit/SDSKeyValueStore+ObjC.h>
#import <SignalServiceKit/SSKAccessors+SDS.h>
#import <SignalServiceKit/SSKAsserts.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SSKPreKeyStore.h>
#import <SignalServiceKit/SSKSignedPreKeyStore.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalRecipient.h>
#import <SignalServiceKit/SignedPrekeyRecord.h>
#import <SignalServiceKit/StickerInfo.h>
#import <SignalServiceKit/StickerPack.h>
#import <SignalServiceKit/StorageCoordinator.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSAttachment.h>
#import <SignalServiceKit/TSAttachmentPointer.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSErrorMessage.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSInfoMessage.h>
#import <SignalServiceKit/TSInteraction.h>
#import <SignalServiceKit/TSInvalidIdentityKeyErrorMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeySendingErrorMessage.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSOutgoingDeleteMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSPaymentModel.h>
#import <SignalServiceKit/TSPaymentModels.h>
#import <SignalServiceKit/TSPaymentRequestModel.h>
#import <SignalServiceKit/TSPreKeyManager.h>
#import <SignalServiceKit/TSPrivateStoryThread.h>
#import <SignalServiceKit/TSQuotedMessage.h>
#import <SignalServiceKit/TSRequest.h>
#import <SignalServiceKit/TSStorageKeys.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/TSUnreadIndicatorInteraction.h>
#import <SignalServiceKit/TSYapDatabaseObject.h>
#import <SignalServiceKit/TestAppContext.h>
#import <SignalServiceKit/TestModel.h>
#import <SignalServiceKit/UIImage+OWS.h>
#import <SignalServiceKit/YDBStorage.h>
