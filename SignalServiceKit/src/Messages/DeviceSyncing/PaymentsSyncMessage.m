//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "PaymentsSyncMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation PaymentsSyncMobileCoinOutgoing

- (instancetype)initWithPicoMob:(uint64_t)picoMob
            recipientUuidString:(NSString *)recipientUuidString
                        receipt:(NSData *)receipt
                     blockIndex:(uint64_t)blockIndex
                 blockTimestamp:(uint64_t)blockTimestamp
                 spentKeyImages:(NSArray<NSData *> *)spentKeyImages
               outputPublicKeys:(NSArray<NSData *> *)outputPublicKeys
                    memoMessage:(nullable NSString *)memoMessage
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _picoMob = picoMob;
    _recipientUuidString = recipientUuidString;
    _receipt = receipt;
    _blockIndex = blockIndex;
    _blockTimestamp = blockTimestamp;
    _spentKeyImages = spentKeyImages;
    _outputPublicKeys = outputPublicKeys;
    _memoMessage = memoMessage;

    return self;
}

@end

#pragma mark -

@interface PaymentsSyncMessage ()

@property (nonatomic, readonly, nullable) PaymentsSyncMobileCoinOutgoing *mcOutgoing;

@end

#pragma mark -

@implementation PaymentsSyncMessage

- (instancetype)initWithThread:(TSThread *)thread mcOutgoing:(nullable PaymentsSyncMobileCoinOutgoing *)mcOutgoing
{
    self = [super initWithThread:thread];
    if (!self) {
        return nil;
    }

    _mcOutgoing = mcOutgoing;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self syncMessageBuilderWithMCOutgoing:self.mcOutgoing transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
