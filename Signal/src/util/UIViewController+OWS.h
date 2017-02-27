//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (OWS)

- (UIBarButtonItem *)createOWSBackButtonWithSelector:(SEL)selector;
- (UIBarButtonItem *)createOWSBackButton;
- (void)useOWSBackButtonWithSelector:(SEL)selector;
- (void)useOWSBackButton;

@end

NS_ASSUME_NONNULL_END
