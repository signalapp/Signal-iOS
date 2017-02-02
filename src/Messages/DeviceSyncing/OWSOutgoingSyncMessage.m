//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSOutgoingSyncMessage.h"
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

- (BOOL)isLegacyMessage
{
    return NO;
}

- (OWSSignalServiceProtosSyncMessage *)buildSyncMessage
{
    NSAssert(NO, @"buildSyncMessage must be overridden in subclass");

    // e.g.
    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];
    return [syncMessageBuilder build];
}

- (NSData *)buildPlainTextData
{
    OWSSignalServiceProtosContentBuilder *contentBuilder = [OWSSignalServiceProtosContentBuilder new];
    [contentBuilder setSyncMessage:[self buildSyncMessage]];

    return [[contentBuilder build] data];
}

@end

NS_ASSUME_NONNULL_END
