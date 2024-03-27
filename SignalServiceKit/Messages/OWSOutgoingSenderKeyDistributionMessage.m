//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOutgoingSenderKeyDistributionMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface OWSOutgoingSenderKeyDistributionMessage ()
@property (strong, nonatomic, readonly) NSData *serializedSKDM;
@property (assign, atomic) BOOL isSentOnBehalfOfOnlineMessage;
@property (assign, atomic) BOOL isSentOnBehalfOfStoryMessage;
@end

@implementation OWSOutgoingSenderKeyDistributionMessage

- (instancetype)initWithThread:(TSContactThread *)destinationThread
    senderKeyDistributionMessageBytes:(NSData *)skdmBytes
                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(destinationThread);
    OWSAssertDebug(skdmBytes);
    if (!destinationThread || !skdmBytes) {
        return nil;
    }

    TSOutgoingMessageBuilder *messageBuilder =
        [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:destinationThread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];
    if (self) {
        _serializedSKDM = [skdmBytes copy];
    }
    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (BOOL)isUrgent
{
    return NO;
}

- (BOOL)isStorySend
{
    return self.isSentOnBehalfOfStoryMessage;
}

- (SealedSenderContentHint)contentHint
{
    return SealedSenderContentHintImplicit;
}

- (nullable SSKProtoContentBuilder *)contentBuilderWithThread:(TSThread *)thread
                                                  transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoContentBuilder *builder = [SSKProtoContent builder];
    [builder setSenderKeyDistributionMessage:self.serializedSKDM];
    return builder;
}

- (void)configureAsSentOnBehalfOf:(TSOutgoingMessage *)message inThread:(TSThread *)thread
{
    self.isSentOnBehalfOfOnlineMessage = message.isOnline;
    self.isSentOnBehalfOfStoryMessage = message.isStorySend && !thread.isGroupThread;
}

@end
