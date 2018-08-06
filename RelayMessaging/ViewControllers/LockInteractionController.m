//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "LockInteractionController.h"
#import <RelayServiceKit/AppContext.h>

@interface LockInteractionController ()

@property (nonatomic) UIAlertController *alertController;

@end

#pragma mark -

@implementation LockInteractionController

+ (instancetype)sharedController
{
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
        [CurrentAppContext() setNetworkActivityIndicatorVisible:networkFlag];
    }

    LockInteractionController *sharedController = [LockInteractionController sharedController];
    sharedController.alertController =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Upgrading Signal ...", nil)
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleAlert];

    [CurrentAppContext().frontmostViewController presentViewController:sharedController.alertController
                                                              animated:YES
                                                            completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = blockingOperation();

        dispatch_async(dispatch_get_main_queue(), ^{
            [sharedController.alertController
                dismissViewControllerAnimated:YES
                                   completion:^{
                                       if (networkFlag) {
                                           [CurrentAppContext() setNetworkActivityIndicatorVisible:NO];
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


+ (LIControllerRetryBlock)defaultNetworkRetry
{
    LIControllerRetryBlock retryBlock = ^void(
        LIControllerBlockingOperation blockingOperation, LIControllerCompletionBlock completionBlock) {
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

        [CurrentAppContext().frontmostViewController presentViewController:retryController animated:YES completion:nil];
    };

    return retryBlock;
}

@end
