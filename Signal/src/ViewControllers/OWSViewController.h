//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSViewController : UIViewController

// We often want to pin one view to the bottom guide
// of a view controller BUT adjust its location upward
// if the keyboard appears.
//
// Use this method in lieu of autoPinToBottomLayoutGuideOfViewController:
- (void)autoPinViewToBottomGuideOrKeyboard:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
