//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOutgoingSyncMessage.h"
#import "ProtoUtils.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSOutgoingSyncMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];

    if (!self) {
        return self;
    }

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                      transaction:(SDSAnyReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    messageBuilder.timestamp = timestamp;
    self = [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];

    if (!self) {
        return self;
    }

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

// This method should not be overridden, since we want to add random padding to *every* sync message
- (nullable SSKProtoSyncMessage *)buildSyncMessageWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessageBuilder *_Nullable builder = [self syncMessageBuilderWithTransaction:transaction];
    if (!builder) {
        return nil;
    }

    NSError *error;
    SSKProtoSyncMessage *_Nullable proto = [[self class] buildSyncMessageProtoForMessageBuilder:builder error:&error];

    if (error || !proto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    return proto;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAbstractMethod();

    return [SSKProtoSyncMessage builder];
}

- (nullable SSKProtoContentBuilder *)contentBuilderWithThread:(TSThread *)thread
                                                  transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessage *_Nullable syncMessage = [self buildSyncMessageWithTransaction:transaction];
    if (!syncMessage) {
        return nil;
    }

    SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
    [contentBuilder setSyncMessage:syncMessage];
    return contentBuilder;
}

+ (nullable SSKProtoSyncMessage *)buildSyncMessageProtoForMessageBuilder:
                                      (SSKProtoSyncMessageBuilder *)syncMessageBuilder
                                                                   error:(NSError **)errorHandle
{
    // Add a random 1-512 bytes to obscure sync message type
    size_t paddingBytesLength = arc4random_uniform(512) + 1;
    syncMessageBuilder.padding = [Cryptography generateRandomBytes:paddingBytesLength];

    return [syncMessageBuilder buildAndReturnError:errorHandle];
}

@end

NS_ASSUME_NONNULL_END
