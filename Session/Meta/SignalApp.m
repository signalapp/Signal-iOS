//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SignalApp.h"
#import "AppDelegate.h"
#import "Session-Swift.h"
#import <SignalCoreKit/Threading.h>
#import <SessionMessagingKit/Environment.h>
#import <SessionMessagingKit/OWSPrimaryStorage.h>
#import <SessionMessagingKit/TSContactThread.h>
#import <SessionMessagingKit/TSGroupThread.h>

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
    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        thread = [TSContactThread getOrCreateThreadWithContactSessionID:recipientId transaction:transaction];
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
        [self.homeViewController show:thread with:action highlightedMessageID:focusMessageId animated:isAnimated];
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
        [self.homeViewController show:thread with:ConversationViewActionNone highlightedMessageID:nil animated:isAnimated];
    });
}

- (void)didChangeCallLoggingPreference:(NSNotification *)notitication
{
//    [AppEnvironment.shared.callService createCallUIAdapter];
}

#pragma mark - Methods

+ (void)resetAppData
{
    [self resetAppData:nil];
}

+ (void)resetAppData:(void (^__nullable)(void))onReset {
    // This _should_ be wiped out below.
    OWSLogError(@"");
    [DDLog flushLog];

    [OWSStorage resetAllStorage];
    [OWSUserProfile resetProfileStorage];
    [Environment.shared.preferences clear];
    [AppEnvironment.shared.notificationPresenter clearAllNotifications];

    if (onReset != nil) { onReset(); }
    exit(0);
}

- (void)showHomeView
{
    HomeVC *homeView = [HomeVC new];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:homeView];
    AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    appDelegate.window.rootViewController = navigationController;
    OWSAssertDebug([navigationController.topViewController isKindOfClass:[HomeVC class]]);

    // Clear the signUpFlowNavigationController.
    [self setSignUpFlowNavigationController:nil];
}

@end

NS_ASSUME_NONNULL_END
