//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSPaymentRequestModel.h"
#import "TSPaymentModels.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation TSPaymentRequestModel

- (instancetype)initWithRequestUuidString:(NSString *)requestUuidString
                        addressUuidString:(NSString *)addressUuidString
                        isIncomingRequest:(BOOL)isIncomingRequest
                            paymentAmount:(TSPaymentAmount *)paymentAmount
                              memoMessage:(nullable NSString *)memoMessage
                              createdDate:(NSDate *)createdDate
{
    self = [super init];

    if (!self) {
        return self;
    }

    _requestUuidString = requestUuidString;
    _addressUuidString = addressUuidString;
    _isIncomingRequest = isIncomingRequest;
    _paymentAmount = paymentAmount;
    _memoMessage = memoMessage;
    _createdTimestamp = createdDate.ows_millisecondsSince1970;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
               addressUuidString:(NSString *)addressUuidString
                createdTimestamp:(uint64_t)createdTimestamp
               isIncomingRequest:(BOOL)isIncomingRequest
                     memoMessage:(nullable NSString *)memoMessage
                   paymentAmount:(TSPaymentAmount *)paymentAmount
               requestUuidString:(NSString *)requestUuidString
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _addressUuidString = addressUuidString;
    _createdTimestamp = createdTimestamp;
    _isIncomingRequest = isIncomingRequest;
    _memoMessage = memoMessage;
    _paymentAmount = paymentAmount;
    _requestUuidString = requestUuidString;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (NSDate *)createdDate
{
    return [NSDate ows_dateWithMillisecondsSince1970:self.createdTimestamp];
}

- (NSUUID *)addressUuid
{
    OWSAssertDebug(self.addressUuidString.length > 0);
    return [[NSUUID alloc] initWithUUIDString:self.addressUuidString];
}

- (SignalServiceAddress *)address
{
    OWSAssertDebug(self.addressUuid != nil);
    return [[SignalServiceAddress alloc] initWithUuid:self.addressUuid];
}

@end

NS_ASSUME_NONNULL_END
