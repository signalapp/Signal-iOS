//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface PaymentsSyncMobileCoinOutgoing : MTLModel

@property (nonatomic, readonly) uint64_t picoMob;
@property (nonatomic, readonly) NSString *recipientUuidString;
@property (nonatomic, readonly) NSData *receipt;
@property (nonatomic, readonly) uint64_t blockIndex;
// This property will be zero if the timestamp is unknown.
@property (nonatomic, readonly) uint64_t blockTimestamp;
@property (nonatomic, readonly) NSArray<NSData *> *spentKeyImages;
@property (nonatomic, readonly) NSArray<NSData *> *outputPublicKeys;
@property (nonatomic, readonly, nullable) NSString *memoMessage;

- (instancetype)initWithPicoMob:(uint64_t)picoMob
            recipientUuidString:(NSString *)recipientUuidString
                        receipt:(NSData *)receipt
                     blockIndex:(uint64_t)blockIndex
                 blockTimestamp:(uint64_t)blockTimestamp
                 spentKeyImages:(NSArray<NSData *> *)spentKeyImages
               outputPublicKeys:(NSArray<NSData *> *)outputPublicKeys
                    memoMessage:(nullable NSString *)memoMessage;

@end

#pragma mark -

// TODO: Support mobilecoin defrags.
// TODO: Support requests.
@interface PaymentsSyncMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                    mcOutgoing:(nullable PaymentsSyncMobileCoinOutgoing *)mcOutgoing NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
