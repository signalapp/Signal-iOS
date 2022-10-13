//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOutgoingNullMessage.h"
#import "OWSVerificationStateSyncMessage.h"
#import "TSContactThread.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingNullMessage ()

@property (nonatomic, nullable, readonly) OWSVerificationStateSyncMessage *verificationStateSyncMessage;

@end

#pragma mark -

@implementation OWSOutgoingNullMessage

- (instancetype)initWithContactThread:(TSContactThread *)contactThread transaction:(SDSAnyReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder =
        [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:contactThread];
    return [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];
}

- (instancetype)initWithContactThread:(TSContactThread *)contactThread
         verificationStateSyncMessage:(OWSVerificationStateSyncMessage *)verificationStateSyncMessage
                          transaction:(SDSAnyReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder =
        [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:contactThread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];
    if (!self) {
        return self;
    }
    
    _verificationStateSyncMessage = verificationStateSyncMessage;
    
    return self;
}

#pragma mark - override TSOutgoingMessage

- (nullable SSKProtoContentBuilder *)contentBuilderWithThread:(TSThread *)thread
                                                  transaction:(SDSAnyReadTransaction *)transaction
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

        nullMessageBuilder.padding = [Cryptography generateRandomBytes:contentLength];
    }

    NSError *error;
    SSKProtoNullMessage *_Nullable nullMessage = [nullMessageBuilder buildAndReturnError:&error];
    if (error || !nullMessage) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

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
