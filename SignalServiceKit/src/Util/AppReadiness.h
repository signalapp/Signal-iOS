//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^AppReadyBlock)(void);

@interface AppReadiness : NSObject

- (instancetype)init NS_UNAVAILABLE;

// This method can be called on any thread.
+ (BOOL)isAppReady;

// This method should only be called on the main thread.
+ (void)setAppIsReady;

// If the app is ready, the block is called immediately;
// otherwise it is called when the app becomes ready.
//
// This method should only be called on the main thread.
// The block will always be called on the main thread.
//
// * The "will become ready" blocks are called before the "did become ready" blocks.
// * The "will become ready" blocks should be used for internal setup of components
//   so that they are ready to interact with other components of the system.
// * The "did become ready" blocks should be used for any work that should be done
//   on app launch, especially work that uses other components.
// * We should usually use "did become ready" blocks since they are safer.
+ (void)runNowOrWhenAppWillBecomeReady:(AppReadyBlock)block NS_SWIFT_NAME(runNowOrWhenAppWillBecomeReady(_:));
+ (void)runNowOrWhenAppDidBecomeReady:(AppReadyBlock)block NS_SWIFT_NAME(runNowOrWhenAppDidBecomeReady(_:));

@end

NS_ASSUME_NONNULL_END
