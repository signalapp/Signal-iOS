//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"
#import "Cryptography.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSOutgoingSyncMessage

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    // override superclass with no-op.
    //
    // There's no need to save this message, since it's not displayed to the user.
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

// This method should not be overridden, since we want to add random padding to *every* sync message
- (OWSSignalServiceProtosSyncMessage *)buildSyncMessage
{
    OWSSignalServiceProtosSyncMessageBuilder *builder = [self syncMessageBuilder];
    
    // Add a random 1-512 bytes to obscure sync message type
    size_t paddingBytesLength = arc4random_uniform(512) + 1;
    builder.padding = [Cryptography generateRandomBytes:paddingBytesLength];
    
    return [builder build];
}

- (OWSSignalServiceProtosSyncMessageBuilder *)syncMessageBuilder
{
    OWSFail(@"Abstract method should be overridden in subclass.");
    return [OWSSignalServiceProtosSyncMessageBuilder new];
}

- (NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    OWSSignalServiceProtosContentBuilder *contentBuilder = [OWSSignalServiceProtosContentBuilder new];
    [contentBuilder setSyncMessage:[self buildSyncMessage]];
    [self addLocalProfileKeyIfNecessary:contentBuilder recipient:recipient];
    return [[contentBuilder build] data];
}

@end

NS_ASSUME_NONNULL_END
