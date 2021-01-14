//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

- (instancetype)initWithThread:(TSThread *)thread
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder];

    if (!self) {
        return self;
    }

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    messageBuilder.timestamp = timestamp;
    self = [super initOutgoingMessageWithBuilder:messageBuilder];

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

    // Add a random 1-512 bytes to obscure sync message type
    size_t paddingBytesLength = arc4random_uniform(512) + 1;
    builder.padding = [Cryptography generateRandomBytes:paddingBytesLength];

    NSError *error;
    SSKProtoSyncMessage *_Nullable proto = [builder buildAndReturnError:&error];
    if (error || !proto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }
    return proto;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction;
{
    OWSAbstractMethod();

    return [SSKProtoSyncMessage builder];
}

- (nullable NSData *)buildPlainTextData:(SignalServiceAddress *)address
                                 thread:(TSThread *)thread
                            transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessage *_Nullable syncMessage = [self buildSyncMessageWithTransaction:transaction];
    if (!syncMessage) {
        return nil;
    }

    SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
    [contentBuilder setSyncMessage:syncMessage];

    NSError *error;
    NSData *_Nullable data = [contentBuilder buildSerializedDataAndReturnError:&error];
    if (error || !data) {
        OWSFailDebug(@"could not serialize protobuf: %@", error);
        return nil;
    }

    return data;
}

@end

NS_ASSUME_NONNULL_END
