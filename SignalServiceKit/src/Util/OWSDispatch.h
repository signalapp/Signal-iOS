//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSDispatch : NSObject

@property (class, strong, nonatomic, readonly) dispatch_queue_t sharedUserInteractive;
@property (class, strong, nonatomic, readonly) dispatch_queue_t sharedUserInitiated;
@property (class, strong, nonatomic, readonly) dispatch_queue_t sharedUtility;
@property (class, strong, nonatomic, readonly) dispatch_queue_t sharedBackground;

@end

NS_ASSUME_NONNULL_END
