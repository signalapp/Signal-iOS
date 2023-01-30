//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

// This public property is only needed for Swift bridging.
@property (nonatomic) BOOL hasInitialRootViewController;

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
- (void)applicationWillTerminate;

- (nullable UIView *)snapshotSplitViewControllerAfterScreenUpdates:(BOOL)afterScreenUpdates;

// This property should be accessed by the Swift extension on this class.
@property (nonatomic, nullable) ConversationSplitViewController *conversationSplitViewControllerForSwift;

@end

NS_ASSUME_NONNULL_END
