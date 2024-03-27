//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OutgoingPaymentSyncMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OutgoingPaymentMobileCoin ()
@property (nonatomic, readonly, nullable) NSString *recipientUuidString;
@end

@implementation OutgoingPaymentMobileCoin

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
                   isDefragmentation:(BOOL)isDefragmentation
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _recipientUuidString = recipientAci.serviceIdUppercaseString;
    _recipientAddress = recipientAddress;
    _amountPicoMob = amountPicoMob;
    _feePicoMob = feePicoMob;
    _blockIndex = blockIndex;
    _blockTimestamp = blockTimestamp;
    _memoMessage = memoMessage;
    _spentKeyImages = spentKeyImages;
    _outputPublicKeys = outputPublicKeys;
    _receiptData = receiptData;
    _isDefragmentation = isDefragmentation;

    return self;
}

- (nullable AciObjC *)recipientAci
{
    return [[AciObjC alloc] initWithAciString:self.recipientUuidString];
}

@end

#pragma mark -

@interface OutgoingPaymentSyncMessage ()

@property (nonatomic, readonly) OutgoingPaymentMobileCoin *mobileCoin;

@end

#pragma mark -

@implementation OutgoingPaymentSyncMessage

- (instancetype)initWithThread:(TSThread *)thread
                    mobileCoin:(OutgoingPaymentMobileCoin *)mobileCoin
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [super initWithThread:thread transaction:transaction];
    if (!self) {
        return nil;
    }

    _mobileCoin = mobileCoin;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self syncMessageBuilderWithMobileCoin:self.mobileCoin transaction:transaction];
}

- (BOOL)isUrgent
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
