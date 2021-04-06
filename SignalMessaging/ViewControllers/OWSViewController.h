//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSViewController : UIViewController

@property (nonatomic) BOOL shouldIgnoreKeyboardChanges;

@property (nonatomic) BOOL shouldUseTheme;

// We often want to pin one view to the bottom of a view controller
// BUT adjust its location upward if the keyboard appears.
- (NSLayoutConstraint *)autoPinViewToBottomOfViewControllerOrKeyboard:(UIView *)view avoidNotch:(BOOL)avoidNotch;

// Override point for any custom handling of keyboard constraint insets
// Invoked while embedded in an appropriate UIAnimationCurve
// Default implementation sets the underlying keyboard constraint offset to `after`
- (void)updateBottomLayoutConstraintFromInset:(CGFloat)before toInset:(CGFloat)after;

// If YES, the bottom view never "reclaims" layout space if the keyboard is dismissed.
// Defaults to NO.
@property (nonatomic) BOOL shouldBottomViewReserveSpaceForKeyboard;

- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)themeDidChange;
- (void)applyTheme;

@end

NS_ASSUME_NONNULL_END
