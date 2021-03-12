//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OutgoingPaymentMobileCoin : MTLModel

@property (nonatomic, readonly, nullable) NSString *recipientUuidString;
@property (nonatomic, readonly, nullable) NSData *recipientAddress;
@property (nonatomic, readonly) uint64_t amountPicoMob;
@property (nonatomic, readonly) uint64_t feePicoMob;
@property (nonatomic, readonly, nullable) NSData *receiptData;
@property (nonatomic, readonly) NSData *transactionData;
@property (nonatomic, readonly) uint64_t blockIndex;
// This property will be zero if the timestamp is unknown.
@property (nonatomic, readonly) uint64_t blockTimestamp;
@property (nonatomic, readonly, nullable) NSString *memoMessage;
@property (nonatomic, readonly) BOOL isDefragmentation;

- (instancetype)initWithRecipientUuidString:(nullable NSString *)recipientUuidString
                           recipientAddress:(nullable NSData *)recipientAddress
                              amountPicoMob:(uint64_t)amountPicoMob
                                 feePicoMob:(uint64_t)feePicoMob
                                receiptData:(nullable NSData *)receiptData
                            transactionData:(NSData *)transactionData
                                 blockIndex:(uint64_t)blockIndex
                             blockTimestamp:(uint64_t)blockTimestamp
                                memoMessage:(nullable NSString *)memoMessage
                          isDefragmentation:(BOOL)isDefragmentation;

@end

#pragma mark -

// TODO: Support mobilecoin defrags.
// TODO: Support requests.
@interface OutgoingPaymentSyncMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                    mobileCoin:(OutgoingPaymentMobileCoin *)mobileCoin NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
