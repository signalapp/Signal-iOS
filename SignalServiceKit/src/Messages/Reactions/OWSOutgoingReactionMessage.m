//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingReactionMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingReactionMessage ()

@property (nonatomic, readonly) TSMessage *message;
@property (nonatomic, readonly) NSString *emoji;
@property (nonatomic, readonly) BOOL isRemoving;

@end

#pragma mark -

@implementation OWSOutgoingReactionMessage

- (instancetype)initWithThread:(TSThread *)thread
                       message:(TSMessage *)message
                         emoji:(NSString *)emoji
                    isRemoving:(BOOL)isRemoving
{
    OWSAssertDebug(thread.uniqueId == message.uniqueThreadId);
    OWSAssertDebug(emoji.isSingleEmoji);

    // MJK TODO - remove senderTimestamp
    self = [super initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                          inThread:thread
                                       messageBody:nil
                                     attachmentIds:[NSMutableArray new]
                                  expiresInSeconds:0
                                   expireStartedAt:0
                                    isVoiceMessage:NO
                                  groupMetaMessage:TSGroupMetaMessageUnspecified
                                     quotedMessage:nil
                                      contactShare:nil
                                       linkPreview:nil
                                    messageSticker:nil
                                 isViewOnceMessage:NO];
    if (!self) {
        return self;
    }

    _message = message;
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
    SSKProtoDataMessageReactionBuilder *reactionBuilder = [SSKProtoDataMessageReaction builderWithEmoji:self.emoji
                                                                                                 remove:self.isRemoving
                                                                                              timestamp:self.message.timestamp];

    SignalServiceAddress *_Nullable messageAuthor;

    if ([self.message isKindOfClass:[TSOutgoingMessage class]]) {
        messageAuthor = TSAccountManager.sharedInstance.localAddress;
    } else if ([self.message isKindOfClass:[TSIncomingMessage class]]) {
        messageAuthor = ((TSIncomingMessage *)self.message).authorAddress;
    }

    if (!messageAuthor) {
        OWSFailDebug(@"message is missing author.");
        return nil;
    }

    if (messageAuthor.phoneNumber) {
        reactionBuilder.authorE164 = messageAuthor.phoneNumber;
    }

    if (messageAuthor.uuidString) {
        reactionBuilder.authorUuid = messageAuthor.uuidString;
    }

    NSError *error;
    SSKProtoDataMessageReaction *_Nullable reactionProto = [reactionBuilder buildAndReturnError:&error];
    if (error || !reactionProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoDataMessageBuilder *builder = [SSKProtoDataMessage builder];
    [builder setTimestamp:self.timestamp];
    [builder setReaction:reactionProto];

    return builder;
}

@end

NS_ASSUME_NONNULL_END
