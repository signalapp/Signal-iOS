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

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:[self valueForKey:@"amountPicoMob"] forKey:@"amountPicoMob"];
    [coder encodeObject:[self valueForKey:@"blockIndex"] forKey:@"blockIndex"];
    [coder encodeObject:[self valueForKey:@"blockTimestamp"] forKey:@"blockTimestamp"];
    [coder encodeObject:[self valueForKey:@"feePicoMob"] forKey:@"feePicoMob"];
    [coder encodeObject:[self valueForKey:@"isDefragmentation"] forKey:@"isDefragmentation"];
    NSString *memoMessage = self.memoMessage;
    if (memoMessage != nil) {
        [coder encodeObject:memoMessage forKey:@"memoMessage"];
    }
    NSArray *outputPublicKeys = self.outputPublicKeys;
    if (outputPublicKeys != nil) {
        [coder encodeObject:outputPublicKeys forKey:@"outputPublicKeys"];
    }
    NSData *receiptData = self.receiptData;
    if (receiptData != nil) {
        [coder encodeObject:receiptData forKey:@"receiptData"];
    }
    NSData *recipientAddress = self.recipientAddress;
    if (recipientAddress != nil) {
        [coder encodeObject:recipientAddress forKey:@"recipientAddress"];
    }
    NSString *recipientUuidString = self.recipientUuidString;
    if (recipientUuidString != nil) {
        [coder encodeObject:recipientUuidString forKey:@"recipientUuidString"];
    }
    NSArray *spentKeyImages = self.spentKeyImages;
    if (spentKeyImages != nil) {
        [coder encodeObject:spentKeyImages forKey:@"spentKeyImages"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_amountPicoMob = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                            forKey:@"amountPicoMob"] unsignedLongLongValue];
    self->_blockIndex = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                         forKey:@"blockIndex"] unsignedLongLongValue];
    self->_blockTimestamp = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                             forKey:@"blockTimestamp"] unsignedLongLongValue];
    self->_feePicoMob = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                         forKey:@"feePicoMob"] unsignedLongLongValue];
    self->_isDefragmentation = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                                forKey:@"isDefragmentation"] boolValue];
    self->_memoMessage = [coder decodeObjectOfClass:[NSString class] forKey:@"memoMessage"];
    self->_outputPublicKeys = [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [NSData class] ]]
                                                    forKey:@"outputPublicKeys"];
    self->_receiptData = [coder decodeObjectOfClass:[NSData class] forKey:@"receiptData"];
    self->_recipientAddress = [coder decodeObjectOfClass:[NSData class] forKey:@"recipientAddress"];
    self->_recipientUuidString = [coder decodeObjectOfClass:[NSString class] forKey:@"recipientUuidString"];
    self->_spentKeyImages = [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [NSData class] ]]
                                                  forKey:@"spentKeyImages"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.amountPicoMob;
    result ^= self.blockIndex;
    result ^= self.blockTimestamp;
    result ^= self.feePicoMob;
    result ^= self.isDefragmentation;
    result ^= self.memoMessage.hash;
    result ^= self.outputPublicKeys.hash;
    result ^= self.receiptData.hash;
    result ^= self.recipientAddress.hash;
    result ^= self.recipientUuidString.hash;
    result ^= self.spentKeyImages.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    OutgoingPaymentMobileCoin *typedOther = (OutgoingPaymentMobileCoin *)other;
    if (self.amountPicoMob != typedOther.amountPicoMob) {
        return NO;
    }
    if (self.blockIndex != typedOther.blockIndex) {
        return NO;
    }
    if (self.blockTimestamp != typedOther.blockTimestamp) {
        return NO;
    }
    if (self.feePicoMob != typedOther.feePicoMob) {
        return NO;
    }
    if (self.isDefragmentation != typedOther.isDefragmentation) {
        return NO;
    }
    if (![NSObject isObject:self.memoMessage equalToObject:typedOther.memoMessage]) {
        return NO;
    }
    if (![NSObject isObject:self.outputPublicKeys equalToObject:typedOther.outputPublicKeys]) {
        return NO;
    }
    if (![NSObject isObject:self.receiptData equalToObject:typedOther.receiptData]) {
        return NO;
    }
    if (![NSObject isObject:self.recipientAddress equalToObject:typedOther.recipientAddress]) {
        return NO;
    }
    if (![NSObject isObject:self.recipientUuidString equalToObject:typedOther.recipientUuidString]) {
        return NO;
    }
    if (![NSObject isObject:self.spentKeyImages equalToObject:typedOther.spentKeyImages]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OutgoingPaymentMobileCoin *result = [[[self class] allocWithZone:zone] init];
    result->_amountPicoMob = self.amountPicoMob;
    result->_blockIndex = self.blockIndex;
    result->_blockTimestamp = self.blockTimestamp;
    result->_feePicoMob = self.feePicoMob;
    result->_isDefragmentation = self.isDefragmentation;
    result->_memoMessage = self.memoMessage;
    result->_outputPublicKeys = self.outputPublicKeys;
    result->_receiptData = self.receiptData;
    result->_recipientAddress = self.recipientAddress;
    result->_recipientUuidString = self.recipientUuidString;
    result->_spentKeyImages = self.spentKeyImages;
    return result;
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

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                         mobileCoin:(OutgoingPaymentMobileCoin *)mobileCoin
                        transaction:(DBReadTransaction *)transaction
{
    self = [super initWithLocalThread:localThread transaction:transaction];
    if (!self) {
        return nil;
    }

    _mobileCoin = mobileCoin;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    OutgoingPaymentMobileCoin *mobileCoin = self.mobileCoin;
    if (mobileCoin != nil) {
        [coder encodeObject:mobileCoin forKey:@"mobileCoin"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_mobileCoin = [coder decodeObjectOfClass:[OutgoingPaymentMobileCoin class] forKey:@"mobileCoin"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.mobileCoin.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OutgoingPaymentSyncMessage *typedOther = (OutgoingPaymentSyncMessage *)other;
    if (![NSObject isObject:self.mobileCoin equalToObject:typedOther.mobileCoin]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OutgoingPaymentSyncMessage *result = [super copyWithZone:zone];
    result->_mobileCoin = self.mobileCoin;
    return result;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(DBReadTransaction *)transaction
{
    return [self syncMessageBuilderWithMobileCoin:self.mobileCoin transaction:transaction];
}

- (BOOL)isUrgent
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
