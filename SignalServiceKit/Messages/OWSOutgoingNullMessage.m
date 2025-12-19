//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOutgoingNullMessage.h"
#import "OWSVerificationStateSyncMessage.h"
#import "TSContactThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingNullMessage ()

@property (nonatomic, nullable, readonly) OWSVerificationStateSyncMessage *verificationStateSyncMessage;

@end

#pragma mark -

@implementation OWSOutgoingNullMessage

- (instancetype)initWithContactThread:(TSContactThread *)contactThread transaction:(DBReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder =
        [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:contactThread];
    return [super initOutgoingMessageWithBuilder:messageBuilder
                            additionalRecipients:@[]
                              explicitRecipients:@[]
                               skippedRecipients:@[]
                                     transaction:transaction];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    OWSVerificationStateSyncMessage *verificationStateSyncMessage = self.verificationStateSyncMessage;
    if (verificationStateSyncMessage != nil) {
        [coder encodeObject:verificationStateSyncMessage forKey:@"verificationStateSyncMessage"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_verificationStateSyncMessage = [coder decodeObjectOfClass:[OWSVerificationStateSyncMessage class]
                                                              forKey:@"verificationStateSyncMessage"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.verificationStateSyncMessage.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSOutgoingNullMessage *typedOther = (OWSOutgoingNullMessage *)other;
    if (![NSObject isObject:self.verificationStateSyncMessage equalToObject:typedOther.verificationStateSyncMessage]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSOutgoingNullMessage *result = [super copyWithZone:zone];
    result->_verificationStateSyncMessage = self.verificationStateSyncMessage;
    return result;
}

- (instancetype)initWithContactThread:(TSContactThread *)contactThread
         verificationStateSyncMessage:(OWSVerificationStateSyncMessage *)verificationStateSyncMessage
                          transaction:(DBReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder =
        [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:contactThread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder
                            additionalRecipients:@[]
                              explicitRecipients:@[]
                               skippedRecipients:@[]
                                     transaction:transaction];
    if (!self) {
        return self;
    }

    _verificationStateSyncMessage = verificationStateSyncMessage;

    return self;
}

#pragma mark - override TSOutgoingMessage

- (nullable SSKProtoContentBuilder *)contentBuilderWithThread:(TSThread *)thread
                                                  transaction:(DBReadTransaction *)transaction
{
    SSKProtoNullMessageBuilder *nullMessageBuilder = [SSKProtoNullMessage builder];

    if (self.verificationStateSyncMessage) {
        NSUInteger contentLength = self.verificationStateSyncMessage.unpaddedVerifiedLength;

        OWSAssertDebug(self.verificationStateSyncMessage.paddingBytesLength > 0);

        // We add the same amount of padding in the VerificationStateSync message and it's corresponding NullMessage so
        // that the sync message is indistinguishable from an outgoing Sent transcript corresponding to the NullMessage.
        // We pad the NullMessage so as to obscure it's content. The sync message (like all sync messages) will be
        // *additionally* padded by the superclass while being sent. The end result is we send a NullMessage of a
        // non-distinct size, and a verification sync which is ~1-512 bytes larger then that.
        contentLength += self.verificationStateSyncMessage.paddingBytesLength;

        OWSAssertDebug(contentLength > 0);

        nullMessageBuilder.padding = [Randomness generateRandomBytes:contentLength];
    }

    SSKProtoNullMessage *nullMessage = [nullMessageBuilder buildInfallibly];

    SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
    contentBuilder.nullMessage = nullMessage;
    return contentBuilder;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (SealedSenderContentHint)contentHint
{
    return SealedSenderContentHintImplicit;
}

@end

NS_ASSUME_NONNULL_END
