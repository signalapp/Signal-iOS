//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"
#import "Cryptography.h"
#import "NSDate+OWS.h"
#import "ProtoBuf+OWS.h"
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
                                  groupMetaMessage:TSGroupMessageUnspecified
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
- (SSKProtoSyncMessage *)buildSyncMessage
{
    SSKProtoSyncMessageBuilder *builder = [self syncMessageBuilder];
    
    // Add a random 1-512 bytes to obscure sync message type
    size_t paddingBytesLength = arc4random_uniform(512) + 1;
    builder.padding = [Cryptography generateRandomBytes:paddingBytesLength];

    return [builder build];
}

- (SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    OWSFail(@"Abstract method should be overridden in subclass.");
    return [SSKProtoSyncMessageBuilder new];
}

- (nullable NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    SSKProtoContentBuilder *contentBuilder = [SSKProtoContentBuilder new];
    [contentBuilder setSyncMessage:[self buildSyncMessage]];
    return [[contentBuilder build] data];
}

@end

NS_ASSUME_NONNULL_END
