//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSPaymentModels.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *NSStringFromTSPaymentCurrency(TSPaymentCurrency value)
{
    switch (value) {
        case TSPaymentCurrencyUnknown:
            return @"Unknown";
        case TSPaymentCurrencyMobileCoin:
            return @"MobileCoin";
    }
}

NSString *NSStringFromTSPaymentType(TSPaymentType value)
{
    switch (value) {
        case TSPaymentTypeIncomingPayment:
            return @"IncomingPayment";
        case TSPaymentTypeOutgoingPaymentNotFromLocalDevice:
            return @"OutgoingPaymentNotFromLocalDevice";
        case TSPaymentTypeOutgoingPayment:
            return @"OutgoingPayment";
        case TSPaymentTypeIncomingUnidentified:
            return @"IncomingUnidentified";
        case TSPaymentTypeOutgoingUnidentified:
            return @"OutgoingUnidentified";
        case TSPaymentTypeOutgoingTransfer:
            return @"OutgoingTransfer";
        case TSPaymentTypeOutgoingDefragmentation:
            return @"OutgoingDefragmentation";
        case TSPaymentTypeOutgoingDefragmentationNotFromLocalDevice:
            return @"OutgoingDefragmentationNotFromLocalDevice";
        case TSPaymentTypeIncomingRestored:
            return @"IncomingRestoredPayment";
        case TSPaymentTypeOutgoingRestored:
            return @"OutgoingRestoredPayment";
        default:
            OWSCFailDebug(@"Unknown value: %d", (int)value);
            return @"Unknown";
    }
}

NSString *NSStringFromTSPaymentState(TSPaymentState value)
{
    switch (value) {
        case TSPaymentStateOutgoingUnsubmitted:
            return @"OutgoingUnsubmitted";
        case TSPaymentStateOutgoingUnverified:
            return @"OutgoingUnverified";
        case TSPaymentStateOutgoingVerified:
            return @"OutgoingVerified";
        case TSPaymentStateOutgoingSending:
            return @"OutgoingSending";
        case TSPaymentStateOutgoingSent:
            return @"OutgoingSent";
        case TSPaymentStateOutgoingComplete:
            return @"OutgoingComplete";
        case TSPaymentStateOutgoingFailed:
            return @"OutgoingFailed";

        case TSPaymentStateIncomingUnverified:
            return @"IncomingUnverified";
        case TSPaymentStateIncomingVerified:
            return @"IncomingVerified";
        case TSPaymentStateIncomingComplete:
            return @"IncomingComplete";
        case TSPaymentStateIncomingFailed:
            return @"IncomingFailed";
        default:
            OWSCFailDebug(@"Unknown TSPaymentState.");
            return @"Unknown";
    }
}

NSString *NSStringFromTSPaymentFailure(TSPaymentFailure value)
{
    switch (value) {
        case TSPaymentFailureNone:
            return @"None";
        case TSPaymentFailureUnknown:
            return @"Unknown";
        case TSPaymentFailureInsufficientFunds:
            return @"InsufficientFunds";
        case TSPaymentFailureValidationFailed:
            return @"ValidationFailed";
        case TSPaymentFailureNotificationSendFailed:
            return @"NotificationSendFailed";
        case TSPaymentFailureInvalid:
            return @"Invalid";
        case TSPaymentFailureExpired:
            return @"Expired";
        default:
            OWSCFailDebug(@"Unknown TSPaymentFailure.");
            return @"Unknown";
    }
}

#pragma mark -

@implementation TSPaymentAmount

- (instancetype)initWithCurrency:(TSPaymentCurrency)currency picoMob:(uint64_t)picoMob
{
    self = [super init];

    if (!self) {
        return self;
    }

    _currency = currency;
    _picoMob = picoMob;

    OWSAssertDebug([self isValidAmountWithCanBeEmpty:YES]);

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:[self valueForKey:@"currency"] forKey:@"currency"];
    [coder encodeObject:[self valueForKey:@"picoMob"] forKey:@"picoMob"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_currency = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                       forKey:@"currency"] unsignedIntegerValue];
    self->_picoMob = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:@"picoMob"] unsignedLongLongValue];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.currency;
    result ^= self.picoMob;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    TSPaymentAmount *typedOther = (TSPaymentAmount *)other;
    if (self.currency != typedOther.currency) {
        return NO;
    }
    if (self.picoMob != typedOther.picoMob) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TSPaymentAmount *result = [[[self class] allocWithZone:zone] init];
    result->_currency = self.currency;
    result->_picoMob = self.picoMob;
    return result;
}

@end

#pragma mark -

@implementation TSPaymentAddress

- (instancetype)initWithCurrency:(TSPaymentCurrency)currency
     mobileCoinPublicAddressData:(NSData *)mobileCoinPublicAddressData
{
    self = [super init];

    if (!self) {
        return self;
    }

    _currency = currency;
    _mobileCoinPublicAddressData = mobileCoinPublicAddressData;

    OWSAssertDebug(self.isValid);

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:[self valueForKey:@"currency"] forKey:@"currency"];
    NSData *mobileCoinPublicAddressData = self.mobileCoinPublicAddressData;
    if (mobileCoinPublicAddressData != nil) {
        [coder encodeObject:mobileCoinPublicAddressData forKey:@"mobileCoinPublicAddressData"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_currency = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                       forKey:@"currency"] unsignedIntegerValue];
    self->_mobileCoinPublicAddressData = [coder decodeObjectOfClass:[NSData class]
                                                             forKey:@"mobileCoinPublicAddressData"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.currency;
    result ^= self.mobileCoinPublicAddressData.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    TSPaymentAddress *typedOther = (TSPaymentAddress *)other;
    if (self.currency != typedOther.currency) {
        return NO;
    }
    if (![NSObject isObject:self.mobileCoinPublicAddressData equalToObject:typedOther.mobileCoinPublicAddressData]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TSPaymentAddress *result = [[[self class] allocWithZone:zone] init];
    result->_currency = self.currency;
    result->_mobileCoinPublicAddressData = self.mobileCoinPublicAddressData;
    return result;
}

@end

#pragma mark -

@implementation TSPaymentNotification

- (instancetype)initWithMemoMessage:(nullable NSString *)memoMessage mcReceiptData:(NSData *)mcReceiptData
{
    self = [super init];

    if (!self) {
        return self;
    }

    _memoMessage = memoMessage;
    _mcReceiptData = mcReceiptData;

    OWSAssertDebug(self.isValid);

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    NSData *mcReceiptData = self.mcReceiptData;
    if (mcReceiptData != nil) {
        [coder encodeObject:mcReceiptData forKey:@"mcReceiptData"];
    }
    NSString *memoMessage = self.memoMessage;
    if (memoMessage != nil) {
        [coder encodeObject:memoMessage forKey:@"memoMessage"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_mcReceiptData = [coder decodeObjectOfClass:[NSData class] forKey:@"mcReceiptData"];
    self->_memoMessage = [coder decodeObjectOfClass:[NSString class] forKey:@"memoMessage"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.mcReceiptData.hash;
    result ^= self.memoMessage.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    TSPaymentNotification *typedOther = (TSPaymentNotification *)other;
    if (![NSObject isObject:self.mcReceiptData equalToObject:typedOther.mcReceiptData]) {
        return NO;
    }
    if (![NSObject isObject:self.memoMessage equalToObject:typedOther.memoMessage]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TSPaymentNotification *result = [[[self class] allocWithZone:zone] init];
    result->_mcReceiptData = self.mcReceiptData;
    result->_memoMessage = self.memoMessage;
    return result;
}

@end

#pragma mark -

@implementation TSArchivedPaymentInfo

- (instancetype)initWithAmount:(nullable NSString *)amount fee:(nullable NSString *)fee note:(nullable NSString *)note
{
    self = [super init];

    if (!self) {
        return self;
    }

    _amount = amount;
    _fee = fee;
    _note = note;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    NSString *amount = self.amount;
    if (amount != nil) {
        [coder encodeObject:amount forKey:@"amount"];
    }
    NSString *fee = self.fee;
    if (fee != nil) {
        [coder encodeObject:fee forKey:@"fee"];
    }
    NSString *note = self.note;
    if (note != nil) {
        [coder encodeObject:note forKey:@"note"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_amount = [coder decodeObjectOfClass:[NSString class] forKey:@"amount"];
    self->_fee = [coder decodeObjectOfClass:[NSString class] forKey:@"fee"];
    self->_note = [coder decodeObjectOfClass:[NSString class] forKey:@"note"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.amount.hash;
    result ^= self.fee.hash;
    result ^= self.note.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    TSArchivedPaymentInfo *typedOther = (TSArchivedPaymentInfo *)other;
    if (![NSObject isObject:self.amount equalToObject:typedOther.amount]) {
        return NO;
    }
    if (![NSObject isObject:self.fee equalToObject:typedOther.fee]) {
        return NO;
    }
    if (![NSObject isObject:self.note equalToObject:typedOther.note]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TSArchivedPaymentInfo *result = [[[self class] allocWithZone:zone] init];
    result->_amount = self.amount;
    result->_fee = self.fee;
    result->_note = self.note;
    return result;
}

@end

NS_ASSUME_NONNULL_END
