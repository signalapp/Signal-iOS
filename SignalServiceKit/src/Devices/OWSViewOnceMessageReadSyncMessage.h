//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSOutgoingSyncMessage.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

@interface OWSViewOnceMessageReadSyncMessage : OWSOutgoingSyncMessage

@property (nonatomic, readonly) SignalServiceAddress *senderAddress;
@property (nonatomic, readonly) uint64_t messageIdTimestamp;
@property (nonatomic, readonly) uint64_t readTimestamp;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                      transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                 senderAddress:(SignalServiceAddress *)senderAddress
                       message:(TSMessage *)message
                 readTimestamp:(uint64_t)readTimestamp
                   transaction:(SDSAnyReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
