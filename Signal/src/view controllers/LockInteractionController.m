//
//  LockInteractionController.m
//  Signal
//
//  Created by Frederic Jacobs on 22/08/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "LockInteractionController.h"

@interface LockInteractionController ()
@property UIAlertController *alertController;
@end

@implementation LockInteractionController

+ (instancetype)sharedController {
    static LockInteractionController *sharedController = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedController = [self new];
    });
    return sharedController;
}

+ (void)performBlock:(LIControllerBlockingOperation)blockingOperation
     completionBlock:(LIControllerCompletionBlock)completionBlock
          retryBlock:(LIControllerRetryBlock)retryBlock
         usesNetwork:(BOOL)networkFlag

{
    if (networkFlag) {
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:networkFlag];
    }

    LockInteractionController *sharedController = [LockInteractionController sharedController];
    sharedController.alertController =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Upgrading Signal ...", nil)
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleAlert];

    [[UIApplication sharedApplication]
            .keyWindow.rootViewController presentViewController:sharedController.alertController
                                                       animated:YES
                                                     completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      BOOL success = blockingOperation();

      dispatch_async(dispatch_get_main_queue(), ^{
        [sharedController.alertController
            dismissViewControllerAnimated:YES
                               completion:^{
                                 if (networkFlag) {
                                     [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                                 }

                                 if (!success) {
                                     retryBlock(blockingOperation, completionBlock);
                                 } else {
                                     completionBlock();
                                 }
                               }];
      });

    });
}


+ (LIControllerRetryBlock)defaultNetworkRetry {
    LIControllerRetryBlock retryBlock =
        ^void(LIControllerBlockingOperation blockingOperation, LIControllerCompletionBlock completionBlock) {
          UIAlertController *retryController =
              [UIAlertController alertControllerWithTitle:@"Upgrading Signal failed"
                                                  message:@"An network error occured while upgrading, please check "
                                                          @"your connectivity and try again."
                                           preferredStyle:UIAlertControllerStyleAlert];

          [retryController
              addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"REGISTER_FAILED_TRY_AGAIN", nil)
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
                                                 [self performBlock:blockingOperation
                                                     completionBlock:completionBlock
                                                          retryBlock:[LockInteractionController defaultNetworkRetry]
                                                         usesNetwork:YES];
                                               }]];

          [[UIApplication sharedApplication]
                  .keyWindow.rootViewController presentViewController:retryController
                                                             animated:YES
                                                           completion:nil];
        };

    return retryBlock;
}

@end
