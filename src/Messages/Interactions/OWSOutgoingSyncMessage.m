//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSOutgoingSyncMessage.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSOutgoingSyncMessage

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (OWSSignalServiceProtosSyncMessage *)buildSyncMessage
{
    NSAssert(NO, @"buildSyncMessage must be overridden in suclass");

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
