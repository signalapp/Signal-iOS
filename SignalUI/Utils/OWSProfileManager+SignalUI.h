//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSProfileManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSProfileManager (SignalUI)

- (void)presentAddThreadToProfileWhitelist:(TSThread *)thread
                        fromViewController:(UIViewController *)fromViewController
                                   success:(void (^)(void))successHandler;

@end

NS_ASSUME_NONNULL_END
