//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSOutgoingDeleteMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSOutgoingDeleteMessage ()

@property (nonatomic, readonly) uint64_t messageTimestamp;
@property (nonatomic, readonly, nullable) NSString *messageUniqueId;
@property (nonatomic, readonly) BOOL isDeletingStoryMessage;

@end

#pragma mark -

@implementation TSOutgoingDeleteMessage

- (instancetype)initWithThread:(TSThread *)thread
                       message:(TSOutgoingMessage *)message
                   transaction:(DBReadTransaction *)transaction
{
    OWSAssertDebug([thread.uniqueId isEqualToString:message.uniqueThreadId]);

    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder
                            additionalRecipients:@[]
                              explicitRecipients:@[]
                               skippedRecipients:@[]
                                     transaction:transaction];
    if (!self) {
        return self;
    }

    _messageTimestamp = message.timestamp;
    _messageUniqueId = message.uniqueId;
    _isDeletingStoryMessage = NO;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:[self valueForKey:@"isDeletingStoryMessage"] forKey:@"isDeletingStoryMessage"];
    [coder encodeObject:[self valueForKey:@"messageTimestamp"] forKey:@"messageTimestamp"];
    NSString *messageUniqueId = self.messageUniqueId;
    if (messageUniqueId != nil) {
        [coder encodeObject:messageUniqueId forKey:@"messageUniqueId"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_isDeletingStoryMessage = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                                     forKey:@"isDeletingStoryMessage"] boolValue];
    self->_messageTimestamp = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                               forKey:@"messageTimestamp"] unsignedLongLongValue];
    self->_messageUniqueId = [coder decodeObjectOfClass:[NSString class] forKey:@"messageUniqueId"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.isDeletingStoryMessage;
    result ^= self.messageTimestamp;
    result ^= self.messageUniqueId.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    TSOutgoingDeleteMessage *typedOther = (TSOutgoingDeleteMessage *)other;
    if (self.isDeletingStoryMessage != typedOther.isDeletingStoryMessage) {
        return NO;
    }
    if (self.messageTimestamp != typedOther.messageTimestamp) {
        return NO;
    }
    if (![NSObject isObject:self.messageUniqueId equalToObject:typedOther.messageUniqueId]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TSOutgoingDeleteMessage *result = [super copyWithZone:zone];
    result->_isDeletingStoryMessage = self.isDeletingStoryMessage;
    result->_messageTimestamp = self.messageTimestamp;
    result->_messageUniqueId = self.messageUniqueId;
    return result;
}

- (instancetype)initWithThread:(TSThread *)thread
                  storyMessage:(StoryMessage *)storyMessage
             skippedRecipients:(NSArray<ServiceIdObjC *> *)skippedRecipients
                   transaction:(DBReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder
                            additionalRecipients:@[]
                              explicitRecipients:@[]
                               skippedRecipients:skippedRecipients
                                     transaction:transaction];
    if (!self) {
        return self;
    }

    _messageTimestamp = storyMessage.timestamp;
    _messageUniqueId = storyMessage.uniqueId;
    _isDeletingStoryMessage = YES;

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (BOOL)isStorySend
{
    return self.isDeletingStoryMessage;
}

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(DBReadTransaction *)transaction
{
    SSKProtoDataMessageDeleteBuilder *deleteBuilder =
        [SSKProtoDataMessageDelete builderWithTargetSentTimestamp:self.messageTimestamp];

    NSError *error;
    SSKProtoDataMessageDelete *_Nullable deleteProto = [deleteBuilder buildAndReturnError:&error];
    if (error || !deleteProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoDataMessageBuilder *builder = [super dataMessageBuilderWithThread:thread transaction:transaction];
    [builder setTimestamp:self.timestamp];
    [builder setDelete:deleteProto];

    return builder;
}

- (void)anyUpdateOutgoingMessageWithTransaction:(DBWriteTransaction *)transaction
                                          block:(void(NS_NOESCAPE ^)(TSOutgoingMessage *_Nonnull))block
{
    [super anyUpdateOutgoingMessageWithTransaction:transaction block:block];

    // Some older outgoing delete messages didn't store the deleted message's unique id.
    // We want to mirror our sending state onto the original message, so it shows up
    // within the conversation.
    if (self.messageUniqueId) {
        TSOutgoingMessage *deletedMessage = [TSOutgoingMessage anyFetchOutgoingMessageWithUniqueId:self.messageUniqueId
                                                                                       transaction:transaction];
        [deletedMessage updateWithRecipientAddressStates:self.recipientAddressStates tx:transaction];
    }
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    return [[super relatedUniqueIds] setByAddingObjectsFromArray:@[ self.messageUniqueId ]];
}

@end

NS_ASSUME_NONNULL_END
