//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOutgoingReactionMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSOutgoingReactionMessage

- (instancetype)initWithThread:(TSThread *)thread
                       message:(TSMessage *)message
                         emoji:(NSString *)emoji
                    isRemoving:(BOOL)isRemoving
              expiresInSeconds:(uint32_t)expiresInSeconds
            expireTimerVersion:(nullable NSNumber *)expireTimerVersion
                   transaction:(DBReadTransaction *)transaction
{
    OWSAssertDebug([thread.uniqueId isEqualToString:message.uniqueThreadId]);
    OWSAssertDebug(emoji.isSingleEmoji);

    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    messageBuilder.expiresInSeconds = expiresInSeconds;
    messageBuilder.expireTimerVersion = expireTimerVersion;
    self = [super initOutgoingMessageWithBuilder:messageBuilder
                            additionalRecipients:@[]
                              explicitRecipients:@[]
                               skippedRecipients:@[]
                                     transaction:transaction];
    if (!self) {
        return self;
    }

    _messageUniqueId = message.uniqueId;
    _emoji = emoji;
    _isRemoving = isRemoving;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    OWSReaction *createdReaction = self.createdReaction;
    if (createdReaction != nil) {
        [coder encodeObject:createdReaction forKey:@"createdReaction"];
    }
    NSString *emoji = self.emoji;
    if (emoji != nil) {
        [coder encodeObject:emoji forKey:@"emoji"];
    }
    [coder encodeObject:[self valueForKey:@"isRemoving"] forKey:@"isRemoving"];
    NSString *messageUniqueId = self.messageUniqueId;
    if (messageUniqueId != nil) {
        [coder encodeObject:messageUniqueId forKey:@"messageUniqueId"];
    }
    OWSReaction *previousReaction = self.previousReaction;
    if (previousReaction != nil) {
        [coder encodeObject:previousReaction forKey:@"previousReaction"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_createdReaction = [coder decodeObjectOfClass:[OWSReaction class] forKey:@"createdReaction"];
    self->_emoji = [coder decodeObjectOfClass:[NSString class] forKey:@"emoji"];
    self->_isRemoving = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:@"isRemoving"] boolValue];
    self->_messageUniqueId = [coder decodeObjectOfClass:[NSString class] forKey:@"messageUniqueId"];
    self->_previousReaction = [coder decodeObjectOfClass:[OWSReaction class] forKey:@"previousReaction"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.createdReaction.hash;
    result ^= self.emoji.hash;
    result ^= self.isRemoving;
    result ^= self.messageUniqueId.hash;
    result ^= self.previousReaction.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSOutgoingReactionMessage *typedOther = (OWSOutgoingReactionMessage *)other;
    if (![NSObject isObject:self.createdReaction equalToObject:typedOther.createdReaction]) {
        return NO;
    }
    if (![NSObject isObject:self.emoji equalToObject:typedOther.emoji]) {
        return NO;
    }
    if (self.isRemoving != typedOther.isRemoving) {
        return NO;
    }
    if (![NSObject isObject:self.messageUniqueId equalToObject:typedOther.messageUniqueId]) {
        return NO;
    }
    if (![NSObject isObject:self.previousReaction equalToObject:typedOther.previousReaction]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSOutgoingReactionMessage *result = [super copyWithZone:zone];
    result->_createdReaction = self.createdReaction;
    result->_emoji = self.emoji;
    result->_isRemoving = self.isRemoving;
    result->_messageUniqueId = self.messageUniqueId;
    result->_previousReaction = self.previousReaction;
    return result;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(DBReadTransaction *)transaction
{
    SSKProtoDataMessageReaction *_Nullable reactionProto = [self buildDataMessageReactionProtoWithTx:transaction];
    if (!reactionProto) {
        return nil;
    }

    SSKProtoDataMessageBuilder *builder = [super dataMessageBuilderWithThread:thread transaction:transaction];
    [builder setTimestamp:self.timestamp];
    [builder setReaction:reactionProto];
    [builder setRequiredProtocolVersion:SSKProtoDataMessageProtocolVersionReactions];

    return builder;
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    return [[super relatedUniqueIds] setByAddingObjectsFromArray:@[ self.messageUniqueId ]];
}

@end

NS_ASSUME_NONNULL_END
