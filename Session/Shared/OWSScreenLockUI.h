//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSScreenLockUI : NSObject

@property (nonatomic, readonly) UIWindow *screenBlockingWindow;

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (void)setupWithRootWindow:(UIWindow *)rootWindow;

- (void)startObserving;

@end

NS_ASSUME_NONNULL_END
