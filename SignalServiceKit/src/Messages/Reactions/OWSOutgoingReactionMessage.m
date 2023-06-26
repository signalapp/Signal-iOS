//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOutgoingReactionMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingReactionMessage ()

@property (nonatomic, readonly) NSString *messageUniqueId;
@property (nonatomic, readonly) NSString *emoji;
@property (nonatomic, readonly) BOOL isRemoving;

@end

#pragma mark -

@implementation OWSOutgoingReactionMessage

- (instancetype)initWithThread:(TSThread *)thread
                       message:(TSMessage *)message
                         emoji:(NSString *)emoji
                    isRemoving:(BOOL)isRemoving
              expiresInSeconds:(uint32_t)expiresInSeconds
                   transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug([thread.uniqueId isEqualToString:message.uniqueThreadId]);
    OWSAssertDebug(emoji.isSingleEmoji);

    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    messageBuilder.expiresInSeconds = expiresInSeconds;
    self = [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];
    if (!self) {
        return self;
    }

    _messageUniqueId = message.uniqueId;
    _emoji = emoji;
    _isRemoving = isRemoving;

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(SDSAnyReadTransaction *)transaction
{
    TSMessage *_Nullable message = [TSMessage anyFetchMessageWithUniqueId:self.messageUniqueId transaction:transaction];
    if (!message) {
        OWSFailDebug(@"unexpectedly missing message for reaction");
        return nil;
    }

    SSKProtoDataMessageReactionBuilder *reactionBuilder =
        [SSKProtoDataMessageReaction builderWithEmoji:self.emoji timestamp:message.timestamp];
    [reactionBuilder setRemove:self.isRemoving];

    SignalServiceAddress *_Nullable messageAuthor;

    if ([message isKindOfClass:[TSOutgoingMessage class]]) {
        messageAuthor = TSAccountManager.shared.localAddress;
    } else if ([message isKindOfClass:[TSIncomingMessage class]]) {
        messageAuthor = ((TSIncomingMessage *)message).authorAddress;
    }

    if (!messageAuthor) {
        OWSFailDebug(@"message is missing author.");
        return nil;
    }

    if (messageAuthor.uuidString) {
        reactionBuilder.authorUuid = messageAuthor.uuidString;
    } else {
        OWSAssertDebug(!SSKFeatureFlags.phoneNumberSharing);
    }

    NSError *error;
    SSKProtoDataMessageReaction *_Nullable reactionProto = [reactionBuilder buildAndReturnError:&error];
    if (error || !reactionProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoDataMessageBuilder *builder = [super dataMessageBuilderWithThread:thread transaction:transaction];
    [builder setTimestamp:self.timestamp];
    [builder setReaction:reactionProto];
    [builder setRequiredProtocolVersion:SSKProtoDataMessageProtocolVersionReactions];

    return builder;
}

- (void)updateWithSendingError:(NSError *)error transaction:(SDSAnyWriteTransaction *)transaction
{
    [super updateWithSendingError:error transaction:transaction];

    // Do nothing if we successfully delivered to anyone. Only cleanup
    // local state if we fail to deliver to anyone.
    if (self.sentRecipientAddresses.count > 0) {
        OWSLogError(@"Failed to send reaction to some recipients: %@", error.userErrorDescription);
        return;
    }

    NSUUID *_Nullable localUuid = TSAccountManager.shared.localUuid;
    if (!localUuid) {
        OWSFailDebug(@"unexpectedly missing local address");
        return;
    }
    ServiceIdObjC *localAci = [[ServiceIdObjC alloc] initWithUuidValue:localUuid];

    TSMessage *_Nullable message = [TSMessage anyFetchMessageWithUniqueId:self.messageUniqueId transaction:transaction];
    if (!message) {
        OWSFailDebug(@"unexpectedly missing message for reaction");
        return;
    }

    OWSLogError(@"Failed to send reaction to all recipients: %@", error.userErrorDescription);

    OWSReaction *_Nullable currentReaction = [message reactionFor:localAci tx:transaction];

    if (![NSString isNullableObject:currentReaction.uniqueId equalTo:self.createdReaction.uniqueId]) {
        OWSLogInfo(@"Skipping reversion, changes have been made since we tried to send this message.");
        return;
    }

    if (self.previousReaction) {
        [message recordReactionFor:localAci
                             emoji:self.previousReaction.emoji
                   sentAtTimestamp:self.previousReaction.sentAtTimestamp
               receivedAtTimestamp:self.previousReaction.receivedAtTimestamp
                                tx:transaction];
    } else {
        [message removeReactionFor:localAci tx:transaction];
    }
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    return [[super relatedUniqueIds] setByAddingObjectsFromArray:@[ self.messageUniqueId ]];
}

@end

NS_ASSUME_NONNULL_END
