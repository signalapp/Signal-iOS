//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSContact;
@class OWSLinkPreview;
@class SSKProtoAttachmentPointer;
@class SSKProtoDataMessage;
@class SSKProtoSyncMessageSent;
@class TSQuotedMessage;
@class TSThread;
@class YapDatabaseReadWriteTransaction;

/**
 * Represents notification of a message sent on our behalf from another device.
 * E.g. When we send a message from Signal-Desktop we want to see it in our conversation on iPhone.
 */
@interface OWSIncomingSentMessageTranscript : NSObject

- (instancetype)initWithProto:(SSKProtoSyncMessageSent *)sentProto
                  transaction:(YapDatabaseReadWriteTransaction *)transaction;

@property (nonatomic, readonly) SSKProtoDataMessage *dataMessage;
@property (nonatomic, readonly) NSString *recipientId;
@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly) uint64_t expirationStartedAt;
@property (nonatomic, readonly) uint32_t expirationDuration;
@property (nonatomic, readonly) BOOL isGroupUpdate;
@property (nonatomic, readonly) BOOL isExpirationTimerUpdate;
@property (nonatomic, readonly) BOOL isEndSessionMessage;
@property (nonatomic, readonly, nullable) NSData *groupId;
@property (nonatomic, readonly) NSString *body;
@property (nonatomic, readonly) NSArray<SSKProtoAttachmentPointer *> *attachmentPointerProtos;
@property (nonatomic, readonly, nullable) TSThread *thread;
@property (nonatomic, readonly, nullable) TSQuotedMessage *quotedMessage;
@property (nonatomic, readonly, nullable) OWSContact *contact;
@property (nonatomic, readonly, nullable) OWSLinkPreview *linkPreview;
@property (nonatomic, readonly) BOOL isRecipientUpdate;

// If either nonUdRecipientIds or udRecipientIds is nil,
// this is either a legacy transcript or it reflects a legacy sync message.
@property (nonatomic, readonly, nullable) NSArray<NSString *> *nonUdRecipientIds;
@property (nonatomic, readonly, nullable) NSArray<NSString *> *udRecipientIds;

@end

NS_ASSUME_NONNULL_END
