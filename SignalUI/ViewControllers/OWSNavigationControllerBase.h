//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// This subclass exists purely to expose UINavigationController's implementation of
/// UINavigationBarDelegate to the swift subclass OWSNavigationController. Objc
/// can force a call to the superclass' implenentation of navigationBar(: shouldPopItem:) but
/// swift can't do that, so we wrap it in objc.
@interface OWSNavigationControllerBase : UINavigationController

- (BOOL)ows_navigationBar:(UINavigationBar *)navigationBar shouldPopItem:(UINavigationItem *)item;

@end

NS_ASSUME_NONNULL_END
