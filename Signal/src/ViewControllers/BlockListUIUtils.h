//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@class Contact;
@class OWSBlockingManager;

typedef void (^BlockActionCompletionBlock)(BOOL isBlocked);

@interface BlockListUIUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (void)showBlockContactActionSheet:(Contact *)contact
                 fromViewController:(UIViewController *)fromViewController
                    blockingManager:(OWSBlockingManager *)blockingManager
                    completionBlock:(BlockActionCompletionBlock)completionBlock;

+ (void)showBlockPhoneNumberActionSheet:(NSString *)phoneNumber
                            displayName:(NSString *)displayName
                     fromViewController:(UIViewController *)fromViewController
                        blockingManager:(OWSBlockingManager *)blockingManager
                        completionBlock:(BlockActionCompletionBlock)completionBlock;

+ (void)showUnblockPhoneNumberActionSheet:(NSString *)phoneNumber
                              displayName:(NSString *)displayName
                       fromViewController:(UIViewController *)fromViewController
                          blockingManager:(OWSBlockingManager *)blockingManager
                          completionBlock:(BlockActionCompletionBlock)completionBlock;

@end
