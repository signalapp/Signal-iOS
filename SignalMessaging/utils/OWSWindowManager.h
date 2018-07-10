//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class MessageActionsViewController;

// This VC can become first responder
// when presented to ensure that the input accessory is updated.
@interface OWSWindowRootViewController : UIViewController

@end

#pragma mark -

@protocol MessageActionsDelegate

- (void)dismissMessageActions:(MessageActionsViewController *)messageActionsViewController;

@end

#pragma mark -

extern NSString *const OWSWindowManagerCallDidChangeNotification;
const CGFloat OWSWindowManagerCallScreenHeight(void);

extern const UIWindowLevel UIWindowLevel_Background;

@interface OWSWindowManager : NSObject <MessageActionsDelegate>

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (void)setupWithRootWindow:(UIWindow *)rootWindow screenBlockingWindow:(UIWindow *)screenBlockingWindow;

- (void)setIsScreenBlockActive:(BOOL)isScreenBlockActive;

#pragma mark - Message Actions

- (void)presentMessageActions:(MessageActionsViewController *)messageActionsViewController;

#pragma mark - Calls

@property (nonatomic, readonly) BOOL shouldShowCallView;

- (void)startCall:(UIViewController *)callViewController;
- (void)endCall:(UIViewController *)callViewController;
- (void)leaveCallView;
- (BOOL)hasCall;

@end

NS_ASSUME_NONNULL_END
