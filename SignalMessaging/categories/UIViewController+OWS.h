//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (OWS)

- (UIViewController *)findFrontmostViewController:(BOOL)ignoringAlerts;

/**
 * Takes up a bit less space than the default system back button
 * used in the MessagesViewController to help left-align the title view.
 *
 * **note** Using this breaks the interactive pop gesture (swipe back) unless you set/unset the
 * interactivePopGesture.delegate to self/nil on viewWillAppear/Disappear
 */
- (UIBarButtonItem *)createOWSBackButton;

+ (UIBarButtonItem *)createOWSBackButtonWithTarget:(id)target selector:(SEL)selector;

@end

NS_ASSUME_NONNULL_END
