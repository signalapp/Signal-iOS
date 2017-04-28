//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class Contact;
@class ContactAccount;
@class OWSBlockingManager;
@class OWSContactsManager;

typedef void (^BlockActionCompletionBlock)(BOOL isBlocked);

@interface BlockListUIUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Block

// TODO: Still necessary?
+ (void)showBlockContactActionSheet:(Contact *)contact
                 fromViewController:(UIViewController *)fromViewController
                    blockingManager:(OWSBlockingManager *)blockingManager
                    contactsManager:(OWSContactsManager *)contactsManager
                    completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

// TODO: Still necessary?
+ (void)showBlockPhoneNumberActionSheet:(NSString *)phoneNumber
                     fromViewController:(UIViewController *)fromViewController
                        blockingManager:(OWSBlockingManager *)blockingManager
                        contactsManager:(OWSContactsManager *)contactsManager
                        completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showBlockContactAccountActionSheet:(ContactAccount *)contactAccount
                        fromViewController:(UIViewController *)fromViewController
                           blockingManager:(OWSBlockingManager *)blockingManager
                           contactsManager:(OWSContactsManager *)contactsManager
                           completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

#pragma mark - Unblock

// TODO: Still necessary?
+ (void)showUnblockContactActionSheet:(Contact *)contact
                   fromViewController:(UIViewController *)fromViewController
                      blockingManager:(OWSBlockingManager *)blockingManager
                      contactsManager:(OWSContactsManager *)contactsManager
                      completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

// TODO: Still necessary?
+ (void)showUnblockPhoneNumberActionSheet:(NSString *)phoneNumber
                       fromViewController:(UIViewController *)fromViewController
                          blockingManager:(OWSBlockingManager *)blockingManager
                          contactsManager:(OWSContactsManager *)contactsManager
                          completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showUnblockContactAccountActionSheet:(ContactAccount *)contactAccount
                          fromViewController:(UIViewController *)fromViewController
                             blockingManager:(OWSBlockingManager *)blockingManager
                             contactsManager:(OWSContactsManager *)contactsManager
                             completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

#pragma mark - UI Utils

+ (NSString *)formatDisplayNameForAlertTitle:(NSString *)displayName;
+ (NSString *)formatDisplayNameForAlertMessage:(NSString *)displayName;

@end

NS_ASSUME_NONNULL_END
