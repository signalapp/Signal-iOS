//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSReadReceiptsForLinkedDevicesMessage.h"
#import "OWSLinkedDeviceReadReceipt.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSReadReceiptsForLinkedDevicesMessage ()

@property (nonatomic, readonly) NSArray<OWSLinkedDeviceReadReceipt *> *readReceipts;

@end

@implementation OWSReadReceiptsForLinkedDevicesMessage

- (instancetype)initWithReadReceipts:(NSArray<OWSLinkedDeviceReadReceipt *> *)readReceipts
{
    self = [super init];
    if (!self) {
        return self;
    }

    _readReceipts = [readReceipts copy];

    return self;
}

- (OWSSignalServiceProtosSyncMessageBuilder *)syncMessageBuilder
{
    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];
    for (OWSLinkedDeviceReadReceipt *readReceipt in self.readReceipts) {
        OWSSignalServiceProtosSyncMessageReadBuilder *readProtoBuilder =
            [OWSSignalServiceProtosSyncMessageReadBuilder new];
        [readProtoBuilder setSender:readReceipt.senderId];
        [readProtoBuilder setTimestamp:readReceipt.messageIdTimestamp];
        [syncMessageBuilder addRead:[readProtoBuilder build]];
    }

    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
