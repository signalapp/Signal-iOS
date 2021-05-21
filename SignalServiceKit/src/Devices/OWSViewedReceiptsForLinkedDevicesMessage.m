//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSLinkedDeviceReadReceipt.h>
#import <SignalServiceKit/OWSViewedReceiptsForLinkedDevicesMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSViewedReceiptsForLinkedDevicesMessage ()

@property (nonatomic, readonly) NSArray<OWSLinkedDeviceViewedReceipt *> *viewedReceipts;

@end

@implementation OWSViewedReceiptsForLinkedDevicesMessage

- (instancetype)initWithThread:(TSThread *)thread
                viewedReceipts:(NSArray<OWSLinkedDeviceViewedReceipt *> *)viewedReceipts
{
    self = [super initWithThread:thread];
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

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    for (OWSLinkedDeviceViewedReceipt *viewedReceipt in self.viewedReceipts) {
        SSKProtoSyncMessageViewedBuilder *viewedProtoBuilder =
            [SSKProtoSyncMessageViewed builderWithTimestamp:viewedReceipt.messageIdTimestamp];

        [viewedProtoBuilder setSenderE164:viewedReceipt.senderAddress.phoneNumber];
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

@end

@interface OWSLinkedDeviceViewedReceipt ()

@property (nonatomic, nullable, readonly) NSString *senderPhoneNumber;
@property (nonatomic, nullable, readonly) NSString *senderUUID;

@end

@implementation OWSLinkedDeviceViewedReceipt

- (instancetype)initWithSenderAddress:(SignalServiceAddress *)address
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
