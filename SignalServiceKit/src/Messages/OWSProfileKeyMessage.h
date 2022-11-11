//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSOutgoingMessage.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSProfileKeyMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder
                                   transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
           receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                        sortId:(uint64_t)sortId
                     timestamp:(uint64_t)timestamp
                uniqueThreadId:(NSString *)uniqueThreadId
                 attachmentIds:(NSArray<NSString *> *)attachmentIds
                          body:(nullable NSString *)body
                  contactShare:(nullable OWSContact *)contactShare
               expireStartedAt:(uint64_t)expireStartedAt
                     expiresAt:(uint64_t)expiresAt
              expiresInSeconds:(unsigned int)expiresInSeconds
            isViewOnceComplete:(BOOL)isViewOnceComplete
             isViewOnceMessage:(BOOL)isViewOnceMessage
                   linkPreview:(nullable OWSLinkPreview *)linkPreview
                messageSticker:(nullable MessageSticker *)messageSticker
                 quotedMessage:(nullable TSQuotedMessage *)quotedMessage
  storedShouldStartExpireTimer:(BOOL)storedShouldStartExpireTimer
                 customMessage:(nullable NSString *)customMessage
              groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
         hasLegacyMessageState:(BOOL)hasLegacyMessageState
           hasSyncedTranscript:(BOOL)hasSyncedTranscript
            isFromLinkedDevice:(BOOL)isFromLinkedDevice
                isVoiceMessage:(BOOL)isVoiceMessage
            legacyMessageState:(TSOutgoingMessageState)legacyMessageState
            legacyWasDelivered:(BOOL)legacyWasDelivered
         mostRecentFailureText:(nullable NSString *)mostRecentFailureText
        recipientAddressStates:(nullable NSDictionary<SignalServiceAddress *,TSOutgoingMessageRecipientState *> *)recipientAddressStates
            storedMessageState:(TSOutgoingMessageState)storedMessageState NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                   transaction:(SDSAnyReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
