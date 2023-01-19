//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface RegistrationUtils : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (void)showRelinkingUI;
+ (void)showReregistrationUIFromViewController:(UIViewController *)fromViewController;

@end

NS_ASSUME_NONNULL_END
