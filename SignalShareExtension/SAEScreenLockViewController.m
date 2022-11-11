//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SAEScreenLockViewController.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalUI/SignalUI-Swift.h>
#import <SignalUI/Theme.h>

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

    self.view.backgroundColor = Theme.launchScreenBackgroundColor;

    self.title = OWSLocalizedString(@"SHARE_EXTENSION_VIEW_TITLE", @"Title for the 'share extension' view.");

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(dismissPressed:)];
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

    [OWSScreenLock.shared
        tryToUnlockScreenLockWithSuccess:^{
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

            [self showScreenLockFailureAlertWithMessage:error.userErrorDescription];
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

    [OWSActionSheets showActionSheetWithTitle:OWSLocalizedString(@"SCREEN_LOCK_UNLOCK_FAILED",
                                                  @"Title for alert indicating that screen lock could not be unlocked.")
                                      message:message
                                  buttonTitle:nil
                                 buttonAction:^(ActionSheetAction *action) {
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
