//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SignalServiceAddress;

@interface OWSLinkedDeviceReadReceipt : MTLModel

@property (nonatomic, readonly) SignalServiceAddress *senderAddress;
@property (nonatomic, readonly) uint64_t messageIdTimestamp;
@property (nonatomic, readonly) uint64_t readTimestamp;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithSenderAddress:(SignalServiceAddress *)address
                   messageIdTimestamp:(uint64_t)messageIdtimestamp
                        readTimestamp:(uint64_t)readTimestamp NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
