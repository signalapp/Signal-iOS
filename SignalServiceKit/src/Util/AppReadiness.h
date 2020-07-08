//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^AppReadyBlock)(void);

@interface AppReadiness : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// This property can be accessed on any thread.
@property (class, readonly) BOOL isAppReady;

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
// * The "will become ready" blocks should never use other components of the system.
//
// * The "did become ready" blocks should be used for any work that should be done
//   on app launch, especially work that uses other components.
// * We should usually use "did become ready" blocks since they are safer.
//
// * We should use the "polite" flavor of "did become ready" blocks when the work
//   can be safely delayed for a second or two after the app becomes ready.
// * We should use the "polite" flavor of "did become ready" blocks wherever possible
//   since they avoid a stampede of activity on launch.
+ (void)runNowOrWhenAppWillBecomeReady:(AppReadyBlock)block NS_SWIFT_NAME(runNowOrWhenAppWillBecomeReady(_:));
+ (void)runNowOrWhenAppDidBecomeReady:(AppReadyBlock)block NS_SWIFT_NAME(runNowOrWhenAppDidBecomeReady(_:));
+ (void)runNowOrWhenAppDidBecomeReadyPolite:(AppReadyBlock)block NS_SWIFT_NAME(runNowOrWhenAppDidBecomeReadyPolite(_:));

@end

NS_ASSUME_NONNULL_END
