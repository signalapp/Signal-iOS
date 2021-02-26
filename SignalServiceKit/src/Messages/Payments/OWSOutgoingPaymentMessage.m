//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingPaymentMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingPaymentMessage ()

@end

#pragma mark -

@implementation OWSOutgoingPaymentMessage

- (instancetype)initWithThread:(TSThread *)thread
           paymentCancellation:(nullable TSPaymentCancellation *)paymentCancellation
           paymentNotification:(nullable TSPaymentNotification *)paymentNotification
                paymentRequest:(nullable TSPaymentRequest *)paymentRequest
{
    OWSAssertDebug(paymentCancellation != nil || paymentNotification != nil || paymentRequest != nil);

    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder];
    if (!self) {
        return self;
    }

    _paymentCancellation = paymentCancellation;
    _paymentNotification = paymentNotification;
    _paymentRequest = paymentRequest;

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(SDSAnyReadTransaction *)transaction
{
    if (self.paymentCancellation == nil && self.paymentNotification == nil && self.paymentRequest == nil) {
        OWSFailDebug(@"Missing payload.");
        return nil;
    }

    SSKProtoDataMessageBuilder *builder = [super dataMessageBuilderWithThread:thread transaction:transaction];
    [builder setTimestamp:self.timestamp];

    if (self.paymentRequest != nil) {
        NSError *error;
        BOOL success = [self.paymentRequest addToDataBuilder:builder error:&error];
        if (error || !success) {
            OWSFailDebug(@"Could not build paymentRequest proto: %@.", error);
        }
    } else if (self.paymentNotification != nil) {
        NSError *error;
        BOOL success = [self.paymentNotification addToDataBuilder:builder error:&error];
        if (error || !success) {
            OWSFailDebug(@"Could not build paymentNotification proto: %@.", error);
        }
    } else if (self.paymentCancellation != nil) {
        NSError *error;
        BOOL success = [self.paymentCancellation addToDataBuilder:builder error:&error];
        if (error || !success) {
            OWSFailDebug(@"Could not build paymentCancellation proto: %@.", error);
        }
    }

    [builder setRequiredProtocolVersion:(uint32_t)SSKProtoDataMessageProtocolVersionPayments];
    return builder;
}

@end

NS_ASSUME_NONNULL_END
