//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ScreenLockViewController.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>

NSString *NSStringForScreenLockUIState(ScreenLockUIState value)
{
    switch (value) {
        case ScreenLockUIStateNone:
            return @"ScreenLockUIStateNone";
        case ScreenLockUIStateScreenProtection:
            return @"ScreenLockUIStateScreenProtection";
        case ScreenLockUIStateScreenLock:
            return @"ScreenLockUIStateScreenLock";
    }
}

@interface ScreenLockViewController ()

@property (nonatomic) UIView *screenBlockingImageView;
@property (nonatomic) UIView *screenBlockingButton;
@property (nonatomic) NSArray<NSLayoutConstraint *> *screenBlockingConstraints;
@property (nonatomic) NSString *screenBlockingSignature;

@end

#pragma mark -

@implementation ScreenLockViewController

- (void)loadView
{
    [super loadView];

    self.view.backgroundColor = UIColor.ows_materialBlueColor;

    UIView *edgesView = [UIView containerView];
    [self.view addSubview:edgesView];
    [edgesView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [edgesView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [edgesView autoPinWidthToSuperview];

    UIImage *image = [UIImage imageNamed:@"logoSignal"];
    UIImageView *imageView = [UIImageView new];
    imageView.image = image;
    [edgesView addSubview:imageView];
    [imageView autoHCenterInSuperview];

    const CGSize screenSize = UIScreen.mainScreen.bounds.size;
    const CGFloat shortScreenDimension = MIN(screenSize.width, screenSize.height);
    const CGFloat imageSize = (CGFloat)round(shortScreenDimension / 3.f);
    [imageView autoSetDimension:ALDimensionWidth toSize:imageSize];
    [imageView autoSetDimension:ALDimensionHeight toSize:imageSize];

    const CGFloat kButtonHeight = 40.f;
    OWSFlatButton *button =
        [OWSFlatButton buttonWithTitle:NSLocalizedString(@"SCREEN_LOCK_UNLOCK_SIGNAL",
                                           @"Label for button on lock screen that lets users unlock Signal.")
                                  font:[OWSFlatButton fontForHeight:kButtonHeight]
                            titleColor:[UIColor ows_materialBlueColor]
                       backgroundColor:[UIColor whiteColor]
                                target:self
                              selector:@selector(showUnlockUI)];
    [edgesView addSubview:button];

    [button autoSetDimension:ALDimensionHeight toSize:kButtonHeight];
    [button autoPinLeadingToSuperviewMarginWithInset:50.f];
    [button autoPinTrailingToSuperviewMarginWithInset:50.f];
    const CGFloat kVMargin = 65.f;
    [button autoPinBottomToSuperviewMarginWithInset:kVMargin];

    self.screenBlockingImageView = imageView;
    self.screenBlockingButton = button;

    [self updateUIWithState:ScreenLockUIStateScreenProtection isLogoAtTop:NO animated:NO];
}

// The "screen blocking" window has three possible states:
//
// * "Just a logo".  Used when app is launching and in app switcher.  Must match the "Launch Screen"
//    storyboard pixel-for-pixel.
// * "Screen Lock, local auth UI presented". Move the Signal logo so that it is visible.
// * "Screen Lock, local auth UI not presented". Move the Signal logo so that it is visible,
//    show "unlock" button.
- (void)updateUIWithState:(ScreenLockUIState)uiState isLogoAtTop:(BOOL)isLogoAtTop animated:(BOOL)animated
{
    OWSAssertIsOnMainThread();

    if (!self.isViewLoaded) {
        return;
    }

    BOOL shouldShowBlockWindow = uiState != ScreenLockUIStateNone;
    BOOL shouldHaveScreenLock = uiState == ScreenLockUIStateScreenLock;

    self.screenBlockingImageView.hidden = !shouldShowBlockWindow;

    NSString *signature = [NSString stringWithFormat:@"%d %d", shouldHaveScreenLock, isLogoAtTop];
    if ([NSObject isNullableObject:self.screenBlockingSignature equalTo:signature]) {
        // Skip redundant work to avoid interfering with ongoing animations.
        return;
    }

    [NSLayoutConstraint deactivateConstraints:self.screenBlockingConstraints];

    NSMutableArray<NSLayoutConstraint *> *screenBlockingConstraints = [NSMutableArray new];

    self.screenBlockingButton.hidden = !shouldHaveScreenLock;

    if (isLogoAtTop) {
        const CGFloat kVMargin = 60.f;
        [screenBlockingConstraints addObject:[self.screenBlockingImageView autoPinEdge:ALEdgeTop
                                                                                toEdge:ALEdgeTop
                                                                                ofView:self.view
                                                                            withOffset:kVMargin]];
    } else {
        [screenBlockingConstraints addObject:[self.screenBlockingImageView autoVCenterInSuperview]];
    }

    self.screenBlockingConstraints = screenBlockingConstraints;
    self.screenBlockingSignature = signature;

    if (animated) {
        [UIView animateWithDuration:0.35f
                         animations:^{
                             [self.view layoutIfNeeded];
                         }];
    } else {
        [self.view layoutIfNeeded];
    }
}

- (void)showUnlockUI
{
    OWSAssertIsOnMainThread();

    [self.delegate unlockButtonWasTapped];
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

@end
