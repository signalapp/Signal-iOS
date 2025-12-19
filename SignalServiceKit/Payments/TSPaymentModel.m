//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSPaymentModel.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSPaymentModel ()

@property (nonatomic) TSPaymentState paymentState;

@property (nonatomic) TSPaymentFailure paymentFailure;

@property (nonatomic, nullable) TSPaymentAmount *paymentAmount;

@property (nonatomic) uint64_t createdTimestamp;

@property (nonatomic, nullable) NSString *addressUuidString;

@property (nonatomic, nullable) NSString *memoMessage;

@property (nonatomic, nullable) NSString *requestUuidString;

@property (nonatomic) BOOL isUnread;

@property (nonatomic, nullable) NSString *interactionUniqueId;

@property (nonatomic, nullable) MobileCoinPayment *mobileCoin;
@property (nonatomic) uint64_t mcLedgerBlockIndex;
@property (nonatomic, nullable) NSData *mcTransactionData;
@property (nonatomic, nullable) NSData *mcReceiptData;

@end

#pragma mark -

@interface MobileCoinPayment ()

@property (nonatomic) uint64_t ledgerBlockTimestamp;

@property (nonatomic) uint64_t ledgerBlockIndex;

+ (MobileCoinPayment *)copy:(nullable MobileCoinPayment *)oldCopy withLedgerBlockIndex:(uint64_t)ledgerBlockIndex;

+ (MobileCoinPayment *)copy:(nullable MobileCoinPayment *)oldCopy
    withLedgerBlockTimestamp:(uint64_t)ledgerBlockTimestamp;

@end

#pragma mark -

@implementation TSPaymentModel

- (instancetype)initWithPaymentType:(TSPaymentType)paymentType
                       paymentState:(TSPaymentState)paymentState
                      paymentAmount:(nullable TSPaymentAmount *)paymentAmount
                        createdDate:(NSDate *)createdDate
               senderOrRecipientAci:(nullable AciObjC *)senderOrRecipientAci
                        memoMessage:(nullable NSString *)memoMessage
                           isUnread:(BOOL)isUnread
                interactionUniqueId:(nullable NSString *)interactionUniqueId
                         mobileCoin:(MobileCoinPayment *)mobileCoin
{
    NSString *uniqueId = [[self class] generateUniqueId];
    self = [super initWithUniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _paymentType = paymentType;
    _paymentState = paymentState;
    _paymentAmount = paymentAmount;
    _createdTimestamp = createdDate.ows_millisecondsSince1970;
    _addressUuidString = senderOrRecipientAci.serviceIdUppercaseString;
    _memoMessage = memoMessage;
    _requestUuidString = nil;
    _isUnread = isUnread;
    _interactionUniqueId = interactionUniqueId;
    _mobileCoin = mobileCoin;

    _mcLedgerBlockIndex = mobileCoin.ledgerBlockIndex;
    _mcTransactionData = mobileCoin.transactionData;
    _mcReceiptData = mobileCoin.receiptData;

    OWSAssertDebug(self.isValid);

    OWSLogInfo(@"Creating payment model: %@", self.descriptionForLogs);

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [self encodeIdsWithCoder:coder];
    NSString *addressUuidString = self.addressUuidString;
    if (addressUuidString != nil) {
        [coder encodeObject:addressUuidString forKey:@"addressUuidString"];
    }
    [coder encodeObject:[self valueForKey:@"createdTimestamp"] forKey:@"createdTimestamp"];
    NSString *interactionUniqueId = self.interactionUniqueId;
    if (interactionUniqueId != nil) {
        [coder encodeObject:interactionUniqueId forKey:@"interactionUniqueId"];
    }
    [coder encodeObject:[self valueForKey:@"isUnread"] forKey:@"isUnread"];
    [coder encodeObject:[self valueForKey:@"mcLedgerBlockIndex"] forKey:@"mcLedgerBlockIndex"];
    NSData *mcReceiptData = self.mcReceiptData;
    if (mcReceiptData != nil) {
        [coder encodeObject:mcReceiptData forKey:@"mcReceiptData"];
    }
    NSData *mcTransactionData = self.mcTransactionData;
    if (mcTransactionData != nil) {
        [coder encodeObject:mcTransactionData forKey:@"mcTransactionData"];
    }
    NSString *memoMessage = self.memoMessage;
    if (memoMessage != nil) {
        [coder encodeObject:memoMessage forKey:@"memoMessage"];
    }
    MobileCoinPayment *mobileCoin = self.mobileCoin;
    if (mobileCoin != nil) {
        [coder encodeObject:mobileCoin forKey:@"mobileCoin"];
    }
    TSPaymentAmount *paymentAmount = self.paymentAmount;
    if (paymentAmount != nil) {
        [coder encodeObject:paymentAmount forKey:@"paymentAmount"];
    }
    [coder encodeObject:[self valueForKey:@"paymentFailure"] forKey:@"paymentFailure"];
    [coder encodeObject:[self valueForKey:@"paymentState"] forKey:@"paymentState"];
    [coder encodeObject:[self valueForKey:@"paymentType"] forKey:@"paymentType"];
    NSString *requestUuidString = self.requestUuidString;
    if (requestUuidString != nil) {
        [coder encodeObject:requestUuidString forKey:@"requestUuidString"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_addressUuidString = [coder decodeObjectOfClass:[NSString class] forKey:@"addressUuidString"];
    self->_createdTimestamp = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                               forKey:@"createdTimestamp"] unsignedLongLongValue];
    self->_interactionUniqueId = [coder decodeObjectOfClass:[NSString class] forKey:@"interactionUniqueId"];
    self->_isUnread = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:@"isUnread"] boolValue];
    self->_mcLedgerBlockIndex = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                                 forKey:@"mcLedgerBlockIndex"] unsignedLongLongValue];
    self->_mcReceiptData = [coder decodeObjectOfClass:[NSData class] forKey:@"mcReceiptData"];
    self->_mcTransactionData = [coder decodeObjectOfClass:[NSData class] forKey:@"mcTransactionData"];
    self->_memoMessage = [coder decodeObjectOfClass:[NSString class] forKey:@"memoMessage"];
    self->_mobileCoin = [coder decodeObjectOfClass:[MobileCoinPayment class] forKey:@"mobileCoin"];
    self->_paymentAmount = [coder decodeObjectOfClass:[TSPaymentAmount class] forKey:@"paymentAmount"];
    self->_paymentFailure = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                             forKey:@"paymentFailure"] unsignedIntegerValue];
    self->_paymentState = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                           forKey:@"paymentState"] unsignedIntegerValue];
    self->_paymentType = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                          forKey:@"paymentType"] unsignedIntegerValue];
    self->_requestUuidString = [coder decodeObjectOfClass:[NSString class] forKey:@"requestUuidString"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.addressUuidString.hash;
    result ^= self.createdTimestamp;
    result ^= self.interactionUniqueId.hash;
    result ^= self.isUnread;
    result ^= self.mcLedgerBlockIndex;
    result ^= self.mcReceiptData.hash;
    result ^= self.mcTransactionData.hash;
    result ^= self.memoMessage.hash;
    result ^= self.mobileCoin.hash;
    result ^= self.paymentAmount.hash;
    result ^= self.paymentFailure;
    result ^= self.paymentState;
    result ^= self.paymentType;
    result ^= self.requestUuidString.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    TSPaymentModel *typedOther = (TSPaymentModel *)other;
    if (![NSObject isObject:self.addressUuidString equalToObject:typedOther.addressUuidString]) {
        return NO;
    }
    if (self.createdTimestamp != typedOther.createdTimestamp) {
        return NO;
    }
    if (![NSObject isObject:self.interactionUniqueId equalToObject:typedOther.interactionUniqueId]) {
        return NO;
    }
    if (self.isUnread != typedOther.isUnread) {
        return NO;
    }
    if (self.mcLedgerBlockIndex != typedOther.mcLedgerBlockIndex) {
        return NO;
    }
    if (![NSObject isObject:self.mcReceiptData equalToObject:typedOther.mcReceiptData]) {
        return NO;
    }
    if (![NSObject isObject:self.mcTransactionData equalToObject:typedOther.mcTransactionData]) {
        return NO;
    }
    if (![NSObject isObject:self.memoMessage equalToObject:typedOther.memoMessage]) {
        return NO;
    }
    if (![NSObject isObject:self.mobileCoin equalToObject:typedOther.mobileCoin]) {
        return NO;
    }
    if (![NSObject isObject:self.paymentAmount equalToObject:typedOther.paymentAmount]) {
        return NO;
    }
    if (self.paymentFailure != typedOther.paymentFailure) {
        return NO;
    }
    if (self.paymentState != typedOther.paymentState) {
        return NO;
    }
    if (self.paymentType != typedOther.paymentType) {
        return NO;
    }
    if (![NSObject isObject:self.requestUuidString equalToObject:typedOther.requestUuidString]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TSPaymentModel *result = [self copyAndAssignIdsWithZone:zone];
    result->_addressUuidString = self.addressUuidString;
    result->_createdTimestamp = self.createdTimestamp;
    result->_interactionUniqueId = self.interactionUniqueId;
    result->_isUnread = self.isUnread;
    result->_mcLedgerBlockIndex = self.mcLedgerBlockIndex;
    result->_mcReceiptData = self.mcReceiptData;
    result->_mcTransactionData = self.mcTransactionData;
    result->_memoMessage = self.memoMessage;
    result->_mobileCoin = self.mobileCoin;
    result->_paymentAmount = self.paymentAmount;
    result->_paymentFailure = self.paymentFailure;
    result->_paymentState = self.paymentState;
    result->_paymentType = self.paymentType;
    result->_requestUuidString = self.requestUuidString;
    return result;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run
// `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
               addressUuidString:(nullable NSString *)addressUuidString
                createdTimestamp:(uint64_t)createdTimestamp
             interactionUniqueId:(nullable NSString *)interactionUniqueId
                        isUnread:(BOOL)isUnread
              mcLedgerBlockIndex:(uint64_t)mcLedgerBlockIndex
                   mcReceiptData:(nullable NSData *)mcReceiptData
               mcTransactionData:(nullable NSData *)mcTransactionData
                     memoMessage:(nullable NSString *)memoMessage
                      mobileCoin:(nullable MobileCoinPayment *)mobileCoin
                   paymentAmount:(nullable TSPaymentAmount *)paymentAmount
                  paymentFailure:(TSPaymentFailure)paymentFailure
                    paymentState:(TSPaymentState)paymentState
                     paymentType:(TSPaymentType)paymentType
               requestUuidString:(nullable NSString *)requestUuidString
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _addressUuidString = addressUuidString;
    _createdTimestamp = createdTimestamp;
    _interactionUniqueId = interactionUniqueId;
    _isUnread = isUnread;
    _mcLedgerBlockIndex = mcLedgerBlockIndex;
    _mcReceiptData = mcReceiptData;
    _mcTransactionData = mcTransactionData;
    _memoMessage = memoMessage;
    _mobileCoin = mobileCoin;
    _paymentAmount = paymentAmount;
    _paymentFailure = paymentFailure;
    _paymentState = paymentState;
    _paymentType = paymentType;
    _requestUuidString = requestUuidString;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (NSDate *)createdDate
{
    return [NSDate ows_dateWithMillisecondsSince1970:self.createdTimestamp];
}

- (nullable AciObjC *)senderOrRecipientAci
{
    return [[AciObjC alloc] initWithAciString:self.addressUuidString];
}

- (NSDate *)sortDate
{
    OWSAssertDebug(self.createdDate != nil);
    if (self.mcLedgerBlockDate != nil) {
        return self.mcLedgerBlockDate;
    }
    return self.createdDate;
}

- (void)updateWithPaymentState:(TSPaymentState)paymentState transaction:(DBWriteTransaction *)transaction
{
    [self anyUpdateWithTransaction:transaction
                             block:^(TSPaymentModel *paymentModel) {
                                 OWSAssertDebug([PaymentUtils isIncomingPaymentState:paymentModel.paymentState] ==
                                     [PaymentUtils isIncomingPaymentState:paymentState]);
                                 paymentModel.paymentState = paymentState;
                             }];
}

- (void)updateWithMCLedgerBlockIndex:(uint64_t)ledgerBlockIndex transaction:(DBWriteTransaction *)transaction
{
    OWSAssertDebug(ledgerBlockIndex > 0);

    [self anyUpdateWithTransaction:transaction
                             block:^(TSPaymentModel *paymentModel) {
                                 OWSAssertDebug(!paymentModel.hasMCLedgerBlockIndex);
                                 paymentModel.mobileCoin = [MobileCoinPayment copy:paymentModel.mobileCoin
                                                              withLedgerBlockIndex:ledgerBlockIndex];
                                 paymentModel.mcLedgerBlockIndex = ledgerBlockIndex;
                                 OWSAssertDebug(paymentModel.mobileCoin != nil);
                             }];
}

- (void)updateWithMCLedgerBlockTimestamp:(uint64_t)ledgerBlockTimestamp transaction:(DBWriteTransaction *)transaction
{
    OWSAssertDebug(ledgerBlockTimestamp > 0);

    [self anyUpdateWithTransaction:transaction
                             block:^(TSPaymentModel *paymentModel) {
                                 OWSAssertDebug(!paymentModel.hasMCLedgerBlockTimestamp);
                                 paymentModel.mobileCoin = [MobileCoinPayment copy:paymentModel.mobileCoin
                                                          withLedgerBlockTimestamp:ledgerBlockTimestamp];
                                 OWSAssertDebug(paymentModel.mobileCoin != nil);
                             }];
}

- (void)updateWithPaymentFailure:(TSPaymentFailure)paymentFailure
                    paymentState:(TSPaymentState)paymentState
                     transaction:(DBWriteTransaction *)transaction
{
    OWSAssertDebug(paymentFailure != TSPaymentFailureNone);
    OWSAssertDebug(paymentState == TSPaymentStateIncomingFailed || paymentState == TSPaymentStateOutgoingFailed);

    [self anyUpdateWithTransaction:transaction
                             block:^(TSPaymentModel *paymentModel) {
                                 OWSAssertDebug([PaymentUtils isIncomingPaymentState:paymentModel.paymentState] ==
                                     [PaymentUtils isIncomingPaymentState:paymentState]);

                                 paymentModel.paymentState = paymentState;
                                 paymentModel.paymentFailure = paymentFailure;

                                 // Scrub any MC state associated with the failure payment.
                                 paymentModel.mobileCoin = nil;
                                 paymentModel.mcLedgerBlockIndex = 0;
                                 paymentModel.mcTransactionData = nil;
                                 paymentModel.mcReceiptData = nil;
                             }];
}

- (void)updateWithPaymentAmount:(TSPaymentAmount *)paymentAmount transaction:(DBWriteTransaction *)transaction
{
    [self anyUpdateWithTransaction:transaction
                             block:^(TSPaymentModel *paymentModel) {
                                 OWSAssertDebug(paymentModel.paymentAmount == nil
                                     || (paymentModel.paymentAmount.currency == paymentAmount.currency
                                         && paymentModel.paymentAmount.picoMob == paymentAmount.picoMob));
                                 paymentModel.paymentAmount = paymentAmount;
                             }];
}

- (void)updateWithIsUnread:(BOOL)isUnread transaction:(DBWriteTransaction *)transaction
{
    [self anyUpdateWithTransaction:transaction
                             block:^(TSPaymentModel *paymentModel) { paymentModel.isUnread = isUnread; }];
}

- (void)updateWithInteractionUniqueId:(NSString *)interactionUniqueId transaction:(DBWriteTransaction *)transaction
{
    [self anyUpdateWithTransaction:transaction
                             block:^(TSPaymentModel *paymentModel) {
                                 paymentModel.interactionUniqueId = interactionUniqueId;
                             }];
}

#pragma mark -

- (void)anyWillInsertWithTransaction:(DBWriteTransaction *)transaction
{
    OWSAssertDebug(self.isValid);

    [super anyWillInsertWithTransaction:transaction];

    [SSKEnvironment.shared.paymentsEventsRef willInsertPayment:self transaction:transaction];
}

- (void)anyDidInsertWithTransaction:(DBWriteTransaction *)transaction
{
    OWSAssertDebug(self.isValid);

    [super anyDidInsertWithTransaction:transaction];
}

- (void)anyWillUpdateWithTransaction:(DBWriteTransaction *)transaction
{
    OWSAssertDebug(self.isValid);

    [super anyWillUpdateWithTransaction:transaction];

    [SSKEnvironment.shared.paymentsEventsRef willUpdatePayment:self transaction:transaction];
}

- (void)anyDidUpdateWithTransaction:(DBWriteTransaction *)transaction
{
    OWSAssertDebug(self.isValid);

    [super anyDidUpdateWithTransaction:transaction];
}

@end

#pragma mark -

@implementation MobileCoinPayment

- (instancetype)initWithRecipientPublicAddressData:(nullable NSData *)recipientPublicAddressData
                                   transactionData:(nullable NSData *)transactionData
                                       receiptData:(nullable NSData *)receiptData
                     incomingTransactionPublicKeys:(nullable NSArray<NSData *> *)incomingTransactionPublicKeys
                                    spentKeyImages:(nullable NSArray<NSData *> *)spentKeyImages
                                  outputPublicKeys:(nullable NSArray<NSData *> *)outputPublicKeys
                              ledgerBlockTimestamp:(uint64_t)ledgerBlockTimestamp
                                  ledgerBlockIndex:(uint64_t)ledgerBlockIndex
                                         feeAmount:(nullable TSPaymentAmount *)feeAmount
{
    self = [super init];

    if (!self) {
        return self;
    }

    _recipientPublicAddressData = recipientPublicAddressData;
    _transactionData = transactionData;
    _receiptData = receiptData;
    _incomingTransactionPublicKeys = incomingTransactionPublicKeys;
    _spentKeyImages = spentKeyImages;
    _outputPublicKeys = outputPublicKeys;
    _ledgerBlockTimestamp = ledgerBlockTimestamp;
    _ledgerBlockIndex = ledgerBlockIndex;
    _feeAmount = feeAmount;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    TSPaymentAmount *feeAmount = self.feeAmount;
    if (feeAmount != nil) {
        [coder encodeObject:feeAmount forKey:@"feeAmount"];
    }
    NSArray *incomingTransactionPublicKeys = self.incomingTransactionPublicKeys;
    if (incomingTransactionPublicKeys != nil) {
        [coder encodeObject:incomingTransactionPublicKeys forKey:@"incomingTransactionPublicKeys"];
    }
    [coder encodeObject:[self valueForKey:@"ledgerBlockIndex"] forKey:@"ledgerBlockIndex"];
    [coder encodeObject:[self valueForKey:@"ledgerBlockTimestamp"] forKey:@"ledgerBlockTimestamp"];
    NSArray *outputPublicKeys = self.outputPublicKeys;
    if (outputPublicKeys != nil) {
        [coder encodeObject:outputPublicKeys forKey:@"outputPublicKeys"];
    }
    NSData *receiptData = self.receiptData;
    if (receiptData != nil) {
        [coder encodeObject:receiptData forKey:@"receiptData"];
    }
    NSData *recipientPublicAddressData = self.recipientPublicAddressData;
    if (recipientPublicAddressData != nil) {
        [coder encodeObject:recipientPublicAddressData forKey:@"recipientPublicAddressData"];
    }
    NSArray *spentKeyImages = self.spentKeyImages;
    if (spentKeyImages != nil) {
        [coder encodeObject:spentKeyImages forKey:@"spentKeyImages"];
    }
    NSData *transactionData = self.transactionData;
    if (transactionData != nil) {
        [coder encodeObject:transactionData forKey:@"transactionData"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_feeAmount = [coder decodeObjectOfClass:[TSPaymentAmount class] forKey:@"feeAmount"];
    self->_incomingTransactionPublicKeys =
        [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [NSData class] ]]
                              forKey:@"incomingTransactionPublicKeys"];
    self->_ledgerBlockIndex = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                               forKey:@"ledgerBlockIndex"] unsignedLongLongValue];
    self->_ledgerBlockTimestamp =
        [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:@"ledgerBlockTimestamp"] unsignedLongLongValue];
    self->_outputPublicKeys = [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [NSData class] ]]
                                                    forKey:@"outputPublicKeys"];
    self->_receiptData = [coder decodeObjectOfClass:[NSData class] forKey:@"receiptData"];
    self->_recipientPublicAddressData = [coder decodeObjectOfClass:[NSData class] forKey:@"recipientPublicAddressData"];
    self->_spentKeyImages = [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [NSData class] ]]
                                                  forKey:@"spentKeyImages"];
    self->_transactionData = [coder decodeObjectOfClass:[NSData class] forKey:@"transactionData"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.feeAmount.hash;
    result ^= self.incomingTransactionPublicKeys.hash;
    result ^= self.ledgerBlockIndex;
    result ^= self.ledgerBlockTimestamp;
    result ^= self.outputPublicKeys.hash;
    result ^= self.receiptData.hash;
    result ^= self.recipientPublicAddressData.hash;
    result ^= self.spentKeyImages.hash;
    result ^= self.transactionData.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    MobileCoinPayment *typedOther = (MobileCoinPayment *)other;
    if (![NSObject isObject:self.feeAmount equalToObject:typedOther.feeAmount]) {
        return NO;
    }
    if (![NSObject isObject:self.incomingTransactionPublicKeys
              equalToObject:typedOther.incomingTransactionPublicKeys]) {
        return NO;
    }
    if (self.ledgerBlockIndex != typedOther.ledgerBlockIndex) {
        return NO;
    }
    if (self.ledgerBlockTimestamp != typedOther.ledgerBlockTimestamp) {
        return NO;
    }
    if (![NSObject isObject:self.outputPublicKeys equalToObject:typedOther.outputPublicKeys]) {
        return NO;
    }
    if (![NSObject isObject:self.receiptData equalToObject:typedOther.receiptData]) {
        return NO;
    }
    if (![NSObject isObject:self.recipientPublicAddressData equalToObject:typedOther.recipientPublicAddressData]) {
        return NO;
    }
    if (![NSObject isObject:self.spentKeyImages equalToObject:typedOther.spentKeyImages]) {
        return NO;
    }
    if (![NSObject isObject:self.transactionData equalToObject:typedOther.transactionData]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    MobileCoinPayment *result = [[[self class] allocWithZone:zone] init];
    result->_feeAmount = self.feeAmount;
    result->_incomingTransactionPublicKeys = self.incomingTransactionPublicKeys;
    result->_ledgerBlockIndex = self.ledgerBlockIndex;
    result->_ledgerBlockTimestamp = self.ledgerBlockTimestamp;
    result->_outputPublicKeys = self.outputPublicKeys;
    result->_receiptData = self.receiptData;
    result->_recipientPublicAddressData = self.recipientPublicAddressData;
    result->_spentKeyImages = self.spentKeyImages;
    result->_transactionData = self.transactionData;
    return result;
}

- (nullable NSDate *)ledgerBlockDate
{
    if (self.ledgerBlockTimestamp > 0) {
        return [NSDate ows_dateWithMillisecondsSince1970:self.ledgerBlockTimestamp];
    } else {
        return nil;
    }
}

+ (MobileCoinPayment *)copy:(nullable MobileCoinPayment *)oldCopy withLedgerBlockIndex:(uint64_t)ledgerBlockIndex
{
    OWSAssertDebug(ledgerBlockIndex > 0);

    MobileCoinPayment *newCopy = (oldCopy != nil ? [oldCopy copy] : [MobileCoinPayment new]);
    newCopy.ledgerBlockIndex = ledgerBlockIndex;
    return newCopy;
}

+ (MobileCoinPayment *)copy:(nullable MobileCoinPayment *)oldCopy
    withLedgerBlockTimestamp:(uint64_t)ledgerBlockTimestamp
{
    OWSAssertDebug(ledgerBlockTimestamp > 0);

    MobileCoinPayment *newCopy = (oldCopy != nil ? [oldCopy copy] : [MobileCoinPayment new]);
    newCopy.ledgerBlockTimestamp = ledgerBlockTimestamp;
    return newCopy;
}


@end

NS_ASSUME_NONNULL_END
