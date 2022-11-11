//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IsScreenBlockActiveDidChangeNotification;

// This VC can become first responder
// when presented to ensure that the input accessory is updated.
@interface OWSWindowRootViewController : UIViewController

@end

#pragma mark -

extern const UIWindowLevel UIWindowLevel_Background;

@protocol CallViewControllerWindowReference;

@interface OWSWindowManager : NSObject

- (void)setupWithRootWindow:(UIWindow *)rootWindow screenBlockingWindow:(UIWindow *)screenBlockingWindow;

@property (nonatomic, readonly) UIWindow *rootWindow;
@property (nonatomic) BOOL isScreenBlockActive;

- (BOOL)isAppWindow:(UIWindow *)window;

- (void)updateWindowFrames;

#pragma mark - Calls

@property (nonatomic, readonly) BOOL shouldShowCallView;
@property (nonatomic, readonly) UIWindow *callViewWindow;

- (void)startCall:(UIViewController<CallViewControllerWindowReference> *)callViewController;
- (void)endCall:(UIViewController<CallViewControllerWindowReference> *)callViewController;
- (void)leaveCallView;
- (void)returnToCallView;
@property (nonatomic, readonly) BOOL hasCall;

@end

NS_ASSUME_NONNULL_END
