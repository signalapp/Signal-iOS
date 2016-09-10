//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSReadReceiptsMessage.h"
#import "OWSReadReceipt.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSReadReceiptsMessage ()

@property (nonatomic, readonly) NSArray<OWSReadReceipt *> *readReceipts;

@end

@implementation OWSReadReceiptsMessage

- (instancetype)initWithReadReceipts:(NSArray<OWSReadReceipt *> *)readReceipts
{
    self = [super init];
    if (!self) {
        return self;
    }

    _readReceipts = [readReceipts copy];

    return self;
}

- (OWSSignalServiceProtosSyncMessage *)buildSyncMessage
{
    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];
    for (OWSReadReceipt *readReceipt in self.readReceipts) {
        OWSSignalServiceProtosSyncMessageReadBuilder *readProtoBuilder =
            [OWSSignalServiceProtosSyncMessageReadBuilder new];
        [readProtoBuilder setSender:readReceipt.senderId];
        [readProtoBuilder setTimestamp:readReceipt.timestamp];
        [syncMessageBuilder addRead:[readProtoBuilder build]];
    }

    return [syncMessageBuilder build];
}

@end

NS_ASSUME_NONNULL_END
