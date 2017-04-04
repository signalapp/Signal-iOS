//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@class Contact;
@class OWSBlockingManager;
@class OWSContactsManager;

typedef void (^BlockActionCompletionBlock)(BOOL isBlocked);

@interface BlockListUIUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (void)showBlockContactActionSheet:(Contact *)contact
                 fromViewController:(UIViewController *)fromViewController
                    blockingManager:(OWSBlockingManager *)blockingManager
                    contactsManager:(OWSContactsManager *)contactsManager
                    completionBlock:(BlockActionCompletionBlock)completionBlock;

+ (void)showBlockPhoneNumberActionSheet:(NSString *)phoneNumber
                     fromViewController:(UIViewController *)fromViewController
                        blockingManager:(OWSBlockingManager *)blockingManager
                        contactsManager:(OWSContactsManager *)contactsManager
                        completionBlock:(BlockActionCompletionBlock)completionBlock;

+ (void)showUnblockPhoneNumberActionSheet:(NSString *)phoneNumber
                       fromViewController:(UIViewController *)fromViewController
                          blockingManager:(OWSBlockingManager *)blockingManager
                          contactsManager:(OWSContactsManager *)contactsManager
                          completionBlock:(BlockActionCompletionBlock)completionBlock;

@end
