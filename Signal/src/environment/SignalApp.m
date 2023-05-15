//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SignalApp.h"
#import "AppDelegate.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/Threading.h>
#import <SignalMessaging/DebugLogger.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSUserDefaults_DidTerminateKey = @"kNSUserDefaults_DidTerminateKey";

#pragma mark -

@implementation SignalApp

+ (instancetype)shared
{
    static SignalApp *sharedApp = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedApp = [[self alloc] initDefault];
    });
    return sharedApp;
}

- (instancetype)initDefault
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    AppReadinessRunNowOrWhenUIDidBecomeReadySync(^{ [self warmCachesAsync]; });

    return self;
}

#pragma mark -

- (void)setup {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangeCallLoggingPreference:)
                                                 name:OWSPreferencesCallLoggingDidChangeNotification
                                               object:nil];
}

- (BOOL)hasSelectedThread
{
    return self.conversationSplitViewController.selectedThread != nil;
}


- (void)didChangeCallLoggingPreference:(NSNotification *)notification
{
    [AppEnvironment.shared.callService createCallUIAdapter];
}

#pragma mark - Methods

+ (void)resetAppDataWithUI
{
    OWSLogInfo(@"");

    DispatchMainThreadSafe(^{
        UIViewController *fromVC = UIApplication.sharedApplication.frontmostViewController;
        [ModalActivityIndicatorViewController
            presentFromViewController:fromVC
                            canCancel:YES
                      backgroundBlock:^(
                          ModalActivityIndicatorViewController *modalActivityIndicator) { [SignalApp resetAppData]; }];
    });
}

+ (void)resetAppData
{
    // This _should_ be wiped out below.
    OWSLogInfo(@"");
    OWSLogFlush();

    DispatchSyncMainThreadSafe(^{
        [self.databaseStorage resetAllStorage];
        [OWSUserProfile resetProfileStorage];
        [Environment.shared.preferences removeAllValues];
        [AppEnvironment.shared.notificationPresenter clearAllNotifications];
        [OWSFileSystem deleteContentsOfDirectory:[OWSFileSystem appSharedDataDirectoryPath]];
        [OWSFileSystem deleteContentsOfDirectory:[OWSFileSystem appDocumentDirectoryPath]];
        [OWSFileSystem deleteContentsOfDirectory:[OWSFileSystem cachesDirectoryPath]];
        [OWSFileSystem deleteContentsOfDirectory:OWSTemporaryDirectory()];
        [OWSFileSystem deleteContentsOfDirectory:NSTemporaryDirectory()];
        [AppDelegate updateApplicationShortcutItemsWithIsRegisteredAndReady:NO];
    });

    [DebugLogger.shared wipeLogsAlwaysWithAppContext:(MainAppContext *)CurrentAppContext()];
    exit(0);
}

- (void)showConversationSplitView
{
    ConversationSplitViewController *splitViewController = [ConversationSplitViewController new];

    AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    appDelegate.window.rootViewController = splitViewController;

    self.conversationSplitViewController = splitViewController;
}

- (void)showDeprecatedOnboardingView:(Deprecated_OnboardingController *)onboardingController
{
    Deprecated_OnboardingNavigationController *navController =
        [[Deprecated_OnboardingNavigationController alloc] initWithOnboardingController:onboardingController];

    UITapGestureRecognizer *submitLogGesture =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(submitOnboardingLogs)];
    submitLogGesture.numberOfTapsRequired = 8;
    submitLogGesture.delaysTouchesEnded = NO;
    [navController.view addGestureRecognizer:submitLogGesture];

    AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    appDelegate.window.rootViewController = navController;

    self.conversationSplitViewController = nil;
}

- (void)submitOnboardingLogs
{
    [DebugLogs submitLogsWithSupportTag:@"Onboarding" completion:nil];
}

- (void)showNewConversationView
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.conversationSplitViewController);

    [self.conversationSplitViewController showNewConversationView];
}

- (nullable UIView *)snapshotSplitViewControllerAfterScreenUpdates:(BOOL)afterScreenUpdates
{
    return [self.conversationSplitViewController.view snapshotViewAfterScreenUpdates:afterScreenUpdates];
}

- (nullable ConversationSplitViewController *)conversationSplitViewControllerForSwift
{
    return self.conversationSplitViewController;
}

@end

NS_ASSUME_NONNULL_END
