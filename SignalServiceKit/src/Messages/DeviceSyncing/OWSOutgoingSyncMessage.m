//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"
#import "Cryptography.h"
#import "NSDate+OWS.h"
#import "ProtoUtils.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSOutgoingSyncMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)init
{
    self = [super initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                          inThread:nil
                                       messageBody:nil
                                     attachmentIds:[NSMutableArray new]
                                  expiresInSeconds:0
                                   expireStartedAt:0
                                    isVoiceMessage:NO
                                  groupMetaMessage:TSGroupMetaMessageUnspecified
                                     quotedMessage:nil
                                      contactShare:nil];

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
- (nullable SSKProtoSyncMessage *)buildSyncMessage
{
    SSKProtoSyncMessageBuilder *_Nullable builder = [self syncMessageBuilder];
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

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    OWSAbstractMethod();

    return [SSKProtoSyncMessageBuilder new];
}

- (nullable NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    SSKProtoSyncMessage *_Nullable syncMessage = [self buildSyncMessage];
    if (!syncMessage) {
        return nil;
    }

    SSKProtoContentBuilder *contentBuilder = [SSKProtoContentBuilder new];
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
