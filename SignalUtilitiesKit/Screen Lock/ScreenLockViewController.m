//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ScreenLockViewController.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SessionUIKit/SessionUIKit.h>

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
    
    // Loki: Set gradient background
    self.view.backgroundColor = UIColor.clearColor;
    CAGradientLayer *layer = [CAGradientLayer new];
    layer.frame = UIScreen.mainScreen.bounds;
    UIColor *gradientStartColor = LKAppModeUtilities.isLightMode ? [UIColor colorWithRGBHex:0xF9F9F9] : [UIColor colorWithRGBHex:0x171717];
    UIColor *gradientEndColor = LKAppModeUtilities.isLightMode ? [UIColor colorWithRGBHex:0xFFFFFF] : [UIColor colorWithRGBHex:0x121212];
    layer.colors = @[ (id)gradientStartColor.CGColor, (id)gradientEndColor.CGColor ];
    [self.view.layer insertSublayer:layer atIndex:0];

    UIView *edgesView = [UIView containerView];
    [self.view addSubview:edgesView];
    [edgesView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [edgesView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [edgesView autoPinWidthToSuperview];

    UIImage *image = [UIImage imageNamed:@"SessionGreen64"];
    UIImageView *imageView = [UIImageView new];
    imageView.image = image;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    [edgesView addSubview:imageView];
    [imageView autoHCenterInSuperview];

    [imageView autoSetDimension:ALDimensionWidth toSize:64];
    [imageView autoSetDimension:ALDimensionHeight toSize:64];

    const CGFloat kButtonHeight = 40.f;
    OWSFlatButton *button =
        [OWSFlatButton buttonWithTitle:NSLocalizedString(@"Unlock Session", @"")
                                  font:[UIFont boldSystemFontOfSize:LKValues.mediumFontSize]
                            titleColor:LKAppModeUtilities.isLightMode ? UIColor.blackColor : UIColor.whiteColor
                       backgroundColor:UIColor.clearColor
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
