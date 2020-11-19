//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSWindowManagerCallDidChangeNotification;

extern NSString *const IsScreenBlockActiveDidChangeNotification;

// This VC can become first responder
// when presented to ensure that the input accessory is updated.
@interface OWSWindowRootViewController : UIViewController

@end

#pragma mark -

extern const UIWindowLevel UIWindowLevel_Background;

@protocol CallViewControllerWindowReference;

@interface OWSWindowManager : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initDefault NS_DESIGNATED_INITIALIZER;

@property (class, nonatomic, readonly, nonnull) OWSWindowManager *shared;

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
