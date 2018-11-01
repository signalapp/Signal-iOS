//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// This VC can become first responder
// when presented to ensure that the input accessory is updated.
@interface OWSWindowRootViewController : UIViewController

@end

#pragma mark -

extern NSString *const OWSWindowManagerCallDidChangeNotification;
const CGFloat OWSWindowManagerCallBannerHeight(void);

extern const UIWindowLevel UIWindowLevel_Background;

@interface OWSWindowManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initDefault NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

- (void)setupWithRootWindow:(UIWindow *)rootWindow screenBlockingWindow:(UIWindow *)screenBlockingWindow;

@property (nonatomic, readonly) UIWindow *rootWindow;

- (void)setIsScreenBlockActive:(BOOL)isScreenBlockActive;

#pragma mark - Message Actions

@property (nonatomic, readonly) BOOL isPresentingMenuActions;

- (void)showMenuActionsWindow:(UIViewController *)menuActionsViewController;
- (void)hideMenuActionsWindow;

#pragma mark - Calls

@property (nonatomic, readonly) BOOL shouldShowCallView;

- (void)startCall:(UIViewController *)callViewController;
- (void)endCall:(UIViewController *)callViewController;
- (void)leaveCallView;
- (BOOL)hasCall;

@end

NS_ASSUME_NONNULL_END
