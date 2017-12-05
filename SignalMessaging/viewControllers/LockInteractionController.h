//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface LockInteractionController : NSObject

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
