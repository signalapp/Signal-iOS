//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingDeleteMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSOutgoingDeleteMessage ()

@property (nonatomic, readonly) uint64_t messageTimestamp;
@property (nonatomic, readonly, nullable) NSString *messageUniqueId;

@end

#pragma mark -

@implementation TSOutgoingDeleteMessage

- (instancetype)initWithThread:(TSThread *)thread
                       message:(TSOutgoingMessage *)message
                   transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug([thread.uniqueId isEqualToString:message.uniqueThreadId]);

    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];
    if (!self) {
        return self;
    }

    _messageTimestamp = message.timestamp;
    _messageUniqueId = message.uniqueId;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread
                  storyMessage:(StoryMessage *)storyMessage
             skippedRecipients:(nullable NSSet<SignalServiceAddress *> *)skippedRecipients
                   transaction:(SDSAnyReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    messageBuilder.skippedRecipients = skippedRecipients;
    self = [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];
    if (!self) {
        return self;
    }

    _messageTimestamp = storyMessage.timestamp;
    _messageUniqueId = storyMessage.uniqueId;

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(SDSAnyReadTransaction *)transaction
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

- (void)anyUpdateOutgoingMessageWithTransaction:(SDSAnyWriteTransaction *)transaction
                                          block:(void(NS_NOESCAPE ^)(TSOutgoingMessage *_Nonnull))block
{
    [super anyUpdateOutgoingMessageWithTransaction:transaction block:block];

    // Some older outgoing delete messages didn't store the deleted message's unique id.
    // We want to mirror our sending state onto the original message, so it shows up
    // within the conversation.
    if (self.messageUniqueId) {
        TSOutgoingMessage *deletedMessage = [TSOutgoingMessage anyFetchOutgoingMessageWithUniqueId:self.messageUniqueId
                                                                                       transaction:transaction];
        [deletedMessage updateWithRecipientAddressStates:self.recipientAddressStates transaction:transaction];
    }
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    return [[super relatedUniqueIds] setByAddingObjectsFromArray:@[ self.messageUniqueId ]];
}

@end

NS_ASSUME_NONNULL_END
