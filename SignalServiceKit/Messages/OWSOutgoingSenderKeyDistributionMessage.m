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
                          transaction:(DBReadTransaction *)transaction
{
    OWSAssertDebug(destinationThread);
    OWSAssertDebug(skdmBytes);
    if (!destinationThread || !skdmBytes) {
        return nil;
    }

    TSOutgoingMessageBuilder *messageBuilder =
        [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:destinationThread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder
                            additionalRecipients:@[]
                              explicitRecipients:@[]
                               skippedRecipients:@[]
                                     transaction:transaction];
    if (self) {
        _serializedSKDM = [skdmBytes copy];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:[self valueForKey:@"isSentOnBehalfOfOnlineMessage"] forKey:@"isSentOnBehalfOfOnlineMessage"];
    [coder encodeObject:[self valueForKey:@"isSentOnBehalfOfStoryMessage"] forKey:@"isSentOnBehalfOfStoryMessage"];
    NSData *serializedSKDM = self.serializedSKDM;
    if (serializedSKDM != nil) {
        [coder encodeObject:serializedSKDM forKey:@"serializedSKDM"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_isSentOnBehalfOfOnlineMessage =
        [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:@"isSentOnBehalfOfOnlineMessage"] boolValue];
    self->_isSentOnBehalfOfStoryMessage =
        [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:@"isSentOnBehalfOfStoryMessage"] boolValue];
    self->_serializedSKDM = [coder decodeObjectOfClass:[NSData class] forKey:@"serializedSKDM"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.isSentOnBehalfOfOnlineMessage;
    result ^= self.isSentOnBehalfOfStoryMessage;
    result ^= self.serializedSKDM.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSOutgoingSenderKeyDistributionMessage *typedOther = (OWSOutgoingSenderKeyDistributionMessage *)other;
    if (self.isSentOnBehalfOfOnlineMessage != typedOther.isSentOnBehalfOfOnlineMessage) {
        return NO;
    }
    if (self.isSentOnBehalfOfStoryMessage != typedOther.isSentOnBehalfOfStoryMessage) {
        return NO;
    }
    if (![NSObject isObject:self.serializedSKDM equalToObject:typedOther.serializedSKDM]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSOutgoingSenderKeyDistributionMessage *result = [super copyWithZone:zone];
    result->_isSentOnBehalfOfOnlineMessage = self.isSentOnBehalfOfOnlineMessage;
    result->_isSentOnBehalfOfStoryMessage = self.isSentOnBehalfOfStoryMessage;
    result->_serializedSKDM = self.serializedSKDM;
    return result;
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
                                                  transaction:(DBReadTransaction *)transaction
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
