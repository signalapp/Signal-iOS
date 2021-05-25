//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class ConversationSplitViewController;
@class OnboardingController;
@class SignalServiceAddress;
@class TSThread;

@interface SignalApp : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)shared;

- (void)setup;

@property (nonatomic, readonly) BOOL hasSelectedThread;
@property (nonatomic, readonly) BOOL didLastLaunchNotTerminate;

#pragma mark - Conversation Presentation

- (void)showNewConversationView;

- (void)presentConversationForAddress:(SignalServiceAddress *)address animated:(BOOL)isAnimated;

- (void)presentConversationForAddress:(SignalServiceAddress *)address
                               action:(ConversationViewAction)action
                             animated:(BOOL)isAnimated;

- (void)presentConversationForThreadId:(NSString *)threadId animated:(BOOL)isAnimated;

- (void)presentConversationForThread:(TSThread *)thread animated:(BOOL)isAnimated;

- (void)presentConversationForThread:(TSThread *)thread action:(ConversationViewAction)action animated:(BOOL)isAnimated;

- (void)presentConversationForThread:(TSThread *)thread
                              action:(ConversationViewAction)action
                      focusMessageId:(nullable NSString *)focusMessageId
                            animated:(BOOL)isAnimated;

- (void)presentConversationAndScrollToFirstUnreadMessageForThreadId:(NSString *)threadId animated:(BOOL)isAnimated;

#pragma mark - Methods

+ (void)resetAppData;
+ (void)resetAppDataWithUI;

- (void)showOnboardingView:(OnboardingController *)onboardingController;
- (void)showConversationSplitView;
- (void)ensureRootViewController:(NSTimeInterval)launchStartedAt;
- (BOOL)receivedVerificationCode:(NSString *)verificationCode;
- (void)applicationWillTerminate;

- (nullable UIView *)snapshotSplitViewControllerAfterScreenUpdates:(BOOL)afterScreenUpdates;

// This property should be accessed by the Swift extension on this class.
@property (nonatomic, nullable) ConversationSplitViewController *conversationSplitViewControllerForSwift;

@end

NS_ASSUME_NONNULL_END
