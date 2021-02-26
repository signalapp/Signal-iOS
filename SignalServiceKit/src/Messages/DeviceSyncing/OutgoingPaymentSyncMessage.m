//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OutgoingPaymentSyncMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OutgoingPaymentMobileCoin

- (instancetype)initWithRecipientUuidString:(NSString *)recipientUuidString
                           recipientAddress:(NSData *)recipientAddress
                              amountPicoMob:(uint64_t)amountPicoMob
                                 feePicoMob:(uint64_t)feePicoMob
                                receiptData:(NSData *)receiptData
                            transactionData:(NSData *)transactionData
                                 blockIndex:(uint64_t)blockIndex
                             blockTimestamp:(uint64_t)blockTimestamp
                                memoMessage:(nullable NSString *)memoMessage
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _recipientUuidString = recipientUuidString;
    _recipientAddress = recipientAddress;
    _amountPicoMob = amountPicoMob;
    _feePicoMob = feePicoMob;
    _receiptData = receiptData;
    _transactionData = transactionData;
    _blockIndex = blockIndex;
    _blockTimestamp = blockTimestamp;
    _memoMessage = memoMessage;

    return self;
}

@end

#pragma mark -

@interface OutgoingPaymentSyncMessage ()

@property (nonatomic, readonly) OutgoingPaymentMobileCoin *mobileCoin;

@end

#pragma mark -

@implementation OutgoingPaymentSyncMessage

- (instancetype)initWithThread:(TSThread *)thread mobileCoin:(OutgoingPaymentMobileCoin *)mobileCoin
{
    self = [super initWithThread:thread];
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

@end

NS_ASSUME_NONNULL_END
