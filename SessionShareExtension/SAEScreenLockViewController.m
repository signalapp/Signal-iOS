//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SAEScreenLockViewController.h"
#import "UIColor+OWS.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SessionUtilitiesKit/AppContext.h>

NS_ASSUME_NONNULL_BEGIN

@interface SAEScreenLockViewController () <ScreenLockViewDelegate>

@property (nonatomic, readonly, weak) id<ShareViewDelegate> shareViewDelegate;

@property (nonatomic) BOOL hasShownAuthUIOnce;

@property (nonatomic) BOOL isShowingAuthUI;

@end

#pragma mark -

@implementation SAEScreenLockViewController

- (instancetype)initWithShareViewDelegate:(id<ShareViewDelegate>)shareViewDelegate
{
    self = [super init];
    if (!self) {
        return self;
    }

    _shareViewDelegate = shareViewDelegate;

    self.delegate = self;

    return self;
}

- (void)loadView
{
    [super loadView];

    UIView.appearance.tintColor = LKColors.text;
    
    // Loki: Set gradient background
    self.view.backgroundColor = UIColor.clearColor;
    CAGradientLayer *layer = [CAGradientLayer new];
    layer.frame = UIScreen.mainScreen.bounds;
    UIColor *gradientStartColor = LKAppModeUtilities.isLightMode ? [UIColor colorWithRGBHex:0xFCFCFC] : [UIColor colorWithRGBHex:0x171717];
    UIColor *gradientEndColor = LKAppModeUtilities.isLightMode ? [UIColor colorWithRGBHex:0xFFFFFF] : [UIColor colorWithRGBHex:0x121212];
    layer.colors = @[ (id)gradientStartColor.CGColor, (id)gradientEndColor.CGColor ];
    [self.view.layer insertSublayer:layer atIndex:0];
    
    // Loki: Set navigation bar background color
    UINavigationBar *navigationBar = self.navigationController.navigationBar;
    [navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    navigationBar.shadowImage = [UIImage new];
    [navigationBar setTranslucent:NO];
    navigationBar.barTintColor = LKColors.navigationBarBackground;

    // Loki: Customize title
    UILabel *titleLabel = [UILabel new];
    titleLabel.text = NSLocalizedString(@"Share to Session", @"");
    titleLabel.textColor = LKColors.text;
    titleLabel.font = [UIFont boldSystemFontOfSize:LKValues.veryLargeFontSize];
    self.navigationItem.titleView = titleLabel;

    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"X"] style:UIBarButtonItemStylePlain target:self action:@selector(dismissPressed:)];
    closeButton.tintColor = LKColors.text;
    self.navigationItem.leftBarButtonItem = closeButton;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self ensureUI];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self ensureUI];

    // Auto-show the auth UI f
    if (!self.hasShownAuthUIOnce) {
        self.hasShownAuthUIOnce = YES;

        [self tryToPresentAuthUIToUnlockScreenLock];
    }
}

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation of view controllers.
    OWSLogVerbose(@"Dealloc: %@", self.class);
}

- (void)tryToPresentAuthUIToUnlockScreenLock
{
    OWSAssertIsOnMainThread();

    if (self.isShowingAuthUI) {
        // We're already showing the auth UI; abort.
        return;
    }
    OWSLogInfo(@"try to unlock screen lock");

    self.isShowingAuthUI = YES;

    [OWSScreenLock.sharedManager tryToUnlockScreenLockWithSuccess:^{
        OWSAssertIsOnMainThread();

        OWSLogInfo(@"unlock screen lock succeeded.");

        self.isShowingAuthUI = NO;

        [self.shareViewDelegate shareViewWasUnlocked];
    }
        failure:^(NSError *error) {
            OWSAssertIsOnMainThread();

            OWSLogInfo(@"unlock screen lock failed.");

            self.isShowingAuthUI = NO;

            [self ensureUI];

            [self showScreenLockFailureAlertWithMessage:error.localizedDescription];
        }
        unexpectedFailure:^(NSError *error) {
            OWSAssertIsOnMainThread();

            OWSLogInfo(@"unlock screen lock unexpectedly failed.");

            self.isShowingAuthUI = NO;

            // Local Authentication isn't working properly.
            // This isn't covered by the docs or the forums but in practice
            // it appears to be effective to retry again after waiting a bit.
            dispatch_async(dispatch_get_main_queue(), ^{
                [self ensureUI];
            });
        }
        cancel:^{
            OWSAssertIsOnMainThread();

            OWSLogInfo(@"unlock screen lock cancelled.");

            self.isShowingAuthUI = NO;

            [self ensureUI];
        }];

    [self ensureUI];
}

- (void)ensureUI
{
    [self updateUIWithState:ScreenLockUIStateScreenLock isLogoAtTop:NO animated:NO];
}

- (void)showScreenLockFailureAlertWithMessage:(NSString *)message
{
    OWSAssertIsOnMainThread();

    [OWSAlerts showAlertWithTitle:NSLocalizedString(@"SCREEN_LOCK_UNLOCK_FAILED",
                                      @"Title for alert indicating that screen lock could not be unlocked.")
                          message:message
                      buttonTitle:nil
                     buttonAction:^(UIAlertAction *action) {
                         // After the alert, update the UI.
                         [self ensureUI];
                     }
               fromViewController:self];
}

- (void)dismissPressed:(id)sender
{
    OWSLogDebug(@"tapped dismiss share button");

    [self cancelShareExperience];
}

- (void)cancelShareExperience
{
    [self.shareViewDelegate shareViewWasCancelled];
}

#pragma mark - ScreenLockViewDelegate

- (void)unlockButtonWasTapped
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"unlockButtonWasTapped");

    [self tryToPresentAuthUIToUnlockScreenLock];
}

@end

NS_ASSUME_NONNULL_END
