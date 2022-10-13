//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class Contact;
@class SignalAccount;
@class SignalServiceAddress;
@class TSGroupModel;
@class TSThread;

typedef void (^BlockActionCompletionBlock)(BOOL isBlocked);

@interface BlockListUIUtils : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Block

+ (void)showBlockThreadActionSheet:(TSThread *)thread
                fromViewController:(UIViewController *)fromViewController
                   completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showBlockAddressActionSheet:(SignalServiceAddress *)address
                 fromViewController:(UIViewController *)fromViewController
                    completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showBlockSignalAccountActionSheet:(SignalAccount *)signalAccount
                       fromViewController:(UIViewController *)fromViewController
                          completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

#pragma mark - Unblock

+ (void)showUnblockThreadActionSheet:(TSThread *)thread
                  fromViewController:(UIViewController *)fromViewController
                     completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showUnblockAddressActionSheet:(SignalServiceAddress *)address
                   fromViewController:(UIViewController *)fromViewController
                      completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showUnblockSignalAccountActionSheet:(SignalAccount *)signalAccount
                         fromViewController:(UIViewController *)fromViewController
                            completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showUnblockGroupActionSheet:(TSGroupModel *)groupModel
                 fromViewController:(UIViewController *)fromViewController
                    completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

#pragma mark - UI Utils

+ (NSString *)formatDisplayNameForAlertTitle:(NSString *)displayName;
+ (NSString *)formatDisplayNameForAlertMessage:(NSString *)displayName;

@end

NS_ASSUME_NONNULL_END
