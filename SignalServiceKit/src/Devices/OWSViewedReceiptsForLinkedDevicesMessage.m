//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSViewedReceiptsForLinkedDevicesMessage.h"
#import "OWSLinkedDeviceReadReceipt.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSViewedReceiptsForLinkedDevicesMessage ()

@property (nonatomic, readonly) NSArray<OWSLinkedDeviceViewedReceipt *> *viewedReceipts;

@end

@implementation OWSViewedReceiptsForLinkedDevicesMessage

- (instancetype)initWithThread:(TSThread *)thread
                viewedReceipts:(NSArray<OWSLinkedDeviceViewedReceipt *> *)viewedReceipts
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [super initWithThread:thread transaction:transaction];
    if (!self) {
        return self;
    }

    _viewedReceipts = [viewedReceipts copy];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (BOOL)isUrgent
{
    return NO;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    for (OWSLinkedDeviceViewedReceipt *viewedReceipt in self.viewedReceipts) {
        SSKProtoSyncMessageViewedBuilder *viewedProtoBuilder =
            [SSKProtoSyncMessageViewed builderWithTimestamp:viewedReceipt.messageIdTimestamp];

        [viewedProtoBuilder setSenderUuid:viewedReceipt.senderAddress.uuidString];

        NSError *error;
        SSKProtoSyncMessageViewed *_Nullable viewedProto = [viewedProtoBuilder buildAndReturnError:&error];
        if (error || !viewedProto) {
            OWSFailDebug(@"could not build protobuf: %@", error);
            return nil;
        }
        [syncMessageBuilder addViewed:viewedProto];
    }
    return syncMessageBuilder;
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    NSMutableArray<NSString *> *messageUniqueIds = [[NSMutableArray alloc] init];
    for (OWSLinkedDeviceViewedReceipt *viewReceipt in self.viewedReceipts) {
        if (viewReceipt.messageUniqueId) {
            [messageUniqueIds addObject:viewReceipt.messageUniqueId];
        }
    }
    return [[super relatedUniqueIds] setByAddingObjectsFromArray:messageUniqueIds];
}

@end

@interface OWSLinkedDeviceViewedReceipt ()

@property (nonatomic, nullable, readonly) NSString *senderPhoneNumber;
@property (nonatomic, nullable, readonly) NSString *senderUUID;

@end

@implementation OWSLinkedDeviceViewedReceipt

- (instancetype)initWithSenderAddress:(SignalServiceAddress *)address
                      messageUniqueId:(nullable NSString *)messageUniqueId
                   messageIdTimestamp:(uint64_t)messageIdTimestamp
                      viewedTimestamp:(uint64_t)viewedTimestamp
{
    OWSAssertDebug(address.isValid && messageIdTimestamp > 0);

    self = [super init];
    if (!self) {
        return self;
    }

    _senderPhoneNumber = address.phoneNumber;
    _senderUUID = address.uuidString;
    _messageUniqueId = messageUniqueId;
    _messageIdTimestamp = messageIdTimestamp;
    _viewedTimestamp = viewedTimestamp;

    return self;
}

- (SignalServiceAddress *)senderAddress
{
    return [[SignalServiceAddress alloc] initWithUuidString:self.senderUUID phoneNumber:self.senderPhoneNumber];
}

@end

NS_ASSUME_NONNULL_END
