//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalMessaging/OWSProfileManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSProfileManager (SignalUI)

- (void)presentAddThreadToProfileWhitelist:(TSThread *)thread
                        fromViewController:(UIViewController *)fromViewController
                                   success:(void (^)(void))successHandler;

@end

NS_ASSUME_NONNULL_END
