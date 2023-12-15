//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSPaymentModels.h"
#import <SignalCoreKit/NSDate+OWS.h>
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

@end

NS_ASSUME_NONNULL_END
