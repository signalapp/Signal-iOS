//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SignalApp.h"
#import "AppDelegate.h"
#import "ConversationViewController.h"
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

#pragma mark - View Convenience Methods

- (void)presentConversationForAddress:(SignalServiceAddress *)address animated:(BOOL)isAnimated
{
    [self presentConversationForAddress:address action:ConversationViewActionNone animated:(BOOL)isAnimated];
}

- (void)presentConversationForAddress:(SignalServiceAddress *)address
                               action:(ConversationViewAction)action
                             animated:(BOOL)isAnimated
{
    __block TSThread *thread = nil;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        thread = [TSContactThread getOrCreateThreadWithContactAddress:address transaction:transaction];
    });
    [self presentConversationForThread:thread action:action animated:(BOOL)isAnimated];
}

- (void)presentConversationForThreadId:(NSString *)threadId animated:(BOOL)isAnimated
{
    OWSAssertDebug(threadId.length > 0);

    __block TSThread *_Nullable thread;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        thread = [TSThread anyFetchWithUniqueId:threadId transaction:transaction];
    }];
    if (thread == nil) {
        OWSFailDebug(@"unable to find thread with id: %@", threadId);
        return;
    }

    [self presentConversationForThread:thread animated:isAnimated];
}

- (void)presentConversationForThread:(TSThread *)thread animated:(BOOL)isAnimated
{
    [self presentConversationForThread:thread action:ConversationViewActionNone animated:isAnimated];
}

- (void)presentConversationForThread:(TSThread *)thread action:(ConversationViewAction)action animated:(BOOL)isAnimated
{
    [self presentConversationForThread:thread action:action focusMessageId:nil animated:isAnimated];
}

- (void)presentConversationForThread:(TSThread *)thread
                              action:(ConversationViewAction)action
                      focusMessageId:(nullable NSString *)focusMessageId
                            animated:(BOOL)isAnimated
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.conversationSplitViewController);

    OWSLogInfo(@"");

    if (!thread) {
        OWSFailDebug(@"Can't present nil thread.");
        return;
    }

    DispatchMainThreadSafe(^{
        if (self.conversationSplitViewController.visibleThread) {
            if ([self.conversationSplitViewController.visibleThread.uniqueId isEqualToString:thread.uniqueId]) {
                ConversationViewController *conversationView
                    = self.conversationSplitViewController.selectedConversationViewController;
                [conversationView popKeyBoard];
                if (action == ConversationViewActionUpdateDraft) {
                    [conversationView reloadDraft];
                }
                return;
            }
        }

        [self.conversationSplitViewController presentThread:thread
                                                     action:action
                                             focusMessageId:focusMessageId
                                                   animated:isAnimated];
    });
}

- (void)presentConversationAndScrollToFirstUnreadMessageForThreadId:(NSString *)threadId animated:(BOOL)isAnimated
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(threadId.length > 0);
    OWSAssertDebug(self.conversationSplitViewController);

    OWSLogInfo(@"");

    __block TSThread *_Nullable thread;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        thread = [TSThread anyFetchWithUniqueId:threadId transaction:transaction];
    }];
    if (thread == nil) {
        OWSFailDebug(@"unable to find thread with id: %@", threadId);
        return;
    }

    DispatchMainThreadSafe(^{
        // If there's a presented blocking splash, but the user is trying to open a thread,
        // dismiss it. We'll try again next time they open the app. We don't want to block
        // them from accessing their conversations.
        [ExperienceUpgradeManager dismissSplashWithoutCompletingIfNecessary];

        if (self.conversationSplitViewController.visibleThread) {
            if ([self.conversationSplitViewController.visibleThread.uniqueId isEqualToString:thread.uniqueId]) {
                [self.conversationSplitViewController.selectedConversationViewController
                    scrollToInitialPositionAnimated:isAnimated];
                return;
            }
        }

        [self.conversationSplitViewController presentThread:thread
                                                     action:ConversationViewActionNone
                                             focusMessageId:nil
                                                   animated:isAnimated];
    });
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
