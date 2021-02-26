//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSPaymentCancellation;
@class TSPaymentNotification;
@class TSPaymentRequest;

@interface OWSOutgoingPaymentMessage : TSOutgoingMessage

@property (nonatomic, readonly, nullable) TSPaymentRequest *paymentRequest;
@property (nonatomic, readonly, nullable) TSPaymentNotification *paymentNotification;
@property (nonatomic, readonly, nullable) TSPaymentCancellation *paymentCancellation;

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
           paymentCancellation:(nullable TSPaymentCancellation *)paymentCancellation
           paymentNotification:(nullable TSPaymentNotification *)paymentNotification
                paymentRequest:(nullable TSPaymentRequest *)paymentRequest;

@end

NS_ASSUME_NONNULL_END
