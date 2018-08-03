//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class Contact;
@class SignalAccount;
@class OWSBlockingManager;
@class OWSContactsManager;

typedef void (^BlockActionCompletionBlock)(BOOL isBlocked);

@interface BlockListUIUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Block

+ (void)showBlockPhoneNumberActionSheet:(NSString *)phoneNumber
                     fromViewController:(UIViewController *)fromViewController
                        blockingManager:(OWSBlockingManager *)blockingManager
                        contactsManager:(OWSContactsManager *)contactsManager
                        completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showBlockSignalAccountActionSheet:(SignalAccount *)signalAccount
                       fromViewController:(UIViewController *)fromViewController
                          blockingManager:(OWSBlockingManager *)blockingManager
                          contactsManager:(OWSContactsManager *)contactsManager
                          completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

#pragma mark - Unblock

+ (void)showUnblockPhoneNumberActionSheet:(NSString *)phoneNumber
                       fromViewController:(UIViewController *)fromViewController
                          blockingManager:(OWSBlockingManager *)blockingManager
                          contactsManager:(OWSContactsManager *)contactsManager
                          completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showUnblockSignalAccountActionSheet:(SignalAccount *)signalAccount
                         fromViewController:(UIViewController *)fromViewController
                            blockingManager:(OWSBlockingManager *)blockingManager
                            contactsManager:(OWSContactsManager *)contactsManager
                            completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

#pragma mark - UI Utils

+ (NSString *)formatDisplayNameForAlertTitle:(NSString *)displayName;
+ (NSString *)formatDisplayNameForAlertMessage:(NSString *)displayName;

@end

NS_ASSUME_NONNULL_END
