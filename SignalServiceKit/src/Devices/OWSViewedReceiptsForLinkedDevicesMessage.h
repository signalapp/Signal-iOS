//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel.h>
#import <SignalServiceKit/OWSOutgoingSyncMessage.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SignalServiceAddress;

@interface OWSLinkedDeviceViewedReceipt : MTLModel

@property (nonatomic, readonly) SignalServiceAddress *senderAddress;
@property (nonatomic, readonly) uint64_t messageIdTimestamp;
@property (nonatomic, readonly) uint64_t viewedTimestamp;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithSenderAddress:(SignalServiceAddress *)address
                   messageIdTimestamp:(uint64_t)messageIdtimestamp
                      viewedTimestamp:(uint64_t)viewedTimestamp NS_DESIGNATED_INITIALIZER;

@end

@interface OWSViewedReceiptsForLinkedDevicesMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                viewedReceipts:(NSArray<OWSLinkedDeviceViewedReceipt *> *)readReceipts NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
