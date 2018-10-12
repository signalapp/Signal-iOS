//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@interface LockInteractionController : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initDefault NS_DESIGNATED_INITIALIZER;

typedef void (^LIControllerCompletionBlock)(void);
typedef BOOL (^LIControllerBlockingOperation)(void);
typedef void (^LIControllerRetryBlock)(
    LIControllerBlockingOperation operationBlock, LIControllerCompletionBlock completionBlock);

+ (void)performBlock:(LIControllerBlockingOperation)blockingOperation
     completionBlock:(LIControllerCompletionBlock)completionBlock
          retryBlock:(LIControllerRetryBlock)retryBlock
         usesNetwork:(BOOL)networkFlag;

+ (LIControllerRetryBlock)defaultNetworkRetry;

@end
