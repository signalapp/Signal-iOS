//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSPaymentActivationRequestMessage.h"
#import "ProfileManagerProtocol.h"
#import "ProtoUtils.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSPaymentActivationRequestMessage

- (instancetype)initWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    return [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];
}

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoDataMessageBuilder *builder = [super dataMessageBuilderWithThread:thread transaction:transaction];

    SSKProtoDataMessagePaymentActivationBuilder *activationBuilder = [SSKProtoDataMessagePaymentActivation builder];
    [activationBuilder setType:SSKProtoDataMessagePaymentActivationTypeRequest];
    NSError *error;
    SSKProtoDataMessagePaymentActivation *activation = [activationBuilder buildAndReturnError:&error];
    if (error || !activation) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoDataMessagePaymentBuilder *paymentBuilder = [SSKProtoDataMessagePayment builder];
    [paymentBuilder setActivation:activation];
    SSKProtoDataMessagePayment *payment = [paymentBuilder buildAndReturnError:&error];
    if (error || !payment) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    [builder setPayment:payment];

    [builder setRequiredProtocolVersion:(uint32_t)SSKProtoDataMessageProtocolVersionPayments];
    return builder;
}

- (instancetype)initWithGrdbId:(int64_t)grdbId
                        uniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          sortId:(uint64_t)sortId
                       timestamp:(uint64_t)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
                   attachmentIds:(NSArray<NSString *> *)attachmentIds
                            body:(nullable NSString *)body
                      bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                    contactShare:(nullable OWSContact *)contactShare
                       editState:(TSEditState)editState
                 expireStartedAt:(uint64_t)expireStartedAt
                       expiresAt:(uint64_t)expiresAt
                expiresInSeconds:(unsigned int)expiresInSeconds
                       giftBadge:(nullable OWSGiftBadge *)giftBadge
               isGroupStoryReply:(BOOL)isGroupStoryReply
              isViewOnceComplete:(BOOL)isViewOnceComplete
               isViewOnceMessage:(BOOL)isViewOnceMessage
                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                  messageSticker:(nullable MessageSticker *)messageSticker
                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
    storedShouldStartExpireTimer:(BOOL)storedShouldStartExpireTimer
           storyAuthorUuidString:(nullable NSString *)storyAuthorUuidString
              storyReactionEmoji:(nullable NSString *)storyReactionEmoji
                  storyTimestamp:(nullable NSNumber *)storyTimestamp
              wasRemotelyDeleted:(BOOL)wasRemotelyDeleted
                   customMessage:(nullable NSString *)customMessage
                groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
           hasLegacyMessageState:(BOOL)hasLegacyMessageState
             hasSyncedTranscript:(BOOL)hasSyncedTranscript
            wasNotCreatedLocally:(BOOL)wasNotCreatedLocally
                  isVoiceMessage:(BOOL)isVoiceMessage
              legacyMessageState:(TSOutgoingMessageState)legacyMessageState
              legacyWasDelivered:(BOOL)legacyWasDelivered
           mostRecentFailureText:(nullable NSString *)mostRecentFailureText
          recipientAddressStates:
              (nullable NSDictionary<SignalServiceAddress *, TSOutgoingMessageRecipientState *> *)recipientAddressStates
              storedMessageState:(TSOutgoingMessageState)storedMessageState
{
    self = [super initWithGrdbId:grdbId
                            uniqueId:uniqueId
                 receivedAtTimestamp:receivedAtTimestamp
                              sortId:sortId
                           timestamp:timestamp
                      uniqueThreadId:uniqueThreadId
                       attachmentIds:attachmentIds
                                body:body
                          bodyRanges:bodyRanges
                        contactShare:contactShare
                           editState:editState
                     expireStartedAt:expireStartedAt
                           expiresAt:expiresAt
                    expiresInSeconds:expiresInSeconds
                           giftBadge:giftBadge
                   isGroupStoryReply:isGroupStoryReply
                  isViewOnceComplete:isViewOnceComplete
                   isViewOnceMessage:isViewOnceMessage
                         linkPreview:linkPreview
                      messageSticker:messageSticker
                       quotedMessage:quotedMessage
        storedShouldStartExpireTimer:storedShouldStartExpireTimer
               storyAuthorUuidString:storyAuthorUuidString
                  storyReactionEmoji:storyReactionEmoji
                      storyTimestamp:storyTimestamp
                  wasRemotelyDeleted:wasRemotelyDeleted
                       customMessage:customMessage
                    groupMetaMessage:groupMetaMessage
               hasLegacyMessageState:hasLegacyMessageState
                 hasSyncedTranscript:hasSyncedTranscript
                      isVoiceMessage:isVoiceMessage
                  legacyMessageState:legacyMessageState
                  legacyWasDelivered:legacyWasDelivered
               mostRecentFailureText:mostRecentFailureText
              recipientAddressStates:recipientAddressStates
                  storedMessageState:storedMessageState
                wasNotCreatedLocally:wasNotCreatedLocally];

    return self;
}

- (SealedSenderContentHint)contentHint
{
    return SealedSenderContentHintImplicit;
}

- (BOOL)hasRenderableContent
{
    return NO;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
