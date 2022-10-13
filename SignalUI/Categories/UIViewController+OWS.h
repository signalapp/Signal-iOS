//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (OWS)

- (UIViewController *)findFrontmostViewController:(BOOL)ignoringAlerts;

@end

NS_ASSUME_NONNULL_END
