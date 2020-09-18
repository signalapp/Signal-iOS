//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSScreenLockUI : NSObject

@property (nonatomic, readonly) UIWindow *screenBlockingWindow;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)shared;

- (void)setupWithRootWindow:(UIWindow *)rootWindow;

- (void)startObserving;

@end

NS_ASSUME_NONNULL_END
