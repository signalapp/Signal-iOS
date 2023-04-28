//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSProfileKeyMessage.h"
#import "ProfileManagerProtocol.h"
#import "ProtoUtils.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSProfileKeyMessage

- (instancetype)initWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    return [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (nullable SSKProtoDataMessage *)buildDataMessage:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread != nil);

    SSKProtoDataMessageBuilder *_Nullable builder = [self dataMessageBuilderWithThread:thread transaction:transaction];
    if (!builder) {
        OWSFailDebug(@"could not build protobuf.");
        return nil;
    }
    [builder setTimestamp:self.timestamp];
    [ProtoUtils addLocalProfileKeyToDataMessageBuilder:builder];
    [builder setFlags:SSKProtoDataMessageFlagsProfileKeyUpdate];

    NSError *error;
    SSKProtoDataMessage *_Nullable dataProto = [builder buildAndReturnError:&error];
    if (error || !dataProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }
    return dataProto;
}

- (SealedSenderContentHint)contentHint
{
    return SealedSenderContentHintImplicit;
}

@end

NS_ASSUME_NONNULL_END
