//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationSplitViewController;
@class Deprecated_OnboardingController;
@class SignalServiceAddress;
@class TSThread;

@interface SignalApp : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)shared;

- (void)setup;

@property (nonatomic, readonly) BOOL hasSelectedThread;

// These properties are only public for Swift bridging.
@property (nonatomic, nullable, weak) ConversationSplitViewController *conversationSplitViewController;

#pragma mark - Conversation Presentation

- (void)showNewConversationView;

#pragma mark - Methods

+ (void)resetAppData;
+ (void)resetAppDataWithUI;

- (void)showDeprecatedOnboardingView:(Deprecated_OnboardingController *)onboardingController;
- (void)showConversationSplitView;

- (nullable UIView *)snapshotSplitViewControllerAfterScreenUpdates:(BOOL)afterScreenUpdates;

// This property should be accessed by the Swift extension on this class.
@property (nonatomic, nullable) ConversationSplitViewController *conversationSplitViewControllerForSwift;

@end

NS_ASSUME_NONNULL_END
