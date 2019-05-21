//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SignalApp.h"
#import "AppDelegate.h"
#import "ConversationViewController.h"
#import "HomeViewController.h"
#import "Signal-Swift.h"
#import "SignalsNavigationController.h"
#import <SignalCoreKit/Threading.h>
#import <SignalMessaging/DebugLogger.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation SignalApp

+ (instancetype)sharedApp
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

    return self;
}

#pragma mark - Singletons

- (void)setup {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangeCallLoggingPreference:)
                                                 name:OWSPreferencesCallLoggingDidChangeNotification
                                               object:nil];
}

#pragma mark - View Convenience Methods

- (void)presentConversationForRecipientId:(NSString *)recipientId animated:(BOOL)isAnimated
{
    [self presentConversationForRecipientId:recipientId action:ConversationViewActionNone animated:(BOOL)isAnimated];
}

- (void)presentConversationForRecipientId:(NSString *)recipientId
                                   action:(ConversationViewAction)action
                                 animated:(BOOL)isAnimated
{
    __block TSThread *thread = nil;
    [OWSPrimaryStorage.dbReadWriteConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            thread = [TSContactThread getOrCreateThreadWithContactId:recipientId transaction:transaction];
        }];
    [self presentConversationForThread:thread action:action animated:(BOOL)isAnimated];
}

- (void)presentConversationForThreadId:(NSString *)threadId animated:(BOOL)isAnimated
{
    OWSAssertDebug(threadId.length > 0);

    TSThread *thread = [TSThread fetchObjectWithUniqueID:threadId];
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

    OWSLogInfo(@"");

    if (!thread) {
        OWSFailDebug(@"Can't present nil thread.");
        return;
    }

    DispatchMainThreadSafe(^{
        UIViewController *frontmostVC = [[UIApplication sharedApplication] frontmostViewController];
        
        if ([frontmostVC isKindOfClass:[ConversationViewController class]]) {
            ConversationViewController *conversationVC = (ConversationViewController *)frontmostVC;
            if ([conversationVC.thread.uniqueId isEqualToString:thread.uniqueId]) {
                [conversationVC popKeyBoard];
                return;
            }
        }
        
        [self.homeViewController presentThread:thread action:action focusMessageId:focusMessageId animated:isAnimated];
    });
}

- (void)presentConversationAndScrollToFirstUnreadMessageForThreadId:(NSString *)threadId animated:(BOOL)isAnimated
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(threadId.length > 0);

    OWSLogInfo(@"");

    TSThread *thread = [TSThread fetchObjectWithUniqueID:threadId];
    if (thread == nil) {
        OWSFailDebug(@"unable to find thread with id: %@", threadId);
        return;
    }

    DispatchMainThreadSafe(^{
        UIViewController *frontmostVC = [[UIApplication sharedApplication] frontmostViewController];

        if ([frontmostVC isKindOfClass:[ConversationViewController class]]) {
            ConversationViewController *conversationVC = (ConversationViewController *)frontmostVC;
            if ([conversationVC.thread.uniqueId isEqualToString:thread.uniqueId]) {
                [conversationVC scrollToFirstUnreadMessage:isAnimated];
                return;
            }
        }

        [self.homeViewController presentThread:thread
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

+ (void)resetAppData
{
    // This _should_ be wiped out below.
    OWSLogError(@"");
    [DDLog flushLog];

    [OWSStorage resetAllStorage];
    [OWSUserProfile resetProfileStorage];
    [Environment.shared.preferences clear];
    [AppEnvironment.shared.notificationPresenter clearAllNotifications];
    [OWSFileSystem deleteContentsOfDirectory:[OWSFileSystem appSharedDataDirectoryPath]];
    [OWSFileSystem deleteContentsOfDirectory:[OWSFileSystem appDocumentDirectoryPath]];
    [OWSFileSystem deleteContentsOfDirectory:[OWSFileSystem cachesDirectoryPath]];
    [OWSFileSystem deleteContentsOfDirectory:OWSTemporaryDirectory()];
    [OWSFileSystem deleteContentsOfDirectory:NSTemporaryDirectory()];

    [DebugLogger.sharedLogger wipeLogs];
    exit(0);
}

- (void)showHomeView
{
    HomeViewController *homeView = [HomeViewController new];
    SignalsNavigationController *navigationController =
        [[SignalsNavigationController alloc] initWithRootViewController:homeView];
    AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    appDelegate.window.rootViewController = navigationController;
    OWSAssertDebug([navigationController.topViewController isKindOfClass:[HomeViewController class]]);

    // Clear the signUpFlowNavigationController.
    [self setSignUpFlowNavigationController:nil];
}

@end

NS_ASSUME_NONNULL_END
