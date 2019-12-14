//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSWindowManagerCallDidChangeNotification;

extern NSString *const IsScreenBlockActiveDidChangeNotification;

// This VC can become first responder
// when presented to ensure that the input accessory is updated.
@interface OWSWindowRootViewController : UIViewController

@end

#pragma mark -

const CGFloat OWSWindowManagerCallBannerHeight(void);

extern const UIWindowLevel UIWindowLevel_Background;

@interface OWSWindowManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initDefault NS_DESIGNATED_INITIALIZER;

@property (class, nonatomic, readonly, nonnull) OWSWindowManager *sharedManager;

- (void)setupWithRootWindow:(UIWindow *)rootWindow screenBlockingWindow:(UIWindow *)screenBlockingWindow;

@property (nonatomic, readonly) UIWindow *rootWindow;
@property (nonatomic) BOOL isScreenBlockActive;

- (BOOL)isAppWindow:(UIWindow *)window;

- (void)updateWindowFrames;
- (void)ensureReturnToCallWindowFrame;

#pragma mark - Calls

@property (nonatomic, readonly) BOOL shouldShowCallView;
@property (nonatomic, readonly) UIWindow *callViewWindow;

- (void)startCall:(UIViewController *)callViewController;
- (void)endCall:(UIViewController *)callViewController;
- (void)leaveCallView;
@property (nonatomic, readonly) BOOL hasCall;

@end

NS_ASSUME_NONNULL_END
