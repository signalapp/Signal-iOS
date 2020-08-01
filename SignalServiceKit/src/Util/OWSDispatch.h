//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSDispatch : NSObject

@property (class, strong, nonatomic, readonly) dispatch_queue_t sharedUserInteractive;
@property (class, strong, nonatomic, readonly) dispatch_queue_t sharedUserInitiated;
@property (class, strong, nonatomic, readonly) dispatch_queue_t sharedUtility;
@property (class, strong, nonatomic, readonly) dispatch_queue_t sharedBackground;

@end

NS_ASSUME_NONNULL_END
