//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSOutgoingMessage;

/**
 * Notifies your other registered devices (if you have any) that you've sent a message.
 * This way the message you just sent can appear on all your devices.
 */
@interface OWSOutgoingSentMessageTranscript : OWSOutgoingSyncMessage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithOutgoingMessage:(TSOutgoingMessage *)message
                      isRecipientUpdate:(BOOL)isRecipientUpdate NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

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
           attachmentFilenameMap:(NSDictionary<NSString *,NSString *> *)attachmentFilenameMap
                   customMessage:(nullable NSString *)customMessage
                groupMetaMessage:(enum TSGroupMetaMessage)groupMetaMessage
           hasLegacyMessageState:(BOOL)hasLegacyMessageState
             hasSyncedTranscript:(BOOL)hasSyncedTranscript
              isFromLinkedDevice:(BOOL)isFromLinkedDevice
                  isVoiceMessage:(BOOL)isVoiceMessage
              legacyMessageState:(enum TSOutgoingMessageState)legacyMessageState
              legacyWasDelivered:(BOOL)legacyWasDelivered
           mostRecentFailureText:(nullable NSString *)mostRecentFailureText
               recipientStateMap:(nullable NSDictionary<NSString *,TSOutgoingMessageRecipientState *> *)recipientStateMap
               isRecipientUpdate:(BOOL)isRecipientUpdate
                         message:(TSOutgoingMessage *)message
                 sentRecipientId:(nullable NSString *)sentRecipientId
NS_DESIGNATED_INITIALIZER
NS_SWIFT_NAME(init(uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:attachmentIds:body:contactShare:expireStartedAt:expiresAt:expiresInSeconds:linkPreview:quotedMessage:schemaVersion:attachmentFilenameMap:customMessage:groupMetaMessage:hasLegacyMessageState:hasSyncedTranscript:isFromLinkedDevice:isVoiceMessage:legacyMessageState:legacyWasDelivered:mostRecentFailureText:recipientStateMap:isRecipientUpdate:message:sentRecipientId:));

@end

NS_ASSUME_NONNULL_END
