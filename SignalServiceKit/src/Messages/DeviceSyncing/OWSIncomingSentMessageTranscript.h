//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class AciObjC;
@class DisappearingMessageToken;
@class MessageBodyRanges;
@class MessageSticker;
@class OWSContact;
@class OWSGiftBadge;
@class OWSLinkPreview;
@class SDSAnyWriteTransaction;
@class SSKProtoAttachmentPointer;
@class SSKProtoDataMessage;
@class SSKProtoSyncMessageSent;
@class ServiceIdObjC;
@class SignalServiceAddress;
@class TSPaymentNotification;
@class TSQuotedMessage;
@class TSThread;

/**
 * Represents notification of a message sent on our behalf from another device.
 * E.g. When we send a message from Signal-Desktop we want to see it in our conversation on iPhone.
 */
@interface OWSIncomingSentMessageTranscript : NSObject

- (nullable instancetype)initWithProto:(SSKProtoSyncMessageSent *)sentProto
                       serverTimestamp:(uint64_t)serverTimestamp
                           transaction:(SDSAnyWriteTransaction *)transaction;

@property (nonatomic, readonly, nullable) SignalServiceAddress *recipientAddress;
@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly) uint64_t dataMessageTimestamp;
@property (nonatomic, readonly) uint64_t serverTimestamp;
@property (nonatomic, readonly) uint64_t expirationStartedAt;
@property (nonatomic, readonly) uint32_t expirationDuration;
@property (nonatomic, readonly) BOOL isExpirationTimerUpdate;
@property (nonatomic, readonly) BOOL isEndSessionMessage;
@property (nonatomic, readonly, nullable) NSData *groupId;
@property (nonatomic, readonly, nullable) NSString *body;
@property (nonatomic, readonly, nullable) MessageBodyRanges *bodyRanges;
@property (nonatomic, readonly) NSArray<SSKProtoAttachmentPointer *> *attachmentPointerProtos;
@property (nonatomic, readonly, nullable) TSThread *thread;
@property (nonatomic, readonly, nullable) TSQuotedMessage *quotedMessage;
@property (nonatomic, readonly, nullable) OWSContact *contact;
@property (nonatomic, readonly, nullable) OWSLinkPreview *linkPreview;
@property (nonatomic, readonly, nullable) OWSGiftBadge *giftBadge;
@property (nonatomic, readonly, nullable) MessageSticker *messageSticker;
@property (nonatomic, readonly) BOOL isRecipientUpdate;
@property (nonatomic, readonly) BOOL isViewOnceMessage;
@property (nonatomic, readonly, nullable) TSPaymentNotification *paymentNotification;
@property (nonatomic, readonly, nullable) NSNumber *requiredProtocolVersion;
@property (nonatomic, readonly) DisappearingMessageToken *disappearingMessageToken;
@property (nonatomic, readonly, nullable) NSNumber *storyTimestamp;
@property (nonatomic, readonly, nullable) AciObjC *storyAuthorAci;

// If either nonUdRecipients or udRecipients is nil, this is either a
// legacy transcript or it reflects a legacy sync message.
@property (nonatomic, readonly, nullable) NSArray<ServiceIdObjC *> *nonUdRecipients;
@property (nonatomic, readonly, nullable) NSArray<ServiceIdObjC *> *udRecipients;

@end

NS_ASSUME_NONNULL_END
