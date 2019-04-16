//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSentMessageTranscript.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSOutgoingMessage (OWSOutgoingSentMessageTranscript)

/**
 * Normally this is private, but we need to embed this
 * data structure within our own.
 *
 * recipientId is nil when building "sent" sync messages for messages
 * sent to groups.
 */
- (nullable SSKProtoDataMessage *)buildDataMessage:(NSString *_Nullable)recipientId;

@end

#pragma mark -

@interface OWSOutgoingSentMessageTranscript ()

@property (nonatomic, readonly) TSOutgoingMessage *message;

// sentRecipientId is the recipient of message, for contact thread messages.
// It is used to identify the thread/conversation to desktop.
@property (nonatomic, readonly, nullable) NSString *sentRecipientId;

@property (nonatomic, readonly) BOOL isRecipientUpdate;

@end

#pragma mark -

@implementation OWSOutgoingSentMessageTranscript

- (instancetype)initWithOutgoingMessage:(TSOutgoingMessage *)message isRecipientUpdate:(BOOL)isRecipientUpdate
{
    self = [super init];

    if (!self) {
        return self;
    }

    _message = message;
    // This will be nil for groups.
    _sentRecipientId = message.thread.contactIdentifier;
    _isRecipientUpdate = isRecipientUpdate;

    return self;
}

- (instancetype)initWithUniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(unsigned long long)receivedAtTimestamp
                          sortId:(unsigned long long)sortId
                       timestamp:(unsigned long long)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
                   attachmentIds:(NSArray<NSString *> *)attachmentIds
                            body:(nullable NSString *)body
                    contactShare:(nullable OWSContact *)contactShare
                 expireStartedAt:(unsigned long long)expireStartedAt
                       expiresAt:(unsigned long long)expiresAt
                expiresInSeconds:(unsigned int)expiresInSeconds
                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                   schemaVersion:(NSUInteger)schemaVersion
           attachmentFilenameMap:(NSDictionary<NSString *, NSString *> *)attachmentFilenameMap
                   customMessage:(nullable NSString *)customMessage
                groupMetaMessage:(enum TSGroupMetaMessage)groupMetaMessage
           hasLegacyMessageState:(BOOL)hasLegacyMessageState
             hasSyncedTranscript:(BOOL)hasSyncedTranscript
              isFromLinkedDevice:(BOOL)isFromLinkedDevice
                  isVoiceMessage:(BOOL)isVoiceMessage
              legacyMessageState:(enum TSOutgoingMessageState)legacyMessageState
              legacyWasDelivered:(BOOL)legacyWasDelivered
           mostRecentFailureText:(nullable NSString *)mostRecentFailureText
               recipientStateMap:
                   (nullable NSDictionary<NSString *, TSOutgoingMessageRecipientState *> *)recipientStateMap
               isRecipientUpdate:(BOOL)isRecipientUpdate
                         message:(TSOutgoingMessage *)message
                 sentRecipientId:(nullable NSString *)sentRecipientId
{
    self = [super initWithUniqueId:uniqueId
               receivedAtTimestamp:receivedAtTimestamp
                            sortId:sortId
                         timestamp:timestamp
                    uniqueThreadId:uniqueThreadId
                     attachmentIds:attachmentIds
                              body:body
                      contactShare:contactShare
                   expireStartedAt:expireStartedAt
                         expiresAt:expiresAt
                  expiresInSeconds:expiresInSeconds
                       linkPreview:linkPreview
                     quotedMessage:quotedMessage
                     schemaVersion:schemaVersion
             attachmentFilenameMap:attachmentFilenameMap
                     customMessage:customMessage
                  groupMetaMessage:groupMetaMessage
             hasLegacyMessageState:hasLegacyMessageState
               hasSyncedTranscript:hasSyncedTranscript
                isFromLinkedDevice:isFromLinkedDevice
                    isVoiceMessage:isVoiceMessage
                legacyMessageState:legacyMessageState
                legacyWasDelivered:legacyWasDelivered
             mostRecentFailureText:mostRecentFailureText
                 recipientStateMap:recipientStateMap];

    if (!self) {
        return self;
    }

    _message = message;
    _sentRecipientId = sentRecipientId;
    _isRecipientUpdate = isRecipientUpdate;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    SSKProtoSyncMessageSentBuilder *sentBuilder = [SSKProtoSyncMessageSent builder];
    [sentBuilder setTimestamp:self.message.timestamp];
    [sentBuilder setDestination:self.sentRecipientId];
    [sentBuilder setIsRecipientUpdate:self.isRecipientUpdate];

    SSKProtoDataMessage *_Nullable dataMessage = [self.message buildDataMessage:self.sentRecipientId];
    if (!dataMessage) {
        OWSFailDebug(@"could not build protobuf.");
        return nil;
    }
    [sentBuilder setMessage:dataMessage];
    [sentBuilder setExpirationStartTimestamp:self.message.timestamp];

    for (NSString *recipientId in self.message.sentRecipientIds) {
        TSOutgoingMessageRecipientState *_Nullable recipientState =
            [self.message recipientStateForRecipientId:recipientId];
        if (!recipientState) {
            OWSFailDebug(@"missing recipient state for: %@", recipientId);
            continue;
        }
        if (recipientState.state != OWSOutgoingMessageRecipientStateSent) {
            OWSFailDebug(@"unexpected recipient state for: %@", recipientId);
            continue;
        }

        NSError *error;
        SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder *statusBuilder =
            [SSKProtoSyncMessageSentUnidentifiedDeliveryStatus builder];
        [statusBuilder setDestination:recipientId];
        [statusBuilder setUnidentified:recipientState.wasSentByUD];
        SSKProtoSyncMessageSentUnidentifiedDeliveryStatus *_Nullable status =
            [statusBuilder buildAndReturnError:&error];
        if (error || !status) {
            OWSFailDebug(@"Couldn't build UD status proto: %@", error);
            continue;
        }
        [sentBuilder addUnidentifiedStatus:status];
    }

    NSError *error;
    SSKProtoSyncMessageSent *_Nullable sentProto = [sentBuilder buildAndReturnError:&error];
    if (error || !sentProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setSent:sentProto];
    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
