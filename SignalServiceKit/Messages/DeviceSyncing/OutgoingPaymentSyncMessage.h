//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSOutgoingSyncMessage.h>

NS_ASSUME_NONNULL_BEGIN

@class AciObjC;

@interface OutgoingPaymentMobileCoin : MTLModel

@property (nonatomic, readonly, nullable) AciObjC *recipientAci;
@property (nonatomic, readonly, nullable) NSData *recipientAddress;
@property (nonatomic, readonly) uint64_t amountPicoMob;
@property (nonatomic, readonly) uint64_t feePicoMob;
@property (nonatomic, readonly) uint64_t blockIndex;
// This property will be zero if the timestamp is unknown.
@property (nonatomic, readonly) uint64_t blockTimestamp;
@property (nonatomic, readonly, nullable) NSString *memoMessage;
@property (nonatomic, readonly) NSArray<NSData *> *spentKeyImages;
@property (nonatomic, readonly) NSArray<NSData *> *outputPublicKeys;
@property (nonatomic, readonly) NSData *receiptData;
@property (nonatomic, readonly) BOOL isDefragmentation;

- (instancetype)initWithRecipientAci:(nullable AciObjC *)recipientAci
                    recipientAddress:(nullable NSData *)recipientAddress
                       amountPicoMob:(uint64_t)amountPicoMob
                          feePicoMob:(uint64_t)feePicoMob
                          blockIndex:(uint64_t)blockIndex
                      blockTimestamp:(uint64_t)blockTimestamp
                         memoMessage:(nullable NSString *)memoMessage
                      spentKeyImages:(NSArray<NSData *> *)spentKeyImages
                    outputPublicKeys:(NSArray<NSData *> *)outputPublicKeys
                         receiptData:(NSData *)receiptData
                   isDefragmentation:(BOOL)isDefragmentation;

@end

#pragma mark -

@interface OutgoingPaymentSyncMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                        transaction:(DBReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                      localThread:(TSContactThread *)localThread
                      transaction:(DBReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                         mobileCoin:(OutgoingPaymentMobileCoin *)mobileCoin
                        transaction:(DBReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
