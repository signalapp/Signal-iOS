//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@protocol MobileCoinHelper;
@protocol PaymentsEvents;
@protocol WebSocketFactory;

// This is _NOT_ a singleton and will be instantiated each time that the SAE is used.
@interface AppSetup : NSObject

+ (void)setupEnvironmentWithPaymentsEvents:(id<PaymentsEvents>)paymentsEvents
                          mobileCoinHelper:(id<MobileCoinHelper>)mobileCoinHelper
                          webSocketFactory:(id<WebSocketFactory>)webSocketFactory
                 appSpecificSingletonBlock:(NS_NOESCAPE dispatch_block_t)appSpecificSingletonBlock
                       migrationCompletion:(void (^)(NSError *_Nullable error))migrationCompletion
NS_SWIFT_NAME(setupEnvironment(paymentsEvents:mobileCoinHelper:webSocketFactory:appSpecificSingletonBlock:migrationCompletion:));

@end

NS_ASSUME_NONNULL_END
