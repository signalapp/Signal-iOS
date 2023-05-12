//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSReadReceiptsForLinkedDevicesMessage.h"
#import "OWSLinkedDeviceReadReceipt.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSReadReceiptsForLinkedDevicesMessage ()

@property (nonatomic, readonly) NSArray<OWSLinkedDeviceReadReceipt *> *readReceipts;

@end

@implementation OWSReadReceiptsForLinkedDevicesMessage

- (instancetype)initWithThread:(TSThread *)thread
                  readReceipts:(NSArray<OWSLinkedDeviceReadReceipt *> *)readReceipts
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [super initWithThread:thread transaction:transaction];
    if (!self) {
        return self;
    }

    _readReceipts = [readReceipts copy];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    for (OWSLinkedDeviceReadReceipt *readReceipt in self.readReceipts) {
        SSKProtoSyncMessageReadBuilder *readProtoBuilder =
            [SSKProtoSyncMessageRead builderWithTimestamp:readReceipt.messageIdTimestamp];

        [readProtoBuilder setSenderUuid:readReceipt.senderAddress.uuidString];

        NSError *error;
        SSKProtoSyncMessageRead *_Nullable readProto = [readProtoBuilder buildAndReturnError:&error];
        if (error || !readProto) {
            OWSFailDebug(@"could not build protobuf: %@", error);
            return nil;
        }
        [syncMessageBuilder addRead:readProto];
    }
    return syncMessageBuilder;
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    NSMutableArray<NSString *> *messageUniqueIds = [[NSMutableArray alloc] init];
    for (OWSLinkedDeviceReadReceipt *readReceipt in self.readReceipts) {
        if (readReceipt.messageUniqueId) {
            [messageUniqueIds addObject:readReceipt.messageUniqueId];
        }
    }
    return [[super relatedUniqueIds] setByAddingObjectsFromArray:messageUniqueIds];
}


@end

NS_ASSUME_NONNULL_END
