//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSViewController : UIViewController

@property (nonatomic) BOOL shouldIgnoreKeyboardChanges;

@property (nonatomic) BOOL shouldUseTheme;

// We often want to pin one view to the bottom of a view controller
// BUT adjust its location upward if the keyboard appears.
- (void)autoPinViewToBottomOfViewControllerOrKeyboard:(UIView *)view avoidNotch:(BOOL)avoidNotch;

// If YES, the bottom view never "reclaims" layout space if the keyboard is dismissed.
// Defaults to NO.
@property (nonatomic) BOOL shouldBottomViewReserveSpaceForKeyboard;

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
