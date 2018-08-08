//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSViewController : UIViewController

@property (nonatomic) BOOL shouldIgnoreKeyboardChanges;

@property (nonatomic) BOOL shouldUseTheme;

// We often want to pin one view to the bottom of a view controller
// BUT adjust its location upward if the keyboard appears.
- (void)autoPinViewToBottomOfViewControllerOrKeyboard:(UIView *)view avoidNotch:(BOOL)avoidNotch;

@end

NS_ASSUME_NONNULL_END
