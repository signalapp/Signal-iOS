//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSPaymentActivationRequestFinishedMessage.h"
#import "ProfileManagerProtocol.h"
#import "ProtoUtils.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSPaymentActivationRequestFinishedMessage

- (instancetype)initWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    return [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];
}


- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoDataMessageBuilder *builder = [super dataMessageBuilderWithThread:thread transaction:transaction];

    SSKProtoDataMessagePaymentActivationBuilder *activationBuilder = [SSKProtoDataMessagePaymentActivation builder];
    [activationBuilder setType:SSKProtoDataMessagePaymentActivationTypeActivated];
    NSError *error;
    SSKProtoDataMessagePaymentActivation *activation = [activationBuilder buildAndReturnError:&error];
    if (error || !activation) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoDataMessagePaymentBuilder *paymentBuilder = [SSKProtoDataMessagePayment builder];
    [paymentBuilder setActivation:activation];
    SSKProtoDataMessagePayment *payment = [paymentBuilder buildAndReturnError:&error];
    if (error || !payment) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    [builder setPayment:payment];

    [builder setRequiredProtocolVersion:(uint32_t)SSKProtoDataMessageProtocolVersionPayments];
    return builder;
}

- (SealedSenderContentHint)contentHint
{
    return SealedSenderContentHintImplicit;
}

- (BOOL)hasRenderableContent
{
    return NO;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
