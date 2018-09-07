//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSViewController.h"
#import "UIView+OWS.h"
#import <SignalMessaging/Theme.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSViewController ()

@property (nonatomic, weak) UIView *bottomLayoutView;
@property (nonatomic) NSLayoutConstraint *bottomLayoutConstraint;

@end

#pragma mark -

@implementation OWSViewController

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation of view controllers.
    OWSLogVerbose(@"Dealloc: %@", self.class);

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) {
        self.shouldUseTheme = YES;
        return self;
    }

    [self observeActivation];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        self.shouldUseTheme = YES;
        return self;
    }

    [self observeActivation];

    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    if (self.shouldUseTheme) {
        self.view.backgroundColor = Theme.backgroundColor;
    }
}

- (void)autoPinViewToBottomOfViewControllerOrKeyboard:(UIView *)view avoidNotch:(BOOL)avoidNotch
{
    OWSAssertDebug(view);
    OWSAssertDebug(!self.bottomLayoutConstraint);

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidShow:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidHide:)
                                                 name:UIKeyboardDidHideNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidChangeFrame:)
                                                 name:UIKeyboardDidChangeFrameNotification
                                               object:nil];

    self.bottomLayoutView = view;
    if (avoidNotch) {
        self.bottomLayoutConstraint = [view autoPinToBottomLayoutGuideOfViewController:self withInset:0.f];
    } else {
        self.bottomLayoutConstraint = [view autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.view];
    }
}

- (void)observeActivation
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(owsViewControllerApplicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)owsViewControllerApplicationDidBecomeActive:(NSNotification *)notification
{
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)keyboardWillShow:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardDidShow:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardDidHide:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardWillChangeFrame:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardDidChangeFrame:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)handleKeyboardNotification:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    if (self.shouldIgnoreKeyboardChanges) {
        return;
    }

    NSDictionary *userInfo = [notification userInfo];

    NSValue *_Nullable keyboardEndFrameValue = userInfo[UIKeyboardFrameEndUserInfoKey];
    if (!keyboardEndFrameValue) {
        OWSFailDebug(@"Missing keyboard end frame");
        return;
    }

    CGRect keyboardEndFrame = [keyboardEndFrameValue CGRectValue];
    CGRect keyboardEndFrameConverted = [self.view convertRect:keyboardEndFrame fromView:nil];
    // Adjust the position of the bottom view to account for the keyboard's
    // intrusion into the view.
    //
    // On iPhoneX, when no keyboard is present, we include a buffer at the bottom of the screen so the bottom view
    // clears the floating "home button". But because the keyboard includes it's own buffer, we subtract the length
    // (height) of the bottomLayoutGuide, else we'd have an unnecessary buffer between the popped keyboard and the input
    // bar.
    CGFloat offset = -MAX(0, (self.view.height - self.bottomLayoutGuide.length - keyboardEndFrameConverted.origin.y));

    // There's no need to use: [UIView animateWithDuration:...].
    // Any layout changes made during these notifications are
    // automatically animated.
    self.bottomLayoutConstraint.constant = offset;
    [self.bottomLayoutView.superview layoutIfNeeded];
}

@end

NS_ASSUME_NONNULL_END
