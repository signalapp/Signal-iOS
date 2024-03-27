//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/BaseModel.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

typedef NS_ENUM(NSUInteger, TSPaymentCurrency) {
    TSPaymentCurrencyUnknown = 0,
    TSPaymentCurrencyMobileCoin = 1,
};

NSString *NSStringFromTSPaymentCurrency(TSPaymentCurrency value);

#pragma mark -

typedef NS_ENUM(NSUInteger, TSPaymentType) {
    TSPaymentTypeIncomingPayment = 0,
    TSPaymentTypeOutgoingPayment,
    TSPaymentTypeOutgoingPaymentNotFromLocalDevice,
    TSPaymentTypeIncomingUnidentified,
    TSPaymentTypeOutgoingUnidentified,
    TSPaymentTypeOutgoingTransfer,
    TSPaymentTypeOutgoingDefragmentation,
    TSPaymentTypeOutgoingDefragmentationNotFromLocalDevice,
};

NSString *NSStringFromTSPaymentType(TSPaymentType value);

#pragma mark -

// This enum is essential to the correct functioning of
// the payments logic. Each value corresponds to a state
// of a state machine.
//
// The payments logic ushers payments through this
// state machine as quickly as possible.
//
// Each state implies which properties of a payment model
// should be present / can be trusted.  See TSPaymentModel.isValid.
//
// NOTE: If you add or remove cases, you need to update
//       paymentStatesToIgnore() and paymentStatesToProcess().
typedef NS_ENUM(NSUInteger, TSPaymentState) {
    // Not (yet) in ledger.
    TSPaymentStateOutgoingUnsubmitted = 0,
    // Possibly in ledger.
    TSPaymentStateOutgoingUnverified,
    // In ledger.
    TSPaymentStateOutgoingVerified,
    // In ledger.
    TSPaymentStateOutgoingSending,
    // In ledger.
    TSPaymentStateOutgoingSent,
    // In ledger.
    TSPaymentStateOutgoingComplete,
    // Not in ledger.
    // Should be ignored during reconciliation.
    TSPaymentStateOutgoingFailed,

    // Possibly in ledger.
    TSPaymentStateIncomingUnverified,
    // In ledger.
    TSPaymentStateIncomingVerified,
    // In ledger.
    TSPaymentStateIncomingComplete,
    // Not in ledger.
    // Should be ignored during reconciliation.
    TSPaymentStateIncomingFailed,
};

#pragma mark -

typedef NS_ENUM(NSUInteger, TSPaymentFailure) {
    TSPaymentFailureNone = 0,
    TSPaymentFailureUnknown,
    TSPaymentFailureInsufficientFunds,
    TSPaymentFailureValidationFailed,
    TSPaymentFailureNotificationSendFailed,
    // The payment model is malformed or completed.
    TSPaymentFailureInvalid,
    TSPaymentFailureExpired,
};

NSString *NSStringFromTSPaymentState(TSPaymentState value);

NSString *NSStringFromTSPaymentFailure(TSPaymentFailure value);

#pragma mark -

@interface TSPaymentAmount : MTLModel

@property (nonatomic, readonly) TSPaymentCurrency currency;
@property (nonatomic, readonly) uint64_t picoMob;

- (instancetype)initWithCurrency:(TSPaymentCurrency)currency picoMob:(uint64_t)picoMob;

@end

#pragma mark -

@interface TSPaymentAddress : MTLModel

@property (nonatomic, readonly) TSPaymentCurrency currency;
@property (nonatomic, readonly) NSData *mobileCoinPublicAddressData;

- (instancetype)initWithCurrency:(TSPaymentCurrency)currency
     mobileCoinPublicAddressData:(NSData *)mobileCoinPublicAddressData;

@end

#pragma mark -

@interface TSPaymentNotification : MTLModel

@property (nonatomic, readonly, nullable) NSString *memoMessage;
@property (nonatomic, readonly) NSData *mcReceiptData;

- (instancetype)initWithMemoMessage:(nullable NSString *)memoMessage mcReceiptData:(NSData *)mcReceiptData;

@end

NS_ASSUME_NONNULL_END
