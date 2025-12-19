//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@import Foundation;

#import <SignalServiceKit/OWSOutgoingSyncMessage.h>

NS_ASSUME_NONNULL_BEGIN

@class AciObjC;
@class DBReadTransaction;
@class SignalServiceAddress;

@interface OWSLinkedDeviceViewedReceipt : NSObject <NSCoding, NSCopying>

@property (nonatomic, readonly) SignalServiceAddress *senderAddress;
@property (nonatomic, readonly, nullable) NSString *messageUniqueId; // Only nil if decoding old values
@property (nonatomic, readonly) uint64_t messageIdTimestamp;
@property (nonatomic, readonly) uint64_t viewedTimestamp;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithSenderAci:(AciObjC *)senderAci
                  messageUniqueId:(nullable NSString *)messageUniqueId
               messageIdTimestamp:(uint64_t)messageIdTimestamp
                  viewedTimestamp:(uint64_t)viewedTimestamp NS_DESIGNATED_INITIALIZER;

@end

@interface OWSViewedReceiptsForLinkedDevicesMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                        transaction:(DBReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                      localThread:(TSContactThread *)localThread
                      transaction:(DBReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                     viewedReceipts:(NSArray<OWSLinkedDeviceViewedReceipt *> *)readReceipts
                        transaction:(DBReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
